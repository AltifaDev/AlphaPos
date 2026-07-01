import Foundation
import SwiftData
import Combine
import UIKit
import os

// MARK: - Master Data Sync (Categories, Menu, Modifiers, Branches)
extension SyncEngine {
    // MARK: - Master Data Sync Loop

    func syncCategories(_ modelContext: ModelContext) async {
        var descriptor = FetchDescriptor<Category>(
            predicate: #Predicate<Category> { $0.isDeleted == true || $0.isSynced == false }
        )
        descriptor.fetchLimit = 500  // Prevent OOM on large datasets
        guard let categories = try? modelContext.fetch(descriptor), !categories.isEmpty else { return }
        for category in categories {
            do {
                if category.isDeleted {
                    if try await NetworkManager.shared.deleteCategoryOnServer(id: category.id) { modelContext.delete(category) }
                } else if try await NetworkManager.shared.uploadCategory(category) {
                    category.isSynced = true
                    category.updatedAt = Date()
                }
            } catch {
                encounteredSyncError = true
                print("SyncEngine [Category Push Error]: \(error.localizedDescription)")
            }
        }
        modelContext.saveWithLogging(label: #function)
    }

    func pullCategoriesFromSupabase(_ modelContext: ModelContext) async {
        do {
            let remoteCategories = try await NetworkManager.shared.fetchCategoriesFromSupabase()
            guard !remoteCategories.isEmpty else { return }
            var __desclocals = FetchDescriptor<Category>()
            __desclocals.fetchLimit = 500  // N3: prevent OOM
            let locals = (try? modelContext.fetch(__desclocals)) ?? []
            var localById = Dictionary(uniqueKeysWithValues: locals.map { ($0.id.uuidString.lowercased(), $0) })

            for remote in remoteCategories {
                guard let idStr = remote["id"] as? String,
                      let id = UUID(uuidString: idStr),
                      let name = remote["name"] as? String else { continue }
                let updatedAt = remoteDate(remote["updated_at"], fallback: .distantPast)
                let description = remote["description"] as? String ?? remote["category_description"] as? String

                if let local = localById[idStr.lowercased()] {
                    guard local.isSynced, updatedAt > local.updatedAt else { continue }
                    local.name = name
                    local.categoryDescription = description
                    local.imageUrl = remote["image_url"] as? String
                    local.updatedAt = updatedAt
                    local.isSynced = true
                } else {
                    let category = Category(id: id, name: name, categoryDescription: description, imageUrl: remote["image_url"] as? String, isSynced: true, updatedAt: updatedAt == .distantPast ? Date() : updatedAt)
                    modelContext.insert(category)
                    localById[idStr.lowercased()] = category
                }
            }
            modelContext.saveWithLogging(label: #function)
        } catch {
            encounteredSyncError = true
            print("SyncEngine [Category Pull Error]: \(error.localizedDescription)")
        }
    }

    // MARK: - Branch Sync

    func syncBranches(_ modelContext: ModelContext) async {
        var descriptor = FetchDescriptor<Branch>(
            predicate: #Predicate<Branch> { $0.isSynced == false }
        )
        descriptor.fetchLimit = 500  // Prevent OOM on large datasets
        guard let branches = try? modelContext.fetch(descriptor), !branches.isEmpty else { return }
        for branch in branches {
            do {
                if try await NetworkManager.shared.uploadBranch(branch) {
                    branch.isSynced = true
                    branch.updatedAt = Date()
                    modelContext.saveWithLogging(label: #function)
                }
            } catch {
                encounteredSyncError = true
                print("SyncEngine [Branch Sync Error]: \(error.localizedDescription)")
            }
        }
    }

    func pullBranchesFromSupabase(_ modelContext: ModelContext) async {
        do {
            let remoteBranches = try await NetworkManager.shared.fetchBranchesFromSupabase()
            guard !remoteBranches.isEmpty else { return }
            var __desclocals = FetchDescriptor<Branch>()
            __desclocals.fetchLimit = 500  // N3: prevent OOM
            let locals = (try? modelContext.fetch(__desclocals)) ?? []
            let localById = Dictionary(uniqueKeysWithValues: locals.map { ($0.id.uuidString.lowercased(), $0) })

            for remote in remoteBranches {
                guard let idStr = remote["id"] as? String,
                      let id = UUID(uuidString: idStr),
                      let name = remote["name"] as? String else { continue }
                let updatedAt = remoteDate(remote["updated_at"], fallback: .distantPast)

                if let local = localById[idStr.lowercased()] {
                    // skip if local has pending unsynced changes
                    guard local.isSynced else { continue }
                    if updatedAt > local.updatedAt {
                        local.name = name
                        local.location = remote["location"] as? String
                        local.phone = remote["phone"] as? String
                        local.updatedAt = updatedAt
                        local.isSynced = true
                    }
                } else {
                    let branch = Branch(id: id, name: name, location: remote["location"] as? String, phone: remote["phone"] as? String, isSynced: true, updatedAt: updatedAt == .distantPast ? Date() : updatedAt)
                    modelContext.insert(branch)
                }
            }
            modelContext.saveWithLogging(label: #function)
        } catch {
            encounteredSyncError = true
            print("SyncEngine [Branch Pull Error]: \(error.localizedDescription)")
        }
    }

    func syncInventoryItems(_ modelContext: ModelContext) async {
        var descriptor = FetchDescriptor<InventoryItem>(
            predicate: #Predicate<InventoryItem> { $0.isDeleted == true || $0.isSynced == false }
        )
        descriptor.fetchLimit = 500  // Prevent OOM on large datasets
        guard let items = try? modelContext.fetch(descriptor), !items.isEmpty else { return }
        for item in items {
            do {
                if item.isDeleted {
                    if try await NetworkManager.shared.deleteInventoryItemOnServer(id: item.id) { modelContext.delete(item) }
                } else if try await NetworkManager.shared.uploadInventoryItem(item) {
                    item.isSynced = true
                    item.updatedAt = Date()
                }
            } catch {
                encounteredSyncError = true
                print("SyncEngine [InventoryItem Push Error]: \(error.localizedDescription)")
            }
        }
        modelContext.saveWithLogging(label: #function)
    }

    func pullInventoryItemsFromSupabase(_ modelContext: ModelContext) async {
        do {
            let remoteItems = try await NetworkManager.shared.fetchInventoryItemsFromSupabase()
            guard !remoteItems.isEmpty else { return }
            var __desclocals = FetchDescriptor<InventoryItem>()
            __desclocals.fetchLimit = 500  // N3: prevent OOM
            let locals = (try? modelContext.fetch(__desclocals)) ?? []
            var localById = Dictionary(uniqueKeysWithValues: locals.map { ($0.id.uuidString.lowercased(), $0) })

            for remote in remoteItems {
                guard let idStr = remote["id"] as? String,
                      let id = UUID(uuidString: idStr),
                      let name = remote["name"] as? String else { continue }
                let updatedAt = remoteDate(remote["updated_at"], fallback: .distantPast)
                let isDeletedRemote = remoteBool(remote["is_deleted"])
                if isDeletedRemote { continue }  // L3: skip deleted items from server

                var supplier: Supplier? = nil
                if let supplierIdStr = remote["supplier_id"] as? String, let supplierId = UUID(uuidString: supplierIdStr) {
                    supplier = (try? modelContext.fetch(FetchDescriptor<Supplier>(predicate: #Predicate<Supplier> { $0.id == supplierId })))?.first
                }
                var branch: Branch? = nil
                if let branchIdStr = remote["branch_id"] as? String, let branchId = UUID(uuidString: branchIdStr) {
                    branch = (try? modelContext.fetch(FetchDescriptor<Branch>(predicate: #Predicate<Branch> { $0.id == branchId })))?.first
                }

                if let local = localById[idStr.lowercased()] {
                    guard local.isSynced, updatedAt > local.updatedAt else { continue }
                    local.name = name
                    local.sku = remote["sku"] as? String
                    local.unit = remote["unit"] as? String ?? local.unit
                    local.currentQuantity = remoteDouble(remote["current_quantity"])
                    local.reorderLevel = remoteDouble(remote["reorder_level"])
                    local.costPrice = remoteDouble(remote["cost_price"])
                    local.supplier = supplier
                    local.branch = branch
                    local.category = remote["category"] as? String
                    local.storageLocation = remote["storage_location"] as? String
                    local.barcode = remote["barcode"] as? String
                    // Safety Stock & Lead Time fields (migration_006)
                    local.safetyStockLevel  = remoteDouble(remote["safety_stock_level"])
                    local.maxStockLevel     = remoteDouble(remote["max_stock_level"])
                    local.leadTimeDays      = (remote["lead_time_days"] as? Int) ?? 1
                    // Expiry alert thresholds
                    local.expiryWarningDays  = (remote["expiry_warning_days"]  as? Int) ?? 7
                    local.expiryCriticalDays = (remote["expiry_critical_days"] as? Int) ?? 3
                    local.updatedAt = updatedAt
                    local.isSynced = true
                } else {
                    let item = InventoryItem(
                        id: id,
                        name: name,
                        sku: remote["sku"] as? String,
                        unit: remote["unit"] as? String ?? "piece",
                        currentQuantity: remoteDouble(remote["current_quantity"]),
                        reorderLevel: remoteDouble(remote["reorder_level"]),
                        costPrice: remoteDouble(remote["cost_price"]),
                        supplier: supplier,
                        branch: branch,
                        safetyStockLevel:  remoteDouble(remote["safety_stock_level"]),
                        maxStockLevel:     remoteDouble(remote["max_stock_level"]),
                        leadTimeDays:      (remote["lead_time_days"]      as? Int) ?? 1,
                        expiryWarningDays: (remote["expiry_warning_days"]  as? Int) ?? 7,
                        expiryCriticalDays:(remote["expiry_critical_days"] as? Int) ?? 3,
                        category: remote["category"] as? String,
                        storageLocation: remote["storage_location"] as? String,
                        barcode: remote["barcode"] as? String,
                        isSynced: true,
                        updatedAt: updatedAt == .distantPast ? Date() : updatedAt
                    )
                    modelContext.insert(item)
                    localById[idStr.lowercased()] = item
                }
            }
            modelContext.saveWithLogging(label: #function)
        } catch {
            encounteredSyncError = true
            print("SyncEngine [InventoryItem Pull Error]: \(error.localizedDescription)")
        }
    }

    func syncModifierGroups(_ modelContext: ModelContext) async {
        var descriptor = FetchDescriptor<ModifierGroup>(
            predicate: #Predicate<ModifierGroup> { $0.isDeleted == true || $0.isSynced == false }
        )
        descriptor.fetchLimit = 500  // Prevent OOM on large datasets
        guard let groups = try? modelContext.fetch(descriptor), !groups.isEmpty else { return }
        for group in groups {
            do {
                if group.isDeleted {
                    if try await NetworkManager.shared.deleteModifierGroupOnServer(id: group.id) { modelContext.delete(group) }
                } else if try await NetworkManager.shared.uploadModifierGroup(group) {
                    group.isSynced = true
                    group.updatedAt = Date()
                }
            } catch {
                encounteredSyncError = true
                print("SyncEngine [ModifierGroup Push Error]: \(error.localizedDescription)")
            }
        }
        modelContext.saveWithLogging(label: #function)
    }

    func pullModifierGroupsFromSupabase(_ modelContext: ModelContext) async {
        do {
            let remoteGroups = try await NetworkManager.shared.fetchModifierGroupsFromSupabase()
            guard !remoteGroups.isEmpty else { return }
            var __desclocals = FetchDescriptor<ModifierGroup>()
            __desclocals.fetchLimit = 500  // N3: prevent OOM
            let locals = (try? modelContext.fetch(__desclocals)) ?? []
            var localById = Dictionary(uniqueKeysWithValues: locals.map { ($0.id.uuidString.lowercased(), $0) })

            for remote in remoteGroups {
                guard let idStr = remote["id"] as? String,
                      let id = UUID(uuidString: idStr),
                      let name = remote["name"] as? String else { continue }
                let updatedAt = remoteDate(remote["updated_at"], fallback: .distantPast)
                if let local = localById[idStr.lowercased()] {
                    guard local.isSynced, updatedAt > local.updatedAt else { continue }
                    local.name = name
                    local.minSelection = remoteInt(remote["min_selection"])
                    local.maxSelection = remoteInt(remote["max_selection"], fallback: 1)
                    local.updatedAt = updatedAt
                    local.isSynced = true
                } else {
                    let group = ModifierGroup(id: id, name: name, minSelection: remoteInt(remote["min_selection"]), maxSelection: remoteInt(remote["max_selection"], fallback: 1), isSynced: true, updatedAt: updatedAt == .distantPast ? Date() : updatedAt)
                    modelContext.insert(group)
                    localById[idStr.lowercased()] = group
                }
            }
            modelContext.saveWithLogging(label: #function)
        } catch {
            encounteredSyncError = true
            print("SyncEngine [ModifierGroup Pull Error]: \(error.localizedDescription)")
        }
    }

    func syncModifiers(_ modelContext: ModelContext) async {
        var descriptor = FetchDescriptor<Modifier>(
            predicate: #Predicate<Modifier> { $0.isDeleted == true || $0.isSynced == false }
        )
        descriptor.fetchLimit = 500  // Prevent OOM on large datasets
        guard let modifiers = try? modelContext.fetch(descriptor), !modifiers.isEmpty else { return }
        for modifier in modifiers {
            do {
                if modifier.isDeleted {
                    if try await NetworkManager.shared.deleteModifierOnServer(id: modifier.id) { modelContext.delete(modifier) }
                } else if try await NetworkManager.shared.uploadModifier(modifier) {
                    modifier.isSynced = true
                    modifier.updatedAt = Date()
                }
            } catch {
                encounteredSyncError = true
                print("SyncEngine [Modifier Push Error]: \(error.localizedDescription)")
            }
        }
        modelContext.saveWithLogging(label: #function)
    }

    func pullModifiersFromSupabase(_ modelContext: ModelContext) async {
        do {
            let remoteModifiers = try await NetworkManager.shared.fetchModifiersFromSupabase()
            guard !remoteModifiers.isEmpty else { return }
            var __desclocals = FetchDescriptor<Modifier>()
            __desclocals.fetchLimit = 500  // N3: prevent OOM
            let locals = (try? modelContext.fetch(__desclocals)) ?? []
            var localById = Dictionary(uniqueKeysWithValues: locals.map { ($0.id.uuidString.lowercased(), $0) })

            for remote in remoteModifiers {
                guard let idStr = remote["id"] as? String,
                      let id = UUID(uuidString: idStr),
                      let name = remote["name"] as? String else { continue }
                var group: ModifierGroup? = nil
                if let groupIdStr = remote["modifier_group_id"] as? String, let groupId = UUID(uuidString: groupIdStr) {
                    group = (try? modelContext.fetch(FetchDescriptor<ModifierGroup>(predicate: #Predicate<ModifierGroup> { $0.id == groupId })))?.first
                }
                var inventoryItem: InventoryItem? = nil
                if let itemIdStr = remote["inventory_item_id"] as? String, let itemId = UUID(uuidString: itemIdStr) {
                    inventoryItem = (try? modelContext.fetch(FetchDescriptor<InventoryItem>(predicate: #Predicate<InventoryItem> { $0.id == itemId })))?.first
                }
                let updatedAt = remoteDate(remote["updated_at"], fallback: .distantPast)
                let quantityRequired = remote["quantity_required"].map { remoteDouble($0) }

                if let local = localById[idStr.lowercased()] {
                    guard local.isSynced, updatedAt > local.updatedAt else { continue }
                    local.modifierGroup = group
                    local.name = name
                    local.extraPrice = remoteDouble(remote["extra_price"])
                    local.isAvailable = remoteBool(remote["is_available"], fallback: true)
                    local.inventoryItemLink = inventoryItem
                    local.quantityRequired = quantityRequired
                    local.updatedAt = updatedAt
                    local.isSynced = true
                } else {
                    let modifier = Modifier(id: id, modifierGroup: group, name: name, extraPrice: remoteDouble(remote["extra_price"]), isAvailable: remoteBool(remote["is_available"], fallback: true), inventoryItemLink: inventoryItem, quantityRequired: quantityRequired, isSynced: true, updatedAt: updatedAt == .distantPast ? Date() : updatedAt)
                    modelContext.insert(modifier)
                    localById[idStr.lowercased()] = modifier
                }
            }
            modelContext.saveWithLogging(label: #function)
        } catch {
            encounteredSyncError = true
            print("SyncEngine [Modifier Pull Error]: \(error.localizedDescription)")
        }
    }

    func syncMenuItemModifierGroups(_ modelContext: ModelContext) async {
        var descriptor = FetchDescriptor<MenuItemModifierGroup>(
            predicate: #Predicate<MenuItemModifierGroup> { $0.isDeleted == true || $0.isSynced == false }
        )
        descriptor.fetchLimit = 500  // Prevent OOM on large datasets
        guard let relations = try? modelContext.fetch(descriptor), !relations.isEmpty else { return }
        for relation in relations {
            do {
                if relation.isDeleted {
                    if let menuItemId = relation.menuItem?.id, let modifierGroupId = relation.modifierGroup?.id {
                        if try await NetworkManager.shared.deleteMenuItemModifierGroupOnServer(menuItemId: menuItemId, modifierGroupId: modifierGroupId) { modelContext.delete(relation) }
                    } else {
                        modelContext.delete(relation)
                    }
                } else if try await NetworkManager.shared.uploadMenuItemModifierGroup(relation) {
                    relation.isSynced = true
                    relation.updatedAt = Date()
                }
            } catch {
                encounteredSyncError = true
                print("SyncEngine [MenuItemModifierGroup Push Error]: \(error.localizedDescription)")
            }
        }
        modelContext.saveWithLogging(label: #function)
    }

    func pullMenuItemModifierGroupsFromSupabase(_ modelContext: ModelContext) async {
        do {
            let remoteRelations = try await NetworkManager.shared.fetchMenuItemModifierGroupsFromSupabase()
            guard !remoteRelations.isEmpty else { return }
            var __desclocals = FetchDescriptor<MenuItemModifierGroup>()
            __desclocals.fetchLimit = 500  // N3: prevent OOM
            let locals = (try? modelContext.fetch(__desclocals)) ?? []
            var localByKey: [String: MenuItemModifierGroup] = [:]
            for relation in locals {
                if let itemId = relation.menuItem?.id.lowercased(), let groupId = relation.modifierGroup?.id.uuidString.lowercased() {
                    localByKey["\(itemId)|\(groupId)"] = relation
                }
            }

            for remote in remoteRelations {
                guard let menuItemId = remote["menu_item_id"] as? String,
                      let groupIdStr = remote["modifier_group_id"] as? String,
                      let groupId = UUID(uuidString: groupIdStr) else { continue }
                let menuItem = (try? modelContext.fetch(FetchDescriptor<MenuItem>(predicate: #Predicate<MenuItem> { $0.id == menuItemId })))?.first
                let modifierGroup = (try? modelContext.fetch(FetchDescriptor<ModifierGroup>(predicate: #Predicate<ModifierGroup> { $0.id == groupId })))?.first
                guard let menuItem, let modifierGroup else { continue }

                let key = "\(menuItemId.lowercased())|\(groupIdStr.lowercased())"
                let updatedAt = remoteDate(remote["updated_at"], fallback: .distantPast)
                if let local = localByKey[key] {
                    guard local.isSynced, updatedAt > local.updatedAt else { continue }
                    local.menuItem = menuItem
                    local.modifierGroup = modifierGroup
                    local.updatedAt = updatedAt
                    local.isSynced = true
                } else {
                    let id = (remote["id"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID()
                    let relation = MenuItemModifierGroup(id: id, menuItem: menuItem, modifierGroup: modifierGroup, isSynced: true, updatedAt: updatedAt == .distantPast ? Date() : updatedAt)
                    modelContext.insert(relation)
                    localByKey[key] = relation
                }
            }
            modelContext.saveWithLogging(label: #function)
        } catch {
            encounteredSyncError = true
            print("SyncEngine [MenuItemModifierGroup Pull Error]: \(error.localizedDescription)")
        }
    }

    func syncInventoryTransactions(_ modelContext: ModelContext) async {
        var descriptor = FetchDescriptor<InventoryTransaction>(
            predicate: #Predicate<InventoryTransaction> { $0.isSynced == false }
        )
        descriptor.fetchLimit = 500  // Prevent OOM on large datasets

        guard let txns = try? modelContext.fetch(descriptor), !txns.isEmpty else { return }

        for txn in txns {
            if txn.isDeleted {
                modelContext.delete(txn)
                modelContext.saveWithLogging(label: #function)
                continue
            }

            let itemName = txn.item?.name ?? "Unknown"
            do {
                let success = try await NetworkManager.shared.uploadInventoryTransaction(
                    id: txn.id,
                    itemId: txn.item?.id,
                    itemName: itemName,
                    quantity: txn.quantity,
                    type: txn.transactionType,
                    costPrice: txn.costPrice,
                    referenceId: txn.referenceId,
                    notes: txn.notes,
                    branchId: txn.branch?.id,
                    isDeleted: txn.isDeleted,
                    updatedAt: txn.updatedAt
                )

                if success {
                    txn.isSynced = true
                    txn.updatedAt = Date()
                    try modelContext.save()
                }
            } catch {
                encounteredSyncError = true
                print("SyncEngine [InventoryTxn Sync Error]: \(error.localizedDescription)")
            }
        }
    }

    func syncMenuItems(_ modelContext: ModelContext) async {
        var descriptor = FetchDescriptor<MenuItem>(
            predicate: #Predicate<MenuItem> { $0.isSynced == false }
        )
        descriptor.fetchLimit = 500  // Prevent OOM on large datasets

        guard let items = try? modelContext.fetch(descriptor), !items.isEmpty else { return }

        for item in items {
            if item.isDeleted {
                do {
                    if try await NetworkManager.shared.deleteMenuItemOnServer(id: item.id) {
                        modelContext.delete(item)
                        try modelContext.save()
                    } else {
                        encounteredSyncError = true
                    }
                } catch {
                    encounteredSyncError = true
                    print("SyncEngine [MenuItem Delete Error]: \(error.localizedDescription)")
                }
                continue
            }

            do {
                let success = try await NetworkManager.shared.uploadMenuItem(item: item)
                if success {
                    item.isSynced = true
                    item.updatedAt = Date()
                    try modelContext.save()
                }
            } catch {
                encounteredSyncError = true
                print("SyncEngine [MenuItem Sync Error]: \(error.localizedDescription)")
            }
        }
    }

}
