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
    var logoBitmap: ESCPOSBuilder.LogoBitmap? = nil  // actual-dimension logo for GS v 0
}

struct PrintResult: Sendable {
    let success: Bool
    let message: String
}

protocol PrinterRenderer: Sendable {
    func render(job: PrintJob, emulation: String) -> Data
}

protocol PrinterTransport: Sendable {
    func deliver(data: Data, printer: Printer, logger: PrintLogger) async -> PrintResult
}

enum PrepStation: String {
    case kitchen
    case bar
}

enum OrderRoutingResolver {
    static func routingMap() -> [String: String] {
        let raw = UserDefaults.standard.string(forKey: "kds_category_routing_json") ?? "{}"
        return (try? JSONDecoder().decode([String: String].self, from: Data(raw.utf8))) ?? [:]
    }

    static func stations(for item: OrderItem, routing: [String: String]? = nil) -> Set<PrepStation> {
        let map = routing ?? routingMap()
        let categoryName = item.menuItem?.category?.name ?? ""
        let categorySlug = slug(categoryName)
        let resolved = map[categoryName] ?? map[categorySlug] ?? map["*"]

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
    }
}
