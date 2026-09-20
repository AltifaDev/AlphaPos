import SwiftUI
import SwiftData
import Combine
import UIKit
import SQLite3

// MARK: - App Delegate
// หมายเหตุ: ไม่ใช้ Remote APNs Push — iPad AlphaPos ใช้ InAppNotificationManager แทน
// (ไม่ต้องการ Push Notifications capability ใน .entitlements)
// iPhone AlphaPosStaff ยังคงใช้ Native Push ตามปกติ
//
// Master iPad notifications are intentionally in-app only.
final class AlphaPosAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        return true
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        Task { @MainActor in
            _ = AuthDeepLinkCoordinator.shared.handle(url)
        }
        return url.scheme?.lowercased() == "alphapos"
    }

}

enum PersistentStoreMigrationRepair {
    /// Makes the standard manual staff discount available as soon as the app
    /// launches, including on stores upgraded from an earlier version.
    static func ensureEmployeePerItemPromotion(in container: ModelContainer) {
        let context = container.mainContext
        let migrationKey = "staff_fixed_per_item_promotion_v2"
        do {
            let promotions = try context.fetch(FetchDescriptor<Promotion>())
                .filter { !$0.isDeleted }
            if let existing = promotions.first(where: {
                $0.audience == "staff" && $0.discountType == "fixed_per_item"
            }) {
                // Upgrade only the built-in v1 promotion once. Later manager
                // edits remain untouched so the rule stays configurable.
                if !UserDefaults.standard.bool(forKey: migrationKey),
                   existing.minimumSpend == 0 {
                    existing.minimumSpend = 50
                    existing.updatedAt = Date()
                    existing.isSynced = false
                    try context.save()
                }
                UserDefaults.standard.set(true, forKey: migrationKey)
                return
            }

            let promotion = Promotion(
                title: "ส่วนลดพนักงาน ฿10 ต่อรายการ",
                promoDescription: "ลด 10 บาทต่อสินค้า 1 ชิ้นที่ราคามากกว่า 50 บาท เลือกใช้โดยพนักงานที่ POS",
                isActive: true,
                discountType: "fixed_per_item",
                discountValue: 10,
                minimumSpend: 50
            )
            promotion.audience = "staff"
            context.insert(promotion)
            try context.save()
            UserDefaults.standard.set(true, forKey: migrationKey)
        } catch {
            context.rollback()
            print("Staff promotion bootstrap failed: \(error.localizedDescription)")
        }
    }

    /// Establishes the local branch invariant before any screen or sync job can
    /// create operational data. This must live at app bootstrap (not in an
    /// inventory screen) because POS, payroll, tables, and background sync all
    /// need a valid branch even when Inventory has never been opened.
    static func ensureOperationalBranch(in container: ModelContainer) {
        let context = container.mainContext
        do {
            var branches = try context.fetch(FetchDescriptor<Branch>())
                .filter { !$0.isDeleted }

            // Online workspaces must pull their canonical branch from Supabase.
            // Creating a random local UUID here (before authentication and the
            // initial pull) used to produce duplicate "Main Branch" rows.
            if branches.isEmpty && OfflineSyncModeController.isOfflineSubscriptionPlan {
                let main = Branch(name: "Main Branch", location: "Headquarters")
                context.insert(main)
                try context.save()
                branches = [main]
            }

            guard !branches.isEmpty else { return }

            // BranchContext repairs a single-branch workspace automatically, but
            // deliberately requires an explicit choice when multiple branches make
            // ownership ambiguous.
            let selected: Branch
            do {
                guard let resolved = try BranchContext.shared.bootstrap(
                    in: context,
                    createDefaultIfEmpty: OfflineSyncModeController.isOfflineSubscriptionPlan
                ) else { return }
                selected = resolved
            } catch BranchContextError.selectionRequired {
                return
            }

            // A branchless row is unambiguous only in a single-branch workspace.
            // Repair it automatically there; never guess ownership across branches.
            guard branches.count == 1 else { return }

            var repaired = false
            for row in try context.fetch(FetchDescriptor<InventoryItem>()) where row.branch == nil {
                row.branch = selected
                row.isSynced = false
                row.updatedAt = Date()
                repaired = true
            }
            if repaired { try context.save() }
        } catch {
            // Preserve the store and retry next launch. Operational APIs fail
            // closed when this invariant cannot be established.
            context.rollback()
            print("Branch integrity bootstrap failed: \(error.localizedDescription)")
        }
    }

    /// Backfills the temporary optional `TableLayoutPreset.diningAreaId` field.
    /// A value is assigned only when existing data identifies exactly one area.
    @MainActor
    static func backfillTableLayoutPresetDiningAreas(in container: ModelContainer) {
        backfillTableLayoutPresetDiningAreas(in: container.mainContext)
    }

    /// This overload is also called after dining-area sync, because legacy
    /// stores may not have any FloorData rows yet when the app first launches.
    @MainActor
    static func backfillTableLayoutPresetDiningAreas(in context: ModelContext) {

        do {
            let presets = try context.fetch(FetchDescriptor<TableLayoutPreset>())
                .filter { $0.diningAreaId == nil }
            let floors = try context.fetch(FetchDescriptor<FloorData>())
                .filter { $0.isActive && !$0.isDeleted }
            let floorPlanImages = try context.fetch(FetchDescriptor<FloorPlanImage>())
                .filter { !$0.isDeleted }
            let restaurantTables = try context.fetch(FetchDescriptor<RestaurantTable>())
                .filter { !$0.isDeleted }

            var repairedCount = 0
            var repairedTableCount = 0
            for table in restaurantTables where table.branchId.isEmpty || table.floorId == nil {
                let candidates: [FloorData]
                if let floorId = table.floorId {
                    candidates = floors.filter { $0.uuid == floorId }
                } else {
                    candidates = floors.filter { $0.floorNumber == (table.floor ?? 1) }
                }
                guard candidates.count == 1, let area = candidates.first else { continue }
                table.floorId = area.uuid
                table.floor = area.floorNumber
                table.branchId = area.branchId
                table.isSynced = false
                table.updatedAt = Date()
                repairedTableCount += 1
            }
            for preset in presets {
                let matchingImages = floorPlanImages.filter { image in
                    image.branchId == preset.branchId &&
                    image.merchantId == preset.merchantId &&
                    preset.bgImageFilename != nil &&
                    image.imageFilename == preset.bgImageFilename
                }
                let imageAreaIDs = Set(matchingImages.map(\.diningAreaId))

                let branchAreaIDs = Set(
                    floors
                        .filter { $0.branchId == preset.branchId }
                        .map(\.uuid)
                )

                // Legacy presets retain stable table UUIDs in their JSON. Use
                // those IDs to recover the old floor number/floorId, then map
                // the floor number to the synced branch dining-area UUID.
                let layoutItems = (try? JSONDecoder().decode(
                    [TableLayoutItem].self,
                    from: Data(preset.tableLayoutJson.utf8)
                )) ?? []
                let layoutTableIDs = Set(layoutItems.map(\.id))
                let referencedTables = restaurantTables.filter {
                    layoutTableIDs.contains($0.id)
                }
                let referencedFloorIDs = Set(referencedTables.compactMap(\.floorId))
                let referencedFloorNumbers = Set(referencedTables.compactMap(\.floor))
                let tableDerivedAreaIDs: Set<UUID>
                if referencedFloorIDs.count == 1 {
                    tableDerivedAreaIDs = referencedFloorIDs
                } else if referencedFloorNumbers.count == 1,
                          let floorNumber = referencedFloorNumbers.first {
                    tableDerivedAreaIDs = Set(
                        floors
                            .filter {
                                $0.branchId == preset.branchId &&
                                $0.floorNumber == floorNumber
                            }
                            .map(\.uuid)
                    )
                } else {
                    tableDerivedAreaIDs = []
                }

                let resolvedID: UUID?
                if imageAreaIDs.count == 1 {
                    resolvedID = imageAreaIDs.first
                } else if tableDerivedAreaIDs.count == 1 {
                    resolvedID = tableDerivedAreaIDs.first
                } else if branchAreaIDs.count == 1 {
                    resolvedID = branchAreaIDs.first
                } else {
                    resolvedID = nil
                }

                if let resolvedID {
                    preset.diningAreaId = resolvedID
                    // Ensure the repaired scope is eventually persisted remotely.
                    preset.isSynced = false
                    preset.updatedAt = Date()
                    repairedCount += 1
                }
            }

            if repairedCount > 0 || repairedTableCount > 0 {
                try context.save()
            }
            let unresolvedCount = presets.count - repairedCount
            print("Migration repair: backfilled \(repairedCount) preset area(s), \(repairedTableCount) table scope(s); \(unresolvedCount) presets unresolved")
        } catch {
            // The store is already open. Preserve all rows and retry on next launch.
            context.rollback()
            print("Migration repair: TableLayoutPreset backfill failed: \(error.localizedDescription)")
        }
    }
}

@main
struct AlphaPosApp: App {
    @UIApplicationDelegateAdaptor(AlphaPosAppDelegate.self) private var appDelegate
    // Set up the SwiftData ModelContainer with versioned schema migration support.
    // AlphaPosMigrationPlan handles upgrading from V1 (OrderItem.order: Optional)
    // to V2 (OrderItem.order: required) by purging orphaned rows before schema upgrade.
    var sharedModelContainer: ModelContainer = {
        // A validated cloud restore is staged while the app is running, then
        // swapped here before SwiftData opens any SQLite connection.
        let didApplyCloudRestore = CloudBackupManager.applyPendingRestoreIfNeeded()
        let schema = Schema([
            Role.self, User.self, RestaurantTable.self, RestaurantWall.self,
            TableSession.self, Supplier.self, InventoryItem.self, Expense.self,
            InventoryTransaction.self, Category.self, MenuItem.self,
            DeliveryPrice.self, Recipe.self, PrepRecipe.self, PrepRecipeComponent.self,
            PrepProductionBatch.self, ModifierGroup.self,
            MenuItemModifierGroup.self, Modifier.self, Order.self,
            OrderItem.self, OrderItemModifier.self, Payment.self,
            CheckoutSession.self, PaymentAttempt.self, Employee.self,
            EmployeeShift.self, Timecard.self, RegisterSession.self,
            Branch.self, PurchaseOrder.self, PurchaseOrderItem.self,
            Promotion.self, PromotionBundleItem.self, Printer.self,
            PrintJobRecord.self, PrintRoutingRule.self, AuditLog.self, Customer.self,
            OrderDiscount.self, OrderTaxLine.self, Tip.self,
            RefundTransaction.self, CashMovement.self, LoyaltyTransaction.self,
            GiftCard.self, MerchantDevice.self, StaffSessionRecord.self,
            SecurityPolicy.self, FloorData.self, FloorPlanImage.self, TableLayoutPreset.self,
            CurrencyExchangeRate.self, TaxRate.self, ShiftReport.self, ReceiptTemplate.self,
            InventoryLot.self, InventoryLotAllocation.self,
            CycleCountSchedule.self, InventoryLotControl.self, InventoryRecall.self,
            InventoryRecallLot.self, IncomingInspection.self, TemperatureLog.self,
            InventoryCountSession.self, ItemUnitConversion.self,
            EmployeeLeave.self,
            WaitlistEntry.self,
            FinancialEvent.self, ShiftClosureSnapshot.self, DailySalesSnapshot.self
        ])

        // Locate default.store and run direct SQLite cleanup on orphaned OrderItems
        // before initializing ModelContainer, allowing safe automatic migration.
        let fm = FileManager.default
        if let appSupportURL = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            // Ensure the Application Support directory is created first on physical devices
            try? fm.createDirectory(at: appSupportURL, withIntermediateDirectories: true, attributes: nil)

            let storeURL = appSupportURL.appendingPathComponent("default.store")
            if fm.fileExists(atPath: storeURL.path) {
                var db: OpaquePointer?
                if sqlite3_open(storeURL.path, &db) == SQLITE_OK {
                    let deleteOrphanedItemsSQL = "DELETE FROM ZORDERITEM WHERE ZORDER IS NULL;"
                    let deleteOrphanedModifiersSQL = "DELETE FROM ZORDERITEMMODIFIER WHERE ZORDERITEM NOT IN (SELECT Z_PK FROM ZORDERITEM) AND ZORDERITEM IS NOT NULL;"
                    sqlite3_exec(db, deleteOrphanedItemsSQL, nil, nil, nil)
                    sqlite3_exec(db, deleteOrphanedModifiersSQL, nil, nil, nil)

                    // Required-branch schema preflight. Resolve legacy NULL foreign
                    // keys from the explicit device selection, or from the only live
                    // branch. Never choose an arbitrary branch in a multi-branch store.
                    let storedBranchHex: String = {
                        guard let uuid = UUID(uuidString: BranchContext.shared.activeBranchIDString) else { return "" }
                        var tuple = uuid.uuid
                        return withUnsafeBytes(of: &tuple) { bytes in
                            bytes.map { String(format: "%02X", $0) }.joined()
                        }
                    }()
                    let selectedBranchPK: String
                    if storedBranchHex.isEmpty {
                        selectedBranchPK = "(SELECT Z_PK FROM ZBRANCH WHERE ZISDELETED=0 AND (SELECT COUNT(*) FROM ZBRANCH WHERE ZISDELETED=0)=1 LIMIT 1)"
                    } else {
                        selectedBranchPK = "COALESCE((SELECT Z_PK FROM ZBRANCH WHERE ZISDELETED=0 AND hex(ZID)='\(storedBranchHex)' LIMIT 1),(SELECT Z_PK FROM ZBRANCH WHERE ZISDELETED=0 AND (SELECT COUNT(*) FROM ZBRANCH WHERE ZISDELETED=0)=1 LIMIT 1))"
                    }
                    for table in ["ZORDER", "ZREGISTERSESSION", "ZINVENTORYTRANSACTION"] {
                        sqlite3_exec(db, "UPDATE \(table) SET ZBRANCH=\(selectedBranchPK) WHERE ZBRANCH IS NULL;", nil, nil, nil)
                    }
                    sqlite3_close(db)
                }
            }
        }

        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            let container = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
            PersistentStoreMigrationRepair.ensureOperationalBranch(in: container)
            PersistentStoreMigrationRepair.backfillTableLayoutPresetDiningAreas(in: container)
            return container
        } catch {
            // A bad/incompatible snapshot must not brick the application. Put
            // the pre-restore store (including its WAL) back and retry once.
            if didApplyCloudRestore,
               CloudBackupManager.restorePreRestoreSafetyStore(),
               let recoveredContainer = try? ModelContainer(
                   for: schema,
                   configurations: [modelConfiguration]
               ) {
                UserDefaults.standard.set(
                    "Restore could not be opened and was rolled back: \(error.localizedDescription)",
                    forKey: "last_cloud_restore_error"
                )
                PersistentStoreMigrationRepair.ensureOperationalBranch(in: recoveredContainer)
                PersistentStoreMigrationRepair.backfillTableLayoutPresetDiningAreas(in: recoveredContainer)
                return recoveredContainer
            }
            // Never delete a POS store automatically: migration failure must preserve sales data.
            // A persistent-store migration error must not become a launch crash. Keep the
            // incompatible store untouched and let the app start with a temporary local
            // container; the normal sync path can then repopulate the workspace while the
            // original store remains available for manual recovery.
            UserDefaults.standard.set(
                "Persistent store was opened in recovery mode: \(error.localizedDescription)",
                forKey: "last_persistent_store_error"
            )
            do {
                let recoveryConfiguration = ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: true
                )
                let recoveryContainer = try ModelContainer(
                    for: schema,
                    configurations: [recoveryConfiguration]
                )
                print("AlphaPos: persistent store recovery mode enabled — \(error.localizedDescription)")
                return recoveryContainer
            } catch {
                // This should only be possible if the model schema itself is invalid.
                // Keep the diagnostic explicit instead of hiding the original failure.
                fatalError(
                    "AlphaPos model schema could not be initialized. Persistent store error: \(error.localizedDescription)"
                )
            }
        }
    }()

    // ── LocalizationManager: inject ทั่วทั้ง app ──────────────────────────
    // ใช้ @StateObject เพื่อให้ app-level re-render เมื่อภาษาเปลี่ยน
    @StateObject private var lm = LocalizationManager.shared

    init() {
        // Must run before AppConfig.shared / NetworkManager touch the API host.
        AppConfig.migrateSupabaseURLIfNeeded()

        if let customerHost = URL(string: UserDefaults.standard.string(forKey: "dynamic_customer_web_url") ?? "")?.host,
           customerHost != "sync.alphaposweb.com" {
            UserDefaults.standard.set("https://sync.alphaposweb.com", forKey: "dynamic_customer_web_url")
        }

        TenantWorkspaceGuard.configure(container: sharedModelContainer)
        TenantWorkspaceGuard.handleFreshInstallIfNeeded()
        TenantWorkspaceGuard.applySecurityUpgradeRepairIfNeeded()
        PersistentStoreMigrationRepair.ensureEmployeePerItemPromotion(in: sharedModelContainer)
        _ = SyncEngine.shared
        PrintService.shared.configure(modelContext: sharedModelContainer.mainContext)

        // Native URLCache setup for image caching (RAM 50MB, Disk 200MB)
        let imageCache = URLCache(
            memoryCapacity: 50 * 1024 * 1024,
            diskCapacity: 200 * 1024 * 1024,
            diskPath: "supabase_product_images"
        )
        URLCache.shared = imageCache
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .modelContainer(sharedModelContainer)
                .environmentObject(lm)
        }
    }
}
