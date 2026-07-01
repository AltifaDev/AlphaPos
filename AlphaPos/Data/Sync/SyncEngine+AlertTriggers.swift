// SyncEngine+AlertTriggers.swift
// AlphaPos — Enterprise Alert Triggers via NotificationStore
// Hooks into SyncEngine lifecycle events to post persistent alerts
// to NotificationStore (which feeds NotificationCenterView).

import Foundation
import SwiftData

// MARK: - Enterprise Alert Triggers
// These methods should be called from existing SyncEngine flows
// to populate the NotificationCenter with actionable alerts.

extension SyncEngine {
    
    // MARK: - Sync Status Alerts
    
    /// Post alert when sync fails after multiple retries
    func alertSyncFailed(error: Error, attempt: Int) {
        guard attempt == 3 else { return } // Only alert exactly on the 3rd failure of a streak
        Task { @MainActor in
            NotificationStore.shared.postAlert(
                priority: .high,
                category: .system,
                title: "alert_sync_failed_title".t,
                message: "alert_sync_failed_msg".t + " (\(error.localizedDescription))",
                device: "Master iPad"
            )
        }
    }
    
    /// Post alert when connection is restored after offline period
    func alertConnectionRestored() {
        Task { @MainActor in
            NotificationStore.shared.postAlert(
                priority: .low,
                category: .system,
                title: "alert_connection_restored_title".t,
                message: "alert_connection_restored_msg".t,
                device: "System"
            )
        }
    }
    
    /// Post alert when going offline
    func alertWentOffline() {
        Task { @MainActor in
            NotificationStore.shared.postAlert(
                priority: .medium,
                category: .system,
                title: "alert_offline_title".t,
                message: "alert_offline_msg".t,
                device: "System"
            )
        }
    }
    
    // MARK: - Order Alerts
    
    /// Post alert for a new customer order (from QR web ordering)
    func alertNewCustomerOrder(orderNumber: String, tableNumber: String, itemCount: Int) {
        Task { @MainActor in
            NotificationStore.shared.postAlert(
                priority: .high,
                category: .orders,
                title: "alert_new_order_title".t + " #\(orderNumber)",
                message: "\("table".t) \(tableNumber) — \(itemCount) " + "alert_items_suffix".t,
                device: "Customer Web",
                tableNumber: tableNumber,
                orderNumber: orderNumber
            )
        }
    }
    
    /// Post alert when an order has been waiting too long in kitchen
    func alertOrderWaitingTooLong(orderNumber: String, tableNumber: String, minutesWaiting: Int) {
        Task { @MainActor in
            NotificationStore.shared.postAlert(
                priority: .critical,
                category: .kitchen,
                title: "alert_order_delayed_title".t,
                message: "#\(orderNumber) — \("table".t) \(tableNumber) — \(minutesWaiting) " + "alert_min_waiting".t,
                device: "Kitchen Display",
                tableNumber: tableNumber,
                orderNumber: orderNumber
            )
        }
    }
    
    /// Post alert when order is cancelled
    func alertOrderCancelled(orderNumber: String, tableNumber: String?, reason: String?) {
        Task { @MainActor in
            let tableInfo = tableNumber.map { " — \("table".t) \($0)" } ?? ""
            NotificationStore.shared.postAlert(
                priority: .medium,
                category: .orders,
                title: "alert_order_cancelled_title".t + " #\(orderNumber)",
                message: "alert_order_cancelled_msg".t + tableInfo + (reason.map { " (\($0))" } ?? ""),
                device: "System",
                tableNumber: tableNumber,
                orderNumber: orderNumber
            )
        }
    }
    
    // MARK: - Payment Alerts
    
    /// Post alert when a payment fails
    func alertPaymentFailed(orderNumber: String?, amount: Double, method: String, error: String?) {
        Task { @MainActor in
            let currencySymbol = UserDefaults.standard.string(forKey: "app_currency_symbol") ?? "฿"
            let orderInfo = orderNumber.map { " #\($0)" } ?? ""
            NotificationStore.shared.postAlert(
                priority: .critical,
                category: .payment,
                title: "alert_payment_failed_title".t + orderInfo,
                message: "\(currencySymbol)\(String(format: "%.2f", amount)) — \(method) — \(error ?? "unknown")",
                device: "Register 1",
                orderNumber: orderNumber
            )
        }
    }
    
    /// Post alert when a large refund is processed
    func alertLargeRefund(orderNumber: String, amount: Double, threshold: Double) {
        guard amount >= threshold else { return }
        Task { @MainActor in
            let currencySymbol = UserDefaults.standard.string(forKey: "app_currency_symbol") ?? "฿"
            NotificationStore.shared.postAlert(
                priority: .high,
                category: .payment,
                title: "alert_large_refund_title".t,
                message: "#\(orderNumber) — \(currencySymbol)\(String(format: "%.2f", amount))",
                device: "Register 1",
                orderNumber: orderNumber
            )
        }
    }
    
    // MARK: - Staff Alerts
    
    /// Post alert when staff clocks in
    func alertStaffClockIn(name: String) {
        Task { @MainActor in
            NotificationStore.shared.postAlert(
                priority: .low,
                category: .staff,
                title: "alert_staff_clock_in_title".t,
                message: name + " " + "alert_staff_clock_in_msg".t,
                device: "Staff iPhone"
            )
        }
    }
    
    /// Post alert when staff clocks out
    func alertStaffClockOut(name: String, hoursWorked: Double) {
        Task { @MainActor in
            NotificationStore.shared.postAlert(
                priority: .low,
                category: .staff,
                title: "alert_staff_clock_out_title".t,
                message: name + " — \(String(format: "%.1f", hoursWorked)) " + "alert_hours_worked".t,
                device: "Staff iPhone"
            )
        }
    }
    
    /// Post alert when staff session is locked due to timeout
    func alertStaffSessionLocked(name: String, reason: String) {
        Task { @MainActor in
            NotificationStore.shared.postAlert(
                priority: .medium,
                category: .staff,
                title: "alert_staff_locked_title".t,
                message: name + " — " + reason,
                device: "Master iPad"
            )
        }
    }
    
    // MARK: - Inventory Alerts
    
    /// Post alert when inventory falls below reorder level
    func alertLowStock(itemName: String, currentQty: Double, reorderLevel: Double) {
        Task { @MainActor in
            NotificationStore.shared.postAlert(
                priority: .medium,
                category: .system,
                title: "alert_low_stock_title".t,
                message: "\(itemName) — \(Int(currentQty))/\(Int(reorderLevel)) " + "alert_low_stock_suffix".t,
                device: "System"
            )
        }
    }
    
    // MARK: - Device Alerts
    
    /// Post alert when a device goes offline
    func alertDeviceOffline(deviceName: String, lastSeen: Date) {
        Task { @MainActor in
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            let timeAgo = formatter.localizedString(for: lastSeen, relativeTo: Date())
            NotificationStore.shared.postAlert(
                priority: .high,
                category: .system,
                title: "alert_device_offline_title".t,
                message: "\(deviceName) — " + "alert_last_seen".t + " \(timeAgo)",
                device: deviceName
            )
        }
    }
    
    /// Post alert when a device reconnects
    func alertDeviceReconnected(deviceName: String) {
        Task { @MainActor in
            NotificationStore.shared.postAlert(
                priority: .low,
                category: .system,
                title: "alert_device_reconnected_title".t,
                message: deviceName + " " + "alert_device_reconnected_msg".t,
                device: deviceName
            )
        }
    }
    
    // MARK: - Kitchen Alerts
    
    /// Post alert when kitchen marks order ready
    func alertOrderReady(orderNumber: String, tableNumber: String?) {
        Task { @MainActor in
            let tableInfo = tableNumber.map { " — \("table".t) \($0)" } ?? ""
            NotificationStore.shared.postAlert(
                priority: .medium,
                category: .kitchen,
                title: "alert_order_ready_title".t + " #\(orderNumber)",
                message: "alert_order_ready_msg".t + tableInfo,
                device: "Kitchen Display",
                tableNumber: tableNumber,
                orderNumber: orderNumber
            )
        }
    }
    
    // MARK: - Customer Alerts
    
    /// Post alert when customer requests assistance via QR
    func alertCustomerCallStaff(tableNumber: String, requestType: String) {
        Task { @MainActor in
            NotificationStore.shared.postAlert(
                priority: .high,
                category: .customer,
                title: "alert_customer_call_title".t,
                message: "\("table".t) \(tableNumber) — \(requestType)",
                device: "Customer Web",
                tableNumber: tableNumber
            )
        }
    }
    
    /// Post alert when customer leaves feedback/rating
    func alertCustomerFeedback(tableNumber: String, rating: Int) {
        Task { @MainActor in
            let stars = String(repeating: "⭐", count: rating)
            NotificationStore.shared.postAlert(
                priority: .low,
                category: .customer,
                title: "alert_feedback_title".t,
                message: "\("table".t) \(tableNumber) — \(stars)",
                device: "Customer Web",
                tableNumber: tableNumber
            )
        }
    }
}
