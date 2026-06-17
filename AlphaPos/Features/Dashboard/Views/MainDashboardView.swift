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
        case tables     = "Tables System"
        case pos        = "POS Ordering"
        case cashDrawer = "Cash Drawer & Shifts"
        case kitchen    = "Kitchen Display"
        case timecard   = "Biometric Clock-In"
        case inventory  = "Stock Inventory"
        case giftCards  = "Gift Cards"
        case loyalty    = "Loyalty"
        case payroll    = "Payroll & Shifts"
        case sales      = "Sales & Analytics"
        case reports    = "Reports"
        case promotions = "Manage Promotions"
        case store      = "Store Management"
        case syncHealth = "Sync & Device Health"
        case settings   = "System Settings"

        var id: String { rawValue }

        /// ชื่อที่แปลแล้วตามภาษาปัจจุบัน — ใช้แทน rawValue ใน UI
        var localizedName: String {
            switch self {
            case .tables:     return L.Nav.tabTables.t
            case .pos:        return L.Nav.tabPOS.t
            case .cashDrawer: return L.Nav.tabCashDrawer.t
            case .kitchen:    return L.Nav.tabKitchen.t
            case .timecard:   return L.Nav.tabTimecard.t
            case .inventory:  return L.Nav.tabInventory.t
            case .giftCards:  return L.Nav.tabGiftCards.t
            case .loyalty:    return L.Nav.tabLoyalty.t
            case .payroll:    return L.Nav.tabPayroll.t
            case .sales:      return L.Nav.tabSales.t
            case .reports:    return L.Nav.tabReports.t
            case .promotions: return L.Nav.tabPromotions.t
            case .store:      return L.Nav.tabStore.t
            case .syncHealth: return L.Nav.tabSyncHealth.t
            case .settings:   return L.Nav.tabSettings.t
            }
        }

        var icon: String {
            switch self {
            case .tables:     return "tablecells.fill"
            case .pos:        return "cart.fill"
            case .cashDrawer: return "safe.fill"
            case .kitchen:    return "flame.fill"
            case .timecard:   return "faceid"
            case .inventory:  return "shippingbox.fill"
            case .giftCards:  return "giftcard.fill"
            case .loyalty:    return "star.circle.fill"
            case .payroll:    return "dollarsign.circle.fill"
            case .sales:      return "chart.bar.xaxis"
            case .reports:    return "doc.text.fill"
            case .promotions: return "megaphone.fill"
            case .store:      return "storefront.fill"
            case .syncHealth: return "waveform.path.ecg.rectangle.fill"
            case .settings:   return "gearshape.fill"
            }
        }

        /// Accent gradient per tab for selected state
        var gradient: LinearGradient {
            switch self {
            case .tables:     return APGradient.accent
            case .pos:        return LinearGradient(colors: [Color.appAccent, Color(hex: "60A5FA")], startPoint: .leading, endPoint: .trailing)
            case .cashDrawer: return LinearGradient(colors: [Color(hex: "10B981"), Color(hex: "059669")], startPoint: .leading, endPoint: .trailing)
            case .kitchen:    return LinearGradient(colors: [Color(hex: "F59E0B"), Color(hex: "FB923C")], startPoint: .leading, endPoint: .trailing)
            case .timecard:   return APGradient.positive
            case .inventory:  return LinearGradient(colors: [Color(hex: "0EA5E9"), Color(hex: "6366F1")], startPoint: .leading, endPoint: .trailing)
            case .giftCards:  return LinearGradient(colors: [Color(hex: "F59E0B"), Color(hex: "F97316")], startPoint: .leading, endPoint: .trailing)
            case .loyalty:    return LinearGradient(colors: [Color(hex: "A78BFA"), Color(hex: "F59E0B")], startPoint: .leading, endPoint: .trailing)
            case .payroll:    return LinearGradient(colors: [Color(hex: "A855F7"), Color(hex: "EC4899")], startPoint: .leading, endPoint: .trailing)
            case .sales:      return LinearGradient(colors: [Color(hex: "8B5CF6"), Color(hex: "D946EF")], startPoint: .leading, endPoint: .trailing)
            case .reports:    return LinearGradient(colors: [Color(hex: "06B6D4"), Color(hex: "3B82F6")], startPoint: .leading, endPoint: .trailing)
            case .promotions: return LinearGradient(colors: [Color(hex: "10B981"), Color(hex: "34D399")], startPoint: .leading, endPoint: .trailing)
            case .store:      return LinearGradient(colors: [Color(hex: "F43F5E"), Color(hex: "FDA4AF")], startPoint: .leading, endPoint: .trailing)
            case .syncHealth: return LinearGradient(colors: [Color(hex: "22C55E"), Color(hex: "0EA5E9")], startPoint: .leading, endPoint: .trailing)
            case .settings:   return LinearGradient(colors: [Color(hex: "9CA3AF"), Color(hex: "4B5563")], startPoint: .leading, endPoint: .trailing)
            }
        }

        var iconColor: Color {
            switch self {
            case .tables:     return Color.appAccent
            case .pos:        return Color(hex: "60A5FA")
            case .cashDrawer: return Color(hex: "10B981")
            case .kitchen:    return Color(hex: "F59E0B")
            case .timecard:   return Color(hex: "34D399")
            case .inventory:  return Color(hex: "0EA5E9")
            case .giftCards:  return Color(hex: "F59E0B")
            case .loyalty:    return Color(hex: "A78BFA")
            case .payroll:    return Color(hex: "A855F7")
            case .sales:      return Color(hex: "8B5CF6")
            case .reports:    return Color(hex: "06B6D4")
            case .promotions: return Color(hex: "10B981")
            case .store:      return Color(hex: "F43F5E")
            case .syncHealth: return Color(hex: "22C55E")
            case .settings:   return Color(hex: "9CA3AF")
            }
        }

        var requiredPermission: AppPermission {
            switch self {
            case .tables: return .tablesManage
            case .pos: return .posSell
            case .cashDrawer: return .cashDrawerManage
            case .kitchen: return .kitchenView
            case .timecard: return .posSell
            case .inventory: return .inventoryView
            case .giftCards: return .posSell
            case .loyalty: return .posSell
            case .payroll: return .payrollManage
            case .sales: return .reportsView
            case .reports: return .reportsView
            case .promotions: return .discountApply
            case .store: return .settingsManage
            case .syncHealth: return .deviceManage
            case .settings: return .settingsManage
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
                        ForEach(visibleTabs) { tab in
                            SidebarTabRow(
                                tab: tab,
                                isSelected: selectedTab == tab
                            )
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedTab = tab
                                    columnVisibility = .detailOnly
                                }
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
        HStack(spacing: 12) {
            // Logo mark
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(APGradient.accent)
                    .frame(width: 40, height: 40)
                    .shadow(color: Color.appAccent.opacity(0.6), radius: 10, x: 0, y: 4)
                Image(systemName: "bolt.fill")
                    .font(.system(size: 20, weight: .black))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("AlphaPos")
                    .font(.title3)
                    .fontWeight(.black)
                    .foregroundColor(.textPrimary)
                Text(L.Dashboard.restaurantManagement.t)
                    .font(.caption2)
                    .foregroundColor(.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, APSpacing.md)
        .padding(.vertical, APSpacing.md)
    }

    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle()
                    .fill(Color.appTeal)
                    .frame(width: 7, height: 7)
                Text(L.Dashboard.systemOnline.t)
                    .font(.caption2)
                    .foregroundColor(.textSecondary)
                Spacer()
                Text("v2.0")
                    .font(.caption2)
                    .foregroundColor(.textTertiary)
            }
            
            HStack(spacing: 5) {
                Image(systemName: syncIcon)
                    .font(.system(size: 8))
                    .foregroundColor(syncColor)
                
                Text(syncStatusText)
                    .font(.system(size: 9))
                    .foregroundColor(.textTertiary)
                
                if let lastSynced = syncEngine.lastSyncedAt {
                    Text("• \(formatTime(lastSynced))")
                        .font(.system(size: 8))
                        .foregroundColor(.textTertiary)
                }
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, APSpacing.md)
        .padding(.bottom, APSpacing.sm)
    }

    @ViewBuilder
    private var staffSessionWidget: some View {
        if let staff = sessionManager.currentStaffSession {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color.appAccent.opacity(0.18))
                            .frame(width: 34, height: 34)
                        Text(staffInitials(staff.displayName))
                            .font(.caption.weight(.black))
                            .foregroundColor(.appAccent)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(staff.displayName)
                            .font(.caption.weight(.bold))
                            .foregroundColor(.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(staff.roleName)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer()
                }

                Button {
                    APHaptic.trigger()
                    sessionManager.lockStaffSession(modelContext: modelContext)
                } label: {
                    Label("lock_register_btn".t, systemImage: "lock.fill")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.appAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.appAccent.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.appSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.appBorderSubtle, lineWidth: 1)
                    )
            )
            .padding(.horizontal, APSpacing.md)
            .padding(.bottom, APSpacing.sm)
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
            if let activeId = activeBranchUUID {
                return item.branch?.id == activeId
            }
            return true
        }
        let lowStockItems = branchItems.filter { $0.currentQuantity <= $0.reorderLevel }
        let totalValue = branchItems.reduce(0.0) { $0 + ($1.currentQuantity * $1.costPrice) }
        
        return VStack(spacing: APSpacing.xs) {
            // Stock Valuation
            HStack(spacing: 8) {
                Image(systemName: "banknote.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.appTeal)
                VStack(alignment: .leading, spacing: 1) {
                    Text(L.Dashboard.stockValue.t)
                        .font(.system(size: 8))
                        .foregroundColor(.textTertiary)
                    Text("฿\(totalValue.formatted(.number.precision(.fractionLength(0))))")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.textPrimary)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.appSurfaceHigh)
            .cornerRadius(APRadius.sm)
            
            // Low Stock Alert
            if !lowStockItems.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.appRose)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L.Dashboard.lowStockAlert.t)
                            .font(.system(size: 8))
                            .foregroundColor(.textTertiary)
                        Text(LocalizationManager.shared.t(L.Dashboard.itemsBelowReorder, lowStockItems.count))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.appRose)
                    }
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.appRose.opacity(0.08))
                .cornerRadius(APRadius.sm)
                .overlay(
                    RoundedRectangle(cornerRadius: APRadius.sm)
                        .stroke(Color.appRose.opacity(0.2), lineWidth: 1)
                )
                .onTapGesture {
                    withAnimation {
                        selectedTab = .inventory
                        columnVisibility = .detailOnly
                    }
                }
            }
        }
        .padding(.horizontal, APSpacing.sm)
        .padding(.bottom, APSpacing.sm)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailContent: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            switch selectedTab {
            case .tables:     TableView(selectedTab: $selectedTab, activeSession: $posTableSession)
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

            Text(tab.localizedName)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(isSelected ? .textPrimary : .textSecondary)

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
