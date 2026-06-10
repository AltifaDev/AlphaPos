import Foundation
import SwiftData

@Model
final class RestaurantTable {
    @Attribute(.unique) var id: UUID
    var tableNumber: String
    var capacity: Int
    var status: String // "vacant", "occupied", "reserved", "cleaning"
    var qrCodeIdentifier: String?
    
    // Floor plan positioning (for drag & drop layout)
    var positionX: Double = 0
    var positionY: Double = 0
    var floor: Int? = 1
    
    // Self-referential relationship for table combining/splitting
    var joinedParent: RestaurantTable?
    
    @Relationship(deleteRule: .nullify, inverse: \RestaurantTable.joinedParent)
    var joinedChildren: [RestaurantTable] = []
    
    @Relationship(deleteRule: .cascade, inverse: \TableSession.table)
    var sessions: [TableSession] = []
    
    // Offline-First Sync Metadata
    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date
    
    init(id: UUID = UUID(), tableNumber: String, capacity: Int, status: String = "vacant", qrCodeIdentifier: String? = nil, positionX: Double = 0, positionY: Double = 0, floor: Int? = 1, isSynced: Bool = false, isDeleted: Bool = false, updatedAt: Date = Date()) {
        self.id = id
        self.tableNumber = tableNumber
        self.capacity = capacity
        self.status = status
        self.qrCodeIdentifier = qrCodeIdentifier
        self.positionX = positionX
        self.positionY = positionY
        self.floor = floor
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
    }
}
