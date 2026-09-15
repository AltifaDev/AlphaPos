// StockAvailability.swift
// AlphaPos — Shared stock evaluation for POS lock + inventory alerts

import Foundation
import SwiftData

enum StockAvailability {
    struct Requirement: Identifiable {
        let id: UUID
        let source: InventoryItem
        let local: InventoryItem?
        var required: Double
        var available: Double { local?.currentQuantity ?? 0 }
        var shortage: Double { max(0, required - available) }
        /// AlphaPos uses a backflush inventory model. Short stock is surfaced
        /// as a warning and the later sell movement may take the balance below
        /// zero; it never prevents a cashier from taking an order.
        var blocksSale: Bool { false }
    }

    /// Fetch recipe rows directly; imported offline stores may not hydrate inverse arrays.
    static func requirements(menuItem: MenuItem, activeBranch: Branch?, modelContext: ModelContext) -> [Requirement] {
        if menuItem.stockTrackingMode == StockTrackingMode.notTracked.rawValue { return [] }
        let menuID = menuItem.id
        let descriptor = FetchDescriptor<Recipe>(predicate: #Predicate { !$0.isDeleted && $0.menuItem?.id == menuID })
        let rows = (try? modelContext.fetch(descriptor)) ?? menuItem.recipes
        var result: [Requirement] = []
        for recipe in rows where !recipe.isDeleted && recipe.menuItem?.id == menuItem.id {
            guard let source = recipe.inventoryItem, !source.isDeleted else { continue }
            let amount = InventoryRequirementCalculator.required(for: recipe, saleQuantity: 1)
            appendBackflushLeaves(
                for: source, required: amount, activeBranch: activeBranch,
                modelContext: modelContext, visiting: [], into: &result
            )
        }
        return result.sorted { $0.blocksSale && !$1.blocksSale }
    }

    /// Expands a sale requirement through active prep recipes.  In the
    /// restaurant backflush model a prep output is virtual at sale time: the
    /// sell movement is recorded only against its raw leaves.  This prevents a
    /// sale from consuming both a prep output and its components.
    private static func appendBackflushLeaves(
        for source: InventoryItem,
        required: Double,
        activeBranch: Branch?,
        modelContext: ModelContext,
        visiting: Set<UUID>,
        into result: inout [Requirement]
    ) {
        guard required.isFinite, required > 0, !source.isDeleted else { return }
        // A malformed circular prep recipe must not cause unbounded recursion
        // or a duplicate deduction.  The editor/server migration rejects these
        // cycles; retaining the current item as a leaf is the safe fallback.
        guard !visiting.contains(source.id) else {
            appendLeaf(source, required: required, activeBranch: activeBranch,
                       modelContext: modelContext, into: &result)
            return
        }
        let sourceID = source.id
        let descriptor = FetchDescriptor<PrepRecipe>(predicate: #Predicate {
            !$0.isDeleted && $0.isActive && $0.outputItem?.id == sourceID
        })
        guard let prep = try? modelContext.fetch(descriptor).first,
              prep.expectedOutputQuantity.isFinite, prep.expectedOutputQuantity > 0,
              !prep.components.filter({ !$0.isDeleted && $0.ingredient != nil }).isEmpty
        else {
            appendLeaf(source, required: required, activeBranch: activeBranch,
                       modelContext: modelContext, into: &result)
            return
        }

        var outputPerBatch = prep.expectedOutputQuantity
        if let from = UnitOfMeasure.parse(prep.outputUnit), let to = UnitOfMeasure.parse(source.unit),
           let converted = UnitOfMeasure.convert(outputPerBatch, from: from, to: to) {
            outputPerBatch = converted
        }
        guard outputPerBatch > 0 else { return }
        let multiplier = required / outputPerBatch
        var nextVisiting = visiting
        nextVisiting.insert(source.id)
        for component in prep.components where !component.isDeleted {
            guard let ingredient = component.ingredient, !ingredient.isDeleted else { continue }
            var componentQuantity = max(component.quantity, 0) * multiplier
            if let from = UnitOfMeasure.parse(component.quantityUnit), let to = UnitOfMeasure.parse(ingredient.unit),
               let converted = UnitOfMeasure.convert(componentQuantity, from: from, to: to) {
                componentQuantity = converted
            }
            appendBackflushLeaves(for: ingredient, required: componentQuantity,
                                  activeBranch: activeBranch, modelContext: modelContext,
                                  visiting: nextVisiting, into: &result)
        }
    }

    private static func appendLeaf(
        _ source: InventoryItem, required: Double, activeBranch: Branch?,
        modelContext: ModelContext, into result: inout [Requirement]
    ) {
        let local = resolveBranchItem(source, branch: activeBranch, context: modelContext)
        var amount = required
        if let local, let from = UnitOfMeasure.parse(source.unit), let to = UnitOfMeasure.parse(local.unit),
           let converted = UnitOfMeasure.convert(amount, from: from, to: to) { amount = converted }
        guard amount > 0 else { return }
        let id = local?.id ?? source.id
        if let index = result.firstIndex(where: { $0.id == id }) {
            result[index].required += amount
        } else {
            result.append(Requirement(id: id, source: source, local: local, required: amount))
        }
    }
    /// How many full units of this menu item can be sold from current stock.
    /// Returns `nil` when the item does not track stock on sale or all items allow negative backflush.
    static func sellableUnits(
        menuItem: MenuItem,
        activeBranch: Branch?,
        modelContext: ModelContext,
        modifiers: [Modifier] = []
    ) -> Double? {
        // Kept for source compatibility with POS callers. The backflush model
        // deliberately has no sellable-quantity ceiling.
        return nil
    }

    /// True when tracked item cannot fulfill a single sale unit.
    static func isOutOfStockForSale(
        menuItem: MenuItem,
        activeBranch: Branch?,
        modelContext: ModelContext
    ) -> Bool {
        guard let units = sellableUnits(menuItem: menuItem, activeBranch: activeBranch, modelContext: modelContext) else {
            return false
        }
        return units < 1
    }

    /// True when any required ingredient currently has negative quantity (backflush sold).
    static func hasNegativeIngredients(
        menuItem: MenuItem,
        activeBranch: Branch?,
        modelContext: ModelContext
    ) -> Bool {
        if !menuItem.recipes.isEmpty {
            return menuItem.recipes.contains { recipe in
                guard !recipe.isDeleted, let inv = recipe.inventoryItem, !inv.isDeleted else { return false }
                return inv.currentQuantity < 0
            }
        }
        let reqs = requirements(menuItem: menuItem, activeBranch: activeBranch, modelContext: modelContext)
        return reqs.contains { ($0.local?.currentQuantity ?? $0.source.currentQuantity) < 0 }
    }

    /// Ingredients that are out or at/below reorder for a menu item (for alert copy).
    static func shortIngredients(
        menuItem: MenuItem,
        activeBranch: Branch?,
        modelContext: ModelContext
    ) -> [(name: String, qty: Double, reorder: Double, isOut: Bool)] {
        var result: [(String, Double, Double, Bool)] = []
        for recipe in menuItem.recipes where !recipe.isDeleted {
            guard let ingredient = recipe.inventoryItem else { continue }
            guard let local = resolveBranchItem(ingredient, branch: activeBranch, context: modelContext) else {
                result.append((ingredient.name, 0, ingredient.reorderLevel, true))
                continue
            }
            let isOut = local.currentQuantity <= 0
            let isLow = local.currentQuantity > 0 && local.currentQuantity <= local.reorderLevel
            if isOut || isLow {
                result.append((local.name, local.currentQuantity, local.reorderLevel, isOut))
            }
        }
        return result
    }

    static func resolveBranchItem(
        _ ingredient: InventoryItem,
        branch: Branch?,
        context: ModelContext
    ) -> InventoryItem? {
        guard let branch else { return ingredient }
        if ingredient.branch?.id == branch.id {
            return ingredient
        }
        let descriptor = FetchDescriptor<InventoryItem>(
            predicate: #Predicate<InventoryItem> { !$0.isDeleted }
        )
        guard let all = try? context.fetch(descriptor) else { return nil }
        if let match = all.first(where: {
            $0.branch?.id == branch.id && (
                (ingredient.sku != nil && $0.sku == ingredient.sku) || $0.name == ingredient.name
            )
        }) {
            return match
        }
        return nil
    }
}
