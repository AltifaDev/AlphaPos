// RecipeCatalogView.swift
// AlphaPos — Premium Recipe & Costing Catalog

import SwiftUI
import SwiftData

struct RecipeCatalogView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var lm: LocalizationManager
    @Query(
        filter: #Predicate<Category> { !$0.isDeleted },
        sort: \Category.name
    ) private var categories: [Category]
    @Query(
        filter: #Predicate<MenuItem> { !$0.isDeleted },
        sort: \MenuItem.name
    ) private var menuItems: [MenuItem]

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
                    LazyVStack(spacing: 4) {
                        ForEach(filteredItems) { item in
                            menuItemRecipeCard(item: item)
                                .onTapGesture {
                                    selectedItem = item
                                    showingBuilder = true
                                }
                        }
                    }
                    .padding(APSpacing.sm)
                }
            }
        }
        .sheet(item: $selectedItem) { item in
            RecipeBuilderSheet(menuItem: item) {
                selectedItem = nil
            }
        }
        .background(Color.appBackground)
        .onAppear {
            let urls = menuItems.compactMap { $0.imageUrl }
            RemoteImageManager.shared.prefetchImages(urls: urls)
        }
        .onChange(of: menuItems) { _, newMenuItems in
            let urls = newMenuItems.compactMap { $0.imageUrl }
            RemoteImageManager.shared.prefetchImages(urls: urls)
        }
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
                    TextField("search_menu_items".t, text: $searchText)
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
                    categoryButton(title: "filter_all".t, id: nil)
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

        return HStack(spacing: APSpacing.sm) {
            RemoteImageView(
                imageUrl: item.imageUrl,
                imageData: item.imageData,
                fallbackColor: Color.appSurfaceHigh,
                fallbackIcon: recipes.isEmpty ? "slash.circle" : (recipes.count == 1 && recipes.first?.quantityRequired == 1.0 ? "shippingbox" : "fork.knife"),
                iconSize: 10
            )
            .frame(width: 28, height: 28)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.textPrimary)

                    // Badge for tracking mode
                    Text(trackingMode == "Not Tracked" ? "catalog_not_tracked".t : (trackingMode == "Finished Good" ? "catalog_finished_good".t : "catalog_recipe_based".t))
                        .font(.system(size: 7, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
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
                    Text(LocalizationManager.shared.t("ingredients_linked_template", recipes.count))
                        .font(.system(size: 9))
                        .foregroundColor(.textSecondary)
                } else {
                    Text("no_stock_setup".t)
                        .font(.system(size: 9))
                        .foregroundColor(.textTertiary)
                }
            }

            Spacer()

            // Financial Costing indicators
            HStack(spacing: APSpacing.sm) {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(LocalizationManager.shared.t("price_template", item.price))
                        .font(.system(size: 9))
                        .foregroundColor(.textPrimary)
                    if !recipes.isEmpty {
                        Text(LocalizationManager.shared.t("cost_template", costPrice))
                            .font(.system(size: 9))
                            .foregroundColor(.textSecondary)
                    }
                }

                if !recipes.isEmpty {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(LocalizationManager.shared.t("margin_template", Int(marginPercent)))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(marginPercent >= 60 ? .appTeal : (marginPercent >= 30 ? .appAmber : .appRose))
                        Text(LocalizationManager.shared.t("food_cost_template", Int(foodCostPercent)))
                            .font(.system(size: 8))
                            .foregroundColor(.textTertiary)
                    }
                    .frame(width: 60, alignment: .trailing)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 8))
                    .foregroundColor(.textTertiary)
            }
        }
        .padding(APSpacing.sm)
        .apCard()
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: APSpacing.md) {
            Image(systemName: "fork.knife.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.textTertiary)
            Text("no_menu_items_found".t)
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
