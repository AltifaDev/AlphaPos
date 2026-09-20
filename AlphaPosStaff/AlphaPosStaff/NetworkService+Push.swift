// NetworkService+Push.swift
// AlphaPosStaff — Push Notification Registration & Management
//
// Responsibilities:
//   • Register APNs device token with Supabase (push_devices table)
//   • Include employee_id so targeted shift/timecard pushes work
//   • Deregister (mark is_active = false) on logout
//   • Expose send-staff-push caller for manual pushes from the app
//   • Read/write per-device notification preferences

import Foundation

extension NetworkService {

    // ─── Token Registration ────────────────────────────────────────────────────

    /// Call from AppDelegate.didRegisterForRemoteNotificationsWithDeviceToken.
    /// Stores token locally, then upserts it to Supabase.
    func registerPushToken(_ tokenData: Data, employeeId: String? = nil) {
        let hexToken = tokenData.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(hexToken, forKey: "apns_device_token")
        if let empId = employeeId {
            UserDefaults.standard.set(empId, forKey: "apns_employee_id")
        }
        Task { try? await self.upsertPushDevice() }
    }

    /// Call after successful employee login to associate employee_id with this device.
    func associatePushToken(with employeeId: String) {
        UserDefaults.standard.set(employeeId, forKey: "apns_employee_id")
        Task { try? await self.upsertPushDevice() }
    }

    /// Call on employee logout. A staff iPhone must not remain eligible for
    /// merchant-wide operational pushes while no employee is signed in.
    func dissociatePushTokenEmployee() {
        UserDefaults.standard.removeObject(forKey: "apns_employee_id")
        Task {
            guard let token = UserDefaults.standard.string(forKey: "apns_device_token"), !token.isEmpty else { return }
            _ = try? await self.sendSupabaseRequest(
                method: "PATCH", endpoint: "push_devices",
                queryItems: [URLQueryItem(name: "device_token", value: "eq.\(token)")],
                payload: ["employee_id": NSNull(), "is_active": false,
                          "updated_at": ISO8601DateFormatter().string(from: Date())]
            )
        }
    }

    /// Mark this device's token as inactive (e.g., on full logout / uninstall callback).
    func deregisterPushToken() async {
        guard let token = UserDefaults.standard.string(forKey: "apns_device_token"),
              !token.isEmpty else { return }
        let payload: [String: Any] = [
            "is_active": false,
            "updated_at": ISO8601DateFormatter().string(from: Date())
        ]
        let query = [URLQueryItem(name: "device_token", value: "eq.\(token)")]
        _ = try? await sendSupabaseRequest(method: "PATCH", endpoint: "push_devices", queryItems: query, payload: payload)
    }

    // ─── Internal Upsert ──────────────────────────────────────────────────────

    /// Upserts this device's push registration row in Supabase.
    /// Called automatically after token registration or employee login/logout.
    func upsertPushDevice() async throws {
        guard let token = UserDefaults.standard.string(forKey: "apns_device_token"),
              !token.isEmpty else { return }

        let employeeIdStr = UserDefaults.standard.string(forKey: "apns_employee_id")
        let merchantId = activeMerchantId

        var payload: [String: Any] = [
            "merchant_id":  merchantId,
            "device_token": token,
            "app_id":       "staff",
            "platform":     "ios",
            "language_code": UserDefaults.standard.string(forKey: "app_language") ?? "en",
            "is_active":    true,
            "updated_at":   ISO8601DateFormatter().string(from: Date())
        ]

        #if DEBUG
        payload["environment"] = "sandbox"
        #else
        payload["environment"] = "production"
        #endif

        if let empId = employeeIdStr, !empId.isEmpty {
            payload["employee_id"] = empId
        } else {
            // Explicitly null out employee_id when logged out
            payload["employee_id"] = NSNull()
        }

        _ = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "push_devices",
            queryItems: [URLQueryItem(name: "on_conflict", value: "device_token")],
            payload: payload
        )

        #if DEBUG
        print("NetworkService [Push]: Registered device token for merchant \(merchantId)" +
              (employeeIdStr != nil ? " employee \(employeeIdStr!)" : ""))
        #endif
    }

    // ─── Manual Push Trigger ──────────────────────────────────────────────────

    /// Manually trigger a push notification via the send-staff-push Edge Function.
    /// Useful for test notifications or manager-initiated alerts.
    ///
    /// - Parameters:
    ///   - eventType: One of "new_order", "order_ready", "service_request", "table_occupied",
    ///                "table_vacant", "shift_reminder", "timecard_reminder", "inventory_alert"
    ///   - merchantId: Target merchant (defaults to activeMerchantId)
    ///   - orderId:    Optional order UUID
    ///   - orderNumber: Optional order display number
    ///   - tableNumber: Optional table number string
    ///   - requestId:  Optional service request UUID
    ///   - requestType: Optional request type label
    ///   - employeeId: Optional — if set, only sends to that employee's devices
    ///   - message:    Optional body override
    @discardableResult
    func sendStaffPush(
        eventType: String,
        merchantId: String? = nil,
        orderId: String? = nil,
        orderNumber: String? = nil,
        tableNumber: String? = nil,
        requestId: String? = nil,
        requestType: String? = nil,
        employeeId: String? = nil,
        message: String? = nil
    ) async throws -> [String: Any] {
        let edgeFunctionURL = AppConfig.supabaseURL
            .appendingPathComponent("functions/v1/send-staff-push")

        var req = URLRequest(url: edgeFunctionURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        let token = authorizationToken
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 10

        var body: [String: Any] = [
            "event_type":  eventType,
            "merchant_id": merchantId ?? activeMerchantId
        ]
        if let v = orderId      { body["order_id"]     = v }
        if let v = orderNumber  { body["order_number"] = v }
        if let v = tableNumber  { body["table_number"] = v }
        if let v = requestId    { body["request_id"]   = v }
        if let v = requestType  { body["request_type"] = v }
        if let v = employeeId   { body["employee_id"]  = v }
        if let v = message      { body["message"]      = v }

        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await session.data(for: req)
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    // ─── Notification Preferences ────────────────────────────────────────────

    struct PushNotificationPreferences {
        var newOrders: Bool
        var orderReady: Bool
        var serviceRequests: Bool
        var tableStatus: Bool
        var webOrders: Bool
        var shiftReminders: Bool
        var timecardReminders: Bool
        var inventoryAlerts: Bool

        static var current: PushNotificationPreferences {
            let d = UserDefaults.standard
            return PushNotificationPreferences(
                newOrders:         d.object(forKey: "push_new_orders")         as? Bool ?? true,
                orderReady:        d.object(forKey: "push_order_ready")        as? Bool ?? true,
                serviceRequests:   d.object(forKey: "push_service_requests")   as? Bool ?? true,
                tableStatus:       d.object(forKey: "push_table_status")       as? Bool ?? false,
                webOrders:         d.object(forKey: "push_web_orders")         as? Bool ?? true,
                shiftReminders:    d.object(forKey: "push_shift_reminders")    as? Bool ?? true,
                timecardReminders: d.object(forKey: "push_timecard_reminders") as? Bool ?? true,
                inventoryAlerts:   d.object(forKey: "push_inventory_alerts")   as? Bool ?? true
            )
        }

        func save() {
            let d = UserDefaults.standard
            d.set(newOrders,         forKey: "push_new_orders")
            d.set(orderReady,        forKey: "push_order_ready")
            d.set(serviceRequests,   forKey: "push_service_requests")
            d.set(tableStatus,       forKey: "push_table_status")
            d.set(webOrders,         forKey: "push_web_orders")
            d.set(shiftReminders,    forKey: "push_shift_reminders")
            d.set(timecardReminders, forKey: "push_timecard_reminders")
            d.set(inventoryAlerts,   forKey: "push_inventory_alerts")
        }

        /// Returns true if the given APNs push type should trigger an in-app/local notification
        func shouldShow(for pushType: String) -> Bool {
            switch pushType {
            case "new_order", "order_new":      return newOrders
            case "order_ready":                  return orderReady
            case "service_request":              return serviceRequests
            case "table_occupied", "table_vacant", "table_status": return tableStatus
            case "web_order", "web_order_new":   return webOrders
            case "schedule", "shift_reminder":   return shiftReminders
            case "timecard", "timecard_reminder": return timecardReminders
            case "inventory_alert", "inventory_low", "inventory_out": return inventoryAlerts
            default:                             return true
            }
        }
    }
}
