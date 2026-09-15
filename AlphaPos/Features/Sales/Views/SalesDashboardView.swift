// SalesDashboardView.swift
// AlphaPos — Financials & Profit/Loss (P&L) Executive Dashboard
// Redesigned with Native iPadOS 27 Design System, fluid animations, and 100% dynamic bilingual localization.

import SwiftUI
import SwiftData
import Charts

// ─────────────────────────────────────────────────────────────────────
// MARK: - Enterprise Financials & P&L Dashboard
// ─────────────────────────────────────────────────────────────────────

struct SalesDashboardView: View {
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var lm: LocalizationManager
    @AppStorage(BranchContext.storageKey) private var activeBranchId = ""
    @AppStorage(GovernmentSupportProgram.enabledSettingsKey) private var thaiChuaThaiPlusEnabled = true

    @Query private var allOrders: [Order]
    @Query private var allInventory: [InventoryItem]
    @Query private var allEmployees: [Employee]
    @Query private var allTimecards: [Timecard]
    @Query(filter: #Predicate<Expense> { !$0.isDeleted }) private var allExpenses: [Expense]
    @Query(filter: #Predicate<InventoryTransaction> { !$0.isDeleted })
    private var inventoryLedger: [InventoryTransaction]
    @Query(sort: \RegisterSession.openedAt, order: .reverse) private var registerSessions: [RegisterSession]
    @Query(filter: #Predicate<FinancialEvent> { !$0.isDeleted }) private var financialEvents: [FinancialEvent]

    @State private var viewModel = SalesViewModel()
    @State private var selectedTab: AnalyticsTab = .overview
    @State private var animateKPIs = false
    @State private var animateCharts = false
    @State private var generatedPDFURL: URL? = nil
    @State private var showingShareSheet = false

    private var isThai: Bool {
        lm.currentLanguage == .thai
    }

    enum AnalyticsTab: String, CaseIterable, Identifiable {
        case overview      = "Overview"
        case profitability = "P&L"
        case delivery      = "Delivery"
        case menu          = "Menu"
        case inventory     = "Inventory"
        case staff         = "Staff"

        var id: String { rawValue }

        func localizedName(isThai: Bool) -> String {
            switch self {
            case .overview:      return isThai ? "ภาพรวม" : "Overview"
            case .profitability: return isThai ? "งบกำไร-ขาดทุน" : "P&L Statement"
            case .delivery:      return isThai ? "เดลิเวอรี" : "Delivery"
            case .menu:          return isThai ? "วิเคราะห์เมนู" : "Menu Margin"
            case .inventory:     return isThai ? "คลังและของเสีย" : "Inventory & Waste"
            case .staff:         return isThai ? "ประสิทธิภาพพนักงาน" : "Labor & Staff"
            }
        }

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

            ScrollView {
                VStack(spacing: APSpacing.md) {
                    // 2. Executive 4-Pillars Financial Strip
                    executiveKPIStrip

                    // 3. Sub-Navigation Tabs
                    analyticsTabBar

                    // 4. Tab Content Router
                    tabContent
                }
                .padding(.horizontal, APSpacing.md)
                .padding(.top, APSpacing.xs)
                .padding(.bottom, APSpacing.xl)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                HStack(spacing: 8) {
                    Text(isThai ? "การเงินและกำไร-ขาดทุน" : "Financials & P&L")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.textPrimary)
                }
            }
            ToolbarItem(placement: .principal) {
                Picker("", selection: $viewModel.summaryMode) {
                    Text(isThai ? "ตามกะ" : "Shift").tag(SalesViewModel.SummaryMode.shift)
                    Text(isThai ? "รายวัน" : "Daily").tag(SalesViewModel.SummaryMode.daily)
                    Text(isThai ? "รายเดือน" : "Monthly").tag(SalesViewModel.SummaryMode.monthly)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 8) {
                    periodSpecificControls

                    Button {
                        APHaptic.selection()
                        refreshData()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.textSecondary)
                            .frame(width: 32, height: 32)
                            .background(Color.appSurface)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.appBorderSubtle, lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    Menu {
                        Button(action: shareFullReportAction) {
                            Label(isThai ? "รายงานสรุปการเงิน (Executive PDF)" : "Executive Financial Summary PDF", systemImage: "doc.plaintext.fill")
                        }
                        Button(action: shareProductReportAction) {
                            Label(isThai ? "รายงานยอดขายสินค้า (Product PDF)" : "Product Sales Report PDF", systemImage: "chart.bar.doc.horizontal")
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 12, weight: .bold))
                            Text(isThai ? "ส่งออก PDF" : "Export PDF")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .foregroundColor(.white)
                        .background(Color.appAccent)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .onAppear {
            refreshData()
            triggerEntranceAnimations()
        }
        .onChange(of: viewModel.summaryMode) { refreshData() }
        .onChange(of: viewModel.selectedRegisterSessionId) {
            configureSelectedShift()
            refreshData()
        }
        .onChange(of: viewModel.selectedDate)  { refreshData() }
        .onChange(of: viewModel.selectedMonth) { refreshData() }
        .onChange(of: viewModel.selectedYear)  { refreshData() }
        .onChange(of: financialEvents.count)   { refreshData() }
        .sheet(isPresented: $showingShareSheet) {
            if let url = generatedPDFURL {
                ShareSheet(activityItems: [url]).presentationDetents([.medium, .large])
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - 1. Native Top Header & Period Controls
    // ─────────────────────────────────────────────────────────────────

    private var financialTopBar: some View {
        HStack(alignment: .center, spacing: 14) {
            // Title & Subtitle Badge
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(LinearGradient(colors: [Color.appAccent, Color(hex: "6366F1")], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 30, height: 30)
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    }

                    Text(isThai ? "การเงินและกำไร-ขาดทุน" : "Financials & P&L")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.textPrimary)

                    Text("P&L EXECUTIVE")
                        .font(.system(size: 9, weight: .black))
                        .foregroundColor(.appAccent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.appAccent.opacity(0.12))
                        .clipShape(Capsule())
                }

                Text(heroPeriodLabel + " • " + (isThai ? "วิเคราะห์ต้นทุน กำไรสุทธิ และผลประกอบการ" : "Profit & Loss, Food Cost & Margin Analytics"))
                    .font(.system(size: 11))
                    .foregroundColor(.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            // Period Selector (Shift / Daily / Monthly)
            Picker("", selection: $viewModel.summaryMode) {
                Text(isThai ? "ตามกะ" : "Shift").tag(SalesViewModel.SummaryMode.shift)
                Text(isThai ? "รายวัน" : "Daily").tag(SalesViewModel.SummaryMode.daily)
                Text(isThai ? "รายเดือน" : "Monthly").tag(SalesViewModel.SummaryMode.monthly)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 280)

            // Date / Shift Picker Control
            periodSpecificControls

            // Quick Action Buttons
            HStack(spacing: 8) {
                Button {
                    APHaptic.selection()
                    refreshData()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.textSecondary)
                        .padding(8)
                        .background(Color.appSurface)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.appBorderSubtle, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .hoverEffect(.lift)

                Menu {
                    Button(action: shareFullReportAction) {
                        Label(isThai ? "รายงานสรุปการเงิน (Executive PDF)" : "Executive Financial Summary PDF", systemImage: "doc.plaintext.fill")
                    }
                    Button(action: shareProductReportAction) {
                        Label(isThai ? "รายงานยอดขายสินค้า (Product PDF)" : "Product Sales Report PDF", systemImage: "chart.bar.doc.horizontal")
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 12, weight: .bold))
                        Text(isThai ? "ส่งออก PDF" : "Export PDF")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .foregroundColor(.white)
                    .background(Color.appAccent)
                    .clipShape(Capsule())
                    .shadow(color: Color.appAccent.opacity(0.25), radius: 4, x: 0, y: 2)
                }
                .buttonStyle(.plain)
                .hoverEffect(.lift)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.appBorderSubtle, lineWidth: 1))
    }

    @ViewBuilder
    private var periodSpecificControls: some View {
        switch viewModel.summaryMode {
        case .shift:
            Menu {
                ForEach(branchSessions) { session in
                    Button {
                        viewModel.selectedRegisterSessionId = session.id
                        configureSelectedShift()
                        refreshData()
                    } label: {
                        HStack {
                            Text(shiftLabel(session))
                            if viewModel.selectedRegisterSessionId == session.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "clock.badge.checkmark")
                        .font(.system(size: 12))
                        .foregroundColor(.appAccent)
                    Text(branchSessions.first(where: { $0.id == viewModel.selectedRegisterSessionId }).map { shiftLabel($0) } ?? (isThai ? "เลือกกะ" : "Select shift"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(.textTertiary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.appSurfaceHigh)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.appBorderSubtle, lineWidth: 1))
            }
            .buttonStyle(.plain)

        case .daily:
            DatePicker("", selection: $viewModel.selectedDate, displayedComponents: .date)
                .datePickerStyle(.compact)
                .labelsHidden()

        case .monthly:
            HStack(spacing: 6) {
                Picker("", selection: $viewModel.selectedMonth) {
                    ForEach(1...12, id: \.self) { i in
                        Text(viewModel.monthsList[i - 1]).tag(i)
                    }
                }
                .pickerStyle(.menu)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color.appSurfaceHigh)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Picker("", selection: $viewModel.selectedYear) {
                    ForEach(viewModel.availableYears, id: \.self) { y in
                        Text("\(y)").tag(y)
                    }
                }
                .pickerStyle(.menu)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color.appSurfaceHigh)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - 2. Executive 4-Pillars Financial Strip
    // ─────────────────────────────────────────────────────────────────

    private var executiveKPIStrip: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                // Pillar 1: Net Revenue
                executiveCard(
                    icon: "banknote.fill",
                    iconColor: .appAccent,
                    title: isThai ? "รายได้สุทธิ (Net Revenue)" : "Net Revenue",
                    primaryValue: "฿\(fmt(viewModel.netRevenue, 0))",
                    primaryColor: .textPrimary,
                    tagLabel: isThai ? "\(viewModel.totalOrders) ออเดอร์" : "\(viewModel.totalOrders) orders",
                    tagColor: .appAccent,
                    subtext1: isThai ? "ยอดขายรวม ฿\(fmt(viewModel.grossRevenue, 0))" : "Gross Sales ฿\(fmt(viewModel.grossRevenue, 0))",
                    subtext2: isThai ? "เฉลี่ย ฿\(fmt(viewModel.averageTicketValue, 0)) / บิล" : "Avg ฿\(fmt(viewModel.averageTicketValue, 0)) / ticket"
                )

                // Pillar 2: COGS & Food Cost
                executiveCard(
                    icon: "fork.knife",
                    iconColor: .appRose,
                    title: isThai ? "ต้นทุนอาหาร (COGS)" : "Cost of Goods (COGS)",
                    primaryValue: "฿\(fmt(viewModel.totalCOGS, 0))",
                    primaryColor: .textPrimary,
                    tagLabel: isThai ? "\(String(format: "%.1f", viewModel.cogsPct))% ยอดขาย" : "\(String(format: "%.1f", viewModel.cogsPct))% Revenue",
                    tagColor: viewModel.cogsPct <= 35 ? .appTeal : (viewModel.cogsPct <= 45 ? .appAmber : .appRose),
                    subtext1: isThai
                        ? "กำไรขั้นต้น: ฿\(fmt(viewModel.grossProfit, 0)) (\(String(format: "%.0f", viewModel.grossMarginPct))%)"
                        : "Gross Profit: ฿\(fmt(viewModel.grossProfit, 0)) (\(String(format: "%.0f", viewModel.grossMarginPct))%)",
                    subtext2: isThai
                        ? "ของเสีย/สูญเสีย: ฿\(fmt(viewModel.totalWasteCost, 0))"
                        : "Waste & Spoilage: ฿\(fmt(viewModel.totalWasteCost, 0))"
                )

                // Pillar 3: Labor & OpEx
                let totalOpAndLabor = viewModel.totalLaborCost + viewModel.totalOperatingExpenses
                executiveCard(
                    icon: "person.2.fill",
                    iconColor: .appAmber,
                    title: isThai ? "ค่าแรง & ค่าใช้จ่าย (OpEx)" : "Labor & OpEx",
                    primaryValue: "฿\(fmt(totalOpAndLabor, 0))",
                    primaryColor: .textPrimary,
                    tagLabel: isThai ? "ค่าแรง \(String(format: "%.1f", viewModel.laborCostPct))%" : "Labor \(String(format: "%.1f", viewModel.laborCostPct))%",
                    tagColor: viewModel.laborCostPct <= 30 ? .appTeal : .appAmber,
                    subtext1: isThai
                        ? "ค่าแรงพนักงาน: ฿\(fmt(viewModel.totalLaborCost, 0))"
                        : "Staff Labor: ฿\(fmt(viewModel.totalLaborCost, 0))",
                    subtext2: isThai
                        ? "ค่าเช่า/น้ำไฟ/OpEx: ฿\(fmt(viewModel.totalOperatingExpenses, 0))"
                        : "Rent/Utilities/OpEx: ฿\(fmt(viewModel.totalOperatingExpenses, 0))"
                )

                // Pillar 4: Estimated Net Profit (P&L)
                let isProfit = viewModel.estimatedNetProfit >= 0
                executiveCard(
                    icon: isProfit ? "arrow.up.right.circle.fill" : "arrow.down.right.circle.fill",
                    iconColor: isProfit ? .appTeal : .appRose,
                    title: isThai ? "กำไรสุทธิ (Net P&L)" : "Net Profit (P&L)",
                    primaryValue: "฿\(fmt(viewModel.estimatedNetProfit, 0))",
                    primaryColor: isProfit ? .appTeal : .appRose,
                    tagLabel: isThai ? "\(String(format: "%.1f", viewModel.netProfitMarginPct))% กำไร" : "\(String(format: "%.1f", viewModel.netProfitMarginPct))% Margin",
                    tagColor: isProfit ? (viewModel.netProfitMarginPct >= 20 ? .appTeal : .appAmber) : .appRose,
                    subtext1: isThai
                        ? (isProfit ? (viewModel.netProfitMarginPct >= 20 ? "สุขภาพการเงิน: ยอดเยี่ยม" : "สุขภาพการเงิน: ปานกลาง") : "สุขภาพการเงิน: ควรปรับลดต้นทุน")
                        : (isProfit ? (viewModel.netProfitMarginPct >= 20 ? "Financial Health: Excellent" : "Financial Health: Moderate") : "Financial Health: Cost Action Needed"),
                    subtext2: isThai
                        ? "หลังหักภาษี, COGS, ค่าแรง, ค่าเสื่อม"
                        : "After Tax, COGS, Labor, Depr."
                )
            }
        }
        .scaleEffect(animateKPIs ? 1 : 0.98)
        .opacity(animateKPIs ? 1 : 0.7)
    }

    private func executiveCard(
        icon: String,
        iconColor: Color,
        title: String,
        primaryValue: String,
        primaryColor: Color,
        tagLabel: String,
        tagColor: Color,
        subtext1: String,
        subtext2: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header Row
            HStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.12))
                        .frame(width: 26, height: 26)
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(iconColor)
                }

                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textSecondary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text(tagLabel)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(tagColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(tagColor.opacity(0.12))
                    .clipShape(Capsule())
            }

            // Big Number
            Text(primaryValue)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(primaryColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())

            Divider().background(Color.appDivider)

            // Subtext breakdown
            VStack(alignment: .leading, spacing: 3) {
                Text(subtext1)
                    .font(.system(size: 10.5))
                    .foregroundColor(.textSecondary)
                    .lineLimit(1)
                Text(subtext2)
                    .font(.system(size: 9.5))
                    .foregroundColor(.textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.appBorderSubtle, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 3)
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - 3. Sub-Navigation Tabs
    // ─────────────────────────────────────────────────────────────────

    private var analyticsTabBar: some View {
        HStack(spacing: 8) {
            ForEach(AnalyticsTab.allCases) { tab in
                let isSelected = selectedTab == tab
                Button {
                    APHaptic.selection()
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                        Text(tab.localizedName(isThai: isThai))
                            .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .foregroundColor(isSelected ? .white : .textSecondary)
                    .background(isSelected ? Color.appAccent : Color.appSurface)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(isSelected ? Color.clear : Color.appBorderSubtle, lineWidth: 1))
                    .shadow(color: isSelected ? Color.appAccent.opacity(0.25) : Color.clear, radius: 4, x: 0, y: 2)
                }
                .buttonStyle(.plain)
                .hoverEffect(.lift)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - 4. Tab Content Router
    // ─────────────────────────────────────────────────────────────────

    @ViewBuilder
    private var tabContent: some View {
        Group {
            switch selectedTab {
            case .overview:      overviewTab
            case .profitability: profitabilityTab
            case .delivery:      deliveryTab
            case .menu:          menuTab
            case .inventory:     inventoryTab
            case .staff:         staffTab
            }
        }
        .id(selectedTab)
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .move(edge: .trailing)),
            removal: .opacity
        ))
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: TAB 1 — OVERVIEW (Redesigned 2-Column Responsive Layout)
    // ─────────────────────────────────────────────────────────────────

    private var overviewTab: some View {
        VStack(spacing: APSpacing.md) {
            // Government Support Banner (if applicable)
            if thaiChuaThaiPlusEnabled && viewModel.supportProgramOrders > 0 {
                supportProgramCard
            }

            // 2-Column Core Financial Layout
            HStack(alignment: .top, spacing: APSpacing.md) {
                // Left Column: P&L Waterfall Ledger & Revenue Trend
                VStack(spacing: APSpacing.md) {
                    plWaterfallCard
                    trendsChartCard
                }
                .frame(maxWidth: .infinity)

                // Right Column: Channel Mix, Payment Donut & Top Profit Leaders
                VStack(spacing: APSpacing.md) {
                    salesChannelMixCard
                    paymentBreakdownCard
                    topMarginItemsCard
                }
                .frame(maxWidth: 440)
            }

            // Product Sales Detailed Table
            productSalesCard
        }
    }

    // ─── P&L Waterfall Card ───────────────────────────────────────────

    private var plWaterfallCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.appAccent.opacity(0.12))
                        .frame(width: 24, height: 24)
                    Image(systemName: "list.bullet.rectangle.portrait.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.appAccent)
                }

                Text(isThai ? "โครงสร้างงบกำไร-ขาดทุน (P&L Waterfall)" : "P&L Waterfall Structure")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.textPrimary)

                Spacer()

                Text(isThai ? "หักค่าใช้จ่ายทีละขั้น" : "Step-down accounting")
                    .font(.system(size: 10))
                    .foregroundColor(.textTertiary)
            }

            let rows: [(label: String, amount: Double, isDeduction: Bool, isTotal: Bool)] = [
                (isThai ? "1. ยอดรับชำระทั้งหมด (รวม VAT)" : "1. Gross Captured Sales (incl. VAT)", viewModel.grossRevenue, false, false),
                (isThai ? "   (-) ส่วนลดและคืนเงิน" : "   (-) Discounts & Refunds", -(viewModel.discountGiven + viewModel.refundedAmount), true, false),
                (isThai ? "2. ยอดขายสุทธิ (รวม VAT)" : "2. Net Sales (incl. VAT)", viewModel.netSalesInclVAT, false, true),
                (isThai ? "   (-) ภาษีขายสุทธิ" : "   (-) Net Output VAT", -viewModel.netOutputVAT, true, false),
                (isThai ? "3. รายได้ทางบัญชี (ไม่รวม VAT)" : "3. Accounting Revenue (ex. VAT)", viewModel.accountingRevenueExVAT, false, true),
                (isThai ? "   (-) ต้นทุนอาหาร/วัตถุดิบ (COGS)" : "   (-) Cost of Goods Sold (COGS)", -viewModel.totalCOGS, true, false),
                (isThai ? "4. กำไรขั้นต้น (Gross Profit)" : "4. Gross Profit", viewModel.grossProfit, false, true),
                (isThai ? "   (-) ค่าแรงพนักงาน" : "   (-) Labor Cost", -viewModel.totalLaborCost, true, false),
                (isThai ? "   (-) วัตถุดิบสูญเสีย/ตัดทิ้ง" : "   (-) Waste & Spoilage", -viewModel.totalWasteCost, true, false),
                (isThai ? "   (-) ค่าใช้จ่ายดำเนินงานร้าน (OpEx)" : "   (-) Operating Expenses (OpEx)", -viewModel.totalOperatingExpenses, true, false),
                (isThai ? "   (-) ค่าตัดจำหน่าย & ค่าเสื่อมราคา" : "   (-) Amortisation & Depreciation", -(viewModel.totalPrepaidExpenseRecognized + viewModel.totalDepreciationExpense), true, false),
                (isThai ? "5. กำไรสุทธิประเมิน (Estimated Net Profit)" : "5. Estimated Net Profit", viewModel.estimatedNetProfit, false, true),
            ]

            VStack(spacing: 2) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 8) {
                        Text(row.label)
                            .font(.system(size: row.isTotal ? 12.5 : 11.5, weight: row.isTotal ? .bold : .regular))
                            .foregroundColor(row.isTotal ? .textPrimary : .textSecondary)
                        Spacer()
                        let valText: String = {
                            if abs(row.amount) < 0.01 { return "฿0" }
                            if row.amount < 0 { return "-฿\(fmt(abs(row.amount), 0))" }
                            return "฿\(fmt(row.amount, 0))"
                        }()
                        Text(valText)
                            .font(.system(size: row.isTotal ? 13 : 11.5, weight: row.isTotal ? .bold : .medium, design: .monospaced))
                            .foregroundColor(row.isTotal
                                             ? (row.amount >= 0 ? .appTeal : .appRose)
                                             : (row.isDeduction ? .appRose : .textPrimary))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, row.isTotal ? 7 : 5)
                    .background(row.isTotal ? Color.appSurfaceHigh : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
            .padding(8)
            .background(Color.appBackground.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(14)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.appBorderSubtle, lineWidth: 1))
    }

    // ─── Sales Mix by Channel Card ────────────────────────────────────

    private var salesChannelMixCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.appTeal.opacity(0.12))
                        .frame(width: 24, height: 24)
                    Image(systemName: "chart.pie.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.appTeal)
                }

                Text(isThai ? "สัดส่วนช่องทางการขาย (Sales Mix)" : "Sales Mix by Channel")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.textPrimary)

                Spacer()
            }

            let totalRev = max(viewModel.netRevenue, 1)
            let dineInPct = (viewModel.dineInRevenue / totalRev) * 100
            let takeOutPct = (viewModel.takeOutRevenue / totalRev) * 100
            let deliveryPct = (viewModel.deliveryRevenue / totalRev) * 100

            // Visual Segmented Bar
            GeometryReader { geo in
                HStack(spacing: 2) {
                    if dineInPct > 0 {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.appTeal)
                            .frame(width: geo.size.width * CGFloat(dineInPct / 100))
                    }
                    if takeOutPct > 0 {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.appAccent)
                            .frame(width: geo.size.width * CGFloat(takeOutPct / 100))
                    }
                    if deliveryPct > 0 {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.appRose)
                            .frame(width: geo.size.width * CGFloat(deliveryPct / 100))
                    }
                    if dineInPct == 0 && takeOutPct == 0 && deliveryPct == 0 {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.appSurfaceHigh)
                            .frame(width: geo.size.width)
                    }
                }
            }
            .frame(height: 10)
            .clipShape(Capsule())

            // Stats breakdown
            HStack(spacing: 8) {
                channelStatBox(title: isThai ? "ทานที่ร้าน" : "Dine In", icon: "chair.fill", count: viewModel.dineInOrders, rev: viewModel.dineInRevenue, pct: dineInPct, color: .appTeal)
                channelStatBox(title: isThai ? "สั่งกลับบ้าน" : "Takeaway", icon: "bag.fill", count: viewModel.takeOutOrders, rev: viewModel.takeOutRevenue, pct: takeOutPct, color: .appAccent)
                channelStatBox(title: isThai ? "เดลิเวอรี" : "Delivery", icon: "box.truck.fill", count: viewModel.deliveryOrders, rev: viewModel.deliveryRevenue, pct: deliveryPct, color: .appRose)
            }
        }
        .padding(14)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.appBorderSubtle, lineWidth: 1))
    }

    private func channelStatBox(title: String, icon: String, count: Int, rev: Double, pct: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(.textSecondary)
            }
            Text("฿\(fmt(rev, 0))")
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .foregroundColor(.textPrimary)
            HStack(spacing: 4) {
                Text(isThai ? "\(count) บิล" : "\(count) orders")
                    .font(.system(size: 9.5))
                    .foregroundColor(.textTertiary)
                Spacer()
                Text("\(String(format: "%.0f", pct))%")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundColor(color)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appSurfaceHigh)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // ─── Payment Breakdown Card ───────────────────────────────────────

    private var paymentBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.appAmber.opacity(0.12))
                        .frame(width: 24, height: 24)
                    Image(systemName: "creditcard.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.appAmber)
                }

                Text(isThai ? "ช่องทางการรับชำระเงิน" : "Payment Breakdown")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.textPrimary)

                Spacer()
            }

            if viewModel.paymentBreakdown.isEmpty {
                emptyState(icon: "creditcard", text: isThai ? "ยังไม่มีข้อมูลการชำระเงิน" : "No payment data recorded")
            } else {
                HStack(spacing: 16) {
                    Chart(viewModel.paymentBreakdown) { pt in
                        SectorMark(angle: .value("Rev", pt.amount), innerRadius: .ratio(0.6), angularInset: 1.5)
                            .cornerRadius(4)
                            .foregroundStyle(colorForPaymentMethod(pt.method))
                    }
                    .frame(width: 100, height: 100)
                    .chartLegend(.hidden)

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(viewModel.paymentBreakdown) { pt in
                            HStack(spacing: 6) {
                                Circle().fill(colorForPaymentMethod(pt.method)).frame(width: 7, height: 7)
                                Text(pt.method).font(.system(size: 11.5)).foregroundColor(.textSecondary).lineLimit(1)
                                Spacer()
                                Text("฿\(fmt(pt.amount, 0))")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundColor(.textPrimary)
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.appBorderSubtle, lineWidth: 1))
    }

    // ─── Revenue Trends Chart Card ────────────────────────────────────

    private var trendsChartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.appAccent.opacity(0.12))
                        .frame(width: 24, height: 24)
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.appAccent)
                }

                Text(isThai ? "แนวโน้มรายได้และชั่วโมงขายดี" : "Revenue & Hourly Trends")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.textPrimary)

                Spacer()

                if let peak = viewModel.peakHour {
                    Text("Peak: \(HourlySalesPoint(hour: peak, revenue: 0).hourLabel) (฿\(fmt(viewModel.peakHourRevenue, 0)))")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.appAccent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.appAccent.opacity(0.1))
                        .clipShape(Capsule())
                }
            }

            if viewModel.summaryMode == .daily || viewModel.summaryMode == .shift {
                Chart(viewModel.hourlyTrend) { p in
                    BarMark(x: .value("Hour", p.hourLabel), y: .value("Revenue", p.revenue))
                        .foregroundStyle(Color.appAccent.gradient)
                        .cornerRadius(4)
                }
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: 160)
                .opacity(animateCharts ? 1 : 0)
            } else {
                Chart(viewModel.dailyTrend) { p in
                    LineMark(x: .value("Day", p.dayLabel), y: .value("Revenue", p.revenue))
                        .foregroundStyle(Color.appAccent)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                        .interpolationMethod(.catmullRom)
                    AreaMark(x: .value("Day", p.dayLabel), y: .value("Revenue", p.revenue))
                        .foregroundStyle(Color.appAccent.opacity(0.12).gradient)
                        .interpolationMethod(.catmullRom)
                }
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: 160)
                .opacity(animateCharts ? 1 : 0)
            }
        }
        .padding(14)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.appBorderSubtle, lineWidth: 1))
    }

    // ─── Top Profit Items Card ────────────────────────────────────────

    private var topMarginItemsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.appTeal.opacity(0.12))
                        .frame(width: 24, height: 24)
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.appTeal)
                }

                Text(isThai ? "เมนูทำกำไรสูงสุด (Top Profit Leaders)" : "Top Margin Products")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.textPrimary)

                Spacer()
            }

            if viewModel.topMarginItems.isEmpty {
                emptyState(icon: "fork.knife", text: isThai ? "ยังไม่มีข้อมูลเมนู" : "No product data recorded")
            } else {
                VStack(spacing: 6) {
                    ForEach(viewModel.topMarginItems.prefix(5)) { prod in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(prod.name)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.textPrimary)
                                    .lineLimit(1)
                                Text(isThai ? "\(prod.quantity) ขายได้ • ฿\(fmt(prod.totalRevenue, 0))" : "\(prod.quantity) sold • ฿\(fmt(prod.totalRevenue, 0))")
                                    .font(.system(size: 10))
                                    .foregroundColor(.textTertiary)
                            }
                            Spacer()
                            Text("\(String(format: "%.0f", prod.grossMarginPct))% GP")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(prod.grossMarginPct >= 50 ? .appTeal : .appRose)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background((prod.grossMarginPct >= 50 ? Color.appTeal : Color.appRose).opacity(0.12))
                                .clipShape(Capsule())
                        }
                        .padding(8)
                        .background(Color.appSurfaceHigh)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
        }
        .padding(14)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.appBorderSubtle, lineWidth: 1))
    }

    // ─── Detailed Product Sales Table ─────────────────────────────────

    private var productSalesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.appAccent.opacity(0.12))
                        .frame(width: 24, height: 24)
                    Image(systemName: "tablecells.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.appAccent)
                }

                Text(isThai ? "รายงานยอดขายแยกตามสินค้า" : "Product Sales Breakdown")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.textPrimary)

                Spacer()

                Button(action: shareProductReportAction) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                        Text(isThai ? "ส่งออก PDF" : "Export PDF")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.appAccent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.appAccent.opacity(0.1))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            if viewModel.productSales.isEmpty {
                emptyLabel(isThai ? "ไม่มีข้อมูลสินค้าขายดี" : "No product sales in this period")
            } else {
                tableHeader([
                    isThai ? "ชื่อสินค้า" : "Item Name",
                    isThai ? "หมวดหมู่" : "Category",
                    isThai ? "จำนวน" : "Qty",
                    isThai ? "ยอดขาย" : "Revenue",
                    isThai ? "กำไร %" : "Margin %"
                ])
                Divider()
                ForEach(viewModel.productSales) { prod in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(prod.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                            Text("\(prod.channel) • \(prod.itemType)").font(.system(size: 9)).foregroundColor(.textTertiary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Text(prod.category).font(.system(size: 11.5)).foregroundColor(.textSecondary).frame(width: 120, alignment: .leading)
                        Text("\(prod.quantity)").font(.system(size: 12, weight: .bold)).frame(width: 50, alignment: .trailing)
                        Text("฿\(fmt(prod.totalRevenue, 0))").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(.appTeal).frame(width: 90, alignment: .trailing)
                        Text(prod.cogs > 0 ? "\(String(format: "%.1f", prod.grossMarginPct))%" : "–")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(prod.grossMarginPct >= 50 ? .appTeal : .appRose)
                            .frame(width: 70, alignment: .trailing)
                    }
                    .padding(.vertical, 7)
                    .padding(.horizontal, 6)
                    Divider()
                }
            }
        }
        .padding(14)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.appBorderSubtle, lineWidth: 1))
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: TAB 2 — P&L (PROFITABILITY)
    // ─────────────────────────────────────────────────────────────────

    private var profitabilityTab: some View {
        VStack(spacing: APSpacing.md) {
            // P&L Summary Cards
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 165), spacing: 12)], spacing: 12) {
                kpiCard(isThai ? "รายได้ไม่รวม VAT" : "Revenue ex. VAT", "฿\(fmt(viewModel.accountingRevenueExVAT, 0))", isThai ? "ฐานรายได้ทางบัญชี" : "Accounting revenue basis", .appTeal)
                kpiCard(isThai ? "ต้นทุนอาหาร (COGS)" : "Total COGS", "฿\(fmt(viewModel.totalCOGS, 0))", isThai ? "ต้นทุนตามสูตรเมนู" : "Standard recipe costs", .appRose)
                kpiCard(isThai ? "กำไรขั้นต้น" : "Gross Profit", "฿\(fmt(viewModel.grossProfit, 0))", isThai ? "รายได้หัก COGS" : "Revenue minus COGS", viewModel.grossProfit >= 0 ? .appTeal : .appRose)
                kpiCard(isThai ? "อัตรากำไรขั้นต้น %" : "Gross Margin %", "\(String(format: "%.1f", viewModel.grossMarginPct))%", "Gross Margin %", viewModel.grossMarginPct >= 40 ? .appTeal : .appRose)
                kpiCard(isThai ? "ค่าแรงพนักงาน" : "Labor Cost", "฿\(fmt(viewModel.totalLaborCost, 0))", isThai ? "คิดเป็น \(String(format: "%.1f", viewModel.laborCostPct))% ยอดขาย" : "\(String(format: "%.1f", viewModel.laborCostPct))% of Revenue", .appAccent)
                kpiCard(isThai ? "ของเสีย/สูญเสีย" : "Waste & Loss", "฿\(fmt(viewModel.totalWasteCost, 0))", isThai ? "มูลค่าสินค้าตัดทิ้ง" : "Spoilage & discard cost", .appRose)
                kpiCard(isThai ? "ค่าใช้จ่ายดำเนินงาน" : "Operating Expenses", "฿\(fmt(viewModel.totalOperatingExpenses, 0))", "OpEx", .appAmber)
                kpiCard(isThai ? "กำไรสุทธิประเมิน" : "Estimated Net Profit", "฿\(fmt(viewModel.estimatedNetProfit, 0))", "\(String(format: "%.1f", viewModel.netProfitMarginPct))% Net Margin", viewModel.estimatedNetProfit >= 0 ? .appTeal : .appRose)
            }

            // Break-Even Target Card
            breakEvenTargetCard

            // Investment Payback Timeline Card
            paybackTimelineCard

            // P&L Waterfall-style breakdown
            plWaterfallCard

            // Category breakdown donut
            if !viewModel.categoryBreakdown.isEmpty {
                categoryBreakdownCard
            }
        }
    }

    // ─── Break-Even Analysis & Daily Sales Target Card ────────────────
    private var breakEvenTargetCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.appIndigo.opacity(0.12))
                        .frame(width: 28, height: 28)
                    Image(systemName: "target")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.appIndigo)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(isThai ? "การวิเคราะห์จุดคุ้มทุน (Break-Even Analysis)" : "Break-Even & Target Analysis")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.textPrimary)
                    Text(isThai ? "คำนวณจาก Fixed OpEx + ค่าเสื่อมราคา หารด้วยอัตรากำไรส่วนเกิน (CMR)" : "Based on Fixed OpEx + Depreciation over Contribution Margin Ratio")
                        .font(.system(size: 10.5))
                        .foregroundColor(.textTertiary)
                }

                Spacer()

                if viewModel.monthlyBreakEvenSales <= 0 {
                    Text(isThai ? "ยังไม่บันทึกต้นทุนคงที่" : "No Fixed Costs")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.appSurfaceHigh)
                        .clipShape(Capsule())
                } else {
                    let isBreakEvenReached = viewModel.grossRevenue >= viewModel.monthlyBreakEvenSales
                    Text(isBreakEvenReached ? (isThai ? "คุ้มทุนแล้ว 🎉" : "Breakeven Met 🎉") : (isThai ? "กำลังสร้างผลงาน" : "In Progress"))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(isBreakEvenReached ? .appTeal : .appAmber)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background((isBreakEvenReached ? Color.appTeal : Color.appAmber).opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            // Progress towards Monthly Break-Even
            let progress = viewModel.monthlyBreakEvenSales > 0 ? min(viewModel.grossRevenue / viewModel.monthlyBreakEvenSales, 2.0) : 0.0
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(isThai ? "ยอดขายปัจจุบันเทียบจุดคุ้มทุนรายเดือน" : "Actual Sales vs Monthly Break-Even")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(.textSecondary)
                    Spacer()
                    Text("฿\(fmt(viewModel.grossRevenue, 0)) / ฿\(fmt(viewModel.monthlyBreakEvenSales, 0))")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.textPrimary)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.appSurfaceHigh)
                            .frame(height: 10)

                        if progress > 0 {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(
                                    LinearGradient(
                                        colors: progress >= 1.0 ? [.appTeal, Color(hex: "10B981")] : [.appAmber, .appIndigo],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(0, min(geo.size.width * CGFloat(progress), geo.size.width)), height: 10)
                        }
                    }
                }
                .frame(height: 10)
            }

            // 3 Pillar Metrics Grid
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    // Daily Target
                    VStack(alignment: .leading, spacing: 3) {
                        Text(isThai ? "เป้าหมายรายวันขั้นต่ำ" : "Min Daily Target")
                            .font(.system(size: 10.5))
                            .foregroundColor(.textSecondary)
                        Text(viewModel.dailyBreakEvenSales > 0 ? "฿\(fmt(viewModel.dailyBreakEvenSales, 0))" : "—")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(viewModel.dailyBreakEvenSales > 0 ? .appIndigo : .textSecondary)
                        Text(isThai ? "เฉลี่ย 30 วัน/เดือน" : "Avg 30 days/mo")
                            .font(.system(size: 9))
                            .foregroundColor(.textTertiary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.appSurfaceHigh)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    // Fixed Costs + Depr
                    let fixedTotal = viewModel.totalOperatingExpenses + viewModel.totalLaborCost + viewModel.totalDepreciationExpense
                    VStack(alignment: .leading, spacing: 3) {
                        Text(isThai ? "ภาระต้นทุนคงที่ + ค่าเสื่อม" : "Fixed Costs + Depr")
                            .font(.system(size: 10.5))
                            .foregroundColor(.textSecondary)
                        Text("฿\(fmt(fixedTotal, 0))")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(fixedTotal > 0 ? .appRose : .textSecondary)
                        Text(isThai ? "OpEx ฿\(fmt(viewModel.totalOperatingExpenses, 0)) • ค่าเสื่อม ฿\(fmt(viewModel.totalDepreciationExpense, 0))" : "OpEx ฿\(fmt(viewModel.totalOperatingExpenses, 0)) • Depr ฿\(fmt(viewModel.totalDepreciationExpense, 0))")
                            .font(.system(size: 9))
                            .foregroundColor(.textTertiary)
                            .lineLimit(1)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.appSurfaceHigh)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    // Contribution Margin Ratio
                    VStack(alignment: .leading, spacing: 3) {
                        Text(isThai ? "อัตรากำไรส่วนเกิน (CMR)" : "Contribution Margin")
                            .font(.system(size: 10.5))
                            .foregroundColor(.textSecondary)
                        Text("\(String(format: "%.1f", viewModel.grossMarginPct))%")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.appTeal)
                        Text(isThai ? "กำไรขั้นต้นหลังหัก COGS" : "Gross margin after COGS")
                            .font(.system(size: 9))
                            .foregroundColor(.textTertiary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.appSurfaceHigh)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
        .padding(14)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.appBorderSubtle, lineWidth: 1))
    }

    // ─── Investment Payback Timeline Card ─────────────────────────────
    private var paybackTimelineCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(hex: "F59E0B").opacity(0.12))
                        .frame(width: 28, height: 28)
                    Image(systemName: "hourglass.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color(hex: "F59E0B"))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(isThai ? "การวิเคราะห์ระยะเวลาคืนทุน (Payback Timeline)" : "Investment Payback Timeline")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.textPrimary)
                    Text(isThai ? "คำนวณจาก เงินลงทุนสร้างร้าน (CapEx) หารด้วย กระแสเงินสดสุทธิ (EBITDA)" : "Calculated from Total CapEx divided by Operating Cash Flow (EBITDA)")
                        .font(.system(size: 10.5))
                        .foregroundColor(.textTertiary)
                }

                Spacer()

                if !viewModel.hasCapExInvestment || viewModel.totalCapExInvestment <= 0 {
                    Text(isThai ? "ยังไม่บันทึกเงินลงทุน" : "No CapEx Data")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.appSurfaceHigh)
                        .clipShape(Capsule())
                } else if viewModel.isFullyPaidBack {
                    Text(isThai ? "คืนทุนครบ 100% 🏆" : "100% Recovered 🏆")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.appTeal)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.appTeal.opacity(0.12))
                        .clipShape(Capsule())
                } else if viewModel.operatingCashFlow <= 0 {
                    Text(isThai ? "รอผลกำไรสุทธิ" : "Awaiting Cash Flow")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.appAmber)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.appAmber.opacity(0.12))
                        .clipShape(Capsule())
                } else {
                    Text(isThai ? "\(String(format: "%.1f", viewModel.paybackProgressPct))% คืนทุน" : "\(String(format: "%.1f", viewModel.paybackProgressPct))% Recovered")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(hex: "F59E0B"))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(hex: "F59E0B").opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            // Payback Grid
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    // Total Initial CapEx
                    VStack(alignment: .leading, spacing: 3) {
                        Text(isThai ? "เงินลงทุนสร้างร้านทั้งหมด (CapEx)" : "Total Initial CapEx")
                            .font(.system(size: 10.5))
                            .foregroundColor(.textSecondary)
                        Text("฿\(fmt(viewModel.totalCapExInvestment, 0))")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(viewModel.totalCapExInvestment > 0 ? .appAccent : .textSecondary)
                        Text(isThai ? (viewModel.totalCapExInvestment > 0 ? "งานก่อสร้าง + เครื่องจักร + สินทรัพย์" : "บันทึกในหน้า ค่าใช้จ่ายและสินทรัพย์") : (viewModel.totalCapExInvestment > 0 ? "Fit-out + Equipment + Assets" : "Record in Expenses & Asset Register"))
                            .font(.system(size: 9))
                            .foregroundColor(.textTertiary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.appSurfaceHigh)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    // Monthly Cash Flow
                    VStack(alignment: .leading, spacing: 3) {
                        Text(isThai ? "กระแสเงินสดดำเนินงาน/เดือน" : "Monthly Operating Cash Flow")
                            .font(.system(size: 10.5))
                            .foregroundColor(.textSecondary)
                        Text("฿\(fmt(viewModel.operatingCashFlow, 0))")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(viewModel.operatingCashFlow > 0 ? .appTeal : (viewModel.operatingCashFlow < 0 ? .appRose : .textSecondary))
                        Text(isThai ? "กำไรสุทธิ + ค่าเสื่อมราคา" : "Net Profit + Depreciation")
                            .font(.system(size: 9))
                            .foregroundColor(.textTertiary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.appSurfaceHigh)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    // Estimated Payback Period
                    VStack(alignment: .leading, spacing: 3) {
                        Text(isThai ? "ระยะเวลาคืนทุนประเมิน" : "Est. Payback Time")
                            .font(.system(size: 10.5))
                            .foregroundColor(.textSecondary)
                        if !viewModel.hasCapExInvestment || viewModel.totalCapExInvestment <= 0 {
                            Text("—")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.textSecondary)
                            Text(isThai ? "ไม่มีข้อมูลเงินลงทุนสินทรัพย์" : "No CapEx records")
                                .font(.system(size: 9))
                                .foregroundColor(.textTertiary)
                        } else if viewModel.isFullyPaidBack {
                            Text(isThai ? "คืนทุนเรียบร้อย 🏆" : "Fully Recovered 🏆")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.appTeal)
                            Text(isThai ? "สร้างกำไรส่วนเกินสะสมแล้ว" : "Generating cumulative returns")
                                .font(.system(size: 9))
                                .foregroundColor(.textTertiary)
                        } else if viewModel.paybackRemainingMonths.isInfinite || viewModel.operatingCashFlow <= 0 {
                            Text(isThai ? "รอผลกำไรสุทธิ" : "Awaiting Cash Flow")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.appAmber)
                            Text(isThai ? "ต้องมีกระแสเงินสดดำเนินงานเป็นบวก" : "Requires positive cash flow")
                                .font(.system(size: 9))
                                .foregroundColor(.textTertiary)
                        } else {
                            let yrs = Int(viewModel.paybackRemainingMonths / 12)
                            let mos = Int(viewModel.paybackRemainingMonths.truncatingRemainder(dividingBy: 12))
                            Text(isThai ? "\(yrs > 0 ? "\(yrs) ปี " : "")\(mos) เดือน" : "\(yrs > 0 ? "\(yrs)y " : "")\(mos)m")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundColor(Color(hex: "F59E0B"))
                            Text(isThai ? "นับจากกระแสเงินสดปัจจุบัน" : "Based on current cash flow")
                                .font(.system(size: 9))
                                .foregroundColor(.textTertiary)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.appSurfaceHigh)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
        .padding(14)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.appBorderSubtle, lineWidth: 1))
    }

    private var categoryBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isThai ? "รายได้แยกตามหมวดหมู่อาหาร" : "Revenue by Category")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.textPrimary)

            HStack(alignment: .top, spacing: 20) {
                Chart(viewModel.categoryBreakdown) { cat in
                    SectorMark(angle: .value("Rev", cat.revenue), innerRadius: .ratio(0.5), angularInset: 1.5)
                        .cornerRadius(4)
                        .foregroundStyle(colorForCategory(cat.category))
                }
                .frame(width: 130, height: 130)
                .chartLegend(.hidden)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(viewModel.categoryBreakdown) { cat in
                        HStack(spacing: 6) {
                            Circle().fill(colorForCategory(cat.category)).frame(width: 6, height: 6)
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
        .padding(14)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.appBorderSubtle, lineWidth: 1))
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: TAB 3 — DELIVERY PLATFORMS
    // ─────────────────────────────────────────────────────────────────

    private var deliveryTab: some View {
        VStack(spacing: APSpacing.md) {
            // Summary KPIs
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    kpiCard(isThai ? "จำนวนออเดอร์เดลิเวอรี" : "Delivery Orders",  "\(viewModel.deliveryOrders)",                isThai ? "ออเดอร์ทั้งหมด" : "Total Orders", .appAccent)
                    kpiCard(isThai ? "ยอดขายเดลิเวอรีรวม" : "Gross Delivery Sales",   "฿\(fmt(viewModel.deliveryRevenue, 0))",      isThai ? "ก่อนหัก GP" : "Before GP fee", .appAccent)
                    kpiCard(isThai ? "ค่า GP & โฆษณา" : "Total GP & Ads Fees",    "฿\(fmt(viewModel.totalDeliveryGPFees + viewModel.totalDeliveryAdFees, 0))",  isThai ? "ค่าธรรมเนียมแพลตฟอร์ม" : "Platform fees", .appRose)
                    kpiCard(isThai ? "รายได้สุทธิเดลิเวอรี" : "Net Delivery Revenue", "฿\(fmt(viewModel.netDeliveryRevenue, 0))",   isThai ? "เงินเข้าบัญชีจริง" : "Actual payout", .appTeal)
                }
            }

            // Platform Breakdown Table
            deliveryPlatformTable

            // Net Margin per Platform Chart
            if !viewModel.deliveryPlatformBreakdown.isEmpty {
                deliveryMarginChart
            }
        }
    }

    private var deliveryPlatformTable: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(isThai ? "สรุปผลงานแยกตามแพลตฟอร์ม" : "Platform Performance Breakdown")
                .font(.system(size: 14, weight: .bold)).foregroundColor(.textPrimary)

            if viewModel.deliveryPlatformBreakdown.isEmpty {
                emptyLabel(isThai ? "ไม่มีข้อมูลเดลิเวอรีในช่วงนี้" : "No delivery data recorded")
            } else {
                HStack {
                    Text(isThai ? "แพลตฟอร์ม" : "Platform").frame(maxWidth: .infinity, alignment: .leading)
                    Text(isThai ? "ออเดอร์" : "Orders").frame(width: 55, alignment: .trailing)
                    Text(isThai ? "ยอดรวม" : "Gross").frame(width: 85, alignment: .trailing)
                    Text("GP Fee").frame(width: 80, alignment: .trailing)
                    Text("Ad Fee").frame(width: 75, alignment: .trailing)
                    Text(isThai ? "ยอดสุทธิ" : "Net Rev").frame(width: 85, alignment: .trailing)
                    Text(isThai ? "กำไร %" : "Margin %").frame(width: 65, alignment: .trailing)
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
                    Text(isThai ? "รวมทั้งหมด" : "Total").fontWeight(.bold).frame(maxWidth: .infinity, alignment: .leading)
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
        .padding(14)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.appBorderSubtle, lineWidth: 1))
    }

    private var deliveryMarginChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(isThai ? "เปรียบเทียบอัตรากำไรหลังหัก GP แต่ละแพลตฟอร์ม" : "Effective Margin % by Platform")
                .font(.system(size: 14, weight: .bold)).foregroundColor(.textPrimary)

            if viewModel.deliveryPlatformBreakdown.isEmpty {
                Text(isThai ? "ไม่มีข้อมูลเปรียบเทียบ" : "No delivery comparison data")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                let maxMargin = max(viewModel.deliveryPlatformBreakdown.map(\.effectiveMarginPct).max() ?? 0, 1)

                Chart(viewModel.deliveryPlatformBreakdown) { platform in
                    BarMark(
                        x: .value("Platform", platform.brandName),
                        y: .value("Margin %", platform.effectiveMarginPct.isFinite ? max(platform.effectiveMarginPct, 0) : 0)
                    )
                    .foregroundStyle(platform.brandColor.gradient)
                    .cornerRadius(5)
                    .annotation(position: .top) {
                        Text("\(String(format: "%.0f", platform.effectiveMarginPct))%")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.textSecondary)
                    }
                }
                .chartYScale(domain: 0...(maxMargin * 1.12))
                .chartYAxis { AxisMarks(position: .leading) { AxisValueLabel(format: FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0)), anchor: .trailing) } }
                .frame(height: 160)
            }
        }
        .padding(14)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.appBorderSubtle, lineWidth: 1))
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: TAB 4 — MENU INTELLIGENCE
    // ─────────────────────────────────────────────────────────────────

    private var menuTab: some View {
        VStack(spacing: APSpacing.md) {
            menuChannelBreakdownCard
            menuEngineeringCard
            if !viewModel.categoryBreakdown.isEmpty { categoryBreakdownCard }
        }
    }

    private var menuChannelBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(isThai ? "รายละเอียดสินค้าแยกช่องทางและ Add-on" : "Product Details by Channel & Add-ons")
                .font(.system(size: 14, weight: .bold)).foregroundColor(.textPrimary)
            Text(isThai ? "เมนูหลักและ modifier แสดงเป็นคนละรายการ เพื่อไม่รวมจำนวน รายได้ และต้นทุนข้ามช่องทาง" : "Main items and modifiers are tracked separately to prevent cross-channel contamination")
                .font(.system(size: 10)).foregroundColor(.textTertiary)
            tableHeader([
                isThai ? "ชื่อสินค้า" : "Item Name",
                isThai ? "ช่องทาง" : "Channel",
                isThai ? "ประเภท" : "Type",
                isThai ? "จำนวน" : "Qty",
                isThai ? "ยอดขาย" : "Revenue",
                isThai ? "กำไร %" : "Margin %"
            ])
            Divider()
            ForEach(viewModel.productSales) { item in
                HStack {
                    Text(item.name).fontWeight(.semibold).frame(maxWidth: .infinity, alignment: .leading).lineLimit(1)
                    Text(item.channel).frame(width: 80, alignment: .leading)
                    Text(item.itemType).foregroundColor(.textSecondary).frame(width: 75, alignment: .leading)
                    Text("\(item.quantity)").frame(width: 45, alignment: .trailing)
                    Text("฿\(fmt(item.totalRevenue, 0))").foregroundColor(.appTeal).frame(width: 85, alignment: .trailing)
                    Text(item.cogs > 0 ? "\(String(format: "%.1f", item.grossMarginPct))%" : "–").frame(width: 65, alignment: .trailing)
                }
                .font(.system(size: 11)).padding(.vertical, 7).padding(.horizontal, 6)
                Divider()
            }
        }
        .padding(14)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.appBorderSubtle, lineWidth: 1))
    }

    private var menuEngineeringCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(isThai ? "เมทริกซ์วิเคราะห์เมนู (Menu Engineering Matrix)" : "Menu Engineering Matrix (BCG)")
                    .font(.system(size: 14, weight: .bold)).foregroundColor(.textPrimary)
                Text(isThai ? "วิเคราะห์เมนูตามความนิยม (Volume) และความสามารถในการทำกำไร (Profitability)" : "Classifying dishes by sales popularity and margin profitability")
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
                emptyState(icon: "fork.knife", text: isThai ? "ยังไม่มีข้อมูลวิเคราะห์เมนู" : "No menu engineering data")
            } else {
                tableHeader([
                    isThai ? "ชื่อสินค้า" : "Item Name",
                    isThai ? "หมวดหมู่" : "Category",
                    isThai ? "จำนวน" : "Qty",
                    isThai ? "ยอดขาย" : "Revenue",
                    isThai ? "กำไร %" : "Margin %",
                    isThai ? "กลุ่มเมนู" : "Segment"
                ])
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
        .padding(14)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.appBorderSubtle, lineWidth: 1))
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: TAB 5 — INVENTORY
    // ─────────────────────────────────────────────────────────────────

    private var inventoryTab: some View {
        VStack(spacing: APSpacing.md) {
            // KPIs
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    kpiCard(isThai ? "มูลค่าสินค้าคงคลัง" : "Stock Value",       "฿\(fmt(viewModel.totalInventoryValue, 0))", isThai ? "มูลค่ารวมในคลัง" : "Total asset value",              .appTeal)
                    kpiCard(isThai ? "ต้นทุนที่ถูกใช้ไป" : "COGS Used",         "฿\(fmt(viewModel.totalCOGS, 0))",           isThai ? "ต้นทุนตามยอดขายจริง" : "Actual used in sales",          .appRose)
                    kpiCard(isThai ? "มูลค่าของเสียตัดทิ้ง" : "Waste & Spoilage", "฿\(fmt(viewModel.totalWasteCost, 0))",      isThai ? "วัตถุดิบเสียหาย/หมดอายุ" : "Damaged / expired",                    .appRose)
                    kpiCard(isThai ? "อัตราหมุนเวียนคลัง" : "Turnover Rate",     String(format: "%.2fx", viewModel.inventoryTurnoverRate), "COGS / Stock Value", .appAccent)
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
    }

    private var lowStockCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.appRose)
                Text(isThai ? "แจ้งเตือนวัตถุดิบใกล้หมด (LOW STOCK ALERT)" : "LOW STOCK ALERTS")
                    .font(.caption).fontWeight(.bold).foregroundColor(.appRose).tracking(1.0)
                Spacer()
                Text(isThai ? "\(viewModel.lowStockItems.count) รายการ" : "\(viewModel.lowStockItems.count) items")
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
        .padding(14)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.appBorderSubtle, lineWidth: 1))
    }

    private var inventoryUsageCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(isThai ? "การใช้วัตถุดิบตามทฤษฎี (Theoretical Usage)" : "Theoretical Ingredient Usage")
                .font(.system(size: 14, weight: .bold)).foregroundColor(.textPrimary)
            Text(isThai ? "คำนวณจากสูตรอาหาร (BOM) คูณด้วยจำนวนจานที่ขายได้" : "Calculated from Bill of Materials (BOM) times units sold")
                .font(.system(size: 10)).foregroundColor(.textTertiary)

            tableHeader([
                isThai ? "วัตถุดิบ" : "Ingredient",
                isThai ? "ปริมาณที่ควรใช้" : "Theoretical Used",
                isThai ? "มูลค่าต้นทุน" : "Cost Used"
            ])
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
        .padding(14)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.appBorderSubtle, lineWidth: 1))
    }

    private var wasteLogCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(isThai ? "บันทึกของเสียและของตัดทิ้ง (Waste Log)" : "Waste & Spoilage Log")
                .font(.system(size: 14, weight: .bold)).foregroundColor(.textPrimary)
            tableHeader([
                isThai ? "วัตถุดิบ" : "Ingredient",
                isThai ? "จำนวน" : "Quantity",
                isThai ? "มูลค่า" : "Cost",
                isThai ? "วันที่" : "Date"
            ])
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
        .padding(14)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.appBorderSubtle, lineWidth: 1))
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: TAB 6 — STAFF
    // ─────────────────────────────────────────────────────────────────

    private var staffTab: some View {
        VStack(spacing: APSpacing.md) {
            // Labor KPIs
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    kpiCard(isThai ? "ค่าแรงพนักงานรวม" : "Total Labor Cost",    "฿\(fmt(viewModel.totalLaborCost, 0))",          isThai ? "ค่าแรงและ OT" : "Wages & Overtime",                                                       .appAccent)
                    kpiCard(isThai ? "ชั่วโมงทำงานรวม" : "Total Labor Hours",         String(format: "%.1f hrs", viewModel.totalLaborHours), isThai ? "จากระบบบันทึกเวลา" : "From timecards",                                .appTeal)
                    kpiCard(isThai ? "สัดส่วนค่าแรงต่อยอดขาย" : "Labor Cost %",        "\(String(format: "%.1f", viewModel.laborCostPct))%",  isThai ? "เป้าหมาย ≤ 30%" : "Target ≤ 30%",                                   viewModel.laborCostPct <= 30 ? .appTeal : .appRose)
                    kpiCard(isThai ? "รายได้ต่อชั่วโมงทำงาน" : "Rev per Labor Hour",      "฿\(fmt(viewModel.revenuePerLaborHour, 0))",   isThai ? "ประสิทธิภาพพนักงาน" : "Staff efficiency",                                          .appTeal)
                }
            }

            // Cashier Performance
            cashierPerformanceCard

            // Staff Labor Breakdown
            if !viewModel.staffLaborBreakdown.isEmpty {
                staffLaborCard
            }
        }
    }

    private var cashierPerformanceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(isThai ? "ประสิทธิภาพแคชเชียร์ (Cashier Performance)" : "Cashier Performance")
                .font(.system(size: 14, weight: .bold)).foregroundColor(.textPrimary)

            if viewModel.cashierPerformance.isEmpty {
                emptyState(icon: "person.2", text: isThai ? "ไม่มีรายการสั่งซื้อในช่วงนี้" : "No orders recorded")
            } else {
                tableHeader([
                    isThai ? "แคชเชียร์" : "Cashier",
                    isThai ? "ออเดอร์" : "Orders",
                    isThai ? "ยอดขาย" : "Revenue",
                    isThai ? "ชิ้นที่ขาย" : "Items",
                    isThai ? "เฉลี่ย/บิล" : "Avg Ticket"
                ])
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
        .padding(14)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.appBorderSubtle, lineWidth: 1))
    }

    private var staffLaborCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(isThai ? "รายละเอียดค่าแรงรายบุคคล" : "Individual Labor Cost Breakdown")
                .font(.system(size: 14, weight: .bold)).foregroundColor(.textPrimary)
            tableHeader([
                isThai ? "พนักงาน" : "Employee",
                isThai ? "ชั่วโมงทำงาน" : "Hours",
                isThai ? "ชั่วโมง OT" : "OT Hours",
                isThai ? "ค่าแรงรวม" : "Labor Cost"
            ])
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
        .padding(14)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.appBorderSubtle, lineWidth: 1))
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Support Program (ไทยช่วยไทย Plus)
    // ─────────────────────────────────────────────────────────────────

    private var supportProgramCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(isThai ? "ไทยช่วยไทย Plus · กระทบยอดโครงการ" : "Gov Co-Payment Settlement Reconciliation")
                .font(.caption).fontWeight(.bold).foregroundColor(.appAccent).tracking(1)
            HStack(spacing: APSpacing.sm) {
                kpiCard(isThai ? "ยอดขายโครงการ" : "Program Sales", "฿\(fmt(viewModel.supportProgramSales, 0))", isThai ? "\(viewModel.supportProgramOrders) ออร์เดอร์" : "\(viewModel.supportProgramOrders) orders", .appAccent)
                kpiCard(isThai ? "ประชาชนชำระ" : "Citizen Paid", "฿\(fmt(viewModel.supportCitizenCollected, 0))", "40%", .appTeal)
                kpiCard(isThai ? "รัฐร่วมจ่าย" : "Gov Receivable", "฿\(fmt(viewModel.supportGovernmentReceivable, 0))", isThai ? "60% · รอกระทบยอด" : "60% · Pending", .appRose)
                kpiCard(isThai ? "เงินร่วมจ่ายเข้าแล้ว" : "Gov Received", "฿\(fmt(viewModel.supportGovernmentReceived, 0))", isThai ? "กระทบยอดแล้ว" : "Reconciled", .appTeal)
            }
            let pending = viewModel.historicalOrders.filter {
                $0.usesGovernmentSupport && $0.supportSettlementStatus == "pending"
            }
            if !pending.isEmpty {
                Divider()
                Text(isThai ? "รายการรอกระทบยอดเงินร่วมจ่าย" : "Pending Government Co-Payment Orders")
                    .font(.caption).fontWeight(.semibold).foregroundColor(.textSecondary)
                ForEach(pending.prefix(10)) { order in
                    HStack {
                        Text(order.orderNumber).font(.caption).fontWeight(.semibold)
                        Text(order.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2).foregroundColor(.textTertiary)
                        Spacer()
                        Text("฿\(fmt(order.supportGovernmentAmount, 0))")
                            .font(.system(.caption, design: .monospaced)).fontWeight(.bold)
                        Button(isThai ? "ยืนยันรัฐจ่ายแล้ว" : "Confirm Received") {
                            order.supportSettlementStatus = "received"
                            order.isSynced = false
                            order.updatedAt = Date()
                            modelContext.saveWithLogging(label: "reconcileGovernmentSupport")
                            refreshData()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            }
        }
        .padding(14)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.appBorderSubtle, lineWidth: 1))
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Helpers & Data Formatting
    // ─────────────────────────────────────────────────────────────────

    private var heroPeriodLabel: String {
        switch viewModel.summaryMode {
        case .shift:
            guard let session = branchSessions.first(where: { $0.id == viewModel.selectedRegisterSessionId }) else { return "—" }
            return shiftLabel(session)
        case .daily:
            return viewModel.selectedDate.formatted(date: .complete, time: .omitted)
        case .monthly:
            return "\(viewModel.selectedMonthName) \(viewModel.selectedYear)"
        }
    }

    private func colorForPaymentMethod(_ method: String) -> Color {
        switch method.lowercased() {
        case let m where m.contains("cash"):
            return Color.appAccent
        case let m where m.contains("credit") || m.contains("card"):
            return Color.appTeal
        case let m where m.contains("promptpay") || m.contains("qr"):
            return Color.appRose
        case let m where m.contains("truemoney") || m.contains("wallet"):
            return Color.appIndigo
        default:
            return Color.appAccent.opacity(0.6)
        }
    }

    private func colorForCategory(_ category: String) -> Color {
        switch category.lowercased() {
        case let c where c.contains("main") || c.contains("dish"):
            return Color.appAccent
        case let c where c.contains("appetizer") || c.contains("snack") || c.contains("starter"):
            return Color.appTeal
        case let c where c.contains("bev") || c.contains("drink") || c.contains("water") || c.contains("soda"):
            return Color.appRose
        default:
            let hash = abs(category.hashValue)
            let colors: [Color] = [.appAccent, .appTeal, .appRose, .appIndigo, .appAmber]
            return colors[hash % colors.count]
        }
    }

    private func kpiCard(_ title: String, _ value: String, _ subtitle: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Capsule()
                    .fill(color)
                    .frame(width: 3, height: 10)
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.textTertiary)
                    .tracking(0.5)
                    .lineLimit(1)
            }
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(color)
                .minimumScaleFactor(0.6).lineLimit(1)
                .contentTransition(.numericText())
            Text(subtitle).font(.system(size: 9.5)).foregroundColor(.textSecondary).lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
        .background(Color.appSurface)
        .cornerRadius(APRadius.md)
        .overlay(RoundedRectangle(cornerRadius: APRadius.md).stroke(Color.appBorderSubtle, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.02), radius: 4, x: 0, y: 2)
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
        emptyState(icon: "chart.bar", text: text)
    }

    private func emptyState(icon: String, text: String) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.appSurfaceHigh)
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.textTertiary)
            }
            Text(text)
                .font(.caption)
                .foregroundColor(.textTertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .center)
        .padding(.vertical, 8)
    }

    private func fmt(_ value: Double, _ decimals: Int = 2) -> String {
        value.formatted(.number.precision(.fractionLength(decimals)))
    }

    // ─────────────────────────────────────────────────────────────────
    // MARK: - Actions & Business Logic
    // ─────────────────────────────────────────────────────────────────

    private func refreshData() {
        guard let branchId = UUID(uuidString: activeBranchId) else { return }
        configureSelectedShift()
        if let branch = allOrders.first(where: { $0.branch.id == branchId })?.branch {
            viewModel.businessDayCutoffHour = branch.businessDayCutoffHour
            viewModel.businessTimeZoneID = branch.timeZoneID
        }
        viewModel.updateAnalytics(
            orders: allOrders.filter { $0.branch.id == branchId },
            inventoryItems: allInventory.filter { $0.branch?.id == branchId },
            employees: allEmployees.filter { UUID(uuidString: $0.branchId) == branchId },
            timecards: allTimecards.filter { UUID(uuidString: $0.employee?.branchId ?? "") == branchId },
            expenses: allExpenses.filter { $0.branch?.id == branchId },
            inventoryTransactions: inventoryLedger.filter { $0.branch.id == branchId },
            financialEvents: financialEvents.filter { $0.branchId == branchId }
        )
        APHaptic.trigger()
    }

    private var branchSessions: [RegisterSession] {
        guard let branchId = UUID(uuidString: activeBranchId) else { return [] }
        return registerSessions.filter { !$0.isDeleted && $0.branch.id == branchId }
    }

    private func configureSelectedShift() {
        guard viewModel.summaryMode == .shift else { return }
        let session = branchSessions.first(where: { $0.id == viewModel.selectedRegisterSessionId })
            ?? branchSessions.first
        viewModel.selectedRegisterSessionId = session?.id
        viewModel.selectedShiftInterval = session.map {
            DateInterval(start: $0.openedAt, end: ($0.closedAt ?? Date()).addingTimeInterval(0.001))
        }
    }

    private func shiftLabel(_ session: RegisterSession) -> String {
        let day = session.openedAt.formatted(.dateTime.day().month(.abbreviated))
        let opened = session.openedAt.formatted(date: .omitted, time: .shortened)
        let closed = (session.closedAt ?? Date()).formatted(date: .omitted, time: .shortened)
        return "\(day) · \(opened)–\(closed)"
    }

    private func triggerEntranceAnimations() {
        withAnimation(.easeOut(duration: 0.35)) { animateKPIs = true }
        withAnimation(.easeOut(duration: 0.5).delay(0.1)) { animateCharts = true }
    }

    @MainActor
    private func shareFullReportAction() {
        APHaptic.trigger()
        let reportView = SalesPDFReportView(
            title: viewModel.summaryMode == .daily
                ? (isThai ? "รายงานสรุปยอดขายประจำวัน" : "Daily Sales Summary")
                : (isThai ? "รายงานสรุปยอดขายประจำเดือน" : "Monthly Sales Summary"),
            subtitle: viewModel.summaryMode == .daily
                ? viewModel.selectedDate.formatted(date: .long, time: .omitted)
                : "\(viewModel.selectedMonthName) \(viewModel.selectedYear)",
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
        if let url = exportToPDF(view: reportView, filename: "AlphaPos_Financial_P&L_Report") {
            self.generatedPDFURL = url
            self.showingShareSheet = true
        }
    }

    @MainActor
    private func shareProductReportAction() {
        APHaptic.trigger()
        let reportView = ProductSalesPDFView(
            title: viewModel.summaryMode == .daily
                ? (isThai ? "รายงานยอดขายสินค้าประจำวัน" : "Daily Product Report")
                : (isThai ? "รายงานยอดขายสินค้าประจำเดือน" : "Monthly Product Report"),
            subtitle: viewModel.summaryMode == .daily
                ? viewModel.selectedDate.formatted(date: .long, time: .omitted)
                : "\(viewModel.selectedMonthName) \(viewModel.selectedYear)",
            generatedAt: Date().formatted(date: .abbreviated, time: .shortened),
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
