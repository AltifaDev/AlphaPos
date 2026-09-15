import SwiftData
import SwiftUI

struct AppRootView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var lm: LocalizationManager
    @StateObject private var sessionManager = AppSessionManager()
    @ObservedObject private var deepLinkCoordinator = AuthDeepLinkCoordinator.shared
    @ObservedObject private var branchContext = BranchContext.shared
    @ObservedObject private var notificationStore = NotificationStore.shared

    var body: some View {
        ZStack {
            switch sessionManager.route {

            case .firstLaunch:
                FirstLaunchModeView(onModeSelected: { _ in
                    // mode ถูกบันทึกลง UserDefaults ใน FirstLaunchModeView แล้ว
                    // เพียงแค่ navigate ไปหน้า login
                    sessionManager.completeFirstLaunch()
                })
                .transition(.opacity.combined(with: .move(edge: .bottom)))

            case .splash:
                SplashScreenView(statusText: sessionManager.statusText)
                    .transition(.opacity)

            case .merchantLogin:
                MerchantAuthView(onAuthenticated: {
                    sessionManager.completeMerchantAuthentication(modelContext: modelContext)
                    let merchantId = MerchantAuthManager.shared.merchantId
                        ?? UserDefaults.standard.string(forKey: "active_merchant_id")
                        ?? ""
                    NotificationStore.shared.activateScope(merchantId: merchantId)
                    Task {
                        await SyncEngine.shared.bootstrapSync(modelContext: modelContext)
                    }
                })
                .id(lm.reloadId)
                .transition(.opacity.combined(with: .move(edge: .bottom)))

            case .ownerSetup:
                OwnerSetupView(
                    initialDisplayName: UserDefaults.standard.string(forKey: "logged_in_name") ?? "",
                    showMfaSoftPrompt: {
                        let mid = MerchantAuthManager.shared.merchantId
                            ?? UserDefaults.standard.string(forKey: "active_merchant_id")
                            ?? ""
                        return !MerchantOnboardingGate.isCompleted(.mfaSoftPrompt, for: mid)
                    }(),
                    onFinished: { displayName, skippedMfa in
                        sessionManager.completeOwnerSetup(
                            displayName: displayName,
                            modelContext: modelContext,
                            skippedMfa: skippedMfa
                        )
                        let merchantId = MerchantAuthManager.shared.merchantId
                            ?? UserDefaults.standard.string(forKey: "active_merchant_id")
                            ?? ""
                        NotificationStore.shared.activateScope(merchantId: merchantId)
                        Task {
                            await SyncEngine.shared.bootstrapSync(modelContext: modelContext)
                        }
                    }
                )
                .id(lm.reloadId)
                .transition(.opacity.combined(with: .move(edge: .bottom)))

            case .staffLock:
                StaffLockView(
                    onUnlock: { employee in
                        sessionManager.unlock(employee: employee, modelContext: modelContext)
                    },
                    onUseStoreAccount: {
                        let mid = MerchantAuthManager.shared.merchantId
                            ?? UserDefaults.standard.string(forKey: "active_merchant_id")
                            ?? ""
                        if MerchantOnboardingGate.canEnterDashboard(for: mid) {
                            sessionManager.unlockAsStoreOwner(modelContext: modelContext)
                        } else {
                            // Force mandatory owner setup instead of unlocking.
                            sessionManager.completeMerchantAuthentication(modelContext: modelContext)
                        }
                    }
                )
                .id(lm.reloadId)
                .transition(.opacity)

            case .dashboard:
                if TenantWorkspaceGuard.isAuthenticatedWorkspaceReady,
                   notificationStore.isInitialReconciliationComplete {
                    MainDashboardView()
                        .id(lm.reloadId)
                        .environmentObject(sessionManager)
                        .transition(.opacity)
                } else if TenantWorkspaceGuard.isAuthenticatedWorkspaceReady {
                    // Online bootstrap mutates the same SwiftData context used by
                    // LiveDashboardView.  Constructing its query-heavy view while
                    // reconciliation is still inserting/deleting rows can block
                    // the main actor or leave the dashboard holding invalidated
                    // model references.  Keep authentication successful, but
                    // delay dashboard materialization until the first sync has
                    // reached a stable local snapshot.
                    SplashScreenView(statusText: "preparing_workspace".t)
                } else {
                    SplashScreenView(statusText: "Tenant verification required")
                        .task {
                            sessionManager.signOutMerchant(modelContext: modelContext)
                        }
                }
            }

            if lm.isReloading {
                LanguageReloadOverlayView(language: lm.currentLanguage)
                    .transition(.opacity)
                    .zIndex(999)
            }

            if sessionManager.isPreparingWorkspace {
                WorkspaceTransitionOverlay(message: sessionManager.transitionText)
                    .transition(.opacity)
                    .zIndex(1001)
            }

            // ─── In-App Notification Banner ─────────────────────────────────
            // แสดง banner แจ้งเตือนที่ด้านบนจอเมื่อแอปเปิดอยู่
            // ไม่ใช้ Native Push — ทำงานโดยไม่ต้องการ Push Notifications capability
            if sessionManager.route == .dashboard {
                VStack {
                    InAppNotificationBanner(onTap: { tableNumber in
                        if let table = tableNumber {
                            NotificationCenter.default.post(
                                name: .openTableNotification,
                                object: nil,
                                userInfo: ["table_number": table]
                            )
                        }
                    })
                    Spacer()
                }
                .zIndex(998)
                .allowsHitTesting(true)
            }

            if sessionManager.route == .dashboard && branchContext.requiresSelection {
                RequiredBranchSelectionView()
                    .zIndex(2000)
            }
            // ────────────────────────────────────────────────────────────────
        }
        .environmentObject(sessionManager)
        .environmentObject(lm)
        .apColorScheme()
        .animation(.easeInOut(duration: 0.22), value: sessionManager.route)
        .animation(.easeInOut(duration: 0.3), value: lm.isReloading)
        .task {
            await sessionManager.bootstrap(modelContext: modelContext)
            _ = try? BranchContext.shared.bootstrap(in: modelContext)
            if TenantWorkspaceGuard.isAuthenticatedWorkspaceReady {
                let merchantId = MerchantAuthManager.shared.merchantId
                    ?? UserDefaults.standard.string(forKey: "active_merchant_id")
                    ?? ""
                NotificationStore.shared.activateScope(merchantId: merchantId)
            }
            await SyncEngine.shared.bootstrapSync(modelContext: modelContext)
        }
        .onOpenURL { url in
            if deepLinkCoordinator.handle(url) {
                sessionManager.presentMerchantLoginForDeepLink()
            }
        }
        .onChange(of: deepLinkCoordinator.pendingActionToken) { _, token in
            guard token != nil else { return }
            sessionManager.presentMerchantLoginForDeepLink()
        }
    }
}
