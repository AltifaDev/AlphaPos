import Foundation
import SwiftData

enum MenuItemSalesRole: String, CaseIterable, Codable, Identifiable {
    case main
    case addOn = "addon"

    var id: String { rawValue }

    static func inferred(from categoryName: String?) -> MenuItemSalesRole {
        let normalized = categoryName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        let addOnNames = ["เพิ่มเติม", "เพิ่ม", "addon", "add-on", "add on", "extras", "extra", "toppings", "topping"]
        return addOnNames.contains(normalized) ? .addOn : .main
    }
}

@Model
final class MenuItem {
    @Attribute(.unique) var id: String
    var name: String
    var itemDescription: String?
    var price: Double
    var imageUrl: String?
    var imageUrl2: String?
    var imageUrl3: String?
    var videoUrl: String?
    var isAvailable: Bool
    var taxRate: Double // e.g., 7.0 for 7% VAT
    var category: Category?
    
    var priceDecimal: Decimal { Decimal(string: String(format: "%.2f", price)) ?? Decimal(price) }
    
    // Offline-First and International Fields
    @Attribute(.externalStorage) var imageData: Data?
    @Attribute(.externalStorage) var imageData2: Data?
    @Attribute(.externalStorage) var imageData3: Data?
    @Attribute(.externalStorage) var videoData: Data?
    var barcode: String?
    var sku: String?
    var isTaxInclusive: Bool?
    var isFavorite: Bool?
    var isBestseller: Bool?
    var colorHex: String?
    
    // Localization Fields
    var nameTranslationsJson: String? = "{}"
    var descriptionTranslationsJson: String? = "{}"

    /// Explicit stock tracking mode for this sellable item.
    /// Values: `not_tracked` | `finished_good` | `recipe_based`
    /// Falls back to recipe heuristic when nil (legacy rows).
    var stockTrackingMode: String?

    /// Default restaurant-sales role copied to each OrderItem at checkout.
    /// `isSalesRoleConfirmed` distinguishes user-reviewed values from legacy
    /// values inferred from the category during migration.
    var salesRole: String = MenuItemSalesRole.main.rawValue
    var isSalesRoleConfirmed: Bool = false
    
    var nameTranslations: [String: String] {
        get {
            guard let jsonStr = nameTranslationsJson,
                  let data = jsonStr.data(using: .utf8),
                  let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
                return [:]
            }
            return dict
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let jsonStr = String(data: data, encoding: .utf8) {
                nameTranslationsJson = jsonStr
            } else {
                nameTranslationsJson = "{}"
            }
        }
    }
    
    var descriptionTranslations: [String: String] {
        get {
            guard let jsonStr = descriptionTranslationsJson,
                  let data = jsonStr.data(using: .utf8),
                  let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
                return [:]
            }
            return dict
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let jsonStr = String(data: data, encoding: .utf8) {
                descriptionTranslationsJson = jsonStr
            } else {
                descriptionTranslationsJson = "{}"
            }
        }
    }
    
    var localizedName: String {
        let langCode = LocalizationManager.shared.languageCode
        if let translated = nameTranslations[langCode], !translated.isEmpty {
            return translated
        }
        return name
    }
    
    var localizedDescription: String? {
        let langCode = LocalizationManager.shared.languageCode
        if let translated = descriptionTranslations[langCode], !translated.isEmpty {
            return translated
        }
        return itemDescription
    }
    
    @Relationship(deleteRule: .cascade, inverse: \Recipe.menuItem)
    var recipes: [Recipe] = []
    
    @Relationship(deleteRule: .cascade, inverse: \MenuItemModifierGroup.menuItem)
    var modifierGroupsRelations: [MenuItemModifierGroup] = []
    
    @Relationship(deleteRule: .cascade, inverse: \DeliveryPrice.menuItem)
    var deliveryPrices: [DeliveryPrice] = []

    
    // Offline-First Sync Metadata
    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date
    
    init(
        id: String = UUID().uuidString.lowercased(),
        name: String,
        itemDescription: String? = nil,
        price: Double,
        imageUrl: String? = nil,
        imageUrl2: String? = nil,
        imageUrl3: String? = nil,
        videoUrl: String? = nil,
        isAvailable: Bool = true,
        taxRate: Double = 7.0,
        category: Category? = nil,
        imageData: Data? = nil,
        imageData2: Data? = nil,
        imageData3: Data? = nil,
        videoData: Data? = nil,
        barcode: String? = nil,
        sku: String? = nil,
        isTaxInclusive: Bool? = true,
        isFavorite: Bool? = false,
        isBestseller: Bool? = false,
        colorHex: String? = nil,
        nameTranslationsJson: String? = "{}",
        descriptionTranslationsJson: String? = "{}",
        stockTrackingMode: String? = nil,
        salesRole: String = MenuItemSalesRole.main.rawValue,
        isSalesRoleConfirmed: Bool = false,
        isSynced: Bool = false,
        isDeleted: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.itemDescription = itemDescription
        self.price = price
        self.imageUrl = imageUrl
        self.imageUrl2 = imageUrl2
        self.imageUrl3 = imageUrl3
        self.videoUrl = videoUrl
        self.isAvailable = isAvailable
        self.taxRate = taxRate
        self.category = category
        self.imageData = imageData
        self.imageData2 = imageData2
        self.imageData3 = imageData3
        self.videoData = videoData
        self.barcode = barcode
        self.sku = sku
        self.isTaxInclusive = isTaxInclusive
        self.isFavorite = isFavorite
        self.isBestseller = isBestseller
        self.colorHex = colorHex
        self.nameTranslationsJson = nameTranslationsJson
        self.descriptionTranslationsJson = descriptionTranslationsJson
        self.stockTrackingMode = stockTrackingMode
        self.salesRole = MenuItemSalesRole(rawValue: salesRole)?.rawValue ?? MenuItemSalesRole.main.rawValue
        self.isSalesRoleConfirmed = isSalesRoleConfirmed
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
    }

    var resolvedSalesRole: MenuItemSalesRole {
        if isSalesRoleConfirmed {
            return MenuItemSalesRole(rawValue: salesRole) ?? .main
        }
        return MenuItemSalesRole.inferred(from: category?.name)
    }

    var orderItemLineType: OrderItemLineType {
        resolvedSalesRole == .addOn ? .addOn : .main
    }
}

// MARK: - Stock Tracking

enum StockTrackingMode: String, CaseIterable, Identifiable {
    case notTracked = "not_tracked"
    case finishedGood = "finished_good"
    case recipeBased = "recipe_based"

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .notTracked: return "stock_mode_not_tracked"
        case .finishedGood: return "stock_mode_finished_good"
        case .recipeBased: return "stock_mode_recipe_based"
        }
    }

    var catalogLocalizationKey: String {
        switch self {
        case .notTracked: return "catalog_not_tracked"
        case .finishedGood: return "catalog_finished_good"
        case .recipeBased: return "catalog_recipe_based"
        }
    }

    var helpLocalizationKey: String {
        switch self {
        case .notTracked: return "stock_mode_not_tracked_help"
        case .finishedGood: return "stock_mode_finished_good_help"
        case .recipeBased: return "stock_mode_recipe_based_help"
        }
    }
}

extension MenuItem {
    /// Prefer stored `stockTrackingMode`; otherwise infer from recipe rows.
    var resolvedTrackingMode: StockTrackingMode {
        if let raw = stockTrackingMode, let mode = StockTrackingMode(rawValue: raw) {
            return mode
        }
        let activeRecipes = recipes.filter { !$0.isDeleted }
        if activeRecipes.isEmpty { return .notTracked }
        if activeRecipes.count == 1, let only = activeRecipes.first, only.quantityRequired == 1.0 {
            return .finishedGood
        }
        return .recipeBased
    }

    var tracksStockOnSale: Bool {
        resolvedTrackingMode != .notTracked && !recipes.filter({ !$0.isDeleted }).isEmpty
    }
}

extension InventoryItem {
    /// Finished-good SKUs created for 1:1 menu sell-through (or tagged as such).
    var isFinishedGoodSKU: Bool {
        if category == "Finished Goods" { return true }
        if let sku, sku.hasPrefix("FG-") { return true }
        return false
    }
}
