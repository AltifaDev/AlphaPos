import SwiftUI
import UIKit
import UserNotifications

final class AlphaPosStaffAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { try? await NetworkService.shared.registerPushDevice(token: token) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        #if DEBUG
        print("APNs registration failed: \(error.localizedDescription)")
        #endif
    }
}

@main
struct AlphaPosStaffApp: App {
    @UIApplicationDelegateAdaptor(AlphaPosStaffAppDelegate.self) private var appDelegate
    @State private var loggedInEmployee: Employee? = nil
    
    init() {
        UNUserNotificationCenter.current().delegate = NotificationManager.shared
        NotificationManager.shared.requestAuthorization()
        
        // Native URLCache setup for image caching (RAM 50MB, Disk 200MB)
        let imageCache = URLCache(
            memoryCapacity: 50 * 1024 * 1024,
            diskCapacity: 200 * 1024 * 1024,
            diskPath: "supabase_product_images"
        )
        URLCache.shared = imageCache
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
            }
            .onAppear {
                #if DEBUG
                if loggedInEmployee == nil {
                    let somchai = Employee(
                        id: "11111111-1111-1111-1111-111111111111",
                        firstName: "Somchai",
                        lastName: "Suksabai",
                        phone: "081-234-5678",
                        nationalId: "1234567890123",
                        employmentType: "monthly",
                        payRate: 25000.0,
                        username: "somchai",
                        role: "Manager",
                        faceRegisteredAt: nil
                    )
                    loggedInEmployee = somchai
                    UserDefaults.standard.set(somchai.id, forKey: "logged_in_employee_id")
                }
                #endif
                
                if let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    let testURL = docsURL.appendingPathComponent("app_onappear.log")
                    let text = "App onAppear: loggedInEmployee = \(String(describing: loggedInEmployee))\n"
                    try? text.write(to: testURL, atomically: true, encoding: .utf8)
                }
            }
            .onChange(of: loggedInEmployee) { newEmp in
                if let emp = newEmp {
                    UserDefaults.standard.set(emp.id, forKey: "logged_in_employee_id")
                } else {
                    UserDefaults.standard.set("", forKey: "logged_in_employee_id")
                }
            }
            .overlay(alignment: .top) {
                EnhancedNotificationContainer()
            }
            .animation(.easeInOut(duration: 0.35), value: loggedInEmployee != nil)
            .apColorScheme()
        }
    }
}
