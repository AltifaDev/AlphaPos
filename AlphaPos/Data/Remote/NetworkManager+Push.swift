// NetworkManager+Push.swift
// AlphaPos — Invoke send-staff-push Edge Function (inventory alerts, etc.)

import Foundation

extension NetworkManager {
    /// Fire-and-forget staff push via Edge Function. Prefer merchant JWT so RLS auth matches.
    @discardableResult
    func sendStaffPush(
        eventType: String,
        title: String? = nil,
        message: String? = nil,
        inventoryItemId: String? = nil,
        inventoryItemName: String? = nil
    ) async -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        guard !merchantId.isEmpty else { return false }

        var body: [String: Any] = [
            "event_type": eventType,
            "merchant_id": merchantId
        ]
        if let title { body["title"] = title }
        if let message { body["message"] = message }
        if let inventoryItemId { body["inventory_item_id"] = inventoryItemId }
        if let inventoryItemName { body["inventory_item_name"] = inventoryItemName }

        let url = config.edgeFunctionURL.appendingPathComponent("send-staff-push")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        let token = MerchantAuthManager.shared.authorizationToken ?? anonKey
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 12
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (_, response) = try await AppNetworkTransport.data(for: request, purpose: .pushRegistration)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            return (200...299).contains(code)
        } catch {
            #if DEBUG
            print("NetworkManager [sendStaffPush]: \(error.localizedDescription)")
            #endif
            return false
        }
    }
}
