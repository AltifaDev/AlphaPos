// CatalogManagerView.swift
// AlphaPos — Unified Catalog Management Dashboard

import SwiftUI
import SwiftData

struct CatalogManagerView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var lm: LocalizationManager
    @EnvironmentObject private var sessionManager: AppSessionManager
    @Query(
        filter: #Predicate<MenuItem> { !$0.isDeleted },
        sort: \MenuItem.name
    ) private var products: [MenuItem]
    @Query(
        filter: #Predicate<Category> { !$0.isDeleted },
        sort: \Category.name
    ) private var categories: [Category]
    @Query(sort: \ModifierGroup.name) private var modifierGroups: [ModifierGroup]
    @Query(
        filter: #Predicate<Recipe> { !$0.isDeleted },
        sort: \Recipe.updatedAt
    ) private var allRecipes: [Recipe]

    @State private var subTab = 0 // 0: Products, 1: Categories, 2: Extras
    @State private var searchText = ""

    // Sheet States
    @State private var selectedProduct: MenuItem? = nil
    @State private var pendingProductForAuthorization: MenuItem? = nil
    @State private var showingProductEditPIN = false
    @State private var productEditAuthorizedBy: UUID? = nil
    @State private var authorizationErrorMessage: String? = nil
    @State private var selectedCategory: Category? = nil
    @State private var selectedModifierGroup: ModifierGroup? = nil

    @State private var showingAddProduct = false
    @State private var showingFinishedGood = false
    @State private var showingFirstProductGuide = false
    @State private var showingMenuImport = false
    @AppStorage("inventory_profile") private var inventoryProfile = "restaurant"
    @State private var showingAddCategory = false
    @State private var showingAddModifierGroup = false

    // Grouping & Filtering States
    @State private var selectedProductCategory = "All"
    @State private var collapsedCategories: Set<String> = []

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

                    if subTab == 0 {
                        Button(action: { showingMenuImport = true }) {
                            Image(systemName: "doc.text.viewfinder")
                                .font(.subheadline).fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(8)
                                .background(APGradient.accent)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }

                    if subTab == 0 {
                        if products.isEmpty {
                            Button(action: { openFirstProductFlow() }) {
                                Image(systemName: "plus")
                                    .font(.subheadline).fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .padding(8)
                                    .background(APGradient.accent)
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("first_product_start_cta".t)
                        } else {
                            Menu {
                                Button {
                                    showingFinishedGood = true
                                } label: {
                                    Label("fg_quick_create_title".t, systemImage: "shippingbox.fill")
                                }
                                Button {
                                    showingAddProduct = true
                                } label: {
                                    Label("fg_full_product_editor".t, systemImage: "fork.knife")
                                }
                            } label: {
                                Image(systemName: "plus")
                                    .font(.subheadline).fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .padding(8)
                                    .background(APGradient.accent)
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
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

                if subTab == 0 {
                    // Category quick-filter chips
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            categoryChip(name: "All")
                            ForEach(uniqueCategoryNames, id: \.self) { name in
                                categoryChip(name: name)
                            }
                            categoryChip(name: "uncategorized".t)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .padding(APSpacing.md)
            .background(Color.appSurface)

            Divider().background(Color.appDivider)

            // Sub-views lists
            ScrollView {
                LazyVStack(spacing: APSpacing.sm) {
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
        .fullScreenCover(item: $selectedProduct) { item in
            ProductEditSheet(menuItem: item, authorizedByEmployeeId: productEditAuthorizedBy) {
                selectedProduct = nil
                productEditAuthorizedBy = nil
            }
        }
        .fullScreenCover(isPresented: $showingAddProduct) {
            ProductEditSheet(menuItem: nil) { showingAddProduct = false }
        }
        .sheet(isPresented: $showingFinishedGood) {
            FinishedGoodQuickCreateSheet(activeBranch: activeCatalogBranch) {
                showingFinishedGood = false
            }
        }
        .sheet(isPresented: $showingFirstProductGuide) {
            FirstProductGuideSheet { outcome in
                showingFirstProductGuide = false
                handleFirstProductOutcome(outcome)
            }
        }
        .fullScreenCover(isPresented: $showingMenuImport) {
            MenuImportSheet { showingMenuImport = false }
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
        .sheet(isPresented: $showingProductEditPIN) {
            ManagerPINVerificationSheet(
                isPresented: $showingProductEditPIN,
                onSuccess: authorizePendingProductEdit,
                onAuthorizedManager: { manager in
                    productEditAuthorizedBy = manager.employeeProfile?.id
                },
                onDismiss: {
                    if !showingProductEditPIN && selectedProduct == nil {
                        pendingProductForAuthorization = nil
                        productEditAuthorizedBy = nil
                    }
                },
                allowStoreOwnerPin: true,
                requiredPermission: .inventoryManage
            )
        }
        .alert("catalog_edit_auth_required_title".t, isPresented: Binding(
            get: { authorizationErrorMessage != nil },
            set: { if !$0 { authorizationErrorMessage = nil } }
        )) {
            Button("ok_btn".t, role: .cancel) { authorizationErrorMessage = nil }
        } message: {
            Text(authorizationErrorMessage ?? "")
        }
        .onAppear {
            let urls = products.compactMap { $0.imageUrl }
            RemoteImageManager.shared.prefetchImages(urls: urls)
            presentPendingFirstProductGuideIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFirstProductGuideNotification)) { _ in
            presentPendingFirstProductGuideIfNeeded()
        }
        .onChange(of: products) { _, newProducts in
            let urls = newProducts.compactMap { $0.imageUrl }
            RemoteImageManager.shared.prefetchImages(urls: urls)
        }
    }

    private func presentPendingFirstProductGuideIfNeeded() {
        guard StoreSetupChecklist.consumePendingFirstProductGuide() else { return }
        guard products.isEmpty else { return }
        subTab = 0
        // Slight delay so InventoryView can switch to .menu first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            showingFirstProductGuide = true
        }
    }

    private func openFirstProductFlow() {
        if products.isEmpty {
            showingFirstProductGuide = true
        } else if inventoryProfile == "simple" {
            showingFinishedGood = true
        } else {
            showingAddProduct = true
        }
    }

    private func handleFirstProductOutcome(_ outcome: FirstProductGuideOutcome) {
        switch outcome {
        case .createTable:
            StoreSetupChecklist.requestAddFirstTable()
        case .openPOS:
            // Tables-on → floor plan (open a table); tables-off → POS.
            NotificationCenter.default.post(name: .openPOSTabNotification, object: nil)
        case .dismiss:
            break
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

    private var uniqueCategoryNames: [String] {
        var names = Set<String>()
        var list: [String] = []
        for cat in categories {
            let name = cat.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = name.lowercased()
            if !names.contains(lower) {
                names.insert(lower)
                list.append(name)
            }
        }
        return list.sorted()
    }

    private func categoryChip(name: String) -> some View {
        Button(action: { selectedProductCategory = name }) {
            Text(name)
                .font(.system(size: 9, weight: .bold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(selectedProductCategory == name ? Color.appAccent : Color.appSurfaceHigh)
                .foregroundColor(selectedProductCategory == name ? .white : .textSecondary)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(selectedProductCategory == name ? Color.clear : Color.appBorderSubtle, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var filteredProducts: [MenuItem] {
        var list = products
        if !searchText.isEmpty {
            list = list.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        if selectedProductCategory != "All" {
            list = list.filter { item in
                let catName = item.category?.name ?? "uncategorized".t
                return catName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == selectedProductCategory.lowercased()
            }
        }
        return list
    }

    private var productsGroupedByCategory: [(category: String, items: [MenuItem])] {
        let list = filteredProducts
        let grouped = Dictionary(grouping: list) { item in
            item.category?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? "uncategorized".t
        }
        return grouped.map { (category: $0.key, items: $0.value) }
            .sorted { a, b in
                if a.category == "uncategorized".t { return false }
                if b.category == "uncategorized".t { return true }
                return a.category.localizedCompare(b.category) == .orderedAscending
            }
    }

    private var productsList: some View {
        VStack(spacing: 12) {
            let grouped = productsGroupedByCategory
            if products.isEmpty {
                firstProductEmptyState
            } else if grouped.isEmpty {
                emptyListView(message: "no_products_matched_search".t)
            } else {
                ForEach(grouped, id: \.category) { section in
                    let isCollapsed = collapsedCategories.contains(section.category)

                    VStack(spacing: 4) {
                        // Section Header
                        Button(action: {
                            if isCollapsed {
                                collapsedCategories.remove(section.category)
                            } else {
                                collapsedCategories.insert(section.category)
                            }
                        }) {
                            HStack {
                                Text(section.category)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.textSecondary)
                                    .textCase(.uppercase)
                                Text("(\(section.items.count))")
                                    .font(.system(size: 8))
                                    .foregroundColor(.textTertiary)
                                Spacer()
                                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.textSecondary)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, APSpacing.sm)
                            .background(Color.appSurfaceHigh.opacity(0.5))
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)

                        if !isCollapsed {
                            ForEach(section.items) { item in
                                let recipes = allRecipes.filter { $0.menuItem?.id == item.id }
                                let mode = item.resolvedTrackingMode
                                let trackingText = mode.catalogLocalizationKey.t
                                let cost = RecipeCostCalculator.cost(for: recipes)
                                let fcPercent = item.price > 0 ? (cost / item.price) * 100.0 : 0.0

                                HStack(spacing: APSpacing.sm) {
                                    RemoteImageView(
                                        imageUrl: item.imageUrl,
                                        imageData: item.imageData,
                                        fallbackColor: Color.appSurfaceHigh,
                                        fallbackIcon: "fork.knife",
                                        iconSize: 10
                                    )
                                    .frame(width: 28, height: 28)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))

                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(item.name)
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundColor(.textPrimary)

                                            Text(trackingText)
                                                .font(.system(size: 7, weight: .bold))
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(mode == .notTracked ? Color.appSurfaceHigh : (mode == .finishedGood ? Color.appTeal.opacity(0.1) : Color.appAccent.opacity(0.1)))
                                                .foregroundColor(mode == .notTracked ? .textSecondary : (mode == .finishedGood ? .appTeal : .appAccent))
                                                .clipShape(Capsule())
                                        }

                                        HStack(spacing: 4) {
                                            if let cat = item.category {
                                                Text(cat.name)
                                                    .font(.system(size: 9))
                                                    .foregroundColor(.textSecondary)
                                                Text("·").font(.system(size: 9)).foregroundColor(.textTertiary)
                                            }
                                            Text("฿\(String(format: "%.2f", item.price))")
                                                .font(.system(size: 9))
                                                .foregroundColor(.textPrimary)
                                        }
                                    }

                                    Spacer()

                                    // Costs and Modifiers link metrics
                                    HStack(spacing: APSpacing.sm) {
                                        if !recipes.isEmpty {
                                            VStack(alignment: .trailing, spacing: 1) {
                                                Text(LocalizationManager.shared.t("food_cost_template", Int(fcPercent)))
                                                    .font(.system(size: 8))
                                                    .foregroundColor(.textTertiary)
                                                Text(LocalizationManager.shared.t("profit_template", Int(100.0 - fcPercent)))
                                                    .font(.system(size: 9, weight: .bold))
                                                    .foregroundColor(100.0 - fcPercent >= 60 ? .appTeal : .appRose)
                                            }
                                        }

                                        if !item.modifierGroupsRelations.isEmpty {
                                            Image(systemName: "plus.circle.fill")
                                                .foregroundColor(.appAccent)
                                                .font(.system(size: 9))
                                        }

                                        Image(systemName: "chevron.right")
                                                    .font(.system(size: 8))
                                                    .foregroundColor(.textTertiary)
                                    }
                                }
                                .padding(APSpacing.sm)
                                .apCard()
                                .onTapGesture {
                                    requestProductEditAuthorization(for: item)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Categories List View

    private var filteredCategories: [Category] {
        let rawList = searchText.isEmpty ? categories : categories.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        var uniqueList: [Category] = []
        var seenNames = Set<String>()
        for cat in rawList {
            let key = cat.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !seenNames.contains(key) {
                seenNames.insert(key)
                uniqueList.append(cat)
            }
        }
        return uniqueList
    }

    private func totalMenuItemsCount(for categoryName: String) -> Int {
        let key = categoryName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matchingCategories = categories.filter { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == key }
        var seenIds = Set<String>()
        var count = 0
        for cat in matchingCategories {
            for item in cat.menuItems where !item.isDeleted {
                if !seenIds.contains(item.id.lowercased()) {
                    seenIds.insert(item.id.lowercased())
                    count += 1
                }
            }
        }
        return count
    }

    private var categoriesList: some View {
        VStack(spacing: 4) {
            if filteredCategories.isEmpty {
                emptyListView(message: "no_categories_matched_search".t)
            } else {
                ForEach(filteredCategories) { cat in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(cat.name)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.textPrimary)
                            if let desc = cat.categoryDescription {
                                Text(desc)
                                    .font(.system(size: 9))
                                    .foregroundColor(.textSecondary)
                            }
                        }

                        Spacer()

                        Text(LocalizationManager.shared.t("products_count_template", totalMenuItemsCount(for: cat.name)))
                            .font(.system(size: 9))
                            .foregroundColor(.textSecondary)
                            .padding(.horizontal, 6)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 8))
                            .foregroundColor(.textTertiary)
                    }
                    .padding(APSpacing.sm)
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
        VStack(spacing: 4) {
            if filteredModifierGroups.isEmpty {
                emptyListView(message: "no_modifiers_matched_search".t)
            } else {
                ForEach(filteredModifierGroups) { group in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.name)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.textPrimary)
                            Text(LocalizationManager.shared.t("selections_range_template", group.minSelection, group.maxSelection))
                                .font(.system(size: 9))
                                .foregroundColor(.textSecondary)
                        }

                        Spacer()

                        Text(LocalizationManager.shared.t("options_count_template", group.modifiers.count))
                            .font(.system(size: 9))
                            .foregroundColor(.textSecondary)
                            .padding(.horizontal, 6)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 8))
                            .foregroundColor(.textTertiary)
                    }
                    .padding(APSpacing.sm)
                    .apCard()
                    .onTapGesture {
                        selectedModifierGroup = group
                    }
                }
            }
        }
    }

    // MARK: - Shared helpers

    private var firstProductEmptyState: some View {
        VStack(spacing: APSpacing.md) {
            Image(systemName: "menucard.fill")
                .font(.system(size: 40))
                .foregroundStyle(APGradient.accent)
            Text("catalog_empty_products_title".t)
                .font(.headline)
                .foregroundColor(.textPrimary)
            Text("catalog_empty_products_subtitle".t)
                .font(.subheadline)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button {
                openFirstProductFlow()
            } label: {
                Label("first_product_start_cta".t, systemImage: "plus.circle.fill")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(APGradient.accent)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: APRadius.md, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .padding(.vertical, APSpacing.lg)
    }

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
        case 0:
            openFirstProductFlow()
        case 1: showingAddCategory = true
        case 2: showingAddModifierGroup = true
        default: break
        }
    }

    private func requestProductEditAuthorization(for item: MenuItem) {
        pendingProductForAuthorization = item
        productEditAuthorizedBy = sessionManager.currentStaffSession?.employeeId
        showingProductEditPIN = true
    }

    private func authorizePendingProductEdit() {
        guard let item = pendingProductForAuthorization else {
            authorizationErrorMessage = "catalog_edit_not_authorized".t
            pendingProductForAuthorization = nil
            return
        }
        selectedProduct = item
        pendingProductForAuthorization = nil
    }

    private var activeCatalogBranch: Branch? {
        try? BranchContext.shared.requireActiveBranch(in: modelContext)
    }
}
