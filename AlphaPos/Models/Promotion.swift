import Foundation
import SwiftData

@Model
final class Promotion {
    @Attribute(.unique) var id: UUID
    var title: String
    var promoDescription: String?
    var imageData: String? // Base64 representation of selected promotion image/banner
    var isActive: Bool
    
    // Offline-First Sync Metadata
    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date
    
    init(id: UUID = UUID(), title: String, promoDescription: String? = nil, imageData: String? = nil, isActive: Bool = true, isSynced: Bool = false, isDeleted: Bool = false, updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.promoDescription = promoDescription
        self.imageData = imageData
        self.isActive = isActive
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
    }
}
