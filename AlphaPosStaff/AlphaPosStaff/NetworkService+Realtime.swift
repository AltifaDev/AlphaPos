// NetworkService+Realtime.swift
// Supabase Realtime WebSocket client, heartbeat, polling, and instant notifications.

import Foundation
import UIKit

extension NetworkService {
    func startRealtimeSync() {
        guard webSocketTask == nil else { return }
        
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
        
        // Reset reconnect counter on successful connection
        reconnectAttempt = 0
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
                        ["event": "*", "schema": "public", "table": "restaurant_tables", "filter": "merchant_id=eq.\(merchantId)"],
                        ["event": "*", "schema": "public", "table": "service_requests", "filter": "merchant_id=eq.\(merchantId)"],
                        ["event": "*", "schema": "public", "table": "floor_plan_images", "filter": "merchant_id=eq.\(merchantId)"],
                        ["event": "*", "schema": "public", "table": "merchants", "filter": "id=eq.\(merchantId)"],
                        ["event": "*", "schema": "public", "table": "employees", "filter": "merchant_id=eq.\(merchantId)"],
                        ["event": "*", "schema": "public", "table": "employee_shifts", "filter": "merchant_id=eq.\(merchantId)"],
                        ["event": "*", "schema": "public", "table": "timecards", "filter": "merchant_id=eq.\(merchantId)"]
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
        
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task {
                await self.refreshAll()
            }
        }
    }

    private func processInstantNotification(table: String, type: String, record: [String: Any]) {
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
                
                if type == "DELETE" {
                    if let idx = self.serviceRequests.firstIndex(where: { $0.id == id }) {
                        self.serviceRequests.remove(at: idx)
                    }
                } else {
                    if let idx = self.serviceRequests.firstIndex(where: { $0.id == id }) {
                        self.serviceRequests[idx] = req
                    } else if status == "pending" {
                        self.serviceRequests.insert(req, at: 0)
                    }
                    
                    if status == "pending" && notificationsEnabled {
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
                    let notificationKey = "\(id)-\(statusLower)"
                    
                    // Trigger instant alert if notifications are enabled
                    if notificationsEnabled {
                        if type == "INSERT" {
                            if statusLower == "preparing" || statusLower == "ready" {
                                if !notifiedOrderIds.contains(notificationKey) {
                                    self.markOrderAsNotified(key: notificationKey)
                                    // Delay notification until items are fetched so the body
                                    // shows item names instead of blank "Table X:".
                                    // Items arrive 1-3s after the order INSERT event.
                                    Task {
                                        try? await Task.sleep(nanoseconds: 2_500_000_000)
                                        if let fetched = try? await NetworkService.shared.fetchOrderById(id) {
                                            let itemsSummary = fetched.items.isEmpty
                                                ? "Table \(tableNumber)"
                                                : fetched.items.prefix(3).map { "\($0.quantity)× \($0.name)" }.joined(separator: ", ")
                                            let title = statusLower == "ready" ? "🍳 Order \(orderNumber) Ready!" : "🧾 New Order \(orderNumber)"
                                            NotificationManager.shared.notify(title: title, body: itemsSummary, type: .order, deduplicationKey: notificationKey, userInfo: ["table_number": tableNumber, "type": "order", "order_id": id])
                                        }
                                    }
                                }
                            }
                        } else if type == "UPDATE" {
                            if statusLower == "ready" || statusLower == "served" {
                                if !notifiedOrderIds.contains(notificationKey) {
                                    self.markOrderAsNotified(key: notificationKey)
                                    let title = statusLower == "ready" ? "🍳 Order \(orderNumber) Ready!" : "🍽️ Order \(orderNumber) Served"
                                    let body = statusLower == "ready" ? "Table \(tableNumber) is ready to be served" : "Table \(tableNumber) has been served"
                                    let notifyType: NotificationType = statusLower == "ready" ? .order : .tableStatus
                                    NotificationManager.shared.notify(title: title, body: body, type: notifyType, deduplicationKey: notificationKey, userInfo: ["table_number": tableNumber, "type": "order", "order_id": id])
                                }
                            }
                        }
                    }
                    
                    // Fetch the single order + items to mutate self.orders locally
                    Task {
                        do {
                            // When the iPad sends an order it POSTs orders first, then order_items.
                            // Delay 2.0 s on INSERT (increased from 1.2 s) to cover slow networks
                            // and server load. The retry loop below handles persistent race conditions.
                            if type == "INSERT" {
                                try? await Task.sleep(nanoseconds: 2_000_000_000)
                            }
                            // Retry up to 4 times (2s, 2s, 3s, 3s) until items arrive
                            var fetchedOrder = try await NetworkService.shared.fetchOrderById(id)
                            let retryDelays: [UInt64] = [2_000_000_000, 2_000_000_000, 3_000_000_000, 3_000_000_000]
                            if type == "INSERT" {
                                for delay in retryDelays {
                                    guard let order = fetchedOrder, order.items.isEmpty else { break }
                                    try? await Task.sleep(nanoseconds: delay)
                                    fetchedOrder = try? await NetworkService.shared.fetchOrderById(id)
                                }
                            }
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
                
            // 3. Restaurant Tables Mutation & Alert
            } else if table == "restaurant_tables" {
                guard let tableNumber = record["table_number"] as? String,
                      let status = record["status"] as? String else { return }
                
                if let idx = self.tables.firstIndex(where: { $0.tableNumber == tableNumber }) {
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
                
            // 4. Table Sessions Mutation
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
                        self.tables[idx].sessionToken = record["session_token"] as? String
                        self.tables[idx].guestCount = record["guest_count"] as? Int ?? 0
                        self.tables[idx].status = "occupied"
                        self.tables[idx].sessionStartedAt = record["started_at"] as? String ?? record["created_at"] as? String
                    } else {
                        self.tables[idx].sessionToken = nil
                        self.tables[idx].guestCount = 0
                        self.tables[idx].status = "vacant"
                        self.tables[idx].currentTotal = 0.0
                        self.tables[idx].sessionStartedAt = nil
                    }
                }
            } else if table == "order_items" {
                guard let orderId = record["order_id"] as? String else { return }
                
                // Fetch the single order + items to mutate self.orders locally
                Task {
                    do {
                        // INSERT event arrives before the batch order_items POST completes.
                        // Wait 1.2 s (เพิ่มจาก 0.8s) เพื่อให้ batch POST order_items เสร็จก่อน
                        if type == "INSERT" {
                            try? await Task.sleep(nanoseconds: 1_200_000_000)
                        }
                        // Retry loop: รอให้ items มาถึงก่อน insert/update self.orders
                        var fetchedOrder = try await NetworkService.shared.fetchOrderById(orderId)
                        let retryDelays: [UInt64] = [1_500_000_000, 2_000_000_000, 2_500_000_000]
                        if type == "INSERT" {
                            for delay in retryDelays {
                                guard let order = fetchedOrder, order.items.isEmpty else { break }
                                try? await Task.sleep(nanoseconds: delay)
                                fetchedOrder = try? await NetworkService.shared.fetchOrderById(orderId)
                            }
                        }
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
        } else if event == "phx_reply" || event == "system" || event == "phx_close" {
            #if DEBUG
            if event == "phx_reply" {
                if let payload = json["payload"] as? [String: Any],
                   let status = payload["status"] as? String {
                    print("NetworkService [Realtime]: phx_reply status = \(status)")
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
