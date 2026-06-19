// MainDashboardView.swift
// AlphaPos — Premium Sidebar Navigation

import SwiftUI
import SwiftData
import Combine


struct MainDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    // รับ LocalizationManager จาก App.swift → trigger re-render เมื่อภาษาเปลี่ยน
    @EnvironmentObject private var lm: LocalizationManager
    @EnvironmentObject private var sessionManager: AppSessionManager

    @AppStorage("app_theme") private var appTheme = AppTheme.dark.rawValue
    @AppStorage("active_branch_id") private var activeBranchId = ""
    @AppStorage("enable_table_system") private var enableTableSystem = true
    @AppStorage("developer_mode_enabled") private var developerModeEnabled = false
    @AppStorage("staff_session_timeout_minutes") private var staffSessionTimeoutMinutes = 15
    @State private var selectedTab: DashboardTab = .tables
    @State private var posTableSession: TableSession? = nil
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @Query(sort: \InventoryItem.name) private var inventoryItems: [InventoryItem]
    @ObservedObject private var syncEngine = SyncEngine.shared
    
    private let timer = Timer.publish(every: 5.0, on: .main, in: .common).autoconnect()

    
    private var visibleTabs: [DashboardTab] {
        DashboardTab.allCases.filter { tab in
            if tab == .tables {
                return enableTableSystem && canAccess(tab)
            }
            if tab == .pos {
                return !enableTableSystem && canAccess(tab)
            }
            return canAccess(tab)
        }
    }

    enum DashboardTab: String, CaseIterable, Identifiable {
        // ── Group 1: Core Operations ─────────────────────────────────────
        case inventory  = "Menus"               // Menus (renamed from Inventory)
        case pos        = "Orders"               // Orders (renamed from POS)
        case tables     = "Table Management"
        case kitchen    = "Kitchen Display"
        // ── Group 2: Management ──────────────────────────────────────────
        case store      = "Stores"               // Stores (renamed)
        case promotions = "Marketing"            // Marketing (renamed)
        case cashDrawer = "Hot Actions"          // Hot Actions (renamed)
        case reports    = "Reports"
        case sales      = "Accounting"           // Accounting (renamed)
        case loyalty    = "Loyalty"
        case giftCards  = "Gift Cards"
        case payroll    = "Payroll"
        case timecard   = "Timecard"
        // ── Group 3: System ──────────────────────────────────────────────
        case syncHealth = "Integrations"         // Integrations (renamed)
        case settings   = "Settings"

        var id: String { rawValue }

        // MARK: - Section grouping
        enum SidebarSection { case operations, management, system }
        var section: SidebarSection {
            switch self {
            case .inventory, .pos, .tables, .kitchen:
                return .operations
            case .store, .promotions, .cashDrawer, .reports, .sales, .loyalty, .giftCards, .payroll, .timecard:
                return .management
            case .syncHealth, .settings:
                return .system
            }
        }

        // MARK: - Badge
        enum Badge { case beta, new, none }
        var badge: Badge {
            switch self {
            case .kitchen: return .beta
            case .sales:   return .new
            default:       return .none
            }
        }

        /// ชื่อที่แปลแล้วตามภาษาปัจจุบัน
        var localizedName: String {
            switch self {
            case .inventory:  return L.Nav.tabInventory.t    // "Menus"
            case .pos:        return L.Nav.tabPOS.t          // "Orders"
            case .tables:     return L.Nav.tabTables.t       // "Table Management"
            case .kitchen:    return L.Nav.tabKitchen.t      // "Kitchen Display"
            case .store:      return L.Nav.tabStore.t        // "Stores"
            case .promotions: return L.Nav.tabPromotions.t   // "Marketing"
            case .cashDrawer: return L.Nav.tabCashDrawer.t   // "Hot Actions"
            case .reports:    return L.Nav.tabReports.t
            case .sales:      return L.Nav.tabSales.t        // "Accounting"
            case .loyalty:    return L.Nav.tabLoyalty.t
            case .giftCards:  return L.Nav.tabGiftCards.t
            case .payroll:    return L.Nav.tabPayroll.t
            case .timecard:   return L.Nav.tabTimecard.t
            case .syncHealth: return L.Nav.tabSyncHealth.t   // "Integrations"
            case .settings:   return L.Nav.tabSettings.t
            }
        }

        var icon: String {
            switch self {
            case .inventory:  return "fork.knife"                        // Menus
            case .pos:        return "tray.full.fill"                    // Orders
            case .tables:     return "tablecells.fill"                   // Table Management
            case .kitchen:    return "display"                           // Kitchen Display
            case .store:      return "chart.bar.fill"                    // Stores
            case .promotions: return "megaphone.fill"                    // Marketing
            case .cashDrawer: return "bolt.circle.fill"                  // Hot Actions
            case .reports:    return "chart.bar.fill"                    // Reports
            case .sales:      return "chart.bar.fill"                    // Accounting
            case .loyalty:    return "star.circle.fill"
            case .giftCards:  return "giftcard.fill"
            case .payroll:    return "dollarsign.circle.fill"
            case .timecard:   return "faceid"
            case .syncHealth: return "puzzlepiece.extension.fill"        // Integrations
            case .settings:   return "gearshape.fill"
            }
        }

        /// Accent gradient per tab for selected state
        var gradient: LinearGradient {
            switch self {
            case .inventory:  return LinearGradient(colors: [Color(hex: "0EA5E9"), Color(hex: "6366F1")], startPoint: .leading, endPoint: .trailing)
            case .pos:        return LinearGradient(colors: [Color.appAccent, Color(hex: "60A5FA")], startPoint: .leading, endPoint: .trailing)
            case .tables:     return APGradient.accent
            case .kitchen:    return LinearGradient(colors: [Color(hex: "F59E0B"), Color(hex: "FB923C")], startPoint: .leading, endPoint: .trailing)
            case .store:      return LinearGradient(colors: [Color(hex: "F43F5E"), Color(hex: "FDA4AF")], startPoint: .leading, endPoint: .trailing)
            case .promotions: return LinearGradient(colors: [Color(hex: "10B981"), Color(hex: "34D399")], startPoint: .leading, endPoint: .trailing)
            case .cashDrawer: return LinearGradient(colors: [Color(hex: "F97316"), Color(hex: "EF4444")], startPoint: .leading, endPoint: .trailing)
            case .reports:    return LinearGradient(colors: [Color(hex: "06B6D4"), Color(hex: "3B82F6")], startPoint: .leading, endPoint: .trailing)
            case .sales:      return LinearGradient(colors: [Color(hex: "8B5CF6"), Color(hex: "D946EF")], startPoint: .leading, endPoint: .trailing)
            case .loyalty:    return LinearGradient(colors: [Color(hex: "A78BFA"), Color(hex: "F59E0B")], startPoint: .leading, endPoint: .trailing)
            case .giftCards:  return LinearGradient(colors: [Color(hex: "F59E0B"), Color(hex: "F97316")], startPoint: .leading, endPoint: .trailing)
            case .payroll:    return LinearGradient(colors: [Color(hex: "A855F7"), Color(hex: "EC4899")], startPoint: .leading, endPoint: .trailing)
            case .timecard:   return APGradient.positive
            case .syncHealth: return LinearGradient(colors: [Color(hex: "22C55E"), Color(hex: "0EA5E9")], startPoint: .leading, endPoint: .trailing)
            case .settings:   return LinearGradient(colors: [Color(hex: "9CA3AF"), Color(hex: "4B5563")], startPoint: .leading, endPoint: .trailing)
            }
        }

        var iconColor: Color {
            switch self {
            case .inventory:  return Color(hex: "0EA5E9")
            case .pos:        return Color(hex: "60A5FA")
            case .tables:     return Color.appAccent
            case .kitchen:    return Color(hex: "F59E0B")
            case .store:      return Color(hex: "F43F5E")
            case .promotions: return Color(hex: "10B981")
            case .cashDrawer: return Color(hex: "F97316")
            case .reports:    return Color(hex: "06B6D4")
            case .sales:      return Color(hex: "8B5CF6")
            case .loyalty:    return Color(hex: "A78BFA")
            case .giftCards:  return Color(hex: "F59E0B")
            case .payroll:    return Color(hex: "A855F7")
            case .timecard:   return Color(hex: "34D399")
            case .syncHealth: return Color(hex: "22C55E")
            case .settings:   return Color(hex: "9CA3AF")
            }
        }

        var requiredPermission: AppPermission {
            switch self {
            case .tables:     return .tablesManage
            case .pos:        return .posSell
            case .cashDrawer: return .cashDrawerManage
            case .kitchen:    return .kitchenView
            case .timecard:   return .posSell
            case .inventory:  return .inventoryView
            case .giftCards:  return .posSell
            case .loyalty:    return .posSell
            case .payroll:    return .payrollManage
            case .sales:      return .reportsView
            case .reports:    return .reportsView
            case .promotions: return .discountApply
            case .store:      return .settingsManage
            case .syncHealth: return .deviceManage
            case .settings:   return .settingsManage
            }
        }
    }

    private var resolvedColorScheme: ColorScheme? {
        if appTheme == AppTheme.dark.rawValue {
            return .dark
        } else if appTheme == AppTheme.light.rawValue {
            return .light
        } else {
            return nil
        }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarContent
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 260)
        } detail: {
            NavigationStack {
                detailContent
            }
        }
        .apColorScheme()
        .onReceive(timer) { _ in
            Task {
                await SyncEngine.shared.syncAll(modelContext: modelContext)
            }
            enforceStaffSessionTimeout()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openTableNotification)) { notification in
            guard let tableNumber = notification.userInfo?["table_number"] as? String else { return }
            let descriptor = FetchDescriptor<RestaurantTable>(
                predicate: #Predicate<RestaurantTable> { $0.tableNumber == tableNumber }
            )
            if let tables = try? modelContext.fetch(descriptor), let table = tables.first {
                if let activeSession = table.sessions.first(where: { $0.isActive }) {
                    self.posTableSession = activeSession
                    self.selectedTab = .pos
                } else {
                    self.selectedTab = .tables
                }
            }
        }
        .onAppear {
            if !enableTableSystem && selectedTab == .tables {
                selectedTab = .pos
            }
            ensureSelectedTabIsAllowed()
            if developerModeEnabled {
                SampleDataSeeder.autoSeedIfOutdated(modelContext: modelContext)
            } else {
                SampleDataSeeder.seedRolesAndEmployeesIfEmpty(modelContext: modelContext)
            }
        }
        .onChange(of: enableTableSystem) { _, enabled in
            if enabled && selectedTab == .pos {
                selectedTab = .tables
            } else if !enabled && selectedTab == .tables {
                selectedTab = .pos
            }
            ensureSelectedTabIsAllowed()
        }
        .onChange(of: sessionManager.currentStaffSession) { _, _ in
            ensureSelectedTabIsAllowed()
        }
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebarContent: some View {
        ZStack {
            // Background
            APGradient.sidebar.ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Brand header ────────────────────────────────────────────
                brandHeader

                Divider()
                    .background(Color.appDivider)
                    .padding(.horizontal, APSpacing.md)

                // ── Navigation items ─────────────────────────────────────────
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: APSpacing.xs) {
                        // ── Group 1: Core Operations ─────────────────────
                        let opTabs  = visibleTabs.filter { $0.section == .operations }
                        let mgtTabs = visibleTabs.filter { $0.section == .management }
                        let sysTabs = visibleTabs.filter { $0.section == .system }

                        ForEach(opTabs) { tab in sidebarRow(tab) }

                        if !opTabs.isEmpty && !mgtTabs.isEmpty {
                            Divider()
                                .background(Color.appDivider)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 4)
                        }

                        // ── Group 2: Management ──────────────────────────
                        ForEach(mgtTabs) { tab in sidebarRow(tab) }

                        if !mgtTabs.isEmpty && !sysTabs.isEmpty {
                            Divider()
                                .background(Color.appDivider)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 4)
                        }

                        // ── Group 3: System ──────────────────────────────
                        ForEach(sysTabs) { tab in sidebarRow(tab) }
                    }
                    .padding(.horizontal, APSpacing.sm)
                    .padding(.top, APSpacing.md)
                }

                Spacer()
                
                // ── Inventory Health Widget ────────────────────────────────
                inventoryHealthWidget

                staffSessionWidget

                // ── Footer version label ─────────────────────────────────────
                sidebarFooter
            }
        }
        .listStyle(.sidebar)
    }

    private func canAccess(_ tab: DashboardTab) -> Bool {
        sessionManager.currentStaffSession == nil || sessionManager.can(tab.requiredPermission)
    }

    private func ensureSelectedTabIsAllowed() {
        guard !visibleTabs.contains(selectedTab), let first = visibleTabs.first else { return }
        selectedTab = first
    }

    private func enforceStaffSessionTimeout() {
        guard let staff = sessionManager.currentStaffSession else { return }
        let timeout = TimeInterval(max(1, staffSessionTimeoutMinutes) * 60)
        if Date().timeIntervalSince(staff.startedAt) >= timeout {
            sessionManager.lockStaffSession(modelContext: modelContext, reason: "session_timeout")
        }
    }

    private var brandHeader: some View {
        HStack(spacing: 10) {
            // Logo mark — compact to align with sidebar toggle button
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(APGradient.accent)
                    .frame(width: 32, height: 32)
                    .shadow(color: Color.appAccent.opacity(0.5), radius: 6, x: 0, y: 2)
                Image(systemName: "bolt.fill")
                    .font(.system(size: 15, weight: .black))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("AlphaPos")
                    .font(.system(size: 15, weight: .black))
                    .foregroundColor(.textPrimary)
                Text(L.Dashboard.restaurantManagement.t)
                    .font(.system(size: 9))
                    .foregroundColor(.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, APSpacing.sm)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    // MARK: - Sidebar Row Helper
    private func sidebarRow(_ tab: DashboardTab) -> some View {
        SidebarTabRow(tab: tab, isSelected: selectedTab == tab)
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedTab = tab
                    columnVisibility = .detailOnly
                }
            }
    }

    private var sidebarFooter: some View {
        HStack(spacing: 6) {
            // Online status dot
            Circle()
                .fill(Color.appTeal)
                .frame(width: 6, height: 6)
            Text(L.Dashboard.systemOnline.t)
                .font(.system(size: 9))
                .foregroundColor(.textSecondary)

            Spacer()

            // Sync status
            HStack(spacing: 3) {
                Image(systemName: syncIcon)
                    .font(.system(size: 8))
                    .foregroundColor(syncColor)
                if let lastSynced = syncEngine.lastSyncedAt {
                    Text(formatTime(lastSynced))
                        .font(.system(size: 8))
                        .foregroundColor(.textTertiary)
                } else {
                    Text(syncStatusText)
                        .font(.system(size: 8))
                        .foregroundColor(.textTertiary)
                        .lineLimit(1)
                }
            }

            Text("v2.0")
                .font(.system(size: 8))
                .foregroundColor(.textTertiary)
        }
        .padding(.horizontal, APSpacing.sm)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var staffSessionWidget: some View {
        if let staff = sessionManager.currentStaffSession {
            HStack(spacing: 8) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(Color.appAccent.opacity(0.18))
                        .frame(width: 28, height: 28)
                    Text(staffInitials(staff.displayName))
                        .font(.system(size: 10, weight: .black))
                        .foregroundColor(.appAccent)
                }

                // Name + role
                VStack(alignment: .leading, spacing: 1) {
                    Text(staff.displayName)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(staff.roleName)
                        .font(.system(size: 9))
                        .foregroundColor(.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                // Lock button — compact icon
                Button {
                    APHaptic.trigger()
                    sessionManager.lockStaffSession(modelContext: modelContext)
                } label: {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.appAccent)
                        .frame(width: 28, height: 28)
                        .background(Color.appAccent.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.appSurface)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appBorderSubtle, lineWidth: 1))
            )
            .padding(.horizontal, APSpacing.sm)
            .padding(.bottom, 4)
        }
    }
    
    private var syncIcon: String {
        switch syncEngine.syncStatus {
        case .idle:
            return "checkmark.circle.fill"
        case .syncing:
            return "arrow.triangle.2.circlepath"
        case .error:
            return "exclamationmark.circle.fill"
        case .offline:
            return "wifi.slash"
        }
    }
    
    private var syncColor: Color {
        switch syncEngine.syncStatus {
        case .idle:
            return .appTeal
        case .syncing:
            return Color.appAccent
        case .error:
            return .red
        case .offline:
            return Color(hex: "9CA3AF")
        }
    }
    
    private var syncStatusText: String {
        switch syncEngine.syncStatus {
        case .idle:
            return L.Dashboard.syncSuccess.t
        case .syncing:
            return L.Dashboard.syncing.t
        case .error:
            return L.Dashboard.syncFailed.t
        case .offline:
            return L.Dashboard.offlineMode.t
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private func staffInitials(_ name: String) -> String {
        let letters = name.split(separator: " ").prefix(2).compactMap { $0.first }
        return letters.isEmpty ? "S" : String(letters).uppercased()
    }
    
    // MARK: - Inventory Health Widget
    
    private var inventoryHealthWidget: some View {
        let activeBranchUUID = UUID(uuidString: activeBranchId)
        let branchItems = inventoryItems.filter { item in
            if let activeId = activeBranchUUID { return item.branch?.id == activeId }
            return true
        }
        let lowStockItems = branchItems.filter { $0.currentQuantity <= $0.reorderLevel }
        let totalValue    = branchItems.reduce(0.0) { $0 + ($1.currentQuantity * $1.costPrice) }

        return HStack(spacing: 6) {
            // Stock value chip
            HStack(spacing: 4) {
                Image(systemName: "banknote.fill")
                    .font(.system(size: 9))
                    .foregroundColor(.appTeal)
                VStack(alignment: .leading, spacing: 0) {
                    Text(L.Dashboard.stockValue.t)
                        .font(.system(size: 7))
                        .foregroundColor(.textTertiary)
                    Text("฿\(totalValue.formatted(.number.precision(.fractionLength(0))))")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.textPrimary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.appSurfaceHigh)
            .cornerRadius(8)

            Spacer()

            // Low-stock badge (only when needed)
            if !lowStockItems.isEmpty {
                HStack(spacing: 3) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.appRose)
                    Text(LocalizationManager.shared.t(L.Dashboard.itemsBelowReorder, lowStockItems.count))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.appRose)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.appRose.opacity(0.08))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appRose.opacity(0.2), lineWidth: 1))
                .onTapGesture {
                    withAnimation { selectedTab = .inventory; columnVisibility = .detailOnly }
                }
            }
        }
        .padding(.horizontal, APSpacing.sm)
        .padding(.bottom, 4)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailContent: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            switch selectedTab {
            case .tables:     TableView(selectedTab: $selectedTab, activeSession: $posTableSession, columnVisibility: $columnVisibility)
            case .pos:        POSView(activeSession: $posTableSession, selectedTab: $selectedTab, columnVisibility: $columnVisibility)
            case .cashDrawer: CashDrawerManagementView()
            case .kitchen:    KitchenDisplayView()
            case .timecard:   EmployeeTimecardView()
            case .inventory:  InventoryView()
            case .giftCards:  GiftCardManagementView()
            case .loyalty:    LoyaltyManagementView()
            case .payroll:    PayrollDashboardView()
            case .sales:      SalesDashboardView()
            case .reports:    ReportsView()
            case .promotions: PromotionsManagementView(columnVisibility: $columnVisibility)
            case .store:      StoreManagementView()
            case .syncHealth: SyncHealthView()
            case .settings:   SettingsView()
            }
        }
    }
}

// MARK: - Sidebar Tab Row

private struct SidebarTabRow: View {
    let tab:        MainDashboardView.DashboardTab
    let isSelected: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            // Icon container
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? tab.gradient : LinearGradient(colors: [Color.appSurfaceHigh], startPoint: .top, endPoint: .bottom))
                    .frame(width: 32, height: 32)
                    .shadow(color: isSelected ? tab.iconColor.opacity(0.5) : .clear, radius: 8, x: 0, y: 2)

                Image(systemName: tab.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isSelected ? .white : tab.iconColor.opacity(0.7))
            }

            HStack(spacing: 6) {
                Text(tab.localizedName)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundColor(isSelected ? .textPrimary : .textSecondary)

                // Badge: Beta / New
                switch tab.badge {
                case .beta:
                    Text("sidebar_badge_beta".t)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.textSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.appSurfaceHigh)
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.appBorderSubtle, lineWidth: 1))
                case .new:
                    Text("sidebar_badge_new".t)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color(hex: "854D0E"))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(hex: "FEF08A").opacity(0.9))
                        .cornerRadius(6)
                case .none:
                    EmptyView()
                }
            }

            Spacer()

            if isSelected {
                Circle()
                    .fill(tab.iconColor)
                    .frame(width: 6, height: 6)
            }
        }
        .overlay(
            // Low Stock badge overlay
            lowStockBadge,
            alignment: .topTrailing
        )
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: APRadius.md, style: .continuous)
                .fill(isSelected ? Color.appSurfaceHigh : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: APRadius.md, style: .continuous)
                        .stroke(isSelected ? Color.appBorderSubtle : Color.clear, lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
        .scaleEffect(isHovered && !isSelected ? 0.98 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onHover { isHovered = $0 }
    }
    
    @ViewBuilder
    private var lowStockBadge: some View {
        EmptyView() // Badge rendered at parent level; placeholder for extensibility
    }
}

// MARK: - Preview

#Preview {
    MainDashboardView()
        .modelContainer(for: [RestaurantTable.self, MenuItem.self, Employee.self, InventoryItem.self], inMemory: true)
}
