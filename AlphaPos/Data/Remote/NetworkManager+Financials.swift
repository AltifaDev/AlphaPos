import Foundation
import CryptoKit
import SwiftData

extension NetworkManager {
    // MARK: - Order Discounts Sync
    func fetchOrderDiscountsFromSupabase() async throws -> [[String: Any]] {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        let data = try await sendSupabaseRequest(
            method: "GET",
            endpoint: "order_discounts",
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)"),
                URLQueryItem(name: "is_deleted", value: "eq.false")
            ]
        )
        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw NetworkError.invalidResponse
        }
        return jsonArray
    }

    func uploadOrderDiscount(_ discount: RemoteOrderDiscountUploadable) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId

        let orderId = discount.order?.id.uuidString.lowercased() ?? ""
        var payload: [String: Any] = [
            "id": discount.id.uuidString.lowercased(),
            "merchant_id": merchantId,
            "order_id": orderId,
            "discount_type": discount.discountType,
            "discount_value": discount.discountValue,
            "discount_amount": discount.discountAmount,
            "is_deleted": discount.isDeleted,
            "updated_at": NetworkManager.iso8601.string(from: discount.updatedAt)
        ]

        if let promoId = discount.promotion?.id.uuidString.lowercased() {
            payload["promotion_id"] = promoId
        }
        if let reason = discount.reason {
            payload["reason"] = reason
        }
        if let employeeId = discount.appliedByEmployeeId {
            payload["applied_by_employee_id"] = employeeId.uuidString.lowercased()
        }

        var supabaseSuccess = false
        do {
            _ = try await sendSupabaseRequest(
                method: "POST",
                endpoint: "order_discounts",
                queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
                payload: payload
            )
            supabaseSuccess = true
        } catch {
            print("NetworkManager: Supabase order discount upload failed: \(error.localizedDescription)")
        }
        return supabaseSuccess
    }

    func deleteOrderDiscountOnServer(id: UUID) async throws -> Bool {
        let idStr = id.uuidString.lowercased()
        let softDeletePayload: [String: Any] = [
            "is_deleted": true,
            "updated_at": NetworkManager.iso8601.string(from: Date())
        ]
        var supabaseSuccess = false
        do {
            _ = try await sendSupabaseRequest(
                method: "PATCH",
                endpoint: "order_discounts",
                queryItems: [URLQueryItem(name: "id", value: "eq.\(idStr)")],
                payload: softDeletePayload
            )
            supabaseSuccess = true
        } catch {
            print("NetworkManager: Supabase order discount soft-delete failed: \(error.localizedDescription)")
        }
        return supabaseSuccess
    }

    // MARK: - Order Tax Lines Sync
    func fetchOrderTaxLinesFromSupabase() async throws -> [[String: Any]] {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        let data = try await sendSupabaseRequest(
            method: "GET",
            endpoint: "order_tax_lines",
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)"),
                URLQueryItem(name: "is_deleted", value: "eq.false")
            ]
        )
        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw NetworkError.invalidResponse
        }
        return jsonArray
    }

    func uploadOrderTaxLine(_ taxLine: RemoteOrderTaxLineUploadable) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId

        let orderId = taxLine.order?.id.uuidString.lowercased() ?? ""
        var payload: [String: Any] = [
            "id": taxLine.id.uuidString.lowercased(),
            "merchant_id": merchantId,
            "order_id": orderId,
            "tax_name": taxLine.taxName,
            "tax_rate": taxLine.taxRate,
            "taxable_amount": taxLine.taxableAmount,
            "tax_amount": taxLine.taxAmount,
            "is_inclusive": taxLine.isInclusive,
            "is_deleted": taxLine.isDeleted,
            "updated_at": NetworkManager.iso8601.string(from: taxLine.updatedAt)
        ]

        if let jurisdiction = taxLine.jurisdiction {
            payload["jurisdiction"] = jurisdiction
        }

        var supabaseSuccess = false
        do {
            _ = try await sendSupabaseRequest(
                method: "POST",
                endpoint: "order_tax_lines",
                queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
                payload: payload
            )
            supabaseSuccess = true
        } catch {
            print("NetworkManager: Supabase order tax line upload failed: \(error.localizedDescription)")
        }
        return supabaseSuccess
    }

    func deleteOrderTaxLineOnServer(id: UUID) async throws -> Bool {
        let idStr = id.uuidString.lowercased()
        let softDeletePayload: [String: Any] = [
            "is_deleted": true,
            "updated_at": NetworkManager.iso8601.string(from: Date())
        ]
        var supabaseSuccess = false
        do {
            _ = try await sendSupabaseRequest(
                method: "PATCH",
                endpoint: "order_tax_lines",
                queryItems: [URLQueryItem(name: "id", value: "eq.\(idStr)")],
                payload: softDeletePayload
            )
            supabaseSuccess = true
        } catch {
            print("NetworkManager: Supabase order tax line soft-delete failed: \(error.localizedDescription)")
        }
        return supabaseSuccess
    }

    // MARK: - Tips Sync
    func fetchTipsFromSupabase() async throws -> [[String: Any]] {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        let data = try await sendSupabaseRequest(
            method: "GET",
            endpoint: "tips",
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)"),
                URLQueryItem(name: "is_deleted", value: "eq.false")
            ]
        )
        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw NetworkError.invalidResponse
        }
        return jsonArray
    }

    func uploadTip(_ tip: RemoteTipUploadable) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId

        let orderId = tip.order?.id.uuidString.lowercased() ?? ""
        var payload: [String: Any] = [
            "id": tip.id.uuidString.lowercased(),
            "merchant_id": merchantId,
            "order_id": orderId,
            "amount": tip.amount,
            "tip_type": tip.tipType,
            "is_deleted": tip.isDeleted,
            "updated_at": NetworkManager.iso8601.string(from: tip.updatedAt)
        ]

        if let paymentId = tip.payment?.id.uuidString.lowercased() {
            payload["payment_id"] = paymentId
        }
        if let employeeId = tip.employeeId {
            payload["employee_id"] = employeeId.uuidString.lowercased()
        }

        var supabaseSuccess = false
        do {
            _ = try await sendSupabaseRequest(
                method: "POST",
                endpoint: "tips",
                queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
                payload: payload
            )
            supabaseSuccess = true
        } catch {
            print("NetworkManager: Supabase tip upload failed: \(error.localizedDescription)")
        }
        return supabaseSuccess
    }

    func deleteTipOnServer(id: UUID) async throws -> Bool {
        let idStr = id.uuidString.lowercased()
        let softDeletePayload: [String: Any] = [
            "is_deleted": true,
            "updated_at": NetworkManager.iso8601.string(from: Date())
        ]
        var supabaseSuccess = false
        do {
            _ = try await sendSupabaseRequest(
                method: "PATCH",
                endpoint: "tips",
                queryItems: [URLQueryItem(name: "id", value: "eq.\(idStr)")],
                payload: softDeletePayload
            )
            supabaseSuccess = true
        } catch {
            print("NetworkManager: Supabase tip soft-delete failed: \(error.localizedDescription)")
        }
        return supabaseSuccess
    }

    // MARK: - Cash Movements Sync
    func fetchCashMovementsFromSupabase() async throws -> [[String: Any]] {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        let data = try await sendSupabaseRequest(
            method: "GET",
            endpoint: "cash_movements",
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)"),
                URLQueryItem(name: "is_deleted", value: "eq.false")
            ]
        )
        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw NetworkError.invalidResponse
        }
        return jsonArray
    }

    func uploadCashMovement(_ movement: RemoteCashMovementUploadable) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId

        let sessionId = movement.registerSession?.id.uuidString.lowercased() ?? ""
        var payload: [String: Any] = [
            "id": movement.id.uuidString.lowercased(),
            "merchant_id": merchantId,
            "register_session_id": sessionId,
            "movement_type": movement.movementType,
            "amount": movement.amount,
            "reason": movement.reason,
            "is_deleted": movement.isDeleted,
            "updated_at": NetworkManager.iso8601.string(from: movement.updatedAt)
        ]

        if let employeeId = movement.performedByEmployeeId {
            payload["performed_by_employee_id"] = employeeId.uuidString.lowercased()
        }

        var supabaseSuccess = false
        do {
            _ = try await sendSupabaseRequest(
                method: "POST",
                endpoint: "cash_movements",
                queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
                payload: payload
            )
            supabaseSuccess = true
        } catch {
            print("NetworkManager: Supabase cash movement upload failed: \(error.localizedDescription)")
        }
        return supabaseSuccess
    }

    func deleteCashMovementOnServer(id: UUID) async throws -> Bool {
        let idStr = id.uuidString.lowercased()
        let softDeletePayload: [String: Any] = [
            "is_deleted": true,
            "updated_at": NetworkManager.iso8601.string(from: Date())
        ]
        var supabaseSuccess = false
        do {
            _ = try await sendSupabaseRequest(
                method: "PATCH",
                endpoint: "cash_movements",
                queryItems: [URLQueryItem(name: "id", value: "eq.\(idStr)")],
                payload: softDeletePayload
            )
            supabaseSuccess = true
        } catch {
            print("NetworkManager: Supabase cash movement soft-delete failed: \(error.localizedDescription)")
        }
        return supabaseSuccess
    }

    // MARK: - Master Data Sync

    func fetchMasterData(endpoint: String) async throws -> [[String: Any]] {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        let data = try await sendSupabaseRequest(
            method: "GET",
            endpoint: endpoint,
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)"),
                URLQueryItem(name: "is_deleted", value: "eq.false")
            ]
        )
        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw NetworkError.invalidResponse
        }
        return jsonArray
    }

    func softDeleteMasterData(endpoint: String, id: UUID) async throws -> Bool {
        let payload: [String: Any] = [
            "is_deleted": true,
            "updated_at": NetworkManager.iso8601.string(from: Date())
        ]
        _ = try await sendSupabaseRequest(
            method: "PATCH",
            endpoint: endpoint,
            queryItems: [URLQueryItem(name: "id", value: "eq.\(id.uuidString.lowercased())")],
            payload: payload
        )
        return true
    }

    func fetchCategoriesFromSupabase() async throws -> [[String: Any]] {
        try await fetchMasterData(endpoint: "categories")
    }

    func uploadCategory(_ category: Category) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        var payload: [String: Any] = [
            "id": category.id.uuidString.lowercased(),
            "merchant_id": merchantId,
            "name": category.name,
            "is_deleted": category.isDeleted,
            "updated_at": NetworkManager.iso8601.string(from: category.updatedAt)
        ]
        if let description = category.categoryDescription {
            payload["description"] = description
        }
        if let imageUrl = category.imageUrl {
            payload["image_url"] = imageUrl
        }

        do {
            _ = try await sendSupabaseRequest(
                method: "POST",
                endpoint: "categories",
                queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
                payload: payload
            )
        } catch {
            if let description = payload.removeValue(forKey: "description") {
                payload["category_description"] = description
                _ = try await sendSupabaseRequest(
                    method: "POST",
                    endpoint: "categories",
                    queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
                    payload: payload
                )
            } else {
                throw error
            }
        }
        return true
    }

    func deleteCategoryOnServer(id: UUID) async throws -> Bool {
        try await softDeleteMasterData(endpoint: "categories", id: id)
    }
}
