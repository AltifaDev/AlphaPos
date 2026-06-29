import Foundation
import SwiftData

@Model
final class MerchantDevice: Identifiable {
    @Attribute(.unique) var id: UUID
    var deviceName: String
    var deviceType: String
    var branchId: UUID?
    var deviceFingerprintHash: String?
    var isTrusted: Bool
    var lastSeenAt: Date?
    var createdAt: Date

    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        deviceName: String,
        deviceType: String = "pos_register",
        branchId: UUID? = nil,
        deviceFingerprintHash: String? = nil,
        isTrusted: Bool = true,
        lastSeenAt: Date? = Date(),
        createdAt: Date = Date(),
        isSynced: Bool = false,
        isDeleted: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.deviceName = deviceName
        self.deviceType = deviceType
        self.branchId = branchId
        self.deviceFingerprintHash = deviceFingerprintHash
        self.isTrusted = isTrusted
        self.lastSeenAt = lastSeenAt
        self.createdAt = createdAt
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
    }
}
