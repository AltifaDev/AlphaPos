import SwiftUI
import SwiftData
import Charts

// ─────────────────────────────────────────────────────────────────────
// MARK: - Enterprise Sales Dashboard
// ─────────────────────────────────────────────────────────────────────
struct SalesDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allOrders: [Order]
    @Query private var allInventory: [InventoryItem]
    @Query private var allEmployees: [Employee]
    @Query private var allTimecards: [Timecard]

    @State private var viewModel = SalesViewModel()
    @State private var selectedTab: AnalyticsTab = .overview
    @State private var animateKPIs = false
    @State private var animateCharts = false
    @State private var generatedPDFURL: URL? = nil
    @State private var showingShareSheet = false

    enum AnalyticsTab: String, CaseIterable {
        case overview      = "Overview"
        case profitability = "P&L"
        case delivery      = "Delivery"
        case menu          = "Menu"
        case inventory     = "Inventory"
        case staff         = "Staff"

        var icon: String {
            switch self {
            case .overview:      return "chart.bar.fill"
            case .profitability: return "dollarsign.circle.fill"
            case .delivery:      return "box.truck.fill"
            case .menu:          return "fork.knife"
            case .inventory:     return "archivebox.fill"
            case .staff:         return "person.2.fill"
            }
        }
    }

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            GeometryReader { _ in
                HStack(spacing: APSpacing.md) {
                    // LEFT COLUMN — Period + Controls
                    leftPanelContainer
                        .frame(width: 320)

                    // RIGHT COLUMN — Tab content
                    VStack(alignment: .leading, spacing: APSpacing.sm) {
                        analyticsTabBar
                        tabContent
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .padding(APSpacing.md)
            }
        }
        .navigationTitle("Sales & Analytics")
        .apNavBar(background: Color.appBackground)
        .onAppear { refreshData(); triggerEntranceAnimations() }
        .onChange(of: viewModel.summaryMode)  { refreshData() }
        .onChange(of: viewModel.selectedDate)  { refreshData() }
        .onChange(of: viewModel.selectedMonth) { refreshData() }
        .onChange(of: viewModel.selectedYear)  { refreshData() }
        .sheet(isPresented: $showingShareSheet) {
            if let url = generatedPDFURL {
                ShareSheet(activityItems: [url]).presentationDetents([.medium, .large])
            }
        }
    }

    // ─── Tab Bar ──────────────────────────────────────────────────────
    private var analyticsTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(AnalyticsTab.allCases, id: \.self) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { selectedTab = tab }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 11, weight: .bold))
                            Text(tab.rawValue)
                                .font(.system(size: 11, weight: .bold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(selectedTab == tab ? Color.appAccent : Color.appSurface)
                        .foregroundColor(selectedTab == tab ? .white : .textSecondary)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(selectedTab == tab ? Color.clear : Color.appBorderSubtle, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // ─── Tab Content Router ───────────────────────────────────────────
    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .overview:      overviewTab
        case .profitability: profitabilityTab
        case .delivery:      deliveryTab
        case .menu:          menuTab
        case .inventory:     inventoryTab
        case .staff:         staffTab
        }
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: LEFT PANEL
    // ─────────────────────────────────────────────────────────────────
    private var leftPanelContainer: some View {
        VStack(spacing: APSpacing.sm) {
            periodSelectorCard
            paymentBreakdownCard
            ordersHistoryLogCard
        }
    }

    private var periodSelectorCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("REPORTING PERIOD")
                .font(.caption).fontWeight(.bold).foregroundColor(.appAccent).tracking(1.0)

            Picker("Mode", selection: $viewModel.summaryMode) {
                Text("Daily Summary").tag(SalesViewModel.SummaryMode.daily)
                Text("Monthly Summary").tag(SalesViewModel.SummaryMode.monthly)
            }
            .pickerStyle(.segmented)

            if viewModel.summaryMode == .daily {
                DatePicker("Target Date", selection: $viewModel.selectedDate, displayedComponents: .date)
                    .datePickerStyle(.compact).foregroundColor(.textPrimary)
            } else {
                HStack(spacing: 8) {
                    Picker("Month", selection: $viewModel.selectedMonth) {
                        ForEach(1...12, id: \.self) { i in
                            Text(viewModel.monthsList[i - 1]).tag(i)
                        }
                    }
                    .pickerStyle(.menu).tint(.appAccent)
                    Spacer()
                    Picker("Year", selection: $viewModel.selectedYear) {
                        ForEach(viewModel.availableYears, id: \.self) { y in
                            Text("\(y)").tag(y)
                        }
                    }
                    .pickerStyle(.menu).tint(.appAccent)
                }
            }
        }
        .apCard()
    }

    private var paymentBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PAYMENT METHOD")
                .font(.caption).fontWeight(.bold).foregroundColor(.appAccent).tracking(1.0)

            if viewModel.paymentBreakdown.isEmpty {
                emptyLabel("No payments recorded.")
            } else {
                HStack(spacing: 16) {
                    Chart(viewModel.paymentBreakdown) { pt in
                        SectorMark(angle: .value("Rev", pt.amount), innerRadius: .ratio(0.55), angularInset: 1.5)
                            .cornerRadius(4)
                            .foregroundStyle(by: .value("Method", pt.method))
                    }
                    .chartForegroundStyleScale([
                        "Cash": Color.appAccent,
                        "Credit Card": Color.appTeal,
                        "PromptPay QR": Color.appRose,
                        "TrueMoney Wallet": Color.appAccent.opacity(0.6)
                    ])
                    .frame(width: 100, height: 100)
                    .chartLegend(.hidden)

                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(viewModel.paymentBreakdown) { pt in
                            HStack {
                                Text(pt.method).font(.caption2).foregroundColor(.textSecondary).lineLimit(1)
                                Spacer()
                                Text("฿\(pt.amount.formatted(.number.precision(.fractionLength(0))))")
                                    .font(.system(.caption2, design: .monospaced)).fontWeight(.bold)
                            }
                        }
                    }
                }
            }
        }
        .apCard()
        .frame(maxHeight: 160)
    }

    private var ordersHistoryLogCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TRANSACTION LOG")
                .font(.caption).fontWeight(.bold).foregroundColor(.appAccent).tracking(1.0)

            if viewModel.historicalOrders.isEmpty {
                emptyLabel("No matching orders found.")
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(viewModel.historicalOrders) { order in
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(order.orderNumber).font(.caption).fontWeight(.bold)
                                    HStack(spacing: 4) {
                                        orderTypePill(order.orderType)
                                        Text(order.createdAt.formatted(date: .omitted, time: .shortened))
                                            .font(.system(size: 9)).foregroundColor(.textTertiary)
                                    }
                                }
                                Spacer()
                                Text("฿\(order.total.formatted(.number.precision(.fractionLength(0))))")
                                    .font(.system(.caption, design: .monospaced)).fontWeight(.bold).foregroundColor(.appTeal)
                            }
                            .padding(.vertical, 6).padding(.horizontal, 8)
                            .background(Color.appSurfaceHigh)
                            .cornerRadius(8)
                        }
                    }
                }
            }
        }
        .apCard()
        .frame(maxHeight: .infinity)
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: TAB 1 — OVERVIEW
    // ─────────────────────────────────────────────────────────────────
    private var overviewTab: some View {
        ScrollView {
            VStack(spacing: APSpacing.md) {
                // KPI Row 1 — Revenue
                Grid(horizontalSpacing: APSpacing.sm, verticalSpacing: APSpacing.sm) {
                    GridRow {
                        kpiCard("GROSS REVENUE",    "฿\(fmt(viewModel.grossRevenue))",     "Net ฿\(fmt(viewModel.netRevenue, 0))",           .appTeal)
                        kpiCard("TOTAL ORDERS",     "\(viewModel.totalOrders)",              "Avg ฿\(fmt(viewModel.averageTicketValue, 0))",   .appAccent)
                        kpiCard("ITEMS SOLD",       "\(viewModel.totalItemsSold)",           "Cancelled: \(viewModel.cancelledItemsCount)",   .appTeal)
                        kpiCard("DISCOUNTS",        "฿\(fmt(viewModel.discountGiven))",      "Refunds: ฿\(fmt(viewModel.refundedAmount, 0))",  .appRose)
                    }
                    GridRow {
                        kpiCard("TAX COLLECTED",    "฿\(fmt(viewModel.taxCollected))",       "VAT",                                           .appAccent)
                        kpiCard("SERVICE CHARGE",   "฿\(fmt(viewModel.serviceChargeCollected))", "Svc fee",                                   .appTeal)
                        kpiCard("MODIFIER REVENUE", "฿\(fmt(viewModel.modifierRevenue))",    "Add-ons & Toppings",                            .appAccent)
                        kpiCard("PEAK HOUR",
                                viewModel.peakHour != nil ? HourlySalesPoint(hour: viewModel.peakHour!, revenue: 0).hourLabel : "–",
                                "฿\(fmt(viewModel.peakHourRevenue, 0))",                                                                    .appTeal)
                    }
                }
                .scaleEffect(animateKPIs ? 1 : 0.97).opacity(animateKPIs ? 1 : 0.6)

                // Order Type Mix
                orderTypeMixCard

                // Revenue Trend
                trendsChartCard

                // Product Sales Table
                productSalesCard
            }
            .padding(.bottom, APSpacing.lg)
        }
    }

    private var orderTypeMixCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ORDER TYPE MIX")
                .font(.caption).fontWeight(.bold).foregroundColor(.appAccent).tracking(1.0)
            HStack(spacing: APSpacing.sm) {
                orderTypeStat("🪑 Dine-In",  viewModel.dineInOrders,   viewModel.dineInRevenue,   .appTeal)
                orderTypeStat("🥡 Take-Out", viewModel.takeOutOrders,  viewModel.takeOutRevenue,  .appAccent)
                orderTypeStat("🚚 Delivery", viewModel.deliveryOrders, viewModel.deliveryRevenue, .appRose)
            }
        }
        .apCard()
    }

    private func orderTypeStat(_ label: String, _ count: Int, _ rev: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption2).foregroundColor(.textSecondary)
            Text("\(count) orders").font(.caption).fontWeight(.bold).foregroundColor(color)
            Text("฿\(fmt(rev, 0))").font(.system(size: 11, design: .monospaced)).foregroundColor(.textPrimary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.25), lineWidth: 1))
    }

    private var trendsChartCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SALES REVENUE TREND")
                .font(.caption).fontWeight(.bold).foregroundColor(.appAccent).tracking(1.0)

            if viewModel.summaryMode == .daily {
                Chart(viewModel.hourlyTrend) { p in
                    BarMark(x: .value("Hour", p.hourLabel), y: .value("Revenue", p.revenue))
                        .foregroundStyle(Color.appAccent.gradient).cornerRadius(4)
                }
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: 160)
                .opacity(animateCharts ? 1 : 0).offset(y: animateCharts ? 0 : 12)
            } else {
                Chart(viewModel.dailyTrend) { p in
                    LineMark(x: .value("Day", p.dayLabel), y: .value("Revenue", p.revenue))
                        .foregroundStyle(Color.appAccent).lineStyle(StrokeStyle(lineWidth: 2.5)).interpolationMethod(.catmullRom)
                    AreaMark(x: .value("Day", p.dayLabel), y: .value("Revenue", p.revenue))
                        .foregroundStyle(Color.appAccent.opacity(0.12).gradient).interpolationMethod(.catmullRom)
                }
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: 160)
                .opacity(animateCharts ? 1 : 0).offset(y: animateCharts ? 0 : 12)
            }
        }
        .apCard()
    }

    private var productSalesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("PRODUCT SALES REPORT")
                    .font(.caption).fontWeight(.bold).foregroundColor(.appAccent).tracking(1.0)
                Spacer()
                Button(action: shareProductReportAction) {
                    Label("Export PDF", systemImage: "square.and.arrow.up")
                        .font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.plain).foregroundColor(.appAccent)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Color.appAccent.opacity(0.1)).cornerRadius(6)
            }

            if viewModel.productSales.isEmpty {
                emptyLabel("No item sales recorded.")
            } else {
                tableHeader(["Item Name", "Category", "Qty", "Revenue", "Margin %"])
                Divider()
                ForEach(viewModel.productSales) { prod in
                    HStack {
                        Text(prod.name).fontWeight(.semibold).frame(maxWidth: .infinity, alignment: .leading).lineLimit(1)
                        Text(prod.category).foregroundColor(.textSecondary).frame(width: 110, alignment: .leading)
                        Text("\(prod.quantity)").fontWeight(.bold).frame(width: 50, alignment: .trailing)
                        Text("฿\(fmt(prod.totalRevenue, 0))").foregroundColor(.appTeal).fontWeight(.bold).frame(width: 90, alignment: .trailing)
                        Text(prod.cogs > 0 ? "\(String(format: "%.1f", prod.grossMarginPct))%" : "–")
                            .foregroundColor(prod.grossMarginPct >= 50 ? .appTeal : .appRose)
                            .frame(width: 70, alignment: .trailing)
                    }
                    .font(.system(size: 11)).padding(.vertical, 7).padding(.horizontal, 6)
                    Divider()
                }
            }

            Button(action: shareFullReportAction) {
                Label("Export Full Summary Report (PDF)", systemImage: "doc.plaintext.fill")
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .apGradientButton(gradient: APGradient.accent, shadow: APShadow.glow)
            .padding(.top, 4)
        }
        .apCard()
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: TAB 2 — P&L (PROFITABILITY)
    // ─────────────────────────────────────────────────────────────────
    private var profitabilityTab: some View {
        ScrollView {
            VStack(spacing: APSpacing.md) {
                // P&L Summary KPIs
                Grid(horizontalSpacing: APSpacing.sm, verticalSpacing: APSpacing.sm) {
                    GridRow {
                        kpiCard("GROSS REVENUE",  "฿\(fmt(viewModel.grossRevenue))",         "ยอดขายรวม",                      .appTeal)
                        kpiCard("TOTAL COGS",     "฿\(fmt(viewModel.totalCOGS))",             "ต้นทุนสินค้าจากสูตรอาหาร",       .appRose)
                        kpiCard("GROSS PROFIT",   "฿\(fmt(viewModel.grossProfit))",            "กำไรขั้นต้น",                    viewModel.grossProfit >= 0 ? .appTeal : .appRose)
                        kpiCard("GROSS MARGIN",   "\(String(format: "%.1f", viewModel.grossMarginPct))%", "Gross Margin %",   viewModel.grossMarginPct >= 40 ? .appTeal : .appRose)
                    }
                    GridRow {
                        kpiCard("LABOR COST",     "฿\(fmt(viewModel.totalLaborCost))",        "\(String(format: "%.1f", viewModel.laborCostPct))% of Revenue",  .appAccent)
                        kpiCard("WASTE COST",     "฿\(fmt(viewModel.totalWasteCost))",        "Loss from spoilage/waste",       .appRose)
                        kpiCard("ESTIMATED NET",  "฿\(fmt(viewModel.estimatedNetProfit))",    "หลังหักค่าแรง + waste",          viewModel.estimatedNetProfit >= 0 ? .appTeal : .appRose)
                        kpiCard("NET MARGIN",     "\(String(format: "%.1f", viewModel.netProfitMarginPct))%", "Net Profit %", viewModel.netProfitMarginPct >= 15 ? .appTeal : .appRose)
                    }
                }

                // P&L Waterfall-style breakdown
                plWaterfallCard

                // Top margin items
                if !viewModel.topMarginItems.isEmpty {
                    topMarginItemsCard
                }

                // Category revenue pie
                if !viewModel.categoryBreakdown.isEmpty {
                    categoryBreakdownCard
                }
            }
            .padding(.bottom, APSpacing.lg)
        }
    }

    private var plWaterfallCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("P&L BREAKDOWN")
                .font(.caption).fontWeight(.bold).foregroundColor(.appAccent).tracking(1.0)

            let rows: [(String, Double, Bool)] = [
                ("Gross Revenue",      viewModel.grossRevenue,              false),
                ("(-) COGS",           -viewModel.totalCOGS,               true),
                ("= Gross Profit",     viewModel.grossProfit,              false),
                ("(-) Labor Cost",     -viewModel.totalLaborCost,          true),
                ("(-) Waste Cost",     -viewModel.totalWasteCost,          true),
                ("(-) Discounts",      -viewModel.discountGiven,           true),
                ("= Est. Net Profit",  viewModel.estimatedNetProfit,       false),
            ]

            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack {
                        Text(row.0)
                            .font(.system(size: 12, weight: row.0.hasPrefix("=") ? .bold : .regular))
                            .foregroundColor(row.0.hasPrefix("=") ? .textPrimary : .textSecondary)
                        Spacer()
                        Text("฿\(fmt(abs(row.1), 0))")
                            .font(.system(size: 12, design: .monospaced))
                            .fontWeight(row.0.hasPrefix("=") ? .bold : .regular)
                            .foregroundColor(row.1 >= 0 ? .appTeal : .appRose)
                    }
                    .padding(.vertical, 7).padding(.horizontal, 8)
                    if row.0.hasPrefix("=") { Divider() }
                }
            }
            .background(Color.appSurfaceHigh)
            .cornerRadius(10)
        }
        .apCard()
    }

    private var topMarginItemsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TOP MARGIN ITEMS")
                .font(.caption).fontWeight(.bold).foregroundColor(.appAccent).tracking(1.0)
            tableHeader(["Item", "Qty", "Revenue", "COGS", "Margin %"])
            Divider()
            ForEach(viewModel.topMarginItems.prefix(10)) { prod in
                HStack {
                    Text(prod.name).frame(maxWidth: .infinity, alignment: .leading).lineLimit(1).fontWeight(.semibold)
                    Text("\(prod.quantity)").frame(width: 40, alignment: .trailing)
                    Text("฿\(fmt(prod.totalRevenue, 0))").foregroundColor(.appTeal).frame(width: 90, alignment: .trailing)
                    Text("฿\(fmt(prod.cogs, 0))").foregroundColor(.appRose).frame(width: 80, alignment: .trailing)
                    Text("\(String(format: "%.1f", prod.grossMarginPct))%")
                        .foregroundColor(prod.grossMarginPct >= 50 ? .appTeal : .appRose)
                        .fontWeight(.bold).frame(width: 70, alignment: .trailing)
                }
                .font(.system(size: 11)).padding(.vertical, 7).padding(.horizontal, 6)
                Divider()
            }
        }
        .apCard()
    }

    private var categoryBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("REVENUE BY CATEGORY")
                .font(.caption).fontWeight(.bold).foregroundColor(.appAccent).tracking(1.0)
            HStack(alignment: .top, spacing: 20) {
                Chart(viewModel.categoryBreakdown) { cat in
                    SectorMark(angle: .value("Rev", cat.revenue), innerRadius: .ratio(0.5), angularInset: 1.5)
                        .cornerRadius(4)
                        .foregroundStyle(by: .value("Category", cat.category))
                }
                .chartForegroundStyleScale([
                    "Main Dishes": Color.appAccent,
                    "Appetizers": Color.appTeal,
                    "Beverages": Color.appRose
                ])
                .frame(width: 130, height: 130)
                .chartLegend(.hidden)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(viewModel.categoryBreakdown) { cat in
                        HStack {
                            Text(cat.category).font(.caption2).foregroundColor(.textSecondary).lineLimit(1)
                            Spacer()
                            Text("฿\(fmt(cat.revenue, 0))")
                                .font(.system(.caption2, design: .monospaced)).fontWeight(.bold)
                            Text("(\(String(format: "%.1f", cat.sharePct))%)")
                                .font(.system(size: 9)).foregroundColor(.textTertiary)
                        }
                    }
                }
            }
        }
        .apCard()
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: TAB 3 — DELIVERY PLATFORMS
    // ─────────────────────────────────────────────────────────────────
    private var deliveryTab: some View {
        ScrollView {
            VStack(spacing: APSpacing.md) {
                // Summary KPIs
                Grid(horizontalSpacing: APSpacing.sm, verticalSpacing: APSpacing.sm) {
                    GridRow {
                        kpiCard("DELIVERY ORDERS",  "\(viewModel.deliveryOrders)",                "จำนวน order delivery",                                         .appAccent)
                        kpiCard("GROSS DELIVERY",   "฿\(fmt(viewModel.deliveryRevenue))",         "ยอดขายรวม delivery",                                           .appAccent)
                        kpiCard("TOTAL GP FEES",    "฿\(fmt(viewModel.totalDeliveryGPFees))",     "GP ที่ถูก platform หัก",                                       .appRose)
                        kpiCard("NET DELIVERY REV", "฿\(fmt(viewModel.netDeliveryRevenue))",      "หลังหัก GP + Ad + Fee",                                        .appTeal)
                    }
                }

                // Platform Breakdown Table
                deliveryPlatformTable

                // Net Margin per Platform Chart
                if !viewModel.deliveryPlatformBreakdown.isEmpty {
                    deliveryMarginChart
                }
            }
            .padding(.bottom, APSpacing.lg)
        }
    }

    private var deliveryPlatformTable: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PLATFORM BREAKDOWN")
                .font(.caption).fontWeight(.bold).foregroundColor(.appAccent).tracking(1.0)

            if viewModel.deliveryPlatformBreakdown.isEmpty {
                emptyLabel("No delivery orders in this period.")
            } else {
                // Header
                HStack {
                    Text("Platform").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Orders").frame(width: 55, alignment: .trailing)
                    Text("Gross").frame(width: 85, alignment: .trailing)
                    Text("GP Fee").frame(width: 80, alignment: .trailing)
                    Text("Ad Fee").frame(width: 75, alignment: .trailing)
                    Text("Net Rev").frame(width: 85, alignment: .trailing)
                    Text("Margin").frame(width: 65, alignment: .trailing)
                }
                .font(.caption2).fontWeight(.bold).foregroundColor(.textSecondary)
                .padding(.vertical, 6).padding(.horizontal, 8)
                Divider()

                ForEach(viewModel.deliveryPlatformBreakdown) { platform in
                    HStack {
                        HStack(spacing: 6) {
                            Circle().fill(platform.brandColor).frame(width: 8, height: 8)
                            Text(platform.brandName).fontWeight(.semibold).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Text("\(platform.orderCount)").frame(width: 55, alignment: .trailing)
                        Text("฿\(fmt(platform.grossRevenue, 0))").foregroundColor(.textPrimary).frame(width: 85, alignment: .trailing)
                        Text("฿\(fmt(platform.gpFees, 0))").foregroundColor(.appRose).frame(width: 80, alignment: .trailing)
                        Text("฿\(fmt(platform.adFees, 0))").foregroundColor(.appRose).frame(width: 75, alignment: .trailing)
                        Text("฿\(fmt(platform.netRevenue, 0))").foregroundColor(.appTeal).fontWeight(.bold).frame(width: 85, alignment: .trailing)
                        Text("\(String(format: "%.1f", platform.effectiveMarginPct))%")
                            .foregroundColor(platform.effectiveMarginPct >= 60 ? .appTeal : .appRose)
                            .fontWeight(.bold).frame(width: 65, alignment: .trailing)
                    }
                    .font(.system(size: 11)).padding(.vertical, 8).padding(.horizontal, 8)
                    Divider()
                }

                // Totals row
                HStack {
                    Text("TOTAL").fontWeight(.bold).frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(viewModel.deliveryOrders)").fontWeight(.bold).frame(width: 55, alignment: .trailing)
                    Text("฿\(fmt(viewModel.deliveryRevenue, 0))").fontWeight(.bold).frame(width: 85, alignment: .trailing)
                    Text("฿\(fmt(viewModel.totalDeliveryGPFees, 0))").foregroundColor(.appRose).fontWeight(.bold).frame(width: 80, alignment: .trailing)
                    Text("฿\(fmt(viewModel.totalDeliveryAdFees, 0))").foregroundColor(.appRose).fontWeight(.bold).frame(width: 75, alignment: .trailing)
                    Text("฿\(fmt(viewModel.netDeliveryRevenue, 0))").foregroundColor(.appTeal).fontWeight(.bold).frame(width: 85, alignment: .trailing)
                    let totalMargin = viewModel.deliveryRevenue > 0 ? viewModel.netDeliveryRevenue / viewModel.deliveryRevenue * 100 : 0
                    Text("\(String(format: "%.1f", totalMargin))%").fontWeight(.bold).foregroundColor(.appTeal).frame(width: 65, alignment: .trailing)
                }
                .font(.system(size: 11)).padding(.vertical, 8).padding(.horizontal, 8)
                .background(Color.appSurfaceHigh).cornerRadius(8)
            }
        }
        .apCard()
    }

    private var deliveryMarginChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("NET MARGIN BY PLATFORM")
                .font(.caption).fontWeight(.bold).foregroundColor(.appAccent).tracking(1.0)

            Chart(viewModel.deliveryPlatformBreakdown) { platform in
                BarMark(
                    x: .value("Platform", platform.brandName),
                    y: .value("Margin %", platform.effectiveMarginPct)
                )
                .foregroundStyle(platform.brandColor.gradient)
                .cornerRadius(5)
                .annotation(position: .top) {
                    Text("\(String(format: "%.0f", platform.effectiveMarginPct))%")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.textSecondary)
                }
            }
            .chartYAxis { AxisMarks(position: .leading) { AxisValueLabel(format: FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0))) } }
            .frame(height: 160)
        }
        .apCard()
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: TAB 4 — MENU INTELLIGENCE
    // ─────────────────────────────────────────────────────────────────
    private var menuTab: some View {
        ScrollView {
            VStack(spacing: APSpacing.md) {
                menuEngineeringCard
                if !viewModel.categoryBreakdown.isEmpty { categoryBreakdownCard }
            }
            .padding(.bottom, APSpacing.lg)
        }
    }

    private var menuEngineeringCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("MENU ENGINEERING MATRIX")
                    .font(.caption).fontWeight(.bold).foregroundColor(.appAccent).tracking(1.0)
                Text("จัดหมวดเมนูตาม Popularity × Profit Margin")
                    .font(.system(size: 10)).foregroundColor(.textTertiary)
            }

            HStack(spacing: 12) {
                ForEach([MenuSegment.star, .plowHorse, .puzzle, .dog], id: \.rawValue) { seg in
                    HStack(spacing: 4) {
                        Circle().fill(seg.color).frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(seg.rawValue).font(.system(size: 9, weight: .bold)).foregroundColor(seg.color)
                            Text(seg.description).font(.system(size: 8)).foregroundColor(.textTertiary)
                        }
                    }
                }
            }
            .padding(.vertical, 6)

            if viewModel.menuEngineeringMatrix.isEmpty {
                emptyLabel("No sales data for menu analysis.")
            } else {
                tableHeader(["Menu Item", "Category", "Qty", "Revenue", "Margin", "Segment"])
                Divider()
                ForEach(viewModel.menuEngineeringMatrix.prefix(20)) { item in
                    HStack {
                        Text(item.product.name).fontWeight(.semibold).frame(maxWidth: .infinity, alignment: .leading).lineLimit(1)
                        Text(item.product.category).foregroundColor(.textSecondary).frame(width: 100, alignment: .leading).lineLimit(1)
                        Text("\(item.product.quantity)").frame(width: 40, alignment: .trailing)
                        Text("฿\(fmt(item.product.totalRevenue, 0))").foregroundColor(.appTeal).frame(width: 85, alignment: .trailing)
                        Text(item.product.cogs > 0 ? "\(String(format: "%.1f", item.product.grossMarginPct))%" : "–")
                            .foregroundColor(item.product.grossMarginPct >= 50 ? .appTeal : .appRose)
                            .frame(width: 60, alignment: .trailing)
                        Text(item.segment.rawValue)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(item.segment.color)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(item.segment.color.opacity(0.12))
                            .cornerRadius(5)
                            .frame(width: 100, alignment: .trailing)
                    }
                    .font(.system(size: 11)).padding(.vertical, 7).padding(.horizontal, 6)
                    Divider()
                }
            }
        }
        .apCard()
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: TAB 5 — INVENTORY
    // ─────────────────────────────────────────────────────────────────
    private var inventoryTab: some View {
        ScrollView {
            VStack(spacing: APSpacing.md) {
                // KPIs
                Grid(horizontalSpacing: APSpacing.sm, verticalSpacing: APSpacing.sm) {
                    GridRow {
                        kpiCard("STOCK VALUE",       "฿\(fmt(viewModel.totalInventoryValue))", "มูลค่าสต็อกทั้งหมด",              .appTeal)
                        kpiCard("COGS USED",         "฿\(fmt(viewModel.totalCOGS))",           "ต้นทุนวัตถุดิบที่ใช้ไป",          .appRose)
                        kpiCard("WASTE COST",        "฿\(fmt(viewModel.totalWasteCost))",      "Loss / Waste",                    .appRose)
                        kpiCard("TURNOVER RATE",     String(format: "%.2fx", viewModel.inventoryTurnoverRate), "COGS / Stock Value", .appAccent)
                    }
                }

                // Low Stock Alerts
                if !viewModel.lowStockItems.isEmpty {
                    lowStockCard
                }

                // Theoretical Usage
                if !viewModel.inventoryUsageSummary.isEmpty {
                    inventoryUsageCard
                }

                // Waste Log
                if !viewModel.wasteTransactions.isEmpty {
                    wasteLogCard
                }
            }
            .padding(.bottom, APSpacing.lg)
        }
    }

    private var lowStockCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.appRose)
                Text("LOW STOCK ALERTS")
                    .font(.caption).fontWeight(.bold).foregroundColor(.appRose).tracking(1.0)
                Spacer()
                Text("\(viewModel.lowStockItems.count) items")
                    .font(.caption2).foregroundColor(.appRose)
            }
            Divider()
            ForEach(viewModel.lowStockItems) { item in
                HStack {
                    Circle()
                        .fill(Color.appRose)
                        .frame(width: 6, height: 6)
                    Text(item.name).font(.system(size: 11)).fontWeight(.semibold)
                    Spacer()
                    Text("\(String(format: "%.2f", item.currentQty)) \(item.unit)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.appRose)
                        .fontWeight(.bold)
                    Text("/ min \(String(format: "%.0f", item.reorderLevel))")
                        .font(.system(size: 9)).foregroundColor(.textTertiary)
                }
                .padding(.vertical, 5)
                Divider()
            }
        }
        .apCard()
    }

    private var inventoryUsageCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("THEORETICAL INGREDIENT USAGE")
                .font(.caption).fontWeight(.bold).foregroundColor(.appAccent).tracking(1.0)
            Text("คำนวณจากสูตรอาหาร × ยอดขาย")
                .font(.system(size: 10)).foregroundColor(.textTertiary)

            tableHeader(["Ingredient", "Used (Theory)", "Cost Used"])
            Divider()
            ForEach(viewModel.inventoryUsageSummary.prefix(15)) { item in
                HStack {
                    Text(item.name).fontWeight(.semibold).frame(maxWidth: .infinity, alignment: .leading).lineLimit(1)
                    Text("\(String(format: "%.2f", item.theoreticalUsed)) \(item.unit)")
                        .foregroundColor(.textSecondary).frame(width: 130, alignment: .trailing)
                    Text("฿\(fmt(item.cost, 0))").foregroundColor(.appRose).fontWeight(.bold).frame(width: 100, alignment: .trailing)
                }
                .font(.system(size: 11)).padding(.vertical, 7).padding(.horizontal, 6)
                Divider()
            }
        }
        .apCard()
    }

    private var wasteLogCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WASTE LOG")
                .font(.caption).fontWeight(.bold).foregroundColor(.appAccent).tracking(1.0)
            tableHeader(["Ingredient", "Qty", "Cost", "Date"])
            Divider()
            ForEach(viewModel.wasteTransactions.prefix(15)) { waste in
                HStack {
                    Text(waste.itemName).fontWeight(.semibold).frame(maxWidth: .infinity, alignment: .leading).lineLimit(1)
                    Text("\(String(format: "%.2f", waste.quantity)) \(waste.unit)").foregroundColor(.textSecondary).frame(width: 100, alignment: .trailing)
                    Text("฿\(fmt(waste.cost, 0))").foregroundColor(.appRose).fontWeight(.bold).frame(width: 80, alignment: .trailing)
                    Text(waste.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 9)).foregroundColor(.textTertiary).frame(width: 90, alignment: .trailing)
                }
                .font(.system(size: 11)).padding(.vertical, 7).padding(.horizontal, 6)
                Divider()
            }
        }
        .apCard()
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: TAB 6 — STAFF
    // ─────────────────────────────────────────────────────────────────
    private var staffTab: some View {
        ScrollView {
            VStack(spacing: APSpacing.md) {
                // Labor KPIs
                Grid(horizontalSpacing: APSpacing.sm, verticalSpacing: APSpacing.sm) {
                    GridRow {
                        kpiCard("TOTAL LABOR COST",    "฿\(fmt(viewModel.totalLaborCost))",          "ค่าแรงรวม",                                                       .appAccent)
                        kpiCard("LABOR HOURS",         String(format: "%.1f hrs", viewModel.totalLaborHours), "ชั่วโมงทำงานรวม",                                .appTeal)
                        kpiCard("LABOR COST %",        "\(String(format: "%.1f", viewModel.laborCostPct))%",  "% ของ Revenue",                                   viewModel.laborCostPct <= 30 ? .appTeal : .appRose)
                        kpiCard("REV/LABOR HOUR",      "฿\(fmt(viewModel.revenuePerLaborHour, 0))",   "Revenue per Hr",                                          .appTeal)
                    }
                }

                // Cashier Performance
                cashierPerformanceCard

                // Staff Labor Breakdown
                if !viewModel.staffLaborBreakdown.isEmpty {
                    staffLaborCard
                }
            }
            .padding(.bottom, APSpacing.lg)
        }
    }

    private var cashierPerformanceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CASHIER PERFORMANCE")
                .font(.caption).fontWeight(.bold).foregroundColor(.appAccent).tracking(1.0)

            if viewModel.cashierPerformance.isEmpty {
                emptyLabel("No orders recorded.")
            } else {
                tableHeader(["Cashier", "Orders", "Revenue", "Items Sold", "Avg Ticket"])
                Divider()
                ForEach(viewModel.cashierPerformance) { cashier in
                    HStack {
                        HStack(spacing: 6) {
                            Image(systemName: "person.circle.fill")
                                .foregroundColor(.appAccent).font(.system(size: 14))
                            Text(cashier.name).fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(cashier.orderCount)").frame(width: 55, alignment: .trailing)
                        Text("฿\(fmt(cashier.revenue, 0))").foregroundColor(.appTeal).fontWeight(.bold).frame(width: 90, alignment: .trailing)
                        Text("\(cashier.itemsSold)").frame(width: 75, alignment: .trailing)
                        Text("฿\(fmt(cashier.avgTicket, 0))").foregroundColor(.appAccent).frame(width: 85, alignment: .trailing)
                    }
                    .font(.system(size: 11)).padding(.vertical, 8).padding(.horizontal, 6)
                    Divider()
                }
            }
        }
        .apCard()
    }

    private var staffLaborCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LABOR COST BREAKDOWN")
                .font(.caption).fontWeight(.bold).foregroundColor(.appAccent).tracking(1.0)
            tableHeader(["Employee", "Hours", "OT (hrs)", "Labor Cost"])
            Divider()
            ForEach(viewModel.staffLaborBreakdown) { staff in
                HStack {
                    Text(staff.name).fontWeight(.semibold).frame(maxWidth: .infinity, alignment: .leading)
                    Text(String(format: "%.1f h", staff.hoursWorked)).frame(width: 70, alignment: .trailing)
                    Text(staff.overtimeMinutes > 0 ? String(format: "%.1f h", staff.overtimeHours) : "–")
                        .foregroundColor(staff.overtimeMinutes > 0 ? .appRose : .textTertiary)
                        .frame(width: 70, alignment: .trailing)
                    Text("฿\(fmt(staff.laborCost, 0))").foregroundColor(.appAccent).fontWeight(.bold).frame(width: 90, alignment: .trailing)
                }
                .font(.system(size: 11)).padding(.vertical, 7).padding(.horizontal, 6)
                Divider()
            }
        }
        .apCard()
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: HELPERS
    // ─────────────────────────────────────────────────────────────────
    private func kpiCard(_ title: String, _ value: String, _ subtitle: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 8, weight: .bold)).foregroundColor(.textTertiary).tracking(0.5)
            Text(value).font(.title3).fontWeight(.bold).foregroundColor(color).minimumScaleFactor(0.6).lineLimit(1)
            Text(subtitle).font(.system(size: 9)).foregroundColor(.textSecondary).lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appSurface)
        .cornerRadius(APRadius.md)
        .overlay(RoundedRectangle(cornerRadius: APRadius.md).stroke(Color.appBorderSubtle, lineWidth: 1))
    }

    private func tableHeader(_ cols: [String]) -> some View {
        HStack {
            Text(cols[0]).frame(maxWidth: .infinity, alignment: .leading)
            ForEach(cols.dropFirst(), id: \.self) { col in
                Text(col).frame(width: col == cols.last ? 80 : 90, alignment: .trailing)
            }
        }
        .font(.caption2).fontWeight(.bold).foregroundColor(.textSecondary)
        .padding(.vertical, 6).padding(.horizontal, 6)
    }

    private func emptyLabel(_ text: String) -> some View {
        Text(text).font(.caption).foregroundColor(.textTertiary)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .center)
    }

    private func orderTypePill(_ type: String) -> some View {
        let (label, color): (String, Color) = {
            switch type {
            case "take_out":  return ("🥡 TO",  .appAccent)
            case "delivery":  return ("🚚 DEL", .appRose)
            default:          return ("🪑 DI",  .appTeal)
            }
        }()
        return Text(label)
            .font(.system(size: 8, weight: .bold)).foregroundColor(color)
            .padding(.horizontal, 4).padding(.vertical, 1)
            .background(color.opacity(0.12)).cornerRadius(4)
    }

    private func fmt(_ value: Double, _ decimals: Int = 2) -> String {
        value.formatted(.number.precision(.fractionLength(decimals)))
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: Actions
    // ─────────────────────────────────────────────────────────────────
    private func refreshData() {
        viewModel.updateAnalytics(
            orders: allOrders,
            inventoryItems: allInventory,
            employees: allEmployees,
            timecards: allTimecards
        )
        APHaptic.trigger()
    }

    private func triggerEntranceAnimations() {
        withAnimation(.easeOut(duration: 0.35)) { animateKPIs = true }
        withAnimation(.easeOut(duration: 0.5).delay(0.1)) { animateCharts = true }
    }

    @MainActor
    private func shareFullReportAction() {
        APHaptic.trigger()
        let reportView = SalesPDFReportView(
            title: viewModel.summaryMode == .daily ? "Daily Sales Summary" : "Monthly Sales Summary",
            subtitle: viewModel.summaryMode == .daily
                ? viewModel.selectedDate.formatted(date: .long, time: .omitted)
                : "\(viewModel.monthsList[viewModel.selectedMonth - 1]) \(viewModel.selectedYear)",
            generatedAt: Date().formatted(date: .abbreviated, time: .shortened),
            grossSales: viewModel.grossRevenue,
            netSales: viewModel.netRevenue,
            tax: viewModel.taxCollected,
            serviceCharge: viewModel.serviceChargeCollected,
            discount: viewModel.discountGiven,
            totalOrders: viewModel.totalOrders,
            averageTicket: viewModel.averageTicketValue,
            totalItems: viewModel.totalItemsSold,
            payments: viewModel.paymentBreakdown,
            products: viewModel.productSales
        )
        if let url = exportToPDF(view: reportView, filename: "AlphaPos_Sales_Report") {
            self.generatedPDFURL = url; self.showingShareSheet = true
        }
    }

    @MainActor
    private func shareProductReportAction() {
        APHaptic.trigger()
        let reportView = ProductSalesPDFView(
            title: viewModel.summaryMode == .daily ? "Daily Report" : "Monthly Report",
            subtitle: viewModel.summaryMode == .daily
                ? viewModel.selectedDate.formatted(date: .long, time: .omitted)
                : "\(viewModel.monthsList[viewModel.selectedMonth - 1]) \(viewModel.selectedYear)",
            generatedAt: Date().formatted(date: .abbreviated, time: .shortened),
            products: viewModel.productSales
        )
        if let url = exportToPDF(view: reportView, filename: "AlphaPos_Product_Sales_Report") {
            self.generatedPDFURL = url; self.showingShareSheet = true
        }
    }

    @MainActor
    private func exportToPDF<Content: View>(view: Content, filename: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(filename).pdf")
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { return nil }
        ctx.beginPDFPage(nil)
        let renderer = ImageRenderer(content: view)
        renderer.render { size, context in
            let scale = min(612 / size.width, 792 / size.height)
            ctx.translateBy(x: (612 - size.width * scale) / 2, y: (792 - size.height * scale) / 2)
            ctx.scaleBy(x: scale, y: scale)
            context(ctx)
        }
        ctx.endPDFPage()
        ctx.closePDF()
        return url
    }
}
