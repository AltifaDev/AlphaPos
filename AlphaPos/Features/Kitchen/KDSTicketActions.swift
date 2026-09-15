import Foundation
import SwiftData

// MARK: - KDS Ticket Actions (Single Source of Truth)
//
// State machine (order):
//   preparing → ready → served → completed
//
// Semantics:
//   • markReady* / bump  → kitchen/bar finished cooking → order becomes `ready`
//     (item.status = served means "done for this station"; servedBy stays nil)
//   • markDelivered*     → food handed to guest / cleared → order becomes `served`
//     (sets servedBy when provided)
//   • recall*            → return items to cooking → order becomes preparing/ready
//
// Every mutation flags isSynced=false, saves, and triggers SyncEngine.syncAll.

@MainActor
enum KDSTicketActions {

    /// Repairs legacy Quick Service tickets that were financially closed but
    /// never bumped by kitchen staff. The age gate prevents a newly paid order
    /// from disappearing while it is still being prepared.
    @discardableResult
    static func reconcileStaleQuickServiceOrders(
        _ orders: [Order],
        tableSystemEnabled: Bool,
        olderThan threshold: TimeInterval = 3 * 60 * 60,
        now: Date = Date(),
        in context: ModelContext,
        sync: Bool = true
    ) -> Int {
        var reconciled = 0

        for order in orders where !order.isDeleted {
            let identity = OrderDisplayIdentity(
                order: order,
                tableSystemEnabled: tableSystemEnabled
            )
            guard identity.isQuickService else { continue }
            guard order.isSettled || order.status == OrderStatus.completed else { continue }
            guard now.timeIntervalSince(order.createdAt) >= threshold else { continue }

            let activeItems = order.items.filter {
                !$0.isDeleted && OrderItemStatus.active.contains($0.status)
            }
            guard !activeItems.isEmpty else { continue }

            for item in activeItems {
                item.status = OrderItemStatus.served
                item.servedBy = nil
                item.updatedAt = now
                item.isSynced = false
            }

            // Preserve `completed` because it is the financial terminal state.
            if order.status != OrderStatus.completed {
                order.status = OrderStatus.served
            }
            order.readyAt = nil
            order.updatedAt = now
            order.isSynced = false

            context.insert(AuditLog(
                actionType: "system_reconciled_stale_quick_service",
                details: "Automatically archived stale paid Quick Service order \(order.orderNumber) after \(Int(now.timeIntervalSince(order.createdAt) / 60)) minutes.",
                originalValue: Double(activeItems.count),
                newValue: 0,
                createdAt: now,
                updatedAt: now
            ))
            reconciled += 1
        }

        guard reconciled > 0 else { return 0 }
        context.saveWithLogging(label: "KDS.reconcileStaleQuickServiceOrders")
        if sync {
            Task { await SyncEngine.shared.syncAll(modelContext: context) }
        }
        return reconciled
    }

    // MARK: - Ready (done cooking)

    /// Mark one item done cooking. Promotes order to `ready` when nothing active remains.
    @discardableResult
    static func markItemReady(
        _ item: OrderItem,
        order: Order,
        completeQuickServiceWhenReady: Bool = false,
        in context: ModelContext,
        sync: Bool = true
    ) -> Bool {
        guard !item.isDeleted else { return false }
        guard OrderItemStatus.active.contains(item.status) else { return false }

        item.status = OrderItemStatus.served
        item.servedBy = nil
        item.updatedAt = Date()
        item.isSynced = false

        refreshOrderStatusAfterItemChange(order)
        completeQuickServiceIfReady(order, enabled: completeQuickServiceWhenReady)
        persist(order: order, in: context, sync: sync, label: "KDS.markItemReady")
        return true
    }

    /// Toggle item between cooking ↔ done-for-station (cook UX on premium cards).
    @discardableResult
    static func toggleItemReady(
        _ item: OrderItem,
        order: Order,
        completeQuickServiceWhenReady: Bool = false,
        in context: ModelContext,
        sync: Bool = true
    ) -> Bool {
        guard item.status != OrderItemStatus.cancelled, !item.isDeleted else { return false }

        if item.status == OrderItemStatus.served {
            item.status = OrderItemStatus.cooking
            item.servedBy = nil
        } else {
            item.status = OrderItemStatus.served
            item.servedBy = nil
        }
        item.updatedAt = Date()
        item.isSynced = false

        refreshOrderStatusAfterItemChange(order)
        completeQuickServiceIfReady(order, enabled: completeQuickServiceWhenReady)
        persist(order: order, in: context, sync: sync, label: "KDS.toggleItemReady")
        return true
    }

    /// Mark all active items for a station as done cooking → order `ready` when none left.
    @discardableResult
    static func markStationReady(
        order: Order,
        station: KDSStation,
        completeQuickServiceWhenReady: Bool = false,
        in context: ModelContext,
        sync: Bool = true
    ) -> Bool {
        var didChange = false
        let now = Date()
        for item in order.items where !item.isDeleted {
            guard OrderItemStatus.active.contains(item.status), item.shouldDisplay(on: station) else { continue }
            item.status = OrderItemStatus.served
            item.servedBy = nil
            item.updatedAt = now
            item.isSynced = false
            didChange = true
        }
        guard didChange else { return false }

        refreshOrderStatusAfterItemChange(order)
        completeQuickServiceIfReady(order, enabled: completeQuickServiceWhenReady)
        persist(order: order, in: context, sync: sync, label: "KDS.markStationReady")
        return true
    }

    // MARK: - Delivered (food to guest)

    /// Confirm delivery for the order: remaining station actives → served, order → `served`.
    @discardableResult
    static func markStationDelivered(
        order: Order,
        station: KDSStation,
        actorName: String?,
        in context: ModelContext,
        sync: Bool = true
    ) -> Bool {
        var didChange = false
        let now = Date()
        let actor = normalizedActor(actorName)

        for item in order.items where !item.isDeleted {
            let matchStation = item.shouldDisplay(on: station)
            if OrderItemStatus.active.contains(item.status) && matchStation {
                item.status = OrderItemStatus.served
                if item.servedBy == nil || item.servedBy?.isEmpty == true {
                    item.servedBy = actor
                }
                item.updatedAt = now
                item.isSynced = false
                didChange = true
            } else if item.status == OrderItemStatus.served,
                      matchStation,
                      (item.servedBy == nil || item.servedBy?.isEmpty == true),
                      let actor {
                item.servedBy = actor
                item.updatedAt = now
                item.isSynced = false
                didChange = true
            }
        }

        let stillActive = order.items.contains {
            !$0.isDeleted && OrderItemStatus.active.contains($0.status)
        }
        if !stillActive && OrderStatus.kitchenActive.contains(order.status) {
            order.status = OrderStatus.served
            didChange = true
        }

        guard didChange else { return false }
        order.isSynced = false
        order.updatedAt = now
        persist(order: order, in: context, sync: sync, label: "KDS.markStationDelivered")
        return true
    }

    /// Auto-complete / bulk: promote a `ready` order with all terminal items → `served`.
    @discardableResult
    static func markOrderDelivered(
        order: Order,
        actorName: String?,
        in context: ModelContext,
        sync: Bool = true
    ) -> Bool {
        guard order.status == OrderStatus.ready else { return false }
        guard !order.isOrphanedKitchenTicket else { return false }

        let allItemsDone = order.items.allSatisfy { item in
            item.isDeleted
                || item.status == OrderItemStatus.served
                || item.status == OrderItemStatus.cancelled
        }
        guard allItemsDone else { return false }

        let now = Date()
        let actor = normalizedActor(actorName)
        order.status = OrderStatus.served
        order.updatedAt = now
        order.isSynced = false

        if let actor {
            for item in order.items where !item.isDeleted && item.status == OrderItemStatus.served {
                if item.servedBy == nil || item.servedBy?.isEmpty == true {
                    item.servedBy = actor
                    item.updatedAt = now
                    item.isSynced = false
                }
            }
        }

        persist(order: order, in: context, sync: sync, label: "KDS.markOrderDelivered")
        return true
    }

    // MARK: - Recall

    @discardableResult
    static func recallItem(
        _ item: OrderItem,
        order: Order,
        in context: ModelContext,
        sync: Bool = true
    ) -> Bool {
        guard !item.isDeleted else { return false }
        guard item.status == OrderItemStatus.served else { return false }

        item.status = OrderItemStatus.cooking
        item.servedBy = nil
        item.updatedAt = Date()
        item.isSynced = false

        refreshOrderStatusAfterItemChange(order)
        persist(order: order, in: context, sync: sync, label: "KDS.recallItem")
        return true
    }

    /// Recall an entire order (history / last-served). Restores station-visible served items.
    @discardableResult
    static func recallOrder(
        _ order: Order,
        showKitchen: Bool,
        showBar: Bool,
        restoreAllServedItems: Bool = false,
        in context: ModelContext,
        sync: Bool = true
    ) -> Bool {
        let now = Date()

        order.status = OrderStatus.preparing
        order.updatedAt = now
        order.isSynced = false

        for item in order.items where !item.isDeleted {
            guard item.status == OrderItemStatus.served else { continue }
            let matchesStation = restoreAllServedItems
                || item.shouldDisplay(showKitchen: showKitchen, showBar: showBar)
            guard matchesStation else { continue }
            item.status = OrderItemStatus.cooking
            item.servedBy = nil
            item.updatedAt = now
            item.isSynced = false
        }

        persist(order: order, in: context, sync: sync, label: "KDS.recallOrder")
        return true
    }

    // MARK: - Alert / Cancel

    @discardableResult
    static func alertItem(
        _ item: OrderItem,
        order: Order,
        in context: ModelContext,
        sync: Bool = true,
        notifyWaiter: Bool = true
    ) -> Bool {
        guard !item.isDeleted else { return false }
        guard item.status != OrderItemStatus.cancelled else { return false }

        item.status = OrderItemStatus.alert
        item.updatedAt = Date()
        item.isSynced = false
        order.isSynced = false
        order.updatedAt = Date()

        persist(order: order, in: context, sync: sync, label: "KDS.alertItem")

        if notifyWaiter {
            Task {
                let tableSystemEnabled = UserDefaults.standard.object(forKey: "enable_table_system") as? Bool ?? true
                let reference = OrderDisplayIdentity(
                    order: order,
                    tableSystemEnabled: tableSystemEnabled
                ).serviceReference
                let itemName = item.menuItem?.name ?? item.itemName
                _ = try? await NetworkManager.shared.createServiceRequest(
                    tableNumber: reference,
                    type: "Kitchen Alert: \(itemName) Issue"
                )
            }
        }
        return true
    }

    @discardableResult
    static func cancelItem(
        _ item: OrderItem,
        order: Order,
        station: KDSStation,
        completeQuickServiceWhenReady: Bool = false,
        in context: ModelContext,
        sync: Bool = true
    ) -> Bool {
        guard !item.isDeleted else { return false }
        guard item.status != OrderItemStatus.cancelled else { return false }

        item.status = OrderItemStatus.cancelled
        item.updatedAt = Date()
        item.isSynced = false

        refreshOrderStatusAfterItemChange(order)
        completeQuickServiceIfReady(order, enabled: completeQuickServiceWhenReady)
        persist(order: order, in: context, sync: sync, label: "KDS.cancelItem")
        return true
    }

    static func requestWaiter(for order: Order) {
        Task {
            let tableSystemEnabled = UserDefaults.standard.object(forKey: "enable_table_system") as? Bool ?? true
            let reference = OrderDisplayIdentity(
                order: order,
                tableSystemEnabled: tableSystemEnabled
            ).serviceReference
            _ = try? await NetworkManager.shared.createServiceRequest(
                tableNumber: reference,
                type: "KDS Alert: \(OrderDisplayIdentity.label(forServiceReference: reference)) Requesting Staff"
            )
        }
    }

    /// True when the station has no remaining cooking/alert items (detail/footer switch).
    static func stationHasActiveItems(order: Order, station: KDSStation) -> Bool {
        order.items.contains {
            !$0.isDeleted
                && OrderItemStatus.active.contains($0.status)
                && $0.shouldDisplay(on: station)
        }
    }

    // MARK: - Internals

    private static func refreshOrderStatusAfterItemChange(_ order: Order) {
        let hasActive = order.items.contains {
            !$0.isDeleted && OrderItemStatus.active.contains($0.status)
        }
        // Paid Quick Service orders remain financially `completed`. KDS owns the
        // item fulfilment state, but must not reopen completed sales and remove
        // them from reports when a cook bumps or recalls an item.
        if order.status == OrderStatus.completed {
            order.isSynced = false
            order.updatedAt = Date()
            return
        }
        if hasActive {
            if order.status != OrderStatus.preparing {
                order.status = OrderStatus.preparing
            }
            order.readyAt = nil
        } else if OrderStatus.kitchenActive.contains(order.status) || order.status == OrderStatus.preparing {
            if order.status != OrderStatus.ready {
                order.status = OrderStatus.ready
                order.readyAt = Date()
            }
        }
        order.isSynced = false
        order.updatedAt = Date()
    }

    /// Quick Service has no waiter hand-off step. Once every prep station is
    /// finished, close the kitchen ticket in the same bump action. Table
    /// Service deliberately remains `ready` until delivery is confirmed.
    private static func completeQuickServiceIfReady(_ order: Order, enabled: Bool) {
        guard enabled, order.status == OrderStatus.ready else { return }
        let allItemsDone = order.items.allSatisfy {
            $0.isDeleted
                || $0.status == OrderItemStatus.served
                || $0.status == OrderItemStatus.cancelled
        }
        guard allItemsDone else { return }
        order.status = OrderStatus.served
        order.readyAt = nil
        order.isSynced = false
        order.updatedAt = Date()
    }

    private static func persist(
        order: Order,
        in context: ModelContext,
        sync: Bool,
        label: String
    ) {
        context.saveWithLogging(label: label)
        guard sync else { return }
        Task {
            await SyncEngine.shared.syncAll(modelContext: context)
        }
    }

    private static func normalizedActor(_ name: String?) -> String? {
        guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
