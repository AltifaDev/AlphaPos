import Foundation
import Security

final class KeychainManager {
    static let shared = KeychainManager()

    private init() {}

    @discardableResult
    func save(_ value: String, forKey key: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        // Delete existing item if it exists
        delete(forKey: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    func retrieve(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)

        guard status == errSecSuccess, let data = dataTypeRef as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    func delete(forKey key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess
    }

    // MARK: - Owner PIN Hashed Methods

    func saveOwnerPin(_ pin: String) -> Bool {
        save(SecurityHelper.hashPIN(pin), forKey: "merchant_owner_pin_hash")
    }

    func verifyOwnerPin(_ enteredPin: String) -> Bool {
        guard let savedHash = retrieve(forKey: "merchant_owner_pin_hash") else {
            if enteredPin == "8888" {
                _ = saveOwnerPin("8888")
                return true
            }
            return false
        }
        let verified = SecurityHelper.verifyPIN(enteredPin, against: savedHash)
        // Transparently upgrade the previous unsalted SHA-256 format.
        if verified && !savedHash.hasPrefix("iter:") {
            _ = saveOwnerPin(enteredPin)
        }
        return verified
    }

    func isDefaultPinActive() -> Bool {
        retrieve(forKey: "merchant_owner_pin_hash") == nil
    }
}
