// InventoryCategoryManager.swift
// AlphaPos — Category Seeding, Auto-Assignment, and ABC Classification
//
// Provides:
// 1. Default restaurant inventory categories with icons + storage locations
// 2. Auto-assignment rules based on SKU patterns and name keywords
// 3. ABC Classification (Pareto analysis) by inventory value

import Foundation
import SwiftData

// MARK: - Category Definition

struct InventoryCategory: Identifiable, Hashable {
    let id: String  // Same as name
    let name: String
    let icon: String  // Emoji
    let defaultStorageLocation: String
    let skuPrefixes: [String]  // SKU prefixes that match this category
    let nameKeywords: [String]  // Name keywords for fallback matching

    init(id: String? = nil, name: String, icon: String, defaultStorageLocation: String, skuPrefixes: [String] = [], nameKeywords: [String] = []) {
        self.id = id ?? name
        self.name = name
        self.icon = icon
        self.defaultStorageLocation = defaultStorageLocation
        self.skuPrefixes = skuPrefixes
        self.nameKeywords = nameKeywords
    }

    static func == (lhs: InventoryCategory, rhs: InventoryCategory) -> Bool {
        lhs.id == rhs.id
    }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    // Compatibility support for views
    static var predefined: [InventoryCategory] {
        InventoryCategoryManager.allCategories
    }
    
    static func icon(for categoryName: String) -> String {
        InventoryCategoryManager.getCategoryIcon(for: categoryName)
    }
    
    static func storageLocation(for categoryName: String) -> String {
        InventoryCategoryManager.getCategoryStorageLocation(for: categoryName)
    }
}

// MARK: - Manager

@Observable
@MainActor
final class InventoryCategoryManager {
    var modelContext: ModelContext?

    // MARK: - All Predefined Categories

    static let allCategories: [InventoryCategory] = [
        InventoryCategory(
            id: "เนื้อสัตว์",
            name: "เนื้อสัตว์",
            icon: "🥩",
            defaultStorageLocation: "ห้องเย็น",
            skuPrefixes: ["ING-BEEF", "ING-PORK", "ING-CHICKEN", "ING-DUCK", "ING-LAMB", "ING-MEAT"],
            nameKeywords: ["beef", "pork", "chicken", "duck", "lamb", "meat", "เนื้อ", "หมู", "ไก่", "เป็ด", "แกะ"]
        ),
        InventoryCategory(
            id: "อาหารทะเล",
            name: "อาหารทะเล",
            icon: "🦐",
            defaultStorageLocation: "ห้องเย็น",
            skuPrefixes: ["ING-PRAWN", "ING-SHRIMP", "ING-FISH", "ING-SQUID", "ING-CRAB", "ING-MUSSEL", "ING-CLAM", "ING-SEAFOOD"],
            nameKeywords: ["prawn", "shrimp", "fish", "squid", "crab", "mussel", "clam", "oyster", "กุ้ง", "ปลา", "หมึก", "ปู", "หอย"]
        ),
        InventoryCategory(
            id: "ผักและผลไม้",
            name: "ผักและผลไม้",
            icon: "🥬",
            defaultStorageLocation: "ห้องเย็น",
            skuPrefixes: ["ING-VEG", "ING-FRUIT", "ING-HERB", "ING-MANGO", "ING-LIME", "ING-TOMATO", "ING-ONION", "ING-GARLIC", "ING-LETTUCE"],
            nameKeywords: ["mango", "lime", "tomato", "onion", "garlic", "lettuce", "pepper", "chili", "cucumber", "carrot", "cabbage", "spinach", "basil", "mint", "lemongrass", "galangal", "ginger", "มะม่วง", "มะนาว", "มะเขือ", "หัวหอม", "กระเทียม", "ผัก", "พริก", "แตง", "แครอท", "กะหล่ำ", "โหระพา", "สะระแหน่", "ตะไคร้", "ข่า", "ขิง"]
        ),
        InventoryCategory(
            id: "นมและผลิตภัณฑ์นม",
            name: "นมและผลิตภัณฑ์นม",
            icon: "🥛",
            defaultStorageLocation: "ห้องเย็น",
            skuPrefixes: ["ING-MILK", "ING-CREAM", "ING-BUTTER", "ING-CHEESE", "ING-YOGURT", "ING-DAIRY"],
            nameKeywords: ["milk", "cream", "butter", "cheese", "yogurt", "นม", "ครีม", "เนย", "ชีส", "โยเกิร์ต"]
        ),
        InventoryCategory(
            id: "แป้งและธัญพืช",
            name: "แป้งและธัญพืช",
            icon: "🍚",
            defaultStorageLocation: "ห้องเก็บแห้ง",
            skuPrefixes: ["ING-RICE", "ING-FLOUR", "ING-SWEETRICE", "ING-NOODLE", "ING-PASTA", "ING-BREAD", "ING-GRAIN"],
            nameKeywords: ["rice", "flour", "noodle", "pasta", "bread", "glutinous", "tapioca", "wheat", "oat", "ข้าว", "แป้ง", "เส้น", "พาสต้า", "ขนมปัง", "ข้าวเหนียว"]
        ),
        InventoryCategory(
            id: "เครื่องปรุงรส",
            name: "เครื่องปรุงรส",
            icon: "🧂",
            defaultStorageLocation: "ชั้นวางเครื่องปรุง",
            skuPrefixes: ["ING-SAUCE", "ING-SOY", "ING-FISH-SAUCE", "ING-OYSTER", "ING-VINEGAR", "ING-SALT", "ING-SUGAR", "ING-SEASONING"],
            nameKeywords: ["sauce", "soy", "fish sauce", "oyster sauce", "vinegar", "salt", "sugar", "msg", "seasoning", "ซอส", "ซีอิ๊ว", "น้ำปลา", "น้ำมันหอย", "น้ำส้ม", "เกลือ", "น้ำตาล"]
        ),
        InventoryCategory(
            id: "น้ำมันและไขมัน",
            name: "น้ำมันและไขมัน",
            icon: "🫒",
            defaultStorageLocation: "ชั้นวางเครื่องปรุง",
            skuPrefixes: ["ING-OIL", "ING-LARD", "ING-COCONUT"],
            nameKeywords: ["oil", "lard", "shortening", "coconut oil", "sesame oil", "olive", "น้ำมัน", "มัน"]
        ),
        InventoryCategory(
            id: "เครื่องเทศและสมุนไพร",
            name: "เครื้องเทศและสมุนไพร",
            icon: "🌿",
            defaultStorageLocation: "ชั้นวางเครื่องปรุง",
            skuPrefixes: ["ING-SPICE", "ING-CURRY", "ING-CUMIN", "ING-TURMERIC", "ING-CINNAMON", "ING-PEPPER"],
            nameKeywords: ["curry", "cumin", "turmeric", "cinnamon", "pepper", "paprika", "chili flake", "star anise", "coriander", "พริกไทย", "ขมิ้น", "อบเชย", "ผงกะหรี่", "ยี่หร่า", "โป๊ยกั๊ก"]
        ),
        InventoryCategory(
            id: "อาหารแห้ง/กระป๋อง",
            name: "อาหารแห้ง/กระป๋อง",
            icon: "🥫",
            defaultStorageLocation: "ห้องเก็บแห้ง",
            skuPrefixes: ["ING-CAN", "ING-DRY", "ING-DRIED", "ING-BEAN", "ING-LENTIL"],
            nameKeywords: ["canned", "dried", "bean", "lentil", "tofu", "tempeh", "กระป๋อง", "แห้ง", "ถั่ว", "เต้าหู้"]
        ),
        InventoryCategory(
            id: "เครื่องดื่ม",
            name: "เครื่องดื่ม",
            icon: "🥤",
            defaultStorageLocation: "ชั้นวางเครื่องดื่ม",
            skuPrefixes: ["ING-BEV", "ING-DRINK", "ING-TEA", "ING-COFFEE", "ING-JUICE", "ING-SODA", "ING-WATER"],
            nameKeywords: ["tea", "coffee", "juice", "soda", "water", "syrup", "ชา", "กาแฟ", "น้ำผลไม้", "น้ำอัดลม", "น้ำ", "ไซรัป"]
        ),
        InventoryCategory(
            id: "แช่แข็ง",
            name: "แช่แข็ง",
            icon: "🧊",
            defaultStorageLocation: "ตู้แช่แข็ง",
            skuPrefixes: ["ING-FROZEN", "ING-ICE"],
            nameKeywords: ["frozen", "ice cream", "แช่แข็ง", "ไอศกรีม", "น้ำแข็ง"]
        ),
        InventoryCategory(
            id: "บรรจุภัณฑ์",
            name: "บรรจุภัณฑ์",
            icon: "📦",
            defaultStorageLocation: "ห้องเก็บแห้ง",
            skuPrefixes: ["PKG-", "ING-PKG", "ING-BOX", "ING-CUP", "ING-BAG", "ING-WRAP"],
            nameKeywords: ["box", "cup", "bag", "wrap", "container", "lid", "straw", "napkin", "กล่อง", "แก้ว", "ถุง", "ฟิล์ม", "หลอด", "กระดาษ"]
        ),
        InventoryCategory(
            id: "สิ้นเปลือง",
            name: "สิ้นเปลือง",
            icon: "🧹",
            defaultStorageLocation: "ห้องเก็บของ",
            skuPrefixes: ["SUP-", "ING-CLEAN", "ING-SOAP", "ING-GLOVE"],
            nameKeywords: ["clean", "soap", "detergent", "glove", "sanitizer", "towel", "น้ำยา", "สบู่", "ถุงมือ", "ผ้า"]
        ),
    ]

    // MARK: - Get Category Icon

    static func getCategoryIcon(for categoryName: String) -> String {
        allCategories.first(where: { $0.name == categoryName })?.icon ?? "📦"
    }

    // MARK: - Get Category Storage Location

    static func getCategoryStorageLocation(for categoryName: String) -> String {
        allCategories.first(where: { $0.name == categoryName })?.defaultStorageLocation ?? "ไม่ระบุ"
    }

    // MARK: - Item Count Per Category

    static func getItemCountPerCategory(items: [InventoryItem]) -> [(category: String, count: Int, icon: String)] {
        var counts: [String: Int] = [:]
        for item in items {
            let cat = item.category ?? "ไม่ระบุหมวดหมู่"
            counts[cat, default: 0] += 1
        }

        return counts.map { (category: $0.key, count: $0.value, icon: getCategoryIcon(for: $0.key)) }
            .sorted { $0.count > $1.count }
    }

    // MARK: - Auto-Assign Categories

    func autoAssignCategories(items: [InventoryItem]) {
        guard let modelContext = modelContext else { return }

        var assignedCount = 0

        for item in items {
            // Skip items that already have a category assigned
            if item.category != nil { continue }

            if let matchedCategory = matchCategory(for: item) {
                item.category = matchedCategory.name
                item.storageLocation = item.storageLocation ?? matchedCategory.defaultStorageLocation
                item.updatedAt = Date()
                item.isSynced = false
                assignedCount += 1
            }
        }

        if assignedCount > 0 {
            try? modelContext.save()
            Task {
                await SyncEngine.shared.syncAll(modelContext: modelContext)
            }
        }
    }

    // MARK: - Match Category for Single Item

    private func matchCategory(for item: InventoryItem) -> InventoryCategory? {
        let sku = (item.sku ?? "").uppercased()
        let name = item.name.lowercased()

        // Priority 1: SKU prefix matching (most reliable)
        for category in Self.allCategories {
            for prefix in category.skuPrefixes {
                if sku.hasPrefix(prefix.uppercased()) {
                    return category
                }
            }
        }

        // Priority 2: Name keyword matching (fallback)
        for category in Self.allCategories {
            for keyword in category.nameKeywords {
                if name.contains(keyword.lowercased()) {
                    return category
                }
            }
        }

        // Priority 3: Special cases
        // Coconut milk → น้ำมันและไขมัน (if "coconut" + "milk" in name)
        if name.contains("coconut") && name.contains("milk") {
            return Self.allCategories.first(where: { $0.id == "นมและผลิตภัณฑ์นม" })
        }

        return nil
    }

    // MARK: - Assign Category to Single Item

    func assignCategory(item: InventoryItem, category: InventoryCategory) {
        guard let modelContext = modelContext else { return }

        item.category = category.name
        item.storageLocation = category.defaultStorageLocation
        item.updatedAt = Date()
        item.isSynced = false

        try? modelContext.save()
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }

    // MARK: - Bulk Assign Category

    func bulkAssignCategory(items: [InventoryItem], category: InventoryCategory) {
        guard let modelContext = modelContext else { return }

        for item in items {
            item.category = category.name
            item.storageLocation = category.defaultStorageLocation
            item.updatedAt = Date()
            item.isSynced = false
        }

        try? modelContext.save()
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }

    // MARK: - ABC Classification

    /// Pareto ABC Analysis:
    /// - A items: Top ~20% of items that account for ~70% of total value
    /// - B items: Next ~30% accounting for ~20% of value
    /// - C items: Remaining ~50% accounting for ~10% of value
    ///
    /// Uses (costPrice × currentQuantity) as proxy for total inventory value per item.
    static func calculateABCClassification(items: [InventoryItem]) -> [UUID: String] {
        guard !items.isEmpty else { return [:] }

        // Calculate value per item
        let itemValues: [(id: UUID, value: Double)] = items
            .map { (id: $0.id, value: $0.costPrice * max($0.currentQuantity, 0)) }
            .sorted { $0.value > $1.value }

        let totalValue = itemValues.reduce(0.0) { $0 + $1.value }
        guard totalValue > 0 else {
            return Dictionary(uniqueKeysWithValues: items.map { ($0.id, "C") })
        }

        var classification: [UUID: String] = [:]
        var cumulativeValue = 0.0

        for item in itemValues {
            cumulativeValue += item.value
            let percentOfTotal = cumulativeValue / totalValue

            if percentOfTotal <= 0.70 {
                classification[item.id] = "A"
            } else if percentOfTotal <= 0.90 {
                classification[item.id] = "B"
            } else {
                classification[item.id] = "C"
            }
        }

        return classification
    }

    // MARK: - ABC Summary Stats

    static func getABCSummary(items: [InventoryItem], classification: [UUID: String]) -> (aCount: Int, bCount: Int, cCount: Int, aValue: Double, bValue: Double, cValue: Double) {
        var aCount = 0, bCount = 0, cCount = 0
        var aValue = 0.0, bValue = 0.0, cValue = 0.0

        for item in items {
            let value = item.costPrice * max(item.currentQuantity, 0)
            switch classification[item.id] {
            case "A":
                aCount += 1
                aValue += value
            case "B":
                bCount += 1
                bValue += value
            default:
                cCount += 1
                cValue += value
            }
        }

        return (aCount, bCount, cCount, aValue, bValue, cValue)
    }
}
