import Foundation

extension NetworkManager {
    func uploadInventoryComplianceRow(endpoint: String, id: UUID, fields: [String: Any]) async throws {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        var payload = fields.mapValues { value -> Any in
            let mirror = Mirror(reflecting: value)
            guard mirror.displayStyle == .optional else { return value }
            return mirror.children.first?.value ?? NSNull()
        }
        payload["id"] = id.uuidString.lowercased()
        payload["merchant_id"] = merchantId
        payload["updated_at"] = Self.iso8601.string(from: Date())
        _ = try await sendSupabaseRequest(method: "POST", endpoint: endpoint,
            queryItems: [URLQueryItem(name: "on_conflict", value: "id")], payload: payload)
    }
}
