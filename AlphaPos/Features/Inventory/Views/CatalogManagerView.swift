// CatalogManagerView.swift
// AlphaPos — Unified Catalog Management Dashboard

import SwiftUI
import SwiftData

struct CatalogManagerView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var lm: LocalizationManager
    @Query(sort: \MenuItem.name) private var products: [MenuItem]
    @Query(sort: \Category.name) private var categories: [Category]
    @Query(sort: \ModifierGroup.name) private var modifierGroups: [ModifierGroup]
    
    @State private var subTab = 0 // 0: Products, 1: Categories, 2: Extras
    @State private var searchText = ""
    
    // Sheet States
    @State private var selectedProduct: MenuItem? = nil
    @State private var selectedCategory: Category? = nil
    @State private var selectedModifierGroup: ModifierGroup? = nil
    
    @State private var showingAddProduct = false
    @State private var showingAddCategory = false
    @State private var showingAddModifierGroup = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Control Header
            VStack(spacing: APSpacing.sm) {
                HStack(spacing: APSpacing.md) {
                    Picker("Catalog Options", selection: $subTab) {
                        Text("inventory_products".t).tag(0)
                        Text("catalog_categories".t).tag(1)
                        Text("catalog_extras".t).tag(2)
                    }
                    .pickerStyle(.segmented)
                    
                    Button(action: openAddSheet) {
                        Image(systemName: "plus")
                            .font(.subheadline).fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(8)
                            .background(APGradient.accent)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                
                // Search field
                HStack(spacing: APSpacing.xs) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.textSecondary)
                        .font(.footnote)
                    TextField(searchPlaceholder, text: $searchText)
                        .font(.subheadline)
                        .foregroundColor(.textPrimary)
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.textSecondary)
                        }
                    }
                }
                .padding(8)
                .background(Color.appSurfaceHigh)
                .cornerRadius(APRadius.md)
                .overlay(
                    RoundedRectangle(cornerRadius: APRadius.md)
                        .stroke(Color.appBorderSubtle, lineWidth: 1)
                )
            }
            .padding(APSpacing.md)
            .background(Color.appSurface)
            
            Divider().background(Color.appDivider)
            
            // Sub-views lists
            ScrollView {
                VStack(spacing: APSpacing.sm) {
                    switch subTab {
                    case 0:
                        productsList
                    case 1:
                        categoriesList
                    case 2:
                        extrasList
                    default:
                        EmptyView()
                    }
                }
                .padding(APSpacing.md)
            }
            .background(Color.appBackground)
        }
        .sheet(item: $selectedProduct) { item in
            ProductEditSheet(menuItem: item) { selectedProduct = nil }
        }
        .sheet(isPresented: $showingAddProduct) {
            ProductEditSheet(menuItem: nil) { showingAddProduct = false }
        }
        .sheet(item: $selectedCategory) { item in
            CategoryEditSheet(category: item) { selectedCategory = nil }
        }
        .sheet(isPresented: $showingAddCategory) {
            CategoryEditSheet(category: nil) { showingAddCategory = false }
        }
        .sheet(item: $selectedModifierGroup) { item in
            ModifierGroupEditSheet(group: item) { selectedModifierGroup = nil }
        }
        .sheet(isPresented: $showingAddModifierGroup) {
            ModifierGroupEditSheet(group: nil) { showingAddModifierGroup = false }
        }
    }
    
    // MARK: - Filtered Lists Helper
    
    private var searchPlaceholder: String {
        switch subTab {
        case 0: return "search_products".t
        case 1: return "search_categories".t
        case 2: return "search_modifiers".t
        default: return "search_placeholder".t
        }
    }
    
    // MARK: - Products List View
    
    private var filteredProducts: [MenuItem] {
        guard !searchText.isEmpty else { return products }
        return products.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    private var productsList: some View {
        VStack(spacing: APSpacing.sm) {
            if filteredProducts.isEmpty {
                emptyListView(message: "no_products_matched_search".t)
            } else {
                ForEach(filteredProducts) { item in
                    let recipes = item.recipes
                    let trackingText = recipes.isEmpty ? "catalog_not_tracked".t : (recipes.count == 1 && recipes.first?.quantityRequired == 1.0 ? "catalog_finished_good".t : "catalog_recipe_based".t)
                    let cost = recipes.reduce(0.0) { $0 + ($1.inventoryItem?.costPrice ?? 0.0) * $1.quantityRequired }
                    let fcPercent = item.price > 0 ? (cost / item.price) * 100.0 : 0.0
                    
                    HStack(spacing: APSpacing.md) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(item.name)
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.textPrimary)
                                
                                Text(trackingText)
                                    .font(.system(size: 8, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(recipes.isEmpty ? Color.appSurfaceHigh : (recipes.count == 1 ? Color.appTeal.opacity(0.1) : Color.appAccent.opacity(0.1)))
                                    .foregroundColor(recipes.isEmpty ? .textSecondary : (recipes.count == 1 ? .appTeal : .appAccent))
                                    .clipShape(Capsule())
                            }
                            
                            HStack(spacing: 6) {
                                if let cat = item.category {
                                    Text(cat.name)
                                        .font(.caption2)
                                        .foregroundColor(.textSecondary)
                                    Text("·").foregroundColor(.textTertiary)
                                }
                                Text("฿\(String(format: "%.2f", item.price))")
                                    .font(.caption2)
                                    .foregroundColor(.textPrimary)
                            }
                        }
                        
                        Spacer()
                        
                        // Costs and Modifiers link metrics
                        HStack(spacing: APSpacing.md) {
                            if !recipes.isEmpty {
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(LocalizationManager.shared.t("food_cost_template", Int(fcPercent)))
                                        .font(.system(size: 9))
                                        .foregroundColor(.textTertiary)
                                    Text(LocalizationManager.shared.t("profit_template", Int(100.0 - fcPercent)))
                                        .font(.caption)
                                        .bold()
                                        .foregroundColor(100.0 - fcPercent >= 60 ? .appTeal : .appRose)
                                }
                            }
                            
                            if !item.modifierGroupsRelations.isEmpty {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(.appAccent)
                                    .font(.caption)
                            }
                            
                            Image(systemName: "chevron.right")
                                        .font(.footnote)
                                        .foregroundColor(.textTertiary)
                        }
                    }
                    .padding(APSpacing.md)
                    .apCard()
                    .onTapGesture {
                        selectedProduct = item
                    }
                }
            }
        }
    }
    
    // MARK: - Categories List View
    
    private var filteredCategories: [Category] {
        guard !searchText.isEmpty else { return categories }
        return categories.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    private var categoriesList: some View {
        VStack(spacing: APSpacing.sm) {
            if filteredCategories.isEmpty {
                emptyListView(message: "no_categories_matched_search".t)
            } else {
                ForEach(filteredCategories) { cat in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(cat.name)
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(.textPrimary)
                            if let desc = cat.categoryDescription {
                                Text(desc)
                                    .font(.caption2)
                                    .foregroundColor(.textSecondary)
                            }
                        }
                        
                        Spacer()
                        
                        Text(LocalizationManager.shared.t("products_count_template", cat.menuItems.count))
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                            .padding(.horizontal, 10)
                        
                        Image(systemName: "chevron.right")
                            .font(.footnote)
                            .foregroundColor(.textTertiary)
                    }
                    .padding(APSpacing.md)
                    .apCard()
                    .onTapGesture {
                        selectedCategory = cat
                    }
                }
            }
        }
    }
    
    // MARK: - Extras List View
    
    private var filteredModifierGroups: [ModifierGroup] {
        guard !searchText.isEmpty else { return modifierGroups }
        return modifierGroups.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    private var extrasList: some View {
        VStack(spacing: APSpacing.sm) {
            if filteredModifierGroups.isEmpty {
                emptyListView(message: "no_modifiers_matched_search".t)
            } else {
                ForEach(filteredModifierGroups) { group in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(group.name)
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(.textPrimary)
                            Text(LocalizationManager.shared.t("selections_range_template", group.minSelection, group.maxSelection))
                                .font(.caption2)
                                .foregroundColor(.textSecondary)
                        }
                        
                        Spacer()
                        
                        Text(LocalizationManager.shared.t("options_count_template", group.modifiers.count))
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                            .padding(.horizontal, 10)
                        
                        Image(systemName: "chevron.right")
                            .font(.footnote)
                            .foregroundColor(.textTertiary)
                    }
                    .padding(APSpacing.md)
                    .apCard()
                    .onTapGesture {
                        selectedModifierGroup = group
                    }
                }
            }
        }
    }
    
    // MARK: - Shared helpers
    
    private func emptyListView(message: String) -> some View {
        VStack(spacing: APSpacing.sm) {
            Image(systemName: "magnifyingglass.circle")
                .font(.title)
                .foregroundColor(.textTertiary)
            Text(message)
                .font(.caption)
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }
    
    private func openAddSheet() {
        switch subTab {
        case 0: showingAddProduct = true
        case 1: showingAddCategory = true
        case 2: showingAddModifierGroup = true
        default: break
        }
    }
}
