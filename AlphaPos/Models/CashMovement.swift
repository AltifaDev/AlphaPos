import Foundation
import SwiftData

@Model
final class CashMovement {
    @Attribute(.unique) var id: UUID
    var registerSession: RegisterSession?
    var movementType: String // "cash_in", "cash_out", "paid_in", "paid_out"
    var amount: Double
    var reason: String
    var performedByEmployeeId: UUID?
    
    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date
    
    init(id: UUID = UUID(), registerSession: RegisterSession? = nil, movementType: String, amount: Double, reason: String, performedByEmployeeId: UUID? = nil, isSynced: Bool = false, isDeleted: Bool = false, updatedAt: Date = Date()) {
        self.id = id
        self.registerSession = registerSession
        self.movementType = movementType
        self.amount = amount
        self.reason = reason
        self.performedByEmployeeId = performedByEmployeeId
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
    }
}

extension CashMovement: RemoteCashMovementUploadable {}
