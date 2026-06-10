import Foundation
import SwiftData

@Model
final class ModifierGroup {
    @Attribute(.unique) var id: UUID
    var name: String
    var minSelection: Int
    var maxSelection: Int
    
    @Relationship(deleteRule: .cascade, inverse: \MenuItemModifierGroup.modifierGroup)
    var menuItemRelations: [MenuItemModifierGroup] = []
    
    @Relationship(deleteRule: .cascade, inverse: \Modifier.modifierGroup)
    var modifiers: [Modifier] = []
    
    // Offline-First Sync Metadata
    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date
    
    init(id: UUID = UUID(), name: String, minSelection: Int = 0, maxSelection: Int = 1, isSynced: Bool = false, isDeleted: Bool = false, updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.minSelection = minSelection
        self.maxSelection = maxSelection
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
    }
}
