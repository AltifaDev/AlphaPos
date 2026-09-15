import Foundation
import SwiftData
import os

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Kitchen ↔ Floor Reconciliation Sweep
// ─────────────────────────────────────────────────────────────────────────────
//
// This is the recovery net for state that has ALREADY diverged — e.g. tickets
// stranded before the guard rail existed, or divergence introduced by an
// offline device syncing stale rows. It runs as part of every sync cycle.
//
// Two independent problems are swept:
//
//   1. ORPHANED TICKETS — a dine-in order still holds a live kitchen ticket
//      (preparing/ready with cooking items) but its table session is gone or
//      inactive. The floor thinks the table is free; the KDS shows a ghost.
//      → auto-terminalize the order as "served" (food almost certainly went
//        out; we never silently delete revenue) and flag it unsynced so the
//        resolution propagates to every device.
//
//   2. STALE TICKETS — a ticket that has been cooking far longer than any real
//      dish could take (default 3h). These are almost always abandoned. We
//      raise a reconciliation alert for a human instead of guessing, and record
//      an AuditLog so the anomaly is traceable.
//
// Both passes are idempotent and safe to run repeatedly.

extension SyncEngine {

    /// Tickets cooking longer than this are considered stale and surfaced for
    /// human reconciliation (they cannot represent a real in-progress dish).
    static let staleTicketThreshold: TimeInterval = 3 * 60 * 60   // 3 hours

    func reconcileKitchenFloorState(modelContext: ModelContext) async {
        var descriptor = FetchDescriptor<Order>(
            predicate: #Predicate<Order> { $0.isDeleted == false }
        )
        descriptor.fetchLimit = 1000
        guard let orders = try? modelContext.fetch(descriptor), !orders.isEmpty else { return }

        let now = Date()
        var didChange = false
        var orphanCount = 0

        for order in orders {
            // ── Pass 1: orphaned tickets ──────────────────────────────────
            if order.isOrphanedKitchenTicket {
                // Grace Period: NEVER auto-serve tickets created/updated within 15 minutes (900s)
                // Prevents sync lag or transient unlinked sessions from mistakenly auto-serving live orders.
                let age = now.timeIntervalSince(order.updatedAt)
                guard age >= 900 else {
                    AppLogger.sync.info(
                        "Reconciliation: orphaned ticket candidate \(order.orderNumber, privacy: .public) within 15m grace period (\(Int(age))s) — skipping auto-serve."
                    )
                    continue
                }

                AppLogger.sync.warning(
                    "Reconciliation: orphaned kitchen ticket \(order.orderNumber, privacy: .public) (age \(Int(age / 60))m) — auto-serving."
                )
                order.markServed(at: now)

                let tableNo = order.tableSession?.table?.tableNumber ?? "-"
                let log = AuditLog(
                    actionType: "kitchen_ticket_reconciled",
                    details: "Orphaned ticket \(order.orderNumber) (table \(tableNo), age \(Int(age / 60))m) auto-served by reconciliation sweep — table had already been cleared.",
                    originalValue: order.total,
                    newValue: order.total
                )
                modelContext.insert(log)
                didChange = true
                orphanCount += 1
                continue
            }

            // ── Pass 2: stale tickets on still-active tables ──────────────
            if order.hasActiveKitchenTicket {
                let age = now.timeIntervalSince(order.createdAt)
                if age >= SyncEngine.staleTicketThreshold {
                    let orderId = order.id
                    // Reuse the delayed-order throttle so we don't spam alerts.
                    let shouldAlert: Bool
                    if let lastAlert = SyncEngine.getAlertTime(orderId) {
                        shouldAlert = now.timeIntervalSince(lastAlert) >= 3600
                    } else {
                        shouldAlert = true
                    }
                    if shouldAlert {
                        SyncEngine.setAlertTime(orderId, now)
                        let tableNo = order.tableSession?.table?.tableNumber ?? "-"
                        let minutes = Int(age / 60)
                        AppLogger.sync.error(
                            "Reconciliation: STALE ticket \(order.orderNumber, privacy: .public) cooking \(minutes)m — needs manual review."
                        )
                        _ = try? await NetworkManager.shared.createServiceRequest(
                            tableNumber: tableNo,
                            type: "Reconciliation Alert: Order #\(order.orderNumber) (table \(tableNo)) has been open for \(minutes) minutes — please verify and close it."
                        )
                        let log = AuditLog(
                            actionType: "kitchen_ticket_stale_flagged",
                            details: "Stale ticket \(order.orderNumber) (table \(tableNo)) open \(minutes)m flagged for manual reconciliation.",
                            originalValue: age,
                            newValue: nil
                        )
                        modelContext.insert(log)
                        didChange = true
                    }
                }
            }
        }

        if didChange {
            modelContext.saveWithLogging(label: "reconcileKitchenFloorState")
            if orphanCount > 0 {
                AppLogger.sync.notice("Reconciliation: resolved \(orphanCount, privacy: .public) orphaned ticket(s).")
            }
        }
    }
}
