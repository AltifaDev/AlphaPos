import Foundation
import SwiftData
import Combine
import UIKit
import os

// MARK: - Supabase Realtime WebSocket Client (methods)
// NOTE: Stored properties (webSocketTask, config, anonKey, syncLock, etc.)
// are declared in SyncEngine.swift (the main class file).
extension SyncEngine {

    func startRealtimeSync(modelContext: ModelContext) {
        self.cachedModelContext = modelContext
        guard webSocketTask == nil else { return }

        let baseRealtimeURL = config.supabaseURL.absoluteString
            .replacingOccurrences(of: "https://", with: "wss://")
            .replacingOccurrences(of: "http://", with: "ws://")
        let wsURLString = "\(baseRealtimeURL)/realtime/v1/websocket?apikey=\(anonKey)&vsn=1.0.0"
        guard let url = URL(string: wsURLString) else { return }

        let wsSessionConfig = URLSessionConfiguration.default
        wsSessionConfig.timeoutIntervalForRequest = 30
        wsSessionConfig.timeoutIntervalForResource = 60
        let session = URLSession(configuration: wsSessionConfig)
        let task = session.webSocketTask(with: url)
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

                try? await Task.sleep(for: .seconds(finalDelay))
                if !Task.isCancelled {
                    self.startRealtimeSync(modelContext: modelContext)
                }
                return
            }
        }
    }

    func joinRealtimeTopic() {
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
                        ["event": "*", "schema": "public", "table": "merchants", "filter": "id=eq.\(merchantId)"],
                        ["event": "*", "schema": "public", "table": "menu_items", "filter": "merchant_id=eq.\(merchantId)"],
                        ["event": "*", "schema": "public", "table": "categories", "filter": "merchant_id=eq.\(merchantId)"],
                        ["event": "*", "schema": "public", "table": "modifiers", "filter": "merchant_id=eq.\(merchantId)"],
                        ["event": "*", "schema": "public", "table": "modifier_groups", "filter": "merchant_id=eq.\(merchantId)"],
                        ["event": "*", "schema": "public", "table": "employees", "filter": "merchant_id=eq.\(merchantId)"],
                        ["event": "*", "schema": "public", "table": "employee_shifts", "filter": "merchant_id=eq.\(merchantId)"],
                        ["event": "*", "schema": "public", "table": "inventory_items", "filter": "merchant_id=eq.\(merchantId)"],
                        ["event": "*", "schema": "public", "table": "customers", "filter": "merchant_id=eq.\(merchantId)"],
                        ["event": "*", "schema": "public", "table": "payments", "filter": "merchant_id=eq.\(merchantId)"],
                        ["event": "*", "schema": "public", "table": "promotions", "filter": "merchant_id=eq.\(merchantId)"],
                        ["event": "*", "schema": "public", "table": "expenses", "filter": "merchant_id=eq.\(merchantId)"],
                        ["event": "*", "schema": "public", "table": "suppliers", "filter": "merchant_id=eq.\(merchantId)"],
                        ["event": "*", "schema": "public", "table": "tax_rates", "filter": "merchant_id=eq.\(merchantId)"],
                        ["event": "*", "schema": "public", "table": "recipes", "filter": "merchant_id=eq.\(merchantId)"],
                        ["event": "*", "schema": "public", "table": "receipt_templates", "filter": "merchant_id=eq.\(merchantId)"],
                        ["event": "*", "schema": "public", "table": "table_layout_presets", "filter": "merchant_id=eq.\(merchantId)"],
                        ["event": "*", "schema": "public", "table": "currency_exchange_rates", "filter": "merchant_id=eq.\(merchantId)"],
                        ["event": "*", "schema": "public", "table": "users", "filter": "merchant_id=eq.\(merchantId)"],
                        ["event": "*", "schema": "public", "table": "refund_transactions", "filter": "merchant_id=eq.\(merchantId)"],
                        ["event": "*", "schema": "public", "table": "tips", "filter": "merchant_id=eq.\(merchantId)"]
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
            guard let self, let task = self.webSocketTask else {
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
                do {
                    try await task.send(.string(jsonString))
                } catch {
                    print("SyncEngine heartbeat failed: \(error)")
                }
            }
            }
        }
    }

    func handleWebSocketMessage(_ text: String, modelContext: ModelContext) {
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
            if event == "phx_reply" {
                if let payload = json["payload"] as? [String: Any],
                   let status = payload["status"] as? String {
                   if status == "ok" {
                        reconnectAttempt = 0
                        // Enterprise Alert: WebSocket reconnected successfully after failures
                        if self.consecutiveSyncFailures > 0 {
                            self.alertConnectionRestored()
                            self.consecutiveSyncFailures = 0
                        }
                    }
                    #if DEBUG
                    print("SyncEngine [Realtime]: phx_reply status = \(status)")
                    #endif
                }
            }
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
        let activeMerchantId = UserDefaults.standard.string(forKey: "active_merchant_id")
            ?? config.defaultMerchantId
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

        // ── Debounce: per-event-type delay ───────────────────────────────
        // C-6 FIX: Use shorter delay for status-critical events so table cards
        // reflect open/close session changes immediately.
        //   table_sessions / orders  → 0.4s  (balanced instant visual feedback and network load)
        //   restaurant_tables        → 0.6s  (layout shift less jarring when batched)
        //   default / full pull      → 1.0s  (multiple endpoints — batch saves network)
        let debounceDelay: Double = {
            switch changedTable {
            case "table_sessions", "orders", "order_items": return 0.4
            case "restaurant_tables":                        return 0.6
            default:                                         return 1.0
            }
        }()
        realtimeDebounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            let capturedTable = changedTable
            Task {
                #if DEBUG
                print("SyncEngine [Realtime]: Debounced pull — changed table: \(capturedTable ?? "unknown")")
                #endif
                self.isCurrentlySyncing = true

                // ── Smart routing: pull only what changed ─────────────────
                // Pulls only the endpoints that actually need refreshing to optimize network usage.
                switch capturedTable {
                case "table_sessions":
                    await self.pullActiveSessions(modelContext)
                case "orders", "order_items":
                    await self.pullCustomerOrders(modelContext)
                    await self.pullActiveSessions(modelContext)
                case "service_requests":
                    await self.syncServiceRequests()
                case "restaurant_tables":
                    await self.pullRestaurantTables(modelContext)
                    await self.pullActiveSessions(modelContext)
                case "menu_items":
                    await self.pullMenuItemsFromSupabase(modelContext)
                case "categories":
                    await self.pullCategoriesFromSupabase(modelContext)
                case "modifiers":
                    await self.pullModifiersFromSupabase(modelContext)
                case "modifier_groups":
                    await self.pullModifierGroupsFromSupabase(modelContext)
                case "employees":
                    await self.pullEmployees(modelContext)
                case "employee_shifts":
                    await self.pullEmployeeShifts(modelContext)
                case "inventory_items":
                    await self.pullInventoryItemsFromSupabase(modelContext)
                case "customers":
                    await self.pullCustomersFromSupabase(modelContext)
                case "payments":
                    await self.pullCompletedOrdersAndPayments(modelContext)
                case "promotions":
                    await self.pullPromotionsFromSupabase(modelContext)
                    await self.pullPromotionBundleItemsFromSupabase(modelContext)
                case "expenses":
                    await self.pullExpensesFromSupabase(modelContext)
                case "suppliers":
                    await self.pullSuppliersFromSupabase(modelContext)
                case "tax_rates":
                    await self.pullTaxRatesFromSupabase(modelContext)
                case "recipes":
                    await self.pullRecipesFromSupabase(modelContext)
                case "receipt_templates":
                    await self.pullReceiptTemplatesFromSupabase(modelContext)
                case "table_layout_presets":
                    await self.pullTableLayoutPresetsFromSupabase(modelContext)
                case "currency_exchange_rates":
                    await self.pullCurrencyExchangeRatesFromSupabase(modelContext)
                case "users":
                    await self.pullUsersFromSupabase(modelContext)
                case "refund_transactions":
                    await self.pullRefundTransactionsFromSupabase(modelContext)
                case "tips":
                    await self.pullTipsFromSupabase(modelContext)
                case "order_tax_lines":
                    await self.pullOrderTaxLinesFromSupabase(modelContext)
                case "order_item_modifiers":
                    await self.pullOrderItemModifiersFromSupabase(modelContext)
                default:
                    // Unknown / composite event — full pull
                    await self.pullRestaurantTables(modelContext)
                    await self.pullRestaurantWallsFromSupabase(modelContext)
                    await self.pullTableLayoutPresetsFromSupabase(modelContext)
                    await self.pullCustomerOrders(modelContext)
                    await self.pullActiveSessions(modelContext)
                    await self.syncServiceRequests()
                    await self.pullEmployees(modelContext)
                    await self.pullEmployeeShifts(modelContext)
                    await self.pullMenuItemsFromSupabase(modelContext)
                    await self.pullPromotionsFromSupabase(modelContext)
                    await self.pullPromotionBundleItemsFromSupabase(modelContext)
                    await self.pullRegisterSessions(modelContext)
                    await self.pullCashMovements(modelContext)
                    await self.pullShiftReportsFromSupabase(modelContext)
                    await self.pullCustomersFromSupabase(modelContext)
                    await self.pullGiftCardsFromSupabase(modelContext)
                    await self.pullLoyaltyTransactionsFromSupabase(modelContext)
                    await self.pullTaxRatesFromSupabase(modelContext)
                    await self.pullCurrencyExchangeRatesFromSupabase(modelContext)
                    await self.pullRecipesFromSupabase(modelContext)
                    await self.pullExpensesFromSupabase(modelContext)
                    await self.pullRefundTransactionsFromSupabase(modelContext)
                    await self.pullOrderTaxLinesFromSupabase(modelContext)
                    await self.pullTipsFromSupabase(modelContext)
                    await self.pullOrderItemModifiersFromSupabase(modelContext)
                    await self.pullUsersFromSupabase(modelContext)
                    await self.pullReceiptTemplatesFromSupabase(modelContext)
                }

                self.isCurrentlySyncing = false
            }
        }
        realtimeDebounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceDelay, execute: workItem)
    }


}
