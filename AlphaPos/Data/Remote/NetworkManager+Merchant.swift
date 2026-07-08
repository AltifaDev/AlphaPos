import Foundation

extension NetworkManager {
    func fetchMerchantSettings(merchantId: UUID) async throws -> [String: Any]? {
        let data = try await sendSupabaseRequest(
            method: "GET",
            endpoint: "merchants",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(merchantId.uuidString.lowercased())")]
        )
        let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        return json?.first
    }
}
