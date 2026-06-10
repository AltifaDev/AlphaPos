import Foundation
import SwiftData

@Model
final class Role {
    @Attribute(.unique) var id: UUID
    var name: String
    var roleDescription: String?
    
    @Relationship(deleteRule: .nullify, inverse: \User.role)
    var users: [User]?
    
    // Offline-First Sync Metadata
    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date
    
    init(id: UUID = UUID(), name: String, roleDescription: String? = nil, isSynced: Bool = false, isDeleted: Bool = false, updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.roleDescription = roleDescription
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
    }
}
