import Foundation
import SwiftData

/// A recipe prepared ahead of sale (pasta sauce, salad dressing, soup base).
/// Its output is a real InventoryItem. Raw materials are consumed only when a
/// batch is produced; menu sales consume the output item and never explode the
/// raw-material recipe again.
@Model
final class PrepRecipe {
    @Attribute(.unique) var id: UUID
    var name: String
    var outputItem: InventoryItem?
    var expectedOutputQuantity: Double
    var outputUnit: String
    var instructions: String?
    var isActive: Bool
    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \PrepRecipeComponent.prepRecipe)
    var components: [PrepRecipeComponent] = []

    init(id: UUID = UUID(), name: String, outputItem: InventoryItem?,
         expectedOutputQuantity: Double, outputUnit: String,
         instructions: String? = nil, isActive: Bool = true,
         isSynced: Bool = false, isDeleted: Bool = false, updatedAt: Date = Date()) {
        self.id = id; self.name = name; self.outputItem = outputItem
        self.expectedOutputQuantity = expectedOutputQuantity; self.outputUnit = outputUnit
        self.instructions = instructions; self.isActive = isActive
        self.isSynced = isSynced; self.isDeleted = isDeleted; self.updatedAt = updatedAt
    }

    var unitCost: Double {
        PrepRecipeMath.unitCost(
            componentCosts: components.filter { !$0.isDeleted }.map {
                guard let ingredient = $0.ingredient else {
                    return (unitCost: 0, quantity: 0)
                }
                return (
                    unitCost: 1,
                    quantity: PrepRecipeMath.componentCost(
                        unitCost: ingredient.costPrice,
                        quantity: $0.quantity,
                        quantityUnit: $0.quantityUnit,
                        inventoryUnit: ingredient.unit
                    )
                )
            }, actualYield: expectedOutputQuantity
        )
    }
}

@Model
final class PrepRecipeComponent {
    @Attribute(.unique) var id: UUID
    var prepRecipe: PrepRecipe?
    var ingredient: InventoryItem?
    var quantity: Double
    var quantityUnit: String
    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date

    init(id: UUID = UUID(), prepRecipe: PrepRecipe?, ingredient: InventoryItem?,
         quantity: Double, quantityUnit: String,
         isSynced: Bool = false, isDeleted: Bool = false, updatedAt: Date = Date()) {
        self.id = id; self.prepRecipe = prepRecipe; self.ingredient = ingredient
        self.quantity = quantity; self.quantityUnit = quantityUnit
        self.isSynced = isSynced; self.isDeleted = isDeleted; self.updatedAt = updatedAt
    }
}

@Model
final class PrepProductionBatch {
    @Attribute(.unique) var id: UUID
    var prepRecipe: PrepRecipe?
    var branch: Branch?
    var batchCount: Double
    var actualOutputQuantity: Double
    var lotNumber: String?
    var producedAt: Date
    var producedByEmployeeId: UUID?
    var notes: String?
    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date

    init(id: UUID = UUID(), prepRecipe: PrepRecipe?, branch: Branch?, batchCount: Double,
         actualOutputQuantity: Double, lotNumber: String? = nil, producedAt: Date = Date(),
         producedByEmployeeId: UUID? = nil, notes: String? = nil,
         isSynced: Bool = false, isDeleted: Bool = false, updatedAt: Date = Date()) {
        self.id = id; self.prepRecipe = prepRecipe; self.branch = branch
        self.batchCount = batchCount; self.actualOutputQuantity = actualOutputQuantity
        self.lotNumber = lotNumber; self.producedAt = producedAt
        self.producedByEmployeeId = producedByEmployeeId; self.notes = notes
        self.isSynced = isSynced; self.isDeleted = isDeleted; self.updatedAt = updatedAt
    }
}
