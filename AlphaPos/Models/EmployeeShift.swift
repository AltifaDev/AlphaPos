import Foundation
import SwiftData

@Model
final class EmployeeShift {
    @Attribute(.unique) var id: UUID
    var employee: Employee?
    var scheduledStart: Date
    var scheduledEnd: Date
    var role: String? // Role for this specific shift, e.g. "cashier", "cook", "barista"
    var notes: String?
    
    @Relationship(deleteRule: .nullify, inverse: \Timecard.shift)
    var timecards: [Timecard] = []
    
    // Offline-First Sync Metadata
    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date
    
    init(id: UUID = UUID(), employee: Employee? = nil, scheduledStart: Date, scheduledEnd: Date, role: String? = nil, notes: String? = nil, isSynced: Bool = false, isDeleted: Bool = false, updatedAt: Date = Date()) {
        self.id = id
        self.employee = employee
        self.scheduledStart = scheduledStart
        self.scheduledEnd = scheduledEnd
        self.role = role
        self.notes = notes
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
    }
}
