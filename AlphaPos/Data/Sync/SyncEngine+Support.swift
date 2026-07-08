import Foundation
import SwiftData
import Combine
import UIKit
import os

// MARK: - Support Data Sync (Supplier, TaxRate, Recipe, CurrencyExchangeRate, User)
// These models support core operations and must be synced to enable
// multi-device consistency for master data management.
extension SyncEngine {

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - Supplier
    // ──────────────────────────────────────────────────────────────────────

    func syncSuppliers(_ modelContext: ModelContext) async {
        var descriptor = FetchDescriptor<Supplier>(
            predicate: #Predicate<Supplier> { $0.isDeleted == true || $0.isSynced == false }
        )
        descriptor.fetchLimit = 500
        guard let suppliers = try? modelContext.fetch(descriptor), !suppliers.isEmpty else { return }

        for supplier in suppliers {
            do {
                if supplier.isDeleted {
                    if try await NetworkManager.shared.deleteSupplierOnServer(id: supplier.id) {
                        modelContext.delete(supplier)
                    }
                } else if try await NetworkManager.shared.uploadSupplier(supplier) {
                    supplier.isSynced = true
                    supplier.updatedAt = Date()
                }
            } catch {
                encounteredSyncError = true
                print("SyncEngine [Supplier Push Error]: \(error.localizedDescription)")
            }
        }
        modelContext.saveWithLogging(label: #function)
    }

    func pullSuppliersFromSupabase(_ modelContext: ModelContext) async {
        do {
            let remoteSuppliers = try await NetworkManager.shared.fetchSuppliersFromSupabase()
            guard !remoteSuppliers.isEmpty else { return }

            var __desclocals = FetchDescriptor<Supplier>()
            __desclocals.fetchLimit = 500
            let locals = (try? modelContext.fetch(__desclocals)) ?? []
            var localById = Dictionary(uniqueKeysWithValues: locals.map { ($0.id.uuidString.lowercased(), $0) })

            for remote in remoteSuppliers {
                guard let idStr = remote["id"] as? String,
                      let id = UUID(uuidString: idStr),
                      let name = remote["name"] as? String else { continue }
                let updatedAt = remoteDate(remote["updated_at"], fallback: .distantPast)

                if let local = localById[idStr.lowercased()] {
                    guard local.isSynced, updatedAt > local.updatedAt else { continue }
                    if local.isDeleted { continue }
                    local.name = name
                    local.contactName = remote["contact_name"] as? String
                    local.phone = remote["phone"] as? String
                    local.email = remote["email"] as? String
                    local.address = remote["address"] as? String
                    local.updatedAt = updatedAt
                    local.isSynced = true
                } else {
                    let supplier = Supplier(
                        id: id,
                        name: name,
                        contactName: remote["contact_name"] as? String,
                        phone: remote["phone"] as? String,
                        email: remote["email"] as? String,
                        address: remote["address"] as? String,
                        isSynced: true,
                        isDeleted: false,
                        updatedAt: updatedAt == .distantPast ? Date() : updatedAt
                    )
                    modelContext.insert(supplier)
                    localById[idStr.lowercased()] = supplier
                }
            }
            modelContext.saveWithLogging(label: #function)
        } catch {
            encounteredSyncError = true
            print("SyncEngine [Supplier Pull Error]: \(error.localizedDescription)")
        }
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - TaxRate
    // ──────────────────────────────────────────────────────────────────────

    func syncTaxRates(_ modelContext: ModelContext) async {
        var descriptor = FetchDescriptor<TaxRate>(
            predicate: #Predicate<TaxRate> { $0.isDeleted == true || $0.isSynced == false }
        )
        descriptor.fetchLimit = 500
        guard let taxRates = try? modelContext.fetch(descriptor), !taxRates.isEmpty else { return }

        for taxRate in taxRates {
            do {
                if taxRate.isDeleted {
                    if try await NetworkManager.shared.deleteTaxRateOnServer(id: taxRate.id) {
                        modelContext.delete(taxRate)
                    }
                } else if try await NetworkManager.shared.uploadTaxRate(taxRate) {
                    taxRate.isSynced = true
                    taxRate.updatedAt = Date()
                }
            } catch {
                encounteredSyncError = true
                print("SyncEngine [TaxRate Push Error]: \(error.localizedDescription)")
            }
        }
        modelContext.saveWithLogging(label: #function)
    }

    func pullTaxRatesFromSupabase(_ modelContext: ModelContext) async {
        do {
            let remoteRates = try await NetworkManager.shared.fetchTaxRatesFromSupabase()
            guard !remoteRates.isEmpty else { return }

            var __desclocals = FetchDescriptor<TaxRate>()
            __desclocals.fetchLimit = 500
            let locals = (try? modelContext.fetch(__desclocals)) ?? []
            var localById = Dictionary(uniqueKeysWithValues: locals.map { ($0.id.uuidString.lowercased(), $0) })

            for remote in remoteRates {
                guard let idStr = remote["id"] as? String,
                      let id = UUID(uuidString: idStr),
                      let name = remote["name"] as? String else { continue }
                let updatedAt = remoteDate(remote["updated_at"], fallback: .distantPast)

                if let local = localById[idStr.lowercased()] {
                    guard local.isSynced, updatedAt > local.updatedAt else { continue }
                    if local.isDeleted { continue }
                    local.name = name
                    local.ratePercentage = remoteDouble(remote["rate_percentage"])
                    local.taxType = remote["tax_type"] as? String ?? local.taxType
                    local.isDefault = remoteBool(remote["is_default"])
                    local.isActive = remoteBool(remote["is_active"], fallback: true)
                    local.updatedAt = updatedAt
                    local.isSynced = true
                } else {
                    let taxRate = TaxRate(
                        id: id,
                        name: name,
                        ratePercentage: remoteDouble(remote["rate_percentage"]),
                        taxType: remote["tax_type"] as? String ?? "exclusive",
                        isDefault: remoteBool(remote["is_default"]),
                        isActive: remoteBool(remote["is_active"], fallback: true),
                        isSynced: true,
                        isDeleted: false,
                        updatedAt: updatedAt == .distantPast ? Date() : updatedAt,
                        createdAt: remoteDate(remote["created_at"], fallback: Date())
                    )
                    modelContext.insert(taxRate)
                    localById[idStr.lowercased()] = taxRate
                }
            }
            modelContext.saveWithLogging(label: #function)
        } catch {
            encounteredSyncError = true
            print("SyncEngine [TaxRate Pull Error]: \(error.localizedDescription)")
        }
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - Recipe
    // ──────────────────────────────────────────────────────────────────────

    func syncRecipes(_ modelContext: ModelContext) async {
        var descriptor = FetchDescriptor<Recipe>(
            predicate: #Predicate<Recipe> { $0.isDeleted == true || $0.isSynced == false }
        )
        descriptor.fetchLimit = 500
        guard let recipes = try? modelContext.fetch(descriptor), !recipes.isEmpty else { return }

        for recipe in recipes {
            do {
                if recipe.isDeleted {
                    if try await NetworkManager.shared.deleteRecipeOnServer(id: recipe.id) {
                        modelContext.delete(recipe)
                    }
                } else if try await NetworkManager.shared.uploadRecipe(recipe) {
                    recipe.isSynced = true
                    recipe.updatedAt = Date()
                }
            } catch {
                encounteredSyncError = true
                print("SyncEngine [Recipe Push Error]: \(error.localizedDescription)")
            }
        }
        modelContext.saveWithLogging(label: #function)
    }

    func pullRecipesFromSupabase(_ modelContext: ModelContext) async {
        do {
            let remoteRecipes = try await NetworkManager.shared.fetchRecipesFromSupabase()
            guard !remoteRecipes.isEmpty else { return }

            var __desclocals = FetchDescriptor<Recipe>()
            __desclocals.fetchLimit = 500
            let locals = (try? modelContext.fetch(__desclocals)) ?? []
            var localById = Dictionary(uniqueKeysWithValues: locals.map { ($0.id.uuidString.lowercased(), $0) })

            for remote in remoteRecipes {
                guard let idStr = remote["id"] as? String,
                      let id = UUID(uuidString: idStr) else { continue }
                let updatedAt = remoteDate(remote["updated_at"], fallback: .distantPast)

                var menuItem: MenuItem? = nil
                if let mid = remote["menu_item_id"] as? String {
                    menuItem = (try? modelContext.fetch(FetchDescriptor<MenuItem>(predicate: #Predicate<MenuItem> { $0.id == mid })))?.first
                }
                var inventoryItem: InventoryItem? = nil
                if let iid = remote["inventory_item_id"] as? String, let itemId = UUID(uuidString: iid) {
                    inventoryItem = (try? modelContext.fetch(FetchDescriptor<InventoryItem>(predicate: #Predicate<InventoryItem> { $0.id == itemId })))?.first
                }

                if let local = localById[idStr.lowercased()] {
                    guard local.isSynced, updatedAt > local.updatedAt else { continue }
                    if local.isDeleted { continue }
                    local.menuItem = menuItem
                    local.inventoryItem = inventoryItem
                    local.quantityRequired = remoteDouble(remote["quantity_required"], fallback: 1.0)
                    local.updatedAt = updatedAt
                    local.isSynced = true
                } else {
                    let recipe = Recipe(
                        id: id,
                        menuItem: menuItem,
                        inventoryItem: inventoryItem,
                        quantityRequired: remoteDouble(remote["quantity_required"], fallback: 1.0),
                        isSynced: true,
                        isDeleted: false,
                        updatedAt: updatedAt == .distantPast ? Date() : updatedAt
                    )
                    modelContext.insert(recipe)
                    localById[idStr.lowercased()] = recipe
                }
            }
            modelContext.saveWithLogging(label: #function)
        } catch {
            encounteredSyncError = true
            print("SyncEngine [Recipe Pull Error]: \(error.localizedDescription)")
        }
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - CurrencyExchangeRate
    // ──────────────────────────────────────────────────────────────────────

    func syncCurrencyExchangeRates(_ modelContext: ModelContext) async {
        var descriptor = FetchDescriptor<CurrencyExchangeRate>(
            predicate: #Predicate<CurrencyExchangeRate> { $0.isDeleted == true || $0.isSynced == false }
        )
        descriptor.fetchLimit = 500
        guard let rates = try? modelContext.fetch(descriptor), !rates.isEmpty else { return }

        for rate in rates {
            do {
                if rate.isDeleted {
                    if try await NetworkManager.shared.deleteCurrencyExchangeRateOnServer(id: rate.id) {
                        modelContext.delete(rate)
                    }
                } else if try await NetworkManager.shared.uploadCurrencyExchangeRate(rate) {
                    rate.isSynced = true
                    rate.updatedAt = Date()
                }
            } catch {
                encounteredSyncError = true
                print("SyncEngine [CurrencyExchangeRate Push Error]: \(error.localizedDescription)")
            }
        }
        modelContext.saveWithLogging(label: #function)
    }

    func pullCurrencyExchangeRatesFromSupabase(_ modelContext: ModelContext) async {
        do {
            let remoteRates = try await NetworkManager.shared.fetchCurrencyExchangeRatesFromSupabase()
            guard !remoteRates.isEmpty else { return }

            var __desclocals = FetchDescriptor<CurrencyExchangeRate>()
            __desclocals.fetchLimit = 500
            let locals = (try? modelContext.fetch(__desclocals)) ?? []
            var localById = Dictionary(uniqueKeysWithValues: locals.map { ($0.id.uuidString.lowercased(), $0) })

            for remote in remoteRates {
                guard let idStr = remote["id"] as? String,
                      let id = UUID(uuidString: idStr) else { continue }
                let updatedAt = remoteDate(remote["updated_at"], fallback: .distantPast)

                if let local = localById[idStr.lowercased()] {
                    guard local.isSynced, updatedAt > local.updatedAt else { continue }
                    if local.isDeleted { continue }
                    local.baseCurrency = remote["base_currency"] as? String ?? local.baseCurrency
                    local.targetCurrency = remote["target_currency"] as? String ?? local.targetCurrency
                    local.exchangeRate = remoteDouble(remote["exchange_rate"], fallback: 1.0)
                    local.effectiveDate = remoteDate(remote["effective_date"])
                    local.isActive = remoteBool(remote["is_active"], fallback: true)
                    local.updatedAt = updatedAt
                    local.isSynced = true
                } else {
                    let rate = CurrencyExchangeRate(
                        id: id,
                        baseCurrency: remote["base_currency"] as? String ?? "THB",
                        targetCurrency: remote["target_currency"] as? String ?? "USD",
                        exchangeRate: remoteDouble(remote["exchange_rate"], fallback: 1.0),
                        effectiveDate: remoteDate(remote["effective_date"]),
                        isActive: remoteBool(remote["is_active"], fallback: true),
                        isSynced: true,
                        isDeleted: false,
                        updatedAt: updatedAt == .distantPast ? Date() : updatedAt,
                        createdAt: remoteDate(remote["created_at"], fallback: Date())
                    )
                    modelContext.insert(rate)
                    localById[idStr.lowercased()] = rate
                }
            }
            modelContext.saveWithLogging(label: #function)
        } catch {
            encounteredSyncError = true
            print("SyncEngine [CurrencyExchangeRate Pull Error]: \(error.localizedDescription)")
        }
    }

    // ──────────────────────────────────────────────────────────────────────
    // MARK: - Role
    // ──────────────────────────────────────────────────────────────────────

    func syncRoles(_ modelContext: ModelContext) async {
        var descriptor = FetchDescriptor<Role>(
            predicate: #Predicate<Role> { $0.isDeleted == true || $0.isSynced == false }
        )
        descriptor.fetchLimit = 500
        guard let roles = try? modelContext.fetch(descriptor), !roles.isEmpty else { return }

        for role in roles {
            do {
                if role.isDeleted {
                    if try await NetworkManager.shared.deleteRoleOnServer(id: role.id) {
                        modelContext.delete(role)
                    }
                } else if try await NetworkManager.shared.uploadRole(role) {
                    let permSuccess = (try? await NetworkManager.shared.replaceRolePermissions(role: role)) ?? false
                    if permSuccess {
                        role.isSynced = true
                        role.updatedAt = Date()
                    }
                }
            } catch {
                encounteredSyncError = true
                print("SyncEngine [Role Push Error]: \(error.localizedDescription)")
            }
        }
        modelContext.saveWithLogging(label: #function)
    }

    func pullRolesFromSupabase(_ modelContext: ModelContext) async {
        do {
            let remoteRoles = try await NetworkManager.shared.fetchRolesFromSupabase()

            // Self-heal: If any local role is marked isSynced = true, but does not exist in the remote list,
            // it means the server doesn't have it (e.g. from an incomplete previous sync).
            // We reset isSynced to false so it will get pushed in the next sync loop.
            let remoteIds = Set(remoteRoles.compactMap { ($0["id"] as? String)?.lowercased() })

            var __desclocals = FetchDescriptor<Role>()
            __desclocals.fetchLimit = 500
            let locals = (try? modelContext.fetch(__desclocals)) ?? []
            var localById = Dictionary(uniqueKeysWithValues: locals.map { ($0.id.uuidString.lowercased(), $0) })

            var selfHealChanged = false
            for local in locals {
                let localIdStr = local.id.uuidString.lowercased()
                if local.isSynced && !remoteIds.contains(localIdStr) {
                    local.isSynced = false
                    selfHealChanged = true
                    print("SyncEngine [Role Self-Heal]: Marked role \(local.name) (\(localIdStr)) as unsynced because it was not found on the server.")
                }
            }
            if selfHealChanged {
                modelContext.saveWithLogging(label: #function)
            }

            guard !remoteRoles.isEmpty else { return }

            // Fetch remote role permissions to align permissionKeys local cache
            let remotePermissions = (try? await NetworkManager.shared.fetchRolePermissionsFromSupabase()) ?? []
            var permissionsByRole: [String: [String]] = [:]
            for perm in remotePermissions {
                if let roleName = perm["role"] as? String,
                   let key = perm["permission_key"] as? String {
                    permissionsByRole[roleName, default: []].append(key)
                }
            }

            for remote in remoteRoles {
                guard let idStr = remote["id"] as? String,
                      let id = UUID(uuidString: idStr),
                      let name = remote["name"] as? String else { continue }
                let updatedAt = remoteDate(remote["updated_at"], fallback: .distantPast)
                let permissionKeysStr = permissionsByRole[name]?.sorted().joined(separator: ",") ?? ""

                if let local = localById[idStr.lowercased()] {
                    guard local.isSynced, updatedAt > local.updatedAt else { continue }
                    if local.isDeleted { continue }
                    local.name = name
                    local.roleDescription = remote["description"] as? String
                    local.permissionKeys = permissionKeysStr
                    local.updatedAt = updatedAt
                    local.isSynced = true
                } else {
                    let role = Role(
                        id: id,
                        name: name,
                        roleDescription: remote["description"] as? String,
                        permissionKeys: permissionKeysStr,
                        isSynced: true,
                        isDeleted: false,
                        updatedAt: updatedAt == .distantPast ? Date() : updatedAt
                    )
                    modelContext.insert(role)
                    localById[idStr.lowercased()] = role
                }
            }
            modelContext.saveWithLogging(label: #function)
        } catch {
            encounteredSyncError = true
            print("SyncEngine [Role Pull Error]: \(error.localizedDescription)")
        }
    }

    // MARK: - User
    // ──────────────────────────────────────────────────────────────────────

    func syncUsers(_ modelContext: ModelContext) async {
        var descriptor = FetchDescriptor<User>(
            predicate: #Predicate<User> { $0.isDeleted == true || $0.isSynced == false }
        )
        descriptor.fetchLimit = 500
        guard let users = try? modelContext.fetch(descriptor), !users.isEmpty else { return }

        for user in users {
            do {
                if let role = user.role, !role.isSynced {
                    continue // Defer user sync until role is synced to server
                }

                if user.isDeleted {
                    if try await NetworkManager.shared.deleteUserOnServer(id: user.id) {
                        modelContext.delete(user)
                    }
                } else if try await NetworkManager.shared.uploadUser(user) {
                    user.isSynced = true
                    user.updatedAt = Date()
                }
            } catch {
                encounteredSyncError = true
                print("SyncEngine [User Push Error]: \(error.localizedDescription)")
            }
        }
        modelContext.saveWithLogging(label: #function)
    }

    func pullUsersFromSupabase(_ modelContext: ModelContext) async {
        do {
            let remoteUsers = try await NetworkManager.shared.fetchUsersFromSupabase()
            guard !remoteUsers.isEmpty else { return }

            var __desclocals = FetchDescriptor<User>()
            __desclocals.fetchLimit = 500
            let locals = (try? modelContext.fetch(__desclocals)) ?? []

            // Deduplicate: If any local user has the same username but a different ID, delete it.
            for remote in remoteUsers {
                guard let idStr = remote["id"] as? String,
                      let id = UUID(uuidString: idStr),
                      let username = remote["username"] as? String else { continue }
                if let conflict = locals.first(where: { $0.id != id && $0.username.lowercased() == username.lowercased() }) {
                    modelContext.delete(conflict)
                }
            }
            try? modelContext.save()
            var localById = Dictionary(uniqueKeysWithValues: locals.map { ($0.id.uuidString.lowercased(), $0) })

            // Pre-fetch roles
            let allRoles = (try? modelContext.fetch(FetchDescriptor<Role>())) ?? []
            let roleMap = Dictionary(uniqueKeysWithValues: allRoles.map { ($0.id.uuidString.lowercased(), $0) })

            for remote in remoteUsers {
                guard let idStr = remote["id"] as? String,
                      let id = UUID(uuidString: idStr),
                      let username = remote["username"] as? String else { continue }
                let updatedAt = remoteDate(remote["updated_at"], fallback: .distantPast)

                var role: Role? = nil
                if let rid = remote["role_id"] as? String { role = roleMap[rid.lowercased()] }

                if let local = localById[idStr.lowercased()] {
                    guard local.isSynced, updatedAt > local.updatedAt else { continue }
                    if local.isDeleted { continue }
                    local.username = username
                    local.email = remote["email"] as? String
                    if let pwdHash = remote["password_hash"] as? String { local.passwordHash = pwdHash }
                    local.pinCodeHash = remote["pin_code_hash"] as? String
                    local.role = role
                    local.isActive = remoteBool(remote["is_active"], fallback: true)
                    local.updatedAt = updatedAt
                    local.isSynced = true
                } else {
                    let user = User(
                        id: id,
                        username: username,
                        email: remote["email"] as? String,
                        passwordHash: remote["password_hash"] as? String ?? "",
                        pinCodeHash: remote["pin_code_hash"] as? String,
                        role: role,
                        isActive: remoteBool(remote["is_active"], fallback: true),
                        isSynced: true,
                        isDeleted: false,
                        updatedAt: updatedAt == .distantPast ? Date() : updatedAt
                    )
                    modelContext.insert(user)
                    localById[idStr.lowercased()] = user
                }
            }
            modelContext.saveWithLogging(label: #function)
        } catch {
            encounteredSyncError = true
            print("SyncEngine [User Pull Error]: \(error.localizedDescription)")
        }
    }
}
