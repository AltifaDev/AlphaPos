import Foundation
import SwiftData

/// Banking-style local workspace isolation for multi-tenant devices.
///
/// Keeps one merchant's local workspace from being opened by another merchant.
/// Destructive removal is reserved for an explicit owner-authorized workflow;
/// authentication and upgrade recovery only quarantine the existing workspace.
enum TenantWorkspaceGuard {
    enum WorkspaceError: LocalizedError {
        case merchantSwitchRequiresExplicitRemoval

        var errorDescription: String? {
            if LocalizationManager.shared.currentLanguage == .thai {
                return "อุปกรณ์นี้มีข้อมูลภายในเครื่องของร้านอื่น กรุณาเข้าสู่ร้านเดิมและสำรองข้อมูลที่ตรวจสอบแล้วก่อนเปลี่ยนร้าน"
            }
            return "This device contains another store's local data. Sign back into that store and create a verified backup before switching stores."
        }
    }

    enum Reason: String {
        case merchantSwitch
        case logout
    }

    private static weak var modelContainer: ModelContainer?
    private static let lock = NSLock()

    /// Shown once after an automatic wipe so the owner understands why the store looks empty.
    static let wipeNoticeKey = "tenant_workspace_wipe_notice"
    static let lastWipedFromKey = "tenant_workspace_last_from"
    static let lastWipedToKey = "tenant_workspace_last_to"
    static let workspaceMerchantKey = "tenant_workspace_merchant_id"
    private static let installationMarkerKey = "alphapos_installation_marker_v1"
    private static let isolationSchemaKey = "tenant_isolation_schema_v1"

    /// Keys that must survive a tenant wipe.
    private static let preservedDefaultsKeys: Set<String> = [
        "app_language",
        "app_theme",
        RememberStorePreferences.enabledKey,
        RememberStorePreferences.emailKey,
        "dynamic_customer_web_url",
        "dynamic_supabase_url",
        "alphapos_auth_device_uuid", // physical device identity; server remints merchant binding if needed
        "TURNSTILE_SITE_KEY",
        "apns_device_token",
        wipeNoticeKey,
        lastWipedFromKey,
        lastWipedToKey,
        isolationSchemaKey,
        installationMarkerKey,
    ]

    /// Exact keys known to hold merchant-scoped cache.
    private static let merchantScopedExactKeys: [String] = [
        "active_merchant_id",
        workspaceMerchantKey,
        "logged_in_email",
        "logged_in_name",
        "active_branch_id",
        "offline_sync_mode",
        "offline_mode_user_set",
        "pending_merchant_onboarding",
        "sync_engine_last_synced_at",
        "did_backfill_accounting_ledger_v2",
        "did_backfill_business_context_v1",
        "did_backfill_inventory_txn_created_at_v1",
        "pending_inventory_focus_id",
        "pending_catalog_first_product",
        "pending_add_first_table",
        "delivery_fee_settings_dirty",
        "store_name",
        "store_phone",
        "store_website",
        "store_address",
        "store_tax_id",
        "store_email",
        "store_logo_url",
        "store_branch_code",
        "store_tax_rate",
        "store_tax_type",
        "store_service_charge_rate",
        "store_receipt_header",
        "store_receipt_footer",
        "promptpay_number",
        "kitchen_workflow_required",
        "enable_table_system",
        "enable_web_ordering",
        "alphapos_current_device_id",
    ]

    // Also wipe any per-merchant onboarding gate keys via prefix.
    // (handled in clearMerchantScopedDefaults via MerchantOnboardingGate.clearAll)

    private static let merchantScopedPrefixes: [String] = [
        "delivery_gp_",
        "delivery_adFee_",
        "delivery_adFeeIsPct_",
        "delivery_otherFee_",
        "floor_plan_",
        "table_layout_",
        "sync_",
        "merchant_onboarding_gate_",
        "store_setup_checklist_dismissed_",
        "store_setup_profile_skipped_",
    ]

    static func configure(container: ModelContainer) {
        lock.lock()
        modelContainer = container
        lock.unlock()
    }

    /// Keychain items can survive uninstall/reinstall while UserDefaults and
    /// SwiftData do not. A missing installation marker therefore means this
    /// installation must not trust any merchant credentials left in Keychain.
    static func handleFreshInstallIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: installationMarkerKey) == nil else { return }

        let previousMerchantId = KeychainManager.shared.retrieve(forKey: "alphapos_merchant_id")
        // A missing marker can also happen when an existing installation first
        // upgrades to a build that introduced this guard. SwiftData may therefore
        // contain the store's only offline copy and must never be erased here.
        // Preserve the merchant identity *before* logout clears Keychain. Without
        // this handoff, the guard sees anonymous local residue on the next login
        // and incorrectly rejects the original merchant as a different store.
        preserveWorkspaceBindingBeforeCredentialPurge(previousMerchantId)
        MerchantAuthManager.shared.logout(removeLocalData: false)
        RememberStorePreferences.applyAfterLogout()
        defaults.set(UUID().uuidString.lowercased(), forKey: installationMarkerKey)

        #if DEBUG
        print("TenantWorkspaceGuard: fresh install credentials purged (previousMerchant=\(previousMerchantId ?? "none"))")
        #endif
    }

    /// Bind the live local store to the merchant whose authenticated token was
    /// just persisted. This marker is required before dashboard or sync access.
    static func bindWorkspace(to merchantId: String) {
        let normalized = normalize(merchantId)
        guard !normalized.isEmpty else { return }
        UserDefaults.standard.set(normalized, forKey: workspaceMerchantKey)
    }

    /// Fail-closed tenant barrier shared by dashboard and every sync entry point.
    static var isAuthenticatedWorkspaceReady: Bool {
        guard MerchantAuthManager.shared.isAuthenticated,
              let credentialMerchant = MerchantAuthManager.shared.merchantId.map(normalize),
              let activeMerchant = UserDefaults.standard.string(forKey: "active_merchant_id").map(normalize),
              let workspaceMerchant = UserDefaults.standard.string(forKey: workspaceMerchantKey).map(normalize),
              !credentialMerchant.isEmpty,
              credentialMerchant == activeMerchant,
              activeMerchant == workspaceMerchant else {
            return false
        }
        return true
    }

    /// One-time upgrade repair: force re-authentication, but never erase the
    /// offline-first store. A merchant mismatch is handled after authentication;
    /// an upgrade itself is not authority to destroy unsynced business records.
    static func applySecurityUpgradeRepairIfNeeded() {
        if UserDefaults.standard.bool(forKey: isolationSchemaKey) { return }
        UserDefaults.standard.set(true, forKey: isolationSchemaKey)

        let previousMerchantId = KeychainManager.shared.retrieve(forKey: "alphapos_merchant_id")
        let hasMerchantSession =
            previousMerchantId != nil
            || KeychainManager.shared.retrieve(forKey: "alphapos_merchant_jwt") != nil
        guard hasMerchantSession else { return }

        #if DEBUG
        print("TenantWorkspaceGuard: applying one-time isolation upgrade repair (force re-login)")
        #endif
        preserveWorkspaceBindingBeforeCredentialPurge(previousMerchantId)
        MerchantAuthManager.shared.logout(removeLocalData: false)
    }

    /// Call after a successful token exchange and **before** persisting the new merchant id.
    /// Throws when an existing workspace must be handled explicitly by its owner.
    static func prepareForIncomingMerchant(
        _ incomingMerchantId: String,
        verifiedUserMerchantId: String? = nil
    ) throws {
        let incoming = normalize(incomingMerchantId)
        guard !incoming.isEmpty else { return }

        let previous = resolvePreviousMerchantId()
        let verified = normalize(verifiedUserMerchantId ?? "")
        #if DEBUG
        let active = normalize(UserDefaults.standard.string(forKey: "active_merchant_id") ?? "")
        let workspace = normalize(UserDefaults.standard.string(forKey: workspaceMerchantKey) ?? "")
        let keychain = normalize(KeychainManager.shared.retrieve(forKey: "alphapos_merchant_id") ?? "")
        print("TenantWorkspaceGuard: incoming=\(incoming) verified=\(verified) previous=\(previous) active=\(active) workspace=\(workspace) keychain=\(keychain)")
        #endif

        // Repair installations affected by the old fresh-install sequence. In
        // that sequence Keychain was cleared before its merchant id was handed
        // to the workspace marker, leaving real local data with no owner id.
        // The merchant claim from the freshly authenticated user session is
        // server-verified; use it only when no conflicting local identity exists.
        if previous.isEmpty, verified == incoming {
            UserDefaults.standard.set(incoming, forKey: workspaceMerchantKey)
            UserDefaults.standard.removeObject(forKey: wipeNoticeKey)
            UserDefaults.standard.removeObject(forKey: lastWipedFromKey)
            UserDefaults.standard.removeObject(forKey: lastWipedToKey)
            #if DEBUG
            print("TenantWorkspaceGuard: repaired orphaned workspace binding for verified merchant \(incoming)")
            #endif
            return
        }

        guard shouldWipe(previous: previous, incoming: incoming) else { return }

        // Never turn an authentication attempt into an implicit destructive
        // action. Keep the existing workspace quarantined until the operator
        // explicitly backs it up and removes it through a dedicated workflow.
        UserDefaults.standard.set(true, forKey: wipeNoticeKey)
        UserDefaults.standard.set(previous, forKey: lastWipedFromKey)
        UserDefaults.standard.set(incoming, forKey: lastWipedToKey)
        throw WorkspaceError.merchantSwitchRequiresExplicitRemoval
    }

    /// Owner logout / shared-device hygiene — always clear local tenant data.
    static func wipeOnLogout(previousMerchantId: String?) {
        let previous = normalize(previousMerchantId ?? resolvePreviousMerchantId())
        performOnMain {
            wipeLocalWorkspace(
                reason: .logout,
                previousMerchantId: previous,
                incomingMerchantId: ""
            )
        }
    }

    /// Returns and clears a one-shot user-facing notice after an automatic wipe.
    static var consumeWipeNoticeIfNeeded: String? {
        guard UserDefaults.standard.bool(forKey: wipeNoticeKey) else { return nil }
        UserDefaults.standard.set(false, forKey: wipeNoticeKey)
        let to = UserDefaults.standard.string(forKey: lastWipedToKey) ?? ""
        if to.isEmpty {
            return "tenant_wipe_notice_logout".t
        }
        return "tenant_wipe_notice_switch".t
    }

    // MARK: - Private

    private static func performOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    nonisolated private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func resolvePreviousMerchantId() -> String {
        // During an upgrade/re-login the Keychain credential may already have
        // been purged while the local workspace markers remain. Prefer the
        // marker that describes the local data, then the non-sensitive cache,
        // and only use Keychain as the final legacy fallback. Otherwise a
        // same-store login can be incorrectly classified as a merchant switch.
        if let workspace = UserDefaults.standard.string(forKey: workspaceMerchantKey),
           !normalize(workspace).isEmpty {
            return normalize(workspace)
        }
        if let defaults = UserDefaults.standard.string(forKey: "active_merchant_id"),
           !normalize(defaults).isEmpty {
            return normalize(defaults)
        }
        if let keychain = KeychainManager.shared.retrieve(forKey: "alphapos_merchant_id"),
           !normalize(keychain).isEmpty {
            return normalize(keychain)
        }
        return ""
    }

    /// Transfers the authenticated merchant identity into the local-workspace
    /// marker before a non-destructive credential purge. Existing bindings win:
    /// they describe the store on disk and must never be silently overwritten.
    private static func preserveWorkspaceBindingBeforeCredentialPurge(_ merchantId: String?) {
        let defaults = UserDefaults.standard
        let existingWorkspace = normalize(defaults.string(forKey: workspaceMerchantKey) ?? "")
        guard existingWorkspace.isEmpty else { return }

        let authenticatedMerchant = normalize(merchantId ?? "")
        let activeMerchant = normalize(defaults.string(forKey: "active_merchant_id") ?? "")
        let resolved = authenticatedMerchant.isEmpty ? activeMerchant : authenticatedMerchant
        guard !resolved.isEmpty else { return }

        defaults.set(resolved, forKey: workspaceMerchantKey)
        #if DEBUG
        print("TenantWorkspaceGuard: preserved workspace binding before credential purge (merchant=\(resolved))")
        #endif
    }

    private static func shouldWipe(previous: String, incoming: String) -> Bool {
        // Same merchant re-auth / token recovery — keep local workspace.
        if !previous.isEmpty && previous == incoming {
            return false
        }
        // Different merchant, or orphaned local session after partial logout.
        if !previous.isEmpty && previous != incoming {
            return true
        }
        // No previous identity, but merchant-scoped residue remains from older builds.
        return hasMerchantScopedResidue()
    }

    private static func hasMerchantScopedResidue() -> Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "offline_sync_mode") != nil { return true }
        if defaults.object(forKey: "pending_merchant_onboarding") != nil { return true }
        if defaults.object(forKey: "sync_engine_last_synced_at") != nil { return true }
        if let name = defaults.string(forKey: "store_name"), !name.isEmpty { return true }
        return false
    }

    private static func wipeLocalWorkspace(
        reason: Reason,
        previousMerchantId: String,
        incomingMerchantId: String
    ) {
        #if DEBUG
        print("TenantWorkspaceGuard: wipe reason=\(reason.rawValue) from=\(previousMerchantId) to=\(incomingMerchantId)")
        #endif

        // Stop sync so we never push previous-tenant rows after erase.
        NetworkManager.shared.simulateOffline = true
        SyncEngine.shared.cancelPendingSync()
        SyncEngine.shared.lastSyncedAt = nil

        lock.lock()
        let container = modelContainer
        lock.unlock()

        if let container {
            do {
                try deleteAllModels(in: container.mainContext)
            } catch {
                #if DEBUG
                print("TenantWorkspaceGuard: ModelContainer.erase failed — \(error)")
                #endif
            }
        } else {
            #if DEBUG
            print("TenantWorkspaceGuard: ModelContainer not configured — defaults-only wipe")
            #endif
        }

        clearMerchantScopedDefaults()

        // Owner PIN is device Keychain, not SwiftData — must clear on tenant change
        // so the next merchant cannot unlock with the previous owner's code.
        KeychainManager.shared.clearOwnerPin()
        MerchantOnboardingGate.clearAll()

        UserDefaults.standard.set(true, forKey: wipeNoticeKey)
        UserDefaults.standard.set(previousMerchantId, forKey: lastWipedFromKey)
        UserDefaults.standard.set(incomingMerchantId, forKey: lastWipedToKey)

        NotificationCenter.default.post(
            name: .tenantWorkspaceDidWipe,
            object: nil,
            userInfo: [
                "reason": reason.rawValue,
                "from": previousMerchantId,
                "to": incomingMerchantId,
            ]
        )
    }

    /// Clear rows without invalidating the live ModelContainer/ModelContext.
    /// `ModelContainer.erase()` makes SwiftUI's registered editor unusable.
    private static func deleteAllModels(in context: ModelContext) throws {
        // SwiftData batch deletion can nullify mandatory inverses before the
        // child batch has committed. Delete and save child groups first.
        try deleteRows(of: InventoryLotAllocation.self, in: context)
        try deleteRows(of: OrderItemModifier.self, in: context)
        try deleteRows(of: OrderTaxLine.self, in: context)
        try deleteRows(of: OrderDiscount.self, in: context)
        try deleteRows(of: Tip.self, in: context)
        try deleteRows(of: RefundTransaction.self, in: context)
        try deleteRows(of: Payment.self, in: context)
        try deleteRows(of: OrderItem.self, in: context)
        try deleteRows(of: Order.self, in: context)

        try deleteRows(of: TableSession.self, in: context)
        try deleteRows(of: RestaurantWall.self, in: context)
        try deleteRows(of: RestaurantTable.self, in: context)
        try deleteRows(of: FloorData.self, in: context)
        try deleteRows(of: WaitlistEntry.self, in: context)
        try deleteRows(of: FloorPlanImage.self, in: context)
        try deleteRows(of: TableLayoutPreset.self, in: context)

        try deleteRows(of: PromotionBundleItem.self, in: context)
        try deleteRows(of: MenuItemModifierGroup.self, in: context)
        try deleteRows(of: Recipe.self, in: context)
        try deleteRows(of: PrepProductionBatch.self, in: context)
        try deleteRows(of: PrepRecipeComponent.self, in: context)
        try deleteRows(of: PrepRecipe.self, in: context)
        try deleteRows(of: DeliveryPrice.self, in: context)
        try deleteRows(of: Modifier.self, in: context)
        try deleteRows(of: ModifierGroup.self, in: context)
        try deleteRows(of: Promotion.self, in: context)
        try deleteRows(of: MenuItem.self, in: context)
        try deleteRows(of: Category.self, in: context)

        try deleteRows(of: PurchaseOrderItem.self, in: context)
        try deleteRows(of: PurchaseOrder.self, in: context)
        try deleteRows(of: InventoryLot.self, in: context)
        try deleteRows(of: InventoryTransaction.self, in: context)
        try deleteRows(of: CycleCountSchedule.self, in: context)
        try deleteRows(of: InventoryItem.self, in: context)
        try deleteRows(of: Supplier.self, in: context)

        try deleteRows(of: EmployeeLeave.self, in: context)
        try deleteRows(of: Timecard.self, in: context)
        try deleteRows(of: EmployeeShift.self, in: context)
        try deleteRows(of: RegisterSession.self, in: context)
        try deleteRows(of: ShiftReport.self, in: context)
        try deleteRows(of: StaffSessionRecord.self, in: context)
        try deleteRows(of: Employee.self, in: context)
        try deleteRows(of: User.self, in: context)
        try deleteRows(of: Role.self, in: context)

        try deleteRows(of: LoyaltyTransaction.self, in: context)
        try deleteRows(of: GiftCard.self, in: context)
        try deleteRows(of: CashMovement.self, in: context)
        try deleteRows(of: Expense.self, in: context)
        try deleteRows(of: Customer.self, in: context)
        try deleteRows(of: PrintJobRecord.self, in: context)
        try deleteRows(of: PrintRoutingRule.self, in: context)
        try deleteRows(of: Printer.self, in: context)
        try deleteRows(of: ReceiptTemplate.self, in: context)
        try deleteRows(of: AuditLog.self, in: context)
        try deleteRows(of: SecurityPolicy.self, in: context)
        try deleteRows(of: MerchantDevice.self, in: context)
        try deleteRows(of: CurrencyExchangeRate.self, in: context)
        try deleteRows(of: TaxRate.self, in: context)
        try deleteRows(of: Branch.self, in: context)
    }

    private static func deleteRows<T: PersistentModel>(
        of type: T.Type,
        in context: ModelContext
    ) throws {
        let rows = try context.fetch(FetchDescriptor<T>())
        for row in rows {
            context.delete(row)
        }
        if context.hasChanges {
            try context.save()
        }
    }

    private static func clearMerchantScopedDefaults() {
        let defaults = UserDefaults.standard
        for key in merchantScopedExactKeys {
            defaults.removeObject(forKey: key)
        }

        let allKeys = Array(defaults.dictionaryRepresentation().keys)
        for key in allKeys {
            if preservedDefaultsKeys.contains(key) { continue }
            if merchantScopedExactKeys.contains(key) { continue }
            if merchantScopedPrefixes.contains(where: { key.hasPrefix($0) }) {
                defaults.removeObject(forKey: key)
            }
        }

        NetworkManager.shared.simulateOffline = false
    }
}

extension Notification.Name {
    static let tenantWorkspaceDidWipe = Notification.Name("alphapos.tenantWorkspaceDidWipe")
}
