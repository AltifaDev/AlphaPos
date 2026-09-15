import Foundation

/// Runtime network modes. Local persistence remains available in every mode;
/// this policy only controls whether a network task may be created.
enum AppNetworkMode: String, Sendable {
    case authenticationRequired
    case online
    case offlineOnly
}

/// A deliberately small allow-list of reasons for creating network traffic.
/// New network features must choose a purpose, which makes accidental cloud
/// access in offline-only mode visible during review and testing.
enum NetworkPurpose: String, Sendable {
    case interactiveAuthentication
    case licensingActivation
    case cloudData
    case authRefresh
    case pushRegistration
    case remoteMedia
    case networkTime
    case connectivityProbe
    case realtime
    case backupTransfer
}

/// A short-lived, user-initiated exception for manual Backup/Restore. It does
/// not change `offline_sync_mode`, so SyncEngine, Realtime and normal REST stay
/// disabled throughout the operation.
final class BackupNetworkAuthorization: @unchecked Sendable {
    static let shared = BackupNetworkAuthorization()
    private let lock = NSLock()
    private var validUntil: Date?
    private init() {}

    var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return validUntil.map { Date() < $0 } ?? false
    }

    func begin(duration: TimeInterval = 300) {
        lock.lock()
        validUntil = Date().addingTimeInterval(duration)
        lock.unlock()
    }

    func end() {
        lock.lock()
        validUntil = nil
        lock.unlock()
    }
}

enum NetworkPolicyError: Error, LocalizedError, Equatable {
    case offlineModeProhibited(NetworkPurpose)

    var errorDescription: String? {
        switch self {
        case .offlineModeProhibited(let purpose):
            return "Network access for \(purpose.rawValue) is disabled in offline-only mode."
        }
    }
}

/// Single source of truth for all outbound traffic.
///
/// Interactive login and first activation are allowed before a trusted local
/// workspace exists. Once an authenticated workspace selects offline-only,
/// no purpose is allowed; signing out returns the app to
/// `authenticationRequired`, where interactive login is available again.
final class NetworkPolicy: @unchecked Sendable {
    static let shared = NetworkPolicy()

    private let lock = NSLock()
    private var overrideMode: AppNetworkMode?

    private init() {}

    var mode: AppNetworkMode {
        lock.lock()
        let override = overrideMode
        lock.unlock()
        if let override { return override }

        let defaults = UserDefaults.standard
        let hasWorkspace = !(defaults.string(forKey: "active_merchant_id") ?? "").isEmpty
        if !hasWorkspace { return .authenticationRequired }
        return defaults.bool(forKey: "offline_sync_mode") ? .offlineOnly : .online
    }

    func allows(_ purpose: NetworkPurpose) -> Bool {
        switch mode {
        case .online:
            return true
        case .authenticationRequired:
            return purpose == .interactiveAuthentication || purpose == .licensingActivation
        case .offlineOnly:
            guard BackupNetworkAuthorization.shared.isActive else { return false }
            return purpose == .backupTransfer
                || purpose == .authRefresh
                || purpose == .interactiveAuthentication
        }
    }

    func require(_ purpose: NetworkPurpose) throws {
        guard allows(purpose) else {
            throw NetworkPolicyError.offlineModeProhibited(purpose)
        }
    }

    /// Test-only override. Passing nil restores the persisted runtime policy.
    func setModeOverrideForTesting(_ mode: AppNetworkMode?) {
        lock.lock()
        overrideMode = mode
        lock.unlock()
    }
}

protocol NetworkTransport: Sendable {
    func data(for request: URLRequest, purpose: NetworkPurpose) async throws -> (Data, URLResponse)
    func data(from url: URL, purpose: NetworkPurpose) async throws -> (Data, URLResponse)
}

struct LiveNetworkTransport: NetworkTransport {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest, purpose: NetworkPurpose) async throws -> (Data, URLResponse) {
        try NetworkPolicy.shared.require(purpose)
        return try await session.data(for: request)
    }

    func data(from url: URL, purpose: NetworkPurpose) async throws -> (Data, URLResponse) {
        try NetworkPolicy.shared.require(purpose)
        return try await session.data(from: url)
    }
}

struct DisabledNetworkTransport: NetworkTransport {
    func data(for request: URLRequest, purpose: NetworkPurpose) async throws -> (Data, URLResponse) {
        throw NetworkPolicyError.offlineModeProhibited(purpose)
    }

    func data(from url: URL, purpose: NetworkPurpose) async throws -> (Data, URLResponse) {
        throw NetworkPolicyError.offlineModeProhibited(purpose)
    }
}

/// Facade used by production code. The policy is checked before URLSession
/// creates a task, preventing DNS, TCP, TLS, and HTTP activity in offline-only.
enum AppNetworkTransport {
    private static let live = LiveNetworkTransport()
    private static let disabled = DisabledNetworkTransport()

    static func data(for request: URLRequest, purpose: NetworkPurpose = .cloudData) async throws -> (Data, URLResponse) {
        let transport: any NetworkTransport = NetworkPolicy.shared.allows(purpose) ? live : disabled
        return try await transport.data(for: request, purpose: purpose)
    }

    static func data(from url: URL, purpose: NetworkPurpose = .remoteMedia) async throws -> (Data, URLResponse) {
        let transport: any NetworkTransport = NetworkPolicy.shared.allows(purpose) ? live : disabled
        return try await transport.data(from: url, purpose: purpose)
    }

    /// Creates a WebSocket task only after the same central policy check used
    /// by HTTP. Callers receive no task at all while networking is disabled.
    static func webSocketTask(
        with url: URL,
        configuration: URLSessionConfiguration = .default,
        purpose: NetworkPurpose = .realtime
    ) throws -> URLSessionWebSocketTask {
        try NetworkPolicy.shared.require(purpose)
        return URLSession(configuration: configuration).webSocketTask(with: url)
    }
}

enum LocalCommitState: String, Codable, Sendable {
    case committed
}

enum CloudSyncState: String, Codable, Sendable {
    case disabled
    case pending
    case syncing
    case synced
    case failed
}

/// Migration-free compatibility layer for the existing `isSynced` fields.
/// New UI and diagnostics should use this resolver instead of displaying an
/// offline-only record as perpetually pending.
enum PersistenceStateResolver {
    static func cloudState(isSynced: Bool, isSyncing: Bool = false, failed: Bool = false) -> CloudSyncState {
        if NetworkPolicy.shared.mode == .offlineOnly { return .disabled }
        if failed { return .failed }
        if isSyncing { return .syncing }
        return isSynced ? .synced : .pending
    }

    static var localState: LocalCommitState { .committed }
}
