// ReportsViewModel.swift
// AlphaPos — Reports Feature Module
//
// Central ViewModel for all report types: Daily Sales, Z-Report,
// Tax/VAT, Menu Profitability, Inventory, and Employee Hours.

import Foundation
import SwiftData
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Report Type Enum
// ─────────────────────────────────────────────────────────────────────────────

enum ReportType: String, CaseIterable, Identifiable {
    case dailySales       = "daily_sales"
    case zReport          = "z_report"
    case taxVAT           = "tax_vat"
    case menuProfitability = "menu_profitability"
    case inventoryStock   = "inventory_stock"
    case employeeHours    = "employee_hours"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dailySales:       return "chart.bar.fill"
        case .zReport:          return "doc.text.fill"
        case .taxVAT:           return "building.columns.fill"
        case .menuProfitability: return "fork.knife"
        case .inventoryStock:   return "archivebox.fill"
        case .employeeHours:    return "clock.fill"
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Period Mode
// ─────────────────────────────────────────────────────────────────────────────

enum ReportPeriod: String, CaseIterable {
    case daily   = "daily"
    case weekly  = "weekly"
    case monthly = "monthly"
    case custom  = "custom"
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Data Points
// ─────────────────────────────────────────────────────────────────────────────

struct ReportsHourlySalesPoint: Identifiable {
    let id = UUID()
    let hour: Int
    let revenue: Double
    let orderCount: Int
}

struct PaymentMethodPoint: Identifiable {
    let id = UUID()
    let method: String
    let amount: Double
    let count: Int
}

struct MenuProfitPoint: Identifiable {
    let id = UUID()
    let menuItemId: String
    let name: String
    let quantitySold: Int
    let revenue: Double
    let cogs: Double
    let grossProfit: Double
    let marginPct: Double
}

struct InventoryAlertItem: Identifiable {
    let id = UUID()
    let itemId: UUID
    let name: String
    let currentQty: Double
    let reorderLevel: Double
    let unit: String
    let costPrice: Double
    let isOutOfStock: Bool
}

struct WasteEntry: Identifiable {
    let id = UUID()
    let itemName: String
    let quantity: Double
    let unit: String
    let cost: Double
    let date: Date
    let notes: String?
}

struct EmployeeHoursEntry: Identifiable {
    let id = UUID()
    let employeeId: UUID
    let name: String
    let employmentType: String
    let totalHours: Double
    let regularHours: Double
    let overtimeHours: Double
    let breakHours: Double
    let payRate: Double
    let estimatedCost: Double
}

struct DailyTaxEntry: Identifiable {
    let id = UUID()
    let date: Date
    let salesIncVAT: Double
    let vatAmount: Double
    let salesExcVAT: Double
    let orderCount: Int
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Reports ViewModel
// ─────────────────────────────────────────────────────────────────────────────

@Observable
final class ReportsViewModel {

    // ── Selection State ──────────────────────────────────────────────────────
    var selectedReport: ReportType = .dailySales
    var periodMode: ReportPeriod = .daily
    var selectedDate: Date = Date()
    var rangeStart: Date = Calendar.current.startOfDay(for: Date())
    var rangeEnd: Date = Date()

    // ── Daily Sales ─────────────────────────────────────────────────────────
    var grossRevenue: Double = 0
    var netRevenue: Double = 0
    var totalOrders: Int = 0
    var averageTicket: Double = 0
    var totalDiscount: Double = 0
    var totalRefunds: Double = 0
    var hourlySales: [ReportsHourlySalesPoint] = []
    var paymentBreakdown: [PaymentMethodPoint] = []

    // ── Z-Report ────────────────────────────────────────────────────────────
    var openingCash: Double = 0
    var totalCashSales: Double = 0
    var totalCashIn: Double = 0
    var totalCashOut: Double = 0
    var expectedCash: Double = 0
    var actualCash: Double = 0
    var variance: Double = 0
    var sessionOpenedAt: Date? = nil
    var sessionClosedAt: Date? = nil
    var cashierName: String = ""

    // ── Tax/VAT ─────────────────────────────────────────────────────────────
    var totalSalesIncVAT: Double = 0
    var totalVATAmount: Double = 0
    var totalSalesExcVAT: Double = 0
    var dailyTaxEntries: [DailyTaxEntry] = []

    // ── Menu Profitability ──────────────────────────────────────────────────
    var menuProfitItems: [MenuProfitPoint] = []
    var sortByColumn: String = "revenue"
    var sortAscending: Bool = false

    // ── Inventory ───────────────────────────────────────────────────────────
    var lowStockItems: [InventoryAlertItem] = []
    var outOfStockItems: [InventoryAlertItem] = []
    var totalStockValue: Double = 0
    var wasteEntries: [WasteEntry] = []
    var totalWasteCost: Double = 0

    // ── Inventory Analytics (advanced report) ───────────────────────────────
    var showInventoryAnalytics: Bool = false   // toggle between classic & analytics view

    // ── Employee Hours ──────────────────────────────────────────────────────
    var employeeHoursEntries: [EmployeeHoursEntry] = []
    var totalLaborHours: Double = 0
    var totalLaborCost: Double = 0
    var totalOvertimeHours: Double = 0

    // ── PDF State ───────────────────────────────────────────────────────────
    var generatedPDFURL: URL? = nil
    var showingShareSheet: Bool = false
    var isGeneratingPDF: Bool = false

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Date Range Helpers
    // ─────────────────────────────────────────────────────────────────────────

    var effectiveStartDate: Date {
        let cal = Calendar.current
        switch periodMode {
        case .daily:
            return cal.startOfDay(for: selectedDate)
        case .weekly:
            let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selectedDate)
            return cal.date(from: comps) ?? cal.startOfDay(for: selectedDate)
        case .monthly:
            let comps = cal.dateComponents([.year, .month], from: selectedDate)
            return cal.date(from: comps) ?? cal.startOfDay(for: selectedDate)
        case .custom:
            return rangeStart
        }
    }

    var effectiveEndDate: Date {
        let cal = Calendar.current
        switch periodMode {
        case .daily:
            return cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: selectedDate)) ?? Date()
        case .weekly:
            return cal.date(byAdding: .day, value: 7, to: effectiveStartDate) ?? Date()
        case .monthly:
            return cal.date(byAdding: .month, value: 1, to: effectiveStartDate) ?? Date()
        case .custom:
            return cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: rangeEnd)) ?? Date()
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Compute Daily Sales
    // ─────────────────────────────────────────────────────────────────────────

    func computeDailySales(orders: [Order], payments: [Payment]) {
        let start = effectiveStartDate
        let end = effectiveEndDate

        let filtered = orders.filter {
            !$0.isDeleted && $0.status == "completed" &&
            $0.createdAt >= start && $0.createdAt < end
        }

        grossRevenue = filtered.reduce(0.0) { $0 + $1.total }
        totalDiscount = filtered.reduce(0.0) { $0 + $1.discount }
        totalRefunds = filtered.flatMap(\.refunds).filter { !$0.isDeleted }.reduce(0.0) { $0 + $1.refundAmount }
        netRevenue = grossRevenue - totalRefunds
        totalOrders = filtered.count
        averageTicket = totalOrders > 0 ? grossRevenue / Double(totalOrders) : 0

        // Hourly breakdown
        let cal = Calendar.current
        var hourlyMap: [Int: (revenue: Double, count: Int)] = [:]
        for order in filtered {
            let hour = cal.component(.hour, from: order.createdAt)
            let existing = hourlyMap[hour] ?? (0, 0)
            hourlyMap[hour] = (existing.revenue + order.total, existing.count + 1)
        }
        hourlySales = (0..<24).map { hour in
            let data = hourlyMap[hour] ?? (0, 0)
            return ReportsHourlySalesPoint(hour: hour, revenue: data.revenue, orderCount: data.count)
        }

        // Payment method breakdown
        let relevantPayments = payments.filter {
            !$0.isDeleted && $0.status == "completed" &&
            $0.paidAt >= start && $0.paidAt < end
        }
        var methodMap: [String: (amount: Double, count: Int)] = [:]
        for payment in relevantPayments {
            let normalizedMethod = payment.paymentMethod.lowercased().replacingOccurrences(of: " ", with: "_")
            let existing = methodMap[normalizedMethod] ?? (0, 0)
            methodMap[normalizedMethod] = (existing.amount + payment.amount, existing.count + 1)
        }
        paymentBreakdown = methodMap.map { key, value in
            PaymentMethodPoint(method: key, amount: value.amount, count: value.count)
        }.sorted { $0.amount > $1.amount }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Compute Z-Report
    // ─────────────────────────────────────────────────────────────────────────

    func computeZReport(sessions: [RegisterSession], movements: [CashMovement], orders: [Order], payments: [Payment]) {
        let start = effectiveStartDate
        let end = effectiveEndDate

        // Find the most recent session in the period
        let relevantSessions = sessions.filter {
            !$0.isDeleted && (
                ($0.openedAt >= start && $0.openedAt < end) ||
                ($0.closedAt != nil && $0.closedAt! >= start && $0.closedAt! < end)
            )
        }.sorted { $0.openedAt > $1.openedAt }

        guard let session = relevantSessions.first else {
            resetZReport()
            return
        }

        openingCash = session.openingCash
        actualCash = session.actualClosingCash
        sessionOpenedAt = session.openedAt
        sessionClosedAt = session.closedAt

        // Cash movements for this session
        let sessionMovements = movements.filter {
            !$0.isDeleted && $0.registerSession?.id == session.id
        }
        totalCashIn = sessionMovements.filter { $0.movementType == "cash_in" || $0.movementType == "paid_in" }.reduce(0.0) { $0 + $1.amount }
        totalCashOut = sessionMovements.filter { $0.movementType == "cash_out" || $0.movementType == "paid_out" }.reduce(0.0) { $0 + $1.amount }

        // Cash sales in the period
        let sessionEnd = session.closedAt ?? Date()
        let periodPayments = payments.filter {
            !$0.isDeleted && $0.status == "completed" &&
            $0.paymentMethod.lowercased().replacingOccurrences(of: " ", with: "_") == "cash" &&
            $0.paidAt >= session.openedAt && $0.paidAt < sessionEnd
        }
        totalCashSales = periodPayments.reduce(0.0) { $0 + $1.amount }

        expectedCash = openingCash + totalCashSales + totalCashIn - totalCashOut
        variance = actualCash - expectedCash
    }

    private func resetZReport() {
        openingCash = 0; totalCashSales = 0; totalCashIn = 0; totalCashOut = 0
        expectedCash = 0; actualCash = 0; variance = 0
        sessionOpenedAt = nil; sessionClosedAt = nil
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Compute Tax/VAT
    // ─────────────────────────────────────────────────────────────────────────

    func computeTaxReport(orders: [Order], taxLines: [OrderTaxLine]) {
        let start = effectiveStartDate
        let end = effectiveEndDate

        let filteredOrders = orders.filter {
            !$0.isDeleted && $0.status == "completed" &&
            $0.createdAt >= start && $0.createdAt < end
        }

        totalSalesIncVAT = filteredOrders.reduce(0.0) { $0 + $1.total }
        totalVATAmount = filteredOrders.reduce(0.0) { $0 + $1.tax }
        totalSalesExcVAT = totalSalesIncVAT - totalVATAmount

        // Daily breakdown
        let cal = Calendar.current
        var dailyMap: [Date: (incVAT: Double, vat: Double, excVAT: Double, count: Int)] = [:]
        for order in filteredOrders {
            let dayStart = cal.startOfDay(for: order.createdAt)
            let existing = dailyMap[dayStart] ?? (0, 0, 0, 0)
            dailyMap[dayStart] = (
                existing.incVAT + order.total,
                existing.vat + order.tax,
                existing.excVAT + (order.total - order.tax),
                existing.count + 1
            )
        }
        dailyTaxEntries = dailyMap.map { date, data in
            DailyTaxEntry(date: date, salesIncVAT: data.incVAT, vatAmount: data.vat, salesExcVAT: data.excVAT, orderCount: data.count)
        }.sorted { $0.date < $1.date }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Compute Menu Profitability
    // ─────────────────────────────────────────────────────────────────────────

    func computeMenuProfitability(orders: [Order], menuItems: [MenuItem]) {
        let start = effectiveStartDate
        let end = effectiveEndDate

        let filteredOrders = orders.filter {
            !$0.isDeleted && $0.status == "completed" &&
            $0.createdAt >= start && $0.createdAt < end
        }

        // Aggregate sales per menu item
        var itemStats: [String: (qty: Int, revenue: Double)] = [:]
        for order in filteredOrders {
            for item in order.items where !item.isDeleted && item.status != "cancelled" {
                guard let menuItem = item.menuItem else { continue }
                let existing = itemStats[menuItem.id] ?? (0, 0)
                itemStats[menuItem.id] = (existing.qty + item.quantity, existing.revenue + item.subtotal)
            }
        }

        // Calculate COGS from recipes
        menuProfitItems = menuItems.compactMap { menuItem in
            guard let stats = itemStats[menuItem.id] else { return nil }
            let cogs = menuItem.recipes.reduce(0.0) { acc, recipe in
                let ingredientCost = recipe.inventoryItem?.costPrice ?? 0
                return acc + (recipe.quantityRequired * ingredientCost * Double(stats.qty))
            }
            let grossProfit = stats.revenue - cogs
            let marginPct = stats.revenue > 0 ? (grossProfit / stats.revenue) * 100 : 0

            return MenuProfitPoint(
                menuItemId: menuItem.id,
                name: menuItem.name,
                quantitySold: stats.qty,
                revenue: stats.revenue,
                cogs: cogs,
                grossProfit: grossProfit,
                marginPct: marginPct
            )
        }

        applySorting()
    }

    func applySorting() {
        switch sortByColumn {
        case "name":
            menuProfitItems.sort { sortAscending ? $0.name < $1.name : $0.name > $1.name }
        case "quantity":
            menuProfitItems.sort { sortAscending ? $0.quantitySold < $1.quantitySold : $0.quantitySold > $1.quantitySold }
        case "revenue":
            menuProfitItems.sort { sortAscending ? $0.revenue < $1.revenue : $0.revenue > $1.revenue }
        case "cogs":
            menuProfitItems.sort { sortAscending ? $0.cogs < $1.cogs : $0.cogs > $1.cogs }
        case "profit":
            menuProfitItems.sort { sortAscending ? $0.grossProfit < $1.grossProfit : $0.grossProfit > $1.grossProfit }
        case "margin":
            menuProfitItems.sort { sortAscending ? $0.marginPct < $1.marginPct : $0.marginPct > $1.marginPct }
        default:
            menuProfitItems.sort { $0.revenue > $1.revenue }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Compute Inventory Report
    // ─────────────────────────────────────────────────────────────────────────

    func computeInventoryReport(items: [InventoryItem], transactions: [InventoryTransaction]) {
        let start = effectiveStartDate
        let end = effectiveEndDate

        let activeItems = items.filter { !$0.isDeleted }

        totalStockValue = activeItems.reduce(0.0) { $0 + ($1.currentQuantity * $1.costPrice) }

        lowStockItems = activeItems.filter {
            $0.currentQuantity <= $0.reorderLevel && $0.currentQuantity > 0
        }.map {
            InventoryAlertItem(itemId: $0.id, name: $0.name, currentQty: $0.currentQuantity, reorderLevel: $0.reorderLevel, unit: $0.unit, costPrice: $0.costPrice, isOutOfStock: false)
        }.sorted { $0.currentQty < $1.currentQty }

        outOfStockItems = activeItems.filter {
            $0.currentQuantity <= 0
        }.map {
            InventoryAlertItem(itemId: $0.id, name: $0.name, currentQty: $0.currentQuantity, reorderLevel: $0.reorderLevel, unit: $0.unit, costPrice: $0.costPrice, isOutOfStock: true)
        }

        // Waste transactions in period
        let wasteTransactions = transactions.filter {
            !$0.isDeleted && $0.transactionType == InventoryMovementType.waste.rawValue &&
            $0.updatedAt >= start && $0.updatedAt < end
        }
        wasteEntries = wasteTransactions.compactMap { tx in
            guard let item = tx.item else { return nil }
            let cost = abs(tx.quantity) * (tx.costPrice ?? item.costPrice)
            return WasteEntry(itemName: item.name, quantity: abs(tx.quantity), unit: item.unit, cost: cost, date: tx.updatedAt, notes: tx.notes)
        }.sorted { $0.date > $1.date }

        totalWasteCost = wasteEntries.reduce(0.0) { $0 + $1.cost }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Compute Employee Hours
    // ─────────────────────────────────────────────────────────────────────────

    func computeEmployeeHours(employees: [Employee], timecards: [Timecard]) {
        let start = effectiveStartDate
        let end = effectiveEndDate

        let activeEmployees = employees.filter { !$0.isDeleted && $0.resignedAt == nil }

        employeeHoursEntries = activeEmployees.compactMap { emp in
            let empTimecards = timecards.filter {
                !$0.isDeleted && $0.employee?.id == emp.id &&
                $0.status == "approved" &&
                $0.clockIn >= start && $0.clockIn < end
            }

            guard !empTimecards.isEmpty else { return nil }

            var totalMins: Double = 0
            var breakMins: Double = 0
            var otMins: Double = 0

            for tc in empTimecards {
                let clockOut = tc.clockOut ?? Date()
                let worked = clockOut.timeIntervalSince(tc.clockIn) / 60.0
                totalMins += worked
                breakMins += Double(tc.breakDurationMinutes)
                otMins += Double(tc.overtimeMinutes)
            }

            let totalHours = (totalMins - breakMins) / 60.0
            let regularHours = max(0, totalHours - (otMins / 60.0))
            let overtimeHours = otMins / 60.0
            let breakHours = breakMins / 60.0

            let estimatedCost: Double
            switch emp.employmentType {
            case "hourly":
                estimatedCost = (regularHours * emp.payRate) + (overtimeHours * emp.payRate * 1.5)
            case "daily":
                let days = Double(empTimecards.count)
                estimatedCost = days * emp.payRate
            default: // monthly
                estimatedCost = emp.payRate
            }

            return EmployeeHoursEntry(
                employeeId: emp.id,
                name: "\(emp.firstName) \(emp.lastName)",
                employmentType: emp.employmentType,
                totalHours: totalHours,
                regularHours: regularHours,
                overtimeHours: overtimeHours,
                breakHours: breakHours,
                payRate: emp.payRate,
                estimatedCost: estimatedCost
            )
        }.sorted { $0.totalHours > $1.totalHours }

        totalLaborHours = employeeHoursEntries.reduce(0.0) { $0 + $1.totalHours }
        totalLaborCost = employeeHoursEntries.reduce(0.0) { $0 + $1.estimatedCost }
        totalOvertimeHours = employeeHoursEntries.reduce(0.0) { $0 + $1.overtimeHours }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - PDF Generation
    // ─────────────────────────────────────────────────────────────────────────

    @MainActor
    func generatePDF(title: String, content: some View) {
        isGeneratingPDF = true
        let renderer = ImageRenderer(content: content.frame(width: 595)) // A4 width in points
        renderer.scale = 2.0

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(title)_\(formattedDate).pdf")

        renderer.render { size, renderer in
            var box = CGRect(origin: .zero, size: CGSize(width: size.width, height: size.height))
            guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            context.beginPage(mediaBox: &box)
            renderer(context)
            context.endPage()
            context.closePDF()
        }

        generatedPDFURL = url
        isGeneratingPDF = false
        showingShareSheet = true
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Formatting Helpers
    // ─────────────────────────────────────────────────────────────────────────

    var formattedDate: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: selectedDate)
    }

    var periodDescription: String {
        let fmt = DateFormatter()
        switch periodMode {
        case .daily:
            fmt.dateStyle = .medium
            return fmt.string(from: selectedDate)
        case .weekly:
            fmt.dateFormat = "d MMM"
            let start = effectiveStartDate
            let end = Calendar.current.date(byAdding: .day, value: 6, to: start) ?? start
            return "\(fmt.string(from: start)) - \(fmt.string(from: end))"
        case .monthly:
            fmt.dateFormat = "MMMM yyyy"
            return fmt.string(from: selectedDate)
        case .custom:
            fmt.dateStyle = .short
            return "\(fmt.string(from: rangeStart)) - \(fmt.string(from: rangeEnd))"
        }
    }

    static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "THB"
        f.currencySymbol = "฿"
        f.maximumFractionDigits = 2
        return f
    }()

    func formatCurrency(_ value: Double) -> String {
        Self.currencyFormatter.string(from: NSNumber(value: value)) ?? "฿\(String(format: "%.2f", value))"
    }
}
