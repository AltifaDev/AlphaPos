import Foundation
import CryptoKit
import SwiftData

extension NetworkManager {
    // MARK: - Purchase Orders Sync

    /// Upserts a PurchaseOrder header and all its items to Supabase in a single sync call.
    /// Items are batch-upserted using on_conflict=id for idempotency.
    func uploadPurchaseOrder(purchaseOrder: PurchaseOrder) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId

        // 1. Upsert PO header
        var poPayload: [String: Any] = [
            "id": purchaseOrder.id.uuidString.lowercased(),
            "merchant_id": merchantId,
            "po_number": purchaseOrder.poNumber,
            "status": purchaseOrder.status,
            "order_date": NetworkManager.iso8601.string(from: purchaseOrder.orderDate),
            "notes": purchaseOrder.notes ?? "",
            "is_synced": true,
            "is_deleted": purchaseOrder.isDeleted,
            "updated_at": NetworkManager.iso8601.string(from: purchaseOrder.updatedAt)
        ]
        if let supplierId = purchaseOrder.supplier?.id {
            poPayload["supplier_id"] = supplierId.uuidString.lowercased()
        }
        if let branchId = purchaseOrder.branch?.id {
            poPayload["branch_id"] = branchId.uuidString.lowercased()
        }
        if let deliveryDate = purchaseOrder.deliveryDate {
            poPayload["delivery_date"] = NetworkManager.iso8601.string(from: deliveryDate)
        }

        _ = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "purchase_orders",
            queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
            payload: poPayload
        )

        // 2. Batch upsert all non-deleted items for this PO
        let activeItems = purchaseOrder.items.filter { !$0.isDeleted }
        if !activeItems.isEmpty {
            let itemsPayload: [[String: Any]] = activeItems.map { item in
                var itemDict: [String: Any] = [
                    "id": item.id.uuidString.lowercased(),
                    "merchant_id": merchantId,
                    "purchase_order_id": purchaseOrder.id.uuidString.lowercased(),
                    "quantity_ordered": item.quantityOrdered,
                    "quantity_received": item.quantityReceived,
                    "unit_cost": item.unitCost,
                    "is_synced": true,
                    "is_deleted": false,
                    "updated_at": NetworkManager.iso8601.string(from: item.updatedAt)
                ]
                if let inventoryItemId = item.inventoryItem?.id {
                    itemDict["inventory_item_id"] = inventoryItemId.uuidString.lowercased()
                }
                return itemDict
            }
            _ = try await sendSupabaseRequest(
                method: "POST",
                endpoint: "purchase_order_items",
                queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
                payload: itemsPayload
            )
        }

        return true
    }

    /// Soft-deletes a PurchaseOrder on Supabase by marking is_deleted = true.
    /// Items are marked as deleted via update (CASCADE DELETE handles physical removal).
    func deletePurchaseOrderOnServer(id: UUID) async throws -> Bool {
        let idStr = id.uuidString.lowercased()
        let deletedPayload: [String: Any] = ["is_deleted": true]

        // Mark items deleted first
        _ = try await sendSupabaseRequest(
            method: "PATCH",
            endpoint: "purchase_order_items",
            queryItems: [URLQueryItem(name: "purchase_order_id", value: "eq.\(idStr)")],
            payload: deletedPayload
        )
        // Mark PO header deleted
        _ = try await sendSupabaseRequest(
            method: "PATCH",
            endpoint: "purchase_orders",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(idStr)")],
            payload: deletedPayload
        )
        return true
    }

    // MARK: - Delivery Prices Sync

    /// Batch upserts all provided DeliveryPrice records to Supabase.
    /// DeliveryPrice has no isSynced flag — all prices are sent on every sync cycle.
    func uploadDeliveryPrices(_ deliveryPrices: [DeliveryPrice]) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId

        // Filter to prices that have a valid menu item link
        let validPrices: [[String: Any]] = deliveryPrices.compactMap { dp in
            guard let menuItemId = dp.menuItem?.id else { return nil }
            return [
                "id": dp.id.uuidString.lowercased(),
                "merchant_id": merchantId,
                "menu_item_id": menuItemId.lowercased(),
                "brand_name": dp.brandName,
                "price": dp.price
            ]
        }

        guard !validPrices.isEmpty else { return true }

        _ = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "delivery_prices",
            queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
            payload: validPrices
        )
        return true
    }

    func deletePromotionOnServer(id: UUID) async throws -> Bool {
        let idStr = id.uuidString.lowercased()
        // Soft-delete: PATCH is_deleted=1 so RLS (which allows PATCH but may block DELETE)
        // works correctly while leaving a tombstone for other devices to purge local cache.
        let softDeletePayload: [String: Any] = [
            "is_deleted": 1,
            "updated_at": NetworkManager.iso8601.string(from: Date())
        ]

        var supabaseSuccess = false
        do {
            _ = try await sendSupabaseRequest(
                method: "PATCH",
                endpoint: "promotions",
                queryItems: [URLQueryItem(name: "id", value: "eq.\(idStr)")],
                payload: softDeletePayload
            )
            supabaseSuccess = true
        } catch {
            print("NetworkManager: Supabase promotion soft-delete failed: \(error.localizedDescription)")
        }

        // Legacy local server call removed.
        return supabaseSuccess
    }
}
