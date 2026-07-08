import Foundation
import SwiftData

@Model
final class Printer {
    @Attribute(.unique) var id: UUID
    var name: String
    var connectionType: String // "network", "bluetooth", "usb"
    var ipAddress: String?
    var port: Int
    var bluetoothName: String?
    var paperWidth: String // "80mm", "58mm"
    var status: String // "online", "offline", "error", "unknown"
    var role: String // "receipt", "kitchen", "label"
    var isActive: Bool
    var emulation: String // "escpos", "starprnt", "tspl"

    @Relationship(deleteRule: .cascade, inverse: \PrintRoutingRule.printer)
    var routingRules: [PrintRoutingRule] = []

    // Offline-First Sync Metadata
    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        connectionType: String = "network",
        ipAddress: String? = nil,
        port: Int = 9100,
        bluetoothName: String? = nil,
        paperWidth: String = "80mm",
        status: String = "unknown",
        role: String = "kitchen",
        isActive: Bool = true,
        emulation: String = "escpos",
        isSynced: Bool = false,
        isDeleted: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.connectionType = connectionType
        self.ipAddress = ipAddress
        self.port = port
        self.bluetoothName = bluetoothName
        self.paperWidth = paperWidth
        self.status = status
        self.role = role
        self.isActive = isActive
        self.emulation = emulation
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
    }
}

@Model
final class PrintJobRecord {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var idempotencyKey: String
    var orderId: UUID
    var orderNumber: String
    var printerId: UUID
    var printerName: String
    var role: String
    var trigger: String
    var itemIdsCSV: String
    var status: String // "queued", "printing", "succeeded", "failed"
    var attempts: Int
    var maxAttempts: Int
    var lastError: String?
    var createdAt: Date
    var updatedAt: Date
    var nextAttemptAt: Date?
    var deliveredAt: Date?

    init(
        id: UUID = UUID(),
        idempotencyKey: String,
        orderId: UUID,
        orderNumber: String,
        printerId: UUID,
        printerName: String,
        role: String,
        trigger: String,
        itemIdsCSV: String,
        status: String = "queued",
        attempts: Int = 0,
        maxAttempts: Int = 3,
        lastError: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        nextAttemptAt: Date? = nil,
        deliveredAt: Date? = nil
    ) {
        self.id = id
        self.idempotencyKey = idempotencyKey
        self.orderId = orderId
        self.orderNumber = orderNumber
        self.printerId = printerId
        self.printerName = printerName
        self.role = role
        self.trigger = trigger
        self.itemIdsCSV = itemIdsCSV
        self.status = status
        self.attempts = attempts
        self.maxAttempts = maxAttempts
        self.lastError = lastError
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.nextAttemptAt = nextAttemptAt
        self.deliveredAt = deliveredAt
    }
}
