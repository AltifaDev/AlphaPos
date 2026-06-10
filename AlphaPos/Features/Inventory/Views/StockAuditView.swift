// StockAuditView.swift
// AlphaPos — Premium Physical Stock Take & Variance Reporting

import SwiftUI
import SwiftData

struct StockAuditView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \InventoryItem.name) private var ingredients: [InventoryItem]
    
    @State private var viewModel = InventoryViewModel()
    
    struct AuditLineItem: Identifiable {
        let id = UUID()
        let item: InventoryItem
        var physicalCount: Double
        var physicalString: String
        var notes: String
    }
    
    @State private var auditLines: [AuditLineItem] = []
    @State private var showingSuccessAlert = false
    @State private var searchPattern = ""
    @State private var selectedLocation = "All"
    @State private var showingScanner = false
    
    private var activeBranch: Branch? {
        if let activeIdString = UserDefaults.standard.string(forKey: "active_branch_id"),
           let activeUUID = UUID(uuidString: activeIdString) {
            let branchDesc = FetchDescriptor<Branch>()
            if let branches = try? modelContext.fetch(branchDesc) {
                return branches.first(where: { $0.id == activeUUID })
            }
        }
        return nil
    }
    
    private var filteredAuditLines: [Binding<AuditLineItem>] {
        var lines: [Binding<AuditLineItem>] = []
        for index in $auditLines.indices {
            let item = auditLines[index].item
            let matchesSearch = searchPattern.isEmpty || 
                item.name.localizedCaseInsensitiveContains(searchPattern) ||
                (item.sku ?? "").localizedCaseInsensitiveContains(searchPattern) ||
                (item.barcode ?? "").localizedCaseInsensitiveContains(searchPattern)
            
            let matchesLocation = selectedLocation == "All" || item.storageLocation == selectedLocation
            
            if matchesSearch && matchesLocation {
                lines.append($auditLines[index])
            }
        }
        return lines
    }
    
    // Summary Calculations
    private var totalVarianceCost: Double {
        auditLines.reduce(0.0) { sum, line in
            let diff = line.physicalCount - line.item.currentQuantity
            return sum + (diff * line.item.costPrice)
        }
    }
    
    private var adjustedItemsCount: Int {
        auditLines.filter { $0.physicalCount != $0.item.currentQuantity }.count
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header Search & Statistics
            VStack(spacing: APSpacing.md) {
                HStack(spacing: APSpacing.md) {
                    statRow(title: "Items to Audit", value: "\(auditLines.count)", icon: "shippingbox.fill", color: .appAccent)
                    statRow(title: "Adjusted Items", value: "\(adjustedItemsCount)", icon: "pencil.circle.fill", color: .appAmber)
                    statRow(
                        title: "Net Variance Cost",
                        value: "฿\(String(format: "%.2f", totalVarianceCost))",
                        icon: totalVarianceCost < 0 ? "arrow.down.forward.and.arrow.up.backward" : "arrow.up.right.circle.fill",
                        color: totalVarianceCost < 0 ? .appRose : (totalVarianceCost > 0 ? .appTeal : .textSecondary)
                    )
                }
                
                HStack(spacing: APSpacing.md) {
                    // Search bar
                    HStack(spacing: APSpacing.sm) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.textSecondary)
                        TextField("Filter ingredients for audit...", text: $searchPattern)
                            .font(.subheadline)
                            .foregroundColor(.textPrimary)
                        
                        Button(action: { showingScanner = true }) {
                            Image(systemName: "barcode.viewfinder")
                                .foregroundColor(.appTeal)
                        }
                        .padding(.horizontal, 4)
                        
                        if !searchPattern.isEmpty {
                            Button(action: { searchPattern = "" }) {
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
                    
                    // Location filter picker
                    let locations = ["All"] + Array(Set(ingredients.compactMap { $0.storageLocation })).sorted()
                    if locations.count > 1 {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.footnote)
                                .foregroundColor(.textSecondary)
                            Picker("Location", selection: $selectedLocation) {
                                ForEach(locations, id: \.self) { loc in
                                    Text(loc).tag(loc)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(.appAccent)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.appSurfaceHigh)
                        .cornerRadius(APRadius.md)
                        .overlay(
                            RoundedRectangle(cornerRadius: APRadius.md)
                                .stroke(Color.appBorderSubtle, lineWidth: 1)
                        )
                    }
                }
            }
            .padding(APSpacing.md)
            .background(Color.appSurface)
            
            Divider().background(Color.appDivider)
            
            if auditLines.isEmpty {
                VStack(spacing: APSpacing.md) {
                    Image(systemName: "tray.circle")
                        .font(.system(size: 48))
                        .foregroundColor(.textTertiary)
                    Text("No Inventory items to audit")
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.appBackground)
            } else {
                // List of Audit Lines
                ScrollView {
                    LazyVStack(spacing: APSpacing.sm) {
                        ForEach(filteredAuditLines) { $line in
                            auditItemCard(line: $line)
                        }
                    }
                    .padding(APSpacing.md)
                }
                .background(Color.appBackground)
                
                // Bottom Action Panel
                bottomActionPanel
            }
        }
        .onAppear {
            viewModel.modelContext = modelContext
            initializeAudit()
        }
        .alert("Audit Committed", isPresented: $showingSuccessAlert) {
            Button("OK") { initializeAudit() }
        } message: {
            Text("Stock levels have been adjusted, and transactions have been created for all differences.")
        }
        .sheet(isPresented: $showingScanner) {
            BarcodeScannerView(onScan: handleBarcodeScan)
        }
    }
    
    // MARK: - Subviews
    
    private func statRow(title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: APSpacing.sm) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.textPrimary)
                Text(title)
                    .font(.system(size: 9))
                    .foregroundColor(.textSecondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appSurfaceHigh)
        .cornerRadius(APRadius.sm)
        .overlay(
            RoundedRectangle(cornerRadius: APRadius.sm)
                .stroke(Color.appBorderSubtle, lineWidth: 1)
        )
    }
    
    private func auditItemCard(line: Binding<AuditLineItem>) -> some View {
        let diff = line.wrappedValue.physicalCount - line.wrappedValue.item.currentQuantity
        let diffCost = diff * line.wrappedValue.item.costPrice
        
        return VStack(spacing: APSpacing.sm) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(line.wrappedValue.item.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.textPrimary)
                    Text("System: \(String(format: "%.1f", line.wrappedValue.item.currentQuantity)) \(line.wrappedValue.item.unit)  ·  Cost: ฿\(String(format: "%.2f", line.wrappedValue.item.costPrice))/\(line.wrappedValue.item.unit)")
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                }
                
                Spacer()
                
                // Quantity edit field
                HStack(spacing: 4) {
                    TextField("0.0", text: line.physicalString)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .padding(6)
                        .background(Color.appSurfaceHigh)
                        .cornerRadius(APRadius.sm)
                        .foregroundColor(.textPrimary)
                        .onChange(of: line.wrappedValue.physicalString) { _, newVal in
                            if let parsed = Double(newVal) {
                                line.wrappedValue.physicalCount = parsed
                            } else if newVal.isEmpty {
                                line.wrappedValue.physicalCount = 0.0
                            }
                        }
                    
                    Text(line.wrappedValue.item.unit)
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                        .frame(width: 40, alignment: .leading)
                }
            }
            
            // Variance indicator and notes
            HStack(spacing: APSpacing.md) {
                // Variance Info
                HStack(spacing: 4) {
                    Text("Variance:")
                        .font(.caption2)
                        .foregroundColor(.textSecondary)
                    
                    if diff == 0 {
                        Text("No Discrepancy")
                            .font(.caption2)
                            .foregroundColor(.textTertiary)
                    } else {
                        let prefix = diff > 0 ? "+" : ""
                        Text(String(format: "%@%.1f %@ (%@฿%.2f)", prefix, diff, line.wrappedValue.item.unit, prefix, diffCost))
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(diff < 0 ? .appRose : .appTeal)
                    }
                }
                
                Spacer()
                
                // Quick notes input
                if diff != 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "pencil")
                            .font(.system(size: 10))
                            .foregroundColor(.textTertiary)
                        TextField("Discrepancy reason...", text: line.notes)
                            .font(.system(size: 11))
                            .foregroundColor(.textPrimary)
                            .frame(width: 180)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.appSurfaceHigh)
                            .cornerRadius(APRadius.sm)
                    }
                }
            }
        }
        .padding(APSpacing.md)
        .apCard()
    }
    
    private var bottomActionPanel: some View {
        HStack {
            Spacer()
            
            Button(action: {
                initializeAudit()
            }) {
                Text("Reset Fields")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.textSecondary)
                    .padding(.horizontal, APSpacing.lg)
                    .padding(.vertical, 12)
                    .background(Color.appSurfaceHigh)
                    .cornerRadius(APRadius.md)
            }
            .buttonStyle(.plain)
            
            Button(action: commitAudit) {
                Text("Commit Audit Adjustments")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(adjustedItemsCount > 0 ? .white : .textTertiary)
                    .padding(.horizontal, APSpacing.lg)
                    .padding(.vertical, 12)
                    .background(adjustedItemsCount > 0 ? APGradient.accent : nil)
                    .backgroundColor(adjustedItemsCount > 0 ? .clear : Color.appSurfaceHigh)
                    .cornerRadius(APRadius.md)
            }
            .disabled(adjustedItemsCount == 0)
            .buttonStyle(.plain)
        }
        .padding(APSpacing.md)
        .background(Color.appSurface)
        .overlay(Rectangle().fill(Color.appDivider).frame(height: 1), alignment: .top)
    }
    
    // MARK: - Logic
    
    private func initializeAudit() {
        let active = activeBranch
        let branchIngredients = ingredients.filter { $0.branch?.id == active?.id }
        auditLines = branchIngredients.map { item in
            AuditLineItem(
                item: item,
                physicalCount: item.currentQuantity,
                physicalString: String(format: "%.1f", item.currentQuantity),
                notes: ""
            )
        }
    }
    
    private func handleBarcodeScan(code: String) {
        if let idx = auditLines.firstIndex(where: { $0.item.barcode == code || $0.item.sku == code }) {
            auditLines[idx].physicalCount += 1.0
            auditLines[idx].physicalString = String(format: "%.1f", auditLines[idx].physicalCount)
            APHaptic.trigger()
            searchPattern = auditLines[idx].item.name
        }
    }
    
    private func commitAudit() {
        let itemsToCommit = auditLines.filter { $0.physicalCount != $0.item.currentQuantity }
        let linesData = itemsToCommit.map { (item: $0.item, physicalCount: $0.physicalCount, notes: $0.notes) }
        
        viewModel.commitAudit(auditLines: linesData)
        showingSuccessAlert = true
    }
}
