// DeepLinkRouter.swift
// AlphaPosStaff — Deep Link Navigation Router
// จัดการ navigation เมื่อ user tap push notification (foreground + background)
// Supports: order, table, alert, timecard, schedule deep links

import SwiftUI
import Combine

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - Deep Link Destination
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

enum DeepLinkDestination: Equatable {
    case order(orderId: String)
    case table(tableNumber: String)
    case alert(alertId: String)
    case timecard
    case schedule
    case quickOrder
    
    /// Tab index this destination should activate
    var targetTab: Int {
        switch self {
        case .table:      return 0  // Tables tab
        case .quickOrder: return 1  // Quick Order tab
        case .alert:      return 2  // Alerts tab
        case .order:      return 2  // Orders appear in alerts/timeline
        case .timecard:   return 3  // Timecard tab
        case .schedule:   return 3  // Schedule (under timecard for now)
        }
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - Deep Link Router (ObservableObject)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

final class DeepLinkRouter: ObservableObject {
    static let shared = DeepLinkRouter()
    
    // MARK: - Published State (drives UI navigation)
    
    /// Current pending deep link destination. Views observe this and navigate accordingly.
    @Published var pendingDestination: DeepLinkDestination? = nil
    
    /// When an order deep link is tapped, this holds the order ID for sheet presentation
    @Published var presentOrderId: String? = nil
    
    /// When a table deep link is tapped, this holds the table number for navigation
    @Published var presentTableNumber: String? = nil
    
    /// When an alert deep link is tapped, this holds the alert ID for scroll-to
    @Published var scrollToAlertId: String? = nil
    
    // MARK: - Notification Names
    
    static let deepLinkNotification = Notification.Name("AlphaPosStaff.deepLink")
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        // Listen for deep link notifications from NotificationManager
        NotificationCenter.default.publisher(for: Self.deepLinkNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleDeepLinkNotification(notification)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Parse Notification Payload
    
    /// Parse a push notification userInfo dictionary into a DeepLinkDestination
    /// Expected payload formats:
    ///   { "deeplink": "order:abc-123" }
    ///   { "deeplink": "table:5" }
    ///   { "deeplink": "alert:xyz-456" }
    ///   { "deeplink": "timecard" }
    ///   { "deeplink": "schedule" }
    ///   OR legacy format:
    ///   { "type": "order", "order_id": "abc-123" }
    ///   { "type": "table_status", "table_number": "5" }
    static func parseUserInfo(_ userInfo: [AnyHashable: Any]) -> DeepLinkDestination? {
        // Format 1: "deeplink" key with colon-separated value
        if let deeplink = userInfo["deeplink"] as? String {
            return parseDeeplinkString(deeplink)
        }
        
        // Format 2: Legacy "type" + ID keys (from existing NotificationManager)
        if let type = userInfo["type"] as? String {
            switch type {
            case "order", "new_order", "order_ready", "order_update":
                if let orderId = userInfo["order_id"] as? String {
                    return .order(orderId: orderId)
                }
            case "table_status", "table_update":
                if let tableNumber = userInfo["table_number"] as? String {
                    return .table(tableNumber: tableNumber)
                }
            case "service_request", "alert":
                if let alertId = userInfo["alert_id"] as? String {
                    return .alert(alertId: alertId)
                }
                // Fallback: use request_id
                if let requestId = userInfo["request_id"] as? String {
                    return .alert(alertId: requestId)
                }
                // Generic alert tap → just open alerts tab
                return .alert(alertId: "")
            case "timecard", "clock_reminder":
                return .timecard
            case "schedule", "shift_reminder":
                return .schedule
            default:
                break
            }
        }
        
        return nil
    }
    
    /// Parse "type:id" format deeplink string
    private static func parseDeeplinkString(_ deeplink: String) -> DeepLinkDestination? {
        let components = deeplink.split(separator: ":", maxSplits: 1)
        guard let type = components.first else { return nil }
        let id = components.count > 1 ? String(components[1]) : ""
        
        switch String(type) {
        case "order":    return .order(orderId: id)
        case "table":    return .table(tableNumber: id)
        case "alert":    return .alert(alertId: id)
        case "timecard": return .timecard
        case "schedule": return .schedule
        case "quick_order": return .quickOrder
        default:         return nil
        }
    }
    
    // MARK: - Handle Incoming Deep Link
    
    /// Called when a deep link notification is received (from NotificationManager delegate)
    func navigate(to destination: DeepLinkDestination) {
        #if DEBUG
        print("DeepLinkRouter: Navigating to \(destination)")
        #endif
        
        // Reset previous state
        presentOrderId = nil
        presentTableNumber = nil
        scrollToAlertId = nil
        
        // Set destination (triggers tab switch in MainTabView)
        pendingDestination = destination
        
        // Set specific presentation state
        switch destination {
        case .order(let orderId):
            presentOrderId = orderId
        case .table(let tableNumber):
            presentTableNumber = tableNumber
        case .alert(let alertId):
            if !alertId.isEmpty {
                scrollToAlertId = alertId
            }
        case .timecard, .schedule, .quickOrder:
            break
        }
        
        // Auto-clear pending destination after a delay (so views have time to react)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.pendingDestination = nil
        }
    }
    
    /// Convenience: navigate from userInfo dictionary
    func navigateFromUserInfo(_ userInfo: [AnyHashable: Any]) {
        guard let destination = Self.parseUserInfo(userInfo) else {
            #if DEBUG
            print("DeepLinkRouter: Could not parse userInfo: \(userInfo)")
            #endif
            return
        }
        navigate(to: destination)
    }
    
    // MARK: - Internal Notification Handler
    
    private func handleDeepLinkNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo else { return }
        navigateFromUserInfo(userInfo)
    }
    
    // MARK: - Clear State
    
    /// Call after navigation is complete to clean up state
    func clearOrderPresentation() {
        presentOrderId = nil
    }
    
    func clearTablePresentation() {
        presentTableNumber = nil
    }
    
    func clearAlertScroll() {
        scrollToAlertId = nil
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - Notification.Name Extension
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

extension Notification.Name {
    static let deepLinkNavigation = Notification.Name("AlphaPosStaff.deepLink")
}
