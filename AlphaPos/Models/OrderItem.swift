import Foundation
import SwiftData

enum OrderItemLineType: String, CaseIterable, Codable {
    case main
    case addOn = "addon"
    case bundleComponent = "bundle_component"
    case promotionReward = "promotion_reward"
}

@Model
final class OrderItem {
    @Attribute(.unique) var id: UUID
    var order: Order?
    var menuItem: MenuItem?
    var itemName: String  // Fallback name from Supabase when menuItem relationship is nil
    var quantity: Int
    var unitPrice: Double
    var subtotal: Double
    /// Immutable sale-time classification used by restaurant KPIs. Never infer
    /// this from the current menu category or price after the sale.
    var lineType: String = OrderItemLineType.main.rawValue
    /// 0 = legacy row requiring one-time catalog fallback, 1 = explicit snapshot.
    var lineTypeVersion: Int = 0
    var notes: String?
    var status: String // "cooking", "served", "cancelled" -> starts as cooking for kitchen
    var servedBy: String? // who served this item (e.g. staff member name)
    var kitchenPrintedAt: Date?
    var barPrintedAt: Date?
    var labelPrintedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \OrderItemModifier.orderItem)
    var modifiers: [OrderItemModifier] = []

    // Offline-First Sync Metadata
    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date
    var rowVersion: Int = 0

    init(id: UUID = UUID(), order: Order? = nil, menuItem: MenuItem? = nil, itemName: String = "", quantity: Int = 1, unitPrice: Double = 0.0, lineType: OrderItemLineType = .main, notes: String? = nil, status: String = "cooking", servedBy: String? = nil, kitchenPrintedAt: Date? = nil, barPrintedAt: Date? = nil, labelPrintedAt: Date? = nil, isSynced: Bool = false, isDeleted: Bool = false, updatedAt: Date = Date(), rowVersion: Int = 0) {
        self.id = id
        self.order = order
        self.menuItem = menuItem
        self.itemName = itemName.isEmpty ? (menuItem?.name ?? "") : itemName
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.subtotal = Double(quantity) * unitPrice
        self.lineType = lineType.rawValue
        self.lineTypeVersion = 1
        self.notes = notes
        self.status = status
        self.servedBy = servedBy
        self.kitchenPrintedAt = kitchenPrintedAt
        self.barPrintedAt = barPrintedAt
        self.labelPrintedAt = labelPrintedAt
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
        self.rowVersion = rowVersion
    }

    var resolvedLineType: OrderItemLineType {
        if let type = OrderItemLineType(rawValue: lineType) {
            // Lightweight migration gives legacy generated rows `main`; retain
            // deterministic compatibility for rows created before lineType.
            if type != .main { return type }
        }
        if notes?.hasPrefix("🎁 Promo reward:") == true { return .promotionReward }
        if notes?.hasPrefix("📦 Bundle component:") == true { return .bundleComponent }
        if lineTypeVersion == 0, menuItem?.resolvedSalesRole == .addOn { return .addOn }
        return .main
    }
}
