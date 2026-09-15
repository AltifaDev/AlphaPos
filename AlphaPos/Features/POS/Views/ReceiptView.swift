// ReceiptView.swift
// AlphaPos — On-Screen Receipt Display

import SwiftUI
import SwiftData
import UIKit
import CoreImage.CIFilterBuiltins

// MARK: - Receipt View Model

@Observable
@MainActor
final class ReceiptViewModel {
    let order: Order

    var storeName: String
    var storeAddress: String
    var storePhone: String
    var storeTaxId: String
    var storeBranchCode: String
    var documentTitle: String
    var receiptHeader: String
    var receiptFooter: String
    var receiptNumber: String
    var formattedDate: String
    var formattedTime: String
    var cashierName: String
    var tableNumber: String?

    struct ReceiptLineItem: Identifiable {
        let id = UUID()
        let name: String
        let quantity: Int
        let unitPrice: Double
        let modifiers: [String]
        let subtotal: Double
    }

    var lineItems: [ReceiptLineItem] = []
    var subtotal: Double = 0.0
    var taxAmount: Double = 0.0
    var serviceCharge: Double = 0.0
    var discount: Double = 0.0
    var total: Double = 0.0
    var taxableBase: Double = 0.0
    struct PaymentLine: Identifiable {
        let id: UUID
        let method: String
        let amount: Double
        let reference: String?
    }

    var paymentLines: [PaymentLine] = []
    var tipAmount: Double = 0.0
    var changeAmount: Double = 0.0

    init(order: Order) {
        self.order = order
        self.storeName = UserDefaults.standard.string(forKey: "store_name") ?? "AlphaPos Restaurant"
        self.storeAddress = UserDefaults.standard.string(forKey: "store_address") ?? ""
        self.storePhone = UserDefaults.standard.string(forKey: "store_phone") ?? ""
        self.storeTaxId = UserDefaults.standard.string(forKey: "store_tax_id") ?? ""
        self.storeBranchCode = UserDefaults.standard.string(forKey: "store_branch_code") ?? "00000"
        self.documentTitle = (ReceiptDocumentType(rawValue: order.receiptDocumentType) ?? .receipt).thaiTitle
        // Same keys Store Settings writes ("store_receipt_header"/"store_receipt_footer")
        // so the on-screen receipt matches the live preview and printed output.
        self.receiptHeader = UserDefaults.standard.string(forKey: "store_receipt_header") ?? "receipt_header_default".t
        self.receiptFooter = UserDefaults.standard.string(forKey: "store_receipt_footer") ?? "receipt_footer_default".t

        // Prefer persisted receipt number (source of truth). Fallback only for
        // legacy orders that predate sequential receipt assignment.
        if let persisted = order.receiptNumber, !persisted.isEmpty {
            self.receiptNumber = persisted
        } else {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyyMMdd"
            dateFormatter.timeZone = TimeZone(identifier: "Asia/Bangkok") ?? .current
            let datePart = dateFormatter.string(from: order.createdAt)
            let sequenceNumber = String(format: "%03d", abs(order.orderNumber.hashValue) % 999 + 1)
            self.receiptNumber = "RCP-\(datePart)-\(sequenceNumber)"
        }

        // Date and time
        let displayDateFormatter = DateFormatter()
        displayDateFormatter.dateFormat = "dd MMM yyyy"
        self.formattedDate = displayDateFormatter.string(from: order.createdAt)

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss"
        self.formattedTime = timeFormatter.string(from: order.createdAt)

        self.cashierName = order.cashierName
        // Never surface the QUICK sentinel as a table number on receipts.
        if let table = order.tableSession?.table?.tableNumber,
           !table.isEmpty,
           table.uppercased() != "QUICK" {
            self.tableNumber = table
        } else {
            self.tableNumber = nil
        }

        // Build line items
        self.buildLineItems()

        // Financials
        self.subtotal = order.subtotal
        self.taxAmount = order.tax
        self.serviceCharge = order.serviceCharge
        self.discount = order.discount
        self.total = order.total
        self.taxableBase = order.taxLines.filter { !$0.isDeleted }.reduce(0) { $0 + $1.taxableAmount }

        // Payment info
        let completedPayments = order.payments.filter { !$0.isDeleted && $0.status == "completed" }
        self.paymentLines = completedPayments.map {
            PaymentLine(id: $0.id, method: $0.paymentMethod, amount: $0.amount, reference: Self.maskedReference($0.transactionReference))
        }
        self.tipAmount = completedPayments.reduce(0) { $0 + $1.tipAmount }
        for payment in completedPayments {
            if let tendered = payment.cashTenderedAmount {
                self.changeAmount += max(0, tendered - payment.amount)
            }
        }
    }

    private static func maskedReference(_ reference: String?) -> String? {
        guard let reference, !reference.isEmpty, !reference.hasPrefix("tendered:") else { return nil }
        guard reference.count > 5 else { return "***" + reference.suffix(2) }
        return String(reference.prefix(3)) + "******" + String(reference.suffix(2))
    }

    private func buildLineItems() {
        let items = order.items.filter {
            !$0.isDeleted && $0.status != "cancelled" && $0.status != "refunded"
        }
        lineItems = items.map { item in
            let modNames = item.modifiers.compactMap { $0.modifier?.name }
            return ReceiptLineItem(
                name: item.menuItem?.localizedName ?? (item.itemName.isEmpty ? "Unknown Item" : item.itemName),
                quantity: item.quantity,
                unitPrice: item.unitPrice,
                modifiers: modNames,
                subtotal: item.subtotal
            )
        }
    }

    var plainTextReceipt: String {
        var lines: [String] = []
        lines.append(storeName)
        lines.append(receiptHeader)
        lines.append("\("receipt_label".t): \(receiptNumber)")
        lines.append("\("date_label".t): \(formattedDate) \(formattedTime)")
        if let headerTag = PlatformOrderNumber.receiptHeaderDisplay(
            orderType: order.orderType,
            platformOrderNumber: order.platformOrderNumber,
            queueNumber: order.queueNumber
        ) {
            lines.append(headerTag)
        }
        if let platform = order.platformOrderNumber, !platform.isEmpty {
            lines.append("\("platform_order_label".t): \(platform)")
        }
        if let brand = order.deliveryBrand, !brand.isEmpty {
            lines.append("\("pos_delivery".t): \(brand)")
        }
        if let program = order.supportProgramName, !program.isEmpty {
            lines.append("โครงการร่วมจ่าย: \(program)")
        }
        if let tableNumber { lines.append("\("table_label".t): \(tableNumber)") }
        lines.append("\("cashier_label".t): \(cashierName)")
        lines.append("------------------------------")
        for item in lineItems {
            lines.append("\(item.quantity)x \(item.name) ฿\(String(format: "%.2f", item.subtotal))")
            for modifier in item.modifiers {
                lines.append("  + \(modifier)")
            }
        }
        lines.append("------------------------------")
        lines.append("\("pos_subtotal".t): ฿\(String(format: "%.2f", subtotal))")
        lines.append("\("pos_vat".t): ฿\(String(format: "%.2f", taxAmount))")
        lines.append("\("pos_service_charge".t): ฿\(String(format: "%.2f", serviceCharge))")
        if discount > 0 { lines.append("\("pos_discount".t): -฿\(String(format: "%.2f", discount))") }
        lines.append("\("pos_total".t): ฿\(String(format: "%.2f", total))")
        if order.usesGovernmentSupport {
            lines.append("รัฐสนับสนุน 60%: ฿\(String(format: "%.2f", order.supportGovernmentAmount))")
            lines.append("ประชาชนชำระ 40%: ฿\(String(format: "%.2f", order.supportCitizenAmount))")
            lines.append("สถานะเงินสนับสนุน: \(order.supportSettlementStatus)")
        }
        for payment in paymentLines {
            lines.append("\("payment_label".t): \(payment.method) ฿\(String(format: "%.2f", payment.amount))")
        }
        if tipAmount > 0 { lines.append("\("pos_tip".t): ฿\(String(format: "%.2f", tipAmount))") }
        if changeAmount > 0 { lines.append("\("pos_change_due".t): ฿\(String(format: "%.2f", changeAmount))") }
        lines.append("------------------------------")
        lines.append(receiptFooter)
        lines.append("powered_by_alphapos".t)
        return lines.joined(separator: "\n")
    }
}

// MARK: - Receipt View

struct ReceiptView: View {
    let order: Order
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var lm: LocalizationManager
    @State private var viewModel: ReceiptViewModel?
    @State private var showingShareSheet = false
    @State private var showingFullTaxInvoiceSheet = false
    @State private var receiptActionMessage = ""
    @State private var showingReceiptActionAlert = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "F5F5F5").ignoresSafeArea()

                if let vm = viewModel {
                    ScrollView {
                        VStack(spacing: 0) {
                            receiptPaper(vm: vm)
                                .padding(.horizontal, APSpacing.xl)
                                .padding(.vertical, APSpacing.lg)
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("receipt_title".t)
                        .font(.headline)
                        .foregroundColor(.black.opacity(0.8))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("close_btn".t) {
                        APHaptic.trigger()
                        dismiss()
                    }
                    .foregroundColor(Color(hex: "2D71F8"))
                    .fontWeight(.semibold)
                }
            }
            .toolbarBackground(Color.white, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
        }
        .preferredColorScheme(.light)
        .onAppear {
            viewModel = ReceiptViewModel(order: order)
            // AirPrint fallback only when no thermal printers and auto-print is on.
            // Thermal auto-print is handled by PrintService.dispatchReceipt on payment.
            let autoPrint: Bool = {
                if UserDefaults.standard.object(forKey: "auto_print_receipt_on_payment") == nil {
                    return true
                }
                return UserDefaults.standard.bool(forKey: "auto_print_receipt_on_payment")
            }()
            if autoPrint, !PrintService.shared.hasActiveReceiptPrinters() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    printReceipt()
                }
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            if let vm = viewModel {
                ShareSheet(activityItems: [vm.plainTextReceipt])
            }
        }
        .sheet(isPresented: $showingFullTaxInvoiceSheet) {
            FullTaxInvoiceSheet(order: order)
        }
        .alert("receipt_title".t, isPresented: $showingReceiptActionAlert) {
            Button("ok_btn".t, role: .cancel) {}
        } message: {
            Text(receiptActionMessage)
        }
    }

    // MARK: - Receipt Paper

    private func receiptPaper(vm: ReceiptViewModel) -> some View {
        VStack(spacing: 0) {
            // Torn top edge
            tornEdge

            VStack(spacing: APSpacing.md) {
                // Store Header
                storeHeader(vm: vm)

                receiptDivider

                // Receipt Info
                receiptInfo(vm: vm)

                receiptDivider

                // Itemized Section
                itemizedSection(vm: vm)

                receiptDivider

                // Totals
                totalsSection(vm: vm)

                receiptDivider

                // Payment
                paymentSection(vm: vm)

                receiptDivider

                // PromptPay is shown only while money is still outstanding.
                if !order.isSettled,
                   order.outstandingAmount > 0.005,
                   !(UserDefaults.standard.string(forKey: "promptpay_number") ?? "").isEmpty {
                    qrCodeSection(vm: vm)
                }

                // Footer
                footerSection(vm: vm)

                // Action buttons
                actionButtons
            }
            .padding(.horizontal, APSpacing.lg)
            .padding(.vertical, APSpacing.lg)
            .background(Color.white)

            // Torn bottom edge
            tornEdge
                .rotation3DEffect(.degrees(180), axis: (x: 1, y: 0, z: 0))
        }
        .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 4)
    }

    // MARK: - Torn Edge

    private var tornEdge: some View {
        GeometryReader { geo in
            Path { path in
                let width = geo.size.width
                let height: CGFloat = 12
                let zigzagWidth: CGFloat = 10
                path.move(to: CGPoint(x: 0, y: height))
                var x: CGFloat = 0
                var toggle = true
                while x < width {
                    x += zigzagWidth
                    let y: CGFloat = toggle ? 0 : height
                    path.addLine(to: CGPoint(x: min(x, width), y: y))
                    toggle.toggle()
                }
                path.addLine(to: CGPoint(x: width, y: height))
            }
            .fill(Color.white)
        }
        .frame(height: 12)
    }

    // MARK: - Store Header

    private func storeHeader(vm: ReceiptViewModel) -> some View {
        VStack(spacing: APSpacing.xs) {
            Text(vm.storeName)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.black)
                .multilineTextAlignment(.center)

            Text(vm.storeAddress)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.black.opacity(0.75))
                .multilineTextAlignment(.center)

            if !vm.storePhone.isEmpty {
                Text("TEL: \(vm.storePhone)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.black.opacity(0.75))
            }

            Text(vm.documentTitle)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.black)

            if let headerTag = PlatformOrderNumber.receiptHeaderDisplay(
                orderType: vm.order.orderType,
                platformOrderNumber: vm.order.platformOrderNumber,
                queueNumber: vm.order.queueNumber
            ) {
                Text(headerTag)
                    .font(.system(size: 20, weight: .black, design: .monospaced))
                    .foregroundColor(.black)
                    .padding(.vertical, 2)
            }

            if !vm.storeTaxId.isEmpty {
                Text("TAX ID: \(vm.storeTaxId)  BR: \(vm.storeBranchCode)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.black.opacity(0.8))
            }

            if vm.order.receiptPrintCount > 0 {
                Text("สำเนา / REPRINT #\(vm.order.receiptPrintCount + 1)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.black)
            }

            if !vm.receiptHeader.isEmpty {
                Text(vm.receiptHeader)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.black.opacity(0.5))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, APSpacing.xs)
    }

    // MARK: - Receipt Info

    private func receiptInfo(vm: ReceiptViewModel) -> some View {
        VStack(spacing: 4) {
            infoRow(label: "receipt_no_label".t, value: vm.receiptNumber)
            infoRow(label: "date_label".t, value: vm.formattedDate)
            infoRow(label: "time_label".t, value: vm.formattedTime)
            infoRow(label: "cashier_label".t, value: vm.cashierName)
            infoRow(label: "pos_order_number".t, value: vm.order.orderNumber)
            if let platform = vm.order.platformOrderNumber, !platform.isEmpty {
                infoRow(label: "platform_order_label".t, value: platform)
            }
            if let brand = vm.order.deliveryBrand, !brand.isEmpty {
                infoRow(label: "pos_delivery".t, value: brand)
            }
            if let program = vm.order.supportProgramName, !program.isEmpty {
                infoRow(label: "โครงการร่วมจ่าย", value: program)
            }
            if let table = vm.tableNumber {
                infoRow(label: "table_label".t, value: table)
            }
            infoRow(label: "type_label".t, value: vm.order.orderType.replacingOccurrences(of: "_", with: " ").capitalized)
        }
        .font(.system(size: 12, design: .monospaced))
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.black.opacity(0.5))
            Spacer()
            Text(value)
                .foregroundColor(.black.opacity(0.85))
                .fontWeight(.medium)
        }
    }

    // MARK: - Itemized Section

    private func itemizedSection(vm: ReceiptViewModel) -> some View {
        VStack(spacing: 2) {
            // Column headers
            HStack {
                Text("qty_header".t)
                    .frame(width: 32, alignment: .leading)
                Text("item_header".t)
                Spacer()
                Text("amount_header".t)
                    .frame(width: 80, alignment: .trailing)
            }
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(.black.opacity(0.4))
            .padding(.bottom, 4)

            ForEach(vm.lineItems) { item in
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .top) {
                        Text("\(item.quantity)x")
                            .frame(width: 32, alignment: .leading)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.name)
                                .fontWeight(.medium)
                            if !item.modifiers.isEmpty {
                                ForEach(item.modifiers, id: \.self) { mod in
                                    Text("  + \(mod)")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.black.opacity(0.45))
                                }
                            }
                        }
                        Spacer()
                        Text("฿\(item.subtotal, specifier: "%.2f")")
                            .frame(width: 80, alignment: .trailing)
                    }

                    if item.quantity > 1 {
                        Text("   @ ฿\(item.unitPrice, specifier: "%.2f") each")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.black.opacity(0.4))
                            .padding(.leading, 32)
                    }
                }
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.black.opacity(0.85))
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Totals Section

    private func totalsSection(vm: ReceiptViewModel) -> some View {
        VStack(spacing: 4) {
            totalRow(label: "pos_subtotal".t, amount: vm.subtotal)

            if vm.serviceCharge > 0 {
                let serviceRate = UserDefaults.standard.object(forKey: "store_service_charge_rate") as? Double ?? 10
                totalRow(label: "pos_service_charge".t + " (\(serviceRate.formatted())%)", amount: vm.serviceCharge)
            }

            if vm.taxAmount > 0 {
                let taxRate = UserDefaults.standard.object(forKey: "store_tax_rate") as? Double ?? 7
                totalRow(label: "Taxable base", amount: vm.taxableBase)
                totalRow(label: "pos_vat".t + " (\(taxRate.formatted())%)", amount: vm.taxAmount)
            }

            if vm.discount > 0 {
                HStack {
                    Text("pos_discount".t)
                        .foregroundColor(.black.opacity(0.6))
                    Spacer()
                    Text("-฿\(vm.discount, specifier: "%.2f")")
                        .foregroundColor(Color(hex: "E53E3E"))
                        .fontWeight(.medium)
                }
                .font(.system(size: 12, design: .monospaced))
            }

            if vm.tipAmount > 0 {
                totalRow(label: "pos_tip".t, amount: vm.tipAmount)
            }

            // Grand total
            HStack {
                Text("pos_total".t)
                    .font(.system(size: 16, weight: .black, design: .monospaced))
                Spacer()
                Text("฿\(vm.total, specifier: "%.2f")")
                    .font(.system(size: 16, weight: .black, design: .monospaced))
            }
            .foregroundColor(.black)
            .padding(.top, 4)

            if vm.order.usesGovernmentSupport {
                totalRow(label: "รัฐสนับสนุน 60%", amount: vm.order.supportGovernmentAmount)
                totalRow(label: "ประชาชนชำระ 40%", amount: vm.order.supportCitizenAmount)
                HStack {
                    Text("สถานะเงินสนับสนุน").foregroundColor(.black.opacity(0.6))
                    Spacer()
                    Text(vm.order.supportSettlementStatus == "received" ? "ได้รับแล้ว" : "รอรับจากรัฐ")
                        .fontWeight(.semibold)
                }
                .font(.system(size: 12, design: .monospaced))
            }
        }
    }

    private func totalRow(label: String, amount: Double) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.black.opacity(0.6))
            Spacer()
            Text("฿\(amount, specifier: "%.2f")")
                .foregroundColor(.black.opacity(0.85))
                .fontWeight(.medium)
        }
        .font(.system(size: 12, design: .monospaced))
    }

    // MARK: - Payment Section

    private func paymentSection(vm: ReceiptViewModel) -> some View {
        VStack(spacing: 4) {
            if vm.paymentLines.isEmpty {
                HStack {
                    Text("paid_via_label".t)
                        .foregroundColor(.black.opacity(0.5))
                    Spacer()
                    Text("—")
                        .foregroundColor(.black.opacity(0.85))
                }
                .font(.system(size: 12, design: .monospaced))
            } else {
                ForEach(vm.paymentLines) { payment in
                    HStack {
                        Text(payment.method)
                            .foregroundColor(.black.opacity(0.5))
                        Spacer()
                        Text("฿\(payment.amount, specifier: "%.2f")")
                            .fontWeight(.semibold)
                            .foregroundColor(.black.opacity(0.85))
                    }
                    .font(.system(size: 12, design: .monospaced))
                    if let reference = payment.reference {
                        Text("Reference: \(reference)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.black.opacity(0.65))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
            }

            if vm.changeAmount > 0 {
                HStack {
                    Text("pos_change_due".t)
                        .foregroundColor(.black.opacity(0.5))
                    Spacer()
                    Text("฿\(vm.changeAmount, specifier: "%.2f")")
                        .fontWeight(.bold)
                        .foregroundColor(Color(hex: "2D71F8"))
                }
                .font(.system(size: 13, design: .monospaced))
            }
        }
    }

    // MARK: - QR Code Placeholder

    private func qrCodeSection(vm: ReceiptViewModel) -> some View {
        let promptPayNumber = UserDefaults.standard.string(forKey: "promptpay_number") ?? ""
        let amountDue = vm.order.outstandingAmount
        return VStack(spacing: APSpacing.sm) {
            if let qr = promptPayQR(target: promptPayNumber, amount: amountDue) {
                Image(uiImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .padding(12) // quiet zone greater than four modules
                    .frame(width: 116, height: 116)
                    .background(Color.white)
            }

            Text(String(format: "สแกน PromptPay เพื่อชำระ THB %.2f", amountDue))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.black.opacity(0.75))
            Text("PromptPay: \(promptPayNumber)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.black.opacity(0.65))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, APSpacing.sm)
    }

    private func promptPayQR(target: String, amount: Double) -> UIImage? {
        let payload = promptPayPayload(target: target, amount: amount)
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "Q"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)) else { return nil }
        let context = CIContext()
        guard let cgImage = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private func promptPayPayload(target: String, amount: Double) -> String {
        let sanitized = target.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "")
        var accountInfo = "0016A000000677010111"
        if sanitized.count == 13 {
            accountInfo += "0213\(sanitized)"
        } else {
            var phone = sanitized
            if phone.hasPrefix("0") { phone.removeFirst() }
            accountInfo += "0113" + "0066" + phone
        }
        var payload = "000201010212"
        payload += String(format: "29%02d%@", accountInfo.count, accountInfo)
        payload += "5303764"
        let amountText = String(format: "%.2f", amount)
        payload += String(format: "54%02d%@", amountText.count, amountText)
        payload += "5802TH6304"
        return payload + crc16(payload)
    }

    private func crc16(_ value: String) -> String {
        var crc: UInt16 = 0xFFFF
        for byte in value.utf8 {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 { crc = (crc & 0x8000) != 0 ? (crc << 1) ^ 0x1021 : crc << 1 }
        }
        return String(format: "%04X", crc)
    }

    // MARK: - Footer

    private func footerSection(vm: ReceiptViewModel) -> some View {
        VStack(spacing: 4) {
            Text(vm.receiptFooter)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.black.opacity(0.4))
                .multilineTextAlignment(.center)

            Text("powered_by_alphapos".t)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.black.opacity(0.25))
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 8) {
            Button(action: {
                APHaptic.trigger()
                showingFullTaxInvoiceSheet = true
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 13, weight: .bold))
                    Text("ออกใบกำกับภาษีเต็มรูปแบบ (A4)")
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: APRadius.md, style: .continuous)
                        .fill(LinearGradient(colors: [Color.appAccent, Color(hex: "3B82F6")], startPoint: .leading, endPoint: .trailing))
                )
                .shadow(color: Color.appAccent.opacity(0.25), radius: 6, x: 0, y: 3)
            }

            HStack(spacing: APSpacing.md) {
                Button(action: {
                    APHaptic.trigger()
                    printReceipt()
                }) {
                    Label("print_btn".t, systemImage: "printer.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(hex: "2D71F8"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(
                            RoundedRectangle(cornerRadius: APRadius.md, style: .continuous)
                                .stroke(Color(hex: "2D71F8"), lineWidth: 1.5)
                        )
                }

                Button(action: {
                    APHaptic.trigger()
                    showingShareSheet = true
                }) {
                    Label("email_btn".t, systemImage: "envelope.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(hex: "2D71F8"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(
                            RoundedRectangle(cornerRadius: APRadius.md, style: .continuous)
                                .stroke(Color(hex: "2D71F8"), lineWidth: 1.5)
                        )
                }
            }
        }
        .padding(.top, APSpacing.sm)
    }

    private func printReceipt() {
        guard let vm = viewModel else { return }
        guard !UserDefaults.standard.bool(forKey: "disable_receipt_printing") else {
            receiptActionMessage = "การพิมพ์ใบเสร็จถูกปิดใช้งานในการตั้งค่าควบคุมระบบ"
            showingReceiptActionAlert = true
            return
        }

        if PrintService.shared.hasActiveReceiptPrinters() {
            // Manual reprint — bypass auto-print toggle
            Task {
                await PrintService.shared.dispatchReceipt(order, forcePrintReceipt: true)
                await MainActor.run {
                    receiptActionMessage = "receipt_sent_to_printer".t
                    showingReceiptActionAlert = true
                }
            }
        } else {
            // Fallback to AirPrint
            let controller = UIPrintInteractionController.shared
            let printInfo = UIPrintInfo(dictionary: nil)
            printInfo.outputType = .general
            printInfo.jobName = vm.receiptNumber
            controller.printInfo = printInfo

            let escaped = vm.plainTextReceipt
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\n", with: "<br>")
            controller.printFormatter = UIMarkupTextPrintFormatter(markupText: "<pre style='font-family: Menlo, monospace; font-size: 12px;'>\(escaped)</pre>")
            controller.present(animated: true) { _, completed, error in
                if let error {
                    receiptActionMessage = error.localizedDescription
                    showingReceiptActionAlert = true
                } else if completed {
                    receiptActionMessage = "receipt_sent_to_printer".t
                    showingReceiptActionAlert = true
                }
            }
        }
    }

    // MARK: - Receipt Divider

    private var receiptDivider: some View {
        HStack(spacing: 4) {
            ForEach(0..<40, id: \.self) { _ in
                Rectangle()
                    .fill(Color.black.opacity(0.12))
                    .frame(width: 6, height: 1)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
    }
}
