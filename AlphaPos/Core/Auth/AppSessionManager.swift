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
        case firstLaunch   // ถามผู้ใช้ครั้งแรกว่าออฟไลน์หรือออนไลน์
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

        // ── Migrate offline_sync_mode default ──────────────────────────────
        // ตรวจว่าผ่าน first launch wizard แล้วหรือยัง
        // ถ้ายัง → แสดง firstLaunch เพื่อให้เลือก online/offline
        // ถ้าผ่านแล้วแต่ไม่เคย set offline_mode → reset เป็น false (online) ป้องกัน legacy bug
        let hasCompletedFirstLaunch = UserDefaults.standard.bool(forKey: "has_completed_first_launch")
        let userDidSetOfflineMode = UserDefaults.standard.bool(forKey: "offline_mode_user_set")
        if !hasCompletedFirstLaunch {
            // Install ใหม่ — ไปหน้าเลือก mode ก่อนเสมอ (แม้ JWT ยังหลือหรือไม่)
            route = .firstLaunch
            return
        }
        if !userDidSetOfflineMode {
            // ผ่าน first launch แต่ flag เก่าค้าง → reset เป็น online (legacy migration)
            UserDefaults.standard.set(false, forKey: "offline_sync_mode")
        }
        // ─────────────────────────────────────────────────────────────────

        route = .splash
        statusText = "Checking trusted device"

        // Auth state is derived solely from Keychain JWT validity — not UserDefaults (tamper-resistant)
        let merchantReady = MerchantAuthManager.shared.isAuthenticated

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
        // Auth state persisted in Keychain by MerchantAuthManager — no UserDefaults needed
        seedStaffIfNeeded(modelContext: modelContext)
        unlockAsStoreOwner(modelContext: modelContext)
    }

    /// เรียกจาก FirstLaunchModeView เมื่อ user เลือก mode แล้ว → ไปหน้า login
    func completeFirstLaunch() {
        route = .merchantLogin
    }

    func unlockAsStoreOwner(modelContext: ModelContext) {
        let sessionId = UUID()
        let ownerId = UUID(uuidString: "00000000-0000-0000-0000-000000000000") ?? UUID()
        
        let displayName = UserDefaults.standard.string(forKey: "logged_in_name") ?? "Store Owner"
        
        currentStaffSession = StaffSession(
            id: sessionId,
            employeeId: ownerId,
            displayName: displayName,
            roleName: "Store Owner",
            permissions: PermissionService.permissions(forRoleName: "Store Manager"),
            startedAt: Date()
        )

        // Navigation is the critical path. Persist the audit/session on the next
        // main-actor turn so SwiftUI can render the dashboard immediately.
        route = .dashboard
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            let deviceId = self.ensureCurrentDevice(modelContext: modelContext).id
            modelContext.insert(StaffSessionRecord(
                id: sessionId,
                deviceId: deviceId,
                employeeId: ownerId,
                roleName: "Store Owner"
            ))
            modelContext.insert(AuditLog(
                employeeId: ownerId,
                actionType: "store_owner_unlock",
                details: "\(displayName) unlocked this register using merchant account"
            ))
            try? modelContext.save()
        }
    }

    func unlock(employee: Employee, modelContext: ModelContext) {
        let fullName = "\(employee.firstName) \(employee.lastName)".trimmingCharacters(in: .whitespacesAndNewlines)
        let role = employee.user?.role
        let roleName = role?.name ?? "Staff"
        let displayName = fullName.isEmpty ? employee.user?.username ?? "Staff" : fullName
        let employeeId = employee.id
        let sessionId = UUID()

        currentStaffSession = StaffSession(
            id: sessionId,
            employeeId: employeeId,
            displayName: displayName,
            roleName: roleName,
            permissions: PermissionService.permissions(for: role),
            startedAt: Date()
        )

        route = .dashboard
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            let deviceId = self.ensureCurrentDevice(modelContext: modelContext).id
            modelContext.insert(StaffSessionRecord(
                id: sessionId,
                deviceId: deviceId,
                employeeId: employeeId,
                roleName: roleName
            ))
            modelContext.insert(AuditLog(
                employeeId: employeeId,
                actionType: "staff_unlock",
                details: "\(displayName) unlocked this register"
            ))
            try? modelContext.save()
        }
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
        // Keychain token cleared by MerchantAuthManager.logout() below
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
