import Foundation

struct AuthSession {
    let accessToken: String
    let refreshToken: String
    let user: AuthUser

    var isAppReviewDemo: Bool {
        user.email.caseInsensitiveCompare("appreview@alphaposweb.com") == .orderedSame
    }
}

struct AuthUser {
    let id: String
    let email: String
    let appMetadata: [String: Any]
    let userMetadata: [String: Any]

    var merchantId: String? { appMetadata["merchant_id"] as? String }
    var fullName: String? { userMetadata["full_name"] as? String }
    var totpFactorId: String? { (userMetadata["totp_factor_id"] as? String) }
}

struct TOTPEnrollment {
    let factorId: String
    let secret: String
    let uri: String
}

enum TOTPLoginPreparation {
    /// Existing verified factor — ask for authenticator code only.
    case verifyExisting(factorId: String)
    /// Fresh enrollment — show QR / secret and allow skip.
    case enrollNew(TOTPEnrollment)
}

struct MerchantActivationResult {
    let merchantId: String
    let deviceId: String
    let deviceCredential: String
    let subscriptionTier: String
    let subscriptionStatus: String
    let subscriptionExpiresAt: Date?
}

/// Local + server draft for incomplete shop/plan onboarding (Phase 5).
struct OnboardingDraftPayload: Codable, Equatable {
    var shopName: String
    var shopPhone: String
    var currency: String
    var taxId: String
    var subscriptionTier: String?
    var billingCycle: String?
    var firstName: String?
    var lastName: String?
}

enum AuthServiceError: Error, LocalizedError {
    case invalidCredentials
    case emailConfirmationRequired
    case captchaRequired
    case serverError(String)
    case invalidResponse
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "อีเมลหรือรหัสผ่านไม่ถูกต้อง"
        case .emailConfirmationRequired:
            return "กรุณายืนยันอีเมลก่อนเข้าสู่ระบบ แล้วกลับมาล็อกอินอีกครั้ง"
        case .captchaRequired:
            return "กรุณายืนยัน Captcha แล้วลองอีกครั้ง"
        case .serverError(let m):
            return m
        case .invalidResponse:
            return "Invalid server response"
        case .networkError(let e):
            return "Network error: \(e.localizedDescription)"
        }
    }
}

final class AuthService {
    static let shared = AuthService()
    nonisolated static let authCallbackURL = "https://alphaposweb.com/auth/callback"
    nonisolated static let authAppDeepLinkURL = "alphapos://auth/callback"

    private let config = AppConfig.shared

    private init() {}

    func signIn(email: String, password: String, captchaToken: String? = nil) async throws -> AuthSession {
        if email.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare("appreview@alphaposweb.com") == .orderedSame {
            return try await signInAppReviewDemo(email: email, password: password)
        }
        let url = URL(string: config.supabaseURL.absoluteString + "/auth/v1/token?grant_type=password")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        var body: [String: Any] = [
            "email": email,
            "password": password
        ]
        if let captchaToken { body["gotrue_meta_security"] = ["captcha_token": captchaToken] }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 10

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await AppNetworkTransport.data(for: req, purpose: .interactiveAuthentication)
        } catch {
            throw AuthServiceError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AuthServiceError.invalidResponse
        }

        guard (200...299).contains(http.statusCode) else {
            throw Self.mapAuthFailure(statusCode: http.statusCode, data: data)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AuthServiceError.invalidResponse
        }

        return try parseSession(from: json)
    }

    /// Apple cannot complete interactive CAPTCHA or owner MFA during review.
    /// This is a separately rate-limited, short-lived session for the synthetic
    /// App Review account only; ordinary accounts still use GoTrue.
    private func signInAppReviewDemo(email: String, password: String) async throws -> AuthSession {
        // Attempt Edge Function demo session first
        do {
            let url = URL(string: config.supabaseURL.absoluteString + "/functions/v1/set-auth-locale")!
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue(config.supabaseAnonKey, forHTTPHeaderField: "apikey")
            req.setValue("Bearer \(config.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
            req.httpBody = try JSONSerialization.data(withJSONObject: [
                "app_review_session": true,
                "email": email,
                "password": password
            ])
            req.timeoutInterval = 10

            let (data, response) = try await AppNetworkTransport.data(for: req, purpose: .interactiveAuthentication)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let session = try parseSession(from: json)
                if !session.accessToken.isEmpty {
                    return session
                }
            }
        } catch {
            // Edge Function route failed; fallback to standard GoTrue password auth below
        }

        // Direct GoTrue auth fallback
        let url = URL(string: config.supabaseURL.absoluteString + "/auth/v1/token?grant_type=password")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        let body: [String: Any] = [
            "email": email,
            "password": password
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 10

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await AppNetworkTransport.data(for: req, purpose: .interactiveAuthentication)
        } catch {
            throw AuthServiceError.networkError(error)
        }
        guard let http = response as? HTTPURLResponse else { throw AuthServiceError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            throw Self.mapAuthFailure(statusCode: http.statusCode, data: data)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AuthServiceError.invalidResponse
        }
        return try parseSession(from: json)
    }

    func signUp(
        email: String,
        password: String,
        captchaToken: String,
        userData: [String: String] = [:],
        redirectTo: String = authCallbackURL
    ) async throws -> AuthSession {
        var components = URLComponents(string: config.supabaseURL.absoluteString + "/auth/v1/signup")!
        components.queryItems = [URLQueryItem(name: "redirect_to", value: redirectTo)]
        guard let url = components.url else { throw AuthServiceError.invalidResponse }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        var body: [String: Any] = ["email": email, "password": password, "gotrue_meta_security": ["captcha_token": captchaToken]]
        if !userData.isEmpty {
            body["data"] = userData
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 10

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await AppNetworkTransport.data(for: req, purpose: .interactiveAuthentication)
        } catch {
            throw AuthServiceError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw AuthServiceError.serverError(Self.serverMessage(from: data, fallback: "Sign up failed"))
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AuthServiceError.invalidResponse
        }

        let session = try parseSession(from: json)
        guard !session.accessToken.isEmpty else {
            throw AuthServiceError.emailConfirmationRequired
        }
        return session
    }

    /// Lists TOTP factors for the signed-in user (from /auth/v1/user — GET /factors is not supported).
    func listTOTPFactors(accessToken: String) async throws -> [(id: String, status: String, friendlyName: String)] {
        let user = try await authRequest(path: "/auth/v1/user", method: "GET", token: accessToken, body: [:])
        let factors = (user["factors"] as? [[String: Any]] ?? []).filter {
            ($0["factor_type"] as? String) == "totp"
        }

        return factors.compactMap { factor in
            guard let id = factor["id"] as? String else { return nil }
            let status = (factor["status"] as? String) ?? ""
            let name = (factor["friendly_name"] as? String) ?? ""
            return (id: id, status: status, friendlyName: name)
        }
    }

    /// Resolves MFA after password login / recovery without creating a duplicate "AlphaPos Owner" factor.
    func prepareOwnerTOTP(accessToken: String, preferredFactorId: String? = nil) async throws -> TOTPLoginPreparation {
        let factors = try await listTOTPFactors(accessToken: accessToken)

        if let preferredFactorId, !preferredFactorId.isEmpty,
           factors.contains(where: { $0.id == preferredFactorId && $0.status == "verified" }) {
            return .verifyExisting(factorId: preferredFactorId)
        }

        if let verified = factors.first(where: { $0.status == "verified" }) {
            return .verifyExisting(factorId: verified.id)
        }

        // Remove leftover unverified enrollments (common after skip / interrupted setup / password reset).
        for factor in factors where factor.status != "verified" {
            try? await unenrollFactor(accessToken: accessToken, factorId: factor.id)
        }

        do {
            return .enrollNew(try await enrollTOTP(accessToken: accessToken))
        } catch {
            let message = (error as? AuthServiceError)?.errorDescription?.lowercased()
                ?? error.localizedDescription.lowercased()
            if message.contains("already exists")
                || message.contains("friendly name")
                || message.contains("mfa_factor_name_conflict") {
                let leftover = try await listTOTPFactors(accessToken: accessToken)
                for factor in leftover {
                    try? await unenrollFactor(accessToken: accessToken, factorId: factor.id)
                }
                let remaining = try await listTOTPFactors(accessToken: accessToken)
                if let verified = remaining.first(where: { $0.status == "verified" }) {
                    return .verifyExisting(factorId: verified.id)
                }
                // Use a unique friendly name if a conflict somehow remains.
                return .enrollNew(try await enrollTOTP(
                    accessToken: accessToken,
                    friendlyName: "AlphaPos Owner \(UUID().uuidString.prefix(8))"
                ))
            }
            throw error
        }
    }

    func enrollTOTP(
        accessToken: String,
        friendlyName: String = "AlphaPos Owner"
    ) async throws -> TOTPEnrollment {
        let json = try await authRequest(path: "/auth/v1/factors", method: "POST", token: accessToken, body: [
            "factor_type": "totp", "friendly_name": friendlyName
        ])
        guard let id = json["id"] as? String, let totp = json["totp"] as? [String: Any],
              let secret = totp["secret"] as? String, let uri = totp["uri"] as? String else {
            throw AuthServiceError.invalidResponse
        }
        return TOTPEnrollment(factorId: id, secret: secret, uri: uri)
    }

    func verifyTOTP(accessToken: String, factorId: String, code: String) async throws -> AuthSession {
        let challenge = try await authRequest(path: "/auth/v1/factors/\(factorId)/challenge", method: "POST", token: accessToken, body: [:])
        guard let challengeId = challenge["id"] as? String else { throw AuthServiceError.invalidResponse }
        let verified = try await authRequest(path: "/auth/v1/factors/\(factorId)/verify", method: "POST", token: accessToken, body: [
            "challenge_id": challengeId, "code": code
        ])
        let upgradedSession = try parseSession(from: verified)
        guard !upgradedSession.accessToken.isEmpty else {
            throw AuthServiceError.invalidResponse
        }

        // GoTrue's factor verification response is not guaranteed to carry the
        // complete user/app_metadata object. Re-read the user with the AAL2 token
        // so merchant_id cannot disappear between password login and MFA.
        let verifiedUser = try await fetchCurrentUser(accessToken: upgradedSession.accessToken)
        return AuthSession(
            accessToken: upgradedSession.accessToken,
            refreshToken: upgradedSession.refreshToken,
            user: verifiedUser
        )
    }

    func saveTOTPFactorId(accessToken: String, factorId: String) async throws {
        _ = try await authRequest(path: "/auth/v1/user", method: "PUT", token: accessToken, body: [
            "data": ["totp_factor_id": factorId]
        ])
    }

    /// Removes an unverified/verified MFA factor (used when the user skips first-time TOTP setup).
    func unenrollFactor(accessToken: String, factorId: String) async throws {
        _ = try await authRequest(path: "/auth/v1/factors/\(factorId)", method: "DELETE", token: accessToken, body: [:])
    }

    private func authRequest(path: String, method: String, token: String, body: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: config.supabaseURL.absoluteString + path)!)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if method != "GET" {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await AppNetworkTransport.data(for: request, purpose: .interactiveAuthentication)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw AuthServiceError.serverError(
                Self.serverMessage(from: data, fallback: "MFA request failed")
            )
        }
        // DELETE may return empty body.
        if data.isEmpty { return [:] }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            if method == "DELETE" { return [:] }
            throw AuthServiceError.invalidResponse
        }
        return json
    }

    func activateMerchant(
        accessToken: String,
        shopName: String,
        firstName: String,
        lastName: String,
        shopPhone: String,
        currency: String,
        taxId: String,
        subscriptionTier: String,
        billingCycle: String,
        termsVersion: String,
        privacyVersion: String,
        consentedAt: Date,
        idempotencyKey: UUID,
        deviceId: UUID,
        deviceName: String,
        deviceFingerprintHash: String
    ) async throws -> MerchantActivationResult {
        let url = URL(string: config.supabaseURL.absoluteString + "/functions/v1/activate-merchant")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15

        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "shop_name": shopName,
            "first_name": firstName,
            "last_name": lastName,
            "shop_phone": shopPhone,
            "currency": currency,
            "tax_id": taxId,
            "subscription_tier": subscriptionTier,
            "billing_cycle": billingCycle,
            "terms_version": termsVersion,
            "privacy_version": privacyVersion,
            "consented_at": ISO8601DateFormatter().string(from: consentedAt),
            "idempotency_key": idempotencyKey.uuidString.lowercased(),
            "device_id": deviceId.uuidString.lowercased(),
            "device_name": deviceName,
            "device_fingerprint_hash": deviceFingerprintHash
        ])

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await AppNetworkTransport.data(for: req, purpose: .licensingActivation)
        } catch {
            throw AuthServiceError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AuthServiceError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let raw = Self.serverMessage(from: data, fallback: "Merchant activation failed")
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let code = json["error"] as? String, code == "ONBOARDING_REQUIRED" {
                let detail = (json["message"] as? String) ?? raw
                throw AuthServiceError.serverError("ONBOARDING_REQUIRED: \(detail)")
            }
            throw AuthServiceError.serverError(raw)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let merchantId = json["merchant_id"] as? String,
              let deviceId = json["device_id"] as? String,
              let deviceCredential = json["device_credential"] as? String else {
            throw AuthServiceError.invalidResponse
        }

        let tier = json["subscription_tier"] as? String ?? subscriptionTier
        let status = json["subscription_status"] as? String ?? "active"
        let expiryString = json["subscription_expires_at"] as? String
        let expiry = expiryString.flatMap { ISO8601DateFormatter().date(from: $0) }

        return MerchantActivationResult(
            merchantId: merchantId,
            deviceId: deviceId,
            deviceCredential: deviceCredential,
            subscriptionTier: tier,
            subscriptionStatus: status,
            subscriptionExpiresAt: expiry
        )
    }

    func resetPassword(
        email: String,
        captchaToken: String? = nil,
        preferredLanguage: String? = nil,
        redirectTo: String = authCallbackURL
    ) async throws {
        // Align recovery email locale with the language selected on the auth screen.
        let lang = preferredLanguage
            ?? LocalizationManager.shared.currentLanguage.rawValue
        await prepareAuthEmailLocale(email: email, preferredLanguage: lang)

        let url = URL(string: config.supabaseURL.absoluteString + "/auth/v1/recover")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        var body: [String: Any] = [
            "email": email,
            "redirect_to": redirectTo
        ]
        if let captchaToken, !captchaToken.isEmpty {
            body["gotrue_meta_security"] = ["captcha_token": captchaToken]
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 10

        let (data, response) = try await AppNetworkTransport.data(for: req, purpose: .interactiveAuthentication)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw AuthServiceError.serverError(
                Self.serverMessage(from: data, fallback: "Password reset failed")
            )
        }

        // GoTrue deliberately returns success for unknown addresses to prevent
        // account enumeration. Callers must describe this as an accepted request,
        // not as proof that an email was delivered.
    }

    /// Best-effort stamp of preferred_language before GoTrue sends recovery/confirm mail.
    func prepareAuthEmailLocale(email: String, preferredLanguage: String) async {
        let url = URL(string: config.supabaseURL.absoluteString + "/functions/v1/set-auth-locale")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(config.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "email": email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            "preferred_language": preferredLanguage,
        ])
        req.timeoutInterval = 8
        _ = try? await AppNetworkTransport.data(for: req, purpose: .interactiveAuthentication)
    }

    func fetchCurrentUser(accessToken: String) async throws -> AuthUser {
        let json = try await authRequest(path: "/auth/v1/user", method: "GET", token: accessToken, body: [:])
        let userId = json["id"] as? String ?? ""
        let userEmail = json["email"] as? String ?? ""
        let appMetadata = json["app_metadata"] as? [String: Any] ?? [:]
        var userMetadata = json["user_metadata"] as? [String: Any] ?? [:]
        if let factors = json["factors"] as? [[String: Any]],
           let totp = factors.first(where: { ($0["factor_type"] as? String) == "totp" && ($0["status"] as? String) == "verified" }),
           let factorId = totp["id"] as? String {
            userMetadata["totp_factor_id"] = factorId
        }
        return AuthUser(id: userId, email: userEmail, appMetadata: appMetadata, userMetadata: userMetadata)
    }

    func updatePassword(accessToken: String, newPassword: String) async throws {
        let url = URL(string: config.supabaseURL.absoluteString + "/auth/v1/user")!
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["password": newPassword])
        req.timeoutInterval = 10

        let (data, response) = try await AppNetworkTransport.data(for: req, purpose: .cloudData)
        guard let http = response as? HTTPURLResponse else {
            throw AuthServiceError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw AuthServiceError.serverError(Self.serverMessage(from: data, fallback: "Password update failed"))
        }
    }

    /// Persist UI locale for localized transactional emails (confirmation / recovery).
    func updatePreferredLanguage(accessToken: String, languageCode: String) async {
        let url = URL(string: config.supabaseURL.absoluteString + "/auth/v1/user")!
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "data": ["preferred_language": languageCode]
        ])
        req.timeoutInterval = 8
        _ = try? await AppNetworkTransport.data(for: req, purpose: .cloudData)
    }

    func changePassword(email: String, currentPassword: String, newPassword: String) async throws {
        let session = try await signIn(email: email, password: currentPassword)
        guard !session.accessToken.isEmpty else { throw AuthServiceError.invalidResponse }

        let url = URL(string: config.supabaseURL.absoluteString + "/auth/v1/user")!
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["password": newPassword])
        req.timeoutInterval = 10

        let (data, response) = try await AppNetworkTransport.data(for: req, purpose: .cloudData)
        guard let http = response as? HTTPURLResponse else {
            throw AuthServiceError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw AuthServiceError.serverError(Self.serverMessage(from: data, fallback: "Password update failed"))
        }
    }

    // MARK: - Private Helpers

    static func mapAuthFailure(statusCode: Int, data: Data) -> AuthServiceError {
        let message = serverMessage(from: data, fallback: "")
        let lowered = message.lowercased()
        let code = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error_code"] as? String

        if code == "email_not_confirmed"
            || lowered.contains("email not confirmed")
            || lowered.contains("email_not_confirmed") {
            return .emailConfirmationRequired
        }
        if code == "captcha_failed"
            || lowered.contains("captcha") {
            return .captchaRequired
        }
        if statusCode == 400 || statusCode == 401 {
            return .invalidCredentials
        }
        return .serverError(message.isEmpty ? "Server error (\(statusCode))" : message)
    }

    static func serverMessage(from data: Data, fallback: String) -> String {
        SecurityHelper.serverMessage(from: data, fallback: fallback)
    }

    private func parseSession(from json: [String: Any]) throws -> AuthSession {
        let accessToken = json["access_token"] as? String ?? ""
        let refreshToken = json["refresh_token"] as? String ?? ""
        let userJson = json["user"] as? [String: Any] ?? json

        let userId = userJson["id"] as? String ?? ""
        let userEmail = userJson["email"] as? String ?? ""
        let appMetadata = userJson["app_metadata"] as? [String: Any] ?? [:]
        var userMetadata = userJson["user_metadata"] as? [String: Any] ?? [:]
        if let factors = userJson["factors"] as? [[String: Any]],
           let totp = factors.first(where: { ($0["factor_type"] as? String) == "totp" && ($0["status"] as? String) == "verified" }),
           let factorId = totp["id"] as? String {
            userMetadata["totp_factor_id"] = factorId
        }

        let user = AuthUser(id: userId, email: userEmail, appMetadata: appMetadata, userMetadata: userMetadata)
        return AuthSession(accessToken: accessToken, refreshToken: refreshToken, user: user)
    }

    // MARK: - Onboarding drafts (Phase 5)

    func fetchOnboardingDraft(accessToken: String) async throws -> OnboardingDraftPayload? {
        let url = URL(string: config.supabaseURL.absoluteString + "/rest/v1/merchant_onboarding_drafts?select=*")!
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await AppNetworkTransport.data(for: req, purpose: .cloudData)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return nil
        }
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let row = rows.first else { return nil }
        return OnboardingDraftPayload(
            shopName: row["shop_name"] as? String ?? "",
            shopPhone: row["shop_phone"] as? String ?? "",
            currency: row["currency"] as? String ?? "THB",
            taxId: row["tax_id"] as? String ?? "",
            subscriptionTier: row["subscription_tier"] as? String,
            billingCycle: row["billing_cycle"] as? String,
            firstName: row["first_name"] as? String,
            lastName: row["last_name"] as? String
        )
    }

    func upsertOnboardingDraft(accessToken: String, draft: OnboardingDraftPayload) async throws {
        guard let userId = jwtSubject(accessToken) else { return }
        let url = URL(string: config.supabaseURL.absoluteString + "/rest/v1/merchant_onboarding_drafts?on_conflict=user_id")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        var body: [String: Any] = [
            "user_id": userId,
            "shop_name": draft.shopName,
            "shop_phone": draft.shopPhone,
            "currency": draft.currency,
            "tax_id": draft.taxId,
            "updated_at": ISO8601DateFormatter().string(from: Date()),
        ]
        if let tier = draft.subscriptionTier { body["subscription_tier"] = tier }
        if let cycle = draft.billingCycle { body["billing_cycle"] = cycle }
        if let firstName = draft.firstName { body["first_name"] = firstName }
        if let lastName = draft.lastName { body["last_name"] = lastName }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        // Best-effort: local autosave remains source of truth when offline.
        _ = try? await AppNetworkTransport.data(for: req, purpose: .cloudData)
    }

    func clearOnboardingDraft(accessToken: String) async {
        guard let userId = jwtSubject(accessToken) else { return }
        let url = URL(string: config.supabaseURL.absoluteString + "/rest/v1/merchant_onboarding_drafts?user_id=eq.\(userId)")!
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue(config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        _ = try? await AppNetworkTransport.data(for: req, purpose: .cloudData)
    }

    private func jwtSubject(_ token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload.append("=") }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sub = json["sub"] as? String else { return nil }
        return sub
    }
}
