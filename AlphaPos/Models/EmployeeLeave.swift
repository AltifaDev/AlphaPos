// EmployeeLeave.swift
// AlphaPos — M-5: Leave Management Model
//
// Leave types: sick, annual, personal, unpaid, maternity, paternity, other
// Status flow: pending → approved / rejected
// Deducted from payroll when status = "approved" and leaveType != "unpaid" (configurable)

import Foundation
import SwiftData

@Model
final class EmployeeLeave {
    @Attribute(.unique) var id: UUID
    var employee: Employee?

    var leaveType: String     // "sick", "annual", "personal", "unpaid", "maternity", "paternity", "other"
    var status: String        // "pending", "approved", "rejected", "cancelled"
    var startDate: Date
    var endDate: Date
    var totalDays: Double     // supports 0.5 half-day
    var reason: String?
    var approvedBy: String?   // manager name/id who approved
    var rejectionReason: String?
    var notes: String?

    // Payroll integration — set by PayrollDashboard when calculating monthly report
    var isPaidLeave: Bool     // false = unpaid deduction
    var deductedFromPayroll: Bool = false

    // Offline-First Sync Metadata
    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date
    var createdAt: Date

    init(
        id: UUID = UUID(),
        employee: Employee? = nil,
        leaveType: String = "sick",
        status: String = "pending",
        startDate: Date = Date(),
        endDate: Date = Date(),
        totalDays: Double = 1.0,
        reason: String? = nil,
        approvedBy: String? = nil,
        rejectionReason: String? = nil,
        notes: String? = nil,
        isPaidLeave: Bool = true,
        deductedFromPayroll: Bool = false,
        isSynced: Bool = false,
        isDeleted: Bool = false,
        updatedAt: Date = Date(),
        createdAt: Date = Date()
    ) {
        self.id = id
        self.employee = employee
        self.leaveType = leaveType
        self.status = status
        self.startDate = startDate
        self.endDate = endDate
        self.totalDays = totalDays
        self.reason = reason
        self.approvedBy = approvedBy
        self.rejectionReason = rejectionReason
        self.notes = notes
        self.isPaidLeave = isPaidLeave
        self.deductedFromPayroll = deductedFromPayroll
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
        self.createdAt = createdAt
    }

    // MARK: - Helpers

    var displayType: String {
        switch leaveType {
        case "sick":        return "leave_type_sick".t
        case "annual":      return "leave_type_annual".t
        case "personal":    return "leave_type_personal".t
        case "unpaid":      return "leave_type_unpaid".t
        case "maternity":   return "leave_type_maternity".t
        case "paternity":   return "leave_type_paternity".t
        default:            return "leave_type_other".t
        }
    }

    var statusColor: String {
        switch status {
        case "approved":   return "appTeal"
        case "rejected":   return "appRose"
        case "cancelled":  return "textTertiary"
        default:           return "appAmber"  // pending
        }
    }

    /// Calculate business days between startDate and endDate (Mon–Sat, excl. Sun)
    static func businessDays(from start: Date, to end: Date) -> Double {
        guard end >= start else { return 0 }
        var count: Double = 0
        var current = start
        let cal = Calendar.current
        while current <= end {
            let weekday = cal.component(.weekday, from: current)
            if weekday != 1 { count += 1 } // exclude Sunday (weekday == 1)
            current = cal.date(byAdding: .day, value: 1, to: current) ?? current.addingTimeInterval(86400)
        }
        return count
    }
}
