import Foundation
import CryptoKit
import SwiftData

extension NetworkManager {
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

// MARK: - String UUID Helper

extension String {
    /// Produces a deterministic UUID v5-like string from a seed string using SHA256.
    /// Used by NetworkManager.createServiceRequest() to prevent duplicate records on retry.
    var deterministicUUIDString: String {
        let data = Data(self.utf8)
        let hash = SHA256.hash(data: data)
        var bytes = Array(hash.prefix(16))
        // Set version (4 bits) = 5, variant = RFC 4122
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        let s = hex
        return "\(s.prefix(8))-\(s.dropFirst(8).prefix(4))-\(s.dropFirst(12).prefix(4))-\(s.dropFirst(16).prefix(4))-\(s.dropFirst(20).prefix(12))"
    }
}
