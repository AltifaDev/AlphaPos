import Foundation

/// One source of truth for order identifiers shown outside the table-management UI.
/// Quick Service is queue-led; Table Service is table-led. The legacy QUICK
/// sentinel is never presented to staff as a real table number.
struct OrderDisplayIdentity {
    let isQuickService: Bool
    let primaryLabel: String
    let orderLabel: String
    let queueNumber: String?
    let tableNumber: String?
    let serviceReference: String

    init(order: Order, tableSystemEnabled: Bool) {
        let rawTable = order.tableSession?.table?.tableNumber
            ?? order.floorTableNumber
        let trimmedTable = rawTable?.trimmingCharacters(in: .whitespacesAndNewlines)
        let validTable = trimmedTable.flatMap { value in
            value.isEmpty || value.uppercased() == "QUICK" ? nil : value
        }
        let trimmedQueue = order.queueNumber?.trimmingCharacters(in: .whitespacesAndNewlines)
        let validQueue = trimmedQueue.flatMap { $0.isEmpty ? nil : $0 }

        isQuickService = !tableSystemEnabled || trimmedTable?.uppercased() == "QUICK"
        queueNumber = validQueue
        tableNumber = validTable
        orderLabel = "order_number".t + order.orderNumber
        serviceReference = validTable
            ?? validQueue.map { "Q-\($0)" }
            ?? "ORDER-\(order.orderNumber)"

        if isQuickService {
            primaryLabel = validQueue.map { "queue_number".t + $0 }
                ?? orderLabel
        } else {
            primaryLabel = validTable.map {
                LocalizationManager.shared.t("table_number_template", $0)
            } ?? validQueue.map { "queue_number".t + $0 }
                ?? orderLabel
        }
    }

    static func label(forServiceReference reference: String) -> String {
        if reference.hasPrefix("Q-") {
            return "queue_number".t + String(reference.dropFirst(2))
        }
        if reference.hasPrefix("ORDER-") {
            return "order_number".t + String(reference.dropFirst(6))
        }
        return LocalizationManager.shared.t("table_number_template", reference)
    }
}
