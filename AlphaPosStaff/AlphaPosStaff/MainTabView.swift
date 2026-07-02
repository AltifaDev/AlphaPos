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
    @State private var previousTab = 0
    @State private var countTimer: Timer? = nil
    
    // Deep link presentation state
    @State private var showOrderTimeline = false
    @State private var deepLinkOrder: Order? = nil
    @State private var showTableDetail = false
    @State private var deepLinkTableNumber: String? = nil

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                ZStack {
                    if selectedTab == 0 {
                        TablesView()
                            .transition(tabTransition(for: 0))
                            .zIndex(0)
                    } else if selectedTab == 1 {
                        QuickOrderView()
                            .transition(tabTransition(for: 1))
                            .zIndex(1)
                    } else if selectedTab == 2 {
                        NotificationListView()
                            .transition(tabTransition(for: 2))
                            .zIndex(2)
                    } else if selectedTab == 3 {
                        NavigationStack {
                            StaffMessagingView()
                        }
                        .transition(tabTransition(for: 3))
                        .zIndex(3)
                    } else if selectedTab == 4 {
                        NavigationStack {
                            MoreMenuView(loggedInEmployee: $loggedInEmployee)
                        }
                        .transition(tabTransition(for: 4))
                        .zIndex(4)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                customTabBar()
            }
            .ignoresSafeArea(.all, edges: .bottom)
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
        .onChange(of: selectedTab) { oldTab, newTab in
            previousTab = oldTab
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
    
    // MARK: - Custom Animated Tab Bar Helpers
    
    private func tabTransition(for tabIndex: Int) -> AnyTransition {
        let isMovingRight = selectedTab > previousTab
        return .asymmetric(
            insertion: .move(edge: isMovingRight ? .trailing : .leading),
            removal: .move(edge: isMovingRight ? .leading : .trailing)
        )
    }
    
    private func customTabBar() -> some View {
        VStack(spacing: 0) {
            Divider()
                .background(Color.secondary.opacity(0.15))
            
            HStack(spacing: 0) {
                tabButton(index: 0, title: "tables", systemImage: "table.furniture")
                tabButton(index: 1, title: "quick_order", systemImage: "bag.fill.badge.plus")
                tabButton(index: 2, title: "alerts", systemImage: "bell.badge.fill", badgeCount: networkService.activeAlertsCount)
                tabButton(index: 3, title: "messages", systemImage: "bubble.left.and.bubble.right.fill", badgeCount: networkService.unreadChatCount)
                tabButton(index: 4, title: "more", systemImage: "ellipsis.circle.fill")
            }
            .padding(.horizontal, 8)
            .padding(.top, 10)
            .padding(.bottom, 10) // Padded naturally, safe area handles extending background
            .background(.ultraThinMaterial)
        }
    }
    
    private func tabButton(index: Int, title: String, systemImage: String, badgeCount: Int = 0) -> some View {
        let isSelected = selectedTab == index
        return Button {
            if selectedTab != index {
                previousTab = selectedTab
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    selectedTab = index
                }
                APHaptic.trigger()
            }
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    Image(systemName: systemImage)
                        .font(.system(size: 20, weight: isSelected ? .bold : .medium))
                        .foregroundColor(isSelected ? .appAccent : .secondary.opacity(0.8))
                        .scaleEffect(isSelected ? 1.15 : 1.0)
                        .frame(width: 28, height: 28)
                    
                    if badgeCount > 0 {
                        Text("\(badgeCount)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.appRose)
                            .clipShape(Capsule())
                            .offset(x: 12, y: -10)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                
                Text(title.localized(for: appLanguage))
                    .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                    .foregroundColor(isSelected ? .appAccent : .secondary.opacity(0.8))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}
