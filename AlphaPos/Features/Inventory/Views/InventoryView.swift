// InventoryView.swift
// AlphaPos — Premium Inventory Interface v2
// Redesigned for high-volume (200+ items) with pagination, dynamic sorting, expiry alerts,
// debounced search, color-coded stock bars, and bulk operations.

import SwiftUI
import SwiftData
import Combine

// MARK: - Main Inventory View

struct InventoryView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var lm: LocalizationManager
    @EnvironmentObject private var sessionManager: AppSessionManager
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query(filter: #Predicate<InventoryItem> { !$0.isDeleted }, sort: \InventoryItem.name) private var inventory: [InventoryItem]
    @Query(filter: #Predicate<InventoryTransaction> { !$0.isDeleted }, sort: \InventoryTransaction.updatedAt, order: .reverse) private var transactions: [InventoryTransaction]
    @Query(filter: #Predicate<Branch> { !$0.isDeleted }, sort: \Branch.name) private var branches: [Branch]
    @Query(filter: #Predicate<InventoryLot> { !$0.isDeleted }, sort: \InventoryLot.expiryDate) private var inventoryLots: [InventoryLot]
    @Query(filter: #Predicate<InventoryLotControl> { !$0.isDeleted }) private var lotControls: [InventoryLotControl]
    @Query(
        filter: #Predicate<MenuItem> { !$0.isDeleted },
        sort: \MenuItem.name
    ) private var menuItems: [MenuItem]

    @State private var viewModel = InventoryViewModel()
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    /// Warehouse users land on operational stock status, not the sales catalog.
    @State private var selectedSection: InventoryMainSection = .stock
    @Namespace private var sectionTabNamespace
    @ObservedObject private var syncEngine = SyncEngine.shared
    @State private var showingEditSheet = false
    @State private var showingMovementHistory = false
    @State private var showingAddSheet = false
    @State private var showingFinishedGoodSheet = false
    @State private var showingReturnSheet = false
    @State private var showingQuickAdjustSheet = false
    @State private var showingTransactionLog = false
    @State private var showingStockGuide = false
    @State private var showingPendingSyncDetails = false

    // Multi-Branch and sheets states
    @AppStorage(BranchContext.storageKey) private var activeBranchId = ""
    /// `simple` = retail / no BOM tabs · `restaurant` = kitchen + recipes
    @AppStorage("inventory_profile") private var inventoryProfile = "restaurant"
    @State private var showingBranchManager = false
    @State private var showingPOManager = false
    @State private var showingTransferSheet = false
    @State private var showingDocumentScanner = false
    // High-Volume filters state
    @State private var statusFilter = "All" // "All", "Low Stock", "Out of Stock"
    @State private var stockKindFilter = "All" // "All", "Ingredients", "FinishedGoods"
    @State private var selectedCategory = "All"
    @State private var savedFilter: InventorySavedFilter = .none
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
    @State private var showingBulkTransferSheet = false
    @State private var showingBulkQuarantineSheet = false
    @FocusState private var searchIsFocused: Bool

    // Category Management
    @State private var showingCategoryManager = false
    @State private var showingBulkAssignCategory = false

    // Cycle Count (ABC-based stocktaking)
    @State private var showingCycleCount = false

    // ABC Classification (computed on data change)
    @State private var abcClassification: [UUID: String] = [:]

    // Expiry Date & FEFO
    @State private var expiryManager = InventoryExpiryManager()
    @State private var showingExpiryAlerts = false
    @State private var expiryAlertCount: (expired: Int, critical: Int, warning: Int) = (0, 0, 0)

    // Safety Stock & Reorder Suggestions
    @State private var safetyStockManager = SafetyStockManager()
    @State private var showingReorderSuggestions = false

    // Decoupled stats computation to prevent Main Thread freeze on render
    @State private var localLowStockCount: Int = 0
    @State private var localFilteredTransactionsCount: Int = 0
    @State private var localReorderSuggestions: [ReorderSuggestion] = []

    // Debounce timer
    @State private var searchDebounceTask: Task<Void, Never>?

    // MARK: - Computed Properties

    private var activeBranch: Branch? {
        guard let selectedID = UUID(uuidString: activeBranchId) else { return nil }
        return branches.first(where: { $0.id == selectedID && !$0.isDeleted })
    }

    /// Pre-filters by branch and isDeleted (fast, SwiftData-backed)
    private var branchInventory: [InventoryItem] {
        let activeItems = inventory
        guard let branch = activeBranch else { return [] }
        return activeItems.filter { $0.branch?.id == branch.id }
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
        case "Negative Stock":
            result = result.filter { $0.currentQuantity < 0.0 }
        case "Out of Stock":
            result = result.filter { $0.currentQuantity <= 0.0 }
        case "Sync KPI":
            result = result.filter { !$0.isSynced }
        case "Quarantine KPI":
            let quarantinedIds = Set(lotControls.filter {
                !$0.isDeleted && $0.disposition == .quarantined
            }.map(\.inventoryItemId))
            result = result.filter { quarantinedIds.contains($0.id) }
        case "Expiry KPI":
            let alertedIds = Set(inventoryLots.compactMap { lot -> UUID? in
                guard !lot.isDeleted, lot.remainingQuantity > 0,
                      let status = lot.expiryDate.map({ _ in lot.expiryStatus(threshold: .default) }),
                      status != .ok else { return nil }
                return lot.inventoryItem?.id
            })
            result = result.filter { alertedIds.contains($0.id) }
        default:
            break
        }

        // 3. Stock kind (ingredients vs finished goods)
        switch stockKindFilter {
        case "Ingredients":
            result = result.filter { !$0.isFinishedGoodSKU }
        case "FinishedGoods":
            result = result.filter { $0.isFinishedGoodSKU }
        default:
            break
        }

        // 4. Category filter
        if selectedCategory != "All" {
            if selectedCategory == "ไม่ระบุหมวดหมู่" {
                result = result.filter { $0.category == nil || $0.category?.isEmpty == true }
            } else {
                result = result.filter { $0.category == selectedCategory }
            }
        }

        // 5. Operational saved filters
        let calendar = Calendar.current
        switch savedFilter {
        case .none: break
        case .expiringThreeDays:
            let cutoff = calendar.date(byAdding: .day, value: 3, to: Date()) ?? Date()
            let ids = Set(inventoryLots.compactMap { lot -> UUID? in
                guard !lot.isDeleted, lot.remainingQuantity > 0,
                      let expiry = lot.expiryDate, expiry >= calendar.startOfDay(for: Date()),
                      expiry <= cutoff else { return nil }
                return lot.inventoryItem?.id
            })
            result = result.filter { ids.contains($0.id) }
        case .negative:
            result = result.filter { $0.currentQuantity < 0 }
        case .noRecipe:
            result = result.filter { $0.recipeUsages.allSatisfy(\.isDeleted) }
        case .noSupplier:
            result = result.filter { $0.supplier == nil }
        case .noLot:
            let ids = Set(inventoryLots.compactMap {
                !$0.isDeleted && $0.remainingQuantity > 0 ? $0.inventoryItem?.id : nil
            })
            result = result.filter { !ids.contains($0.id) }
        }

        // 6. Sorting
        result = sortItems(result)

        return result
    }

    private var visibleSections: [InventoryMainSection] {
        InventoryMainSection.visible(for: inventoryProfile)
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
            return activeTransactions.filter { $0.branch.id == branch.id }
        }
        return activeTransactions
    }

    // Stats
    private var lowStockCount: Int {
        branchInventory.filter { $0.currentQuantity > 0 && $0.currentQuantity <= $0.reorderLevel }.count
    }
    private var negativeStockCount: Int {
        branchInventory.filter { $0.currentQuantity < 0.0 }.count
    }
    private var outOfStockCount: Int {
        branchInventory.filter { $0.currentQuantity <= 0.0 }.count
    }
    private var quarantineCount: Int {
        guard let branchId = activeBranch?.id else { return 0 }
        return lotControls.filter {
            !$0.isDeleted && $0.disposition == .quarantined && $0.branchId == branchId
        }.count
    }
    private var pendingInventoryItems: [InventoryItem] {
        branchInventory.filter { !$0.isSynced }
    }
    private var pendingInventoryLots: [InventoryLot] {
        guard let branchId = activeBranch?.id else { return [] }
        return inventoryLots.filter {
            !$0.isDeleted && !$0.isSynced
            && InventorySyncScope.includes(activeBranchId: branchId, entityBranchId: $0.branch?.id)
        }
    }
    private var pendingInventoryTransactions: [InventoryTransaction] {
        filteredTransactionsList.filter { !$0.isSynced }
    }
    private var pendingLotControls: [InventoryLotControl] {
        guard let branchId = activeBranch?.id else { return [] }
        return lotControls.filter {
            !$0.isDeleted && !$0.isSynced
            && InventorySyncScope.includes(activeBranchId: branchId, entityBranchId: $0.branchId)
        }
    }
    private var pendingSyncCount: Int {
        pendingInventoryItems.count
        + pendingInventoryLots.count
        + pendingInventoryTransactions.count
        + pendingLotControls.count
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

    private var nearestLotByItemId: [UUID: InventoryLot] {
        inventoryLots.reduce(into: [:]) { result, lot in
            guard !lot.isDeleted, lot.remainingQuantity > 0,
                  let itemId = lot.inventoryItem?.id else { return }
            if result[itemId]?.expiryDate == nil ||
                (lot.expiryDate != nil && lot.expiryDate! < result[itemId]!.expiryDate!) {
                result[itemId] = lot
            }
        }
    }

    // MARK: - Body

    var body: some View {
        Group {
            if sessionManager.can(.inventoryView) && sessionManager.can(.inventoryManage) && sessionManager.can(.productCostsView) {
                managementBody
            } else if sessionManager.can(.inventoryView) {
                OperationalStockView()
            } else {
                ContentUnavailableView("ไม่มีสิทธิ์เข้าถึงคลังสินค้า", systemImage: "lock.shield")
            }
        }
    }

    private var managementBody: some View {
        inventorySheetsAndAlerts(content: content)
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("")
            .apNavBar(background: Color.appBackground)
            .toolbar { toolbarContent }
            .onAppear {
                viewModel.modelContext = modelContext
                viewModel.seedDefaultBranchIfNeeded()
                expiryManager.modelContext = modelContext
                safetyStockManager.modelContext = modelContext
                recalculateABC()
                refreshExpiryCount()
                refreshStats()
                applyPendingInventoryFocus()
                applyPendingFirstProductGuide()
                withAnimation(.easeOut(duration: 0.4)) {
                    isAnimatedIn = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openInventoryItemNotification)) { _ in
                applyPendingInventoryFocus()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openFirstProductGuideNotification)) { _ in
                guard menuItems.isEmpty else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedSection = .menu
                }
            }
            .onChange(of: activeBranchId) { _, _ in
                exitSelectionMode()
                refreshStats()
            }
            .onChange(of: inventory) { _, _ in refreshStats() }
            .onChange(of: transactions) { _, _ in refreshStats() }
            .onChange(of: searchText) { _, newValue in
                debounceSearch(newValue)
            }
            .onChange(of: statusFilter) { _, _ in resetPagination() }
            .onChange(of: stockKindFilter) { _, _ in resetPagination() }
            .onChange(of: selectedCategory) { _, _ in resetPagination() }
            .onChange(of: savedFilter) { _, _ in resetPagination() }
            .onChange(of: sortKey) { _, _ in resetPagination() }
            .onChange(of: sortAscending) { _, _ in resetPagination() }
            .onChange(of: inventoryProfile) { _, _ in
                if !visibleSections.contains(selectedSection) {
                    selectedSection = visibleSections.first ?? .menu
                }
            }
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
            .sheet(isPresented: $showingFinishedGoodSheet) {
                FinishedGoodQuickCreateSheet(activeBranch: activeBranch) {
                    showingFinishedGoodSheet = false
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
            .sheet(isPresented: $showingBulkTransferSheet) {
                if let active = activeBranch, let item = selectedItemObjects.first {
                    StockTransferSheet(sourceBranch: active, preselectedItem: item)
                }
            }
            .sheet(isPresented: $showingBulkQuarantineSheet) {
                BulkQuarantineSheet(items: selectedItemObjects, lots: inventoryLots) {
                    showingBulkQuarantineSheet = false
                    exitSelectionMode()
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
            .fullScreenCover(isPresented: $showingDocumentScanner) {
                StockDocumentScanSheet {
                    showingDocumentScanner = false
                }
            }
            .sheet(isPresented: $showingCategoryManager) {
                ManageCategoriesSheet()
            }
            .sheet(isPresented: $showingTransactionLog) {
                transactionSheet
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
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
            .sheet(isPresented: $showingExpiryAlerts) {
                ExpiryAlertListSheet(
                    alerts: expiryManager.getExpiringAlerts(branch: activeBranch)
                )
                .onDisappear { refreshExpiryCount() }
            }
            .sheet(isPresented: $showingReorderSuggestions) {
                ReorderSuggestionListSheet(
                    suggestions: localReorderSuggestions,
                    safetyStockManager: safetyStockManager
                )
            }
            .sheet(isPresented: $showingCycleCount) {
                CycleCountView(activeBranch: activeBranch)
            }
            .sheet(isPresented: $showingStockGuide) {
                InventoryStockGuideView()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showingPendingSyncDetails) {
                InventoryPendingSyncView(
                    branchName: activeBranch?.name ?? "—",
                    itemCount: pendingInventoryItems.count,
                    transactionCount: pendingInventoryTransactions.count,
                    lotCount: pendingInventoryLots.count,
                    controlCount: pendingLotControls.count,
                    lastSyncedAt: syncEngine.lastSyncedAt
                ) {
                    Task { await syncEngine.syncAll(modelContext: modelContext) }
                }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
    }

    private var content: some View {
        ZStack {
            inventoryAmbientCanvas

            VStack(spacing: APSpacing.sm) {
                inventoryNavigationChrome

                sectionContent
                    .id(selectedSection)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.98)),
                            removal: .opacity.combined(with: .scale(scale: 1.01))
                        )
                    )
            }
            .padding(.horizontal, APSpacing.md)
            .padding(.top, APSpacing.xs)
            .animation(.spring(response: 0.32, dampingFraction: 0.86), value: selectedSection)
        }
    }

    /// A quiet, content-aware canvas gives Liquid Glass something to refract.
    /// The low chroma keeps operational values readable in light and dark mode.
    private var inventoryAmbientCanvas: some View {
        ZStack {
            Color.appBackground
            Circle()
                .fill(Color.appAccent.opacity(0.10))
                .frame(width: 420, height: 420)
                .blur(radius: 90)
                .offset(x: -360, y: -360)
            Circle()
                .fill(Color.appTeal.opacity(0.07))
                .frame(width: 360, height: 360)
                .blur(radius: 100)
                .offset(x: 440, y: -260)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    /// Navigation and workspace context form one chrome layer; stock data stays
    /// on an opaque surface for reliable contrast and fast scanning.
    private var inventoryNavigationChrome: some View {
        branchAndSyncContext
    }

    private var branchAndSyncContext: some View {
        HStack(spacing: APSpacing.md) {
            Menu {
                ForEach(branches) { branch in
                    Button {
                        APHaptic.selection()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            BranchContext.shared.select(branch)
                        }
                    } label: {
                        if branch.id == activeBranch?.id {
                            Label(branch.name, systemImage: "checkmark")
                        } else {
                            Text(branch.name)
                        }
                    }
                }
                Divider()
                Button("manage_branches".t) { showingBranchManager = true }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "building.2.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Text(activeBranch?.name ?? (lm.currentLanguage == .thai ? "เลือกสาขา" : "Select branch"))
                        .font(.system(size: 13, weight: .bold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.textTertiary)
                }
                .foregroundColor(activeBranch == nil ? .appRose : .textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.appSurfaceHigh.opacity(0.8), in: Capsule())
                .overlay(Capsule().stroke(Color.appBorderSubtle, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .hoverEffect(.lift)
            .accessibilityLabel(lm.currentLanguage == .thai ? "สาขาที่กำลังใช้งาน" : "Active branch")

            if let location = activeBranch?.location, !location.isEmpty {
                Text("· \(location)")
                    .font(.system(size: 11.5))
                    .foregroundColor(.textSecondary)
            }

            Spacer()

            Button { showingPendingSyncDetails = true } label: {
                HStack(spacing: 5) {
                    Circle()
                        .fill(pendingSyncCount == 0 ? Color.appTeal : Color.appAmber)
                        .frame(width: 7, height: 7)
                    Text("\(pendingSyncCount) \(lm.currentLanguage == .thai ? "รอซิงก์" : "pending")")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(pendingSyncCount == 0 ? .appTeal : .appAmber)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    (pendingSyncCount == 0 ? Color.appTeal : Color.appAmber).opacity(0.12),
                    in: Capsule()
                )
            }
            .buttonStyle(.plain)
            .hoverEffect(.lift)
            .accessibilityHint(lm.currentLanguage == .thai ? "เปิดรายละเอียดสถานะซิงก์ของสาขานี้" : "Shows sync details for this branch")

            Text(syncEngine.lastSyncedAt.map {
                (lm.currentLanguage == .thai ? "ซิงก์ล่าสุด " : "Last sync ")
                + $0.formatted(date: .omitted, time: .shortened)
            } ?? (lm.currentLanguage == .thai ? "ยังไม่เคยซิงก์" : "Never synced"))
            .font(.system(size: 11))
            .foregroundColor(.textTertiary)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch selectedSection {
        case .stock:
            if activeBranch == nil {
                AnyView(branchRequiredState)
            } else if branchInventory.isEmpty {
                AnyView(emptyState)
            } else {
                AnyView(inventoryPanel)
            }
        case .purchasing:
            AnyView(InventoryPurchasingHubView(
                activeBranch: activeBranch,
                showingDocumentScanner: $showingDocumentScanner
            ))
        case .counts:
            AnyView(InventoryCountsHubView(showingCycleCount: $showingCycleCount))
        case .menu:
            AnyView(CatalogManagerView())
        case .recipes:
            AnyView(RecipeCatalogView())
        }
    }

    private var branchRequiredState: some View {
        VStack(spacing: APSpacing.md) {
            Image(systemName: "building.2.crop.circle.fill")
                .font(.system(size: 52))
                .foregroundColor(.appRose)
            Text(lm.currentLanguage == .thai ? "เลือกสาขาก่อนดูหรือจัดการสต็อก" : "Select a branch to view or manage stock")
                .font(.title3.weight(.bold))
                .foregroundColor(.textPrimary)
            Text(lm.currentLanguage == .thai
                 ? "ยอดคงเหลือ Lot จุดสั่งซื้อ และธุรกรรมจะแสดงเฉพาะสาขาที่เลือก เพื่อป้องกันการแก้ไขผิดสาขา"
                 : "On-hand balances, lots, reorder points, and transactions are scoped to the selected branch to prevent cross-branch mistakes.")
                .font(.subheadline)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
            Button {
                showingBranchManager = true
            } label: {
                Label(lm.currentLanguage == .thai ? "เลือกหรือจัดการสาขา" : "Select or manage branch",
                      systemImage: "building.2")
            }
            .buttonStyle(.borderedProminent)
            .tint(.appTeal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .accessibilityElement(children: .contain)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            nativeSectionSegmentedControl
        }

        if selectedSection == .stock && activeBranch != nil {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if branches.count > 1
                        && (sessionManager.can(.inventoryTransfer) || sessionManager.can(.inventoryManage)) {
                        Button(action: { showingTransferSheet = true }) {
                            Label("transfer_stock".t, systemImage: "arrow.left.arrow.right")
                        }
                    }
                    Button(action: { showingTransactionLog = true }) {
                        Label("transaction_log".t, systemImage: "clock.arrow.circlepath")
                    }
                    Button(action: { showingCategoryManager = true }) {
                        Label("manage_categories".t, systemImage: "tag")
                    }
                    Button(action: { showingStockGuide = true }) {
                        Label(lm.currentLanguage == .thai ? "วิธีใช้หน้าสต็อก" : "Stock guide",
                              systemImage: "questionmark.circle")
                    }
                    if sessionManager.can(.inventoryReceive) || sessionManager.can(.inventoryManage) {
                        Button(action: { showingDocumentScanner = true }) {
                            Label("stock_scan_title".t, systemImage: "doc.viewfinder")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.textPrimary)
                }
                .hoverEffect(.lift)
                .accessibilityLabel(lm.currentLanguage == .thai ? "เครื่องมือ" : "Tools")
            }

            if sessionManager.can(.inventoryManage) {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showingAddSheet = true } label: {
                            Label("add_stock_item".t, systemImage: "shippingbox")
                        }
                        Button { showingFinishedGoodSheet = true } label: {
                            Label("fg_quick_create_title".t, systemImage: "shippingbox.fill")
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .bold))
                            Text("add_stock_item".t)
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(.appAccent)
                    }
                    .hoverEffect(.lift)
                }
            }
        } else if selectedSection == .counts && activeBranch != nil
            && (sessionManager.can(.inventoryCount) || sessionManager.can(.inventoryManage)) {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: { showingCycleCount = true }) {
                    Label("inventory_cycle_count".t, systemImage: "checklist")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.appAccent)
                }
                .hoverEffect(.lift)
            }
        } else if selectedSection == .menu {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingFinishedGoodSheet = true } label: {
                    Label("fg_quick_create_title".t, systemImage: "shippingbox.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.appAccent)
                }
                .hoverEffect(.lift)
            }
        }
    }

    private var nativeSectionSegmentedControl: some View {
        HStack(spacing: 2) {
            ForEach(visibleSections, id: \.self) { section in
                let isSelected = selectedSection == section
                Button {
                    guard selectedSection != section else { return }
                    APHaptic.selection()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                        selectedSection = section
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: section.iconName)
                            .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                        Text(section.titleKey.t)
                            .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .foregroundColor(isSelected ? .white : .textSecondary)
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(Color.appAccent)
                                .matchedGeometryEffect(id: "INVENTORY_ACTIVE_TAB", in: sectionTabNamespace)
                                .shadow(color: Color.appAccent.opacity(0.35), radius: 6, x: 0, y: 2)
                        }
                    }
                }
                .buttonStyle(.plain)
                .hoverEffect(.lift)
            }
        }
        .padding(3)
        .background(Color.appSurfaceHigh.opacity(0.85), in: Capsule())
        .overlay(Capsule().stroke(Color.appBorderSubtle, lineWidth: 1))
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
        } else if showingQuickAdjustSheet {
            QuickStockAdjustSheet(item: item, viewModel: viewModel) {
                showingQuickAdjustSheet = false
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
        AnyView(
            VStack(spacing: APSpacing.xl) {
                ZStack {
                    Circle()
                        .fill(Color.appAccent.opacity(0.12))
                        .frame(width: 110, height: 110)
                        .blur(radius: 20)

                    Circle()
                        .fill(Color.appSurfaceHigh)
                        .frame(width: 88, height: 88)
                        .overlay(Circle().stroke(Color.appBorderSubtle, lineWidth: 1))

                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(APGradient.accent)
                }

                VStack(spacing: 8) {
                    Text("inventory_empty_title".t)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.textPrimary)

                    Text("inventory_empty_subtitle_v2".t)
                        .font(.system(size: 13))
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 380)
                }

                HStack(spacing: 12) {
                    if activeBranch != nil {
                        Button(action: {
                            APHaptic.trigger()
                            showingFinishedGoodSheet = true
                        }) {
                            Label("fg_quick_create_title".t, systemImage: "shippingbox.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(Color.appTeal, in: Capsule())
                                .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            APHaptic.trigger()
                            showingAddSheet = true
                        }) {
                            Label("add_stock_item".t, systemImage: "plus.circle.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(Color.appSurfaceHigh, in: Capsule())
                                .overlay(Capsule().stroke(Color.appBorderSubtle, lineWidth: 1))
                                .foregroundColor(.appAccent)
                        }
                        .buttonStyle(.plain)
                    }

                    if menuItems.isEmpty {
                        Button(action: {
                            APHaptic.trigger()
                            StoreSetupChecklist.requestFirstProductGuide()
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                                selectedSection = .menu
                            }
                        }) {
                            Label("first_product_start_cta".t, systemImage: "fork.knife")
                                .font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(Color.appSurfaceHigh, in: Capsule())
                                .overlay(Capsule().stroke(Color.appBorderSubtle, lineWidth: 1))
                                .foregroundColor(.textPrimary)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button(action: {
                            APHaptic.trigger()
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                                selectedSection = .menu
                            }
                        }) {
                            Label("inventory_products".t, systemImage: "fork.knife")
                                .font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(Color.appSurfaceHigh, in: Capsule())
                                .overlay(Capsule().stroke(Color.appBorderSubtle, lineWidth: 1))
                                .foregroundColor(.textPrimary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        )
    }

    // MARK: - Inventory Panel (Left)

    private var inventoryPanel: some View {
        AnyView(
            VStack(spacing: 0) {
                // Thin status strip (tappable → statusFilter); expiry/reorder open as sheets via chips
                inventoryStatsHeader

                // Single compact toolbar: search + kind + category + sort + view
                stockToolbar

                if isSelectionMode {
                    bulkActionBar
                }

                if !isAnimatedIn {
                    skeletonLoading
                } else if filteredInventory.isEmpty {
                    filteredEmptyState
                } else {
                    itemListView
                }
            }
            .frame(maxWidth: .infinity)
            .background(Color.appSurface)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.appBorderSubtle, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.035), radius: 12, y: 4)
        )
    }

    // MARK: - Compact Status Strip (replaces tall KPI cards + status chips)

    private var inventoryStatsHeader: some View {
        AnyView(
            ScrollView(.horizontal, showsIndicators: false) {
              HStack(spacing: APSpacing.sm) {
                Text(lm.currentLanguage == .thai ? "ภาพรวม" : "Overview")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.textPrimary)
                    .padding(.trailing, 2)

                Button { showingStockGuide = true } label: {
                    Label(lm.currentLanguage == .thai ? "วิธีใช้" : "Guide", systemImage: "questionmark.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.appTeal)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 44)
                        .background(Color.appTeal.opacity(0.09), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityHint(lm.currentLanguage == .thai
                                   ? "เปิดคำอธิบายสัญลักษณ์และขั้นตอนใช้งานหน้าสต็อก"
                                   : "Explains stock symbols and workflows")

                statusStripChip(
                    title: "filter_all".t,
                    value: "\(branchInventory.count)",
                    tag: "All",
                    color: .appAccent
                )
                if negativeStockCount > 0 {
                    statusStripChip(
                        title: lm.currentLanguage == .thai ? "สต็อกติดลบ (รอรับเข้า)" : "Negative",
                        value: "\(negativeStockCount)",
                        tag: "Negative Stock",
                        color: .appRose
                    )
                }
                statusStripChip(
                    title: "filter_low_stock".t,
                    value: "\(localLowStockCount)",
                    tag: "Low Stock",
                    color: .orange
                )
                statusStripChip(
                    title: "filter_out_of_stock".t,
                    value: "\(outOfStockCount)",
                    tag: "Out of Stock",
                    color: .textSecondary
                )

                let expiryTotal = expiryAlertCount.expired + expiryAlertCount.critical + expiryAlertCount.warning
                if expiryTotal > 0 {
                    statusStripChip(
                        title: lm.currentLanguage == .thai ? "ใกล้หมดอายุ" : "Expiring",
                        value: "\(expiryTotal)",
                        tag: "Expiry KPI",
                        color: .appAmber
                    )
                }
                if quarantineCount > 0 {
                    statusStripChip(
                        title: lm.currentLanguage == .thai ? "กักกัน" : "Quarantine",
                        value: "\(quarantineCount)",
                        tag: "Quarantine KPI",
                        color: .appRose
                    )
                }

                Text(LocalizationManager.shared.t("items_count_template", filteredInventory.count))
                    .font(.caption2)
                    .foregroundColor(.textTertiary)
                    .lineLimit(1)
              }
            }
            .padding(.horizontal, APSpacing.md)
            .padding(.vertical, APSpacing.sm)
            .background(Color.appSurface)
            .overlay(Rectangle().fill(Color.appDivider).frame(height: 1), alignment: .bottom)
        )
    }

    private func statusStripChip(title: String, value: String, tag: String, color: Color) -> some View {
        let selected = statusFilter == tag
        return Button {
            APHaptic.selection()
            statusFilter = tag
            resetPagination()
        } label: {
            HStack(spacing: 4) {
                Text(value)
                    .font(.system(size: 12, weight: .bold).monospacedDigit())
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundColor(selected ? .white : color)
            .padding(.horizontal, 9)
            .frame(minHeight: 44)
            .background(selected ? color : color.opacity(0.10))
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(selected ? Color.clear : color.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityLabel("\(title), \(value)")
        .accessibilityHint(lm.currentLanguage == .thai ? "แตะเพื่อกรองรายการ" : "Filter the inventory list")
        .accessibilityValue(selected ? (lm.currentLanguage == .thai ? "เลือกอยู่" : "Selected") : "")
    }

    @ViewBuilder
    private var compactExpiryChip: some View {
        let total = expiryAlertCount.expired + expiryAlertCount.critical + expiryAlertCount.warning
        if total > 0 {
            Button { showingExpiryAlerts = true } label: {
                HStack(spacing: 3) {
                    Image(systemName: expiryAlertCount.expired > 0
                          ? "xmark.circle.fill"
                          : "clock.badge.exclamationmark.fill")
                        .font(.system(size: 10))
                    Text("\(total)")
                        .font(.system(size: 11, weight: .bold).monospacedDigit())
                }
                .foregroundColor(expiryAlertCount.expired > 0 ? .appRose : .orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background((expiryAlertCount.expired > 0 ? Color.appRose : Color.orange).opacity(0.12))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var compactReorderChip: some View {
        let urgent = localReorderSuggestions.filter { $0.status == .outOfStock || $0.status == .atReorderPoint }.count
        if !localReorderSuggestions.isEmpty {
            Button { showingReorderSuggestions = true } label: {
                HStack(spacing: 3) {
                    Image(systemName: urgent > 0 ? "cart.badge.plus" : "cart")
                        .font(.system(size: 10))
                    Text("\(localReorderSuggestions.count)")
                        .font(.system(size: 11, weight: .bold).monospacedDigit())
                }
                .foregroundColor(urgent > 0 ? Color("appYellow") : .appTeal)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background((urgent > 0 ? Color("appYellow") : Color.appTeal).opacity(0.12))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private func refreshExpiryCount() {
        expiryAlertCount = viewModel.expiryAlertCount(branch: activeBranch)
    }

    // MARK: - Compact Stock Toolbar (search + filters in one row)

    private var stockToolbar: some View {
        AnyView(
            ScrollView(.horizontal, showsIndicators: false) {
              HStack(spacing: APSpacing.sm) {
                // Search
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13))
                        .foregroundColor(.textSecondary)
                    TextField("search_placeholder".t, text: $searchText)
                        .font(.subheadline)
                        .foregroundColor(.textPrimary)
                        .tint(.appAccent)
                        .focused($searchIsFocused)
                        .accessibilityLabel(lm.currentLanguage == .thai ? "ค้นหาสต็อก" : "Search inventory")
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                            debouncedSearchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 44)
                .background(Color.appSurfaceHigh)
                .clipShape(RoundedRectangle(cornerRadius: APRadius.sm, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: APRadius.sm, style: .continuous)
                        .stroke(Color.appBorderSubtle, lineWidth: 1)
                )
                .frame(minWidth: 140, maxWidth: .infinity)

                // Kind: compact segmented (no duplicate "All" vs status)
                Picker("", selection: $stockKindFilter) {
                    Text("stock_kind_all".t).tag("All")
                    Text("stock_kind_ingredients".t).tag("Ingredients")
                    Text("stock_kind_finished".t).tag("FinishedGoods")
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 300)
                .onChange(of: stockKindFilter) { _, _ in resetPagination() }

                // Category menu (replaces horizontal chip row)
                Menu {
                    Button {
                        selectedCategory = "All"
                        resetPagination()
                    } label: {
                        labelCheck(selectedCategory == "All", "filter_all".t)
                    }
                    ForEach(availableCategories, id: \.self) { cat in
                        Button {
                            selectedCategory = cat
                            resetPagination()
                        } label: {
                            labelCheck(selectedCategory == cat, "\(InventoryCategory.icon(for: cat)) \(cat) (\(categoryItemCounts[cat] ?? 0))")
                        }
                    }
                    if let uncatCount = categoryItemCounts["ไม่ระบุหมวดหมู่"], uncatCount > 0 {
                        Button {
                            selectedCategory = "ไม่ระบุหมวดหมู่"
                            resetPagination()
                        } label: {
                            labelCheck(selectedCategory == "ไม่ระบุหมวดหมู่", "\("no_category_option".t) (\(uncatCount))")
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "tag")
                            .font(.system(size: 11, weight: .semibold))
                        Text(categoryMenuTitle)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundColor(selectedCategory == "All" ? .textSecondary : .appTeal)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 44)
                    .background(selectedCategory == "All" ? Color.appSurfaceHigh : Color.appTeal.opacity(0.12))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.appBorderSubtle, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .hoverEffect(.lift)
                .accessibilityLabel(lm.currentLanguage == .thai ? "กรองตามหมวดหมู่" : "Filter by category")

                Menu {
                    ForEach(InventorySavedFilter.allCases) { filter in
                        Button {
                            savedFilter = filter
                            resetPagination()
                        } label: {
                            labelCheck(savedFilter == filter, filter.title(isThai: lm.currentLanguage == .thai))
                        }
                    }
                } label: {
                    Label(savedFilter.title(isThai: lm.currentLanguage == .thai), systemImage: "line.3.horizontal.decrease.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(savedFilter == .none ? .textPrimary : .appTeal)
                        .padding(.horizontal, 10).frame(minHeight: 44)
                        .background(savedFilter == .none ? Color.appSurfaceHigh : Color.appTeal.opacity(0.12))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.appBorderSubtle, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .hoverEffect(.lift)
                .accessibilityLabel(lm.currentLanguage == .thai ? "ตัวกรองที่บันทึก" : "Saved filters")

                // Sort menu
                Menu {
                    ForEach(InventorySortKey.allCases, id: \.self) { key in
                        Button {
                            if sortKey == key {
                                sortAscending.toggle()
                            } else {
                                sortKey = key
                                sortAscending = true
                            }
                        } label: {
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
                            .font(.system(size: 11, weight: .semibold))
                        Text(sortKey.displayName)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                    }
                    .foregroundColor(.textSecondary)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 44)
                    .background(Color.appSurfaceHigh)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.appBorderSubtle, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .hoverEffect(.lift)

                // View mode
                Button {
                    APHaptic.selection()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                        viewMode = viewMode == .table ? .card : .table
                    }
                } label: {
                    Label(
                        viewMode == .table
                            ? (lm.currentLanguage == .thai ? "ตาราง" : "Table")
                            : (lm.currentLanguage == .thai ? "การ์ด" : "Cards"),
                        systemImage: viewMode == .table ? "list.bullet" : "square.grid.2x2"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.textSecondary)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(Color.appSurfaceHigh)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .hoverEffect(.lift)
                .accessibilityHint(lm.currentLanguage == .thai ? "แตะเพื่อเปลี่ยนรูปแบบการแสดงผล" : "Changes the inventory layout")

                // Bulk select
                Button {
                    APHaptic.selection()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                        toggleSelectionMode()
                    }
                } label: {
                    Label(
                        isSelectionMode
                            ? (lm.currentLanguage == .thai ? "เสร็จสิ้น" : "Done")
                            : (lm.currentLanguage == .thai ? "เลือก" : "Select"),
                        systemImage: isSelectionMode ? "checkmark.circle.fill" : "checkmark.circle"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundColor(isSelectionMode ? .white : .textSecondary)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(isSelectionMode ? Color.appTeal : Color.appSurfaceHigh)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .hoverEffect(.lift)
                .accessibilityLabel(lm.currentLanguage == .thai ? "เลือกหลายรายการ" : "Select multiple items")
              }
            }
            .padding(.horizontal, APSpacing.md)
            .padding(.vertical, 8)
            .background(Color.appSurface)
            .overlay(Rectangle().fill(Color.appDivider).frame(height: 1), alignment: .bottom)
            .background {
                Button("") { searchIsFocused = true }
                    .keyboardShortcut("f", modifiers: [.command])
                    .opacity(0.001)
                    .frame(width: 1, height: 1)
                    .accessibilityHidden(true)
            }
        )
    }

    private var categoryMenuTitle: String {
        if selectedCategory == "All" {
            return "category_header".t
        }
        if selectedCategory == "ไม่ระบุหมวดหมู่" {
            return "no_category_option".t
        }
        return selectedCategory
    }

    @ViewBuilder
    private func labelCheck(_ selected: Bool, _ title: String) -> some View {
        if selected {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
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
            .disabled(selectedItems.isEmpty || activeBranch == nil)

            Button(action: { showingBulkTransferSheet = true }) {
                Label(lm.currentLanguage == .thai ? "ย้าย" : "Transfer", systemImage: "arrow.left.arrow.right")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .disabled(selectedItems.count != 1 || activeBranch == nil)

            Button(action: { showingBulkQuarantineSheet = true }) {
                Label(lm.currentLanguage == .thai ? "กักกัน" : "Quarantine", systemImage: "exclamationmark.shield.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.appAmber)
            }
            .buttonStyle(.bordered)
            .disabled(selectedItems.isEmpty || activeBranch == nil || !sessionManager.can(.inventoryRecall))

            Button(action: {
                exitSelectionMode()
                showingCycleCount = true
            }) {
                Label(lm.currentLanguage == .thai ? "ตรวจนับ" : "Count", systemImage: "checklist")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .disabled(activeBranch == nil || !(sessionManager.can(.inventoryCount) || sessionManager.can(.inventoryManage)))

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
            .disabled(selectedItems.isEmpty || activeBranch == nil)

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
            .disabled(selectedItems.isEmpty || activeBranch == nil)
        }
        .padding(.horizontal, APSpacing.md)
        .padding(.vertical, 8)
        .background(Color.appTeal.opacity(0.05))
        .overlay(Rectangle().fill(Color.appTeal.opacity(0.3)).frame(height: 1), alignment: .bottom)
    }

    // MARK: - Item List View (Paginated)

    private var itemListView: some View {
        AnyView(
            ScrollView(.vertical) {
                Group {
                    if effectiveViewMode == .table {
                        // Separate the axes. A bidirectional ScrollView can vertically
                        // center short table content, producing the large dead zone
                        // visible in the previous iPad layout.
                        ScrollView(.horizontal, showsIndicators: true) {
                            LazyVStack(spacing: 0) {
                                InventoryListHeader(
                                    resultCount: filteredInventory.count,
                                    sortKey: $sortKey,
                                    sortAscending: $sortAscending
                                )
                                ForEach(paginatedInventory) { item in
                                    itemRow(for: item)
                                }
                                if hasMoreItems {
                                    loadMoreButton
                                }
                            }
                            .frame(minWidth: 1190, alignment: .leading)
                        }
                    } else {
                        LazyVStack(spacing: APSpacing.sm) {
                            ForEach(paginatedInventory) { item in
                                itemRow(for: item)
                            }
                            if hasMoreItems {
                                loadMoreButton
                            }
                        }
                    }
                }
                .padding(APSpacing.md)
            }
            .scrollBounceBehavior(.basedOnSize)
            .transition(.opacity)
        )
    }

    @ViewBuilder
    private func itemRow(for item: InventoryItem) -> some View {
        if effectiveViewMode == .table {
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

                InventoryItemTableRow(
                    item: item,
                    nearestLot: nearestLotByItemId[item.id],
                    abcClass: abcClassification[item.id]
                ) {
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
                } onQuickAdjust: {
                    viewModel.selectedItem = item
                    showingQuickAdjustSheet = true
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
                } onQuickAdjust: {
                    viewModel.selectedItem = item
                    showingQuickAdjustSheet = true
                }
            }
        }
    }

    /// Fixed-width operational columns are useful at normal sizes; at accessibility
    /// sizes switch to cards so 200% text never clips or hides an action.
    private var effectiveViewMode: InventoryViewMode {
        dynamicTypeSize.isAccessibilitySize ? .card : viewMode
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

    // MARK: - Transaction Bottom Sheet

    private var transactionSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("transaction_log".t)
                        .font(.headline.weight(.semibold))
                        .foregroundColor(.textPrimary)
                    Text(LocalizationManager.shared.t("last_entries_template", min(filteredTransactionsList.count, 30)))
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                }
                Spacer()
                Image(systemName: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            }
            .padding(.horizontal, APSpacing.md)
            .padding(.vertical, 12)
            .background(Color.appSurface)

                Divider().background(Color.appDivider)

                if filteredTransactionsList.isEmpty {
                VStack(spacing: APSpacing.sm) {
                    Image(systemName: "tray")
                        .font(.system(size: 22))
                        .foregroundColor(.textTertiary)
                    Text("no_transactions_yet".t)
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.appBackground)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(Array(filteredTransactionsList.prefix(30))) { txn in
                                TransactionLogRow(txn: txn)
                            }
                        }
                        .padding(APSpacing.md)
                    }
                    .background(Color.appBackground)
                }
            }
            .background(Color.appBackground)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("done_btn".t) { showingTransactionLog = false }
                }
            }
        }
    }

    // MARK: - Helper Methods

    private func sortItems(_ items: [InventoryItem]) -> [InventoryItem] {
        if sortKey == .expiry {
            expiryManager.preloadLots()
        }
        defer {
            expiryManager.clearLotsCache()
        }
        return items.sorted { a, b in
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
            case .expiry:
                // FEFO sort: item with earliest nearest-expiry lot comes first
                let aExpiry = expiryManager.lots(for: a).first?.expiryDate
                let bExpiry = expiryManager.lots(for: b).first?.expiryDate
                switch (aExpiry, bExpiry) {
                case let (.some(da), .some(db)): result = da < db
                case (.some, .none):             result = true   // items with expiry before no-expiry
                case (.none, .some):             result = false
                case (.none, .none):             result = a.name < b.name
                }
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

    // MARK: - Decoupled Stats Refresher
    private func refreshStats() {
        let activeItems = inventory.filter { !$0.isDeleted }
        let filteredItems: [InventoryItem]
        if let branch = activeBranch {
            filteredItems = activeItems.filter { $0.branch?.id == branch.id }
        } else {
            filteredItems = activeItems
        }

        localLowStockCount = filteredItems.filter { $0.currentQuantity > 0 && $0.currentQuantity <= $0.reorderLevel }.count

        let activeTransactions = transactions.filter { !$0.isDeleted }
        if let branch = activeBranch {
            localFilteredTransactionsCount = activeTransactions.filter { $0.branch.id == branch.id }.count
        } else {
            localFilteredTransactionsCount = activeTransactions.count
        }

        localReorderSuggestions = safetyStockManager.generateSuggestions(branch: activeBranch)
        StockAlertEvaluator.refresh(modelContext: modelContext)
    }

    /// Focus stock list on an item opened from Notification Center.
    private func applyPendingInventoryFocus() {
        guard let idString = UserDefaults.standard.string(forKey: "pending_inventory_focus_id"),
              let uuid = UUID(uuidString: idString) else { return }
        UserDefaults.standard.removeObject(forKey: "pending_inventory_focus_id")

        selectedSection = .stock
        if let item = branchInventory.first(where: { $0.id == uuid }) {
            searchText = item.name
            debouncedSearchText = item.name
            selectedCategory = "All"
            statusFilter = "All"
            stockKindFilter = "All"
            resetPagination()
        }
    }

    /// Checklist / POS empty CTA: switch to Catalog (menu) so First Product Guide can present.
    private func applyPendingFirstProductGuide() {
        guard UserDefaults.standard.bool(forKey: StoreSetupChecklist.pendingFirstProductKey) else { return }
        guard menuItems.isEmpty else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedSection = .menu
        }
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

/// Primary Inventory sections. Visibility depends on `inventory_profile`.
/// Order = sellability first (Products), then ops (Stock / Recipes / Purchasing / Counts).
enum InventoryMainSection: String, CaseIterable, Identifiable, Hashable {
    case stock
    case menu
    case recipes
    case purchasing
    case counts

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .menu: return "inventory_products"
        case .stock: return "inventory_stock_items"
        case .recipes: return "inventory_recipes"
        case .purchasing: return "inventory_purchasing"
        case .counts: return "inventory_counts"
        }
    }

    var iconName: String {
        switch self {
        case .stock: return "shippingbox.fill"
        case .menu: return "square.grid.2x2.fill"
        case .recipes: return "book.closed.fill"
        case .purchasing: return "cart.fill"
        case .counts: return "checklist"
        }
    }

    /// Segment order prioritizes what merchants sell before back-of-house stock work.
    static func visible(for profile: String) -> [InventoryMainSection] {
        if profile == "simple" {
            return [.stock, .menu, .purchasing, .counts]
        }
        return [.stock, .menu, .recipes, .purchasing, .counts]
    }
}

enum InventoryViewMode: String {
    case table, card
}

private enum InventorySavedFilter: String, CaseIterable, Identifiable {
    case none, expiringThreeDays, negative, noRecipe, noSupplier, noLot
    var id: String { rawValue }
    func title(isThai: Bool) -> String {
        switch self {
        case .none: return isThai ? "ตัวกรองที่บันทึก" : "Saved filters"
        case .expiringThreeDays: return isThai ? "ใกล้หมดอายุ 3 วัน" : "Expires within 3 days"
        case .negative: return isThai ? "สต็อกติดลบ" : "Negative stock"
        case .noRecipe: return isThai ? "ไม่มีสูตร" : "No recipe"
        case .noSupplier: return isThai ? "ไม่มีซัพพลายเออร์" : "No supplier"
        case .noLot: return isThai ? "ไม่มี Lot" : "No lot"
        }
    }
}

// MARK: - Stock Guide

private struct InventoryPendingSyncView: View {
    @Environment(\.dismiss) private var dismiss
    let branchName: String
    let itemCount: Int
    let transactionCount: Int
    let lotCount: Int
    let controlCount: Int
    let lastSyncedAt: Date?
    let retry: () -> Void
    private var isThai: Bool { LocalizationManager.shared.currentLanguage == .thai }
    private var total: Int { itemCount + transactionCount + lotCount + controlCount }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: APSpacing.lg) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(branchName).font(.title3.bold())
                    Text(lastSyncedAt.map {
                        (isThai ? "ซิงก์ล่าสุด " : "Last synced ") + $0.formatted(date: .abbreviated, time: .shortened)
                    } ?? (isThai ? "ยังไม่เคยซิงก์" : "Never synced"))
                    .font(.caption).foregroundColor(.textSecondary)
                }

                VStack(spacing: 0) {
                    syncRow(isThai ? "รายการสินค้า" : "Items", itemCount, "shippingbox")
                    Divider()
                    syncRow(isThai ? "ธุรกรรม" : "Transactions", transactionCount, "arrow.left.arrow.right")
                    Divider()
                    syncRow(isThai ? "ล็อตสินค้า" : "Lots", lotCount, "square.stack.3d.up")
                    Divider()
                    syncRow(isThai ? "การกักกัน/ควบคุมล็อต" : "Lot controls", controlCount, "exclamationmark.shield")
                }
                .apCard(padding: 0)

                if total > 0 {
                    Button {
                        retry()
                        dismiss()
                    } label: {
                        Label(isThai ? "ลองซิงก์อีกครั้ง" : "Retry sync", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .apGlassButton(prominent: true, tint: .appTeal)
                    .frame(maxWidth: .infinity)
                } else {
                    Label(isThai ? "ข้อมูลของสาขานี้ซิงก์ครบแล้ว" : "This branch is fully synced",
                          systemImage: "checkmark.icloud.fill")
                        .foregroundColor(.appTeal)
                }
                Spacer()
            }
            .padding(APSpacing.lg)
            .background(Color.appBackground)
            .navigationTitle(isThai ? "สถานะการซิงก์" : "Sync status")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(isThai ? "เสร็จสิ้น" : "Done") { dismiss() }
                }
            }
        }
    }

    private func syncRow(_ title: String, _ count: Int, _ icon: String) -> some View {
        HStack(spacing: APSpacing.md) {
            Image(systemName: icon).foregroundColor(count == 0 ? .appTeal : .appAmber).frame(width: 24)
            Text(title)
            Spacer()
            Text("\(count)").font(.body.monospacedDigit().bold())
        }
        .padding(APSpacing.md)
        .accessibilityElement(children: .combine)
    }
}

private struct InventoryStockGuideView: View {
    @Environment(\.dismiss) private var dismiss
    private var isThai: Bool { LocalizationManager.shared.currentLanguage == .thai }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: APSpacing.lg) {
                    intro
                    abcGuide
                    trackingGuide
                    statusGuide
                    workflowGuide
                    tableGuide
                }
                .padding(APSpacing.lg)
            }
            .background(Color.appBackground)
            .navigationTitle(isThai ? "วิธีใช้หน้าสต็อก" : "Using Stock")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(isThai ? "เสร็จสิ้น" : "Done") { dismiss() }
                }
            }
        }
    }

    private var intro: some View {
        guideCard(icon: "shippingbox.fill", tint: .appTeal,
                  title: isThai ? "หน้าสต็อกใช้ทำอะไร" : "What this screen does") {
            Text(isThai
                 ? "ใช้ดูจำนวนคงเหลือ มูลค่า Lot วันหมดอายุ จุดสั่งซื้อ และสถานะของสินค้าในสาขาที่เลือก ตัวเลขทุกแถวอ้างอิงสาขาที่แสดงด้านบนเสมอ"
                 : "Review on-hand quantity, value, lots, expiry, reorder points, and item status for the selected branch. Every row is scoped to the branch shown above.")
        }
    }

    private var abcGuide: some View {
        guideCard(icon: "chart.bar.xaxis", tint: .appAccent,
                  title: isThai ? "ตัวอักษร A, B และ C คืออะไร" : "What A, B, and C mean") {
            Text(isThai
                 ? "ระบบจัดกลุ่ม ABC จากมูลค่าสต็อก เพื่อช่วยกำหนดความถี่ในการตรวจนับ ไม่ใช่เกรดคุณภาพของสินค้า"
                 : "ABC groups items by inventory value to help prioritize counting. It is not a product-quality grade.")
            guideLegendBadge("A", color: .appRose,
                             text: isThai ? "มูลค่าสูง — สำคัญที่สุด ควรตรวจนับบ่อย" : "High value — highest priority; count frequently")
            guideLegendBadge("B", color: .appAmber,
                             text: isThai ? "มูลค่าปานกลาง — ตรวจนับตามรอบปกติ" : "Medium value — count on a regular cycle")
            guideLegendBadge("C", color: .green,
                             text: isThai ? "มูลค่าต่ำกว่า — ตรวจนับเป็นรอบห่างกว่าได้" : "Lower value — can be counted less frequently")
            Text(isThai
                 ? "AlphaPos คำนวณจากมูลค่า จำนวนคงเหลือ × ต้นทุน และแบ่งตามมูลค่าสะสมโดยประมาณ: A 70% แรก, B ถึง 90%, ที่เหลือเป็น C"
                 : "AlphaPos calculates on-hand × unit cost and uses cumulative value: roughly the first 70% is A, up to 90% is B, and the remainder is C.")
                .font(.caption)
                .foregroundColor(.textSecondary)
        }
    }

    private var trackingGuide: some View {
        guideCard(icon: "link", tint: .appAccent,
                  title: isThai ? "ป้ายใต้ชื่อสินค้า" : "Labels below item names") {
            guideRow(icon: "fork.knife", title: isThai ? "ตัดตามสูตร" : "Recipe-based",
                     detail: isThai ? "ยอดจะลดอัตโนมัติเมื่อขายเมนูที่ใช้วัตถุดิบนี้" : "Stock decreases when a sold menu item uses this ingredient.")
            guideRow(icon: "shippingbox", title: isThai ? "วัตถุดิบ/นับตรง" : "Ingredient / direct",
                     detail: isThai ? "รับเข้า ตัดเสีย หรือปรับยอดจากการตรวจนับโดยตรง" : "Receive, waste, or adjust it directly through a stock count.")
            guideRow(icon: "takeoutbag.and.cup.and.straw", title: isThai ? "สินค้าสำเร็จรูป" : "Finished good",
                     detail: isThai ? "สินค้าที่เก็บยอดพร้อมขายโดยไม่ตัดจากสูตรวัตถุดิบ" : "A sellable item whose own finished quantity is tracked.")
        }
    }

    private var statusGuide: some View {
        guideCard(icon: "checkmark.circle", tint: .appTeal,
                  title: isThai ? "สีและสถานะ" : "Colors and statuses") {
            guideRow(icon: "checkmark.circle.fill", title: isThai ? "เขียว — สต็อกปกติ" : "Green — Stock OK",
                     detail: isThai ? "จำนวนสูงกว่าจุดสั่งซื้อ" : "Quantity is above the reorder point.", color: .appTeal)
            guideRow(icon: "exclamationmark.triangle.fill", title: isThai ? "ส้ม — สต็อกต่ำ/ใกล้หมดอายุ" : "Amber — Low/expiring",
                     detail: isThai ? "ควรตรวจสอบและเตรียมสั่งซื้อ" : "Review the item and prepare to reorder.", color: .appAmber)
            guideRow(icon: "xmark.circle.fill", title: isThai ? "แดง — หมดสต็อก/หมดอายุ" : "Red — Out/expired",
                     detail: isThai ? "ต้องดำเนินการก่อนขายหรือใช้งานต่อ" : "Action is required before further use or sale.", color: .appRose)
        }
    }

    private var workflowGuide: some View {
        guideCard(icon: "list.number", tint: .appAccent,
                  title: isThai ? "ขั้นตอนใช้งานทั่วไป" : "Common workflow") {
            numberedStep(1, isThai ? "เลือกสาขา" : "Select a branch",
                         isThai ? "แตะชื่อสาขาด้านบนก่อนดูหรือแก้ไขยอด" : "Tap the branch name before reviewing or changing quantities.")
            numberedStep(2, isThai ? "ค้นหาและกรอง" : "Search and filter",
                         isThai ? "ค้นหาด้วยชื่อหรือ SKU แล้วกรองวัตถุดิบ สินค้าสำเร็จรูป หมวดหมู่ หรือสถานะ" : "Search by name or SKU, then filter by kind, category, or status.")
            numberedStep(3, isThai ? "ดำเนินการกับสินค้า" : "Act on an item",
                         isThai ? "แตะ … ท้ายแถวเพื่อรับสินค้า ตัดของเสีย คืนผู้ขาย แก้ไข หรือดูประวัติ" : "Tap … at the end of a row to receive, waste, return, edit, or view history.")
            numberedStep(4, isThai ? "ตรวจนับหลายรายการ" : "Count multiple items",
                         isThai ? "แตะ เลือก เพื่อเลือกหลายแถว แล้วใช้คำสั่งตรวจนับหรือดำเนินการแบบกลุ่ม" : "Tap Select, choose rows, then run a count or another bulk action.")
        }
    }

    private var tableGuide: some View {
        guideCard(icon: "tablecells", tint: .textSecondary,
                  title: isThai ? "ความหมายของคอลัมน์" : "Table columns") {
            guideRow(icon: "number", title: isThai ? "หมายเลขล็อต" : "Lot number",
                     detail: isThai ? "ล็อตที่ใกล้หมดอายุหรือเกี่ยวข้องกับยอดคงเหลือ" : "The relevant or nearest-expiry lot.")
            guideRow(icon: "scalemass", title: isThai ? "จำนวนสต็อก" : "On hand",
                     detail: isThai ? "จำนวนที่พร้อมใช้ในหน่วยของสินค้า" : "Available quantity in the item's unit.")
            guideRow(icon: "bahtsign", title: isThai ? "ต้นทุนและมูลค่า" : "Cost and value",
                     detail: isThai ? "ต้นทุนต่อหน่วย และมูลค่ารวมของยอดคงเหลือ" : "Unit cost and total on-hand value.")
            guideRow(icon: "cart", title: isThai ? "จุดสั่งซื้อ" : "Reorder point",
                     detail: isThai ? "เมื่อยอดถึงหรือต่ำกว่าค่านี้ ระบบจะแจ้งว่าสต็อกต่ำ" : "At or below this level, the item is marked low stock.")
        }
    }

    private func guideCard<Content: View>(icon: String, tint: Color, title: String,
                                          @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: APSpacing.md) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundColor(tint)
            content()
                .font(.subheadline)
                .foregroundColor(.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .apCard()
    }

    private func guideLegendBadge(_ letter: String, color: Color, text: String) -> some View {
        HStack(spacing: APSpacing.sm) {
            Text(letter)
                .font(.caption.bold())
                .foregroundColor(.white)
                .frame(width: 26, height: 26)
                .background(color, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            Text(text)
        }
        .accessibilityElement(children: .combine)
    }

    private func guideRow(icon: String, title: String, detail: String, color: Color = .textSecondary) -> some View {
        HStack(alignment: .top, spacing: APSpacing.sm) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.semibold)
                Text(detail).font(.caption).foregroundColor(.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func numberedStep(_ number: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: APSpacing.sm) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundColor(.white)
                .frame(width: 26, height: 26)
                .background(Color.appAccent, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.semibold)
                Text(detail).font(.caption).foregroundColor(.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct BulkQuarantineSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sessionManager: AppSessionManager

    let items: [InventoryItem]
    let lots: [InventoryLot]
    let onComplete: () -> Void
    @State private var reason = ""
    @State private var errorMessage = ""

    private var selectedIds: Set<UUID> { Set(items.map(\.id)) }
    private var eligibleLots: [InventoryLot] {
        lots.filter {
            !$0.isDeleted && $0.remainingQuantity > 0
            && ($0.inventoryItem.map { selectedIds.contains($0.id) } ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent(LocalizationManager.shared.currentLanguage == .thai ? "สินค้าที่เลือก" : "Selected items",
                                   value: "\(items.count)")
                    LabeledContent(LocalizationManager.shared.currentLanguage == .thai ? "Lot ที่จะกักกัน" : "Lots to quarantine",
                                   value: "\(eligibleLots.count)")
                }
                Section(LocalizationManager.shared.currentLanguage == .thai ? "เหตุผลบังคับ" : "Required reason") {
                    TextField(LocalizationManager.shared.currentLanguage == .thai
                              ? "เช่น บรรจุภัณฑ์เสียหาย / อุณหภูมิผิดเกณฑ์"
                              : "For example: damaged packaging / temperature excursion",
                              text: $reason, axis: .vertical)
                        .lineLimit(2...4)
                        .accessibilityLabel(LocalizationManager.shared.currentLanguage == .thai ? "เหตุผลการกักกัน" : "Quarantine reason")
                }
                if !errorMessage.isEmpty {
                    Text(errorMessage).foregroundColor(.appRose)
                }
            }
            .navigationTitle(LocalizationManager.shared.currentLanguage == .thai ? "กักกัน Lot" : "Quarantine lots")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.Common.cancel.t) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(LocalizationManager.shared.currentLanguage == .thai ? "ยืนยันกักกัน" : "Confirm quarantine") {
                        quarantine()
                    }
                    .disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || eligibleLots.isEmpty)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    private func quarantine() {
        guard sessionManager.can(.inventoryRecall) || sessionManager.can(.inventoryManage) else {
            errorMessage = LocalizationManager.shared.currentLanguage == .thai
                ? "ไม่มีสิทธิ์กักกันสินค้า" : "You are not authorized to quarantine inventory."
            return
        }
        let normalizedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        for lot in eligibleLots {
            guard let item = lot.inventoryItem,
                  let branchId = lot.branch?.id ?? item.branch?.id else { continue }
            if let existing = try? modelContext.fetch(FetchDescriptor<InventoryLotControl>()).first(where: {
                !$0.isDeleted && $0.lotId == lot.id
            }) {
                existing.disposition = .quarantined
                existing.reasonCode = normalizedReason
                existing.isSynced = false
            } else {
                modelContext.insert(InventoryLotControl(
                    lotId: lot.id, inventoryItemId: item.id, branchId: branchId,
                    disposition: .quarantined, reasonCode: normalizedReason
                ))
            }
        }
        do {
            try modelContext.save()
            dismiss()
            onComplete()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
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
                    .frame(width: 280, alignment: .leading)
                Text("po_verify_lot_number".t)
                    .frame(width: 82, alignment: .leading)
                sortableColumn("inv_stock_quantity_col".t, key: .quantity, alignment: .trailing)
                    .frame(width: 88, alignment: .trailing)
                Text("inv_unit_cost_lbl".t)
                    .frame(width: 90, alignment: .trailing)
                sortableColumn("inv_stock_value_col".t, key: .cost, alignment: .trailing)
                    .frame(width: 82, alignment: .trailing)
                columnDivider
                Text("expiry_label".t)
                    .frame(width: 120, alignment: .leading)
                Text(LocalizationManager.shared.currentLanguage == .thai ? "จุดสั่งซื้อ" : "Reorder point")
                    .frame(width: 90, alignment: .trailing)
                columnDivider
                Text("Supplier")
                    .frame(width: 130, alignment: .leading)
                Text("status_label".t)
                    .frame(width: 108, alignment: .center)
                Text("actions_header".t)
                    .frame(width: 44, alignment: .trailing)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .padding(.horizontal, APSpacing.sm)
            .padding(.vertical, 9)
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

    private var columnDivider: some View {
        Rectangle()
            .fill(Color.appDivider)
            .frame(width: 1, height: 22)
            .padding(.horizontal, 8)
    }
}

// MARK: - Inventory Table Row (dense + expandable)

private struct InventoryItemTableRow: View {
    let item: InventoryItem
    let nearestLot: InventoryLot?
    var abcClass: String? = nil
    let onReceive: () -> Void
    let onWaste: () -> Void
    let onReturn: () -> Void
    let onEdit: () -> Void
    let onHistory: () -> Void
    var onQuickAdjust: (() -> Void)? = nil

    @State private var isExpanded = false

    private var isNegative: Bool { item.currentQuantity < 0 }
    private var isOut: Bool { item.currentQuantity == 0 }
    private var isLow: Bool { item.currentQuantity > 0 && item.currentQuantity <= item.reorderLevel }
    private var expiryStatus: ExpiryStatus? {
        guard let nearestLot, nearestLot.expiryDate != nil else { return nil }
        return nearestLot.expiryStatus(
            threshold: ExpiryAlertThreshold(
                warningDays: item.expiryWarningDays,
                criticalDays: item.expiryCriticalDays
            )
        )
    }
    private var status: (text: String, icon: String, color: Color) {
        if expiryStatus == .expired { return ("org_status_expired".t, "xmark.octagon.fill", .appRose) }
        if expiryStatus == .critical || expiryStatus == .warning {
            return ("expires_label".t, "clock.badge.exclamationmark.fill", .appAmber)
        }
        if isNegative {
            let label = LocalizationManager.shared.currentLanguage == .thai ? "สต็อกติดลบ (รอรับเข้า)" : "Negative"
            return (label, "arrow.down.forward.circle.fill", .appRose)
        }
        if isOut { return ("filter_out_of_stock".t, "xmark.circle.fill", .textSecondary) }
        if isLow { return ("filter_low_stock".t, "exclamationmark.triangle.fill", .appAmber) }
        return ("stock_ok".t, "checkmark.circle.fill", .appTeal)
    }
    private var expiryText: String {
        guard let nearestLot else {
            return LocalizationManager.shared.currentLanguage == .thai ? "ไม่มี Lot" : "No active lot"
        }
        guard let date = nearestLot.expiryDate else {
            return LocalizationManager.shared.currentLanguage == .thai ? "ไม่ระบุวันหมดอายุ" : "Expiry not set"
        }
        let days = nearestLot.daysUntilExpiry() ?? 0
        return "\(date.formatted(.dateTime.day().month(.abbreviated))) · \(days)d"
    }
    private var formattedStock: FormattedStockUnit {
        SmartUnitFormatter.format(quantity: item.currentQuantity, unit: item.unit)
    }
    private var quantityText: String {
        formattedStock.fullText
    }
    private var stockValue: Double { max(item.currentQuantity, 0) * item.costPrice }
    private var trackingMode: (text: String, color: Color) {
        if item.recipeUsages.contains(where: { !$0.isDeleted }) {
            return (LocalizationManager.shared.currentLanguage == .thai ? "ตัดตามสูตร" : "Recipe-based", .appAccent)
        }
        if item.isFinishedGoodSKU {
            return (LocalizationManager.shared.currentLanguage == .thai ? "สินค้าสำเร็จรูป" : "Finished good", .appTeal)
        }
        return (LocalizationManager.shared.currentLanguage == .thai ? "วัตถุดิบ/นับตรง" : "Ingredient / direct", .textPrimary)
    }

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
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 0) {
                    // Item identity owns a stable width so badges can never
                    // squeeze Thai text into one character per line.
                    HStack(spacing: 4) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.textTertiary)
                            .frame(width: 10)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(item.name)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.textPrimary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .layoutPriority(2)
                                if let abc = abcClass {
                                    Text(abc)
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 3)
                                        .padding(.vertical, 0.5)
                                        .background(abc == "A" ? Color.red.opacity(0.8) : abc == "B" ? Color.orange.opacity(0.8) : Color.green.opacity(0.8))
                                        .clipShape(RoundedRectangle(cornerRadius: 2))
                                        .accessibilityLabel(abcAccessibilityLabel(abc))
                                }
                            }
                            HStack(spacing: 5) {
                                Text(item.sku ?? "—")
                                    .font(.system(size: 11))
                                    .foregroundColor(.textSecondary)
                                    .lineLimit(1)
                                Text(trackingMode.text)
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(trackingMode.color)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(trackingMode.color.opacity(0.12))
                                    .clipShape(Capsule())
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                        }
                    }
                    .frame(width: 280, alignment: .leading)

                    Text(nearestLot?.lotNumber ?? (LocalizationManager.shared.currentLanguage == .thai ? "ไม่มี Lot" : "No lot"))
                        .font(.system(size: 12))
                        .foregroundColor(nearestLot == nil ? .appAmber : .textSecondary)
                        .lineLimit(1)
                        .frame(width: 82, alignment: .leading)

                    // On Hand (with Smart Auto-Scale)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(formattedStock.primaryText)
                            .font(.system(size: 13, weight: .semibold).monospacedDigit())
                            .foregroundColor(isLow || isOut ? .appRose : .textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        if let secondary = formattedStock.secondaryText {
                            Text(secondary)
                                .font(.system(size: 9).monospacedDigit())
                                .foregroundColor(.textSecondary)
                                .lineLimit(1)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(Color.appSurfaceHigh)
                                    .frame(height: 2)
                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(stockBarColor)
                                    .frame(width: geo.size.width * fillRatio, height: 2)
                            }
                        }
                        .frame(width: 52, height: 2)
                    }
                    .frame(width: 88, alignment: .trailing)

                    Text(String(format: "฿%.2f/%@", item.costPrice, item.unit))
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(width: 90, alignment: .trailing)

                    // Stock value
                    Text(String(format: "฿%.0f", stockValue))
                        .font(.system(size: 13, weight: .medium).monospacedDigit())
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: 82, alignment: .trailing)

                    Rectangle()
                        .fill(Color.appDivider)
                        .frame(width: 1, height: 28)
                        .padding(.horizontal, 8)

                    Text(expiryText)
                        .font(.system(size: 11, weight: expiryStatus == nil ? .regular : .medium))
                        .foregroundColor(expiryStatus == .expired ? .appRose : expiryStatus == .critical || expiryStatus == .warning ? .appAmber : .textSecondary)
                        .lineLimit(1)
                        .frame(width: 120, alignment: .leading)

                    Text("\(item.reorderLevel.formatted(.number.precision(.fractionLength(0...1)))) \(item.unit)")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundColor(isLow || isOut ? .appAmber : .textPrimary)
                        .lineLimit(1)
                        .frame(width: 90, alignment: .trailing)

                    Rectangle()
                        .fill(Color.appDivider)
                        .frame(width: 1, height: 28)
                        .padding(.horizontal, 8)

                    Group {
                        if let supplier = item.supplier {
                            Text(supplier.name)
                                .foregroundColor(.textSecondary)
                        } else {
                            Text(LocalizationManager.shared.currentLanguage == .thai ? "ไม่ระบุ" : "Not set")
                                .foregroundColor(.textSecondary)
                        }
                    }
                    .font(.system(size: 11, weight: item.supplier == nil ? .medium : .regular))
                    .lineLimit(1)
                    .frame(width: 130, alignment: .leading)

                    // Status
                    Label(status.text, systemImage: status.icon)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(status.color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(status.color.opacity(0.12))
                        .clipShape(Capsule())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: 108, alignment: .center)

                    // Overflow menu (receive/waste moved here)
                    Menu {
                        Button(action: { onQuickAdjust?() }) {
                            Label(LocalizationManager.shared.currentLanguage == .thai ? "นับสต๊อก / ปรับยอด" : "Physical Count / Adjust", systemImage: "checklist")
                        }
                        Button(action: onReceive) { Label("inventory_receive".t, systemImage: "plus.circle") }
                        Button(action: onWaste) { Label("inventory_waste".t, systemImage: "minus.circle") }
                        Button(action: onReturn) { Label("return_to_supplier".t, systemImage: "arrow.uturn.left.circle") }
                        Divider()
                        Button(action: onEdit) { Label("edit_details".t, systemImage: "pencil") }
                        Button(action: onHistory) { Label("movement_history".t, systemImage: "clock.arrow.circlepath") }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.textSecondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .frame(width: 44, alignment: .trailing)
                }
                .padding(.horizontal, APSpacing.sm)
                .padding(.vertical, 7)
                .frame(minHeight: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(item.name), \(abcClass.map { abcAccessibilityLabel($0) } ?? ""), \(trackingMode.text), \(quantityText), \(status.text), \(expiryText)")
            .accessibilityHint(LocalizationManager.shared.currentLanguage == .thai
                               ? "แตะเพื่อดูรายละเอียดและการดำเนินการ"
                               : "Open details and inventory actions")
            .accessibilityAddTraits(.isButton)

            if isExpanded {
                HStack(spacing: APSpacing.md) {
                    detailChip("category_header".t, item.category ?? "uncategorized".t)
                    detailChip("category_location_header".t, item.storageLocation ?? "no_location".t)
                    detailChip("inv_unit_cost_lbl".t, String(format: "฿%.2f/%@", item.costPrice, item.unit))
                    detailChip("inv_safety_stock_lbl".t, String(format: "%.0f %@", item.safetyStockLevel, item.unit))
                    detailChip("inv_lead_time_lbl".t, "\(item.leadTimeDays)d")
                    if let barcode = item.barcode, !barcode.isEmpty {
                        detailChip("Barcode", barcode)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, APSpacing.md)
                .padding(.bottom, 6)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Divider().background(Color.appDivider)
        }
        .background(Color.appSurface)
        .contextMenu {
            Button(action: { onQuickAdjust?() }) {
                Label(LocalizationManager.shared.currentLanguage == .thai ? "นับสต๊อก / ปรับยอด" : "Physical Count / Adjust", systemImage: "checklist")
            }
            Button(action: onReceive) { Label("inventory_receive".t, systemImage: "plus.circle") }
            Button(action: onWaste) { Label("inventory_waste".t, systemImage: "minus.circle") }
            Button(action: onReturn) { Label("return_to_supplier".t, systemImage: "arrow.uturn.left.circle") }
            Divider()
            Button(action: onEdit) { Label("edit_details".t, systemImage: "pencil") }
            Button(action: onHistory) { Label("movement_history".t, systemImage: "clock.arrow.circlepath") }
        }
        .hoverEffect(.highlight)
    }

    private func detailChip(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.textTertiary)
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.textPrimary)
                .lineLimit(1)
        }
    }

    private func abcAccessibilityLabel(_ abc: String) -> String {
        let isThai = LocalizationManager.shared.currentLanguage == .thai
        switch abc {
        case "A": return isThai ? "กลุ่ม A มูลค่าสูง ควรตรวจนับบ่อย" : "Class A, high value, count frequently"
        case "B": return isThai ? "กลุ่ม B มูลค่าปานกลาง" : "Class B, medium value"
        default: return isThai ? "กลุ่ม C มูลค่าต่ำกว่า" : "Class C, lower value"
        }
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
    var onQuickAdjust: (() -> Void)? = nil

    private var isNegative: Bool { item.currentQuantity < 0 }
    private var isOut: Bool { item.currentQuantity == 0 }
    private var isLow: Bool { item.currentQuantity > 0 && item.currentQuantity <= item.reorderLevel }

    private var fillRatio: Double {
        guard item.reorderLevel > 0 else { return 1.0 }
        let capacity = item.reorderLevel * 3.0
        return min(max(item.currentQuantity / capacity, 0.0), 1.0)
    }

    private var stockBarColor: Color {
        if isNegative { return .appRose }
        if fillRatio < 0.25 { return .appRose }
        if fillRatio < 0.50 { return .appAmber }
        return .appTeal
    }

    private var stockBarGradient: LinearGradient {
        if isNegative { return APGradient.destructive }
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
                        if isNegative {
                            APBadge(text: LocalizationManager.shared.currentLanguage == .thai ? "สต็อกติดลบ (รอรับเข้า)" : "Negative", color: .appRose, icon: "arrow.down.forward.circle.fill")
                        } else if isOut {
                            APBadge(text: "filter_out_of_stock".t, color: .textSecondary, icon: "xmark.circle.fill")
                        } else if isLow {
                            APBadge(text: "filter_low_stock".t, color: .appAmber, icon: "exclamationmark.triangle.fill")
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

                let formatted = SmartUnitFormatter.format(quantity: item.currentQuantity, unit: item.unit)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatted.primaryText)
                        .font(.headline).fontWeight(.bold)
                        .foregroundColor(isLow || isOut ? .appRose : .textPrimary)
                    if let secondary = formatted.secondaryText {
                        Text(secondary)
                            .font(.caption2)
                            .foregroundColor(.textSecondary)
                    }
                }
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

                Button(action: { onQuickAdjust?() }) {
                    Label(LocalizationManager.shared.currentLanguage == .thai ? "นับสต๊อก" : "Count", systemImage: "checklist")
                        .font(.caption).fontWeight(.semibold)
                        .foregroundColor(.appAccent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.appAccent.opacity(0.12))
                        .clipShape(Capsule())
                }

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
                    Button(action: { onQuickAdjust?() }) {
                        Label(LocalizationManager.shared.currentLanguage == .thai ? "นับสต๊อก / ปรับยอด" : "Physical Count / Adjust", systemImage: "checklist")
                    }
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
        .contextMenu {
            Button(action: { onQuickAdjust?() }) {
                Label(LocalizationManager.shared.currentLanguage == .thai ? "นับสต๊อก / ปรับยอด" : "Physical Count / Adjust", systemImage: "checklist")
            }
            Button(action: onReceive) { Label("inventory_receive".t, systemImage: "plus.circle") }
            Button(action: onWaste) { Label("inventory_waste".t, systemImage: "minus.circle") }
            Button(action: onReturn) { Label("return_to_supplier".t, systemImage: "arrow.uturn.left.circle") }
            Divider()
            Button(action: onEdit) { Label("edit_details".t, systemImage: "pencil") }
            Button(action: onHistory) { Label("movement_history".t, systemImage: "clock.arrow.circlepath") }
        }
        .hoverEffect(.lift)
    }
}

// MARK: - Transaction Log Row

private struct TransactionLogRow: View {
    let txn: InventoryTransaction

    private var typeConfig: (label: String, icon: String, color: Color, gradient: LinearGradient) {
        switch txn.movementType {
        case .receive:
            return ("inventory_receive".t, "plus.circle.fill", .appTeal, APGradient.positive)
        case .waste:
            return ("inventory_waste".t, "trash.fill", .appRose, APGradient.destructive)
        case .void:
            return ("reports_voids".t, "arrow.uturn.backward.circle.fill", .appTeal, APGradient.positive)
        case .sell:
            return ("sell_label".t, "cart.fill", Color.appAccent, APGradient.accent)
        case .returnToSupplier:
            return ("return_to_supplier".t, "arrow.uturn.left.circle.fill", .appAmber, APGradient.warning)
        case .transferOut:
            return ("xfer_out".t, "arrow.right.circle.fill", .appRose, APGradient.destructive)
        case .transferIn:
            return ("xfer_in".t, "arrow.left.circle.fill", .appTeal, APGradient.positive)
        case .refundReturn:
            return ("refund_label".t, "arrow.uturn.backward.circle.fill", .appAmber, APGradient.warning)
        case .productionConsume:
            return (LocalizationManager.shared.currentLanguage == .thai ? "ใช้วัตถุดิบผลิต" : "Production use",
                    "arrow.down.to.line.compact", .appRose, APGradient.destructive)
        case .productionOutput:
            return (LocalizationManager.shared.currentLanguage == .thai ? "รับผลผลิตจาก Batch" : "Batch output",
                    "frying.pan.fill", .appTeal, APGradient.positive)
        case .adjust, .opening:
            return ("adjustment_label".t, "arrow.left.and.right.circle.fill", .appAmber, APGradient.warning)
        }
    }

    var body: some View {
        let cfg = typeConfig
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(cfg.color.opacity(0.15))
                    .frame(width: 24, height: 24)
                Image(systemName: cfg.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(cfg.color)
            }

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(txn.item?.name ?? "unknown_item".t)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(String(format: "%@%.1f",
                                txn.quantity >= 0 ? "+" : "",
                                txn.quantity))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundColor(txn.quantity < 0 ? .appRose : .appTeal)
                }
                HStack(spacing: 4) {
                    Text(cfg.label)
                        .font(.caption.weight(.medium))
                        .foregroundColor(cfg.color)
                    Text("·")
                        .font(.caption)
                        .foregroundColor(.textTertiary)
                    Text(txn.notes ?? "no_details".t)
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(txn.updatedAt, format: .dateTime.day().month().hour().minute())
                        .font(.caption2)
                        .foregroundColor(.textTertiary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

// MARK: - Modal Input Helpers

@ViewBuilder
private func modalFormField<Content: View>(label: String, icon: String? = nil, hint: String? = nil, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 5) {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(.appAccent)
            }
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.textSecondary)
            if let hint {
                Spacer()
                Text(hint)
                    .font(.system(size: 10))
                    .foregroundColor(.textTertiary)
            }
        }
        content()
    }
}

@ViewBuilder
private func modalTextInput(_ placeholder: String, text: Binding<String>, keyboardType: UIKeyboardType = .default, prefix: String? = nil, suffix: String? = nil) -> some View {
    HStack(spacing: 6) {
        if let prefix {
            Text(prefix)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.textSecondary)
        }
        TextField(placeholder, text: text)
            .keyboardType(keyboardType)
            .font(.system(size: 14))
            .foregroundColor(.textPrimary)
        if let suffix, !suffix.isEmpty {
            Text(suffix)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.textTertiary)
        }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .background(Color.appSurfaceHigh)
    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    .overlay(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(Color.appBorderSubtle, lineWidth: 1)
    )
}

@ViewBuilder
private func inputField(_ placeholder: String, text: Binding<String>, keyboardType: UIKeyboardType = .default) -> some View {
    modalTextInput(placeholder, text: text, keyboardType: keyboardType)
}

// MARK: - Receive Stock Sheet

/// Limited stock workspace: no purchase costs, supplier data, recipes or edits.
struct OperationalStockView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var sessionManager: AppSessionManager
    @Query(filter: #Predicate<InventoryItem> { !$0.isDeleted }, sort: \InventoryItem.name) private var items: [InventoryItem]
    @State private var receiving: InventoryItem?
    @State private var search = ""
    private var branch: Branch? { try? BranchContext.shared.requireActiveBranch(in: modelContext) }
    private var visibleItems: [InventoryItem] {
        guard let branch else { return [] }
        return items.filter { $0.branch?.id == branch.id && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("คลังสาขา · ไม่แสดงต้นทุนและข้อมูลการจัดซื้อ")
                        .foregroundStyle(.secondary)
                    if branch == nil { Text("กรุณาเลือกสาขาก่อนดูสต๊อก") }
                }
                ForEach(visibleItems) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.name).font(.headline)
                        Text("คงเหลือ \(item.currentQuantity.formatted()) \(item.unit)")
                            .foregroundStyle(item.currentQuantity <= 0 ? Color.red : Color.primary)
                        if sessionManager.can(.inventoryReceive) {
                            Button("รับสต๊อก") { receiving = item }.buttonStyle(.borderless)
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "ค้นหาวัตถุดิบ")
            .navigationTitle("สต๊อกสำหรับปฏิบัติงาน")
            .sheet(item: $receiving) { item in
                if sessionManager.can(.productCostsView) {
                    ReceiveStockView(item: item, viewModel: InventoryViewModel(modelContext: modelContext)) { receiving = nil }
                } else {
                    OperationalReceiveStockView(item: item) { receiving = nil }
                }
            }
        }
    }
}

struct OperationalReceiveStockView: View {
    let item: InventoryItem
    let onComplete: () -> Void
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var sessionManager: AppSessionManager
    @State private var quantity = ""
    @State private var reason = ""
    @State private var lot = ""
    @State private var hasExpiry = false
    @State private var expiry = Date()
    @State private var saveError: String?
    @State private var submitted = false
    private var canReceive: Bool { sessionManager.can(.inventoryReceive) || sessionManager.can(.inventoryManage) }
    var body: some View {
        NavigationStack {
            Form {
                Section(item.name) {
                    Text("รับเพิ่มเป็นหน่วย \(item.unit)")
                    TextField("จำนวน", text: $quantity).keyboardType(.decimalPad)
                    TextField("เหตุผล / เอกสารอ้างอิง", text: $reason)
                    TextField("เลขล็อต", text: $lot)
                    Toggle("ระบุวันหมดอายุ", isOn: $hasExpiry)
                    if hasExpiry { DatePicker("หมดอายุ", selection: $expiry, displayedComponents: .date) }
                    Text("รับจำนวนด้วยต้นทุนเดิมในระบบ การตรวจราคาซื้อให้ผู้มีสิทธิ์ดำเนินการ")
                        .font(.caption).foregroundStyle(.secondary)
                    if let saveError { Text(saveError).foregroundStyle(.red) }
                }
            }
            .navigationTitle("รับสต๊อก")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ปิด") { onComplete() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("บันทึก") { receive() }
                        .disabled(!canReceive || submitted || (Double(quantity) ?? 0) <= 0 || reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
    private func receive() {
        guard canReceive, !submitted, let amount = Double(quantity), amount.isFinite, amount > 0,
              let branch = try? BranchContext.shared.requireActiveBranch(in: modelContext),
              branch.id == item.branch?.id else { return }
        submitted = true
        let before = item.currentQuantity
        InventoryViewModel(modelContext: modelContext).processReceiveWithExpiry(item: item, amountString: quantity,
            costString: "", notes: reason, expiryDate: hasExpiry ? expiry : nil,
            lotNumber: lot.isEmpty ? nil : lot, saveImmediately: false)
        modelContext.insert(AuditLog(employeeId: sessionManager.currentStaffSession?.employeeId,
            actionType: "operational_stock_receive", details: "Item \(item.id); branch \(branch.id); \(reason)",
            originalValue: before, newValue: item.currentQuantity))
        do { try modelContext.save(); onComplete() }
        catch { saveError = "บันทึกไม่สำเร็จ กรุณาให้ผู้ดูแลตรวจสอบ ห้ามรับซ้ำเพื่อป้องกันยอดซ้ำ" }
    }
}

struct ReceiveStockView: View {
    @EnvironmentObject private var sessionManager: AppSessionManager
    let item: InventoryItem
    let viewModel: InventoryViewModel
    let onComplete: () -> Void

    // Receive Modes: 0 = Direct Base/Scale Unit, 1 = Standard Package, 2 = Multi-Tier Packaging (ลัง/แพ็ก/ห่อ)
    @State private var receiveMode: Int = 1
    @State private var directUnit: String = "" // "kg" or "g"
    @State private var amountString = ""
    @State private var costString = ""
    @State private var noteText = ""

    // Mode 1: Standard Package
    @State private var packCountString = ""
    @State private var quantityPerPackString = ""
    @State private var packageUnit: UnitOfMeasure = .g
    @State private var packagePriceString = ""
    @State private var packagePriceMode: StockPackagePriceMode = .total

    // Mode 2: Multi-Tier Packaging (ลัง -> แพ็ก -> ห่อ)
    @State private var multiTierLevel: PackagingTierLevel = .crate
    @State private var multiTierCountString = "1"
    @State private var multiTierPacksPerCrateString = "12"
    @State private var multiTierPiecesPerPackString = "3"
    @State private var multiTierPieceSizeString = "500"
    @State private var multiTierPieceUnit: UnitOfMeasure = .g
    @State private var multiTierPriceString = ""
    @State private var multiTierPriceMode: StockPackagePriceMode = .total

    // Expiry Date & Lot Tracking (FEFO)
    @State private var hasExpiry = false
    @State private var expiryDate = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
    @State private var lotNumber = ""

    private var isThai: Bool { LocalizationManager.shared.currentLanguage == .thai }

    private var inventoryUnit: UnitOfMeasure? {
        UnitOfMeasure.parse(item.unit)
    }

    private var compatiblePackageUnits: [UnitOfMeasure] {
        guard let inventoryUnit else { return [] }
        return UnitOfMeasure.allCases.filter { $0.family == inventoryUnit.family }
    }

    private var activeDirectUnit: String {
        directUnit.isEmpty ? item.unit : directUnit
    }

    private var directCalculatedAmount: Double {
        let raw = Double(amountString.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0.0
        if item.unit == "g" && activeDirectUnit == "kg" {
            return raw * 1000.0
        } else if item.unit == "ml" && activeDirectUnit == "L" {
            return raw * 1000.0
        }
        return raw
    }

    private var directCalculatedCost: Double {
        let raw = Double(costString.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0.0
        if item.unit == "g" && activeDirectUnit == "kg" {
            return raw / 1000.0
        } else if item.unit == "ml" && activeDirectUnit == "L" {
            return raw / 1000.0
        }
        return raw
    }

    private var packageCalculation: StockPackageCalculation? {
        guard let inventoryUnit,
              let packCount = Double(packCountString),
              let quantityPerPack = Double(quantityPerPackString),
              let enteredPrice = Double(packagePriceString) else { return nil }
        return StockPackagePricing.calculate(
            packCount: packCount,
            quantityPerPack: quantityPerPack,
            packageUnit: packageUnit,
            inventoryUnit: inventoryUnit,
            enteredPrice: enteredPrice,
            priceMode: packagePriceMode
        )
    }

    private var multiTierCalculation: MultiTierPackagingCalculation? {
        guard let inventoryUnit,
              let count = Double(multiTierCountString),
              let packs = Double(multiTierPacksPerCrateString),
              let pieces = Double(multiTierPiecesPerPackString),
              let pieceSize = Double(multiTierPieceSizeString),
              let price = Double(multiTierPriceString) else { return nil }
        return MultiTierPackagingCalculation.calculate(
            level: multiTierLevel,
            enteredCount: count,
            packsPerCrate: packs,
            piecesPerPack: pieces,
            pieceSize: pieceSize,
            pieceUnit: multiTierPieceUnit,
            inventoryUnit: inventoryUnit,
            enteredPrice: price,
            priceMode: multiTierPriceMode,
            isThai: isThai
        )
    }

    private var canProcess: Bool {
        let hasPermission = sessionManager.can(.inventoryReceive) || sessionManager.can(.inventoryManage)
        guard hasPermission else { return false }
        if receiveMode == 0 {
            return directCalculatedAmount > 0
        } else if receiveMode == 1 {
            return packageCalculation != nil
        } else {
            return multiTierCalculation != nil
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: APSpacing.md) {
                        // Section 1: Item Summary
                        VStack(alignment: .leading, spacing: 10) {
                            sectionHeader("item_information".t)
                            HStack(spacing: 12) {
                                infoRow(label: "name_label".t, value: item.name)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                infoRow(label: "sku_label".t, value: item.sku ?? "N/A")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                let formatted = SmartUnitFormatter.format(quantity: item.currentQuantity, unit: item.unit)
                                infoRow(label: "on_hand_label".t, value: formatted.fullText)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .apCard()

                        // Section 2: Incoming Stock
                        VStack(alignment: .leading, spacing: 12) {
                            sectionHeader("incoming_stock".t)

                            // 3-Mode Switcher
                            Picker("", selection: $receiveMode) {
                                Text(isThai ? "หน่วยตรง (กก./ลิตร/หน่วย)" : "Direct Unit").tag(0)
                                Text(isThai ? "ตามแพ็ก (1 ระดับ)" : "Single Pack").tag(1)
                                Text(isThai ? "บรรจุภัณฑ์หลายชั้น (ลัง/แพ็ก/ห่อ)" : "Multi-Tier").tag(2)
                            }
                            .pickerStyle(.segmented)

                            if receiveMode == 0 {
                                // Direct Mode with Smart Unit Switcher
                                if item.unit == "g" {
                                    HStack(spacing: 8) {
                                        Text(isThai ? "หน่วยที่มาส่ง:" : "Receiving Unit:")
                                            .font(.caption.weight(.medium))
                                            .foregroundColor(.textSecondary)
                                        Button("กรัม (g)") { directUnit = "g" }
                                            .font(.caption.weight(activeDirectUnit == "g" ? .bold : .regular))
                                            .foregroundColor(activeDirectUnit == "g" ? .white : .textPrimary)
                                            .padding(.horizontal, 10).padding(.vertical, 4)
                                            .background(activeDirectUnit == "g" ? Color.appAccent : Color.appSurfaceHigh)
                                            .clipShape(Capsule())
                                        Button("กิโลกรัม (kg)") { directUnit = "kg" }
                                            .font(.caption.weight(activeDirectUnit == "kg" ? .bold : .regular))
                                            .foregroundColor(activeDirectUnit == "kg" ? .white : .textPrimary)
                                            .padding(.horizontal, 10).padding(.vertical, 4)
                                            .background(activeDirectUnit == "kg" ? Color.appAccent : Color.appSurfaceHigh)
                                            .clipShape(Capsule())
                                        Spacer()
                                    }
                                } else if item.unit == "ml" {
                                    HStack(spacing: 8) {
                                        Text(isThai ? "หน่วยที่มาส่ง:" : "Receiving Unit:")
                                            .font(.caption.weight(.medium))
                                            .foregroundColor(.textSecondary)
                                        Button("มิลลิลิตร (ml)") { directUnit = "ml" }
                                            .font(.caption.weight(activeDirectUnit == "ml" ? .bold : .regular))
                                            .foregroundColor(activeDirectUnit == "ml" ? .white : .textPrimary)
                                            .padding(.horizontal, 10).padding(.vertical, 4)
                                            .background(activeDirectUnit == "ml" ? Color.appAccent : Color.appSurfaceHigh)
                                            .clipShape(Capsule())
                                        Button("ลิตร (L)") { directUnit = "L" }
                                            .font(.caption.weight(activeDirectUnit == "L" ? .bold : .regular))
                                            .foregroundColor(activeDirectUnit == "L" ? .white : .textPrimary)
                                            .padding(.horizontal, 10).padding(.vertical, 4)
                                            .background(activeDirectUnit == "L" ? Color.appAccent : Color.appSurfaceHigh)
                                            .clipShape(Capsule())
                                        Spacer()
                                    }
                                }

                                HStack(spacing: 12) {
                                    modalFormField(label: isThai ? "จำนวนที่รับ (\(activeDirectUnit))" : "Quantity (\(activeDirectUnit))", icon: "plus.circle.fill") {
                                        modalTextInput("0.0", text: $amountString, keyboardType: .decimalPad, suffix: activeDirectUnit)
                                    }
                                    .frame(maxWidth: .infinity)

                                    modalFormField(label: isThai ? "ต้นทุนต่อ \(activeDirectUnit)" : "Cost per \(activeDirectUnit)", icon: "banknote.fill") {
                                        modalTextInput("0.00", text: $costString, keyboardType: .decimalPad, prefix: "฿", suffix: "/\(activeDirectUnit)")
                                    }
                                    .frame(maxWidth: .infinity)
                                }

                                if directCalculatedAmount > 0 && activeDirectUnit != item.unit {
                                    HStack {
                                        Label(
                                            isThai
                                                ? "ระบบจะเพิ่มเข้าสต๊อก: \(String(format: "%.1f", directCalculatedAmount)) \(item.unit) (ต้นทุน ฿\(String(format: "%.4f", directCalculatedCost))/\(item.unit))"
                                                : "Will add: \(String(format: "%.1f", directCalculatedAmount)) \(item.unit) (฿\(String(format: "%.4f", directCalculatedCost))/\(item.unit))",
                                            systemImage: "arrow.left.arrow.right"
                                        )
                                        .font(.caption.weight(.medium))
                                        .foregroundColor(.appTeal)
                                        Spacer()
                                    }
                                    .padding(8)
                                    .background(Color.appTeal.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                }

                            } else if receiveMode == 1 {
                                // Single Pack Mode
                                HStack(spacing: 12) {
                                    modalFormField(label: isThai ? "จำนวนแพ็กที่ซื้อ" : "Packages purchased", icon: "shippingbox.fill") {
                                        modalTextInput("0", text: $packCountString, keyboardType: .decimalPad, suffix: isThai ? "แพ็ก" : "packs")
                                    }
                                    .frame(maxWidth: .infinity)

                                    modalFormField(label: isThai ? "ปริมาณต่อแพ็ก" : "Quantity per package", icon: "scalemass.fill") {
                                        HStack(spacing: 8) {
                                            modalTextInput("0", text: $quantityPerPackString, keyboardType: .decimalPad)
                                            Picker("", selection: $packageUnit) {
                                                ForEach(compatiblePackageUnits) { unit in
                                                    Text(unit.rawValue).tag(unit)
                                                }
                                            }
                                            .labelsHidden()
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                }

                                Picker("", selection: $packagePriceMode) {
                                    Text(isThai ? "ราคารวม" : "Total price").tag(StockPackagePriceMode.total)
                                    Text(isThai ? "ราคาต่อแพ็ก" : "Price per package").tag(StockPackagePriceMode.perPack)
                                }
                                .pickerStyle(.segmented)

                                modalFormField(
                                    label: packagePriceMode == .total
                                        ? (isThai ? "ราคารวมทั้งหมด" : "Total purchase price")
                                        : (isThai ? "ราคาต่อแพ็ก" : "Price per package"),
                                    icon: "banknote.fill"
                                ) {
                                    modalTextInput("0.00", text: $packagePriceString, keyboardType: .decimalPad, prefix: "฿")
                                }

                                if let calculation = packageCalculation {
                                    HStack {
                                        Label(
                                            String(format: isThai ? "รับเข้า %.2f %@" : "Receive %.2f %@", calculation.receivedQuantity, item.unit),
                                            systemImage: "shippingbox.and.arrow.backward.fill"
                                        )
                                        Spacer()
                                        Text(String(format: isThai ? "ต้นทุนอัตโนมัติ ฿%.4f/%@" : "Auto cost ฿%.4f/%@", calculation.unitCost, item.unit))
                                    }
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.appTeal)
                                    .padding(10)
                                    .background(Color.appTeal.opacity(0.10))
                                    .clipShape(RoundedRectangle(cornerRadius: APRadius.sm))
                                }

                            } else {
                                // Multi-Tier Packaging Mode (ลัง -> แพ็ก -> ห่อ)
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(isThai ? "เลือกระดับบรรจุภัณฑ์ที่มาส่งวันนี้:" : "Select delivery packaging level:")
                                        .font(.caption.weight(.medium))
                                        .foregroundColor(.textSecondary)

                                    Picker("", selection: $multiTierLevel) {
                                        ForEach(PackagingTierLevel.allCases) { lvl in
                                            Text(lvl.title(isThai: isThai)).tag(lvl)
                                        }
                                    }
                                    .pickerStyle(.segmented)

                                    HStack(spacing: 12) {
                                        modalFormField(
                                            label: isThai ? "จำนวน\(multiTierLevel.title(isThai: true))ที่รับ" : "Quantity",
                                            icon: "archivebox.fill"
                                        ) {
                                            modalTextInput("1", text: $multiTierCountString, keyboardType: .decimalPad)
                                        }
                                        .frame(maxWidth: .infinity)

                                        modalFormField(
                                            label: multiTierPriceMode == .total ? (isThai ? "ราคารวม" : "Total price") : (isThai ? "ราคาต่อหน่วย" : "Price per unit"),
                                            icon: "banknote.fill"
                                        ) {
                                            modalTextInput("0.00", text: $multiTierPriceString, keyboardType: .decimalPad, prefix: "฿")
                                        }
                                        .frame(maxWidth: .infinity)
                                    }

                                    Picker("", selection: $multiTierPriceMode) {
                                        Text(isThai ? "ราคารวมทั้งหมด" : "Total price").tag(StockPackagePriceMode.total)
                                        Text(isThai ? "ราคาต่อ\(multiTierLevel.title(isThai: true))" : "Price per unit").tag(StockPackagePriceMode.perPack)
                                    }
                                    .pickerStyle(.segmented)

                                    // Hierarchy Definition Card
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(isThai ? "โครงสร้างบรรจุภัณฑ์ (เช่น 1 ลัง = 12 แพ็ก, 1 แพ็ก = 3 ห่อ, 1 ห่อ = 500g):" : "Packaging Breakdown:")
                                            .font(.caption2.weight(.bold))
                                            .foregroundColor(.textSecondary)

                                        HStack(spacing: 8) {
                                            if multiTierLevel == .crate {
                                                modalFormField(label: isThai ? "แพ็ก/ลัง" : "Packs/Crate") {
                                                    modalTextInput("12", text: $multiTierPacksPerCrateString, keyboardType: .numberPad)
                                                }
                                                .frame(maxWidth: .infinity)
                                            }

                                            if multiTierLevel == .crate || multiTierLevel == .pack {
                                                modalFormField(label: isThai ? "ห่อ/แพ็ก" : "Bags/Pack") {
                                                    modalTextInput("3", text: $multiTierPiecesPerPackString, keyboardType: .numberPad)
                                                }
                                                .frame(maxWidth: .infinity)
                                            }

                                            modalFormField(label: isThai ? "ขนาดต่อห่อ" : "Size/Bag") {
                                                HStack(spacing: 4) {
                                                    modalTextInput("500", text: $multiTierPieceSizeString, keyboardType: .decimalPad)
                                                    Picker("", selection: $multiTierPieceUnit) {
                                                        ForEach(compatiblePackageUnits) { unit in
                                                            Text(unit.rawValue).tag(unit)
                                                        }
                                                    }
                                                    .labelsHidden()
                                                }
                                            }
                                            .frame(maxWidth: .infinity)
                                        }
                                    }
                                    .padding(10)
                                    .background(Color.appSurfaceHigh)
                                    .clipShape(RoundedRectangle(cornerRadius: APRadius.sm))

                                    // Real-time Multi-Tier Summary Banner
                                    if let calc = multiTierCalculation {
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack {
                                                Image(systemName: "checkmark.seal.fill")
                                                    .foregroundColor(.appTeal)
                                                Text(calc.summaryText)
                                                    .font(.caption.weight(.bold))
                                                    .foregroundColor(.textPrimary)
                                                Spacer()
                                                Text(String(format: "รวม ฿%.2f", calc.totalCost))
                                                    .font(.caption.weight(.semibold))
                                                    .foregroundColor(.textPrimary)
                                            }
                                            let formatted = SmartUnitFormatter.format(quantity: calc.totalBaseQuantity, unit: item.unit)
                                            Text(isThai
                                                 ? "📥 จะเพิ่มเข้าสต๊อก: \(formatted.fullText) · ต้นทุน ฿\(String(format: "%.4f", calc.unitCost))/\(item.unit)"
                                                 : "📥 Adding to stock: \(formatted.fullText) · Cost ฿\(String(format: "%.4f", calc.unitCost))/\(item.unit)")
                                                .font(.caption.weight(.semibold))
                                                .foregroundColor(.appTeal)
                                        }
                                        .padding(10)
                                        .background(Color.appTeal.opacity(0.12))
                                        .clipShape(RoundedRectangle(cornerRadius: APRadius.sm))
                                    }
                                }
                            }

                            modalFormField(label: "invoice_reference_note".t, icon: "doc.text.fill") {
                                modalTextInput("invoice_reference_note".t, text: $noteText)
                            }
                        }
                        .apCard()

                        // Section 3: Expiry & Lot Tracking
                        VStack(alignment: .leading, spacing: 10) {
                            sectionHeader("expiry_lot_section_title".t)
                            ExpiryDatePicker(
                                hasExpiry: $hasExpiry,
                                expiryDate: $expiryDate,
                                lotNumber: $lotNumber
                            )
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
                        guard sessionManager.can(.inventoryReceive) || sessionManager.can(.inventoryManage) else { return }
                        let receiveAmount: String
                        let receiveCost: String
                        var finalNote = noteText

                        if receiveMode == 0 {
                            receiveAmount = String(directCalculatedAmount)
                            receiveCost = String(directCalculatedCost)
                            if activeDirectUnit != item.unit {
                                let conversionNote = "Received \(amountString) \(activeDirectUnit)"
                                finalNote = finalNote.isEmpty ? conversionNote : "\(finalNote) (\(conversionNote))"
                            }
                        } else if receiveMode == 1, let calculation = packageCalculation {
                            receiveAmount = String(calculation.receivedQuantity)
                            receiveCost = String(calculation.unitCost)
                        } else if receiveMode == 2, let calculation = multiTierCalculation {
                            receiveAmount = String(calculation.totalBaseQuantity)
                            receiveCost = String(calculation.unitCost)
                            let tierNote = calculation.summaryText
                            finalNote = finalNote.isEmpty ? tierNote : "\(finalNote) (\(tierNote))"
                        } else {
                            return
                        }

                        viewModel.processReceiveWithExpiry(
                            item: item,
                            amountString: receiveAmount,
                            costString: receiveCost,
                            notes: finalNote,
                            expiryDate: hasExpiry ? expiryDate : nil,
                            lotNumber: hasExpiry ? lotNumber : nil
                        )
                        onComplete()
                    }
                    .disabled(!canProcess)
                    .foregroundStyle(APGradient.positive)
                }
            }
        }
        .apColorScheme()
        .onAppear {
            if let inventoryUnit {
                packageUnit = inventoryUnit
                multiTierPieceUnit = inventoryUnit
                if inventoryUnit == .g {
                    directUnit = "kg"
                } else if inventoryUnit == .ml {
                    directUnit = "L"
                }
            } else {
                receiveMode = 0
            }
        }
    }
}

// MARK: - Waste/Adjust Stock Sheet

struct WasteStockView: View {
    @EnvironmentObject private var sessionManager: AppSessionManager
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
                        // Section 1: Item Summary
                        VStack(alignment: .leading, spacing: 10) {
                            sectionHeader("item_information".t)
                            HStack(spacing: 12) {
                                infoRow(label: "Name", value: item.name)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                infoRow(label: "On Hand", value: String(format: "%.1f %@", item.currentQuantity, item.unit))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .apCard()

                        // Section 2: Adjustment & Reason
                        VStack(alignment: .leading, spacing: 12) {
                            sectionHeader("adjustment_label".t)

                            HStack(spacing: 12) {
                                modalFormField(label: "quantity_label".t, icon: "minus.circle.fill") {
                                    modalTextInput("0.0", text: $amountString, keyboardType: .decimalPad, suffix: item.unit)
                                }
                                .frame(maxWidth: .infinity)

                                modalFormField(label: "reason_label".t, icon: "exclamationmark.bubble.fill") {
                                    Picker("reason_label".t, selection: $reasonSelection) {
                                        ForEach(reasons, id: \.self) { reason in
                                            Text(reason == "Spoilage" ? "reason_spoilage".t :
                                                 (reason == "Wastage" ? "reason_wastage".t :
                                                 (reason == "Spillage/Accident" ? "reason_spillage_accident".t :
                                                  "reason_audit_correction".t)))
                                            .tag(reason)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(Color.appSurfaceHigh)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.appBorderSubtle, lineWidth: 1))
                                }
                                .frame(maxWidth: .infinity)
                            }

                            modalFormField(label: "additional_details".t, icon: "text.alignleft") {
                                modalTextInput("additional_details".t, text: $noteText)
                            }
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
                        guard sessionManager.can(.inventoryAdjust) || sessionManager.can(.inventoryManage) else { return }
                        viewModel.processWaste(item: item, amountString: amountString,
                                               reasonSelection: reasonSelection, notes: noteText)
                        onComplete()
                    }
                    .disabled(amountString.isEmpty || !(sessionManager.can(.inventoryAdjust) || sessionManager.can(.inventoryManage)))
                    .foregroundStyle(APGradient.destructive)
                }
            }
        }
        .apColorScheme()
    }
}

// MARK: - Bulk Receive Sheet

struct BulkReceiveSheet: View {
    @EnvironmentObject private var sessionManager: AppSessionManager
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

                        VStack(alignment: .leading, spacing: 12) {
                            sectionHeader("incoming_stock".t)
                            modalFormField(label: "quantity_per_item".t, icon: "plus.circle.fill") {
                                modalTextInput("0.0", text: $amountString, keyboardType: .decimalPad)
                            }
                            modalFormField(label: "invoice_reference_note".t, icon: "doc.text.fill") {
                                modalTextInput("invoice_reference_note".t, text: $noteText)
                            }
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
                        guard sessionManager.can(.inventoryReceive) || sessionManager.can(.inventoryManage) else { return }
                        for item in items {
                            viewModel.processReceive(item: item, amountString: amountString,
                                                      costString: "", notes: noteText.isEmpty ? "Bulk receive" : noteText)
                        }
                        onComplete()
                    }
                    .disabled(amountString.isEmpty || !(sessionManager.can(.inventoryReceive) || sessionManager.can(.inventoryManage)))
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

                        VStack(alignment: .leading, spacing: 12) {
                            sectionHeader("adjustment_label".t)

                            HStack(spacing: 12) {
                                modalFormField(label: "quantity_per_item".t, icon: "minus.circle.fill") {
                                    modalTextInput("0.0", text: $amountString, keyboardType: .decimalPad)
                                }
                                .frame(maxWidth: .infinity)

                                modalFormField(label: "reason_label".t, icon: "exclamationmark.bubble.fill") {
                                    Picker("reason_label".t, selection: $reasonSelection) {
                                        ForEach(reasons, id: \.self) { reason in
                                            Text(reason).tag(reason)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(Color.appSurfaceHigh)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.appBorderSubtle, lineWidth: 1))
                                }
                                .frame(maxWidth: .infinity)
                            }

                            modalFormField(label: "additional_details".t, icon: "text.alignleft") {
                                modalTextInput("additional_details".t, text: $noteText)
                            }
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
                        let wasteAmount = Double(amountString) ?? 0
                        viewModel.bulkWaste(
                            items: items,
                            amount: wasteAmount,
                            reason: reasonSelection,
                            notes: noteText.isEmpty ? "Bulk waste" : noteText
                        )
                        onComplete()
                    }
                    .disabled(amountString.isEmpty || (Double(amountString) ?? 0) <= 0)
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

    // Safety Stock & Lead Time
    @State private var safetyStockString = "0.0"
    @State private var maxStockString = "0.0"
    @State private var leadTimeDaysString = "1"
    @State private var outOfStockPolicy: OutOfStockPolicy = .allowNegative

    private var normalizedEntry: NormalizedInventoryMeasurement {
        InventoryUnitNormalization.normalize(
            quantity: Double(reorderString) ?? 0,
            unit: unit,
            unitCost: Double(costString) ?? 0
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: APSpacing.md) {
                        // Section 1: Basic Information (2 Columns)
                        VStack(alignment: .leading, spacing: 12) {
                            sectionHeader("item_details".t)

                            // Row 1: Name & SKU
                            HStack(spacing: 12) {
                                modalFormField(label: "item_name_placeholder".t, icon: "shippingbox.fill") {
                                    modalTextInput("item_name_placeholder".t, text: $name)
                                }
                                .frame(maxWidth: .infinity)

                                modalFormField(label: "sku_code_placeholder".t, icon: "barcode") {
                                    modalTextInput("sku_code_placeholder".t, text: $sku)
                                }
                                .frame(maxWidth: .infinity)
                            }

                            // Row 2: Barcode & Unit
                            HStack(spacing: 12) {
                                modalFormField(label: "barcode_placeholder".t, icon: "qrcode.viewfinder") {
                                    modalTextInput("barcode_placeholder".t, text: $barcode)
                                }
                                .frame(maxWidth: .infinity)

                                modalFormField(label: "unit_placeholder".t, icon: "scalemass.fill") {
                                    StandardUnitPickerMenu(unit: $unit, isFormFieldStyle: true)
                                }
                                .frame(maxWidth: .infinity)
                            }

                            // Row 3: Category & Location
                            HStack(spacing: 12) {
                                modalFormField(label: "category_placeholder".t, icon: "tag.fill") {
                                    modalTextInput("category_placeholder".t, text: $category)
                                }
                                .frame(maxWidth: .infinity)

                                modalFormField(label: "storage_location_placeholder".t, icon: "mappin.and.ellipse") {
                                    modalTextInput("storage_location_placeholder".t, text: $storageLocation)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .apCard()

                        // Section 2: Reordering, Cost & Safety Stock (2 Columns)
                        VStack(alignment: .leading, spacing: 12) {
                            sectionHeader("reordering_costs".t)

                            // Row 1: Cost Price & Reorder Point
                            HStack(spacing: 12) {
                                modalFormField(label: "unit_cost_price_placeholder".t, icon: "banknote.fill") {
                                    modalTextInput("0.00", text: $costString, keyboardType: .decimalPad, prefix: "฿")
                                }
                                .frame(maxWidth: .infinity)

                                modalFormField(label: "reorder_trigger_level_placeholder".t, icon: "exclamationmark.triangle.fill") {
                                    modalTextInput("0.0", text: $reorderString, keyboardType: .decimalPad, suffix: unit)
                                }
                                .frame(maxWidth: .infinity)
                            }

                            if normalizedEntry.unit != unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                                Label(
                                    "ระบบจะจัดเก็บเป็น ฿\(String(format: "%.4f", normalizedEntry.unitCost))/\(normalizedEntry.unit)",
                                    systemImage: "arrow.left.arrow.right"
                                )
                                .font(.caption.weight(.medium))
                                .foregroundColor(.appTeal)
                            }

                            Divider().background(Color.appDivider)

                            // Safety Stock & Lead Time (2-Column Grid)
                            SafetyStockFields(
                                safetyStockString: $safetyStockString,
                                maxStockString: $maxStockString,
                                leadTimeDaysString: $leadTimeDaysString,
                                unit: unit
                            )
                        }
                        .apCard()

                        // Section 3: Policy & Supplier
                        VStack(alignment: .leading, spacing: 12) {
                            sectionHeader("classification_location".t)

                            outOfStockPolicyCard(selection: $outOfStockPolicy)

                            Divider().background(Color.appDivider)

                            modalFormField(label: "supplier_label".t, icon: "building.2.fill") {
                                Picker("supplier_label".t, selection: $selectedSupplierId) {
                                    Text("no_supplier_option".t).tag(nil as UUID?)
                                    ForEach(suppliers) { sup in
                                        Text(sup.name).tag(sup.id as UUID?)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(Color.appSurfaceHigh)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.appBorderSubtle, lineWidth: 1))
                            }
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
                            outOfStockPolicy: outOfStockPolicy,
                            safetyStockLevel: Double(safetyStockString) ?? 0.0,
                            maxStockLevel: Double(maxStockString) ?? 0.0,
                            leadTimeDays: Int(leadTimeDaysString) ?? 1,
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
                // Safety Stock & Lead Time
                safetyStockString  = String(format: "%.1f", item.safetyStockLevel)
                maxStockString     = String(format: "%.1f", item.maxStockLevel)
                leadTimeDaysString = String(item.leadTimeDays)
                outOfStockPolicy = item.outOfStockPolicy
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
        let sorted = item.transactions.sorted { $0.createdAt > $1.createdAt }
        guard filterType != "All" else { return sorted }
        return sorted.filter { $0.transactionType == filterType }
    }

    private var totalReceived: Double {
        item.transactions.filter { $0.transactionType == InventoryMovementType.receive.rawValue }.reduce(0.0) { $0 + $1.quantity }
    }

    private var totalWasted: Double {
        item.transactions.filter { $0.transactionType == InventoryMovementType.waste.rawValue }.reduce(0.0) { $0 + abs($1.quantity) }
    }

    private var totalSold: Double {
        item.transactions.filter { $0.transactionType == InventoryMovementType.sell.rawValue }.reduce(0.0) { $0 + abs($1.quantity) }
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
                HStack(spacing: APSpacing.xs) {
                    APBadge(text: typeConfig.label, color: typeConfig.color)

                    let isVerified = InventoryAuditSigner.verifyTransaction(txn)
                    HStack(spacing: 2) {
                        Image(systemName: isVerified ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                            .font(.system(size: 7))
                        Text(isVerified ? "SECURE" : "UNVERIFIED")
                            .font(.system(size: 6, weight: .black))
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(isVerified ? Color.appTeal.opacity(0.15) : Color.appRose.opacity(0.15))
                    .foregroundColor(isVerified ? .appTeal : .appRose)
                    .cornerRadius(3)

                    Spacer()
                    Text(String(format: "%@%.1f %@",
                                txn.quantity >= 0 ? "+" : "",
                                txn.quantity,
                                item.unit))
                        .font(.subheadline).fontWeight(.bold)
                        .foregroundColor(txn.quantity >= 0 ? .appTeal : .appRose)
                }

                HStack {
                    Text(InventoryAuditSigner.cleanNotes(txn.notes) ?? "no_details".t)
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                        .lineLimit(1)
                    Spacer()
                    if let cost = txn.costPrice {
                        Text("฿\(String(format: "%.2f", cost))/\(item.unit)")
                            .font(.caption2)
                            .foregroundColor(.textTertiary)
                    }
                    Text(txn.createdAt, format: .dateTime.day().month().hour().minute())
                        .font(.caption2)
                        .foregroundColor(.textTertiary)
                }
            }
        }
        .padding(APSpacing.md)
        .apCard()
    }
}

// MARK: - Quick Stock Adjust Sheet (Physical Count Reconciliation)

struct QuickStockAdjustSheet: View {
    let item: InventoryItem
    let viewModel: InventoryViewModel
    let onComplete: () -> Void

    @EnvironmentObject private var lm: LocalizationManager
    @State private var physicalCountString = ""
    @State private var selectedReason = "stock_audit"
    @State private var customNotes = ""
    @State private var isSubmitting = false

    @State private var countUnitMode: String = "" // "kg" when item.unit is "g"

    private var isThai: Bool { lm.currentLanguage == .thai }

    private var currentQty: Double { item.currentQuantity }

    private var activeCountUnit: String {
        countUnitMode.isEmpty ? item.unit : countUnitMode
    }

    private var parsedCount: Double? {
        guard let entered = Double(physicalCountString.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        if item.unit == "g" && activeCountUnit == "kg" {
            return entered * 1000.0
        } else if item.unit == "ml" && activeCountUnit == "L" {
            return entered * 1000.0
        }
        return entered
    }

    private var diff: Double? {
        guard let parsed = parsedCount else { return nil }
        return parsed - currentQty
    }

    private var formattedSystemStock: FormattedStockUnit {
        SmartUnitFormatter.format(quantity: currentQty, unit: item.unit)
    }

    private let reasonOptions: [(id: String, th: String, en: String, icon: String)] = [
        ("stock_audit", "ตรวจนับสต๊อกตามรอบ / ประจำวัน", "Periodic Cycle Count", "checklist"),
        ("correction", "แก้ไขยอดบันทึกผิดพลาดก่อนหน้า", "Correction of Previous Error", "arrow.uturn.backward.circle.fill"),
        ("spoilage", "สินค้าเสียหาย / เสื่อมสภาพ / หมดอายุ", "Damaged / Expired / Spoiled", "trash.circle.fill"),
        ("unrecorded_usage", "ใช้งานหรือขายโดยไม่ได้บันทึก", "Unrecorded Sales or Usage", "cart.badge.minus"),
        ("other", "อื่นๆ (ระบุในหมายเหตุ)", "Other Adjustment", "ellipsis.circle.fill")
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: APSpacing.md) {
                        // Card 1: Item & Current Stock (with Smart Auto-Scale)
                        VStack(alignment: .leading, spacing: 12) {
                            sectionHeader(isThai ? "ข้อมูลวัตถุดิบและสต๊อกในระบบ" : "Item & System Stock")
                            HStack(alignment: .center, spacing: 16) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.name)
                                        .font(.title3.weight(.bold))
                                        .foregroundColor(.textPrimary)
                                    HStack(spacing: 6) {
                                        if let sku = item.sku, !sku.isEmpty {
                                            Text("SKU: \(sku)")
                                        }
                                        if let cat = item.category, !cat.isEmpty {
                                            Text("· \(cat)")
                                        }
                                    }
                                    .font(.caption)
                                    .foregroundColor(.textSecondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(isThai ? "สต๊อกในระบบปัจจุบัน" : "Current System Stock")
                                        .font(.caption)
                                        .foregroundColor(.textSecondary)
                                    Text(formattedSystemStock.primaryText)
                                        .font(.title3.weight(.bold))
                                        .foregroundColor(.appTeal)
                                    if let secondary = formattedSystemStock.secondaryText {
                                        Text(secondary)
                                            .font(.caption2)
                                            .foregroundColor(.textSecondary)
                                    }
                                }
                            }
                        }
                        .apCard()

                        // Card 2: Actual Physical Count Input
                        VStack(alignment: .leading, spacing: 14) {
                            sectionHeader(isThai ? "ยอดที่นับได้จริงหน้างาน (Physical Count)" : "Actual Count")

                            Text(isThai ? "กรอกจำนวนสต๊อกคงเหลือจริงที่นับได้ ณ ตอนนี้" : "Enter counted stock currently on hand")
                                .font(.caption)
                                .foregroundColor(.textSecondary)

                            // Smart Unit Switcher
                            if item.unit == "g" {
                                HStack(spacing: 8) {
                                    Text(isThai ? "หน่วยที่นับ:" : "Count Unit:")
                                        .font(.caption.weight(.medium))
                                        .foregroundColor(.textSecondary)
                                    Button("กรัม (g)") { countUnitMode = "g" }
                                        .font(.caption.weight(activeCountUnit == "g" ? .bold : .regular))
                                        .foregroundColor(activeCountUnit == "g" ? .white : .textPrimary)
                                        .padding(.horizontal, 10).padding(.vertical, 4)
                                        .background(activeCountUnit == "g" ? Color.appAccent : Color.appSurfaceHigh)
                                        .clipShape(Capsule())
                                    Button("กิโลกรัม (kg)") { countUnitMode = "kg" }
                                        .font(.caption.weight(activeCountUnit == "kg" ? .bold : .regular))
                                        .foregroundColor(activeCountUnit == "kg" ? .white : .textPrimary)
                                        .padding(.horizontal, 10).padding(.vertical, 4)
                                        .background(activeCountUnit == "kg" ? Color.appAccent : Color.appSurfaceHigh)
                                        .clipShape(Capsule())
                                    Spacer()
                                }
                            } else if item.unit == "ml" {
                                HStack(spacing: 8) {
                                    Text(isThai ? "หน่วยที่นับ:" : "Count Unit:")
                                        .font(.caption.weight(.medium))
                                        .foregroundColor(.textSecondary)
                                    Button("มิลลิลิตร (ml)") { countUnitMode = "ml" }
                                        .font(.caption.weight(activeCountUnit == "ml" ? .bold : .regular))
                                        .foregroundColor(activeCountUnit == "ml" ? .white : .textPrimary)
                                        .padding(.horizontal, 10).padding(.vertical, 4)
                                        .background(activeCountUnit == "ml" ? Color.appAccent : Color.appSurfaceHigh)
                                        .clipShape(Capsule())
                                    Button("ลิตร (L)") { countUnitMode = "L" }
                                        .font(.caption.weight(activeCountUnit == "L" ? .bold : .regular))
                                        .foregroundColor(activeCountUnit == "L" ? .white : .textPrimary)
                                        .padding(.horizontal, 10).padding(.vertical, 4)
                                        .background(activeCountUnit == "L" ? Color.appAccent : Color.appSurfaceHigh)
                                        .clipShape(Capsule())
                                    Spacer()
                                }
                            }

                            HStack(spacing: 10) {
                                modalTextInput(
                                    activeCountUnit == item.unit
                                        ? String(format: "%.2f", currentQty)
                                        : String(format: "%.2f", currentQty / 1000.0),
                                    text: $physicalCountString,
                                    keyboardType: .decimalPad,
                                    suffix: activeCountUnit
                                )

                                Button(isThai ? "เท่าเดิม" : "Match") {
                                    if activeCountUnit == item.unit {
                                        physicalCountString = String(format: "%.2f", currentQty)
                                    } else {
                                        physicalCountString = String(format: "%.2f", currentQty / 1000.0)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .tint(.secondary)

                                Button(isThai ? "หมด (0)" : "Zero") {
                                    physicalCountString = "0"
                                }
                                .buttonStyle(.bordered)
                                .tint(.appRose)
                            }

                            // Quick Steppers
                            HStack(spacing: 8) {
                                ForEach([-5.0, -1.0, 1.0, 5.0], id: \.self) { delta in
                                    Button(action: {
                                        let current = Double(physicalCountString.trimmingCharacters(in: .whitespacesAndNewlines)) ?? (activeCountUnit == item.unit ? currentQty : currentQty / 1000.0)
                                        let updated = max(0, current + delta)
                                        physicalCountString = String(format: "%.2f", updated)
                                    }) {
                                        Text(delta > 0 ? "+\(Int(delta))" : "\(Int(delta))")
                                            .font(.caption.weight(.semibold))
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(Color.appSurfaceHigh)
                                            .clipShape(Capsule())
                                            .overlay(Capsule().stroke(Color.appBorderSubtle, lineWidth: 1))
                                    }
                                    .buttonStyle(.plain)
                                }
                                Spacer()
                            }

                            // Real-time Variance Box
                            if let diff = diff {
                                Divider().background(Color.appDivider)
                                HStack(spacing: 16) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(isThai ? "ส่วนต่างสต๊อก (Variance)" : "Stock Variance")
                                            .font(.caption)
                                            .foregroundColor(.textSecondary)
                                        HStack(spacing: 6) {
                                            Image(systemName: diff > 0 ? "arrow.up.circle.fill" : (diff < 0 ? "arrow.down.circle.fill" : "checkmark.circle.fill"))
                                            let formattedDiff = SmartUnitFormatter.format(quantity: diff, unit: item.unit)
                                            Text("\(diff > 0 ? "+" : "")\(formattedDiff.fullText)")
                                                .font(.headline.weight(.bold))
                                        }
                                        .foregroundColor(diff > 0 ? .appTeal : (diff < 0 ? .appRose : .textSecondary))
                                    }

                                    Spacer()

                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(isThai ? "ผลกระทบมูลค่าต้นทุน" : "Cost Impact")
                                            .font(.caption)
                                            .foregroundColor(.textSecondary)
                                        Text(String(format: "%+0.2f ฿", diff * item.costPrice))
                                            .font(.headline.weight(.semibold))
                                            .foregroundColor(diff > 0 ? .appTeal : (diff < 0 ? .appRose : .textSecondary))
                                    }
                                }
                                .padding(12)
                                .background((diff > 0 ? Color.appTeal : (diff < 0 ? Color.appRose : Color.appSurfaceHigh)).opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                        }
                        .apCard()

                        // Card 3: Adjustment Reason & Notes
                        VStack(alignment: .leading, spacing: 12) {
                            sectionHeader(isThai ? "สาเหตุการปรับยอดสต๊อก" : "Adjustment Reason")

                            Picker(isThai ? "สาเหตุ" : "Reason", selection: $selectedReason) {
                                ForEach(reasonOptions, id: \.id) { opt in
                                    Label(isThai ? opt.th : opt.en, systemImage: opt.icon)
                                        .tag(opt.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.appSurfaceHigh)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.appBorderSubtle, lineWidth: 1))

                            modalFormField(label: isThai ? "หมายเหตุเพิ่มเติม (ถ้ามี)" : "Notes (Optional)", icon: "note.text") {
                                modalTextInput(isThai ? "เช่น นับกะเย็น พบคีย์สต็อกผิดจากเมื่อวาน" : "e.g. evening audit, correcting error", text: $customNotes)
                            }
                        }
                        .apCard()
                    }
                    .padding(APSpacing.md)
                }
            }
            .navigationTitle(isThai ? "นับสต๊อกและปรับยอดจริง" : "Reconcile Physical Count")
            .apNavBar(background: Color.appSurface)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel_btn".t) { onComplete() }.foregroundColor(.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isThai ? "บันทึกยอดจริง" : "Save Count") {
                        guard let count = parsedCount else { return }
                        isSubmitting = true
                        viewModel.adjustItemStock(
                            item: item,
                            toPhysicalCount: count,
                            reasonCode: selectedReason,
                            notes: customNotes
                        )
                        onComplete()
                    }
                    .disabled(parsedCount == nil || isSubmitting)
                    .foregroundStyle(APGradient.accent)
                }
            }
        }
        .apColorScheme()
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
    @State private var isCustomUnit = false
    @State private var customUnit = ""
    @State private var reorderString = "5.0"
    @State private var costString = "0.0"
    @State private var selectedSupplierId: UUID? = nil

    // Opening Stock On Hand
    @State private var hasInitialStock = true
    @State private var initialStockString = ""
    @State private var inputUnitMode: String = "" // e.g. "kg" when unit is "g"

    // Progressive Disclosure
    @State private var showAdvancedSettings = false

    @State private var category = ""
    @State private var storageLocation = ""
    @State private var barcode = ""

    // Safety Stock & Lead Time
    @State private var safetyStockString = "0.0"
    @State private var maxStockString = "0.0"
    @State private var leadTimeDaysString = "1"
    @State private var outOfStockPolicy: OutOfStockPolicy = .allowNegative

    private var isThai: Bool { lm.currentLanguage == .thai }

    private let unitPresets: [(labelTh: String, labelEn: String, value: String)] = [
        ("กรัม (g)", "g", "g"),
        ("กก. (kg)", "kg", "kg"),
        ("มล. (ml)", "ml", "ml"),
        ("ลิตร (L)", "liter", "liter"),
        ("ชิ้น (pc)", "piece", "piece"),
        ("ฟอง", "egg", "piece"),
        ("ขวด", "bottle", "bottle"),
        ("กระป๋อง", "can", "can"),
        ("กล่อง", "box", "box"),
        ("แพ็ก", "pack", "pack")
    ]

    private var effectiveUnit: String {
        if isCustomUnit {
            let trimmed = customUnit.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "piece" : trimmed
        }
        return unit
    }

    private var activeInputUnit: String {
        inputUnitMode.isEmpty ? effectiveUnit : inputUnitMode
    }

    private var initialQty: Double {
        guard hasInitialStock else { return 0.0 }
        let raw = Double(initialStockString.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0.0
        if effectiveUnit == "g" && activeInputUnit == "kg" {
            return raw * 1000.0
        } else if (effectiveUnit == "ml" || effectiveUnit == "liter") && activeInputUnit == "L" && effectiveUnit == "ml" {
            return raw * 1000.0
        }
        return raw
    }

    private var unitCost: Double {
        let enteredCost = Double(costString.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0.0
        if effectiveUnit == "g" && activeInputUnit == "kg" {
            return enteredCost / 1000.0
        } else if effectiveUnit == "ml" && activeInputUnit == "L" {
            return enteredCost / 1000.0
        }
        return enteredCost
    }

    private var totalOpeningValuation: Double {
        let raw = Double(initialStockString.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0.0
        let enteredCost = Double(costString.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0.0
        return raw * enteredCost
    }

    private var normalizedEntry: NormalizedInventoryMeasurement {
        InventoryUnitNormalization.normalize(
            quantity: Double(reorderString) ?? 0,
            unit: effectiveUnit,
            unitCost: unitCost
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: APSpacing.md) {
                        // Section 1: Core Details (Name, Category, Unit)
                        VStack(alignment: .leading, spacing: 14) {
                            sectionHeader(isThai ? "ข้อมูลวัตถุดิบหลัก" : "Essential Details")

                            modalFormField(label: "item_name_placeholder".t, icon: "shippingbox.fill") {
                                modalTextInput(isThai ? "เช่น นมสด Meiji, ชาเขียวมัทฉะ, ไข่ไก่" : "e.g. Fresh Milk, Matcha Powder", text: $name)
                            }

                            // Category
                            modalFormField(label: "category_placeholder".t, icon: "tag.fill") {
                                modalTextInput(isThai ? "เช่น วัตถุดิบเครื่องดื่ม, เนื้อสัตว์, บรรจุภัณฑ์" : "e.g. Beverages, Dairy, Packaging", text: $category)
                            }

                            // Unit Presets
                            VStack(alignment: .leading, spacing: 8) {
                                Label(isThai ? "หน่วยนับวัตถุดิบ (Unit of Measure)" : "Unit of Measure", systemImage: "scalemass.fill")
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(.textSecondary)

                                // Preset Pills Grid
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 8)], spacing: 8) {
                                    ForEach(unitPresets, id: \.value) { preset in
                                        let isSelected = !isCustomUnit && unit == preset.value
                                        Button(action: {
                                            unit = preset.value
                                            isCustomUnit = false
                                        }) {
                                            Text(isThai ? preset.labelTh : preset.labelEn)
                                                .font(.caption.weight(isSelected ? .bold : .regular))
                                                .foregroundColor(isSelected ? .white : .textPrimary)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 7)
                                                .frame(maxWidth: .infinity)
                                                .background(isSelected ? Color.appAccent : Color.appSurfaceHigh)
                                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                        .stroke(isSelected ? Color.clear : Color.appBorderSubtle, lineWidth: 1)
                                                )
                                        }
                                        .buttonStyle(.plain)
                                    }

                                    // Custom unit toggle pill
                                    Button(action: {
                                        isCustomUnit = true
                                    }) {
                                        Text(isThai ? "อื่นๆ…" : "Custom…")
                                            .font(.caption.weight(isCustomUnit ? .bold : .regular))
                                            .foregroundColor(isCustomUnit ? .white : .textSecondary)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 7)
                                            .frame(maxWidth: .infinity)
                                            .background(isCustomUnit ? Color.appAccent : Color.appSurfaceHigh)
                                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                    .stroke(isCustomUnit ? Color.clear : Color.appBorderSubtle, lineWidth: 1)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }

                                if isCustomUnit {
                                    modalTextInput(isThai ? "ระบุชื่อหน่วยนับ เช่น ถุง, หลอด" : "Specify custom unit", text: $customUnit)
                                        .padding(.top, 4)
                                }
                            }
                        }
                        .apCard()

                        // Section 2: Opening Stock & Cost (Single-step Setup)
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                sectionHeader(isThai ? "สต๊อกตั้งต้นและต้นทุน" : "Initial Stock & Cost")
                                Spacer()
                                Toggle("", isOn: $hasInitialStock)
                                    .labelsHidden()
                            }

                            if hasInitialStock {
                                Text(isThai ? "บันทึกจำนวนคงเหลือที่มีอยู่จริงตอนนี้ ระบบจะสร้างยอดยกมาเริ่มต้นให้อัตโนมัติ" : "Record current on-hand quantity directly as opening balance")
                                    .font(.caption)
                                    .foregroundColor(.textSecondary)

                                // Smart Unit Switcher for Mass / Volume
                                if effectiveUnit == "g" {
                                    HStack(spacing: 8) {
                                        Text(isThai ? "หน่วยที่ต้องการกรอก:" : "Input Unit:")
                                            .font(.caption.weight(.medium))
                                            .foregroundColor(.textSecondary)
                                        Button("กรัม (g)") { inputUnitMode = "g" }
                                            .font(.caption.weight(activeInputUnit == "g" ? .bold : .regular))
                                            .foregroundColor(activeInputUnit == "g" ? .white : .textPrimary)
                                            .padding(.horizontal, 10).padding(.vertical, 4)
                                            .background(activeInputUnit == "g" ? Color.appAccent : Color.appSurfaceHigh)
                                            .clipShape(Capsule())
                                        Button("กิโลกรัม (kg)") { inputUnitMode = "kg" }
                                            .font(.caption.weight(activeInputUnit == "kg" ? .bold : .regular))
                                            .foregroundColor(activeInputUnit == "kg" ? .white : .textPrimary)
                                            .padding(.horizontal, 10).padding(.vertical, 4)
                                            .background(activeInputUnit == "kg" ? Color.appAccent : Color.appSurfaceHigh)
                                            .clipShape(Capsule())
                                        Spacer()
                                    }
                                } else if effectiveUnit == "ml" {
                                    HStack(spacing: 8) {
                                        Text(isThai ? "หน่วยที่ต้องการกรอก:" : "Input Unit:")
                                            .font(.caption.weight(.medium))
                                            .foregroundColor(.textSecondary)
                                        Button("มิลลิลิตร (ml)") { inputUnitMode = "ml" }
                                            .font(.caption.weight(activeInputUnit == "ml" ? .bold : .regular))
                                            .foregroundColor(activeInputUnit == "ml" ? .white : .textPrimary)
                                            .padding(.horizontal, 10).padding(.vertical, 4)
                                            .background(activeInputUnit == "ml" ? Color.appAccent : Color.appSurfaceHigh)
                                            .clipShape(Capsule())
                                        Button("ลิตร (L)") { inputUnitMode = "L" }
                                            .font(.caption.weight(activeInputUnit == "L" ? .bold : .regular))
                                            .foregroundColor(activeInputUnit == "L" ? .white : .textPrimary)
                                            .padding(.horizontal, 10).padding(.vertical, 4)
                                            .background(activeInputUnit == "L" ? Color.appAccent : Color.appSurfaceHigh)
                                            .clipShape(Capsule())
                                        Spacer()
                                    }
                                }

                                HStack(spacing: 12) {
                                    modalFormField(label: isThai ? "สต๊อกคงเหลือจริง (\(activeInputUnit))" : "Opening Quantity (\(activeInputUnit))", icon: "archivebox.fill") {
                                        modalTextInput("0", text: $initialStockString, keyboardType: .decimalPad, suffix: activeInputUnit)
                                    }
                                    .frame(maxWidth: .infinity)

                                    modalFormField(label: isThai ? "ต้นทุนต่อ \(activeInputUnit)" : "Cost per \(activeInputUnit)", icon: "banknote.fill") {
                                        modalTextInput("0.00", text: $costString, keyboardType: .decimalPad, prefix: "฿")
                                    }
                                    .frame(maxWidth: .infinity)
                                }

                                // Live Valuation Banner
                                if initialQty > 0 {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 12) {
                                            Image(systemName: "checkmark.seal.fill")
                                                .foregroundColor(.appTeal)
                                            Text(isThai
                                                 ? "มูลค่าสต๊อกรวม: ฿\(String(format: "%.2f", totalOpeningValuation))"
                                                 : "Total Opening Value: ฿\(String(format: "%.2f", totalOpeningValuation))")
                                                .font(.caption.weight(.bold))
                                                .foregroundColor(.textPrimary)
                                            Spacer()
                                        }
                                        if activeInputUnit != effectiveUnit {
                                            Text(isThai
                                                 ? "ระบบจะแปลงและบันทึกสต๊อกเป็น \(String(format: "%.1f", initialQty)) \(effectiveUnit) (ต้นทุน ฿\(String(format: "%.4f", unitCost))/\(effectiveUnit))"
                                                 : "Will be stored as \(String(format: "%.1f", initialQty)) \(effectiveUnit) (฿\(String(format: "%.4f", unitCost))/\(effectiveUnit))")
                                                .font(.caption2)
                                                .foregroundColor(.appTeal)
                                        }
                                    }
                                    .padding(10)
                                    .background(Color.appTeal.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                            } else {
                                HStack(spacing: 12) {
                                    modalFormField(label: "unit_cost_price_placeholder".t, icon: "banknote.fill") {
                                        modalTextInput("0.00", text: $costString, keyboardType: .decimalPad, prefix: "฿")
                                    }
                                    .frame(maxWidth: .infinity)

                                    Text(isThai ? "สร้างรายการวัตถุดิบโดยยังไม่มียอดสต๊อก (คงเหลือ 0)" : "Item will be created with 0 on-hand stock")
                                        .font(.caption)
                                        .foregroundColor(.textTertiary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        .apCard()

                        // Section 3: Summary Preview Card
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label(isThai ? "สรุปรายการก่อนบันทึก" : "Summary Preview", systemImage: "info.circle.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.appAccent)
                                Spacer()
                            }

                            HStack(spacing: 16) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(isThai ? "ชื่อวัตถุดิบ" : "Item Name").font(.caption2).foregroundColor(.textSecondary)
                                    Text(name.isEmpty ? "-" : name).font(.subheadline.weight(.semibold)).foregroundColor(.textPrimary)
                                }
                                Divider().frame(height: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(isThai ? "สต๊อกเริ่มต้น" : "Opening Stock").font(.caption2).foregroundColor(.textSecondary)
                                    Text(hasInitialStock ? "\(String(format: "%.2f", initialQty)) \(effectiveUnit)" : "0 \(effectiveUnit)")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(hasInitialStock && initialQty > 0 ? .appTeal : .textPrimary)
                                }
                                Divider().frame(height: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(isThai ? "มูลค่ารวม" : "Total Value").font(.caption2).foregroundColor(.textSecondary)
                                    Text(String(format: "฿%.2f", totalOpeningValuation))
                                        .font(.subheadline.weight(.bold))
                                        .foregroundColor(.appTeal)
                                }
                            }
                        }
                        .apCard()

                        // Section 4: Progressive Disclosure (Advanced Settings)
                        VStack(alignment: .leading, spacing: 12) {
                            DisclosureGroup(isExpanded: $showAdvancedSettings) {
                                VStack(alignment: .leading, spacing: 14) {
                                    // Row 1: SKU & Barcode
                                    HStack(spacing: 12) {
                                        modalFormField(label: "sku_code_placeholder".t, icon: "barcode") {
                                            modalTextInput("sku_code_placeholder".t, text: $sku)
                                        }
                                        .frame(maxWidth: .infinity)

                                        modalFormField(label: "barcode_placeholder".t, icon: "qrcode.viewfinder") {
                                            modalTextInput("barcode_placeholder".t, text: $barcode)
                                        }
                                        .frame(maxWidth: .infinity)
                                    }

                                    // Row 2: Location & Reorder Level
                                    HStack(spacing: 12) {
                                        modalFormField(label: "storage_location_placeholder".t, icon: "mappin.and.ellipse") {
                                            modalTextInput("storage_location_placeholder".t, text: $storageLocation)
                                        }
                                        .frame(maxWidth: .infinity)

                                        modalFormField(label: "reorder_trigger_level_placeholder".t, icon: "exclamationmark.triangle.fill") {
                                            modalTextInput("0.0", text: $reorderString, keyboardType: .decimalPad, suffix: effectiveUnit)
                                        }
                                        .frame(maxWidth: .infinity)
                                    }

                                    Divider().background(Color.appDivider)

                                    // Safety Stock & Lead Time
                                    SafetyStockFields(
                                        safetyStockString: $safetyStockString,
                                        maxStockString: $maxStockString,
                                        leadTimeDaysString: $leadTimeDaysString,
                                        unit: effectiveUnit
                                    )

                                    Divider().background(Color.appDivider)

                                    // Out of Stock Policy
                                    outOfStockPolicyCard(selection: $outOfStockPolicy)

                                    // Supplier
                                    modalFormField(label: "supplier_label".t, icon: "building.2.fill") {
                                        Picker("supplier_label".t, selection: $selectedSupplierId) {
                                            Text("no_supplier_option".t).tag(nil as UUID?)
                                            ForEach(suppliers) { sup in
                                                Text(sup.name).tag(sup.id as UUID?)
                                            }
                                        }
                                        .pickerStyle(.menu)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                        .background(Color.appSurfaceHigh)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.appBorderSubtle, lineWidth: 1))
                                    }
                                }
                                .padding(.top, 10)
                            } label: {
                                HStack {
                                    Label(isThai ? "การตั้งค่าขั้นสูง (บาร์โค้ด, จุดสั่งซื้อ, สต๊อกปลอดภัย, ซัพพลายเออร์)" : "Advanced Configuration", systemImage: "slider.horizontal.3")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(.textPrimary)
                                    Spacer()
                                }
                            }
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
                        let cost = unitCost
                        let finalUnit = effectiveUnit
                        viewModel.addInventoryItem(
                            name: name,
                            sku: sku.isEmpty ? nil : sku,
                            unit: finalUnit,
                            initialQuantity: initialQty,
                            reorderLevel: reorder,
                            costPrice: cost,
                            outOfStockPolicy: outOfStockPolicy,
                            safetyStockLevel: Double(safetyStockString) ?? 0.0,
                            maxStockLevel: Double(maxStockString) ?? 0.0,
                            leadTimeDays: Int(leadTimeDaysString) ?? 1,
                            supplierId: selectedSupplierId,
                            category: category.isEmpty ? nil : category,
                            storageLocation: storageLocation.isEmpty ? nil : storageLocation,
                            barcode: barcode.isEmpty ? nil : barcode,
                            activeBranch: activeBranch
                        )
                        onComplete()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || effectiveUnit.isEmpty)
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

                        VStack(alignment: .leading, spacing: 10) {
                            sectionHeader("item_information".t)
                            HStack(spacing: 12) {
                                infoRow(label: "Name", value: item.name)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                infoRow(label: "On Hand", value: String(format: "%.1f %@", item.currentQuantity, item.unit))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .apCard()

                        VStack(alignment: .leading, spacing: 12) {
                            sectionHeader("return_to_supplier_title".t)
                            modalFormField(label: "quantity_label".t, icon: "arrow.uturn.left.circle.fill") {
                                modalTextInput("0.0", text: $amountString, keyboardType: .decimalPad, suffix: item.unit)
                            }
                            modalFormField(label: "return_details_placeholder".t, icon: "text.alignleft") {
                                modalTextInput("return_details_placeholder".t, text: $noteText)
                            }
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

@ViewBuilder
private func outOfStockPolicyCard(selection: Binding<OutOfStockPolicy>) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.octagon.fill")
                .font(.system(size: 11))
                .foregroundColor(.appAccent)
            Text("stock_policy_title".t)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.textSecondary)
        }
        Picker("stock_policy_title".t, selection: selection) {
            Text("stock_policy_allow_negative".t).tag(OutOfStockPolicy.allowNegative)
            Text("stock_policy_block".t).tag(OutOfStockPolicy.block)
        }
        .pickerStyle(.segmented)

        Text(selection.wrappedValue == .block
             ? "stock_policy_block_desc".t
             : "stock_policy_allow_negative_desc".t)
            .font(.caption2)
            .foregroundColor(.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
