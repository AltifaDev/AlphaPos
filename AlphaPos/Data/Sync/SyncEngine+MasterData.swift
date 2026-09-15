import Foundation
import SwiftData

enum InventoryTransactionIdentityPolicy {
    static func canMatchByReference(
        remoteReferenceId: UUID?,
        localReferenceId: UUID?,
        remoteItemId: UUID?,
        localItemId: UUID?,
        remoteType: String,
        localType: String
    ) -> Bool {
        guard let remoteReferenceId else { return false }
        return localReferenceId == remoteReferenceId
            && localItemId == remoteItemId
            && localType == remoteType
    }
}

enum BranchParentSyncPolicy {
    static func requiresUpload(localIsSynced: Bool, existsRemotely: Bool) -> Bool {
        !localIsSynced || !existsRemotely
    }
}
import Combine
import UIKit
import os

// MARK: - Master Data Sync (Categories, Menu, Modifiers, Branches)
extension SyncEngine {
    // MARK: - Master Data Sync Loop

    func syncCategories(_ modelContext: ModelContext) async {
        var descriptor = FetchDescriptor<Category>(
            predicate: #Predicate<Category> { $0.isSynced == false }
        )
        descriptor.fetchLimit = 500  // Prevent OOM on large datasets
        guard let categories = try? modelContext.fetch(descriptor), !categories.isEmpty else { return }
        for category in categories {
            do {
                if category.isDeleted {
                    if try await NetworkManager.shared.deleteCategoryOnServer(id: category.id) {
                        category.isSynced = true
                        category.updatedAt = Date()
                    }
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
            // Use reduce(into:) instead of Dictionary(uniqueKeysWithValues:) to safely handle
            // duplicate category names in local store (e.g. "beverages" vs "Beverages")
            // uniqueKeysWithValues crashes with Fatal error when duplicate keys exist.
            var localByName: [String: Category] = locals.reduce(into: [:]) { dict, cat in
                dict[cat.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] = cat
            }

            for remote in remoteCategories {
                guard let idStr = remote["id"] as? String,
                      let id = UUID(uuidString: idStr),
                      let name = remote["name"] as? String else { continue }
                let updatedAt = remoteDate(remote["updated_at"], fallback: .distantPast)
                let description = remote["description"] as? String ?? remote["category_description"] as? String
                let nameKey = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

                if let local = localById[idStr.lowercased()] {
                    let decision = shouldApplyRemoteUpdate(localIsSynced: local.isSynced, localUpdatedAt: local.updatedAt, remoteUpdatedAt: updatedAt)
                    guard decision == .applyRemote else { continue }
                    local.name = name
                    local.categoryDescription = description
                    local.imageUrl = remote["image_url"] as? String
                    local.updatedAt = updatedAt
                    local.isSynced = true
                } else if let local = localByName[nameKey] {
                    local.categoryDescription = description
                    local.imageUrl = remote["image_url"] as? String
                    local.updatedAt = max(local.updatedAt, updatedAt == .distantPast ? Date() : updatedAt)
                    local.isSynced = true
                    localById[idStr.lowercased()] = local
                } else {
                    let category = Category(id: id, name: name, categoryDescription: description, imageUrl: remote["image_url"] as? String, isSynced: true, updatedAt: updatedAt == .distantPast ? Date() : updatedAt)
                    modelContext.insert(category)
                    localById[idStr.lowercased()] = category
                    localByName[nameKey] = category
                }
            }
            // Clean up any legacy duplicate categories (same name, different id) that
            // were created by earlier seed/import paths before name-matching existed.
            deduplicateCategories(modelContext)
            modelContext.saveWithLogging(label: #function)
        } catch {
            encounteredSyncError = true
            print("SyncEngine [Category Pull Error]: \(error.localizedDescription)")
        }
    }

    /// Merge duplicate categories that share the same (case-insensitive, trimmed) name.
    /// Keeps a single "primary" row per name (prefer synced, then oldest), re-links all
    /// MenuItems from duplicates onto the primary, and removes redundant local aliases.
    func deduplicateCategories(_ modelContext: ModelContext) {
        var descriptor = FetchDescriptor<Category>()
        descriptor.fetchLimit = 1000
        guard let all = try? modelContext.fetch(descriptor) else { return }

        // Group active categories by normalized name.
        var groups: [String: [Category]] = [:]
        for cat in all where !cat.isDeleted {
            let key = cat.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            groups[key, default: []].append(cat)
        }

        for (_, dupes) in groups where dupes.count > 1 {
            // Choose primary: prefer already-synced rows, then the oldest updatedAt (stable id).
            let sorted = dupes.sorted { lhs, rhs in
                if lhs.isSynced != rhs.isSynced { return lhs.isSynced && !rhs.isSynced }
                return lhs.updatedAt < rhs.updatedAt
            }
            guard let primary = sorted.first else { continue }

            for dup in sorted.dropFirst() {
                // Re-link menu items from the duplicate onto the primary category.
                for item in dup.menuItems {
                    item.category = primary
                    item.isSynced = false            // force re-sync of the re-pointed item
                    item.updatedAt = Date()
                }
                // The server already enforces one active normalized name per merchant.
                // This row is therefore a local alias (or an already-deleted remote row),
                // not a user deletion that still needs to be pushed.
                dup.isDeleted = true
                dup.isSynced = true
                dup.updatedAt = Date()
            }
        }

        // Repair aliases left by older builds. Preserve genuine user deletions:
        // only suppress a tombstone when another active local category has the same name.
        let activeNames = Set(all.lazy.filter { !$0.isDeleted }.map {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        })
        for category in all where category.isDeleted && !category.isSynced {
            let key = category.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if activeNames.contains(key) {
                category.isSynced = true
            }
        }
    }

    // MARK: - Branch Sync

    func syncBranches(_ modelContext: ModelContext) async {
        var descriptor = FetchDescriptor<Branch>()
        descriptor.fetchLimit = 500  // Prevent OOM on large datasets
        guard let branches = try? modelContext.fetch(descriptor), !branches.isEmpty else { return }
        let remoteIds: Set<UUID>
        do {
            remoteIds = Set(try await NetworkManager.shared.fetchBranchesFromSupabase().compactMap {
                ($0["id"] as? String).flatMap(UUID.init(uuidString:))
            })
        } catch {
            reportSyncFailure("Branch parent verification: \(error.localizedDescription)", soft: false)
            return
        }

        for branch in branches where !branch.isDeleted {
            guard BranchParentSyncPolicy.requiresUpload(
                localIsSynced: branch.isSynced,
                existsRemotely: remoteIds.contains(branch.id)
            ) else { continue }
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
                        local.businessDayCutoffHour = Int(remoteDouble(remote["business_day_cutoff_hour"], fallback: 4))
                        local.timeZoneID = remote["time_zone_id"] as? String ?? "Asia/Bangkok"
                        local.updatedAt = updatedAt
                        local.isSynced = true
                    }
                } else {
                    let branch = Branch(id: id, name: name, location: remote["location"] as? String, phone: remote["phone"] as? String, businessDayCutoffHour: Int(remoteDouble(remote["business_day_cutoff_hour"], fallback: 4)), timeZoneID: remote["time_zone_id"] as? String ?? "Asia/Bangkok", isSynced: true, updatedAt: updatedAt == .distantPast ? Date() : updatedAt)
                    modelContext.insert(branch)
                }
            }
            modelContext.saveWithLogging(label: #function)

            // Older installs can contain a real server branch and a second
            // placeholder "Main Branch" created locally during bootstrap. If
            // that placeholder became active before the branch pull, every
            // branch-scoped screen appears empty even though the merchant and
            // its data are unchanged. Prefer the non-placeholder sibling; the
            // exact fingerprint keeps genuine multi-branch stores untouched.
            let refreshedAfterPull = (try? modelContext.fetch(FetchDescriptor<Branch>())) ?? []
            if let activeId = BranchContext.shared.activeBranchID,
               let active = refreshedAfterPull.first(where: { $0.id == activeId && !$0.isDeleted }),
               active.name.caseInsensitiveCompare("Main Branch") == .orderedSame,
               active.location?.caseInsensitiveCompare("Headquarters") == .orderedSame,
               (active.phone ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let recovered = refreshedAfterPull.first(where: {
                   !$0.isDeleted
                       && $0.id != active.id
                       && $0.name.caseInsensitiveCompare(active.name) == .orderedSame
                       && ($0.location?.caseInsensitiveCompare("Headquarters") != .orderedSame
                           || !($0.phone ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
               }) {
                BranchContext.shared.select(recovered)
                #if DEBUG
                print("SyncEngine: replaced bootstrap placeholder branch with existing store branch \(recovered.id)")
                #endif
            }

            // New merchant workspaces may receive their first branch from the
            // server before a branch has ever been selected on this device.
            // Persist a valid fallback now so the branch-scoped pulls that run
            // immediately after this method do not fail with an empty UUID.
            let refreshedBranches = (try? modelContext.fetch(FetchDescriptor<Branch>())) ?? []
            let activeBranchId = BranchContext.shared.activeBranchIDString
            let hasValidActiveBranch = refreshedBranches.contains {
                !$0.isDeleted && $0.id.uuidString.caseInsensitiveCompare(activeBranchId) == .orderedSame
            }
            if !hasValidActiveBranch,
               let fallback = refreshedBranches
                .filter({ !$0.isDeleted })
                .sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
                .first {
                BranchContext.shared.select(fallback)
            }
        } catch {
            encounteredSyncError = true
            print("SyncEngine [Branch Pull Error]: \(error.localizedDescription)")
        }
    }

    func syncInventoryItems(_ modelContext: ModelContext) async {
        var descriptor = FetchDescriptor<InventoryItem>(
            predicate: #Predicate<InventoryItem> { $0.isSynced == false }
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

    @discardableResult
    func pullInventoryItemsFromSupabase(_ modelContext: ModelContext) async -> Bool {
        do {
            let remoteItems = try await NetworkManager.shared.fetchInventoryItemsFromSupabase()
            guard !remoteItems.isEmpty else { return true }
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
                    let remoteQty = remoteDouble(remote["current_quantity"])
                    guard updatedAt > local.updatedAt || !local.isSynced else { continue }
                    local.currentQuantity = remoteQty

                    local.name = name
                    local.sku = remote["sku"] as? String
                    local.unit = remote["unit"] as? String ?? local.unit
                    local.reorderLevel = remoteDouble(remote["reorder_level"])
                    local.costPrice = remoteDouble(remote["cost_price"])
                    local.outOfStockPolicyRaw = (remote["out_of_stock_policy"] as? String) ?? OutOfStockPolicy.allowNegative.rawValue
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
                        outOfStockPolicy: OutOfStockPolicy(rawValue: remote["out_of_stock_policy"] as? String ?? "") ?? .allowNegative,
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
            return true
        } catch {
            encounteredSyncError = true
            print("SyncEngine [InventoryItem Pull Error]: \(error.localizedDescription)")
            return false
        }
    }

    func syncModifierGroups(_ modelContext: ModelContext) async {
        var descriptor = FetchDescriptor<ModifierGroup>(
            predicate: #Predicate<ModifierGroup> { $0.isSynced == false }
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
                    let decision = shouldApplyRemoteUpdate(localIsSynced: local.isSynced, localUpdatedAt: local.updatedAt, remoteUpdatedAt: updatedAt)
                    guard decision == .applyRemote else { continue }
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
            predicate: #Predicate<Modifier> { $0.isSynced == false }
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
                    let decision = shouldApplyRemoteUpdate(localIsSynced: local.isSynced, localUpdatedAt: local.updatedAt, remoteUpdatedAt: updatedAt)
                    guard decision == .applyRemote else { continue }
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
            predicate: #Predicate<MenuItemModifierGroup> { $0.isSynced == false }
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
                    let decision = shouldApplyRemoteUpdate(localIsSynced: local.isSynced, localUpdatedAt: local.updatedAt, remoteUpdatedAt: updatedAt)
                    guard decision == .applyRemote else { continue }
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
                    branchId: txn.branch.id,
                    createdAt: txn.createdAt,
                    businessDateKey: txn.businessDateKey,
                    registerSessionId: txn.registerSessionId,
                    isDeleted: txn.isDeleted,
                    updatedAt: txn.updatedAt,
                    reasonCode: txn.reasonCode,
                    auditSignature: txn.auditSignature
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

    @discardableResult
    func pullInventoryTransactionsFromSupabase(_ modelContext: ModelContext) async -> Bool {
        do {
            let remoteTransactions = try await NetworkManager.shared.fetchInventoryTransactionsFromSupabase()
            guard !remoteTransactions.isEmpty else { return true }

            let localTransactions = (try? modelContext.fetch(FetchDescriptor<InventoryTransaction>())) ?? []
            let items = (try? modelContext.fetch(FetchDescriptor<InventoryItem>())) ?? []
            let branches = (try? modelContext.fetch(FetchDescriptor<Branch>())) ?? []
            var localById = Dictionary(uniqueKeysWithValues: localTransactions.map { ($0.id, $0) })
            let itemById = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
            let branchById = Dictionary(uniqueKeysWithValues: branches.map { ($0.id, $0) })

            for remote in remoteTransactions {
                guard let idString = remote["id"] as? String, let id = UUID(uuidString: idString) else { continue }
                let type = remote["transaction_type"] as? String ?? remote["type"] as? String ?? InventoryMovementType.adjust.rawValue
                let itemId = (remote["item_id"] as? String).flatMap(UUID.init(uuidString:))
                let branchId = (remote["branch_id"] as? String).flatMap(UUID.init(uuidString:))
                let referenceId = (remote["reference_id"] as? String).flatMap(UUID.init(uuidString:))
                let quantity = remoteDouble(remote["quantity"])
                let costPrice = remote["cost_price"].map { remoteDouble($0) }
                let createdAt = remoteDate(remote["created_at"], fallback: Date())
                let updatedAt = remoteDate(remote["updated_at"], fallback: createdAt)
                guard let transactionBranch = branchId.flatMap({ branchById[$0] }) else {
                    encounteredSyncError = true
                    continue
                }

                // Only business events with a stable reference may be matched
                // across different server/client movement IDs. Manual receives
                // and wastes commonly have a nil reference; matching those by
                // item + type would collapse multiple ledger rows into one.
                let referencedLocal = referenceId.flatMap { stableReference in
                    localTransactions.first {
                        InventoryTransactionIdentityPolicy.canMatchByReference(
                            remoteReferenceId: stableReference,
                            localReferenceId: $0.referenceId,
                            remoteItemId: itemId,
                            localItemId: $0.item?.id,
                            remoteType: type,
                            localType: $0.transactionType
                        )
                    }
                }
                let local = localById[id] ?? referencedLocal
                if let local {
                    local.item = itemId.flatMap { itemById[$0] }
                    local.branch = transactionBranch
                    local.transactionType = type
                    local.quantity = quantity
                    local.costPrice = costPrice
                    local.referenceId = referenceId
                    local.notes = remote["notes"] as? String
                    local.reasonCode = remote["reason_code"] as? String
                    local.auditSignature = remote["audit_signature"] as? String
                    local.createdAt = createdAt
                    local.businessDateKey = remote["business_date"] as? String ?? local.businessDateKey
                    local.registerSessionId = (remote["register_session_id"] as? String).flatMap(UUID.init(uuidString:))
                    local.updatedAt = updatedAt
                    local.isSynced = true
                    local.isDeleted = false
                } else {
                    let transaction = InventoryTransaction(
                        id: id,
                        item: itemId.flatMap { itemById[$0] },
                        transactionType: type,
                        quantity: quantity,
                        costPrice: costPrice,
                        referenceId: referenceId,
                        notes: remote["notes"] as? String,
                        branch: transactionBranch,
                        createdAt: createdAt,
                        businessDateKey: remote["business_date"] as? String ?? "",
                        registerSessionId: (remote["register_session_id"] as? String).flatMap(UUID.init(uuidString:)),
                        isSynced: true,
                        reasonCode: remote["reason_code"] as? String,
                        auditSignature: remote["audit_signature"] as? String
                    )
                    modelContext.insert(transaction)
                    localById[id] = transaction
                }
            }
            modelContext.saveWithLogging(label: #function)
            return true
        } catch {
            encounteredSyncError = true
            print("SyncEngine [InventoryTxn Pull Error]: \(error.localizedDescription)")
            return false
        }
    }

    /// Rebuilds local on-hand from movements accepted by the server.
    func reconcileInventoryFromLedger(_ modelContext: ModelContext) {
        let transactions = ((try? modelContext.fetch(FetchDescriptor<InventoryTransaction>())) ?? [])
            // Synced rows are the confirmed ledger; unsynced rows are the
            // device's pending offline delta and must remain visible locally.
            .filter { !$0.isDeleted }
        let grouped = Dictionary(grouping: transactions) { $0.item?.id }

        for (_, movements) in grouped {
            guard let item = movements.first?.item else { continue }
            item.currentQuantity = movements.reduce(0.0) { $0 + $1.quantity }
            item.isSynced = true
        }
        modelContext.saveWithLogging(label: #function)
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
                        item.isSynced = true
                        item.updatedAt = Date()
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
