# -*- coding: utf-8 -*-
import sys

file_path = "/Users/mac/Documents/AlphaPos/AlphaPos/Features/POS/Views/ReceiptView.swift"

with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# Add EnvironmentObject
if "@EnvironmentObject private var lm: LocalizationManager" not in content:
    content = content.replace(
        "    @Environment(\.dismiss) private var dismiss",
        "    @Environment(\.dismiss) private var dismiss\n    @EnvironmentObject private var lm: LocalizationManager"
    )

subs = [
    # Fallbacks in ViewModel (Need @MainActor context, but calling t is fine)
    ('UserDefaults.standard.string(forKey: "receipt_header") ?? "Thank you for dining with us!"',
     'UserDefaults.standard.string(forKey: "receipt_header") ?? "receipt_header_default".t'),
    ('UserDefaults.standard.string(forKey: "receipt_footer") ?? "See you again soon! • www.alphapos.app"',
     'UserDefaults.standard.string(forKey: "receipt_footer") ?? "receipt_footer_default".t'),

    # plainTextReceipt lines
    ('lines.append("Receipt: \\(receiptNumber)")', 'lines.append("\\("receipt_label".t): \\(receiptNumber)")'),
    ('lines.append("Date: \\(formattedDate) \\(formattedTime)")', 'lines.append("\\("date_label".t): \\(formattedDate) \\(formattedTime)")'),
    ('if let tableNumber { lines.append("Table: \\(tableNumber)") }', 'if let tableNumber { lines.append("\\("table_label".t): \\(tableNumber)") }'),
    ('lines.append("Cashier: \\(cashierName)")', 'lines.append("\\("cashier_label".t): \\(cashierName)")'),
    ('lines.append("Subtotal: ฿\\(String(format: "%.2f", subtotal))")', 'lines.append("\\("pos_subtotal".t): ฿\\(String(format: "%.2f", subtotal))")'),
    ('lines.append("Tax: ฿\\(String(format: "%.2f", taxAmount))")', 'lines.append("\\("pos_vat".t): ฿\\(String(format: "%.2f", taxAmount))")'),
    ('lines.append("Service: ฿\\(String(format: "%.2f", serviceCharge))")', 'lines.append("\\("pos_service_charge".t): ฿\\(String(format: "%.2f", serviceCharge))")'),
    ('if discount > 0 { lines.append("Discount: -฿\\(String(format: "%.2f", discount))") }', 'if discount > 0 { lines.append("\\("pos_discount".t): -฿\\(String(format: "%.2f", discount))") }'),
    ('lines.append("TOTAL: ฿\\(String(format: "%.2f", total))")', 'lines.append("\\("pos_total".t): ฿\\(String(format: "%.2f", total))")'),
    ('lines.append("Payment: \\(paymentMethod) ฿\\(String(format: "%.2f", paymentAmount))")', 'lines.append("\\("payment_label".t): \\(paymentMethod) ฿\\(String(format: "%.2f", paymentAmount))")'),
    ('if changeAmount > 0 { lines.append("Change: ฿\\(String(format: "%.2f", changeAmount))") }', 'if changeAmount > 0 { lines.append("\\("pos_change_due".t): ฿\\(String(format: "%.2f", changeAmount))") }'),
    ('lines.append("Powered by AlphaPos")', 'lines.append("powered_by_alphapos".t)'),

    # Toolbar and Alerts
    ('Text("Receipt")\n                        .font(.headline)', 'Text("receipt_title".t)\n                        .font(.headline)'),
    ('Button("Close")', 'Button("close_btn".t)'),
    ('.alert("Receipt", isPresented: $showingReceiptActionAlert)', '.alert("receipt_title".t, isPresented: $showingReceiptActionAlert)'),
    ('Button("OK", role: .cancel)', 'Button("ok_btn".t, role: .cancel)'),

    # receiptInfo
    ('infoRow(label: "Receipt #", value: vm.receiptNumber)', 'infoRow(label: "receipt_no_label".t, value: vm.receiptNumber)'),
    ('infoRow(label: "Date", value: vm.formattedDate)', 'infoRow(label: "date_label".t, value: vm.formattedDate)'),
    ('infoRow(label: "Time", value: vm.formattedTime)', 'infoRow(label: "time_label".t, value: vm.formattedTime)'),
    ('infoRow(label: "Cashier", value: vm.cashierName)', 'infoRow(label: "cashier_label".t, value: vm.cashierName)'),
    ('infoRow(label: "Order #", value: vm.order.orderNumber)', 'infoRow(label: "pos_order_number".t, value: vm.order.orderNumber)'),
    ('infoRow(label: "Table", value: table)', 'infoRow(label: "table_label".t, value: table)'),
    ('infoRow(label: "Type", value: vm.order.orderType.replacingOccurrences(of: "_", with: " ").capitalized)', 'infoRow(label: "type_label".t, value: vm.order.orderType.replacingOccurrences(of: "_", with: " ").capitalized)'),

    # Columns
    ('Text("QTY")\n                    .frame(width: 32, alignment: .leading)', 'Text("qty_header".t)\n                    .frame(width: 32, alignment: .leading)'),
    ('Text("ITEM")', 'Text("item_header".t)'),
    ('Text("AMOUNT")\n                    .frame(width: 80, alignment: .trailing)', 'Text("amount_header".t)\n                    .frame(width: 80, alignment: .trailing)'),

    # Totals
    ('totalRow(label: "Subtotal", amount: vm.subtotal)', 'totalRow(label: "pos_subtotal".t, amount: vm.subtotal)'),
    ('totalRow(label: "Service Charge (10%)", amount: vm.serviceCharge)', 'totalRow(label: "pos_service_charge".t + " (10%)", amount: vm.serviceCharge)'),
    ('totalRow(label: "VAT (7%)", amount: vm.taxAmount)', 'totalRow(label: "pos_vat".t + " (7%)", amount: vm.taxAmount)'),
    ('Text("Discount")', 'Text("pos_discount".t)'),
    ('totalRow(label: "Tip", amount: vm.tipAmount)', 'totalRow(label: "pos_tip".t, amount: vm.tipAmount)'),
    ('Text("TOTAL")\n                    .font(.system(size: 16, weight: .black, design: .monospaced))', 'Text("pos_total".t)\n                    .font(.system(size: 16, weight: .black, design: .monospaced))'),

    # Payment
    ('Text("Paid via")', 'Text("paid_via_label".t)'),
    ('Text("Tendered")', 'Text("tendered_label".t)'),
    ('Text("Change")', 'Text("pos_change_due".t)'),

    # QR
    ('Text("QR Code")\n                            .font(.system(size: 8, design: .monospaced))', 'Text("pos_qr_code".t)\n                            .font(.system(size: 8, design: .monospaced))'),
    ('Text("Scan for digital receipt")', 'Text("scan_digital_receipt".t)'),

    # Footer
    ('Text("Powered by AlphaPos")', 'Text("powered_by_alphapos".t)'),

    # Print / Email buttons
    ('Label("Print", systemImage: "printer.fill")', 'Label("print_btn".t, systemImage: "printer.fill")'),
    ('Label("Email", systemImage: "envelope.fill")', 'Label("email_btn".t, systemImage: "envelope.fill")'),
    ('receiptActionMessage = "Receipt sent to printer."', 'receiptActionMessage = "receipt_sent_to_printer".t'),
]

for old_str, new_str in subs:
    content = content.replace(old_str, new_str)

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)

print("ReceiptView localized successfully!")
