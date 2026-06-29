import Foundation
import SwiftData
import Combine
import CoreFoundation
import ExternalAccessory

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - PrintService
// Orchestrator for the AlphaPos Print Pipeline
// Coordinates routing, rendering, and delivery to printer hardware.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class PrintService: ObservableObject {

    static let shared = PrintService()
    
    var modelContext: ModelContext? {
        didSet {
            #if DEBUG
            print("PrintService modelContext updated")
            #endif
        }
    }

    private init() { }

    /// nonisolated config setup helper
    nonisolated func configure(modelContext: ModelContext) {
        Task { @MainActor in
            PrintService.shared.modelContext = modelContext
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Public Entry Points
    // ─────────────────────────────────────────────────────────────────────────

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Trigger: Send to Kitchen  (createPayment = false)
    // Fires kitchen + bar + sticker printers where printOnOrder = true.
    // Sends only items that are newly added in this submission pass
    // (status == "cooking" with no prior printedAt timestamp).
    // Receipt printers are intentionally excluded here — receipt is
    // printed only after payment is confirmed.
    // ─────────────────────────────────────────────────────────────────────────

    /// Dispatch kitchen-side tickets when an order is sent to the kitchen.
    /// Call this from processCheckout(createPayment: false).
    func dispatchKitchenOrder(_ order: Order) async {
        let newItems = order.items.filter { !$0.isDeleted && $0.status == "cooking" }
        guard !newItems.isEmpty else { return }
        async let k: () = printKitchenTickets(order, items: newItems, trigger: .onOrder)
        async let b: () = printBarTickets(order, items: newItems, trigger: .onOrder)
        async let s: () = printStickerLabels(order, items: newItems, trigger: .onOrder)
        _ = await (k, b, s)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Trigger: Payment Confirmed  (createPayment = true)
    // Fires receipt printers always.
    // Also fires kitchen/bar/sticker printers where printOnPayment = true
    // (useful for takeout / delivery workflows that print on payment).
    // ─────────────────────────────────────────────────────────────────────────

    /// Dispatch receipt (and optional kitchen re-print) after payment is confirmed.
    /// Call this from processCheckout(createPayment: true).
    func dispatchReceipt(_ order: Order) async {
        async let r: () = printReceipt(order)
        // Also send to kitchen/bar/sticker printers that opt in to printOnPayment
        // (covers takeout/delivery stores that don't use "send to kitchen" flow)
        let allItems = order.items.filter { !$0.isDeleted }
        async let k: () = printKitchenTickets(order, items: allItems, trigger: .onPayment)
        async let b: () = printBarTickets(order, items: allItems, trigger: .onPayment)
        async let s: () = printStickerLabels(order, items: allItems, trigger: .onPayment)
        _ = await (r, k, b, s)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Trigger: Legacy / Full Dispatch
    // Retained for backward compatibility. Sends all roles concurrently
    // without trigger filtering. Prefer dispatchKitchenOrder / dispatchReceipt.
    // ─────────────────────────────────────────────────────────────────────────

    /// Legacy: print receipt, kitchen, bar, and label tickets concurrently.
    /// Prefer dispatchKitchenOrder / dispatchReceipt for correct trigger semantics.
    func dispatchAll(_ order: Order) async {
        async let r: () = printReceipt(order)
        let allItems = order.items.filter { !$0.isDeleted }
        async let k: () = printKitchenTickets(order, items: allItems, trigger: nil)
        async let b: () = printBarTickets(order, items: allItems, trigger: nil)
        async let s: () = printStickerLabels(order, items: allItems, trigger: nil)
        _ = await (r, k, b, s)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Role-level print functions (internal, trigger-aware)
    // ─────────────────────────────────────────────────────────────────────────

    private enum PrintTrigger { case onOrder, onPayment }

    /// Print receipt — always fires regardless of routing rules.
    private func printReceipt(_ order: Order) async {
        guard let printers = activePrinters(forRole: "receipt"), !printers.isEmpty else { return }
        let template = defaultTemplate(forRole: "receipt")
        // Load logo bitmap once — reuse across all receipt printers
        let paperWidth = template?.paperWidth ?? printers.first?.paperWidth ?? "80mm"
        let maxDots = paperWidth == "58mm" ? 150 : 200
        let logoBitmap = ESCPOSBuilder.loadLogoBitmap(maxWidthDots: maxDots)
        for printer in printers {
            var job = PrintJob(order: order, role: "receipt", template: template)
            job.logoBitmap = logoBitmap
            _ = await sendJob(job, to: printer)
        }
    }

    /// Print kitchen tickets — respects printOnOrder / printOnPayment routing flags.
    private func printKitchenTickets(
        _ order: Order,
        items: [OrderItem],
        trigger: PrintTrigger?
    ) async {
        guard !items.isEmpty,
              let printers = activePrinters(forRole: "kitchen"),
              !printers.isEmpty else { return }
        let template = defaultTemplate(forRole: "kitchen")
        for printer in printers {
            // Respect per-printer trigger flag (nil = no filter, used by legacy dispatchAll)
            if let trigger = trigger, !printerResponds(printer, to: trigger) { continue }
            let filtered = routedItems(items: items, printer: printer)
            guard !filtered.isEmpty else { continue }
            let job = PrintJob(order: order, role: "kitchen", template: template)
            _ = await sendJob(job, to: printer, customItems: filtered)
        }
    }

    /// Print bar tickets — respects printOnOrder / printOnPayment routing flags.
    private func printBarTickets(
        _ order: Order,
        items: [OrderItem],
        trigger: PrintTrigger?
    ) async {
        guard !items.isEmpty,
              let printers = activePrinters(forRole: "bar"),
              !printers.isEmpty else { return }
        let template = defaultTemplate(forRole: "bar")
        for printer in printers {
            if let trigger = trigger, !printerResponds(printer, to: trigger) { continue }
            let filtered = routedItems(items: items, printer: printer)
            guard !filtered.isEmpty else { continue }
            let job = PrintJob(order: order, role: "bar", template: template)
            _ = await sendJob(job, to: printer, customItems: filtered)
        }
    }

    /// Print sticker labels — respects printOnOrder / printOnPayment routing flags.
    private func printStickerLabels(
        _ order: Order,
        items: [OrderItem],
        trigger: PrintTrigger?
    ) async {
        guard !items.isEmpty,
              let printers = activePrinters(forRole: "label"),
              !printers.isEmpty else { return }
        let template = defaultTemplate(forRole: "label")
        for printer in printers {
            if let trigger = trigger, !printerResponds(printer, to: trigger) { continue }
            let filtered = routedItems(items: items, printer: printer)
            guard !filtered.isEmpty else { continue }
            let job = PrintJob(order: order, role: "label", template: template)
            _ = await sendJob(job, to: printer, customItems: filtered)
        }
    }

    /// Returns true if the printer has at least one routing rule matching the trigger.
    /// A printer with no routing rules is treated as "respond to all triggers".
    private func printerResponds(_ printer: Printer, to trigger: PrintTrigger) -> Bool {
        let activeRules = printer.routingRules.filter { !$0.isDeleted }
        if activeRules.isEmpty { return true }
        switch trigger {
        case .onOrder:   return activeRules.contains { $0.printOnOrder }
        case .onPayment: return activeRules.contains { $0.printOnPayment }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Shift Print Entry Points
    // ─────────────────────────────────────────────────────────────────────────

    /// พิมพ์ใบเปิดกะ — เรียกจาก StartShiftRegisterSheet หลังบันทึก session สำเร็จ
    /// ตรวจสอบ AppStorage "print_open_shift" ก่อนพิมพ์
    func printOpenShift(session: RegisterSession, cashierName: String = "") async {
        guard UserDefaults.standard.bool(forKey: "print_open_shift") else { return }
        guard let printers = activePrinters(forRole: "receipt"), !printers.isEmpty else { return }
        for printer in printers {
            let emulation = getEffectiveEmulation(for: printer)
            let data = ShiftReportBuilder.buildOpenShift(
                session: session,
                cashierName: cashierName,
                emulation: emulation
            )
            let transport = getTransport(for: printer)
            let logger = PrintLogger()
            _ = await transport.deliver(data: data, printer: printer, logger: logger)
        }
    }

    /// พิมพ์ Z-Report เมื่อปิดกะ — เรียกจาก CashDrawerManagementView หลัง closeRegisterSession
    /// ตรวจสอบ AppStorage "print_close_shift" ก่อนพิมพ์
    func printZReport(
        session: RegisterSession,
        report: ShiftReport,
        cashSales: Double,
        cardSales: Double,
        qrSales: Double,
        totalRefunds: Double,
        cashMovementsIn: Double,
        cashMovementsOut: Double
    ) async {
        guard UserDefaults.standard.bool(forKey: "print_close_shift") else { return }
        guard let printers = activePrinters(forRole: "receipt"), !printers.isEmpty else { return }
        for printer in printers {
            let emulation = getEffectiveEmulation(for: printer)
            let data = ShiftReportBuilder.buildZReport(
                session: session,
                report: report,
                cashSales: cashSales,
                cardSales: cardSales,
                qrSales: qrSales,
                totalRefunds: totalRefunds,
                cashMovementsIn: cashMovementsIn,
                cashMovementsOut: cashMovementsOut,
                emulation: emulation
            )
            let transport = getTransport(for: printer)
            let logger = PrintLogger()
            _ = await transport.deliver(data: data, printer: printer, logger: logger)
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Diagnostic Test Print
    // ─────────────────────────────────────────────────────────────────────────

    /// Diagnostic test print with console logging
    func printTest(to printer: Printer, previewType: String? = nil) async -> (success: Bool, log: [String]) {
        let logger = PrintLogger()
        let type = previewType ?? printer.role
        let template = defaultTemplate(forRole: type)
        let emulation = getEffectiveEmulation(for: printer)
        
        logger.append("[1] Resolving printer configuration...")
        logger.append("    Name: \(printer.name)")
        logger.append("    Interface: \(printer.connectionType.uppercased())")
        logger.append("    Width: \(printer.paperWidth)")
        logger.append("    Emulation: \(emulation.uppercased())")
        
        logger.append("[2] Compiling print payload...")
        let data: Data
        switch type {
        case "receipt":
            let maxDots = printer.paperWidth == "58mm" ? 150 : 200
            let logoBitmap = ESCPOSBuilder.loadLogoBitmap(maxWidthDots: maxDots)
            data = ESCPOSBuilder.buildTestReceipt(printer: printer, template: template, logoBitmap: logoBitmap, emulation: emulation)
        case "kitchen":
            data = ESCPOSBuilder.buildTestKitchenTicket(printer: printer, stationLabel: "KITCHEN TICKET", template: template, emulation: emulation)
        case "bar":
            data = ESCPOSBuilder.buildTestKitchenTicket(printer: printer, stationLabel: "BAR TICKET", template: template, emulation: emulation)
        case "label", "sticker":
            data = TSPLBuilder.buildTestSticker(printer: printer, template: template)
        default:
            data = ESCPOSBuilder.buildTestReceipt(printer: printer, template: template, emulation: emulation)
        }
        logger.append("    Compiled \(data.count) bytes of print payload.")
        
        logger.append("[3] Establishing connection...")
        let transport = getTransport(for: printer)
        let result = await transport.deliver(data: data, printer: printer, logger: logger)
        
        logger.append(result.success ? "✓ Test print successful!" : "✗ Test print failed.")
        logger.append("    Detail: \(result.message)")
        
        return (result.success, logger.logs)
    }

    // ──────────────
    // MARK: - Internal Pipeline Dispatcher
    // ─────────────────────────────────────────────────────────────────────────

    private func sendJob(_ job: PrintJob, to printer: Printer, customItems: [OrderItem]? = nil) async -> PrintResult {
        let logger = PrintLogger()
        let emulation = getEffectiveEmulation(for: printer)
        let renderer = getRenderer(for: printer, emulation: emulation)
        
        let data: Data
        if let customItems = customItems, (job.role == "kitchen" || job.role == "bar") {
            let stationLabel = job.role == "bar" ? "BAR TICKET" : "KITCHEN TICKET"
            data = ESCPOSBuilder.buildKitchenTicket(
                order: job.order,
                items: customItems,
                stationLabel: stationLabel,
                template: job.template,
                emulation: emulation
            )
        } else {
            data = renderer.render(job: job, emulation: emulation)
        }
        
        let transport = getTransport(for: printer)
        return await transport.deliver(data: data, printer: printer, logger: logger)
    }

    private func getRenderer(for printer: Printer, emulation: String) -> PrinterRenderer {
        guard let brand = PrinterBrand(rawValue: emulation) else { return ESCPosRenderer() }
        switch brand {
        case .star:
            return StarRenderer()
        case .tspl:
            return TSPLRenderer()
        default:
            return ESCPosRenderer()
        }
    }

    private func getTransport(for printer: Printer) -> PrinterTransport {
        switch printer.connectionType {
        case "network":
            return TCPTransport()
        case "usb":
            let emulation = getEffectiveEmulation(for: printer)
            if emulation == "star" {
                return StarUSBTransport()
            }
            return EAAccessoryTransport()
        case "bluetooth":
            return BLETransport()
        default:
            return TCPTransport()
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Helper Lookup Methods
    // ─────────────────────────────────────────────────────────────────────────

    private func getEffectiveEmulation(for printer: Printer) -> String {
        if printer.connectionType == "usb" {
            let manager = EAAccessoryManager.shared()
            let accessories = manager.connectedAccessories
            
            for brand in PrinterBrand.allCases {
                let protocols = brand.mfiProtocols
                if accessories.contains(where: { acc in
                    acc.protocolStrings.contains(where: { protocols.contains($0) })
                }) {
                    return brand.rawValue
                }
            }
        }
        return printer.emulation
    }

    private func activePrinters(forRole role: String) -> [Printer]? {
        guard let ctx = modelContext else { return nil }
        let all = (try? ctx.fetch(FetchDescriptor<Printer>())) ?? []
        return all.filter { !$0.isDeleted && $0.isActive && $0.role == role }
    }

    private func defaultTemplate(forRole role: String) -> ReceiptTemplate? {
        guard let ctx = modelContext else { return nil }
        let templateType = (role == "label" || role == "sticker") ? "sticker" : role
        
        let descriptor = FetchDescriptor<ReceiptTemplate>(
            predicate: #Predicate<ReceiptTemplate> { !$0.isDeleted }
        )
        let all = (try? ctx.fetch(descriptor)) ?? []
        let filtered = all.filter { $0.templateType == templateType }
        return filtered.first(where: { $0.isDefault }) ?? filtered.first
    }

    private func routedItems(items: [OrderItem], printer: Printer) -> [OrderItem] {
        let activeRules = printer.routingRules.filter { !$0.isDeleted }
        if activeRules.isEmpty { return items }
        let allowedSlugs = Set(activeRules.compactMap { $0.categoryId })
        return items.filter { item in
            guard let cat = item.menuItem?.category?.name else { return false }
            let slug = cat.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            return allowedSlugs.contains(slug)
        }
    }
}
