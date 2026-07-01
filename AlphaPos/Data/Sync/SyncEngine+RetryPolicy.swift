// SyncEngine+RetryPolicy.swift
// AlphaPos — Exponential Backoff Retry for Sync Push Operations
//
// Drop-in extension: adds `syncWithRetry()` helper that wraps any
// per-entity upload with exponential backoff + structured logging.
// Replaces the raw do/catch pattern scattered across SyncEngine+*.swift.
//
// ─────────────────────────────────────────────────────────────────────────────
// Usage (in any SyncEngine extension):
//
//   for item in items {
//       await syncWithRetry(label: "InventoryItem", entityId: item.id) {
//           try await NetworkManager.shared.uploadInventoryItem(item)
//       } onSuccess: {
//           item.isSynced = true
//       }
//   }
//   modelContext.saveWithLogging(label: #function)
//
// ─────────────────────────────────────────────────────────────────────────────

import Foundation
import SwiftData
import os

extension SyncEngine {

    // MARK: - syncWithRetry

    /// Executes a single-entity sync upload with exponential backoff.
    /// On permanent failure, sets `encounteredSyncError` and logs via AppLogger.
    /// - Parameters:
    ///   - label: Entity type name for logs (e.g. "InventoryItem")
    ///   - entityId: For deduplication logging only
    ///   - policy: Retry policy (default: 3 attempts)
    ///   - upload: The async throwing network call
    ///   - onSuccess: Called when upload succeeds (typically mark isSynced = true)
    func syncWithRetry(
        label: String,
        entityId: UUID,
        policy: SyncRetryPolicy = .default,
        upload: () async throws -> Bool,
        onSuccess: () -> Void
    ) async {
        do {
            let success = try await withRetry(label: label, policy: policy) {
                try await upload()
            }
            if success { onSuccess() }
        } catch {
            encounteredSyncError = true
            AppLogger.sync.error("[\(label) \(entityId.uuidString.prefix(8))] Permanent failure: \(error.localizedDescription)")
            // Enqueue for retry on next performSync call
            OfflineWriteQueue.shared.enqueue(
                entityType: label,
                entityId: entityId,
                operation: "upsert"
            )
        }
    }

    // MARK: - Upgraded syncInventoryItems (with retry)

    /// Upgraded version of syncInventoryItems using syncWithRetry.
    /// Replaces the existing function in SyncEngine+MasterData.swift.
    /// Wire this call inside performSync by replacing `await syncInventoryItems(modelContext)`.
    func syncInventoryItemsWithRetry(_ modelContext: ModelContext) async {
        var descriptor = FetchDescriptor<InventoryItem>(
            predicate: #Predicate<InventoryItem> { $0.isDeleted == true || $0.isSynced == false }
        )
        descriptor.fetchLimit = 500
        guard let items = try? modelContext.fetch(descriptor), !items.isEmpty else { return }

        for item in items {
            if item.isDeleted {
                await syncWithRetry(
                    label: "InventoryItem.delete",
                    entityId: item.id,
                    upload: { try await NetworkManager.shared.deleteInventoryItemOnServer(id: item.id) },
                    onSuccess: { modelContext.delete(item) }
                )
            } else {
                await syncWithRetry(
                    label: "InventoryItem.upsert",
                    entityId: item.id,
                    upload: { try await NetworkManager.shared.uploadInventoryItem(item) },
                    onSuccess: {
                        item.isSynced = true
                        item.updatedAt = Date()
                    }
                )
            }
        }
        modelContext.saveWithLogging(label: #function)
    }

    // MARK: - Upgraded syncInventoryTransactions (with retry)

    func syncInventoryTransactionsWithRetry(_ modelContext: ModelContext) async {
        var descriptor = FetchDescriptor<InventoryTransaction>(
            predicate: #Predicate<InventoryTransaction> { $0.isSynced == false }
        )
        descriptor.fetchLimit = 500
        guard let txns = try? modelContext.fetch(descriptor), !txns.isEmpty else { return }

        for txn in txns {
            if txn.isDeleted {
                modelContext.delete(txn)
                continue
            }
            let itemName = txn.item?.name ?? "Unknown"
            await syncWithRetry(
                label: "InventoryTransaction",
                entityId: txn.id,
                upload: {
                    try await NetworkManager.shared.uploadInventoryTransaction(
                        id: txn.id,
                        itemId: txn.item?.id,
                        itemName: itemName,
                        quantity: txn.quantity,
                        type: txn.transactionType,
                        costPrice: txn.costPrice,
                        referenceId: txn.referenceId,
                        notes: txn.notes,
                        branchId: txn.branch?.id,
                        isDeleted: txn.isDeleted,
                        updatedAt: txn.updatedAt
                    )
                },
                onSuccess: {
                    txn.isSynced = true
                    txn.updatedAt = Date()
                }
            )
        }
        modelContext.saveWithLogging(label: #function)
    }

    // MARK: - Upgraded syncInventoryLots (with retry)

    func syncInventoryLotsWithRetry(_ modelContext: ModelContext) async {
        var descriptor = FetchDescriptor<InventoryLot>(
            predicate: #Predicate<InventoryLot> { $0.isSynced == false }
        )
        descriptor.fetchLimit = 500
        guard let lots = try? modelContext.fetch(descriptor), !lots.isEmpty else { return }

        let toDelete = lots.filter { $0.isDeleted }
        let toUpsert = lots.filter { !$0.isDeleted }

        // Batch upload (preferred — single HTTP call for up to 200 lots)
        if !toUpsert.isEmpty {
            do {
                let success = try await withRetry(label: "InventoryLot.batchUpsert") {
                    try await NetworkManager.shared.batchUploadInventoryLots(toUpsert)
                }
                if success { toUpsert.forEach { $0.isSynced = true } }
            } catch {
                encounteredSyncError = true
                AppLogger.sync.error("[InventoryLot batchUpsert] Permanent failure: \(error.localizedDescription)")
                // Fall back to per-lot to identify which ones succeed
                for lot in toUpsert {
                    await syncWithRetry(
                        label: "InventoryLot.fallbackUpsert",
                        entityId: lot.id,
                        policy: .conservative,
                        upload: { try await NetworkManager.shared.uploadInventoryLot(lot) },
                        onSuccess: { lot.isSynced = true }
                    )
                }
            }
        }

        for lot in toDelete {
            await syncWithRetry(
                label: "InventoryLot.delete",
                entityId: lot.id,
                upload: { try await NetworkManager.shared.deleteInventoryLotOnServer(id: lot.id) },
                onSuccess: { lot.isSynced = true }
            )
        }

        modelContext.saveWithLogging(label: #function)
    }
}

// MARK: - performSync wiring comment
//
// To upgrade performSync in SyncEngine+Notifications.swift, replace:
//
//   await syncInventoryItems(modelContext)
//   await syncInventoryTransactions(modelContext)
//   await syncInventoryLots(modelContext)
//
// with:
//
//   await syncInventoryItemsWithRetry(modelContext)
//   await syncInventoryTransactionsWithRetry(modelContext)
//   await syncInventoryLotsWithRetry(modelContext)
