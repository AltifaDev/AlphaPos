import Foundation
import SwiftData

@Model
final class User {
    @Attribute(.unique) var id: UUID
    var username: String
    var email: String?
    var passwordHash: String
    var pinCodeHash: String?
    var role: Role?
    var isActive: Bool
    
    @Relationship(deleteRule: .cascade, inverse: \Employee.user)
    var employeeProfile: Employee?
    
    // Offline-First Sync Metadata
    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date
    
    init(id: UUID = UUID(), username: String, email: String? = nil, passwordHash: String, pinCodeHash: String? = nil, role: Role? = nil, isActive: Bool = true, isSynced: Bool = false, isDeleted: Bool = false, updatedAt: Date = Date()) {
        self.id = id
        self.username = username
        self.email = email
        self.passwordHash = passwordHash
        self.pinCodeHash = pinCodeHash
        self.role = role
        self.isActive = isActive
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
    }
}
