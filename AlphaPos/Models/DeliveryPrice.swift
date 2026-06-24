import Foundation
import SwiftData

@Model
final class DeliveryPrice {
    @Attribute(.unique) var id: UUID
    var brandName: String // "GrabFood", "LINE MAN", "ShopeeFood", "Foodpanda", "Robinhood"
    var price: Double

    var menuItem: MenuItem?

    // Offline-First Sync Metadata
    var isSynced: Bool = false
    var isDeleted: Bool = false
    var updatedAt: Date = Date()

    init(id: UUID = UUID(), brandName: String, price: Double, menuItem: MenuItem? = nil,
         isSynced: Bool = false, isDeleted: Bool = false, updatedAt: Date = Date()) {
        self.id = id
        self.brandName = brandName
        self.price = price
        self.menuItem = menuItem
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
    }
}
