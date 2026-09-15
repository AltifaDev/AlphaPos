import Foundation
import SwiftData

/// Append-only accounting fact used by dashboards and statutory reconciliation.
/// Corrections are new reversal/adjustment events; posted rows are never rewritten.
@Model
final class FinancialEvent {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var sourceEventKey: String
    var eventType: String
    var sourceType: String
    var sourceId: UUID
    var orderId: UUID?
    var branchId: UUID
    var registerSessionId: UUID?
    var businessDateKey: String
    var occurredAt: Date
    var recordedAt: Date
    var amount: Double
    var paymentMethod: String?
    var status: String
    var revisionOfEventId: UUID?
    var sourceDeviceId: String?
    var isLateAdjustment: Bool
    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date

    init(
        id: UUID = UUID(), sourceEventKey: String, eventType: String,
        sourceType: String, sourceId: UUID, orderId: UUID? = nil,
        branchId: UUID, registerSessionId: UUID? = nil,
        businessDateKey: String, occurredAt: Date, recordedAt: Date = Date(),
        amount: Double, paymentMethod: String? = nil, status: String = "posted",
        revisionOfEventId: UUID? = nil, sourceDeviceId: String? = nil,
        isLateAdjustment: Bool = false, isSynced: Bool = false,
        isDeleted: Bool = false, updatedAt: Date = Date()
    ) {
        self.id = id
        self.sourceEventKey = sourceEventKey
        self.eventType = eventType
        self.sourceType = sourceType
        self.sourceId = sourceId
        self.orderId = orderId
        self.branchId = branchId
        self.registerSessionId = registerSessionId
        self.businessDateKey = businessDateKey
        self.occurredAt = occurredAt
        self.recordedAt = recordedAt
        self.amount = amount
        self.paymentMethod = paymentMethod
        self.status = status
        self.revisionOfEventId = revisionOfEventId
        self.sourceDeviceId = sourceDeviceId
        self.isLateAdjustment = isLateAdjustment
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
    }
}

