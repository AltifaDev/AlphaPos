// KitchenLifecycleTests.swift
// AlphaPos — Kitchen ↔ Floor state-consistency tests
//
// Covers the bug where a table was cleared by the cashier while its kitchen
// ticket was still live: the floor showed the table vacant while the KDS kept
// the ghost ticket forever (#9619 stuck "cooking" for 1,622 minutes).
//
// The production logic lives on SwiftData @Model types (Order / OrderItem /
// TableSession) in Models/Order+Lifecycle.swift and the reconciliation sweep in
// Data/Sync/SyncEngine+Reconciliation.swift. Those cannot be exercised by the
// swiftc-based run_tests.sh (no SwiftData), so — exactly like OrderSettlementTests
// — we mirror the PURE decision logic here and assert on it. The mirror is kept
// byte-for-byte equivalent to the real predicates.

import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Pure logic mirror (kept equivalent to Order+Lifecycle / Reconciliation)
// ─────────────────────────────────────────────────────────────────────────────

enum KitchenLifecycleLogic {

    // Mirrors OrderStatus / OrderItemStatus sets.
    static let kitchenActiveStatuses: Set<String> = ["preparing", "ready"]
    static let terminalStatuses: Set<String> = ["completed", "cancelled"]
    static let activeItemStatuses: Set<String> = ["cooking", "alert"]

    /// Mirror of Order.hasActiveKitchenTicket.
    static func hasActiveKitchenTicket(
        isDeleted: Bool,
        status: String,
        itemStatuses: [String]      // non-deleted items only
    ) -> Bool {
        guard !isDeleted else { return false }
        guard kitchenActiveStatuses.contains(status) else { return false }
        if status == "ready" {
            return itemStatuses.contains { $0 != "cancelled" }
        }
        return itemStatuses.contains { activeItemStatuses.contains($0) }
    }

    static func shouldSendDeliveryDelayAlert(
        isDeleted: Bool,
        status: String,
        sessionActive: Bool?,
        tableNumber: String?,
        readyAt: Date?,
        now: Date
    ) -> Bool {
        guard !isDeleted, status == "ready", sessionActive == true else { return false }
        guard !(tableNumber?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) else { return false }
        guard let readyAt else { return false }
        return now.timeIntervalSince(readyAt) >= 600
    }

    /// Mirror of Order.isOrphanedKitchenTicket.
    /// sessionState: nil = no session (nullified), true = active, false = inactive.
    static func isOrphanedKitchenTicket(
        isDeleted: Bool,
        status: String,
        itemStatuses: [String],
        orderType: String,
        sessionActive: Bool?,
        floorTableNumber: String? = nil
    ) -> Bool {
        guard hasActiveKitchenTicket(isDeleted: isDeleted, status: status, itemStatuses: itemStatuses) else { return false }
        guard orderType == "dine_in" else { return false }
        let anchored = !(floorTableNumber?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        guard anchored else { return false }
        guard let active = sessionActive else { return true }   // session nullified → orphan
        return !active                                          // session closed → orphan
    }

    /// Mirror of the KDS guard decision: should this ticket be shown on the KDS?
    static func shouldDisplayOnKDS(
        isDeleted: Bool,
        status: String,
        itemStatuses: [String],
        orderType: String,
        sessionActive: Bool?,
        floorTableNumber: String? = nil
    ) -> Bool {
        // Orphans are skipped; everything else with a live ticket is shown.
        if isOrphanedKitchenTicket(isDeleted: isDeleted, status: status,
                                   itemStatuses: itemStatuses, orderType: orderType,
                                   sessionActive: sessionActive,
                                   floorTableNumber: floorTableNumber) {
            return false
        }
        return hasActiveKitchenTicket(isDeleted: isDeleted, status: status, itemStatuses: itemStatuses)
    }

    /// Mirror of markServed: returns the resulting (orderStatus, itemStatuses).
    static func markServed(status: String, itemStatuses: [String]) -> (String, [String]) {
        let newStatus = kitchenActiveStatuses.contains(status) ? "served" : status
        let newItems = itemStatuses.map { activeItemStatuses.contains($0) ? "served" : $0 }
        return (newStatus, newItems)
    }

    /// Mirror of voidForClear: returns the resulting (orderStatus, itemStatuses).
    static func voidForClear(status: String, itemStatuses: [String]) -> (String, [String]) {
        let newItems = itemStatuses.map { activeItemStatuses.contains($0) ? "cancelled" : $0 }
        return ("cancelled", newItems)
    }

    /// Mirror of reconciliation stale check.
    static func isStale(ageSeconds: TimeInterval, threshold: TimeInterval = 3 * 60 * 60) -> Bool {
        ageSeconds >= threshold
    }

    static func shouldReconcileStaleQuickService(
        isQuickService: Bool,
        isSettled: Bool,
        isCompleted: Bool,
        hasActiveItems: Bool,
        ageSeconds: TimeInterval,
        threshold: TimeInterval = 3 * 60 * 60
    ) -> Bool {
        isQuickService
            && (isSettled || isCompleted)
            && hasActiveItems
            && ageSeconds >= threshold
    }

    static func isVisibleInLiveQueue(
        isSettled: Bool,
        ageSeconds: TimeInterval,
        staleThreshold: TimeInterval = 60 * 60
    ) -> Bool {
        !isSettled && ageSeconds < staleThreshold
    }

    // Mirror of the KitchenOrderDetailView list rendering decision (the ForEach
    // bug): items must render when the displayed list is non-empty.
    static func detailShowsItems(displayedCount: Int) -> Bool {
        displayedCount > 0
    }

    // ── KDSTicketActions mirrors ───────────────────────────────────────────
    // Ready = done cooking → order `ready`. Delivered = food to guest → `served`.

    /// Mirror of markStationReady / bump: station items cooking/alert → served;
    /// order becomes ready only when NO active items remain anywhere.
    static func markStationReady(
        orderStatus: String,
        itemStatuses: [String],
        stationMask: [Bool], // true = item belongs to this station
        isQuickService: Bool = false
    ) -> (String, [String]) {
        var items = itemStatuses
        for i in items.indices where stationMask[i] && activeItemStatuses.contains(items[i]) {
            items[i] = "served"
        }
        let stillActive = items.contains { activeItemStatuses.contains($0) }
        if stillActive { return ("preparing", items) }
        if orderStatus == "completed" { return ("completed", items) }
        return (isQuickService ? "served" : "ready", items)
    }

    /// Mirror of markStationDelivered / Clear Delivered.
    static func markStationDelivered(
        orderStatus: String,
        itemStatuses: [String],
        stationMask: [Bool]
    ) -> (String, [String]) {
        var items = itemStatuses
        for i in items.indices where stationMask[i] && activeItemStatuses.contains(items[i]) {
            items[i] = "served"
        }
        let stillActive = items.contains { activeItemStatuses.contains($0) }
        if !stillActive && kitchenActiveStatuses.contains(orderStatus) {
            return ("served", items)
        }
        return (orderStatus, items)
    }

    /// Mirror of markOrderDelivered auto-complete (ready + all terminal → served).
    static func markOrderDelivered(orderStatus: String, itemStatuses: [String]) -> String? {
        guard orderStatus == "ready" else { return nil }
        let allDone = itemStatuses.allSatisfy { $0 == "served" || $0 == "cancelled" }
        return allDone ? "served" : nil
    }

    /// Mirror of recallItem: served → cooking; order preparing if any active.
    static func recallItem(orderStatus: String, itemStatuses: [String], index: Int) -> (String, [String]) {
        var items = itemStatuses
        guard items.indices.contains(index), items[index] == "served" else {
            return (orderStatus, items)
        }
        items[index] = "cooking"
        let hasActive = items.contains { activeItemStatuses.contains($0) }
        return (hasActive ? "preparing" : "ready", items)
    }
}

enum KitchenLifecycleTests {

    static func runAll() -> [TestResult] {
        [
            test_activeTicketWhenPreparingWithCookingItem(),
            test_noActiveTicketWhenServed(),
            test_noActiveTicketWhenDeleted(),
            test_readyOrderRemainsPendingDelivery(),
            test_orphanWhenSessionNullified(),
            test_readyOrphanWhenSessionNullified(),
            test_orphanWhenSessionInactive(),
            test_notOrphanWhenSessionActive(),
            test_counterDineInNotOrphan(),
            test_takeoutNeverOrphan(),
            test_kdsHidesOrphan(),
            test_kdsShowsCounterDineIn(),
            test_kdsShowsActiveDineIn(),
            test_markServedTerminalizes(),
            test_markServedIdempotentOnServed(),
            test_voidForClearCancelsEverything(),
            test_staleThreshold(),
            test_notStaleUnderThreshold(),
            test_reconcilesPaidStaleQuickService(),
            test_doesNotReconcileFreshQuickService(),
            test_doesNotReconcileUnpaidQuickService(),
            test_doesNotReconcileTableService(),
            test_paidOrderLeavesLiveQueueImmediately(),
            test_unpaidStaleOrderLeavesLiveQueueWithoutDeletion(),
            test_freshUnpaidOrderRemainsLive(),
            test_deliveryAlertRequiresActiveTable(),
            test_deliveryAlertUsesReadyTime(),
            test_detailRendersWhenItemsPresent(),
            test_detailEmptyStateWhenNoItems(),
            test_markStationReadyPromotesToReady(),
            test_markStationReadyKeepsPreparingWhenOtherStationActive(),
            test_quickServiceBumpCompletesInOneAction(),
            test_quickServiceWaitsForOtherStation(),
            test_tableServiceStillWaitsForDelivery(),
            test_paidQuickServicePreservesCompletedStatus(),
            test_bumpDoesNotSkipToServed(),
            test_markStationDeliveredSetsServed(),
            test_autoCompleteOnlyFromReady(),
            test_recallItemReturnsToPreparing()
        ]
    }

    // ── hasActiveKitchenTicket ────────────────────────────────────────────

    private static func test_activeTicketWhenPreparingWithCookingItem() -> TestResult {
        let name = #function
        return KitchenLifecycleLogic.hasActiveKitchenTicket(
            isDeleted: false, status: "preparing", itemStatuses: ["cooking"]
        ) ? .success(name) : .failure(name, "preparing order with a cooking item must have a live ticket.")
    }

    private static func test_noActiveTicketWhenServed() -> TestResult {
        let name = #function
        return KitchenLifecycleLogic.hasActiveKitchenTicket(
            isDeleted: false, status: "served", itemStatuses: ["served"]
        ) == false ? .success(name) : .failure(name, "served order must NOT have a live ticket.")
    }

    private static func test_noActiveTicketWhenDeleted() -> TestResult {
        let name = #function
        return KitchenLifecycleLogic.hasActiveKitchenTicket(
            isDeleted: true, status: "preparing", itemStatuses: ["cooking"]
        ) == false ? .success(name) : .failure(name, "deleted order must NOT have a live ticket.")
    }

    private static func test_readyOrderRemainsPendingDelivery() -> TestResult {
        let name = #function
        return KitchenLifecycleLogic.hasActiveKitchenTicket(
            isDeleted: false, status: "ready", itemStatuses: ["served"]
        ) ? .success(name) : .failure(name, "ready food is pending delivery even after kitchen items are done.")
    }

    // ── isOrphanedKitchenTicket ───────────────────────────────────────────

    private static func test_orphanWhenSessionNullified() -> TestResult {
        let name = #function
        // This is the exact #9619 case: live ticket, dine-in, session == nil.
        return KitchenLifecycleLogic.isOrphanedKitchenTicket(
            isDeleted: false, status: "preparing", itemStatuses: ["cooking"],
            orderType: "dine_in", sessionActive: nil, floorTableNumber: "12"
        ) ? .success(name) : .failure(name, "dine-in ticket with a nullified session must be an orphan.")
    }

    private static func test_orphanWhenSessionInactive() -> TestResult {
        let name = #function
        return KitchenLifecycleLogic.isOrphanedKitchenTicket(
            isDeleted: false, status: "preparing", itemStatuses: ["cooking"],
            orderType: "dine_in", sessionActive: false, floorTableNumber: "3"
        ) ? .success(name) : .failure(name, "dine-in ticket with an inactive session must be an orphan.")
    }

    private static func test_readyOrphanWhenSessionNullified() -> TestResult {
        let name = #function
        return KitchenLifecycleLogic.isOrphanedKitchenTicket(
            isDeleted: false, status: "ready", itemStatuses: ["served"],
            orderType: "dine_in", sessionActive: nil, floorTableNumber: "T1"
        ) ? .success(name) : .failure(name, "ready dine-in order without its table session must be reconciled.")
    }

    private static func test_notOrphanWhenSessionActive() -> TestResult {
        let name = #function
        return KitchenLifecycleLogic.isOrphanedKitchenTicket(
            isDeleted: false, status: "preparing", itemStatuses: ["cooking"],
            orderType: "dine_in", sessionActive: true, floorTableNumber: "7"
        ) == false ? .success(name) : .failure(name, "ticket on an active session must NOT be an orphan.")
    }

    private static func test_counterDineInNotOrphan() -> TestResult {
        let name = #function
        return KitchenLifecycleLogic.isOrphanedKitchenTicket(
            isDeleted: false, status: "preparing", itemStatuses: ["cooking"],
            orderType: "dine_in", sessionActive: nil, floorTableNumber: nil
        ) == false ? .success(name) : .failure(name, "counter dine-in without a table must NOT be an orphan.")
    }

    private static func test_takeoutNeverOrphan() -> TestResult {
        let name = #function
        // Take-out orders legitimately have no session.
        return KitchenLifecycleLogic.isOrphanedKitchenTicket(
            isDeleted: false, status: "preparing", itemStatuses: ["cooking"],
            orderType: "take_out", sessionActive: nil
        ) == false ? .success(name) : .failure(name, "take-out ticket must never be flagged as orphan.")
    }

    // ── KDS display guard ─────────────────────────────────────────────────

    private static func test_kdsHidesOrphan() -> TestResult {
        let name = #function
        return KitchenLifecycleLogic.shouldDisplayOnKDS(
            isDeleted: false, status: "preparing", itemStatuses: ["cooking"],
            orderType: "dine_in", sessionActive: nil, floorTableNumber: "12"
        ) == false ? .success(name) : .failure(name, "KDS must hide an orphaned (ghost) ticket.")
    }

    private static func test_kdsShowsCounterDineIn() -> TestResult {
        let name = #function
        return KitchenLifecycleLogic.shouldDisplayOnKDS(
            isDeleted: false, status: "preparing", itemStatuses: ["cooking"],
            orderType: "dine_in", sessionActive: nil, floorTableNumber: nil
        ) ? .success(name) : .failure(name, "KDS must show counter dine-in tickets.")
    }

    private static func test_kdsShowsActiveDineIn() -> TestResult {
        let name = #function
        return KitchenLifecycleLogic.shouldDisplayOnKDS(
            isDeleted: false, status: "preparing", itemStatuses: ["cooking"],
            orderType: "dine_in", sessionActive: true, floorTableNumber: "7"
        ) ? .success(name) : .failure(name, "KDS must show a live ticket on an active table.")
    }

    // ── Terminalization ───────────────────────────────────────────────────

    private static func test_markServedTerminalizes() -> TestResult {
        let name = #function
        let (s, items) = KitchenLifecycleLogic.markServed(status: "preparing", itemStatuses: ["cooking", "alert", "served"])
        return (s == "served" && items == ["served", "served", "served"])
            ? .success(name)
            : .failure(name, "markServed must set order→served and all active items→served (got \(s), \(items)).")
    }

    private static func test_markServedIdempotentOnServed() -> TestResult {
        let name = #function
        let (s, items) = KitchenLifecycleLogic.markServed(status: "served", itemStatuses: ["served"])
        return (s == "served" && items == ["served"])
            ? .success(name)
            : .failure(name, "markServed on an already-served order must be a no-op (got \(s), \(items)).")
    }

    private static func test_voidForClearCancelsEverything() -> TestResult {
        let name = #function
        let (s, items) = KitchenLifecycleLogic.voidForClear(status: "preparing", itemStatuses: ["cooking", "served"])
        // Active items cancel; already-served items are left untouched.
        return (s == "cancelled" && items == ["cancelled", "served"])
            ? .success(name)
            : .failure(name, "voidForClear must cancel the order and its active items (got \(s), \(items)).")
    }

    // ── Reconciliation stale check ────────────────────────────────────────

    private static func test_staleThreshold() -> TestResult {
        let name = #function
        // 1,622 minutes (the reported #9619 age) is far beyond the 3h threshold.
        return KitchenLifecycleLogic.isStale(ageSeconds: 1622 * 60)
            ? .success(name)
            : .failure(name, "a ticket open 1,622 minutes must be flagged stale.")
    }

    private static func test_notStaleUnderThreshold() -> TestResult {
        let name = #function
        return KitchenLifecycleLogic.isStale(ageSeconds: 30 * 60) == false
            ? .success(name)
            : .failure(name, "a 30-minute-old ticket must NOT be flagged stale.")
    }

    private static func test_reconcilesPaidStaleQuickService() -> TestResult {
        let name = #function
        return KitchenLifecycleLogic.shouldReconcileStaleQuickService(
            isQuickService: true,
            isSettled: true,
            isCompleted: false,
            hasActiveItems: true,
            ageSeconds: 4 * 60 * 60
        ) ? .success(name) : .failure(name, "A paid stale Quick Service ticket must be archived.")
    }

    private static func test_doesNotReconcileFreshQuickService() -> TestResult {
        let name = #function
        return !KitchenLifecycleLogic.shouldReconcileStaleQuickService(
            isQuickService: true,
            isSettled: true,
            isCompleted: false,
            hasActiveItems: true,
            ageSeconds: 30 * 60
        ) ? .success(name) : .failure(name, "A fresh paid order may still be cooking and must remain visible.")
    }

    private static func test_doesNotReconcileUnpaidQuickService() -> TestResult {
        let name = #function
        return !KitchenLifecycleLogic.shouldReconcileStaleQuickService(
            isQuickService: true,
            isSettled: false,
            isCompleted: false,
            hasActiveItems: true,
            ageSeconds: 24 * 60 * 60
        ) ? .success(name) : .failure(name, "Time alone must not archive an unpaid order.")
    }

    private static func test_doesNotReconcileTableService() -> TestResult {
        let name = #function
        return !KitchenLifecycleLogic.shouldReconcileStaleQuickService(
            isQuickService: false,
            isSettled: true,
            isCompleted: false,
            hasActiveItems: true,
            ageSeconds: 24 * 60 * 60
        ) ? .success(name) : .failure(name, "Table Service requires explicit delivery confirmation.")
    }

    private static func test_paidOrderLeavesLiveQueueImmediately() -> TestResult {
        let name = #function
        return !KitchenLifecycleLogic.isVisibleInLiveQueue(isSettled: true, ageSeconds: 30)
            ? .success(name)
            : .failure(name, "A fully paid order must leave the live KDS queue immediately.")
    }

    private static func test_unpaidStaleOrderLeavesLiveQueueWithoutDeletion() -> TestResult {
        let name = #function
        return !KitchenLifecycleLogic.isVisibleInLiveQueue(isSettled: false, ageSeconds: 61 * 60)
            ? .success(name)
            : .failure(name, "A stale unpaid ticket must move out of the live queue.")
    }

    private static func test_freshUnpaidOrderRemainsLive() -> TestResult {
        let name = #function
        return KitchenLifecycleLogic.isVisibleInLiveQueue(isSettled: false, ageSeconds: 20 * 60)
            ? .success(name)
            : .failure(name, "A fresh unpaid ticket must remain in the live queue.")
    }

    private static func test_deliveryAlertRequiresActiveTable() -> TestResult {
        let name = #function
        let now = Date()
        let nullSession = KitchenLifecycleLogic.shouldSendDeliveryDelayAlert(
            isDeleted: false, status: "ready", sessionActive: nil,
            tableNumber: nil, readyAt: now.addingTimeInterval(-700), now: now
        )
        let closedSession = KitchenLifecycleLogic.shouldSendDeliveryDelayAlert(
            isDeleted: false, status: "ready", sessionActive: false,
            tableNumber: "T1", readyAt: now.addingTimeInterval(-700), now: now
        )
        return !nullSession && !closedSession
            ? .success(name)
            : .failure(name, "orphaned/closed table orders must never send delivery-delay alerts.")
    }

    private static func test_deliveryAlertUsesReadyTime() -> TestResult {
        let name = #function
        let now = Date()
        let tooSoon = KitchenLifecycleLogic.shouldSendDeliveryDelayAlert(
            isDeleted: false, status: "ready", sessionActive: true,
            tableNumber: "T1", readyAt: now.addingTimeInterval(-60), now: now
        )
        let delayed = KitchenLifecycleLogic.shouldSendDeliveryDelayAlert(
            isDeleted: false, status: "ready", sessionActive: true,
            tableNumber: "T1", readyAt: now.addingTimeInterval(-601), now: now
        )
        return !tooSoon && delayed
            ? .success(name)
            : .failure(name, "delivery delay must be measured from readyAt, not order creation.")
    }

    // ── KitchenOrderDetailView ForEach bug ────────────────────────────────

    private static func test_detailRendersWhenItemsPresent() -> TestResult {
        let name = #function
        // Regression guard for the missing `} else {`: when items exist the
        // detail view MUST render them (previously it showed nothing).
        return KitchenLifecycleLogic.detailShowsItems(displayedCount: 3)
            ? .success(name)
            : .failure(name, "detail view must render the item list when items are present.")
    }

    private static func test_detailEmptyStateWhenNoItems() -> TestResult {
        let name = #function
        return KitchenLifecycleLogic.detailShowsItems(displayedCount: 0) == false
            ? .success(name)
            : .failure(name, "detail view must show the empty state when there are no items.")
    }

    // ── KDS ready vs delivered contract ───────────────────────────────────

    private static func test_markStationReadyPromotesToReady() -> TestResult {
        let name = #function
        let (s, items) = KitchenLifecycleLogic.markStationReady(
            orderStatus: "preparing",
            itemStatuses: ["cooking", "cooking"],
            stationMask: [true, true]
        )
        return (s == "ready" && items == ["served", "served"])
            ? .success(name)
            : .failure(name, "station ready must set order→ready (got \(s), \(items)).")
    }

    private static func test_markStationReadyKeepsPreparingWhenOtherStationActive() -> TestResult {
        let name = #function
        let (s, items) = KitchenLifecycleLogic.markStationReady(
            orderStatus: "preparing",
            itemStatuses: ["cooking", "cooking"],
            stationMask: [true, false] // only first item is this station
        )
        return (s == "preparing" && items == ["served", "cooking"])
            ? .success(name)
            : .failure(name, "other-station actives must keep order preparing (got \(s), \(items)).")
    }

    private static func test_quickServiceBumpCompletesInOneAction() -> TestResult {
        let name = #function
        let (status, items) = KitchenLifecycleLogic.markStationReady(
            orderStatus: "preparing",
            itemStatuses: ["cooking", "cooking"],
            stationMask: [true, true],
            isQuickService: true
        )
        return status == "served" && items == ["served", "served"]
            ? .success(name)
            : .failure(name, "Quick Service must close after the final prep bump (got \(status), \(items)).")
    }

    private static func test_quickServiceWaitsForOtherStation() -> TestResult {
        let name = #function
        let (status, items) = KitchenLifecycleLogic.markStationReady(
            orderStatus: "preparing",
            itemStatuses: ["cooking", "cooking"],
            stationMask: [true, false],
            isQuickService: true
        )
        return status == "preparing" && items == ["served", "cooking"]
            ? .success(name)
            : .failure(name, "Quick Service must remain open while another station is active.")
    }

    private static func test_tableServiceStillWaitsForDelivery() -> TestResult {
        let name = #function
        let (status, _) = KitchenLifecycleLogic.markStationReady(
            orderStatus: "preparing",
            itemStatuses: ["cooking"],
            stationMask: [true]
        )
        return status == "ready"
            ? .success(name)
            : .failure(name, "Table Service must remain ready until delivery is confirmed.")
    }

    private static func test_paidQuickServicePreservesCompletedStatus() -> TestResult {
        let name = #function
        let (status, items) = KitchenLifecycleLogic.markStationReady(
            orderStatus: "completed",
            itemStatuses: ["cooking"],
            stationMask: [true],
            isQuickService: true
        )
        return status == "completed" && items == ["served"]
            ? .success(name)
            : .failure(name, "A paid Quick Service sale must not be reopened or downgraded.")
    }

    private static func test_bumpDoesNotSkipToServed() -> TestResult {
        let name = #function
        // Regression: bump previously jumped to `served`, skipping ready alerts.
        let (s, _) = KitchenLifecycleLogic.markStationReady(
            orderStatus: "preparing",
            itemStatuses: ["cooking"],
            stationMask: [true]
        )
        return s == "ready"
            ? .success(name)
            : .failure(name, "bump/ready must land on ready, not served (got \(s)).")
    }

    private static func test_markStationDeliveredSetsServed() -> TestResult {
        let name = #function
        let (s, items) = KitchenLifecycleLogic.markStationDelivered(
            orderStatus: "ready",
            itemStatuses: ["served", "cooking"],
            stationMask: [true, true]
        )
        return (s == "served" && items == ["served", "served"])
            ? .success(name)
            : .failure(name, "clear delivered must set order→served (got \(s), \(items)).")
    }

    private static func test_autoCompleteOnlyFromReady() -> TestResult {
        let name = #function
        let fromPreparing = KitchenLifecycleLogic.markOrderDelivered(
            orderStatus: "preparing", itemStatuses: ["served"]
        )
        let fromReady = KitchenLifecycleLogic.markOrderDelivered(
            orderStatus: "ready", itemStatuses: ["served", "cancelled"]
        )
        return (fromPreparing == nil && fromReady == "served")
            ? .success(name)
            : .failure(name, "auto-complete must only fire from ready (got \(String(describing: fromPreparing)), \(String(describing: fromReady))).")
    }

    private static func test_recallItemReturnsToPreparing() -> TestResult {
        let name = #function
        let (s, items) = KitchenLifecycleLogic.recallItem(
            orderStatus: "ready",
            itemStatuses: ["served", "served"],
            index: 0
        )
        return (s == "preparing" && items == ["cooking", "served"])
            ? .success(name)
            : .failure(name, "recall must restore cooking + preparing (got \(s), \(items)).")
    }
}
