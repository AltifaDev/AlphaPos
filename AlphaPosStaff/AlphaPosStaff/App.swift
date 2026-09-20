import SwiftUI
import UIKit
import UserNotifications

private enum StaffTextSize: String {
    case system, small, normal, large

    var dynamicTypeSize: DynamicTypeSize {
        switch self {
        case .system, .normal: return .large
        case .small: return .small
        case .large: return .accessibility1
        }
    }
}

private extension View {
    @ViewBuilder
    func staffTextSize(_ value: StaffTextSize) -> some View {
        if value == .system {
            self
        } else {
            self.dynamicTypeSize(value.dynamicTypeSize)
        }
    }
}

final class AlphaPosStaffAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // APNs registration starts only after pairing and explicit permission.
        return true
    }

    // ── APNs token received ────────────────────────────────────────────────────
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // Use the enhanced registrar that also stores employee_id
        NetworkService.shared.registerPushToken(deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        #if DEBUG
        print("APNs registration failed: \(error.localizedDescription)")
        #endif
    }

    // ── Remote notification received in background/foreground ─────────────────
    // This fires when a push arrives while the app is in the foreground OR
    // when the app is woken in the background with content-available: 1.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        handleIncomingPush(userInfo: userInfo)
        completionHandler(.newData)
    }

    // ── Shared push handler ───────────────────────────────────────────────────
    private func handleIncomingPush(userInfo: [AnyHashable: Any]) {
        let pushType = userInfo["type"] as? String ?? ""
        let prefs = NetworkService.PushNotificationPreferences.current

        // Respect per-category user preference
        guard prefs.shouldShow(for: pushType) else {
            #if DEBUG
            print("AppDelegate: Push suppressed by user preference: \(pushType)")
            #endif
            return
        }

        // When app is active → in-app banner (handled by NotificationManager via UNDelegate)
        // When app is background → system banner (already shown by iOS)
        // Here we only need to trigger a data refresh
        Task {
            await NetworkService.shared.refreshAll()
        }
    }
}

@main
struct AlphaPosStaffApp: App {
    @UIApplicationDelegateAdaptor(AlphaPosStaffAppDelegate.self) private var appDelegate
    @State private var loggedInEmployee: Employee? = nil
    @State private var isShowingSplash = true
    @AppStorage("app_text_size") private var appTextSize = StaffTextSize.system.rawValue

    private static func migrateRetiredSupabaseURLIfNeeded() {
        let key = "dynamic_supabase_url"
        guard let stored = UserDefaults.standard.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !stored.isEmpty,
              AppConfig.isInvalidSupabaseURL(stored) else {
            return
        }
        if let path = Bundle.main.path(forResource: "Config", ofType: "plist"),
           let dict = NSDictionary(contentsOfFile: path) as? [String: Any],
           let plistURL = (dict["SUPABASE_URL"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !plistURL.isEmpty {
            UserDefaults.standard.set(plistURL, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
    
    init() {
        Self.migrateRetiredSupabaseURLIfNeeded()
        UNUserNotificationCenter.current().delegate = NotificationManager.shared
        
        // Native URLCache setup for image caching (RAM 50MB, Disk 200MB)
        let imageCache = URLCache(
            memoryCapacity: 50 * 1024 * 1024,
            diskCapacity: 200 * 1024 * 1024,
            diskPath: "supabase_product_images"
        )
        URLCache.shared = imageCache

        // Initialize default app language if not set
        if UserDefaults.standard.string(forKey: "app_language") == nil {
            let defaultCode = LanguageManager.defaultLanguageCode()
            UserDefaults.standard.set(defaultCode, forKey: "app_language")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                if let _ = loggedInEmployee {
                    MainTabView(loggedInEmployee: $loggedInEmployee)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                } else {
                    LoginView(loggedInEmployee: $loggedInEmployee)
                        .transition(.opacity)
                }

                if isShowingSplash {
                    StaffSplashScreenView()
                        .transition(.opacity)
                        .zIndex(10_000)
                }
            }
            .staffTextSize(StaffTextSize(rawValue: appTextSize) ?? .system)
            .onAppear {
                // NOTE: DEBUG auto-login was removed. It created a fake Employee with a
                // random UUID that did not exist in Supabase, so server-side PIN
                // verification (verifyPin) in TimecardView always failed with
                // "PIN incorrect" even though the login screen was bypassed.
                // The app now always shows the real LoginView, so the logged-in
                // employee carries a real DB id and PIN verification works.

                if let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    let testURL = docsURL.appendingPathComponent("app_onappear.log")
                    let text = "App onAppear: loggedInEmployee = \(String(describing: loggedInEmployee))\n"
                    try? text.write(to: testURL, atomically: true, encoding: .utf8)
                }
            }
            .onChange(of: loggedInEmployee) { newEmp in
                if let emp = newEmp {
                    StaffSessionContext.setEmployee(id: emp.id, name: "\(emp.firstName) \(emp.lastName)")
                    Task {
                        let isClockedIn = (try? await NetworkService.shared.hasActiveTimecard(for: emp.id)) ?? false
                        await MainActor.run {
                            UserDefaults.standard.set(isClockedIn, forKey: "staff_is_clocked_in")
                        }
                    }
                } else {
                    StaffSessionContext.clearEmployee()
                    UserDefaults.standard.set(false, forKey: "staff_is_clocked_in")
                }
            }
            .overlay(alignment: .top) {
                EnhancedNotificationContainer()
            }
            .animation(.easeInOut(duration: 0.35), value: loggedInEmployee != nil)
            .animation(.easeOut(duration: 0.35), value: isShowingSplash)
            .apColorScheme()
            .task {
                guard isShowingSplash else { return }
                try? await Task.sleep(nanoseconds: 1_650_000_000)
                guard !Task.isCancelled else { return }
                isShowingSplash = false
            }
        }
    }
}
