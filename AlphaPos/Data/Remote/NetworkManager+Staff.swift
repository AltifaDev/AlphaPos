import Foundation
import CryptoKit
import SwiftData

extension NetworkManager {
    // MARK: - Audit Logs Sync

    func uploadAuditLog(_ log: RemoteAuditLogUploadable) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""

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

    /// Pull recent audit rows for the active merchant (RLS-scoped).
    func fetchAuditLogs(limit: Int = 100) async throws -> [[String: Any]] {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        let data = try await sendSupabaseRequest(
            method: "GET",
            endpoint: "audit_logs",
            queryItems: [
                URLQueryItem(name: "merchant_id", value: "eq.\(merchantId.lowercased())"),
                URLQueryItem(name: "is_deleted", value: "eq.false"),
                URLQueryItem(name: "order", value: "created_at.desc"),
                URLQueryItem(name: "limit", value: "\(max(1, min(limit, 200)))")
            ]
        )
        return (try JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
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
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
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
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
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
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
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
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        let payload: [String: Any] = [
            "merchant_id": merchantId,
            "passcode_min_length": policy.passcodeMinLength,
            "passcode_max_attempts": policy.passcodeMaxAttempts,
            "lockout_minutes": policy.lockoutMinutes,
            "staff_session_timeout_minutes": policy.staffSessionTimeoutMinutes,
            "require_manager_override_for_refund": policy.requireManagerOverrideForRefund,
            "require_manager_override_for_void": policy.requireManagerOverrideForVoid,
            "require_manager_override_for_no_sale": policy.requireManagerOverrideForNoSale,
            "require_manager_override_for_drawer_test": policy.requireManagerOverrideForDrawerTest,
            "require_face_scan": policy.requireFaceScan,
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

    func fetchSecurityPolicy() async throws -> [String: Any]? {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        let data = try await sendSupabaseRequest(
            method: "GET",
            endpoint: "security_policies",
            queryItems: [
                URLQueryItem(name: "merchant_id", value: "eq.\(merchantId.lowercased())"),
                URLQueryItem(name: "limit", value: "1")
            ]
        )
        return (try JSONSerialization.jsonObject(with: data) as? [[String: Any]])?.first
    }

    // MARK: - Register Sessions Sync

    func uploadRegisterSession(_ session: RegisterSession) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""

        var payload: [String: Any] = [
            "id": session.id.uuidString.lowercased(),
            "merchant_id": merchantId,
            "opened_by_user_id": session.openedByUserId.uuidString.lowercased(),
            "opened_at": NetworkManager.iso8601.string(from: session.openedAt),
            "business_date": session.businessDateKey,
            "opening_cash": session.openingCash,
            "expected_closing_cash": session.expectedClosingCash,
            "actual_closing_cash": session.actualClosingCash,
            "cash_discrepancy": session.cashDiscrepancy,
            "is_synced": true,
            "is_deleted": session.isDeleted,
            "updated_at": NetworkManager.iso8601.string(from: session.updatedAt)
        ]

        payload["branch_id"] = session.branch.id.uuidString.lowercased()
        if let closedBy = session.closedByUserId {
            payload["closed_by_user_id"] = closedBy.uuidString.lowercased()
        }
        if let closedAt = session.closedAt {
            payload["closed_at"] = NetworkManager.iso8601.string(from: closedAt)
        }
        if let notes = session.notes {
            payload["notes"] = notes
        }

        do {
            _ = try await sendSupabaseRequest(
                method: "POST",
                endpoint: "register_sessions",
                queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
                payload: payload
            )
        } catch {
            // Transitional compatibility for self-hosted instances where the
            // business-date migration has not reached PostgREST's schema cache.
            // Retry the rest of the register session instead of blocking all sync.
            let message = error.localizedDescription
            guard message.contains("PGRST204"), message.contains("business_date") else {
                throw error
            }
            payload.removeValue(forKey: "business_date")
            _ = try await sendSupabaseRequest(
                method: "POST",
                endpoint: "register_sessions",
                queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
                payload: payload
            )
        }
        return true
    }

    func fetchRegisterSessionsFromSupabase() async throws -> [[String: Any]] {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        let branchId = try activeOperationalBranchId()
        let data = try await sendSupabaseRequest(
            method: "GET",
            endpoint: "register_sessions",
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)"),
                URLQueryItem(name: "branch_id", value: "eq.\(branchId)"),
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

    /// Result of uploading a shift report after ensuring parent FK rows exist.
    struct ShiftReportUploadResult {
        let success: Bool
        /// Parent employee was created/upserted on the server during this upload.
        let createdGeneratedByEmployee: Bool
        /// Parent register session was created/upserted on the server during this upload.
        let createdRegisterSession: Bool
    }

    /// Uploads a Z/X shift report.
    ///
    /// Policy when `employees` / `register_sessions` rows are missing on the server:
    /// - **Create/upsert** those parent rows first (from local SwiftData).
    /// - Then upload `shift_reports` with the real FK ids attached.
    @discardableResult
    func uploadShiftReport(_ report: ShiftReport) async throws -> Bool {
        try await uploadShiftReportDetailed(report).success
    }

    func uploadShiftReportDetailed(_ report: ShiftReport) async throws -> ShiftReportUploadResult {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        let branchId = try activeOperationalBranchId()

        var payload: [String: Any] = [
            "id": report.id.uuidString.lowercased(),
            "merchant_id": merchantId,
            "branch_id": branchId,
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

        var createdGeneratedByEmployee = false
        var createdRegisterSession = false

        if let session = report.registerSession, !session.isDeleted {
            let ensured = try await ensureRegisterSessionOnServer(session)
            if ensured.ready {
                payload["register_session_id"] = session.id.uuidString.lowercased()
                createdRegisterSession = ensured.created
            } else {
                throw NetworkError.serverError(
                    "shift_reports: could not create register_sessions row \(session.id.uuidString.lowercased())"
                )
            }
        }

        if let employee = report.generatedByEmployee, !employee.isDeleted {
            let ensured = try await ensureEmployeeOnServer(employee)
            if ensured.ready {
                payload["generated_by_employee_id"] = employee.id.uuidString.lowercased()
                createdGeneratedByEmployee = ensured.created
            } else {
                throw NetworkError.serverError(
                    "shift_reports: could not create employees row \(employee.id.uuidString.lowercased())"
                )
            }
        }

        _ = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "shift_reports",
            queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
            payload: payload
        )
        return ShiftReportUploadResult(
            success: true,
            createdGeneratedByEmployee: createdGeneratedByEmployee,
            createdRegisterSession: createdRegisterSession
        )
    }

    /// Ensures a register session row exists remotely; creates it from local data if missing.
    func ensureRegisterSessionOnServer(_ session: RegisterSession) async throws -> (ready: Bool, created: Bool) {
        if await remoteRowExists(endpoint: "register_sessions", id: session.id) {
            if !session.isSynced {
                session.isSynced = true
                session.updatedAt = Date()
            }
            return (true, false)
        }
        let uploaded = try await uploadRegisterSession(session)
        if uploaded {
            session.isSynced = true
            session.updatedAt = Date()
        }
        return (uploaded, uploaded)
    }

    /// Ensures an employee row exists remotely; creates user (if needed) + employee from local data.
    func ensureEmployeeOnServer(_ employee: Employee) async throws -> (ready: Bool, created: Bool) {
        if await remoteRowExists(endpoint: "employees", id: employee.id) {
            if !employee.isSynced {
                employee.isSynced = true
                employee.updatedAt = Date()
            }
            return (true, false)
        }

        // Employees sync normally waits for User — mirror that here so username/role land first.
        if let user = employee.user, !user.isDeleted {
            if !(await remoteRowExists(endpoint: "users", id: user.id)) {
                _ = try await uploadUser(user)
            }
            user.isSynced = true
            user.updatedAt = Date()
        }

        let uploaded = try await uploadEmployee(employee: employee)
        guard uploaded else { return (false, false) }
        employee.isSynced = true
        employee.updatedAt = Date()
        // Confirm the row is actually queryable before attaching the FK.
        let ready = await remoteRowExists(endpoint: "employees", id: employee.id)
        return (ready, true)
    }

    /// Read-only existence probe.
    func remoteRowExists(endpoint: String, id: UUID) async -> Bool {
        do {
            let data = try await sendSupabaseRequest(
                method: "GET",
                endpoint: endpoint,
                queryItems: [
                    URLQueryItem(name: "id", value: "eq.\(id.uuidString.lowercased())"),
                    URLQueryItem(name: "select", value: "id"),
                    URLQueryItem(name: "limit", value: "1")
                ]
            )
            let rows = (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
            return !rows.isEmpty
        } catch {
            return false
        }
    }

    func fetchEmployees() async throws -> [[String: Any]] {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        let branchId = try activeOperationalBranchId()
        let data = try await sendSupabaseRequest(method: "GET", endpoint: "employees", queryItems: [
            URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)"),
            URLQueryItem(name: "branch_id", value: "eq.\(branchId)"),
            URLQueryItem(name: "is_deleted", value: "eq.false")
        ])
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw NSError(
                domain: "AlphaPos.EmployeeSync",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid employees response"]
            )
        }
        return rows
    }

    func fetchEmployeeShifts() async throws -> [[String: Any]] {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        let branchId = try activeOperationalBranchId()
        let data = try await sendSupabaseRequest(method: "GET", endpoint: "employee_shifts", queryItems: [
            URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)"),
            URLQueryItem(name: "branch_id", value: "eq.\(branchId)")
        ])
        return (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
    }
}
