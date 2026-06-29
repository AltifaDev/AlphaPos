import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - PrintLogger
// Class reference type helper to collect step-by-step diagnostic print logs safely.
// ─────────────────────────────────────────────────────────────────────────────
final class PrintLogger: Sendable {
    private let queue = DispatchQueue(label: "com.alphapos.printlogger")
    private var _logs = [String]()
    
    var logs: [String] {
        queue.sync { _logs }
    }
    
    func append(_ message: String) {
        print("[PrintService] \(message)")
        queue.async {
            self._logs.append(message)
        }
    }
}
