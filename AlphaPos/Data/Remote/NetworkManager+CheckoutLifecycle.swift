import Foundation

extension NetworkManager {
    func uploadCheckoutSession(_ session: CheckoutSession) async throws -> Bool {
        var payload: [String: Any] = [
            "id": session.id.uuidString.lowercased(),
            "merchant_id": session.merchantId.uuidString.lowercased(),
            "service_mode": session.serviceMode,
            "state": session.state,
            "version": session.version,
            "created_at": Self.iso8601.string(from: session.createdAt),
            "updated_at": Self.iso8601.string(from: session.updatedAt),
            "is_deleted": session.isDeleted
        ]
        if let id = session.order?.id { payload["order_id"] = id.uuidString.lowercased() }
        if let value = session.lockedByDevice { payload["locked_by_device"] = value }
        if let value = session.lockedAt { payload["locked_at"] = Self.iso8601.string(from: value) }
        if let value = session.parkedAt { payload["parked_at"] = Self.iso8601.string(from: value) }
        if let value = session.completedAt { payload["completed_at"] = Self.iso8601.string(from: value) }
        _ = try await sendSupabaseRequest(method: "POST", endpoint: "checkout_sessions",
            queryItems: [URLQueryItem(name: "on_conflict", value: "id")], payload: payload)
        return true
    }

    func uploadPaymentAttempt(_ attempt: PaymentAttempt) async throws -> Bool {
        var payload: [String: Any] = [
            "id": attempt.id.uuidString.lowercased(),
            "merchant_id": attempt.merchantId.uuidString.lowercased(),
            "idempotency_key": attempt.idempotencyKey,
            "method": attempt.method,
            "amount": attempt.amount,
            "currency": attempt.currency,
            "status": attempt.status,
            "created_at": Self.iso8601.string(from: attempt.createdAt),
            "updated_at": Self.iso8601.string(from: attempt.updatedAt),
            "is_deleted": attempt.isDeleted
        ]
        if let id = attempt.checkoutSession?.id { payload["checkout_session_id"] = id.uuidString.lowercased() }
        if let id = attempt.order?.id { payload["order_id"] = id.uuidString.lowercased() }
        if let value = attempt.providerReference { payload["provider_reference"] = value }
        if let value = attempt.failureReason { payload["failure_reason"] = value }
        if let value = attempt.expiresAt { payload["expires_at"] = Self.iso8601.string(from: value) }
        _ = try await sendSupabaseRequest(method: "POST", endpoint: "payment_attempts",
            queryItems: [URLQueryItem(name: "on_conflict", value: "id")], payload: payload)
        return true
    }
}
