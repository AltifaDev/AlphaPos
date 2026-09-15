// NotificationCenterView.swift
// AlphaPos — Enterprise Notification Center (Master Device)
// v2: Wired to NotificationStore for real Supabase Realtime alerts.

import SwiftUI
import SwiftData

/// Unified Notification Center for the Master Device.
/// Aggregates alerts from ALL devices via NotificationStore.
///
/// Data flow:
/// ```
/// Supabase Realtime WS → SyncEngine → InAppNotificationManager
///                                    → NotificationStore → THIS VIEW
/// ```
struct NotificationCenterView: View {
    @EnvironmentObject private var sessionManager: AppSessionManager
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var lm: LocalizationManager
    
    @ObservedObject private var store = NotificationStore.shared
    @ObservedObject private var syncEngine = SyncEngine.shared
    @Query(filter: #Predicate<Order> { !$0.isDeleted }) private var orders: [Order]
    @Query(filter: #Predicate<InventoryItem> { !$0.isDeleted }) private var stockItems: [InventoryItem]
    @AppStorage("active_merchant_id") private var activeMerchantId = ""
    @AppStorage(BranchContext.storageKey) private var activeBranchId = ""
    
    @State private var selectedFilter: NotificationAlert.AlertCategory = .all
    @State private var searchText = ""

    private var authorizedAlerts: [NotificationAlert] {
        guard sessionManager.can(.notificationsView) else { return [] }
        return store.filtered(by: .all).filter { alert in
            if sessionManager.can(.organizationManage) { return true }
            let categoryAllowed: Bool
            switch alert.category {
            case .orders: categoryAllowed = sessionManager.can(.posSell)
            case .kitchen: categoryAllowed = sessionManager.can(.kitchenView)
            case .inventory: categoryAllowed = sessionManager.can(.inventoryView)
            case .payment: categoryAllowed = sessionManager.can(.cashDrawerManage)
            case .customer: categoryAllowed = sessionManager.can(.customersView)
            case .staff: categoryAllowed = sessionManager.can(.staffManage)
            case .system: categoryAllowed = sessionManager.can(.deviceManage)
            case .all: categoryAllowed = false
            }
            guard categoryAllowed, !activeBranchId.isEmpty else { return false }
            if let number = alert.orderNumber {
                return orders.contains { $0.orderNumber == number && $0.branch.id.uuidString.lowercased() == activeBranchId.lowercased() }
            }
            if let id = alert.inventoryItemId {
                return stockItems.contains { $0.id.uuidString.lowercased() == id.lowercased() && $0.branch?.id.uuidString.lowercased() == activeBranchId.lowercased() }
            }
            // Legacy history without a verifiable branch must not leak across branches.
            return false
        }
    }
    private var authorizedUnreadCount: Int { authorizedAlerts.filter { !$0.isRead }.count }
    private func markAuthorizedRead() { authorizedAlerts.forEach { store.markRead($0.id) } }
    
    var body: some View {
        VStack(spacing: 0) {
            // Filter chips
            filterChipsSection
            
            Divider().background(Color.appDivider)
            
            // Alerts list
            alertsListSection
        }
        .background(Color.appBackground)
        .navigationTitle("notification_center_title".t)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                headerSection
            }
        }
        .onAppear {
            store.activateScope(merchantId: activeMerchantId)
            rebuildLiveAlerts()
            StockAlertEvaluator.refresh(modelContext: modelContext, force: true)
            Task { await SyncEngine.shared.performSync(modelContext: modelContext) }
        }
        .onChange(of: orders.count) { _, _ in
            rebuildLiveAlerts()
        }
        // Property updates (isStaffConfirmed / status) after iPhone approve do not
        // change orders.count — rebuild when confirmation fingerprint changes.
        .onChange(of: orderAlertFingerprint) { _, _ in
            rebuildLiveAlerts()
        }
        .onChange(of: syncEngine.lastSyncedAt) { _, _ in
            rebuildLiveAlerts()
            StockAlertEvaluator.refresh(modelContext: modelContext)
        }
        .onChange(of: syncEngine.activeRequests.count) { _, _ in
            rebuildLiveAlerts()
        }
        .onChange(of: activeMerchantId) { _, merchantId in
            store.activateScope(merchantId: merchantId)
            rebuildLiveAlerts()
        }
        .onChange(of: activeBranchId) { _, _ in rebuildLiveAlerts() }
        .onChange(of: lm.currentLanguage) { _, _ in
            // Live alerts contain composed text, so rebuild them immediately
            // whenever the in-app language changes.
            store.switchHistoryLanguage()
            rebuildLiveAlerts()
            StockAlertEvaluator.refresh(modelContext: modelContext, force: true)
        }
    }

    /// Tracks approval/kitchen state so NC clears when Staff confirms on iPhone.
    private var orderAlertFingerprint: String {
        orders
            .map { "\($0.id.uuidString.prefix(8))|\($0.status)|\($0.isStaffConfirmed)|\($0.isAwaitingStaffApproval)" }
            .sorted()
            .joined(separator: ";")
    }

    private func rebuildLiveAlerts() {
        let scopedOrders = activeBranchId.isEmpty
            ? orders
            : orders.filter { order in
                order.branch.id.uuidString.lowercased() == activeBranchId.lowercased()
            }
        store.rebuildLiveOperationalAlerts(
            orders: scopedOrders,
            serviceRequests: syncEngine.activeRequests
        )
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        HStack(spacing: 8) {
            // Unread count badge
            if authorizedUnreadCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 14))
                    Text("\(authorizedUnreadCount)")
                        .font(.caption.weight(.bold))
                }
                .foregroundColor(.appAccent)
                .frame(width: 40, height: 36)
                .background(Color.appAccent.opacity(0.1))
                .cornerRadius(10)
            }
            
            // Mark all read
            if authorizedUnreadCount > 0 {
                Button {
                    withAnimation { markAuthorizedRead() }
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.textSecondary)
                    .frame(width: 40, height: 36)
                    .background(Color.appSurfaceHigh)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("notif_mark_all_read".t)
            }

            Menu {
                Button {
                    markAuthorizedRead()
                } label: {
                    Label("notif_mark_all_read".t, systemImage: "checkmark.circle")
                }
                Button {
                    authorizedAlerts.forEach { store.acknowledge($0.id) }
                } label: {
                    Label("notif_dismiss_history".t, systemImage: "archivebox")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.textSecondary)
                    .frame(width: 40, height: 36)
                    .background(Color.appSurfaceHigh)
                    .cornerRadius(8)
            }
            .accessibilityLabel("notif_more_actions".t)
        }
    }
    
    // MARK: - Filter Chips
    
    private var filterChipsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(NotificationAlert.AlertCategory.allCases) { category in
                    let unread = authorizedAlerts.filter { !$0.isRead && (category == .all || $0.category == category) }.count
                    let active = store.activeCount(in: category)
                    
                    Button {
                        withAnimation { selectedFilter = category }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: category.icon)
                                .font(.system(size: 12))
                            Text(category.label)
                                .font(.system(size: 12, weight: .medium))
                            if unread > 0 {
                                Text("\(unread)")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 18, height: 18)
                                    .background(category.color)
                                    .clipShape(Circle())
                            } else if active > 0 {
                                Text("\(active)")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(category.color)
                                    .padding(.horizontal, 5)
                                    .frame(minWidth: 18, minHeight: 18)
                                    .overlay(
                                        Capsule().stroke(category.color.opacity(0.6), lineWidth: 1)
                                    )
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(selectedFilter == category ? category.color.opacity(0.15) : Color.appSurfaceHigh)
                        .foregroundColor(selectedFilter == category ? category.color : .textSecondary)
                        .cornerRadius(20)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(selectedFilter == category ? category.color.opacity(0.3) : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
    }
    
    // MARK: - Alerts List
    
    private var alertsListSection: some View {
        let filteredAlerts = authorizedAlerts.filter { selectedFilter == .all || $0.category == selectedFilter }
        
        return ScrollView {
            if filteredAlerts.isEmpty {
                // Empty state
                VStack(spacing: 16) {
                    Image(systemName: "bell.slash")
                        .font(.system(size: 44))
                        .foregroundColor(.textTertiary)
                    Text("notif_no_alerts".t)
                        .font(.headline)
                        .foregroundColor(.textSecondary)
                    Text("notif_no_alerts_desc".t)
                        .font(.subheadline)
                        .foregroundColor(.textTertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 320)
                .padding()
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(filteredAlerts) { alert in
                        alertRow(alert)
                    }
                }
                .padding()
            }
        }
        .refreshable {
            await refreshData()
        }
    }
    
    @MainActor
    private func refreshData() async {
        APHaptic.trigger()
        store.activateScope(merchantId: activeMerchantId)
        rebuildLiveAlerts()
        StockAlertEvaluator.refresh(modelContext: modelContext, force: true)
        await SyncEngine.shared.performSync(modelContext: modelContext)
        rebuildLiveAlerts()
    }
    
    // MARK: - Alert Row
    
    private func alertRow(_ alert: NotificationAlert) -> some View {
        // Whether this alert can navigate to an order/table or inventory SKU
        let canOpen = navigationTarget(for: alert) != nil
            || alert.orderNumber != nil
            || inventoryTarget(for: alert) != nil
            || alert.liveKey?.hasPrefix("stale-shift-") == true

        return HStack(spacing: 12) {
            // Priority indicator
            Rectangle()
                .fill(alert.priority.color)
                .frame(width: 4)
                .cornerRadius(2)
            
            // Category icon
            ZStack {
                Circle()
                    .fill(alert.category.color.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: rowIcon(for: alert))
                    .font(.system(size: 14))
                    .foregroundColor(alert.priority.color)
            }
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(alert.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(alert.isRead ? .textSecondary : .textPrimary)
                    
                    if !alert.isRead {
                        Circle()
                            .fill(Color.appAccent)
                            .frame(width: 6, height: 6)
                    }
                    
                    Spacer()
                    
                    Text(timeLabel(for: alert.createdAt))
                        .font(.system(size: 11))
                        .foregroundColor(.textTertiary)
                }
                
                Text(alert.message)
                    .font(.system(size: 12))
                    .foregroundColor(.textSecondary)
                    .lineLimit(2)
                
                HStack(spacing: 8) {
                    // Device badge
                    HStack(spacing: 4) {
                        Image(systemName: deviceIcon(alert.device))
                            .font(.system(size: 9))
                        Text(localizedDeviceName(alert.device))
                            .font(.system(size: 10))
                    }
                    .foregroundColor(.textTertiary)
                    
                    // Priority badge
                    Text(alert.priority.label)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(alert.priority.color)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(alert.priority.color.opacity(0.1))
                        .cornerRadius(4)

                    Label(
                        alert.isRead ? "notif_status_read".t : "notif_status_new".t,
                        systemImage: alert.isRead ? "checkmark.circle.fill" : "circle.fill"
                    )
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(alert.isRead ? .textTertiary : .appAccent)
                }
            }
            
            // Tappable affordance — chevron to open the related order/table
            if canOpen {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textTertiary)
            }

            if !alert.isLive {
                Button {
                    store.acknowledge(alert.id)
                } label: {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("notif_dismiss".t)
            }

        }
        .padding(12)
        .background(alert.isRead ? Color.appSurface.opacity(0.72) : Color.appAccent.opacity(0.06))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    alert.isRead ? Color.appBorderSubtle : Color.appAccent.opacity(0.3),
                    lineWidth: 1
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            store.markRead(alert.id)
            if canOpen {
                if alert.category == .inventory {
                    openInventory(for: alert)
                } else if alert.liveKey?.hasPrefix("stale-shift-") == true {
                    openShiftManagement()
                } else {
                    openOrder(for: alert)
                }
            }
        }
        .contextMenu {
            if !alert.isLive {
                Button {
                    store.acknowledge(alert.id)
                } label: {
                    Label("notif_dismiss".t, systemImage: "checkmark.circle")
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(alert.priority.label), \(alert.title), \(alert.message), " +
            (alert.isRead ? "notif_status_read".t : "notif_status_new".t)
        )
        .accessibilityHint(canOpen ? "notif_open_details_hint".t : "")
        .accessibilityAddTraits(canOpen ? .isButton : [])
    }

    // MARK: - Navigation

    /// Resolve which table number an alert should open, if any.
    /// Uses the alert's explicit tableNumber, else parses "Table N" / "โต๊ะ N" from the message.
    private func navigationTarget(for alert: NotificationAlert) -> String? {
        if let t = alert.tableNumber, !t.trimmingCharacters(in: .whitespaces).isEmpty {
            return t
        }
        // Fallback: parse a table number out of the message text.
        let text = alert.message
        if let range = text.range(of: "(?:Table|โต๊ะ)\\s*#?\\s*([0-9A-Za-z-]+)", options: .regularExpression) {
            let matched = String(text[range])
            if let numRange = matched.range(of: "([0-9A-Za-z-]+)$", options: .regularExpression) {
                return String(matched[numRange])
            }
        }
        return nil
    }

    /// Inventory deep-link: explicit id, else parse from liveKey `inv-out-|inv-low-UUID`.
    private func inventoryTarget(for alert: NotificationAlert) -> String? {
        if let id = alert.inventoryItemId, !id.isEmpty { return id }
        guard alert.category == .inventory, let key = alert.liveKey else { return nil }
        for prefix in ["inv-out-", "inv-low-"] where key.hasPrefix(prefix) {
            let id = String(key.dropFirst(prefix.count))
            if UUID(uuidString: id) != nil { return id }
        }
        return nil
    }

    private func openInventory(for alert: NotificationAlert) {
        guard let itemId = inventoryTarget(for: alert) else { return }
        APHaptic.trigger()
        store.markRead(alert.id)
        NotificationCenter.default.post(
            name: .openInventoryItemNotification,
            object: nil,
            userInfo: ["inventory_item_id": itemId]
        )
    }

    private func openShiftManagement() {
        APHaptic.trigger()
        NotificationCenter.default.post(name: .openPOSTabNotification, object: nil)
    }

    /// Tapping an alert opens the related order/table on the master device.
    /// Posts `.openTableNotification`, which MainDashboardView observes to switch
    /// to the POS/Tables tab with the correct active session.
    private func openOrder(for alert: NotificationAlert) {
        guard alert.orderNumber != nil || navigationTarget(for: alert) != nil else { return }
        APHaptic.trigger()
        store.markRead(alert.id)
        var userInfo: [String: String] = [:]
        if let orderNumber = alert.orderNumber {
            userInfo["order_number"] = orderNumber
        }
        if let table = navigationTarget(for: alert) {
            userInfo["table_number"] = table
        }
        NotificationCenter.default.post(
            name: .openOrderNotification,
            object: nil,
            userInfo: userInfo
        )
    }
    
    // MARK: - Helpers
    
    private func timeLabel(for date: Date) -> String {
        let relative = timeAgo(date)
        let absolute: String = {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: lm.currentLanguage.rawValue)
            formatter.timeZone = .current
            if Calendar.current.isDateInToday(date) {
                formatter.dateStyle = .none
                formatter.timeStyle = .short
            } else {
                // Overnight / previous-day web orders: show date so 00:17
                // is not confused with "just now" evening times.
                formatter.dateStyle = .short
                formatter.timeStyle = .short
            }
            return formatter.string(from: date)
        }()
        return "\(relative) · \(absolute)"
    }
    
    private func timeAgo(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "notif_just_now".t }
        if interval < 3600 { return "\(Int(interval / 60)) " + "notif_min_ago".t }
        if interval < 86400 { return "\(Int(interval / 3600)) " + "notif_hr_ago".t }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
    
    private func deviceIcon(_ device: String) -> String {
        switch device.lowercased() {
        case let d where d.contains("ipad"): return "ipad.landscape"
        case let d where d.contains("iphone"), let d where d.contains("staff"): return "iphone"
        case let d where d.contains("kitchen"): return "display"
        case let d where d.contains("customer"), let d where d.contains("web"): return "globe"
        default: return "server.rack"
        }
    }

    private func rowIcon(for alert: NotificationAlert) -> String {
        guard alert.category == .system else { return alert.category.icon }
        switch alert.priority {
        case .critical, .high: return "exclamationmark.triangle.fill"
        case .medium: return "info.circle.fill"
        case .low: return "checkmark.circle.fill"
        }
    }

    private func localizedDeviceName(_ device: String) -> String {
        switch device {
        case "System": return "notif_category_system".t
        case "Inventory": return "notif_category_inventory".t
        case "Printer": return "notif_device_printer".t
        case "Customer Web": return "notif_device_customer_web".t
        case "Customer Web / Staff": return "notif_device_customer_web_staff".t
        case "Staff App", "Staff iPhone": return "notif_device_staff_app".t
        case "Kitchen Display": return "notif_device_kitchen_display".t
        case "Delivery System": return "notif_device_delivery_system".t
        case "Master iPad": return "notif_device_master_ipad".t
        default: return device
        }
    }
}

// MARK: - Escalation Settings Sheet
