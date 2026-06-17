// DailySalesReportView.swift
// AlphaPos — Reports Feature Module
//
// Displays daily/monthly sales summary with KPIs, hourly bar chart,
// and payment method breakdown pie chart.

import SwiftUI
import SwiftData
import Charts

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Daily Sales Report View
// ─────────────────────────────────────────────────────────────────────────────

struct DailySalesReportView: View {
    @Bindable var viewModel: ReportsViewModel
    @EnvironmentObject private var lm: LocalizationManager

    var body: some View {
        VStack(alignment: .leading, spacing: APSpacing.lg) {
            // KPI Cards Row
            kpiCardsSection

            // Hourly Sales Chart
            hourlySalesChart

            // Payment Method Breakdown
            paymentBreakdownSection
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - KPI Cards
    // ─────────────────────────────────────────────────────────────────────────

    private var kpiCardsSection: some View {
        VStack(spacing: APSpacing.md) {
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: APSpacing.md) {
                kpiCard(
                    title: L.Reports.grossRevenue.t,
                    value: viewModel.formatCurrency(viewModel.grossRevenue),
                    icon: "banknote.fill",
                    color: .appAccent
                )
                kpiCard(
                    title: L.Reports.netRevenue.t,
                    value: viewModel.formatCurrency(viewModel.netRevenue),
                    icon: "chart.line.uptrend.xyaxis",
                    color: .appTeal
                )
                kpiCard(
                    title: L.Reports.totalOrders.t,
                    value: "\(viewModel.totalOrders)",
                    icon: "bag.fill",
                    color: .orange
                )
                kpiCard(
                    title: L.Reports.avgTicket.t,
                    value: viewModel.formatCurrency(viewModel.averageTicket),
                    icon: "ticket.fill",
                    color: .purple
                )
            }

            // Secondary KPIs
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: APSpacing.md) {
                kpiCard(
                    title: L.Reports.totalDiscount.t,
                    value: viewModel.formatCurrency(viewModel.totalDiscount),
                    icon: "tag.fill",
                    color: .pink
                )
                kpiCard(
                    title: L.Reports.totalRefunds.t,
                    value: viewModel.formatCurrency(viewModel.totalRefunds),
                    icon: "arrow.uturn.left.circle.fill",
                    color: .red
                )
                kpiCard(
                    title: L.Reports.paymentMethods.t,
                    value: "\(viewModel.paymentBreakdown.count)",
                    icon: "creditcard.fill",
                    color: .indigo
                )
                kpiCard(
                    title: L.Reports.peakHour.t,
                    value: peakHourString,
                    icon: "clock.fill",
                    color: .mint
                )
            }
        }
    }

    private var peakHourString: String {
        guard let peak = viewModel.hourlySales.max(by: { $0.revenue < $1.revenue }), peak.revenue > 0 else {
            return "-"
        }
        return String(format: "%02d:00", peak.hour)
    }

    private func kpiCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            HStack {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color)
                Spacer()
            }
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(APSpacing.md)
        .background(translucent(.appSurfaceHigh, 0.5))
        .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Hourly Sales Chart
    // ─────────────────────────────────────────────────────────────────────────

    private var hourlySalesChart: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            Text(L.Reports.hourlySales.t)
                .font(.headline)

            Chart(viewModel.hourlySales) { point in
                BarMark(
                    x: .value("Hour", String(format: "%02d", point.hour)),
                    y: .value("Revenue", point.revenue)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.appAccent, Color.appAccent.opacity(0.6)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .cornerRadius(4)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: 1)) { value in
                    if let str = value.as(String.self), let hour = Int(str), hour % 3 == 0 {
                        AxisValueLabel { Text(str) }
                        AxisTick()
                    }
                }
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
            .frame(height: 200)
        }
        .padding(APSpacing.md)
        .background(translucent(.appSurfaceHigh, 0.3))
        .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Payment Breakdown
    // ─────────────────────────────────────────────────────────────────────────

    private var paymentBreakdownSection: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            Text(L.Reports.paymentBreakdown.t)
                .font(.headline)

            if viewModel.paymentBreakdown.isEmpty {
                Text(L.Reports.noData.t)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, APSpacing.lg)
            } else {
                HStack(spacing: APSpacing.lg) {
                    // Pie chart
                    Chart(viewModel.paymentBreakdown) { point in
                        SectorMark(
                            angle: .value("Amount", point.amount),
                            innerRadius: .ratio(0.5),
                            angularInset: 2
                        )
                        .foregroundStyle(by: .value("Method", displayPaymentMethod(point.method)))
                        .cornerRadius(4)
                    }
                    .frame(width: 180, height: 180)

                    // Legend table
                    VStack(alignment: .leading, spacing: APSpacing.sm) {
                        ForEach(viewModel.paymentBreakdown) { point in
                            HStack {
                                Text(displayPaymentMethod(point.method))
                                    .font(.subheadline)
                                Spacer()
                                Text(viewModel.formatCurrency(point.amount))
                                    .font(.subheadline.weight(.medium).monospacedDigit())
                                Text("(\(point.count))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(APSpacing.md)
        .background(translucent(.appSurfaceHigh, 0.3))
        .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Helpers
    // ─────────────────────────────────────────────────────────────────────────

    private func displayPaymentMethod(_ method: String) -> String {
        switch method {
        case "cash":           return L.Reports.methodCash.t
        case "credit_card":    return L.Reports.methodCard.t
        case "qr_promptpay":   return L.Reports.methodQR.t
        case "true_money":     return "TrueMoney"
        default:               return method.capitalized
        }
    }

    private func abbreviatedCurrency(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "%.0fK", value / 1000)
        }
        return String(format: "%.0f", value)
    }

    private func translucent(_ color: Color, _ opacity: Double) -> Color {
        color.opacity(opacity)
    }
}
