// Promotion_updated.swift
// AlphaPos — Updated Promotion Model
//
// Changes from original:
// 1. Added @Relationship to PromotionBundleItem (cascade delete)
// 2. Added maxRedemptions, currentRedemptions, perCustomerLimit for usage control
// 3. Added rewardMenuItemId for Buy X Get Y where reward item differs from required item
// 4. Enhanced isEffective() to check redemption limits
// 5. Added incrementRedemption() helper

import Foundation
import SwiftData

@Model
final class Promotion {
    @Attribute(.unique) var id: UUID
    var title: String
    var promoDescription: String?
    var imageData: String? // Base64 representation of selected promotion image/video banner
    var mediaType: String = "image" // "image" or "video"
    var isActive: Bool
    var discountType: String = "none" // "none", "percentage", "fixed", "bundle_price", "buy_x_get_y", "buy_x_pay_y"
    var discountValue: Double = 0.0
    var minimumSpend: Double = 0.0
    var appliesToMenuItemId: String? // The item that triggers the promotion
    var rewardMenuItemId: String? // The item given as reward (if different from trigger item; nil = same item)
    var requiredQuantity: Int = 1
    var rewardQuantity: Int = 0
    var startsAt: Date?
    var endsAt: Date?

    // Usage Tracking — NEW
    var maxRedemptions: Int? // nil = unlimited total redemptions
    var currentRedemptions: Int = 0
    var perCustomerLimit: Int? // nil = unlimited per customer

    // Bundle Items — NEW
    @Relationship(deleteRule: .cascade, inverse: \PromotionBundleItem.promotion)
    var bundleItems: [PromotionBundleItem] = []

    // Offline-First Sync Metadata
    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date

    // M-2: Coupon Code support
    var couponCode: String?           // nil = auto-apply only; set = requires code entry
    var couponMaxRedemptions: Int?    // nil = unlimited; per-code redemption cap
    var couponExpiresAt: Date?        // nil = follows promotion end date

    init(
        id: UUID = UUID(),
        title: String,
        promoDescription: String? = nil,
        imageData: String? = nil,
        mediaType: String = "image",
        isActive: Bool = true,
        discountType: String = "none",
        discountValue: Double = 0.0,
        minimumSpend: Double = 0.0,
        appliesToMenuItemId: String? = nil,
        rewardMenuItemId: String? = nil,
        requiredQuantity: Int = 1,
        rewardQuantity: Int = 0,
        startsAt: Date? = nil,
        endsAt: Date? = nil,
        maxRedemptions: Int? = nil,
        currentRedemptions: Int = 0,
        perCustomerLimit: Int? = nil,
        isSynced: Bool = false,
        isDeleted: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.promoDescription = promoDescription
        self.imageData = imageData
        self.mediaType = mediaType
        self.isActive = isActive
        self.discountType = discountType
        self.discountValue = discountValue
        self.minimumSpend = minimumSpend
        self.appliesToMenuItemId = appliesToMenuItemId
        self.rewardMenuItemId = rewardMenuItemId
        self.requiredQuantity = requiredQuantity
        self.rewardQuantity = rewardQuantity
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.maxRedemptions = maxRedemptions
        self.currentRedemptions = currentRedemptions
        self.perCustomerLimit = perCustomerLimit
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
    }

    /// Check if promotion is currently effective (date range + active + not deleted + within redemption limits)
    func isEffective(at date: Date = Date()) -> Bool {
        guard isActive, !isDeleted else { return false }
        if let startsAt, date < startsAt { return false }
        if let endsAt, date > endsAt { return false }
        // Check global redemption cap
        if let max = maxRedemptions, currentRedemptions >= max { return false }
        return true
    }

    /// Check if a specific customer has exceeded their per-customer limit
    /// customerRedemptionCount should be fetched from OrderDiscount records for this customer + promotion
    func isWithinCustomerLimit(customerRedemptionCount: Int) -> Bool {
        guard let limit = perCustomerLimit else { return true }
        return customerRedemptionCount < limit
    }

    /// Calculate discount for percentage/fixed types
    func discountAmount(for subtotal: Double, at date: Date = Date()) -> Double {
        guard isEffective(at: date), subtotal >= minimumSpend, discountValue > 0 else { return 0 }

        switch discountType {
        case "percentage":
            return min(subtotal, subtotal * min(discountValue, 100.0) / 100.0)
        case "fixed":
            return min(subtotal, discountValue)
        default:
            return 0
        }
    }

    /// Increment the redemption counter after a successful checkout
    func incrementRedemption() {
        currentRedemptions += 1
        updatedAt = Date()
        isSynced = false
    }

    /// The effective reward item ID — falls back to appliesToMenuItemId if rewardMenuItemId is nil
    var effectiveRewardMenuItemId: String? {
        rewardMenuItemId ?? appliesToMenuItemId
    }
}
