// InventoryView.swift
// AlphaPos — Premium Inventory Interface v2
// Redesigned for high-volume (200+ items) with pagination, dynamic sorting,
// debounced search, color-coded stock bars, and bulk operations.

import SwiftUI
import SwiftData
import Combine

// MARK: - Main Inventory View

struct InventoryView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var lm: LocalizationManager
    @Query(sort: \InventoryItem.name) private var inventory: [InventoryItem]
    @Query(sort: \InventoryTransaction.updatedAt, order: .reverse) private var transactions: [InventoryTransaction]
    @Query(sort: \Branch.name) private var branches: [Branch]

    @State private var viewModel = InventoryViewModel()
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var selectedSection = 0 // 0: Raw Materials, 1: Products, 2: Recipes & BOM, 3: Suppliers, 4: Stock Audit, 5: Expenses
    @State private var showingEditSheet = false
    @State private var showingMovementHistory = false
    @State private var showingAddSheet = false
    @State private var showingReturnSheet = false

    // Multi-Branch and sheets states
    @AppStorage("active_branch_id") private var activeBranchId = ""
    @State private var showingBranchManager = false
    @State private var showingPOManager = false
    @State private var showingTransferSheet = false
    @State private var showingDocumentScanner = false

    // High-Volume filters state
    @State private var statusFilter = "All" // "All", "Low Stock", "Out of Stock"
    @State private var selectedCategory = "All"
    @State private var isAnimatedIn = false

    // NEW: Dynamic sorting
    @State private var sortKey: InventorySortKey = .name
    @State private var sortAscending = true

    // NEW: Pagination
    @State private var displayedItemCount = 50
    private let pageSize = 50

    // NEW: View mode toggle
    @State private var viewMode: InventoryViewMode = .table

    // NEW: Bulk selection
    @State private var isSelectionMode = false
    @State private var selectedItems: Set<UUID> = []
    @State private var showingBulkReceiveSheet = false
    @State private var showingBulkWasteSheet = false
    @State private var showingBulkDeleteAlert = false

    // Category Management
    @State private var showingCategoryManager = false
    @State private var showingBulkAssignCategory = false

    // ABC Classification (computed on data change)
    @State private var abcClassification: [UUID: String] = [:]

    // Debounce timer
    @State private var searchDebounceTask: Task<Void, Never>?

    // MARK: - Computed Properties

    private var activeBranch: Branch? {
        branches.first(where: { $0.id.uuidString == activeBranchId })
    }

    /// Pre-filters by branch and isDeleted (fast, SwiftData-backed)
    private var branchInventory: [InventoryItem] {
        let activeItems = inventory.filter { !$0.isDeleted }
        if let branch = activeBranch {
            return activeItems.filter { $0.branch?.id == branch.id }
        }
        return activeItems
    }

    /// Main filtered + sorted + paginated list
    private var filteredInventory: [InventoryItem] {
        var result = branchInventory

        // 1. Search using debounced text
        if !debouncedSearchText.isEmpty {
            let query = debouncedSearchText.lowercased()
            result = result.filter {
                $0.name.lowercased().contains(query) ||
                ($0.sku ?? "").lowercased().contains(query) ||
                ($0.barcode ?? "").lowercased().contains(query)
            }
        }

        // 2. Status filter
        switch statusFilter {
        case "Low Stock":
            result = result.filter { $0.currentQuantity > 0 && $0.currentQuantity <= $0.reorderLevel }
        case "Out of Stock":
            result = result.filter { $0.currentQuantity <= 0.0 }
        default:
            break
        }

        // 3. Category filter
        if selectedCategory != "All" {
            if selectedCategory == "ไม่ระบุหมวดหมู่" {
                result = result.filter { $0.category == nil || $0.category?.isEmpty == true }
            } else {
                result = result.filter { $0.category == selectedCategory }
            }
        }

        // 4. Sorting
        result = sortItems(result)

        return result
    }

    /// Paginated slice of filteredInventory
    private var paginatedInventory: [InventoryItem] {
        Array(filteredInventory.prefix(displayedItemCount))
    }

    private var hasMoreItems: Bool {
        displayedItemCount < filteredInventory.count
    }

    private var filteredTransactionsList: [InventoryTransaction] {
        let activeTransactions = transactions.filter { !$0.isDeleted }
        if let branch = activeBranch {
            return activeTransactions.filter { $0.branch?.id == branch.id }
        }
        return activeTransactions
    }

    // Stats
    private var lowStockCount: Int {
        branchInventory.filter { $0.currentQuantity > 0 && $0.currentQuantity <= $0.reorderLevel }.count
    }
    private var outOfStockCount: Int {
        branchInventory.filter { $0.currentQuantity <= 0.0 }.count
    }

    // Category item counts for chip display
    private var categoryItemCounts: [String: Int] {
        var counts: [String: Int] = [:]
        for item in branchInventory {
            let cat = item.category ?? "ไม่ระบุหมวดหมู่"
            counts[cat, default: 0] += 1
        }
        return counts
    }

    // Available categories list
    private var availableCategories: [String] {
        Array(Set(branchInventory.compactMap { $0.category })).sorted()
    }

    // MARK: - Body

    var body: some View {
        inventorySheetsAndAlerts(content: content)
            .navigationTitle("inventory_title".t)
            .apNavBar(background: Color.appBackground)
            .toolbar { toolbarContent }
            .onAppear {
                viewModel.modelContext = modelContext
                viewModel.seedDefaultBranchIfNeeded()
                recalculateABC()
                withAnimation(.easeOut(duration: 0.4)) {
                    isAnimatedIn = true
                }
            }
            .onChange(of: searchText) { _, newValue in
                debounceSearch(newValue)
            }
            .onChange(of: statusFilter) { _, _ in resetPagination() }
            .onChange(of: selectedCategory) { _, _ in resetPagination() }
            .onChange(of: sortKey) { _, _ in resetPagination() }
            .onChange(of: sortAscending) { _, _ in resetPagination() }
    }

    @ViewBuilder
    private func inventorySheetsAndAlerts(content: some View) -> some View {
        content
            .sheet(item: $viewModel.selectedItem) { item in
                sheetContent(for: item)
            }
            .sheet(isPresented: $showingAddSheet) {
                AddStockItemView(viewModel: viewModel, activeBranch: activeBranch) {
                    showingAddSheet = false
                }
            }
            .sheet(isPresented: $showingBranchManager) {
                BranchManagerView()
            }
            .sheet(isPresented: $showingPOManager) {
                if let active = activeBranch {
                    PurchaseOrderManagerView(activeBranch: active)
                }
            }
            .sheet(isPresented: $showingTransferSheet) {
                if let active = activeBranch {
                    StockTransferSheet(sourceBranch: active)
                }
            }
            .sheet(isPresented: $showingBulkReceiveSheet) {
                BulkReceiveSheet(items: selectedItemObjects, viewModel: viewModel) {
                    showingBulkReceiveSheet = false
                    exitSelectionMode()
                }
            }
            .sheet(isPresented: $showingBulkWasteSheet) {
                BulkWasteSheet(items: selectedItemObjects, viewModel: viewModel) {
                    showingBulkWasteSheet = false
                    exitSelectionMode()
                }
            }
            .sheet(isPresented: $showingDocumentScanner) {
                StockDocumentScanSheet {
                    showingDocumentScanner = false
                }
            }
            .sheet(isPresented: $showingCategoryManager) {
                ManageCategoriesSheet()
            }
            .sheet(isPresented: $showingBulkAssignCategory) {
                BulkAssignCategorySheet(
                    selectedItemIds: selectedItems,
                    onComplete: {
                        exitSelectionMode()
                    }
                )
            }
            .alert("bulk_delete_alert_title".t, isPresented: $showingBulkDeleteAlert) {
                Button("cancel_btn".t, role: .cancel) { }
                Button("delete_btn".t, role: .destructive) {
                    for item in selectedItemObjects {
                        viewModel.deleteInventoryItem(item: item)
                    }
                    exitSelectionMode()
                }
            } message: {
                Text(LocalizationManager.shared.t("bulk_delete_confirm_message", selectedItems.count))
            }
    }

    private var content: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                sectionPicker

                Divider().background(Color.appDivider)

                sectionContent
            }
            .animation(.easeInOut(duration: 0.22), value: selectedSection)
        }
    }

    private var sectionPicker: some View {
        Picker("Inventory Menu", selection: $selectedSection) {
            Text("inventory_raw_materials".t).tag(0)
            Text("inventory_products".t).tag(1)
            Text("inventory_recipes".t).tag(2)
            Text("inventory_suppliers".t).tag(3)
            Text("inventory_stock_audit".t).tag(4)
            Text("inventory_expenses".t).tag(5)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, APSpacing.md)
        .padding(.vertical, APSpacing.sm)
        .background(Color.appSurface)
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch selectedSection {
        case 0:
            if branchInventory.isEmpty {
                emptyState
            } else {
                HStack(spacing: 0) {
                    inventoryPanel
                    transactionPanel
                }
            }
        case 1:
            CatalogManagerView()
        case 2:
            RecipeCatalogView()
        case 3:
            SupplierManagerView()
        case 4:
            StockAuditView()
        case 5:
            ExpenseTrackerView()
        default:
            EmptyView()
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            HStack(spacing: APSpacing.md) {
                // Branch Selector
                if let active = activeBranch {
                    Menu {
                        ForEach(branches) { b in
                            Button(action: { activeBranchId = b.id.uuidString }) {
                                HStack {
                                    Text(b.name)
                                    if b.id.uuidString == activeBranchId {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                        Divider()
                        Button("manage_branches".t) {
                            showingBranchManager = true
                        }
                    } label: {
                        Label(active.name, systemImage: "building.2")
                            .foregroundColor(.appTeal)
                    }
                } else {
                    Button("manage_branches".t) {
                        showingBranchManager = true
                    }
                    .foregroundColor(.appTeal)
                }

                // Stock Transfer
                if selectedSection == 0 && activeBranch != nil && branches.count > 1 {
                    Button(action: { showingTransferSheet = true }) {
                        Label("transfer_stock".t, systemImage: "arrow.left.arrow.right")
                            .foregroundColor(.appTeal)
                    }
                }

                // Add Material
                if selectedSection == 0 && activeBranch != nil {
                    Button(action: { showingAddSheet = true }) {
                        Label("add_raw_material".t, systemImage: "plus")
                            .foregroundColor(.appTeal)
                    }
                }

                // PO Manager
                if selectedSection == 0 && activeBranch != nil {
                    Button(action: { showingPOManager = true }) {
                        Label("purchase_orders".t, systemImage: "doc.text")
                            .foregroundColor(.appTeal)
                    }
                }
                
                // Manage Categories Button
                if selectedSection == 0 && activeBranch != nil {
                    Button(action: { showingCategoryManager = true }) {
                        Label("จัดการหมวดหมู่", systemImage: "tag")
                            .foregroundColor(.appTeal)
                    }
                }
                
                // AI Receipt Scanner
                if selectedSection == 0 && activeBranch != nil {
                    Button(action: { showingDocumentScanner = true }) {
                        Label("stock_scan_title".t, systemImage: "sparkles.rectangle.stack")
                            .foregroundColor(.appTeal)
                    }
                }
            }
        }
    }

    // MARK: - Sheet Router

    @ViewBuilder
    private func sheetContent(for item: InventoryItem) -> some View {
        if viewModel.showingReceiveSheet {
            ReceiveStockView(item: item, viewModel: viewModel) {
                viewModel.showingReceiveSheet = false
                viewModel.selectedItem = nil
            }
        } else if viewModel.showingWasteSheet {
            WasteStockView(item: item, viewModel: viewModel) {
                viewModel.showingWasteSheet = false
                viewModel.selectedItem = nil
            }
        } else if showingReturnSheet {
            ReturnSupplierStockView(item: item, viewModel: viewModel) {
                showingReturnSheet = false
                viewModel.selectedItem = nil
            }
        } else if showingEditSheet {
            EditStockItemView(item: item, viewModel: viewModel) {
                showingEditSheet = false
                viewModel.selectedItem = nil
            }
        } else if showingMovementHistory {
            ItemMovementHistorySheet(item: item) {
                showingMovementHistory = false
                viewModel.selectedItem = nil
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: APSpacing.lg) {
            ZStack {
                Circle().fill(Color.appSurface).frame(width: 100, height: 100)
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(APGradient.accent)
            }
            Text("inventory_empty_title".t)
                .font(.title2).fontWeight(.bold).foregroundColor(.textPrimary)
            Text("inventory_empty_subtitle".t)
                .font(.subheadline).foregroundColor(.textSecondary)
                .multilineTextAlignment(.center).frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Inventory Panel (Left)

    private var inventoryPanel: some View {
        VStack(spacing: 0) {
            // Stats header
            inventoryStatsHeader

            Divider().background(Color.appDivider)

            // Search bar with debounce
            searchBar

            // Filters & Sort controls
            filtersSection

            // Bulk action bar (when in selection mode)
            if isSelectionMode {
                bulkActionBar
            }

            // Item list with pagination
            if !isAnimatedIn {
                skeletonLoading
            } else if filteredInventory.isEmpty {
                filteredEmptyState
            } else {
                itemListView
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color.appBackground)
    }

    // MARK: - Stats Header

    private var inventoryStatsHeader: some View {
        HStack(spacing: APSpacing.md) {
            statCard(title: "total_items".t, value: "\(branchInventory.count)", icon: "shippingbox.fill", color: Color.appAccent)
            statCard(title: "filter_low_stock".t, value: "\(lowStockCount)", icon: "exclamationmark.triangle.fill", color: .appRose)
            statCard(title: "transactions".t, value: "\(filteredTransactionsList.count)", icon: "arrow.left.and.right.circle.fill", color: .appTeal)
        }
        .padding(APSpacing.md)
        .background(Color.appSurface)
    }

    private func statCard(title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: APSpacing.sm) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.headline).fontWeight(.bold)
                    .foregroundColor(.textPrimary)
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.textSecondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appSurfaceHigh)
        .clipShape(RoundedRectangle(cornerRadius: APRadius.sm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: APRadius.sm, style: .continuous)
                .stroke(Color.appBorderSubtle, lineWidth: 1)
        )
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: APSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.textSecondary)
                .font(.subheadline)
            TextField("search_placeholder".t, text: $searchText)
                .font(.subheadline)
                .foregroundColor(.textPrimary)
                .tint(.appAccent)
            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                    debouncedSearchText = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.textSecondary)
                }
            }
        }
        .padding(.horizontal, APSpacing.md)
        .padding(.vertical, 8)
        .background(Color.appSurfaceHigh)
        .cornerRadius(APRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: APRadius.md)
                .stroke(Color.appBorderSubtle, lineWidth: 1)
        )
        .padding(.horizontal, APSpacing.md)
        .padding(.vertical, APSpacing.sm)
        .background(Color.appBackground)
    }

    // MARK: - Filters Section

    private var filtersSection: some View {
        VStack(spacing: APSpacing.sm) {
            // Row 1: Status filters + View mode + Select toggle
            HStack(spacing: APSpacing.xs) {
                statusFilterButton(title: "filter_all".t, tag: "All", count: branchInventory.count)
                statusFilterButton(
                    title: "filter_low_stock".t,
                    tag: "Low Stock",
                    count: lowStockCount,
                    color: .appRose
                )
                statusFilterButton(
                    title: "filter_out_of_stock".t,
                    tag: "Out of Stock",
                    count: outOfStockCount,
                    color: .textSecondary
                )

                Spacer()

                // View mode toggle
                Button(action: { viewMode = viewMode == .table ? .card : .table }) {
                    Image(systemName: viewMode == .table ? "list.bullet" : "square.grid.2x2")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(Color.appSurfaceHigh)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)

                // Bulk select toggle
                Button(action: { toggleSelectionMode() }) {
                    Image(systemName: isSelectionMode ? "checkmark.circle.fill" : "checkmark.circle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(isSelectionMode ? .appTeal : .textSecondary)
                        .frame(width: 30, height: 30)
                        .background(isSelectionMode ? Color.appTeal.opacity(0.12) : Color.appSurfaceHigh)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, APSpacing.md)

            // Row 2: Sort control
            HStack(spacing: APSpacing.sm) {
                // Sort picker
                Menu {
                    ForEach(InventorySortKey.allCases, id: \.self) { key in
                        Button(action: {
                            if sortKey == key {
                                sortAscending.toggle()
                            } else {
                                sortKey = key
                                sortAscending = true
                            }
                        }) {
                            HStack {
                                Text(key.displayName)
                                if sortKey == key {
                                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.arrow.down")
                        Text(sortKey.displayName)
                        Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                    }
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.appSurfaceHigh)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(Color.appBorderSubtle, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                // Results count
                Text(LocalizationManager.shared.t("items_count_template", filteredInventory.count))
                    .font(.caption2)
                    .foregroundColor(.textTertiary)

                Spacer()
            }
            .padding(.horizontal, APSpacing.md)

            // Row 3: Category filter (only if categories exist)
            if !availableCategories.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: APSpacing.xs) {
                        categoryChip(name: "ทั้งหมด", icon: "📋", count: branchInventory.count, isSelected: selectedCategory == "All") {
                            selectedCategory = "All"
                        }
                        ForEach(availableCategories, id: \.self) { cat in
                            categoryChip(
                                name: cat,
                                icon: InventoryCategory.icon(for: cat),
                                count: categoryItemCounts[cat] ?? 0,
                                isSelected: selectedCategory == cat
                            ) {
                                selectedCategory = cat
                            }
                        }
                        // Uncategorized
                        if let uncatCount = categoryItemCounts["ไม่ระบุหมวดหมู่"], uncatCount > 0 {
                            categoryChip(name: "ไม่ระบุหมวดหมู่", icon: "❓", count: uncatCount, isSelected: selectedCategory == "ไม่ระบุหมวดหมู่") {
                                selectedCategory = "ไม่ระบุหมวดหมู่"
                            }
                        }
                    }
                    .padding(.horizontal, APSpacing.md)
                }
                .padding(.vertical, APSpacing.xs)
            }
        }
        .padding(.vertical, 6)
        .background(Color.appBackground)
        .overlay(Rectangle().fill(Color.appDivider).frame(height: 1), alignment: .bottom)
    }

    // MARK: - Bulk Action Bar

    private var bulkActionBar: some View {
        HStack(spacing: APSpacing.md) {
            Text(LocalizationManager.shared.t("items_selected_count", selectedItems.count))
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.textPrimary)

            Spacer()

            // Select all
            Button(action: { selectAll() }) {
                Label("select_all".t, systemImage: "checkmark.circle")
                    .font(.caption).fontWeight(.semibold)
                    .foregroundColor(.appTeal)
            }
            .buttonStyle(.plain)

            // Bulk receive
            Button(action: { showingBulkReceiveSheet = true }) {
                Label("inventory_receive".t, systemImage: "plus.circle.fill")
                    .font(.caption).fontWeight(.semibold)
                    .foregroundColor(.appTeal)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.appTeal.opacity(0.12))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(selectedItems.isEmpty)

            // Bulk waste
            Button(action: { showingBulkWasteSheet = true }) {
                Label("inventory_waste".t, systemImage: "minus.circle.fill")
                    .font(.caption).fontWeight(.semibold)
                    .foregroundColor(.appRose)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.appRose.opacity(0.12))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(selectedItems.isEmpty)

            // Bulk delete
            Button(action: { showingBulkDeleteAlert = true }) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.appRose)
                    .frame(width: 28, height: 28)
                    .background(Color.appRose.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(selectedItems.isEmpty)
        }
        .padding(.horizontal, APSpacing.md)
        .padding(.vertical, 8)
        .background(Color.appTeal.opacity(0.05))
        .overlay(Rectangle().fill(Color.appTeal.opacity(0.3)).frame(height: 1), alignment: .bottom)
    }

    // MARK: - Item List View (Paginated)

    private var itemListView: some View {
        ScrollView {
            LazyVStack(spacing: viewMode == .table ? 0 : APSpacing.sm, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(paginatedInventory) { item in
                        itemRow(for: item)
                    }

                    // Load More / Infinite scroll trigger
                    if hasMoreItems {
                        loadMoreButton
                    }
                } header: {
                    if viewMode == .table {
                        InventoryListHeader(
                            resultCount: filteredInventory.count,
                            sortKey: $sortKey,
                            sortAscending: $sortAscending
                        )
                    }
                }
            }
            .padding(.horizontal, APSpacing.md)
            .padding(.bottom, APSpacing.md)
        }
        .transition(.opacity)
    }

    @ViewBuilder
    private func itemRow(for item: InventoryItem) -> some View {
        if viewMode == .table {
            HStack(spacing: 0) {
                // Selection checkbox
                if isSelectionMode {
                    Button(action: { toggleSelection(item) }) {
                        Image(systemName: selectedItems.contains(item.id) ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 18))
                            .foregroundColor(selectedItems.contains(item.id) ? .appTeal : .textTertiary)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 8)
                }

                InventoryItemTableRow(item: item, abcClass: abcClassification[item.id]) {
                    viewModel.selectedItem = item
                    viewModel.showingReceiveSheet = true
                } onWaste: {
                    viewModel.selectedItem = item
                    viewModel.showingWasteSheet = true
                } onReturn: {
                    viewModel.selectedItem = item
                    showingReturnSheet = true
                } onEdit: {
                    viewModel.selectedItem = item
                    showingEditSheet = true
                } onHistory: {
                    viewModel.selectedItem = item
                    showingMovementHistory = true
                }
            }
        } else {
            HStack(spacing: 0) {
                if isSelectionMode {
                    Button(action: { toggleSelection(item) }) {
                        Image(systemName: selectedItems.contains(item.id) ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 18))
                            .foregroundColor(selectedItems.contains(item.id) ? .appTeal : .textTertiary)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 8)
                }

                InventoryItemCard(item: item) {
                    viewModel.selectedItem = item
                    viewModel.showingReceiveSheet = true
                } onWaste: {
                    viewModel.selectedItem = item
                    viewModel.showingWasteSheet = true
                } onReturn: {
                    viewModel.selectedItem = item
                    showingReturnSheet = true
                } onEdit: {
                    viewModel.selectedItem = item
                    showingEditSheet = true
                } onHistory: {
                    viewModel.selectedItem = item
                    showingMovementHistory = true
                }
            }
        }
    }

    // MARK: - Load More

    private var loadMoreButton: some View {
        Button(action: { loadMore() }) {
            HStack(spacing: APSpacing.sm) {
                Image(systemName: "arrow.down.circle")
                    .font(.subheadline)
                Text(LocalizationManager.shared.t("load_more_items", min(pageSize, filteredInventory.count - displayedItemCount)))
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.appTeal)
            .frame(maxWidth: .infinity)
            .padding(APSpacing.md)
            .background(Color.appTeal.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: APRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: APRadius.md, style: .continuous)
                    .stroke(Color.appTeal.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.top, APSpacing.sm)
        .onAppear {
            // Auto-load more when user scrolls to the bottom (infinite scroll)
            loadMore()
        }
    }

    // MARK: - Skeleton Loading

    private var skeletonLoading: some View {
        VStack(spacing: APSpacing.sm) {
            ForEach(0..<6, id: \.self) { _ in
                Color.appSurfaceHigh
                    .cornerRadius(APRadius.sm)
                    .frame(height: 52)
            }
        }
        .padding(APSpacing.md)
        .redacted(reason: .placeholder)
        .transition(.opacity)
    }

    // MARK: - Filtered Empty State

    private var filteredEmptyState: some View {
        VStack(spacing: APSpacing.sm) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 34, weight: .semibold))
                .foregroundColor(.textTertiary)
            Text("no_search_results".t)
                .font(.headline)
                .foregroundColor(.textPrimary)
            Text("try_adjust_filters".t)
                .font(.caption)
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
    }

    // MARK: - Transaction Panel (Right)

    private var transactionPanel: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("transaction_log".t)
                        .font(.headline).fontWeight(.bold)
                        .foregroundColor(.textPrimary)
                    Text(LocalizationManager.shared.t("last_entries_template", min(filteredTransactionsList.count, 30)))
                        .font(.caption2)
                        .foregroundColor(.textSecondary)
                }
                Spacer()
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundColor(.textSecondary)
            }
            .padding(APSpacing.md)
            .background(Color.appSurface)

            Divider().background(Color.appDivider)

            if filteredTransactionsList.isEmpty {
                VStack(spacing: APSpacing.md) {
                    Image(systemName: "tray.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.textTertiary)
                    Text("no_transactions_yet".t)
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.appBackground)
            } else {
                ScrollView {
                    LazyVStack(spacing: APSpacing.sm) {
                        ForEach(Array(filteredTransactionsList.prefix(30))) { txn in
                            TransactionLogRow(txn: txn)
                        }
                    }
                    .padding(APSpacing.md)
                }
                .background(Color.appBackground)
            }
        }
        .frame(width: 360)
        .overlay(Rectangle().fill(Color.appDivider).frame(width: 1), alignment: .leading)
    }

    // MARK: - Helper Methods

    private func statusFilterButton(title: String, tag: String, count: Int, color: Color = .appAccent) -> some View {
        Button(action: { statusFilter = tag }) {
            HStack(spacing: 4) {
                Text(title)
                Text("(\(count))")
                    .font(.system(size: 10))
                    .foregroundColor(statusFilter == tag ? .white : .textTertiary)
            }
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(statusFilter == tag ? color : Color.appSurfaceHigh)
            .foregroundColor(statusFilter == tag ? .white : .textSecondary)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(statusFilter == tag ? Color.clear : Color.appBorderSubtle, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func sortItems(_ items: [InventoryItem]) -> [InventoryItem] {
        items.sorted { a, b in
            let result: Bool
            switch sortKey {
            case .name:
                result = a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            case .quantity:
                result = a.currentQuantity < b.currentQuantity
            case .cost:
                result = a.costPrice < b.costPrice
            case .updated:
                result = a.updatedAt < b.updatedAt
            }
            return sortAscending ? result : !result
        }
    }

    private func debounceSearch(_ query: String) {
        searchDebounceTask?.cancel()
        searchDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
            guard !Task.isCancelled else { return }
            await MainActor.run {
                debouncedSearchText = query
                resetPagination()
            }
        }
    }

    private func resetPagination() {
        displayedItemCount = pageSize
    }

    private func loadMore() {
        displayedItemCount = min(displayedItemCount + pageSize, filteredInventory.count)
    }

    private func toggleSelectionMode() {
        isSelectionMode.toggle()
        if !isSelectionMode {
            selectedItems.removeAll()
        }
    }

    private func exitSelectionMode() {
        isSelectionMode = false
        selectedItems.removeAll()
    }

    private func toggleSelection(_ item: InventoryItem) {
        if selectedItems.contains(item.id) {
            selectedItems.remove(item.id)
        } else {
            selectedItems.insert(item.id)
        }
    }

    private func selectAll() {
        for item in paginatedInventory {
            selectedItems.insert(item.id)
        }
    }

    private var selectedItemObjects: [InventoryItem] {
        paginatedInventory.filter { selectedItems.contains($0.id) }
    }

    // MARK: - Category Chip Helper
    @ViewBuilder
    private func categoryChip(name: String, icon: String, count: Int, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(icon)
                    .font(.system(size: 12))
                Text(name)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                Text("\(count)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(isSelected ? .white.opacity(0.9) : .secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(isSelected ? Color.white.opacity(0.2) : Color.secondary.opacity(0.1))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Color.appTeal : Color.appSurface)
            .foregroundColor(isSelected ? .white : .primary)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.clear : Color.appDivider, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - ABC Recalculation
    private func recalculateABC() {
        let items = branchInventory
        guard !items.isEmpty else { return }
        
        // Calculate value: costPrice × currentQuantity
        let itemValues = items.map { (id: $0.id, value: $0.costPrice * max($0.currentQuantity, 0)) }
        let sorted = itemValues.sorted { $0.value > $1.value }
        let totalValue = sorted.reduce(0.0) { $0 + $1.value }
        
        guard totalValue > 0 else {
            abcClassification = Dictionary(uniqueKeysWithValues: items.map { ($0.id, "C") })
            return
        }
        
        var cumulative = 0.0
        var result: [UUID: String] = [:]
        
        for item in sorted {
            cumulative += item.value
            let pct = cumulative / totalValue
            if pct <= 0.70 {
                result[item.id] = "A"
            } else if pct <= 0.90 {
                result[item.id] = "B"
            } else {
                result[item.id] = "C"
            }
        }
        
        abcClassification = result
    }

    // MARK: - Auto-Assign Categories
    private func autoAssignAllCategories() {
        let mgr = InventoryCategoryManager()
        mgr.modelContext = modelContext
        mgr.autoAssignCategories(items: branchInventory)
        recalculateABC()
    }
}

// MARK: - Supporting Types

enum InventoryViewMode: String {
    case table, card
}

// MARK: - Dense Inventory Table Header (with sortable columns)

private struct InventoryListHeader: View {
    let resultCount: Int
    @Binding var sortKey: InventorySortKey
    @Binding var sortAscending: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                sortableColumn("item_header".t, key: .name, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("category_location_header".t)
                    .frame(width: 150, alignment: .leading)
                sortableColumn("on_hand_label".t, key: .quantity, alignment: .trailing)
                    .frame(width: 130, alignment: .trailing)
                sortableColumn("reorder_cost_header".t, key: .cost, alignment: .trailing)
                    .frame(width: 150, alignment: .trailing)
                Text("status_label".t)
                    .frame(width: 100, alignment: .center)
                Text("actions_header".t)
                    .frame(width: 132, alignment: .trailing)
            }
            .font(.caption2.weight(.bold))
            .foregroundColor(.textSecondary)
            .textCase(.uppercase)
            .padding(.horizontal, APSpacing.md)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .background(Color.appSurface)

            Divider().background(Color.appDivider)
        }
    }

    private func sortableColumn(_ title: String, key: InventorySortKey, alignment: Alignment) -> some View {
        Button(action: {
            if sortKey == key {
                sortAscending.toggle()
            } else {
                sortKey = key
                sortAscending = true
            }
        }) {
            HStack(spacing: 3) {
                Text(title)
                if sortKey == key {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.appTeal)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Inventory Table Row (with color-coded stock bar)

private struct InventoryItemTableRow: View {
    let item: InventoryItem
    var abcClass: String? = nil
    let onReceive: () -> Void
    let onWaste: () -> Void
    let onReturn: () -> Void
    let onEdit: () -> Void
    let onHistory: () -> Void

    private var isOut: Bool { item.currentQuantity <= 0 }
    private var isLow: Bool { !isOut && item.currentQuantity <= item.reorderLevel }
    private var statusText: String {
        if isOut { return "filter_out_of_stock".t }
        if isLow { return "filter_low_stock".t }
        return "stock_ok".t
    }
    private var statusColor: Color {
        if isOut { return .textSecondary }
        if isLow { return .appRose }
        return .appTeal
    }

    /// Color-coded fill ratio:
    /// Red: <25% of capacity (reorderLevel × 3)
    /// Yellow: 25-50% of capacity
    /// Green: >50% of capacity
    private var fillRatio: Double {
        guard item.reorderLevel > 0 else { return 1.0 }
        let capacity = item.reorderLevel * 3.0
        return min(max(item.currentQuantity / capacity, 0.0), 1.0)
    }

    private var stockBarColor: Color {
        if fillRatio < 0.25 { return .appRose }
        if fillRatio < 0.50 { return .appAmber }
        return .appTeal
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Item name + SKU column
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                    if let abc = abcClass {
                        Text(abc)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(abc == "A" ? Color.red.opacity(0.8) : abc == "B" ? Color.orange.opacity(0.8) : Color.green.opacity(0.8))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    HStack(spacing: 6) {
                        Text(item.sku ?? "N/A")
                        if let barcode = item.barcode, !barcode.isEmpty {
                            Text("•")
                            Text(barcode)
                        }
                    }
                    .font(.caption2)
                    .foregroundColor(.textSecondary)
                    .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Category + Location
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.category ?? "uncategorized".t)
                        .font(.caption.weight(.medium))
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                    Text(item.storageLocation ?? "no_location".t)
                        .font(.caption2)
                        .foregroundColor(.textSecondary)
                        .lineLimit(1)
                }
                .frame(width: 150, alignment: .leading)

                // On Hand + mini stock bar
                VStack(alignment: .trailing, spacing: 4) {
                    Text(String(format: "%.1f %@", item.currentQuantity, item.unit))
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(isLow || isOut ? .appRose : .textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    // Mini color-coded stock bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.appSurfaceHigh)
                                .frame(height: 3)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(stockBarColor)
                                .frame(width: geo.size.width * fillRatio, height: 3)
                        }
                    }
                    .frame(width: 60, height: 3)
                }
                .frame(width: 130, alignment: .trailing)

                // Reorder + Cost
                VStack(alignment: .trailing, spacing: 3) {
                    Text(LocalizationManager.shared.t("reorder_at_template", Int(item.reorderLevel), item.unit))
                        .font(.caption2)
                        .foregroundColor(.textSecondary)
                        .lineLimit(1)
                    Text(String(format: "฿%.2f/%@", item.costPrice, item.unit))
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                }
                .frame(width: 150, alignment: .trailing)

                // Status badge
                APBadge(text: statusText, color: statusColor)
                    .frame(width: 100, alignment: .center)

                // Actions
                HStack(spacing: 6) {
                    iconAction("inventory_receive".t, "plus.circle.fill", .appTeal, onReceive)
                    iconAction("inventory_waste".t, "minus.circle.fill", .appRose, onWaste)
                    Menu {
                        Button(action: onReturn) { Label("return_to_supplier".t, systemImage: "arrow.uturn.left.circle") }
                        Button(action: onEdit) { Label("edit_details".t, systemImage: "pencil") }
                        Button(action: onHistory) { Label("movement_history".t, systemImage: "clock.arrow.circlepath") }
                    } label: {
                        Image(systemName: "ellipsis.circle.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.textPrimary)
                            .frame(width: 32, height: 32)
                            .background(Color.appSurfaceHigh)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .help("more_actions".t)
                }
                .frame(width: 132, alignment: .trailing)
            }
            .padding(.horizontal, APSpacing.md)
            .frame(minHeight: 64)
            .background(Color.appSurface)
            .overlay(Divider().background(Color.appDivider), alignment: .bottom)
        }
    }

    private func iconAction(_ title: String, _ icon: String, _ color: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(title)
    }
}

// MARK: - Inventory Item Card (with color-coded stock bar)

private struct InventoryItemCard: View {
    let item: InventoryItem
    let onReceive: () -> Void
    let onWaste: () -> Void
    let onReturn: () -> Void
    let onEdit: () -> Void
    let onHistory: () -> Void

    private var isLow: Bool { item.currentQuantity <= item.reorderLevel }
    private var isOut: Bool { item.currentQuantity <= 0 }

    private var fillRatio: Double {
        guard item.reorderLevel > 0 else { return 1.0 }
        let capacity = item.reorderLevel * 3.0
        return min(max(item.currentQuantity / capacity, 0.0), 1.0)
    }

    private var stockBarColor: Color {
        if fillRatio < 0.25 { return .appRose }
        if fillRatio < 0.50 { return .appAmber }
        return .appTeal
    }

    private var stockBarGradient: LinearGradient {
        if fillRatio < 0.25 { return APGradient.destructive }
        if fillRatio < 0.50 { return APGradient.warning }
        return APGradient.positive
    }

    var body: some View {
        VStack(spacing: APSpacing.sm) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(item.name)
                            .font(.subheadline).fontWeight(.semibold)
                            .foregroundColor(.textPrimary)
                        if isOut {
                            APBadge(text: "filter_out_of_stock".t, color: .textSecondary, icon: "xmark.circle.fill")
                        } else if isLow {
                            APBadge(text: "filter_low_stock".t, color: .appRose, icon: "exclamationmark.triangle.fill")
                        }
                    }
                    HStack(spacing: 6) {
                        Text("SKU: \(item.sku ?? "N/A")")
                        Text("·")
                        Text("฿\(String(format: "%.2f", item.costPrice))/\(item.unit)")
                        if let cat = item.category {
                            Text("·")
                            Text(cat)
                                .foregroundColor(.appTeal)
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                }

                Spacer()

                Text(String(format: "%.1f %@", item.currentQuantity, item.unit))
                    .font(.headline).fontWeight(.bold)
                    .foregroundColor(isLow || isOut ? .appRose : .textPrimary)
            }

            // Color-coded stock level bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.appSurfaceHigh)
                        .frame(height: 5)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(stockBarGradient)
                        .frame(width: geo.size.width * fillRatio, height: 5)
                }
            }
            .frame(height: 5)

            HStack(spacing: APSpacing.sm) {
                Text(LocalizationManager.shared.t("reorder_at_template", Int(item.reorderLevel), item.unit))
                    .font(.caption2)
                    .foregroundColor(.textSecondary)
                Spacer()

                Button(action: onReceive) {
                    Label("inventory_receive".t, systemImage: "plus.circle.fill")
                        .font(.caption).fontWeight(.semibold)
                        .foregroundColor(.appTeal)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.appTeal.opacity(0.12))
                        .clipShape(Capsule())
                }

                Button(action: onWaste) {
                    Label("inventory_waste".t, systemImage: "minus.circle.fill")
                        .font(.caption).fontWeight(.semibold)
                        .foregroundColor(.appRose)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.appRose.opacity(0.12))
                        .clipShape(Capsule())
                }

                Menu {
                    Button(action: onReturn) {
                        Label("return_to_supplier".t, systemImage: "arrow.uturn.left.circle")
                    }
                    Button(action: onEdit) {
                        Label("edit_details".t, systemImage: "pencil")
                    }
                    Button(action: onHistory) {
                        Label("movement_history".t, systemImage: "clock.arrow.circlepath")
                    }
                } label: {
                    Label("more_actions".t, systemImage: "ellipsis.circle.fill")
                        .font(.caption).fontWeight(.semibold)
                        .foregroundColor(.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.appSurfaceHigh)
                        .clipShape(Capsule())
                }
                .menuStyle(.button)
            }
            .buttonStyle(.plain)
        }
        .apCard()
    }
}

// MARK: - Transaction Log Row

private struct TransactionLogRow: View {
    let txn: InventoryTransaction

    private var typeConfig: (label: String, icon: String, color: Color, gradient: LinearGradient) {
        switch txn.transactionType {
        case "receive":
            return ("inventory_receive".t, "plus.circle.fill", .appTeal, APGradient.positive)
        case "waste":
            return ("inventory_waste".t, "trash.fill", .appRose, APGradient.destructive)
        case "sell":
            return ("sell_label".t, "cart.fill", Color.appAccent, APGradient.accent)
        case "return_to_supplier":
            return ("return_to_supplier".t, "arrow.uturn.left.circle.fill", .appAmber, APGradient.warning)
        case "transfer_out":
            return ("xfer_out".t, "arrow.right.circle.fill", .appRose, APGradient.destructive)
        case "transfer_in":
            return ("xfer_in".t, "arrow.left.circle.fill", .appTeal, APGradient.positive)
        case "refund_return":
            return ("refund_label".t, "arrow.uturn.backward.circle.fill", .appAmber, APGradient.warning)
        default:
            return ("adjustment_label".t, "arrow.left.and.right.circle.fill", .appAmber, APGradient.warning)
        }
    }

    var body: some View {
        let cfg = typeConfig
        HStack(spacing: APSpacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(cfg.gradient)
                    .frame(width: 34, height: 34)
                Image(systemName: cfg.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(txn.item?.name ?? "unknown_item".t)
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(.textPrimary)
                    Spacer()
                    Text(String(format: "%@%.1f %@",
                                txn.quantity >= 0 ? "+" : "",
                                txn.quantity,
                                txn.item?.unit ?? ""))
                        .font(.subheadline).fontWeight(.bold)
                        .foregroundColor(txn.quantity < 0 ? .appRose : .appTeal)
                }

                HStack {
                    APBadge(text: cfg.label, color: cfg.color)
                    Text(txn.notes ?? "no_details".t)
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                        .lineLimit(1)
                    Spacer()
                    Text(txn.updatedAt, format: .dateTime.day().month().hour().minute())
                        .font(.caption2)
                        .foregroundColor(.textTertiary)
                }
            }
        }
        .padding(APSpacing.md)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: APRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: APRadius.md, style: .continuous)
                .stroke(Color.appBorderSubtle, lineWidth: 1)
        )
    }
}

// MARK: - Receive Stock Sheet

struct ReceiveStockView: View {
    let item: InventoryItem
    let viewModel: InventoryViewModel
    let onComplete: () -> Void

    @State private var amountString = ""
    @State private var costString = ""
    @State private var noteText = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: APSpacing.md) {
                        VStack(alignment: .leading, spacing: APSpacing.sm) {
                            sectionHeader("item_information".t)
                            infoRow(label: "name_label".t, value: item.name)
                            infoRow(label: "sku_label".t, value: item.sku ?? "N/A")
                            infoRow(label: "on_hand_label".t, value: String(format: "%.1f %@", item.currentQuantity, item.unit))
                        }
                        .apCard()

                        VStack(alignment: .leading, spacing: APSpacing.sm) {
                            sectionHeader("incoming_stock".t)
                            inputField(LocalizationManager.shared.t("quantity_with_unit", item.unit), text: $amountString)
                            inputField(LocalizationManager.shared.t("unit_cost_with_unit", item.unit), text: $costString)
                            inputField("invoice_reference_note".t, text: $noteText)
                        }
                        .apCard()
                    }
                    .padding(APSpacing.md)
                }
            }
            .navigationTitle("receive_stock_title".t)
            .apNavBar(background: Color.appSurface)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel_btn".t) { onComplete() }.foregroundColor(.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("process_btn".t) {
                        viewModel.processReceive(item: item, amountString: amountString,
                                                  costString: costString, notes: noteText)
                        onComplete()
                    }
                    .disabled(amountString.isEmpty)
                    .foregroundStyle(APGradient.positive)
                }
            }
        }
        .apColorScheme()
    }
}

// MARK: - Waste/Adjust Stock Sheet

struct WasteStockView: View {
    let item: InventoryItem
    let viewModel: InventoryViewModel
    let onComplete: () -> Void

    @State private var amountString = ""
    @State private var reasonSelection = "Spoilage"
    @State private var noteText = ""

    let reasons = ["Spoilage", "Wastage", "Spillage/Accident", "Audit Correction"]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: APSpacing.md) {
                        VStack(alignment: .leading, spacing: APSpacing.sm) {
                            sectionHeader("item_information".t)
                            infoRow(label: "Name", value: item.name)
                            infoRow(label: "On Hand", value: String(format: "%.1f %@", item.currentQuantity, item.unit))
                        }
                        .apCard()

                        VStack(alignment: .leading, spacing: APSpacing.sm) {
                            sectionHeader("adjustment_label".t)
                            inputField(LocalizationManager.shared.t("quantity_to_deduct", item.unit), text: $amountString)

                            Picker("reason_label".t, selection: $reasonSelection) {
                                ForEach(reasons, id: \.self) { reason in
                                    Text(reason == "Spoilage" ? "reason_spoilage".t :
                                         (reason == "Wastage" ? "reason_wastage".t :
                                         (reason == "Spillage/Accident" ? "reason_spillage_accident".t :
                                          "reason_audit_correction".t)))
                                    .tag(reason)
                                }
                            }
                            .pickerStyle(.segmented)

                            inputField("additional_details".t, text: $noteText)
                        }
                        .apCard()
                    }
                    .padding(APSpacing.md)
                }
            }
            .navigationTitle("record_waste_adjust".t)
            .apNavBar(background: Color.appSurface)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel_btn".t) { onComplete() }.foregroundColor(.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("process_btn".t) {
                        viewModel.processWaste(item: item, amountString: amountString,
                                               reasonSelection: reasonSelection, notes: noteText)
                        onComplete()
                    }
                    .disabled(amountString.isEmpty)
                    .foregroundStyle(APGradient.destructive)
                }
            }
        }
        .apColorScheme()
    }
}

// MARK: - Bulk Receive Sheet

struct BulkReceiveSheet: View {
    let items: [InventoryItem]
    let viewModel: InventoryViewModel
    let onComplete: () -> Void

    @State private var amountString = ""
    @State private var noteText = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: APSpacing.md) {
                        VStack(alignment: .leading, spacing: APSpacing.sm) {
                            sectionHeader("bulk_receive_info".t)
                            Text(LocalizationManager.shared.t("bulk_receive_description", items.count))
                                .font(.subheadline)
                                .foregroundColor(.textSecondary)

                            // Item list preview
                            ForEach(items) { item in
                                HStack {
                                    Text(item.name)
                                        .font(.caption)
                                        .foregroundColor(.textPrimary)
                                    Spacer()
                                    Text(String(format: "%.1f %@", item.currentQuantity, item.unit))
                                        .font(.caption)
                                        .foregroundColor(.textSecondary)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        .apCard()

                        VStack(alignment: .leading, spacing: APSpacing.sm) {
                            sectionHeader("incoming_stock".t)
                            inputField("quantity_per_item".t, text: $amountString)
                            inputField("invoice_reference_note".t, text: $noteText)
                        }
                        .apCard()
                    }
                    .padding(APSpacing.md)
                }
            }
            .navigationTitle("bulk_receive_title".t)
            .apNavBar(background: Color.appSurface)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel_btn".t) { onComplete() }.foregroundColor(.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("process_btn".t) {
                        for item in items {
                            viewModel.processReceive(item: item, amountString: amountString,
                                                      costString: "", notes: noteText.isEmpty ? "Bulk receive" : noteText)
                        }
                        onComplete()
                    }
                    .disabled(amountString.isEmpty)
                    .foregroundStyle(APGradient.positive)
                }
            }
        }
        .apColorScheme()
    }
}

// MARK: - Bulk Waste Sheet

struct BulkWasteSheet: View {
    let items: [InventoryItem]
    let viewModel: InventoryViewModel
    let onComplete: () -> Void

    @State private var amountString = ""
    @State private var reasonSelection = "Spoilage"
    @State private var noteText = ""

    let reasons = ["Spoilage", "Wastage", "Spillage/Accident", "Audit Correction"]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: APSpacing.md) {
                        VStack(alignment: .leading, spacing: APSpacing.sm) {
                            sectionHeader("bulk_waste_info".t)
                            Text(LocalizationManager.shared.t("bulk_waste_description", items.count))
                                .font(.subheadline)
                                .foregroundColor(.textSecondary)

                            ForEach(items) { item in
                                HStack {
                                    Text(item.name)
                                        .font(.caption)
                                        .foregroundColor(.textPrimary)
                                    Spacer()
                                    Text(String(format: "%.1f %@", item.currentQuantity, item.unit))
                                        .font(.caption)
                                        .foregroundColor(.textSecondary)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        .apCard()

                        VStack(alignment: .leading, spacing: APSpacing.sm) {
                            sectionHeader("adjustment_label".t)
                            inputField("quantity_per_item".t, text: $amountString)

                            Picker("reason_label".t, selection: $reasonSelection) {
                                ForEach(reasons, id: \.self) { reason in
                                    Text(reason).tag(reason)
                                }
                            }
                            .pickerStyle(.segmented)

                            inputField("additional_details".t, text: $noteText)
                        }
                        .apCard()
                    }
                    .padding(APSpacing.md)
                }
            }
            .navigationTitle("bulk_waste_title".t)
            .apNavBar(background: Color.appSurface)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel_btn".t) { onComplete() }.foregroundColor(.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("process_btn".t) {
                        for item in items {
                            viewModel.processWaste(item: item, amountString: amountString,
                                                    reasonSelection: reasonSelection, notes: noteText.isEmpty ? "Bulk waste" : noteText)
                        }
                        onComplete()
                    }
                    .disabled(amountString.isEmpty)
                    .foregroundStyle(APGradient.destructive)
                }
            }
        }
        .apColorScheme()
    }
}

// MARK: - Sheet Helpers (global functions)

private func sectionHeader(_ text: String) -> some View {
    Text(text)
        .font(.caption)
        .fontWeight(.bold)
        .foregroundColor(.textSecondary)
        .textCase(.uppercase)
        .tracking(1)
}

private func infoRow(label: String, value: String) -> some View {
    VStack(spacing: 0) {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.textSecondary)
            Spacer()
            Text(value)
                .font(.subheadline).fontWeight(.semibold)
                .foregroundColor(.textPrimary)
        }
        .padding(.vertical, 4)
        Divider().background(Color.appDivider)
    }
}

private func inputField(_ placeholder: String, text: Binding<String>) -> some View {
    TextField(placeholder, text: text)
        .font(.subheadline)
        .foregroundColor(.textPrimary)
        .tint(.appAccent)
        .padding(APSpacing.sm)
        .background(Color.appSurfaceHigh)
        .clipShape(RoundedRectangle(cornerRadius: APRadius.sm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: APRadius.sm, style: .continuous)
                .stroke(Color.appBorderSubtle, lineWidth: 1)
        )
}

// MARK: - Edit Stock Item View

struct EditStockItemView: View {
    let item: InventoryItem
    let viewModel: InventoryViewModel
    let onComplete: () -> Void

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var lm: LocalizationManager
    @Query(sort: \Supplier.name) private var suppliers: [Supplier]

    @State private var name = ""
    @State private var sku = ""
    @State private var unit = ""
    @State private var reorderString = ""
    @State private var costString = ""
    @State private var selectedSupplierId: UUID? = nil
    @State private var showingDeleteAlert = false

    // High-Volume fields
    @State private var category = ""
    @State private var storageLocation = ""
    @State private var barcode = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: APSpacing.md) {
                        VStack(alignment: .leading, spacing: APSpacing.sm) {
                            sectionHeader("item_details".t)
                            inputField("item_name_placeholder".t, text: $name)
                            inputField("sku_code_placeholder".t, text: $sku)
                            inputField("barcode_placeholder".t, text: $barcode)
                            inputField("unit_placeholder".t, text: $unit)
                        }
                        .apCard()

                        VStack(alignment: .leading, spacing: APSpacing.sm) {
                            sectionHeader("classification_location".t)
                            inputField("category_placeholder".t, text: $category)
                            inputField("storage_location_placeholder".t, text: $storageLocation)
                        }
                        .apCard()

                        VStack(alignment: .leading, spacing: APSpacing.sm) {
                            sectionHeader("reordering_costs".t)
                            inputField("reorder_trigger_level_placeholder".t, text: $reorderString)
                            inputField("unit_cost_price_placeholder".t, text: $costString)
                        }
                        .apCard()

                        VStack(alignment: .leading, spacing: APSpacing.sm) {
                            sectionHeader("supplier_association".t)
                            Picker("supplier_label".t, selection: $selectedSupplierId) {
                                Text("no_supplier_option".t).tag(nil as UUID?)
                                ForEach(suppliers) { sup in
                                    Text(sup.name).tag(sup.id as UUID?)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(.appAccent)
                        }
                        .apCard()

                        // Delete section
                        VStack(alignment: .leading, spacing: APSpacing.sm) {
                            sectionHeader("danger_zone".t)
                            Button(action: { showingDeleteAlert = true }) {
                                HStack {
                                    Image(systemName: "trash.fill")
                                    Text("delete_this_item_btn".t)
                                }
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.appRose)
                                .frame(maxWidth: .infinity)
                                .padding(APSpacing.sm)
                                .background(Color.appRose.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: APRadius.sm, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: APRadius.sm, style: .continuous)
                                        .stroke(Color.appRose.opacity(0.25), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        .apCard()
                    }
                    .padding(APSpacing.md)
                }
            }
            .navigationTitle("edit_item_details_title".t)
            .apNavBar(background: Color.appSurface)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel_btn".t) { onComplete() }.foregroundColor(.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("save_btn".t) {
                        let reorder = Double(reorderString) ?? item.reorderLevel
                        let cost = Double(costString) ?? item.costPrice
                        viewModel.updateInventoryItem(
                            item: item,
                            name: name,
                            sku: sku.isEmpty ? nil : sku,
                            unit: unit,
                            reorderLevel: reorder,
                            costPrice: cost,
                            supplierId: selectedSupplierId,
                            category: category.isEmpty ? nil : category,
                            storageLocation: storageLocation.isEmpty ? nil : storageLocation,
                            barcode: barcode.isEmpty ? nil : barcode
                        )
                        onComplete()
                    }
                    .disabled(name.isEmpty || unit.isEmpty)
                    .foregroundStyle(APGradient.accent)
                }
            }
            .onAppear {
                name = item.name
                sku = item.sku ?? ""
                unit = item.unit
                reorderString = String(format: "%.1f", item.reorderLevel)
                costString = String(format: "%.2f", item.costPrice)
                selectedSupplierId = item.supplier?.id
                category = item.category ?? ""
                storageLocation = item.storageLocation ?? ""
                barcode = item.barcode ?? ""
            }
            .alert("delete_item_alert_title".t, isPresented: $showingDeleteAlert) {
                Button("cancel_btn".t, role: .cancel) { }
                Button("delete_btn".t, role: .destructive) {
                    viewModel.deleteInventoryItem(item: item)
                    onComplete()
                }
            } message: {
                Text("Are you sure you want to permanently delete \"\(item.name)\"? This action cannot be undone and all related transactions will be removed.")
            }
        }
        .apColorScheme()
    }
}

// MARK: - Item Movement History Sheet

struct ItemMovementHistorySheet: View {
    let item: InventoryItem
    let onDismiss: () -> Void

    @State private var filterType = "All"

    private let typeOptions = ["All", "receive", "waste", "sell", "adjust", "refund_return"]

    private var filteredTransactions: [InventoryTransaction] {
        let sorted = item.transactions.sorted { $0.updatedAt > $1.updatedAt }
        guard filterType != "All" else { return sorted }
        return sorted.filter { $0.transactionType == filterType }
    }

    private var totalReceived: Double {
        item.transactions.filter { $0.transactionType == "receive" }.reduce(0.0) { $0 + $1.quantity }
    }

    private var totalWasted: Double {
        item.transactions.filter { $0.transactionType == "waste" }.reduce(0.0) { $0 + abs($1.quantity) }
    }

    private var totalSold: Double {
        item.transactions.filter { $0.transactionType == "sell" }.reduce(0.0) { $0 + abs($1.quantity) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Summary stats
                    HStack(spacing: APSpacing.md) {
                        summaryCard(title: "on_hand_label".t, value: String(format: "%.1f %@", item.currentQuantity, item.unit), icon: "shippingbox.fill", color: .appAccent)
                        summaryCard(title: "received_label".t, value: String(format: "%.1f", totalReceived), icon: "plus.circle.fill", color: .appTeal)
                        summaryCard(title: "wasted_label".t, value: String(format: "%.1f", totalWasted), icon: "trash.fill", color: .appRose)
                        summaryCard(title: "sold_label".t, value: String(format: "%.1f", totalSold), icon: "cart.fill", color: Color.appAccent)
                    }
                    .padding(APSpacing.md)
                    .background(Color.appSurface)

                    Divider().background(Color.appDivider)

                    // Type filter capsules
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: APSpacing.xs) {
                            ForEach(typeOptions, id: \.self) { opt in
                                let display = opt == "All" ? "filter_all".t :
                                    (opt == "receive" ? "inventory_receive".t :
                                    (opt == "waste" ? "inventory_waste".t :
                                    (opt == "sell" ? "sell_label".t :
                                    (opt == "refund_return" ? "refund_label".t : "adjustment_label".t))))
                                let count = opt == "All" ? item.transactions.count : item.transactions.filter({ $0.transactionType == opt }).count
                                Button(action: { filterType = opt }) {
                                    HStack(spacing: 4) {
                                        Text(display)
                                        Text("(\(count))")
                                            .font(.system(size: 9))
                                    }
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(filterType == opt ? APGradient.accent : nil)
                                    .backgroundColor(filterType == opt ? .clear : Color.appSurfaceHigh)
                                    .foregroundColor(filterType == opt ? .white : .textSecondary)
                                    .clipShape(Capsule())
                                    .overlay(
                                        Capsule()
                                            .stroke(filterType == opt ? Color.clear : Color.appBorderSubtle, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, APSpacing.md)
                        .padding(.vertical, APSpacing.sm)
                    }
                    .background(Color.appBackground)
                    .overlay(Rectangle().fill(Color.appDivider).frame(height: 1), alignment: .bottom)

                    // Transaction list
                    if filteredTransactions.isEmpty {
                        VStack(spacing: APSpacing.md) {
                            Image(systemName: "tray.fill")
                                .font(.system(size: 36))
                                .foregroundColor(.textTertiary)
                            Text("no_transactions_found".t)
                                .font(.subheadline)
                                .foregroundColor(.textSecondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: APSpacing.sm) {
                                ForEach(filteredTransactions) { txn in
                                    movementRow(txn: txn)
                                }
                            }
                            .padding(APSpacing.md)
                        }
                    }
                }
            }
            .navigationTitle(LocalizationManager.shared.t("item_history_title_template", item.name))
            .navigationBarTitleDisplayMode(.inline)
            .apNavBar(background: Color.appSurface)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("close_btn_label".t) { onDismiss() }
                        .foregroundColor(.textSecondary)
                }
            }
        }
        .apColorScheme()
    }

    private func summaryCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundColor(color)
            Text(value)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.textPrimary)
            Text(title)
                .font(.system(size: 8))
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(Color.appSurfaceHigh)
        .cornerRadius(APRadius.sm)
        .overlay(
            RoundedRectangle(cornerRadius: APRadius.sm)
                .stroke(Color.appBorderSubtle, lineWidth: 1)
        )
    }

    private func movementRow(txn: InventoryTransaction) -> some View {
        let typeConfig: (label: String, icon: String, color: Color) = {
            switch txn.transactionType {
            case "receive": return ("Receive", "plus.circle.fill", .appTeal)
            case "waste": return ("Waste", "trash.fill", .appRose)
            case "sell": return ("Sell", "cart.fill", Color.appAccent)
            case "refund_return": return ("Refund", "arrow.uturn.backward.circle.fill", .appAmber)
            default: return ("Adjust", "arrow.left.and.right.circle.fill", .appAmber)
            }
        }()

        return HStack(spacing: APSpacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(typeConfig.color.opacity(0.15))
                    .frame(width: 34, height: 34)
                Image(systemName: typeConfig.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(typeConfig.color)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    APBadge(text: typeConfig.label, color: typeConfig.color)
                    Spacer()
                    Text(String(format: "%@%.1f %@",
                                txn.quantity >= 0 ? "+" : "",
                                txn.quantity,
                                item.unit))
                        .font(.subheadline).fontWeight(.bold)
                        .foregroundColor(txn.quantity >= 0 ? .appTeal : .appRose)
                }

                HStack {
                    Text(txn.notes ?? "no_details".t)
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                        .lineLimit(1)
                    Spacer()
                    if let cost = txn.costPrice {
                        Text("฿\(String(format: "%.2f", cost))/\(item.unit)")
                            .font(.caption2)
                            .foregroundColor(.textTertiary)
                    }
                    Text(txn.updatedAt, format: .dateTime.day().month().hour().minute())
                        .font(.caption2)
                        .foregroundColor(.textTertiary)
                }
            }
        }
        .padding(APSpacing.md)
        .apCard()
    }
}

// MARK: - Add Stock Item View

struct AddStockItemView: View {
    let viewModel: InventoryViewModel
    let activeBranch: Branch?
    let onComplete: () -> Void

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var lm: LocalizationManager
    @Query(sort: \Supplier.name) private var suppliers: [Supplier]

    @State private var name = ""
    @State private var sku = ""
    @State private var unit = "piece"
    @State private var reorderString = "5.0"
    @State private var costString = "0.0"
    @State private var selectedSupplierId: UUID? = nil

    @State private var category = ""
    @State private var storageLocation = ""
    @State private var barcode = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: APSpacing.md) {
                        VStack(alignment: .leading, spacing: APSpacing.sm) {
                            sectionHeader("item_details".t)
                            inputField("item_name_placeholder".t, text: $name)
                            inputField("sku_code_placeholder".t, text: $sku)
                            inputField("barcode_placeholder".t, text: $barcode)
                            inputField("unit_placeholder".t, text: $unit)
                        }
                        .apCard()

                        VStack(alignment: .leading, spacing: APSpacing.sm) {
                            sectionHeader("classification_location".t)
                            inputField("category_placeholder".t, text: $category)
                            inputField("storage_location_placeholder".t, text: $storageLocation)
                        }
                        .apCard()

                        VStack(alignment: .leading, spacing: APSpacing.sm) {
                            sectionHeader("reordering_costs".t)
                            inputField("reorder_trigger_level_placeholder".t, text: $reorderString)
                            inputField("unit_cost_price_placeholder".t, text: $costString)
                        }
                        .apCard()

                        VStack(alignment: .leading, spacing: APSpacing.sm) {
                            sectionHeader("supplier_association".t)
                            Picker("supplier_label".t, selection: $selectedSupplierId) {
                                Text("no_supplier_option".t).tag(nil as UUID?)
                                ForEach(suppliers) { sup in
                                    Text(sup.name).tag(sup.id as UUID?)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(.appAccent)
                        }
                        .apCard()
                    }
                    .padding(APSpacing.md)
                }
            }
            .navigationTitle("add_raw_material".t)
            .apNavBar(background: Color.appSurface)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel_btn".t) { onComplete() }.foregroundColor(.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("save_btn".t) {
                        let reorder = Double(reorderString) ?? 0.0
                        let cost = Double(costString) ?? 0.0
                        viewModel.addInventoryItem(
                            name: name,
                            sku: sku.isEmpty ? nil : sku,
                            unit: unit,
                            reorderLevel: reorder,
                            costPrice: cost,
                            supplierId: selectedSupplierId,
                            category: category.isEmpty ? nil : category,
                            storageLocation: storageLocation.isEmpty ? nil : storageLocation,
                            barcode: barcode.isEmpty ? nil : barcode,
                            activeBranch: activeBranch
                        )
                        onComplete()
                    }
                    .disabled(name.isEmpty || unit.isEmpty)
                    .foregroundStyle(APGradient.accent)
                }
            }
        }
        .apColorScheme()
    }
}

// MARK: - Return Supplier Stock View

struct ReturnSupplierStockView: View {
    let item: InventoryItem
    let viewModel: InventoryViewModel
    let onComplete: () -> Void

    @State private var amountString = ""
    @State private var noteText = ""
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: APSpacing.md) {
                        if !errorMessage.isEmpty {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(.appRose)
                                .padding(APSpacing.sm)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.appRose.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: APRadius.sm))
                        }

                        VStack(alignment: .leading, spacing: APSpacing.sm) {
                            sectionHeader("item_information".t)
                            infoRow(label: "Name", value: item.name)
                            infoRow(label: "On Hand", value: String(format: "%.1f %@", item.currentQuantity, item.unit))
                        }
                        .apCard()

                        VStack(alignment: .leading, spacing: APSpacing.sm) {
                            sectionHeader("Return to Supplier")
                            inputField(LocalizationManager.shared.t("quantity_to_return", item.unit), text: $amountString)
                            inputField("return_details_placeholder".t, text: $noteText)
                        }
                        .apCard()
                    }
                    .padding(APSpacing.md)
                }
            }
            .navigationTitle("return_to_supplier_title".t)
            .apNavBar(background: Color.appSurface)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel_btn".t) { onComplete() }.foregroundColor(.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("process_btn".t) {
                        if let qty = Double(amountString), qty > item.currentQuantity {
                            errorMessage = "quantity_exceeds_stock_error".t
                        } else {
                            errorMessage = ""
                            viewModel.processReturnToSupplier(item: item, amountString: amountString, notes: noteText)
                            onComplete()
                        }
                    }
                    .disabled(amountString.isEmpty)
                    .foregroundStyle(APGradient.destructive)
                }
            }
        }
        .apColorScheme()
    }
}
