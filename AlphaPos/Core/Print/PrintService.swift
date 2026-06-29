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
                        totalCups: totalCups,
                        template: nil
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
