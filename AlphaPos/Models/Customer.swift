import Foundation
import SwiftData

@Model
final class Customer {
    @Attribute(.unique) var id: UUID
    var name: String
    var email: String?
    var phone: String?
    var taxId: String?
    var address: String?
    var loyaltyPoints: Int
    var membershipTier: String // "standard", "silver", "gold", "platinum"
    var totalSpend: Double
    var visitCount: Int
    var notes: String?
    var dateOfBirth: Date?
    var allergies: String?
    var preferences: String?
    var isTaxExempt: Bool
    
    // Offline-First Sync Metadata
    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date
    var createdAt: Date
    
    init(id: UUID = UUID(), name: String, email: String? = nil, phone: String? = nil, taxId: String? = nil, address: String? = nil, loyaltyPoints: Int = 0, membershipTier: String = "standard", totalSpend: Double = 0.0, visitCount: Int = 0, notes: String? = nil, dateOfBirth: Date? = nil, allergies: String? = nil, preferences: String? = nil, isTaxExempt: Bool = false, isSynced: Bool = false, isDeleted: Bool = false, updatedAt: Date = Date(), createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.email = email
        self.phone = phone
        self.taxId = taxId
        self.address = address
        self.loyaltyPoints = loyaltyPoints
        self.membershipTier = membershipTier
        self.totalSpend = totalSpend
        self.visitCount = visitCount
        self.notes = notes
        self.dateOfBirth = dateOfBirth
        self.allergies = allergies
        self.preferences = preferences
        self.isTaxExempt = isTaxExempt
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
        self.createdAt = createdAt
    }
}

extension Customer: RemoteCustomerUploadable {}
