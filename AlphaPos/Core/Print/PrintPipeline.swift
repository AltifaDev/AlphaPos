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
