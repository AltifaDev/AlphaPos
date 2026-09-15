import Foundation
import SwiftData

extension Notification.Name {
    static let accountingLedgerDidChange = Notification.Name("accountingLedgerDidChange")
}

enum AccountingScope: Sendable, Equatable {
    case registerSession(UUID)
    case businessDay(String)
    case calendar(DateInterval)
}

/// Single writer and reader for financial reporting facts.
/// Source keys make retries idempotent; posted values are corrected by a new
/// reversal/adjustment event rather than mutating a historical fact.
@MainActor
enum AccountingLedgerService {
    @discardableResult
    static func recordCapturedPayment(_ payment: Payment, order: Order, in context: ModelContext, isHistoricalBackfill: Bool = false) -> Bool {
        guard payment.isCaptured, !payment.isDeleted else { return false }
        let key = "payment:\(payment.id.uuidString.lowercased()):capture"
        guard !contains(sourceEventKey: key, in: context) else { return false }
        let branch = order.branch
        let businessDate = BusinessDayContext.normalizedKey(payment.businessDateKey, eventAt: payment.paidAt, branch: branch)
        let recordedAt = Date()
        let late = !isHistoricalBackfill && isClosedSession(payment.registerSessionId, recordedAt: recordedAt, in: context)
        context.insert(FinancialEvent(
            sourceEventKey: key,
            eventType: "sale_capture",
            sourceType: "payment",
            sourceId: payment.id,
            orderId: order.id,
            branchId: branch.id,
            registerSessionId: payment.registerSessionId,
            businessDateKey: businessDate,
            occurredAt: payment.paidAt,
            recordedAt: recordedAt,
            amount: max(0, payment.amount),
            paymentMethod: payment.paymentMethod,
            sourceDeviceId: UserDefaults.standard.string(forKey: "device_id"),
            isLateAdjustment: late
        ))
        if order.usesGovernmentSupport && order.supportGovernmentAmount > 0 {
            let subsidyKey = "order:\(order.id.uuidString.lowercased()):government_subsidy"
            if !contains(sourceEventKey: subsidyKey, in: context) {
                context.insert(FinancialEvent(
                    sourceEventKey: subsidyKey,
                    eventType: "government_subsidy",
                    sourceType: "order",
                    sourceId: order.id,
                    orderId: order.id,
                    branchId: branch.id,
                    registerSessionId: payment.registerSessionId,
                    businessDateKey: businessDate,
                    occurredAt: payment.paidAt,
                    amount: order.supportGovernmentAmount,
                    paymentMethod: order.supportProgramName ?? GovernmentSupportProgram.thaiChuaThaiPlus,
                    sourceDeviceId: UserDefaults.standard.string(forKey: "device_id"),
                    isLateAdjustment: late
                ))
            }
        }
        NotificationCenter.default.post(name: .accountingLedgerDidChange, object: nil)
        rebuildDailySnapshot(branch: branch, businessDateKey: businessDate, in: context)
        return true
    }

    @discardableResult
    static func recordCompletedRefund(_ refund: RefundTransaction, order: Order, in context: ModelContext, isHistoricalBackfill: Bool = false) -> Bool {
        guard refund.status == "completed", !refund.isDeleted else { return false }
        let key = "refund:\(refund.id.uuidString.lowercased()):completed"
        guard !contains(sourceEventKey: key, in: context) else { return false }
        let branch = order.branch
        let occurredAt = refund.financialEventAt
        let businessDate = BusinessDayContext.normalizedKey(refund.businessDateKey, eventAt: occurredAt, branch: branch)
        let recordedAt = Date()
        let late = !isHistoricalBackfill && isClosedSession(refund.registerSessionId, recordedAt: recordedAt, in: context)
        context.insert(FinancialEvent(
            sourceEventKey: key,
            eventType: "refund",
            sourceType: "refund",
            sourceId: refund.id,
            orderId: order.id,
            branchId: branch.id,
            registerSessionId: refund.registerSessionId,
            businessDateKey: businessDate,
            occurredAt: occurredAt,
            recordedAt: recordedAt,
            amount: -max(0, refund.refundAmount),
            paymentMethod: refund.refundMethod,
            sourceDeviceId: UserDefaults.standard.string(forKey: "device_id"),
            isLateAdjustment: late
        ))
        NotificationCenter.default.post(name: .accountingLedgerDidChange, object: nil)
        rebuildDailySnapshot(branch: branch, businessDateKey: businessDate, in: context)
        return true
    }

    /// Correcting a captured tender never edits its posted accounting fact.
    /// The original capture is reversed and the replacement payment posts a
    /// new capture under the same business date and register session.
    @discardableResult
    static func recordVoidedPayment(_ payment: Payment, order: Order, in context: ModelContext) -> Bool {
        let key = "payment:\(payment.id.uuidString.lowercased()):void"
        guard !contains(sourceEventKey: key, in: context) else { return false }
        let branch = order.branch
        let businessDate = BusinessDayContext.normalizedKey(
            payment.businessDateKey, eventAt: payment.paidAt, branch: branch
        )
        context.insert(FinancialEvent(
            sourceEventKey: key,
            eventType: "payment_void",
            sourceType: "payment",
            sourceId: payment.id,
            orderId: order.id,
            branchId: branch.id,
            registerSessionId: payment.registerSessionId,
            businessDateKey: businessDate,
            occurredAt: payment.paidAt,
            amount: -max(0, payment.amount),
            paymentMethod: payment.paymentMethod,
            sourceDeviceId: UserDefaults.standard.string(forKey: "device_id")
        ))
        rebuildDailySnapshot(branch: branch, businessDateKey: businessDate, in: context)
        NotificationCenter.default.post(name: .accountingLedgerDidChange, object: nil)
        return true
    }

    @discardableResult
    static func recordCashMovement(_ movement: CashMovement, in context: ModelContext) -> Bool {
        guard !movement.isDeleted, movement.amount > 0, let session = movement.registerSession else { return false }
        let outbound = movement.movementType == "cash_out" || movement.movementType == "paid_out"
        let inbound = movement.movementType == "cash_in" || movement.movementType == "paid_in"
        guard inbound || outbound else { return false }
        let key = "cash_movement:\(movement.id.uuidString.lowercased())"
        guard !contains(sourceEventKey: key, in: context) else { return false }
        context.insert(FinancialEvent(
            sourceEventKey: key,
            eventType: outbound ? "cash_out" : "cash_in",
            sourceType: "cash_movement",
            sourceId: movement.id,
            branchId: session.branch.id,
            registerSessionId: session.id,
            businessDateKey: session.businessDateKey,
            occurredAt: movement.updatedAt,
            amount: outbound ? -movement.amount : movement.amount,
            paymentMethod: "cash",
            sourceDeviceId: UserDefaults.standard.string(forKey: "device_id"),
            isLateAdjustment: session.closedAt.map { movement.updatedAt > $0 } ?? false
        ))
        NotificationCenter.default.post(name: .accountingLedgerDidChange, object: nil)
        return true
    }

    static func summary(branchId: UUID, scope: AccountingScope, in context: ModelContext) -> AccountingSummary {
        let targetBranch = branchId
        let events: [FinancialEvent]
        switch scope {
        case .registerSession(let id):
            let sessionId: UUID? = id
            events = (try? context.fetch(FetchDescriptor<FinancialEvent>(predicate: #Predicate {
                !$0.isDeleted && $0.status == "posted" && $0.branchId == targetBranch && $0.registerSessionId == sessionId
            }))) ?? []
        case .businessDay(let key):
            let businessKey = key
            events = (try? context.fetch(FetchDescriptor<FinancialEvent>(predicate: #Predicate {
                !$0.isDeleted && $0.status == "posted" && $0.branchId == targetBranch && $0.businessDateKey == businessKey
            }))) ?? []
        case .calendar(let interval):
            let start = interval.start
            let end = interval.end
            events = (try? context.fetch(FetchDescriptor<FinancialEvent>(predicate: #Predicate {
                !$0.isDeleted && $0.status == "posted" && $0.branchId == targetBranch && $0.occurredAt >= start && $0.occurredAt < end
            }))) ?? []
        }
        return summarize(events)
    }

    static func backfill(in context: ModelContext) -> (payments: Int, refunds: Int, closureSnapshots: Int) {
        var paymentCount = 0
        var refundCount = 0
        // Read existing keys once. Calling `contains` for every historical
        // payment/refund turns this repair into an N+1 query and can block the
        // main ModelContext for seconds on mature stores.
        let existingKeys = Set(
            ((try? context.fetch(FetchDescriptor<FinancialEvent>())) ?? [])
                .map(\.sourceEventKey)
        )
        for payment in (try? context.fetch(FetchDescriptor<Payment>())) ?? [] {
            guard let order = payment.order else { continue }
            let key = "payment:\(payment.id.uuidString.lowercased()):capture"
            guard !existingKeys.contains(key) else { continue }
            if recordCapturedPayment(payment, order: order, in: context, isHistoricalBackfill: true) { paymentCount += 1 }
        }
        for refund in (try? context.fetch(FetchDescriptor<RefundTransaction>())) ?? [] {
            guard let order = refund.order else { continue }
            let key = "refund:\(refund.id.uuidString.lowercased()):completed"
            guard !existingKeys.contains(key) else { continue }
            if recordCompletedRefund(refund, order: order, in: context, isHistoricalBackfill: true) { refundCount += 1 }
        }
        // Save ledger facts independently. Do not traverse legacy
        // ShiftReport -> RegisterSession relationships during bootstrap: old
        // stores can contain a dangling Core Data relationship after a shift
        // was deleted, and merely reading RegisterSession.id is an
        // unrecoverable SwiftData fatalError (not a throwable fetch failure).
        // New shifts create their immutable snapshot in the close-shift
        // transaction; legacy snapshots must be repaired by scalar migration.
        try? context.save()
        let snapshotCount = 0
        if paymentCount > 0 || refundCount > 0 || snapshotCount > 0 {
            NotificationCenter.default.post(name: .accountingLedgerDidChange, object: nil)
        }
        return (paymentCount, refundCount, snapshotCount)
    }

    static func createClosureSnapshot(
        session: RegisterSession, report: ShiftReport,
        serviceCharge: Double = 0, cashIn: Double = 0, cashOut: Double = 0,
        transactionCount: Int, generatedByUserId: UUID?, in context: ModelContext
    ) {
        guard let closedAt = session.closedAt else { return }
        let sessionId = session.id
        let existing = (try? context.fetch(FetchDescriptor<ShiftClosureSnapshot>())) ?? []
        guard !existing.contains(where: { $0.registerSessionId == sessionId }) else { return }
        let summary = summary(branchId: session.branch.id, scope: .registerSession(session.id), in: context)
        context.insert(ShiftClosureSnapshot(
            registerSessionId: session.id,
            branchId: session.branch.id,
            businessDateKey: session.businessDateKey,
            openedAt: session.openedAt,
            closedAt: closedAt,
            openingCash: session.openingCash,
            grossSales: report.grossSales,
            discounts: report.totalDiscounts,
            netSales: report.netSales,
            refunds: report.totalRefunds,
            tax: report.totalTax,
            serviceCharge: serviceCharge,
            cashSales: summary.cash,
            cardSales: summary.card,
            qrSales: summary.qr,
            otherSales: summary.other,
            cashIn: cashIn,
            cashOut: cashOut,
            expectedCash: report.cashExpected,
            actualCash: report.cashActual,
            discrepancy: report.overShort,
            transactionCount: transactionCount,
            lateAdjustmentTotal: summary.lateAdjustmentTotal,
            generatedByUserId: generatedByUserId
        ))
        rebuildDailySnapshot(branch: session.branch, businessDateKey: session.businessDateKey, in: context)
    }

    static func rebuildDailySnapshot(branch: Branch, businessDateKey: String, in context: ModelContext) {
        let branchId = branch.id
        let key = businessDateKey
        let financial = summary(branchId: branchId, scope: .businessDay(key), in: context)
        let orders = ((try? context.fetch(FetchDescriptor<Order>(predicate: #Predicate {
            !$0.isDeleted && $0.businessDateKey == key
        }))) ?? []).filter { $0.branch.id == branchId && financial.orderIds.contains($0.id) }
        let gross = orders.reduce(0) { $0 + $1.total + $1.discount }
        let discounts = orders.reduce(0) { $0 + $1.discount }
        let tax = orders.reduce(0) { $0 + $1.tax }
        let service = orders.reduce(0) { $0 + $1.serviceCharge }
        let snapshotKey = "\(branchId.uuidString.lowercased()):\(key):v1"
        var descriptor = FetchDescriptor<DailySalesSnapshot>(predicate: #Predicate { $0.snapshotKey == snapshotKey })
        descriptor.fetchLimit = 1
        let snapshot = (try? context.fetch(descriptor))?.first
        if let snapshot {
            snapshot.grossSales = gross
            snapshot.discounts = discounts
            snapshot.netSales = financial.netSales
            snapshot.refunds = financial.refunds
            snapshot.tax = tax
            snapshot.serviceCharge = service
            snapshot.cashSales = financial.cash
            snapshot.cardSales = financial.card
            snapshot.qrSales = financial.qr
            snapshot.otherSales = financial.other
            snapshot.orderCount = financial.orderIds.count
            snapshot.paymentCount = financial.paymentCount
            snapshot.lateAdjustmentTotal = financial.lateAdjustmentTotal
            snapshot.calculatedThrough = Date()
            snapshot.updatedAt = Date()
            snapshot.isSynced = false
        } else {
            context.insert(DailySalesSnapshot(
                branchId: branchId, businessDateKey: key,
                grossSales: gross, discounts: discounts,
                netSales: financial.netSales, refunds: financial.refunds,
                tax: tax, serviceCharge: service,
                cashSales: financial.cash, cardSales: financial.card,
                qrSales: financial.qr, otherSales: financial.other,
                orderCount: financial.orderIds.count,
                paymentCount: financial.paymentCount,
                lateAdjustmentTotal: financial.lateAdjustmentTotal
            ))
        }
    }

    private static func summarize(_ events: [FinancialEvent]) -> AccountingSummary {
        AccountingMath.summarize(events.map {
            AccountingFact(eventType: $0.eventType, amount: $0.amount,
                           paymentMethod: $0.paymentMethod, orderId: $0.orderId,
                           isLateAdjustment: $0.isLateAdjustment)
        })
    }

    private static func contains(sourceEventKey: String, in context: ModelContext) -> Bool {
        let key = sourceEventKey
        var descriptor = FetchDescriptor<FinancialEvent>(predicate: #Predicate { $0.sourceEventKey == key })
        descriptor.fetchLimit = 1
        return ((try? context.fetch(descriptor))?.isEmpty == false)
    }

    private static func isClosedSession(_ id: UUID?, recordedAt: Date, in context: ModelContext) -> Bool {
        guard let id else { return false }
        let sessions = (try? context.fetch(FetchDescriptor<RegisterSession>())) ?? []
        guard let closedAt = sessions.first(where: { $0.id == id })?.closedAt else { return false }
        return recordedAt > closedAt
    }

}
