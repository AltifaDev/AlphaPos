// NetworkService+Core.swift
// Core of the central network layer: class definition, stored properties,
// HTTP client (sendSupabaseRequest), lifecycle observers, push registration,
// connection check, and the refreshAll sync pipeline.
//
// Implementation is split across extension files:
//   NetworkService+Chat.swift, +Orders.swift, +Tables.swift, +Timecard.swift,
//   +Breaks.swift, +Shifts.swift, +MenuTips.swift, +Realtime.swift

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
    var anonKey: String { AppConfig.supabaseAnonKey }
    
    @ObservationIgnored
    lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        return URLSession(configuration: config)
    }()
    
    // Global lists
    var tables: [RestaurantTable] = []

    var menuItems: [MenuItem] = []
    var serviceRequests: [ServiceRequest] = []
    var orders: [Order] = []
    var floorPlanImages: [FloorPlanImageStaff] = []
    
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
    var notifiedRequestIds = Set<String>()
    @ObservationIgnored
    private var notifiedRequestKeysHistory: [String] = []
    @ObservationIgnored
    var notifiedOrderIds = Set<String>()
    @ObservationIgnored
    private var notifiedOrderKeysHistory: [String] = []
    @ObservationIgnored
    var notifiedTableStatuses: [String: String] = [:]
    
    func markOrderAsNotified(key: String) {
        if !self.notifiedOrderIds.contains(key) {
            self.notifiedOrderIds.insert(key)
            self.notifiedOrderKeysHistory.append(key)
            if self.notifiedOrderKeysHistory.count > 300 {
                let oldest = self.notifiedOrderKeysHistory.removeFirst()
                self.notifiedOrderIds.remove(oldest)
            }
        }
    }
    
    func markRequestAsNotified(requestId: String) {
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
    
    var activeMerchantId: String {
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
    func sendSupabaseRequest(method: String, endpoint: String, queryItems: [URLQueryItem]? = nil, payload: Any? = nil) async throws -> Data {
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
        
        // Add x-merchant-id header so RLS get_active_merchant_id() functions can evaluate correctly
        // when the JWT token does not explicitly contain the merchant_id claim (like anonKey).
        let merchantId = activeMerchantId.isEmpty ? AppConfig.defaultMerchantId : activeMerchantId
        request.setValue(merchantId, forHTTPHeaderField: "x-merchant-id")
        
        // Joined queries (select with nested relations like order_items(*)) can be
        // slower than simple selects — 15 s gives enough headroom on slow WiFi/3G
        // while still catching genuine outages within a reasonable window.
        request.timeoutInterval = 15.0
        
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
            if errorMsg.contains("PGRST301") {
                #if DEBUG
                print("NetworkService: Detected JWT decryption error (PGRST301). Clearing token...")
                #endif
                MerchantAuthManager.shared.logout()
            }
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
                } else if let cached = await OfflineCache.shared.loadCachedMenu() {
                    // Offline fallback: load from cache
                    await MainActor.run {
                        self.menuItems = cached
                    }
                }
            }
            
            // Perform concurrent requests to Supabase
            async let fetchedTables = fetchTables()
            async let fetchedRequests = fetchRequests()
            async let fetchedOrders = fetchAllActiveOrders()
            async let fetchedWorkflow = fetchMerchantSettings()
            async let fetchedFloorPlans = fetchFloorPlanImages()
            
            // Await all concurrent fetches (orders first for notification priority)
            let ordersRes = try await fetchedOrders
            let (tablesRes, requestsRes, floorPlansRes) = try await (fetchedTables, fetchedRequests, fetchedFloorPlans)
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
                // Cache tables and orders for offline use
                OfflineCache.shared.cacheTables(tablesRes)
                OfflineCache.shared.cacheOrders(ordersRes)

                if self.floorPlanImages != floorPlansRes {
                    self.floorPlanImages = floorPlansRes
                }
                if self.serviceRequests != requestsRes {
                    self.serviceRequests = requestsRes
                }
                if self.orders != ordersRes {
                    self.orders = ordersRes
                }
                self.connectionError = false
                // NWPathMonitor owns isOffline — don't override it here
                
                // Sync offline queue if we just came back online
                if OfflineCache.shared.queuedOrderCount > 0 {
                    Task {
                        let synced = await OfflineCache.shared.syncOfflineQueue()
                        if synced > 0 {
                            #if DEBUG
                            print("[NetworkService] Synced \(synced) offline queued orders")
                            #endif
                        }
                    }
                }
                
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
                // NWPathMonitor owns isOffline — connectionError is the authoritative flag for UI
                
                // Offline fallback: load cached data
                if self.tables.isEmpty, let cachedTables = OfflineCache.shared.loadCachedTables() {
                    self.tables = cachedTables
                }
                if self.menuItems.isEmpty, let cachedMenu = OfflineCache.shared.loadCachedMenu() {
                    self.menuItems = cachedMenu
                }
                if self.orders.isEmpty, let cachedOrders = OfflineCache.shared.loadCachedOrders() {
                    self.orders = cachedOrders
                }
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
    
    // MARK: - Supabase Realtime WebSocket Client
    
    var webSocketTask: URLSessionWebSocketTask?
    
    // Reconnection: Exponential backoff state
    @ObservationIgnored
    var reconnectAttempt: Int = 0
    @ObservationIgnored
    let maxReconnectDelay: TimeInterval = 30.0
    
    // Debounce: Prevent rapid-fire refreshAll from multiple Realtime events
    @ObservationIgnored
    var realtimeRefreshTask: Task<Void, Never>?
    
    @ObservationIgnored
    var realtimeDebounceWorkItem: DispatchWorkItem?
    
    // Heartbeat: Store timer reference to prevent leak on reconnect
    @ObservationIgnored
    var heartbeatTimer: Timer?
    @ObservationIgnored
    var pollingTimer: Timer?
    
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
        // 5. Delete all floor plan images
        _ = try await sendSupabaseRequest(method: "DELETE", endpoint: "floor_plan_images", queryItems: [merchantFilter])
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
