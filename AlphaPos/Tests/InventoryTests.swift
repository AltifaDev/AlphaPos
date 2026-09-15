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
        transactions: [InventoryEntry],
        allowNegativeSales: Bool = false
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
        return allowNegativeSales ? result : max(0.0, result)
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
            test_allowNegativeSale_tracksBackorder(),
            test_receivingStock_offsetsNegativeBalance(),
            test_reorderAlert_triggersWhenAtOrBelowLevel(),
            test_reorderAlert_notTriggeredAboveLevel(),
            test_multipleTransactions_correctRunningTotal(),
            test_adjustAfterReceive_overridesTotal(),
            test_stockValue_calculation(),
            test_stockValue_zeroQuantity(),
            test_stockValue_zeroCost(),
            test_packagePricing_totalPrice_convertsToBaseUnit(),
            test_packagePricing_perPackPrice_convertsToBaseUnit(),
            test_packagePricing_rejectsIncompatibleUnits(),
            test_smartUnitFormatter_scaling(),
            test_multiTierPackaging_cratePackPieceConversion(),
            test_multiTierPackaging_packPieceConversion()
        ]
    }

    private static func test_packagePricing_totalPrice_convertsToBaseUnit() -> TestResult {
        let name = #function
        let result = StockPackagePricing.calculate(
            packCount: 7,
            quantityPerPack: 1.5,
            packageUnit: .kg,
            inventoryUnit: .g,
            enteredPrice: 693,
            priceMode: .total
        )
        guard let result else { return .failure(name, "Expected a valid package calculation") }
        guard approxEqual(result.receivedQuantity, 10_500) else {
            return .failure(name, "Expected 10,500 g, got \(result.receivedQuantity)")
        }
        return approxEqual(result.unitCost, 0.066)
            ? .success(name)
            : .failure(name, "Expected 0.066/g, got \(result.unitCost)")
    }

    private static func test_packagePricing_perPackPrice_convertsToBaseUnit() -> TestResult {
        let name = #function
        let result = StockPackagePricing.calculate(
            packCount: 3,
            quantityPerPack: 720,
            packageUnit: .ml,
            inventoryUnit: .ml,
            enteredPrice: 83,
            priceMode: .perPack
        )
        guard let result else { return .failure(name, "Expected a valid package calculation") }
        guard approxEqual(result.totalCost, 249) else {
            return .failure(name, "Expected total cost 249, got \(result.totalCost)")
        }
        return approxEqual(result.unitCost, 249.0 / 2160.0)
            ? .success(name)
            : .failure(name, "Unexpected unit cost \(result.unitCost)")
    }

    private static func test_packagePricing_rejectsIncompatibleUnits() -> TestResult {
        let name = #function
        let result = StockPackagePricing.calculate(
            packCount: 1,
            quantityPerPack: 1,
            packageUnit: .kg,
            inventoryUnit: .ml,
            enteredPrice: 100,
            priceMode: .total
        )
        return result == nil
            ? .success(name)
            : .failure(name, "Mass must not convert to volume")
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

    private static func test_allowNegativeSale_tracksBackorder() -> TestResult {
        let name = #function
        let result = InventoryCalculator.applyTransactions(
            starting: 2.0,
            transactions: [InventoryEntry(type: .sell, quantity: 5.0)],
            allowNegativeSales: true
        )
        return approxEqual(result, -3.0)
            ? .success(name)
            : .failure(name, "Expected -3.0 after an allowed oversell, got \(result)")
    }

    private static func test_receivingStock_offsetsNegativeBalance() -> TestResult {
        let name = #function
        let result = InventoryCalculator.applyTransactions(
            starting: -5.0,
            transactions: [InventoryEntry(type: .receive, quantity: 10.0)],
            allowNegativeSales: true
        )
        return approxEqual(result, 5.0)
            ? .success(name)
            : .failure(name, "Expected receipt to offset the negative balance to 5.0, got \(result)")
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

    private static func test_smartUnitFormatter_scaling() -> TestResult {
        let name = #function

        // Test 1: 20,000 grams should format to 20 kg with (20,000 g) secondary
        let formatted20kg = SmartUnitFormatter.format(quantity: 20000.0, unit: "g")
        guard formatted20kg.primaryText == "20 kg" else {
            return .failure(name, "Expected '20 kg', got '\(formatted20kg.primaryText)'")
        }
        guard formatted20kg.secondaryText != nil else {
            return .failure(name, "Expected secondary text for 20000 g")
        }

        // Test 2: 500 grams should format to 500 g without secondary
        let formatted500g = SmartUnitFormatter.format(quantity: 500.0, unit: "g")
        guard formatted500g.primaryText == "500 g", formatted500g.secondaryText == nil else {
            return .failure(name, "Expected '500 g' without secondary, got '\(formatted500g.fullText)'")
        }

        // Test 3: 5,500 ml should format to 5.5 L
        let formatted5L = SmartUnitFormatter.format(quantity: 5500.0, unit: "ml")
        guard formatted5L.primaryText == "5.5 L" else {
            return .failure(name, "Expected '5.5 L', got '\(formatted5L.primaryText)'")
        }

        return .success(name)
    }

    private static func test_multiTierPackaging_cratePackPieceConversion() -> TestResult {
        let name = #function

        // 2 Crates, where 1 Crate = 12 Packs, 1 Pack = 3 Bags, 1 Bag = 500g, Total Price = 1800 Baht
        // Total pieces = 2 * 12 * 3 = 72 bags
        // Total grams = 72 * 500 = 36,000 g
        // Cost per gram = 1,800 / 36,000 = 0.05 ฿/g
        let calc = MultiTierPackagingCalculation.calculate(
            level: .crate,
            enteredCount: 2,
            packsPerCrate: 12,
            piecesPerPack: 3,
            pieceSize: 500,
            pieceUnit: .g,
            inventoryUnit: .g,
            enteredPrice: 1800,
            priceMode: .total,
            isThai: true
        )

        guard let calc else {
            return .failure(name, "Expected valid calculation result")
        }
        guard approxEqual(calc.totalBaseQuantity, 36000.0) else {
            return .failure(name, "Expected 36000 g, got \(calc.totalBaseQuantity)")
        }
        guard approxEqual(calc.unitCost, 0.05) else {
            return .failure(name, "Expected 0.05 ฿/g, got \(calc.unitCost)")
        }
        guard approxEqual(calc.totalCost, 1800.0) else {
            return .failure(name, "Expected 1800 total cost, got \(calc.totalCost)")
        }

        return .success(name)
    }

    private static func test_multiTierPackaging_packPieceConversion() -> TestResult {
        let name = #function

        // 5 Packs, where 1 Pack = 3 Bags, 1 Bag = 500g, Price per pack = 75 Baht
        // Total pieces = 5 * 3 = 15 bags
        // Total grams = 15 * 500 = 7,500 g
        // Total cost = 5 * 75 = 375 Baht
        // Cost per gram = 375 / 7500 = 0.05 ฿/g
        let calc = MultiTierPackagingCalculation.calculate(
            level: .pack,
            enteredCount: 5,
            packsPerCrate: 12,
            piecesPerPack: 3,
            pieceSize: 500,
            pieceUnit: .g,
            inventoryUnit: .g,
            enteredPrice: 75,
            priceMode: .perPack,
            isThai: true
        )

        guard let calc else {
            return .failure(name, "Expected valid calculation result")
        }
        guard approxEqual(calc.totalBaseQuantity, 7500.0) else {
            return .failure(name, "Expected 7500 g, got \(calc.totalBaseQuantity)")
        }
        guard approxEqual(calc.totalCost, 375.0) else {
            return .failure(name, "Expected 375 total cost, got \(calc.totalCost)")
        }
        guard approxEqual(calc.unitCost, 0.05) else {
            return .failure(name, "Expected 0.05 ฿/g, got \(calc.unitCost)")
        }

        return .success(name)
    }
}
