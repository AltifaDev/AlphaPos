import Foundation

extension NetworkManager {
    private func fetchPrepRows(_ endpoint: String) async throws -> [[String: Any]] {
        let data = try await sendSupabaseRequest(method: "GET", endpoint: endpoint,
            queryItems: [URLQueryItem(name: "is_deleted", value: "eq.false")])
        return (try JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
    }

    private func upsertPrepRow(_ endpoint: String, payload: [String: Any]) async throws -> Bool {
        _ = try await sendSupabaseRequest(method: "POST", endpoint: endpoint,
            queryItems: [URLQueryItem(name: "on_conflict", value: "id")], payload: payload)
        return true
    }

    func fetchPrepRecipes() async throws -> [[String: Any]] { try await fetchPrepRows("prep_recipes") }
    func fetchPrepRecipeComponents() async throws -> [[String: Any]] { try await fetchPrepRows("prep_recipe_components") }

    func uploadPrepRecipe(_ recipe: PrepRecipe) async throws -> Bool {
        guard let outputId=recipe.outputItem?.id else { return false }
        return try await upsertPrepRow("prep_recipes", payload: [
            "id":recipe.id.uuidString.lowercased(),
            "merchant_id":UserDefaults.standard.string(forKey:"active_merchant_id") ?? "",
            "name":recipe.name,"output_inventory_item_id":outputId.uuidString.lowercased(),
            "expected_output_quantity":recipe.expectedOutputQuantity,"output_unit":recipe.outputUnit,
            "instructions":recipe.instructions ?? NSNull(),"is_active":recipe.isActive,
            "is_deleted":recipe.isDeleted,"updated_at":NetworkManager.iso8601.string(from:recipe.updatedAt)
        ])
    }

    func uploadPrepRecipeComponent(_ component: PrepRecipeComponent) async throws -> Bool {
        guard let recipeId=component.prepRecipe?.id, let ingredientId=component.ingredient?.id else { return false }
        return try await upsertPrepRow("prep_recipe_components", payload: [
            "id":component.id.uuidString.lowercased(),
            "merchant_id":UserDefaults.standard.string(forKey:"active_merchant_id") ?? "",
            "prep_recipe_id":recipeId.uuidString.lowercased(),
            "ingredient_inventory_item_id":ingredientId.uuidString.lowercased(),
            "quantity":component.quantity,"quantity_unit":component.quantityUnit,
            "is_deleted":component.isDeleted,"updated_at":NetworkManager.iso8601.string(from:component.updatedAt)
        ])
    }

    func producePrepBatch(_ batch: PrepProductionBatch) async throws -> [String: Any] {
        guard let recipeId=batch.prepRecipe?.id, let branchId=batch.branch?.id else { return [:] }
        let data=try await sendSupabaseRequest(method:"POST",endpoint:"rpc/produce_prep_recipe_batch",payload:[
            "p_batch_id":batch.id.uuidString.lowercased(),
            "p_merchant_id":UserDefaults.standard.string(forKey:"active_merchant_id") ?? "",
            "p_branch_id":branchId.uuidString.lowercased(),"p_prep_recipe_id":recipeId.uuidString.lowercased(),
            "p_batch_count":batch.batchCount,"p_actual_output_quantity":batch.actualOutputQuantity,
            "p_lot_number":batch.lotNumber ?? NSNull(),"p_produced_by":batch.producedByEmployeeId?.uuidString.lowercased() ?? NSNull(),
            "p_notes":batch.notes ?? NSNull()
        ])
        return (try JSONSerialization.jsonObject(with:data) as? [String:Any]) ?? [:]
    }
}
