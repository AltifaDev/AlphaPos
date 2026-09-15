import Foundation

extension NetworkManager {
    func createSubscriptionPayment(tier: String, billingCycle: String) async throws -> URL {
        var request = URLRequest(url: config.supabaseURL.appendingPathComponent("functions/v1/create-paypal-order"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(MerchantAuthManager.shared.authorizationToken ?? anonKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "subscription_tier": tier,
            "billing_cycle": billingCycle
        ])
        let (data, response) = try await AppNetworkTransport.data(for: request, purpose: .cloudData)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw NetworkError.serverError(String(data: data, encoding: .utf8) ?? "Unable to create payment")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawURL = json["approval_url"] as? String, let url = URL(string: rawURL) else {
            throw NetworkError.invalidResponse
        }
        return url
    }

    func fetchMerchantSettings(merchantId: UUID, allowOfflinePlanRecovery: Bool = false) async throws -> [String: Any]? {
        let data = try await sendSupabaseRequest(
            method: "GET",
            endpoint: "merchants",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(merchantId.uuidString.lowercased())")],
            allowOfflinePlanRecovery: allowOfflinePlanRecovery
        )
        let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        return json?.first
    }

    func updateMerchantFeatureFlags(isTableSystemEnabled: Bool, isWebOrderingEnabled: Bool) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        _ = try await sendSupabaseRequest(
            method: "PATCH",
            endpoint: "merchants",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(merchantId.lowercased())")],
            payload: [
                "is_table_system_enabled": isTableSystemEnabled,
                "is_web_ordering_enabled": isWebOrderingEnabled
            ]
        )
        return true
    }

    func updateMerchantWebCover(url: String?, mediaType: String) async throws {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        guard !merchantId.isEmpty else { throw NetworkError.serverError("Missing merchant ID") }
        let payload: [String: Any] = [
            "web_cover_url": url ?? NSNull(),
            "web_cover_media_type": mediaType
        ]
        _ = try await sendSupabaseRequest(
            method: "PATCH",
            endpoint: "merchants",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(merchantId.lowercased())")],
            payload: payload
        )
    }

    func uploadDeliveryFeeSettings() async throws {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        let brands = ExternalSalesChannel.all
        let settings = Dictionary(uniqueKeysWithValues: brands.map { brand in
            (brand, [
                "gp": UserDefaults.standard.double(forKey: "delivery_gp_\(brand)"),
                "ad_fee": UserDefaults.standard.double(forKey: "delivery_adFee_\(brand)"),
                "ad_fee_is_pct": UserDefaults.standard.bool(forKey: "delivery_adFeeIsPct_\(brand)"),
                "other_fee": UserDefaults.standard.double(forKey: "delivery_otherFee_\(brand)")
            ] as [String: Any])
        })
        _ = try await sendSupabaseRequest(
            method: "PATCH",
            endpoint: "merchants",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(merchantId.lowercased())")],
            payload: ["delivery_fee_settings": settings]
        )
    }
}
