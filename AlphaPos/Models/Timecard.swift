import Foundation
import SwiftData

@Model
final class Timecard {
    @Attribute(.unique) var id: UUID
    var employee: Employee?
    var shift: EmployeeShift? // Shift link
    var clockIn: Date
    var clockOut: Date?
    var breakDurationMinutes: Int
    var overtimeMinutes: Int
    var verifiedByUserId: UUID? // Reference to the manager user id who reviewed
    var status: String // "approved", "pending_audit", "rejected" -> approved automatically on matching face scan
    var notes: String?
    
    // Face verification details captured via iPad camera
    var clockInFaceConfidence: Double?
    var clockInSelfieUrl: String?
    var clockOutFaceConfidence: Double?
    var clockOutSelfieUrl: String?
    
    // Offline-First Sync Metadata
    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date
    
    init(id: UUID = UUID(), employee: Employee? = nil, shift: EmployeeShift? = nil, clockIn: Date = Date(), clockOut: Date? = nil, breakDurationMinutes: Int = 0, overtimeMinutes: Int = 0, verifiedByUserId: UUID? = nil, status: String = "approved", notes: String? = nil, clockInFaceConfidence: Double? = nil, clockInSelfieUrl: String? = nil, clockOutFaceConfidence: Double? = nil, clockOutSelfieUrl: String? = nil, isSynced: Bool = false, isDeleted: Bool = false, updatedAt: Date = Date()) {
        self.id = id
        self.employee = employee
        self.shift = shift
        self.clockIn = clockIn
        self.clockOut = clockOut
        self.breakDurationMinutes = breakDurationMinutes
        self.overtimeMinutes = overtimeMinutes
        self.verifiedByUserId = verifiedByUserId
        self.status = status
        self.notes = notes
        self.clockInFaceConfidence = clockInFaceConfidence
        self.clockInSelfieUrl = clockInSelfieUrl
        self.clockOutFaceConfidence = clockOutFaceConfidence
        self.clockOutSelfieUrl = clockOutSelfieUrl
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
    }
}
