// MainDashboardView.swift
// AlphaPos — Premium Sidebar Navigation

import SwiftUI
import SwiftData
import Combine


struct MainDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("app_theme") private var appTheme = AppTheme.dark.rawValue
    @AppStorage("active_branch_id") private var activeBranchId = ""
    @AppStorage("enable_table_system") private var enableTableSystem = true
    @State private var selectedTab: DashboardTab = .tables
    @State private var posTableSession: TableSession? = nil
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @Query(sort: \InventoryItem.name) private var inventoryItems: [InventoryItem]
    @ObservedObject private var syncEngine = SyncEngine.shared
    
    private let timer = Timer.publish(every: 5.0, on: .main, in: .common).autoconnect()

    
    private var visibleTabs: [DashboardTab] {
        DashboardTab.allCases.filter { tab in
            if tab == .tables {
                return enableTableSystem
            }
            if tab == .pos {
                return !enableTableSystem
            }
            return true
        }
    }

    enum DashboardTab: String, CaseIterable, Identifiable {
        case tables     = "Tables System"
        case pos        = "POS Ordering"
        case kitchen    = "Kitchen Display"
        case timecard   = "Biometric Clock-In"
        case inventory  = "Stock Inventory"
        case payroll    = "Payroll & Shifts"
        case sales      = "Sales & Analytics"
        case promotions = "Manage Promotions"
        case store      = "Store Management"
        case settings   = "System Settings"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .tables:     return "tablecells.fill"
            case .pos:        return "cart.fill"
            case .kitchen:    return "flame.fill"
            case .timecard:   return "faceid"
            case .inventory:  return "shippingbox.fill"
            case .payroll:    return "dollarsign.circle.fill"
            case .sales:      return "chart.bar.xaxis"
            case .promotions: return "megaphone.fill"
            case .store:      return "storefront.fill"
            case .settings:   return "gearshape.fill"
            }
        }

        /// Accent gradient per tab for selected state
        var gradient: LinearGradient {
            switch self {
            case .tables:     return APGradient.accent
            case .pos:        return LinearGradient(colors: [Color(hex: "6C63FF"), Color(hex: "818CF8")], startPoint: .leading, endPoint: .trailing)
            case .kitchen:    return LinearGradient(colors: [Color(hex: "F59E0B"), Color(hex: "FB923C")], startPoint: .leading, endPoint: .trailing)
            case .timecard:   return APGradient.positive
            case .inventory:  return LinearGradient(colors: [Color(hex: "0EA5E9"), Color(hex: "6366F1")], startPoint: .leading, endPoint: .trailing)
            case .payroll:    return LinearGradient(colors: [Color(hex: "A855F7"), Color(hex: "EC4899")], startPoint: .leading, endPoint: .trailing)
            case .sales:      return LinearGradient(colors: [Color(hex: "8B5CF6"), Color(hex: "D946EF")], startPoint: .leading, endPoint: .trailing)
            case .promotions: return LinearGradient(colors: [Color(hex: "10B981"), Color(hex: "34D399")], startPoint: .leading, endPoint: .trailing)
            case .store:      return LinearGradient(colors: [Color(hex: "F43F5E"), Color(hex: "FDA4AF")], startPoint: .leading, endPoint: .trailing)
            case .settings:   return LinearGradient(colors: [Color(hex: "9CA3AF"), Color(hex: "4B5563")], startPoint: .leading, endPoint: .trailing)
            }
        }

        var iconColor: Color {
            switch self {
            case .tables:     return Color(hex: "6C63FF")
            case .pos:        return Color(hex: "818CF8")
            case .kitchen:    return Color(hex: "F59E0B")
            case .timecard:   return Color(hex: "34D399")
            case .inventory:  return Color(hex: "0EA5E9")
            case .payroll:    return Color(hex: "A855F7")
            case .sales:      return Color(hex: "8B5CF6")
            case .promotions: return Color(hex: "10B981")
            case .store:      return Color(hex: "F43F5E")
            case .settings:   return Color(hex: "9CA3AF")
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
        }
        .onAppear {
            if !enableTableSystem && selectedTab == .tables {
                selectedTab = .pos
            }
            SampleDataSeeder.autoSeedIfOutdated(modelContext: modelContext)
        }
        .onChange(of: enableTableSystem) { _, enabled in
            if enabled && selectedTab == .pos {
                selectedTab = .tables
            } else if !enabled && selectedTab == .tables {
                selectedTab = .pos
            }
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

                // ── Footer version label ─────────────────────────────────────
                sidebarFooter
            }
        }
        .listStyle(.sidebar)
    }

    private var brandHeader: some View {
        HStack(spacing: 12) {
            // Logo mark
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(APGradient.accent)
                    .frame(width: 40, height: 40)
                    .shadow(color: Color(hex: "6C63FF").opacity(0.6), radius: 10, x: 0, y: 4)
                Image(systemName: "bolt.fill")
                    .font(.system(size: 20, weight: .black))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("AlphaPos")
                    .font(.title3)
                    .fontWeight(.black)
                    .foregroundColor(.textPrimary)
                Text("Restaurant Management")
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
                Text("System Online")
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
            return Color(hex: "6C63FF")
        case .error:
            return .red
        case .offline:
            return Color(hex: "9CA3AF")
        }
    }
    
    private var syncStatusText: String {
        switch syncEngine.syncStatus {
        case .idle:
            return "Sync Success"
        case .syncing:
            return "Syncing..."
        case .error:
            return "Sync Failed"
        case .offline:
            return "Offline Mode"
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
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
                    Text("Stock Value")
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
                        Text("Low Stock Alert")
                            .font(.system(size: 8))
                            .foregroundColor(.textTertiary)
                        Text("\(lowStockItems.count) item\(lowStockItems.count > 1 ? "s" : "") below reorder level")
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
            case .kitchen:    KitchenDisplayView()
            case .timecard:   EmployeeTimecardView()
            case .inventory:  InventoryView()
            case .payroll:    PayrollDashboardView()
            case .sales:      SalesDashboardView()
            case .promotions: PromotionsManagementView(columnVisibility: $columnVisibility)
            case .store:      StoreManagementView()
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

            Text(tab.rawValue)
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
