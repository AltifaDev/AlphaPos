import Foundation
import SwiftData

@Model
final class RestaurantTable {
    @Attribute(.unique) var id: UUID
    var tableNumber: String
    var capacity: Int
    var status: String // "vacant", "occupied", "reserved", "cleaning"
    var qrCodeIdentifier: String?
    
    // Floor plan positioning (for drag & drop layout)
    var positionX: Double = 0
    var positionY: Double = 0
    /// Visual scale on the floor plan (1.0 = default). Used for corner-handle resize in edit mode.
    var layoutScale: Double = 1.0
    var floor: Int? = 1
    /// Stable reference to the synced branch dining area.
    var floorId: UUID?
    /// Branch scope is stored on the table so offline edits cannot be uploaded
    /// into whichever branch happens to be active later.
    var branchId: String = ""
    var isRound: Bool = false   // kept for backward compatibility
    var tableShape: String = "rectangle" // "rectangle", "square", "circle", "oval"
    var zone: String? = "Indoor"

    // Self-referential relationship for table combining/splitting
    var joinedParent: RestaurantTable?
    
    @Relationship(deleteRule: .nullify, inverse: \RestaurantTable.joinedParent)
    var joinedChildren: [RestaurantTable] = []
    
    @Relationship(deleteRule: .cascade, inverse: \TableSession.table)
    var sessions: [TableSession] = []
    
    // Offline-First Sync Metadata
    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date

    init(id: UUID = UUID(), tableNumber: String, capacity: Int, tableShape: String = "rectangle", isRound: Bool = false, status: String = "vacant", qrCodeIdentifier: String? = nil, positionX: Double = 0, positionY: Double = 0, layoutScale: Double = 1.0, floor: Int? = 1, floorId: UUID? = nil, branchId: String = "", zone: String? = "Indoor", isSynced: Bool = false, isDeleted: Bool = false, updatedAt: Date = Date()) {
        self.id = id
        self.tableNumber = tableNumber
        self.capacity = capacity
        self.tableShape = tableShape
        self.isRound = tableShape == "circle" || tableShape == "oval"
        self.status = status
        self.qrCodeIdentifier = qrCodeIdentifier
        self.positionX = positionX
        self.positionY = positionY
        self.layoutScale = layoutScale <= 0 ? 1.0 : layoutScale
        self.floor = floor
        self.floorId = floorId
        self.branchId = branchId
        self.zone = zone
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
    }

    /// Clamped floor-plan display scale (defaults to 1 when unset/invalid).
    var resolvedLayoutScale: Double {
        let s = layoutScale
        guard s.isFinite, s > 0 else { return 1.0 }
        return min(2.5, max(0.5, s))
    }

    /// Deleting any member while its joined group is serving guests would
    /// orphan the shared session. Clear/checkout the group before deletion.
    var joinedGroupHasActiveSession: Bool {
        let leader = joinedParent ?? self
        return ([leader] + leader.joinedChildren).contains { member in
            member.sessions.contains { $0.isActive && !$0.isDeleted }
        }
    }

    /// Detach joined-table relationships, then leave a syncable tombstone for
    /// this table only. Call only after `joinedGroupHasActiveSession == false`.
    func prepareForDeletion(at date: Date = Date()) {
        if joinedParent != nil {
            joinedParent = nil
        } else {
            for child in Array(joinedChildren) {
                child.joinedParent = nil
                child.status = "vacant"
                child.isSynced = false
                child.updatedAt = date
            }
        }
        isDeleted = true
        isSynced = false
        updatedAt = date
    }
    
    // MARK: - Computed Properties
    
    /// Get elapsed minutes since table was occupied (today's active session only).
    var elapsedMinutes: Int {
        guard status.lowercased() == "occupied",
              let activeSession = sessions.last(where: {
                  $0.isActive && Calendar.current.isDateInToday($0.startedAt)
              }) else {
            return 0
        }
        let elapsed = Date().timeIntervalSince(activeSession.startedAt)
        return Int(elapsed / 60)
    }
    
}
