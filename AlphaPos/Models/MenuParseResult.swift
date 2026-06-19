// MenuParseResult.swift
// AlphaPos — Data models for AI-powered menu image parsing

import Foundation

// MARK: - Parsed Menu Item (Single extracted product)

struct ParsedMenuItem: Identifiable, Codable {
    let id: UUID
    var name: String
    var price: Double
    var suggestedCategory: String?
    var description: String?
    var isSelected: Bool
    var isDuplicate: Bool
    
    enum CodingKeys: String, CodingKey {
        case id, name, price
        case suggestedCategory = "suggested_category"
        case description
        case isSelected = "is_selected"
        case isDuplicate = "is_duplicate"
    }
    
    init(id: UUID = UUID(), name: String, price: Double, suggestedCategory: String? = nil, description: String? = nil, isSelected: Bool = true, isDuplicate: Bool = false) {
        self.id = id
        self.name = name
        self.price = price
        self.suggestedCategory = suggestedCategory
        self.description = description
        self.isSelected = isSelected
        self.isDuplicate = isDuplicate
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        self.name = try container.decode(String.self, forKey: .name)
        self.price = try container.decode(Double.self, forKey: .price)
        self.suggestedCategory = try container.decodeIfPresent(String.self, forKey: .suggestedCategory)
        self.description = try container.decodeIfPresent(String.self, forKey: .description)
        self.isSelected = (try? container.decode(Bool.self, forKey: .isSelected)) ?? true
        self.isDuplicate = (try? container.decode(Bool.self, forKey: .isDuplicate)) ?? false
    }
}

// MARK: - Menu Parse Result (Full AI response)

struct MenuParseResult: Codable {
    let items: [ParsedMenuItem]
    let suggestedCategories: [String]
    let totalItemsFound: Int
    let confidence: Double
    
    enum CodingKeys: String, CodingKey {
        case items
        case suggestedCategories = "suggested_categories"
        case totalItemsFound = "total_items_found"
        case confidence
    }
}

// MARK: - Import Progress

enum MenuImportStep: Int, CaseIterable {
    case upload = 0
    case review = 1
    case complete = 2
    
    var title: String {
        switch self {
        case .upload:   return "menu_import_step_upload".t
        case .review:   return "menu_import_step_review".t
        case .complete: return "menu_import_step_complete".t
        }
    }
    
    var icon: String {
        switch self {
        case .upload:   return "photo.on.rectangle.angled"
        case .review:   return "checklist"
        case .complete: return "checkmark.seal.fill"
        }
    }
}

struct MenuImportSummary {
    var totalFound: Int = 0
    var imported: Int = 0
    var skipped: Int = 0
    var duplicatesSkipped: Int = 0
    var categoriesCreated: Int = 0
    var errors: [String] = []
}
