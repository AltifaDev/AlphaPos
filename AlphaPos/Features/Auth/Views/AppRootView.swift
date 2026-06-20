import SwiftData
import SwiftUI

struct AppRootView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var lm: LocalizationManager
    @StateObject private var sessionManager = AppSessionManager()

    var body: some View {
        ZStack {
            switch sessionManager.route {
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
        }
        .environmentObject(sessionManager)
        .environmentObject(lm)
        .animation(.easeInOut(duration: 0.25), value: sessionManager.route)
        .animation(.easeInOut(duration: 0.3), value: lm.isReloading)
        .task {
            await sessionManager.bootstrap(modelContext: modelContext)
        }
    }
}
