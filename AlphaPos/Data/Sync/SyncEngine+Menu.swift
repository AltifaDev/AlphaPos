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

            // Fetch existing local items and categories for O(1) lookup
            var __desclocalItems = FetchDescriptor<MenuItem>()
            __desclocalItems.fetchLimit = 500  // N3: prevent OOM
            let localItems = (try? modelContext.fetch(__desclocalItems)) ?? []
            var __desclocalCategories = FetchDescriptor<Category>()
            __desclocalCategories.fetchLimit = 500  // N3: prevent OOM
            let localCategories = (try? modelContext.fetch(__desclocalCategories)) ?? []

            // Deduplicate: If any local menu item has the same name but a different ID, delete it.
            for remote in remoteItems {
                guard let idString = remote["id"] as? String,
                      let name = remote["name"] as? String else { continue }
                if let conflict = localItems.first(where: { $0.id.lowercased() != idString.lowercased() && $0.name.lowercased() == name.lowercased() }) {
                    conflict.isDeleted = true
                    conflict.isSynced = true
                    conflict.updatedAt = Date()
                }
            }
            try? modelContext.save()

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
                if MenuItemSalesRole.inferred(from: cat.name) == .addOn { localCatsBySlug["addons"] = cat }
            }

            var didChange = false

            for remote in remoteItems {
                guard let name = remote["name"] as? String,
                      let price = remote["price"] as? Double,
                      let idString = remote["id"] as? String else { continue }

                let desc = remote["description"] as? String ?? ""
                let categorySlug = (remote["category"] as? String ?? "mains").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                let imageUrl = remote["image_url"] as? String ?? ""
                let imageUrl2 = remote["image_url_2"] as? String ?? ""
                let imageUrl3 = remote["image_url_3"] as? String ?? ""
                let videoUrl = remote["video_url"] as? String ?? ""
                let remoteSalesRole = MenuItemSalesRole(
                    rawValue: remote["sales_role"] as? String ?? MenuItemSalesRole.main.rawValue
                ) ?? .main
                let remoteSalesRoleConfirmed = remoteBool(remote["sales_role_confirmed"], fallback: false)

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
                    case "drinks", "beverages": catName = "Beverages"
                    case "desserts": catName = "Desserts"
                    case "addons": catName = "เพิ่มเติม"
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
                    if existing.isSynced, existing.salesRole != remoteSalesRole.rawValue {
                        existing.salesRole = remoteSalesRole.rawValue
                        changed = true
                    }
                    if existing.isSynced, existing.isSalesRoleConfirmed != remoteSalesRoleConfirmed {
                        existing.isSalesRoleConfirmed = remoteSalesRoleConfirmed
                        changed = true
                    }
                    let remoteAvailable = remoteBool(remote["is_available"], fallback: true)
                    // Prefer remote availability when local is already synced; keep local unsynced edits.
                    if existing.isSynced, existing.isAvailable != remoteAvailable {
                        existing.isAvailable = remoteAvailable
                        changed = true
                    }
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
                        isAvailable: remoteBool(remote["is_available"], fallback: true),
                        category: category,
                        nameTranslationsJson: nameTransJson,
                        descriptionTranslationsJson: descTransJson,
                        salesRole: remoteSalesRole.rawValue,
                        isSalesRoleConfirmed: remoteSalesRoleConfirmed
                    )
                    newItem.isSynced = true
                    modelContext.insert(newItem)
                    localItemsById[idString.lowercased()] = newItem
                    didChange = true
                }
            }

            // Delivery prices are part of the menu read model, so every POS uses
            // the same platform price instead of a device-local stale copy.
            let localPrices = (try? modelContext.fetch(FetchDescriptor<DeliveryPrice>())) ?? []
            var pricesById = Dictionary(uniqueKeysWithValues: localPrices.map { ($0.id, $0) })
            for remote in remoteItems {
                guard let menuId = remote["id"] as? String,
                      let menuItem = localItemsById[menuId.lowercased()] else { continue }
                let remotePrices = remote["delivery_prices"] as? [[String: Any]] ?? []
                let remoteIds = Set(remotePrices.compactMap { ($0["id"] as? String).flatMap(UUID.init(uuidString:)) })

                for value in remotePrices {
                    guard let idString = value["id"] as? String,
                          let id = UUID(uuidString: idString),
                          let brand = value["brand_name"] as? String else { continue }
                    let price = remoteDouble(value["price"])
                    if let existing = pricesById[id] {
                        existing.brandName = brand
                        existing.price = price
                        existing.menuItem = menuItem
                        existing.isDeleted = false
                        existing.isSynced = true
                    } else {
                        let newPrice = DeliveryPrice(id: id, brandName: brand, price: price, menuItem: menuItem, isSynced: true)
                        modelContext.insert(newPrice)
                        pricesById[id] = newPrice
                    }
                }

                for local in menuItem.deliveryPrices where !remoteIds.contains(local.id) {
                    local.isDeleted = true
                    local.isSynced = true
                }
            }

            // Reconcile hard-deletes made directly in Supabase.
            // Keep local tombstones so live SwiftUI/POS references are not invalidated.
            let remoteIdSet = Set(remoteItems.compactMap { $0["id"] as? String }.map { $0.lowercased() })
            for local in localItems where local.isSynced && !local.isDeleted {
                if !remoteIdSet.contains(local.id.lowercased()) {
                    local.isDeleted = true
                    local.isSynced = true
                    local.updatedAt = Date()
                    didChange = true
                }
            }

            // Prefetch images in background to populate URLCache
            prefetchImages(remoteItems)

            if didChange {
                modelContext.saveWithLogging(label: #function)
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

    private func prefetchImages(_ items: [[String: Any]]) {
        for item in items {
            guard let urlStr = item["image_url"] as? String, !urlStr.isEmpty, let url = URL(string: urlStr) else { continue }
            guard NetworkPolicy.shared.allows(.remoteMedia) else { continue }
            Task { _ = try? await AppNetworkTransport.data(from: url, purpose: .remoteMedia) }
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
                await NetworkManager.shared.recordSyncConflict(
                    entityType: "purchase_order", entityId: po.id,
                    expectedVersion: po.rowVersion, error: error
                )
                encounteredSyncError = true
                print("SyncEngine [PurchaseOrder Sync Error]: \(error.localizedDescription)")
            }
        }
    }

    /// Pulls branch-scoped PO headers and their lines, including tombstones.
    /// Header parents are merged first so line attachment never creates an
    /// orphan. Unsynced local edits retain ownership through the shared
    /// conflict policy instead of being silently overwritten.
    func pullPurchaseOrdersFromSupabase(_ modelContext: ModelContext) async {
        do {
            let remoteHeaders = try await NetworkManager.shared.fetchPurchaseOrdersFromSupabase()
            let remoteItems = try await NetworkManager.shared.fetchPurchaseOrderItemsFromSupabase()

            let localPOs = (try? modelContext.fetch(FetchDescriptor<PurchaseOrder>())) ?? []
            let localItems = (try? modelContext.fetch(FetchDescriptor<PurchaseOrderItem>())) ?? []
            let suppliers = (try? modelContext.fetch(FetchDescriptor<Supplier>())) ?? []
            let branches = (try? modelContext.fetch(FetchDescriptor<Branch>())) ?? []
            let inventoryItems = (try? modelContext.fetch(FetchDescriptor<InventoryItem>())) ?? []

            var poById = Dictionary(uniqueKeysWithValues: localPOs.map { ($0.id.uuidString.lowercased(), $0) })
            var itemById = Dictionary(uniqueKeysWithValues: localItems.map { ($0.id.uuidString.lowercased(), $0) })
            let supplierById = Dictionary(uniqueKeysWithValues: suppliers.map { ($0.id.uuidString.lowercased(), $0) })
            let branchById = Dictionary(uniqueKeysWithValues: branches.map { ($0.id.uuidString.lowercased(), $0) })
            let inventoryById = Dictionary(uniqueKeysWithValues: inventoryItems.map { ($0.id.uuidString.lowercased(), $0) })

            for remote in remoteHeaders {
                guard let idString = remote["id"] as? String,
                      let id = UUID(uuidString: idString) else { continue }
                let key = idString.lowercased()
                let updatedAt = remoteDate(remote["updated_at"], fallback: .distantPast)
                let isDeleted = remoteBool(remote["is_deleted"])

                if let local = poById[key] {
                    guard shouldApplyRemoteUpdate(
                        localIsSynced: local.isSynced,
                        localUpdatedAt: local.updatedAt,
                        remoteUpdatedAt: updatedAt
                    ) == .applyRemote else { continue }
                    if isDeleted {
                        modelContext.delete(local)
                        poById.removeValue(forKey: key)
                        continue
                    }
                    applyRemotePurchaseOrder(remote, to: local, supplierById: supplierById, branchById: branchById)
                    local.updatedAt = updatedAt
                    local.rowVersion = remoteInt(remote["row_version"])
                    local.isSynced = true
                    local.isDeleted = false
                } else if !isDeleted {
                    let po = PurchaseOrder(
                        id: id,
                        poNumber: remote["po_number"] as? String ?? "PO-\(id.uuidString.prefix(8))",
                        supplier: (remote["supplier_id"] as? String).flatMap { supplierById[$0.lowercased()] },
                        branch: (remote["branch_id"] as? String).flatMap { branchById[$0.lowercased()] },
                        status: remote["status"] as? String ?? "draft",
                        orderDate: remoteDate(remote["order_date"], fallback: Date()),
                        deliveryDate: remoteDateOptional(remote["delivery_date"]),
                        notes: remote["notes"] as? String,
                        isSynced: true,
                        isDeleted: false,
                        updatedAt: updatedAt == .distantPast ? Date() : updatedAt,
                        rowVersion: remoteInt(remote["row_version"])
                    )
                    applyRemotePurchaseOrder(remote, to: po, supplierById: supplierById, branchById: branchById)
                    modelContext.insert(po)
                    poById[key] = po
                }
            }

            for remote in remoteItems {
                guard let idString = remote["id"] as? String,
                      let id = UUID(uuidString: idString),
                      let poId = remote["purchase_order_id"] as? String,
                      let po = poById[poId.lowercased()] else { continue }
                let key = idString.lowercased()
                let updatedAt = remoteDate(remote["updated_at"], fallback: .distantPast)
                let isDeleted = remoteBool(remote["is_deleted"])

                if let local = itemById[key] {
                    guard shouldApplyRemoteUpdate(
                        localIsSynced: local.isSynced,
                        localUpdatedAt: local.updatedAt,
                        remoteUpdatedAt: updatedAt
                    ) == .applyRemote else { continue }
                    if isDeleted {
                        modelContext.delete(local)
                        itemById.removeValue(forKey: key)
                        continue
                    }
                    applyRemotePurchaseOrderItem(remote, to: local, po: po, inventoryById: inventoryById)
                    local.updatedAt = updatedAt
                    local.rowVersion = remoteInt(remote["row_version"])
                    local.isSynced = true
                    local.isDeleted = false
                } else if !isDeleted {
                    let line = PurchaseOrderItem(id: id, purchaseOrder: po, isSynced: true, updatedAt: updatedAt == .distantPast ? Date() : updatedAt, rowVersion: remoteInt(remote["row_version"]))
                    applyRemotePurchaseOrderItem(remote, to: line, po: po, inventoryById: inventoryById)
                    modelContext.insert(line)
                    itemById[key] = line
                }
            }
            modelContext.saveWithLogging(label: #function)
        } catch {
            reportSyncFailure("Purchase order pull: \(error.localizedDescription)", soft: true)
        }
    }

    private func applyRemotePurchaseOrder(
        _ remote: [String: Any],
        to po: PurchaseOrder,
        supplierById: [String: Supplier],
        branchById: [String: Branch]
    ) {
        po.poNumber = remote["po_number"] as? String ?? po.poNumber
        po.supplier = (remote["supplier_id"] as? String).flatMap { supplierById[$0.lowercased()] }
        po.branch = (remote["branch_id"] as? String).flatMap { branchById[$0.lowercased()] }
        po.status = remote["status"] as? String ?? po.status
        po.orderDate = remoteDate(remote["order_date"], fallback: po.orderDate)
        po.deliveryDate = remoteDateOptional(remote["delivery_date"])
        po.notes = remote["notes"] as? String
        po.documentType = remote["document_type"] as? String
        po.invoiceNumber = remote["invoice_number"] as? String
        po.taxInvoiceNumber = remote["tax_invoice_number"] as? String
        po.supplierNameRaw = remote["supplier_name_raw"] as? String
        po.supplierTaxId = remote["supplier_tax_id"] as? String
        po.supplierBranchCode = remote["supplier_branch_code"] as? String
        po.customerReference = remote["customer_reference"] as? String
        po.invoiceDate = remoteDateOptional(remote["invoice_date"], dateOnly: true)
        po.currencyCode = remote["currency_code"] as? String ?? "THB"
        po.subtotal = remoteOptionalDouble(remote["subtotal"])
        po.taxAmount = remoteOptionalDouble(remote["tax_amount"])
        po.grandTotal = remoteOptionalDouble(remote["grand_total"])
        po.extractionConfidence = remoteOptionalDouble(remote["extraction_confidence"])
        if let warnings = remote["validation_warnings"],
           JSONSerialization.isValidJSONObject(warnings),
           let data = try? JSONSerialization.data(withJSONObject: warnings) {
            po.validationWarningsJSON = String(data: data, encoding: .utf8)
        } else {
            po.validationWarningsJSON = remote["validation_warnings"] as? String
        }
        po.sourceDocumentHash = remote["source_document_hash"] as? String
    }

    private func applyRemotePurchaseOrderItem(
        _ remote: [String: Any],
        to item: PurchaseOrderItem,
        po: PurchaseOrder,
        inventoryById: [String: InventoryItem]
    ) {
        item.purchaseOrder = po
        item.inventoryItem = (remote["inventory_item_id"] as? String).flatMap { inventoryById[$0.lowercased()] }
        item.quantityOrdered = remoteDouble(remote["quantity_ordered"])
        item.quantityReceived = remoteDouble(remote["quantity_received"])
        item.unitCost = remoteDouble(remote["unit_cost"])
        item.lineNumber = remote["line_number"] as? String
        item.sourceItemName = remote["source_item_name"] as? String
        item.sellerItemId = remote["seller_item_id"] as? String
        item.barcode = remote["barcode"] as? String
        item.sourceUnit = remote["source_unit"] as? String
        item.unitCode = remote["unit_code"] as? String
        item.priceBaseQuantity = remoteDouble(remote["price_base_quantity"], fallback: 1)
        item.lineNetAmount = remoteOptionalDouble(remote["line_net_amount"])
        item.vatRate = remoteOptionalDouble(remote["vat_rate"])
        item.vatCode = remote["vat_code"] as? String
        item.taxAmount = remoteOptionalDouble(remote["tax_amount"])
        item.lineTotal = remoteOptionalDouble(remote["line_total"])
        item.lineConfidence = remoteOptionalDouble(remote["line_confidence"])
        item.expiryDate = remoteDateOptional(remote["expiry_date"], dateOnly: true)
        item.lotNumber = remote["lot_number"] as? String
    }

    private func remoteOptionalDouble(_ value: Any?) -> Double? {
        guard value != nil, !(value is NSNull) else { return nil }
        return remoteDouble(value)
    }

    private func remoteDateOptional(_ value: Any?, dateOnly: Bool = false) -> Date? {
        guard let value, !(value is NSNull) else { return nil }
        if let date = value as? Date { return date }
        guard let string = value as? String, !string.isEmpty else { return nil }
        if dateOnly, let date = NetworkManager.dateOnlyFormatter.date(from: string) { return date }
        let parsed = remoteDate(string, fallback: .distantPast)
        return parsed == .distantPast ? nil : parsed
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
            let deletedPrices = allPrices.filter(\.isDeleted)
            let activePrices = allPrices.filter { !$0.isDeleted }
            for deleted in deletedPrices {
                try await NetworkManager.shared.deleteDeliveryPriceOnServer(id: deleted.id)
                modelContext.delete(deleted)
            }
            _ = try await NetworkManager.shared.uploadDeliveryPrices(activePrices)
            try modelContext.save()
            #if DEBUG
            print("SyncEngine [DeliveryPrices]: Synced \(allPrices.count) delivery price(s)")
            #endif
        } catch {
            encounteredSyncError = true
            print("SyncEngine [DeliveryPrices Sync Error]: \(error.localizedDescription)")
        }
    }

    func syncPromotions(_ modelContext: ModelContext) async {
        guard !OfflineSyncModeController.isEnabled,
              !OfflineSyncModeController.isOfflineSubscriptionPlan else { return }
        var descriptor = FetchDescriptor<Promotion>(
            predicate: #Predicate<Promotion> { $0.isSynced == false && ($0.audience == "public" || $0.pendingWebRemoval) }
        )
        descriptor.fetchLimit = 500  // Prevent OOM on large datasets

        guard let promotions = try? modelContext.fetch(descriptor), !promotions.isEmpty else { return }

        // Ensure linked menu items exist remotely before promotion FK upsert.
        if promotions.contains(where: { $0.isPublicPromotion && !$0.isDeleted }) {
            await syncMenuItems(modelContext)
        }

        for promotion in promotions {
            // Withdraw a previously public row, but retain the private local definition.
            if !promotion.isPublicPromotion {
                if promotion.pendingWebRemoval {
                    do {
                        guard try await NetworkManager.shared.deletePromotionOnServer(id: promotion.id) else {
                            encounteredSyncError = true
                            continue
                        }
                        promotion.pendingWebRemoval = false
                        try modelContext.save()
                    } catch {
                        encounteredSyncError = true
                        continue
                    }
                }
                continue
            }
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
                let revision = promotion.updatedAt
                let mediaURL = try await NetworkManager.shared.uploadPromotion(promotion: promotion)
                guard promotion.isPublicPromotion, promotion.updatedAt == revision else { continue }
                _ = try await NetworkManager.shared.uploadPromotionBundleItems(for: promotion)
                guard promotion.isPublicPromotion, promotion.updatedAt == revision else { continue }
                for bundleItem in promotion.bundleItems {
                    bundleItem.isSynced = true
                    bundleItem.updatedAt = Date()
                }
                // Replace local base64 with Storage URL so other devices/web can load media.
                if !mediaURL.isEmpty {
                    promotion.imageData = mediaURL
                }
                promotion.isSynced = true
                promotion.updatedAt = Date()
                try modelContext.save()
            } catch {
                encounteredSyncError = true
                print("SyncEngine [Promotion Sync Error]: \(error.localizedDescription)")
            }
        }
    }


    func pullPromotionsFromSupabase(_ modelContext: ModelContext) async {
        guard !OfflineSyncModeController.isEnabled,
              !OfflineSyncModeController.isOfflineSubscriptionPlan else { return }
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
                    // Cloud rows/tombstones must never overwrite a locally private promotion.
                    guard existing.isPublicPromotion, existing.isSynced else { continue }
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
            for local in localPromos where local.isPublicPromotion && local.isSynced && !local.isDeleted {
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
            for localBundleItem in localBundleItems where localBundleItem.isSynced && !localBundleItem.isDeleted && localBundleItem.promotion?.isPublicPromotion == true {
                if !remoteBundleIds.contains(localBundleItem.id.uuidString.lowercased()) {
                    modelContext.delete(localBundleItem)
                    didChange = true
                }
            }

            if didChange {
                modelContext.saveWithLogging(label: #function)
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
                  let promotion = localPromosById[promotionIdStr.lowercased()], promotion.isPublicPromotion,
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

        // A stale duplicate must never revive a tombstone with the same table
        // number. Quarantine it into the same delete operation before upload.
        let deletedNumbers = Set(tables.filter(\.isDeleted).map {
            "\($0.branchId)|\($0.floorId?.uuidString ?? "")|\(canonicalTableNumber($0.tableNumber))"
        })
        for table in tables where !table.isDeleted
            && deletedNumbers.contains("\(table.branchId)|\(table.floorId?.uuidString ?? "")|\(canonicalTableNumber(table.tableNumber))") {
            table.isDeleted = true
            table.updatedAt = Date()
        }

        // Upload leaders / unjoined tables first so joined_parent_table_id FKs resolve.
        let orderedTables = tables.sorted { a, b in
            if a.isDeleted != b.isDeleted { return a.isDeleted && !b.isDeleted }
            let aIsChild = a.joinedParent != nil
            let bIsChild = b.joinedParent != nil
            if aIsChild != bIsChild { return !aIsChild && bIsChild }
            return false
        }

        for table in orderedTables {
            do {
                let success = try await NetworkManager.shared.uploadRestaurantTable(table: table)
                if success {
                    if table.isDeleted {
                        modelContext.delete(table)
                    } else {
                        // Keep clear/vacant dirty until inactive session uploads
                        // finish — otherwise pull resurrects remote occupied.
                        let hasUnsyncedSessionClose = table.sessions.contains {
                            !$0.isSynced && !$0.isActive && !$0.isDeleted
                        }
                        if table.status.lowercased() != "occupied" && hasUnsyncedSessionClose {
                            #if DEBUG
                            print("SyncEngine [Table Sync]: Deferred isSynced for \(table.tableNumber) — pending session close")
                            #endif
                        } else {
                            table.isSynced = true
                            table.updatedAt = Date()
                        }
                    }
                    try modelContext.save()
                }
            } catch {
                encounteredSyncError = true
                print("SyncEngine [Table Sync Error]: \(error.localizedDescription)")
            }
        }
    }

    enum TableSessionSyncPhase {
        case opening
        case closing
    }

    func syncTableSessions(
        _ modelContext: ModelContext,
        phase: TableSessionSyncPhase
    ) async {
        var descriptor = FetchDescriptor<TableSession>(
            predicate: #Predicate<TableSession> { $0.isSynced == false }
        )
        descriptor.fetchLimit = 500  // Prevent OOM on large datasets

        guard let unsyncedSessions = try? modelContext.fetch(descriptor) else { return }
        let sessions = unsyncedSessions.filter { session in
            switch phase {
            case .opening:
                return session.isActive && !session.isDeleted
            case .closing:
                return !session.isActive || session.isDeleted
            }
        }
        guard !sessions.isEmpty else { return }

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
                await NetworkManager.shared.recordSyncConflict(
                    entityType: "table_session", entityId: session.id,
                    expectedVersion: session.rowVersion, error: error
                )
                encounteredSyncError = true
                print("SyncEngine [TableSession Sync Error]: \(error.localizedDescription)")
            }
        }
    }

}
