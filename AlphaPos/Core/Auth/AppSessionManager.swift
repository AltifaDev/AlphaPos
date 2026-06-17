import Combine
import Foundation
import SwiftData
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class AppSessionManager: ObservableObject {
    enum Route: Equatable {
        case splash
        case merchantLogin
        case staffLock
        case dashboard
    }

    struct StaffSession: Equatable {
        let id: UUID
        let employeeId: UUID
        let displayName: String
        let roleName: String
        let permissions: Set<AppPermission>
        let startedAt: Date
    }

    @Published private(set) var route: Route = .splash
    @Published private(set) var statusText = "Starting secure workspace"
    @Published private(set) var currentStaffSession: StaffSession?

    private var hasBootstrapped = false
    private let minimumSplashTime: UInt64 = 750_000_000

    func bootstrap(modelContext: ModelContext, force: Bool = false) async {
        guard force || !hasBootstrapped else { return }
        hasBootstrapped = true
        route = .splash
        statusText = "Checking trusted device"

        let merchantReady = MerchantAuthManager.shared.isAuthenticated || UserDefaults.standard.bool(forKey: "is_logged_in")

        if merchantReady {
            statusText = "Loading staff access"
            seedStaffIfNeeded(modelContext: modelContext)
        }

        try? await Task.sleep(nanoseconds: minimumSplashTime)

        if !merchantReady {
            route = .merchantLogin
        } else if currentStaffSession == nil {
            route = .staffLock
        } else {
            route = .dashboard
        }
    }

    func completeMerchantAuthentication(modelContext: ModelContext) {
        UserDefaults.standard.set(true, forKey: "is_logged_in")
        currentStaffSession = nil
        seedStaffIfNeeded(modelContext: modelContext)
        route = .staffLock
    }

    func unlock(employee: Employee, modelContext: ModelContext) {
        let fullName = "\(employee.firstName) \(employee.lastName)".trimmingCharacters(in: .whitespacesAndNewlines)
        let role = employee.user?.role
        let sessionId = UUID()
        let deviceId = ensureCurrentDevice(modelContext: modelContext).id

        currentStaffSession = StaffSession(
            id: sessionId,
            employeeId: employee.id,
            displayName: fullName.isEmpty ? employee.user?.username ?? "Staff" : fullName,
            roleName: role?.name ?? "Staff",
            permissions: PermissionService.permissions(for: role),
            startedAt: Date()
        )

        modelContext.insert(StaffSessionRecord(
            id: sessionId,
            deviceId: deviceId,
            employeeId: employee.id,
            roleName: role?.name ?? "Staff"
        ))
        modelContext.insert(AuditLog(
            employeeId: employee.id,
            actionType: "staff_unlock",
            details: "\(fullName.isEmpty ? employee.user?.username ?? "Staff" : fullName) unlocked this register"
        ))
        try? modelContext.save()
        route = .dashboard
    }

    func lockStaffSession(modelContext: ModelContext? = nil, reason: String = "manual_lock") {
        if let modelContext, let session = currentStaffSession {
            let sessionId = session.id
            let descriptor = FetchDescriptor<StaffSessionRecord>(
                predicate: #Predicate<StaffSessionRecord> { $0.id == sessionId }
            )
            if let record = (try? modelContext.fetch(descriptor))?.first {
                record.endedAt = Date()
                record.endedReason = reason
                record.isSynced = false
                record.updatedAt = Date()
            }
            modelContext.insert(AuditLog(
                employeeId: session.employeeId,
                actionType: "staff_lock",
                details: "\(session.displayName) locked this register (\(reason))"
            ))
            try? modelContext.save()
        }
        currentStaffSession = nil
        route = .staffLock
    }

    func signOutMerchant(modelContext: ModelContext? = nil) {
        lockStaffSession(modelContext: modelContext, reason: "merchant_sign_out")
        UserDefaults.standard.set(false, forKey: "is_logged_in")
        MerchantAuthManager.shared.logout()
        route = .merchantLogin
    }

    func can(_ permission: AppPermission) -> Bool {
        currentStaffSession?.permissions.contains(permission) ?? false
    }

    private func seedStaffIfNeeded(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<Employee>()
        let employees = (try? modelContext.fetch(descriptor)) ?? []
        guard employees.isEmpty else { return }
        SampleDataSeeder.seedRolesAndEmployeesIfEmpty(modelContext: modelContext)
    }

    @discardableResult
    private func ensureCurrentDevice(modelContext: ModelContext) -> MerchantDevice {
        let key = "alphapos_current_device_id"
        if let rawId = UserDefaults.standard.string(forKey: key),
           let id = UUID(uuidString: rawId) {
            let descriptor = FetchDescriptor<MerchantDevice>(
                predicate: #Predicate<MerchantDevice> { $0.id == id }
            )
            if let device = (try? modelContext.fetch(descriptor))?.first {
                device.lastSeenAt = Date()
                device.updatedAt = Date()
                device.isSynced = false
                return device
            }
        }

        let newDevice = MerchantDevice(
            deviceName: Self.defaultDeviceName,
            deviceFingerprintHash: SecurityHelper.sha256(UUID().uuidString)
        )
        UserDefaults.standard.set(newDevice.id.uuidString.lowercased(), forKey: key)
        modelContext.insert(newDevice)
        return newDevice
    }

    private static var defaultDeviceName: String {
        #if os(iOS)
        return UIDevice.current.name
        #elseif os(macOS)
        return Host.current().localizedName ?? "AlphaPos Register"
        #else
        return "AlphaPos Register"
        #endif
    }
}
