import Foundation
import SwiftData
import Combine
import UIKit
import os
import AVFoundation

// MARK: - Lifecycle Observers + In-App Notification Triggers
// ไม่ใช้ UNUserNotificationCenter — ใช้ InAppNotificationManager แทน
// เพื่อหลีกเลี่ยง Push Notifications capability ที่ Personal Team ไม่รองรับ
extension SyncEngine {
    func setupLifecycleObservers() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
            guard let self else { return }
            #if DEBUG
            print("SyncEngine: App returned to foreground. Reconnecting WebSocket...")
            #endif
            self.webSocketTask?.cancel(with: .normalClosure, reason: nil)
            self.webSocketTask = nil
            self.realtimeListenTask?.cancel()
            self.realtimeListenTask = nil
            if let context = self.cachedModelContext {
                self.startRealtimeSync(modelContext: context)
                Task { await self.syncAll(modelContext: context) }
            }
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name("merchantTokenDidRefresh"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
            guard let self else { return }
            #if DEBUG
            print("SyncEngine: JWT token refreshed. Reconnecting WebSocket...")
            #endif
            self.webSocketTask?.cancel(with: .normalClosure, reason: nil)
            self.webSocketTask = nil
            self.realtimeListenTask?.cancel()
            self.realtimeListenTask = nil
            self.heartbeatTimer?.invalidate()
            self.heartbeatTimer = nil
            if let context = self.cachedModelContext {
                self.startRealtimeSync(modelContext: context)
            }
            }
        }
    }

    // MARK: - In-App Notification Triggers (แทนที่ UNUserNotificationCenter)

    /// แจ้งเตือนออเดอร์ใหม่จากลูกค้า — ทำงานเฉพาะเมื่อแอปเปิดอยู่
    func triggerLocalNotification(orderNumber: String, tableNumber: String) {
        Task { @MainActor in
            InAppNotificationManager.shared.postNewOrder(
                orderNumber: orderNumber,
                tableNumber: tableNumber
            )
        }
    }

    /// แจ้งเตือนลูกค้าเรียก Staff — ทำงานเฉพาะเมื่อแอปเปิดอยู่
    func triggerServiceRequestNotification(tableNumber: String, requestType: String) {
        Task { @MainActor in
            InAppNotificationManager.shared.postServiceRequest(
                tableNumber: tableNumber,
                requestType: requestType
            )
        }
    }

    /// แจ้งเตือนกะงานค้างเปิดนาน — throttle 6 ชั่วโมง
    func triggerStaleShiftNotification(hoursOpen: Int) {
        let lastNotifiedKey = "last_stale_shift_notification_time"
        if let lastNotified = UserDefaults.standard.object(forKey: lastNotifiedKey) as? Date {
            if Date().timeIntervalSince(lastNotified) < 3600 * 6 { return }
        }
        UserDefaults.standard.set(Date(), forKey: lastNotifiedKey)
        Task { @MainActor in
            InAppNotificationManager.shared.postStaleShift(hoursOpen: hoursOpen)
        }
    }

    // MARK: - Sync Orchestration

    func syncAll(modelContext: ModelContext) async {
        if let activeSyncTask {
            await activeSyncTask.value
            return
        }
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performSync(modelContext: modelContext)
        }
        activeSyncTask = task
        await task.value
        activeSyncTask = nil
    }

    func performSync(modelContext: ModelContext) async {
        encounteredSyncError = false

        // ─── Offline / Online Mode Gate ────────────────────────────────────
        let isOfflineModeOn = UserDefaults.standard.bool(forKey: "offline_sync_mode")
        NetworkManager.shared.simulateOffline = isOfflineModeOn
        if isOfflineModeOn {
            await MainActor.run { self.syncStatus = .offline }
            return
        }
        // ─── End Offline Gate ──────────────────────────────────────────────

        // Check for stale RegisterSession
        await MainActor.run {
            var descriptor = FetchDescriptor<RegisterSession>(
                predicate: #Predicate<RegisterSession> { $0.closedAt == nil && !$0.isDeleted }
            )
            descriptor.fetchLimit = 500
            if let sessions = try? modelContext.fetch(descriptor), let activeShift = sessions.first {
                let hoursOpen = Calendar.current.dateComponents([.hour], from: activeShift.openedAt, to: Date()).hour ?? 0
                if hoursOpen >= 24 {
                    self.triggerStaleShiftNotification(hoursOpen: hoursOpen)
                }
            }
        }

        await MainActor.run { self.startRealtimeSync(modelContext: modelContext) }

        guard await NetworkManager.shared.isConnected() else {
            #if DEBUG
            print("SyncEngine: Device is offline. Sync task aborted.")
            #endif
            await MainActor.run { self.syncStatus = .offline }
            return
        }

        await MainActor.run { self.syncStatus = .syncing }
        #if DEBUG
        print("SyncEngine: Initiating data synchronization...")
        #endif

        // ─── Stage 1: Pushes (Sequential to respect foreign key & relationship constraints) ───
        await syncMerchant()
        await syncSecurityPolicies(modelContext)
        await syncRoles(modelContext)
        await syncRolePermissions(modelContext)
        await syncMerchantDevices(modelContext)
        await syncUsers(modelContext)
        await syncEmployees(modelContext)
        await syncStaffSessions(modelContext)
        await syncAuditLogs(modelContext)
        await syncTables(modelContext)
        await syncTableSessions(modelContext)
        await syncFloorPlanImages(modelContext)
        await syncRestaurantWalls(modelContext)
        await syncTableLayoutPresets(modelContext)
        await syncEmployeeShifts(modelContext)
        await syncOrders(modelContext)
        await syncPayments(modelContext)
        await syncOrderDiscounts(modelContext)
        await syncOrderTaxLines(modelContext)
        await syncTips(modelContext)
        await syncOrderItemModifiers(modelContext)
        await syncTimecards(modelContext)
        await syncRegisterSessions(modelContext)
        await syncCashMovements(modelContext)
        await syncShiftReports(modelContext)

        await syncCategories(modelContext)
        await syncModifierGroups(modelContext)
        await syncModifiers(modelContext)
        await syncMenuItemModifierGroups(modelContext)

        await syncBranches(modelContext)
        await syncSuppliers(modelContext)
        await syncInventoryItemsWithRetry(modelContext)
        await syncInventoryTransactionsWithRetry(modelContext)
        await syncInventoryLotsWithRetry(modelContext)          // Expiry/FEFO lots (retry-enabled)
        await syncRecipes(modelContext)
        await syncMenuItems(modelContext)
        await syncPromotions(modelContext)
        await syncPromotionBundleItems(modelContext)
        await syncPurchaseOrders(modelContext)
        await syncDeliveryPrices(modelContext)
        await syncPrinters(modelContext)
        await syncPrintRoutingRules(modelContext)
        await syncReceiptTemplates(modelContext)
        await syncCustomers(modelContext)
        await syncGiftCards(modelContext)
        await syncLoyaltyTransactions(modelContext)
        await syncTaxRates(modelContext)
        await syncCurrencyExchangeRates(modelContext)
        await syncExpenses(modelContext)
        await syncRefundTransactions(modelContext)

        // ─── Stage 2: Pulls (Concurrent using TaskGroup — parallel HTTP fetching) ───
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.pullCategoriesFromSupabase(modelContext) }
            group.addTask { await self.pullModifierGroupsFromSupabase(modelContext) }
            group.addTask { await self.pullModifiersFromSupabase(modelContext) }
            group.addTask { await self.pullMenuItemModifierGroupsFromSupabase(modelContext) }
            group.addTask { await self.pullBranchesFromSupabase(modelContext) }
            group.addTask { await self.pullSuppliersFromSupabase(modelContext) }
            group.addTask { await self.pullInventoryItemsFromSupabase(modelContext) }
            group.addTask { await self.pullInventoryLotsFromSupabase(modelContext) }  // Expiry/FEFO lots
            group.addTask { await self.pullMenuItemsFromSupabase(modelContext) }
            group.addTask { await self.pullPromotionsFromSupabase(modelContext) }
            group.addTask { await self.pullPromotionBundleItemsFromSupabase(modelContext) }
            group.addTask { await self.pullRestaurantTables(modelContext) }
            group.addTask { await self.pullRestaurantWallsFromSupabase(modelContext) }
            group.addTask { await self.pullTableLayoutPresetsFromSupabase(modelContext) }
            group.addTask { await self.pullEmployees(modelContext) }
            group.addTask { await self.pullEmployeeShifts(modelContext) }
            group.addTask { await self.pullCustomerOrders(modelContext) }
            group.addTask { await self.pullCompletedOrdersAndPayments(modelContext) }
            group.addTask { await self.pullActiveSessions(modelContext) }
            group.addTask { await self.pullRegisterSessions(modelContext) }
            group.addTask { await self.pullCashMovements(modelContext) }
            group.addTask { await self.pullShiftReportsFromSupabase(modelContext) }
            group.addTask { await self.syncServiceRequests() }
            group.addTask { await self.pullCustomersFromSupabase(modelContext) }
            group.addTask { await self.pullGiftCardsFromSupabase(modelContext) }
            group.addTask { await self.pullLoyaltyTransactionsFromSupabase(modelContext) }
            group.addTask { await self.pullTaxRatesFromSupabase(modelContext) }
            group.addTask { await self.pullCurrencyExchangeRatesFromSupabase(modelContext) }
            group.addTask { await self.pullRecipesFromSupabase(modelContext) }
            group.addTask { await self.pullExpensesFromSupabase(modelContext) }
            group.addTask { await self.pullRefundTransactionsFromSupabase(modelContext) }
            group.addTask { await self.pullOrderTaxLinesFromSupabase(modelContext) }
            group.addTask { await self.pullTipsFromSupabase(modelContext) }
            group.addTask { await self.pullOrderItemModifiersFromSupabase(modelContext) }
            group.addTask { await self.pullUsersFromSupabase(modelContext) }
            group.addTask { await self.pullRolesFromSupabase(modelContext) }
            group.addTask { await self.pullReceiptTemplatesFromSupabase(modelContext) }
        }

        await checkForDelayedOrders(modelContext: modelContext)

        let isStillConnected = await NetworkManager.shared.isConnected()
        let completedSuccessfully = isStillConnected && !encounteredSyncError

        await MainActor.run {
            self.syncStatus = completedSuccessfully ? .idle : (isStillConnected ? .error : .offline)
            if completedSuccessfully {
                self.lastSyncedAt = Date()
                self.isFirstSync = false
                // Enterprise Alert: connection restored after previous failure
                if self.consecutiveSyncFailures >= 3 {
                    self.alertConnectionRestored()
                }
                self.consecutiveSyncFailures = 0
            } else if isStillConnected {
                // Enterprise Alert: sync error
                self.consecutiveSyncFailures += 1
                self.alertSyncFailed(error: NSError(domain: "SyncEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "Data synchronization encountered errors"]), attempt: self.consecutiveSyncFailures)
            } else {
                // Enterprise Alert: offline
                if self.syncStatus != .offline {
                    self.alertWentOffline()
                }
            }
        }
        #if DEBUG
        print(completedSuccessfully ? "SyncEngine: Sync completed." : "SyncEngine: Sync completed with errors.")
        #endif
    }

    func hasPendingSyncData(in modelContext: ModelContext) -> Bool {
        do {
            if try modelContext.fetchCount(FetchDescriptor<SecurityPolicy>(predicate: #Predicate { !$0.isSynced })) > 0 { return true }
            if try modelContext.fetchCount(FetchDescriptor<Role>(predicate: #Predicate { !$0.isSynced })) > 0 { return true }
            if try modelContext.fetchCount(FetchDescriptor<MerchantDevice>(predicate: #Predicate { !$0.isSynced })) > 0 { return true }
            if try modelContext.fetchCount(FetchDescriptor<Employee>(predicate: #Predicate { !$0.isSynced })) > 0 { return true }
            if try modelContext.fetchCount(FetchDescriptor<StaffSessionRecord>(predicate: #Predicate { !$0.isSynced })) > 0 { return true }
            if try modelContext.fetchCount(FetchDescriptor<AuditLog>(predicate: #Predicate { !$0.isSynced })) > 0 { return true }
            if try modelContext.fetchCount(FetchDescriptor<RestaurantTable>(predicate: #Predicate { !$0.isSynced })) > 0 { return true }
            if try modelContext.fetchCount(FetchDescriptor<TableSession>(predicate: #Predicate { !$0.isSynced })) > 0 { return true }
            if try modelContext.fetchCount(FetchDescriptor<FloorPlanImage>(predicate: #Predicate { !$0.isSynced })) > 0 { return true }
            if try modelContext.fetchCount(FetchDescriptor<EmployeeShift>(predicate: #Predicate { !$0.isSynced })) > 0 { return true }
            if try modelContext.fetchCount(FetchDescriptor<Order>(predicate: #Predicate { !$0.isSynced })) > 0 { return true }
            if try modelContext.fetchCount(FetchDescriptor<Payment>(predicate: #Predicate { !$0.isSynced })) > 0 { return true }
            if try modelContext.fetchCount(FetchDescriptor<OrderDiscount>(predicate: #Predicate { !$0.isSynced })) > 0 { return true }
            if try modelContext.fetchCount(FetchDescriptor<Timecard>(predicate: #Predicate { !$0.isSynced })) > 0 { return true }
            if try modelContext.fetchCount(FetchDescriptor<InventoryTransaction>(predicate: #Predicate { !$0.isSynced })) > 0 { return true }
            if try modelContext.fetchCount(FetchDescriptor<MenuItem>(predicate: #Predicate { !$0.isSynced })) > 0 { return true }
            if try modelContext.fetchCount(FetchDescriptor<Promotion>(predicate: #Predicate { !$0.isSynced })) > 0 { return true }
            if try modelContext.fetchCount(FetchDescriptor<PurchaseOrder>(predicate: #Predicate { !$0.isSynced })) > 0 { return true }
            if try modelContext.fetchCount(FetchDescriptor<Printer>(predicate: #Predicate { !$0.isSynced })) > 0 { return true }
            if try modelContext.fetchCount(FetchDescriptor<PrintRoutingRule>(predicate: #Predicate { !$0.isSynced })) > 0 { return true }
            if try modelContext.fetchCount(FetchDescriptor<Customer>(predicate: #Predicate { !$0.isSynced })) > 0 { return true }
            if try modelContext.fetchCount(FetchDescriptor<GiftCard>(predicate: #Predicate { !$0.isSynced })) > 0 { return true }
            if try modelContext.fetchCount(FetchDescriptor<LoyaltyTransaction>(predicate: #Predicate { !$0.isSynced })) > 0 { return true }
            // Previously missing models — added for complete sync coverage
            if try modelContext.fetchCount(FetchDescriptor<Expense>(predicate: #Predicate { !$0.isSynced })) > 0 { return true }
            if try modelContext.fetchCount(FetchDescriptor<Supplier>(predicate: #Predicate { !$0.isSynced })) > 0 { return true }
            if try modelContext.fetchCount(FetchDescriptor<TaxRate>(predicate: #Predicate { !$0.isSynced })) > 0 { return true }
            if try modelContext.fetchCount(FetchDescriptor<Recipe>(predicate: #Predicate { !$0.isSynced })) > 0 { return true }
            if try modelContext.fetchCount(FetchDescriptor<ShiftReport>(predicate: #Predicate { !$0.isSynced })) > 0 { return true }
            if try modelContext.fetchCount(FetchDescriptor<RefundTransaction>(predicate: #Predicate { !$0.isSynced })) > 0 { return true }
            if try modelContext.fetchCount(FetchDescriptor<OrderTaxLine>(predicate: #Predicate { !$0.isSynced })) > 0 { return true }
            if try modelContext.fetchCount(FetchDescriptor<Tip>(predicate: #Predicate { !$0.isSynced })) > 0 { return true }
            if try modelContext.fetchCount(FetchDescriptor<RestaurantWall>(predicate: #Predicate { !$0.isSynced })) > 0 { return true }
            if try modelContext.fetchCount(FetchDescriptor<ReceiptTemplate>(predicate: #Predicate { !$0.isSynced })) > 0 { return true }
            if try modelContext.fetchCount(FetchDescriptor<TableLayoutPreset>(predicate: #Predicate { !$0.isSynced })) > 0 { return true }
            if try modelContext.fetchCount(FetchDescriptor<CurrencyExchangeRate>(predicate: #Predicate { !$0.isSynced })) > 0 { return true }
            if try modelContext.fetchCount(FetchDescriptor<User>(predicate: #Predicate { !$0.isSynced })) > 0 { return true }
            if try modelContext.fetchCount(FetchDescriptor<OrderItemModifier>(predicate: #Predicate { !$0.isSynced })) > 0 { return true }
            if try modelContext.fetchCount(FetchDescriptor<PromotionBundleItem>(predicate: #Predicate { !$0.isSynced })) > 0 { return true }
            return false
        } catch {
            encounteredSyncError = true
            return true
        }
    }
}
