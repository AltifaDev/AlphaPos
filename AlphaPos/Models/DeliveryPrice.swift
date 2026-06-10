import Foundation
import SwiftData

@Model
final class DeliveryPrice {
    @Attribute(.unique) var id: UUID
    var brandName: String // "GrabFood", "LINE MAN", "ShopeeFood", "Foodpanda", "Robinhood"
    var price: Double
    
    var menuItem: MenuItem?
    
    init(id: UUID = UUID(), brandName: String, price: Double, menuItem: MenuItem? = nil) {
        self.id = id
        self.brandName = brandName
        self.price = price
        self.menuItem = menuItem
    }
}
