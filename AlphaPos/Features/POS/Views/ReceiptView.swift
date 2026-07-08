// ReceiptView.swift
// AlphaPos — On-Screen Receipt Display

import SwiftUI
import SwiftData
import UIKit

// MARK: - Receipt View Model

@Observable
@MainActor
final class ReceiptViewModel {
    let order: Order

    var storeName: String
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
    var paymentMethod: String = ""
    var paymentAmount: Double = 0.0
    var tipAmount: Double = 0.0
    var changeAmount: Double = 0.0

    init(order: Order) {
        self.order = order
        self.storeName = UserDefaults.standard.string(forKey: "store_name") ?? "AlphaPos Restaurant"
        self.receiptHeader = UserDefaults.standard.string(forKey: "receipt_header") ?? "receipt_header_default".t
        self.receiptFooter = UserDefaults.standard.string(forKey: "receipt_footer") ?? "receipt_footer_default".t

        // Generate receipt number: RCP-YYYYMMDD-NNN
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        let datePart = dateFormatter.string(from: order.createdAt)
        let sequenceNumber = String(format: "%03d", abs(order.orderNumber.hashValue) % 999 + 1)
        self.receiptNumber = "RCP-\(datePart)-\(sequenceNumber)"

        // Date and time
        let displayDateFormatter = DateFormatter()
        displayDateFormatter.dateFormat = "dd MMM yyyy"
        self.formattedDate = displayDateFormatter.string(from: order.createdAt)

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss"
        self.formattedTime = timeFormatter.string(from: order.createdAt)

        self.cashierName = order.cashierName
        self.tableNumber = order.tableSession?.table?.tableNumber

        // Build line items
        self.buildLineItems()

        // Financials
        self.subtotal = order.subtotal
        self.taxAmount = order.tax
        self.serviceCharge = order.serviceCharge
        self.discount = order.discount
        self.total = order.total

        // Payment info
        if let payment = order.payments.first {
            self.paymentMethod = payment.paymentMethod
            self.paymentAmount = payment.amount
            if payment.paymentMethod.lowercased().contains("cash") {
                self.changeAmount = max(0, payment.amount - order.total)
            }
        }
    }

    private func buildLineItems() {
        let items = order.items.filter { !$0.isDeleted }
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
        lines.append("\("payment_label".t): \(paymentMethod) ฿\(String(format: "%.2f", paymentAmount))")
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
            if UserDefaults.standard.bool(forKey: "auto_print_receipt_on_payment") {
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

                // QR Code Placeholder
                if UserDefaults.standard.object(forKey: "show_qr_on_receipt") as? Bool ?? true {
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
                totalRow(label: "pos_service_charge".t + " (10%)", amount: vm.serviceCharge)
            }

            totalRow(label: "pos_vat".t + " (7%)", amount: vm.taxAmount)

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
            HStack {
                Text("paid_via_label".t)
                    .foregroundColor(.black.opacity(0.5))
                Spacer()
                Text(vm.paymentMethod.isEmpty ? "—" : vm.paymentMethod)
                    .fontWeight(.semibold)
                    .foregroundColor(.black.opacity(0.85))
            }
            .font(.system(size: 12, design: .monospaced))

            if vm.paymentAmount > 0 {
                HStack {
                    Text("tendered_label".t)
                        .foregroundColor(.black.opacity(0.5))
                    Spacer()
                    Text("฿\(vm.paymentAmount, specifier: "%.2f")")
                        .foregroundColor(.black.opacity(0.85))
                }
                .font(.system(size: 12, design: .monospaced))
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
        VStack(spacing: APSpacing.sm) {
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.black.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .frame(width: 100, height: 100)
                .overlay(
                    VStack(spacing: 4) {
                        Image(systemName: "qrcode")
                            .font(.system(size: 36))
                            .foregroundColor(.black.opacity(0.2))
                        Text("pos_qr_code".t)
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.black.opacity(0.3))
                    }
                )

            Text("scan_digital_receipt".t)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.black.opacity(0.35))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, APSpacing.sm)
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
        HStack(spacing: APSpacing.md) {
            Button(action: {
                APHaptic.trigger()
                printReceipt()
            }) {
                Label("print_btn".t, systemImage: "printer.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: APRadius.md, style: .continuous)
                            .fill(Color(hex: "2D71F8"))
                    )
            }

            Button(action: {
                APHaptic.trigger()
                showingShareSheet = true
            }) {
                Label("email_btn".t, systemImage: "envelope.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(hex: "2D71F8"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: APRadius.md, style: .continuous)
                            .stroke(Color(hex: "2D71F8"), lineWidth: 1.5)
                    )
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
            // Print using hardware printers (USB, network, bluetooth thermal printers)
            Task {
                await PrintService.shared.dispatchReceipt(order)
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
