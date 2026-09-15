import Foundation
import SwiftData

/// Canonical retail reporting context. Event timestamps remain immutable while
/// businessDateKey groups overnight trading and registerSessionId identifies
/// the exact till/shift responsible for a transaction.
enum BusinessDayContext {
    static let defaultCutoffHour = 4
    static let defaultTimeZoneID = "Asia/Bangkok"

    struct Assignment {
        let businessDateKey: String
        let registerSessionId: UUID?
    }

    static func key(for eventAt: Date, cutoffHour: Int = defaultCutoffHour, timeZoneID: String = defaultTimeZoneID) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneID) ?? .current
        let hour = min(max(cutoffHour, 0), 23)
        let shifted = calendar.date(byAdding: .hour, value: -hour, to: eventAt) ?? eventAt
        let components = calendar.dateComponents([.year, .month, .day], from: shifted)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    /// Determines whether a stored businessDateKey falls within the business date range [start, end).
    static func contains(
        businessDateKey: String,
        from start: Date,
        to end: Date,
        cutoffHour: Int = defaultCutoffHour,
        timeZoneID: String = defaultTimeZoneID
    ) -> Bool {
        guard !businessDateKey.isEmpty else { return false }
        let startKey = key(for: start, cutoffHour: cutoffHour, timeZoneID: timeZoneID)
        let lastMoment = end.addingTimeInterval(-0.001)
        let endKey = key(for: lastMoment >= start ? lastMoment : start, cutoffHour: cutoffHour, timeZoneID: timeZoneID)
        return businessDateKey >= startKey && businessDateKey <= endKey
    }

    static func assignment(at eventAt: Date, branch: Branch, in context: ModelContext) -> Assignment {
        let sessions = (try? context.fetch(FetchDescriptor<RegisterSession>())) ?? []
        let active = sessions
            .filter { !$0.isDeleted && $0.branch.id == branch.id && $0.openedAt <= eventAt && ($0.closedAt == nil || $0.closedAt! >= eventAt) }
            .max { $0.openedAt < $1.openedAt }
        return Assignment(
            businessDateKey: active?.businessDateKey ?? key(for: eventAt, cutoffHour: branch.businessDayCutoffHour, timeZoneID: branch.timeZoneID),
            registerSessionId: active?.id
        )
    }

    static func normalizedKey(_ stored: String, eventAt: Date, branch: Branch) -> String {
        stored.isEmpty ? key(for: eventAt, cutoffHour: branch.businessDayCutoffHour, timeZoneID: branch.timeZoneID) : stored
    }

    static func stamp(payment: Payment, order: Order, in context: ModelContext) {
        let value = assignment(at: payment.paidAt, branch: order.branch, in: context)
        payment.businessDateKey = value.businessDateKey
        payment.registerSessionId = value.registerSessionId
        // An order can have split tenders. Its accounting owner is the first
        // captured payment; later payments keep their own exact shift metadata.
        if order.businessDateKey.isEmpty { order.businessDateKey = value.businessDateKey }
        if order.registerSessionId == nil { order.registerSessionId = value.registerSessionId }
        AccountingLedgerService.recordCapturedPayment(payment, order: order, in: context)
    }

    static func stamp(inventoryTransaction transaction: InventoryTransaction, in context: ModelContext) {
        let value = assignment(at: transaction.createdAt, branch: transaction.branch, in: context)
        transaction.businessDateKey = value.businessDateKey
        transaction.registerSessionId = value.registerSessionId
    }

    static func stamp(refund: RefundTransaction, order: Order, in context: ModelContext) {
        let value = assignment(at: refund.financialEventAt, branch: order.branch, in: context)
        refund.businessDateKey = value.businessDateKey
        refund.registerSessionId = value.registerSessionId
        AccountingLedgerService.recordCompletedRefund(refund, order: order, in: context)
    }
}
