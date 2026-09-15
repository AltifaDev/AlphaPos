import Foundation
import SwiftData

extension SyncEngine {
    func syncPrepRecipes(_ context: ModelContext) async {
        let recipes=(try? context.fetch(FetchDescriptor<PrepRecipe>(predicate:#Predicate { !$0.isSynced }))) ?? []
        for value in recipes {
            do { if try await NetworkManager.shared.uploadPrepRecipe(value) { value.isSynced=true } }
            catch { reportSyncFailure("Prep recipe push: \(error.localizedDescription)",soft:false) }
        }
        let components=(try? context.fetch(FetchDescriptor<PrepRecipeComponent>(predicate:#Predicate { !$0.isSynced }))) ?? []
        for value in components {
            do { if try await NetworkManager.shared.uploadPrepRecipeComponent(value) { value.isSynced=true } }
            catch { reportSyncFailure("Prep component push: \(error.localizedDescription)",soft:false) }
        }
        let batches=(try? context.fetch(FetchDescriptor<PrepProductionBatch>(predicate:#Predicate { !$0.isSynced && !$0.isDeleted }))) ?? []
        for value in batches {
            do { _=try await NetworkManager.shared.producePrepBatch(value); value.isSynced=true }
            catch { reportSyncFailure("Prep batch production: \(error.localizedDescription)",soft:false) }
        }
        context.saveWithLogging(label:#function)
    }

    func pullPrepRecipes(_ context: ModelContext) async {
        do {
            let remoteRecipes=try await NetworkManager.shared.fetchPrepRecipes()
            let remoteComponents=try await NetworkManager.shared.fetchPrepRecipeComponents()
            let items=(try? context.fetch(FetchDescriptor<InventoryItem>())) ?? []
            let itemById=Dictionary(uniqueKeysWithValues:items.map{($0.id.uuidString.lowercased(),$0)})
            var recipes=(try? context.fetch(FetchDescriptor<PrepRecipe>())) ?? []
            var recipeById=Dictionary(uniqueKeysWithValues:recipes.map{($0.id.uuidString.lowercased(),$0)})
            for row in remoteRecipes {
                guard let idText=row["id"] as? String,let id=UUID(uuidString:idText),
                      let name=row["name"] as? String,let outputText=row["output_inventory_item_id"] as? String,
                      let output=itemById[outputText.lowercased()] else { continue }
                let target=recipeById[idText.lowercased()] ?? PrepRecipe(id:id,name:name,outputItem:output,
                    expectedOutputQuantity:remoteDouble(row["expected_output_quantity"],fallback:1),
                    outputUnit:row["output_unit"] as? String ?? output.unit,isSynced:true)
                if recipeById[idText.lowercased()] == nil { context.insert(target); recipes.append(target); recipeById[idText.lowercased()]=target }
                target.name=name;target.outputItem=output
                target.expectedOutputQuantity=remoteDouble(row["expected_output_quantity"],fallback:1)
                target.outputUnit=row["output_unit"] as? String ?? output.unit
                target.instructions=row["instructions"] as? String;target.isActive=row["is_active"] as? Bool ?? true
                target.isSynced=true
            }
            let existing=(try? context.fetch(FetchDescriptor<PrepRecipeComponent>())) ?? []
            let byId=Dictionary(uniqueKeysWithValues:existing.map{($0.id.uuidString.lowercased(),$0)})
            for row in remoteComponents {
                guard let idText=row["id"] as? String,let id=UUID(uuidString:idText),
                      let recipeText=row["prep_recipe_id"] as? String,let recipe=recipeById[recipeText.lowercased()],
                      let ingredientText=row["ingredient_inventory_item_id"] as? String,
                      let ingredient=itemById[ingredientText.lowercased()] else { continue }
                let target=byId[idText.lowercased()] ?? PrepRecipeComponent(id:id,prepRecipe:recipe,ingredient:ingredient,
                    quantity:remoteDouble(row["quantity"],fallback:1),quantityUnit:row["quantity_unit"] as? String ?? ingredient.unit,isSynced:true)
                if byId[idText.lowercased()] == nil { context.insert(target) }
                target.prepRecipe=recipe;target.ingredient=ingredient;target.quantity=remoteDouble(row["quantity"],fallback:1)
                target.quantityUnit=row["quantity_unit"] as? String ?? ingredient.unit;target.isSynced=true
            }
            context.saveWithLogging(label:#function)
        } catch { reportSyncFailure("Prep recipe pull: \(error.localizedDescription)",soft:true) }
    }
}
