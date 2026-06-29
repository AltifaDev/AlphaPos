// NotificationStore.swift
// AlphaPos — Enterprise Notification Store (Persistent Alert History)
// Provides a persistent in-memory store of ALL alerts for Notification Center.
// InAppNotificationManager handles transient banners (auto-dismiss);
// NotificationStore retains the full history until explicitly acknowledged.

import Foundation
import Combine
import SwiftUI

// MARK: - Alert Model

/// A persistent alert for the Notification Center.
/// Unlike InAppNotification (which auto-dismisses), these stay until acknowledged.
struct NotificationAlert: Identifiable, Equatable {
    let id = UUID()
    let priority: AlertPriority
    let category: AlertCategory
    let title: String
    let message: String
    let device: String          // Source device/system
    let tableNumber: String?    // For navigation
    let orderNumber: String?
    let createdAt: Date
    var isRead: Bool = false
    var isAcknowledged: Bool = false
    
    enum AlertPriority: Int, Comparable, CaseIterable {
        case critical = 0
        case high = 1
        case medium = 2
        case low = 3
        
        static func < (lhs: AlertPriority, rhs: AlertPriority) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
        
        var color: Color {
            switch self {
            case .critical: return Color(hex: "EF4444")
            case .high: return Color(hex: "F59E0B")
            case .medium: return Color(hex: "3B82F6")
            case .low: return Color(hex: "9CA3AF")
            }
        }
        
        var label: String {
            switch self {
            case .critical: return "Critical"
            case .high: return "High"
            case .medium: return "Medium"
            case .low: return "Low"
            }
        }
    }
    
    enum AlertCategory: String, CaseIterable, Identifiable {
        case all = "All"
        case orders = "Orders"
        case kitchen = "Kitchen"
        case staff = "Staff"
        case system = "System"
        case customer = "Customer"
        case payment = "Payment"
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .all: return "bell.fill"
            case .orders: return "tray.full.fill"
            case .kitchen: return "flame.fill"
            case .staff: return "person.2.fill"
            case .system: return "exclamationmark.triangle.fill"
            case .customer: return "person.crop.circle.fill"
            case .payment: return "creditcard.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .all: return .appAccent
            case .orders: return Color(hex: "3B82F6")
            case .kitchen: return Color(hex: "F59E0B")
            case .staff: return Color(hex: "8B5CF6")
            case .system: return Color(hex: "EF4444")
            case .customer: return Color(hex: "10B981")
            case .payment: return Color(hex: "EC4899")
            }
        }
    }
}

// MARK: - Notification Store (Observable Singleton)

/// Central store for all enterprise notifications.
/// Wire into NotificationCenterView via @ObservedObject or @EnvironmentObject.
///
/// Data flow:
/// ```
/// SyncEngine (Realtime WS) ──▶ InAppNotificationManager (transient banner)
///                          └──▶ NotificationStore (persistent history)
/// ```
@MainActor
final class NotificationStore: ObservableObject {
    static let shared = NotificationStore()
    
    /// All alerts (newest first)
    @Published var alerts: [NotificationAlert] = []
    
    /// Unread count (for badges)
    var unreadCount: Int {
        alerts.filter { !$0.isRead }.count
    }
    
    /// Active (unacknowledged) alert count
    var activeCount: Int {
        alerts.filter { !$0.isAcknowledged }.count
    }
    
    private var cancellables = Set<AnyCancellable>()
    private let maxAlerts = 200 // Keep last 200 alerts in memory
    
    private init() {
        // Subscribe to InAppNotificationManager to auto-capture all alerts
        InAppNotificationManager.shared.$latestNotification
            .compactMap { $0 }
            .sink { [weak self] notification in
                self?.captureFromInApp(notification)
            }
            .store(in: &cancellables)
        
        // Subscribe to SyncEngine active service requests
        SyncEngine.shared.$activeRequests
            .removeDuplicates { old, new in old.count == new.count }
            .sink { [weak self] requests in
                self?.captureServiceRequests(requests)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Capture from InAppNotificationManager
    
    private func captureFromInApp(_ notification: InAppNotification) {
        let alert = NotificationAlert(
            priority: mapPriority(notification.type),
            category: mapCategory(notification.type),
            title: notification.title,
            message: notification.body,
            device: deviceName(for: notification.type),
            tableNumber: notification.tableNumber,
            orderNumber: extractOrderNumber(notification.title),
            createdAt: notification.createdAt
        )
        addAlert(alert)
    }
    
    // MARK: - Capture Service Requests
    
    private var trackedRequestIds = Set<String>()
    
    private func captureServiceRequests(_ requests: [ServiceRequest]) {
        for request in requests where !trackedRequestIds.contains(request.id) {
            trackedRequestIds.insert(request.id)
            let alert = NotificationAlert(
                priority: .high,
                category: .customer,
                title: "service_request_alert_title".t,
                message: "\("table".t) \(request.tableNumber) — \(request.requestType)",
                device: "Customer Web",
                tableNumber: request.tableNumber,
                orderNumber: nil,
                createdAt: ISO8601DateFormatter().date(from: request.createdAt) ?? Date()
            )
            addAlert(alert)
        }
    }
    
    // MARK: - Public API
    
    /// Post a custom alert from anywhere in the app (e.g. payment failure, sync error)
    func postAlert(
        priority: NotificationAlert.AlertPriority,
        category: NotificationAlert.AlertCategory,
        title: String,
        message: String,
        device: String = "System",
        tableNumber: String? = nil,
        orderNumber: String? = nil
    ) {
        let alert = NotificationAlert(
            priority: priority,
            category: category,
            title: title,
            message: message,
            device: device,
            tableNumber: tableNumber,
            orderNumber: orderNumber,
            createdAt: Date()
        )
        addAlert(alert)
    }
    
    /// Mark alert as read
    func markRead(_ alertId: UUID) {
        if let idx = alerts.firstIndex(where: { $0.id == alertId }) {
            alerts[idx].isRead = true
        }
    }
    
    /// Acknowledge (dismiss) alert
    func acknowledge(_ alertId: UUID) {
        if let idx = alerts.firstIndex(where: { $0.id == alertId }) {
            alerts[idx].isAcknowledged = true
        }
    }
    
    /// Acknowledge all alerts
    func acknowledgeAll() {
        for i in alerts.indices {
            alerts[i].isAcknowledged = true
            alerts[i].isRead = true
        }
    }
    
    /// Get alerts filtered by category
    func filtered(by category: NotificationAlert.AlertCategory) -> [NotificationAlert] {
        if category == .all { return alerts.filter { !$0.isAcknowledged } }
        return alerts.filter { $0.category == category && !$0.isAcknowledged }
    }
    
    /// Clear acknowledged alerts older than X hours
    func cleanup(olderThan hours: Int = 24) {
        let cutoff = Date().addingTimeInterval(-TimeInterval(hours * 3600))
        alerts.removeAll { $0.isAcknowledged && $0.createdAt < cutoff }
    }
    
    // MARK: - Private Helpers
    
    private func addAlert(_ alert: NotificationAlert) {
        alerts.insert(alert, at: 0)
        // Trim to maxAlerts
        if alerts.count > maxAlerts {
            alerts = Array(alerts.prefix(maxAlerts))
        }
    }
    
    private func mapPriority(_ type: InAppNotificationType) -> NotificationAlert.AlertPriority {
        switch type {
        case .cookingAlert, .deliveryAlert: return .critical
        case .newOrder: return .high
        case .serviceRequest: return .medium
        case .staleShift: return .low
        }
    }
    
    private func mapCategory(_ type: InAppNotificationType) -> NotificationAlert.AlertCategory {
        switch type {
        case .newOrder: return .orders
        case .serviceRequest: return .customer
        case .cookingAlert: return .kitchen
        case .deliveryAlert: return .orders
        case .staleShift: return .system
        }
    }
    
    private func deviceName(for type: InAppNotificationType) -> String {
        switch type {
        case .newOrder: return "Customer Web"
        case .serviceRequest: return "Customer Web"
        case .cookingAlert: return "Kitchen Display"
        case .deliveryAlert: return "Delivery System"
        case .staleShift: return "System"
        }
    }
    
    private func extractOrderNumber(_ title: String) -> String? {
        // Extract #XXX from title
        if let range = title.range(of: "#\\d+", options: .regularExpression) {
            return String(title[range])
        }
        return nil
    }
}
