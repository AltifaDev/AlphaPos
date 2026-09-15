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
    var isVATRecoverable: Bool = true
    var paymentMethod: String // "Cash", "Credit Card", "Bank Transfer", "Accounts Payable"
    var status: String // "Paid", "Unpaid"
    var isCapEx: Bool
    /// Accounting treatment. Legacy rows derive from isCapEx when empty.
    var recognitionType: String = "operating_expense"
    var expenseNature: String = "other"
    var isRecurring: Bool = false
    var recurrenceFrequency: String = "none"
    var serviceStartDate: Date?
    var serviceEndDate: Date?
    // Fixed-asset / investment fields (IAS 16 management schedule)
    var assetClass: String?
    var availableForUseDate: Date?
    var usefulLifeMonths: Int = 0
    var residualValue: Double = 0
    var investmentProject: String?
    var expectedMonthlyCashBenefit: Double = 0
    var expectedMonthlyIncrementalCost: Double = 0
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
        isVATRecoverable: Bool = true,
        paymentMethod: String = "Cash",
        status: String = "Paid",
        isCapEx: Bool = false,
        recognitionType: String? = nil,
        expenseNature: String = "other",
        isRecurring: Bool = false,
        recurrenceFrequency: String = "none",
        serviceStartDate: Date? = nil,
        serviceEndDate: Date? = nil,
        assetClass: String? = nil,
        availableForUseDate: Date? = nil,
        usefulLifeMonths: Int = 0,
        residualValue: Double = 0,
        investmentProject: String? = nil,
        expectedMonthlyCashBenefit: Double = 0,
        expectedMonthlyIncrementalCost: Double = 0,
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
        self.isVATRecoverable = isVATRecoverable
        self.paymentMethod = paymentMethod
        self.status = status
        self.isCapEx = isCapEx
        self.recognitionType = recognitionType ?? (isCapEx ? "fixed_asset" : "operating_expense")
        self.expenseNature = expenseNature
        self.isRecurring = isRecurring
        self.recurrenceFrequency = recurrenceFrequency
        self.serviceStartDate = serviceStartDate
        self.serviceEndDate = serviceEndDate
        self.assetClass = assetClass
        self.availableForUseDate = availableForUseDate
        self.usefulLifeMonths = usefulLifeMonths
        self.residualValue = residualValue
        self.investmentProject = investmentProject
        self.expectedMonthlyCashBenefit = expectedMonthlyCashBenefit
        self.expectedMonthlyIncrementalCost = expectedMonthlyIncrementalCost
        self.date = date
        self.notes = notes
        self.supplier = supplier
        self.branch = branch
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
    }
}
