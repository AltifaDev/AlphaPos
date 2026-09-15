// OrderSettlementTests.swift
// AlphaPos — Order settlement / double-charge guard tests
//
// Verifies the pure predicate behind POSView.isOrderSettled and the payment
// breakdown consistency fallback used by pullCustomerOrders. Both address the
// reported iPad bug: a bill already paid (e.g. on a staff phone) kept showing
// "Ready for Payment" with an active pay button (double-charge risk), and the
// totals showed an inconsistent "Subtotal 0 / Total 90".

import Foundation

// Mirror of the pure settlement logic (kept equivalent to POSView.isOrderSettled
// and the pullCustomerOrders breakdown fallback). Standalone so the run_tests.sh
// swiftc build can exercise it without SwiftData.
enum OrderSettlementLogic {
    /// Fulfillment completion is not financial settlement. Only captured tender
    /// covering the total may remove an order from the payment surface.
    static func isSettled(status: String, total: Double, paid: Double) -> Bool {
        total <= 0.005 || max(0, total - paid) < 0.005
    }

    /// Whether the POS should still offer payment actions for a table session.
    /// Requires an empty cart, all items served, and at least one UNsettled order.
    static func shouldShowPaymentActions(
        cartEmpty: Bool,
        allServed: Bool,
        hasUnsettledOrder: Bool
    ) -> Bool {
        cartEmpty && allServed && hasUnsettledOrder
    }

    /// Consistent subtotal fallback: prefer server subtotal, else the summed item
    /// lines, else the whole total (so the UI never shows Subtotal 0 / Total N).
    static func effectiveSubtotal(remoteSubtotal: Double, itemsSubtotal: Double, total: Double) -> Double {
        if remoteSubtotal > 0 { return remoteSubtotal }
        if itemsSubtotal > 0 { return itemsSubtotal }
        return total
    }
}

enum OrderSettlementTests {

    static func runAll() -> [TestResult] {
        [
            test_notSettledWhenCompletedButUnpaid(),
            test_settledWhenHasCompletedPayment(),
            test_notSettledWhenPartiallyPaid(),
            test_notSettledWhenPreparingAndUnpaid(),
            test_paymentActionsHiddenWhenAllOrdersSettled(),
            test_paymentActionsShownWhenUnsettledRemains(),
            test_subtotalFallsBackToItemsSum(),
            test_subtotalFallsBackToTotal(),
            test_subtotalPrefersServerValue()
        ]
    }

    // ── Settlement predicate ─────────────────────────────────────────────────

    private static func test_notSettledWhenCompletedButUnpaid() -> TestResult {
        let name = #function
        return !OrderSettlementLogic.isSettled(status: "completed", total: 100, paid: 0)
            ? .success(name)
            : .failure(name, "Fulfillment completion must not hide an unpaid order.")
    }

    private static func test_settledWhenHasCompletedPayment() -> TestResult {
        let name = #function
        // Paid on a phone: status may still read "served"/"preparing" locally,
        // but a completed payment means the bill is settled.
        return OrderSettlementLogic.isSettled(status: "served", total: 100, paid: 100)
            ? .success(name)
            : .failure(name, "Order with a completed payment must be treated as settled.")
    }

    private static func test_notSettledWhenPreparingAndUnpaid() -> TestResult {
        let name = #function
        return OrderSettlementLogic.isSettled(status: "preparing", total: 100, paid: 0) == false
            ? .success(name)
            : .failure(name, "Unpaid, in-progress order must NOT be treated as settled.")
    }

    private static func test_notSettledWhenPartiallyPaid() -> TestResult {
        let name = #function
        return OrderSettlementLogic.isSettled(status: "served", total: 100, paid: 40) == false
            ? .success(name)
            : .failure(name, "A partial payment must leave the order open with an outstanding balance.")
    }

    // ── Payment-button gating (double-charge guard) ──────────────────────────

    private static func test_paymentActionsHiddenWhenAllOrdersSettled() -> TestResult {
        let name = #function
        // The reported bug: cart empty, items served, but the only order is
        // already paid → payment actions must be HIDDEN.
        let show = OrderSettlementLogic.shouldShowPaymentActions(
            cartEmpty: true, allServed: true, hasUnsettledOrder: false
        )
        return show == false
            ? .success(name)
            : .failure(name, "Payment actions must be hidden when every order is already settled (no double charge).")
    }

    private static func test_paymentActionsShownWhenUnsettledRemains() -> TestResult {
        let name = #function
        let show = OrderSettlementLogic.shouldShowPaymentActions(
            cartEmpty: true, allServed: true, hasUnsettledOrder: true
        )
        return show
            ? .success(name)
            : .failure(name, "Payment actions should show when an unsettled, all-served order remains.")
    }

    // ── Breakdown consistency (Subtotal 0 / Total 90 bug) ────────────────────

    private static func test_subtotalFallsBackToItemsSum() -> TestResult {
        let name = #function
        // Server sent total only (subtotal 0); items sum to 90.
        let s = OrderSettlementLogic.effectiveSubtotal(remoteSubtotal: 0, itemsSubtotal: 90, total: 90)
        return s == 90
            ? .success(name)
            : .failure(name, "Subtotal should fall back to summed item lines (expected 90, got \(s)).")
    }

    private static func test_subtotalFallsBackToTotal() -> TestResult {
        let name = #function
        // Server sent total only and no usable item prices → use total.
        let s = OrderSettlementLogic.effectiveSubtotal(remoteSubtotal: 0, itemsSubtotal: 0, total: 90)
        return s == 90
            ? .success(name)
            : .failure(name, "Subtotal should fall back to total when no breakdown/items (expected 90, got \(s)).")
    }

    private static func test_subtotalPrefersServerValue() -> TestResult {
        let name = #function
        let s = OrderSettlementLogic.effectiveSubtotal(remoteSubtotal: 80, itemsSubtotal: 90, total: 90)
        return s == 80
            ? .success(name)
            : .failure(name, "Server-provided subtotal should win when present (expected 80, got \(s)).")
    }
}
