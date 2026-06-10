import Foundation
import SwiftData

@Model
final class Supplier {
    @Attribute(.unique) var id: UUID
    var name: String
    var contactName: String?
    var phone: String?
    var email: String?
    var address: String?
    
    @Relationship(deleteRule: .nullify, inverse: \InventoryItem.supplier)
    var inventoryItems: [InventoryItem] = []
    
    // Offline-First Sync Metadata
    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date
    
    init(id: UUID = UUID(), name: String, contactName: String? = nil, phone: String? = nil, email: String? = nil, address: String? = nil, isSynced: Bool = false, isDeleted: Bool = false, updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.contactName = contactName
        self.phone = phone
        self.email = email
        self.address = address
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
    }
}
