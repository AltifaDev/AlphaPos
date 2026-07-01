// NetworkService+Subscription.swift
// AlphaPosStaff — ดึงข้อมูลและตรวจสอบสถานะสมาชิกจากเซิร์ฟเวอร์

import Foundation

extension NetworkService {
    struct MerchantSubscription: Codable {
        let subscriptionTier: String?
        let subscriptionStatus: String?
        let subscriptionExpiresAt: String?
        
        enum CodingKeys: String, CodingKey {
            case subscriptionTier = "subscription_tier"
            case subscriptionStatus = "subscription_status"
            case subscriptionExpiresAt = "subscription_expires_at"
        }
    }
    
    /// Fetches the subscription details of the currently active merchant.
    func fetchMerchantSubscription(merchantId: String) async throws -> MerchantSubscription {
        let queryItems = [
            URLQueryItem(name: "select", value: "subscription_tier,subscription_status,subscription_expires_at"),
            URLQueryItem(name: "id", value: "eq.\(merchantId.lowercased())")
        ]
        
        let data = try await sendSupabaseRequest(
            method: "GET",
            endpoint: "merchants",
            queryItems: queryItems
        )
        
        let decoder = JSONDecoder()
        let results = try decoder.decode([MerchantSubscription].self, from: data)
        guard let first = results.first else {
            throw NSError(
                domain: "NetworkService",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Merchant not found"]
            )
        }
        return first
    }
}
