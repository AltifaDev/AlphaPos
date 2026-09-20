// OrderTimelineView.swift
// AlphaPosStaff — Visual Order Status Timeline
// แสดง timeline แนวตั้งของ order status (Placed → Confirmed → Preparing → Ready → Served)

import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Timeline Step Model
// ─────────────────────────────────────────────────────────────────────────────

enum TimelineStepStatus {
    case completed
    case current
    case pending
}

struct TimelineStep: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let timestamp: Date?
    let status: TimelineStepStatus
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - OrderTimelineView
// ─────────────────────────────────────────────────────────────────────────────

struct OrderTimelineView: View {
    let initialOrder: Order
    @State private var order: Order
    @AppStorage("app_language") private var appLanguage = "en"
    @Environment(\.dismiss) private var dismiss
    
    @State private var pulseAnimation = false
    @State private var elapsedTimer: Timer? = nil
    @State private var pollTimer: Timer? = nil
    @State private var isRefreshing = false
    @State private var now = Date()

    /// Realtime is the primary update path. Polling is only a low-frequency
    /// recovery path for a dropped websocket event or temporary reconnect.
    private let fallbackPollingInterval: TimeInterval = 12
    
    // Average estimated prep time (in minutes) — can be adjusted per-restaurant
    private let estimatedPrepMinutes: Double = 15
    
    init(order: Order) {
        self.initialOrder = order
        _order = State(initialValue: order)
    }
    
    private var orderCreatedDate: Date? {
        parseISO8601(order.createdAt)
    }
    
    private var steps: [TimelineStep] {
        buildSteps(for: order)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 0) {
                        // Order header card
                        orderHeaderCard
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                        
                        // Estimated time (if still in progress)
                        if isInProgress {
                            estimatedTimeCard
                                .padding(.horizontal, 16)
                                .padding(.top, 12)
                        } else if order.isPaid {
                            paymentCompletedCard
                                .padding(.horizontal, 16)
                                .padding(.top, 12)
                        }
                        
                        // Timeline
                        timelineSection
                            .padding(.horizontal, 16)
                            .padding(.top, 20)
                        
                        // Order items summary
                        orderItemsCard
                            .padding(.horizontal, 16)
                            .padding(.top, 20)
                            .padding(.bottom, 40)
                    }
                }
                .refreshable {
                    await refreshOrder()
                }
            }
            .navigationTitle("order_timeline".localized(for: appLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await refreshOrder() }
                    } label: {
                        if isRefreshing {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.appAccent)
                        }
                    }
                    .disabled(isRefreshing)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.textTertiary)
                    }
                }
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    pulseAnimation = true
                }
                // Update elapsed time every second
                elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                    now = Date()
                }
                startFallbackPollingIfNeeded()
                Task { await refreshOrder() }
            }
            .onDisappear {
                elapsedTimer?.invalidate()
                elapsedTimer = nil
                pollTimer?.invalidate()
                pollTimer = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("StaffOrderUpdated"))) { note in
                if let updated = note.object as? Order, updated.id == order.id {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        self.order = updated
                    }
                    reconcileFallbackPolling()
                }
            }
        }
    }
    
    private func refreshOrder() async {
        guard !order.id.isEmpty else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            if let updated = try await NetworkService.shared.fetchOrderById(order.id) {
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        self.order = updated
                    }
                    reconcileFallbackPolling()
                }
            }
        } catch {
            #if DEBUG
            print("OrderTimelineView refresh failed: \(error)")
            #endif
        }
    }

    /// Keep the fallback alive only while kitchen fulfilment can still change.
    /// A paid order may remain active, so payment/order `completed` alone must
    /// not stop polling; item fulfilment is the source of truth.
    private var needsFallbackPolling: Bool {
        if order.status.lowercased() == "cancelled" { return false }
        let activeItems = order.items.filter { $0.status.lowercased() != "cancelled" }
        guard !activeItems.isEmpty else { return true }
        return !activeItems.allSatisfy { $0.status.lowercased() == "served" }
    }

    private func startFallbackPollingIfNeeded() {
        guard needsFallbackPolling, pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: fallbackPollingInterval, repeats: true) { _ in
            Task { await refreshOrder() }
        }
    }

    private func reconcileFallbackPolling() {
        if needsFallbackPolling {
            startFallbackPollingIfNeeded()
        } else {
            pollTimer?.invalidate()
            pollTimer = nil
        }
    }
    
    // MARK: - Order Header Card
    
    private var orderHeaderCard: some View {
        VStack(spacing: 12) {
            HStack {
                // Order number
                VStack(alignment: .leading, spacing: 4) {
                    Text(order.orderNumber)
                        .font(.system(size: 18, weight: .black, design: .monospaced))
                        .foregroundColor(.textPrimary)
                    Text(order.isQuickOrder ? "quick_order".localized(for: appLanguage) : "Table \(order.tableNumber)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.textSecondary)
                    if let queue = order.queueNumber, !queue.isEmpty {
                        HStack(spacing: 4) {
                            Text("\("queue_number".localized(for: appLanguage))")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(Color(hex: "4B5563"))
                            Text(queue.replacingOccurrences(of: "#", with: ""))
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(.textPrimary)
                        }
                    }
                    if let receipt = order.receiptNumber, !receipt.isEmpty {
                        Text(receipt)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.textTertiary)
                    }
                    if let brand = order.deliveryBrand, !brand.isEmpty {
                        Text(brand)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.appTeal)
                    }
                    if let platform = order.platformOrderNumber, !platform.isEmpty {
                        Text("\("platform_order_label".localized(for: appLanguage)): \(platform)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(.textSecondary)
                    }
                }
                
                Spacer()
                
                // Status badge & Payment badge
                VStack(alignment: .trailing, spacing: 6) {
                    // The order-level `completed` value is financial for paid
                    // Staff Quick Orders. Show kitchen fulfilment separately so
                    // a paid ticket with cooking items is not labelled finished.
                    OrderStatusBadge(status: fulfillmentStatus, size: .large)
                    
                    if order.isPaid {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 11, weight: .bold))
                            Text("filter_paid".localized(for: appLanguage))
                                .font(.system(size: 11, weight: .bold))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.appGreen.opacity(0.15))
                        .foregroundColor(.appGreen)
                        .cornerRadius(6)
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "clock.badge.exclamationmark")
                                .font(.system(size: 11, weight: .bold))
                            Text("filter_unpaid".localized(for: appLanguage))
                                .font(.system(size: 11, weight: .bold))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.appAmber.opacity(0.15))
                        .foregroundColor(.appAmber)
                        .cornerRadius(6)
                    }
                }
            }
            
            Divider().background(Color.appDivider)
            
            // Total & time
            HStack {
                Label(formatDateTime(order.createdAt), systemImage: "clock")
                    .font(.system(size: 12))
                    .foregroundColor(.textSecondary)
                Spacer()
                Text("฿\(String(format: "%.2f", order.total))")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.appAccent)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: APRadius.lg, style: .continuous)
                .fill(Color.appSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: APRadius.lg, style: .continuous)
                        .stroke(Color.appBorderSubtle, lineWidth: 1)
                )
        )
    }
    
    // MARK: - Estimated Time Card
    
    private var estimatedTimeCard: some View {
        HStack(spacing: 12) {
            // Animated clock
            ZStack {
                Circle()
                    .fill(Color.appAccent.opacity(0.1))
                    .frame(width: 44, height: 44)
                Image(systemName: "timer")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.appAccent)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text("estimated_time".localized(for: appLanguage))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.textSecondary)
                Text(estimatedRemainingText)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.textPrimary)
            }
            
            Spacer()
            
            // Elapsed
            VStack(alignment: .trailing, spacing: 3) {
                Text("elapsed_time".localized(for: appLanguage))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.textSecondary)
                Text(elapsedText)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.appAmber)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: APRadius.md, style: .continuous)
                .fill(Color.appAccent.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: APRadius.md, style: .continuous)
                        .stroke(Color.appAccent.opacity(0.15), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Payment Completed Card
    
    private var paymentCompletedCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.appGreen.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.appGreen)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text("payment_completed_banner".localized(for: appLanguage))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.appGreen)
                if let payment = order.payments.first(where: { $0.status.lowercased() == "completed" }) {
                    Text("\(payment.method) · ฿\(String(format: "%.2f", payment.amount))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.textSecondary)
                } else {
                    Text("฿\(String(format: "%.2f", order.total))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.textSecondary)
                }
            }
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: APRadius.md, style: .continuous)
                .fill(Color.appGreen.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: APRadius.md, style: .continuous)
                        .stroke(Color.appGreen.opacity(0.25), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Timeline Section
    
    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                timelineRow(step: step, isLast: index == steps.count - 1, index: index)
            }
        }
    }
    

    
    private func timelineRow(step: TimelineStep, isLast: Bool, index: Int) -> some View {
        HStack(alignment: .top, spacing: 16) {
            // Left: icon + connector line
            VStack(spacing: 0) {
                // Icon circle
                ZStack {
                    Circle()
                        .fill(circleColor(for: step.status).opacity(step.status == .current ? 0.2 : 0.12))
                        .frame(width: 40, height: 40)
                        .scaleEffect(step.status == .current && pulseAnimation ? 1.2 : 1.0)
                        .opacity(step.status == .current && pulseAnimation ? 0.6 : 1.0)
                    
                    Circle()
                        .fill(circleColor(for: step.status))
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: step.icon)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                }
                
                // Connector line
                if !isLast {
                    Rectangle()
                        .fill(
                            step.status == .completed
                                ? Color.appGreen.opacity(0.6)
                                : Color.appDivider.opacity(0.4)
                        )
                        .frame(width: 2.5, height: 50)
                }
            }
            
            // Right: title + timestamp + elapsed between steps
            VStack(alignment: .leading, spacing: 4) {
                Text(step.title)
                    .font(.system(size: 15, weight: step.status == .current ? .bold : .semibold))
                    .foregroundColor(step.status == .pending ? .textTertiary : .textPrimary)
                
                if let ts = step.timestamp {
                    Text(formatTime(ts))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.textSecondary)
                    
                    // Show elapsed since previous step
                    if index > 0, let prevTs = steps[index - 1].timestamp {
                        let elapsed = ts.timeIntervalSince(prevTs)
                        if elapsed > 0 {
                            Text("+ \(formatDuration(elapsed))")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.appAccent)
                                .padding(.top, 2)
                        }
                    }
                } else if step.status == .current {
                    // Waiting indicator
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.6)
                            .tint(.appAccent)
                        Text("In progress...")
                            .font(.system(size: 11))
                            .foregroundColor(.appAccent)
                    }
                } else {
                    Text("—")
                        .font(.system(size: 12))
                        .foregroundColor(.textTertiary)
                }
            }
            .padding(.top, 6)
            
            Spacer()
        }
    }
    
    // MARK: - Order Items Card
    
    private var orderItemsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("items_label".localized(for: appLanguage).capitalized)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.textSecondary)
            
            ForEach(order.items) { item in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 10) {
                        Text("\(item.quantity)×")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(.appAccent)
                            .frame(width: 28, alignment: .trailing)
                        
                        Text(item.name)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.textPrimary)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        // Item status
                        OrderStatusBadge(status: item.status, size: .small)
                    }
                    // Options + note (unified, parity with master device)
                    ItemOptionsView(
                        modifiers: item.modifiers.map { ($0.name, $0.price) },
                        notes: item.notes,
                        tint: .appAccent
                    )
                    .padding(.leading, 38)
                }
                .padding(.vertical, 6)
                
                if item.id != order.items.last?.id {
                    Divider().background(Color.appDivider.opacity(0.5))
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: APRadius.lg, style: .continuous)
                .fill(Color.appSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: APRadius.lg, style: .continuous)
                        .stroke(Color.appBorderSubtle, lineWidth: 1)
                )
        )
    }
    
    // MARK: - Helpers
    
    private var isInProgress: Bool {
        fulfillmentStatus == "preparing" || fulfillmentStatus == "ready"
    }
    
    private var elapsedText: String {
        guard let created = orderCreatedDate else { return "--" }
        let elapsed = now.timeIntervalSince(created)
        return formatDuration(elapsed)
    }
    
    private var estimatedRemainingText: String {
        guard let created = orderCreatedDate else { return "--" }
        let elapsed = now.timeIntervalSince(created) / 60
        let remaining = max(0, estimatedPrepMinutes - elapsed)
        if remaining <= 0 { return "Almost ready!" }
        return "~\(Int(remaining)) min"
    }
    
    private func circleColor(for status: TimelineStepStatus) -> Color {
        switch status {
        case .completed: return .appGreen
        case .current:   return .appAccent
        case .pending:   return Color.textTertiary.opacity(0.5)
        }
    }
    
    private func buildSteps(for order: Order) -> [TimelineStep] {
        let status = order.status.lowercased()
        let created = orderCreatedDate

        // Kitchen fulfilment is intentionally derived from item states. A paid
        // Staff Quick Order has order.status == completed while its food remains
        // cooking, so payment must never advance the kitchen timeline.
        let liveItems = order.items.filter { $0.status.lowercased() != "cancelled" }
        let itemStatuses = liveItems.map { $0.status.lowercased() }
        let hasPreparingItems = itemStatuses.contains {
            ["pending", "preparing", "cooking", "alert"].contains($0)
        }
        let hasReadyItems = itemStatuses.contains("ready")
        let allServed = !liveItems.isEmpty && itemStatuses.allSatisfy { $0 == "served" }

        let currentIndex: Int = {
            if status == "cancelled" { return -1 }
            if allServed { return 4 }
            if hasPreparingItems { return 2 }
            if hasReadyItems { return 3 }
            switch status {
            case "pending", "placed":       return 0
            case "confirmed":               return 1
            case "preparing", "cooking":    return 2
            case "ready":                   return 3
            case "served":                  return 4
            // A payment-only completed status with no terminal item evidence
            // stays at preparing instead of fabricating kitchen completion.
            case "completed":               return liveItems.isEmpty ? 1 : 2
            default:                        return 0
            }
        }()
        
        let stepData: [(key: String, icon: String)] = [
            ("order_placed", "arrow.up.circle.fill"),
            ("order_confirmed", "checkmark.circle.fill"),
            ("order_preparing", "flame.fill"),
            ("order_ready", "bell.fill"),
            ("order_served", "takeoutbag.and.cup.and.straw.fill")
        ]
        
        return stepData.enumerated().map { (idx, data) in
            let stepStatus: TimelineStepStatus
            if status == "cancelled" {
                stepStatus = idx == 0 ? .completed : .pending
            } else if allServed {
                // The kitchen has terminalized every non-cancelled item. Close
                // the final fulfilment step instead of leaving "Served" spinning.
                stepStatus = .completed
            } else if idx < currentIndex {
                stepStatus = .completed
            } else if idx == currentIndex {
                stepStatus = .current
            } else {
                stepStatus = .pending
            }
            
            // Only createdAt is a real timestamp in this payload. Never invent
            // future +3 minute timestamps for kitchen events that have not occurred.
            let timestamp: Date? = {
                idx == 0 ? created : nil
            }()
            
            return TimelineStep(
                title: data.key.localized(for: appLanguage),
                icon: data.icon,
                timestamp: timestamp,
                status: stepStatus
            )
        }
    }

    /// Operational food status displayed independently from payment state.
    private var fulfillmentStatus: String {
        let statuses = order.items
            .filter { $0.status.lowercased() != "cancelled" }
            .map { $0.status.lowercased() }
        guard !statuses.isEmpty else {
            return order.status.lowercased() == "completed" ? "confirmed" : order.status
        }
        if statuses.allSatisfy({ $0 == "served" }) { return "served" }
        if statuses.contains(where: { ["pending", "preparing", "cooking", "alert"].contains($0) }) {
            return "preparing"
        }
        if statuses.contains("ready") { return "ready" }
        return order.status
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
    
    private func formatDateTime(_ iso: String) -> String {
        guard let date = parseISO8601(iso) else { return iso }
        let formatter = DateFormatter()
        formatter.dateFormat = "dd MMM, HH:mm"
        return formatter.string(from: date)
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let totalSec = Int(max(0, seconds))
        let min = totalSec / 60
        let sec = totalSec % 60
        if min >= 60 {
            return "\(min / 60)h \(min % 60)m"
        }
        return "\(min)m \(sec)s"
    }
    
    private func parseISO8601(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = formatter.date(from: string) { return d }
        formatter.formatOptions = [.withInternetDateTime]
        if let d = formatter.date(from: string) { return d }
        // Fallback: basic date parsing
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return df.date(from: string)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Preview
// ─────────────────────────────────────────────────────────────────────────────

#Preview {
    OrderTimelineView(
        order: Order(
            id: "test-1",
            orderNumber: "QO-1234",
            tableNumber: "QUICK",
            total: 450.0,
            status: "preparing",
            createdAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-600)),
            items: [
                OrderItem(id: "i1", name: "Pad Thai", quantity: 2, price: 120, status: "cooking", item_id: nil, notes: nil, servedBy: nil),
                OrderItem(id: "i2", name: "Tom Yum Soup", quantity: 1, price: 210, status: "ready", item_id: nil, notes: nil, servedBy: nil)
            ],
            sessionToken: nil
        )
    )
}
