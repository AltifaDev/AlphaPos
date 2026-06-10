import Foundation
import SwiftData

@Model
final class PurchaseOrderItem {
    @Attribute(.unique) var id: UUID
    var purchaseOrder: PurchaseOrder?
    var inventoryItem: InventoryItem?
    var quantityOrdered: Double
    var quantityReceived: Double
    var unitCost: Double
    
    // Offline-First Sync Metadata
    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date
    
    init(
        id: UUID = UUID(),
        purchaseOrder: PurchaseOrder? = nil,
        inventoryItem: InventoryItem? = nil,
        quantityOrdered: Double = 0.0,
        quantityReceived: Double = 0.0,
        unitCost: Double = 0.0,
        isSynced: Bool = false,
        isDeleted: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.purchaseOrder = purchaseOrder
        self.inventoryItem = inventoryItem
        self.quantityOrdered = quantityOrdered
        self.quantityReceived = quantityReceived
        self.unitCost = unitCost
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
    }
}
