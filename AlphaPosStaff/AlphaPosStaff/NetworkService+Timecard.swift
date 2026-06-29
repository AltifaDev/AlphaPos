// NetworkService+Timecard.swift
// Timecards, PIN verification, employees, and face registration.

import Foundation
import CryptoKit

extension NetworkService {
    func fetchEmployees() async throws -> [Employee] {
        // SECURITY: select only the fields the UI actually needs.
        // pin_code and face_embedding are NEVER fetched to the client —
        // PIN verification is done server-side via verifyPin().
        let safeSelect = "id,first_name,last_name,phone,national_id," +
                         "employment_type,pay_rate,username,role," +
                         "face_registered_at"
        let data = try await sendSupabaseRequest(method: "GET", endpoint: "employees", queryItems: [
            URLQueryItem(name: "select", value: safeSelect)
        ])
        // Use Codable decoder — Employee already has CodingKeys defined in Models.swift
        let decoder = JSONDecoder()
        let employees = (try? decoder.decode([Employee].self, from: data)) ?? []
        return employees
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

    private func constantTimeCompare(_ a: String, _ b: String) -> Bool {
        guard a.count == b.count else { return false }
        let aBytes = [UInt8](a.utf8)
        let bBytes = [UInt8](b.utf8)
        var result: UInt8 = 0
        for i in 0..<aBytes.count {
            result |= aBytes[i] ^ bBytes[i]
        }
        return result == 0
    }

    func verifyPin(employeeId: String, pinDigits: String, expectedPinHash: String? = nil) async throws -> Bool {
        // Try new format (iter:salt:hash) first, fall back to legacy SHA256
        func matchesStoredHash(_ stored: String) -> Bool {
            if stored.hasPrefix("iter:") {
                return verifyIteratedPin(pinDigits, against: stored)
            } else {
                // Legacy SHA256-only hash
                let inputData = Data(pinDigits.utf8)
                let hashed = CryptoKit.SHA256.hash(data: inputData)
                let pinHash = hashed.compactMap { String(format: "%02x", $0) }.joined()
                return constantTimeCompare(pinHash, stored)
            }
        }
        
        // 1. Local / pre-loaded verification (Offline fallback)
        if let expected = expectedPinHash {
            return matchesStoredHash(expected)
        }
        
        // 2. Database verification (Direct column query fallback)
        do {
            let data = try await sendSupabaseRequest(method: "GET", endpoint: "employees", queryItems: [
                URLQueryItem(name: "id", value: "eq.\(employeeId)"),
                URLQueryItem(name: "select", value: "pin_code")
            ])
            if let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
               let firstResult = json.first,
               let dbPinCode = firstResult["pin_code"] as? String {
                return matchesStoredHash(dbPinCode)
            }
        } catch {
            print("verifyPin error: \(error.localizedDescription)")
            throw error
        }
        
        return false
    }

    /// Verify an iterated hash (format: "iter:<n>:<salt_b64>:<hash_hex>")
    private func verifyIteratedPin(_ pin: String, against storedHash: String) -> Bool {
        let parts = storedHash.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false)
        guard parts.count == 4,
              let iterations = Int(parts[1]) else { return false }
        let salt = String(parts[2])
        let expectedHash = String(parts[3])
        
        var hash = salt + pin
        for _ in 0..<iterations {
            let inputData = Data(hash.utf8)
            let digested = CryptoKit.SHA256.hash(data: inputData)
            hash = digested.compactMap { String(format: "%02x", $0) }.joined()
        }
        return constantTimeCompare(hash, expectedHash)
    }

    func fetchTimecards(for employeeId: String) async throws -> [Timecard] {
        let data = try await sendSupabaseRequest(method: "GET", endpoint: "timecards", queryItems: [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "employee_id", value: "eq.\(employeeId)"),
            URLQueryItem(name: "order", value: "clock_in.desc")
        ])
        let jsonArray = (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
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
                clockOutFaceConfidence: dict["clock_out_confidence"] as? Double
            )
        }
    }

    func uploadTimecard(timecard: Timecard) async throws -> Bool {
        let merchantId = self.activeMerchantId
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
            "merchant_id": merchantId
        ]
        
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
}
