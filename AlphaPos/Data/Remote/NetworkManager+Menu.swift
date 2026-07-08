import Foundation
import CryptoKit
import SwiftData

extension NetworkManager {
    // MARK: - Menu Items Sync

    func uploadProductMedia(
        _ data: Data,
        merchantId: String,
        itemId: String,
        fileName: String,
        contentType: String
    ) async throws -> String {
        // Refresh token if needed before uploading
        await MerchantAuthManager.shared.refreshTokenIfNeeded()

        let objectPath = "\(merchantId.lowercased())/\(itemId.lowercased())/\(fileName)"
        var uploadURL = config.supabaseURL
        for component in ["storage", "v1", "object", "product-media"] + objectPath.split(separator: "/").map(String.init) {
            uploadURL.appendPathComponent(component)
        }

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        let token = MerchantAuthManager.shared.currentToken ?? anonKey
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("true", forHTTPHeaderField: "x-upsert")
        request.httpBody = data
        request.timeoutInterval = 60

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.serverError("Invalid HTTP response")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: responseData, encoding: .utf8) ?? "Storage upload failed"
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 || message.contains("PGRST301") || message.contains("AccessDenied") || message.contains("violates row-level security") || message.contains("Unauthorized") {
                #if DEBUG
                print("NetworkManager: Detected authentication/RLS error during storage upload. Clearing token...")
                #endif
                MerchantAuthManager.shared.logout()
            }
            throw NetworkError.serverError(message)
        }

        var publicURL = config.supabaseURL
        for component in ["storage", "v1", "object", "public", "product-media"] + objectPath.split(separator: "/").map(String.init) {
            publicURL.appendPathComponent(component)
        }
        return publicURL.absoluteString
    }

    func uploadStoreLogo(
        _ data: Data,
        merchantId: String,
        contentType: String = "image/png"
    ) async throws -> String {
        await MerchantAuthManager.shared.refreshTokenIfNeeded()

        let objectPath = "\(merchantId.lowercased())/logo/store_logo.png"
        var uploadURL = config.supabaseURL
        for component in ["storage", "v1", "object", "product-media"] + objectPath.split(separator: "/").map(String.init) {
            uploadURL.appendPathComponent(component)
        }

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        let token = MerchantAuthManager.shared.currentToken ?? anonKey
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("true", forHTTPHeaderField: "x-upsert")
        request.httpBody = data
        request.timeoutInterval = 60

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.serverError("Invalid HTTP response")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: responseData, encoding: .utf8) ?? "Storage upload failed"
            throw NetworkError.serverError(message)
        }

        var publicURL = config.supabaseURL
        for component in ["storage", "v1", "object", "public", "product-media"] + objectPath.split(separator: "/").map(String.init) {
            publicURL.appendPathComponent(component)
        }
        return publicURL.absoluteString
    }

    /// Maps iPad Category display names to the lowercase category slugs used by the iPhone app and Supabase schema.
    private func categorySlug(from categoryName: String?) -> String {
        guard let name = categoryName?.lowercased() else { return "mains" }
        switch name {
        case let n where n.contains("appetizer"): return "appetizers"
        case let n where n.contains("main"), let n where n.contains("dish"): return "mains"
        case let n where n.contains("beverage"), let n where n.contains("drink"): return "drinks"
        case let n where n.contains("dessert"), let n where n.contains("sweet"): return "desserts"
        default: return "mains"
        }
    }

    /// Emoji mapping based on category for display on iPhone staff app.
    private func defaultEmoji(for categorySlug: String) -> String {
        switch categorySlug {
        case "appetizers": return "🥟"
        case "mains": return "🍛"
        case "drinks": return "🧋"
        case "desserts": return "🍨"
        default: return "🍽️"
        }
    }

    /// Upserts a single MenuItem from SwiftData to the Supabase `menu_items` table.
    func uploadMenuItem(item: MenuItem) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        let catSlug = categorySlug(from: item.category?.name)

        if let data = item.imageData {
            item.imageUrl = try await uploadProductMedia(data, merchantId: merchantId, itemId: item.id, fileName: "image-1.jpg", contentType: "image/jpeg")
        }
        if let data = item.imageData2 {
            item.imageUrl2 = try await uploadProductMedia(data, merchantId: merchantId, itemId: item.id, fileName: "image-2.jpg", contentType: "image/jpeg")
        }
        if let data = item.imageData3 {
            item.imageUrl3 = try await uploadProductMedia(data, merchantId: merchantId, itemId: item.id, fileName: "image-3.jpg", contentType: "image/jpeg")
        }
        if let data = item.videoData {
            item.videoUrl = try await uploadProductMedia(data, merchantId: merchantId, itemId: item.id, fileName: "video.mp4", contentType: "video/mp4")
        }

        let payload: [String: Any] = [
            "id": item.id.lowercased(),
            "name": item.name,
            "description": item.itemDescription ?? "",
            "price": item.price,
            "category": catSlug,
            "emoji": defaultEmoji(for: catSlug),
            "img_class": catSlug,
            "merchant_id": merchantId,
            "image_url": item.imageUrl ?? "",
            "image_url_2": item.imageUrl2 ?? "",
            "image_url_3": item.imageUrl3 ?? "",
            "video_url": item.videoUrl ?? "",
            "name_translations": item.nameTranslations,
            "description_translations": item.descriptionTranslations
        ]

        _ = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "menu_items",
            queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
            payload: payload
        )
        return true
    }

    /// Deletes a MenuItem from Supabase by its ID.
    func deleteMenuItemOnServer(id: String) async throws -> Bool {
        _ = try await sendSupabaseRequest(
            method: "DELETE",
            endpoint: "menu_items",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(id.lowercased())")]
        )
        return true
    }

    /// Fetches all menu items for the active merchant from Supabase.
    /// Returns an array of dictionaries with all menu item fields.
    func fetchMenuItemsFromSupabase() async throws -> [[String: Any]] {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        let data = try await sendSupabaseRequest(
            method: "GET",
            endpoint: "menu_items",
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)"),
                // is_deleted column does not exist on menu_items table — filter omitted
            ]
        )
        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw NetworkError.invalidResponse
        }
        return jsonArray
    }

    /// Fetches all promotions for the active merchant, including soft-deleted rows.
    /// Deleted rows are needed as tombstones so local caches can purge records
    /// when an admin changes the database directly.
    func fetchPromotionsFromSupabase() async throws -> [[String: Any]] {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        let data = try await sendSupabaseRequest(
            method: "GET",
            endpoint: "promotions",
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)")
            ]
        )
        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw NetworkError.invalidResponse
        }
        return jsonArray
    }

    func uploadPromotion(promotion: Promotion) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        var payload: [String: Any] = [
            "id": promotion.id.uuidString.lowercased(),
            "merchant_id": merchantId,
            "title": promotion.title,
            "promo_description": promotion.promoDescription ?? "",
            "image_data": promotion.imageData ?? "",
            "media_type": promotion.mediaType,
            "is_active": promotion.isActive ? 1 : 0,
            "discount_type": promotion.discountType,
            "discount_value": promotion.discountValue,
            "minimum_spend": promotion.minimumSpend,
            "applies_to_menu_item_id": promotion.appliesToMenuItemId.map { $0 as Any } ?? NSNull(),
            "reward_menu_item_id": promotion.rewardMenuItemId.map { $0 as Any } ?? NSNull(),
            "required_quantity": promotion.requiredQuantity,
            "reward_quantity": promotion.rewardQuantity,
            "max_redemptions": promotion.maxRedemptions.map { $0 as Any } ?? NSNull(),
            "current_redemptions": promotion.currentRedemptions,
            "per_customer_limit": promotion.perCustomerLimit.map { $0 as Any } ?? NSNull(),
            "is_deleted": promotion.isDeleted ? 1 : 0,
            "updated_at": NetworkManager.iso8601.string(from: promotion.updatedAt)
        ]
        if let startsAt = promotion.startsAt {
            payload["starts_at"] = NetworkManager.iso8601.string(from: startsAt)
        }
        if let endsAt = promotion.endsAt {
            payload["ends_at"] = NetworkManager.iso8601.string(from: endsAt)
        }

        var supabaseSuccess = false
        do {
            _ = try await sendSupabaseRequest(
                method: "POST",
                endpoint: "promotions",
                queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
                payload: payload
            )
            supabaseSuccess = true
        } catch {
            print("NetworkManager: Supabase promotion upload failed: \(error.localizedDescription)")
        }

        // Legacy local server call removed — Supabase is the single source of truth.
        // isSynced is only set true when Supabase succeeds.
        return supabaseSuccess
    }

    func uploadPromotionBundleItems(for promotion: Promotion) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId

        let payload: [[String: Any]] = promotion.bundleItems.compactMap { bundleItem in
            guard let menuItemId = bundleItem.menuItem?.id else { return nil }
            return [
                "id": bundleItem.id.uuidString.lowercased(),
                "merchant_id": merchantId,
                "promotion_id": promotion.id.uuidString.lowercased(),
                "menu_item_id": menuItemId,
                "quantity": bundleItem.quantity,
                "display_order": bundleItem.displayOrder,
                "is_synced": true,
                "is_deleted": bundleItem.isDeleted,
                "updated_at": NetworkManager.iso8601.string(from: bundleItem.updatedAt)
            ]
        }

        if !payload.isEmpty {
            _ = try await sendSupabaseRequest(
                method: "POST",
                endpoint: "promotion_bundle_items",
                queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
                payload: payload
            )
        }

        let activeBundleIds = promotion.bundleItems
            .filter { !$0.isDeleted }
            .map { $0.id.uuidString.lowercased() }

        let deletedPayload: [String: Any] = [
            "is_deleted": true,
            "updated_at": NetworkManager.iso8601.string(from: Date())
        ]

        var queryItems = [
            URLQueryItem(name: "promotion_id", value: "eq.\(promotion.id.uuidString.lowercased())"),
            URLQueryItem(name: "is_deleted", value: "eq.false")
        ]
        if !activeBundleIds.isEmpty {
            queryItems.append(URLQueryItem(name: "id", value: "not.in.(\(activeBundleIds.joined(separator: ",")))"))
        }

        _ = try await sendSupabaseRequest(
            method: "PATCH",
            endpoint: "promotion_bundle_items",
            queryItems: queryItems,
            payload: deletedPayload
        )

        return true
    }

    func fetchPromotionBundleItemsFromSupabase() async throws -> [[String: Any]] {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        let data = try await sendSupabaseRequest(
            method: "GET",
            endpoint: "promotion_bundle_items",
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)")
            ]
        )
        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw NetworkError.invalidResponse
        }
        return jsonArray
    }
}
