// NetworkService+Pairing.swift
// AlphaPosStaff — ตรวจสอบและประมวลผลโทเค็น/รหัสจับคู่ของพนักงานกับเซิร์ฟเวอร์

import Foundation

extension NetworkService {
    struct PairingResponse: Codable {
        let id: UUID
        let merchantId: UUID
        let branchId: UUID
        let token: String
        let pairingCode: String
        let expiresAt: String
        let isUsed: Bool
        
        enum CodingKeys: String, CodingKey {
            case id
            case merchantId = "merchant_id"
            case branchId = "branch_id"
            case token
            case pairingCode = "pairing_code"
            case expiresAt = "expires_at"
            case isUsed = "is_used"
        }
    }
    
    /// Validates a pairing token from a QR Code scan.
    /// Sets is_used to true on success and returns the merchant ID.
    func validatePairingToken(token: String) async throws -> String {
        let nowStr = ISO8601DateFormatter().string(from: Date())
        let queryItems = [
            URLQueryItem(name: "token", value: "eq.\(token)"),
            URLQueryItem(name: "is_used", value: "eq.false"),
            URLQueryItem(name: "expires_at", value: "gt.\(nowStr)")
        ]
        
        let data = try await sendSupabaseRequest(
            method: "GET",
            endpoint: "device_pairing_tokens",
            queryItems: queryItems
        )
        
        let decoder = JSONDecoder()
        let results = try decoder.decode([PairingResponse].self, from: data)
        guard let first = results.first else {
            throw NSError(domain: "NetworkService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Invalid or expired pairing QR Code"])
        }
        
        // Mark as used
        let patchPayload: [String: Any] = ["is_used": true]
        let patchQuery = [URLQueryItem(name: "id", value: "eq.\(first.id.uuidString.lowercased())")]
        _ = try await sendSupabaseRequest(
            method: "PATCH",
            endpoint: "device_pairing_tokens",
            queryItems: patchQuery,
            payload: patchPayload
        )
        
        return first.merchantId.uuidString.lowercased()
    }
    
    /// Validates a 6-digit numeric passcode.
    /// Sets is_used to true on success and returns the merchant ID.
    func validatePairingCode(code: String) async throws -> String {
        let cleaned = code.replacingOccurrences(of: " ", with: "")
        guard cleaned.count == 6 else {
            throw NSError(domain: "NetworkService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Pairing code must be 6 digits"])
        }
        
        let nowStr = ISO8601DateFormatter().string(from: Date())
        let queryItems = [
            URLQueryItem(name: "pairing_code", value: "eq.\(cleaned)"),
            URLQueryItem(name: "is_used", value: "eq.false"),
            URLQueryItem(name: "expires_at", value: "gt.\(nowStr)")
        ]
        
        let data = try await sendSupabaseRequest(
            method: "GET",
            endpoint: "device_pairing_tokens",
            queryItems: queryItems
        )
        
        let decoder = JSONDecoder()
        let results = try decoder.decode([PairingResponse].self, from: data)
        guard let first = results.first else {
            throw NSError(domain: "NetworkService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Invalid or expired pairing code"])
        }
        
        // Mark as used
        let patchPayload: [String: Any] = ["is_used": true]
        let patchQuery = [URLQueryItem(name: "id", value: "eq.\(first.id.uuidString.lowercased())")]
        _ = try await sendSupabaseRequest(
            method: "PATCH",
            endpoint: "device_pairing_tokens",
            queryItems: patchQuery,
            payload: patchPayload
        )
        
        return first.merchantId.uuidString.lowercased()
    }
}
