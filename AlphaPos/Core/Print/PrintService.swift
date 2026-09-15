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

    /// Session-only emergency pause for every automatic POS print route.
    /// This deliberately is not persisted: terminating and reopening the app
    /// always restores normal printing, so a forgotten pause cannot carry over
    /// to the next shift. Manual pre-bills and forced receipt copies still work.
    @Published var isAutomaticPrintingTemporarilyPaused = false

    var modelContext: ModelContext? {
        didSet {
            #if DEBUG
            print("PrintService modelContext updated")
            #endif
        }
    }

    private let deliveryCoordinator = DeliveryCoordinator()

    private actor DeliveryCoordinator {
        private var activeDeliveryKeys = Set<String>()

        func withReservation<T>(
            key: String,
            operation: @MainActor @Sendable () async throws -> T
        ) async rethrows -> T {
            while activeDeliveryKeys.contains(key) {
                try? await Task.sleep(for: .milliseconds(150))
            }
            activeDeliveryKeys.insert(key)
            defer { activeDeliveryKeys.remove(key) }
            return try await operation()
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
        guard !isAutomaticPrintingTemporarilyPaused else { return }
        await retryPendingPrintJobs()
        let logger = PrintLogger()
        // Web orders must be confirmed by staff (on iPad/iPhone) before any
        // kitchen/bar/sticker ticket is printed. Unconfirmed web orders are
        // held — staff approval flips isStaffConfirmed and re-dispatches.
        guard staffConfirmedForKitchen(order, logger: logger) else { return }
        let newItems = order.items.filter { !$0.isDeleted && $0.status == "cooking" }
        guard !newItems.isEmpty else { return }
        async let k: () = printKitchenTickets(order, items: newItems, trigger: .onOrder)
        async let b: () = printBarTickets(order, items: newItems, trigger: .onOrder)
        async let s: () = printStickerLabels(order, items: newItems, trigger: .onOrder)
        _ = await (k, b, s)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Trigger: Remote Kitchen Order (Staff iPhone / Web → this iPad)
    // Fires kitchen + bar + sticker tickets for items that are in "cooking"
    // state but have NOT yet been printed on this device (printedAt == nil).
    //
    // Unlike dispatchKitchenOrder (which prints the whole current "cooking"
    // set on an explicit iPad submission), this incremental variant is safe to
    // call repeatedly from the realtime orders/order_items handler: it only
    // sends genuinely new/unprinted lines, so adding items to an order over
    // time prints each new line exactly once instead of re-sending the batch.
    // markPrinted() stamps kitchenPrintedAt / barPrintedAt on success, and the
    // per-role printedAt filter below prevents any duplicate on later events.
    // ─────────────────────────────────────────────────────────────────────────

    /// Dispatch kitchen/bar/sticker tickets for unprinted "cooking" items only.
    /// Safe to call on every realtime order/order_items change.
    func dispatchIncrementalKitchenOrder(_ order: Order) async {
        guard !isAutomaticPrintingTemporarilyPaused else { return }
        await retryPendingPrintJobs()
        let logger = PrintLogger()
        // Gate remote (web) orders on staff confirmation — see dispatchKitchenOrder.
        // This is the realtime path that fires when a web order syncs in, so it
        // is the primary enforcement point for the "confirm before print" rule.
        guard staffConfirmedForKitchen(order, logger: logger) else { return }
        let cooking = order.items.filter { !$0.isDeleted && $0.status == "cooking" }
        guard !cooking.isEmpty else { return }

        // Per-station unprinted filters (printedAt stamped by markPrinted()).
        let kitchenItems = cooking.filter { $0.kitchenPrintedAt == nil }
        let barItems     = cooking.filter { $0.barPrintedAt == nil }
        let labelItems   = cooking.filter { $0.labelPrintedAt == nil }

        // routedItems() inside each print method further narrows items to the
        // stations/categories each physical printer is configured for, so an
        // item destined only for the bar won't produce an empty kitchen ticket.
        async let k: () = printKitchenTickets(order, items: kitchenItems, trigger: .onOrder)
        async let b: () = printBarTickets(order, items: barItems, trigger: .onOrder)
        async let s: () = printStickerLabels(order, items: labelItems, trigger: .onOrder)
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
    /// - Parameter forcePrintReceipt: When true (manual reprint), ignore `auto_print_receipt_on_payment`.
    func dispatchReceipt(_ order: Order, forcePrintReceipt: Bool = false) async {
        guard forcePrintReceipt || !isAutomaticPrintingTemporarilyPaused else { return }
        await retryPendingPrintJobs()
        // A manual copy is receipt-only: never duplicate kitchen/bar tickets
        // and never pulse the cash drawer while reprinting historical sales.
        if forcePrintReceipt {
            await printReceipt(order, force: true)
            return
        }
        // Also send to kitchen/bar/sticker printers that opt in to printOnPayment
        // (covers takeout/delivery stores that don't use "send to kitchen" flow)
        let allItems = order.items.filter { !$0.isDeleted }
        async let k: () = printKitchenTickets(order, items: allItems, trigger: .onPayment)
        async let b: () = printBarTickets(order, items: allItems, trigger: .onPayment)
        async let s: () = printStickerLabels(order, items: allItems, trigger: .onPayment)

        // Finish the receipt before opening the drawer. Sending both commands
        // concurrently to one USB accessory can make the drawer pulse overtake
        // the receipt and produce only a short blank paper feed.
        await printReceipt(order, force: forcePrintReceipt)

        let hasCashPayment = order.payments.contains { payment in
            !payment.isDeleted && payment.status == "completed" && payment.paymentMethod.lowercased() == "cash"
        }
        // Drawer kick is independent of receipt auto-print; gated by its own setting.
        // Missing key defaults to true (legacy always-open-on-cash behavior).
        let autoOpenDrawer: Bool = {
            if UserDefaults.standard.object(forKey: "auto_open_cash_drawer_on_cash_payment") == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: "auto_open_cash_drawer_on_cash_payment")
        }()
        if hasCashPayment && autoOpenDrawer {
            await openCashDrawer()
        }
        _ = await (k, b, s)
    }

    /// Print an unpaid customer check for review before payment.
    /// This is intentionally not idempotent: staff commonly reprint pre-bills after item changes.
    func dispatchPreBill(orders: [Order]) async -> PrintResult {
        await retryPendingPrintJobs()
        let activeOrders = orders.filter {
            !$0.isDeleted && $0.status != "cancelled" && !$0.isSettled &&
            $0.items.contains { !$0.isDeleted && $0.status != "cancelled" }
        }
        guard !activeOrders.isEmpty else {
            return PrintResult(success: false, message: "No printable order items.")
        }
        guard let printers = activePrinters(forRole: "receipt"), !printers.isEmpty else {
            return PrintResult(success: false, message: "No active receipt printer configured.")
        }

        var finalResult = PrintResult(success: false, message: "No printer attempted.")

        for printer in printers {
            let template = defaultTemplate(forRole: "receipt", paperWidth: printer.paperWidth)
            let maxDots = printer.paperWidth == "58mm" ? 180 : 240
            let logoBitmap = ESCPOSBuilder.loadLogoBitmap(maxWidthDots: maxDots)
            let emulation = getEffectiveEmulation(for: printer)
            let data = ESCPOSBuilder.buildPreBill(
                orders: activeOrders,
                template: template,
                logoBitmap: logoBitmap,
                emulation: emulation,
                paperWidth: printer.paperWidth
            )
            let transport = getTransport(for: printer)
            let logger = PrintLogger()
            let result = await transport.deliver(data: data, printer: printer, logger: logger)
            if result.success {
                finalResult = result
            } else if !finalResult.success {
                finalResult = result
            }
        }

        return finalResult
    }

    /// Print a customer check directly from an unpersisted Quick Service cart.
    func dispatchPreBill(draft: PreBillDraft) async -> PrintResult {
        guard !draft.items.isEmpty else {
            return PrintResult(success: false, message: "No printable cart items.")
        }
        guard let printers = activePrinters(forRole: "receipt"), !printers.isEmpty else {
            return PrintResult(success: false, message: "No active receipt printer configured.")
        }

        var finalResult = PrintResult(success: false, message: "No printer attempted.")
        for printer in printers {
            let template = defaultTemplate(forRole: "receipt", paperWidth: printer.paperWidth)
            let maxDots = printer.paperWidth == "58mm" ? 180 : 240
            let data = ESCPOSBuilder.buildPreBill(
                draft: draft,
                template: template,
                logoBitmap: ESCPOSBuilder.loadLogoBitmap(maxWidthDots: maxDots),
                emulation: getEffectiveEmulation(for: printer),
                paperWidth: printer.paperWidth
            )
            let result = await getTransport(for: printer).deliver(
                data: data,
                printer: printer,
                logger: PrintLogger()
            )
            if result.success || !finalResult.success { finalResult = result }
        }
        return finalResult
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Trigger: Legacy / Full Dispatch
    // Retained for backward compatibility. Sends all roles concurrently
    // without trigger filtering. Prefer dispatchKitchenOrder / dispatchReceipt.
    // ─────────────────────────────────────────────────────────────────────────

    /// Legacy: print receipt, kitchen, bar, and label tickets concurrently.
    /// Prefer dispatchKitchenOrder / dispatchReceipt for correct trigger semantics.
    func dispatchAll(_ order: Order) async {
        guard !isAutomaticPrintingTemporarilyPaused else { return }
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

    /// Whether auto-print on payment is enabled for thermal + AirPrint paths.
    /// Missing key defaults to `true` to preserve legacy always-print behavior.
    private var isAutoPrintReceiptEnabled: Bool {
        if UserDefaults.standard.object(forKey: "auto_print_receipt_on_payment") == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: "auto_print_receipt_on_payment")
    }

    /// Print receipt — respects `auto_print_receipt_on_payment` unless `force` is true.
    /// When `force` is true (manual reprint from Staff/iPad UI), bypass PrintJobRecord
    /// idempotency so a second print is allowed.
    private func printReceipt(_ order: Order, force: Bool = false) async {
        let receiptEnabled = UserDefaults.standard.value(forKey: "receipt_printer_enabled") as? Bool ?? true
        guard receiptEnabled else { return }
        guard !UserDefaults.standard.bool(forKey: "disable_receipt_printing") else { return }
        if !force {
            guard isAutoPrintReceiptEnabled else { return }
        }
        guard let printers = activePrinters(forRole: "receipt"), !printers.isEmpty else { return }
        var successfulCopies = 0
        for printer in printers {
            let template = defaultTemplate(forRole: "receipt", paperWidth: printer.paperWidth)
            let maxDots = printer.paperWidth == "58mm" ? 180 : 240
            var job = PrintJob(order: order, role: "receipt", template: template)
            job.hardwarePaperWidth = printer.paperWidth
            job.logoBitmap = ESCPOSBuilder.loadLogoBitmap(maxWidthDots: maxDots)
            if force {
                let result = await deliverJob(job, to: printer, customItems: nil)
                if result.success { successfulCopies += 1 }
            } else {
                let result = await enqueueAndSend(job, to: printer, trigger: .onPayment)
                if result.success { successfulCopies += 1 }
            }
        }
        if successfulCopies > 0 {
            order.receiptPrintCount += successfulCopies
            order.receiptLastPrintedAt = Date()
            order.isSynced = false
            order.updatedAt = Date()
            try? modelContext?.save()
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
              let printers = resolvePrinters(forRole: "kitchen", logger: PrintLogger()),
              !printers.isEmpty else { return }
        for printer in printers {
            // Respect per-printer trigger flag (nil = no filter, used by legacy dispatchAll)
            if let trigger = trigger, !printerResponds(printer, to: trigger) { continue }
            let filtered = routedItems(items: items, printer: printer, stationRole: "kitchen")
            guard !filtered.isEmpty else { continue }
            let job = PrintJob(
                order: order,
                role: "kitchen",
                template: defaultTemplate(forRole: "kitchen", paperWidth: printer.paperWidth),
                hardwarePaperWidth: printer.paperWidth
            )
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
              let printers = resolvePrinters(forRole: "bar", logger: PrintLogger()),
              !printers.isEmpty else { return }
        for printer in printers {
            if let trigger = trigger, !printerResponds(printer, to: trigger) { continue }
            let filtered = routedItems(items: items, printer: printer, stationRole: "bar")
            guard !filtered.isEmpty else { continue }
            let job = PrintJob(
                order: order,
                role: "bar",
                template: defaultTemplate(forRole: "bar", paperWidth: printer.paperWidth),
                hardwarePaperWidth: printer.paperWidth
            )
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
              let printers = resolvePrinters(forRole: "label", logger: PrintLogger()),
              !printers.isEmpty else { return }
        for printer in printers {
            if let trigger = trigger, !printerResponds(printer, to: trigger) { continue }
            let filtered = routedItems(items: items, printer: printer, stationRole: "label")
            guard !filtered.isEmpty else { continue }
            let job = PrintJob(
                order: order,
                role: "label",
                template: defaultTemplate(forRole: "label", paperWidth: printer.paperWidth),
                hardwarePaperWidth: printer.paperWidth
            )
            let result = await enqueueAndSend(job, to: printer, customItems: filtered, trigger: trigger ?? .legacy)
            if !result.success {
                await postFailureNotification(printerName: printer.name, role: "สติกเกอร์", itemCount: filtered.count, message: result.message, order: order)
            }
        }
    }

    private func postFailureNotification(printerName: String, role: String, itemCount: Int, message: String, order: Order) async {
        await MainActor.run {
            let title = LocalizationManager.shared.t("notif_printer_failure_title", printerName)
            let body = LocalizationManager.shared.t("notif_printer_failure_body", itemCount, message)
            InAppNotificationManager.shared.post(
                InAppNotification(
                    type: .printerAlert,
                    title: title,
                    body: body,
                    tableNumber: order.tableSession?.table?.tableNumber,
                    dedupeKey: "printer:\(printerName):\(order.id.uuidString)"
                )
            )

        }
    }

    /// Returns true if the printer has at least one routing rule matching the trigger.
    /// A printer with no routing rules prints prep tickets when orders are sent,
    /// but does not re-print prep tickets on payment.
    private func printerResponds(_ printer: Printer, to trigger: PrintTrigger) -> Bool {
        let activeRules = printer.routingRules.filter { !$0.isDeleted }
        // Missing key preserves the legacy/default Table Service behaviour.
        let tableSystemEnabled = UserDefaults.standard.object(forKey: "enable_table_system") as? Bool ?? true
        let isQuickService = !tableSystemEnabled
        return PrintRoutingGate.respondsToPrepTrigger(
            trigger: trigger.rawValue,
            isQuickService: isQuickService,
            printOnOrderValues: activeRules.map(\.printOnOrder),
            printOnPaymentValues: activeRules.map(\.printOnPayment)
        )
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
        tenders: [ShiftTenderSummary],
        receiptCount: Int,
        failedPaymentCount: Int,
        cashMovementsIn: Double,
        cashMovementsOut: Double,
        openedBy: String,
        closedBy: String,
        isThai: Bool,
        respectAutoPrintSetting: Bool = true
    ) async -> Bool {
        if respectAutoPrintSetting,
           !(UserDefaults.standard.object(forKey: "print_close_shift") as? Bool ?? true) { return false }
        guard let printers = activePrinters(forRole: "receipt"), !printers.isEmpty else { return false }
        var didPrint = false
        for printer in printers {
            let emulation = getEffectiveEmulation(for: printer)
            let data = ShiftReportBuilder.buildZReport(
                session: session,
                report: report,
                tenders: tenders,
                receiptCount: receiptCount,
                failedPaymentCount: failedPaymentCount,
                cashMovementsIn: cashMovementsIn,
                cashMovementsOut: cashMovementsOut,
                openedBy: openedBy,
                closedBy: closedBy,
                isThai: isThai,
                emulation: emulation
            )
            let transport = getTransport(for: printer)
            let logger = PrintLogger()
            let result = await transport.deliver(data: data, printer: printer, logger: logger)
            didPrint = didPrint || result.success
        }
        return didPrint
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Diagnostic Test Print
    // ─────────────────────────────────────────────────────────────────────────

    /// Diagnostic test print with console logging
    func printTest(to printer: Printer, previewType: String? = nil) async -> (success: Bool, log: [String]) {
        let logger = PrintLogger()
        let type = previewType ?? printer.role
        let template = defaultTemplate(forRole: type, paperWidth: printer.paperWidth)
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
            let maxDots = printer.paperWidth == "58mm" ? 180 : 240
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
        let usesStarSDK = printer.connectionType == "usb" && emulation == "star"
        let data = usesStarSDK ? Data() : CashDrawerBuilder.buildOpenDrawer(emulation: emulation)
        logger.append("[2] Compiled \(usesStarSDK ? "StarIO10" : "\(data.count)-byte") drawer command.")
        logger.append("[3] Sending drawer pulse...")

        let transport: PrinterTransport = usesStarSDK ? StarDrawerTransport() : getTransport(for: printer)
        let result = await deliverSerialized(data: data, printer: printer, logger: logger, transport: transport)
        logger.append(result.success ? "✓ Cash drawer pulse sent." : "✗ Cash drawer pulse failed.")
        logger.append("    Detail: \(result.message)")
        return (result.success, logger.logs)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Connectivity Test (reachability only — no paper emitted)
    // Standards-compliant "is this printer online?" check. Works for ANY
    // network printer supported on iPad/iPhone. USB uses MFi accessory
    // presence; Bluetooth reports guidance since verification needs a job.
    // ─────────────────────────────────────────────────────────────────────────
    func probeConnectivity(to printer: Printer) async -> (success: Bool, log: [String]) {
        let logger = PrintLogger()
        logger.append("[1] Checking printer connectivity...")
        logger.append("    Name: \(printer.name)")
        logger.append("    Interface: \(printer.connectionType.uppercased())")

        switch printer.connectionType {
        case "network":
            guard let ip = printer.ipAddress, !ip.isEmpty else {
                logger.append("    ERROR: No IP address configured.")
                return (false, logger.logs)
            }
            logger.append("    Probing \(ip):\(printer.port) (RAW socket)...")
            let result = await TCPConnectivityProbe.probe(host: ip, port: UInt16(printer.port))
            logger.append("    Result: \(result.state.rawValue)")
            logger.append("    \(result.detail)")
            if result.isReachable {
                logger.append("✓ Printer is ONLINE and reachable.")
            } else {
                logger.append("✗ Printer is not reachable.")
            }
            return (result.isReachable, logger.logs)

        case "usb":
            let accessories = USBAccessoryProbe.connectedAccessories()
            logger.append("    Found \(accessories.count) MFi USB accessory/accessories.")
            let supported = accessories.filter { $0.isSupported }
            for acc in accessories {
                logger.append("    • \(acc.name) (\(acc.manufacturer) \(acc.model)) — \(acc.isSupported ? "supported" : "unsupported")")
            }
            if supported.isEmpty {
                logger.append("✗ No supported USB printer detected. Check the cable and power.")
                return (false, logger.logs)
            }
            logger.append("✓ Supported USB printer detected.")
            return (true, logger.logs)

        case "bluetooth":
            logger.append("    Bluetooth reachability cannot be verified without a print job.")
            logger.append("    Ensure the printer is paired in iPad/iPhone Settings, then run a Test Print.")
            return (true, logger.logs)

        default:
            logger.append("✗ Unknown connection type.")
            return (false, logger.logs)
        }
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

        if record.status == "succeeded" || record.status == "sent" {
            return PrintResult(success: true, message: "Already sent to printer.")
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
            record.status = result.confirmation == .confirmed ? "succeeded" : "sent"
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
                emulation: emulation,
                paperWidth: printer.paperWidth
            )
        } else if let customItems = customItems, job.role == "label" || job.role == "sticker" {
            data = buildLabelPayload(order: job.order, items: customItems, template: job.template, emulation: emulation)
        } else {
            data = renderer.render(job: job, emulation: emulation)
        }

        guard !data.isEmpty, job.role != "receipt" || data.count >= 32 else {
            return PrintResult(success: false, message: "Receipt renderer produced an empty or incomplete payload.")
        }

        let transport = getTransport(for: printer)
        return await deliverSerialized(data: data, printer: printer, logger: logger, transport: transport)
    }

    private func deliverSerialized(
        data: Data,
        printer: Printer,
        logger: PrintLogger,
        transport: PrinterTransport
    ) async -> PrintResult {
        let key = physicalPrinterKey(printer)
        let result: PrintResult = await deliveryCoordinator.withReservation(key: key) {
            await transport.deliver(data: data, printer: printer, logger: logger)
        }
        return result
    }

    func retryPendingPrintJobs(limit: Int = 20) async {
        guard !isAutomaticPrintingTemporarilyPaused else { return }
        guard let ctx = modelContext else { return }
        let now = Date()
        let records = ((try? ctx.fetch(FetchDescriptor<PrintJobRecord>())) ?? [])
            .filter {
                $0.status != "succeeded"
                    && $0.status != "sent"
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

            let template = defaultTemplate(forRole: record.role, paperWidth: printer.paperWidth)
            var job = PrintJob(order: order, role: record.role, template: template)
            job.hardwarePaperWidth = printer.paperWidth
            if record.role == "receipt" {
                let paperWidth = template?.paperWidth ?? printer.paperWidth
                let maxDots = paperWidth == "58mm" ? 180 : 240
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
        let rawTable = order.tableSession?.table?.tableNumber
        let tableLabel: String = {
            guard let rawTable, !rawTable.isEmpty, rawTable.uppercased() != "QUICK" else { return "Takeaway" }
            return rawTable
        }()
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
        // Normalise to lowercase so "STAR", "Star", "star" all map correctly
        guard let brand = PrinterBrand(rawValue: emulation.lowercased()) else { return ESCPosRenderer() }
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
        // Normalise stored emulation string to lowercase to match PrinterBrand rawValues
        return printer.emulation.lowercased()
    }

    func hasActiveReceiptPrinters() -> Bool {
        return !(activePrinters(forRole: "receipt")?.isEmpty ?? true)
    }

    public var hasAnyActivePrinter: Bool {
        guard let ctx = modelContext else { return false }
        let all = (try? ctx.fetch(FetchDescriptor<Printer>())) ?? []
        return all.contains { !$0.isDeleted && $0.isActive }
    }

    private func activePrinters(forRole role: String) -> [Printer]? {
        guard let ctx = modelContext else { return nil }
        let all = (try? ctx.fetch(FetchDescriptor<Printer>())) ?? []
        return uniquePhysicalPrinters(all.filter { !$0.isDeleted && $0.isActive && $0.role == role })
    }

    // ────────────────────────────────────────────────────────────────────
    // MARK: - Printer resolution with Single-Printer fallback
    //
    // resolvePrinters(forRole:) is the station-aware resolver used by every
    // role-level print function. Beyond the strict role match performed by
    // activePrinters(forRole:), it adds two operator-facing behaviours:
    //
    //   • Single-Printer Mode ("single_printer_mode"): when the shop has one
    //     physical printer (testing, or a station printer is broken) the
    //     operator can route EVERY job — kitchen, bar, sticker, receipt — to
    //     one device. All active printers become eligible for every role.
    //
    //   • Receipt fallback ("printer_role_fallback"): when no printer is
    //     configured for the requested station but a receipt printer exists,
    //     the job falls back to the receipt printer instead of silently
    //     printing nothing. This is what lets "kitchen" tickets come out of
    //     the same printer as the receipt when only one printer is set up.
    //
    // Both toggles default to false so existing multi-printer shops keep the
    // strict per-role routing they configured. When a fallback is taken, a
    // diagnostic line is logged so an empty print run is never a silent no-op.
    // ────────────────────────────────────────────────────────────────────
    private func resolvePrinters(forRole role: String, logger: PrintLogger?) -> [Printer]? {
        guard let ctx = modelContext else { return nil }
        let all = (try? ctx.fetch(FetchDescriptor<Printer>())) ?? []
        let live = all.filter { !$0.isDeleted && $0.isActive }

        let singlePrinterMode = UserDefaults.standard.bool(forKey: "single_printer_mode")
        let fallbackEnabled = UserDefaults.standard.bool(forKey: "printer_role_fallback")

        // Delegate the routing decision to the pure gate (pinned by unit tests).
        let candidates = PrintRoutingGate.candidateRoles(
            forStation: role,
            hasStationPrinter: live.contains { $0.role == role },
            hasReceiptPrinter: live.contains { $0.role == "receipt" },
            singlePrinterMode: singlePrinterMode,
            roleFallback: fallbackEnabled
        )

        guard let choice = candidates.first else {
            logResolveMiss(role: role, reason: "no printer configured for role and no fallback available", logger: logger)
            return nil
        }

        // "*" is the Single-Printer sentinel — every active printer is eligible.
        if choice == "*" {
            let printers = uniquePhysicalPrinters(live)
            if printers.isEmpty {
                logResolveMiss(role: role, reason: "single_printer_mode on but no active printer", logger: logger)
                return nil
            }
            return printers
        }

        if choice != role {
            logResolveMiss(role: role, reason: "no \(role) printer — falling back to \(choice) printer", logger: logger)
        }
        let printers = uniquePhysicalPrinters(live.filter { $0.role == choice })
        return printers.isEmpty ? nil : printers
    }

    /// Emit a diagnostic line whenever a station resolves to zero printers or
    /// takes a fallback path, so "kitchen didn't print" is always explainable.
    private func logResolveMiss(role: String, reason: String, logger: PrintLogger?) {
        logger?.append("resolvePrinters[\(role)]: \(reason)")
    }

    /// Whether an order is cleared for kitchen/bar/sticker printing.
    ///
    /// Only orders that originate from the web ordering channel are gated:
    /// a web order must be explicitly confirmed by staff on an iPad/iPhone
    /// (which flips `isStaffConfirmed` to true and re-dispatches) before its
    /// tickets are printed or sent to the kitchen. Orders created directly on
    /// the POS (iPad) or staff app (iPhone) are already staff-initiated, so
    /// they are always cleared. The check is defensive against older records
    /// where the field may be absent (defaults to confirmed).
    private func staffConfirmedForKitchen(_ order: Order, logger: PrintLogger?) -> Bool {
        if PrintRoutingGate.kitchenPrintAllowed(
            orderSource: order.orderSource,
            isStaffConfirmed: order.isStaffConfirmed
        ) { return true }
        logger?.append(
            "kitchen dispatch held for web order \(order.orderNumber): awaiting staff confirmation"
        )
        return false
    }

    private func uniquePhysicalPrinters(_ printers: [Printer]) -> [Printer] {
        var seen = Set<String>()
        return printers.filter { printer in
            let key = physicalPrinterKey(printer)
            return seen.insert(key).inserted
        }
    }

    private func physicalPrinterKey(_ printer: Printer) -> String {
        switch printer.connectionType {
        case "network":
            return "network|\(printer.ipAddress ?? "")|\(printer.port)"
        case "bluetooth":
            return "bluetooth|\(printer.bluetoothName ?? printer.name)"
        case "usb":
            let emulation = getEffectiveEmulation(for: printer)
            let accessoryIdentifier = usbAccessoryIdentifier(for: printer)
            // USB transports currently target FIRST_FOUND_DEVICE. Treat legacy
            // duplicate configurations as one physical destination even when
            // iOS has not exposed the accessory serial yet.
            let deviceIdentifier = accessoryIdentifier ?? "first-found-device"
            return "usb|\(emulation)|\(printer.paperWidth)|\(deviceIdentifier)"
        default:
            return "\(printer.connectionType)|\(printer.name)"
        }
    }

    private func usbAccessoryIdentifier(for printer: Printer) -> String? {
        guard printer.connectionType == "usb" else { return nil }

        let manager = EAAccessoryManager.shared()
        let emulation = getEffectiveEmulation(for: printer)
        let brand = PrinterBrand(rawValue: emulation.lowercased())
        let protocols = brand?.mfiProtocols ?? []

        for accessory in manager.connectedAccessories where !protocols.isEmpty {
            if accessory.protocolStrings.contains(where: { protocols.contains($0) }) {
                let serial = accessory.serialNumber
                if !serial.isEmpty {
                    return "serial|\(serial)"
                }
                return "conn|\(accessory.connectionID)"
            }
        }

        return nil
    }

    private func fetchOrder(id: UUID) -> Order? {
        guard let ctx = modelContext else { return nil }
        return ((try? ctx.fetch(FetchDescriptor<Order>())) ?? []).first { $0.id == id && !$0.isDeleted }
    }

    private func fetchPrinter(id: UUID) -> Printer? {
        guard let ctx = modelContext else { return nil }
        return ((try? ctx.fetch(FetchDescriptor<Printer>())) ?? []).first { $0.id == id && !$0.isDeleted && $0.isActive }
    }

    private func defaultTemplate(forRole role: String, paperWidth: String? = nil) -> ReceiptTemplate? {
        guard let ctx = modelContext else { return nil }
        let templateType = (role == "label" || role == "sticker") ? "sticker" : role

        let descriptor = FetchDescriptor<ReceiptTemplate>(
            predicate: #Predicate<ReceiptTemplate> { !$0.isDeleted }
        )
        let all = (try? ctx.fetch(descriptor)) ?? []
        let filtered = all.filter { $0.templateType == templateType }
        let matchingWidth = paperWidth.map { width in filtered.filter { $0.paperWidth == width } } ?? []
        return matchingWidth.first(where: { $0.isDefault })
            ?? matchingWidth.first
            ?? filtered.first(where: { $0.isDefault })
            ?? filtered.first
    }

    /// Narrows the item set for a single physical printer.
    ///
    /// `stationRole` is the LOGICAL station this print run represents
    /// (kitchen/bar/label), which can differ from `printer.role` when the job
    /// was resolved via Single-Printer Mode or the receipt fallback. Station
    /// matching always uses `stationRole` so a kitchen run keeps kitchen items
    /// even when it is physically going to the receipt printer. Category
    /// routing rules are only applied when the printer is actually configured
    /// for this station (printer.role == stationRole); a fallback/aggregated
    /// printer ignores per-category rules so nothing is silently dropped.
    private func routedItems(items: [OrderItem], printer: Printer, stationRole: String) -> [OrderItem] {
        let activeRules = printer.routingRules.filter { !$0.isDeleted }
        let allowedSlugs = Set(activeRules.compactMap { $0.categoryId })
        let applyCategoryRules = PrintRoutingGate.shouldApplyCategoryRules(
            printerRole: printer.role,
            stationRole: stationRole,
            hasActiveRules: !activeRules.isEmpty
        )
        return items.filter { item in
            if !matchesPrinterStation(item: item, role: stationRole) { return false }
            if !applyCategoryRules { return true }
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
            let logger = PrintLogger()
            let transport: PrinterTransport
            let data: Data
            if printer.connectionType == "usb" && emulation == "star" {
                transport = StarDrawerTransport()
                data = Data()
            } else {
                transport = getTransport(for: printer)
                data = CashDrawerBuilder.buildOpenDrawer(emulation: emulation)
            }
            _ = await deliverSerialized(data: data, printer: printer, logger: logger, transport: transport)
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
