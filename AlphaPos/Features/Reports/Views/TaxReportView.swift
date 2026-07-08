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

    @State private var showingShareSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: APSpacing.lg) {
            // Header with Export button
            HStack {
                Text("รายงานภาษี (Tax Report)")
                    .font(.title3.bold())
                Spacer()
                Button {
                    showingShareSheet = true
                } label: {
                    Label("ส่งรายงานทางอีเมล (Email)", systemImage: "envelope.fill")
                        .font(.caption.bold())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.appAccent)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            }

            // Summary Cards
            taxSummaryCards

            // Split Tax Category Summary
            VStack(alignment: .leading, spacing: APSpacing.sm) {
                Text("สรุปแยกประเภทภาษี (Tax Type Summary)")
                    .font(.headline)

                HStack(spacing: APSpacing.md) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("สินค้ากลุ่มมีภาษี (VAT 7%)")
                            .font(.caption).foregroundColor(.secondary)
                        Text(viewModel.formatCurrency(viewModel.vatSalesAmount))
                            .font(.title3.bold())
                        Text("ภาษีมูลค่าเพิ่ม: \(viewModel.formatCurrency(viewModel.vatTaxAmount))")
                            .font(.caption).foregroundColor(.orange)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.08))
                    .cornerRadius(10)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("สินค้ากลุ่มยกเว้นภาษี (Non-VAT)")
                            .font(.caption).foregroundColor(.secondary)
                        Text(viewModel.formatCurrency(viewModel.nonVatSalesAmount))
                            .font(.title3.bold())
                        Text("ได้รับยกเว้นภาษี")
                            .font(.caption).foregroundColor(.appTeal)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.appTeal.opacity(0.08))
                    .cornerRadius(10)
                }
            }

            // Daily breakdown chart
            dailyVATChart

            // Detailed table
            dailyBreakdownTable
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(activityItems: [plainTextTaxReport])
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

    private var plainTextTaxReport: String {
        var lines: [String] = []
        lines.append("รายงานภาษีมูลค่าเพิ่ม (VAT Tax Report)")
        lines.append("ช่วงเวลา: \(formatDateShort(viewModel.effectiveStartDate)) - \(formatDateShort(viewModel.effectiveEndDate))")
        lines.append("------------------------------------------------")
        lines.append("ยอดขายรวมภาษี: \(viewModel.formatCurrency(viewModel.totalSalesIncVAT))")
        lines.append("ยอดขายกลุ่ม VAT: \(viewModel.formatCurrency(viewModel.vatSalesAmount))")
        lines.append("ภาษีมูลค่าเพิ่ม (VAT 7%): \(viewModel.formatCurrency(viewModel.vatTaxAmount))")
        lines.append("ยอดขายกลุ่มยกเว้นภาษี (Non-VAT): \(viewModel.formatCurrency(viewModel.nonVatSalesAmount))")
        lines.append("------------------------------------------------")
        lines.append("รายละเอียดรายวัน:")
        for entry in viewModel.dailyTaxEntries {
            lines.append("- \(formatDateShort(entry.date)): \(entry.orderCount) ออเดอร์, ยอดขาย \(viewModel.formatCurrency(entry.salesIncVAT)), ภาษี \(viewModel.formatCurrency(entry.vatAmount))")
        }
        return lines.joined(separator: "\n")
    }
}
