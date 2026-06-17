import Foundation
import SwiftData

@Model
final class StaffSessionRecord {
    @Attribute(.unique) var id: UUID
    var deviceId: UUID?
    var employeeId: UUID?
    var roleName: String?
    var startedAt: Date
    var endedAt: Date?
    var endedReason: String?

    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        deviceId: UUID? = nil,
        employeeId: UUID? = nil,
        roleName: String? = nil,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        endedReason: String? = nil,
        isSynced: Bool = false,
        isDeleted: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.deviceId = deviceId
        self.employeeId = employeeId
        self.roleName = roleName
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.endedReason = endedReason
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
    }
}
