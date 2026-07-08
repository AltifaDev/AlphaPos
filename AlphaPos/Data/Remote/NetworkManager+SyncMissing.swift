import Foundation
import SwiftData

// MARK: - Network Methods for Previously Missing Sync Models
// Covers: Expense, Supplier, TaxRate, Recipe, RestaurantWall,
//         ReceiptTemplate, TableLayoutPreset, CurrencyExchangeRate,
//         User, OrderItemModifier

extension NetworkManager {

    // MARK: - Generic Helpers (reuses fetchMasterData / softDeleteMasterData from +Financials)

    private func upsertMasterData(endpoint: String, payload: [String: Any]) async throws -> Bool {
        _ = try await sendSupabaseRequest(
            method: "POST",
            endpoint: endpoint,
            queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
            payload: payload
        )
        return true
    }

    // ─── Expense ────────────────────────────────────────────────────────

    func fetchExpensesFromSupabase() async throws -> [[String: Any]] {
        try await fetchMasterData(endpoint: "expenses")
    }

    func uploadExpense(_ expense: Expense) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        var payload: [String: Any] = [
            "id": expense.id.uuidString.lowercased(),
            "merchant_id": merchantId,
            "title": expense.title,
            "category": expense.category,
            "quantity": expense.quantity,
            "unit_price": expense.unitPrice,
            "amount": expense.amount,
            "vat_rate": expense.vatRate,
            "vat_amount": expense.vatAmount,
            "payment_method": expense.paymentMethod,
            "status": expense.status,
            "is_capex": expense.isCapEx,
            "date": NetworkManager.iso8601.string(from: expense.date),
            "is_deleted": expense.isDeleted,
            "updated_at": NetworkManager.iso8601.string(from: expense.updatedAt)
        ]
        if let invoiceNo = expense.invoiceNo { payload["invoice_no"] = invoiceNo }
        if let unit = expense.unit { payload["unit"] = unit }
        if let notes = expense.notes { payload["notes"] = notes }
        if let supplierId = expense.supplier?.id { payload["supplier_id"] = supplierId.uuidString.lowercased() }
        if let branchId = expense.branch?.id { payload["branch_id"] = branchId.uuidString.lowercased() }
        return try await upsertMasterData(endpoint: "expenses", payload: payload)
    }

    func deleteExpenseOnServer(id: UUID) async throws -> Bool {
        try await softDeleteMasterData(endpoint: "expenses", id: id)
    }

    // ─── Supplier ───────────────────────────────────────────────────────

    func fetchSuppliersFromSupabase() async throws -> [[String: Any]] {
        try await fetchMasterData(endpoint: "suppliers")
    }

    func uploadSupplier(_ supplier: Supplier) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        var payload: [String: Any] = [
            "id": supplier.id.uuidString.lowercased(),
            "merchant_id": merchantId,
            "name": supplier.name,
            "is_deleted": supplier.isDeleted,
            "updated_at": NetworkManager.iso8601.string(from: supplier.updatedAt)
        ]
        if let contactName = supplier.contactName { payload["contact_name"] = contactName }
        if let phone = supplier.phone { payload["phone"] = phone }
        if let email = supplier.email { payload["email"] = email }
        if let address = supplier.address { payload["address"] = address }
        return try await upsertMasterData(endpoint: "suppliers", payload: payload)
    }

    func deleteSupplierOnServer(id: UUID) async throws -> Bool {
        try await softDeleteMasterData(endpoint: "suppliers", id: id)
    }

    // ─── TaxRate ────────────────────────────────────────────────────────

    func fetchTaxRatesFromSupabase() async throws -> [[String: Any]] {
        try await fetchMasterData(endpoint: "tax_rates")
    }

    func uploadTaxRate(_ taxRate: TaxRate) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        let payload: [String: Any] = [
            "id": taxRate.id.uuidString.lowercased(),
            "merchant_id": merchantId,
            "name": taxRate.name,
            "rate_percentage": taxRate.ratePercentage,
            "tax_type": taxRate.taxType,
            "is_default": taxRate.isDefault,
            "is_active": taxRate.isActive,
            "is_deleted": taxRate.isDeleted,
            "updated_at": NetworkManager.iso8601.string(from: taxRate.updatedAt),
            "created_at": NetworkManager.iso8601.string(from: taxRate.createdAt)
        ]
        return try await upsertMasterData(endpoint: "tax_rates", payload: payload)
    }

    func deleteTaxRateOnServer(id: UUID) async throws -> Bool {
        try await softDeleteMasterData(endpoint: "tax_rates", id: id)
    }

    // ─── Recipe ─────────────────────────────────────────────────────────

    func fetchRecipesFromSupabase() async throws -> [[String: Any]] {
        try await fetchMasterData(endpoint: "recipes")
    }

    func uploadRecipe(_ recipe: Recipe) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        var payload: [String: Any] = [
            "id": recipe.id.uuidString.lowercased(),
            "merchant_id": merchantId,
            "quantity_required": recipe.quantityRequired,
            "is_deleted": recipe.isDeleted,
            "updated_at": NetworkManager.iso8601.string(from: recipe.updatedAt)
        ]
        if let menuItemId = recipe.menuItem?.id { payload["menu_item_id"] = menuItemId }
        if let inventoryItemId = recipe.inventoryItem?.id { payload["inventory_item_id"] = inventoryItemId.uuidString.lowercased() }
        return try await upsertMasterData(endpoint: "recipes", payload: payload)
    }

    func deleteRecipeOnServer(id: UUID) async throws -> Bool {
        try await softDeleteMasterData(endpoint: "recipes", id: id)
    }

    // ─── RestaurantWall ─────────────────────────────────────────────────

    func fetchRestaurantWallsFromSupabase() async throws -> [[String: Any]] {
        try await fetchMasterData(endpoint: "restaurant_walls")
    }

    func uploadRestaurantWall(_ wall: RestaurantWall) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        var payload: [String: Any] = [
            "id": wall.id.uuidString.lowercased(),
            "merchant_id": merchantId,
            "floor": wall.floor,
            "type": wall.typeString,
            "start_x": wall.startX,
            "start_y": wall.startY,
            "end_x": wall.endX,
            "end_y": wall.endY,
            "stroke_width": wall.strokeWidth,
            "is_deleted": wall.isDeleted,
            "updated_at": NetworkManager.iso8601.string(from: wall.updatedAt)
        ]
        if let cx = wall.controlX { payload["control_x"] = cx }
        if let cy = wall.controlY { payload["control_y"] = cy }
        return try await upsertMasterData(endpoint: "restaurant_walls", payload: payload)
    }

    func deleteRestaurantWallOnServer(id: UUID) async throws -> Bool {
        try await softDeleteMasterData(endpoint: "restaurant_walls", id: id)
    }

    // ─── ReceiptTemplate ────────────────────────────────────────────────

    func fetchReceiptTemplatesFromSupabase() async throws -> [[String: Any]] {
        try await fetchMasterData(endpoint: "receipt_templates")
    }

    func uploadReceiptTemplate(_ template: ReceiptTemplate) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        var payload: [String: Any] = [
            "id": template.id.uuidString.lowercased(),
            "merchant_id": merchantId,
            "name": template.name,
            "template_type": template.templateType,
            "show_tax_id": template.showTaxId,
            "show_customer_info": template.showCustomerInfo,
            "is_default": template.isDefault,
            "paper_width": template.paperWidth,
            "show_service_charge": template.showServiceCharge,
            "show_logo": template.showLogo,
            "show_table_info": template.showTableInfo,
            "show_qr_code": template.showQRCode,
            "show_item_modifiers": template.showItemModifiers,
            "show_order_type": template.showOrderType,
            "sticker_size": template.stickerSize,
            "is_deleted": template.isDeleted,
            "updated_at": NetworkManager.iso8601.string(from: template.updatedAt),
            "created_at": NetworkManager.iso8601.string(from: template.createdAt)
        ]
        if let headerText = template.headerText { payload["header_text"] = headerText }
        if let footerText = template.footerText { payload["footer_text"] = footerText }
        if let logoUrl = template.logoUrl { payload["logo_url"] = logoUrl }
        return try await upsertMasterData(endpoint: "receipt_templates", payload: payload)
    }

    func deleteReceiptTemplateOnServer(id: UUID) async throws -> Bool {
        try await softDeleteMasterData(endpoint: "receipt_templates", id: id)
    }

    // ─── TableLayoutPreset ──────────────────────────────────────────────

    func fetchTableLayoutPresetsFromSupabase() async throws -> [[String: Any]] {
        try await fetchMasterData(endpoint: "table_layout_presets")
    }

    func uploadTableLayoutPreset(_ preset: TableLayoutPreset) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        var payload: [String: Any] = [
            "id": preset.id.uuidString.lowercased(),
            "merchant_id": merchantId,
            "branch_id": preset.branchId,
            "floor": preset.floor,
            "name": preset.name,
            "bg_image_scale": preset.bgImageScale,
            "bg_image_offset_x": preset.bgImageOffsetX,
            "bg_image_offset_y": preset.bgImageOffsetY,
            "table_layout_json": preset.tableLayoutJson,
            "is_deleted": preset.isDeleted,
            "updated_at": NetworkManager.iso8601.string(from: preset.updatedAt)
        ]
        if let bgFilename = preset.bgImageFilename { payload["bg_image_filename"] = bgFilename }
        return try await upsertMasterData(endpoint: "table_layout_presets", payload: payload)
    }

    func deleteTableLayoutPresetOnServer(id: UUID) async throws -> Bool {
        try await softDeleteMasterData(endpoint: "table_layout_presets", id: id)
    }

    // ─── CurrencyExchangeRate ───────────────────────────────────────────

    func fetchCurrencyExchangeRatesFromSupabase() async throws -> [[String: Any]] {
        try await fetchMasterData(endpoint: "currency_exchange_rates")
    }

    func uploadCurrencyExchangeRate(_ rate: CurrencyExchangeRate) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        let payload: [String: Any] = [
            "id": rate.id.uuidString.lowercased(),
            "merchant_id": merchantId,
            "base_currency": rate.baseCurrency,
            "target_currency": rate.targetCurrency,
            "exchange_rate": rate.exchangeRate,
            "effective_date": NetworkManager.iso8601.string(from: rate.effectiveDate),
            "is_active": rate.isActive,
            "is_deleted": rate.isDeleted,
            "updated_at": NetworkManager.iso8601.string(from: rate.updatedAt),
            "created_at": NetworkManager.iso8601.string(from: rate.createdAt)
        ]
        return try await upsertMasterData(endpoint: "currency_exchange_rates", payload: payload)
    }

    func deleteCurrencyExchangeRateOnServer(id: UUID) async throws -> Bool {
        try await softDeleteMasterData(endpoint: "currency_exchange_rates", id: id)
    }

    // ─── Role ───────────────────────────────────────────────────────────

    func fetchRolesFromSupabase() async throws -> [[String: Any]] {
        try await fetchMasterData(endpoint: "roles")
    }

    func fetchRolePermissionsFromSupabase() async throws -> [[String: Any]] {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        let data = try await sendSupabaseRequest(
            method: "GET",
            endpoint: "role_permissions",
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

    func uploadRole(_ role: Role) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        let payload: [String: Any] = [
            "id": role.id.uuidString.lowercased(),
            "merchant_id": merchantId,
            "name": role.name,
            "description": role.roleDescription ?? "",
            "is_deleted": role.isDeleted,
            "updated_at": NetworkManager.iso8601.string(from: role.updatedAt)
        ]
        return try await upsertMasterData(endpoint: "roles", payload: payload)
    }

    func deleteRoleOnServer(id: UUID) async throws -> Bool {
        try await softDeleteMasterData(endpoint: "roles", id: id)
    }

    // ─── User ───────────────────────────────────────────────────────────

    func fetchUsersFromSupabase() async throws -> [[String: Any]] {
        try await fetchMasterData(endpoint: "users")
    }

    func uploadUser(_ user: User) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        var payload: [String: Any] = [
            "id": user.id.uuidString.lowercased(),
            "merchant_id": merchantId,
            "username": user.username,
            "password_hash": user.passwordHash,
            "is_active": user.isActive,
            "is_deleted": user.isDeleted,
            "updated_at": NetworkManager.iso8601.string(from: user.updatedAt)
        ]
        if let email = user.email { payload["email"] = email }
        if let pinHash = user.pinCodeHash { payload["pin_code_hash"] = pinHash }
        if let role = user.role {
            _ = try await uploadRole(role)
            payload["role_id"] = role.id.uuidString.lowercased()
        }
        return try await upsertMasterData(endpoint: "users", payload: payload)
    }

    func deleteUserOnServer(id: UUID) async throws -> Bool {
        try await softDeleteMasterData(endpoint: "users", id: id)
    }

    // ─── OrderItemModifier ──────────────────────────────────────────────

    func fetchOrderItemModifiersFromSupabase() async throws -> [[String: Any]] {
        try await fetchMasterData(endpoint: "order_item_modifiers")
    }

    func uploadOrderItemModifier(_ oim: OrderItemModifier) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        var payload: [String: Any] = [
            "id": oim.id.uuidString.lowercased(),
            "merchant_id": merchantId,
            "price": oim.price,
            "is_deleted": oim.isDeleted,
            "updated_at": NetworkManager.iso8601.string(from: oim.updatedAt)
        ]
        if let orderItemId = oim.orderItem?.id { payload["order_item_id"] = orderItemId.uuidString.lowercased() }
        if let modifierId = oim.modifier?.id { payload["modifier_id"] = modifierId.uuidString.lowercased() }
        return try await upsertMasterData(endpoint: "order_item_modifiers", payload: payload)
    }

    func deleteOrderItemModifierOnServer(id: UUID) async throws -> Bool {
        try await softDeleteMasterData(endpoint: "order_item_modifiers", id: id)
    }

    // ─── RefundTransaction delete (not in existing code) ────────────────

    func deleteRefundTransactionOnServer(id: UUID) async throws -> Bool {
        try await softDeleteMasterData(endpoint: "refund_transactions", id: id)
    }

    // ─── ShiftReport fetch & delete ─────────────────────────────────────

    func fetchShiftReportsFromSupabase() async throws -> [[String: Any]] {
        try await fetchMasterData(endpoint: "shift_reports")
    }

    func deleteShiftReportOnServer(id: UUID) async throws -> Bool {
        try await softDeleteMasterData(endpoint: "shift_reports", id: id)
    }
}
