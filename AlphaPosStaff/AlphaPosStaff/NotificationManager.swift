import Foundation
import UserNotifications

@objc final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    
    private override init() {
        super.init()
    }
    
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            #if DEBUG
            if granted {
                print("NotificationManager: Permission granted")
            } else if let error = error {
                print("NotificationManager: Permission error: \(error.localizedDescription)")
            }
            #endif
        }
    }
    
    func triggerNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = UNNotificationSound.default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            #if DEBUG
            if let error = error {
                print("NotificationManager: Failed to add notification: \(error.localizedDescription)")
            }
            #endif
        }
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show banner, play sound, and update badge even in foreground
        completionHandler([.banner, .list, .sound, .badge])
    }
}
