import Foundation
import SwiftData

/// Immutable versioned facts captured when a till shift is closed.
@Model
final class ShiftClosureSnapshot {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var snapshotKey: String
    var registerSessionId: UUID
    var branchId: UUID
    var businessDateKey: String
    var version: Int
    var openedAt: Date
    var closedAt: Date
    var openingCash: Double
    var grossSales: Double
    var discounts: Double
    var netSales: Double
    var refunds: Double
    var tax: Double
    var serviceCharge: Double
    var cashSales: Double
    var cardSales: Double
    var qrSales: Double
    var otherSales: Double
    var cashIn: Double
    var cashOut: Double
    var expectedCash: Double
    var actualCash: Double
    var discrepancy: Double
    var transactionCount: Int
    var lateAdjustmentTotal: Double
    var generatedAt: Date
    var generatedByUserId: UUID?
    var isSynced: Bool

    init(
        id: UUID = UUID(), registerSessionId: UUID, branchId: UUID,
        businessDateKey: String, version: Int = 1, openedAt: Date,
        closedAt: Date, openingCash: Double, grossSales: Double,
        discounts: Double, netSales: Double, refunds: Double, tax: Double,
        serviceCharge: Double, cashSales: Double, cardSales: Double,
        qrSales: Double, otherSales: Double, cashIn: Double = 0,
        cashOut: Double = 0, expectedCash: Double, actualCash: Double,
        discrepancy: Double, transactionCount: Int,
        lateAdjustmentTotal: Double = 0, generatedAt: Date = Date(),
        generatedByUserId: UUID? = nil, isSynced: Bool = false
    ) {
        self.id = id
        self.snapshotKey = "\(registerSessionId.uuidString.lowercased()):v\(version)"
        self.registerSessionId = registerSessionId
        self.branchId = branchId
        self.businessDateKey = businessDateKey
        self.version = version
        self.openedAt = openedAt
        self.closedAt = closedAt
        self.openingCash = openingCash
        self.grossSales = grossSales
        self.discounts = discounts
        self.netSales = netSales
        self.refunds = refunds
        self.tax = tax
        self.serviceCharge = serviceCharge
        self.cashSales = cashSales
        self.cardSales = cardSales
        self.qrSales = qrSales
        self.otherSales = otherSales
        self.cashIn = cashIn
        self.cashOut = cashOut
        self.expectedCash = expectedCash
        self.actualCash = actualCash
        self.discrepancy = discrepancy
        self.transactionCount = transactionCount
        self.lateAdjustmentTotal = lateAdjustmentTotal
        self.generatedAt = generatedAt
        self.generatedByUserId = generatedByUserId
        self.isSynced = isSynced
    }
}

