import Foundation
import CryptoKit

/// Manages merchant-specific JWT authentication for Supabase.
///
/// Instead of using the Supabase Anonymous Key (which is shared across all merchants),
/// this manager obtains a per-merchant JWT token from the Edge Function
/// `issue-merchant-token`. The JWT contains a `merchant_id` claim that Supabase
/// PostgREST and Realtime extract via `current_setting('request.jwt.claims')`,
/// enabling RLS policies to isolate data per merchant without relying on
/// custom HTTP headers.
///
/// **Token lifecycle:**
/// 1. On first launch or after logout: `authenticate(merchantId:deviceSecret:)` is called.
/// 2. The JWT (24h TTL) is stored in Keychain.
/// 3. A background timer auto-refreshes the token 1 hour before expiry.
/// 4. `currentToken` is always available for NetworkManager/SyncEngine.
///
/// **Fallback:** If no JWT is stored, callers should fall back to the anon key
/// to allow a graceful transition period.
final class MerchantAuthManager {
    static let shared = MerchantAuthManager()
    
    // MARK: - Keychain Keys
    
    private let keychainTokenKey = "alphapos_merchant_jwt"
    private let keychainExpiryKey = "alphapos_merchant_jwt_expiry"
    private let keychainMerchantIdKey = "alphapos_merchant_id"
    private let keychainDeviceSecretKey = "alphapos_device_secret"
    
    // MARK: - Configuration
    
    /// How many seconds before token expiry to trigger a refresh.
    private let refreshMarginSeconds: TimeInterval = 3600 // 1 hour
    
    /// Timer for background auto-refresh.
    private var refreshTimer: Timer?
    
    // MARK: - Public API
    
    /// The current JWT token, or `nil` if not authenticated.
    var currentToken: String? {
        KeychainManager.shared.retrieve(forKey: keychainTokenKey)
    }
    
    /// Whether a valid (non-expired) JWT is available.
    var isAuthenticated: Bool {
        guard let _ = currentToken, let expiryStr = KeychainManager.shared.retrieve(forKey: keychainExpiryKey),
              let expiry = Double(expiryStr) else {
            return false
        }
        return Date().timeIntervalSince1970 < expiry
    }
    
    /// The authenticated merchant ID, if available.
    var merchantId: String? {
        KeychainManager.shared.retrieve(forKey: keychainMerchantIdKey)
    }
    
    private init() {
        // Schedule auto-refresh if we already have a token at launch
        if isAuthenticated {
            scheduleAutoRefresh()
        }
    }
    
    // MARK: - Authentication
    
    /// Authenticate with the Edge Function to obtain a merchant-specific JWT.
    ///
    /// - Parameters:
    ///   - merchantId: The UUID of the merchant (from `merchants.id`).
    ///   - deviceSecret: A shared secret provisioned for this merchant's devices.
    /// - Returns: The JWT access token string.
    /// - Throws: `AuthError` if authentication fails.
    @discardableResult
    func authenticate(merchantId: String, deviceSecret: String) async throws -> String {
        let config = AppConfig.shared
        let edgeFunctionURL = URL(string: config.supabaseURL.absoluteString + "/functions/v1/issue-merchant-token")!
        
        var request = URLRequest(url: edgeFunctionURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Edge Functions require the anon key in the apikey header for access control
        request.setValue(config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(config.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10.0
        
        let payload: [String: String] = [
            "merchant_id": merchantId,
            "device_secret": deviceSecret
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            if httpResponse.statusCode == 401 {
                throw AuthError.invalidCredentials(errorMsg)
            }
            throw AuthError.serverError(httpResponse.statusCode, errorMsg)
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String,
              let expiresIn = json["expires_in"] as? Int else {
            throw AuthError.invalidResponse
        }
        
        // Store token and metadata in Keychain
        let expiryTimestamp = Date().timeIntervalSince1970 + Double(expiresIn)
        KeychainManager.shared.save(accessToken, forKey: keychainTokenKey)
        KeychainManager.shared.save(String(expiryTimestamp), forKey: keychainExpiryKey)
        KeychainManager.shared.save(merchantId, forKey: keychainMerchantIdKey)
        KeychainManager.shared.save(deviceSecret, forKey: keychainDeviceSecretKey)

        // Cache merchant_id in UserDefaults so NetworkManager can read it without Keychain lookup on every call.
        // NOTE: This is a NON-SENSITIVE cache. The authoritative auth state is the Keychain JWT above.
        //       Do NOT use UserDefaults "active_merchant_id" as an auth gate — it can be tampered.
        //       Auth gate must always use MerchantAuthManager.shared.isAuthenticated (Keychain-backed).
        UserDefaults.standard.set(merchantId, forKey: "active_merchant_id")
        
        #if DEBUG
        print("MerchantAuthManager: Successfully authenticated merchant \(merchantId)")
        print("MerchantAuthManager: Token expires at \(Date(timeIntervalSince1970: expiryTimestamp))")
        #endif
        
        // Schedule auto-refresh
        scheduleAutoRefresh()
        
        return accessToken
    }
    
    // MARK: - Token Refresh
    
    /// Refresh the current token using the refresh-token Edge Function.
    /// Falls back to full re-authentication if refresh fails.
    func refreshTokenIfNeeded() async {
        guard let token = currentToken else { return }
        
        // Check if refresh is needed (within margin of expiry)
        guard let expiryStr = KeychainManager.shared.retrieve(forKey: keychainExpiryKey),
              let expiry = Double(expiryStr) else {
            return
        }
        
        let timeUntilExpiry = expiry - Date().timeIntervalSince1970
        guard timeUntilExpiry < refreshMarginSeconds else {
            #if DEBUG
            print("MerchantAuthManager: Token still fresh (\(Int(timeUntilExpiry))s remaining)")
            #endif
            return
        }
        
        #if DEBUG
        print("MerchantAuthManager: Refreshing token (\(Int(timeUntilExpiry))s until expiry)")
        #endif
        
        // Try refresh endpoint first
        do {
            let config = AppConfig.shared
            let refreshURL = URL(string: config.supabaseURL.absoluteString + "/functions/v1/refresh-token")!
            
            var request = URLRequest(url: refreshURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(config.supabaseAnonKey, forHTTPHeaderField: "apikey")
            // Use standard anon key for Authorization header to bypass Supabase Edge Gateway validation
            request.setValue("Bearer \(config.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
            // Pass the custom merchant token in X-Merchant-Token header
            request.setValue(token, forHTTPHeaderField: "X-Merchant-Token")
            request.timeoutInterval = 10.0
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let newToken = json["access_token"] as? String,
                  let expiresIn = json["expires_in"] as? Int else {
                throw AuthError.invalidResponse
            }
            
            let newExpiry = Date().timeIntervalSince1970 + Double(expiresIn)
            KeychainManager.shared.save(newToken, forKey: keychainTokenKey)
            KeychainManager.shared.save(String(newExpiry), forKey: keychainExpiryKey)
            
            #if DEBUG
            print("MerchantAuthManager: Token refreshed successfully. New expiry: \(Date(timeIntervalSince1970: newExpiry))")
            #endif
            
            // Notify SyncEngine to reconnect WebSocket with new token
            NotificationCenter.default.post(name: .merchantTokenDidRefresh, object: nil)
            
        } catch {
            #if DEBUG
            print("MerchantAuthManager: Refresh failed (\(error)), attempting re-authentication...")
            #endif
            
            // Fallback: re-authenticate with stored credentials
            guard let storedMerchantId = KeychainManager.shared.retrieve(forKey: keychainMerchantIdKey),
                  let storedDeviceSecret = KeychainManager.shared.retrieve(forKey: keychainDeviceSecretKey) else {
                #if DEBUG
                print("MerchantAuthManager: No stored credentials for re-authentication")
                #endif
                return
            }
            
            do {
                try await authenticate(merchantId: storedMerchantId, deviceSecret: storedDeviceSecret)
                NotificationCenter.default.post(name: .merchantTokenDidRefresh, object: nil)
            } catch {
                #if DEBUG
                print("MerchantAuthManager: Re-authentication also failed: \(error)")
                #endif
            }
        }
    }
    
    // MARK: - Logout
    
    /// Clear all stored credentials and cancel refresh timer.
    func logout() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        
        KeychainManager.shared.delete(forKey: keychainTokenKey)
        KeychainManager.shared.delete(forKey: keychainExpiryKey)
        KeychainManager.shared.delete(forKey: keychainMerchantIdKey)
        KeychainManager.shared.delete(forKey: keychainDeviceSecretKey)
        
        #if DEBUG
        print("MerchantAuthManager: Logged out and cleared credentials")
        #endif
    }
    
    // MARK: - Private
    
    /// Schedule a timer to auto-refresh the token before it expires.
    private func scheduleAutoRefresh() {
        refreshTimer?.invalidate()
        
        guard let expiryStr = KeychainManager.shared.retrieve(forKey: keychainExpiryKey),
              let expiry = Double(expiryStr) else {
            return
        }
        
        // Fire 1 hour before expiry (or immediately if within margin)
        let refreshAt = max(expiry - refreshMarginSeconds, Date().timeIntervalSince1970 + 60)
        let delay = refreshAt - Date().timeIntervalSince1970
        
        #if DEBUG
        print("MerchantAuthManager: Scheduling auto-refresh in \(Int(delay))s")
        #endif
        
        DispatchQueue.main.async { [weak self] in
            self?.refreshTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                Task {
                    await self?.refreshTokenIfNeeded()
                }
            }
        }
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
    /// Posted when the merchant JWT token has been refreshed.
    /// Observers (e.g. SyncEngine) should reconnect their WebSocket with the new token.
    static let merchantTokenDidRefresh = Notification.Name("merchantTokenDidRefresh")
}
