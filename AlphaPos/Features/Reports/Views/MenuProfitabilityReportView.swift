// MenuProfitabilityReportView.swift
// AlphaPos — Reports Feature Module
//
// Displays per-menu-item profitability: quantity sold, revenue, COGS,
// gross profit, and margin %. Includes sortable table and top/bottom highlights.

import SwiftUI
import SwiftData
import Charts

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Menu Profitability Report View
// ─────────────────────────────────────────────────────────────────────────────

struct MenuProfitabilityReportView: View {
    @Bindable var viewModel: ReportsViewModel
    @EnvironmentObject private var lm: LocalizationManager

    var body: some View {
        VStack(alignment: .leading, spacing: APSpacing.lg) {
            // Summary KPIs
            profitSummaryCards

            // Top/Bottom highlights
            topBottomHighlights

            // Sortable table
            profitabilityTable
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Summary Cards
    // ─────────────────────────────────────────────────────────────────────────

    private var profitSummaryCards: some View {
        HStack(spacing: APSpacing.md) {
            summaryCard(
                title: L.Reports.totalItems.t,
                value: "\(viewModel.menuProfitItems.count)",
                icon: "fork.knife",
                color: .appAccent
            )
            summaryCard(
                title: L.Reports.totalRevenue.t,
                value: viewModel.formatCurrency(totalRevenue),
                icon: "banknote.fill",
                color: .appTeal
            )
            summaryCard(
                title: L.Reports.totalCOGS.t,
                value: viewModel.formatCurrency(totalCOGS),
                icon: "cart.fill",
                color: .orange
            )
            summaryCard(
                title: L.Reports.avgMargin.t,
                value: String(format: "%.1f%%", avgMargin),
                icon: "percent",
                color: avgMargin > 50 ? .appTeal : .orange
            )
        }
    }

    private func summaryCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(APSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appSurfaceHigh.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Top/Bottom Highlights
    // ─────────────────────────────────────────────────────────────────────────

    private var topBottomHighlights: some View {
        HStack(spacing: APSpacing.md) {
            // Top 5 most profitable
            VStack(alignment: .leading, spacing: APSpacing.sm) {
                Label(L.Reports.topProfitable.t, systemImage: "arrow.up.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.appTeal)

                ForEach(topProfitable.prefix(5)) { item in
                    HStack {
                        Text(item.name)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        Text(String(format: "%.1f%%", item.marginPct))
                            .font(.caption.weight(.medium).monospacedDigit())
                            .foregroundStyle(Color.appTeal)
                    }
                }
            }
            .padding(APSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.appTeal.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: APRadius.md))

            // Bottom 5 least profitable
            VStack(alignment: .leading, spacing: APSpacing.sm) {
                Label(L.Reports.leastProfitable.t, systemImage: "arrow.down.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)

                ForEach(bottomProfitable.prefix(5)) { item in
                    HStack {
                        Text(item.name)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        Text(String(format: "%.1f%%", item.marginPct))
                            .font(.caption.weight(.medium).monospacedDigit())
                            .foregroundStyle(.red)
                    }
                }
            }
            .padding(APSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Profitability Table
    // ─────────────────────────────────────────────────────────────────────────

    private var profitabilityTable: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            Text(L.Reports.menuItemBreakdown.t)
                .font(.headline)

            if viewModel.menuProfitItems.isEmpty {
                Text(L.Reports.noData.t)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, APSpacing.lg)
                    .frame(maxWidth: .infinity)
            } else {
                // Table header with sort controls
                tableHeader

                Divider()

                // Data rows
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.menuProfitItems) { item in
                            tableRow(item)
                            Divider().opacity(0.3)
                        }
                    }
                }
                .frame(maxHeight: 400)
            }
        }
        .padding(APSpacing.md)
        .background(Color.appSurfaceHigh.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
    }

    private var tableHeader: some View {
        HStack {
            sortableHeader(L.Reports.itemName.t, column: "name", width: 160)
            sortableHeader(L.Reports.qtySold.t, column: "quantity", width: 60)
            sortableHeader(L.Reports.revenue.t, column: "revenue", width: 100)
            sortableHeader(L.Reports.cogs.t, column: "cogs", width: 100)
            sortableHeader(L.Reports.profit.t, column: "profit", width: 100)
            sortableHeader(L.Reports.margin.t, column: "margin", width: 70)
        }
        .padding(.horizontal, APSpacing.sm)
    }

    private func sortableHeader(_ title: String, column: String, width: CGFloat) -> some View {
        Button {
            if viewModel.sortByColumn == column {
                viewModel.sortAscending.toggle()
            } else {
                viewModel.sortByColumn = column
                viewModel.sortAscending = false
            }
            viewModel.applySorting()
        } label: {
            HStack(spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                if viewModel.sortByColumn == column {
                    Image(systemName: viewModel.sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
            }
            .foregroundStyle(viewModel.sortByColumn == column ? Color.appAccent : .secondary)
        }
        .buttonStyle(.plain)
        .frame(width: width, alignment: column == "name" ? .leading : .trailing)
    }

    private func tableRow(_ item: MenuProfitPoint) -> some View {
        HStack {
            Text(item.name)
                .font(.subheadline)
                .lineLimit(1)
                .frame(width: 160, alignment: .leading)
            Text("\(item.quantitySold)")
                .font(.subheadline.monospacedDigit())
                .frame(width: 60, alignment: .trailing)
            Text(viewModel.formatCurrency(item.revenue))
                .font(.subheadline.monospacedDigit())
                .frame(width: 100, alignment: .trailing)
            Text(viewModel.formatCurrency(item.cogs))
                .font(.subheadline.monospacedDigit())
                .frame(width: 100, alignment: .trailing)
                .foregroundStyle(.orange)
            Text(viewModel.formatCurrency(item.grossProfit))
                .font(.subheadline.monospacedDigit())
                .frame(width: 100, alignment: .trailing)
                .foregroundStyle(item.grossProfit >= 0 ? Color.appTeal : .red)
            Text(String(format: "%.1f%%", item.marginPct))
                .font(.subheadline.weight(.medium).monospacedDigit())
                .frame(width: 70, alignment: .trailing)
                .foregroundStyle(marginColor(item.marginPct))
        }
        .padding(.horizontal, APSpacing.sm)
        .padding(.vertical, APSpacing.xs)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Computed Properties
    // ─────────────────────────────────────────────────────────────────────────

    private var totalRevenue: Double {
        viewModel.menuProfitItems.reduce(0) { $0 + $1.revenue }
    }

    private var totalCOGS: Double {
        viewModel.menuProfitItems.reduce(0) { $0 + $1.cogs }
    }

    private var avgMargin: Double {
        guard !viewModel.menuProfitItems.isEmpty else { return 0 }
        return viewModel.menuProfitItems.reduce(0) { $0 + $1.marginPct } / Double(viewModel.menuProfitItems.count)
    }

    private var topProfitable: [MenuProfitPoint] {
        viewModel.menuProfitItems.sorted { $0.marginPct > $1.marginPct }
    }

    private var bottomProfitable: [MenuProfitPoint] {
        viewModel.menuProfitItems.sorted { $0.marginPct < $1.marginPct }
    }

    private func marginColor(_ pct: Double) -> Color {
        if pct >= 60 { return .appTeal }
        if pct >= 30 { return .orange }
        return .red
    }
}
