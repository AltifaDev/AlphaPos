import Foundation
import SwiftData

@Model
final class Modifier {
    @Attribute(.unique) var id: UUID
    var modifierGroup: ModifierGroup?
    var name: String
    var extraPrice: Double
    var extraPriceDecimal: Decimal { Decimal(string: String(format: "%.2f", extraPrice)) ?? Decimal(extraPrice) }
    var isAvailable: Bool
    
    // Optional link to inventory (e.g. extra cheese reduces cheese inventory)
    var inventoryItemLink: InventoryItem?
    var quantityRequired: Double?
    
    // Offline-First Sync Metadata
    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date
    
    init(id: UUID = UUID(), modifierGroup: ModifierGroup? = nil, name: String, extraPrice: Double = 0.0, isAvailable: Bool = true, inventoryItemLink: InventoryItem? = nil, quantityRequired: Double? = nil, isSynced: Bool = false, isDeleted: Bool = false, updatedAt: Date = Date()) {
        self.id = id
        self.modifierGroup = modifierGroup
        self.name = name
        self.extraPrice = extraPrice
        self.isAvailable = isAvailable
        self.inventoryItemLink = inventoryItemLink
        self.quantityRequired = quantityRequired
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
    }
}
