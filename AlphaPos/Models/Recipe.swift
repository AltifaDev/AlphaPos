import Foundation
import SwiftData

@Model
final class Recipe {
    @Attribute(.unique) var id: UUID
    var menuItem: MenuItem?
    var inventoryItem: InventoryItem?
    var quantityRequired: Double // Quantity of inventory item consumed per menu item purchase
    
    // Offline-First Sync Metadata
    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date
    
    init(id: UUID = UUID(), menuItem: MenuItem? = nil, inventoryItem: InventoryItem? = nil, quantityRequired: Double, isSynced: Bool = false, isDeleted: Bool = false, updatedAt: Date = Date()) {
        self.id = id
        self.menuItem = menuItem
        self.inventoryItem = inventoryItem
        self.quantityRequired = quantityRequired
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
    }
}
