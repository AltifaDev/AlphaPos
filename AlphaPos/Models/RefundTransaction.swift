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
    /// Immutable financial event time. Reporting must never use `updatedAt`,
    /// because synchronization/approval edits can move a refund to another day.
    var createdAt: Date = Date.distantPast
    var businessDateKey: String = ""
    var registerSessionId: UUID?
    
    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date
    
    init(id: UUID = UUID(), order: Order? = nil, originalPayment: Payment? = nil, refundAmount: Double = 0.0, refundMethod: String = "cash", reasonCode: String = "customer_request", reasonNotes: String? = nil, refundedByEmployeeId: UUID? = nil, approvedByEmployeeId: UUID? = nil, status: String = "completed", createdAt: Date = Date(), businessDateKey: String = "", registerSessionId: UUID? = nil, isSynced: Bool = false, isDeleted: Bool = false, updatedAt: Date = Date()) {
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
        self.createdAt = createdAt
        self.businessDateKey = businessDateKey
        self.registerSessionId = registerSessionId
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
    }
}

extension RefundTransaction: RemoteRefundTransactionUploadable {
    /// Compatibility fallback for local rows created before `createdAt` was
    /// introduced. The server already had this column; old local-only rows use
    /// their last known update time until they are synchronized.
    var financialEventAt: Date { createdAt == .distantPast ? updatedAt : createdAt }
}
