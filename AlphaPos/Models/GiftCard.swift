import Foundation
import SwiftData

@Model
final class GiftCard {
    @Attribute(.unique) var id: UUID
    var cardNumber: String
    var balance: Double
    var initialValue: Double
    var customer: Customer?
    var status: String // "active", "exhausted", "expired", "disabled"
    var expiresAt: Date?
    
    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date
    
    init(id: UUID = UUID(), cardNumber: String = "", balance: Double = 0.0, initialValue: Double = 0.0, customer: Customer? = nil, status: String = "active", expiresAt: Date? = nil, isSynced: Bool = false, isDeleted: Bool = false, updatedAt: Date = Date()) {
        self.id = id
        self.cardNumber = cardNumber
        self.balance = balance
        self.initialValue = initialValue
        self.customer = customer
        self.status = status
        self.expiresAt = expiresAt
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
    }
}

extension GiftCard: RemoteGiftCardUploadable {}
