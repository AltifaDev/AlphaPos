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
            await PrintService.shared.retryPendingPrintJobs()
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
        await retryPendingPrintJobs()
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
        await retryPendingPrintJobs()
        async let r: () = printReceipt(order)
        // Also send to kitchen/bar/sticker printers that opt in to printOnPayment
        // (covers takeout/delivery stores that don't use "send to kitchen" flow)
        let allItems = order.items.filter { !$0.isDeleted }
        async let k: () = printKitchenTickets(order, items: allItems, trigger: .onPayment)
        async let b: () = printBarTickets(order, items: allItems, trigger: .onPayment)
        async let s: () = printStickerLabels(order, items: allItems, trigger: .onPayment)

        let hasCashPayment = order.payments.contains { payment in
            !payment.isDeleted && payment.status == "completed" && payment.paymentMethod.lowercased() == "cash"
        }
        if hasCashPayment {
            async let d: () = openCashDrawer()
            _ = await (r, k, b, s, d)
        } else {
            _ = await (r, k, b, s)
        }
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

    private enum PrintTrigger: String { case onOrder, onPayment, legacy }

    /// Print receipt — always fires regardless of routing rules.
    private func printReceipt(_ order: Order) async {
        let receiptEnabled = UserDefaults.standard.value(forKey: "receipt_printer_enabled") as? Bool ?? true
        guard receiptEnabled else { return }
        guard !UserDefaults.standard.bool(forKey: "disable_receipt_printing") else { return }
        guard let printers = activePrinters(forRole: "receipt"), !printers.isEmpty else { return }
        let template = defaultTemplate(forRole: "receipt")
        // Load logo bitmap once — reuse across all receipt printers
        let paperWidth = template?.paperWidth ?? printers.first?.paperWidth ?? "80mm"
        let maxDots = paperWidth == "58mm" ? 150 : 200
        let logoBitmap = ESCPOSBuilder.loadLogoBitmap(maxWidthDots: maxDots)
        for printer in printers {
            var job = PrintJob(order: order, role: "receipt", template: template)
            job.logoBitmap = logoBitmap
            _ = await enqueueAndSend(job, to: printer, trigger: .onPayment)
        }
    }

    /// Print kitchen tickets — respects printOnOrder / printOnPayment routing flags.
    private func printKitchenTickets(
        _ order: Order,
        items: [OrderItem],
        trigger: PrintTrigger?
    ) async {
        let kitchenEnabled = UserDefaults.standard.value(forKey: "kitchen_printer_enabled") as? Bool ?? true
        guard kitchenEnabled else { return }
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
            let result = await enqueueAndSend(job, to: printer, customItems: filtered, trigger: trigger ?? .legacy)
            if !result.success {
                await postFailureNotification(printerName: printer.name, role: "ครัว", itemCount: filtered.count, message: result.message, order: order)
            }
        }
    }

    /// Print bar tickets — respects printOnOrder / printOnPayment routing flags.
    private func printBarTickets(
        _ order: Order,
        items: [OrderItem],
        trigger: PrintTrigger?
    ) async {
        let kitchenEnabled = UserDefaults.standard.value(forKey: "kitchen_printer_enabled") as? Bool ?? true
        guard kitchenEnabled else { return }
        guard !items.isEmpty,
              let printers = activePrinters(forRole: "bar"),
              !printers.isEmpty else { return }
        let template = defaultTemplate(forRole: "bar")
        for printer in printers {
            if let trigger = trigger, !printerResponds(printer, to: trigger) { continue }
            let filtered = routedItems(items: items, printer: printer)
            guard !filtered.isEmpty else { continue }
            let job = PrintJob(order: order, role: "bar", template: template)
            let result = await enqueueAndSend(job, to: printer, customItems: filtered, trigger: trigger ?? .legacy)
            if !result.success {
                await postFailureNotification(printerName: printer.name, role: "บาร์", itemCount: filtered.count, message: result.message, order: order)
            }
        }
    }

    /// Print sticker labels — respects printOnOrder / printOnPayment routing flags.
    private func printStickerLabels(
        _ order: Order,
        items: [OrderItem],
        trigger: PrintTrigger?
    ) async {
        let kitchenEnabled = UserDefaults.standard.value(forKey: "kitchen_printer_enabled") as? Bool ?? true
        guard kitchenEnabled else { return }
        guard !items.isEmpty,
              let printers = activePrinters(forRole: "label"),
              !printers.isEmpty else { return }
        let template = defaultTemplate(forRole: "label")
        for printer in printers {
            if let trigger = trigger, !printerResponds(printer, to: trigger) { continue }
            let filtered = routedItems(items: items, printer: printer)
            guard !filtered.isEmpty else { continue }
            let job = PrintJob(order: order, role: "label", template: template)
            let result = await enqueueAndSend(job, to: printer, customItems: filtered, trigger: trigger ?? .legacy)
            if !result.success {
                await postFailureNotification(printerName: printer.name, role: "สติกเกอร์", itemCount: filtered.count, message: result.message, order: order)
            }
        }
    }

    private func postFailureNotification(printerName: String, role: String, itemCount: Int, message: String, order: Order) async {
        await MainActor.run {
            let title = "เครื่องพิมพ์\(role) (\(printerName)) ล้มเหลว"
            let body = "ไม่สามารถพิมพ์รายการออเดอร์ \(itemCount) รายการได้: \(message)"
            InAppNotificationManager.shared.post(
                InAppNotification(
                    type: .printerAlert,
                    title: title,
                    body: body,
                    tableNumber: order.tableSession?.table?.tableNumber
                )
            )

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
        case .legacy:    return true
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

    func testCashDrawer(to printer: Printer) async -> (success: Bool, log: [String]) {
        let logger = PrintLogger()
        logger.append("[1] Resolving cash drawer printer...")
        logger.append("    Name: \(printer.name)")
        logger.append("    Interface: \(printer.connectionType.uppercased())")

        let emulation = getEffectiveEmulation(for: printer)
        let data = CashDrawerBuilder.buildOpenDrawer(emulation: emulation)
        logger.append("[2] Compiled \(data.count) bytes of drawer pulse command.")
        logger.append("[3] Sending drawer pulse...")

        let transport = getTransport(for: printer)
        let result = await transport.deliver(data: data, printer: printer, logger: logger)
        logger.append(result.success ? "✓ Cash drawer pulse sent." : "✗ Cash drawer pulse failed.")
        logger.append("    Detail: \(result.message)")
        return (result.success, logger.logs)
    }

    // ──────────────
    // MARK: - Internal Pipeline Dispatcher
    // ─────────────────────────────────────────────────────────────────────────

    private func enqueueAndSend(
        _ job: PrintJob,
        to printer: Printer,
        customItems: [OrderItem]? = nil,
        trigger: PrintTrigger
    ) async -> PrintResult {
        guard let ctx = modelContext else {
            return await deliverJob(job, to: printer, customItems: customItems)
        }

        let key = idempotencyKey(order: job.order, printer: printer, role: job.role, trigger: trigger, items: customItems)
        let record = existingPrintJob(key: key) ?? PrintJobRecord(
            idempotencyKey: key,
            orderId: job.order.id,
            orderNumber: job.order.orderNumber,
            printerId: printer.id,
            printerName: printer.name,
            role: job.role,
            trigger: trigger.rawValue,
            itemIdsCSV: itemIdsCSV(customItems)
        )

        if record.status == "succeeded" {
            return PrintResult(success: true, message: "Already printed.")
        }

        if record.modelContext == nil {
            ctx.insert(record)
        }

        record.status = "printing"
        record.attempts += 1
        record.updatedAt = Date()
        try? ctx.save()

        let result = await deliverJob(job, to: printer, customItems: customItems)
        let now = Date()
        record.updatedAt = now
        if result.success {
            record.status = "succeeded"
            record.lastError = nil
            record.deliveredAt = now
            record.nextAttemptAt = nil
            markPrinted(items: customItems, role: job.role, at: now)
        } else {
            record.status = "failed"
            record.lastError = result.message
            record.nextAttemptAt = now.addingTimeInterval(retryDelay(forAttempt: record.attempts))
        }
        try? ctx.save()
        return result
    }

    private func deliverJob(_ job: PrintJob, to printer: Printer, customItems: [OrderItem]? = nil) async -> PrintResult {
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
        } else if let customItems = customItems, job.role == "label" || job.role == "sticker" {
            data = buildLabelPayload(order: job.order, items: customItems, template: job.template, emulation: emulation)
        } else {
            data = renderer.render(job: job, emulation: emulation)
        }

        let transport = getTransport(for: printer)
        return await transport.deliver(data: data, printer: printer, logger: logger)
    }

    func retryPendingPrintJobs(limit: Int = 20) async {
        guard let ctx = modelContext else { return }
        let now = Date()
        let records = ((try? ctx.fetch(FetchDescriptor<PrintJobRecord>())) ?? [])
            .filter {
                $0.status != "succeeded"
                    && $0.attempts < $0.maxAttempts
                    && ($0.nextAttemptAt == nil || $0.nextAttemptAt! <= now)
            }
            .sorted { $0.createdAt < $1.createdAt }
            .prefix(limit)

        for record in records {
            guard let order = fetchOrder(id: record.orderId),
                  let printer = fetchPrinter(id: record.printerId) else {
                record.status = "failed"
                record.lastError = "Missing order or printer for retry."
                record.updatedAt = Date()
                continue
            }

            let template = defaultTemplate(forRole: record.role)
            var job = PrintJob(order: order, role: record.role, template: template)
            if record.role == "receipt" {
                let paperWidth = template?.paperWidth ?? printer.paperWidth
                let maxDots = paperWidth == "58mm" ? 150 : 200
                job.logoBitmap = ESCPOSBuilder.loadLogoBitmap(maxWidthDots: maxDots)
            }
            let customItems = record.role == "receipt" ? nil : items(from: order, csv: record.itemIdsCSV)
            _ = await enqueueAndSend(job, to: printer, customItems: customItems, trigger: PrintTrigger(rawValue: record.trigger) ?? .legacy)
        }
        try? ctx.save()
    }

    private func existingPrintJob(key: String) -> PrintJobRecord? {
        guard let ctx = modelContext else { return nil }
        return ((try? ctx.fetch(FetchDescriptor<PrintJobRecord>())) ?? []).first { $0.idempotencyKey == key }
    }

    private func idempotencyKey(order: Order, printer: Printer, role: String, trigger: PrintTrigger, items: [OrderItem]?) -> String {
        let itemPart = itemIdsCSV(items)
        return [order.id.uuidString, printer.id.uuidString, role, trigger.rawValue, itemPart].joined(separator: "|")
    }

    private func itemIdsCSV(_ items: [OrderItem]?) -> String {
        guard let items, !items.isEmpty else { return "all" }
        return items.map { $0.id.uuidString }.sorted().joined(separator: ",")
    }

    private func items(from order: Order, csv: String) -> [OrderItem] {
        guard csv != "all" else { return order.items.filter { !$0.isDeleted } }
        let ids = Set(csv.split(separator: ",").compactMap { UUID(uuidString: String($0)) })
        return order.items.filter { ids.contains($0.id) && !$0.isDeleted }
    }

    private func retryDelay(forAttempt attempts: Int) -> TimeInterval {
        min(300, pow(2.0, Double(max(0, attempts - 1))) * 15)
    }

    private func markPrinted(items: [OrderItem]?, role: String, at date: Date) {
        guard let items else { return }
        for item in items {
            switch role {
            case "kitchen":
                item.kitchenPrintedAt = date
            case "bar":
                item.barPrintedAt = date
            case "label", "sticker":
                item.labelPrintedAt = date
            default:
                break
            }
            item.updatedAt = date
        }
    }

    private func buildLabelPayload(order: Order, items: [OrderItem], template: ReceiptTemplate?, emulation: String) -> Data {
        let tableLabel = order.tableSession?.table?.tableNumber ?? "Takeaway"
        let queueNumber = order.queueNumber ?? ""
        var data = Data()

        for (index, item) in items.enumerated() {
            if emulation == "tspl" {
                data.append(TSPLBuilder.buildSticker(
                    item: item,
                    tableLabel: tableLabel,
                    queueNumber: queueNumber,
                    cupIndex: index + 1,
                    totalCups: items.count,
                    template: template
                ))
            } else {
                data.append(ESCPOSBuilder.buildItemLabel(
                    item: item,
                    tableLabel: tableLabel,
                    queueNumber: queueNumber,
                    cupIndex: index + 1,
                    totalCups: items.count,
                    template: template,
                    emulation: emulation
                ))
            }
        }

        return data
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

    func hasActiveReceiptPrinters() -> Bool {
        return !(activePrinters(forRole: "receipt")?.isEmpty ?? true)
    }

    private func activePrinters(forRole role: String) -> [Printer]? {
        guard let ctx = modelContext else { return nil }
        let all = (try? ctx.fetch(FetchDescriptor<Printer>())) ?? []
        return all.filter { !$0.isDeleted && $0.isActive && $0.role == role }
    }

    private func fetchOrder(id: UUID) -> Order? {
        guard let ctx = modelContext else { return nil }
        return ((try? ctx.fetch(FetchDescriptor<Order>())) ?? []).first { $0.id == id && !$0.isDeleted }
    }

    private func fetchPrinter(id: UUID) -> Printer? {
        guard let ctx = modelContext else { return nil }
        return ((try? ctx.fetch(FetchDescriptor<Printer>())) ?? []).first { $0.id == id && !$0.isDeleted && $0.isActive }
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
        let allowedSlugs = Set(activeRules.compactMap { $0.categoryId })
        return items.filter { item in
            if !matchesPrinterStation(item: item, role: printer.role) { return false }
            if activeRules.isEmpty { return true }
            guard let cat = item.menuItem?.category?.name else { return false }
            return allowedSlugs.contains(OrderRoutingResolver.slug(cat))
        }
    }

    private func matchesPrinterStation(item: OrderItem, role: String) -> Bool {
        let stations = OrderRoutingResolver.stations(for: item)
        switch role {
        case "kitchen":
            return stations.contains(.kitchen)
        case "bar", "label", "sticker":
            return stations.contains(.bar)
        default:
            return true
        }
    }

    /// Exposes cash drawer pulse trigger to active receipt printers
    func openCashDrawer() async {
        guard let printers = activePrinters(forRole: "receipt"), !printers.isEmpty else { return }
        for printer in printers {
            let emulation = getEffectiveEmulation(for: printer)
            let data = CashDrawerBuilder.buildOpenDrawer(emulation: emulation)
            let transport = getTransport(for: printer)
            let logger = PrintLogger()
            _ = await transport.deliver(data: data, printer: printer, logger: logger)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - CashDrawerBuilder
// Generates printer-specific command codes to kick the cash drawer.
// ─────────────────────────────────────────────────────────────────────────────
enum CashDrawerBuilder {
    static func buildOpenDrawer(emulation: String) -> Data {
        if emulation.lowercased() == "star" {
            // Star command to kick drawer 1 is ASCII BEL [0x07]
            return Data([0x07])
        } else {
            // ESC/POS command: ESC p m t1 t2
            // m = 0 (Pin 2), t1 = 25 (50ms on), t2 = 250 (500ms off)
            return Data([0x1B, 0x70, 0x00, 0x19, 0xFA])
        }
    }
}
