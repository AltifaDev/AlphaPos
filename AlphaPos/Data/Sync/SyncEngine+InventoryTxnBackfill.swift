// SyncEngine+InventoryTxnBackfill.swift
// AlphaPos — One-time backfill for InventoryTransaction.createdAt
//
// Context:
//   `InventoryTransaction` gained an explicit `createdAt` (business event time)
//   so reports stop dating movements by `updatedAt` (sync metadata). Rows that
//   existed BEFORE this change get `createdAt = Date()` from the SwiftData
//   lightweight migration default — which would bunch all historical movements
//   onto the migration date and distort waste/COGS/usage reports.
//
//   This one-time, idempotent pass repairs those rows locally:
//     • If the txn references an order (referenceId → Order.id), use that
//       order's createdAt — the most accurate event time.
//     • Otherwise fall back to the txn's own updatedAt, which is far closer to
//       the real event time than the migration timestamp.
//
//   It is gated by a UserDefaults flag so it only runs once per device, and it
//   only touches rows whose createdAt is implausibly close to "now" relative to
//   updatedAt (i.e. the migration default), so re-runs and already-correct rows
//   are left untouched.
//
// Wiring (SyncEngine+Notifications.swift, very early in performSync, before pulls):
//     await backfillInventoryTransactionCreatedAt(modelContext)

import Foundation
import SwiftData

extension SyncEngine {

    private static let inventoryTxnCreatedAtBackfillKey = "did_backfill_inventory_txn_created_at_v1"
    private static let businessContextBackfillKey = "did_backfill_business_context_v1"
    private static let accountingLedgerBackfillKey = "did_backfill_accounting_ledger_v2"

    @MainActor
    func backfillAccountingLedger(_ modelContext: ModelContext) async {
        // New payments/refunds write their ledger fact in the same transaction.
        // Historical reconciliation is therefore a versioned migration, not a
        // periodic operational task.
        guard !UserDefaults.standard.bool(forKey: Self.accountingLedgerBackfillKey) else { return }
        let result = AccountingLedgerService.backfill(in: modelContext)
        UserDefaults.standard.set(true, forKey: Self.accountingLedgerBackfillKey)
        #if DEBUG
        if result.payments > 0 || result.refunds > 0 || result.closureSnapshots > 0 {
            print("Accounting ledger reconciliation: \(result.payments) payments, \(result.refunds) refunds, \(result.closureSnapshots) closure snapshots")
        }
        #endif
    }

    @MainActor
    func backfillBusinessContext(_ modelContext: ModelContext) async {
        guard !UserDefaults.standard.bool(forKey: Self.businessContextBackfillKey) else { return }
        let branches = (try? modelContext.fetch(FetchDescriptor<Branch>())) ?? []
        let branchById = Dictionary(uniqueKeysWithValues: branches.map { ($0.id, $0) })
        let sessions = (try? modelContext.fetch(FetchDescriptor<RegisterSession>())) ?? []

        for session in sessions where session.businessDateKey.isEmpty {
            session.businessDateKey = BusinessDayContext.key(for: session.openedAt, cutoffHour: session.branch.businessDayCutoffHour, timeZoneID: session.branch.timeZoneID)
            session.isSynced = false
        }

        func assignment(at date: Date, branch: Branch) -> BusinessDayContext.Assignment {
            let session = sessions.filter {
                !$0.isDeleted && $0.branch.id == branch.id && $0.openedAt <= date && ($0.closedAt == nil || $0.closedAt! >= date)
            }.max { $0.openedAt < $1.openedAt }
            return .init(businessDateKey: session?.businessDateKey ?? BusinessDayContext.key(for: date, cutoffHour: branch.businessDayCutoffHour, timeZoneID: branch.timeZoneID), registerSessionId: session?.id)
        }

        let payments = (try? modelContext.fetch(FetchDescriptor<Payment>())) ?? []
        for payment in payments where !payment.isDeleted {
            guard let branch = payment.order?.branch else { continue }
            let value = assignment(at: payment.paidAt, branch: branch)
            if payment.businessDateKey.isEmpty { payment.businessDateKey = value.businessDateKey }
            if payment.registerSessionId == nil { payment.registerSessionId = value.registerSessionId }
            payment.isSynced = false
        }

        let orders = (try? modelContext.fetch(FetchDescriptor<Order>())) ?? []
        for order in orders where !order.isDeleted {
            if let first = order.payments.filter({ !$0.isDeleted && $0.isCaptured }).min(by: { $0.paidAt < $1.paidAt }) {
                order.businessDateKey = first.businessDateKey
                order.registerSessionId = first.registerSessionId
            } else if order.businessDateKey.isEmpty, let branch = branchById[order.branch.id] {
                let value = assignment(at: order.createdAt, branch: branch)
                order.businessDateKey = value.businessDateKey
                order.registerSessionId = value.registerSessionId
            }
            order.isSynced = false
        }

        let refunds = (try? modelContext.fetch(FetchDescriptor<RefundTransaction>())) ?? []
        for refund in refunds where !refund.isDeleted {
            guard let branch = refund.order?.branch else { continue }
            let value = assignment(at: refund.financialEventAt, branch: branch)
            if refund.businessDateKey.isEmpty { refund.businessDateKey = value.businessDateKey }
            if refund.registerSessionId == nil { refund.registerSessionId = value.registerSessionId }
            refund.isSynced = false
        }

        let transactions = (try? modelContext.fetch(FetchDescriptor<InventoryTransaction>())) ?? []
        for transaction in transactions where !transaction.isDeleted {
            let value = assignment(at: transaction.createdAt, branch: transaction.branch)
            if transaction.businessDateKey.isEmpty { transaction.businessDateKey = value.businessDateKey }
            if transaction.registerSessionId == nil { transaction.registerSessionId = value.registerSessionId }
            transaction.isSynced = false
        }

        modelContext.saveWithLogging(label: #function)
        UserDefaults.standard.set(true, forKey: Self.businessContextBackfillKey)
    }

    /// One-time local repair of InventoryTransaction.createdAt for rows created
    /// before the event-time migration. Idempotent and safe to call every launch.
    @MainActor
    func backfillInventoryTransactionCreatedAt(_ modelContext: ModelContext) async {
        // Gate: run at most once per device.
        guard !UserDefaults.standard.bool(forKey: Self.inventoryTxnCreatedAtBackfillKey) else { return }

        let descriptor = FetchDescriptor<InventoryTransaction>(
            predicate: #Predicate<InventoryTransaction> { $0.isDeleted == false }
        )
        guard let txns = try? modelContext.fetch(descriptor), !txns.isEmpty else {
            // Nothing to repair — mark done so we don't re-scan an empty store forever.
            UserDefaults.standard.set(true, forKey: Self.inventoryTxnCreatedAtBackfillKey)
            return
        }

        // Build an order lookup once for referenceId → Order.createdAt resolution.
        let orderDescriptor = FetchDescriptor<Order>()
        let orders = (try? modelContext.fetch(orderDescriptor)) ?? []
        let orderById: [UUID: Order] = Dictionary(
            orders.map { ($0.id, $0) },
            uniquingKeysWith: { a, _ in a }
        )

        // A row needs repair when its createdAt looks like the migration default:
        // i.e. it sits at/after its own updatedAt (event time can never be later
        // than the last sync write) by more than a small tolerance.
        let tolerance: TimeInterval = 5.0
        var repaired = 0

        for txn in txns {
            let looksLikeMigrationDefault = txn.createdAt > txn.updatedAt.addingTimeInterval(tolerance)
            guard looksLikeMigrationDefault else { continue }

            if let refId = txn.referenceId, let order = orderById[refId] {
                txn.createdAt = order.createdAt
            } else {
                txn.createdAt = txn.updatedAt
            }
            // Mark unsynced so the corrected createdAt is pushed to Supabase by the
            // subsequent syncInventoryTransactions pass (which only uploads rows
            // with isSynced == false). Do NOT bump updatedAt — that is sync
            // metadata and must keep reflecting the real last-write time.
            txn.isSynced = false
            repaired += 1
        }

        if repaired > 0 {
            modelContext.saveWithLogging(label: #function)
        }
        UserDefaults.standard.set(true, forKey: Self.inventoryTxnCreatedAtBackfillKey)

        #if DEBUG
        print("SyncEngine [InventoryTxn createdAt backfill]: repaired \(repaired)/\(txns.count) rows")
        #endif
    }
}
