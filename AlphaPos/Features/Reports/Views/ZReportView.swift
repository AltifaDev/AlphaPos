// ZReportView.swift
// AlphaPos — Reports Feature Module
//
// End-of-Day / Shift Close report displaying cash drawer summary,
// opening/closing balances, movements, and variance.
// Designed as a receipt-style printable format.

import SwiftUI
import SwiftData

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Z-Report View
// ─────────────────────────────────────────────────────────────────────────────

struct ZReportView: View {
    @Bindable var viewModel: ReportsViewModel
    @EnvironmentObject private var lm: LocalizationManager

    var body: some View {
        VStack(alignment: .leading, spacing: APSpacing.lg) {
            if viewModel.sessionOpenedAt == nil {
                noSessionView
            } else {
                receiptStyleReport
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - No Session
    // ─────────────────────────────────────────────────────────────────────────

    private var noSessionView: some View {
        VStack(spacing: APSpacing.md) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(L.Reports.noSession.t)
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(L.Reports.noSessionDesc.t)
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, APSpacing.xxl)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Receipt Style Report
    // ─────────────────────────────────────────────────────────────────────────

    private var receiptStyleReport: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Receipt container with thermal printer aesthetic
            VStack(alignment: .leading, spacing: APSpacing.md) {
                // Header
                receiptHeader

                receiptDivider

                // Session Info
                sessionInfoSection

                receiptDivider

                // Cash Flow Summary
                cashFlowSection

                receiptDivider

                // Totals
                totalsSection

                receiptDivider

                // Variance
                varianceSection
            }
            .padding(APSpacing.lg)
            .background(Color.appSurfaceHigh.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
            .frame(maxWidth: 480)
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Receipt Sections
    // ─────────────────────────────────────────────────────────────────────────

    private var receiptHeader: some View {
        VStack(spacing: APSpacing.xs) {
            Text("Z-REPORT")
                .font(.title3.weight(.bold).monospaced())
            Text(L.Reports.endOfDay.t)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var sessionInfoSection: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            Text(L.Reports.sessionInfo.t)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            receiptRow(L.Reports.openedAt.t, formatTime(viewModel.sessionOpenedAt))
            receiptRow(L.Reports.closedAt.t, formatTime(viewModel.sessionClosedAt))
            if let opened = viewModel.sessionOpenedAt, let closed = viewModel.sessionClosedAt {
                receiptRow(L.Reports.duration.t, formatDuration(from: opened, to: closed))
            }
        }
    }

    private var cashFlowSection: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            Text(L.Reports.cashFlow.t)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            receiptRow(L.Reports.openingBalance.t, viewModel.formatCurrency(viewModel.openingCash))
            receiptRow(L.Reports.cashSales.t, "+ " + viewModel.formatCurrency(viewModel.totalCashSales))
            receiptRow(L.Reports.cashIn.t, "+ " + viewModel.formatCurrency(viewModel.totalCashIn))
            receiptRow(L.Reports.cashOut.t, "- " + viewModel.formatCurrency(viewModel.totalCashOut))
        }
    }

    private var totalsSection: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            Text(L.Reports.totals.t)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            receiptRow(L.Reports.expectedCash.t, viewModel.formatCurrency(viewModel.expectedCash), bold: true)
            receiptRow(L.Reports.actualCash.t, viewModel.formatCurrency(viewModel.actualCash), bold: true)
        }
    }

    private var varianceSection: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            let isOver = viewModel.variance > 0
            let isShort = viewModel.variance < 0
            let varianceColor: Color = isShort ? .red : (isOver ? .orange : .appTeal)

            HStack {
                Text(L.Reports.variance.t)
                    .font(.subheadline.weight(.bold))
                Spacer()
                HStack(spacing: APSpacing.xs) {
                    if isOver {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundStyle(varianceColor)
                        Text("+" + viewModel.formatCurrency(viewModel.variance))
                    } else if isShort {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(varianceColor)
                        Text(viewModel.formatCurrency(viewModel.variance))
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(varianceColor)
                        Text(viewModel.formatCurrency(0))
                    }
                }
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(varianceColor)
            }
            .padding(APSpacing.sm)
            .background(varianceColor.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: APRadius.sm))

            if isShort {
                Text(L.Reports.varianceShort.t)
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.8))
            } else if isOver {
                Text(L.Reports.varianceOver.t)
                    .font(.caption)
                    .foregroundStyle(.orange.opacity(0.8))
            } else {
                Text(L.Reports.varianceOk.t)
                    .font(.caption)
                    .foregroundStyle(Color.appTeal)
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Receipt Primitives
    // ─────────────────────────────────────────────────────────────────────────

    private func receiptRow(_ label: String, _ value: String, bold: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(bold ? .subheadline.weight(.semibold) : .subheadline)
            Spacer()
            Text(value)
                .font(bold ? .subheadline.weight(.bold).monospacedDigit() : .subheadline.monospacedDigit())
        }
    }

    private var receiptDivider: some View {
        Text(String(repeating: "─", count: 40))
            .font(.caption.monospaced())
            .foregroundStyle(.secondary.opacity(0.5))
            .frame(maxWidth: .infinity, alignment: .center)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Formatters
    // ─────────────────────────────────────────────────────────────────────────

    private func formatTime(_ date: Date?) -> String {
        guard let date else { return "—" }
        let fmt = DateFormatter()
        fmt.dateFormat = "dd/MM/yyyy HH:mm"
        return fmt.string(from: date)
    }

    private func formatDuration(from start: Date, to end: Date) -> String {
        let interval = end.timeIntervalSince(start)
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        return String(format: "%dh %02dm", hours, minutes)
    }
}
