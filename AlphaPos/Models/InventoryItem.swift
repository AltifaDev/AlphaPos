import Foundation
import SwiftData

@Model
final class InventoryItem {
    @Attribute(.unique) var id: UUID
    var name: String
    var sku: String?
    var unit: String // "kg", "g", "liter", "ml", "piece", "can"
    var currentQuantity: Double
    var reorderLevel: Double
    var costPrice: Double
    var supplier: Supplier?
    
    var branch: Branch?
    
    // High-Volume inventory optimizations
    var category: String?
    var storageLocation: String?
    var barcode: String?
    
    @Relationship(deleteRule: .cascade, inverse: \InventoryTransaction.item)
    var transactions: [InventoryTransaction] = []
    
    @Relationship(deleteRule: .cascade, inverse: \Recipe.inventoryItem)
    var recipeUsages: [Recipe] = []
    
    // Offline-First Sync Metadata
    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date
    
    init(
        id: UUID = UUID(),
        name: String,
        sku: String? = nil,
        unit: String,
        currentQuantity: Double = 0.0,
        reorderLevel: Double = 0.0,
        costPrice: Double = 0.0,
        supplier: Supplier? = nil,
        branch: Branch? = nil,
        category: String? = nil,
        storageLocation: String? = nil,
        barcode: String? = nil,
        isSynced: Bool = false,
        isDeleted: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.sku = sku
        self.unit = unit
        self.currentQuantity = currentQuantity
        self.reorderLevel = reorderLevel
        self.costPrice = costPrice
        self.supplier = supplier
        self.branch = branch
        self.category = category
        self.storageLocation = storageLocation
        self.barcode = barcode
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
    }
}
