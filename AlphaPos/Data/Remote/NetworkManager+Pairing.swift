// NetworkManager+Pairing.swift
// AlphaPos — สร้างคำขอรหัสและโทเค็นเชื่อมต่อเครื่องฝั่ง POS

import Foundation

extension NetworkManager {
    struct DevicePairingToken: Codable {
        let id: UUID
        let merchantId: UUID
        let branchId: UUID
        let token: String
        let pairingCode: String
        let expiresAt: Date

        enum CodingKeys: String, CodingKey {
            case id
            case merchantId = "merchant_id"
            case branchId = "branch_id"
            case token
            case pairingCode = "pairing_code"
            case expiresAt = "expires_at"
        }
    }

    /// Generates a dynamic one-time pairing token and numeric passcode on Supabase.
    func createPairingToken(merchantId: UUID, branchId: UUID) async throws -> DevicePairingToken {
        let token = UUID().uuidString + "-" + UUID().uuidString
        let code = String(format: "%06d", Int.random(in: 100000...999999))
        let expires = Date().addingTimeInterval(600) // 10 minutes

        let payload: [String: Any] = [
            "merchant_id": merchantId.uuidString.lowercased(),
            "branch_id": branchId.uuidString.lowercased(),
            "token": token,
            "pairing_code": code,
            "expires_at": NetworkManager.iso8601.string(from: expires)
        ]

        // Use POST with return=representation preference to get created record
        let url = serverBaseURL.appendingPathComponent("device_pairing_tokens")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")

        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        request.httpBody = jsonData

        let (data, response) = try await URLSession.shared.data(for: request)
        let httpStatus = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(httpStatus) else {
            let errStr = String(data: data, encoding: .utf8) ?? "HTTP POST failed"
            throw NSError(domain: "NetworkManager", code: httpStatus, userInfo: [NSLocalizedDescriptionKey: errStr])
        }

        // Decode response to verify it was written
        struct DecodedToken: Codable {
            let id: UUID
            let merchant_id: UUID
            let branch_id: UUID
            let token: String
            let pairing_code: String
            let expires_at: String
        }
        let results = try JSONDecoder().decode([DecodedToken].self, from: data)
        guard let first = results.first else {
            throw NSError(domain: "NetworkManager", code: 500, userInfo: [NSLocalizedDescriptionKey: "No representation returned"])
        }

        let parsedExpiry = NetworkManager.iso8601.date(from: first.expires_at) ?? expires
        return DevicePairingToken(
            id: first.id,
            merchantId: first.merchant_id,
            branchId: first.branch_id,
            token: first.token,
            pairingCode: first.pairing_code,
            expiresAt: parsedExpiry
        )
    }

    // H-5: Poll Supabase to check if Staff app has consumed the pairing token
    // Returns the newly registered MerchantDevice if paired, nil if still waiting.
    func checkPairingStatus(token: String) async throws -> PairedDeviceInfo? {
        let url = serverBaseURL
            .appendingPathComponent("merchant_devices")
            .appending(queryItems: [
                URLQueryItem(name: "pairing_token", value: "eq.\(token)"),
                URLQueryItem(name: "limit", value: "1")
            ])
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        let httpStatus = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(httpStatus) else { return nil }

        struct Row: Codable {
            let id: String
            let device_name: String
            let device_type: String
            let branch_id: String?
            let is_trusted: Bool
            let device_fingerprint_hash: String?
            let last_seen_at: String?
            let created_at: String
        }
        let rows = (try? JSONDecoder().decode([Row].self, from: data)) ?? []
        guard let row = rows.first else { return nil }
        return PairedDeviceInfo(
            id: UUID(uuidString: row.id) ?? UUID(),
            deviceName: row.device_name,
            deviceType: row.device_type,
            branchId: row.branch_id.flatMap { UUID(uuidString: $0) },
            isTrusted: row.is_trusted,
            fingerprint: row.device_fingerprint_hash,
            createdAt: NetworkManager.iso8601.date(from: row.created_at) ?? Date()
        )
    }

    struct PairedDeviceInfo {
        let id: UUID
        let deviceName: String
        let deviceType: String
        let branchId: UUID?
        let isTrusted: Bool
        let fingerprint: String?
        let createdAt: Date
    }
}
