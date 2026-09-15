import Foundation

enum PrepRecipeTests {
    static func runAll() -> [TestResult] {
        [unitCostUsesActualYield(), crossUnitComponentCost(), readableMassUnit(), readableVolumeUnit(), saleDoesNotExplodeComponents()]
    }
    private static func unitCostUsesActualYield() -> TestResult {
        let value=PrepRecipeMath.unitCost(componentCosts:[(2,3),(4,1)],actualYield:5)
        return result("prep unit cost uses actual yield", abs(value-2)<0.0001,
                      "expected 2, got \(value)")
    }
    private static func crossUnitComponentCost() -> TestResult {
        let value=PrepRecipeMath.componentCost(unitCost:395,quantity:280,quantityUnit:"g",inventoryUnit:"kg")
        return result("prep component cost converts grams to kilograms", abs(value-110.6)<0.0001,
                      "expected 110.6, got \(value)")
    }
    private static func readableMassUnit() -> TestResult {
        let value=PrepRecipeMath.displayQuantity(2300,unit:"g")
        return result("prep readable mass unit", value.0==2.3 && value.1=="kg",
                      "expected 2.3 kg, got \(value.0) \(value.1)")
    }
    private static func readableVolumeUnit() -> TestResult {
        let value=PrepRecipeMath.displayQuantity(1500,unit:"ml")
        return result("prep readable volume unit", value.0==1.5 && value.1=="L",
                      "expected 1.5 L, got \(value.0) \(value.1)")
    }
    private static func saleDoesNotExplodeComponents() -> TestResult {
        let deduction=PrepRecipeMath.saleDeduction(outputQuantityPerSale:230,saleCount:2)
        return result("prep sale deducts output once", deduction==460,
                      "sale must deduct 460g prepared sauce, not raw ingredients again")
    }

    private static func result(_ name: String, _ passed: Bool, _ message: String) -> TestResult {
        passed ? .success(name) : .failure(name, message)
    }
}
