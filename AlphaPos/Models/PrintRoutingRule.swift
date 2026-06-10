import Foundation
import SwiftData

@Model
final class PrintRoutingRule {
    @Attribute(.unique) var id: UUID
    var printer: Printer?
    var categoryId: String? // Textual category slug (e.g., "mains", "drinks")
    var printOnOrder: Bool
    var printOnPayment: Bool
    
    // Offline-First Sync Metadata
    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date
    
    init(
        id: UUID = UUID(),
        printer: Printer? = nil,
        categoryId: String? = nil,
        printOnOrder: Bool = true,
        printOnPayment: Bool = false,
        isSynced: Bool = false,
        isDeleted: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.printer = printer
        self.categoryId = categoryId
        self.printOnOrder = printOnOrder
        self.printOnPayment = printOnPayment
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
    }
}
