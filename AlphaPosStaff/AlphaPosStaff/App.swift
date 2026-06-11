import SwiftUI

@main
struct AlphaPosStaffApp: App {
    @State private var loggedInEmployee: Employee? = nil
    
    init() {
        UNUserNotificationCenter.current().delegate = NotificationManager.shared
        NotificationManager.shared.requestAuthorization()
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
            .overlay(alignment: .top) {
                InAppNotificationContainer()
            }
            .animation(.easeInOut(duration: 0.35), value: loggedInEmployee != nil)
            .apColorScheme()
        }
    }
}
