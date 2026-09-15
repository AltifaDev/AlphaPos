import Foundation
import Testing
@testable import AlphaPosStaff

@Suite("Backend contract")
struct BackendContractTests {
    @Test func staffPINContractIsExactlyFourNumericDigits() {
        #expect(StaffPINPolicy.isValid("1234"))
        #expect(!StaffPINPolicy.isValid("123"))
        #expect(!StaffPINPolicy.isValid("12345"))
        #expect(!StaffPINPolicy.isValid("12a4"))
        #expect(StaffPINPolicy.normalized("12a345") == "1234")
    }

    @Test func checkoutCommandRejectsMismatchedTotal() {
        let command = CheckoutCommand(
            orderId: UUID(), idempotencyKey: "checkout:test", tableNumber: "QUICK",
            payments: [CheckoutPaymentCommand(id: UUID(), amount: 99, method: "cash")],
            expectedTotal: 100
        )
        #expect(throws: (any Error).self) { try command.validate() }
    }

    @Test func checkoutCommandAcceptsSplitTotal() throws {
        let command = CheckoutCommand(
            orderId: UUID(), idempotencyKey: "split:test", tableNumber: "A1",
            payments: [
                CheckoutPaymentCommand(id: UUID(), amount: 40, method: "cash"),
                CheckoutPaymentCommand(id: UUID(), amount: 60, method: "card")
            ], expectedTotal: 100
        )
        try command.validate()
    }
}
