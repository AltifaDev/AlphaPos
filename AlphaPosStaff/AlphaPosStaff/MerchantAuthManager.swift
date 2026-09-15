import Foundation
import CryptoKit

/// Manages merchant-specific JWT authentication for the iPhone Staff app.
///
/// Mirror of the iPad `MerchantAuthManager` adapted for the Staff app's architecture.
/// Obtains a per-merchant JWT from the `issue-merchant-token` Edge Function,
/// stores it in Keychain, and auto-refreshes before expiry.
///
/// Devices authenticate only through one-time pairing. No reusable merchant
/// device secret is accepted or stored by the Staff app.
final class MerchantAuthManager {
    static let shared = MerchantAuthManager()
    
    // MARK: - Keychain Keys (using iOS Keychain Services directly)
    
    private let keychainTokenKey = "alphapos_staff_merchant_jwt"
    private let keychainExpiryKey = "alphapos_staff_merchant_jwt_expiry"
    private let keychainMerchantIdKey = "alphapos_staff_merchant_id"
    private let keychainDeviceIdKey = "alphapos_staff_device_id"
    private let keychainRefreshTokenKey = "alphapos_staff_refresh_token"
    
    private let refreshMarginSeconds: TimeInterval = 3600 // 1 hour
    private var refreshTimer: Timer?
    
    // MARK: - Public API
    
    var currentToken: String? {
        keychainRetrieve(forKey: keychainTokenKey)
    }
    
    var isAuthenticated: Bool {
        guard let _ = currentToken,
              let expiryStr = keychainRetrieve(forKey: keychainExpiryKey),
              let expiry = Double(expiryStr) else {
            return false
        }
        return Date().timeIntervalSince1970 < expiry
    }
    
    var merchantId: String? {
        keychainRetrieve(forKey: keychainMerchantIdKey)
    }
    
    private init() {
        if isAuthenticated {
            scheduleAutoRefresh()
        } else if currentToken != nil {
            Task { await refreshTokenIfNeeded() }
        }
    }
    
    func acceptPairedSession(
        accessToken: String,
        expiresIn: Int,
        merchantId: String,
        deviceId: String,
        refreshToken: String
    ) {
        let expiryTimestamp = Date().timeIntervalSince1970 + Double(expiresIn)
        keychainSave(accessToken, forKey: keychainTokenKey)
        keychainSave(String(expiryTimestamp), forKey: keychainExpiryKey)
        keychainSave(merchantId, forKey: keychainMerchantIdKey)
        keychainSave(deviceId, forKey: keychainDeviceIdKey)
        keychainSave(refreshToken, forKey: keychainRefreshTokenKey)
        UserDefaults.standard.set(merchantId, forKey: "active_merchant_id")
        scheduleAutoRefresh()
        NotificationCenter.default.post(name: .merchantTokenDidRefresh, object: nil)
    }
    
    // MARK: - Token Refresh
    
    func refreshTokenIfNeeded(force: Bool = false) async {
        guard let token = currentToken else { return }
        
        guard let expiryStr = keychainRetrieve(forKey: keychainExpiryKey),
              let expiry = Double(expiryStr) else { return }
        
        let timeUntilExpiry = expiry - Date().timeIntervalSince1970
        guard force || timeUntilExpiry < refreshMarginSeconds else { return }
        
        #if DEBUG
        print("MerchantAuthManager: Refreshing token (\(Int(timeUntilExpiry))s until expiry)")
        #endif
        
        do {
            let refreshURL = URL(string: AppConfig.supabaseURL.absoluteString + "/functions/v1/refresh-token")!
            
            var request = URLRequest(url: refreshURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
            // Use standard anon key for Authorization header to bypass Supabase Edge Gateway validation
            request.setValue("Bearer \(AppConfig.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
            // Pass the custom merchant token in X-Merchant-Token header
            request.setValue(token, forHTTPHeaderField: "X-Merchant-Token")
            // Authentication is on the critical interaction path. Fail fast so
            // the UI can offer a retry instead of appearing frozen.
            request.timeoutInterval = 5.0
            if let deviceId = keychainRetrieve(forKey: keychainDeviceIdKey),
               let refreshToken = keychainRetrieve(forKey: keychainRefreshTokenKey) {
                request.httpBody = try JSONSerialization.data(withJSONObject: [
                    "device_id": deviceId,
                    "refresh_token": refreshToken
                ])
            }
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let newToken = json["access_token"] as? String,
                  let expiresIn = json["expires_in"] as? Int else {
                throw AuthError.invalidResponse
            }
            
            let newExpiry = Date().timeIntervalSince1970 + Double(expiresIn)
            keychainSave(newToken, forKey: keychainTokenKey)
            keychainSave(String(newExpiry), forKey: keychainExpiryKey)
            
            #if DEBUG
            print("MerchantAuthManager: Token refreshed successfully")
            #endif
            
            NotificationCenter.default.post(name: .merchantTokenDidRefresh, object: nil)
            
        } catch {
            #if DEBUG
            print("MerchantAuthManager: Refresh failed, attempting re-authentication...")
            #endif
            
            // Pairing credentials are the only recovery path. Keep the expired
            // session so LoginView can explain that re-pairing is required.
        }
    }
    
    // MARK: - Logout
    
    func logout() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        keychainDelete(forKey: keychainTokenKey)
        keychainDelete(forKey: keychainExpiryKey)
        keychainDelete(forKey: keychainMerchantIdKey)
        keychainDelete(forKey: keychainDeviceIdKey)
        keychainDelete(forKey: keychainRefreshTokenKey)
    }
    
    // MARK: - Private Helpers
    
    private func scheduleAutoRefresh() {
        refreshTimer?.invalidate()
        
        guard let expiryStr = keychainRetrieve(forKey: keychainExpiryKey),
              let expiry = Double(expiryStr) else { return }
        
        let refreshAt = max(expiry - refreshMarginSeconds, Date().timeIntervalSince1970 + 60)
        let delay = refreshAt - Date().timeIntervalSince1970
        
        DispatchQueue.main.async { [weak self] in
            self?.refreshTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                Task { await self?.refreshTokenIfNeeded() }
            }
        }
    }
    
    // MARK: - Inline Keychain Helpers (no external dependency)
    
    @discardableResult
    private func keychainSave(_ value: String, forKey key: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        keychainDelete(forKey: key)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }
    
    private func keychainRetrieve(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        guard status == errSecSuccess, let data = dataTypeRef as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    @discardableResult
    private func keychainDelete(forKey key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }
}

// MARK: - Error Types

enum AuthError: Error, LocalizedError {
    case invalidCredentials(String)
    case invalidResponse
    case serverError(Int, String)
    case tokenExpired
    
    var errorDescription: String? {
        switch self {
        case .invalidCredentials(let msg): return "Invalid credentials: \(msg)"
        case .invalidResponse: return "Received invalid response from auth server."
        case .serverError(let code, let msg): return "Auth server error (\(code)): \(msg)"
        case .tokenExpired: return "Authentication token has expired."
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let merchantTokenDidRefresh = Notification.Name("merchantTokenDidRefresh")
}
