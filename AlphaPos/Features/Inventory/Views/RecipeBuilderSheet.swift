// RecipeBuilderSheet.swift
// AlphaPos — Premium Recipe Editor & Costing Engine

import SwiftUI
import SwiftData

struct RecipeBuilderSheet: View {
    let menuItem: MenuItem
    let onDismiss: () -> Void
    
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \InventoryItem.name) private var allIngredients: [InventoryItem]
    
    @State private var viewModel = InventoryViewModel()
    @State private var trackingMode = "not_tracked" // "not_tracked", "finished_good", "recipe_based"
    
    // Finished Good mode fields
    @State private var selectedIngredientId: UUID? = nil
    
    // Recipe based mode fields
    struct RecipeLineInput: Identifiable {
        let id = UUID()
        let ingredient: InventoryItem
        var qty: Double
        var qtyString: String
    }
    
    @State private var recipeLines: [RecipeLineInput] = []
    @State private var showingAddIngredient = false
    
    // Costing calculations
    private var totalCost: Double {
        switch trackingMode {
        case "not_tracked":
            return 0.0
        case "finished_good":
            if let ingredientId = selectedIngredientId,
               let matched = allIngredients.first(where: { $0.id == ingredientId }) {
                return matched.costPrice
            }
            return 0.0
        case "recipe_based":
            return recipeLines.reduce(0.0) { sum, line in
                sum + (line.ingredient.costPrice * line.qty)
            }
        default:
            return 0.0
        }
    }
    
    private var foodCostPercent: Double {
        guard menuItem.price > 0 else { return 0.0 }
        return (totalCost / menuItem.price) * 100.0
    }
    
    private var grossMarginPercent: Double {
        return max(0.0, 100.0 - foodCostPercent)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: APSpacing.md) {
                            // Header Info Card
                            itemOverviewCard
                            
                            // Tracking Mode Selection
                            trackingModeSelectorCard
                            
                            // Specific Configuration depending on mode
                            if trackingMode == "finished_good" {
                                finishedGoodConfigCard
                            } else if trackingMode == "recipe_based" {
                                recipeConfigCard
                            }
                            
                            // Costing Analysis Panel (if tracked)
                            if trackingMode != "not_tracked" {
                                costingAnalysisCard
                            }
                        }
                        .padding(APSpacing.md)
                    }
                    
                    // Bottom Save Panel
                    bottomActionPanel
                }
            }
            .navigationTitle("Recipe Settings")
            .navigationBarTitleDisplayMode(.inline)
            .apNavBar(background: Color.appSurface)
            .onAppear {
                viewModel.modelContext = modelContext
                loadCurrentRecipe()
            }
            .sheet(isPresented: $showingAddIngredient) {
                ingredientSelectionSheet
            }
        }
    }
    
    // MARK: - Subviews
    
    private var itemOverviewCard: some View {
        HStack(spacing: APSpacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: APRadius.sm)
                    .fill(Color.appSurfaceHigh)
                    .frame(width: 50, height: 50)
                Image(systemName: "tag.fill")
                    .foregroundColor(.appAccent)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(menuItem.name)
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                Text(menuItem.category?.name ?? "No Category")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            }
            
            Spacer()
            
            Text("฿\(String(format: "%.2f", menuItem.price))")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.textPrimary)
        }
        .padding(APSpacing.md)
        .apCard()
    }
    
    private var trackingModeSelectorCard: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            Text("Stock Tracking Mode")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.textSecondary)
                .textCase(.uppercase)
            
            Picker("Tracking Mode", selection: $trackingMode) {
                Text("Not Tracked").tag("not_tracked")
                Text("Direct (Finished Good)").tag("finished_good")
                Text("Recipe-Based").tag("recipe_based")
            }
            .pickerStyle(.segmented)
        }
        .padding(APSpacing.md)
        .apCard()
    }
    
    private var finishedGoodConfigCard: some View {
        VStack(alignment: .leading, spacing: APSpacing.md) {
            Text("Finished Good Configuration")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.textSecondary)
                .textCase(.uppercase)
            
            Text("Finished Goods map 1:1 with an inventory item. E.g., canned drinks, beer bottles, pre-packaged items.")
                .font(.caption2)
                .foregroundColor(.textTertiary)
            
            Picker("Linked Inventory Item", selection: $selectedIngredientId) {
                Text("— Auto-create matching item —").tag(nil as UUID?)
                ForEach(allIngredients) { ingredient in
                    Text("\(ingredient.name) (SKU: \(ingredient.sku ?? "N/A"))").tag(ingredient.id as UUID?)
                }
            }
            .pickerStyle(.menu)
            .padding(.vertical, 4)
            .tint(.appAccent)
        }
        .padding(APSpacing.md)
        .apCard()
    }
    
    private var recipeConfigCard: some View {
        VStack(alignment: .leading, spacing: APSpacing.md) {
            HStack {
                Text("Recipe Components")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.textSecondary)
                    .textCase(.uppercase)
                
                Spacer()
                
                Button(action: { showingAddIngredient = true }) {
                    Label("Add Raw Ingredient", systemImage: "plus.circle.fill")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.appAccent)
                }
                .buttonStyle(.plain)
            }
            
            if recipeLines.isEmpty {
                VStack(spacing: APSpacing.sm) {
                    Image(systemName: "plus.circle")
                        .font(.title2)
                        .foregroundColor(.textTertiary)
                    Text("No ingredients added yet")
                        .font(.caption)
                        .foregroundColor(.textTertiary)
                }
                .frame(maxWidth: .infinity, minHeight: 100)
                .background(Color.appSurfaceHigh.opacity(0.4))
                .cornerRadius(APRadius.md)
            } else {
                VStack(spacing: APSpacing.sm) {
                    ForEach($recipeLines) { $line in
                        HStack(spacing: APSpacing.sm) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(line.ingredient.name)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.textPrimary)
                                Text("Cost: ฿\(String(format: "%.2f", line.ingredient.costPrice))/\(line.ingredient.unit)")
                                    .font(.caption2)
                                    .foregroundColor(.textSecondary)
                            }
                            
                            Spacer()
                            
                            HStack(spacing: 4) {
                                TextField("0.0", text: $line.qtyString)
                                    .keyboardType(.decimalPad)
                                    .font(.subheadline)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 70)
                                    .padding(6)
                                    .background(Color.appSurfaceHigh)
                                    .cornerRadius(APRadius.sm)
                                    .foregroundColor(.textPrimary)
                                    .onChange(of: line.qtyString) { _, newVal in
                                        if let parsed = Double(newVal) {
                                            line.qty = parsed
                                        } else if newVal.isEmpty {
                                            line.qty = 0.0
                                        }
                                    }
                                
                                Text(line.ingredient.unit)
                                    .font(.caption)
                                    .foregroundColor(.textSecondary)
                                    .frame(width: 40, alignment: .leading)
                            }
                            
                            Button(action: { removeLine(lineId: line.id) }) {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.appRose)
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
    
    private var costingAnalysisCard: some View {
        VStack(alignment: .leading, spacing: APSpacing.md) {
            Text("Food Cost & Margin Analysis")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.textSecondary)
                .textCase(.uppercase)
            
            HStack(spacing: APSpacing.lg) {
                // Costing circles
                VStack(spacing: 4) {
                    ZStack {
                        Circle()
                            .stroke(Color.appSurfaceHigh, lineWidth: 6)
                            .frame(width: 70, height: 70)
                        
                        Circle()
                            .trim(from: 0.0, to: CGFloat(min(1.0, foodCostPercent / 100.0)))
                            .stroke(foodCostPercent > 40 ? Color.appRose : (foodCostPercent > 25 ? Color.appAmber : Color.appTeal), lineWidth: 6)
                            .frame(width: 70, height: 70)
                            .rotationEffect(Angle(degrees: -90))
                        
                        Text(String(format: "%.0f%%", foodCostPercent))
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.textPrimary)
                    }
                    Text("Food Cost %")
                        .font(.caption2)
                        .foregroundColor(.textSecondary)
                }
                
                VStack(spacing: 4) {
                    ZStack {
                        Circle()
                            .stroke(Color.appSurfaceHigh, lineWidth: 6)
                            .frame(width: 70, height: 70)
                        
                        Circle()
                            .trim(from: 0.0, to: CGFloat(min(1.0, grossMarginPercent / 100.0)))
                            .stroke(grossMarginPercent >= 60 ? Color.appTeal : (grossMarginPercent >= 30 ? Color.appAmber : Color.appRose), lineWidth: 6)
                            .frame(width: 70, height: 70)
                            .rotationEffect(Angle(degrees: -90))
                        
                        Text(String(format: "%.0f%%", grossMarginPercent))
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.textPrimary)
                    }
                    Text("Gross Margin %")
                        .font(.caption2)
                        .foregroundColor(.textSecondary)
                }
                
                // Numbers
                VStack(alignment: .leading, spacing: 6) {
                    costInfoRow(label: "Menu Price", value: "฿\(String(format: "%.2f", menuItem.price))", color: .textPrimary)
                    costInfoRow(label: "Total Unit Cost", value: "฿\(String(format: "%.2f", totalCost))", color: .textSecondary)
                    costInfoRow(
                        label: "Gross Profit",
                        value: "฿\(String(format: "%.2f", max(0.0, menuItem.price - totalCost)))",
                        color: grossMarginPercent >= 60 ? .appTeal : (grossMarginPercent >= 30 ? .appAmber : .appRose)
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(APSpacing.md)
        .apCard()
    }
    
    private func costInfoRow(label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label)
                .font(.caption2)
                .foregroundColor(.textSecondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(color)
        }
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
            
            Button(action: saveRecipe) {
                Text("Save Changes")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(APGradient.accent)
                    .cornerRadius(APRadius.md)
            }
            .buttonStyle(.plain)
        }
        .padding(APSpacing.md)
        .background(Color.appSurface)
        .overlay(Rectangle().fill(Color.appDivider).frame(height: 1), alignment: .top)
    }
    
    private var ingredientSelectionSheet: some View {
        NavigationStack {
            List(allIngredients) { ingredient in
                Button(action: { addIngredient(ingredient) }) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(ingredient.name)
                                .font(.subheadline)
                                .foregroundColor(.textPrimary)
                            Text("SKU: \(ingredient.sku ?? "N/A")  ·  Unit: \(ingredient.unit)")
                                .font(.caption2)
                                .foregroundColor(.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "plus.circle")
                            .foregroundColor(.appAccent)
                    }
                }
            }
            .navigationTitle("Select Raw Ingredient")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingAddIngredient = false }
                }
            }
        }
        .apColorScheme()
    }
    
    // MARK: - Logic Operations
    
    private func loadCurrentRecipe() {
        let recipes = menuItem.recipes
        if recipes.isEmpty {
            trackingMode = "not_tracked"
        } else if recipes.count == 1 && recipes.first?.quantityRequired == 1.0 {
            trackingMode = "finished_good"
            selectedIngredientId = recipes.first?.inventoryItem?.id
        } else {
            trackingMode = "recipe_based"
            recipeLines = recipes.map { recipe in
                let ingredient = recipe.inventoryItem!
                return RecipeLineInput(
                    ingredient: ingredient,
                    qty: recipe.quantityRequired,
                    qtyString: String(format: "%.2f", recipe.quantityRequired)
                )
            }
        }
    }
    
    private func addIngredient(_ ingredient: InventoryItem) {
        // Check if already in the recipe lines
        if !recipeLines.contains(where: { $0.ingredient.id == ingredient.id }) {
            recipeLines.append(RecipeLineInput(
                ingredient: ingredient,
                qty: 1.0,
                qtyString: "1.00"
            ))
        }
        showingAddIngredient = false
    }
    
    private func removeLine(lineId: UUID) {
        recipeLines.removeAll(where: { $0.id == lineId })
    }
    
    private func saveRecipe() {
        let linesData = recipeLines.map { (ingredientId: $0.ingredient.id, qty: $0.qty) }
        viewModel.saveRecipe(
            for: menuItem,
            trackingMode: trackingMode,
            selectedIngredientId: selectedIngredientId,
            recipeLines: linesData
        )
        onDismiss()
    }
}
