import Foundation
import SwiftData

@Model
final class OrderItem {
    @Attribute(.unique) var id: UUID
    var order: Order?
    var menuItem: MenuItem?
    var quantity: Int
    var unitPrice: Double
    var subtotal: Double
    var notes: String?
    var status: String // "cooking", "served", "cancelled" -> starts as cooking for kitchen
    
    @Relationship(deleteRule: .cascade, inverse: \OrderItemModifier.orderItem)
    var modifiers: [OrderItemModifier] = []
    
    // Offline-First Sync Metadata
    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date
    
    init(id: UUID = UUID(), order: Order? = nil, menuItem: MenuItem? = nil, quantity: Int = 1, unitPrice: Double = 0.0, notes: String? = nil, status: String = "cooking", isSynced: Bool = false, isDeleted: Bool = false, updatedAt: Date = Date()) {
        self.id = id
        self.order = order
        self.menuItem = menuItem
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.subtotal = Double(quantity) * unitPrice
        self.notes = notes
        self.status = status
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
    }
}
