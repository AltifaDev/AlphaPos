// InventoryViewModel_v2.swift
// AlphaPos — Enhanced Inventory ViewModel with Pagination, Bulk Operations & Promotion Tracking
//
// Drop-in replacement for: AlphaPos/Features/Inventory/ViewModels/InventoryViewModel.swift
// Changes:
//   ✓ Pagination (fetchLimit + offset, loadNextPage)
//   ✓ Dynamic sorting (SortKey enum + sortAscending)
//   ✓ Bulk operations (bulkReceive, bulkWaste, bulkDelete)
//   ✓ Promotion cost impact calculator
//   ✓ All existing functions preserved unchanged

import Foundation
import SwiftData
import SwiftUI
import os

enum InventorySyncScope {
    static func includes(activeBranchId: UUID?, entityBranchId: UUID?) -> Bool {
        guard let activeBranchId else { return false }
        return entityBranchId == activeBranchId
    }
}

// MARK: - Sort Configuration

enum InventorySortKey: String, CaseIterable, Identifiable {
    case name = "name"
    case quantity = "quantity"
    case cost = "cost"
    case updated = "updated"
    case expiry  = "expiry"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .name: return "inventory_sort_name".t
        case .quantity: return "inventory_sort_quantity".t
        case .cost: return "inventory_sort_cost".t
        case .updated: return "inventory_sort_updated".t
        case .expiry:  return "inventory_sort_expiry".t
        }
    }
    
    var systemImage: String {
        switch self {
        case .name: return "textformat.abc"
        case .quantity: return "number"
        case .cost: return "dollarsign.circle"
        case .updated: return "clock"
        case .expiry:  return "calendar.badge.exclamationmark"
        }
    }
}

// MARK: - Paginated Fetch Result

struct PaginatedInventoryResult {
    let items: [InventoryItem]
    let totalCount: Int
    let hasMore: Bool
}

// MARK: - InventoryViewModel

@Observable
@MainActor
final class InventoryViewModel {
    var modelContext: ModelContext?
    
    // UI selection and sheet states
    var selectedItem: InventoryItem?
    var showingReceiveSheet = false
    var showingWasteSheet = false
    
    // MARK: Pagination State
    var paginatedItems: [InventoryItem] = []
    var currentPage: Int = 0
    var pageSize: Int = 50
    var hasMoreItems: Bool = true
    var totalItemCount: Int = 0
    var isLoadingPage: Bool = false
    
    // MARK: Sort State
    var sortKey: InventorySortKey = .name
    var sortAscending: Bool = true
    
    // MARK: Bulk Selection State
    var isInBulkMode: Bool = false
    var selectedItemIds: Set<UUID> = []
    
    init(modelContext: ModelContext? = nil) {
        self.modelContext = modelContext
    }

    /// Compact date stamp used for auto-generated adjustment lot numbers.
    private static let auditLotDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd"
        return df
    }()
    
    // MARK: - Pagination Methods
    
    /// Reset pagination and load first page with given filters.
    func resetAndLoadFirstPage(
        branch: Branch?,
        search: String,
        status: String,
        category: String
    ) {
        currentPage = 0
        paginatedItems = []
        hasMoreItems = true
        totalItemCount = 0
        loadNextPage(branch: branch, search: search, status: status, category: category)
    }
    
    /// Load the next page of inventory items applying filters and sort.
    func loadNextPage(
        branch: Branch?,
        search: String,
        status: String,
        category: String
    ) {
        guard let modelContext = modelContext, !isLoadingPage else { return }
        isLoadingPage = true
        
        let offset = currentPage * pageSize
        
        // Build predicate based on filters
        let predicate = buildPredicate(branch: branch, search: search, status: status, category: category)
        
        // Build sort descriptors
        let sortDescriptors = buildSortDescriptors()
        
        let descriptor = FetchDescriptor<InventoryItem>(predicate: predicate, sortBy: sortDescriptors)
        
        if let allItems = try? modelContext.fetch(descriptor) {
            let matchingItems = applyRuntimeFilters(allItems, branch: branch, search: search, status: status, category: category)
            totalItemCount = matchingItems.count
            let pageItems = Array(matchingItems.dropFirst(offset).prefix(pageSize))
            if currentPage == 0 {
                paginatedItems = pageItems
            } else {
                paginatedItems.append(contentsOf: pageItems)
            }
            hasMoreItems = pageItems.count == pageSize
            currentPage += 1
        } else {
            hasMoreItems = false
        }
        
        isLoadingPage = false
    }
    
    /// Reload current paginated data in-place (e.g., after edit/receive/waste).
    func refreshCurrentData(
        branch: Branch?,
        search: String,
        status: String,
        category: String
    ) {
        guard let modelContext = modelContext else { return }
        
        let predicate = buildPredicate(branch: branch, search: search, status: status, category: category)
        let sortDescriptors = buildSortDescriptors()
        
        // Re-fetch all items up to current loaded count
        let currentLoadedCount = paginatedItems.count
        
        let descriptor = FetchDescriptor<InventoryItem>(predicate: predicate, sortBy: sortDescriptors)
        
        if let allItems = try? modelContext.fetch(descriptor) {
            let matchingItems = applyRuntimeFilters(allItems, branch: branch, search: search, status: status, category: category)
            let refreshedItems = Array(matchingItems.prefix(max(currentLoadedCount, pageSize)))
            totalItemCount = matchingItems.count
            paginatedItems = refreshedItems
            hasMoreItems = refreshedItems.count >= max(currentLoadedCount, pageSize)
        }
    }
    
    // MARK: - Predicate Builder
    
    private func buildPredicate(
        branch: Branch?,
        search: String,
        status: String,
        category: String
    ) -> Predicate<InventoryItem> {
        #Predicate<InventoryItem> { item in
            item.isDeleted == false
        }
    }

    private func applyRuntimeFilters(
        _ items: [InventoryItem],
        branch: Branch?,
        search: String,
        status: String,
        category: String
    ) -> [InventoryItem] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return items.filter { item in
            if let branch, item.branch?.id != branch.id {
                return false
            }

            if !query.isEmpty {
                let nameMatches = item.name.lowercased().contains(query)
                let skuMatches = (item.sku ?? "").lowercased().contains(query)
                let barcodeMatches = (item.barcode ?? "").lowercased().contains(query)
                if !nameMatches && !skuMatches && !barcodeMatches {
                    return false
                }
            }

            if category != "All", item.category != category {
                return false
            }

            if status == "Low Stock" {
                return item.currentQuantity > 0 && item.currentQuantity <= item.reorderLevel
            }

            if status == "Out of Stock" {
                return item.currentQuantity <= 0
            }

            return true
        }
    }
    
    // MARK: - Sort Descriptor Builder
    
    private func buildSortDescriptors() -> [SortDescriptor<InventoryItem>] {
        switch sortKey {
        case .name:
            return [SortDescriptor(\InventoryItem.name, order: sortAscending ? .forward : .reverse)]
        case .quantity:
            return [SortDescriptor(\InventoryItem.currentQuantity, order: sortAscending ? .forward : .reverse)]
        case .cost:
            return [SortDescriptor(\InventoryItem.costPrice, order: sortAscending ? .forward : .reverse)]
        case .updated:
            return [SortDescriptor(\InventoryItem.updatedAt, order: sortAscending ? .forward : .reverse)]
        case .expiry:
            return [SortDescriptor(\InventoryItem.updatedAt, order: sortAscending ? .forward : .reverse)]
        }
    }
    
    // MARK: - Bulk Selection
    
    func toggleBulkMode() {
        isInBulkMode.toggle()
        if !isInBulkMode {
            selectedItemIds.removeAll()
        }
    }
    
    func toggleItemSelection(_ item: InventoryItem) {
        if selectedItemIds.contains(item.id) {
            selectedItemIds.remove(item.id)
        } else {
            selectedItemIds.insert(item.id)
        }
    }
    
    func selectAll() {
        selectedItemIds = Set(paginatedItems.map { $0.id })
    }
    
    func deselectAll() {
        selectedItemIds.removeAll()
    }
    
    var selectedItems: [InventoryItem] {
        paginatedItems.filter { selectedItemIds.contains($0.id) }
    }
    
    // MARK: - Bulk Operations
    
    /// Bulk receive: Add the same quantity to multiple items with WAC calculation.
    /// Bulk receive at the item's *existing* average cost (cost unchanged).
    func bulkReceive(items: [InventoryItem], amount: Double, notes: String) {
        bulkReceive(items: items, amount: amount, unitCost: nil, notes: notes)
    }

    /// Bulk receive with a (possibly new) unit cost, applying Weighted Average
    /// Cost: WAC = (oldQty × oldCost + newQty × newCost) / (oldQty + newQty).
    func bulkReceive(
        items: [InventoryItem],
        amount: Double,
        unitCost: Double?,
        notes: String
    ) {
        guard let modelContext = modelContext, amount > 0 else { return }

        for item in items {
            guard let branch = item.branch else {
                AppLogger.inventory.error("Bulk receive skipped orphan inventory item \(item.id)")
                continue
            }
            let oldQty = max(item.currentQuantity, 0.0)
            let oldCost = item.costPrice
            let newCost = unitCost ?? item.costPrice
            let totalQty = oldQty + amount

            // WAC — blend existing stock with the newly received batch.
            if totalQty > 0 {
                item.costPrice = ((oldQty * oldCost) + (amount * newCost)) / totalQty
            }

            item.currentQuantity += amount
            item.updatedAt = Date()
            item.isSynced = false

            let txn = InventoryTransaction(
                item: item,
                transactionType: InventoryMovementType.receive.rawValue,
                quantity: amount,
                costPrice: newCost,
                notes: notes.isEmpty ? "Bulk receive (\(items.count) items)" : notes,
                branch: branch,
                reasonCode: "receive"
            )
            modelContext.insert(txn)

            // Register a lot so FEFO tracking stays accurate for bulk receipts.
            expiryManager.registerLot(
                for: item,
                quantity: amount,
                costPrice: newCost,
                expiryDate: nil,
                lotNumber: nil,
                sourceTransactionId: txn.id
            )
        }

        modelContext.saveWithLogging(label: #function)

        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }
    
    /// Bulk waste: Subtract a specific amount per item (defaults to full quantity if amount ≤ 0).
    func bulkWaste(items: [InventoryItem], amount: Double = 0, reason: String, notes: String) {
        guard let modelContext = modelContext else { return }

        for item in items {
            guard let branch = item.branch else {
                AppLogger.inventory.error("Bulk waste skipped orphan inventory item \(item.id)")
                continue
            }
            // If amount ≤ 0 caller wants to waste the full remaining quantity
            let wasteQty = amount > 0 ? min(amount, item.currentQuantity) : item.currentQuantity
            guard wasteQty > 0 else { continue }

            item.currentQuantity = max(0, item.currentQuantity - wasteQty)
            item.updatedAt = Date()
            item.isSynced = false

            // Keep lots in sync with currentQuantity (FEFO drain)
            expiryManager.consumeFEFO(item: item, quantity: wasteQty)

            let txnNote = "Bulk Waste: \(reason)" + (notes.isEmpty ? "" : " (\(notes))")
            let txn = InventoryTransaction(
                item: item,
                transactionType: InventoryMovementType.waste.rawValue,
                quantity: -wasteQty,
                notes: txnNote,
                branch: branch,
                reasonCode: "waste"
            )
            modelContext.insert(txn)
        }

        modelContext.saveWithLogging(label: #function)

        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }
    
    /// Bulk soft-delete: Mark multiple items as deleted.
    func bulkDelete(items: [InventoryItem]) {
        guard let modelContext = modelContext else { return }
        
        for item in items {
            item.isDeleted = true
            item.isSynced = false
            item.updatedAt = Date()
        }
        
        modelContext.saveWithLogging(label: #function)
        isInBulkMode = false
        selectedItemIds.removeAll()
        
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }
    
    // MARK: - Promotion Cost Impact Tracking
    
    /// Calculate the total cost impact of a promotion across orders.
    /// This considers the discount amount given AND the COGS of free/reward items.
    func calculatePromotionCostImpact(promotion: Promotion, orders: [Order]) -> Double {
        guard let modelContext = modelContext else { return 0.0 }
        
        var totalCostImpact = 0.0
        
        // 1. Sum of all OrderDiscount amounts linked to this promotion
        let discountDesc = FetchDescriptor<OrderDiscount>()
        if let allDiscounts = try? modelContext.fetch(discountDesc) {
            let promoDiscounts = allDiscounts.filter { $0.promotion?.id == promotion.id && !$0.isDeleted }
            totalCostImpact += promoDiscounts.reduce(0.0) { $0 + $1.discountAmount }
        }
        
        // 2. For buy_x_get_y promotions, calculate COGS of reward items
        if promotion.discountType == "buy_x_get_y" || promotion.discountType == "buy_x_pay_y" {
            // Find the menu item this promotion applies to
            if let menuItemId = promotion.appliesToMenuItemId {
                let menuDesc = FetchDescriptor<MenuItem>()
                if let menuItems = try? modelContext.fetch(menuDesc),
                   let targetItem = menuItems.first(where: { $0.id == menuItemId }) {
                    // Calculate COGS per unit using recipes
                    let cogsPerUnit = RecipeCostCalculator.cost(for: targetItem.recipes)
                    
                    // Count how many times this promotion was redeemed
                    let promoDiscountCount: Int
                    let discountDesc2 = FetchDescriptor<OrderDiscount>()
                    if let allDiscounts = try? modelContext.fetch(discountDesc2) {
                        promoDiscountCount = allDiscounts.filter { $0.promotion?.id == promotion.id && !$0.isDeleted }.count
                    } else {
                        promoDiscountCount = 0
                    }
                    
                    // Each redemption gives rewardQuantity free items
                    let freeItemCost = cogsPerUnit * Double(promotion.rewardQuantity) * Double(promoDiscountCount)
                    totalCostImpact += freeItemCost
                }
            }
        }
        
        return totalCostImpact
    }
    
    /// Get promotion usage statistics.
    func getPromotionUsageStats(promotion: Promotion) -> (redemptionCount: Int, totalDiscount: Double, avgDiscount: Double) {
        guard let modelContext = modelContext else { return (0, 0, 0) }
        
        let discountDesc = FetchDescriptor<OrderDiscount>()
        guard let allDiscounts = try? modelContext.fetch(discountDesc) else { return (0, 0, 0) }
        
        let promoDiscounts = allDiscounts.filter { $0.promotion?.id == promotion.id && !$0.isDeleted }
        let count = promoDiscounts.count
        let total = promoDiscounts.reduce(0.0) { $0 + $1.discountAmount }
        let avg = count > 0 ? total / Double(count) : 0.0
        
        return (count, total, avg)
    }
    
    // MARK: - Paginated Transaction Fetch
    
    /// Fetch transactions with pagination for the transaction log panel.
    func fetchTransactions(
        branch: Branch?,
        limit: Int = 30,
        offset: Int = 0
    ) -> [InventoryTransaction] {
        guard let modelContext = modelContext else { return [] }
        
        let branchId = branch?.id
        let descriptor = FetchDescriptor<InventoryTransaction>(
            predicate: #Predicate<InventoryTransaction> { !$0.isDeleted },
            sortBy: [SortDescriptor(\InventoryTransaction.updatedAt, order: .reverse)]
        )
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        let scoped = rows.filter { branchId == nil || $0.branch.id == branchId }
        return Array(scoped.dropFirst(offset).prefix(limit))
    }
    
    // MARK: - Statistics Helpers
    
    /// Get inventory statistics for the summary cards.
    func getInventoryStats(branch: Branch?) -> (totalItems: Int, lowStockCount: Int, outOfStockCount: Int, totalValue: Double) {
        guard let modelContext = modelContext else { return (0, 0, 0, 0.0) }
        
        let branchId = branch?.id
        let activePredicate = #Predicate<InventoryItem> { item in
            item.isDeleted == false &&
            (branchId == nil || item.branch?.id == branchId)
        }
        
        let descriptor = FetchDescriptor<InventoryItem>(predicate: activePredicate)
        guard let items = try? modelContext.fetch(descriptor) else { return (0, 0, 0, 0.0) }
        
        let totalItems = items.count
        let lowStockCount = items.filter { $0.currentQuantity > 0 && $0.currentQuantity <= $0.reorderLevel }.count
        let outOfStockCount = items.filter { $0.currentQuantity <= 0 }.count
        let totalValue = items.reduce(0.0) { $0 + ($1.currentQuantity * $1.costPrice) }
        
        return (totalItems, lowStockCount, outOfStockCount, totalValue)
    }
    
    /// Get all unique categories from inventory items.
    func getCategories(branch: Branch?) -> [String] {
        guard let modelContext = modelContext else { return [] }
        
        let branchId = branch?.id
        let predicate = #Predicate<InventoryItem> { item in
            item.isDeleted == false &&
            (branchId == nil || item.branch?.id == branchId)
        }
        
        let descriptor = FetchDescriptor<InventoryItem>(predicate: predicate)
        guard let items = try? modelContext.fetch(descriptor) else { return [] }
        
        let categories = Set(items.compactMap { $0.category }).sorted()
        return categories
    }
    
    // MARK: - Existing Functions (Preserved)
    
    func processReceive(item: InventoryItem, amountString: String, costString: String, notes: String) {
        guard let modelContext = modelContext, let branch = item.branch,
              let amount = Double(amountString), amount > 0 else { return }
        let newUnitCost = Double(costString) ?? item.costPrice

        // Weighted Average Cost (WAC) calculation — International Standard
        // Formula: WAC = (oldQty × oldCost + newQty × newCost) / (oldQty + newQty)
        let oldQty = max(item.currentQuantity, 0.0)
        let oldCost = item.costPrice
        let totalQty = oldQty + amount

        if totalQty > 0 {
            item.costPrice = ((oldQty * oldCost) + (amount * newUnitCost)) / totalQty
        } else {
            item.costPrice = newUnitCost
        }

        // Update item quantity
        item.currentQuantity += amount
        item.updatedAt = Date()
        item.isSynced = false

        let txn = InventoryTransaction(
            item: item,
            transactionType: InventoryMovementType.receive.rawValue,
            quantity: amount,
            costPrice: newUnitCost,
            notes: notes.isEmpty ? "Supplier delivery receive" : notes,
            branch: branch,
            reasonCode: "receive"
        )
        modelContext.insert(txn)

        // ── Lot registration for FEFO tracking (no expiry date for this path) ──
        // Callers that have expiry info (ReceiveStockView, StockDocumentScanSheet)
        // use processReceiveWithExpiry() instead, which passes expiryDate + lotNumber.
        expiryManager.registerLot(
            for: item,
            quantity: amount,
            costPrice: newUnitCost,
            expiryDate: nil,
            lotNumber: nil,
            sourceTransactionId: txn.id
        )

        modelContext.saveWithLogging(label: #function)

        // Trigger background sync task
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }
    
    func processWaste(item: InventoryItem, amountString: String, reasonSelection: String, notes: String) {
        guard let modelContext = modelContext, let branch = item.branch,
              let amount = Double(amountString), amount > 0 else { return }

        // Subtract item quantity (floor at 0 — stock cannot go negative)
        let before = item.currentQuantity
        let deducted = min(amount, before)
        item.currentQuantity = max(0, before - amount)
        item.updatedAt = Date()
        item.isSynced = false

        // Keep lots in sync with currentQuantity (FEFO drain) — GS1 lot traceability
        expiryManager.consumeFEFO(item: item, quantity: deducted)

        let txnNote = "Waste: \(reasonSelection)" + (notes.isEmpty ? "" : " (\(notes))")
        let txn = InventoryTransaction(
            item: item,
            transactionType: InventoryMovementType.waste.rawValue,
            quantity: -deducted,
            notes: txnNote,
            branch: branch,
            reasonCode: "waste"
        )
        modelContext.insert(txn)
        modelContext.saveWithLogging(label: #function)
        
        // Trigger background sync task
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }
    
    // MARK: - Phase 1 & 2: Recipe Management
    
    func saveRecipe(
        for menuItem: MenuItem,
        trackingMode: String,
        selectedIngredientId: UUID?,
        recipeLines: [(ingredientId: UUID, qty: Double)]
    ) {
        guard let modelContext = modelContext else { return }

        var autoCreateBranch: Branch?
        if trackingMode == "finished_good", selectedIngredientId == nil {
            let activeId = UUID(uuidString: BranchContext.shared.activeBranchIDString)
            let branches = (try? modelContext.fetch(FetchDescriptor<Branch>())) ?? []
            autoCreateBranch = branches.first { $0.id == activeId && !$0.isDeleted }
            guard autoCreateBranch != nil else {
                AppLogger.inventory.error("Refused finished-good creation without an active branch")
                return
            }
        }
        
        // 1. Delete existing recipes. Fetch directly because an imported
        // offline store may not have hydrated `menuItem.recipes` yet.
        let recipeDescriptor = FetchDescriptor<Recipe>()
        let oldRecipes = ((try? modelContext.fetch(recipeDescriptor)) ?? []).filter {
            $0.menuItem?.id == menuItem.id
        }
        for recipe in oldRecipes {
            modelContext.delete(recipe)
        }
        menuItem.recipes.removeAll()
        
        // 2. Setup based on mode
        switch trackingMode {
        case "not_tracked":
            break
            
        case "finished_good":
            if let ingredientId = selectedIngredientId {
                let descriptor = FetchDescriptor<InventoryItem>()
                if let ingredients = try? modelContext.fetch(descriptor),
                   let ingredient = ingredients.first(where: { $0.id == ingredientId }) {
                    let newRecipe = Recipe(
                        menuItem: menuItem,
                        inventoryItem: ingredient,
                        quantityRequired: 1.0,
                        quantityUnit: ingredient.unit
                    )
                    modelContext.insert(newRecipe)
                }
            } else {
                // Auto-create matching InventoryItem
                let newIngredient = InventoryItem(
                    name: menuItem.name,
                    sku: "FG-\(menuItem.name.prefix(4).uppercased().trimmingCharacters(in: .whitespaces))-\(Int.random(in: 100...999))",
                    unit: "piece",
                    currentQuantity: 0.0,
                    reorderLevel: 5.0,
                    costPrice: menuItem.price * 0.5,
                    branch: autoCreateBranch,
                    category: "Finished Goods",
                    storageLocation: "Front Counter"
                )
                modelContext.insert(newIngredient)
                
                let newRecipe = Recipe(
                    menuItem: menuItem,
                    inventoryItem: newIngredient,
                    quantityRequired: 1.0,
                    quantityUnit: newIngredient.unit
                )
                modelContext.insert(newRecipe)
            }
            
        case "recipe_based":
            let descriptor = FetchDescriptor<InventoryItem>()
            if let ingredients = try? modelContext.fetch(descriptor) {
                for line in recipeLines {
                    if let ingredient = ingredients.first(where: { $0.id == line.ingredientId }) {
                        let newRecipe = Recipe(
                            menuItem: menuItem,
                            inventoryItem: ingredient,
                            quantityRequired: line.qty,
                            quantityUnit: ingredient.unit
                        )
                        modelContext.insert(newRecipe)
                    }
                }
            }
            
        default:
            break
        }

        menuItem.stockTrackingMode = StockTrackingMode(rawValue: trackingMode)?.rawValue ?? trackingMode
        menuItem.updatedAt = Date()
        menuItem.isSynced = false
        modelContext.saveWithLogging(label: #function)
        
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }
    
    // MARK: - Phase 3: Supplier & Inventory Edit
    
    func addSupplier(
        name: String,
        contactName: String?,
        phone: String?,
        email: String?,
        address: String?,
        taxId: String? = nil,
        paymentTerms: String? = nil,
        defaultLeadTimeDays: Int = 7
    ) {
        guard let modelContext = modelContext else { return }

        let supplier = Supplier(
            name: name,
            contactName: contactName,
            phone: phone,
            email: email,
            address: address,
            taxId: taxId,
            paymentTerms: paymentTerms,
            defaultLeadTimeDays: defaultLeadTimeDays
        )
        modelContext.insert(supplier)
        modelContext.saveWithLogging(label: #function)

        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }

    func updateSupplier(
        _ supplier: Supplier,
        name: String,
        contactName: String?,
        phone: String?,
        email: String?,
        address: String?,
        taxId: String?,
        paymentTerms: String?,
        defaultLeadTimeDays: Int
    ) {
        guard let modelContext = modelContext else { return }
        supplier.name = name
        supplier.contactName = contactName
        supplier.phone = phone
        supplier.email = email
        supplier.address = address
        supplier.taxId = taxId
        supplier.paymentTerms = paymentTerms
        supplier.defaultLeadTimeDays = defaultLeadTimeDays
        supplier.updatedAt = Date()
        supplier.isSynced = false
        modelContext.saveWithLogging(label: #function)

        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }

    func deleteSupplier(_ supplier: Supplier) {
        guard let modelContext = modelContext else { return }
        supplier.isDeleted = true
        supplier.updatedAt = Date()
        supplier.isSynced = false
        // Unlink inventory items
        for item in supplier.inventoryItems {
            item.supplier = nil
            item.updatedAt = Date()
            item.isSynced = false
        }
        modelContext.saveWithLogging(label: #function)

        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }
    
    func updateInventoryItem(
        item: InventoryItem,
        name: String,
        sku: String?,
        unit: String,
        reorderLevel: Double,
        costPrice: Double,
        outOfStockPolicy: OutOfStockPolicy = .allowNegative,
        safetyStockLevel: Double = 0.0,
        maxStockLevel: Double = 0.0,
        leadTimeDays: Int = 1,
        supplierId: UUID?,
        category: String?,
        storageLocation: String?,
        barcode: String?
    ) {
        guard let modelContext = modelContext else { return }

        let requestedUnit = UnitOfMeasure.parse(unit)
        let storedUnit = UnitOfMeasure.parse(item.unit)
        // Do not rewrite the unit of an item with movement history: its lots and
        // transactions are expressed in that existing unit. The cost calculator
        // still converts recipe quantities safely in that case.
        let canCanonicalizeStoredUnit = item.currentQuantity == 0 && item.transactions.isEmpty
        let targetUnit: UnitOfMeasure?
        if canCanonicalizeStoredUnit, let requestedUnit {
            let canonicalUnit = InventoryUnitNormalization.normalize(
                quantity: 0,
                unit: requestedUnit.rawValue,
                unitCost: 0
            ).unit
            targetUnit = UnitOfMeasure.parse(canonicalUnit)
        } else {
            targetUnit = storedUnit
        }
        let normalized = (requestedUnit.flatMap { source in targetUnit.map { InventoryUnitNormalization.convert(quantity: reorderLevel, unit: source, unitCost: costPrice, to: $0) } })
            ?? InventoryUnitNormalization.normalize(quantity: reorderLevel, unit: unit, unitCost: costPrice)
        let normalizedSafety = requestedUnit.flatMap { source in
            targetUnit.flatMap { UnitOfMeasure.convert(safetyStockLevel, from: source, to: $0) }
        } ?? safetyStockLevel
        let normalizedMaximum = requestedUnit.flatMap { source in
            targetUnit.flatMap { UnitOfMeasure.convert(maxStockLevel, from: source, to: $0) }
        } ?? maxStockLevel
        
        item.name = name
        item.sku = sku
        item.unit = normalized.unit
        item.reorderLevel = normalized.quantity
        item.costPrice = normalized.unitCost
        item.outOfStockPolicy = outOfStockPolicy
        item.safetyStockLevel = normalizedSafety
        item.maxStockLevel = normalizedMaximum
        item.leadTimeDays = leadTimeDays
        item.category = category
        item.storageLocation = storageLocation
        item.barcode = barcode
        
        if let supplierId = supplierId {
            let desc = FetchDescriptor<Supplier>()
            if let suppliers = try? modelContext.fetch(desc),
               let supplier = suppliers.first(where: { $0.id == supplierId }) {
                item.supplier = supplier
            } else {
                item.supplier = nil
            }
        } else {
            item.supplier = nil
        }
        
        item.updatedAt = Date()
        item.isSynced = false
        modelContext.saveWithLogging(label: #function)
        
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }
    
    func deleteInventoryItem(item: InventoryItem) {
        guard let modelContext = modelContext else { return }
        
        item.isDeleted = true
        item.isSynced = false
        item.updatedAt = Date()
        modelContext.saveWithLogging(label: #function)
        
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }
    
    func addInventoryItem(
        name: String,
        sku: String?,
        unit: String,
        initialQuantity: Double = 0.0,
        reorderLevel: Double,
        costPrice: Double,
        outOfStockPolicy: OutOfStockPolicy = .allowNegative,
        safetyStockLevel: Double = 0.0,
        maxStockLevel: Double = 0.0,
        leadTimeDays: Int = 1,
        supplierId: UUID?,
        category: String?,
        storageLocation: String?,
        barcode: String?,
        activeBranch: Branch?
    ) {
        guard let modelContext = modelContext, let activeBranch else {
            AppLogger.inventory.error("Refused inventory item creation without an active branch")
            return
        }
        
        var selectedSupplier: Supplier? = nil
        if let supplierId = supplierId {
            let desc = FetchDescriptor<Supplier>()
            if let suppliers = try? modelContext.fetch(desc) {
                selectedSupplier = suppliers.first(where: { $0.id == supplierId })
            }
        }

        let normalized = InventoryUnitNormalization.normalize(quantity: reorderLevel, unit: unit, unitCost: costPrice)
        let normalizedInitial = InventoryUnitNormalization.normalize(quantity: max(0, initialQuantity), unit: unit, unitCost: costPrice).quantity
        let normalizedSafety = InventoryUnitNormalization.normalize(quantity: safetyStockLevel, unit: unit, unitCost: 0).quantity
        let normalizedMaximum = InventoryUnitNormalization.normalize(quantity: maxStockLevel, unit: unit, unitCost: 0).quantity
        
        let newItem = InventoryItem(
            name: name,
            sku: sku,
            unit: normalized.unit,
            currentQuantity: normalizedInitial,
            reorderLevel: normalized.quantity,
            costPrice: normalized.unitCost,
            outOfStockPolicy: outOfStockPolicy,
            supplier: selectedSupplier,
            branch: activeBranch,
            safetyStockLevel: normalizedSafety,
            maxStockLevel: normalizedMaximum,
            leadTimeDays: leadTimeDays,
            category: category,
            storageLocation: storageLocation,
            barcode: barcode
        )
        modelContext.insert(newItem)

        if normalizedInitial > 0 {
            let openTxn = InventoryTransaction(
                item: newItem,
                transactionType: InventoryMovementType.opening.rawValue,
                quantity: normalizedInitial,
                costPrice: normalized.unitCost,
                notes: "ยอดสต๊อกเริ่มต้น (Opening stock)",
                branch: activeBranch,
                reasonCode: "opening"
            )
            modelContext.insert(openTxn)
        }
        
        // Propagate to other branches
        let branchDesc = FetchDescriptor<Branch>()
        if let branches = try? modelContext.fetch(branchDesc) {
            for otherBranch in branches where !otherBranch.isDeleted {
                if otherBranch.id == activeBranch.id {
                    continue
                }
                let copy = InventoryItem(
                    name: name,
                    sku: sku,
                    unit: normalized.unit,
                    currentQuantity: 0.0,
                    reorderLevel: normalized.quantity,
                    costPrice: normalized.unitCost,
                    outOfStockPolicy: outOfStockPolicy,
                    supplier: selectedSupplier,
                    branch: otherBranch,
                    safetyStockLevel: normalizedSafety,
                    maxStockLevel: normalizedMaximum,
                    leadTimeDays: leadTimeDays,
                    category: category,
                    storageLocation: storageLocation,
                    barcode: barcode
                )
                modelContext.insert(copy)
            }
        }
        
        modelContext.saveWithLogging(label: #function)
        
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }

    /// Reconciles an item's current stock to an actual physical count, creating an .adjust audit transaction.
    func adjustItemStock(
        item: InventoryItem,
        toPhysicalCount physicalCount: Double,
        reasonCode: String = "stock_audit",
        notes: String = ""
    ) {
        guard let modelContext = modelContext, let branch = item.branch else { return }
        let diff = physicalCount - item.currentQuantity
        guard abs(diff) > 0.00001 else { return }

        let previousQty = item.currentQuantity
        item.currentQuantity = physicalCount
        item.updatedAt = Date()
        item.isSynced = false

        let autoNotes = "ปรับยอดจาก \(String(format: "%.2f", previousQty)) เป็น \(String(format: "%.2f", physicalCount)) \(item.unit)"
        let fullNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? autoNotes : "\(autoNotes) (\(notes))"

        let txn = InventoryTransaction(
            item: item,
            transactionType: InventoryMovementType.adjust.rawValue,
            quantity: diff,
            costPrice: item.costPrice,
            notes: fullNotes,
            branch: branch,
            reasonCode: reasonCode
        )
        modelContext.insert(txn)

        modelContext.saveWithLogging(label: #function)
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }
    
    func processReturnToSupplier(item: InventoryItem, amountString: String, notes: String) {
        guard let modelContext = modelContext, let branch = item.branch,
              let amount = Double(amountString), amount > 0 else { return }

        let before = item.currentQuantity
        let returned = min(amount, before)
        item.currentQuantity = max(0, before - amount)
        item.updatedAt = Date()
        item.isSynced = false

        // Keep lots in sync with currentQuantity (FEFO drain)
        expiryManager.consumeFEFO(item: item, quantity: returned)

        let txnNote = "Return to Supplier: " + (notes.isEmpty ? "No details" : notes)
        let txn = InventoryTransaction(
            item: item,
            transactionType: InventoryMovementType.returnToSupplier.rawValue,
            quantity: -returned,
            notes: txnNote,
            branch: branch,
            reasonCode: "return_to_supplier"
        )
        modelContext.insert(txn)
        modelContext.saveWithLogging(label: #function)
        
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }
    
    // MARK: - Phase 3: Physical Stock Audit
    
    func commitAudit(
        auditLines: [(item: InventoryItem, physicalCount: Double, notes: String)],
        countSessionId: UUID = UUID()
    ) {
        guard let modelContext = modelContext else { return }
        
        for line in auditLines {
            let item = line.item
            guard let branch = item.branch else {
                AppLogger.inventory.error("Stock audit skipped orphan inventory item \(item.id)")
                continue
            }
            let physicalCount = line.physicalCount
            let diff = physicalCount - item.currentQuantity

            if diff != 0 {
                item.currentQuantity = physicalCount
                item.updatedAt = Date()
                item.isSynced = false

                // Reconcile lots with the physical count so FEFO stays accurate.
                if diff < 0 {
                    // Missing stock → drain lots FEFO by the shortage.
                    expiryManager.consumeFEFO(item: item, quantity: -diff)
                } else {
                    // Found extra stock → register a new adjustment lot at current cost.
                    let adjLotNumber = "ADJ-\(InventoryViewModel.auditLotDateFormatter.string(from: Date()))"
                    expiryManager.registerLot(
                        for: item,
                        quantity: diff,
                        costPrice: item.costPrice,
                        expiryDate: nil,
                        lotNumber: adjLotNumber,
                        sourceTransactionId: nil
                    )
                }

            }

            // Keep one immutable evidence row even when variance is zero. The
            // shared reference groups every line in this physical-count session.
            let evidence = "System \(item.currentQuantity - diff); counted \(physicalCount) \(item.unit)"
            let notesText = line.notes.isEmpty ? evidence : "\(evidence) · \(line.notes)"
            let txn = InventoryTransaction(
                item: item,
                transactionType: InventoryMovementType.adjust.rawValue,
                quantity: diff,
                referenceId: countSessionId,
                notes: notesText,
                branch: branch,
                reasonCode: "stock_audit"
            )
            modelContext.insert(txn)
        }
        
        modelContext.saveWithLogging(label: #function)
        
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }
    
    // MARK: - Catalog CRUD: Products (MenuItem)
    
    @discardableResult
    func addProduct(
        name: String,
        price: Double,
        description: String?,
        categoryId: UUID?,
        isAvailable: Bool,
        barcode: String? = nil,
        sku: String? = nil,
        isTaxInclusive: Bool = true,
        isFavorite: Bool = false,
        isBestseller: Bool = false,
        colorHex: String? = nil,
        imageData: Data? = nil,
        imageData2: Data? = nil,
        imageData3: Data? = nil,
        videoData: Data? = nil,
        taxRate: Double = 7.0,
        deliveryPrices: [(brandName: String, price: Double)] = [],
        nameTranslations: [String: String] = [:],
        descriptionTranslations: [String: String] = [:],
        salesRole: MenuItemSalesRole? = nil,
        isSalesRoleConfirmed: Bool = false
    ) -> MenuItem? {
        guard let modelContext = modelContext else { return nil }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, price.isFinite, price >= 0 else { return nil }
        
        var selectedCategory: Category? = nil
        if let catId = categoryId {
            let desc = FetchDescriptor<Category>()
            if let categories = try? modelContext.fetch(desc) {
                selectedCategory = categories.first(where: { $0.id == catId })
            }
        }
        
        let resolvedSalesRole = salesRole ?? MenuItemSalesRole.inferred(from: selectedCategory?.name)
        let product = MenuItem(
            name: trimmedName,
            itemDescription: description,
            price: price,
            isAvailable: isAvailable,
            taxRate: taxRate,
            category: selectedCategory,
            imageData: imageData,
            imageData2: imageData2,
            imageData3: imageData3,
            videoData: videoData,
            barcode: barcode,
            sku: sku,
            isTaxInclusive: isTaxInclusive,
            isFavorite: isFavorite,
            colorHex: colorHex,
            salesRole: resolvedSalesRole.rawValue,
            isSalesRoleConfirmed: isSalesRoleConfirmed
        )
        product.nameTranslations = nameTranslations
        product.descriptionTranslations = descriptionTranslations
        modelContext.insert(product)
        
        for dp in deliveryPrices {
            let deliveryPrice = DeliveryPrice(brandName: dp.brandName, price: dp.price, menuItem: product)
            modelContext.insert(deliveryPrice)
        }
        
        guard modelContext.saveWithLogging(label: #function) else {
            return nil
        }
        
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }

        return product
    }

    /// One-step create for retail finished goods (sell 1 = deduct 1 stock unit).
    /// Creates MenuItem + InventoryItem (Finished Goods) + Recipe link + optional opening qty.
    @discardableResult
    func createFinishedGood(
        name: String,
        sellPrice: Double,
        costPrice: Double,
        initialQuantity: Double,
        unit: String,
        barcode: String?,
        sku: String?,
        reorderLevel: Double,
        categoryId: UUID?,
        salesRole: MenuItemSalesRole = .main,
        activeBranch: Branch?
    ) -> MenuItem? {
        guard let modelContext = modelContext, let activeBranch else {
            AppLogger.inventory.error("Refused finished-good creation without an active branch")
            return nil
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var selectedCategory: Category? = nil
        if let catId = categoryId {
            let desc = FetchDescriptor<Category>()
            selectedCategory = (try? modelContext.fetch(desc))?.first(where: { $0.id == catId })
        }

        let skuValue: String
        if let sku, !sku.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            skuValue = sku.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            let prefix = trimmed.prefix(4).uppercased().trimmingCharacters(in: .whitespaces)
            skuValue = "FG-\(prefix)-\(Int.random(in: 100...999))"
        }

        let cleanedBarcode = barcode?.trimmingCharacters(in: .whitespacesAndNewlines)
        let barcodeValue = (cleanedBarcode?.isEmpty == false) ? cleanedBarcode : nil

        let stockItem = InventoryItem(
            name: trimmed,
            sku: skuValue,
            unit: unit.isEmpty ? "piece" : unit,
            currentQuantity: max(0, initialQuantity),
            reorderLevel: reorderLevel,
            costPrice: costPrice,
            branch: activeBranch,
            category: "Finished Goods",
            storageLocation: "Front Counter",
            barcode: barcodeValue
        )
        modelContext.insert(stockItem)

        if initialQuantity > 0 {
            let receiveTxn = InventoryTransaction(
                item: stockItem,
                transactionType: InventoryMovementType.receive.rawValue,
                quantity: initialQuantity,
                notes: "Opening stock for finished good",
                branch: activeBranch
            )
            modelContext.insert(receiveTxn)
            modelContext.insert(InventoryLot(
                inventoryItem: stockItem,
                branch: activeBranch,
                lotNumber: "OPEN-\(skuValue)",
                initialQuantity: initialQuantity,
                lotCostPrice: costPrice,
                sourceTransactionId: receiveTxn.id
            ))
        }

        let product = MenuItem(
            name: trimmed,
            price: sellPrice,
            isAvailable: true,
            category: selectedCategory,
            barcode: barcodeValue,
            sku: skuValue,
            stockTrackingMode: StockTrackingMode.finishedGood.rawValue,
            salesRole: salesRole.rawValue,
            isSalesRoleConfirmed: true
        )
        modelContext.insert(product)

        let recipe = Recipe(
            menuItem: product,
            inventoryItem: stockItem,
            quantityRequired: 1.0
        )
        modelContext.insert(recipe)

        product.updatedAt = Date()
        product.isSynced = false
        stockItem.updatedAt = Date()
        stockItem.isSynced = false

        modelContext.saveWithLogging(label: #function)

        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
            await MainActor.run {
                StockAlertEvaluator.refresh(modelContext: modelContext, force: true)
            }
        }

        return product
    }
    
    func updateProduct(
        menuItem: MenuItem,
        name: String,
        price: Double,
        description: String?,
        categoryId: UUID?,
        isAvailable: Bool,
        barcode: String?,
        sku: String?,
        isTaxInclusive: Bool,
        isFavorite: Bool,
        colorHex: String?,
        imageData: Data?,
        imageData2: Data?,
        imageData3: Data?,
        videoData: Data?,
        taxRate: Double,
        deliveryPrices: [(brandName: String, price: Double)],
        nameTranslations: [String: String] = [:],
        descriptionTranslations: [String: String] = [:],
        salesRole: MenuItemSalesRole = .main,
        isSalesRoleConfirmed: Bool = true
    ) {
        guard let modelContext = modelContext else { return }
        
        menuItem.name = name
        menuItem.price = price
        menuItem.itemDescription = description
        menuItem.isAvailable = isAvailable
        menuItem.barcode = barcode
        menuItem.sku = sku
        menuItem.isTaxInclusive = isTaxInclusive
        menuItem.isFavorite = isFavorite
        menuItem.colorHex = colorHex
        menuItem.imageData = imageData
        menuItem.imageData2 = imageData2
        menuItem.imageData3 = imageData3
        menuItem.videoData = videoData
        menuItem.taxRate = taxRate
        menuItem.nameTranslations = nameTranslations
        menuItem.descriptionTranslations = descriptionTranslations
        menuItem.salesRole = salesRole.rawValue
        menuItem.isSalesRoleConfirmed = isSalesRoleConfirmed
        
        if let catId = categoryId {
            let desc = FetchDescriptor<Category>()
            if let categories = try? modelContext.fetch(desc) {
                menuItem.category = categories.first(where: { $0.id == catId })
            }
        } else {
            menuItem.category = nil
        }
        
        // Preserve IDs so edits upsert cleanly; tombstones remove deleted brands remotely.
        let requestedBrands = Set(deliveryPrices.map(\.brandName))
        for old in menuItem.deliveryPrices where !requestedBrands.contains(old.brandName) {
            old.isDeleted = true
            old.isSynced = false
            old.updatedAt = Date()
        }
        for value in deliveryPrices {
            if let existing = menuItem.deliveryPrices.first(where: { $0.brandName == value.brandName }) {
                existing.price = value.price
                existing.isDeleted = false
                existing.isSynced = false
                existing.updatedAt = Date()
            } else {
                modelContext.insert(DeliveryPrice(brandName: value.brandName, price: value.price, menuItem: menuItem))
            }
        }
        
        menuItem.updatedAt = Date()
        menuItem.isSynced = false
        modelContext.saveWithLogging(label: #function)
        
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }

    
    func deleteProduct(menuItem: MenuItem) {
        guard let modelContext = modelContext else { return }
        
        menuItem.isDeleted = true
        menuItem.isSynced = false
        menuItem.updatedAt = Date()
        modelContext.saveWithLogging(label: #function)
        
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }
    
    func updateProductModifierGroups(menuItem: MenuItem, selectedGroupIds: [UUID]) {
        guard let modelContext = modelContext else { return }
        
        // Delete old relations
        let relations = menuItem.modifierGroupsRelations
        for rel in relations {
            if let group = rel.modifierGroup, !selectedGroupIds.contains(group.id) {
                modelContext.delete(rel)
            }
        }
        
        // Add new relations
        let descriptor = FetchDescriptor<ModifierGroup>()
        if let allGroups = try? modelContext.fetch(descriptor) {
            for groupId in selectedGroupIds {
                if !relations.contains(where: { $0.modifierGroup?.id == groupId }) {
                    if let group = allGroups.first(where: { $0.id == groupId }) {
                        let newRel = MenuItemModifierGroup(menuItem: menuItem, modifierGroup: group)
                        modelContext.insert(newRel)
                    }
                }
            }
        }
        
        menuItem.updatedAt = Date()
        menuItem.isSynced = false
        modelContext.saveWithLogging(label: #function)
        
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }
    
    // MARK: - Catalog CRUD: Categories
    
    func addCategory(name: String, description: String?) {
        guard let modelContext = modelContext else { return }
        let nameKey = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let existing = (try? modelContext.fetch(FetchDescriptor<Category>())) ?? []
        if existing.contains(where: { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == nameKey }) {
            return
        }
        
        let category = Category(name: name, categoryDescription: description)
        modelContext.insert(category)
        modelContext.saveWithLogging(label: #function)
        
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }
    
    func updateCategory(category: Category, name: String, description: String?) {
        guard let modelContext = modelContext else { return }
        let nameKey = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let existing = (try? modelContext.fetch(FetchDescriptor<Category>())) ?? []
        if existing.contains(where: { $0.id != category.id && $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == nameKey }) {
            return
        }
        
        category.name = name
        category.categoryDescription = description
        
        category.updatedAt = Date()
        category.isSynced = false
        modelContext.saveWithLogging(label: #function)
        
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }
    
    func deleteCategory(category: Category) {
        guard let modelContext = modelContext else { return }
        
        category.isDeleted = true
        category.isSynced = false
        category.updatedAt = Date()
        modelContext.saveWithLogging(label: #function)
        
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }
    
    // MARK: - Catalog CRUD: Extras (Modifier Groups & Modifiers)
    
    func addModifierGroup(name: String, minSelection: Int, maxSelection: Int) {
        guard let modelContext = modelContext else { return }
        
        let group = ModifierGroup(name: name, minSelection: minSelection, maxSelection: maxSelection)
        modelContext.insert(group)
        modelContext.saveWithLogging(label: #function)
        
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }
    
    func updateModifierGroup(group: ModifierGroup, name: String, minSelection: Int, maxSelection: Int) {
        guard let modelContext = modelContext else { return }
        
        group.name = name
        group.minSelection = minSelection
        group.maxSelection = maxSelection
        
        group.updatedAt = Date()
        group.isSynced = false
        modelContext.saveWithLogging(label: #function)
        
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }
    
    func deleteModifierGroup(group: ModifierGroup) {
        guard let modelContext = modelContext else { return }
        
        modelContext.delete(group)
        modelContext.saveWithLogging(label: #function)
        
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }
    
    func addModifier(to group: ModifierGroup, name: String, extraPrice: Double, inventoryItemId: UUID?, qtyRequired: Double?) {
        guard let modelContext = modelContext else { return }
        
        var linkedIngredient: InventoryItem? = nil
        if let ingredientId = inventoryItemId {
            let desc = FetchDescriptor<InventoryItem>()
            if let ingredients = try? modelContext.fetch(desc) {
                linkedIngredient = ingredients.first(where: { $0.id == ingredientId })
            }
        }
        
        let modifier = Modifier(
            modifierGroup: group,
            name: name,
            extraPrice: extraPrice,
            inventoryItemLink: linkedIngredient,
            quantityRequired: qtyRequired
        )
        modelContext.insert(modifier)
        modelContext.saveWithLogging(label: #function)
        
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }
    
    func updateModifier(modifier: Modifier, name: String, extraPrice: Double, inventoryItemId: UUID?, qtyRequired: Double?) {
        guard let modelContext = modelContext else { return }
        
        modifier.name = name
        modifier.extraPrice = extraPrice
        modifier.quantityRequired = qtyRequired
        
        if let ingredientId = inventoryItemId {
            let desc = FetchDescriptor<InventoryItem>()
            if let ingredients = try? modelContext.fetch(desc) {
                modifier.inventoryItemLink = ingredients.first(where: { $0.id == ingredientId })
            }
        } else {
            modifier.inventoryItemLink = nil
        }
        
        modifier.updatedAt = Date()
        modifier.isSynced = false
        modelContext.saveWithLogging(label: #function)
        
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }
    
    func deleteModifier(modifier: Modifier) {
        guard let modelContext = modelContext else { return }
        
        modelContext.delete(modifier)
        modelContext.saveWithLogging(label: #function)
        
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }
    
    // MARK: - Enterprise Multi-Branch Workflows
    
    func seedDefaultBranchIfNeeded() {
        guard let modelContext = modelContext else { return }
        
        let branchDesc = FetchDescriptor<Branch>()
        let existingBranches = (try? modelContext.fetch(branchDesc)) ?? []
        
        // Online branches are canonical server records. Creating one here while
        // the initial pull is still settling can split one store into two UUIDs.
        // Local seeding is reserved for the deliberately offline product.
        if existingBranches.isEmpty && OfflineSyncModeController.isOfflineSubscriptionPlan {
            let mainBranch = Branch(name: "Main Branch", location: "Headquarters", phone: "02-123-4567")
            modelContext.insert(mainBranch)
            
            // Link existing branchless models to Main Branch
            let itemDesc = FetchDescriptor<InventoryItem>()
            if let items = try? modelContext.fetch(itemDesc) {
                for item in items {
                    if item.branch == nil {
                        item.branch = mainBranch
                    }
                }
            }
            
            modelContext.saveWithLogging(label: #function)
            BranchContext.shared.select(mainBranch)
        } else if !existingBranches.isEmpty {
            _ = try? BranchContext.shared.bootstrap(in: modelContext, createDefaultIfEmpty: false)
        }
    }
    
    func addBranch(name: String, location: String?, phone: String?) {
        guard let modelContext = modelContext else { return }
        let newBranch = Branch(name: name, location: location, phone: phone)
        modelContext.insert(newBranch)
        modelContext.saveWithLogging(label: #function)

        // Auto-activate when no valid branch is currently selected so
        // branch-dependent features (device pairing, POS) work right away.
        if BranchContext.shared.activeBranchID == nil {
            BranchContext.shared.select(newBranch)
        }
        
        // Let's copy existing items to the new branch so it has the same product catalog (starting with 0 stock)
        let itemDesc = FetchDescriptor<InventoryItem>()
        if let items = try? modelContext.fetch(itemDesc) {
            // Only copy distinct SKUs from the primary/other branch catalog
            var addedSKUs = Set<String>()
            for item in items {
                guard let sku = item.sku else { continue }
                if !addedSKUs.contains(sku) {
                    addedSKUs.insert(sku)
                    // Create item copy for new branch
                    let copy = InventoryItem(
                        name: item.name,
                        sku: item.sku,
                        unit: item.unit,
                        currentQuantity: 0.0,
                        reorderLevel: item.reorderLevel,
                        costPrice: item.costPrice,
                        outOfStockPolicy: item.outOfStockPolicy,
                        supplier: item.supplier,
                        branch: newBranch,
                        category: item.category,
                        storageLocation: item.storageLocation,
                        barcode: item.barcode
                    )
                    modelContext.insert(copy)
                }
            }
            modelContext.saveWithLogging(label: #function)
        }
    }
    
    // MARK: - Purchase Order Workflows
    
    func createPurchaseOrder(
        poNumber: String,
        supplier: Supplier,
        branch: Branch,
        itemsList: [(item: InventoryItem, qtyOrdered: Double, unitCost: Double)],
        notes: String?
    ) {
        guard let modelContext = modelContext else { return }
        
        let newPO = PurchaseOrder(
            poNumber: poNumber,
            supplier: supplier,
            branch: branch,
            status: "draft",
            orderDate: Date(),
            notes: notes
        )
        modelContext.insert(newPO)
        
        for line in itemsList {
            let poItem = PurchaseOrderItem(
                purchaseOrder: newPO,
                inventoryItem: line.item,
                quantityOrdered: line.qtyOrdered,
                quantityReceived: 0.0,
                unitCost: line.unitCost
            )
            modelContext.insert(poItem)
        }
        
        modelContext.saveWithLogging(label: #function)
        
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }
    
    func sendPurchaseOrder(po: PurchaseOrder) {
        guard let modelContext = modelContext else { return }
        po.status = "sent"
        po.updatedAt = Date()
        po.isSynced = false
        modelContext.saveWithLogging(label: #function)
        
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }
    
    func commitPurchaseOrderReceive(
        po: PurchaseOrder,
        receivedItems: [UUID: (qtyReceived: Double, unitCost: Double, expiryDate: Date?, lotNumber: String?)],
        notes: String
    ) {
        guard let modelContext = modelContext, let purchaseBranch = po.branch else {
            AppLogger.inventory.error("Refused purchase-order receipt without a branch")
            return
        }
        
        po.deliveryDate = Date()
        po.updatedAt = Date()
        po.isSynced = false
        
        var allFullyReceived = true
        
        for poItem in po.items {
            guard let key = poItem.inventoryItem?.id, let received = receivedItems[key] else { continue }
            
            let requestedQty = received.qtyReceived
            let newQty = InventoryReceivingPolicy.acceptedQuantity(
                requested: requestedQty,
                ordered: poItem.quantityOrdered,
                alreadyReceived: poItem.quantityReceived
            )
            guard newQty > 0, received.unitCost.isFinite, received.unitCost >= 0 else { continue }
            let unitCost = received.unitCost
            
            poItem.quantityReceived += newQty
            poItem.unitCost = unitCost
            poItem.expiryDate = received.expiryDate
            poItem.lotNumber = received.lotNumber
            poItem.updatedAt = Date()
            poItem.isSynced = false
            
            if poItem.quantityReceived < poItem.quantityOrdered {
                allFullyReceived = false
            }
            
            if let invItem = poItem.inventoryItem, newQty > 0 {
                // Update quantity
                let oldQty = max(invItem.currentQuantity, 0.0)
                let oldCost = invItem.costPrice

                // WAC (Weighted Average Cost)
                let totalQty = oldQty + newQty
                if totalQty > 0 {
                    invItem.costPrice = ((oldQty * oldCost) + (newQty * unitCost)) / totalQty
                } else {
                    invItem.costPrice = unitCost
                }

                invItem.currentQuantity += newQty
                invItem.updatedAt = Date()
                invItem.isSynced = false

                // Transaction
                let txnNote = "PO Receive #\(po.poNumber) (Partial)" + (notes.isEmpty ? "" : " (\(notes))")
                let txn = InventoryTransaction(
                    item: invItem,
                    transactionType: InventoryMovementType.receive.rawValue,
                    quantity: newQty,
                    costPrice: unitCost,
                    notes: txnNote,
                    branch: purchaseBranch,
                    reasonCode: "receive"
                )
                modelContext.insert(txn)

                // Lot registration for FEFO tracking
                let receivedLot = expiryManager.registerLot(
                    for: invItem,
                    quantity: newQty,
                    costPrice: unitCost,
                    expiryDate: received.expiryDate,
                    lotNumber: received.lotNumber?.isEmpty == true ? "PO-\(po.poNumber)" : (received.lotNumber ?? "PO-\(po.poNumber)"),
                    sourceTransactionId: txn.id
                )

                // Every PO receipt creates incoming-inspection evidence. The
                // receiving UI can enrich temperature/packaging fields; safe
                // defaults still preserve who/what/when/lot linkage.
                modelContext.insert(IncomingInspection(
                    purchaseOrderId: po.id,
                    purchaseOrderItemId: poItem.id,
                    inventoryItemId: invItem.id,
                    lotId: receivedLot?.id,
                    branchId: purchaseBranch.id,
                    supplierId: po.supplier?.id,
                    receivedQuantity: newQty,
                    decision: .accepted,
                    reasonCode: "po_receive"
                ))
            }
        }
        
        if allFullyReceived {
            po.status = "received"
        } else {
            let totalReceived = po.items.reduce(0.0) { $0 + $1.quantityReceived }
            if totalReceived > 0 {
                po.status = "partially_received"
            } else {
                po.status = "sent"
            }
        }
        
        modelContext.saveWithLogging(label: #function)
        
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }
    
    func cancelPurchaseOrder(po: PurchaseOrder) {
        guard let modelContext = modelContext else { return }
        po.status = "cancelled"
        po.updatedAt = Date()
        po.isSynced = false
        modelContext.saveWithLogging(label: #function)
        
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }
    
    func deletePurchaseOrder(po: PurchaseOrder) {
        guard let modelContext = modelContext else { return }
        // Purchase orders are audit evidence. Never physically remove them here:
        // the sync engine needs the tombstone in order to delete the same record
        // on every device and on Supabase.
        po.isDeleted = true
        po.isSynced = false
        po.updatedAt = Date()
        for line in po.items {
            line.isDeleted = true
            line.isSynced = false
            line.updatedAt = po.updatedAt
        }
        modelContext.saveWithLogging(label: #function)
        
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }
    
    // MARK: - Stock Transfer between Branches
    
    func transferStock(
        item: InventoryItem,
        fromBranch: Branch,
        toBranch: Branch,
        quantity: Double,
        notes: String
    ) {
        guard let modelContext = modelContext else { return }
        guard quantity > 0, quantity <= item.currentQuantity else { return }
        let transferId = UUID()
        
        // 1. Deduct quantity from source branch item
        item.currentQuantity -= quantity
        item.updatedAt = Date()
        item.isSynced = false

        // Keep source lots in sync (FEFO drain) — GS1 lot traceability
        let transferredLots = expiryManager.consumeFEFO(item: item, quantity: quantity)
        
        // 2. Find target branch item with the same SKU (or name if no SKU)
        let itemDesc = FetchDescriptor<InventoryItem>()
        let allItems = (try? modelContext.fetch(itemDesc)) ?? []
        
        var targetItem: InventoryItem? = nil
        if let sku = item.sku, !sku.isEmpty {
            targetItem = allItems.first(where: { $0.branch?.id == toBranch.id && $0.sku == sku })
        } else {
            targetItem = allItems.first(where: { $0.branch?.id == toBranch.id && $0.name == item.name })
        }
        
        // If not found, create it in target branch
        if targetItem == nil {
            let newItem = InventoryItem(
                name: item.name,
                sku: item.sku,
                unit: item.unit,
                currentQuantity: 0.0,
                reorderLevel: item.reorderLevel,
                costPrice: item.costPrice,
                outOfStockPolicy: item.outOfStockPolicy,
                supplier: item.supplier,
                branch: toBranch,
                category: item.category,
                storageLocation: item.storageLocation,
                barcode: item.barcode
            )
            modelContext.insert(newItem)
            targetItem = newItem
        }
        
        guard let target = targetItem else { return }
        
        // 3. Add quantity to target item
        target.currentQuantity += quantity
        target.updatedAt = Date()
        target.isSynced = false

        // Preserve the source lot identity/expiry and cost at the destination.
        for allocation in transferredLots.consumed {
            modelContext.insert(InventoryLot(
                inventoryItem: target,
                branch: toBranch,
                lotNumber: allocation.lot.lotNumber,
                receivedDate: Date(),
                expiryDate: allocation.lot.expiryDate,
                initialQuantity: allocation.quantityTaken,
                lotCostPrice: allocation.lot.lotCostPrice,
                sourceTransactionId: transferId
            ))
        }
        
        // 4. Create Transactions
        let txnOut = InventoryTransaction(
            item: item,
            transactionType: InventoryMovementType.transferOut.rawValue,
            quantity: -quantity,
            costPrice: transferredLots.consumed.isEmpty
                ? item.costPrice
                : transferredLots.totalCOGS / quantity,
            referenceId: transferId,
            notes: "Transfer to \(toBranch.name)" + (notes.isEmpty ? "" : " (\(notes))"),
            branch: fromBranch,
            reasonCode: "transfer"
        )

        let txnIn = InventoryTransaction(
            item: target,
            transactionType: InventoryMovementType.transferIn.rawValue,
            quantity: quantity,
            costPrice: txnOut.costPrice,
            referenceId: transferId,
            notes: "Transfer from \(fromBranch.name)" + (notes.isEmpty ? "" : " (\(notes))"),
            branch: toBranch,
            reasonCode: "transfer"
        )
        
        modelContext.insert(txnOut)
        modelContext.insert(txnIn)
        
        modelContext.saveWithLogging(label: #function)
        
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }
}
