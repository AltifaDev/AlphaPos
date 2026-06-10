import Foundation
import SwiftData

@Model
final class MenuItemModifierGroup {
    @Attribute(.unique) var id: UUID
    var menuItem: MenuItem?
    var modifierGroup: ModifierGroup?
    
    // Offline-First Sync Metadata
    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date
    
    init(id: UUID = UUID(), menuItem: MenuItem? = nil, modifierGroup: ModifierGroup? = nil, isSynced: Bool = false, isDeleted: Bool = false, updatedAt: Date = Date()) {
        self.id = id
        self.menuItem = menuItem
        self.modifierGroup = modifierGroup
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
    }
}
