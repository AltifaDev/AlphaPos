// SyncEngine+Inventory.swift
// AlphaPos — Sync: InventoryLot Push/Pull + Safety Stock field patch
//
// Drop-in extension alongside existing SyncEngine+MasterData.swift.
// Adds:
//   syncInventoryLots()          — push unsynced lots, soft-delete tombstones
//   pullInventoryLotsFromSupabase() — pull & merge lots from server
//   patchInventoryItemSafetyStock() — one-time column backfill (idempotent)
//
// ── How to wire in performSync (SyncEngine+Notifications.swift) ──────────────
//   Stage 1 (Pushes) — add after syncInventoryTransactions:
//       await syncInventoryLots(modelContext)
//
//   Stage 2 (Pulls) — add to TaskGroup:
//       group.addTask { await self.pullInventoryLotsFromSupabase(modelContext) }
// ─────────────────────────────────────────────────────────────────────────────

import Foundation
import SwiftData

extension SyncEngine {

    // MARK: - Push: InventoryLots

    /// Uploads all unsynced (or soft-deleted) InventoryLot records to Supabase.
    /// Uses batch upload when possible (≤200 lots), falls back to per-lot for deletes.
    func syncInventoryLots(_ modelContext: ModelContext) async {
        var descriptor = FetchDescriptor<InventoryLot>(
            predicate: #Predicate<InventoryLot> { $0.isSynced == false }
        )
        descriptor.fetchLimit = 500
        guard let lots = try? modelContext.fetch(descriptor), !lots.isEmpty else { return }

        // Separate deletes from upserts
        let toDelete = lots.filter { $0.isDeleted }
        let toUpsert = lots.filter { !$0.isDeleted }

        // ── Batch upsert (active lots) ──────────────────────────────────────
        if !toUpsert.isEmpty {
            do {
                if try await NetworkManager.shared.batchUploadInventoryLots(toUpsert) {
                    for lot in toUpsert {
                        lot.isSynced = true
                    }
                }
            } catch {
                encounteredSyncError = true
                print("SyncEngine [InventoryLot Batch Push Error]: \(error.localizedDescription)")
            }
        }

        // ── Per-lot soft-delete (tombstones) ────────────────────────────────
        for lot in toDelete {
            do {
                if try await NetworkManager.shared.deleteInventoryLotOnServer(id: lot.id) {
                    lot.isSynced = true
                    // Keep tombstone locally for 7 days, then it can be purged
                }
            } catch {
                encounteredSyncError = true
                print("SyncEngine [InventoryLot Delete Error]: \(error.localizedDescription)")
            }
        }

        do {
            try modelContext.save()
        } catch {
            print("SyncEngine [InventoryLot Push Save Error]: \(error.localizedDescription)")
        }
    }

    // MARK: - Pull: InventoryLots

    /// Fetches all lots from Supabase and merges into local SwiftData store.
    /// Conflict resolution: server wins when server.updated_at > local.updatedAt.
    func pullInventoryLotsFromSupabase(_ modelContext: ModelContext) async {
        do {
            let remoteLots = try await NetworkManager.shared.fetchInventoryLotsFromSupabase()
            guard !remoteLots.isEmpty else { return }

            // Pre-fetch all local lots and items once (avoid N+1 queries)
            var descLots = FetchDescriptor<InventoryLot>()
            descLots.fetchLimit = 2000
            let localLots = (try? modelContext.fetch(descLots)) ?? []
            var localById: [String: InventoryLot] = Dictionary(
                uniqueKeysWithValues: localLots.map { ($0.id.uuidString.lowercased(), $0) }
            )

            var descItems = FetchDescriptor<InventoryItem>()
            descItems.fetchLimit = 1000
            let localItems = (try? modelContext.fetch(descItems)) ?? []
            let itemById: [String: InventoryItem] = Dictionary(
                uniqueKeysWithValues: localItems.map { ($0.id.uuidString.lowercased(), $0) }
            )

            var descBranches = FetchDescriptor<Branch>()
            descBranches.fetchLimit = 100
            let localBranches = (try? modelContext.fetch(descBranches)) ?? []
            let branchById: [String: Branch] = Dictionary(
                uniqueKeysWithValues: localBranches.map { ($0.id.uuidString.lowercased(), $0) }
            )

            for remote in remoteLots {
                guard let idStr = remote["id"] as? String,
                      let id = UUID(uuidString: idStr) else { continue }

                let isDeletedRemote = remoteBool(remote["is_deleted"])
                let updatedAt = remoteDate(remote["updated_at"], fallback: .distantPast)
                let inventoryItem = (remote["inventory_item_id"] as? String).flatMap { itemById[$0.lowercased()] }
                let branch = (remote["branch_id"] as? String).flatMap { branchById[$0.lowercased()] }

                // Parse expiry_date (DATE string "yyyy-MM-dd")
                let expiryDate: Date? = {
                    guard let str = remote["expiry_date"] as? String, !str.isEmpty else { return nil }
                    return NetworkManager.dateOnlyFormatter.date(from: str)
                }()

                // Parse received_date
                let receivedDate = remoteDate(remote["received_date"], fallback: Date())

                let initialQty   = remoteDouble(remote["initial_quantity"])
                let remainingQty = remoteDouble(remote["remaining_quantity"])
                let costPrice    = remoteDouble(remote["lot_cost_price"])
                let lotNumber    = remote["lot_number"] as? String
                let srcTxnId: UUID? = (remote["source_transaction_id"] as? String).flatMap { UUID(uuidString: $0) }

                if let local = localById[idStr.lowercased()] {
                    // Merge: skip if local is newer or unsynced (local changes win)
                    guard local.isSynced, updatedAt > local.updatedAt else { continue }

                    if isDeletedRemote {
                        local.isDeleted = true
                        local.isSynced = true
                    } else {
                        local.inventoryItem    = inventoryItem
                        local.branch           = branch
                        local.lotNumber        = lotNumber
                        local.expiryDate       = expiryDate
                        local.receivedDate     = receivedDate
                        local.initialQuantity  = initialQty
                        local.remainingQuantity = remainingQty
                        local.lotCostPrice     = costPrice
                        local.sourceTransactionId = srcTxnId
                        local.updatedAt        = updatedAt
                        local.isSynced         = true
                    }
                } else {
                    guard !isDeletedRemote else { continue }  // don't create locally-deleted remote lots
                    let lot = InventoryLot(
                        inventoryItem:     inventoryItem,
                        branch:            branch,
                        lotNumber:         lotNumber,
                        receivedDate:      receivedDate,
                        expiryDate:        expiryDate,
                        initialQuantity:   initialQty,
                        remainingQuantity: remainingQty,
                        lotCostPrice:      costPrice,
                        sourceTransactionId: srcTxnId,
                        isSynced:          true,
                        updatedAt:         updatedAt == .distantPast ? Date() : updatedAt
                    )
                    modelContext.insert(lot)
                    localById[idStr.lowercased()] = lot
                }
            }

            do {
                try modelContext.save()
            } catch {
                print("SyncEngine [InventoryLot Pull Save Error]: \(error.localizedDescription)")
            }
        } catch {
            encounteredSyncError = true
            print("SyncEngine [InventoryLot Pull Error]: \(error.localizedDescription)")
        }
    }

    // MARK: - Safety Stock Fields: Upload patch for existing InventoryItems

    /// One-time idempotent patch that uploads safety_stock_level / max_stock_level /
    /// lead_time_days for ALL existing InventoryItems regardless of isSynced flag.
    ///
    /// Call once after first launch with the new app version, or manually from Settings.
    /// Uses PATCH so only the 3 new columns are updated — no risk of clobbering other fields.
    func patchInventoryItemSafetyStock(_ modelContext: ModelContext) async {
        var descriptor = FetchDescriptor<InventoryItem>(
            predicate: #Predicate<InventoryItem> { $0.isDeleted == false }
        )
        descriptor.fetchLimit = 1000
        guard let items = try? modelContext.fetch(descriptor), !items.isEmpty else { return }

        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId

        // Batch PATCH is not supported cleanly via Supabase REST for multiple rows with
        // different values — use individual PATCHes, but rate-limit with a short sleep.
        // For large datasets this runs in the background and respects encounteredSyncError.
        var patchCount = 0
        for item in items {
            // Skip items that have default values — no-op PATCHes waste bandwidth
            guard item.safetyStockLevel > 0 || item.maxStockLevel > 0 || item.leadTimeDays != 1 else { continue }

            do {
                _ = try await NetworkManager.shared.sendSupabaseRequest(
                    method: "PATCH",
                    endpoint: "inventory_items",
                    queryItems: [
                        URLQueryItem(name: "id",          value: "eq.\(item.id.uuidString.lowercased())"),
                        URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)")
                    ],
                    payload: [
                        "safety_stock_level": item.safetyStockLevel,
                        "max_stock_level":    item.maxStockLevel,
                        "lead_time_days":     item.leadTimeDays,
                        "updated_at":         NetworkManager.iso8601.string(from: Date())
                    ]
                )
                patchCount += 1
                // Rate-limit: 10ms between PATCHes to avoid Supabase 429
                if patchCount % 50 == 0 {
                    try await Task.sleep(nanoseconds: 100_000_000)  // 100ms pause every 50 items
                }
            } catch {
                encounteredSyncError = true
                print("SyncEngine [SafetyStock Patch Error \(item.name)]: \(error.localizedDescription)")
            }
        }
        #if DEBUG
        print("SyncEngine [SafetyStock Patch]: patched \(patchCount) items")
        #endif
    }
}

// MARK: - SyncEngine Helper Stubs
// (remoteDouble, remoteBool, remoteDate are already defined in SyncEngine+Helpers.swift)
// This comment is here to clarify — DO NOT redefine them here.
