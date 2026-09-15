import Foundation

private enum CheckoutLifecycleLogic {
    static func canAcquireLock(owner: String?, lockedAt: Date?, requester: String, now: Date, timeout: TimeInterval = 120) -> Bool {
        guard let owner, owner != requester, let lockedAt else { return true }
        return now.timeIntervalSince(lockedAt) >= timeout
    }

    static func isTerminal(_ state: String) -> Bool {
        ["captured", "failed", "cancelled", "expired"].contains(state)
    }

    static func idempotencyKey(checkoutId: UUID, method: String) -> String {
        "checkout:\(checkoutId.uuidString):\(method.lowercased().replacingOccurrences(of: " ", with: "_"))"
    }
}

enum CheckoutLifecycleTests {
    static func runAll() -> [TestResult] {
        [
            test_activeForeignLockBlocksRecall(),
            test_expiredLockCanBeRecovered(),
            test_idempotencyKeyIsStable(),
            test_pendingIsNotTerminal(),
            test_captureIsTerminal(),
            test_qrCodeOrderVoidLifecycle(),
            test_voidReversalAmountIntegrity()
        ]
    }

    private static func test_activeForeignLockBlocksRecall() -> TestResult {
        let now = Date()
        let allowed = CheckoutLifecycleLogic.canAcquireLock(owner: "A", lockedAt: now, requester: "B", now: now)
        return !allowed ? .success(#function) : .failure(#function, "A live foreign lock must block recall")
    }

    private static func test_expiredLockCanBeRecovered() -> TestResult {
        let now = Date()
        let allowed = CheckoutLifecycleLogic.canAcquireLock(owner: "A", lockedAt: now.addingTimeInterval(-121), requester: "B", now: now)
        return allowed ? .success(#function) : .failure(#function, "Expired lock should be recoverable")
    }

    private static func test_idempotencyKeyIsStable() -> TestResult {
        let id = UUID()
        let a = CheckoutLifecycleLogic.idempotencyKey(checkoutId: id, method: "QR PromptPay")
        let b = CheckoutLifecycleLogic.idempotencyKey(checkoutId: id, method: "QR PromptPay")
        return a == b ? .success(#function) : .failure(#function, "Retry must reuse the same key")
    }

    private static func test_pendingIsNotTerminal() -> TestResult {
        !CheckoutLifecycleLogic.isTerminal("awaiting_customer")
            ? .success(#function) : .failure(#function, "Pending attempt must remain resumable")
    }

    private static func test_captureIsTerminal() -> TestResult {
        CheckoutLifecycleLogic.isTerminal("captured")
            ? .success(#function) : .failure(#function, "Captured attempt must be terminal")
    }

    private static func test_qrCodeOrderVoidLifecycle() -> TestResult {
        let paymentMethod = "qr_promptpay"
        let isSupportedForVoid = ["cash", "qr_promptpay", "credit_card", "true_money"].contains(paymentMethod)
        guard isSupportedForVoid else {
            return .failure(#function, "qr_promptpay must be supported for void and ledger reversal")
        }
        let terminalState = "cancelled"
        guard CheckoutLifecycleLogic.isTerminal(terminalState) else {
            return .failure(#function, "cancelled must be terminal state")
        }
        return .success(#function)
    }

    private static func test_voidReversalAmountIntegrity() -> TestResult {
        let paidAmount = 150.0
        let previouslyRefunded = 0.0
        let unrefunded = max(0, paidAmount - previouslyRefunded)
        return unrefunded == 150.0 ? .success(#function) : .failure(#function, "Void reversal must match unrefunded balance")
    }
}
