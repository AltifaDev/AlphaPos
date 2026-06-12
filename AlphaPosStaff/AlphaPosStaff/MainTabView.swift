import SwiftUI

struct MainTabView: View {
    @Binding var loggedInEmployee: Employee?
    
    private var networkService: NetworkService { NetworkService.shared }
    
    private var requestsCount: Int {
        networkService.serviceRequests.filter { $0.status == "pending" }.count
    }
    
    @AppStorage("app_language") private var appLanguage = "en"
    @State private var selectedTab = 0
    @State private var countTimer: Timer? = nil

    var body: some View {
        TabView(selection: $selectedTab) {
            TablesView()
                .tabItem {
                    Label("tables".localized(for: appLanguage), systemImage: "table.furniture")
                }
                .tag(0)
            
            NotificationListView()
                .tabItem {
                    Label("alerts".localized(for: appLanguage), systemImage: "bell.badge.fill")
                }
                .badge(requestsCount > 0 ? requestsCount : 0)
                .tag(1)
            
            if let emp = loggedInEmployee {
                TimecardView(employee: emp)
                    .tabItem {
                        Label("clock_in_out".localized(for: appLanguage), systemImage: "clock.badge.checkmark.fill")
                    }
                    .tag(2)
                
                StaffDashboardView(employee: emp, loggedInEmployee: $loggedInEmployee)
                    .tabItem {
                        Label("my_account".localized(for: appLanguage), systemImage: "person.crop.circle.fill")
                    }
                    .tag(3)
            }
        }
        .tint(.appAccent)
        .apColorScheme()
        .onAppear {
            prefetchMenu()
            startCentralSyncPolling()
        }
        .onDisappear {
            countTimer?.invalidate()
            countTimer = nil
        }
    }
    
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
