// NetworkService+Orders.swift
// Orders, order items, sessions, payments, checkout, and service requests.

import Foundation

extension NetworkService {
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

    func fetchTableOrders(tableNumber: String) async throws -> [Order] {
        // Fetch ALL non-cancelled orders for this table.
        // Do NOT filter by session_token here — orders created from the main POS app
        // (via SyncEngine) may have a different session_token or none at all.
        // Filtering by session_token causes those orders to be silently dropped.
        // NOTE: We intentionally include "completed" so TableDetailView can detect
        //       post-payment state and enter "still dining" mode if needed.
        let ordersData = try await sendSupabaseRequest(method: "GET", endpoint: "orders", queryItems: [
            URLQueryItem(name: "select", value: "*,order_items(*)"),
            URLQueryItem(name: "table_number", value: "eq.\(tableNumber)"),
            URLQueryItem(name: "status", value: "in.(preparing,ready,served,completed)"),
            URLQueryItem(name: "order", value: "created_at.asc")
        ])
        let ordersArray = (try? JSONSerialization.jsonObject(with: ordersData) as? [[String: Any]]) ?? []
        return try await parseOrders(ordersArray)
    }

    private func parseOrderItems(_ jsonArray: [[String: Any]]) -> [OrderItem] {
        jsonArray.map { itemDict in
            OrderItem(
                id: itemDict["id"] as? String ?? "",
                name: itemDict["item_name"] as? String ?? "",
                quantity: itemDict["quantity"] as? Int ?? 1,
                price: itemDict["price"] as? Double ?? 0.0,
                status: itemDict["status"] as? String ?? "cooking",
                item_id: itemDict["item_id"] as? String,
                notes: itemDict["notes"] as? String,
                servedBy: itemDict["served_by"] as? String
            )
        }
    }

    private func fetchOrderItems(orderId: String) async throws -> [OrderItem] {
        let itemsData = try await sendSupabaseRequest(method: "GET", endpoint: "order_items", queryItems: [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "order_id", value: "eq.\(orderId)"),
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
                createdAt: dict["created_at"] as? String ?? "",
                items: items,
                sessionToken: dict["session_token"] as? String
            ))
        }

        return parsed
    }

    func fetchAllActiveOrders() async throws -> [Order] {
        let ordersData = try await sendSupabaseRequest(method: "GET", endpoint: "orders", queryItems: [
            URLQueryItem(name: "select", value: "*,order_items(*)"),
            // ไม่ fetch completed — ลด payload และป้องกัน orders เก่า occupy ใน limit
            URLQueryItem(name: "status", value: "in.(preparing,ready,served)"),
            URLQueryItem(name: "order", value: "created_at.desc"),
            URLQueryItem(name: "limit", value: "100")
        ])
        let jsonArray = (try? JSONSerialization.jsonObject(with: ordersData) as? [[String: Any]]) ?? []
        return try await parseOrders(jsonArray)
    }

    func fetchOrderById(_ orderId: String) async throws -> Order? {
        let ordersData = try await sendSupabaseRequest(method: "GET", endpoint: "orders", queryItems: [
            URLQueryItem(name: "select", value: "*,order_items(*)"),
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

    func serveOrderItem(itemId: String, orderId: String, servedBy: String? = nil) async throws -> Bool {
        var payload: [String: Any] = ["status": "served"]
        if let servedBy = servedBy {
            payload["served_by"] = servedBy
        }
        _ = try await sendSupabaseRequest(
            method: "PATCH",
            endpoint: "order_items",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(itemId)")],
            payload: payload
        )

        if let order = try await fetchOrderById(orderId) {
            let isOrderServed = !order.items.isEmpty &&
                order.items.allSatisfy { $0.status == "served" || $0.status == "cancelled" }
            if isOrderServed && order.status != "served" {
                _ = try await sendSupabaseRequest(
                    method: "PATCH",
                    endpoint: "orders",
                    queryItems: [URLQueryItem(name: "id", value: "eq.\(orderId)")],
                    payload: ["status": "served"]
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
        _ = try await sendSupabaseRequest(
            method: "PATCH",
            endpoint: "order_items",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(itemId)")],
            payload: payload
        )

        if let order = try await fetchOrderById(orderId) {
            if order.status == "served" {
                _ = try await sendSupabaseRequest(
                    method: "PATCH",
                    endpoint: "orders",
                    queryItems: [URLQueryItem(name: "id", value: "eq.\(orderId)")],
                    payload: ["status": "preparing"]
                )
            }
        }

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

    func uploadOrder(
        orderId: String,
        orderNumber: String,
        tableNumber: String,
        total: Double,
        items: [[String: Any]],
        sessionToken: String? = nil,
        guestCount: Int = 2,
        orderType: String = "dine_in",
        queueNumber: String? = nil,
        cashierName: String? = nil
    ) async throws -> Bool {
        guard !items.isEmpty else {
            throw NetworkError.serverError("Cannot upload an order without items")
        }

        let merchantId = self.activeMerchantId
        var orderPayload: [String: Any] = [
            "id": orderId,
            "order_number": orderNumber,
            "table_number": tableNumber,
            "total": total,
            "status": "preparing",
            "guest_count": guestCount,
            "order_type": orderType,
            "created_at": ISO8601DateFormatter().string(from: Date()),
            "merchant_id": merchantId
        ]
        if let token = sessionToken, !token.isEmpty {
            orderPayload["session_token"] = token
        }
        if let qNum = queueNumber {
            orderPayload["queue_number"] = qNum
        }
        if let cashier = cashierName {
            orderPayload["cashier_name"] = cashier
        }

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

        _ = try await sendSupabaseRequest(method: "POST", endpoint: "orders", payload: orderPayload)

        do {
            _ = try await sendSupabaseRequest(method: "POST", endpoint: "order_items", payload: orderItems)
        } catch {
            try? await sendSupabaseRequest(
                method: "DELETE",
                endpoint: "orders",
                queryItems: [URLQueryItem(name: "id", value: "eq.\(orderId)")]
            )
            throw error
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

    /// Upload split payment records for an order (split bill feature)
    func uploadSplitPayment(orderId: String, splits: [[String: Any]]) async throws -> Bool {
        let merchantId = self.activeMerchantId
        let payments: [[String: Any]] = splits.map { split in
            var record: [String: Any] = [
                "id": UUID().uuidString,
                "order_id": orderId,
                "amount": split["amount"] as? Double ?? 0,
                "payment_method": split["payment_method"] as? String ?? "cash",
                "person_index": split["person_index"] as? Int ?? 0,
                "split_type": "split",
                "created_at": ISO8601DateFormatter().string(from: Date()),
                "status": "completed",
                "merchant_id": merchantId
            ]
            if let itemIds = split["item_ids"] as? [String] {
                record["item_ids"] = itemIds.joined(separator: ",")
            }
            return record
        }
        _ = try await sendSupabaseRequest(method: "POST", endpoint: "payments", payload: payments)
        return true
    }
}
