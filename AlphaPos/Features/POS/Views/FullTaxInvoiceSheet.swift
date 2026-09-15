// FullTaxInvoiceSheet.swift
// AlphaPos — Issue Full Tax Invoice Modal (ใบเสร็จรับเงิน/ใบกำกับภาษีเต็มรูปแบบ)
//
// Form modal allowing cashiers & managers to issue official A4 Full Tax Invoices.
// Supports picking existing customers, real-time 13-digit Tax ID validation,
// on-screen preview, AirPrint printing, and PDF export/emailing.

import SwiftUI
import SwiftData
import UIKit

struct FullTaxInvoiceSheet: View {
    let order: Order
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var lm: LocalizationManager

    @Query(filter: #Predicate<Customer> { !$0.isDeleted }, sort: \Customer.name)
    private var allCustomers: [Customer]

    // Form Fields
    @State private var buyerName: String = ""
    @State private var buyerTaxId: String = ""
    @State private var buyerBranchType: String = "head_office" // "head_office" or "branch"
    @State private var buyerBranchCode: String = "00000"
    @State private var buyerAddress: String = ""
    @State private var buyerPhone: String = ""
    @State private var buyerEmail: String = ""
    @State private var saveToCustomerCRM: Bool = true
    @State private var isCopy: Bool = false

    // State
    @State private var generatedPDFData: Data? = nil
    @State private var generatedPDFURL: URL? = nil
    @State private var showingShareSheet = false
    @State private var showingSuccessAlert = false
    @State private var alertMessage = ""
    @State private var selectedExistingCustomer: Customer? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header Banner
                    headerCard

                    // Quick Customer Picker
                    if !allCustomers.isEmpty {
                        existingCustomerPicker
                    }

                    // Buyer Information Form
                    buyerInfoForm

                    // Tax Calculation Summary
                    taxSummaryPreview

                    // Action Buttons
                    actionButtons
                }
                .padding(20)
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("ออกใบกำกับภาษีเต็มรูปแบบ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("ปิด") {
                        dismiss()
                    }
                    .foregroundColor(.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        generateAndPrint()
                    } label: {
                        Label("พิมพ์ A4", systemImage: "printer.fill")
                            .fontWeight(.semibold)
                    }
                    .disabled(!isValidForm)
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                if let url = generatedPDFURL {
                    ShareSheet(activityItems: [url])
                }
            }
            .alert("ใบกำกับภาษีเต็มรูปแบบ", isPresented: $showingSuccessAlert) {
                Button("ตกลง", role: .cancel) {
                    dismiss()
                }
            } message: {
                Text(alertMessage)
            }
            .onAppear {
                prefillFromOrder()
            }
        }
    }

    // MARK: - Header Card
    private var headerCard: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(colors: [Color.appAccent, Color(hex: "3B82F6")], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 44, height: 44)
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("ใบเสร็จรับเงิน / ใบกำกับภาษีเต็มรูปแบบ (A4)")
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                Text("อ้างอิงออเดอร์ #\(order.orderNumber) • ยอดสุทธิ ฿\(String(format: "%.2f", order.total))")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            }
            Spacer()

            Toggle("พิมพ์สำเนา (Copy)", isOn: $isCopy)
                .font(.caption)
                .fixedSize()
        }
        .padding(14)
        .background(Color.appSurface)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.appBorderSubtle, lineWidth: 1))
    }

    // MARK: - Existing Customer Picker
    private var existingCustomerPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("เลือกลูกค้าจากฐานข้อมูล (CRM)")
                .font(.caption.weight(.bold))
                .foregroundColor(.appAccent)
                .textCase(.uppercase)

            Menu {
                Button("กรอกข้อมูลใหม่ (New Customer)") {
                    selectedExistingCustomer = nil
                    buyerName = ""
                    buyerTaxId = ""
                    buyerAddress = ""
                    buyerPhone = ""
                    buyerEmail = ""
                }
                Divider()
                ForEach(allCustomers) { customer in
                    Button("\(customer.name) (\(customer.taxId ?? customer.phone ?? "ทั่วไป"))") {
                        selectCustomer(customer)
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .foregroundColor(.appAccent)
                    Text(selectedExistingCustomer?.name ?? "แตะเพื่อค้นหาหรือเลือกลูกค้า...")
                        .foregroundColor(selectedExistingCustomer != nil ? .textPrimary : .textSecondary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                }
                .padding(12)
                .background(Color.appSurface)
                .cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appBorderSubtle, lineWidth: 1))
            }
        }
    }

    // MARK: - Form Fields
    private var buyerInfoForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("ข้อมูลผู้ซื้อ / ผู้รับบริการ (BUYER DETAILS)")
                .font(.caption.weight(.bold))
                .foregroundColor(.appAccent)
                .textCase(.uppercase)

            VStack(spacing: 12) {
                // Name
                formTextField(
                    title: "ชื่อบริษัท / ชื่อนิติบุคคล หรือ ชื่อ-นามสกุล ผู้ซื้อ *",
                    placeholder: "เช่น บริษัท สยาม ฟู๊ดส์ จำกัด หรือ นายสมชาย ใจดี",
                    text: $buyerName,
                    icon: "building.2.fill"
                )

                // Tax ID with validation indicator
                VStack(alignment: .leading, spacing: 4) {
                    formTextField(
                        title: "เลขประจำตัวผู้เสียภาษี 13 หลัก (Tax ID) *",
                        placeholder: "เลข 13 หลัก เช่น 0105566012345",
                        text: $buyerTaxId,
                        icon: "creditcard.fill",
                        keyboard: .numberPad
                    )

                    let cleanTaxId = buyerTaxId.filter(\.isNumber)
                    if !cleanTaxId.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: cleanTaxId.count == 13 ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                .foregroundColor(cleanTaxId.count == 13 ? .appTeal : .appAmber)
                            Text(cleanTaxId.count == 13 ? "เลขประจำตัวผู้เสียภาษีถูกต้อง (13 หลัก)" : "กรุณากรอกตัวเลขให้ครบ 13 หลัก (ปัจจุบัน \(cleanTaxId.count)/13)")
                                .font(.system(size: 11))
                                .foregroundColor(cleanTaxId.count == 13 ? .appTeal : .appAmber)
                        }
                        .padding(.horizontal, 4)
                    }
                }

                // Branch selector
                VStack(alignment: .leading, spacing: 6) {
                    Text("สาขาของผู้ซื้อ")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.textSecondary)

                    HStack(spacing: 12) {
                        Button {
                            buyerBranchType = "head_office"
                            buyerBranchCode = "00000"
                        } label: {
                            HStack {
                                Image(systemName: buyerBranchType == "head_office" ? "largecircle.fill.circle" : "circle")
                                Text("สำนักงานใหญ่ (Head Office)")
                            }
                            .font(.caption.weight(.medium))
                            .foregroundColor(buyerBranchType == "head_office" ? .appAccent : .textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(buyerBranchType == "head_office" ? Color.appAccent.opacity(0.12) : Color.appSurface)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)

                        Button {
                            buyerBranchType = "branch"
                            if buyerBranchCode == "00000" { buyerBranchCode = "00001" }
                        } label: {
                            HStack {
                                Image(systemName: buyerBranchType == "branch" ? "largecircle.fill.circle" : "circle")
                                Text("สาขาที่...")
                            }
                            .font(.caption.weight(.medium))
                            .foregroundColor(buyerBranchType == "branch" ? .appAccent : .textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(buyerBranchType == "branch" ? Color.appAccent.opacity(0.12) : Color.appSurface)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)

                        if buyerBranchType == "branch" {
                            TextField("รหัสสาขา 5 หลัก", text: $buyerBranchCode)
                                .keyboardType(.numberPad)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 110)
                        }
                    }
                }

                // Address
                VStack(alignment: .leading, spacing: 4) {
                    Text("ที่อยู่ตาม ภ.พ.20 หรือที่อยู่จดทะเบียน *")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.textSecondary)

                    TextField("เลขที่ ถนน แขวง/ตำบล เขต/อำเภอ จังหวัด รหัสไปรษณีย์", text: $buyerAddress, axis: .vertical)
                        .lineLimit(2...4)
                        .padding(10)
                        .background(Color.appSurface)
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBorderSubtle, lineWidth: 1))
                }

                // Phone & Email
                HStack(spacing: 12) {
                    formTextField(title: "เบอร์โทรศัพท์ (ถ้ามี)", placeholder: "08X-XXX-XXXX", text: $buyerPhone, icon: "phone.fill", keyboard: .phonePad)
                    formTextField(title: "อีเมลส่ง e-Tax (ถ้ามี)", placeholder: "billing@company.com", text: $buyerEmail, icon: "envelope.fill", keyboard: .emailAddress)
                }

                Toggle("บันทึกข้อมูลลูกค้าเข้าระบบ CRM สำหรับครั้งต่อไป", isOn: $saveToCustomerCRM)
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                    .padding(.top, 4)
            }
            .padding(14)
            .background(Color.appSurface)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.appBorderSubtle, lineWidth: 1))
        }
    }

    // MARK: - Tax Summary Preview
    private var taxSummaryPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("สรุปการคำนวณภาษีมูลค่าเพิ่ม (VAT SUMMARY)")
                .font(.caption.weight(.bold))
                .foregroundColor(.appAccent)
                .textCase(.uppercase)

            VStack(spacing: 8) {
                summaryRow("รวมมูลค่าสินค้า/บริการ (Gross Subtotal)", order.subtotal)
                if order.discount > 0 {
                    summaryRow("หัก ส่วนลด (Discount)", -order.discount)
                }
                if order.serviceCharge > 0 {
                    summaryRow("ค่าบริการ (Service Charge)", order.serviceCharge)
                }

                let taxableBase = max(0, order.total / 1.07)
                let vatAmount = max(0, order.total - taxableBase)

                Divider().opacity(0.4)
                summaryRow("มูลค่าก่อนภาษี (Taxable Base)", taxableBase)
                summaryRow("ภาษีมูลค่าเพิ่ม 7% (VAT 7%)", vatAmount)

                Divider().opacity(0.4)
                HStack {
                    Text("ยอดรวมสุทธิ (Grand Total)")
                        .font(.subheadline.weight(.bold))
                    Spacer()
                    Text("฿\(String(format: "%.2f", order.total))")
                        .font(.headline.weight(.black))
                        .foregroundColor(.appAccent)
                }

                Text("(\(ThaiBahtTextFormatter.format(order.total)))")
                    .font(.caption)
                    .foregroundColor(.appTeal)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .background(Color.appSurface)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.appBorderSubtle, lineWidth: 1))
        }
    }

    // MARK: - Action Buttons
    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button {
                generateAndPrint()
            } label: {
                HStack {
                    Image(systemName: "printer.fill")
                    Text("พิมพ์ใบกำกับภาษีเต็มรูปแบบ (A4)")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(isValidForm ? Color.appAccent : Color.gray)
                .cornerRadius(12)
            }
            .disabled(!isValidForm)

            HStack(spacing: 12) {
                Button {
                    exportPDF()
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("ส่งออก PDF / แชร์")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.appAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.appSurface)
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appAccent, lineWidth: 1))
                }
                .disabled(!isValidForm)

                Button {
                    saveCustomerAndComplete()
                } label: {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("บันทึกข้อมูล")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.appTeal)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.appTeal.opacity(0.12))
                    .cornerRadius(10)
                }
                .disabled(!isValidForm)
            }
        }
    }

    // MARK: - Helpers
    private func formTextField(
        title: String,
        placeholder: String,
        text: Binding<String>,
        icon: String,
        keyboard: UIKeyboardType = .default
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.textSecondary)
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(.textTertiary)
                TextField(placeholder, text: text)
                    .keyboardType(keyboard)
            }
            .padding(10)
            .background(Color.appSurface)
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBorderSubtle, lineWidth: 1))
        }
    }

    private func summaryRow(_ title: String, _ amount: Double) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundColor(.textSecondary)
            Spacer()
            Text(amount < 0 ? "-฿\(String(format: "%.2f", abs(amount)))" : "฿\(String(format: "%.2f", amount))")
                .font(.caption.weight(.medium))
                .foregroundColor(.textPrimary)
        }
    }

    private var isValidForm: Bool {
        let cleanTax = buyerTaxId.filter(\.isNumber)
        return !buyerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
               cleanTax.count == 13 &&
               !buyerAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func prefillFromOrder() {
        if let cust = order.customer {
            selectCustomer(cust)
        }
    }

    private func selectCustomer(_ cust: Customer) {
        selectedExistingCustomer = cust
        buyerName = cust.name
        buyerTaxId = cust.taxId ?? ""
        buyerAddress = cust.address ?? ""
        buyerPhone = cust.phone ?? ""
        buyerEmail = cust.email ?? ""
    }

    private func buildSnapshot() -> FullTaxInvoiceSnapshot {
        let storeName = UserDefaults.standard.string(forKey: "store_name") ?? "AlphaPos Restaurant"
        let storeTaxId = UserDefaults.standard.string(forKey: "store_tax_id") ?? "0105559000000"
        let storeBranchCode = UserDefaults.standard.string(forKey: "store_branch_code") ?? "00000"
        let storeAddress = UserDefaults.standard.string(forKey: "store_address") ?? ""
        let storePhone = UserDefaults.standard.string(forKey: "store_phone") ?? ""

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        let dateCode = dateFormatter.string(from: order.createdAt)
        let seq = String(format: "%04d", abs(order.orderNumber.hashValue) % 9999 + 1)
        let invoiceNo = "TAX-\(dateCode)-\(seq)"

        let buyer = FullTaxInvoiceBuyerInfo(
            name: buyerName.trimmingCharacters(in: .whitespacesAndNewlines),
            taxId: buyerTaxId.filter(\.isNumber),
            branchType: buyerBranchType,
            branchCode: buyerBranchCode,
            address: buyerAddress.trimmingCharacters(in: .whitespacesAndNewlines),
            phone: buyerPhone.isEmpty ? nil : buyerPhone,
            email: buyerEmail.isEmpty ? nil : buyerEmail
        )

        let items: [FullTaxInvoiceItem] = order.items.filter { !$0.isDeleted && $0.status != "cancelled" }.enumerated().map { (idx, item) in
            FullTaxInvoiceItem(
                index: idx + 1,
                name: item.menuItem?.localizedName ?? (item.itemName.isEmpty ? "Item" : item.itemName),
                quantity: item.quantity,
                unitPrice: item.unitPrice,
                discount: 0.0,
                amount: item.subtotal,
                isTaxable: true
            )
        }

        let taxableBase = max(0, order.total / 1.07)
        let vatAmount = max(0, order.total - taxableBase)
        let completedPayment = order.payments.first(where: { !$0.isDeleted && $0.status == "completed" })

        return FullTaxInvoiceSnapshot(
            invoiceNumber: invoiceNo,
            invoiceDate: Date(),
            refOrderNumber: order.orderNumber,
            refReceiptNumber: order.receiptNumber,
            sellerName: storeName,
            sellerTaxId: storeTaxId,
            sellerBranchCode: storeBranchCode,
            sellerAddress: storeAddress,
            sellerPhone: storePhone,
            buyer: buyer,
            items: items,
            grossSubtotal: order.subtotal,
            discount: order.discount,
            serviceCharge: order.serviceCharge,
            taxableBase: taxableBase,
            vatAmount: vatAmount,
            nonVatAmount: 0.0,
            grandTotal: order.total,
            thaiBahtText: ThaiBahtTextFormatter.format(order.total),
            cashierName: order.cashierName,
            paymentMethod: completedPayment?.paymentMethod ?? "Cash",
            isCopy: isCopy
        )
    }

    private func generateAndPrint() {
        saveCustomerIfRequested()
        let snapshot = buildSnapshot()
        let pdfData = FullTaxInvoicePDFGenerator.renderPDF(snapshot: snapshot)

        let printController = UIPrintInteractionController.shared
        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.outputType = .general
        printInfo.jobName = snapshot.invoiceNumber
        printController.printInfo = printInfo
        printController.printingItem = pdfData

        printController.present(animated: true) { _, completed, error in
            if completed {
                alertMessage = "ออกใบกำกับภาษีเต็มรูปแบบ \(snapshot.invoiceNumber) สำเร็จแล้ว"
                showingSuccessAlert = true
            }
        }
    }

    private func exportPDF() {
        saveCustomerIfRequested()
        let snapshot = buildSnapshot()
        let pdfData = FullTaxInvoicePDFGenerator.renderPDF(snapshot: snapshot)

        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("\(snapshot.invoiceNumber).pdf")
        do {
            try pdfData.write(to: fileURL)
            generatedPDFURL = fileURL
            showingShareSheet = true
        } catch {
            print("Failed to save PDF: \(error)")
        }
    }

    private func saveCustomerIfRequested() {
        guard saveToCustomerCRM else { return }
        let cleanTax = buyerTaxId.filter(\.isNumber)
        guard cleanTax.count == 13 else { return }

        if let existing = selectedExistingCustomer {
            existing.taxId = cleanTax
            existing.address = buyerAddress
            if !buyerPhone.isEmpty { existing.phone = buyerPhone }
            if !buyerEmail.isEmpty { existing.email = buyerEmail }
        } else {
            // Check if already exists by Tax ID
            let match = allCustomers.first(where: { $0.taxId == cleanTax })
            if let match {
                match.name = buyerName
                match.address = buyerAddress
            } else {
                let newCustomer = Customer(
                    name: buyerName,
                    email: buyerEmail.isEmpty ? nil : buyerEmail,
                    phone: buyerPhone.isEmpty ? nil : buyerPhone,
                    taxId: cleanTax,
                    address: buyerAddress
                )
                modelContext.insert(newCustomer)
            }
        }
        try? modelContext.save()
    }

    private func saveCustomerAndComplete() {
        saveCustomerIfRequested()
        alertMessage = "บันทึกข้อมูลใบกำกับภาษีเต็มรูปแบบเรียบร้อยแล้ว"
        showingSuccessAlert = true
    }
}
