import Combine
import Foundation

enum AuthDeepLinkAction {
    case emailConfirmed(AuthSession)
    case passwordRecovery(accessToken: String)
    case failed(message: String)
}

@MainActor
final class AuthDeepLinkCoordinator: ObservableObject {
    static let shared = AuthDeepLinkCoordinator()

    @Published private(set) var pendingAction: AuthDeepLinkAction?
    @Published private(set) var pendingActionToken: UUID?

    private init() {}

    private func publish(_ action: AuthDeepLinkAction) {
        pendingAction = action
        pendingActionToken = UUID()
    }

    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "alphapos" else { return false }

        if url.host?.lowercased() == "pair" {
            return false
        }

        guard url.host?.lowercased() == "auth",
              url.path.lowercased().hasPrefix("/callback") else {
            return false
        }

        let params = Self.parseParams(from: url)
        if let error = params["error"] ?? params["error_code"], !error.isEmpty {
            let description = params["error_description"]?.replacingOccurrences(of: "+", with: " ")
                ?? "Email link could not be completed."
            publish(.failed(message: description))
            return true
        }

        guard let accessToken = params["access_token"], !accessToken.isEmpty else {
            return false
        }

        let type = params["type"] ?? "signup"
        if type == "recovery" {
            publish(.passwordRecovery(accessToken: accessToken))
            return true
        }

        let refreshToken = params["refresh_token"] ?? ""
        publish(.emailConfirmed(
            AuthSession(
                accessToken: accessToken,
                refreshToken: refreshToken,
                user: AuthUser(id: "", email: "", appMetadata: [:], userMetadata: [:])
            )
        ))
        return true
    }

    func consumePendingAction() -> AuthDeepLinkAction? {
        defer { clearPendingAction() }
        return pendingAction
    }

    func clearPendingAction() {
        pendingAction = nil
        pendingActionToken = nil
    }

    private static func parseParams(from url: URL) -> [String: String] {
        var params: [String: String] = [:]

        if let fragment = url.fragment, !fragment.isEmpty {
            params.merge(parseQueryString(fragment)) { _, new in new }
        }

        if let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
            for item in items {
                if let value = item.value {
                    params[item.name] = value
                }
            }
        }

        return params
    }

    private static func parseQueryString(_ value: String) -> [String: String] {
        var params: [String: String] = [:]
        for pair in value.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard let key = parts.first else { continue }
            let rawValue = parts.count > 1 ? parts[1] : ""
            let decoded = rawValue.removingPercentEncoding ?? rawValue
            params[key] = decoded
        }
        return params
    }
}
