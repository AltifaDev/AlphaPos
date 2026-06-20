import Foundation
import SwiftData

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

protocol RemoteAuditLogUploadable {
    var id: UUID { get }
    var employeeId: UUID? { get }
    var actionType: String { get }
    var details: String? { get }
    var originalValue: Double? { get }
    var newValue: Double? { get }
    var createdAt: Date { get }
    var isDeleted: Bool { get }
    var updatedAt: Date { get }
}

protocol RemoteCustomerUploadable {
    var id: UUID { get }
    var name: String { get }
    var email: String? { get }
    var phone: String? { get }
    var taxId: String? { get }
    var address: String? { get }
    var loyaltyPoints: Int { get }
    var membershipTier: String { get }
    var totalSpend: Double { get }
    var visitCount: Int { get }
    var notes: String? { get }
    var dateOfBirth: Date? { get }
    var allergies: String? { get }
    var preferences: String? { get }
    var isDeleted: Bool { get }
    var updatedAt: Date { get }
}

protocol RemoteRefundTransactionUploadable {
    var id: UUID { get }
    var order: Order? { get }
    var originalPayment: Payment? { get }
    var refundAmount: Double { get }
    var refundMethod: String { get }
    var reasonCode: String { get }
    var reasonNotes: String? { get }
    var refundedByEmployeeId: UUID? { get }
    var approvedByEmployeeId: UUID? { get }
    var status: String { get }
    var isDeleted: Bool { get }
    var updatedAt: Date { get }
}

protocol RemoteOrderDiscountUploadable {
    var id: UUID { get }
    var order: Order? { get }
    var promotion: Promotion? { get }
    var discountType: String { get }
    var discountValue: Double { get }
    var discountAmount: Double { get }
    var reason: String? { get }
    var appliedByEmployeeId: UUID? { get }
    var isDeleted: Bool { get }
    var updatedAt: Date { get }
}

protocol RemoteOrderTaxLineUploadable {
    var id: UUID { get }
    var order: Order? { get }
    var taxName: String { get }
    var taxRate: Double { get }
    var taxableAmount: Double { get }
    var taxAmount: Double { get }
    var isInclusive: Bool { get }
    var jurisdiction: String? { get }
    var isDeleted: Bool { get }
    var updatedAt: Date { get }
}

protocol RemoteTipUploadable {
    var id: UUID { get }
    var order: Order? { get }
    var payment: Payment? { get }
    var amount: Double { get }
    var tipType: String { get }
    var employeeId: UUID? { get }
    var isDeleted: Bool { get }
    var updatedAt: Date { get }
}

protocol RemoteCashMovementUploadable {
    var id: UUID { get }
    var registerSession: RegisterSession? { get }
    var movementType: String { get }
    var amount: Double { get }
    var reason: String { get }
    var performedByEmployeeId: UUID? { get }
    var isDeleted: Bool { get }
    var updatedAt: Date { get }
}

protocol RemoteLoyaltyTransactionUploadable {
    var id: UUID { get }
    var customer: Customer? { get }
    var order: Order? { get }
    var transactionType: String { get }
    var points: Int { get }
    var pointsBalanceAfter: Int { get }
    var transactionDescription: String? { get }
    var isDeleted: Bool { get }
    var updatedAt: Date { get }
}

protocol RemoteGiftCardUploadable {
    var id: UUID { get }
    var cardNumber: String { get }
    var balance: Double { get }
    var initialValue: Double { get }
    var customer: Customer? { get }
    var status: String { get }
    var expiresAt: Date? { get }
    var isDeleted: Bool { get }
    var updatedAt: Date { get }
}

final class NetworkManager {
    static let shared = NetworkManager()
    private let config = AppConfig.shared

    // Configurable endpoint pointing directly to Supabase REST API
    lazy var serverBaseURL: URL = config.supabaseRestURL
    private lazy var anonKey: String = config.supabaseAnonKey

    // Shared ISO8601 formatter — DateFormatter is expensive; reuse across all calls
    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    // Simulator states
    var simulateOffline = false

    var isWebOrderingEnabled: Bool {
        UserDefaults.standard.object(forKey: "enable_web_ordering") as? Bool ?? true
    }

    private init() {
        NotificationCenter.default.addObserver(
            forName: .merchantTokenDidRefresh,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { try? await self?.registerSavedPushToken() }
        }
    }

    func registerPushDevice(token: String) async throws {
        UserDefaults.standard.set(token, forKey: "apns_device_token")
        try await registerSavedPushToken()
    }

    private func registerSavedPushToken() async throws {
        guard let token = UserDefaults.standard.string(forKey: "apns_device_token"), !token.isEmpty else { return }
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        let payload: [String: Any] = [
            "merchant_id": merchantId,
            "device_token": token,
            "app_id": "pos",
            "platform": "ios",
            "is_active": true,
            "updated_at": NetworkManager.iso8601.string(from: Date())
        ]
        _ = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "push_devices",
            queryItems: [URLQueryItem(name: "on_conflict", value: "device_token")],
            payload: payload
        )
    }

    // Connectivity cache: avoid one HEAD request per sync function
    private var _lastConnectedAt: Date?
    private var _lastConnectedResult: Bool = false
    private let connectivityCacheTTL: TimeInterval = 10.0

    func isConnected() async -> Bool {
        if simulateOffline { return false }

        // Return cached result if fresh enough
        if let last = _lastConnectedAt, Date().timeIntervalSince(last) < connectivityCacheTTL {
            return _lastConnectedResult
        }

        // Quick ping check to Supabase menu_items REST endpoint
        var request = URLRequest(url: serverBaseURL.appendingPathComponent("menu_items"))
        request.httpMethod = "HEAD"
        // Use merchant JWT if available, otherwise fall back to anon key
        let token = MerchantAuthManager.shared.currentToken ?? anonKey
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        if !merchantId.isEmpty {
            request.setValue(merchantId, forHTTPHeaderField: "x-merchant-id")
        }
        request.timeoutInterval = 1.5

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let result = (response as? HTTPURLResponse).map { (200...299).contains($0.statusCode) } ?? false
            _lastConnectedAt = Date()
            _lastConnectedResult = result
            return result
        } catch {
            _lastConnectedAt = Date()
            _lastConnectedResult = false
            return false
        }
    }

    /// Call this when going offline or when you want to force a fresh check on next isConnected() call.
    func invalidateConnectivityCache() {
        _lastConnectedAt = nil
    }

    // General request sender that performs actual HTTP queries to Supabase
    private func sendSupabaseRequest(method: String, endpoint: String, queryItems: [URLQueryItem]? = nil, payload: Any? = nil) async throws -> Data {
        if simulateOffline {
            throw NetworkError.offline
        }

        var url = serverBaseURL.appendingPathComponent(endpoint)
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
        // Falls back to anon key during transition period.
        let token = MerchantAuthManager.shared.currentToken ?? anonKey
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        if !merchantId.isEmpty {
            request.setValue(merchantId, forHTTPHeaderField: "x-merchant-id")
        }

        request.timeoutInterval = 5.0

        // Enable upsert for POST with on_conflict parameter
        if method == "POST" {
            request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        }

        if let payload = payload {
            let jsonData = try JSONSerialization.data(withJSONObject: payload)
            request.httpBody = jsonData
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "HTTP Request failed"
            throw NetworkError.serverError(errorMsg)
        }

        return data
    }

    // Pull active orders from customer self-ordering database in Supabase
    func fetchCustomerOrders() async throws -> [[String: Any]] {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        let data = try await sendSupabaseRequest(method: "GET", endpoint: "orders", queryItems: [
            URLQueryItem(name: "select", value: "*,order_items(*),payments(*)"),
            URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)")
        ])

        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw NetworkError.invalidResponse
        }

        // Map from snake_case database columns to camelCase client names expected by SyncEngine
        return jsonArray.map { dict in
            var mapped = dict
            mapped["orderNumber"] = dict["order_number"]
            mapped["tableNumber"] = dict["table_number"]
            mapped["createdAt"] = dict["created_at"]

            // Map items
            if let items = dict["order_items"] as? [[String: Any]] {
                mapped["items"] = items.map { itemDict in
                    var mappedItem = itemDict
                    mappedItem["name"] = itemDict["item_name"]
                    mappedItem["itemId"] = itemDict["item_id"]
                    return mappedItem
                }
            }

            // Map payments
            if let payments = dict["payments"] as? [[String: Any]] {
                mapped["payments"] = payments.map { payDict in
                    var mappedPay = payDict
                    mappedPay["paymentMethod"] = payDict["payment_method"]
                    mappedPay["createdAt"] = payDict["created_at"]
                    return mappedPay
                }
            }
            return mapped
        }
    }

    // MARK: - API Upload Endpoints

    func uploadOrder(order: Order) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        var orderPayload: [String: Any] = [
            "id": order.id.uuidString,
            "order_number": order.orderNumber,
            "table_number": order.tableSession?.table?.tableNumber ?? "",
            "total": order.total,
            "status": order.status,
            "created_at": NetworkManager.iso8601.string(from: order.createdAt),
            "updated_at": NetworkManager.iso8601.string(from: order.updatedAt),
            "merchant_id": merchantId,
            "delivery_brand": order.deliveryBrand ?? "",
            "delivery_gp": order.deliveryGP,
            "delivery_ad_fee": order.deliveryAdFee,
            "delivery_ad_fee_is_pct": order.deliveryAdFeeIsPct,
            "delivery_other_fee": order.deliveryOtherFee
        ]
        orderPayload["guest_count"] = order.guestCount
        if let sessionToken = order.tableSession?.sessionToken {
            orderPayload["session_token"] = sessionToken
        }

        // 1. Insert order record
        _ = try await sendSupabaseRequest(method: "POST", endpoint: "orders", payload: orderPayload)

        // 2. Insert order items
        var itemsPayload: [[String: Any]] = []
        for item in order.items {
            var itemPayload: [String: Any] = [
                "id": item.id.uuidString,
                "order_id": order.id.uuidString,
                "item_name": item.menuItem?.name ?? "Unknown Item",
                "quantity": item.quantity,
                "price": item.unitPrice,
                "status": item.status,
                "item_id": item.menuItem?.id.lowercased() ?? "",
                "merchant_id": merchantId,
                "created_at": NetworkManager.iso8601.string(from: Date())
            ]
            if let branchId = order.branch?.id {
                itemPayload["branch_id"] = branchId.uuidString.lowercased()
            }
            itemsPayload.append(itemPayload)
        }
        if !itemsPayload.isEmpty {
            _ = try await sendSupabaseRequest(method: "POST", endpoint: "order_items", payload: itemsPayload)
        }

        return true
    }

    func fetchServiceRequests() async throws -> [[String: Any]] {
        let data = try await sendSupabaseRequest(method: "GET", endpoint: "service_requests", queryItems: [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "status", value: "eq.pending")
        ])

        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw NetworkError.invalidResponse
        }

        return jsonArray.map { dict in
            var mapped = dict
            mapped["tableNumber"] = dict["table_number"]
            mapped["requestType"] = dict["request_type"]
            mapped["createdAt"] = dict["created_at"]
            return mapped
        }
    }

    func resolveServiceRequest(id: String) async throws -> Bool {
        _ = try await sendSupabaseRequest(
            method: "PATCH",
            endpoint: "service_requests",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(id)")],
            payload: ["status": "completed"]
        )
        return true
    }

    func createServiceRequest(tableNumber: String, type: String) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        let payload: [String: Any] = [
            "id": UUID().uuidString,
            "table_number": tableNumber,
            "request_type": type,
            "status": "pending",
            "created_at": NetworkManager.iso8601.string(from: Date()),
            "merchant_id": merchantId
        ]
        _ = try await sendSupabaseRequest(method: "POST", endpoint: "service_requests", payload: payload)
        return true
    }

    func fetchActiveSessions() async throws -> [[String: Any]] {
        let data = try await sendSupabaseRequest(method: "GET", endpoint: "table_sessions", queryItems: [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "is_active", value: "eq.1")
        ])

        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw NetworkError.invalidResponse
        }

        return jsonArray.map { dict in
            var mapped = dict
            mapped["tableNumber"] = dict["table_number"]
            mapped["sessionToken"] = dict["session_token"]
            return mapped
        }
    }

    func closeTableSession(tableNumber: String) async throws -> Bool {
        let endedAtStr = NetworkManager.iso8601.string(from: Date())
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
        return true
    }

    func deleteOrderItem(itemId: UUID) async throws -> Bool {
        _ = try await sendSupabaseRequest(
            method: "DELETE",
            endpoint: "order_items",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(itemId.uuidString)")]
        )
        return true
    }

    /// Soft-deletes an order on Supabase by marking is_deleted = true and status = "cancelled".
    /// Physical DELETE is avoided to preserve audit trail and allow rollback.
    func deleteOrderOnServer(id: UUID) async throws -> Bool {
        let payload: [String: Any] = [
            "is_deleted": true,
            "status": "cancelled",
            "updated_at": NetworkManager.iso8601.string(from: Date())
        ]
        _ = try await sendSupabaseRequest(
            method: "PATCH",
            endpoint: "orders",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(id.uuidString.lowercased())")],
            payload: payload
        )
        return true
    }

    func uploadPayment(id: UUID, orderId: UUID?, amount: Double, method: String) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        let payload: [String: Any] = [
            "id": id.uuidString,
            "order_id": orderId?.uuidString ?? "",
            "amount": amount,
            "payment_method": method,
            "created_at": NetworkManager.iso8601.string(from: Date()),
            "status": "completed",
            "merchant_id": merchantId
        ]
        _ = try await sendSupabaseRequest(method: "POST", endpoint: "payments", payload: payload)
        return true
    }

    func completeCheckout(paymentId: UUID, orderId: UUID, amount: Double, method: String, tableNumber: String) async throws -> Bool {
        let payload: [String: Any] = [
            "p_payment_id": paymentId.uuidString,
            "p_order_id": orderId.uuidString,
            "p_amount": amount,
            "p_method": method,
            "p_table_number": tableNumber
        ]
        _ = try await sendSupabaseRequest(method: "POST", endpoint: "rpc/complete_checkout", payload: payload)
        return true
    }

    func uploadTimecard(id: UUID, employeeId: UUID, employeeName: String, clockIn: Date, clockOut: Date?, status: String, breakDuration: Int = 0, overtimeMinutes: Int = 0, notes: String? = nil, clockInConfidence: Double? = nil, clockOutConfidence: Double? = nil, clockInSelfieUrl: String? = nil, clockOutSelfieUrl: String? = nil, shiftId: UUID? = nil, verifiedByUserId: UUID? = nil) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        var payload: [String: Any] = [
            "id": id.uuidString,
            "employee_id": employeeId.uuidString,
            "employee_name": employeeName,
            "clock_in": NetworkManager.iso8601.string(from: clockIn),
            "break_duration": breakDuration,
            "overtime_minutes": overtimeMinutes,
            "status": status,
            "merchant_id": merchantId
        ]
        if let notes = notes { payload["notes"] = notes }
        if let clockInConfidence = clockInConfidence { payload["clock_in_confidence"] = clockInConfidence }
        if let clockOutConfidence = clockOutConfidence { payload["clock_out_confidence"] = clockOutConfidence }
        if let clockInSelfieUrl = clockInSelfieUrl { payload["clock_in_selfie_url"] = clockInSelfieUrl }
        if let clockOutSelfieUrl = clockOutSelfieUrl { payload["clock_out_selfie_url"] = clockOutSelfieUrl }
        if let shiftId = shiftId { payload["shift_id"] = shiftId.uuidString }
        if let verifiedByUserId = verifiedByUserId { payload["verified_by_user_id"] = verifiedByUserId.uuidString }
        if let clockOut = clockOut {
            payload["clock_out"] = NetworkManager.iso8601.string(from: clockOut)
        } else {
            payload["clock_out"] = NSNull()
        }
        payload["updated_at"] = NetworkManager.iso8601.string(from: Date())
        _ = try await sendSupabaseRequest(method: "POST", endpoint: "timecards", queryItems: [URLQueryItem(name: "on_conflict", value: "id")], payload: payload)
        return true
    }

    /// Fetches the ID of an active (clocked-in, not clocked-out) timecard for an employee.
    /// Returns nil if no active timecard exists on the server.
    func fetchActiveTimecard(employeeId: UUID) async throws -> String? {
        let data = try await sendSupabaseRequest(method: "GET", endpoint: "timecards", queryItems: [
            URLQueryItem(name: "select", value: "id"),
            URLQueryItem(name: "employee_id", value: "eq.\(employeeId.uuidString.lowercased())"),
            URLQueryItem(name: "clock_out", value: "is.null"),
            URLQueryItem(name: "limit", value: "1")
        ])
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = json.first,
              let id = first["id"] as? String else { return nil }
        return id
    }

    func uploadInventoryTransaction(
        id: UUID,
        itemId: UUID?,
        itemName: String,
        quantity: Double,
        type: String,
        costPrice: Double? = nil,
        referenceId: UUID? = nil,
        notes: String? = nil,
        branchId: UUID? = nil,
        isDeleted: Bool = false,
        updatedAt: Date = Date()
    ) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        var payload: [String: Any] = [
            "id": id.uuidString.lowercased(),
            "merchant_id": merchantId,
            "item_name": itemName,
            "quantity": quantity,
            "type": type,
            "transaction_type": type,
            "is_deleted": isDeleted,
            "is_synced": true,
            "updated_at": NetworkManager.iso8601.string(from: updatedAt),
            "created_at": NetworkManager.iso8601.string(from: Date())
        ]

        if let itemId {
            payload["item_id"] = itemId.uuidString.lowercased()
        }
        if let costPrice {
            payload["cost_price"] = costPrice
        }
        if let referenceId {
            payload["reference_id"] = referenceId.uuidString.lowercased()
        }
        if let notes {
            payload["notes"] = notes
        }
        if let branchId {
            payload["branch_id"] = branchId.uuidString.lowercased()
        }

        let conflictTarget = (referenceId != nil && itemId != nil)
            ? "merchant_id,transaction_type,reference_id,item_id"
            : "id"

        _ = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "inventory_transactions",
            queryItems: [URLQueryItem(name: "on_conflict", value: conflictTarget)],
            payload: payload
        )
        return true
    }

    func fetchRestaurantTables() async throws -> [[String: Any]] {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        let data = try await sendSupabaseRequest(method: "GET", endpoint: "restaurant_tables", queryItems: [
            URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)"),
            URLQueryItem(name: "is_deleted", value: "eq.false")
        ])
        return (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
    }

    func uploadRestaurantTable(table: RestaurantTable) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        let payload: [String: Any] = [
            "id": table.id.uuidString.lowercased(),
            "merchant_id": merchantId,
            "table_number": table.tableNumber,
            "capacity": table.capacity,
            "status": table.status,
            "qr_code_identifier": table.qrCodeIdentifier ?? "",
            "position_x": table.positionX,
            "position_y": table.positionY,
            "floor": table.floor ?? 1,
            "is_deleted": table.isDeleted,
            "zone": table.zone ?? "Indoor",
            "updated_at": NetworkManager.iso8601.string(from: table.updatedAt)
        ]

        // Upsert table
        _ = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "restaurant_tables",
            queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
            payload: payload
        )
        return true
    }

    func fetchRestaurantWalls() async throws -> [[String: Any]] {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        let data = try await sendSupabaseRequest(method: "GET", endpoint: "restaurant_walls", queryItems: [
            URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)"),
            URLQueryItem(name: "is_deleted", value: "eq.false")
        ])
        return (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
    }

    func uploadRestaurantWall(wall: RestaurantWall) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        let payload: [String: Any] = [
            "id": wall.id.uuidString.lowercased(),
            "merchant_id": merchantId,
            "floor": wall.floor,
            "type_string": wall.typeString,
            "start_x": wall.startX,
            "start_y": wall.startY,
            "end_x": wall.endX,
            "end_y": wall.endY,
            "control_x": wall.controlX ?? NSNull(),
            "control_y": wall.controlY ?? NSNull(),
            "stroke_width": wall.strokeWidth,
            "is_deleted": wall.isDeleted,
            "updated_at": NetworkManager.iso8601.string(from: wall.updatedAt)
        ]

        _ = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "restaurant_walls",
            queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
            payload: payload
        )
        return true
    }

    // MARK: - Floor Plan Image Sync
    func fetchFloorPlanImages() async throws -> [[String: Any]] {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        let data = try await sendSupabaseRequest(method: "GET", endpoint: "floor_plan_images", queryItems: [
            URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)"),
            URLQueryItem(name: "is_deleted", value: "eq.false")
        ])
        return (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
    }
    
    func uploadFloorPlanMedia(data: Data, fileName: String) async throws -> String {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        let objectPath = "\(merchantId.lowercased())/floor_plans/\(fileName)"
        var uploadURL = config.supabaseURL
        for component in ["storage", "v1", "object", "product-media"] + objectPath.split(separator: "/").map(String.init) {
            uploadURL.appendPathComponent(component)
        }

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        let token = MerchantAuthManager.shared.currentToken ?? anonKey
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.setValue("true", forHTTPHeaderField: "x-upsert")
        request.httpBody = data
        request.timeoutInterval = 60

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: responseData, encoding: .utf8) ?? "Storage upload failed"
            throw NetworkError.serverError(message)
        }

        var publicURL = config.supabaseURL
        for component in ["storage", "v1", "object", "public", "product-media"] + objectPath.split(separator: "/").map(String.init) {
            publicURL.appendPathComponent(component)
        }
        return publicURL.absoluteString
    }
    
    func downloadFloorPlanMedia(fileName: String) async throws -> Data {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        let objectPath = "\(merchantId.lowercased())/floor_plans/\(fileName)"
        var publicURL = config.supabaseURL
        for component in ["storage", "v1", "object", "public", "product-media"] + objectPath.split(separator: "/").map(String.init) {
            publicURL.appendPathComponent(component)
        }
        
        let (data, response) = try await URLSession.shared.data(from: publicURL)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.serverError("Failed to download floor plan media")
        }
        return data
    }

    func uploadFloorPlanImage(floorPlan: FloorPlanImage) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        let payload: [String: Any] = [
            "id": floorPlan.id.uuidString.lowercased(),
            "merchant_id": merchantId,
            "floor": floorPlan.floor,
            "image_filename": floorPlan.imageFilename,
            "is_deleted": floorPlan.isDeleted,
            "updated_at": NetworkManager.iso8601.string(from: floorPlan.updatedAt)
        ]
        _ = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "floor_plan_images",
            queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
            payload: payload
        )
        return true
    }

    func uploadTableSession(session: TableSession) async throws -> Bool {

        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        var payload: [String: Any] = [
            "id": session.id.uuidString.lowercased(),
            "table_number": session.table?.tableNumber ?? "",
            "session_token": session.sessionToken,
            "is_active": session.isActive ? 1 : 0,
            "guest_count": session.guestCount,
            "created_at": NetworkManager.iso8601.string(from: session.startedAt),
            "merchant_id": merchantId
        ]

        if let endedAt = session.endedAt {
            payload["ended_at"] = NetworkManager.iso8601.string(from: endedAt)
        }

        _ = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "table_sessions",
            queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
            payload: payload
        )

        // When a new active session is created, migrate any active orders on this table
        // that have no session_token (or belong to a previous session) to use this session's token.
        // This ensures iPhone Staff app can always find orders via session_token lookup.
        if session.isActive, let tableNumber = session.table?.tableNumber, !tableNumber.isEmpty {
            do {
                _ = try await sendSupabaseRequest(
                    method: "PATCH",
                    endpoint: "orders",
                    queryItems: [
                        URLQueryItem(name: "table_number", value: "eq.\(tableNumber)"),
                        URLQueryItem(name: "status", value: "not.in.(completed,cancelled)"),
                        URLQueryItem(name: "session_token", value: "is.null")
                    ],
                    payload: ["session_token": session.sessionToken]
                )
                #if DEBUG
                print("NetworkManager [Session]: Migrated null-token orders on table \(tableNumber) to session \(session.sessionToken)")
                #endif
            } catch {
                // Non-fatal: orders will still be visible via timestamp fallback
                #if DEBUG
                print("NetworkManager [Session]: Order migration skipped: \(error.localizedDescription)")
                #endif
            }
        }

        return true
    }

    func deleteTableSession(id: UUID) async throws -> Bool {
        _ = try await sendSupabaseRequest(
            method: "DELETE",
            endpoint: "table_sessions",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(id.uuidString.lowercased())")]
        )
        return true
    }

    func uploadEmployee(employee: Employee) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        let username = employee.user?.username ?? "staff_\(employee.id.uuidString.prefix(8).lowercased())"
        // WARNING: pinCodeHash should already be hashed client-side before reaching this point.
        // Do NOT send raw PINs here. Verify that employee.user?.pinCodeHash contains a bcrypt/SHA hash,
        // not a plaintext PIN. The default fallback "0000" is a placeholder — never ship this in production.
        let pinCode = employee.user?.pinCodeHash ?? "0000"
        let role = employee.user?.role?.name ?? "Staff"


        var payload: [String: Any] = [
            "id": employee.id.uuidString.lowercased(),
            "merchant_id": merchantId,
            "first_name": employee.firstName,
            "last_name": employee.lastName,
            "phone": employee.phone ?? "",
            "national_id": employee.nationalId ?? "",
            "employment_type": employee.employmentType,
            "pay_rate": employee.payRate,
            "username": username,
            "pin_code": pinCode,
            "role": role,
            "updated_at": NetworkManager.iso8601.string(from: employee.updatedAt)
        ]

        if let bankAccountNumber = employee.bankAccountNumber { payload["bank_account_number"] = bankAccountNumber }
        if let bankName = employee.bankName { payload["bank_name"] = bankName }
        if let email = employee.email { payload["email"] = email }
        if let address = employee.address { payload["address"] = address }
        if let emergencyContactName = employee.emergencyContactName { payload["emergency_contact_name"] = emergencyContactName }
        if let emergencyContactPhone = employee.emergencyContactPhone { payload["emergency_contact_phone"] = emergencyContactPhone }
        if let dateOfBirth = employee.dateOfBirth { payload["date_of_birth"] = NetworkManager.iso8601.string(from: dateOfBirth) }
        if let faceRegisteredAt = employee.faceRegisteredAt { payload["face_registered_at"] = NetworkManager.iso8601.string(from: faceRegisteredAt) }
        if let resignedAt = employee.resignedAt { payload["resigned_at"] = NetworkManager.iso8601.string(from: resignedAt) }
        payload["joined_at"] = NetworkManager.iso8601.string(from: employee.joinedAt)

        if let faceData = employee.faceEmbeddingData {
            payload["face_embedding"] = faceData.base64EncodedString()
        }

        _ = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "employees",
            queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
            payload: payload
        )
        return true
    }

    func uploadEmployeeShift(shift: EmployeeShift) async throws -> Bool {
        guard let employeeId = shift.employee?.id else { return false }
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        let payload: [String: Any] = [
            "id": shift.id.uuidString.lowercased(),
            "employee_id": employeeId.uuidString.lowercased(),
            "merchant_id": merchantId,
            "scheduled_start": NetworkManager.iso8601.string(from: shift.scheduledStart),
            "scheduled_end": NetworkManager.iso8601.string(from: shift.scheduledEnd),
            "role": shift.role ?? "",
            "notes": shift.notes ?? "",
            "updated_at": NetworkManager.iso8601.string(from: shift.updatedAt)
        ]
        _ = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "employee_shifts",
            queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
            payload: payload
        )
        return true
    }

    func uploadMerchant(
        id: UUID,
        name: String,
        email: String,
        kitchenWorkflowRequired: Bool,
        isTableSystemEnabled: Bool = true,
        isWebOrderingEnabled: Bool = true,
        phone: String? = nil,
        website: String? = nil,
        address: String? = nil,
        taxId: String? = nil,
        branchCode: String? = nil,
        taxRate: Double? = nil,
        taxType: String? = nil,
        serviceChargeRate: Double? = nil,
        receiptHeader: String? = nil,
        receiptFooter: String? = nil,
        promptPayNumber: String? = nil
    ) async throws -> Bool {
        var payload: [String: Any] = [
            "id": id.uuidString.lowercased(),
            "name": name,
            "email": email,
            "kitchen_workflow_required": kitchenWorkflowRequired,
            "is_table_system_enabled": isTableSystemEnabled,
            "is_web_ordering_enabled": isWebOrderingEnabled
        ]

        if let phone = phone { payload["phone"] = phone }
        if let website = website { payload["website"] = website }
        if let address = address { payload["address_street"] = address }
        if let taxId = taxId { payload["tax_id"] = taxId }
        if let branchCode = branchCode { payload["branch_code"] = branchCode }
        if let taxRate = taxRate { payload["tax_rate"] = taxRate }
        if let taxType = taxType { payload["tax_type"] = taxType }
        if let serviceChargeRate = serviceChargeRate { payload["service_charge_rate"] = serviceChargeRate }
        if let receiptHeader = receiptHeader { payload["receipt_header"] = receiptHeader }
        if let receiptFooter = receiptFooter { payload["receipt_footer"] = receiptFooter }
        if let promptPayNumber = promptPayNumber { payload["promptpay_number"] = promptPayNumber }

        _ = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "merchants",
            queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
            payload: payload
        )
        return true
    }

    func deleteMerchantOnServer() async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        _ = try await sendSupabaseRequest(
            method: "DELETE",
            endpoint: "merchants",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(merchantId)")]
        )
        return true
    }

    func wipeRemoteTransactionsAndSessions() async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
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

    // MARK: - Menu Items Sync

    private func uploadProductMedia(
        _ data: Data,
        merchantId: String,
        itemId: String,
        fileName: String,
        contentType: String
    ) async throws -> String {
        let objectPath = "\(merchantId.lowercased())/\(itemId.lowercased())/\(fileName)"
        var uploadURL = config.supabaseURL
        for component in ["storage", "v1", "object", "product-media"] + objectPath.split(separator: "/").map(String.init) {
            uploadURL.appendPathComponent(component)
        }

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        let token = MerchantAuthManager.shared.currentToken ?? anonKey
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("true", forHTTPHeaderField: "x-upsert")
        request.httpBody = data
        request.timeoutInterval = 60

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: responseData, encoding: .utf8) ?? "Storage upload failed"
            throw NetworkError.serverError(message)
        }

        var publicURL = config.supabaseURL
        for component in ["storage", "v1", "object", "public", "product-media"] + objectPath.split(separator: "/").map(String.init) {
            publicURL.appendPathComponent(component)
        }
        return publicURL.absoluteString
    }

    /// Maps iPad Category display names to the lowercase category slugs used by the iPhone app and Supabase schema.
    private func categorySlug(from categoryName: String?) -> String {
        guard let name = categoryName?.lowercased() else { return "mains" }
        switch name {
        case let n where n.contains("appetizer"): return "appetizers"
        case let n where n.contains("main"), let n where n.contains("dish"): return "mains"
        case let n where n.contains("beverage"), let n where n.contains("drink"): return "drinks"
        case let n where n.contains("dessert"), let n where n.contains("sweet"): return "desserts"
        default: return "mains"
        }
    }

    /// Emoji mapping based on category for display on iPhone staff app.
    private func defaultEmoji(for categorySlug: String) -> String {
        switch categorySlug {
        case "appetizers": return "🥟"
        case "mains": return "🍛"
        case "drinks": return "🧋"
        case "desserts": return "🍨"
        default: return "🍽️"
        }
    }

    /// Upserts a single MenuItem from SwiftData to the Supabase `menu_items` table.
    func uploadMenuItem(item: MenuItem) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        let catSlug = categorySlug(from: item.category?.name)

        if let data = item.imageData {
            item.imageUrl = try await uploadProductMedia(data, merchantId: merchantId, itemId: item.id, fileName: "image-1.jpg", contentType: "image/jpeg")
        }
        if let data = item.imageData2 {
            item.imageUrl2 = try await uploadProductMedia(data, merchantId: merchantId, itemId: item.id, fileName: "image-2.jpg", contentType: "image/jpeg")
        }
        if let data = item.imageData3 {
            item.imageUrl3 = try await uploadProductMedia(data, merchantId: merchantId, itemId: item.id, fileName: "image-3.jpg", contentType: "image/jpeg")
        }
        if let data = item.videoData {
            item.videoUrl = try await uploadProductMedia(data, merchantId: merchantId, itemId: item.id, fileName: "video.mp4", contentType: "video/mp4")
        }

        let payload: [String: Any] = [
            "id": item.id.lowercased(),
            "name": item.name,
            "description": item.itemDescription ?? "",
            "price": item.price,
            "category": catSlug,
            "emoji": defaultEmoji(for: catSlug),
            "img_class": catSlug,
            "merchant_id": merchantId,
            "image_url": item.imageUrl ?? "",
            "image_url_2": item.imageUrl2 ?? "",
            "image_url_3": item.imageUrl3 ?? "",
            "video_url": item.videoUrl ?? "",
            "name_translations": item.nameTranslations,
            "description_translations": item.descriptionTranslations
        ]

        _ = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "menu_items",
            queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
            payload: payload
        )
        return true
    }

    /// Deletes a MenuItem from Supabase by its ID.
    func deleteMenuItemOnServer(id: String) async throws -> Bool {
        _ = try await sendSupabaseRequest(
            method: "DELETE",
            endpoint: "menu_items",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(id.lowercased())")]
        )
        return true
    }

    /// Fetches all menu items for the active merchant from Supabase.
    /// Returns an array of dictionaries with all menu item fields.
    func fetchMenuItemsFromSupabase() async throws -> [[String: Any]] {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        let data = try await sendSupabaseRequest(
            method: "GET",
            endpoint: "menu_items",
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)"),
                URLQueryItem(name: "is_deleted", value: "eq.false")
            ]
        )
        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw NetworkError.invalidResponse
        }
        return jsonArray
    }

    /// Fetches all promotions for the active merchant, including soft-deleted rows.
    /// Deleted rows are needed as tombstones so local caches can purge records
    /// when an admin changes the database directly.
    func fetchPromotionsFromSupabase() async throws -> [[String: Any]] {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        let data = try await sendSupabaseRequest(
            method: "GET",
            endpoint: "promotions",
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)")
            ]
        )
        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw NetworkError.invalidResponse
        }
        return jsonArray
    }

    func uploadPromotion(promotion: Promotion) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        var payload: [String: Any] = [
            "id": promotion.id.uuidString.lowercased(),
            "merchant_id": merchantId,
            "title": promotion.title,
            "promo_description": promotion.promoDescription ?? "",
            "image_data": promotion.imageData ?? "",
            "media_type": promotion.mediaType,
            "is_active": promotion.isActive ? 1 : 0,
            "discount_type": promotion.discountType,
            "discount_value": promotion.discountValue,
            "minimum_spend": promotion.minimumSpend,
            "applies_to_menu_item_id": promotion.appliesToMenuItemId.map { $0 as Any } ?? NSNull(),
            "reward_menu_item_id": promotion.rewardMenuItemId.map { $0 as Any } ?? NSNull(),
            "required_quantity": promotion.requiredQuantity,
            "reward_quantity": promotion.rewardQuantity,
            "max_redemptions": promotion.maxRedemptions.map { $0 as Any } ?? NSNull(),
            "current_redemptions": promotion.currentRedemptions,
            "per_customer_limit": promotion.perCustomerLimit.map { $0 as Any } ?? NSNull(),
            "is_deleted": promotion.isDeleted ? 1 : 0,
            "updated_at": NetworkManager.iso8601.string(from: promotion.updatedAt)
        ]
        if let startsAt = promotion.startsAt {
            payload["starts_at"] = NetworkManager.iso8601.string(from: startsAt)
        }
        if let endsAt = promotion.endsAt {
            payload["ends_at"] = NetworkManager.iso8601.string(from: endsAt)
        }

        var supabaseSuccess = false
        do {
            _ = try await sendSupabaseRequest(
                method: "POST",
                endpoint: "promotions",
                queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
                payload: payload
            )
            supabaseSuccess = true
        } catch {
            print("NetworkManager: Supabase promotion upload failed: \(error.localizedDescription)")
        }

        // Legacy local server call removed — Supabase is the single source of truth.
        // isSynced is only set true when Supabase succeeds.
        return supabaseSuccess
    }

    func uploadPromotionBundleItems(for promotion: Promotion) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId

        let payload: [[String: Any]] = promotion.bundleItems.compactMap { bundleItem in
            guard let menuItemId = bundleItem.menuItem?.id else { return nil }
            return [
                "id": bundleItem.id.uuidString.lowercased(),
                "merchant_id": merchantId,
                "promotion_id": promotion.id.uuidString.lowercased(),
                "menu_item_id": menuItemId,
                "quantity": bundleItem.quantity,
                "display_order": bundleItem.displayOrder,
                "is_synced": true,
                "is_deleted": bundleItem.isDeleted,
                "updated_at": NetworkManager.iso8601.string(from: bundleItem.updatedAt)
            ]
        }

        if !payload.isEmpty {
            _ = try await sendSupabaseRequest(
                method: "POST",
                endpoint: "promotion_bundle_items",
                queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
                payload: payload
            )
        }

        let activeBundleIds = promotion.bundleItems
            .filter { !$0.isDeleted }
            .map { $0.id.uuidString.lowercased() }

        let deletedPayload: [String: Any] = [
            "is_deleted": true,
            "updated_at": NetworkManager.iso8601.string(from: Date())
        ]

        var queryItems = [
            URLQueryItem(name: "promotion_id", value: "eq.\(promotion.id.uuidString.lowercased())"),
            URLQueryItem(name: "is_deleted", value: "eq.false")
        ]
        if !activeBundleIds.isEmpty {
            queryItems.append(URLQueryItem(name: "id", value: "not.in.(\(activeBundleIds.joined(separator: ",")))"))
        }

        _ = try await sendSupabaseRequest(
            method: "PATCH",
            endpoint: "promotion_bundle_items",
            queryItems: queryItems,
            payload: deletedPayload
        )

        return true
    }

    func fetchPromotionBundleItemsFromSupabase() async throws -> [[String: Any]] {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        let data = try await sendSupabaseRequest(
            method: "GET",
            endpoint: "promotion_bundle_items",
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)")
            ]
        )
        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw NetworkError.invalidResponse
        }
        return jsonArray
    }

    // MARK: - Purchase Orders Sync

    /// Upserts a PurchaseOrder header and all its items to Supabase in a single sync call.
    /// Items are batch-upserted using on_conflict=id for idempotency.
    func uploadPurchaseOrder(purchaseOrder: PurchaseOrder) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId

        // 1. Upsert PO header
        var poPayload: [String: Any] = [
            "id": purchaseOrder.id.uuidString.lowercased(),
            "merchant_id": merchantId,
            "po_number": purchaseOrder.poNumber,
            "status": purchaseOrder.status,
            "order_date": NetworkManager.iso8601.string(from: purchaseOrder.orderDate),
            "notes": purchaseOrder.notes ?? "",
            "is_synced": true,
            "is_deleted": purchaseOrder.isDeleted,
            "updated_at": NetworkManager.iso8601.string(from: purchaseOrder.updatedAt)
        ]
        if let supplierId = purchaseOrder.supplier?.id {
            poPayload["supplier_id"] = supplierId.uuidString.lowercased()
        }
        if let branchId = purchaseOrder.branch?.id {
            poPayload["branch_id"] = branchId.uuidString.lowercased()
        }
        if let deliveryDate = purchaseOrder.deliveryDate {
            poPayload["delivery_date"] = NetworkManager.iso8601.string(from: deliveryDate)
        }

        _ = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "purchase_orders",
            queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
            payload: poPayload
        )

        // 2. Batch upsert all non-deleted items for this PO
        let activeItems = purchaseOrder.items.filter { !$0.isDeleted }
        if !activeItems.isEmpty {
            let itemsPayload: [[String: Any]] = activeItems.map { item in
                var itemDict: [String: Any] = [
                    "id": item.id.uuidString.lowercased(),
                    "merchant_id": merchantId,
                    "purchase_order_id": purchaseOrder.id.uuidString.lowercased(),
                    "quantity_ordered": item.quantityOrdered,
                    "quantity_received": item.quantityReceived,
                    "unit_cost": item.unitCost,
                    "is_synced": true,
                    "is_deleted": false,
                    "updated_at": NetworkManager.iso8601.string(from: item.updatedAt)
                ]
                if let inventoryItemId = item.inventoryItem?.id {
                    itemDict["inventory_item_id"] = inventoryItemId.uuidString.lowercased()
                }
                return itemDict
            }
            _ = try await sendSupabaseRequest(
                method: "POST",
                endpoint: "purchase_order_items",
                queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
                payload: itemsPayload
            )
        }

        return true
    }

    /// Soft-deletes a PurchaseOrder on Supabase by marking is_deleted = true.
    /// Items are marked as deleted via update (CASCADE DELETE handles physical removal).
    func deletePurchaseOrderOnServer(id: UUID) async throws -> Bool {
        let idStr = id.uuidString.lowercased()
        let deletedPayload: [String: Any] = ["is_deleted": true]

        // Mark items deleted first
        _ = try await sendSupabaseRequest(
            method: "PATCH",
            endpoint: "purchase_order_items",
            queryItems: [URLQueryItem(name: "purchase_order_id", value: "eq.\(idStr)")],
            payload: deletedPayload
        )
        // Mark PO header deleted
        _ = try await sendSupabaseRequest(
            method: "PATCH",
            endpoint: "purchase_orders",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(idStr)")],
            payload: deletedPayload
        )
        return true
    }

    // MARK: - Delivery Prices Sync

    /// Batch upserts all provided DeliveryPrice records to Supabase.
    /// DeliveryPrice has no isSynced flag — all prices are sent on every sync cycle.
    func uploadDeliveryPrices(_ deliveryPrices: [DeliveryPrice]) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId

        // Filter to prices that have a valid menu item link
        let validPrices: [[String: Any]] = deliveryPrices.compactMap { dp in
            guard let menuItemId = dp.menuItem?.id else { return nil }
            return [
                "id": dp.id.uuidString.lowercased(),
                "merchant_id": merchantId,
                "menu_item_id": menuItemId.lowercased(),
                "brand_name": dp.brandName,
                "price": dp.price
            ]
        }

        guard !validPrices.isEmpty else { return true }

        _ = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "delivery_prices",
            queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
            payload: validPrices
        )
        return true
    }

    func deletePromotionOnServer(id: UUID) async throws -> Bool {
        let idStr = id.uuidString.lowercased()
        // Soft-delete: PATCH is_deleted=1 so RLS (which allows PATCH but may block DELETE)
        // works correctly while leaving a tombstone for other devices to purge local cache.
        let softDeletePayload: [String: Any] = [
            "is_deleted": 1,
            "updated_at": NetworkManager.iso8601.string(from: Date())
        ]

        var supabaseSuccess = false
        do {
            _ = try await sendSupabaseRequest(
                method: "PATCH",
                endpoint: "promotions",
                queryItems: [URLQueryItem(name: "id", value: "eq.\(idStr)")],
                payload: softDeletePayload
            )
            supabaseSuccess = true
        } catch {
            print("NetworkManager: Supabase promotion soft-delete failed: \(error.localizedDescription)")
        }

        // Legacy local server call removed.
        return supabaseSuccess
    }

    // MARK: - Printers & Routing Rules Sync

    func uploadPrinter(_ printer: Printer) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId

        let payload: [String: Any] = [
            "id": printer.id.uuidString.lowercased(),
            "merchant_id": merchantId,
            "name": printer.name,
            "connection_type": printer.connectionType,
            "ip_address": printer.ipAddress ?? "",
            "port": printer.port,
            "bluetooth_name": printer.bluetoothName ?? "",
            "paper_width": printer.paperWidth,
            "status": printer.status,
            "role": printer.role,
            "is_active": printer.isActive,
            "is_synced": true,
            "is_deleted": printer.isDeleted,
            "updated_at": NetworkManager.iso8601.string(from: printer.updatedAt)
        ]

        _ = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "printers",
            queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
            payload: payload
        )
        return true
    }

    func deletePrinterOnServer(id: UUID) async throws -> Bool {
        _ = try await sendSupabaseRequest(
            method: "DELETE",
            endpoint: "printers",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(id.uuidString.lowercased())")]
        )
        return true
    }

    func uploadPrintRoutingRule(_ rule: PrintRoutingRule) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId

        guard let printerId = rule.printer?.id else {
            throw NSError(domain: "NetworkManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "Rule is not linked to a printer"])
        }

        let payload: [String: Any] = [
            "id": rule.id.uuidString.lowercased(),
            "merchant_id": merchantId,
            "printer_id": printerId.uuidString.lowercased(),
            "category_id": rule.categoryId ?? "",
            "print_on_order": rule.printOnOrder,
            "print_on_payment": rule.printOnPayment,
            "is_synced": true,
            "is_deleted": rule.isDeleted,
            "updated_at": NetworkManager.iso8601.string(from: rule.updatedAt)
        ]

        _ = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "print_routing_rules",
            queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
            payload: payload
        )
        return true
    }

    func deletePrintRoutingRuleOnServer(id: UUID) async throws -> Bool {
        _ = try await sendSupabaseRequest(
            method: "DELETE",
            endpoint: "print_routing_rules",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(id.uuidString.lowercased())")]
        )
        return true
    }

    // MARK: - Audit Logs Sync

    func uploadAuditLog(_ log: RemoteAuditLogUploadable) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId

        var payload: [String: Any] = [
            "id": log.id.uuidString.lowercased(),
            "merchant_id": merchantId,
            "action_type": log.actionType,
            "is_synced": true,
            "is_deleted": log.isDeleted,
            "updated_at": NetworkManager.iso8601.string(from: log.updatedAt),
            "created_at": NetworkManager.iso8601.string(from: log.createdAt)
        ]

        if let empId = log.employeeId {
            payload["employee_id"] = empId.uuidString.lowercased()
        }
        if let details = log.details {
            payload["details"] = details
        }
        if let origVal = log.originalValue {
            payload["original_value"] = origVal
        }
        if let newVal = log.newValue {
            payload["new_value"] = newVal
        }

        _ = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "audit_logs",
            queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
            payload: payload
        )
        return true
    }

    func deleteAuditLogOnServer(id: UUID) async throws -> Bool {
        _ = try await sendSupabaseRequest(
            method: "DELETE",
            endpoint: "audit_logs",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(id.uuidString.lowercased())")]
        )
        return true
    }

    // MARK: - Staff Security and Device Sync

    func replaceRolePermissions(role: Role) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        _ = try await sendSupabaseRequest(
            method: "DELETE",
            endpoint: "role_permissions",
            queryItems: [URLQueryItem(name: "role", value: "eq.\(role.name)")]
        )

        let permissions = PermissionService.permissions(for: role)
        guard !permissions.isEmpty else { return true }

        let payload = permissions.map { permission in
            [
                "merchant_id": merchantId,
                "role": role.name,
                "permission_key": permission.rawValue
            ]
        }

        _ = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "role_permissions",
            queryItems: [URLQueryItem(name: "on_conflict", value: "merchant_id,role,permission_key")],
            payload: payload
        )
        return true
    }

    func uploadMerchantDevice(_ device: MerchantDevice) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        var payload: [String: Any] = [
            "id": device.id.uuidString.lowercased(),
            "merchant_id": merchantId,
            "device_name": device.deviceName,
            "device_type": device.deviceType,
            "is_trusted": device.isTrusted,
            "updated_at": NetworkManager.iso8601.string(from: device.updatedAt)
        ]
        if let branchId = device.branchId {
            payload["branch_id"] = branchId.uuidString.lowercased()
        }
        if let fingerprint = device.deviceFingerprintHash {
            payload["device_fingerprint_hash"] = fingerprint
        }
        if let lastSeenAt = device.lastSeenAt {
            payload["last_seen_at"] = NetworkManager.iso8601.string(from: lastSeenAt)
        }
        payload["created_at"] = NetworkManager.iso8601.string(from: device.createdAt)

        _ = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "merchant_devices",
            queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
            payload: payload
        )
        return true
    }

    func uploadStaffSessionRecord(_ session: StaffSessionRecord) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        var payload: [String: Any] = [
            "id": session.id.uuidString.lowercased(),
            "merchant_id": merchantId,
            "started_at": NetworkManager.iso8601.string(from: session.startedAt),
            "created_at": NetworkManager.iso8601.string(from: session.startedAt)
        ]
        if let deviceId = session.deviceId {
            payload["device_id"] = deviceId.uuidString.lowercased()
        }
        if let employeeId = session.employeeId {
            payload["employee_id"] = employeeId.uuidString.lowercased()
        }
        if let roleName = session.roleName {
            payload["role"] = roleName
        }
        if let endedAt = session.endedAt {
            payload["ended_at"] = NetworkManager.iso8601.string(from: endedAt)
        }
        if let endedReason = session.endedReason {
            payload["ended_reason"] = endedReason
        }

        _ = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "staff_sessions",
            queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
            payload: payload
        )
        return true
    }

    func uploadSecurityPolicy(_ policy: SecurityPolicy) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        let payload: [String: Any] = [
            "merchant_id": merchantId,
            "passcode_min_length": policy.passcodeMinLength,
            "passcode_max_attempts": policy.passcodeMaxAttempts,
            "lockout_minutes": policy.lockoutMinutes,
            "staff_session_timeout_minutes": policy.staffSessionTimeoutMinutes,
            "require_manager_override_for_refund": policy.requireManagerOverrideForRefund,
            "require_manager_override_for_void": policy.requireManagerOverrideForVoid,
            "updated_at": NetworkManager.iso8601.string(from: policy.updatedAt)
        ]

        _ = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "security_policies",
            queryItems: [URLQueryItem(name: "on_conflict", value: "merchant_id")],
            payload: payload
        )
        return true
    }

    // MARK: - Register Sessions Sync

    func uploadRegisterSession(_ session: RegisterSession) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId

        var payload: [String: Any] = [
            "id": session.id.uuidString.lowercased(),
            "merchant_id": merchantId,
            "opened_by_user_id": session.openedByUserId.uuidString.lowercased(),
            "opened_at": NetworkManager.iso8601.string(from: session.openedAt),
            "opening_cash": session.openingCash,
            "expected_closing_cash": session.expectedClosingCash,
            "actual_closing_cash": session.actualClosingCash,
            "cash_discrepancy": session.cashDiscrepancy,
            "is_synced": true,
            "is_deleted": session.isDeleted,
            "updated_at": NetworkManager.iso8601.string(from: session.updatedAt)
        ]

        if let branchId = session.branch?.id {
            payload["branch_id"] = branchId.uuidString.lowercased()
        }
        if let closedBy = session.closedByUserId {
            payload["closed_by_user_id"] = closedBy.uuidString.lowercased()
        }
        if let closedAt = session.closedAt {
            payload["closed_at"] = NetworkManager.iso8601.string(from: closedAt)
        }
        if let notes = session.notes {
            payload["notes"] = notes
        }

        _ = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "register_sessions",
            queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
            payload: payload
        )
        return true
    }

    func deleteRegisterSessionOnServer(id: UUID) async throws -> Bool {
        _ = try await sendSupabaseRequest(
            method: "DELETE",
            endpoint: "register_sessions",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(id.uuidString.lowercased())")]
        )
        return true
    }

    func uploadShiftReport(_ report: ShiftReport) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId

        var payload: [String: Any] = [
            "id": report.id.uuidString.lowercased(),
            "merchant_id": merchantId,
            "report_type": report.reportType,
            "gross_sales": report.grossSales,
            "net_sales": report.netSales,
            "total_tax": report.totalTax,
            "total_discounts": report.totalDiscounts,
            "total_refunds": report.totalRefunds,
            "cash_expected": report.cashExpected,
            "cash_actual": report.cashActual,
            "over_short": report.overShort,
            "is_synced": true,
            "is_deleted": report.isDeleted,
            "updated_at": NetworkManager.iso8601.string(from: report.updatedAt),
            "created_at": NetworkManager.iso8601.string(from: report.createdAt)
        ]

        if let sessionId = report.registerSession?.id {
            payload["register_session_id"] = sessionId.uuidString.lowercased()
        }
        if let employeeId = report.generatedByEmployee?.id {
            payload["generated_by_employee_id"] = employeeId.uuidString.lowercased()
        }

        _ = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "shift_reports",
            queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
            payload: payload
        )
        return true
    }

    // MARK: - Customers Sync
    func fetchCustomersFromSupabase() async throws -> [[String: Any]] {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        let data = try await sendSupabaseRequest(
            method: "GET",
            endpoint: "customers",
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)"),
                URLQueryItem(name: "is_deleted", value: "eq.false")
            ]
        )
        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw NetworkError.invalidResponse
        }
        return jsonArray
    }

    func uploadCustomer(customer: RemoteCustomerUploadable) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId

        var payload: [String: Any] = [
            "id": customer.id.uuidString.lowercased(),
            "merchant_id": merchantId,
            "name": customer.name,
            "loyalty_points": customer.loyaltyPoints,
            "membership_tier": customer.membershipTier,
            "total_spend": customer.totalSpend,
            "visit_count": customer.visitCount,
            "is_deleted": customer.isDeleted,
            "updated_at": NetworkManager.iso8601.string(from: customer.updatedAt)
        ]

        if let email = customer.email { payload["email"] = email }
        if let phone = customer.phone { payload["phone"] = phone }
        if let taxId = customer.taxId { payload["tax_id"] = taxId }
        if let address = customer.address { payload["address"] = address }
        if let notes = customer.notes { payload["notes"] = notes }
        if let allergies = customer.allergies { payload["allergies"] = allergies }
        if let preferences = customer.preferences { payload["preferences"] = preferences }
        if let dob = customer.dateOfBirth {
            payload["date_of_birth"] = NetworkManager.iso8601.string(from: dob)
        }

        var supabaseSuccess = false
        do {
            _ = try await sendSupabaseRequest(
                method: "POST",
                endpoint: "customers",
                queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
                payload: payload
            )
            supabaseSuccess = true
        } catch {
            print("NetworkManager: Supabase customer upload failed: \(error.localizedDescription)")
        }
        return supabaseSuccess
    }

    func deleteCustomerOnServer(id: UUID) async throws -> Bool {
        let idStr = id.uuidString.lowercased()
        let softDeletePayload: [String: Any] = [
            "is_deleted": true,
            "updated_at": NetworkManager.iso8601.string(from: Date())
        ]
        var supabaseSuccess = false
        do {
            _ = try await sendSupabaseRequest(
                method: "PATCH",
                endpoint: "customers",
                queryItems: [URLQueryItem(name: "id", value: "eq.\(idStr)")],
                payload: softDeletePayload
            )
            supabaseSuccess = true
        } catch {
            print("NetworkManager: Supabase customer soft-delete failed: \(error.localizedDescription)")
        }
        return supabaseSuccess
    }

    // MARK: - Refund Transactions Sync
    func fetchRefundTransactionsFromSupabase() async throws -> [[String: Any]] {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        let data = try await sendSupabaseRequest(
            method: "GET",
            endpoint: "refund_transactions",
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)"),
                URLQueryItem(name: "is_deleted", value: "eq.false")
            ]
        )
        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw NetworkError.invalidResponse
        }
        return jsonArray
    }

    func uploadRefundTransaction(refund: RemoteRefundTransactionUploadable) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId

        let orderId = refund.order?.id.uuidString.lowercased() ?? ""
        let originalPaymentId = refund.originalPayment?.id.uuidString.lowercased() ?? ""

        var payload: [String: Any] = [
            "id": refund.id.uuidString.lowercased(),
            "merchant_id": merchantId,
            "order_id": orderId,
            "refund_amount": refund.refundAmount,
            "refund_method": refund.refundMethod,
            "reason_code": refund.reasonCode,
            "status": refund.status,
            "is_deleted": refund.isDeleted,
            "updated_at": NetworkManager.iso8601.string(from: refund.updatedAt)
        ]

        if !originalPaymentId.isEmpty {
            payload["original_payment_id"] = originalPaymentId
        }
        if let reasonNotes = refund.reasonNotes {
            payload["reason_notes"] = reasonNotes
        }
        if let refundedBy = refund.refundedByEmployeeId {
            payload["refunded_by_employee_id"] = refundedBy.uuidString.lowercased()
        }
        if let approvedBy = refund.approvedByEmployeeId {
            payload["approved_by_employee_id"] = approvedBy.uuidString.lowercased()
        }

        var supabaseSuccess = false
        do {
            _ = try await sendSupabaseRequest(
                method: "POST",
                endpoint: "refund_transactions",
                queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
                payload: payload
            )
            supabaseSuccess = true
        } catch {
            print("NetworkManager: Supabase refund upload failed: \(error.localizedDescription)")
        }
        return supabaseSuccess
    }

    func deleteRefundOnServer(id: UUID) async throws -> Bool {
        let idStr = id.uuidString.lowercased()
        let softDeletePayload: [String: Any] = [
            "is_deleted": true,
            "updated_at": NetworkManager.iso8601.string(from: Date())
        ]
        var supabaseSuccess = false
        do {
            _ = try await sendSupabaseRequest(
                method: "PATCH",
                endpoint: "refund_transactions",
                queryItems: [URLQueryItem(name: "id", value: "eq.\(idStr)")],
                payload: softDeletePayload
            )
            supabaseSuccess = true
        } catch {
            print("NetworkManager: Supabase refund soft-delete failed: \(error.localizedDescription)")
        }
        return supabaseSuccess
    }

    // MARK: - Order Discounts Sync
    func fetchOrderDiscountsFromSupabase() async throws -> [[String: Any]] {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        let data = try await sendSupabaseRequest(
            method: "GET",
            endpoint: "order_discounts",
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)"),
                URLQueryItem(name: "is_deleted", value: "eq.false")
            ]
        )
        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw NetworkError.invalidResponse
        }
        return jsonArray
    }

    func uploadOrderDiscount(_ discount: RemoteOrderDiscountUploadable) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId

        let orderId = discount.order?.id.uuidString.lowercased() ?? ""
        var payload: [String: Any] = [
            "id": discount.id.uuidString.lowercased(),
            "merchant_id": merchantId,
            "order_id": orderId,
            "discount_type": discount.discountType,
            "discount_value": discount.discountValue,
            "discount_amount": discount.discountAmount,
            "is_deleted": discount.isDeleted,
            "updated_at": NetworkManager.iso8601.string(from: discount.updatedAt)
        ]

        if let promoId = discount.promotion?.id.uuidString.lowercased() {
            payload["promotion_id"] = promoId
        }
        if let reason = discount.reason {
            payload["reason"] = reason
        }
        if let employeeId = discount.appliedByEmployeeId {
            payload["applied_by_employee_id"] = employeeId.uuidString.lowercased()
        }

        var supabaseSuccess = false
        do {
            _ = try await sendSupabaseRequest(
                method: "POST",
                endpoint: "order_discounts",
                queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
                payload: payload
            )
            supabaseSuccess = true
        } catch {
            print("NetworkManager: Supabase order discount upload failed: \(error.localizedDescription)")
        }
        return supabaseSuccess
    }

    func deleteOrderDiscountOnServer(id: UUID) async throws -> Bool {
        let idStr = id.uuidString.lowercased()
        let softDeletePayload: [String: Any] = [
            "is_deleted": true,
            "updated_at": NetworkManager.iso8601.string(from: Date())
        ]
        var supabaseSuccess = false
        do {
            _ = try await sendSupabaseRequest(
                method: "PATCH",
                endpoint: "order_discounts",
                queryItems: [URLQueryItem(name: "id", value: "eq.\(idStr)")],
                payload: softDeletePayload
            )
            supabaseSuccess = true
        } catch {
            print("NetworkManager: Supabase order discount soft-delete failed: \(error.localizedDescription)")
        }
        return supabaseSuccess
    }

    // MARK: - Order Tax Lines Sync
    func fetchOrderTaxLinesFromSupabase() async throws -> [[String: Any]] {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        let data = try await sendSupabaseRequest(
            method: "GET",
            endpoint: "order_tax_lines",
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)"),
                URLQueryItem(name: "is_deleted", value: "eq.false")
            ]
        )
        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw NetworkError.invalidResponse
        }
        return jsonArray
    }

    func uploadOrderTaxLine(_ taxLine: RemoteOrderTaxLineUploadable) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId

        let orderId = taxLine.order?.id.uuidString.lowercased() ?? ""
        var payload: [String: Any] = [
            "id": taxLine.id.uuidString.lowercased(),
            "merchant_id": merchantId,
            "order_id": orderId,
            "tax_name": taxLine.taxName,
            "tax_rate": taxLine.taxRate,
            "taxable_amount": taxLine.taxableAmount,
            "tax_amount": taxLine.taxAmount,
            "is_inclusive": taxLine.isInclusive,
            "is_deleted": taxLine.isDeleted,
            "updated_at": NetworkManager.iso8601.string(from: taxLine.updatedAt)
        ]

        if let jurisdiction = taxLine.jurisdiction {
            payload["jurisdiction"] = jurisdiction
        }

        var supabaseSuccess = false
        do {
            _ = try await sendSupabaseRequest(
                method: "POST",
                endpoint: "order_tax_lines",
                queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
                payload: payload
            )
            supabaseSuccess = true
        } catch {
            print("NetworkManager: Supabase order tax line upload failed: \(error.localizedDescription)")
        }
        return supabaseSuccess
    }

    func deleteOrderTaxLineOnServer(id: UUID) async throws -> Bool {
        let idStr = id.uuidString.lowercased()
        let softDeletePayload: [String: Any] = [
            "is_deleted": true,
            "updated_at": NetworkManager.iso8601.string(from: Date())
        ]
        var supabaseSuccess = false
        do {
            _ = try await sendSupabaseRequest(
                method: "PATCH",
                endpoint: "order_tax_lines",
                queryItems: [URLQueryItem(name: "id", value: "eq.\(idStr)")],
                payload: softDeletePayload
            )
            supabaseSuccess = true
        } catch {
            print("NetworkManager: Supabase order tax line soft-delete failed: \(error.localizedDescription)")
        }
        return supabaseSuccess
    }

    // MARK: - Tips Sync
    func fetchTipsFromSupabase() async throws -> [[String: Any]] {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        let data = try await sendSupabaseRequest(
            method: "GET",
            endpoint: "tips",
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)"),
                URLQueryItem(name: "is_deleted", value: "eq.false")
            ]
        )
        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw NetworkError.invalidResponse
        }
        return jsonArray
    }

    func uploadTip(_ tip: RemoteTipUploadable) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId

        let orderId = tip.order?.id.uuidString.lowercased() ?? ""
        var payload: [String: Any] = [
            "id": tip.id.uuidString.lowercased(),
            "merchant_id": merchantId,
            "order_id": orderId,
            "amount": tip.amount,
            "tip_type": tip.tipType,
            "is_deleted": tip.isDeleted,
            "updated_at": NetworkManager.iso8601.string(from: tip.updatedAt)
        ]

        if let paymentId = tip.payment?.id.uuidString.lowercased() {
            payload["payment_id"] = paymentId
        }
        if let employeeId = tip.employeeId {
            payload["employee_id"] = employeeId.uuidString.lowercased()
        }

        var supabaseSuccess = false
        do {
            _ = try await sendSupabaseRequest(
                method: "POST",
                endpoint: "tips",
                queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
                payload: payload
            )
            supabaseSuccess = true
        } catch {
            print("NetworkManager: Supabase tip upload failed: \(error.localizedDescription)")
        }
        return supabaseSuccess
    }

    func deleteTipOnServer(id: UUID) async throws -> Bool {
        let idStr = id.uuidString.lowercased()
        let softDeletePayload: [String: Any] = [
            "is_deleted": true,
            "updated_at": NetworkManager.iso8601.string(from: Date())
        ]
        var supabaseSuccess = false
        do {
            _ = try await sendSupabaseRequest(
                method: "PATCH",
                endpoint: "tips",
                queryItems: [URLQueryItem(name: "id", value: "eq.\(idStr)")],
                payload: softDeletePayload
            )
            supabaseSuccess = true
        } catch {
            print("NetworkManager: Supabase tip soft-delete failed: \(error.localizedDescription)")
        }
        return supabaseSuccess
    }

    // MARK: - Cash Movements Sync
    func fetchCashMovementsFromSupabase() async throws -> [[String: Any]] {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        let data = try await sendSupabaseRequest(
            method: "GET",
            endpoint: "cash_movements",
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)"),
                URLQueryItem(name: "is_deleted", value: "eq.false")
            ]
        )
        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw NetworkError.invalidResponse
        }
        return jsonArray
    }

    func uploadCashMovement(_ movement: RemoteCashMovementUploadable) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId

        let sessionId = movement.registerSession?.id.uuidString.lowercased() ?? ""
        var payload: [String: Any] = [
            "id": movement.id.uuidString.lowercased(),
            "merchant_id": merchantId,
            "register_session_id": sessionId,
            "movement_type": movement.movementType,
            "amount": movement.amount,
            "reason": movement.reason,
            "is_deleted": movement.isDeleted,
            "updated_at": NetworkManager.iso8601.string(from: movement.updatedAt)
        ]

        if let employeeId = movement.performedByEmployeeId {
            payload["performed_by_employee_id"] = employeeId.uuidString.lowercased()
        }

        var supabaseSuccess = false
        do {
            _ = try await sendSupabaseRequest(
                method: "POST",
                endpoint: "cash_movements",
                queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
                payload: payload
            )
            supabaseSuccess = true
        } catch {
            print("NetworkManager: Supabase cash movement upload failed: \(error.localizedDescription)")
        }
        return supabaseSuccess
    }

    func deleteCashMovementOnServer(id: UUID) async throws -> Bool {
        let idStr = id.uuidString.lowercased()
        let softDeletePayload: [String: Any] = [
            "is_deleted": true,
            "updated_at": NetworkManager.iso8601.string(from: Date())
        ]
        var supabaseSuccess = false
        do {
            _ = try await sendSupabaseRequest(
                method: "PATCH",
                endpoint: "cash_movements",
                queryItems: [URLQueryItem(name: "id", value: "eq.\(idStr)")],
                payload: softDeletePayload
            )
            supabaseSuccess = true
        } catch {
            print("NetworkManager: Supabase cash movement soft-delete failed: \(error.localizedDescription)")
        }
        return supabaseSuccess
    }

    // MARK: - Master Data Sync

    private func fetchMasterData(endpoint: String) async throws -> [[String: Any]] {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        let data = try await sendSupabaseRequest(
            method: "GET",
            endpoint: endpoint,
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)"),
                URLQueryItem(name: "is_deleted", value: "eq.false")
            ]
        )
        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw NetworkError.invalidResponse
        }
        return jsonArray
    }

    private func softDeleteMasterData(endpoint: String, id: UUID) async throws -> Bool {
        let payload: [String: Any] = [
            "is_deleted": true,
            "updated_at": NetworkManager.iso8601.string(from: Date())
        ]
        _ = try await sendSupabaseRequest(
            method: "PATCH",
            endpoint: endpoint,
            queryItems: [URLQueryItem(name: "id", value: "eq.\(id.uuidString.lowercased())")],
            payload: payload
        )
        return true
    }

    func fetchCategoriesFromSupabase() async throws -> [[String: Any]] {
        try await fetchMasterData(endpoint: "categories")
    }

    func uploadCategory(_ category: Category) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        var payload: [String: Any] = [
            "id": category.id.uuidString.lowercased(),
            "merchant_id": merchantId,
            "name": category.name,
            "is_deleted": category.isDeleted,
            "updated_at": NetworkManager.iso8601.string(from: category.updatedAt)
        ]
        if let description = category.categoryDescription {
            payload["description"] = description
        }
        if let imageUrl = category.imageUrl {
            payload["image_url"] = imageUrl
        }

        do {
            _ = try await sendSupabaseRequest(
                method: "POST",
                endpoint: "categories",
                queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
                payload: payload
            )
        } catch {
            if let description = payload.removeValue(forKey: "description") {
                payload["category_description"] = description
                _ = try await sendSupabaseRequest(
                    method: "POST",
                    endpoint: "categories",
                    queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
                    payload: payload
                )
            } else {
                throw error
            }
        }
        return true
    }

    func deleteCategoryOnServer(id: UUID) async throws -> Bool {
        try await softDeleteMasterData(endpoint: "categories", id: id)
    }

    func fetchInventoryItemsFromSupabase() async throws -> [[String: Any]] {
        try await fetchMasterData(endpoint: "inventory_items")
    }

    func uploadInventoryItem(_ item: InventoryItem) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        var payload: [String: Any] = [
            "id": item.id.uuidString.lowercased(),
            "merchant_id": merchantId,
            "name": item.name,
            "unit": item.unit,
            "current_quantity": item.currentQuantity,
            "reorder_level": item.reorderLevel,
            "cost_price": item.costPrice,
            "is_deleted": item.isDeleted,
            "updated_at": NetworkManager.iso8601.string(from: item.updatedAt)
        ]
        if let sku = item.sku { payload["sku"] = sku }
        if let supplierId = item.supplier?.id.uuidString.lowercased() { payload["supplier_id"] = supplierId }
        if let branchId = item.branch?.id.uuidString.lowercased() { payload["branch_id"] = branchId }
        if let category = item.category { payload["category"] = category }
        if let storageLocation = item.storageLocation { payload["storage_location"] = storageLocation }
        if let barcode = item.barcode { payload["barcode"] = barcode }

        _ = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "inventory_items",
            queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
            payload: payload
        )
        return true
    }

    func deleteInventoryItemOnServer(id: UUID) async throws -> Bool {
        try await softDeleteMasterData(endpoint: "inventory_items", id: id)
    }

    func fetchModifierGroupsFromSupabase() async throws -> [[String: Any]] {
        try await fetchMasterData(endpoint: "modifier_groups")
    }

    func uploadModifierGroup(_ group: ModifierGroup) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        let payload: [String: Any] = [
            "id": group.id.uuidString.lowercased(),
            "merchant_id": merchantId,
            "name": group.name,
            "min_selection": group.minSelection,
            "max_selection": group.maxSelection,
            "is_deleted": group.isDeleted,
            "updated_at": NetworkManager.iso8601.string(from: group.updatedAt)
        ]
        _ = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "modifier_groups",
            queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
            payload: payload
        )
        return true
    }

    func deleteModifierGroupOnServer(id: UUID) async throws -> Bool {
        try await softDeleteMasterData(endpoint: "modifier_groups", id: id)
    }

    func fetchModifiersFromSupabase() async throws -> [[String: Any]] {
        try await fetchMasterData(endpoint: "modifiers")
    }

    func uploadModifier(_ modifier: Modifier) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        var payload: [String: Any] = [
            "id": modifier.id.uuidString.lowercased(),
            "merchant_id": merchantId,
            "name": modifier.name,
            "extra_price": modifier.extraPrice,
            "is_available": modifier.isAvailable,
            "is_deleted": modifier.isDeleted,
            "updated_at": NetworkManager.iso8601.string(from: modifier.updatedAt)
        ]
        if let groupId = modifier.modifierGroup?.id.uuidString.lowercased() { payload["modifier_group_id"] = groupId }
        if let itemId = modifier.inventoryItemLink?.id.uuidString.lowercased() { payload["inventory_item_id"] = itemId }
        if let quantityRequired = modifier.quantityRequired { payload["quantity_required"] = quantityRequired }

        _ = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "modifiers",
            queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
            payload: payload
        )
        return true
    }

    func deleteModifierOnServer(id: UUID) async throws -> Bool {
        try await softDeleteMasterData(endpoint: "modifiers", id: id)
    }

    func fetchMenuItemModifierGroupsFromSupabase() async throws -> [[String: Any]] {
        try await fetchMasterData(endpoint: "menu_item_modifier_groups")
    }

    func uploadMenuItemModifierGroup(_ relation: MenuItemModifierGroup) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        guard let menuItemId = relation.menuItem?.id.lowercased(),
              let modifierGroupId = relation.modifierGroup?.id.uuidString.lowercased() else {
            throw NetworkError.serverError("Menu item modifier group relation requires both sides.")
        }

        let payload: [String: Any] = [
            "menu_item_id": menuItemId,
            "modifier_group_id": modifierGroupId,
            "merchant_id": merchantId,
            "is_deleted": relation.isDeleted,
            "updated_at": NetworkManager.iso8601.string(from: relation.updatedAt)
        ]
        _ = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "menu_item_modifier_groups",
            queryItems: [URLQueryItem(name: "on_conflict", value: "menu_item_id,modifier_group_id")],
            payload: payload
        )
        return true
    }

    func deleteMenuItemModifierGroupOnServer(menuItemId: String, modifierGroupId: UUID) async throws -> Bool {
        let payload: [String: Any] = [
            "is_deleted": true,
            "updated_at": NetworkManager.iso8601.string(from: Date())
        ]
        _ = try await sendSupabaseRequest(
            method: "PATCH",
            endpoint: "menu_item_modifier_groups",
            queryItems: [
                URLQueryItem(name: "menu_item_id", value: "eq.\(menuItemId.lowercased())"),
                URLQueryItem(name: "modifier_group_id", value: "eq.\(modifierGroupId.uuidString.lowercased())")
            ],
            payload: payload
        )
        return true
    }

    // MARK: - Loyalty Transactions Sync
    func fetchLoyaltyTransactionsFromSupabase() async throws -> [[String: Any]] {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        let data = try await sendSupabaseRequest(
            method: "GET",
            endpoint: "loyalty_transactions",
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)"),
                URLQueryItem(name: "is_deleted", value: "eq.false")
            ]
        )
        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw NetworkError.invalidResponse
        }
        return jsonArray
    }

    func uploadLoyaltyTransaction(_ transaction: RemoteLoyaltyTransactionUploadable) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        guard let customerId = transaction.customer?.id.uuidString.lowercased() else {
            throw NetworkError.serverError("Loyalty transaction requires a customer.")
        }

        var payload: [String: Any] = [
            "id": transaction.id.uuidString.lowercased(),
            "merchant_id": merchantId,
            "customer_id": customerId,
            "transaction_type": transaction.transactionType,
            "points": transaction.points,
            "points_balance_after": transaction.pointsBalanceAfter,
            "is_deleted": transaction.isDeleted,
            "updated_at": NetworkManager.iso8601.string(from: transaction.updatedAt)
        ]

        if let orderId = transaction.order?.id.uuidString.lowercased() {
            payload["order_id"] = orderId
        }
        if let description = transaction.transactionDescription {
            payload["description"] = description
        }

        var supabaseSuccess = false
        do {
            _ = try await sendSupabaseRequest(
                method: "POST",
                endpoint: "loyalty_transactions",
                queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
                payload: payload
            )
            supabaseSuccess = true
        } catch {
            print("NetworkManager: Supabase loyalty transaction upload failed: \(error.localizedDescription)")
        }
        return supabaseSuccess
    }

    func deleteLoyaltyTransactionOnServer(id: UUID) async throws -> Bool {
        let idStr = id.uuidString.lowercased()
        let softDeletePayload: [String: Any] = [
            "is_deleted": true,
            "updated_at": NetworkManager.iso8601.string(from: Date())
        ]
        var supabaseSuccess = false
        do {
            _ = try await sendSupabaseRequest(
                method: "PATCH",
                endpoint: "loyalty_transactions",
                queryItems: [URLQueryItem(name: "id", value: "eq.\(idStr)")],
                payload: softDeletePayload
            )
            supabaseSuccess = true
        } catch {
            print("NetworkManager: Supabase loyalty transaction soft-delete failed: \(error.localizedDescription)")
        }
        return supabaseSuccess
    }

    // MARK: - Gift Cards Sync
    func fetchGiftCardsFromSupabase() async throws -> [[String: Any]] {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        let data = try await sendSupabaseRequest(
            method: "GET",
            endpoint: "gift_cards",
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)"),
                URLQueryItem(name: "is_deleted", value: "eq.false")
            ]
        )
        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw NetworkError.invalidResponse
        }
        return jsonArray
    }

    func uploadGiftCard(_ giftCard: RemoteGiftCardUploadable) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        var payload: [String: Any] = [
            "id": giftCard.id.uuidString.lowercased(),
            "merchant_id": merchantId,
            "card_number": giftCard.cardNumber,
            "balance": giftCard.balance,
            "initial_value": giftCard.initialValue,
            "status": giftCard.status,
            "is_deleted": giftCard.isDeleted,
            "updated_at": NetworkManager.iso8601.string(from: giftCard.updatedAt)
        ]

        if let customerId = giftCard.customer?.id.uuidString.lowercased() {
            payload["customer_id"] = customerId
        }
        if let expiresAt = giftCard.expiresAt {
            payload["expires_at"] = NetworkManager.iso8601.string(from: expiresAt)
        }

        var supabaseSuccess = false
        do {
            _ = try await sendSupabaseRequest(
                method: "POST",
                endpoint: "gift_cards",
                queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
                payload: payload
            )
            supabaseSuccess = true
        } catch {
            print("NetworkManager: Supabase gift card upload failed: \(error.localizedDescription)")
        }
        return supabaseSuccess
    }

    func deleteGiftCardOnServer(id: UUID) async throws -> Bool {
        let idStr = id.uuidString.lowercased()
        let softDeletePayload: [String: Any] = [
            "is_deleted": true,
            "updated_at": NetworkManager.iso8601.string(from: Date())
        ]
        var supabaseSuccess = false
        do {
            _ = try await sendSupabaseRequest(
                method: "PATCH",
                endpoint: "gift_cards",
                queryItems: [URLQueryItem(name: "id", value: "eq.\(idStr)")],
                payload: softDeletePayload
            )
            supabaseSuccess = true
        } catch {
            print("NetworkManager: Supabase gift card soft-delete failed: \(error.localizedDescription)")
        }
        return supabaseSuccess
    }
}
