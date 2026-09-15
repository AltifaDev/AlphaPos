// NetworkService+Tables.swift
// Tables, floor plan media, table status, and merchant settings.

import Foundation

extension NetworkService {
    func fetchDiningAreas() async throws -> [DiningAreaStaff] {
        let merchantId = activeMerchantId
        let branchId = StaffSessionContext.branchId
        guard !merchantId.isEmpty else { throw StaffServiceError.missingMerchantSession }
        guard !branchId.isEmpty else { throw StaffServiceError.missingBranchSession }
        let data = try await sendSupabaseRequest(method: "GET", endpoint: "dining_areas", queryItems: [
            URLQueryItem(name: "select", value: "id,branch_id,floor_number,name,sort_order"),
            URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)"),
            URLQueryItem(name: "branch_id", value: "eq.\(branchId)"),
            URLQueryItem(name: "is_active", value: "eq.true"),
            URLQueryItem(name: "is_deleted", value: "eq.false"),
            URLQueryItem(name: "order", value: "sort_order.asc,floor_number.asc")
        ])
        return try JSONDecoder().decode([DiningAreaStaff].self, from: data)
    }

    func fetchTables() async throws -> [RestaurantTable] {
        let merchantId = activeMerchantId
        guard !merchantId.isEmpty else { throw StaffServiceError.missingMerchantSession }
        let branchId = StaffSessionContext.branchId
        guard !branchId.isEmpty else { throw StaffServiceError.missingBranchSession }
        var dynamicTables: [(String, String?, String?, String?, Int, Int, Double, Double, String, Bool, String)] = []

        do {
            let tablesData = try await sendSupabaseRequest(method: "GET", endpoint: "restaurant_tables", queryItems: [
                URLQueryItem(name: "select", value: "id,branch_id,dining_area_id,table_number,capacity,floor,position_x,position_y,status,is_round,table_shape,zone,dining_areas(name,floor_number)"),
                URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)"),
                URLQueryItem(name: "branch_id", value: "eq.\(branchId)"),
                URLQueryItem(name: "is_deleted", value: "eq.false")
            ])
            let tablesJson = (try? JSONSerialization.jsonObject(with: tablesData) as? [[String: Any]]) ?? []
            dynamicTables = tablesJson.compactMap { dict -> (String, String?, String?, String?, Int, Int, Double, Double, String, Bool, String)? in
                guard let num = dict["table_number"] as? String,
                      let cap = dict["capacity"] as? Int,
                      let floor = dict["floor"] as? Int else { return nil }
                let posX = dict["position_x"] as? Double ?? 0.0
                let posY = dict["position_y"] as? Double ?? 0.0
                let status = dict["status"] as? String ?? "vacant"
                let shape = (dict["table_shape"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let isRound: Bool = {
                    if !shape.isEmpty { return shape == "circle" || shape == "oval" }
                    return dict["is_round"] as? Bool ?? false
                }()
                let area = dict["dining_areas"] as? [String: Any]
                let zone = area?["name"] as? String ?? dict["zone"] as? String ?? "Indoor"
                return (num, dict["id"] as? String, dict["branch_id"] as? String,
                        dict["dining_area_id"] as? String, cap, floor, posX, posY, status, isRound, zone)
            }
        } catch {
            throw error
        }
        
        let sessionsData = try await sendSupabaseRequest(method: "GET", endpoint: "table_sessions", queryItems: [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)"),
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
            URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)"),
            URLQueryItem(name: "status", value: "in.(pending,preparing,ready)")
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
        
        return dynamicTables.map { num, tableId, branchId, diningAreaId, cap, floor, posX, posY, dbStatus, isRound, zoneVal in
            if let session = activeSessionsMap[num] {
                let guestCount = session["guest_count"] as? Int ?? 2
                let activeSessionId = session["id"] as? String
                let token = session["session_token"] as? String
                let total = tableTotals[num] ?? 0.0
                let startedAt = session["started_at"] as? String ?? session["created_at"] as? String
                return RestaurantTable(
                    restaurantTableId: tableId,
                    branchId: branchId,
                    diningAreaId: diningAreaId,
                    tableNumber: num,
                    capacity: cap,
                    floor: floor,
                    zone: zoneVal,
                    status: "occupied",
                    guestCount: guestCount,
                    activeSessionId: activeSessionId,
                    sessionToken: token,
                    isRound: isRound,
                    currentTotal: total,
                    positionX: posX,
                    positionY: posY,
                    sessionStartedAt: startedAt
                )
            } else {
                return RestaurantTable(
                    restaurantTableId: tableId,
                    branchId: branchId,
                    diningAreaId: diningAreaId,
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
        let merchantId = activeMerchantId
        guard !merchantId.isEmpty else { throw StaffServiceError.missingMerchantSession }
        let data = try await sendSupabaseRequest(method: "GET", endpoint: "floor_plan_images", queryItems: [
            URLQueryItem(name: "select", value: "id,branch_id,dining_area_id,floor,image_filename,is_deleted,scale,offset_x,offset_y,dining_areas(floor_number)"),
            URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)"),
            URLQueryItem(name: "is_deleted", value: "eq.false")
        ])
        let json = (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
        return json.compactMap { dict -> FloorPlanImageStaff? in
            guard let id = dict["id"] as? String,
                  let imageFilename = dict["image_filename"] as? String else { return nil }
            let area = dict["dining_areas"] as? [String: Any]
            let floor = dict["floor"] as? Int ?? area?["floor_number"] as? Int ?? 1
            let isDeleted = dict["is_deleted"] as? Bool ?? false
            var staffImage = FloorPlanImageStaff(
                id: id,
                branchId: dict["branch_id"] as? String,
                diningAreaId: dict["dining_area_id"] as? String,
                floor: floor,
                imageFilename: imageFilename,
                isDeleted: isDeleted
            )
            staffImage.scale = dict["scale"] as? Double ?? 1.0
            staffImage.offsetX = dict["offset_x"] as? Double ?? 0.0
            staffImage.offsetY = dict["offset_y"] as? Double ?? 0.0
            return staffImage
        }
    }

    func downloadFloorPlanMedia(fileName: String) async throws -> Data {
        let merchantId = activeMerchantId
        guard !merchantId.isEmpty else { throw StaffServiceError.missingMerchantSession }
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

    struct MerchantSettingsPayload: Sendable {
        var kitchenWorkflowRequired: Bool = true
        var promptPayNumber: String = ""
        var isTableSystemEnabled: Bool = true
        var isWebOrderingEnabled: Bool = true
        var merchantName: String = ""
        var taxRate: Double = 0.0
        var taxType: String = "inclusive"
        var serviceChargeRate: Double = 0.0
        var currency: String = "THB"
        var phone: String = ""
        var address: String = ""
        var taxId: String = ""
        var receiptHeader: String = ""
        var receiptFooter: String = ""
    }

    func fetchMerchantSettings() async throws -> MerchantSettingsPayload {
        let data = try await sendSupabaseRequest(method: "GET", endpoint: "merchants", queryItems: [
            URLQueryItem(name: "select", value: "name,phone,address_street,tax_id,receipt_header,receipt_footer,kitchen_workflow_required,promptpay_number,is_table_system_enabled,is_web_ordering_enabled,tax_rate,tax_type,service_charge_rate,currency"),
            URLQueryItem(name: "id", value: "eq.\(activeMerchantId)")
        ])
        if let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
           let firstMerchant = json.first {
            var payload = MerchantSettingsPayload()
            payload.merchantName = firstMerchant["name"] as? String ?? ""
            payload.phone = firstMerchant["phone"] as? String ?? ""
            payload.address = firstMerchant["address_street"] as? String ?? ""
            payload.taxId = firstMerchant["tax_id"] as? String ?? ""
            payload.receiptHeader = firstMerchant["receipt_header"] as? String ?? ""
            payload.receiptFooter = firstMerchant["receipt_footer"] as? String ?? ""
            payload.kitchenWorkflowRequired = firstMerchant["kitchen_workflow_required"] as? Bool ?? true
            payload.promptPayNumber = firstMerchant["promptpay_number"] as? String ?? ""
            payload.isTableSystemEnabled = firstMerchant["is_table_system_enabled"] as? Bool ?? true
            payload.isWebOrderingEnabled = firstMerchant["is_web_ordering_enabled"] as? Bool ?? true
            if let tr = firstMerchant["tax_rate"] as? Double {
                payload.taxRate = tr
            } else if let trStr = firstMerchant["tax_rate"] as? String, let tr = Double(trStr) {
                payload.taxRate = tr
            }
            payload.taxType = firstMerchant["tax_type"] as? String ?? "inclusive"
            if let sc = firstMerchant["service_charge_rate"] as? Double {
                payload.serviceChargeRate = sc
            } else if let scStr = firstMerchant["service_charge_rate"] as? String, let sc = Double(scStr) {
                payload.serviceChargeRate = sc
            }
            payload.currency = firstMerchant["currency"] as? String ?? "THB"
            return payload
        }
        return MerchantSettingsPayload()
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
