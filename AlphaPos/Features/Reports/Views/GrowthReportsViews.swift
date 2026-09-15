// GrowthReportsViews.swift
// AlphaPos — Reports Feature Module
//
// Growth analytics: Customer Analytics (CRM), Branch Comparison and
// Sales Forecast. All three read exclusively from SwiftData via
// ReportsViewModel computed state.

import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Customer Analytics (CRM)
// ─────────────────────────────────────────────────────────────────────────────

struct CustomerAnalyticsReportView: View {
    @Bindable var viewModel: ReportsViewModel
    @EnvironmentObject private var lm: LocalizationManager

    var body: some View {
        VStack(alignment: .leading, spacing: APSpacing.lg) {
            kpiRow
            tierSection
            topCustomersSection
            attachRateHint
        }
    }

    private var kpiRow: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: APSpacing.md, alignment: .top), count: 4)
        return LazyVGrid(columns: columns, spacing: APSpacing.md) {
            ReportKPICard(title: "crm_member_sales".t,
                          value: viewModel.formatCurrency(viewModel.memberSales),
                          subtitle: "\(viewModel.memberOrderCount) \("rv_txn_unit".t)",
                          icon: "creditcard.fill", color: .appAccent)
            ReportKPICard(title: "crm_attach_rate".t,
                          value: String(format: "%.1f%%", viewModel.customerAttachRatePct),
                          subtitle: "crm_attach_rate_hint".t,
                          icon: "person.crop.circle.badge.checkmark", color: .appTeal)
            ReportKPICard(title: "crm_active_customers".t,
                          value: "\(viewModel.activeCustomerCount)",
                          subtitle: "\("crm_of_base".t) \(viewModel.totalCustomerBase)",
                          icon: "person.2.fill", color: .indigo)
            ReportKPICard(title: "crm_new_customers".t,
                          value: "\(viewModel.newCustomerCount)",
                          subtitle: "crm_new_hint".t,
                          icon: "person.badge.plus", color: .orange)
        }
    }

    private var tierSection: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            Text("crm_tier_mix".t)
                .font(.headline)

            if viewModel.customerTierBreakdown.isEmpty {
                ReportEmptyState(icon: "person.2", text: "crm_no_member_orders".t)
            } else {
                HStack(spacing: APSpacing.md) {
                    ForEach(viewModel.customerTierBreakdown) { point in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Circle().fill(tierColor(point.tier)).frame(width: 8, height: 8)
                                Text(tierLabel(point.tier))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(tierColor(point.tier))
                            }
                            Text(viewModel.formatCurrency(point.spend))
                                .font(.subheadline.weight(.bold).monospacedDigit())
                                .lineLimit(1).minimumScaleFactor(0.7)
                            Text("\(point.customerCount) \("crm_customer_unit".t)")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(tierColor(point.tier).opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: APRadius.sm))
                    }
                }
            }
        }
        .padding(APSpacing.md)
        .background(Color.appSurfaceHigh.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
    }

    private var topCustomersSection: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            Text("crm_top_customers".t)
                .font(.headline)

            if viewModel.topCustomers.isEmpty {
                ReportEmptyState(icon: "person.crop.circle.badge.questionmark", text: "crm_no_member_orders".t)
            } else {
                HStack {
                    Text("crm_customer_col".t).frame(maxWidth: .infinity, alignment: .leading)
                    Text("crm_tier_col".t).frame(width: 90, alignment: .trailing)
                    Text("crm_orders_col".t).frame(width: 60, alignment: .trailing)
                    Text("crm_points_col".t).frame(width: 70, alignment: .trailing)
                    Text("crm_spend_col".t).frame(width: 104, alignment: .trailing)
                }
                .font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                Divider()

                ForEach(viewModel.topCustomers) { customer in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(customer.name)
                                .font(.subheadline.weight(.medium)).lineLimit(1)
                            if let last = customer.lastVisit {
                                Text("\("crm_last_visit".t): \(last.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(tierLabel(customer.tier))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(tierColor(customer.tier))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(tierColor(customer.tier).opacity(0.12))
                            .clipShape(Capsule())
                            .frame(width: 90, alignment: .trailing)
                        Text("\(customer.orderCount)")
                            .font(.subheadline.monospacedDigit())
                            .frame(width: 60, alignment: .trailing)
                        Text("\(customer.loyaltyPoints)")
                            .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                            .frame(width: 70, alignment: .trailing)
                        Text(viewModel.formatCurrency(customer.spend))
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .frame(width: 104, alignment: .trailing)
                    }
                    .padding(.vertical, 5)
                    Divider().opacity(0.2)
                }
            }
        }
        .padding(APSpacing.md)
        .background(Color.appSurfaceHigh.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
    }

    private var attachRateHint: some View {
        Text("crm_footer_hint".t)
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tierLabel(_ tier: String) -> String {
        switch tier {
        case "standard": return "crm_tier_standard".t
        case "silver":   return "Silver"
        case "gold":     return "Gold"
        case "platinum": return "Platinum"
        default:         return tier.capitalized
        }
    }

    private func tierColor(_ tier: String) -> Color {
        switch tier {
        case "silver":   return .gray
        case "gold":     return .orange
        case "platinum": return .indigo
        default:         return .appTeal
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Branch Comparison
// ─────────────────────────────────────────────────────────────────────────────

struct BranchComparisonReportView: View {
    @Bindable var viewModel: ReportsViewModel
    @EnvironmentObject private var lm: LocalizationManager
    @AppStorage("store_name") private var storeName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: APSpacing.lg) {
            kpiRow
            branchChartSection
            branchTableSection
            if viewModel.activeBranchCount <= 1 {
                Text("branch_single_hint".t)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(APSpacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: APRadius.sm))
            }
        }
    }

    private var kpiRow: some View {
        HStack(spacing: APSpacing.md) {
            ReportKPICard(title: "branch_total_revenue".t,
                          value: viewModel.formatCurrency(viewModel.branchTotalRevenue),
                          subtitle: "branch_all_locations".t,
                          icon: "banknote.fill", color: .appTeal)
            ReportKPICard(title: "branch_count".t,
                          value: "\(viewModel.activeBranchCount)",
                          subtitle: "branch_active_lbl".t,
                          icon: "building.2.fill", color: .appAccent)
            ReportKPICard(title: "branch_best".t,
                          value: displayBranchName(viewModel.branchSalesBreakdown.first?.branchName),
                          subtitle: viewModel.branchSalesBreakdown.first.map { viewModel.formatCurrency($0.revenue) } ?? "—",
                          icon: "trophy.fill", color: .orange)
        }
    }

    private var branchChartSection: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            Text("branch_revenue_by".t)
                .font(.headline)

            if viewModel.branchSalesBreakdown.isEmpty {
                ReportEmptyState(icon: "building.2", text: "branch_no_data".t)
            } else {
                let maxRevenue = max(viewModel.branchSalesBreakdown.map(\.revenue).max() ?? 0, 1)

                VStack(spacing: 8) {
                    ForEach(viewModel.branchSalesBreakdown) { point in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(displayBranchName(point.branchName))
                                    .font(.subheadline)
                                Spacer()
                                Text(viewModel.formatCurrency(point.revenue))
                                    .font(.subheadline.weight(.semibold).monospacedDigit())
                            }

                            GeometryReader { geo in
                                let width = max(CGFloat(max(point.revenue, 0) / maxRevenue) * geo.size.width, 4)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(
                                        LinearGradient(colors: [Color.appAccent, Color.appAccent.opacity(0.65)],
                                                       startPoint: .leading, endPoint: .trailing)
                                    )
                                    .frame(width: width, height: 10)
                            }
                            .frame(height: 10)
                        }
                    }
                }
            }
        }
        .padding(APSpacing.md)
        .background(Color.appSurfaceHigh.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
    }

    private var branchTableSection: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            Text("branch_detail_table".t)
                .font(.headline)

            if viewModel.branchSalesBreakdown.isEmpty {
                ReportEmptyState(icon: "building.2", text: "branch_no_data".t)
            } else {
                HStack {
                    Text("branch_col".t).frame(maxWidth: .infinity, alignment: .leading)
                    Text("orders_header".t).frame(width: 70, alignment: .trailing)
                    Text("branch_guests_col".t).frame(width: 70, alignment: .trailing)
                    Text("avg_ticket_short_lbl".t).frame(width: 96, alignment: .trailing)
                    Text("purchasing_spend_col".t).frame(width: 104, alignment: .trailing)
                    Text("%").frame(width: 56, alignment: .trailing)
                }
                .font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                Divider()

                ForEach(viewModel.branchSalesBreakdown) { branch in
                    HStack {
                        Text(displayBranchName(branch.branchName))
                            .font(.subheadline.weight(.medium)).lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(branch.orderCount)")
                            .font(.subheadline.monospacedDigit())
                            .frame(width: 70, alignment: .trailing)
                        Text("\(branch.guestCount)")
                            .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                            .frame(width: 70, alignment: .trailing)
                        Text(viewModel.formatCurrency(branch.avgTicket))
                            .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                            .frame(width: 96, alignment: .trailing)
                        Text(viewModel.formatCurrency(branch.revenue))
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .frame(width: 104, alignment: .trailing)
                        Text(String(format: "%.1f%%", branch.sharePct))
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            .frame(width: 56, alignment: .trailing)
                    }
                    .padding(.vertical, 5)
                    Divider().opacity(0.2)
                }
            }
        }
        .padding(APSpacing.md)
        .background(Color.appSurfaceHigh.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
    }

    private func displayBranchName(_ name: String?) -> String {
        guard let name else { return "—" }
        if name == "__main__" {
            return storeName.isEmpty ? "branch_main_store".t : storeName
        }
        return name
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Sales Forecast
// ─────────────────────────────────────────────────────────────────────────────

struct SalesForecastReportView: View {
    @Bindable var viewModel: ReportsViewModel
    @EnvironmentObject private var lm: LocalizationManager

    var body: some View {
        VStack(alignment: .leading, spacing: APSpacing.lg) {
            kpiRow
            forecastChartSection
            confidenceSection
        }
    }

    private var kpiRow: some View {
        HStack(spacing: APSpacing.md) {
            ReportKPICard(title: "fc_next7_total".t,
                          value: viewModel.formatCurrency(viewModel.forecastNext7Total),
                          subtitle: "fc_next7_hint".t,
                          icon: "calendar.badge.clock", color: .appAccent)
            ReportKPICard(title: "fc_avg_daily".t,
                          value: viewModel.formatCurrency(viewModel.forecastAvgDaily),
                          subtitle: "fc_avg_hint".t,
                          icon: "chart.bar.fill", color: .appTeal)
            ReportKPICard(title: "fc_momentum".t,
                          value: String(format: "%+.1f%%", viewModel.forecastTrendPct),
                          subtitle: "fc_momentum_hint".t,
                          icon: viewModel.forecastTrendPct >= 0 ? "arrow.up.right" : "arrow.down.right",
                          color: viewModel.forecastTrendPct >= 0 ? .appTeal : .red)
        }
    }

    private var forecastChartSection: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            Text("fc_chart_title".t)
                .font(.headline)

            if viewModel.forecastSeries.allSatisfy({ $0.revenue == 0 }) {
                ReportEmptyState(icon: "chart.line.uptrend.xyaxis", text: "fc_no_history".t)
            } else {
                let maxRevenue = max(viewModel.forecastSeries.map(\.revenue).max() ?? 0, 1)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .bottom, spacing: 6) {
                        ForEach(viewModel.forecastSeries) { point in
                            VStack(spacing: 4) {
                                let ratio = CGFloat(max(point.revenue, 0) / maxRevenue)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(
                                        point.isForecast
                                            ? AnyShapeStyle(Color.orange.opacity(0.75))
                                            : AnyShapeStyle(Color.appAccent.gradient)
                                    )
                                    .frame(width: 22, height: max(ratio * 120, 4))

                                Text(formatForecastDate(point.date))
                                    .font(.system(size: 8))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                .frame(height: 150)

                HStack(spacing: APSpacing.md) {
                    legendDot(color: .appAccent, label: "fc_actual_legend".t)
                    legendDot(color: .orange.opacity(0.7), label: "fc_forecast_legend".t)
                }
            }
        }
        .padding(APSpacing.md)
        .background(Color.appSurfaceHigh.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
    }

    private func formatForecastDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "dd/MM"
        return fmt.string(from: date)
    }

    private var confidenceSection: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            Text("fc_confidence_title".t)
                .font(.headline)

            HStack(spacing: APSpacing.sm) {
                ForEach(1...4, id: \.self) { week in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(week <= viewModel.forecastHistoryWeeks ? Color.appTeal : Color.appSurfaceHigh)
                        .frame(height: 8)
                }
            }
            Text(confidenceText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("fc_method_note".t)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(APSpacing.md)
        .background(Color.appSurfaceHigh.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
    }

    private var confidenceText: String {
        switch viewModel.forecastHistoryWeeks {
        case 0:  return "fc_confidence_none".t
        case 1:  return "fc_confidence_low".t
        case 2, 3: return "fc_confidence_medium".t
        default: return "fc_confidence_high".t
        }
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Shared components
// ─────────────────────────────────────────────────────────────────────────────

struct ReportKPICard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            HStack {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color)
                Spacer(minLength: 0)
            }
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 24, alignment: .topLeading)
        }
        .padding(APSpacing.md)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .background(Color.appSurfaceHigh.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
    }
}

struct ReportEmptyState: View {
    let icon: String
    let text: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
    }
}
