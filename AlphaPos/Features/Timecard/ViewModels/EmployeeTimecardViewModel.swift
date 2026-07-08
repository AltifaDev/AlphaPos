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

    init(modelContext: ModelContext? = nil) {
        self.modelContext = modelContext
    }

    func fetchActiveTimecard(for employee: Employee) -> Timecard? {
        guard let modelContext = modelContext else { return nil }

        let employeeId = employee.id
        var descriptor = FetchDescriptor<Timecard>(
            predicate: #Predicate<Timecard> { $0.employee?.id == employeeId && $0.clockOut == nil }
        )
        descriptor.fetchLimit = 1

        do {
            let cards = try modelContext.fetch(descriptor)
            return cards.first
        } catch {
            return nil
        }
    }

    func handleScanResult(employee: Employee, success: Bool, confidence: Double) {
        guard let modelContext = modelContext else { return }

        let activeCard = fetchActiveTimecard(for: employee)

        if scannerMode == .clockIn {
            // Clock-in processing
            let timecard = Timecard(
                employee: employee,
                clockIn: Date(),
                clockOut: nil,
                breakDurationMinutes: 0,
                status: "pending_audit",
                clockInFaceConfidence: confidence,
                clockInSelfieUrl: nil
            )
            modelContext.insert(timecard)

            modelContext.saveWithLogging(label: #function)
            showingScanner = false

            let empName = "\(employee.firstName) \(employee.lastName)"
            SyncEngine.shared.alertStaffClockIn(name: empName)
            Task {
                await SyncEngine.shared.syncAll(modelContext: modelContext)
            }
        } else if let card = activeCard {
            // Check if the employee has an active open register session
            if let userId = employee.user?.id {
                let descriptor = FetchDescriptor<RegisterSession>(
                    predicate: #Predicate<RegisterSession> { $0.openedByUserId == userId && $0.closedAt == nil && !$0.isDeleted }
                )
                if let sessions = try? modelContext.fetch(descriptor), let activeSession = sessions.first {
                    // We have an active register session! Show warning instead of immediately clocking out
                    self.activeRegisterSessionForWarning = activeSession
                    self.showRegisterSessionWarning = true
                    self.showingScanner = false
                    return
                }
            }

            performClockOut(employee: employee, confidence: confidence, activeCard: card)
        }
    }

    func forceClockOut(employee: Employee, confidence: Double) {
        let activeCard = fetchActiveTimecard(for: employee)
        performClockOut(employee: employee, confidence: confidence, activeCard: activeCard)
        self.activeRegisterSessionForWarning = nil
        self.showRegisterSessionWarning = false
    }

    private func performClockOut(employee: Employee, confidence: Double, activeCard: Timecard?) {
        guard let modelContext = modelContext else { return }
        if let card = activeCard {
            card.clockOut = Date()
            card.clockOutFaceConfidence = confidence
            card.clockOutSelfieUrl = nil
            card.status = "pending_audit"
            card.updatedAt = Date()
            card.isSynced = false

            if let shift = card.shift {
                let duration = card.clockOut!.timeIntervalSince(card.clockIn) / 60.0
                let scheduledDuration = shift.scheduledEnd.timeIntervalSince(shift.scheduledStart) / 60.0
                if duration > scheduledDuration {
                    card.overtimeMinutes = Int(duration - scheduledDuration)
                }
            }
        }

        modelContext.saveWithLogging(label: #function)
        showingScanner = false

        let empName = "\(employee.firstName) \(employee.lastName)"
        if let card = activeCard, let clockOut = card.clockOut {
            let hoursWorked = clockOut.timeIntervalSince(card.clockIn) / 3600.0
            SyncEngine.shared.alertStaffClockOut(name: empName, hoursWorked: hoursWorked)
        }

        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }

    func seedSampleEmployees() {
        guard let modelContext = modelContext else { return }

        let managerRole = Role(name: "Manager", roleDescription: "Store manager")
        let baristaRole = Role(name: "Barista", roleDescription: "Coffee specialist")
        modelContext.insert(managerRole)
        modelContext.insert(baristaRole)

        // Fixed UUIDs — must match SampleDataSeeder constants so FK references stay valid after re-seed
        let seedEmp1Id  = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let seedEmp2Id  = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let seedUser1Id = UUID(uuidString: "11111111-1111-1111-1111-111111112001")!
        let seedUser2Id = UUID(uuidString: "11111111-1111-1111-1111-111111112002")!
        let user1 = User(id: seedUser1Id, username: "somchai", email: "somchai@alphapos.com", passwordHash: SecurityHelper.sha256("password"), pinCodeHash: SecurityHelper.sha256("1234"), role: managerRole, isSynced: false, isDeleted: false, updatedAt: Date())
        let user2 = User(id: seedUser2Id, username: "somsri", email: "somsri@alphapos.com", passwordHash: SecurityHelper.sha256("password"), pinCodeHash: SecurityHelper.sha256("5678"), role: baristaRole, isSynced: false, isDeleted: false, updatedAt: Date())
        modelContext.insert(user1)
        modelContext.insert(user2)

        let emp1 = Employee(id: seedEmp1Id, user: user1, firstName: "Somchai", lastName: "Suksabai", phone: "081-234-5678", nationalId: "1234567890123", employmentType: "monthly", payRate: 25000.0, isSynced: false, isDeleted: false, updatedAt: Date())
        let emp2 = Employee(id: seedEmp2Id, user: user2, firstName: "Somsri", lastName: "Jaidee", phone: "089-876-5432", nationalId: "9876543210987", employmentType: "hourly", payRate: 75.0, isSynced: false, isDeleted: false, updatedAt: Date())

        // Mock Reference face vectors
        emp1.faceEmbeddingData = Data("mock_embedding_1".utf8)
        emp1.faceRegisteredAt = Date()
        emp2.faceEmbeddingData = Data("mock_embedding_2".utf8)
        emp2.faceRegisteredAt = Date()

        modelContext.insert(emp1)
        modelContext.insert(emp2)

        // Seed mock scheduled shifts for the current week
        let calendar = Calendar.current
        let today = Date()
        for i in 0..<5 {
            if let start = calendar.date(byAdding: .day, value: i - 2, to: today) {
                let scheduledStart = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: start)!
                let scheduledEnd = calendar.date(bySettingHour: 17, minute: 0, second: 0, of: start)!

                let shift1 = EmployeeShift(employee: emp1, scheduledStart: scheduledStart, scheduledEnd: scheduledEnd, role: "Manager")
                let shift2 = EmployeeShift(employee: emp2, scheduledStart: scheduledStart, scheduledEnd: scheduledEnd, role: "Barista")

                modelContext.insert(shift1)
                modelContext.insert(shift2)
            }
        }

        modelContext.saveWithLogging(label: #function)
    }
}
