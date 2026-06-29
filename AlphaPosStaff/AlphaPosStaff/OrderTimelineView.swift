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
    let order: Order
    @AppStorage("app_language") private var appLanguage = "en"
    @Environment(\.dismiss) private var dismiss
    
    @State private var pulseAnimation = false
    @State private var elapsedTimer: Timer? = nil
    @State private var now = Date()
    
    // Average estimated prep time (in minutes) — can be adjusted per-restaurant
    private let estimatedPrepMinutes: Double = 15
    
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
            }
            .navigationTitle("order_timeline".localized(for: appLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
            }
            .onDisappear {
                elapsedTimer?.invalidate()
                elapsedTimer = nil
            }
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
                    Text(order.tableNumber == "QUICK" ? "quick_order".localized(for: appLanguage) : "Table \(order.tableNumber)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.textSecondary)
                }
                
                Spacer()
                
                // Status badge
                OrderStatusBadge(status: order.status, size: .large)
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
        let s = order.status.lowercased()
        return s == "preparing" || s == "confirmed" || s == "pending"
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
        
        // Determine which step we're at
        let statusOrder = ["placed", "confirmed", "preparing", "ready", "served"]
        let currentIndex: Int = {
            switch status {
            case "pending", "placed":       return 0
            case "confirmed":               return 1
            case "preparing", "cooking":    return 2
            case "ready":                   return 3
            case "served", "completed":     return 4
            case "cancelled":               return -1
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
            } else if idx < currentIndex {
                stepStatus = .completed
            } else if idx == currentIndex {
                stepStatus = .current
            } else {
                stepStatus = .pending
            }
            
            // Estimate timestamps (only createdAt is real, rest are simulated)
            let timestamp: Date? = {
                if stepStatus == .completed || stepStatus == .current {
                    if idx == 0 { return created }
                    // Simulate: each step takes ~3 min
                    if let base = created {
                        return base.addingTimeInterval(Double(idx) * 180)
                    }
                }
                return nil
            }()
            
            return TimelineStep(
                title: data.key.localized(for: appLanguage),
                icon: data.icon,
                timestamp: timestamp,
                status: stepStatus
            )
        }
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
