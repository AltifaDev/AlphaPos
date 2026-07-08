import Foundation
import SwiftData

@Model
final class LoyaltyTransaction {
    @Attribute(.unique) var id: UUID
    var customer: Customer?
    var order: Order?
    var transactionType: String // "earn", "redeem", "adjust", "expire"
    var points: Int
    var pointsBalanceAfter: Int
    var transactionDescription: String?

    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date

    // M-4: Loyalty Point Expiry
    var expiresAt: Date?          // nil = never expires; set = points expire on this date
    var earnedAt: Date            // วันที่ได้รับ points (used by expiry scheduler)

    init(id: UUID = UUID(), customer: Customer? = nil, order: Order? = nil, transactionType: String = "earn", points: Int = 0, pointsBalanceAfter: Int = 0, transactionDescription: String? = nil, expiresAt: Date? = nil, earnedAt: Date = Date(), isSynced: Bool = false, isDeleted: Bool = false, updatedAt: Date = Date()) {
        self.id = id
        self.customer = customer
        self.order = order
        self.transactionType = transactionType
        self.points = points
        self.pointsBalanceAfter = pointsBalanceAfter
        self.transactionDescription = transactionDescription
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
        self.expiresAt = expiresAt
        self.earnedAt = earnedAt
    }
}

extension LoyaltyTransaction: RemoteLoyaltyTransactionUploadable {}
