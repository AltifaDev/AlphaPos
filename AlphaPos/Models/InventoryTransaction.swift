import Foundation
import SwiftData

@Model
final class InventoryTransaction {
    @Attribute(.unique) var id: UUID
    var item: InventoryItem?
    var transactionType: String // "receive", "waste", "adjust", "sell"
    var quantity: Double
    var costPrice: Double?
    var referenceId: UUID? // Maps to OrderItem ID or Supplier invoice
    var notes: String?
    var branch: Branch?
    
    // Offline-First Sync Metadata
    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date
    
    init(id: UUID = UUID(), item: InventoryItem? = nil, transactionType: String, quantity: Double, costPrice: Double? = nil, referenceId: UUID? = nil, notes: String? = nil, branch: Branch? = nil, isSynced: Bool = false, isDeleted: Bool = false, updatedAt: Date = Date()) {
        self.id = id
        self.item = item
        self.transactionType = transactionType
        self.quantity = quantity
        self.costPrice = costPrice
        self.referenceId = referenceId
        self.notes = notes
        self.branch = branch
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
    }
}
