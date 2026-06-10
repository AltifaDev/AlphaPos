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
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
    }
}
