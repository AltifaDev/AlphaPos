// DailySalesReportTests.swift
// AlphaPos — Daily Sales international bridge math (pure, no SwiftData)

import Foundation

/// Mirrors the tax-inclusive Daily Sales bridge used by ReportsViewModel.computeDailySales.
enum DailySalesBridgeLogic {
    struct OrderInput {
        let subtotal: Double
        let tax: Double
        let serviceCharge: Double
        let discount: Double
        let total: Double
        let refunds: Double
        let isCancelled: Bool
        let isRecognizedSale: Bool
    }

    struct PaymentInput {
        let amount: Double
        let tipAmount: Double
        let isCompleted: Bool
    }

    struct Result {
        let grossSales: Double
        let discounts: Double
        let netSalesIncVAT: Double
        let vatCollected: Double
        let serviceCharge: Double
        let netSalesExVAT: Double
        let refunds: Double
        let netRevenueAfterRefunds: Double
        let tips: Double
        let paymentsCollected: Double
        let tenderVariance: Double
        let voidCount: Int
        let voidAmount: Double
        let orderCount: Int
        let averageTicket: Double
    }

    static func compute(orders: [OrderInput], payments: [PaymentInput]) -> Result {
        let sales = orders.filter { $0.isRecognizedSale && !$0.isCancelled }
        var gross = 0.0
        var discounts = 0.0
        var ticketTotal = 0.0
        var vat = 0.0
        var sc = 0.0
        var refunds = 0.0

        for order in sales {
            let componentGross = order.subtotal + order.serviceCharge + order.tax
            let ticketGross = order.total + order.discount
            let orderGross = abs(componentGross - ticketGross) <= 0.05 ? componentGross : ticketGross
            gross += orderGross
            discounts += order.discount
            ticketTotal += order.total
            vat += order.tax
            sc += order.serviceCharge
            refunds += order.refunds
        }

        let voids = orders.filter { $0.isCancelled }
        let completedPayments = payments.filter(\.isCompleted)
        let paymentsCollected = completedPayments.reduce(0.0) { $0 + $1.amount }
        let tips = completedPayments.reduce(0.0) { $0 + $1.tipAmount }
        let orderCount = sales.count

        return Result(
            grossSales: gross,
            discounts: discounts,
            netSalesIncVAT: ticketTotal,
            vatCollected: vat,
            serviceCharge: sc,
            netSalesExVAT: max(0, ticketTotal - vat),
            refunds: refunds,
            netRevenueAfterRefunds: ticketTotal - refunds,
            tips: tips,
            paymentsCollected: paymentsCollected,
            tenderVariance: (paymentsCollected - refunds) - (ticketTotal - refunds),
            voidCount: voids.count,
            voidAmount: voids.reduce(0.0) { $0 + $1.total },
            orderCount: orderCount,
            averageTicket: orderCount > 0 ? ticketTotal / Double(orderCount) : 0
        )
    }
}

enum DailySalesReportTests {
    static func runAll() -> [TestResult] {
        [
            test_bridgeIdentityGrossMinusDiscountEqualsNet(),
            test_refundsReduceNetRevenue(),
            test_tipsExcludedFromSalesVariance(),
            test_voidsExcludedFromSales(),
            test_averageTicketUsesNetSales()
        ]
    }

    private static func test_bridgeIdentityGrossMinusDiscountEqualsNet() -> TestResult {
        let name = #function
        let result = DailySalesBridgeLogic.compute(
            orders: [
                .init(subtotal: 100, tax: 7, serviceCharge: 10, discount: 17, total: 100, refunds: 0, isCancelled: false, isRecognizedSale: true)
            ],
            payments: [.init(amount: 100, tipAmount: 0, isCompleted: true)]
        )
        // components 117 vs ticket+discount 117 → prefer components as gross
        guard abs(result.grossSales - 117) < 0.01 else {
            return .failure(name, "gross expected 117 got \(result.grossSales)")
        }
        guard abs(result.netSalesIncVAT - 100) < 0.01 else {
            return .failure(name, "net sales expected 100 got \(result.netSalesIncVAT)")
        }
        guard abs(result.grossSales - result.discounts - result.netSalesIncVAT) < 0.01 else {
            return .failure(name, "identity Gross − Discount = Net Sales failed")
        }
        return .success(name)
    }

    private static func test_refundsReduceNetRevenue() -> TestResult {
        let name = #function
        let result = DailySalesBridgeLogic.compute(
            orders: [
                .init(subtotal: 200, tax: 14, serviceCharge: 0, discount: 0, total: 214, refunds: 50, isCancelled: false, isRecognizedSale: true)
            ],
            payments: [.init(amount: 214, tipAmount: 0, isCompleted: true)]
        )
        guard abs(result.netRevenueAfterRefunds - 164) < 0.01 else {
            return .failure(name, "net revenue expected 164 got \(result.netRevenueAfterRefunds)")
        }
        return .success(name)
    }

    private static func test_tipsExcludedFromSalesVariance() -> TestResult {
        let name = #function
        let result = DailySalesBridgeLogic.compute(
            orders: [
                .init(subtotal: 100, tax: 0, serviceCharge: 0, discount: 0, total: 100, refunds: 0, isCancelled: false, isRecognizedSale: true)
            ],
            payments: [.init(amount: 100, tipAmount: 20, isCompleted: true)]
        )
        guard abs(result.tips - 20) < 0.01 else {
            return .failure(name, "tips expected 20 got \(result.tips)")
        }
        guard abs(result.tenderVariance) < 0.01 else {
            return .failure(name, "variance should ignore tips; got \(result.tenderVariance)")
        }
        return .success(name)
    }

    private static func test_voidsExcludedFromSales() -> TestResult {
        let name = #function
        let result = DailySalesBridgeLogic.compute(
            orders: [
                .init(subtotal: 50, tax: 0, serviceCharge: 0, discount: 0, total: 50, refunds: 0, isCancelled: false, isRecognizedSale: true),
                .init(subtotal: 80, tax: 0, serviceCharge: 0, discount: 0, total: 80, refunds: 0, isCancelled: true, isRecognizedSale: false)
            ],
            payments: [.init(amount: 50, tipAmount: 0, isCompleted: true)]
        )
        guard result.orderCount == 1, abs(result.netSalesIncVAT - 50) < 0.01 else {
            return .failure(name, "void should not count in sales")
        }
        guard result.voidCount == 1, abs(result.voidAmount - 80) < 0.01 else {
            return .failure(name, "void amount expected 80")
        }
        return .success(name)
    }

    private static func test_averageTicketUsesNetSales() -> TestResult {
        let name = #function
        let result = DailySalesBridgeLogic.compute(
            orders: [
                .init(subtotal: 100, tax: 0, serviceCharge: 0, discount: 20, total: 80, refunds: 0, isCancelled: false, isRecognizedSale: true),
                .init(subtotal: 100, tax: 0, serviceCharge: 0, discount: 0, total: 100, refunds: 0, isCancelled: false, isRecognizedSale: true)
            ],
            payments: []
        )
        guard abs(result.averageTicket - 90) < 0.01 else {
            return .failure(name, "avg ticket expected 90 got \(result.averageTicket)")
        }
        return .success(name)
    }
}
