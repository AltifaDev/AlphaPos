// RecipeCatalogView.swift
// AlphaPos — Premium Recipe & Costing Catalog

import SwiftUI
import SwiftData

struct RecipeCatalogView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Category.name) private var categories: [Category]
    @Query(sort: \MenuItem.name) private var menuItems: [MenuItem]
    
    @State private var selectedItem: MenuItem?
    @State private var showingBuilder = false
    @State private var searchText = ""
    @State private var selectedCategoryId: UUID? = nil
    
    private var filteredItems: [MenuItem] {
        menuItems.filter { item in
            let matchesSearch = searchText.isEmpty || item.name.localizedCaseInsensitiveContains(searchText)
            let matchesCategory = selectedCategoryId == nil || item.category?.id == selectedCategoryId
            return matchesSearch && matchesCategory
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Filter Bar
            filterBar
            
            Divider().background(Color.appDivider)
            
            if filteredItems.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: APSpacing.md) {
                        ForEach(filteredItems) { item in
                            menuItemRecipeCard(item: item)
                                .onTapGesture {
                                    selectedItem = item
                                    showingBuilder = true
                                }
                        }
                    }
                    .padding(APSpacing.md)
                }
            }
        }
        .sheet(item: $selectedItem) { item in
            RecipeBuilderSheet(menuItem: item) {
                selectedItem = nil
            }
        }
        .background(Color.appBackground)
    }
    
    // MARK: - Filter Bar
    
    private var filterBar: some View {
        VStack(spacing: APSpacing.sm) {
            HStack(spacing: APSpacing.sm) {
                // Search field
                HStack(spacing: APSpacing.xs) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.textSecondary)
                        .font(.footnote)
                    TextField("Search menu items...", text: $searchText)
                        .font(.subheadline)
                        .foregroundColor(.textPrimary)
                        .tint(.appAccent)
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.textSecondary)
                        }
                    }
                }
                .padding(.horizontal, APSpacing.sm)
                .padding(.vertical, 8)
                .background(Color.appSurfaceHigh)
                .cornerRadius(APRadius.md)
                .overlay(
                    RoundedRectangle(cornerRadius: APRadius.md)
                        .stroke(Color.appBorderSubtle, lineWidth: 1)
                )
            }
            
            // Category capsules
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: APSpacing.xs) {
                    categoryButton(title: "All", id: nil)
                    ForEach(categories) { cat in
                        categoryButton(title: cat.name, id: cat.id)
                    }
                }
            }
        }
        .padding(.horizontal, APSpacing.md)
        .padding(.vertical, APSpacing.sm)
        .background(Color.appSurface)
    }
    
    private func categoryButton(title: String, id: UUID?) -> some View {
        Button(action: { selectedCategoryId = id }) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(selectedCategoryId == id ? APGradient.accent : nil)
                .backgroundColor(selectedCategoryId == id ? .clear : Color.appSurfaceHigh)
                .foregroundColor(selectedCategoryId == id ? .white : .textSecondary)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(selectedCategoryId == id ? Color.clear : Color.appBorderSubtle, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Menu Item Row Card
    
    private func menuItemRecipeCard(item: MenuItem) -> some View {
        // Calculate tracking mode and costing
        let recipes = item.recipes
        let trackingMode: String
        let costPrice: Double
        
        if recipes.isEmpty {
            trackingMode = "Not Tracked"
            costPrice = 0.0
        } else if recipes.count == 1 && recipes.first?.quantityRequired == 1.0 {
            trackingMode = "Finished Good"
            costPrice = recipes.first?.inventoryItem?.costPrice ?? 0.0
        } else {
            trackingMode = "Recipe-Based"
            costPrice = recipes.reduce(0.0) { $0 + ($1.inventoryItem?.costPrice ?? 0.0) * $1.quantityRequired }
        }
        
        let foodCostPercent = item.price > 0 ? (costPrice / item.price) * 100.0 : 0.0
        let marginPercent = 100.0 - foodCostPercent
        
        return HStack(spacing: APSpacing.md) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: APRadius.sm, style: .continuous)
                    .fill(Color.appSurfaceHigh)
                    .frame(width: 46, height: 46)
                
                Image(systemName: recipes.isEmpty ? "slash.circle" : (recipes.count == 1 && recipes.first?.quantityRequired == 1.0 ? "shippingbox" : "fork.knife"))
                    .font(.title3)
                    .foregroundColor(recipes.isEmpty ? .textTertiary : (recipes.count == 1 ? .appTeal : .appAccent))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(item.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.textPrimary)
                    
                    // Badge for tracking mode
                    Text(trackingMode)
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            trackingMode == "Not Tracked" ? Color.appSurfaceHigh :
                            (trackingMode == "Finished Good" ? Color.appTeal.opacity(0.12) : Color.appAccent.opacity(0.12))
                        )
                        .foregroundColor(
                            trackingMode == "Not Tracked" ? .textTertiary :
                            (trackingMode == "Finished Good" ? .appTeal : .appAccent)
                        )
                        .clipShape(Capsule())
                }
                
                if !recipes.isEmpty {
                    Text("\(recipes.count) raw ingredient\(recipes.count > 1 ? "s" : "") linked")
                        .font(.caption2)
                        .foregroundColor(.textSecondary)
                } else {
                    Text("No stock connection setup")
                        .font(.caption2)
                        .foregroundColor(.textTertiary)
                }
            }
            
            Spacer()
            
            // Financial Costing indicators
            HStack(spacing: APSpacing.md) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Price: ฿\(String(format: "%.2f", item.price))")
                        .font(.caption)
                        .foregroundColor(.textPrimary)
                    if !recipes.isEmpty {
                        Text("Cost: ฿\(String(format: "%.2f", costPrice))")
                            .font(.caption2)
                            .foregroundColor(.textSecondary)
                    }
                }
                
                if !recipes.isEmpty {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Margin: \(String(format: "%.0f%%", marginPercent))")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(marginPercent >= 60 ? .appTeal : (marginPercent >= 30 ? .appAmber : .appRose))
                        Text("Food Cost: \(String(format: "%.0f%%", foodCostPercent))")
                            .font(.system(size: 9))
                            .foregroundColor(.textTertiary)
                    }
                    .frame(width: 80, alignment: .trailing)
                }
                
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundColor(.textTertiary)
            }
        }
        .padding(APSpacing.md)
        .apCard()
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: APSpacing.md) {
            Image(systemName: "fork.knife.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.textTertiary)
            Text("No Menu Items Found")
                .font(.headline)
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// Custom backgroundColor backport modifier
extension View {
    func backgroundColor(_ color: Color) -> some View {
        self.background(color)
    }
}
