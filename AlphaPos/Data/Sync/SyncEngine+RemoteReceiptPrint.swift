import Foundation
import SwiftData

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Pure decision gate (unit-testable, no SwiftData / actor dependency)
// ─────────────────────────────────────────────────────────────────────────────

enum RemoteReceiptPrintGate {
    /// Pure predicate deciding whether a remote receipt should print.
    ///
    /// Kept free of SwiftData / MainActor so it can be unit-tested in isolation.
    /// - Parameters:
    ///   - isStationEnabled: this iPad is opted in as the receipt station.
    ///   - orderExists: the order was found locally and is not deleted.
    ///   - hasLiveItems: the order has >=1 non-deleted line item (items synced).
    ///   - isCompleted: the order status == "completed" (bill fully settled;
    ///     set authoritatively by the complete_checkout RPC).
    static func shouldPrint(
        isStationEnabled: Bool,
        orderExists: Bool,
        hasLiveItems: Bool,
        isCompleted: Bool
    ) -> Bool {
        isStationEnabled && orderExists && hasLiveItems && isCompleted
    }

    /// Pure predicate deciding whether to send kitchen/bar tickets for an order
    /// on a realtime orders/order_items change.
    /// - Parameters:
    ///   - isStationEnabled: this iPad is the designated print station.
    ///   - orderActive: order status is neither "completed" nor "cancelled".
    ///   - hasUnprintedCookingItem: >=1 "cooking" line with a nil printedAt for
    ///     at least one station (kitchen/bar/label).
    static func shouldPrintKitchen(
        isStationEnabled: Bool,
        orderActive: Bool,
        hasUnprintedCookingItem: Bool
    ) -> Bool {
        isStationEnabled && orderActive && hasUnprintedCookingItem
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Remote Receipt Printing (Staff iPhone → iPad printer)
//
// When a staff device (AlphaPosStaff / iPhone) takes payment, it writes a row
// into the `payments` table on Supabase. This iPad is subscribed to that table
// via Realtime and keeps the receipt printer connected at all times. This
// extension turns an incoming `payments` change event into an automatic receipt
// print on the iPad — so staff can collect payment on the phone and the bill
// prints on the always-connected station printer.
//
// Three safeguards are enforced here (see AlphaPos design decisions):
//   1. Multi-iPad double-print guard  — only the iPad opted in as the receipt
//      station (`remote_receipt_print_enabled`) prints. PrintJobRecord
//      idempotency is per-device (local SwiftData) and does NOT coordinate
//      across devices, so this flag is what actually prevents N iPads from
//      each printing a copy.
//   2. Order-items completeness       — Realtime events can arrive before the
//      joined `order_items` have finished syncing. We only print once the local
//      Order actually has (non-deleted) line items, retrying briefly otherwise.
//   3. Split / mixed payment          — split & mixed payments insert several
//      `payments` rows. The final row is written via the `complete_checkout`
//      RPC, which authoritatively flips `orders.status = 'completed'`. We treat
//      that status as the "bill fully settled" signal, so a multi-row bill
//      prints exactly one final receipt rather than one per payment fragment.
//      (A payment-sum check is NOT used as the primary gate because the amount
//      recorded is the grand total incl. tax + service charge, whereas
//      `order.total`'s composition varies across call sites — status is the
//      reliable signal.)
// ─────────────────────────────────────────────────────────────────────────────

extension SyncEngine {

    /// UserDefaults key: set to `true` on exactly ONE iPad per branch to make it
    /// the receipt-printing station for payments taken on staff devices.
    static let remoteReceiptPrintEnabledKey = "remote_receipt_print_enabled"
    static let remoteKitchenPrintEnabledKey = "remote_kitchen_print_enabled"

    /// Entry point invoked from the Realtime `payments` case, AFTER
    /// `pullCompletedOrdersAndPayments` has upserted the order + items + payments
    /// into the local store.
    ///
    /// Also used by `sync_outbox` `print_receipt` jobs from Staff (manual reprint).
    /// Payload may include `force: true` and/or `order_ids: [uuid…]`.
    ///
    /// - Parameters:
    ///   - record: the changed `payments` row from the Realtime payload
    ///             (`payload.data.record`). May be nil for composite events.
    ///   - modelContext: the active SwiftData context.
    @MainActor
    func handleRemotePaymentPrint(record: [String: Any]?, modelContext: ModelContext) async {
        // ── Guard 1: only the designated receipt-station iPad prints ──────────
        guard UserDefaults.standard.bool(forKey: Self.remoteReceiptPrintEnabledKey) else {
            return
        }

        let force = (record?["force"] as? Bool) == true
            || (record?["force"] as? String)?.lowercased() == "true"

        // Prefer explicit order_ids (Staff manual / multi-order), else single order_id.
        var orderIdStrings: [String] = []
        if let ids = record?["order_ids"] as? [String] {
            orderIdStrings = ids
        } else if let ids = record?["order_ids"] as? [Any] {
            orderIdStrings = ids.compactMap { $0 as? String }
        }
        if orderIdStrings.isEmpty,
           let single = (record?["order_id"] as? String) ?? (record?["orderId"] as? String) {
            orderIdStrings = [single]
        }
        guard !orderIdStrings.isEmpty else {
            #if DEBUG
            print("SyncEngine [RemotePrint]: No resolvable order_id in payment record — skipping.")
            #endif
            return
        }

        for orderIdStr in orderIdStrings {
            guard let orderId = UUID(uuidString: orderIdStr) else { continue }

            // ── Guard 2 + 3: wait for the order to be fully synced AND settled ────
            // Manual force reprints still require a local order with items, but
            // skip the "completed" wait when force is set (order may already be
            // completed and just needs a reprint).
            var order = fetchLocalOrder(id: orderId, modelContext: modelContext)
            var attempt = 0
            while !isReadyToPrint(order, requireCompleted: !force), attempt < 4 {
                attempt += 1
                try? await Task.sleep(for: .milliseconds(600))
                await pullCompletedOrdersAndPayments(modelContext)
                order = fetchLocalOrder(id: orderId, modelContext: modelContext)
            }

            guard let order, isReadyToPrint(order, requireCompleted: !force) else {
                #if DEBUG
                print("SyncEngine [RemotePrint]: Order \(orderId) not ready to print after retries — skipping.")
                #endif
                continue
            }

            #if DEBUG
            let collected = settledPaymentTotal(order)
            print("SyncEngine [RemotePrint]: Dispatching receipt for order \(order.orderNumber) — status=\(order.status), paid=\(collected)/\(order.total), force=\(force).")
            #endif

            await PrintService.shared.dispatchReceipt(order, forcePrintReceipt: force)
        }
    }

    /// Staff iPhone requested an unpaid guest check — print pre-bill on this station.
    @MainActor
    @discardableResult
    func handleRemotePreBillPrint(payload: [String: Any], modelContext: ModelContext) async -> Bool {
        guard UserDefaults.standard.bool(forKey: Self.remoteReceiptPrintEnabledKey) else {
            return false
        }

        var orderIdStrings: [String] = []
        if let ids = payload["order_ids"] as? [String] {
            orderIdStrings = ids
        } else if let ids = payload["order_ids"] as? [Any] {
            orderIdStrings = ids.compactMap { $0 as? String }
        }
        guard !orderIdStrings.isEmpty else {
            #if DEBUG
            print("SyncEngine [RemotePreBill]: Missing order_ids — skipping.")
            #endif
            return false
        }

        // Pull latest orders/items so Staff-created lines are present locally.
        await pullCustomerOrders(modelContext)
        await pullCompletedOrdersAndPayments(modelContext)

        var orders: [Order] = []
        for idStr in orderIdStrings {
            guard let uuid = UUID(uuidString: idStr) else { continue }
            var order = fetchLocalOrder(id: uuid, modelContext: modelContext)
            var attempt = 0
            while (order == nil || !(order?.items.contains { !$0.isDeleted } ?? false)) && attempt < 4 {
                attempt += 1
                try? await Task.sleep(for: .milliseconds(500))
                await pullCustomerOrders(modelContext)
                order = fetchLocalOrder(id: uuid, modelContext: modelContext)
            }
            if let order, !order.isDeleted {
                orders.append(order)
            }
        }

        // Fallback: resolve by table number if ids did not hydrate yet.
        if orders.isEmpty, let tableNumber = payload["table_number"] as? String, !tableNumber.isEmpty {
            let all = (try? modelContext.fetch(FetchDescriptor<Order>())) ?? []
            orders = all.filter {
                !$0.isDeleted &&
                ($0.tableSession?.table?.tableNumber == tableNumber) &&
                $0.status != "cancelled" &&
                !$0.isSettled &&
                $0.items.contains { !$0.isDeleted && $0.status != "cancelled" }
            }
        }

        guard !orders.isEmpty else {
            #if DEBUG
            print("SyncEngine [RemotePreBill]: No local orders resolved — skipping.")
            #endif
            return false
        }

        #if DEBUG
        print("SyncEngine [RemotePreBill]: Printing pre-bill for \(orders.count) order(s).")
        #endif
        let result = await PrintService.shared.dispatchPreBill(orders: orders)
        return result.success
    }

    /// An order is ready for a remote receipt print when it exists, is not
    /// deleted, has at least one live line item (items finished syncing), and
    /// (unless force-reprint) has been authoritatively marked "completed".
    @MainActor
    private func isReadyToPrint(_ order: Order?, requireCompleted: Bool = true) -> Bool {
        guard let order, !order.isDeleted else {
            return RemoteReceiptPrintGate.shouldPrint(
                isStationEnabled: true, orderExists: false,
                hasLiveItems: false, isCompleted: false
            )
        }
        let hasItems = order.items.contains { !$0.isDeleted }
        let completed = order.status == "completed"
        return RemoteReceiptPrintGate.shouldPrint(
            isStationEnabled: true,
            orderExists: true,
            hasLiveItems: hasItems,
            isCompleted: requireCompleted ? completed : true
        )
    }

    /// Sum of completed, non-deleted payments — used for diagnostics/logging.
    @MainActor
    private func settledPaymentTotal(_ order: Order) -> Double {
        order.payments
            .filter { !$0.isDeleted && $0.status == "completed" }
            .reduce(0.0) { $0 + $1.amount }
    }

    /// Local-store lookup for an Order by id (mirrors PrintService.fetchOrder,
    /// which is private to that type).
    @MainActor
    private func fetchLocalOrder(id: UUID, modelContext: ModelContext) -> Order? {
        var descriptor = FetchDescriptor<Order>(predicate: #Predicate<Order> { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Remote Kitchen / Bar Printing (Staff iPhone / Web → this iPad)
    //
    // Staff phones and the web ordering channel never print directly — they
    // only write orders/order_items to Supabase. When an order is sent to the
    // kitchen from a phone (uploadOrder) or a pending web order is approved
    // (items promoted to "cooking"), this iPad — the always-connected station —
    // reacts to the realtime orders/order_items change and prints the kitchen,
    // bar, and sticker tickets for any not-yet-printed lines.
    //
    // Guards mirror the receipt path:
    //   1. Only the designated kitchen print station iPad prints.
    //   2. Only "cooking" items that have no printedAt stamp are sent, so
    //      repeated realtime events never reprint an existing ticket.
    // ─────────────────────────────────────────────────────────────────────────

    /// Called from the Realtime `orders` / `order_items` case, AFTER
    /// pullCustomerOrders has upserted orders + items into the local store.
    @MainActor
    func handleRemoteKitchenPrint(modelContext: ModelContext) async {
        // Guard 1: only if designated kitchen/bar/sticker print station is enabled (defaults to false until configured)
        guard UserDefaults.standard.bool(forKey: Self.remoteKitchenPrintEnabledKey) else {
            return
        }

        // Guard 2: only if at least one active physical printer exists in the store
        guard PrintService.shared.hasAnyActivePrinter else {
            return
        }

        // Find local orders that currently have unprinted "cooking" lines.
        // Scope to non-completed, non-cancelled orders so we never re-fire
        // kitchen tickets for a bill that is already closed.
        let descriptor = FetchDescriptor<Order>()
        let orders = (try? modelContext.fetch(descriptor)) ?? []

        for order in orders where !order.isDeleted {
            let orderActive = order.status != "completed" && order.status != "cancelled"
            let hasUnprintedCooking = order.items.contains { item in
                !item.isDeleted
                    && item.status == "cooking"
                    && (item.kitchenPrintedAt == nil || item.barPrintedAt == nil || item.labelPrintedAt == nil)
            }
            guard RemoteReceiptPrintGate.shouldPrintKitchen(
                isStationEnabled: true,   // station flag already checked above
                orderActive: orderActive,
                hasUnprintedCookingItem: hasUnprintedCooking
            ) else { continue }

            #if DEBUG
            print("SyncEngine [RemotePrint]: Dispatching kitchen/bar tickets for order \(order.orderNumber).")
            #endif
            // Idempotent: only unprinted lines are sent, and PrintJobRecord +
            // per-item printedAt stamps prevent duplicates across repeat events.
            await PrintService.shared.dispatchIncrementalKitchenOrder(order)
        }
    }

}
