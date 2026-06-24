import Foundation
import Network
import SwiftData
import Combine
import CoreFoundation

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - PrintService
// หัวใจหลักของระบบพิมพ์ AlphaPos
// รองรับ: ESC/POS (receipt, kitchen, bar) และ TSPL (สติกเกอร์แก้ว)
// Transport: TCP/IP raw socket port 9100 (ไม่ต้อง Driver)
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class PrintService: ObservableObject {

    static let shared = PrintService()
    private init() { }

    // inject modelContext จาก App หรือ View ที่เรียกใช้
    var modelContext: ModelContext?

    /// เรียกจาก App.init() หรือ onAppear — nonisolated เพื่อหลีกเลี่ยง actor isolation issue
    nonisolated func configure(modelContext: ModelContext) {
        Task { @MainActor in
            PrintService.shared.modelContext = modelContext
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Public Entry Points
    // ─────────────────────────────────────────────────────────────────────────

    /// พิมพ์ใบเสร็จ → เครื่องพิมพ์ role = "receipt"
    func printReceipt(_ order: Order) async {
        guard let printers = activePrinters(forRole: "receipt"), !printers.isEmpty else { return }
        let data = ESCPOSBuilder.buildReceipt(order: order)
        for printer in printers {
            await sendToPrinter(printer, data: data)
        }
    }

    /// พิมพ์ ticket ครัว → เครื่องพิมพ์ role = "kitchen" + routing rules
    func printKitchenTickets(_ order: Order) async {
        guard let printers = activePrinters(forRole: "kitchen"), !printers.isEmpty else { return }
        for printer in printers {
            let items = routedItems(order: order, printer: printer)
            guard !items.isEmpty else { continue }
            let data = ESCPOSBuilder.buildKitchenTicket(order: order, items: items)
            await sendToPrinter(printer, data: data)
        }
    }

    /// พิมพ์ ticket บาร์ → เครื่องพิมพ์ role = "bar" + routing rules
    func printBarTickets(_ order: Order) async {
        guard let printers = activePrinters(forRole: "bar"), !printers.isEmpty else { return }
        for printer in printers {
            let items = routedItems(order: order, printer: printer)
            guard !items.isEmpty else { continue }
            let data = ESCPOSBuilder.buildKitchenTicket(order: order, items: items, stationLabel: "BAR STATION")
            await sendToPrinter(printer, data: data)
        }
    }

    /// พิมพ์สติกเกอร์แก้ว → เครื่องพิมพ์ role = "label" + routing rules
    /// พิมพ์ 1 สติกเกอร์ต่อ 1 แก้ว (คูณด้วย quantity)
    func printStickerLabels(_ order: Order) async {
        guard let printers = activePrinters(forRole: "label"), !printers.isEmpty else { return }
        let tableLabel = order.tableSession?.table?.tableNumber ?? order.queueNumber ?? "—"

        for printer in printers {
            let items = routedItems(order: order, printer: printer)
            guard !items.isEmpty else { continue }

            // คำนวณ total cups สำหรับ queue counter
            let totalCups = items.reduce(0) { $0 + $1.quantity }
            var cupIndex = 1

            for item in items {
                for _ in 1...max(1, item.quantity) {
                    let data = TSPLBuilder.buildSticker(
                        item: item,
                        tableLabel: tableLabel,
                        queueNumber: order.queueNumber ?? order.orderNumber,
                        cupIndex: cupIndex,
                        totalCups: totalCups
                    )
                    await sendToPrinter(printer, data: data)
                    cupIndex += 1
                }
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Dispatch All (เรียกจาก processCheckout)
    // ─────────────────────────────────────────────────────────────────────────

    func dispatchAll(_ order: Order) async {
        async let r: () = printReceipt(order)
        async let k: () = printKitchenTickets(order)
        async let b: () = printBarTickets(order)
        async let s: () = printStickerLabels(order)
        _ = await (r, k, b, s)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Printer Lookup
    // ─────────────────────────────────────────────────────────────────────────

    private func activePrinters(forRole role: String) -> [Printer]? {
        guard let ctx = modelContext else { return nil }
        let all = (try? ctx.fetch(FetchDescriptor<Printer>())) ?? []
        return all.filter { !$0.isDeleted && $0.isActive && $0.role == role }
    }

    /// กรอง OrderItem ตาม routing rules ของเครื่องพิมพ์
    /// ถ้าไม่มี rule → ส่งทุก item
    private func routedItems(order: Order, printer: Printer) -> [OrderItem] {
        let activeRules = printer.routingRules.filter { !$0.isDeleted }
        let items = order.items.filter { !$0.isDeleted }
        if activeRules.isEmpty { return items }
        let allowedSlugs = Set(activeRules.compactMap { $0.categoryId })
        return items.filter { item in
            guard let cat = item.menuItem?.category?.name else { return false }
            let slug = cat.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            return allowedSlugs.contains(slug)
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - TCP Transport (Network.framework — ไม่ต้อง Driver)
    // ─────────────────────────────────────────────────────────────────────────

    private func sendToPrinter(_ printer: Printer, data: Data) async {
        switch printer.connectionType {
        case "network":
            guard let ip = printer.ipAddress, !ip.isEmpty else { return }
            await sendViaTCP(data: data, host: ip, port: printer.port)
        case "bluetooth":
            // Bluetooth: ใช้ ExternalAccessory framework (ต้อง pair ก่อน)
            // TODO: implement EASession transport
            break
        default:
            break
        }
    }

    private func sendViaTCP(data: Data, host: String, port: Int) async {
        await withCheckedContinuation { continuation in
            let endpoint = NWEndpoint.hostPort(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(integerLiteral: UInt16(port))
            )
            let connection = NWConnection(to: endpoint, using: .tcp)
            let queue = DispatchQueue(label: "com.alphapos.print.\(host)")

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: data, completion: .contentProcessed { error in
                        connection.cancel()
                        continuation.resume()
                    })
                case .failed, .cancelled:
                    continuation.resume()
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - ESC/POS Builder (Receipt + Kitchen/Bar)
// ─────────────────────────────────────────────────────────────────────────────

enum ESCPOSBuilder {

    // ESC/POS Control Bytes
    private static let ESC: UInt8  = 0x1B
    private static let GS: UInt8   = 0x1D
    private static let LF: UInt8   = 0x0A
    private static let INIT: [UInt8]          = [0x1B, 0x40]          // Initialize
    private static let ALIGN_CENTER: [UInt8]  = [0x1B, 0x61, 0x01]   // Center
    private static let ALIGN_LEFT: [UInt8]    = [0x1B, 0x61, 0x00]   // Left
    private static let BOLD_ON: [UInt8]       = [0x1B, 0x45, 0x01]
    private static let BOLD_OFF: [UInt8]      = [0x1B, 0x45, 0x00]
    private static let DOUBLE_HEIGHT_ON: [UInt8]  = [0x1B, 0x21, 0x10]
    private static let DOUBLE_HEIGHT_OFF: [UInt8] = [0x1B, 0x21, 0x00]
    private static let DOUBLE_SIZE_ON: [UInt8]    = [0x1B, 0x21, 0x30] // Double width+height
    private static let DOUBLE_SIZE_OFF: [UInt8]   = [0x1B, 0x21, 0x00]
    private static let CUT: [UInt8]           = [0x1D, 0x56, 0x42, 0x00] // Full cut
    private static let FEED_3: [UInt8]        = [0x1B, 0x64, 0x03]    // Feed 3 lines

    // ── Receipt ──────────────────────────────────────────────────────────────
    static func buildReceipt(order: Order) -> Data {
        var b = buf()

        // Header
        b += ALIGN_CENTER + BOLD_ON + DOUBLE_SIZE_ON
        b += text("ALPHAPOS\n")
        b += DOUBLE_SIZE_OFF + BOLD_OFF
        b += text("Receipt\n")
        b += text(divider()) + LF_byte

        // Order info
        b += ALIGN_LEFT
        let df = dateFormatter()
        b += text("Date : \(df.string(from: order.createdAt))\n")
        b += text("Order: \(order.orderNumber)\n")
        if let table = order.tableSession?.table?.tableNumber {
            b += text("Table: \(table)\n")
        }
        if let q = order.queueNumber, !q.isEmpty {
            b += text("Queue: #\(q)\n")
        }
        b += text("Type : \(order.orderType.uppercased())\n")
        b += text(divider()) + LF_byte

        // Items
        for item in order.items.filter({ !$0.isDeleted }) {
            let name = item.menuItem?.name ?? "Item"
            let price = String(format: "%.2f", item.unitPrice * Double(item.quantity))
            b += BOLD_ON
            b += text(lineItem(name, qty: item.quantity, price: price))
            b += BOLD_OFF
            for mod in item.modifiers.filter({ !$0.isDeleted }) {
                let modName = mod.modifier?.name ?? ""
                let modPrice = mod.price > 0 ? String(format: "+%.2f", mod.price) : ""
                b += text("  + \(modName) \(modPrice)\n")
            }
            if let notes = item.notes, !notes.isEmpty {
                b += text("  (\(notes))\n")
            }
        }

        b += text(divider()) + LF_byte

        // Totals
        b += text(lineTotal("Subtotal", value: order.subtotal))
        if order.tax > 0    { b += text(lineTotal("Tax (VAT)", value: order.tax)) }
        if order.serviceCharge > 0 { b += text(lineTotal("Service Charge", value: order.serviceCharge)) }
        if order.discount > 0 { b += text(lineTotal("Discount", value: -order.discount)) }
        b += text(divider())
        b += BOLD_ON + DOUBLE_HEIGHT_ON
        b += text(lineTotal("TOTAL", value: order.total))
        b += DOUBLE_HEIGHT_OFF + BOLD_OFF
        b += text(divider()) + LF_byte

        // Footer
        b += ALIGN_CENTER
        b += text("Thank you! See you again.\n")
        b += FEED_3 + CUT

        return Data(b)
    }

    // ── Kitchen / Bar Ticket ─────────────────────────────────────────────────
    static func buildKitchenTicket(
        order: Order,
        items: [OrderItem],
        stationLabel: String = "KITCHEN"
    ) -> Data {
        var b = buf()

        // Station Header
        b += ALIGN_CENTER + BOLD_ON + DOUBLE_SIZE_ON
        b += text("[ \(stationLabel) ]\n")
        b += DOUBLE_SIZE_OFF + BOLD_OFF
        b += ALIGN_LEFT

        let df = timeFormatter()
        b += text("Time : \(df.string(from: order.createdAt))\n")
        b += text("Order: \(order.orderNumber)\n")
        if let table = order.tableSession?.table?.tableNumber {
            b += text("Table: \(table)\n")
        }
        if let q = order.queueNumber, !q.isEmpty {
            b += text("Queue: #\(q)\n")
        }
        b += text(divider()) + LF_byte

        // Items
        for item in items {
            let name = item.menuItem?.name ?? "Item"
            b += BOLD_ON + DOUBLE_HEIGHT_ON
            b += text("x\(item.quantity) \(name)\n")
            b += DOUBLE_HEIGHT_OFF + BOLD_OFF
            for mod in item.modifiers.filter({ !$0.isDeleted }) {
                b += text("  >> \(mod.modifier?.name ?? "")\n")
            }
            if let notes = item.notes, !notes.isEmpty {
                b += text("  ** \(notes)\n")
            }
        }

        b += FEED_3 + CUT
        return Data(b)
    }

    // ── Helpers ──────────────────────────────────────────────────────────────
    private static func buf() -> [UInt8] { INIT }
    private static var LF_byte: [UInt8] { [LF] }

    private static func text(_ s: String) -> [UInt8] {
        Array((s.data(using: .windowsCP874) ?? s.data(using: .utf8) ?? Data()))
    }

    private static func divider(_ char: Character = "-", width: Int = 42) -> String {
        String(repeating: char, count: width) + "\n"
    }

    private static func lineItem(_ name: String, qty: Int, price: String, width: Int = 42) -> String {
        let left = "x\(qty) \(name)"
        let right = price
        let spaces = max(1, width - left.count - right.count)
        return left + String(repeating: " ", count: spaces) + right + "\n"
    }

    private static func lineTotal(_ label: String, value: Double, width: Int = 42) -> String {
        let right = String(format: "%.2f", value)
        let spaces = max(1, width - label.count - right.count)
        return label + String(repeating: " ", count: spaces) + right + "\n"
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
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - TSPL Builder (สติกเกอร์แก้ว)
// ─────────────────────────────────────────────────────────────────────────────
// รองรับเครื่องพิมพ์ TSC, Zebra, Brother ที่ใช้ TSPL/TSPL2
// ขนาด label: 40x30 mm (ค่า default สำหรับ roll แก้วมาตรฐาน)

enum TSPLBuilder {

    /// width/height หน่วย mm  — ปรับได้ตาม label roll ที่ใช้จริง
    static let labelWidth  = 40
    static let labelHeight = 30
    static let gapHeight   = 2

    static func buildSticker(
        item: OrderItem,
        tableLabel: String,
        queueNumber: String,
        cupIndex: Int,
        totalCups: Int
    ) -> Data {
        let itemName  = item.menuItem?.name ?? "Item"
        let modLines  = item.modifiers
            .filter { !$0.isDeleted }
            .compactMap { $0.modifier?.name }

        let notes     = item.notes ?? ""
        let timeStr   = timeNow()
        let queueShort = queueNumber.prefix(12)
        let cupLabel  = "\(cupIndex)/\(totalCups)"

        var lines: [String] = []

        // ── TSPL Header ──────────────────────────────────────────────────────
        lines.append("SIZE \(labelWidth) mm, \(labelHeight) mm")
        lines.append("GAP \(gapHeight) mm, 0 mm")
        lines.append("DIRECTION 0")
        lines.append("REFERENCE 0,0")
        lines.append("OFFSET 0 mm")
        lines.append("SET PEEL OFF")
        lines.append("SET CUTTER OFF")
        lines.append("CLS")

        // ── Row 1: Table + Cup counter ───────────────────────────────────────
        // TABLE label (left)
        lines.append("TEXT 4,4,\"3\",0,1,1,\"\(escapeTS(tableLabel))\"")
        // Cup counter (right, เช่น "2/5")
        let cupX = 290
        lines.append("TEXT \(cupX),4,\"3\",0,1,1,\"\(cupLabel)\"")

        // ── Divider ──────────────────────────────────────────────────────────
        lines.append("BAR 4,28,380,2")

        // ── Row 2: Item name (ใหญ่) ──────────────────────────────────────────
        let nameFont = itemName.count > 16 ? "3" : "4"
        lines.append("TEXT 4,34,\"\(nameFont)\",0,1,1,\"\(escapeTS(itemName))\"")

        // ── Rows 3+: Modifiers ───────────────────────────────────────────────
        var yPos = 68
        let maxMods = 3
        for (i, mod) in modLines.prefix(maxMods).enumerated() {
            lines.append("TEXT 4,\(yPos),\"2\",0,1,1,\"- \(escapeTS(mod))\"")
            yPos += 16
            _ = i
        }
        if !notes.isEmpty {
            let noteClip = String(notes.prefix(28))
            lines.append("TEXT 4,\(yPos),\"2\",0,1,1,\"* \(escapeTS(noteClip))\"")
            yPos += 16
        }

        // ── Footer: เวลา + Queue ─────────────────────────────────────────────
        let footerY = labelHeight * 8 - 18   // เกือบล่างสุด
        lines.append("BAR 4,\(footerY - 4),380,1")
        lines.append("TEXT 4,\(footerY),\"1\",0,1,1,\"\(timeStr)\"")
        lines.append("TEXT 160,\(footerY),\"1\",0,1,1,\"Q:\(escapeTS(String(queueShort)))\"")

        // ── Print ────────────────────────────────────────────────────────────
        lines.append("PRINT 1,1")
        lines.append("")    // trailing newline

        let tsplString = lines.joined(separator: "\r\n")
        return tsplString.data(using: .ascii) ?? Data()
    }

    private static func escapeTS(_ s: String) -> String {
        // TSPL ใช้ backslash เป็น escape — escape double-quote และ backslash
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func timeNow() -> String {
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        return df.string(from: Date())
    }
}

// MARK: - Windows CP874 Encoding Support
extension String.Encoding {
    static let windowsCP874 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(1060))
}
