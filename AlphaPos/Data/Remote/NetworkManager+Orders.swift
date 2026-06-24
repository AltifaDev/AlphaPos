import Foundation
import CryptoKit
import SwiftData

extension NetworkManager {
    // MARK: - API Upload Endpoints

    func uploadOrder(order: Order) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        var orderPayload: [String: Any] = [
            "id": order.id.uuidString.lowercased(),
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
        _ = try await sendSupabaseRequest(method: "POST", endpoint: "orders",
            queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
            payload: orderPayload)

        // 2. Insert order items
        var itemsPayload: [[String: Any]] = []
        for item in order.items {
            var itemPayload: [String: Any] = [
                "id": item.id.uuidString.lowercased(),
                "order_id": order.id.uuidString.lowercased(),
                "item_name": item.menuItem?.name ?? (item.itemName.isEmpty ? "Unknown Item" : item.itemName),
                "quantity": item.quantity,
                "price": item.unitPrice,
                "status": item.status,
                "merchant_id": merchantId,
                "created_at": NetworkManager.iso8601.string(from: Date())
            ]
            if let servedBy = item.servedBy {
                itemPayload["served_by"] = servedBy
            } else {
                itemPayload["served_by"] = NSNull()
            }
            if let itemId = item.menuItem?.id {
                itemPayload["item_id"] = itemId.lowercased()
            } else {
                itemPayload["item_id"] = NSNull()
            }
            if let branchId = order.branch?.id {
                itemPayload["branch_id"] = branchId.uuidString.lowercased()
            }
            itemsPayload.append(itemPayload)
        }
        if !itemsPayload.isEmpty {
            _ = try await sendSupabaseRequest(method: "POST", endpoint: "order_items",
                queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
                payload: itemsPayload)
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
        // Deterministic ID: hash from merchantId+tableNumber+type+minute-window
        // Prevents duplicate service requests when the call is retried within the same minute
        let minuteKey = Int(Date().timeIntervalSince1970 / 60)
        let deterministicSeed = "\(merchantId)-\(tableNumber)-\(type)-\(minuteKey)"
        let deterministicId = UUID(uuidString: deterministicSeed.deterministicUUIDString) ?? UUID()
        let payload: [String: Any] = [
            "id": deterministicId.uuidString.lowercased(),
            "table_number": tableNumber,
            "request_type": type,
            "status": "pending",
            "created_at": NetworkManager.iso8601.string(from: Date()),
            "merchant_id": merchantId
        ]
        _ = try await sendSupabaseRequest(method: "POST", endpoint: "service_requests",
            queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
            payload: payload)
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

    func deletePaymentOnServer(id: UUID) async throws -> Bool {
        _ = try await sendSupabaseRequest(method: "DELETE", endpoint: "payments",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(id.uuidString.lowercased())")])
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

    func deleteTimecardOnServer(id: UUID) async throws -> Bool {
        _ = try await sendSupabaseRequest(method: "DELETE", endpoint: "timecards",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(id.uuidString.lowercased())")])
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
}


