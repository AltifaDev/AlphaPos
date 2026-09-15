// TaxReportView.swift
// AlphaPos — Reports Feature Module
//
// VAT Summary report for Thai Revenue Department (สรรพากร).
// Displays total sales (incl. VAT), VAT 7% amount, sales (excl. VAT),
// and daily breakdown table.

import SwiftUI
import SwiftData

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Tax Report View
// ─────────────────────────────────────────────────────────────────────────────

struct TaxReportView: View {
    @Bindable var viewModel: ReportsViewModel
    @EnvironmentObject private var lm: LocalizationManager

    @Query(filter: #Predicate<Order> { !$0.isDeleted }, sort: \Order.createdAt, order: .reverse)
    private var allOrders: [Order]

    @State private var showingShareSheet = false
    @State private var exportItems: [Any] = []
    @State private var exportError: String?
    @State private var selectedOrderForFullTax: Order? = nil
    @State private var orderSearchText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: APSpacing.lg) {
            // Header with Export button
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("รายงานภาษี & ใบกำกับภาษี (Tax & Fiscal Report)")
                        .font(.title3.bold())
                    Text("สรุปภาษีมูลค่าเพิ่ม 7% (ภ.พ.30) และระบบออกใบกำกับภาษีเต็มรูปแบบ (ม.86/4)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                HStack(spacing: 8) {
                    Button(action: exportVATCSV) {
                        Label("VAT CSV", systemImage: "tablecells")
                    }
                    Button(action: exportJournalCSV) {
                        Label("Accounting CSV", systemImage: "books.vertical")
                    }
                    Button {
                        exportItems = [plainTextTaxReport]
                        showingShareSheet = true
                    } label: {
                        Label("Email", systemImage: "envelope.fill")
                    }
                    .background(Color.appAccent)
                }
                .font(.caption.bold())
                .buttonStyle(.borderedProminent)
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

            // VAT position — output vs input VAT (ภ.พ.30 reconciliation)
            vatPositionSection

            // Full Tax Invoices Issuance Section
            fullTaxInvoiceManagerSection

            // Daily breakdown chart
            dailyVATChart

            // Detailed table
            dailyBreakdownTable
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(activityItems: exportItems)
        }
        .sheet(item: $selectedOrderForFullTax) { order in
            FullTaxInvoiceSheet(order: order)
        }
        .alert("Export ไม่สำเร็จ", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("ตกลง", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "Unknown export error")
        }
    }

    private func exportVATCSV() {
        do {
            let rows = eligibleOrders.map { order in
                let tax = max(0, order.taxLines.filter { !$0.isDeleted }.reduce(0) { $0 + $1.taxAmount })
                let vat = tax > 0 ? tax : max(0, order.tax)
                return ThaiVATExportRow(
                    documentNumber: order.receiptNumber ?? order.orderNumber,
                    documentDate: exportDate(order.createdAt),
                    customerTaxId: order.customer?.taxId ?? "",
                    customerName: order.customer?.name ?? "ลูกค้าทั่วไป",
                    branchNumber: UserDefaults.standard.string(forKey: "store_branch_code") ?? "00000",
                    taxableAmount: max(0, order.total - vat), vatAmount: vat,
                    totalAmount: max(0, order.total), cancelled: order.status == "cancelled"
                )
            }
            shareExport(try AccountingExport.thaiVATCSV(rows), name: "alphapos-vat-\(exportDate(Date())).csv")
        } catch { exportError = error.localizedDescription }
    }

    private func exportJournalCSV() {
        do {
            var rows: [AccountingExportRow] = []
            for order in eligibleOrders {
                let document = order.receiptNumber ?? order.orderNumber
                let taxLines = order.taxLines.filter { !$0.isDeleted }.reduce(0) { $0 + $1.taxAmount }
                let tax = taxLines > 0 ? max(0, taxLines) : max(0, order.tax)
                let total = max(0, order.total)
                let source = "order:\(order.id.uuidString.lowercased())"
                let capturedPayment = order.payments.first(where: { $0.isCaptured && !$0.isDeleted })
                let method = capturedPayment?.paymentMethod.lowercased() ?? "other"
                let occurredAt = capturedPayment?.paidAt ?? order.createdAt
                let debitCode = method == "cash" ? "1100" : "1130"
                rows.append(AccountingExportRow(documentNumber: document, businessDate: order.businessDateKey.isEmpty ? exportDate(order.createdAt) : order.businessDateKey, occurredAt: occurredAt, accountCode: debitCode, accountName: method == "cash" ? "เงินสด" : "เงินรับชำระ", debit: total, credit: 0, taxCode: "", description: "รับชำระการขาย", sourceEventKey: source))
                rows.append(AccountingExportRow(documentNumber: document, businessDate: order.businessDateKey.isEmpty ? exportDate(order.createdAt) : order.businessDateKey, occurredAt: occurredAt, accountCode: "4100", accountName: "รายได้จากการขาย", debit: 0, credit: max(0, total - tax), taxCode: tax > 0 ? "VAT7" : "NOVAT", description: "รายได้", sourceEventKey: source))
                if tax > 0 {
                    rows.append(AccountingExportRow(documentNumber: document, businessDate: order.businessDateKey.isEmpty ? exportDate(order.createdAt) : order.businessDateKey, occurredAt: occurredAt, accountCode: "2100", accountName: "ภาษีขาย", debit: 0, credit: tax, taxCode: "VAT7", description: "ภาษีมูลค่าเพิ่ม", sourceEventKey: source))
                }
            }
            shareExport(try AccountingExport.journalCSV(rows), name: "alphapos-accounting-\(exportDate(Date())).csv")
        } catch { exportError = error.localizedDescription }
    }

    private func shareExport(_ data: Data, name: String) {
        do {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AlphaPosExports", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(name)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            exportItems = [url]
            showingShareSheet = true
        } catch { exportError = error.localizedDescription }
    }

    private func exportDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Bangkok")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
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
    // MARK: - VAT Position (ภ.พ.30)
    // ─────────────────────────────────────────────────────────────────────────

    private var vatPositionSection: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            Text("tax_vat_position".t)
                .font(.headline)
            Text("tax_vat_position_desc".t)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: APSpacing.md) {
                vatPositionCard(
                    title: "tax_output_vat".t,
                    value: viewModel.formatCurrency(viewModel.totalVATAmount),
                    icon: "arrow.up.right.circle.fill",
                    color: .orange
                )
                Image(systemName: "minus")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                vatPositionCard(
                    title: "tax_input_vat".t,
                    value: viewModel.formatCurrency(viewModel.taxInputVAT),
                    icon: "arrow.down.left.circle.fill",
                    color: .indigo
                )
                Image(systemName: "equal")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                vatPositionCard(
                    title: viewModel.taxNetVATPayable >= 0 ? "tax_net_payable".t : "tax_net_refundable".t,
                    value: viewModel.formatCurrency(abs(viewModel.taxNetVATPayable)),
                    icon: "building.columns.fill",
                    color: viewModel.taxNetVATPayable >= 0 ? .red : .appTeal
                )
            }
        }
        .padding(APSpacing.md)
        .background(Color.appSurfaceHigh.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
    }

    private func vatPositionCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
                .lineLimit(1)
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(APSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Full Tax Invoice Management
    // ─────────────────────────────────────────────────────────────────────────

    private var eligibleOrders: [Order] {
        allOrders.filter { order in
            order.isRecognizedSale &&
            order.createdAt >= viewModel.effectiveStartDate &&
            order.createdAt < viewModel.effectiveEndDate &&
            (orderSearchText.isEmpty ||
             order.orderNumber.localizedCaseInsensitiveContains(orderSearchText) ||
             (order.customer?.name.localizedCaseInsensitiveContains(orderSearchText) ?? false) ||
             (order.customer?.taxId?.localizedCaseInsensitiveContains(orderSearchText) ?? false))
        }
    }

    private var fullTaxInvoiceManagerSection: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ระบบออกใบกำกับภาษีเต็มรูปแบบ (Full Tax Invoices)")
                        .font(.headline)
                    Text("ค้นหาออเดอร์ในงวดนี้เพื่อพิมพ์ใบกำกับภาษีเต็มรูปแบบ A4 สำหรับลูกค้าองค์กรหรือนิติบุคคล")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    TextField("ค้นหาเลขที่ออเดอร์ / ชื่อลูกค้า / Tax ID...", text: $orderSearchText)
                        .font(.caption)
                        .frame(width: 200)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.appSurface)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBorderSubtle, lineWidth: 1))
            }

            if eligibleOrders.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text("ไม่พบรายการขายที่เข้าเงื่อนไขในช่วงเวลานี้")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 20)
                    Spacer()
                }
                .background(Color.appSurface.opacity(0.5))
                .cornerRadius(10)
            } else {
                VStack(spacing: 6) {
                    ForEach(eligibleOrders.prefix(8)) { order in
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.appAccent.opacity(0.12))
                                    .frame(width: 32, height: 32)
                                Image(systemName: "receipt.fill")
                                    .font(.caption)
                                    .foregroundColor(.appAccent)
                            }

                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 6) {
                                    Text("#\(order.orderNumber)")
                                        .font(.subheadline.weight(.bold))
                                    if let cust = order.customer {
                                        Text("• \(cust.name)")
                                            .font(.caption)
                                            .foregroundColor(.textSecondary)
                                    }
                                }
                                Text("\(order.createdAt.formatted(date: .abbreviated, time: .shortened)) • \(order.items.count) รายการ • ชำระโดย \(order.payments.first?.paymentMethod.capitalized ?? "Cash")")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 1) {
                                Text("฿\(String(format: "%.2f", order.total))")
                                    .font(.subheadline.weight(.bold).monospacedDigit())
                                let vatPart = order.total - (order.total / 1.07)
                                Text("VAT 7%: ฿\(String(format: "%.2f", vatPart))")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                            }

                            Button {
                                selectedOrderForFullTax = order
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "doc.text.fill")
                                    Text("ออกใบกำกับภาษี A4")
                                }
                                .font(.caption.weight(.bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.appAccent)
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.appSurface)
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBorderSubtle, lineWidth: 1))
                    }
                }
            }
        }
        .padding(.vertical, 4)
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
                let maxSales = max(viewModel.dailyTaxEntries.map(\.salesExcVAT).max() ?? 0, 1)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .bottom, spacing: 8) {
                        ForEach(viewModel.dailyTaxEntries) { entry in
                            VStack(spacing: 4) {
                                let ratio = CGFloat(max(entry.salesExcVAT, 0) / maxSales)
                                ZStack(alignment: .bottom) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.appSurfaceHigh.opacity(0.4))
                                        .frame(width: 28, height: 110)

                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.appAccent.gradient)
                                        .frame(width: 28, height: max(ratio * 110, 4))

                                    let vatRatio = CGFloat(max(entry.vatAmount, 0) / maxSales)
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.orange.gradient)
                                        .frame(width: 28, height: max(vatRatio * 110, 2))
                                }

                                Text(formatDateShort(entry.date))
                                    .font(.system(size: 8))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                .frame(height: 150)

                HStack(spacing: APSpacing.md) {
                    HStack(spacing: 4) {
                        Circle().fill(Color.appAccent).frame(width: 8, height: 8)
                        Text(L.Reports.salesExcVAT.t).font(.caption2).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 4) {
                        Circle().fill(Color.orange).frame(width: 8, height: 8)
                        Text(L.Reports.vatAmount.t).font(.caption2).foregroundStyle(.secondary)
                    }
                }
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
        lines.append("ภาษีขาย (Output VAT): \(viewModel.formatCurrency(viewModel.totalVATAmount))")
        lines.append("ภาษีซื้อ (Input VAT): \(viewModel.formatCurrency(viewModel.taxInputVAT))")
        lines.append(viewModel.taxNetVATPayable >= 0
            ? "ภาษีที่ต้องนำส่ง (Net VAT Payable): \(viewModel.formatCurrency(viewModel.taxNetVATPayable))"
            : "ภาษีขอคืน (Net VAT Refundable): \(viewModel.formatCurrency(abs(viewModel.taxNetVATPayable)))")
        lines.append("------------------------------------------------")
        lines.append("รายละเอียดรายวัน:")
        for entry in viewModel.dailyTaxEntries {
            lines.append("- \(formatDateShort(entry.date)): \(entry.orderCount) ออเดอร์, ยอดขาย \(viewModel.formatCurrency(entry.salesIncVAT)), ภาษี \(viewModel.formatCurrency(entry.vatAmount))")
        }
        return lines.joined(separator: "\n")
    }
}
