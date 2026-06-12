import SwiftUI
import SwiftData

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
            Printer.self,
            PrintRoutingRule.self
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

    @AppStorage("is_logged_in") private var isLoggedIn = false

    init() {
        _ = SyncEngine.shared
    }

    var body: some Scene {
        WindowGroup {
            if isLoggedIn {
                MainDashboardView()
                    .modelContainer(sharedModelContainer)
            } else {
                MerchantAuthView()
                    .modelContainer(sharedModelContainer)
            }
        }
    }
}
