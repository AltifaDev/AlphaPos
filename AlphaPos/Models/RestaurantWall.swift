import Foundation
import SwiftData

enum WallType: String, Codable {
    case straight
    case curved
}

@Model
final class RestaurantWall {
    @Attribute(.unique) var id: UUID
    var floor: Int
    var typeString: String
    var startX: Double
    var startY: Double
    var endX: Double
    var endY: Double
    var controlX: Double?
    var controlY: Double?
    var strokeWidth: Double
    var updatedAt: Date
    var isSynced: Bool
    var isDeleted: Bool
    
    var type: WallType {
        get { WallType(rawValue: typeString) ?? .straight }
        set { typeString = newValue.rawValue }
    }
    
    init(id: UUID = UUID(), floor: Int, type: WallType = .straight, startX: Double, startY: Double, endX: Double, endY: Double, controlX: Double? = nil, controlY: Double? = nil, strokeWidth: Double = 10.0, isSynced: Bool = false, isDeleted: Bool = false) {
        self.id = id
        self.floor = floor
        self.typeString = type.rawValue
        self.startX = startX
        self.startY = startY
        self.endX = endX
        self.endY = endY
        self.controlX = controlX
        self.controlY = controlY
        self.strokeWidth = strokeWidth
        self.updatedAt = Date()
        self.isSynced = isSynced
        self.isDeleted = isDeleted
    }
}
