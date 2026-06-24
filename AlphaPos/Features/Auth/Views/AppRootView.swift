import SwiftData
import SwiftUI

struct AppRootView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var lm: LocalizationManager
    @StateObject private var sessionManager = AppSessionManager()

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
                })
                .id(lm.reloadId)
                .transition(.opacity.combined(with: .move(edge: .bottom)))

            case .staffLock:
                StaffLockView(
                    onUnlock: { employee in
                        sessionManager.unlock(employee: employee, modelContext: modelContext)
                    },
                    onUseStoreAccount: {
                        sessionManager.unlockAsStoreOwner(modelContext: modelContext)
                    }
                )
                .id(lm.reloadId)
                .transition(.opacity)

            case .dashboard:
                MainDashboardView()
                    .id(lm.reloadId)
                    .environmentObject(sessionManager)
                    .transition(.opacity)
            }

            if lm.isReloading {
                LanguageReloadOverlayView(language: lm.currentLanguage)
                    .transition(.opacity)
                    .zIndex(999)
            }

            // ─── In-App Notification Banner ─────────────────────────────────
            // แสดง banner แจ้งเตือนที่ด้านบนจอเมื่อแอปเปิดอยู่
            // ไม่ใช้ Native Push — ทำงานโดยไม่ต้องการ Push Notifications capability
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
            // ────────────────────────────────────────────────────────────────
        }
        .environmentObject(sessionManager)
        .environmentObject(lm)
        .animation(.easeOut(duration: 0.12), value: sessionManager.route)
        .animation(.easeInOut(duration: 0.3), value: lm.isReloading)
        .task {
            await sessionManager.bootstrap(modelContext: modelContext)
        }
    }
}
