// InventoryView.swift
// AlphaPos — Premium Inventory Interface

import SwiftUI
import SwiftData

struct InventoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \InventoryItem.name) private var inventory: [InventoryItem]
    @Query(sort: \InventoryTransaction.updatedAt, order: .reverse) private var transactions: [InventoryTransaction]
    @Query(sort: \Branch.name) private var branches: [Branch]

    @State private var viewModel = InventoryViewModel()
    @State private var searchText = ""
    @State private var selectedSection = 0 // 0: Raw Materials, 1: Products, 2: Recipes & BOM, 3: Suppliers, 4: Stock Audit
    @State private var showingEditSheet = false
    @State private var showingMovementHistory = false
    @State private var showingAddSheet = false
    @State private var showingReturnSheet = false
    
    // Multi-Branch and sheets states
    @AppStorage("active_branch_id") private var activeBranchId = ""
    @State private var showingBranchManager = false
    @State private var showingPOManager = false
    @State private var showingTransferSheet = false
    
    // High-Volume filters state
    @State private var statusFilter = "All" // "All", "Low Stock", "Out of Stock"
    @State private var selectedCategory = "All" // Category name or "All"

    private var activeBranch: Branch? {
        branches.first(where: { $0.id.uuidString == activeBranchId })
    }

    private var filteredInventory: [InventoryItem] {
        var result = inventory
        
        // Filter by Active Branch!
        if let branch = activeBranch {
            result = result.filter { $0.branch?.id == branch.id }
        }
        
        // 1. Search query (name, sku, barcode)
        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                ($0.sku ?? "").localizedCaseInsensitiveContains(searchText) ||
                ($0.barcode ?? "").localizedCaseInsensitiveContains(searchText)
            }
        }
        
        // 2. Status filter
        switch statusFilter {
        case "Low Stock":
            result = result.filter { $0.currentQuantity <= $0.reorderLevel }
        case "Out of Stock":
            result = result.filter { $0.currentQuantity <= 0.0 }
        default:
            break
        }
        
        // 3. Category filter
        if selectedCategory != "All" {
            result = result.filter { $0.category == selectedCategory }
        }
        
        return result
    }
    
    private var filteredTransactionsList: [InventoryTransaction] {
        if let branch = activeBranch {
            return transactions.filter { $0.branch?.id == branch.id }
        }
        return transactions
    }

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // Outer Inner tab selector
                Picker("Inventory Menu", selection: $selectedSection) {
                    Text("Raw Materials").tag(0)
                    Text("Products").tag(1)
                    Text("Recipes & BOM").tag(2)
                    Text("Suppliers").tag(3)
                    Text("Stock Audit").tag(4)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, APSpacing.md)
                .padding(.vertical, APSpacing.sm)
                .background(Color.appSurface)
                
                Divider().background(Color.appDivider)
                
                switch selectedSection {
                case 0:
                    if filteredInventory.isEmpty {
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
                default:
                    EmptyView()
                }
            }
        }
        .navigationTitle("Stock & Inventory")
        .apNavBar(background: Color.appBackground)
        .toolbar {
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
                            Button("Manage Branches...") {
                                showingBranchManager = true
                            }
                        } label: {
                            Label(active.name, systemImage: "building.2")
                                .foregroundColor(.appTeal)
                        }
                    } else {
                        Button("Manage Branches...") {
                            showingBranchManager = true
                        }
                        .foregroundColor(.appTeal)
                    }
                    
                    // Stock Transfer Button (only if active branch is selected and there's another branch to transfer to)
                    if selectedSection == 0 && activeBranch != nil && branches.count > 1 {
                        Button(action: { showingTransferSheet = true }) {
                            Label("Transfer Stock", systemImage: "arrow.left.arrow.right")
                                .foregroundColor(.appTeal)
                        }
                    }
                    
                    // Add Material Button
                    if selectedSection == 0 && activeBranch != nil {
                        Button(action: { showingAddSheet = true }) {
                            Label("Add Raw Material", systemImage: "plus")
                                .foregroundColor(.appTeal)
                        }
                    }
                    
                    // PO Manager Button
                    if selectedSection == 0 && activeBranch != nil {
                        Button(action: { showingPOManager = true }) {
                            Label("Purchase Orders", systemImage: "doc.text")
                                .foregroundColor(.appTeal)
                        }
                    }
                }
            }
        }
        .sheet(item: $viewModel.selectedItem) { item in
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
        .onAppear {
            viewModel.modelContext = modelContext
            viewModel.seedDefaultBranchIfNeeded()
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
            Text("Inventory Empty")
                .font(.title2).fontWeight(.bold).foregroundColor(.textPrimary)
            Text("Seed menu items from the POS tab to auto-generate ingredients.")
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

            // Search bar with visual separation
            HStack(spacing: APSpacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.textSecondary)
                    .font(.subheadline)
                TextField("Search items...", text: $searchText)
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
            
            // High-Volume Filters Section
            VStack(spacing: APSpacing.sm) {
                // Status Filter Badges
                HStack(spacing: APSpacing.xs) {
                    statusFilterButton(title: "All", tag: "All", count: inventory.count)
                    statusFilterButton(
                        title: "Low Stock",
                        tag: "Low Stock",
                        count: inventory.filter { $0.currentQuantity <= $0.reorderLevel }.count,
                        color: .appRose
                    )
                    statusFilterButton(
                        title: "Out of Stock",
                        tag: "Out of Stock",
                        count: inventory.filter { $0.currentQuantity <= 0 }.count,
                        color: .textSecondary
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, APSpacing.md)
                
                // Category list dynamic scroll
                let categoriesList = ["All"] + Array(Set(inventory.compactMap { $0.category })).sorted()
                if categoriesList.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: APSpacing.xs) {
                            ForEach(categoriesList, id: \.self) { cat in
                                Button(action: { selectedCategory = cat }) {
                                    Text(cat)
                                        .font(.system(size: 11, weight: .medium))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(selectedCategory == cat ? APGradient.accent : nil)
                                        .backgroundColor(selectedCategory == cat ? .clear : Color.appSurfaceHigh)
                                        .foregroundColor(selectedCategory == cat ? .white : .textSecondary)
                                        .clipShape(Capsule())
                                        .overlay(
                                            Capsule()
                                                .stroke(selectedCategory == cat ? Color.clear : Color.appBorderSubtle, lineWidth: 1)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, APSpacing.md)
                    }
                }
            }
            .padding(.vertical, 6)
            .background(Color.appBackground)
            .overlay(Rectangle().fill(Color.appDivider).frame(height: 1), alignment: .bottom)

            // Item list
            ScrollView {
                LazyVStack(spacing: APSpacing.sm) {
                    ForEach(filteredInventory) { item in
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
                .padding(APSpacing.md)
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color.appBackground)
    }

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

    private var inventoryStatsHeader: some View {
        let activeItems = filteredInventory
        let lowStockCount = activeItems.filter { $0.currentQuantity <= $0.reorderLevel }.count
        return HStack(spacing: APSpacing.md) {
            statCard(title: "Total Items",   value: "\(activeItems.count)",  icon: "shippingbox.fill", color: Color(hex: "6C63FF"))
            statCard(title: "Low Stock",     value: "\(lowStockCount)",    icon: "exclamationmark.triangle.fill", color: .appRose)
            statCard(title: "Transactions",  value: "\(filteredTransactionsList.count)", icon: "arrow.left.and.right.circle.fill", color: .appTeal)
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

    // MARK: - Transaction Panel (Right)

    private var transactionPanel: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Transaction Log")
                        .font(.headline).fontWeight(.bold)
                        .foregroundColor(.textPrimary)
                    Text("Last \(min(filteredTransactionsList.count, 30)) entries")
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
                    Text("No transactions yet")
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
        .frame(width: 420)
        .overlay(Rectangle().fill(Color.appDivider).frame(width: 1), alignment: .leading)
    }
}

// MARK: - Inventory Item Card

private struct InventoryItemCard: View {
    let item:      InventoryItem
    let onReceive: () -> Void
    let onWaste:   () -> Void
    let onReturn:  () -> Void
    let onEdit:    () -> Void
    let onHistory: () -> Void

    private var isLow: Bool { item.currentQuantity <= item.reorderLevel }
    private var fillRatio: Double {
        guard item.reorderLevel > 0 else { return 1.0 }
        return min(item.currentQuantity / (item.reorderLevel * 3), 1.0)
    }

    var body: some View {
        VStack(spacing: APSpacing.sm) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(item.name)
                            .font(.subheadline).fontWeight(.semibold)
                            .foregroundColor(.textPrimary)
                        if isLow {
                            APBadge(text: "Low Stock", color: .appRose, icon: "exclamationmark.triangle.fill")
                        }
                    }
                    Text("SKU: \(item.sku ?? "N/A")  ·  ฿\(String(format: "%.2f", item.costPrice))/\(item.unit)")
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                }

                Spacer()

                Text(String(format: "%.1f %@", item.currentQuantity, item.unit))
                    .font(.headline).fontWeight(.bold)
                    .foregroundColor(isLow ? .appRose : .textPrimary)
            }

            // Stock level bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.appSurfaceHigh)
                        .frame(height: 5)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(isLow ? APGradient.destructive : APGradient.positive)
                        .frame(width: geo.size.width * fillRatio, height: 5)
                }
            }
            .frame(height: 5)

            HStack(spacing: APSpacing.sm) {
                Text("Reorder at \(String(format: "%.0f", item.reorderLevel)) \(item.unit)")
                    .font(.caption2)
                    .foregroundColor(.textSecondary)
                Spacer()

                Button(action: onReceive) {
                    Label("Receive", systemImage: "plus.circle.fill")
                        .font(.caption).fontWeight(.semibold)
                        .foregroundColor(.appTeal)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.appTeal.opacity(0.12))
                        .clipShape(Capsule())
                }

                Button(action: onWaste) {
                    Label("Waste", systemImage: "minus.circle.fill")
                        .font(.caption).fontWeight(.semibold)
                        .foregroundColor(.appRose)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.appRose.opacity(0.12))
                        .clipShape(Capsule())
                }
                
                Menu {
                    Button(action: onReturn) {
                        Label("Return to Supplier", systemImage: "arrow.uturn.left.circle")
                    }
                    Button(action: onEdit) {
                        Label("Edit Details", systemImage: "pencil")
                    }
                    Button(action: onHistory) {
                        Label("Movement History", systemImage: "clock.arrow.circlepath")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle.fill")
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
            return ("Receive", "plus.circle.fill", .appTeal, APGradient.positive)
        case "waste":
            return ("Waste", "trash.fill", .appRose, APGradient.destructive)
        case "sell":
            return ("Sell", "cart.fill", Color(hex: "6C63FF"), APGradient.accent)
        case "return_to_supplier":
            return ("Return", "arrow.uturn.left.circle.fill", .appAmber, APGradient.warning)
        case "transfer_out":
            return ("Xfer Out", "arrow.right.circle.fill", .appRose, APGradient.destructive)
        case "transfer_in":
            return ("Xfer In", "arrow.left.circle.fill", .appTeal, APGradient.positive)
        default:
            return ("Adjust", "arrow.left.and.right.circle.fill", .appAmber, APGradient.warning)
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
                    Text(txn.item?.name ?? "Unknown Item")
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
                    Text(txn.notes ?? "No details")
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
    let item:       InventoryItem
    let viewModel:  InventoryViewModel
    let onComplete: () -> Void

    @State private var amountString = ""
    @State private var costString   = ""
    @State private var noteText     = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: APSpacing.md) {
                        // Item info card
                        VStack(alignment: .leading, spacing: APSpacing.sm) {
                            sectionHeader("Item Information")
                            infoRow(label: "Name",     value: item.name)
                            infoRow(label: "SKU",      value: item.sku ?? "N/A")
                            infoRow(label: "On Hand",  value: String(format: "%.1f %@", item.currentQuantity, item.unit))
                        }
                        .apCard()

                        // Input card
                        VStack(alignment: .leading, spacing: APSpacing.sm) {
                            sectionHeader("Incoming Stock")
                            inputField("Quantity (\(item.unit))", text: $amountString)
                            inputField("Unit Cost (฿/\(item.unit))", text: $costString)
                            inputField("Invoice / Reference Note", text: $noteText)
                        }
                        .apCard()
                    }
                    .padding(APSpacing.md)
                }
            }
            .navigationTitle("Receive Stock")
            .apNavBar(background: Color.appSurface)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onComplete() }.foregroundColor(.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Process") {
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
    let item:       InventoryItem
    let viewModel:  InventoryViewModel
    let onComplete: () -> Void

    @State private var amountString      = ""
    @State private var reasonSelection   = "Spoilage"
    @State private var noteText          = ""

    let reasons = ["Spoilage", "Wastage", "Spillage/Accident", "Audit Correction"]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: APSpacing.md) {
                        VStack(alignment: .leading, spacing: APSpacing.sm) {
                            sectionHeader("Item Information")
                            infoRow(label: "Name",    value: item.name)
                            infoRow(label: "On Hand", value: String(format: "%.1f %@", item.currentQuantity, item.unit))
                        }
                        .apCard()

                        VStack(alignment: .leading, spacing: APSpacing.sm) {
                            sectionHeader("Adjustment")
                            inputField("Quantity to Deduct (\(item.unit))", text: $amountString)

                            Picker("Reason", selection: $reasonSelection) {
                                ForEach(reasons, id: \.self) { Text($0).tag($0) }
                            }
                            .pickerStyle(.segmented)

                            inputField("Additional Details", text: $noteText)
                        }
                        .apCard()
                    }
                    .padding(APSpacing.md)
                }
            }
            .navigationTitle("Record Waste / Adjust")
            .apNavBar(background: Color.appSurface)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onComplete() }.foregroundColor(.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Process") {
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

// MARK: - Sheet Helpers

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
    let item:       InventoryItem
    let viewModel:  InventoryViewModel
    let onComplete: () -> Void

    @Environment(\.modelContext) private var modelContext
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
                            sectionHeader("Item Details")
                            inputField("Item Name", text: $name)
                            inputField("SKU Code", text: $sku)
                            inputField("Barcode", text: $barcode)
                            inputField("Unit (e.g. kg, liter, piece)", text: $unit)
                        }
                        .apCard()

                        VStack(alignment: .leading, spacing: APSpacing.sm) {
                            sectionHeader("Classification & Location")
                            inputField("Ingredient Category (e.g. Meat, Dairy, Veg)", text: $category)
                            inputField("Storage Location (e.g. Freezer A, Shelf 3)", text: $storageLocation)
                        }
                        .apCard()

                        VStack(alignment: .leading, spacing: APSpacing.sm) {
                            sectionHeader("Reordering & Costs")
                            inputField("Reorder Trigger Level", text: $reorderString)
                            inputField("Unit Cost Price (฿)", text: $costString)
                        }
                        .apCard()
                        
                        VStack(alignment: .leading, spacing: APSpacing.sm) {
                            sectionHeader("Supplier Association")
                            Picker("Supplier", selection: $selectedSupplierId) {
                                Text("— No Supplier —").tag(nil as UUID?)
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
                            sectionHeader("Danger Zone")
                            Button(action: { showingDeleteAlert = true }) {
                                HStack {
                                    Image(systemName: "trash.fill")
                                    Text("Delete This Item")
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
            .navigationTitle("Edit Item Details")
            .apNavBar(background: Color.appSurface)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onComplete() }.foregroundColor(.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
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
            .alert("Delete Item", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
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
    
    private let typeOptions = ["All", "receive", "waste", "sell", "adjust"]
    
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
                        summaryCard(title: "On Hand", value: String(format: "%.1f %@", item.currentQuantity, item.unit), icon: "shippingbox.fill", color: .appAccent)
                        summaryCard(title: "Received", value: String(format: "%.1f", totalReceived), icon: "plus.circle.fill", color: .appTeal)
                        summaryCard(title: "Wasted", value: String(format: "%.1f", totalWasted), icon: "trash.fill", color: .appRose)
                        summaryCard(title: "Sold", value: String(format: "%.1f", totalSold), icon: "cart.fill", color: Color(hex: "6C63FF"))
                    }
                    .padding(APSpacing.md)
                    .background(Color.appSurface)
                    
                    Divider().background(Color.appDivider)
                    
                    // Type filter capsules
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: APSpacing.xs) {
                            ForEach(typeOptions, id: \.self) { opt in
                                let display = opt == "All" ? "All" : opt.capitalized
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
                            Text("No transactions found")
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
            .navigationTitle("\(item.name) — History")
            .navigationBarTitleDisplayMode(.inline)
            .apNavBar(background: Color.appSurface)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { onDismiss() }
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
            case "sell": return ("Sell", "cart.fill", Color(hex: "6C63FF"))
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
                    Text(txn.notes ?? "No details")
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
    let viewModel:    InventoryViewModel
    let activeBranch: Branch?
    let onComplete:   () -> Void

    @Environment(\.modelContext) private var modelContext
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
                            sectionHeader("Item Details")
                            inputField("Item Name (e.g. Sugar)", text: $name)
                            inputField("SKU Code (e.g. RAW-SUG)", text: $sku)
                            inputField("Barcode", text: $barcode)
                            inputField("Unit (e.g. kg, liter, piece)", text: $unit)
                        }
                        .apCard()

                        VStack(alignment: .leading, spacing: APSpacing.sm) {
                            sectionHeader("Classification & Location")
                            inputField("Ingredient Category (e.g. Condiments)", text: $category)
                            inputField("Storage Location (e.g. Pantry A)", text: $storageLocation)
                        }
                        .apCard()

                        VStack(alignment: .leading, spacing: APSpacing.sm) {
                            sectionHeader("Reordering & Costs")
                            inputField("Reorder Trigger Level", text: $reorderString)
                            inputField("Unit Cost Price (฿)", text: $costString)
                        }
                        .apCard()
                        
                        VStack(alignment: .leading, spacing: APSpacing.sm) {
                            sectionHeader("Supplier Association")
                            Picker("Supplier", selection: $selectedSupplierId) {
                                Text("— No Supplier —").tag(nil as UUID?)
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
            .navigationTitle("Add Raw Material")
            .apNavBar(background: Color.appSurface)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onComplete() }.foregroundColor(.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
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
    let item:       InventoryItem
    let viewModel:  InventoryViewModel
    let onComplete: () -> Void

    @State private var amountString = ""
    @State private var noteText     = ""
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
                            sectionHeader("Item Information")
                            infoRow(label: "Name",    value: item.name)
                            infoRow(label: "On Hand", value: String(format: "%.1f %@", item.currentQuantity, item.unit))
                        }
                        .apCard()

                        VStack(alignment: .leading, spacing: APSpacing.sm) {
                            sectionHeader("Return to Supplier")
                            inputField("Quantity to Return (\(item.unit))", text: $amountString)
                            inputField("Return details (discrepancies, invoice number)", text: $noteText)
                        }
                        .apCard()
                    }
                    .padding(APSpacing.md)
                }
            }
            .navigationTitle("Return to Supplier")
            .apNavBar(background: Color.appSurface)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onComplete() }.foregroundColor(.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Process") {
                        if let qty = Double(amountString), qty > item.currentQuantity {
                            errorMessage = "Quantity exceeds current stock level."
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
