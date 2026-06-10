import Foundation
import SwiftData

@Model
final class Category {
    @Attribute(.unique) var id: UUID
    var name: String
    var categoryDescription: String?
    var imageUrl: String?
    
    @Relationship(deleteRule: .nullify, inverse: \MenuItem.category)
    var menuItems: [MenuItem] = []
    
    // Offline-First Sync Metadata
    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date
    
    init(id: UUID = UUID(), name: String, categoryDescription: String? = nil, imageUrl: String? = nil, isSynced: Bool = false, isDeleted: Bool = false, updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.categoryDescription = categoryDescription
        self.imageUrl = imageUrl
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
    }
}
