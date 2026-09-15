import Foundation
import CryptoKit
import SwiftData

extension NetworkManager {
    // MARK: - Purchase Orders Sync

    /// Atomically upserts a PurchaseOrder and its lines. Existing rows carry the
    /// last server revision so concurrent edits fail instead of overwriting.
    func uploadPurchaseOrder(purchaseOrder: PurchaseOrder) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""

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
        if let value = purchaseOrder.documentType { poPayload["document_type"] = value }
        if let value = purchaseOrder.invoiceNumber { poPayload["invoice_number"] = value }
        if let value = purchaseOrder.taxInvoiceNumber { poPayload["tax_invoice_number"] = value }
        if let value = purchaseOrder.supplierNameRaw { poPayload["supplier_name_raw"] = value }
        if let value = purchaseOrder.supplierTaxId { poPayload["supplier_tax_id"] = value }
        if let value = purchaseOrder.supplierBranchCode { poPayload["supplier_branch_code"] = value }
        if let value = purchaseOrder.customerReference { poPayload["customer_reference"] = value }
        if let value = purchaseOrder.invoiceDate { poPayload["invoice_date"] = NetworkManager.dateOnlyFormatter.string(from: value) }
        poPayload["currency_code"] = purchaseOrder.currencyCode
        if let value = purchaseOrder.subtotal { poPayload["subtotal"] = value }
        if let value = purchaseOrder.taxAmount { poPayload["tax_amount"] = value }
        if let value = purchaseOrder.grandTotal { poPayload["grand_total"] = value }
        if let value = purchaseOrder.extractionConfidence { poPayload["extraction_confidence"] = value }
        if let json = purchaseOrder.validationWarningsJSON,
           let data = json.data(using: .utf8),
           let value = try? JSONSerialization.jsonObject(with: data) {
            poPayload["validation_warnings"] = value
        }
        if let value = purchaseOrder.sourceDocumentHash { poPayload["source_document_hash"] = value }
        if purchaseOrder.rowVersion > 0 { poPayload["expected_row_version"] = purchaseOrder.rowVersion }

        // Include tombstones so line deletions propagate to every device.
        if !purchaseOrder.items.isEmpty {
            let itemsPayload: [[String: Any]] = purchaseOrder.items.map { item in
                var itemDict: [String: Any] = [
                    "id": item.id.uuidString.lowercased(),
                    "merchant_id": merchantId,
                    "purchase_order_id": purchaseOrder.id.uuidString.lowercased(),
                    "quantity_ordered": item.quantityOrdered,
                    "quantity_received": item.quantityReceived,
                    "unit_cost": item.unitCost,
                    "is_synced": true,
                    "is_deleted": item.isDeleted,
                    "updated_at": NetworkManager.iso8601.string(from: item.updatedAt)
                ]
                if let inventoryItemId = item.inventoryItem?.id {
                    itemDict["inventory_item_id"] = inventoryItemId.uuidString.lowercased()
                }
                if let value = item.lineNumber { itemDict["line_number"] = value }
                if let value = item.sourceItemName { itemDict["source_item_name"] = value }
                if let value = item.sellerItemId { itemDict["seller_item_id"] = value }
                if let value = item.barcode { itemDict["barcode"] = value }
                if let value = item.sourceUnit { itemDict["source_unit"] = value }
                if let value = item.unitCode { itemDict["unit_code"] = value }
                itemDict["price_base_quantity"] = item.priceBaseQuantity
                if let value = item.lineNetAmount { itemDict["line_net_amount"] = value }
                if let value = item.vatRate { itemDict["vat_rate"] = value }
                if let value = item.vatCode { itemDict["vat_code"] = value }
                if let value = item.taxAmount { itemDict["tax_amount"] = value }
                if let value = item.lineTotal { itemDict["line_total"] = value }
                if let value = item.lineConfidence { itemDict["line_confidence"] = value }
                if let value = item.expiryDate { itemDict["expiry_date"] = NetworkManager.dateOnlyFormatter.string(from: value) }
                if let value = item.lotNumber { itemDict["lot_number"] = value }
                if item.rowVersion > 0 { itemDict["expected_row_version"] = item.rowVersion }
                return itemDict
            }
            let data = try await sendSupabaseRequest(
                method: "POST",
                endpoint: "rpc/upsert_purchase_order_atomic_cas",
                payload: ["p_order": poPayload, "p_items": itemsPayload]
            )
            applyPurchaseOrderVersions(from: data, to: purchaseOrder)
        } else {
            let data = try await sendSupabaseRequest(
                method: "POST",
                endpoint: "rpc/upsert_purchase_order_atomic_cas",
                payload: ["p_order": poPayload, "p_items": []]
            )
            applyPurchaseOrderVersions(from: data, to: purchaseOrder)
        }

        return true
    }

    private func applyPurchaseOrderVersions(from data: Data, to purchaseOrder: PurchaseOrder) {
        guard let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        purchaseOrder.rowVersion = response["purchase_order_row_version"] as? Int ?? purchaseOrder.rowVersion
        guard let versions = response["item_row_versions"] as? [String: Any] else { return }
        for item in purchaseOrder.items {
            let value = versions[item.id.uuidString.lowercased()]
            item.rowVersion = value as? Int ?? (value as? NSNumber)?.intValue ?? item.rowVersion
        }
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

    /// Pulls PO headers including tombstones so deletes propagate to every device.
    func fetchPurchaseOrdersFromSupabase() async throws -> [[String: Any]] {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        let branchId = try activeOperationalBranchId()
        return try await fetchAllPages(
            endpoint: "purchase_orders",
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)"),
                URLQueryItem(name: "branch_id", value: "eq.\(branchId)"),
                URLQueryItem(name: "order", value: "updated_at.asc,id.asc")
            ],
            pageSize: 500
        )
    }

    /// Pulls PO lines including tombstones. Branch isolation is enforced by
    /// merchant RLS and again while attaching lines to the branch-scoped headers.
    func fetchPurchaseOrderItemsFromSupabase() async throws -> [[String: Any]] {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        return try await fetchAllPages(
            endpoint: "purchase_order_items",
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)"),
                URLQueryItem(name: "order", value: "updated_at.asc,id.asc")
            ],
            pageSize: 500
        )
    }

    // MARK: - Delivery Prices Sync

    /// Batch upserts all provided DeliveryPrice records to Supabase.
    /// DeliveryPrice has no isSynced flag — all prices are sent on every sync cycle.
    func uploadDeliveryPrices(_ deliveryPrices: [DeliveryPrice]) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""

        // Filter to prices that have a valid menu item link
        let validPrices: [[String: Any]] = deliveryPrices.compactMap { dp in
            guard !dp.isDeleted, let menuItemId = dp.menuItem?.id else { return nil }
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

    func deleteDeliveryPriceOnServer(id: UUID) async throws {
        _ = try await sendSupabaseRequest(
            method: "DELETE",
            endpoint: "delivery_prices",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(id.uuidString.lowercased())")]
        )
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
