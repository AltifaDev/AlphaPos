import Foundation
import SwiftData

@Model
final class OrderDiscount {
    @Attribute(.unique) var id: UUID
    var order: Order?
    var promotion: Promotion?
    var discountType: String // "percentage", "fixed", "item_level"
    var discountValue: Double
    var discountAmount: Double // actual amount deducted
    var reason: String?
    var appliedByEmployeeId: UUID?
    
    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date
    
    init(id: UUID = UUID(), order: Order? = nil, promotion: Promotion? = nil, discountType: String = "fixed", discountValue: Double = 0.0, discountAmount: Double = 0.0, reason: String? = nil, appliedByEmployeeId: UUID? = nil, isSynced: Bool = false, isDeleted: Bool = false, updatedAt: Date = Date()) {
        self.id = id
        self.order = order
        self.promotion = promotion
        self.discountType = discountType
        self.discountValue = discountValue
        self.discountAmount = discountAmount
        self.reason = reason
        self.appliedByEmployeeId = appliedByEmployeeId
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
    }
}

extension OrderDiscount: RemoteOrderDiscountUploadable {}
