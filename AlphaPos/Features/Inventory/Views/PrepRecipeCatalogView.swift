import SwiftUI
import SwiftData

struct PrepRecipeCatalogView: View {
    private static let pageSize = 50
    @State private var fetchLimit = pageSize

    var body: some View {
        PrepRecipeCatalogPage(
            fetchLimit: fetchLimit,
            pageSize: Self.pageSize,
            onLoadMore: { fetchLimit += Self.pageSize }
        )
        // Recreate the bounded SwiftData query only when the user requests the
        // next page. This avoids materializing the complete recipe catalogue
        // when the workspace first opens.
        .id(fetchLimit)
    }
}

private struct PrepRecipeCatalogPage: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var recipes: [PrepRecipe]

    let fetchLimit: Int
    let pageSize: Int
    let onLoadMore: () -> Void

    @State private var selectedRecipeId: UUID?
    @State private var editorDestination: PrepEditorDestination?
    @State private var expandedRecipeIDs: Set<UUID> = []
    @State private var searchText = ""
    @State private var filterMode: FilterMode = .all

    init(fetchLimit: Int, pageSize: Int, onLoadMore: @escaping () -> Void) {
        var descriptor = FetchDescriptor<PrepRecipe>(
            predicate: #Predicate { $0.isDeleted == false },
            sortBy: [SortDescriptor(\PrepRecipe.name)]
        )
        descriptor.fetchLimit = fetchLimit
        _recipes = Query(descriptor)
        self.fetchLimit = fetchLimit
        self.pageSize = pageSize
        self.onLoadMore = onLoadMore
    }

    enum FilterMode: String, CaseIterable {
        case all = "ทั้งหมด"
        case rootsOnly = "สูตรหลัก"
        case nestedOnly = "สูตรย่อย"

        var titleTh: String { rawValue }
        var titleEn: String {
            switch self {
            case .all: return "All"
            case .rootsOnly: return "Roots Only"
            case .nestedOnly: return "Sub-recipes Only"
            }
        }
    }

    enum PrepEditorDestination: Identifiable {
        case new
        case edit(PrepRecipe)

        var id: String {
            switch self {
            case .new: return "new"
            case .edit(let recipe): return recipe.id.uuidString
            }
        }
    }

    private struct TreeRow: Identifiable {
        let recipe: PrepRecipe
        let depth: Int
        let isRoot: Bool
        let hasChildren: Bool
        var id: UUID { recipe.id }
    }

    private var activeRecipes: [PrepRecipe] { recipes }

    private var selectedRecipe: PrepRecipe? {
        if let id = selectedRecipeId {
            return activeRecipes.first { $0.id == id }
        }
        return activeRecipes.first
    }

    var body: some View {
        NavigationSplitView {
            sidebarPane
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 360)
                .navigationTitle(LocalizationManager.shared.currentLanguage == .thai ? "สูตรเตรียม" : "Prep Recipes")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            editorDestination = .new
                        } label: {
                            Label(LocalizationManager.shared.currentLanguage == .thai ? "สร้างสูตรเตรียม" : "New Prep", systemImage: "plus")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }
        } detail: {
            if let recipe = selectedRecipe {
                PrepRecipeDetailPaneView(
                    recipe: recipe,
                    allRecipes: activeRecipes,
                    onEdit: { editorDestination = .edit(recipe) }
                )
            } else {
                ContentUnavailableView(
                    LocalizationManager.shared.currentLanguage == .thai ? "ยังไม่มีสูตรเตรียม" : "No Prep Recipes",
                    systemImage: "arrow.triangle.branch",
                    description: Text(LocalizationManager.shared.currentLanguage == .thai
                                      ? "กดปุ่ม + เพื่อสร้างสูตรเตรียมหรือวัตถุดิบกึ่งสำเร็จรูปสำหรับตัดสต็อก"
                                      : "Tap + to create intermediate prep formulas.")
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(item: $editorDestination) { destination in
            switch destination {
            case .new:
                PrepRecipeEditorView(recipe: nil)
            case .edit(let recipe):
                PrepRecipeEditorView(recipe: recipe)
            }
        }
        .onAppear {
            if selectedRecipeId == nil, let first = activeRecipes.first {
                selectedRecipeId = first.id
            }
        }
    }

    // MARK: - Sidebar Master List

    private var sidebarPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(LocalizationManager.shared.currentLanguage == .thai ? "ค้นหาสูตรเตรียม" : "Search recipes", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .accessibilityLabel(LocalizationManager.shared.currentLanguage == .thai ? "ล้างคำค้นหา" : "Clear search")
                }
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .apLiquidGlass(in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            // Filter mode capsules
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(FilterMode.allCases, id: \.self) { mode in
                        Button {
                            filterMode = mode
                        } label: {
                            Text(LocalizationManager.shared.currentLanguage == .thai ? mode.titleTh : mode.titleEn)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(filterMode == mode ? Color.appAccent : Color.appSurfaceHigh)
                                .foregroundColor(filterMode == mode ? .white : .textSecondary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, APSpacing.md)
                .padding(.vertical, APSpacing.xs)
            }
            .background(Color.appSurface)

            Divider().background(Color.appDivider)

            // Recipe List
            if displayedRows.isEmpty {
                if searchText.isEmpty {
                    ContentUnavailableView(
                        LocalizationManager.shared.currentLanguage == .thai ? "ยังไม่มีสูตรเตรียม" : "No Prep Recipes",
                        systemImage: "arrow.triangle.branch",
                        description: Text(LocalizationManager.shared.currentLanguage == .thai
                                          ? "กดปุ่ม + เพื่อสร้างสูตรเตรียม"
                                          : "Tap + to create a prep recipe.")
                    )
                } else {
                    ContentUnavailableView.search(text: searchText)
                }
            } else {
                List(selection: $selectedRecipeId) {
                    ForEach(displayedRows) { row in
                        recipeRowView(row.recipe, depth: row.depth, isRoot: row.isRoot, hasChildren: row.hasChildren)
                            .tag(row.recipe.id)
                            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                    }

                    if recipes.count >= fetchLimit {
                        Button(action: onLoadMore) {
                            HStack {
                                Spacer()
                                Label(
                                    LocalizationManager.shared.currentLanguage == .thai
                                        ? "โหลดเพิ่มอีก \(pageSize) รายการ"
                                        : "Load \(pageSize) more",
                                    systemImage: "arrow.down.circle"
                                )
                                .font(.subheadline.weight(.semibold))
                                Spacer()
                            }
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.plain)
                .environment(\.defaultMinListRowHeight, 52)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Color.white)
        .animation(.easeInOut(duration: 0.22), value: selectedRecipeId)
        .animation(.easeInOut(duration: 0.22), value: expandedRecipeIDs)
    }

    // MARK: - Tree Hierarchy Rows

    private var displayedRows: [TreeRow] {
        let recipes = activeRecipes
        let recipeByID = Dictionary(uniqueKeysWithValues: recipes.map { ($0.id, $0) })
        // Keep the first recipe if legacy data contains duplicate output-item
        // relationships. Dictionary(uniqueKeysWithValues:) would trap here.
        let outputToRecipeID = recipes.reduce(into: [UUID: UUID]()) { result, recipe in
            guard let outputID = recipe.outputItem?.id, result[outputID] == nil else { return }
            result[outputID] = recipe.id
        }

        // Build the relationship graph once. The previous implementation called
        // isChild()/children() from every computed property and every row, which
        // became quadratic (and ran on the SwiftUI main thread).
        var childrenByRecipeID: [UUID: [PrepRecipe]] = [:]
        var childIDs = Set<UUID>()
        for recipe in recipes {
            for component in recipe.components where !component.isDeleted {
                guard let ingredientID = component.ingredient?.id,
                      let childID = outputToRecipeID[ingredientID],
                      childID != recipe.id,
                      let child = recipeByID[childID] else { continue }
                childrenByRecipeID[recipe.id, default: []].append(child)
                childIDs.insert(childID)
            }
        }

        let matching = recipes.filter {
            searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText)
        }

        if !searchText.isEmpty {
            return matching.filter { recipe in
                filterMode == .all || (filterMode == .rootsOnly ? !childIDs.contains(recipe.id) : childIDs.contains(recipe.id))
            }.map {
                TreeRow(recipe: $0, depth: 0, isRoot: !childIDs.contains($0.id), hasChildren: !(childrenByRecipeID[$0.id] ?? []).isEmpty)
            }
        }

        let roots = matching.filter { !childIDs.contains($0.id) }
        if filterMode == .nestedOnly {
            return matching.filter { childIDs.contains($0.id) }.map {
                TreeRow(recipe: $0, depth: 0, isRoot: false, hasChildren: !(childrenByRecipeID[$0.id] ?? []).isEmpty)
            }
        }

        return roots.flatMap {
            flattenedRows(for: $0, depth: 0, ancestry: [], childrenByRecipeID: childrenByRecipeID, childIDs: childIDs)
        }
    }

    private func flattenedRows(
        for recipe: PrepRecipe,
        depth: Int,
        ancestry: Set<UUID>,
        childrenByRecipeID: [UUID: [PrepRecipe]],
        childIDs: Set<UUID>
    ) -> [TreeRow] {
        guard !ancestry.contains(recipe.id) else { return [] }
        let children = childrenByRecipeID[recipe.id] ?? []
        let row = TreeRow(recipe: recipe, depth: depth, isRoot: !childIDs.contains(recipe.id), hasChildren: !children.isEmpty)
        guard expandedRecipeIDs.contains(recipe.id) else { return [row] }
        let nextAncestry = ancestry.union([recipe.id])
        return [row] + children.flatMap {
            flattenedRows(for: $0, depth: depth + 1, ancestry: nextAncestry, childrenByRecipeID: childrenByRecipeID, childIDs: childIDs)
        }
    }

    private func recipeRowView(_ recipe: PrepRecipe, depth: Int, isRoot: Bool, hasChildren: Bool) -> some View {
        let activeComponents = recipe.components.filter { !$0.isDeleted }
        let batchCost = calculateBatchCost(recipe)

        return HStack(spacing: 8) {
            // Tree indentation & expander
            if depth > 0 {
                HStack(spacing: 0) {
                    ForEach(0..<depth, id: \.self) { _ in
                        Rectangle()
                            .fill(Color.appDivider)
                            .frame(width: 2)
                            .padding(.leading, 8)
                    }
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.textTertiary)
                        .padding(.trailing, 2)
                }
            }

            if hasChildren {
                Button {
                    if expandedRecipeIDs.contains(recipe.id) {
                        expandedRecipeIDs.remove(recipe.id)
                    } else {
                        expandedRecipeIDs.insert(recipe.id)
                    }
                } label: {
                    Image(systemName: expandedRecipeIDs.contains(recipe.id) ? "chevron.down.circle.fill" : "chevron.right.circle.fill")
                        .foregroundColor(.appAccent)
                        .font(.body)
                }
                .buttonStyle(.plain)
            } else {
                Circle()
                    .fill(isRoot ? Color.appAccent.opacity(0.8) : Color.appTeal.opacity(0.8))
                    .frame(width: 7, height: 7)
                    .padding(.leading, hasChildren ? 0 : 4)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(recipe.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)

                    Text(isRoot ? (LocalizationManager.shared.currentLanguage == .thai ? "สูตรหลัก" : "Root") : (LocalizationManager.shared.currentLanguage == .thai ? "สูตรย่อย" : "Sub-recipe"))
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background((isRoot ? Color.appAccent : Color.appTeal).opacity(0.12))
                        .foregroundColor(isRoot ? .appAccent : .appTeal)
                        .clipShape(Capsule())
                }

                HStack(spacing: 6) {
                    Text("\(formatted(recipe.expectedOutputQuantity)) \(recipe.outputUnit)")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.textSecondary)
                    Text("•")
                        .font(.caption2)
                        .foregroundColor(.textTertiary)
                    Text("\(activeComponents.count) ส่วนผสม")
                        .font(.caption2)
                        .foregroundColor(.textTertiary)
                }
            }

            Spacer()

            // Cost summary in row
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "฿%.2f", batchCost))
                    .font(.caption.weight(.bold))
                    .foregroundColor(.textPrimary)
                if recipe.expectedOutputQuantity > 0 {
                    Text(String(format: "฿%.3f/%@", batchCost / recipe.expectedOutputQuantity, recipe.outputUnit))
                        .font(.system(size: 9))
                        .foregroundColor(.textSecondary)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedRecipeId = recipe.id
        }
    }

    private func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    private func calculateBatchCost(_ recipe: PrepRecipe) -> Double {
        recipe.components.filter { !$0.isDeleted }.reduce(0.0) { sum, comp in
            guard let item = comp.ingredient else { return sum }
            return sum + PrepRecipeMath.componentCost(
                unitCost: item.costPrice,
                quantity: comp.quantity,
                quantityUnit: comp.quantityUnit,
                inventoryUnit: item.unit
            )
        }
    }
}

// MARK: - Detail Pane View

private struct PrepRecipeDetailPaneView: View {
    @Environment(\.modelContext) private var modelContext
    let recipe: PrepRecipe
    let allRecipes: [PrepRecipe]
    let onEdit: () -> Void
    @State private var showsStockFlow = false
    @State private var showsInstructions = false
    @State private var consumingMenuItems: [MenuItem] = []

    private var activeComponents: [PrepRecipeComponent] {
        recipe.components.filter { !$0.isDeleted }
    }

    private var batchCost: Double {
        activeComponents.reduce(0.0) { sum, comp in
            guard let item = comp.ingredient else { return sum }
            return sum + PrepRecipeMath.componentCost(
                unitCost: item.costPrice,
                quantity: comp.quantity,
                quantityUnit: comp.quantityUnit,
                inventoryUnit: item.unit
            )
        }
    }

    private var unitCost: Double {
        guard recipe.expectedOutputQuantity > 0 else { return 0 }
        return batchCost / recipe.expectedOutputQuantity
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                
                // Top Header Card
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(recipe.name)
                                .font(.title2.weight(.bold))
                                .foregroundColor(.textPrimary)

                            if let output = recipe.outputItem {
                                Label(output.name, systemImage: "shippingbox.fill")
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.appSurfaceHigh)
                                    .foregroundColor(.textSecondary)
                                    .clipShape(Capsule())
                            }
                        }

                        Text(LocalizationManager.shared.currentLanguage == .thai
                             ? "แก้ไขล่าสุด: \(recipe.updatedAt.formatted(date: .abbreviated, time: .shortened))"
                             : "Last updated: \(recipe.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundColor(.textTertiary)
                    }

                    Spacer()

                    Button {
                        onEdit()
                    } label: {
                        Label(LocalizationManager.shared.currentLanguage == .thai ? "แก้ไขสูตร" : "Edit Formula", systemImage: "pencil")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)

                // KPI Metric Cards Row
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    kpiCard(
                        title: LocalizationManager.shared.currentLanguage == .thai ? "ผลผลิตต่อแบตช์" : "Batch Yield",
                        value: "\(formatted(recipe.expectedOutputQuantity)) \(recipe.outputUnit)",
                        subtext: LocalizationManager.shared.currentLanguage == .thai ? "\(activeComponents.count) ส่วนผสม" : "\(activeComponents.count) ingredients",
                        icon: "scalemass.fill",
                        color: .appAccent
                    )

                    kpiCard(
                        title: LocalizationManager.shared.currentLanguage == .thai ? "ต้นทุนรวมต่อแบตช์" : "Total Batch Cost",
                        value: String(format: "฿%.2f", batchCost),
                        subtext: LocalizationManager.shared.currentLanguage == .thai ? "รวมวัตถุดิบทั้งหมด" : "All ingredients included",
                        icon: "banknote.fill",
                        color: .appTeal
                    )

                    kpiCard(
                        title: LocalizationManager.shared.currentLanguage == .thai ? "ต้นทุนต่อหน่วย" : "Unit Cost",
                        value: String(format: "฿%.4f / %@", unitCost, recipe.outputUnit),
                        subtext: LocalizationManager.shared.currentLanguage == .thai ? "คำนวณจากผลผลิตจริง" : "Calculated from yield",
                        icon: "chart.line.uptrend.xyaxis",
                        color: .appAmber
                    )
                }
                .padding(.horizontal, 14)

                // Bill of Materials (BOM) Table
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(LocalizationManager.shared.currentLanguage == .thai ? "ส่วนผสม" : "Bill of Materials",
                              systemImage: "list.bullet.rectangle.portrait.fill")
                            .font(.headline)
                            .foregroundColor(.textPrimary)

                        Spacer()

                        Text("\(activeComponents.count) รายการ")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.textSecondary)
                    }

                    VStack(spacing: 0) {
                        // Table Header
                        HStack {
                            Text(LocalizationManager.shared.currentLanguage == .thai ? "วัตถุดิบ / สูตรเตรียม" : "Item")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.textSecondary)
                            Spacer()
                            Text(LocalizationManager.shared.currentLanguage == .thai ? "ปริมาณที่ใช้" : "Quantity")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.textSecondary)
                                .frame(width: 90, alignment: .trailing)
                            Text(LocalizationManager.shared.currentLanguage == .thai ? "ราคาต่อหน่วย" : "Unit Price")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.textSecondary)
                                .frame(width: 90, alignment: .trailing)
                            Text(LocalizationManager.shared.currentLanguage == .thai ? "ต้นทุนรวม" : "Total Cost")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.textSecondary)
                                .frame(width: 90, alignment: .trailing)
                        }
                        .padding(.horizontal, APSpacing.md)
                        .padding(.vertical, 7)
                        .background(Color.appSurfaceHigh)

                        Divider().background(Color.appDivider)

                        // Table Rows
                        ForEach(activeComponents) { comp in
                            let item = comp.ingredient
                            let isSubRecipe = allRecipes.contains { $0.outputItem?.id == item?.id }
                            let compCost = item != nil ? PrepRecipeMath.componentCost(
                                unitCost: item!.costPrice,
                                quantity: comp.quantity,
                                quantityUnit: comp.quantityUnit,
                                inventoryUnit: item!.unit
                            ) : 0

                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(item?.name ?? "—")
                                            .font(.subheadline.weight(.medium))
                                            .foregroundColor(.textPrimary)

                                        if isSubRecipe {
                                            Text(LocalizationManager.shared.currentLanguage == .thai ? "สูตรย่อย" : "Sub-recipe")
                                                .font(.system(size: 9, weight: .bold))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 1.5)
                                                .background(Color.appTeal.opacity(0.12))
                                                .foregroundColor(.appTeal)
                                                .clipShape(Capsule())
                                        }
                                    }

                                    if isSubRecipe {
                                        Text(LocalizationManager.shared.currentLanguage == .thai ? "จะแตกเป็นวัตถุดิบดิบตอนขาย" : "Expands to raw stock at sale")
                                            .font(.caption2)
                                            .foregroundColor(.textTertiary)
                                    }
                                }

                                Spacer()

                                Text("\(formatted(comp.quantity)) \(comp.quantityUnit)")
                                    .font(.subheadline)
                                    .foregroundColor(.textPrimary)
                                    .frame(width: 90, alignment: .trailing)

                                Text(String(format: "฿%.2f/%@", item?.costPrice ?? 0, item?.unit ?? ""))
                                    .font(.caption)
                                    .foregroundColor(.textSecondary)
                                    .frame(width: 90, alignment: .trailing)

                                Text(String(format: "฿%.2f", compCost))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.textPrimary)
                                    .frame(width: 90, alignment: .trailing)
                            }
                            .padding(.horizontal, APSpacing.md)
                            .padding(.vertical, 7)

                            Divider().background(Color.appDivider.opacity(0.5))
                        }
                    }
                    .background(Color.appSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.appBorderSubtle, lineWidth: 1)
                    )
                }
                .padding(.horizontal, 14)

                // Raw Stock Explosion Diagram
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(LocalizationManager.shared.currentLanguage == .thai ? "การตัดสต็อกอัตโนมัติ" : "Raw Stock Explosion",
                              systemImage: "arrow.triangle.branch")
                            .font(.headline)
                            .foregroundColor(.textPrimary)

                        Spacer()

                        Text(LocalizationManager.shared.currentLanguage == .thai ? "ระบบไม่ตัดสต็อกซ้ำซ้อน" : "No double deduction")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.appAccent.opacity(0.12))
                            .foregroundColor(.appAccent)
                            .clipShape(Capsule())
                    }

                    DisclosureGroup(isExpanded: $showsStockFlow) {
                        VStack(alignment: .leading, spacing: 8) {
                        Text(LocalizationManager.shared.currentLanguage == .thai
                             ? "เมื่อขายเมนูหน้าร้าน ระบบจะคำนวณสัดส่วนและตัดสต็อกไปยังวัตถุดิบจริงทันที:"
                             : "When a dish is sold, raw ingredients are automatically calculated and deducted:")
                            .font(.caption)
                            .foregroundColor(.textSecondary)

                        HStack(spacing: 8) {
                            Text(recipe.name)
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.appSurfaceHigh)
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                            Image(systemName: "arrow.right")
                                .font(.caption.weight(.bold))
                                .foregroundColor(.textTertiary)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(activeComponents) { comp in
                                        HStack(spacing: 4) {
                                            Circle()
                                                .fill(Color.appTeal)
                                                .frame(width: 5, height: 5)
                                            Text(comp.ingredient?.name ?? "")
                                                .font(.caption.weight(.medium))
                                            Text("(\(formatted(comp.quantity)) \(comp.quantityUnit))")
                                                .font(.caption2)
                                                .foregroundColor(.textSecondary)
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 5)
                                        .background(Color.appSurfaceHigh)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                    }
                                }
                            }
                        }
                    }
                    } label: {
                        Label(LocalizationManager.shared.currentLanguage == .thai ? "ดูเส้นทางวัตถุดิบ · \(activeComponents.count) รายการ" : "Ingredient flow · \(activeComponents.count) items", systemImage: "point.3.connected.trianglepath.dotted")
                            .font(.subheadline)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.appSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.appBorderSubtle, lineWidth: 1)
                    )
                }
                .padding(.horizontal, 14)

                // Usage in Sales Dishes
                if !consumingMenuItems.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(LocalizationManager.shared.currentLanguage == .thai ? "เมนูหน้าร้านที่นำสูตรนี้ไปใช้ (\(consumingMenuItems.count))" : "Used in Dishes (\(consumingMenuItems.count))",
                              systemImage: "fork.knife")
                            .font(.headline)
                            .foregroundColor(.textPrimary)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180))], spacing: 8) {
                            ForEach(consumingMenuItems) { menu in
                                HStack(spacing: 8) {
                                    Image(systemName: "fork.knife.circle.fill")
                                        .foregroundColor(.appAccent)
                                    Text(menu.name)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundColor(.textPrimary)
                                        .lineLimit(1)
                                    Spacer()
                                }
                                .padding(10)
                                .background(Color.appSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(Color.appBorderSubtle, lineWidth: 1)
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                }

                // Instructions (if present)
                if let steps = recipe.instructions, !steps.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(LocalizationManager.shared.currentLanguage == .thai ? "ขั้นตอนการเตรียม" : "Preparation Instructions",
                              systemImage: "text.alignleft")
                            .font(.headline)
                            .foregroundColor(.textPrimary)

                        DisclosureGroup(isExpanded: $showsInstructions) {
                            Text(steps)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } label: {
                            Text(steps)
                                .lineLimit(1)
                        }
                            .font(.subheadline)
                            .foregroundColor(.textSecondary)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.appSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.appBorderSubtle, lineWidth: 1)
                            )
                    }
                    .padding(.horizontal, 14)
                }

                Spacer(minLength: 12)
            }
        }
        .background(Color.white)
        .id(recipe.id)
        .monospacedDigit()
        .animation(.easeInOut(duration: 0.25), value: showsStockFlow)
        .animation(.easeInOut(duration: 0.25), value: showsInstructions)
        .task(id: recipe.id) {
            loadConsumingMenuItems()
        }
    }

    /// Fetch only recipe rows related to the selected prep output instead of
    /// retaining every dish recipe and menu item in the catalogue view.
    private func loadConsumingMenuItems() {
        guard let outputID = recipe.outputItem?.id else {
            consumingMenuItems = []
            return
        }

        let descriptor = FetchDescriptor<Recipe>(
            predicate: #Predicate<Recipe> {
                $0.isDeleted == false && $0.inventoryItem?.id == outputID
            }
        )
        let matches = (try? modelContext.fetch(descriptor)) ?? []
        var seen = Set<String>()
        consumingMenuItems = matches.compactMap { row in
            guard let menu = row.menuItem, seen.insert(menu.id).inserted else { return nil }
            return menu
        }
    }

    private func kpiCard(title: String, value: String, subtext: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                Spacer()
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(color)
            }

            Text(value)
                .font(.headline.weight(.bold))
                .monospacedDigit()
                .foregroundColor(.textPrimary)


        }
        .padding(12)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.appBorderSubtle, lineWidth: 1)
        )
    }

    private func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }
}

// MARK: - Native Prep Recipe Editor

private struct PrepRecipeEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \InventoryItem.name) private var inventory: [InventoryItem]
    @Query private var allComponents: [PrepRecipeComponent]
    let recipe: PrepRecipe?

    @State private var name = ""
    @State private var outputItemId: UUID?
    @State private var expectedOutput = ""
    @State private var outputUnit = "g"
    @State private var instructions = ""
    @State private var lines: [Line] = []
    @State private var showingIngredientPicker = false
    @State private var errorMessage = ""

    struct Line: Identifiable {
        let id: UUID
        let ingredient: InventoryItem
        var quantity: String
        var unit: String
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(LocalizationManager.shared.currentLanguage == .thai ? "ผลลัพธ์อ้างอิงของสูตร" : "Formula reference output") {
                    TextField(LocalizationManager.shared.currentLanguage == .thai
                              ? "ชื่อสูตร เช่น ซอสคลุกหมี่, น้ำพริกแคบหมู"
                              : "Recipe name, e.g. Special Sauce", text: $name)
                    Picker(LocalizationManager.shared.currentLanguage == .thai ? "สินค้าผลผลิต" : "Output inventory item", selection: $outputItemId) {
                        Text("—").tag(nil as UUID?)
                        ForEach(inventory.filter { !$0.isDeleted }) { Text($0.name).tag($0.id as UUID?) }
                    }
                    .onChange(of: outputItemId) { _, newId in
                        if recipe == nil, let item = inventory.first(where: { $0.id == newId }), !item.unit.isEmpty {
                            outputUnit = item.unit
                        }
                    }
                    HStack {
                        TextField(LocalizationManager.shared.currentLanguage == .thai ? "ปริมาณผลผลิตอ้างอิง" : "Reference yield", text: $expectedOutput)
                            .keyboardType(.decimalPad)
                        StandardUnitPickerMenu(unit: $outputUnit, suggestedUnit: inventory.first(where: { $0.id == outputItemId })?.unit)
                    }
                }

                Section {
                    ForEach($lines) { $line in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(line.ingredient.name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(.textPrimary)
                                Text(String(format: "฿%.2f/%@", line.ingredient.costPrice, line.ingredient.unit))
                                    .font(.caption).foregroundColor(.textSecondary)
                            }
                            Spacer()
                            TextField("0", text: $line.quantity)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 75)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(Color.appSurfaceHigh)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                            StandardUnitPickerMenu(unit: $line.unit, suggestedUnit: line.ingredient.unit)

                            Button(role: .destructive) { lines.removeAll { $0.id == line.id } } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.appRose)
                                    .font(.title3)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 2)
                    }
                    Button { showingIngredientPicker = true } label: {
                        Label(LocalizationManager.shared.currentLanguage == .thai ? "เพิ่มวัตถุดิบในสูตรเตรียม" : "Add prep ingredient",
                              systemImage: "plus.circle")
                    }
                } header: {
                    Text(LocalizationManager.shared.currentLanguage == .thai ? "วัตถุดิบตามปริมาณอ้างอิง" : "Ingredients for the reference yield")
                } footer: {
                    Text(LocalizationManager.shared.currentLanguage == .thai
                         ? "ใช้ g/ml เป็นหลัก ระบบจะคำนวณและตัดสต็อกวัตถุดิบจริงตามสัดส่วนอัตโนมัติ"
                         : "Prefer g/ml. Raw components are exploded automatically at sale.")
                }

                Section(LocalizationManager.shared.currentLanguage == .thai ? "ขั้นตอนการเตรียม (ไม่บังคับ)" : "Instructions (Optional)") {
                    TextField(LocalizationManager.shared.currentLanguage == .thai ? "ระบุขั้นตอน เช่น ผสมซีอิ๊วกับน้ำมันเจียว..." : "Preparation steps", text: $instructions, axis: .vertical)
                        .lineLimit(3...8)
                }
                if !errorMessage.isEmpty { Text(errorMessage).foregroundColor(.appRose) }
            }
            .navigationTitle(recipe == nil
                             ? (LocalizationManager.shared.currentLanguage == .thai ? "สร้างสูตรเตรียมใหม่" : "New Prep Recipe")
                             : (LocalizationManager.shared.currentLanguage == .thai ? "แก้ไขสูตรเตรียม" : "Edit Prep Recipe"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L.Common.cancel.t) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(L.Common.save.t) { save() }.disabled(!canSave) }
            }
            .onAppear(perform: load)
            .sheet(isPresented: $showingIngredientPicker) {
                NavigationStack {
                    List(inventory.filter { item in
                        !item.isDeleted && item.id != outputItemId && !lines.contains { $0.ingredient.id == item.id }
                    }) { item in
                        Button(item.name) {
                            let defaultUnit = item.unit.isEmpty ? "g" : item.unit
                            lines.append(Line(id: UUID(), ingredient: item, quantity: "1", unit: defaultUnit))
                            showingIngredientPicker = false
                        }
                    }
                    .navigationTitle(LocalizationManager.shared.currentLanguage == .thai ? "เลือกวัตถุดิบ" : "Choose ingredient")
                }
            }
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && outputItemId != nil
        && (Double(expectedOutput) ?? 0) > 0 && !lines.isEmpty
        && lines.allSatisfy { (Double($0.quantity) ?? 0) > 0 }
    }

    private func formatQuantity(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(value))
        } else {
            return String(value)
        }
    }

    private func load() {
        guard let recipe else { return }
        name = recipe.name
        outputItemId = recipe.outputItem?.id
        expectedOutput = formatQuantity(recipe.expectedOutputQuantity)
        outputUnit = recipe.outputUnit
        instructions = recipe.instructions ?? ""

        let components = !recipe.components.isEmpty
            ? recipe.components
            : allComponents.filter { !$0.isDeleted && $0.prepRecipe?.id == recipe.id }

        lines = components.compactMap { component in
            guard !component.isDeleted, let item = component.ingredient else { return nil }
            return Line(
                id: component.id,
                ingredient: item,
                quantity: formatQuantity(component.quantity),
                unit: component.quantityUnit
            )
        }
    }

    private func save() {
        guard canSave, let outputId = outputItemId,
              let output = inventory.first(where: { $0.id == outputId }),
              let yield = Double(expectedOutput) else { return }
        let target = recipe ?? PrepRecipe(name: name, outputItem: output,
            expectedOutputQuantity: yield, outputUnit: outputUnit)
        if recipe == nil { modelContext.insert(target) }
        target.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        target.outputItem = output
        target.expectedOutputQuantity = yield
        target.outputUnit = outputUnit
        target.instructions = instructions.isEmpty ? nil : instructions
        target.updatedAt = Date()
        target.isSynced = false
        for old in target.components { modelContext.delete(old) }
        target.components.removeAll()
        for line in lines {
            guard let quantity = Double(line.quantity) else { continue }
            let component = PrepRecipeComponent(prepRecipe: target, ingredient: line.ingredient,
                quantity: quantity, quantityUnit: line.unit)
            modelContext.insert(component)
            target.components.append(component)
        }
        do { try modelContext.save(); dismiss() } catch { errorMessage = error.localizedDescription }
    }
}
