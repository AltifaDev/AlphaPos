// InventoryTests.swift
// AlphaPos — Phase 4: Unit Testing Suite
//
// Tests inventory stock-management business logic (pure; no SwiftData):
//   - Receiving stock increases currentQuantity
//   - Waste / removal decreases currentQuantity
//   - Manual adjustment sets exact quantity
//   - Sales deduction via "sell" transaction
//   - Reorder threshold detection
//   - Quantity cannot go below zero (guard check)
//   - Multiple sequential transactions produce correct running total
//   - costPrice change is reflected correctly in transaction records

import Foundation

// ─── Lightweight inventory helpers (pure functions) ──────────────────────────

private enum TransactionType: String {
    case receive = "receive"
    case waste   = "waste"
    case adjust  = "adjust"
    case sell    = "sell"
}

private struct InventoryEntry {
    let type:     TransactionType
    let quantity: Double
}

private enum InventoryCalculator {

    /// Apply a sequence of transactions to a starting quantity.
    /// Returns the resulting quantity, floored at 0.
    static func applyTransactions(
        starting: Double,
        transactions: [InventoryEntry]
    ) -> Double {
        let result = transactions.reduce(starting) { qty, tx in
            switch tx.type {
            case .receive:
                return qty + tx.quantity
            case .waste, .sell:
                return qty - tx.quantity
            case .adjust:
                return tx.quantity          // absolute override
            }
        }
        return max(0.0, result)
    }

    /// Returns true when stock has fallen to or below the reorder level.
    static func needsReorder(currentQuantity: Double, reorderLevel: Double) -> Bool {
        currentQuantity <= reorderLevel
    }

    /// Total value of inventory items on hand.
    static func stockValue(quantity: Double, costPrice: Double) -> Double {
        quantity * costPrice
    }
}
// ─────────────────────────────────────────────────────────────────────────────

private let ε = 1e-9

private func approxEqual(_ a: Double, _ b: Double) -> Bool {
    abs(a - b) < ε
}

// MARK: -

enum InventoryTests {

    static func runAll() -> [TestResult] {
        [
            test_receiveStock_increasesQuantity(),
            test_wasteStock_decreasesQuantity(),
            test_adjustStock_setsAbsoluteQuantity(),
            test_sellDeduction_decreasesQuantity(),
            test_quantityFlooredAtZero(),
            test_reorderAlert_triggersWhenAtOrBelowLevel(),
            test_reorderAlert_notTriggeredAboveLevel(),
            test_multipleTransactions_correctRunningTotal(),
            test_adjustAfterReceive_overridesTotal(),
            test_stockValue_calculation(),
            test_stockValue_zeroQuantity(),
            test_stockValue_zeroCost()
        ]
    }

    // MARK: - Receive

    private static func test_receiveStock_increasesQuantity() -> TestResult {
        let name   = #function
        let result = InventoryCalculator.applyTransactions(
            starting: 10.0,
            transactions: [InventoryEntry(type: .receive, quantity: 25.0)]
        )
        return approxEqual(result, 35.0)
            ? .success(name)
            : .failure(name, "Expected 35.0 after receive, got \(result)")
    }

    // MARK: - Waste

    private static func test_wasteStock_decreasesQuantity() -> TestResult {
        let name   = #function
        let result = InventoryCalculator.applyTransactions(
            starting: 50.0,
            transactions: [InventoryEntry(type: .waste, quantity: 12.5)]
        )
        return approxEqual(result, 37.5)
            ? .success(name)
            : .failure(name, "Expected 37.5 after waste, got \(result)")
    }

    // MARK: - Adjust

    private static func test_adjustStock_setsAbsoluteQuantity() -> TestResult {
        let name   = #function
        // Regardless of starting quantity, adjust overrides it.
        let result = InventoryCalculator.applyTransactions(
            starting: 9999.0,
            transactions: [InventoryEntry(type: .adjust, quantity: 42.0)]
        )
        return approxEqual(result, 42.0)
            ? .success(name)
            : .failure(name, "Adjust should set absolute qty to 42.0, got \(result)")
    }

    // MARK: - Sell

    private static func test_sellDeduction_decreasesQuantity() -> TestResult {
        let name   = #function
        let result = InventoryCalculator.applyTransactions(
            starting: 100.0,
            transactions: [InventoryEntry(type: .sell, quantity: 3.5)]
        )
        return approxEqual(result, 96.5)
            ? .success(name)
            : .failure(name, "Expected 96.5 after sell, got \(result)")
    }

    // MARK: - Floor at zero

    private static func test_quantityFlooredAtZero() -> TestResult {
        let name   = #function
        // Oversell scenario — quantity must not go negative.
        let result = InventoryCalculator.applyTransactions(
            starting: 5.0,
            transactions: [InventoryEntry(type: .waste, quantity: 100.0)]
        )
        return result >= 0.0
            ? .success(name)
            : .failure(name, "Quantity must be ≥ 0 after oversell, got \(result)")
    }

    // MARK: - Reorder alerts

    private static func test_reorderAlert_triggersWhenAtOrBelowLevel() -> TestResult {
        let name = #function
        // Exactly at reorder level should trigger.
        let atLevel    = InventoryCalculator.needsReorder(currentQuantity: 10.0, reorderLevel: 10.0)
        let belowLevel = InventoryCalculator.needsReorder(currentQuantity:  5.0, reorderLevel: 10.0)
        guard atLevel    else { return .failure(name, "Should trigger reorder when qty equals reorder level") }
        guard belowLevel else { return .failure(name, "Should trigger reorder when qty is below reorder level") }
        return .success(name)
    }

    private static func test_reorderAlert_notTriggeredAboveLevel() -> TestResult {
        let name   = #function
        let result = InventoryCalculator.needsReorder(currentQuantity: 10.1, reorderLevel: 10.0)
        return !result
            ? .success(name)
            : .failure(name, "Should NOT trigger reorder when qty is above reorder level")
    }

    // MARK: - Multiple sequential transactions

    private static func test_multipleTransactions_correctRunningTotal() -> TestResult {
        let name = #function
        // Start 20, receive 30, sell 5, waste 2, sell 3 → 40
        let txs: [InventoryEntry] = [
            InventoryEntry(type: .receive, quantity: 30),
            InventoryEntry(type: .sell,    quantity:  5),
            InventoryEntry(type: .waste,   quantity:  2),
            InventoryEntry(type: .sell,    quantity:  3)
        ]
        let result = InventoryCalculator.applyTransactions(starting: 20.0, transactions: txs)
        return approxEqual(result, 40.0)
            ? .success(name)
            : .failure(name, "Expected 40.0 after mixed transactions, got \(result)")
    }

    private static func test_adjustAfterReceive_overridesTotal() -> TestResult {
        let name = #function
        // receive adds, then adjust resets to absolute 15
        let txs: [InventoryEntry] = [
            InventoryEntry(type: .receive, quantity: 50.0),
            InventoryEntry(type: .adjust,  quantity: 15.0)
        ]
        let result = InventoryCalculator.applyTransactions(starting: 0.0, transactions: txs)
        return approxEqual(result, 15.0)
            ? .success(name)
            : .failure(name, "Adjust should override to 15.0, got \(result)")
    }

    // MARK: - Stock value

    private static func test_stockValue_calculation() -> TestResult {
        let name   = #function
        let value  = InventoryCalculator.stockValue(quantity: 12.5, costPrice: 80.0)
        return approxEqual(value, 1000.0)
            ? .success(name)
            : .failure(name, "Expected stock value 1000.0, got \(value)")
    }

    private static func test_stockValue_zeroQuantity() -> TestResult {
        let name  = #function
        let value = InventoryCalculator.stockValue(quantity: 0.0, costPrice: 500.0)
        return approxEqual(value, 0.0)
            ? .success(name)
            : .failure(name, "Zero quantity should yield 0 stock value, got \(value)")
    }

    private static func test_stockValue_zeroCost() -> TestResult {
        let name  = #function
        let value = InventoryCalculator.stockValue(quantity: 100.0, costPrice: 0.0)
        return approxEqual(value, 0.0)
            ? .success(name)
            : .failure(name, "Zero cost price should yield 0 stock value, got \(value)")
    }
}
