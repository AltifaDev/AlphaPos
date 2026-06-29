// NetworkService+Breaks.swift
// Break timer APIs.

import Foundation

extension NetworkService {
    // MARK: - Break Timer APIs

    func startBreak(type: String) async throws {
        let merchantId = self.activeMerchantId
        let employeeId = UserDefaults.standard.string(forKey: "employee_id") ?? ""
        
        let payload: [String: Any] = [
            "id": UUID().uuidString,
            "employee_id": employeeId,
            "merchant_id": merchantId,
            "break_type": type,
            "start_time": ISO8601DateFormatter().string(from: Date()),
            "status": "active"
        ]
        
        _ = try await sendSupabaseRequest(method: "POST", endpoint: "employee_breaks", payload: payload)
    }

    func endBreak() async throws {
        let merchantId = self.activeMerchantId
        let employeeId = UserDefaults.standard.string(forKey: "employee_id") ?? ""
        
        let payload: [String: Any] = [
            "end_time": ISO8601DateFormatter().string(from: Date()),
            "status": "completed"
        ]
        
        let queryItems = [
            URLQueryItem(name: "employee_id", value: "eq.\(employeeId)"),
            URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)"),
            URLQueryItem(name: "status", value: "eq.active")
        ]
        
        _ = try await sendSupabaseRequest(method: "PATCH", endpoint: "employee_breaks", queryItems: queryItems, payload: payload)
    }

    func fetchBreakHistory(date: Date) async throws -> [BreakRecord] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: date)
        
        let employeeId = UserDefaults.standard.string(forKey: "employee_id") ?? ""
        let merchantId = self.activeMerchantId
        
        let queryItems = [
            URLQueryItem(name: "employee_id", value: "eq.\(employeeId)"),
            URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)"),
            URLQueryItem(name: "start_time", value: "gte.\(dateString)T00:00:00"),
            URLQueryItem(name: "order", value: "start_time.desc")
        ]
        
        let data = try await sendSupabaseRequest(method: "GET", endpoint: "employee_breaks", queryItems: queryItems)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let records = try decoder.decode([BreakRecord].self, from: data)
        return records
    }
}
