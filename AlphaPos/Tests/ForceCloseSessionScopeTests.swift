import Foundation

enum ForceCloseSessionScopeTests {
    static func runAll() -> [TestResult] {
        [stampedRowsUseOnlyTargetShift(), legacyRowsAreLimitedByBranchAndNextShift()]
    }

    private static func stampedRowsUseOnlyTargetShift() -> TestResult {
        let name = #function
        let sessionId = UUID(), branchId = UUID()
        let openedAt = Date(timeIntervalSince1970: 1_000)
        let endAt = Date(timeIntervalSince1970: 2_000)
        let target = ForceCloseScopePolicy.contains(
            stampedSessionId: sessionId, eventBranchId: nil, eventAt: .distantPast,
            sessionId: sessionId, branchId: branchId, openedAt: openedAt, legacyEndAt: endAt)
        let other = ForceCloseScopePolicy.contains(
            stampedSessionId: UUID(), eventBranchId: branchId, eventAt: openedAt,
            sessionId: sessionId, branchId: branchId, openedAt: openedAt, legacyEndAt: endAt)
        return target && !other ? .success(name) : .failure(name, "Stamped events leaked across shifts.")
    }

    private static func legacyRowsAreLimitedByBranchAndNextShift() -> TestResult {
        let name = #function
        let sessionId = UUID(), branchId = UUID(), otherBranchId = UUID()
        let openedAt = Date(timeIntervalSince1970: 2_000)
        let nextOpenedAt = openedAt.addingTimeInterval(200)
        let endAt = ForceCloseScopePolicy.legacyEnd(
            sessionId: sessionId, branchId: branchId, openedAt: openedAt,
            closingAt: openedAt.addingTimeInterval(500), sessions: [
                (sessionId, branchId, openedAt, false),
                (UUID(), branchId, nextOpenedAt, false),
                (UUID(), otherBranchId, openedAt.addingTimeInterval(50), false)
            ])
        let target = ForceCloseScopePolicy.contains(
            stampedSessionId: nil, eventBranchId: branchId, eventAt: openedAt.addingTimeInterval(100),
            sessionId: sessionId, branchId: branchId, openedAt: openedAt, legacyEndAt: endAt)
        let nextShift = ForceCloseScopePolicy.contains(
            stampedSessionId: nil, eventBranchId: branchId, eventAt: nextOpenedAt,
            sessionId: sessionId, branchId: branchId, openedAt: openedAt, legacyEndAt: endAt)
        let otherBranch = ForceCloseScopePolicy.contains(
            stampedSessionId: nil, eventBranchId: otherBranchId, eventAt: openedAt.addingTimeInterval(100),
            sessionId: sessionId, branchId: branchId, openedAt: openedAt, legacyEndAt: endAt)
        return target && !nextShift && !otherBranch && endAt == nextOpenedAt
            ? .success(name) : .failure(name, "Legacy events crossed branch or next-shift boundaries.")
    }
}
