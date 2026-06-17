import Foundation
import UserNotifications
import UIKit

// MARK: - Central Notification Router
// Single entry point for ALL notifications in the app.
// Decides whether to show In-App banner or iOS system notification based on app state.
// Never fires both simultaneously.

@objc final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    
    // Time-based deduplication: key → timestamp of last fire
    @ObservationIgnored
    private var recentKeys: [String: Date] = [:]
    private let deduplicationWindow: TimeInterval = 30.0 // seconds
    private let maxRecentKeys = 200
    
    private override init() {
        super.init()
    }
    
    // MARK: - Setup
    
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
    
    // MARK: - Single Entry Point
    
    /// The ONLY function any caller should use to trigger a notification.
    /// This router decides the delivery channel based on app state.
    ///
    /// - Parameters:
    ///   - title: Notification title
    ///   - body: Notification body text
    ///   - type: NotificationType for styling/sound decisions
    ///   - deduplicationKey: Unique key to prevent duplicate fires within 30s window.
    ///                       If nil, no deduplication is performed.
    func notify(title: String, body: String, type: NotificationType = .system, deduplicationKey: String? = nil) {
        // 1. Deduplication check
        if let key = deduplicationKey {
            let now = Date()
            if let lastFired = recentKeys[key], now.timeIntervalSince(lastFired) < deduplicationWindow {
                #if DEBUG
                print("NotificationManager [DEDUP]: Skipped '\(key)' — fired \(String(format: "%.1f", now.timeIntervalSince(lastFired)))s ago")
                #endif
                return
            }
            recentKeys[key] = now
            pruneRecentKeys()
        }
        
        // 2. Route based on app state
        if Thread.isMainThread {
            routeNotification(title: title, body: body, type: type)
        } else {
            DispatchQueue.main.async { [self] in
                routeNotification(title: title, body: body, type: type)
            }
        }
    }
    
    // MARK: - Private Routing
    
    private func routeNotification(title: String, body: String, type: NotificationType) {
        let appState = UIApplication.shared.applicationState
        
        if appState == .active {
            // ✅ FOREGROUND: In-App banner ONLY — no iOS system notification
            #if DEBUG
            print("NotificationManager [ROUTE]: Foreground → In-App banner: \(title)")
            #endif
            EnhancedNotificationManager.shared.enqueue(title: title, body: body, type: type)
            
        } else {
            // ✅ BACKGROUND: iOS system notification ONLY — no in-app banner
            #if DEBUG
            print("NotificationManager [ROUTE]: Background → iOS notification: \(title)")
            #endif
            fireSystemNotification(title: title, body: body)
        }
    }
    
    // MARK: - iOS System Notification (Background only)
    
    private func fireSystemNotification(title: String, body: String) {
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
        // If this delegate fires while the app is active, it means a system notification
        // was somehow scheduled. Suppress it completely — the In-App banner handles everything.
        DispatchQueue.main.async {
            if UIApplication.shared.applicationState == .active {
                // Suppress everything in foreground — In-App banner is already showing
                completionHandler([])
            } else {
                // Background: show native banner, sound, and badge
                completionHandler([.banner, .sound, .badge])
            }
        }
    }
    
    // MARK: - Dedup Maintenance
    
    private func pruneRecentKeys() {
        guard recentKeys.count > maxRecentKeys else { return }
        let cutoff = Date().addingTimeInterval(-deduplicationWindow)
        recentKeys = recentKeys.filter { $0.value > cutoff }
        // If still too many, remove oldest entries
        if recentKeys.count > maxRecentKeys {
            let sorted = recentKeys.sorted { $0.value < $1.value }
            let toRemove = sorted.prefix(recentKeys.count - maxRecentKeys / 2)
            for item in toRemove {
                recentKeys.removeValue(forKey: item.key)
            }
        }
    }
}
