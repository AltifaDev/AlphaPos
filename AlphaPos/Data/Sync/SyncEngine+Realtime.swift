import Foundation
import SwiftData
import Combine
import UIKit
import os

// MARK: - Supabase Realtime WebSocket Client (methods)
// NOTE: Stored properties (webSocketTask, config, anonKey, syncLock, etc.)
// are declared in SyncEngine.swift (the main class file).
extension SyncEngine {

    // ponytail: keep the existing Postgres Changes client while traffic is
    // store-scale; move to private Broadcast/Supabase Swift when measured event
    // throughput or protocol maintenance exceeds this small adapter.

    func startRealtimeSync(modelContext: ModelContext) {
        self.cachedModelContext = modelContext
        guard TenantWorkspaceGuard.isAuthenticatedWorkspaceReady else {
            cancelPendingSync()
            return
        }
        guard NetworkPolicy.shared.allows(.realtime) else {
            cancelPendingSync()
            return
        }
        guard webSocketTask == nil else { return }

        let baseRealtimeURL = config.supabaseURL.absoluteString
            .replacingOccurrences(of: "https://", with: "wss://")
            .replacingOccurrences(of: "http://", with: "ws://")
        let wsURLString = "\(baseRealtimeURL)/realtime/v1/websocket?apikey=\(anonKey)&vsn=1.0.0"
        guard let url = URL(string: wsURLString) else { return }

        let wsSessionConfig = URLSessionConfiguration.default
        wsSessionConfig.timeoutIntervalForRequest = 30
        wsSessionConfig.timeoutIntervalForResource = 60
        guard let task = try? AppNetworkTransport.webSocketTask(
            with: url,
            configuration: wsSessionConfig
        ) else {
            cancelPendingSync()
            return
        }
        self.webSocketTask = task
        task.resume()

        // Keep all ModelContext and connection state on MainActor.
        realtimeListenTask?.cancel()
        realtimeListenTask = Task { [weak self] in
            guard let self else { return }
            await self.listenToWebSocket(modelContext: modelContext)
        }

        // Join realtime topic
        joinRealtimeTopic()

        // Keep-alive heartbeat every 20 seconds (invalidate any existing timer first)
        startHeartbeat()

    }

    func scheduleRealtimeReconnect(modelContext: ModelContext, reason: String) {
        guard !UserDefaults.standard.bool(forKey: "offline_sync_mode"),
              realtimeReconnectTask == nil else { return }

        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        realtimeListenTask?.cancel()
        realtimeListenTask = nil
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        pendingHeartbeatRef = nil

        let delay = min(maxReconnectDelay, pow(2.0, Double(reconnectAttempt)))
        let finalDelay = max(1.0, delay + delay * Double.random(in: -0.25...0.25))
        reconnectAttempt += 1

        #if DEBUG
        print("SyncEngine [Realtime]: \(reason). Reconnecting in \(String(format: "%.1f", finalDelay))s")
        #endif

        realtimeReconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(finalDelay))
            guard let self, !Task.isCancelled else { return }
            self.realtimeReconnectTask = nil
            await MerchantAuthManager.shared.refreshTokenIfNeeded()
            self.startRealtimeSync(modelContext: modelContext)
            // Postgres Changes has no replay guarantee. A full pull closes the
            // gap before sync status/connection-restored UI is announced.
            await self.syncAll(modelContext: modelContext)
        }
    }

    func listenToWebSocket(modelContext: ModelContext) async {
        while !Task.isCancelled, let task = webSocketTask {
            do {
                let message = try await task.receive()
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
            } catch {
                guard !Task.isCancelled else { return }
                self.scheduleRealtimeReconnect(
                    modelContext: modelContext,
                    reason: "WebSocket receive failed: \(error.localizedDescription)"
                )
                return
            }
        }
    }

    func joinRealtimeTopic() {
        guard TenantWorkspaceGuard.isAuthenticatedWorkspaceReady,
              let rawMerchantId = UserDefaults.standard.string(forKey: "active_merchant_id") else {
            cancelPendingSync()
            return
        }
        let merchantId = rawMerchantId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !merchantId.isEmpty else {
            cancelPendingSync()
            return
        }

        guard let accessToken = MerchantAuthManager.shared.authorizationToken else {
            cancelPendingSync()
            return
        }
        #if DEBUG
        print("SyncEngine [Realtime] JOIN: merchantId=\(merchantId) tokenType=\(MerchantAuthManager.shared.authorizationToken != nil ? "AUTH" : "ANON")")
        #endif
        let joinPayload: [String: Any] = [
            "topic": "realtime:public",
            "event": "phx_join",
            "payload": [
                "config": [
                    "postgres_changes": [
                        // Keep the always-on channel limited to operational tables
                        // guaranteed by 20260713000200_realtime_order_session_integrity.
                        // Master data is reconciled by the foreground/full pull.
                        ["event": "*", "schema": "public", "table": "orders", "filter": "merchant_id=eq.\(merchantId)"],
                        ["event": "*", "schema": "public", "table": "order_items", "filter": "merchant_id=eq.\(merchantId)"],
                        ["event": "*", "schema": "public", "table": "order_item_modifiers", "filter": "merchant_id=eq.\(merchantId)"],
                        ["event": "*", "schema": "public", "table": "table_sessions", "filter": "merchant_id=eq.\(merchantId)"],
                        ["event": "*", "schema": "public", "table": "service_requests", "filter": "merchant_id=eq.\(merchantId)"],
                        ["event": "*", "schema": "public", "table": "restaurant_tables", "filter": "merchant_id=eq.\(merchantId)"],
                        ["event": "*", "schema": "public", "table": "payments", "filter": "merchant_id=eq.\(merchantId)"],
                        ["event": "*", "schema": "public", "table": "inventory_transactions", "filter": "merchant_id=eq.\(merchantId)"],
                        ["event": "*", "schema": "public", "table": "inventory_lots", "filter": "merchant_id=eq.\(merchantId)"],
                        ["event": "*", "schema": "public", "table": "purchase_orders", "filter": "merchant_id=eq.\(merchantId)"],
                        ["event": "*", "schema": "public", "table": "purchase_order_items", "filter": "merchant_id=eq.\(merchantId)"],
                        ["event": "*", "schema": "public", "table": "sync_outbox", "filter": "merchant_id=eq.\(merchantId)"]
                    ]
                ],
                "access_token": accessToken
            ],
            "ref": "1"
        ]

        if let data = try? JSONSerialization.data(withJSONObject: joinPayload, options: []),
           let jsonString = String(data: data, encoding: .utf8) {
            Task { [weak self] in
                do {
                    try await self?.webSocketTask?.send(.string(jsonString))
                    print("SyncEngine: Successfully sent join payload for postgres changes (merchant-scoped).")
                } catch {
                    print("SyncEngine: Failed to send join payload: \(error)")
                }
            }
        }
    }

    func startHeartbeat() {
        // Invalidate any existing heartbeat timer to prevent leak
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil

        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 20.0, repeats: true) { [weak self] timer in
            Task { @MainActor [weak self] in
            guard let self,
                  let task = self.webSocketTask,
                  let modelContext = self.cachedModelContext else {
                timer.invalidate()
                return
            }
            if self.pendingHeartbeatRef != nil {
                self.scheduleRealtimeReconnect(
                    modelContext: modelContext,
                    reason: "Heartbeat acknowledgement timed out"
                )
                return
            }
            self.heartbeatSequence += 1
            let heartbeatRef = "heartbeat-\(self.heartbeatSequence)"
            self.pendingHeartbeatRef = heartbeatRef
            let heartbeat: [String: Any] = [
                "topic": "phoenix",
                "event": "heartbeat",
                "payload": [:],
                "ref": heartbeatRef
            ]
            if let data = try? JSONSerialization.data(withJSONObject: heartbeat, options: []),
               let jsonString = String(data: data, encoding: .utf8) {
                do {
                    try await task.send(.string(jsonString))
                } catch {
                    self.scheduleRealtimeReconnect(
                        modelContext: modelContext,
                        reason: "Heartbeat send failed: \(error.localizedDescription)"
                    )
                }
            }
            }
        }
    }

    func handleWebSocketMessage(_ text: String, modelContext: ModelContext) {
        #if DEBUG
        print("SyncEngine [Realtime] RAW MSG: \(text.prefix(500))")
        #endif
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let event = json["event"] as? String else { return }

        if event == "phx_reply",
           let payload = json["payload"] as? [String: Any],
           let status = payload["status"] as? String {
            let ref = json["ref"] as? String
            if ref == pendingHeartbeatRef {
                pendingHeartbeatRef = nil
            }
            if status == "error" {
                scheduleRealtimeReconnect(
                    modelContext: modelContext,
                    reason: "Channel request rejected: \(String(describing: payload["response"]))"
                )
            } else if ref == "1" {
                reconnectAttempt = 0
                // Postgres Changes does not replay events sent while this
                // socket was disconnected.  The reconnect task also performs
                // a full sync, but that can race the channel join and finish
                // before the server has accepted this subscription.  Pull
                // orders after the join acknowledgement so Quick Orders made
                // on an iPhone are recovered even when the iPad missed the
                // INSERT/UPDATE realtime event.
                Task { [weak self] in
                    guard let self else { return }
                    await self.pullCustomerOrders(modelContext)
                    await self.pullActiveSessions(modelContext)
                }
            }
            return
        }

        if event == "phx_error" || event == "phx_close" {
            scheduleRealtimeReconnect(modelContext: modelContext, reason: "Channel received \(event)")
            return
        }

        if event == "system" {
            let payload = json["payload"] as? [String: Any]
            if (payload?["status"] as? String)?.lowercased() == "error" {
                let message = payload?["message"] as? String ?? "Unknown Realtime system error"
                if message.contains("Unable to subscribe to changes with given parameters") {
                    // This is deterministic configuration drift. Reconnecting with
                    // the same payload only creates a hot loop and repeated full pulls.
                    encounteredSyncError = true
                    #if DEBUG
                    print("SyncEngine [Realtime]: Non-retryable subscription error: \(message)")
                    #endif
                } else {
                    scheduleRealtimeReconnect(modelContext: modelContext, reason: "Realtime system error: \(message)")
                }
            }
            return
        }

        // Supabase Realtime V1 normally uses `postgres_changes`; tolerate an
        // equivalent payload event for compatibility with self-hosted versions.
        let isPostgresChange: Bool
        if event == "postgres_changes" {
            isPostgresChange = true
        } else {
            // Catch any other events that contain postgres change data in payload
            if let payload = json["payload"] as? [String: Any],
               let _ = payload["data"] as? [String: Any] {
                isPostgresChange = true
            } else {
                isPostgresChange = false
            }
        }

guard isPostgresChange else {
            #if DEBUG
            print("SyncEngine [Realtime]: Ignored non-postgres event: \(event)")
            #endif
            return
        }

        // ── Extract changed table name for smart routing ──────────────────
        // Supabase Realtime V1 embeds the changed table in:
        //   payload.data.table  (postgres_changes events)
        // We use this to pull ONLY the endpoints that actually need refreshing,
        // which avoids unnecessary pullRestaurantTables calls when only a session changed.
        let changedTable: String? = {
            if let payload = json["payload"] as? [String: Any],
               let data    = payload["data"]    as? [String: Any],
               let tbl     = data["table"]      as? String {
                return tbl
            }
            return nil
        }()

        // H-9 FIX: Double-check merchant_id in the changed record to prevent
        // processing events that accidentally broadcast across tenants.
        // Supabase RLS + join filter should handle this, but we verify defensively.
        let activeMerchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        guard TenantWorkspaceGuard.isAuthenticatedWorkspaceReady,
              !activeMerchantId.isEmpty else {
            return
        }

        #if DEBUG
        print("SyncEngine [Realtime]: Postgres event=\(event) table=\(changedTable ?? "nil") merchantCheck=\(activeMerchantId)")
        #endif

        // Capture the changed row itself so downstream handlers (e.g. remote
        // receipt printing on `payments`) can inspect it inside the debounced
        // work item without re-parsing the payload.
        let changedRecord: [String: Any]? = {
            if let payload = json["payload"] as? [String: Any],
               let data    = payload["data"]    as? [String: Any],
               let rec     = data["record"]     as? [String: Any] {
                return rec
            }
            return nil
        }()

        if let payload    = json["payload"]  as? [String: Any],
           let data       = payload["data"]  as? [String: Any],
           let record     = data["record"]   as? [String: Any],
           let recMerchId = record["merchant_id"] as? String,
           !recMerchId.isEmpty,
           recMerchId.lowercased() != activeMerchantId.lowercased() {
            #if DEBUG
            print("SyncEngine [Realtime]: Dropped event — merchant_id mismatch (got \(recMerchId), expected \(activeMerchantId))")
            #endif
            return
        }

        let tableKey = changedTable ?? "*"
        pendingRealtimeTables.insert(tableKey)
        if let changedRecord {
            pendingRealtimeRecords[tableKey, default: []].append(changedRecord)
        }
        assert(pendingRealtimeRecords.keys.allSatisfy(pendingRealtimeTables.contains))

        // The running drain consumes anything added while it is awaiting HTTP.
        guard !isCurrentlySyncing, realtimeDebounceWorkItem == nil else { return }

        let debounceDelay: Double = {
            switch changedTable {
            case "table_sessions", "orders", "order_items", "merchants": return 0.4
            case "restaurant_tables":                        return 0.6
            default:                                         return 1.0
            }
        }()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.realtimeDebounceWorkItem = nil
            Task { await self.drainRealtimeChanges(modelContext: modelContext) }
        }
        realtimeDebounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceDelay, execute: workItem)
    }

    func drainRealtimeChanges(modelContext: ModelContext) async {
        guard !isCurrentlySyncing else { return }
        isCurrentlySyncing = true
        defer { isCurrentlySyncing = false }

        while !pendingRealtimeTables.isEmpty {
            let tables = pendingRealtimeTables
            let records = pendingRealtimeRecords
            assert(records.keys.allSatisfy(tables.contains))
            pendingRealtimeTables.removeAll()
            pendingRealtimeRecords.removeAll()

            // Stable order keeps table metadata ahead of session-derived status.
            for table in tables.sorted(by: realtimeTablePrecedes) {
                await pullRealtimeChange(table, records: records[table] ?? [], modelContext: modelContext)
            }
        }
    }

    private func realtimeTablePrecedes(_ lhs: String, _ rhs: String) -> Bool {
        let priority = ["restaurant_tables", "table_sessions", "orders", "order_items"]
        return (priority.firstIndex(of: lhs) ?? priority.count) < (priority.firstIndex(of: rhs) ?? priority.count)
    }

    private func pullRealtimeChange(
        _ table: String,
        records: [[String: Any]],
        modelContext: ModelContext
    ) async {
        switch table {
        case "table_sessions":
            await pullActiveSessions(modelContext)
        case "orders", "order_items":
            await pullCustomerOrders(modelContext)
            await pullActiveSessions(modelContext)
            await handleRemoteKitchenPrint(modelContext: modelContext)
        case "service_requests": await syncServiceRequests()
        case "restaurant_tables":
            await pullRestaurantTables(modelContext)
            await pullActiveSessions(modelContext)
        case "merchants": await pullMerchantSettings()
        case "menu_items": await pullMenuItemsFromSupabase(modelContext)
        case "categories": await pullCategoriesFromSupabase(modelContext)
        case "modifiers": await pullModifiersFromSupabase(modelContext)
        case "modifier_groups": await pullModifierGroupsFromSupabase(modelContext)
        case "employees": await pullEmployees(modelContext)
        case "employee_shifts": await pullEmployeeShifts(modelContext)
        case "inventory_items": await pullInventoryItemsFromSupabase(modelContext)
        case "inventory_transactions":
            if await pullInventoryTransactionsFromSupabase(modelContext) {
                reconcileInventoryFromLedger(modelContext)
            }
        case "inventory_lots": _ = await pullInventoryLotsFromSupabase(modelContext)
        case "purchase_orders", "purchase_order_items": await pullPurchaseOrdersFromSupabase(modelContext)
        case "customers": await pullCustomersFromSupabase(modelContext)
        case "payments":
            await pullCompletedOrdersAndPayments(modelContext)
            for record in records {
                await handleRemotePaymentPrint(record: record, modelContext: modelContext)
            }
        case "sync_outbox":
            // Staff (or triggers) enqueued a print/push job — drain immediately.
            await drainSyncOutbox(modelContext)
        case "promotions":
            await pullPromotionsFromSupabase(modelContext)
            await pullPromotionBundleItemsFromSupabase(modelContext)
        case "expenses": await pullExpensesFromSupabase(modelContext)
        case "suppliers": await pullSuppliersFromSupabase(modelContext)
        case "tax_rates": await pullTaxRatesFromSupabase(modelContext)
        case "recipes": await pullRecipesFromSupabase(modelContext)
        case "receipt_templates": await pullReceiptTemplatesFromSupabase(modelContext)
        case "table_layout_presets": await pullTableLayoutPresetsFromSupabase(modelContext)
        case "floor_plan_images": await pullFloorPlanImagesFromSupabase(modelContext)
        case "dining_areas": await pullDiningAreas(modelContext)
        case "currency_exchange_rates": await pullCurrencyExchangeRatesFromSupabase(modelContext)
        case "users": await pullUsersFromSupabase(modelContext)
        case "refund_transactions": await pullRefundTransactionsFromSupabase(modelContext)
        case "tips": await pullTipsFromSupabase(modelContext)
        case "order_tax_lines": await pullOrderTaxLinesFromSupabase(modelContext)
        case "order_item_modifiers": await pullOrderItemModifiersFromSupabase(modelContext)
        default:
            await syncAll(modelContext: modelContext)
        }
    }


}
