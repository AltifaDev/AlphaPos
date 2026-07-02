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
        let hash = pin.sha256Hash
        return save(hash, forKey: "merchant_owner_pin_hash")
    }
    
    func verifyOwnerPin(_ enteredPin: String) -> Bool {
        guard let savedHash = retrieve(forKey: "merchant_owner_pin_hash") else {
            // Default pin is "8888"
            let defaultHash = "8888".sha256Hash
            return enteredPin.sha256Hash == defaultHash
        }
        return enteredPin.sha256Hash == savedHash
    }
    
    func isDefaultPinActive() -> Bool {
        guard let savedHash = retrieve(forKey: "merchant_owner_pin_hash") else {
            return true
        }
        return savedHash == "8888".sha256Hash
    }
}

import CryptoKit

extension String {
    var sha256Hash: String {
        let inputData = Data(self.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
}
