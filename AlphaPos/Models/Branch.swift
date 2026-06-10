import Foundation
import SwiftData

@Model
final class Branch {
    @Attribute(.unique) var id: UUID
    var name: String
    var location: String?
    var phone: String?
    
    @Relationship(deleteRule: .cascade, inverse: \InventoryItem.branch)
    var inventoryItems: [InventoryItem] = []
    
    @Relationship(deleteRule: .cascade, inverse: \PurchaseOrder.branch)
    var purchaseOrders: [PurchaseOrder] = []
    
    @Relationship(deleteRule: .cascade, inverse: \Order.branch)
    var orders: [Order] = []
    
    // Offline-First Sync Metadata
    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date
    
    init(
        id: UUID = UUID(),
        name: String,
        location: String? = nil,
        phone: String? = nil,
        isSynced: Bool = false,
        isDeleted: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.location = location
        self.phone = phone
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
    }
}
