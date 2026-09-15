import Foundation
import Security

final class KeychainManager {
    static let shared = KeychainManager()

    private let ownerPinHashKey = "merchant_owner_pin_hash"
    private let openRouterAPIKeyKey = "openrouter_api_key"
    private let service = Bundle.main.bundleIdentifier ?? "AltifaDev.AlphaPos"

    /// Common PINs that must never be accepted as the store-owner passcode.
    static let bannedOwnerPins: Set<String> = [
        "0000", "1111", "2222", "3333", "4444", "5555", "6666", "7777", "8888", "9999",
        "1234", "4321", "1212", "1010", "2580",
    ]

    private var memoryFallback: [String: String] = [:]

    private init() {}

    @discardableResult
    func save(_ value: String, forKey key: String) -> Bool {
        #if TEST_RUNNER
        memoryFallback[key] = value
        #endif

        guard let data = value.data(using: .utf8) else { return false }

        let query = itemQuery(forKey: key)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var newItem = query
            attributes.forEach { newItem[$0.key] = $0.value }
            status = SecItemAdd(newItem as CFDictionary, nil)

            // Another writer may have inserted the item between update and add.
            if status == errSecDuplicateItem {
                status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            }
        }

        guard status == errSecSuccess else {
            logFailure(operation: "save", key: key, status: status)
            #if TEST_RUNNER
            return true
            #else
            return false
            #endif
        }

        return true
    }

    func retrieve(forKey key: String) -> String? {
        #if TEST_RUNNER
        if let mem = memoryFallback[key] { return mem }
        #endif

        if let value = retrieve(query: itemQuery(forKey: key), key: key) {
            return value
        }

        // One-time compatibility path for values created before kSecAttrService
        // was introduced. Migrate a readable legacy value into the namespaced item.
        guard let legacyValue = retrieve(query: legacyItemQuery(forKey: key), key: key) else {
            return nil
        }
        _ = save(legacyValue, forKey: key)
        return legacyValue
    }

    @discardableResult
    func delete(forKey key: String) -> Bool {
        #if TEST_RUNNER
        memoryFallback.removeValue(forKey: key)
        #endif

        let status = SecItemDelete(itemQuery(forKey: key) as CFDictionary)
        let legacyStatus = SecItemDelete(legacyItemQuery(forKey: key) as CFDictionary)
        let succeeded = (status == errSecSuccess || status == errSecItemNotFound)
            && (legacyStatus == errSecSuccess || legacyStatus == errSecItemNotFound)
        if status != errSecSuccess && status != errSecItemNotFound {
            logFailure(operation: "delete", key: key, status: status)
        }
        if legacyStatus != errSecSuccess && legacyStatus != errSecItemNotFound {
            logFailure(operation: "delete legacy", key: key, status: legacyStatus)
        }
        #if TEST_RUNNER
        return true
        #else
        return succeeded
        #endif
    }

    private func itemQuery(forKey key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: service
        ]
    }

    private func legacyItemQuery(forKey key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
    }

    private func retrieve(query: [String: Any], key: String) -> String? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne

        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(lookup as CFDictionary, &dataTypeRef)

        guard status == errSecSuccess else {
            if status != errSecItemNotFound {
                logFailure(operation: "retrieve", key: key, status: status)
            }
            return nil
        }
        guard let data = dataTypeRef as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func logFailure(operation: String, key: String, status: OSStatus) {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown error"
        NSLog("KeychainManager: %@ failed for key %@ (OSStatus %d: %@)", operation, key, status, message)
    }

    // MARK: - Owner PIN

    /// Digits-only 4–8 length PIN that is not in the banned list.
    static func isAcceptableOwnerPin(_ pin: String) -> Bool {
        let clean = pin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count >= 4, clean.count <= 8, clean.allSatisfy(\.isNumber) else { return false }
        return !bannedOwnerPins.contains(clean)
    }

    @discardableResult
    func saveOwnerPin(_ pin: String) -> Bool {
        guard Self.isAcceptableOwnerPin(pin) else { return false }
        return save(SecurityHelper.hashPIN(pin), forKey: ownerPinHashKey)
    }

    func clearOwnerPin() {
        delete(forKey: ownerPinHashKey)
        UserDefaults.standard.removeObject(forKey: "merchant_owner_pin") // legacy plaintext
    }

    /// True when a real owner PIN exists (not missing, not legacy default 8888).
    func isOwnerPinConfigured() -> Bool {
        guard let savedHash = retrieve(forKey: ownerPinHashKey) else { return false }
        // Legacy builds auto-saved "8888" when unset — treat that as unconfigured.
        if SecurityHelper.verifyPIN("8888", against: savedHash) {
            return false
        }
        return true
    }

    /// Kept for Settings UI; true when the owner must set a PIN.
    func isDefaultPinActive() -> Bool {
        !isOwnerPinConfigured()
    }

    func verifyOwnerPin(_ enteredPin: String) -> Bool {
        // Never accept unlock while PIN is unset / still the insecure legacy default.
        guard isOwnerPinConfigured(),
              let savedHash = retrieve(forKey: ownerPinHashKey) else {
            return false
        }

        let verified = SecurityHelper.verifyPIN(enteredPin, against: savedHash)
        // Transparently upgrade the previous unsalted SHA-256 format.
        if verified && !savedHash.hasPrefix("iter:") {
            _ = save(SecurityHelper.hashPIN(enteredPin), forKey: ownerPinHashKey)
        }
        return verified
    }

    // MARK: - Device-bound PIN throttling

    struct PinAttemptState: Equatable {
        let attempts: Int
        let lockedUntil: Date?
    }

    private func pinAttemptKey(subjectId: String) -> String {
        "pin_attempt_state_" + subjectId.lowercased()
    }

    func pinAttemptState(subjectId: String) -> PinAttemptState {
        guard let raw = retrieve(forKey: pinAttemptKey(subjectId: subjectId)) else {
            return PinAttemptState(attempts: 0, lockedUntil: nil)
        }
        let parts = raw.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, let attempts = Int(parts[0]), let timestamp = Double(parts[1]) else {
            _ = delete(forKey: pinAttemptKey(subjectId: subjectId))
            return PinAttemptState(attempts: 0, lockedUntil: nil)
        }
        let lockedUntil = timestamp > Date().timeIntervalSince1970
            ? Date(timeIntervalSince1970: timestamp)
            : nil
        return PinAttemptState(attempts: lockedUntil == nil ? 0 : attempts, lockedUntil: lockedUntil)
    }

    @discardableResult
    func recordFailedPinAttempt(subjectId: String, maxAttempts: Int, lockoutMinutes: Int) -> PinAttemptState {
        let current = pinAttemptState(subjectId: subjectId)
        let attempts = current.attempts + 1
        let lockedUntil = attempts >= max(1, maxAttempts)
            ? Date().addingTimeInterval(TimeInterval(max(1, lockoutMinutes) * 60))
            : nil
        let timestamp = lockedUntil?.timeIntervalSince1970 ?? 0
        _ = save("\(attempts)|\(timestamp)", forKey: pinAttemptKey(subjectId: subjectId))
        return PinAttemptState(attempts: attempts, lockedUntil: lockedUntil)
    }

    func clearPinAttempts(subjectId: String) {
        _ = delete(forKey: pinAttemptKey(subjectId: subjectId))
    }

    // MARK: - API secrets

    /// Reads the OpenRouter secret and migrates the legacy UserDefaults value
    /// into Keychain exactly once.
    func openRouterAPIKey() -> String {
        if let secured = retrieve(forKey: openRouterAPIKeyKey) { return secured }
        let legacy = UserDefaults.standard.string(forKey: openRouterAPIKeyKey) ?? ""
        guard !legacy.isEmpty else { return "" }
        if save(legacy, forKey: openRouterAPIKeyKey) {
            UserDefaults.standard.removeObject(forKey: openRouterAPIKeyKey)
        }
        return legacy
    }

    @discardableResult
    func saveOpenRouterAPIKey(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.removeObject(forKey: openRouterAPIKeyKey)
        return trimmed.isEmpty
            ? delete(forKey: openRouterAPIKeyKey)
            : save(trimmed, forKey: openRouterAPIKeyKey)
    }
}
