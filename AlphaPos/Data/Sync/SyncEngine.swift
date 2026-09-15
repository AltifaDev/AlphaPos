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
    var restaurantTableId: String? = nil
    var diningAreaId: String? = nil
    var expiresAt: String? = nil
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
    // A cold launch has not synchronized yet; never advertise a false green "Synced" state.
    @Published var syncStatus: SyncStatus = .syncing
    @Published var lastSyncedAt: Date? = nil
    @Published var activeRequests: [ServiceRequest] = []

    // Online hub metrics from `get_sync_health` / `sync_outbox` (shared with Staff + web).
    @Published var hubPending: Int = 0
    @Published var hubFailed: Int = 0
    @Published var hubProcessing: Int = 0
    @Published var hubOldestLabel: String = "—"
    @Published var hubHealthError: String? = nil
    @Published var hubByJobType: [(type: String, count: Int)] = []
    @Published var cloudEntityCounts: [String: Int] = [:]
    @Published var isRefreshingOnlineHealth: Bool = false
    /// Human-readable reason for the latest sync warning / critical error (UI).
    @Published var lastSyncErrorSummary: String? = nil
    /// Individual diagnostic lines shown under the status banner.
    @Published var lastSyncFailureDetails: [String] = []
    /// Soft (non-blocking) failures occurred in the last cycle — status stays idle.
    @Published var hadSoftSyncFailures: Bool = false

    private static let lastSyncedAtDefaultsKey = "sync_engine_last_synced_at"

    var isRealtimeConnected: Bool {
        webSocketTask != nil && realtimeListenTask != nil
    }

    // MARK: - Internal Properties (accessible by all extension files in the module)
    // Note: `internal` (no modifier) is required because Swift `private` is
    // file-scoped for classes — extensions in separate files cannot access it.

    var cachedModelContext: ModelContext?
    var activeSyncTask: Task<Void, Never>?

    // MARK: - Cart Protection
    // Menu-item IDs currently held in the active POS cart. Sync must NOT delete
    // these models (dedup / hard-delete reconcile) while they are in use, or the
    // cart UI crashes with "backing data could no longer be found". The POS view
    // model keeps this in sync as the cart changes.
    var protectedMenuItemIds: Set<String> = []

    // Thread-safe sync error flag.
    // When `failuresAreSoft` is true, `encounteredSyncError = true` only records a
    // soft warning (pull / outbox / orphan rows) and does NOT flip the global status
    // to `.error` — that reserved for critical push / auth failures.
    let syncErrorLock = OSAllocatedUnfairLock()
    var _encounteredSyncError: Bool = false
    var _failuresAreSoft: Bool = false
    var _softFailureFlag: Bool = false
    var _failureLabels: [String] = []

    /// When true, assigning `encounteredSyncError = true` becomes a soft failure.
    var failuresAreSoft: Bool {
        get { syncErrorLock.lock(); defer { syncErrorLock.unlock() }; return _failuresAreSoft }
        set { syncErrorLock.lock(); defer { syncErrorLock.unlock() }; _failuresAreSoft = newValue }
    }

    var encounteredSyncError: Bool {
        get {
            syncErrorLock.lock(); defer { syncErrorLock.unlock() }
            return _encounteredSyncError
        }
        set {
            if newValue {
                syncErrorLock.lock()
                let treatSoft = _failuresAreSoft
                syncErrorLock.unlock()

                // Capture the latest HTTP failure so bare `= true` still surfaces detail.
                let autoLabels = treatSoft
                    ? []
                    : NetworkManager.shared.recentFailureSummaries(limit: 2)

                syncErrorLock.lock()
                if treatSoft {
                    _softFailureFlag = true
                } else {
                    _encounteredSyncError = true
                    if _failureLabels.isEmpty {
                        _failureLabels.append(contentsOf: autoLabels)
                    }
                }
                let snapshot = _failureLabels
                syncErrorLock.unlock()

                if !treatSoft, !snapshot.isEmpty {
                    Task { @MainActor in
                        self.lastSyncErrorSummary = snapshot.suffix(3).joined(separator: " · ")
                        self.lastSyncFailureDetails = Array(snapshot.suffix(8))
                    }
                }
            } else {
                syncErrorLock.lock()
                _encounteredSyncError = false
                _softFailureFlag = false
                _failureLabels.removeAll(keepingCapacity: true)
                syncErrorLock.unlock()
            }
        }
    }

    var softSyncFailuresObserved: Bool {
        syncErrorLock.lock(); defer { syncErrorLock.unlock() }
        return _softFailureFlag
    }

    /// Record a labeled failure. Pass `soft: true` for non-blocking issues
    /// (orphaned rows, optional pulls) even during the push phase.
    func reportSyncFailure(_ label: String, soft: Bool? = nil) {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        syncErrorLock.lock()
        let treatSoft = soft ?? _failuresAreSoft
        if treatSoft {
            _softFailureFlag = true
        } else {
            _encounteredSyncError = true
        }
        if _failureLabels.count < 8 {
            _failureLabels.append(trimmed)
        }
        let snapshot = _failureLabels
        syncErrorLock.unlock()

        Task { @MainActor in
            self.lastSyncErrorSummary = snapshot.suffix(3).joined(separator: " · ")
            if treatSoft {
                self.hadSoftSyncFailures = true
            }
        }
    }

    func consumeFailureSummary(preferSoftMessage: Bool) -> String? {
        let details = buildFailureDetailLines(preferSoftMessage: preferSoftMessage)
        guard !details.isEmpty else { return nil }
        return details.prefix(3).joined(separator: " · ")
    }

    /// Merge SyncEngine labels + recent NetworkManager HTTP failures into UI lines.
    func buildFailureDetailLines(preferSoftMessage: Bool) -> [String] {
        syncErrorLock.lock()
        let labels = _failureLabels
        let soft = _softFailureFlag
        let critical = _encounteredSyncError
        syncErrorLock.unlock()

        var lines: [String] = []
        for label in labels where !lines.contains(label) {
            lines.append(label)
        }

        for net in NetworkManager.shared.recentFailureSummaries(limit: 5) {
            let already = lines.contains { existing in
                existing == net || existing.contains(String(net.prefix(48))) || net.contains(String(existing.prefix(48)))
            }
            if !already { lines.append(net) }
        }

        if critical || soft || preferSoftMessage {
            for op in OfflineWriteQueue.shared.pending.prefix(3) {
                let line = "Queued retry: \(op.entityType) \(op.operation) · \(op.entityId.uuidString.prefix(8))"
                if !lines.contains(line) { lines.append(line) }
            }
        }

        if lines.isEmpty, critical {
            lines.append("sync_unknown_critical_hint".t)
        } else if lines.isEmpty, soft || preferSoftMessage {
            lines.append("sync_partial_warning".t)
        }

        return Array(lines.prefix(8))
    }

    // Thread-safe alert deduplication table
    nonisolated static let alertTimesLock = OSAllocatedUnfairLock()
    nonisolated(unsafe) static var _lastAlertTimes: [UUID: Date] = [:]
    nonisolated static func getAlertTime(_ key: UUID) -> Date? {
        alertTimesLock.lock(); defer { alertTimesLock.unlock() }
        return _lastAlertTimes[key]
    }
    nonisolated static func setAlertTime(_ key: UUID, _ value: Date) {
        alertTimesLock.lock(); defer { alertTimesLock.unlock() }
        _lastAlertTimes[key] = value
    }
    nonisolated static func removeAlertTime(_ key: UUID) {
        alertTimesLock.lock(); defer { alertTimesLock.unlock() }
        _lastAlertTimes.removeValue(forKey: key)
    }
    nonisolated static func clearAlertTimes() {
        alertTimesLock.lock(); defer { alertTimesLock.unlock() }
        _lastAlertTimes.removeAll()
    }

    var notifiedRequestIds = Set<String>()
    var notifiedReadyOrderIds = Set<UUID>()
    var isFirstSync = true
    var consecutiveSyncFailures = 0

    /// Notification delivery state is tenant-session scoped. Reset it whenever
    /// credentials/workspace change so one merchant cannot suppress or inherit
    /// another merchant's alerts.
    func resetNotificationRuntimeState() {
        notifiedRequestIds.removeAll()
        notifiedReadyOrderIds.removeAll()
        isFirstSync = true
        activeRequests = []
        Self.clearAlertTimes()
    }

    // MARK: - Realtime WebSocket
    // Declared here (class body) so all extension files can access them.
    var webSocketTask: URLSessionWebSocketTask?
    var realtimeListenTask: Task<Void, Never>?
    var realtimeReconnectTask: Task<Void, Never>?
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

    // Coalesce rapid events without dropping changes from different tables.
    var realtimeDebounceWorkItem: DispatchWorkItem?
    var pendingRealtimeTables = Set<String>()
    var pendingRealtimeRecords: [String: [[String: Any]]] = [:]

    // Guard: Prevent circular sync (iPad push → receive own event → pull again)
    var _isCurrentlySyncing: Bool = false
    var isCurrentlySyncing: Bool {
        get { syncLock.lock(); defer { syncLock.unlock() }; return _isCurrentlySyncing }
        set { syncLock.lock(); defer { syncLock.unlock() }; _isCurrentlySyncing = newValue }
    }

    // Heartbeat: Store timer reference to prevent leak on reconnect
    var heartbeatTimer: Timer?
    var pendingHeartbeatRef: String?
    var heartbeatSequence = 0

    // MARK: - Init

    private override init() {
        super.init()
        if let ts = UserDefaults.standard.object(forKey: Self.lastSyncedAtDefaultsKey) as? Double {
            lastSyncedAt = Date(timeIntervalSince1970: ts)
        }
        setupLifecycleObservers()
    }

    func persistLastSyncedAt(_ date: Date) {
        lastSyncedAt = date
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: Self.lastSyncedAtDefaultsKey)
    }

    /// Refresh cloud outbox + live table counts from Supabase for Sync Health.
    func refreshOnlineSyncHealth() async {
        guard !isRefreshingOnlineHealth else { return }
        isRefreshingOnlineHealth = true
        defer { isRefreshingOnlineHealth = false }

        async let hub: Void = refreshHubOutboxHealth()
        async let counts: Void = refreshCloudEntityCounts()
        _ = await (hub, counts)
    }

    private func refreshHubOutboxHealth() async {
        do {
            let health = try await NetworkManager.shared.fetchSyncHealth()
            hubPending = remoteInt(health["pending_count"])
            hubFailed = remoteInt(health["failed_count"])
            hubProcessing = remoteInt(health["processing_count"])
            if let oldest = health["oldest_created_at"] as? String, !oldest.isEmpty {
                hubOldestLabel = String(oldest.prefix(16)).replacingOccurrences(of: "T", with: " ")
            } else {
                hubOldestLabel = "—"
            }
            if let rows = health["by_job_type"] as? [[String: Any]] {
                hubByJobType = rows.compactMap { row in
                    guard let type = row["job_type"] as? String else { return nil }
                    return (type, remoteInt(row["count"]))
                }
            } else {
                hubByJobType = []
            }
            hubHealthError = nil
            if let serverTime = parseISO8601DateOptional(health["server_time"]),
               lastSyncedAt == nil {
                // Prefer a real server clock over "never" when health responds.
                persistLastSyncedAt(serverTime)
            }
        } catch {
            hubHealthError = error.localizedDescription
            #if DEBUG
            print("SyncEngine [Hub Health]: \(error.localizedDescription)")
            #endif
        }
    }

    private func refreshCloudEntityCounts() async {
        // Merchant-scoped counts only — avoid is_deleted filters that some tables lack.
        let tables: [(key: String, endpoint: String)] = [
            ("orders", "orders"),
            ("payments", "payments"),
            ("restaurant_tables", "restaurant_tables"),
            ("menu_items", "menu_items"),
            ("inventory_items", "inventory_items"),
            ("customers", "customers"),
            ("loyalty_transactions", "loyalty_transactions"),
            ("gift_cards", "gift_cards"),
            ("cash_movements", "cash_movements"),
            ("refund_transactions", "refund_transactions")
        ]

        var next: [String: Int] = cloudEntityCounts
        await withTaskGroup(of: (String, Int?).self) { group in
            for table in tables {
                group.addTask {
                    do {
                        let count = try await NetworkManager.shared.fetchExactRowCount(endpoint: table.endpoint)
                        return (table.key, count)
                    } catch {
                        #if DEBUG
                        print("SyncEngine [Cloud Count \(table.key)]: \(error.localizedDescription)")
                        #endif
                        return (table.key, nil)
                    }
                }
            }
            for await (key, count) in group {
                if let count { next[key] = count }
            }
        }
        cloudEntityCounts = next
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
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        realtimeListenTask?.cancel()
        realtimeListenTask = nil
        realtimeReconnectTask?.cancel()
        realtimeReconnectTask = nil
        realtimeDebounceWorkItem?.cancel()
        realtimeDebounceWorkItem = nil
        pendingRealtimeTables.removeAll()
        pendingRealtimeRecords.removeAll()
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        pendingHeartbeatRef = nil
        Task { await MainActor.run { self.syncStatus = .offline } }
    }
}
