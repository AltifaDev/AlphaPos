// NetworkService+Realtime.swift
// Supabase Realtime WebSocket client, heartbeat, polling, and instant notifications.

import Foundation
import UIKit

extension NetworkService {
    func startRealtimeSync() {
        guard webSocketTask == nil else { return }
        realtimeJoinSucceeded = false
        
        let baseRealtimeURL = AppConfig.supabaseRealtimeURL.absoluteString
            .replacingOccurrences(of: "https://", with: "wss://")
            .replacingOccurrences(of: "http://", with: "ws://")
        let wsURLString = "\(baseRealtimeURL)/websocket?apikey=\(anonKey)&vsn=1.0.0"
        guard let url = URL(string: wsURLString) else { return }
        
        let wsSession = URLSession(configuration: .default)
        let task = wsSession.webSocketTask(with: url)
        self.webSocketTask = task
        task.resume()
        
        listenToWebSocket()
        joinRealtimeTopic()
        startHeartbeat()
        startPollingSync()
        
    }

    private func listenToWebSocket() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleWebSocketMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleWebSocketMessage(text)
                    }
                @unknown default:
                    break
                }
                self.listenToWebSocket()
            case .failure(let error):
                print("NetworkService WebSocket error: \(error.localizedDescription)")
                self.realtimeJoinSucceeded = false
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
                print("NetworkService: Reconnecting in \(String(format: "%.1f", finalDelay))s (attempt \(reconnectAttempt))")
                #endif
                
                DispatchQueue.main.asyncAfter(deadline: .now() + finalDelay) {
                    self.startRealtimeSync()
                }
            }
        }
    }

    private func joinRealtimeTopic() {
        let merchantId = self.activeMerchantId
        let accessToken = authorizationToken
        
        let joinPayload: [String: Any] = [
            "topic": "realtime:public",
            "event": "phx_join",
            "payload": [
                "config": [
                    "postgres_changes": [
                        ["event": "*", "schema": "public", "table": "orders", "filter": "merchant_id=eq.\(merchantId)"],
                        ["event": "*", "schema": "public", "table": "order_items", "filter": "merchant_id=eq.\(merchantId)"],
                        ["event": "*", "schema": "public", "table": "order_item_modifiers", "filter": "merchant_id=eq.\(merchantId)"],
                        ["event": "*", "schema": "public", "table": "table_sessions", "filter": "merchant_id=eq.\(merchantId)"],
                        ["event": "*", "schema": "public", "table": "restaurant_tables", "filter": "merchant_id=eq.\(merchantId)"],
                        ["event": "*", "schema": "public", "table": "service_requests", "filter": "merchant_id=eq.\(merchantId)"],
                        ["event": "*", "schema": "public", "table": "floor_plan_images", "filter": "merchant_id=eq.\(merchantId)"],
                        ["event": "*", "schema": "public", "table": "dining_areas", "filter": "merchant_id=eq.\(merchantId)"],
                        ["event": "*", "schema": "public", "table": "sync_outbox", "filter": "merchant_id=eq.\(merchantId)"]
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
                    print("NetworkService: Failed to send join payload: \(error)")
                } else {
                    print("NetworkService: Successfully sent join payload (merchant-scoped).")
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
                        print("NetworkService heartbeat failed: \(error)")
                    }
                }
            }
        }
    }

    private func startPollingSync() {
        pollingTimer?.invalidate()
        pollingTimer = nil

        pollingTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] timer in
            guard let self = self else { return }
            Task {
                await self.refreshAll()
            }
            // ── WebSocket health check ────────────────────────────────────
            // ถ้า webSocketTask เป็น nil (disconnect โดยไม่มี error callback)
            // ให้ reconnect ทันทีโดยไม่รอ backoff
            if self.webSocketTask == nil {
                #if DEBUG
                print("NetworkService [HealthCheck]: WebSocket nil — reconnecting...")
                #endif
                self.reconnectAttempt = 0
                self.startRealtimeSync()
            }
        }
    }

    /// Force reconnect WebSocket ทันที — เรียกจาก outside (เช่น TablesView pull-to-refresh)
    func forceReconnect() {
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        realtimeJoinSucceeded = false
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        reconnectAttempt = 0
        startRealtimeSync()
        Task { await refreshAll() }
    }

    private func processInstantNotification(table: String, type: String, record: [String: Any]) {
        // Realtime subscriptions are merchant-filtered. Enforce branch scope a
        // second time on-device so a stale/mis-issued token can never surface
        // another branch's operational event or notification.
        if let recordBranch = record["branch_id"] as? String,
           !recordBranch.isEmpty,
           recordBranch.lowercased() != StaffSessionContext.branchId {
            return
        }
        Task { @MainActor in
            let notificationsEnabled = UserDefaults.standard.object(forKey: "enable_notifications") as? Bool ?? true
            
            // 1. Service Requests Mutation & Alert
            if table == "service_requests" {
                guard let id = record["id"] as? String,
                      let tableNumber = record["table_number"] as? String,
                      let requestType = record["request_type"] as? String,
                      let status = record["status"] as? String else { return }
                
                let req = ServiceRequest(
                    id: id,
                    tableNumber: tableNumber,
                    requestType: requestType,
                    status: status,
                    createdAt: record["created_at"] as? String ?? ISO8601DateFormatter().string(from: Date())
                )
                let isCurrentRequest = StaffNotificationPolicy.isCurrentBusinessDay(timestamp: req.createdAt)
                
                if type == "DELETE" {
                    if let idx = self.serviceRequests.firstIndex(where: { $0.id == id }) {
                        self.serviceRequests.remove(at: idx)
                    }
                } else {
                    if let idx = self.serviceRequests.firstIndex(where: { $0.id == id }) {
                        self.serviceRequests[idx] = req
                    } else if status == "pending" && isCurrentRequest {
                        self.serviceRequests.insert(req, at: 0)
                    }
                    
                    if status == "pending" && isCurrentRequest && notificationsEnabled {
                        guard !notifiedRequestIds.contains(id) else { return }
                        self.markRequestAsNotified(requestId: id)
                        
                        let title = "🔔 Table \(tableNumber): \(requestType)"
                        let body = "Customer requested assistance"
                        NotificationManager.shared.notify(title: title, body: body, type: .request, deduplicationKey: "req-\(id)", userInfo: ["table_number": tableNumber, "type": "service_request", "request_id": id])
                    }
                }
                
            // 2. Orders Mutation & Alert
            } else if table == "orders" {
                guard let id = record["id"] as? String else { return }
                
                if type == "DELETE" {
                    if let idx = self.orders.firstIndex(where: { $0.id == id }) {
                        self.orders.remove(at: idx)
                    }
                } else {
                    guard let status = record["status"] as? String else { return }
                    let tableNumber = record["table_number"] as? String ?? "N/A"
                    let orderSource = record["order_source"] as? String ?? "pos"
                    let rawOrderNum = record["order_number"]
                    let orderNumber: String
                    if let numStr = rawOrderNum as? String {
                        orderNumber = numStr
                    } else if let numInt = rawOrderNum as? Int {
                        orderNumber = String(numInt)
                    } else {
                        orderNumber = "N/A"
                    }

                    let statusLower = status.lowercased()
                    let isWebOrder = orderSource == "web"
                    let eventDate = ISO8601DateParser.date(from: record["created_at"] as? String)
                    let isCurrentEvent = StaffNotificationPolicy.isCurrentBusinessDay(eventDate)
                    // Use source-aware key so web "pending" and staff "preparing" deduplicate separately
                    let notificationKey = "\(id)-\(statusLower)-\(orderSource)"

                    // Trigger instant alert if notifications are enabled
                    if notificationsEnabled && isCurrentEvent {
                        if type == "INSERT" {
                            // Web orders arrive as "pending" (awaiting approval)
                            // Staff orders arrive as "preparing" — both should notify
                            let shouldNotifyInsert = isWebOrder
                                ? statusLower == "pending"
                                : (statusLower == "preparing" || statusLower == "ready")
                            if shouldNotifyInsert {
                                if !notifiedOrderIds.contains(notificationKey) {
                                    self.markOrderAsNotified(key: notificationKey)
                                    let title = isWebOrder
                                        ? "🌐 Web Order \(orderNumber) — อนุมัติด่วน!"
                                        : (statusLower == "ready" ? "🍳 Order \(orderNumber) Ready!" : "🧾 New Order \(orderNumber)")
                                    NotificationManager.shared.notify(title: title, body: "Table \(tableNumber)", type: .order, deduplicationKey: notificationKey, userInfo: ["table_number": tableNumber, "type": "order", "order_id": id])
                                }
                            }
                        } else if type == "UPDATE" {
                            if statusLower == "preparing" || statusLower == "ready" || statusLower == "served" {
                                if !notifiedOrderIds.contains(notificationKey) {
                                    self.markOrderAsNotified(key: notificationKey)
                                    let title = statusLower == "preparing" ? "🧾 New Order \(orderNumber)" : (statusLower == "ready" ? "🍳 Order \(orderNumber) Ready!" : "🍽️ Order \(orderNumber) Served")
                                    let body = statusLower == "preparing" ? "Table \(tableNumber)" : (statusLower == "ready" ? "Table \(tableNumber) is ready to be served" : "Table \(tableNumber) has been served")
                                    let notifyType: NotificationType = statusLower == "served" ? .tableStatus : .order
                                    NotificationManager.shared.notify(title: title, body: body, type: notifyType, deduplicationKey: notificationKey, userInfo: ["table_number": tableNumber, "type": "order", "order_id": id])
                                }
                            }
                        }
                    }
                    
                    // Fetch the single order + items to mutate self.orders locally
                    Task {
                        do {
                            // Atomic order RPC commits the complete aggregate before
                            // Postgres emits Realtime events, so no timing sleeps are needed.
                            let fetchedOrder = try await NetworkService.shared.fetchOrderById(id)
                            if let order = fetchedOrder {
                                await MainActor.run {
                                    if let idx = self.orders.firstIndex(where: { $0.id == order.id }) {
                                        self.orders[idx] = order
                                    } else {
                                        self.orders.insert(order, at: 0)
                                    }
                                }
                            }
                        } catch {
                            print("NetworkService [Realtime fetchOrderById failed]: \(error)")
                        }
                    }
                }
                
            // 3. Merchant settings mutation
            } else if table == "merchants" {
                if let tableSystemEnabled = record["is_table_system_enabled"] as? Bool {
                    self.isTableSystemEnabled = tableSystemEnabled
                }
                if let webOrderingEnabled = record["is_web_ordering_enabled"] as? Bool {
                    self.isWebOrderingEnabled = webOrderingEnabled
                }
                if let workflowRequired = record["kitchen_workflow_required"] as? Bool {
                    self.kitchenWorkflowRequired = workflowRequired
                }
                if let promptPay = record["promptpay_number"] as? String {
                    self.promptPayNumber = promptPay
                }

            // 4. Restaurant Tables Mutation & Alert
            } else if table == "restaurant_tables" {
                guard let tableNumber = record["table_number"] as? String,
                      let status = record["status"] as? String else { return }
                
                if let idx = self.tables.firstIndex(where: { $0.tableNumber == tableNumber }) {
                    // table_sessions is authoritative for occupied/vacant. A delayed
                    // restaurant_tables event must not make an active table look vacant.
                    guard self.tables[idx].sessionToken == nil || status == "occupied" else { return }
                    self.tables[idx].status = status
                    if status == "vacant" {
                        self.tables[idx].sessionToken = nil
                        self.tables[idx].currentTotal = 0.0
                        self.tables[idx].guestCount = 0
                    }
                }
                
                if notificationsEnabled {
                    let notifiedStatus = notifiedTableStatuses[tableNumber]
                    if notifiedStatus != status {
                        notifiedTableStatuses[tableNumber] = status
                        if status == "occupied" {
                            let guestCount = record["guest_count"] as? Int ?? 0
                            let title = "🚪 Table \(tableNumber) Occupied"
                            let body = "Session started for \(guestCount) guests"
                            NotificationManager.shared.notify(title: title, body: body, type: .tableStatus, deduplicationKey: "table-\(tableNumber)-occupied", userInfo: ["table_number": tableNumber, "type": "table_status"])
                        } else if status == "vacant" {
                            let title = "💳 Table \(tableNumber) Vacant"
                            let body = "Session ended / table cleared"
                            NotificationManager.shared.notify(title: title, body: body, type: .tableStatus, deduplicationKey: "table-\(tableNumber)-vacant", userInfo: ["table_number": tableNumber, "type": "table_status"])
                        }
                    }
                }
                
            // 5. Table Sessions Mutation
            } else if table == "table_sessions" {
                guard let tableNumber = record["table_number"] as? String else { return }
                
                // Handle is_active as both Bool (from AlphaPos) and Int (from customer-order-web)
                let isActive: Bool
                if let boolVal = record["is_active"] as? Bool {
                    isActive = boolVal
                } else if let intVal = record["is_active"] as? Int {
                    isActive = intVal != 0
                } else {
                    return
                }
                
                if let idx = self.tables.firstIndex(where: { $0.tableNumber == tableNumber }) {
                    if isActive {
                        self.tables[idx].activeSessionId = record["id"] as? String
                        self.tables[idx].sessionToken = record["session_token"] as? String
                        self.tables[idx].guestCount = record["guest_count"] as? Int ?? 0
                        self.tables[idx].status = "occupied"
                        self.tables[idx].sessionStartedAt = record["started_at"] as? String ?? record["created_at"] as? String
                    } else {
                        self.tables[idx].activeSessionId = nil
                        self.tables[idx].sessionToken = nil
                        self.tables[idx].guestCount = 0
                        if self.tables[idx].status == "occupied" {
                            self.tables[idx].status = "vacant"
                        }
                        self.tables[idx].currentTotal = 0.0
                        self.tables[idx].sessionStartedAt = nil
                    }
                }
            } else if table == "order_items" {
                guard let orderId = record["order_id"] as? String else { return }
                
                // Fetch the single order + items to mutate self.orders locally
                Task {
                    do {
                        let fetchedOrder = try await NetworkService.shared.fetchOrderById(orderId)
                        if let order = fetchedOrder {
                            await MainActor.run {
                                if let idx = self.orders.firstIndex(where: { $0.id == order.id }) {
                                    self.orders[idx] = order
                                } else {
                                    // order_items event มาถึงก่อน orders event (หรือ order ไม่อยู่ใน limit)
                                    // ให้เพิ่ม order เข้า self.orders เสมอ เพื่อให้ onChange ใน TableDetailView fire
                                    self.orders.insert(order, at: 0)
                                }
                            }
                        }
                    } catch {
                        print("NetworkService [Realtime fetchOrderById for order_items failed]: \(error)")
                    }
                }
            } else if table == "order_item_modifiers" {
                // An option was added/removed/changed on an order item. The record
                // only carries order_item_id, so find the owning order in memory and
                // refetch it (fetchOrderById now joins order_item_modifiers → modifiers).
                guard let orderItemId = record["order_item_id"] as? String else { return }
                let owningOrderId = self.orders.first { order in
                    order.items.contains { $0.id == orderItemId }
                }?.id
                guard let orderId = owningOrderId else {
                    // Owning order not loaded yet — the debounced refreshAll will reconcile.
                    return
                }
                Task {
                    if let order = try? await NetworkService.shared.fetchOrderById(orderId) {
                        await MainActor.run {
                            if let idx = self.orders.firstIndex(where: { $0.id == order.id }) {
                                self.orders[idx] = order
                            }
                        }
                    }
                }
            } else if table == "sync_outbox" {
                // Outbox rows are emitted only after their parent transaction
                // commits. Reconcile from the authoritative aggregate once.
                Task { await self.refreshAll() }
            } else if table == "floor_plan_images" {
                Task {
                    if let fetchedFloorPlans = try? await self.fetchFloorPlanImages() {
                        await MainActor.run {
                            self.floorPlanImages = fetchedFloorPlans
                        }
                    }
                }
            }
        }
    }

    private func handleWebSocketMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let event = json["event"] as? String else { return }
        
        // Supabase Realtime V1 sends postgres change events with event name "postgres_changes".
        // Also handle other event formats for robustness.
        let isPostgresChange: Bool
        if event == "postgres_changes" {
            isPostgresChange = true
        } else if event == "phx_reply" {
            let status = (json["payload"] as? [String: Any])?["status"] as? String
            if status == "ok" {
                realtimeJoinSucceeded = true
                reconnectAttempt = 0
            } else if status == "error" {
                realtimeJoinSucceeded = false
            }
            #if DEBUG
            print("NetworkService [Realtime]: phx_reply status = \(status ?? "unknown")")
            #endif
            isPostgresChange = false
        } else if event == "system" || event == "phx_close" {
            realtimeJoinSucceeded = false
            #if DEBUG
            print("NetworkService [Realtime]: control event = \(event), reconnecting")
            #endif
            webSocketTask?.cancel(with: .goingAway, reason: nil)
            webSocketTask = nil
            heartbeatTimer?.invalidate()
            heartbeatTimer = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self, self.webSocketTask == nil else { return }
                self.startRealtimeSync()
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
        
        // Extract postgres_changes payload:
        if let payload = json["payload"] as? [String: Any],
           let dataPayload = payload["data"] as? [String: Any],
           let table = dataPayload["table"] as? String,
           let type = dataPayload["type"] as? String {
            let record = dataPayload["record"] as? [String: Any] ?? dataPayload["old_record"] as? [String: Any] ?? [:]
            
            // Process instant notification immediately
            processInstantNotification(table: table, type: type, record: record)
            
            // Debounced full refresh: cancel pending task and schedule a new one after 1.5s.
            // This ensures the in-memory model stays fully consistent after rapid-fire events.
            realtimeRefreshTask?.cancel()
            realtimeRefreshTask = Task { [weak self] in
                guard let self = self else { return }
                do {
                    try await Task.sleep(nanoseconds: 1_500_000_000)
                } catch {
                    return // Task was cancelled — do nothing
                }
                #if DEBUG
                print("NetworkService [Realtime]: Performing debounced refreshAll...")
                #endif
                await self.refreshAll()
            }
        }
    }
}
