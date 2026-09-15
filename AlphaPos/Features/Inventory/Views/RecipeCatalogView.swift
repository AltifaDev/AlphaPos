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
    @Query(
        filter: #Predicate<Recipe> { !$0.isDeleted },
        sort: \Recipe.updatedAt
    ) private var allRecipes: [Recipe]
    @Query(
        filter: #Predicate<PrepRecipe> { !$0.isDeleted },
        sort: \PrepRecipe.name
    ) private var nestedRecipes: [PrepRecipe]

    @State private var selectedItem: MenuItem?
    @State private var showingBuilder = false
    @State private var searchText = ""
    @State private var selectedCategoryId: UUID? = nil
    @State private var recipeWorkspace = 0
    @State private var showingRecipeGuide = false

    private var filteredItems: [MenuItem] {
        menuItems.filter { item in
            // A prep output is an internal formula in this workflow, not a
            // customer-facing menu. Keeping it out of the sales workspace
            // prevents operators from confusing sauce/prep setup with a sale.
            guard !isIntermediateMenu(item) else { return false }
            let matchesSearch = searchText.isEmpty || item.name.localizedCaseInsensitiveContains(searchText)
            let matchesCategory = selectedCategoryId == nil || item.category?.id == selectedCategoryId
            return matchesSearch && matchesCategory
        }
    }

    private func isIntermediateMenu(_ item: MenuItem) -> Bool {
        nestedRecipes.contains {
            $0.outputItem?.name.trimmingCharacters(in: .whitespacesAndNewlines)
                .localizedCaseInsensitiveCompare(item.name.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Clean Native Segmented Control Header
            HStack(spacing: APSpacing.md) {
                Picker("", selection: $recipeWorkspace) {
                    Text(lm.currentLanguage == .thai ? "เมนูหน้าร้าน" : "Menu Dishes").tag(0)
                    Text(lm.currentLanguage == .thai ? "สูตรเตรียม" : "Prep Recipes").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)

                Spacer()

                Button {
                    showingRecipeGuide = true
                } label: {
                    Label(lm.currentLanguage == .thai ? "คู่มือการตัดสต็อก" : "Stock Guide",
                          systemImage: "questionmark.circle")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, APSpacing.md)
            .padding(.vertical, APSpacing.sm)
            .apLiquidGlass(allowNativeOnPad: true, in: RoundedRectangle(cornerRadius: 16))

            Divider().background(Color.appDivider)

            if recipeWorkspace == 1 {
                PrepRecipeCatalogView()
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else {
                // Filter Bar
                filterBar

                Divider().background(Color.appDivider)

                if filteredItems.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 290), spacing: APSpacing.sm)], spacing: APSpacing.sm) {
                            ForEach(filteredItems) { item in
                                menuItemRecipeCard(item: item)
                                    .onTapGesture {
                                        selectedItem = item
                                        showingBuilder = true
                                    }
                            }
                        }
                        .padding(12)
                    }
                }
            }
        }
        .sheet(item: $selectedItem) { item in
            RecipeBuilderSheet(menuItem: item) {
                selectedItem = nil
            }
        }
        .sheet(isPresented: $showingRecipeGuide) {
            RecipeStockGuideSheet()
        }
        .background(recipeWorkspace == 1 ? Color.white : Color.appBackground)
        .animation(.easeInOut(duration: 0.24), value: recipeWorkspace)
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
        // The recipe workspace is about stock relationships. Financial metrics
        // live in reporting so they do not compete with the setup task here.
        let recipes = allRecipes.filter { $0.menuItem?.id == item.id }
        let mode = item.resolvedTrackingMode

        let linkedIntermediates = recipes.compactMap { recipe in
            nestedRecipes.first { $0.outputItem?.id == recipe.inventoryItem?.id }?.name
        }
        let isReady = mode != .notTracked && !recipes.isEmpty

        return HStack(spacing: 10) {
            RemoteImageView(
                imageUrl: item.imageUrl,
                imageData: item.imageData,
                fallbackColor: Color.appSurfaceHigh,
                fallbackIcon: mode == .notTracked ? "slash.circle" : (mode == .finishedGood ? "shippingbox" : "fork.knife"),
                iconSize: 10
            )
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.textPrimary)
                        .lineLimit(2)

                    readinessBadge(isReady: isReady)
                }

                if isReady {
                    Text(lm.currentLanguage == .thai
                         ? "ใช้ \(recipes.count) รายการ · ตัดสต็อกเมื่อขาย"
                         : "Uses \(recipes.count) components · deducts on sale")
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                    if !linkedIntermediates.isEmpty {
                        Label(linkedIntermediates.joined(separator: " · "), systemImage: "arrow.triangle.branch")
                            .font(.caption2.weight(.medium))
                            .foregroundColor(.appTeal)
                    }
                } else {
                    Text(lm.currentLanguage == .thai ? "ยังไม่มีสูตรสำหรับตัดสต๊อก" : "No stock formula configured")
                        .font(.caption).foregroundColor(.textTertiary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.bold))
                .foregroundColor(.textTertiary)
        }
        .padding(12)
        .apLiquidGlass(tint: isReady ? Color.appAccent.opacity(0.035) : Color.appAmber.opacity(0.05),
                       interactive: true, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func readinessBadge(isReady: Bool) -> some View {
        Label(isReady
              ? (lm.currentLanguage == .thai ? "พร้อมตัดสต๊อก" : "Stock ready")
              : (lm.currentLanguage == .thai ? "ต้องตั้งค่าสูตร" : "Formula needed"),
              systemImage: isReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            .font(.caption2.weight(.bold))
            .foregroundColor(isReady ? .appTeal : .appAmber)
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background((isReady ? Color.appTeal : Color.appAmber).opacity(0.12), in: Capsule())
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
            Text("inventory_recipes_empty_hint".t)
                .font(.caption)
                .foregroundColor(.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, APSpacing.lg)
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
