import Foundation
import CryptoKit
import SwiftData

extension NetworkManager {
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
                // M10: upsert on id; Supabase unique constraint on (merchant_id, email) or (merchant_id, phone) will reject true duplicates
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
}
