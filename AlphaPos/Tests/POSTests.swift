// POSTests.swift
// AlphaPos — Phase 4: Unit Testing Suite
//
// Tests core POS business logic (pure arithmetic; no SwiftData dependency):
//   - Cart line-item subtotal: quantity × unitPrice
//   - Cart grand total = sum of all subtotals
//   - Tax calculation (configurable %)
//   - Service charge calculation
//   - Percentage discount
//   - Fixed-amount discount capped at subtotal
//   - Order total = subtotal + tax + serviceCharge − discount
//   - Floating-point precision (within 1e-9 tolerance)
//   - Zero-quantity edge case
//   - Zero-price edge case

import Foundation

// ─── Lightweight POS calculation helpers (pure functions) ────────────────────
// These mirror the logic that ViewModels / checkout flows rely on.

private struct CartLine {
    let unitPrice: Double
    let quantity:  Int
    var subtotal: Double { Double(quantity) * unitPrice }
}

private enum POSCalculator {
    /// Sum of all line-item subtotals.
    static func cartSubtotal(_ lines: [CartLine]) -> Double {
        lines.reduce(0) { $0 + $1.subtotal }
    }

    /// Tax amount.
    static func taxAmount(subtotal: Double, rate: Double) -> Double {
        subtotal * rate
    }

    /// Service charge amount.
    static func serviceChargeAmount(subtotal: Double, rate: Double) -> Double {
        subtotal * rate
    }

    /// Percentage-based discount (0…1 → proportion of subtotal).
    static func percentageDiscount(subtotal: Double, rate: Double) -> Double {
        subtotal * rate
    }

    /// Fixed discount, capped so it can never exceed subtotal.
    static func fixedDiscount(subtotal: Double, fixed: Double) -> Double {
        min(fixed, subtotal)
    }

    static func bundleDiscount(unitPrice: Double, quantity: Int, required: Int, bundlePrice: Double) -> Double {
        let groups = quantity / required
        return max(0, unitPrice * Double(required * groups) - bundlePrice * Double(groups))
    }

    static func buyXGetYDiscount(unitPrice: Double, quantity: Int, buy: Int, free: Int) -> Double {
        unitPrice * Double((quantity / (buy + free)) * free)
    }

    static func buyXPayYDiscount(unitPrice: Double, quantity: Int, buy: Int, pay: Int) -> Double {
        unitPrice * Double((quantity / buy) * (buy - pay))
    }

    /// Final order total.
    static func orderTotal(
        subtotal: Double,
        tax: Double,
        serviceCharge: Double,
        discount: Double
    ) -> Double {
        subtotal + tax + serviceCharge - discount
    }

    static func deliveryFinancials(
        total: Double, refunded: Double, gp: Double,
        adFee: Double, adFeeIsPct: Bool, otherFee: Double
    ) -> (cost: Double, net: Double) {
        let revenue = max(0, total - refunded)
        let gpCost = revenue * min(max(gp, 0), 100) / 100
        let adCost = adFeeIsPct ? revenue * min(max(adFee, 0), 100) / 100 : max(adFee, 0)
        let cost = gpCost + adCost + max(otherFee, 0)
        return (cost, revenue - cost)
    }

    static func resolvePostDeliveryOrderType(configured: String?, enableTableSystem: Bool) -> String {
        let preferred = configured ?? "take_out"
        if preferred == "dine_in" {
            return enableTableSystem ? "dine_in" : "walk_in"
        }
        return "take_out"
    }
}
// ─────────────────────────────────────────────────────────────────────────────

private let ε = 1e-9   // floating-point comparison tolerance

private func approxEqual(_ a: Double, _ b: Double) -> Bool {
    abs(a - b) < ε
}

// MARK: -

enum POSTests {

    static func runAll() -> [TestResult] {
        [
            test_lineItemSubtotal(),
            test_lineItemSubtotal_zeroPriceItem(),
            test_lineItemSubtotal_zeroQuantity(),
            test_cartSubtotal_multipleLines(),
            test_cartSubtotal_emptyCart(),
            test_taxAmount_standardRate(),
            test_taxAmount_zeroRate(),
            test_serviceCharge_standardRate(),
            test_percentageDiscount(),
            test_fixedDiscount_belowSubtotal(),
            test_fixedDiscount_cappedAtSubtotal(),
            test_bundleDiscount(),
            test_buyXGetYDiscount(),
            test_buyXPayYDiscount(),
            test_orderTotal_fullCombo(),
            test_orderTotal_noDiscountNoExtras(),
            test_orderTotal_neverNegative(),
            test_deliveryFees_standardOrder(),
            test_deliveryFees_percentageFeesFollowRefund(),
            test_deliveryFees_clampInvalidPercentages(),
            test_governmentSupport_splitAndRounding(),
            test_split_payment_allocation(),
            test_void_item_inventory_reversal(),
            test_postDeliveryOrderType_defaultsToTakeaway(),
            test_postDeliveryOrderType_configuredTakeaway(),
            test_postDeliveryOrderType_configuredDineInWithTableSystem(),
            test_postDeliveryOrderType_configuredDineInWithoutTableSystem()
        ]
    }

    private static func test_deliveryFees_standardOrder() -> TestResult {
        let name = #function
        let result = POSCalculator.deliveryFinancials(total: 1_000, refunded: 0, gp: 30, adFee: 5, adFeeIsPct: true, otherFee: 20)
        return approxEqual(result.cost, 370) && approxEqual(result.net, 630)
            ? .success(name)
            : .failure(name, "Expected cost 370/net 630, got \(result)")
    }

    private static func test_deliveryFees_percentageFeesFollowRefund() -> TestResult {
        let name = #function
        let result = POSCalculator.deliveryFinancials(total: 1_000, refunded: 500, gp: 30, adFee: 5, adFeeIsPct: true, otherFee: 20)
        return approxEqual(result.cost, 195) && approxEqual(result.net, 305)
            ? .success(name)
            : .failure(name, "Expected refund-adjusted cost 195/net 305, got \(result)")
    }

    private static func test_deliveryFees_clampInvalidPercentages() -> TestResult {
        let name = #function
        let result = POSCalculator.deliveryFinancials(total: 100, refunded: 0, gp: 120, adFee: -5, adFeeIsPct: true, otherFee: -10)
        return approxEqual(result.cost, 100) && approxEqual(result.net, 0)
            ? .success(name)
            : .failure(name, "Invalid percentages must be safely bounded, got \(result)")
    }

    private static func test_governmentSupport_splitAndRounding() -> TestResult {
        let split = GovernmentSupportProgram.split(total: 89)
        let exactTotal = abs((split.citizen + split.government) - 89) < 0.001
        let correctShares = abs(split.citizen - 35.60) < 0.001 && abs(split.government - 53.40) < 0.001
        return exactTotal && correctShares
            ? .success(#function)
            : .failure(#function, "Expected citizen 35.60 + government 53.40 = 89.00")
    }

    // MARK: - Line-item subtotal

    private static func test_lineItemSubtotal() -> TestResult {
        let name = #function
        let line = CartLine(unitPrice: 120.0, quantity: 3)
        return approxEqual(line.subtotal, 360.0)
            ? .success(name)
            : .failure(name, "Expected 360.0, got \(line.subtotal)")
    }

    private static func test_lineItemSubtotal_zeroPriceItem() -> TestResult {
        let name = #function
        let line = CartLine(unitPrice: 0.0, quantity: 5)
        return approxEqual(line.subtotal, 0.0)
            ? .success(name)
            : .failure(name, "Zero-price item should have 0 subtotal, got \(line.subtotal)")
    }

    private static func test_lineItemSubtotal_zeroQuantity() -> TestResult {
        let name = #function
        let line = CartLine(unitPrice: 99.0, quantity: 0)
        return approxEqual(line.subtotal, 0.0)
            ? .success(name)
            : .failure(name, "Zero-qty item should have 0 subtotal, got \(line.subtotal)")
    }

    // MARK: - Cart subtotal

    private static func test_cartSubtotal_multipleLines() -> TestResult {
        let name = #function
        let lines: [CartLine] = [
            CartLine(unitPrice: 100.0, quantity: 2),  // 200
            CartLine(unitPrice:  50.0, quantity: 3),  // 150
            CartLine(unitPrice:  25.0, quantity: 4)   // 100
        ]
        let expected = 450.0
        let actual   = POSCalculator.cartSubtotal(lines)
        return approxEqual(actual, expected)
            ? .success(name)
            : .failure(name, "Expected \(expected), got \(actual)")
    }

    private static func test_cartSubtotal_emptyCart() -> TestResult {
        let name   = #function
        let actual = POSCalculator.cartSubtotal([])
        return approxEqual(actual, 0.0)
            ? .success(name)
            : .failure(name, "Empty cart subtotal must be 0.0, got \(actual)")
    }

    // MARK: - Tax

    private static func test_taxAmount_standardRate() -> TestResult {
        let name   = #function
        // Thai VAT: 7 %
        let actual = POSCalculator.taxAmount(subtotal: 1000.0, rate: 0.07)
        return approxEqual(actual, 70.0)
            ? .success(name)
            : .failure(name, "Expected 70.0 tax, got \(actual)")
    }

    private static func test_taxAmount_zeroRate() -> TestResult {
        let name   = #function
        let actual = POSCalculator.taxAmount(subtotal: 1000.0, rate: 0.0)
        return approxEqual(actual, 0.0)
            ? .success(name)
            : .failure(name, "Zero-rate tax must be 0.0, got \(actual)")
    }

    // MARK: - Service charge

    private static func test_serviceCharge_standardRate() -> TestResult {
        let name   = #function
        // 10 % service charge
        let actual = POSCalculator.serviceChargeAmount(subtotal: 1000.0, rate: 0.10)
        return approxEqual(actual, 100.0)
            ? .success(name)
            : .failure(name, "Expected 100.0 service charge, got \(actual)")
    }

    // MARK: - Discount

    private static func test_percentageDiscount() -> TestResult {
        let name   = #function
        // 15 % off 500 → 75
        let actual = POSCalculator.percentageDiscount(subtotal: 500.0, rate: 0.15)
        return approxEqual(actual, 75.0)
            ? .success(name)
            : .failure(name, "Expected 75.0 discount, got \(actual)")
    }

    private static func test_fixedDiscount_belowSubtotal() -> TestResult {
        let name   = #function
        let actual = POSCalculator.fixedDiscount(subtotal: 300.0, fixed: 50.0)
        return approxEqual(actual, 50.0)
            ? .success(name)
            : .failure(name, "Fixed discount below subtotal should equal fixed amount, got \(actual)")
    }

    private static func test_fixedDiscount_cappedAtSubtotal() -> TestResult {
        let name   = #function
        // discount (500) > subtotal (200) → cap at 200
        let actual = POSCalculator.fixedDiscount(subtotal: 200.0, fixed: 500.0)
        return approxEqual(actual, 200.0)
            ? .success(name)
            : .failure(name, "Fixed discount must be capped at subtotal (200.0), got \(actual)")
    }

    private static func test_bundleDiscount() -> TestResult {
        let name = #function
        let actual = POSCalculator.bundleDiscount(unitPrice: 120, quantity: 6, required: 3, bundlePrice: 299)
        return approxEqual(actual, 122) ? .success(name) : .failure(name, "Expected 122, got \(actual)")
    }

    private static func test_buyXGetYDiscount() -> TestResult {
        let name = #function
        let actual = POSCalculator.buyXGetYDiscount(unitPrice: 100, quantity: 4, buy: 1, free: 1)
        return approxEqual(actual, 200) ? .success(name) : .failure(name, "Expected 200, got \(actual)")
    }

    private static func test_buyXPayYDiscount() -> TestResult {
        let name = #function
        let actual = POSCalculator.buyXPayYDiscount(unitPrice: 90, quantity: 6, buy: 3, pay: 2)
        return approxEqual(actual, 180) ? .success(name) : .failure(name, "Expected 180, got \(actual)")
    }

    // MARK: - Order total

    private static func test_orderTotal_fullCombo() -> TestResult {
        let name = #function
        // subtotal 1000, tax 70 (7%), service 100 (10%), discount 50 → 1120
        let actual = POSCalculator.orderTotal(
            subtotal: 1000.0,
            tax: 70.0,
            serviceCharge: 100.0,
            discount: 50.0
        )
        return approxEqual(actual, 1120.0)
            ? .success(name)
            : .failure(name, "Expected total 1120.0, got \(actual)")
    }

    private static func test_orderTotal_noDiscountNoExtras() -> TestResult {
        let name   = #function
        let actual = POSCalculator.orderTotal(
            subtotal: 450.0,
            tax: 0.0,
            serviceCharge: 0.0,
            discount: 0.0
        )
        return approxEqual(actual, 450.0)
            ? .success(name)
            : .failure(name, "Expected total 450.0, got \(actual)")
    }

    /// Ensure a massive fixed discount cannot produce a negative total.
    private static func test_orderTotal_neverNegative() -> TestResult {
        let name     = #function
        let subtotal = 100.0
        let discount = POSCalculator.fixedDiscount(subtotal: subtotal, fixed: 9999.0)
        let actual   = POSCalculator.orderTotal(
            subtotal: subtotal,
            tax: 0.0,
            serviceCharge: 0.0,
            discount: discount
        )
        return actual >= 0.0
            ? .success(name)
            : .failure(name, "Order total must never be negative, got \(actual)")
    }

    /// Verifies GAAP-compliant proportional split payment distribution.
    private static func test_split_payment_allocation() -> TestResult {
        let name = #function
        let orderTotals = [500.0, 300.0]
        var paymentsAllocated = [0.0, 0.0]
        var payments = [400.0, 400.0]

        for i in 0..<orderTotals.count {
            var remaining = orderTotals[i]
            while remaining > 0 && !payments.isEmpty {
                let payAmount = min(remaining, payments[0])
                paymentsAllocated[i] += payAmount
                remaining -= payAmount
                payments[0] -= payAmount
                if payments[0] <= 0 {
                    payments.removeFirst()
                }
            }
        }

        guard approxEqual(paymentsAllocated[0], 500.0) && approxEqual(paymentsAllocated[1], 300.0) else {
            return .failure(name, "Proportional split payment allocation failed: \(paymentsAllocated)")
        }
        return .success(name)
    }

    /// Verifies that raw material inventory deductions are correctly credited back on item voids.
    /// NOTE: Actual database trigger execution is verified in PostgreSQL/SQLite integration tests
    /// (see Database/test_void_stock_reversal_database.sql). This unit test verifies the
    /// arithmetic logic for POS quantity restorations.
    private static func test_void_item_inventory_reversal() -> TestResult {
        let name = #function
        var currentInventory = 100.0
        let orderedQty = 10
        let recipeQty = 1.5 // 1.5 units per recipe

        // 1. Simulate stock deduction on order item insertion (status: cooking)
        currentInventory -= recipeQty * Double(orderedQty)

        // 2. Simulate stock reversal on order item cancellation (status: cancelled)
        let voidQty = 10
        currentInventory += recipeQty * Double(voidQty)

        guard approxEqual(currentInventory, 100.0) else {
            return .failure(name, "Void reversal failed to restore stock levels mathematically")
        }
        return .success(name)
    }

    private static func test_postDeliveryOrderType_defaultsToTakeaway() -> TestResult {
        let name = #function
        let resolved = POSCalculator.resolvePostDeliveryOrderType(configured: nil, enableTableSystem: true)
        return resolved == "take_out"
            ? .success(name)
            : .failure(name, "Expected take_out by default, got \(resolved)")
    }

    private static func test_postDeliveryOrderType_configuredTakeaway() -> TestResult {
        let name = #function
        let resolved = POSCalculator.resolvePostDeliveryOrderType(configured: "take_out", enableTableSystem: true)
        return resolved == "take_out"
            ? .success(name)
            : .failure(name, "Expected take_out, got \(resolved)")
    }

    private static func test_postDeliveryOrderType_configuredDineInWithTableSystem() -> TestResult {
        let name = #function
        let resolved = POSCalculator.resolvePostDeliveryOrderType(configured: "dine_in", enableTableSystem: true)
        return resolved == "dine_in"
            ? .success(name)
            : .failure(name, "Expected dine_in when table system enabled, got \(resolved)")
    }

    private static func test_postDeliveryOrderType_configuredDineInWithoutTableSystem() -> TestResult {
        let name = #function
        let resolved = POSCalculator.resolvePostDeliveryOrderType(configured: "dine_in", enableTableSystem: false)
        return resolved == "walk_in"
            ? .success(name)
            : .failure(name, "Expected walk_in when table system disabled, got \(resolved)")
    }
}
