// TaxReportView.swift
// AlphaPos — Reports Feature Module
//
// VAT Summary report for Thai Revenue Department (สรรพากร).
// Displays total sales (incl. VAT), VAT 7% amount, sales (excl. VAT),
// and daily breakdown table.

import SwiftUI
import SwiftData
import Charts

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Tax Report View
// ─────────────────────────────────────────────────────────────────────────────

struct TaxReportView: View {
    @Bindable var viewModel: ReportsViewModel
    @EnvironmentObject private var lm: LocalizationManager

    var body: some View {
        VStack(alignment: .leading, spacing: APSpacing.lg) {
            // Summary Cards
            taxSummaryCards

            // Daily breakdown chart
            dailyVATChart

            // Detailed table
            dailyBreakdownTable
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Summary Cards
    // ─────────────────────────────────────────────────────────────────────────

    private var taxSummaryCards: some View {
        HStack(spacing: APSpacing.md) {
            taxSummaryCard(
                title: L.Reports.salesIncVAT.t,
                value: viewModel.formatCurrency(viewModel.totalSalesIncVAT),
                icon: "banknote.fill",
                color: .appAccent
            )
            taxSummaryCard(
                title: L.Reports.vatAmount.t,
                value: viewModel.formatCurrency(viewModel.totalVATAmount),
                icon: "building.columns.fill",
                color: .orange
            )
            taxSummaryCard(
                title: L.Reports.salesExcVAT.t,
                value: viewModel.formatCurrency(viewModel.totalSalesExcVAT),
                icon: "minus.circle.fill",
                color: .appTeal
            )
        }
    }

    private func taxSummaryCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Spacer()
            }
            Text(value)
                .font(.title2.weight(.bold).monospacedDigit())
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
    // MARK: - Daily VAT Chart
    // ─────────────────────────────────────────────────────────────────────────

    private var dailyVATChart: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            Text(L.Reports.dailyVATBreakdown.t)
                .font(.headline)

            if viewModel.dailyTaxEntries.isEmpty {
                Text(L.Reports.noData.t)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, APSpacing.lg)
                    .frame(maxWidth: .infinity)
            } else {
                Chart(viewModel.dailyTaxEntries) { entry in
                    BarMark(
                        x: .value("Date", entry.date, unit: .day),
                        y: .value("VAT", entry.vatAmount)
                    )
                    .foregroundStyle(Color.orange.gradient)
                    .cornerRadius(4)

                    LineMark(
                        x: .value("Date", entry.date, unit: .day),
                        y: .value("Sales", entry.salesExcVAT)
                    )
                    .foregroundStyle(Color.appAccent)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(abbreviatedCurrency(v))
                            }
                        }
                    }
                }
                .chartForegroundStyleScale([
                    L.Reports.vatAmount.t: Color.orange,
                    L.Reports.salesExcVAT.t: Color.appAccent
                ])
                .frame(height: 180)
            }
        }
        .padding(APSpacing.md)
        .background(Color.appSurfaceHigh.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Daily Breakdown Table
    // ─────────────────────────────────────────────────────────────────────────

    private var dailyBreakdownTable: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            Text(L.Reports.detailedBreakdown.t)
                .font(.headline)

            if viewModel.dailyTaxEntries.isEmpty {
                Text(L.Reports.noData.t)
                    .foregroundStyle(.secondary)
            } else {
                // Table header
                HStack {
                    Text(L.Reports.date.t)
                        .frame(width: 100, alignment: .leading)
                    Text(L.Reports.orders.t)
                        .frame(width: 60, alignment: .trailing)
                    Text(L.Reports.salesIncVAT.t)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text(L.Reports.vatAmount.t)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text(L.Reports.salesExcVAT.t)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, APSpacing.sm)

                Divider()

                // Data rows
                ForEach(viewModel.dailyTaxEntries) { entry in
                    HStack {
                        Text(formatDateShort(entry.date))
                            .frame(width: 100, alignment: .leading)
                        Text("\(entry.orderCount)")
                            .frame(width: 60, alignment: .trailing)
                        Text(viewModel.formatCurrency(entry.salesIncVAT))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        Text(viewModel.formatCurrency(entry.vatAmount))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .foregroundStyle(.orange)
                        Text(viewModel.formatCurrency(entry.salesExcVAT))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .font(.subheadline.monospacedDigit())
                    .padding(.horizontal, APSpacing.sm)
                    .padding(.vertical, APSpacing.xs)
                }

                Divider()

                // Totals row
                HStack {
                    Text(L.Reports.total.t)
                        .frame(width: 100, alignment: .leading)
                        .font(.subheadline.weight(.bold))
                    Text("\(viewModel.dailyTaxEntries.reduce(0) { $0 + $1.orderCount })")
                        .frame(width: 60, alignment: .trailing)
                    Text(viewModel.formatCurrency(viewModel.totalSalesIncVAT))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text(viewModel.formatCurrency(viewModel.totalVATAmount))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .foregroundStyle(.orange)
                    Text(viewModel.formatCurrency(viewModel.totalSalesExcVAT))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .font(.subheadline.weight(.bold).monospacedDigit())
                .padding(.horizontal, APSpacing.sm)
                .padding(.vertical, APSpacing.sm)
                .background(Color.appSurfaceHigh.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: APRadius.sm))
            }
        }
        .padding(APSpacing.md)
        .background(Color.appSurfaceHigh.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Helpers
    // ─────────────────────────────────────────────────────────────────────────

    private func formatDateShort(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "dd/MM/yy"
        return fmt.string(from: date)
    }

    private func abbreviatedCurrency(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "%.0fK", value / 1000)
        }
        return String(format: "%.0f", value)
    }
}
