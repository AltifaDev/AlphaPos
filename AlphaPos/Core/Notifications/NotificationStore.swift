// NotificationStore.swift
// AlphaPos — Enterprise Notification Store (Persistent Alert History)
// Provides a persistent in-memory store of ALL alerts for Notification Center.
// InAppNotificationManager handles transient banners (auto-dismiss);
// NotificationStore retains the full history until explicitly acknowledged.

import Foundation
import Combine
import SwiftUI
import CryptoKit
import SwiftData

// MARK: - Alert Model

/// A persistent alert for the Notification Center.
/// Unlike InAppNotification (which auto-dismisses), these stay until acknowledged.
struct NotificationAlert: Identifiable, Equatable, Codable {
    let id: UUID
    let priority: AlertPriority
    let category: AlertCategory
    let title: String
    let message: String
    let device: String          // Source device/system
    let tableNumber: String?    // For navigation
    let orderNumber: String?
    /// Inventory SKU id for deep-link into Inventory (UUID string).
    let inventoryItemId: String?
    let createdAt: Date
    /// Stable key for live operational rows (order-/request-based). History alerts leave this nil.
    let liveKey: String?
    /// Live work-queue rows rebuild from SwiftData; they clear when the condition clears.
    let isLive: Bool
    var isRead: Bool = false
    var isAcknowledged: Bool = false

    init(
        id: UUID = UUID(),
        priority: AlertPriority,
        category: AlertCategory,
        title: String,
        message: String,
        device: String,
        tableNumber: String? = nil,
        orderNumber: String? = nil,
        inventoryItemId: String? = nil,
        createdAt: Date = Date(),
        liveKey: String? = nil,
        isLive: Bool = false,
        isRead: Bool = false,
        isAcknowledged: Bool = false
    ) {
        self.id = id
        self.priority = priority
        self.category = category
        self.title = title
        self.message = message
        self.device = device
        self.tableNumber = tableNumber
        self.orderNumber = orderNumber
        self.inventoryItemId = inventoryItemId
        self.createdAt = createdAt
        self.liveKey = liveKey
        self.isLive = isLive
        self.isRead = isRead
        self.isAcknowledged = isAcknowledged
    }

    enum AlertPriority: Int, Comparable, CaseIterable, Codable {
        case critical = 0
        case high = 1
        case medium = 2
        case low = 3

        static func < (lhs: AlertPriority, rhs: AlertPriority) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        var color: Color {
            switch self {
            case .critical: return Color(hex: "EF4444")
            case .high: return Color(hex: "F59E0B")
            case .medium: return Color(hex: "3B82F6")
            case .low: return Color(hex: "9CA3AF")
            }
        }

        var label: String {
            switch self {
            case .critical: return "notif_priority_critical".t
            case .high: return "notif_priority_high".t
            case .medium: return "notif_priority_medium".t
            case .low: return "notif_priority_low".t
            }
        }
    }

    enum AlertCategory: String, CaseIterable, Identifiable, Codable {
        case all = "All"
        case orders = "Orders"
        case kitchen = "Kitchen"
        case staff = "Staff"
        case inventory = "Inventory"
        case system = "System"
        case customer = "Customer"
        case payment = "Payment"

        var id: String { rawValue }

        var label: String {
            switch self {
            case .all: return "notif_category_all".t
            case .orders: return "notif_category_orders".t
            case .kitchen: return "notif_category_kitchen".t
            case .staff: return "notif_category_staff".t
            case .inventory: return "notif_category_inventory".t
            case .system: return "notif_category_system".t
            case .customer: return "notif_category_customer".t
            case .payment: return "notif_category_payment".t
            }
        }

        var icon: String {
            switch self {
            case .all: return "bell.fill"
            case .orders: return "tray.full.fill"
            case .kitchen: return "flame.fill"
            case .staff: return "person.2.fill"
            case .inventory: return "shippingbox.fill"
            case .system: return "gearshape.2.fill"
            case .customer: return "person.crop.circle.fill"
            case .payment: return "creditcard.fill"
            }
        }

        var color: Color {
            switch self {
            case .all: return .appAccent
            case .orders: return Color(hex: "3B82F6")
            case .kitchen: return Color(hex: "F59E0B")
            case .staff: return Color(hex: "8B5CF6")
            case .inventory: return Color(hex: "0D9488")
            case .system: return Color(hex: "64748B")
            case .customer: return Color(hex: "10B981")
            case .payment: return Color(hex: "EC4899")
            }
        }
    }
}

// MARK: - Notification Store (Observable Singleton)

/// Central store for all enterprise notifications.
/// Wire into NotificationCenterView via @ObservedObject or @EnvironmentObject.
///
/// Data flow:
/// ```
/// SyncEngine (Realtime WS) ──▶ InAppNotificationManager (transient banner)
///                          └──▶ NotificationStore (persistent history)
/// ```
@MainActor
final class NotificationStore: ObservableObject {
    static let shared = NotificationStore()

    /// Event/history alerts (newest first) — banners, kitchen delay pulses, etc.
    @Published var alerts: [NotificationAlert] = []
    /// Live work queue rebuilt from SwiftData orders + pending service requests (Staff parity).
    @Published private(set) var liveAlerts: [NotificationAlert] = []
    /// Live inventory low / out rows (cleared when stock recovers).
    @Published private(set) var liveInventoryAlerts: [NotificationAlert] = []
    /// Badge counts remain hidden until the cold-start cache has been
    /// reconciled with the server (or an offline reconciliation completes).
    /// This prevents a stale local count flashing briefly during launch.
    @Published private(set) var isInitialReconciliationComplete = false

    /// New-event count for badges. Inventory live rows represent active
    /// conditions, not dozens of newly delivered messages; threshold crossings
    /// are represented by history pulses instead.
    var unreadCount: Int {
        guard isInitialReconciliationComplete else { return 0 }
        return visibleHistoryAlerts.filter { !$0.isRead }.count
            + liveAlerts.filter { !$0.isRead }.count
    }

    func unreadCount(in category: NotificationAlert.AlertCategory) -> Int {
        guard isInitialReconciliationComplete else { return 0 }
        if category == .all { return unreadCount }
        let historyCount = visibleHistoryAlerts.filter {
            !$0.isRead && $0.category == category
        }.count
        let operationalCount = liveAlerts.filter {
            !$0.isRead && $0.category == category
        }.count
        return historyCount + operationalCount
    }

    /// Active (unacknowledged) alert count including live work items
    var activeCount: Int {
        visibleHistoryAlerts.count
            + liveAlerts.count
            + liveInventoryAlerts.count
    }

    func activeCount(in category: NotificationAlert.AlertCategory) -> Int {
        if category == .all { return activeCount }
        return filtered(by: category).count
    }

    private var cancellables = Set<AnyCancellable>()
    private let maxAlerts = 200 // Keep last 200 alerts in memory
    private var activeMerchantId: String?
    private var activeHistoryLanguageCode = LocalizationManager.shared.currentLanguage.rawValue
    private var inventoryFirstSeenAt: [String: Date] = [:]
    private var inventoryOccurrencesLoaded = false
    private var activeInventoryBranchId = "all"
    private var isCurrentScope: Bool {
        let current = (UserDefaults.standard.string(forKey: "active_merchant_id") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return !current.isEmpty && activeMerchantId == current
    }

    private init() {
        // Subscribe to InAppNotificationManager to auto-capture all alerts
        InAppNotificationManager.shared.$latestNotification
            .compactMap { $0 }
            .sink { [weak self] notification in
                self?.captureFromInApp(notification)
            }
            .store(in: &cancellables)

        // Subscribe to SyncEngine active service requests
        SyncEngine.shared.$activeRequests
            .removeDuplicates()
            .sink { [weak self] requests in
                self?.captureServiceRequests(requests)
            }
            .store(in: &cancellables)

        LocalizationManager.shared.$currentLanguage
            .dropFirst()
            .sink { [weak self] _ in
                self?.switchHistoryLanguage()
            }
            .store(in: &cancellables)
    }

    // MARK: - Capture from InAppNotificationManager

    private func captureFromInApp(_ notification: InAppNotification) {
        // Avoid double-posting into the Notification Center. Two in-app types
        // reach the store via a SECOND, richer path as well, so we skip them
        // here to prevent duplicate rows:
        //
        //   • .newOrder       → also posted by alertNewCustomerOrder → postAlert
        //                       (correct Quick/Table label, device, item count)
        //   • .serviceRequest → also captured from SyncEngine.$activeRequests via
        //                       captureServiceRequests (has its own dedup by id)
        //
        // The in-app banner is unaffected: it is driven by
        // InAppNotificationManager.activeNotifications, not by this capture.
        // Other types (cooking/delivery/printer/stale-shift) have only this
        // path, so they still flow through to the Notification Center.
        switch notification.type {
        case .newOrder, .serviceRequest, .cookingAlert, .deliveryAlert, .staleShift:
            // Orders and requests already have canonical live rows rebuilt
            // from source state. Stale shifts use one keyed condition row.
            return
        default: break
        }

        let alert = NotificationAlert(
            priority: mapPriority(notification.type),
            category: mapCategory(notification.type),
            title: notification.title,
            message: notification.body,
            device: deviceName(for: notification.type),
            tableNumber: notification.tableNumber,
            orderNumber: extractOrderNumber(notification.title),
            createdAt: notification.createdAt
        )
        addAlert(alert)
    }

    // MARK: - Capture Service Requests

    private var trackedRequestIds = Set<String>()

    private func captureServiceRequests(_ requests: [ServiceRequest]) {
        let pending = requests.filter { $0.status.lowercased() == "pending" }
        let pendingIds = Set(pending.map(\.id))
        if SyncEngine.shared.isFirstSync {
            trackedRequestIds = pendingIds
            return
        }
        trackedRequestIds.formIntersection(pendingIds)
        for request in pending where !trackedRequestIds.contains(request.id) {
            trackedRequestIds.insert(request.id)
            // Live rebuild owns sticky pending-request rows; history only keeps a pulse.
            let alert = NotificationAlert(
                priority: .high,
                category: .customer,
                title: "service_request_alert_title".t,
                message: "\(OrderDisplayIdentity.label(forServiceReference: request.tableNumber)) — \(request.requestType)",
                device: "Customer Web",
                tableNumber: request.tableNumber.hasPrefix("Q-") || request.tableNumber.hasPrefix("ORDER-")
                    ? nil : request.tableNumber,
                orderNumber: nil,
                createdAt: ISO8601DateFormatter().date(from: request.createdAt) ?? Date(),
                liveKey: "req-\(request.id)"
            )
            addAlert(alert)
        }
    }

    // MARK: - Live operational queue (Staff NotificationList parity)

    /// Rebuild the actionable work queue from local orders + pending service requests.
    /// This is what keeps iPad Notification Center aligned with Staff "รอยืนยัน" / ready / preparing.
    func rebuildLiveOperationalAlerts(orders: [Order], serviceRequests: [ServiceRequest]) {
        guard isCurrentScope else { return }
        let readIds = Set(liveAlerts.filter(\.isRead).map(\.id))
        var next: [NotificationAlert] = []

        for order in orders where !order.isDeleted {
            guard !order.items.filter({ !$0.isDeleted }).isEmpty else { continue }
            // Operational order work never crosses the local end-of-day boundary.
            // The underlying order remains available in reports/audit history.
            guard NotificationDeliveryPolicy.isInCurrentBusinessDay(order.createdAt) else { continue }
            let status = order.status.lowercased()
            guard status != "cancelled" && status != "completed" else { continue }

            let sessionActive = order.tableSession?.isActive == true
            let awaiting = order.isAwaitingStaffApproval
            // Drop stale approval rows after phone confirm + table clear: if the
            // session is gone/inactive and staff already confirmed, do not keep
            // "รอยืนยันออเดอร์เว็บ" sticky as อ่านแล้ว.
            if awaiting, !sessionActive, order.isStaffConfirmed { continue }
            if awaiting, !sessionActive, status == "served" { continue }

            let isActive = awaiting
                || status == "ready"
                || status == "preparing"
                || status == "cooking"
            guard isActive else { continue } // Notification Center shows active work only

            let tableSystemEnabled = UserDefaults.standard.object(forKey: "enable_table_system") as? Bool ?? true
            let identity = OrderDisplayIdentity(order: order, tableSystemEnabled: tableSystemEnabled)
            let items = order.items.filter { !$0.isDeleted }
            let itemsSummary = items
                .prefix(6)
                .map { "\($0.quantity)x \($0.itemName.isEmpty ? ($0.menuItem?.name ?? "Item") : $0.itemName)" }
                .joined(separator: ", ")
            let more = items.count > 6 ? " +\(items.count - 6)" : ""

            let (title, category, priority, device): (String, NotificationAlert.AlertCategory, NotificationAlert.AlertPriority, String)
            if awaiting {
                title = "\("notif_order_awaiting_approval".t) — \(order.orderNumber)"
                category = .orders
                priority = .high
                device = order.orderSource == "web" ? "Customer Web" : "Staff App"
            } else if status == "ready" {
                title = "\("alert_order_ready_title".t) — \(order.orderNumber)"
                category = .orders
                priority = .high
                device = "Kitchen Display"
            } else {
                let minutes = Int(Date().timeIntervalSince(order.createdAt) / 60)
                title = minutes >= 10
                    ? "\("notif_kitchen_delayed".t) \(minutes) \("notif_minutes".t) — \(order.orderNumber)"
                    : "\("notif_kitchen_preparing".t) — \(order.orderNumber)"
                category = .kitchen
                priority = minutes >= 10 ? .critical : .medium
                device = "Kitchen Display"
            }

            let message = "\(identity.primaryLabel) · \(items.count) \("alert_items_suffix".t) · \(itemsSummary)\(more)"
            let key = "order-\(order.id.uuidString.lowercased())"
            next.append(NotificationAlert(
                id: Self.stableUUID(from: key),
                priority: priority,
                category: category,
                title: title,
                message: message,
                device: device,
                tableNumber: identity.isQuickService ? nil : identity.tableNumber,
                orderNumber: order.orderNumber,
                createdAt: order.createdAt,
                liveKey: key,
                isLive: true,
                isRead: readIds.contains(Self.stableUUID(from: key))
            ))
        }

        for request in serviceRequests where request.status.lowercased() == "pending" {
            guard let requestDate = ISO8601DateFormatter().date(from: request.createdAt),
                  NotificationDeliveryPolicy.isInCurrentBusinessDay(requestDate) else { continue }
            let isBill = request.requestType.lowercased().contains("bill")
                || request.requestType.lowercased().contains("check")
            let key = "req-\(request.id)"
            next.append(NotificationAlert(
                id: Self.stableUUID(from: key),
                priority: isBill ? .high : .medium,
                category: .customer,
                title: "\("notif_customer_service_request".t) — \(OrderDisplayIdentity.label(forServiceReference: request.tableNumber))",
                message: request.requestType,
                device: "Customer Web",
                tableNumber: request.tableNumber.hasPrefix("Q-") || request.tableNumber.hasPrefix("ORDER-")
                    ? nil : request.tableNumber,
                orderNumber: nil,
                createdAt: requestDate,
                liveKey: key,
                isLive: true,
                isRead: readIds.contains(Self.stableUUID(from: key))
            ))
        }

        next.sort { lhs, rhs in
            if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
            return lhs.createdAt > rhs.createdAt
        }
        liveAlerts = next

        // History pulses (ออเดอร์ใหม่ / รอยืนยัน) stay after mark-read; clear them
        // once the matching order is confirmed or no longer in the live queue.
        let liveOrderNumbers = Set(next.compactMap(\.orderNumber))
        let resolvedNumbers = Set(
            orders
                .filter {
                    !$0.isDeleted &&
                    ($0.isStaffConfirmed
                     || ["completed", "cancelled", "served"].contains($0.status.lowercased())
                     || !$0.isAwaitingStaffApproval)
                }
                .map(\.orderNumber)
        )
        resolveOrderHistoryAlerts(
            resolvedOrderNumbers: resolvedNumbers,
            stillLiveOrderNumbers: liveOrderNumbers
        )
    }

    /// Mark matching history events as read after the order is resolved.
    ///
    /// Resolution must not acknowledge (hide) the history row. The live work
    /// item already disappears when it leaves the actionable states; keeping
    /// the event history visible prevents a notification from appearing
    /// briefly and then vanishing without an audit trail.
    func resolveOrderHistoryAlerts(
        resolvedOrderNumbers: Set<String>,
        stillLiveOrderNumbers: Set<String>
    ) {
        guard !resolvedOrderNumbers.isEmpty else { return }
        for i in alerts.indices {
            guard !alerts[i].isAcknowledged,
                  alerts[i].category == .orders,
                  let orderNumber = alerts[i].orderNumber,
                  resolvedOrderNumbers.contains(orderNumber),
                  !stillLiveOrderNumbers.contains(orderNumber) else { continue }
            alerts[i].isRead = true
        }
        persistHistory()
    }

    /// Rebuild sticky inventory alerts from current branch stock levels.
    func rebuildLiveInventoryAlerts(items: [InventoryItem]) {
        guard isCurrentScope else { return }
        let currentBranch = (BranchContext.shared.activeBranchIDString)
            .lowercased()
        if currentBranch != activeInventoryBranchId {
            persistInventoryOccurrences()
            activeInventoryBranchId = currentBranch
            inventoryFirstSeenAt.removeAll()
            inventoryOccurrencesLoaded = false
        }
        loadInventoryOccurrencesIfNeeded()
        let readIds = Set(liveInventoryAlerts.filter(\.isRead).map(\.id))
        var next: [NotificationAlert] = []

        for item in items {
            let qty = item.currentQuantity
            if qty <= 0 {
                let key = "inv-out-\(item.id.uuidString)"
                let id = Self.stableUUID(from: key)
                next.append(NotificationAlert(
                    id: id,
                    priority: .critical,
                    category: .inventory,
                    title: "alert_out_of_stock_title".t,
                    message: "\(item.name) — \(String(format: "%.1f", qty)) \(item.unit)",
                    device: "Inventory",
                    inventoryItemId: item.id.uuidString,
                    createdAt: inventoryFirstSeenAt[key] ?? Date(),
                    liveKey: key,
                    isLive: true,
                    isRead: readIds.contains(id)
                ))
            } else if qty <= item.reorderLevel {
                let key = "inv-low-\(item.id.uuidString)"
                let id = Self.stableUUID(from: key)
                next.append(NotificationAlert(
                    id: id,
                    priority: .medium,
                    category: .inventory,
                    title: "alert_low_stock_title".t,
                    message: "\(item.name) — \(String(format: "%.1f", qty))/\(String(format: "%.0f", item.reorderLevel)) " + "alert_low_stock_suffix".t,
                    device: "Inventory",
                    inventoryItemId: item.id.uuidString,
                    createdAt: inventoryFirstSeenAt[key] ?? Date(),
                    liveKey: key,
                    isLive: true,
                    isRead: readIds.contains(id)
                ))
            }
        }

        next.sort { lhs, rhs in
            if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
            return lhs.title < rhs.title
        }
        let activeKeys = Set(next.compactMap(\.liveKey))
        inventoryFirstSeenAt = inventoryFirstSeenAt.filter { activeKeys.contains($0.key) }
        for key in activeKeys where inventoryFirstSeenAt[key] == nil {
            inventoryFirstSeenAt[key] = next.first(where: { $0.liveKey == key })?.createdAt ?? Date()
        }
        persistInventoryOccurrences()
        liveInventoryAlerts = next
    }

    // MARK: - Public API

    /// Notifications are process-local; never carry them across merchant sessions.
    /// First bind (nil → merchant) must NOT wipe alerts already posted by sync.
    func activateScope(merchantId: String) {
        let normalized = merchantId.lowercased()
        guard !normalized.isEmpty else {
            deactivateScope()
            return
        }
        if activeMerchantId == normalized {
            if activeHistoryLanguageCode != LocalizationManager.shared.currentLanguage.rawValue {
                switchHistoryLanguage()
            }
            return
        }
        InAppNotificationManager.shared.clearAll()
        SyncEngine.shared.resetNotificationRuntimeState()
        isInitialReconciliationComplete = false
        activeMerchantId = normalized
        activeHistoryLanguageCode = LocalizationManager.shared.currentLanguage.rawValue
        activeInventoryBranchId = (
            BranchContext.shared.activeBranchIDString
        ).lowercased()
        alerts.removeAll()
        liveAlerts.removeAll()
        liveInventoryAlerts.removeAll()
        trackedRequestIds.removeAll()
        inventoryFirstSeenAt.removeAll()
        inventoryOccurrencesLoaded = false
        loadHistory()
        cleanup(olderThan: 24 * 30)
    }

    func deactivateScope() {
        if let activeMerchantId {
            let prefix = "notification_inventory_occurrences.v1.\(activeMerchantId)."
            let scopedPrefixes = [
                prefix,
                "stock_oos_pulse_ids.\(activeMerchantId).",
                "stock_auto_disabled_menu_ids.\(activeMerchantId).",
                "last_stale_shift_notification_time.\(activeMerchantId)."
            ]
            for key in UserDefaults.standard.dictionaryRepresentation().keys {
                if scopedPrefixes.contains(where: key.hasPrefix) {
                    UserDefaults.standard.removeObject(forKey: key)
                }
            }
            for language in AppLanguage.allCases {
                UserDefaults.standard.removeObject(
                    forKey: historyKey(
                        merchantId: activeMerchantId,
                        languageCode: language.rawValue
                    )
                )
            }
            UserDefaults.standard.removeObject(forKey: "notification_history.v1.\(activeMerchantId)")
        }
        activeMerchantId = nil
        isInitialReconciliationComplete = false
        alerts.removeAll()
        liveAlerts.removeAll()
        liveInventoryAlerts.removeAll()
        trackedRequestIds.removeAll()
        inventoryFirstSeenAt.removeAll()
        inventoryOccurrencesLoaded = false
        InAppNotificationManager.shared.clearAll()
    }

    /// Publish the reconciled badge value once, after bootstrap has finished.
    /// Calling this repeatedly for foreground refreshes is intentionally safe.
    func completeInitialReconciliation() {
        isInitialReconciliationComplete = true
    }

    /// History strings are stored per selected language. Live alerts rebuild
    /// from source data; history from another language is never mixed into the
    /// current UI.
    func switchHistoryLanguage() {
        let nextLanguage = LocalizationManager.shared.currentLanguage.rawValue
        guard activeMerchantId != nil, activeHistoryLanguageCode != nextLanguage else { return }
        persistHistory()
        activeHistoryLanguageCode = nextLanguage
        alerts.removeAll()
        InAppNotificationManager.shared.clearAll()
        loadHistory()
    }

    /// Post a custom alert from anywhere in the app (e.g. payment failure, sync error)
    func postAlert(
        priority: NotificationAlert.AlertPriority,
        category: NotificationAlert.AlertCategory,
        title: String,
        message: String,
        device: String = "System",
        tableNumber: String? = nil,
        orderNumber: String? = nil,
        inventoryItemId: String? = nil
    ) {
        let alert = NotificationAlert(
            priority: priority,
            category: category,
            title: title,
            message: message,
            device: device,
            tableNumber: tableNumber,
            orderNumber: orderNumber,
            inventoryItemId: inventoryItemId,
            createdAt: Date()
        )
        addAlert(alert)
    }

    /// Create or refresh one unresolved condition without producing duplicate
    /// rows. The first-seen timestamp is preserved so age remains meaningful.
    func upsertConditionAlert(
        key: String,
        priority: NotificationAlert.AlertPriority,
        category: NotificationAlert.AlertCategory,
        title: String,
        message: String,
        device: String = "System"
    ) {
        guard isCurrentScope else { return }
        // Remove legacy unkeyed copies (including older technical-message rows)
        // when the same condition is first upgraded to the keyed model.
        alerts.removeAll {
            $0.liveKey == nil && $0.category == category && $0.title == title
        }
        if let index = alerts.firstIndex(where: { $0.liveKey == key && !$0.isAcknowledged }) {
            let current = alerts[index]
            alerts[index] = NotificationAlert(
                id: current.id,
                priority: priority,
                category: category,
                title: title,
                message: message,
                device: device,
                createdAt: current.createdAt,
                liveKey: key,
                isLive: true,
                isRead: current.isRead
            )
            persistHistory()
            return
        }
        // A recovered condition may recur later. Keep only one identity so
        // SwiftUI never receives duplicate stable IDs.
        alerts.removeAll { $0.liveKey == key }
        addAlert(NotificationAlert(
            id: Self.stableUUID(from: key),
            priority: priority,
            category: category,
            title: title,
            message: message,
            device: device,
            liveKey: key,
            isLive: true
        ))
    }

    /// Resolve a condition only when the underlying state has recovered.
    func resolveConditionAlert(key: String) {
        guard let index = alerts.firstIndex(where: { $0.liveKey == key && !$0.isAcknowledged }) else { return }
        alerts[index].isRead = true
        alerts[index].isAcknowledged = true
        persistHistory()
    }

    func resolveStaleShiftConditions(except activeKeys: Set<String>) {
        var changed = false
        for index in alerts.indices {
            guard let key = alerts[index].liveKey,
                  key.hasPrefix("stale-shift-"),
                  !activeKeys.contains(key),
                  !alerts[index].isAcknowledged else { continue }
            alerts[index].isRead = true
            alerts[index].isAcknowledged = true
            changed = true
        }
        if changed { persistHistory() }
    }

    /// Mark alert as read
    func markRead(_ alertId: UUID) {
        if let idx = liveAlerts.firstIndex(where: { $0.id == alertId }) {
            liveAlerts[idx].isRead = true
        }
        if let idx = alerts.firstIndex(where: { $0.id == alertId }) {
            alerts[idx].isRead = true
        }
        if let idx = liveInventoryAlerts.firstIndex(where: { $0.id == alertId }) {
            liveInventoryAlerts[idx].isRead = true
        }
        persistHistory()
    }

    func markAllRead() {
        for i in alerts.indices where !alerts[i].isAcknowledged { alerts[i].isRead = true }
        for i in liveAlerts.indices { liveAlerts[i].isRead = true }
        for i in liveInventoryAlerts.indices { liveInventoryAlerts[i].isRead = true }
        persistHistory()
    }

    /// Acknowledge (dismiss) alert — live rows ignore this (they clear when work is done)
    func acknowledge(_ alertId: UUID) {
        if liveAlerts.contains(where: { $0.id == alertId }) { return }
        if let idx = alerts.firstIndex(where: { $0.id == alertId }) {
            if alerts[idx].isLive { return }
            alerts[idx].isAcknowledged = true
        }
        persistHistory()
    }

    /// Acknowledge all history alerts (live work queue stays until resolved)
    func acknowledgeAll() {
        for i in alerts.indices where !alerts[i].isLive {
            alerts[i].isAcknowledged = true
            alerts[i].isRead = true
        }
        persistHistory()
    }

    /// Get alerts filtered by category — live work + unacknowledged history
    func filtered(by category: NotificationAlert.AlertCategory) -> [NotificationAlert] {
        let history = visibleHistoryAlerts
        let merged = (liveAlerts + liveInventoryAlerts + history).sorted { lhs, rhs in
            if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
            return lhs.createdAt > rhs.createdAt
        }
        if category == .all { return merged }
        return merged.filter { $0.category == category }
    }

    private var visibleHistoryAlerts: [NotificationAlert] {
        let liveKeys = Set(liveAlerts.compactMap(\.liveKey)).union(liveInventoryAlerts.compactMap(\.liveKey))
        let liveOrderNumbers = Set(liveAlerts.compactMap(\.orderNumber))
        return alerts.filter { alert in
            guard !alert.isAcknowledged else { return false }
            if !alert.isLive {
                guard NotificationDeliveryPolicy.shouldShowHistory(
                    categoryRawValue: alert.category.rawValue,
                    createdAt: alert.createdAt
                ) else { return false }
            }
            if let key = alert.liveKey, liveKeys.contains(key) { return false }
            if NotificationDeliveryPolicy.historyDuplicatesLiveOrder(
                historyOrderNumber: alert.orderNumber,
                liveOrderNumbers: liveOrderNumbers
            ) {
                return false
            }
            return true
        }
    }

    /// Clear acknowledged alerts older than X hours
    func cleanup(olderThan hours: Int = 24) {
        let cutoff = Date().addingTimeInterval(-TimeInterval(hours * 3600))
        alerts.removeAll { $0.isAcknowledged && $0.createdAt < cutoff }
        persistHistory()
    }

    // MARK: - Private Helpers

    private func addAlert(_ alert: NotificationAlert) {
        guard isCurrentScope else { return }
        alerts.insert(alert, at: 0)
        // Trim to maxAlerts
        if alerts.count > maxAlerts {
            alerts = Array(alerts.prefix(maxAlerts))
        }
        persistHistory()
    }

    private func historyKey(merchantId: String, languageCode: String) -> String {
        "notification_history.v2.\(merchantId).\(languageCode)"
    }

    private func inventoryOccurrenceKey(merchantId: String) -> String {
        "notification_inventory_occurrences.v1.\(merchantId).\(activeInventoryBranchId)"
    }

    private func loadInventoryOccurrencesIfNeeded() {
        guard !inventoryOccurrencesLoaded, let activeMerchantId else { return }
        inventoryOccurrencesLoaded = true
        let raw = UserDefaults.standard.dictionary(
            forKey: inventoryOccurrenceKey(merchantId: activeMerchantId)
        ) as? [String: Double] ?? [:]
        inventoryFirstSeenAt = raw.mapValues(Date.init(timeIntervalSince1970:))
    }

    private func persistInventoryOccurrences() {
        guard let activeMerchantId else { return }
        let raw = inventoryFirstSeenAt.mapValues(\.timeIntervalSince1970)
        UserDefaults.standard.set(
            raw,
            forKey: inventoryOccurrenceKey(merchantId: activeMerchantId)
        )
    }

    private func persistHistory() {
        guard let activeMerchantId,
              let data = try? JSONEncoder().encode(alerts) else { return }
        UserDefaults.standard.set(
            data,
            forKey: historyKey(
                merchantId: activeMerchantId,
                languageCode: activeHistoryLanguageCode
            )
        )
    }

    private func loadHistory() {
        guard let activeMerchantId,
              let data = UserDefaults.standard.data(
                forKey: historyKey(
                    merchantId: activeMerchantId,
                    languageCode: activeHistoryLanguageCode
                )
              ),
              let restored = try? JSONDecoder().decode([NotificationAlert].self, from: data) else {
            return
        }
        var normalized: [NotificationAlert] = []
        var hasSyncCondition = false
        for alert in restored.prefix(maxAlerts) {
            let isLegacyTechnicalSync = alert.category == .system && (
                alert.message.localizedCaseInsensitiveContains("PGRST") ||
                alert.message.localizedCaseInsensitiveContains("schema cache") ||
                alert.message.localizedCaseInsensitiveContains("Server returned error") ||
                alert.message.localizedCaseInsensitiveContains("HTTP 400")
            )
            guard isLegacyTechnicalSync else {
                normalized.append(alert)
                continue
            }
            // Collapse persisted raw backend errors from older builds into one
            // user-facing condition. A successful sync resolves this row.
            guard !hasSyncCondition else { continue }
            hasSyncCondition = true
            normalized.append(NotificationAlert(
                id: Self.stableUUID(from: "system-sync-failed"),
                priority: .medium,
                category: .system,
                title: "alert_sync_failed_title".t,
                message: "alert_sync_failed_msg".t,
                device: "Master iPad",
                createdAt: alert.createdAt,
                liveKey: "system-sync-failed",
                isLive: true,
                isRead: alert.isRead,
                isAcknowledged: alert.isAcknowledged
            ))
        }
        alerts = normalized
        persistHistory()
    }

    private func mapPriority(_ type: InAppNotificationType) -> NotificationAlert.AlertPriority {
        switch type {
        case .cookingAlert, .deliveryAlert, .printerAlert: return .critical
        case .newOrder: return .high
        case .serviceRequest: return .medium
        case .staleShift: return .medium
        }
    }


    private func mapCategory(_ type: InAppNotificationType) -> NotificationAlert.AlertCategory {
        switch type {
        case .newOrder: return .orders
        case .serviceRequest: return .customer
        case .cookingAlert: return .kitchen
        case .deliveryAlert: return .orders
        case .staleShift, .printerAlert: return .system
        }
    }


    private func deviceName(for type: InAppNotificationType) -> String {
        switch type {
        case .newOrder: return "Customer Web"
        case .serviceRequest: return "Customer Web"
        case .cookingAlert: return "Kitchen Display"
        case .deliveryAlert: return "Delivery System"
        case .staleShift: return "System"
        case .printerAlert: return "Printer"
        }
    }


    private func extractOrderNumber(_ title: String) -> String? {
        // Extract #XXX from title
        if let range = title.range(of: "#\\d+", options: .regularExpression) {
            return String(title[range])
        }
        return nil
    }

    private static func stableUUID(from key: String) -> UUID {
        let digest = SHA256.hash(data: Data(key.utf8))
        var bytes = Array(digest.prefix(16))
        // RFC 4122 variant bits
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
