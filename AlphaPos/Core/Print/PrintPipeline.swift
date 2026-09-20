import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Print Pipeline Types & Protocols
// ─────────────────────────────────────────────────────────────────────────────

enum PrintCommandSet: String, Sendable {
    case escpos = "ESC/POS"
    case starPRNT = "StarPRNT"
    case tspl = "TSPL"
}

struct PrintJob: Sendable {
    let order: Order
    let role: String // receipt, kitchen, bar, label
    let template: ReceiptTemplate?
    /// Optional heading for a category-split prep ticket (for example, "เมนูผัด").
    /// The order number and queue remain sourced from the same `order` on every ticket.
    var categoryLabel: String? = nil
    var hardwarePaperWidth: String? = nil
    var logoBitmap: ESCPOSBuilder.LogoBitmap? = nil  // actual-dimension logo for GS v 0
    var typography: PrintTypographyProfile? = nil
}

struct PrintResult: Sendable {
    let success: Bool
    let message: String
    var confirmation: PrintConfirmation = .accepted
}

enum PrintConfirmation: String, Sendable {
    case accepted
    case confirmed
}

protocol PrinterRenderer: Sendable {
    func render(job: PrintJob, emulation: String) -> Data
}

@MainActor
protocol PrinterTransport: Sendable {
    func deliver(data: Data, printer: Printer, logger: PrintLogger) async -> PrintResult
}

enum PrepStation: String {
    case kitchen
    case bar
}

enum ReceiptComplianceGate {
    static func canIssueAbbreviatedTaxInvoice(vatEnabled: Bool, taxId: String) -> Bool {
        let digits = taxId.filter(\.isNumber)
        return vatEnabled && digits.count == 13 && digits != "1234567890123"
    }
}

// ─────────────────────────────────────────────────────────────────────────
// MARK: - PrintRoutingGate (pure, unit-testable)
//
// Pure decision helpers for the printer-resolution and web-order-confirmation
// rules. Kept free of SwiftData / MainActor so they can be exercised in the
// standalone swiftc test runner. PrintService mirrors these decisions; keep the
// two in sync (the unit tests pin the behaviour).
// ─────────────────────────────────────────────────────────────────────────
enum PrintRoutingGate {

    /// Whether a prep printer should answer a dispatch trigger.
    /// Quick Service is payment-first, so its kitchen/bar/label tickets must
    /// answer `onPayment` even for legacy rules saved before that workflow was
    /// represented in Printer Settings. Table Service continues to respect the
    /// per-rule trigger flags.
    static func respondsToPrepTrigger(
        trigger: String,
        isQuickService: Bool,
        printOnOrderValues: [Bool],
        printOnPaymentValues: [Bool]
    ) -> Bool {
        if trigger == "legacy" { return true }
        if isQuickService && trigger == "onPayment" { return true }
        if printOnOrderValues.isEmpty && printOnPaymentValues.isEmpty {
            return trigger == "onOrder"
        }
        switch trigger {
        case "onOrder": return printOnOrderValues.contains(true)
        case "onPayment": return printOnPaymentValues.contains(true)
        default: return false
        }
    }

    /// Which physical-printer roles should serve a logical station, given the
    /// operator toggles. Returns the ordered list of candidate roles to try;
    /// PrintService resolves each to concrete printers.
    ///
    /// - singlePrinterMode: route every job to any active printer.
    /// - roleFallback: when no printer matches the station, fall back to the
    ///   receipt printer.
    static func candidateRoles(
        forStation station: String,
        hasStationPrinter: Bool,
        hasReceiptPrinter: Bool,
        singlePrinterMode: Bool,
        roleFallback: Bool
    ) -> [String] {
        if singlePrinterMode {
            // Everything collapses onto whatever active printers exist.
            return ["*"]
        }
        if hasStationPrinter {
            return [station]
        }
        if roleFallback, station != "receipt", hasReceiptPrinter {
            return ["receipt"]
        }
        return []
    }

    /// Whether a station print run should apply per-category routing rules.
    /// Rules only apply when the printer is actually configured for that
    /// station; a fallback/aggregated printer prints everything for the station.
    static func shouldApplyCategoryRules(
        printerRole: String,
        stationRole: String,
        hasActiveRules: Bool
    ) -> Bool {
        printerRole == stationRole && hasActiveRules
    }

    /// Whether an order is cleared to print kitchen/bar/sticker tickets.
    /// Only web orders are gated: they must be staff-confirmed first.
    static func kitchenPrintAllowed(
        orderSource: String,
        isStaffConfirmed: Bool
    ) -> Bool {
        orderSource != "web" || isStaffConfirmed
    }

    /// Whether THIS device should print directly when staff approve a web order.
    /// Only the designated station device prints, so a separate station iPad
    /// doesn't double-print alongside the approving device.
    static func approvingDeviceShouldPrint(isThisDeviceStation: Bool) -> Bool {
        isThisDeviceStation
    }
}

enum OrderRoutingResolver {
    static func routingMap() -> [String: String] {
        let raw = UserDefaults.standard.string(forKey: "kds_category_routing_json") ?? "{}"
        return (try? JSONDecoder().decode([String: String].self, from: Data(raw.utf8))) ?? [:]
    }

    static func stations(for item: OrderItem, routing: [String: String]? = nil) -> Set<PrepStation> {
        let map = routing ?? routingMap()
        let categoryName = item.menuItem?.category?.name ?? ""
        let categoryId = item.menuItem?.category?.id.uuidString.lowercased() ?? ""
        let categorySlug = slug(categoryName)
        let resolved = map[categoryId] ?? map[categoryName] ?? map[categorySlug] ?? map["*"]

        switch resolved {
        case "bar":
            return [.bar]
        case "both":
            return [.kitchen, .bar]
        case "kitchen":
            return [.kitchen]
        default:
            return isBeverage(categoryName) ? [.bar] : [.kitchen]
        }
    }

    static func slug(_ value: String) -> String {
        value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isBeverage(_ categoryName: String) -> Bool {
        let lower = categoryName.lowercased()
        return lower.contains("beverage")
            || lower.contains("drink")
            || lower.contains("juice")
            || lower.contains("tea")
            || lower.contains("coffee")
            || lower.contains("smoothie")
            || lower.contains("soda")
            || lower.contains("cocktail")
            || lower.contains("beer")
            || lower.contains("wine")
            // Thai / regional category names commonly used in merchant menus
            || lower.contains("เครื่องดื่ม")
            || lower.contains("กาแฟ")
            || lower.contains("ชานม")
            || lower.contains("ชาเย็น")
            || lower.contains("น้ำดื่ม")
            || lower.contains("น้ำผลไม้")
            || lower.contains("แอลกอฮอล")
            || lower.contains("เบียร์")
            || lower.contains("ไวน์")
            || lower.contains("โซดา")
    }
}
