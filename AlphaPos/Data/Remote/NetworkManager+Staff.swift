import Foundation
import CryptoKit
import SwiftData

extension NetworkManager {
    // MARK: - Audit Logs Sync

    func uploadAuditLog(_ log: RemoteAuditLogUploadable) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId

        var payload: [String: Any] = [
            "id": log.id.uuidString.lowercased(),
            "merchant_id": merchantId,
            "action_type": log.actionType,
            "is_synced": true,
            "is_deleted": log.isDeleted,
            "updated_at": NetworkManager.iso8601.string(from: log.updatedAt),
            "created_at": NetworkManager.iso8601.string(from: log.createdAt)
        ]

        if let empId = log.employeeId {
            payload["employee_id"] = empId.uuidString.lowercased()
        }
        if let details = log.details {
            payload["details"] = details
        }
        if let origVal = log.originalValue {
            payload["original_value"] = origVal
        }
        if let newVal = log.newValue {
            payload["new_value"] = newVal
        }

        _ = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "audit_logs",
            queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
            payload: payload
        )
        return true
    }

    func deleteAuditLogOnServer(id: UUID) async throws -> Bool {
        _ = try await sendSupabaseRequest(
            method: "DELETE",
            endpoint: "audit_logs",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(id.uuidString.lowercased())")]
        )
        return true
    }

    // MARK: - Staff Security and Device Sync

    func replaceRolePermissions(role: Role) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        _ = try await sendSupabaseRequest(
            method: "DELETE",
            endpoint: "role_permissions",
            queryItems: [URLQueryItem(name: "role", value: "eq.\(role.name)")]
        )

        let permissions = PermissionService.permissions(for: role)
        guard !permissions.isEmpty else { return true }

        let payload = permissions.map { permission in
            [
                "merchant_id": merchantId,
                "role": role.name,
                "permission_key": permission.rawValue
            ]
        }

        _ = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "role_permissions",
            queryItems: [URLQueryItem(name: "on_conflict", value: "merchant_id,role,permission_key")],
            payload: payload
        )
        return true
    }

    func uploadMerchantDevice(_ device: MerchantDevice) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        var payload: [String: Any] = [
            "id": device.id.uuidString.lowercased(),
            "merchant_id": merchantId,
            "device_name": device.deviceName,
            "device_type": device.deviceType,
            "is_trusted": device.isTrusted,
            "updated_at": NetworkManager.iso8601.string(from: device.updatedAt)
        ]
        if let branchId = device.branchId {
            payload["branch_id"] = branchId.uuidString.lowercased()
        }
        if let fingerprint = device.deviceFingerprintHash {
            payload["device_fingerprint_hash"] = fingerprint
        }
        if let lastSeenAt = device.lastSeenAt {
            payload["last_seen_at"] = NetworkManager.iso8601.string(from: lastSeenAt)
        }
        payload["created_at"] = NetworkManager.iso8601.string(from: device.createdAt)

        _ = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "merchant_devices",
            queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
            payload: payload
        )
        return true
    }

    func uploadStaffSessionRecord(_ session: StaffSessionRecord) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        var payload: [String: Any] = [
            "id": session.id.uuidString.lowercased(),
            "merchant_id": merchantId,
            "started_at": NetworkManager.iso8601.string(from: session.startedAt),
            "created_at": NetworkManager.iso8601.string(from: session.startedAt)
        ]
        if let deviceId = session.deviceId {
            payload["device_id"] = deviceId.uuidString.lowercased()
        }
        if let employeeId = session.employeeId {
            payload["employee_id"] = employeeId.uuidString.lowercased()
        }
        if let roleName = session.roleName {
            payload["role"] = roleName
        }
        if let endedAt = session.endedAt {
            payload["ended_at"] = NetworkManager.iso8601.string(from: endedAt)
        }
        if let endedReason = session.endedReason {
            payload["ended_reason"] = endedReason
        }

        _ = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "staff_sessions",
            queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
            payload: payload
        )
        return true
    }

    func uploadSecurityPolicy(_ policy: SecurityPolicy) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        let payload: [String: Any] = [
            "merchant_id": merchantId,
            "passcode_min_length": policy.passcodeMinLength,
            "passcode_max_attempts": policy.passcodeMaxAttempts,
            "lockout_minutes": policy.lockoutMinutes,
            "staff_session_timeout_minutes": policy.staffSessionTimeoutMinutes,
            "require_manager_override_for_refund": policy.requireManagerOverrideForRefund,
            "require_manager_override_for_void": policy.requireManagerOverrideForVoid,
            "updated_at": NetworkManager.iso8601.string(from: policy.updatedAt)
        ]

        _ = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "security_policies",
            queryItems: [URLQueryItem(name: "on_conflict", value: "merchant_id")],
            payload: payload
        )
        return true
    }

    // MARK: - Register Sessions Sync

    func uploadRegisterSession(_ session: RegisterSession) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId

        var payload: [String: Any] = [
            "id": session.id.uuidString.lowercased(),
            "merchant_id": merchantId,
            "opened_by_user_id": session.openedByUserId.uuidString.lowercased(),
            "opened_at": NetworkManager.iso8601.string(from: session.openedAt),
            "opening_cash": session.openingCash,
            "expected_closing_cash": session.expectedClosingCash,
            "actual_closing_cash": session.actualClosingCash,
            "cash_discrepancy": session.cashDiscrepancy,
            "is_synced": true,
            "is_deleted": session.isDeleted,
            "updated_at": NetworkManager.iso8601.string(from: session.updatedAt)
        ]

        if let branchId = session.branch?.id {
            payload["branch_id"] = branchId.uuidString.lowercased()
        }
        if let closedBy = session.closedByUserId {
            payload["closed_by_user_id"] = closedBy.uuidString.lowercased()
        }
        if let closedAt = session.closedAt {
            payload["closed_at"] = NetworkManager.iso8601.string(from: closedAt)
        }
        if let notes = session.notes {
            payload["notes"] = notes
        }

        _ = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "register_sessions",
            queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
            payload: payload
        )
        return true
    }

    func fetchRegisterSessionsFromSupabase() async throws -> [[String: Any]] {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        let data = try await sendSupabaseRequest(
            method: "GET",
            endpoint: "register_sessions",
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)"),
                URLQueryItem(name: "is_deleted", value: "eq.false")
            ]
        )
        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw NetworkError.invalidResponse
        }
        return jsonArray
    }

    func deleteRegisterSessionOnServer(id: UUID) async throws -> Bool {
        _ = try await sendSupabaseRequest(
            method: "DELETE",
            endpoint: "register_sessions",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(id.uuidString.lowercased())")]
        )
        return true
    }

    func uploadShiftReport(_ report: ShiftReport) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId

        var payload: [String: Any] = [
            "id": report.id.uuidString.lowercased(),
            "merchant_id": merchantId,
            "report_type": report.reportType,
            "gross_sales": report.grossSales,
            "net_sales": report.netSales,
            "total_tax": report.totalTax,
            "total_discounts": report.totalDiscounts,
            "total_refunds": report.totalRefunds,
            "cash_expected": report.cashExpected,
            "cash_actual": report.cashActual,
            "over_short": report.overShort,
            "is_synced": true,
            "is_deleted": report.isDeleted,
            "updated_at": NetworkManager.iso8601.string(from: report.updatedAt),
            "created_at": NetworkManager.iso8601.string(from: report.createdAt)
        ]

        if let sessionId = report.registerSession?.id {
            payload["register_session_id"] = sessionId.uuidString.lowercased()
        }
        if let employeeId = report.generatedByEmployee?.id {
            payload["generated_by_employee_id"] = employeeId.uuidString.lowercased()
        }

        _ = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "shift_reports",
            queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
            payload: payload
        )
        return true
    }

    func fetchEmployees() async throws -> [[String: Any]] {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        let data = try await sendSupabaseRequest(method: "GET", endpoint: "employees", queryItems: [
            URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)"),
            URLQueryItem(name: "is_deleted", value: "eq.false")
        ])
        return (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
    }

    func fetchEmployeeShifts() async throws -> [[String: Any]] {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        let data = try await sendSupabaseRequest(method: "GET", endpoint: "employee_shifts", queryItems: [
            URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)"),
            URLQueryItem(name: "is_deleted", value: "eq.false")
        ])
        return (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
    }
}
