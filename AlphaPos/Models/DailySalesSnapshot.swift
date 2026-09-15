import Foundation
import SwiftData

@Model
final class DailySalesSnapshot {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var snapshotKey: String
    var branchId: UUID
    var businessDateKey: String
    var version: Int
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
    var orderCount: Int
    var paymentCount: Int
    var lateAdjustmentTotal: Double
    var calculatedThrough: Date
    var updatedAt: Date
    var isSynced: Bool

    init(
        id: UUID = UUID(), branchId: UUID, businessDateKey: String,
        version: Int = 1, grossSales: Double = 0, discounts: Double = 0,
        netSales: Double = 0, refunds: Double = 0, tax: Double = 0,
        serviceCharge: Double = 0, cashSales: Double = 0,
        cardSales: Double = 0, qrSales: Double = 0, otherSales: Double = 0,
        orderCount: Int = 0, paymentCount: Int = 0,
        lateAdjustmentTotal: Double = 0, calculatedThrough: Date = Date(),
        updatedAt: Date = Date(), isSynced: Bool = false
    ) {
        self.id = id
        self.snapshotKey = "\(branchId.uuidString.lowercased()):\(businessDateKey):v\(version)"
        self.branchId = branchId
        self.businessDateKey = businessDateKey
        self.version = version
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
        self.orderCount = orderCount
        self.paymentCount = paymentCount
        self.lateAdjustmentTotal = lateAdjustmentTotal
        self.calculatedThrough = calculatedThrough
        self.updatedAt = updatedAt
        self.isSynced = isSynced
    }
}
