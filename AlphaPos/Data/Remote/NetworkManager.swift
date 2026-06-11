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

final class NetworkManager {
    static let shared = NetworkManager()
    private let config = AppConfig.shared
    
    // Configurable endpoint pointing directly to Supabase REST API
    lazy var serverBaseURL: URL = config.supabaseRestURL
    private lazy var anonKey: String = config.supabaseAnonKey
    
    // Simulator states
    var simulateOffline = false
    
    var isWebOrderingEnabled: Bool {
        UserDefaults.standard.object(forKey: "enable_web_ordering") as? Bool ?? true
    }
    
    private init() {}
    
    func isConnected() async -> Bool {
        guard isWebOrderingEnabled else { return false }
        if simulateOffline { return false }
        
        // Quick ping check to Supabase menu_items REST endpoint
        var request = URLRequest(url: serverBaseURL.appendingPathComponent("menu_items"))
        request.httpMethod = "HEAD"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        if !merchantId.isEmpty {
            request.setValue(merchantId, forHTTPHeaderField: "x-merchant-id")
        }
        
        request.timeoutInterval = 1.5
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
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
        guard isWebOrderingEnabled else {
            throw NetworkError.offline
        }
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
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
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
        let data = try await sendSupabaseRequest(method: "GET", endpoint: "orders", queryItems: [
            URLQueryItem(name: "select", value: "*,order_items(*),payments(*)")
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
            "table_number": order.tableSession?.table?.tableNumber ?? "12",
            "total": order.total,
            "status": order.status,
            "created_at": ISO8601DateFormatter().string(from: order.createdAt),
            "updated_at": ISO8601DateFormatter().string(from: order.updatedAt),
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
            let itemPayload: [String: Any] = [
                "id": item.id.uuidString,
                "order_id": order.id.uuidString,
                "item_name": item.menuItem?.name ?? "Unknown Item",
                "quantity": item.quantity,
                "price": item.unitPrice,
                "status": item.status,
                "item_id": item.menuItem?.id.lowercased() ?? "",
                "merchant_id": merchantId,
                "created_at": ISO8601DateFormatter().string(from: Date())
            ]
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
            "created_at": ISO8601DateFormatter().string(from: Date()),
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
    
    func uploadPayment(id: UUID, orderId: UUID?, amount: Double, method: String) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        let payload: [String: Any] = [
            "id": id.uuidString,
            "order_id": orderId?.uuidString ?? "",
            "amount": amount,
            "payment_method": method,
            "created_at": ISO8601DateFormatter().string(from: Date()),
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
    
    func uploadTimecard(id: UUID, employeeId: UUID, employeeName: String, clockIn: Date, clockOut: Date?, status: String, breakDuration: Int = 0, overtimeMinutes: Int = 0, notes: String? = nil, clockInConfidence: Double? = nil, clockOutConfidence: Double? = nil) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        let formatter = ISO8601DateFormatter()
        var payload: [String: Any] = [
            "id": id.uuidString,
            "employee_id": employeeId.uuidString,
            "employee_name": employeeName,
            "clock_in": formatter.string(from: clockIn),
            "break_duration": breakDuration,
            "overtime_minutes": overtimeMinutes,
            "status": status,
            "merchant_id": merchantId
        ]
        if let notes = notes {
            payload["notes"] = notes
        }
        if let clockInConfidence = clockInConfidence {
            payload["clock_in_confidence"] = clockInConfidence
        }
        if let clockOutConfidence = clockOutConfidence {
            payload["clock_out_confidence"] = clockOutConfidence
        }
        if let clockOut = clockOut {
            payload["clock_out"] = formatter.string(from: clockOut)
        } else {
            payload["clock_out"] = NSNull()
        }
        _ = try await sendSupabaseRequest(method: "POST", endpoint: "timecards", payload: payload)
        return true
    }
    
    func uploadInventoryTransaction(id: UUID, itemName: String, quantity: Double, type: String) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        let payload: [String: Any] = [
            "id": id.uuidString.lowercased(),
            "merchant_id": merchantId,
            "item_name": itemName,
            "quantity": quantity,
            "type": type,
            "created_at": ISO8601DateFormatter().string(from: Date())
        ]
        _ = try await sendSupabaseRequest(method: "POST", endpoint: "inventory_transactions", payload: payload)
        return true
    }
    
    func fetchRestaurantTables() async throws -> [[String: Any]] {
        let data = try await sendSupabaseRequest(method: "GET", endpoint: "restaurant_tables")
        return (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
    }
    
    func uploadRestaurantTable(table: RestaurantTable) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        let formatter = ISO8601DateFormatter()
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
            "updated_at": formatter.string(from: table.updatedAt)
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
    
    func uploadTableSession(session: TableSession) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        let formatter = ISO8601DateFormatter()
        var payload: [String: Any] = [
            "id": session.id.uuidString.lowercased(),
            "table_number": session.table?.tableNumber ?? "",
            "session_token": session.sessionToken,
            "is_active": session.isActive ? 1 : 0,
            "guest_count": session.guestCount,
            "created_at": formatter.string(from: session.startedAt),
            "merchant_id": merchantId
        ]
        
        if let endedAt = session.endedAt {
            payload["ended_at"] = formatter.string(from: endedAt)
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
        let pinCode = employee.user?.pinCodeHash ?? "0000"
        let role = employee.user?.role?.name ?? "Staff"
        
        let payload: [String: Any] = [
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
            "role": role
        ]
        
        _ = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "employees",
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
        phone: String? = nil,
        website: String? = nil,
        address: String? = nil,
        taxId: String? = nil,
        branchCode: String? = nil,
        taxRate: Double? = nil,
        taxType: String? = nil,
        serviceChargeRate: Double? = nil,
        receiptHeader: String? = nil,
        receiptFooter: String? = nil
    ) async throws -> Bool {
        var payload: [String: Any] = [
            "id": id.uuidString.lowercased(),
            "name": name,
            "email": email,
            "kitchen_workflow_required": kitchenWorkflowRequired
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
        
        let payload: [String: Any] = [
            "id": item.id.lowercased(),
            "name": item.name,
            "description": item.itemDescription ?? "",
            "price": item.price,
            "category": catSlug,
            "emoji": defaultEmoji(for: catSlug),
            "img_class": catSlug,
            "merchant_id": merchantId,
            "image_url": item.imageUrl ?? ""
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
        let data = try await sendSupabaseRequest(
            method: "GET",
            endpoint: "menu_items",
            queryItems: [URLQueryItem(name: "select", value: "*")]
        )
        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw NetworkError.invalidResponse
        }
        return jsonArray
    }
    
    /// Fetches all active (non-deleted) promotions for the active merchant from Supabase.
    func fetchPromotionsFromSupabase() async throws -> [[String: Any]] {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        let data = try await sendSupabaseRequest(
            method: "GET",
            endpoint: "promotions",
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)"),
                URLQueryItem(name: "is_deleted", value: "eq.0")
            ]
        )
        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw NetworkError.invalidResponse
        }
        return jsonArray
    }
    
    func uploadPromotion(promotion: Promotion) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        let formatter = ISO8601DateFormatter()
        let payload: [String: Any] = [
            "id": promotion.id.uuidString.lowercased(),
            "merchant_id": merchantId,
            "title": promotion.title,
            "promo_description": promotion.promoDescription ?? "",
            "image_data": promotion.imageData ?? "",
            "is_active": promotion.isActive ? 1 : 0,
            "is_deleted": promotion.isDeleted ? 1 : 0,
            "updated_at": formatter.string(from: promotion.updatedAt)
        ]
        
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
        
        var localSuccess = false
        if let localURL = URL(string: "http://127.0.0.1:8080/v1/promotions") {
            var req = URLRequest(url: localURL)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.timeoutInterval = 1.5
            do {
                req.httpBody = try JSONSerialization.data(withJSONObject: payload)
                let (_, response) = try await URLSession.shared.data(for: req)
                if let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) {
                    localSuccess = true
                }
            } catch {
                print("NetworkManager: Local server promotion upload failed: \(error.localizedDescription)")
            }
        }
        
        return supabaseSuccess || localSuccess
    }
    
    // MARK: - Purchase Orders Sync
    
    /// Upserts a PurchaseOrder header and all its items to Supabase in a single sync call.
    /// Items are batch-upserted using on_conflict=id for idempotency.
    func uploadPurchaseOrder(purchaseOrder: PurchaseOrder) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        let formatter = ISO8601DateFormatter()
        
        // 1. Upsert PO header
        var poPayload: [String: Any] = [
            "id": purchaseOrder.id.uuidString.lowercased(),
            "merchant_id": merchantId,
            "po_number": purchaseOrder.poNumber,
            "status": purchaseOrder.status,
            "order_date": formatter.string(from: purchaseOrder.orderDate),
            "notes": purchaseOrder.notes ?? "",
            "is_synced": true,
            "is_deleted": purchaseOrder.isDeleted,
            "updated_at": formatter.string(from: purchaseOrder.updatedAt)
        ]
        if let supplierId = purchaseOrder.supplier?.id {
            poPayload["supplier_id"] = supplierId.uuidString.lowercased()
        }
        if let branchId = purchaseOrder.branch?.id {
            poPayload["branch_id"] = branchId.uuidString.lowercased()
        }
        if let deliveryDate = purchaseOrder.deliveryDate {
            poPayload["delivery_date"] = formatter.string(from: deliveryDate)
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
                    "updated_at": formatter.string(from: item.updatedAt)
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
        let formatter = ISO8601DateFormatter()
        // Soft-delete: PATCH is_deleted=true so RLS (which allows PATCH but may block DELETE)
        // works correctly. fetchPromotionsFromSupabase already filters is_deleted=eq.false.
        let softDeletePayload: [String: Any] = [
            "is_deleted": 1,
            "updated_at": formatter.string(from: Date())
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
        
        let legacyPayload = ["id": idStr]
        if let localURL = URL(string: "http://127.0.0.1:8080/v1/promotions/delete") {
            var req = URLRequest(url: localURL)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.timeoutInterval = 1.5
            do {
                req.httpBody = try JSONSerialization.data(withJSONObject: legacyPayload)
                let (_, response) = try await URLSession.shared.data(for: req)
                if let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) {
                }
            } catch {
                print("NetworkManager: Local server promotion delete failed: \(error.localizedDescription)")
            }
        }
        
        return supabaseSuccess
    }
    
    // MARK: - Printers & Routing Rules Sync
    
    func uploadPrinter(_ printer: Printer) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        let formatter = ISO8601DateFormatter()
        
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
            "updated_at": formatter.string(from: printer.updatedAt)
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
        let formatter = ISO8601DateFormatter()
        
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
            "updated_at": formatter.string(from: rule.updatedAt)
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
}
