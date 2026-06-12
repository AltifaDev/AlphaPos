import Foundation
import SwiftData
import SwiftUI

@Observable
final class SalesViewModel {
    enum SummaryMode {
        case daily
        case monthly
    }

    // UI state variables
    var summaryMode: SummaryMode = .daily
    var selectedDate: Date = Date()
    var selectedMonth: Int = Calendar.current.component(.month, from: Date())
    var selectedYear: Int = Calendar.current.component(.year, from: Date())

    // ─────────────────────────────────────────────────
    // MARK: KPIs — Revenue & Orders
    // ─────────────────────────────────────────────────
    var grossRevenue: Double = 0.0
    var netRevenue: Double = 0.0
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
    var grossProfit: Double = 0.0          // grossRevenue − totalCOGS
    var grossMarginPct: Double = 0.0       // grossProfit / grossRevenue × 100
    var totalLaborCost: Double = 0.0       // จาก Timecard + Employee.payRate
    var totalLaborHours: Double = 0.0
    var laborCostPct: Double = 0.0         // laborCost / grossRevenue × 100
    var revenuePerLaborHour: Double = 0.0
    var totalWasteCost: Double = 0.0       // InventoryTransaction type="waste" × costPrice
    var estimatedNetProfit: Double = 0.0   // grossProfit − laborCost − wasteCost
    var netProfitMarginPct: Double = 0.0

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
    var netDeliveryRevenue: Double = 0.0

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

    init() {}

    // ─────────────────────────────────────────────────
    // MARK: - Main Entry: updateAnalytics
    // ─────────────────────────────────────────────────

    /// Master analytics update — calls all sub-analyzers
    func updateAnalytics(
        orders: [Order],
        inventoryItems: [InventoryItem] = [],
        employees: [Employee] = [],
        timecards: [Timecard] = []
    ) {
        let calendar = Calendar.current

        // 1. Filter completed orders for the selected period
        let filtered = orders.filter { order in
            guard !order.isDeleted, !order.payments.isEmpty else { return false }
            switch summaryMode {
            case .daily:
                return calendar.isDate(order.createdAt, inSameDayAs: selectedDate)
            case .monthly:
                let m = calendar.component(.month, from: order.createdAt)
                let y = calendar.component(.year, from: order.createdAt)
                return m == selectedMonth && y == selectedYear
            }
        }

        self.historicalOrders = filtered.sorted(by: { $0.createdAt > $1.createdAt })

        // 2. Cancelled orders (same period, no payment)
        let cancelledInPeriod = orders.filter { order in
            guard !order.isDeleted, order.status == "cancelled" else { return false }
            switch summaryMode {
            case .daily:
                return calendar.isDate(order.createdAt, inSameDayAs: selectedDate)
            case .monthly:
                let m = calendar.component(.month, from: order.createdAt)
                let y = calendar.component(.year, from: order.createdAt)
                return m == selectedMonth && y == selectedYear
            }
        }
        self.cancelledOrders = cancelledInPeriod.count
        self.cancelledItemsCount = cancelledInPeriod.flatMap { $0.items }.reduce(0) { $0 + $1.quantity }

        // Run sub-analyzers
        computeRevenueKPIs(filtered: filtered)
        computeOrderTypeMix(filtered: filtered)
        computeTrends(filtered: filtered, calendar: calendar)
        computePaymentBreakdown(filtered: filtered)
        computeProductSales(filtered: filtered)
        computeDeliveryAnalytics(filtered: filtered)
        computeCategoryBreakdown()
        computeMenuEngineering()
        computeCashierPerformance(filtered: filtered)

        if !inventoryItems.isEmpty {
            computeInventoryAnalytics(inventoryItems: inventoryItems, filtered: filtered)
            computeProfitability(filtered: filtered, inventoryItems: inventoryItems)
        }

        if !timecards.isEmpty && !employees.isEmpty {
            computeLaborAnalytics(timecards: timecards, employees: employees, calendar: calendar)
        }
    }

    // ─────────────────────────────────────────────────
    // MARK: Revenue KPIs
    // ─────────────────────────────────────────────────
    private func computeRevenueKPIs(filtered: [Order]) {
        var gross = 0.0, tax = 0.0, svc = 0.0, disc = 0.0, items = 0, refunds = 0.0

        for order in filtered {
            gross += order.total
            tax   += order.tax
            svc   += order.serviceCharge
            disc  += order.discount

            for item in order.items where item.status != "cancelled" {
                items += item.quantity
            }
            // Refunded payments
            for payment in order.payments where payment.status == "refunded" {
                refunds += payment.amount
            }
        }

        self.grossRevenue      = gross
        self.taxCollected      = tax
        self.serviceChargeCollected = svc
        self.discountGiven     = disc
        self.netRevenue        = gross - tax - svc
        self.totalOrders       = filtered.count
        self.averageTicketValue = filtered.isEmpty ? 0 : gross / Double(filtered.count)
        self.totalItemsSold    = items
        self.refundedAmount    = refunds

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
            if summaryMode == .daily {
                let h = calendar.component(.hour, from: order.createdAt)
                hourlyMap[h, default: 0] += order.total
            } else {
                let d = calendar.component(.day, from: order.createdAt)
                dailyMap[d, default: 0] += order.total
            }
        }

        if summaryMode == .daily {
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
            for payment in order.payments where payment.status != "refunded" {
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
            case "true_money":     name = "TrueMoney Wallet"
            default:               name = key.capitalized
            }
            return PaymentBreakdownPoint(method: name, amount: val.amount, count: val.count)
        }.sorted(by: { $0.amount > $1.amount })
    }

    // ─────────────────────────────────────────────────
    // MARK: Product Sales + Modifier Revenue
    // ─────────────────────────────────────────────────
    private func computeProductSales(filtered: [Order]) {
        var productMap: [String: ProductSalesPoint] = [:]
        var modRev = 0.0

        for order in filtered {
            for item in order.items where item.status != "cancelled" {
                let itemId   = item.menuItem?.id ?? item.id.uuidString
                let itemName = item.menuItem?.name ?? "Unknown Dish"
                let category = item.menuItem?.category?.name ?? "Other"

                if let ex = productMap[itemId] {
                    productMap[itemId] = ProductSalesPoint(
                        name: itemName, category: category,
                        quantity: ex.quantity + item.quantity,
                        unitPrice: item.unitPrice,
                        totalRevenue: ex.totalRevenue + item.subtotal,
                        cogs: ex.cogs  // will be filled in profitability pass
                    )
                } else {
                    productMap[itemId] = ProductSalesPoint(
                        name: itemName, category: category,
                        quantity: item.quantity,
                        unitPrice: item.unitPrice,
                        totalRevenue: item.subtotal,
                        cogs: 0
                    )
                }
                // Modifier add-on revenue
                for mod in item.modifiers {
                    modRev += mod.price * Double(item.quantity)
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
        guard !productSales.isEmpty else {
            self.menuEngineeringMatrix = []
            self.topMarginItems = []
            return
        }

        let avgQty    = Double(productSales.map(\.quantity).reduce(0, +)) / Double(productSales.count)
        let avgMargin = productSales.isEmpty ? 0 : productSales.map(\.grossMarginPct).reduce(0, +) / Double(productSales.count)

        self.menuEngineeringMatrix = productSales.map { prod in
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

        self.topMarginItems = productSales
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
            let brand = order.deliveryBrand?.isEmpty == false ? order.deliveryBrand! : "Other"
            let gpFee = order.total * (order.deliveryGP / 100.0)
            let adFee = order.deliveryAdFeeIsPct
                ? order.total * (order.deliveryAdFee / 100.0)
                : order.deliveryAdFee
            let otherFee = order.deliveryOtherFee
            let netRev   = order.total - gpFee - adFee - otherFee

            if let ex = platformMap[brand] {
                platformMap[brand] = DeliveryPlatformPoint(
                    brandName:     brand,
                    orderCount:    ex.orderCount + 1,
                    grossRevenue:  ex.grossRevenue + order.total,
                    gpFees:        ex.gpFees + gpFee,
                    adFees:        ex.adFees + adFee,
                    otherFees:     ex.otherFees + otherFee,
                    netRevenue:    ex.netRevenue + netRev
                )
            } else {
                platformMap[brand] = DeliveryPlatformPoint(
                    brandName:    brand,
                    orderCount:   1,
                    grossRevenue: order.total,
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
    // MARK: Profitability — COGS from Recipe
    // ─────────────────────────────────────────────────
    private func computeProfitability(filtered: [Order], inventoryItems: [InventoryItem]) {
        // Build ingredient cost lookup: menuItemId → COGS per unit sold
        var cogsPerMenuItem: [String: Double] = [:]
        for inv in inventoryItems {
            for recipe in inv.recipeUsages where !recipe.isDeleted {
                guard let menuId = recipe.menuItem?.id else { continue }
                let ingredientCost = recipe.quantityRequired * inv.costPrice
                cogsPerMenuItem[menuId, default: 0] += ingredientCost
            }
        }

        // Compute COGS per product (match by menuItem.id from order items)
        var productCogsMap: [String: Double] = [:]  // productSalesPoint.id (menuItem.id or name) → total COGS
        for order in filtered {
            for item in order.items where item.status != "cancelled" {
                guard let menuItem = item.menuItem else { continue }
                let unitCOGS = cogsPerMenuItem[menuItem.id] ?? 0
                productCogsMap[menuItem.id, default: 0] += unitCOGS * Double(item.quantity)
            }
        }

        // Update productSales with COGS
        let updatedProducts: [ProductSalesPoint] = productSales.map { prod in
            ProductSalesPoint(
                name: prod.name, category: prod.category,
                quantity: prod.quantity, unitPrice: prod.unitPrice,
                totalRevenue: prod.totalRevenue,
                cogs: productCogsMap[prod.id] ?? 0
            )
        }

        // Direct COGS total from order items × recipes
        var directCOGS = 0.0
        for order in filtered {
            for item in order.items where item.status != "cancelled" {
                guard let menuItem = item.menuItem else { continue }
                let unitCOGS = cogsPerMenuItem[menuItem.id] ?? 0
                directCOGS += unitCOGS * Double(item.quantity)
            }
        }

        self.totalCOGS       = directCOGS
        self.grossProfit      = grossRevenue - directCOGS
        self.grossMarginPct   = grossRevenue > 0 ? grossProfit / grossRevenue * 100 : 0
        self.productSales     = updatedProducts

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
            case .daily:
                return calendar.isDate(clockIn, inSameDayAs: selectedDate)
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
            let workedSecs = clockOut.timeIntervalSince(tc.clockIn)
            let breakSecs  = Double(tc.breakDurationMinutes) * 60
            let netHours   = max(0, (workedSecs - breakSecs) / 3600)

            let regularHours = max(0, netHours - Double(tc.overtimeMinutes) / 60)
            let otHours      = Double(tc.overtimeMinutes) / 60

            let regularCost = regularHours * emp.payRate
            let otCost       = otHours * emp.payRate * 1.5
            let totalEmpCost = regularCost + otCost

            let cur = empMap[emp.id] ?? (0, 0, 0, "\(emp.firstName) \(emp.lastName)")
            empMap[emp.id] = (cur.hours + netHours, cur.otMins + tc.overtimeMinutes, cur.cost + totalEmpCost, cur.name)

            totalHours += netHours
            totalCost  += totalEmpCost
        }

        self.totalLaborHours  = totalHours
        self.totalLaborCost   = totalCost
        self.laborCostPct     = grossRevenue > 0 ? totalCost / grossRevenue * 100 : 0
        self.revenuePerLaborHour = totalHours > 0 ? grossRevenue / totalHours : 0

        self.staffLaborBreakdown = empMap.map { _, val in
            StaffLaborPoint(name: val.name, hoursWorked: val.hours, overtimeMinutes: val.otMins, laborCost: val.cost)
        }.sorted(by: { $0.laborCost > $1.laborCost })

        recomputeNetProfit()
    }

    // ─────────────────────────────────────────────────
    // MARK: Inventory Analytics
    // ─────────────────────────────────────────────────
    private func computeInventoryAnalytics(inventoryItems: [InventoryItem], filtered: [Order]) {
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

        // Waste summary from InventoryTransactions
        let allWaste = activeItems.flatMap { $0.transactions }.filter { $0.transactionType == "waste" && !$0.isDeleted }
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
                date: tx.updatedAt
            )
        }.sorted(by: { $0.date > $1.date })

        // Theoretical usage (from sold items × recipe)
        var usageMap: [String: (name: String, unit: String, theoretical: Double, cost: Double)] = [:]
        for order in filtered {
            for item in order.items where item.status != "cancelled" {
                guard let menuItem = item.menuItem else { continue }
                for recipe in menuItem.recipes where !recipe.isDeleted {
                    guard let inv = recipe.inventoryItem else { continue }
                    let used = recipe.quantityRequired * Double(item.quantity)
                    let key  = inv.id.uuidString
                    let cur  = usageMap[key] ?? (inv.name, inv.unit, 0, 0)
                    usageMap[key] = (cur.name, cur.unit, cur.theoretical + used, cur.cost + used * inv.costPrice)
                }
            }
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
        self.estimatedNetProfit  = grossProfit - totalLaborCost - totalWasteCost
        self.netProfitMarginPct  = grossRevenue > 0 ? estimatedNetProfit / grossRevenue * 100 : 0
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
    var id: String { name }
    let name: String
    let category: String
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
