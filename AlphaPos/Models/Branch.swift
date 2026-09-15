import Foundation
import SwiftData

@Model
final class Branch {
    @Attribute(.unique) var id: UUID
    var name: String
    var location: String?
    var phone: String?
    /// Local end-of-business-day boundary. 04:00 means transactions from
    /// midnight through 03:59 belong to the preceding business date.
    var businessDayCutoffHour: Int = 4
    var timeZoneID: String = "Asia/Bangkok"
    
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
        businessDayCutoffHour: Int = 4,
        timeZoneID: String = "Asia/Bangkok",
        isSynced: Bool = false,
        isDeleted: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.location = location
        self.phone = phone
        self.businessDayCutoffHour = min(max(businessDayCutoffHour, 0), 23)
        self.timeZoneID = TimeZone(identifier: timeZoneID) == nil ? "Asia/Bangkok" : timeZoneID
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
    }
}
