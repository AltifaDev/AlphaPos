// MainDashboardView.swift
// AlphaPos — Enterprise Premium Sidebar Navigation (v3.0)
// Redesigned: 5-group enterprise sidebar with Live Dashboard,
// Notification Center, Customer CRM, Device Management, Organization

import SwiftUI
import SwiftData
import Combine


struct MainDashboardView: View {
    @AppStorage("app_text_size") private var appTextSize = AppTextSize.system.rawValue
    @Environment(\.modelContext) private var modelContext
    // รับ LocalizationManager จาก App.swift → trigger re-render เมื่อภาษาเปลี่ยน
    @EnvironmentObject private var lm: LocalizationManager
    @EnvironmentObject private var sessionManager: AppSessionManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage("app_theme") private var appTheme = AppTheme.dark.rawValue
    @AppStorage(BranchContext.storageKey) private var activeBranchId = ""
    @AppStorage("enable_table_system") private var enableTableSystem = true
    @AppStorage("developer_mode_enabled") private var developerModeEnabled = false
    @AppStorage("staff_session_timeout_minutes") private var staffSessionTimeoutMinutes = 15
    @AppStorage("offline_sync_mode") private var offlineSyncMode = false
    @State private var selectedTab: DashboardTab = .dashboard
    @State private var navigationPath = NavigationPath()
    @State private var restoreOffer: CloudBackupManifest?
    @State private var showRestoreOffer = false
    @State private var restoreOfferMessage: String?
    @State private var posTableSession: TableSession? = nil
    @State private var focusedPOSOrderNumber: String? = nil
    @State private var posQuickOrderMode = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var brandGlow = false
    @State private var showSetupChecklist = false
    @State private var setupChecklistItems: [StoreSetupChecklist.Item] = []
    @State private var showDeferredOwnerPinSetup = false
    @State private var showSubscriptionPaywall = false
    @State private var showAttendanceModal = false
    @State private var showTopBarHelp = false
    @State private var showPaymentCorrections = false
    // The sidebar only renders low-stock warnings. Materializing the complete
    // inventory catalogue here made every tab pay that cost.
    @Query(
        filter: #Predicate<InventoryItem> {
            !$0.isDeleted && $0.currentQuantity <= $0.reorderLevel
        },
        sort: \InventoryItem.name
    ) private var lowStockInventoryItems: [InventoryItem]
    @Query(filter: #Predicate<Order> {
        !$0.isDeleted && $0.orderType != "dine_in" &&
        $0.status != "completed" && $0.status != "cancelled"
    }) private var pendingQuickOrders: [Order]
    @ObservedObject private var syncEngine = SyncEngine.shared

    // Manual connect/cancel prevents timer leak when view leaves hierarchy
    private let syncTimer = Timer.publish(every: 30.0, on: .main, in: .common)
    private let timeoutTimer = Timer.publish(every: 15.0, on: .main, in: .common)
    @State private var syncTimerCancellable: Cancellable? = nil
    @State private var timeoutTimerCancellable: Cancellable? = nil
    @State private var deferredPOSSyncTask: Task<Void, Never>? = nil


    private var visibleTabs: [DashboardTab] {
        DashboardTab.allCases.filter { tab in
            if tab == .syncHealth && offlineSyncMode {
                return false
            }
            if tab == .tables {
                return enableTableSystem && canAccess(tab)
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
        case billHistory    = "Bill History"
        case expenses       = "Expenses"             // NEW: Expense & Asset Register
        case reports        = "Reports"
        case sales          = "Accounting"
        case promotions     = "Marketing"
        case loyalty        = "Loyalty"
        case giftCards      = "Gift Cards"
        // ── Group 4: People ───────────────────────────────────────────────
        case customers      = "Customers"            // NEW: Customer CRM
        case employees      = "Employees"            // Unified HR workspace
        case payroll        = "Payroll"              // Legacy deep link → Employee hub
        case timecard       = "Timecard"             // Legacy deep link → Employee hub
        // ── Group 5: Enterprise ───────────────────────────────────────────
        case store          = "Stores"
        case devices        = "Devices"              // NEW: Device Management
        case organization   = "Organization"         // NEW: Tenant Management
        // ── Group 6: System ───────────────────────────────────────────────
        case syncHealth     = "Integrations"
        case settings       = "Settings"

        // Customer profiles, loyalty and gift cards live in one workspace.
        // Payroll + Timecard live under Employees. Keep legacy cases for deep links.
        static var allCases: [DashboardTab] {
            [.dashboard, .notifications,
             .tables, .pos, .kitchen, .inventory,
             .cashDrawer, .payments, .billHistory, .expenses, .reports, .sales, .promotions,
             .customers, .employees,
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
            case .cashDrawer, .payments, .billHistory, .expenses, .reports, .sales, .promotions, .loyalty, .giftCards:
                return .management
            case .customers, .employees, .payroll, .timecard:
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
            case .kitchen:       return .none
            case .dashboard:     return .new
            case .notifications: return .new
            case .customers:     return .new
            case .employees:     return .new
            case .devices:       return .new
            case .organization:  return .new
            case .payments:      return .new
            case .expenses:      return .new
            default:             return .none
            }
        }

        /// ชื่อที่แปลแล้วตามภาษาปัจจุบัน
        var localizedName: String {
            switch self {
            case .dashboard:     return "dashboard_nav".t
            case .notifications: return "notifications_nav".t
            case .tables:        return L.Nav.tabTables.t
            case .pos:
                // This destination is the tableless counter-order workflow.
                // Keep its name stable so it cannot be confused with the
                // separate Table Management destination when that feature is on.
                return LocalizationManager.shared.currentLanguage == .thai ? "ออเดอร์ด่วน" : "Quick Order"
            case .kitchen:       return L.Nav.tabKitchen.t
            case .inventory:     return L.Nav.tabInventory.t
            case .cashDrawer:    return L.Nav.tabCashDrawer.t
            case .payments:      return "payments_nav".t
            case .billHistory:   return LocalizationManager.shared.currentLanguage == .thai ? "ประวัติบิล" : "Bill History"
            case .expenses:      return LocalizationManager.shared.currentLanguage == .thai ? "ค่าใช้จ่ายและสินทรัพย์" : "Expenses & Assets"
            case .reports:       return L.Nav.tabReports.t
            case .sales:         return L.Nav.tabSales.t
            case .promotions:    return L.Nav.tabPromotions.t
            case .loyalty:       return "customer_value_title".t
            case .giftCards:     return L.Nav.tabGiftCards.t
            case .customers:     return "customers_nav".t
            case .employees:     return "employees_nav".t
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
            case .billHistory:   return "doc.text.magnifyingglass"
            case .expenses:      return "banknote.fill"
            case .reports:       return "chart.bar.fill"
            case .sales:         return "chart.line.uptrend.xyaxis"
            case .promotions:    return "megaphone.fill"
            case .loyalty:       return "person.crop.circle.badge.checkmark"
            case .giftCards:     return "giftcard.fill"
            case .customers:     return "person.2.fill"                  // Customer CRM
            case .employees:     return "person.badge.shield.checkmark.fill"
            case .payroll:       return "banknote"
            case .timecard:      return "clock.badge.checkmark"
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
            case .billHistory:   return LinearGradient(colors: [Color(hex: "F97316"), Color(hex: "EF4444")], startPoint: .leading, endPoint: .trailing)
            case .expenses:      return LinearGradient(colors: [Color(hex: "F59E0B"), Color(hex: "D97706")], startPoint: .leading, endPoint: .trailing)
            case .reports:       return LinearGradient(colors: [Color(hex: "06B6D4"), Color(hex: "3B82F6")], startPoint: .leading, endPoint: .trailing)
            case .sales:         return LinearGradient(colors: [Color(hex: "8B5CF6"), Color(hex: "D946EF")], startPoint: .leading, endPoint: .trailing)
            case .promotions:    return LinearGradient(colors: [Color(hex: "10B981"), Color(hex: "34D399")], startPoint: .leading, endPoint: .trailing)
            case .loyalty:       return LinearGradient(colors: [Color(hex: "A78BFA"), Color(hex: "F59E0B")], startPoint: .leading, endPoint: .trailing)
            case .giftCards:     return LinearGradient(colors: [Color(hex: "F59E0B"), Color(hex: "F97316")], startPoint: .leading, endPoint: .trailing)
            case .customers:     return LinearGradient(colors: [Color(hex: "EC4899"), Color(hex: "F43F5E")], startPoint: .leading, endPoint: .trailing)
            case .employees:     return LinearGradient(colors: [Color(hex: "0F766E"), Color(hex: "334155")], startPoint: .leading, endPoint: .trailing)
            case .payroll:       return LinearGradient(colors: [Color(hex: "0F766E"), Color(hex: "334155")], startPoint: .leading, endPoint: .trailing)
            case .timecard:      return LinearGradient(colors: [Color(hex: "0F766E"), Color(hex: "334155")], startPoint: .leading, endPoint: .trailing)
            case .store:         return LinearGradient(colors: [Color(hex: "0F766E"), Color(hex: "14B8A6")], startPoint: .leading, endPoint: .trailing)
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
            case .billHistory:   return Color(hex: "F97316")
            case .expenses:      return Color(hex: "F59E0B")
            case .reports:       return Color(hex: "06B6D4")
            case .sales:         return Color(hex: "8B5CF6")
            case .promotions:    return Color(hex: "10B981")
            case .loyalty:       return Color(hex: "A78BFA")
            case .giftCards:     return Color(hex: "F59E0B")
            case .customers:     return Color(hex: "EC4899")
            case .employees:     return Color(hex: "0F766E")
            case .payroll:       return Color(hex: "0F766E")
            case .timecard:      return Color(hex: "334155")
            case .store:         return Color(hex: "0F766E")
            case .devices:       return Color(hex: "14B8A6")
            case .organization:  return Color(hex: "6366F1")
            case .syncHealth:    return Color(hex: "22C55E")
            case .settings:      return Color(hex: "9CA3AF")
            }
        }

        var requiredPermission: AppPermission {
            switch self {
            case .dashboard:     return .dashboardView
            case .notifications: return .notificationsView
            case .tables:        return .tablesManage
            case .pos:           return .posSell
            case .kitchen:       return .kitchenView
            case .inventory:     return .inventoryView
            case .cashDrawer:    return .cashDrawerManage
            case .payments:      return .paymentsManage
            case .billHistory:   return .accountingView
            case .expenses:      return .expensesManage
            case .reports:       return .reportsView
            case .sales:         return .accountingView
            case .promotions:    return .promotionsManage
            case .loyalty:       return .customersManage

            case .giftCards:     return .customersManage
            case .customers:     return .customersManage
            case .employees:     return .staffManage
            case .payroll:       return .payrollManage
            case .timecard:      return .posSell
            case .store:         return .settingsManage
            case .devices:       return .devicesView
            case .organization:  return .organizationView
            case .syncHealth:    return .deviceManage
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

    private var restoreOfferAlertPresented: Binding<Bool> {
        Binding(
            get: { restoreOfferMessage != nil },
            set: { isPresented in
                if !isPresented {
                    restoreOfferMessage = nil
                }
            }
        )
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                sidebarContent
                    .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 260)
            } detail: {
                NavigationStack(path: $navigationPath) {
                    detailContent
                }
                .toolbar(.visible, for: .navigationBar)
                .toolbar {
                    if canAccess(.timecard) {
                        ToolbarItem(placement: .topBarTrailing) {
                            attendanceToolbarButton
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                APHaptic.trigger()
                                showPaymentCorrections = true
                            } label: {
                                Image(systemName: "arrow.triangle.2.circlepath.circle")
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.circle)
                            .accessibilityLabel("แก้ไขช่องทางชำระเงิน")
                            .accessibilityHint("เปิดรายการบิลที่ชำระแล้วเพื่อแก้ไขช่องทางชำระเงิน")
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                APHaptic.trigger()
                                showTopBarHelp = true
                            } label: {
                                Image(systemName: "questionmark.circle")
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.circle)
                            .accessibilityLabel("คำอธิบายปุ่มแถบด้านบน")
                        }
                    }
                }
            }

            // Setup assistance belongs on the overview. It must never cover
            // operational tables such as inventory, counts, or purchasing.
            if selectedTab == .dashboard && showSetupChecklist && !setupChecklistItems.isEmpty {
                StoreSetupChecklistView(
                    items: setupChecklistItems,
                    onSelect: handleSetupChecklistSelect,
                    onDismiss: dismissSetupChecklist,
                    onSkipProfile: skipSetupProfile
                )
                .frame(maxWidth: 420)
                .fixedSize(horizontal: false, vertical: true)
                .padding(20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(50)
                // Card only — do not let an invisible ZStack layer eat taps across the detail pane.
                .allowsHitTesting(true)
            }

        }
        .overlay {
            ActivityTouchForwarder {
                sessionManager.touchActivity()
            }
        }
        .sheet(isPresented: $showAttendanceModal) {
            NavigationStack {
                StaffAttendanceKioskView()
                    .navigationTitle("ลงเวลาพนักงาน")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("เสร็จสิ้น") { showAttendanceModal = false }
                        }
                    }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .modelContext(modelContext)
        }
        .sheet(isPresented: $showTopBarHelp) {
            TopBarHelpSheet(isThai: lm.currentLanguage == .thai)
        }
        .sheet(isPresented: $showPaymentCorrections) {
            PaymentCorrectionOrdersSheet()
        }
        .task(id: activeMerchantIdForBackupOffer) {
            await checkForCloudRestoreOffer()
        }
        .confirmationDialog("พบข้อมูลสำรองของร้าน", isPresented: $showRestoreOffer) {
            Button("กู้คืนข้อมูล") {
                if let restoreOffer {
                    Task { await stageCloudRestore(restoreOffer) }
                }
            }
            Button("ใช้ข้อมูลในเครื่องต่อ") {
                markRestoreOfferHandled()
            }
            Button("ยกเลิก", role: .cancel) {}
        } message: {
            if let restoreOffer {
                Text("Backup วันที่ \(restoreOffer.createdAt.formatted(date: .abbreviated, time: .shortened)) • App \(restoreOffer.appVersion) • \(restoreOffer.recordCounts.values.reduce(0, +)) รายการ")
            }
        }
        .alert("Cloud Restore", isPresented: restoreOfferAlertPresented) {
            Button("ตกลง", role: .cancel) {}
        } message: {
            Text(restoreOfferMessage ?? "")
        }
        .apColorScheme()
        .fullScreenCover(isPresented: $showDeferredOwnerPinSetup) {
            OwnerSetupView(
                initialDisplayName: UserDefaults.standard.string(forKey: "logged_in_name") ?? "",
                showMfaSoftPrompt: false,
                onFinished: { displayName, _ in
                    if !displayName.isEmpty {
                        UserDefaults.standard.set(displayName, forKey: "logged_in_name")
                    }
                    let mid = MerchantAuthManager.shared.merchantId
                        ?? UserDefaults.standard.string(forKey: "active_merchant_id")
                        ?? ""
                    if !mid.isEmpty {
                        MerchantOnboardingGate.markCompleted(.ownerPin, for: mid)
                    }
                    showDeferredOwnerPinSetup = false
                    refreshSetupChecklist()
                }
            )
        }
        .sheet(isPresented: $showSubscriptionPaywall) {
            NavigationStack {
                SubscriptionSettingsView()
            }
        }
        .onReceive(timeoutTimer) { _ in
            enforceStaffSessionTimeout()
        }
        .onReceive(syncTimer) { _ in
            // Offline Quick Service is local-first. Do not run the full sync
            // orchestration (and its maintenance scans) from a main-run-loop
            // timer while the operator is navigating or taking an order.
            guard !offlineSyncMode else { return }
            requestPeriodicSync()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openTableNotification)) { notification in
            guard let tableNumber = notification.userInfo?["table_number"] as? String else { return }
            let descriptor = FetchDescriptor<RestaurantTable>(
                predicate: #Predicate<RestaurantTable> { $0.tableNumber == tableNumber }
            )
            if let tables = try? modelContext.fetch(descriptor), let table = tables.first {
                if let activeSession = table.sessions.first(where: { $0.isActive }) {
                    self.posTableSession = activeSession
                    self.posQuickOrderMode = false
                    self.selectedTab = .pos
                } else {
                    self.selectedTab = .tables
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openOrderNotification)) { notification in
            let orderNumber = notification.userInfo?["order_number"] as? String
            let tableNumber = notification.userInfo?["table_number"] as? String

            var matchedOrder: Order?
            if let orderNumber {
                var descriptor = FetchDescriptor<Order>(
                    predicate: #Predicate<Order> {
                        $0.orderNumber == orderNumber && !$0.isDeleted
                    }
                )
                descriptor.fetchLimit = 1
                matchedOrder = try? modelContext.fetch(descriptor).first
            }

            // Remote Quick Orders are queued independently. Do not navigate
            // away from a table that is currently being edited.
            let isQuickOrder = (matchedOrder?.isQuickServiceOrder ?? false)
                || tableNumber?.uppercased() == "QUICK"
            if isQuickOrder && posTableSession != nil {
                return
            }

            if let activeSession = matchedOrder?.tableSession,
               activeSession.isActive,
               !activeSession.isDeleted {
                posTableSession = activeSession
                posQuickOrderMode = false
                focusedPOSOrderNumber = orderNumber
                selectedTab = .pos
                columnVisibility = .detailOnly
                return
            }

            if let tableNumber {
                let descriptor = FetchDescriptor<RestaurantTable>(
                    predicate: #Predicate<RestaurantTable> {
                        $0.tableNumber == tableNumber
                    }
                )
                if let table = try? modelContext.fetch(descriptor).first,
                   let activeSession = table.sessions.first(where: {
                       $0.isActive && !$0.isDeleted
                   }) {
                   posTableSession = activeSession
                    posQuickOrderMode = false
                   focusedPOSOrderNumber = orderNumber
                    selectedTab = .pos
                    columnVisibility = .detailOnly
                    return
                }
            }

            // Counter/quick/orphaned web orders legitimately may not have an
            // active table. Open POS and present the exact persisted order.
            posTableSession = nil
            posQuickOrderMode = (matchedOrder.map { $0.orderType != "dine_in" } ?? false)
                || tableNumber?.uppercased() == "QUICK"
            focusedPOSOrderNumber = orderNumber
            selectedTab = .pos
            columnVisibility = .detailOnly
        }
        .onReceive(NotificationCenter.default.publisher(for: .openInventoryItemNotification)) { notification in
            guard canAccess(.inventory) else { return }
            if let itemId = notification.userInfo?["inventory_item_id"] as? String {
                UserDefaults.standard.set(itemId, forKey: "pending_inventory_focus_id")
            }
            withAnimation {
                selectedTab = .inventory
                columnVisibility = .detailOnly
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openPaymentsNotification)) { _ in
            guard canAccess(.payments) else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = .payments
                columnVisibility = .detailOnly
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFirstProductGuideNotification)) { _ in
            guard canAccess(.inventory) else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = .inventory
                columnVisibility = .detailOnly
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openAddFirstTableNotification)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = .tables
                columnVisibility = .detailOnly
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openPOSTabNotification)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = .pos
                columnVisibility = .detailOnly
            }
        }
        // A table session and Quick Order are mutually exclusive POS contexts.
        // Keep the table context authoritative while SwiftUI is switching tabs;
        // otherwise a stale Quick Order flag can make POS clear the table cart.
        .onChange(of: posTableSession?.id) { _, newSessionID in
            if newSessionID != nil, posQuickOrderMode {
                posQuickOrderMode = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .reopenStoreSetupChecklistNotification)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = .dashboard
            }
            refreshSetupChecklist()
        }
        .onAppear {
            ensureSelectedTabIsAllowed()
            syncTimerCancellable = syncTimer.connect()
            timeoutTimerCancellable = timeoutTimer.connect()
            refreshSetupChecklist()
            if StoreSetupChecklist.isTrialExpired {
                showSubscriptionPaywall = true
            }
        }
        .onDisappear {
            syncTimerCancellable?.cancel()
            syncTimerCancellable = nil
            timeoutTimerCancellable?.cancel()
            timeoutTimerCancellable = nil
            deferredPOSSyncTask?.cancel()
            deferredPOSSyncTask = nil
        }
        .onChange(of: enableTableSystem) { _, enabled in
            // Feature visibility changes must not eject the operator from POS.
            // POS supports Quick Order with no table session; Table Management
            // is simply removed when table service is disabled.
            ensureSelectedTabIsAllowed()
        }
        .onChange(of: sessionManager.currentStaffSession) { _, _ in
            ensureSelectedTabIsAllowed()
        }
        .onChange(of: selectedTab) { _, _ in
            // Programmatic navigation (alerts, notifications, sheets, etc.) must
            // obey the same feature flags and staff permissions as the sidebar.
            // Without this guard a hidden destination could still be opened by
            // assigning `selectedTab` directly.
            ensureSelectedTabIsAllowed()
            navigationPath = NavigationPath()
            refreshSetupChecklist()
        }
    }

    private var attendanceToolbarButton: some View {
        Button {
            APHaptic.trigger()
            showAttendanceModal = true
        } label: {
            Image(systemName: "faceid")
                .font(.system(size: 17, weight: .semibold))
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .accessibilityLabel("ลงเวลาพนักงาน")
        .accessibilityHint("เปิดหน้าต่างสแกนใบหน้าเพื่อเข้างานหรือออกงาน")
    }

    private var activeMerchantIdForBackupOffer: String {
        UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
    }

    private func checkForCloudRestoreOffer() async {
        await Task.yield()
        let merchantId = activeMerchantIdForBackupOffer.lowercased()
        guard !merchantId.isEmpty,
              UserDefaults.standard.string(forKey: "cloud_restore_offer_handled_merchant") != merchantId else { return }
        do {
            if let manifest = try await CloudBackupManager.shared.fetchLatestBackup() {
                restoreOffer = manifest
                showRestoreOffer = true
            } else {
                markRestoreOfferHandled()
            }
        } catch {
            // Login must never be blocked merely because Backup discovery is
            // unavailable. The user can retry from Settings.
        }
    }

    private func stageCloudRestore(_ manifest: CloudBackupManifest) async {
        do {
            try await CloudBackupManager.shared.stageRestore(manifest)
            markRestoreOfferHandled()
            restoreOfferMessage = "ตรวจสอบ Backup สำเร็จแล้ว กรุณาปิด AlphaPos จาก App Switcher และเปิดใหม่เพื่อใช้ข้อมูลที่กู้คืน"
        } catch {
            restoreOfferMessage = error.localizedDescription
        }
    }

    private func markRestoreOfferHandled() {
        UserDefaults.standard.set(activeMerchantIdForBackupOffer.lowercased(), forKey: "cloud_restore_offer_handled_merchant")
    }

    // MARK: - Store setup checklist (Phase 4)

    private func refreshSetupChecklist() {
        let items = StoreSetupChecklist.incompleteItems(modelContext: modelContext)
        setupChecklistItems = items
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            showSetupChecklist = StoreSetupChecklist.shouldShowBanner(items: items)
        }
    }

    private func dismissSetupChecklist() {
        let mid = MerchantAuthManager.shared.merchantId
            ?? UserDefaults.standard.string(forKey: "active_merchant_id")
            ?? ""
        StoreSetupChecklist.dismiss(for: mid)
        withAnimation {
            showSetupChecklist = StoreSetupChecklist.shouldShowBanner(modelContext: modelContext)
            setupChecklistItems = StoreSetupChecklist.incompleteItems(modelContext: modelContext)
        }
    }

    private func skipSetupProfile() {
        let mid = MerchantAuthManager.shared.merchantId
            ?? UserDefaults.standard.string(forKey: "active_merchant_id")
            ?? ""
        StoreSetupChecklist.skipProfile(for: mid)
        refreshSetupChecklist()
    }

    private func handleSetupChecklistSelect(_ item: StoreSetupChecklist.Item) {
        switch item {
        case .firstMenuItem:
            StoreSetupChecklist.requestFirstProductGuide()
            withAnimation { selectedTab = .inventory }
        case .firstTable:
            StoreSetupChecklist.requestAddFirstTable()
            withAnimation { selectedTab = .tables }
        case .ownerPin:
            showDeferredOwnerPinSetup = true
        case .openShift:
            withAnimation { selectedTab = enableTableSystem ? .tables : .pos }
        case .shopProfile:
            withAnimation { selectedTab = .organization }
        case .activatePlan:
            showSubscriptionPaywall = true
        }
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebarContent: some View {
        ZStack {
            // Keep navigation chrome visually separate from the content layer.
            // Xcode 27 automatically renders this material with the refreshed
            // Liquid Glass diffusion and edge treatment on iPadOS 27.
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 0.5)
                }
                .ignoresSafeArea()

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
                    .padding(.top, APSpacing.xs)
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
        .appTextSize(AppTextSize(rawValue: appTextSize) ?? .system)
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundColor(.textTertiary)
                .tracking(1.2)
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    private func canAccess(_ tab: DashboardTab) -> Bool {
        guard sessionManager.currentStaffSession != nil else { return false }
        if tab == .employees {
            return sessionManager.can(.staffManage) || sessionManager.can(.payrollManage)
        }
        return sessionManager.can(tab.requiredPermission)
    }

    private func ensureSelectedTabIsAllowed() {
        // When table system is enabled, .pos serves as the order-taking screen for tables.
        // It is hidden from the sidebar list but allowed for programmatic navigation.
        if selectedTab == .pos && canAccess(.pos) {
            return
        }

        guard !visibleTabs.contains(selectedTab) else { return }

        // POS is available independently from Table Management. Table Service
        // and Quick Order are modes inside POS, so a table-enabled merchant can
        // still take counter orders without opening a table session.
        if visibleTabs.contains(.pos) {
            selectedTab = .pos
        } else if visibleTabs.contains(.tables) {
            selectedTab = .tables
        } else if let first = visibleTabs.first {
            selectedTab = first
        }
    }

    private func enforceStaffSessionTimeout() {
        guard let session = sessionManager.currentStaffSession else { return }
        // PIN unlock remains local-first. Once background sync applies a remote
        // revocation/deactivation, end the local session on the next guard tick.
        let ownerId = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        if session.employeeId != ownerId {
            let employeeId = session.employeeId
            let descriptor = FetchDescriptor<Employee>(
                predicate: #Predicate<Employee> { employee in
                    employee.id == employeeId
                }
            )
            let employee = (try? modelContext.fetch(descriptor))?.first
            if employee == nil || employee?.isDeleted == true || employee?.resignedAt != nil ||
                employee?.user?.isActive == false || employee?.user?.isDeleted == true {
                sessionManager.lockStaffSession(modelContext: modelContext, reason: "credential_revoked")
                return
            }
            if PermissionService.permissions(for: employee?.user?.role) != session.permissions {
                sessionManager.lockStaffSession(modelContext: modelContext, reason: "permissions_changed")
                return
            }
        }
        let timeout = TimeInterval(max(1, staffSessionTimeoutMinutes) * 60)
        // Idle-based timeout: inactivity, not wall-clock since unlock.
        if Date().timeIntervalSince(sessionManager.lastActivityAt) >= timeout {
            sessionManager.lockStaffSession(modelContext: modelContext, reason: "session_timeout")
        }
    }

    /// Full SyncEngine reconciliation is MainActor-isolated because it mutates
    /// the live SwiftData context. Starting it from a run-loop timer while the
    /// cashier is touching the Order screen can consume several frame budgets
    /// and surface as "System gesture gate timed out". Keep realtime delivery
    /// active, but defer the periodic full scan until the operator has paused.
    private func requestPeriodicSync() {
        let interactionGrace: TimeInterval = 1.5
        let isTakingOrder = selectedTab == .pos

        // Realtime delivery already keeps the live dashboard current. A full
        // reconciliation changes many observed SwiftData collections and can
        // repeatedly restart KPI aggregation on the main actor. Run that scan
        // from operational/management screens instead of underneath Dashboard.
        guard selectedTab != .dashboard else { return }

        guard isTakingOrder,
              Date().timeIntervalSince(sessionManager.lastActivityAt) < interactionGrace else {
            Task { await SyncEngine.shared.syncAll(modelContext: modelContext) }
            return
        }

        guard deferredPOSSyncTask == nil else { return }
        deferredPOSSyncTask = Task { @MainActor in
            defer { deferredPOSSyncTask = nil }
            while !Task.isCancelled {
                let remaining = interactionGrace - Date().timeIntervalSince(sessionManager.lastActivityAt)
                if selectedTab != .pos || remaining <= 0 {
                    await SyncEngine.shared.syncAll(modelContext: modelContext)
                    return
                }
                try? await Task.sleep(for: .milliseconds(max(100, Int(remaining * 1_000))))
            }
        }
    }

    private var brandHeader: some View {
        HStack(spacing: 10) {
            Image("AppLogoMark")
                .resizable()
                .scaledToFill()
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.55), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .offset(x: brandGlow ? 26 : -26)
                    .blendMode(.screen)
                    .mask(Image("AppLogoMark").resizable().scaledToFill())
                }
                .shadow(
                    color: Color.appAccent.opacity(brandGlow ? 0.55 : 0.25),
                    radius: brandGlow ? 8 : 4,
                    x: brandGlow ? 2 : -1,
                    y: 2
                )

            VStack(alignment: .leading, spacing: 1) {
                Text("AlphaPos")
                    .font(.system(size: 15, weight: .black))
                    .foregroundColor(.textPrimary)
                    .overlay {
                        LinearGradient(
                            colors: [.clear, Color.appAccent.opacity(0.75), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .offset(x: brandGlow ? 42 : -42)
                        .mask(Text("AlphaPos").font(.system(size: 15, weight: .black)))
                    }
                    .shadow(
                        color: Color.appAccent.opacity(brandGlow ? 0.28 : 0.08),
                        radius: brandGlow ? 4 : 1,
                        x: brandGlow ? 1 : -1,
                        y: 1
                    )
                Text(L.Dashboard.restaurantManagement.t)
                    .font(.system(size: 8.5))
                    .foregroundColor(.textSecondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, APSpacing.sm)
        .padding(.top, -6)
        .padding(.bottom, 2)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                brandGlow = true
            }
        }
    }

    // MARK: - Sidebar Row Helper
    private func isSidebarTabSelected(_ tab: DashboardTab) -> Bool {
        if enableTableSystem {
            // เมื่อเปิดระบบโต๊ะ:
            // 1. ถ้ามี active table session อยู่ (กำลังสั่งอาหารให้โต๊ะ)
            //    ให้ไฮไลต์อยู่ที่แท็บ .tables ("โต๊ะ") เสมอ ไม่กระโดดไปไฮไลต์ที่ .pos ("ออเดอร์ด่วน")
            if posTableSession != nil {
                return tab == .tables
            }
            // 2. ถ้าอยู่ในหน้า POS โดยไม่มี table session (โหมดออเดอร์ด่วน)
            //    ให้ไฮไลต์ที่แท็บ .pos ("ออเดอร์ด่วน")
            if selectedTab == .pos {
                return tab == .pos
            }
            return selectedTab == tab
        } else {
            return selectedTab == tab
        }
    }

    private func sidebarRow(_ tab: DashboardTab) -> some View {
        SidebarTabRow(
            tab: tab,
            isSelected: isSidebarTabSelected(tab),
            quickOrderCount: pendingQuickOrders.count
        )
            .onTapGesture {
                sessionManager.touchActivity()
                let selectTab = {
                    if tab == .pos {
                        // แตะแท็บ "ออเดอร์ด่วน" จากแถบข้าง เข้าสู่โหมดออเดอร์ด่วน / คิว iPhone
                        posTableSession = nil
                        posQuickOrderMode = true
                    } else if tab == .tables {
                        // แตะแท็บ "โต๊ะ" กลับมาดูผังโต๊ะ
                        posQuickOrderMode = false
                    }
                    if selectedTab == tab {
                        navigationPath = NavigationPath()
                    } else {
                        navigationPath = NavigationPath()
                        selectedTab = tab
                    }
                }

                if UIDevice.current.userInterfaceIdiom == .pad {
                    // Resizing a NavigationSplitView while a Charts canvas is
                    // leaving the hierarchy can make Charts interpolate an
                    // invalid path and trap inside CanvasDisplayList. Keep the
                    // stable two-column iPad layout and switch content without
                    // an animated geometry transition.
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { selectTab() }
                } else {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectTab()
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
                if syncEngine.syncStatus == .error {
                    Text(syncStatusText)
                        .font(.system(size: 8))
                        .foregroundColor(.textTertiary)
                        .lineLimit(1)
                } else if syncEngine.hadSoftSyncFailures {
                    Text("sync_partial_short".t)
                        .font(.system(size: 8))
                        .foregroundColor(.textTertiary)
                        .lineLimit(1)
                } else if let lastSynced = syncEngine.lastSyncedAt {
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
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(staff.roleName == "Store Owner" ? "store_owner".t : staff.roleName)
                        .font(.system(size: 8.5))
                        .foregroundColor(.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                // Lock button — compact icon (manual staff lock)
                Button {
                    APHaptic.trigger()
                    sessionManager.lockStaffSession(modelContext: modelContext, reason: "manual_lock")
                } label: {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.appAccent)
                        .frame(width: 28, height: 28)
                        .background(Color.appAccent.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("staff_lock_now".t)
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
            return syncEngine.hadSoftSyncFailures ? "exclamationmark.circle.fill" : "checkmark.circle.fill"
        case .syncing:
            return "arrow.triangle.2.circlepath"
        case .error:
            return "clock.arrow.circlepath"
        case .offline:
            return "wifi.slash"
        }
    }

    private var syncColor: Color {
        switch syncEngine.syncStatus {
        case .idle:
            return syncEngine.hadSoftSyncFailures ? Color(hex: "F59E0B") : .appTeal
        case .syncing:
            return Color.appAccent
        case .error:
            return Color(hex: "F59E0B")
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
            return "sync_retry_pending".t
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
        let branchItems = lowStockInventoryItems.filter { item in
            if let activeId = activeBranchUUID { return item.branch?.id == activeId }
            return true
        }
        let lowStockItems = branchItems

        return HStack(spacing: 6) {
            Spacer()

            // Low-stock badge (only when needed)
            if !lowStockItems.isEmpty && canAccess(.inventory) {
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
                        columnVisibility = .detailOnly
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
            if !canAccess(selectedTab) {
                ContentUnavailableView("ไม่มีสิทธิ์เข้าถึง", systemImage: "lock.shield", description: Text("กรุณาติดต่อผู้ดูแลเพื่อขอสิทธิ์สำหรับงานนี้"))
            } else {
            switch selectedTab {
            // Overview
            case .dashboard:     LiveDashboardView(columnVisibility: $columnVisibility)
            case .notifications: NotificationCenterView()
            // Operations
            case .tables:        TableView(selectedTab: $selectedTab, activeSession: $posTableSession, columnVisibility: $columnVisibility, quickOrderMode: $posQuickOrderMode)
            case .pos:           POSView(
                activeSession: $posTableSession,
                selectedTab: $selectedTab,
                columnVisibility: $columnVisibility,
                focusedOrderNumber: $focusedPOSOrderNumber,
                quickOrderMode: $posQuickOrderMode
            )
            case .kitchen:       KitchenDisplayView(columnVisibility: $columnVisibility)
            case .inventory:
                if sessionManager.can(.inventoryManage) && sessionManager.can(.productCostsView) {
                    InventoryView()
                } else {
                    OperationalStockView()
                }
            // Management
            case .cashDrawer:    CashDrawerManagementView()
            case .payments:      PaymentGatewayView(columnVisibility: $columnVisibility)
            case .billHistory:   BillHistoryView()
            case .expenses:      ExpenseTrackerView()
            case .reports:       ReportsView(columnVisibility: $columnVisibility)
            case .sales:         SalesDashboardView(columnVisibility: $columnVisibility)
            case .promotions:    PromotionsManagementView(columnVisibility: $columnVisibility)
            case .loyalty:       CustomerValueManagementView(initialSection: .loyalty)
            case .giftCards:     CustomerValueManagementView(initialSection: .giftCards)
            // People
            case .customers:     CustomerValueManagementView(initialSection: .customers)
            case .employees:     EmployeeManagementView(initialSection: .staff, columnVisibility: $columnVisibility)
            case .payroll:       EmployeeManagementView(initialSection: .payroll, columnVisibility: $columnVisibility)
            case .timecard:      EmployeeTimecardView()
            // Enterprise
            case .store:         StoreManagementView(columnVisibility: $columnVisibility)
            case .devices:       DeviceManagementView()
            case .organization:  OrganizationManagementView(columnVisibility: $columnVisibility)
            // System
            case .syncHealth:    SyncHealthView()
            case .settings:      SettingsView(columnVisibility: $columnVisibility)
            }
            }
        }
    }
}

private struct TopBarHelpSheet: View {
    @Environment(\.dismiss) private var dismiss
    let isThai: Bool

    private var items: [(String, String, String)] {
        isThai ? [
            ("faceid", "ลงเวลาพนักงาน", "สแกนใบหน้าเพื่อบันทึกเวลาเข้างานหรือออกงาน"),
            ("takeoutbag.and.cup.and.straw.fill", "คิวด่วน (กำลังทำ)", "เปิดรายการออเดอร์ Quick Service ที่กำลังดำเนินการ ไม่ใช่จำนวนแจ้งเตือน"),
            ("clock.arrow.circlepath", "ออเดอร์ล่าสุด", "แสดงคิวล่าสุดและเวลาที่บันทึกไว้เพื่ออ่านตรวจสอบเท่านั้น"),
            ("printer.fill", "เครื่องพิมพ์", "เลือกเครื่องพิมพ์และสั่งพิมพ์ใบเสร็จหรือรายการเข้าครัว"),
            ("arrow.uturn.backward", "ย้อนกลับ", "กลับไปยังหน้าหรือโต๊ะก่อนหน้าโดยไม่ลบบิลที่กำลังทำอยู่")
        ] : [
            ("faceid", "Staff attendance", "Scan a face to clock in or clock out."),
            ("takeoutbag.and.cup.and.straw.fill", "Quick queue", "Open pending Quick Service orders."),
            ("clock.arrow.circlepath", "Recent orders", "Shows the latest queue and timestamp for read-only reference."),
            ("printer.fill", "Printer", "Choose a printer and print receipts or kitchen tickets."),
            ("arrow.uturn.backward", "Back", "Return to the previous page or table without deleting the current bill.")
        ]
    }

    var body: some View {
        NavigationStack {
            List {
                Section(isThai ? "ปุ่มบนแถบการทำงาน" : "Toolbar actions") {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.1).font(.subheadline.weight(.semibold))
                                Text(item.2).font(.caption).foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: item.0).foregroundColor(.accentColor)
                        }
                        .padding(.vertical, 5)
                    }
                }
                Section(isThai ? "การแก้ไขช่องทางชำระเงิน" : "Payment corrections") {
                    Text(isThai
                         ? "เปิด ‘ออเดอร์ล่าสุด’ แล้วเลือกรายการที่ชำระแล้ว จากนั้นกด ‘แก้ไขช่องทางชำระเงิน’ ระบบจะยกเลิกรายการเดิม สร้างรายการใหม่ และบันทึกประวัติการอนุมัติ โดยไม่เปลี่ยนยอดขายรวม"
                         : "Open Recent orders, select a paid bill, then choose Correct payment method. The original payment is voided, replaced, and audited without changing total sales.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle(isThai ? "วิธีใช้ปุ่มด้านบน" : "Toolbar guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(isThai ? "เสร็จสิ้น" : "Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Sidebar Tab Row

private struct SidebarTabRow: View {
    let tab:        MainDashboardView.DashboardTab
    let isSelected: Bool
    let quickOrderCount: Int
    @State private var isHovered = false
    // LINE-style unread badge + animated bell for the Notifications tab
    @ObservedObject private var notificationStore = NotificationStore.shared
    @State private var bellWiggle = false

    /// Unread count driving the badge (only meaningful for the notifications tab)
    private var unreadCount: Int {
        tab == .notifications ? notificationStore.unreadCount : 0
    }

    private var quickOrders: Int {
        tab == .pos ? quickOrderCount : 0
    }

    var body: some View {
        HStack(spacing: 12) {
            // Icon container
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? tab.gradient : LinearGradient(colors: [Color.appSurfaceHigh], startPoint: .top, endPoint: .bottom))
                    .frame(width: 32, height: 32)
                    .shadow(color: isSelected ? tab.iconColor.opacity(0.5) : .clear, radius: 8, x: 0, y: 2)

                Image(systemName: tab.icon)
                    .font(.body.weight(.semibold))
                    .foregroundColor(isSelected ? .white : tab.iconColor.opacity(0.7))
                    // Gentle bell shake when there are unread notifications
                    .rotationEffect(.degrees(bellWiggle && (unreadCount > 0 || quickOrders > 0) ? 10 : 0), anchor: .top)
                    .animation(
                        unreadCount > 0 || quickOrders > 0
                            ? .easeInOut(duration: 0.15).repeatCount(4, autoreverses: true)
                            : .default,
                        value: bellWiggle
                    )
            }

            HStack(spacing: 6) {
                Text(tab.localizedName)
                    .font(.body)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundColor(isSelected ? .textPrimary : .textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                // Notifications tab: show a LINE-style numeric unread badge
                // (overrides the "New" badge) when there are unread alerts.
                if (tab == .notifications && unreadCount > 0) || (tab == .pos && quickOrders > 0) {
                    let count = tab == .notifications ? unreadCount : quickOrders
                    Text(count > 99 ? "99+" : "\(count)")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, unreadCount > 9 ? 5 : 0)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(tab == .notifications ? Color(hex: "EF4444") : Color.appAmber)
                        .clipShape(Capsule())
                        .shadow(color: Color(hex: "EF4444").opacity(0.45), radius: 3, x: 0, y: 1)
                } else {
                // Badge: Beta / New
                switch tab.badge {
                case .beta:
                    Text("sidebar_badge_beta".t)
                        .font(.caption2.weight(.bold))
                        .foregroundColor(.textSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.appSurfaceHigh)
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.appBorderSubtle, lineWidth: 1))
                case .new:
                    Text("sidebar_badge_new".t)
                        .font(.caption2.weight(.bold))
                        .foregroundColor(Color(hex: "854D0E"))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(hex: "FEF08A").opacity(0.9))
                        .cornerRadius(6)
                case .none:
                    EmptyView()
                }
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
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background {
            let shape = RoundedRectangle(
                cornerRadius: APChrome.controlCornerRadius,
                style: .continuous
            )
            if isSelected {
                Color.clear
                    .apSelectedChrome(tint: tab.iconColor, in: shape)
            } else if isHovered {
                shape.fill(tab.iconColor.opacity(APChrome.hoverTintOpacity))
            }
        }
        .contentShape(Rectangle())
        .scaleEffect(isHovered && !isSelected ? 0.98 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onHover { isHovered = $0 }
        // Gentle, recurring wiggle while unread alerts remain. The task is
        // keyed on unreadCount so it restarts when the count changes and is
        // automatically cancelled by SwiftUI when the row leaves the view.
        .task(id: unreadCount + quickOrders) {
            guard (tab == .notifications && unreadCount > 0) || (tab == .pos && quickOrders > 0) else { return }
            // Wiggle once immediately, then repeat every 3s as a soft reminder.
            triggerBellWiggle()
            while unreadCount > 0 {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if Task.isCancelled { break }
                triggerBellWiggle()
            }
        }
    }

    /// Plays one gentle wiggle burst (~0.7s) then settles.
    private func triggerBellWiggle() {
        bellWiggle = false
        DispatchQueue.main.async {
            bellWiggle = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { bellWiggle = false }
        }
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
