// NetworkService+Timecard.swift
// Timecards, PIN verification, employees, and face registration.

import Foundation
import OSLog

enum PinVerificationError: Error {
    case invalidServerResponse
}

extension NetworkService {
    private static var pinLogger: Logger {
        Logger(subsystem: "com.alphapos.staff", category: "Authentication")
    }
    func fetchEmployees() async throws -> [Employee] {
        guard !activeMerchantId.isEmpty else { throw StaffServiceError.missingMerchantSession }
        guard !StaffSessionContext.branchId.isEmpty else { throw StaffServiceError.missingBranchSession }
        // SECURITY: the database RPC is the single eligibility boundary. It
        // returns only active, branch-scoped, PIN-enabled profiles and never
        // exposes credential hashes to the device.
        let data = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "rpc/get_staff_login_profiles",
            payload: [:]
        )
        let decoder = JSONDecoder()
        do {
            let profiles = try decoder.decode([Employee].self, from: data)
            // The RPC is authoritative. Defensive ID de-duplication prevents a
            // malformed response from producing duplicate SwiftUI identities.
            var seen = Set<String>()
            return profiles.filter { seen.insert($0.id.lowercased()).inserted }
        } catch {
            throw NetworkError.serverError("Invalid staff login profile response")
        }
    }

    // NOTE: registerEmployeeFace() is retained for future use when a real
    // biometric pipeline (Vision/ARKit) is implemented. Not called from any UI currently.
    func registerEmployeeFace(employeeId: String, faceEmbedding: String) async throws -> Bool {
        let formatter = ISO8601DateFormatter()
        let nowStr = formatter.string(from: Date())
        let payload: [String: Any] = [
            "face_embedding": faceEmbedding,
            "face_registered_at": nowStr
        ]
        _ = try await sendSupabaseRequest(
            method: "PATCH",
            endpoint: "employees",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(employeeId)")],
            payload: payload
        )
        return true
    }

    func verifyPin(employeeId: String, pinDigits: String) async throws -> Bool {
        guard StaffPINPolicy.isValid(pinDigits) else { return false }
        // PIN hashes never leave the database. The RPC resolves the employee and
        // canonical user credential, verifies the hash, and returns one Boolean.
        let startedAt = Date()
        do {
            let data = try await sendSupabaseRequest(
                method: "POST",
                endpoint: "rpc/verify_staff_pin",
                payload: ["p_employee_id": employeeId, "p_pin": pinDigits],
                timeoutInterval: 5.0
            )
            guard let verified = try? JSONDecoder().decode(Bool.self, from: data) else {
                throw PinVerificationError.invalidServerResponse
            }
            let totalMilliseconds = Int(Date().timeIntervalSince(startedAt) * 1_000)
            Self.pinLogger.info("staff_auth rpc_total_ms=\(totalMilliseconds, privacy: .public) verified=\(verified, privacy: .public)")
            return verified
        } catch {
            let totalMilliseconds = Int(Date().timeIntervalSince(startedAt) * 1_000)
            Self.pinLogger.error("staff_auth rpc_failed_ms=\(totalMilliseconds, privacy: .public) error=\(String(describing: error), privacy: .public)")
            throw error
        }
    }

    func fetchTimecards(for employeeId: String) async throws -> [Timecard] {
        guard !activeMerchantId.isEmpty else { throw StaffServiceError.missingMerchantSession }
        guard !StaffSessionContext.branchId.isEmpty else { throw StaffServiceError.missingBranchSession }
        let data = try await sendSupabaseRequest(method: "GET", endpoint: "timecards", queryItems: [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "merchant_id", value: "eq.\(activeMerchantId)"),
            URLQueryItem(name: "branch_id", value: "eq.\(StaffSessionContext.branchId)"),
            URLQueryItem(name: "employee_id", value: "eq.\(employeeId)"),
            URLQueryItem(name: "order", value: "clock_in.desc")
        ])
        guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw NetworkError.serverError("Invalid timecard response")
        }
        let formatter = ISO8601DateFormatter()
        return jsonArray.map { dict in
            let clockInStr = dict["clock_in"] as? String ?? ""
            let clockInVal = formatter.date(from: clockInStr)?.timeIntervalSince1970 ?? 0.0
            
            let clockOutStr = dict["clock_out"] as? String
            let clockOutVal = clockOutStr.flatMap { formatter.date(from: $0)?.timeIntervalSince1970 }
            
            return Timecard(
                id: dict["id"] as? String ?? "",
                employeeId: dict["employee_id"] as? String ?? "",
                employeeName: dict["employee_name"] as? String ?? "",
                clockIn: clockInVal,
                clockOut: clockOutVal,
                breakDurationMinutes: dict["break_duration"] as? Int ?? 0,
                overtimeMinutes: dict["overtime_minutes"] as? Int ?? 0,
                status: dict["status"] as? String ?? "approved",
                notes: dict["notes"] as? String,
                clockInFaceConfidence: dict["clock_in_confidence"] as? Double,
                clockOutFaceConfidence: dict["clock_out_confidence"] as? Double,
                clockInSelfieUrl: dict["clock_in_selfie_url"] as? String,
                clockOutSelfieUrl: dict["clock_out_selfie_url"] as? String,
                shiftId: dict["shift_id"] as? String
            )
        }
    }

    /// Work authorization is based on an open timecard, never on the presence
    /// of a scheduled shift. This keeps authentication and scheduling separate
    /// while giving POS actions one consistent attendance check.
    func hasActiveTimecard(for employeeId: String) async throws -> Bool {
        guard !activeMerchantId.isEmpty else { throw StaffServiceError.missingMerchantSession }
        guard !StaffSessionContext.branchId.isEmpty else { throw StaffServiceError.missingBranchSession }
        let data = try await sendSupabaseRequest(method: "GET", endpoint: "timecards", queryItems: [
            URLQueryItem(name: "select", value: "id"),
            URLQueryItem(name: "merchant_id", value: "eq.\(activeMerchantId)"),
            URLQueryItem(name: "branch_id", value: "eq.\(StaffSessionContext.branchId)"),
            URLQueryItem(name: "employee_id", value: "eq.\(employeeId)"),
            URLQueryItem(name: "clock_out", value: "is.null"),
            URLQueryItem(name: "limit", value: "1")
        ])
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw NetworkError.serverError("Invalid active-timecard response")
        }
        return !rows.isEmpty
    }

    func uploadTimecard(timecard: Timecard) async throws -> Bool {
        let merchantId = self.activeMerchantId
        let branchId = StaffSessionContext.branchId
        guard !merchantId.isEmpty else { throw StaffServiceError.missingMerchantSession }
        guard !branchId.isEmpty else { throw StaffServiceError.missingBranchSession }
        let formatter = ISO8601DateFormatter()
        let clockInStr = formatter.string(from: Date(timeIntervalSince1970: timecard.clockIn))
        
        var payload: [String: Any] = [
            "id": timecard.id,
            "employee_id": timecard.employeeId,
            "employee_name": timecard.employeeName,
            "clock_in": clockInStr,
            "break_duration": timecard.breakDurationMinutes,
            "overtime_minutes": timecard.overtimeMinutes,
            "status": timecard.status,
            "notes": timecard.notes ?? "",
            "clock_in_confidence": timecard.clockInFaceConfidence ?? 0.0,
            "clock_out_confidence": timecard.clockOutFaceConfidence ?? 0.0,
            "merchant_id": merchantId,
            "branch_id": branchId,
            "shift_id": timecard.shiftId ?? NSNull()
        ]

        payload["clock_in_selfie_url"] = timecard.clockInSelfieUrl ?? NSNull()
        payload["clock_out_selfie_url"] = timecard.clockOutSelfieUrl ?? NSNull()
        
        if let clockOut = timecard.clockOut, clockOut > 0 {
            payload["clock_out"] = formatter.string(from: Date(timeIntervalSince1970: clockOut))
        } else {
            payload["clock_out"] = NSNull()
        }
        
        // Idempotent upsert — retry ปลอดภัย ไม่ duplicate
        _ = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "timecards",
            queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
            payload: payload)
        return true
    }

    /// Uploads a deliberately low-resolution evidence JPEG to a private bucket.
    /// The returned value is an object path, not a public URL.
    func uploadTimecardEvidence(_ jpegData: Data, employeeId: String, timecardId: String, event: String) async throws -> String {
        guard !activeMerchantId.isEmpty else { throw NetworkError.invalidResponse }
        await MerchantAuthManager.shared.refreshTokenIfNeeded()

        let safeEvent = event == "clock_out" ? "clock-out" : "clock-in"
        let objectPath = "\(activeMerchantId)/\(employeeId.lowercased())/\(timecardId.lowercased())/\(safeEvent).jpg"
        guard let projectURL = URL(string: baseURL.absoluteString.replacingOccurrences(of: "/rest/v1", with: "")) else {
            throw NetworkError.invalidResponse
        }
        var request = URLRequest(url: projectURL.appendingPathComponent("storage/v1/object/timecard-evidence/\(objectPath)"))
        request.httpMethod = "POST"
        request.httpBody = jpegData
        request.timeoutInterval = 20
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(authorizationToken)", forHTTPHeaderField: "Authorization")
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.setValue("true", forHTTPHeaderField: "x-upsert")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw NetworkError.serverError(String(data: data, encoding: .utf8) ?? "Evidence upload failed")
        }
        return objectPath
    }
}
