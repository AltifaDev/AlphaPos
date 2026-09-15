import Foundation

/// Selects the immutable financial events owned by a register session.
/// Rows created before session stamping are accepted only when their order is
/// from the same branch and their event time falls before the next branch shift.
struct ForceCloseSessionScope {
    let sessionId: UUID
    let branchId: UUID
    let openedAt: Date
    let legacyEndAt: Date

    init(session: RegisterSession, sessions: [RegisterSession], closingAt: Date) {
        sessionId = session.id
        branchId = session.branch.id
        openedAt = session.openedAt
        legacyEndAt = ForceCloseScopePolicy.legacyEnd(
            sessionId: session.id, branchId: session.branch.id,
            openedAt: session.openedAt, closingAt: closingAt,
            sessions: sessions.map { ($0.id, $0.branch.id, $0.openedAt, $0.isDeleted) }
        )
    }

    func contains(_ payment: Payment) -> Bool {
        ForceCloseScopePolicy.contains(
            stampedSessionId: payment.registerSessionId, eventBranchId: payment.order?.branch.id,
            eventAt: payment.paidAt, sessionId: sessionId, branchId: branchId,
            openedAt: openedAt, legacyEndAt: legacyEndAt
        )
    }

    func contains(_ refund: RefundTransaction) -> Bool {
        let eventBranchId = refund.order?.branch.id ?? refund.originalPayment?.order?.branch.id
        return ForceCloseScopePolicy.contains(
            stampedSessionId: refund.registerSessionId, eventBranchId: eventBranchId,
            eventAt: refund.financialEventAt, sessionId: sessionId, branchId: branchId,
            openedAt: openedAt, legacyEndAt: legacyEndAt
        )
    }
}
