import Foundation
import SwiftData

@Model
final class FloorPlanImage {
    @Attribute(.unique) var id: UUID
    var merchantId: String
    var floor: Int
    /// Filename only (e.g. "floor_plan_1.jpg") — resolved against Documents directory at runtime
    var imageFilename: String
    var updatedAt: Date
    var isSynced: Bool
    var isDeleted: Bool
    
    // Background Independent Transform
    var scale: Double = 1.0
    var offsetX: Double = 0.0
    var offsetY: Double = 0.0

    init(
        id: UUID = UUID(),
        merchantId: String,
        floor: Int,
        imageFilename: String,
        scale: Double = 1.0,
        offsetX: Double = 0.0,
        offsetY: Double = 0.0,
        updatedAt: Date = Date(),
        isSynced: Bool = false,
        isDeleted: Bool = false
    ) {
        self.id = id
        self.merchantId = merchantId
        self.floor = floor
        self.imageFilename = imageFilename
        self.scale = scale
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.updatedAt = updatedAt
        self.isSynced = isSynced
        self.isDeleted = isDeleted
    }

    /// Resolved absolute path for reading the image file
    var resolvedImagePath: String? {
        guard !imageFilename.isEmpty else { return nil }
        let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docsURL.appendingPathComponent(imageFilename).path
    }
}
