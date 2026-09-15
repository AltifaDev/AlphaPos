import Foundation

extension NetworkManager {
    func uploadFinancialEvent(_ event: FinancialEvent) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        var payload: [String: Any] = [
            "id": event.id.uuidString.lowercased(),
            "merchant_id": merchantId,
            "branch_id": event.branchId.uuidString.lowercased(),
            "source_event_key": event.sourceEventKey,
            "event_type": event.eventType,
            "source_type": event.sourceType,
            "source_id": event.sourceId.uuidString.lowercased(),
            "business_date": event.businessDateKey,
            "occurred_at": Self.iso8601.string(from: event.occurredAt),
            "recorded_at": Self.iso8601.string(from: event.recordedAt),
            "amount": event.amount,
            "status": event.status,
            "is_late_adjustment": event.isLateAdjustment,
            "is_deleted": event.isDeleted,
            "updated_at": Self.iso8601.string(from: event.updatedAt)
        ]
        if let id = event.orderId { payload["order_id"] = id.uuidString.lowercased() }
        if let id = event.registerSessionId { payload["register_session_id"] = id.uuidString.lowercased() }
        if let method = event.paymentMethod { payload["payment_method"] = method }
        if let id = event.revisionOfEventId { payload["revision_of_event_id"] = id.uuidString.lowercased() }
        if let id = event.sourceDeviceId { payload["source_device_id"] = id }
        _ = try await sendSupabaseRequest(
            method: "POST", endpoint: "financial_events",
            queryItems: [URLQueryItem(name: "on_conflict", value: "merchant_id,source_event_key")],
            payload: payload
        )
        return true
    }

    func fetchFinancialEvents() async throws -> [[String: Any]] {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        let branchId = try activeOperationalBranchId()
        let data = try await sendSupabaseRequest(
            method: "GET", endpoint: "financial_events",
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)"),
                URLQueryItem(name: "branch_id", value: "eq.\(branchId)"),
                URLQueryItem(name: "is_deleted", value: "eq.false"),
                URLQueryItem(name: "order", value: "recorded_at.desc"),
                URLQueryItem(name: "limit", value: "5000")
            ]
        )
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw NetworkError.invalidResponse
        }
        return rows
    }

    func uploadShiftClosureSnapshot(_ value: ShiftClosureSnapshot) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        var payload: [String: Any] = [
            "id": value.id.uuidString.lowercased(), "merchant_id": merchantId,
            "branch_id": value.branchId.uuidString.lowercased(),
            "register_session_id": value.registerSessionId.uuidString.lowercased(),
            "business_date": value.businessDateKey, "version": value.version,
            "opened_at": Self.iso8601.string(from: value.openedAt),
            "closed_at": Self.iso8601.string(from: value.closedAt),
            "opening_cash": value.openingCash, "gross_sales": value.grossSales,
            "discounts": value.discounts, "net_sales": value.netSales,
            "refunds": value.refunds, "tax": value.tax,
            "service_charge": value.serviceCharge, "cash_sales": value.cashSales,
            "card_sales": value.cardSales, "qr_sales": value.qrSales,
            "other_sales": value.otherSales, "cash_in": value.cashIn,
            "cash_out": value.cashOut, "expected_cash": value.expectedCash,
            "actual_cash": value.actualCash, "discrepancy": value.discrepancy,
            "transaction_count": value.transactionCount,
            "late_adjustment_total": value.lateAdjustmentTotal,
            "generated_at": Self.iso8601.string(from: value.generatedAt)
        ]
        if let id = value.generatedByUserId { payload["generated_by_user_id"] = id.uuidString.lowercased() }
        _ = try await sendSupabaseRequest(method: "POST", endpoint: "shift_closure_snapshots", queryItems: [URLQueryItem(name: "on_conflict", value: "merchant_id,register_session_id,version")], payload: payload)
        return true
    }

    func uploadDailySalesSnapshot(_ value: DailySalesSnapshot) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        let payload: [String: Any] = [
            "id": value.id.uuidString.lowercased(), "merchant_id": merchantId,
            "branch_id": value.branchId.uuidString.lowercased(),
            "business_date": value.businessDateKey, "version": value.version,
            "gross_sales": value.grossSales, "discounts": value.discounts,
            "net_sales": value.netSales, "refunds": value.refunds,
            "tax": value.tax, "service_charge": value.serviceCharge,
            "cash_sales": value.cashSales, "card_sales": value.cardSales,
            "qr_sales": value.qrSales, "other_sales": value.otherSales,
            "order_count": value.orderCount, "payment_count": value.paymentCount,
            "late_adjustment_total": value.lateAdjustmentTotal,
            "calculated_through": Self.iso8601.string(from: value.calculatedThrough),
            "updated_at": Self.iso8601.string(from: value.updatedAt)
        ]
        _ = try await sendSupabaseRequest(method: "POST", endpoint: "daily_sales_snapshots", queryItems: [URLQueryItem(name: "on_conflict", value: "merchant_id,branch_id,business_date,version")], payload: payload)
        return true
    }
}
