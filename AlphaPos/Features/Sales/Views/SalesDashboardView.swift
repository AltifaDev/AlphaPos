import SwiftUI
import SwiftData
import Charts

struct SalesDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allOrders: [Order]
    
    @State private var viewModel = SalesViewModel()
    
    // Animation triggers
    @State private var animateKPIs = false
    @State private var animateCharts = false
    
    // PDF sharing sheets
    @State private var generatedPDFURL: URL? = nil
    @State private var showingShareSheet = false
    
    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            
            GeometryReader { geo in
                HStack(spacing: APSpacing.md) {
                    // ── LEFT COLUMN: CONTROLS & SIDE PANELS (Width: 340) ─────────
                    leftPanelContainer
                        .frame(width: 340)
                    
                    // ── RIGHT COLUMN: ANALYTICS CONTENT (Expanding) ───────────────
                    VStack(alignment: .leading, spacing: APSpacing.md) {
                        // Metrics / KPIs Grid
                        metricsGridSection
                            .scaleEffect(animateKPIs ? 1.0 : 0.98)
                            .opacity(animateKPIs ? 1.0 : 0.7)
                        
                        // Trends Chart
                        trendsChartCard
                            .opacity(animateCharts ? 1.0 : 0.0)
                            .offset(y: animateCharts ? 0 : 15)
                        
                        // Itemized Product Sales Table
                        productSalesCard
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(APSpacing.md)
            }
        }
        .navigationTitle("Sales & Analytics")
        .apNavBar(background: Color.appBackground)
        .onAppear {
            refreshData()
            triggerEntranceAnimations()
        }
        .onChange(of: viewModel.summaryMode) { refreshData() }
        .onChange(of: viewModel.selectedDate) { refreshData() }
        .onChange(of: viewModel.selectedMonth) { refreshData() }
        .onChange(of: viewModel.selectedYear) { refreshData() }
        .sheet(isPresented: $showingShareSheet, content: {
            if let url = generatedPDFURL {
                ShareSheet(activityItems: [url])
                    .presentationDetents([.medium, .large])
            }
        })
    }
    
    // MARK: - Left Panel Container
    
    private var leftPanelContainer: some View {
        VStack(spacing: APSpacing.md) {
            // Period selector card
            VStack(alignment: .leading, spacing: 14) {
                Text("REPORTING PERIOD")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.appAccent)
                    .tracking(1.0)
                
                Picker("Summary Mode", selection: $viewModel.summaryMode) {
                    Text("Daily Summary").tag(SalesViewModel.SummaryMode.daily)
                    Text("Monthly Summary").tag(SalesViewModel.SummaryMode.monthly)
                }
                .pickerStyle(.segmented)
                
                if viewModel.summaryMode == .daily {
                    DatePicker("Target Date", selection: $viewModel.selectedDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .foregroundColor(.textPrimary)
                } else {
                    HStack(spacing: 8) {
                        Picker("Month", selection: $viewModel.selectedMonth) {
                            ForEach(1...12, id: \.self) { monthIndex in
                                Text(viewModel.monthsList[monthIndex - 1]).tag(monthIndex)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(.appAccent)
                        
                        Spacer()
                        
                        Picker("Year", selection: $viewModel.selectedYear) {
                            ForEach(viewModel.availableYears, id: \.self) { year in
                                Text("\(year)").tag(year)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(.appAccent)
                    }
                }
            }
            .apCard()
            
            // Payment Breakdown Card
            paymentBreakdownCard
            
            // Order History Log Card
            ordersHistoryLogCard
        }
    }
    
    // MARK: - Right Column Sections
    
    private var metricsGridSection: some View {
        Grid(horizontalSpacing: APSpacing.md, verticalSpacing: APSpacing.md) {
            GridRow {
                kpiCard(title: "TOTAL REVENUE", value: "฿\(viewModel.grossRevenue.formatted(.number.precision(.fractionLength(2))))", subtitle: "Net: ฿\(viewModel.netRevenue.formatted(.number.precision(.fractionLength(0))))", color: .appTeal)
                kpiCard(title: "TOTAL ORDERS", value: "\(viewModel.totalOrders)", subtitle: "Avg Ticket: ฿\(viewModel.averageTicketValue.formatted(.number.precision(.fractionLength(0))))", color: .appAccent)
                kpiCard(title: "ITEMS SOLD", value: "\(viewModel.totalItemsSold)", subtitle: "Total ordered items", color: .appTeal)
                kpiCard(title: "DISCOUNTS GIVEN", value: "฿\(viewModel.discountGiven.formatted(.number.precision(.fractionLength(2))))", subtitle: "Total loyalty price drop", color: .appRose)
            }
        }
    }
    
    private var trendsChartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SALES REVENUE TREND")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.appAccent)
                .tracking(1.0)
            
            if viewModel.summaryMode == .daily {
                Chart(viewModel.hourlyTrend) { point in
                    BarMark(
                        x: .value("Hour", point.hourLabel),
                        y: .value("Revenue", point.revenue)
                    )
                    .foregroundStyle(Color.appAccent.gradient)
                    .cornerRadius(4)
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: 160)
            } else {
                Chart(viewModel.dailyTrend) { point in
                    LineMark(
                        x: .value("Day", point.dayLabel),
                        y: .value("Revenue", point.revenue)
                    )
                    .foregroundStyle(Color.appAccent)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 3))
                    
                    AreaMark(
                        x: .value("Day", point.dayLabel),
                        y: .value("Revenue", point.revenue)
                    )
                    .foregroundStyle(Color.appAccent.opacity(0.15).gradient)
                    .interpolationMethod(.catmullRom)
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: 160)
            }
        }
        .apCard()
    }
    
    private var paymentBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PAYMENT METHOD BREAKDOWN")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.appAccent)
                .tracking(1.0)
            
            if viewModel.paymentBreakdown.isEmpty {
                Spacer()
                Text("No payments recorded.")
                    .font(.caption)
                    .foregroundColor(.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                HStack(spacing: 20) {
                    Chart(viewModel.paymentBreakdown) { point in
                        SectorMark(
                            angle: .value("Revenue", point.amount),
                            innerRadius: .ratio(0.6),
                            angularInset: 1.5
                        )
                        .cornerRadius(5)
                        .foregroundStyle(by: .value("Method", point.method))
                    }
                    .frame(width: 120, height: 120)
                    .chartLegend(.hidden)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(viewModel.paymentBreakdown) { pt in
                            HStack {
                                Circle()
                                    .fill(pt.method.contains("Cash") ? Color.appTeal : (pt.method.contains("Credit") ? Color.appAccent : Color.appTeal.opacity(0.6)))
                                    .frame(width: 6, height: 6)
                                Text(pt.method)
                                    .font(.caption2)
                                    .foregroundColor(.textSecondary)
                                Spacer()
                                Text("฿\(pt.amount.formatted(.number.precision(.fractionLength(0))))")
                                    .font(.system(.caption2, design: .monospaced))
                                    .fontWeight(.bold)
                                    .foregroundColor(.textPrimary)
                            }
                        }
                    }
                }
            }
        }
        .apCard()
        .frame(maxHeight: 180)
    }
    
    private var ordersHistoryLogCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TRANSACTION LOG")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.appAccent)
                .tracking(1.0)
            
            if viewModel.historicalOrders.isEmpty {
                Spacer()
                Text("No matching orders found.")
                    .font(.caption)
                    .foregroundColor(.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(viewModel.historicalOrders) { order in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(order.orderNumber)
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundColor(.textPrimary)
                                    Text("Table \(order.tableSession?.table?.tableNumber ?? "12") • \(order.createdAt.formatted(date: .omitted, time: .shortened))")
                                        .font(.system(size: 9))
                                        .foregroundColor(.textSecondary)
                                }
                                Spacer()
                                Text("฿\(order.total.formatted(.number.precision(.fractionLength(0))))")
                                    .font(.system(.caption, design: .monospaced))
                                    .fontWeight(.bold)
                                    .foregroundColor(.appTeal)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
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
    
    private var productSalesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("PRODUCT SALES REPORT")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.appAccent)
                    .tracking(1.0)
                
                Spacer()
                
                // Export Product Sales PDF Action
                Button(action: shareProductReportAction) {
                    Label("Export Product List (PDF)", systemImage: "square.and.arrow.up")
                        .font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundColor(.appAccent)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.appAccent.opacity(0.1))
                .cornerRadius(6)
            }
            
            if viewModel.productSales.isEmpty {
                Spacer()
                Text("No item sales recorded.")
                    .font(.caption)
                    .foregroundColor(.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        // Table Header
                        HStack {
                            Text("Item Name")
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("Category")
                                .frame(width: 120, alignment: .leading)
                            Text("Qty Sold")
                                .frame(width: 80, alignment: .trailing)
                            Text("Revenue")
                                .frame(width: 100, alignment: .trailing)
                        }
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.textSecondary)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        
                        Divider()
                            .background(Color.appDivider)
                        
                        ForEach(viewModel.productSales.prefix(10)) { prod in
                            HStack {
                                Text(prod.name)
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .lineLimit(1)
                                Text(prod.category)
                                    .foregroundColor(.textSecondary)
                                    .frame(width: 120, alignment: .leading)
                                Text("\(prod.quantity)")
                                    .fontWeight(.bold)
                                    .foregroundColor(.textPrimary)
                                    .frame(width: 80, alignment: .trailing)
                                Text("฿\(prod.totalRevenue.formatted(.number.precision(.fractionLength(0))))")
                                    .foregroundColor(.appTeal)
                                    .fontWeight(.bold)
                                    .frame(width: 100, alignment: .trailing)
                            }
                            .font(.system(size: 11))
                            .padding(.vertical, 8)
                            .padding(.horizontal, 8)
                            
                            Divider()
                                .background(Color.appDivider)
                        }
                    }
                }
            }
            
            // Full report action button
            Button(action: shareFullReportAction) {
                Label("Export Full Summary Report (PDF)", systemImage: "doc.plaintext.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .apGradientButton(gradient: APGradient.accent, shadow: APShadow.glow)
            .padding(.top, 4)
        }
        .apCard()
        .frame(maxHeight: .infinity)
    }
    
    // MARK: - KPI Card Helper
    
    private func kpiCard(title: String, value: String, subtitle: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.textTertiary)
                .tracking(0.5)
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(subtitle)
                .font(.system(size: 9))
                .foregroundColor(.textSecondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appSurface)
        .cornerRadius(APRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: APRadius.md)
                .stroke(Color.appBorderSubtle, lineWidth: 1)
        )
    }
    
    // MARK: - Actions
    
    private func refreshData() {
        viewModel.updateAnalytics(orders: allOrders)
        APHaptic.trigger()
    }
    
    private func triggerEntranceAnimations() {
        withAnimation(.easeOut(duration: 0.35)) {
            animateKPIs = true
        }
        withAnimation(.easeOut(duration: 0.5).delay(0.1)) {
            animateCharts = true
        }
    }
    
    @MainActor
    private func shareFullReportAction() {
        APHaptic.trigger()
        
        let generatedDateStr = Date().formatted(date: .abbreviated, time: .shortened)
        let reportTitle = viewModel.summaryMode == .daily ? "Daily Sales Summary" : "Monthly Sales Summary"
        
        let dateRangeStr: String
        if viewModel.summaryMode == .daily {
            dateRangeStr = viewModel.selectedDate.formatted(date: .long, time: .omitted)
        } else {
            dateRangeStr = "\(viewModel.monthsList[viewModel.selectedMonth - 1]) \(viewModel.selectedYear)"
        }
        
        let reportView = SalesPDFReportView(
            title: reportTitle,
            subtitle: dateRangeStr,
            generatedAt: generatedDateStr,
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
            self.generatedPDFURL = url
            self.showingShareSheet = true
        }
    }
    
    @MainActor
    private func shareProductReportAction() {
        APHaptic.trigger()
        
        let generatedDateStr = Date().formatted(date: .abbreviated, time: .shortened)
        let reportTitle = viewModel.summaryMode == .daily ? "Daily Report" : "Monthly Report"
        
        let dateRangeStr: String
        if viewModel.summaryMode == .daily {
            dateRangeStr = viewModel.selectedDate.formatted(date: .long, time: .omitted)
        } else {
            dateRangeStr = "\(viewModel.monthsList[viewModel.selectedMonth - 1]) \(viewModel.selectedYear)"
        }
        
        let reportView = ProductSalesPDFView(
            title: reportTitle,
            subtitle: dateRangeStr,
            generatedAt: generatedDateStr,
            products: viewModel.productSales
        )
        
        if let url = exportToPDF(view: reportView, filename: "AlphaPos_Product_Sales_Report") {
            self.generatedPDFURL = url
            self.showingShareSheet = true
        }
    }
    
    @MainActor
    private func exportToPDF<Content: View>(view: Content, filename: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(filename).pdf")
        var box = CGRect(x: 0, y: 0, width: 612, height: 792) // Letter page format
        
        guard let pdfContext = CGContext(url as CFURL, mediaBox: &box, nil) else {
            return nil
        }
        
        pdfContext.beginPDFPage(nil)
        
        let renderer = ImageRenderer(content: view)
        renderer.render { size, context in
            let scale = min(612 / size.width, 792 / size.height)
            let xOffset = (612 - size.width * scale) / 2
            let yOffset = (792 - size.height * scale) / 2
            
            pdfContext.translateBy(x: xOffset, y: yOffset)
            pdfContext.scaleBy(x: scale, y: scale)
            context(pdfContext)
        }
        
        pdfContext.endPDFPage()
        pdfContext.closePDF()
        
        return url
    }
}
