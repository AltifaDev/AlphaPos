import Foundation
import CryptoKit
import SwiftData

extension NetworkManager {
    // MARK: - Dining Area Sync
    func fetchDiningAreas() async throws -> [[String: Any]] {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        let branchId = BranchContext.shared.activeBranchIDString
        let data = try await sendSupabaseRequest(method: "GET", endpoint: "dining_areas", queryItems: [
            URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)"),
            URLQueryItem(name: "branch_id", value: "eq.\(branchId)"),
            URLQueryItem(name: "order", value: "sort_order.asc,floor_number.asc")
        ])
        return (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
    }

    func uploadDiningArea(_ area: FloorData) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        let payload: [String: Any] = [
            "id": area.uuid.uuidString.lowercased(), "merchant_id": merchantId,
            "branch_id": area.branchId, "floor_number": area.floorNumber,
            "name": area.name, "sort_order": area.sortOrder,
            "is_active": area.isActive, "is_deleted": area.isDeleted,
            "updated_at": NetworkManager.iso8601.string(from: area.updatedAt)
        ]
        do {
            _ = try await sendSupabaseRequest(method: "POST", endpoint: "dining_areas",
                queryItems: [URLQueryItem(name: "on_conflict", value: "id")], payload: payload)
            return true
        } catch {
            if error.localizedDescription.contains("dining_areas_merchant_id_branch_id_floor_number_key") || error.localizedDescription.contains("23505") {
                _ = try await sendSupabaseRequest(method: "PATCH", endpoint: "dining_areas",
                    queryItems: [
                        URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)"),
                        URLQueryItem(name: "branch_id", value: "eq.\(area.branchId)"),
                        URLQueryItem(name: "floor_number", value: "eq.\(area.floorNumber)")
                    ],
                    payload: [
                        "name": area.name,
                        "sort_order": area.sortOrder,
                        "is_active": area.isActive,
                        "is_deleted": area.isDeleted,
                        "updated_at": NetworkManager.iso8601.string(from: area.updatedAt)
                    ])
                return true
            }
            throw error
        }
    }

    // MARK: - Floor Plan Image Sync
    func fetchFloorPlanImages() async throws -> [[String: Any]] {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        let branchId = BranchContext.shared.activeBranchIDString
        var queryItems = [
            URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)"),
            URLQueryItem(name: "is_deleted", value: "eq.false")
        ]
        // branch_id is a UUID column. Legacy "default_branch" placeholders
        // must never be sent as a PostgREST UUID filter.
        if UUID(uuidString: branchId) != nil {
            queryItems.append(URLQueryItem(name: "branch_id", value: "eq.\(branchId)"))
        }
        let data = try await sendSupabaseRequest(
            method: "GET",
            endpoint: "floor_plan_images",
            queryItems: queryItems
        )
        return (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
    }
    
    func uploadFloorPlanMedia(data: Data, fileName: String) async throws -> String {
        // Refresh token if needed before uploading
        await MerchantAuthManager.shared.refreshTokenIfNeeded()
        
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        let objectPath = "\(merchantId.lowercased())/floor_plans/\(fileName)"
        var uploadURL = config.supabaseURL
        for component in ["storage", "v1", "object", "product-media"] + objectPath.split(separator: "/").map(String.init) {
            uploadURL.appendPathComponent(component)
        }

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        let token = MerchantAuthManager.shared.authorizationToken ?? anonKey
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.setValue("true", forHTTPHeaderField: "x-upsert")
        request.httpBody = data
        request.timeoutInterval = 60

        let (responseData, response) = try await AppNetworkTransport.data(for: request, purpose: .cloudData)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.serverError("Invalid HTTP response")
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: responseData, encoding: .utf8) ?? "Storage upload failed"
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 || message.contains("PGRST301") || message.contains("AccessDenied") || message.contains("violates row-level security") || message.contains("Unauthorized") {
                #if DEBUG
                print("NetworkManager: Detected authentication/RLS error during storage upload. Clearing token...")
                #endif
                // Preserve the local workspace on an expired/rejected token.
                MerchantAuthManager.shared.logout(removeLocalData: false)
            }
            throw NetworkError.serverError(message)
        }

        var publicURL = config.supabaseURL
        for component in ["storage", "v1", "object", "public", "product-media"] + objectPath.split(separator: "/").map(String.init) {
            publicURL.appendPathComponent(component)
        }
        return publicURL.absoluteString
    }
    
    func downloadFloorPlanMedia(fileName: String) async throws -> Data {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        let objectPath = "\(merchantId.lowercased())/floor_plans/\(fileName)"
        var publicURL = config.supabaseURL
        for component in ["storage", "v1", "object", "public", "product-media"] + objectPath.split(separator: "/").map(String.init) {
            publicURL.appendPathComponent(component)
        }
        
        let (data, response) = try await AppNetworkTransport.data(from: publicURL, purpose: .remoteMedia)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.serverError("Failed to download floor plan media")
        }
        return data
    }

    func uploadFloorPlanImage(floorPlan: FloorPlanImage) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        let branchId = floorPlan.branchId.isEmpty
            ? (BranchContext.shared.activeBranchIDString)
            : floorPlan.branchId
        guard UUID(uuidString: branchId) != nil else {
            // Defer until branch bootstrap selects a real UUID.
            return false
        }
        let payload: [String: Any] = [
            "id": floorPlan.id.uuidString.lowercased(),
            "merchant_id": merchantId,
            "branch_id": branchId,
            "dining_area_id": floorPlan.diningAreaId.uuidString.lowercased(),
            "image_filename": floorPlan.imageFilename,
            "is_deleted": floorPlan.isDeleted,
            "scale": floorPlan.scale,
            "offset_x": floorPlan.offsetX,
            "offset_y": floorPlan.offsetY,
            "updated_at": NetworkManager.iso8601.string(from: floorPlan.updatedAt)
        ]
        _ = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "floor_plan_images",
            queryItems: [URLQueryItem(name: "on_conflict", value: "merchant_id,branch_id,dining_area_id")],
            payload: payload
        )
        return true
    }

    func uploadTableSession(session: TableSession) async throws -> Bool {

        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        let branchId = try activeOperationalBranchId()
        var payload: [String: Any] = [
            "id": session.id.uuidString.lowercased(),
            "table_number": session.table?.tableNumber ?? "",
            "session_token": session.sessionToken,
            "is_active": session.isActive ? 1 : 0,
            "guest_count": session.guestCount,
            "cashier_name": session.cashierName,
            "created_at": NetworkManager.iso8601.string(from: session.startedAt),
            "ended_at": session.endedAt.map { NetworkManager.iso8601.string(from: $0) } ?? NSNull(),
            "merchant_id": merchantId,
            "branch_id": branchId
        ]
        if session.rowVersion > 0 { payload["expected_row_version"] = session.rowVersion }

        // A CAS conflict cannot be retried with the same stale row version. Refresh
        // it first, then retry at most twice with exponential backoff and jitter. This bounds
        // load during multi-device conflicts and prevents a tight retry loop or log flood.
        for attempt in 1...3 {
            do {
                let data = try await sendSupabaseRequest(
                    method: "POST",
                    endpoint: "rpc/upsert_table_session_cas",
                    payload: ["p_session": payload]
                )
                if let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    session.rowVersion = response["row_version"] as? Int
                        ?? (response["row_version"] as? NSNumber)?.intValue
                        ?? session.rowVersion
                }
                break
            } catch {
                let message = String(describing: error)
                guard attempt < 3, message.contains("table_session_conflict") else { throw error }

                // Query by ID first, then fallback to session_token
                var queryItems = [
                    URLQueryItem(name: "id", value: "eq.\(session.id.uuidString.lowercased())"),
                    URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)"),
                    URLQueryItem(name: "select", value: "row_version"),
                    URLQueryItem(name: "limit", value: "1")
                ]
                var rows = try? await sendSupabaseRequest(
                    method: "GET",
                    endpoint: "table_sessions",
                    queryItems: queryItems
                )
                if rows == nil || (try? JSONSerialization.jsonObject(with: rows!) as? [[String: Any]])?.isEmpty == true {
                    queryItems[0] = URLQueryItem(name: "session_token", value: "eq.\(session.sessionToken)")
                    rows = try? await sendSupabaseRequest(
                        method: "GET",
                        endpoint: "table_sessions",
                        queryItems: queryItems
                    )
                }

                if let data = rows,
                   let response = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                   let row = response.first,
                   let latest = row["row_version"] as? Int ?? (row["row_version"] as? NSNumber)?.intValue {
                    session.rowVersion = latest
                    payload["expected_row_version"] = latest
                }

                // Exponential backoff: 500ms * 2^(attempt-1) + jitter (0-250ms)
                let baseDelay = 500_000_000 * UInt64(1 << (attempt - 1))
                let jitter = UInt64.random(in: 0...250_000_000)
                let delay = baseDelay + jitter
                try await Task.sleep(nanoseconds: delay)
            }
        }

        // When a new active session is created, migrate any active orders on this table
        // that have no session_token (or belong to a previous session) to use this session's token.
        // This ensures iPhone Staff app can always find orders via session_token lookup.
        if session.isActive, let tableNumber = session.table?.tableNumber, !tableNumber.isEmpty {
            do {
                _ = try await sendSupabaseRequest(
                    method: "PATCH",
                    endpoint: "orders",
                    queryItems: [
                        URLQueryItem(name: "table_number", value: "eq.\(tableNumber)"),
                        URLQueryItem(name: "status", value: "not.in.(completed,cancelled)"),
                        URLQueryItem(name: "session_token", value: "is.null")
                    ],
                    payload: ["session_token": session.sessionToken]
                )
                #if DEBUG
                print("NetworkManager [Session]: Migrated null-token orders on table \(tableNumber) to session \(session.sessionToken)")
                #endif
            } catch {
                // Non-fatal: orders will still be visible via timestamp fallback
                #if DEBUG
                print("NetworkManager [Session]: Order migration skipped: \(error.localizedDescription)")
                #endif
            }
        }

        return true
    }

    func deleteTableSession(id: UUID) async throws -> Bool {
        _ = try await sendSupabaseRequest(
            method: "DELETE",
            endpoint: "table_sessions",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(id.uuidString.lowercased())")]
        )
        return true
    }

    func uploadEmployee(employee: Employee) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        let branchId = UUID(uuidString: employee.branchId) != nil ? employee.branchId : try activeOperationalBranchId()
        let username = employee.user?.username ?? "staff_\(employee.id.uuidString.prefix(8).lowercased())"
        let role = employee.user?.role?.name ?? "Staff"


        var payload: [String: Any] = [
            "id": employee.id.uuidString.lowercased(),
            "merchant_id": merchantId,
            "branch_id": branchId,
            "first_name": employee.firstName,
            "last_name": employee.lastName,
            "phone": employee.phone ?? "",
            "national_id": employee.nationalId ?? "",
            "employment_type": employee.employmentType,
            "pay_rate": employee.payRate,
            "username": username,
            "role": role,
            "staff_app_enabled": employee.staffAppEnabled,
            "updated_at": NetworkManager.iso8601.string(from: employee.updatedAt)
        ]

        // Login credentials belong exclusively to users.pin_code_hash. The
        // legacy employees.pin_code column is varchar(100), while the current
        // salted/iterated hash can exceed that limit and used to reject the
        // entire employee update (including pay_rate).
        if let user = employee.user {
            let userById = try await sendSupabaseRequest(
                method: "GET",
                endpoint: "users",
                queryItems: [
                    URLQueryItem(name: "select", value: "id"),
                    URLQueryItem(name: "id", value: "eq.\(user.id.uuidString.lowercased())"),
                    URLQueryItem(name: "is_deleted", value: "eq.false"),
                    URLQueryItem(name: "limit", value: "1")
                ]
            )
            let userData: Data
            if let rows = try? JSONSerialization.jsonObject(with: userById) as? [[String: Any]],
               !rows.isEmpty {
                userData = userById
            } else {
                // Legacy fallback only. The production migration enforces one
                // active username per merchant, so this is deterministic.
                userData = try await sendSupabaseRequest(
                    method: "GET",
                    endpoint: "users",
                    queryItems: [
                        URLQueryItem(name: "select", value: "id"),
                        URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)"),
                        URLQueryItem(name: "username", value: "eq.\(user.username.lowercased())"),
                        URLQueryItem(name: "is_deleted", value: "eq.false"),
                        URLQueryItem(name: "limit", value: "1")
                    ]
                )
            }
            if let rows = try? JSONSerialization.jsonObject(with: userData) as? [[String: Any]],
               let remoteUserId = rows.first?["id"] as? String {
                payload["user_id"] = remoteUserId
            }
        }

        // PATCH must carry NULL for cleared optional fields. Omitting a key
        // leaves the old server value intact, which is then pulled back and
        // looks like the edit was reset.
        payload["bank_account_number"] = employee.bankAccountNumber ?? NSNull()
        payload["bank_name"] = employee.bankName ?? NSNull()
        payload["email"] = employee.email ?? NSNull()
        payload["address"] = employee.address ?? NSNull()
        payload["emergency_contact_name"] = employee.emergencyContactName ?? NSNull()
        payload["emergency_contact_phone"] = employee.emergencyContactPhone ?? NSNull()
        payload["date_of_birth"] = employee.dateOfBirth.map { NetworkManager.iso8601.string(from: $0) } ?? NSNull()
        if employee.faceEmbeddingNeedsRemoteClear {
            payload["face_registered_at"] = NSNull()
        } else if let faceRegisteredAt = employee.faceRegisteredAt {
            payload["face_registered_at"] = NetworkManager.iso8601.string(from: faceRegisteredAt)
        }
        payload["resigned_at"] = employee.resignedAt.map { NetworkManager.iso8601.string(from: $0) } ?? NSNull()
        payload["joined_at"] = NetworkManager.iso8601.string(from: employee.joinedAt)

        // Only send face_embedding when face was recently registered (within last 24h) or first upload
        // This prevents uploading large base64 binary on every sync cycle
        let faceIsNew = employee.faceRegisteredAt.map { Date().timeIntervalSince($0) < 86400 } ?? false
        if employee.faceEmbeddingNeedsRemoteClear {
            payload["face_embedding"] = NSNull()
        } else if let faceData = employee.faceEmbeddingData, faceIsNew {
            payload["face_embedding"] = faceData.base64EncodedString()
        }

        // Try PATCH first (update existing row by id) — avoids username uniqueness violation (23505)
        // that occurs when two local employees share a username but have different UUIDs.
        // PATCH on a non-existent id is a no-op (returns 0 rows), then fall through to POST/upsert.
        let patchData = try? await sendSupabaseRequest(
            method: "PATCH",
            endpoint: "employees",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(employee.id.uuidString.lowercased())")],
            payload: payload)
        let patchedCount = (try? JSONSerialization.jsonObject(with: patchData ?? Data()) as? [[String: Any]])?.count ?? 0
        if patchedCount > 0 { return true }

        _ = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "employees",
            // on_conflict "id" for new employees (PATCH returned 0 rows above)
            queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
            payload: payload
        )
        return true
    }

    func uploadEmployeeShift(shift: EmployeeShift) async throws -> Bool {
        guard let employeeId = shift.employee?.id else { return false }
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        let payload: [String: Any] = [
            "id": shift.id.uuidString.lowercased(),
            "employee_id": employeeId.uuidString.lowercased(),
            "merchant_id": merchantId,
            "scheduled_start": NetworkManager.iso8601.string(from: shift.scheduledStart),
            "scheduled_end": NetworkManager.iso8601.string(from: shift.scheduledEnd),
            "role": shift.role ?? "",
            "notes": shift.notes ?? "",
            "shift_type": shiftType(for: shift.scheduledStart),
            "is_deleted": shift.isDeleted,
            "updated_at": NetworkManager.iso8601.string(from: shift.updatedAt)
        ]
        _ = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "employee_shifts",
            queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
            payload: payload
        )
        return true
    }

    private func shiftType(for start: Date) -> String {
        let hour = Calendar.current.component(.hour, from: start)
        switch hour {
        case 5..<12: return "morning"
        case 12..<17: return "afternoon"
        case 17..<22: return "evening"
        default: return "night"
        }
    }

    func uploadMerchant(
        id: UUID,
        name: String,
        email: String,
        kitchenWorkflowRequired: Bool,
        isTableSystemEnabled: Bool = true,
        isWebOrderingEnabled: Bool = true,
        phone: String? = nil,
        website: String? = nil,
        address: String? = nil,
        taxId: String? = nil,
        branchCode: String? = nil,
        taxRate: Double? = nil,
        taxType: String? = nil,
        serviceChargeRate: Double? = nil,
        receiptHeader: String? = nil,
        receiptFooter: String? = nil,
        promptPayNumber: String? = nil,
        logoUrl: String? = nil
    ) async throws -> Bool {
        var payload: [String: Any] = [
            "id": id.uuidString.lowercased(),
            "name": name,
            "email": email,
            "kitchen_workflow_required": kitchenWorkflowRequired,
            "is_table_system_enabled": isTableSystemEnabled,
            "is_web_ordering_enabled": isWebOrderingEnabled
        ]

        if let phone = phone { payload["phone"] = phone }
        if let website = website { payload["website"] = website }
        if let address = address { payload["address_street"] = address }
        if let taxId = taxId { payload["tax_id"] = taxId }
        if let branchCode = branchCode { payload["branch_code"] = branchCode }
        if let taxRate = taxRate { payload["tax_rate"] = taxRate }
        if let taxType = taxType { payload["tax_type"] = taxType }
        if let serviceChargeRate = serviceChargeRate { payload["service_charge_rate"] = serviceChargeRate }
        if let receiptHeader = receiptHeader { payload["receipt_header"] = receiptHeader }
        if let receiptFooter = receiptFooter { payload["receipt_footer"] = receiptFooter }
        if let promptPayNumber = promptPayNumber { payload["promptpay_number"] = promptPayNumber }
        if let logoUrl = logoUrl { payload["logo_url"] = logoUrl }

        _ = try await sendSupabaseRequest(
            // Use PATCH (UPDATE) instead of POST (INSERT/UPSERT) for merchants.
            // The anon role does NOT have INSERT privilege on merchants (42501 error).
            // Merchant rows are created via admin/edge function — the iPad only needs to UPDATE its own row.
            // RLS policy ensures each merchant can only PATCH their own row (id = auth.uid()).
            method: "PATCH",
            endpoint: "merchants",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(id.uuidString.lowercased())")],
            payload: payload
        )
        return true
    }

    func deleteMerchantOnServer() async throws -> Bool {
        guard let token = MerchantAuthManager.shared.userAccessToken else {
            throw NetworkError.serverError("Please sign in again before deleting the account")
        }
        let url = URL(string: config.supabaseURL.absoluteString + "/functions/v1/delete-account")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["confirmation": "DELETE"])
        let (data, response) = try await AppNetworkTransport.data(for: request, purpose: .cloudData)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw NetworkError.serverError(AuthService.serverMessage(from: data, fallback: "Account deletion failed"))
        }
        return true
    }

    func wipeRemoteTransactionsAndSessions() async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        guard !merchantId.isEmpty else {
            throw NetworkError.serverError("No active merchant configured")
        }
        let merchantFilter = URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)")
        // 1. Delete all table sessions for this merchant
        _ = try await sendSupabaseRequest(method: "DELETE", endpoint: "table_sessions", queryItems: [merchantFilter])
        // 1.5. Delete all payments first (required due to ON DELETE RESTRICT on orders constraint)
        _ = try await sendSupabaseRequest(method: "DELETE", endpoint: "payments", queryItems: [merchantFilter])
        // 2. Delete all orders
        _ = try await sendSupabaseRequest(method: "DELETE", endpoint: "orders", queryItems: [merchantFilter])
        // 3. Delete all service requests
        _ = try await sendSupabaseRequest(method: "DELETE", endpoint: "service_requests", queryItems: [merchantFilter])
        // 4. Reset all restaurant tables status to vacant
        _ = try await sendSupabaseRequest(method: "PATCH", endpoint: "restaurant_tables", queryItems: [merchantFilter], payload: ["status": "vacant"])
        // 5. Delete all floor plan images
        _ = try await sendSupabaseRequest(method: "DELETE", endpoint: "floor_plan_images", queryItems: [merchantFilter])
        return true
    }

    /// Deletes only the operator-selected operational data groups for the
    /// active merchant. Dependency order is intentional: checkout/payment
    /// rows must be removed before their orders, and cash movements before
    /// register sessions.
    func wipeRemoteOperationalData(categories: [String]) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        guard !merchantId.isEmpty else {
            throw NetworkError.serverError("No active merchant configured")
        }
        let selected = Set(categories)
        let merchantFilter = [URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)")]

        if selected.contains("payments") || selected.contains("orders") {
            _ = try await sendSupabaseRequest(method: "DELETE", endpoint: "payment_attempts", queryItems: merchantFilter)
            _ = try await sendSupabaseRequest(method: "DELETE", endpoint: "checkout_sessions", queryItems: merchantFilter)
            _ = try await sendSupabaseRequest(method: "DELETE", endpoint: "payments", queryItems: merchantFilter)
        }
        if selected.contains("orders") {
            _ = try await sendSupabaseRequest(method: "DELETE", endpoint: "orders", queryItems: merchantFilter)
        }
        if selected.contains("table_sessions") {
            _ = try await sendSupabaseRequest(method: "DELETE", endpoint: "service_requests", queryItems: merchantFilter)
            _ = try await sendSupabaseRequest(method: "DELETE", endpoint: "table_sessions", queryItems: merchantFilter)
            _ = try await sendSupabaseRequest(
                method: "PATCH",
                endpoint: "restaurant_tables",
                queryItems: merchantFilter,
                payload: ["status": "vacant"]
            )
        }
        if selected.contains("registers") {
            _ = try await sendSupabaseRequest(method: "DELETE", endpoint: "cash_movements", queryItems: merchantFilter)
            _ = try await sendSupabaseRequest(method: "DELETE", endpoint: "register_sessions", queryItems: merchantFilter)
        }
        return true
    }
}
