import Foundation
import SwiftData

@Model
final class RegisterSession {
    @Attribute(.unique) var id: UUID
    var openedByUserId: UUID // Staff User ID
    var closedByUserId: UUID?
    var openedAt: Date
    var closedAt: Date?
    /// Immutable retail business date assigned when the shift opens.
    var businessDateKey: String = ""
    var openingCash: Double
    var expectedClosingCash: Double
    var actualClosingCash: Double
    var cashDiscrepancy: Double // Actual Closing Cash - Expected Closing Cash
    var notes: String?
    var branch: Branch
    
    // Offline-First Sync Metadata
    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date
    
    init(id: UUID = UUID(), openedByUserId: UUID, closedByUserId: UUID? = nil, openedAt: Date = Date(), closedAt: Date? = nil, businessDateKey: String = "", openingCash: Double = 0.0, expectedClosingCash: Double = 0.0, actualClosingCash: Double = 0.0, cashDiscrepancy: Double = 0.0, notes: String? = nil, branch: Branch, isSynced: Bool = false, isDeleted: Bool = false, updatedAt: Date = Date()) {
        self.id = id
        self.openedByUserId = openedByUserId
        self.closedByUserId = closedByUserId
        self.openedAt = openedAt
        self.closedAt = closedAt
        self.businessDateKey = businessDateKey.isEmpty
            ? BusinessDayContext.key(for: openedAt, cutoffHour: branch.businessDayCutoffHour, timeZoneID: branch.timeZoneID)
            : businessDateKey
        self.openingCash = openingCash
        self.expectedClosingCash = expectedClosingCash
        self.actualClosingCash = actualClosingCash
        self.cashDiscrepancy = cashDiscrepancy
        self.notes = notes
        self.branch = branch
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
    }
}
