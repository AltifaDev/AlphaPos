import Foundation
import SwiftData

/// A branch-scoped dining area (floor/room/patio) that is synced across devices.
/// `floorNumber` remains as the canvas/layout key while tables migrate to the
/// stable UUID in `floorId`.
@Model
final class FloorData {
    @Attribute(.unique) var uuid: UUID
    var floorNumber: Int
    var name: String
    var branchId: String
    var sortOrder: Int
    var isActive: Bool
    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date

    var id: Int { floorNumber }

    init(
        uuid: UUID = UUID(),
        floorNumber: Int,
        name: String,
        branchId: String,
        sortOrder: Int = 0,
        isActive: Bool = true,
        isSynced: Bool = false,
        isDeleted: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.uuid = uuid
        self.floorNumber = floorNumber
        self.name = name
        self.branchId = branchId
        self.sortOrder = sortOrder
        self.isActive = isActive
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
    }
}
