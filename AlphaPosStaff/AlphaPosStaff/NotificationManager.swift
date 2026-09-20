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
            if granted {
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
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
    func notify(title: String, body: String, type: NotificationType = .system, deduplicationKey: String? = nil, userInfo: [String: Any]? = nil) {
        // Operational alerts are for on-duty staff only. The server applies
        // the same rule for APNs; this local guard covers realtime/in-app
        // notifications while the app is open or during a logout transition.
        let isOperational: Bool
        switch type {
        case .order, .request, .tableStatus, .urgent: isOperational = true
        case .system: isOperational = false
        }
        if isOperational {
            let employeeId = StaffSessionContext.employeeId
            let isClockedIn = UserDefaults.standard.bool(forKey: "staff_is_clocked_in")
            guard !employeeId.isEmpty && isClockedIn else {
                #if DEBUG
                print("NotificationManager: operational notification suppressed — staff not on duty")
                #endif
                return
            }
        }
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
            routeNotification(title: title, body: body, type: type, userInfo: userInfo)
        } else {
            DispatchQueue.main.async { [self] in
                routeNotification(title: title, body: body, type: type, userInfo: userInfo)
            }
        }
    }
    
    // MARK: - Private Routing
    
    private func routeNotification(title: String, body: String, type: NotificationType, userInfo: [String: Any]?) {
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
            fireSystemNotification(title: title, body: body, userInfo: userInfo)
        }
    }
    
    // MARK: - iOS System Notification (Background only)
    
    private func fireSystemNotification(title: String, body: String, userInfo: [String: Any]?) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = UNNotificationSound.default
        if let info = userInfo {
            content.userInfo = info
        }
        
        let count = NetworkService.shared.activeAlertsCount
        content.badge = NSNumber(value: count)
        
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
    
    // MARK: - Remote Push → In-App Banner Bridge
    
    /// Called when a remote push arrives while the app is in the foreground.
    /// Converts the APNs payload into an in-app banner so users don't miss it.
    func handleRemotePush(userInfo: [AnyHashable: Any]) {
        let pushType = userInfo["type"] as? String ?? "system"
        
        // Check per-category preference
        let prefs = NetworkService.PushNotificationPreferences.current
        guard prefs.shouldShow(for: pushType) else { return }
        
        // Extract title/body from aps.alert or top-level keys
        let apsAlert = (userInfo["aps"] as? [String: Any])?["alert"] as? [String: Any]
        let title = apsAlert?["title"] as? String
                 ?? userInfo["title"] as? String
                 ?? "AlphaPos Staff"
        let body  = apsAlert?["body"] as? String
                 ?? userInfo["body"] as? String
                 ?? ""
        
        let notifType = mapPushTypeToNotificationType(pushType)
        let stableId = (userInfo["order_id"] as? String)
            ?? (userInfo["request_id"] as? String)
            ?? (userInfo["table_number"] as? String)
        let deduplicationKey = stableId.map { "push:\(pushType):\($0)" }

        notify(title: title, body: body, type: notifType,
               deduplicationKey: deduplicationKey,
               userInfo: userInfo as? [String: Any])
    }
    
    private func mapPushTypeToNotificationType(_ pushType: String) -> NotificationType {
        switch pushType {
        case "new_order", "order_new", "web_order":
            return .order
        case "order_ready":
            return .order
        case "service_request":
            return .request
        case "table_status", "table_occupied", "table_vacant":
            return .tableStatus
        case "timecard", "timecard_reminder", "schedule", "shift_reminder":
            return .system
        default:
            return .system
        }
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        let pushType = userInfo["type"] as? String ?? "system"
        
        DispatchQueue.main.async {
            if UIApplication.shared.applicationState == .active {
                // Foreground: convert to in-app banner and suppress system banner
                self.handleRemotePush(userInfo: userInfo)
                completionHandler([])
            } else {
                // Background: check user preference before showing system banner
                let prefs = NetworkService.PushNotificationPreferences.current
                if prefs.shouldShow(for: pushType) {
                    completionHandler([.banner, .sound, .badge])
                } else {
                    completionHandler([])
                }
            }
        }
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        
        // Route through DeepLinkRouter for all notification taps
        if let destination = DeepLinkRouter.parseUserInfo(userInfo) {
            DispatchQueue.main.async {
                DeepLinkRouter.shared.navigate(to: destination)
            }
        } else {
            // Fallback: legacy behavior for unrecognized payloads
            let type = userInfo["type"] as? String
            if type == "order" || type == "order_ready" || type == "new_order" || type == "service_request" {
                NotificationCenter.default.post(
                    name: .openAlertsNotification,
                    object: nil,
                    userInfo: userInfo
                )
            } else if type == "table_status" || type == "table_occupied" || type == "table_vacant" {
                if let tableNumber = userInfo["table_number"] as? String {
                    NotificationCenter.default.post(
                        name: .openTableNotification,
                        object: nil,
                        userInfo: ["table_number": tableNumber]
                    )
                }
            }
        }
        
        // Trigger a fresh sync whenever a push is tapped
        Task { await NetworkService.shared.refreshAll() }
        
        completionHandler()
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

extension Notification.Name {
    static let openAlertsNotification = Notification.Name("openAlertsNotification")
    static let openTableNotification = Notification.Name("openTableNotification")
    static let checkoutCompleted = Notification.Name("checkoutCompleted")
}
