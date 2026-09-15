// ReportsView.swift
// AlphaPos — Reports Feature Module
//
// Main container view with sidebar navigation for all report types.
// Layout: Left panel (320px) for report selection + date filters,
// Right panel for the active report content.

import SwiftUI
import SwiftData

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Reports Main View
// ─────────────────────────────────────────────────────────────────────────────

struct ReportsView: View {
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var lm: LocalizationManager
    @EnvironmentObject private var sessionManager: AppSessionManager
    @AppStorage(BranchContext.storageKey) private var activeBranchId = ""

    @Query(filter: #Predicate<Order> { !$0.isDeleted }) private var allOrders: [Order]
    @Query(filter: #Predicate<Payment> { !$0.isDeleted }) private var allPayments: [Payment]
    @Query(filter: #Predicate<RegisterSession> { !$0.isDeleted }) private var allSessions: [RegisterSession]
    @Query(filter: #Predicate<CashMovement> { !$0.isDeleted }) private var allMovements: [CashMovement]
    @Query(filter: #Predicate<OrderTaxLine> { !$0.isDeleted }) private var allTaxLines: [OrderTaxLine]
    @Query(filter: #Predicate<MenuItem> { !$0.isDeleted }) private var allMenuItems: [MenuItem]
    @Query(filter: #Predicate<InventoryItem> { !$0.isDeleted }) private var allInventory: [InventoryItem]
    @Query(filter: #Predicate<InventoryTransaction> { !$0.isDeleted }) private var allInvTransactions: [InventoryTransaction]
    @Query(filter: #Predicate<InventoryLot> { !$0.isDeleted })         private var allInventoryLots: [InventoryLot]
    @Query(filter: #Predicate<Employee> { !$0.isDeleted }) private var allEmployees: [Employee]
    @Query(sort: \User.username) private var allUsers: [User]
    @Query(filter: #Predicate<Timecard> { !$0.isDeleted }) private var allTimecards: [Timecard]
    @Query(filter: #Predicate<Promotion> { !$0.isDeleted }) private var allPromotions: [Promotion]
    @Query(filter: #Predicate<OrderDiscount> { !$0.isDeleted }) private var allOrderDiscounts: [OrderDiscount]
    @Query(filter: #Predicate<PurchaseOrder> { !$0.isDeleted }) private var allPurchaseOrders: [PurchaseOrder]
    @Query(filter: #Predicate<RefundTransaction> { !$0.isDeleted }) private var allRefunds: [RefundTransaction]
    @Query(filter: #Predicate<Customer> { !$0.isDeleted }) private var allCustomers: [Customer]
    @Query(filter: #Predicate<Branch> { !$0.isDeleted }) private var allBranches: [Branch]
    @Query(filter: #Predicate<FinancialEvent> { !$0.isDeleted && $0.status == "posted" })
    private var allFinancialEvents: [FinancialEvent]

    @State private var viewModel = ReportsViewModel()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var branchSessions: [RegisterSession] {
        guard let branchId = UUID(uuidString: activeBranchId) else { return [] }
        return allSessions.filter { $0.branch.id == branchId }.sorted { $0.openedAt > $1.openedAt }
    }

    private var dateFilteredBranchSessions: [RegisterSession] {
        var calendar = Calendar(identifier: .gregorian)
        if let branchId = UUID(uuidString: activeBranchId),
           let branch = allBranches.first(where: { $0.id == branchId }) {
            calendar.timeZone = TimeZone(identifier: branch.timeZoneID) ?? .current
        }
        let start = calendar.startOfDay(for: viewModel.selectedDate)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return branchSessions.filter { session in
            session.openedAt < end && (session.closedAt ?? Date()) >= start
        }
    }

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            if horizontalSizeClass == .regular {
                GeometryReader { _ in
                    HStack(spacing: APSpacing.md) {
                        // LEFT PANEL — Report Type Selection + Date Filters
                        leftPanel
                            .frame(width: 320)

                        // RIGHT PANEL — Report Content
                        rightPanel
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .padding(.horizontal, APSpacing.md)
                    .padding(.top, 0)
                    .padding(.bottom, APSpacing.md)
                }
            } else {
                NavigationStack {
                    leftPanel
                        .padding(.horizontal, APSpacing.md)
                        .padding(.top, 0)
                        .padding(.bottom, APSpacing.md)
                        .navigationTitle(L.Reports.title.t)
                        .background(Color.appBackground)
                }
            }
        }
        .navigationTitle(L.Reports.title.t)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .onAppear {
            configureSelectedShiftIfNeeded()
            refreshCurrentReport()
        }
        .onChange(of: viewModel.selectedReport) { refreshCurrentReport() }
        .onChange(of: viewModel.periodMode) { refreshCurrentReport() }
        .onChange(of: viewModel.dateBasis) {
            configureSelectedShiftIfNeeded()
            refreshCurrentReport()
        }
        .onChange(of: viewModel.selectedRegisterSessionId) {
            configureSelectedShiftIfNeeded()
            refreshCurrentReport()
        }
        .onChange(of: viewModel.selectedDate) {
            if viewModel.dateBasis == .registerShift { configureSelectedShiftIfNeeded() }
            refreshCurrentReport()
        }
        .onChange(of: viewModel.rangeStart) {
            if viewModel.rangeEnd < viewModel.rangeStart { viewModel.rangeEnd = viewModel.rangeStart }
            refreshCurrentReport()
        }
        .onChange(of: viewModel.rangeEnd) { refreshCurrentReport() }
        .onChange(of: viewModel.comparisonMonths) { refreshCurrentReport() }
        .onChange(of: allFinancialEvents.count) { refreshCurrentReport() }
        .sheet(isPresented: $viewModel.showingShareSheet) {
            if let url = viewModel.generatedPDFURL {
                ShareSheet(activityItems: [url])
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Left Panel
    // ─────────────────────────────────────────────────────────────────────────

    private var leftPanel: some View {
        VStack(spacing: APSpacing.md) {
            if horizontalSizeClass == .regular {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(L.Reports.title.t)
                            .font(.headline)
                        Spacer()
                    }
                    Text(lm.currentLanguage == .thai ? "รายงานทางการเพื่อการตรวจสอบและยื่นภาษี" : "Official Audit, Fiscal & Tax Records")
                        .font(.system(size: 10))
                        .foregroundColor(.textSecondary)
                }
            }
            ScrollView {
                VStack(spacing: APSpacing.md) {
                    reportTypeList

                    Divider().opacity(0.3)

                    periodControls
                }
            }
            .scrollIndicators(.hidden)

            exportButton
        }
        .padding(APSpacing.md)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: APRadius.lg))
    }

    private var reportTypeList: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            ForEach(ReportType.Category.allCases, id: \.rawValue) { cat in
                let items = visibleReportTypes.filter { $0.category == cat }
                if !items.isEmpty {
                    VStack(alignment: .leading, spacing: APSpacing.xs) {
                        Text(cat.title(isThai: lm.currentLanguage == .thai).uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.appAccent)
                            .tracking(0.8)
                            .padding(.top, 4)

                        ForEach(items) { reportType in
                            if horizontalSizeClass == .compact {
                                NavigationLink {
                                    rightPanel
                                        .navigationTitle(localizedReportName(reportType))
                                        .background(Color.appBackground)
                                        .onAppear {
                                            viewModel.selectedReport = reportType
                                            refreshCurrentReport()
                                        }
                                } label: {
                                    reportTypeRow(reportType)
                                }
                            } else {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        viewModel.selectedReport = reportType
                                    }
                                } label: {
                                    reportTypeRow(reportType)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    private var visibleReportTypes: [ReportType] {
        ReportType.allCases.filter { canViewReport($0) }
    }

    private func canViewReport(_ report: ReportType) -> Bool {
        guard sessionManager.can(.reportsView) else { return false }
        switch report {
        case .menuProfitability:
            return sessionManager.can(.profitAnalyticsView) && sessionManager.can(.productCostsView)
        case .inventoryStock, .purchasing:
            return sessionManager.can(.inventoryView) && sessionManager.can(.productCostsView)
        case .taxVAT:
            return sessionManager.can(.accountingView)
        case .employeeHours:
            return sessionManager.can(.staffManage) || sessionManager.can(.payrollManage)
        case .customerAnalytics:
            return sessionManager.can(.customersManage)
        case .branchComparison:
            return sessionManager.can(.organizationView)
        default: return true
        }
    }

    private func reportTypeRow(_ reportType: ReportType) -> some View {
        HStack(spacing: APSpacing.sm) {
            Image(systemName: reportType.icon)
                .frame(width: 24)
                .foregroundStyle(viewModel.selectedReport == reportType ? Color.appAccent : .secondary)
            Text(localizedReportName(reportType))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(viewModel.selectedReport == reportType ? Color.primary : .secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, APSpacing.sm)
        .padding(.vertical, APSpacing.sm)
        .background(
            viewModel.selectedReport == reportType ?
            Color.appAccent.opacity(0.1) : Color.clear
        )
        .clipShape(RoundedRectangle(cornerRadius: APRadius.sm))
    }

    private var periodControls: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            Label(lm.currentLanguage == .thai ? "ขอบเขตข้อมูล" : "Reporting Scope", systemImage: "calendar.badge.clock")
                .font(.subheadline.weight(.semibold))

            Picker("", selection: $viewModel.dateBasis) {
                Text(lm.currentLanguage == .thai ? "กะ" : "Shift").tag(ReportDateBasis.registerShift)
                Text(lm.currentLanguage == .thai ? "วันทำการ" : "Business day").tag(ReportDateBasis.businessDay)
                Text(lm.currentLanguage == .thai ? "วันปฏิทิน" : "Calendar day").tag(ReportDateBasis.calendarDay)
            }
            .pickerStyle(.segmented)

            if viewModel.dateBasis == .registerShift {
                DatePicker(
                    lm.currentLanguage == .thai ? "วันที่ของกะ" : "Shift Date",
                    selection: $viewModel.selectedDate,
                    displayedComponents: .date
                )
                .font(.subheadline)

                Picker(lm.currentLanguage == .thai ? "เลือกกะ" : "Select shift", selection: $viewModel.selectedRegisterSessionId) {
                    // The initial selection is nil until onAppear resolves the
                    // newest shift, even when sessions already exist. Always
                    // provide a matching tag so Picker never enters an
                    // undefined selection state during its first render.
                    Text(dateFilteredBranchSessions.isEmpty
                         ? (lm.currentLanguage == .thai ? "ไม่มีกะในวันที่เลือก" : "No shifts on selected date")
                         : (lm.currentLanguage == .thai ? "กำลังเลือกกะ…" : "Selecting shift…"))
                        .tag(Optional<UUID>.none)
                    ForEach(dateFilteredBranchSessions) { session in
                        Text(reportShiftLabel(session)).tag(Optional(session.id))
                    }
                }
                .pickerStyle(.menu)
                .disabled(dateFilteredBranchSessions.isEmpty)

                Text("\(dateFilteredBranchSessions.count) " + (lm.currentLanguage == .thai ? "กะในวันที่เลือก" : "shift(s) on selected date"))
                    .font(.caption2)
                    .foregroundStyle(dateFilteredBranchSessions.isEmpty ? Color.orange : Color.secondary)
            } else {
                quickDatePresets

                Picker("", selection: $viewModel.periodMode) {
                    Text(L.Reports.periodDaily.t).tag(ReportPeriod.daily)
                    Text(L.Reports.periodWeekly.t).tag(ReportPeriod.weekly)
                    Text(L.Reports.periodMonthly.t).tag(ReportPeriod.monthly)
                    Text(L.Reports.periodCustom.t).tag(ReportPeriod.custom)
                }
                .pickerStyle(.segmented)

                if viewModel.periodMode == .custom {
                    VStack(spacing: APSpacing.xs) {
                        DatePicker(L.Reports.startDate.t, selection: $viewModel.rangeStart, displayedComponents: .date)
                        DatePicker(L.Reports.endDate.t, selection: $viewModel.rangeEnd, in: viewModel.rangeStart..., displayedComponents: .date)
                    }
                    .font(.subheadline)
                } else {
                    DatePicker(L.Reports.date.t, selection: $viewModel.selectedDate, displayedComponents: .date)
                        .font(.subheadline)
                }
            }

            HStack(spacing: APSpacing.xs) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.appTeal)
                VStack(alignment: .leading, spacing: 1) {
                    Text(lm.currentLanguage == .thai ? "ช่วงข้อมูลที่กำลังแสดง" : "Active reporting period")
                        .font(.caption2).foregroundStyle(.secondary)
                    Text(viewModel.periodDescription)
                        .font(.footnote.weight(.semibold)).monospacedDigit()
                }
            }
            .padding(APSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.appTeal.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: APRadius.sm))
        }
        .padding(APSpacing.sm)
        .background(Color.appSurfaceHigh.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
    }

    private var quickDatePresets: some View {
        HStack(spacing: 6) {
            quickDateButton(lm.currentLanguage == .thai ? "วันนี้" : "Today", icon: "sun.max") {
                viewModel.periodMode = .daily; viewModel.selectedDate = Date()
            }
            quickDateButton(lm.currentLanguage == .thai ? "เมื่อวาน" : "Yesterday", icon: "clock.arrow.circlepath") {
                viewModel.periodMode = .daily
                viewModel.selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
            }
            quickDateButton("7 " + (lm.currentLanguage == .thai ? "วัน" : "Days"), icon: "calendar") {
                viewModel.periodMode = .custom
                viewModel.rangeEnd = Date()
                viewModel.rangeStart = Calendar.current.date(byAdding: .day, value: -6, to: Date()) ?? Date()
            }
            quickDateButton(lm.currentLanguage == .thai ? "เดือนนี้" : "Month", icon: "calendar.circle") {
                viewModel.periodMode = .monthly; viewModel.selectedDate = Date()
            }
        }
    }

    private func quickDateButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.caption)
                Text(title).font(.system(size: 9, weight: .semibold)).lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(Color.appAccent.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: APRadius.sm))
        }
        .buttonStyle(.plain)
    }

    private var exportButton: some View {
        Button {
            exportCurrentReport()
        } label: {
            HStack {
                if viewModel.isGeneratingPDF {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "square.and.arrow.up")
                }
                Text(L.Reports.exportPDF.t)
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, APSpacing.sm)
            .background(Color.appAccent)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: APRadius.sm))
        }
        .disabled(viewModel.isGeneratingPDF)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Right Panel
    // ─────────────────────────────────────────────────────────────────────────

    private var rightPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: APSpacing.md) {
                // Header
                HStack(spacing: APSpacing.sm) {
                    ZStack {
                        RoundedRectangle(cornerRadius: APRadius.md, style: .continuous)
                            .fill(APGradient.accent)
                            .frame(width: 44, height: 44)
                        Image(systemName: viewModel.selectedReport.icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    VStack(alignment: .leading, spacing: APSpacing.xs) {
                        Text(localizedReportName(viewModel.selectedReport))
                            .font(.title2.weight(.bold))
                            .contentTransition(.opacity)
                        HStack(spacing: 6) {
                            Label(viewModel.periodDescription, systemImage: "calendar")
                            Text("•")
                            Text(activeDateBasisLabel)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        refreshCurrentReport()
                    } label: {
                        Label(lm.currentLanguage == .thai ? "รีเฟรช" : "Refresh", systemImage: "arrow.clockwise")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(Color.appAccent.opacity(0.1))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, APSpacing.sm)

                // Report content — animated cross-fade when switching reports
                reportContent
                    .id(viewModel.selectedReport)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .trailing)),
                        removal: .opacity
                    ))
            }
            .padding(APSpacing.md)
            .animation(.easeInOut(duration: 0.25), value: viewModel.selectedReport)
        }
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: APRadius.lg))
    }

    private var activeDateBasisLabel: String {
        switch viewModel.dateBasis {
        case .registerShift: return lm.currentLanguage == .thai ? "ตามกะ" : "Shift basis"
        case .businessDay: return lm.currentLanguage == .thai ? "วันทำการ" : "Business-day basis"
        case .calendarDay: return lm.currentLanguage == .thai ? "วันปฏิทิน" : "Calendar-day basis"
        }
    }

    @ViewBuilder
    private var reportContent: some View {
        if !canViewReport(viewModel.selectedReport) {
            ContentUnavailableView("ไม่มีสิทธิ์ดูรายงานนี้", systemImage: "lock.shield")
        } else {
        switch viewModel.selectedReport {
        case .dailySales:
            DailySalesReportView(viewModel: viewModel)
        case .productSales:
            ProductSalesReportView(viewModel: viewModel, onScopeChange: refreshCurrentReport)
        case .zReport:
            ZReportView(viewModel: viewModel)
        case .taxVAT:
            TaxReportView(viewModel: viewModel)
        case .menuProfitability:
            MenuProfitabilityReportView(viewModel: viewModel, onScopeChange: refreshCurrentReport)
        case .inventoryStock:
            VStack(spacing: 0) {
                        // Toggle bar
                        Picker("", selection: $viewModel.showInventoryAnalytics) {
                            Text("สรุปทั่วไป").tag(false)
                            Text("Analytics").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .padding(.bottom, APSpacing.sm)

                        if viewModel.showInventoryAnalytics {
                            InventoryAnalyticsReportView(
                                viewModel: viewModel,
                                allInventory: allInventory,
                                allTransactions: allInvTransactions,
                                allLots: allInventoryLots
                            )
                        } else {
                            InventoryReportView(viewModel: viewModel)
                        }
                    }
        case .purchasing:
            PurchasingReportView(viewModel: viewModel)
        case .refundsVoids:
            RefundsVoidsReportView(viewModel: viewModel)
        case .customerAnalytics:
            CustomerAnalyticsReportView(viewModel: viewModel)
        case .branchComparison:
            BranchComparisonReportView(viewModel: viewModel)
        case .salesForecast:
            SalesForecastReportView(viewModel: viewModel)
        case .employeeHours:
            EmployeeHoursReportView(viewModel: viewModel)
        case .monthlyComparison:
            MonthlyComparisonReportView(viewModel: viewModel)
        case .promotionPerformance:
            PromotionPerformanceReportView(viewModel: viewModel)
        }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Actions
    // ─────────────────────────────────────────────────────────────────────────

    private func refreshCurrentReport() {
        guard canViewReport(viewModel.selectedReport) else { return }
        guard let branchId = UUID(uuidString: activeBranchId) else { return }
        let branchOrders = allOrders.filter { $0.branch.id == branchId }
        let branchPayments = allPayments.filter { $0.order?.branch.id == branchId }
        let branchSessions = allSessions.filter { $0.branch.id == branchId }
        let branchMovements = allMovements.filter { $0.registerSession?.branch.id == branchId }
        let branchTaxLines = allTaxLines.filter { $0.order?.branch.id == branchId }
        let branchInventory = allInventory.filter { $0.branch?.id == branchId }
        let branchTransactions = allInvTransactions.filter { $0.branch.id == branchId }
        let branchEmployees = allEmployees.filter { UUID(uuidString: $0.branchId) == branchId }
        let branchTimecards = allTimecards.filter { UUID(uuidString: $0.employee?.branchId ?? "") == branchId }
        let branchPurchaseOrders = allPurchaseOrders.filter { $0.branch?.id == branchId }
        let branchRefunds = allRefunds.filter { $0.order?.branch.id == branchId }
        let branchEvents = allFinancialEvents.filter { $0.branchId == branchId }
        viewModel.modelContext = modelContext
        if let branch = allBranches.first(where: { $0.id == branchId }) {
            viewModel.businessDayCutoffHour = branch.businessDayCutoffHour
            viewModel.businessTimeZoneID = branch.timeZoneID
        }
        viewModel.configureRecognizedSalesScope(financialEvents: branchEvents)
        switch viewModel.selectedReport {
        case .dailySales:
            refreshDailySales(isOfflineMode: UserDefaults.standard.bool(forKey: "offline_sync_mode"))
        case .productSales:
            viewModel.computeProductSales(orders: branchOrders, menuItems: allMenuItems)
        case .zReport:
            viewModel.computeZReport(
                sessions: branchSessions, movements: branchMovements,
                orders: branchOrders, payments: branchPayments,
                refunds: branchRefunds, employees: branchEmployees, users: allUsers
            )
        case .taxVAT:
            viewModel.computeTaxReport(orders: branchOrders, taxLines: branchTaxLines, purchaseOrders: branchPurchaseOrders)
        case .menuProfitability:
            viewModel.computeMenuProfitability(orders: branchOrders, menuItems: allMenuItems)
        case .inventoryStock:
            viewModel.computeInventoryReport(items: branchInventory, transactions: branchTransactions)
            // Analytics view uses allInventoryLots passed directly — no extra compute step needed
        case .purchasing:
            viewModel.computePurchasingReport(purchaseOrders: branchPurchaseOrders)
        case .refundsVoids:
            viewModel.computeRefundVoidReport(refunds: branchRefunds, orders: branchOrders, employees: branchEmployees)
        case .customerAnalytics:
            viewModel.computeCustomerAnalytics(customers: allCustomers, orders: branchOrders)
        case .branchComparison:
            viewModel.computeBranchComparison(orders: allOrders, branches: allBranches)
        case .salesForecast:
            viewModel.computeSalesForecast(orders: branchOrders)
        case .employeeHours:
            viewModel.computeEmployeeHours(employees: branchEmployees, timecards: branchTimecards)
        case .monthlyComparison:
            // L-2: trigger re-computation when range or data changes
            viewModel.computeMonthlyComparison(orders: branchOrders, payments: branchPayments, taxLines: branchTaxLines)
        case .promotionPerformance:
            viewModel.computePromotionPerformance(orders: branchOrders, promotions: allPromotions, discounts: allOrderDiscounts.filter { $0.order?.branch.id == branchId })
        }
    }

    /// Local SwiftData compute always; when online, pull completed sales then recompute.
    private func refreshDailySales(isOfflineMode: Bool) {
        guard let branchId = UUID(uuidString: activeBranchId) else { return }
        let branchOrders = allOrders.filter { $0.branch.id == branchId }
        let branchPayments = allPayments.filter { $0.order?.branch.id == branchId }
        let branchEvents = allFinancialEvents.filter { $0.branchId == branchId }
        viewModel.computeDailySales(
            orders: branchOrders,
            payments: branchPayments,
            financialEvents: branchEvents,
            isOfflineMode: isOfflineMode
        )
        guard !isOfflineMode else { return }

        Task {
            await SyncEngine.shared.pullCompletedOrdersAndPayments(modelContext)
            await MainActor.run {
                let orderDescriptor = FetchDescriptor<Order>(predicate: #Predicate { !$0.isDeleted })
                let paymentDescriptor = FetchDescriptor<Payment>(predicate: #Predicate { !$0.isDeleted })
                let orders = (try? modelContext.fetch(orderDescriptor)) ?? allOrders
                let payments = (try? modelContext.fetch(paymentDescriptor)) ?? allPayments
                let eventDescriptor = FetchDescriptor<FinancialEvent>(predicate: #Predicate {
                    !$0.isDeleted && $0.status == "posted"
                })
                let events = (try? modelContext.fetch(eventDescriptor)) ?? allFinancialEvents
                viewModel.computeDailySales(
                    orders: orders.filter { $0.branch.id == branchId },
                    payments: payments.filter { $0.order?.branch.id == branchId },
                    financialEvents: events.filter { $0.branchId == branchId },
                    isOfflineMode: false
                )
            }
        }
    }

    private func configureSelectedShiftIfNeeded() {
        guard viewModel.dateBasis == .registerShift else { return }
        if viewModel.periodMode != .daily { viewModel.periodMode = .daily }
        let session = dateFilteredBranchSessions.first(where: { $0.id == viewModel.selectedRegisterSessionId })
            ?? dateFilteredBranchSessions.first
        viewModel.selectedRegisterSessionId = session?.id
        viewModel.selectedShiftInterval = session.map {
            DateInterval(start: $0.openedAt, end: ($0.closedAt ?? Date()).addingTimeInterval(0.001))
        }
    }

    private func reportShiftLabel(_ session: RegisterSession) -> String {
        let day = session.openedAt.formatted(.dateTime.day().month(.abbreviated))
        let opened = session.openedAt.formatted(date: .omitted, time: .shortened)
        let closed = (session.closedAt ?? Date()).formatted(date: .omitted, time: .shortened)
        return "\(day) · \(opened)–\(closed)"
    }

    private func exportCurrentReport() {
        guard canViewReport(viewModel.selectedReport) else { return }
        if viewModel.selectedReport == .dailySales {
            let ud = UserDefaults.standard
            let storeName = ud.string(forKey: "store_name") ?? "AlphaPos"

            // Resolve the actual branch NAME from SwiftData (the old code
            // passed the branch *code* into the name field).
            var branchName: String? = nil
            branchName = (try? BranchContext.shared.requireActiveBranch(in: modelContext))?.name

            viewModel.generateDailySalesPDF(
                storeName: storeName,
                taxId: ud.string(forKey: "store_tax_id"),
                branchName: branchName,
                storeAddress: ud.string(forKey: "store_address"),
                storePhone: ud.string(forKey: "store_phone"),
                branchCode: ud.string(forKey: "store_branch_code")
            )
            return
        }

        if viewModel.selectedReport == .productSales {
            viewModel.generateProductSalesPDF(storeName: UserDefaults.standard.string(forKey: "store_name") ?? "AlphaPos")
            return
        }

        // Analytics report uses CoreGraphics multi-page PDF exporter
        if viewModel.selectedReport == .inventoryStock && viewModel.showInventoryAnalytics {
            let analytics = InventoryAnalytics(
                items: allInventory,
                transactions: allInvTransactions,
                lots: allInventoryLots,
                start: viewModel.effectiveStartDate,
                end: viewModel.effectiveEndDate
            )
            viewModel.generateInventoryAnalyticsPDF(analytics: analytics)
        } else {
            // Existing single-page ImageRenderer export
            let title = localizedReportName(viewModel.selectedReport).replacingOccurrences(of: " ", with: "_")
            viewModel.generatePDF(title: title, content: reportContent)
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Localization Helper
    // ─────────────────────────────────────────────────────────────────────────

    private func localizedReportName(_ type: ReportType) -> String {
        switch type {
        case .dailySales:       return L.Reports.dailySales.t
        case .productSales:     return "รายงานยอดขายตามสินค้า"
        case .zReport:          return L.Reports.zReport.t
        case .taxVAT:           return L.Reports.taxVAT.t
        case .menuProfitability: return L.Reports.menuProfit.t
        case .inventoryStock:   return L.Reports.inventory.t
        case .purchasing:       return "report_purchasing_title".t
        case .refundsVoids:     return "report_refunds_voids_title".t
        case .customerAnalytics: return "report_customer_analytics_title".t
        case .branchComparison: return "report_branch_comparison_title".t
        case .salesForecast:    return "report_sales_forecast_title".t
        case .employeeHours:    return L.Reports.employeeHours.t
        case .monthlyComparison: return "report_monthly_comparison_title".t
        case .promotionPerformance: return "report_promotion_performance_title".t
        }
    }
}
