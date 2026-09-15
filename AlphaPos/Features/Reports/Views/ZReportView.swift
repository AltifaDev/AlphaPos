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

                salesSummarySection

                receiptDivider

                tenderBreakdownSection

                receiptDivider

                // Cash Flow Summary
                cashFlowSection

                receiptDivider

                // Totals
                totalsSection

                receiptDivider

                // Variance
                if viewModel.sessionClosedAt != nil {
                    varianceSection
                }

                if !viewModel.zNotes.isEmpty {
                    receiptDivider
                    notesSection
                }
            }
            .padding(APSpacing.lg)
            .background(Color.appSurfaceHigh.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
            .frame(maxWidth: 560)
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
            receiptRow(lm.currentLanguage == .thai ? "รหัสกะ" : "Shift ID", viewModel.zSessionId)
            if !viewModel.zBusinessDateKey.isEmpty {
                receiptRow(lm.currentLanguage == .thai ? "วันทำการ" : "Business Date", viewModel.zBusinessDateKey)
            }
            receiptRow(lm.currentLanguage == .thai ? "ผู้เปิดกะ" : "Opened By", viewModel.zOpenedBy)
            receiptRow(lm.currentLanguage == .thai ? "ผู้ปิดกะ" : "Closed By", viewModel.zClosedBy)
            if let opened = viewModel.sessionOpenedAt, let closed = viewModel.sessionClosedAt {
                receiptRow(L.Reports.duration.t, formatDuration(from: opened, to: closed))
            }
        }
    }

    private var salesSummarySection: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            sectionTitle(lm.currentLanguage == .thai ? "1. สรุปยอดขาย (SALES SUMMARY)" : "1. SALES SUMMARY")
            receiptRow(lm.currentLanguage == .thai ? "ยอดขายรวมก่อนส่วนลด" : "Gross Sales", viewModel.formatCurrency(viewModel.zGrossSales))
            receiptRow(lm.currentLanguage == .thai ? "หัก ส่วนลด" : "Less: Discounts", signedMoney(-viewModel.zDiscounts))
            receiptRow(lm.currentLanguage == .thai ? "หัก คืนเงิน" : "Less: Refunds", signedMoney(-viewModel.zRefunds))
            receiptRow(lm.currentLanguage == .thai ? "ยอดขายสุทธิ (รวม VAT)" : "Net Sales (incl. VAT)", viewModel.formatCurrency(viewModel.zNetSales), bold: true)
            receiptRow(lm.currentLanguage == .thai ? "ภาษีขายรวมอยู่ในยอด" : "Output VAT included", viewModel.formatCurrency(viewModel.zTax))
            receiptRow(lm.currentLanguage == .thai ? "ค่าบริการรวมอยู่ในยอด" : "Service Charge included", viewModel.formatCurrency(viewModel.zServiceCharge))
            receiptRow(lm.currentLanguage == .thai ? "จำนวนใบเสร็จ" : "Receipt Count", "\(viewModel.zReceiptCount)")
            if viewModel.zFailedPaymentCount > 0 {
                receiptRow(lm.currentLanguage == .thai ? "รายการชำระไม่สำเร็จ" : "Failed Payments", "\(viewModel.zFailedPaymentCount)")
            }
        }
    }

    private var tenderBreakdownSection: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            sectionTitle(lm.currentLanguage == .thai ? "2. สรุปยอดรับชำระ (TENDER RECONCILIATION)" : "2. TENDER RECONCILIATION")
            if viewModel.zTenderBreakdown.isEmpty {
                receiptRow(lm.currentLanguage == .thai ? "ไม่มีรายการรับชำระ" : "No captured tenders", viewModel.formatCurrency(0))
            } else {
                ForEach([false, true], id: \.self) { isDelivery in
                    let tenders = viewModel.zTenderBreakdown.filter { $0.isDelivery == isDelivery }
                    if !tenders.isEmpty {
                        sectionTitle(isDelivery
                            ? (lm.currentLanguage == .thai ? "เดลิเวอรี่ / รอโอน" : "Delivery / Pending Settlement")
                            : (lm.currentLanguage == .thai ? "หน้าร้าน / รวมไทยช่วยไทย" : "In-Store / Including Government Support"))
                        ForEach(tenders) { tender in
                            VStack(spacing: 3) {
                                receiptRow("\(tender.method) (\(tender.count))", viewModel.formatCurrency(tender.net), bold: true)
                                receiptRow(lm.currentLanguage == .thai ? "  รับชำระ" : "  Received", viewModel.formatCurrency(tender.received))
                                if tender.refunded > 0.005 {
                                    receiptRow(lm.currentLanguage == .thai ? "  คืนเงิน" : "  Refunded", signedMoney(-tender.refunded))
                                }
                                if tender.isDelivery {
                                    Text(lm.currentLanguage == .thai ? "เดลิเวอรี / รอรับเงินจากแพลตฟอร์ม" : "Delivery / platform settlement")
                                        .font(.caption2).foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        receiptRow(
                            isDelivery
                                ? (lm.currentLanguage == .thai ? "รวมเดลิเวอรี่ (รอโอน)" : "Subtotal Delivery (Pending)")
                                : (lm.currentLanguage == .thai ? "รวมยอดหน้าร้าน" : "Subtotal In-Store"),
                            viewModel.formatCurrency(tenders.reduce(0) { $0 + $1.net }), bold: true
                        )
                    }
                }
                receiptRow(
                    lm.currentLanguage == .thai ? "รวมรับชำระสุทธิ" : "Total Net Tender",
                    viewModel.formatCurrency(viewModel.zTenderBreakdown.reduce(0) { $0 + $1.net }),
                    bold: true
                )
                receiptRow(
                    lm.currentLanguage == .thai ? "ผลต่าง Tender เทียบยอดขาย" : "Tender-to-Sales Variance",
                    signedMoney(viewModel.zTenderVariance),
                    bold: abs(viewModel.zTenderVariance) >= 0.005
                )
                if abs(viewModel.zTenderVariance) >= 0.005 {
                    Text(lm.currentLanguage == .thai
                         ? "ต้องตรวจสอบรายการชำระ เงินสนับสนุน ทิป หรือรายการ sync ที่ยังไม่ครบ"
                         : "Review payments, subsidies, tips, or incomplete synchronization.")
                        .font(.caption2).foregroundStyle(.red)
                }
            }
        }
    }

    private var cashFlowSection: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            sectionTitle(lm.currentLanguage == .thai ? "3. กระทบยอดลิ้นชักเงินสด (CASH DRAWER)" : "3. CASH DRAWER RECONCILIATION")

            receiptRow("(+) " + L.Reports.openingBalance.t, viewModel.formatCurrency(viewModel.openingCash))
            receiptRow("(+) " + L.Reports.cashSales.t, viewModel.formatCurrency(viewModel.totalCashSales))
            receiptRow("(+) " + L.Reports.cashIn.t, viewModel.formatCurrency(viewModel.totalCashIn))
            receiptRow("(-) " + L.Reports.cashOut.t, signedMoney(-viewModel.totalCashOut))
            if viewModel.zCashRefunds > 0.005 {
                receiptRow(lm.currentLanguage == .thai ? "(-) คืนเงินสด" : "(-) Cash Refunds", signedMoney(-viewModel.zCashRefunds))
            }
        }
    }

    private var totalsSection: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            sectionTitle(lm.currentLanguage == .thai ? "4. ผลการนับเงินสด (CASH COUNT)" : "4. CASH COUNT")

            receiptRow(L.Reports.expectedCash.t, viewModel.formatCurrency(viewModel.expectedCash), bold: true)
            receiptRow(L.Reports.actualCash.t, viewModel.sessionClosedAt == nil ? "—" : viewModel.formatCurrency(viewModel.actualCash), bold: true)
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: APSpacing.xs) {
            sectionTitle(lm.currentLanguage == .thai ? "หมายเหตุ / เหตุผลผลต่าง" : "NOTES / VARIANCE REASON")
            Text(viewModel.zNotes).font(.caption.monospaced())
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

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.bold).monospaced())
            .foregroundStyle(.secondary)
    }

    private func signedMoney(_ value: Double) -> String {
        if value < -0.004 { return "- " + viewModel.formatCurrency(abs(value)) }
        if value > 0.004 { return "+ " + viewModel.formatCurrency(value) }
        return viewModel.formatCurrency(0)
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
