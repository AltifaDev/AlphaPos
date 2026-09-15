// NetworkService+Orders.swift
// Orders, order items, sessions, payments, checkout, and service requests.

import Foundation

extension NetworkService {
    func fetchRequests() async throws -> [ServiceRequest] {
        let data = try await sendSupabaseRequest(method: "GET", endpoint: "service_requests", queryItems: [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "status", value: "eq.pending"),
            URLQueryItem(name: "created_at", value: "gte.\(StaffNotificationPolicy.currentBusinessDayStart())"),
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

    func fetchTableOrders(
        tableNumber: String,
        activeSessionId: String?,
        sessionToken: String?,
        sessionStartedAt: String?
    ) async throws -> [Order] {
        if let id = activeSessionId, !id.isEmpty {
            do {
                let bundleData = try await sendSupabaseRequest(
                    method: "POST",
                    endpoint: "rpc/get_table_order_bundle",
                    payload: [
                        "p_table_session_id": id,
                        "p_branch_id": StaffSessionContext.branchId
                    ]
                )
                guard let bundle = try JSONSerialization.jsonObject(with: bundleData) as? [String: Any],
                      bundle["contract_version"] as? Int == 1,
                      let rows = bundle["orders"] as? [[String: Any]] else {
                    throw NetworkError.invalidResponse
                }
                return try await parseOrders(rows)
            } catch let error as StaffHTTPError where error.statusCode == 404 {
                // Rolling deployment: old servers may not have the RPC yet.
            }
        }

        // A table number is reusable and therefore never an order-session boundary.
        // Scope to the canonical table_session_id, with narrow compatibility paths
        // for legacy rows created before that column was populated.
        var queryItems = [
            URLQueryItem(name: "select", value: "*,order_items(*,order_item_modifiers(id,price,modifiers(name))),payments(id,amount,payment_method,status,created_at)"),
            URLQueryItem(name: "merchant_id", value: "eq.\(activeMerchantId)"),
            URLQueryItem(name: "branch_id", value: "eq.\(StaffSessionContext.branchId)"),
            URLQueryItem(name: "table_number", value: "eq.\(tableNumber)"),
            URLQueryItem(name: "status", value: "in.(preparing,ready,served,completed,pending)"),
            URLQueryItem(name: "order", value: "created_at.asc")
        ]
        if let id = activeSessionId, !id.isEmpty {
            // Current web/POS orders always carry the canonical session UUID.
            // Query it directly: embedding legacy timestamp/token fallbacks in a
            // PostgREST `or` expression made one malformed device timestamp turn
            // the entire order request into HTTP 400.
            queryItems.append(URLQueryItem(name: "table_session_id", value: "eq.\(id)"))
        } else if let token = sessionToken, !token.isEmpty {
            queryItems.append(URLQueryItem(name: "session_token", value: "eq.\(token)"))
        } else if let startedAt = sessionStartedAt, !startedAt.isEmpty {
            queryItems.append(URLQueryItem(name: "created_at", value: "gte.\(startedAt)"))
        } else {
            // Fail closed: without a session boundary, showing no orders is safer
            // than leaking a previous party's bill into a newly opened table.
            return []
        }
        let primary = try await fetchTableOrderRows(queryItems: queryItems)
        if !primary.isEmpty || activeSessionId == nil {
            return try await parseOrders(primary)
        }

        // Compatibility for old orders created before table_session_id was
        // populated. Keep each fallback as a simple filter so a bad legacy
        // timestamp cannot prevent canonical orders from loading.
        if let token = sessionToken, !token.isEmpty {
            var legacyTokenQuery = Array(queryItems.dropLast())
            legacyTokenQuery.append(URLQueryItem(name: "table_session_id", value: "is.null"))
            legacyTokenQuery.append(URLQueryItem(name: "session_token", value: "eq.\(token)"))
            let legacy = try await fetchTableOrderRows(queryItems: legacyTokenQuery)
            if !legacy.isEmpty { return try await parseOrders(legacy) }
        }
        if let startedAt = sessionStartedAt, !startedAt.isEmpty {
            var legacyDateQuery = Array(queryItems.dropLast())
            legacyDateQuery.append(URLQueryItem(name: "table_session_id", value: "is.null"))
            legacyDateQuery.append(URLQueryItem(name: "session_token", value: "is.null"))
            legacyDateQuery.append(URLQueryItem(name: "created_at", value: "gte.\(startedAt)"))
            let legacy = try await fetchTableOrderRows(queryItems: legacyDateQuery)
            if !legacy.isEmpty { return try await parseOrders(legacy) }
        }
        return []
    }

    private func fetchTableOrderRows(queryItems: [URLQueryItem]) async throws -> [[String: Any]] {
        var requestQuery = queryItems
        let ordersData: Data
        do {
            ordersData = try await sendSupabaseRequest(method: "GET", endpoint: "orders", queryItems: requestQuery)
        } catch {
            // An optional embedded relation may be absent while PostgREST reloads
            // its schema cache. Fetch the order row and load items separately.
            requestQuery[0] = URLQueryItem(name: "select", value: "*")
            ordersData = try await sendSupabaseRequest(method: "GET", endpoint: "orders", queryItems: requestQuery)
        }
        return (try? JSONSerialization.jsonObject(with: ordersData) as? [[String: Any]]) ?? []
    }

    private func parseOrderItems(_ jsonArray: [[String: Any]]) -> [OrderItem] {
        jsonArray.compactMap { itemDict in
            // Cancellation is a soft delete so inventory and audit history stay
            // intact. Never render those rows back into an active ticket.
            if itemDict["is_deleted"] as? Bool == true { return nil }
            return OrderItem(
                id: itemDict["id"] as? String ?? "",
                name: itemDict["item_name"] as? String ?? "",
                quantity: itemDict["quantity"] as? Int ?? 1,
                price: itemDict["price"] as? Double ?? 0.0,
                status: itemDict["status"] as? String ?? "cooking",
                item_id: itemDict["item_id"] as? String,
                notes: itemDict["notes"] as? String,
                servedBy: itemDict["served_by"] as? String,
                modifiers: parseOrderItemModifiers(itemDict["order_item_modifiers"] as? [[String: Any]] ?? []),
                rowVersion: itemDict["row_version"] as? Int
            )
        }
    }

    /// PATCH with row_version guard. Empty representation ⇒ concurrent edit conflict.
    private func patchWithVersion(
        endpoint: String,
        id: String,
        payload: [String: Any],
        expectedRowVersion: Int?
    ) async throws {
        var queryItems = [URLQueryItem(name: "id", value: "eq.\(id)")]
        if let version = expectedRowVersion {
            queryItems.append(URLQueryItem(name: "row_version", value: "eq.\(version)"))
        }
        let data = try await sendSupabaseRequest(
            method: "PATCH",
            endpoint: endpoint,
            queryItems: queryItems,
            payload: payload
        )
        if expectedRowVersion != nil {
            let rows = (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
            if rows.isEmpty {
                throw NetworkError.conflict("\(endpoint) id=\(id) was modified by another device")
            }
        }
    }

    /// Parse nested `order_item_modifiers(id,price,modifiers(name))` join into display models.
    private func parseOrderItemModifiers(_ jsonArray: [[String: Any]]) -> [OrderItemModifier] {
        jsonArray.compactMap { modDict in
            // Skip soft-deleted rows if the flag is present
            if let deleted = modDict["is_deleted"] as? Bool, deleted { return nil }
            let nested = modDict["modifiers"] as? [String: Any]
            let name = (nested?["name"] as? String)
                ?? (modDict["name"] as? String)
                ?? ""
            guard !name.isEmpty else { return nil }
            return OrderItemModifier(
                id: modDict["id"] as? String ?? UUID().uuidString,
                name: name,
                price: modDict["price"] as? Double ?? 0.0
            )
        }
    }

    private func fetchOrderItems(orderId: String) async throws -> [OrderItem] {
        let itemsData = try await sendSupabaseRequest(method: "GET", endpoint: "order_items", queryItems: [
            // Keep this query independent of optional nested relations. A
            // schema-cache problem in modifiers must not hide the whole order.
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "order_id", value: "eq.\(orderId)"),
            URLQueryItem(name: "merchant_id", value: "eq.\(activeMerchantId)"),
            URLQueryItem(name: "branch_id", value: "eq.\(StaffSessionContext.branchId)"),
            URLQueryItem(name: "order", value: "created_at.asc")
        ])
        let itemsArray = (try? JSONSerialization.jsonObject(with: itemsData) as? [[String: Any]]) ?? []
        return parseOrderItems(itemsArray)
    }

    private func parseOrders(_ jsonArray: [[String: Any]]) async throws -> [Order] {
        var parsed: [Order] = []

        for dict in jsonArray {
            let orderId = dict["id"] as? String ?? ""
            var items = parseOrderItems(dict["order_items"] as? [[String: Any]] ?? [])
            let payments = parseOrderPayments(dict["payments"] as? [[String: Any]] ?? [])
            // Fallback: joined query อาจไม่มี items ถ้า PostgREST cache หรือ replication lag
            // fetch order_items แยกทันที (ไม่ต้อง sleep เพราะ uploadOrder ส่ง concurrent แล้ว)
            if items.isEmpty && !orderId.isEmpty {
                items = try await fetchOrderItems(orderId: orderId)
            }

            parsed.append(Order(
                id: orderId,
                orderNumber: dict["order_number"] as? String ?? "",
                tableNumber: dict["table_number"] as? String ?? "",
                total: dict["total"] as? Double ?? 0.0,
                status: dict["status"] as? String ?? "preparing",
                createdAt: Self.timestampString(dict["created_at"]),
                items: items,
                tableSessionId: dict["table_session_id"] as? String,
                sessionToken: dict["session_token"] as? String,
                payments: payments,
                orderSource: dict["order_source"] as? String ?? "pos",
                isStaffConfirmed: dict["is_staff_confirmed"] as? Bool
                    ?? ((dict["order_source"] as? String) != "web"),
                rowVersion: dict["row_version"] as? Int,
                orderType: dict["order_type"] as? String ?? "dine_in",
                queueNumber: Self.queueNumberString(dict["queue_number"]),
                receiptNumber: dict["receipt_number"] as? String,
                deliveryBrand: dict["delivery_brand"] as? String,
                platformOrderNumber: dict["platform_order_number"] as? String
            ))
        }

        return parsed
    }

    /// queue_number may be INTEGER or VARCHAR depending on migration history.
    private static func queueNumberString(_ value: Any?) -> String? {
        if let string = value as? String, !string.isEmpty { return string }
        if let int = value as? Int { return NetworkService.formatQueueNumber(int) }
        if let double = value as? Double { return NetworkService.formatQueueNumber(Int(double)) }
        return nil
    }

    /// PostgREST timestamps are strings; coerce defensively so we never drop created_at.
    private static func timestampString(_ value: Any?) -> String {
        if let string = value as? String { return string }
        if let date = value as? Date {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.string(from: date)
        }
        return ""
    }

    func fetchAllActiveOrders() async throws -> [Order] {
        let ordersData = try await sendSupabaseRequest(method: "GET", endpoint: "orders", queryItems: [
            URLQueryItem(name: "select", value: "*,order_items(*,order_item_modifiers(id,price,modifiers(name))),payments(id,amount,payment_method,status,created_at)"),
            // Keep served orders from prior business days when they are still
            // unpaid. A served bill must remain recoverable until settlement;
            // filtering by business-day silently made iPhone and iPad disagree.
            URLQueryItem(name: "status", value: "in.(preparing,ready,served,pending)"),
            URLQueryItem(name: "order", value: "created_at.desc"),
            URLQueryItem(name: "limit", value: "500")
        ])
        let jsonArray = (try? JSONSerialization.jsonObject(with: ordersData) as? [[String: Any]]) ?? []
        return try await parseOrders(jsonArray).filter { !$0.isPaid }
    }

    func fetchOrderById(_ orderId: String) async throws -> Order? {
        let ordersData = try await sendSupabaseRequest(method: "GET", endpoint: "orders", queryItems: [
            URLQueryItem(name: "select", value: "*,order_items(*,order_item_modifiers(id,price,modifiers(name))),payments(id,amount,payment_method,status,created_at)"),
            URLQueryItem(name: "id", value: "eq.\(orderId)")
        ])
        let jsonArray = (try? JSONSerialization.jsonObject(with: ordersData) as? [[String: Any]]) ?? []
        guard let dict = jsonArray.first else { return nil }
        var items = parseOrderItems(dict["order_items"] as? [[String: Any]] ?? [])
        if items.isEmpty {
            items = try await fetchOrderItems(orderId: orderId)
        }
        return Order(
            id: dict["id"] as? String ?? "",
            orderNumber: dict["order_number"] as? String ?? "",
            tableNumber: dict["table_number"] as? String ?? "",
            total: dict["total"] as? Double ?? 0.0,
            status: dict["status"] as? String ?? "preparing",
            createdAt: Self.timestampString(dict["created_at"]),
            items: items,
            tableSessionId: dict["table_session_id"] as? String,
            sessionToken: dict["session_token"] as? String,
            payments: parseOrderPayments(dict["payments"] as? [[String: Any]] ?? []),
            orderSource: dict["order_source"] as? String ?? "pos",
            isStaffConfirmed: dict["is_staff_confirmed"] as? Bool
                ?? ((dict["order_source"] as? String) != "web"),
            rowVersion: dict["row_version"] as? Int,
            orderType: dict["order_type"] as? String ?? "dine_in",
            queueNumber: Self.queueNumberString(dict["queue_number"]),
            receiptNumber: dict["receipt_number"] as? String,
            deliveryBrand: dict["delivery_brand"] as? String,
            platformOrderNumber: dict["platform_order_number"] as? String
        )
    }

    private func parseOrderPayments(_ jsonArray: [[String: Any]]) -> [OrderPayment] {
        jsonArray.map { dict in
            OrderPayment(
                id: dict["id"] as? String ?? UUID().uuidString,
                amount: dict["amount"] as? Double ?? 0,
                method: dict["payment_method"] as? String ?? "",
                status: dict["status"] as? String ?? "",
                createdAt: dict["created_at"] as? String
            )
        }
    }

    // POST triggers
    func openSession(tableNumber: String, guestCount: Int) async throws -> Bool {
        let merchantId = self.activeMerchantId
        let branchId = StaffSessionContext.branchId
        guard !merchantId.isEmpty else { throw StaffServiceError.missingMerchantSession }
        guard !branchId.isEmpty else { throw StaffServiceError.missingBranchSession }
        let payload: [String: Any] = [
            "id": UUID().uuidString,
            "table_number": tableNumber,
            "session_token": UUID().uuidString,
            "is_active": 1,
            "guest_count": guestCount,
            "created_at": ISO8601DateFormatter().string(from: Date()),
            "merchant_id": merchantId,
            "branch_id": branchId
        ]
        _ = try await sendSupabaseRequest(
            method: "POST", endpoint: "rpc/upsert_table_session_cas",
            payload: ["p_session": payload]
        )
        await refreshAll()
        return true
    }

    func closeSession(tableNumber: String) async throws -> Bool {
        let merchantId = self.activeMerchantId
        let branchId = StaffSessionContext.branchId
        guard !merchantId.isEmpty else {
            throw NetworkError.serverError("No active merchant configured")
        }
        guard !branchId.isEmpty else { throw StaffServiceError.missingBranchSession }
        let endedAtStr = ISO8601DateFormatter().string(from: Date())
        let rowsData = try await sendSupabaseRequest(method: "GET", endpoint: "table_sessions", queryItems: [
            URLQueryItem(name: "select", value: "id,session_token,guest_count,cashier_name,created_at,row_version"),
            URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)"),
            URLQueryItem(name: "table_number", value: "eq.\(tableNumber)"),
            URLQueryItem(name: "is_active", value: "eq.1"),
            URLQueryItem(name: "order", value: "created_at.desc"),
            URLQueryItem(name: "limit", value: "1")
        ])
        guard let rows = try? JSONSerialization.jsonObject(with: rowsData) as? [[String: Any]],
              let row = rows.first,
              let id = row["id"] as? String,
              let token = row["session_token"] as? String else { return true }
        var session: [String: Any] = [
            "id": id, "merchant_id": merchantId, "branch_id": branchId,
            "table_number": tableNumber, "session_token": token, "is_active": 0,
            "guest_count": row["guest_count"] as? Int ?? 2,
            "cashier_name": row["cashier_name"] as? String ?? "",
            "created_at": row["created_at"] as? String ?? endedAtStr,
            "ended_at": endedAtStr
        ]
        if let version = row["row_version"] as? Int { session["expected_row_version"] = version }

        for attempt in 1...3 {
            do {
                _ = try await sendSupabaseRequest(method: "POST", endpoint: "rpc/upsert_table_session_cas", payload: ["p_session": session])
                break
            } catch {
                let message = String(describing: error)
                guard attempt < 3, message.contains("table_session_conflict") else { throw error }

                // Refresh row version
                let latestData = try? await sendSupabaseRequest(method: "GET", endpoint: "table_sessions", queryItems: [
                    URLQueryItem(name: "id", value: "eq.\(id)"),
                    URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)"),
                    URLQueryItem(name: "select", value: "row_version"),
                    URLQueryItem(name: "limit", value: "1")
                ])
                if let data = latestData,
                   let response = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                   let latestRow = response.first,
                   let latestVersion = latestRow["row_version"] as? Int {
                    session["expected_row_version"] = latestVersion
                }

                let baseDelay = 500_000_000 * UInt64(1 << (attempt - 1))
                let jitter = UInt64.random(in: 0...250_000_000)
                try await Task.sleep(nanoseconds: baseDelay + jitter)
            }
        }
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
        let order = try await fetchOrderById(orderId)
        try await patchWithVersion(
            endpoint: "orders",
            id: orderId,
            payload: ["status": "served"],
            expectedRowVersion: order?.rowVersion
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

    /// Mark an order (and its items) as completed after payment. Used for
    /// quick orders which have no table session to close via complete_checkout,
    /// so the order does not linger in "preparing"/"served" as if still open.
    func markOrderCompleted(orderId: String, receiptNumber: String? = nil) async throws -> Bool {
        let order = try await fetchOrderById(orderId)
        var payload: [String: Any] = ["status": "completed"]
        if let receiptNumber, !receiptNumber.isEmpty {
            payload["receipt_number"] = receiptNumber
        }
        try await patchWithVersion(
            endpoint: "orders",
            id: orderId,
            payload: payload,
            expectedRowVersion: order?.rowVersion
        )
        _ = try await sendSupabaseRequest(
            method: "PATCH",
            endpoint: "order_items",
            queryItems: [URLQueryItem(name: "order_id", value: "eq.\(orderId)")],
            payload: ["status": "served"]
        )
        return true
    }

    /// Next daily queue integer for counter / quick / delivery orders.
    func generateQueueNumber() async throws -> Int {
        let merchantId = self.activeMerchantId
        let data = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "rpc/generate_queue_number",
            payload: ["p_merchant_id": merchantId]
        )
        if let value = try? JSONDecoder().decode(Int.self, from: data) { return value }
        if let values = try? JSONDecoder().decode([Int].self, from: data), let value = values.first { return value }
        if let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           let value = Int(text) {
            return value
        }
        throw NetworkError.serverError("Invalid generate_queue_number response")
    }

    /// Next daily receipt number `RCP-YYYYMMDD-NNN`.
    func generateReceiptNumber() async throws -> String {
        let merchantId = self.activeMerchantId
        let data = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "rpc/generate_receipt_number",
            payload: ["p_merchant_id": merchantId]
        )
        if let value = try? JSONDecoder().decode(String.self, from: data) { return value }
        if let values = try? JSONDecoder().decode([String].self, from: data), let value = values.first { return value }
        if let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\" \n\r\t")),
           text.hasPrefix("RCP-") {
            return text
        }
        throw NetworkError.serverError("Invalid generate_receipt_number response")
    }

    static func formatQueueNumber(_ value: Int) -> String {
        let enableLimit = UserDefaults.standard.bool(forKey: "enable_queue_reset_limit")
        let maxLimit = UserDefaults.standard.integer(forKey: "queue_reset_max_count")
        let normalizedValue: Int
        if enableLimit && maxLimit > 0 {
            let mod = max(1, value) % maxLimit
            normalizedValue = mod == 0 ? maxLimit : mod
        } else {
            normalizedValue = max(1, value)
        }
        return String(format: "%03d", normalizedValue)
    }

    static func localFallbackQueueNumber(merchantId: String) -> String {
        let day = dayStampBangkok()
        let key = "local_queue_seq_\(merchantId)_\(day)"
        var next = UserDefaults.standard.integer(forKey: key) + 1
        let enableLimit = UserDefaults.standard.bool(forKey: "enable_queue_reset_limit")
        let maxLimit = UserDefaults.standard.integer(forKey: "queue_reset_max_count")
        if enableLimit && maxLimit > 0 && next > maxLimit {
            next = 1
        }
        UserDefaults.standard.set(next, forKey: key)
        return formatQueueNumber(next)
    }

    static func localFallbackReceiptNumber(merchantId: String) -> String {
        let day = dayStampBangkok()
        let key = "local_receipt_seq_\(merchantId)_\(day)"
        let next = UserDefaults.standard.integer(forKey: key) + 1
        UserDefaults.standard.set(next, forKey: key)
        return String(format: "RCP-%@-%03d", day, next)
    }

    private static func dayStampBangkok() -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Bangkok") ?? .current
        let parts = cal.dateComponents([.year, .month, .day], from: Date())
        return String(format: "%04d%02d%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    func serveOrderItem(itemId: String, orderId: String, servedBy: String? = nil) async throws -> Bool {
        if let order = try await fetchOrderById(orderId), order.isAwaitingStaffApproval {
            throw NetworkError.serverError("Approve this customer order before serving it")
        }
        var payload: [String: Any] = ["status": "served"]
        if let servedBy = servedBy {
            payload["served_by"] = servedBy
        }
        let prior = try await fetchOrderById(orderId)
        let itemVersion = prior?.items.first(where: { $0.id == itemId })?.rowVersion
        try await patchWithVersion(
            endpoint: "order_items",
            id: itemId,
            payload: payload,
            expectedRowVersion: itemVersion
        )

        if let order = try await fetchOrderById(orderId) {
            let isOrderServed = !order.items.isEmpty &&
                order.items.allSatisfy { $0.status == "served" || $0.status == "cancelled" }
            if isOrderServed && order.status != "served" {
                try await patchWithVersion(
                    endpoint: "orders",
                    id: orderId,
                    payload: ["status": "served"],
                    expectedRowVersion: order.rowVersion
                )
            }
        }

        await refreshAll()
        return true
    }

    func recallOrderItem(itemId: String, orderId: String) async throws -> Bool {
        let payload: [String: Any] = [
            "status": "cooking",
            "served_by": NSNull()
        ]
        let prior = try await fetchOrderById(orderId)
        let itemVersion = prior?.items.first(where: { $0.id == itemId })?.rowVersion
        try await patchWithVersion(
            endpoint: "order_items",
            id: itemId,
            payload: payload,
            expectedRowVersion: itemVersion
        )

        if let order = try await fetchOrderById(orderId) {
            if order.status == "served" {
                try await patchWithVersion(
                    endpoint: "orders",
                    id: orderId,
                    payload: ["status": "preparing"],
                    expectedRowVersion: order.rowVersion
                )
            }
        }

        await refreshAll()
        return true
    }

    func approveOrder(order: Order) async throws -> Bool {
        _ = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "rpc/approve_customer_order",
            payload: ["p_order_id": order.id]
        )
        await refreshAll()
        return true
    }

    func deleteOrderItem(itemId: String) async throws -> Bool {
        let currentVersion = (try? await fetchAllActiveOrders())?
            .flatMap(\.items).first(where: { $0.id == itemId })?.rowVersion
        try await patchWithVersion(
            endpoint: "order_items", id: itemId,
            payload: ["status": "cancelled", "is_deleted": true],
            expectedRowVersion: currentVersion
        )
        await refreshAll()
        return true
    }

    /// Patch quantity and/or notes for a single order item
    func patchOrderItem(itemId: String, quantity: Int? = nil, notes: String?) async throws -> Bool {
        var payload: [String: Any] = [:]
        if let q = quantity { payload["quantity"] = q }
        if let n = notes    { payload["notes"]    = n } else { payload["notes"] = NSNull() }
        // Look up current version across active tables (best-effort).
        var expectedVersion: Int?
        if let orders = try? await fetchAllActiveOrders() {
            expectedVersion = orders
                .flatMap(\.items)
                .first(where: { $0.id == itemId })?
                .rowVersion
        }
        try await patchWithVersion(
            endpoint: "order_items",
            id: itemId,
            payload: payload,
            expectedRowVersion: expectedVersion
        )
        await refreshAll()
        return true
    }

    func uploadOrder(
        orderId: String,
        orderNumber: String,
        tableNumber: String,
        total: Double,
        subtotal: Double? = nil,
        tax: Double = 0.0,
        serviceCharge: Double = 0.0,
        items: [[String: Any]],
        sessionToken: String? = nil,
        guestCount: Int = 2,
        orderType: String = "dine_in",
        queueNumber: String? = nil,
        receiptNumber: String? = nil,
        deliveryBrand: String? = nil,
        platformOrderNumber: String? = nil,
        cashierName: String? = nil
    ) async throws -> Bool {
        guard !items.isEmpty else {
            throw NetworkError.serverError("Cannot upload an order without items")
        }

        let merchantId = self.activeMerchantId
        let branchId = StaffSessionContext.branchId
        guard !merchantId.isEmpty else { throw StaffServiceError.missingMerchantSession }
        guard !branchId.isEmpty else { throw StaffServiceError.missingBranchSession }
        // Counter orders are deliberately tableless. Normalize at the last
        // boundary so callers cannot accidentally create a phantom table from
        // a stale UI value or an external order reference.
        let normalizedTableNumber = orderType == "dine_in" && sessionToken?.isEmpty == false
            ? tableNumber
            : "QUICK"
        var orderPayload: [String: Any] = [
            "id": orderId,
            "order_number": orderNumber,
            "table_number": normalizedTableNumber,
            "total": total,
            // subtotal defaults to the item total when not supplied — tax and
            // service charge are applied later at payment time. Sending these
            // keeps the DB row consistent so the POS never shows Subtotal 0.
            "subtotal": subtotal ?? total,
            "tax": tax,
            "service_charge": serviceCharge,
            "status": "preparing",
            // Staff-initiated order (iPhone). Explicitly tag the channel and mark
            // it confirmed so the kitchen prints immediately — unlike web orders,
            // a staff member is already placing this order, so no extra approval
            // step is required before it reaches the kitchen.
            "order_source": "staff",
            "is_staff_confirmed": true,
            "guest_count": guestCount,
            "order_type": orderType,
            "created_at": ISO8601DateFormatter().string(from: Date()),
            "merchant_id": merchantId,
            "branch_id": branchId,
            "idempotency_key": orderId.lowercased()
        ]
        if let token = sessionToken, !token.isEmpty {
            orderPayload["session_token"] = token
        }
        if let qNum = queueNumber {
            orderPayload["queue_number"] = qNum
        }
        if let receipt = receiptNumber, !receipt.isEmpty {
            orderPayload["receipt_number"] = receipt
        }
        if let brand = deliveryBrand, !brand.isEmpty {
            orderPayload["delivery_brand"] = brand
        }
        if let platform = platformOrderNumber, !platform.isEmpty {
            orderPayload["platform_order_number"] = platform
        }
        if let cashier = cashierName {
            orderPayload["cashier_name"] = cashier
        }

        // Build order-item rows, keeping each row's id so we can attach modifiers.
        var orderItemModifiers: [[String: Any]] = []
        let orderItems = items.map { item -> [String: Any] in
            let itemRowId = item["id"] as? String ?? UUID().uuidString
            // Collect any chosen options for this line → order_item_modifiers rows.
            if let mods = item["modifiers"] as? [[String: Any]] {
                for mod in mods {
                    guard let modifierId = mod["id"] as? String, !modifierId.isEmpty else { continue }
                    orderItemModifiers.append([
                        "id": UUID().uuidString,
                        "order_item_id": itemRowId,
                        "modifier_id": modifierId,
                        "price": mod["price"] as? Double ?? 0.0,
                        "merchant_id": merchantId
                    ])
                }
            }
            return [
                "id": itemRowId,
                "order_id": orderId,
                "item_name": item["name"] as? String ?? "",
                "quantity": item["quantity"] as? Int ?? 1,
                "price": item["price"] as? Double ?? 0.0,
                "line_type": item["lineType"] as? String ?? "main",
                "status": "cooking",
                "item_id": item["itemId"] as? String ?? "",
                "merchant_id": merchantId,
                "branch_id": branchId
            ]
        }

        let response = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "rpc/create_order_atomic_cas",
            payload: [
                "p_order": orderPayload,
                "p_items": orderItems,
                "p_modifiers": orderItemModifiers
            ]
        )
        if let object = try? JSONSerialization.jsonObject(with: response) as? [String: Any],
           let status = object["status"] as? String,
           status != "ok" {
            throw NetworkError.invalidResponse
        }
        await refreshAll()
        return true
    }

    func completeCheckout(paymentId: UUID, orderId: String, amount: Double, method: String, tableNumber: String,
                          subtotal: Double? = nil, tax: Double? = nil, serviceCharge: Double? = nil, discount: Double? = nil) async throws -> Bool {
        var breakdown: [String: Any] = ["grand_total": amount]
        if let subtotal { breakdown["subtotal"] = subtotal }
        if let tax { breakdown["tax"] = tax }
        if let serviceCharge { breakdown["service_charge"] = serviceCharge }
        if let discount { breakdown["discount"] = discount }
        return try await completeCheckoutAtomic(
            orderId: orderId,
            payments: [[
                "id": paymentId.uuidString.lowercased(),
                "amount": amount,
                "payment_method": method
            ]],
            tableNumber: tableNumber,
            breakdown: breakdown,
            idempotencyKey: "checkout:\(paymentId.uuidString.lowercased())"
        )
    }

    func completeCheckoutAtomic(
        orderId: String,
        payments: [[String: Any]],
        tableNumber: String,
        breakdown: [String: Any],
        idempotencyKey: String
    ) async throws -> Bool {
        let payload: [String: Any] = [
            "p_order_id": orderId,
            "p_idempotency_key": idempotencyKey,
            "p_payments": payments,
            "p_table_number": tableNumber,
            "p_breakdown": breakdown
        ]
        let data = try await sendSupabaseRequest(method: "POST", endpoint: "rpc/complete_checkout_atomic", payload: payload)
        guard let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              result["status"] as? String == "completed" else {
            throw NetworkError.invalidResponse
        }
        return true
    }

}
