import Foundation
import SwiftData
import SwiftUI

@Observable
@MainActor
final class InventoryViewModel {
    var modelContext: ModelContext?
    
    // UI selection and sheet states
    var selectedItem: InventoryItem?
    var showingReceiveSheet = false
    var showingWasteSheet = false
    
    init(modelContext: ModelContext? = nil) {
        self.modelContext = modelContext
    }
    
    func processReceive(item: InventoryItem, amountString: String, costString: String, notes: String) {
        guard let modelContext = modelContext, let amount = Double(amountString) else { return }
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
            transactionType: "receive",
            quantity: amount,
            costPrice: newUnitCost,
            notes: notes.isEmpty ? "Supplier delivery receive" : notes,
            branch: item.branch
        )
        modelContext.insert(txn)
        try? modelContext.save()
        
        // Trigger background sync task
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }
    
    func processWaste(item: InventoryItem, amountString: String, reasonSelection: String, notes: String) {
        guard let modelContext = modelContext, let amount = Double(amountString) else { return }
        
        // Subtract item quantity
        item.currentQuantity -= amount
        item.updatedAt = Date()
        item.isSynced = false
        
        let txnNote = "Waste: \(reasonSelection)" + (notes.isEmpty ? "" : " (\(notes))")
        let txn = InventoryTransaction(
            item: item,
            transactionType: "waste",
            quantity: -amount,
            notes: txnNote,
            branch: item.branch
        )
        modelContext.insert(txn)
        try? modelContext.save()
        
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
        
        // 1. Delete existing recipes
        let oldRecipes = menuItem.recipes
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
                    let newRecipe = Recipe(menuItem: menuItem, inventoryItem: ingredient, quantityRequired: 1.0)
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
                    category: "Finished Goods",
                    storageLocation: "Front Counter"
                )
                modelContext.insert(newIngredient)
                
                let newRecipe = Recipe(menuItem: menuItem, inventoryItem: newIngredient, quantityRequired: 1.0)
                modelContext.insert(newRecipe)
            }
            
        case "recipe_based":
            let descriptor = FetchDescriptor<InventoryItem>()
            if let ingredients = try? modelContext.fetch(descriptor) {
                for line in recipeLines {
                    if let ingredient = ingredients.first(where: { $0.id == line.ingredientId }) {
                        let newRecipe = Recipe(menuItem: menuItem, inventoryItem: ingredient, quantityRequired: line.qty)
                        modelContext.insert(newRecipe)
                    }
                }
            }
            
        default:
            break
        }
        
        menuItem.updatedAt = Date()
        menuItem.isSynced = false
        try? modelContext.save()
        
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }
    
    // MARK: - Phase 3: Supplier & Inventory Edit
    
    func addSupplier(name: String, contactName: String?, phone: String?, email: String?, address: String?) {
        guard let modelContext = modelContext else { return }
        
        let supplier = Supplier(
            name: name,
            contactName: contactName,
            phone: phone,
            email: email,
            address: address
        )
        modelContext.insert(supplier)
        try? modelContext.save()
        
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
        supplierId: UUID?,
        category: String?,
        storageLocation: String?,
        barcode: String?
    ) {
        guard let modelContext = modelContext else { return }
        
        item.name = name
        item.sku = sku
        item.unit = unit
        item.reorderLevel = reorderLevel
        item.costPrice = costPrice
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
        try? modelContext.save()
        
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }
    
    func deleteInventoryItem(item: InventoryItem) {
        guard let modelContext = modelContext else { return }
        
        modelContext.delete(item)
        try? modelContext.save()
        
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }
    
    func addInventoryItem(
        name: String,
        sku: String?,
        unit: String,
        reorderLevel: Double,
        costPrice: Double,
        supplierId: UUID?,
        category: String?,
        storageLocation: String?,
        barcode: String?,
        activeBranch: Branch?
    ) {
        guard let modelContext = modelContext else { return }
        
        var selectedSupplier: Supplier? = nil
        if let supplierId = supplierId {
            let desc = FetchDescriptor<Supplier>()
            if let suppliers = try? modelContext.fetch(desc) {
                selectedSupplier = suppliers.first(where: { $0.id == supplierId })
            }
        }
        
        let newItem = InventoryItem(
            name: name,
            sku: sku,
            unit: unit,
            currentQuantity: 0.0,
            reorderLevel: reorderLevel,
            costPrice: costPrice,
            supplier: selectedSupplier,
            branch: activeBranch,
            category: category,
            storageLocation: storageLocation,
            barcode: barcode
        )
        modelContext.insert(newItem)
        
        // Propagate to other branches
        let branchDesc = FetchDescriptor<Branch>()
        if let branches = try? modelContext.fetch(branchDesc) {
            for otherBranch in branches {
                if let activeBranch = activeBranch, otherBranch.id == activeBranch.id {
                    continue
                }
                let copy = InventoryItem(
                    name: name,
                    sku: sku,
                    unit: unit,
                    currentQuantity: 0.0,
                    reorderLevel: reorderLevel,
                    costPrice: costPrice,
                    supplier: selectedSupplier,
                    branch: otherBranch,
                    category: category,
                    storageLocation: storageLocation,
                    barcode: barcode
                )
                modelContext.insert(copy)
            }
        }
        
        try? modelContext.save()
        
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }
    
    func processReturnToSupplier(item: InventoryItem, amountString: String, notes: String) {
        guard let modelContext = modelContext, let amount = Double(amountString) else { return }
        
        item.currentQuantity -= amount
        item.updatedAt = Date()
        item.isSynced = false
        
        let txnNote = "Return to Supplier: " + (notes.isEmpty ? "No details" : notes)
        let txn = InventoryTransaction(
            item: item,
            transactionType: "return_to_supplier",
            quantity: -amount,
            notes: txnNote,
            branch: item.branch
        )
        modelContext.insert(txn)
        try? modelContext.save()
        
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }
    
    // MARK: - Phase 3: Physical Stock Audit
    
    func commitAudit(auditLines: [(item: InventoryItem, physicalCount: Double, notes: String)]) {
        guard let modelContext = modelContext else { return }
        
        for line in auditLines {
            let item = line.item
            let physicalCount = line.physicalCount
            let diff = physicalCount - item.currentQuantity
            
            if diff != 0 {
                item.currentQuantity = physicalCount
                item.updatedAt = Date()
                item.isSynced = false
                
                let notesText = line.notes.isEmpty ? "Physical audit adjustment" : line.notes
                let txn = InventoryTransaction(
                    item: item,
                    transactionType: "adjust",
                    quantity: diff,
                    notes: notesText,
                    branch: item.branch
                )
                modelContext.insert(txn)
            }
        }
        
        try? modelContext.save()
        
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }
    
    // MARK: - Catalog CRUD: Products (MenuItem)
    
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
        colorHex: String? = nil,
        imageData: Data? = nil,
        taxRate: Double = 7.0,
        deliveryPrices: [(brandName: String, price: Double)] = []
    ) {
        guard let modelContext = modelContext else { return }
        
        var selectedCategory: Category? = nil
        if let catId = categoryId {
            let desc = FetchDescriptor<Category>()
            if let categories = try? modelContext.fetch(desc) {
                selectedCategory = categories.first(where: { $0.id == catId })
            }
        }
        
        let product = MenuItem(
            name: name,
            itemDescription: description,
            price: price,
            isAvailable: isAvailable,
            taxRate: taxRate,
            category: selectedCategory,
            imageData: imageData,
            barcode: barcode,
            sku: sku,
            isTaxInclusive: isTaxInclusive,
            isFavorite: isFavorite,
            colorHex: colorHex
        )
        modelContext.insert(product)
        
        for dp in deliveryPrices {
            let deliveryPrice = DeliveryPrice(brandName: dp.brandName, price: dp.price, menuItem: product)
            modelContext.insert(deliveryPrice)
        }
        
        try? modelContext.save()
        
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
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
        taxRate: Double,
        deliveryPrices: [(brandName: String, price: Double)]
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
        menuItem.taxRate = taxRate
        
        if let catId = categoryId {
            let desc = FetchDescriptor<Category>()
            if let categories = try? modelContext.fetch(desc) {
                menuItem.category = categories.first(where: { $0.id == catId })
            }
        } else {
            menuItem.category = nil
        }
        
        // Update delivery prices relationship
        let oldPrices = menuItem.deliveryPrices
        for op in oldPrices {
            modelContext.delete(op)
        }
        menuItem.deliveryPrices.removeAll()
        
        for dp in deliveryPrices {
            let deliveryPrice = DeliveryPrice(brandName: dp.brandName, price: dp.price, menuItem: menuItem)
            modelContext.insert(deliveryPrice)
        }
        
        menuItem.updatedAt = Date()
        menuItem.isSynced = false
        try? modelContext.save()
        
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }

    
    func deleteProduct(menuItem: MenuItem) {
        guard let modelContext = modelContext else { return }
        
        modelContext.delete(menuItem)
        try? modelContext.save()
        
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
        try? modelContext.save()
        
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }
    
    // MARK: - Catalog CRUD: Categories
    
    func addCategory(name: String, description: String?) {
        guard let modelContext = modelContext else { return }
        
        let category = Category(name: name, categoryDescription: description)
        modelContext.insert(category)
        try? modelContext.save()
        
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }
    
    func updateCategory(category: Category, name: String, description: String?) {
        guard let modelContext = modelContext else { return }
        
        category.name = name
        category.categoryDescription = description
        
        category.updatedAt = Date()
        category.isSynced = false
        try? modelContext.save()
        
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }
    
    func deleteCategory(category: Category) {
        guard let modelContext = modelContext else { return }
        
        modelContext.delete(category)
        try? modelContext.save()
        
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }
    
    // MARK: - Catalog CRUD: Extras (Modifier Groups & Modifiers)
    
    func addModifierGroup(name: String, minSelection: Int, maxSelection: Int) {
        guard let modelContext = modelContext else { return }
        
        let group = ModifierGroup(name: name, minSelection: minSelection, maxSelection: maxSelection)
        modelContext.insert(group)
        try? modelContext.save()
        
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
        try? modelContext.save()
        
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }
    
    func deleteModifierGroup(group: ModifierGroup) {
        guard let modelContext = modelContext else { return }
        
        modelContext.delete(group)
        try? modelContext.save()
        
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
        try? modelContext.save()
        
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
        try? modelContext.save()
        
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }
    
    func deleteModifier(modifier: Modifier) {
        guard let modelContext = modelContext else { return }
        
        modelContext.delete(modifier)
        try? modelContext.save()
        
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }
    
    // MARK: - Enterprise Multi-Branch Workflows
    
    func seedDefaultBranchIfNeeded() {
        guard let modelContext = modelContext else { return }
        
        let branchDesc = FetchDescriptor<Branch>()
        let existingBranches = (try? modelContext.fetch(branchDesc)) ?? []
        
        if existingBranches.isEmpty {
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
            
            let orderDesc = FetchDescriptor<Order>()
            if let orders = try? modelContext.fetch(orderDesc) {
                for order in orders {
                    if order.branch == nil {
                        order.branch = mainBranch
                    }
                }
            }
            
            let txnDesc = FetchDescriptor<InventoryTransaction>()
            if let txns = try? modelContext.fetch(txnDesc) {
                for txn in txns {
                    if txn.branch == nil {
                        txn.branch = mainBranch
                    }
                }
            }
            
            let sessionDesc = FetchDescriptor<RegisterSession>()
            if let sessions = try? modelContext.fetch(sessionDesc) {
                for session in sessions {
                    if session.branch == nil {
                        session.branch = mainBranch
                    }
                }
            }
            
            try? modelContext.save()
            UserDefaults.standard.set(mainBranch.id.uuidString, forKey: "active_branch_id")
        } else if UserDefaults.standard.string(forKey: "active_branch_id") == nil, let first = existingBranches.first {
            UserDefaults.standard.set(first.id.uuidString, forKey: "active_branch_id")
        }
    }
    
    func addBranch(name: String, location: String?, phone: String?) {
        guard let modelContext = modelContext else { return }
        let newBranch = Branch(name: name, location: location, phone: phone)
        modelContext.insert(newBranch)
        try? modelContext.save()
        
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
                        supplier: item.supplier,
                        branch: newBranch,
                        category: item.category,
                        storageLocation: item.storageLocation,
                        barcode: item.barcode
                    )
                    modelContext.insert(copy)
                }
            }
            try? modelContext.save()
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
        
        try? modelContext.save()
        
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }
    
    func sendPurchaseOrder(po: PurchaseOrder) {
        guard let modelContext = modelContext else { return }
        po.status = "sent"
        po.updatedAt = Date()
        po.isSynced = false
        try? modelContext.save()
        
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }
    
    func commitPurchaseOrderReceive(
        po: PurchaseOrder,
        receivedItems: [UUID: (qtyReceived: Double, unitCost: Double)],
        notes: String
    ) {
        guard let modelContext = modelContext else { return }
        
        po.deliveryDate = Date()
        po.updatedAt = Date()
        po.isSynced = false
        
        var allFullyReceived = true
        
        for poItem in po.items {
            guard let key = poItem.inventoryItem?.id, let received = receivedItems[key] else { continue }
            
            let newQty = received.qtyReceived
            let unitCost = received.unitCost
            
            poItem.quantityReceived += newQty
            poItem.unitCost = unitCost
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
                    transactionType: "receive",
                    quantity: newQty,
                    costPrice: unitCost,
                    notes: txnNote,
                    branch: po.branch
                )
                modelContext.insert(txn)
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
        
        try? modelContext.save()
        
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }
    
    func cancelPurchaseOrder(po: PurchaseOrder) {
        guard let modelContext = modelContext else { return }
        po.status = "cancelled"
        po.updatedAt = Date()
        po.isSynced = false
        try? modelContext.save()
        
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }
    
    func deletePurchaseOrder(po: PurchaseOrder) {
        guard let modelContext = modelContext else { return }
        modelContext.delete(po)
        try? modelContext.save()
        
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
        
        // 1. Deduct quantity from source branch item
        item.currentQuantity -= quantity
        item.updatedAt = Date()
        item.isSynced = false
        
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
        
        // 4. Create Transactions
        let txnOut = InventoryTransaction(
            item: item,
            transactionType: "transfer_out",
            quantity: -quantity,
            notes: "Transfer to \(toBranch.name)" + (notes.isEmpty ? "" : " (\(notes))"),
            branch: fromBranch
        )
        
        let txnIn = InventoryTransaction(
            item: target,
            transactionType: "transfer_in",
            quantity: quantity,
            notes: "Transfer from \(fromBranch.name)" + (notes.isEmpty ? "" : " (\(notes))"),
            branch: toBranch
        )
        
        modelContext.insert(txnOut)
        modelContext.insert(txnIn)
        
        try? modelContext.save()
        
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }
}
