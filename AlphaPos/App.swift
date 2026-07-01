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
            PrintRoutingRule.self, AuditLog.self, Customer.self,
            OrderDiscount.self, OrderTaxLine.self, Tip.self,
            RefundTransaction.self, CashMovement.self, LoyaltyTransaction.self,
            GiftCard.self, MerchantDevice.self, StaffSessionRecord.self,
            SecurityPolicy.self, FloorPlanImage.self, TableLayoutPreset.self,
            CurrencyExchangeRate.self, TaxRate.self, ShiftReport.self, ReceiptTemplate.self
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
            // Attempt recovery: remove only SwiftData store files, then retry.
            if let appSupportURL = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                let storeFiles = (try? fm.contentsOfDirectory(at: appSupportURL, includingPropertiesForKeys: nil)) ?? []
                let swiftDataExtensions = [".store", ".store-shm", ".store-wal",
                                           ".sqlite", ".sqlite-shm", ".sqlite-wal"]
                for file in storeFiles {
                    if swiftDataExtensions.contains(where: { file.lastPathComponent.hasSuffix($0) }) {
                        try? fm.removeItem(at: file)
                    }
                }
            }

            do {
                return try ModelContainer(
                    for: schema,
                    configurations: [modelConfiguration]
                )
            } catch {
                fatalError("Could not create ModelContainer after reset: \(error.localizedDescription)")
            }
        }
    }()

    // ── LocalizationManager: inject ทั่วทั้ง app ──────────────────────────
    // ใช้ @StateObject เพื่อให้ app-level re-render เมื่อภาษาเปลี่ยน
    @StateObject private var lm = LocalizationManager.shared

    init() {
        _ = SyncEngine.shared
        PrintService.shared.configure(modelContext: sharedModelContainer.mainContext)
        cleanupDuplicateSeedEmployees(sharedModelContainer.mainContext)
        
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

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .modelContainer(sharedModelContainer)
                .environmentObject(lm)
        }
    }
}
