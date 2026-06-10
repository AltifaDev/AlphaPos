import Foundation
import SwiftData

@Model
final class OrderItemModifier {
    @Attribute(.unique) var id: UUID
    var orderItem: OrderItem?
    var modifier: Modifier?
    var price: Double
    
    // Offline-First Sync Metadata
    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date
    
    init(id: UUID = UUID(), orderItem: OrderItem? = nil, modifier: Modifier? = nil, price: Double = 0.0, isSynced: Bool = false, isDeleted: Bool = false, updatedAt: Date = Date()) {
        self.id = id
        self.orderItem = orderItem
        self.modifier = modifier
        self.price = price
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
    }
}
