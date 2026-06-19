import Foundation
import SwiftData

@Model
final class TableSession {
    @Attribute(.unique) var id: UUID
    var sessionToken: String // Generated dynamically for customer mobile web access validation
    var startedAt: Date
    var endedAt: Date?
    var isActive: Bool
    var table: RestaurantTable?
    
    @Relationship(deleteRule: .nullify, inverse: \Order.tableSession)
    var orders: [Order] = []
    
    // Offline-First Sync Metadata
    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date
    
    var guestCount: Int = 2
    var cashierName: String = "Alex M."
    var queueNumber: String? = nil
    
    var totalAmount: Double {
        orders.filter { !$0.isDeleted && $0.status != "cancelled" }.reduce(0.0) { $0 + $1.total }
    }
    
    init(id: UUID = UUID(), sessionToken: String = UUID().uuidString, startedAt: Date = Date(), endedAt: Date? = nil, isActive: Bool = true, table: RestaurantTable? = nil, guestCount: Int = 2, cashierName: String = "Alex M.", queueNumber: String? = nil, isSynced: Bool = false, isDeleted: Bool = false, updatedAt: Date = Date()) {
        self.id = id
        self.sessionToken = sessionToken
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.isActive = isActive
        self.table = table
        self.guestCount = guestCount
        self.cashierName = cashierName
        self.queueNumber = queueNumber
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
    }
}
