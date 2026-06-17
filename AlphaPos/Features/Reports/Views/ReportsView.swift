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
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var lm: LocalizationManager

    @Query(filter: #Predicate<Order> { !$0.isDeleted }) private var allOrders: [Order]
    @Query(filter: #Predicate<Payment> { !$0.isDeleted }) private var allPayments: [Payment]
    @Query(filter: #Predicate<RegisterSession> { !$0.isDeleted }) private var allSessions: [RegisterSession]
    @Query(filter: #Predicate<CashMovement> { !$0.isDeleted }) private var allMovements: [CashMovement]
    @Query(filter: #Predicate<OrderTaxLine> { !$0.isDeleted }) private var allTaxLines: [OrderTaxLine]
    @Query(filter: #Predicate<MenuItem> { !$0.isDeleted }) private var allMenuItems: [MenuItem]
    @Query(filter: #Predicate<InventoryItem> { !$0.isDeleted }) private var allInventory: [InventoryItem]
    @Query(filter: #Predicate<InventoryTransaction> { !$0.isDeleted }) private var allInvTransactions: [InventoryTransaction]
    @Query(filter: #Predicate<Employee> { !$0.isDeleted }) private var allEmployees: [Employee]
    @Query(filter: #Predicate<Timecard> { !$0.isDeleted }) private var allTimecards: [Timecard]

    @State private var viewModel = ReportsViewModel()

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            GeometryReader { _ in
                HStack(spacing: APSpacing.md) {
                    // LEFT PANEL — Report Type Selection + Date Filters
                    leftPanel
                        .frame(width: 320)

                    // RIGHT PANEL — Report Content
                    rightPanel
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(APSpacing.md)
            }
        }
        .navigationTitle(L.Reports.title.t)
        .apNavBar(background: Color.appBackground)
        .onAppear { refreshCurrentReport() }
        .onChange(of: viewModel.selectedReport) { refreshCurrentReport() }
        .onChange(of: viewModel.periodMode) { refreshCurrentReport() }
        .onChange(of: viewModel.selectedDate) { refreshCurrentReport() }
        .onChange(of: viewModel.rangeStart) { refreshCurrentReport() }
        .onChange(of: viewModel.rangeEnd) { refreshCurrentReport() }
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
            // Report type selector
            reportTypeList

            Divider().opacity(0.3)

            // Period controls
            periodControls

            Spacer()

            // Export button
            exportButton
        }
        .padding(APSpacing.md)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: APRadius.lg))
    }

    private var reportTypeList: some View {
        VStack(alignment: .leading, spacing: APSpacing.xs) {
            Text(L.Reports.selectReport.t)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            ForEach(ReportType.allCases) { reportType in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.selectedReport = reportType
                    }
                } label: {
                    HStack(spacing: APSpacing.sm) {
                        Image(systemName: reportType.icon)
                            .frame(width: 24)
                            .foregroundStyle(viewModel.selectedReport == reportType ? Color.appAccent : .secondary)
                        Text(localizedReportName(reportType))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(viewModel.selectedReport == reportType ? Color.primary : .secondary)
                        Spacer()
                    }
                    .padding(.horizontal, APSpacing.sm)
                    .padding(.vertical, APSpacing.sm)
                    .background(
                        viewModel.selectedReport == reportType ?
                        Color.appAccent.opacity(0.1) : Color.clear
                    )
                    .clipShape(RoundedRectangle(cornerRadius: APRadius.sm))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var periodControls: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            Text(L.Reports.period.t)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Picker("", selection: $viewModel.periodMode) {
                Text(L.Reports.periodDaily.t).tag(ReportPeriod.daily)
                Text(L.Reports.periodWeekly.t).tag(ReportPeriod.weekly)
                Text(L.Reports.periodMonthly.t).tag(ReportPeriod.monthly)
                Text(L.Reports.periodCustom.t).tag(ReportPeriod.custom)
            }
            .pickerStyle(.segmented)

            if viewModel.periodMode == .custom {
                DatePicker(L.Reports.startDate.t, selection: $viewModel.rangeStart, displayedComponents: .date)
                    .font(.subheadline)
                DatePicker(L.Reports.endDate.t, selection: $viewModel.rangeEnd, displayedComponents: .date)
                    .font(.subheadline)
            } else {
                DatePicker(L.Reports.date.t, selection: $viewModel.selectedDate, displayedComponents: .date)
                    .font(.subheadline)
            }

            // Period description
            Text(viewModel.periodDescription)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, APSpacing.xs)
        }
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
                HStack {
                    VStack(alignment: .leading, spacing: APSpacing.xs) {
                        Text(localizedReportName(viewModel.selectedReport))
                            .font(.title2.weight(.bold))
                        Text(viewModel.periodDescription)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.bottom, APSpacing.sm)

                // Report content
                reportContent
            }
            .padding(APSpacing.md)
        }
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: APRadius.lg))
    }

    @ViewBuilder
    private var reportContent: some View {
        switch viewModel.selectedReport {
        case .dailySales:
            DailySalesReportView(viewModel: viewModel)
        case .zReport:
            ZReportView(viewModel: viewModel)
        case .taxVAT:
            TaxReportView(viewModel: viewModel)
        case .menuProfitability:
            MenuProfitabilityReportView(viewModel: viewModel)
        case .inventoryStock:
            InventoryReportView(viewModel: viewModel)
        case .employeeHours:
            EmployeeHoursReportView(viewModel: viewModel)
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Actions
    // ─────────────────────────────────────────────────────────────────────────

    private func refreshCurrentReport() {
        switch viewModel.selectedReport {
        case .dailySales:
            viewModel.computeDailySales(orders: allOrders, payments: allPayments)
        case .zReport:
            viewModel.computeZReport(sessions: allSessions, movements: allMovements, orders: allOrders, payments: allPayments)
        case .taxVAT:
            viewModel.computeTaxReport(orders: allOrders, taxLines: allTaxLines)
        case .menuProfitability:
            viewModel.computeMenuProfitability(orders: allOrders, menuItems: allMenuItems)
        case .inventoryStock:
            viewModel.computeInventoryReport(items: allInventory, transactions: allInvTransactions)
        case .employeeHours:
            viewModel.computeEmployeeHours(employees: allEmployees, timecards: allTimecards)
        }
    }

    private func exportCurrentReport() {
        let title = localizedReportName(viewModel.selectedReport).replacingOccurrences(of: " ", with: "_")
        viewModel.generatePDF(title: title, content: reportContent)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Localization Helper
    // ─────────────────────────────────────────────────────────────────────────

    private func localizedReportName(_ type: ReportType) -> String {
        switch type {
        case .dailySales:       return L.Reports.dailySales.t
        case .zReport:          return L.Reports.zReport.t
        case .taxVAT:           return L.Reports.taxVAT.t
        case .menuProfitability: return L.Reports.menuProfit.t
        case .inventoryStock:   return L.Reports.inventory.t
        case .employeeHours:    return L.Reports.employeeHours.t
        }
    }
}
