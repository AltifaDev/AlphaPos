import Foundation
import SwiftData

@Model
final class Supplier {
    @Attribute(.unique) var id: UUID
    var name: String
    var contactName: String?
    var phone: String?
    var email: String?
    var address: String?
    /// Tax ID / VAT registration (aligns with PO.supplierTaxId from invoices).
    var taxId: String?
    /// e.g. "Net 30", "COD", "7 days"
    var paymentTerms: String?
    /// Default lead time used when creating POs / safety stock.
    var defaultLeadTimeDays: Int

    @Relationship(deleteRule: .nullify, inverse: \InventoryItem.supplier)
    var inventoryItems: [InventoryItem] = []

    // Offline-First Sync Metadata
    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        contactName: String? = nil,
        phone: String? = nil,
        email: String? = nil,
        address: String? = nil,
        taxId: String? = nil,
        paymentTerms: String? = nil,
        defaultLeadTimeDays: Int = 7,
        isSynced: Bool = false,
        isDeleted: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.contactName = contactName
        self.phone = phone
        self.email = email
        self.address = address
        self.taxId = taxId
        self.paymentTerms = paymentTerms
        self.defaultLeadTimeDays = defaultLeadTimeDays
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
    }
}
