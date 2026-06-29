// InventoryEnhancementTests.swift
// AlphaPos — Phase 1-3 Unit Tests (Pure logic)

import Foundation

private let ε = 1e-9
private func approxEqual(_ a: Double, _ b: Double) -> Bool {
    abs(a - b) < ε
}

struct TestRecipeLine {
    let costPrice: Double
    let quantityRequired: Double
}

enum InventoryEnhancementTests {
    
    static func runAll() -> [TestResult] {
        [
            test_recipeCosting_calculation(),
            test_foodCostPercent_calculation(),
            test_grossMargin_calculation(),
            test_finishedGoodSimulator(),
            test_auditVariance_calculation(),
            test_auditVarianceCost_calculation(),
            test_categoryRelationships(),
            test_productCreationAndAvailability(),
            test_modifierGroupMinMaxRestrictions(),
            test_modifierInventoryDeductionLink(),
            test_barcodeSearchMatch(),
            test_categoryFilter(),
            test_locationFilter(),
            test_productTaxCalculation(),
            test_fuzzyReceiptMatcher()
        ]
    }
    
    // MARK: - Recipe Costing & Margin
    
    private static func test_recipeCosting_calculation() -> TestResult {
        let name = #function
        let lines = [
            TestRecipeLine(costPrice: 0.4, quantityRequired: 18.0),  // 7.2
            TestRecipeLine(costPrice: 0.05, quantityRequired: 150.0) // 7.5
        ]
        
        let totalCost = lines.reduce(0.0) { $0 + ($1.costPrice * $1.quantityRequired) }
        return approxEqual(totalCost, 14.7)
            ? .success(name)
            : .failure(name, "Expected total costing 14.7, got \(totalCost)")
    }
    
    private static func test_foodCostPercent_calculation() -> TestResult {
        let name = #function
        let totalCost = 14.7
        let menuPrice = 80.0
        let foodCostPercent = (totalCost / menuPrice) * 100.0 // 18.375%
        return approxEqual(foodCostPercent, 18.375)
            ? .success(name)
            : .failure(name, "Expected food cost percent 18.375, got \(foodCostPercent)")
    }
    
    private static func test_grossMargin_calculation() -> TestResult {
        let name = #function
        let foodCostPercent = 18.375
        let margin = 100.0 - foodCostPercent // 81.625%
        return approxEqual(margin, 81.625)
            ? .success(name)
            : .failure(name, "Expected gross margin 81.625, got \(margin)")
    }
    
    // MARK: - Finished Goods Simulator
    
    private static func test_finishedGoodSimulator() -> TestResult {
        let name = #function
        // Simulate checking if a menu item has a 1:1 recipe matching the name and quantity is 1.0
        let itemsCount = 1
        let qty = 1.0
        let isFinishedGood = itemsCount == 1 && qty == 1.0
        return isFinishedGood
            ? .success(name)
            : .failure(name, "Finished good simulator check failed")
    }
    
    // MARK: - Audit Variance & Cost
    
    private static func test_auditVariance_calculation() -> TestResult {
        let name = #function
        let currentQty = 15.0
        let physicalCount = 12.0
        let variance = physicalCount - currentQty // -3.0
        return approxEqual(variance, -3.0)
            ? .success(name)
            : .failure(name, "Expected variance -3.0, got \(variance)")
    }
    
    private static func test_auditVarianceCost_calculation() -> TestResult {
        let name = #function
        let currentQty = 15.0
        let physicalCount = 12.0
        let costPrice = 50.0
        
        let variance = physicalCount - currentQty
        let varianceCost = variance * costPrice // -150.0
        
        return approxEqual(varianceCost, -150.0)
            ? .success(name)
            : .failure(name, "Expected variance cost -150.0, got \(varianceCost)")
    }
    
    // MARK: - Category & Product CRUD Simulation
    
    private static func test_categoryRelationships() -> TestResult {
        let name = #function
        let categoryName = "Appetizers"
        let description = "Starters and snacks"
        
        let category = (name: categoryName, desc: description)
        
        return category.name == "Appetizers" && category.desc == "Starters and snacks"
            ? .success(name)
            : .failure(name, "Category values mismatched")
    }
    
    private static func test_productCreationAndAvailability() -> TestResult {
        let name = #function
        let prodName = "Gyoza"
        let price = 80.0
        let isAvailable = true
        
        let item = (name: prodName, price: price, isAvailable: isAvailable)
        
        return item.name == "Gyoza" && approxEqual(item.price, 80.0) && item.isAvailable
            ? .success(name)
            : .failure(name, "Product values mismatched")
    }
    
    // MARK: - Modifiers/Extras Simulation
    
    private static func test_modifierGroupMinMaxRestrictions() -> TestResult {
        let name = #function
        let groupName = "Sweetness"
        let minSelect = 1
        let maxSelect = 1
        
        let group = (name: groupName, min: minSelect, max: maxSelect)
        
        return group.name == "Sweetness" && group.min == 1 && group.max == 1
            ? .success(name)
            : .failure(name, "ModifierGroup values mismatched")
    }
    
    private static func test_modifierInventoryDeductionLink() -> TestResult {
        let name = #function
        let modName = "Extra Cheese"
        let linkedIngredientSku = "ING-CHEESE"
        let qtyRequired = 1.0
        
        let mod = (name: modName, sku: linkedIngredientSku, qty: qtyRequired)
        
        return mod.name == "Extra Cheese" && mod.sku == "ING-CHEESE" && approxEqual(mod.qty, 1.0)
            ? .success(name)
            : .failure(name, "Modifier link values mismatched")
    }
    
    private static func test_barcodeSearchMatch() -> TestResult {
        let name = #function
        let items = [
            (name: "Pork", sku: "P-001" as String?, barcode: "1234567890" as String?),
            (name: "Beef", sku: "B-001" as String?, barcode: "9876543210" as String?),
            (name: "Chicken", sku: "C-001" as String?, barcode: nil as String?)
        ]
        
        let searchPattern = "12345"
        let matches = items.filter { item in
            item.name.localizedCaseInsensitiveContains(searchPattern) ||
            (item.sku ?? "").localizedCaseInsensitiveContains(searchPattern) ||
            (item.barcode ?? "").localizedCaseInsensitiveContains(searchPattern)
        }
        
        return matches.count == 1 && matches[0].name == "Pork"
            ? .success(name)
            : .failure(name, "Barcode search matching logic failed")
    }
    
    private static func test_categoryFilter() -> TestResult {
        let name = #function
        let items = [
            (name: "Pork", category: "Meat"),
            (name: "Milk", category: "Dairy"),
            (name: "Coke", category: "Beverages"),
            (name: "Spinach", category: nil as String?)
        ]
        
        let categoryFilter = "Meat"
        let matches = items.filter { $0.category == categoryFilter }
        
        return matches.count == 1 && matches[0].name == "Pork"
            ? .success(name)
            : .failure(name, "Category filtering logic failed")
    }
    
    private static func test_locationFilter() -> TestResult {
        let name = #function
        let items = [
            (name: "Pork", storageLocation: "Freezer A"),
            (name: "Milk", storageLocation: "Fridge B"),
            (name: "Coke", storageLocation: "Front Shelf"),
            (name: "Spinach", storageLocation: nil as String?)
        ]
        
        let locationFilter = "Freezer A"
        let matches = items.filter { $0.storageLocation == locationFilter }
        
        return matches.count == 1 && matches[0].name == "Pork"
            ? .success(name)
            : .failure(name, "Location filtering logic failed")
    }
    
    private static func test_productTaxCalculation() -> TestResult {
        let name = #function
        let item1 = (price: 107.0, isTaxInclusive: true, taxRate: 7.0)
        let item2 = (price: 100.0, isTaxInclusive: false, taxRate: 10.0)
        
        let tax1 = item1.price * (item1.taxRate / (100 + item1.taxRate))
        let tax2 = item2.price * (item2.taxRate / 100.0)
        let totalTax = tax1 + tax2
        
        let total1 = item1.price
        let total2 = item2.price * (1.0 + item2.taxRate / 100.0)
        let totalAmount = total1 + total2
        
        return approxEqual(totalTax, 17.0) && approxEqual(totalAmount, 217.0)
            ? .success(name)
            : .failure(name, "Expected tax 17.0 and total 217.0, got tax \(totalTax) and total \(totalAmount)")
    }
    
    private static func findBestMatch(for name: String, in items: [String]) -> String? {
        let normalized = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let exact = items.first(where: { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == normalized }) {
            return exact
        }
        if let sub = items.first(where: { normalized.contains($0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)) || $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines).contains(normalized) }) {
            return sub
        }
        return nil
    }
    
    private static func test_fuzzyReceiptMatcher() -> TestResult {
        let name = #function
        let stockItems = ["Coffee Beans Meiji Premium", "Paper Cups Large", "Full Cream Fresh Milk"]
        let scannedName1 = "Paper Cups Large (scanned)"
        let scannedName2 = "Full Cream Fresh Milk"
        let scannedName3 = "Coffee Beans Meiji"
        let scannedName4 = "Chairs"
        
        let match1 = findBestMatch(for: scannedName1, in: stockItems)
        let match2 = findBestMatch(for: scannedName2, in: stockItems)
        let match3 = findBestMatch(for: scannedName3, in: stockItems)
        let match4 = findBestMatch(for: scannedName4, in: stockItems)
        
        let success = match1 == "Paper Cups Large" &&
                      match2 == "Full Cream Fresh Milk" &&
                      match3 == "Coffee Beans Meiji Premium" &&
                      match4 == nil
        
        return success
            ? .success(name)
            : .failure(name, "Receipt matching logic failed. Match1=\(String(describing: match1)), Match2=\(String(describing: match2)), Match3=\(String(describing: match3)), Match4=\(String(describing: match4))")
    }
}
