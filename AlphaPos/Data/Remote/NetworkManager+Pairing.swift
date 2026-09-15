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

    /// Creates a one-time pairing token + 6-digit code via SECURITY DEFINER RPC.
    /// Direct inserts into `device_pairing_tokens` are revoked for anon/authenticated.
    func createPairingToken(merchantId: UUID, branchId: UUID) async throws -> DevicePairingToken {
        guard !OfflineSyncModeController.isEnabled else { throw NetworkError.offline }
        let payload: [String: Any] = [
            "p_merchant_id": merchantId.uuidString.lowercased(),
            "p_branch_id": branchId.uuidString.lowercased()
        ]

        let data = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "rpc/create_device_pairing",
            payload: payload
        )

        struct Row: Codable {
            let id: UUID
            let merchantId: UUID
            let branchId: UUID
            let token: String
            let pairingCode: String
            let expiresAt: String

            enum CodingKeys: String, CodingKey {
                case id
                case merchantId = "merchant_id"
                case branchId = "branch_id"
                case token
                case pairingCode = "pairing_code"
                case expiresAt = "expires_at"
            }
        }

        let rows = try JSONDecoder().decode([Row].self, from: data)
        guard let row = rows.first else {
            throw NetworkError.serverError("create_device_pairing returned empty result")
        }
        let expires = NetworkManager.iso8601.date(from: row.expiresAt)
            ?? ISO8601DateFormatter().date(from: row.expiresAt)
            ?? Date().addingTimeInterval(600)
        return DevicePairingToken(
            id: row.id,
            merchantId: row.merchantId,
            branchId: row.branchId,
            token: row.token,
            pairingCode: row.pairingCode,
            expiresAt: expires
        )
    }

    /// Poll for a device registered against this pairing token.
    /// - QR path: returns trusted device when Staff finishes scan.
    /// - Code path: first returns pending (`isTrusted=false`), then trusted after Approve.
    func checkPairingStatus(token: String) async throws -> PairedDeviceInfo? {
        guard !OfflineSyncModeController.isEnabled else { throw NetworkError.offline }
        let data = try await sendSupabaseRequest(
            method: "GET",
            endpoint: "merchant_devices",
            queryItems: [
                URLQueryItem(name: "pairing_token", value: "eq.\(token)"),
                URLQueryItem(name: "limit", value: "1")
            ]
        )

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

    func approvePendingDevice(id: UUID) async throws {
        guard !OfflineSyncModeController.isEnabled else { throw NetworkError.offline }
        _ = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "rpc/approve_pending_device_pairing",
            payload: ["p_device_id": id.uuidString.lowercased()]
        )
    }

    func rejectPendingDevice(id: UUID) async throws {
        guard !OfflineSyncModeController.isEnabled else { throw NetworkError.offline }
        _ = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "rpc/reject_pending_device_pairing",
            payload: ["p_device_id": id.uuidString.lowercased()]
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
