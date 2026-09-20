// LiveDashboardView.swift
// AlphaPos — Enterprise Live KPI Dashboard (v2 — Real Data)
// Wired to SwiftData @Query for live, real-time metrics.

import SwiftUI
import SwiftData
import Charts
import os

private let dashboardPerformanceLog = OSLog(
    subsystem: Bundle.main.bundleIdentifier ?? "AlphaPos",
    category: "DashboardPerformance"
)

private struct DashboardSection: Identifiable {
    let id: String
    let content: AnyView
}

private enum DashboardPresentationMode: String {
    case simple
    case full
}

/// Real-time KPI Dashboard showing live business metrics from SwiftData.
/// This is the "home" landing page for the Master Device.
///
/// Data sources:
/// - Orders (@Query) → revenue, order count, avg prep time
/// - RestaurantTables (@Query) → table occupancy
/// - OrderItems (via Orders) → top selling items
/// - Timecards (@Query) → staff on duty
struct LiveDashboardView: View {
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var lm: LocalizationManager
    @EnvironmentObject private var sessionManager: AppSessionManager
    @AppStorage(BranchContext.storageKey) private var activeBranchId = ""
    @AppStorage("app_currency_symbol") private var currencySymbol = "฿"
    @AppStorage(GovernmentSupportProgram.enabledSettingsKey) private var thaiChuaThaiPlusEnabled = true
    @AppStorage("offline_sync_mode") private var offlineSyncMode = false
    @AppStorage("enable_table_system") private var tableSystemEnabled = true
    @AppStorage("dashboard_presentation_mode") private var presentationModeRawValue = DashboardPresentationMode.full.rawValue

    // MARK: - SwiftData Queries

    /// All orders (sorted newest first) — used for revenue, counts, activity
    @Query(filter: #Predicate<Order> { !$0.isDeleted }, sort: \Order.createdAt, order: .reverse)
    private var allOrders: [Order]

    /// All tables — used for occupancy calculation
    @Query(filter: #Predicate<RestaurantTable> { !$0.isDeleted })
    private var allTables: [RestaurantTable]

    /// Active timecards (staff currently on duty)
    @Query(filter: #Predicate<Timecard> { $0.clockOut == nil })
    private var activeTimecards: [Timecard]

    /// All inventory items — used for stock alerts
    @Query(filter: #Predicate<InventoryItem> { !$0.isDeleted })
    private var inventoryItems: [InventoryItem]

    /// Immutable sale-ledger costs are preferred over today's recipe prices for
    /// historical gross-profit reporting.
    @Query(filter: #Predicate<InventoryTransaction> {
        !$0.isDeleted &&
        ($0.transactionType == "sell" || $0.transactionType == "refund_return")
    })
    private var inventoryTransactions: [InventoryTransaction]

    @Query(filter: #Predicate<RegisterSession> { !$0.isDeleted }, sort: \RegisterSession.openedAt, order: .reverse)
    private var registerSessions: [RegisterSession]
    @Query(filter: #Predicate<Branch> { !$0.isDeleted }) private var branches: [Branch]
    @Query(filter: #Predicate<FinancialEvent> { !$0.isDeleted && $0.status == "posted" })
    private var financialEvents: [FinancialEvent]

    // MARK: - State

    @State private var refreshTimer: Timer? = nil
    @State private var currentTime = Date()
    @State private var gradientShift = false
    @State private var livePulse = false
    @State private var generatedPDFURL: URL? = nil
    @State private var showingShareSheet = false
    @State private var showingHourlySalesFullScreen = false
    @State private var showingAddOnBreakdownSheet = false
    @State private var addOnBreakdownChannel: DashboardSalesChannel = .all
    @State private var showingTransferBreakdownSheet = false
    @State private var showingOrderVoidSheet = false
    @State private var selectedOrderForVoid: Order? = nil
    @State private var isExportingPDF = false
    @State private var showExportError = false
    @State private var selectedPeriod: DashboardPeriod = .currentShift
    @State private var selectedChannel: DashboardSalesChannel = .all
    @State private var selectedComparison: DashboardComparison = .previousPeriod
    @State private var selectedCashier = "all"
    @State private var selectedRegisterSessionId: UUID?
    
    /// Automatically filter dashboard sections based on logged-in user's role & permissions
    private var effectiveViewMode: DashboardViewMode {
        guard let session = sessionManager.currentStaffSession else {
            return .all
        }
        if !session.permissions.contains(.reportsView) && !session.permissions.contains(.dashboardView) && !session.permissions.contains(.profitAnalyticsView) {
            return .operations
        }
        return .all
    }
    @State private var hourlyChartMetric: HourlyChartMetric = .revenue
    @State private var selectedDeliveryOrderForEdit: Order? = nil
    @State private var showingQuickPOSheet = false
    @State private var chartAnimationProgress = 0.0
    @State private var cachedMetrics = DashboardAggregatedMetrics()
    @State private var hasLoadedMetrics = false
    @State private var isRefreshingMetrics = false
    @State private var cachedComparisonMetrics = DashboardComparisonMetrics()
    @State private var lastComparisonScopeKey = ""
    @State private var hasLoadedComparisonMetrics = false

    /// A ninth-generation iPad has ample capacity for business calculations,
    /// but animating every chart and translucent surface while those results
    /// are materialized causes avoidable frame drops.  Keep motion on faster
    /// form factors and preserve the user's Reduce Motion preference.
    private var allowsDecorativeDashboardMotion: Bool {
        !reduceMotion && UIDevice.current.userInterfaceIdiom != .pad
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ForEach(dashboardSections) { section in
                    section.content
                }
            }
            .padding(.horizontal, APSpacing.md)
            .padding(.top, 0)
            .padding(.bottom, APSpacing.md)
        }
        .contentMargins(.top, 0, for: .scrollContent)
        .background(dashboardBackground)
        .navigationTitle("dashboard_title".t)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 8) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.appRose)
                            .frame(width: 7, height: 7)
                        Text("LIVE")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.appRose)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.appRose.opacity(0.1))
                    .clipShape(Capsule())

                    Text(currentTime.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.textSecondary)
                }
            }
        }
        .redacted(reason: hasLoadedMetrics ? [] : .placeholder)
        .allowsHitTesting(hasLoadedMetrics)
        .task(id: metricsRefreshKey) {
            await refreshMetricsDebounced()
        }
        .overlay(alignment: .topTrailing) {
            if isRefreshingMetrics && hasLoadedMetrics {
                ProgressView()
                    .controlSize(.small)
                    .padding(10)
                    .accessibilityLabel(lm.currentLanguage == .thai ? "กำลังอัปเดต Dashboard" : "Updating dashboard")
            }
        }
        .onAppear {
            if allowsDecorativeDashboardMotion {
                withAnimation(.easeInOut(duration: 7).repeatForever(autoreverses: true)) {
                    gradientShift = true
                }
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    livePulse = true
                }
            }
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
                currentTime = Date()
            }
            restartChartAnimation()
        }
        .onDisappear {
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
        .onChange(of: selectedPeriod) { _, _ in
            restartChartAnimation()
        }
        .onChange(of: selectedRegisterSessionId) { _, _ in restartChartAnimation() }
        .onChange(of: selectedComparison) { _, _ in restartChartAnimation() }
        .onChange(of: selectedChannel) { _, _ in restartChartAnimation() }
        .onChange(of: selectedCashier) { _, _ in restartChartAnimation() }
        .onChange(of: activeBranchId) { _, _ in restartChartAnimation() }
        .sheet(isPresented: $showingShareSheet) {
            if let url = generatedPDFURL {
                ShareSheet(activityItems: [url])
            }
        }
        .sheet(item: $selectedDeliveryOrderForEdit) { order in
            DeliveryOrderQuickEditSheet(order: order) {
                Task { await refreshMetricsDebounced() }
            }
        }
        .sheet(isPresented: $showingQuickPOSheet) {
            QuickPOGeneratorSheet(lowStockItems: lowStockItems, branch: activeBranch) {
                Task { await refreshMetricsDebounced() }
            }
        }
        .sheet(isPresented: $showingAddOnBreakdownSheet) {
            AddOnBreakdownSheet(
                initialChannel: addOnBreakdownChannel,
                allAddOns: addOnBreakdown,
                allRevenue: addOnsRevenue,
                allQuantity: addOnsSold,
                storefrontAddOns: storefrontAddOnBreakdown,
                storefrontRevenue: storefrontAddOnsRevenue,
                storefrontQuantity: storefrontAddOnsSold,
                deliveryAddOns: deliveryAddOnBreakdown,
                deliveryRevenue: deliveryAddOnsRevenue,
                deliveryQuantity: deliveryAddOnsSold,
                currencySymbol: currencySymbol,
                isThai: lm.currentLanguage == .thai
            )
        }
        .sheet(isPresented: $showingTransferBreakdownSheet) {
            TransferBreakdownSheet(
                transfers: transferBreakdown,
                totalTransfer: transferTenderTotal,
                currencySymbol: currencySymbol,
                isThai: lm.currentLanguage == .thai
            )
        }
        .sheet(isPresented: $showingOrderVoidSheet) {
            OrderVoidManagementSheet(
                initialOrder: selectedOrderForVoid,
                onVoidCompleted: {
                    selectedOrderForVoid = nil
                    Task { await refreshMetricsDebounced() }
                }
            )
        }
        .fullScreenCover(isPresented: $showingHourlySalesFullScreen) {
            hourlySalesFullScreen
        }
        .overlay {
            if isExportingPDF {
                ZStack {
                    Color.black.opacity(0.18).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView().controlSize(.large).tint(.appAccent)
                        Text("กำลังจัดทำรายงาน PDF…")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.textPrimary)
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 22)
                    .apLiquidGlass(tint: Color.appAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .transition(.opacity)
            }
        }
        .alert("ไม่สามารถสร้าง PDF ได้", isPresented: $showExportError) {
            Button("ตกลง", role: .cancel) {}
        }
    }

    /// A homogeneous, type-erased section list avoids asking the Swift runtime
    /// to recursively substitute one enormous conditional generic view type.
    /// This is particularly important on older physical iPads in Debug builds.
    private var dashboardSections: [DashboardSection] {
        var sections: [DashboardSection] = [
            .init(id: "header", content: AnyView(headerSection.dashboardAppear(0.0))),
            .init(id: "filters", content: AnyView(dashboardFilterBar.dashboardAppear(0.02))),
            .init(id: "health", content: AnyView(dataHealthStrip.dashboardAppear(0.03)))
        ]

        if presentationMode == .simple {
            sections.append(.init(id: "simple-summary", content: AnyView(simpleDashboardSection.dashboardAppear(0.08))))
            return sections
        }

        if effectiveViewMode == .all || effectiveViewMode == .executive {
            sections.append(.init(id: "storewide-overview", content: AnyView(storewideOverviewSection.dashboardAppear(0.1))))
        }
        if effectiveViewMode == .all || effectiveViewMode == .operations || effectiveViewMode == .executive {
            sections.append(.init(id: "storefront-operations", content: AnyView(storefrontOperationsSection.dashboardAppear(0.12))))
            sections.append(.init(id: "delivery-credit", content: AnyView(deliveryCreditSection.dashboardAppear(0.14))))
        }
        if (effectiveViewMode == .all || effectiveViewMode == .operations) && !dashboardExceptions.isEmpty {
            sections.append(.init(id: "exceptions", content: AnyView(exceptionCenterCard.dashboardAppear(0.13))))
        }
        if (effectiveViewMode == .all || effectiveViewMode == .operations) && !lowStockItems.isEmpty {
            sections.append(.init(id: "low-stock", content: AnyView(lowStockWarningBanner.dashboardAppear(0.15))))
        }
        if effectiveViewMode == .all || effectiveViewMode == .executive {
            let financialPair = HStack(alignment: .top, spacing: 16) {
                AnyView(financialSummaryCard)
                AnyView(paymentMixCard)
            }
            sections.append(.init(id: "financial-pair", content: AnyView(financialPair.dashboardAppear(0.22))))
            sections.append(.init(id: "sales-channel", content: AnyView(salesChannelOverviewCard.dashboardAppear(0.24))))
        }
        if !todayDeliveryPlatforms.isEmpty {
            sections.append(.init(id: "delivery-channels", content: AnyView(deliveryChannelsCard.dashboardAppear(0.25))))
        }

        let chartPair = HStack(spacing: 16) {
            AnyView(hourlySalesChartCard)
            AnyView(categoryBreakdownChartCard)
        }
        sections.append(.init(id: "charts", content: AnyView(chartPair.dashboardAppear(0.28))))

        if effectiveViewMode == .all || effectiveViewMode == .executive {
            if canViewProfitAndCosts {
                let profitPair = HStack(spacing: 16) {
                    AnyView(revenueBridgeChartCard)
                    AnyView(profitCompositionChartCard)
                }
                sections.append(.init(id: "profit", content: AnyView(profitPair.dashboardAppear(0.31))))
            } else {
                sections.append(.init(id: "revenue-bridge", content: AnyView(revenueBridgeChartCard.dashboardAppear(0.31))))
            }
        }
        if effectiveViewMode == .all || effectiveViewMode == .operations {
            let operationsPair = HStack(spacing: 16) {
                AnyView(topSellingItemsCard)
                AnyView(staffOnDutyCard)
            }
            sections.append(.init(id: "operations", content: AnyView(operationsPair.dashboardAppear(0.34))))
            sections.append(.init(id: "activity", content: AnyView(activitySection.dashboardAppear(0.4))))
        }
        return sections
    }

    private var presentationMode: DashboardPresentationMode {
        DashboardPresentationMode(rawValue: presentationModeRawValue) ?? .full
    }

    /// Subtle ambient background: base color with two soft radial glows that
    /// drift slowly for a modern, non-distracting depth effect.
    private var dashboardBackground: some View {
        ZStack {
            Color.appBackground
            RadialGradient(
                colors: [Color.appAccent.opacity(0.08), .clear],
                center: gradientShift ? .topLeading : .topTrailing,
                startRadius: 40, endRadius: 500
            )
            RadialGradient(
                colors: [Color.appTeal.opacity(0.06), .clear],
                center: gradientShift ? .bottomTrailing : .bottomLeading,
                startRadius: 60, endRadius: 600
            )
            RadialGradient(
                colors: [Color(hex: "8B5CF6").opacity(0.07), .clear],
                center: .center,
                startRadius: 20, endRadius: 420
            )
        }
        .ignoresSafeArea()
    }

    // MARK: - Computed Data

    private var activeBranchUUID: UUID? { UUID(uuidString: activeBranchId) }
    private var activeBranch: Branch? {
        guard let branchId = activeBranchUUID else { return nil }
        return branches.first { !$0.isDeleted && $0.id == branchId }
            ?? branchOrders.first?.branch
    }
    private var branchRegisterSessions: [RegisterSession] {
        guard let branchId = activeBranchUUID else { return [] }
        return registerSessions.filter { !$0.isDeleted && $0.branch.id == branchId }
    }
    private var currentRegisterSession: RegisterSession? { branchRegisterSessions.first { $0.closedAt == nil } }
    private var selectedHistoricalSession: RegisterSession? {
        if let selectedRegisterSessionId,
           let selected = branchRegisterSessions.first(where: { $0.id == selectedRegisterSessionId }) {
            return selected
        }
        return branchRegisterSessions.first(where: { $0.closedAt != nil })
    }
    private var branchOrders: [Order] {
        guard let branchId = activeBranchUUID else { return [] }
        return allOrders.filter { $0.branch.id == branchId }
    }
    private var branchTables: [RestaurantTable] {
        allTables.filter { $0.branchId.caseInsensitiveCompare(activeBranchId) == .orderedSame }
    }
    private var branchInventoryItems: [InventoryItem] {
        guard let branchId = activeBranchUUID else { return [] }
        return inventoryItems.filter { $0.branch?.id == branchId }
    }

    private var selectedDateInterval: DateInterval {
        if selectedPeriod == .currentShift, let session = currentRegisterSession {
            return DateInterval(start: session.openedAt, end: currentTime.addingTimeInterval(0.001))
        }
        if selectedPeriod == .historicalShift, let session = selectedHistoricalSession {
            return DateInterval(start: session.openedAt, end: (session.closedAt ?? currentTime).addingTimeInterval(0.001))
        }
        if selectedPeriod == .businessDay, let branch = activeBranch {
            return selectedPeriod.businessInterval(containing: currentTime, cutoffHour: branch.businessDayCutoffHour, timeZoneID: branch.timeZoneID)
        }
        return selectedPeriod.interval(containing: currentTime, calendar: .current)
    }

    private var comparisonDateInterval: DateInterval {
        if selectedPeriod.usesRegisterSession,
           let selected = selectedPeriod == .currentShift ? currentRegisterSession : selectedHistoricalSession,
           let previous = branchRegisterSessions.first(where: {
               $0.id != selected.id && $0.closedAt != nil && $0.openedAt < selected.openedAt
           }) {
            return DateInterval(start: previous.openedAt, end: previous.closedAt!.addingTimeInterval(0.001))
        }
        return selectedComparison.interval(before: selectedDateInterval, calendar: .current)
    }

    private func matchesGlobalFilters(_ order: Order) -> Bool {
        selectedChannel.matches(order) &&
        (selectedCashier == "all" || order.cashierName == selectedCashier)
    }

    // MARK: - Optimized Consolidated Aggregation Model

    fileprivate struct DashboardAddOnDetail: Identifiable {
        let id = UUID()
        let name: String
        var quantity: Int
        var revenue: Double
    }

    fileprivate struct DashboardTransferDetail: Identifiable {
        let id = UUID()
        let methodKey: String
        let displayName: String
        let amount: Double
        let count: Int
    }

    private struct DashboardAggregatedMetrics {
        var todayGrossSales: Double = 0
        var todayDiscounts: Double = 0
        var todayRefunds: Double = 0
        var todayRevenue: Double = 0
        var todayVATCollected: Double = 0
        var todayServiceCharge: Double = 0

        var completedOrdersCount: Int = 0
        var storefrontOrdersCount: Int = 0
        var deliveryOrdersCount: Int = 0

        var storefrontSalesTotal: Double = 0
        var dineInSalesTotal: Double = 0
        var takeOutSalesTotal: Double = 0
        var storefrontGrossSales: Double = 0
        var storefrontDiscounts: Double = 0
        var deliverySalesTotal: Double = 0
        var deliveryGrossSales: Double = 0
        var deliveryDiscounts: Double = 0
        var cashTenderTotal: Double = 0
        var transferTenderTotal: Double = 0

        var itemsSold: Int = 0
        var addOnsSold: Int = 0
        var addOnsRevenue: Double = 0
        var storefrontAddOnsSold: Int = 0
        var storefrontAddOnsRevenue: Double = 0
        var deliveryAddOnsSold: Int = 0
        var deliveryAddOnsRevenue: Double = 0
        var bundleComponentsSold: Int = 0
        var bundleComponentsRevenue: Double = 0
        var promotionRewardsSold: Int = 0
        var promotionRewardsValue: Double = 0
        var totalGuests: Int = 0
        var avgOrderValue: Double = 0

        var todayCOGS: Double = 0
        var grossProfit: Double = 0
        var grossMargin: Double = 0

        var todayPaymentMix: [(method: String, amount: Double, count: Int)] = []
        var todaySettlementMix: [(method: String, amount: Double, count: Int)] = []
        var todayDeliveryPlatforms: [DashboardDeliveryPlatform] = []
        var salesChannelSummaries: [DashboardChannelSummary] = []
        var topStorefrontItems: [(name: String, category: String, quantity: Int, revenue: Double)] = []
        var topDeliveryItems: [(name: String, category: String, quantity: Int, revenue: Double)] = []
        var chartSalesData: [DashboardHourlySalesPoint] = []
        var chartCategoryData: [DashboardCategorySalesPoint] = []
        var dashboardExceptions: [DashboardException] = []
        var addOnBreakdown: [DashboardAddOnDetail] = []
        var storefrontAddOnBreakdown: [DashboardAddOnDetail] = []
        var deliveryAddOnBreakdown: [DashboardAddOnDetail] = []
        var transferBreakdown: [DashboardTransferDetail] = []
        var todayVoidedOrdersCount: Int = 0
        var todayVoidedAmount: Double = 0

        var isSelectedLedgerComplete: Bool = true
        var todaySettledAmount: Double = 0
        var todaySettlementVariance: Double = 0
        var todayDeliveryPlatformFees: Double = 0
        var estimatedNetProceeds: Double = 0
        var todaySupportCitizenContribution: Double = 0
        var todaySupportGovernmentContribution: Double = 0
        var pendingSupportSettlementOrders: [Order] = []

        var yesterdayRevenue: Double = 0
        var previousBills: Int = 0
        var previousItems: Int = 0
        var previousDiscounts: Double = 0
        var previousRefunds: Double = 0
        var previousProfit: Double = 0
        var previousMargin: Double = 0

        var completedTodayOrders: [Order] = []
        var completedStorefrontOrders: [Order] = []
        var completedDeliveryOrders: [Order] = []
        var comparisonOrders: [Order] = []
        var todayOrders: [Order] = []
    }

    /// Stable snapshot consumed by every card in this render. Previously this
    /// was a computed property, so every accessor rebuilt the complete dashboard
    /// (including COGS) during a single SwiftUI body evaluation.
    private var metrics: DashboardAggregatedMetrics { cachedMetrics }

    // MARK: - Comparison Baseline Cache

    private struct DashboardComparisonMetrics {
        var netRevenue: Double = 0
        var refunds: Double = 0
        var bills: Int = 0
        var discounts: Double = 0
        var items: Int = 0
        var profit: Double = 0
        var margin: Double = 0
        var orders: [Order] = []
        var hourlyRevenue: [Int: Double] = [:]
        var hourlyOrdersCount: [Int: Int] = [:]
        var hourlyItemsCount: [Int: Int] = [:]
    }

    private var comparisonScopeKey: String {
        "\(activeBranchId)|\(selectedPeriod.rawValue)|\(selectedComparison.rawValue)|\(selectedRegisterSessionId?.uuidString ?? "")|\(selectedChannel.rawValue)|\(selectedCashier)"
    }

    /// A compact, lightweight invalidation token.
    /// Uses prefix scanning on reverse-sorted collections to detect recent updates in O(1)
    /// without scanning tens of thousands of historical orders on the main thread.
    private struct MetricsRefreshKey: Hashable {
        let branchId: String
        let period: String
        let comparison: String
        let channel: String
        let cashier: String
        let registerSessionId: UUID?
        let clockTick: Date
        let recentOrderCount: Int
        let recentOrderUpdate: Date?
        let recentEventCount: Int
        let recentEventUpdate: Date?
        let tableCount: Int
        let timecardCount: Int
    }

    private var metricsRefreshKey: MetricsRefreshKey {
        MetricsRefreshKey(
            branchId: activeBranchId,
            period: selectedPeriod.rawValue,
            comparison: selectedComparison.rawValue,
            channel: selectedChannel.rawValue,
            cashier: selectedCashier,
            registerSessionId: selectedRegisterSessionId,
            clockTick: currentTime,
            recentOrderCount: allOrders.count,
            recentOrderUpdate: allOrders.prefix(80).lazy.map(\.updatedAt).max(),
            recentEventCount: financialEvents.count,
            recentEventUpdate: financialEvents.prefix(120).lazy.map(\.updatedAt).max(),
            tableCount: allTables.count,
            timecardCount: activeTimecards.count
        )
    }

    /// Coalesces notifications and updates the dashboard using dual-engine architecture:
    /// - Comparison baseline is computed once and cached (not re-calculated on every new bill).
    /// - Live/current period metrics are computed with maximum speed and minimum memory.
    @MainActor
    private func refreshMetricsDebounced() async {
        if hasLoadedMetrics {
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
        } else {
            await Task.yield()
        }

        isRefreshingMetrics = true
        let signpostId = OSSignpostID(log: dashboardPerformanceLog)
        os_signpost(
            .begin,
            log: dashboardPerformanceLog,
            name: "Dashboard Aggregation",
            signpostID: signpostId,
            "orders=%{public}d events=%{public}d transactions=%{public}d",
            allOrders.count,
            financialEvents.count,
            inventoryTransactions.count
        )

        // 1. Compute comparison baseline ONLY when scope changes or initial load
        let currentCompKey = comparisonScopeKey
        if lastComparisonScopeKey != currentCompKey || !hasLoadedComparisonMetrics {
            cachedComparisonMetrics = computeComparisonMetrics()
            lastComparisonScopeKey = currentCompKey
            hasLoadedComparisonMetrics = true
        }

        // 2. Compute live/current period metrics (Lightweight & Real-time)
        let snapshot = computeAggregatedMetrics(comparison: cachedComparisonMetrics)

        os_signpost(.end, log: dashboardPerformanceLog, name: "Dashboard Aggregation", signpostID: signpostId)
        guard !Task.isCancelled else {
            isRefreshingMetrics = false
            return
        }
        cachedMetrics = snapshot
        hasLoadedMetrics = true
        isRefreshingMetrics = false
    }

    private struct DashboardResolvedScope {
        let interval: DateInterval
        let sessionId: UUID?
        let businessDateKey: String?
    }

    /// Resolve the selected accounting boundary once per KPI calculation.
    private func accountingScope(comparison: Bool) -> DashboardResolvedScope {
        let interval = comparison ? comparisonDateInterval : selectedDateInterval
        if selectedPeriod.usesRegisterSession {
            let selected = selectedPeriod == .currentShift ? currentRegisterSession : selectedHistoricalSession
            let selectedStart = selected?.openedAt ?? .distantPast
            let session = comparison
                ? branchRegisterSessions.first(where: {
                    $0.closedAt != nil && $0.openedAt < selectedStart
                })
                : selected
            return DashboardResolvedScope(interval: interval, sessionId: session?.id, businessDateKey: nil)
        }
        if selectedPeriod == .businessDay {
            let key = BusinessDayContext.key(
                for: comparison ? interval.start : currentTime,
                cutoffHour: activeBranch?.businessDayCutoffHour ?? 4,
                timeZoneID: activeBranch?.timeZoneID ?? "Asia/Bangkok"
            )
            return DashboardResolvedScope(interval: interval, sessionId: nil, businessDateKey: key)
        }
        return DashboardResolvedScope(interval: interval, sessionId: nil, businessDateKey: nil)
    }

    private func isEventInResolvedScope(_ event: FinancialEvent, scope: DashboardResolvedScope) -> Bool {
        if selectedPeriod.usesRegisterSession {
            guard let sessionId = scope.sessionId else { return false }
            return RegisterShiftScope.contains(
                eventSessionId: event.registerSessionId, eventAt: event.occurredAt,
                sessionId: sessionId, openedAt: scope.interval.start, closedAt: scope.interval.end
            )
        }
        if selectedPeriod == .businessDay { return event.businessDateKey == scope.businessDateKey }
        return scope.interval.contains(event.occurredAt)
    }

    private func isPaymentInScope(_ payment: Payment, scope: DashboardResolvedScope) -> Bool {
        let interval = scope.interval
        if selectedPeriod.usesRegisterSession {
            guard let sessionId = scope.sessionId else { return false }
            return payment.registerSessionId == sessionId || (payment.registerSessionId == nil && interval.contains(payment.paidAt))
        }
        if selectedPeriod == .businessDay {
            guard let key = scope.businessDateKey else { return false }
            return payment.businessDateKey == key || (payment.businessDateKey.isEmpty && interval.contains(payment.paidAt))
        }
        return interval.contains(payment.paidAt)
    }

    /// Computes the comparison period metrics once and returns a lightweight snapshot.
    /// This is isolated from the live/current period calculation so historical data is not re-computed on every live tick.
    private func computeComparisonMetrics() -> DashboardComparisonMetrics {
        var comp = DashboardComparisonMetrics()
        guard let branchId = activeBranchUUID else { return comp }

        let comparisonScope = accountingScope(comparison: true)
        let activeOrders = branchOrders
        let allowedOrderIds = Set(activeOrders.filter(matchesGlobalFilters).map(\.id))

        var comparisonEvents: [FinancialEvent] = []
        for event in financialEvents {
            guard !event.isDeleted, event.status == "posted", event.branchId == branchId,
                  AccountingMath.recognizedAmount(eventType: event.eventType, amount: event.amount) != nil,
                  let orderId = event.orderId, allowedOrderIds.contains(orderId) else { continue }

            if isEventInResolvedScope(event, scope: comparisonScope) {
                comparisonEvents.append(event)
            }
        }

        let comparisonAccountingSummary = AccountingMath.summarize(comparisonEvents.map {
            AccountingFact(eventType: $0.eventType, amount: $0.amount, paymentMethod: $0.paymentMethod,
                           orderId: $0.orderId, isLateAdjustment: $0.isLateAdjustment)
        })

        comp.netRevenue = comparisonAccountingSummary.netSales
        comp.refunds = comparisonAccountingSummary.refunds

        let comparisonRecognizedOrderIds = Set(comparisonEvents.compactMap {
            ($0.eventType == "sale_capture" || $0.eventType == "government_subsidy") ? $0.orderId : nil
        })

        let compOrders = activeOrders.filter { comparisonRecognizedOrderIds.contains($0.id) && matchesGlobalFilters($0) }
        comp.orders = compOrders
        comp.bills = compOrders.count
        comp.discounts = compOrders.reduce(0.0) { $0 + $1.discount }
        comp.items = compOrders.flatMap(\.items).filter(isMainSaleItem).reduce(0) { $0 + $1.quantity }

        if canViewProfitAndCosts {
            var compCaptured: [UUID: Double] = [:]
            for event in comparisonEvents {
                guard let orderId = event.orderId,
                      let amount = AccountingMath.recognizedAmount(eventType: event.eventType, amount: event.amount),
                      event.eventType != "refund" else { continue }
                compCaptured[orderId, default: 0] += amount
            }
            let prevCOGS = estimatedCOGS(for: compOrders, in: comparisonDateInterval, capturedByOrder: compCaptured)
            comp.profit = comp.netRevenue - prevCOGS
            comp.margin = comp.netRevenue > 0 ? comp.profit / comp.netRevenue * 100 : 0
        }

        var yesterdayHours: [Int: Double] = [:]
        var yesterdayOrdersCount: [Int: Int] = [:]
        var yesterdayItemsCount: [Int: Int] = [:]
        for h in 0...23 {
            yesterdayHours[h] = 0
            yesterdayOrdersCount[h] = 0
            yesterdayItemsCount[h] = 0
        }
        let calendar = Calendar.current
        for event in comparisonEvents {
            let hour = calendar.component(.hour, from: event.occurredAt)
            yesterdayHours[hour, default: 0] += AccountingMath.recognizedAmount(eventType: event.eventType, amount: event.amount) ?? 0
        }
        for order in compOrders {
            let hour = calendar.component(.hour, from: order.createdAt)
            yesterdayOrdersCount[hour, default: 0] += 1
            yesterdayItemsCount[hour, default: 0] += order.items.filter(isMainSaleItem).reduce(0) { $0 + $1.quantity }
        }
        comp.hourlyRevenue = yesterdayHours
        comp.hourlyOrdersCount = yesterdayOrdersCount
        comp.hourlyItemsCount = yesterdayItemsCount

        return comp
    }

    /// Single-pass aggregator computes live/current dashboard statistics in O(N_today).
    /// Uses pre-computed comparison metrics from cache to avoid expensive historical recalculations.
    private func computeAggregatedMetrics(comparison: DashboardComparisonMetrics) -> DashboardAggregatedMetrics {
        var m = DashboardAggregatedMetrics()
        guard let branchId = activeBranchUUID else { return m }

        let currentScope = accountingScope(comparison: false)
        let activeOrders = branchOrders
        let currentPeriodOrders = activeOrders.filter {
            selectedDateInterval.contains($0.createdAt) && !$0.isDeleted && matchesGlobalFilters($0)
        }
        m.todayOrders = currentPeriodOrders

        let allowedOrderIds = Set(activeOrders.filter(matchesGlobalFilters).map(\.id))

        var currentEvents: [FinancialEvent] = []

        for event in financialEvents {
            guard !event.isDeleted, event.status == "posted", event.branchId == branchId,
                  AccountingMath.recognizedAmount(eventType: event.eventType, amount: event.amount) != nil,
                  let orderId = event.orderId, allowedOrderIds.contains(orderId) else { continue }

            if isEventInResolvedScope(event, scope: currentScope) {
                currentEvents.append(event)
            }
        }

        let currentAccountingSummary = AccountingMath.summarize(currentEvents.map {
            AccountingFact(eventType: $0.eventType, amount: $0.amount, paymentMethod: $0.paymentMethod,
                           orderId: $0.orderId, isLateAdjustment: $0.isLateAdjustment)
        })

        m.todayRevenue = currentAccountingSummary.netSales
        m.todayRefunds = currentAccountingSummary.refunds
        // Channel totals use the same scoped events as the storewide net total,
        // including refunds of earlier orders and excluding later-shift refunds.
        let orderTypeByID = Dictionary(uniqueKeysWithValues: activeOrders.map { ($0.id, $0.orderType) })
        for event in currentEvents {
            guard let amount = AccountingMath.recognizedAmount(eventType: event.eventType, amount: event.amount),
                  let orderId = event.orderId else { continue }
            switch orderTypeByID[orderId] {
            case "delivery":
                m.deliverySalesTotal += amount
            case "take_out":
                m.takeOutSalesTotal += amount
                m.storefrontSalesTotal += amount
            default:
                m.dineInSalesTotal += amount
                m.storefrontSalesTotal += amount
            }
        }

        // Plug in pre-computed comparison baseline
        m.yesterdayRevenue = comparison.netRevenue
        m.previousRefunds = comparison.refunds
        m.comparisonOrders = comparison.orders
        m.previousBills = comparison.bills
        m.previousDiscounts = comparison.discounts
        m.previousItems = comparison.items
        m.previousProfit = comparison.profit
        m.previousMargin = comparison.margin

        let currentRecognizedOrderIds = Set(currentEvents.compactMap {
            ($0.eventType == "sale_capture" || $0.eventType == "government_subsidy") ? $0.orderId : nil
        })

        let completedOrders = activeOrders.filter { currentRecognizedOrderIds.contains($0.id) && matchesGlobalFilters($0) }

        m.completedTodayOrders = completedOrders
        m.completedOrdersCount = completedOrders.count

        var capturedByOrder: [UUID: Double] = [:]
        for event in currentEvents {
            guard let orderId = event.orderId,
                  let amount = AccountingMath.recognizedAmount(eventType: event.eventType, amount: event.amount),
                  event.eventType != "refund" else { continue }
            capturedByOrder[orderId, default: 0] += amount
        }

        var storefrontItemMap: [String: (name: String, category: String, qty: Int, rev: Double)] = [:]
        var deliveryItemMap: [String: (name: String, category: String, qty: Int, rev: Double)] = [:]
        var paymentMap: [String: (amount: Double, count: Int)] = [:]
        var addOnItemsMap: [String: (qty: Int, rev: Double)] = [:]
        var storefrontAddOnItemsMap: [String: (qty: Int, rev: Double)] = [:]
        var deliveryAddOnItemsMap: [String: (qty: Int, rev: Double)] = [:]
        var transferMap: [String: (amount: Double, count: Int)] = [:]
        var deliveryPlatformOrders: [String: [Order]] = [:]
        var channelGroups: [DashboardChannelSummary.Kind: [Order]] = [:]

        for order in completedOrders {
            let capturedAmount = capturedByOrder[order.id, default: 0]
            let fraction = AccountingMath.capturedFraction(ticketTotal: order.total, recognizedBeforeRefunds: capturedAmount)

            let componentGross = order.subtotal + order.serviceCharge + order.tax
            let ticketGross = order.total + order.discount
            let gross = abs(componentGross - ticketGross) <= 0.05 ? componentGross : ticketGross
            m.todayGrossSales += gross * fraction
            m.todayDiscounts += order.discount * fraction
            m.todayVATCollected += order.tax
            m.todayServiceCharge += order.serviceCharge
            m.totalGuests += order.guestCount

            if order.orderType == "delivery" {
                m.deliveryGrossSales += gross * fraction
                m.deliveryDiscounts += order.discount * fraction
                m.deliveryOrdersCount += 1
                m.completedDeliveryOrders.append(order)

                let brand = order.deliveryBrand?.trimmingCharacters(in: .whitespacesAndNewlines)
                let brandKey = (brand?.isEmpty == false) ? brand! : "Other"
                deliveryPlatformOrders[brandKey, default: []].append(order)
            } else {
                m.storefrontGrossSales += gross * fraction
                m.storefrontDiscounts += order.discount * fraction
                m.storefrontOrdersCount += 1
                m.completedStorefrontOrders.append(order)
            }

            // Channel summaries grouping
            let channelKind: DashboardChannelSummary.Kind
            if order.orderType == "delivery",
               order.deliveryBrand?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                channelKind = .marketplace
            } else if order.orderType == "delivery" {
                channelKind = .delivery
            } else if order.orderSource == "web" {
                channelKind = .online
            } else if order.isQuickServiceOrder {
                channelKind = .quickService
            } else {
                channelKind = .storefront
            }
            channelGroups[channelKind, default: []].append(order)

            // Payment Mix & Tenders
            if order.usesGovernmentSupport {
                let key = thaiChuaThaiPlusEnabled
                    ? (order.supportProgramName ?? GovernmentSupportProgram.thaiChuaThaiPlus)
                    : (lm.currentLanguage == .thai ? "วิธีชำระอื่น" : "Other payment")
                let existing = paymentMap[key] ?? (0, 0)
                paymentMap[key] = (existing.amount + order.total, existing.count + 1)
            } else {
                for payment in order.payments where !payment.isDeleted && payment.isCaptured && isPaymentInScope(payment, scope: currentScope) {
                    let key = payment.paymentMethod.lowercased().replacingOccurrences(of: " ", with: "_")
                    let existing = paymentMap[key] ?? (0, 0)
                    paymentMap[key] = (existing.amount + payment.amount, existing.count + 1)

                    if key == "cash" {
                        m.cashTenderTotal += payment.amount
                    } else if ["qr", "qr_promptpay", "promptpay", "transfer", "bank_transfer"].contains(key) {
                        m.transferTenderTotal += payment.amount
                        let subKey = (key.contains("qr") || key.contains("promptpay")) ? "promptpay" : "bank_transfer"
                        let curr = transferMap[subKey] ?? (0, 0)
                        transferMap[subKey] = (curr.amount + payment.amount, curr.count + 1)
                    } else if ["true_money", "truemoney", "rabbit_linepay", "e_wallet", "wallet"].contains(key) {
                        let curr = transferMap["e_wallet"] ?? (0, 0)
                        transferMap["e_wallet"] = (curr.amount + payment.amount, curr.count + 1)
                    }
                }
            }

            if order.usesGovernmentSupport && thaiChuaThaiPlusEnabled {
                m.todaySupportCitizenContribution += order.supportCitizenAmount
                m.todaySupportGovernmentContribution += order.supportGovernmentAmount
                if order.supportSettlementStatus == "pending" {
                    m.pendingSupportSettlementOrders.append(order)
                }
            }

            // Restaurant line mix. Modifiers and generated child lines are
            // intentionally excluded from the main-dish KPI.
            let isDeliveryOrder = order.orderType == "delivery"
            for item in order.items where !item.isDeleted && item.status != "cancelled" {
                switch item.resolvedLineType {
                case .main:
                    m.itemsSold += item.quantity
                    let activeMods = item.modifiers.filter { !$0.isDeleted }
                    let modsCount = activeMods.count * item.quantity
                    let modsRev = activeMods.reduce(0.0) { $0 + ($1.price * Double(item.quantity)) }
                    m.addOnsSold += modsCount
                    m.addOnsRevenue += modsRev
                    if isDeliveryOrder {
                        m.deliveryAddOnsSold += modsCount
                        m.deliveryAddOnsRevenue += modsRev
                    } else {
                        m.storefrontAddOnsSold += modsCount
                        m.storefrontAddOnsRevenue += modsRev
                    }
                    for mod in activeMods {
                        let modName = mod.modifier?.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        let name = (modName?.isEmpty == false) ? modName! : (lm.currentLanguage == .thai ? "ตัวเลือกเสริม" : "Add-on")
                        let rev = mod.price * Double(item.quantity)
                        
                        let currentAll = addOnItemsMap[name] ?? (qty: 0, rev: 0.0)
                        addOnItemsMap[name] = (qty: currentAll.qty + item.quantity, rev: currentAll.rev + rev)
                        
                        if isDeliveryOrder {
                            let current = deliveryAddOnItemsMap[name] ?? (qty: 0, rev: 0.0)
                            deliveryAddOnItemsMap[name] = (qty: current.qty + item.quantity, rev: current.rev + rev)
                        } else {
                            let current = storefrontAddOnItemsMap[name] ?? (qty: 0, rev: 0.0)
                            storefrontAddOnItemsMap[name] = (qty: current.qty + item.quantity, rev: current.rev + rev)
                        }
                    }
                case .addOn:
                    m.addOnsSold += item.quantity
                    m.addOnsRevenue += item.subtotal
                    if isDeliveryOrder {
                        m.deliveryAddOnsSold += item.quantity
                        m.deliveryAddOnsRevenue += item.subtotal
                    } else {
                        m.storefrontAddOnsSold += item.quantity
                        m.storefrontAddOnsRevenue += item.subtotal
                    }
                    let itemName = item.itemName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let name = !itemName.isEmpty ? itemName : (lm.currentLanguage == .thai ? "สินค้าเสริม" : "Add-on item")
                    
                    let currentAll = addOnItemsMap[name] ?? (qty: 0, rev: 0.0)
                    addOnItemsMap[name] = (qty: currentAll.qty + item.quantity, rev: currentAll.rev + item.subtotal)
                    
                    if isDeliveryOrder {
                        let current = deliveryAddOnItemsMap[name] ?? (qty: 0, rev: 0.0)
                        deliveryAddOnItemsMap[name] = (qty: current.qty + item.quantity, rev: current.rev + item.subtotal)
                    } else {
                        let current = storefrontAddOnItemsMap[name] ?? (qty: 0, rev: 0.0)
                        storefrontAddOnItemsMap[name] = (qty: current.qty + item.quantity, rev: current.rev + item.subtotal)
                    }
                case .bundleComponent:
                    m.bundleComponentsSold += item.quantity
                    m.bundleComponentsRevenue += item.subtotal
                case .promotionReward:
                    m.promotionRewardsSold += item.quantity
                    m.promotionRewardsValue += item.subtotal > 0 ? item.subtotal : (item.unitPrice * Double(item.quantity))
                }

                guard item.resolvedLineType == .main else { continue }
                let name = item.itemName.isEmpty ? "Unknown" : item.itemName
                let key = item.menuItem?.id ?? "snapshot:\(name.lowercased())"
                // Storefront and delivery prices can differ. Keep them in
                // separate aggregates so quantities, revenue, and average
                // selling price never imply one shared catalog price.
                if order.orderType == "delivery" {
                    let existing = deliveryItemMap[key] ?? (name: name, category: inferredCategoryName(for: item), qty: 0, rev: 0)
                    deliveryItemMap[key] = (name: existing.name, category: existing.category, qty: existing.qty + item.quantity, rev: existing.rev + item.subtotal)
                } else {
                    let existing = storefrontItemMap[key] ?? (name: name, category: inferredCategoryName(for: item), qty: 0, rev: 0)
                    storefrontItemMap[key] = (name: existing.name, category: existing.category, qty: existing.qty + item.quantity, rev: existing.rev + item.subtotal)
                }
            }
        }

        m.addOnBreakdown = addOnItemsMap
            .map { DashboardAddOnDetail(name: $0.key, quantity: $0.value.qty, revenue: $0.value.rev) }
            .sorted {
                if $0.quantity != $1.quantity {
                    return $0.quantity > $1.quantity
                }
                return $0.revenue > $1.revenue
            }

        m.storefrontAddOnBreakdown = storefrontAddOnItemsMap
            .map { DashboardAddOnDetail(name: $0.key, quantity: $0.value.qty, revenue: $0.value.rev) }
            .sorted {
                if $0.quantity != $1.quantity {
                    return $0.quantity > $1.quantity
                }
                return $0.revenue > $1.revenue
            }

        m.deliveryAddOnBreakdown = deliveryAddOnItemsMap
            .map { DashboardAddOnDetail(name: $0.key, quantity: $0.value.qty, revenue: $0.value.rev) }
            .sorted {
                if $0.quantity != $1.quantity {
                    return $0.quantity > $1.quantity
                }
                return $0.revenue > $1.revenue
            }

        if transferMap.isEmpty && m.transferTenderTotal > 0 {
            m.transferBreakdown = [
                DashboardTransferDetail(
                    methodKey: "promptpay",
                    displayName: lm.currentLanguage == .thai ? "PromptPay (สแกน QR)" : "PromptPay / QR",
                    amount: m.transferTenderTotal,
                    count: completedOrders.filter { $0.payments.contains { ["qr", "qr_promptpay", "promptpay", "transfer", "bank_transfer"].contains($0.paymentMethod.lowercased().replacingOccurrences(of: " ", with: "_")) } }.count
                )
            ]
        } else {
            m.transferBreakdown = transferMap.map { subKey, val in
                let displayName: String
                switch subKey {
                case "promptpay":
                    displayName = lm.currentLanguage == .thai ? "PromptPay (สแกน QR)" : "PromptPay / QR"
                case "bank_transfer":
                    displayName = lm.currentLanguage == .thai ? "โอนเงินผ่านธนาคาร" : "Bank Transfer"
                case "e_wallet":
                    displayName = "E-Wallet / TrueMoney"
                default:
                    displayName = paymentMethodDisplayName(subKey)
                }
                return DashboardTransferDetail(methodKey: subKey, displayName: displayName, amount: val.amount, count: val.count)
            }.sorted { $0.amount > $1.amount }
        }

        if m.completedOrdersCount > 0 {
            m.avgOrderValue = m.todayRevenue / Double(m.completedOrdersCount)
        }

        m.todayPaymentMix = paymentMap
            .map { (method: paymentMethodDisplayName($0.key), amount: $0.value.amount, count: $0.value.count) }
            .sorted { $0.amount > $1.amount }
        m.todaySettlementMix = m.todayPaymentMix

        m.todaySettledAmount = m.todaySettlementMix.reduce(0.0) { $0 + $1.amount } - m.todayRefunds
        m.todaySettlementVariance = m.todayRevenue - m.todaySettledAmount

        m.todayDeliveryPlatforms = deliveryPlatformOrders.map { brand, platformOrders in
            let gross = platformOrders.reduce(0.0) { $0 + $1.total }
            let gp = platformOrders.reduce(0.0) { $0 + $1.deliveryGPFeeAmount }
            let ads = platformOrders.reduce(0.0) { $0 + $1.deliveryAdFeeAmount }
            let other = platformOrders.reduce(0.0) { $0 + max($1.deliveryOtherFee, 0) }
            return DashboardDeliveryPlatform(brand: brand, orders: platformOrders.sorted { $0.createdAt > $1.createdAt }, gross: gross, gpFees: gp, adFees: ads, otherFees: other, net: gross - gp - ads - other)
        }.sorted { $0.gross > $1.gross }

        m.todayDeliveryPlatformFees = m.todayDeliveryPlatforms.reduce(0.0) { $0 + $1.totalFees }
        m.estimatedNetProceeds = m.todaySettledAmount - m.todayDeliveryPlatformFees

        m.salesChannelSummaries = DashboardChannelSummary.Kind.allCases.compactMap { kind in
            guard let orders = channelGroups[kind], !orders.isEmpty else { return nil }
            let gross = orders.reduce(0.0) { $0 + $1.total }
            let fees = orders.reduce(0.0) { $0 + $1.deliveryPlatformCost }
            var mainItems = 0
            var addOnItems = 0
            var addOnSales = 0.0
            for order in orders {
                for item in order.items where !item.isDeleted && item.status != "cancelled" {
                    switch item.resolvedLineType {
                    case .main:
                        mainItems += item.quantity
                        let activeModifiers = item.modifiers.filter { !$0.isDeleted }
                        addOnItems += activeModifiers.count * item.quantity
                        addOnSales += activeModifiers.reduce(0.0) { $0 + $1.price * Double(item.quantity) }
                    case .addOn:
                        addOnItems += item.quantity
                        addOnSales += item.subtotal
                    case .bundleComponent, .promotionReward:
                        break
                    }
                }
            }
            return DashboardChannelSummary(
                kind: kind,
                orders: orders.count,
                mainItems: mainItems,
                addOnItems: addOnItems,
                addOnSales: addOnSales,
                gross: gross,
                fees: fees
            )
        }

        m.topStorefrontItems = storefrontItemMap
            .map { (name: $0.value.name, category: $0.value.category, quantity: $0.value.qty, revenue: $0.value.rev) }
            .sorted { $0.quantity > $1.quantity }
            .prefix(8)
            .map { $0 }
        m.topDeliveryItems = deliveryItemMap
            .map { (name: $0.value.name, category: $0.value.category, quantity: $0.value.qty, revenue: $0.value.rev) }
            .sorted { $0.quantity > $1.quantity }
            .prefix(8)
            .map { $0 }

        // COGS calculation
        if canViewProfitAndCosts {
            let cogsSignpostId = OSSignpostID(log: dashboardPerformanceLog)
            os_signpost(
                .begin,
                log: dashboardPerformanceLog,
                name: "Dashboard COGS",
                signpostID: cogsSignpostId,
                "currentOrders=%{public}d",
                completedOrders.count
            )
            let todayCOGS = estimatedCOGS(for: completedOrders, in: selectedDateInterval, capturedByOrder: capturedByOrder)
            m.todayCOGS = todayCOGS
            m.grossProfit = m.todayRevenue - todayCOGS
            m.grossMargin = m.todayRevenue > 0 ? m.grossProfit / m.todayRevenue * 100 : 0
            os_signpost(.end, log: dashboardPerformanceLog, name: "Dashboard COGS", signpostID: cogsSignpostId)
        }

        // Charts
        let todayLabel = selectedPeriod.title(isThai: lm.currentLanguage == .thai)
        let yesterdayLabel = selectedComparison.title(isThai: lm.currentLanguage == .thai)
        var todayHours: [Int: Double] = [:]
        var todayOrdersCount: [Int: Int] = [:]
        var todayItemsCount: [Int: Int] = [:]
        for h in 0...23 {
            todayHours[h] = 0
            todayOrdersCount[h] = 0
            todayItemsCount[h] = 0
        }
        let calendar = Calendar.current
        for event in currentEvents {
            let hour = calendar.component(.hour, from: event.occurredAt)
            todayHours[hour, default: 0] += AccountingMath.recognizedAmount(eventType: event.eventType, amount: event.amount) ?? 0
        }
        for order in completedOrders {
            let hour = calendar.component(.hour, from: order.createdAt)
            todayOrdersCount[hour, default: 0] += 1
            todayItemsCount[hour, default: 0] += order.items.filter(isMainSaleItem).reduce(0) { $0 + $1.quantity }
        }
        var salesPoints: [DashboardHourlySalesPoint] = []
        for h in 0...23 {
            salesPoints.append(DashboardHourlySalesPoint(
                hour: h,
                revenue: comparison.hourlyRevenue[h] ?? 0.0,
                ordersCount: comparison.hourlyOrdersCount[h] ?? 0,
                itemsCount: comparison.hourlyItemsCount[h] ?? 0,
                period: yesterdayLabel
            ))
            salesPoints.append(DashboardHourlySalesPoint(
                hour: h,
                revenue: todayHours[h] ?? 0.0,
                ordersCount: todayOrdersCount[h] ?? 0,
                itemsCount: todayItemsCount[h] ?? 0,
                period: todayLabel
            ))
        }
        m.chartSalesData = salesPoints

        // Category breakdown
        let mainsLabel = "dashboard_main_dishes".t
        let appetizersLabel = "dashboard_appetizers".t
        let drinksLabel = "dashboard_beverages".t
        let dessertsLabel = "dashboard_desserts".t
        let specialsLabel = "dashboard_specials".t
        var categoryMap: [String: Double] = [:]

        var netByOrder: [UUID: Double] = [:]
        for event in currentEvents {
            guard let orderId = event.orderId,
                  let amount = AccountingMath.recognizedAmount(eventType: event.eventType, amount: event.amount) else { continue }
            netByOrder[orderId, default: 0] += amount
        }

        for order in activeOrders where netByOrder[order.id] != nil && matchesGlobalFilters(order) {
            let eligibleItems = order.items.filter(isMainSaleItem)
            let allocations = AccountingMath.allocate(netByOrder[order.id, default: 0], weights: eligibleItems.map(\.subtotal))
            for (item, allocatedRevenue) in zip(eligibleItems, allocations) {
                let rawCategory = inferredCategoryName(for: item)
                let mappedCategory: String
                let slug = rawCategory.lowercased()

                if slug.contains("main") { mappedCategory = mainsLabel }
                else if slug.contains("appetizer") { mappedCategory = appetizersLabel }
                else if slug.contains("drink") || slug.contains("beverage") { mappedCategory = drinksLabel }
                else if slug.contains("dessert") { mappedCategory = dessertsLabel }
                else if !rawCategory.isEmpty { mappedCategory = rawCategory }
                else { mappedCategory = specialsLabel }

                categoryMap[mappedCategory] = (categoryMap[mappedCategory] ?? 0.0) + allocatedRevenue
            }
        }
        m.chartCategoryData = categoryMap.map { DashboardCategorySalesPoint(categoryName: $0.key, revenue: $0.value) }
            .sorted { $0.revenue > $1.revenue }

        // Exceptions
        var issues: [DashboardException] = []
        let unsettled = currentPeriodOrders.filter { !$0.isDeleted && $0.status != "cancelled" && $0.outstandingAmount > 0.005 }
        if !unsettled.isEmpty {
            issues.append(.init(kind: .critical, titleTH: "ออเดอร์ยังชำระไม่ครบ", titleEN: "Unsettled orders", detailTH: "ออเดอร์เปิดหรือชำระบางส่วน", detailEN: "Open or partially paid orders", count: unsettled.count, amount: unsettled.reduce(0) { $0 + $1.outstandingAmount }, orders: unsettled))
        }
        let failed = currentPeriodOrders.filter { order in order.payments.contains { !$0.isDeleted && $0.status == "failed" } }
        if !failed.isEmpty {
            issues.append(.init(kind: .critical, titleTH: "การชำระเงินไม่สำเร็จ", titleEN: "Failed payments", detailTH: "ต้องตรวจสอบก่อนปิดกะ", detailEN: "Review before shift close", count: failed.count, amount: failed.flatMap(\.payments).filter { $0.status == "failed" }.reduce(0) { $0 + $1.amount }, orders: failed))
        }
        let missingBrand = completedOrders.filter { $0.orderType == "delivery" && ($0.deliveryBrand?.isEmpty != false) }
        if !missingBrand.isEmpty {
            issues.append(.init(kind: .warning, titleTH: "เดลิเวอรีไม่ระบุแพลตฟอร์ม", titleEN: "Delivery channel missing", detailTH: "ยอดถูกจัดไว้ใน Other", detailEN: "Sales grouped under Other", count: missingBrand.count, amount: missingBrand.reduce(0) { $0 + $1.recognizedNetTotal }, orders: missingBrand))
        }
        let missingPlatformID = completedOrders.filter { $0.orderType == "delivery" && ($0.platformOrderNumber?.isEmpty != false) }
        if !missingPlatformID.isEmpty {
            issues.append(.init(kind: .warning, titleTH: "ไม่มีเลขออเดอร์แพลตฟอร์ม", titleEN: "Platform order ID missing", detailTH: "อาจกระทบการกระทบยอด", detailEN: "May block reconciliation", count: missingPlatformID.count, amount: missingPlatformID.reduce(0) { $0 + $1.recognizedNetTotal }, orders: missingPlatformID))
        }
        if abs(m.todaySettlementVariance) > 0.005 {
            issues.append(.init(kind: .critical, titleTH: "ยอดขายกับยอดชำระไม่ตรง", titleEN: "Sales/payment variance", detailTH: "ตรวจสอบ payment และ refund", detailEN: "Review payments and refunds", count: completedOrders.count, amount: abs(m.todaySettlementVariance), orders: completedOrders))
        }

        let voidedOrders = currentPeriodOrders.filter { $0.status == "cancelled" }
        m.todayVoidedOrdersCount = voidedOrders.count
        m.todayVoidedAmount = voidedOrders.reduce(0) { $0 + $1.recognizedNetTotal }

        m.dashboardExceptions = issues

        return m
    }

    /// WWDC22/10136 pattern: keep mark identity stable and animate the state
    /// that drives mark values. Swift Charts interpolates the marks for us.
    private func restartChartAnimation() {
        if !allowsDecorativeDashboardMotion {
            chartAnimationProgress = 1
            return
        }
        chartAnimationProgress = 0
        Task { @MainActor in
            await Task.yield()
            withAnimation(.easeInOut(duration: 0.8)) {
                chartAnimationProgress = 1
            }
        }
    }

    // Forwarding accessors for compatibility
    private var todayOrders: [Order] { metrics.todayOrders }
    private var completedTodayOrders: [Order] { metrics.completedTodayOrders }
    private var completedStorefrontOrders: [Order] { metrics.completedStorefrontOrders }
    private var completedDeliveryOrders: [Order] { metrics.completedDeliveryOrders }
    private var comparisonOrders: [Order] { metrics.comparisonOrders }
    private var todayRevenue: Double { metrics.todayRevenue }
    private var yesterdayRevenue: Double { metrics.yesterdayRevenue }
    private var todayGrossSales: Double { metrics.todayGrossSales }
    private var todayDiscounts: Double { metrics.todayDiscounts }
    private var todayRefunds: Double { metrics.todayRefunds }
    private var todayVATCollected: Double { metrics.todayVATCollected }
    private var todayServiceCharge: Double { metrics.todayServiceCharge }
    private var itemsSold: Int { metrics.itemsSold }
    private var addOnsSold: Int { metrics.addOnsSold }
    private var addOnsRevenue: Double { metrics.addOnsRevenue }
    private var storefrontAddOnsSold: Int { metrics.storefrontAddOnsSold }
    private var storefrontAddOnsRevenue: Double { metrics.storefrontAddOnsRevenue }
    private var deliveryAddOnsSold: Int { metrics.deliveryAddOnsSold }
    private var deliveryAddOnsRevenue: Double { metrics.deliveryAddOnsRevenue }
    private var bundleComponentsSold: Int { metrics.bundleComponentsSold }
    private var bundleComponentsRevenue: Double { metrics.bundleComponentsRevenue }
    private var promotionRewardsSold: Int { metrics.promotionRewardsSold }
    private var promotionRewardsValue: Double { metrics.promotionRewardsValue }
    private var totalGuests: Int { metrics.totalGuests }
    private var avgOrderValue: Double { metrics.avgOrderValue }
    private var grossProfit: Double { metrics.grossProfit }
    private var todayCOGS: Double { metrics.todayCOGS }
    private var grossMargin: Double { metrics.grossMargin }
    private var storefrontSalesTotal: Double { metrics.storefrontSalesTotal }
    private var dineInSalesTotal: Double { metrics.dineInSalesTotal }
    private var takeOutSalesTotal: Double { metrics.takeOutSalesTotal }
    private var storefrontGrossSales: Double { metrics.storefrontGrossSales }
    private var storefrontDiscounts: Double { metrics.storefrontDiscounts }
    private var deliverySalesTotal: Double { metrics.deliverySalesTotal }
    private var deliveryGrossSales: Double { metrics.deliveryGrossSales }
    private var deliveryDiscounts: Double { metrics.deliveryDiscounts }
    private var cashTenderTotal: Double { metrics.cashTenderTotal }
    private var transferTenderTotal: Double { metrics.transferTenderTotal }
    private var todayPaymentMix: [(method: String, amount: Double, count: Int)] { metrics.todayPaymentMix }
    private var todaySettlementMix: [(method: String, amount: Double, count: Int)] { metrics.todaySettlementMix }
    private var todayDeliveryPlatforms: [DashboardDeliveryPlatform] { metrics.todayDeliveryPlatforms }
    private var salesChannelSummaries: [DashboardChannelSummary] { metrics.salesChannelSummaries }
    private var topStorefrontItems: [(name: String, category: String, quantity: Int, revenue: Double)] { metrics.topStorefrontItems }
    private var topDeliveryItems: [(name: String, category: String, quantity: Int, revenue: Double)] { metrics.topDeliveryItems }
    private var chartSalesData: [DashboardHourlySalesPoint] { metrics.chartSalesData }
    private var chartCategoryData: [DashboardCategorySalesPoint] { metrics.chartCategoryData }
    private var dashboardExceptions: [DashboardException] { metrics.dashboardExceptions }
    private var addOnBreakdown: [DashboardAddOnDetail] { metrics.addOnBreakdown }
    private var storefrontAddOnBreakdown: [DashboardAddOnDetail] { metrics.storefrontAddOnBreakdown }
    private var deliveryAddOnBreakdown: [DashboardAddOnDetail] { metrics.deliveryAddOnBreakdown }
    private var transferBreakdown: [DashboardTransferDetail] { metrics.transferBreakdown }
    private var netDeliveryExpected: Double { max(deliverySalesTotal - todayDeliveryPlatformFees, 0) }
    private var netCombinedProceeds: Double { storefrontSalesTotal + netDeliveryExpected }
    private var isSelectedLedgerComplete: Bool { metrics.isSelectedLedgerComplete }
    private var todaySettledAmount: Double { metrics.todaySettledAmount }
    private var todaySettlementVariance: Double { metrics.todaySettlementVariance }
    private var todayDeliveryPlatformFees: Double { metrics.todayDeliveryPlatformFees }
    private var estimatedNetProceeds: Double { metrics.estimatedNetProceeds }
    private var todaySupportCitizenContribution: Double { metrics.todaySupportCitizenContribution }
    private var todaySupportGovernmentContribution: Double { metrics.todaySupportGovernmentContribution }
    private var pendingSupportSettlementOrders: [Order] { metrics.pendingSupportSettlementOrders }

    private var selectedPeriodRefunds: [RefundTransaction] {
        completedTodayOrders.flatMap(\.refunds).filter { !$0.isDeleted && $0.status == "completed" }
    }
    private var comparisonPeriodRefunds: [RefundTransaction] {
        comparisonOrders.flatMap(\.refunds).filter { !$0.isDeleted && $0.status == "completed" }
    }

    private var revenueTrend: String? {
        guard yesterdayRevenue > 0 else { return nil }
        let change = ((todayRevenue - yesterdayRevenue) / yesterdayRevenue) * 100
        let sign = change >= 0 ? "+" : ""
        return "\(sign)\(Int(change))%"
    }

    private var activeOrders: [Order] {
        todayOrders.filter { $0.status == "preparing" || $0.status == "ready" }
    }

    private var tableOccupancy: Int {
        let activeTables = branchTables.filter { !$0.isDeleted }
        guard !activeTables.isEmpty else { return 0 }
        let occupied = activeTables.filter { $0.status == "occupied" }.count
        return Int((Double(occupied) / Double(activeTables.count)) * 100)
    }

    private var avgPrepTime: Int {
        let completedItems = todayOrders.flatMap { $0.items }
            .filter { $0.status == "served" || $0.status == "ready" }
        guard !completedItems.isEmpty else { return 0 }
        let totalMinutes = completedItems.reduce(0.0) { total, item in
            if let order = item.order {
                let diff = item.updatedAt.timeIntervalSince(order.createdAt) / 60
                return total + max(0, min(diff, 60))
            }
            return total
        }
        return Int(totalMinutes / Double(completedItems.count))
    }

    private var yesterdayAvgPrepTime: Int {
        let completedItems = comparisonOrders.flatMap { $0.items }
            .filter { $0.status == "served" || $0.status == "ready" }
        guard !completedItems.isEmpty else { return 0 }
        let totalMinutes = completedItems.reduce(0.0) { total, item in
            if let order = item.order {
                let diff = item.updatedAt.timeIntervalSince(order.createdAt) / 60
                return total + max(0, min(diff, 60))
            }
            return total
        }
        return Int(totalMinutes / Double(completedItems.count))
    }

    private var prepTimeTrend: String? {
        let todayAvg = avgPrepTime
        let yesterdayAvg = yesterdayAvgPrepTime
        guard todayAvg > 0, yesterdayAvg > 0 else { return nil }
        let diff = todayAvg - yesterdayAvg
        if diff < 0 {
            return "\(diff) min"
        } else if diff > 0 {
            return "+\(diff) min"
        }
        return "0 min"
    }

    private func isMainSaleItem(_ item: OrderItem) -> Bool {
        !item.isDeleted && item.status != "cancelled" && item.resolvedLineType == .main
    }

    private var canViewProfitAndCosts: Bool {
        sessionManager.can(.profitAnalyticsView) && sessionManager.can(.productCostsView)
    }

    private func estimatedCOGS(for orders: [Order], in interval: DateInterval, capturedByOrder: [UUID: Double]) -> Double {
        guard canViewProfitAndCosts else { return 0 }
        let itemReferences = Set(orders.flatMap(\.items).flatMap { item in
            [item.id] + item.modifiers.filter { !$0.isDeleted }.map(\.id)
        })
        let ledgerCostByReference = Dictionary(grouping: inventoryTransactions.filter {
            !$0.isDeleted && $0.movementType == .sell && $0.referenceId.map(itemReferences.contains) == true
        }, by: { $0.referenceId! }).mapValues { rows in
            rows.reduce(0.0) { $0 + $1.magnitude * ($1.costPrice ?? $1.item?.costPrice ?? 0) }
        }

        let soldCost = orders.flatMap(\.items)
            .filter { !$0.isDeleted && $0.status != "cancelled" }
            .reduce(0.0) { total, item in
                guard let order = item.order else { return total }
                let fraction = AccountingMath.capturedFraction(ticketTotal: order.total, recognizedBeforeRefunds: capturedByOrder[order.id, default: 0])
                let references = [item.id] + item.modifiers.filter { !$0.isDeleted }.map(\.id)
                let ledgerCost = references.reduce(0.0) { $0 + (ledgerCostByReference[$1] ?? 0) }
                if ledgerCost > 0 { return total + ledgerCost * fraction }
                guard let menuItem = item.menuItem else { return total }
                let recipeCost = menuItem.recipes.filter { !$0.isDeleted }.reduce(0.0) { cost, recipe in
                    guard let inventory = recipe.inventoryItem else { return cost }
                    return cost + InventoryRequirementCalculator.required(for: recipe, saleQuantity: item.quantity) * inventory.costPrice
                }
                let modifierCost = item.modifiers.filter { !$0.isDeleted }.reduce(0.0) { cost, line in
                    guard let modifier = line.modifier,
                          !modifier.isDeleted,
                          let inventory = modifier.inventoryItemLink else { return cost }
                    return cost + InventoryRequirementCalculator.required(for: modifier, saleQuantity: item.quantity) * inventory.costPrice
                }
                return total + (recipeCost + modifierCost) * fraction
            }
        let returnedCost = inventoryTransactions.filter {
            !$0.isDeleted && $0.movementType == .refundReturn && interval.contains($0.createdAt) &&
            $0.item?.branch?.id == activeBranchUUID
        }.reduce(0.0) { $0 + $1.magnitude * ($1.costPrice ?? $1.item?.costPrice ?? 0) }
        return max(0, soldCost - returnedCost)
    }

    private func trend(current: Double, previous: Double) -> String? {
        guard abs(previous) > 0.005 else { return nil }
        return String(format: "%+.1f%%", (current - previous) / abs(previous) * 100)
    }

    private func paymentMethodDisplayName(_ key: String) -> String {
        switch key {
        case "cash":         return "reports_method_cash".t
        case "credit_card":  return "dashboard_credit_card".t
        case "qr_promptpay": return "PromptPay"
        case "true_money":   return "TrueMoney"
        default:             return key.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func paymentMethodColor(_ method: String) -> Color {
        let m = method.lowercased()
        if m.contains("cash") || m.contains("เงินสด") { return Color(hex: "10B981") }
        if m.contains("credit") || m.contains("card") || m.contains("บัตร") { return Color(hex: "3B82F6") }
        if m.contains("promptpay") || m.contains("qr") { return Color(hex: "8B5CF6") }
        if m.contains("true") || m.contains("wallet") { return Color(hex: "F59E0B") }
        return Color(hex: "EC4899")
    }

    private var unsyncedTodayOrders: [Order] {
        todayOrders.filter { !$0.isSynced }
    }

    private var unsyncedTodayPayments: [Payment] {
        todayOrders.flatMap(\.payments).filter { !$0.isDeleted && !$0.isSynced }
    }

    private var latestDashboardUpdate: Date {
        let orderDate = todayOrders.map(\.updatedAt).max()
        let paymentDate = todayOrders.flatMap(\.payments).map(\.updatedAt).max()
        return [orderDate, paymentDate].compactMap { $0 }.max() ?? currentTime
    }

    private var staffOnDuty: [(name: String, clockIn: Date)] {
        activeTimecards.filter { $0.employee?.branchId.caseInsensitiveCompare(activeBranchId) == .orderedSame }.compactMap { tc in
            guard let emp = tc.employee else { return nil }
            return (name: "\(emp.firstName) \(emp.lastName)", clockIn: tc.clockIn)
        }
    }

    private var hasSalesDataTodayOrYesterday: Bool {
        !completedTodayOrders.isEmpty || !comparisonOrders.isEmpty
    }

    private var animatedChartSalesData: [DashboardHourlySalesPoint] {
        chartSalesData.map {
            DashboardHourlySalesPoint(
                hour: $0.hour,
                revenue: $0.revenue * chartAnimationProgress,
                ordersCount: Int(Double($0.ordersCount) * chartAnimationProgress),
                itemsCount: Int(Double($0.itemsCount) * chartAnimationProgress),
                period: $0.period
            )
        }
    }

    private var peakRushHourText: String? {
        let todayLabel = selectedPeriod.title(isThai: lm.currentLanguage == .thai)
        let todayPoints = chartSalesData.filter { $0.period == todayLabel }
        if hourlyChartMetric == .revenue {
            guard let peak = todayPoints.max(by: { $0.revenue < $1.revenue }), peak.revenue > 0 else { return nil }
            return String(format: "%02d:00–%02d:00 (%@)", peak.hour, (peak.hour + 1) % 24, dashboardMoney(peak.revenue))
        } else {
            guard let peak = todayPoints.max(by: { $0.ordersCount < $1.ordersCount }), peak.ordersCount > 0 else { return nil }
            return String(format: "%02d:00–%02d:00 (%d " + (lm.currentLanguage == .thai ? "บิล" : "bills") + ")", peak.hour, (peak.hour + 1) % 24, peak.ordersCount)
        }
    }

    private var avgDiningDurationMinutes: Int {
        let dineInOrders = completedTodayOrders.filter { $0.orderType == "dine_in" }
        guard !dineInOrders.isEmpty else { return 0 }
        let totalMinutes = dineInOrders.reduce(0.0) { sum, ord in
            let diff = (ord.readyAt ?? ord.updatedAt).timeIntervalSince(ord.createdAt) / 60
            return sum + max(10, min(diff, 180))
        }
        return Int(totalMinutes / Double(dineInOrders.count))
    }

    private var animatedChartCategoryData: [DashboardCategorySalesPoint] {
        chartCategoryData.map {
            DashboardCategorySalesPoint(categoryName: $0.categoryName, revenue: $0.revenue * chartAnimationProgress)
        }
    }

    private func inferredCategoryName(for item: OrderItem) -> String {
        if let category = item.menuItem?.category?.name, !category.isEmpty {
            return category
        }
        let name = item.itemName.lowercased()
        if name.contains("drink") || name.contains("beverage") || name.contains("coffee") || name.contains("tea") || name.contains("juice") || name.contains("water") || name.contains("beer") || name.contains("lager") || name.contains("เครื่องดื่ม") || name.contains("ชา") || name.contains("กาแฟ") || name.contains("เบียร์") {
            return "Beverages"
        }
        if name.contains("dessert") || name.contains("cake") || name.contains("sweet") || name.contains("ของหวาน") || name.contains("เค้ก") {
            return "Desserts"
        }
        if name.contains("appetizer") || name.contains("snack") || name.contains("starter") || name.contains("ทานเล่น") || name.contains("ของกินเล่น") {
            return "Appetizers"
        }
        return "Main Dishes"
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("dashboard_title".t)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(heroForeground)
                    Text(lm.currentLanguage == .thai ? "ภาพรวมเรียลไทม์" : "Live Snapshot")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(heroForeground.opacity(0.9))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(heroForeground.opacity(0.12), in: Capsule())
                }
                Text(currentTime.formatted(date: .complete, time: .omitted) + " • " + (lm.currentLanguage == .thai ? "สถานะการดำเนินงานหน้าร้านสด" : "Real-time floor & operational status"))
                    .font(.subheadline)
                    .foregroundColor(heroForeground.opacity(0.75))
            }
            Spacer()

            // Live indicator with pulse
            HStack(spacing: 6) {
                Circle()
                    .fill(heroForeground)
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle()
                            .stroke(heroForeground.opacity(0.5), lineWidth: 2)
                            .scaleEffect(livePulse ? 1.9 : 1.1)
                            .opacity(livePulse ? 0 : 1)
                    )
                Text("LIVE")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(heroForeground)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(heroForeground.opacity(0.10))
            .cornerRadius(20)

            // Current time
            Text(currentTime.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(heroForeground)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(heroForeground.opacity(0.10))
                .cornerRadius(8)

            // Export / share daily summary
            Button(action: beginDashboardExport) {
                Label(isExportingPDF ? "กำลังสร้าง…" : "export_pdf".t, systemImage: isExportingPDF ? "hourglass" : "square.and.arrow.up")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(heroForeground)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .apLiquidGlass(tint: heroForeground.opacity(0.10), interactive: true, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isExportingPDF)

        }
        .padding(18)
        .background {
            AnimatedFinancialClouds(reduceMotion: reduceMotion)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(LinearGradient(colors: [heroForeground.opacity(0.34), heroForeground.opacity(0.04)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                }
        }
        .apLiquidGlass(tint: Color(hex: "20B8CD").opacity(0.08), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Color(hex: "20B8CD").opacity(0.22), radius: 16, x: 0, y: 8)
    }

    private var heroForeground: Color { colorScheme == .dark ? .white : Color(hex: "122033") }

    // MARK: - Global Filters

    private var availableCashiers: [String] {
        Array(Set(branchOrders.map(\.cashierName).filter { !$0.isEmpty })).sorted()
    }

    private var dashboardFilterBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(lm.currentLanguage == .thai ? "ตัวกรองทั้ง Dashboard" : "Dashboard filters", systemImage: "line.3.horizontal.decrease.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.textPrimary)
                Spacer()
                Picker("", selection: $presentationModeRawValue) {
                    Label(lm.currentLanguage == .thai ? "แบบง่าย" : "Simple", systemImage: "rectangle.grid.1x2")
                        .tag(DashboardPresentationMode.simple.rawValue)
                    Label(lm.currentLanguage == .thai ? "แบบเต็ม" : "Full", systemImage: "rectangle.grid.2x2")
                        .tag(DashboardPresentationMode.full.rawValue)
                }
                .pickerStyle(.segmented)
                .frame(width: 210)
                .accessibilityLabel(lm.currentLanguage == .thai ? "รูปแบบการแสดงแดชบอร์ด" : "Dashboard display mode")
                // Role-based Auto Identification Badge
                HStack(spacing: 6) {
                    Image(systemName: effectiveViewMode == .operations ? "person.badge.shield.checkmark.fill" : "crown.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(effectiveViewMode == .operations ? .appTeal : .appAccent)
                    Text(sessionManager.currentStaffSession.map { "\($0.displayName) (\($0.roleName))" } ?? (effectiveViewMode == .operations ? (lm.currentLanguage == .thai ? "ปฏิบัติการ / แคชเชียร์" : "Operations / Cashier") : (lm.currentLanguage == .thai ? "ผู้บริหาร / เจ้าของ" : "Executive / Owner")))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(.textSecondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.appSurfaceHigh)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.appBorderSubtle, lineWidth: 1))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    dashboardFilterMenu(title: selectedPeriod.title(isThai: lm.currentLanguage == .thai), icon: "calendar") {
                        AnyView(ForEach(DashboardPeriod.allCases) { period in
                            Button(period.title(isThai: lm.currentLanguage == .thai)) { selectedPeriod = period }
                        })
                    }
                    if selectedPeriod == .historicalShift {
                        dashboardFilterMenu(
                            title: selectedHistoricalSession.map(shiftLabel) ?? (lm.currentLanguage == .thai ? "เลือกกะ" : "Select shift"),
                            icon: "clock.arrow.2.circlepath"
                        ) {
                            AnyView(ForEach(branchRegisterSessions.filter { $0.closedAt != nil }) { session in
                                Button(shiftLabel(session)) { selectedRegisterSessionId = session.id }
                            })
                        }
                    }
                    dashboardFilterMenu(title: lm.currentLanguage == .thai ? "สาขาปัจจุบัน" : "Active branch", icon: "building.2") {
                        AnyView(Text(lm.currentLanguage == .thai ? "ข้อมูลของสาขาที่กำลังใช้งาน" : "Current active branch"))
                    }
                    dashboardFilterMenu(title: selectedChannel.title(isThai: lm.currentLanguage == .thai), icon: "point.3.connected.trianglepath.dotted") {
                        AnyView(ForEach(DashboardSalesChannel.allCases) { channel in
                            Button(channel.title(isThai: lm.currentLanguage == .thai)) { selectedChannel = channel }
                        })
                    }
                    dashboardFilterMenu(title: selectedCashier == "all" ? (lm.currentLanguage == .thai ? "พนักงานทั้งหมด" : "All staff") : selectedCashier, icon: "person.crop.circle") {
                        AnyView(Group {
                            Button(lm.currentLanguage == .thai ? "พนักงานทั้งหมด" : "All staff") { selectedCashier = "all" }
                            ForEach(availableCashiers, id: \.self) { cashier in
                                Button(cashier) { selectedCashier = cashier }
                            }
                        })
                    }
                    dashboardFilterMenu(title: selectedComparison.title(isThai: lm.currentLanguage == .thai), icon: "arrow.left.arrow.right") {
                        AnyView(ForEach(DashboardComparison.allCases) { comparison in
                            Button(comparison.title(isThai: lm.currentLanguage == .thai)) { selectedComparison = comparison }
                        })
                    }
                }
            }
        }
        .padding(14)
        .apLiquidGlass(tint: Color.appAccent.opacity(0.025), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// The content is intentionally type-erased. A generic helper here caused
    /// recursive generic-metadata substitution on physical iPads when all seven
    /// filter-menu specializations were instantiated together.
    private func dashboardFilterMenu(title: String, icon: String, content: () -> AnyView) -> some View {
        Menu(content: content) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .font(.caption.weight(.semibold))
            .foregroundColor(.textSecondary)
            .padding(.horizontal, 11).frame(height: 34)
            .background(Color.appSurface.opacity(0.72), in: Capsule())
            .overlay(Capsule().stroke(Color.appDivider, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Data Health & Exceptions

    private var dataHealthStrip: some View {
        HStack(spacing: 10) {
            Label(lm.currentLanguage == .thai ? "ข้อมูลล่าสุด \(latestDashboardUpdate.formatted(date: .omitted, time: .shortened))" : "Updated \(latestDashboardUpdate.formatted(date: .omitted, time: .shortened))", systemImage: "clock.arrow.circlepath")
            Divider().frame(height: 16)
            Label(lm.currentLanguage == .thai ? "สาขาปัจจุบัน" : "Active branch", systemImage: "building.2")
            Divider().frame(height: 16)
            if offlineSyncMode {
                Label(
                    lm.currentLanguage == .thai ? "โหมดออฟไลน์ · ข้อมูลบันทึกในเครื่อง" : "Offline mode · Data saved locally",
                    systemImage: "internaldrive.fill"
                )
                .foregroundColor(.appTeal)
            } else {
                Label(lm.currentLanguage == .thai ? "\(unsyncedTodayOrders.count) ออเดอร์รอซิงก์" : "\(unsyncedTodayOrders.count) orders pending sync", systemImage: unsyncedTodayOrders.isEmpty ? "checkmark.icloud.fill" : "icloud.slash.fill")
                    .foregroundColor(unsyncedTodayOrders.isEmpty ? .appTeal : .appAmber)
                Label(lm.currentLanguage == .thai ? "\(unsyncedTodayPayments.count) payment รอซิงก์" : "\(unsyncedTodayPayments.count) payments pending sync", systemImage: "creditcard.and.123")
                    .foregroundColor(unsyncedTodayPayments.isEmpty ? .textSecondary : .appAmber)
            }
            Spacer()
            Text("\(selectedPeriod.title(isThai: lm.currentLanguage == .thai)) · " + (lm.currentLanguage == .thai ? "เวลาท้องถิ่น" : "Local time"))
                .foregroundColor(.textTertiary)
        }
        .font(.caption2).foregroundColor(.textSecondary)
        .padding(.horizontal, 14).padding(.vertical, 9)
        .apLiquidGlass(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var exceptionCenterCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "exclamationmark.shield.fill").foregroundColor(.appAmber)
                Text(lm.currentLanguage == .thai ? "ศูนย์ตรวจสอบรายการผิดปกติ" : "Exception center")
                    .font(.headline).foregroundColor(.textPrimary)
                Spacer()
                Text("\(dashboardExceptions.count) " + (lm.currentLanguage == .thai ? "ประเภท" : "issues"))
                    .font(.caption).fontWeight(.bold).foregroundColor(.appAmber)
            }
            ForEach(dashboardExceptions) { issue in
                DisclosureGroup {
                    VStack(spacing: 5) {
                        ForEach(issue.orders.prefix(10)) { order in
                            Button {
                                selectedOrderForVoid = order
                                showingOrderVoidSheet = true
                            } label: {
                                HStack(spacing: 8) {
                                    if let platformNo = order.platformOrderNumber?.trimmingCharacters(in: .whitespacesAndNewlines), !platformNo.isEmpty {
                                        Text(platformNo)
                                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                                            .foregroundColor(.appAccent)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(Color.appAccent.opacity(0.12))
                                            .cornerRadius(4)
                                        Text("#\(order.orderNumber)").fontWeight(.semibold).foregroundColor(.textTertiary)
                                    } else {
                                        Text("#\(order.orderNumber)").fontWeight(.semibold)
                                    }
                                    Text(order.createdAt.formatted(date: .omitted, time: .shortened)).foregroundColor(.textTertiary)
                                    Text(order.paymentStatus.capitalized).foregroundColor(issue.color)
                                    if let brand = order.deliveryBrand, !brand.isEmpty { Text(brand).foregroundColor(.textTertiary) }
                                    Spacer()
                                    Text(dashboardMoney(order.recognizedNetTotal)).fontWeight(.semibold)
                                    Image(systemName: "xmark.bin")
                                        .font(.system(size: 10))
                                        .foregroundColor(.appRose)
                                        .padding(.leading, 4)
                                }
                                .font(.system(size: 10, design: .monospaced))
                            }
                            .buttonStyle(.plain)
                        }
                    }.padding(.top, 7).padding(.leading, 18)
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: issue.icon).foregroundColor(issue.color).frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(issue.title(isThai: lm.currentLanguage == .thai)).font(.subheadline).fontWeight(.semibold).foregroundColor(.textPrimary)
                            Text(issue.detail(isThai: lm.currentLanguage == .thai)).font(.caption2).foregroundColor(.textTertiary)
                        }
                        Spacer()
                        Text("\(issue.count)").font(.system(.caption, design: .monospaced)).fontWeight(.bold)
                        Text(dashboardMoney(issue.amount)).font(.system(.caption, design: .monospaced)).fontWeight(.bold).foregroundColor(issue.color).frame(width: 100, alignment: .trailing)
                    }
                }.tint(issue.color)
                Divider().background(Color.appDivider)
            }

            // Summary of voided orders in this period
            HStack(spacing: 8) {
                Image(systemName: "xmark.bin.fill")
                    .foregroundColor(metrics.todayVoidedOrdersCount > 0 ? .appRose : .textTertiary)
                    .font(.caption)
                if metrics.todayVoidedOrdersCount > 0 {
                    Text(lm.currentLanguage == .thai
                         ? "บิลที่ยกเลิกในรอบนี้ (Voided): \(metrics.todayVoidedOrdersCount) บิล · รวม \(dashboardMoney(metrics.todayVoidedAmount))"
                         : "Voided in this period: \(metrics.todayVoidedOrdersCount) orders · \(dashboardMoney(metrics.todayVoidedAmount))")
                        .font(.caption2)
                        .foregroundColor(.textSecondary)
                } else {
                    Text(lm.currentLanguage == .thai
                         ? "ยังไม่มีบิลที่ถูกยกเลิกในรอบนี้"
                         : "No voided orders in this period")
                        .font(.caption2)
                        .foregroundColor(.textTertiary)
                }
                Spacer()
                Button {
                    selectedOrderForVoid = nil
                    showingOrderVoidSheet = true
                } label: {
                    Text(lm.currentLanguage == .thai ? "จัดการยกเลิกบิล" : "Manage Voids")
                        .font(.caption2.bold())
                        .foregroundColor(.appAccent)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 2)
        }
        .padding(16)
        .apLiquidGlass(tint: Color.appAmber.opacity(0.035), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Financial Summary Card (Separating In-Store Direct Money & Delivery Receivables)

    private var financialSummaryCard: some View {
        let netDeliveryExpected = max(deliverySalesTotal - todayDeliveryPlatformFees, 0)
        let netCombinedProceeds = storefrontSalesTotal + netDeliveryExpected

        return VStack(alignment: .leading, spacing: 14) {
            // Card Header
            HStack {
                ZStack {
                    Circle()
                        .fill(Color(hex: "10B981").opacity(0.12))
                        .frame(width: 28, height: 28)
                    Image(systemName: "banknote.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color(hex: "10B981"))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(lm.currentLanguage == .thai ? "สรุปการเงินและการรับชำระ" : "Financial & Settlement Summary")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.textPrimary)
                    Text(lm.currentLanguage == .thai ? "แยกยอดเงินจริงหน้าร้าน vs เดลิเวอรีรอโอน" : "Separated In-store Direct Funds vs Delivery Receivables")
                        .font(.system(size: 10))
                        .foregroundColor(.textTertiary)
                }
                Spacer()
                Text("dashboard_today".t)
                    .font(.caption2.weight(.medium))
                    .foregroundColor(.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.appSurfaceHigh)
                    .clipShape(Capsule())
            }

            // SECTION 1: In-Store Direct Money
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label(lm.currentLanguage == .thai ? "1. ยอดรับเงินจริงหน้าร้าน (In-Store Direct)" : "1. In-Store Direct Settlements", systemImage: "storefront.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.appAccent)
                    Spacer()
                    Text(dashboardMoney(storefrontSalesTotal))
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(.appAccent)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.appAccent.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                VStack(spacing: 2) {
                    financialRow(lm.currentLanguage == .thai ? "   • เงินสดเข้าลิ้นชัก (Cash)" : "   • Cash in Drawer", cashTenderTotal, .appTeal)
                    financialRow(lm.currentLanguage == .thai ? "   • เงินโอน / QR PromptPay" : "   • PromptPay / QR Transfer", transferTenderTotal, .appIndigo)
                    let cardAndOther = max(storefrontSalesTotal - cashTenderTotal - transferTenderTotal, 0)
                    if cardAndOther > 0 {
                        financialRow(lm.currentLanguage == .thai ? "   • บัตรเครดิต / ช่องทางอื่น" : "   • Credit Card / Other", cardAndOther, .textSecondary)
                    }
                }
            }

            // SECTION 2: Delivery & Receivables
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label(lm.currentLanguage == .thai ? "2. ยอดเดลิเวอรี & รอกระทบยอด (Delivery Receivables)" : "2. Delivery Platforms & Receivables", systemImage: "box.truck.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.appTeal)
                    Spacer()
                    Text(dashboardMoney(netDeliveryExpected))
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(.appTeal)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.appTeal.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                VStack(spacing: 2) {
                    financialRow(lm.currentLanguage == .thai ? "   • ยอดขายบนแอป (Gross Delivery)" : "   • Gross Delivery Sales", deliverySalesTotal, .textPrimary)
                    financialRow(lm.currentLanguage == .thai ? "   • หัก ค่า GP & ค่าธรรมเนียมแพลตฟอร์ม" : "   • Less Platform GP & Fees", -todayDeliveryPlatformFees, .appRose)
                    financialRow(lm.currentLanguage == .thai ? "   • ยอดสุทธิประเมินที่แพลตฟอร์มจะโอนเข้า" : "   • Expected Platform Payout", netDeliveryExpected, .appTeal, bold: true)
                }
            }

            Divider().background(Color.appDivider)

            // SECTION 3: Combined Accounting Revenue & Tax
            VStack(spacing: 3) {
                financialRow(lm.currentLanguage == .thai ? "รวมรายได้สุทธิทางบัญชีทั้งร้าน" : "Total Combined Net Proceeds", netCombinedProceeds, Color(hex: "10B981"), bold: true)
                financialRow(L.Sales.taxCollected.t + (lm.currentLanguage == .thai ? " (รวมในยอดแล้ว)" : " (included)"), todayVATCollected, .textSecondary)
                if todayServiceCharge > 0 {
                    financialRow("service_charge_lbl".t + (lm.currentLanguage == .thai ? " (รวมในยอดแล้ว)" : " (included)"), todayServiceCharge, .textSecondary)
                }
            }

            // Note on drawer reconciliation
            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.appAccent)
                Text(lm.currentLanguage == .thai
                     ? "ยอดเงินสดในลิ้นชักที่ต้องกระทบยอดตรวจนับ คือยอดส่วนที่ 1 (เงินสดเข้าลิ้นชัก) เท่านั้น ยอดเดลิเวอรีจะไม่รวมในเงินสดหน้าร้าน"
                     : "Cash drawer reconciliation applies only to Section 1 (Cash). Delivery orders are settled separately by platforms.")
                    .font(.system(size: 10))
                    .foregroundColor(.textTertiary)
            }
            .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .apLiquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func financialRow(_ label: String, _ value: Double, _ color: Color, bold: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.system(size: bold ? 13 : 12, weight: bold ? .bold : .regular))
                .foregroundColor(bold ? .textPrimary : .textSecondary)
            Spacer()
            Text("\(value < 0 ? "−" : "")\(currencySymbol)\(abs(value).formatted(.number.precision(.fractionLength(0))))")
                .font(.system(size: bold ? 14 : 12, weight: bold ? .bold : .medium, design: .monospaced))
                .foregroundColor(color)
                .contentTransition(.numericText())
        }
        .padding(.vertical, 1)
    }

    private func metricDefinition(_ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(title).fontWeight(.semibold).foregroundColor(.textSecondary).frame(width: 120, alignment: .leading)
            Text(detail).foregroundColor(.textTertiary).fixedSize(horizontal: false, vertical: true)
        }.font(.caption2)
    }

    // MARK: - Payment Mix Card

    private var paymentMixCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "creditcard.fill")
                    .foregroundColor(Color(hex: "8B5CF6"))
                Text(L.Sales.paymentMethods.t)
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                Spacer()
            }

            let chartEntries = todaySettlementMix.filter {
                !$0.method.isEmpty && $0.amount.isFinite && $0.amount > 0
            }

            if chartEntries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "creditcard")
                        .font(.system(size: 28))
                        .foregroundColor(.textTertiary)
                    Text("no_activity_yet".t)
                        .font(.caption)
                        .foregroundColor(.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            } else {
                HStack(spacing: 16) {
                    Chart(chartEntries, id: \.method) { entry in
                        SectorMark(
                            angle: .value("Amount", entry.amount),
                            innerRadius: .ratio(0.6),
                            angularInset: 1.5
                        )
                        .cornerRadius(4)
                        .foregroundStyle(paymentMethodColor(entry.method))
                    }
                    .frame(width: 110, height: 110)
                    .chartLegend(.hidden)
                    .transaction { transaction in
                        // Charts can trap inside CanvasDisplayList on iPad while
                        // SwiftUI is re-laying out an animated sector chart.
                        transaction.animation = nil
                        transaction.disablesAnimations = true
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(todaySettlementMix, id: \.method) { entry in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(paymentMethodColor(entry.method))
                                        .frame(width: 7, height: 7)
                                    Text(entry.method)
                                        .font(.caption)
                                        .foregroundColor(.textSecondary)
                                        .lineLimit(1)
                                    Spacer()
                                    Text("\(currencySymbol)\(entry.amount.formatted(.number.precision(.fractionLength(0))))")
                                        .font(.system(.caption, design: .monospaced))
                                        .fontWeight(.bold)
                                        .foregroundColor(.textPrimary)
                                }
                                HStack {
                                    Text("\(entry.count) " + (lm.currentLanguage == .thai ? "รายการ" : "transactions"))
                                    Spacer()
                                    Text(lm.currentLanguage == .thai ? "เฉลี่ย \(currencySymbol)\((entry.amount / Double(max(entry.count, 1))).formatted(.number.precision(.fractionLength(0))))" : "Avg \(currencySymbol)\((entry.amount / Double(max(entry.count, 1))).formatted(.number.precision(.fractionLength(0))))")
                                    Spacer()
                                    Text(todaySettledAmount > 0 ? String(format: "%.1f%%", entry.amount / todaySettledAmount * 100) : "0%")
                                }
                                .font(.system(size: 9))
                                .foregroundColor(.textTertiary)
                            }
                        }
                    }
                }

                Divider().background(Color.appDivider)
                HStack {
                    Text(lm.currentLanguage == .thai ? "รวมยอดตามวิธีชำระเงิน" : "Payment method total")
                    Spacer()
                    Text("\(currencySymbol)\(todaySettledAmount.formatted(.number.precision(.fractionLength(0))))")
                        .font(.system(.caption, design: .monospaced)).fontWeight(.bold)
                }
                .font(.caption)
                .foregroundColor(.textPrimary)

                if todaySupportGovernmentContribution > 0.005 {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(lm.currentLanguage == .thai
                             ? "รายละเอียดเงินร่วมจ่าย ไทยช่วยไทย พลัส"
                             : "Thai Chuai Thai Plus contribution")
                            .font(.caption2).fontWeight(.semibold)
                            .foregroundColor(.textSecondary)
                        HStack {
                            Text(lm.currentLanguage == .thai ? "ประชาชนจ่าย 40%" : "Citizen 40%")
                            Spacer()
                            Text("\(currencySymbol)\(todaySupportCitizenContribution.formatted(.number.precision(.fractionLength(0))))")
                        }
                        HStack {
                            Text(lm.currentLanguage == .thai ? "รัฐร่วมจ่าย 60%" : "Government contribution 60%")
                            Spacer()
                            Text("\(currencySymbol)\(todaySupportGovernmentContribution.formatted(.number.precision(.fractionLength(0))))")
                        }

                        if !pendingSupportSettlementOrders.isEmpty {
                            HStack(spacing: 5) {
                                Image(systemName: "clock")
                                Text(lm.currentLanguage == .thai
                                     ? "ข้อมูลประกอบ: รอตรวจสอบการกระทบยอด \(pendingSupportSettlementOrders.count) รายการ"
                                     : "Reference: \(pendingSupportSettlementOrders.count) settlements pending review")
                                Spacer()
                            }
                            .font(.system(size: 9))
                            .foregroundColor(.textTertiary)
                            .padding(.top, 3)
                        }
                    }
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.textSecondary)
                }

                if abs(todaySettlementVariance) > 0.005 {
                    HStack(spacing: 5) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(lm.currentLanguage == .thai ? "ยอดรอตรวจสอบ" : "Unreconciled")
                        Spacer()
                        Text("\(currencySymbol)\(abs(todaySettlementVariance).formatted(.number.precision(.fractionLength(0))))")
                    }
                    .font(.caption2).fontWeight(.semibold)
                    .foregroundColor(Color(hex: "F59E0B"))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .apLiquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Sales Channels & Delivery Drill-down

    private var salesChannelOverviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "point.3.connected.trianglepath.dotted").foregroundColor(.appAccent)
                Text(lm.currentLanguage == .thai ? "ยอดขายแยกตามช่องทาง" : "Sales by channel")
                    .font(.headline).foregroundColor(.textPrimary)
                Spacer()
                Text(lm.currentLanguage == .thai ? "ไม่รวมยอดซ้ำระหว่างช่องทาง" : "Mutually exclusive totals")
                    .font(.caption2).foregroundColor(.textTertiary)
            }

            if salesChannelSummaries.isEmpty {
                Text(lm.currentLanguage == .thai ? "ยังไม่มีข้อมูลในช่วงที่เลือก" : "No data for the selected period")
                    .font(.caption).foregroundColor(.textTertiary).padding(.vertical, 14)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(lm.currentLanguage == .thai ? "ช่องทาง" : "Channel").frame(width: 140, alignment: .leading)
                            Text(lm.currentLanguage == .thai ? "บิล" : "Bills").frame(width: 52, alignment: .trailing)
                            Text(lm.currentLanguage == .thai ? "เมนูหลัก" : "Main items").frame(width: 70, alignment: .trailing)
                            Text("Add-on").frame(width: 58, alignment: .trailing)
                            Text(lm.currentLanguage == .thai ? "ยอด Add-on" : "Add-on sales").frame(width: 90, alignment: .trailing)
                            Text(lm.currentLanguage == .thai ? "ยอดขาย" : "Sales").frame(width: 100, alignment: .trailing)
                            Text(lm.currentLanguage == .thai ? "เฉลี่ย/บิล" : "Avg/bill").frame(width: 92, alignment: .trailing)
                            Text(lm.currentLanguage == .thai ? "ค่าธรรมเนียม" : "Fees").frame(width: 92, alignment: .trailing)
                            Text(lm.currentLanguage == .thai ? "ยอดสุทธิ" : "Net").frame(width: 100, alignment: .trailing)
                        }
                        .font(.caption2.weight(.bold)).foregroundColor(.textSecondary)

                        ForEach(salesChannelSummaries) { channel in
                            HStack {
                                Label(channel.kind.title(isThai: lm.currentLanguage == .thai), systemImage: channel.kind.icon)
                                    .lineLimit(1)
                                    .foregroundColor(channel.kind.color).frame(width: 140, alignment: .leading)
                                Text("\(channel.orders)").frame(width: 52, alignment: .trailing)
                                Text("\(channel.mainItems)").frame(width: 70, alignment: .trailing)
                                Text("\(channel.addOnItems)").foregroundColor(channel.addOnItems > 0 ? .appAccent : .textTertiary).frame(width: 58, alignment: .trailing)
                                Text(dashboardMoney(channel.addOnSales)).foregroundColor(channel.addOnSales > 0 ? .appAccent : .textTertiary).frame(width: 90, alignment: .trailing)
                                Text(dashboardMoney(channel.gross)).frame(width: 100, alignment: .trailing)
                                Text(dashboardMoney(channel.averageTicket)).frame(width: 92, alignment: .trailing)
                                Text(channel.fees > 0 ? "−\(dashboardMoney(channel.fees))" : dashboardMoney(0)).foregroundColor(channel.fees > 0 ? .appRose : .textTertiary).frame(width: 92, alignment: .trailing)
                                Text(dashboardMoney(channel.net)).fontWeight(.bold).foregroundColor(.appTeal).frame(width: 100, alignment: .trailing)
                            }
                            .font(.system(size: 11, design: .monospaced)).foregroundColor(.textPrimary)
                            Divider().background(Color.appDivider)
                        }
                    }
                    .frame(minWidth: 780, alignment: .leading)
                }
            }
        }
        .padding(16)
        .apLiquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var deliveryChannelsCard: some View {
        let grossTotal = todayDeliveryPlatforms.reduce(0.0) { $0 + $1.gross }
        let feeTotal = todayDeliveryPlatforms.reduce(0.0) { $0 + $1.totalFees }
        let netTotal = todayDeliveryPlatforms.reduce(0.0) { $0 + $1.net }
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "shippingbox.fill").foregroundColor(Color(hex: "06B6D4"))
                VStack(alignment: .leading, spacing: 2) {
                    Text(lm.currentLanguage == .thai ? "ยอดขายตามช่องทางเดลิเวอรี" : "Delivery sales channels").font(.headline).foregroundColor(.textPrimary)
                    Text(lm.currentLanguage == .thai ? "รวมอยู่ในยอดขายด้านบนแล้ว · แตะแพลตฟอร์มเพื่อดูรายละเอียด" : "Already included in total sales · Expand for details").font(.caption2).foregroundColor(.textTertiary)
                }
                Spacer()
                Text(lm.currentLanguage == .thai ? "รายงานเต็ม: ยอดขาย › Delivery" : "Full report: Sales › Delivery").font(.caption).fontWeight(.semibold).foregroundColor(.appAccent)
            }
            HStack(spacing: 10) {
                deliverySummaryMetric(lm.currentLanguage == .thai ? "ออเดอร์" : "Orders", "\(todayDeliveryPlatforms.reduce(0) { $0 + $1.orders.count })", .appAccent)
                deliverySummaryMetric(lm.currentLanguage == .thai ? "ยอดขายรวม" : "Gross sales", dashboardMoney(grossTotal), .textPrimary)
                deliverySummaryMetric(lm.currentLanguage == .thai ? "ค่าธรรมเนียมรวม" : "Total fees", dashboardMoney(feeTotal), .appRose)
                deliverySummaryMetric(lm.currentLanguage == .thai ? "ยอดสุทธิ" : "Net proceeds", dashboardMoney(netTotal), .appTeal)
            }
            VStack(spacing: 0) {
                deliveryTableHeader
                ForEach(todayDeliveryPlatforms) { platform in
                    Divider().background(Color.appDivider)
                    DisclosureGroup {
                        VStack(spacing: 7) {
                            HStack(spacing: 12) {
                                deliveryFeeDetail("GP/Commission", platform.gpFees)
                                deliveryFeeDetail(lm.currentLanguage == .thai ? "ค่าโฆษณา" : "Advertising", platform.adFees)
                                deliveryFeeDetail(lm.currentLanguage == .thai ? "ค่าใช้จ่ายอื่น" : "Other fees", platform.otherFees)
                                deliveryFeeDetail(lm.currentLanguage == .thai ? "อัตราค่าธรรมเนียม" : "Fee rate", platform.effectiveFeeRate, isPercent: true)
                                deliveryFeeDetail(lm.currentLanguage == .thai ? "รอบโอนเงิน" : "Payout cycle", platform.payoutSchedule(isThai: lm.currentLanguage == .thai))
                            }
                            ForEach(platform.orders.prefix(8)) { order in
                                Button {
                                    selectedDeliveryOrderForEdit = order
                                } label: {
                                    HStack(spacing: 8) {
                                        if let platformNo = order.platformOrderNumber?.trimmingCharacters(in: .whitespacesAndNewlines), !platformNo.isEmpty {
                                            Text(platformNo)
                                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                                .foregroundColor(.appAccent)
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(Color.appAccent.opacity(0.12))
                                                .cornerRadius(4)
                                            Text("#\(order.orderNumber)").foregroundColor(.textTertiary)
                                        } else {
                                            Text("#\(order.orderNumber)").fontWeight(.semibold)
                                        }
                                        Text(order.createdAt.formatted(date: .omitted, time: .shortened)).foregroundColor(.textTertiary)
                                        Text("\(order.items.filter(isMainSaleItem).reduce(0) { $0 + $1.quantity }) " + (lm.currentLanguage == .thai ? "เมนูหลัก" : "main items")).foregroundColor(.textTertiary)
                                        Spacer()
                                        Text(dashboardMoney(order.recognizedNetTotal))
                                        Text("−\(dashboardMoney(order.deliveryPlatformCost))").foregroundColor(.appRose)
                                        Text(dashboardMoney(order.deliveryNetRevenue)).foregroundColor(.appTeal).fontWeight(.bold)
                                        Image(systemName: "pencil.circle")
                                            .foregroundColor(.textTertiary.opacity(0.8))
                                    }.font(.system(size: 10, design: .monospaced))
                                }
                                .buttonStyle(.plain)
                            }
                        }.padding(.top, 8).padding(.leading, 14)
                    } label: { deliveryPlatformRow(platform) }
                    .tint(.appAccent).padding(.vertical, 8)
                }
            }
        }
        .padding(16)
        .apLiquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var deliveryTableHeader: some View {
        HStack {
            Text(lm.currentLanguage == .thai ? "แพลตฟอร์ม" : "Platform").frame(maxWidth: .infinity, alignment: .leading)
            Text(lm.currentLanguage == .thai ? "ออเดอร์" : "Orders").frame(width: 60, alignment: .trailing)
            Text(lm.currentLanguage == .thai ? "ยอดรวม" : "Gross").frame(width: 100, alignment: .trailing)
            Text(lm.currentLanguage == .thai ? "ค่าธรรมเนียม" : "Fees").frame(width: 100, alignment: .trailing)
            Text(lm.currentLanguage == .thai ? "ยอดสุทธิ" : "Net").frame(width: 100, alignment: .trailing)
            Text(lm.currentLanguage == .thai ? "คงเหลือ" : "Margin").frame(width: 70, alignment: .trailing)
        }.font(.caption2).fontWeight(.bold).foregroundColor(.textSecondary).padding(.horizontal, 24).padding(.vertical, 5)
    }

    private func deliveryPlatformRow(_ platform: DashboardDeliveryPlatform) -> some View {
        HStack {
            HStack(spacing: 7) { Circle().fill(platform.color).frame(width: 8, height: 8); Text(platform.brand).fontWeight(.semibold).lineLimit(1) }.frame(maxWidth: .infinity, alignment: .leading)
            Text("\(platform.orders.count)").frame(width: 60, alignment: .trailing)
            Text(dashboardMoney(platform.gross)).frame(width: 100, alignment: .trailing)
            Text("−\(dashboardMoney(platform.totalFees))").foregroundColor(.appRose).frame(width: 100, alignment: .trailing)
            Text(dashboardMoney(platform.net)).foregroundColor(.appTeal).fontWeight(.bold).frame(width: 100, alignment: .trailing)
            Text(String(format: "%.1f%%", platform.netMargin)).frame(width: 70, alignment: .trailing)
        }.font(.system(size: 11, design: .monospaced)).foregroundColor(.textPrimary)
    }

    private func deliverySummaryMetric(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) { Text(title).font(.caption2).foregroundColor(.textSecondary); Text(value).font(.system(.subheadline, design: .monospaced)).fontWeight(.bold).foregroundColor(color) }
            .padding(9).frame(maxWidth: .infinity, alignment: .leading).background(Color.appSurfaceHigh.opacity(0.7)).clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func deliveryFeeDetail(_ title: String, _ value: Double, isPercent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) { Text(title).font(.system(size: 9)).foregroundColor(.textTertiary); Text(isPercent ? String(format: "%.1f%%", value) : dashboardMoney(value)).font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundColor(.textSecondary) }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func deliveryFeeDetail(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 9)).foregroundColor(.textTertiary)
            Text(text).font(.system(size: 10, weight: .semibold)).foregroundColor(.textSecondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func dashboardMoney(_ value: Double) -> String {
        "\(currencySymbol)\(value.formatted(.number.precision(.fractionLength(2))))"
    }

    private func shiftLabel(_ session: RegisterSession) -> String {
        let end = session.closedAt ?? currentTime
        let day = session.openedAt.formatted(.dateTime.day().month(.abbreviated))
        let opened = session.openedAt.formatted(date: .omitted, time: .shortened)
        let closed = end.formatted(date: .omitted, time: .shortened)
        return "\(day) · \(opened)–\(closed)"
    }

    // MARK: - Helper Labels for Tenders & Add-ons

    private var transferSummaryDetailText: String {
        if transferBreakdown.isEmpty {
            return lm.currentLanguage == .thai ? "PromptPay และการโอนเงิน" : "PromptPay & bank transfer"
        }
        let parts = transferBreakdown.prefix(2).map { "\($0.displayName): \(dashboardMoney($0.amount))" }
        return parts.joined(separator: " · ")
    }

    private var addOnsSummaryDetailText: String {
        if addOnBreakdown.isEmpty {
            return lm.currentLanguage == .thai ? "ยอดรวม \(dashboardMoney(addOnsRevenue))" : "Total \(dashboardMoney(addOnsRevenue))"
        }
        let top = addOnBreakdown.prefix(2).map { "\($0.name) (\($0.quantity))" }.joined(separator: ", ")
        return (lm.currentLanguage == .thai ? "ขายดี: " : "Top: ") + top
    }

    private var storefrontAddOnsSummaryDetailText: String {
        if storefrontAddOnBreakdown.isEmpty {
            return lm.currentLanguage == .thai ? "ยอดรวม \(dashboardMoney(storefrontAddOnsRevenue))" : "Total \(dashboardMoney(storefrontAddOnsRevenue))"
        }
        let top = storefrontAddOnBreakdown.prefix(2).map { "\($0.name) (\($0.quantity))" }.joined(separator: ", ")
        return (lm.currentLanguage == .thai ? "ขายดี: " : "Top: ") + top
    }

    private var deliveryAddOnsSummaryDetailText: String {
        if deliveryAddOnBreakdown.isEmpty {
            return lm.currentLanguage == .thai ? "ยอดรวม \(dashboardMoney(deliveryAddOnsRevenue))" : "Total \(dashboardMoney(deliveryAddOnsRevenue))"
        }
        let top = deliveryAddOnBreakdown.prefix(2).map { "\($0.name) (\($0.quantity))" }.joined(separator: ", ")
        return (lm.currentLanguage == .thai ? "ขายดี: " : "Top: ") + top
    }

    // MARK: - Simple Dashboard

    private var simpleDashboardSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(lm.currentLanguage == .thai ? "สรุปยอดขาย" : "Sales summary")
                    .font(.title2.bold())
                    .foregroundColor(.textPrimary)
                Text(lm.currentLanguage == .thai
                     ? "ดูยอดรวม ช่องทางขาย และการรับชำระที่สำคัญในหน้าเดียว"
                     : "Your essential sales, channels, and payments at a glance")
                    .font(.subheadline)
                    .foregroundColor(.textSecondary)
            }

            HStack(spacing: 14) {
                SimpleDashboardCard(
                    title: lm.currentLanguage == .thai ? "ยอดขายสุทธิ" : "Net sales",
                    value: isSelectedLedgerComplete ? dashboardMoney(todayRevenue) : "—",
                    detail: "\(completedTodayOrders.count) " + (lm.currentLanguage == .thai ? "บิลสำเร็จ" : "completed bills"),
                    icon: "banknote.fill",
                    color: Color(hex: "10B981"),
                    isPrimary: true
                )
                SimpleDashboardCard(
                    title: lm.currentLanguage == .thai ? "ยอดเฉลี่ยต่อบิล" : "Average per bill",
                    value: dashboardMoney(avgOrderValue),
                    detail: lm.currentLanguage == .thai ? "เฉลี่ยจากทุกช่องทาง" : "Across all channels",
                    icon: "receipt.fill",
                    color: Color(hex: "3B82F6")
                )
                SimpleDashboardCard(
                    title: lm.currentLanguage == .thai ? "จำนวนสินค้าที่ขาย" : "Items sold",
                    value: "\(itemsSold)",
                    detail: lm.currentLanguage == .thai ? "รายการเมนูหลัก" : "main menu items",
                    icon: "shippingbox.fill",
                    color: Color(hex: "8B5CF6")
                )
            }

            simpleSectionHeader(
                title: lm.currentLanguage == .thai ? "ขายผ่านช่องทางไหน" : "Sales by channel",
                subtitle: lm.currentLanguage == .thai ? "ยอดสุทธิและจำนวนบิล" : "Net sales and bill count",
                icon: "square.grid.3x1.below.line.grid.1x2"
            )

            HStack(spacing: 14) {
                SimpleDashboardCard(
                    title: lm.currentLanguage == .thai ? "หน้าร้าน / ทานที่ร้าน" : "Dine-in",
                    value: dashboardMoney(dineInSalesTotal),
                    detail: "\(dineInOrderCount) " + (lm.currentLanguage == .thai ? "บิล" : "bills"),
                    icon: "storefront.fill",
                    color: Color(hex: "3B82F6")
                )
                SimpleDashboardCard(
                    title: lm.currentLanguage == .thai ? "สั่งกลับบ้าน" : "Takeaway",
                    value: dashboardMoney(takeOutSalesTotal),
                    detail: "\(takeOutOrderCount) " + (lm.currentLanguage == .thai ? "บิล" : "bills"),
                    icon: "takeoutbag.and.cup.and.straw.fill",
                    color: Color(hex: "F59E0B")
                )
                SimpleDashboardCard(
                    title: lm.currentLanguage == .thai ? "เดลิเวอรี" : "Delivery",
                    value: dashboardMoney(deliverySalesTotal),
                    detail: "\(completedDeliveryOrders.count) " + (lm.currentLanguage == .thai ? "บิล" : "bills"),
                    icon: "box.truck.fill",
                    color: Color(hex: "06B6D4")
                )
            }

            simpleSectionHeader(
                title: lm.currentLanguage == .thai ? "ลูกค้าชำระอย่างไร" : "Payments received",
                subtitle: lm.currentLanguage == .thai ? "ยอดรับแยกตามวิธีชำระเงิน" : "Collected by payment method",
                icon: "creditcard.fill"
            )

            if todayPaymentMix.isEmpty {
                ContentUnavailableView(
                    lm.currentLanguage == .thai ? "ยังไม่มีรายการชำระเงิน" : "No payments yet",
                    systemImage: "creditcard",
                    description: Text(lm.currentLanguage == .thai ? "รายการชำระเงินจะแสดงที่นี่เมื่อมีการขาย" : "Payments will appear here after a sale")
                )
                .frame(maxWidth: .infinity, minHeight: 130)
                .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
                    ForEach(Array(todayPaymentMix.enumerated()), id: \.offset) { _, payment in
                        SimpleDashboardCard(
                            title: payment.method,
                            value: dashboardMoney(payment.amount),
                            detail: "\(payment.count) " + (lm.currentLanguage == .thai ? "รายการชำระ" : "payments"),
                            icon: paymentIcon(payment.method),
                            color: paymentMethodColor(payment.method)
                        )
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var dineInOrderCount: Int {
        completedTodayOrders.filter { $0.orderType != "delivery" && $0.orderType != "take_out" }.count
    }

    private var takeOutOrderCount: Int {
        completedTodayOrders.filter { $0.orderType == "take_out" }.count
    }

    private func paymentIcon(_ method: String) -> String {
        let normalized = method.lowercased()
        if normalized.contains("cash") || normalized.contains("เงินสด") { return "banknote.fill" }
        if normalized.contains("promptpay") || normalized.contains("qr") { return "qrcode" }
        if normalized.contains("card") || normalized.contains("บัตร") { return "creditcard.fill" }
        if normalized.contains("wallet") || normalized.contains("true") { return "wallet.bifold.fill" }
        return "creditcard.and.123"
    }

    private func simpleSectionHeader(title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(.appAccent)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.headline).foregroundColor(.textPrimary)
                Text(subtitle).font(.caption).foregroundColor(.textSecondary)
            }
        }
    }

    // MARK: - Tier 1: Storewide Overview (ภาพรวมยอดขายทั้งร้าน)

    private var storewideOverviewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(lm.currentLanguage == .thai ? "1. ภาพรวมยอดขายทั้งร้าน (Storewide Overview)" : "1. Storewide Sales Overview", systemImage: "chart.bar.xaxis")
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                Spacer()
                Text(lm.currentLanguage == .thai ? "รวมทุกช่องทาง · ก่อนแยกหน้าร้าน / เดลิเวอรี" : "All channels combined")
                    .font(.caption2)
                    .foregroundColor(.textTertiary)
            }

            let previousRefunds = metrics.previousRefunds
            let previousRevenue = metrics.yesterdayRevenue
            let previousBills = metrics.previousBills
            let previousItems = metrics.previousItems
            let previousDiscounts = metrics.previousDiscounts
            let previousProfit = metrics.previousProfit
            let previousMargin = metrics.previousMargin
            let comparisonLabel = selectedComparison.subtitle(isThai: lm.currentLanguage == .thai)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                KPICard(
                    title: lm.currentLanguage == .thai ? "ยอดขายสุทธิรวม" : "Total net sales",
                    value: isSelectedLedgerComplete
                        ? "\(currencySymbol)\(todayRevenue.formatted(.number.precision(.fractionLength(0))))"
                        : "—",
                    icon: "banknote.fill",
                    color: Color(hex: "10B981"),
                    trend: trend(current: todayRevenue, previous: previousRevenue),
                    subtitle: comparisonLabel,
                    trendIsFavorable: todayRevenue >= previousRevenue
                )
                KPICard(
                    title: lm.currentLanguage == .thai ? "จำนวนบิลสำเร็จรวม" : "Total completed bills",
                    value: "\(completedTodayOrders.count)",
                    icon: "receipt.fill",
                    color: Color(hex: "3B82F6"),
                    trend: trend(current: Double(completedTodayOrders.count), previous: Double(previousBills)),
                    subtitle: comparisonLabel,
                    trendIsFavorable: completedTodayOrders.count >= previousBills
                )
                KPICard(
                    title: lm.currentLanguage == .thai ? "ยอดเฉลี่ยต่อบิลรวม" : "Overall average ticket",
                    value: dashboardMoney(avgOrderValue),
                    icon: "cart.fill",
                    color: Color(hex: "8B5CF6"),
                    trend: trend(current: avgOrderValue, previous: previousBills > 0 ? previousRevenue / Double(previousBills) : 0),
                    subtitle: comparisonLabel,
                    trendIsFavorable: avgOrderValue >= (previousBills > 0 ? previousRevenue / Double(previousBills) : 0)
                )
                KPICard(
                    title: lm.currentLanguage == .thai ? "จำนวนเมนูหลักที่ขาย" : "Main items sold",
                    value: "\(itemsSold)",
                    icon: "shippingbox.fill",
                    color: Color(hex: "06B6D4"),
                    trend: trend(current: Double(itemsSold), previous: Double(previousItems)),
                    subtitle: comparisonLabel,
                    trendIsFavorable: itemsSold >= previousItems
                )
                if canViewProfitAndCosts {
                    KPICard(
                        title: lm.currentLanguage == .thai ? "กำไรขั้นต้นโดยประมาณ" : "Estimated gross profit",
                        value: dashboardMoney(grossProfit),
                        icon: "chart.line.uptrend.xyaxis",
                        color: Color(hex: "14B8A6"),
                        trend: trend(current: grossProfit, previous: previousProfit),
                        subtitle: lm.currentLanguage == .thai ? "จากต้นทุนสูตรที่บันทึก" : "From recorded recipe costs",
                        trendIsFavorable: grossProfit >= previousProfit
                    )
                    KPICard(
                        title: lm.currentLanguage == .thai ? "อัตรากำไรขั้นต้น" : "Gross margin",
                        value: String(format: "%.1f%%", grossMargin),
                        icon: "percent",
                        color: Color(hex: "0EA5E9"),
                        trend: previousMargin > 0 ? String(format: "%+.1f จุด", grossMargin - previousMargin) : nil,
                        subtitle: lm.currentLanguage == .thai ? "ยอดสุทธิ − ต้นทุนสินค้า" : "Net sales − COGS",
                        trendIsFavorable: grossMargin >= previousMargin
                    )
                }
                KPICard(
                    title: lm.currentLanguage == .thai ? "ส่วนลดรวม" : "Total discounts",
                    value: dashboardMoney(todayDiscounts),
                    icon: "tag.fill",
                    color: Color(hex: "F59E0B"),
                    trend: trend(current: todayDiscounts, previous: previousDiscounts),
                    subtitle: comparisonLabel,
                    trendIsFavorable: todayDiscounts <= previousDiscounts
                )
                KPICard(
                    title: lm.currentLanguage == .thai ? "คืนสินค้ารวม" : "Total refunds",
                    value: dashboardMoney(todayRefunds),
                    icon: "arrow.uturn.backward.circle.fill",
                    color: todayRefunds > previousRefunds ? Color.appRose : Color.appTeal,
                    trend: trend(current: todayRefunds, previous: previousRefunds),
                    subtitle: "\(selectedPeriodRefunds.count) " + (lm.currentLanguage == .thai ? "รายการ" : "transactions"),
                    trendIsFavorable: todayRefunds <= previousRefunds
                )
            }
        }
    }

    // MARK: - Tier 2: Storefront Operations (ยอดขายหน้าร้าน & เงินรับจริง)

    private var storefrontOperationsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(lm.currentLanguage == .thai ? "2. ยอดขายหน้าร้าน & เงินรับจริง (Storefront Direct Settlements)" : "2. Storefront Direct Settlements", systemImage: "storefront.fill")
                    .font(.headline)
                    .foregroundColor(.appAccent)
                Spacer()
                Text(lm.currentLanguage == .thai ? "เงินสด & โอนเข้าบัญชีโดยตรง · ตรวจนับได้จริง" : "Direct cash & transfers · Auditable")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(.appTeal)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.appTeal.opacity(0.1))
                    .clipShape(Capsule())
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    DashboardBreakdownCard(
                        title: lm.currentLanguage == .thai ? "ยอดขายหน้าร้าน" : "Storefront sales",
                        value: dashboardMoney(storefrontSalesTotal),
                        detail: lm.currentLanguage == .thai
                            ? "\(completedStorefrontOrders.count) บิล · ทานที่ร้าน/สั่งกลับบ้าน"
                            : "\(completedStorefrontOrders.count) bills · Dine-in/Takeaway",
                        icon: "storefront.fill",
                        color: Color(hex: "3B82F6")
                    )
                    DashboardBreakdownCard(
                        title: lm.currentLanguage == .thai ? "เงินสดเข้าลิ้นชัก" : "Cash in drawer",
                        value: dashboardMoney(cashTenderTotal),
                        detail: lm.currentLanguage == .thai ? "รับชำระด้วยเงินสดจริง · กระทบยอดลิ้นชัก" : "Cash tender · Physical drawer audit",
                        icon: "banknote.fill",
                        color: Color(hex: "10B981"),
                        badge: lm.currentLanguage == .thai ? "นับเงินสด" : "Audit Cash"
                    )
                    DashboardBreakdownCard(
                        title: lm.currentLanguage == .thai ? "ยอดเงินโอน / QR" : "Transfer / QR",
                        value: dashboardMoney(transferTenderTotal),
                        detail: transferSummaryDetailText,
                        icon: "qrcode",
                        color: Color(hex: "8B5CF6"),
                        badge: lm.currentLanguage == .thai ? "แตะดูแจกแจง" : "Breakdown",
                        action: { showingTransferBreakdownSheet = true }
                    )
                    DashboardBreakdownCard(
                        title: lm.currentLanguage == .thai ? "รายการเสริมหน้าร้าน" : "Storefront add-ons",
                        value: "\(storefrontAddOnsSold) " + (lm.currentLanguage == .thai ? "รายการ" : "items"),
                        detail: storefrontAddOnsSummaryDetailText,
                        icon: "plus.circle.fill",
                        color: Color(hex: "F59E0B"),
                        badge: lm.currentLanguage == .thai ? "แตะดูแจกแจง" : "Breakdown",
                        action: {
                            addOnBreakdownChannel = .storefront
                            showingAddOnBreakdownSheet = true
                        }
                    )
                }
                .padding(.vertical, 2)
            }

            if bundleComponentsSold > 0 || promotionRewardsSold > 0 || (tableSystemEnabled && avgDiningDurationMinutes > 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        if bundleComponentsSold > 0 {
                            SecondaryKPICard(
                                title: lm.currentLanguage == .thai ? "ส่วนประกอบชุด" : "Bundle components",
                                value: "\(bundleComponentsSold) " + (lm.currentLanguage == .thai ? "ชิ้น" : "pcs"),
                                amount: dashboardMoney(bundleComponentsRevenue),
                                icon: "shippingbox.fill"
                            )
                            .frame(width: 240, height: 68)
                        }
                        if promotionRewardsSold > 0 {
                            SecondaryKPICard(
                                title: lm.currentLanguage == .thai ? "สินค้าของแถม" : "Promotion rewards",
                                value: "\(promotionRewardsSold) " + (lm.currentLanguage == .thai ? "รายการ" : "items"),
                                amount: promotionRewardsValue > 0 ? dashboardMoney(promotionRewardsValue) : (lm.currentLanguage == .thai ? "ฟรี" : "Free"),
                                icon: "gift.fill"
                            )
                            .frame(width: 240, height: 68)
                        }
                        if tableSystemEnabled && avgDiningDurationMinutes > 0 {
                            SecondaryKPICard(
                                title: lm.currentLanguage == .thai ? "เวลานั่งทานเฉลี่ย" : "Avg dining time",
                                value: "\(avgDiningDurationMinutes) " + (lm.currentLanguage == .thai ? "นาที" : "min"),
                                icon: "clock.arrow.circlepath"
                            )
                            .frame(width: 240, height: 68)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: - Tier 3: Delivery Receivables (เดลิเวอรี & ยอดเครดิตรอโอน - แยกขาดอย่างเด็ดขาด)

    private var deliveryCreditSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(lm.currentLanguage == .thai ? "3. ยอดเดลิเวอรี & รอกระทบยอด (Delivery Receivables)" : "3. Delivery Receivables", systemImage: "box.truck.fill")
                    .font(.headline)
                    .foregroundColor(Color(hex: "06B6D4"))
                Spacer()
                Text(lm.currentLanguage == .thai ? "แยกขาดจากหน้าร้านอย่างเด็ดขาด" : "Strictly separated from storefront")
                    .font(.caption2.bold())
                    .foregroundColor(.appRose)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.appRose.opacity(0.12))
                    .clipShape(Capsule())
            }

            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.shield.fill")
                    .foregroundColor(.appRose)
                    .font(.subheadline)
                Text(lm.currentLanguage == .thai
                     ? "เงินเดลิเวอรีเป็นยอดเครดิตรอโอนจากแพลตฟอร์ม (Receivables) ไม่สามารถนับเป็นเงินสดในลิ้นชักหน้าร้านได้จริง"
                     : "Delivery funds are platform credit receivables. They cannot be physically counted in the storefront cash drawer.")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                Spacer()
            }
            .padding(10)
            .background(Color.appRose.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.appRose.opacity(0.2), lineWidth: 1))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    DashboardBreakdownCard(
                        title: lm.currentLanguage == .thai ? "ยอดขายบนแอป (Gross)" : "Gross delivery sales",
                        value: dashboardMoney(deliveryGrossSales > 0 ? deliveryGrossSales : deliverySalesTotal),
                        detail: lm.currentLanguage == .thai ? "ยอดขายตามราคาเต็มบนแอปพลิเคชัน" : "Full price sales on delivery apps",
                        icon: "shippingbox.fill",
                        color: Color(hex: "06B6D4")
                    )
                    DashboardBreakdownCard(
                        title: lm.currentLanguage == .thai ? "หัก GP & ค่าธรรมเนียม" : "Less GP & platform fees",
                        value: todayDeliveryPlatformFees > 0 ? "−\(dashboardMoney(todayDeliveryPlatformFees))" : dashboardMoney(0),
                        detail: lm.currentLanguage == .thai ? "ค่าคอมมิชชั่นและค่าบริการแอปพลิเคชัน" : "Platform commission & fees",
                        icon: "percent",
                        color: .appRose
                    )
                    DashboardBreakdownCard(
                        title: lm.currentLanguage == .thai ? "ยอดสุทธิประเมินที่รอโอนเข้า" : "Expected net payout",
                        value: dashboardMoney(netDeliveryExpected),
                        detail: lm.currentLanguage == .thai ? "เงินโอนเข้าบัญชีตามรอบกระทบยอด" : "Estimated bank transfer after GP",
                        icon: "banknote",
                        color: .appTeal,
                        badge: lm.currentLanguage == .thai ? "เครดิตรอโอน" : "Receivable"
                    )
                    DashboardBreakdownCard(
                        title: lm.currentLanguage == .thai ? "จำนวนออเดอร์เดลิเวอรี" : "Delivery orders",
                        value: "\(completedDeliveryOrders.count) " + (lm.currentLanguage == .thai ? "บิล" : "bills"),
                        detail: todayDeliveryPlatforms.isEmpty
                            ? (lm.currentLanguage == .thai ? "ยังไม่มีคำสั่งซื้อเดลิเวอรี" : "No delivery orders")
                            : todayDeliveryPlatforms.map(\.brand).joined(separator: ", "),
                        icon: "scooter",
                        color: Color(hex: "F97316")
                    )
                    if deliveryAddOnsSold > 0 {
                        DashboardBreakdownCard(
                            title: lm.currentLanguage == .thai ? "รายการเสริมเดลิเวอรี" : "Delivery add-ons",
                            value: "\(deliveryAddOnsSold) " + (lm.currentLanguage == .thai ? "รายการ" : "items"),
                            detail: deliveryAddOnsSummaryDetailText,
                            icon: "plus.circle.fill",
                            color: Color(hex: "F59E0B"),
                            badge: lm.currentLanguage == .thai ? "แตะดูแจกแจง" : "Breakdown",
                            action: {
                                addOnBreakdownChannel = .delivery
                                showingAddOnBreakdownSheet = true
                            }
                        )
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // Forwarding aliases for backward compatibility
    private var kpiCardsSection: some View { storewideOverviewSection }
    private var restaurantItemMixSection: some View { storefrontOperationsSection }
    private var tenderAndDeliveryCardsSection: some View { deliveryCreditSection }

    // MARK: - Secondary KPIs

    private var secondaryKPIsSection: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 16) {
            SecondaryKPICard(
                title: "kpi_avg_order_value".t,
                value: "\(currencySymbol)\(avgOrderValue.formatted(.number.precision(.fractionLength(0))))",
                icon: "cart.fill"
            )
            SecondaryKPICard(
                title: "kpi_total_guests".t,
                value: "\(totalGuests)",
                icon: "person.2.fill"
            )
            SecondaryKPICard(
                title: "kpi_staff_on_duty".t,
                value: "\(staffOnDuty.count)",
                icon: "person.badge.clock.fill"
            )
            SecondaryKPICard(
                title: "kpi_orders_completed".t,
                value: "\(completedTodayOrders.count)",
                icon: "checkmark.circle.fill"
            )
        }
    }

    // MARK: - Top Selling Items Card

    private var topSellingItemsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "trophy.fill")
                    .foregroundColor(Color(hex: "F59E0B"))
                Text(lm.currentLanguage == .thai ? "เมนูหลักขายดี" : "Top-selling main items")
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                Spacer()
            }

            if topStorefrontItems.isEmpty && topDeliveryItems.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "fork.knife.circle")
                        .font(.system(size: 28))
                        .foregroundColor(.textTertiary)
                    Text("no_activity_yet".t)
                        .font(.caption)
                        .foregroundColor(.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            } else {
                topSellingChannelSection(
                    title: lm.currentLanguage == .thai ? "ยอดขายหน้าร้าน" : "Storefront sales",
                    subtitle: lm.currentLanguage == .thai ? "ราคาหน้าร้านเท่านั้น" : "Storefront prices only",
                    icon: "storefront.fill",
                    color: .appAccent,
                    items: topStorefrontItems
                )

                Divider().background(Color.appDivider)

                topSellingChannelSection(
                    title: lm.currentLanguage == .thai ? "ยอดขายเดลิเวอรี" : "Delivery sales",
                    subtitle: lm.currentLanguage == .thai ? "ราคาเดลิเวอรีเท่านั้น" : "Delivery prices only",
                    icon: "shippingbox.fill",
                    color: .appTeal,
                    items: topDeliveryItems
                )
            }
        }
        .padding(16)
        .apLiquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func topSellingChannelSection(
        title: String,
        subtitle: String,
        icon: String,
        color: Color,
        items: [(name: String, category: String, quantity: Int, revenue: Double)]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: icon).foregroundColor(color)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 12, weight: .bold)).foregroundColor(.textPrimary)
                    Text(subtitle).font(.system(size: 9)).foregroundColor(.textTertiary)
                }
            }

            if items.isEmpty {
                Text(lm.currentLanguage == .thai ? "ไม่มีรายการในช่องทางนี้" : "No items in this channel")
                    .font(.caption)
                    .foregroundColor(.textTertiary)
                    .padding(.vertical, 8)
            } else {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(spacing: 10) {
                        // Rank
                        Text("#\(index + 1)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(index < 3 ? Color(hex: "F59E0B") : .textTertiary)
                            .frame(width: 24)

                        // Name
                        Text(item.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.textPrimary)
                            .lineLimit(1)

                        Text(item.category)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.textTertiary)
                            .lineLimit(1)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.appSurfaceHigh)
                            .clipShape(Capsule())

                        Spacer()

                        // Quantity badge
                        Text("×\(item.quantity)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(color)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(color.opacity(0.1))
                            .cornerRadius(4)

                        // Revenue
                        Text("\(currencySymbol)\(item.revenue.formatted(.number.precision(.fractionLength(0))))")
                            .font(.system(size: 11))
                            .foregroundColor(.textSecondary)
                            .frame(width: 60, alignment: .trailing)

                        Text("\(lm.currentLanguage == .thai ? "เฉลี่ย " : "Avg ")\(currencySymbol)\((item.revenue / Double(max(item.quantity, 1))).formatted(.number.precision(.fractionLength(2))))/\(lm.currentLanguage == .thai ? "ชิ้น" : "unit")")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.textTertiary)
                            .frame(width: 105, alignment: .trailing)
                    }
                    .padding(.vertical, 3)

                    if index < items.count - 1 {
                        Divider().background(Color.appDivider)
                    }
                }
            }
        }
    }

    // MARK: - Staff On Duty Card

    private var staffOnDutyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "person.badge.clock.fill")
                    .foregroundColor(Color(hex: "8B5CF6"))
                Text("kpi_staff_on_duty".t)
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                Spacer()
                Text("\(staffOnDuty.count)")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.appAccent)
            }

            if staffOnDuty.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "person.slash")
                        .font(.system(size: 28))
                        .foregroundColor(.textTertiary)
                    Text("kpi_no_staff_on_duty".t)
                        .font(.caption)
                        .foregroundColor(.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            } else {
                ForEach(Array(staffOnDuty.enumerated()), id: \.offset) { index, staff in
                    HStack(spacing: 10) {
                        // Avatar
                        ZStack {
                            Circle()
                                .fill(Color(hex: "8B5CF6").opacity(0.15))
                                .frame(width: 30, height: 30)
                            Text(staffInitials(staff.name))
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(Color(hex: "8B5CF6"))
                        }

                        VStack(alignment: .leading, spacing: 1) {
                            Text(staff.name)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.textPrimary)
                                .lineLimit(1)
                            Text("kpi_clocked_in_at".t + " " + staff.clockIn.formatted(date: .omitted, time: .shortened))
                                .font(.system(size: 10))
                                .foregroundColor(.textTertiary)
                        }

                        Spacer()

                        // Duration
                        let mins = Int(currentTime.timeIntervalSince(staff.clockIn) / 60)
                        let hours = mins / 60
                        let remainMins = mins % 60
                        Text("\(hours)h \(remainMins)m")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.textSecondary)
                    }
                    .padding(.vertical, 2)

                    if index < staffOnDuty.count - 1 {
                        Divider().background(Color.appDivider)
                    }
                }
            }
        }
        .padding(16)
        .apLiquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Activity Feed

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundColor(.appAccent)
                Text("kpi_recent_activity".t)
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                Spacer()
                Text("\(completedTodayOrders.count) " + "kpi_orders_today_suffix".t)
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            }

            if todayOrders.prefix(10).isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 28))
                        .foregroundColor(.textTertiary)
                    Text("no_activity_yet".t)
                        .font(.subheadline)
                        .foregroundColor(.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 40)
            } else {
                ForEach(Array(todayOrders.prefix(10).enumerated()), id: \.offset) { index, order in
                    let identity = OrderDisplayIdentity(order: order, tableSystemEnabled: tableSystemEnabled)
                    HStack(spacing: 12) {
                        // Status icon
                        ZStack {
                            Circle()
                                .fill(statusColor(order.status).opacity(0.15))
                                .frame(width: 32, height: 32)
                            Image(systemName: statusIcon(order.status))
                                .font(.system(size: 13))
                                .foregroundColor(statusColor(order.status))
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("#\(order.orderNumber)")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.textPrimary)

                                if let pf = order.platformOrderNumber?.trimmingCharacters(in: .whitespacesAndNewlines), !pf.isEmpty {
                                    Text(pf)
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundColor(.appAccent)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Color.appAccent.opacity(0.12))
                                        .cornerRadius(4)
                                }

                                // Order type badge
                                Text(orderTypeName(order.orderType))
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(.textSecondary)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.appSurfaceHigh)
                                    .cornerRadius(4)

                                // Status badge
                                Text(order.status.capitalized)
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(statusColor(order.status))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(statusColor(order.status).opacity(0.1))
                                    .cornerRadius(4)
                            }

                            HStack(spacing: 4) {
                                Text(order.createdAt.formatted(date: .omitted, time: .shortened))
                                    .font(.system(size: 10))
                                    .foregroundColor(.textTertiary)
                                if identity.isQuickService || identity.tableNumber != nil {
                                    Text("• \(identity.primaryLabel)")
                                        .font(.system(size: 10))
                                        .foregroundColor(.textTertiary)
                                }
                                Text("• \(order.items.count) items")
                                    .font(.system(size: 10))
                                    .foregroundColor(.textTertiary)
                            }
                        }

                        Spacer()

                        Text("\(currencySymbol)\(order.total.formatted(.number.precision(.fractionLength(0))))")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.textPrimary)
                    }
                    .padding(.vertical, 6)

                    if index < min(todayOrders.count, 10) - 1 {
                        Divider().background(Color.appDivider)
                    }
                }
            }
        }
        .padding(16)
        .apLiquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Helpers

    private func staffInitials(_ name: String) -> String {
        let letters = name.split(separator: " ").prefix(2).compactMap { $0.first }
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    private func statusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "preparing": return Color(hex: "F59E0B")
        case "ready": return Color(hex: "3B82F6")
        case "served", "completed": return Color(hex: "10B981")
        case "cancelled": return Color(hex: "EF4444")
        default: return .textSecondary
        }
    }

    private func statusIcon(_ status: String) -> String {
        switch status.lowercased() {
        case "preparing": return "flame.fill"
        case "ready": return "bell.fill"
        case "served", "completed": return "checkmark.circle.fill"
        case "cancelled": return "xmark.circle.fill"
        default: return "bag.fill"
        }
    }

    private func orderTypeName(_ type: String) -> String {
        switch type {
        case "dine_in": return "Dine In"
        case "take_out": return "Take Out"
        case "delivery": return "Delivery"
        default: return type.capitalized
        }
    }

    // MARK: - Charts Subviews

    private var hourlySalesChartCard: some View {
        let currentLabel = selectedPeriod.title(isThai: lm.currentLanguage == .thai)
        let priorLabel = selectedComparison.title(isThai: lm.currentLanguage == .thai)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: hourlyChartMetric == .revenue ? "chart.line.uptrend.xyaxis" : "takeoutbag.and.cup.and.straw.fill")
                    .foregroundColor(.appAccent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(hourlyChartMetric == .revenue ? "dashboard_hourly_sales".t : (lm.currentLanguage == .thai ? "ภาระงานครัว & ออเดอร์รายชั่วโมง" : "Hourly Kitchen Load & Orders"))
                        .font(.headline)
                        .foregroundColor(.textPrimary)
                    if let peak = peakRushHourText {
                        Text(lm.currentLanguage == .thai ? "ช่วงพีคสุด (Rush Hour): \(peak)" : "Peak hour: \(peak)")
                            .font(.caption2.bold())
                            .foregroundColor(.appRose)
                    }
                }
                Spacer()

                Picker("", selection: $hourlyChartMetric) {
                    ForEach(HourlyChartMetric.allCases) { metric in
                        Text(metric.title(isThai: lm.currentLanguage == .thai)).tag(metric)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)

                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.appAccent)
                    .accessibilityLabel(lm.currentLanguage == .thai ? "เปิดกราฟเต็มจอ" : "Open full-screen chart")
            }

            if !hasSalesDataTodayOrYesterday {
                VStack(spacing: 8) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 28))
                        .foregroundColor(.textTertiary)
                    Text("no_activity_yet".t)
                        .font(.caption)
                        .foregroundColor(.textTertiary)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                hourlySalesChart(showEveryHour: false)
                .frame(height: 200)
                .animation(reduceMotion ? nil : .smooth(duration: 0.5), value: chartSalesData)
            }
        }
        .padding(16)
        .apLiquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture { showingHourlySalesFullScreen = true }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(lm.currentLanguage == .thai ? "แตะสองครั้งเพื่อเปิดกราฟเต็มจอและเลื่อนดูรายชั่วโมง" : "Double tap to open a full-screen, horizontally scrollable chart")
    }

    private var hourlySalesFullScreen: some View {
        let currentLabel = selectedPeriod.title(isThai: lm.currentLanguage == .thai)
        let priorLabel = selectedComparison.title(isThai: lm.currentLanguage == .thai)
        return NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label(hourlyChartMetric == .revenue ? "dashboard_hourly_sales".t : (lm.currentLanguage == .thai ? "ภาระงานครัว & ออเดอร์รายชั่วโมง" : "Hourly Kitchen Load & Orders"), systemImage: hourlyChartMetric == .revenue ? "chart.line.uptrend.xyaxis" : "takeoutbag.and.cup.and.straw.fill")
                        .font(.title2.bold())
                        .foregroundColor(.textPrimary)
                    Spacer()
                    Picker("", selection: $hourlyChartMetric) {
                        ForEach(HourlyChartMetric.allCases) { metric in
                            Text(metric.title(isThai: lm.currentLanguage == .thai)).tag(metric)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 250)
                    Text("\(currentLabel) / \(priorLabel)")
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)
                }

                if let peak = peakRushHourText {
                    Text(lm.currentLanguage == .thai ? "ช่วงพีคสุด (Rush Hour): \(peak)" : "Peak hour: \(peak)")
                        .font(.subheadline.bold())
                        .foregroundColor(.appRose)
                }

                Text(lm.currentLanguage == .thai
                     ? "เลื่อนซ้าย–ขวาเพื่อดูเวลาครบทุกชั่วโมง"
                     : "Scroll horizontally to inspect every hour")
                    .font(.caption)
                    .foregroundColor(.textTertiary)

                ScrollView(.horizontal, showsIndicators: true) {
                    hourlySalesChart(showEveryHour: true)
                        .frame(width: 1_560, height: 520)
                        .padding(.horizontal, 4)
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(24)
            .background(Color.appBackground.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingHourlySalesFullScreen = false
                    } label: {
                        Label(lm.currentLanguage == .thai ? "ปิด" : "Close", systemImage: "xmark.circle.fill")
                    }
                }
            }
        }
    }

    private func hourlySalesChart(showEveryHour: Bool) -> some View {
        let currentLabel = selectedPeriod.title(isThai: lm.currentLanguage == .thai)
        let priorLabel = selectedComparison.title(isThai: lm.currentLanguage == .thai)
        let axisValues = Array(stride(from: 0, through: 23, by: showEveryHour ? 1 : 3))
        let isRevenue = hourlyChartMetric == .revenue
        let maxYValue = max(animatedChartSalesData.map { isRevenue ? $0.revenue : Double($0.ordersCount) }.max() ?? 0, 1) * 1.15

        return Chart(animatedChartSalesData) { point in
            let yVal = isRevenue ? max(point.revenue, 0) : Double(point.ordersCount)
            LineMark(
                x: .value("Hour", point.hour),
                y: .value(isRevenue ? "Revenue" : "Orders", yVal.isFinite ? yVal : 0)
            )
            .foregroundStyle(by: .value("Period", point.period))
            .interpolationMethod(.monotone)
            .lineStyle(StrokeStyle(lineWidth: point.period == currentLabel ? 3.0 : 1.5,
                                   dash: point.period == priorLabel ? [4, 4] : []))

            if point.period == currentLabel {
                AreaMark(
                    x: .value("Hour", point.hour),
                    y: .value(isRevenue ? "Revenue" : "Orders", yVal.isFinite ? yVal : 0)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.appAccent.opacity(0.2), Color.appAccent.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.monotone)
            }
        }
        .chartForegroundStyleScale([
            currentLabel: Color.appAccent,
            priorLabel: Color.textSecondary.opacity(0.5)
        ])
        .chartXScale(domain: 0...23)
        .chartXAxis {
            AxisMarks(values: axisValues) { value in
                if let h = value.as(Int.self) {
                    AxisValueLabel(anchor: .top) { Text(String(format: "%02d:00", h)) }
                    AxisTick()
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel(anchor: .trailing) {
                    if let v = value.as(Double.self), v.isFinite {
                        Text(isRevenue ? abbreviatedCurrency(v) : "\(Int(v))")
                    }
                }
            }
        }
        .chartYScale(domain: 0...maxYValue)
        .chartPlotStyle { plot in
            plot.background(Color.appSurfaceHigh.opacity(0.28))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .transaction { transaction in
            // Keep Charts' Canvas out of geometry interpolation. The surrounding
            // dashboard can still animate independently.
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
    }

    private var categoryBreakdownChartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundColor(Color(hex: "10B981"))
                Text("dashboard_sales_by_category".t)
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                Spacer()
            }

            if chartCategoryData.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.textTertiary)
                    Text("no_activity_yet".t)
                        .font(.caption)
                        .foregroundColor(.textTertiary)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                let maxCat = max(animatedChartCategoryData.map(\.revenue).max() ?? 0, 1)
                Chart(animatedChartCategoryData) { point in
                    BarMark(
                        x: .value("Revenue", point.revenue.isFinite ? max(point.revenue, 0) : 0),
                        y: .value("Category", point.categoryName)
                    )
                    .foregroundStyle(by: .value("Category", point.categoryName))
                    .cornerRadius(4)
                    .annotation(position: .trailing, alignment: .leading) {
                        Text("\(currencySymbol)\(point.revenue.formatted(.number.precision(.fractionLength(0))))")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundColor(.textSecondary)
                            .padding(.leading, 4)
                    }
                }
                .chartXScale(domain: 0...(maxCat * 1.12))
                .chartForegroundStyleScale([
                    "dashboard_main_dishes".t: Color(hex: "3B82F6"),
                    "dashboard_appetizers".t: Color(hex: "F59E0B"),
                    "dashboard_beverages".t: Color(hex: "10B981"),
                    "dashboard_desserts".t: Color(hex: "8B5CF6"),
                    "dashboard_specials".t: Color(hex: "EC4899")
                ])
                .chartXAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel(anchor: .top) {
                            if let v = value.as(Double.self), v.isFinite {
                                Text(abbreviatedCurrency(v))
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisValueLabel(anchor: .trailing)
                    }
                }
                .frame(height: 200)
                .transaction { transaction in
                    transaction.animation = nil
                    transaction.disablesAnimations = true
                }
            }
        }
        .padding(16)
        .apLiquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var revenueBridgeChartData: [DashboardFinancialChartPoint] {
        let isThai = lm.currentLanguage == .thai
        return [
            .init(key: "gross", label: isThai ? "ยอดก่อนส่วนลด" : "Gross sales", value: todayGrossSales),
            .init(key: "discount", label: isThai ? "ส่วนลด" : "Discounts", value: todayDiscounts),
            .init(key: "refund", label: isThai ? "คืนเงิน" : "Refunds", value: todayRefunds),
            .init(key: "net", label: isThai ? "ยอดขายสุทธิ" : "Net sales", value: todayRevenue)
        ]
    }

    private var profitCompositionChartData: [DashboardFinancialChartPoint] {
        let isThai = lm.currentLanguage == .thai
        return [
            .init(key: "net", label: isThai ? "ยอดขายสุทธิ" : "Net sales", value: todayRevenue),
            .init(key: "cogs", label: isThai ? "ต้นทุนสินค้า" : "COGS", value: todayCOGS),
            .init(key: "profit", label: isThai ? "กำไรขั้นต้น" : "Gross profit", value: grossProfit)
        ]
    }

    private var revenueBridgeChartCard: some View {
        financialAnimatedChartCard(
            title: lm.currentLanguage == .thai ? "กระทบยอดขายสุทธิ" : "Net sales reconciliation",
            subtitle: lm.currentLanguage == .thai ? "ยอดก่อนส่วนลด − ส่วนลด − คืนเงิน" : "Gross − discounts − refunds",
            icon: "arrow.left.arrow.right.circle.fill",
            tint: Color(hex: "3B82F6"),
            points: revenueBridgeChartData
        )
    }

    private var profitCompositionChartCard: some View {
        financialAnimatedChartCard(
            title: lm.currentLanguage == .thai ? "กำไรและต้นทุนสินค้า" : "Profit and COGS",
            subtitle: lm.currentLanguage == .thai ? "ยอดสุทธิ − COGS = กำไรขั้นต้น" : "Net sales − COGS = gross profit",
            icon: "chart.bar.xaxis",
            tint: Color(hex: "14B8A6"),
            points: profitCompositionChartData
        )
    }

    private func financialAnimatedChartCard(
        title: String, subtitle: String, icon: String, tint: Color,
        points: [DashboardFinancialChartPoint]
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon).foregroundColor(tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).foregroundColor(.textPrimary)
                    Text(subtitle).font(.caption2).foregroundColor(.textTertiary)
                }
                Spacer()
            }

            let animatedPoints = points.map {
                DashboardFinancialChartPoint(key: $0.key, label: $0.label, value: $0.value * chartAnimationProgress)
            }
            let maxVal = max(animatedPoints.map(\.value).max() ?? 0, 1)
            Chart(animatedPoints) { point in
                BarMark(
                    x: .value("Amount", point.value.isFinite ? max(point.value, 0) : 0),
                    y: .value("Metric", point.label)
                )
                .foregroundStyle(financialChartColor(point.key))
                .cornerRadius(5)
                .annotation(position: .trailing, alignment: .leading) {
                    Text(dashboardMoney(point.value))
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(.textSecondary)
                        .padding(.leading, 4)
                }
            }
            .chartXScale(domain: 0...(maxVal * 1.12))
            .chartXAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel(anchor: .top) {
                        if let amount = value.as(Double.self), amount.isFinite { Text(abbreviatedCurrency(amount)) }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let label = value.as(String.self) {
                            Text(label)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .frame(width: 88, alignment: .trailing)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 200, maxHeight: 200)
            .clipped()
            .transaction { transaction in
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.8), value: chartAnimationProgress)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .apLiquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func financialChartColor(_ key: String) -> Color {
        switch key {
        case "gross": return Color(hex: "3B82F6")
        case "discount": return Color(hex: "F59E0B")
        case "refund": return Color(hex: "EF4444")
        case "cogs": return Color(hex: "8B5CF6")
        case "profit": return Color(hex: "14B8A6")
        default: return Color(hex: "10B981")
        }
    }

    private func abbreviatedCurrency(_ value: Double) -> String {
        if value >= 1000000 {
            return String(format: "%.1fM", value / 1000000)
        }
        if value >= 1000 {
            return String(format: "%.0fK", value / 1000)
        }
        return String(format: "%.0f", value)
    }

    // MARK: - PDF Export

    private func beginDashboardExport() {
        guard !isExportingPDF else { return }
        APHaptic.trigger()
        withAnimation(.easeOut(duration: 0.16)) { isExportingPDF = true }
        Task { @MainActor in
            // Let SwiftUI present the progress state before ImageRenderer starts.
            try? await Task.sleep(for: .milliseconds(80))
            if let url = makeDashboardPDF() {
                generatedPDFURL = url
                isExportingPDF = false
                showingShareSheet = true
            } else {
                isExportingPDF = false
                showExportError = true
            }
        }
    }

    @MainActor
    private func makeDashboardPDF() -> URL? {
        let storeName = UserDefaults.standard.string(forKey: "store_name") ?? "AlphaPos"
        let summary = DashboardSummaryPDFView(
            storeName: storeName,
            dateLabel: currentTime.formatted(date: .long, time: .shortened),
            currencySymbol: currencySymbol,
            grossSales: todayGrossSales,
            discounts: todayDiscounts,
            refunds: todayRefunds,
            netRevenue: todayRevenue,
            vatCollected: todayVATCollected,
            serviceCharge: todayServiceCharge,
            orderCount: completedTodayOrders.count,
            avgOrderValue: avgOrderValue,
            totalGuests: totalGuests,
            activeOrderCount: activeOrders.count,
            tableOccupancy: tableOccupancy,
            averagePrepMinutes: avgPrepTime,
            staffOnDutyCount: staffOnDuty.count,
            lowStockCount: lowStockItems.count,
            yesterdayRevenue: yesterdayRevenue,
            paymentMix: todaySettlementMix.map { ($0.method, $0.amount, $0.count) },
            storefrontTopItems: topStorefrontItems.map { ($0.name, $0.quantity, $0.revenue) },
            deliveryTopItems: topDeliveryItems.map { ($0.name, $0.quantity, $0.revenue) }
        )

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AlphaPos_Dashboard_\(currentTime.formatted(.iso8601.year().month().day())).pdf")
        var box = CGRect(x: 0, y: 0, width: 595, height: 842) // ISO A4 portrait
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { return nil }
        ctx.beginPDFPage(nil)
        let renderer = ImageRenderer(content: summary.frame(width: 547))
        renderer.scale = 1.0
        renderer.render { size, render in
            let scale = min(box.width / size.width, box.height / size.height)
            ctx.translateBy(x: (box.width - size.width * scale) / 2, y: (box.height - size.height * scale) / 2)
            ctx.scaleBy(x: scale, y: scale)
            render(ctx)
        }
        ctx.endPDFPage()
        ctx.closePDF()
        return url
    }
}

// MARK: - Animated Financial Cloud Hero

private struct AnimatedFinancialClouds: View {
    @Environment(\.colorScheme) private var colorScheme
    let reduceMotion: Bool

    var body: some View {
        Group {
            if reduceMotion {
                cloudScene(time: 0)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
                    cloudScene(time: timeline.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .background(
            colorScheme == .dark
                ? AnyShapeStyle(LinearGradient(colors: [Color(hex: "07131F"), Color(hex: "0A3040"), Color(hex: "101E34")], startPoint: .topLeading, endPoint: .bottomTrailing))
                : AnyShapeStyle(Color.white)
        )
    }

    private func cloudScene(time: TimeInterval) -> some View {
        Canvas { context, size in
            let palette = colorScheme == .dark
                ? [Color(hex: "46D7F0"), Color(hex: "7868F2"), Color(hex: "36D39A")]
                : [Color(hex: "A9EAF4"), Color(hex: "CFC8FF"), Color(hex: "BDEEDC")]

            for index in 0..<7 {
                let duration = 12.0 + Double(index % 3) * 3.0
                let progress = CGFloat((time / duration + Double(index) * 0.19).truncatingRemainder(dividingBy: 1))
                let x = size.width * (0.34 + CGFloat(index % 5) * 0.14)
                let y = size.height * (1.18 - progress * 1.5)
                let width = size.width * (0.12 + CGFloat(index % 3) * 0.025)
                let height = width * 0.34
                let cloud = Path(roundedRect: CGRect(x: x - width / 2, y: y - height / 2, width: width, height: height), cornerRadius: height / 2)

                context.drawLayer { layer in
                    layer.addFilter(.blur(radius: 14 + CGFloat(index % 3) * 4))
                    layer.fill(cloud, with: .color(palette[index % palette.count].opacity(colorScheme == .dark ? 0.16 : 0.22)))

                    let crown = Path(ellipseIn: CGRect(x: x - width * 0.22, y: y - height * 0.92, width: width * 0.44, height: height * 1.1))
                    layer.fill(crown, with: .color(palette[index % palette.count].opacity(colorScheme == .dark ? 0.14 : 0.18)))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Dashboard Summary PDF Content

/// Printable executive summary of today's dashboard — white background,
/// mirrors the on-screen financial bridge, payment mix, and top items.
private struct DashboardSummaryPDFView: View {
    let storeName: String
    let dateLabel: String
    let currencySymbol: String
    let grossSales: Double
    let discounts: Double
    let refunds: Double
    let netRevenue: Double
    let vatCollected: Double
    let serviceCharge: Double
    let orderCount: Int
    let avgOrderValue: Double
    let totalGuests: Int
    let activeOrderCount: Int
    let tableOccupancy: Int
    let averagePrepMinutes: Int
    let staffOnDutyCount: Int
    let lowStockCount: Int
    let yesterdayRevenue: Double
    let paymentMix: [(method: String, amount: Double, count: Int)]
    let storefrontTopItems: [(name: String, quantity: Int, revenue: Double)]
    let deliveryTopItems: [(name: String, quantity: Int, revenue: Double)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Branded report header
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(storeName).font(.system(size: 21, weight: .bold))
                    Text("EXECUTIVE DAILY PERFORMANCE REPORT")
                        .font(.system(size: 9, weight: .bold)).tracking(1.1)
                    Text(dateLabel).font(.system(size: 9))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("AlphaPos").font(.system(size: 12, weight: .bold))
                    Text("LIVE OPERATIONS & SALES").font(.system(size: 8, weight: .semibold))
                    Text("Generated securely on device").font(.system(size: 7))
                }
            }
            .foregroundColor(.white)
            .padding(14)
            .background(LinearGradient(colors: [Color(hex: "123A66"), Color(hex: "126E82")], startPoint: .leading, endPoint: .trailing))
            .cornerRadius(10)
            Divider()

            // KPI strip
            HStack(spacing: 10) {
                pdfKPI("Net Revenue", money(netRevenue))
                pdfKPI("Orders", "\(orderCount)")
                pdfKPI("Avg Order", money(avgOrderValue))
                pdfKPI("Guests", "\(totalGuests)")
            }

            sectionTitle("OPERATIONS SNAPSHOT")
            HStack(spacing: 8) {
                pdfKPI("Active Orders", "\(activeOrderCount)")
                pdfKPI("Table Occupancy", "\(tableOccupancy)%")
                pdfKPI("Avg Prep", averagePrepMinutes > 0 ? "\(averagePrepMinutes) min" : "—")
                pdfKPI("Staff on Duty", "\(staffOnDutyCount)")
                pdfKPI("Low Stock", "\(lowStockCount)")
            }

            // Financial bridge
            sectionTitle("FINANCIAL SUMMARY")
            VStack(spacing: 4) {
                pdfRow("Gross Sales", money(grossSales))
                pdfRow("Discounts", "−" + money(discounts))
                pdfRow("Refunds", "−" + money(refunds))
                Divider()
                pdfRow("Net Revenue", money(netRevenue), bold: true)
                pdfRow("VAT Collected", money(vatCollected))
                pdfRow("Service Charge", money(serviceCharge))
            }

            if !paymentMix.isEmpty {
                sectionTitle("PAYMENT METHODS")
                VStack(spacing: 4) {
                    ForEach(Array(paymentMix.enumerated()), id: \.offset) { _, entry in
                        pdfRow("\(entry.method) (×\(entry.count))", money(entry.amount))
                    }
                }
            }

            sectionTitle("PERFORMANCE CONTEXT")
            VStack(spacing: 4) {
                pdfRow("Yesterday Revenue", money(yesterdayRevenue))
                pdfRow("Revenue Change", revenueChangeLabel)
                pdfRow("Revenue per Guest", totalGuests > 0 ? money(netRevenue / Double(totalGuests)) : "—")
            }

            if !storefrontTopItems.isEmpty {
                sectionTitle("TOP-SELLING MAIN ITEMS — STOREFRONT")
                VStack(spacing: 4) {
                    ForEach(Array(storefrontTopItems.prefix(8).enumerated()), id: \.offset) { index, item in
                        pdfTopItemRow(index: index, item: item)
                    }
                }
            }

            if !deliveryTopItems.isEmpty {
                sectionTitle("TOP-SELLING MAIN ITEMS — DELIVERY")
                VStack(spacing: 4) {
                    ForEach(Array(deliveryTopItems.prefix(8).enumerated()), id: \.offset) { index, item in
                        pdfTopItemRow(index: index, item: item)
                    }
                }
            }

            Spacer(minLength: 8)
            Divider()
            Text("dashboard_generated_by".t + " • \(dateLabel)")
                .font(.system(size: 8))
                .foregroundColor(.gray)
            Text("Internal management report • Values reflect recognized sales and completed payments available on this device at generation time.")
                .font(.system(size: 7))
                .foregroundColor(.gray)
        }
        .padding(24)
        .background(Color.white)
        .foregroundColor(.black)
    }

    private func money(_ value: Double) -> String {
        "\(currencySymbol)\(value.formatted(.number.precision(.fractionLength(2))))"
    }

    private func pdfTopItemRow(
        index: Int,
        item: (name: String, quantity: Int, revenue: Double)
    ) -> some View {
        HStack {
            Text("#\(index + 1)")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.gray)
                .frame(width: 22, alignment: .leading)
            Text(item.name).font(.system(size: 10))
            Spacer()
            Text("×\(item.quantity)")
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 40, alignment: .trailing)
            Text(money(item.revenue))
                .font(.system(size: 10, design: .monospaced))
                .frame(width: 80, alignment: .trailing)
        }
    }

    private var revenueChangeLabel: String {
        guard yesterdayRevenue > 0 else { return "No comparable prior-day revenue" }
        let percent = ((netRevenue - yesterdayRevenue) / yesterdayRevenue) * 100
        return String(format: "%+.1f%%", percent)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(.gray)
            .tracking(1.0)
            .padding(.top, 4)
    }

    private func pdfKPI(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 8)).foregroundColor(.gray)
            Text(value).font(.system(size: 13, weight: .bold))
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(white: 0.96))
        .cornerRadius(6)
    }

    private func pdfRow(_ label: String, _ value: String, bold: Bool = false) -> some View {
        HStack {
            Text(label).font(.system(size: 10, weight: bold ? .bold : .regular))
            Spacer()
            Text(value).font(.system(size: 10, weight: bold ? .bold : .regular, design: .monospaced))
        }
    }
}

// MARK: - Staggered Appear Animation

private struct DashboardAppearModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let delay: Double
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 16)
            .onAppear {
                if reduceMotion || UIDevice.current.userInterfaceIdiom == .pad { shown = true }
                else {
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.85).delay(delay)) { shown = true }
                }
            }
    }
}

private extension View {
    /// Fade-and-rise entrance used to stagger dashboard sections.
    func dashboardAppear(_ delay: Double) -> some View {
        modifier(DashboardAppearModifier(delay: delay))
    }
}

// MARK: - KPI Card Component

private struct SimpleDashboardCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let value: String
    let detail: String
    let icon: String
    let color: Color
    var isPrimary = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: isPrimary ? 24 : 20, weight: .semibold))
                .foregroundColor(color)
                .frame(width: isPrimary ? 50 : 44, height: isPrimary ? 50 : 44)
                .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 13, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.textSecondary)
                    .lineLimit(1)
                Text(value)
                    .font(.system(size: isPrimary ? 27 : 23, weight: .bold, design: .rounded))
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .contentTransition(.numericText())
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: isPrimary ? 112 : 104, alignment: .leading)
        .background(
            LinearGradient(
                colors: [color.opacity(colorScheme == .dark ? 0.13 : 0.08), Color.appSurface],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(color.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: color.opacity(colorScheme == .dark ? 0.08 : 0.06), radius: 8, x: 0, y: 3)
    }
}

private struct DashboardBreakdownCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let value: String
    let detail: String
    let icon: String
    let color: Color
    var badge: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        let cardBody = HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 38, height: 38)
                .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(.textSecondary)
                        .lineLimit(1)
                    
                    if let badge = badge {
                        Text(badge)
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundColor(color)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(color.opacity(0.14))
                            .clipShape(Capsule())
                    }
                }
                
                Text(value)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
                
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundColor(.textSecondary)
                    .lineLimit(1)
            }
            
            Spacer(minLength: 0)
            
            if action != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.textSecondary.opacity(0.7))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 240, height: 96, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.appSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.appBorderSubtle, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.04), radius: 5, x: 0, y: 2)

        Group {
            if let action = action {
                Button(action: action) {
                    cardBody
                }
                .buttonStyle(.plain)
            } else {
                cardBody
            }
        }
    }
}

private struct KPICard: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let value: String
    let icon: String
    let color: Color
    let trend: String?
    var subtitle: String? = nil
    var trendIsFavorable: Bool? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(color)
                Spacer()
                if let trend = trend {
                    Text(trend)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(trendColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            trendColor.opacity(0.12)
                        )
                        .cornerRadius(4)
                }
            }

            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.5), value: value)

            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.textSecondary)
                .lineLimit(1)

            Text(subtitle ?? " ")
                .font(.system(size: 10))
                .foregroundColor(subtitle != nil ? .textSecondary : .clear)
                .lineLimit(1)
        }
        .padding(14)
        .frame(minHeight: 104, maxHeight: 104, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.appSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(color.opacity(0.05))
                )
        )
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(color.opacity(0.22), lineWidth: 1))
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.28 : 0.04), radius: 5, x: 0, y: 2)
    }

    private var trendColor: Color {
        guard let trendIsFavorable else { return .textSecondary }
        return trendIsFavorable ? .appTeal : .appRose
    }
}

// MARK: - Secondary KPI Card

private struct SecondaryKPICard: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let value: String
    var amount: String? = nil
    let icon: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.appAccent)
                .frame(width: 34, height: 34)
                .background(Color.appAccent.opacity(0.12))
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(value)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.textPrimary)
                    if let amount = amount, !amount.isEmpty {
                        Text(amount)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.appTeal)
                    }
                }
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.appSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.appAccent.opacity(0.04))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.appBorderSubtle, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.25 : 0.03), radius: 4, x: 0, y: 1.5)
    }
}

extension LiveDashboardView {
    private var lowStockItems: [InventoryItem] {
        branchInventoryItems.filter { item in
            // Align with the Inventory module & Reports definition of low stock
            // (qty at or below the reorder level). Previously this used
            // safetyStockLevel, so the dashboard banner disagreed with the
            // inventory list and the inventory report counts.
            !item.isDeleted && item.currentQuantity <= item.reorderLevel
        }
    }

    private var lowStockWarningBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .font(.title3)
                Text("low_stock_alert".t)
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                Spacer()
                Button {
                    showingQuickPOSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "cart.badge.plus")
                        Text(lm.currentLanguage == .thai ? "สร้างใบสั่งซื้อด่วน (Quick PO)" : "Create Quick PO")
                    }
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.appAccent)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)

                Text(LocalizationManager.shared.t("items_count_template", lowStockItems.count))
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.2))
                    .foregroundColor(.red)
                    .cornerRadius(8)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(lowStockItems.prefix(10)) { item in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.textPrimary)
                                Text(LocalizationManager.shared.t("dashboard_stock_remaining", String(format: "%.1f", item.currentQuantity), String(format: "%.1f", item.reorderLevel)))
                                    .font(.system(size: 11))
                                    .foregroundColor(.textSecondary)
                            }
                            Image(systemName: item.currentQuantity <= 0 ? "xmark.circle.fill" : "exclamationmark.circle.fill")
                                .foregroundColor(item.currentQuantity <= 0 ? .red : .orange)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.appSurfaceHigh)
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(item.currentQuantity <= 0 ? Color.red.opacity(0.3) : Color.orange.opacity(0.3), lineWidth: 1)
                        )
                    }
                }
            }
        }
        .padding()
        .background(Color.red.opacity(0.06))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.red.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Chart Data Models

private struct DashboardHourlySalesPoint: Identifiable, Equatable {
    var id: String { "\(period):\(hour)" }
    let hour: Int
    let revenue: Double
    var ordersCount: Int = 0
    var itemsCount: Int = 0
    let period: String
}

private enum DashboardViewMode: String, CaseIterable, Identifiable {
    case all, operations, executive
    var id: String { rawValue }

    func title(isThai: Bool) -> String {
        switch self {
        case .all: return isThai ? "ทั้งหมด" : "All"
        case .operations: return isThai ? "ปฏิบัติการ/แคชเชียร์" : "Operations"
        case .executive: return isThai ? "ผู้บริหาร/เจ้าของ" : "Executive"
        }
    }

    var icon: String {
        switch self {
        case .all: return "square.grid.2x2.fill"
        case .operations: return "checklist.checked"
        case .executive: return "chart.pie.fill"
        }
    }
}

private enum HourlyChartMetric: String, CaseIterable, Identifiable {
    case revenue, orders
    var id: String { rawValue }

    func title(isThai: Bool) -> String {
        switch self {
        case .revenue: return isThai ? "ยอดขาย (฿)" : "Revenue (฿)"
        case .orders: return isThai ? "ออเดอร์/จาน" : "Orders & Dishes"
        }
    }
}

private struct DashboardCategorySalesPoint: Identifiable, Equatable {
    var id: String { categoryName }
    let categoryName: String
    let revenue: Double
}

private struct DashboardFinancialChartPoint: Identifiable, Equatable {
    var id: String { key }
    let key: String
    let label: String
    let value: Double
}

private enum DashboardPeriod: String, CaseIterable, Identifiable {
    case currentShift, historicalShift, businessDay, calendarToday, yesterday, sevenDays, thisMonth
    var id: String { rawValue }

    func title(isThai: Bool) -> String {
        switch self {
        case .currentShift: return isThai ? "กะปัจจุบัน" : "Current shift"
        case .historicalShift: return isThai ? "กะย้อนหลัง" : "Historical shift"
        case .businessDay: return isThai ? "วันทำการปัจจุบัน" : "Current business day"
        case .calendarToday: return isThai ? "วันปฏิทินวันนี้" : "Calendar today"
        case .yesterday: return isThai ? "เมื่อวาน" : "Yesterday"
        case .sevenDays: return isThai ? "7 วันล่าสุด" : "Last 7 days"
        case .thisMonth: return isThai ? "เดือนนี้" : "This month"
        }
    }

    func interval(containing date: Date, calendar: Calendar) -> DateInterval {
        let today = calendar.startOfDay(for: date)
        switch self {
        case .currentShift, .historicalShift, .businessDay, .calendarToday:
            return DateInterval(start: today, end: calendar.date(byAdding: .day, value: 1, to: today)!)
        case .yesterday:
            let start = calendar.date(byAdding: .day, value: -1, to: today)!
            return DateInterval(start: start, end: today)
        case .sevenDays:
            let start = calendar.date(byAdding: .day, value: -6, to: today)!
            return DateInterval(start: start, end: calendar.date(byAdding: .day, value: 1, to: today)!)
        case .thisMonth:
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: date))!
            return DateInterval(start: start, end: calendar.date(byAdding: .month, value: 1, to: start)!)
        }
    }

    var usesRegisterSession: Bool { self == .currentShift || self == .historicalShift }

    func businessInterval(containing date: Date, cutoffHour: Int, timeZoneID: String) -> DateInterval {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneID) ?? .current
        let shifted = calendar.date(byAdding: .hour, value: -min(max(cutoffHour, 0), 23), to: date) ?? date
        let shiftedDay = calendar.startOfDay(for: shifted)
        let start = calendar.date(byAdding: .hour, value: min(max(cutoffHour, 0), 23), to: shiftedDay)!
        return DateInterval(start: start, end: calendar.date(byAdding: .day, value: 1, to: start)!)
    }
}

private enum DashboardComparison: String, CaseIterable, Identifiable {
    case previousPeriod, previousWeek
    var id: String { rawValue }

    func title(isThai: Bool) -> String {
        switch self {
        case .previousPeriod: return isThai ? "เทียบเมื่อวาน" : "Yesterday"
        case .previousWeek: return isThai ? "เทียบสัปดาห์ก่อน (7 วัน)" : "Previous week"
        }
    }

    func subtitle(isThai: Bool) -> String {
        isThai ? "\(title(isThai: true)) · ฐานเวลาเดียวกัน" : "vs \(title(isThai: false).lowercased())"
    }

    func interval(before current: DateInterval, calendar: Calendar) -> DateInterval {
        switch self {
        case .previousPeriod:
            return DateInterval(start: current.start.addingTimeInterval(-current.duration), end: current.start)
        case .previousWeek:
            return DateInterval(start: calendar.date(byAdding: .day, value: -7, to: current.start)!, end: calendar.date(byAdding: .day, value: -7, to: current.end)!)
        }
    }
}

private enum DashboardSalesChannel: String, CaseIterable, Identifiable {
    case all, storefront, quickService, dineIn, takeOut, delivery, online
    var id: String { rawValue }
    func title(isThai: Bool) -> String {
        switch self {
        case .all: return isThai ? "ทุกช่องทางขาย" : "All channels"
        case .storefront: return isThai ? "หน้าร้าน" : "Storefront"
        case .quickService: return isThai ? "Quick Service" : "Quick Service"
        case .dineIn: return isThai ? "ทานที่ร้าน" : "Dine-in"
        case .takeOut: return isThai ? "สั่งกลับบ้าน" : "Takeaway"
        case .delivery: return "Delivery"
        case .online: return "Online"
        }
    }
    func matches(_ order: Order) -> Bool {
        switch self {
        case .all: return true
        case .storefront: return order.orderType == "dine_in" && !order.isQuickServiceOrder
        case .quickService: return order.isQuickServiceOrder
        case .dineIn: return order.orderType == "dine_in" && !order.isQuickServiceOrder
        case .takeOut: return order.orderType == "take_out"
        case .delivery: return order.orderType == "delivery"
        case .online: return order.orderSource == "web"
        }
    }
}

private struct DashboardChannelSummary: Identifiable {
    enum Kind: String, CaseIterable, Identifiable {
        case storefront, quickService, delivery, online, marketplace
        var id: String { rawValue }
        func title(isThai: Bool) -> String {
            switch self {
            case .storefront: return isThai ? "หน้าร้าน" : "Storefront"
            case .quickService: return isThai ? "Quick Service" : "Quick Service"
            case .delivery: return "Delivery"
            case .online: return "Online"
            case .marketplace: return "Marketplace"
            }
        }
        var icon: String {
            switch self {
            case .storefront: return "storefront.fill"
            case .quickService: return "takeoutbag.and.cup.and.straw.fill"
            case .delivery: return "scooter"
            case .online: return "globe"
            case .marketplace: return "square.grid.2x2.fill"
            }
        }
        var color: Color {
            switch self {
            case .storefront: return .appAccent
            case .quickService: return .appAmber
            case .delivery: return .appTeal
            case .online: return Color(hex: "8B5CF6")
            case .marketplace: return Color(hex: "F59E0B")
            }
        }
    }
    let kind: Kind
    let orders: Int
    let mainItems: Int
    let addOnItems: Int
    let addOnSales: Double
    let gross: Double
    let fees: Double
    var id: String { kind.rawValue }
    var averageTicket: Double { orders > 0 ? gross / Double(orders) : 0 }
    var net: Double { gross - fees }
}

private struct DashboardDeliveryPlatform: Identifiable {
    var id: String { brand }
    let brand: String
    let orders: [Order]
    let gross: Double
    let gpFees: Double
    let adFees: Double
    let otherFees: Double
    let net: Double

    var totalFees: Double { gpFees + adFees + otherFees }
    var effectiveFeeRate: Double { gross > 0 ? totalFees / gross * 100 : 0 }
    var netMargin: Double { gross > 0 ? net / gross * 100 : 0 }
    var color: Color {
        switch brand.lowercased() {
        case let value where value.contains("grab"): return Color(hex: "00B14F")
        case let value where value.contains("line"): return Color(hex: "06C755")
        case let value where value.contains("shopee"): return Color(hex: "EE4D2D")
        case let value where value.contains("panda"): return Color(hex: "D70F64")
        case let value where value.contains("robin"): return Color(hex: "7B2CBF")
        default: return Color.appAccent
        }
    }

    func payoutSchedule(isThai: Bool) -> String {
        let lower = brand.lowercased()
        if lower.contains("grab") || lower.contains("shopee") || lower.contains("robin") {
            return isThai ? "โอนรายวัน (T+1)" : "Daily (T+1)"
        }
        if lower.contains("line") {
            return isThai ? "รอบสัปดาห์ / T+2" : "Weekly / T+2"
        }
        if lower.contains("panda") {
            return isThai ? "รอบ 2 สัปดาห์" : "Bi-weekly"
        }
        return isThai ? "ตามรอบคู่ค้า" : "Partner cycle"
    }
}

private struct DashboardException: Identifiable {
    enum Kind { case critical, warning, info }
    let id = UUID()
    let kind: Kind
    let titleTH: String
    let titleEN: String
    let detailTH: String
    let detailEN: String
    let count: Int
    let amount: Double
    let orders: [Order]

    func title(isThai: Bool) -> String { isThai ? titleTH : titleEN }
    func detail(isThai: Bool) -> String { isThai ? detailTH : detailEN }
    var icon: String {
        switch kind {
        case .critical: return "xmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }
    var color: Color {
        switch kind {
        case .critical: return .appRose
        case .warning: return .appAmber
        case .info: return .appAccent
        }
    }
}

// MARK: - Delivery Order Quick Edit Sheet

private struct DeliveryOrderQuickEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var lm: LocalizationManager
    let order: Order
    let onSave: () -> Void

    @State private var platformOrderNumber: String
    @State private var deliveryBrand: String
    @State private var deliveryGP: Double
    @State private var deliveryAdFee: Double
    @State private var deliveryAdFeeIsPct: Bool
    @State private var deliveryOtherFee: Double

    init(order: Order, onSave: @escaping () -> Void) {
        self.order = order
        self.onSave = onSave
        _platformOrderNumber = State(initialValue: order.platformOrderNumber ?? "")
        _deliveryBrand = State(initialValue: order.deliveryBrand ?? "GrabFood")
        _deliveryGP = State(initialValue: order.deliveryGP)
        _deliveryAdFee = State(initialValue: order.deliveryAdFee)
        _deliveryAdFeeIsPct = State(initialValue: order.deliveryAdFeeIsPct)
        _deliveryOtherFee = State(initialValue: order.deliveryOtherFee)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(lm.currentLanguage == .thai ? "ข้อมูลอ้างอิงออเดอร์" : "Order References")) {
                    LabeledContent(lm.currentLanguage == .thai ? "เลขออเดอร์ POS" : "POS Order #", value: "#\(order.orderNumber)")
                    LabeledContent(lm.currentLanguage == .thai ? "เวลาที่บันทึก" : "Created At", value: order.createdAt.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent(lm.currentLanguage == .thai ? "ยอดรวม" : "Order Total", value: "฿\(order.total.formatted(.number.precision(.fractionLength(2))))")
                }

                Section(header: Text(lm.currentLanguage == .thai ? "ข้อมูลแพลตฟอร์มเดลิเวอรี" : "Delivery Platform Details")) {
                    Picker(lm.currentLanguage == .thai ? "แพลตฟอร์ม" : "Platform", selection: $deliveryBrand) {
                        ForEach(ExternalSalesChannel.all, id: \.self) { brand in
                            Text(brand).tag(brand)
                        }
                    }
                    .onChange(of: deliveryBrand) { _, newBrand in
                        platformOrderNumber = PlatformOrderNumber.rebrand(platformOrderNumber, to: newBrand)
                    }

                    HStack {
                        Text(lm.currentLanguage == .thai ? "เลขออเดอร์เดลิเวอรี" : "Platform Order #")
                        Spacer()
                        TextField("#12345 / GF-123", text: $platformOrderNumber)
                            .multilineTextAlignment(.trailing)
                            .font(.system(.body, design: .monospaced))
                    }
                }

                Section(header: Text(lm.currentLanguage == .thai ? "ค่าธรรมเนียมและส่วนแบ่ง (GP/Fees)" : "Fees & Commission (GP)")) {
                    HStack {
                        Text("GP (%)")
                        Spacer()
                        TextField("0.0", value: $deliveryGP, format: .number.precision(.fractionLength(1)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    HStack {
                        Text(lm.currentLanguage == .thai ? "ค่าโฆษณา (Ad Fee)" : "Ad Fee")
                        Spacer()
                        TextField("0.0", value: $deliveryAdFee, format: .number.precision(.fractionLength(2)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    HStack {
                        Text(lm.currentLanguage == .thai ? "ค่าใช้จ่ายอื่น" : "Other Fee")
                        Spacer()
                        TextField("0.0", value: $deliveryOtherFee, format: .number.precision(.fractionLength(2)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                }
            }
            .navigationTitle(lm.currentLanguage == .thai ? "แก้ไขข้อมูลเดลิเวอรี" : "Edit Delivery Order")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(lm.currentLanguage == .thai ? "ยกเลิก" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(lm.currentLanguage == .thai ? "บันทึก" : "Save") {
                        saveChanges()
                    }
                    .fontWeight(.bold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func saveChanges() {
        order.deliveryBrand = deliveryBrand
        let normalized = PlatformOrderNumber.applyBrandPrefix(platformOrderNumber, brand: deliveryBrand)
        order.platformOrderNumber = normalized.isEmpty ? nil : normalized
        order.deliveryGP = deliveryGP
        order.deliveryAdFee = deliveryAdFee
        order.deliveryAdFeeIsPct = deliveryAdFeeIsPct
        order.deliveryOtherFee = deliveryOtherFee
        order.isSynced = false
        order.updatedAt = Date()
        try? modelContext.save()
        onSave()
        dismiss()
    }
}

// MARK: - Quick PO Generator Sheet

private struct QuickPOGeneratorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var lm: LocalizationManager
    let lowStockItems: [InventoryItem]
    let branch: Branch?
    let onCreated: () -> Void

    @State private var quantities: [UUID: Double] = [:]
    @State private var notes = "สั่งซื้อด่วนจากระบบแจ้งเตือนสต็อกต่ำ Live Dashboard"

    init(lowStockItems: [InventoryItem], branch: Branch?, onCreated: @escaping () -> Void) {
        self.lowStockItems = lowStockItems
        self.branch = branch
        self.onCreated = onCreated
        var initialQty: [UUID: Double] = [:]
        for item in lowStockItems {
            let suggested = max(1.0, (item.reorderLevel * 2.0) - item.currentQuantity)
            initialQty[item.id] = (suggested * 10).rounded() / 10
        }
        _quantities = State(initialValue: initialQty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(lm.currentLanguage == .thai ? "รายการสินค้าสต็อกต่ำที่แนะนำให้สั่งซื้อ" : "Recommended Low Stock Items")) {
                    ForEach(lowStockItems) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.name).fontWeight(.semibold)
                                Text(lm.currentLanguage == .thai ? "คงเหลือ: \(item.currentQuantity.formatted()) (เกณฑ์: \(item.reorderLevel.formatted()))" : "In stock: \(item.currentQuantity.formatted()) (Min: \(item.reorderLevel.formatted()))")
                                    .font(.caption)
                                    .foregroundColor(.textSecondary)
                            }
                            Spacer()
                            HStack(spacing: 4) {
                                TextField("0", value: Binding(
                                    get: { quantities[item.id] ?? 1.0 },
                                    set: { quantities[item.id] = max(0, $0) }
                                ), format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 65)
                                .textFieldStyle(.roundedBorder)

                                Text(item.unit)
                                    .font(.caption)
                                    .foregroundColor(.textTertiary)
                            }
                        }
                    }
                }

                Section(header: Text(lm.currentLanguage == .thai ? "หมายเหตุใบสั่งซื้อ" : "PO Notes")) {
                    TextField(lm.currentLanguage == .thai ? "ระบุหมายเหตุ..." : "Enter notes...", text: $notes)
                }
            }
            .navigationTitle(lm.currentLanguage == .thai ? "สร้างใบสั่งซื้อด่วน (Quick PO)" : "Create Quick PO")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(lm.currentLanguage == .thai ? "ยกเลิก" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(lm.currentLanguage == .thai ? "สร้าง PO ฉบับร่าง" : "Create Draft PO") {
                        createPO()
                    }
                    .fontWeight(.bold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func createPO() {
        guard let branch = branch else { dismiss(); return }
        let now = Date()
        let poNumber = "PO-QUICK-\(now.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits)).replacingOccurrences(of: "/", with: ""))-\(String(format: "%04d", Int.random(in: 1000...9999)))"
        let po = PurchaseOrder(
            poNumber: poNumber,
            supplier: lowStockItems.first?.supplier,
            branch: branch,
            status: "draft",
            orderDate: now,
            notes: notes,
            isSynced: false,
            updatedAt: now
        )
        modelContext.insert(po)
        for item in lowStockItems {
            let qty = quantities[item.id] ?? 1.0
            guard qty > 0 else { continue }
            let poItem = PurchaseOrderItem(
                purchaseOrder: po,
                inventoryItem: item,
                quantityOrdered: qty,
                unitCost: item.costPrice,
                isSynced: false,
                updatedAt: now
            )
            modelContext.insert(poItem)
            po.items.append(poItem)
        }
        try? modelContext.save()
        onCreated()
        dismiss()
    }
}

// MARK: - Add-on Itemized Breakdown Sheet

private struct AddOnBreakdownSheet: View {
    let allAddOns: [LiveDashboardView.DashboardAddOnDetail]
    let allRevenue: Double
    let allQuantity: Int
    let storefrontAddOns: [LiveDashboardView.DashboardAddOnDetail]
    let storefrontRevenue: Double
    let storefrontQuantity: Int
    let deliveryAddOns: [LiveDashboardView.DashboardAddOnDetail]
    let deliveryRevenue: Double
    let deliveryQuantity: Int
    let currencySymbol: String
    let isThai: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedChannel: DashboardSalesChannel
    @State private var searchText = ""

    init(
        initialChannel: DashboardSalesChannel = .all,
        allAddOns: [LiveDashboardView.DashboardAddOnDetail],
        allRevenue: Double,
        allQuantity: Int,
        storefrontAddOns: [LiveDashboardView.DashboardAddOnDetail],
        storefrontRevenue: Double,
        storefrontQuantity: Int,
        deliveryAddOns: [LiveDashboardView.DashboardAddOnDetail],
        deliveryRevenue: Double,
        deliveryQuantity: Int,
        currencySymbol: String,
        isThai: Bool
    ) {
        self._selectedChannel = State(initialValue: initialChannel)
        self.allAddOns = allAddOns
        self.allRevenue = allRevenue
        self.allQuantity = allQuantity
        self.storefrontAddOns = storefrontAddOns
        self.storefrontRevenue = storefrontRevenue
        self.storefrontQuantity = storefrontQuantity
        self.deliveryAddOns = deliveryAddOns
        self.deliveryRevenue = deliveryRevenue
        self.deliveryQuantity = deliveryQuantity
        self.currencySymbol = currencySymbol
        self.isThai = isThai
    }

    private var activeAddOns: [LiveDashboardView.DashboardAddOnDetail] {
        switch selectedChannel {
        case .all: return allAddOns
        case .storefront: return storefrontAddOns
        case .delivery: return deliveryAddOns
        default: return allAddOns
        }
    }

    private var activeRevenue: Double {
        switch selectedChannel {
        case .all: return allRevenue
        case .storefront: return storefrontRevenue
        case .delivery: return deliveryRevenue
        default: return allRevenue
        }
    }

    private var activeQuantity: Int {
        switch selectedChannel {
        case .all: return allQuantity
        case .storefront: return storefrontQuantity
        case .delivery: return deliveryQuantity
        default: return allQuantity
        }
    }

    private var filteredAddOns: [LiveDashboardView.DashboardAddOnDetail] {
        let items = activeAddOns
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return items
        }
        return items.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                // Channel Segmented Control
                Picker("", selection: $selectedChannel) {
                    Text(isThai ? "ทั้งหมด" : "All").tag(DashboardSalesChannel.all)
                    Text(isThai ? "หน้าร้าน" : "Storefront").tag(DashboardSalesChannel.storefront)
                    Text(isThai ? "เดลิเวอรี" : "Delivery").tag(DashboardSalesChannel.delivery)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                // Summary KPIs
                HStack(spacing: 12) {
                    summaryTile(
                        title: isThai ? "รายการเสริมที่ขาย" : "Total Add-ons Sold",
                        value: "\(activeQuantity) " + (isThai ? "ชิ้น" : "pcs"),
                        icon: "plus.circle.fill",
                        color: .appAccent
                    )
                    summaryTile(
                        title: isThai ? "ยอดขายสินค้าเสริม" : "Total Add-on Sales",
                        value: "\(currencySymbol)\(activeRevenue.formatted(.number.precision(.fractionLength(2))))",
                        icon: "banknote.fill",
                        color: .appTeal
                    )
                    summaryTile(
                        title: isThai ? "ประเภทที่ขายได้" : "Unique Items",
                        value: "\(activeAddOns.count) " + (isThai ? "ชนิด" : "types"),
                        icon: "list.bullet.rectangle.portrait.fill",
                        color: Color(hex: "8B5CF6")
                    )
                }
                .padding(.horizontal)

                if activeAddOns.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "plus.circle.dashed")
                            .font(.system(size: 40))
                            .foregroundColor(.textTertiary)
                        Text(isThai ? "ยังไม่มีข้อมูลการขายสินค้าเสริมในช่องทางนี้" : "No add-on sales recorded for this channel")
                            .font(.subheadline)
                            .foregroundColor(.textTertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Search bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.textTertiary)
                        TextField(isThai ? "ค้นหาชื่อรายการ Add-on..." : "Search add-on name...", text: $searchText)
                            .textFieldStyle(.plain)
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.textTertiary)
                            }
                        }
                    }
                    .padding(10)
                    .background(Color.appSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.appBorderSubtle, lineWidth: 1)
                    )
                    .padding(.horizontal)

                    // Table Header
                    HStack {
                        Text(isThai ? "ลำดับ / รายการเสริม" : "Rank / Add-on Item")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(isThai ? "จำนวนที่ขาย" : "Qty Sold")
                            .frame(width: 90, alignment: .trailing)
                        Text(isThai ? "ยอดรวม" : "Total Sales")
                            .frame(width: 110, alignment: .trailing)
                        Text(isThai ? "สัดส่วน" : "Share")
                            .frame(width: 65, alignment: .trailing)
                    }
                    .font(.caption.bold())
                    .foregroundColor(.textSecondary)
                    .padding(.horizontal, 24)

                    // Table Rows
                    List {
                        ForEach(Array(filteredAddOns.enumerated()), id: \.element.id) { index, item in
                            HStack {
                                HStack(spacing: 8) {
                                    Text("\(index + 1)")
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .foregroundColor(index < 3 ? .appAccent : .textTertiary)
                                        .frame(width: 24, height: 24)
                                        .background((index < 3 ? Color.appAccent : Color.textTertiary).opacity(0.12))
                                        .clipShape(Circle())

                                    Text(item.name)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.textPrimary)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                Text("\(item.quantity) " + (isThai ? "ชิ้น" : "pcs"))
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.textSecondary)
                                    .frame(width: 90, alignment: .trailing)

                                Text("\(currencySymbol)\(item.revenue.formatted(.number.precision(.fractionLength(2))))")
                                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                                    .foregroundColor(.appTeal)
                                    .frame(width: 110, alignment: .trailing)

                                let share = activeRevenue > 0 ? (item.revenue / activeRevenue * 100) : 0
                                Text(String(format: "%.1f%%", share))
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundColor(.textTertiary)
                                    .frame(width: 65, alignment: .trailing)
                            }
                            .padding(.vertical, 3)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .padding(.top, 14)
            .navigationTitle(isThai ? "แจกแจงรายการเสริมที่ขาย (Add-ons)" : "Add-on Sales Breakdown")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(isThai ? "ปิด" : "Close") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func summaryTile(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundColor(color)
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundColor(.textSecondary)
            }
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.textPrimary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.appSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.appBorderSubtle, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.25 : 0.03), radius: 4, x: 0, y: 1.5)
    }
}

// MARK: - Transfer & QR Tender Breakdown Sheet

private struct TransferBreakdownSheet: View {
    let transfers: [LiveDashboardView.DashboardTransferDetail]
    let totalTransfer: Double
    let currencySymbol: String
    let isThai: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                VStack(spacing: 6) {
                    Text(isThai ? "ยอดรับชำระผ่านเงินโอน / QR ทั้งหมด" : "Total Transfer / QR Tender")
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                    Text("\(currencySymbol)\(totalTransfer.formatted(.number.precision(.fractionLength(2))))")
                        .font(.system(size: 26, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: "8B5CF6"))
                    Text(isThai ? "โอนเข้าบัญชีโดยตรง · ไม่เข้าลิ้นชักเงินสด" : "Direct deposit to bank · Not cash in drawer")
                        .font(.caption2)
                        .foregroundColor(.textTertiary)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(hex: "8B5CF6").opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal)

                if transfers.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "qrcode")
                            .font(.system(size: 36))
                            .foregroundColor(.textTertiary)
                        Text(isThai ? "ยังไม่มียอดชำระด้วยเงินโอนหรือ QR ในช่วงเวลานี้" : "No transfer/QR payments recorded")
                            .font(.caption)
                            .foregroundColor(.textTertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(transfers) { item in
                            HStack {
                                HStack(spacing: 12) {
                                    Image(systemName: item.methodKey == "promptpay" ? "qrcode" : (item.methodKey == "bank_transfer" ? "building.columns.fill" : "wallet.pass.fill"))
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(Color(hex: "8B5CF6"))
                                        .frame(width: 32, height: 32)
                                        .background(Color(hex: "8B5CF6").opacity(0.12))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.displayName)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(.textPrimary)
                                        Text("\(item.count) " + (isThai ? "รายการ" : "txns"))
                                            .font(.caption2)
                                            .foregroundColor(.textTertiary)
                                    }
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("\(currencySymbol)\(item.amount.formatted(.number.precision(.fractionLength(2))))")
                                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                                        .foregroundColor(.textPrimary)
                                    let pct = totalTransfer > 0 ? (item.amount / totalTransfer * 100) : 0
                                    Text(String(format: "%.1f%%", pct))
                                        .font(.caption2)
                                        .foregroundColor(.textTertiary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .padding(.top, 16)
            .navigationTitle(isThai ? "แจกแจงยอดเงินโอน & QR" : "Transfer & QR Breakdown")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(isThai ? "ปิด" : "Close") {
                        dismiss()
                    }
                }
            }
        }
    }
}
