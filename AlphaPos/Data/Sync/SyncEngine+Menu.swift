import Foundation
import SwiftData
import Combine
import UIKit
import os

// MARK: - Menu Pull, Purchase Orders, Delivery Prices, Customers
extension SyncEngine {
    // MARK: - Pull Menu Items from Supabase (Single Source of Truth)

    /// Fetches menu items from Supabase and upserts into SwiftData.
    /// This makes Supabase the single source of truth for the menu.
    /// Any item added/edited in Supabase will automatically appear in the iOS POS app.
    func pullMenuItemsFromSupabase(_ modelContext: ModelContext) async {
        do {
            let remoteItems = try await NetworkManager.shared.fetchMenuItemsFromSupabase()
            guard !remoteItems.isEmpty else { return }

            // Prefetch images in background to warm the cache
            prefetchImages(for: remoteItems)

            // Fetch existing local items and categories for O(1) lookup
            var __desclocalItems = FetchDescriptor<MenuItem>()
            __desclocalItems.fetchLimit = 500  // N3: prevent OOM
            let localItems = (try? modelContext.fetch(__desclocalItems)) ?? []
            var __desclocalCategories = FetchDescriptor<Category>()
            __desclocalCategories.fetchLimit = 500  // N3: prevent OOM
            let localCategories = (try? modelContext.fetch(__desclocalCategories)) ?? []

            var localItemsById: [String: MenuItem] = [:]
            for item in localItems {
                localItemsById[item.id.lowercased()] = item
            }

            var localCatsBySlug: [String: Category] = [:]
            for cat in localCategories {
                let slug = cat.name.lowercased()
                localCatsBySlug[slug] = cat
                // Also map common aliases
                if slug.contains("main") { localCatsBySlug["mains"] = cat }
                if slug.contains("appetizer") { localCatsBySlug["appetizers"] = cat }
                if slug.contains("beverage") || slug.contains("drink") {
                    localCatsBySlug["drinks"] = cat
                    localCatsBySlug["beverages"] = cat
                }
                if slug.contains("dessert") { localCatsBySlug["desserts"] = cat }
            }

            var didChange = false

            for remote in remoteItems {
                guard let name = remote["name"] as? String,
                      let price = remote["price"] as? Double,
                      let idString = remote["id"] as? String else { continue }

                let desc = remote["description"] as? String ?? ""
                let categorySlug = remote["category"] as? String ?? "mains"
                let imageUrl = remote["image_url"] as? String ?? ""
                let imageUrl2 = remote["image_url_2"] as? String ?? ""
                let imageUrl3 = remote["image_url_3"] as? String ?? ""
                let videoUrl = remote["video_url"] as? String ?? ""
                
                let nameTrans = remote["name_translations"] as? [String: String] ?? [:]
                let descTrans = remote["description_translations"] as? [String: String] ?? [:]
                
                let encoder = JSONEncoder()
                let nameTransJson = (try? String(data: encoder.encode(nameTrans), encoding: .utf8)) ?? "{}"
                let descTransJson = (try? String(data: encoder.encode(descTrans), encoding: .utf8)) ?? "{}"

                // Find or create local category
                let category: Category
                if let existingCat = localCatsBySlug[categorySlug] {
                    category = existingCat
                } else {
                    // Create a new local category for the slug
                    let catName: String
                    switch categorySlug {
                    case "mains": catName = "Main Dishes"
                    case "appetizers": catName = "Appetizers"
                    case "drinks": catName = "Beverages"
                    case "desserts": catName = "Desserts"
                    default: catName = categorySlug.capitalized
                    }
                    let newCat = Category(name: catName)
                    modelContext.insert(newCat)
                    localCatsBySlug[categorySlug] = newCat
                    category = newCat
                }

                if let existing = localItemsById[idString.lowercased()] {
                    // Update if name, price, description, imageUrl, or translations changed
                    var changed = false
                    if existing.name != name { existing.name = name; changed = true }
                    if abs((existing.price) - price) > 0.001 { existing.price = price; changed = true }
                    if (existing.itemDescription ?? "") != desc { existing.itemDescription = desc; changed = true }
                    if (existing.imageUrl ?? "") != imageUrl { existing.imageUrl = imageUrl; changed = true }
                    if (existing.imageUrl2 ?? "") != imageUrl2 { existing.imageUrl2 = imageUrl2; changed = true }
                    if (existing.imageUrl3 ?? "") != imageUrl3 { existing.imageUrl3 = imageUrl3; changed = true }
                    if (existing.videoUrl ?? "") != videoUrl { existing.videoUrl = videoUrl; changed = true }
                    if existing.nameTranslationsJson != nameTransJson { existing.nameTranslationsJson = nameTransJson; changed = true }
                    if existing.descriptionTranslationsJson != descTransJson { existing.descriptionTranslationsJson = descTransJson; changed = true }
                    if changed {
                        existing.isSynced = true
                        existing.updatedAt = Date()
                        didChange = true
                    }
                } else {
                    // Insert new item from Supabase
                    let newItem = MenuItem(
                        id: idString,
                        name: name,
                        itemDescription: desc.isEmpty ? nil : desc,
                        price: price,
                        imageUrl: imageUrl.isEmpty ? nil : imageUrl,
                        imageUrl2: imageUrl2.isEmpty ? nil : imageUrl2,
                        imageUrl3: imageUrl3.isEmpty ? nil : imageUrl3,
                        videoUrl: videoUrl.isEmpty ? nil : videoUrl,
                        category: category,
                        nameTranslationsJson: nameTransJson,
                        descriptionTranslationsJson: descTransJson
                    )
                    newItem.isSynced = true
                    modelContext.insert(newItem)
                    didChange = true
                }
            }

            // Reconcile hard-deletes made directly in Supabase.
            // Items no longer present remotely are purged from local SwiftData.
            let remoteIdSet = Set(remoteItems.compactMap { $0["id"] as? String }.map { $0.lowercased() })
            for local in localItems where local.isSynced && !local.isDeleted {
                if !remoteIdSet.contains(local.id.lowercased()) {
                    modelContext.delete(local)
                    didChange = true
                }
            }

            if didChange {
                try? modelContext.save()
                #if DEBUG
                print("SyncEngine [PullMenu]: Updated SwiftData from Supabase (\(remoteItems.count) items)")
                #endif
            }
        } catch {
            encounteredSyncError = true
            #if DEBUG
            print("SyncEngine [PullMenu]: Skipped (offline or error): \(error.localizedDescription)")
            #endif
        }
    }

    private func prefetchImages(for remoteItems: [[String: Any]]) {
        for remote in remoteItems {
            for key in ["image_url", "image_url_2", "image_url_3"] {
                if let urlStr = remote[key] as? String, !urlStr.isEmpty, let url = URL(string: urlStr) {
                    var request = URLRequest(url: url)
                    request.cachePolicy = .returnCacheDataElseLoad
                    URLSession.shared.dataTask(with: request).resume()
                }
            }
        }
    }

    // MARK: - Purchase Orders Sync

    /// Syncs unsynced PurchaseOrders to Supabase.
    /// Handles soft-delete: marks the PO and its items as deleted remotely, then purges locally.
    /// Items are uploaded inline — no separate sync pass needed for PurchaseOrderItem.
    func syncPurchaseOrders(_ modelContext: ModelContext) async {
        var descriptor = FetchDescriptor<PurchaseOrder>(
            predicate: #Predicate<PurchaseOrder> { $0.isSynced == false }
        )
        descriptor.fetchLimit = 500  // Prevent OOM on large datasets

        guard let purchaseOrders = try? modelContext.fetch(descriptor), !purchaseOrders.isEmpty else { return }

        for po in purchaseOrders {
            if po.isDeleted {
                do {
                    if try await NetworkManager.shared.deletePurchaseOrderOnServer(id: po.id) {
                        for item in po.items {
                            modelContext.delete(item)
                        }
                        modelContext.delete(po)
                        try modelContext.save()
                    } else {
                        encounteredSyncError = true
                    }
                } catch {
                    encounteredSyncError = true
                    print("SyncEngine [PurchaseOrder Delete Error]: \(error.localizedDescription)")
                }
                continue
            }

            do {
                let success = try await NetworkManager.shared.uploadPurchaseOrder(purchaseOrder: po)
                if success {
                    po.isSynced = true
                    po.updatedAt = Date()
                    // Mark items as synced too
                    for item in po.items {
                        item.isSynced = true
                        item.updatedAt = Date()
                    }
                    try modelContext.save()
                    #if DEBUG
                    print("SyncEngine [PurchaseOrder]: Synced PO \(po.poNumber) with \(po.items.count) item(s)")
                    #endif
                }
            } catch {
                encounteredSyncError = true
                print("SyncEngine [PurchaseOrder Sync Error]: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Delivery Prices Sync

    /// Syncs all DeliveryPrices for menu items that are already synced to Supabase.
    /// DeliveryPrice has no isSynced flag — all prices are batch-upserted on every cycle.
    /// This is safe because there are typically few delivery prices (max ~5 per menu item).
    func syncDeliveryPrices(_ modelContext: ModelContext) async {
        // Only sync delivery prices for menu items that are already on the server
        var descriptor = FetchDescriptor<MenuItem>(
            predicate: #Predicate<MenuItem> { $0.isSynced == true && $0.isDeleted == false }
        )
        descriptor.fetchLimit = 500  // Prevent OOM on large datasets

        guard let menuItems = try? modelContext.fetch(descriptor) else { return }

        let allPrices = menuItems.flatMap { $0.deliveryPrices }
        guard !allPrices.isEmpty else { return }

        do {
            _ = try await NetworkManager.shared.uploadDeliveryPrices(allPrices)
            #if DEBUG
            print("SyncEngine [DeliveryPrices]: Synced \(allPrices.count) delivery price(s)")
            #endif
        } catch {
            encounteredSyncError = true
            print("SyncEngine [DeliveryPrices Sync Error]: \(error.localizedDescription)")
        }
    }

    func syncPromotions(_ modelContext: ModelContext) async {
        var descriptor = FetchDescriptor<Promotion>(
            predicate: #Predicate<Promotion> { $0.isDeleted == true || $0.isSynced == false }
        )
        descriptor.fetchLimit = 500  // Prevent OOM on large datasets

        guard let promotions = try? modelContext.fetch(descriptor), !promotions.isEmpty else { return }

        for promotion in promotions {
            if promotion.isDeleted {
                do {
                    let success = try await NetworkManager.shared.deletePromotionOnServer(id: promotion.id)
                    if success {
                        modelContext.delete(promotion)
                        try modelContext.save()
                    }
                } catch {
                    encounteredSyncError = true
                    print("SyncEngine [Promotion Delete Error]: \(error.localizedDescription)")
                }
                continue
            }

            do {
                let success = try await NetworkManager.shared.uploadPromotion(promotion: promotion)
                if success {
                    _ = try await NetworkManager.shared.uploadPromotionBundleItems(for: promotion)
                    for bundleItem in promotion.bundleItems {
                        bundleItem.isSynced = true
                        bundleItem.updatedAt = Date()
                    }
                    promotion.isSynced = true
                    promotion.updatedAt = Date()
                    try modelContext.save()
                }
            } catch {
                encounteredSyncError = true
                print("SyncEngine [Promotion Sync Error]: \(error.localizedDescription)")
            }
        }
    }


    func pullPromotionsFromSupabase(_ modelContext: ModelContext) async {
        do {
            let remotePromos = try await NetworkManager.shared.fetchPromotionsFromSupabase()
            let remoteBundleItems = try await NetworkManager.shared.fetchPromotionBundleItemsFromSupabase()

            // Fetch ALL local promotions (including soft-deleted ones) so we can match by ID
            var __desclocalPromos = FetchDescriptor<Promotion>()
            __desclocalPromos.fetchLimit = 500  // N3: prevent OOM
            let localPromos = (try? modelContext.fetch(__desclocalPromos)) ?? []
            var __desclocalBundleItems = FetchDescriptor<PromotionBundleItem>()
            __desclocalBundleItems.fetchLimit = 500  // N3: prevent OOM
            let localBundleItems = (try? modelContext.fetch(__desclocalBundleItems)) ?? []
            var __desclocalMenuItems = FetchDescriptor<MenuItem>()
            __desclocalMenuItems.fetchLimit = 500  // N3: prevent OOM
            let localMenuItems = (try? modelContext.fetch(__desclocalMenuItems)) ?? []

            var localPromosById: [String: Promotion] = [:]
            for promo in localPromos {
                localPromosById[promo.id.uuidString.lowercased()] = promo
            }
            var localBundleItemsById: [String: PromotionBundleItem] = [:]
            for bundleItem in localBundleItems {
                localBundleItemsById[bundleItem.id.uuidString.lowercased()] = bundleItem
            }
            var localMenuItemsById: [String: MenuItem] = [:]
            for menuItem in localMenuItems {
                localMenuItemsById[menuItem.id.lowercased()] = menuItem
            }

            var didChange = false
            var remoteIds = Set<String>()

            for remote in remotePromos {
                guard let idStr = remote["id"] as? String,
                      let id = UUID(uuidString: idStr),
                      let title = remote["title"] as? String else { continue }
                remoteIds.insert(idStr.lowercased())

                let desc = remote["promo_description"] as? String
                let imageData = remote["image_data"] as? String
                let mediaType = remote["media_type"] as? String ?? "image"
                let discountType = remote["discount_type"] as? String ?? "none"
                let discountValue = remoteDouble(remote["discount_value"])
                let minimumSpend = remoteDouble(remote["minimum_spend"])
                let appliesToMenuItemId = (remote["applies_to_menu_item_id"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                let rewardMenuItemId = (remote["reward_menu_item_id"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                let requiredQuantity = max(1, remoteInt(remote["required_quantity"], fallback: 1))
                let rewardQuantity = max(0, remoteInt(remote["reward_quantity"], fallback: 0))
                let maxRedemptionsRaw = remoteInt(remote["max_redemptions"], fallback: -1)
                let maxRedemptions = maxRedemptionsRaw >= 0 ? maxRedemptionsRaw : nil
                let currentRedemptions = max(0, remoteInt(remote["current_redemptions"], fallback: 0))
                let perCustomerLimitRaw = remoteInt(remote["per_customer_limit"], fallback: -1)
                let perCustomerLimit = perCustomerLimitRaw >= 1 ? perCustomerLimitRaw : nil
                let startsAt = remoteDate(remote["starts_at"], fallback: .distantPast) == .distantPast ? nil : remoteDate(remote["starts_at"], fallback: .distantPast)
                let endsAt = remoteDate(remote["ends_at"], fallback: .distantPast) == .distantPast ? nil : remoteDate(remote["ends_at"], fallback: .distantPast)

                // Use existing remoteBool() helper instead of manual if/else chains
                let isActive = remoteBool(remote["is_active"], fallback: true)
                let isDeleted = remoteBool(remote["is_deleted"], fallback: false)

                let updatedAtStr = remote["updated_at"] as? String ?? ""
                let updatedAt = parseISO8601Date(updatedAtStr)

                if let existing = localPromosById[idStr.lowercased()] {
                    if isDeleted {
                        modelContext.delete(existing)
                        didChange = true
                    } else {
                        // If locally marked as deleted (pending push), DON'T overwrite with remote data
                        if existing.isDeleted {
                            // Skip — local deletion takes precedence; syncPromotions will push this
                            continue
                        }
                        // Only update if local record is already synced OR remote is newer
                        if existing.isSynced || updatedAt > existing.updatedAt {
                            var changed = false
                            if existing.title != title { existing.title = title; changed = true }
                            if existing.promoDescription != desc { existing.promoDescription = desc; changed = true }
                            if existing.imageData != imageData { existing.imageData = imageData; changed = true }
                            if existing.mediaType != mediaType { existing.mediaType = mediaType; changed = true }
                            if existing.isActive != isActive { existing.isActive = isActive; changed = true }
                            if existing.discountType != discountType { existing.discountType = discountType; changed = true }
                            if existing.discountValue != discountValue { existing.discountValue = discountValue; changed = true }
                            if existing.minimumSpend != minimumSpend { existing.minimumSpend = minimumSpend; changed = true }
                            if existing.appliesToMenuItemId != appliesToMenuItemId { existing.appliesToMenuItemId = appliesToMenuItemId; changed = true }
                            if existing.rewardMenuItemId != rewardMenuItemId { existing.rewardMenuItemId = rewardMenuItemId; changed = true }
                            if existing.requiredQuantity != requiredQuantity { existing.requiredQuantity = requiredQuantity; changed = true }
                            if existing.rewardQuantity != rewardQuantity { existing.rewardQuantity = rewardQuantity; changed = true }
                            if existing.maxRedemptions != maxRedemptions { existing.maxRedemptions = maxRedemptions; changed = true }
                            if existing.currentRedemptions != currentRedemptions { existing.currentRedemptions = currentRedemptions; changed = true }
                            if existing.perCustomerLimit != perCustomerLimit { existing.perCustomerLimit = perCustomerLimit; changed = true }
                            if existing.startsAt != startsAt { existing.startsAt = startsAt; changed = true }
                            if existing.endsAt != endsAt { existing.endsAt = endsAt; changed = true }
                            if changed {
                                existing.isSynced = true
                                existing.updatedAt = updatedAt
                                didChange = true
                            }
                        }
                    }
                } else if !isDeleted {
                    // No local copy found — insert from remote (only if it is not deleted)
                    let newPromo = Promotion(
                        id: id,
                        title: title,
                        promoDescription: desc,
                        imageData: imageData,
                        mediaType: mediaType,
                        isActive: isActive,
                        discountType: discountType,
                        discountValue: discountValue,
                        minimumSpend: minimumSpend,
                        appliesToMenuItemId: appliesToMenuItemId,
                        rewardMenuItemId: rewardMenuItemId,
                        requiredQuantity: requiredQuantity,
                        rewardQuantity: rewardQuantity,
                        startsAt: startsAt,
                        endsAt: endsAt,
                        maxRedemptions: maxRedemptions,
                        currentRedemptions: currentRedemptions,
                        perCustomerLimit: perCustomerLimit,
                        isSynced: true,
                        isDeleted: false,
                        updatedAt: updatedAt
                    )
                    modelContext.insert(newPromo)
                    didChange = true
                }
            }

            // Reconcile hard-deletes made directly in Supabase. If a clean local
            // promotion no longer exists remotely, purge the local cache too.
            for local in localPromos where local.isSynced && !local.isDeleted {
                if !remoteIds.contains(local.id.uuidString.lowercased()) {
                    modelContext.delete(local)
                    didChange = true
                }
            }

            let remoteBundleIds = reconcilePromotionBundleItems(
                remoteBundleItems,
                localBundleItemsById: localBundleItemsById,
                localPromosById: localPromosById,
                localMenuItemsById: localMenuItemsById,
                modelContext: modelContext
            )
            for localBundleItem in localBundleItems where localBundleItem.isSynced && !localBundleItem.isDeleted {
                if !remoteBundleIds.contains(localBundleItem.id.uuidString.lowercased()) {
                    modelContext.delete(localBundleItem)
                    didChange = true
                }
            }

            if didChange {
                try? modelContext.save()
                #if DEBUG
                print("SyncEngine [PullPromotions]: Updated SwiftData from Supabase (\(remotePromos.count) remote items)")
                #endif
            }
        } catch {
            encounteredSyncError = true
            #if DEBUG
            print("SyncEngine [PullPromotions]: Skipped or failed: \(error.localizedDescription)")
            #endif
        }
    }

    @discardableResult
    func reconcilePromotionBundleItems(
        _ remoteBundleItems: [[String: Any]],
        localBundleItemsById: [String: PromotionBundleItem],
        localPromosById: [String: Promotion],
        localMenuItemsById: [String: MenuItem],
        modelContext: ModelContext
    ) -> Set<String> {
        var remoteIds = Set<String>()

        for remote in remoteBundleItems {
            guard let idStr = remote["id"] as? String,
                  let id = UUID(uuidString: idStr),
                  let promotionIdStr = remote["promotion_id"] as? String,
                  let menuItemId = remote["menu_item_id"] as? String,
                  let promotion = localPromosById[promotionIdStr.lowercased()],
                  let menuItem = localMenuItemsById[menuItemId.lowercased()] else { continue }

            let normalizedId = idStr.lowercased()
            remoteIds.insert(normalizedId)

            let quantity = max(1, remoteInt(remote["quantity"], fallback: 1))
            let displayOrder = max(0, remoteInt(remote["display_order"], fallback: 0))
            let updatedAt = remoteDate(remote["updated_at"], fallback: Date())
            let isDeleted = remoteBool(remote["is_deleted"], fallback: false)

            if let existing = localBundleItemsById[normalizedId] {
                if isDeleted {
                    modelContext.delete(existing)
                    continue
                }

                if existing.isSynced || updatedAt > existing.updatedAt {
                    existing.promotion = promotion
                    existing.menuItem = menuItem
                    existing.quantity = quantity
                    existing.displayOrder = displayOrder
                    existing.isSynced = true
                    existing.isDeleted = false
                    existing.updatedAt = updatedAt
                }
            } else if !isDeleted {
                let newBundleItem = PromotionBundleItem(
                    id: id,
                    promotion: promotion,
                    menuItem: menuItem,
                    quantity: quantity,
                    displayOrder: displayOrder,
                    isSynced: true,
                    isDeleted: false,
                    updatedAt: updatedAt
                )
                modelContext.insert(newBundleItem)
            }
        }

        return remoteIds
    }

    func syncTables(_ modelContext: ModelContext) async {
        var descriptor = FetchDescriptor<RestaurantTable>(
            predicate: #Predicate<RestaurantTable> { $0.isSynced == false }
        )
        descriptor.fetchLimit = 500  // Prevent OOM on large datasets

        guard let tables = try? modelContext.fetch(descriptor), !tables.isEmpty else { return }

        for table in tables {
            do {
                let success = try await NetworkManager.shared.uploadRestaurantTable(table: table)
                if success {
                    if table.isDeleted {
                        modelContext.delete(table)
                    } else {
                        table.isSynced = true
                        table.updatedAt = Date()
                    }
                    try modelContext.save()
                }
            } catch {
                encounteredSyncError = true
                print("SyncEngine [Table Sync Error]: \(error.localizedDescription)")
            }
        }
    }

    func syncTableSessions(_ modelContext: ModelContext) async {


        var descriptor = FetchDescriptor<TableSession>(
            predicate: #Predicate<TableSession> { $0.isSynced == false }
        )
        descriptor.fetchLimit = 500  // Prevent OOM on large datasets

        guard let sessions = try? modelContext.fetch(descriptor), !sessions.isEmpty else { return }

        for session in sessions {
            do {
                if session.isDeleted {
                    do {
                        _ = try await NetworkManager.shared.deleteTableSession(id: session.id)
                        modelContext.delete(session)
                        try modelContext.save()
                    } catch {
                        encounteredSyncError = true
                        print("SyncEngine [TableSession Delete Error]: \(error.localizedDescription)")
                    }
                    continue
                }

                let success = try await NetworkManager.shared.uploadTableSession(session: session)
                if success {
                    session.isSynced = true
                    session.updatedAt = Date()
                    try modelContext.save()
                }
            } catch {
                encounteredSyncError = true
                print("SyncEngine [TableSession Sync Error]: \(error.localizedDescription)")
            }
        }
    }

}
