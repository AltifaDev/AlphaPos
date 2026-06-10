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
    var menuItems: [MenuItem] = []
    var serviceRequests: [ServiceRequest] = []
    var orders: [Order] = []
    
    // Status states
    var isFetching = false
    var connectionError = false
    var kitchenWorkflowRequired = true
    
    @ObservationIgnored
    private var _isCurrentlySyncing = false
    private let syncLock = NSLock()
    private var isCurrentlySyncing: Bool {
        get { syncLock.lock(); defer { syncLock.unlock() }; return _isCurrentlySyncing }
        set { syncLock.lock(); defer { syncLock.unlock() }; _isCurrentlySyncing = newValue }
    }
    
    private var isFirstSync = true
    
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
                await self.refreshAll()
            }
        }
    }
    
    // Ping/Check connection to Supabase menu_items REST endpoint
    func checkConnection() async -> Bool {
        var req = URLRequest(url: baseURL.appendingPathComponent("menu_items"))
        req.httpMethod = "HEAD"
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
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
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Dynamic merchant scoping
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? AppConfig.defaultMerchantId
        request.setValue(merchantId, forHTTPHeaderField: "x-merchant-id")
        
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
            
            let (tablesRes, requestsRes, ordersRes) = try await (fetchedTables, fetchedRequests, fetchedOrders)
            let workflowRes = (try? await fetchedWorkflow) ?? true
            
            await MainActor.run {
                self.kitchenWorkflowRequired = workflowRes
                let oldTables = self.tables
                let oldRequests = self.serviceRequests
                let oldOrders = self.orders
                
                if self.tables != tablesRes {
                    self.tables = tablesRes
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
                    // 1. Service Requests Diff
                    let oldPendingIds = Set(oldRequests.filter { $0.status == "pending" }.map { $0.id })
                    let newPendingRequests = requestsRes.filter { $0.status == "pending" }
                    for req in newPendingRequests {
                        if !oldPendingIds.contains(req.id) {
                            NotificationManager.shared.triggerNotification(
                                title: "🔔 Table \(req.tableNumber): \(req.requestType)",
                                body: "Customer requested assistance at \(self.formatISOStringTime(req.createdAt))"
                            )
                        }
                    }
                    
                    // 2. Table Status Diff
                    for table in tablesRes {
                        if let oldTable = oldTables.first(where: { $0.tableNumber == table.tableNumber }) {
                            if oldTable.status != table.status {
                                if table.status == "occupied" {
                                    NotificationManager.shared.triggerNotification(
                                        title: "🚪 Table \(table.tableNumber) Occupied",
                                        body: "Session started for \(table.guestCount) guests"
                                    )
                                } else if table.status == "vacant" && oldTable.status == "occupied" {
                                    NotificationManager.shared.triggerNotification(
                                        title: "💳 Table \(table.tableNumber) Vacant",
                                        body: "Session ended / table cleared"
                                    )
                                }
                            }
                        }
                    }
                    
                    // 3. Order Status Diff
                    for order in ordersRes {
                        if let oldOrder = oldOrders.first(where: { $0.id == order.id }) {
                            if oldOrder.status != order.status {
                                if order.status.lowercased() == "ready" {
                                    let itemsSummary = order.items.map { "\($0.quantity)x \($0.name)" }.joined(separator: ", ")
                                    NotificationManager.shared.triggerNotification(
                                        title: "🍳 Order \(order.orderNumber) Ready!",
                                        body: "Table \(order.tableNumber): \(itemsSummary)"
                                    )
                                }
                            }
                        } else {
                            if order.status.lowercased() == "preparing" || order.status.lowercased() == "ready" {
                                let itemsSummary = order.items.map { "\($0.quantity)x \($0.name)" }.joined(separator: ", ")
                                NotificationManager.shared.triggerNotification(
                                    title: "📝 New Order \(order.orderNumber)",
                                    body: "Table \(order.tableNumber): \(itemsSummary) (Total: ฿\(Int(order.total)))"
                                )
                            }
                        }
                    }
                } else {
                    self.isFirstSync = false
                }
                
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
        var dynamicTables: [(String, Int, Int, Double, Double, String)] = []
        
        do {
            let tablesData = try await sendSupabaseRequest(method: "GET", endpoint: "restaurant_tables", queryItems: [
                URLQueryItem(name: "select", value: "table_number,capacity,floor,position_x,position_y,status"),
                URLQueryItem(name: "is_deleted", value: "eq.false")
            ])
            let tablesJson = (try? JSONSerialization.jsonObject(with: tablesData) as? [[String: Any]]) ?? []
            dynamicTables = tablesJson.compactMap { dict -> (String, Int, Int, Double, Double, String)? in
                guard let num = dict["table_number"] as? String,
                      let cap = dict["capacity"] as? Int,
                      let floor = dict["floor"] as? Int else { return nil }
                let posX = dict["position_x"] as? Double ?? 0.0
                let posY = dict["position_y"] as? Double ?? 0.0
                let status = dict["status"] as? String ?? "vacant"
                return (num, cap, floor, posX, posY, status)
            }
        } catch {
            #if DEBUG
            print("NetworkService [fetchTables Error]: \(error.localizedDescription). Using static fallback.")
            #endif
        }
        
        if dynamicTables.isEmpty {
            dynamicTables = [
                ("1", 2, 1, 40.0, 40.0, "vacant"),
                ("2", 4, 1, 200.0, 40.0, "vacant"),
                ("3", 4, 1, 380.0, 40.0, "vacant"),
                ("4", 6, 1, 40.0, 200.0, "vacant"),
                ("5", 8, 1, 320.0, 200.0, "vacant"),
                ("VIP 1", 10, 1, 140.0, 360.0, "vacant"),
                ("201", 4, 2, 60.0, 60.0, "vacant"),
                ("202", 4, 2, 240.0, 60.0, "vacant"),
                ("203", 6, 2, 420.0, 60.0, "vacant"),
                ("301 (ROOF)", 8, 3, 120.0, 120.0, "vacant")
            ]
        }
        
        let sessionsData = try await sendSupabaseRequest(method: "GET", endpoint: "table_sessions", queryItems: [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "is_active", value: "eq.1")
        ])
        
        let sessions = (try? JSONSerialization.jsonObject(with: sessionsData) as? [[String: Any]]) ?? []
        let activeSessionsMap = Dictionary(uniqueKeysWithValues: sessions.compactMap { dict -> (String, [String: Any])? in
            guard let tableNum = dict["table_number"] as? String else { return nil }
            return (tableNum, dict)
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
        
        return dynamicTables.map { num, cap, floor, posX, posY, dbStatus in
            if let session = activeSessionsMap[num] {
                let guestCount = session["guest_count"] as? Int ?? 1
                let token = session["session_token"] as? String
                let total = tableTotals[num] ?? 0.0
                return RestaurantTable(
                    tableNumber: num,
                    capacity: cap,
                    floor: floor,
                    status: "occupied",
                    guestCount: guestCount,
                    sessionToken: token,
                    currentTotal: total,
                    positionX: posX,
                    positionY: posY
                )
            } else {
                return RestaurantTable(
                    tableNumber: num,
                    capacity: cap,
                    floor: floor,
                    status: dbStatus,
                    guestCount: 0,
                    sessionToken: nil,
                    currentTotal: 0.0,
                    positionX: posX,
                    positionY: posY
                )
            }
        }
    }
    
    func fetchMerchantSettings() async throws -> Bool {
        let data = try await sendSupabaseRequest(method: "GET", endpoint: "merchants", queryItems: [
            URLQueryItem(name: "select", value: "kitchen_workflow_required")
        ])
        if let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
           let firstMerchant = json.first {
            return firstMerchant["kitchen_workflow_required"] as? Bool ?? true
        }
        return true
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
            URLQueryItem(name: "status", value: "eq.pending"),
            URLQueryItem(name: "order", value: "created_at.desc")
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
                pinCode: dict["pin_code"] as? String
            )
        }
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
        let inputData = Data(pinDigits.utf8)
        let hashed = CryptoKit.SHA256.hash(data: inputData)
        let pinHash = hashed.compactMap { String(format: "%02x", $0) }.joined()
        
        // 1. Local / pre-loaded verification (Offline fallback)
        if let expected = expectedPinHash {
            return constantTimeCompare(pinHash, expected) || constantTimeCompare(pinDigits, expected)
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
                return constantTimeCompare(pinHash, dbPinCode) || constantTimeCompare(pinDigits, dbPinCode)
            }
        } catch {
            print("verifyPin error: \(error.localizedDescription)")
            throw error
        }
        
        return false
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
    
    func fetchTableOrders(tableNumber: String, sessionToken: String) async throws -> [Order] {
        let sessionData = try await sendSupabaseRequest(method: "GET", endpoint: "table_sessions", queryItems: [
            URLQueryItem(name: "select", value: "created_at"),
            URLQueryItem(name: "table_number", value: "eq.\(tableNumber)"),
            URLQueryItem(name: "session_token", value: "eq.\(sessionToken)"),
            URLQueryItem(name: "is_active", value: "eq.1")
        ])
        let sessions = (try? JSONSerialization.jsonObject(with: sessionData) as? [[String: Any]]) ?? []
        guard let session = sessions.first, let sessionStart = session["created_at"] as? String else {
            return []
        }
        
        // Normalize timestamp string to prevent "+" timezone characters being decoded as spaces in URL query parameters
        var normalizedStart = sessionStart
        if let plusIndex = sessionStart.firstIndex(of: "+") {
            normalizedStart = String(sessionStart[..<plusIndex]) + "Z"
        }
        
        let ordersData = try await sendSupabaseRequest(method: "GET", endpoint: "orders", queryItems: [
            URLQueryItem(name: "select", value: "*,order_items(*)"),
            URLQueryItem(name: "table_number", value: "eq.\(tableNumber)"),
            URLQueryItem(name: "created_at", value: "gte.\(normalizedStart)")
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
                items: items
            )
        }
    }
    
    func fetchAllActiveOrders() async throws -> [Order] {
        let ordersData = try await sendSupabaseRequest(method: "GET", endpoint: "orders", queryItems: [
            URLQueryItem(name: "select", value: "*,order_items(*)"),
            URLQueryItem(name: "status", value: "in.(preparing,ready)")
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
                items: items
            )
        }
    }
    
    // POST triggers
    func openSession(tableNumber: String, guestCount: Int) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? AppConfig.defaultMerchantId
        let payload: [String: Any] = [
            "id": UUID().uuidString,
            "table_number": tableNumber,
            "session_token": "session-" + Math.randomString(length: 12),
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
    
    func deleteOrderItem(itemId: String) async throws -> Bool {
        _ = try await sendSupabaseRequest(
            method: "DELETE",
            endpoint: "order_items",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(itemId)")]
        )
        await refreshAll()
        return true
    }
    
    func uploadOrder(orderId: String, orderNumber: String, tableNumber: String, total: Double, items: [[String: Any]]) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? AppConfig.defaultMerchantId
        let orderPayload: [String: Any] = [
            "id": orderId,
            "order_number": orderNumber,
            "table_number": tableNumber,
            "total": total,
            "status": "preparing",
            "created_at": ISO8601DateFormatter().string(from: Date()),
            "merchant_id": merchantId
        ]
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
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? AppConfig.defaultMerchantId
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
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? AppConfig.defaultMerchantId
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
    private var realtimeDebounceWorkItem: DispatchWorkItem?
    
    // Heartbeat: Store timer reference to prevent leak on reconnect
    @ObservationIgnored
    private var heartbeatTimer: Timer?
    
    func startRealtimeSync() {
        guard webSocketTask == nil else { return }
        
        let wsURLString = "wss://sdmtkixrqkmwcpwoisrg.supabase.co/realtime/v1/websocket?apikey=\(anonKey)&vsn=1.0.0"
        guard let url = URL(string: wsURLString) else { return }
        
        let wsSession = URLSession(configuration: .default)
        let task = wsSession.webSocketTask(with: url)
        self.webSocketTask = task
        task.resume()
        
        listenToWebSocket()
        joinRealtimeTopic()
        startHeartbeat()
        
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
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? AppConfig.defaultMerchantId
        
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
        
        // Guard against circular sync: if we are currently pushing data, skip pull
        guard !isCurrentlySyncing else {
            #if DEBUG
            print("NetworkService [Realtime]: Skipping pull — currently syncing (avoiding circular sync).")
            #endif
            return
        }
        
        // Debounce: Cancel any pending refresh and schedule a new one after 1.5 seconds.
        // This batches multiple rapid Realtime events into a single refreshAll() call.
        realtimeDebounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            Task {
                #if DEBUG
                print("NetworkService [Realtime]: Database change detected. Performing debounced refreshAll...")
                #endif
                await self.refreshAll()
            }
        }
        realtimeDebounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: workItem)
    }
    
    func clearCache() {
        self.tables = []
        self.menuItems = []
        self.serviceRequests = []
        self.orders = []
    }
    
    func wipeRemoteTransactionsAndSessions() async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? AppConfig.defaultMerchantId
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
