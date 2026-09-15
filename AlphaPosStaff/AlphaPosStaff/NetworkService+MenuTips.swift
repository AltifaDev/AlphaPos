// NetworkService+MenuTips.swift
// Menu, tips, and tip summary.

import Foundation

extension NetworkService {
    func fetchMenu() async throws -> [MenuItem] {
        let data = try await sendSupabaseRequest(method: "GET", endpoint: "menu_items", queryItems: [
            URLQueryItem(name: "select", value: "*")
        ])
        let jsonArray = (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
        let items = jsonArray.map { dict in
            MenuItem(
                id: dict["id"] as? String ?? "",
                name: dict["name"] as? String ?? "",
                desc: dict["description"] as? String,
                price: dict["price"] as? Double ?? 0.0,
                category: dict["category"] as? String ?? "mains",
                emoji: dict["emoji"] as? String,
                imgClass: dict["img_class"] as? String,
                image_url: dict["image_url"] as? String,
                salesRole: dict["sales_role"] as? String
            )
        }
        // Cache for offline use
        await OfflineCache.shared.cacheMenu(items)
        
        // Prefetch images in background to populate URLCache
        prefetchImages(items)
        
        return items
    }

    // MARK: - Modifier Groups (option picker)

    /// Fetch the modifier groups (and their modifiers) attached to a menu item.
    /// Mirrors the master device: menu_item_modifier_groups → modifier_groups → modifiers.
    /// Returns an empty array when the item has no options (caller adds it directly).
    func fetchModifierGroups(forMenuItemId itemId: String) async throws -> [StaffModifierGroup] {
        guard !itemId.isEmpty else { return [] }
        let data = try await sendSupabaseRequest(method: "GET", endpoint: "menu_item_modifier_groups", queryItems: [
            URLQueryItem(name: "select",
                         value: "modifier_groups(id,name,min_selection,max_selection,modifiers(id,name,extra_price,is_available))"),
            URLQueryItem(name: "menu_item_id", value: "eq.\(itemId)")
        ])
        let rows = (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []

        var groups: [StaffModifierGroup] = []
        for row in rows {
            guard let g = row["modifier_groups"] as? [String: Any] else { continue }
            if let deleted = g["is_deleted"] as? Bool, deleted { continue }
            let modsRaw = g["modifiers"] as? [[String: Any]] ?? []
            let mods: [StaffModifier] = modsRaw.compactMap { m in
                if let del = m["is_deleted"] as? Bool, del { return nil }
                let available = m["is_available"] as? Bool ?? true
                guard available else { return nil }
                let name = m["name"] as? String ?? ""
                guard !name.isEmpty else { return nil }
                return StaffModifier(
                    id: m["id"] as? String ?? UUID().uuidString,
                    name: name,
                    extraPrice: m["extra_price"] as? Double ?? 0.0,
                    isAvailable: available
                )
            }
            guard !mods.isEmpty else { continue }
            groups.append(StaffModifierGroup(
                id: g["id"] as? String ?? UUID().uuidString,
                name: g["name"] as? String ?? "",
                minSelection: g["min_selection"] as? Int ?? 0,
                maxSelection: g["max_selection"] as? Int ?? 1,
                modifiers: mods
            ))
        }
        return groups
    }

    private func prefetchImages(_ items: [MenuItem]) {
        for item in items {
            guard let urlStr = item.image_url, !urlStr.isEmpty, let url = URL(string: urlStr) else { continue }
            // Perform light background request to trigger URLCache storage
            URLSession.shared.dataTask(with: url).resume()
        }
    }

    // MARK: - Tip Tracker APIs

    func fetchTips(from startDate: Date, to endDate: Date) async throws -> [TipRecord] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        let startStr = formatter.string(from: startDate)
        let endStr = formatter.string(from: endDate)
        let employeeId = UserDefaults.standard.string(forKey: "logged_in_employee_id") ?? ""
        
        let data = try await sendSupabaseRequest(method: "GET", endpoint: "tips", queryItems: [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "employee_id", value: "eq.\(employeeId)"),
            URLQueryItem(name: "created_at", value: "gte.\(startStr)"),
            URLQueryItem(name: "created_at", value: "lte.\(endStr)"),
            URLQueryItem(name: "order", value: "created_at.desc"),
            URLQueryItem(name: "merchant_id", value: "eq.\(activeMerchantId)")
        ])
        
        let decoder = JSONDecoder()
        do {
            let records = try decoder.decode([TipRecord].self, from: data)
            return records
        } catch {
            // If table doesn't exist yet or parsing fails, return empty
            return []
        }
    }

    func fetchTipSummary(period: String) async throws -> TipSummary? {
        let employeeId = UserDefaults.standard.string(forKey: "logged_in_employee_id") ?? ""
        
        let data = try await sendSupabaseRequest(method: "GET", endpoint: "rpc/get_tip_summary", queryItems: [
            URLQueryItem(name: "p_employee_id", value: employeeId),
            URLQueryItem(name: "p_period", value: period),
            URLQueryItem(name: "p_merchant_id", value: activeMerchantId)
        ])
        
        let decoder = JSONDecoder()
        do {
            // RPC returns a single object or array with one element
            if let summaryArray = try? decoder.decode([TipSummary].self, from: data),
               let first = summaryArray.first {
                return first
            }
            let summary = try decoder.decode(TipSummary.self, from: data)
            return summary
        } catch {
            return nil
        }
    }
}
