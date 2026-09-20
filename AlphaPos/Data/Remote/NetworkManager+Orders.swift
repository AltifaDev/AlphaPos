import Foundation
import CryptoKit
import SwiftData

extension NetworkManager {
    // MARK: - API Upload Endpoints

    func approveCustomerOrder(orderId: UUID) async throws {
        _ = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "rpc/approve_customer_order",
            payload: ["p_order_id": orderId.uuidString.lowercased()]
        )
    }

    func uploadOrder(order: Order) async throws -> Bool {
        let activeItems = order.items.filter { !$0.isDeleted }
        guard !activeItems.isEmpty else {
            throw NetworkError.serverError("Refusing to upload order \(order.orderNumber) without order items")
        }

        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""

        // ── Build order payload ───────────────────────────────────────────────
        // Counter / quick-sale orders (no table session) use sentinel "QUICK"
        // so clients never treat an empty string as a real table number.
        let resolvedTableNumber: String = {
            if let table = order.tableSession?.table?.tableNumber, !table.isEmpty { return table }
            return "QUICK"
        }()
        let resolvedBranchId = order.branch.id.uuidString.lowercased()

        var orderPayload: [String: Any] = [
            "id":                    order.id.uuidString.lowercased(),
            "order_number":          order.orderNumber,
            "table_number":          resolvedTableNumber,
            "order_type":            order.orderType,
            "total":                 order.total,
            "status":                order.status,
            "created_at":            NetworkManager.iso8601.string(from: order.createdAt),
            "business_date":         order.businessDateKey.isEmpty ? NSNull() : order.businessDateKey,
            "register_session_id":   order.registerSessionId?.uuidString.lowercased() ?? NSNull(),
            "updated_at":            NetworkManager.iso8601.string(from: order.updatedAt),
            "merchant_id":           merchantId,
            "branch_id":             resolvedBranchId,
            "cashier_name":          order.cashierName,
            "queue_number":          order.queueNumber ?? "",
            "receipt_number":        order.receiptNumber ?? "",
            "delivery_brand":        order.deliveryBrand ?? "",
            "delivery_gp":           order.deliveryGP,
            "delivery_ad_fee":       order.deliveryAdFee,
            "delivery_ad_fee_is_pct": order.deliveryAdFeeIsPct,
            "delivery_other_fee":    order.deliveryOtherFee,
            "platform_order_number": order.platformOrderNumber ?? "",
            "support_program_name": order.supportProgramName ?? "",
            "support_government_rate": order.supportGovernmentRate,
            "support_citizen_amount": order.supportCitizenAmount,
            "support_government_amount": order.supportGovernmentAmount,
            "support_settlement_status": order.supportSettlementStatus,
            "guest_count":           order.guestCount,
            // Origin channel + kitchen-print gate. Staff approving a web order
            // on the iPad flips is_staff_confirmed → true; syncing it back lets
            // other station iPads know the order is cleared to print.
            "order_source":          order.orderSource,
            "is_staff_confirmed":    order.isStaffConfirmed
        ]
        if order.rowVersion > 0 { orderPayload["expected_row_version"] = order.rowVersion }
        if let sessionToken = order.tableSession?.sessionToken {
            orderPayload["session_token"] = sessionToken
        }
        if let readyAt = order.readyAt {
            orderPayload["ready_at"] = NetworkManager.iso8601.string(from: readyAt)
        }

        // ── Build items + modifiers payload ──────────────────────────────────
        var itemsPayload: [[String: Any]] = []
        var modifiersPayload: [[String: Any]] = []
        for item in activeItems {
            var itemPayload: [String: Any] = [
                "id":        item.id.uuidString.lowercased(),
                "order_id":  order.id.uuidString.lowercased(),
                "item_name": item.menuItem?.name ?? (item.itemName.isEmpty ? "Unknown Item" : item.itemName),
                "quantity":  item.quantity,
                "price":     item.unitPrice,
                "line_type": item.resolvedLineType.rawValue,
                "status":    item.status,
                "merchant_id": merchantId,
                // Prefer order.createdAt — OrderItem has no createdAt field.
                // ON CONFLICT in create_order_atomic does not overwrite created_at.
                "created_at":  NetworkManager.iso8601.string(from: order.createdAt),
                "notes":     NSNull(),
                "served_by": NSNull()
            ]
            if let notes = item.notes, !notes.isEmpty { itemPayload["notes"] = notes }
            if let servedBy = item.servedBy            { itemPayload["served_by"] = servedBy }
            if let itemId = item.menuItem?.id           { itemPayload["item_id"] = itemId.lowercased() }
            if !resolvedBranchId.isEmpty                { itemPayload["branch_id"] = resolvedBranchId }
            if item.rowVersion > 0                      { itemPayload["expected_row_version"] = item.rowVersion }
            itemsPayload.append(itemPayload)

            for oim in item.modifiers where !oim.isDeleted {
                var modPayload: [String: Any] = [
                    "id": oim.id.uuidString.lowercased(),
                    "order_item_id": item.id.uuidString.lowercased(),
                    "price": oim.price,
                    "merchant_id": merchantId
                ]
                if let modifierId = oim.modifier?.id {
                    modPayload["modifier_id"] = modifierId.uuidString.lowercased()
                }
                modifiersPayload.append(modPayload)
            }
        }

        // ── ATOMIC RPC call (มาตรฐานสากล — Single Transaction) ───────────────
        // แทนที่จะส่ง POST orders + POST order_items แยก (partial commit ได้)
        // ใช้ create_order_atomic RPC ที่ Postgres รัน BEGIN…COMMIT เดียว
        // → ถ้า items fail → order ก็ rollback อัตโนมัติ (ไม่มี orphan order)
        // → idempotent: ON CONFLICT DO UPDATE → retry ปลอดภัย
        let operationRequest: [String: Any] = [
            "p_order": orderPayload,
            "p_items": itemsPayload,
            "p_modifiers": modifiersPayload
        ]
        // One stable operation ID per exact snapshot. A lost response can be
        // replayed after app restart; a later local edit produces a new ID.
        let operationData = try JSONSerialization.data(withJSONObject: operationRequest, options: [.sortedKeys])
        let operationHash = SHA256.hash(data: operationData)
            .map { String(format: "%02x", $0) }.joined()
        orderPayload["operation_id"] = "pos:\(order.id.uuidString.lowercased()):\(operationHash)"
        let rpcPayload: [String: Any] = [
            "p_order": orderPayload,
            "p_items": itemsPayload,
            "p_modifiers": modifiersPayload
        ]

        let data = try await sendOrderMutation(payload: rpcPayload)

        // Modifiers were included in the atomic RPC — mark them synced locally.
        for item in activeItems {
            for oim in item.modifiers where !oim.isDeleted {
                oim.isSynced = true
                oim.updatedAt = Date()
            }
        }

        // ตรวจสอบ response { "order_id": "...", "items_count": N, "status": "ok" }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let status = json["status"] as? String, status == "ok" {
            if let serverOrderIdStr = json["order_id"] as? String,
               let serverOrderId = UUID(uuidString: serverOrderIdStr),
               serverOrderId != order.id {
                order.id = serverOrderId
            }
            if let version = json["order_row_version"] as? Int { order.rowVersion = version }
            if let versions = json["item_row_versions"] as? [String: Int] {
                for item in activeItems {
                    if let version = versions[item.id.uuidString.lowercased()] { item.rowVersion = version }
                }
            }
            return true
        }
        // RPC return ค่าอื่น — ถือว่าสำเร็จถ้าไม่มี HTTP error (sendSupabaseRequest throw แล้ว)
        return true
    }

    /// The server records each operation ID with its result in one transaction.
    /// Retry only transient contention/availability failures; never
    /// retry validation, authentication, or optimistic-concurrency conflicts.
    private func sendOrderMutation(payload: [String: Any]) async throws -> Data {
        var lastError: Error?

        for attempt in 0..<3 {
            do {
                return try await sendSupabaseRequest(
                    method: "POST",
                    endpoint: "rpc/create_order_atomic_cas",
                    payload: payload,
                    timeoutOverride: 15.0
                )
            } catch {
                lastError = error
                guard attempt < 2, isRetryableOrderMutationError(error) else { throw error }

                let baseDelay = 250_000_000 * UInt64(1 << attempt)
                let jitter = UInt64(Int.random(in: 0...250) * 1_000_000)
                try await Task.sleep(nanoseconds: baseDelay + jitter)
            }
        }

        throw lastError ?? NetworkError.serverError("Order upload failed")
    }

    private func isRetryableOrderMutationError(_ error: Error) -> Bool {
        let message = error.localizedDescription.uppercased()
        if message.contains("PGRST002") || message.contains("PGRST003") {
            return true
        }
        if message.contains("55P03") || message.contains("ORDER_BUSY") || message.contains("ORDER_ITEM_BUSY") {
            return true
        }
        if message.contains("DEADLOCK DETECTED") || message.contains("COULD NOT SERIALIZE") {
            return true
        }
        if message.contains("HTTP 502") || message.contains("HTTP 503") || message.contains("HTTP 504") {
            return true
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .cannotConnectToHost, .notConnectedToInternet:
                return true
            default:
                return false
            }
        }
        return false
    }

    func fetchServiceRequests() async throws -> [[String: Any]] {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        let branchId = try activeOperationalBranchId()
        let now = NetworkManager.iso8601.string(from: Date())
        let data = try await sendSupabaseRequest(method: "GET", endpoint: "service_requests", queryItems: [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)"),
            URLQueryItem(name: "branch_id", value: "eq.\(branchId)"),
            URLQueryItem(name: "status", value: "eq.pending"),
            URLQueryItem(name: "or", value: "(expires_at.is.null,expires_at.gt.\(now))")
        ])

        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw NetworkError.invalidResponse
        }

        return jsonArray.map { dict in
            var mapped = dict
            mapped["tableNumber"] = dict["table_number"]
            mapped["requestType"] = dict["request_type"]
            mapped["createdAt"] = dict["created_at"]
            mapped["restaurantTableId"] = dict["restaurant_table_id"]
            mapped["diningAreaId"] = dict["dining_area_id"]
            mapped["expiresAt"] = dict["expires_at"]
            return mapped
        }
    }

    func resolveServiceRequest(id: String) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        let branchId = try activeOperationalBranchId()
        _ = try await sendSupabaseRequest(
            method: "PATCH",
            endpoint: "service_requests",
            queryItems: [
                URLQueryItem(name: "id", value: "eq.\(id)"),
                URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)"),
                URLQueryItem(name: "branch_id", value: "eq.\(branchId)")
            ],
            payload: ["status": "completed"]
        )
        return true
    }

    func createServiceRequest(tableNumber: String, type: String) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        let branchId = try activeOperationalBranchId()
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
            "merchant_id": merchantId,
            "branch_id": branchId
        ]
        _ = try await sendSupabaseRequest(method: "POST", endpoint: "service_requests",
            queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
            payload: payload)
        return true
    }

    func fetchActiveSessions() async throws -> [[String: Any]] {
        let storedMerchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        let merchantId = storedMerchantId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !merchantId.isEmpty else {
            throw NetworkError.serverError("No authenticated merchant")
        }
        let branchId = try activeOperationalBranchId()
        let data = try await sendSupabaseRequest(method: "GET", endpoint: "table_sessions", queryItems: [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)"),
            URLQueryItem(name: "branch_id", value: "eq.\(branchId)"),
            URLQueryItem(name: "is_active", value: "eq.1"),
            URLQueryItem(name: "is_deleted", value: "eq.false")
        ])

        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw NetworkError.invalidResponse
        }

        return jsonArray.map { dict in
            var mapped = dict
            mapped["tableNumber"] = dict["table_number"]
            mapped["sessionToken"] = dict["session_token"]
            mapped["tableId"] = dict["table_id"]
            return mapped
        }
    }

    func closeTableSession(tableNumber: String) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        let branchId = try activeOperationalBranchId()
        let endedAtStr = NetworkManager.iso8601.string(from: Date())
        _ = try await sendSupabaseRequest(
            method: "PATCH",
            endpoint: "table_sessions",
            queryItems: [
                URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)"),
                URLQueryItem(name: "branch_id", value: "eq.\(branchId)"),
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
    func deleteOrderOnServer(id: UUID, expectedRowVersion: Int) async throws -> Bool {
        let orderId = id.uuidString.lowercased()
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        let branchId = try activeOperationalBranchId()
        let scope = [
            URLQueryItem(name: "id", value: "eq.\(orderId)"),
            URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)"),
            URLQueryItem(name: "branch_id", value: "eq.\(branchId)")
        ]
        if expectedRowVersion < 1 {
            // A never-acknowledged create may still have committed remotely.
            // Only discard the local tombstone if the server confirms no row.
            let data = try await sendSupabaseRequest(
                method: "GET", endpoint: "orders",
                queryItems: scope + [URLQueryItem(name: "select", value: "id")]
            )
            guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                throw NetworkError.invalidResponse
            }
            if rows.isEmpty { return true }
            throw NetworkError.conflict("Order \(orderId) exists remotely without a known local version")
        }
        let payload: [String: Any] = [
            "is_deleted": true,
            "status": "cancelled",
            "updated_at": NetworkManager.iso8601.string(from: Date())
        ]
        let data = try await sendSupabaseRequest(
            method: "PATCH",
            endpoint: "orders",
            queryItems: scope + [URLQueryItem(name: "row_version", value: "eq.\(expectedRowVersion)")],
            payload: payload
        )
        guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw NetworkError.invalidResponse
        }
        guard !rows.isEmpty else {
            throw NetworkError.conflict("Order \(orderId) changed before cancellation")
        }
        return true
    }

    func uploadPayment(id: UUID, orderId: UUID?, amount: Double, method: String, paidAt: Date, businessDateKey: String, registerSessionId: UUID?) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        let payload: [String: Any] = [
            "id": id.uuidString,
            "order_id": orderId?.uuidString ?? "",
            "amount": amount,
            "payment_method": method,
            "created_at": NetworkManager.iso8601.string(from: paidAt),
            "business_date": businessDateKey,
            "register_session_id": registerSessionId?.uuidString.lowercased() ?? NSNull(),
            "status": "completed",
            "merchant_id": merchantId
        ]
        _ = try await sendSupabaseRequest(method: "POST", endpoint: "payments", payload: payload)
        return true
    }

    func annotatePaymentBusinessContext(id: UUID, paidAt: Date, businessDateKey: String, registerSessionId: UUID?) async throws {
        let payload: [String: Any] = [
            "created_at": NetworkManager.iso8601.string(from: paidAt),
            "business_date": businessDateKey,
            "register_session_id": registerSessionId?.uuidString.lowercased() ?? NSNull()
        ]
        _ = try await sendSupabaseRequest(method: "PATCH", endpoint: "payments", queryItems: [URLQueryItem(name: "id", value: "eq.\(id.uuidString.lowercased())")], payload: payload)
    }

    func deletePaymentOnServer(id: UUID) async throws -> Bool {
        _ = try await sendSupabaseRequest(method: "DELETE", endpoint: "payments",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(id.uuidString.lowercased())")])
        return true
    }

    func completeCheckout(order: Order, payments: [Payment], tableNumber: String) async throws -> Bool {
        guard !payments.isEmpty else { return false }
        let paymentPayloads: [[String: Any]] = payments.map { payment in
            var value: [String: Any] = [
                "id": payment.id.uuidString.lowercased(),
                "amount": payment.amount,
                "payment_method": payment.paymentMethod
            ]
            if let reference = payment.transactionReference, !reference.isEmpty {
                value["transaction_reference"] = reference
            }
            return value
        }
        // Prefer the status captured on the table at payment time. Falling back
        // to the setting keeps direct/legacy checkout callers compatible.
        let capturedTableStatus = order.tableSession?.table?.status.lowercased()
        let configuredTableStatus = UserDefaults.standard.object(forKey: "enable_table_cleaning_after_checkout") as? Bool ?? true
            ? "cleaning"
            : "vacant"
        let postCheckoutTableStatus = capturedTableStatus.flatMap {
            ["cleaning", "vacant"].contains($0) ? $0 : nil
        } ?? configuredTableStatus
        let payload: [String: Any] = [
            "p_order_id": order.id.uuidString.lowercased(),
            "p_idempotency_key": "checkout:\(order.id.uuidString.lowercased())",
            "p_payments": paymentPayloads,
            "p_table_number": tableNumber,
            "p_breakdown": [
                "subtotal": order.subtotal,
                "tax": order.tax,
                "service_charge": order.serviceCharge,
                "discount": order.discount,
                "grand_total": payments.reduce(0.0) { $0 + $1.amount },
                "table_status_after_checkout": postCheckoutTableStatus
            ]
        ]
        _ = try await sendSupabaseRequest(method: "POST", endpoint: "rpc/complete_checkout_atomic", payload: payload)
        return true
    }

    /// Next daily queue integer for counter / quick / delivery orders.
    func generateQueueNumber() async throws -> Int {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
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
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        let data = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "rpc/generate_receipt_number",
            payload: ["p_merchant_id": merchantId]
        )
        if let value = try? JSONDecoder().decode(String.self, from: data) { return value }
        if let values = try? JSONDecoder().decode([String].self, from: data), let value = values.first { return value }
        if let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\" \n\r\t")) ,
           text.hasPrefix("RCP-") {
            return text
        }
        throw NetworkError.serverError("Invalid generate_receipt_number response")
    }

    /// Formats a queue integer for display / storage as international standard (`001`, `002`, `015`),
    /// with support for configurable auto-reset when reaching a maximum limit (e.g. 20, 30, 40).
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

    /// Cleans and sanitizes a raw queue number string into standard international format.
    static func sanitizeQueueNumber(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let digits = raw.filter { $0.isNumber }
        if let intVal = Int(digits), intVal > 0 {
            return formatQueueNumber(intVal)
        }
        return nil
    }

    /// Offline-safe local fallback when RPC is unavailable.
    static func localFallbackQueueNumber(merchantId: String) -> String {
        let day = Self.dayStampBangkok()
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

    /// Resets today's local queue counter back to start.
    static func resetDailyQueueSequence(merchantId: String) {
        let day = Self.dayStampBangkok()
        let key = "local_queue_seq_\(merchantId)_\(day)"
        UserDefaults.standard.set(0, forKey: key)
    }

    static func localFallbackReceiptNumber(merchantId: String) -> String {
        let day = Self.dayStampBangkok()
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

    func fetchCompletedOrdersFromSupabase() async throws -> [[String: Any]] {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        let branchId = try activeOperationalBranchId()
        let data = try await sendSupabaseRequest(
            method: "GET",
            endpoint: "orders",
            queryItems: [
                URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)"),
                URLQueryItem(name: "branch_id", value: "eq.\(branchId)"),
                URLQueryItem(name: "status", value: "eq.completed"),
                URLQueryItem(name: "select", value: "*,order_items(*),payments(*)")
            ]
        )
        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw NetworkError.invalidResponse
        }
        return jsonArray
    }

    func uploadTimecard(id: UUID, employeeId: UUID, employeeName: String, clockIn: Date, clockOut: Date?, status: String, breakDuration: Int = 0, overtimeMinutes: Int = 0, notes: String? = nil, clockInConfidence: Double? = nil, clockOutConfidence: Double? = nil, clockInSelfieUrl: String? = nil, clockOutSelfieUrl: String? = nil, shiftId: UUID? = nil, verifiedByUserId: UUID? = nil) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        let branchId = try activeOperationalBranchId()
        var payload: [String: Any] = [
            "id": id.uuidString,
            "employee_id": employeeId.uuidString,
            "employee_name": employeeName,
            "clock_in": NetworkManager.iso8601.string(from: clockIn),
            "break_duration": breakDuration,
            "overtime_minutes": overtimeMinutes,
            "status": status,
            "merchant_id": merchantId,
            "branch_id": branchId
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
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        let branchId = try activeOperationalBranchId()
        let data = try await sendSupabaseRequest(method: "GET", endpoint: "timecards", queryItems: [
            URLQueryItem(name: "select", value: "id"),
            URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)"),
            URLQueryItem(name: "branch_id", value: "eq.\(branchId)"),
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
        createdAt: Date = Date(),
        businessDateKey: String,
        registerSessionId: UUID?,
        isDeleted: Bool = false,
        updatedAt: Date = Date(),
        reasonCode: String? = nil,
        auditSignature: String? = nil
    ) async throws -> Bool {
        guard let itemId else { return false }
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        let payload: [String: Any] = [
            "p_movement_id": id.uuidString.lowercased(),
            "p_merchant_id": merchantId,
            "p_item_id": itemId.uuidString.lowercased(),
            "p_type": type,
            "p_quantity": quantity,
            "p_reference_id": referenceId?.uuidString.lowercased() ?? NSNull(),
            "p_branch_id": branchId?.uuidString.lowercased() ?? NSNull(),
            "p_cost_price": costPrice ?? NSNull(),
            "p_notes": notes ?? NSNull(),
            "p_reason_code": reasonCode ?? NSNull(),
            "p_created_at": NetworkManager.iso8601.string(from: createdAt),
            "p_audit_signature": auditSignature ?? NSNull(),
            "p_business_date": businessDateKey.isEmpty ? NSNull() : businessDateKey,
            "p_register_session_id": registerSessionId?.uuidString.lowercased() ?? NSNull()
        ]
        _ = try await sendSupabaseRequest(method: "POST", endpoint: "rpc/apply_inventory_movement", payload: payload)
        return true
    }

    func transferInventoryAtomic(
        transferId: UUID,
        sourceItemId: UUID,
        targetItemId: UUID,
        quantity: Double,
        notes: String?,
        createdAt: Date,
        businessDateKey: String,
        registerSessionId: UUID?
    ) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        _ = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "rpc/transfer_inventory_atomic",
            payload: [
                "p_transfer_id": transferId.uuidString.lowercased(),
                "p_merchant_id": merchantId,
                "p_source_item_id": sourceItemId.uuidString.lowercased(),
                "p_target_item_id": targetItemId.uuidString.lowercased(),
                "p_quantity": quantity,
                "p_notes": notes.map { $0 as Any } ?? NSNull(),
                "p_created_at": NetworkManager.iso8601.string(from: createdAt),
                "p_business_date": businessDateKey.isEmpty ? NSNull() : businessDateKey,
                "p_register_session_id": registerSessionId?.uuidString.lowercased() ?? NSNull()
            ]
        )
        return true
    }

    func fetchInventoryTransactionsFromSupabase() async throws -> [[String: Any]] {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        let branchId = try activeOperationalBranchId()
        return try await fetchAllPages(
            endpoint: "inventory_transactions",
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)"),
                URLQueryItem(name: "branch_id", value: "eq.\(branchId)"),
                URLQueryItem(name: "is_deleted", value: "eq.false"),
                URLQueryItem(name: "order", value: "created_at.asc,id.asc")
            ],
            pageSize: 500
        )
    }

    /// Fetch table rows for reconciliation. Display callers should use
    /// fetchActiveRestaurantTables() so tombstones never enter the UI query.
    func fetchRestaurantTables() async throws -> [[String: Any]] {
        let storedMerchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        let merchantId = storedMerchantId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !merchantId.isEmpty else {
            throw NetworkError.serverError("No authenticated merchant")
        }
        let branchId = try activeOperationalBranchId()
        let queryItems = [
            URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)"),
            URLQueryItem(name: "branch_id", value: "eq.\(branchId)")
        ]
        let data = try await sendSupabaseRequest(
            method: "GET", endpoint: "restaurant_tables", queryItems: queryItems
        )
        return (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
    }

    func fetchActiveRestaurantTables() async throws -> [[String: Any]] {
        let rows = try await fetchRestaurantTables()
        return rows.filter { !($0["is_deleted"] as? Bool ?? false) }
    }

    func fetchRestaurantTable(id: UUID) async throws -> [String: Any]? {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        let branchId = try activeOperationalBranchId()
        let data = try await sendSupabaseRequest(
            method: "GET", endpoint: "restaurant_tables",
            queryItems: [
                URLQueryItem(name: "select", value: "id,is_deleted,merchant_id,branch_id,table_number,dining_area_id"),
                URLQueryItem(name: "id", value: "eq.\(id.uuidString.lowercased())"),
                URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)"),
                URLQueryItem(name: "branch_id", value: "eq.\(branchId)"),
                URLQueryItem(name: "limit", value: "1")
            ]
        )
        return (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]])?.first
    }

    func uploadRestaurantTable(table: RestaurantTable) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        let activeBranchId = BranchContext.shared.activeBranchIDString
        let branchId = UUID(uuidString: table.branchId) != nil ? table.branchId : activeBranchId
        guard UUID(uuidString: branchId) != nil, let diningAreaId = table.floorId else { return false }
        var payload: [String: Any] = [
            "id": table.id.uuidString.lowercased(),
            "merchant_id": merchantId,
            "branch_id": branchId,
            "table_number": table.tableNumber,
            "capacity": table.capacity,
            "table_shape": table.tableShape,
            "is_round": table.isRound,
            "qr_code_identifier": table.qrCodeIdentifier ?? "",
            "position_x": table.positionX,
            "position_y": table.positionY,
            "layout_scale": table.resolvedLayoutScale,
            "floor": table.floor ?? 1,
            "is_deleted": table.isDeleted,
            "zone": table.zone ?? "Indoor",
            "updated_at": NetworkManager.iso8601.string(from: table.updatedAt)
        ]
        payload["dining_area_id"] = diningAreaId.uuidString.lowercased()

        // Join/split: child → leader UUID; NULL clears the link on upsert.
        if let parent = table.joinedParent, !parent.isDeleted, parent.id != table.id {
            payload["joined_parent_table_id"] = parent.id.uuidString.lowercased()
        } else {
            payload["joined_parent_table_id"] = NSNull()
        }

        // occupied is derived from active table_sessions on the server.
        if table.status != "occupied" {
            payload["status"] = table.status
        }

        var patchPayload = payload
        patchPayload.removeValue(forKey: "id")

        // Update the exact row first. Matching by table number here lets a stale
        // local duplicate resurrect a different row that was just soft-deleted.
        let patchData = try await sendSupabaseRequest(
            method: "PATCH",
            endpoint: "restaurant_tables",
            queryItems: [
                URLQueryItem(name: "id", value: "eq.\(table.id.uuidString.lowercased())"),
                URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)"),
                // A stale device must never revive a server tombstone. Reusing
                // a deleted table number is handled below only for a genuinely
                // new local UUID created by Add Table.
                URLQueryItem(name: "is_deleted", value: "eq.false")
            ],
            payload: patchPayload
        )
        let patchedCount = (try? JSONSerialization.jsonObject(with: patchData) as? [[String: Any]])?.count ?? 0
        if patchedCount > 0 { return true }

        // PATCH returns no row both when an ID is unknown and when it is a
        // tombstone. Distinguish them before the logical-key reuse fallback:
        // the latter is a deletion observed from another device and must stay
        // deleted, while the former may be an intentional re-creation.
        let exactRowData = try await sendSupabaseRequest(
            method: "GET",
            endpoint: "restaurant_tables",
            queryItems: [
                URLQueryItem(name: "select", value: "id,is_deleted"),
                URLQueryItem(name: "id", value: "eq.\(table.id.uuidString.lowercased())"),
                URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)"),
                URLQueryItem(name: "limit", value: "1")
            ]
        )
        if let exactRows = try? JSONSerialization.jsonObject(with: exactRowData) as? [[String: Any]],
           let exactRow = exactRows.first,
           exactRow["is_deleted"] as? Bool == true {
            // pullRestaurantTables will apply the tombstone to the local model
            // in this same sync cycle. Returning success prevents retries from
            // reaching the resurrection/upsert path in the meantime.
            return true
        }

        // New local UUID with a reused table number: preserve the historical
        // server UUID so existing order/session foreign keys remain valid.
        let reusedData = try await sendSupabaseRequest(
            method: "PATCH",
            endpoint: "restaurant_tables",
            queryItems: [
                URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)"),
                URLQueryItem(name: "branch_id", value: "eq.\(branchId)"),
                URLQueryItem(name: "dining_area_id", value: "eq.\(diningAreaId.uuidString.lowercased())"),
                URLQueryItem(name: "table_number", value: "eq.\(table.tableNumber)")
            ],
            payload: patchPayload
        )
        let reusedCount = (try? JSONSerialization.jsonObject(with: reusedData) as? [[String: Any]])?.count ?? 0
        if reusedCount > 0 { return true }

        // No matching number exists yet: create it.
        _ = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "restaurant_tables",
            queryItems: [URLQueryItem(name: "on_conflict", value: "merchant_id,branch_id,dining_area_id,table_number")],
            payload: payload
        )
        return true
    }

    func deleteRestaurantTableOnServer(id: UUID) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        _ = try await sendSupabaseRequest(
            method: "PATCH",
            endpoint: "restaurant_tables",
            queryItems: [
                URLQueryItem(name: "id", value: "eq.\(id.uuidString.lowercased())"),
                URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)")
            ],
            payload: [
                "is_deleted": true,
                "updated_at": NetworkManager.iso8601.string(from: Date())
            ]
        )
        return true
    }

    func deleteRestaurantTablesOnServer(ids: [UUID]) async throws -> Int {
        guard !ids.isEmpty else { return 0 }
        #if DEBUG
        print("[TableDelete][Network] POST RPC bulk_soft_delete ids=\(ids.map(\.uuidString))")
        #endif
        let data = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "rpc/bulk_soft_delete_restaurant_tables",
            payload: ["p_table_ids": ids.map { $0.uuidString.lowercased() }]
        )
        let count = try JSONDecoder().decode(Int.self, from: data)
        #if DEBUG
        print("[TableDelete][Network] RPC decoded count=\(count)")
        #endif
        return count
    }

    func fetchRestaurantWalls() async throws -> [[String: Any]] {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        let data = try await sendSupabaseRequest(method: "GET", endpoint: "restaurant_walls", queryItems: [
            URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)"),
            URLQueryItem(name: "is_deleted", value: "eq.false")
        ])
        return (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
    }

    func uploadRestaurantWall(wall: RestaurantWall) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
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
