// PromotionBundleItem.swift
// AlphaPos — Bundle Promotion Component Model
//
// Maps which MenuItems (and their quantities) compose a bundle promotion.
// Example: "Family Meal" bundle = 2x Fried Rice + 1x Soup + 1x Drink at ฿199

import Foundation
import SwiftData

@Model
final class PromotionBundleItem {
    @Attribute(.unique) var id: UUID
    var promotion: Promotion?
    var menuItem: MenuItem?
    var quantity: Int // How many of this item are included in the bundle
    var displayOrder: Int // UI ordering within the bundle

    // Offline-First Sync Metadata
    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        promotion: Promotion? = nil,
        menuItem: MenuItem? = nil,
        quantity: Int = 1,
        displayOrder: Int = 0,
        isSynced: Bool = false,
        isDeleted: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.promotion = promotion
        self.menuItem = menuItem
        self.quantity = quantity
        self.displayOrder = displayOrder
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
    }
}
