import Foundation
import SwiftData

/// Represents a reusable table layout configuration (tables layout and background images)
/// scoped strictly to a specific merchant and branch for security.
@Model
final class TableLayoutPreset {
    @Attribute(.unique) var id: UUID
    var merchantId: String
    var branchId: String
    var floor: Int
    var name: String // e.g. "Layout A", "Layout B"
    
    // Background Image associated with this preset
    var bgImageFilename: String?
    var bgImageScale: Double = 1.0
    var bgImageOffsetX: Double = 0.0
    var bgImageOffsetY: Double = 0.0
    
    // Serialized JSON array of [TableLayoutItem] containing table numbers, coordinates, zones, shapes, etc.
    var tableLayoutJson: String
    
    var updatedAt: Date
    var isSynced: Bool
    var isDeleted: Bool

    init(
        id: UUID = UUID(),
        merchantId: String,
        branchId: String,
        floor: Int,
        name: String,
        bgImageFilename: String? = nil,
        bgImageScale: Double = 1.0,
        bgImageOffsetX: Double = 0.0,
        bgImageOffsetY: Double = 0.0,
        tableLayoutJson: String,
        updatedAt: Date = Date(),
        isSynced: Bool = false,
        isDeleted: Bool = false
    ) {
        self.id = id
        self.merchantId = merchantId
        self.branchId = branchId
        self.floor = floor
        self.name = name
        self.bgImageFilename = bgImageFilename
        self.bgImageScale = bgImageScale
        self.bgImageOffsetX = bgImageOffsetX
        self.bgImageOffsetY = bgImageOffsetY
        self.tableLayoutJson = tableLayoutJson
        self.updatedAt = updatedAt
        self.isSynced = isSynced
        self.isDeleted = isDeleted
    }
}

/// Codable item containing individual table configuration inside the serialized preset JSON
struct TableLayoutItem: Codable {
    var id: UUID
    var tableNumber: String
    var capacity: Int
    var tableShape: String // "rectangle", "square", "circle", "oval"
    var positionX: Double
    var positionY: Double
    var zone: String?
}
