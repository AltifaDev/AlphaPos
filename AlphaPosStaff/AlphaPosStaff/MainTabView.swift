import SwiftUI
import Combine

struct MainTabView: View {
    @Binding var loggedInEmployee: Employee?
    
    private var networkService: NetworkService { NetworkService.shared }
    @StateObject private var deepLinkRouter = DeepLinkRouter.shared
    
    private var requestsCount: Int {
        networkService.serviceRequests.filter { $0.status == "pending" }.count
    }
    
    @AppStorage("app_language") private var appLanguage = "en"
    @AppStorage("logged_in_employee_name") private var loggedInEmployeeName = ""
    @AppStorage("logged_in_employee_role") private var loggedInEmployeeRole = ""
    @State private var selectedTab = 0
    @State private var countTimer: Timer? = nil
    
    // Deep link presentation state
    @State private var showOrderTimeline = false
    @State private var deepLinkOrder: Order? = nil
    @State private var showTableDetail = false
    @State private var deepLinkTableNumber: String? = nil

    var body: some View {
        ZStack(alignment: .top) {
            TabView(selection: $selectedTab) {
            TablesView()
                .tabItem {
                    Label("tables".localized(for: appLanguage), systemImage: "table.furniture")
                }
                .tag(0)
            
            QuickOrderView()
                .tabItem {
                    Label("quick_order".localized(for: appLanguage), systemImage: "bag.fill.badge.plus")
                }
                .tag(1)
            
            NotificationListView()
                .tabItem {
                    Label("alerts".localized(for: appLanguage), systemImage: "bell.badge.fill")
                }
            .badge(networkService.activeAlertsCount)
                .tag(2)
            
            NavigationStack {
                StaffMessagingView()
            }
            .tabItem {
                Label("messages".localized(for: appLanguage), systemImage: "bubble.left.and.bubble.right.fill")
            }
            .badge(networkService.unreadChatCount)
            .tag(3)
            
            NavigationStack {
                MoreMenuView(loggedInEmployee: $loggedInEmployee)
            }
            .tabItem {
                Label("more".localized(for: appLanguage), systemImage: "ellipsis.circle.fill")
            }
            .tag(4)
        }
        .tint(.appAccent)
        .apColorScheme()
            
            // Offline banner overlay
            if OfflineCache.shared.isOffline {
                VStack {
                    OfflineBannerView(queueCount: OfflineCache.shared.queuedOrderCount)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    Spacer()
                }
                .animation(.easeInOut(duration: 0.3), value: OfflineCache.shared.isOffline)
            }
        }
        .onAppear {
            if let emp = loggedInEmployee {
                loggedInEmployeeName = "\(emp.firstName) \(emp.lastName)"
                loggedInEmployeeRole = emp.role
            }
            prefetchMenu()
            startCentralSyncPolling()
        }
        .onChange(of: loggedInEmployee) { newEmp in
            if let emp = newEmp {
                loggedInEmployeeName = "\(emp.firstName) \(emp.lastName)"
                loggedInEmployeeRole = emp.role
            } else {
                loggedInEmployeeName = ""
                loggedInEmployeeRole = ""
            }
        }
        .onDisappear {
            countTimer?.invalidate()
            countTimer = nil
        }
        // MARK: - Legacy Notification Handlers (backward compatibility)
        .onReceive(NotificationCenter.default.publisher(for: .openAlertsNotification)) { _ in
            self.selectedTab = 2
        }
        .onReceive(NotificationCenter.default.publisher(for: .openTableNotification)) { _ in
            self.selectedTab = 0
        }
        // MARK: - Deep Link Router Navigation
        .onReceive(deepLinkRouter.$pendingDestination.compactMap { $0 }) { destination in
            handleDeepLink(destination)
        }
        .onReceive(deepLinkRouter.$presentOrderId.compactMap { $0 }) { orderId in
            // Find the order in network service data and present timeline
            if let order = findOrder(byId: orderId) {
                deepLinkOrder = order
                showOrderTimeline = true
            }
        }
        .onReceive(deepLinkRouter.$presentTableNumber.compactMap { $0 }) { tableNumber in
            deepLinkTableNumber = tableNumber
            showTableDetail = true
        }
        // MARK: - Deep Link Sheets
        .sheet(isPresented: $showOrderTimeline, onDismiss: {
            deepLinkRouter.clearOrderPresentation()
            deepLinkOrder = nil
        }) {
            if let order = deepLinkOrder {
                // ไม่ใส่ NavigationStack ซ้อน — OrderTimelineView มี NavigationStack ของตัวเองอยู่แล้ว
                OrderTimelineView(order: order)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                showOrderTimeline = false
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .apColorScheme()
            }
        }
        .sheet(isPresented: $showTableDetail, onDismiss: {
            deepLinkRouter.clearTablePresentation()
            deepLinkTableNumber = nil
        }) {
            if let tableNum = deepLinkTableNumber,
               let table = findTable(byNumber: tableNum) {
                // ไม่ใส่ NavigationStack ซ้อน — TableDetailView ถูกออกแบบให้อยู่ใน stack ของ parent
                TableDetailView(table: table)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                showTableDetail = false
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .apColorScheme()
            }
        }
    }
    
    // MARK: - Deep Link Handler
    
    private func handleDeepLink(_ destination: DeepLinkDestination) {
        withAnimation(.easeInOut(duration: 0.25)) {
            selectedTab = destination.targetTab
        }
        
        #if DEBUG
        print("MainTabView: Deep link → tab \(destination.targetTab) for \(destination)")
        #endif
    }
    
    // MARK: - Data Lookup Helpers
    
    private func findOrder(byId orderId: String) -> Order? {
        // Search in all orders from NetworkService
        return networkService.orders.first { $0.id == orderId }
    }
    
    private func findTable(byNumber tableNumber: String) -> RestaurantTable? {
        return networkService.tables.first { $0.tableNumber == tableNumber }
    }
    
    // MARK: - Existing Helpers
    
    private func prefetchMenu() {
        Task {
            // Warm-up cache
            _ = try? await networkService.fetchMenu()
        }
    }
    
    private func startCentralSyncPolling() {
        Task {
            await networkService.refreshAll()
        }
        countTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { _ in
            Task {
                await networkService.refreshAll()
            }
        }
    }
}
