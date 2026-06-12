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
    
    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        requestNotificationPermission()
        setupLifecycleObservers()
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
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound, .badge])
    }
    
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
        await syncTables(modelContext)
        await syncTableSessions(modelContext)
        await syncEmployees(modelContext)
        await syncOrders(modelContext)
        await syncPayments(modelContext)
        await syncTimecards(modelContext)
        await syncInventoryTransactions(modelContext)
        await syncMenuItems(modelContext)
        await syncPromotions(modelContext)
        await syncPurchaseOrders(modelContext)
        await syncDeliveryPrices(modelContext)
        await syncPrinters(modelContext)
        await syncPrintRoutingRules(modelContext)
        
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
        
        // Check for delayed orders and dispatch alerts
        await checkForDelayedOrders(modelContext: modelContext)
        
        await MainActor.run {
            self.syncStatus = .idle
            self.lastSyncedAt = Date()
        }
        
        #if DEBUG
        print("SyncEngine: Sync completed.")
        #endif
    }
    
    // MARK: - Sync Helpers
    
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
                    notes: timecard.notes
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
                    itemName: itemName,
                    quantity: txn.quantity,
                    type: txn.transactionType
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
                    // Update if name, price, description, or imageUrl changed
                    var changed = false
                    if existing.name != name { existing.name = name; changed = true }
                    if abs((existing.price) - price) > 0.001 { existing.price = price; changed = true }
                    if (existing.itemDescription ?? "") != desc { existing.itemDescription = desc; changed = true }
                    if (existing.imageUrl ?? "") != imageUrl { existing.imageUrl = imageUrl; changed = true }
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
                        category: category
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
                    _ = try await NetworkManager.shared.deletePromotionOnServer(id: promotion.id)
                    modelContext.delete(promotion)
                    try modelContext.save()
                } catch {
                    print("SyncEngine [Promotion Delete Error]: \(error.localizedDescription)")
                }
                continue
            }
            
            do {
                let success = try await NetworkManager.shared.uploadPromotion(promotion: promotion)
                if success {
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
            
            // Fetch ALL local promotions (including soft-deleted ones) so we can match by ID
            let localPromos = (try? modelContext.fetch(FetchDescriptor<Promotion>())) ?? []
            
            var localPromosById: [String: Promotion] = [:]
            for promo in localPromos {
                localPromosById[promo.id.uuidString.lowercased()] = promo
            }
            
            // If Supabase returned nothing, nothing to do (deletions are handled by syncPromotions push)
            guard !remotePromos.isEmpty else { return }
            
            var didChange = false
            let df = ISO8601DateFormatter()
            
            for remote in remotePromos {
                guard let idStr = remote["id"] as? String,
                      let id = UUID(uuidString: idStr),
                      let title = remote["title"] as? String else { continue }
                
                let desc = remote["promo_description"] as? String
                let imageData = remote["image_data"] as? String
                
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
                let updatedAt = df.date(from: updatedAtStr) ?? Date()
                
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
                            if existing.isActive != isActive { existing.isActive = isActive; changed = true }
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
                        isActive: isActive,
                        isSynced: true,
                        isDeleted: false,
                        updatedAt: updatedAt
                    )
                    modelContext.insert(newPromo)
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
    
    private func syncMerchant() async {
        guard let merchantIdStr = UserDefaults.standard.string(forKey: "active_merchant_id"),
              let merchantId = UUID(uuidString: merchantIdStr) else { return }
        
        let name = UserDefaults.standard.string(forKey: "store_name") ?? UserDefaults.standard.string(forKey: "logged_in_name") ?? "My New POS Shop"
        let email = UserDefaults.standard.string(forKey: "logged_in_email") ?? "owner@alphapos.com"
        let kitchenWorkflowRequired = UserDefaults.standard.object(forKey: "kitchen_workflow_required") as? Bool ?? true
        
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
        
        do {
            _ = try await NetworkManager.shared.uploadMerchant(
                id: merchantId,
                name: name,
                email: email,
                kitchenWorkflowRequired: kitchenWorkflowRequired,
                phone: phone,
                website: website,
                address: address,
                taxId: taxId,
                branchCode: branchCode,
                taxRate: taxRate,
                taxType: taxType,
                serviceChargeRate: serviceChargeRate,
                receiptHeader: receiptHeader,
                receiptFooter: receiptFooter
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
                
                let df = ISO8601DateFormatter()
                let updatedAtStr = remoteTable["updated_at"] as? String ?? ""
                let updatedAt = df.date(from: updatedAtStr) ?? Date()
                
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
                    } else if table.isSynced || updatedAt > table.updatedAt {
                        table.tableNumber = tableNumber
                        table.capacity = capacity
                        
                        // Defer status to pullActiveSessions to avoid flickering.
                        // Only apply the cloud status if there is NO local active session.
                        // If an active session exists, pullActiveSessions will set the correct status.
                        let sessionDesc = FetchDescriptor<TableSession>(
                            predicate: #Predicate<TableSession> { $0.table?.tableNumber == tableNumber && $0.isActive }
                        )
                        let hasLocalActiveSession = ((try? modelContext.fetch(sessionDesc)) ?? []).first != nil
                        
                        if !hasLocalActiveSession {
                            // No active session locally — safe to use cloud status
                            // But only set to "vacant" if cloud says so; avoid overriding
                            // statuses like "cleaning" or "reserved" set by staff
                            table.status = status
                        }
                        // If hasLocalActiveSession == true, keep current status (pullActiveSessions will reconcile)
                        
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
                
                let df = ISO8601DateFormatter()
                let createdAt = df.date(from: createdAtStr) ?? Date()
                
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
                                let pCreatedAt = df.date(from: pCreatedAtStr) ?? Date()
                                
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
                        let pCreatedAt = df.date(from: pCreatedAtStr) ?? Date()
                        
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
                self.triggerLocalNotification(orderNumber: orderNumber, tableNumber: tableNumber)
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
                        if !Calendar.current.isDateInToday(activeSession.startedAt) {
                            activeSession.isActive = false
                            activeSession.endedAt = Date()
                            activeSession.isSynced = false
                            activeSession.updatedAt = Date()
                            table.status = "vacant"
                            table.updatedAt = Date()
                            
                            let tNum = table.tableNumber
                            Task {
                                _ = try? await NetworkManager.shared.closeTableSession(tableNumber: tNum)
                            }
                            #if DEBUG
                            print("SyncEngine [Session Pull]: Expired stale local active session (from previous day) for Table \(table.tableNumber).")
                            #endif
                        } else if !hasRemoteSession && activeSession.isSynced {
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
                
                // Check if session started today
                let startedAtStr = session["created_at"] as? String ?? ""
                let df = ISO8601DateFormatter()
                let startedAt = df.date(from: startedAtStr) ?? Date()
                
                if !Calendar.current.isDateInToday(startedAt) {
                    // Stale active session from remote! Close it on remote asynchronously and ignore it.
                    Task {
                        _ = try? await NetworkManager.shared.closeTableSession(tableNumber: tableNumber)
                    }
                    #if DEBUG
                    print("SyncEngine [Session Pull]: Ignored stale remote session for Table \(tableNumber) (started at \(startedAtStr)) and closed it.")
                    #endif
                    continue
                }
                
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
                    
                    if let activeSession = localActiveSessions.first {
                        if activeSession.sessionToken != sessionToken {
                            activeSession.sessionToken = sessionToken
                        }
                        let remoteGuestCount = (session["guest_count"] as? Int) ?? (session["guestCount"] as? Int) ?? 2
                        if activeSession.guestCount != remoteGuestCount {
                            activeSession.guestCount = remoteGuestCount
                        }
                        if table.status != "occupied" {
                            table.status = "occupied"
                            table.updatedAt = Date()
                        }
                    } else {
                        // No active session locally. Create one and mark occupied!
                        let remoteGuestCount = (session["guest_count"] as? Int) ?? (session["guestCount"] as? Int) ?? 2
                        let newSession = TableSession(sessionToken: sessionToken, startedAt: Date(), isActive: true, table: table, guestCount: remoteGuestCount)
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
                ]
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

