import Foundation
import CryptoKit
import SwiftData

extension NetworkManager {
    // MARK: - Floor Plan Image Sync
    func fetchFloorPlanImages() async throws -> [[String: Any]] {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        let data = try await sendSupabaseRequest(method: "GET", endpoint: "floor_plan_images", queryItems: [
            URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)"),
            URLQueryItem(name: "is_deleted", value: "eq.false")
        ])
        return (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
    }
    
    func uploadFloorPlanMedia(data: Data, fileName: String) async throws -> String {
        // Refresh token if needed before uploading
        await MerchantAuthManager.shared.refreshTokenIfNeeded()
        
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        let objectPath = "\(merchantId.lowercased())/floor_plans/\(fileName)"
        var uploadURL = config.supabaseURL
        for component in ["storage", "v1", "object", "product-media"] + objectPath.split(separator: "/").map(String.init) {
            uploadURL.appendPathComponent(component)
        }

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        let token = MerchantAuthManager.shared.currentToken ?? anonKey
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.setValue("true", forHTTPHeaderField: "x-upsert")
        request.httpBody = data
        request.timeoutInterval = 60

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.serverError("Invalid HTTP response")
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: responseData, encoding: .utf8) ?? "Storage upload failed"
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 || message.contains("PGRST301") || message.contains("AccessDenied") || message.contains("violates row-level security") || message.contains("Unauthorized") {
                #if DEBUG
                print("NetworkManager: Detected authentication/RLS error during storage upload. Clearing token...")
                #endif
                MerchantAuthManager.shared.logout()
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
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        let objectPath = "\(merchantId.lowercased())/floor_plans/\(fileName)"
        var publicURL = config.supabaseURL
        for component in ["storage", "v1", "object", "public", "product-media"] + objectPath.split(separator: "/").map(String.init) {
            publicURL.appendPathComponent(component)
        }
        
        let (data, response) = try await URLSession.shared.data(from: publicURL)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.serverError("Failed to download floor plan media")
        }
        return data
    }

    func uploadFloorPlanImage(floorPlan: FloorPlanImage) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        let payload: [String: Any] = [
            "id": floorPlan.id.uuidString.lowercased(),
            "merchant_id": merchantId,
            "floor": floorPlan.floor,
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
            queryItems: [URLQueryItem(name: "on_conflict", value: "merchant_id,floor")],
            payload: payload
        )
        return true
    }

    func uploadTableSession(session: TableSession) async throws -> Bool {

        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        var payload: [String: Any] = [
            "id": session.id.uuidString.lowercased(),
            "table_number": session.table?.tableNumber ?? "",
            "session_token": session.sessionToken,
            "is_active": session.isActive ? 1 : 0,
            "guest_count": session.guestCount,
            "created_at": NetworkManager.iso8601.string(from: session.startedAt),
            "merchant_id": merchantId
        ]

        if let endedAt = session.endedAt {
            payload["ended_at"] = NetworkManager.iso8601.string(from: endedAt)
        }

        _ = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "table_sessions",
            // upsert on session_token (has unique constraint) to avoid duplicate key errors
            queryItems: [URLQueryItem(name: "on_conflict", value: "session_token")],
            payload: payload
        )

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
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        let username = employee.user?.username ?? "staff_\(employee.id.uuidString.prefix(8).lowercased())"
        // WARNING: pinCodeHash should already be hashed client-side before reaching this point.
        // Do NOT send raw PINs here. Verify that employee.user?.pinCodeHash contains a bcrypt/SHA hash,
        // not a plaintext PIN. The default fallback "0000" is a placeholder — never ship this in production.
        let pinCode = employee.user?.pinCodeHash ?? "0000"
        let role = employee.user?.role?.name ?? "Staff"


        var payload: [String: Any] = [
            "id": employee.id.uuidString.lowercased(),
            "merchant_id": merchantId,
            "first_name": employee.firstName,
            "last_name": employee.lastName,
            "phone": employee.phone ?? "",
            "national_id": employee.nationalId ?? "",
            "employment_type": employee.employmentType,
            "pay_rate": employee.payRate,
            "username": username,
            "pin_code": pinCode,
            "role": role,
            "updated_at": NetworkManager.iso8601.string(from: employee.updatedAt)
        ]

        if let bankAccountNumber = employee.bankAccountNumber { payload["bank_account_number"] = bankAccountNumber }
        if let bankName = employee.bankName { payload["bank_name"] = bankName }
        if let email = employee.email { payload["email"] = email }
        if let address = employee.address { payload["address"] = address }
        if let emergencyContactName = employee.emergencyContactName { payload["emergency_contact_name"] = emergencyContactName }
        if let emergencyContactPhone = employee.emergencyContactPhone { payload["emergency_contact_phone"] = emergencyContactPhone }
        if let dateOfBirth = employee.dateOfBirth { payload["date_of_birth"] = NetworkManager.iso8601.string(from: dateOfBirth) }
        if let faceRegisteredAt = employee.faceRegisteredAt { payload["face_registered_at"] = NetworkManager.iso8601.string(from: faceRegisteredAt) }
        if let resignedAt = employee.resignedAt { payload["resigned_at"] = NetworkManager.iso8601.string(from: resignedAt) }
        payload["joined_at"] = NetworkManager.iso8601.string(from: employee.joinedAt)

        // Only send face_embedding when face was recently registered (within last 24h) or first upload
        // This prevents uploading large base64 binary on every sync cycle
        let faceIsNew = employee.faceRegisteredAt.map { Date().timeIntervalSince($0) < 86400 } ?? false
        if faceIsNew, let faceData = employee.faceEmbeddingData {
            payload["face_embedding"] = faceData.base64EncodedString()
        }

        _ = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "employees",
            queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
            payload: payload
        )
        return true
    }

    func uploadEmployeeShift(shift: EmployeeShift) async throws -> Bool {
        guard let employeeId = shift.employee?.id else { return false }
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        let payload: [String: Any] = [
            "id": shift.id.uuidString.lowercased(),
            "employee_id": employeeId.uuidString.lowercased(),
            "merchant_id": merchantId,
            "scheduled_start": NetworkManager.iso8601.string(from: shift.scheduledStart),
            "scheduled_end": NetworkManager.iso8601.string(from: shift.scheduledEnd),
            "role": shift.role ?? "",
            "notes": shift.notes ?? "",
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
        promptPayNumber: String? = nil
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

        _ = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "merchants",
            queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
            payload: payload
        )
        return true
    }

    func deleteMerchantOnServer() async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        _ = try await sendSupabaseRequest(
            method: "DELETE",
            endpoint: "merchants",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(merchantId)")]
        )
        return true
    }

    func wipeRemoteTransactionsAndSessions() async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
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
}
