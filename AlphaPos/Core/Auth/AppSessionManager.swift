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
        case ownerSetup    // Mandatory owner profile + PIN before dashboard
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
    @Published private(set) var isPreparingWorkspace = false
    @Published private(set) var transitionText = "Preparing workspace"
    /// Last user interaction time for idle staff-session timeout.
    /// Not `@Published` — publishing on every touch re-renders MainDashboardView mid-tap
    /// and cancels Buttons / sidebar / chip interactions.
    private(set) var lastActivityAt = Date()

    private var hasBootstrapped = false
    private let minimumSplashTime: UInt64 = 250_000_000
    private var workspaceTransitionWatchdog: Task<Void, Never>?

    func touchActivity() {
        lastActivityAt = Date()
    }

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
            // ยกเว้นแผนออฟไลน์ที่ต้องบังคับโหมดออฟไลน์ตลอด
            if OfflineSyncModeController.isOfflineSubscriptionPlan {
                OfflineSyncModeController.enforcePlanPolicy(modelContext: modelContext)
            } else {
                UserDefaults.standard.set(false, forKey: "offline_sync_mode")
            }
        }
        // Offline plans always stay in offline sync mode.
        OfflineSyncModeController.enforcePlanPolicy(modelContext: modelContext)
        // ─────────────────────────────────────────────────────────────────

        route = .splash
        statusText = "Checking trusted device"

        // Recover an expiring/expired saved session before deciding to show login.
        // refreshTokenIfNeeded() falls back to the stored merchant credentials.
        if !UserDefaults.standard.bool(forKey: "offline_sync_mode"),
           MerchantAuthManager.shared.currentToken != nil {
            statusText = "Refreshing secure session"
            await MerchantAuthManager.shared.refreshTokenIfNeeded()
        }

        // Auth state is derived solely from Keychain JWT validity — not UserDefaults (tamper-resistant)
        let merchantReady = TenantWorkspaceGuard.isAuthenticatedWorkspaceReady

        if merchantReady {
            statusText = "Loading staff access"
            seedStaffIfNeeded(modelContext: modelContext)
        }

        try? await Task.sleep(nanoseconds: minimumSplashTime)

        if !merchantReady {
            route = .merchantLogin
            return
        }

        let merchantId = MerchantAuthManager.shared.merchantId
            ?? UserDefaults.standard.string(forKey: "active_merchant_id")
            ?? ""
        if !merchantId.isEmpty {
            MerchantOnboardingGate.bootstrapReturningOwner(merchantId: merchantId)
        }

        if !MerchantOnboardingGate.canEnterDashboard(for: merchantId) {
            // Returning / wiped device still needs owner PIN before any workspace.
            route = .ownerSetup
        } else if currentStaffSession == nil {
            route = .staffLock
        } else {
            route = .dashboard
        }
    }

    func completeMerchantAuthentication(modelContext: ModelContext) {
        let merchantId = MerchantAuthManager.shared.merchantId
            ?? UserDefaults.standard.string(forKey: "active_merchant_id")
            ?? ""

        if !merchantId.isEmpty {
            MerchantOnboardingGate.markCompleted(
                [.account, .emailVerified, .shopProfile, .planAndTerms, .tenantActivated, .mfaSoftPrompt, .dashboardReady],
                for: merchantId
            )
            if KeychainManager.shared.isOwnerPinConfigured() {
                MerchantOnboardingGate.markCompleted(.ownerPin, for: merchantId)
            }
        }

        // Phase 3: PIN is deferred — enter workspace immediately after tenant activate.
        // OwnerSetup still used when Staff Lock / open-shift requires a missing PIN.
        if MerchantOnboardingGate.canEnterDashboard(for: merchantId) {
            seedStaffIfNeeded(modelContext: modelContext)
            unlockAsStoreOwner(modelContext: modelContext)
        } else {
            route = .ownerSetup
        }
    }

    /// Called when OwnerSetupView finishes PIN (+ optional MFA soft step).
    func completeOwnerSetup(displayName: String, modelContext: ModelContext, skippedMfa: Bool) {
        let merchantId = MerchantAuthManager.shared.merchantId
            ?? UserDefaults.standard.string(forKey: "active_merchant_id")
            ?? ""
        if !displayName.isEmpty {
            UserDefaults.standard.set(displayName, forKey: "logged_in_name")
        }
        if !merchantId.isEmpty {
            MerchantOnboardingGate.markCompleted(.ownerPin, for: merchantId)
            MerchantOnboardingGate.markCompleted(.mfaSoftPrompt, for: merchantId)
            MerchantOnboardingGate.markCompleted(.dashboardReady, for: merchantId)
        }
        seedStaffIfNeeded(modelContext: modelContext)
        unlockAsStoreOwner(modelContext: modelContext)
    }

    /// เรียกจาก FirstLaunchModeView เมื่อ user เลือก mode แล้ว → ไปหน้า login
    func completeFirstLaunch() {
        route = .merchantLogin
    }

    func presentMerchantLoginForDeepLink() {
        hasBootstrapped = true
        route = .merchantLogin
    }

    func unlockAsStoreOwner(modelContext: ModelContext) {
        let merchantId = MerchantAuthManager.shared.merchantId
            ?? UserDefaults.standard.string(forKey: "active_merchant_id")
            ?? ""
        guard MerchantOnboardingGate.canEnterDashboard(for: merchantId) else {
            route = .ownerSetup
            return
        }

        let sessionId = UUID()
        let ownerId = UUID(uuidString: "00000000-0000-0000-0000-000000000000") ?? UUID()
        
        let displayName = UserDefaults.standard.string(forKey: "logged_in_name") ?? "Store Owner"
        
        currentStaffSession = StaffSession(
            id: sessionId,
            employeeId: ownerId,
            displayName: displayName,
            roleName: "Store Owner",
            permissions: PermissionService.permissions(forRoleName: "Store Owner"),
            startedAt: Date()
        )
        touchActivity()

        beginWorkspaceTransition()
        Task { @MainActor [weak self] in
            // First let SwiftUI commit the loading overlay. Constructing the
            // query-heavy dashboard in the same transaction starves animations
            // and triggers UIKit's system gesture gate timeout.
            await Task.yield()
            guard let self else { return }
            self.route = .dashboard
            // Authentication is complete once the session and route are set.
            // Never keep the blocking overlay tied to optional audit persistence.
            self.finishWorkspaceTransition()

            // Let the first dashboard frame render before touching SwiftData.
            // This avoids competing with query-heavy dashboard construction on
            // the same MainActor immediately after PIN/biometric success.
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard self.currentStaffSession?.id == sessionId else { return }

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
            modelContext.saveWithLogging(label: #function)
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
        touchActivity()

        beginWorkspaceTransition(for: displayName)
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            self.route = .dashboard
            self.finishWorkspaceTransition()
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard self.currentStaffSession?.id == sessionId else { return }

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
            modelContext.saveWithLogging(label: #function)
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
            modelContext.saveWithLogging(label: #function)
        }
        // Enterprise Alert: notify Notification Center about locked session
        if reason == "session_timeout", let session = currentStaffSession {
            SyncEngine.shared.alertStaffSessionLocked(name: session.displayName, reason: "Session timeout")
        }
        currentStaffSession = nil
        isPreparingWorkspace = false
        route = .staffLock
    }

    func signOutMerchant(modelContext: ModelContext? = nil) {
        // Signing out is an authentication action, not a data-erasure action.
        // Preserve the offline-first workspace so a transient auth problem or
        // owner sign-out can never destroy unsynced POS records.
        lockStaffSession(
            modelContext: nil,
            reason: "merchant_sign_out"
        )
        // NotificationStore is process-wide; clear it before credentials change
        // so no alert from the previous tenant survives on the login screen.
        NotificationStore.shared.deactivateScope()
        InAppNotificationManager.shared.clearAll()
        SyncEngine.shared.resetNotificationRuntimeState()
        // Keychain token cleared by MerchantAuthManager.logout() below
        MerchantAuthManager.shared.logout(removeLocalData: false)
        RememberStorePreferences.applyAfterLogout()
        route = .merchantLogin
    }

    private func beginWorkspaceTransition(for displayName: String? = nil) {
        transitionText = displayName.map {
            LocalizationManager.shared.t("opening_workspace_for", $0)
        } ?? "preparing_workspace".t
        isPreparingWorkspace = true
        workspaceTransitionWatchdog?.cancel()
        workspaceTransitionWatchdog = Task { @MainActor [weak self] in
            // Defensive recovery: no persistence or dashboard workload may leave
            // the full-screen input-blocking overlay visible indefinitely.
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            self?.isPreparingWorkspace = false
        }
    }

    private func finishWorkspaceTransition() {
        workspaceTransitionWatchdog?.cancel()
        workspaceTransitionWatchdog = nil
        Task { @MainActor [weak self] in
            // Give SwiftUI time to commit the first dashboard frame. The
            // overlay itself uses the system ProgressView animation, so no
            // custom loading animation is needed here.
            try? await Task.sleep(nanoseconds: 450_000_000)
            self?.isPreparingWorkspace = false
        }
    }

    func can(_ permission: AppPermission) -> Bool {
        currentStaffSession?.permissions.contains(permission) ?? false
    }

    func canAssignRole(_ role: Role?, to employeeID: UUID?) -> Bool {
        guard let session = currentStaffSession, can(.staffPermissionsManage), let role else { return false }
        guard employeeID != session.employeeId else { return false }
        return PermissionService.permissions(for: role).isSubset(of: session.permissions)
    }

    private func seedStaffIfNeeded(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<Employee>()
        let employees = (try? modelContext.fetch(descriptor)) ?? []
        guard employees.isEmpty else { return }
        RoleBootstrap.ensureDefaultRoles(modelContext: modelContext)
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
