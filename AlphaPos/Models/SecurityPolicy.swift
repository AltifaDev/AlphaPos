import Foundation
import SwiftData

@Model
final class SecurityPolicy {
    @Attribute(.unique) var id: UUID
    var passcodeMinLength: Int
    var passcodeMaxAttempts: Int
    var lockoutMinutes: Int
    var staffSessionTimeoutMinutes: Int
    var requireManagerOverrideForRefund: Bool
    var requireManagerOverrideForVoid: Bool
    /// Require manager PIN before manual No-Sale cash drawer open.
    var requireManagerOverrideForNoSale: Bool = true
    /// Require manager PIN before hardware verification that kicks the cash drawer.
    var requireManagerOverrideForDrawerTest: Bool = true
    /// Require camera/face verification before staff clock-in and clock-out.
    var requireFaceScan: Bool = true

    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        passcodeMinLength: Int = 4,
        passcodeMaxAttempts: Int = 5,
        lockoutMinutes: Int = 5,
        staffSessionTimeoutMinutes: Int = 15,
        requireManagerOverrideForRefund: Bool = true,
        requireManagerOverrideForVoid: Bool = true,
        requireManagerOverrideForNoSale: Bool = true,
        requireManagerOverrideForDrawerTest: Bool = true,
        requireFaceScan: Bool = true,
        isSynced: Bool = false,
        isDeleted: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.passcodeMinLength = passcodeMinLength
        self.passcodeMaxAttempts = passcodeMaxAttempts
        self.lockoutMinutes = lockoutMinutes
        self.staffSessionTimeoutMinutes = staffSessionTimeoutMinutes
        self.requireManagerOverrideForRefund = requireManagerOverrideForRefund
        self.requireManagerOverrideForVoid = requireManagerOverrideForVoid
        self.requireManagerOverrideForNoSale = requireManagerOverrideForNoSale
        self.requireManagerOverrideForDrawerTest = requireManagerOverrideForDrawerTest
        self.requireFaceScan = requireFaceScan
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
    }
}
