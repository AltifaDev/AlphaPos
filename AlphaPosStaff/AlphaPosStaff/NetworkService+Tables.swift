// NetworkService+Tables.swift
// Tables, floor plan media, table status, and merchant settings.

import Foundation

extension NetworkService {
    func fetchTables() async throws -> [RestaurantTable] {
        var dynamicTables: [(String, Int, Int, Double, Double, String, Bool, String)] = []

        do {
            let tablesData = try await sendSupabaseRequest(method: "GET", endpoint: "restaurant_tables", queryItems: [
                URLQueryItem(name: "select", value: "table_number,capacity,floor,position_x,position_y,status,is_round,zone"),
                URLQueryItem(name: "is_deleted", value: "eq.false")
            ])
            let tablesJson = (try? JSONSerialization.jsonObject(with: tablesData) as? [[String: Any]]) ?? []
            dynamicTables = tablesJson.compactMap { dict -> (String, Int, Int, Double, Double, String, Bool, String)? in
                guard let num = dict["table_number"] as? String,
                      let cap = dict["capacity"] as? Int,
                      let floor = dict["floor"] as? Int else { return nil }
                let posX = dict["position_x"] as? Double ?? 0.0
                let posY = dict["position_y"] as? Double ?? 0.0
                let status = dict["status"] as? String ?? "vacant"
                let isRound = dict["is_round"] as? Bool ?? false
                let zone = dict["zone"] as? String ?? "Indoor"
                return (num, cap, floor, posX, posY, status, isRound, zone)
            }
        } catch {
            #if DEBUG
            print("NetworkService [fetchTables Error]: \(error.localizedDescription). Using static fallback.")
            #endif
        }
        
        if dynamicTables.isEmpty {
            dynamicTables = [
                // Floor 1 Tables: Synchronized with AlphaPos (6 tables)
                ("1", 2, 1, 40.0, 40.0, "vacant", false, "Indoor"),
                ("2", 4, 1, 200.0, 40.0, "vacant", false, "Indoor"),
                ("3", 4, 1, 380.0, 40.0, "vacant", false, "Indoor"),
                ("4", 6, 1, 40.0, 200.0, "vacant", false, "Indoor"),
                ("5", 8, 1, 320.0, 200.0, "vacant", false, "Indoor"),
                ("VIP 1", 10, 1, 140.0, 360.0, "vacant", false, "Indoor"),
                // Floor 2 Tables (3 tables)
                ("201", 4, 2, 60.0, 60.0, "vacant", false, "Indoor"),
                ("202", 4, 2, 240.0, 60.0, "vacant", false, "Indoor"),
                ("203", 6, 2, 420.0, 60.0, "vacant", false, "Indoor"),
                // Floor 3 Tables (1 table)
                ("301 (ROOF)", 8, 3, 120.0, 120.0, "vacant", false, "Rooftop")
            ]
        }
        
        let sessionsData = try await sendSupabaseRequest(method: "GET", endpoint: "table_sessions", queryItems: [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "is_active", value: "eq.1")
        ])
        
        let sessions = (try? JSONSerialization.jsonObject(with: sessionsData) as? [[String: Any]]) ?? []
        let activeSessionsMap = Dictionary(sessions.compactMap { dict -> (String, [String: Any])? in
            guard let tableNum = dict["table_number"] as? String else { return nil }
            return (tableNum, dict)
        }, uniquingKeysWith: { (first, second) in
            let firstCreated = first["created_at"] as? String ?? ""
            let secondCreated = second["created_at"] as? String ?? ""
            return firstCreated >= secondCreated ? first : second
        })
        
        let ordersData = try await sendSupabaseRequest(method: "GET", endpoint: "orders", queryItems: [
            URLQueryItem(name: "select", value: "table_number,total,created_at"),
            URLQueryItem(name: "status", value: "neq.cancelled")
        ])
        
        let orders = (try? JSONSerialization.jsonObject(with: ordersData) as? [[String: Any]]) ?? []
        
        var tableTotals: [String: Double] = [:]
        for order in orders {
            guard let tableNum = order["table_number"] as? String,
                  let total = order["total"] as? Double,
                  let createdAtStr = order["created_at"] as? String,
                  let activeSession = activeSessionsMap[tableNum],
                  let sessionStartStr = activeSession["created_at"] as? String else { continue }
            
            if createdAtStr >= sessionStartStr {
                tableTotals[tableNum, default: 0.0] += total
            }
        }
        
        return dynamicTables.map { num, cap, floor, posX, posY, dbStatus, isRound, zoneVal in
            if let session = activeSessionsMap[num] {
                let guestCount = session["guest_count"] as? Int ?? 2
                let token = session["session_token"] as? String
                let total = tableTotals[num] ?? 0.0
                let startedAt = session["started_at"] as? String ?? session["created_at"] as? String
                return RestaurantTable(
                    tableNumber: num,
                    capacity: cap,
                    floor: floor,
                    zone: zoneVal,
                    status: "occupied",
                    guestCount: guestCount,
                    sessionToken: token,
                    isRound: isRound,
                    currentTotal: total,
                    positionX: posX,
                    positionY: posY,
                    sessionStartedAt: startedAt
                )
            } else {
                return RestaurantTable(
                    tableNumber: num,
                    capacity: cap,
                    floor: floor,
                    zone: zoneVal,
                    status: dbStatus,
                    guestCount: 0,
                    sessionToken: nil,
                    isRound: isRound,
                    currentTotal: 0.0,
                    positionX: posX,
                    positionY: posY,
                    sessionStartedAt: nil
                )
            }
        }
    }

    func fetchFloorPlanImages() async throws -> [FloorPlanImageStaff] {
        let merchantId = activeMerchantId.isEmpty ? AppConfig.defaultMerchantId : activeMerchantId
        let data = try await sendSupabaseRequest(method: "GET", endpoint: "floor_plan_images", queryItems: [
            URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)"),
            URLQueryItem(name: "is_deleted", value: "eq.false")
        ])
        let json = (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
        return json.compactMap { dict -> FloorPlanImageStaff? in
            guard let id = dict["id"] as? String,
                  let floor = dict["floor"] as? Int,
                  let imageFilename = dict["image_filename"] as? String else { return nil }
            let isDeleted = dict["is_deleted"] as? Bool ?? false
            var staffImage = FloorPlanImageStaff(id: id, floor: floor, imageFilename: imageFilename, isDeleted: isDeleted)
            staffImage.scale = dict["scale"] as? Double ?? 1.0
            staffImage.offsetX = dict["offset_x"] as? Double ?? 0.0
            staffImage.offsetY = dict["offset_y"] as? Double ?? 0.0
            return staffImage
        }
    }

    func downloadFloorPlanMedia(fileName: String) async throws -> Data {
        let merchantId = activeMerchantId.isEmpty ? AppConfig.defaultMerchantId : activeMerchantId
        let objectPath = "\(merchantId.lowercased())/floor_plans/\(fileName)"
        var publicURL = AppConfig.supabaseURL
        for component in ["storage", "v1", "object", "public", "product-media"] + objectPath.split(separator: "/").map(String.init) {
            publicURL.appendPathComponent(component)
        }
        
        let (data, response) = try await URLSession.shared.data(from: publicURL)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.serverError("Failed to download floor plan media")
        }
        return data
    }

    func fetchMerchantSettings() async throws -> (Bool, String, Bool, Bool) {
        let data = try await sendSupabaseRequest(method: "GET", endpoint: "merchants", queryItems: [
            URLQueryItem(name: "select", value: "kitchen_workflow_required,promptpay_number,is_table_system_enabled,is_web_ordering_enabled"),
            URLQueryItem(name: "id", value: "eq.\(activeMerchantId)")
        ])
        if let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
           let firstMerchant = json.first {
            let workflow = firstMerchant["kitchen_workflow_required"] as? Bool ?? true
            let promptPay = firstMerchant["promptpay_number"] as? String ?? ""
            let tableSystem = firstMerchant["is_table_system_enabled"] as? Bool ?? true
            let webOrdering = firstMerchant["is_web_ordering_enabled"] as? Bool ?? true
            return (workflow, promptPay, tableSystem, webOrdering)
        }
        return (true, "", true, true)
    }

    func updateTableStatus(tableNumber: String, status: String) async throws -> Bool {
        let merchantId = self.activeMerchantId
        guard !merchantId.isEmpty else {
            throw NetworkError.serverError("No active merchant configured")
        }
        let queryItems = [
            URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)"),
            URLQueryItem(name: "table_number", value: "eq.\(tableNumber)")
        ]
        let payload = ["status": status]
        _ = try await sendSupabaseRequest(method: "PATCH", endpoint: "restaurant_tables", queryItems: queryItems, payload: payload)
        return true
    }
}
