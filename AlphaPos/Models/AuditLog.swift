import Foundation
import SwiftData

@Model
final class AuditLog {
    @Attribute(.unique) var id: UUID
    var employeeId: UUID?
    var actionType: String // "item_void", "refund", "price_override", "discount_applied"
    var details: String?
    var originalValue: Double?
    var newValue: Double?
    var createdAt: Date
    
    // Offline-First Sync Metadata
    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date
    
    init(
        id: UUID = UUID(),
        employeeId: UUID? = nil,
        actionType: String,
        details: String? = nil,
        originalValue: Double? = nil,
        newValue: Double? = nil,
        createdAt: Date = Date(),
        isSynced: Bool = false,
        isDeleted: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.employeeId = employeeId
        self.actionType = actionType
        self.details = details
        self.originalValue = originalValue
        self.newValue = newValue
        self.createdAt = createdAt
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
    }
}

extension AuditLog: RemoteAuditLogUploadable {}
