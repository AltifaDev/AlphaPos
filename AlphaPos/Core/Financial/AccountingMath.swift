import Foundation

enum RegisterShiftScope {
    /// Session identity is authoritative. Event time is only a compatibility
    /// fallback for legacy rows created before registerSessionId existed.
    static func contains(
        eventSessionId: UUID?, eventAt: Date,
        sessionId: UUID, openedAt: Date, closedAt: Date
    ) -> Bool {
        if let eventSessionId { return eventSessionId == sessionId }
        return eventAt >= openedAt && eventAt <= closedAt
    }
}

struct AccountingSummary: Sendable, Equatable {
    var capturedSales = 0.0
    var refunds = 0.0
    var cash = 0.0
    var card = 0.0
    var qr = 0.0
    var other = 0.0
    var paymentCount = 0
    var refundCount = 0
    var lateAdjustmentTotal = 0.0
    var orderIds = Set<UUID>()

    var netSales: Double { capturedSales - refunds }
}

struct AccountingFact: Sendable {
    let eventType: String
    let amount: Double
    let paymentMethod: String?
    let orderId: UUID?
    let isLateAdjustment: Bool
}

enum AccountingMath {
    /// Applies a fixed discount to every sellable unit while preventing any
    /// cart line from becoming negative.
    static func fixedPerItemDiscount(
        value: Double,
        minimumUnitPrice: Double = 0,
        lines: [(quantity: Int, total: Double)]
    ) -> Double {
        guard value > 0 else { return 0 }
        return lines.reduce(0) { result, line in
            let quantity = max(0, line.quantity)
            guard quantity > 0 else { return result }
            let unitPrice = max(0, line.total) / Double(quantity)
            // The configured threshold is exclusive: a threshold of ฿50 means
            // only units priced above ฿50 qualify.
            guard unitPrice > minimumUnitPrice else { return result }
            return result + min(max(0, line.total), value * Double(quantity))
        }
    }

    static func normalizedExpenseRecognition(_ raw: String, legacyIsCapEx: Bool) -> String {
        let supported = ["operating_expense", "fixed_asset", "prepaid_expense", "refundable_deposit"]
        return supported.contains(raw) ? raw : (legacyIsCapEx ? "fixed_asset" : "operating_expense")
    }

    static func monthlyStraightLineDepreciation(cost: Double, residualValue: Double, usefulLifeMonths: Int) -> Double {
        guard cost > 0, usefulLifeMonths > 0 else { return 0 }
        return max(0, cost - max(0, residualValue)) / Double(usefulLifeMonths)
    }

    static func accumulatedDepreciation(
        cost: Double, residualValue: Double, usefulLifeMonths: Int,
        availableForUse: Date, asOf: Date, calendar: Calendar = .current
    ) -> Double {
        guard asOf >= availableForUse else { return 0 }
        let elapsed = (calendar.dateComponents([.month], from: calendar.startOfDay(for: availableForUse), to: calendar.startOfDay(for: asOf)).month ?? 0) + 1
        let months = min(max(elapsed, 0), max(usefulLifeMonths, 0))
        return monthlyStraightLineDepreciation(cost: cost, residualValue: residualValue, usefulLifeMonths: usefulLifeMonths) * Double(months)
    }

    static func simplePaybackMonths(investment: Double, monthlyCashBenefit: Double, monthlyIncrementalCost: Double) -> Double? {
        let netBenefit = monthlyCashBenefit - monthlyIncrementalCost
        guard investment > 0, netBenefit > 0 else { return nil }
        return investment / netBenefit
    }

    static func recognizedAmount(eventType: String, amount: Double) -> Double? {
        switch eventType {
        case "sale_capture", "government_subsidy": return max(0, amount)
        case "refund", "payment_void", "reversal": return -abs(amount)
        default: return nil
        }
    }

    static func capturedFraction(ticketTotal: Double, recognizedBeforeRefunds: Double) -> Double {
        guard ticketTotal > 0.005 else { return recognizedBeforeRefunds > 0 ? 1 : 0 }
        return min(max(recognizedBeforeRefunds / ticketTotal, 0), 1)
    }

    /// Allocates document output VAT to a captured/refunded amount. This keeps
    /// Dashboard reconciliation, sales reports and P&L on the same tax basis.
    static func allocatedOutputVAT(ticketTotal: Double, documentVAT: Double, recognizedAmount: Double) -> Double {
        guard ticketTotal > 0.005, documentVAT > 0, recognizedAmount > 0 else { return 0 }
        return min(documentVAT, recognizedAmount * documentVAT / ticketTotal)
    }

    static func allocate(_ amount: Double, weights: [Double]) -> [Double] {
        let positive = weights.map { max(0, $0) }
        let total = positive.reduce(0, +)
        guard total > 0 else { return Array(repeating: 0, count: weights.count) }
        return positive.map { amount * $0 / total }
    }

    static func summarize(_ facts: [AccountingFact]) -> AccountingSummary {
        var result = AccountingSummary()
        for fact in facts {
            if fact.eventType == "sale_capture" || fact.eventType == "government_subsidy" {
                let amount = max(0, fact.amount)
                result.capturedSales += amount
                if fact.eventType == "sale_capture" { result.paymentCount += 1 }
                if let orderId = fact.orderId { result.orderIds.insert(orderId) }
                let method = (fact.paymentMethod ?? "").lowercased()
                if method == "cash" { result.cash += amount }
                else if method.contains("card") || method.contains("credit") { result.card += amount }
                else if method.contains("qr") || method.contains("promptpay") { result.qr += amount }
                else { result.other += amount }
            } else if fact.eventType == "refund" {
                result.refunds += abs(fact.amount)
                result.refundCount += 1
            } else if fact.eventType == "payment_void" || fact.eventType == "reversal" {
                let amount = -abs(fact.amount)
                result.capturedSales += amount
                if let orderId = fact.orderId { result.orderIds.insert(orderId) }
                let method = (fact.paymentMethod ?? "").lowercased()
                if method == "cash" { result.cash += amount }
                else if method.contains("card") || method.contains("credit") { result.card += amount }
                else if method.contains("qr") || method.contains("promptpay") { result.qr += amount }
                else { result.other += amount }
            }
            if fact.isLateAdjustment { result.lateAdjustmentTotal += fact.amount }
        }
        return result
    }

    // MARK: - Break-Even & Investment Payback Analysis (Managerial F&B Accounting)

    /// Computes Monthly Break-Even Sales: (Fixed OpEx + Monthly Depreciation) / Contribution Margin Ratio
    static func breakEvenMonthlySales(fixedOpEx: Double, monthlyDepreciation: Double, grossMarginPct: Double) -> Double {
        let fixedCosts = max(0, fixedOpEx) + max(0, monthlyDepreciation)
        let cmr = min(max(grossMarginPct / 100.0, 0.05), 1.0)
        guard fixedCosts > 0 else { return 0 }
        return fixedCosts / cmr
    }

    /// Computes Daily Break-Even Sales Target based on active operating days in month
    static func breakEvenDailySales(monthlyBreakEven: Double, daysInMonth: Int = 30) -> Double {
        guard daysInMonth > 0 else { return 0 }
        return monthlyBreakEven / Double(daysInMonth)
    }

    /// Computes Net Operating Cash Flow (EBITDA approximation): Net Profit + Depreciation
    static func operatingCashFlow(netProfit: Double, depreciation: Double) -> Double {
        return netProfit + max(0, depreciation)
    }

    /// Computes Payback Progress & Estimated Timeline
    static func paybackMetrics(
        totalCapEx: Double,
        accumulatedCashFlow: Double,
        monthlyAverageCashFlow: Double
    ) -> (
        progressPct: Double,
        isFullyPaidBack: Bool,
        hasInvestmentData: Bool,
        remainingMonths: Double,
        remainingDays: Int,
        paybackYears: Double
    ) {
        guard totalCapEx > 0 else {
            return (0.0, false, false, 0, 0, 0)
        }
        let progress = min(max((accumulatedCashFlow / totalCapEx) * 100.0, 0), 100.0)
        let remainingCapital = max(0, totalCapEx - accumulatedCashFlow)
        let isComplete = remainingCapital <= 0.01

        if isComplete {
            return (100.0, true, true, 0, 0, 0)
        }

        guard monthlyAverageCashFlow > 0 else {
            return (progress, false, true, Double.infinity, Int.max, Double.infinity)
        }

        let remainingMonths = remainingCapital / monthlyAverageCashFlow
        let remainingDays = Int(remainingMonths * 30.0)
        let paybackYears = (totalCapEx / monthlyAverageCashFlow) / 12.0

        return (progress, false, true, remainingMonths, remainingDays, paybackYears)
    }
}
