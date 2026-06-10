import Foundation
import SwiftData

@Model
final class PurchaseOrder {
    @Attribute(.unique) var id: UUID
    var poNumber: String
    var supplier: Supplier?
    var branch: Branch?
    var status: String // "draft", "sent", "received", "cancelled"
    var orderDate: Date
    var deliveryDate: Date?
    var notes: String?
    
    @Relationship(deleteRule: .cascade, inverse: \PurchaseOrderItem.purchaseOrder)
    var items: [PurchaseOrderItem] = []
    
    // Offline-First Sync Metadata
    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date
    
    init(
        id: UUID = UUID(),
        poNumber: String,
        supplier: Supplier? = nil,
        branch: Branch? = nil,
        status: String = "draft",
        orderDate: Date = Date(),
        deliveryDate: Date? = nil,
        notes: String? = nil,
        isSynced: Bool = false,
        isDeleted: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.poNumber = poNumber
        self.supplier = supplier
        self.branch = branch
        self.status = status
        self.orderDate = orderDate
        self.deliveryDate = deliveryDate
        self.notes = notes
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
    }
}
