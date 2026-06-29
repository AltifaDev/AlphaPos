import Foundation
import UIKit
import CoreGraphics

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Windows CP874 Encoding Support
// ─────────────────────────────────────────────────────────────────────────────
extension String.Encoding {
    static let windowsCP874 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.isoLatinThai.rawValue)))
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - ESC/POS Renderer
// ─────────────────────────────────────────────────────────────────────────────
struct ESCPosRenderer: PrinterRenderer {
    func render(job: PrintJob, emulation: String) -> Data {
        switch job.role {
        case "receipt":
            return ESCPOSBuilder.buildReceipt(order: job.order, template: job.template, logoBitmap: job.logoBitmap, emulation: emulation)
        case "kitchen", "bar":
            let stationLabel = job.role == "bar" ? "BAR TICKET" : "KITCHEN TICKET"
            let activeItems = job.order.items.filter { !$0.isDeleted }
            return ESCPOSBuilder.buildKitchenTicket(
                order: job.order,
                items: activeItems,
                stationLabel: stationLabel,
                template: job.template,
                emulation: emulation
            )
        default:
            return ESCPOSBuilder.buildReceipt(order: job.order, template: job.template, emulation: emulation)
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
        
        let tableLabel = job.order.tableSession?.table?.tableNumber ?? "Takeaway"
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

    static func buildReceipt(order: Order, template: ReceiptTemplate?, logoBitmap: ESCPOSBuilder.LogoBitmap? = nil, emulation: String = "escpos") -> Data {
        var b = buf()
        let paperWidthStr = template?.paperWidth ?? "80mm"
        let width = (paperWidthStr == "58mm") ? 32 : 42
        
        let showLogo = template?.showLogo ?? true
        let showTaxId = template?.showTaxId ?? true
        let showCustomerInfo = template?.showCustomerInfo ?? true
        let showQRCode = template?.showQRCode ?? true
        let showServiceCharge = template?.showServiceCharge ?? true
        let showTableInfo = template?.showTableInfo ?? true
        let showOrderType = template?.showOrderType ?? true
        let showItemModifiers = template?.showItemModifiers ?? true
        
        let storeName = UserDefaults.standard.string(forKey: "store_name") ?? "AlphaPos Restaurant"
        let storePhone = UserDefaults.standard.string(forKey: "store_phone") ?? "02-123-4567"
        let storeAddress = UserDefaults.standard.string(forKey: "store_address") ?? "123 Sukhumvit Rd, Bangkok"
        let storeTaxId = UserDefaults.standard.string(forKey: "store_tax_id") ?? "1234567890123"
        let storeBranchCode = UserDefaults.standard.string(forKey: "store_branch_code") ?? "00000"
        let promptPayNumber = UserDefaults.standard.string(forKey: "promptpay_number") ?? ""

        if let header = template?.headerText, !header.isEmpty {
            b += ALIGN_CENTER + text("\(header)\n")
        }

        if showLogo {
            if let logo = logoBitmap {
                b += rasterImage(logo)
            }
            // ถ้าไม่มี logoBitmap — ไม่พิมพ์ placeholder ข้อความ ให้ใช้ชื่อร้านแทน
        }
        b += BOLD_ON + DOUBLE_SIZE_ON + text("\(storeName)\n") + DOUBLE_SIZE_OFF + BOLD_OFF
        b += text("\(storeAddress)\n") + text("TEL: \(storePhone)\n") + BOLD_ON + text("TAX INVOICE (ABBREVIATED)\n") + BOLD_OFF
        b += text(divider("-", width: width))

        if showTaxId {
            b += ALIGN_LEFT
            if width == 32 {
                b += text("TAX ID: \(storeTaxId)\nBRANCH: \(storeBranchCode)\n")
            } else {
                b += text("TAX ID: \(storeTaxId)  BR: \(storeBranchCode)\n")
            }
            b += text(divider("-", width: width))
        }
        
        if showCustomerInfo {
            b += ALIGN_LEFT
            if let customer = order.customer {
                let tier = customer.membershipTier.uppercased()
                b += text("CUSTOMER : \(customer.name) (\(tier))\n")
                if let tId = customer.taxId, !tId.isEmpty { b += text("TAX EXEMPT: \(tId)\n") }
            } else {
                b += text("CUSTOMER : Walk-in Customer\n")
            }
            b += text(divider("-", width: width))
        }

        b += ALIGN_LEFT
        let df = dateFormatter()
        b += text("DATE : \(df.string(from: order.createdAt))\nORDER: \(order.orderNumber)\n")
        
        if showTableInfo {
            var tableLine = ""
            if let table = order.tableSession?.table?.tableNumber { tableLine += "TABLE: \(table)  " }
            if let q = order.queueNumber, !q.isEmpty { tableLine += "QUEUE: #\(q)" }
            if !tableLine.isEmpty { b += text("\(tableLine)\n") }
        }
        
        if showOrderType {
            let typeLabel = order.orderType.uppercased()
            b += text("TYPE : \(typeLabel)  |  GUESTS: \(order.guestCount)\n")
        }
        b += text(divider("-", width: width))

        b += ALIGN_LEFT
        b += text(width == 32 ? "ITEM                  QTY  PRICE\n" : "ITEM                           QTY   PRICE\n")
        b += text(divider("-", width: width))

        for item in order.items.filter({ !$0.isDeleted }) {
            let name = item.menuItem?.name ?? "Item"
            let price = String(format: "%.2f", item.unitPrice * Double(item.quantity))
            b += BOLD_ON + text(lineItem(name, qty: item.quantity, price: price, width: width)) + BOLD_OFF
            
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
        b += text(lineTotal("SUBTOTAL", value: order.subtotal, width: width))
        if order.tax > 0 {
            let taxRate = UserDefaults.standard.double(forKey: "store_tax_rate")
            let taxType = UserDefaults.standard.string(forKey: "store_tax_type") ?? "inclusive"
            let taxLabel = String(format: "%.0f%% VAT (%@)", taxRate, taxType.uppercased())
            b += text(lineTotal(taxLabel, value: order.tax, width: width))
        }
        if showServiceCharge && order.serviceCharge > 0 { b += text(lineTotal("SERVICE CHARGE", value: order.serviceCharge, width: width)) }
        if order.discount > 0 { b += text(lineTotal("DISCOUNT", value: -order.discount, width: width)) }
        b += text(divider("-", width: width))
        
        // TOTAL: label double-height, value right-aligned normal width
        let totalStr = String(format: "%.2f", order.total)
        let totalLabelW = width - totalStr.count - 1
        b += BOLD_ON + DOUBLE_HEIGHT_ON
        b += text(String(repeating: " ", count: max(0, totalLabelW)) + "\n")
        b += DOUBLE_HEIGHT_OFF + BOLD_OFF
        b += BOLD_ON + text(lineTotal("GRAND TOTAL", value: order.total, width: width)) + BOLD_OFF
        b += text(divider("-", width: width))

        b += ALIGN_CENTER
        if showQRCode && !promptPayNumber.isEmpty {
            b += text("SCAN TO PAY - PROMPTPAY\n")
            let payload = buildPromptPayPayload(target: promptPayNumber, amount: order.total)
            b += qrCode(payload) + text("\nPromptPay: \(promptPayNumber)\n")
        } else {
            b += text("PAID VIA CASH / TRANSFER\n")
        }
        b += text("\n") + BOLD_ON + text("THANK YOU FOR YOUR PATRONAGE\n") + BOLD_OFF

        if let footer = template?.footerText, !footer.isEmpty {
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
        emulation: String = "escpos"
    ) -> Data {
        var b = buf()
        let paperWidthStr = template?.paperWidth ?? "80mm"
        let width = (paperWidthStr == "58mm") ? 32 : 42
        
        let showTableInfo = template?.showTableInfo ?? true
        let showOrderType = template?.showOrderType ?? true
        let showItemModifiers = template?.showItemModifiers ?? true

        b += ALIGN_CENTER + BOLD_ON + DOUBLE_SIZE_ON + text("[ \(stationLabel) ]\n") + DOUBLE_SIZE_OFF + BOLD_OFF + ALIGN_LEFT

        let df = timeFormatter()
        b += text("Time : \(df.string(from: order.createdAt))\nORDER: \(order.orderNumber)\n")
        
        if showTableInfo {
            if let table = order.tableSession?.table?.tableNumber { b += text("Table: \(table)\n") }
            if let q = order.queueNumber, !q.isEmpty { b += text("Queue: #\(q)\n") }
        }
        if showOrderType { b += text("Type : \(order.orderType.uppercased())\n") }
        b += text(divider("-", width: width))

        if let customHeader = template?.headerText, !customHeader.isEmpty {
            b += ALIGN_CENTER + BOLD_ON + text("\(customHeader)\n") + ALIGN_LEFT + BOLD_OFF + text(divider("-", width: width))
        }

        for item in items {
            let name = item.menuItem?.name ?? "Item"
            b += BOLD_ON + DOUBLE_HEIGHT_ON + text("x\(item.quantity) \(name)\n") + DOUBLE_HEIGHT_OFF + BOLD_OFF
            
            if showItemModifiers {
                for mod in item.modifiers.filter({ !$0.isDeleted }) { b += text("  >> \(mod.modifier?.name ?? "")\n") }
                if let notes = item.notes, !notes.isEmpty { b += text("  ** \(notes)\n") }
            }
        }

        if let customFooter = template?.footerText, !customFooter.isEmpty {
            b += text(divider("-", width: width)) + ALIGN_CENTER + BOLD_ON + text("\(customFooter)\n") + ALIGN_LEFT + BOLD_OFF
        }

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
        var b = buf()
        let paperWidthStr = template?.paperWidth ?? printer.paperWidth
        let width = (paperWidthStr == "58mm") ? 32 : 42

        let storeName = UserDefaults.standard.string(forKey: "store_name") ?? "AlphaPos Restaurant"
        let storePhone = UserDefaults.standard.string(forKey: "store_phone") ?? "02-123-4567"
        let storeAddress = UserDefaults.standard.string(forKey: "store_address") ?? "123 Sukhumvit Rd, Bangkok"
        let storeTaxId = UserDefaults.standard.string(forKey: "store_tax_id") ?? "1234567890123"
        let storeBranchCode = UserDefaults.standard.string(forKey: "store_branch_code") ?? "00000"
        let promptPayNumber = UserDefaults.standard.string(forKey: "promptpay_number") ?? ""

        // ── Mirror ทุก toggle เหมือน buildReceipt ──────────────────────
        let showLogo          = template?.showLogo          ?? true
        let showTaxId         = template?.showTaxId         ?? true
        let showCustomerInfo  = template?.showCustomerInfo  ?? true
        let showQRCode        = template?.showQRCode        ?? true
        let showServiceCharge = template?.showServiceCharge ?? true
        let showTableInfo     = template?.showTableInfo     ?? true
        let showOrderType     = template?.showOrderType     ?? true
        let showItemModifiers = template?.showItemModifiers ?? true

        // ── Header text ──────────────────────────────────────────────────
        if let header = template?.headerText, !header.isEmpty {
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
        b += BOLD_ON + DOUBLE_SIZE_ON + text("\(storeName)\n") + DOUBLE_SIZE_OFF + BOLD_OFF
        b += text("\(storeAddress)\n")
        b += text("TEL: \(storePhone)\n")
        b += BOLD_ON + text("TAX INVOICE (ABBREVIATED)\n") + BOLD_OFF
        b += text(divider("-", width: width))

        // ── Tax ID (LEFT — เหมือน buildReceipt) ─────────────────────────
        if showTaxId {
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
            b += text("TAX EXEMPT: EX-99221\n")
            b += text(divider("-", width: width))
        }

        // ── Order info sample (LEFT — เหมือน buildReceipt) ───────────────
        b += ALIGN_LEFT
        b += text("DATE : \(dateFormatter().string(from: Date()))\n")
        b += text("ORDER: #AP-102546-CN\n")
        if showTableInfo {
            b += text("TABLE: Table 08 (Zone A)  QUEUE: #32\n")
        }
        if showOrderType {
            b += text("TYPE : DINE-IN  |  GUESTS: 3\n")
        }
        b += text(divider("-", width: width))

        // ── Items header (LEFT) ──────────────────────────────────────────
        b += ALIGN_LEFT
        b += text(width == 32 ? "ITEM                  QTY  PRICE\n" : "ITEM                           QTY   PRICE\n")
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
        let taxEnabled = UserDefaults.standard.bool(forKey: "enable_tax")
        let scEnabled = UserDefaults.standard.bool(forKey: "enable_service_charge")
        let testSubtotal = 780.00
        let testSC = (showServiceCharge && scEnabled) ? 78.00 : 0.00
        let testDiscount = -39.00
        let testTotal = testSubtotal + testSC + testDiscount
        let totalStr = String(format: "%.2f", testTotal)

        b += text(lineTotal("SUBTOTAL",             value: "780.00",  width: width))
        if showServiceCharge && scEnabled {
            b += text(lineTotal("SERVICE CHARGE (10%)", value: "78.00",  width: width))
        }
        if taxEnabled {
            let sampleTaxRate = UserDefaults.standard.double(forKey: "store_tax_rate")
            let sampleTaxType = UserDefaults.standard.string(forKey: "store_tax_type") ?? "inclusive"
            let sampleTaxLabel = String(format: "%.0f%% VAT (%@)", sampleTaxRate, sampleTaxType.uppercased())
            b += text(lineTotal(sampleTaxLabel,   value: "59.36",   width: width))
        }
        b += text(lineTotal("DISCOUNT (PROMO)",     value: "-39.00",  width: width))
        b += text(divider("-", width: width))
        b += BOLD_ON + text(lineTotal("GRAND TOTAL", value: totalStr, width: width)) + BOLD_OFF
        b += text(divider("-", width: width))

        // ── Payment / QR (CENTER — เหมือน buildReceipt) ─────────────────
        b += ALIGN_CENTER
        if showQRCode {
            // ใช้ promptPayNumber จริงถ้ามี ไม่งั้นใช้ sample เพื่อให้เห็น QR จริงในหน้าทดสอบ
            let qrTarget = promptPayNumber.isEmpty ? "0066812345678" : promptPayNumber
            let displayNum = promptPayNumber.isEmpty ? "08-1234-5678 (sample)" : promptPayNumber
            b += BOLD_ON + text("SCAN TO PAY - PROMPTPAY\n") + BOLD_OFF
            let payload = buildPromptPayPayload(target: qrTarget, amount: 878.00)
            b += qrCode(payload)
            b += text("\nPromptPay: \(displayNum)\n")
        } else if !showQRCode {
            b += text("PAID VIA CASH / TRANSFER\n")
        }
        b += BOLD_ON + text("THANK YOU FOR YOUR PATRONAGE\n") + BOLD_OFF

        // ── Footer text ──────────────────────────────────────────────────
        if let footer = template?.footerText, !footer.isEmpty {
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
        var b = buf()
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
            b += BOLD_ON + DOUBLE_HEIGHT_ON
            b += text("x\(item.qty) \(item.name.uppercased())\n")
            b += DOUBLE_HEIGHT_OFF + BOLD_OFF
            if showItemModifiers {
                for mod in item.mods {
                    b += text("  >> \(mod)\n")
                }
                if let note = item.note {
                    b += text("  ** \(note)\n")
                }
            }
        }

        b += text(divider("-", width: width))
        b += ALIGN_CENTER + text("* \(stationLabel) TICKET *\n")

        b += FEED_3 + cutSequence(emulation: emulation)
        return Data(b)
    }
    
    private static func cutSequence(emulation: String) -> [UInt8] {
        if let brand = PrinterBrand(rawValue: emulation) { return brand.cutCommand }
        return [0x1D, 0x56, 0x42, 0x00]
    }

    private static func buf() -> [UInt8] { INIT + [0x1B, 0x74, 0x15] }

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

    static func loadLogoBitmap(maxWidthDots: Int = 200) -> LogoBitmap? {
        let path = UserDefaults.standard.string(forKey: "store_logo_path") ?? ""
        guard !path.isEmpty else { return nil }
        let fm = FileManager.default
        var img: UIImage?
        if fm.fileExists(atPath: path) {
            img = UIImage(contentsOfFile: path)
        } else if let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
            if let data = try? Data(contentsOf: docs.appendingPathComponent(path)) {
                img = UIImage(data: data)
            }
        }
        guard let uiImg = img else { return nil }
        return imageTo1BitBitmap(uiImg, maxWidthDots: maxWidthDots)
    }

    /// Convert UIImage → 1-bit grayscale bitmap (packed, MSB-first rows)
    /// suitable for GS v 0 ESC/POS raster printing.
    static func imageTo1BitBitmap(_ image: UIImage, maxWidthDots: Int) -> LogoBitmap? {
        // Scale to fit maxWidthDots maintaining aspect ratio
        let scale = min(1.0, CGFloat(maxWidthDots) / image.size.width)
        let targetW = Int(image.size.width * scale)
        let targetH = Int(image.size.height * scale)
        guard targetW > 0, targetH > 0 else { return nil }

        let bytesPerRow = (targetW + 7) / 8
        var bitmap = [UInt8](repeating: 0, count: bytesPerRow * targetH)

        // Draw into 8-bit grayscale context
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(
            data: nil, width: targetW, height: targetH,
            bitsPerComponent: 8, bytesPerRow: targetW,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ), let cgImg = image.cgImage else { return nil }
        ctx.setFillColor(gray: 1.0, alpha: 1.0)
        ctx.fill(CGRect(x: 0, y: 0, width: targetW, height: targetH))
        ctx.draw(cgImg, in: CGRect(x: 0, y: 0, width: targetW, height: targetH))
        guard let pixels = ctx.data else { return nil }
        let ptr = pixels.assumingMemoryBound(to: UInt8.self)

        // Threshold to 1-bit (pixel < 128 = black = bit 1)
        for row in 0..<targetH {
            for col in 0..<targetW {
                let px = ptr[row * targetW + col]
                if px < 128 {
                    bitmap[row * bytesPerRow + col / 8] |= (0x80 >> (col % 8))
                }
            }
        }
        return LogoBitmap(data: Data(bitmap), widthPx: targetW, heightPx: targetH)
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
    private static func divider(_ char: Character = "-", width: Int = 42) -> String {
        String(repeating: char, count: width) + "\n"
    }
    private static func lineItem(_ name: String, qty: Int, price: String, width: Int = 42) -> String {
        // Layout: NAME (left-fill) | QTY (right-3 or 4) | PRICE (right-8 or 7)
        // ตรงกับ ReceiptLivePreview: name(flex) | qty(28px center) | price(58px trail)
        if width <= 32 {
            // 58mm: name(22) qty(3) price(7)
            let nameCol = 22; let qtyCol = 3; let priceCol = 7  // total = 32
            let truncName = name.count > nameCol ? String(name.prefix(nameCol)) : name
            let namePart  = truncName.padding(toLength: nameCol, withPad: " ", startingAt: 0)
            let qtyStr    = String(qty)
            let qtyPart   = String(repeating: " ", count: max(0, qtyCol - qtyStr.count)) + qtyStr
            let pricePart = String(repeating: " ", count: max(0, priceCol - price.count)) + price
            return namePart + qtyPart + pricePart + "\n"
        } else {
            // 80mm: name(30) qty(4) price(8)
            let nameCol = 30; let qtyCol = 4; let priceCol = 8  // total = 42
            let truncName = name.count > nameCol ? String(name.prefix(nameCol)) : name
            let namePart  = truncName.padding(toLength: nameCol, withPad: " ", startingAt: 0)
            let qtyStr    = String(qty)
            let qtyPart   = String(repeating: " ", count: max(0, qtyCol - qtyStr.count)) + qtyStr
            let pricePart = String(repeating: " ", count: max(0, priceCol - price.count)) + price
            return namePart + qtyPart + pricePart + "\n"
        }
    }
    private static func lineTotal(_ label: String, value: Double, width: Int = 42) -> String {
        let right = String(format: "%.2f", value)
        let spaces = max(1, width - label.count - right.count)
        return label + String(repeating: " ", count: spaces) + right + "\n"
    }
    private static func lineTotal(_ label: String, value: String, width: Int = 42) -> String {
        let spaces = max(1, width - label.count - value.count)
        return label + String(repeating: " ", count: spaces) + value + "\n"
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
    private static func qrCode(_ dataStr: String) -> [UInt8] {
        let dataBytes = Array(dataStr.utf8)
        let numBytes = dataBytes.count
        let pL = UInt8((numBytes + 3) & 0xFF)
        let pH = UInt8(((numBytes + 3) >> 8) & 0xFF)
        
        var b = [UInt8]()
        b += [0x1D, 0x28, 0x6B, 0x04, 0x00, 0x31, 0x41, 0x32, 0x00]
        b += [0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x43, 0x05]
        b += [0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x44, 0x32]
        b += [0x1D, 0x28, 0x6B, pL, pH, 0x31, 0x50, 0x30] + dataBytes
        b += [0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x51, 0x30]
        return b
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
        var b = INIT + [0x1B, 0x74, 0x15]
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
        cashSales: Double,
        cardSales: Double,
        qrSales: Double,
        totalRefunds: Double,
        cashMovementsIn: Double,
        cashMovementsOut: Double,
        emulation: String = "escpos"
    ) -> Data {
        var b = INIT + [0x1B, 0x74, 0x15]
        let width = 42
        let storeName = UserDefaults.standard.string(forKey: "store_name") ?? "AlphaPos Restaurant"
        let storeTaxId = UserDefaults.standard.string(forKey: "store_tax_id") ?? ""
        let df = dateFormatter()

        b += ALIGN_CENTER
        b += BOLD_ON + DOUBLE_SIZE_ON + text("** Z-REPORT **\n") + DOUBLE_SIZE_OFF + BOLD_OFF
        b += text("\(storeName)\n")
        if !storeTaxId.isEmpty { b += text("TAX ID: \(storeTaxId)\n") }
        b += text(divider("=", width: width))

        b += ALIGN_LEFT
        b += text("SHIFT OPEN : \(df.string(from: session.openedAt))\n")
        b += text("SHIFT CLOSE: \(df.string(from: session.closedAt ?? Date()))\n")
        let mins = Int((session.closedAt ?? Date()).timeIntervalSince(session.openedAt) / 60)
        b += text("DURATION   : \(mins / 60)h \(mins % 60)m\n")
        b += text(divider("-", width: width))

        b += BOLD_ON + text("SALES SUMMARY\n") + BOLD_OFF
        b += text(lineTotal("Cash Sales",    value: cashSales,      width: width))
        b += text(lineTotal("Card Sales",    value: cardSales,      width: width))
        b += text(lineTotal("QR / Transfer", value: qrSales,        width: width))
        b += text(lineTotal("Refunds",        value: -totalRefunds, width: width))
        b += text(divider("-", width: width))
        let grossSales = cashSales + cardSales + qrSales
        let netSales = grossSales - totalRefunds
        b += BOLD_ON + text(lineTotal("GROSS SALES", value: grossSales, width: width)) + BOLD_OFF
        b += BOLD_ON + text(lineTotal("NET SALES",   value: netSales,   width: width)) + BOLD_OFF
        b += text(divider("=", width: width))

        b += BOLD_ON + text("CASH DRAWER\n") + BOLD_OFF
        b += text(lineTotal("Opening Balance",  value: session.openingCash,          width: width))
        b += text(lineTotal("+ Cash Sales",     value: cashSales,                    width: width))
        b += text(lineTotal("+ Cash In",        value: cashMovementsIn,              width: width))
        b += text(lineTotal("- Cash Out",       value: -cashMovementsOut,            width: width))
        b += text(lineTotal("- Refunds (Cash)", value: -totalRefunds,                width: width))
        b += text(divider("-", width: width))
        b += BOLD_ON + text(lineTotal("EXPECTED CASH", value: session.expectedClosingCash, width: width)) + BOLD_OFF
        b += BOLD_ON + text(lineTotal("ACTUAL CASH",   value: session.actualClosingCash,   width: width)) + BOLD_OFF
        b += text(divider("-", width: width))
        let variance = session.cashDiscrepancy
        b += BOLD_ON + text(lineTotal("VARIANCE", value: variance, width: width)) + BOLD_OFF
        if abs(variance) > 0.01 { b += ALIGN_CENTER + text(variance > 0 ? "(OVER)\n" : "(SHORT)\n") }
        b += text(divider("=", width: width))

        b += ALIGN_CENTER + text("* END OF SHIFT *\n")
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
        if let brand = PrinterBrand(rawValue: emulation) { return brand.cutCommand }
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
        let timeStr   = timeNow()
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
        let maxMods = 3
        if showMods {
            for (_, mod) in modLines.prefix(maxMods).enumerated() {
                lines.append("TEXT 4,\(yPos),\"2\",0,1,1,\"- \(escapeTS(mod))\"")
                yPos += 16
            }
            if !notes.isEmpty {
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
