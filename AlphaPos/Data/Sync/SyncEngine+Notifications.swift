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
            self.realtimeReconnectTask?.cancel()
            self.realtimeReconnectTask = nil
            self.heartbeatTimer?.invalidate()
            self.heartbeatTimer = nil
            self.pendingHeartbeatRef = nil
            if let context = self.cachedModelContext {
                await self.bootstrapSync(modelContext: context)
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
            self.realtimeReconnectTask?.cancel()
            self.realtimeReconnectTask = nil
            self.heartbeatTimer?.invalidate()
            self.heartbeatTimer = nil
            self.pendingHeartbeatRef = nil
            if let context = self.cachedModelContext {
                await self.bootstrapSync(modelContext: context)
            }
            }
        }
    }

    // MARK: - In-App Notification Triggers (แทนที่ UNUserNotificationCenter)

    /// แจ้งเตือนออเดอร์ใหม่จากลูกค้า — ทำงานเฉพาะเมื่อแอปเปิดอยู่
    func triggerLocalNotification(orderNumber: String, tableNumber: String, queueNumber: String? = nil, orderType: String? = nil) {
        Task { @MainActor in
            InAppNotificationManager.shared.postNewOrder(
                orderNumber: orderNumber,
                tableNumber: tableNumber,
                queueNumber: queueNumber,
                orderType: orderType
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

    /// แจ้งเตือนกะงานค้างเปิดนาน — one active condition per shift.
    func triggerStaleShiftNotification(shiftId: UUID, hoursOpen: Int) {
        let merchant = UserDefaults.standard.string(forKey: "active_merchant_id") ?? "none"
        let branch = BranchContext.shared.activeBranchIDString
        let lastNotifiedKey = "last_stale_shift_notification_time.\(merchant).\(branch).\(shiftId.uuidString.lowercased())"
        if let lastNotified = UserDefaults.standard.object(forKey: lastNotifiedKey) as? Date {
            if Date().timeIntervalSince(lastNotified) < 3600 * 6 { return }
        }
        UserDefaults.standard.set(Date(), forKey: lastNotifiedKey)
        Task { @MainActor in
            InAppNotificationManager.shared.postStaleShift(hoursOpen: hoursOpen)
            NotificationStore.shared.upsertConditionAlert(
                key: "stale-shift-\(shiftId.uuidString.lowercased())",
                priority: hoursOpen >= 48 ? .high : .medium,
                category: .system,
                title: String(format: "stale_shift_center_title".t, hoursOpen),
                message: "stale_shift_center_body".t,
                device: "System"
            )
        }
    }

    // MARK: - Sync Orchestration

    /// Single entry point for cold launch, login, and foreground recovery.
    func bootstrapSync(modelContext: ModelContext) async {
        cachedModelContext = modelContext

        guard TenantWorkspaceGuard.isAuthenticatedWorkspaceReady else {
            cancelPendingSync()
            syncStatus = .error
            lastSyncErrorSummary = "Tenant verification required"
            NotificationStore.shared.completeInitialReconciliation()
            return
        }

        if UserDefaults.standard.bool(forKey: "offline_sync_mode") {
            syncStatus = .offline
            await runLocalOperationalChecks(modelContext: modelContext)
            NotificationStore.shared.completeInitialReconciliation()
            return
        }
        guard MerchantAuthManager.shared.currentToken != nil else {
            NotificationStore.shared.completeInitialReconciliation()
            return
        }
        syncStatus = .syncing
        await MerchantAuthManager.shared.refreshTokenIfNeeded()
        guard MerchantAuthManager.shared.isAuthenticated else {
            syncStatus = .error
            lastSyncErrorSummary = "sync_auth_required".t
            NotificationStore.shared.completeInitialReconciliation()
            return
        }
        await syncAll(modelContext: modelContext)
        NotificationStore.shared.completeInitialReconciliation()
    }

    func syncAll(modelContext: ModelContext) async {
        cachedModelContext = modelContext

        guard TenantWorkspaceGuard.isAuthenticatedWorkspaceReady else {
            cancelPendingSync()
            syncStatus = .error
            lastSyncErrorSummary = "Tenant verification required"
            return
        }

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
        guard TenantWorkspaceGuard.isAuthenticatedWorkspaceReady else {
            await MainActor.run {
                self.syncStatus = .error
                self.lastSyncErrorSummary = "Tenant verification required"
            }
            return
        }
        failuresAreSoft = false
        encounteredSyncError = false
        NetworkManager.shared.clearRecentNetworkFailures()
        await MainActor.run {
            self.lastSyncErrorSummary = nil
            self.lastSyncFailureDetails = []
            self.hadSoftSyncFailures = false
        }

        // ─── Offline / Online Mode Gate ────────────────────────────────────
        let isOfflineModeOn = UserDefaults.standard.bool(forKey: "offline_sync_mode")
        NetworkManager.shared.simulateOffline = isOfflineModeOn
        if isOfflineModeOn {
            await runLocalOperationalChecks(modelContext: modelContext)
            await MainActor.run { self.syncStatus = .offline }
            return
        }
        // ─── End Offline Gate ──────────────────────────────────────────────

        await MainActor.run {
            self.syncStatus = .syncing
            self.startRealtimeSync(modelContext: modelContext)
        }

        guard await NetworkManager.shared.isConnected() else {
            #if DEBUG
            print("SyncEngine: Device is offline. Sync task aborted.")
            #endif
            await runLocalOperationalChecks(modelContext: modelContext)
            await MainActor.run { self.syncStatus = .offline }
            return
        }

        await NetworkTimeService.shared.syncWithServer()
        #if DEBUG
        print("SyncEngine: Initiating data synchronization...")
        #endif

        // Hold the same lock realtime drain uses so pulls cannot interleave
        // with table/session pushes and resurrect cleared/opened state.
        isCurrentlySyncing = true
        defer {
            isCurrentlySyncing = false
            // Events queued during sync never scheduled a drain — flush them.
            if !pendingRealtimeTables.isEmpty {
                let ctx = modelContext
                Task { await self.drainRealtimeChanges(modelContext: ctx) }
            }
        }

        // Soft: shared outbox drain must not paint the whole cycle red.
        failuresAreSoft = true
        await drainSyncOutbox(modelContext)
        failuresAreSoft = false

        // ─── Stage 1: Pushes (Sequential to respect foreign key & relationship constraints) ───
        await syncMerchant()
        // Resolve the server-owned branch identity before any branch-scoped
        // push. Older builds could manufacture an empty "Main Branch" with a
        // new UUID during bootstrap; pushing it first caused HTTP 400 and then
        // left kitchen/order children pointing at a parent that did not exist.
        failuresAreSoft = true
        await pullBranchesFromSupabase(modelContext)
        failuresAreSoft = false
        // Branches and floor-plan records are parents of sessions, orders and
        // other branch-scoped data. A newly created table must reach the server
        // before a session or order can reference it.
        await syncBranches(modelContext)
        await syncDiningAreas(modelContext)
        await syncTables(modelContext)
        await syncFloorPlanImages(modelContext)
        await syncRestaurantWalls(modelContext)
        await syncTableLayoutPresets(modelContext)
        await pushDeliveryFeeSettingsIfNeeded()
        await syncSecurityPolicies(modelContext)
        await syncRoles(modelContext)
        await syncRolePermissions(modelContext)
        await syncMerchantDevices(modelContext)
        await syncUsers(modelContext)
        await syncEmployees(modelContext)
        await syncStaffSessions(modelContext)
        await syncAuditLogs(modelContext)
        // POS owns its stock movement. Push it before the order status so the
        // server trigger sees the same reference and does not deduct twice.
        await syncInventoryTransactionsWithRetry(modelContext)
        // Publish newly-opened sessions before their orders. Web orders are
        // guarded by the server and require the exact active session to exist.
        await syncTableSessions(modelContext, phase: .opening)
        await syncOrders(modelContext)
        await syncCheckoutLifecycle(modelContext)
        // Publish closes/deletes only after orders. The DB rejects closing a
        // session while kitchen tickets are still pending/preparing/ready.
        await syncTableSessions(modelContext, phase: .closing)
        await syncEmployeeShifts(modelContext)
        // Build local accounting facts before any ledger push. Cloud sync only
        // replicates the local ledger; it must never be responsible for creating it.
        await backfillBusinessContext(modelContext)
        await backfillAccountingLedger(modelContext)
        await syncPayments(modelContext)
        await syncFinancialEvents(modelContext)
        await syncAccountingSnapshots(modelContext)
        await syncCheckoutLifecycle(modelContext)
        await syncOrderDiscounts(modelContext)
        await syncOrderTaxLines(modelContext)
        await syncTips(modelContext)
        await syncOrderItemModifiers(modelContext)
        await syncTimecards(modelContext)
        await syncRegisterSessions(modelContext)
        await syncCashMovements(modelContext)
        await syncShiftReports(modelContext)

        // Resolve legacy seed/import rows that have the same normalized name as
        // a server category before pushing, otherwise the server's name-unique
        // index correctly rejects a different local UUID forever.
        failuresAreSoft = true
        await pullCategoriesFromSupabase(modelContext)
        failuresAreSoft = false
        await syncCategories(modelContext)
        await syncModifierGroups(modelContext)
        await syncModifiers(modelContext)
        await syncMenuItemModifierGroups(modelContext)

        await syncSuppliers(modelContext)
        await syncInventoryItemsWithRetry(modelContext)
        // One-time repair of legacy InventoryTransaction.createdAt BEFORE pushing,
        // so the corrected event-time is uploaded to Supabase in this same pass.
        await backfillInventoryTransactionCreatedAt(modelContext)
        await syncInventoryTransactionsWithRetry(modelContext)
        await syncInventoryLotsWithRetry(modelContext)          // Expiry/FEFO lots (retry-enabled)
        await syncRecipes(modelContext)
        await syncPrepRecipes(modelContext)
        await syncMenuItems(modelContext)
        await syncPromotions(modelContext)
        await syncPromotionBundleItems(modelContext)
        await syncPurchaseOrders(modelContext)
        await syncDeliveryPrices(modelContext)
        await syncPrinters(modelContext)
        await syncPrinterPreferences()
        await syncPrintRoutingRules(modelContext)
        await syncReceiptTemplates(modelContext)
        await syncCustomers(modelContext)
        await syncGiftCards(modelContext)
        await syncLoyaltyTransactions(modelContext)
        await syncTaxRates(modelContext)
        await syncCurrencyExchangeRates(modelContext)
        await syncExpenses(modelContext)
        await syncRefundTransactions(modelContext)
        await syncInventoryCompliance(modelContext)

        // ─── Stage 2: Pulls — soft failures (retry next cycle) ───
        // SwiftData ModelContext is not Sendable. Running these in a task group
        // against one context causes intermittent store contract violations.
        failuresAreSoft = true
        await pullModifierGroupsFromSupabase(modelContext)
        await pullModifiersFromSupabase(modelContext)
        await pullMenuItemModifierGroupsFromSupabase(modelContext)
        await pullBranchesFromSupabase(modelContext)
        await pullSuppliersFromSupabase(modelContext)
        let inventoryItemsComplete = await pullInventoryItemsFromSupabase(modelContext)
        let inventoryTransactionsComplete = await pullInventoryTransactionsFromSupabase(modelContext)
        let inventoryLotsComplete = await pullInventoryLotsFromSupabase(modelContext)
        await pullMenuItemsFromSupabase(modelContext)
        await pullPromotionsFromSupabase(modelContext)
        await pullPromotionBundleItemsFromSupabase(modelContext)
        await pullPurchaseOrdersFromSupabase(modelContext)
        await pullRestaurantWallsFromSupabase(modelContext)
        await pullDiningAreas(modelContext)
        await pullFloorPlanImagesFromSupabase(modelContext)
        await pullTableLayoutPresetsFromSupabase(modelContext)
        // Authentication identities must exist before Employee profiles are
        // attached. Pulling Employees first created a temporary random User;
        // the later canonical User pull then deleted it as a duplicate and the
        // cascade relationship deleted the Employee profile as well.
        await pullRolesFromSupabase(modelContext)
        await pullUsersFromSupabase(modelContext)
        await pullEmployees(modelContext)
        await pullEmployeeShifts(modelContext)
        await pullCustomerOrders(modelContext)
        await pullCompletedOrdersAndPayments(modelContext)
        await pullFinancialEvents(modelContext)
        await pullRegisterSessions(modelContext)
        await pullCashMovements(modelContext)
        await pullShiftReportsFromSupabase(modelContext)
        await syncServiceRequests()
        await pullCustomersFromSupabase(modelContext)
        await pullGiftCardsFromSupabase(modelContext)
        await pullLoyaltyTransactionsFromSupabase(modelContext)
        await pullTaxRatesFromSupabase(modelContext)
        await pullCurrencyExchangeRatesFromSupabase(modelContext)
        await pullRecipesFromSupabase(modelContext)
        await pullPrepRecipes(modelContext)
        await pullExpensesFromSupabase(modelContext)
        await pullRefundTransactionsFromSupabase(modelContext)
        await pullOrderTaxLinesFromSupabase(modelContext)
        await pullTipsFromSupabase(modelContext)
        await pullOrderItemModifiersFromSupabase(modelContext)
        await pullReceiptTemplatesFromSupabase(modelContext)
        await pullMerchantSettings()
        await pullPrinterSettingsFromSupabase(modelContext)
        // Never rebuild on-hand from a partial cloud snapshot. Pending local
        // movements remain a separate optimistic delta until their next retry.
        if inventoryItemsComplete && inventoryTransactionsComplete && inventoryLotsComplete {
            reconcileInventoryFromLedger(modelContext)
        } else {
            reportSyncFailure("Inventory reconciliation skipped: incomplete cloud snapshot", soft: true)
        }

        // Table status is derived from active sessions. Pull the table records
        // first, then reconcile sessions so both cannot race on the same models.
        await pullRestaurantTables(modelContext)
        await pullActiveSessions(modelContext)

        // Recover any kitchen/floor divergence (orphaned or stale tickets).
        await reconcileKitchenFloorState(modelContext: modelContext)

        await runLocalOperationalChecks(modelContext: modelContext)

        // Live Sync Health feeds — never critical.
        await pullAuditLogs(modelContext, limit: 40)
        await refreshOnlineSyncHealth()
        failuresAreSoft = false

        let isStillConnected = await NetworkManager.shared.isConnected()
        let criticalFailed = encounteredSyncError
        let softFailed = softSyncFailuresObserved
        let detailLines = buildFailureDetailLines(preferSoftMessage: softFailed && !criticalFailed)
        let detailSummary = detailLines.prefix(3).joined(separator: " · ")

        await MainActor.run {
            self.hadSoftSyncFailures = softFailed && !criticalFailed
            self.lastSyncFailureDetails = detailLines
            if !isStillConnected {
                let wasOffline = self.syncStatus == .offline
                self.syncStatus = .offline
                self.lastSyncErrorSummary = nil
                self.lastSyncFailureDetails = []
                if !wasOffline {
                    self.alertWentOffline()
                }
            } else if criticalFailed {
                self.syncStatus = .error
                self.lastSyncErrorSummary = detailSummary.isEmpty ? L.Sync.statusError.t : detailSummary
                self.consecutiveSyncFailures += 1
                self.alertSyncFailed(
                    error: NSError(
                        domain: "SyncEngine",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: self.lastSyncErrorSummary ?? "Data synchronization encountered errors"]
                    ),
                    attempt: self.consecutiveSyncFailures
                )
            } else {
                self.syncStatus = .idle
                self.persistLastSyncedAt(Date())
                self.isFirstSync = false
                NotificationStore.shared.resolveConditionAlert(key: "system-sync-failed")
                NotificationStore.shared.resolveConditionAlert(key: "system-offline")
                if softFailed {
                    self.lastSyncErrorSummary = detailSummary.isEmpty ? "sync_partial_warning".t : detailSummary
                } else {
                    self.lastSyncErrorSummary = nil
                    self.lastSyncFailureDetails = []
                }
                if self.consecutiveSyncFailures >= 3 {
                    self.alertConnectionRestored()
                }
                self.consecutiveSyncFailures = 0
            }
        }
        #if DEBUG
        if criticalFailed {
            print("SyncEngine: Sync completed with CRITICAL errors.")
        } else if softFailed {
            print("SyncEngine: Sync completed with soft warnings (status stays idle).")
        } else {
            print("SyncEngine: Sync completed.")
        }
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
            if try modelContext.fetchCount(FetchDescriptor<InventoryLotControl>(predicate: #Predicate { !$0.isSynced })) > 0 { return true }
            if try modelContext.fetchCount(FetchDescriptor<InventoryRecall>(predicate: #Predicate { !$0.isSynced })) > 0 { return true }
            if try modelContext.fetchCount(FetchDescriptor<InventoryRecallLot>(predicate: #Predicate { !$0.isSynced })) > 0 { return true }
            if try modelContext.fetchCount(FetchDescriptor<IncomingInspection>(predicate: #Predicate { !$0.isSynced })) > 0 { return true }
            if try modelContext.fetchCount(FetchDescriptor<TemperatureLog>(predicate: #Predicate { !$0.isSynced })) > 0 { return true }
            if try modelContext.fetchCount(FetchDescriptor<InventoryCountSession>(predicate: #Predicate { !$0.isSynced })) > 0 { return true }
            if try modelContext.fetchCount(FetchDescriptor<ItemUnitConversion>(predicate: #Predicate { !$0.isSynced })) > 0 { return true }
            return false
        } catch {
            encounteredSyncError = true
            return true
        }
    }

    func notifyReadyOrders(_ modelContext: ModelContext) {
        let descriptor = FetchDescriptor<Order>(
            predicate: #Predicate<Order> { $0.status == "ready" && !$0.isDeleted }
        )
        if let readyOrders = try? modelContext.fetch(descriptor) {
            let operationalReady = readyOrders.filter(\.isOperationalReadyOrder)
            let currentReadyIds = Set(operationalReady.map(\.id))
            notifiedReadyOrderIds.formIntersection(currentReadyIds)
            for order in operationalReady {
                if !notifiedReadyOrderIds.contains(order.id) {
                    notifiedReadyOrderIds.insert(order.id)
                    // First sync establishes baseline state. Only transitions
                    // observed after baseline are delivered as new events.
                    if !isFirstSync {
                        alertOrderReady(
                            orderNumber: order.orderNumber,
                            tableNumber: order.tableSession?.table?.tableNumber
                        )
                    }
                }
            }
        }
    }
}
