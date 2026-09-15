import CryptoKit
import Foundation
import UIKit

extension NetworkService {
    func validatePairingToken(token: String) async throws -> String {
        let value = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        guard (60...128).contains(value.count),
              value.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw PairingError.invalidCredential
        }
        return try await consumePairing(token: value, code: nil)
    }

    /// Submit 6-digit code → wait for POS Approve → receive JWT.
    func validatePairingCode(code: String) async throws -> String {
        let value = code.filter(\.isNumber)
        guard value.count == 6 else { throw PairingError.invalidCredential }
        switch try await requestCodePairing(code: value) {
        case .completed(let merchantId):
            return merchantId
        case .pending(let pending):
            return try await waitForPairingApproval(
                deviceId: pending.deviceId,
                merchantId: pending.merchantId,
                branchId: pending.branchId,
                refreshToken: pending.refreshToken
            )
        }
    }

    private enum CodePairingResult {
        case completed(String)
        case pending(PendingPairing)
    }

    private func requestCodePairing(code: String) async throws -> CodePairingResult {
        let url = AppConfig.supabaseURL.appendingPathComponent("functions/v1/issue-merchant-token")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(AppConfig.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? UIDevice.current.name
        let fingerprint = SHA256.hash(data: Data(deviceId.utf8)).map { String(format: "%02x", $0) }.joined()
        let payload: [String: Any] = [
            "pairing_code": code,
            "device_name": UIDevice.current.name,
            "device_fingerprint_hash": fingerprint
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PairingError.invalidResponse }

        guard (200...299).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(PairingErrorResponse.self, from: data).error)
                ?? "Pairing failed"
            throw PairingError.server(message)
        }

        if http.statusCode == 202
            || (try? JSONDecoder().decode(PendingPairingResponse.self, from: data).status) == "pending_approval" {
            let pending = try JSONDecoder().decode(PendingPairingResponse.self, from: data)
            return .pending(PendingPairing(
                deviceId: pending.deviceId,
                merchantId: pending.merchantId,
                branchId: pending.branchId,
                refreshToken: pending.refreshToken
            ))
        }

        let result = try JSONDecoder().decode(PairingAuthResponse.self, from: data)
        MerchantAuthManager.shared.acceptPairedSession(
            accessToken: result.accessToken,
            expiresIn: result.expiresIn,
            merchantId: result.merchantId,
            deviceId: result.deviceId,
            refreshToken: result.refreshToken
        )
        UserDefaults.standard.set(result.branchId, forKey: "active_branch_id")
        UserDefaults.standard.set(result.deviceId, forKey: "paired_device_id")
        return .completed(result.merchantId)
    }

    private func waitForPairingApproval(
        deviceId: String,
        merchantId: String,
        branchId: String,
        refreshToken: String
    ) async throws -> String {
        let url = AppConfig.supabaseURL.appendingPathComponent("functions/v1/refresh-token")
        let deadline = Date().addingTimeInterval(5 * 60)

        while Date() < deadline {
            try Task.checkCancellation()

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(AppConfig.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 15
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "device_id": deviceId,
                "refresh_token": refreshToken
            ])

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw PairingError.invalidResponse }

            if http.statusCode == 202 {
                try await Task.sleep(nanoseconds: 2_000_000_000)
                continue
            }

            if http.statusCode == 410 {
                throw PairingError.server("Pairing was rejected on the POS iPad")
            }

            guard (200...299).contains(http.statusCode) else {
                let message = (try? JSONDecoder().decode(PairingErrorResponse.self, from: data).error)
                    ?? "Waiting for POS approval failed"
                throw PairingError.server(message)
            }

            let result = try JSONDecoder().decode(RefreshAuthResponse.self, from: data)
            MerchantAuthManager.shared.acceptPairedSession(
                accessToken: result.accessToken,
                expiresIn: result.expiresIn,
                merchantId: result.merchantId,
                deviceId: deviceId,
                refreshToken: refreshToken
            )
            UserDefaults.standard.set(branchId, forKey: "active_branch_id")
            UserDefaults.standard.set(deviceId, forKey: "paired_device_id")
            return merchantId
        }

        throw PairingError.server("Timed out waiting for POS approval")
    }

    private func consumePairing(token: String?, code: String?) async throws -> String {
        let url = AppConfig.supabaseURL.appendingPathComponent("functions/v1/issue-merchant-token")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(AppConfig.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? UIDevice.current.name
        let fingerprint = SHA256.hash(data: Data(deviceId.utf8)).map { String(format: "%02x", $0) }.joined()
        var payload: [String: Any] = [
            "device_name": UIDevice.current.name,
            "device_fingerprint_hash": fingerprint
        ]
        if let token { payload["pairing_token"] = token }
        if let code { payload["pairing_code"] = code }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PairingError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(PairingErrorResponse.self, from: data).error)
                ?? "Pairing failed"
            throw PairingError.server(message)
        }

        let result = try JSONDecoder().decode(PairingAuthResponse.self, from: data)
        MerchantAuthManager.shared.acceptPairedSession(
            accessToken: result.accessToken,
            expiresIn: result.expiresIn,
            merchantId: result.merchantId,
            deviceId: result.deviceId,
            refreshToken: result.refreshToken
        )
        UserDefaults.standard.set(result.branchId, forKey: "active_branch_id")
        UserDefaults.standard.set(result.deviceId, forKey: "paired_device_id")
        return result.merchantId
    }

    private struct PendingPairing {
        let deviceId: String
        let merchantId: String
        let branchId: String
        let refreshToken: String
    }

    private struct PendingPairingResponse: Decodable {
        let status: String?
        let merchantId: String
        let branchId: String
        let deviceId: String
        let refreshToken: String

        enum CodingKeys: String, CodingKey {
            case status
            case merchantId = "merchant_id"
            case branchId = "branch_id"
            case deviceId = "device_id"
            case refreshToken = "refresh_token"
        }
    }

    private struct PairingAuthResponse: Decodable {
        let accessToken: String
        let expiresIn: Int
        let merchantId: String
        let branchId: String
        let deviceId: String
        let refreshToken: String

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case expiresIn = "expires_in"
            case merchantId = "merchant_id"
            case branchId = "branch_id"
            case deviceId = "device_id"
            case refreshToken = "refresh_token"
        }
    }

    private struct RefreshAuthResponse: Decodable {
        let accessToken: String
        let expiresIn: Int
        let merchantId: String

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case expiresIn = "expires_in"
            case merchantId = "merchant_id"
        }
    }

    private struct PairingErrorResponse: Decodable { let error: String }

    private enum PairingError: LocalizedError {
        case invalidCredential
        case invalidResponse
        case server(String)

        var errorDescription: String? {
            switch self {
            case .invalidCredential: return "Invalid pairing QR code or 6-digit code"
            case .invalidResponse: return "Invalid response from pairing server"
            case .server(let message): return message
            }
        }
    }
}
