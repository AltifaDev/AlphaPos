import Foundation
import Observation

struct NetworkDiagnosticEvent: Identifiable, Codable {
    let id: UUID
    let requestId: String
    let method: String
    let endpoint: String
    let statusCode: Int?
    let durationMilliseconds: Int
    let occurredAt: Date
    let error: String?
    let retryable: Bool
}

@Observable
final class NetworkDiagnostics {
    static let shared = NetworkDiagnostics()
    private(set) var recentEvents: [NetworkDiagnosticEvent] = []
    private let maximumEvents = 100

    func record(_ event: NetworkDiagnosticEvent) {
        recentEvents.insert(event, at: 0)
        if recentEvents.count > maximumEvents { recentEvents.removeLast(recentEvents.count - maximumEvents) }
    }

    var recentFailures: [NetworkDiagnosticEvent] { recentEvents.filter { $0.error != nil } }
}

struct StaffHTTPError: Error, LocalizedError {
    let statusCode: Int
    let requestId: String
    let endpoint: String
    let serverMessage: String

    var isRetryable: Bool { statusCode == 408 || statusCode == 429 || statusCode >= 500 }
    var errorDescription: String? { "\(endpoint) failed (HTTP \(statusCode), request \(requestId)): \(serverMessage)" }
}
