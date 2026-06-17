import Foundation
import SwiftData

@Model
final class MenuItem {
    @Attribute(.unique) var id: String
    var name: String
    var itemDescription: String?
    var price: Double
    var imageUrl: String?
    var isAvailable: Bool
    var taxRate: Double // e.g., 7.0 for 7% VAT
    var category: Category?
    
    var priceDecimal: Decimal { Decimal(string: String(format: "%.2f", price)) ?? Decimal(price) }
    
    // Offline-First and International Fields
    @Attribute(.externalStorage) var imageData: Data?
    var barcode: String?
    var sku: String?
    var isTaxInclusive: Bool?
    var isFavorite: Bool?
    var isBestseller: Bool?
    var colorHex: String?
    
    // Localization Fields
    var nameTranslationsJson: String? = "{}"
    var descriptionTranslationsJson: String? = "{}"
    
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
        isAvailable: Bool = true,
        taxRate: Double = 7.0,
        category: Category? = nil,
        imageData: Data? = nil,
        barcode: String? = nil,
        sku: String? = nil,
        isTaxInclusive: Bool? = true,
        isFavorite: Bool? = false,
        isBestseller: Bool? = false,
        colorHex: String? = nil,
        nameTranslationsJson: String? = "{}",
        descriptionTranslationsJson: String? = "{}",
        isSynced: Bool = false,
        isDeleted: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.itemDescription = itemDescription
        self.price = price
        self.imageUrl = imageUrl
        self.isAvailable = isAvailable
        self.taxRate = taxRate
        self.category = category
        self.imageData = imageData
        self.barcode = barcode
        self.sku = sku
        self.isTaxInclusive = isTaxInclusive
        self.isFavorite = isFavorite
        self.isBestseller = isBestseller
        self.colorHex = colorHex
        self.nameTranslationsJson = nameTranslationsJson
        self.descriptionTranslationsJson = descriptionTranslationsJson
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
    }
}
