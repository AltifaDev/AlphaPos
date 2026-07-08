// MonthlyComparisonReportView.swift
// AlphaPos — L-2: Monthly Comparison Report
//
// Displays revenue, order count, avg order value, and top item
// for the last N months side-by-side with trend indicators.

import SwiftUI
import Charts

struct MonthlyComparisonReportView: View {
    @Bindable var viewModel: ReportsViewModel
    @EnvironmentObject private var lm: LocalizationManager
    @AppStorage("app_currency_symbol") private var currencySymbol = "฿"

    private var points: [ReportsViewModel.MonthPoint] { viewModel.monthlyPoints }

    // Current vs previous month
    private var current: ReportsViewModel.MonthPoint? { points.last }
    private var previous: ReportsViewModel.MonthPoint? { points.dropLast().last }

    private func pctChange(_ current: Double, _ prev: Double) -> Double? {
        guard prev > 0 else { return nil }
        return ((current - prev) / prev) * 100
    }

    var body: some View {
        VStack(alignment: .leading, spacing: APSpacing.lg) {

            if points.isEmpty {
                emptyState
            } else {
                // Range selector
                rangePicker

                // KPI summary cards
                kpiRow

                // Revenue bar chart
                revenueChart

                // Month-by-month table
                monthTable
            }
        }
    }

    // MARK: - Range Picker

    private var rangePicker: some View {
        HStack(spacing: 8) {
            ForEach([3, 6, 12], id: \.self) { n in
                Button(action: { viewModel.comparisonMonths = n }) {
                    Text("report_months_\(n)".t)
                        .font(.caption.bold())
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(viewModel.comparisonMonths == n
                            ? Color.appAccent : Color.appSurfaceHigh)
                        .foregroundColor(viewModel.comparisonMonths == n ? .white : .textSecondary)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Text("report_monthly_comparison_title".t)
                .font(.title2.bold()).foregroundColor(.textPrimary)
        }
    }

    // MARK: - KPI Row

    private var kpiRow: some View {
        HStack(spacing: APSpacing.md) {
            if let cur = current {
                kpiCard(
                    title: "report_revenue".t,
                    value: "\(currencySymbol)\(cur.revenue.formatted(.number.precision(.fractionLength(0))))",
                    pct: previous.map { pctChange(cur.revenue, $0.revenue) } ?? nil,
                    icon: "banknote.fill", color: .appTeal
                )
                kpiCard(
                    title: "report_orders".t,
                    value: "\(cur.orderCount)",
                    pct: previous.map { pctChange(Double(cur.orderCount), Double($0.orderCount)) } ?? nil,
                    icon: "cart.fill", color: .appAccent
                )
                kpiCard(
                    title: "report_avg_order".t,
                    value: "\(currencySymbol)\(cur.avgOrderValue.formatted(.number.precision(.fractionLength(0))))",
                    pct: previous.map { pctChange(cur.avgOrderValue, $0.avgOrderValue) } ?? nil,
                    icon: "chart.line.uptrend.xyaxis", color: .appAmber
                )
                kpiCard(
                    title: "report_tax_collected".t,
                    value: "\(currencySymbol)\(cur.taxCollected.formatted(.number.precision(.fractionLength(0))))",
                    pct: nil,
                    icon: "building.columns.fill", color: Color(.systemPurple)
                )
            }
        }
    }

    private func kpiCard(title: String, value: String, pct: Double??, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13)).foregroundColor(color)
                Text(title).font(.caption).foregroundColor(.textSecondary)
            }
            Text(value).font(.title3.bold()).foregroundColor(.textPrimary)
            if let p = pct, let pctVal = p {
                HStack(spacing: 3) {
                    Image(systemName: pctVal >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 10))
                    Text(String(format: "%.1f%%", abs(pctVal)))
                        .font(.caption2.bold())
                }
                .foregroundColor(pctVal >= 0 ? .appTeal : .appRose)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.06))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.18), lineWidth: 1))
    }

    // MARK: - Revenue Bar Chart

    private var revenueChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("report_revenue_trend".t)
                .font(.caption.bold()).foregroundColor(.appAccent).tracking(0.8)

            Chart(points) { pt in
                BarMark(
                    x: .value("Month", pt.label),
                    y: .value("Revenue", pt.revenue)
                )
                .foregroundStyle(
                    pt.id == current?.id
                        ? AnyShapeStyle(APGradient.accent)
                        : AnyShapeStyle(Color.appSurfaceHigh)
                )
                .cornerRadius(4)
            }
            .chartYAxis {
                AxisMarks(position: .leading) { val in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    AxisValueLabel {
                        if let v = val.as(Double.self) {
                            Text("\(currencySymbol)\((v/1000).formatted(.number.precision(.fractionLength(0))))k")
                                .font(.caption2).foregroundColor(.textTertiary)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks { val in
                    AxisValueLabel {
                        Text(val.as(String.self) ?? "")
                            .font(.caption2)
                            .foregroundColor(.textSecondary)
                    }
                }
            }

            .frame(height: 180)
        }
        .padding(14)
        .background(Color.appSurface)
        .cornerRadius(12)
    }

    // MARK: - Month Table

    private var monthTable: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("report_monthly_breakdown".t)
                .font(.caption.bold()).foregroundColor(.appAccent).tracking(0.8)

            // Header
            HStack {
                Text("report_month_col".t)
                    .font(.caption2.bold()).foregroundColor(.textSecondary).frame(width: 70, alignment: .leading)
                Spacer()
                Text("report_revenue_col".t)
                    .font(.caption2.bold()).foregroundColor(.textSecondary).frame(width: 90, alignment: .trailing)
                Text("report_orders_col".t)
                    .font(.caption2.bold()).foregroundColor(.textSecondary).frame(width: 60, alignment: .trailing)
                Text("report_avg_col".t)
                    .font(.caption2.bold()).foregroundColor(.textSecondary).frame(width: 80, alignment: .trailing)
                Text("report_top_item_col".t)
                    .font(.caption2.bold()).foregroundColor(.textSecondary).frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 10)

            ForEach(points.reversed()) { pt in
                let isCurrentMonth = pt.id == current?.id
                HStack {
                    Text(pt.label)
                        .font(.system(size: 12, weight: isCurrentMonth ? .bold : .regular))
                        .foregroundColor(isCurrentMonth ? .appAccent : .textPrimary)
                        .frame(width: 70, alignment: .leading)
                    Spacer()
                    Text("\(currencySymbol)\(pt.revenue.formatted(.number.precision(.fractionLength(0))))")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(.textPrimary)
                        .frame(width: 90, alignment: .trailing)
                    Text("\(pt.orderCount)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.textSecondary)
                        .frame(width: 60, alignment: .trailing)
                    Text("\(currencySymbol)\(pt.avgOrderValue.formatted(.number.precision(.fractionLength(0))))")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.textSecondary)
                        .frame(width: 80, alignment: .trailing)
                    Text(pt.topItem)
                        .font(.caption)
                        .foregroundColor(.textTertiary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(8)
                .background(isCurrentMonth ? Color.appAccent.opacity(0.06) : Color.clear)
                .cornerRadius(8)
                .padding(.horizontal, 2)
            }
        }
        .padding(14)
        .background(Color.appSurface)
        .cornerRadius(12)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 44)).foregroundColor(.textTertiary)
            Text("report_no_data".t)
                .font(.headline).foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
