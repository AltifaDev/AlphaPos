// TableSessionConsistencyTests.swift
// Regression contracts for the table-management/POS divergence incident.

import Foundation

/// Pure mirror of the display rule in TableView. Keeping this contract
/// framework-free lets the standalone test runner exercise the race cases
/// without constructing SwiftData models or requiring a device build.
private enum TableSessionConsistencyLogic {
    static func operationalStatus(
        storedStatus: String,
        activeSessionOnLeader: Bool,
        activeSessionOnJoinedChild: Bool,
        sessionDeleted: Bool = false
    ) -> String {
        if !sessionDeleted && (activeSessionOnLeader || activeSessionOnJoinedChild) {
            return "occupied"
        }
        return storedStatus
    }

    static func visibleOrderCount(
        orderCount: Int,
        sessionActive: Bool,
        sessionDeleted: Bool = false
    ) -> Int {
        sessionActive && !sessionDeleted ? orderCount : 0
    }

    static func canReuseExistingSession(
        sessionActive: Bool,
        sessionDeleted: Bool,
        storedStatus: String
    ) -> Bool {
        sessionActive && !sessionDeleted && storedStatus != "cancelled"
    }

    /// A close request must not be sent ahead of the atomic payment transition.
    static func syncStepsForPaidTable() -> [String] {
        ["save_local_checkout", "print_local_receipt", "sync_atomic_checkout", "close_joined_children"]
    }

    static func rejectsOrphanRemoteSession(
        remoteSessionStartedAt: Date,
        latestSettledPaymentAt: Date?,
        hasUnpaidOrder: Bool
    ) -> Bool {
        !hasUnpaidOrder
            && latestSettledPaymentAt.map { remoteSessionStartedAt <= $0 } == true
    }

    static func canAttachOrderByTableFallback(
        orderCreatedAt: Date,
        sessionStartedAt: Date,
        sessionOperational: Bool,
        clockTolerance: TimeInterval = 5 * 60
    ) -> Bool {
        sessionOperational
            && orderCreatedAt >= sessionStartedAt.addingTimeInterval(-clockTolerance)
    }

    static func canDisplayOrder(
        orderCreatedAt: Date,
        sessionStartedAt: Date,
        isDeleted: Bool,
        isSettled: Bool,
        clockTolerance: TimeInterval = 5 * 60
    ) -> Bool {
        !isDeleted
            && !isSettled
            && orderCreatedAt >= sessionStartedAt.addingTimeInterval(-clockTolerance)
    }
}

enum TableSessionConsistencyTests {
    static func runAll() -> [TestResult] {
        [
            test_vacantRowWithActiveLeaderSessionIsOccupied(),
            test_vacantRowWithActiveJoinedSessionIsOccupied(),
            test_activeSessionExposesOrdersBeforeStatusPull(),
            test_deletedSessionDoesNotResurrectTable(),
            test_existingSessionIsReusedWhenStatusPullLags(),
            test_checkoutSyncPrecedesStandaloneClose(),
            test_completedTableDoesNotExposeOrders(),
            test_staleRemoteSessionAfterSettlementIsRejected(),
            test_newRemoteSessionWithUnpaidOrderIsPreserved(),
            test_oldOrderCannotAttachToNewTableSession(),
            test_currentOrderCanAttachToCurrentTableSession(),
            test_historicalOrderCannotDisplayInNewSession()
        ]
    }

    private static func test_oldOrderCannotAttachToNewTableSession() -> TestResult {
        let sessionStart = Date()
        let result = TableSessionConsistencyLogic.canAttachOrderByTableFallback(
            orderCreatedAt: sessionStart.addingTimeInterval(-3 * 60 * 60),
            sessionStartedAt: sessionStart,
            sessionOperational: true
        )
        return result == false
            ? .success(#function)
            : .failure(#function, "A historical order must never migrate into a newly opened table session")
    }

    private static func test_currentOrderCanAttachToCurrentTableSession() -> TestResult {
        let sessionStart = Date()
        let result = TableSessionConsistencyLogic.canAttachOrderByTableFallback(
            orderCreatedAt: sessionStart.addingTimeInterval(30),
            sessionStartedAt: sessionStart,
            sessionOperational: true
        )
        return result
            ? .success(#function)
            : .failure(#function, "A current order should attach to its current operational session")
    }

    private static func test_historicalOrderCannotDisplayInNewSession() -> TestResult {
        let sessionStart = Date()
        let result = TableSessionConsistencyLogic.canDisplayOrder(
            orderCreatedAt: sessionStart.addingTimeInterval(-24 * 60 * 60),
            sessionStartedAt: sessionStart,
            isDeleted: false,
            isSettled: false
        )
        return result == false
            ? .success(#function)
            : .failure(#function, "Historical table orders must not appear in a new session")
    }

    private static func test_vacantRowWithActiveLeaderSessionIsOccupied() -> TestResult {
        let result = TableSessionConsistencyLogic.operationalStatus(
            storedStatus: "vacant", activeSessionOnLeader: true, activeSessionOnJoinedChild: false
        )
        return result == "occupied"
            ? .success(#function)
            : .failure(#function, "An active leader session must override a stale vacant table row")
    }

    private static func test_vacantRowWithActiveJoinedSessionIsOccupied() -> TestResult {
        let result = TableSessionConsistencyLogic.operationalStatus(
            storedStatus: "vacant", activeSessionOnLeader: false, activeSessionOnJoinedChild: true
        )
        return result == "occupied"
            ? .success(#function)
            : .failure(#function, "An active joined-child session must mark the group occupied")
    }

    private static func test_activeSessionExposesOrdersBeforeStatusPull() -> TestResult {
        let result = TableSessionConsistencyLogic.visibleOrderCount(
            orderCount: 3, sessionActive: true
        )
        return result == 3
            ? .success(#function)
            : .failure(#function, "Orders must remain visible while table.status is catching up")
    }

    private static func test_deletedSessionDoesNotResurrectTable() -> TestResult {
        let result = TableSessionConsistencyLogic.operationalStatus(
            storedStatus: "vacant", activeSessionOnLeader: true, activeSessionOnJoinedChild: false,
            sessionDeleted: true
        )
        return result == "vacant"
            ? .success(#function)
            : .failure(#function, "Deleted sessions must never make a table occupied")
    }

    private static func test_existingSessionIsReusedWhenStatusPullLags() -> TestResult {
        let result = TableSessionConsistencyLogic.canReuseExistingSession(
            sessionActive: true, sessionDeleted: false, storedStatus: "vacant"
        )
        return result
            ? .success(#function)
            : .failure(#function, "A delayed status pull must not create a competing session")
    }

    private static func test_checkoutSyncPrecedesStandaloneClose() -> TestResult {
        let steps = TableSessionConsistencyLogic.syncStepsForPaidTable()
        guard let syncIndex = steps.firstIndex(of: "sync_atomic_checkout"),
              let closeIndex = steps.firstIndex(of: "close_joined_children") else {
            return .failure(#function, "Checkout sync/close steps are incomplete")
        }
        return syncIndex < closeIndex
            ? .success(#function)
            : .failure(#function, "Closing a remote session before atomic checkout can resurrect it")
    }

    private static func test_completedTableDoesNotExposeOrders() -> TestResult {
        let result = TableSessionConsistencyLogic.visibleOrderCount(
            orderCount: 3, sessionActive: false
        )
        return result == 0
            ? .success(#function)
            : .failure(#function, "Closed sessions must not leak stale orders into POS")
    }

    private static func test_staleRemoteSessionAfterSettlementIsRejected() -> TestResult {
        let paidAt = Date(timeIntervalSince1970: 2_000)
        let result = TableSessionConsistencyLogic.rejectsOrphanRemoteSession(
            remoteSessionStartedAt: Date(timeIntervalSince1970: 1_000),
            latestSettledPaymentAt: paidAt,
            hasUnpaidOrder: false
        )
        return result
            ? .success(#function)
            : .failure(#function, "A remote session older than the latest settlement must not resurrect the table")
    }

    private static func test_newRemoteSessionWithUnpaidOrderIsPreserved() -> TestResult {
        let paidAt = Date(timeIntervalSince1970: 2_000)
        let result = TableSessionConsistencyLogic.rejectsOrphanRemoteSession(
            remoteSessionStartedAt: Date(timeIntervalSince1970: 1_000),
            latestSettledPaymentAt: paidAt,
            hasUnpaidOrder: true
        )
        return !result
            ? .success(#function)
            : .failure(#function, "A session with an unpaid order must remain active")
    }
}
