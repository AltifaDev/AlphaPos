// ModifierGroupEditSheet.swift
// AlphaPos — Modifier Group & Options Editor

import SwiftUI
import SwiftData

struct ModifierGroupEditSheet: View {
    let group: ModifierGroup? // Nil when creating new
    let onDismiss: () -> Void
    
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \InventoryItem.name) private var allIngredients: [InventoryItem]
    
    @State private var viewModel = InventoryViewModel()
    
    // Group fields
    @State private var name = ""
    @State private var minSelection = 0
    @State private var maxSelection = 1
    
    // Sub-editor state
    @State private var selectedModifier: Modifier? = nil
    @State private var showingModifierSheet = false
    @State private var showingDeleteAlert = false
    
    var isEditing: Bool { group != nil }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: APSpacing.md) {
                            // Section 1: Group properties
                            VStack(alignment: .leading, spacing: APSpacing.sm) {
                                Text("Group Setup")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.textSecondary)
                                    .textCase(.uppercase)
                                
                                inputFieldRow(label: "Group Name", placeholder: "e.g., Sweetness Level, Size, Toppings", text: $name)
                                
                                HStack(spacing: APSpacing.md) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Min Selection")
                                            .font(.caption2)
                                            .foregroundColor(.textSecondary)
                                        Stepper("\(minSelection)", value: $minSelection, in: 0...10)
                                            .padding(6)
                                            .background(Color.appSurfaceHigh)
                                            .cornerRadius(APRadius.sm)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Max Selection")
                                            .font(.caption2)
                                            .foregroundColor(.textSecondary)
                                        Stepper("\(maxSelection)", value: $maxSelection, in: 1...20)
                                            .padding(6)
                                            .background(Color.appSurfaceHigh)
                                            .cornerRadius(APRadius.sm)
                                    }
                                }
                            }
                            .apCard()
                            
                            // Section 2: Modifiers list (Only when editing)
                            if let group = group {
                                modifiersSection(group)
                            }
                            
                            // Section 3: Danger Zone
                            if isEditing {
                                deleteSectionCard
                            }
                        }
                        .padding(APSpacing.md)
                    }
                    
                    bottomActionPanel
                }
            }
            .navigationTitle(isEditing ? "Edit Extras Group" : "Add Extras Group")
            .navigationBarTitleDisplayMode(.inline)
            .apNavBar(background: Color.appSurface)
            .onAppear {
                viewModel.modelContext = modelContext
                if let grp = group {
                    name = grp.name
                    minSelection = grp.minSelection
                    maxSelection = grp.maxSelection
                }
            }
            .sheet(isPresented: $showingModifierSheet) {
                ModifierOptionEditSheet(
                    group: group!,
                    modifier: selectedModifier,
                    ingredients: allIngredients,
                    viewModel: viewModel
                ) {
                    showingModifierSheet = false
                    selectedModifier = nil
                }
            }
            .alert("Delete Group", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    if let grp = group {
                        viewModel.deleteModifierGroup(group: grp)
                    }
                    onDismiss()
                }
            } message: {
                Text("Are you sure you want to delete this group? All extra options under this group will be deleted too.")
            }
        }
    }
    
    // MARK: - Subviews
    
    private func modifiersSection(_ group: ModifierGroup) -> some View {
        VStack(alignment: .leading, spacing: APSpacing.md) {
            HStack {
                Text("Modifier Options")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.textSecondary)
                    .textCase(.uppercase)
                
                Spacer()
                
                Button(action: {
                    selectedModifier = nil
                    showingModifierSheet = true
                }) {
                    Label("Add Option", systemImage: "plus.circle.fill")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.appAccent)
                }
                .buttonStyle(.plain)
            }
            
            if group.modifiers.isEmpty {
                VStack(spacing: APSpacing.sm) {
                    Image(systemName: "plus.circle")
                        .font(.title2)
                        .foregroundColor(.textTertiary)
                    Text("No options added yet")
                        .font(.caption2)
                        .foregroundColor(.textTertiary)
                }
                .frame(maxWidth: .infinity, minHeight: 80)
                .background(Color.appSurfaceHigh.opacity(0.4))
                .cornerRadius(APRadius.md)
            } else {
                VStack(spacing: APSpacing.sm) {
                    ForEach(group.modifiers.sorted(by: { $0.name < $1.name })) { mod in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mod.name)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.textPrimary)
                                
                                if let link = mod.inventoryItemLink {
                                    Text("Linked to inventory: \(link.name) (Deducts \(String(format: "%.1f", mod.quantityRequired ?? 0.0)) \(link.unit))")
                                        .font(.system(size: 10))
                                        .foregroundColor(.appTeal)
                                }
                            }
                            Spacer()
                            Text("+฿\(String(format: "%.2f", mod.extraPrice))")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(mod.extraPrice > 0 ? .appAccent : .textSecondary)
                                .padding(.horizontal, 10)
                            
                            Button(action: {
                                selectedModifier = mod
                                showingModifierSheet = true
                            }) {
                                Image(systemName: "pencil")
                                    .foregroundColor(.textSecondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                        
                        Divider().background(Color.appDivider)
                    }
                }
            }
        }
        .padding(APSpacing.md)
        .apCard()
    }
    
    private var deleteSectionCard: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            Text("Danger Zone")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.appRose)
                .textCase(.uppercase)
            
            Text("Deleting this group will delete all options and unlink it from all associated products. This cannot be undone.")
                .font(.caption2)
                .foregroundColor(.textSecondary)
            
            Button(action: { showingDeleteAlert = true }) {
                Text("Delete Modifier Group")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(Color.appRose)
                    .cornerRadius(APRadius.md)
            }
            .buttonStyle(.plain)
        }
        .padding(APSpacing.md)
        .apCard()
    }
    
    private var bottomActionPanel: some View {
        HStack(spacing: APSpacing.md) {
            Button(action: onDismiss) {
                Text("Cancel")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.appSurfaceHigh)
                    .cornerRadius(APRadius.md)
            }
            .buttonStyle(.plain)
            
            Button(action: saveGroup) {
                Text(isEditing ? "Save Changes" : "Add Group & Continue")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(name.isEmpty ? .textTertiary : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(name.isEmpty ? nil : APGradient.accent)
                    .backgroundColor(name.isEmpty ? Color.appSurfaceHigh : .clear)
                    .cornerRadius(APRadius.md)
            }
            .disabled(name.isEmpty)
            .buttonStyle(.plain)
        }
        .padding(APSpacing.md)
        .background(Color.appSurface)
        .overlay(Rectangle().fill(Color.appDivider).frame(height: 1), alignment: .top)
    }
    
    private func inputFieldRow(label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.textSecondary)
            TextField(placeholder, text: text)
                .font(.subheadline)
                .foregroundColor(.textPrimary)
                .tint(.appAccent)
                .padding(8)
                .background(Color.appSurfaceHigh)
                .cornerRadius(APRadius.sm)
                .overlay(
                    RoundedRectangle(cornerRadius: APRadius.sm)
                        .stroke(Color.appBorderSubtle, lineWidth: 1)
                )
        }
    }
    
    // MARK: - Save
    
    private func saveGroup() {
        if let grp = group {
            viewModel.updateModifierGroup(
                group: grp,
                name: name,
                minSelection: minSelection,
                maxSelection: maxSelection
            )
            onDismiss()
        } else {
            viewModel.addModifierGroup(
                name: name,
                minSelection: minSelection,
                maxSelection: maxSelection
            )
            // Dismiss and let user edit/add modifiers by re-selecting
            onDismiss()
        }
    }
}

// MARK: - Sub-Sheet: Add/Edit Modifier Option

struct ModifierOptionEditSheet: View {
    let group: ModifierGroup
    let modifier: Modifier?
    let ingredients: [InventoryItem]
    let viewModel: InventoryViewModel
    let onDismiss: () -> Void
    
    @State private var name = ""
    @State private var extraPriceString = ""
    @State private var selectedIngredientId: UUID? = nil
    @State private var qtyRequiredString = ""
    @State private var showingDeleteAlert = false
    
    var isEditing: Bool { modifier != nil }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: APSpacing.md) {
                        // Details
                        VStack(alignment: .leading, spacing: APSpacing.sm) {
                            Text("Option Info")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.textSecondary)
                                .textCase(.uppercase)
                            
                            inputFieldRow(label: "Option Name", placeholder: "e.g., Brown Sugar Pearl, Extra Cheese, Hot", text: $name)
                            inputFieldRow(label: "Extra Price Added (฿)", placeholder: "0.00", text: $extraPriceString)
                                .keyboardType(.decimalPad)
                        }
                        .apCard()
                        
                        // Inventory Link
                        VStack(alignment: .leading, spacing: APSpacing.sm) {
                            Text("Inventory Stock Deduction Link")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.textSecondary)
                                .textCase(.uppercase)
                            
                            Text("If selecting this option consumes raw inventory, choose the item and quantity here.")
                                .font(.caption2)
                                .foregroundColor(.textTertiary)
                            
                            Picker("Linked Ingredient", selection: $selectedIngredientId) {
                                Text("— None —").tag(nil as UUID?)
                                ForEach(ingredients) { ing in
                                    Text("\(ing.name) (\(ing.unit))").tag(ing.id as UUID?)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(.appAccent)
                            
                            if selectedIngredientId != nil {
                                inputFieldRow(label: "Deduction Quantity", placeholder: "e.g. 1.0, 15.0", text: $qtyRequiredString)
                                    .keyboardType(.decimalPad)
                            }
                        }
                        .apCard()
                        
                        if isEditing {
                            VStack(alignment: .leading, spacing: APSpacing.sm) {
                                Text("Delete Option")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.appRose)
                                    .textCase(.uppercase)
                                
                                Button(action: { showingDeleteAlert = true }) {
                                    Text("Delete Option")
                                        .font(.subheadline)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                        .padding(.vertical, 8)
                                        .frame(maxWidth: .infinity)
                                        .background(Color.appRose)
                                        .cornerRadius(APRadius.md)
                                }
                                .buttonStyle(.plain)
                            }
                            .apCard()
                        }
                    }
                    .padding(APSpacing.md)
                }
                .navigationTitle(isEditing ? "Edit Option" : "Add Option")
                .navigationBarTitleDisplayMode(.inline)
                .apNavBar(background: Color.appSurface)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { onDismiss() }.foregroundColor(.textSecondary)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            saveModifier()
                        }
                        .disabled(name.isEmpty)
                        .foregroundStyle(APGradient.accent)
                    }
                }
                .alert("Delete Option", isPresented: $showingDeleteAlert) {
                    Button("Cancel", role: .cancel) {}
                    Button("Delete", role: .destructive) {
                        if let mod = modifier {
                            viewModel.deleteModifier(modifier: mod)
                        }
                        onDismiss()
                    }
                } message: {
                    Text("Are you sure you want to delete this option?")
                }
                .onAppear {
                    if let mod = modifier {
                        name = mod.name
                        extraPriceString = String(format: "%.2f", mod.extraPrice)
                        selectedIngredientId = mod.inventoryItemLink?.id
                        if let qty = mod.quantityRequired {
                            qtyRequiredString = String(format: "%.1f", qty)
                        }
                    }
                }
            }
        }
        .apColorScheme()
    }
    
    private func inputFieldRow(label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.textSecondary)
            TextField(placeholder, text: text)
                .font(.subheadline)
                .foregroundColor(.textPrimary)
                .tint(.appAccent)
                .padding(8)
                .background(Color.appSurfaceHigh)
                .cornerRadius(APRadius.sm)
                .overlay(
                    RoundedRectangle(cornerRadius: APRadius.sm)
                        .stroke(Color.appBorderSubtle, lineWidth: 1)
                )
        }
    }
    
    private func saveModifier() {
        let price = Double(extraPriceString) ?? 0.0
        let qty = Double(qtyRequiredString)
        
        if let mod = modifier {
            viewModel.updateModifier(
                modifier: mod,
                name: name,
                extraPrice: price,
                inventoryItemId: selectedIngredientId,
                qtyRequired: qty
            )
        } else {
            viewModel.addModifier(
                to: group,
                name: name,
                extraPrice: price,
                inventoryItemId: selectedIngredientId,
                qtyRequired: qty
            )
        }
        onDismiss()
    }
}
