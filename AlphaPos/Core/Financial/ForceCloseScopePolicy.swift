import Foundation

enum ForceCloseScopePolicy {
    static func legacyEnd(sessionId: UUID, branchId: UUID, openedAt: Date, closingAt: Date,
                          sessions: [(id: UUID, branchId: UUID, openedAt: Date, isDeleted: Bool)]) -> Date {
        sessions.filter {
            !$0.isDeleted && $0.id != sessionId && $0.branchId == branchId &&
            $0.openedAt > openedAt && $0.openedAt < closingAt
        }.map(\.openedAt).min() ?? closingAt
    }

    static func contains(stampedSessionId: UUID?, eventBranchId: UUID?, eventAt: Date,
                         sessionId: UUID, branchId: UUID, openedAt: Date, legacyEndAt: Date) -> Bool {
        if let stampedSessionId { return stampedSessionId == sessionId }
        guard eventBranchId == branchId else { return false }
        return eventAt >= openedAt && eventAt < legacyEndAt
    }
}
