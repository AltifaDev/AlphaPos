import Foundation
import SwiftData

@Model
final class Tip {
    @Attribute(.unique) var id: UUID
    var order: Order?
    var payment: Payment?
    var amount: Double
    var tipType: String // "manual", "percentage", "round_up"
    var employeeId: UUID?
    
    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date
    
    init(id: UUID = UUID(), order: Order? = nil, payment: Payment? = nil, amount: Double = 0.0, tipType: String = "manual", employeeId: UUID? = nil, isSynced: Bool = false, isDeleted: Bool = false, updatedAt: Date = Date()) {
        self.id = id
        self.order = order
        self.payment = payment
        self.amount = amount
        self.tipType = tipType
        self.employeeId = employeeId
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
    }
}

extension Tip: RemoteTipUploadable {}
