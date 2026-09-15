import Foundation
import SwiftData

@Model
final class PurchaseOrderItem {
    @Attribute(.unique) var id: UUID
    var purchaseOrder: PurchaseOrder?
    var inventoryItem: InventoryItem?
    var quantityOrdered: Double
    var quantityReceived: Double
    var unitCost: Double

    // Original invoice line data is preserved even when no InventoryItem matches.
    var lineNumber: String?
    var sourceItemName: String?
    var sellerItemId: String?
    var barcode: String?
    var sourceUnit: String?
    var unitCode: String?
    var priceBaseQuantity: Double = 1.0
    var lineNetAmount: Double?
    var vatRate: Double?
    var vatCode: String?
    var taxAmount: Double?
    var lineTotal: Double?
    var lineConfidence: Double?

    // Lot / Expiry tracking for FEFO
    var expiryDate: Date?
    var lotNumber: String?
    
    // Offline-First Sync Metadata
    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date
    var rowVersion: Int = 0
    
    init(
        id: UUID = UUID(),
        purchaseOrder: PurchaseOrder? = nil,
        inventoryItem: InventoryItem? = nil,
        quantityOrdered: Double = 0.0,
        quantityReceived: Double = 0.0,
        unitCost: Double = 0.0,
        lineNumber: String? = nil,
        sourceItemName: String? = nil,
        sellerItemId: String? = nil,
        barcode: String? = nil,
        sourceUnit: String? = nil,
        unitCode: String? = nil,
        priceBaseQuantity: Double = 1.0,
        lineNetAmount: Double? = nil,
        vatRate: Double? = nil,
        vatCode: String? = nil,
        taxAmount: Double? = nil,
        lineTotal: Double? = nil,
        lineConfidence: Double? = nil,
        expiryDate: Date? = nil,
        lotNumber: String? = nil,
        isSynced: Bool = false,
        isDeleted: Bool = false,
        updatedAt: Date = Date(),
        rowVersion: Int = 0
    ) {
        self.id = id
        self.purchaseOrder = purchaseOrder
        self.inventoryItem = inventoryItem
        self.quantityOrdered = quantityOrdered
        self.quantityReceived = quantityReceived
        self.unitCost = unitCost
        self.lineNumber = lineNumber
        self.sourceItemName = sourceItemName
        self.sellerItemId = sellerItemId
        self.barcode = barcode
        self.sourceUnit = sourceUnit
        self.unitCode = unitCode
        self.priceBaseQuantity = priceBaseQuantity
        self.lineNetAmount = lineNetAmount
        self.vatRate = vatRate
        self.vatCode = vatCode
        self.taxAmount = taxAmount
        self.lineTotal = lineTotal
        self.lineConfidence = lineConfidence
        self.expiryDate = expiryDate
        self.lotNumber = lotNumber
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
        self.rowVersion = rowVersion
    }
}
