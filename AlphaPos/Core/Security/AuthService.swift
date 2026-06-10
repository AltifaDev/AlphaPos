import Foundation

struct AuthSession {
    let accessToken: String
    let refreshToken: String
    let user: AuthUser
}

struct AuthUser {
    let id: String
    let email: String
    let appMetadata: [String: Any]
    let userMetadata: [String: Any]

    var merchantId: String? { appMetadata["merchant_id"] as? String }
    var fullName: String? { userMetadata["full_name"] as? String }
}

enum AuthServiceError: Error, LocalizedError {
    case invalidCredentials
    case serverError(String)
    case invalidResponse
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials: return "Invalid email or password"
        case .serverError(let m): return "Server error: \(m)"
        case .invalidResponse: return "Invalid server response"
        case .networkError(let e): return "Network error: \(e.localizedDescription)"
        }
    }
}

final class AuthService {
    static let shared = AuthService()
    private let config = AppConfig.shared

    private init() {}

    func signIn(email: String, password: String) async throws -> AuthSession {
        let url = URL(string: config.supabaseURL.absoluteString + "/auth/v1/token?grant_type=password")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "email": email,
            "password": password
        ])
        req.timeoutInterval = 10

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw AuthServiceError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AuthServiceError.invalidResponse
        }

        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 400 {
                throw AuthServiceError.invalidCredentials
            }
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AuthServiceError.serverError(body)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AuthServiceError.invalidResponse
        }

        return try parseSession(from: json)
    }

    func signUp(email: String, password: String, userData: [String: String] = [:]) async throws -> AuthSession {
        let url = URL(string: config.supabaseURL.absoluteString + "/auth/v1/signup")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        var body: [String: Any] = ["email": email, "password": password]
        if !userData.isEmpty {
            body["data"] = userData
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: req)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw AuthServiceError.serverError("Sign up failed")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AuthServiceError.invalidResponse
        }

        return try parseSession(from: json)
    }

    func resetPassword(email: String) async throws {
        let url = URL(string: config.supabaseURL.absoluteString + "/auth/v1/recover")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["email": email])
        req.timeoutInterval = 10

        let (_, response) = try await URLSession.shared.data(for: req)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw AuthServiceError.serverError("Password reset failed")
        }
    }

    // MARK: - Private Helpers

    private func parseSession(from json: [String: Any]) throws -> AuthSession {
        let accessToken = json["access_token"] as? String ?? ""
        let refreshToken = json["refresh_token"] as? String ?? ""
        let userJson = json["user"] as? [String: Any] ?? json

        let userId = userJson["id"] as? String ?? ""
        let userEmail = userJson["email"] as? String ?? ""
        let appMetadata = userJson["app_metadata"] as? [String: Any] ?? [:]
        let userMetadata = userJson["user_metadata"] as? [String: Any] ?? [:]

        let user = AuthUser(id: userId, email: userEmail, appMetadata: appMetadata, userMetadata: userMetadata)
        return AuthSession(accessToken: accessToken, refreshToken: refreshToken, user: user)
    }
}
