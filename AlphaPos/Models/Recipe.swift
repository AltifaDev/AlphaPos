import Foundation
import SwiftData

@Model
final class Recipe {
    @Attribute(.unique) var id: UUID
    var menuItem: MenuItem?
    var inventoryItem: InventoryItem?
    var quantityRequired: Double // Quantity of inventory item consumed per menu item purchase
    var quantityUnit: String?
    var yieldPercentage: Double = 100
    
    // Offline-First Sync Metadata
    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date
    
    init(id: UUID = UUID(), menuItem: MenuItem? = nil, inventoryItem: InventoryItem? = nil, quantityRequired: Double, quantityUnit: String? = nil, yieldPercentage: Double = 100, isSynced: Bool = false, isDeleted: Bool = false, updatedAt: Date = Date()) {
        self.id = id
        self.menuItem = menuItem
        self.inventoryItem = inventoryItem
        self.quantityRequired = quantityRequired
        self.quantityUnit = quantityUnit
        self.yieldPercentage = min(max(yieldPercentage, 0.01), 100)
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
    }
}

enum InventoryRequirementCalculator {
    static func required(for recipe: Recipe, saleQuantity: Int) -> Double {
        guard saleQuantity > 0, let item = recipe.inventoryItem else { return 0 }
        let entered = max(recipe.quantityRequired, 0)
        let converted: Double
        if let from = UnitOfMeasure.parse(recipe.quantityUnit),
           let to = UnitOfMeasure.parse(item.unit),
           let value = UnitOfMeasure.convert(entered, from: from, to: to) {
            converted = value
        } else {
            converted = entered
        }
        return converted * Double(saleQuantity) / (min(max(recipe.yieldPercentage, 0.01), 100) / 100)
    }

    static func required(for modifier: Modifier, saleQuantity: Int) -> Double {
        max(modifier.quantityRequired ?? 0, 0) * Double(max(saleQuantity, 0))
    }
}

enum RecipeCostCalculator {
    /// Returns the standard cost for a recipe line after converting its entered
    /// unit into the inventory item's stored unit (for example 40 g → 0.04 kg).
    static func cost(for recipe: Recipe, saleQuantity: Int = 1) -> Double {
        guard let item = recipe.inventoryItem else { return 0 }
        return InventoryRequirementCalculator.required(for: recipe, saleQuantity: saleQuantity) * item.costPrice
    }

    static func cost(for recipes: [Recipe], saleQuantity: Int = 1) -> Double {
        recipes.lazy.filter { !$0.isDeleted }.reduce(0) { $0 + cost(for: $1, saleQuantity: saleQuantity) }
    }
}
