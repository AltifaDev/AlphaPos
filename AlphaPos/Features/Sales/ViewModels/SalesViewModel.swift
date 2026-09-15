import Foundation
import SwiftData
import SwiftUI

@Observable @MainActor
final class SalesViewModel {
    enum SummaryMode {
        case shift
        case daily
        case monthly
    }

    // UI state variables
    var summaryMode: SummaryMode = .shift
    var selectedRegisterSessionId: UUID?
    var selectedShiftInterval: DateInterval?
    var selectedDate: Date = Date()
    var selectedMonth: Int = Calendar.current.component(.month, from: Date())
    var selectedYear: Int = Calendar.current.component(.year, from: Date())
    var businessDayCutoffHour: Int = 4
    var businessTimeZoneID: String = "Asia/Bangkok"

    // ─────────────────────────────────────────────────
    // MARK: KPIs — Revenue & Orders
    // ─────────────────────────────────────────────────
    var grossRevenue: Double = 0.0
    var netRevenue: Double = 0.0
    /// Net sales after refunds including VAT; reconciles to Dashboard.
    var netSalesInclVAT: Double = 0.0
    /// Net output VAT after refund reversals; a liability, not P&L revenue.
    var netOutputVAT: Double = 0.0
    /// Revenue used by P&L under tax-exclusive accounting presentation.
    var accountingRevenueExVAT: Double = 0.0
    var taxCollected: Double = 0.0
    var serviceChargeCollected: Double = 0.0
    var discountGiven: Double = 0.0
    var totalOrders: Int = 0
    var averageTicketValue: Double = 0.0
    var totalItemsSold: Int = 0

    // ─────────────────────────────────────────────────
    // MARK: KPIs — Order Type Mix
    // ─────────────────────────────────────────────────
    var dineInOrders: Int = 0
    var takeOutOrders: Int = 0
    var deliveryOrders: Int = 0
    var dineInRevenue: Double = 0.0
    var takeOutRevenue: Double = 0.0
    var deliveryRevenue: Double = 0.0

    // ─────────────────────────────────────────────────
    // MARK: KPIs — Cancellation & Voids
    // ─────────────────────────────────────────────────
    var cancelledOrders: Int = 0
    var cancelledItemsCount: Int = 0
    var refundedAmount: Double = 0.0

    // ─────────────────────────────────────────────────
    // MARK: Profitability (P&L)
    // ─────────────────────────────────────────────────
    var totalCOGS: Double = 0.0           // Cost of Goods Sold จาก Recipe × InventoryItem.costPrice
    var cogsPct: Double { grossRevenue > 0 ? (totalCOGS / grossRevenue) * 100 : 0.0 }
    var grossProfit: Double = 0.0          // grossRevenue − totalCOGS
    var grossMarginPct: Double = 0.0       // grossProfit / grossRevenue × 100
    var totalLaborCost: Double = 0.0       // จาก Timecard + Employee.payRate
    var totalLaborHours: Double = 0.0
    var laborCostPct: Double = 0.0         // laborCost / grossRevenue × 100
    var revenuePerLaborHour: Double = 0.0
    var totalWasteCost: Double = 0.0       // InventoryTransaction type="waste" × costPrice
    var totalOperatingExpenses: Double = 0.0 // C-3: Expense model (cash expenses, bills, etc.)
    var totalDepreciationExpense: Double = 0.0
    var totalPrepaidExpenseRecognized: Double = 0.0
    var estimatedNetProfit: Double = 0.0   // grossProfit − laborCost − wasteCost − operatingExpenses
    var netProfitMarginPct: Double = 0.0

    // ─────────────────────────────────────────────────
    // MARK: Break-Even & Investment Payback
    // ─────────────────────────────────────────────────
    var totalCapExInvestment: Double = 0.0
    var hasCapExInvestment: Bool = false
    var monthlyBreakEvenSales: Double = 0.0
    var dailyBreakEvenSales: Double = 0.0
    var operatingCashFlow: Double = 0.0
    var paybackProgressPct: Double = 0.0
    var paybackRemainingMonths: Double = 0.0
    var paybackRemainingDays: Int = 0
    var paybackTotalYears: Double = 0.0
    var isFullyPaidBack: Bool = false

    // ─────────────────────────────────────────────────
    // MARK: Inventory Analytics
    // ─────────────────────────────────────────────────
    var totalInventoryValue: Double = 0.0   // Σ (currentQty × costPrice)
    var lowStockItems: [InventoryAlertPoint] = []
    var inventoryUsageSummary: [InventoryUsagePoint] = []
    var wasteTransactions: [WastePoint] = []
    var inventoryTurnoverRate: Double = 0.0

    // ─────────────────────────────────────────────────
    // MARK: Delivery Platform Analytics
    // ─────────────────────────────────────────────────
    var deliveryPlatformBreakdown: [DeliveryPlatformPoint] = []
    var totalDeliveryGPFees: Double = 0.0
    var totalDeliveryAdFees: Double = 0.0
    var totalDeliveryPlatformCosts: Double = 0.0
    var netDeliveryRevenue: Double = 0.0

    // Government co-payment reconciliation (kept separate from delivery).
    var supportProgramOrders: Int = 0
    var supportProgramSales: Double = 0.0
    var supportCitizenCollected: Double = 0.0
    var supportGovernmentReceivable: Double = 0.0
    var supportGovernmentReceived: Double = 0.0

    // ─────────────────────────────────────────────────
    // MARK: Staff Analytics
    // ─────────────────────────────────────────────────
    var cashierPerformance: [CashierPerformancePoint] = []
    var staffLaborBreakdown: [StaffLaborPoint] = []
    var peakHour: Int? = nil
    var peakHourRevenue: Double = 0.0

    // ─────────────────────────────────────────────────
    // MARK: Menu Intelligence
    // ─────────────────────────────────────────────────
    var menuEngineeringMatrix: [MenuMatrixPoint] = []   // Star/Plow/Puzzle/Dog
    var topMarginItems: [ProductSalesPoint] = []
    var categoryBreakdown: [CategoryBreakdownPoint] = []
    var modifierRevenue: Double = 0.0

    // ─────────────────────────────────────────────────
    // MARK: Trend & Breakdown (existing)
    // ─────────────────────────────────────────────────
    var hourlyTrend: [HourlySalesPoint] = []
    var dailyTrend: [DailySalesPoint] = []
    var paymentBreakdown: [PaymentBreakdownPoint] = []
    var productSales: [ProductSalesPoint] = []
    var historicalOrders: [Order] = []

    // Available years for filter picker
    let availableYears: [Int] = {
        let y = Calendar.current.component(.year, from: Date())
        return Array((y - 2)...(y + 1))
    }()

    let monthsList = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December"
    ]

    var selectedMonthName: String {
        let index = selectedMonth - 1
        guard index >= 0 && index < monthsList.count else {
            return "Month \(selectedMonth)"
        }
        return monthsList[index]
    }

    init() {}

    private var selectedBusinessDayInterval: DateInterval {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: businessTimeZoneID) ?? .current
        let dayStart = calendar.startOfDay(for: selectedDate)
        let start = calendar.date(byAdding: .hour, value: businessDayCutoffHour, to: dayStart) ?? dayStart
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return DateInterval(start: start, end: end)
    }

    // ─────────────────────────────────────────────────
    // MARK: - Main Entry: updateAnalytics
    // ─────────────────────────────────────────────────

    /// Master analytics update — calls all sub-analyzers
func updateAnalytics(
        orders: [Order],
        inventoryItems: [InventoryItem] = [],
        employees: [Employee] = [],
        timecards: [Timecard] = [],
        expenses: [Expense] = [],
        inventoryTransactions: [InventoryTransaction] = [],
        financialEvents: [FinancialEvent] = []
    ) {
        self.runAnalytics(
            orders: orders,
            inventoryItems: inventoryItems,
            employees: employees,
            timecards: timecards,
            expenses: expenses,
            inventoryTransactions: inventoryTransactions,
            financialEvents: financialEvents
        )
    }

    /// Internal: runs on the main actor to preserve SwiftData model context integrity
    private func runAnalytics(
        orders: [Order],
        inventoryItems: [InventoryItem],
        employees: [Employee],
        timecards: [Timecard],
        expenses: [Expense] = [],
        inventoryTransactions: [InventoryTransaction],
        financialEvents: [FinancialEvent]
    ) {
        let calendar = Calendar.current

        // 1. Filter recognized sales for the selected period.
        // Uses the same canonical definition as Dashboard & Reports
        // (Order.isRecognizedSale) so all three modules agree on what
        // counts as a sale — paid orders OR closed/completed orders,
        // never cancelled/deleted ones.
        // FinancialEvent is the canonical recognized-sales source used by the
        // Live Dashboard. Order timestamps are operational, not accounting
        // timestamps, and can differ after partial settlement or late sync.
        let scopedFinancialEvents = financialEvents.filter(isFinancialEventInSelectedPeriod)
        let recognizedOrderIds = Set(scopedFinancialEvents.compactMap { event in
            (event.eventType == "sale_capture" || event.eventType == "government_subsidy")
                ? event.orderId : nil
        })
        let filtered = orders.filter { !$0.isDeleted && recognizedOrderIds.contains($0.id) }

        self.historicalOrders = filtered.sorted(by: { $0.createdAt > $1.createdAt })

        // 2. Cancelled orders (same period, no payment)
        let cancelledInPeriod = orders.filter { order in
            guard !order.isDeleted, order.status == "cancelled" else { return false }
            switch summaryMode {
            case .shift:
                guard let interval = selectedShiftInterval else { return false }
                return order.createdAt >= interval.start && order.createdAt < interval.end
            case .daily:
                return selectedBusinessDayInterval.contains(order.createdAt)
            case .monthly:
                let m = calendar.component(.month, from: order.createdAt)
                let y = calendar.component(.year, from: order.createdAt)
                return m == selectedMonth && y == selectedYear
            }
        }
        self.cancelledOrders = cancelledInPeriod.count
        self.cancelledItemsCount = cancelledInPeriod.flatMap { $0.items }.reduce(0) { $0 + $1.quantity }

        // Run sub-analyzers
        computeRevenueKPIs(filtered: filtered, allOrders: orders, financialEvents: scopedFinancialEvents)
        computeOrderTypeMix(filtered: filtered)
        computeTrends(filtered: filtered, calendar: calendar)
        computePaymentBreakdown(filtered: filtered)
        computeProductSales(filtered: filtered)
        computeDeliveryAnalytics(filtered: filtered)
        computeSupportProgramAnalytics(filtered: filtered)
        computeCategoryBreakdown()
        computeMenuEngineering()
        computeCashierPerformance(filtered: filtered)

        // P&L must still be computed when the inventory catalog is empty;
        // in that case COGS is explicitly zero rather than leaving stale state.
        computeProfitability(
            filtered: filtered,
            inventoryTransactions: inventoryTransactions,
            financialEvents: scopedFinancialEvents,
            expenses: expenses
        )
        if !inventoryItems.isEmpty {
            computeInventoryAnalytics(
                inventoryItems: inventoryItems,
                inventoryTransactions: inventoryTransactions
            )
        }

        if !timecards.isEmpty && !employees.isEmpty {
            computeLaborAnalytics(timecards: timecards, employees: employees, calendar: calendar)
        }
    }

    private func isFinancialEventInSelectedPeriod(_ event: FinancialEvent) -> Bool {
        guard !event.isDeleted, event.status == "posted",
              AccountingMath.recognizedAmount(eventType: event.eventType, amount: event.amount) != nil else { return false }
        let calendar = Calendar.current
        switch summaryMode {
        case .shift:
            guard let sessionId = selectedRegisterSessionId,
                  let interval = selectedShiftInterval else { return false }
            return event.registerSessionId == sessionId ||
                (event.registerSessionId == nil && interval.contains(event.occurredAt))
        case .daily:
            let expectedKey = BusinessDayContext.key(
                for: selectedBusinessDayInterval.start,
                cutoffHour: businessDayCutoffHour,
                timeZoneID: businessTimeZoneID
            )
            return event.businessDateKey == expectedKey ||
                (event.businessDateKey.isEmpty && selectedBusinessDayInterval.contains(event.occurredAt))
        case .monthly:
            return calendar.component(.month, from: event.occurredAt) == selectedMonth &&
                calendar.component(.year, from: event.occurredAt) == selectedYear
        }
    }

    // ─────────────────────────────────────────────────
    // MARK: Revenue KPIs
    // ─────────────────────────────────────────────────
    private func computeRevenueKPIs(
        filtered: [Order],
        allOrders: [Order],
        financialEvents: [FinancialEvent]
    ) {
        var gross = 0.0, tax = 0.0, svc = 0.0, disc = 0.0, items = 0, refunds = 0.0

        for order in filtered {
            gross += order.total
            tax   += order.tax
            svc   += order.serviceCharge
            disc  += order.discount

            for item in order.items where item.status != "cancelled" {
                items += item.quantity
            }
            // Refunds come from RefundTransaction — the same source Daily Sales
            // reports and the Live Dashboard use — so refund totals reconcile
            // across all three modules.
            refunds += order.refunds.filter { refund in
                guard !refund.isDeleted && refund.status == "completed" else { return false }
                switch summaryMode {
                case .shift:
                    guard let sessionId = selectedRegisterSessionId,
                          let interval = selectedShiftInterval else { return false }
                    return RegisterShiftScope.contains(
                        eventSessionId: refund.registerSessionId,
                        eventAt: refund.financialEventAt,
                        sessionId: sessionId,
                        openedAt: interval.start,
                        closedAt: interval.end
                    )
                case .daily:
                    return selectedBusinessDayInterval.contains(refund.financialEventAt)
                case .monthly:
                    return Calendar.current.component(.month, from: refund.financialEventAt) == selectedMonth &&
                           Calendar.current.component(.year, from: refund.financialEventAt) == selectedYear
                }
            }.reduce(0.0) { $0 + $1.refundAmount }
        }

        self.grossRevenue      = gross
        self.taxCollected      = tax
        self.serviceChargeCollected = svc
        self.discountGiven     = disc
        // Net revenue = ticket totals net of refunds (matches Reports.netRevenue
        // and Dashboard todayRevenue). VAT / service charge remain visible as
        // their own KPIs and in the P&L bridge below.
        let facts = financialEvents.map {
            AccountingFact(eventType: $0.eventType, amount: $0.amount,
                           paymentMethod: $0.paymentMethod, orderId: $0.orderId,
                           isLateAdjustment: $0.isLateAdjustment)
        }
        let ledger = AccountingMath.summarize(facts)
        self.grossRevenue = ledger.capturedSales
        self.refundedAmount = ledger.refunds
        self.netRevenue = ledger.netSales
        self.netSalesInclVAT = ledger.netSales

        let ordersById = Dictionary(uniqueKeysWithValues: allOrders.map { ($0.id, $0) })
        var capturedByOrder: [UUID: Double] = [:]
        for event in financialEvents where event.eventType != "refund" {
            guard let orderId = event.orderId,
                  let amount = AccountingMath.recognizedAmount(
                    eventType: event.eventType, amount: event.amount
                  ) else { continue }
            capturedByOrder[orderId, default: 0] += amount
        }
        let capturedVAT = filtered.reduce(0.0) { result, order in
            result + AccountingMath.allocatedOutputVAT(
                ticketTotal: order.total, documentVAT: order.tax,
                recognizedAmount: capturedByOrder[order.id, default: 0]
            )
        }
        var refundsByOrder: [UUID: Double] = [:]
        for event in financialEvents where event.eventType == "refund" {
            guard let orderId = event.orderId else { continue }
            refundsByOrder[orderId, default: 0] += abs(event.amount)
        }
        let reversedVAT = refundsByOrder.reduce(0.0) { result, entry in
            guard let order = ordersById[entry.key], order.total > 0 else { return result }
            return result + AccountingMath.allocatedOutputVAT(
                ticketTotal: order.total, documentVAT: order.tax,
                recognizedAmount: entry.value
            )
        }
        self.netOutputVAT = capturedVAT - reversedVAT
        self.taxCollected = self.netOutputVAT
        self.accountingRevenueExVAT = self.netSalesInclVAT - self.netOutputVAT
        self.totalOrders       = filtered.count
        self.averageTicketValue = filtered.isEmpty ? 0 : self.grossRevenue / Double(filtered.count)
        self.totalItemsSold    = items

        // Peak hour
        if let best = hourlyTrend.max(by: { $0.revenue < $1.revenue }), best.revenue > 0 {
            self.peakHour        = best.hour
            self.peakHourRevenue = best.revenue
        }
    }

    // ─────────────────────────────────────────────────
    // MARK: Order Type Mix
    // ─────────────────────────────────────────────────
    private func computeOrderTypeMix(filtered: [Order]) {
        var dineInCnt = 0, takeOutCnt = 0, deliveryCnt = 0
        var dineInRev = 0.0, takeOutRev = 0.0, deliveryRev = 0.0

        for order in filtered {
            switch order.orderType {
            case "dine_in":
                dineInCnt += 1; dineInRev += order.total
            case "take_out":
                takeOutCnt += 1; takeOutRev += order.total
            case "delivery":
                deliveryCnt += 1; deliveryRev += order.total
            default:
                dineInCnt += 1; dineInRev += order.total
            }
        }

        self.dineInOrders    = dineInCnt
        self.takeOutOrders   = takeOutCnt
        self.deliveryOrders  = deliveryCnt
        self.dineInRevenue   = dineInRev
        self.takeOutRevenue  = takeOutRev
        self.deliveryRevenue = deliveryRev
    }

    // ─────────────────────────────────────────────────
    // MARK: Trends
    // ─────────────────────────────────────────────────
    private func computeTrends(filtered: [Order], calendar: Calendar) {
        var hourlyMap: [Int: Double] = [:]
        var dailyMap: [Int: Double] = [:]

        for order in filtered {
            if summaryMode != .monthly {
                let h = calendar.component(.hour, from: order.createdAt)
                hourlyMap[h, default: 0] += order.total
            } else {
                let d = calendar.component(.day, from: order.createdAt)
                dailyMap[d, default: 0] += order.total
            }
        }

        if summaryMode != .monthly {
            var pts: [HourlySalesPoint] = []
            for hour in 9...22 {
                pts.append(HourlySalesPoint(hour: hour, revenue: hourlyMap[hour] ?? 0))
            }
            for (h, r) in hourlyMap where h < 9 || h > 22 {
                pts.append(HourlySalesPoint(hour: h, revenue: r))
            }
            self.hourlyTrend = pts.sorted(by: { $0.hour < $1.hour })
            self.dailyTrend = []
        } else {
            let base = calendar.date(from: DateComponents(year: selectedYear, month: selectedMonth)) ?? Date()
            let daysLimit = calendar.range(of: .day, in: .month, for: base)?.count ?? 30
            self.dailyTrend = (1...daysLimit).map { DailySalesPoint(day: $0, revenue: dailyMap[$0] ?? 0) }
            self.hourlyTrend = []
        }

        // Update peak hour after trends computed
        if let best = hourlyTrend.max(by: { $0.revenue < $1.revenue }), best.revenue > 0 {
            self.peakHour = best.hour
            self.peakHourRevenue = best.revenue
        }
    }

    // ─────────────────────────────────────────────────
    // MARK: Payment Breakdown
    // ─────────────────────────────────────────────────
    private func computePaymentBreakdown(filtered: [Order]) {
        var map: [String: (amount: Double, count: Int)] = [:]
        for order in filtered {
            // Only captured payments represent tender actually received.
            // Refunded, failed and manager-voided correction records must stay
            // in the audit trail without inflating the payment breakdown.
            for payment in order.payments where !payment.isDeleted && payment.isCaptured {
                if summaryMode == .shift,
                   let sessionId = selectedRegisterSessionId,
                   let interval = selectedShiftInterval,
                   !RegisterShiftScope.contains(
                       eventSessionId: payment.registerSessionId,
                       eventAt: payment.paidAt,
                       sessionId: sessionId,
                       openedAt: interval.start,
                       closedAt: interval.end
                   ) { continue }
                let key = payment.paymentMethod.lowercased()
                let cur = map[key] ?? (0, 0)
                map[key] = (cur.amount + payment.amount, cur.count + 1)
            }
        }

        self.paymentBreakdown = map.map { key, val in
            let name: String
            switch key {
            case "cash":           name = "Cash"
            case "credit_card":    name = "Credit Card"
            case "qr_promptpay":   name = "PromptPay QR"
            case "delivery_platform": name = "Delivery Platform"
            case "true_money":     name = "TrueMoney Wallet"
            default:               name = key.capitalized
            }
            return PaymentBreakdownPoint(method: name, amount: val.amount, count: val.count)
        }.sorted(by: { $0.amount > $1.amount })
    }

    private func computeSupportProgramAnalytics(filtered: [Order]) {
        let supported = filtered.filter(\.usesGovernmentSupport)
        supportProgramOrders = supported.count
        supportProgramSales = supported.reduce(0) { $0 + $1.recognizedNetTotal }
        supportCitizenCollected = supported.reduce(0) { $0 + min($1.paidAmount, $1.supportCitizenAmount) }
        supportGovernmentReceived = supported
            .filter { $0.supportSettlementStatus == "received" }
            .reduce(0) { $0 + $1.supportGovernmentAmount }
        supportGovernmentReceivable = supported
            .filter { $0.supportSettlementStatus == "pending" }
            .reduce(0) { $0 + $1.supportGovernmentAmount }
    }

    // ─────────────────────────────────────────────────
    // MARK: Product Sales + Modifier Revenue
    // ─────────────────────────────────────────────────
    private func computeProductSales(filtered: [Order]) {
        var productMap: [String: ProductSalesPoint] = [:]
        var modRev = 0.0

        for order in filtered {
            let channel = order.orderType == "delivery" ? "เดลิเวอรี" : "หน้าร้าน"
            for item in order.items where !item.isDeleted && item.status != "cancelled" {
                let itemId   = item.menuItem?.id ?? item.id.uuidString
                let itemName = item.menuItem?.name ?? "Unknown Dish"
                let category = item.menuItem?.category?.name ?? "Other"
                let itemType = item.resolvedLineType == .addOn ? "Add-on" : "เมนูหลัก"
                let key = "\(channel)|\(itemType)|\(itemId)"

                if let ex = productMap[key] {
                    productMap[key] = ProductSalesPoint(
                        name: itemName, category: category,
                        channel: channel, itemType: itemType, sourceId: itemId,
                        quantity: ex.quantity + item.quantity,
                        unitPrice: item.unitPrice,
                        totalRevenue: ex.totalRevenue + item.subtotal,
                        cogs: ex.cogs  // will be filled in profitability pass
                    )
                } else {
                    productMap[key] = ProductSalesPoint(
                        name: itemName, category: category,
                        channel: channel, itemType: itemType, sourceId: itemId,
                        quantity: item.quantity,
                        unitPrice: item.unitPrice,
                        totalRevenue: item.subtotal,
                        cogs: 0
                    )
                }
                // Modifier add-on revenue
                for mod in item.modifiers where !mod.isDeleted {
                    let revenue = mod.price * Double(item.quantity)
                    modRev += revenue
                    let name = mod.modifier?.name ?? "Modifier"
                    let modKey = "\(channel)|modifier|\(mod.id.uuidString)"
                    if let ex = productMap[modKey] {
                        productMap[modKey] = ProductSalesPoint(name: name, category: "Modifier", channel: channel, itemType: "Modifier", sourceId: mod.id.uuidString, quantity: ex.quantity + item.quantity, unitPrice: mod.price, totalRevenue: ex.totalRevenue + revenue, cogs: ex.cogs)
                    } else {
                        productMap[modKey] = ProductSalesPoint(name: name, category: "Modifier", channel: channel, itemType: "Modifier", sourceId: mod.id.uuidString, quantity: item.quantity, unitPrice: mod.price, totalRevenue: revenue, cogs: 0)
                    }
                }
            }
        }

        self.productSales    = productMap.values.sorted(by: { $0.quantity > $1.quantity })
        self.modifierRevenue = modRev
    }

    // ─────────────────────────────────────────────────
    // MARK: Category Breakdown
    // ─────────────────────────────────────────────────
    private func computeCategoryBreakdown() {
        var catMap: [String: (revenue: Double, qty: Int)] = [:]
        for prod in productSales {
            let cur = catMap[prod.category] ?? (0, 0)
            catMap[prod.category] = (cur.revenue + prod.totalRevenue, cur.qty + prod.quantity)
        }
        self.categoryBreakdown = catMap.map { key, val in
            CategoryBreakdownPoint(
                category: key,
                revenue: val.revenue,
                quantity: val.qty,
                sharePct: grossRevenue > 0 ? val.revenue / grossRevenue * 100 : 0
            )
        }.sorted(by: { $0.revenue > $1.revenue })
    }

    // ─────────────────────────────────────────────────
    // MARK: Menu Engineering Matrix (Star/Plow/Puzzle/Dog)
    // ─────────────────────────────────────────────────
    private func computeMenuEngineering() {
        let mainProducts = productSales.filter { $0.itemType == "เมนูหลัก" }
        guard !mainProducts.isEmpty else {
            self.menuEngineeringMatrix = []
            self.topMarginItems = []
            return
        }

        let avgQty    = Double(mainProducts.map(\.quantity).reduce(0, +)) / Double(mainProducts.count)
        let avgMargin = mainProducts.map(\.grossMarginPct).reduce(0, +) / Double(mainProducts.count)

        self.menuEngineeringMatrix = mainProducts.map { prod in
            let isHighPop    = Double(prod.quantity) >= avgQty
            let isHighMargin = prod.grossMarginPct >= avgMargin
            let segment: MenuSegment
            switch (isHighPop, isHighMargin) {
            case (true,  true):  segment = .star
            case (true,  false): segment = .plowHorse
            case (false, true):  segment = .puzzle
            case (false, false): segment = .dog
            }
            return MenuMatrixPoint(product: prod, segment: segment)
        }.sorted(by: { $0.product.totalRevenue > $1.product.totalRevenue })

        self.topMarginItems = mainProducts
            .filter { $0.cogs > 0 }
            .sorted(by: { $0.grossMarginPct > $1.grossMarginPct })
            .prefix(10)
            .map { $0 }
    }

    // ─────────────────────────────────────────────────
    // MARK: Delivery Platform Analytics
    // ─────────────────────────────────────────────────
    private func computeDeliveryAnalytics(filtered: [Order]) {
        let deliveryOrders = filtered.filter { $0.orderType == "delivery" }
        var platformMap: [String: DeliveryPlatformPoint] = [:]

        for order in deliveryOrders {
            let brand: String
            if let deliveryBrand = order.deliveryBrand, !deliveryBrand.isEmpty {
                brand = deliveryBrand
            } else {
                brand = "Other"
            }
            let gpFee = order.deliveryGPFeeAmount
            let adFee = order.deliveryAdFeeAmount
            let otherFee = max(order.deliveryOtherFee, 0)
            let grossRevenue = order.total
            let netRev = order.deliveryNetRevenue

            if let ex = platformMap[brand] {
                platformMap[brand] = DeliveryPlatformPoint(
                    brandName:     brand,
                    orderCount:    ex.orderCount + 1,
                    grossRevenue:  ex.grossRevenue + grossRevenue,
                    gpFees:        ex.gpFees + gpFee,
                    adFees:        ex.adFees + adFee,
                    otherFees:     ex.otherFees + otherFee,
                    netRevenue:    ex.netRevenue + netRev
                )
            } else {
                platformMap[brand] = DeliveryPlatformPoint(
                    brandName:    brand,
                    orderCount:   1,
                    grossRevenue: grossRevenue,
                    gpFees:       gpFee,
                    adFees:       adFee,
                    otherFees:    otherFee,
                    netRevenue:   netRev
                )
            }
        }

        self.deliveryPlatformBreakdown = platformMap.values
            .sorted(by: { $0.grossRevenue > $1.grossRevenue })
        self.totalDeliveryGPFees  = platformMap.values.map(\.gpFees).reduce(0, +)
        self.totalDeliveryAdFees  = platformMap.values.map(\.adFees).reduce(0, +)
        self.totalDeliveryPlatformCosts = platformMap.values.reduce(0) { $0 + $1.gpFees + $1.adFees + $1.otherFees }
        self.netDeliveryRevenue   = platformMap.values.map(\.netRevenue).reduce(0, +)
    }

    // ─────────────────────────────────────────────────
    // MARK: Cashier Performance
    // ─────────────────────────────────────────────────
    private func computeCashierPerformance(filtered: [Order]) {
        var cashierMap: [String: (orders: Int, revenue: Double, items: Int)] = [:]
        for order in filtered {
            let name = order.cashierName.isEmpty ? "Unknown" : order.cashierName
            let cur = cashierMap[name] ?? (0, 0, 0)
            let itemCount = order.items.filter { $0.status != "cancelled" }.reduce(0) { $0 + $1.quantity }
            cashierMap[name] = (cur.orders + 1, cur.revenue + order.total, cur.items + itemCount)
        }
        self.cashierPerformance = cashierMap.map { name, val in
            CashierPerformancePoint(
                name: name,
                orderCount: val.orders,
                revenue: val.revenue,
                itemsSold: val.items,
                avgTicket: val.orders > 0 ? val.revenue / Double(val.orders) : 0
            )
        }.sorted(by: { $0.revenue > $1.revenue })
    }

    // ─────────────────────────────────────────────────
    // MARK: Profitability — actual COGS from immutable sell ledger snapshots
    // ─────────────────────────────────────────────────
    private func computeProfitability(
        filtered: [Order],
        inventoryTransactions: [InventoryTransaction],
        financialEvents: [FinancialEvent],
        expenses: [Expense] = []
    ) {
        let sellCostByReference = Dictionary(grouping: inventoryTransactions.filter {
            !$0.isDeleted && $0.movementType == .sell && $0.referenceId != nil
        }, by: { $0.referenceId! }).mapValues {
            $0.reduce(0) { $0 + $1.magnitude * ($1.costPrice ?? 0) }
        }

        var capturedByOrder: [UUID: Double] = [:]
        for event in financialEvents where event.eventType != "refund" {
            guard let orderId = event.orderId,
                  let amount = AccountingMath.recognizedAmount(
                    eventType: event.eventType, amount: event.amount
                  ) else { continue }
            capturedByOrder[orderId, default: 0] += amount
        }

        // Compute COGS per product (match by menuItem.id from order items).
        // Partial settlements recognize the same fraction of COGS as Dashboard.
        var productCogsMap: [String: Double] = [:]  // productSalesPoint.id (menuItem.id or name) → total COGS
        for order in filtered {
            let capturedFraction = AccountingMath.capturedFraction(
                ticketTotal: order.total,
                recognizedBeforeRefunds: capturedByOrder[order.id, default: 0]
            )
            for item in order.items where item.status != "cancelled" {
                guard let menuItem = item.menuItem else { continue }
                let channel = order.orderType == "delivery" ? "เดลิเวอรี" : "หน้าร้าน"
                let itemType = item.resolvedLineType == .addOn ? "Add-on" : "เมนูหลัก"
                productCogsMap["\(channel)|\(itemType)|\(menuItem.id)", default: 0] += capturedFraction * (sellCostByReference[item.id] ?? 0)
                for modifier in item.modifiers where !modifier.isDeleted {
                    productCogsMap["\(channel)|modifier|\(modifier.id.uuidString)", default: 0] += capturedFraction * (sellCostByReference[modifier.id] ?? 0)
                }
            }
        }

        // Update productSales with COGS
        let updatedProducts: [ProductSalesPoint] = productSales.map { prod in
            ProductSalesPoint(
                name: prod.name, category: prod.category,
                channel: prod.channel, itemType: prod.itemType, sourceId: prod.sourceId,
                quantity: prod.quantity, unitPrice: prod.unitPrice,
                totalRevenue: prod.totalRevenue,
                cogs: productCogsMap[prod.id] ?? 0
            )
        }

        let directCOGS = productCogsMap.values.reduce(0, +)

        self.totalCOGS       = directCOGS
        // P&L starts from revenue net of refunds so the statement reconciles
        // with the Net Revenue KPI and the Reports module.
        self.grossProfit      = accountingRevenueExVAT - directCOGS
        self.grossMarginPct   = accountingRevenueExVAT > 0 ? grossProfit / accountingRevenueExVAT * 100 : 0
        self.productSales     = updatedProducts

        let calendar = Calendar.current
        let expenseInterval: DateInterval? = {
            switch summaryMode {
            case .shift: return selectedShiftInterval
            case .daily:
                return selectedBusinessDayInterval
            case .monthly:
                guard let start = calendar.date(from: DateComponents(year: selectedYear, month: selectedMonth, day: 1)),
                      let end = calendar.date(byAdding: .month, value: 1, to: start) else { return nil }
                return DateInterval(start: start, end: end)
            }
        }()
        var operating = 0.0
        var depreciation = 0.0
        var prepaid = 0.0
        for expense in expenses {
            guard !expense.isDeleted, let interval = expenseInterval else { continue }
            let treatment = AccountingMath.normalizedExpenseRecognition(
                expense.recognitionType, legacyIsCapEx: expense.isCapEx
            )
            let netCost = max(0, expense.amount - (expense.isVATRecoverable ? expense.vatAmount : 0))
            switch treatment {
            case "operating_expense":
                if interval.contains(expense.date) { operating += netCost }
            case "prepaid_expense":
                guard let serviceStart = expense.serviceStartDate,
                      let serviceEnd = expense.serviceEndDate, serviceEnd > serviceStart else {
                    if interval.contains(expense.date) { prepaid += netCost }
                    continue
                }
                let overlapStart = max(interval.start, serviceStart)
                let overlapEnd = min(interval.end, serviceEnd)
                if overlapEnd > overlapStart {
                    prepaid += netCost * overlapEnd.timeIntervalSince(overlapStart) / serviceEnd.timeIntervalSince(serviceStart)
                }
            case "fixed_asset":
                let available = expense.availableForUseDate ?? expense.date
                guard available < interval.end, expense.usefulLifeMonths > 0 else { continue }
                let monthly = AccountingMath.monthlyStraightLineDepreciation(
                    cost: netCost, residualValue: expense.residualValue,
                    usefulLifeMonths: expense.usefulLifeMonths
                )
                let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: interval.start)) ?? interval.start
                let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? interval.end
                let activeStart = max(interval.start, available)
                let overlap = max(0, min(interval.end, monthEnd).timeIntervalSince(activeStart))
                let monthDuration = max(1, monthEnd.timeIntervalSince(monthStart))
                depreciation += monthly * min(1, overlap / monthDuration)
            default: // refundable deposits are balance-sheet assets, not P&L expense
                break
            }
        }
        // CapEx Total Initial Investment
        let totalCapEx = expenses.filter {
            !$0.isDeleted &&
            AccountingMath.normalizedExpenseRecognition($0.recognitionType, legacyIsCapEx: $0.isCapEx) == "fixed_asset"
        }.reduce(0.0) { total, exp in
            total + max(0, exp.amount - (exp.isVATRecoverable ? exp.vatAmount : 0))
        }
        self.totalCapExInvestment = totalCapEx

        self.totalOperatingExpenses = operating
        self.totalDepreciationExpense = depreciation
        self.totalPrepaidExpenseRecognized = prepaid

        recomputeNetProfit()
        computeMenuEngineering()  // recompute with COGS data
    }

    // ─────────────────────────────────────────────────
    // MARK: Labor Analytics from Timecard
    // ─────────────────────────────────────────────────
    private func computeLaborAnalytics(timecards: [Timecard], employees: [Employee], calendar: Calendar) {
        let relevantTimecards = timecards.filter { tc in
            guard !tc.isDeleted else { return false }
            let clockIn = tc.clockIn
            switch summaryMode {
            case .shift:
                guard let interval = selectedShiftInterval else { return false }
                return clockIn < interval.end && (tc.clockOut ?? interval.end) > interval.start
            case .daily:
                let interval = selectedBusinessDayInterval
                return clockIn < interval.end && (tc.clockOut ?? interval.end) > interval.start
            case .monthly:
                let m = calendar.component(.month, from: clockIn)
                let y = calendar.component(.year, from: clockIn)
                return m == selectedMonth && y == selectedYear
            }
        }

        var empMap: [UUID: (hours: Double, otMins: Int, cost: Double, name: String)] = [:]
        var totalHours = 0.0
        var totalCost  = 0.0

        for tc in relevantTimecards {
            guard let emp = tc.employee, let clockOut = tc.clockOut else { continue }
            let effectiveIn: Date
            let effectiveOut: Date
            if summaryMode == .shift, let interval = selectedShiftInterval {
                effectiveIn = max(tc.clockIn, interval.start)
                effectiveOut = min(clockOut, interval.end)
            } else {
                effectiveIn = tc.clockIn
                effectiveOut = clockOut
            }
            let fullWorkedSecs = max(1, clockOut.timeIntervalSince(tc.clockIn))
            let workedSecs = max(0, effectiveOut.timeIntervalSince(effectiveIn))
            let allocation = min(1, workedSecs / fullWorkedSecs)
            let breakSecs  = Double(tc.breakDurationMinutes) * 60 * allocation
            let netHours   = max(0, (workedSecs - breakSecs) / 3600)

            let allocatedOT = Double(tc.overtimeMinutes) * allocation
            let regularHours = max(0, netHours - allocatedOT / 60)
            let otHours      = allocatedOT / 60

            let regularCost = regularHours * emp.payRate
            let otCost       = otHours * emp.payRate * 1.5
            let totalEmpCost = regularCost + otCost

            let cur = empMap[emp.id] ?? (0, 0, 0, "\(emp.firstName) \(emp.lastName)")
            empMap[emp.id] = (cur.hours + netHours, cur.otMins + Int(allocatedOT.rounded()), cur.cost + totalEmpCost, cur.name)

            totalHours += netHours
            totalCost  += totalEmpCost
        }

        self.totalLaborHours  = totalHours
        self.totalLaborCost   = totalCost
        self.laborCostPct = accountingRevenueExVAT > 0 ? totalCost / accountingRevenueExVAT * 100 : 0
        self.revenuePerLaborHour = totalHours > 0 ? accountingRevenueExVAT / totalHours : 0

        self.staffLaborBreakdown = empMap.map { _, val in
            StaffLaborPoint(name: val.name, hoursWorked: val.hours, overtimeMinutes: val.otMins, laborCost: val.cost)
        }.sorted(by: { $0.laborCost > $1.laborCost })

        recomputeNetProfit()
    }

    // ─────────────────────────────────────────────────
    // MARK: Inventory Analytics
    // ─────────────────────────────────────────────────
    private func computeInventoryAnalytics(
        inventoryItems: [InventoryItem],
        inventoryTransactions: [InventoryTransaction]
    ) {
        let activeItems = inventoryItems.filter { !$0.isDeleted }

        // Total stock value
        self.totalInventoryValue = activeItems.reduce(0) { $0 + ($1.currentQuantity * $1.costPrice) }

        // Low stock alerts
        self.lowStockItems = activeItems
            .filter { $0.currentQuantity <= $0.reorderLevel && $0.reorderLevel > 0 }
            .map { item in
                InventoryAlertPoint(
                    name: item.name,
                    currentQty: item.currentQuantity,
                    reorderLevel: item.reorderLevel,
                    unit: item.unit,
                    isOutOfStock: item.currentQuantity <= 0
                )
            }
            .sorted(by: { $0.currentQty < $1.currentQty })

        // Waste summary from InventoryTransactions — scoped to the selected
        // period (by event time, createdAt) so waste cost in the P&L matches
        // the revenue period instead of accumulating all-time waste.
        let calendar = Calendar.current
        let allWaste = activeItems.flatMap { $0.transactions }.filter { tx in
            guard tx.transactionType == InventoryMovementType.waste.rawValue, !tx.isDeleted else { return false }
            switch summaryMode {
            case .shift:
                guard let interval = selectedShiftInterval else { return false }
                return tx.createdAt >= interval.start && tx.createdAt < interval.end
            case .daily:
                return selectedBusinessDayInterval.contains(tx.createdAt)
            case .monthly:
                let m = calendar.component(.month, from: tx.createdAt)
                let y = calendar.component(.year, from: tx.createdAt)
                return m == selectedMonth && y == selectedYear
            }
        }
        self.totalWasteCost = allWaste.reduce(0.0) { total, tx in
            let costPer = tx.costPrice ?? (tx.item?.costPrice ?? 0)
            return total + abs(tx.quantity) * costPer
        }
        self.wasteTransactions = allWaste.map { tx in
            WastePoint(
                itemName: tx.item?.name ?? "Unknown",
                quantity: abs(tx.quantity),
                unit: tx.item?.unit ?? "",
                cost: abs(tx.quantity) * (tx.costPrice ?? tx.item?.costPrice ?? 0),
                date: tx.createdAt
            )
        }.sorted(by: { $0.date > $1.date })

        // Usage and cost come from the immutable sell ledger snapshot, not today's recipe.
        var usageMap: [String: (name: String, unit: String, theoretical: Double, cost: Double)] = [:]
        for tx in inventoryTransactions where tx.movementType == .sell && !tx.isDeleted {
            let inPeriod: Bool
            switch summaryMode {
            case .shift:
                if let interval = selectedShiftInterval {
                    inPeriod = tx.createdAt >= interval.start && tx.createdAt < interval.end
                } else {
                    inPeriod = false
                }
            case .daily:
                inPeriod = selectedBusinessDayInterval.contains(tx.createdAt)
            case .monthly:
                inPeriod = calendar.component(.month, from: tx.createdAt) == selectedMonth
                    && calendar.component(.year, from: tx.createdAt) == selectedYear
            }
            guard inPeriod, let inv = tx.item else { continue }
            let used = tx.magnitude
            let key = inv.id.uuidString
            let cur = usageMap[key] ?? (inv.name, inv.unit, 0, 0)
            usageMap[key] = (cur.name, cur.unit, cur.theoretical + used, cur.cost + used * (tx.costPrice ?? 0))
        }
        self.inventoryUsageSummary = usageMap.values.map {
            InventoryUsagePoint(name: $0.name, unit: $0.unit, theoreticalUsed: $0.theoretical, cost: $0.cost)
        }.sorted(by: { $0.cost > $1.cost })

        // Inventory Turnover Rate = COGS / Avg Inventory Value (simplified: use current value)
        self.inventoryTurnoverRate = totalInventoryValue > 0 ? totalCOGS / totalInventoryValue : 0

        recomputeNetProfit()
    }

    // ─────────────────────────────────────────────────
    // MARK: Net Profit (called after each sub-analyzer)
    // ─────────────────────────────────────────────────
    private func recomputeNetProfit() {
        // C-3: Include operating expenses in net profit calculation
        self.estimatedNetProfit = grossProfit - totalLaborCost - totalWasteCost
            - totalOperatingExpenses - totalPrepaidExpenseRecognized
            - totalDepreciationExpense - totalDeliveryPlatformCosts
        self.netProfitMarginPct = accountingRevenueExVAT > 0
            ? estimatedNetProfit / accountingRevenueExVAT * 100 : 0
        recomputeBreakEvenAndPayback()
    }

    private func recomputeBreakEvenAndPayback() {
        let fixedOpEx = totalOperatingExpenses + totalLaborCost + totalPrepaidExpenseRecognized
        self.monthlyBreakEvenSales = AccountingMath.breakEvenMonthlySales(
            fixedOpEx: fixedOpEx,
            monthlyDepreciation: totalDepreciationExpense,
            grossMarginPct: grossMarginPct
        )
        self.dailyBreakEvenSales = AccountingMath.breakEvenDailySales(
            monthlyBreakEven: monthlyBreakEvenSales,
            daysInMonth: 30
        )
        self.operatingCashFlow = AccountingMath.operatingCashFlow(
            netProfit: estimatedNetProfit,
            depreciation: totalDepreciationExpense
        )

        let payback = AccountingMath.paybackMetrics(
            totalCapEx: totalCapExInvestment,
            accumulatedCashFlow: max(0, operatingCashFlow),
            monthlyAverageCashFlow: max(0, operatingCashFlow)
        )
        self.hasCapExInvestment = payback.hasInvestmentData
        self.paybackProgressPct = payback.progressPct
        self.isFullyPaidBack = payback.isFullyPaidBack
        self.paybackRemainingMonths = payback.remainingMonths
        self.paybackRemainingDays = payback.remainingDays
        self.paybackTotalYears = payback.paybackYears
    }
}

// ─────────────────────────────────────────────────────
// MARK: - Supporting Data Structures
// ─────────────────────────────────────────────────────

struct HourlySalesPoint: Identifiable, Equatable {
    var id: Int { hour }
    let hour: Int
    let revenue: Double
    var hourLabel: String {
        let ampm = hour >= 12 ? "PM" : "AM"
        let h = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour)
        return "\(h) \(ampm)"
    }
}

struct DailySalesPoint: Identifiable, Equatable {
    var id: Int { day }
    let day: Int
    let revenue: Double
    var dayLabel: String { "\(day)" }
}

struct PaymentBreakdownPoint: Identifiable, Equatable {
    var id: String { method }
    let method: String
    let amount: Double
    let count: Int
}

struct ProductSalesPoint: Identifiable, Equatable {
    var id: String { "\(channel)|\(itemType)|\(sourceId)" }
    let name: String
    let category: String
    let channel: String
    let itemType: String
    let sourceId: String
    let quantity: Int
    let unitPrice: Double
    let totalRevenue: Double
    var cogs: Double
    var grossProfit: Double { totalRevenue - cogs }
    var grossMarginPct: Double { totalRevenue > 0 ? grossProfit / totalRevenue * 100 : 0 }
}

struct DeliveryPlatformPoint: Identifiable, Equatable {
    var id: String { brandName }
    let brandName: String
    let orderCount: Int
    let grossRevenue: Double
    let gpFees: Double
    let adFees: Double
    let otherFees: Double
    let netRevenue: Double
    var effectiveMarginPct: Double { grossRevenue > 0 ? netRevenue / grossRevenue * 100 : 0 }
    var totalFees: Double { gpFees + adFees + otherFees }

    var brandColor: Color {
        switch brandName.lowercased() {
        case let s where s.contains("grab"):    return Color.appTeal
        case let s where s.contains("line"):    return Color.appTeal
        case let s where s.contains("shopee"):  return Color.appRose
        case let s where s.contains("panda"):   return Color.appRose
        case let s where s.contains("robin"):   return Color.appAccent
        default:                                return Color.appAccent
        }
    }
}

struct CashierPerformancePoint: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let orderCount: Int
    let revenue: Double
    let itemsSold: Int
    let avgTicket: Double
}

struct StaffLaborPoint: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let hoursWorked: Double
    let overtimeMinutes: Int
    let laborCost: Double
    var overtimeHours: Double { Double(overtimeMinutes) / 60 }
}

struct InventoryAlertPoint: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let currentQty: Double
    let reorderLevel: Double
    let unit: String
    let isOutOfStock: Bool
}

struct InventoryUsagePoint: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let unit: String
    let theoreticalUsed: Double
    let cost: Double
}

struct WastePoint: Identifiable, Equatable {
    var id = UUID()
    let itemName: String
    let quantity: Double
    let unit: String
    let cost: Double
    let date: Date
}

struct CategoryBreakdownPoint: Identifiable, Equatable {
    var id: String { category }
    let category: String
    let revenue: Double
    let quantity: Int
    let sharePct: Double
}

enum MenuSegment: String {
    case star      = "⭐ Star"
    case plowHorse = "🐎 Plow Horse"
    case puzzle    = "❓ Puzzle"
    case dog       = "📉 Dog"

    var color: Color {
        switch self {
        case .star:      return .appTeal
        case .plowHorse: return .appAccent
        case .puzzle:    return .appAccent // Map to appAccent (Royal Blue)
        case .dog:       return .appRose
        }
    }

    var description: String {
        switch self {
        case .star:      return "ขายดี + กำไรสูง"
        case .plowHorse: return "ขายดี + กำไรต่ำ"
        case .puzzle:    return "ขายน้อย + กำไรสูง"
        case .dog:       return "ขายน้อย + กำไรต่ำ"
        }
    }
}

struct MenuMatrixPoint: Identifiable, Equatable {
    var id: String { product.id }
    let product: ProductSalesPoint
    let segment: MenuSegment
}
