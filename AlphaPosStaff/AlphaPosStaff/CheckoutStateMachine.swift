import Foundation

enum CheckoutState: String, Codable, CaseIterable {
    case open
    case processing
    case completed
    case failed
    case cancelled
}

nonisolated enum CheckoutEvent: Equatable {
    case begin
    case succeed
    case fail
    case retry
    case cancel
}

enum CheckoutStateError: Error, Equatable {
    case invalidTransition(from: CheckoutState, event: CheckoutEvent)
}

/// Pure state machine shared by every Staff checkout surface. Server-side
/// `complete_checkout_atomic` is the authoritative transition/commit boundary.
struct CheckoutStateMachine {
    private(set) var state: CheckoutState = .open

    mutating func apply(_ event: CheckoutEvent) throws {
        let next: CheckoutState?
        switch (state, event) {
        case (.open, .begin), (.failed, .retry): next = .processing
        case (.processing, .succeed): next = .completed
        case (.processing, .fail): next = .failed
        case (.open, .cancel), (.failed, .cancel): next = .cancelled
        default: next = nil
        }
        guard let next else { throw CheckoutStateError.invalidTransition(from: state, event: event) }
        state = next
    }
}

struct CheckoutPaymentCommand {
    let id: UUID
    let amount: Decimal
    let method: String
}

struct CheckoutCommand {
    let orderId: UUID
    let idempotencyKey: String
    let tableNumber: String
    let payments: [CheckoutPaymentCommand]
    let expectedTotal: Decimal

    func validate() throws {
        guard !idempotencyKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !payments.isEmpty,
              payments.allSatisfy({ $0.amount > 0 }),
              payments.reduce(Decimal.zero, { $0 + $1.amount }) == expectedTotal else {
            throw NetworkError.invalidResponse
        }
    }
}
