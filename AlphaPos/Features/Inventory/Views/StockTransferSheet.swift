import SwiftUI
import SwiftData

struct StockTransferSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let sourceBranch: Branch
    @Query(sort: \Branch.name) private var branches: [Branch]
    @Query(sort: \InventoryItem.name) private var allItems: [InventoryItem]
    
    @State private var selectedItem: InventoryItem?
    @State private var destinationBranch: Branch?
    @State private var quantityString = ""
    @State private var notes = ""
    
    @State private var errorMessage = ""
    
    private var sourceItems: [InventoryItem] {
        allItems.filter { $0.branch?.id == sourceBranch.id }
    }
    
    private var filteredDestinations: [Branch] {
        branches.filter { $0.id != sourceBranch.id }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: APSpacing.lg) {
                        
                        // Error message
                        if !errorMessage.isEmpty {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(.appRose)
                                .padding(APSpacing.sm)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.appRose.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: APRadius.sm))
                        }
                        
                        // Source Branch Info
                        VStack(alignment: .leading, spacing: APSpacing.xs) {
                            Text("FROM BRANCH (SOURCE)")
                                .font(.caption2).fontWeight(.bold).foregroundColor(.textSecondary).tracking(0.5)
                            Text(sourceBranch.name)
                                .font(.headline)
                                .foregroundColor(.textPrimary)
                                .padding(APSpacing.md)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.appSurface.opacity(0.4))
                                .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
                        }
                        
                        // Destination Branch Selector
                        VStack(alignment: .leading, spacing: APSpacing.xs) {
                            Text("TO BRANCH (DESTINATION)")
                                .font(.caption2).fontWeight(.bold).foregroundColor(.appTeal).tracking(0.5)
                            Picker("Select Store", selection: $destinationBranch) {
                                Text("Choose Destination Branch...").tag(nil as Branch?)
                                ForEach(filteredDestinations) { b in
                                    Text(b.name).tag(b as Branch?)
                                }
                            }
                            .tint(.appTeal)
                            .padding(APSpacing.xs)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.appSurface)
                            .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
                        }
                        
                        // Item Selector
                        VStack(alignment: .leading, spacing: APSpacing.xs) {
                            Text("SELECT STOCK ITEM TO TRANSFER")
                                .font(.caption2).fontWeight(.bold).foregroundColor(.appTeal).tracking(0.5)
                            Picker("Select Item", selection: $selectedItem) {
                                Text("Choose Stock Item...").tag(nil as InventoryItem?)
                                ForEach(sourceItems) { item in
                                    Text("\(item.name) (Stock: \(String(format: "%.2f", item.currentQuantity)) \(item.unit))")
                                        .tag(item as InventoryItem?)
                                }
                            }
                            .tint(.appTeal)
                            .padding(APSpacing.xs)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.appSurface)
                            .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
                        }
                        
                        // Quantity
                        if let item = selectedItem {
                            VStack(alignment: .leading, spacing: APSpacing.xs) {
                                Text("TRANSFER QUANTITY (MAX: \(String(format: "%.2f", item.currentQuantity)) \(item.unit))")
                                    .font(.caption2).fontWeight(.bold).foregroundColor(.appTeal).tracking(0.5)
                                TextField("0.0", text: $quantityString)
                                    .padding(APSpacing.md)
                                    .background(Color.appSurface)
                                    .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
                                    .keyboardType(.decimalPad)
                                    .foregroundColor(.textPrimary)
                                
                                if let qty = Double(quantityString), qty > item.currentQuantity {
                                    Text("Warning: Quantity exceeds available stock (\(String(format: "%.2f", item.currentQuantity)) \(item.unit))")
                                        .font(.caption2)
                                        .foregroundColor(.appRose)
                                }
                            }
                        }
                        
                        // Notes
                        VStack(alignment: .leading, spacing: APSpacing.xs) {
                            Text("REASON / TRANSFER NOTES")
                                .font(.caption2).fontWeight(.bold).foregroundColor(.textSecondary).tracking(0.5)
                            TextField("Optional audit note...", text: $notes)
                                .padding(APSpacing.md)
                                .background(Color.appSurface)
                                .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
                                .foregroundColor(.textPrimary)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Stock Transfer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.textPrimary)
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button("Commit") {
                        performTransfer()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(.appTeal)
                    .disabled(!canTransfer)
                }
            }
        }
    }
    
    private var canTransfer: Bool {
        guard let item = selectedItem,
              destinationBranch != nil,
              let qty = Double(quantityString),
              qty > 0,
              qty <= item.currentQuantity else {
            return false
        }
        return true
    }
    
    private func performTransfer() {
        guard let item = selectedItem,
              let dest = destinationBranch,
              let qty = Double(quantityString) else {
            errorMessage = "Invalid transfer configurations."
            return
        }
        
        errorMessage = ""
        let vm = InventoryViewModel(modelContext: modelContext)
        vm.transferStock(item: item, fromBranch: sourceBranch, toBranch: dest, quantity: qty, notes: notes)
        dismiss()
    }
}
