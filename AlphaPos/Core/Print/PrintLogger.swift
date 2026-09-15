import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - PrintLogger
// Class reference type helper to collect step-by-step diagnostic print logs safely.
// ─────────────────────────────────────────────────────────────────────────────
final class PrintLogger: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.alphapos.printlogger")
    nonisolated(unsafe) private var _logs = [String]()

    nonisolated var logs: [String] {
        queue.sync { _logs }
    }

    nonisolated func append(_ message: String) {
        print("[PrintService] \(message)")
        queue.sync {
            self._logs.append(message)
        }
    }
}
