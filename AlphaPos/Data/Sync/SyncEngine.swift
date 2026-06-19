import Foundation
import SwiftData
import Combine
import UserNotifications
import UIKit
import os

struct ServiceRequest: Identifiable, Codable, Hashable {
    var id: String
    var tableNumber: String
    var requestType: String
    var status: String
    var createdAt: String
}

final class SyncEngine: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = SyncEngine()

    enum SyncStatus {
        case idle
        case syncing
        case error
        case offline

        var localizedDescription: String {
            switch self {
            case .idle: return "Synced"
            case .syncing: return "Syncing..."
            case .error: return "Sync Error"
            case .offline: return "Offline"
            }
        }
    }

    @Published var syncStatus: SyncStatus = .idle
    @Published var lastSyncedAt: Date? = nil
    @Published var activeRequests: [ServiceRequest] = []
    private var cachedModelContext: ModelContext?
    private static let alertTimesLock = OSAllocatedUnfairLock()
    private static var _lastAlertTimes: [UUID: Date] = [:]
    static func getAlertTime(_ key: UUID) -> Date? {
        alertTimesLock.lock(); defer { alertTimesLock.unlock() }
        return _lastAlertTimes[key]
    }
    static func setAlertTime(_ key: UUID, _ value: Date) {
        alertTimesLock.lock(); defer { alertTimesLock.unlock() }
        _lastAlertTimes[key] = value
    }
    static func removeAlertTime(_ key: UUID) {
        alertTimesLock.lock(); defer { alertTimesLock.unlock() }
        _lastAlertTimes.removeValue(forKey: key)
    }

    private var notifiedRequestIds = Set<String>()
    private var isFirstSync = true

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        requestNotificationPermission()
        setupLifecycleObservers()
    }

    private func remoteDouble(_ value: Any?, fallback defaultValue: Double = 0.0) -> Double {
        value as? Double ?? (value as? NSNumber)?.doubleValue ?? (value as? String).flatMap(Double.init) ?? defaultValue
    }

    private func remoteInt(_ value: Any?, fallback defaultValue: Int = 0) -> Int {
        value as? Int ?? (value as? NSNumber)?.intValue ?? (value as? String).flatMap(Int.init) ?? defaultValue
    }

    private func remoteBool(_ value: Any?, fallback defaultValue: Bool = false) -> Bool {
        if let boolValue = value as? Bool { return boolValue }
        if let intValue = value as? Int { return intValue != 0 }
        if let stringValue = value as? String {
            return ["true", "1", "yes"].contains(stringValue.lowercased())
        }
        return defaultValue
    }

    private func parseISO8601Date(_ value: Any?, fallback defaultValue: Date = Date()) -> Date {
        guard let stringValue = value as? String else { return defaultValue }
        let cleanStr = stringValue.replacingOccurrences(of: " ", with: "T")
        
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: cleanStr) { return d }
        
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        if let d = f2.date(from: cleanStr) { return d }
        
        return defaultValue
    }
    
    private func parseISO8601DateOptional(_ value: Any?) -> Date? {
        guard let stringValue = value as? String else { return nil }
        let cleanStr = stringValue.replacingOccurrences(of: " ", with: "T")
        
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: cleanStr) { return d }
        
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        if let d = f2.date(from: cleanStr) { return d }
        
        return nil
    }

    private func remoteDate(_ value: Any?, fallback defaultValue: Date = Date()) -> Date {
        return parseISO8601Date(value, fallback: defaultValue)
    }

    private func setupLifecycleObservers() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            #if DEBUG
            print("SyncEngine: App returned to foreground. Reconnecting WebSocket...")
            #endif

            // Cancel existing WebSocket task
            self.webSocketTask?.cancel(with: .normalClosure, reason: nil)
            self.webSocketTask = nil

            if let context = self.cachedModelContext {
                self.startRealtimeSync(modelContext: context)
                Task {
                    await self.syncAll(modelContext: context)
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name("merchantTokenDidRefresh"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            #if DEBUG
            print("SyncEngine: JWT token refreshed. Reconnecting WebSocket...")
            #endif
            self.webSocketTask?.cancel(with: .normalClosure, reason: nil)
            self.webSocketTask = nil
            self.heartbeatTimer?.invalidate()
            self.heartbeatTimer = nil
            if let context = self.cachedModelContext {
                self.startRealtimeSync(modelContext: context)
            }
        }
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            #if DEBUG
            if granted {
                print("SyncEngine: Notification permission granted.")
            } else if let error = error {
                print("SyncEngine: Notification authorization error: \(error.localizedDescription)")
            }
            #endif
        }
    }

    func triggerLocalNotification(orderNumber: String, tableNumber: String) {
        let content = UNMutableNotificationContent()
        content.title = "New Customer Order!"
        content.body = "Table \(tableNumber) placed order \(orderNumber.suffix(4))"
        content.sound = UNNotificationSound.default
        content.userInfo = [
            "table_number": tableNumber,
            "type": "order"
        ]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            #if DEBUG
            if let error = error {
                print("SyncEngine: Failed to trigger notification: \(error)")
            }
            #endif
        }
    }

    func triggerServiceRequestNotification(tableNumber: String, requestType: String) {
        let content = UNMutableNotificationContent()
        content.title = "🛎️ Staff Call: Table \(tableNumber)"

        let serviceKeyMap = [
            "Bill (Cash)": "Pay Cash",
            "Bill (Card)": "Pay Card",
            "Bill (QR)": "Pay QR",
            "Ice/Water": "Get Water",
            "Extra Utensils": "Utensils",
            "General Help": "Call Staff"
        ]
        let displayType = serviceKeyMap[requestType] ?? requestType
        content.body = "Table \(tableNumber) requested: \(displayType)"
        content.sound = UNNotificationSound.default
        content.userInfo = [
            "table_number": tableNumber,
            "type": "service_request"
        ]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            #if DEBUG
            if let error = error {
                print("SyncEngine: Failed to trigger service request notification: \(error)")
            }
            #endif
        }
      // MARK: - UNUserNotificationCenterDelegate
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.badge, .sound, .banner, .list])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let tableNumber = userInfo["table_number"] as? String {
            NotificationCenter.default.post(
                name: .openTableNotification,
                object: nil,
                userInfo: ["table_number": tableNumber]
            )
        }
        completionHandler()
    }    }

    // Asynchronous task to sync all unsynced data
    func syncAll(modelContext: ModelContext) async {
        // Initialize Realtime WebSocket task
        await MainActor.run {
            self.startRealtimeSync(modelContext: modelContext)
        }

        guard await NetworkManager.shared.isConnected() else {
            #if DEBUG
            print("SyncEngine: Device is offline. Sync task aborted.")
            #endif
            await MainActor.run {
                self.syncStatus = .offline
            }
            return
        }

        await MainActor.run {
            self.syncStatus = .syncing
        }

        #if DEBUG
        print("SyncEngine: Initiating data synchronization...")
        #endif

        // Push local POS edits to cloud
        await syncMerchant()
        await syncSecurityPolicies(modelContext)
        await syncRolePermissions(modelContext)
        await syncMerchantDevices(modelContext)
        await syncStaffSessions(modelContext)
        await syncAuditLogs(modelContext)
        await syncTables(modelContext)
        await syncTableSessions(modelContext)
        await syncFloorPlanImages(modelContext)
        await syncEmployees(modelContext)
        await syncEmployeeShifts(modelContext)
        await syncOrders(modelContext)
        await syncPayments(modelContext)
        await syncOrderDiscounts(modelContext)
        await syncTimecards(modelContext)
        await syncInventoryTransactions(modelContext)
        await syncMenuItems(modelContext)
        await syncPromotions(modelContext)
        await syncPurchaseOrders(modelContext)
        await syncDeliveryPrices(modelContext)
        await syncPrinters(modelContext)
        await syncPrintRoutingRules(modelContext)
        await syncCustomers(modelContext)
        await syncGiftCards(modelContext)
        await syncLoyaltyTransactions(modelContext)

        // Pull remote tables from cloud
        await pullRestaurantTables(modelContext)

        // Pull menu items from Supabase (single source of truth)
        await pullMenuItemsFromSupabase(modelContext)

        // Pull promotions from Supabase
        await pullPromotionsFromSupabase(modelContext)

        // Pull mobile customer orders from cloud
        await pullCustomerOrders(modelContext)

        // Pull active table sessions
        await pullActiveSessions(modelContext)

        // Pull active service requests
        await syncServiceRequests()

        await pullCustomersFromSupabase(modelContext)
        await pullGiftCardsFromSupabase(modelContext)
        await pullLoyaltyTransactionsFromSupabase(modelContext)

        // Check for delayed orders and dispatch alerts
        await checkForDelayedOrders(modelContext: modelContext)

        await MainActor.run {
            self.syncStatus = .idle
            self.lastSyncedAt = Date()
            self.isFirstSync = false
        }

        #if DEBUG
        print("SyncEngine: Sync completed.")
        #endif
    }

    // MARK: - Sync Helpers

    private func syncSecurityPolicies(_ modelContext: ModelContext) async {
        let descriptor = FetchDescriptor<SecurityPolicy>(
            predicate: #Predicate<SecurityPolicy> { $0.isSynced == false }
        )
        guard let policies = try? modelContext.fetch(descriptor), !policies.isEmpty else { return }
        for policy in policies {
            do {
                let success = try await NetworkManager.shared.uploadSecurityPolicy(policy)
                if success { policy.isSynced = true }
            } catch {
                print("SyncEngine [SecurityPolicy Sync Error]: \(error.localizedDescription)")
            }
        }
        try? modelContext.save()
    }

    private func syncRolePermissions(_ modelContext: ModelContext) async {
        let descriptor = FetchDescriptor<Role>(
            predicate: #Predicate<Role> { $0.isSynced == false }
        )
        guard let roles = try? modelContext.fetch(descriptor), !roles.isEmpty else { return }
        for role in roles {
            do {
                let success = try await NetworkManager.shared.replaceRolePermissions(role: role)
                if success { role.isSynced = true }
            } catch {
                print("SyncEngine [RolePermission Sync Error]: \(error.localizedDescription)")
            }
        }
        try? modelContext.save()
    }

    private func syncMerchantDevices(_ modelContext: ModelContext) async {
        let descriptor = FetchDescriptor<MerchantDevice>(
            predicate: #Predicate<MerchantDevice> { $0.isSynced == false }
        )
        guard let devices = try? modelContext.fetch(descriptor), !devices.isEmpty else { return }
        for device in devices {
            do {
                let success = try await NetworkManager.shared.uploadMerchantDevice(device)
                if success { device.isSynced = true }
            } catch {
                print("SyncEngine [MerchantDevice Sync Error]: \(error.localizedDescription)")
            }
        }
        try? modelContext.save()
    }

    private func syncStaffSessions(_ modelContext: ModelContext) async {
        let descriptor = FetchDescriptor<StaffSessionRecord>(
            predicate: #Predicate<StaffSessionRecord> { $0.isSynced == false }
        )
        guard let sessions = try? modelContext.fetch(descriptor), !sessions.isEmpty else { return }
        for session in sessions {
            do {
                let success = try await NetworkManager.shared.uploadStaffSessionRecord(session)
                if success { session.isSynced = true }
            } catch {
                print("SyncEngine [StaffSession Sync Error]: \(error.localizedDescription)")
            }
        }
        try? modelContext.save()
    }

    private func syncAuditLogs(_ modelContext: ModelContext) async {
        let descriptor = FetchDescriptor<AuditLog>(
            predicate: #Predicate<AuditLog> { $0.isSynced == false }
        )
        guard let logs = try? modelContext.fetch(descriptor), !logs.isEmpty else { return }
        for log in logs {
            do {
                if log.isDeleted {
                    _ = try await NetworkManager.shared.deleteAuditLogOnServer(id: log.id)
                    modelContext.delete(log)
                } else {
                    let success = try await NetworkManager.shared.uploadAuditLog(log)
                    if success { log.isSynced = true }
                }
            } catch {
                print("SyncEngine [AuditLog Sync Error]: \(error.localizedDescription)")
            }
        }
        try? modelContext.save()
    }

    private func syncOrders(_ modelContext: ModelContext) async {
        let descriptor = FetchDescriptor<Order>(
            predicate: #Predicate<Order> { $0.isSynced == false }
        )

        guard let orders = try? modelContext.fetch(descriptor), !orders.isEmpty else { return }

        for order in orders {
            if order.isDeleted {
                // Handle soft delete upload and then purge
                do {
                    // Simulate delete on server
                    try await Task.sleep(nanoseconds: 100_000_000)
                    modelContext.delete(order)
                    try modelContext.save()
                } catch {
                    print("SyncEngine [Order Delete Error]: \(error.localizedDescription)")
                }
                continue
            }

            do {
                let success = try await NetworkManager.shared.uploadOrder(order: order)

                if success {
                    order.isSynced = true
                    order.updatedAt = Date()
                    try modelContext.save()
                }
            } catch {
                print("SyncEngine [Order Sync Error]: \(error.localizedDescription)")
            }
        }
    }

    private func syncPayments(_ modelContext: ModelContext) async {
        let descriptor = FetchDescriptor<Payment>(
            predicate: #Predicate<Payment> { $0.isSynced == false }
        )

        guard let payments = try? modelContext.fetch(descriptor), !payments.isEmpty else { return }

        for payment in payments {
            if payment.isDeleted {
                modelContext.delete(payment)
                try? modelContext.save()
                continue
            }

            do {
                let success: Bool
                if let order = payment.order,
                   let tableSession = order.tableSession,
                   let table = tableSession.table {
                    success = try await NetworkManager.shared.completeCheckout(
                        paymentId: payment.id,
                        orderId: order.id,
                        amount: payment.amount,
                        method: payment.paymentMethod,
                        tableNumber: table.tableNumber
                    )
                } else {
                    success = try await NetworkManager.shared.uploadPayment(
                        id: payment.id,
                        orderId: payment.order?.id,
                        amount: payment.amount,
                        method: payment.paymentMethod
                    )
                }

                if success {
                    payment.isSynced = true
                    payment.updatedAt = Date()
                    try modelContext.save()
                }
            } catch {
                print("SyncEngine [Payment Sync Error]: \(error.localizedDescription)")
            }

        }
    }

    private func syncOrderDiscounts(_ modelContext: ModelContext) async {
        let descriptor = FetchDescriptor<OrderDiscount>(
            predicate: #Predicate<OrderDiscount> { $0.isSynced == false }
        )

        guard let discounts = try? modelContext.fetch(descriptor), !discounts.isEmpty else { return }

        for discount in discounts {
            do {
                let success: Bool
                if discount.isDeleted {
                    success = try await NetworkManager.shared.deleteOrderDiscountOnServer(id: discount.id)
                    if success {
                        modelContext.delete(discount)
                        try modelContext.save()
                    }
                } else {
                    success = try await NetworkManager.shared.uploadOrderDiscount(discount)
                    if success {
                        discount.isSynced = true
                        discount.updatedAt = Date()
                        try modelContext.save()
                    }
                }
            } catch {
                print("SyncEngine [OrderDiscount Sync Error]: \(error.localizedDescription)")
            }
        }
    }

    private func syncTimecards(_ modelContext: ModelContext) async {
        let descriptor = FetchDescriptor<Timecard>(
            predicate: #Predicate<Timecard> { $0.isSynced == false }
        )

        guard let timecards = try? modelContext.fetch(descriptor), !timecards.isEmpty else { return }

        for timecard in timecards {
            if timecard.isDeleted {
                modelContext.delete(timecard)
                try? modelContext.save()
                continue
            }

            guard let employeeId = timecard.employee?.id else {
                print("SyncEngine [Timecard Sync Error]: Missing employee relation for timecard \(timecard.id)")
                continue
            }

            // Duplicate detection: before pushing a new clock-in, check if there's
            // already an active timecard for this employee on the server
            if timecard.clockOut == nil {
                let remoteActive = try? await NetworkManager.shared.fetchActiveTimecard(employeeId: employeeId)
                if let remoteActive = remoteActive, remoteActive != timecard.id.uuidString.lowercased() {
                    print("SyncEngine [Timecard Sync]: Remote active timecard found for employee \(employeeId). Merging data into local record.")
                    // Another device created an active timecard — mark ours as a duplicate
                    timecard.status = "pending_audit"
                    timecard.notes = (timecard.notes ?? "") + " [Possible duplicate: remote active timecard exists]"
                }
            }

            let empName = "\(timecard.employee?.firstName ?? "") \(timecard.employee?.lastName ?? "")"
            do {
                let success = try await NetworkManager.shared.uploadTimecard(
                    id: timecard.id, employeeId: employeeId,
                    employeeName: empName,
                    clockIn: timecard.clockIn,
                    clockOut: timecard.clockOut,
                    status: timecard.status,
                    breakDuration: timecard.breakDurationMinutes,
                    overtimeMinutes: timecard.overtimeMinutes,
                    notes: timecard.notes,
                    clockInConfidence: timecard.clockInFaceConfidence,
                    clockOutConfidence: timecard.clockOutFaceConfidence,
                    clockInSelfieUrl: timecard.clockInSelfieUrl,
                    clockOutSelfieUrl: timecard.clockOutSelfieUrl,
                    shiftId: timecard.shift?.id,
                    verifiedByUserId: timecard.verifiedByUserId
                )

                if success {
                    timecard.isSynced = true
                    timecard.updatedAt = Date()
                    try modelContext.save()
                }
            } catch {
                print("SyncEngine [Timecard Sync Error]: \(error.localizedDescription)")
            }
        }
    }

    private func syncCustomers(_ modelContext: ModelContext) async {
        let descriptor = FetchDescriptor<Customer>(
            predicate: #Predicate<Customer> { $0.isDeleted == true || $0.isSynced == false }
        )
        guard let customers = try? modelContext.fetch(descriptor), !customers.isEmpty else { return }
        for customer in customers {
            do {
                if customer.isDeleted {
                    if try await NetworkManager.shared.deleteCustomerOnServer(id: customer.id) {
                        modelContext.delete(customer)
                    }
                } else if try await NetworkManager.shared.uploadCustomer(customer: customer) {
                    customer.isSynced = true
                    customer.updatedAt = Date()
                }
            } catch {
                print("SyncEngine [Customer Push Error]: \(error.localizedDescription)")
            }
        }
        try? modelContext.save()
    }

    private func pullCustomersFromSupabase(_ modelContext: ModelContext) async {
        do {
            let remoteCustomers = try await NetworkManager.shared.fetchCustomersFromSupabase()
            guard !remoteCustomers.isEmpty else { return }
            let locals = (try? modelContext.fetch(FetchDescriptor<Customer>())) ?? []
            var localById = Dictionary(uniqueKeysWithValues: locals.map { ($0.id.uuidString.lowercased(), $0) })

            for remote in remoteCustomers {
                guard let idStr = remote["id"] as? String,
                      let id = UUID(uuidString: idStr),
                      let name = remote["name"] as? String else { continue }
                let updatedAt = remoteDate(remote["updated_at"], fallback: .distantPast)

                if let local = localById[idStr.lowercased()] {
                    guard local.isSynced, updatedAt > local.updatedAt else { continue }
                    if local.isDeleted { continue }
                    local.name = name
                    local.email = remote["email"] as? String
                    local.phone = remote["phone"] as? String
                    local.taxId = remote["tax_id"] as? String
                    local.address = remote["address"] as? String
                    local.loyaltyPoints = remoteInt(remote["loyalty_points"])
                    local.membershipTier = remote["membership_tier"] as? String ?? "standard"
                    local.totalSpend = remoteDouble(remote["total_spend"])
                    local.visitCount = remoteInt(remote["visit_count"])
                    local.notes = remote["notes"] as? String
                    local.allergies = remote["allergies"] as? String
                    local.preferences = remote["preferences"] as? String
                    if let dobStr = remote["date_of_birth"] as? String {
                        local.dateOfBirth = parseISO8601DateOptional(dobStr)
                    }
                    local.updatedAt = updatedAt
                    local.isSynced = true
                } else {
                    let dob = (remote["date_of_birth"] as? String).flatMap { parseISO8601DateOptional($0) }
                    let customer = Customer(
                        id: id,
                        name: name,
                        email: remote["email"] as? String,
                        phone: remote["phone"] as? String,
                        taxId: remote["tax_id"] as? String,
                        address: remote["address"] as? String,
                        loyaltyPoints: remoteInt(remote["loyalty_points"]),
                        membershipTier: remote["membership_tier"] as? String ?? "standard",
                        totalSpend: remoteDouble(remote["total_spend"]),
                        visitCount: remoteInt(remote["visit_count"]),
                        notes: remote["notes"] as? String,
                        dateOfBirth: dob,
                        allergies: remote["allergies"] as? String,
                        preferences: remote["preferences"] as? String,
                        isSynced: true,
                        isDeleted: false,
                        updatedAt: updatedAt == .distantPast ? Date() : updatedAt,
                        createdAt: remoteDate(remote["created_at"], fallback: Date())
                    )
                    modelContext.insert(customer)
                    localById[idStr.lowercased()] = customer
                }
            }
            try? modelContext.save()
        } catch {
            print("SyncEngine [Customer Pull Error]: \(error.localizedDescription)")
        }
    }

    private func syncGiftCards(_ modelContext: ModelContext) async {
        let descriptor = FetchDescriptor<GiftCard>(
            predicate: #Predicate<GiftCard> { $0.isDeleted == true || $0.isSynced == false }
        )
        guard let cards = try? modelContext.fetch(descriptor), !cards.isEmpty else { return }
        for card in cards {
            do {
                if card.isDeleted {
                    if try await NetworkManager.shared.deleteGiftCardOnServer(id: card.id) {
                        modelContext.delete(card)
                    }
                } else if try await NetworkManager.shared.uploadGiftCard(card) {
                    card.isSynced = true
                    card.updatedAt = Date()
                }
            } catch {
                print("SyncEngine [GiftCard Push Error]: \(error.localizedDescription)")
            }
        }
        try? modelContext.save()
    }

    private func pullGiftCardsFromSupabase(_ modelContext: ModelContext) async {
        do {
            let remoteCards = try await NetworkManager.shared.fetchGiftCardsFromSupabase()
            guard !remoteCards.isEmpty else { return }
            let locals = (try? modelContext.fetch(FetchDescriptor<GiftCard>())) ?? []
            var localById = Dictionary(uniqueKeysWithValues: locals.map { ($0.id.uuidString.lowercased(), $0) })

            for remote in remoteCards {
                guard let idStr = remote["id"] as? String,
                      let id = UUID(uuidString: idStr),
                      let cardNumber = remote["card_number"] as? String else { continue }
                let updatedAt = remoteDate(remote["updated_at"], fallback: .distantPast)

                var customer: Customer? = nil
                if let customerIdStr = remote["customer_id"] as? String, let customerId = UUID(uuidString: customerIdStr) {
                    customer = (try? modelContext.fetch(FetchDescriptor<Customer>(predicate: #Predicate<Customer> { $0.id == customerId })))?.first
                }

                let expiresAt = (remote["expires_at"] as? String).flatMap { parseISO8601DateOptional($0) }

                if let local = localById[idStr.lowercased()] {
                    guard local.isSynced, updatedAt > local.updatedAt else { continue }
                    if local.isDeleted { continue }
                    local.cardNumber = cardNumber
                    local.balance = remoteDouble(remote["balance"])
                    local.initialValue = remoteDouble(remote["initial_value"])
                    local.customer = customer
                    local.status = remote["status"] as? String ?? "active"
                    local.expiresAt = expiresAt
                    local.updatedAt = updatedAt
                    local.isSynced = true
                } else {
                    let card = GiftCard(
                        id: id,
                        cardNumber: cardNumber,
                        balance: remoteDouble(remote["balance"]),
                        initialValue: remoteDouble(remote["initial_value"]),
                        customer: customer,
                        status: remote["status"] as? String ?? "active",
                        expiresAt: expiresAt,
                        isSynced: true,
                        isDeleted: false,
                        updatedAt: updatedAt == .distantPast ? Date() : updatedAt
                    )
                    modelContext.insert(card)
                    localById[idStr.lowercased()] = card
                }
            }
            try? modelContext.save()
        } catch {
            print("SyncEngine [GiftCard Pull Error]: \(error.localizedDescription)")
        }
    }

    private func syncLoyaltyTransactions(_ modelContext: ModelContext) async {
        let descriptor = FetchDescriptor<LoyaltyTransaction>(
            predicate: #Predicate<LoyaltyTransaction> { $0.isDeleted == true || $0.isSynced == false }
        )
        guard let txns = try? modelContext.fetch(descriptor), !txns.isEmpty else { return }
        for txn in txns {
            do {
                if txn.isDeleted {
                    if try await NetworkManager.shared.deleteLoyaltyTransactionOnServer(id: txn.id) {
                        modelContext.delete(txn)
                    }
                } else if try await NetworkManager.shared.uploadLoyaltyTransaction(txn) {
                    txn.isSynced = true
                    txn.updatedAt = Date()
                }
            } catch {
                print("SyncEngine [LoyaltyTransaction Push Error]: \(error.localizedDescription)")
            }
        }
        try? modelContext.save()
    }

    private func pullLoyaltyTransactionsFromSupabase(_ modelContext: ModelContext) async {
        do {
            let remoteTxns = try await NetworkManager.shared.fetchLoyaltyTransactionsFromSupabase()
            guard !remoteTxns.isEmpty else { return }
            let locals = (try? modelContext.fetch(FetchDescriptor<LoyaltyTransaction>())) ?? []
            var localById = Dictionary(uniqueKeysWithValues: locals.map { ($0.id.uuidString.lowercased(), $0) })

            for remote in remoteTxns {
                guard let idStr = remote["id"] as? String,
                      let id = UUID(uuidString: idStr) else { continue }
                let updatedAt = remoteDate(remote["updated_at"], fallback: .distantPast)

                var customer: Customer? = nil
                if let customerIdStr = remote["customer_id"] as? String, let customerId = UUID(uuidString: customerIdStr) {
                    customer = (try? modelContext.fetch(FetchDescriptor<Customer>(predicate: #Predicate<Customer> { $0.id == customerId })))?.first
                }

                var order: Order? = nil
                if let orderIdStr = remote["order_id"] as? String, let orderId = UUID(uuidString: orderIdStr) {
                    order = (try? modelContext.fetch(FetchDescriptor<Order>(predicate: #Predicate<Order> { $0.id == orderId })))?.first
                }

                if let local = localById[idStr.lowercased()] {
                    guard local.isSynced, updatedAt > local.updatedAt else { continue }
                    if local.isDeleted { continue }
                    local.customer = customer
                    local.order = order
                    local.transactionType = remote["transaction_type"] as? String ?? "earn"
                    local.points = remoteInt(remote["points"])
                    local.pointsBalanceAfter = remoteInt(remote["points_balance_after"])
                    local.transactionDescription = remote["description"] as? String
                    local.updatedAt = updatedAt
                    local.isSynced = true
                } else {
                    let txn = LoyaltyTransaction(
                        id: id,
                        customer: customer,
                        order: order,
                        transactionType: remote["transaction_type"] as? String ?? "earn",
                        points: remoteInt(remote["points"]),
                        pointsBalanceAfter: remoteInt(remote["points_balance_after"]),
                        transactionDescription: remote["description"] as? String,
                        isSynced: true,
                        isDeleted: false,
                        updatedAt: updatedAt == .distantPast ? Date() : updatedAt
                    )
                    modelContext.insert(txn)
                    localById[idStr.lowercased()] = txn
                }
            }
            try? modelContext.save()
        } catch {
            print("SyncEngine [LoyaltyTransaction Pull Error]: \(error.localizedDescription)")
        }
    }

    // MARK: - Master Data Sync Loop

    private func syncCategories(_ modelContext: ModelContext) async {
        let descriptor = FetchDescriptor<Category>(
            predicate: #Predicate<Category> { $0.isDeleted == true || $0.isSynced == false }
        )
        guard let categories = try? modelContext.fetch(descriptor), !categories.isEmpty else { return }
        for category in categories {
            do {
                if category.isDeleted {
                    if try await NetworkManager.shared.deleteCategoryOnServer(id: category.id) { modelContext.delete(category) }
                } else if try await NetworkManager.shared.uploadCategory(category) {
                    category.isSynced = true
                    category.updatedAt = Date()
                }
            } catch {
                print("SyncEngine [Category Push Error]: \(error.localizedDescription)")
            }
        }
        try? modelContext.save()
    }

    private func pullCategoriesFromSupabase(_ modelContext: ModelContext) async {
        do {
            let remoteCategories = try await NetworkManager.shared.fetchCategoriesFromSupabase()
            guard !remoteCategories.isEmpty else { return }
            let locals = (try? modelContext.fetch(FetchDescriptor<Category>())) ?? []
            var localById = Dictionary(uniqueKeysWithValues: locals.map { ($0.id.uuidString.lowercased(), $0) })

            for remote in remoteCategories {
                guard let idStr = remote["id"] as? String,
                      let id = UUID(uuidString: idStr),
                      let name = remote["name"] as? String else { continue }
                let updatedAt = remoteDate(remote["updated_at"], fallback: .distantPast)
                let description = remote["description"] as? String ?? remote["category_description"] as? String

                if let local = localById[idStr.lowercased()] {
                    guard local.isSynced, updatedAt > local.updatedAt else { continue }
                    local.name = name
                    local.categoryDescription = description
                    local.imageUrl = remote["image_url"] as? String
                    local.updatedAt = updatedAt
                    local.isSynced = true
                } else {
                    let category = Category(id: id, name: name, categoryDescription: description, imageUrl: remote["image_url"] as? String, isSynced: true, updatedAt: updatedAt == .distantPast ? Date() : updatedAt)
                    modelContext.insert(category)
                    localById[idStr.lowercased()] = category
                }
            }
            try? modelContext.save()
        } catch {
            print("SyncEngine [Category Pull Error]: \(error.localizedDescription)")
        }
    }

    private func syncInventoryItems(_ modelContext: ModelContext) async {
        let descriptor = FetchDescriptor<InventoryItem>(
            predicate: #Predicate<InventoryItem> { $0.isDeleted == true || $0.isSynced == false }
        )
        guard let items = try? modelContext.fetch(descriptor), !items.isEmpty else { return }
        for item in items {
            do {
                if item.isDeleted {
                    if try await NetworkManager.shared.deleteInventoryItemOnServer(id: item.id) { modelContext.delete(item) }
                } else if try await NetworkManager.shared.uploadInventoryItem(item) {
                    item.isSynced = true
                    item.updatedAt = Date()
                }
            } catch {
                print("SyncEngine [InventoryItem Push Error]: \(error.localizedDescription)")
            }
        }
        try? modelContext.save()
    }

    private func pullInventoryItemsFromSupabase(_ modelContext: ModelContext) async {
        do {
            let remoteItems = try await NetworkManager.shared.fetchInventoryItemsFromSupabase()
            guard !remoteItems.isEmpty else { return }
            let locals = (try? modelContext.fetch(FetchDescriptor<InventoryItem>())) ?? []
            var localById = Dictionary(uniqueKeysWithValues: locals.map { ($0.id.uuidString.lowercased(), $0) })

            for remote in remoteItems {
                guard let idStr = remote["id"] as? String,
                      let id = UUID(uuidString: idStr),
                      let name = remote["name"] as? String else { continue }
                let updatedAt = remoteDate(remote["updated_at"], fallback: .distantPast)

                var supplier: Supplier? = nil
                if let supplierIdStr = remote["supplier_id"] as? String, let supplierId = UUID(uuidString: supplierIdStr) {
                    supplier = (try? modelContext.fetch(FetchDescriptor<Supplier>(predicate: #Predicate<Supplier> { $0.id == supplierId })))?.first
                }
                var branch: Branch? = nil
                if let branchIdStr = remote["branch_id"] as? String, let branchId = UUID(uuidString: branchIdStr) {
                    branch = (try? modelContext.fetch(FetchDescriptor<Branch>(predicate: #Predicate<Branch> { $0.id == branchId })))?.first
                }

                if let local = localById[idStr.lowercased()] {
                    guard local.isSynced, updatedAt > local.updatedAt else { continue }
                    local.name = name
                    local.sku = remote["sku"] as? String
                    local.unit = remote["unit"] as? String ?? local.unit
                    local.currentQuantity = remoteDouble(remote["current_quantity"])
                    local.reorderLevel = remoteDouble(remote["reorder_level"])
                    local.costPrice = remoteDouble(remote["cost_price"])
                    local.supplier = supplier
                    local.branch = branch
                    local.category = remote["category"] as? String
                    local.storageLocation = remote["storage_location"] as? String
                    local.barcode = remote["barcode"] as? String
                    local.updatedAt = updatedAt
                    local.isSynced = true
                } else {
                    let item = InventoryItem(id: id, name: name, sku: remote["sku"] as? String, unit: remote["unit"] as? String ?? "piece", currentQuantity: remoteDouble(remote["current_quantity"]), reorderLevel: remoteDouble(remote["reorder_level"]), costPrice: remoteDouble(remote["cost_price"]), supplier: supplier, branch: branch, category: remote["category"] as? String, storageLocation: remote["storage_location"] as? String, barcode: remote["barcode"] as? String, isSynced: true, updatedAt: updatedAt == .distantPast ? Date() : updatedAt)
                    modelContext.insert(item)
                    localById[idStr.lowercased()] = item
                }
            }
            try? modelContext.save()
        } catch {
            print("SyncEngine [InventoryItem Pull Error]: \(error.localizedDescription)")
        }
    }

    private func syncModifierGroups(_ modelContext: ModelContext) async {
        let descriptor = FetchDescriptor<ModifierGroup>(
            predicate: #Predicate<ModifierGroup> { $0.isDeleted == true || $0.isSynced == false }
        )
        guard let groups = try? modelContext.fetch(descriptor), !groups.isEmpty else { return }
        for group in groups {
            do {
                if group.isDeleted {
                    if try await NetworkManager.shared.deleteModifierGroupOnServer(id: group.id) { modelContext.delete(group) }
                } else if try await NetworkManager.shared.uploadModifierGroup(group) {
                    group.isSynced = true
                    group.updatedAt = Date()
                }
            } catch {
                print("SyncEngine [ModifierGroup Push Error]: \(error.localizedDescription)")
            }
        }
        try? modelContext.save()
    }

    private func pullModifierGroupsFromSupabase(_ modelContext: ModelContext) async {
        do {
            let remoteGroups = try await NetworkManager.shared.fetchModifierGroupsFromSupabase()
            guard !remoteGroups.isEmpty else { return }
            let locals = (try? modelContext.fetch(FetchDescriptor<ModifierGroup>())) ?? []
            var localById = Dictionary(uniqueKeysWithValues: locals.map { ($0.id.uuidString.lowercased(), $0) })

            for remote in remoteGroups {
                guard let idStr = remote["id"] as? String,
                      let id = UUID(uuidString: idStr),
                      let name = remote["name"] as? String else { continue }
                let updatedAt = remoteDate(remote["updated_at"], fallback: .distantPast)
                if let local = localById[idStr.lowercased()] {
                    guard local.isSynced, updatedAt > local.updatedAt else { continue }
                    local.name = name
                    local.minSelection = remoteInt(remote["min_selection"])
                    local.maxSelection = remoteInt(remote["max_selection"], fallback: 1)
                    local.updatedAt = updatedAt
                    local.isSynced = true
                } else {
                    let group = ModifierGroup(id: id, name: name, minSelection: remoteInt(remote["min_selection"]), maxSelection: remoteInt(remote["max_selection"], fallback: 1), isSynced: true, updatedAt: updatedAt == .distantPast ? Date() : updatedAt)
                    modelContext.insert(group)
                    localById[idStr.lowercased()] = group
                }
            }
            try? modelContext.save()
        } catch {
            print("SyncEngine [ModifierGroup Pull Error]: \(error.localizedDescription)")
        }
    }

    private func syncModifiers(_ modelContext: ModelContext) async {
        let descriptor = FetchDescriptor<Modifier>(
            predicate: #Predicate<Modifier> { $0.isDeleted == true || $0.isSynced == false }
        )
        guard let modifiers = try? modelContext.fetch(descriptor), !modifiers.isEmpty else { return }
        for modifier in modifiers {
            do {
                if modifier.isDeleted {
                    if try await NetworkManager.shared.deleteModifierOnServer(id: modifier.id) { modelContext.delete(modifier) }
                } else if try await NetworkManager.shared.uploadModifier(modifier) {
                    modifier.isSynced = true
                    modifier.updatedAt = Date()
                }
            } catch {
                print("SyncEngine [Modifier Push Error]: \(error.localizedDescription)")
            }
        }
        try? modelContext.save()
    }

    private func pullModifiersFromSupabase(_ modelContext: ModelContext) async {
        do {
            let remoteModifiers = try await NetworkManager.shared.fetchModifiersFromSupabase()
            guard !remoteModifiers.isEmpty else { return }
            let locals = (try? modelContext.fetch(FetchDescriptor<Modifier>())) ?? []
            var localById = Dictionary(uniqueKeysWithValues: locals.map { ($0.id.uuidString.lowercased(), $0) })

            for remote in remoteModifiers {
                guard let idStr = remote["id"] as? String,
                      let id = UUID(uuidString: idStr),
                      let name = remote["name"] as? String else { continue }
                var group: ModifierGroup? = nil
                if let groupIdStr = remote["modifier_group_id"] as? String, let groupId = UUID(uuidString: groupIdStr) {
                    group = (try? modelContext.fetch(FetchDescriptor<ModifierGroup>(predicate: #Predicate<ModifierGroup> { $0.id == groupId })))?.first
                }
                var inventoryItem: InventoryItem? = nil
                if let itemIdStr = remote["inventory_item_id"] as? String, let itemId = UUID(uuidString: itemIdStr) {
                    inventoryItem = (try? modelContext.fetch(FetchDescriptor<InventoryItem>(predicate: #Predicate<InventoryItem> { $0.id == itemId })))?.first
                }
                let updatedAt = remoteDate(remote["updated_at"], fallback: .distantPast)
                let quantityRequired = remote["quantity_required"].map { remoteDouble($0) }

                if let local = localById[idStr.lowercased()] {
                    guard local.isSynced, updatedAt > local.updatedAt else { continue }
                    local.modifierGroup = group
                    local.name = name
                    local.extraPrice = remoteDouble(remote["extra_price"])
                    local.isAvailable = remoteBool(remote["is_available"], fallback: true)
                    local.inventoryItemLink = inventoryItem
                    local.quantityRequired = quantityRequired
                    local.updatedAt = updatedAt
                    local.isSynced = true
                } else {
                    let modifier = Modifier(id: id, modifierGroup: group, name: name, extraPrice: remoteDouble(remote["extra_price"]), isAvailable: remoteBool(remote["is_available"], fallback: true), inventoryItemLink: inventoryItem, quantityRequired: quantityRequired, isSynced: true, updatedAt: updatedAt == .distantPast ? Date() : updatedAt)
                    modelContext.insert(modifier)
                    localById[idStr.lowercased()] = modifier
                }
            }
            try? modelContext.save()
        } catch {
            print("SyncEngine [Modifier Pull Error]: \(error.localizedDescription)")
        }
    }

    private func syncMenuItemModifierGroups(_ modelContext: ModelContext) async {
        let descriptor = FetchDescriptor<MenuItemModifierGroup>(
            predicate: #Predicate<MenuItemModifierGroup> { $0.isDeleted == true || $0.isSynced == false }
        )
        guard let relations = try? modelContext.fetch(descriptor), !relations.isEmpty else { return }
        for relation in relations {
            do {
                if relation.isDeleted {
                    if let menuItemId = relation.menuItem?.id, let modifierGroupId = relation.modifierGroup?.id {
                        if try await NetworkManager.shared.deleteMenuItemModifierGroupOnServer(menuItemId: menuItemId, modifierGroupId: modifierGroupId) { modelContext.delete(relation) }
                    } else {
                        modelContext.delete(relation)
                    }
                } else if try await NetworkManager.shared.uploadMenuItemModifierGroup(relation) {
                    relation.isSynced = true
                    relation.updatedAt = Date()
                }
            } catch {
                print("SyncEngine [MenuItemModifierGroup Push Error]: \(error.localizedDescription)")
            }
        }
        try? modelContext.save()
    }

    private func pullMenuItemModifierGroupsFromSupabase(_ modelContext: ModelContext) async {
        do {
            let remoteRelations = try await NetworkManager.shared.fetchMenuItemModifierGroupsFromSupabase()
            guard !remoteRelations.isEmpty else { return }
            let locals = (try? modelContext.fetch(FetchDescriptor<MenuItemModifierGroup>())) ?? []
            var localByKey: [String: MenuItemModifierGroup] = [:]
            for relation in locals {
                if let itemId = relation.menuItem?.id.lowercased(), let groupId = relation.modifierGroup?.id.uuidString.lowercased() {
                    localByKey["\(itemId)|\(groupId)"] = relation
                }
            }

            for remote in remoteRelations {
                guard let menuItemId = remote["menu_item_id"] as? String,
                      let groupIdStr = remote["modifier_group_id"] as? String,
                      let groupId = UUID(uuidString: groupIdStr) else { continue }
                let menuItem = (try? modelContext.fetch(FetchDescriptor<MenuItem>(predicate: #Predicate<MenuItem> { $0.id == menuItemId })))?.first
                let modifierGroup = (try? modelContext.fetch(FetchDescriptor<ModifierGroup>(predicate: #Predicate<ModifierGroup> { $0.id == groupId })))?.first
                guard let menuItem, let modifierGroup else { continue }

                let key = "\(menuItemId.lowercased())|\(groupIdStr.lowercased())"
                let updatedAt = remoteDate(remote["updated_at"], fallback: .distantPast)
                if let local = localByKey[key] {
                    guard local.isSynced, updatedAt > local.updatedAt else { continue }
                    local.menuItem = menuItem
                    local.modifierGroup = modifierGroup
                    local.updatedAt = updatedAt
                    local.isSynced = true
                } else {
                    let id = (remote["id"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID()
                    let relation = MenuItemModifierGroup(id: id, menuItem: menuItem, modifierGroup: modifierGroup, isSynced: true, updatedAt: updatedAt == .distantPast ? Date() : updatedAt)
                    modelContext.insert(relation)
                    localByKey[key] = relation
                }
            }
            try? modelContext.save()
        } catch {
            print("SyncEngine [MenuItemModifierGroup Pull Error]: \(error.localizedDescription)")
        }
    }

    private func syncInventoryTransactions(_ modelContext: ModelContext) async {
        let descriptor = FetchDescriptor<InventoryTransaction>(
            predicate: #Predicate<InventoryTransaction> { $0.isSynced == false }
        )

        guard let txns = try? modelContext.fetch(descriptor), !txns.isEmpty else { return }

        for txn in txns {
            if txn.isDeleted {
                modelContext.delete(txn)
                try? modelContext.save()
                continue
            }

            let itemName = txn.item?.name ?? "Unknown"
            do {
                let success = try await NetworkManager.shared.uploadInventoryTransaction(
                    id: txn.id,
                    itemId: txn.item?.id,
                    itemName: itemName,
                    quantity: txn.quantity,
                    type: txn.transactionType,
                    costPrice: txn.costPrice,
                    referenceId: txn.referenceId,
                    notes: txn.notes,
                    branchId: txn.branch?.id,
                    isDeleted: txn.isDeleted,
                    updatedAt: txn.updatedAt
                )

                if success {
                    txn.isSynced = true
                    txn.updatedAt = Date()
                    try modelContext.save()
                }
            } catch {
                print("SyncEngine [InventoryTxn Sync Error]: \(error.localizedDescription)")
            }
        }
    }

    private func syncMenuItems(_ modelContext: ModelContext) async {
        let descriptor = FetchDescriptor<MenuItem>(
            predicate: #Predicate<MenuItem> { $0.isSynced == false }
        )

        guard let items = try? modelContext.fetch(descriptor), !items.isEmpty else { return }

        for item in items {
            if item.isDeleted {
                do {
                    _ = try await NetworkManager.shared.deleteMenuItemOnServer(id: item.id)
                    modelContext.delete(item)
                    try modelContext.save()
                } catch {
                    print("SyncEngine [MenuItem Delete Error]: \(error.localizedDescription)")
                }
                continue
            }

            do {
                let success = try await NetworkManager.shared.uploadMenuItem(item: item)
                if success {
                    item.isSynced = true
                    item.updatedAt = Date()
                    try modelContext.save()
                }
            } catch {
                print("SyncEngine [MenuItem Sync Error]: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Pull Menu Items from Supabase (Single Source of Truth)

    /// Fetches menu items from Supabase and upserts into SwiftData.
    /// This makes Supabase the single source of truth for the menu.
    /// Any item added/edited in Supabase will automatically appear in the iOS POS app.
    private func pullMenuItemsFromSupabase(_ modelContext: ModelContext) async {
        do {
            let remoteItems = try await NetworkManager.shared.fetchMenuItemsFromSupabase()
            guard !remoteItems.isEmpty else { return }

            // Fetch existing local items and categories for O(1) lookup
            let localItems = (try? modelContext.fetch(FetchDescriptor<MenuItem>())) ?? []
            let localCategories = (try? modelContext.fetch(FetchDescriptor<Category>())) ?? []

            var localItemsById: [String: MenuItem] = [:]
            for item in localItems {
                localItemsById[item.id.lowercased()] = item
            }

            var localCatsBySlug: [String: Category] = [:]
            for cat in localCategories {
                let slug = cat.name.lowercased()
                localCatsBySlug[slug] = cat
                // Also map common aliases
                if slug.contains("main") { localCatsBySlug["mains"] = cat }
                if slug.contains("appetizer") { localCatsBySlug["appetizers"] = cat }
                if slug.contains("beverage") || slug.contains("drink") {
                    localCatsBySlug["drinks"] = cat
                    localCatsBySlug["beverages"] = cat
                }
                if slug.contains("dessert") { localCatsBySlug["desserts"] = cat }
            }

            var didChange = false

            for remote in remoteItems {
                guard let name = remote["name"] as? String,
                      let price = remote["price"] as? Double,
                      let idString = remote["id"] as? String else { continue }

                let desc = remote["description"] as? String ?? ""
                let categorySlug = remote["category"] as? String ?? "mains"
                let imageUrl = remote["image_url"] as? String ?? ""
                let imageUrl2 = remote["image_url_2"] as? String ?? ""
                let imageUrl3 = remote["image_url_3"] as? String ?? ""
                let videoUrl = remote["video_url"] as? String ?? ""
                
                let nameTrans = remote["name_translations"] as? [String: String] ?? [:]
                let descTrans = remote["description_translations"] as? [String: String] ?? [:]
                
                let encoder = JSONEncoder()
                let nameTransJson = (try? String(data: encoder.encode(nameTrans), encoding: .utf8)) ?? "{}"
                let descTransJson = (try? String(data: encoder.encode(descTrans), encoding: .utf8)) ?? "{}"

                // Find or create local category
                let category: Category
                if let existingCat = localCatsBySlug[categorySlug] {
                    category = existingCat
                } else {
                    // Create a new local category for the slug
                    let catName: String
                    switch categorySlug {
                    case "mains": catName = "Main Dishes"
                    case "appetizers": catName = "Appetizers"
                    case "drinks": catName = "Beverages"
                    case "desserts": catName = "Desserts"
                    default: catName = categorySlug.capitalized
                    }
                    let newCat = Category(name: catName)
                    modelContext.insert(newCat)
                    localCatsBySlug[categorySlug] = newCat
                    category = newCat
                }

                if let existing = localItemsById[idString.lowercased()] {
                    // Update if name, price, description, imageUrl, or translations changed
                    var changed = false
                    if existing.name != name { existing.name = name; changed = true }
                    if abs((existing.price) - price) > 0.001 { existing.price = price; changed = true }
                    if (existing.itemDescription ?? "") != desc { existing.itemDescription = desc; changed = true }
                    if (existing.imageUrl ?? "") != imageUrl { existing.imageUrl = imageUrl; changed = true }
                    if (existing.imageUrl2 ?? "") != imageUrl2 { existing.imageUrl2 = imageUrl2; changed = true }
                    if (existing.imageUrl3 ?? "") != imageUrl3 { existing.imageUrl3 = imageUrl3; changed = true }
                    if (existing.videoUrl ?? "") != videoUrl { existing.videoUrl = videoUrl; changed = true }
                    if existing.nameTranslationsJson != nameTransJson { existing.nameTranslationsJson = nameTransJson; changed = true }
                    if existing.descriptionTranslationsJson != descTransJson { existing.descriptionTranslationsJson = descTransJson; changed = true }
                    if changed {
                        existing.isSynced = true
                        existing.updatedAt = Date()
                        didChange = true
                    }
                } else {
                    // Insert new item from Supabase
                    let newItem = MenuItem(
                        id: idString,
                        name: name,
                        itemDescription: desc.isEmpty ? nil : desc,
                        price: price,
                        imageUrl: imageUrl.isEmpty ? nil : imageUrl,
                        imageUrl2: imageUrl2.isEmpty ? nil : imageUrl2,
                        imageUrl3: imageUrl3.isEmpty ? nil : imageUrl3,
                        videoUrl: videoUrl.isEmpty ? nil : videoUrl,
                        category: category,
                        nameTranslationsJson: nameTransJson,
                        descriptionTranslationsJson: descTransJson
                    )
                    newItem.isSynced = true
                    modelContext.insert(newItem)
                    didChange = true
                }
            }

            if didChange {
                try? modelContext.save()
                #if DEBUG
                print("SyncEngine [PullMenu]: Updated SwiftData from Supabase (\(remoteItems.count) items)")
                #endif
            }
        } catch {
            // Silently fail — app works offline with existing SwiftData cache
            #if DEBUG
            print("SyncEngine [PullMenu]: Skipped (offline or error): \(error.localizedDescription)")
            #endif
        }
    }

    // MARK: - Purchase Orders Sync

    /// Syncs unsynced PurchaseOrders to Supabase.
    /// Handles soft-delete: marks the PO and its items as deleted remotely, then purges locally.
    /// Items are uploaded inline — no separate sync pass needed for PurchaseOrderItem.
    private func syncPurchaseOrders(_ modelContext: ModelContext) async {
        let descriptor = FetchDescriptor<PurchaseOrder>(
            predicate: #Predicate<PurchaseOrder> { $0.isSynced == false }
        )

        guard let purchaseOrders = try? modelContext.fetch(descriptor), !purchaseOrders.isEmpty else { return }

        for po in purchaseOrders {
            if po.isDeleted {
                do {
                    _ = try await NetworkManager.shared.deletePurchaseOrderOnServer(id: po.id)
                    // Purge items then PO from local store
                    for item in po.items {
                        modelContext.delete(item)
                    }
                    modelContext.delete(po)
                    try modelContext.save()
                } catch {
                    print("SyncEngine [PurchaseOrder Delete Error]: \(error.localizedDescription)")
                }
                continue
            }

            do {
                let success = try await NetworkManager.shared.uploadPurchaseOrder(purchaseOrder: po)
                if success {
                    po.isSynced = true
                    po.updatedAt = Date()
                    // Mark items as synced too
                    for item in po.items {
                        item.isSynced = true
                        item.updatedAt = Date()
                    }
                    try modelContext.save()
                    #if DEBUG
                    print("SyncEngine [PurchaseOrder]: Synced PO \(po.poNumber) with \(po.items.count) item(s)")
                    #endif
                }
            } catch {
                print("SyncEngine [PurchaseOrder Sync Error]: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Delivery Prices Sync

    /// Syncs all DeliveryPrices for menu items that are already synced to Supabase.
    /// DeliveryPrice has no isSynced flag — all prices are batch-upserted on every cycle.
    /// This is safe because there are typically few delivery prices (max ~5 per menu item).
    private func syncDeliveryPrices(_ modelContext: ModelContext) async {
        // Only sync delivery prices for menu items that are already on the server
        let descriptor = FetchDescriptor<MenuItem>(
            predicate: #Predicate<MenuItem> { $0.isSynced == true && $0.isDeleted == false }
        )

        guard let menuItems = try? modelContext.fetch(descriptor) else { return }

        let allPrices = menuItems.flatMap { $0.deliveryPrices }
        guard !allPrices.isEmpty else { return }

        do {
            _ = try await NetworkManager.shared.uploadDeliveryPrices(allPrices)
            #if DEBUG
            print("SyncEngine [DeliveryPrices]: Synced \(allPrices.count) delivery price(s)")
            #endif
        } catch {
            print("SyncEngine [DeliveryPrices Sync Error]: \(error.localizedDescription)")
        }
    }

    private func syncPromotions(_ modelContext: ModelContext) async {
        let descriptor = FetchDescriptor<Promotion>(
            predicate: #Predicate<Promotion> { $0.isDeleted == true || $0.isSynced == false }
        )

        guard let promotions = try? modelContext.fetch(descriptor), !promotions.isEmpty else { return }

        for promotion in promotions {
            if promotion.isDeleted {
                do {
                    let success = try await NetworkManager.shared.deletePromotionOnServer(id: promotion.id)
                    if success {
                        modelContext.delete(promotion)
                        try modelContext.save()
                    }
                } catch {
                    print("SyncEngine [Promotion Delete Error]: \(error.localizedDescription)")
                }
                continue
            }

            do {
                let success = try await NetworkManager.shared.uploadPromotion(promotion: promotion)
                if success {
                    _ = try await NetworkManager.shared.uploadPromotionBundleItems(for: promotion)
                    for bundleItem in promotion.bundleItems {
                        bundleItem.isSynced = true
                        bundleItem.updatedAt = Date()
                    }
                    promotion.isSynced = true
                    promotion.updatedAt = Date()
                    try modelContext.save()
                }
            } catch {
                print("SyncEngine [Promotion Sync Error]: \(error.localizedDescription)")
            }
        }
    }


    private func pullPromotionsFromSupabase(_ modelContext: ModelContext) async {
        do {
            let remotePromos = try await NetworkManager.shared.fetchPromotionsFromSupabase()
            let remoteBundleItems = try await NetworkManager.shared.fetchPromotionBundleItemsFromSupabase()

            // Fetch ALL local promotions (including soft-deleted ones) so we can match by ID
            let localPromos = (try? modelContext.fetch(FetchDescriptor<Promotion>())) ?? []
            let localBundleItems = (try? modelContext.fetch(FetchDescriptor<PromotionBundleItem>())) ?? []
            let localMenuItems = (try? modelContext.fetch(FetchDescriptor<MenuItem>())) ?? []

            var localPromosById: [String: Promotion] = [:]
            for promo in localPromos {
                localPromosById[promo.id.uuidString.lowercased()] = promo
            }
            var localBundleItemsById: [String: PromotionBundleItem] = [:]
            for bundleItem in localBundleItems {
                localBundleItemsById[bundleItem.id.uuidString.lowercased()] = bundleItem
            }
            var localMenuItemsById: [String: MenuItem] = [:]
            for menuItem in localMenuItems {
                localMenuItemsById[menuItem.id.lowercased()] = menuItem
            }

            var didChange = false
            var remoteIds = Set<String>()

            for remote in remotePromos {
                guard let idStr = remote["id"] as? String,
                      let id = UUID(uuidString: idStr),
                      let title = remote["title"] as? String else { continue }
                remoteIds.insert(idStr.lowercased())

                let desc = remote["promo_description"] as? String
                let imageData = remote["image_data"] as? String
                let mediaType = remote["media_type"] as? String ?? "image"
                let discountType = remote["discount_type"] as? String ?? "none"
                let discountValue = remoteDouble(remote["discount_value"])
                let minimumSpend = remoteDouble(remote["minimum_spend"])
                let appliesToMenuItemId = (remote["applies_to_menu_item_id"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                let rewardMenuItemId = (remote["reward_menu_item_id"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                let requiredQuantity = max(1, remoteInt(remote["required_quantity"], fallback: 1))
                let rewardQuantity = max(0, remoteInt(remote["reward_quantity"], fallback: 0))
                let maxRedemptionsRaw = remoteInt(remote["max_redemptions"], fallback: -1)
                let maxRedemptions = maxRedemptionsRaw >= 0 ? maxRedemptionsRaw : nil
                let currentRedemptions = max(0, remoteInt(remote["current_redemptions"], fallback: 0))
                let perCustomerLimitRaw = remoteInt(remote["per_customer_limit"], fallback: -1)
                let perCustomerLimit = perCustomerLimitRaw >= 1 ? perCustomerLimitRaw : nil
                let startsAt = remoteDate(remote["starts_at"], fallback: .distantPast) == .distantPast ? nil : remoteDate(remote["starts_at"], fallback: .distantPast)
                let endsAt = remoteDate(remote["ends_at"], fallback: .distantPast) == .distantPast ? nil : remoteDate(remote["ends_at"], fallback: .distantPast)

                let isActive: Bool
                if let boolVal = remote["is_active"] as? Bool {
                    isActive = boolVal
                } else if let intVal = remote["is_active"] as? Int {
                    isActive = intVal != 0
                } else if let doubleVal = remote["is_active"] as? Double {
                    isActive = doubleVal != 0.0
                } else {
                    isActive = true
                }

                let isDeleted: Bool
                if let boolVal = remote["is_deleted"] as? Bool {
                    isDeleted = boolVal
                } else if let intVal = remote["is_deleted"] as? Int {
                    isDeleted = intVal != 0
                } else if let doubleVal = remote["is_deleted"] as? Double {
                    isDeleted = doubleVal != 0.0
                } else {
                    isDeleted = false
                }

                let updatedAtStr = remote["updated_at"] as? String ?? ""
                let updatedAt = parseISO8601Date(updatedAtStr)

                if let existing = localPromosById[idStr.lowercased()] {
                    if isDeleted {
                        modelContext.delete(existing)
                        didChange = true
                    } else {
                        // If locally marked as deleted (pending push), DON'T overwrite with remote data
                        if existing.isDeleted {
                            // Skip — local deletion takes precedence; syncPromotions will push this
                            continue
                        }
                        // Only update if local record is already synced OR remote is newer
                        if existing.isSynced || updatedAt > existing.updatedAt {
                            var changed = false
                            if existing.title != title { existing.title = title; changed = true }
                            if existing.promoDescription != desc { existing.promoDescription = desc; changed = true }
                            if existing.imageData != imageData { existing.imageData = imageData; changed = true }
                            if existing.mediaType != mediaType { existing.mediaType = mediaType; changed = true }
                            if existing.isActive != isActive { existing.isActive = isActive; changed = true }
                            if existing.discountType != discountType { existing.discountType = discountType; changed = true }
                            if existing.discountValue != discountValue { existing.discountValue = discountValue; changed = true }
                            if existing.minimumSpend != minimumSpend { existing.minimumSpend = minimumSpend; changed = true }
                            if existing.appliesToMenuItemId != appliesToMenuItemId { existing.appliesToMenuItemId = appliesToMenuItemId; changed = true }
                            if existing.rewardMenuItemId != rewardMenuItemId { existing.rewardMenuItemId = rewardMenuItemId; changed = true }
                            if existing.requiredQuantity != requiredQuantity { existing.requiredQuantity = requiredQuantity; changed = true }
                            if existing.rewardQuantity != rewardQuantity { existing.rewardQuantity = rewardQuantity; changed = true }
                            if existing.maxRedemptions != maxRedemptions { existing.maxRedemptions = maxRedemptions; changed = true }
                            if existing.currentRedemptions != currentRedemptions { existing.currentRedemptions = currentRedemptions; changed = true }
                            if existing.perCustomerLimit != perCustomerLimit { existing.perCustomerLimit = perCustomerLimit; changed = true }
                            if existing.startsAt != startsAt { existing.startsAt = startsAt; changed = true }
                            if existing.endsAt != endsAt { existing.endsAt = endsAt; changed = true }
                            if changed {
                                existing.isSynced = true
                                existing.updatedAt = updatedAt
                                didChange = true
                            }
                        }
                    }
                } else if !isDeleted {
                    // No local copy found — insert from remote (only if it is not deleted)
                    let newPromo = Promotion(
                        id: id,
                        title: title,
                        promoDescription: desc,
                        imageData: imageData,
                        mediaType: mediaType,
                        isActive: isActive,
                        discountType: discountType,
                        discountValue: discountValue,
                        minimumSpend: minimumSpend,
                        appliesToMenuItemId: appliesToMenuItemId,
                        rewardMenuItemId: rewardMenuItemId,
                        requiredQuantity: requiredQuantity,
                        rewardQuantity: rewardQuantity,
                        startsAt: startsAt,
                        endsAt: endsAt,
                        maxRedemptions: maxRedemptions,
                        currentRedemptions: currentRedemptions,
                        perCustomerLimit: perCustomerLimit,
                        isSynced: true,
                        isDeleted: false,
                        updatedAt: updatedAt
                    )
                    modelContext.insert(newPromo)
                    didChange = true
                }
            }

            // Reconcile hard-deletes made directly in Supabase. If a clean local
            // promotion no longer exists remotely, purge the local cache too.
            for local in localPromos where local.isSynced && !local.isDeleted {
                if !remoteIds.contains(local.id.uuidString.lowercased()) {
                    modelContext.delete(local)
                    didChange = true
                }
            }

            let remoteBundleIds = reconcilePromotionBundleItems(
                remoteBundleItems,
                localBundleItemsById: localBundleItemsById,
                localPromosById: localPromosById,
                localMenuItemsById: localMenuItemsById,
                modelContext: modelContext
            )
            for localBundleItem in localBundleItems where localBundleItem.isSynced && !localBundleItem.isDeleted {
                if !remoteBundleIds.contains(localBundleItem.id.uuidString.lowercased()) {
                    modelContext.delete(localBundleItem)
                    didChange = true
                }
            }

            if didChange {
                try? modelContext.save()
                #if DEBUG
                print("SyncEngine [PullPromotions]: Updated SwiftData from Supabase (\(remotePromos.count) remote items)")
                #endif
            }
        } catch {
            #if DEBUG
            print("SyncEngine [PullPromotions]: Skipped or failed: \(error.localizedDescription)")
            #endif
        }
    }

    @discardableResult
    private func reconcilePromotionBundleItems(
        _ remoteBundleItems: [[String: Any]],
        localBundleItemsById: [String: PromotionBundleItem],
        localPromosById: [String: Promotion],
        localMenuItemsById: [String: MenuItem],
        modelContext: ModelContext
    ) -> Set<String> {
        var remoteIds = Set<String>()

        for remote in remoteBundleItems {
            guard let idStr = remote["id"] as? String,
                  let id = UUID(uuidString: idStr),
                  let promotionIdStr = remote["promotion_id"] as? String,
                  let menuItemId = remote["menu_item_id"] as? String,
                  let promotion = localPromosById[promotionIdStr.lowercased()],
                  let menuItem = localMenuItemsById[menuItemId.lowercased()] else { continue }

            let normalizedId = idStr.lowercased()
            remoteIds.insert(normalizedId)

            let quantity = max(1, remoteInt(remote["quantity"], fallback: 1))
            let displayOrder = max(0, remoteInt(remote["display_order"], fallback: 0))
            let updatedAt = remoteDate(remote["updated_at"], fallback: Date())
            let isDeleted = remoteBool(remote["is_deleted"], fallback: false)

            if let existing = localBundleItemsById[normalizedId] {
                if isDeleted {
                    modelContext.delete(existing)
                    continue
                }

                if existing.isSynced || updatedAt > existing.updatedAt {
                    existing.promotion = promotion
                    existing.menuItem = menuItem
                    existing.quantity = quantity
                    existing.displayOrder = displayOrder
                    existing.isSynced = true
                    existing.isDeleted = false
                    existing.updatedAt = updatedAt
                }
            } else if !isDeleted {
                let newBundleItem = PromotionBundleItem(
                    id: id,
                    promotion: promotion,
                    menuItem: menuItem,
                    quantity: quantity,
                    displayOrder: displayOrder,
                    isSynced: true,
                    isDeleted: false,
                    updatedAt: updatedAt
                )
                modelContext.insert(newBundleItem)
            }
        }

        return remoteIds
    }

    private func syncTables(_ modelContext: ModelContext) async {
        let descriptor = FetchDescriptor<RestaurantTable>(
            predicate: #Predicate<RestaurantTable> { $0.isSynced == false }
        )

        guard let tables = try? modelContext.fetch(descriptor), !tables.isEmpty else { return }

        for table in tables {
            do {
                let success = try await NetworkManager.shared.uploadRestaurantTable(table: table)
                if success {
                    if table.isDeleted {
                        modelContext.delete(table)
                    } else {
                        table.isSynced = true
                        table.updatedAt = Date()
                    }
                    try modelContext.save()
                }
            } catch {
                print("SyncEngine [Table Sync Error]: \(error.localizedDescription)")
            }
        }
    }

    private func syncTableSessions(_ modelContext: ModelContext) async {


        let descriptor = FetchDescriptor<TableSession>(
            predicate: #Predicate<TableSession> { $0.isSynced == false }
        )

        guard let sessions = try? modelContext.fetch(descriptor), !sessions.isEmpty else { return }

        for session in sessions {
            do {
                if session.isDeleted {
                    _ = try? await NetworkManager.shared.deleteTableSession(id: session.id)
                    modelContext.delete(session)
                    try modelContext.save()
                    continue
                }

                let success = try await NetworkManager.shared.uploadTableSession(session: session)
                if success {
                    session.isSynced = true
                    session.updatedAt = Date()
                    try modelContext.save()
                }
            } catch {
                print("SyncEngine [TableSession Sync Error]: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Floor Plan Image Sync
    private func syncFloorPlanImages(_ modelContext: ModelContext) async {
        let descriptor = FetchDescriptor<FloorPlanImage>(
            predicate: #Predicate<FloorPlanImage> { $0.isSynced == false }
        )
        guard let items = try? modelContext.fetch(descriptor), !items.isEmpty else { return }

        for item in items {
            do {
                let success = try await NetworkManager.shared.uploadFloorPlanImage(floorPlan: item)
                if success {
                    if item.isDeleted {
                        modelContext.delete(item)
                    } else {
                        item.isSynced = true
                        item.updatedAt = Date()
                    }
                    try? modelContext.save()
                }
            } catch {
                print("SyncEngine [FloorPlanImage Sync Error]: \(error.localizedDescription)")
            }
        }
    }

    private func syncEmployees(_ modelContext: ModelContext) async {
        let descriptor = FetchDescriptor<Employee>(
            predicate: #Predicate<Employee> { $0.isSynced == false }
        )

        guard let employees = try? modelContext.fetch(descriptor), !employees.isEmpty else { return }

        for employee in employees {
            do {
                let success = try await NetworkManager.shared.uploadEmployee(employee: employee)
                if success {
                    if employee.isDeleted {
                        modelContext.delete(employee)
                    } else {
                        employee.isSynced = true
                        employee.updatedAt = Date()
                    }
                    try modelContext.save()
                }
            } catch {
                print("SyncEngine [Employee Sync Error]: \(error.localizedDescription)")
            }
        }
    }

    private func syncEmployeeShifts(_ modelContext: ModelContext) async {
        let descriptor = FetchDescriptor<EmployeeShift>(
            predicate: #Predicate<EmployeeShift> { $0.isSynced == false }
        )

        guard let shifts = try? modelContext.fetch(descriptor), !shifts.isEmpty else { return }

        for shift in shifts {
            if shift.isDeleted {
                modelContext.delete(shift)
                try? modelContext.save()
                continue
            }

            guard shift.employee != nil else {
                print("SyncEngine [EmployeeShift Sync Error]: Missing employee relation for shift \(shift.id)")
                continue
            }

            do {
                let success = try await NetworkManager.shared.uploadEmployeeShift(shift: shift)
                if success {
                    shift.isSynced = true
                    shift.updatedAt = Date()
                    try modelContext.save()
                }
            } catch {
                print("SyncEngine [EmployeeShift Sync Error]: \(error.localizedDescription)")
            }
        }
    }

    private func syncMerchant() async {
        guard let merchantIdStr = UserDefaults.standard.string(forKey: "active_merchant_id"),
              let merchantId = UUID(uuidString: merchantIdStr) else { return }

        let name = UserDefaults.standard.string(forKey: "store_name") ?? UserDefaults.standard.string(forKey: "logged_in_name") ?? "My New POS Shop"
        let email = UserDefaults.standard.string(forKey: "logged_in_email") ?? "owner@alphapos.com"
        let kitchenWorkflowRequired = UserDefaults.standard.object(forKey: "kitchen_workflow_required") as? Bool ?? true
        let isTableSystemEnabled = UserDefaults.standard.object(forKey: "enable_table_system") as? Bool ?? true
        let isWebOrderingEnabled = UserDefaults.standard.object(forKey: "enable_web_ordering") as? Bool ?? true

        let phone = UserDefaults.standard.string(forKey: "store_phone")
        let website = UserDefaults.standard.string(forKey: "store_website")
        let address = UserDefaults.standard.string(forKey: "store_address")
        let taxId = UserDefaults.standard.string(forKey: "store_tax_id")
        let branchCode = UserDefaults.standard.string(forKey: "store_branch_code")
        let taxRate = UserDefaults.standard.object(forKey: "store_tax_rate") as? Double
        let taxType = UserDefaults.standard.string(forKey: "store_tax_type")
        let serviceChargeRate = UserDefaults.standard.object(forKey: "store_service_charge_rate") as? Double
        let receiptHeader = UserDefaults.standard.string(forKey: "store_receipt_header")
        let receiptFooter = UserDefaults.standard.string(forKey: "store_receipt_footer")
        let promptPayNumber = UserDefaults.standard.string(forKey: "promptpay_number")

        do {
            _ = try await NetworkManager.shared.uploadMerchant(
                id: merchantId,
                name: name,
                email: email,
                kitchenWorkflowRequired: kitchenWorkflowRequired,
                isTableSystemEnabled: isTableSystemEnabled,
                isWebOrderingEnabled: isWebOrderingEnabled,
                phone: phone,
                website: website,
                address: address,
                taxId: taxId,
                branchCode: branchCode,
                taxRate: taxRate,
                taxType: taxType,
                serviceChargeRate: serviceChargeRate,
                receiptHeader: receiptHeader,
                receiptFooter: receiptFooter,
                promptPayNumber: promptPayNumber
            )
        } catch {
            print("SyncEngine [Merchant Sync Error]: \(error.localizedDescription)")
        }
    }

    func pullRestaurantTables(_ modelContext: ModelContext) async {
        guard await NetworkManager.shared.isConnected() else { return }

        // 0. Normalize existing local table numbers (e.g. "T1" -> "1")
        let localTablesDescriptor = FetchDescriptor<RestaurantTable>()
        if let localTables = try? modelContext.fetch(localTablesDescriptor) {
            var needsSave = false
            for table in localTables {
                let trimmed = table.tableNumber.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.lowercased().hasPrefix("t") {
                    let suffix = String(trimmed.dropFirst())
                    if suffix.allSatisfy({ $0.isNumber }) {
                        table.tableNumber = suffix
                        table.isSynced = false
                        table.updatedAt = Date()
                        needsSave = true
                    }
                }
            }
            if needsSave {
                try? modelContext.save()
            }
        }

        do {
            let remoteTables = try await NetworkManager.shared.fetchRestaurantTables()

            for remoteTable in remoteTables {
                guard let idStr = remoteTable["id"] as? String,
                      let id = UUID(uuidString: idStr) else { continue }

                let tableNumber = remoteTable["table_number"] as? String ?? ""
                let capacity = remoteTable["capacity"] as? Int ?? 2
                let status = remoteTable["status"] as? String ?? "vacant"
                let qrCodeIdentifier = remoteTable["qr_code_identifier"] as? String
                let positionX = remoteTable["position_x"] as? Double ?? 0.0
                let positionY = remoteTable["position_y"] as? Double ?? 0.0
                let floor = remoteTable["floor"] as? Int ?? 1
                let zone = remoteTable["zone"] as? String ?? "Indoor"
                let isDeleted = remoteTable["is_deleted"] as? Bool ?? false

                let updatedAtStr = remoteTable["updated_at"] as? String ?? ""
                let updatedAt = parseISO8601Date(updatedAtStr)

                var existingTable: RestaurantTable? = nil
                let idDescriptor = FetchDescriptor<RestaurantTable>(
                    predicate: #Predicate<RestaurantTable> { $0.id == id }
                )

                if let matches = try? modelContext.fetch(idDescriptor), let first = matches.first {
                    existingTable = first
                } else {
                    let numDescriptor = FetchDescriptor<RestaurantTable>(
                        predicate: #Predicate<RestaurantTable> { $0.tableNumber == tableNumber }
                    )
                    if let matches = try? modelContext.fetch(numDescriptor), !matches.isEmpty {
                        // Prioritize preserving the table that has active sessions or unsynced edits
                        let sortedMatches = matches.sorted { t1, t2 in
                            let t1HasActive = t1.sessions.contains(where: { $0.isActive })
                            let t2HasActive = t2.sessions.contains(where: { $0.isActive })
                            if t1HasActive != t2HasActive {
                                return t1HasActive && !t2HasActive
                            }
                            return !t1.isSynced && t2.isSynced
                        }

                        existingTable = sortedMatches.first
                        existingTable?.id = id

                        if sortedMatches.count > 1 {
                            for i in 1..<sortedMatches.count {
                                modelContext.delete(sortedMatches[i])
                            }
                        }
                    }
                }

                if let table = existingTable {
                    if isDeleted {
                        modelContext.delete(table)
                    } else {
                        table.tableNumber = tableNumber
                        table.capacity = capacity

                        // Supabase is authoritative. Active sessions are applied immediately
                        // afterwards by pullActiveSessions and will set occupied when needed.
                        table.status = status

                        table.qrCodeIdentifier = qrCodeIdentifier
                        table.positionX = positionX
                        table.positionY = positionY
                        table.floor = floor
                        table.zone = zone
                        table.isSynced = true
                        table.updatedAt = updatedAt
                    }
                } else if !isDeleted {
                    let newTable = RestaurantTable(
                        id: id,
                        tableNumber: tableNumber,
                        capacity: capacity,
                        status: status,
                        qrCodeIdentifier: qrCodeIdentifier,
                        positionX: positionX,
                        positionY: positionY,
                        floor: floor,
                        zone: zone,
                        isSynced: true,
                        isDeleted: false,
                        updatedAt: updatedAt
                    )
                    modelContext.insert(newTable)
                }
            }
            try? modelContext.save()
        } catch {
            print("SyncEngine [Table Pull Error]: \(error.localizedDescription)")
        }
    }

    // Pull active orders from customer mobile app and insert into local SwiftData store
    func pullCustomerOrders(_ modelContext: ModelContext) async {
        guard await NetworkManager.shared.isConnected() else { return }

        do {
            let remoteOrders = try await NetworkManager.shared.fetchCustomerOrders()

            // Track all remote order IDs to identify deleted orders later
            var remoteOrderIds = Set<UUID>()

            for remoteOrder in remoteOrders {
                guard let idString = remoteOrder["id"] as? String,
                      let orderId = UUID(uuidString: idString) else { continue }

                remoteOrderIds.insert(orderId)

                // Check if this order already exists locally
                let descriptor = FetchDescriptor<Order>(
                    predicate: #Predicate<Order> { $0.id == orderId }
                )

                let orderNumber = remoteOrder["orderNumber"] as? String ?? "ORD-UNKNOWN"
                let total = remoteOrder["total"] as? Double ?? 0.0
                let status = remoteOrder["status"] as? String ?? "preparing"
                let createdAtStr = remoteOrder["createdAt"] as? String ?? ""
                let tableNumber = remoteOrder["tableNumber"] as? String ?? ""

                let createdAt = parseISO8601Date(createdAtStr)

                // Find or create Table Session for this tableNumber
                let tableDescriptor = FetchDescriptor<RestaurantTable>(
                    predicate: #Predicate<RestaurantTable> { $0.tableNumber == tableNumber }
                )

                let sessionToken = remoteOrder["sessionToken"] as? String ?? remoteOrder["session_token"] as? String
                var targetTableSession: TableSession? = nil

                if let token = sessionToken {
                    let sessionDesc = FetchDescriptor<TableSession>(
                        predicate: #Predicate<TableSession> { $0.sessionToken == token }
                    )
                    if let sessions = try? modelContext.fetch(sessionDesc), let matchedSession = sessions.first {
                        targetTableSession = matchedSession
                    }
                }

                if targetTableSession == nil {
                    if let tables = try? modelContext.fetch(tableDescriptor), let table = tables.first {
                        if let activeSession = table.sessions.first(where: { $0.isActive }) {
                            if Calendar.current.isDateInToday(activeSession.startedAt) {
                                targetTableSession = activeSession
                            } else {
                                // Close stale session
                                activeSession.isActive = false
                                activeSession.endedAt = Date()
                                activeSession.isSynced = false
                                activeSession.updatedAt = Date()

                                let newSession = TableSession(startedAt: Date(), isActive: true, table: table)
                                if let token = sessionToken {
                                    newSession.sessionToken = token
                                }
                                modelContext.insert(newSession)
                                targetTableSession = newSession
                                table.status = "occupied"
                            }
                        } else {
                            let newSession = TableSession(startedAt: Date(), isActive: true, table: table)
                            if let token = sessionToken {
                                newSession.sessionToken = token
                            }
                            modelContext.insert(newSession)
                            targetTableSession = newSession
                            table.status = "occupied"
                        }
                    }
                }

                if let existingOrders = try? modelContext.fetch(descriptor), let existingOrder = existingOrders.first {
                    // Order already exists. Update its status, total, and ensure it links to the active session.
                    existingOrder.status = status
                    existingOrder.total = total
                    if existingOrder.tableSession == nil || existingOrder.tableSession != targetTableSession {
                        existingOrder.tableSession = targetTableSession
                    }

                    // Update order items
                    if let remoteItems = remoteOrder["items"] as? [[String: Any]] {
                        let remoteItemIds = Set(remoteItems.compactMap { remoteItem -> UUID? in
                            if let idStr = remoteItem["id"] as? String {
                                return UUID(uuidString: idStr)
                            }
                            return nil
                        })

                        // 1. Delete local items that are no longer present on the server
                        for localItem in existingOrder.items {
                            if !remoteItemIds.contains(localItem.id) {
                                modelContext.delete(localItem)
                            }
                        }

                        // 2. Add or update remote items
                        for remoteItem in remoteItems {
                            let itemIdStr = remoteItem["id"] as? String ?? ""
                            if let itemId = UUID(uuidString: itemIdStr) {
                                let name = remoteItem["name"] as? String ?? "Unknown Item"
                                let qty = remoteItem["quantity"] as? Int ?? 1
                                let price = remoteItem["price"] as? Double ?? 0.0
                                let itemStatus = remoteItem["status"] as? String ?? "cooking"

                                if let localItem = existingOrder.items.first(where: { $0.id == itemId }) {
                                    localItem.quantity = qty
                                    localItem.unitPrice = price
                                    localItem.subtotal = Double(qty) * price
                                    localItem.status = itemStatus
                                } else {
                                    // Item was added remotely, create it locally
                                    let itemDescriptor = FetchDescriptor<MenuItem>(
                                        predicate: #Predicate<MenuItem> { $0.name == name }
                                    )
                                    let menuItem = (try? modelContext.fetch(itemDescriptor))?.first

                                    let orderItem = OrderItem(
                                        id: itemId,
                                        order: existingOrder,
                                        menuItem: menuItem,
                                        quantity: qty,
                                        unitPrice: price,
                                        notes: nil,
                                        status: itemStatus
                                    )
                                    modelContext.insert(orderItem)
                                    existingOrder.items.append(orderItem)
                                }
                            }
                        }
                    }

                    // Update order payments
                    if let remotePayments = remoteOrder["payments"] as? [[String: Any]] {
                        let remotePaymentIds = Set(remotePayments.compactMap { remotePayment -> UUID? in
                            if let idStr = remotePayment["id"] as? String {
                                return UUID(uuidString: idStr)
                            }
                            return nil
                        })

                        // 1. Delete local payments that are no longer present on the server
                        for localPayment in existingOrder.payments {
                            if !remotePaymentIds.contains(localPayment.id) {
                                modelContext.delete(localPayment)
                            }
                        }

                        // 2. Add or update remote payments
                        for remotePayment in remotePayments {
                            let paymentIdStr = remotePayment["id"] as? String ?? ""
                            if let paymentId = UUID(uuidString: paymentIdStr) {
                                let amount = remotePayment["amount"] as? Double ?? 0.0
                                let method = remotePayment["paymentMethod"] as? String ?? "cash"
                                let pCreatedAtStr = remotePayment["createdAt"] as? String ?? ""
                                let pCreatedAt = parseISO8601Date(pCreatedAtStr)

                                if let localPayment = existingOrder.payments.first(where: { $0.id == paymentId }) {
                                    localPayment.amount = amount
                                    localPayment.paymentMethod = method
                                    localPayment.paidAt = pCreatedAt
                                } else {
                                    // Payment was added remotely, create it locally
                                    let newPayment = Payment(
                                        id: paymentId,
                                        order: existingOrder,
                                        paymentMethod: method,
                                        amount: amount,
                                        status: "completed",
                                        paidAt: pCreatedAt,
                                        isSynced: true // Already synced on server
                                    )
                                    modelContext.insert(newPayment)
                                    existingOrder.payments.append(newPayment)
                                }
                            }
                        }
                    }
                    try? modelContext.save()
                    continue
                }

                // Create new Order
                let newOrder = Order(
                    id: orderId,
                    orderNumber: orderNumber,
                    tableSession: targetTableSession,
                    orderType: "dine_in",
                    status: status,
                    total: total,
                    createdAt: createdAt,
                    isSynced: true // Already synced on server
                )

                modelContext.insert(newOrder)

                // Map items
                if let remoteItems = remoteOrder["items"] as? [[String: Any]] {
                    for remoteItem in remoteItems {
                        let name = remoteItem["name"] as? String ?? "Unknown Item"
                        let qty = remoteItem["quantity"] as? Int ?? 1
                        let price = remoteItem["price"] as? Double ?? 0.0
                        let itemStatus = remoteItem["status"] as? String ?? "cooking"
                        let itemIdStr = remoteItem["id"] as? String ?? ""
                        let itemId = UUID(uuidString: itemIdStr) ?? UUID()

                        // Find local MenuItem by name
                        let itemDescriptor = FetchDescriptor<MenuItem>(
                            predicate: #Predicate<MenuItem> { $0.name == name }
                        )
                        let localItem = (try? modelContext.fetch(itemDescriptor))?.first

                        let orderItem = OrderItem(
                            id: itemId,
                            order: newOrder,
                            menuItem: localItem,
                            quantity: qty,
                            unitPrice: price,
                            notes: nil,
                            status: itemStatus
                        )
                        modelContext.insert(orderItem)
                        newOrder.items.append(orderItem)
                    }
                }

                // Map payments
                if let remotePayments = remoteOrder["payments"] as? [[String: Any]] {
                    for remotePayment in remotePayments {
                        let paymentIdStr = remotePayment["id"] as? String ?? ""
                        let paymentId = UUID(uuidString: paymentIdStr) ?? UUID()
                        let amount = remotePayment["amount"] as? Double ?? 0.0
                        let method = remotePayment["paymentMethod"] as? String ?? "cash"
                        let pCreatedAtStr = remotePayment["createdAt"] as? String ?? ""
                        let pCreatedAt = parseISO8601Date(pCreatedAtStr)

                        let newPayment = Payment(
                            id: paymentId,
                            order: newOrder,
                            paymentMethod: method,
                            amount: amount,
                            status: "completed",
                            paidAt: pCreatedAt,
                            isSynced: true // Already synced on server
                        )
                        modelContext.insert(newPayment)
                        newOrder.payments.append(newPayment)
                    }
                }

                try modelContext.save()
                
                let age = Date().timeIntervalSince(createdAt)
                if !self.isFirstSync && age < 300 {
                    self.triggerLocalNotification(orderNumber: orderNumber, tableNumber: tableNumber)
                }
                
                #if DEBUG
                print("SyncEngine [Pull]: Inserted customer order \(orderNumber) for Table \(tableNumber) successfully.")
                #endif
            }

            // Delete local synced orders belonging to active table sessions that are no longer on the server
            let orderDescriptor = FetchDescriptor<Order>()
            if let localOrders = try? modelContext.fetch(orderDescriptor) {
                for localOrder in localOrders {
                    if localOrder.isSynced && !localOrder.isDeleted && localOrder.tableSession?.isActive == true {
                        if !remoteOrderIds.contains(localOrder.id) {
                            modelContext.delete(localOrder)
                            #if DEBUG
                            print("SyncEngine [Pull]: Deleted local order \(localOrder.orderNumber) because it was removed from the server.")
                            #endif
                        }
                    }
                }
                try? modelContext.save()
            }

        } catch {
            print("SyncEngine [Pull Customer Orders Error]: \(error.localizedDescription)")
        }
    }

    func pullActiveSessions(_ modelContext: ModelContext) async {
        guard await NetworkManager.shared.isConnected() else { return }
        do {
            let remoteSessions = try await NetworkManager.shared.fetchActiveSessions()
            let remoteActiveTables = Set(remoteSessions.compactMap { $0["tableNumber"] as? String })

            // 1. Deactivate local sessions that are no longer active on the server
            let allTablesDescriptor = FetchDescriptor<RestaurantTable>()
            if let allTables = try? modelContext.fetch(allTablesDescriptor) {
                for table in allTables {
                    let hasRemoteSession = remoteActiveTables.contains(table.tableNumber)

                    let tableNumber = table.tableNumber
                    let sessionDesc = FetchDescriptor<TableSession>(
                        predicate: #Predicate<TableSession> { $0.table?.tableNumber == tableNumber && $0.isActive }
                    )
                    let localActiveSessions = (try? modelContext.fetch(sessionDesc)) ?? []

                    for activeSession in localActiveSessions {
                        if !hasRemoteSession {
                            activeSession.isActive = false
                            activeSession.endedAt = Date()
                            table.status = "vacant"
                            table.updatedAt = Date()
                            #if DEBUG
                            print("SyncEngine [Session Pull]: Closed local active session for Table \(table.tableNumber). Status set to vacant.")
                            #endif
                        }
                    }
                    if localActiveSessions.isEmpty {
                        // If no local active session exists but table status is occupied/reserved, and there's no remote active session
                        if !hasRemoteSession && (table.status == "occupied" || table.status == "reserved") && table.isSynced {
                            table.status = "vacant"
                            table.updatedAt = Date()
                            #if DEBUG
                            print("SyncEngine [Session Pull]: Reset out-of-sync table status for Table \(table.tableNumber) to vacant.")
                            #endif
                        }
                    }
                }
            }

            // 2. Process active remote sessions
            for session in remoteSessions {
                guard let tableNumber = session["tableNumber"] as? String,
                      let sessionToken = session["sessionToken"] as? String else { continue }

                // An explicitly active cloud session remains authoritative across midnight.
                let startedAtStr = session["started_at"] as? String ?? session["created_at"] as? String ?? ""
                let startedAt = parseISO8601Date(startedAtStr)

                // Fetch table locally
                let tableDescriptor = FetchDescriptor<RestaurantTable>(
                    predicate: #Predicate<RestaurantTable> { $0.tableNumber == tableNumber }
                )
                if let tables = try? modelContext.fetch(tableDescriptor), let table = tables.first {
                    // Fetch active session directly from database to avoid SwiftData caching/existential issues
                    let sessionDesc = FetchDescriptor<TableSession>(
                        predicate: #Predicate<TableSession> { $0.table?.tableNumber == tableNumber && $0.isActive }
                    )
                    let localActiveSessions = (try? modelContext.fetch(sessionDesc)) ?? []

                    var foundMatchingSession = false
                    for activeSession in localActiveSessions {
                        if activeSession.sessionToken == sessionToken {
                            activeSession.startedAt = startedAt
                            let remoteGuestCount = (session["guest_count"] as? Int) ?? (session["guestCount"] as? Int) ?? 2
                            if activeSession.guestCount != remoteGuestCount {
                                activeSession.guestCount = remoteGuestCount
                            }
                            if table.status != "occupied" {
                                table.status = "occupied"
                                table.updatedAt = Date()
                            }
                            foundMatchingSession = true
                        } else {
                            activeSession.isActive = false
                            activeSession.endedAt = Date()
                            #if DEBUG
                            print("SyncEngine [Session Pull]: Closed stale local session \(activeSession.sessionToken ?? "") because it mismatches remote session \(sessionToken)")
                            #endif
                        }
                    }

                    if !foundMatchingSession {
                        // No active session locally matches the remote session token. Create one!
                        let remoteGuestCount = (session["guest_count"] as? Int) ?? (session["guestCount"] as? Int) ?? 2
                        let newSession = TableSession(sessionToken: sessionToken, startedAt: startedAt, isActive: true, table: table, guestCount: remoteGuestCount)
                        modelContext.insert(newSession)
                        table.status = "occupied"
                        table.updatedAt = Date()
                        #if DEBUG
                        print("SyncEngine [Session Pull]: Active session detected for Table \(tableNumber) with \(remoteGuestCount) guests. Status set to occupied.")
                        #endif
                    }
                }
            }
            try? modelContext.save()
        } catch {
            print("SyncEngine [Sessions Pull Error]: \(error.localizedDescription)")
        }
    }

    func syncServiceRequests() async {
        guard await NetworkManager.shared.isConnected() else { return }
        do {
            let remoteRequests = try await NetworkManager.shared.fetchServiceRequests()
            var newRequests: [ServiceRequest] = []
            for req in remoteRequests {
                if let id = req["id"] as? String,
                   let tableNum = req["tableNumber"] as? String,
                   let type = req["requestType"] as? String,
                   let status = req["status"] as? String,
                   let createdAt = req["createdAt"] as? String {
                    let request = ServiceRequest(id: id, tableNumber: tableNum, requestType: type, status: status, createdAt: createdAt)
                    newRequests.append(request)

                    if status == "pending" {
                        let alreadyNotified = self.notifiedRequestIds.contains(id)
                        if !alreadyNotified {
                            self.notifiedRequestIds.insert(id)
                            self.triggerServiceRequestNotification(tableNumber: tableNum, requestType: type)
                        }
                    }
                }
            }

            await MainActor.run {
                self.activeRequests = newRequests
            }
        } catch {
            print("SyncEngine [Service Requests Sync Error]: \(error.localizedDescription)")
        }
    }

    // MARK: - Supabase Realtime WebSocket Client

    private var webSocketTask: URLSessionWebSocketTask?
    private let config = AppConfig.shared
    private lazy var anonKey: String = config.supabaseAnonKey

    private let syncLock = OSAllocatedUnfairLock()

    // Reconnection: Exponential backoff state
    private var _reconnectAttempt: Int = 0
    private var reconnectAttempt: Int {
        get { syncLock.lock(); defer { syncLock.unlock() }; return _reconnectAttempt }
        set { syncLock.lock(); defer { syncLock.unlock() }; _reconnectAttempt = newValue }
    }
    private let maxReconnectDelay: TimeInterval = 30.0

    // Debounce: Prevent rapid-fire pulls from multiple Realtime events
    private var realtimeDebounceWorkItem: DispatchWorkItem?

    // Guard: Prevent circular sync (iPad push → receive own event → pull again)
    private var _isCurrentlySyncing: Bool = false
    private var isCurrentlySyncing: Bool {
        get { syncLock.lock(); defer { syncLock.unlock() }; return _isCurrentlySyncing }
        set { syncLock.lock(); defer { syncLock.unlock() }; _isCurrentlySyncing = newValue }
    }

    // Heartbeat: Store timer reference to prevent leak on reconnect
    private var heartbeatTimer: Timer?

    func startRealtimeSync(modelContext: ModelContext) {
        self.cachedModelContext = modelContext
        guard webSocketTask == nil else { return }

        let wsURLString = "\(config.supabaseURL.absoluteString.replacingOccurrences(of: "https://", with: "wss://"))/realtime/v1/websocket?apikey=\(anonKey)&vsn=1.0.0"
        guard let url = URL(string: wsURLString) else { return }

        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: url)
        self.webSocketTask = task
        task.resume()

        // Listen to incoming messages
        listenToWebSocket(modelContext: modelContext)

        // Join realtime topic
        joinRealtimeTopic()

        // Keep-alive heartbeat every 20 seconds (invalidate any existing timer first)
        startHeartbeat()

        // Reset reconnect counter on successful connection
        reconnectAttempt = 0
    }

    private func listenToWebSocket(modelContext: ModelContext) {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleWebSocketMessage(text, modelContext: modelContext)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleWebSocketMessage(text, modelContext: modelContext)
                    }
                @unknown default:
                    break
                }
                // Keep listening
                self.listenToWebSocket(modelContext: modelContext)
            case .failure(let error):
                print("SyncEngine WebSocket error: \(error.localizedDescription)")
                self.webSocketTask = nil
                self.heartbeatTimer?.invalidate()
                self.heartbeatTimer = nil

                // Exponential backoff: 2s → 4s → 8s → 16s → 30s max
                let delay = min(maxReconnectDelay, pow(2.0, Double(reconnectAttempt)) * 1.0)
                // Add jitter (±25%) to prevent thundering herd
                let jitter = delay * Double.random(in: -0.25...0.25)
                let finalDelay = max(1.0, delay + jitter)
                reconnectAttempt += 1

                #if DEBUG
                print("SyncEngine: Reconnecting in \(String(format: "%.1f", finalDelay))s (attempt \(reconnectAttempt))")
                #endif

                DispatchQueue.main.asyncAfter(deadline: .now() + finalDelay) {
                    self.startRealtimeSync(modelContext: modelContext)
                }
            }
        }
    }

    private func joinRealtimeTopic() {
        let rawMerchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        let merchantId = rawMerchantId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? config.defaultMerchantId.lowercased() : rawMerchantId.lowercased()

        let accessToken = MerchantAuthManager.shared.currentToken ?? anonKey
        let joinPayload: [String: Any] = [
            "topic": "realtime:public",
            "event": "phx_join",
            "payload": [
                "config": [
                    "postgres_changes": [
                        ["event": "*", "schema": "public", "table": "orders", "filter": "merchant_id=eq.\(merchantId)"],
                        ["event": "*", "schema": "public", "table": "order_items", "filter": "merchant_id=eq.\(merchantId)"],
                        ["event": "*", "schema": "public", "table": "table_sessions", "filter": "merchant_id=eq.\(merchantId)"],
                        ["event": "*", "schema": "public", "table": "service_requests", "filter": "merchant_id=eq.\(merchantId)"],
                        ["event": "*", "schema": "public", "table": "restaurant_tables", "filter": "merchant_id=eq.\(merchantId)"],
                        ["event": "*", "schema": "public", "table": "merchants", "filter": "id=eq.\(merchantId)"]
                    ]
                ],
                "access_token": accessToken
            ],
            "ref": "1"
        ]

        if let data = try? JSONSerialization.data(withJSONObject: joinPayload, options: []),
           let jsonString = String(data: data, encoding: .utf8) {
            webSocketTask?.send(.string(jsonString)) { error in
                if let error = error {
                    print("SyncEngine: Failed to send join payload: \(error)")
                } else {
                    print("SyncEngine: Successfully sent join payload for postgres changes (merchant-scoped).")
                }
            }
        }
    }

    private func startHeartbeat() {
        // Invalidate any existing heartbeat timer to prevent leak
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil

        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 20.0, repeats: true) { [weak self] timer in
            guard let self = self, let task = self.webSocketTask else {
                timer.invalidate()
                return
            }
            let heartbeat: [String: Any] = [
                "topic": "phoenix",
                "event": "heartbeat",
                "payload": [:],
                "ref": "heartbeat"
            ]
            if let data = try? JSONSerialization.data(withJSONObject: heartbeat, options: []),
               let jsonString = String(data: data, encoding: .utf8) {
                task.send(.string(jsonString)) { error in
                    if let error = error {
                        print("SyncEngine heartbeat failed: \(error)")
                    }
                }
            }
        }
    }

    private func handleWebSocketMessage(_ text: String, modelContext: ModelContext) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let event = json["event"] as? String else { return }

        // Supabase Realtime V1 sends postgres change events with event name "postgres_changes".
        // Also handle system events and detect changes from payload for robustness.
        let isPostgresChange: Bool
        if event == "postgres_changes" {
            isPostgresChange = true
        } else if event == "phx_reply" || event == "system" || event == "phx_close" {
            // Handle connection lifecycle events
            #if DEBUG
            if event == "phx_reply" {
                if let payload = json["payload"] as? [String: Any],
                   let status = payload["status"] as? String {
                    print("SyncEngine [Realtime]: phx_reply status = \(status)")
                }
            }
            #endif
            isPostgresChange = false
        } else {
            // Catch any other events that contain postgres change data in payload
            if let payload = json["payload"] as? [String: Any],
               let _ = payload["data"] as? [String: Any] {
                isPostgresChange = true
            } else {
                isPostgresChange = false
            }
        }

        guard isPostgresChange else { return }

        // Guard against circular sync: if we are currently pushing data, skip pull
        guard !isCurrentlySyncing else {
            #if DEBUG
            print("SyncEngine [Realtime]: Skipping pull — currently syncing (avoiding circular sync).")
            #endif
            return
        }

        // Debounce: Cancel any pending pull and schedule a new one after 1.5 seconds.
        // This batches multiple rapid Realtime events into a single pull operation.
        realtimeDebounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            Task {
                #if DEBUG
                print("SyncEngine [Realtime]: Database change detected. Performing debounced pull...")
                #endif
                self.isCurrentlySyncing = true
                await self.pullRestaurantTables(modelContext)
                await self.pullCustomerOrders(modelContext)
                await self.pullActiveSessions(modelContext)
                await self.syncServiceRequests()
                self.isCurrentlySyncing = false
            }
        }
        realtimeDebounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: workItem)
    }


    // MARK: - Table Sessions Sync (Guest Count)

    /// Sync table sessions: upload local unsync'd sessions, then pull latest from Supabase
    private func syncTableSessionsNew(_ modelContext: ModelContext) async {

        // Phase 1: Upload unsync'd local table sessions
        await uploadUnsyncedTableSessions(modelContext: modelContext)

        // Phase 2: Pull latest table sessions from Supabase
        await pullTableSessionsFromSupabase(modelContext: modelContext)
    }

    /// Upload all unsync'd table sessions to Supabase
    private func uploadUnsyncedTableSessions(modelContext: ModelContext) async {
        do {
            let descriptor = FetchDescriptor<TableSession>(
                predicate: #Predicate<TableSession> { session in
                    !session.isSynced && !session.isDeleted
                }
            )

            let unsyncedSessions = try modelContext.fetch(descriptor)
            guard !unsyncedSessions.isEmpty else {
                #if DEBUG
                print("[SyncEngine] No unsync'd table sessions to upload")
                #endif
                return
            }

            #if DEBUG
            print("[SyncEngine] Uploading \(unsyncedSessions.count) unsync'd table sessions...")
            #endif

            for session in unsyncedSessions {
                let uploadSuccess = await uploadTableSession(session, modelContext: modelContext)

                if uploadSuccess {
                    session.isSynced = true
                    session.updatedAt = Date()
                    #if DEBUG
                    print("[SyncEngine] ✅ Uploaded table session \(session.id.uuidString) - guests: \(session.guestCount)")
                    #endif
                } else {
                    #if DEBUG
                    print("[SyncEngine] ⚠️ Failed to upload table session \(session.id.uuidString)")
                    #endif
                }
            }

            try modelContext.save()

        } catch {
            #if DEBUG
            print("[SyncEngine] Error uploading table sessions: \(error.localizedDescription)")
            #endif
        }
    }

    /// Upload a single table session to Supabase
    private func uploadTableSession(_ session: TableSession, modelContext: ModelContext) async -> Bool {
        do {
            let _: [String: Any] = [
                "id": session.id.uuidString,
                "merchant_id": UserDefaults.standard.string(forKey: "activeMerchantId") ?? "",
                "table_id": session.table?.id.uuidString ?? "",
                "guest_count": session.guestCount,
                "session_token": session.sessionToken,
                "started_at": iso8601Format(session.startedAt),
                "ended_at": session.endedAt.map { iso8601Format($0) } as Any? ?? NSNull(),
                "is_active": session.isActive,
                "updated_at": iso8601Format(Date()),
                "is_synced": true,
                "is_deleted": false
            ]

            let success = try await NetworkManager.shared.uploadTableSession(
                session: session
            )

            return success

        } catch {
            #if DEBUG
            print("[SyncEngine] Failed to upload table session: \(error.localizedDescription)")
            #endif
            return false
        }
    }

    /// Pull latest table sessions from Supabase and update local SwiftData
    private func pullTableSessionsFromSupabase(modelContext: ModelContext) async {
        do {
            #if DEBUG
            print("[SyncEngine] Pulling table sessions from Supabase...")
            #endif

            let remoteSessions = try await NetworkManager.shared.fetchActiveSessions()

            #if DEBUG
            print("[SyncEngine] Received \(remoteSessions.count) table sessions from Supabase")
            #endif

            // Update local SwiftData with remote sessions
            for remoteSession in remoteSessions {
                await updateLocalTableSession(remoteSession, modelContext: modelContext)
            }

        } catch {
            #if DEBUG
            print("[SyncEngine] Failed to pull table sessions from Supabase: \(error.localizedDescription)")
            #endif
        }
    }

    /// Update local TableSession with data from Supabase, creating if not exists
    private func updateLocalTableSession(_ remote: [String: Any], modelContext: ModelContext) async {
        do {
            guard let idStr = remote["id"] as? String,
                  let sessionId = UUID(uuidString: idStr),
                  let guestCount = remote["guest_count"] as? Int,
                  let sessionToken = remote["session_token"] as? String
            else {
                return
            }

            let descriptor = FetchDescriptor<TableSession>(
                predicate: #Predicate<TableSession> { $0.id == sessionId }
            )
            let existing = try modelContext.fetch(descriptor).first

            if let existing = existing {
                // Update existing
                existing.guestCount = guestCount
                existing.isSynced = true
                existing.updatedAt = Date()

                #if DEBUG
                print("[SyncEngine] Updated table session \(sessionId.uuidString) - guests: \(guestCount)")
                #endif

            } else {
                // Create new local session
                let newSession = TableSession(
                    id: sessionId,
                    sessionToken: sessionToken,
                    guestCount: guestCount,
                    isSynced: true,
                    isDeleted: false,
                    updatedAt: Date()
                )

                modelContext.insert(newSession)
                #if DEBUG
                print("[SyncEngine] Created new table session \(sessionId.uuidString)")
                #endif
            }

            try modelContext.save()

        } catch {
            #if DEBUG
            print("[SyncEngine] Error updating local table session: \(error.localizedDescription)")
            #endif
        }
    }

    // MARK: - Helpers

    /// Format Date to ISO8601 string for Supabase
    private func iso8601Format(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private func checkForDelayedOrders(modelContext: ModelContext) async {
        let descriptor = FetchDescriptor<Order>()
        guard var orders = try? modelContext.fetch(descriptor) else { return }

        // Sort by createdAt ascending (FIFO)
        orders.sort(by: { $0.createdAt < $1.createdAt })

        let now = Date()

        // Filter orders that are older than 10 minutes (600 seconds) and not yet delivered/served
        let delayedOrders = orders.filter { order in
            let isOlderThan10Min = now.timeIntervalSince(order.createdAt) >= 600
            if order.status == "preparing" {
                let hasActiveItems = order.items.contains(where: { $0.status == "cooking" || $0.status == "alert" })
                return hasActiveItems && isOlderThan10Min
            } else if order.status == "ready" {
                return isOlderThan10Min
            }
            return false
        }

        // If there are any delayed orders, get the oldest one (FIFO priority)
        guard let oldestDelayedOrder = delayedOrders.first else { return }

        let orderId = oldestDelayedOrder.id
        let tableNum = oldestDelayedOrder.tableSession?.table?.tableNumber ?? "1"
        let orderNum = String(oldestDelayedOrder.orderNumber.suffix(4))

        // Check if we should trigger the alert (either first time, or 10 minutes passed since last alert for this specific order)
        let shouldAlert: Bool
        if let lastAlert = SyncEngine.getAlertTime(orderId) {
            shouldAlert = now.timeIntervalSince(lastAlert) >= 600
        } else {
            shouldAlert = true
        }

        if shouldAlert {
            SyncEngine.setAlertTime(orderId, now)

            // 1. Create a service request on the server to notify AlphaPos and AlphaPosStaff
            let alertType: String
            let notificationBody: String
            if oldestDelayedOrder.status == "ready" {
                alertType = "Delivery Alert: Table \(tableNum) (#\(orderNum)) has been ready but not delivered for over 10 minutes!"
                notificationBody = "Table \(tableNum) (#\(orderNum)) has been ready but not delivered for over 10 minutes."
            } else {
                alertType = "Cooking Alert: Table \(tableNum) (#\(orderNum)) has had items cooking for more than 10 minutes!"
                notificationBody = "Table \(tableNum) (#\(orderNum)) has been cooking for over 10 minutes."
            }

            _ = try? await NetworkManager.shared.createServiceRequest(tableNumber: tableNum, type: alertType)

            // 2. Trigger local system notification on this iPad
            let content = UNMutableNotificationContent()
            content.title = oldestDelayedOrder.status == "ready" ? "Delivery Alert!" : "Cooking Alert!"
            content.body = notificationBody
            content.sound = UNNotificationSound.default

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            let request = UNNotificationRequest(
                identifier: "delayed-\(orderId.uuidString)",
                content: content,
                trigger: trigger
            )
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    /// Syncs unsynced Printers to Supabase
    private func syncPrinters(_ modelContext: ModelContext) async {
        let descriptor = FetchDescriptor<Printer>(
            predicate: #Predicate<Printer> { $0.isSynced == false }
        )
        guard let printers = try? modelContext.fetch(descriptor), !printers.isEmpty else { return }

        for printer in printers {
            do {
                if printer.isDeleted {
                    _ = try await NetworkManager.shared.deletePrinterOnServer(id: printer.id)
                    modelContext.delete(printer)
                } else {
                    let success = try await NetworkManager.shared.uploadPrinter(printer)
                    if success {
                        printer.isSynced = true
                    }
                }
            } catch {
                print("SyncEngine [Printer Sync Error]: \(error.localizedDescription)")
            }
        }
        try? modelContext.save()
    }

    /// Syncs unsynced PrintRoutingRules to Supabase
    private func syncPrintRoutingRules(_ modelContext: ModelContext) async {
        let descriptor = FetchDescriptor<PrintRoutingRule>(
            predicate: #Predicate<PrintRoutingRule> { $0.isSynced == false }
        )
        guard let rules = try? modelContext.fetch(descriptor), !rules.isEmpty else { return }

        for rule in rules {
            do {
                if rule.isDeleted {
                    _ = try await NetworkManager.shared.deletePrintRoutingRuleOnServer(id: rule.id)
                    modelContext.delete(rule)
                } else {
                    let success = try await NetworkManager.shared.uploadPrintRoutingRule(rule)
                    if success {
                        rule.isSynced = true
                    }
                }
            } catch {
                print("SyncEngine [PrintRoutingRule Sync Error]: \(error.localizedDescription)")
            }
        }
        try? modelContext.save()
    }
}

extension Notification.Name {
    static let openTableNotification = Notification.Name("openTableNotification")
}
