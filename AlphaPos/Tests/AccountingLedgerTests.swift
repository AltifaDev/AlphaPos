import Foundation

struct AccountingLedgerTests {
    private static func result(_ name: String, _ passed: Bool, _ details: String = "") -> TestResult {
        passed ? .success(name) : .failure(name, details.isEmpty ? "assertion failed" : details)
    }

    static func runAll() -> [TestResult] {
        let order = UUID()
        let summary = AccountingMath.summarize([
            AccountingFact(eventType: "sale_capture", amount: 400, paymentMethod: "cash", orderId: order, isLateAdjustment: false),
            AccountingFact(eventType: "government_subsidy", amount: 600, paymentMethod: "thai_program", orderId: order, isLateAdjustment: false),
            AccountingFact(eventType: "refund", amount: -100, paymentMethod: "cash", orderId: order, isLateAdjustment: true),
            AccountingFact(eventType: "payment_void", amount: -400, paymentMethod: "cash", orderId: order, isLateAdjustment: false),
            AccountingFact(eventType: "sale_capture", amount: 400, paymentMethod: "credit_card", orderId: order, isLateAdjustment: false)
        ])
        let idempotentInput = [AccountingFact(eventType: "sale_capture", amount: 100, paymentMethod: "qr_promptpay", orderId: order, isLateAdjustment: false)]
        let started = Date()
        let large = AccountingMath.summarize((0..<100_000).map { index in
            AccountingFact(eventType: index % 10 == 0 ? "refund" : "sale_capture", amount: index % 10 == 0 ? -10 : 10, paymentMethod: "cash", orderId: nil, isLateAdjustment: false)
        })
        let elapsed = Date().timeIntervalSince(started)
        let shiftId = UUID()
        let otherShiftId = UUID()
        let openedAt = Date(timeIntervalSince1970: 1_000)
        let closedAt = Date(timeIntervalSince1970: 2_000)
        let screenshotSummary = AccountingMath.summarize([
            AccountingFact(eventType: "sale_capture", amount: 3245, paymentMethod: "cash", orderId: order, isLateAdjustment: false),
            AccountingFact(eventType: "sale_capture", amount: 5175, paymentMethod: "qr", orderId: order, isLateAdjustment: false),
            AccountingFact(eventType: "government_subsidy", amount: 6070, paymentMethod: "thai_program", orderId: order, isLateAdjustment: false),
            AccountingFact(eventType: "sale_capture", amount: 282, paymentMethod: "delivery", orderId: order, isLateAdjustment: false),
            AccountingFact(eventType: "refund", amount: -89, paymentMethod: "delivery", orderId: order, isLateAdjustment: false)
        ])
        let staffDiscount = AccountingMath.fixedPerItemDiscount(
            value: 10,
            minimumUnitPrice: 50,
            lines: [(quantity: 1, total: 60), (quantity: 2, total: 120), (quantity: 3, total: 180)]
        )
        let cappedStaffDiscount = AccountingMath.fixedPerItemDiscount(
            value: 10,
            minimumUnitPrice: 50,
            lines: [(quantity: 2, total: 12)]
        )
        let thresholdStaffDiscount = AccountingMath.fixedPerItemDiscount(
            value: 10,
            minimumUnitPrice: 50,
            lines: [(quantity: 2, total: 100), (quantity: 1, total: 49)]
        )
        return [
            result("staff promotion discounts one to three ฿60 units", staffDiscount == 60),
            result("staff promotion excludes prices below discount threshold", cappedStaffDiscount == 0),
            result("staff promotion threshold is strictly greater than ฿50", thresholdStaffDiscount == 0),
            result("shift screenshot net deducts refund once", screenshotSummary.capturedSales == 14772 && screenshotSummary.refunds == 89 && screenshotSummary.netSales == 14683),
            result("shift screenshot storefront includes government support", screenshotSummary.cash + screenshotSummary.qr + 6070 == 14490),
            result("shift rejects legacy refund after close", !RegisterShiftScope.contains(eventSessionId: nil, eventAt: closedAt.addingTimeInterval(1), sessionId: shiftId, openedAt: openedAt, closedAt: closedAt)),
            result("ledger correction preserves sales and moves tender", summary.capturedSales == 1_000 && summary.cash == 0 && summary.card == 400),
            result("ledger refund reduces net", summary.refunds == 100 && summary.netSales == 900),
            result("ledger late adjustment retained", summary.lateAdjustmentTotal == -100),
            result("ledger unique order count", summary.orderIds.count == 1),
            result("ledger deterministic reduction", AccountingMath.summarize(idempotentInput) == AccountingMath.summarize(idempotentInput)),
            result("ledger 100k performance", large.paymentCount == 90_000 && large.refundCount == 10_000 && elapsed < 2.0, "\(elapsed)s"),
            result("shift uses explicit session identity", RegisterShiftScope.contains(eventSessionId: shiftId, eventAt: .distantFuture, sessionId: shiftId, openedAt: openedAt, closedAt: closedAt)),
            result("shift rejects another explicit session", !RegisterShiftScope.contains(eventSessionId: otherShiftId, eventAt: Date(timeIntervalSince1970: 1_500), sessionId: shiftId, openedAt: openedAt, closedAt: closedAt)),
            result("shift time fallback includes legacy event", RegisterShiftScope.contains(eventSessionId: nil, eventAt: Date(timeIntervalSince1970: 1_500), sessionId: shiftId, openedAt: openedAt, closedAt: closedAt))
        ]
    }
}
