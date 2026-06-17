import Foundation
import SwiftData

@Model
final class RefundTransaction {
    @Attribute(.unique) var id: UUID
    var order: Order?
    var originalPayment: Payment?
    var refundAmount: Double
    var refundMethod: String // "cash", "original_tender", "store_credit"
    var reasonCode: String // "customer_request", "defective", "wrong_order", "overcharge"
    var reasonNotes: String?
    var refundedByEmployeeId: UUID?
    var approvedByEmployeeId: UUID?
    var status: String // "pending_approval", "completed", "rejected"
    
    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date
    
    init(id: UUID = UUID(), order: Order? = nil, originalPayment: Payment? = nil, refundAmount: Double = 0.0, refundMethod: String = "cash", reasonCode: String = "customer_request", reasonNotes: String? = nil, refundedByEmployeeId: UUID? = nil, approvedByEmployeeId: UUID? = nil, status: String = "completed", isSynced: Bool = false, isDeleted: Bool = false, updatedAt: Date = Date()) {
        self.id = id
        self.order = order
        self.originalPayment = originalPayment
        self.refundAmount = refundAmount
        self.refundMethod = refundMethod
        self.reasonCode = reasonCode
        self.reasonNotes = reasonNotes
        self.refundedByEmployeeId = refundedByEmployeeId
        self.approvedByEmployeeId = approvedByEmployeeId
        self.status = status
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
    }
}

extension RefundTransaction: RemoteRefundTransactionUploadable {}
