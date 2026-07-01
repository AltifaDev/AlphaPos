// NetworkService+Shifts.swift
// Shift schedules and daily summary.

import Foundation

extension NetworkService {
    // MARK: - Shift Schedule

    private func parseDate(_ dateStr: String) -> Date? {
        let isoFormatter = ISO8601DateFormatter()
        if let date = isoFormatter.date(from: dateStr) {
            return date
        }
        
        let isoFractionalFormatter = ISO8601DateFormatter()
        isoFractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFractionalFormatter.date(from: dateStr) {
            return date
        }
        
        let cleanStr = dateStr.replacingOccurrences(of: " ", with: "T")
        if let date = isoFormatter.date(from: cleanStr) {
            return date
        }
        if let date = isoFractionalFormatter.date(from: cleanStr) {
            return date
        }
        
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        
        df.dateFormat = "yyyy-MM-dd HH:mm:ssZ"
        if let date = df.date(from: dateStr) {
            return date
        }
        
        df.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSZ"
        if let date = df.date(from: dateStr) {
            return date
        }
        
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let date = df.date(from: dateStr) {
            return date
        }
        
        return nil
    }

    func fetchMyShifts(weekOf date: Date) async throws -> [Shift] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let startDate = formatter.string(from: date)
        let endDate = formatter.string(from: Calendar.current.date(byAdding: .day, value: 6, to: date) ?? date)
        
        let employeeId = UserDefaults.standard.string(forKey: "logged_in_employee_id") ?? ""
        
        let data = try await sendSupabaseRequest(method: "GET", endpoint: "employee_shifts", queryItems: [
            URLQueryItem(name: "select", value: "*,employees(first_name,last_name)"),
            URLQueryItem(name: "employee_id", value: "eq.\(employeeId)"),
            URLQueryItem(name: "scheduled_start", value: "gte.\(startDate)T00:00:00"),
            URLQueryItem(name: "scheduled_start", value: "lte.\(endDate)T23:59:59"),
            URLQueryItem(name: "order", value: "scheduled_start.asc")
        ])
        
        let jsonArray = (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
        return jsonArray.compactMap { dict -> Shift? in
            guard let id = dict["id"] as? String,
                  let empId = dict["employee_id"] as? String,
                  let scheduledStartStr = dict["scheduled_start"] as? String,
                  let scheduledEndStr = dict["scheduled_end"] as? String
            else { return nil }
            
            // Resolve employee name
            let empDict = dict["employees"] as? [String: Any]
            let firstName = empDict?["first_name"] as? String ?? ""
            let lastName = empDict?["last_name"] as? String ?? ""
            let empName = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
            
            // Parse dates
            guard let startDateVal = parseDate(scheduledStartStr),
                  let endDateVal = parseDate(scheduledEndStr)
            else { return nil }
            
            // Format to Shift's expected types
            let dateOnlyFormatter = DateFormatter()
            dateOnlyFormatter.dateFormat = "yyyy-MM-dd"
            let dateStr = dateOnlyFormatter.string(from: startDateVal)
            
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "HH:mm"
            let startTimeStr = timeFormatter.string(from: startDateVal)
            let endTimeStr = timeFormatter.string(from: endDateVal)
            
            let shiftTypeStr = dict["shift_type"] as? String ?? "morning"
            let shiftType = ShiftType(rawValue: shiftTypeStr) ?? .morning
            
            return Shift(
                id: id,
                employeeId: empId,
                employeeName: empName,
                date: dateStr,
                startTime: startTimeStr,
                endTime: endTimeStr,
                shiftType: shiftType,
                station: dict["station"] as? String,
                notes: dict["notes"] as? String
            )
        }
    }

    func fetchTeamShifts(weekOf date: Date) async throws -> [Shift] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let startDate = formatter.string(from: date)
        let endDate = formatter.string(from: Calendar.current.date(byAdding: .day, value: 6, to: date) ?? date)
        
        let employeeId = UserDefaults.standard.string(forKey: "logged_in_employee_id") ?? ""
        
        let data = try await sendSupabaseRequest(method: "GET", endpoint: "employee_shifts", queryItems: [
            URLQueryItem(name: "select", value: "*,employees(first_name,last_name)"),
            URLQueryItem(name: "employee_id", value: "neq.\(employeeId)"),
            URLQueryItem(name: "scheduled_start", value: "gte.\(startDate)T00:00:00"),
            URLQueryItem(name: "scheduled_start", value: "lte.\(endDate)T23:59:59"),
            URLQueryItem(name: "order", value: "scheduled_start.asc")
        ])
        
        let jsonArray = (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
        return jsonArray.compactMap { dict -> Shift? in
            guard let id = dict["id"] as? String,
                  let empId = dict["employee_id"] as? String,
                  let scheduledStartStr = dict["scheduled_start"] as? String,
                  let scheduledEndStr = dict["scheduled_end"] as? String
            else { return nil }
            
            // Resolve employee name
            let empDict = dict["employees"] as? [String: Any]
            let firstName = empDict?["first_name"] as? String ?? ""
            let lastName = empDict?["last_name"] as? String ?? ""
            let empName = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
            
            // Parse dates
            guard let startDateVal = parseDate(scheduledStartStr),
                  let endDateVal = parseDate(scheduledEndStr)
            else { return nil }
            
            // Format to Shift's expected types
            let dateOnlyFormatter = DateFormatter()
            dateOnlyFormatter.dateFormat = "yyyy-MM-dd"
            let dateStr = dateOnlyFormatter.string(from: startDateVal)
            
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "HH:mm"
            let startTimeStr = timeFormatter.string(from: startDateVal)
            let endTimeStr = timeFormatter.string(from: endDateVal)
            
            let shiftTypeStr = dict["shift_type"] as? String ?? "morning"
            let shiftType = ShiftType(rawValue: shiftTypeStr) ?? .morning
            
            return Shift(
                id: id,
                employeeId: empId,
                employeeName: empName,
                date: dateStr,
                startTime: startTimeStr,
                endTime: endTimeStr,
                shiftType: shiftType,
                station: dict["station"] as? String,
                notes: dict["notes"] as? String
            )
        }
    }

    // MARK: - Daily Summary

    func fetchDailySummary(date: Date) async throws -> DailySummary {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateStr = formatter.string(from: date)
        let employeeId = UserDefaults.standard.string(forKey: "logged_in_employee_id") ?? ""
        
        let data = try await sendSupabaseRequest(method: "GET", endpoint: "rpc/get_daily_summary", queryItems: [
            URLQueryItem(name: "p_employee_id", value: employeeId),
            URLQueryItem(name: "p_date", value: dateStr)
        ])
        
        // Try decoding structured response from Supabase RPC
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let ordersServed = json["orders_served"] as? Int ?? 0
            let revenueGenerated = json["revenue_generated"] as? Double ?? 0.0
            let avgPrepTime = json["avg_prep_time"] as? Int ?? 0
            let tablesTurned = json["tables_turned"] as? Int ?? 0
            let tipsEarned = json["tips_earned"] as? Double ?? 0.0
            let hourlyOrders = json["hourly_orders"] as? [Int] ?? Array(repeating: 0, count: 24)
            let hoursWorked = json["hours_worked"] as? Double ?? 0.0
            let streak = json["streak"] as? Int ?? 1
            
            var topItems: [DailySummary.TopSoldItem] = []
            if let topItemsArray = json["top_items"] as? [[String: Any]] {
                topItems = topItemsArray.compactMap { item in
                    guard let name = item["name"] as? String,
                          let qty = item["quantity"] as? Int else { return nil }
                    return DailySummary.TopSoldItem(name: name, quantity: qty)
                }
            }
            
            return DailySummary(
                ordersServed: ordersServed,
                revenueGenerated: revenueGenerated,
                avgPrepTime: avgPrepTime,
                tablesTurned: tablesTurned,
                tipsEarned: tipsEarned,
                hourlyOrders: hourlyOrders,
                topItems: topItems,
                hoursWorked: hoursWorked,
                streak: streak
            )
        }
        
        // Fallback: try standard Codable decoding
        let decoder = JSONDecoder()
        if let summary = try? decoder.decode(DailySummary.self, from: data) {
            return summary
        }
        
        throw NetworkError.invalidResponse
    }

    func fetchTodayActiveShift(employeeId: String) async throws -> Shift? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let todayStr = formatter.string(from: Date())
        
        let data = try await sendSupabaseRequest(method: "GET", endpoint: "employee_shifts", queryItems: [
            URLQueryItem(name: "select", value: "*,employees(first_name,last_name)"),
            URLQueryItem(name: "employee_id", value: "eq.\(employeeId)"),
            URLQueryItem(name: "scheduled_start", value: "gte.\(todayStr)T00:00:00"),
            URLQueryItem(name: "scheduled_start", value: "lte.\(todayStr)T23:59:59")
        ])
        
        let jsonArray = (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
        guard let dict = jsonArray.first else { return nil }
        
        guard let id = dict["id"] as? String,
              let empId = dict["employee_id"] as? String,
              let scheduledStartStr = dict["scheduled_start"] as? String,
              let scheduledEndStr = dict["scheduled_end"] as? String
        else { return nil }
        
        let empDict = dict["employees"] as? [String: Any]
        let firstName = empDict?["first_name"] as? String ?? ""
        let lastName = empDict?["last_name"] as? String ?? ""
        let empName = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        
        guard let startDateVal = parseDate(scheduledStartStr),
              let endDateVal = parseDate(scheduledEndStr)
        else { return nil }
        
        let dateOnlyFormatter = DateFormatter()
        dateOnlyFormatter.dateFormat = "yyyy-MM-dd"
        let dateStr = dateOnlyFormatter.string(from: startDateVal)
        
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        let startTimeStr = timeFormatter.string(from: startDateVal)
        let endTimeStr = timeFormatter.string(from: endDateVal)
        
        let shiftTypeStr = dict["shift_type"] as? String ?? "morning"
        let shiftType = ShiftType(rawValue: shiftTypeStr) ?? .morning
        
        return Shift(
            id: id,
            employeeId: empId,
            employeeName: empName,
            date: dateStr,
            startTime: startTimeStr,
            endTime: endTimeStr,
            shiftType: shiftType,
            station: dict["station"] as? String,
            notes: dict["notes"] as? String
        )
    }
}
