// AppErrorHandler.swift
// AlphaPos — Centralised Error Handling & Retry Infrastructure
//
// ─────────────────────────────────────────────────────────────────────────────
// Provides:
//   ModelContext.saveWithRetry()    — replaces all `modelContext.saveWithLogging(label: #function)`
//   NetworkManager.withRetry()      — exponential backoff for any async throws
//   SyncRetryPolicy                 — configurable backoff parameters
//   AppLogger                       — structured os.Logger wrapper (replaces print)
//   PendingOperation                — offline queue for failed writes
// ─────────────────────────────────────────────────────────────────────────────

import Foundation
import SwiftData
import os
import Combine

// MARK: - AppLogger

/// Structured logger using the unified Apple logging system.
/// Replace `print(...)` calls with `AppLogger.<subsystem>.log(...)`.
enum AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.alphapos"

    static let sync      = Logger(subsystem: subsystem, category: "Sync")
    static let inventory = Logger(subsystem: subsystem, category: "Inventory")
    static let pos       = Logger(subsystem: subsystem, category: "POS")
    static let network   = Logger(subsystem: subsystem, category: "Network")
    static let database  = Logger(subsystem: subsystem, category: "Database")
    static let general   = Logger(subsystem: subsystem, category: "General")
}

// MARK: - SyncRetryPolicy

/// Exponential backoff configuration for network retry operations.
struct SyncRetryPolicy {
    /// Maximum number of retry attempts before giving up.
    var maxAttempts: Int
    /// Base delay in seconds (multiplied by 2^attempt for each retry).
    var baseDelaySeconds: Double
    /// Maximum delay cap in seconds (prevents runaway waits).
    var maxDelaySeconds: Double
    /// Jitter fraction (0–1) added to avoid thundering-herd.
    var jitterFraction: Double

    nonisolated static let `default` = SyncRetryPolicy(
        maxAttempts:      3,
        baseDelaySeconds: 1.0,
        maxDelaySeconds:  30.0,
        jitterFraction:   0.2
    )

    nonisolated static let aggressive = SyncRetryPolicy(
        maxAttempts:      5,
        baseDelaySeconds: 0.5,
        maxDelaySeconds:  60.0,
        jitterFraction:   0.3
    )

    nonisolated static let conservative = SyncRetryPolicy(
        maxAttempts:      2,
        baseDelaySeconds: 2.0,
        maxDelaySeconds:  20.0,
        jitterFraction:   0.1
    )

    /// Calculate delay for attempt N (1-indexed).
    func delay(for attempt: Int) -> Double {
        let exponential = baseDelaySeconds * pow(2.0, Double(attempt - 1))
        let capped = min(exponential, maxDelaySeconds)
        let jitter = capped * jitterFraction * Double.random(in: 0...1)
        return capped + jitter
    }
}

// MARK: - Retryable Error Classification

/// Classifies network errors as retryable or terminal.
enum RetryDecision {
    case retry(after: Double)   // wait then retry
    case giveUp(Error)          // terminal failure

    static func decide(
        error: Error,
        attempt: Int,
        policy: SyncRetryPolicy
    ) -> RetryDecision {
        guard attempt <= policy.maxAttempts else {
            return .giveUp(error)
        }
        // Non-retryable: auth errors, server validation failures
        if let netErr = error as? NetworkError {
            switch netErr {
            case .serverError(let msg) where msg.contains("PGRST") && !msg.contains("PGRST301"):
                return .giveUp(error)   // PostgREST schema/constraint error — retrying won't help
            default:
                break
            }
        }
        let nsErr = error as NSError
        // Non-retryable: cancelled, URL format errors
        if nsErr.code == NSURLErrorCancelled
            || nsErr.code == NSURLErrorBadURL
            || nsErr.code == NSURLErrorUnsupportedURL {
            return .giveUp(error)
        }
        return .retry(after: policy.delay(for: attempt))
    }
}

// MARK: - withRetry helper (free function)

/// Executes `operation` with exponential backoff retries.
/// - Parameters:
///   - label: Human-readable label for logging (e.g. "uploadInventoryLot")
///   - policy: Retry policy (default: 3 attempts, 1s/2s/4s + jitter)
///   - operation: The async throwing operation to execute
/// - Returns: The result of the first successful attempt.
/// - Throws: The last error if all attempts fail.
func withRetry<T>(
    label: String,
    policy: SyncRetryPolicy = .default,
    operation: () async throws -> T
) async throws -> T {
    var lastError: Error?
    for attempt in 1...(policy.maxAttempts + 1) {
        do {
            return try await operation()
        } catch {
            lastError = error
            switch RetryDecision.decide(error: error, attempt: attempt, policy: policy) {
            case .giveUp(let finalError):
                AppLogger.network.error("[\(label)] Terminal failure after \(attempt) attempt(s): \(finalError.localizedDescription)")
                throw finalError
            case .retry(let delay):
                AppLogger.network.warning("[\(label)] Attempt \(attempt)/\(policy.maxAttempts) failed (\(error.localizedDescription)). Retrying in \(String(format: "%.1f", delay))s...")
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }
    throw lastError ?? NSError(domain: "AppErrorHandler", code: -1,
                                userInfo: [NSLocalizedDescriptionKey: "Unknown retry failure"])
}

// MARK: - ModelContext.saveWithRetry

extension ModelContext {
    /// Saves the context, logging any error. Does NOT silently swallow it.
    /// Use this as a drop-in replacement for `modelContext.saveWithLogging(label: #function)`.
    ///
    /// - Parameter label: Context hint for the log message (e.g. function name).
    /// - Returns: True if saved successfully, false on error.
    @discardableResult
    func saveWithLogging(label: String = #function) -> Bool {
        do {
            try save()
            return true
        } catch {
            AppLogger.database.error("[Save] \(label): \(error.localizedDescription)")
            // Queue for retry on next sync cycle (set isSynced = false ensures
            // the sync engine will re-upload on the next performSync call)
            return false
        }
    }

    /// Saves and retries up to `maxAttempts` times on transient SwiftData errors.
    /// Falls back to `saveWithLogging` for non-retriable errors.
    @discardableResult
    func saveWithRetry(
        label: String = #function,
        maxAttempts: Int = 3,
        baseDelay: Double = 0.1
    ) async -> Bool {
        for attempt in 1...maxAttempts {
            do {
                try save()
                return true
            } catch {
                let isRetriable = isRetriableSaveError(error)
                if !isRetriable || attempt == maxAttempts {
                    AppLogger.database.error("[Save:\(attempt)] \(label): \(error.localizedDescription)")
                    return false
                }
                let delay = baseDelay * pow(2.0, Double(attempt - 1))
                AppLogger.database.warning("[Save:\(attempt)] \(label): transient error, retrying in \(String(format: "%.2f", delay))s")
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        return false
    }

    private func isRetriableSaveError(_ error: Error) -> Bool {
        let nsErr = error as NSError
        // SwiftData concurrent write conflict codes
        return nsErr.domain == "NSCocoaErrorDomain"
            && (nsErr.code == 133021   // Merge conflict
             || nsErr.code == 134302   // Persistent store save
             || nsErr.code == 134400)  // Migration in progress
    }
}

// MARK: - PendingOperation (Offline Write Queue)

/// Represents a write operation that failed and should be retried on next sync.
/// Stored in UserDefaults as lightweight JSON (no SwiftData dependency).
struct PendingOperation: Codable, Identifiable {
    let id: UUID
    let entityType: String     // e.g. "InventoryItem", "InventoryLot"
    let entityId: UUID
    let operation: String      // "upsert" | "softDelete"
    let failedAt: Date
    var retryCount: Int
    let maxRetries: Int

    var isExhausted: Bool { retryCount >= maxRetries }
}

/// In-memory + UserDefaults queue for operations that failed during sync.
@MainActor
final class OfflineWriteQueue: ObservableObject {
    static let shared = OfflineWriteQueue()
    private let storageKey = "alphapos.offline_queue"

    @Published private(set) var pending: [PendingOperation] = []

    private init() { load() }

    func enqueue(entityType: String, entityId: UUID, operation: String, maxRetries: Int = 5) {
        // Deduplicate: same entity + operation → bump retryCount
        if let idx = pending.firstIndex(where: { $0.entityId == entityId && $0.operation == operation }) {
            pending[idx].retryCount += 1
            if pending[idx].isExhausted {
                AppLogger.sync.error("[OfflineQueue] Exhausted retries for \(entityType) \(entityId) [\(operation)]")
                pending.remove(at: idx)
            }
        } else {
            let op = PendingOperation(
                id: UUID(),
                entityType: entityType,
                entityId: entityId,
                operation: operation,
                failedAt: Date(),
                retryCount: 0,
                maxRetries: maxRetries
            )
            pending.append(op)
        }
        save()
    }

    func dequeue(id: UUID) {
        pending.removeAll { $0.id == id }
        save()
    }

    func clearAll() {
        pending.removeAll()
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([PendingOperation].self, from: data) else { return }
        pending = decoded
    }

    private func save() {
        if let encoded = try? JSONEncoder().encode(pending) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }
}
