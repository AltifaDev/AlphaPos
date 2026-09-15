import Foundation
import SwiftData
import SwiftUI

@Observable
@MainActor
final class EmployeeTimecardViewModel {
    var modelContext: ModelContext?

    // UI state
    var selectedEmployee: Employee?
    var showingScanner = false
    var scannerMode: EmployeeTimecardView.ScannerMode = .clockIn

    // Search & Filter state
    var employeeSearchQuery = ""
    var employeeFilterStatus = 0 // 0: All, 1: Clocked In, 2: Clocked Out

    var timecardSearchQuery = ""
    var timecardFilterStatus = 0 // 0: All, 1: Approved, 2: Pending
    var timecardFilterDate: Date? = nil

    var showRegisterSessionWarning = false
    var activeRegisterSessionForWarning: RegisterSession? = nil

    // Success feedback state
    var showSuccessFeedback = false
    var lastClockEvent: (employeeName: String, mode: EmployeeTimecardView.ScannerMode, time: Date)? = nil

    /// Grace window (minutes) before late / early-out flags apply.
    var shiftGraceMinutes: Int = ShiftAttendanceMatcher.defaultGraceMinutes

    init(modelContext: ModelContext? = nil) {
        self.modelContext = modelContext
    }

    func fetchActiveTimecard(for employee: Employee, in context: ModelContext? = nil) -> Timecard? {
        if let memoryCard = employee.timecards.first(where: { $0.clockOut == nil && !$0.isDeleted }) {
            return memoryCard
        }
        guard let ctx = context ?? modelContext else { return nil }

        let employeeId = employee.id
        var descriptor = FetchDescriptor<Timecard>(
            predicate: #Predicate<Timecard> { $0.employee?.id == employeeId && $0.clockOut == nil && !$0.isDeleted }
        )
        descriptor.fetchLimit = 1

        do {
            let cards = try ctx.fetch(descriptor)
            return cards.first
        } catch {
            return nil
        }
    }

    /// Local equivalent of Staff `fetchTodayActiveShift` — reads SwiftData `EmployeeShift`.
    func fetchTodayActiveShift(for employee: Employee, at date: Date = Date(), in context: ModelContext? = nil) -> EmployeeShift? {
        guard let ctx = context ?? modelContext else { return nil }

        let employeeId = employee.id
        let descriptor = FetchDescriptor<EmployeeShift>(
            predicate: #Predicate<EmployeeShift> {
                $0.employee?.id == employeeId && !$0.isDeleted
            },
            sortBy: [SortDescriptor(\.scheduledStart)]
        )
        let shifts = (try? ctx.fetch(descriptor)) ?? []
        return ShiftAttendanceMatcher.activeShift(from: shifts, at: date)
    }

    func handleScanResult(employee: Employee, success: Bool, confidence: Double, context: ModelContext? = nil) {
        if let context { self.modelContext = context }
        guard let modelContext = context ?? self.modelContext else {
            print("⚠️ [Attendance] handleScanResult aborted: modelContext is nil")
            return
        }
        guard success else {
            recordAttendanceAudit(employee: employee, action: scannerMode == .clockIn ? "attendance.face_scan_failed.clock_in" : "attendance.face_scan_failed.clock_out", details: "Face liveness or match verification failed", in: modelContext)
            showingScanner = false
            return
        }

        recordAttendanceAudit(
            employee: employee,
            action: scannerMode == .clockIn ? "attendance.face_scan_verified.clock_in" : "attendance.face_scan_verified.clock_out",
            details: "Employee face embedding matched after live head-turn challenge; median cosine similarity=\(String(format: "%.4f", confidence))",
            in: modelContext
        )

        let activeCard = fetchActiveTimecard(for: employee, in: modelContext)

        if scannerMode == .clockIn, activeCard != nil {
            recordAttendanceAudit(
                employee: employee,
                action: "attendance.duplicate_clock_in_blocked",
                details: "Clock-in was blocked because an active timecard already exists",
                in: modelContext
            )
            showingScanner = false
            return
        }

        if scannerMode == .clockIn {
            performClockIn(employee: employee, confidence: confidence, in: modelContext)
        } else if let card = activeCard {
            // Check if the employee has an active open register session
            if let userId = employee.user?.id {
                let descriptor = FetchDescriptor<RegisterSession>(
                    predicate: #Predicate<RegisterSession> { $0.openedByUserId == userId && $0.closedAt == nil && !$0.isDeleted }
                )
                if let sessions = try? modelContext.fetch(descriptor), let activeSession = sessions.first {
                    self.activeRegisterSessionForWarning = activeSession
                    self.showRegisterSessionWarning = true
                    self.showingScanner = false
                    return
                }
            }

            performClockOut(employee: employee, confidence: confidence, activeCard: card, in: modelContext)
        }
    }

    /// Writes an audit event without storing a face image or biometric template.
    private func recordAttendanceAudit(employee: Employee, action: String, details: String, in context: ModelContext? = nil) {
        guard let ctx = context ?? modelContext else { return }
        let log = AuditLog(employeeId: employee.id, actionType: action, details: details)
        ctx.insert(log)
        ctx.saveWithLogging(label: "attendance_audit")
        Task { await SyncEngine.shared.syncAll(modelContext: ctx) }
    }

    func forceClockOut(employee: Employee, confidence: Double, context: ModelContext? = nil) {
        let ctx = context ?? modelContext
        guard let ctx else { return }
        let activeCard = fetchActiveTimecard(for: employee, in: ctx)
        performClockOut(employee: employee, confidence: confidence, activeCard: activeCard, in: ctx)
        self.activeRegisterSessionForWarning = nil
        self.showRegisterSessionWarning = false
    }

    // MARK: - Clock In (Layer 1: bind shift)

    private func performClockIn(employee: Employee, confidence: Double, in modelContext: ModelContext) {
        let now = Date()
        let todayShift = fetchTodayActiveShift(for: employee, at: now, in: modelContext)
        let decision = ShiftAttendanceMatcher.clockInDecision(
            shift: todayShift,
            clockIn: now,
            graceMinutes: shiftGraceMinutes
        )

        let timecard = Timecard(
            employee: employee,
            shift: todayShift,
            clockIn: now,
            clockOut: nil,
            breakDurationMinutes: 0,
            overtimeMinutes: 0,
            status: decision.status,
            notes: decision.notes,
            clockInFaceConfidence: confidence,
            clockInSelfieUrl: nil
        )
        modelContext.insert(timecard)
        timecard.employee = employee
        if !employee.timecards.contains(where: { $0.id == timecard.id }) {
            employee.timecards.append(timecard)
        }
        guard modelContext.saveWithLogging(label: #function) else {
            // Do not report an attendance event as successful unless it is
            // durably present in SwiftData. A later observation refresh would
            // otherwise revert the optimistic relationship state.
            modelContext.rollback()
            showingScanner = false
            return
        }

        self.lastClockEvent = (
            employeeName: "\(employee.firstName) \(employee.lastName)",
            mode: .clockIn,
            time: now
        )
        self.showSuccessFeedback = true
        self.showingScanner = false

        let empName = "\(employee.firstName) \(employee.lastName)"
        SyncEngine.shared.alertStaffClockIn(name: empName)
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }

    // MARK: - Clock Out (Layer 2: punctuality + OT from schedule)

    private func performClockOut(employee: Employee, confidence: Double, activeCard: Timecard?, in modelContext: ModelContext) {
        guard let card = activeCard else { return }

        let clockOut = Date()
        card.clockOut = clockOut
        card.clockOutFaceConfidence = confidence
        card.clockOutSelfieUrl = nil
        card.updatedAt = Date()
        card.isSynced = false

        // Backfill shift link if iPad/legacy clock-in omitted it
        if card.shift == nil {
            card.shift = fetchTodayActiveShift(for: employee, at: card.clockIn, in: modelContext)
        }

        let decision = ShiftAttendanceMatcher.clockOutDecision(
            shift: card.shift,
            clockOut: clockOut,
            existingNotes: card.notes,
            graceMinutes: shiftGraceMinutes
        )
        card.overtimeMinutes = decision.overtimeMinutes
        card.notes = ShiftAttendanceMatcher.mergeNotes(card.notes, decision.notesSuffix)
        card.status = decision.status

        modelContext.saveWithLogging(label: #function)
        try? modelContext.save()

        self.lastClockEvent = (
            employeeName: "\(employee.firstName) \(employee.lastName)",
            mode: .clockOut,
            time: clockOut
        )
        self.showSuccessFeedback = true
        self.showingScanner = false

        let empName = "\(employee.firstName) \(employee.lastName)"
        let hoursWorked = clockOut.timeIntervalSince(card.clockIn) / 3600.0
        SyncEngine.shared.alertStaffClockOut(name: empName, hoursWorked: hoursWorked)

        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }
}
