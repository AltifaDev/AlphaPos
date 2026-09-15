import Foundation
import SwiftData

enum OutOfStockPolicy: String, CaseIterable, Identifiable {
    case block = "block"
    case allowNegative = "allow_negative"

    var id: String { rawValue }
}

@Model
final class InventoryItem {
    @Attribute(.unique) var id: UUID
    var name: String
    var sku: String?
    var unit: String // "kg", "g", "liter", "ml", "piece", "can"
    var currentQuantity: Double
    var reorderLevel: Double
    var costPrice: Double
    /// Controls whether POS blocks a sale or records a negative balance when stock is insufficient.
    /// Stored as a raw value so SwiftData can lightweight-migrate existing stores safely.
    /// Defaults to allowNegative to enable uninterrupted front-of-house sales (backflush model).
    var outOfStockPolicyRaw: String = OutOfStockPolicy.allowNegative.rawValue

    var outOfStockPolicy: OutOfStockPolicy {
        get { OutOfStockPolicy(rawValue: outOfStockPolicyRaw) ?? .allowNegative }
        set { outOfStockPolicyRaw = newValue.rawValue }
    }

    // ── Safety Stock & Lead Time (ISO 9001 / GS1 Best Practice) ──────────
    /// Buffer stock to absorb demand spikes or late deliveries.
    /// Formula hint: safetyStockLevel = Z × σ_demand × √leadTimeDays
    var safetyStockLevel: Double
    /// Maximum stock to hold — prevents over-ordering & spoilage.
    var maxStockLevel: Double
    /// Average supplier lead time in days (used in Reorder Point calculation).
    /// Reorder Point = safetyStockLevel + (avgDailyUsage × leadTimeDays)
    var leadTimeDays: Int
    // ─────────────────────────────────────────────────────────────────────

    var supplier: Supplier?
    
    // Expiry Date Configuration (per-item override)
    /// Days before expiry to show a Warning badge (default 7, per GHP/HACCP guidance)
    var expiryWarningDays: Int
    /// Days before expiry to show a Critical badge (default 3)
    var expiryCriticalDays: Int

    var branch: Branch?
    
    // High-Volume inventory optimizations
    var category: String?
    var storageLocation: String?
    var barcode: String?
    
    @Relationship(deleteRule: .cascade, inverse: \InventoryTransaction.item)
    var transactions: [InventoryTransaction] = []
    
    @Relationship(deleteRule: .cascade, inverse: \Recipe.inventoryItem)
    var recipeUsages: [Recipe] = []
    
    // Offline-First Sync Metadata
    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date
    
    init(
        id: UUID = UUID(),
        name: String,
        sku: String? = nil,
        unit: String,
        currentQuantity: Double = 0.0,
        reorderLevel: Double = 0.0,
        costPrice: Double = 0.0,
        outOfStockPolicy: OutOfStockPolicy = .allowNegative,
        supplier: Supplier? = nil,
        branch: Branch? = nil,
        safetyStockLevel: Double = 0.0,
        maxStockLevel: Double = 0.0,
        leadTimeDays: Int = 1,
        expiryWarningDays: Int = 7,
        expiryCriticalDays: Int = 3,
        category: String? = nil,
        storageLocation: String? = nil,
        barcode: String? = nil,
        isSynced: Bool = false,
        isDeleted: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.sku = sku
        self.unit = unit
        self.currentQuantity = currentQuantity
        self.reorderLevel = reorderLevel
        self.costPrice = costPrice
        self.outOfStockPolicyRaw = outOfStockPolicy.rawValue
        self.supplier = supplier
        self.branch = branch
        self.safetyStockLevel = safetyStockLevel
        self.maxStockLevel = maxStockLevel
        self.leadTimeDays = leadTimeDays
        self.expiryWarningDays = expiryWarningDays
        self.expiryCriticalDays = expiryCriticalDays
        self.category = category
        self.storageLocation = storageLocation
        self.barcode = barcode
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
    }
}
