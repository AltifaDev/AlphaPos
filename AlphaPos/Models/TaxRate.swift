import Foundation
import SwiftData

@Model
final class TaxRate {
    @Attribute(.unique) var id: UUID
    var name: String
    var ratePercentage: Double
    var taxType: String // "exclusive", "inclusive"
    var isDefault: Bool
    var isActive: Bool
    
    // Offline-First Sync Metadata
    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date
    var createdAt: Date
    
    init(id: UUID = UUID(), name: String, ratePercentage: Double, taxType: String = "exclusive", isDefault: Bool = false, isActive: Bool = true, isSynced: Bool = false, isDeleted: Bool = false, updatedAt: Date = Date(), createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.ratePercentage = ratePercentage
        self.taxType = taxType
        self.isDefault = isDefault
        self.isActive = isActive
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
        self.createdAt = createdAt
    }
}
