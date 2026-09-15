import CryptoKit
import Foundation

struct OfflineEntitlement: Codable, Equatable, Sendable {
    let merchantId: String
    let deviceId: String
    let subscriptionTier: String
    let issuedAt: Date
    let validUntil: Date?
}

/// Tamper-evident proof that this device completed a successful online login.
enum OfflineEntitlementStore {
    private static let payloadKey = "alphapos_offline_entitlement_payload_v1"
    private static let signatureKey = "alphapos_offline_entitlement_signature_v1"
    private static let signingKeyKey = "alphapos_offline_entitlement_signing_key_v1"

    @discardableResult
    static func issue(merchantId: String, deviceId: String, subscriptionTier: String, subscriptionExpiry: Double?) -> Bool {
        let now = Date()
        let validUntil: Date?
        if subscriptionTier == "offline_perpetual" {
            validUntil = nil
        } else if let subscriptionExpiry {
            validUntil = Date(timeIntervalSince1970: subscriptionExpiry)
        } else {
            validUntil = Calendar.current.date(byAdding: .day, value: 90, to: now)
        }
        let entitlement = OfflineEntitlement(
            merchantId: merchantId.lowercased(), deviceId: deviceId.lowercased(),
            subscriptionTier: subscriptionTier, issuedAt: now, validUntil: validUntil
        )
        guard let payload = try? JSONEncoder().encode(entitlement),
              let payloadString = String(data: payload, encoding: .utf8),
              let key = signingKey() else { return false }
        let signature = Data(HMAC<SHA256>.authenticationCode(for: payload, using: key)).base64EncodedString()
        return KeychainManager.shared.save(payloadString, forKey: payloadKey)
            && KeychainManager.shared.save(signature, forKey: signatureKey)
    }

    static func validated(merchantId: String?, deviceId: String?, now: Date = Date()) -> OfflineEntitlement? {
        guard let merchantId, let deviceId,
              let payloadString = KeychainManager.shared.retrieve(forKey: payloadKey),
              let payload = payloadString.data(using: .utf8),
              let signatureString = KeychainManager.shared.retrieve(forKey: signatureKey),
              let signature = Data(base64Encoded: signatureString),
              let key = signingKey(createIfMissing: false),
              HMAC<SHA256>.isValidAuthenticationCode(signature, authenticating: payload, using: key),
              let entitlement = try? JSONDecoder().decode(OfflineEntitlement.self, from: payload),
              entitlement.merchantId == merchantId.lowercased(),
              entitlement.deviceId == deviceId.lowercased(),
              entitlement.validUntil.map({ now <= $0 }) ?? true else { return nil }
        return entitlement
    }

    static func clear() {
        KeychainManager.shared.delete(forKey: payloadKey)
        KeychainManager.shared.delete(forKey: signatureKey)
        KeychainManager.shared.delete(forKey: signingKeyKey)
    }

    private static func signingKey(createIfMissing: Bool = true) -> SymmetricKey? {
        if let encoded = KeychainManager.shared.retrieve(forKey: signingKeyKey),
           let data = Data(base64Encoded: encoded) { return SymmetricKey(data: data) }
        guard createIfMissing else { return nil }
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        guard KeychainManager.shared.save(data.base64EncodedString(), forKey: signingKeyKey) else { return nil }
        return key
    }
}
