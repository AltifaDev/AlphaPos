import Foundation
import SwiftData

@Model
final class ShiftReport {
    @Attribute(.unique) var id: UUID
    var registerSession: RegisterSession?
    var reportType: String // "Z", "X"
    var grossSales: Double
    var netSales: Double
    var totalTax: Double
    var totalDiscounts: Double
    var totalRefunds: Double
    var cashExpected: Double
    var cashActual: Double
    var overShort: Double
    var generatedByEmployee: Employee?
    
    // Offline-First Sync Metadata
    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date
    var createdAt: Date
    
    init(id: UUID = UUID(), registerSession: RegisterSession? = nil, reportType: String = "Z", grossSales: Double = 0.0, netSales: Double = 0.0, totalTax: Double = 0.0, totalDiscounts: Double = 0.0, totalRefunds: Double = 0.0, cashExpected: Double = 0.0, cashActual: Double = 0.0, overShort: Double = 0.0, generatedByEmployee: Employee? = nil, isSynced: Bool = false, isDeleted: Bool = false, updatedAt: Date = Date(), createdAt: Date = Date()) {
        self.id = id
        self.registerSession = registerSession
        self.reportType = reportType
        self.grossSales = grossSales
        self.netSales = netSales
        self.totalTax = totalTax
        self.totalDiscounts = totalDiscounts
        self.totalRefunds = totalRefunds
        self.cashExpected = cashExpected
        self.cashActual = cashActual
        self.overShort = overShort
        self.generatedByEmployee = generatedByEmployee
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
        self.createdAt = createdAt
    }
}
