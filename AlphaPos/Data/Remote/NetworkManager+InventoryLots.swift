// NetworkManager+InventoryLots.swift
// AlphaPos — Supabase API: InventoryLot Push & Pull
//
// Handles upload and fetch for inventory_lots table.
// Pattern: same upsert-on-conflict idiom used throughout NetworkManager.
// ─────────────────────────────────────────────────────────────────────────────

import Foundation
import SwiftData

extension NetworkManager {

    // MARK: - Upload (Push)

    /// Upserts a single InventoryLot to Supabase.
    /// Called by SyncEngine+Inventory when isSynced == false.
    func uploadInventoryLot(_ lot: InventoryLot) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId

        var payload: [String: Any] = [
            "id":                lot.id.uuidString.lowercased(),
            "merchant_id":       merchantId,
            "initial_quantity":  lot.initialQuantity,
            "remaining_quantity": lot.remainingQuantity,
            "lot_cost_price":    lot.lotCostPrice,
            "received_date":     NetworkManager.iso8601.string(from: lot.receivedDate),
            "is_deleted":        lot.isDeleted,
            "is_synced":         true,
            "updated_at":        NetworkManager.iso8601.string(from: lot.updatedAt)
        ]

        if let itemId = lot.inventoryItem?.id {
            payload["inventory_item_id"] = itemId.uuidString.lowercased()
        }
        if let branchId = lot.branch?.id {
            payload["branch_id"] = branchId.uuidString.lowercased()
        }
        if let lotNumber = lot.lotNumber {
            payload["lot_number"] = lotNumber
        }
        if let expiryDate = lot.expiryDate {
            // DATE only (no time) — matches SQL column type DATE
            payload["expiry_date"] = Self.dateOnlyFormatter.string(from: expiryDate)
        }
        if let srcTxnId = lot.sourceTransactionId {
            payload["source_transaction_id"] = srcTxnId.uuidString.lowercased()
        }

        _ = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "inventory_lots",
            queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
            payload: payload
        )
        return true
    }

    /// Batch-uploads an array of InventoryLots in one HTTP call.
    /// Idempotent via on_conflict=id. Max 200 lots per call (Supabase row limit).
    func batchUploadInventoryLots(_ lots: [InventoryLot]) async throws -> Bool {
        guard !lots.isEmpty else { return true }
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId

        let payloads: [[String: Any]] = lots.map { lot in
            var p: [String: Any] = [
                "id":                lot.id.uuidString.lowercased(),
                "merchant_id":       merchantId,
                "initial_quantity":  lot.initialQuantity,
                "remaining_quantity": lot.remainingQuantity,
                "lot_cost_price":    lot.lotCostPrice,
                "received_date":     NetworkManager.iso8601.string(from: lot.receivedDate),
                "is_deleted":        lot.isDeleted,
                "is_synced":         true,
                "updated_at":        NetworkManager.iso8601.string(from: lot.updatedAt)
            ]
            if let itemId  = lot.inventoryItem?.id { p["inventory_item_id"] = itemId.uuidString.lowercased() }
            if let branchId = lot.branch?.id       { p["branch_id"]         = branchId.uuidString.lowercased() }
            if let ln = lot.lotNumber              { p["lot_number"]         = ln }
            if let exp = lot.expiryDate            { p["expiry_date"]        = Self.dateOnlyFormatter.string(from: exp) }
            if let src = lot.sourceTransactionId   { p["source_transaction_id"] = src.uuidString.lowercased() }
            return p
        }

        // Chunk into 200-row batches to stay within Supabase default limit
        for chunk in stride(from: 0, to: payloads.count, by: 200).map({ Array(payloads[$0..<min($0+200, payloads.count)]) }) {
            _ = try await sendSupabaseRequest(
                method: "POST",
                endpoint: "inventory_lots",
                queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
                payload: chunk
            )
        }
        return true
    }

    // MARK: - Soft Delete

    /// Marks a lot as deleted on Supabase (tombstone for other devices).
    func deleteInventoryLotOnServer(id: UUID) async throws -> Bool {
        _ = try await sendSupabaseRequest(
            method: "PATCH",
            endpoint: "inventory_lots",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(id.uuidString.lowercased())")],
            payload: [
                "is_deleted": true,
                "updated_at": NetworkManager.iso8601.string(from: Date())
            ]
        )
        return true
    }

    // MARK: - Fetch (Pull)

    /// Fetches all non-deleted lots for the current merchant from Supabase.
    /// Returns raw [String: Any] dicts — parsing done in SyncEngine.
    func fetchInventoryLotsFromSupabase() async throws -> [[String: Any]] {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        let data = try await sendSupabaseRequest(
            method: "GET",
            endpoint: "inventory_lots",
            queryItems: [
                URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)"),
                URLQueryItem(name: "is_deleted",  value: "eq.false"),
                URLQueryItem(name: "select",       value: "*"),
                URLQueryItem(name: "order",        value: "updated_at.desc"),
                URLQueryItem(name: "limit",        value: "2000")   // lots can be many per item
            ],
            payload: nil
        )
        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return jsonArray
    }

    // MARK: - Date-Only Formatter (shared)

    static let dateOnlyFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(identifier: "UTC")
        return df
    }()
}
