// ReportsViewModel.swift
// AlphaPos — Reports Feature Module
//
// Central ViewModel for all report types: Daily Sales, Z-Report,
// Tax/VAT, Menu Profitability, Inventory, and Employee Hours.

import Foundation
import SwiftData
import SwiftUI

enum ReportItemScope: String, CaseIterable, Identifiable {
    case main
    case addOns
    case allUnits

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .main: return "เมนูหลัก (Main items)"
        case .addOns: return "สินค้าเพิ่มเติม (Add-ons)"
        case .allUnits: return "ทุกหน่วย (All units)"
        }
    }

    var quantityLabel: String {
        switch self {
        case .main: return "จำนวนเมนูหลักที่ขาย"
        case .addOns: return "จำนวนสินค้าเพิ่มเติมที่ขาย"
        case .allUnits: return "จำนวนทุกหน่วยที่ขาย"
        }
    }

    func includes(_ item: OrderItem) -> Bool {
        switch self {
        case .main: return item.resolvedLineType == .main
        case .addOns: return item.resolvedLineType == .addOn
        case .allUnits: return true
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Report Type Enum
// ─────────────────────────────────────────────────────────────────────────────

enum ReportType: String, CaseIterable, Identifiable {
    case dailySales       = "daily_sales"
    case productSales     = "product_sales"
    case zReport          = "z_report"
    case taxVAT           = "tax_vat"
    case menuProfitability = "menu_profitability"
    case inventoryStock   = "inventory_stock"
    case purchasing       = "purchasing"
    case refundsVoids     = "refunds_voids"
    case customerAnalytics = "customer_analytics"
    case branchComparison = "branch_comparison"
    case salesForecast    = "sales_forecast"
    case employeeHours    = "employee_hours"
    case monthlyComparison = "monthly_comparison"  // L-2
    case promotionPerformance = "promotion_performance"

    var id: String { rawValue }

    enum Category: String, CaseIterable {
        case fiscalSales
        case costInventory
        case auditManagement

        func title(isThai: Bool) -> String {
            switch self {
            case .fiscalSales:     return isThai ? "ยอดขาย ปิดกะ และภาษี" : "Sales, Shift & Tax"
            case .costInventory:   return isThai ? "ควบคุมต้นทุนและคลัง" : "Cost & Inventory"
            case .auditManagement: return isThai ? "ตรวจสอบและบริหารงาน" : "Audit & Management"
            }
        }
    }

    var category: Category {
        switch self {
        case .dailySales, .productSales, .zReport, .taxVAT, .monthlyComparison:
            return .fiscalSales
        case .menuProfitability, .inventoryStock, .purchasing, .promotionPerformance:
            return .costInventory
        case .refundsVoids, .customerAnalytics, .branchComparison, .salesForecast, .employeeHours:
            return .auditManagement
        }
    }

    var icon: String {
        switch self {
        case .dailySales:       return "chart.bar.fill"
        case .productSales:     return "list.bullet.rectangle.fill"
        case .zReport:          return "doc.text.fill"
        case .taxVAT:           return "building.columns.fill"
        case .menuProfitability: return "fork.knife"
        case .inventoryStock:   return "archivebox.fill"
        case .purchasing:       return "shippingbox.fill"
        case .refundsVoids:     return "arrow.uturn.backward.circle.fill"
        case .customerAnalytics: return "person.2.fill"
        case .branchComparison: return "building.2.fill"
        case .salesForecast:    return "chart.line.uptrend.xyaxis"
        case .employeeHours:    return "clock.fill"
        case .monthlyComparison: return "chart.bar.xaxis.ascending"
        case .promotionPerformance: return "tag.fill"
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

enum ReportDateBasis: String, CaseIterable {
    case registerShift
    case businessDay
    case calendarDay
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

struct ReportTenderPoint: Identifiable {
    var id: String { method + (isDelivery ? "|delivery" : "|store") }
    let method: String
    let received: Double
    let refunded: Double
    let count: Int
    let isDelivery: Bool
    var net: Double { received - refunded }
}

struct MenuProfitPoint: Identifiable {
    let id = UUID()
    let menuItemId: String
    let name: String
    let channel: String
    let itemType: String
    let quantitySold: Int
    let revenue: Double
    let cogs: Double
    let grossProfit: Double
    let marginPct: Double
}

struct ReportProductSalesPoint: Identifiable {
    let id: String
    let sku: String
    let name: String
    let category: String
    let channel: String
    let itemType: String
    let quantitySold: Int
    let grossSales: Double
    let discount: Double
    let refunds: Double
    let netSales: Double
    let averageUnitPrice: Double
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

// ── Inventory usage & planning analysis ──────────────────────────────────────

/// Per-item consumption vs waste in the selected period.
struct ItemUsagePoint: Identifiable {
    let id = UUID()
    let itemName: String
    let unit: String
    let usedQty: Double
    let usedCost: Double
    let wasteQty: Double
    let wasteCost: Double
    /// Waste as % of total outflow (used + wasted) — food-cost control metric.
    let wastePct: Double
}

/// Stock movement totals grouped by movement type (receive, sell, waste, …).
struct MovementTypePoint: Identifiable {
    let id = UUID()
    let type: String
    let count: Int
    let quantity: Double
    let value: Double
}

/// Waste grouped by structured reason code (HACCP-style cause analysis).
struct WasteReasonPoint: Identifiable {
    let id = UUID()
    let reason: String
    let count: Int
    let cost: Double
}

/// Daily usage vs waste cost — trend line for the period.
struct InventoryDailyFlowPoint: Identifiable {
    let id = UUID()
    let date: Date
    let usageCost: Double
    let wasteCost: Double
}

/// Forward-looking stock coverage: how many days until an item runs out at
/// the current consumption rate. Drives the reorder plan.
struct StockCoveragePoint: Identifiable {
    let id = UUID()
    let itemName: String
    let unit: String
    let currentQty: Double
    let avgDailyUsage: Double
    let daysRemaining: Double
}

// ── Refund / Void audit (loss prevention & exception reporting) ──────────────

struct RefundReasonPoint: Identifiable {
    let id = UUID()
    let reason: String
    let count: Int
    let amount: Double
}

struct RefundMethodPoint: Identifiable {
    let id = UUID()
    let method: String
    let count: Int
    let amount: Double
}

struct EmployeeRefundPoint: Identifiable {
    let id = UUID()
    let employeeName: String
    let count: Int
    let amount: Double
}

struct RefundLogEntry: Identifiable {
    let id: UUID
    let orderNumber: String
    let amount: Double
    let method: String
    let reason: String
    let refundedBy: String
    let approvedBy: String?
    let status: String
    let date: Date
}

struct VoidLogEntry: Identifiable {
    let id: UUID
    let orderNumber: String
    let amount: Double
    let itemCount: Int
    let date: Date
}

// ── Customer analytics (CRM) ─────────────────────────────────────────────────

struct CustomerTierPoint: Identifiable {
    let id = UUID()
    let tier: String
    let customerCount: Int
    let spend: Double
}

struct TopCustomerPoint: Identifiable {
    let id: UUID
    let name: String
    let tier: String
    let orderCount: Int
    let spend: Double
    let loyaltyPoints: Int
    let lastVisit: Date?
}

// ── Branch comparison ────────────────────────────────────────────────────────

struct BranchSalesPoint: Identifiable {
    let id = UUID()
    let branchName: String
    let orderCount: Int
    let revenue: Double
    let avgTicket: Double
    let guestCount: Int
    let sharePct: Double
}

// ── Sales forecast ───────────────────────────────────────────────────────────

struct ForecastDayPoint: Identifiable {
    let id = UUID()
    let date: Date
    let revenue: Double
    let isForecast: Bool
}

// ── Purchasing / Procurement (spend analysis) ────────────────────────────────

struct SupplierSpendPoint: Identifiable {
    let id = UUID()
    let supplierName: String
    let poCount: Int
    let totalSpend: Double
    let receivedSpend: Double
    let outstandingSpend: Double
    let sharePct: Double
}

struct PurchasedItemPoint: Identifiable {
    let id = UUID()
    let itemName: String
    let unit: String
    let quantityOrdered: Double
    let quantityReceived: Double
    let totalCost: Double
    let avgUnitCost: Double
}

struct POStatusPoint: Identifiable {
    let id = UUID()
    let status: String
    let count: Int
    let value: Double
}

struct PORecentEntry: Identifiable {
    let id: UUID
    let poNumber: String
    let supplierName: String
    let status: String
    let orderDate: Date
    let value: Double
    let itemCount: Int
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

struct DailySalesDeliveryOrderItem: Identifiable, Equatable {
    let id: UUID
    let brandName: String
    let orderNumber: String
    let platformOrderNumber: String?
    let netSales: Double
    let refunds: Double
}

struct DailySalesDeliveryPlatformItem: Identifiable, Equatable {
    var id: String { brandName }
    let brandName: String
    let ordersCount: Int
    let grossRevenue: Double
    let discount: Double
    let netSales: Double
    let platformFees: Double
    let refunds: Double
    let netReceivables: Double
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Reports ViewModel
// ─────────────────────────────────────────────────────────────────────────────

@Observable
final class ReportsViewModel {
    var modelContext: ModelContext?
    /// Canonical recognized-sale identities for the selected reporting scope.
    /// When populated, every order-based report follows the same FinancialEvent
    /// boundary as Daily Sales, Dashboard, and P&L.
    private var scopedRecognizedOrderIds: Set<UUID>?

    // ── Selection State ──────────────────────────────────────────────────────
    var selectedReport: ReportType = .dailySales
    var periodMode: ReportPeriod = .daily
    var dateBasis: ReportDateBasis = .registerShift
    var businessDayCutoffHour: Int = 4
    var businessTimeZoneID: String = "Asia/Bangkok"
    var selectedDate: Date = Date()
    var selectedRegisterSessionId: UUID?
    var selectedShiftInterval: DateInterval?
    var rangeStart: Date = Calendar.current.startOfDay(for: Date())
    var rangeEnd: Date = Date()

    // ── Daily Sales (international tax-inclusive bridge) ────────────────────
    /// Gross sales before discounts: Σ(ticket total + discount).
    var grossRevenue: Double = 0
    /// Net sales including VAT (ticket totals): Gross − Discounts.
    var netSalesIncVAT: Double = 0
    /// Net revenue after refunds: Net Sales − Refunds.
    var netRevenue: Double = 0
    var totalOrders: Int = 0
    var averageTicket: Double = 0
    var totalDiscount: Double = 0
    var totalRefunds: Double = 0
    var merchandiseSubtotal: Double = 0
    var serviceChargeTotal: Double = 0
    var vatCollected: Double = 0
    /// Output VAT reversed by completed refunds in the selected accounting period.
    var refundVAT: Double = 0
    /// P&L revenue basis: net sales after refunds, excluding output VAT.
    var accountingRevenueExVAT: Double = 0
    var netSalesExVAT: Double = 0
    var tipsTotal: Double = 0
    var voidOrderCount: Int = 0
    var voidAmount: Double = 0
    var paymentsCollected: Double = 0
    /// Payments collected − net sales (tips excluded from both sides when tipAmount is separate).
    var salesTenderVariance: Double = 0
    var hourlySales: [ReportsHourlySalesPoint] = (0..<24).map { ReportsHourlySalesPoint(hour: $0, revenue: 0, orderCount: 0) }
    var paymentBreakdown: [PaymentMethodPoint] = []
    var reportComputedAt: Date = Date()
    var reportDataModeOffline: Bool = false
    var dailySalesReportId: String = ""
    var peakHour: Int? = nil

    // ── Storefront vs Delivery (DBD / Revenue Department Split) ─────────────
    var storefrontGross: Double = 0
    var storefrontDiscount: Double = 0
    var storefrontNetSales: Double = 0
    var storefrontRefunds: Double = 0
    var storefrontNetRevenue: Double = 0
    var storefrontOrdersCount: Int = 0
    var storefrontCash: Double = 0
    var storefrontTransfer: Double = 0
    var storefrontCard: Double = 0
    var storefrontOtherTenders: Double = 0

    var deliveryOrderDetails: [DailySalesDeliveryOrderItem] = []
    var deliveryRefunds: Double = 0
    var deliveryGross: Double = 0
    var deliveryDiscount: Double = 0
    var deliveryNetSales: Double = 0
    var deliveryPlatformFees: Double = 0
    var deliveryNetReceivables: Double = 0
    var deliveryOrdersCount: Int = 0
    var deliveryPlatformBreakdown: [DailySalesDeliveryPlatformItem] = []

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
    var zSessionId: String = ""
    var zBusinessDateKey: String = ""
    var zGrossSales: Double = 0
    var zDiscounts: Double = 0
    var zRefunds: Double = 0
    var zTax: Double = 0
    var zServiceCharge: Double = 0
    var zNetSales: Double = 0
    var zReceiptCount: Int = 0
    var zFailedPaymentCount: Int = 0
    var zTenderBreakdown: [ReportTenderPoint] = []
    var zTenderVariance: Double = 0
    var zCashRefunds: Double = 0
    var zOpenedBy: String = "—"
    var zClosedBy: String = "—"
    var zNotes: String = ""

    // ── Tax/VAT ─────────────────────────────────────────────────────────────
    var totalSalesIncVAT: Double = 0
    var totalVATAmount: Double = 0
    var totalSalesExcVAT: Double = 0
    var dailyTaxEntries: [DailyTaxEntry] = []

    var vatSalesAmount: Double = 0
    var vatTaxAmount: Double = 0
    var nonVatSalesAmount: Double = 0

    // VAT position (ภ.พ.30-style reconciliation): output VAT from sales minus
    // input VAT from purchase invoices = net VAT payable (or refundable).
    var taxInputVAT: Double = 0
    var taxNetVATPayable: Double = 0

    // ── Refunds & Voids Audit ────────────────────────────────────────────────
    var refundTotalAmount: Double = 0
    var refundCount: Int = 0
    /// Refunds as % of net sales (inc. VAT) in the same period.
    var refundRatePct: Double = 0
    var auditVoidCount: Int = 0
    var auditVoidAmount: Double = 0
    var pendingRefundCount: Int = 0
    var refundsByReason: [RefundReasonPoint] = []
    var refundsByMethod: [RefundMethodPoint] = []
    var refundsByEmployee: [EmployeeRefundPoint] = []
    var refundLog: [RefundLogEntry] = []
    var voidLog: [VoidLogEntry] = []

    // ── Menu Profitability ──────────────────────────────────────────────────
    var menuProfitItems: [MenuProfitPoint] = []
    var productSalesItems: [ReportProductSalesPoint] = []
    var productSalesScope: ReportItemScope = .main
    var menuProfitabilityScope: ReportItemScope = .main
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

    // ── Inventory Usage & Planning ───────────────────────────────────────────
    /// Cost of stock consumed by sales (theoretical COGS) in the period.
    var inventoryUsageCost: Double = 0
    /// Cost of stock received from suppliers in the period.
    var inventoryReceivedCost: Double = 0
    /// Waste as % of total outflow cost (usage + waste) — food-cost KPI.
    var inventoryWastePct: Double = 0
    var itemUsageBreakdown: [ItemUsagePoint] = []
    var movementTypeBreakdown: [MovementTypePoint] = []
    var wasteReasonBreakdown: [WasteReasonPoint] = []
    var dailyUsageTrend: [InventoryDailyFlowPoint] = []
    var stockCoverage: [StockCoveragePoint] = []

    // ── Purchasing / Procurement ─────────────────────────────────────────────
    /// Committed spend = all non-cancelled, non-draft POs in the period.
    var purchaseTotalSpend: Double = 0
    /// Value of POs already received (goods in).
    var purchaseReceivedSpend: Double = 0
    /// Value of sent POs awaiting delivery.
    var purchaseOutstandingSpend: Double = 0
    /// Input VAT paid on purchases (from invoice tax amounts).
    var purchaseInputVAT: Double = 0
    var purchaseOrderCount: Int = 0
    var purchaseAvgPOValue: Double = 0
    var supplierSpendBreakdown: [SupplierSpendPoint] = []
    var topPurchasedItems: [PurchasedItemPoint] = []
    var poStatusBreakdown: [POStatusPoint] = []
    var recentPurchaseOrders: [PORecentEntry] = []

    // ── Customer Analytics ───────────────────────────────────────────────────
    /// Sales attached to a known customer profile in the period.
    var memberSales: Double = 0
    var memberOrderCount: Int = 0
    /// % of recognized orders that have a customer attached (attach rate).
    var customerAttachRatePct: Double = 0
    /// Customers created during the period.
    var newCustomerCount: Int = 0
    /// Distinct customers with at least one order in the period.
    var activeCustomerCount: Int = 0
    var avgSpendPerMemberOrder: Double = 0
    var customerTierBreakdown: [CustomerTierPoint] = []
    var topCustomers: [TopCustomerPoint] = []
    var totalCustomerBase: Int = 0

    // ── Branch Comparison ────────────────────────────────────────────────────
    var branchSalesBreakdown: [BranchSalesPoint] = []
    var branchTotalRevenue: Double = 0
    var activeBranchCount: Int = 0

    // ── Sales Forecast ───────────────────────────────────────────────────────
    /// Actual daily revenue (recent history) + projected days.
    var forecastSeries: [ForecastDayPoint] = []
    var forecastNext7Total: Double = 0
    var forecastAvgDaily: Double = 0
    /// Last 7 days vs previous 7 days revenue change.
    var forecastTrendPct: Double = 0
    /// Weeks of sales history backing the forecast (drives confidence).
    var forecastHistoryWeeks: Int = 0

    // ── Employee Hours ──────────────────────────────────────────────────────
    var employeeHoursEntries: [EmployeeHoursEntry] = []
    var totalLaborHours: Double = 0
    var totalLaborCost: Double = 0
    var totalOvertimeHours: Double = 0

    // ── Promotion Performance ────────────────────────────────────────────────
    struct PromotionPerformancePoint: Identifiable {
        let id = UUID()
        let promoId: UUID
        let title: String
        let discountType: String
        let redemptionCount: Int
        let totalDiscountGiven: Double
        let triggeredRevenue: Double
    }
    var promotionPerformanceItems: [PromotionPerformancePoint] = []

    // ── PDF State ───────────────────────────────────────────────────────────
    var generatedPDFURL: URL? = nil
    var showingShareSheet: Bool = false
    var isGeneratingPDF: Bool = false

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Date Range Helpers
    // ─────────────────────────────────────────────────────────────────────────

    var effectiveStartDate: Date {
        if dateBasis == .registerShift, let selectedShiftInterval { return selectedShiftInterval.start }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = dateBasis == .businessDay ? (TimeZone(identifier: businessTimeZoneID) ?? .current) : .current
        let offset = dateBasis == .businessDay ? min(max(businessDayCutoffHour, 0), 23) : 0
        func shiftedStart(_ date: Date) -> Date { cal.date(byAdding: .hour, value: offset, to: cal.startOfDay(for: date)) ?? cal.startOfDay(for: date) }
        switch periodMode {
        case .daily:
            return shiftedStart(selectedDate)
        case .weekly:
            let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selectedDate)
            return cal.date(byAdding: .hour, value: offset, to: cal.date(from: comps) ?? cal.startOfDay(for: selectedDate)) ?? shiftedStart(selectedDate)
        case .monthly:
            let comps = cal.dateComponents([.year, .month], from: selectedDate)
            return cal.date(byAdding: .hour, value: offset, to: cal.date(from: comps) ?? cal.startOfDay(for: selectedDate)) ?? shiftedStart(selectedDate)
        case .custom:
            return shiftedStart(rangeStart)
        }
    }

    var effectiveEndDate: Date {
        if dateBasis == .registerShift, let selectedShiftInterval { return selectedShiftInterval.end }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = dateBasis == .businessDay ? (TimeZone(identifier: businessTimeZoneID) ?? .current) : .current
        switch periodMode {
        case .daily:
            return cal.date(byAdding: .day, value: 1, to: effectiveStartDate) ?? Date()
        case .weekly:
            return cal.date(byAdding: .day, value: 7, to: effectiveStartDate) ?? Date()
        case .monthly:
            return cal.date(byAdding: .month, value: 1, to: effectiveStartDate) ?? Date()
        case .custom:
            let days = max(1, cal.dateComponents([.day], from: cal.startOfDay(for: rangeStart), to: cal.startOfDay(for: rangeEnd)).day.map { $0 + 1 } ?? 1)
            return cal.date(byAdding: .day, value: days, to: effectiveStartDate) ?? Date()
        }
    }

    /// Canonical sales boundary shared by every report. A register shift is an
    /// identity boundary first; its timestamps are only a compatibility
    /// fallback for legacy rows which predate registerSessionId.
    private func containsOrder(_ order: Order) -> Bool {
        guard !order.isDeleted else { return false }
        if let scopedRecognizedOrderIds {
            return scopedRecognizedOrderIds.contains(order.id)
        }
        guard order.isRecognizedSale else { return false }
        if dateBasis == .registerShift, let sessionId = selectedRegisterSessionId {
            if let explicit = order.registerSessionId { return explicit == sessionId }
            return order.payments.contains {
                !$0.isDeleted && $0.isCaptured && RegisterShiftScope.contains(
                    eventSessionId: $0.registerSessionId,
                    eventAt: $0.paidAt,
                    sessionId: sessionId,
                    openedAt: effectiveStartDate,
                    closedAt: effectiveEndDate
                )
            }
        }
        if dateBasis == .businessDay {
            if !order.businessDateKey.isEmpty {
                return BusinessDayContext.contains(
                    businessDateKey: order.businessDateKey,
                    from: effectiveStartDate,
                    to: effectiveEndDate,
                    cutoffHour: businessDayCutoffHour,
                    timeZoneID: businessTimeZoneID
                )
            }
        }
        return order.recognizedAt >= effectiveStartDate && order.recognizedAt < effectiveEndDate
    }

    /// Resolve FinancialEvent scope once before computing any report. This
    /// prevents product, tax, profitability, customer, and comparison reports
    /// from drifting away from the Daily Sales ledger boundary.
    func configureRecognizedSalesScope(financialEvents: [FinancialEvent]) {
        let start = effectiveStartDate
        let end = effectiveEndDate
        let selectedShiftId = selectedRegisterSessionId
        let scoped = financialEvents.filter { event in
            guard !event.isDeleted, event.status == "posted",
                  event.eventType == "sale_capture" || event.eventType == "government_subsidy" else { return false }
            if dateBasis == .registerShift, let selectedShiftId {
                return event.registerSessionId == selectedShiftId ||
                    (event.registerSessionId == nil && event.occurredAt >= start && event.occurredAt < end)
            }
            if dateBasis == .businessDay {
                return BusinessDayContext.contains(
                    businessDateKey: event.businessDateKey,
                    from: start,
                    to: end,
                    cutoffHour: businessDayCutoffHour,
                    timeZoneID: businessTimeZoneID
                ) || (event.businessDateKey.isEmpty && event.occurredAt >= start && event.occurredAt < end)
            }
            return event.occurredAt >= start && event.occurredAt < end
        }
        scopedRecognizedOrderIds = Set(scoped.compactMap(\.orderId))
    }

    private func containsPayment(_ payment: Payment) -> Bool {
        guard !payment.isDeleted && payment.isCaptured else { return false }
        if dateBasis == .registerShift, let sessionId = selectedRegisterSessionId {
            return RegisterShiftScope.contains(
                eventSessionId: payment.registerSessionId,
                eventAt: payment.paidAt,
                sessionId: sessionId,
                openedAt: effectiveStartDate,
                closedAt: effectiveEndDate
            )
        }
        if dateBasis == .businessDay, !payment.businessDateKey.isEmpty {
            return BusinessDayContext.contains(
                businessDateKey: payment.businessDateKey,
                from: effectiveStartDate,
                to: effectiveEndDate,
                cutoffHour: businessDayCutoffHour,
                timeZoneID: businessTimeZoneID
            )
        }
        return payment.paidAt >= effectiveStartDate && payment.paidAt < effectiveEndDate
    }

    private func containsRefund(_ refund: RefundTransaction) -> Bool {
        guard !refund.isDeleted else { return false }
        if dateBasis == .registerShift, let sessionId = selectedRegisterSessionId {
            return RegisterShiftScope.contains(
                eventSessionId: refund.registerSessionId,
                eventAt: refund.financialEventAt,
                sessionId: sessionId,
                openedAt: effectiveStartDate,
                closedAt: effectiveEndDate
            )
        }
        if dateBasis == .businessDay, !refund.businessDateKey.isEmpty {
            return BusinessDayContext.contains(
                businessDateKey: refund.businessDateKey,
                from: effectiveStartDate,
                to: effectiveEndDate,
                cutoffHour: businessDayCutoffHour,
                timeZoneID: businessTimeZoneID
            )
        }
        return refund.financialEventAt >= effectiveStartDate && refund.financialEventAt < effectiveEndDate
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Compute Daily Sales
    // ─────────────────────────────────────────────────────────────────────────

    func computeDailySales(
        orders: [Order],
        payments: [Payment],
        financialEvents: [FinancialEvent] = [],
        isOfflineMode: Bool = false
    ) {
        // Imported or legacy records can contain non-finite floating-point values.
        // Never propagate them into report totals or Swift Charts.
        func finite(_ value: Double) -> Double { value.isFinite ? value : 0 }

        let start = effectiveStartDate
        let end = effectiveEndDate
        reportComputedAt = Date()
        reportDataModeOffline = isOfflineMode
        let idFormatter = DateFormatter()
        idFormatter.dateFormat = "yyyyMMdd-HHmm"
        dailySalesReportId = "DS-\(idFormatter.string(from: reportComputedAt))"

        let selectedShiftId = selectedRegisterSessionId
        let scopedEvents = financialEvents.filter { event in
            guard !event.isDeleted, event.status == "posted",
                  AccountingMath.recognizedAmount(eventType: event.eventType, amount: event.amount) != nil else { return false }
            if dateBasis == .registerShift, let selectedShiftId {
                return event.registerSessionId == selectedShiftId ||
                    (event.registerSessionId == nil && event.occurredAt >= start && event.occurredAt < end)
            }
            if dateBasis == .businessDay {
                return BusinessDayContext.contains(
                    businessDateKey: event.businessDateKey,
                    from: start,
                    to: end,
                    cutoffHour: businessDayCutoffHour,
                    timeZoneID: businessTimeZoneID
                ) || (event.businessDateKey.isEmpty && event.occurredAt >= start && event.occurredAt < end)
            }
            return event.occurredAt >= start && event.occurredAt < end
        }
        let ledger = AccountingMath.summarize(scopedEvents.map {
            AccountingFact(eventType: $0.eventType, amount: $0.amount,
                           paymentMethod: $0.paymentMethod, orderId: $0.orderId,
                           isLateAdjustment: $0.isLateAdjustment)
        })
        let recognizedIds = Set(scopedEvents.compactMap { event in
            (event.eventType == "sale_capture" || event.eventType == "government_subsidy")
                ? event.orderId : nil
        })
        let filtered = orders.filter { !$0.isDeleted && recognizedIds.contains($0.id) }
        var capturedByOrder: [UUID: Double] = [:]
        for event in scopedEvents where event.eventType != "refund" {
            guard let orderId = event.orderId,
                  let amount = AccountingMath.recognizedAmount(eventType: event.eventType, amount: event.amount) else { continue }
            capturedByOrder[orderId, default: 0] += amount
        }
        let ordersById = Dictionary(uniqueKeysWithValues: orders.map { ($0.id, $0) })

        var gross = 0.0
        var discounts = 0.0
        var ticketTotal = 0.0
        var merchandise = 0.0
        var serviceCharge = 0.0
        var vat = 0.0
        var refunds = 0.0

        var sfGross = 0.0
        var sfDiscount = 0.0
        var sfTicket = 0.0
        var sfOrders = 0

        var delGross = 0.0
        var delDiscount = 0.0
        var delTicket = 0.0
        var delFees = 0.0
        var delOrders = 0

        var platformMap: [String: (gross: Double, discount: Double, net: Double, fees: Double, count: Int)] = [:]

        for order in filtered {
            let fraction = AccountingMath.capturedFraction(
                ticketTotal: finite(order.total),
                recognizedBeforeRefunds: capturedByOrder[order.id, default: 0]
            )
            let componentGross = finite(order.subtotal) + finite(order.serviceCharge) + finite(order.tax)
            let ticketGross = finite(order.total) + finite(order.discount)
            // Prefer component rebuild when it matches ticket+discount (tax-inclusive identity).
            let orderGross = abs(componentGross - ticketGross) <= 0.05 ? componentGross : ticketGross
            let g = orderGross * fraction
            let d = finite(order.discount) * fraction
            let t = finite(order.total) * fraction

            gross += g
            discounts += d
            ticketTotal += t
            merchandise += finite(order.subtotal) * fraction
            serviceCharge += finite(order.serviceCharge) * fraction
            vat += finite(order.tax) * fraction

            if order.orderType == "delivery" {
                delGross += g
                delDiscount += d
                delTicket += t
                delOrders += 1
                let fees = (finite(order.deliveryGPFeeAmount) + finite(order.deliveryAdFeeAmount) + finite(order.deliveryOtherFee)) * fraction
                delFees += fees

                let brand = (order.deliveryBrand?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? order.deliveryBrand!.trimmingCharacters(in: .whitespacesAndNewlines) : "Delivery"
                let current = platformMap[brand] ?? (0, 0, 0, 0, 0)
                platformMap[brand] = (
                    gross: current.gross + g,
                    discount: current.discount + d,
                    net: current.net + t,
                    fees: current.fees + fees,
                    count: current.count + 1
                )
            } else {
                sfGross += g
                sfDiscount += d
                sfTicket += t
                sfOrders += 1
            }
        }

        // Refunds are period transactions of their own. A refund processed
        // today must not be moved back to the day on which its order was opened.
        refunds = ledger.refunds

        // Refunds retain their own reporting period, including refund-only days.
        var deliveryRefundsByOrder: [UUID: Double] = [:]
        var deliveryRefundsByPlatform: [String: Double] = [:]
        var sfRefunds = 0.0
        for event in scopedEvents where event.eventType == "refund" {
            if let orderId = event.orderId, let order = ordersById[orderId], order.orderType == "delivery" {
                let amount = abs(finite(event.amount))
                deliveryRefundsByOrder[orderId, default: 0] += amount
                let brand = order.deliveryBrand?.trimmingCharacters(in: .whitespacesAndNewlines)
                let key = brand?.isEmpty == false ? brand! : "Delivery"
                deliveryRefundsByPlatform[key, default: 0] += amount
                if platformMap[key] == nil { platformMap[key] = (0, 0, 0, 0, 0) }
            } else {
                sfRefunds += abs(finite(event.amount))
            }
        }

        // Storefront payment tender breakdown
        var sfCash = 0.0
        var sfTransfer = 0.0
        var sfCard = 0.0
        var sfOther = 0.0

        for event in scopedEvents {
            guard let orderId = event.orderId, let order = ordersById[orderId], order.orderType != "delivery" else {
                continue
            }
            let amt: Double
            if event.eventType == "sale_capture" || event.eventType == "government_subsidy" {
                amt = max(finite(AccountingMath.recognizedAmount(eventType: event.eventType, amount: event.amount) ?? 0), 0)
            } else if event.eventType == "payment_void" || event.eventType == "reversal" {
                amt = -abs(finite(event.amount))
            } else {
                continue
            }
            let method = (event.paymentMethod ?? "").lowercased()
            if method.contains("cash") || method.contains("เงินสด") {
                sfCash += amt
            } else if method.contains("qr") || method.contains("promptpay") || method.contains("transfer") || method.contains("โอน") {
                sfTransfer += amt
            } else if method.contains("card") || method.contains("credit") || method.contains("debit") || method.contains("บัตร") {
                sfCard += amt
            } else {
                sfOther += amt
            }
        }

        // Assign Storefront & Delivery Properties
        self.storefrontGross = sfGross
        self.storefrontDiscount = sfDiscount
        self.storefrontNetSales = sfTicket
        self.storefrontRefunds = sfRefunds
        self.storefrontNetRevenue = sfTicket - sfRefunds
        self.storefrontOrdersCount = sfOrders
        self.storefrontCash = sfCash
        self.storefrontTransfer = sfTransfer
        self.storefrontCard = sfCard
        self.storefrontOtherTenders = sfOther

        self.deliveryGross = delGross
        self.deliveryDiscount = delDiscount
        self.deliveryNetSales = delTicket
        self.deliveryPlatformFees = delFees
        self.deliveryRefunds = deliveryRefundsByOrder.values.reduce(0, +)
        self.deliveryNetReceivables = delTicket - self.deliveryRefunds - delFees
        self.deliveryOrderDetails = orders.filter {
            $0.orderType == "delivery" && ((!$0.isDeleted && recognizedIds.contains($0.id)) || deliveryRefundsByOrder[$0.id] != nil)
        }.sorted {
            $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt
        }.map { order in
            let brand = order.deliveryBrand?.trimmingCharacters(in: .whitespacesAndNewlines)
            let number = order.platformOrderNumber?.trimmingCharacters(in: .whitespacesAndNewlines)
            return DailySalesDeliveryOrderItem(
                id: order.id,
                brandName: brand?.isEmpty == false ? brand! : "Delivery",
                orderNumber: order.orderNumber,
                platformOrderNumber: number?.isEmpty == false ? number : nil,
                netSales: order.isDeleted ? 0 : finite(order.total) * AccountingMath.capturedFraction(
                    ticketTotal: finite(order.total), recognizedBeforeRefunds: capturedByOrder[order.id, default: 0]
                ),
                refunds: deliveryRefundsByOrder[order.id, default: 0]
            )
        }
        self.deliveryOrdersCount = delOrders
        self.deliveryPlatformBreakdown = platformMap.map { key, val in
            DailySalesDeliveryPlatformItem(
                brandName: key,
                ordersCount: val.count,
                grossRevenue: val.gross,
                discount: val.discount,
                netSales: val.net,
                platformFees: val.fees,
                refunds: deliveryRefundsByPlatform[key, default: 0],
                netReceivables: val.net - deliveryRefundsByPlatform[key, default: 0] - val.fees
            )
        }.sorted { $0.netSales > $1.netSales }

        // Preserve the accounting bridge exactly even for partial captures,
        // subsidies and late adjustments: Gross − Discount = captured sales.
        grossRevenue = ledger.capturedSales + discounts
        totalDiscount = discounts
        // Net sales must match cashier ticket totals for EOD reconciliation.
        // The ledger is the same recognized-sales source used by Dashboard.
        // Component totals above are proportional presentation breakdowns.
        netSalesIncVAT = ledger.capturedSales
        merchandiseSubtotal = merchandise
        serviceChargeTotal = serviceCharge
        var refundsByOrder: [UUID: Double] = [:]
        for event in scopedEvents where event.eventType == "refund" {
            guard let orderId = event.orderId else { continue }
            refundsByOrder[orderId, default: 0] += abs(event.amount)
        }
        let refundedVAT = refundsByOrder.reduce(0.0) { result, entry in
            guard let order = ordersById[entry.key], order.total > 0 else { return result }
            return result + AccountingMath.allocatedOutputVAT(
                ticketTotal: order.total, documentVAT: order.tax,
                recognizedAmount: entry.value
            )
        }
        refundVAT = refundedVAT
        vatCollected = vat - refundedVAT
        totalRefunds = refunds
        netRevenue = netSalesIncVAT - totalRefunds
        accountingRevenueExVAT = netRevenue - vatCollected
        netSalesExVAT = accountingRevenueExVAT
        totalOrders = recognizedIds.count
        averageTicket = totalOrders > 0 ? netSalesIncVAT / Double(totalOrders) : 0

        // Voids (cancelled) — excluded from sales, reported separately.
        let voided = orders.filter {
            !$0.isDeleted &&
            $0.status == "cancelled" &&
            $0.createdAt >= start && $0.createdAt < end
        }
        voidOrderCount = voided.count
        voidAmount = voided.reduce(0.0) { $0 + finite($1.total) }

        // Tips + payments for the same recognized orders (not merely paidAt window).
        let orderPayments = payments.filter { payment in
            guard !payment.isDeleted, payment.isCaptured else { return false }
            guard let order = payment.order else { return false }
            guard recognizedIds.contains(order.id) else { return false }
            if dateBasis == .registerShift, let selectedShiftId {
                return RegisterShiftScope.contains(
                    eventSessionId: payment.registerSessionId, eventAt: payment.paidAt,
                    sessionId: selectedShiftId, openedAt: start, closedAt: end
                )
            }
            return true
        }
        let tendersFromPayments = orderPayments.reduce(0.0) { $0 + finite($1.amount) }
        let subsidiesFromEvents = scopedEvents
            .filter { $0.eventType == "government_subsidy" }
            .reduce(0.0) { $0 + max(0, finite($1.amount)) }
        if !payments.isEmpty {
            paymentsCollected = tendersFromPayments + subsidiesFromEvents
        } else {
            paymentsCollected = ledger.capturedSales
        }
        tipsTotal = orderPayments.reduce(0.0) { $0 + finite($1.tipAmount) }
        salesTenderVariance = (paymentsCollected - totalRefunds) - netRevenue

        // Hourly breakdown — net sales (ticket total) by createdAt hour
        let cal = Calendar.current
        var hourlyMap: [Int: (revenue: Double, count: Int)] = [:]
        var hourlyOrderIds: [Int: Set<UUID>] = [:]
        for event in scopedEvents {
            guard let amount = AccountingMath.recognizedAmount(eventType: event.eventType, amount: event.amount) else { continue }
            let hour = cal.component(.hour, from: event.occurredAt)
            let existing = hourlyMap[hour] ?? (0, 0)
            if (event.eventType == "sale_capture" || event.eventType == "government_subsidy"),
               let orderId = event.orderId {
                hourlyOrderIds[hour, default: []].insert(orderId)
            }
            hourlyMap[hour] = (existing.revenue + amount, 0)
        }
        hourlySales = (0..<24).map { hour in
            let data = hourlyMap[hour] ?? (0, 0)
            return ReportsHourlySalesPoint(
                hour: hour, revenue: data.revenue,
                orderCount: hourlyOrderIds[hour]?.count ?? 0
            )
        }
        if let peak = hourlySales.max(by: { $0.revenue < $1.revenue }), peak.revenue > 0 {
            peakHour = peak.hour
        } else {
            peakHour = nil
        }

        // Payment tender mix for the same order-linked payments
        var methodMap: [String: (amount: Double, count: Int)] = [:]
        for event in scopedEvents where event.eventType == "sale_capture" || event.eventType == "government_subsidy" {
            let normalizedMethod = (event.paymentMethod ?? "other").lowercased().replacingOccurrences(of: " ", with: "_")
            let existing = methodMap[normalizedMethod] ?? (0, 0)
            methodMap[normalizedMethod] = (existing.amount + max(finite(event.amount), 0), existing.count + 1)
        }
        paymentBreakdown = methodMap.map { key, value in
            PaymentMethodPoint(method: key, amount: value.amount, count: value.count)
        }.sorted { $0.amount > $1.amount }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Compute Z-Report
    // ─────────────────────────────────────────────────────────────────────────

    func computeZReport(
        sessions: [RegisterSession], movements: [CashMovement], orders: [Order],
        payments: [Payment], refunds: [RefundTransaction], employees: [Employee], users: [User]
    ) {
        let start = effectiveStartDate
        let end = effectiveEndDate

        // Find the most recent session in the period
        let relevantSessions = sessions.filter {
            !$0.isDeleted && (
                (dateBasis == .registerShift && $0.id == selectedRegisterSessionId) ||
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
        zSessionId = String(session.id.uuidString.prefix(8)).uppercased()
        zBusinessDateKey = session.businessDateKey
        zNotes = session.notes ?? ""
        let employeeByUserId = Dictionary(uniqueKeysWithValues: employees.compactMap { employee in
            employee.user.map { ($0.id, "\(employee.firstName) \(employee.lastName)") }
        })
        let usernameById = Dictionary(uniqueKeysWithValues: users.map { ($0.id, $0.username) })
        zOpenedBy = employeeByUserId[session.openedByUserId]
            ?? usernameById[session.openedByUserId]
            ?? String(session.openedByUserId.uuidString.prefix(8)).uppercased()
        zClosedBy = session.closedByUserId.map {
            employeeByUserId[$0] ?? usernameById[$0] ?? String($0.uuidString.prefix(8)).uppercased()
        } ?? "—"

        // Cash movements for this session
        let sessionMovements = movements.filter {
            !$0.isDeleted && $0.registerSession?.id == session.id
        }
        totalCashIn = sessionMovements.filter { $0.movementType == "cash_in" || $0.movementType == "paid_in" }.reduce(0.0) { $0 + $1.amount }
        totalCashOut = sessionMovements.filter { $0.movementType == "cash_out" || $0.movementType == "paid_out" }.reduce(0.0) { $0 + $1.amount }

        // Cash sales in the period
        let allSessionPayments = payments.filter {
            !$0.isDeleted &&
            RegisterShiftScope.contains(
                eventSessionId: $0.registerSessionId,
                eventAt: $0.paidAt,
                sessionId: session.id,
                openedAt: session.openedAt,
                closedAt: session.closedAt ?? Date()
            )
        }
        let capturedPayments = allSessionPayments.filter(\.isCaptured)
        let sessionRefunds = refunds.filter {
            !$0.isDeleted && $0.status == "completed" && RegisterShiftScope.contains(
                eventSessionId: $0.registerSessionId, eventAt: $0.financialEventAt,
                sessionId: session.id, openedAt: session.openedAt,
                closedAt: session.closedAt ?? Date()
            )
        }
        var orderMap: [UUID: Order] = [:]
        for payment in capturedPayments {
            if let order = payment.order { orderMap[order.id] = order }
        }
        let recognizedOrders = Array(orderMap.values).filter(\.isRecognizedSale)

        func tenderName(_ raw: String) -> String {
            switch raw.lowercased().replacingOccurrences(of: " ", with: "_") {
            case "cash": return "Cash"
            case "card", "credit_card", "debit_card": return "Card"
            case "qr", "qr_promptpay", "promptpay", "transfer", "bank_transfer": return "PromptPay / QR"
            case "true_money": return "TrueMoney"
            case "original_tender": return "Original Tender"
            default: return raw.replacingOccurrences(of: "_", with: " ").capitalized
            }
        }
        func tenderInfo(payment: Payment) -> (name: String, delivery: Bool) {
            if let order = payment.order,
               order.orderType == "delivery" || order.deliveryBrand?.isEmpty == false {
                let brand = order.deliveryBrand?.trimmingCharacters(in: .whitespacesAndNewlines)
                return (brand?.isEmpty == false ? brand! : "Delivery", true)
            }
            let lower = payment.paymentMethod.lowercased()
            let deliveryWords = ["delivery", "grab", "line_man", "lineman", "shopee", "foodpanda", "robinhood"]
            return (tenderName(payment.paymentMethod), deliveryWords.contains(where: lower.contains))
        }
        var received: [String: (amount: Double, count: Int, delivery: Bool)] = [:]
        for payment in capturedPayments where payment.order?.usesGovernmentSupport != true {
            let info = tenderInfo(payment: payment)
            let method = info.name
            let delivery = info.delivery
            let key = method + (delivery ? "|delivery" : "|store")
            let old = received[key] ?? (0, 0, delivery)
            received[key] = (old.amount + payment.amount, old.count + 1, delivery)
        }
        let programOrders = recognizedOrders.filter(\.usesGovernmentSupport)
        if !programOrders.isEmpty {
            let key = GovernmentSupportProgram.thaiChuaThaiPlus + "|store"
            received[key] = (
                // Refunds are deducted once below, within the selected shift.
                programOrders.reduce(0) { $0 + $1.total },
                programOrders.count,
                false
            )
        }
        var refunded: [String: (amount: Double, delivery: Bool)] = [:]
        for refund in sessionRefunds {
            let info: (name: String, delivery: Bool)
            if refund.order?.usesGovernmentSupport == true {
                info = (GovernmentSupportProgram.thaiChuaThaiPlus, false)
            } else if let original = refund.originalPayment {
                info = tenderInfo(payment: original)
            } else {
                let raw = refund.refundMethod
                let lower = raw.lowercased()
                let words = ["delivery", "grab", "line_man", "lineman", "shopee", "foodpanda", "robinhood"]
                info = (tenderName(raw), words.contains(where: lower.contains))
            }
            let method = info.name
            let delivery = info.delivery
            let key = method + (delivery ? "|delivery" : "|store")
            let old = refunded[key] ?? (0, delivery)
            refunded[key] = (old.amount + refund.refundAmount, delivery)
        }
        zTenderBreakdown = Set(received.keys).union(refunded.keys).map { key in
            let rec = received[key] ?? (0, 0, false)
            let ref = refunded[key] ?? (0, rec.delivery)
            return ReportTenderPoint(
                method: key.components(separatedBy: "|").first ?? key,
                received: rec.amount, refunded: ref.amount,
                count: rec.count, isDelivery: rec.delivery || ref.delivery
            )
        }.sorted {
            if $0.isDelivery != $1.isDelivery { return !$0.isDelivery }
            return $0.received > $1.received
        }

        let cashTender = zTenderBreakdown.first { $0.method.lowercased() == "cash" && !$0.isDelivery }
        totalCashSales = cashTender?.received ?? 0
        zCashRefunds = cashTender?.refunded ?? 0
        expectedCash = session.closedAt == nil
            ? openingCash + totalCashSales - zCashRefunds + totalCashIn - totalCashOut
            : session.expectedClosingCash
        variance = actualCash - expectedCash

        zGrossSales = recognizedOrders.reduce(0) { $0 + $1.total + $1.discount }
        zDiscounts = recognizedOrders.reduce(0) { $0 + $1.discount }
        zRefunds = sessionRefunds.reduce(0) { $0 + $1.refundAmount }
        zTax = recognizedOrders.reduce(0) { $0 + $1.tax }
        zServiceCharge = recognizedOrders.reduce(0) { $0 + $1.serviceCharge }
        zNetSales = max(0, zGrossSales - zDiscounts - zRefunds)
        zTenderVariance = zTenderBreakdown.reduce(0) { $0 + $1.net } - zNetSales
        zReceiptCount = recognizedOrders.count
        zFailedPaymentCount = allSessionPayments.filter { $0.status == "failed" }.count
    }

    private func resetZReport() {
        openingCash = 0; totalCashSales = 0; totalCashIn = 0; totalCashOut = 0
        expectedCash = 0; actualCash = 0; variance = 0
        sessionOpenedAt = nil; sessionClosedAt = nil
        zSessionId = ""; zBusinessDateKey = ""; zGrossSales = 0; zDiscounts = 0
        zRefunds = 0; zTax = 0; zServiceCharge = 0; zNetSales = 0
        zReceiptCount = 0; zFailedPaymentCount = 0; zTenderBreakdown = []; zTenderVariance = 0
        zCashRefunds = 0; zOpenedBy = "—"; zClosedBy = "—"; zNotes = ""
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Compute Tax/VAT
    // ─────────────────────────────────────────────────────────────────────────

    func computeTaxReport(orders: [Order], taxLines: [OrderTaxLine], purchaseOrders: [PurchaseOrder] = []) {
        let start = effectiveStartDate
        let end = effectiveEndDate

        let filteredOrders = orders.filter(containsOrder)

        totalSalesIncVAT = filteredOrders.reduce(0.0) { $0 + $1.total }
        totalVATAmount = filteredOrders.reduce(0.0) { $0 + $1.tax }
        totalSalesExcVAT = totalSalesIncVAT - totalVATAmount

        // ── VAT position (ภ.พ.30): output VAT − input VAT ────────────────────
        // Input VAT comes from purchase invoices in the same period
        // (committed POs only — drafts and cancellations carry no tax credit).
        taxInputVAT = purchaseOrders
            .filter {
                !$0.isDeleted &&
                $0.status != "cancelled" && $0.status != "draft" &&
                $0.orderDate >= start && $0.orderDate < end
            }
            .reduce(0.0) { $0 + ($1.taxAmount ?? 0) }
        taxNetVATPayable = totalVATAmount - taxInputVAT

        // Split Tax Calculation
        vatSalesAmount = 0.0
        vatTaxAmount = 0.0
        nonVatSalesAmount = 0.0

        for order in filteredOrders {
            let orderTaxLines = order.taxLines.filter { !$0.isDeleted }
            if orderTaxLines.isEmpty {
                nonVatSalesAmount += order.total
            } else {
                for taxLine in orderTaxLines {
                    if taxLine.taxRate > 0 {
                        vatTaxAmount += taxLine.taxAmount
                        vatSalesAmount += taxLine.taxableAmount
                    } else {
                        nonVatSalesAmount += taxLine.taxableAmount
                    }
                }

                // Tax lines are the durable snapshot; old item->menu links may point at deleted catalog rows.
            }
        }

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
        let filteredOrders = orders.filter(containsOrder)

        // Aggregate from the order-line snapshot; the live MenuItem may have been deleted later.
        var itemStats: [String: (name: String, channel: String, itemType: String, qty: Int, revenue: Double, cogs: Double)] = [:]
        var activeMenuByName: [String: MenuItem] = [:]
        for menuItem in menuItems where activeMenuByName[menuItem.name] == nil {
            activeMenuByName[menuItem.name] = menuItem
        }

        let ledger = (try? modelContext?.fetch(FetchDescriptor<InventoryTransaction>())) ?? []
        let sellCostByReference = Dictionary(grouping: ledger.filter {
            !$0.isDeleted && $0.movementType == .sell && $0.referenceId != nil
        }, by: { $0.referenceId! }).mapValues {
            $0.reduce(0) { $0 + $1.magnitude * ($1.costPrice ?? 0) }
        }

        for order in filteredOrders {
            let activeItems = order.items.filter { !$0.isDeleted && $0.status != "cancelled" }
            let allocationBase = activeItems.reduce(0.0) { partial, item in
                partial + item.subtotal + item.modifiers.filter { !$0.isDeleted }.reduce(0.0) { $0 + $1.price * Double(item.quantity) }
            }
            let channel = order.orderType == "delivery" ? "เดลิเวอรี" : "หน้าร้าน"

            for item in activeItems where menuProfitabilityScope != .addOns && (menuProfitabilityScope == .allUnits || item.resolvedLineType == .main) {
                let itemName = item.itemName.trimmingCharacters(in: .whitespacesAndNewlines)
                let name = itemName.isEmpty ? "Unknown Item" : itemName
                let key = "\(channel)|main|\(name)"
                let itemCogs = sellCostByReference[item.id] ?? 0
                let proportionalDiscount = allocationBase > 0 ? (item.subtotal / allocationBase) * order.discount : 0
                let netRevenue = max(0.0, item.subtotal - proportionalDiscount)
                let existing = itemStats[key] ?? (name, channel, "เมนูหลัก", 0, 0, 0)
                itemStats[key] = (name, channel, "เมนูหลัก", existing.qty + item.quantity, existing.revenue + netRevenue, existing.cogs + itemCogs)
            }

            for item in activeItems where menuProfitabilityScope != .main {
                if item.resolvedLineType == .addOn {
                    let name = item.itemName.isEmpty ? "Add-on" : item.itemName
                    let key = "\(channel)|addon|\(name)"
                    let discount = allocationBase > 0 ? (item.subtotal / allocationBase) * order.discount : 0
                    let existing = itemStats[key] ?? (name, channel, "Add-on", 0, 0, 0)
                    itemStats[key] = (name, channel, "Add-on", existing.qty + item.quantity, existing.revenue + max(0, item.subtotal - discount), existing.cogs + (sellCostByReference[item.id] ?? 0))
                }
                for modifier in item.modifiers where !modifier.isDeleted {
                    let name = modifier.modifier?.name ?? "Modifier"
                    let gross = modifier.price * Double(item.quantity)
                    let discount = allocationBase > 0 ? (gross / allocationBase) * order.discount : 0
                    let key = "\(channel)|modifier|\(name)"
                    let existing = itemStats[key] ?? (name, channel, "Modifier", 0, 0, 0)
                    itemStats[key] = (name, channel, "Modifier", existing.qty + item.quantity, existing.revenue + max(0, gross - discount), existing.cogs + (sellCostByReference[modifier.id] ?? 0))
                }
            }
        }

        menuProfitItems = itemStats.map { key, stats in
            let grossProfit = stats.revenue - stats.cogs
            let marginPct = stats.revenue > 0 ? (grossProfit / stats.revenue) * 100 : 0

            return MenuProfitPoint(
                menuItemId: activeMenuByName[stats.name]?.id ?? key,
                name: stats.name,
                channel: stats.channel,
                itemType: stats.itemType,
                quantitySold: stats.qty,
                revenue: stats.revenue,
                cogs: stats.cogs,
                grossProfit: grossProfit,
                marginPct: marginPct
            )
        }

        applySorting()
    }

    func computeProductSales(orders: [Order], menuItems: [MenuItem]) {
        let catalog = Dictionary(uniqueKeysWithValues: menuItems.map { ($0.id, $0) })
        var totals: [String: (sku: String, name: String, category: String, channel: String, itemType: String, qty: Int, gross: Double, discount: Double, refunds: Double)] = [:]

        for order in orders where containsOrder(order) {
            let allActiveItems = order.items.filter { !$0.isDeleted && $0.status != "cancelled" }
            // Allocate order-level discounts/refunds once across every active
            // line. Filtering the denominator by scope would duplicate the
            // whole discount in Main, Add-on, and All-units reports.
            let lineTotal = allActiveItems.reduce(0.0) { partial, item in partial + item.subtotal + item.modifiers.filter { !$0.isDeleted }.reduce(0.0) { $0 + $1.price * Double(item.quantity) } }
            let channel = order.orderType == "delivery" ? "เดลิเวอรี" : "หน้าร้าน"
            for item in allActiveItems where productSalesScope != .addOns && (productSalesScope == .allUnits || item.resolvedLineType == .main) {
                let menu = item.menuItem ?? catalog.values.first { $0.name == item.itemName }
                let key = "\(channel)|main|\(menu?.id ?? item.itemName)"
                let share = lineTotal > 0 ? item.subtotal / lineTotal : (allActiveItems.count == 1 ? 1 : 0)
                let gross = item.subtotal > 0 ? item.subtotal : max(order.subtotal, order.total) * share
                let current = totals[key] ?? (
                    menu?.sku ?? "—",
                    item.itemName,
                    menu?.category?.name ?? inferredProductCategory(item.itemName), channel, "เมนูหลัก",
                    0, 0, 0, 0
                )
                totals[key] = (
                    current.sku, current.name, current.category, channel, "เมนูหลัก",
                    current.qty + item.quantity,
                    current.gross + gross,
                    current.discount + order.discount * share,
                    current.refunds + order.refundedTotal * share
                )
            }
            for item in allActiveItems where productSalesScope != .main {
                var components: [(String, String, String, String, Double, Int)] = []
                if item.resolvedLineType == .addOn { components.append((item.id.uuidString, item.itemName, "Add-on", "Add-on", item.subtotal, item.quantity)) }
                components += item.modifiers.filter { !$0.isDeleted }.map { ($0.id.uuidString, $0.modifier?.name ?? "Modifier", "Modifier", "Modifier", $0.price * Double(item.quantity), item.quantity) }
                for component in components {
                    let key = "\(channel)|addon|\(component.0)|\(component.1)"
                    let share = lineTotal > 0 ? component.4 / lineTotal : 0
                    let current = totals[key] ?? ("—", component.1, component.2, channel, component.3, 0, 0, 0, 0)
                    totals[key] = (current.sku, current.name, current.category, channel, component.3, current.qty + component.5, current.gross + component.4, current.discount + order.discount * share, current.refunds + order.refundedTotal * share)
                }
            }
        }

        productSalesItems = totals.map { key, value in
            let net = max(0, value.gross - value.discount - value.refunds)
            return ReportProductSalesPoint(
                id: key, sku: value.sku, name: value.name, category: value.category,
                channel: value.channel, itemType: value.itemType,
                quantitySold: value.qty, grossSales: value.gross,
                discount: value.discount, refunds: value.refunds, netSales: net,
                averageUnitPrice: value.qty > 0 ? net / Double(value.qty) : 0
            )
        }.sorted { $0.netSales > $1.netSales }
    }

    private func inferredProductCategory(_ itemName: String) -> String {
        let name = itemName.lowercased()
        if ["drink", "beverage", "coffee", "tea", "juice", "water", "beer", "lager", "ชา", "กาแฟ", "เบียร์", "เครื่องดื่ม"].contains(where: name.contains) {
            return "เครื่องดื่ม"
        }
        if ["dessert", "cake", "sweet", "ของหวาน", "เค้ก"].contains(where: name.contains) {
            return "ของหวาน"
        }
        return "ไม่ระบุหมวดหมู่"
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Compute Promotion Performance
    // ─────────────────────────────────────────────────────────────────────────

    func computePromotionPerformance(orders: [Order], promotions: [Promotion], discounts: [OrderDiscount]) {
        let filteredOrders = orders.filter(containsOrder)

        let filteredOrderIds = Set(filteredOrders.map { $0.id })

        // Group discounts by promotion ID
        var promoStats: [UUID: (count: Int, discount: Double, revenue: Double)] = [:]
        for od in discounts where !od.isDeleted {
            guard let order = od.order, filteredOrderIds.contains(order.id), let promo = od.promotion else { continue }
            let existing = promoStats[promo.id] ?? (0, 0.0, 0.0)
            promoStats[promo.id] = (
                existing.count + 1,
                existing.discount + od.discountAmount,
                existing.revenue + order.total
            )
        }

        self.promotionPerformanceItems = promotions.compactMap { promo in
            let stats = promoStats[promo.id] ?? (0, 0.0, 0.0)
            guard stats.count > 0 || promo.isActive else { return nil }
            return PromotionPerformancePoint(
                promoId: promo.id,
                title: promo.title,
                discountType: promo.discountType,
                redemptionCount: stats.count,
                totalDiscountGiven: stats.discount,
                triggeredRevenue: stats.revenue
            )
        }.sorted { $0.totalDiscountGiven > $1.totalDiscountGiven }
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
            $0.createdAt >= start && $0.createdAt < end
        }
        wasteEntries = wasteTransactions.compactMap { tx in
            guard let item = tx.item else { return nil }
            let cost = abs(tx.quantity) * (tx.costPrice ?? item.costPrice)
            return WasteEntry(itemName: item.name, quantity: abs(tx.quantity), unit: item.unit, cost: cost, date: tx.createdAt, notes: tx.notes)
        }.sorted { $0.date > $1.date }

        totalWasteCost = wasteEntries.reduce(0.0) { $0 + $1.cost }

        computeInventoryUsageAnalysis(items: activeItems, transactions: transactions, start: start, end: end)
    }

    /// Usage vs waste analysis for planning: per-item consumption, movement
    /// totals, waste causes, daily trend and forward stock coverage.
    private func computeInventoryUsageAnalysis(
        items: [InventoryItem],
        transactions: [InventoryTransaction],
        start: Date,
        end: Date
    ) {
        let periodTx = transactions.filter {
            !$0.isDeleted && $0.createdAt >= start && $0.createdAt < end
        }

        func txCost(_ tx: InventoryTransaction) -> Double {
            tx.magnitude * (tx.costPrice ?? tx.item?.costPrice ?? 0)
        }

        let sellType    = InventoryMovementType.sell.rawValue
        let wasteType   = InventoryMovementType.waste.rawValue
        let receiveType = InventoryMovementType.receive.rawValue

        let sellTx    = periodTx.filter { $0.transactionType == sellType }
        let wasteTx   = periodTx.filter { $0.transactionType == wasteType }
        let receiveTx = periodTx.filter { $0.transactionType == receiveType }

        inventoryUsageCost    = sellTx.reduce(0.0) { $0 + txCost($1) }
        inventoryReceivedCost = receiveTx.reduce(0.0) { $0 + txCost($1) }
        let totalOutflow = inventoryUsageCost + totalWasteCost
        inventoryWastePct = totalOutflow > 0 ? totalWasteCost / totalOutflow * 100 : 0

        // ── Per-item usage vs waste ──────────────────────────────────────────
        var itemMap: [String: (unit: String, usedQty: Double, usedCost: Double, wasteQty: Double, wasteCost: Double)] = [:]
        for tx in sellTx {
            guard let item = tx.item else { continue }
            var entry = itemMap[item.name] ?? (item.unit, 0, 0, 0, 0)
            entry.usedQty += tx.magnitude
            entry.usedCost += txCost(tx)
            itemMap[item.name] = entry
        }
        for tx in wasteTx {
            guard let item = tx.item else { continue }
            var entry = itemMap[item.name] ?? (item.unit, 0, 0, 0, 0)
            entry.wasteQty += tx.magnitude
            entry.wasteCost += txCost(tx)
            itemMap[item.name] = entry
        }
        itemUsageBreakdown = itemMap.map { name, v in
            let outflow = v.usedCost + v.wasteCost
            return ItemUsagePoint(
                itemName: name, unit: v.unit,
                usedQty: v.usedQty, usedCost: v.usedCost,
                wasteQty: v.wasteQty, wasteCost: v.wasteCost,
                wastePct: outflow > 0 ? v.wasteCost / outflow * 100 : 0
            )
        }.sorted { ($0.usedCost + $0.wasteCost) > ($1.usedCost + $1.wasteCost) }

        // ── Movement type totals ─────────────────────────────────────────────
        var moveMap: [String: (count: Int, qty: Double, value: Double)] = [:]
        for tx in periodTx {
            var entry = moveMap[tx.transactionType] ?? (0, 0, 0)
            entry.count += 1
            entry.qty += tx.magnitude
            entry.value += txCost(tx)
            moveMap[tx.transactionType] = entry
        }
        movementTypeBreakdown = moveMap.map { type, v in
            MovementTypePoint(type: type, count: v.count, quantity: v.qty, value: v.value)
        }.sorted { $0.value > $1.value }

        // ── Waste by reason (HACCP cause analysis) ───────────────────────────
        var reasonMap: [String: (count: Int, cost: Double)] = [:]
        for tx in wasteTx {
            let reason = (tx.reasonCode?.isEmpty == false ? tx.reasonCode! :
                          (tx.notes?.isEmpty == false ? tx.notes! : "unspecified"))
            var entry = reasonMap[reason] ?? (0, 0)
            entry.count += 1
            entry.cost += txCost(tx)
            reasonMap[reason] = entry
        }
        wasteReasonBreakdown = reasonMap.map { reason, v in
            WasteReasonPoint(reason: reason, count: v.count, cost: v.cost)
        }.sorted { $0.cost > $1.cost }

        // ── Daily usage vs waste trend ───────────────────────────────────────
        let cal = Calendar.current
        var dayMap: [Date: (usage: Double, waste: Double)] = [:]
        for tx in sellTx {
            let day = cal.startOfDay(for: tx.createdAt)
            dayMap[day, default: (0, 0)].usage += txCost(tx)
        }
        for tx in wasteTx {
            let day = cal.startOfDay(for: tx.createdAt)
            dayMap[day, default: (0, 0)].waste += txCost(tx)
        }
        dailyUsageTrend = dayMap.map { date, v in
            InventoryDailyFlowPoint(date: date, usageCost: v.usage, wasteCost: v.waste)
        }.sorted { $0.date < $1.date }

        // ── Forward stock coverage (days of supply) ──────────────────────────
        // Average daily consumption over the period → days until stock-out.
        let periodDays = max(1.0, end.timeIntervalSince(start) / 86_400)
        var usageQtyByItemId: [UUID: Double] = [:]
        for tx in sellTx {
            guard let item = tx.item else { continue }
            usageQtyByItemId[item.id, default: 0] += tx.magnitude
        }
        for tx in wasteTx {
            guard let item = tx.item else { continue }
            usageQtyByItemId[item.id, default: 0] += tx.magnitude
        }
        stockCoverage = items.compactMap { item in
            guard let usedQty = usageQtyByItemId[item.id], usedQty > 0 else { return nil }
            let avgDaily = usedQty / periodDays
            let days = avgDaily > 0 ? max(0, item.currentQuantity) / avgDaily : 0
            return StockCoveragePoint(
                itemName: item.name,
                unit: item.unit,
                currentQty: item.currentQuantity,
                avgDailyUsage: avgDaily,
                daysRemaining: days
            )
        }.sorted { $0.daysRemaining < $1.daysRemaining }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Compute Purchasing / Procurement Report
    // ─────────────────────────────────────────────────────────────────────────

    /// Procurement spend analysis (spend-cube style: supplier × item × status).
    /// PO value prefers the invoice grand total when the document was scanned,
    /// otherwise falls back to Σ(qty ordered × unit cost) from line items.
    func computePurchasingReport(purchaseOrders: [PurchaseOrder]) {
        let start = effectiveStartDate
        let end = effectiveEndDate

        let periodPOs = purchaseOrders.filter {
            !$0.isDeleted && $0.orderDate >= start && $0.orderDate < end
        }

        func poValue(_ po: PurchaseOrder) -> Double {
            if let total = po.grandTotal, total > 0 { return total }
            return po.items
                .filter { !$0.isDeleted }
                .reduce(0.0) { $0 + $1.quantityOrdered * $1.unitCost }
        }

        func supplierName(_ po: PurchaseOrder) -> String {
            if let name = po.supplier?.name, !name.isEmpty { return name }
            if let raw = po.supplierNameRaw, !raw.isEmpty { return raw }
            return "—"
        }

        // Committed spend excludes cancelled and draft documents.
        let committedPOs = periodPOs.filter { $0.status != "cancelled" && $0.status != "draft" }
        let receivedPOs  = committedPOs.filter { $0.status == "received" }
        let sentPOs      = committedPOs.filter { $0.status == "sent" }

        purchaseTotalSpend       = committedPOs.reduce(0.0) { $0 + poValue($1) }
        purchaseReceivedSpend    = receivedPOs.reduce(0.0) { $0 + poValue($1) }
        purchaseOutstandingSpend = sentPOs.reduce(0.0) { $0 + poValue($1) }
        purchaseInputVAT         = committedPOs.reduce(0.0) { $0 + ($1.taxAmount ?? 0) }
        purchaseOrderCount       = committedPOs.count
        purchaseAvgPOValue       = committedPOs.isEmpty ? 0 : purchaseTotalSpend / Double(committedPOs.count)

        // ── Spend by supplier ────────────────────────────────────────────────
        var supplierMap: [String: (count: Int, total: Double, received: Double, outstanding: Double)] = [:]
        for po in committedPOs {
            let name = supplierName(po)
            let value = poValue(po)
            var entry = supplierMap[name] ?? (0, 0, 0, 0)
            entry.count += 1
            entry.total += value
            if po.status == "received" { entry.received += value }
            if po.status == "sent"     { entry.outstanding += value }
            supplierMap[name] = entry
        }
        supplierSpendBreakdown = supplierMap.map { name, v in
            SupplierSpendPoint(
                supplierName: name,
                poCount: v.count,
                totalSpend: v.total,
                receivedSpend: v.received,
                outstandingSpend: v.outstanding,
                sharePct: purchaseTotalSpend > 0 ? v.total / purchaseTotalSpend * 100 : 0
            )
        }.sorted { $0.totalSpend > $1.totalSpend }

        // ── Top purchased items ──────────────────────────────────────────────
        var itemMap: [String: (unit: String, qtyOrdered: Double, qtyReceived: Double, cost: Double)] = [:]
        for po in committedPOs {
            for line in po.items where !line.isDeleted {
                let name = line.inventoryItem?.name
                    ?? line.sourceItemName
                    ?? "—"
                let unit = line.inventoryItem?.unit ?? line.sourceUnit ?? ""
                let lineCost = line.lineTotal ?? (line.quantityOrdered * line.unitCost)
                var entry = itemMap[name] ?? (unit, 0, 0, 0)
                entry.qtyOrdered += line.quantityOrdered
                entry.qtyReceived += line.quantityReceived
                entry.cost += lineCost
                itemMap[name] = entry
            }
        }
        topPurchasedItems = itemMap.map { name, v in
            PurchasedItemPoint(
                itemName: name,
                unit: v.unit,
                quantityOrdered: v.qtyOrdered,
                quantityReceived: v.qtyReceived,
                totalCost: v.cost,
                avgUnitCost: v.qtyOrdered > 0 ? v.cost / v.qtyOrdered : 0
            )
        }.sorted { $0.totalCost > $1.totalCost }

        // ── Status breakdown (includes draft/cancelled for visibility) ──────
        var statusMap: [String: (count: Int, value: Double)] = [:]
        for po in periodPOs {
            var entry = statusMap[po.status] ?? (0, 0)
            entry.count += 1
            entry.value += poValue(po)
            statusMap[po.status] = entry
        }
        poStatusBreakdown = statusMap.map { status, v in
            POStatusPoint(status: status, count: v.count, value: v.value)
        }.sorted { $0.value > $1.value }

        // ── Recent PO log ────────────────────────────────────────────────────
        recentPurchaseOrders = periodPOs
            .sorted { $0.orderDate > $1.orderDate }
            .prefix(20)
            .map { po in
                PORecentEntry(
                    id: po.id,
                    poNumber: po.poNumber,
                    supplierName: supplierName(po),
                    status: po.status,
                    orderDate: po.orderDate,
                    value: poValue(po),
                    itemCount: po.items.filter { !$0.isDeleted }.count
                )
            }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Compute Customer Analytics (CRM)
    // ─────────────────────────────────────────────────────────────────────────

    /// CRM analysis from the existing Customer model + orders linked via
    /// `Order.customer`. Attach rate shows how much of the revenue is
    /// identified — the leading indicator for loyalty-program health.
    func computeCustomerAnalytics(customers: [Customer], orders: [Order]) {
        let start = effectiveStartDate
        let end = effectiveEndDate

        let activeCustomers = customers.filter { !$0.isDeleted }
        totalCustomerBase = activeCustomers.count

        let periodOrders = orders.filter(containsOrder)
        let memberOrders = periodOrders.filter { $0.customer != nil && $0.customer?.isDeleted == false }

        memberOrderCount = memberOrders.count
        memberSales = memberOrders.reduce(0.0) { $0 + $1.recognizedNetTotal }
        customerAttachRatePct = periodOrders.isEmpty ? 0 : Double(memberOrders.count) / Double(periodOrders.count) * 100
        avgSpendPerMemberOrder = memberOrders.isEmpty ? 0 : memberSales / Double(memberOrders.count)

        newCustomerCount = activeCustomers.filter { $0.createdAt >= start && $0.createdAt < end }.count

        // ── Per-customer aggregates within the period ────────────────────────
        var spendByCustomer: [UUID: (name: String, tier: String, points: Int, count: Int, spend: Double, lastVisit: Date?)] = [:]
        for order in memberOrders {
            guard let customer = order.customer else { continue }
            var entry = spendByCustomer[customer.id]
                ?? (customer.name, customer.membershipTier, customer.loyaltyPoints, 0, 0, nil)
            entry.count += 1
            entry.spend += order.recognizedNetTotal
            entry.lastVisit = max(entry.lastVisit ?? .distantPast, order.recognizedAt)
            spendByCustomer[customer.id] = entry
        }
        activeCustomerCount = spendByCustomer.count

        topCustomers = spendByCustomer
            .map { id, v in
                TopCustomerPoint(id: id, name: v.name, tier: v.tier, orderCount: v.count,
                                 spend: v.spend, loyaltyPoints: v.points, lastVisit: v.lastVisit)
            }
            .sorted { $0.spend > $1.spend }
            .prefix(15)
            .map { $0 }

        // ── Membership tier mix (period spend) ───────────────────────────────
        var tierMap: [String: (count: Int, spend: Double)] = [:]
        for (_, v) in spendByCustomer {
            tierMap[v.tier, default: (0, 0)].count += 1
            tierMap[v.tier]!.spend += v.spend
        }
        customerTierBreakdown = tierMap
            .map { CustomerTierPoint(tier: $0.key, customerCount: $0.value.count, spend: $0.value.spend) }
            .sorted { $0.spend > $1.spend }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Compute Branch Comparison
    // ─────────────────────────────────────────────────────────────────────────

    /// Revenue per branch via `Order.branch`. Orders without a branch link
    /// are grouped under the main store so totals always reconcile with
    /// Daily Sales.
    func computeBranchComparison(orders: [Order], branches: [Branch]) {
        activeBranchCount = branches.filter { !$0.isDeleted }.count

        let periodOrders = orders.filter(containsOrder)
        branchTotalRevenue = periodOrders.reduce(0.0) { $0 + $1.recognizedNetTotal }

        var branchMap: [String: (count: Int, revenue: Double, guests: Int)] = [:]
        for order in periodOrders {
            let name = order.branch.isDeleted ? "__inactive__" : order.branch.name
            var entry = branchMap[name] ?? (0, 0, 0)
            entry.count += 1
            entry.revenue += order.recognizedNetTotal
            entry.guests += order.guestCount
            branchMap[name] = entry
        }

        branchSalesBreakdown = branchMap.map { name, v in
            BranchSalesPoint(
                branchName: name,
                orderCount: v.count,
                revenue: v.revenue,
                avgTicket: v.count > 0 ? v.revenue / Double(v.count) : 0,
                guestCount: v.guests,
                sharePct: branchTotalRevenue > 0 ? v.revenue / branchTotalRevenue * 100 : 0
            )
        }.sorted { $0.revenue > $1.revenue }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Compute Sales Forecast
    // ─────────────────────────────────────────────────────────────────────────

    /// 7-day projection using a weekday seasonal average (each future day is
    /// projected from the mean of the same weekday over up to 4 trailing
    /// weeks). Transparent, explainable, and degrades gracefully with little
    /// history — confidence is surfaced via `forecastHistoryWeeks`.
    func computeSalesForecast(orders: [Order]) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let historyStart = cal.date(byAdding: .day, value: -28, to: today) ?? today

        let sales = orders.filter {
            $0.isRecognizedSale && $0.recognizedAt >= historyStart && $0.recognizedAt < today
        }

        // Daily revenue history
        var dailyRevenue: [Date: Double] = [:]
        for order in sales {
            let day = cal.startOfDay(for: order.recognizedAt)
            dailyRevenue[day, default: 0] += order.total
        }
        for refund in orders.flatMap(\.refunds) where !refund.isDeleted && refund.status == "completed" {
            guard refund.financialEventAt >= historyStart && refund.financialEventAt < today else { continue }
            let day = cal.startOfDay(for: refund.financialEventAt)
            dailyRevenue[day, default: 0] -= max(refund.refundAmount, 0)
        }

        let daysWithSales = dailyRevenue.keys.count
        forecastHistoryWeeks = min(4, daysWithSales / 7)

        // Weekday means from available history
        var weekdayTotals: [Int: (sum: Double, count: Int)] = [:]
        for (day, revenue) in dailyRevenue {
            let weekday = cal.component(.weekday, from: day)
            weekdayTotals[weekday, default: (0, 0)].sum += revenue
            weekdayTotals[weekday]!.count += 1
        }
        let overallDailyMean = daysWithSales > 0
            ? dailyRevenue.values.reduce(0, +) / Double(daysWithSales)
            : 0

        func projected(for date: Date) -> Double {
            let weekday = cal.component(.weekday, from: date)
            if let stats = weekdayTotals[weekday], stats.count > 0 {
                return stats.sum / Double(stats.count)
            }
            return overallDailyMean
        }

        // Series: last 14 actual days + next 7 projected days
        var series: [ForecastDayPoint] = []
        for offset in stride(from: -14, through: -1, by: 1) {
            guard let day = cal.date(byAdding: .day, value: offset, to: today) else { continue }
            series.append(ForecastDayPoint(date: day, revenue: dailyRevenue[day] ?? 0, isForecast: false))
        }
        var next7 = 0.0
        for offset in 0..<7 {
            guard let day = cal.date(byAdding: .day, value: offset, to: today) else { continue }
            let value = projected(for: day)
            next7 += value
            series.append(ForecastDayPoint(date: day, revenue: value, isForecast: true))
        }
        forecastSeries = series
        forecastNext7Total = next7
        forecastAvgDaily = next7 / 7

        // Momentum: last 7 actual days vs the 7 before that
        func window(_ fromOffset: Int, _ toOffset: Int) -> Double {
            var total = 0.0
            for offset in fromOffset..<toOffset {
                if let day = cal.date(byAdding: .day, value: offset, to: today) {
                    total += dailyRevenue[day] ?? 0
                }
            }
            return total
        }
        let last7 = window(-7, 0)
        let prev7 = window(-14, -7)
        forecastTrendPct = prev7 > 0 ? (last7 - prev7) / prev7 * 100 : 0
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Compute Refunds & Voids Audit
    // ─────────────────────────────────────────────────────────────────────────

    /// Exception / loss-prevention report: who refunded what, why, and how,
    /// plus voided (cancelled) tickets. Refund rate is benchmarked against
    /// net sales of the same period.
    ///
    func computeRefundVoidReport(refunds: [RefundTransaction], orders: [Order], employees: [Employee]) {
        let start = effectiveStartDate
        let end = effectiveEndDate

        func refundDate(_ refund: RefundTransaction) -> Date {
            refund.financialEventAt
        }

        let periodRefunds = refunds.filter { $0.status != "rejected" && containsRefund($0) }
        let completedRefunds = periodRefunds.filter { $0.status == "completed" }

        refundTotalAmount = completedRefunds.reduce(0.0) { $0 + $1.refundAmount }
        refundCount = completedRefunds.count
        pendingRefundCount = periodRefunds.filter { $0.status == "pending_approval" }.count

        // Benchmark against recognized sales in the same window.
        let periodSales = orders
            .filter(containsOrder)
            .reduce(0.0) { $0 + $1.total }
        refundRatePct = periodSales > 0 ? refundTotalAmount / periodSales * 100 : 0

        // ── Group by reason / method / employee ──────────────────────────────
        let employeeNames = Dictionary(uniqueKeysWithValues: employees.map { ($0.id, "\($0.firstName) \($0.lastName)") })
        func employeeName(_ id: UUID?) -> String {
            guard let id else { return "—" }
            return employeeNames[id] ?? "—"
        }

        var reasonMap: [String: (count: Int, amount: Double)] = [:]
        var methodMap: [String: (count: Int, amount: Double)] = [:]
        var employeeMap: [String: (count: Int, amount: Double)] = [:]
        for refund in completedRefunds {
            reasonMap[refund.reasonCode, default: (0, 0)].count += 1
            reasonMap[refund.reasonCode]!.amount += refund.refundAmount
            methodMap[refund.refundMethod, default: (0, 0)].count += 1
            methodMap[refund.refundMethod]!.amount += refund.refundAmount
            let name = employeeName(refund.refundedByEmployeeId)
            employeeMap[name, default: (0, 0)].count += 1
            employeeMap[name]!.amount += refund.refundAmount
        }
        refundsByReason = reasonMap
            .map { RefundReasonPoint(reason: $0.key, count: $0.value.count, amount: $0.value.amount) }
            .sorted { $0.amount > $1.amount }
        refundsByMethod = methodMap
            .map { RefundMethodPoint(method: $0.key, count: $0.value.count, amount: $0.value.amount) }
            .sorted { $0.amount > $1.amount }
        refundsByEmployee = employeeMap
            .map { EmployeeRefundPoint(employeeName: $0.key, count: $0.value.count, amount: $0.value.amount) }
            .sorted { $0.amount > $1.amount }

        // ── Refund log ───────────────────────────────────────────────────────
        refundLog = periodRefunds
            .sorted { refundDate($0) > refundDate($1) }
            .prefix(30)
            .map { refund in
                RefundLogEntry(
                    id: refund.id,
                    orderNumber: refund.order?.orderNumber ?? "—",
                    amount: refund.refundAmount,
                    method: refund.refundMethod,
                    reason: refund.reasonNotes?.isEmpty == false ? refund.reasonNotes! : refund.reasonCode,
                    refundedBy: employeeName(refund.refundedByEmployeeId),
                    approvedBy: refund.approvedByEmployeeId.map { employeeName($0) },
                    status: refund.status,
                    date: refundDate(refund)
                )
            }

        // ── Voided tickets ───────────────────────────────────────────────────
        let voided = orders.filter {
            !$0.isDeleted && $0.status == "cancelled" &&
            $0.createdAt >= start && $0.createdAt < end
        }
        auditVoidCount = voided.count
        auditVoidAmount = voided.reduce(0.0) { $0 + $1.total }
        voidLog = voided
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(30)
            .map { order in
                VoidLogEntry(
                    id: order.id,
                    orderNumber: order.orderNumber,
                    amount: order.total,
                    itemCount: order.items
                        .filter { !$0.isDeleted && $0.status != "cancelled" && $0.resolvedLineType == .main }
                        .reduce(0) { $0 + $1.quantity },
                    date: order.createdAt
                )
            }
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
    // MARK: - L-2: Monthly Comparison Report
    // ─────────────────────────────────────────────────────────────────────────

    struct MonthPoint: Identifiable {
        let id = UUID()
        let label: String
        let month: Int
        let year: Int
        let revenue: Double
        let orderCount: Int
        let avgOrderValue: Double
        let topItem: String
        let taxCollected: Double
        let refundAmount: Double
    }

    var monthlyPoints: [MonthPoint] = []
    var comparisonMonths: Int = 6


    func computeMonthlyComparison(orders: [Order], payments: [Payment], taxLines: [OrderTaxLine]) {
        let cal = Calendar.current
        let now = Date()
        var points: [MonthPoint] = []

        for offset in stride(from: -(comparisonMonths - 1), through: 0, by: 1) {
            guard let targetDate = cal.date(byAdding: .month, value: offset, to: now) else { continue }
            let targetMonth = cal.component(.month, from: targetDate)
            let targetYear  = cal.component(.year,  from: targetDate)

            let monthOrders = orders.filter { order in
                guard order.isRecognizedSale else { return false }
                return cal.component(.month, from: order.recognizedAt) == targetMonth
                    && cal.component(.year,  from: order.recognizedAt) == targetYear
            }
            let revenue    = monthOrders.reduce(0.0) { $0 + $1.total }
            let orderCount = monthOrders.count
            let avgOV      = orderCount > 0 ? revenue / Double(orderCount) : 0.0

            let monthTax = taxLines.filter { tl in
                guard !tl.isDeleted, let order = tl.order else { return false }
                return cal.component(.month, from: order.recognizedAt) == targetMonth
                    && cal.component(.year,  from: order.recognizedAt) == targetYear
            }.reduce(0.0) { $0 + $1.taxAmount }

            // RefundTransaction is the canonical refund source (same as Daily
            // Sales and the Live Dashboard) — the Payment.status path counted
            // a different population and made months disagree with daily totals.
            let monthRefunds = orders.flatMap(\.refunds).filter {
                !$0.isDeleted && $0.status == "completed" &&
                cal.component(.month, from: $0.financialEventAt) == targetMonth &&
                cal.component(.year, from: $0.financialEventAt) == targetYear
            }.reduce(0.0) { $0 + max($1.refundAmount, 0) }

            var itemCounts: [String: Int] = [:]
            for order in monthOrders {
                for item in order.items where !item.isDeleted && item.status != "cancelled" && item.resolvedLineType == .main {
                    let snapshotName = item.itemName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let name = snapshotName.isEmpty ? "Unknown Item" : snapshotName
                    itemCounts[name, default: 0] += item.quantity
                }
            }
            let topItem = itemCounts.max(by: { $0.value < $1.value })?.key ?? "—"

            let df = DateFormatter()
            df.locale = Locale(identifier: "th_TH")
            df.dateFormat = "MMM yy"
            let label = df.string(from: targetDate)

            points.append(MonthPoint(
                label: label, month: targetMonth, year: targetYear,
                revenue: revenue, orderCount: orderCount, avgOrderValue: avgOV,
                topItem: topItem, taxCollected: monthTax, refundAmount: monthRefunds
            ))
        }
        self.monthlyPoints = points
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - PDF Generation
    // ─────────────────────────────────────────────────────────────────────────

    @MainActor
    func generatePDF(title: String, content: some View) {
        isGeneratingPDF = true
        let pageSize = CGSize(width: 595, height: 842)
        let margin: CGFloat = 36
        let bodyHeight = pageSize.height - margin * 2
        let renderer = ImageRenderer(content: content.frame(width: pageSize.width - margin * 2))
        renderer.scale = 2.0

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(title)_\(formattedDate).pdf")

        renderer.render { size, renderer in
            var box = CGRect(origin: .zero, size: pageSize)
            guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            let pageCount = max(1, Int(ceil(size.height / bodyHeight)))
            for page in 0..<pageCount {
                context.beginPage(mediaBox: &box)
                context.saveGState()
                context.clip(to: CGRect(x: margin, y: margin, width: pageSize.width - margin * 2, height: bodyHeight))
                context.translateBy(x: margin, y: margin - CGFloat(page) * bodyHeight)
                renderer(context)
                context.restoreGState()
                context.endPage()
            }
            context.closePDF()
        }

        generatedPDFURL = url
        isGeneratingPDF = false
        showingShareSheet = true
    }

    @MainActor
    func generateDailySalesPDF(
        storeName: String,
        taxId: String?,
        branchName: String?,
        storeAddress: String? = nil,
        storePhone: String? = nil,
        branchCode: String? = nil
    ) {
        isGeneratingPDF = true
        defer { isGeneratingPDF = false }

        let snapshot = DailySalesReportSnapshot(
            reportId: dailySalesReportId,
            periodLabel: periodDescription,
            computedAt: reportComputedAt,
            isOfflineMode: reportDataModeOffline,
            storeName: storeName,
            taxId: taxId,
            branchName: branchName,
            storeAddress: storeAddress,
            storePhone: storePhone,
            branchCode: branchCode,
            grossSales: grossRevenue,
            discounts: totalDiscount,
            netSalesIncVAT: netSalesIncVAT,
            merchandiseSubtotal: merchandiseSubtotal,
            serviceCharge: serviceChargeTotal,
            vatCollected: vatCollected,
            refundVAT: refundVAT,
            netSalesExVAT: netSalesExVAT,
            refunds: totalRefunds,
            netRevenueAfterRefunds: netRevenue,
            tips: tipsTotal,
            voidCount: voidOrderCount,
            voidAmount: voidAmount,
            orderCount: totalOrders,
            averageTicket: averageTicket,
            paymentsCollected: paymentsCollected,
            tenderVariance: salesTenderVariance,
            peakHour: peakHour,
            paymentBreakdown: paymentBreakdown.map {
                DailySalesReportSnapshot.TenderLine(method: $0.method, amount: $0.amount, count: $0.count)
            },
            storefrontNetSales: storefrontNetSales,
            storefrontCash: storefrontCash,
            storefrontTransfer: storefrontTransfer,
            storefrontCard: storefrontCard,
            deliveryNetSales: deliveryNetSales,
            deliveryPlatformFees: deliveryPlatformFees,
            deliveryNetReceivables: deliveryNetReceivables,
            deliveryRefunds: deliveryRefunds,
            deliveryOrderDetails: deliveryOrderDetails
        )

        guard let url = DailySalesPDFExporter.export(snapshot: snapshot) else { return }
        generatedPDFURL = url
        showingShareSheet = true
    }

    @MainActor
    func generateProductSalesPDF(storeName: String) {
        isGeneratingPDF = true
        defer { isGeneratingPDF = false }
        guard let url = ProductSalesPDFExporter.export(.init(
            storeName: storeName,
            period: periodDescription,
            generatedAt: Date(),
            scopeLabel: productSalesScope.displayName,
            quantityLabel: productSalesScope.quantityLabel,
            rows: productSalesItems
        )) else { return }
        generatedPDFURL = url
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
        if dateBasis == .registerShift, let selectedShiftInterval {
            fmt.dateFormat = "d MMM HH:mm"
            return "\(fmt.string(from: selectedShiftInterval.start)) – \(fmt.string(from: selectedShiftInterval.end))"
        }
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
