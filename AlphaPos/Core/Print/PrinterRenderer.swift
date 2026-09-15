import Foundation
import UIKit
import CoreGraphics

struct PreBillDraftModifier {
    let name: String
    let price: Double
}

struct PreBillDraftItem {
    let name: String
    let quantity: Int
    let unitPrice: Double
    let modifiers: [PreBillDraftModifier]
    let notes: String
}

struct PreBillDraft {
    let orderReference: String
    let orderType: String
    let guestCount: Int
    let items: [PreBillDraftItem]
    let subtotal: Double
    let tax: Double
    let serviceCharge: Double
    let discount: Double
    let total: Double
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Windows CP874 Encoding & Monospace Width Support
// ─────────────────────────────────────────────────────────────────────────────
extension String.Encoding {
    static let windowsCP874 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.isoLatinThai.rawValue)))
}

extension String {
    /// Calculate visual printable width on CP874 monospace thermal printer
    /// (Thai combining upper/lower vowels and tone marks take 0 advance width on monospace thermal printers)
    var thaiVisualWidth: Int {
        let combiningThaiScalars: Set<UInt32> = [
            0x0E31, 0x0E34, 0x0E35, 0x0E36, 0x0E37, 0x0E38, 0x0E39, 0x0E3A,
            0x0E47, 0x0E48, 0x0E49, 0x0E4A, 0x0E4B, 0x0E4C, 0x0E4D, 0x0E4E
        ]
        var count = 0
        for scalar in self.unicodeScalars {
            if !combiningThaiScalars.contains(scalar.value) {
                count += 1
            }
        }
        return count
    }

    /// Truncate string so its thaiVisualWidth does not exceed maxVisualWidth
    func truncateThaiByVisualWidth(_ maxVisualWidth: Int) -> String {
        let combiningThaiScalars: Set<UInt32> = [
            0x0E31, 0x0E34, 0x0E35, 0x0E36, 0x0E37, 0x0E38, 0x0E39, 0x0E3A,
            0x0E47, 0x0E48, 0x0E49, 0x0E4A, 0x0E4B, 0x0E4C, 0x0E4D, 0x0E4E
        ]
        var result = ""
        var currentVisualWidth = 0
        for char in self {
            var charVisualWidth = 0
            for scalar in char.unicodeScalars {
                if !combiningThaiScalars.contains(scalar.value) {
                    charVisualWidth += 1
                }
            }
            if currentVisualWidth + charVisualWidth > maxVisualWidth {
                break
            }
            result.append(char)
            currentVisualWidth += charVisualWidth
        }
        return result
    }

    /// Pad string with spaces on the right to reach a target visual width
    func paddedThai(to visualWidth: Int) -> String {
        let current = self.thaiVisualWidth
        let needed = max(0, visualWidth - current)
        return self + String(repeating: " ", count: needed)
    }

    /// Pad string with spaces on the left to right-align within a target visual width
    func rightAlignedThai(in visualWidth: Int) -> String {
        let current = self.thaiVisualWidth
        let needed = max(0, visualWidth - current)
        return String(repeating: " ", count: needed) + self
    }
}

private func receiptLines(_ value: String, width: Int, maxLines: Int = 2) -> [String] {
    let normalized = value
        .replacingOccurrences(of: "\n", with: " ")
        .split(whereSeparator: { $0.isWhitespace })
        .map(String.init)
    guard !normalized.isEmpty, width > 0, maxLines > 0 else { return [] }

    var lines: [String] = []
    var current = ""
    for word in normalized {
        let candidate = current.isEmpty ? word : "\(current) \(word)"
        if candidate.thaiVisualWidth <= width {
            current = candidate
        } else {
            if !current.isEmpty {
                lines.append(current)
                if lines.count == maxLines { return lines }
            }
            current = word.truncateThaiByVisualWidth(width)
        }
    }
    if lines.count < maxLines, !current.isEmpty { lines.append(current) }
    return Array(lines.prefix(maxLines))
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - ESC/POS Renderer
// ─────────────────────────────────────────────────────────────────────────────
struct ESCPosRenderer: PrinterRenderer {
    func render(job: PrintJob, emulation: String) -> Data {
        switch job.role {
        case "receipt":
            return ESCPOSBuilder.buildReceipt(
                order: job.order,
                template: job.template,
                logoBitmap: job.logoBitmap,
                emulation: emulation,
                paperWidth: job.hardwarePaperWidth
            )
        case "kitchen", "bar":
            let stationLabel = job.role == "bar" ? "BAR TICKET" : "KITCHEN TICKET"
            let activeItems = job.order.items.filter { !$0.isDeleted }
            return ESCPOSBuilder.buildKitchenTicket(
                order: job.order,
                items: activeItems,
                stationLabel: stationLabel,
                template: job.template,
                emulation: emulation,
                paperWidth: job.hardwarePaperWidth
            )
        default:
            return ESCPOSBuilder.buildReceipt(
                order: job.order,
                template: job.template,
                emulation: emulation,
                paperWidth: job.hardwarePaperWidth
            )
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Star Renderer
// ─────────────────────────────────────────────────────────────────────────────
struct StarRenderer: PrinterRenderer {
    func render(job: PrintJob, emulation: String) -> Data {
        // Under Star-native path, this would use StarXpandCommand builder.
        // For now, as a dynamic transition stub, it delegates to the optimized ESC/POS payload
        // using Star's specific command adjustments.
        return ESCPosRenderer().render(job: job, emulation: emulation)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - TSPL Renderer
// ─────────────────────────────────────────────────────────────────────────────
struct TSPLRenderer: PrinterRenderer {
    func render(job: PrintJob, emulation: String) -> Data {
        let items = job.order.items.filter { !$0.isDeleted }
        var combinedData = Data()

        let rawTable = job.order.tableSession?.table?.tableNumber
        let tableLabel: String = {
            guard let rawTable, !rawTable.isEmpty, rawTable.uppercased() != "QUICK" else { return "Takeaway" }
            return rawTable
        }()
        let queueNum = job.order.queueNumber ?? ""

        for (index, item) in items.enumerated() {
            let stickerBytes = TSPLBuilder.buildSticker(
                item: item,
                tableLabel: tableLabel,
                queueNumber: queueNum,
                cupIndex: index + 1,
                totalCups: items.count,
                template: job.template
            )
            combinedData.append(stickerBytes)
        }
        return combinedData
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Legacy ESC/POS Byte Builder
// ─────────────────────────────────────────────────────────────────────────────
enum ESCPOSBuilder {
    private static let ESC: UInt8  = 0x1B
    private static let GS: UInt8   = 0x1D
    private static let LF: UInt8   = 0x0A
    private static let INIT: [UInt8]          = [0x1B, 0x40]
    private static let ALIGN_CENTER: [UInt8]  = [0x1B, 0x61, 0x01]
    private static let ALIGN_LEFT: [UInt8]    = [0x1B, 0x61, 0x00]
    private static let BOLD_ON: [UInt8]       = [0x1B, 0x45, 0x01]
    private static let BOLD_OFF: [UInt8]      = [0x1B, 0x45, 0x00]
    private static let DOUBLE_HEIGHT_ON: [UInt8]  = [0x1B, 0x21, 0x10]
    private static let DOUBLE_HEIGHT_OFF: [UInt8] = [0x1B, 0x21, 0x00]
    private static let DOUBLE_SIZE_ON: [UInt8]    = [0x1B, 0x21, 0x30]
    private static let DOUBLE_SIZE_OFF: [UInt8]   = [0x1B, 0x21, 0x00]
    private static let CUT: [UInt8]           = [0x1D, 0x56, 0x42, 0x00]
    private static let FEED_3: [UInt8]        = [0x1B, 0x64, 0x03]

    static func buildReceipt(
        order: Order,
        template: ReceiptTemplate?,
        logoBitmap: ESCPOSBuilder.LogoBitmap? = nil,
        emulation: String = "escpos",
        paperWidth: String? = nil
    ) -> Data {
        var b = buf(emulation: emulation)
        let paperWidthStr = paperWidth ?? template?.paperWidth ?? "80mm"
        let width = (paperWidthStr == "58mm") ? 32 : 42

        let showLogo = (template?.showLogo ?? true) && (UserDefaults.standard.object(forKey: "show_logo_on_receipt") as? Bool ?? true)
        let showTaxId = template?.showTaxId ?? true
        let showCustomerInfo = template?.showCustomerInfo ?? true
        let showServiceCharge = template?.showServiceCharge ?? true
        let showTableInfo = template?.showTableInfo ?? true
        let showOrderType = template?.showOrderType ?? true
        let showItemModifiers = template?.showItemModifiers ?? true

        let storeName = UserDefaults.standard.string(forKey: "store_name") ?? "AlphaPos Restaurant"
        let storePhone = UserDefaults.standard.string(forKey: "store_phone") ?? "02-123-4567"
        let storeAddress = UserDefaults.standard.string(forKey: "store_address") ?? "123 Sukhumvit Rd, Bangkok"
        let storeTaxId = UserDefaults.standard.string(forKey: "store_tax_id") ?? ""
        let storeBranchCode = UserDefaults.standard.string(forKey: "store_branch_code") ?? "00000"
        let configuredTaxType = UserDefaults.standard.string(forKey: "store_tax_type") ?? "inclusive"
        let documentType = ReceiptDocumentType(rawValue: order.receiptDocumentType) ?? .receipt
        let isTaxInvoice = documentType.isTaxInvoice
        let documentNumber = order.receiptNumber?.trimmingCharacters(in: .whitespacesAndNewlines)
        let issuedAt = order.payments
            .filter { !$0.isDeleted && $0.status == "completed" }
            .map(\.paidAt)
            .max() ?? order.createdAt

        let validationErrors = ReceiptValidation.sellerErrors(
            documentType: documentType,
            storeName: storeName,
            address: storeAddress,
            taxId: storeTaxId,
            branchCode: storeBranchCode,
            documentNumber: documentNumber ?? ""
        )
        let exclusiveTax = order.taxLines.filter { !$0.isDeleted && !$0.isInclusive }.reduce(0) { $0 + $1.taxAmount }
        let expectedTotal = order.subtotal + order.serviceCharge - order.discount
            + (order.taxLines.isEmpty && configuredTaxType != "inclusive" ? order.tax : exclusiveTax)
        guard validationErrors.isEmpty, abs(expectedTotal - order.total) < 0.011 else { return Data() }

        // ── Store Header (Centered) ──────────────────────────────────
        b += ALIGN_CENTER
        if let header = resolvedHeader(template) {
            b += text("\(header)\n")
        }

        if showLogo {
            if let logo = logoBitmap {
                b += rasterImage(logo)
            }
        }
        b += BOLD_ON + text("\(storeName)\n") + BOLD_OFF
        for addressLine in receiptLines(storeAddress, width: width, maxLines: 2) {
            b += text("\(addressLine)\n")
        }
        b += text("TEL: \(storePhone)\n")
        if showTaxId && !storeTaxId.isEmpty {
            b += text("TAX ID: \(storeTaxId)  BRANCH: \(storeBranchCode)\n")
        }
        b += BOLD_ON + text("\(documentType.thaiTitle)\n") + BOLD_OFF
        if showTableInfo, let headerTag = PlatformOrderNumber.receiptHeaderDisplay(
            orderType: order.orderType,
            platformOrderNumber: order.platformOrderNumber,
            queueNumber: order.queueNumber
        ) {
            b += BOLD_ON + DOUBLE_SIZE_ON + text("\(headerTag)\n") + DOUBLE_SIZE_OFF + BOLD_OFF
        }
        if order.receiptPrintCount > 0 {
            b += BOLD_ON + text("สำเนา / REPRINT #\(order.receiptPrintCount + 1)\n") + BOLD_OFF
        }
        b += text(divider("-", width: width))

        // ── Customer & Order Metadata ────────────────────────────────
        b += ALIGN_LEFT
        if showCustomerInfo {
            if let customer = order.customer {
                let tier = customer.membershipTier.uppercased()
                b += text("ลูกค้า (Customer): \(customer.name) (\(tier))\n")
                if let tId = customer.taxId, !tId.isEmpty { b += text("TAX ID ลูกค้า: \(tId)\n") }
            } else {
                b += text("ลูกค้า: ลูกค้าทั่วไป (Walk-in)\n")
            }
            b += text(divider("-", width: width))
        }

        let df = dateFormatter()
        b += text("วันที่ (Date): \(df.string(from: issuedAt))\n")
        if let documentNumber, !documentNumber.isEmpty {
            b += text("\(isTaxInvoice ? "เลขที่ใบกำกับภาษี" : "เลขที่ใบเสร็จ"): \(documentNumber)\n")
        }
        b += text("ออเดอร์ (Order): \(order.orderNumber)\n")

        if showTableInfo {
            if let table = order.tableSession?.table?.tableNumber,
               !table.isEmpty,
               table.uppercased() != "QUICK" {
                b += text("โต๊ะ (Table): \(table)\n")
            }
        }

        if showOrderType {
            let typeThai: String
            switch order.orderType.lowercased() {
            case "dine_in": typeThai = "ทานที่ร้าน (Dine-In)"
            case "take_out", "takeaway": typeThai = "สั่งกลับบ้าน (Take Away)"
            case "delivery": typeThai = "เดลิเวอรี (Delivery)"
            default: typeThai = order.orderType.uppercased()
            }
            b += text("ประเภท: \(typeThai)  |  จำนวน: \(order.guestCount) ท่าน\n")
            if let brand = order.deliveryBrand, !brand.isEmpty {
                b += text("แพลตฟอร์ม: \(brand)\n")
            }
            if let platform = order.platformOrderNumber, !platform.isEmpty {
                b += text("PF ORDER: \(platform)\n")
            }
        }

        let cashier = order.cashierName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cashier.isEmpty && cashier.lowercased() != "staff" {
            b += text("พนักงาน (Cashier): \(cashier)\n")
        }
        b += text(divider("-", width: width))

        // ── Line Items ───────────────────────────────────────────────
        b += ALIGN_LEFT
        b += text(lineItemHeader(width: width))
        b += text(divider("-", width: width))

        for item in order.items.filter({
            !$0.isDeleted && $0.status != "cancelled" && $0.status != "refunded"
        }) {
            let name = item.menuItem?.name ?? item.itemName
            let price = String(format: "%.2f", item.unitPrice * Double(item.quantity))
            b += BOLD_ON + text(lineItem(name, qty: item.quantity, price: price, width: width)) + BOLD_OFF
            b += text("  \(item.quantity) x \(String(format: "%.2f", item.unitPrice)) THB\n")

            if showItemModifiers {
                for mod in item.modifiers.filter({ !$0.isDeleted }) {
                    let modName = mod.modifier?.name ?? ""
                    let modPrice = mod.price > 0 ? String(format: "+%.2f", mod.price) : ""
                    b += text("  + \(modName) \(modPrice)\n")
                }
                if let notes = item.notes, !notes.isEmpty { b += text("  (\(notes))\n") }
            }
        }

        // ── Totals & Financial Summary ───────────────────────────────
        b += text(divider("-", width: width))
        b += text(lineTotal("ยอดรวม (SUBTOTAL)", value: order.subtotal, width: width))
        if showServiceCharge && order.serviceCharge > 0 { b += text(lineTotal("ค่าบริการ (SERVICE)", value: order.serviceCharge, width: width)) }
        if order.discount > 0 { b += text(lineTotal("ส่วนลด (DISCOUNT)", value: -order.discount, width: width)) }
        for taxLine in order.taxLines.filter({ !$0.isDeleted }).sorted(by: { $0.taxRate < $1.taxRate }) {
            let taxLabel = String(format: "ภาษี VAT %.2g%% %@", taxLine.taxRate, taxLine.isInclusive ? "(INCL)" : "")
            b += text(lineTotal("ฐานภาษี (TAX BASE)", value: taxLine.taxableAmount, width: width))
            b += text(lineTotal(taxLabel, value: taxLine.taxAmount, width: width))
        }
        if isTaxInvoice { b += text("ราคารวมภาษีมูลค่าเพิ่มแล้ว (VAT Included)\n") }
        b += text(divider("-", width: width))

        // GRAND TOTAL
        b += BOLD_ON + text(lineTotal("ยอดรวมสุทธิ (TOTAL)", value: order.total, width: width)) + BOLD_OFF
        b += text(divider("-", width: width))

        // ── Payment & Change Breakdown ───────────────────────────────
        b += ALIGN_LEFT
        let activePayments = order.payments.filter { !$0.isDeleted && $0.status == "completed" }
        if activePayments.isEmpty {
            b += ALIGN_CENTER + BOLD_ON + text("ชำระเงินแล้ว (PAID)\n") + BOLD_OFF + ALIGN_LEFT
        } else {
            for payment in activePayments {
                let methodLabel = paymentMethodLabel(payment.paymentMethod)
                b += text(lineTotal("ชำระโดย (\(methodLabel))", value: payment.amount, width: width))
                if let tendered = payment.cashTenderedAmount {
                    let change = max(0, tendered - payment.amount)
                    b += text(lineTotal("  รับเงินมา (TENDERED)", value: tendered, width: width))
                    b += text(lineTotal("  เงินทอน (CHANGE)", value: change, width: width))
                } else if payment.paymentMethod.lowercased().contains("cash") {
                    b += text(lineTotal("  รับเงินมา (TENDERED)", value: payment.amount, width: width))
                    b += text(lineTotal("  เงินทอน (CHANGE)", value: 0.0, width: width))
                }
                if let ref = maskedPaymentReference(payment.transactionReference) {
                    b += text("  รหัสอ้างอิง (REF): \(ref)\n")
                }
            }
        }

        // ── Enhanced Footer ──────────────────────────────────────────
        b += text(divider("-", width: width))
        b += ALIGN_CENTER
        b += BOLD_ON + text("ขอบคุณที่ใช้บริการ\nTHANK YOU FOR YOUR PATRONAGE\n") + BOLD_OFF
        b += text("โปรดตรวจสอบรายการและเงินทอนก่อนออกจากร้าน\n")

        if let footer = resolvedFooter(template) {
            b += text(divider("-", width: width)) + text("\(footer)\n")
        }

        b += FEED_3 + cutSequence(emulation: emulation)
        return Data(b)
    }

    static func buildPreBill(
        orders: [Order],
        template: ReceiptTemplate?,
        logoBitmap: ESCPOSBuilder.LogoBitmap? = nil,
        emulation: String = "escpos",
        paperWidth: String? = nil
    ) -> Data {
        var b = buf(emulation: emulation)
        let paperWidthStr = paperWidth ?? template?.paperWidth ?? "80mm"
        let width = (paperWidthStr == "58mm") ? 32 : 42

        let showLogo = (template?.showLogo ?? true) && (UserDefaults.standard.object(forKey: "show_logo_on_receipt") as? Bool ?? true)
        let showTableInfo = template?.showTableInfo ?? true
        let showOrderType = template?.showOrderType ?? true
        let showItemModifiers = template?.showItemModifiers ?? true
        let showQRCode = template?.showQRCode ?? true

        let storeName = UserDefaults.standard.string(forKey: "store_name") ?? "AlphaPos Restaurant"
        let storePhone = UserDefaults.standard.string(forKey: "store_phone") ?? "02-123-4567"
        let storeAddress = UserDefaults.standard.string(forKey: "store_address") ?? "123 Sukhumvit Rd, Bangkok"
        let promptPayNumber = UserDefaults.standard.string(forKey: "promptpay_number") ?? ""

        let activeOrders = orders.filter { !$0.isDeleted }
        let allItems = activeOrders.flatMap { $0.items }.filter { !$0.isDeleted }
        let subtotal = activeOrders.reduce(0.0) { $0 + $1.subtotal }
        let tax = activeOrders.reduce(0.0) { $0 + $1.tax }
        let serviceCharge = activeOrders.reduce(0.0) { $0 + $1.serviceCharge }
        let discount = activeOrders.reduce(0.0) { $0 + $1.discount }
        let total = activeOrders.reduce(0.0) { $0 + $1.outstandingAmount }

        b += ALIGN_CENTER
        if let header = resolvedHeader(template) {
            b += text("\(header)\n")
        }
        if showLogo, let logo = logoBitmap {
            b += rasterImage(logo)
        }
        b += BOLD_ON + text("\(storeName)\n") + BOLD_OFF
        for addressLine in receiptLines(storeAddress, width: width, maxLines: 2) {
            b += text("\(addressLine)\n")
        }
        b += text("TEL: \(storePhone)\n")
        b += text(divider("-", width: width))
        b += BOLD_ON + DOUBLE_HEIGHT_ON + text("PRE-BILL / CHECK\n") + DOUBLE_HEIGHT_OFF + BOLD_OFF
        b += text("NOT TAX INVOICE\n")
        b += text("UNPAID - FOR CUSTOMER REVIEW\n")
        b += text(divider("-", width: width))

        b += ALIGN_LEFT
        let df = dateFormatter()
        b += text("DATE : \(df.string(from: Date()))\n")
        if let first = activeOrders.first {
            b += text("ORDER: \(activeOrders.map { $0.orderNumber }.joined(separator: ", "))\n")

            if showTableInfo {
                var tableLine = ""
                if let table = first.tableSession?.table?.tableNumber,
                   !table.isEmpty,
                   table.uppercased() != "QUICK" {
                    tableLine += "TABLE: \(table)  "
                }
                if let q = first.queueNumber, !q.isEmpty { tableLine += "QUEUE: #\(q)" }
                if !tableLine.isEmpty { b += text("\(tableLine)\n") }
            }

            if showOrderType {
                b += text("TYPE : \(first.orderType.uppercased())  |  GUESTS: \(first.guestCount)\n")
            }
        }
        b += text(divider("-", width: width))

        b += text(lineItemHeader(width: width))
        b += text(divider("-", width: width))

        for item in allItems {
            let name = item.menuItem?.name ?? item.itemName
            let price = String(format: "%.2f", item.unitPrice * Double(item.quantity))
            b += BOLD_ON + text(lineItem(name.isEmpty ? "Item" : name, qty: item.quantity, price: price, width: width)) + BOLD_OFF

            if showItemModifiers {
                for mod in item.modifiers.filter({ !$0.isDeleted }) {
                    let modName = mod.modifier?.name ?? ""
                    let modPrice = mod.price > 0 ? String(format: "+%.2f", mod.price) : ""
                    b += text("  + \(modName) \(modPrice)\n")
                }
                if let notes = item.notes, !notes.isEmpty { b += text("  (\(notes))\n") }
            }
        }

        b += text(divider("-", width: width))
        b += text(lineTotal("SUBTOTAL", value: subtotal, width: width))
        if tax > 0 {
            let taxRate = UserDefaults.standard.object(forKey: "store_tax_rate") as? Double ?? 7.0
            let taxType = UserDefaults.standard.string(forKey: "store_tax_type") ?? "inclusive"
            let taxLabel = String(format: "%.0f%% VAT (%@)", taxRate, taxType.uppercased())
            b += text(lineTotal(taxLabel, value: tax, width: width))
        }
        if serviceCharge > 0 { b += text(lineTotal("SERVICE CHARGE", value: serviceCharge, width: width)) }
        if discount > 0 { b += text(lineTotal("DISCOUNT", value: -discount, width: width)) }
        b += text(divider("-", width: width))
        b += BOLD_ON + DOUBLE_HEIGHT_ON + text(lineTotal("AMOUNT DUE", value: total, width: width)) + DOUBLE_HEIGHT_OFF + BOLD_OFF
        b += text(divider("-", width: width))
        b += ALIGN_CENTER + text("Please review your order.\nPayment has not been received.\n")

        if showQRCode && !promptPayNumber.isEmpty {
            b += text("\nSCAN TO PAY - PROMPTPAY\n")
            let payload = buildPromptPayPayload(target: promptPayNumber, amount: total)
            b += qrCode(payload, moduleSize: 8) + text("\nPromptPay: \(promptPayNumber)\n")
        }

        if let footer = resolvedFooter(template) {
            b += text(divider("-", width: width)) + text("\(footer)\n")
        }

        b += FEED_3 + cutSequence(emulation: emulation)
        return Data(b)
    }

    /// Pre-bill renderer for a Quick Service cart that has not been persisted
    /// as an Order yet. It carries the same customer-facing totals and locked
    /// PromptPay payload without creating a sale or deducting inventory.
    static func buildPreBill(
        draft: PreBillDraft,
        template: ReceiptTemplate?,
        logoBitmap: ESCPOSBuilder.LogoBitmap? = nil,
        emulation: String = "escpos",
        paperWidth: String? = nil
    ) -> Data {
        var b = buf(emulation: emulation)
        let paperWidthStr = paperWidth ?? template?.paperWidth ?? "80mm"
        let width = paperWidthStr == "58mm" ? 32 : 42
        let showLogo = (template?.showLogo ?? true) &&
            (UserDefaults.standard.object(forKey: "show_logo_on_receipt") as? Bool ?? true)
        let showModifiers = template?.showItemModifiers ?? true
        let showQRCode = template?.showQRCode ?? true
        let storeName = UserDefaults.standard.string(forKey: "store_name") ?? "AlphaPos Restaurant"
        let storePhone = UserDefaults.standard.string(forKey: "store_phone") ?? "02-123-4567"
        let storeAddress = UserDefaults.standard.string(forKey: "store_address") ?? ""
        let promptPayNumber = UserDefaults.standard.string(forKey: "promptpay_number") ?? ""

        b += ALIGN_CENTER
        if let header = resolvedHeader(template) { b += text("\(header)\n") }
        if showLogo, let logoBitmap { b += rasterImage(logoBitmap) }
        b += BOLD_ON + text("\(storeName)\n") + BOLD_OFF
        for line in receiptLines(storeAddress, width: width, maxLines: 2) { b += text("\(line)\n") }
        b += text("TEL: \(storePhone)\n")
        b += text(divider("-", width: width))
        b += BOLD_ON + DOUBLE_HEIGHT_ON + text("PRE-BILL / CHECK\n") + DOUBLE_HEIGHT_OFF + BOLD_OFF
        b += text("NOT TAX INVOICE\nUNPAID - FOR CUSTOMER REVIEW\n")
        b += text(divider("-", width: width))
        b += ALIGN_LEFT
        b += text("DATE : \(dateFormatter().string(from: Date()))\n")
        b += text("ORDER: \(draft.orderReference)\n")
        b += text("TYPE : \(draft.orderType.uppercased())  |  GUESTS: \(draft.guestCount)\n")
        b += text(divider("-", width: width))
        b += text(lineItemHeader(width: width))
        b += text(divider("-", width: width))

        for item in draft.items {
            let price = String(format: "%.2f", item.unitPrice * Double(item.quantity))
            b += BOLD_ON + text(lineItem(item.name.isEmpty ? "Item" : item.name, qty: item.quantity, price: price, width: width)) + BOLD_OFF
            if showModifiers {
                for modifier in item.modifiers {
                    let priceText = modifier.price > 0 ? String(format: "+%.2f", modifier.price) : ""
                    b += text("  + \(modifier.name) \(priceText)\n")
                }
                if !item.notes.isEmpty { b += text("  (\(item.notes))\n") }
            }
        }

        b += text(divider("-", width: width))
        b += text(lineTotal("SUBTOTAL", value: draft.subtotal, width: width))
        if draft.tax > 0 { b += text(lineTotal("VAT", value: draft.tax, width: width)) }
        if draft.serviceCharge > 0 { b += text(lineTotal("SERVICE CHARGE", value: draft.serviceCharge, width: width)) }
        if draft.discount > 0 { b += text(lineTotal("DISCOUNT", value: -draft.discount, width: width)) }
        b += text(divider("-", width: width))
        b += BOLD_ON + DOUBLE_HEIGHT_ON + text(lineTotal("AMOUNT DUE", value: draft.total, width: width)) + DOUBLE_HEIGHT_OFF + BOLD_OFF
        b += text(divider("-", width: width))
        b += ALIGN_CENTER + text("Please review your order.\nPayment has not been received.\n")

        if showQRCode && !promptPayNumber.isEmpty {
            b += text("\nSCAN TO PAY - PROMPTPAY\n")
            let payload = buildPromptPayPayload(target: promptPayNumber, amount: draft.total)
            b += qrCode(payload, moduleSize: 8) + text("\nPromptPay: \(promptPayNumber)\n")
        }
        if let footer = resolvedFooter(template) {
            b += text(divider("-", width: width)) + text("\(footer)\n")
        }
        b += FEED_3 + cutSequence(emulation: emulation)
        return Data(b)
    }

    static func buildKitchenTicket(
        order: Order,
        items: [OrderItem],
        stationLabel: String = "KITCHEN",
        template: ReceiptTemplate? = nil,
        emulation: String = "escpos",
        paperWidth: String? = nil
    ) -> Data {
        // XPrinter firmware variants do not share the same ESC/POS code-page
        // table. Render kitchen tickets as a bitmap so Thai text is shaped by
        // iOS and does not depend on the printer ROM.
        if emulation.lowercased() == "xprinter" {
            return buildKitchenTicketRaster(order: order, items: items, stationLabel: stationLabel,
                                            template: template, paperWidth: paperWidth)
        }
        var b = buf(emulation: emulation)
        let paperWidthStr = paperWidth ?? template?.paperWidth ?? "80mm"
        let width = (paperWidthStr == "58mm") ? 32 : 42

        let showTableInfo = template?.showTableInfo ?? true
        let showOrderType = template?.showOrderType ?? true
        let showItemModifiers = template?.showItemModifiers ?? true

        b += ALIGN_CENTER + BOLD_ON + DOUBLE_SIZE_ON + text("[ \(stationLabel) ]\n") + DOUBLE_SIZE_OFF + BOLD_OFF + ALIGN_LEFT

        let df = timeFormatter()
        b += text("Time : \(df.string(from: order.createdAt))\nORDER: \(order.orderNumber)\n")

        if showTableInfo {
            if let table = order.tableSession?.table?.tableNumber,
               !table.isEmpty,
               table.uppercased() != "QUICK" {
                b += text("Table: \(table)\n")
            }
            if let q = order.queueNumber, !q.isEmpty { b += text("Queue: #\(q)\n") }
        }
        if showOrderType { b += text("Type : \(order.orderType.uppercased())\n") }
        b += text(divider("-", width: width))

        if let customHeader = template?.headerText, !customHeader.isEmpty {
            b += ALIGN_CENTER + BOLD_ON + text("\(customHeader)\n") + ALIGN_LEFT + BOLD_OFF + text(divider("-", width: width))
        }

        for item in items {
            let name = item.menuItem?.name ?? "Item"
            b += BOLD_ON + text(wrappedPrepLine(quantity: item.quantity, name: name, width: width)) + BOLD_OFF

            if showItemModifiers {
                for mod in item.modifiers.filter({ !$0.isDeleted }) {
                    b += text(wrappedIndentedLine(prefix: "  >> ", value: mod.modifier?.name ?? "", width: width))
                }
                if let notes = item.notes, !notes.isEmpty {
                    b += text(wrappedIndentedLine(prefix: "  ** ", value: notes, width: width))
                }
            }
        }

        if let customFooter = template?.footerText, !customFooter.isEmpty {
            b += text(divider("-", width: width)) + ALIGN_CENTER + BOLD_ON + text("\(customFooter)\n") + ALIGN_LEFT + BOLD_OFF
        }

        b += FEED_3 + CUT
        return Data(b)
    }

    private static func buildKitchenTicketRaster(
        order: Order, items: [OrderItem], stationLabel: String,
        template: ReceiptTemplate?, paperWidth: String?
    ) -> Data {
        let paperWidthStr = paperWidth ?? template?.paperWidth ?? "80mm"
        let width = paperWidthStr == "58mm" ? 384 : 576
        let charWidth = paperWidthStr == "58mm" ? 32 : 42
        let showTableInfo = template?.showTableInfo ?? true
        let showOrderType = template?.showOrderType ?? true
        let showItemModifiers = template?.showItemModifiers ?? true
        var lines = ["[ \(stationLabel) ]", ""]
        let df = timeFormatter()
        lines += ["Time : \(df.string(from: order.createdAt))", "ORDER: \(order.orderNumber)"]
        if showTableInfo {
            if let table = order.tableSession?.table?.tableNumber, !table.isEmpty, table.uppercased() != "QUICK" { lines.append("Table: \(table)") }
            if let q = order.queueNumber, !q.isEmpty { lines.append("Queue: #\(q)") }
        }
        if showOrderType { lines.append("Type : \(order.orderType.uppercased())") }
        lines.append(String(divider("-", width: charWidth).dropLast()))
        if let header = template?.headerText, !header.isEmpty { lines.append(header); lines.append(String(divider("-", width: charWidth).dropLast())) }
        for item in items {
            lines.append(contentsOf: wrappedPrepLine(quantity: item.quantity, name: item.menuItem?.name ?? "Item", width: charWidth).split(separator: "\n", omittingEmptySubsequences: false).map(String.init))
            if showItemModifiers {
                for mod in item.modifiers.filter({ !$0.isDeleted }) { lines.append(contentsOf: wrappedIndentedLine(prefix: "  >> ", value: mod.modifier?.name ?? "", width: charWidth).split(separator: "\n", omittingEmptySubsequences: false).map(String.init)) }
                if let notes = item.notes, !notes.isEmpty { lines.append(contentsOf: wrappedIndentedLine(prefix: "  ** ", value: notes, width: charWidth).split(separator: "\n", omittingEmptySubsequences: false).map(String.init)) }
            }
        }
        if let footer = template?.footerText, !footer.isEmpty { lines.append(String(divider("-", width: charWidth).dropLast())); lines.append(footer) }
        guard let bitmap = textBitmap(lines.joined(separator: "\n"), width: width) else { return Data(INIT + text(lines.joined(separator: "\n") + "\n") + FEED_3 + CUT) }
        return Data(INIT + rasterImage(bitmap) + FEED_3 + CUT)
    }

    static func buildItemLabel(
        item: OrderItem,
        tableLabel: String,
        queueNumber: String,
        cupIndex: Int,
        totalCups: Int,
        template: ReceiptTemplate?,
        emulation: String
    ) -> Data {
        var b = buf(emulation: emulation)
        let paperWidthStr = template?.paperWidth ?? "80mm"
        let width = (paperWidthStr == "58mm") ? 32 : 42

        let showTable = template?.showTableInfo ?? true
        let showMods = template?.showItemModifiers ?? true
        let showQueue = template?.showOrderType ?? true

        b += INIT

        // Header
        b += ALIGN_CENTER + BOLD_ON + text("[ LABEL TICKET ]\n") + BOLD_OFF

        var headerInfo = ""
        if showTable {
            headerInfo += "Table: \(tableLabel)  "
        }
        headerInfo += "Item: \(cupIndex)/\(totalCups)\n"
        b += text(headerInfo)

        if showQueue && !queueNumber.isEmpty {
            b += text("Queue: #\(queueNumber)\n")
        }
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        let timeStr = df.string(from: Date())
        b += text("Time: \(timeStr)\n")
        b += text(divider("-", width: width))




        // Item Name
        let name = item.menuItem?.name ?? "Item"
        b += ALIGN_LEFT + BOLD_ON + DOUBLE_HEIGHT_ON + text("x\(item.quantity) \(name)\n") + DOUBLE_HEIGHT_OFF + BOLD_OFF

        // Modifiers & Notes
        if showMods {
            let activeMods = item.modifiers.filter { !$0.isDeleted }
            for mod in activeMods {
                b += text("  >> \(mod.modifier?.name ?? "")\n")
            }
            if let notes = item.notes, !notes.isEmpty {
                b += text("  ** \(notes)\n")
            }
        }

        b += text(divider("-", width: width))
        b += FEED_3 + CUT
        return Data(b)
    }

    /// สร้าง sample logo bitmap สำหรับ Test Print เมื่อไม่มี store_logo_path
    /// วาด store name initials + border frame เป็น 1-bit bitmap จริง
    static func buildSampleLogoBitmap(storeName: String, maxWidthDots: Int = 200) -> LogoBitmap? {
        // ขนาด logo: 160×48 dots สำหรับ 80mm, 120×36 สำหรับ 58mm
        let logoW = maxWidthDots <= 150 ? 120 : 160
        let logoH = maxWidthDots <= 150 ? 36  : 48

        // ใช้ UIGraphicsImageRenderer วาด initials ใน rounded box
        let size = CGSize(width: logoW, height: logoH)
        let fmt  = UIGraphicsImageRendererFormat()
        fmt.scale = 1; fmt.opaque = false

        let uiImg = UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            let cgCtx = ctx.cgContext
            let rect  = CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2)

            // พื้นหลังขาว
            cgCtx.setFillColor(UIColor.white.cgColor)
            cgCtx.fill(CGRect(origin: .zero, size: size))

            // กรอบดำ
            cgCtx.setStrokeColor(UIColor.black.cgColor)
            cgCtx.setLineWidth(2)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 4)
            path.stroke()

            // ข้อความ initials ตรงกลาง (ใช้ initials 2 ตัวแรก หรือ "AP" ถ้าว่าง)
            let raw      = storeName.trimmingCharacters(in: .whitespaces)
            let words    = raw.components(separatedBy: " ").filter { !$0.isEmpty }
            let initials: String
            if words.count >= 2 {
                initials = String(words[0].prefix(1)) + String(words[1].prefix(1))
            } else if !raw.isEmpty {
                initials = String(raw.prefix(2)).uppercased()
            } else {
                initials = "AP"
            }

            let fontSize  = CGFloat(logoH) * 0.55
            let font      = UIFont.boldSystemFont(ofSize: fontSize)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.black,
            ]
            let textSize  = (initials as NSString).size(withAttributes: attrs)
            let textX     = (size.width  - textSize.width)  / 2
            let textY     = (size.height - textSize.height) / 2
            (initials as NSString).draw(at: CGPoint(x: textX, y: textY), withAttributes: attrs)
        }

        return imageTo1BitBitmap(uiImg, maxWidthDots: logoW)
    }

    // ── Test Page Builders ───────────────────────────────────────────────────
    static func buildTestReceipt(printer: Printer, template: ReceiptTemplate?, logoBitmap: ESCPOSBuilder.LogoBitmap? = nil, emulation: String = "escpos") -> Data {
        var b = buf(emulation: emulation)
        let paperWidthStr = printer.paperWidth
        let width = (paperWidthStr == "58mm") ? 32 : 42

        let storeName = UserDefaults.standard.string(forKey: "store_name") ?? "AlphaPos Restaurant"
        let storePhone = UserDefaults.standard.string(forKey: "store_phone") ?? "02-123-4567"
        let storeAddress = UserDefaults.standard.string(forKey: "store_address") ?? "123 Sukhumvit Rd, Bangkok"
        let storeTaxId = UserDefaults.standard.string(forKey: "store_tax_id") ?? ""
        let storeBranchCode = UserDefaults.standard.string(forKey: "store_branch_code") ?? "00000"
        let configuredTaxType = UserDefaults.standard.string(forKey: "store_tax_type") ?? "inclusive"
        let isTaxInvoice = configuredTaxType == "inclusive" && ReceiptComplianceGate.canIssueAbbreviatedTaxInvoice(
            vatEnabled: UserDefaults.standard.bool(forKey: "enable_tax"),
            taxId: storeTaxId
        )
        // ── Mirror ทุก toggle เหมือน buildReceipt ──────────────────────
        let showLogo          = (template?.showLogo          ?? true) && (UserDefaults.standard.object(forKey: "show_logo_on_receipt") as? Bool ?? true)
        let showTaxId         = template?.showTaxId         ?? true
        let showCustomerInfo  = template?.showCustomerInfo  ?? true
        let showServiceCharge = template?.showServiceCharge ?? true
        let showTableInfo     = template?.showTableInfo     ?? true
        let showOrderType     = template?.showOrderType     ?? true
        let showItemModifiers = template?.showItemModifiers ?? true

        // ── Header text ──────────────────────────────────────────────────
        if let header = resolvedHeader(template) {
            b += ALIGN_CENTER + text("\(header)\n")
        }

        // ── Store header (CENTER — เหมือน buildReceipt) ──────────────────
        b += ALIGN_CENTER
        if showLogo {
            if let logo = logoBitmap {
                b += rasterImage(logo)
            } else {
                // ไม่มี store logo จริง → สร้าง sample logo จาก store name initials
                if let sampleLogo = buildSampleLogoBitmap(storeName: storeName, maxWidthDots: width == 32 ? 120 : 160) {
                    b += rasterImage(sampleLogo)
                }
            }
        }
        b += BOLD_ON + text("\(storeName)\n") + BOLD_OFF
        for addressLine in receiptLines(storeAddress, width: width, maxLines: 2) {
            b += text("\(addressLine)\n")
        }
        b += text("TEL: \(storePhone)\n")
        b += BOLD_ON + text(isTaxInvoice ? "ใบกำกับภาษีอย่างย่อ\n" : "ใบเสร็จรับเงิน\n") + BOLD_OFF
        if showTableInfo {
            b += BOLD_ON + DOUBLE_SIZE_ON + text("คิวที่ #32\n") + DOUBLE_SIZE_OFF + BOLD_OFF
        }
        b += text(divider("-", width: width))

        // ── Tax ID (LEFT — เหมือน buildReceipt) ─────────────────────────
        if showTaxId && isTaxInvoice {
            b += ALIGN_LEFT
            if width == 32 {
                b += text("TAX ID: \(storeTaxId)\nBRANCH: \(storeBranchCode)\n")
            } else {
                b += text("TAX ID: \(storeTaxId)  BR: \(storeBranchCode)\n")
            }
            b += text(divider("-", width: width))
        }

        // ── Customer info sample (เหมือน buildReceipt showCustomerInfo) ─
        if showCustomerInfo {
            b += ALIGN_LEFT
            b += text("CUSTOMER : Somchai V. (Member)\n")
            b += text("CUSTOMER TAX ID: 0105559876543\n")
            b += text(divider("-", width: width))
        }

        // ── Order info sample (LEFT — เหมือน buildReceipt) ───────────────
        b += ALIGN_LEFT
        b += text("ISSUED: \(dateFormatter().string(from: Date())) ICT\n")
        b += text("RECEIPT NO.: RCP-20260622-0001\n")
        b += text("ORDER: #AP-102546-CN\n")
        if showTableInfo {
            b += text("TABLE: Table 08 (Zone A)\n")
        }
        if showOrderType {
            b += text("TYPE : DINE-IN  |  GUESTS: 3\n")
        }
        b += text(divider("-", width: width))

        // ── Items header (LEFT) ──────────────────────────────────────────
        b += ALIGN_LEFT
        b += text(lineItemHeader(width: width))
        b += text(divider("-", width: width))

        // ── Sample items — ตรงกับ ReceiptLivePreview ────────────────────
        struct SampleItem { let name: String; let qty: Int; let price: Double; let mods: [String] }
        let sampleItems = [
            SampleItem(name: "Premium Beef Burger", qty: 2, price: 220.00,
                       mods: ["Extra Cheese (x2) (+฿40)", "Medium Rare"]),
            SampleItem(name: "Crispy French Fries",  qty: 1, price: 120.00,
                       mods: ["Spicy Seasoning"]),
            SampleItem(name: "Matcha Latte (Oat)",   qty: 2, price: 110.00,
                       mods: ["Sweet 50% (x2)", "Oat Milk (+฿30)"]),
        ]
        for item in sampleItems {
            let price = String(format: "%.2f", item.price * Double(item.qty))
            b += BOLD_ON + text(lineItem(item.name, qty: item.qty, price: price, width: width)) + BOLD_OFF
            if showItemModifiers {
                for mod in item.mods { b += text("  + \(mod)\n") }
            }
        }

        b += text(divider("-", width: width))

        // ── Totals (LEFT — เหมือน buildReceipt) ─────────────────────────
        b += ALIGN_LEFT
        let taxEnabled = UserDefaults.standard.object(forKey: "enable_tax") as? Bool ?? true
        let scEnabled = UserDefaults.standard.object(forKey: "enable_service_charge") as? Bool ?? true
        let testTaxRate = UserDefaults.standard.object(forKey: "store_tax_rate") as? Double ?? 7.0
        let testTaxType = UserDefaults.standard.string(forKey: "store_tax_type") ?? "inclusive"
        let sampleCalculation = ReceiptCalculationEngine.calculate(.init(
            lines: [
                .init(id: "burger", name: "Premium Beef Burger", quantity: 2, unitPrice: 220, taxRate: taxEnabled ? Decimal(testTaxRate) : 0, taxInclusive: testTaxType == "inclusive"),
                .init(id: "fries", name: "Crispy French Fries", quantity: 1, unitPrice: 120, taxRate: taxEnabled ? Decimal(testTaxRate) : 0, taxInclusive: testTaxType == "inclusive"),
                .init(id: "latte", name: "Matcha Latte (Oat)", quantity: 2, unitPrice: 110, taxRate: taxEnabled ? Decimal(testTaxRate) : 0, taxInclusive: testTaxType == "inclusive")
            ], discount: 39, serviceChargeRate: 10,
            serviceChargeEnabled: showServiceCharge && scEnabled,
            serviceChargeTaxable: true,
            serviceChargeTaxRate: taxEnabled ? Decimal(testTaxRate) : 0,
            serviceChargeTaxInclusive: testTaxType == "inclusive",
            customerTaxExempt: false, roundingMode: .perLine
        ))
        let testTax = NSDecimalNumber(decimal: sampleCalculation.tax).doubleValue
        let testTotal = NSDecimalNumber(decimal: sampleCalculation.total).doubleValue
        let totalStr = String(format: "%.2f", testTotal)

        b += text(lineTotal("ยอดรวม (SUBTOTAL)",             value: "780.00",  width: width))
        if showServiceCharge && scEnabled {
            b += text(lineTotal("ค่าบริการ (SERVICE 10%)", value: "78.00",  width: width))
        }
        b += text(lineTotal("ส่วนลด (DISCOUNT)",     value: "-39.00",  width: width))
        if taxEnabled {
            let sampleTaxLabel = testTaxType == "inclusive"
                ? String(format: "ภาษี VAT %.0f%% (INCLUDED)", testTaxRate)
                : String(format: "ภาษี VAT %.0f%%", testTaxRate)
            b += text(lineTotal(sampleTaxLabel, value: String(format: "%.2f", testTax), width: width))
            b += text(lineTotal("ฐานภาษี (TAX BASE)", value: NSDecimalNumber(decimal: sampleCalculation.taxableBase).doubleValue, width: width))
        }
        b += text(divider("-", width: width))
        b += BOLD_ON + text(lineTotal("ยอดรวมสุทธิ (TOTAL)", value: totalStr, width: width)) + BOLD_OFF
        b += text(divider("-", width: width))

        // ── Payment confirmation (เหมือน buildReceipt) ─────────────────
        b += ALIGN_LEFT
        b += text(lineTotal("ชำระโดย (เงินสด / CASH)", value: totalStr, width: width))
        b += text(lineTotal("  รับเงินมา (TENDERED)", value: "1000.00", width: width))
        let sampleChange = 1000.00 - (Double(totalStr) ?? 0.0)
        b += text(lineTotal("  เงินทอน (CHANGE)", value: String(format: "%.2f", sampleChange), width: width))
        b += text(divider("-", width: width))

        b += ALIGN_CENTER
        b += BOLD_ON + text("ขอบคุณที่ใช้บริการ\nTHANK YOU FOR YOUR PATRONAGE\n") + BOLD_OFF
        b += text("โปรดตรวจสอบรายการและเงินทอนก่อนออกจากร้าน\n")

        // ── Footer text ──────────────────────────────────────────────────
        if let footer = resolvedFooter(template) {
            b += text(divider("-", width: width)) + ALIGN_CENTER + text("\(footer)\n")
        }

        b += FEED_3 + CUT
        return Data(b)
    }

    static func buildTestKitchenTicket(
        printer: Printer,
        stationLabel: String = "KITCHEN",
        template: ReceiptTemplate? = nil,
        emulation: String = "escpos"
    ) -> Data {
        var b = buf(emulation: emulation)
        let paperWidthStr = template?.paperWidth ?? printer.paperWidth
        let width = (paperWidthStr == "58mm") ? 32 : 42

        let showTableInfo     = template?.showTableInfo     ?? true
        let showItemModifiers = template?.showItemModifiers ?? true

        // ── Station header ───────────────────────────────────────────────
        b += ALIGN_CENTER + BOLD_ON + DOUBLE_SIZE_ON
        b += text("[ \(stationLabel) ]\n")
        b += DOUBLE_SIZE_OFF + BOLD_OFF + ALIGN_LEFT
        b += text(divider("-", width: width))

        // ── Order info ───────────────────────────────────────────────────
        b += text("TIME : \(timeFormatter().string(from: Date()))\n")
        b += text("ORDER: #AP-TEST-001\n")
        if showTableInfo {
            b += text("TABLE: Table 08 (Zone A)\n")
            b += text("QUEUE: #32\n")
        }
        b += text(divider("-", width: width))

        // ── Sample items (สอดคล้องกับ ReceiptLivePreview / kitchenTicketBody) ──
        let isBar = stationLabel.uppercased().contains("BAR")
        let sampleItems: [(name: String, qty: Int, mods: [String], note: String?)] = isBar ? [
            ("Matcha Latte (Oat)",   2, ["Sweet 50% (x2)", "Oat Milk (+฿30)"], nil),
            ("Iced Americano",       1, ["No Sugar", "Extra Shot"],             "น้ำแข็งน้อย"),
            ("Strawberry Smoothie",  1, [],                                     nil),
        ] : [
            ("Premium Beef Burger",  2, ["Extra Cheese (x2)", "Medium Rare"],  nil),
            ("Crispy French Fries",  1, ["Spicy Seasoning"],                   nil),
            ("Tom Yum Soup (large)", 1, [],                                    "ไม่ใส่เห็ด"),
        ]

        for item in sampleItems {
            b += BOLD_ON
            b += text(wrappedPrepLine(quantity: item.qty, name: item.name.uppercased(), width: width))
            b += BOLD_OFF
            if showItemModifiers {
                for mod in item.mods {
                    b += text(wrappedIndentedLine(prefix: "  >> ", value: mod, width: width))
                }
                if let note = item.note {
                    b += text(wrappedIndentedLine(prefix: "  ** ", value: note, width: width))
                }
            }
        }

        b += text(divider("-", width: width))
        b += ALIGN_CENTER + text("* \(stationLabel) TICKET *\n")

        b += FEED_3 + cutSequence(emulation: emulation)
        return Data(b)
    }

    private static func cutSequence(emulation: String) -> [UInt8] {
        if let brand = PrinterBrand(rawValue: emulation.lowercased()) { return brand.cutCommand }
        return [0x1D, 0x56, 0x42, 0x00]
    }

    /// Return the printer initialisation preamble.
    /// ESC/POS: INIT + configurable Thai code table.
    /// Star STAR mode: INIT only — ESC t is "Set Tab Positions" in Star mode and
    /// would consume the following 21 bytes as tab-stop data, corrupting the payload.
    private static func buf(emulation: String = "escpos") -> [UInt8] {
        let isStarMode = emulation.lowercased() == "star"
        // XP-C300H uses ESC/POS Thai Character Code 42 (page 20).
        // Keeping this as a setting allows other ESC/POS firmware variants
        // to override it without changing the renderer.
        let storedPage = UserDefaults.standard.object(forKey: "escpos_thai_code_page") as? Int
        // Version 24 used 21 as the default. Treat that legacy value as the
        // old default for Xprinter so existing installations are corrected
        // without requiring the user to clear app data or reinstall.
        let configuredPage: Int = {
            if emulation.lowercased() == "xprinter", storedPage == nil || storedPage == 21 {
                return 20
            }
            return storedPage ?? 20
        }()
        return isStarMode ? INIT : INIT + [0x1B, 0x74, UInt8(clamping: configuredPage)]
    }

    // ── Logo raster helpers ───────────────────────────────────────────────

    /// Convert a stored logo path (from UserDefaults "store_logo_path") to
    /// a 1-bit packed bitmap Data ready for `rasterImage()`.
    /// Returns nil if path is empty or image cannot be loaded.
    /// Call from @MainActor context (UIImage) — used by PrintService.
    /// Struct ที่เก็บ 1-bit bitmap พร้อม actual dimensions
    struct LogoBitmap {
        let data: Data
        let widthPx: Int   // actual pixel width (สำหรับ bytesPerRow calculation)
        let heightPx: Int  // actual pixel height (สำหรับ numRows)
        var bytesPerRow: Int { (widthPx + 7) / 8 }
    }

    static func loadLogoBitmap(maxWidthDots: Int = 240) -> LogoBitmap? {
        guard let uiImg = loadLogoUIImage() else { return nil }
        return imageTo1BitBitmap(uiImg, maxWidthDots: maxWidthDots)
    }

    /// Comprehensive loader for store logo supporting:
    /// - "store_logo_path" (filename, full filesystem path, file:// URI, or remote URL)
    /// - "store_logo_url" (synced merchant logo remote or local URL)
    /// - Documents directory default "store_logo.png"
    /// - Caches directory default "store_logo_print_cache"
    static func loadLogoUIImage() -> UIImage? {
        let fm = FileManager.default
        let pathKey = UserDefaults.standard.string(forKey: "store_logo_path") ?? ""
        let urlKey = UserDefaults.standard.string(forKey: "store_logo_url") ?? ""

        // 1. Try file path / file URI / relative filename from store_logo_path
        if !pathKey.isEmpty {
            // Case A: file:// URI
            if let fileURL = URL(string: pathKey), fileURL.isFileURL {
                if let data = try? Data(contentsOf: fileURL), let img = UIImage(data: data) {
                    return img
                }
                if fm.fileExists(atPath: fileURL.path), let img = UIImage(contentsOfFile: fileURL.path) {
                    return img
                }
            }
            // Case B: raw filesystem path
            if fm.fileExists(atPath: pathKey), let img = UIImage(contentsOfFile: pathKey) {
                return img
            }
            // Case C: relative filename inside .documentDirectory
            if let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
                let fileURL = docs.appendingPathComponent(pathKey)
                if let data = try? Data(contentsOf: fileURL), let img = UIImage(data: data) {
                    return img
                }
            }
        }

        // 2. Try store_logo_url (synced from merchant cloud settings)
        let candidateURLString = !urlKey.isEmpty ? urlKey : (pathKey.hasPrefix("http") ? pathKey : "")
        if !candidateURLString.isEmpty {
            if let url = URL(string: candidateURLString) {
                if url.isFileURL {
                    if let data = try? Data(contentsOf: url), let img = UIImage(data: data) {
                        return img
                    }
                    if fm.fileExists(atPath: url.path), let img = UIImage(contentsOfFile: url.path) {
                        return img
                    }
                } else if candidateURLString.hasPrefix("http://") || candidateURLString.hasPrefix("https://") {
                    // Check local print cache first
                    if let cacheURL = remoteLogoCacheURL(),
                       let data = try? Data(contentsOf: cacheURL),
                       let img = UIImage(data: data) {
                        return img
                    }
                    // Fetch remote data and populate local cache for subsequent prints
                    if let data = try? Data(contentsOf: url), let img = UIImage(data: data) {
                        if let cacheURL = remoteLogoCacheURL() {
                            try? data.write(to: cacheURL, options: .atomic)
                        }
                        if let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
                            let docFile = docs.appendingPathComponent("store_logo.png")
                            try? data.write(to: docFile, options: .atomic)
                        }
                        return img
                    }
                }
            }
        }

        // 3. Fallback: cached print logo in .cachesDirectory
        if let cacheURL = remoteLogoCacheURL(),
           let data = try? Data(contentsOf: cacheURL),
           let img = UIImage(data: data) {
            return img
        }

        // 4. Fallback: default "store_logo.png" in .documentDirectory
        if let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
            let defaultFile = docs.appendingPathComponent("store_logo.png")
            if let data = try? Data(contentsOf: defaultFile), let img = UIImage(data: data) {
                return img
            }
        }

        return nil
    }

    nonisolated static func remoteLogoCacheURL() -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("store_logo_print_cache")
    }

    /// Convert UIImage → 1-bit grayscale bitmap suitable for GS v 0 ESC/POS raster printing.
    static func imageTo1BitBitmap(_ image: UIImage, maxWidthDots: Int) -> LogoBitmap? {
        guard image.size.width > 0, image.size.height > 0 else { return nil }
        
        let scale = min(1.0, CGFloat(maxWidthDots) / image.size.width)
        let targetW = max(8, Int(image.size.width * scale))
        let targetH = max(8, Int(image.size.height * scale))

        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(
            data: nil,
            width: targetW,
            height: targetH,
            bitsPerComponent: 8,
            bytesPerRow: targetW,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        // White background
        ctx.setFillColor(gray: 1.0, alpha: 1.0)
        ctx.fill(CGRect(x: 0, y: 0, width: targetW, height: targetH))

        if let cgImg = image.cgImage {
            ctx.draw(cgImg, in: CGRect(x: 0, y: 0, width: targetW, height: targetH))
        } else {
            UIGraphicsPushContext(ctx)
            image.draw(in: CGRect(x: 0, y: 0, width: targetW, height: targetH))
            UIGraphicsPopContext()
        }

        guard let pixelData = ctx.data else { return nil }
        let ptr = pixelData.assumingMemoryBound(to: UInt8.self)

        let bytesPerRow = (targetW + 7) / 8
        var bitmap = [UInt8](repeating: 0, count: bytesPerRow * targetH)

        for row in 0..<targetH {
            for col in 0..<targetW {
                let px = ptr[row * targetW + col]
                if px < 160 {
                    bitmap[row * bytesPerRow + col / 8] |= (0x80 >> (col % 8))
                }
            }
        }

        return LogoBitmap(data: Data(bitmap), widthPx: targetW, heightPx: targetH)
    }

    private static func textBitmap(_ value: String, width: Int) -> LogoBitmap? {
        let font = UIFont(name: "Menlo", size: width <= 384 ? 22 : 22) ?? UIFont.monospacedSystemFont(ofSize: 22, weight: .regular)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byClipping
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black, .paragraphStyle: paragraph]
        let measured = (value as NSString).boundingRect(with: CGSize(width: CGFloat(width), height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil)
        let height = max(24, Int(ceil(measured.height)) + 8)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            (value as NSString).draw(in: CGRect(x: 2, y: 2, width: width - 4, height: height - 4), withAttributes: attributes)
        }
        return imageTo1BitBitmap(image, maxWidthDots: width)
    }

    /// Emit GS v 0 raster image command for a 1-bit bitmap produced by imageTo1BitBitmap.
    /// - Parameters:
    ///   - bitmapData: packed 1-bit rows (MSB first), bytesPerRow = ceil(width/8)
    ///   - maxWidthDots: the width in dots used when generating the bitmap
    private static func rasterImage(_ logo: LogoBitmap) -> [UInt8] {
        guard logo.heightPx > 0, logo.bytesPerRow > 0 else { return [] }
        // GS v 0  mode=0 (normal) xL xH yL yH [data]
        // xL/xH = bytesPerRow (actual width), yL/yH = actual height in rows
        let xL = UInt8(logo.bytesPerRow & 0xFF)
        let xH = UInt8((logo.bytesPerRow >> 8) & 0xFF)
        let yL = UInt8(logo.heightPx & 0xFF)
        let yH = UInt8((logo.heightPx >> 8) & 0xFF)
        var cmd: [UInt8] = [0x1D, 0x76, 0x30, 0x00, xL, xH, yL, yH]
        cmd += Array(logo.data)
        return cmd
    }

    private static func text(_ s: String) -> [UInt8] {
        Array((s.data(using: .windowsCP874) ?? s.data(using: .utf8) ?? Data()))
    }
    private static func resolvedHeader(_ template: ReceiptTemplate?) -> String? {
        nonEmpty(template?.headerText)
            ?? nonEmpty(UserDefaults.standard.string(forKey: "store_receipt_header"))
    }
    private static func resolvedFooter(_ template: ReceiptTemplate?) -> String? {
        nonEmpty(template?.footerText)
            ?? nonEmpty(UserDefaults.standard.string(forKey: "store_receipt_footer"))
    }
    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
    private static func divider(_ char: Character = "-", width: Int = 42) -> String {
        String(repeating: char, count: width) + "\n"
    }

    private static func lineItemHeader(width: Int = 42) -> String {
        if width <= 32 {
            // 58mm (32 chars): Name(18) | QTY(4) | AMOUNT(10)
            let namePart = "รายการ/ITEM".truncateThaiByVisualWidth(18).paddedThai(to: 18)
            let qtyPart = "QTY".rightAlignedThai(in: 4)
            let pricePart = "รวมเงิน".rightAlignedThai(in: 10)
            return namePart + qtyPart + pricePart + "\n"
        } else {
            // 80mm (42 chars): Name(27) | QTY(5) | AMOUNT(10)
            let namePart = "รายการ / ITEM".truncateThaiByVisualWidth(27).paddedThai(to: 27)
            let qtyPart = "จำนวน".rightAlignedThai(in: 5)
            let pricePart = "รวมเงิน".rightAlignedThai(in: 10)
            return namePart + qtyPart + pricePart + "\n"
        }
    }

    private static func lineItem(_ name: String, qty: Int, price: String, width: Int = 42) -> String {
        if width <= 32 {
            // 58mm (32 chars): Name(18) | QTY(4) | AMOUNT(10)
            let namePart = name.truncateThaiByVisualWidth(17).paddedThai(to: 18)
            let qtyPart = String(qty).rightAlignedThai(in: 4)
            let pricePart = price.rightAlignedThai(in: 10)
            return namePart + qtyPart + pricePart + "\n"
        } else {
            // 80mm (42 chars): Name(27) | QTY(5) | AMOUNT(10)
            let namePart = name.truncateThaiByVisualWidth(26).paddedThai(to: 27)
            let qtyPart = String(qty).rightAlignedThai(in: 5)
            let pricePart = price.rightAlignedThai(in: 10)
            return namePart + qtyPart + pricePart + "\n"
        }
    }
    private static func lineTotal(_ label: String, value: Double, width: Int = 42) -> String {
        lineTotal(label, value: String(format: "%.2f", value), width: width)
    }
    private static func padded(_ value: String, to width: Int) -> String {
        value.paddedThai(to: width)
    }
    private static func lineTotal(_ label: String, value: String, width: Int = 42) -> String {
        let labelVisualW = label.thaiVisualWidth
        let valueVisualW = value.thaiVisualWidth
        let spaces = max(1, width - labelVisualW - valueVisualW)
        return label + String(repeating: " ", count: spaces) + value + "\n"
    }
    private static func paymentMethodLabel(_ method: String) -> String {
        switch method.lowercased().replacingOccurrences(of: " ", with: "_") {
        case "cash": return "CASH"
        case "credit_card", "card": return "CARD"
        case "qr_promptpay", "qr", "promptpay": return "QR PROMPTPAY"
        case "true_money": return "TRUE MONEY"
        default: return method.uppercased().replacingOccurrences(of: "_", with: " ")
        }
    }
    private static func maskedPaymentReference(_ reference: String?) -> String? {
        guard let reference else { return nil }
        let value = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.hasPrefix("tendered:") else { return nil }
        if value.count <= 6 { return String(repeating: "*", count: max(2, value.count - 2)) + value.suffix(2) }
        return String(value.prefix(3)) + String(repeating: "*", count: min(8, value.count - 5)) + String(value.suffix(2))
    }
    private static func dateFormatter() -> DateFormatter {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm"
        return df
    }
    private static func timeFormatter() -> DateFormatter {
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        return df
    }
    private static func qrCode(_ dataStr: String, moduleSize: UInt8 = 5) -> [UInt8] {
        let dataBytes = Array(dataStr.utf8)
        let numBytes = dataBytes.count
        let pL = UInt8((numBytes + 3) & 0xFF)
        let pH = UInt8(((numBytes + 3) >> 8) & 0xFF)

        var b = [UInt8]()
        b += [0x1D, 0x28, 0x6B, 0x04, 0x00, 0x31, 0x41, 0x32, 0x00]
        b += [0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x43, min(max(moduleSize, 3), 10)]
        b += [0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x44, 0x32]
        b += [0x1D, 0x28, 0x6B, pL, pH, 0x31, 0x50, 0x30] + dataBytes
        b += [0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x51, 0x30]
        return b
    }
    private static func wrappedPrepLine(quantity: Int, name: String, width: Int) -> String {
        let prefix = "x\(quantity) "
        let bodyWidth = max(8, width - prefix.count)
        let lines = wrap(name, width: bodyWidth)
        guard let first = lines.first else { return "\(prefix)\n" }
        let continuation = String(repeating: " ", count: prefix.count)
        return ([prefix + first] + lines.dropFirst().map { continuation + $0 }).joined(separator: "\n") + "\n"
    }
    private static func wrappedIndentedLine(prefix: String, value: String, width: Int) -> String {
        let bodyWidth = max(8, width - prefix.count)
        let lines = wrap(value, width: bodyWidth)
        guard let first = lines.first else { return "\(prefix)\n" }
        let continuation = String(repeating: " ", count: prefix.count)
        return ([prefix + first] + lines.dropFirst().map { continuation + $0 }).joined(separator: "\n") + "\n"
    }
    private static func wrap(_ value: String, width: Int) -> [String] {
        let words = value.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        var lines = [String]()
        var current = ""
        for word in words {
            if word.count > width {
                if !current.isEmpty {
                    lines.append(current)
                    current = ""
                }
                var rest = word
                while rest.count > width {
                    lines.append(String(rest.prefix(width)))
                    rest = String(rest.dropFirst(width))
                }
                current = rest
            } else if current.isEmpty {
                current = word
            } else if current.count + 1 + word.count <= width {
                current += " " + word
            } else {
                lines.append(current)
                current = word
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines
    }
    private static func buildPromptPayPayload(target: String, amount: Double) -> String {
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
        payload += String(format: "29%02d%@", accountInfo.count, accountInfo) + "5303764"
        let amt = String(format: "%.2f", amount)
        payload += String(format: "54%02d%@", amt.count, amt) + "5802TH6304"
        let crc = crc16(payload)
        return payload + String(format: "%04X", crc)
    }
    private static func crc16(_ str: String) -> UInt16 {
        var crc: UInt16 = 0xFFFF
        for byte in Array(str.utf8) {
            for i in 0..<8 {
                let bit = ((byte >> (7 - i)) & 1) == 1
                let c15 = ((crc >> 15) & 1) == 1
                crc <<= 1
            if c15 != bit { crc ^= 0x1021 }
            }
        }
        return crc
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Shift Report Builder  (Open/Close Shift Z-Report)
// ─────────────────────────────────────────────────────────────────────────────
struct ShiftTenderSummary: Identifiable, Sendable {
    let method: String
    let count: Int
    let received: Double
    let refunded: Double
    var isDelivery: Bool = false
    var id: String { method }
    var net: Double { received - refunded }
}

enum ShiftReportBuilder {

    private static let INIT: [UInt8]            = [0x1B, 0x40]
    private static let ALIGN_CENTER: [UInt8]    = [0x1B, 0x61, 0x01]
    private static let ALIGN_LEFT: [UInt8]      = [0x1B, 0x61, 0x00]
    private static let BOLD_ON: [UInt8]         = [0x1B, 0x45, 0x01]
    private static let BOLD_OFF: [UInt8]        = [0x1B, 0x45, 0x00]
    private static let DOUBLE_SIZE_ON: [UInt8]  = [0x1B, 0x21, 0x30]
    private static let DOUBLE_SIZE_OFF: [UInt8] = [0x1B, 0x21, 0x00]
    private static let FEED_3: [UInt8]          = [0x1B, 0x64, 0x03]

    // ── Open Shift Slip ──────────────────────────────────────────────────────
    /// พิมพ์ใบเปิดกะ — แสดงจำนวนเงินในลิ้นชัก, ชื่อแคชเชียร์, เวลาเปิด
    static func buildOpenShift(session: RegisterSession, cashierName: String = "", emulation: String = "escpos") -> Data {
        var b: [UInt8] = emulation.lowercased() == "star" ? INIT : INIT + [0x1B, 0x74, 0x15]
        let width = 42
        let storeName = UserDefaults.standard.string(forKey: "store_name") ?? "AlphaPos Restaurant"
        let df = dateFormatter()

        b += ALIGN_CENTER
        b += BOLD_ON + DOUBLE_SIZE_ON + text("SHIFT OPEN\n") + DOUBLE_SIZE_OFF + BOLD_OFF
        b += text("\(storeName)\n")
        b += text(divider("-", width: width))

        b += ALIGN_LEFT
        b += text("DATE  : \(df.string(from: session.openedAt))\n")
        if !cashierName.isEmpty { b += text("CASHIER: \(cashierName)\n") }
        b += text(divider("-", width: width))

        b += BOLD_ON + text(lineTotal("OPENING CASH", value: session.openingCash, width: width)) + BOLD_OFF
        b += text(divider("=", width: width))

        b += ALIGN_CENTER + text("* SHIFT STARTED *\n")
        b += FEED_3 + cutCmd(emulation: emulation)
        return Data(b)
    }

    // ── Z-Report / Close Shift Slip ──────────────────────────────────────────
    /// พิมพ์ Z-Report เมื่อปิดกะ — สรุปยอดขาย, เงินสด, ความต่าง
    static func buildZReport(
        session: RegisterSession,
        report: ShiftReport,
        tenders: [ShiftTenderSummary],
        receiptCount: Int,
        failedPaymentCount: Int,
        cashMovementsIn: Double,
        cashMovementsOut: Double,
        openedBy: String,
        closedBy: String,
        isThai: Bool,
        emulation: String = "escpos"
    ) -> Data {
        var b: [UInt8] = emulation.lowercased() == "star" ? INIT : INIT + [0x1B, 0x74, 0x15]
        let width = 42
        let storeName = UserDefaults.standard.string(forKey: "store_name") ?? "AlphaPos Restaurant"
        let storeTaxId = UserDefaults.standard.string(forKey: "store_tax_id") ?? ""
        let df = dateFormatter()

        func label(_ th: String, _ en: String) -> String { isThai ? th : en }
        df.locale = Locale(identifier: isThai ? "th_TH" : "en_US_POSIX")

        b += ALIGN_CENTER
        b += BOLD_ON + DOUBLE_SIZE_ON + text("** \(label("รายงาน Z", "Z-REPORT")) **\n") + DOUBLE_SIZE_OFF + BOLD_OFF
        b += text("\(storeName)\n")
        if !storeTaxId.isEmpty { b += text("\(label("เลขประจำตัวผู้เสียภาษี", "TAX ID")): \(storeTaxId)\n") }
        b += text(divider("=", width: width))

        b += ALIGN_LEFT
        b += text("\(label("เปิดกะ", "SHIFT OPEN")) : \(df.string(from: session.openedAt))\n")
        b += text("\(label("ปิดกะ", "SHIFT CLOSE")): \(df.string(from: session.closedAt ?? Date()))\n")
        b += text("\(label("รหัสกะ", "SHIFT ID"))   : \(session.id.uuidString.prefix(8).uppercased())\n")
        let branch = session.branch.name
        if !branch.isEmpty { b += text("\(label("สาขา", "BRANCH"))     : \(branch)\n") }
        if !openedBy.isEmpty { b += text("\(label("เปิดโดย", "OPENED BY"))  : \(openedBy)\n") }
        if !closedBy.isEmpty { b += text("\(label("ปิดโดย", "CLOSED BY"))  : \(closedBy)\n") }
        let mins = max(0, Int((session.closedAt ?? Date()).timeIntervalSince(session.openedAt) / 60))
        b += text("\(label("ระยะเวลา", "DURATION"))   : \(mins / 60)\(label("ชม.", "h")) \(mins % 60)\(label("น.", "m"))\n")
        b += text(divider("-", width: width))

        // 1. Sales Summary
        b += BOLD_ON + text("\(label("1. สรุปยอดขาย", "1. SALES SUMMARY"))\n") + BOLD_OFF
        b += text(lineTotal(label("ยอดขายรวม", "Gross Sales"), value: report.grossSales, width: width))
        if report.totalDiscounts > 0.005 {
            b += text(lineTotal(label("ส่วนลด", "Discounts"), value: -report.totalDiscounts, width: width))
        }
        if report.totalRefunds > 0.005 {
            b += text(lineTotal(label("คืนเงิน", "Refunds"), value: -report.totalRefunds, width: width))
        }
        if report.totalTax > 0.005 {
            b += text(lineTotal(label("ภาษี (รวมแล้ว)", "Tax (included)"), value: report.totalTax, width: width))
        }
        b += text(divider("-", width: width))
        b += BOLD_ON + text(lineTotal(label("ยอดขายสุทธิ", "NET SALES"), value: report.netSales, width: width)) + BOLD_OFF
        b += text("\(label("จำนวนใบเสร็จ", "RECEIPTS"))    : \(receiptCount)\n")
        if failedPaymentCount > 0 {
            b += text("\(label("ชำระไม่สำเร็จ", "FAILED PAY.")) : \(failedPaymentCount)\n")
        }
        b += text(divider("=", width: width))

        // 2. Payment Breakdown
        b += BOLD_ON + text("\(label("2. สรุปยอดรับชำระ", "2. PAYMENT BREAKDOWN"))\n") + BOLD_OFF
        
        let inStoreTenders = tenders.filter { !$0.isDelivery }
        let deliveryTenders = tenders.filter { $0.isDelivery }

        if !inStoreTenders.isEmpty {
            b += text("[\(label("หน้าร้าน / ได้รับเงินทันที", "In-Store / Immediate"))]\n")
            for tender in inStoreTenders {
                b += text("\(tender.method) (\(tender.count))\n")
                b += text(lineTotal(label("  รับชำระ", "  Received"), value: tender.received, width: width))
                if tender.refunded > 0.005 {
                    b += text(lineTotal(label("  คืนเงิน", "  Refunds"), value: -tender.refunded, width: width))
                }
                b += BOLD_ON + text(lineTotal(label("  สุทธิ", "  Net"), value: tender.net, width: width)) + BOLD_OFF
            }
            let inStoreTotal = inStoreTenders.reduce(0) { $0 + $1.net }
            b += text(lineTotal(label("  รวมหน้าร้าน", "  Subtotal In-Store"), value: inStoreTotal, width: width))
        }

        if !deliveryTenders.isEmpty {
            b += text("\n[\(label("เดลิเวอรี่ / รอระบบโอน", "Delivery / Pending"))]\n")
            for tender in deliveryTenders {
                b += text("\(tender.method) (\(tender.count))\n")
                b += text(lineTotal(label("  รับชำระ", "  Received"), value: tender.received, width: width))
                if tender.refunded > 0.005 {
                    b += text(lineTotal(label("  คืนเงิน", "  Refunds"), value: -tender.refunded, width: width))
                }
                b += BOLD_ON + text(lineTotal(label("  สุทธิ", "  Net"), value: tender.net, width: width)) + BOLD_OFF
            }
            let delTotal = deliveryTenders.reduce(0) { $0 + $1.net }
            b += text(lineTotal(label("  รวมเดลิเวอรี่ (รอโอน)", "  Subtotal Delivery"), value: delTotal, width: width))
        }

        b += text(divider("-", width: width))
        b += BOLD_ON + text(lineTotal(label("รวมรับชำระทั้งหมด", "TOTAL RECEIVED"), value: tenders.reduce(0) { $0 + $1.net }, width: width)) + BOLD_OFF
        b += text(divider("=", width: width))

        // 3. Cash Drawer Reconciliation
        let cashTender = tenders.first { $0.method.lowercased().contains("cash") || $0.method.contains("เงินสด") }
        b += BOLD_ON + text("\(label("3. ลิ้นชักเงินสด", "3. CASH DRAWER"))\n") + BOLD_OFF
        b += text(lineTotal(label("(+) เงินเปิดกะ", "(+) Opening Float"), value: session.openingCash, width: width))
        b += text(lineTotal(label("(+) ยอดขายเงินสด", "(+) Cash Received"), value: cashTender?.received ?? 0, width: width))
        if cashMovementsIn > 0.005 {
            b += text(lineTotal(label("(+) เงินเข้า", "(+) Cash In"), value: cashMovementsIn, width: width))
        }
        if cashMovementsOut > 0.005 {
            b += text(lineTotal(label("(-) เงินออก", "(-) Cash Out"), value: -cashMovementsOut, width: width))
        }
        if (cashTender?.refunded ?? 0) > 0.005 {
            b += text(lineTotal(label("(-) คืนเงินสด", "(-) Cash Refunds"), value: -(cashTender?.refunded ?? 0), width: width))
        }
        b += text(divider("-", width: width))
        b += BOLD_ON + text(lineTotal(label("(=) เงินสดที่ควรมี", "(=) EXPECTED CASH"), value: session.expectedClosingCash, width: width)) + BOLD_OFF
        b += BOLD_ON + text(lineTotal(label("(=) เงินสดที่นับได้จริง", "(=) ACTUAL CASH"), value: session.actualClosingCash, width: width)) + BOLD_OFF
        b += text(divider("-", width: width))
        let variance = session.cashDiscrepancy
        b += BOLD_ON + text(lineTotal(label("ผลต่างเงินสด", "VARIANCE"), value: variance, width: width)) + BOLD_OFF
        if abs(variance) < 0.005 {
            b += ALIGN_CENTER + text(label("(ตรง)\n", "(BALANCED)\n"))
        } else {
            b += ALIGN_CENTER + text(variance > 0 ? label("(เกิน)\n", "(OVER)\n") : label("(ขาด)\n", "(SHORT)\n"))
        }
        b += text(divider("=", width: width))

        if let notes = session.notes, !notes.isEmpty {
            b += ALIGN_LEFT + text("\(label("หมายเหตุ", "NOTES")): \(notes)\n")
            b += text(divider("-", width: width))
        }

        b += ALIGN_CENTER + text("\(label("ปิดโดย", "CLOSED BY")): \(closedBy)\n")
        b += text("\(label("ลายเซ็นพนักงาน", "CASHIER SIGN")): ____________________\n\n")
        b += text("\(label("ลายเซ็นผู้จัดการ", "MANAGER SIGN")): ____________________\n")
        b += text("* \(label("สิ้นสุดกะ / รายงาน Z", "END OF SHIFT / Z REPORT")) *\n")
        b += FEED_3 + cutCmd(emulation: emulation)
        return Data(b)
    }

    private static func text(_ s: String) -> [UInt8] {
        Array((s.data(using: .windowsCP874) ?? s.data(using: .utf8) ?? Data()))
    }
    private static func divider(_ c: Character = "-", width: Int = 42) -> String {
        String(repeating: c, count: width) + "\n"
    }
    private static func lineTotal(_ label: String, value: Double, width: Int = 42) -> String {
        let right = String(format: "%.2f", value)
        let spaces = max(1, width - label.count - right.count)
        return label + String(repeating: " ", count: spaces) + right + "\n"
    }
    private static func dateFormatter() -> DateFormatter {
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HH:mm"; return df
    }
    private static func cutCmd(emulation: String) -> [UInt8] {
        if let brand = PrinterBrand(rawValue: emulation.lowercased()) { return brand.cutCommand }
        return [0x1D, 0x56, 0x42, 0x00]
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - TSPL Builder (สติกเกอร์แก้ว)
// ─────────────────────────────────────────────────────────────────────────────
enum TSPLBuilder {
    static let labelWidth  = 40
    static let labelHeight = 30
    static let gapHeight   = 2

    static func buildSticker(
        item: OrderItem,
        tableLabel: String,
        queueNumber: String,
        cupIndex: Int,
        totalCups: Int,
        template: ReceiptTemplate?
    ) -> Data {
        let itemName  = item.menuItem?.name ?? "Item"
        let modLines  = item.modifiers.filter { !$0.isDeleted }.compactMap { $0.modifier?.name }
        let notes     = item.notes ?? ""
        let timeStr   = TSPLBuilder.timeNow()
        let queueShort = queueNumber.prefix(12)



        let cupLabel  = "\(cupIndex)/\(totalCups)"

        let showTable = template?.showTableInfo ?? true
        let showMods = template?.showItemModifiers ?? true
        let showQueue = template?.showOrderType ?? true

        let size = template?.stickerSize ?? "40x30"
        let parts = size.split(separator: "x")
        let w = parts.count == 2 ? (Int(parts[0]) ?? labelWidth) : labelWidth
        let h = parts.count == 2 ? (Int(parts[1]) ?? labelHeight) : labelHeight

        var lines: [String] = []
        lines.append("SIZE \(w) mm, \(h) mm")
        lines.append("GAP \(gapHeight) mm, 0 mm")
        lines.append("DIRECTION 0")
        lines.append("REFERENCE 0,0")
        lines.append("OFFSET 0 mm")
        lines.append("SET PEEL OFF")
        lines.append("SET CUTTER OFF")
        lines.append("CLS")
        lines.append("CODEPAGE 874")

        if showTable { lines.append("TEXT 4,4,\"3\",0,1,1,\"\(escapeTS(tableLabel))\"") }
        lines.append("TEXT 290,4,\"3\",0,1,1,\"\(cupLabel)\"")
        lines.append("BAR 4,28,380,2")

        let nameFont = itemName.count > 16 ? "3" : "4"
        lines.append("TEXT 4,34,\"\(nameFont)\",0,1,1,\"\(escapeTS(itemName))\"")

        var yPos = 68
        if showMods {
            let footerLineY = h * 8 - 22
            let availableDots = footerLineY - yPos
            let maxTextLines = max(1, availableDots / 16)
            let hasNotes = !notes.isEmpty
            let maxMods = hasNotes ? max(1, maxTextLines - 1) : maxTextLines

            for (_, mod) in modLines.prefix(maxMods).enumerated() {
                lines.append("TEXT 4,\(yPos),\"2\",0,1,1,\"- \(escapeTS(mod))\"")
                yPos += 16
            }
            if hasNotes {
                let noteClip = String(notes.prefix(28))
                lines.append("TEXT 4,\(yPos),\"2\",0,1,1,\"* \(escapeTS(noteClip))\"")
                yPos += 16
            }
        }

        let footerY = h * 8 - 18
        lines.append("BAR 4,\(footerY - 4),380,1")
        lines.append("TEXT 4,\(footerY),\"1\",0,1,1,\"\(timeStr)\"")
        if showQueue { lines.append("TEXT 160,\(footerY),\"1\",0,1,1,\"Q:\(escapeTS(String(queueShort)))\"") }

        lines.append("PRINT 1,1\n")
        let tsplString = lines.joined(separator: "\r\n")
        return tsplString.data(using: .ascii) ?? Data()
    }

    static func buildTestSticker(printer: Printer, template: ReceiptTemplate? = nil) -> Data {
        let size = template?.stickerSize ?? "40x30"
        let parts = size.split(separator: "x")
        let w = parts.count == 2 ? (Int(parts[0]) ?? labelWidth) : labelWidth
        let h = parts.count == 2 ? (Int(parts[1]) ?? labelHeight) : labelHeight

        var lines: [String] = []
        lines.append("SIZE \(w) mm, \(h) mm")
        lines.append("GAP 2 mm, 0 mm")
        lines.append("DIRECTION 0")
        lines.append("REFERENCE 0,0")
        lines.append("OFFSET 0 mm")
        lines.append("SET PEEL OFF")
        lines.append("SET CUTTER OFF")
        lines.append("CLS")
        lines.append("CODEPAGE 874")

        // Match visually StickerPreviewCard:
        lines.append("TEXT 4,4,\"3\",0,1,1,\"T-08 [TICKET 1/3]\"")
        lines.append("TEXT 290,4,\"3\",0,1,1,\"QUE: #32\"")
        lines.append("BAR 4,28,380,2")

        lines.append("TEXT 4,34,\"4\",0,1,1,\"Matcha Latte (Oat)\"")
        lines.append("TEXT 4,68,\"2\",0,1,1,\"- Sweet 50%\"")
        lines.append("TEXT 4,84,\"2\",0,1,1,\"- Extra Oat Milk (+฿30)\"")

        let footerY = h * 8 - 18
        lines.append("BAR 4,\(footerY - 4),380,1")
        lines.append("TEXT 4,\(footerY),\"1\",0,1,1,\"2026-06-10 12:15\"")
        lines.append("TEXT 160,\(footerY),\"1\",0,1,1,\"AlphaPOS Cafe & Grill\"")

        // Mock barcode for TSPL
        lines.append("BARCODE 260,\(footerY - 14),\"128\",16,0,0,1,1,\"32\"")

        lines.append("PRINT 1,1\n")
        let tsplString = lines.joined(separator: "\r\n")
        return tsplString.data(using: .ascii) ?? Data()
    }

    fileprivate static func escapeTS(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
    fileprivate static func timeNow() -> String {
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        return df.string(from: Date())
    }
}
