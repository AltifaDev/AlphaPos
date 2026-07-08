import SwiftUI
import SwiftData
import Combine
import UIKit
import UserNotifications
import SQLite3

// MARK: - App Delegate
// หมายเหตุ: ไม่ใช้ Remote APNs Push — iPad AlphaPos ใช้ InAppNotificationManager แทน
// (ไม่ต้องการ Push Notifications capability ใน .entitlements)
// iPhone AlphaPosStaff ยังคงใช้ Native Push ตามปกติ
//
// Local Notification (UNUserNotificationCenter) ใช้สำหรับ background notification
// ไม่ใช่ Remote Push — ไม่ต้องการ Push Notifications capability เพิ่มเติม
final class AlphaPosAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // ขอสิทธิ์ Local Notification (alert + sound + badge)
        // ไม่ต้องการ Push Notifications capability — เป็นแค่ local notification
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            #if DEBUG
            if granted {
                print("AlphaPos: Local notification permission granted")
            } else {
                print("AlphaPos: Local notification permission denied — \(error?.localizedDescription ?? "unknown")")
            }
            #endif
        }
        return true
    }

    // Foreground: suppress system banner — InAppNotificationManager banner ทำงานแทน
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([]) // ซ่อน system banner ตอน foreground
    }

    // User tap notification ตอน background → แอปเปิดขึ้นมา
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }
}

@main
struct AlphaPosApp: App {
    @UIApplicationDelegateAdaptor(AlphaPosAppDelegate.self) private var appDelegate
    // Set up the SwiftData ModelContainer with versioned schema migration support.
    // AlphaPosMigrationPlan handles upgrading from V1 (OrderItem.order: Optional)
    // to V2 (OrderItem.order: required) by purging orphaned rows before schema upgrade.
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Role.self, User.self, RestaurantTable.self, RestaurantWall.self,
            TableSession.self, Supplier.self, InventoryItem.self, Expense.self,
            InventoryTransaction.self, Category.self, MenuItem.self,
            DeliveryPrice.self, Recipe.self, ModifierGroup.self,
            MenuItemModifierGroup.self, Modifier.self, Order.self,
            OrderItem.self, OrderItemModifier.self, Payment.self, Employee.self,
            EmployeeShift.self, Timecard.self, RegisterSession.self,
            Branch.self, PurchaseOrder.self, PurchaseOrderItem.self,
            Promotion.self, PromotionBundleItem.self, Printer.self,
            PrintJobRecord.self, PrintRoutingRule.self, AuditLog.self, Customer.self,
            OrderDiscount.self, OrderTaxLine.self, Tip.self,
            RefundTransaction.self, CashMovement.self, LoyaltyTransaction.self,
            GiftCard.self, MerchantDevice.self, StaffSessionRecord.self,
            SecurityPolicy.self, FloorPlanImage.self, TableLayoutPreset.self,
            CurrencyExchangeRate.self, TaxRate.self, ShiftReport.self, ReceiptTemplate.self,
            InventoryLot.self,
            EmployeeLeave.self,
            WaitlistEntry.self
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
                    sqlite3_close(db)
                }
            }
        }

        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            return try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            // Never delete a POS store automatically: migration failure must preserve sales data.
            fatalError("Persistent store migration failed; local data was preserved: \(error.localizedDescription)")
        }
    }()

    // ── LocalizationManager: inject ทั่วทั้ง app ──────────────────────────
    // ใช้ @StateObject เพื่อให้ app-level re-render เมื่อภาษาเปลี่ยน
    @StateObject private var lm = LocalizationManager.shared

    init() {
        _ = SyncEngine.shared
        PrintService.shared.configure(modelContext: sharedModelContainer.mainContext)
        cleanupDuplicateSeedEmployees(sharedModelContainer.mainContext)
        cleanupDuplicateCategoriesAndBranchlessItems(sharedModelContainer.mainContext)

        // Native URLCache setup for image caching (RAM 50MB, Disk 200MB)
        let imageCache = URLCache(
            memoryCapacity: 50 * 1024 * 1024,
            diskCapacity: 200 * 1024 * 1024,
            diskPath: "supabase_product_images"
        )
        URLCache.shared = imageCache
    }

    private func cleanupDuplicateSeedEmployees(_ modelContext: ModelContext) {
        let mockEmpIds = [
            UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        ]
        for id in mockEmpIds {
            let descriptor = FetchDescriptor<Employee>(
                predicate: #Predicate<Employee> { $0.id == id }
            )
            if let matches = try? modelContext.fetch(descriptor), !matches.isEmpty {
                for emp in matches {
                    if let user = emp.user {
                        modelContext.delete(user)
                    }
                    modelContext.delete(emp)
                }
                #if DEBUG
                print("AlphaPos: Cleaned up duplicate mock employee \(id)")
                #endif
            }
        }
        modelContext.saveWithLogging(label: #function)
    }

    private func cleanupDuplicateCategoriesAndBranchlessItems(_ modelContext: ModelContext) {
        // 1. Link branchless inventory items to Main Branch
        let branchDesc = FetchDescriptor<Branch>()
        let branches = (try? modelContext.fetch(branchDesc)) ?? []
        let mainBranch: Branch
        if let first = branches.first {
            mainBranch = first
        } else {
            mainBranch = Branch(name: "Main Branch", location: "Headquarters", phone: "02-123-4567")
            modelContext.insert(mainBranch)
        }

        let itemDesc = FetchDescriptor<InventoryItem>()
        if let items = try? modelContext.fetch(itemDesc) {
            var itemsUpdated = 0
            for item in items {
                if item.branch == nil {
                    item.branch = mainBranch
                    itemsUpdated += 1
                }
            }
            if itemsUpdated > 0 {
                #if DEBUG
                print("AppInit [Cleanup]: Linked \(itemsUpdated) branchless inventory item(s) to Main Branch.")
                #endif
            }
        }

        // 2. Clean up duplicate categories
        let categoryDesc = FetchDescriptor<Category>()
        if let categories = try? modelContext.fetch(categoryDesc) {
            var seenNames: [String: Category] = [:]
            var categoriesDeleted = 0
            for cat in categories {
                let nameKey = cat.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if let existing = seenNames[nameKey] {
                    // Re-link its menu items to the existing category, then delete it.
                    for item in cat.menuItems {
                        item.category = existing
                        item.isSynced = false
                    }
                    cat.menuItems.removeAll()
                    modelContext.delete(cat)
                    categoriesDeleted += 1
                } else {
                    seenNames[nameKey] = cat
                }
            }
            if categoriesDeleted > 0 {
                #if DEBUG
                print("AppInit [Cleanup]: Merged and deleted \(categoriesDeleted) duplicate category record(s).")
                #endif
            }
        }

        try? modelContext.save()
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .modelContainer(sharedModelContainer)
                .environmentObject(lm)
        }
    }
}
