import Foundation
import SwiftData

@Model
final class Payment {
    @Attribute(.unique) var id: UUID
    var order: Order?
    var paymentMethod: String // "cash", "credit_card", "qr_promptpay", "true_money"
    var amount: Double
    var transactionReference: String?
    var status: String // "completed", "refunded", "failed"
    var paidAt: Date
    var tipAmount: Double
    
    // Offline-First Sync Metadata
    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date
    
    init(id: UUID = UUID(), order: Order? = nil, paymentMethod: String, amount: Double, transactionReference: String? = nil, status: String = "completed", paidAt: Date = Date(), tipAmount: Double = 0.0, isSynced: Bool = false, isDeleted: Bool = false, updatedAt: Date = Date()) {
        self.id = id
        self.order = order
        self.paymentMethod = paymentMethod
        self.amount = amount
        self.transactionReference = transactionReference
        self.status = status
        self.paidAt = paidAt
        self.tipAmount = tipAmount
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
    }
}
