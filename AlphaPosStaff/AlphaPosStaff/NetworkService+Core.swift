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
import OSLog

enum NetworkError: Error, LocalizedError {
    case offline
    case serverError(String)
    case invalidResponse
    case conflict(String)
    var errorDescription: String? {
        switch self {
        case .offline: return "No internet connection detected."
        case .serverError(let msg): return "Server returned error: \(msg)"
        case .invalidResponse: return "Received invalid response from server."
        case .conflict(let msg): return "Sync conflict: \(msg)"
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
    private static let performanceLogger = Logger(subsystem: "com.alphapos.staff", category: "NetworkPerformance")

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
    var diningAreas: [DiningAreaStaff] = []

    var menuItems: [MenuItem] = []
    var serviceRequests: [ServiceRequest] = []
    var orders: [Order] = []
    var floorPlanImages: [FloorPlanImageStaff] = []
    var unreadChatCount = 0
    
    var activeAlertsCount: Int {
        let pendingRequests = serviceRequests.filter {
            $0.status == "pending"
                && StaffNotificationPolicy.isCurrentBusinessDay(timestamp: $0.createdAt)
        }.count
        let activeOrders = orders.filter {
            StaffNotificationPolicy.isCurrentBusinessDay(timestamp: $0.createdAt)
                && ($0.isAwaitingStaffApproval
                    || ["preparing", "cooking", "ready"].contains($0.status.lowercased()))
        }.count
        return pendingRequests + activeOrders
    }
    
    // Status states
    var isFetching = false
    var connectionError = false
    
    /// Convenience computed property: true when connected to backend
    var isOnline: Bool { !connectionError }
    var isRealtimeConnected: Bool { realtimeJoinSucceeded }
    var lastSyncDisplayDate: Date? { lastSuccessfulSyncAt }
    var kitchenWorkflowRequired = true
    var promptPayNumber = ""
    var isTableSystemEnabled = true
    var isWebOrderingEnabled = true
    var merchantName = ""
    var merchantPhone = ""
    var merchantAddress = ""
    var merchantTaxId = ""
    var merchantReceiptHeader = ""
    var merchantReceiptFooter = ""
    var taxRate: Double = 0.0
    var taxType = "inclusive"
    var serviceChargeRate: Double = 0.0
    var currency = "THB"
    var currencySymbol = "฿"
    private var lastSyncTime: Date = Date(timeIntervalSince1970: 0)
    private var lastSuccessfulSyncAt: Date?
    
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
    @ObservationIgnored
    var realtimeJoinSucceeded = false
    
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
    private static let debugLogQueue = DispatchQueue(label: "com.alphapos.staff.debug-log", qos: .utility)
    
    private func writeDebugLog(_ message: String) {
        #if DEBUG
        Self.debugLogQueue.async {
            guard let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
            let logURL = docsURL.appendingPathComponent("debug_sync.log")
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            let line = "[\(formatter.string(from: Date()))] \(message)\n"
            guard let data = line.data(using: .utf8) else { return }
            if FileManager.default.fileExists(atPath: logURL.path) {
                if let fileHandle = try? FileHandle(forWritingTo: logURL) {
                    try? fileHandle.seekToEnd()
                    try? fileHandle.write(contentsOf: data)
                    try? fileHandle.close()
                }
            } else {
                try? line.write(to: logURL, atomically: true, encoding: .utf8)
            }
        }
        #endif
    }
    
    @ObservationIgnored
    private var activeSyncTask: Task<Void, Never>?
    
    var activeMerchantId: String {
        (UserDefaults.standard.string(forKey: "active_merchant_id") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    var authorizationToken: String {
        let auth = MerchantAuthManager.shared
        guard auth.isAuthenticated,
              auth.merchantId?.lowercased() == activeMerchantId,
              let token = auth.currentToken else { return anonKey }
        return token
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
            self.realtimeJoinSucceeded = false
            self.heartbeatTimer?.invalidate()
            self.heartbeatTimer = nil
            self.pollingTimer?.invalidate()
            self.pollingTimer = nil
            // Reset reconnect backoff so foreground gets immediate reconnect
            self.reconnectAttempt = 0

            // Reconnect WebSocket and sync REST data
            self.startRealtimeSync()
            Task {
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
            self.realtimeJoinSucceeded = false
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
            self.realtimeJoinSucceeded = false
            self.heartbeatTimer?.invalidate()
            self.heartbeatTimer = nil
            self.startRealtimeSync()
            Task { try? await self.upsertPushDevice() }
        }
    }
    
    // Ping/Check connection to Supabase menu_items REST endpoint
    func checkConnection() async -> Bool {
        var req = URLRequest(url: baseURL.appendingPathComponent("menu_items"))
        req.httpMethod = "HEAD"
        // Use merchant JWT if available, fall back to anon key
        let token = authorizationToken
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
    func sendSupabaseRequest(method: String, endpoint: String, queryItems: [URLQueryItem]? = nil, payload: Any? = nil, timeoutInterval: TimeInterval = 15.0) async throws -> Data {
        let requestStartedAt = Date()
        let requestId = UUID().uuidString.lowercased()
        let auth = MerchantAuthManager.shared
        let tokenRefreshStartedAt = Date()
        await auth.refreshTokenIfNeeded()
        let tokenRefreshMilliseconds = Int(Date().timeIntervalSince(tokenRefreshStartedAt) * 1_000)
        if endpoint == "rpc/verify_staff_pin" {
            Self.performanceLogger.info("staff_auth token_refresh_ms=\(tokenRefreshMilliseconds, privacy: .public) request_id=\(requestId, privacy: .public)")
        }
        guard auth.isAuthenticated,
              auth.merchantId?.lowercased() == activeMerchantId else {
            throw AuthError.tokenExpired
        }

        var scopedQueryItems = queryItems ?? []
        let branchScopedTables: Set<String> = [
            "orders", "order_items", "payments", "restaurant_tables", "table_sessions",
            "service_requests", "employees", "employee_shifts", "employee_breaks",
            "chat_channels", "chat_messages", "checkout_operations", "timecards",
            "tips", "floor_plan_images", "dining_areas", "table_layout_presets"
        ]
        if method != "POST",
           branchScopedTables.contains(endpoint),
           !StaffSessionContext.branchId.isEmpty,
           !scopedQueryItems.contains(where: { $0.name == "branch_id" }) {
            scopedQueryItems.append(URLQueryItem(name: "branch_id", value: "eq.\(StaffSessionContext.branchId)"))
        }

        var url = baseURL.appendingPathComponent(endpoint)
        if !scopedQueryItems.isEmpty, var components = URLComponents(url: url, resolvingAgainstBaseURL: true) {
            components.queryItems = scopedQueryItems
            if let newUrl = components.url {
                url = newUrl
            }
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        // Use merchant JWT if available — the JWT contains a `merchant_id` claim
        // that PostgREST extracts via `current_setting('request.jwt.claims')`,
        // enabling RLS policies to isolate data per merchant automatically.
        let token = authorizationToken
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(requestId, forHTTPHeaderField: "x-request-id")
        request.setValue("AlphaPosStaff/1 order-contract/1", forHTTPHeaderField: "x-client-info")
        
        // Add x-merchant-id header so RLS get_active_merchant_id() functions can evaluate correctly
        // when the JWT token does not explicitly contain the merchant_id claim (like anonKey).
        if !activeMerchantId.isEmpty {
            request.setValue(activeMerchantId, forHTTPHeaderField: "x-merchant-id")
        }
        
        // Joined queries (select with nested relations like order_items(*)) can be
        // slower than simple selects — 15 s gives enough headroom on slow WiFi/3G
        // while still catching genuine outages within a reasonable window.
        request.timeoutInterval = timeoutInterval
        
        // Enable upsert for POST with on_conflict parameter
        if method == "POST" {
            request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        } else if method == "PATCH" {
            request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        }
        
        if let payload = payload {
            let jsonData = try JSONSerialization.data(withJSONObject: payload)
            request.httpBody = jsonData
        }
        
        var (data, response) = try await dataWithTransientRetry(for: request)
        if let http = response as? HTTPURLResponse,
           http.statusCode == 401 || http.statusCode == 403 {
            let forcedRefreshStartedAt = Date()
            await MerchantAuthManager.shared.refreshTokenIfNeeded(force: true)
            if endpoint == "rpc/verify_staff_pin" {
                let forcedRefreshMilliseconds = Int(Date().timeIntervalSince(forcedRefreshStartedAt) * 1_000)
                Self.performanceLogger.info("staff_auth forced_token_refresh_ms=\(forcedRefreshMilliseconds, privacy: .public) request_id=\(requestId, privacy: .public)")
            }
            if MerchantAuthManager.shared.isAuthenticated {
                request.setValue("Bearer \(authorizationToken)", forHTTPHeaderField: "Authorization")
                (data, response) = try await dataWithTransientRetry(for: request)
            }
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            NetworkDiagnostics.shared.record(NetworkDiagnosticEvent(
                id: UUID(), requestId: requestId, method: method, endpoint: endpoint,
                statusCode: nil, durationMilliseconds: Int(Date().timeIntervalSince(requestStartedAt) * 1_000),
                occurredAt: Date(), error: "Invalid HTTP response", retryable: true
            ))
            throw NetworkError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP Request failed"
            let structuredError = StaffHTTPError(
                statusCode: httpResponse.statusCode,
                requestId: requestId,
                endpoint: endpoint,
                serverMessage: message
            )
            NetworkDiagnostics.shared.record(NetworkDiagnosticEvent(
                id: UUID(), requestId: requestId, method: method, endpoint: endpoint,
                statusCode: httpResponse.statusCode,
                durationMilliseconds: Int(Date().timeIntervalSince(requestStartedAt) * 1_000),
                occurredAt: Date(), error: structuredError.localizedDescription, retryable: structuredError.isRetryable
            ))
            throw structuredError
        }

        NetworkDiagnostics.shared.record(NetworkDiagnosticEvent(
            id: UUID(), requestId: requestId, method: method, endpoint: endpoint,
            statusCode: httpResponse.statusCode,
            durationMilliseconds: Int(Date().timeIntervalSince(requestStartedAt) * 1_000),
            occurredAt: Date(), error: nil, retryable: false
        ))
        return data
    }

    /// Retry only safe reads and only transient transport/server failures.
    /// HTTP 400/401/403/409 are contract/auth/conflict outcomes and are never
    /// repeated blindly. The same request ID is retained across attempts.
    private func dataWithTransientRetry(for request: URLRequest) async throws -> (Data, URLResponse) {
        let safeToRetry = request.httpMethod == "GET"
        let maximumAttempts = safeToRetry ? 3 : 1
        var attempt = 1
        while true {
            do {
                let result = try await session.data(for: request)
                if let response = result.1 as? HTTPURLResponse,
                   safeToRetry,
                   attempt < maximumAttempts,
                   response.statusCode == 408 || response.statusCode == 429 || response.statusCode >= 500 {
                    let delay = UInt64(250 * (1 << (attempt - 1)) + Int.random(in: 0...150))
                    try await Task.sleep(nanoseconds: delay * 1_000_000)
                    attempt += 1
                    continue
                }
                return result
            } catch {
                guard safeToRetry, attempt < maximumAttempts else { throw error }
                let delay = UInt64(250 * (1 << (attempt - 1)) + Int.random(in: 0...150))
                try await Task.sleep(nanoseconds: delay * 1_000_000)
                attempt += 1
            }
        }
    }

    /// Shared hub health (same RPC as POS SyncHealthView + web /v1/sync/status).
    func fetchSyncHealth() async throws -> [String: Any] {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id")
            ?? UserDefaults.standard.string(forKey: "merchant_id")
            ?? ""
        var payload: [String: Any] = [:]
        if !merchantId.isEmpty {
            payload["p_merchant_id"] = merchantId.lowercased()
        }
        let data = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "rpc/get_sync_health",
            payload: payload
        )
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let ok = obj["ok"] as? Bool, ok == false {
                let message = (obj["error"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                throw NetworkError.serverError(message?.isEmpty == false ? message! : "get_sync_health failed")
            }
            return obj
        }
        throw NetworkError.invalidResponse
    }
    
    func refreshAll() async {
        if !MerchantAuthManager.shared.isAuthenticated {
            await MerchantAuthManager.shared.refreshTokenIfNeeded()
            guard MerchantAuthManager.shared.isAuthenticated else { return }
        }

        if let existingTask = activeSyncTask {
            await existingTask.value
            return
        }
        
        // Do not pin networking, JSON parsing, diffing, and cache preparation to
        // the UI executor. UI state is committed in the MainActor block below.
        let task = Task {
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
            async let fetchedDiningAreas = fetchDiningAreas()
            async let fetchedRequests = fetchRequests()
            async let fetchedOrders = fetchAllActiveOrders()
            async let fetchedWorkflow = fetchMerchantSettings()
            async let fetchedFloorPlans = fetchFloorPlanImages()
            async let fetchedUnreadChat = fetchTotalUnreadChatCount()
            
            // Tables are the critical path for online/offline state. Optional
            // endpoints keep their last known value so one slow feature does not
            // make the whole table screen look offline.
            let tablesRes = try await fetchedTables
            let diningAreasRes = (try? await fetchedDiningAreas) ?? self.diningAreas
            let ordersRes = (try? await fetchedOrders) ?? self.orders
            let requestsRes = (try? await fetchedRequests) ?? self.serviceRequests
            let floorPlansRes = (try? await fetchedFloorPlans) ?? self.floorPlanImages
            _ = await fetchedUnreadChat
            let settingsRes = (try? await fetchedWorkflow) ?? MerchantSettingsPayload()
            
            await MainActor.run {
                self.kitchenWorkflowRequired = settingsRes.kitchenWorkflowRequired
                self.promptPayNumber = settingsRes.promptPayNumber
                self.isTableSystemEnabled = settingsRes.isTableSystemEnabled
                self.isWebOrderingEnabled = settingsRes.isWebOrderingEnabled
                self.merchantName = settingsRes.merchantName
                self.merchantPhone = settingsRes.phone
                self.merchantAddress = settingsRes.address
                self.merchantTaxId = settingsRes.taxId
                self.merchantReceiptHeader = settingsRes.receiptHeader
                self.merchantReceiptFooter = settingsRes.receiptFooter
                self.taxRate = settingsRes.taxRate
                self.taxType = settingsRes.taxType
                self.serviceChargeRate = settingsRes.serviceChargeRate
                self.currency = settingsRes.currency
                self.currencySymbol = (settingsRes.currency == "THB" || settingsRes.currency.isEmpty) ? "฿" : settingsRes.currency
                let oldTables = self.tables
                let oldRequests = self.serviceRequests
                let oldOrders = self.orders
                
                self.writeDebugLog("--- performRefreshAll sync block ---")
                self.writeDebugLog("isFirstSync: \(self.isFirstSync)")
                self.writeDebugLog("oldOrders count: \(oldOrders.count), ordersRes count: \(ordersRes.count)")
                
                if self.tables != tablesRes {
                    self.tables = tablesRes
                }
                if self.diningAreas != diningAreasRes {
                    self.diningAreas = diningAreasRes
                }
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
                self.lastSuccessfulSyncAt = Date()
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
                        let oldPendingIds = Set(oldRequests.filter {
                            $0.status == "pending"
                                && StaffNotificationPolicy.isCurrentBusinessDay(timestamp: $0.createdAt)
                        }.map { $0.id })
                        let newPendingRequests = requestsRes.filter {
                            $0.status == "pending"
                                && StaffNotificationPolicy.isCurrentBusinessDay(timestamp: $0.createdAt)
                        }
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
                                if order.isAwaitingStaffApproval || statusLower == "preparing" || statusLower == "ready" {
                                    let notificationKey = "\(order.id)-\(statusLower)-\(order.orderSource)"
                                    if !self.notifiedOrderIds.contains(notificationKey) {
                                        self.writeDebugLog("Triggering new/preparing notification for order \(order.orderNumber)")
                                        self.markOrderAsNotified(key: notificationKey)
                                        let itemsSummary = order.items.map { "\($0.quantity)x \($0.name)" }.joined(separator: ", ")
                                        let title = order.isAwaitingStaffApproval
                                            ? "🌐 Web Order \(order.orderNumber) — อนุมัติด่วน!"
                                            : (statusLower == "ready" ? "🍳 Order \(order.orderNumber) Ready!" : "📝 New Order \(order.orderNumber)")
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

            // OfflineCache schedules encoding and disk I/O on a utility queue.
            await OfflineCache.shared.cacheTables(tablesRes)
            await OfflineCache.shared.cacheOrders(ordersRes)
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
