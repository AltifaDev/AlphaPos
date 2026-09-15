import Foundation
import Testing
@testable import AlphaPosStaff

@Suite("Checkout state machine")
struct CheckoutStateMachineTests {
    @Test func successfulCheckout() throws {
        var machine = CheckoutStateMachine()
        try machine.apply(.begin)
        try machine.apply(.succeed)
        #expect(machine.state == .completed)
    }

    @Test func failedCheckoutCanRetry() throws {
        var machine = CheckoutStateMachine()
        try machine.apply(.begin)
        try machine.apply(.fail)
        try machine.apply(.retry)
        #expect(machine.state == .processing)
    }

    @Test func completedCheckoutCannotRunTwice() throws {
        var machine = CheckoutStateMachine()
        try machine.apply(.begin)
        try machine.apply(.succeed)
        #expect(throws: CheckoutStateError.self) { try machine.apply(.begin) }
    }
}
