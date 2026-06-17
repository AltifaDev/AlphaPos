import Foundation
import SwiftData

@Model
final class OrderTaxLine {
    @Attribute(.unique) var id: UUID
    var order: Order?
    var taxName: String // e.g., "VAT 7%", "Service Tax"
    var taxRate: Double
    var taxableAmount: Double
    var taxAmount: Double
    var isInclusive: Bool
    var jurisdiction: String?
    
    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date
    
    init(id: UUID = UUID(), order: Order? = nil, taxName: String = "VAT", taxRate: Double = 7.0, taxableAmount: Double = 0.0, taxAmount: Double = 0.0, isInclusive: Bool = true, jurisdiction: String? = nil, isSynced: Bool = false, isDeleted: Bool = false, updatedAt: Date = Date()) {
        self.id = id
        self.order = order
        self.taxName = taxName
        self.taxRate = taxRate
        self.taxableAmount = taxableAmount
        self.taxAmount = taxAmount
        self.isInclusive = isInclusive
        self.jurisdiction = jurisdiction
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
    }
}

extension OrderTaxLine: RemoteOrderTaxLineUploadable {}
