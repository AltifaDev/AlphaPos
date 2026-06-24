import Foundation
import CryptoKit
import SwiftData

extension NetworkManager {
    // MARK: - Branch Sync

    func fetchBranchesFromSupabase() async throws -> [[String: Any]] {
        // branches table has no is_deleted column — use custom query without that filter
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        let data = try await sendSupabaseRequest(
            method: "GET",
            endpoint: "branches",
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)")
            ]
        )
        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw NetworkError.invalidResponse
        }
        return jsonArray
    }

    func uploadBranch(_ branch: Branch) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        var payload: [String: Any] = [
            "id": branch.id.uuidString.lowercased(),
            "merchant_id": merchantId,
            "name": branch.name,
            "updated_at": NetworkManager.iso8601.string(from: branch.updatedAt)
        ]
        if let location = branch.location { payload["location"] = location }
        if let phone = branch.phone { payload["phone"] = phone }
        _ = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "branches",
            queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
            payload: payload
        )
        return true
    }

    func deleteBranchOnServer(id: UUID) async throws -> Bool {
        // branches table has no is_deleted column — use hard DELETE
        _ = try await sendSupabaseRequest(
            method: "DELETE",
            endpoint: "branches",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(id.uuidString.lowercased())")]
        )
        return true
    }

    func fetchInventoryItemsFromSupabase() async throws -> [[String: Any]] {
        try await fetchMasterData(endpoint: "inventory_items")
    }

    func uploadInventoryItem(_ item: InventoryItem) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        var payload: [String: Any] = [
            "id": item.id.uuidString.lowercased(),
            "merchant_id": merchantId,
            "name": item.name,
            "unit": item.unit,
            "current_quantity": item.currentQuantity,
            "reorder_level": item.reorderLevel,
            "cost_price": item.costPrice,
            "is_deleted": item.isDeleted,
            "updated_at": NetworkManager.iso8601.string(from: item.updatedAt)
        ]
        if let sku = item.sku { payload["sku"] = sku }
        if let supplierId = item.supplier?.id.uuidString.lowercased() { payload["supplier_id"] = supplierId }
        if let branchId = item.branch?.id.uuidString.lowercased() { payload["branch_id"] = branchId }
        if let category = item.category { payload["category"] = category }
        if let storageLocation = item.storageLocation { payload["storage_location"] = storageLocation }
        if let barcode = item.barcode { payload["barcode"] = barcode }

        _ = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "inventory_items",
            queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
            payload: payload
        )
        return true
    }

    func deleteInventoryItemOnServer(id: UUID) async throws -> Bool {
        try await softDeleteMasterData(endpoint: "inventory_items", id: id)
    }

    func fetchModifierGroupsFromSupabase() async throws -> [[String: Any]] {
        try await fetchMasterData(endpoint: "modifier_groups")
    }

    func uploadModifierGroup(_ group: ModifierGroup) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        let payload: [String: Any] = [
            "id": group.id.uuidString.lowercased(),
            "merchant_id": merchantId,
            "name": group.name,
            "min_selection": group.minSelection,
            "max_selection": group.maxSelection,
            "is_deleted": group.isDeleted,
            "updated_at": NetworkManager.iso8601.string(from: group.updatedAt)
        ]
        _ = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "modifier_groups",
            queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
            payload: payload
        )
        return true
    }

    func deleteModifierGroupOnServer(id: UUID) async throws -> Bool {
        try await softDeleteMasterData(endpoint: "modifier_groups", id: id)
    }

    func fetchModifiersFromSupabase() async throws -> [[String: Any]] {
        try await fetchMasterData(endpoint: "modifiers")
    }

    func uploadModifier(_ modifier: Modifier) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        var payload: [String: Any] = [
            "id": modifier.id.uuidString.lowercased(),
            "merchant_id": merchantId,
            "name": modifier.name,
            "extra_price": modifier.extraPrice,
            "is_available": modifier.isAvailable,
            "is_deleted": modifier.isDeleted,
            "updated_at": NetworkManager.iso8601.string(from: modifier.updatedAt)
        ]
        if let groupId = modifier.modifierGroup?.id.uuidString.lowercased() { payload["modifier_group_id"] = groupId }
        if let itemId = modifier.inventoryItemLink?.id.uuidString.lowercased() { payload["inventory_item_id"] = itemId }
        if let quantityRequired = modifier.quantityRequired { payload["quantity_required"] = quantityRequired }

        _ = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "modifiers",
            queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
            payload: payload
        )
        return true
    }

    func deleteModifierOnServer(id: UUID) async throws -> Bool {
        try await softDeleteMasterData(endpoint: "modifiers", id: id)
    }

    func fetchMenuItemModifierGroupsFromSupabase() async throws -> [[String: Any]] {
        try await fetchMasterData(endpoint: "menu_item_modifier_groups")
    }

    func uploadMenuItemModifierGroup(_ relation: MenuItemModifierGroup) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        guard let menuItemId = relation.menuItem?.id.lowercased(),
              let modifierGroupId = relation.modifierGroup?.id.uuidString.lowercased() else {
            throw NetworkError.serverError("Menu item modifier group relation requires both sides.")
        }

        let payload: [String: Any] = [
            "menu_item_id": menuItemId,
            "modifier_group_id": modifierGroupId,
            "merchant_id": merchantId,
            "is_deleted": relation.isDeleted,
            "updated_at": NetworkManager.iso8601.string(from: relation.updatedAt)
        ]
        _ = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "menu_item_modifier_groups",
            queryItems: [URLQueryItem(name: "on_conflict", value: "menu_item_id,modifier_group_id")],
            payload: payload
        )
        return true
    }

    func deleteMenuItemModifierGroupOnServer(menuItemId: String, modifierGroupId: UUID) async throws -> Bool {
        let payload: [String: Any] = [
            "is_deleted": true,
            "updated_at": NetworkManager.iso8601.string(from: Date())
        ]
        _ = try await sendSupabaseRequest(
            method: "PATCH",
            endpoint: "menu_item_modifier_groups",
            queryItems: [
                URLQueryItem(name: "menu_item_id", value: "eq.\(menuItemId.lowercased())"),
                URLQueryItem(name: "modifier_group_id", value: "eq.\(modifierGroupId.uuidString.lowercased())")
            ],
            payload: payload
        )
        return true
    }
}
