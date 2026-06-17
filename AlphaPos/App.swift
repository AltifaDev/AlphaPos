import SwiftUI
import SwiftData
import Combine

@main
struct AlphaPosApp: App {
    // Set up the SwiftData ModelContainer with all custom models
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Role.self,
            User.self,
            RestaurantTable.self,
            RestaurantWall.self,
            TableSession.self,
            Supplier.self,
            InventoryItem.self,
            InventoryTransaction.self,
            Category.self,
            MenuItem.self,
            DeliveryPrice.self,
            Recipe.self,
            ModifierGroup.self,
            MenuItemModifierGroup.self,
            Modifier.self,
            Order.self,
            OrderItem.self,
            OrderItemModifier.self,
            Payment.self,
            Employee.self,
            EmployeeShift.self,
            Timecard.self,
            RegisterSession.self,
            Branch.self,
            PurchaseOrder.self,
            PurchaseOrderItem.self,
            Promotion.self,
            PromotionBundleItem.self,
            Printer.self,
            PrintRoutingRule.self,
            AuditLog.self,
            Customer.self,
            OrderDiscount.self,
            OrderTaxLine.self,
            Tip.self,
            RefundTransaction.self,
            CashMovement.self,
            LoyaltyTransaction.self,
            GiftCard.self,
            MerchantDevice.self,
            StaffSessionRecord.self,
            SecurityPolicy.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // Only remove SwiftData store files, not all files in Application Support
            let fm = FileManager.default
            if let appSupportURL = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                let storeFiles = (try? fm.contentsOfDirectory(at: appSupportURL, includingPropertiesForKeys: nil)) ?? []
                let swiftDataExtensions = [".store", ".sqlite"]
                for file in storeFiles {
                    if swiftDataExtensions.contains(where: { file.lastPathComponent.hasSuffix($0) }) {
                        try? fm.removeItem(at: file)
                    }
                }
            }
            
            do {
                return try ModelContainer(for: schema, configurations: [modelConfiguration])
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
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .modelContainer(sharedModelContainer)
                .environmentObject(lm)
        }
    }
}
