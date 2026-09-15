import Foundation
import SwiftData

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Order / Kitchen Lifecycle (Single Source of Truth)
// ─────────────────────────────────────────────────────────────────────────────
//
// PROBLEM THIS SOLVES
// -------------------
// A table could be "cleared" by the cashier (session closed, table → vacant)
// while its kitchen ticket was still non-terminal. The Kitchen Display kept
// showing the ticket forever (e.g. #9619 stuck "cooking" for 1,622 minutes)
// because:
//   1. The Vacant / Reserved / Cleaning buttons closed the session but never
//      flipped the order/items out of "preparing"/"cooking".
//   2. The KDS guard relied only on `session.isActive`, and broke entirely when
//      `order.tableSession == nil` (orphaned by the .nullify delete rule).
//
// The rules below make the ORDER the source of truth. A table is only truly
// clear when all of its orders are in a TERMINAL state, and clearing a table
// MUST terminalize its open orders (either as served/completed or voided).
//
// STATE MACHINE
// -------------
//   Order.status : preparing → ready → served → completed
//                            ↘ cancelled  (terminal, requires reason + auth)
//   OrderItem.status : cooking → served
//                              ↘ cancelled
//                              ↘ alert (still active on KDS)
//
// KDS action semantics (see KDSTicketActions):
//   • markStationReady / bump → items done cooking → order becomes `ready`
//     (item.status=served means station finished; servedBy stays nil)
//   • markStationDelivered / Clear Delivered → order becomes `served`
//     (sets servedBy when an actor name is available)
//
// Terminal order statuses: completed, cancelled  (also "served" once paid).
// A kitchen ticket is "active" only while it has items in cooking/alert.

enum OrderStatus {
    static let preparing = "preparing"
    static let ready     = "ready"
    static let served    = "served"
    static let completed = "completed"
    static let cancelled = "cancelled"

    /// Statuses in which the order still owns a live kitchen ticket.
    static let kitchenActive: Set<String> = [preparing, ready]
    /// Statuses that mean the order is done from the kitchen's perspective.
    static let terminal: Set<String> = [completed, cancelled]
}

enum OrderItemStatus {
    static let cooking   = "cooking"
    static let alert     = "alert"
    static let served    = "served"
    static let cancelled = "cancelled"

    /// Item statuses that keep a ticket visible on the KDS.
    static let active: Set<String> = [cooking, alert]
}

/// How to resolve open kitchen tickets when a table is being cleared.
enum TableClearResolution {
    /// The food was actually delivered — mark items served, order served.
    case serve
    /// The order is being abandoned — void items + order (needs reason/auth).
    case void(reason: String, employeeId: UUID?)
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Order helpers
// ─────────────────────────────────────────────────────────────────────────────

extension Order {

    /// Same rule as Staff `Order.isAwaitingStaffApproval` — pending / unconfirmed web orders.
    /// Once `isStaffConfirmed` is true, never keep the approval queue sticky even if
    /// local `status` briefly lags as `"pending"` after iPhone approve.
    var isAwaitingStaffApproval: Bool {
        let activeItems = items.filter { !$0.isDeleted && $0.status != "served" && $0.status != "cancelled" }
        guard !activeItems.isEmpty else { return false }
        let statusLower = status.lowercased()
        if ["cancelled", "completed", "served"].contains(statusLower) { return false }
        if isStaffConfirmed { return false }
        return statusLower == "pending" || orderSource.lowercased() == "web"
    }

    /// True while this order still has a live kitchen ticket
    /// (non-deleted, non-terminal, with at least one cooking/alert item).
    var hasActiveKitchenTicket: Bool {
        guard !isDeleted else { return false }
        guard OrderStatus.kitchenActive.contains(status) else { return false }
        if status == OrderStatus.ready {
            return items.contains { !$0.isDeleted && $0.status != OrderItemStatus.cancelled }
        }
        return items.contains {
            !$0.isDeleted && OrderItemStatus.active.contains($0.status)
        }
    }

    /// A ready order may notify staff only while it still belongs to a live
    /// table session. Counter/take-out orders remain valid but have no table
    /// number, so the table-specific delayed alert does not fabricate one.
    var isOperationalReadyOrder: Bool {
        guard !isDeleted, status == OrderStatus.ready else { return false }
        guard orderType == "dine_in", floorTableNumber != nil else { return true }
        return tableSession?.isActive == true
    }

    var activeTableNumber: String? {
        guard tableSession?.isActive == true,
              let number = tableSession?.table?.tableNumber,
              !number.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return number
    }

    /// Original table anchor retained after its session closes. Such orders
    /// must be recovered explicitly before approval to avoid printing or
    /// charging against a detached POS context.
    var recoveryTableNumber: String? {
        let number = floorTableNumber
            ?? tableSession?.table?.tableNumber
        let trimmed = number?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed : nil
    }

    var requiresTableSessionRecovery: Bool {
        guard isAwaitingStaffApproval, recoveryTableNumber != nil else {
            return false
        }
        guard let session = tableSession else { return true }
        return !session.isActive || session.isDeleted || session.table == nil
    }

    /// A dine-in order whose backing table session is gone or inactive is an
    /// ORPHAN — the floor thinks the table is free but the kitchen still holds
    /// the ticket. Take-out / delivery orders legitimately have no session, so
    /// they are never treated as orphans. Counter dine-in (no table) also keeps
    /// `floorTableNumber` nil so tickets still show on KDS.
    var isOrphanedKitchenTicket: Bool {
        guard hasActiveKitchenTicket else { return false }
        guard orderType == "dine_in" else { return false }
        let anchoredToTable = !(floorTableNumber?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty ?? true)
        guard anchoredToTable else { return false }
        guard let session = tableSession else { return true }   // session nullified
        return !session.isActive                                 // session closed
    }

    /// Mark the order + its cooking items as served (food delivered).
    /// Idempotent and sync-safe (flags everything unsynced).
    func markServed(at date: Date = Date()) {
        guard !isDeleted else { return }
        if OrderStatus.kitchenActive.contains(status) {
            status = OrderStatus.served
            readyAt = nil
            isSynced = false
            updatedAt = date
        }
        for item in items where !item.isDeleted && OrderItemStatus.active.contains(item.status) {
            item.status = OrderItemStatus.served
            item.isSynced = false
            item.updatedAt = date
        }
    }

    /// Void the order + its cooking items (order abandoned / clear-with-pending).
    /// Records an AuditLog so voids are traceable. Idempotent + sync-safe.
    @discardableResult
    @MainActor
    func voidForClear(reason: String,
                      employeeId: UUID?,
                      in context: ModelContext,
                      at date: Date = Date()) -> AuditLog? {
        guard !isDeleted else { return nil }
        guard hasActiveKitchenTicket else { return nil }

        let activeItems = items.filter { !$0.isDeleted && OrderItemStatus.active.contains($0.status) }
        let references = Set(activeItems.flatMap { [$0.id] + $0.modifiers.map(\.id) })
        InventoryReversalService.reverse(
            referenceIds: references,
            as: .void,
            notes: "Void on table clear — Order: \(orderNumber)",
            in: context
        )

        status = OrderStatus.cancelled
        readyAt = nil
        isSynced = false
        updatedAt = date
        for item in items where !item.isDeleted && OrderItemStatus.active.contains(item.status) {
            item.status = OrderItemStatus.cancelled
            item.isSynced = false
            item.updatedAt = date
        }

        let tableNo = tableSession?.table?.tableNumber ?? "-"
        let log = AuditLog(
            employeeId: employeeId,
            actionType: "order_void_on_clear",
            details: "Order \(orderNumber) (table \(tableNo)) voided on table clear. Reason: \(reason)",
            originalValue: total,
            newValue: 0
        )
        context.insert(log)
        return log
    }
}

extension Order {
    /// Manager-authorized cancellation used when an occupied table must be
    /// cleared before payment. This is intentionally a soft void rather than a
    /// hard delete so sales, inventory, and audit history remain reconcilable.
    @MainActor
    @discardableResult
    func voidUnsettledForTableClear(
        reason: String,
        employeeId: UUID?,
        in context: ModelContext,
        at date: Date = Date()
    ) -> AuditLog? {
        guard !isDeleted,
              !isSettled,
              status != OrderStatus.cancelled,
              !payments.contains(where: { !$0.isDeleted && $0.amount > 0.005 })
        else { return nil }

        let voidedItems = items.filter {
            !$0.isDeleted && $0.status != OrderItemStatus.cancelled
        }
        let references = Set(voidedItems.flatMap { [$0.id] + $0.modifiers.map(\.id) })
        InventoryReversalService.reverse(
            referenceIds: references,
            as: .void,
            notes: "Manager table clear — Order: \(orderNumber)",
            in: context
        )

        status = OrderStatus.cancelled
        readyAt = nil
        isSynced = false
        updatedAt = date
        for item in voidedItems {
            item.status = OrderItemStatus.cancelled
            item.isSynced = false
            item.updatedAt = date
        }

        let tableNo = tableSession?.table?.tableNumber ?? "-"
        let log = AuditLog(
            employeeId: employeeId,
            actionType: "unpaid_order_void_on_table_clear",
            details: "Order \(orderNumber) (table \(tableNo)) voided before payment. Reason: \(reason)",
            originalValue: total,
            newValue: 0
        )
        context.insert(log)
        return log
    }

    /// Comprehensive Order Void & Cancellation:
    /// Works for both unpaid orders and already paid/completed orders (e.g. duplicate entry, cashier error).
    /// If `restockInventory` is true, restores all ingredient lots and stock quantities via InventoryReversalService.
    /// If the order has completed payments, generates RefundTransactions, reverses payments, and records ledger events.
    /// Cancels all order items, terminalizes kitchen tickets, writes an AuditLog, and triggers synchronization.
    @MainActor
    @discardableResult
    func voidEntireOrder(
        reason: String,
        restockInventory: Bool,
        managerEmployeeId: UUID?,
        in context: ModelContext,
        at date: Date = Date()
    ) -> AuditLog? {
        guard !isDeleted, status != OrderStatus.cancelled else { return nil }

        let originalTotal = recognizedNetTotal

        // 1. Inventory reversal (if restock requested)
        if restockInventory {
            let activeItems = items.filter { !$0.isDeleted && $0.status != OrderItemStatus.cancelled }
            let references = Set(activeItems.flatMap { [$0.id] + $0.modifiers.map(\.id) })
            if !references.isEmpty {
                InventoryReversalService.reverse(
                    referenceIds: references,
                    as: .void,
                    notes: "Void order #\(orderNumber): \(reason)",
                    in: context
                )
            }
        }

        // 2. Financial reversal for any completed payments
        for payment in payments where !payment.isDeleted && payment.amount > 0.005 {
            let previouslyRefunded = refunds
                .filter { $0.originalPayment?.id == payment.id && !$0.isDeleted && $0.status == "completed" }
                .reduce(0.0) { $0 + $1.refundAmount }
            let unrefunded = max(0, payment.amount - previouslyRefunded)
            if unrefunded > 0.005 {
                let refund = RefundTransaction(
                    order: self,
                    originalPayment: payment,
                    refundAmount: unrefunded,
                    refundMethod: payment.paymentMethod,
                    reasonCode: "order_void",
                    reasonNotes: reason,
                    refundedByEmployeeId: managerEmployeeId,
                    approvedByEmployeeId: managerEmployeeId,
                    status: "completed"
                )
                BusinessDayContext.stamp(refund: refund, order: self, in: context)
                context.insert(refund)
                AccountingLedgerService.recordCompletedRefund(refund, order: self, in: context)

                payment.status = "refunded"
                payment.isSynced = false
                payment.updatedAt = date
            }
        }

        // 3. Mark order and items as cancelled
        status = OrderStatus.cancelled
        readyAt = nil
        isSynced = false
        updatedAt = date

        for item in items where !item.isDeleted {
            item.status = OrderItemStatus.cancelled
            item.isSynced = false
            item.updatedAt = date
        }

        // 4. Audit Log
        let log = AuditLog(
            employeeId: managerEmployeeId,
            actionType: "order_void_complete",
            details: "Order #\(orderNumber) voided. Reason: \(reason). Restocked: \(restockInventory)",
            originalValue: originalTotal,
            newValue: 0
        )
        context.insert(log)
        try? context.save()

        StockAlertEvaluator.refresh(modelContext: context)

        Task {
            await SyncEngine.shared.syncAll(modelContext: context)
        }

        return log
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - TableSession helpers
// ─────────────────────────────────────────────────────────────────────────────

extension TableSession {

    /// Orders on this session that still hold a live kitchen ticket.
    var openKitchenOrders: [Order] {
        orders.filter { $0.hasActiveKitchenTicket }
    }

    /// True when clearing this table would strand a ticket at the kitchen.
    var hasPendingKitchenTickets: Bool {
        !openKitchenOrders.isEmpty
    }

    /// Terminalize every open order on this session using the chosen resolution.
    /// Call this from EVERY table-clear path (vacant / cleaning / reserved /
    /// checkout / transfer) so the kitchen and the floor can never diverge.
    @MainActor
    func terminalizeOpenOrders(_ resolution: TableClearResolution,
                               in context: ModelContext,
                               at date: Date = Date()) {
        for order in openKitchenOrders {
            switch resolution {
            case .serve:
                order.markServed(at: date)
            case let .void(reason, employeeId):
                order.voidForClear(reason: reason, employeeId: employeeId, in: context, at: date)
            }
        }
    }
}
