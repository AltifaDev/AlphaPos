import Foundation

/// Persists "Remember this store" preference and remembered owner email only.
/// Never stores passwords — merchant session continuity uses Keychain JWT after login.
enum RememberStorePreferences {
    static let enabledKey = "remember_store_enabled"
    static let emailKey = "remembered_merchant_email"

    static var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: enabledKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: enabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var rememberedEmail: String {
        get { UserDefaults.standard.string(forKey: emailKey) ?? "" }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if trimmed.isEmpty {
                UserDefaults.standard.removeObject(forKey: emailKey)
            } else {
                UserDefaults.standard.set(trimmed, forKey: emailKey)
            }
        }
    }

    /// Call after a successful merchant login.
    static func applyAfterSuccessfulLogin(email: String) {
        if isEnabled {
            rememberedEmail = email
        } else {
            rememberedEmail = ""
        }
    }

    /// Call when the owner signs out of the store account.
    static func applyAfterLogout() {
        rememberedEmail = ""
        isEnabled = false
    }
}
