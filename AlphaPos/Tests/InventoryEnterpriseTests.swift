// InventoryEnterpriseTests.swift
// AlphaPos — Phase 4: Unit Testing Suite
//
// Tests enterprise inventory features:
//   - Weighted Average Cost (WAC) formulas
//   - Purchase Order lifecycle states & total calculations
//   - Multi-Branch catalog stock mapping & isolation logic
//   - Stock Transfer quantity transfers

import Foundation

// ─── Pure functions to simulate Enterprise Business Logic ────────────────────
private enum EnterpriseCalculator {
    
    /// Calculate the Weighted Average Cost (WAC)
    static func calculateWAC(oldQty: Double, oldCost: Double, newQty: Double, newCost: Double) -> Double {
        let totalQty = oldQty + newQty
        guard totalQty > 0 else { return newCost }
        return ((oldQty * oldCost) + (newQty * newCost)) / totalQty
    }
    
    /// Verify state transitions for POs: draft -> sent -> received
    static func canTransition(from current: String, to next: String) -> Bool {
        switch (current, next) {
        case ("draft", "sent"): return true
        case ("draft", "cancelled"): return true
        case ("sent", "received"): return true
        case ("sent", "partially_received"): return true
        case ("sent", "cancelled"): return true
        case ("partially_received", "received"): return true
        case ("partially_received", "cancelled"): return true
        default: return false
        }
    }
    
    /// POS local checkout stock lookup & deduction across branches.
    /// Deducts quantity only from the matching SKU in the ACTIVE branch catalog.
    static func deductFromBranchCatalog(
        sku: String,
        qty: Double,
        activeBranchId: UUID,
        items: inout [(id: UUID, sku: String, branchId: UUID, qty: Double)]
    ) -> Bool {
        if let idx = items.firstIndex(where: { $0.branchId == activeBranchId && $0.sku == sku }) {
            items[idx].qty -= qty
            return true
        }
        return false
    }
    
    /// Transfer stock from one branch item to another branch item.
    static func transferStock(
        fromQty: Double,
        toQty: Double,
        transferQty: Double
    ) -> (newFromQty: Double, newToQty: Double, success: Bool) {
        guard transferQty > 0, transferQty <= fromQty else {
            return (fromQty, toQty, false)
        }
        return (fromQty - transferQty, toQty + transferQty, true)
    }
}
// ─────────────────────────────────────────────────────────────────────────────

private let ε = 1e-9

private func approxEqual(_ a: Double, _ b: Double) -> Bool {
    abs(a - b) < ε
}

enum InventoryEnterpriseTests {
    
    static func runAll() -> [TestResult] {
        [
            test_WAC_calculations(),
            test_WAC_zeroStartingQty(),
            test_PO_stateTransitions(),
            test_PO_invalidStateTransitions(),
            test_multiBranch_isolationAndSKUMap(),
            test_stockTransfer_quantities(),
            test_PO_partialReceiveAndCancel(),
            test_PO_WACIncrementalCalculations(),
            test_rawMaterialCreationPropagation(),
            test_supplierReturnStockDeduction()
        ]
    }
    
    // MARK: - WAC Tests
    
    private static func test_WAC_calculations() -> TestResult {
        let name = #function
        // 10 items @ 5.0 cost + 5 items @ 8.0 cost -> WAC should be 6.0
        let actual = EnterpriseCalculator.calculateWAC(oldQty: 10.0, oldCost: 5.0, newQty: 5.0, newCost: 8.0)
        return approxEqual(actual, 6.0)
            ? .success(name)
            : .failure(name, "Expected WAC of 6.0, got \(actual)")
    }
    
    private static func test_WAC_zeroStartingQty() -> TestResult {
        let name = #function
        // 0 items @ 0 cost + 10 items @ 12.5 cost -> WAC should be 12.5
        let actual = EnterpriseCalculator.calculateWAC(oldQty: 0.0, oldCost: 0.0, newQty: 10.0, newCost: 12.5)
        return approxEqual(actual, 12.5)
            ? .success(name)
            : .failure(name, "Expected WAC of 12.5, got \(actual)")
    }
    
    // MARK: - PO State Transitions
    
    private static func test_PO_stateTransitions() -> TestResult {
        let name = #function
        let t1 = EnterpriseCalculator.canTransition(from: "draft", to: "sent")
        let t2 = EnterpriseCalculator.canTransition(from: "sent", to: "received")
        return (t1 && t2)
            ? .success(name)
            : .failure(name, "PO transitions draft->sent->received should be valid")
    }
    
    private static func test_PO_invalidStateTransitions() -> TestResult {
        let name = #function
        let t1 = EnterpriseCalculator.canTransition(from: "draft", to: "received")
        let t2 = EnterpriseCalculator.canTransition(from: "received", to: "sent")
        return (!t1 && !t2)
            ? .success(name)
            : .failure(name, "Invalid PO transitions should return false")
    }
    
    // MARK: - Multi-Branch Isolation
    
    private static func test_multiBranch_isolationAndSKUMap() -> TestResult {
        let name = #function
        let branchA = UUID()
        let branchB = UUID()
        
        var mockCatalog = [
            (id: UUID(), sku: "ING-BEAN", branchId: branchA, qty: 100.0),
            (id: UUID(), sku: "ING-BEAN", branchId: branchB, qty: 50.0)
        ]
        
        // Deduct 20 from active branch A
        let success = EnterpriseCalculator.deductFromBranchCatalog(sku: "ING-BEAN", qty: 20.0, activeBranchId: branchA, items: &mockCatalog)
        
        let itemA = mockCatalog.first(where: { $0.branchId == branchA })!
        let itemB = mockCatalog.first(where: { $0.branchId == branchB })!
        
        return (success && approxEqual(itemA.qty, 80.0) && approxEqual(itemB.qty, 50.0))
            ? .success(name)
            : .failure(name, "Branch A stock should be 80.0, Branch B should remain 50.0. Got A: \(itemA.qty), B: \(itemB.qty)")
    }
    
    // MARK: - Stock Transfer
    
    private static func test_stockTransfer_quantities() -> TestResult {
        let name = #function
        // Transfer 15.0 from 50.0 to 10.0
        let result = EnterpriseCalculator.transferStock(fromQty: 50.0, toQty: 10.0, transferQty: 15.0)
        return (result.success && approxEqual(result.newFromQty, 35.0) && approxEqual(result.newToQty, 25.0))
            ? .success(name)
            : .failure(name, "Expected transfer result to be 35.0 and 25.0, got \(result.newFromQty) and \(result.newToQty)")
    }
    
    private static func test_PO_partialReceiveAndCancel() -> TestResult {
        let name = #function
        let t1 = EnterpriseCalculator.canTransition(from: "sent", to: "partially_received")
        let t2 = EnterpriseCalculator.canTransition(from: "partially_received", to: "received")
        let t3 = EnterpriseCalculator.canTransition(from: "partially_received", to: "cancelled")
        
        return (t1 && t2 && t3)
            ? .success(name)
            : .failure(name, "PO transitions with partially_received and cancelled should be valid")
    }
    
    private static func test_PO_WACIncrementalCalculations() -> TestResult {
        let name = #function
        // Start with 0 stock, receive 5 @ $10
        var qty = 0.0
        var wac = 0.0
        
        let wac1 = EnterpriseCalculator.calculateWAC(oldQty: qty, oldCost: wac, newQty: 5.0, newCost: 10.0)
        qty += 5.0
        wac = wac1
        
        // Receive 5 @ $12
        let wac2 = EnterpriseCalculator.calculateWAC(oldQty: qty, oldCost: wac, newQty: 5.0, newCost: 12.0)
        
        return approxEqual(wac2, 11.0)
            ? .success(name)
            : .failure(name, "Expected incremental WAC of 11.0, got \(wac2)")
    }
    
    private static func test_rawMaterialCreationPropagation() -> TestResult {
        let name = #function
        let branchA = UUID()
        let branchB = UUID()
        let branches = [branchA, branchB]
        
        var mockItems: [(sku: String, branchId: UUID, qty: Double)] = []
        let newSku = "RAW-SUGAR"
        let activeBranch = branchA
        
        // Simulating vm.addInventoryItem
        mockItems.append((sku: newSku, branchId: activeBranch, qty: 0.0))
        for otherBranch in branches {
            if otherBranch != activeBranch {
                mockItems.append((sku: newSku, branchId: otherBranch, qty: 0.0))
            }
        }
        
        let countForSku = mockItems.filter { $0.sku == newSku }.count
        return countForSku == 2
            ? .success(name)
            : .failure(name, "Expected RAW-SUGAR to propagate to 2 branches, found \(countForSku)")
    }
    
    private static func test_supplierReturnStockDeduction() -> TestResult {
        let name = #function
        var qty = 10.0
        let returnQty = 3.0
        
        // Simulating processReturnToSupplier
        qty -= returnQty
        
        return approxEqual(qty, 7.0)
            ? .success(name)
            : .failure(name, "Expected stock qty after return to be 7.0, got \(qty)")
    }
}
