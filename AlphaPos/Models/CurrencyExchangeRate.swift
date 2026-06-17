import Foundation
import SwiftData

@Model
final class CurrencyExchangeRate {
    @Attribute(.unique) var id: UUID
    var baseCurrency: String
    var targetCurrency: String
    var exchangeRate: Double
    var effectiveDate: Date
    var isActive: Bool
    
    // Offline-First Sync Metadata
    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date
    var createdAt: Date
    
    init(id: UUID = UUID(), baseCurrency: String = "THB", targetCurrency: String, exchangeRate: Double, effectiveDate: Date = Date(), isActive: Bool = true, isSynced: Bool = false, isDeleted: Bool = false, updatedAt: Date = Date(), createdAt: Date = Date()) {
        self.id = id
        self.baseCurrency = baseCurrency
        self.targetCurrency = targetCurrency
        self.exchangeRate = exchangeRate
        self.effectiveDate = effectiveDate
        self.isActive = isActive
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
        self.createdAt = createdAt
    }
}
