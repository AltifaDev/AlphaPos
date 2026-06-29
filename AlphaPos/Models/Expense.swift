import Foundation
import SwiftData

@Model
final class Expense {
    @Attribute(.unique) var id: UUID
    var invoiceNo: String?
    var title: String
    var category: String // "Raw Materials", "Equipment", "Consumables", "Maintenance", "Other"
    var quantity: Double
    var unit: String?
    var unitPrice: Double
    var amount: Double
    var vatRate: Double // e.g. 7.0
    var vatAmount: Double
    var paymentMethod: String // "Cash", "Credit Card", "Bank Transfer", "Accounts Payable"
    var status: String // "Paid", "Unpaid"
    var isCapEx: Bool
    var date: Date
    var notes: String?
    
    @Relationship(deleteRule: .nullify)
    var supplier: Supplier?
    var branch: Branch?
    
    // Offline-First Sync Metadata
    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date
    
    init(
        id: UUID = UUID(),
        invoiceNo: String? = nil,
        title: String,
        category: String,
        quantity: Double = 1.0,
        unit: String? = nil,
        unitPrice: Double = 0.0,
        amount: Double = 0.0,
        vatRate: Double = 0.0,
        vatAmount: Double = 0.0,
        paymentMethod: String = "Cash",
        status: String = "Paid",
        isCapEx: Bool = false,
        date: Date = Date(),
        notes: String? = nil,
        supplier: Supplier? = nil,
        branch: Branch? = nil,
        isSynced: Bool = false,
        isDeleted: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.invoiceNo = invoiceNo
        self.title = title
        self.category = category
        self.quantity = quantity
        self.unit = unit
        self.unitPrice = unitPrice
        self.amount = amount == 0.0 ? (quantity * unitPrice) : amount
        self.vatRate = vatRate
        self.vatAmount = vatAmount
        self.paymentMethod = paymentMethod
        self.status = status
        self.isCapEx = isCapEx
        self.date = date
        self.notes = notes
        self.supplier = supplier
        self.branch = branch
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
    }
}
