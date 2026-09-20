// RecentOrdersSheetView.swift
// AlphaPosStaff — Parity with iPad's "ตรวจสอบออเดอร์ล่าสุด" (Recent Order Check)
// Allows iPhone staff to quickly inspect recent quick orders, check payment status, and track live timeline.

import SwiftUI

struct RecentOrdersSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("app_language") private var appLanguage = "en"
    
    @State private var orders: [Order] = []
    @State private var isLoading = false
    @State private var selectedFilter: String = "all" // "all", "unpaid", "paid"
    @State private var searchText: String = ""
    @State private var selectedOrderForTimeline: Order? = nil
    @State private var selectedOrderForEdit: Order? = nil
    @State private var pollTimer: Timer? = nil
    
    private var visibleOrders: [Order] {
        orders.filter { order in
            let matchesFilter: Bool
            switch selectedFilter {
            case "unpaid":
                matchesFilter = !order.isPaid && order.status.lowercased() != "cancelled"
            case "paid":
                matchesFilter = order.isPaid && order.status.lowercased() != "cancelled"
            default:
                matchesFilter = true
            }
            guard matchesFilter else { return false }
            
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !query.isEmpty else { return true }
            
            let queueText = order.queueNumber?.lowercased() ?? ""
            let orderNum = order.orderNumber.lowercased()
            let itemsText = order.items.map { $0.name.lowercased() }.joined(separator: " ")
            let tableNum = order.tableNumber.lowercased()
            
            return queueText.contains(query) ||
                orderNum.contains(query) ||
                itemsText.contains(query) ||
                tableNum.contains(query)
        }
    }
    
    var body: some View {
        NavigationStack {
            List {
                // Info header notice
                Section {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.appAccent)
                            .font(.system(size: 16))
                            .padding(.top, 2)
                        Text("recent_order_notice".localized(for: appLanguage))
                            .font(.system(size: 12))
                            .foregroundColor(.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                }
                
                // Segmented Filter
                Section {
                    Picker("payment_status".localized(for: appLanguage), selection: $selectedFilter) {
                        Text("filter_all".localized(for: appLanguage)).tag("all")
                        Text("filter_unpaid".localized(for: appLanguage)).tag("unpaid")
                        Text("filter_paid".localized(for: appLanguage)).tag("paid")
                    }
                    .pickerStyle(.segmented)
                }
                
                // Orders list
                if isLoading && orders.isEmpty {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView()
                                .padding()
                            Spacer()
                        }
                    }
                } else if visibleOrders.isEmpty {
                    ContentUnavailableView(
                        "no_matching_orders".localized(for: appLanguage),
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("no_matching_orders_desc".localized(for: appLanguage))
                    )
                } else {
                    Section(String(format: "latest_orders_count".localized(for: appLanguage), visibleOrders.count)) {
                        ForEach(visibleOrders) { order in
                            Button {
                                selectedOrderForTimeline = order
                            } label: {
                                RecentOrderCardRow(order: order, appLanguage: appLanguage)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                if !order.isPaid && order.status.lowercased() != "cancelled" {
                                    Button {
                                        selectedOrderForEdit = order
                                    } label: {
                                        Label("แก้ไขรายการ", systemImage: "pencil")
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $searchText, prompt: "search_queue_order_item".localized(for: appLanguage))
            .navigationTitle("recent_order_check".localized(for: appLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel_btn".localized(for: appLanguage)) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await loadOrders() }
                    } label: {
                        if isLoading {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14, weight: .semibold))
                        }
                    }
                    .disabled(isLoading)
                }
            }
            .refreshable {
                await loadOrders()
            }
            .onAppear {
                Task { await loadOrders() }
                pollTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { _ in
                    Task { await loadOrders(isSilent: true) }
                }
            }
            .onDisappear {
                pollTimer?.invalidate()
                pollTimer = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("StaffOrderUpdated"))) { note in
                if let updated = note.object as? Order {
                    if let idx = orders.firstIndex(where: { $0.id == updated.id }) {
                        orders[idx] = updated
                    } else if updated.isQuickOrder {
                        orders.insert(updated, at: 0)
                    }
                }
            }
            .sheet(item: $selectedOrderForTimeline) { order in
                OrderTimelineView(order: order)
            }
            .sheet(item: $selectedOrderForEdit) { order in
                QuickOrderEditSheet(order: order, appLanguage: appLanguage) {
                    Task { await loadOrders(isSilent: true) }
                }
            }
        }
        .presentationDetents([.large])
    }
    
    private func loadOrders(isSilent: Bool = false) async {
        if !isSilent { isLoading = true }
        defer { if !isSilent { isLoading = false } }
        do {
            let fetched = try await NetworkService.shared.fetchQuickOrderHistory()
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    self.orders = fetched
                }
            }
        } catch {
            #if DEBUG
            print("RecentOrdersSheetView load error: \(error)")
            #endif
        }
    }
}

/// Edit surface for unpaid staff Quick Orders.  It deliberately uses the
/// same item editor and optimistic row-version APIs as table orders, so an
/// iPhone can correct a pay-later order without creating a second charge.
private struct QuickOrderEditSheet: View {
    let order: Order
    let appLanguage: String
    let onChanged: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var editingItem: OrderItem?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(order.items.filter { $0.status.lowercased() != "cancelled" }) { item in
                        HStack {
                            VStack(alignment: .leading) {
                                Text("\(item.quantity)× \(item.name)").font(.headline)
                                Text("฿\(String(format: "%.2f", item.price * Double(item.quantity)))")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            Button { editingItem = item } label: { Image(systemName: "pencil") }
                        }
                    }
                } header: {
                    Text(appLanguage == "th" ? "แก้ไขก่อนชำระเงิน" : "Edit before payment")
                }
            }
            .navigationTitle(order.queueNumber ?? order.orderNumber)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("ปิด") { dismiss() } } }
            .sheet(item: $editingItem) { item in
                EditOrderItemSheet(item: item, order: order, appLanguage: appLanguage,
                                   royalBlue: .appAccent, elfGreen: .appGreen, coralRed: .appRose,
                                   allowsQuantityEdit: false)
                    .onDisappear { onChanged() }
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - RecentOrderCardRow
// ─────────────────────────────────────────────────────────────────────────────

private struct RecentOrderCardRow: View {
    let order: Order
    let appLanguage: String
    
    private var itemSummary: String {
        let items = order.items.map { "\($0.quantity)× \($0.name)" }
        return items.isEmpty ? "—" : items.joined(separator: ", ")
    }
    
    private var createdDate: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = formatter.date(from: order.createdAt) { return d }
        formatter.formatOptions = [.withInternetDateTime]
        if let d = formatter.date(from: order.createdAt) { return d }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return df.date(from: order.createdAt)
    }
    
    private var relativeAgeText: String {
        guard let d = createdDate else { return order.createdAt }
        let elapsed = max(0, Date().timeIntervalSince(d))
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        let timeStr = timeFormatter.string(from: d)
        
        let ageStr: String
        if elapsed < 60 {
            ageStr = appLanguage == "th" ? "เมื่อสักครู่" : "Just now"
        } else {
            let mins = Int(elapsed / 60)
            if mins < 60 {
                ageStr = appLanguage == "th" ? "\(mins) นาทีที่แล้ว" : "\(mins)m ago"
            } else {
                let hours = mins / 60
                ageStr = appLanguage == "th" ? "\(hours) ชม. ที่แล้ว" : "\(hours)h ago"
            }
        }
        return "\(timeStr) · \(ageStr)"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            // Top: Queue/Order number + Payment Badge
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(order.queueNumber.map { (appLanguage == "th" ? "คิว #" : "Queue #") + $0.replacingOccurrences(of: "#", with: "") }
                             ?? "#\(order.orderNumber)")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.textPrimary)
                        
                        // Order type tag
                        Text(order.orderType.capitalized)
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.appSurface)
                            .foregroundColor(.textSecondary)
                            .cornerRadius(4)
                    }
                    
                    Text(relativeAgeText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.textSecondary)
                }
                
                Spacer()
                
                // Payment badge
                if order.isPaid {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text("filter_paid".localized(for: appLanguage))
                            .font(.system(size: 11, weight: .bold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.appGreen.opacity(0.12))
                    .foregroundColor(.appGreen)
                    .cornerRadius(6)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.badge.exclamationmark")
                            .font(.system(size: 10, weight: .bold))
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
            
            // Items summary
            Text(itemSummary)
                .font(.system(size: 13))
                .foregroundColor(.textSecondary)
                .lineLimit(2)
            
            // Bottom: Fulfillment status + Price
            HStack {
                OrderStatusBadge(status: order.status, size: .small, lang: appLanguage)
                
                Spacer()
                
                if !order.isPaid {
                    Text("due_amount".localized(for: appLanguage) + "฿\(String(format: "%.2f", order.total))")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.appRose)
                } else {
                    Text("฿\(String(format: "%.2f", order.total))")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.appTeal)
                }
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.textTertiary)
            }
        }
        .padding(.vertical, 4)
    }
}
