// MainDashboardView.swift
// AlphaPos — Enterprise Premium Sidebar Navigation (v3.0)
// Redesigned: 5-group enterprise sidebar with Live Dashboard,
// Notification Center, Customer CRM, Device Management, Organization

import SwiftUI
import SwiftData
import Combine


struct MainDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    // รับ LocalizationManager จาก App.swift → trigger re-render เมื่อภาษาเปลี่ยน
    @EnvironmentObject private var lm: LocalizationManager
    @EnvironmentObject private var sessionManager: AppSessionManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @AppStorage("app_theme") private var appTheme = AppTheme.dark.rawValue
    @AppStorage("active_branch_id") private var activeBranchId = ""
    @AppStorage("enable_table_system") private var enableTableSystem = true
    @AppStorage("developer_mode_enabled") private var developerModeEnabled = false
    @AppStorage("staff_session_timeout_minutes") private var staffSessionTimeoutMinutes = 15
    @AppStorage("offline_sync_mode") private var offlineSyncMode = false
    @State private var selectedTab: DashboardTab = .dashboard
    @State private var navigationPath = NavigationPath()
    @State private var posTableSession: TableSession? = nil
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @Query(sort: \InventoryItem.name) private var inventoryItems: [InventoryItem]
    @ObservedObject private var syncEngine = SyncEngine.shared

    // Manual connect/cancel prevents timer leak when view leaves hierarchy
    private let timer = Timer.publish(every: 5.0, on: .main, in: .common)
    @State private var timerCancellable: Cancellable? = nil


    private var visibleTabs: [DashboardTab] {
        DashboardTab.allCases.filter { tab in
            if tab == .syncHealth && offlineSyncMode {
                return false
            }
            if tab == .tables {
                return enableTableSystem && canAccess(tab)
            }
            if tab == .pos {
                return !enableTableSystem && canAccess(tab)
            }
            return canAccess(tab)
        }
    }

    // MARK: - Enterprise Sidebar Tabs (5 Groups)

    enum DashboardTab: String, CaseIterable, Identifiable {
        // ── Group 1: Overview ─────────────────────────────────────────────
        case dashboard      = "Dashboard"            // NEW: Live KPI Dashboard
        case notifications  = "Notifications"        // NEW: Unified Notification Center
        // ── Group 2: Operations ───────────────────────────────────────────
        case tables         = "Table Management"
        case pos            = "Orders"
        case kitchen        = "Kitchen Display"
        case inventory      = "Menus"
        // ── Group 3: Management ───────────────────────────────────────────
        case cashDrawer     = "Hot Actions"
        case payments       = "Payments"             // NEW: Payment Gateway
        case reports        = "Reports"
        case sales          = "Accounting"
        case promotions     = "Marketing"
        case loyalty        = "Loyalty"
        case giftCards      = "Gift Cards"
        // ── Group 4: People ───────────────────────────────────────────────
        case customers      = "Customers"            // NEW: Customer CRM
        case payroll        = "Payroll"
        case timecard       = "Timecard"
        // ── Group 5: Enterprise ───────────────────────────────────────────
        case store          = "Stores"
        case devices        = "Devices"              // NEW: Device Management
        case organization   = "Organization"         // NEW: Tenant Management
        // ── Group 6: System ───────────────────────────────────────────────
        case syncHealth     = "Integrations"
        case settings       = "Settings"

        // Gift cards live inside unified Customer Value workspace.
        // Keep legacy case so previously persisted navigation remains valid.
        static var allCases: [DashboardTab] {
            [.dashboard, .notifications,
             .tables, .pos, .kitchen, .inventory,
             .cashDrawer, .payments, .reports, .sales, .promotions, .loyalty,
             .customers, .payroll, .timecard,
             .store, .devices, .organization,
             .syncHealth, .settings]
        }

        var id: String { rawValue }

        // MARK: - Section grouping (6 groups)
        enum SidebarSection: String, CaseIterable {
            case overview    = "OVERVIEW"
            case operations  = "OPERATIONS"
            case management  = "MANAGEMENT"
            case people      = "PEOPLE"
            case enterprise  = "ENTERPRISE"
            case system      = "SYSTEM"
        }

        var section: SidebarSection {
            switch self {
            case .dashboard, .notifications:
                return .overview
            case .tables, .pos, .kitchen, .inventory:
                return .operations
            case .cashDrawer, .payments, .reports, .sales, .promotions, .loyalty, .giftCards:
                return .management
            case .customers, .payroll, .timecard:
                return .people
            case .store, .devices, .organization:
                return .enterprise
            case .syncHealth, .settings:
                return .system
            }
        }

        // MARK: - Badge
        enum Badge { case beta, new, none }
        var badge: Badge {
            switch self {
            case .kitchen:       return .beta
            case .dashboard:     return .new
            case .notifications: return .new
            case .customers:     return .new
            case .devices:       return .new
            case .organization:  return .new
            case .payments:      return .new
            default:             return .none
            }
        }

        /// ชื่อที่แปลแล้วตามภาษาปัจจุบัน
        var localizedName: String {
            switch self {
            case .dashboard:     return "dashboard_nav".t
            case .notifications: return "notifications_nav".t
            case .tables:        return L.Nav.tabTables.t
            case .pos:           return L.Nav.tabPOS.t
            case .kitchen:       return L.Nav.tabKitchen.t
            case .inventory:     return L.Nav.tabInventory.t
            case .cashDrawer:    return L.Nav.tabCashDrawer.t
            case .payments:      return "payments_nav".t
            case .reports:       return L.Nav.tabReports.t
            case .sales:         return L.Nav.tabSales.t
            case .promotions:    return L.Nav.tabPromotions.t
            case .loyalty:       return "customer_value_title".t
            case .giftCards:     return L.Nav.tabGiftCards.t
            case .customers:     return "customers_nav".t
            case .payroll:       return L.Nav.tabPayroll.t
            case .timecard:      return L.Nav.tabTimecard.t
            case .store:         return L.Nav.tabStore.t
            case .devices:       return "devices_nav".t
            case .organization:  return "organization_nav".t
            case .syncHealth:    return L.Nav.tabSyncHealth.t
            case .settings:      return L.Nav.tabSettings.t
            }
        }

        var icon: String {
            switch self {
            case .dashboard:     return "square.grid.2x2.fill"           // Live Dashboard
            case .notifications: return "bell.badge.fill"                // Notification Center
            case .tables:        return "tablecells.fill"
            case .pos:           return "tray.full.fill"
            case .kitchen:       return "display"
            case .inventory:     return "fork.knife"
            case .cashDrawer:    return "bolt.circle.fill"
            case .payments:      return "creditcard.and.123"
            case .reports:       return "chart.bar.fill"
            case .sales:         return "chart.line.uptrend.xyaxis"
            case .promotions:    return "megaphone.fill"
            case .loyalty:       return "person.crop.circle.badge.checkmark"
            case .giftCards:     return "giftcard.fill"
            case .customers:     return "person.2.fill"                  // Customer CRM
            case .payroll:       return "dollarsign.circle.fill"
            case .timecard:      return "faceid"
            case .store:         return "building.2.fill"
            case .devices:       return "ipad.and.iphone"               // Device Management
            case .organization:  return "building.columns.fill"          // Organization
            case .syncHealth:    return "puzzlepiece.extension.fill"
            case .settings:      return "gearshape.fill"
            }
        }

        /// Accent gradient per tab for selected state
        var gradient: LinearGradient {
            switch self {
            case .dashboard:     return LinearGradient(colors: [Color(hex: "6366F1"), Color(hex: "8B5CF6")], startPoint: .leading, endPoint: .trailing)
            case .notifications: return LinearGradient(colors: [Color(hex: "EF4444"), Color(hex: "F97316")], startPoint: .leading, endPoint: .trailing)
            case .tables:        return APGradient.accent
            case .pos:           return LinearGradient(colors: [Color.appAccent, Color(hex: "60A5FA")], startPoint: .leading, endPoint: .trailing)
            case .kitchen:       return LinearGradient(colors: [Color(hex: "F59E0B"), Color(hex: "FB923C")], startPoint: .leading, endPoint: .trailing)
            case .inventory:     return LinearGradient(colors: [Color(hex: "0EA5E9"), Color(hex: "6366F1")], startPoint: .leading, endPoint: .trailing)
            case .cashDrawer:    return LinearGradient(colors: [Color(hex: "F97316"), Color(hex: "EF4444")], startPoint: .leading, endPoint: .trailing)
            case .payments:      return LinearGradient(colors: [Color(hex: "10B981"), Color(hex: "059669")], startPoint: .leading, endPoint: .trailing)
            case .reports:       return LinearGradient(colors: [Color(hex: "06B6D4"), Color(hex: "3B82F6")], startPoint: .leading, endPoint: .trailing)
            case .sales:         return LinearGradient(colors: [Color(hex: "8B5CF6"), Color(hex: "D946EF")], startPoint: .leading, endPoint: .trailing)
            case .promotions:    return LinearGradient(colors: [Color(hex: "10B981"), Color(hex: "34D399")], startPoint: .leading, endPoint: .trailing)
            case .loyalty:       return LinearGradient(colors: [Color(hex: "A78BFA"), Color(hex: "F59E0B")], startPoint: .leading, endPoint: .trailing)
            case .giftCards:     return LinearGradient(colors: [Color(hex: "F59E0B"), Color(hex: "F97316")], startPoint: .leading, endPoint: .trailing)
            case .customers:     return LinearGradient(colors: [Color(hex: "EC4899"), Color(hex: "F43F5E")], startPoint: .leading, endPoint: .trailing)
            case .payroll:       return LinearGradient(colors: [Color(hex: "A855F7"), Color(hex: "EC4899")], startPoint: .leading, endPoint: .trailing)
            case .timecard:      return APGradient.positive
            case .store:         return LinearGradient(colors: [Color(hex: "F43F5E"), Color(hex: "FDA4AF")], startPoint: .leading, endPoint: .trailing)
            case .devices:       return LinearGradient(colors: [Color(hex: "14B8A6"), Color(hex: "0EA5E9")], startPoint: .leading, endPoint: .trailing)
            case .organization:  return LinearGradient(colors: [Color(hex: "6366F1"), Color(hex: "3B82F6")], startPoint: .leading, endPoint: .trailing)
            case .syncHealth:    return LinearGradient(colors: [Color(hex: "22C55E"), Color(hex: "0EA5E9")], startPoint: .leading, endPoint: .trailing)
            case .settings:      return LinearGradient(colors: [Color(hex: "9CA3AF"), Color(hex: "4B5563")], startPoint: .leading, endPoint: .trailing)
            }
        }

        var iconColor: Color {
            switch self {
            case .dashboard:     return Color(hex: "6366F1")
            case .notifications: return Color(hex: "EF4444")
            case .tables:        return Color.appAccent
            case .pos:           return Color(hex: "60A5FA")
            case .kitchen:       return Color(hex: "F59E0B")
            case .inventory:     return Color(hex: "0EA5E9")
            case .cashDrawer:    return Color(hex: "F97316")
            case .payments:      return Color(hex: "10B981")
            case .reports:       return Color(hex: "06B6D4")
            case .sales:         return Color(hex: "8B5CF6")
            case .promotions:    return Color(hex: "10B981")
            case .loyalty:       return Color(hex: "A78BFA")
            case .giftCards:     return Color(hex: "F59E0B")
            case .customers:     return Color(hex: "EC4899")
            case .payroll:       return Color(hex: "A855F7")
            case .timecard:      return Color(hex: "34D399")
            case .store:         return Color(hex: "F43F5E")
            case .devices:       return Color(hex: "14B8A6")
            case .organization:  return Color(hex: "6366F1")
            case .syncHealth:    return Color(hex: "22C55E")
            case .settings:      return Color(hex: "9CA3AF")
            }
        }

        var requiredPermission: AppPermission {
            switch self {
            case .dashboard:     return .dashboardView
            case .notifications: return .notificationsManage
            case .tables:        return .tablesManage
            case .pos:           return .posSell
            case .kitchen:       return .kitchenView
            case .inventory:     return .inventoryView
            case .cashDrawer:    return .cashDrawerManage
            case .payments:      return .paymentsManage
            case .reports:       return .reportsView
            case .sales:         return .reportsView
            case .promotions:    return .posSell
            case .loyalty:       return .posSell

            case .giftCards:     return .posSell
            case .customers:     return .customersView
            case .payroll:       return .payrollManage
            case .timecard:      return .posSell
            case .store:         return .settingsManage
            case .devices:       return .devicesView
            case .organization:  return .organizationView
            case .syncHealth:    return .devicesView
            case .settings:      return .settingsManage
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
            NavigationStack(path: $navigationPath) {
                detailContent
                    .navigationTitle(" ")
                    .navigationBarTitleDisplayMode(.inline)
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
                selectedTab = .dashboard
            }
            ensureSelectedTabIsAllowed()
            if developerModeEnabled {
                SampleDataSeeder.autoSeedIfOutdated(modelContext: modelContext)
            } else {
                SampleDataSeeder.seedRolesAndEmployeesIfEmpty(modelContext: modelContext)
            }
            timerCancellable = timer.connect()
        }
        .onDisappear {
            timerCancellable?.cancel()
            timerCancellable = nil
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
        .onChange(of: selectedTab) { _, _ in
            navigationPath = NavigationPath()
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

                // ── Navigation items (6 sections) ───────────────────────────
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: APSpacing.xs) {
                        let sections: [DashboardTab.SidebarSection] = [.overview, .operations, .management, .people, .enterprise, .system]

                        ForEach(sections, id: \.rawValue) { section in
                            let sectionTabs = visibleTabs.filter { $0.section == section }
                            if !sectionTabs.isEmpty {
                                // Section header label
                                sectionHeader(section.rawValue)

                                ForEach(sectionTabs) { tab in sidebarRow(tab) }
                            }
                        }
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

    // MARK: - Section Header

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.textTertiary)
                .tracking(1.2)
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.top, 10)
        .padding(.bottom, 2)
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
                    if selectedTab == tab {
                        navigationPath = NavigationPath()
                    } else {
                        navigationPath = NavigationPath()
                        selectedTab = tab
                    }
                    if horizontalSizeClass == .compact {
                        columnVisibility = .detailOnly
                    }
                }
            }
    }

    private var sidebarFooter: some View {
        HStack(spacing: 6) {
            // Online/Offline status dot
            Circle()
                .fill(offlineSyncMode ? Color.orange : Color.appTeal)
                .frame(width: 6, height: 6)
            Text(offlineSyncMode ? L.Dashboard.offlineMode.t : L.Dashboard.systemOnline.t)
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

            Text("v3.0")
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
                    if staff.roleName == "Store Owner" {
                        Circle()
                            .fill(LinearGradient(colors: [Color(hex: "8A2387"), Color(hex: "E94057"), Color(hex: "F27121")], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 28, height: 28)
                        Image(systemName: "crown.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.white)
                    } else {
                        Circle()
                            .fill(Color.appAccent.opacity(0.18))
                            .frame(width: 28, height: 28)
                        Text(staffInitials(staff.displayName))
                            .font(.system(size: 10, weight: .black))
                            .foregroundColor(.appAccent)
                    }
                }

                // Name + role
                VStack(alignment: .leading, spacing: 1) {
                    Text(staff.displayName)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(staff.roleName == "Store Owner" ? "store_owner".t : staff.roleName)
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
                    withAnimation {
                        selectedTab = .inventory
                        if horizontalSizeClass == .compact {
                            columnVisibility = .detailOnly
                        }
                    }
                }
            }
        }
        .padding(.horizontal, APSpacing.sm)
        .padding(.bottom, 4)
    }

    // MARK: - Detail Content (maps tabs to views)

    @ViewBuilder
    private var detailContent: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            switch selectedTab {
            // Overview
            case .dashboard:     LiveDashboardView()
            case .notifications: NotificationCenterView()
            // Operations
            case .tables:        TableView(selectedTab: $selectedTab, activeSession: $posTableSession, columnVisibility: $columnVisibility)
            case .pos:           POSView(activeSession: $posTableSession, selectedTab: $selectedTab, columnVisibility: $columnVisibility)
            case .kitchen:       KitchenDisplayView()
            case .inventory:     InventoryView()
            // Management
            case .cashDrawer:    CashDrawerManagementView()
            case .payments:      PaymentGatewayView()
            case .reports:       ReportsView()
            case .sales:         SalesDashboardView()
            case .promotions:    PromotionsManagementView(columnVisibility: $columnVisibility)
            case .loyalty:       CustomerValueManagementView(initialSection: .loyalty)
            case .giftCards:     CustomerValueManagementView(initialSection: .giftCards)
            // People
            case .customers:     CustomerCRMView()
            case .payroll:       PayrollDashboardView()
            case .timecard:      EmployeeTimecardView()
            // Enterprise
            case .store:         StoreManagementView()
            case .devices:       DeviceManagementView()
            case .organization:  OrganizationManagementView()
            // System
            case .syncHealth:    SyncHealthView()
            case .settings:      SettingsView()
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
