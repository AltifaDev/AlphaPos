import Foundation

enum PrepRecipeMath {
    static func componentCost(
        unitCost: Double,
        quantity: Double,
        quantityUnit: String,
        inventoryUnit: String
    ) -> Double {
        guard unitCost.isFinite, unitCost >= 0,
              quantity.isFinite, quantity >= 0 else { return 0 }
        let converted = UnitOfMeasure.parse(quantityUnit).flatMap { source in
            UnitOfMeasure.parse(inventoryUnit).flatMap { target in
                UnitOfMeasure.convert(quantity, from: source, to: target)
            }
        } ?? quantity
        return unitCost * converted
    }

    static func unitCost(componentCosts: [(unitCost: Double, quantity: Double)], actualYield: Double) -> Double {
        guard actualYield.isFinite, actualYield > 0 else { return 0 }
        let total = componentCosts.reduce(0.0) { result, value in
            guard value.unitCost.isFinite, value.quantity.isFinite,
                  value.unitCost >= 0, value.quantity >= 0 else { return result }
            return result + value.unitCost * value.quantity
        }
        return total / actualYield
    }

    static func displayQuantity(_ quantity: Double, unit: String) -> (Double, String) {
        let normalized = unit.lowercased()
        if normalized == "mg", quantity >= 1000 { return (quantity / 1000, "g") }
        if normalized == "g", quantity >= 1000 { return (quantity / 1000, "kg") }
        if normalized == "ml", quantity >= 1000 { return (quantity / 1000, "L") }
        return (quantity, unit)
    }

    /// A stocked prep output is consumed once at sale. Raw components were
    /// already consumed during batch production and must not be exploded again.
    static func saleDeduction(outputQuantityPerSale: Double, saleCount: Int) -> Double {
        max(outputQuantityPerSale, 0) * Double(max(saleCount, 0))
    }
}
