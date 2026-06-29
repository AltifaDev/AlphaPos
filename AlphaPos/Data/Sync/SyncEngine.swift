import Foundation
import SwiftData
import Combine
import UIKit
import os

struct ServiceRequest: Identifiable, Codable, Hashable {
    var id: String
    var tableNumber: String
    var requestType: String
    var status: String
    var createdAt: String
}

@MainActor
final class SyncEngine: NSObject, ObservableObject {
    static let shared = SyncEngine()

    enum SyncStatus {
        case idle
        case syncing
        case error
        case offline

        var localizedDescription: String {
            switch self {
            case .idle: return "Synced"
            case .syncing: return "Syncing..."
            case .error: return "Sync Error"
            case .offline: return "Offline"
            }
        }
    }

    // MARK: - Published State
    @Published var syncStatus: SyncStatus = .idle
    @Published var lastSyncedAt: Date? = nil
    @Published var activeRequests: [ServiceRequest] = []

    // MARK: - Internal Properties (accessible by all extension files in the module)
    // Note: `internal` (no modifier) is required because Swift `private` is
    // file-scoped for classes — extensions in separate files cannot access it.

    var cachedModelContext: ModelContext?
    var activeSyncTask: Task<Void, Never>?

    // Thread-safe sync error flag
    let syncErrorLock = OSAllocatedUnfairLock()
    var _encounteredSyncError: Bool = false
    var encounteredSyncError: Bool {
        get { syncErrorLock.lock(); defer { syncErrorLock.unlock() }; return _encounteredSyncError }
        set { syncErrorLock.lock(); defer { syncErrorLock.unlock() }; _encounteredSyncError = newValue }
    }

    // Thread-safe alert deduplication table
    static let alertTimesLock = OSAllocatedUnfairLock()
    static var _lastAlertTimes: [UUID: Date] = [:]
    static func getAlertTime(_ key: UUID) -> Date? {
        alertTimesLock.lock(); defer { alertTimesLock.unlock() }
        return _lastAlertTimes[key]
    }
    static func setAlertTime(_ key: UUID, _ value: Date) {
        alertTimesLock.lock(); defer { alertTimesLock.unlock() }
        _lastAlertTimes[key] = value
    }
    static func removeAlertTime(_ key: UUID) {
        alertTimesLock.lock(); defer { alertTimesLock.unlock() }
        _lastAlertTimes.removeValue(forKey: key)
    }

    var notifiedRequestIds = Set<String>()
    var isFirstSync = true
    var consecutiveSyncFailures = 0

    // MARK: - Realtime WebSocket
    // Declared here (class body) so all extension files can access them.
    var webSocketTask: URLSessionWebSocketTask?
    var realtimeListenTask: Task<Void, Never>?
    let config = AppConfig.shared
    lazy var anonKey: String = config.supabaseAnonKey

    // Shared lock for Realtime state (reconnect attempt, isCurrentlySyncing)
    let syncLock = OSAllocatedUnfairLock()

    // Reconnection: Exponential backoff state
    var _reconnectAttempt: Int = 0
    var reconnectAttempt: Int {
        get { syncLock.lock(); defer { syncLock.unlock() }; return _reconnectAttempt }
        set { syncLock.lock(); defer { syncLock.unlock() }; _reconnectAttempt = newValue }
    }
    let maxReconnectDelay: TimeInterval = 30.0

    // Debounce: Prevent rapid-fire pulls from multiple Realtime events
    var realtimeDebounceWorkItem: DispatchWorkItem?

    // Guard: Prevent circular sync (iPad push → receive own event → pull again)
    var _isCurrentlySyncing: Bool = false
    var isCurrentlySyncing: Bool {
        get { syncLock.lock(); defer { syncLock.unlock() }; return _isCurrentlySyncing }
        set { syncLock.lock(); defer { syncLock.unlock() }; _isCurrentlySyncing = newValue }
    }

    // Heartbeat: Store timer reference to prevent leak on reconnect
    var heartbeatTimer: Timer?

    // MARK: - Init

    private override init() {
        super.init()
        setupLifecycleObservers()
    }

    // MARK: - Remote Value Parsing Helpers
    // These are `internal` so all extension files can call them.

    func remoteDouble(_ value: Any?, fallback defaultValue: Double = 0.0) -> Double {
        value as? Double ?? (value as? NSNumber)?.doubleValue ?? (value as? String).flatMap(Double.init) ?? defaultValue
    }

    func remoteInt(_ value: Any?, fallback defaultValue: Int = 0) -> Int {
        value as? Int ?? (value as? NSNumber)?.intValue ?? (value as? String).flatMap(Int.init) ?? defaultValue
    }

    func remoteBool(_ value: Any?, fallback defaultValue: Bool = false) -> Bool {
        if let boolValue = value as? Bool { return boolValue }
        if let intValue = value as? Int { return intValue != 0 }
        if let stringValue = value as? String {
            return ["true", "1", "yes"].contains(stringValue.lowercased())
        }
        return defaultValue
    }

    // MARK: - Static Date Formatters (shared instances — avoids allocation on every sync call)
    static let iso8601WithFractionals: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    static let iso8601Standard: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static let fallbackFormatters: [DateFormatter] = {
        let formats = [
            "yyyy-MM-dd HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd HH:mm:ss.SSSZ",
            "yyyy-MM-dd HH:mm:ss"
        ]
        return formats.map { format in
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = TimeZone(secondsFromGMT: 0)
            df.dateFormat = format
            return df
        }
    }()

    func parseISO8601Date(_ value: Any?, fallback defaultValue: Date = Date()) -> Date {
        return parseISO8601DateOptional(value) ?? defaultValue
    }

    func parseISO8601DateOptional(_ value: Any?) -> Date? {
        guard let stringValue = value as? String else { return nil }
        let cleanStr = stringValue.replacingOccurrences(of: " ", with: "T")
        if let d = SyncEngine.iso8601WithFractionals.date(from: cleanStr) { return d }
        if let d = SyncEngine.iso8601Standard.date(from: cleanStr) { return d }
        
        for df in SyncEngine.fallbackFormatters {
            let input = df.dateFormat.contains("'T'") ? cleanStr : stringValue
            if let d = df.date(from: input) { return d }
        }
        
        return nil
    }

    func remoteDate(_ value: Any?, fallback defaultValue: Date = Date()) -> Date {
        return parseISO8601Date(value, fallback: defaultValue)
    }

    // MARK: - Offline Mode Support

    /// Cancel any in-flight sync task immediately.
    /// Called when the user switches to Offline Mode in Settings so the current
    /// sync cycle stops making network calls without waiting for it to finish.
    func cancelPendingSync() {
        activeSyncTask?.cancel()
        activeSyncTask = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        realtimeListenTask?.cancel()
        realtimeListenTask = nil
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        Task { await MainActor.run { self.syncStatus = .offline } }
    }
}
