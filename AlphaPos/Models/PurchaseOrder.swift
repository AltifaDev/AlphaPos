import Foundation
import SwiftData

@Model
final class PurchaseOrder {
    @Attribute(.unique) var id: UUID
    var poNumber: String
    var supplier: Supplier?
    var branch: Branch?
    var status: String // "draft", "sent", "received", "cancelled"
    var orderDate: Date
    var deliveryDate: Date?
    var notes: String?

    // Source document metadata (Peppol/UBL-inspired procurement record)
    var documentType: String?
    var invoiceNumber: String?
    var taxInvoiceNumber: String?
    var supplierNameRaw: String?
    var supplierTaxId: String?
    var supplierBranchCode: String?
    var customerReference: String?
    var invoiceDate: Date?
    var currencyCode: String = "THB"
    var subtotal: Double?
    var taxAmount: Double?
    var grandTotal: Double?
    var extractionConfidence: Double?
    var validationWarningsJSON: String?
    var sourceDocumentHash: String?
    
    @Relationship(deleteRule: .cascade, inverse: \PurchaseOrderItem.purchaseOrder)
    var items: [PurchaseOrderItem] = []
    
    // Offline-First Sync Metadata
    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date
    var rowVersion: Int = 0
    
    init(
        id: UUID = UUID(),
        poNumber: String,
        supplier: Supplier? = nil,
        branch: Branch? = nil,
        status: String = "draft",
        orderDate: Date = Date(),
        deliveryDate: Date? = nil,
        notes: String? = nil,
        documentType: String? = nil,
        invoiceNumber: String? = nil,
        taxInvoiceNumber: String? = nil,
        supplierNameRaw: String? = nil,
        supplierTaxId: String? = nil,
        supplierBranchCode: String? = nil,
        customerReference: String? = nil,
        invoiceDate: Date? = nil,
        currencyCode: String = "THB",
        subtotal: Double? = nil,
        taxAmount: Double? = nil,
        grandTotal: Double? = nil,
        extractionConfidence: Double? = nil,
        validationWarningsJSON: String? = nil,
        sourceDocumentHash: String? = nil,
        isSynced: Bool = false,
        isDeleted: Bool = false,
        updatedAt: Date = Date(),
        rowVersion: Int = 0
    ) {
        self.id = id
        self.poNumber = poNumber
        self.supplier = supplier
        self.branch = branch
        self.status = status
        self.orderDate = orderDate
        self.deliveryDate = deliveryDate
        self.notes = notes
        self.documentType = documentType
        self.invoiceNumber = invoiceNumber
        self.taxInvoiceNumber = taxInvoiceNumber
        self.supplierNameRaw = supplierNameRaw
        self.supplierTaxId = supplierTaxId
        self.supplierBranchCode = supplierBranchCode
        self.customerReference = customerReference
        self.invoiceDate = invoiceDate
        self.currencyCode = currencyCode
        self.subtotal = subtotal
        self.taxAmount = taxAmount
        self.grandTotal = grandTotal
        self.extractionConfidence = extractionConfidence
        self.validationWarningsJSON = validationWarningsJSON
        self.sourceDocumentHash = sourceDocumentHash
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
        self.rowVersion = rowVersion
    }
}
