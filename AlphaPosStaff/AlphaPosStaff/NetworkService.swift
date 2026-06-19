import Foundation
import Observation
import UIKit
import CryptoKit

enum NetworkError: Error, LocalizedError {
    case offline
    case serverError(String)
    case invalidResponse
    
    var errorDescription: String? {
        switch self {
        case .offline: return "No internet connection detected."
        case .serverError(let msg): return "Server returned error: \(msg)"
        case .invalidResponse: return "Received invalid response from server."
        }
    }
}

struct SyncResponse: Codable {
    let tables: [RestaurantTable]
    let requests: [ServiceRequest]
    let orders: [Order]?
}

@Observable
final class NetworkService {
    static let shared = NetworkService()
    
    var baseURL: URL { AppConfig.supabaseRestURL }
    private var anonKey: String { AppConfig.supabaseAnonKey }
    
    @ObservationIgnored
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpShouldUsePipelining = true
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        return URLSession(configuration: config)
    }()
    
    // Global lists
    var tables: [RestaurantTable] = []
    var walls: [RestaurantWall] = []
    var menuItems: [MenuItem] = []
    var serviceRequests: [ServiceRequest] = []
    var orders: [Order] = []
    
    var activeAlertsCount: Int {
        let pendingRequests = serviceRequests.filter { $0.status == "pending" }.count
        let preparingOrReadyOrders = orders.filter { $0.status == "preparing" || $0.status == "ready" }.count
        return pendingRequests + preparingOrReadyOrders
    }
    
    // Status states
    var isFetching = false
    var connectionError = false
    
    /// Convenience computed property: true when connected to backend
    var isOnline: Bool { !connectionError }
    var kitchenWorkflowRequired = true
    var promptPayNumber = ""
    var isTableSystemEnabled = true
    var isWebOrderingEnabled = true
    private var lastSyncTime: Date = Date(timeIntervalSince1970: 0)
    
    @ObservationIgnored
    private var notifiedRequestIds = Set<String>()
    @ObservationIgnored
    private var notifiedRequestKeysHistory: [String] = []
    @ObservationIgnored
    private var notifiedOrderIds = Set<String>()
    @ObservationIgnored
    private var notifiedOrderKeysHistory: [String] = []
    @ObservationIgnored
    private var notifiedTableStatuses: [String: String] = [:]
    
    private func markOrderAsNotified(key: String) {
        if !self.notifiedOrderIds.contains(key) {
            self.notifiedOrderIds.insert(key)
            self.notifiedOrderKeysHistory.append(key)
            if self.notifiedOrderKeysHistory.count > 300 {
                let oldest = self.notifiedOrderKeysHistory.removeFirst()
                self.notifiedOrderIds.remove(oldest)
            }
        }
    }
    
    private func markRequestAsNotified(requestId: String) {
        if !self.notifiedRequestIds.contains(requestId) {
            self.notifiedRequestIds.insert(requestId)
            self.notifiedRequestKeysHistory.append(requestId)
            if self.notifiedRequestKeysHistory.count > 300 {
                let oldest = self.notifiedRequestKeysHistory.removeFirst()
                self.notifiedRequestIds.remove(oldest)
            }
        }
    }
    
    @ObservationIgnored
    private var _isCurrentlySyncing = false
    private let syncLock = NSLock()
    private var isCurrentlySyncing: Bool {
        get { syncLock.lock(); defer { syncLock.unlock() }; return _isCurrentlySyncing }
        set { syncLock.lock(); defer { syncLock.unlock() }; _isCurrentlySyncing = newValue }
    }
    
    private var isFirstSync = true
    
    private func writeDebugLog(_ message: String) {
        guard let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let logURL = docsURL.appendingPathComponent("debug_sync.log")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let timestamp = formatter.string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logURL.path) {
                if let fileHandle = try? FileHandle(forWritingTo: logURL) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            } else {
                try? line.write(to: logURL, atomically: true, encoding: .utf8)
            }
        }
    }
    
    @ObservationIgnored
    private var activeSyncTask: Task<Void, Never>?
    
    private var activeMerchantId: String {
        let raw = UserDefaults.standard.string(forKey: "active_merchant_id") ?? AppConfig.defaultMerchantId
        return raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? AppConfig.defaultMerchantId.lowercased() : raw.lowercased()
    }
    
    private init() {
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
            print("NetworkService: App returned to foreground. Reconnecting WebSocket...")
            #endif
            
            // Cancel existing WebSocket task
            self.webSocketTask?.cancel(with: .normalClosure, reason: nil)
            self.webSocketTask = nil
            
            // Reconnect WebSocket and sync REST data
            self.startRealtimeSync()
            Task {
                // Single sync on foreground resume
                await self.refreshAll()
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            #if DEBUG
            print("NetworkService: App entered background. Stopping timers...")
            #endif
            self.heartbeatTimer?.invalidate()
            self.heartbeatTimer = nil
            self.pollingTimer?.invalidate()
            self.pollingTimer = nil
            self.webSocketTask?.cancel(with: .normalClosure, reason: nil)
            self.webSocketTask = nil
        }
        
        // Observe JWT token refresh — reconnect WebSocket with the new token
        NotificationCenter.default.addObserver(
            forName: .merchantTokenDidRefresh,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            #if DEBUG
            print("NetworkService: JWT token refreshed. Reconnecting WebSocket...")
            #endif
            self.webSocketTask?.cancel(with: .normalClosure, reason: nil)
            self.webSocketTask = nil
            self.heartbeatTimer?.invalidate()
            self.heartbeatTimer = nil
            self.startRealtimeSync()
            Task { try? await self.registerSavedPushToken() }
        }
    }

    func registerPushDevice(token: String) async throws {
        UserDefaults.standard.set(token, forKey: "apns_device_token")
        try await registerSavedPushToken()
    }

    private func registerSavedPushToken() async throws {
        guard let token = UserDefaults.standard.string(forKey: "apns_device_token"), !token.isEmpty else { return }
        let payload: [String: Any] = [
            "merchant_id": activeMerchantId,
            "device_token": token,
            "app_id": "staff",
            "platform": "ios",
            "is_active": true,
            "updated_at": ISO8601DateFormatter().string(from: Date())
        ]
        _ = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "push_devices",
            queryItems: [URLQueryItem(name: "on_conflict", value: "device_token")],
            payload: payload
        )
    }
    
    // Ping/Check connection to Supabase menu_items REST endpoint
    func checkConnection() async -> Bool {
        var req = URLRequest(url: baseURL.appendingPathComponent("menu_items"))
        req.httpMethod = "HEAD"
        // Use merchant JWT if available, fall back to anon key
        let token = MerchantAuthManager.shared.currentToken ?? anonKey
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 2.0
        do {
            let (_, response) = try await session.data(for: req)
            if let httpResponse = response as? HTTPURLResponse {
                return (200...299).contains(httpResponse.statusCode)
            }
            return false
        } catch {
            return false
        }
    }
    
    // General request sender that performs actual HTTP queries to Supabase
    private func sendSupabaseRequest(method: String, endpoint: String, queryItems: [URLQueryItem]? = nil, payload: Any? = nil) async throws -> Data {
        var url = baseURL.appendingPathComponent(endpoint)
        if let queryItems = queryItems, var components = URLComponents(url: url, resolvingAgainstBaseURL: true) {
            components.queryItems = queryItems
            if let newUrl = components.url {
                url = newUrl
            }
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        // Use merchant JWT if available — the JWT contains a `merchant_id` claim
        // that PostgREST extracts via `current_setting('request.jwt.claims')`,
        // enabling RLS policies to isolate data per merchant automatically.
        let token = MerchantAuthManager.shared.currentToken ?? anonKey
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // merchant_id is now embedded in the JWT claims — no x-merchant-id header needed
        
        request.timeoutInterval = 5.0
        
        // Enable upsert for POST with on_conflict parameter
        if method == "POST" {
            request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        }
        
        if let payload = payload {
            let jsonData = try JSONSerialization.data(withJSONObject: payload)
            request.httpBody = jsonData
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "HTTP Request failed"
            throw NetworkError.serverError(errorMsg)
        }
        
        return data
    }
    
    func refreshAll() async {
        // Auto-authenticate via JWT if not already authenticated in development
        if !MerchantAuthManager.shared.isAuthenticated {
            #if DEBUG
            print("NetworkService: Not authenticated via JWT. Performing auto-authentication...")
            #endif
            let merchantId = activeMerchantId.isEmpty ? AppConfig.defaultMerchantId : activeMerchantId
            do {
                try await MerchantAuthManager.shared.authenticate(
                    merchantId: merchantId,
                    deviceSecret: AppConfig.defaultDeviceSecret
                )
            } catch {
                #if DEBUG
                print("NetworkService: Auto-authentication failed: \(error.localizedDescription)")
                #endif
            }
        }

        if let existingTask = activeSyncTask {
            await existingTask.value
            return
        }
        
        let task = Task { @MainActor in
            await performRefreshAll()
        }
        activeSyncTask = task
        await task.value
        activeSyncTask = nil
    }
    
    private func performRefreshAll() async {
        // Prevent rapid consecutive syncs (debounce 5 seconds)
        let now = Date()
        if now.timeIntervalSince(lastSyncTime) < 3.0 {
            #if DEBUG
            print("[NetworkService] Sync debounced - last sync was \(Int(now.timeIntervalSince(lastSyncTime)))s ago")
            #endif
            return
        }
        lastSyncTime = now
        
        isCurrentlySyncing = true
        isFetching = true
        
        defer {
            isFetching = false
            isCurrentlySyncing = false
        }
        
        do {
            // Fetch menu once on startup/demand
            if menuItems.isEmpty {
                if let menu = try? await fetchMenu() {
                    await MainActor.run {
                        self.menuItems = menu
                    }
                }
            }
            
            // Perform concurrent requests to Supabase
            async let fetchedTables = fetchTables()
            async let fetchedRequests = fetchRequests()
            async let fetchedOrders = fetchAllActiveOrders()
            async let fetchedWorkflow = fetchMerchantSettings()
            async let fetchedWalls = fetchWalls()
            
            // Await all concurrent fetches (orders first for notification priority)
            let ordersRes = try await fetchedOrders
            let (tablesRes, requestsRes, wallsRes) = try await (fetchedTables, fetchedRequests, fetchedWalls)
            let settingsRes = (try? await fetchedWorkflow) ?? (true, "", true, true)
            
            await MainActor.run {
                self.kitchenWorkflowRequired = settingsRes.0
                self.promptPayNumber = settingsRes.1
                self.isTableSystemEnabled = settingsRes.2
                self.isWebOrderingEnabled = settingsRes.3
                let oldTables = self.tables
                let oldRequests = self.serviceRequests
                let oldOrders = self.orders
                
                self.writeDebugLog("--- performRefreshAll sync block ---")
                self.writeDebugLog("isFirstSync: \(self.isFirstSync)")
                self.writeDebugLog("oldOrders count: \(oldOrders.count), ordersRes count: \(ordersRes.count)")
                
                if self.tables != tablesRes {
                    self.tables = tablesRes
                }
                if self.walls != wallsRes {
                    self.walls = wallsRes
                }
                if self.serviceRequests != requestsRes {
                    self.serviceRequests = requestsRes
                }
                if self.orders != ordersRes {
                    self.orders = ordersRes
                }
                self.connectionError = false
                
                // Diff-checking for notifications
                if !self.isFirstSync {
                    let notificationsEnabled = UserDefaults.standard.object(forKey: "enable_notifications") as? Bool ?? true
                    self.writeDebugLog("notificationsEnabled: \(notificationsEnabled)")
                    if notificationsEnabled {
                        // 1. Service Requests Diff
                        let oldPendingIds = Set(oldRequests.filter { $0.status == "pending" }.map { $0.id })
                        let newPendingRequests = requestsRes.filter { $0.status == "pending" }
                        for req in newPendingRequests {
                            if !oldPendingIds.contains(req.id) && !self.notifiedRequestIds.contains(req.id) {
                                self.markRequestAsNotified(requestId: req.id)
                                let title = "🔔 Table \(req.tableNumber): \(req.requestType)"
                                let body = "Customer requested assistance at \(self.formatISOStringTime(req.createdAt))"
                                NotificationManager.shared.notify(title: title, body: body, type: .request, deduplicationKey: "req-\(req.id)", userInfo: ["table_number": req.tableNumber, "type": "service_request", "request_id": req.id])
                            }
                        }
                        
                        // 2. Table Status Diff
                        for table in tablesRes {
                            if let oldTable = oldTables.first(where: { $0.tableNumber == table.tableNumber }) {
                                if oldTable.status != table.status {
                                    let notifiedStatus = self.notifiedTableStatuses[table.tableNumber]
                                    if notifiedStatus != table.status {
                                        self.notifiedTableStatuses[table.tableNumber] = table.status
                                        if table.status == "occupied" {
                                            let title = "🚪 Table \(table.tableNumber) Occupied"
                                            let body = "Session started for \(table.guestCount) guests"
                                            NotificationManager.shared.notify(title: title, body: body, type: .tableStatus, deduplicationKey: "table-\(table.tableNumber)-occupied", userInfo: ["table_number": table.tableNumber, "type": "table_status"])
                                        } else if table.status == "vacant" && oldTable.status == "occupied" {
                                            let title = "💳 Table \(table.tableNumber) Vacant"
                                            let body = "Session ended / table cleared"
                                            NotificationManager.shared.notify(title: title, body: body, type: .tableStatus, deduplicationKey: "table-\(table.tableNumber)-vacant", userInfo: ["table_number": table.tableNumber, "type": "table_status"])
                                        }
                                    }
                                }
                            }
                        }
                        
                        // 3. Order Status Diff
                        for order in ordersRes {
                            let statusLower = order.status.lowercased()
                            self.writeDebugLog("Diffing order \(order.orderNumber) with status \(statusLower)")
                            if let oldOrder = oldOrders.first(where: { $0.id == order.id }) {
                                self.writeDebugLog("Found old order \(order.orderNumber), old status: \(oldOrder.status), new status: \(order.status)")
                                if oldOrder.status != order.status {
                                    if statusLower == "ready" {
                                        let notificationKey = "\(order.id)-ready"
                                        if !self.notifiedOrderIds.contains(notificationKey) {
                                            self.writeDebugLog("Triggering ready notification for order \(order.orderNumber)")
                                            self.markOrderAsNotified(key: notificationKey)
                                            let itemsSummary = order.items.map { "\($0.quantity)x \($0.name)" }.joined(separator: ", ")
                                            let title = "🍳 Order \(order.orderNumber) Ready!"
                                            let body = "Table \(order.tableNumber): \(itemsSummary)"
                                            NotificationManager.shared.notify(title: title, body: body, type: .order, deduplicationKey: notificationKey, userInfo: ["table_number": order.tableNumber, "type": "order", "order_id": order.id])
                                        }
                                    }
                                }
                            } else {
                                self.writeDebugLog("Order \(order.orderNumber) is NEW (not in oldOrders)!")
                                if statusLower == "preparing" || statusLower == "ready" {
                                    let notificationKey = "\(order.id)-\(statusLower)"
                                    if !self.notifiedOrderIds.contains(notificationKey) {
                                        self.writeDebugLog("Triggering new/preparing notification for order \(order.orderNumber)")
                                        self.markOrderAsNotified(key: notificationKey)
                                        let itemsSummary = order.items.map { "\($0.quantity)x \($0.name)" }.joined(separator: ", ")
                                        let title = statusLower == "ready" ? "🍳 Order \(order.orderNumber) Ready!" : "📝 New Order \(order.orderNumber)"
                                        let body = "Table \(order.tableNumber): \(itemsSummary)"
                                        NotificationManager.shared.notify(title: title, body: body, type: .order, deduplicationKey: notificationKey, userInfo: ["table_number": order.tableNumber, "type": "order", "order_id": order.id])
                                    } else {
                                        self.writeDebugLog("Already notified order \(order.orderNumber) with key \(notificationKey)")
                                    }
                                }
                            }
                        }
                    }
                } else {
                    self.isFirstSync = false
                }
                
                // Tracked IDs are now safely managed using bounded FIFO histories. No need to clear them out on every sync loop.
                
                // Initialize WebSocket Realtime task
                self.startRealtimeSync()
            }
        } catch {
            await MainActor.run {
                self.connectionError = true
            }
            print("NetworkService [Refresh Error]: \(error.localizedDescription)")
        }
    }
    
    private func formatISOStringTime(_ isoString: String) -> String {
        let df = ISO8601DateFormatter()
        guard let date = df.date(from: isoString) else { return "" }
        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short
        return timeFormatter.string(from: date)
    }
    
    func fetchTables() async throws -> [RestaurantTable] {
        var dynamicTables: [(String, Int, Int, Double, Double, String, Bool, String)] = []

        do {
            let tablesData = try await sendSupabaseRequest(method: "GET", endpoint: "restaurant_tables", queryItems: [
                URLQueryItem(name: "select", value: "table_number,capacity,floor,position_x,position_y,status,is_round,zone"),
                URLQueryItem(name: "is_deleted", value: "eq.false")
            ])
            let tablesJson = (try? JSONSerialization.jsonObject(with: tablesData) as? [[String: Any]]) ?? []
            dynamicTables = tablesJson.compactMap { dict -> (String, Int, Int, Double, Double, String, Bool, String)? in
                guard let num = dict["table_number"] as? String,
                      let cap = dict["capacity"] as? Int,
                      let floor = dict["floor"] as? Int else { return nil }
                let posX = dict["position_x"] as? Double ?? 0.0
                let posY = dict["position_y"] as? Double ?? 0.0
                let status = dict["status"] as? String ?? "vacant"
                let isRound = dict["is_round"] as? Bool ?? false
                let zone = dict["zone"] as? String ?? "Indoor"
                return (num, cap, floor, posX, posY, status, isRound, zone)
            }
        } catch {
            #if DEBUG
            print("NetworkService [fetchTables Error]: \(error.localizedDescription). Using static fallback.")
            #endif
        }
        
        if dynamicTables.isEmpty {
            dynamicTables = [
                // Floor 1 Tables: Synchronized with AlphaPos (6 tables)
                ("1", 2, 1, 40.0, 40.0, "vacant", false, "Indoor"),
                ("2", 4, 1, 200.0, 40.0, "vacant", false, "Indoor"),
                ("3", 4, 1, 380.0, 40.0, "vacant", false, "Indoor"),
                ("4", 6, 1, 40.0, 200.0, "vacant", false, "Indoor"),
                ("5", 8, 1, 320.0, 200.0, "vacant", false, "Indoor"),
                ("VIP 1", 10, 1, 140.0, 360.0, "vacant", false, "Indoor"),
                // Floor 2 Tables (3 tables)
                ("201", 4, 2, 60.0, 60.0, "vacant", false, "Indoor"),
                ("202", 4, 2, 240.0, 60.0, "vacant", false, "Indoor"),
                ("203", 6, 2, 420.0, 60.0, "vacant", false, "Indoor"),
                // Floor 3 Tables (1 table)
                ("301 (ROOF)", 8, 3, 120.0, 120.0, "vacant", false, "Rooftop")
            ]
        }
        
        let sessionsData = try await sendSupabaseRequest(method: "GET", endpoint: "table_sessions", queryItems: [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "is_active", value: "eq.1")
        ])
        
        let sessions = (try? JSONSerialization.jsonObject(with: sessionsData) as? [[String: Any]]) ?? []
        let activeSessionsMap = Dictionary(sessions.compactMap { dict -> (String, [String: Any])? in
            guard let tableNum = dict["table_number"] as? String else { return nil }
            return (tableNum, dict)
        }, uniquingKeysWith: { (first, second) in
            let firstCreated = first["created_at"] as? String ?? ""
            let secondCreated = second["created_at"] as? String ?? ""
            return firstCreated >= secondCreated ? first : second
        })
        
        let ordersData = try await sendSupabaseRequest(method: "GET", endpoint: "orders", queryItems: [
            URLQueryItem(name: "select", value: "table_number,total,created_at"),
            URLQueryItem(name: "status", value: "neq.cancelled")
        ])
        
        let orders = (try? JSONSerialization.jsonObject(with: ordersData) as? [[String: Any]]) ?? []
        
        var tableTotals: [String: Double] = [:]
        for order in orders {
            guard let tableNum = order["table_number"] as? String,
                  let total = order["total"] as? Double,
                  let createdAtStr = order["created_at"] as? String,
                  let activeSession = activeSessionsMap[tableNum],
                  let sessionStartStr = activeSession["created_at"] as? String else { continue }
            
            if createdAtStr >= sessionStartStr {
                tableTotals[tableNum, default: 0.0] += total
            }
        }
        
        return dynamicTables.map { num, cap, floor, posX, posY, dbStatus, isRound, zoneVal in
            if let session = activeSessionsMap[num] {
                let guestCount = session["guest_count"] as? Int ?? 2
                let token = session["session_token"] as? String
                let total = tableTotals[num] ?? 0.0
                let startedAt = session["started_at"] as? String ?? session["created_at"] as? String
                return RestaurantTable(
                    tableNumber: num,
                    capacity: cap,
                    floor: floor,
                    zone: zoneVal,
                    status: "occupied",
                    guestCount: guestCount,
                    sessionToken: token,
                    isRound: isRound,
                    currentTotal: total,
                    positionX: posX,
                    positionY: posY,
                    sessionStartedAt: startedAt
                )
            } else {
                return RestaurantTable(
                    tableNumber: num,
                    capacity: cap,
                    floor: floor,
                    zone: zoneVal,
                    status: dbStatus,
                    guestCount: 0,
                    sessionToken: nil,
                    isRound: isRound,
                    currentTotal: 0.0,
                    positionX: posX,
                    positionY: posY,
                    sessionStartedAt: nil
                )
            }
        }
    }
    
    func fetchWalls() async throws -> [RestaurantWall] {
        let data = try await sendSupabaseRequest(method: "GET", endpoint: "restaurant_walls", queryItems: [
            URLQueryItem(name: "is_deleted", value: "eq.false")
        ])
        let json = (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
        return json.compactMap { dict -> RestaurantWall? in
            guard let id = dict["id"] as? String,
                  let floor = dict["floor"] as? Int,
                  let typeString = dict["type_string"] as? String,
                  let startX = dict["start_x"] as? Double,
                  let startY = dict["start_y"] as? Double,
                  let endX = dict["end_x"] as? Double,
                  let endY = dict["end_y"] as? Double else { return nil }
            
            let controlX = dict["control_x"] as? Double
            let controlY = dict["control_y"] as? Double
            let strokeWidth = dict["stroke_width"] as? Double ?? 10.0
            let isDeleted = dict["is_deleted"] as? Bool ?? false
            
            return RestaurantWall(
                id: id,
                floor: floor,
                typeString: typeString,
                startX: startX,
                startY: startY,
                endX: endX,
                endY: endY,
                controlX: controlX,
                controlY: controlY,
                strokeWidth: strokeWidth,
                isDeleted: isDeleted
            )
        }
    }
    
    func fetchMerchantSettings() async throws -> (Bool, String, Bool, Bool) {
        let data = try await sendSupabaseRequest(method: "GET", endpoint: "merchants", queryItems: [
            URLQueryItem(name: "select", value: "kitchen_workflow_required,promptpay_number,is_table_system_enabled,is_web_ordering_enabled"),
            URLQueryItem(name: "id", value: "eq.\(activeMerchantId)")
        ])
        if let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
           let firstMerchant = json.first {
            let workflow = firstMerchant["kitchen_workflow_required"] as? Bool ?? true
            let promptPay = firstMerchant["promptpay_number"] as? String ?? ""
            let tableSystem = firstMerchant["is_table_system_enabled"] as? Bool ?? true
            let webOrdering = firstMerchant["is_web_ordering_enabled"] as? Bool ?? true
            return (workflow, promptPay, tableSystem, webOrdering)
        }
        return (true, "", true, true)
    }
    
    func fetchMenu() async throws -> [MenuItem] {
        let data = try await sendSupabaseRequest(method: "GET", endpoint: "menu_items", queryItems: [
            URLQueryItem(name: "select", value: "*")
        ])
        let jsonArray = (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
        return jsonArray.map { dict in
            MenuItem(
                id: dict["id"] as? String ?? "",
                name: dict["name"] as? String ?? "",
                desc: dict["description"] as? String,
                price: dict["price"] as? Double ?? 0.0,
                category: dict["category"] as? String ?? "mains",
                emoji: dict["emoji"] as? String,
                imgClass: dict["img_class"] as? String,
                image_url: dict["image_url"] as? String
            )
        }
    }
    
    func fetchRequests() async throws -> [ServiceRequest] {
        let data = try await sendSupabaseRequest(method: "GET", endpoint: "service_requests", queryItems: [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "order", value: "created_at.desc"),
            URLQueryItem(name: "limit", value: "20")
        ])
        let jsonArray = (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
        return jsonArray.map { dict in
            ServiceRequest(
                id: dict["id"] as? String ?? "",
                tableNumber: dict["table_number"] as? String ?? "",
                requestType: dict["request_type"] as? String ?? "Waiter",
                status: dict["status"] as? String ?? "pending",
                createdAt: dict["created_at"] as? String ?? ""
            )
        }
    }
    
    func fetchEmployees() async throws -> [Employee] {
        let data = try await sendSupabaseRequest(method: "GET", endpoint: "employees", queryItems: [
            URLQueryItem(name: "select", value: "*")
        ])
        let jsonArray = (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
        return jsonArray.map { dict in
            Employee(
                id: dict["id"] as? String ?? "",
                firstName: dict["first_name"] as? String ?? "",
                lastName: dict["last_name"] as? String ?? "",
                phone: dict["phone"] as? String,
                nationalId: dict["national_id"] as? String,
                employmentType: dict["employment_type"] as? String ?? "monthly",
                payRate: dict["pay_rate"] as? Double ?? 0.0,
                username: dict["username"] as? String ?? "",
                role: dict["role"] as? String ?? "Staff",
                pinCode: dict["pin_code"] as? String,
                faceEmbedding: dict["face_embedding"] as? String,
                faceRegisteredAt: dict["face_registered_at"] as? String
            )
        }
    }

    func registerEmployeeFace(employeeId: String, faceEmbedding: String) async throws -> Bool {
        let formatter = ISO8601DateFormatter()
        let nowStr = formatter.string(from: Date())
        let payload: [String: Any] = [
            "face_embedding": faceEmbedding,
            "face_registered_at": nowStr
        ]
        _ = try await sendSupabaseRequest(
            method: "PATCH",
            endpoint: "employees",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(employeeId)")],
            payload: payload
        )
        return true
    }

    private func constantTimeCompare(_ a: String, _ b: String) -> Bool {
        guard a.count == b.count else { return false }
        let aBytes = [UInt8](a.utf8)
        let bBytes = [UInt8](b.utf8)
        var result: UInt8 = 0
        for i in 0..<aBytes.count {
            result |= aBytes[i] ^ bBytes[i]
        }
        return result == 0
    }

    func verifyPin(employeeId: String, pinDigits: String, expectedPinHash: String? = nil) async throws -> Bool {
        // Try new format (iter:salt:hash) first, fall back to legacy SHA256
        func matchesStoredHash(_ stored: String) -> Bool {
            if stored.hasPrefix("iter:") {
                return verifyIteratedPin(pinDigits, against: stored)
            } else {
                // Legacy SHA256-only hash
                let inputData = Data(pinDigits.utf8)
                let hashed = CryptoKit.SHA256.hash(data: inputData)
                let pinHash = hashed.compactMap { String(format: "%02x", $0) }.joined()
                return constantTimeCompare(pinHash, stored)
            }
        }
        
        // 1. Local / pre-loaded verification (Offline fallback)
        if let expected = expectedPinHash {
            return matchesStoredHash(expected)
        }
        
        // 2. Database verification (Direct column query fallback)
        do {
            let data = try await sendSupabaseRequest(method: "GET", endpoint: "employees", queryItems: [
                URLQueryItem(name: "id", value: "eq.\(employeeId)"),
                URLQueryItem(name: "select", value: "pin_code")
            ])
            if let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
               let firstResult = json.first,
               let dbPinCode = firstResult["pin_code"] as? String {
                return matchesStoredHash(dbPinCode)
            }
        } catch {
            print("verifyPin error: \(error.localizedDescription)")
            throw error
        }
        
        return false
    }
    
    /// Verify an iterated hash (format: "iter:<n>:<salt_b64>:<hash_hex>")
    private func verifyIteratedPin(_ pin: String, against storedHash: String) -> Bool {
        let parts = storedHash.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false)
        guard parts.count == 4,
              let iterations = Int(parts[1]) else { return false }
        let salt = String(parts[2])
        let expectedHash = String(parts[3])
        
        var hash = salt + pin
        for _ in 0..<iterations {
            let inputData = Data(hash.utf8)
            let digested = CryptoKit.SHA256.hash(data: inputData)
            hash = digested.compactMap { String(format: "%02x", $0) }.joined()
        }
        return constantTimeCompare(hash, expectedHash)
    }
    
    func fetchTimecards(for employeeId: String) async throws -> [Timecard] {
        let data = try await sendSupabaseRequest(method: "GET", endpoint: "timecards", queryItems: [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "employee_id", value: "eq.\(employeeId)"),
            URLQueryItem(name: "order", value: "clock_in.desc")
        ])
        let jsonArray = (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
        let formatter = ISO8601DateFormatter()
        return jsonArray.map { dict in
            let clockInStr = dict["clock_in"] as? String ?? ""
            let clockInVal = formatter.date(from: clockInStr)?.timeIntervalSince1970 ?? 0.0
            
            let clockOutStr = dict["clock_out"] as? String
            let clockOutVal = clockOutStr.flatMap { formatter.date(from: $0)?.timeIntervalSince1970 }
            
            return Timecard(
                id: dict["id"] as? String ?? "",
                employeeId: dict["employee_id"] as? String ?? "",
                employeeName: dict["employee_name"] as? String ?? "",
                clockIn: clockInVal,
                clockOut: clockOutVal,
                breakDurationMinutes: dict["break_duration"] as? Int ?? 0,
                overtimeMinutes: dict["overtime_minutes"] as? Int ?? 0,
                status: dict["status"] as? String ?? "approved",
                notes: dict["notes"] as? String,
                clockInFaceConfidence: dict["clock_in_confidence"] as? Double,
                clockOutFaceConfidence: dict["clock_out_confidence"] as? Double
            )
        }
    }
    
    func fetchTableOrders(tableNumber: String) async throws -> [Order] {
        // Fetch ALL non-cancelled orders for this table.
        // Do NOT filter by session_token here — orders created from the main POS app
        // (via SyncEngine) may have a different session_token or none at all.
        // Filtering by session_token causes those orders to be silently dropped.
        let ordersData = try await sendSupabaseRequest(method: "GET", endpoint: "orders", queryItems: [
            URLQueryItem(name: "select", value: "*,order_items(*)"),
            URLQueryItem(name: "table_number", value: "eq.\(tableNumber)"),
            URLQueryItem(name: "status", value: "neq.cancelled"),
            URLQueryItem(name: "order", value: "created_at.asc")
        ])
        let ordersArray = (try? JSONSerialization.jsonObject(with: ordersData) as? [[String: Any]]) ?? []
        return parseOrders(ordersArray)
    }
    
    private func parseOrders(_ jsonArray: [[String: Any]]) -> [Order] {
        return jsonArray.map { dict in
            let items = (dict["order_items"] as? [[String: Any]] ?? []).map { itemDict in
                OrderItem(
                    id: itemDict["id"] as? String ?? "",
                    name: itemDict["item_name"] as? String ?? "",
                    quantity: itemDict["quantity"] as? Int ?? 1,
                    price: itemDict["price"] as? Double ?? 0.0,
                    status: itemDict["status"] as? String ?? "cooking",
                    item_id: itemDict["item_id"] as? String,
                    notes: itemDict["notes"] as? String
                )
            }
            return Order(
                id: dict["id"] as? String ?? "",
                orderNumber: dict["order_number"] as? String ?? "",
                tableNumber: dict["table_number"] as? String ?? "",
                total: dict["total"] as? Double ?? 0.0,
                status: dict["status"] as? String ?? "preparing",
                createdAt: dict["created_at"] as? String ?? "",
                items: items,
                sessionToken: dict["session_token"] as? String
            )
        }
    }
    
    func fetchAllActiveOrders() async throws -> [Order] {
        let ordersData = try await sendSupabaseRequest(method: "GET", endpoint: "orders", queryItems: [
            URLQueryItem(name: "select", value: "*,order_items(*)"),
            URLQueryItem(name: "status", value: "in.(preparing,ready,served,completed)"),
            URLQueryItem(name: "order", value: "created_at.desc"),
            URLQueryItem(name: "limit", value: "30")
        ])
        let jsonArray = (try? JSONSerialization.jsonObject(with: ordersData) as? [[String: Any]]) ?? []
        return jsonArray.map { dict in
            let items = (dict["order_items"] as? [[String: Any]] ?? []).map { itemDict in
                OrderItem(
                    id: itemDict["id"] as? String ?? "",
                    name: itemDict["item_name"] as? String ?? "",
                    quantity: itemDict["quantity"] as? Int ?? 1,
                    price: itemDict["price"] as? Double ?? 0.0,
                    status: itemDict["status"] as? String ?? "cooking",
                    item_id: itemDict["item_id"] as? String,
                    notes: itemDict["notes"] as? String
                )
            }
            return Order(
                id: dict["id"] as? String ?? "",
                orderNumber: dict["order_number"] as? String ?? "",
                tableNumber: dict["table_number"] as? String ?? "",
                total: dict["total"] as? Double ?? 0.0,
                status: dict["status"] as? String ?? "preparing",
                createdAt: dict["created_at"] as? String ?? "",
                items: items,
                sessionToken: dict["session_token"] as? String
            )
        }
    }
    
    func fetchOrderById(_ orderId: String) async throws -> Order? {
        let ordersData = try await sendSupabaseRequest(method: "GET", endpoint: "orders", queryItems: [
            URLQueryItem(name: "select", value: "*,order_items(*)"),
            URLQueryItem(name: "id", value: "eq.\(orderId)")
        ])
        let jsonArray = (try? JSONSerialization.jsonObject(with: ordersData) as? [[String: Any]]) ?? []
        guard let dict = jsonArray.first else { return nil }
        
        let items = (dict["order_items"] as? [[String: Any]] ?? []).map { itemDict in
            OrderItem(
                id: itemDict["id"] as? String ?? "",
                name: itemDict["item_name"] as? String ?? "",
                quantity: itemDict["quantity"] as? Int ?? 1,
                price: itemDict["price"] as? Double ?? 0.0,
                status: itemDict["status"] as? String ?? "cooking",
                item_id: itemDict["item_id"] as? String
            )
        }
        return Order(
            id: dict["id"] as? String ?? "",
            orderNumber: dict["order_number"] as? String ?? "",
            tableNumber: dict["table_number"] as? String ?? "",
            total: dict["total"] as? Double ?? 0.0,
            status: dict["status"] as? String ?? "preparing",
            createdAt: dict["created_at"] as? String ?? "",
            items: items,
            sessionToken: dict["session_token"] as? String
        )
    }
    
    // POST triggers
    func openSession(tableNumber: String, guestCount: Int) async throws -> Bool {
        let merchantId = self.activeMerchantId
        let payload: [String: Any] = [
            "id": UUID().uuidString,
            "table_number": tableNumber,
            "session_token": UUID().uuidString,
            "is_active": 1,
            "guest_count": guestCount,
            "created_at": ISO8601DateFormatter().string(from: Date()),
            "merchant_id": merchantId
        ]
        _ = try await sendSupabaseRequest(method: "POST", endpoint: "table_sessions", payload: payload)
        await refreshAll()
        return true
    }
    
    func closeSession(tableNumber: String) async throws -> Bool {
        let endedAtStr = ISO8601DateFormatter().string(from: Date())
        _ = try await sendSupabaseRequest(
            method: "PATCH",
            endpoint: "table_sessions",
            queryItems: [
                URLQueryItem(name: "table_number", value: "eq.\(tableNumber)"),
                URLQueryItem(name: "is_active", value: "eq.1")
            ],
            payload: [
                "is_active": 0,
                "ended_at": endedAtStr
            ]
        )
        await refreshAll()
        return true
    }
    
    func resolveRequest(requestId: String) async throws -> Bool {
        _ = try await sendSupabaseRequest(
            method: "PATCH",
            endpoint: "service_requests",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(requestId)")],
            payload: ["status": "completed"]
        )
        await refreshAll()
        return true
    }
    
    func serveOrder(orderId: String) async throws -> Bool {
        _ = try await sendSupabaseRequest(
            method: "PATCH",
            endpoint: "orders",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(orderId)")],
            payload: ["status": "served"]
        )
        _ = try await sendSupabaseRequest(
            method: "PATCH",
            endpoint: "order_items",
            queryItems: [URLQueryItem(name: "order_id", value: "eq.\(orderId)")],
            payload: ["status": "served"]
        )
        await refreshAll()
        return true
    }
    
    func deleteOrderItem(itemId: String) async throws -> Bool {
        _ = try await sendSupabaseRequest(
            method: "DELETE",
            endpoint: "order_items",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(itemId)")]
        )
        await refreshAll()
        return true
    }

    /// Patch quantity and/or notes for a single order item
    func patchOrderItem(itemId: String, quantity: Int? = nil, notes: String?) async throws -> Bool {
        var payload: [String: Any] = [:]
        if let q = quantity { payload["quantity"] = q }
        if let n = notes    { payload["notes"]    = n } else { payload["notes"] = NSNull() }
        _ = try await sendSupabaseRequest(
            method: "PATCH",
            endpoint: "order_items",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(itemId)")],
            payload: payload
        )
        await refreshAll()
        return true
    }

    func uploadOrder(orderId: String, orderNumber: String, tableNumber: String, total: Double, items: [[String: Any]], sessionToken: String? = nil, guestCount: Int = 2) async throws -> Bool {
        let merchantId = self.activeMerchantId
        var orderPayload: [String: Any] = [
            "id": orderId,
            "order_number": orderNumber,
            "table_number": tableNumber,
            "total": total,
            "status": "preparing",
            "guest_count": guestCount,
            "created_at": ISO8601DateFormatter().string(from: Date()),
            "merchant_id": merchantId
        ]
        if let token = sessionToken, !token.isEmpty {
            orderPayload["session_token"] = token
        }
        _ = try await sendSupabaseRequest(method: "POST", endpoint: "orders", payload: orderPayload)
        
        let orderItems = items.map { item -> [String: Any] in
            return [
                "id": item["id"] as? String ?? UUID().uuidString,
                "order_id": orderId,
                "item_name": item["name"] as? String ?? "",
                "quantity": item["quantity"] as? Int ?? 1,
                "price": item["price"] as? Double ?? 0.0,
                "status": "cooking",
                "item_id": item["itemId"] as? String ?? "",
                "merchant_id": merchantId
            ]
        }
        if !orderItems.isEmpty {
            _ = try await sendSupabaseRequest(method: "POST", endpoint: "order_items", payload: orderItems)
        }
        await refreshAll()
        return true
    }
    
    func uploadPayment(orderId: String, amount: Double, method: String) async throws -> Bool {
        let merchantId = self.activeMerchantId
        let payload: [String: Any] = [
            "id": UUID().uuidString,
            "order_id": orderId,
            "amount": amount,
            "payment_method": method,
            "created_at": ISO8601DateFormatter().string(from: Date()),
            "status": "completed",
            "merchant_id": merchantId
        ]
        _ = try await sendSupabaseRequest(method: "POST", endpoint: "payments", payload: payload)
        return true
    }
    
    func completeCheckout(paymentId: UUID, orderId: String, amount: Double, method: String, tableNumber: String) async throws -> Bool {
        let payload: [String: Any] = [
            "p_payment_id": paymentId.uuidString,
            "p_order_id": orderId,
            "p_amount": amount,
            "p_method": method,
            "p_table_number": tableNumber
        ]
        _ = try await sendSupabaseRequest(method: "POST", endpoint: "rpc/complete_checkout", payload: payload)
        return true
    }

    
    func uploadTimecard(timecard: Timecard) async throws -> Bool {
        let merchantId = self.activeMerchantId
        let formatter = ISO8601DateFormatter()
        let clockInStr = formatter.string(from: Date(timeIntervalSince1970: timecard.clockIn))
        
        var payload: [String: Any] = [
            "id": timecard.id,
            "employee_id": timecard.employeeId,
            "employee_name": timecard.employeeName,
            "clock_in": clockInStr,
            "break_duration": timecard.breakDurationMinutes,
            "overtime_minutes": timecard.overtimeMinutes,
            "status": timecard.status,
            "notes": timecard.notes ?? "",
            "clock_in_confidence": timecard.clockInFaceConfidence ?? 0.0,
            "clock_out_confidence": timecard.clockOutFaceConfidence ?? 0.0,
            "merchant_id": merchantId
        ]
        
        if let clockOut = timecard.clockOut, clockOut > 0 {
            payload["clock_out"] = formatter.string(from: Date(timeIntervalSince1970: clockOut))
        } else {
            payload["clock_out"] = NSNull()
        }
        
        _ = try await sendSupabaseRequest(method: "POST", endpoint: "timecards", payload: payload)
        return true
    }
    
    // MARK: - Supabase Realtime WebSocket Client
    
    private var webSocketTask: URLSessionWebSocketTask?
    
    // Reconnection: Exponential backoff state
    @ObservationIgnored
    private var reconnectAttempt: Int = 0
    @ObservationIgnored
    private let maxReconnectDelay: TimeInterval = 30.0
    
    // Debounce: Prevent rapid-fire refreshAll from multiple Realtime events
    @ObservationIgnored
    private var realtimeRefreshTask: Task<Void, Never>?
    
    @ObservationIgnored
    private var realtimeDebounceWorkItem: DispatchWorkItem?
    
    // Heartbeat: Store timer reference to prevent leak on reconnect
    @ObservationIgnored
    private var heartbeatTimer: Timer?
    @ObservationIgnored
    private var pollingTimer: Timer?
    
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
                        ["event": "*", "schema": "public", "table": "service_requests", "filter": "merchant_id=eq.\(merchantId)"],
                        ["event": "*", "schema": "public", "table": "restaurant_tables", "filter": "merchant_id=eq.\(merchantId)"],
                        ["event": "*", "schema": "public", "table": "restaurant_walls", "filter": "merchant_id=eq.\(merchantId)"],
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
                                    let title = statusLower == "ready" ? "🍳 Order \(orderNumber) Ready!" : "📝 New Order \(orderNumber)"
                                    let body = "Table \(tableNumber)"
                                    NotificationManager.shared.notify(title: title, body: body, type: .order, deduplicationKey: notificationKey, userInfo: ["table_number": tableNumber, "type": "order", "order_id": id])
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
                            if let fetchedOrder = try await NetworkService.shared.fetchOrderById(id) {
                                await MainActor.run {
                                    if let idx = self.orders.firstIndex(where: { $0.id == fetchedOrder.id }) {
                                        self.orders[idx] = fetchedOrder
                                    } else {
                                        self.orders.insert(fetchedOrder, at: 0)
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
            } else if table == "restaurant_walls" {
                Task {
                    if let fetchedWalls = try? await self.fetchWalls() {
                        await MainActor.run {
                            self.walls = fetchedWalls
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
    
    func clearCache() {
        self.tables = []
        self.menuItems = []
        self.serviceRequests = []
        self.orders = []
    }
    
    func wipeRemoteTransactionsAndSessions() async throws -> Bool {
        let merchantId = self.activeMerchantId
        guard !merchantId.isEmpty else {
            throw NetworkError.serverError("No active merchant configured")
        }
        let merchantFilter = URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)")
        // 1. Delete all table sessions for this merchant
        _ = try await sendSupabaseRequest(method: "DELETE", endpoint: "table_sessions", queryItems: [merchantFilter])
        // 2. Delete all orders (cascade deletes order_items and payments)
        _ = try await sendSupabaseRequest(method: "DELETE", endpoint: "orders", queryItems: [merchantFilter])
        // 3. Delete all service requests
        _ = try await sendSupabaseRequest(method: "DELETE", endpoint: "service_requests", queryItems: [merchantFilter])
        // 4. Reset all restaurant tables status to vacant
        _ = try await sendSupabaseRequest(method: "PATCH", endpoint: "restaurant_tables", queryItems: [merchantFilter], payload: ["status": "vacant"])
        return true
    }
}

// Helper Math
struct Math {
    static func randomString(length: Int) -> String {
        let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<length).map{ _ in letters.randomElement()! })
    }
}
