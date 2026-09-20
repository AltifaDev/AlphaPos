import SwiftUI
import SwiftData
import Combine
import AudioToolbox

enum KDSStation: String, CaseIterable, Codable {
    case kitchen
    case bar

    var displayName: String {
        switch self {
        case .kitchen: return "kds_station_kitchen".t
        case .bar: return "kds_station_bar".t
        }
    }
}

/// Display-only KDS policy. Ageing a ticket never deletes sales data; it only
/// moves the ticket out of the live queue. Values are store/device settings.
enum KDSDisplayPolicy {
    static var warningMinutes: Int { max(1, UserDefaults.standard.integer(forKey: "kds_warning_minutes").nonZero(or: 15)) }
    static var delayedMinutes: Int { max(warningMinutes, UserDefaults.standard.integer(forKey: "kds_delayed_minutes").nonZero(or: 30)) }
    static var staleMinutes: Int { max(delayedMinutes, UserDefaults.standard.integer(forKey: "kds_stale_minutes").nonZero(or: 60)) }
    static var maximumLiveTickets: Int { 100 }

    static func isStale(_ order: Order, now: Date) -> Bool {
        now.timeIntervalSince(order.createdAt) >= TimeInterval(staleMinutes * 60)
    }

    static func isVisibleInLiveQueue(_ order: Order, now: Date) -> Bool {
        // Payment completion must not hide a ticket that still has cooking
        // items. Quick Orders from AlphaPosStaff may be paid immediately after
        // submission, and the KDS can otherwise miss the ticket entirely.
        // Orders with no active cooking items are removed below after station
        // routing, so completed/settled history remains out of the live queue.
        return !isStale(order, now: now)
    }
}

private extension Int {
    func nonZero(or fallback: Int) -> Int { self == 0 ? fallback : self }
}

struct KDSTicket: Identifiable, Equatable {
    let order: Order
    let station: KDSStation

    var id: String {
        "\(order.id.uuidString)-\(station.rawValue)"
    }

    static func == (lhs: KDSTicket, rhs: KDSTicket) -> Bool {
        lhs.id == rhs.id && lhs.order.updatedAt == rhs.order.updatedAt
    }
}

struct KitchenDisplayView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var lm: LocalizationManager
    @EnvironmentObject private var sessionManager: AppSessionManager
    @ObservedObject private var syncEngine = SyncEngine.shared
    @AppStorage(BranchContext.storageKey) private var activeBranchId = ""
    @AppStorage("offline_sync_mode") private var offlineSyncMode = false
    @Binding var columnVisibility: NavigationSplitViewVisibility
    // Filter in memory: the compound SwiftData predicates become prohibitively
    // expensive for the compiler now that Order.branch is a required relationship.
    @Query(sort: \Order.createdAt) private var queriedOrders: [Order]

    private var branchActiveOrders: [Order] {
        guard let branchId = UUID(uuidString: activeBranchId) else { return [] }
        return queriedOrders.filter {
            $0.branch.id == branchId &&
            ($0.status == "preparing" || $0.status == "ready" || $0.status == "completed")
        }
    }
    private var branchServedOrders: [Order] {
        guard let branchId = UUID(uuidString: activeBranchId) else { return [] }
        return queriedOrders
            .filter {
                $0.branch.id == branchId && ($0.status == "served" || $0.status == "completed")
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private let columns = [
        GridItem(.adaptive(minimum: 220), spacing: 12)
    ]

    /// Keyboard / bump-bar focus — must NOT open the detail cover.
    @State private var focusedTicket: KDSTicket? = nil
    /// Explicit ticket opened in full-screen detail.
    @State private var detailTicket: KDSTicket? = nil
    @State private var showingHelpView = false
    @State private var showingSettingsPopover = false
    @State private var showingHistoryDrawer = false
    @State private var isWide = true
    @State private var isViewAppeared = false

    init(columnVisibility: Binding<NavigationSplitViewVisibility> = .constant(.all)) {
        _columnVisibility = columnVisibility
    }

    // Search and filter states
    @State private var searchText = ""
    @State private var selectedFilter = "all"
    @AppStorage("kds_view_style") private var kdsViewStyle = "columns"
    @AppStorage("kds_show_kitchen") private var kdsShowKitchen = true
    @AppStorage("kds_show_bar") private var kdsShowBar = true
    @AppStorage("kds_auto_complete_enabled") private var kdsAutoCompleteEnabled = false
    @AppStorage("kds_sound_enabled") private var kdsSoundEnabled = true
    @AppStorage("kds_workflow_mode") private var kdsWorkflowMode = "full"
    // L-9: Physical KDS / Bump Bar — keyboard shortcut support
    @AppStorage("kds_keyboard_shortcuts_enabled") private var kdsKeyboardShortcutsEnabled = true
    @AppStorage("enable_table_system") private var tableSystemEnabled = true

    // L-7: Category-based routing — JSON: {"CategoryName": "kitchen"|"bar"|"both"}
    @AppStorage("kds_category_routing_json") private var kdsCategoryRoutingJson = "{}"

    private var categoryRouting: [String: String] {
        (try? JSONDecoder().decode([String: String].self,
             from: kdsCategoryRoutingJson.data(using: .utf8) ?? Data())) ?? [:]
    }

    private var currentActorName: String? {
        let name = sessionManager.currentStaffSession?.displayName
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? nil : name
    }

    private var canManageKitchen: Bool {
        guard let session = sessionManager.currentStaffSession else {
            return true // owner dashboard without staff lock
        }
        if session.permissions.contains(.kitchenManage)
            || session.permissions.contains(.orderVoid) {
            return true
        }
        // Legacy cook roles that only had kitchen.view before kitchen.manage existed
        return session.permissions.contains(.kitchenView)
            && !session.permissions.contains(.posSell)
    }

    // Timer for refreshing delayed status every second
    @State private var currentSecond = Date()
    @State private var previousTicketCount = 0
    // Use manual connect/cancel to prevent timer leak when view is hidden but not destroyed
    private let secondTimer = Timer.publish(every: 1, on: .main, in: .common)
    @State private var secondTimerCancellable: Cancellable? = nil

    var filteredTickets: [KDSTicket] {
        var tickets: [KDSTicket] = []
        let now = Date()
        let routing = categoryRouting  // L-7: category → station routing map

        guard kdsWorkflowMode == "full" || kdsWorkflowMode == "display_only" else { return [] }
        for order in branchActiveOrders {
            let isStale = KDSDisplayPolicy.isStale(order, now: now)
            if selectedFilter == "stale" {
                guard !order.isSettled && isStale else { continue }
            } else {
                guard KDSDisplayPolicy.isVisibleInLiveQueue(order, now: now) else { continue }
            }
            // Skip orphaned / stale tickets whose table was already cleared.
            // Covers an inactive session AND a nullified (nil) session — the
            // latter stranded ticket #9619 on screen for 1,622 minutes.
            if order.isOrphanedKitchenTicket { continue }
            // L-7: Group items by their resolved station using the shared print/KDS routing rules.
            let activeItems = order.items.filter {
                ($0.status == "cooking" || $0.status == "alert") && !$0.isDeleted
            }

            var kitchenItems: [OrderItem] = []
            var barItems: [OrderItem] = []
            for item in activeItems {
                let stations = OrderRoutingResolver.stations(for: item, routing: routing)
                if stations.contains(.kitchen) { kitchenItems.append(item) }
                if stations.contains(.bar) { barItems.append(item) }
            }

            // Respect visibility toggles
            if kdsShowKitchen && !kitchenItems.isEmpty {
                if matchesSearchAndFilter(order: order, items: kitchenItems, now: now, filter: selectedFilter) {
                    tickets.append(KDSTicket(order: order, station: .kitchen))
                }
            }
            if kdsShowBar && !barItems.isEmpty {
                if matchesSearchAndFilter(order: order, items: barItems, now: now, filter: selectedFilter) {
                    tickets.append(KDSTicket(order: order, station: .bar))
                }
            }
        }

        // Sort by order creation date (FIFO)
        return Array(tickets.sorted { $0.order.createdAt < $1.order.createdAt }
            .prefix(KDSDisplayPolicy.maximumLiveTickets))
    }

    /// Hint when SwiftData has live orders but filters/routing hide every ticket.
    private var emptyStateSubtitle: String? {
        let routing = categoryRouting
        var awaitingApproval = false
        var barOnly = false
        var hasVisibleCandidate = false

        for order in branchActiveOrders {
            if order.isOrphanedKitchenTicket { continue }
            if order.isAwaitingStaffApproval {
                awaitingApproval = true
                continue
            }
            let activeItems = order.items.filter {
                ($0.status == "cooking" || $0.status == "alert") && !$0.isDeleted
            }
            guard !activeItems.isEmpty else { continue }

            var kitchenItems: [OrderItem] = []
            var barItems: [OrderItem] = []
            for item in activeItems {
                let stations = OrderRoutingResolver.stations(for: item, routing: routing)
                if stations.contains(.kitchen) { kitchenItems.append(item) }
                if stations.contains(.bar) { barItems.append(item) }
            }

            if kdsShowKitchen && !kitchenItems.isEmpty { hasVisibleCandidate = true }
            if kdsShowBar && !barItems.isEmpty { hasVisibleCandidate = true }
            if kdsShowKitchen && kitchenItems.isEmpty && !barItems.isEmpty { barOnly = true }
        }

        if awaitingApproval { return "kds_empty_pending_approval".t }
        if barOnly && !hasVisibleCandidate { return "kds_empty_routed_to_bar".t }
        return nil
    }

    private func matchesSearchAndFilter(order: Order, items: [OrderItem], now: Date, filter: String) -> Bool {
        // 1. Search text filter
        if !searchText.isEmpty {
            let identity = OrderDisplayIdentity(order: order, tableSystemEnabled: tableSystemEnabled)
            let tableNum = identity.tableNumber ?? ""
            let queueNum = identity.queueNumber ?? ""
            let orderNum = order.orderNumber
            let matchesTable = tableNum.localizedCaseInsensitiveContains(searchText)
            let matchesQueue = queueNum.localizedCaseInsensitiveContains(searchText)
            let matchesOrder = orderNum.localizedCaseInsensitiveContains(searchText)
            let matchesItem = items.contains { $0.menuItem?.name.localizedCaseInsensitiveContains(searchText) ?? false }
            guard matchesTable || matchesQueue || matchesOrder || matchesItem else { return false }
        }

        // 2. Filter type
        switch filter {
        case "dine_in":
            return order.orderType == "dine_in"
        case "take_out":
            return order.orderType == "take_out"
        case "delayed":
            return now.timeIntervalSince(order.createdAt) >= TimeInterval(KDSDisplayPolicy.delayedMinutes * 60)
        case "stale":
            return KDSDisplayPolicy.isStale(order, now: now)
        default:
            return true
        }
    }

    var oldestDelayedOrder: Order? {
        let now = Date()
        return branchActiveOrders
            .filter { order in
                guard KDSDisplayPolicy.isVisibleInLiveQueue(order, now: now) else { return false }
                // Skip orphaned / stale tickets whose table was already cleared.
                // Covers an inactive session AND a nullified (nil) session — the
                // latter stranded ticket #9619 on screen for 1,622 minutes.
                if order.isOrphanedKitchenTicket { return false }
                let activeItems = order.items.filter { $0.status == "cooking" || $0.status == "alert" }
                let matchedItems = activeItems.filter { $0.shouldDisplay(showKitchen: kdsShowKitchen, showBar: kdsShowBar) }
                guard !matchedItems.isEmpty else { return false }

                return now.timeIntervalSince(order.createdAt) >= TimeInterval(KDSDisplayPolicy.delayedMinutes * 60)
            }
            .first
    }

    private func countForFilter(_ filter: String) -> Int {
        var count = 0
        let now = Date()
        for order in branchActiveOrders {
            let isStale = KDSDisplayPolicy.isStale(order, now: now)
            if filter == "stale" {
                guard !order.isSettled && isStale else { continue }
            } else {
                guard KDSDisplayPolicy.isVisibleInLiveQueue(order, now: now) else { continue }
            }
            // Skip orphaned / stale tickets whose table was already cleared.
            // Covers an inactive session AND a nullified (nil) session — the
            // latter stranded ticket #9619 on screen for 1,622 minutes.
            if order.isOrphanedKitchenTicket { continue }
            let activeKitchenItems = order.items.filter { ($0.status == "cooking" || $0.status == "alert") && $0.shouldDisplay(on: .kitchen) }
            let activeBarItems = order.items.filter { ($0.status == "cooking" || $0.status == "alert") && $0.shouldDisplay(on: .bar) }

            if kdsShowKitchen && !activeKitchenItems.isEmpty {
                if matchesSearchAndFilter(order: order, items: activeKitchenItems, now: now, filter: filter) {
                    count += 1
                }
            }
            if kdsShowBar && !activeBarItems.isEmpty {
                if matchesSearchAndFilter(order: order, items: activeBarItems, now: now, filter: filter) {
                    count += 1
                }
            }
        }
        return count
    }

    @ViewBuilder
    private func filterPill(title: String, tag: String, count: Int, isDestructive: Bool = false) -> some View {
        let isSelected = selectedFilter == tag
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedFilter = tag
            }
            APHaptic.trigger()
        }) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .lineLimit(1)
                Text("\(count)")
                    .font(.system(size: 10, weight: .black))
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(isSelected ? Color.white.opacity(0.25) : Color.appSurfaceHigh)
                    .cornerRadius(6)
                    .foregroundColor(isSelected ? .white : .textSecondary)
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Group {
                    if isSelected {
                        if isDestructive {
                            APGradient.destructive
                        } else {
                            APGradient.accent
                        }
                    } else {
                        LinearGradient(colors: [Color.appSurfaceHigh.opacity(0.5)], startPoint: .top, endPoint: .bottom)
                    }
                }
            )
            .foregroundColor(isSelected ? .white : .textPrimary)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.clear : Color.appBorderSubtle, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.appBackground.ignoresSafeArea()

                    VStack(spacing: 0) {
                        // 1. Flashing warning banner for the oldest active delayed order (FIFO priority)
                        delayedOrderBanner

                        // Sync health banner — tickets may be stale when sync is red
                        kdsSyncStatusBanner

                        // 2. Search & Filter subbar
                        searchAndFilterSubbar


                        // 3. Main content area
                        ZStack(alignment: .bottom) {
                            mainTicketsContent
                            if kdsKeyboardShortcutsEnabled {
                                kdsKeyboardHintBar
                            }
                        }

                    }
                    .background(sizeDetector)

                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: filteredTickets)

                    if showingHistoryDrawer {
                        historyDrawerOverlay
                    }
                }
                .navigationTitle(L.Nav.tabKitchen.t)
                .navigationBarTitleDisplayMode(.inline)
                .apNavBar(background: Color.appBackground)
                .fullScreenCover(item: $detailTicket) { ticket in
                    KitchenOrderDetailView(ticket: ticket, canManageKitchen: canManageKitchen)
                }
                .sheet(isPresented: $showingHelpView) {
                    KDSHelpView()
                }
                .toolbar {
                    // Intentionally empty leading slot — queue title lives in the
                    // filter subbar with the sidebar toggle so they never collide.
                    ToolbarItem(placement: .topBarLeading) {
                        Color.clear.frame(width: 1, height: 1)
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 12) {
                            // Help Button
                            Button(action: {
                                showingHelpView = true
                                APHaptic.trigger()
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "questionmark.circle")
                                    if isWide {
                                        Text("kds_help_button".t)
                                    }
                                }
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.textSecondary)
                            }
                            .buttonStyle(.plain)

                            // Recall Button
                            Button(action: {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    recallLastServedOrder()
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.uturn.backward")
                                    if isWide {
                                        Text("pos_recall".t)
                                    }
                                }
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.appAccent)
                            }
                            .buttonStyle(.plain)

                            // History Button
                            Button(action: {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                    showingHistoryDrawer.toggle()
                                }
                                APHaptic.trigger()
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "clock.arrow.circlepath")
                                    if isWide {
                                        Text("loyalty_history".t)
                                    }
                                }
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.appTeal)
                            }
                            .buttonStyle(.plain)

                            // View Toggle Button (Replaces squished segmented control)
                            Button(action: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    if kdsViewStyle == "columns" {
                                        kdsViewStyle = "grid"
                                    } else {
                                        kdsViewStyle = "columns"
                                    }
                                }
                                APHaptic.trigger()
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: kdsViewStyle == "columns" ? "rectangle.split.3x1" : "square.grid.2x2")
                                    if isWide {
                                        Text(kdsViewStyle == "columns" ? "kds_new_view".t : "kds_original_view".t)
                                    }
                                }
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.textSecondary)
                            }
                            .buttonStyle(.plain)

                            // Settings Button
                            Button(action: {
                                showingSettingsPopover = true
                                APHaptic.trigger()
                            }) {
                                Image(systemName: "gearshape.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(.textSecondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("kds_station_selector_acc".t)
                            .popover(isPresented: $showingSettingsPopover) {
                                KDSSettingsPopoverView(showKitchen: $kdsShowKitchen, showBar: $kdsShowBar)
                                    .presentationCompactAdaptation(.popover)
                            }
                        }
                    }
                }
        .onReceive(secondTimer) { date in
            currentSecond = date

            // KDS Auto-Complete: automatically mark orders as "served" when all items are done
            if kdsAutoCompleteEnabled {
                performAutoCompleteCheck()
            }

            // Keep bump-bar focus valid as the queue mutates
            if let focused = focusedTicket,
               !filteredTickets.contains(where: { $0.id == focused.id }) {
                focusedTicket = nil
            }

            // KDS Sound Alert: chime when ticket count increases (kitchen/bar split aware)
            if kdsSoundEnabled {
                let currentCount = filteredTickets.count
                if currentCount > previousTicketCount && previousTicketCount > 0 {
                    APHaptic.trigger()
                    AudioServicesPlaySystemSound(1007)
                }
                previousTicketCount = currentCount
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.65, dampingFraction: 0.75)) {
                isViewAppeared = true
            }
            secondTimerCancellable = secondTimer.connect()
            Task {
                await SyncEngine.shared.syncAll(modelContext: modelContext)
                _ = KDSTicketActions.reconcileStaleQuickServiceOrders(
                    branchActiveOrders,
                    tableSystemEnabled: tableSystemEnabled,
                    in: modelContext
                )
            }
        }
        .onDisappear {
            isViewAppeared = false
            secondTimerCancellable?.cancel()
            secondTimerCancellable = nil
        }
        // L-9: Physical KDS / Bump Bar — keyboard shortcuts
        // Space / Return  →  bump (complete) the currently selected OR oldest ticket
        .background(

            Group {
                if kdsKeyboardShortcutsEnabled {
                    // Space = bump selected (or oldest)
                    Button("") { bumpSelectedOrOldest() }
                        .keyboardShortcut(.space, modifiers: [])
                        .opacity(0).frame(width: 0, height: 0).allowsHitTesting(false)

                    // Return = same as Space
                    Button("") { bumpSelectedOrOldest() }
                        .keyboardShortcut(.return, modifiers: [])
                        .opacity(0).frame(width: 0, height: 0).allowsHitTesting(false)

                    // Right Arrow → select next ticket
                    Button("") { selectNextTicket(forward: true) }
                        .keyboardShortcut(.rightArrow, modifiers: [])
                        .opacity(0).frame(width: 0, height: 0).allowsHitTesting(false)

                    // Left Arrow → select previous ticket
                    Button("") { selectNextTicket(forward: false) }
                        .keyboardShortcut(.leftArrow, modifiers: [])
                        .opacity(0).frame(width: 0, height: 0).allowsHitTesting(false)

                    // Escape → deselect focus (does not dismiss detail cover)
                    Button("") { focusedTicket = nil }
                        .keyboardShortcut(.escape, modifiers: [])
                        .opacity(0).frame(width: 0, height: 0).allowsHitTesting(false)

                    // ⌘K → toggle kitchen station
                    Button("") { kdsShowKitchen.toggle() }
                        .keyboardShortcut("k", modifiers: [.command])
                        .opacity(0).frame(width: 0, height: 0).allowsHitTesting(false)

                    // ⌘B → toggle bar station
                    Button("") { kdsShowBar.toggle() }
                        .keyboardShortcut("b", modifiers: [.command])
                        .opacity(0).frame(width: 0, height: 0).allowsHitTesting(false)
                }
            }
        )
    }

    // MARK: - L-9: Keyboard Hint Bar

    @ViewBuilder
    private var kdsKeyboardHintBar: some View {
        VStack {
            Spacer()
            HStack(spacing: 16) {
                kbdHint(key: "space", label: "kds_kb_bump".t, icon: "")
                kbdHint(key: "←  →", label: "kds_kb_navigate".t, icon: "")
                kbdHint(key: "esc", label: "kds_kb_deselect".t, icon: "")
                kbdHint(key: "⌘K", label: "kds_kb_toggle_kitchen".t, icon: "")
                kbdHint(key: "⌘B", label: "kds_kb_toggle_bar".t, icon: "")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.55))
            .cornerRadius(10)
            .padding(.bottom, 12)
        }
        .allowsHitTesting(false)
    }

    private func kbdHint(key: String, label: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Color.white.opacity(0.15))
                .cornerRadius(5)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.7))
        }
    }

    private var sizeDetector: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear {
                    isWide = geo.size.width > 850
                }
                .onChange(of: geo.size.width) { _, newWidth in
                    isWide = newWidth > 850
                }
        }
    }

    private var kdsSyncStatusBanner: some View {
        Group {
            if !offlineSyncMode && syncEngine.syncStatus == .error {
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color.appRose)
                        .frame(width: 8, height: 8)
                    Text("kds_sync_error_banner".t)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    if let summary = syncEngine.lastSyncErrorSummary, !summary.isEmpty {
                        Text(summary)
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.8))
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.appRose.opacity(0.92))
            }
        }
    }

    private var delayedOrderBanner: some View {
        Group {
            if let delayed = oldestDelayedOrder {
                let minutes = Int(currentSecond.timeIntervalSince(delayed.createdAt) / 60)
                let identity = OrderDisplayIdentity(order: delayed, tableSystemEnabled: tableSystemEnabled)
                let alertMsg: String = {
                    if identity.isQuickService {
                        return "\(identity.primaryLabel) • \(identity.orderLabel) • \(minutes) \("notif_minutes".t)"
                    }
                    let table = identity.tableNumber ?? "—"
                    let orderSuffix = String(delayed.orderNumber.suffix(4))
                    return delayed.status == "ready"
                        ? LocalizationManager.shared.t("kds_delayed_banner_ready", table, orderSuffix, minutes)
                        : LocalizationManager.shared.t("kds_delayed_banner_cooking", table, orderSuffix, minutes)
                }()
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text(alertMsg)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.appRose)
                .cornerRadius(8)
                .padding([.horizontal, .top])
                .offset(y: isViewAppeared ? 0 : -30)
                .opacity(isViewAppeared ? 1 : 0)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var searchAndFilterSubbar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Text(isWide ? "kds_queue_wide".t : "kds_queue_narrow".t)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
                Text("\(filteredTickets.count)")
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.appAccent.opacity(0.15))
                    .foregroundColor(.appAccent)
                    .clipShape(Capsule())
            }
            .layoutPriority(1)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.textSecondary)
                    .font(.system(size: 14))
                TextField("kds_search_placeholder".t, text: $searchText)
                    .font(.system(size: 13))
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.textSecondary)
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.appSurfaceHigh.opacity(0.8))
            .cornerRadius(10)
            .frame(minWidth: isWide ? 200 : 140, maxWidth: isWide ? 240 : 180)
            .offset(x: isViewAppeared ? 0 : -40)
            .opacity(isViewAppeared ? 1 : 0)

            Spacer(minLength: 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterPill(title: "pos_category_all".t, tag: "all", count: countForFilter("all"))
                    filterPill(title: "pos_dine_in".t, tag: "dine_in", count: countForFilter("dine_in"))
                    filterPill(title: "pos_take_out".t, tag: "take_out", count: countForFilter("take_out"))
                    filterPill(title: "kds_delayed_pill".t, tag: "delayed", count: countForFilter("delayed"), isDestructive: true)
                    filterPill(
                        title: lm.currentLanguage == .thai ? "ค้างผิดปกติ" : "Stale",
                        tag: "stale",
                        count: countForFilter("stale"),
                        isDestructive: true
                    )
                }
            }
            .offset(x: isViewAppeared ? 0 : 40)
            .opacity(isViewAppeared ? 1 : 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.appSurface)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.appDivider.opacity(0.5)),
            alignment: .bottom
        )
    }

    private var mainTicketsContent: some View {
        Group {
            if filteredTickets.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.textTertiary)
                    Text("kds_no_active_tickets".t)
                        .font(.title3)
                        .foregroundColor(.textSecondary)
                    if let subtitle = emptyStateSubtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundColor(.textTertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(y: isViewAppeared ? 0 : 50)
                .opacity(isViewAppeared ? 1 : 0)
            } else {
                ScrollView(kdsViewStyle == "columns" ? .horizontal : .vertical, showsIndicators: true) {
                    if kdsViewStyle == "columns" {
                        // New premium columns view (resembles the requested design)
                        HStack(alignment: .top, spacing: 16) {
                            ForEach(filteredTickets) { ticket in
                                KitchenPremiumTicketCard(
                                    ticket: ticket,
                                    now: currentSecond,
                                    isFocused: focusedTicket?.id == ticket.id,
                                    onSelect: { detailTicket = ticket }
                                )
                                    .allowsHitTesting(kdsWorkflowMode == "full")
                                    .transition(.asymmetric(
                                        insertion: .scale(scale: 0.9).combined(with: .opacity).combined(with: .move(edge: .bottom)),
                                        removal: .opacity
                                    ))
                            }
                        }
                        .padding()
                        .padding(.bottom, kdsKeyboardShortcutsEnabled ? 44 : 0)
                    } else {
                        // Enhanced original grid view (compact layout)
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(filteredTickets) { ticket in
                                KitchenTicketView(
                                    ticket: ticket,
                                    now: currentSecond,
                                    isFocused: focusedTicket?.id == ticket.id,
                                    onSelect: { detailTicket = ticket }
                                )
                                    .allowsHitTesting(kdsWorkflowMode == "full")
                                    .transition(.asymmetric(
                                        insertion: .scale(scale: 0.9).combined(with: .opacity),
                                        removal: .opacity
                                    ))
                            }
                        }
                        .padding()
                        .padding(.bottom, kdsKeyboardShortcutsEnabled ? 44 : 0)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(y: isViewAppeared ? 0 : 50)
                .opacity(isViewAppeared ? 1 : 0)
            }
        }
    }



    @ViewBuilder
    private var historyDrawerOverlay: some View {

        HStack(spacing: 0) {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                        showingHistoryDrawer = false
                    }
                    APHaptic.trigger()
                }

            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundColor(.appTeal)
                        .font(.system(size: 16, weight: .bold))
                    Text("kds_recently_served".t)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.textPrimary)
                    Spacer()

                    Button(action: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                            showingHistoryDrawer = false
                        }
                        APHaptic.trigger()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color.appSurfaceHigh)

                Divider().background(Color.appDivider)

                ScrollView {
                    VStack(spacing: 12) {
                        let stationServedOrders = branchServedOrders.filter { order in
                            let activeItems = order.items.filter { $0.status == "served" || $0.status == "cancelled" }
                            let matchedItems = activeItems.filter { $0.shouldDisplay(showKitchen: kdsShowKitchen, showBar: kdsShowBar) }
                            return !matchedItems.isEmpty
                        }

                        if stationServedOrders.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "clock.badge.checkmark")
                                    .font(.system(size: 40))
                                    .foregroundColor(.textTertiary)
                                    .padding(.top, 40)
                                Text("kds_no_recently_served".t)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.textSecondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                        } else {
                            ForEach(stationServedOrders.prefix(15)) { order in
                                let identity = OrderDisplayIdentity(order: order, tableSystemEnabled: tableSystemEnabled)
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack(alignment: .top) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(identity.primaryLabel)
                                                .font(.system(size: 13, weight: .bold))
                                                .foregroundColor(.textPrimary)
                                            Text(identity.orderLabel)
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundColor(.textSecondary)
                                        }
                                        Spacer()

                                        Button(action: {
                                            recallOrder(order)
                                        }) {
                                            HStack(spacing: 4) {
                                                Image(systemName: "arrow.uturn.backward")
                                                    .font(.system(size: 9, weight: .black))
                                                Text("pos_recall".t)
                                                    .font(.system(size: 10, weight: .bold))
                                            }
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.appAccent.opacity(0.12))
                                            .foregroundColor(.appAccent)
                                            .cornerRadius(6)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .stroke(Color.appAccent.opacity(0.3), lineWidth: 0.8)
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }

                                    let matchedItems = order.items.filter { $0.shouldDisplay(showKitchen: kdsShowKitchen, showBar: kdsShowBar) }
                                    VStack(alignment: .leading, spacing: 6) {
                                        ForEach(matchedItems) { item in
                                            HStack(alignment: .top, spacing: 6) {
                                                Text("\(item.quantity)x")
                                                    .font(.system(size: 11, weight: .black))
                                                    .foregroundColor(item.status == "cancelled" ? .textTertiary : .appTeal)

                                                VStack(alignment: .leading, spacing: 1) {
                                                    Text(item.menuItem?.name ?? item.itemName)
                                                        .font(.system(size: 11, weight: .semibold))
                                                        .foregroundColor(item.status == "cancelled" ? .textTertiary : .textPrimary)
                                                        .strikethrough(item.status == "cancelled")

                                                    if !item.modifiers.isEmpty {
                                                        Text(item.modifiers.compactMap { $0.modifier?.name }.joined(separator: ", "))
                                                            .font(.system(size: 9))
                                                            .foregroundColor(.textSecondary)
                                                    }
                                                }
                                                Spacer()
                                                if item.status == "cancelled" {
                                                    Text("kds_cancelled".t)
                                                        .font(.system(size: 9, weight: .bold))
                                                        .foregroundColor(.appRose)
                                                }
                                            }
                                        }
                                    }

                                    HStack {
                                        Spacer()
                                        Text(LocalizationManager.shared.t("kds_served_at_template", formattedTime(order.updatedAt)))
                                            .font(.system(size: 9, weight: .medium))
                                            .foregroundColor(.textTertiary)
                                    }
                                }
                                .padding(12)
                                .background(Color.appSurface)
                                .cornerRadius(10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.appBorderSubtle, lineWidth: 1)
                                )
                            }
                        }
                    }
                    .padding(14)
                }
            }
            .frame(width: 320)
            .background(Color.appSurfaceHigh)
            .overlay(
                Rectangle()
                    .frame(width: 1)
                    .foregroundColor(Color.appDivider),
                alignment: .leading
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.asymmetric(
            insertion: .move(edge: .trailing),
            removal: .move(edge: .trailing)
        ))
    }

    private func recallOrder(_ order: Order) {
        withAnimation {
            _ = KDSTicketActions.recallOrder(
                order,
                showKitchen: kdsShowKitchen,
                showBar: kdsShowBar,
                in: modelContext
            )
            APHaptic.trigger()
        }
    }

    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func recallLastServedOrder() {
        let descriptor = FetchDescriptor<Order>()
        guard let orders = try? modelContext.fetch(descriptor) else { return }

        // Filter in memory for orders that are served or ready
        let filtered = orders.filter { $0.status == "served" || $0.status == "ready" }
        // Sort by updatedAt descending (most recent first)
        let sorted = filtered.sorted(by: { $0.updatedAt > $1.updatedAt })

        if let lastOrder = sorted.first {
            _ = KDSTicketActions.recallOrder(
                lastOrder,
                showKitchen: true,
                showBar: true,
                restoreAllServedItems: true,
                in: modelContext
            )
            APHaptic.trigger()
        }
    }

    /// KDS Auto-Complete: When enabled, automatically transitions orders from "ready" to "served"
    /// when ALL items in the order have a terminal status (served or cancelled).
    private func performAutoCompleteCheck() {
        var didAutoComplete = false

        for order in branchActiveOrders {
            if KDSTicketActions.markOrderDelivered(
                order: order,
                actorName: currentActorName,
                in: modelContext,
                sync: false
            ) {
                didAutoComplete = true
            }
        }

        if didAutoComplete {
            APHaptic.trigger()
            Task { await SyncEngine.shared.syncAll(modelContext: modelContext) }
        }
    }
}

// MARK: - Premium KDS Ticket Card (Requested Design Layout)

struct KitchenPremiumTicketCard: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var lm: LocalizationManager
    @AppStorage("enable_table_system") private var tableSystemEnabled = true
    var ticket: KDSTicket
    var now: Date
    var isFocused: Bool = false
    var onSelect: () -> Void

    var order: Order { ticket.order }
    var station: KDSStation { ticket.station }
    private var identity: OrderDisplayIdentity {
        OrderDisplayIdentity(order: order, tableSystemEnabled: tableSystemEnabled)
    }

    private var readyButtonTitle: String {
        if identity.isQuickService { return "kds_all_completed".t }
        return station == .kitchen ? "kds_mark_kitchen_ready".t : "kds_mark_bar_ready".t
    }

    private var elapsedSeconds: Int { max(0, Int(now.timeIntervalSince(order.createdAt))) }
    private var elapsedTime: Int { elapsedSeconds / 60 }

    var groupedItems: [(category: String, items: [OrderItem])] {
        let filtered = order.items.filter { item in
            item.shouldDisplay(on: station)
        }
        let grouped = Dictionary(grouping: filtered) { item in
            item.menuItem?.category?.name.uppercased() ?? "OTHER"
        }
        return grouped.map { (category: $0.key, items: $0.value) }.sorted { $0.category < $1.category }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header: color based on cooking time
            VStack(alignment: .leading, spacing: 2) {
                // Station badge row
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: station == .kitchen ? "flame.fill" : "wineglass.fill")
                        Text(station == .kitchen ? "kds_station_kitchen_upper".t : "kds_station_bar_upper".t)
                    }
                    .font(.system(size: 9, weight: .black))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(station == .kitchen ? Color.appRose.opacity(0.15) : Color.appTeal.opacity(0.15))
                    .foregroundColor(station == .kitchen ? .appRose : .appTeal)
                    .cornerRadius(4)

                    Spacer()
                }
                .padding(.bottom, 2)

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(identity.primaryLabel)
                            .font(.system(
                                size: identity.isQuickService ? 22 : 13,
                                weight: identity.isQuickService ? .black : .bold,
                                design: .rounded
                            ))
                            .foregroundColor(elapsedTime >= KDSDisplayPolicy.warningMinutes ? headerTextColor() : .textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(identity.orderLabel)
                            .font(.system(
                                size: identity.isQuickService ? 11 : 18,
                                weight: identity.isQuickService ? .semibold : .black,
                                design: identity.isQuickService ? .monospaced : .default
                            ))
                            .foregroundColor(elapsedTime >= KDSDisplayPolicy.warningMinutes ? headerTextColor() : .textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "timer")
                        Text(timeString(seconds: elapsedSeconds))
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(elapsedTime >= KDSDisplayPolicy.warningMinutes ? headerTextColor() : .appAccent)
                }

                if elapsedTime < KDSDisplayPolicy.warningMinutes {
                    Rectangle()
                        .frame(height: 1.5)
                        .foregroundColor(station == .kitchen ? .appRose : .appTeal)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(headerColor())

            // Item details
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if groupedItems.isEmpty {
                        VStack(spacing: 8) {
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(.appTeal)
                            Text("kds_all_done".t)
                                .font(.caption)
                                .foregroundColor(.appTeal)
                                .italic()
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, minHeight: 180, alignment: .center)
                    } else {
                        ForEach(groupedItems, id: \.category) { group in
                            VStack(alignment: .leading, spacing: 6) {
                                // Category Header Band
                                Text(group.category)
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.textSecondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.appSurfaceHigh)
                                    .cornerRadius(3)
                                    .padding(.bottom, 2)

                                ForEach(group.items) { item in
                                    let isDone = item.status == "served" || item.status == "cancelled"
                                    HStack(alignment: .top, spacing: 8) {
                                        Text("\(item.quantity)")
                                            .font(.system(size: 14, weight: .black))
                                            .foregroundColor(item.status == "alert" ? .appRose : (isDone ? .textTertiary : .textPrimary))
                                            .frame(width: 14, alignment: .leading)
                                            .strikethrough(isDone)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.menuItem?.name ?? item.itemName)
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundColor(item.status == "alert" ? .appRose : (isDone ? .textTertiary : .textPrimary))
                                                .strikethrough(isDone)
                                                .multilineTextAlignment(.leading)

                                            if !item.modifiers.isEmpty {
                                                Text(item.modifiers.compactMap { $0.modifier?.name }.joined(separator: ", "))
                                                    .font(.system(size: 10))
                                                    .foregroundColor(isDone ? .textTertiary : .appTeal)
                                                    .strikethrough(isDone)
                                                    .multilineTextAlignment(.leading)
                                            }

                                            if item.status == "served" {
                                                HStack(spacing: 2) {
                                                    Image(systemName: "checkmark.circle.fill")
                                                    if let servedBy = item.servedBy, !servedBy.isEmpty {
                                                        Text(LocalizationManager.shared.t("kds_served_by_template", servedBy))
                                                    } else {
                                                        Text("kds_item_ready_badge".t)
                                                    }
                                                }
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundColor(.appTeal)
                                            } else if item.status == "cancelled" {
                                                Text("kds_item_cancelled_badge".t)
                                                    .font(.system(size: 9, weight: .bold))
                                                    .foregroundColor(.appRose)
                                            }
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, 2)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        if item.status != "cancelled" {
                                            toggleItemServe(item)
                                        }
                                    }
                                    Divider().background(Color.appDivider)
                                }
                            }
                        }
                    }
                }
                .padding(10)
            }
            .background(Color.appSurface)

            Spacer(minLength: 0)

            // Footer Action Panel
            HStack {
                if !identity.isQuickService {
                    Button(action: alertWaiter) {
                        Text("kds_request_waiter".t)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.appTeal)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button(action: serveEntireTicket) {
                    Text(readyButtonTitle)
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Color.appAccent.opacity(0.12))
                        .foregroundColor(.appAccent)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.appAccent.opacity(0.3), lineWidth: 0.8)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(readyButtonTitle)
                .accessibilityHint("kds_mark_ready_hint".t)
            }
            .padding(10)
            .background(Color.appSurfaceHigh.opacity(0.5))
        }
        .frame(width: 240, height: 380)
        .background(Color.appSurface)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isFocused ? Color.appAccent : borderColor(), lineWidth: isFocused ? 3 : borderWidth())
        )
        .shadow(color: Color.black.opacity(isFocused ? 0.22 : 0.12), radius: isFocused ? 10 : 6, x: 0, y: 3)
        .onTapGesture(perform: onSelect)
        .accessibilityLabel("Order \(order.orderNumber), \(order.items.count) items")
        .accessibilityHint("Double-tap to view order details")
    }

    private func timeString(seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }

    private func headerColor() -> Color {
        if elapsedTime >= KDSDisplayPolicy.delayedMinutes { return .appRose }
        if elapsedTime >= KDSDisplayPolicy.warningMinutes { return .appAmber }
        return Color.appSurface
    }

    private func headerTextColor() -> Color {
        if elapsedTime >= KDSDisplayPolicy.warningMinutes && elapsedTime < KDSDisplayPolicy.delayedMinutes { return .black }
        return .white
    }

    private func borderColor() -> Color {
        if elapsedTime >= KDSDisplayPolicy.delayedMinutes { return .appRose }
        if elapsedTime >= KDSDisplayPolicy.warningMinutes { return .appAmber }
        if station == .bar { return Color.appTeal.opacity(0.4) }
        return Color.appBorderSubtle
    }

    private func borderWidth() -> CGFloat {
        if elapsedTime >= KDSDisplayPolicy.warningMinutes { return 2 }
        return 1
    }

    private func toggleItemServe(_ item: OrderItem) {
        withAnimation {
            _ = KDSTicketActions.toggleItemReady(
                item,
                order: order,
                completeQuickServiceWhenReady: identity.isQuickService,
                in: modelContext
            )
        }
    }

    private func alertWaiter() {
        KDSTicketActions.requestWaiter(for: order)
        APHaptic.trigger()
    }

    private func serveEntireTicket() {
        withAnimation {
            _ = KDSTicketActions.markStationReady(
                order: order,
                station: station,
                completeQuickServiceWhenReady: identity.isQuickService,
                in: modelContext
            )
        }
        APHaptic.trigger()
    }
}

// MARK: - Original KDS Ticket View Component (Enhanced & Compacted)

struct KitchenTicketView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var lm: LocalizationManager
    @EnvironmentObject private var sessionManager: AppSessionManager
    @AppStorage("enable_table_system") private var tableSystemEnabled = true
    var ticket: KDSTicket
    var now: Date
    var isFocused: Bool = false
    var onSelect: () -> Void

    var order: Order { ticket.order }
    var station: KDSStation { ticket.station }
    private var identity: OrderDisplayIdentity {
        OrderDisplayIdentity(order: order, tableSystemEnabled: tableSystemEnabled)
    }

    private var readyButtonTitle: String {
        if identity.isQuickService { return "kds_all_completed".t }
        return station == .kitchen ? "kds_mark_kitchen_ready".t : "kds_mark_bar_ready".t
    }

    private var currentActorName: String? {
        let name = sessionManager.currentStaffSession?.displayName
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? nil : name
    }

    private var elapsedTime: Int { max(0, Int(now.timeIntervalSince(order.createdAt) / 60)) }

    var body: some View {
        VStack(spacing: 0) {
            // Header Info: styled closer to the reference image based on severity
            VStack(alignment: .leading, spacing: 2) {
                // Station badge row
                HStack {
                    HStack(spacing: 3) {
                        Image(systemName: station == .kitchen ? "flame.fill" : "wineglass.fill")
                        Text(station == .kitchen ? "kds_station_kitchen_upper".t : "kds_station_bar_upper".t)
                    }
                    .font(.system(size: 8, weight: .black))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(station == .kitchen ? Color.appRose.opacity(0.15) : Color.appTeal.opacity(0.15))
                    .foregroundColor(station == .kitchen ? .appRose : .appTeal)
                    .cornerRadius(3)

                    Spacer()
                }
                .padding(.bottom, 2)

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(identity.primaryLabel)
                            .font(.system(
                                size: identity.isQuickService ? 18 : 10,
                                weight: identity.isQuickService ? .black : .bold,
                                design: .rounded
                            ))
                            .foregroundColor(elapsedTime >= KDSDisplayPolicy.warningMinutes ? headerTextColor() : .textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(identity.orderLabel)
                            .font(.system(
                                size: identity.isQuickService ? 9 : 14,
                                weight: identity.isQuickService ? .semibold : .black,
                                design: identity.isQuickService ? .monospaced : .default
                            ))
                            .foregroundColor(elapsedTime >= KDSDisplayPolicy.warningMinutes ? headerTextColor() : .textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                    }
                    Spacer()

                    // Timer
                    HStack(spacing: 3) {
                        Image(systemName: "timer")
                            .font(.system(size: 9))
                        Text("\(elapsedTime)m")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(elapsedTime >= KDSDisplayPolicy.warningMinutes ? headerTextColor() : .appAccent)
                }

                if elapsedTime < KDSDisplayPolicy.warningMinutes {
                    Rectangle()
                        .frame(height: 1.2)
                        .foregroundColor(station == .kitchen ? .appRose : .appTeal)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(headerColor())
            .onTapGesture(perform: onSelect)

            // Order Items List: compacted to show more items
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    let displayedItems = order.items.filter { item in
                        item.shouldDisplay(on: station)
                    }

                    if displayedItems.isEmpty {
                        VStack(spacing: 4) {
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.appTeal)
                            Text("kds_all_completed".t)
                                .font(.system(size: 10))
                                .foregroundColor(.appTeal)
                                .italic()
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, minHeight: 140, alignment: .center)
                    } else {
                        ForEach(displayedItems) { item in
                            let isDone = item.status == "served" || item.status == "cancelled"
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(alignment: .top) {
                                    Text("\(item.quantity)x")
                                        .font(.system(size: 11, weight: .black))
                                        .foregroundColor(item.status == "alert" ? .appRose : (isDone ? .textTertiary : .appAmber))
                                        .frame(width: 14, alignment: .leading)
                                        .strikethrough(isDone)

                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(item.menuItem?.name ?? item.itemName)
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor(item.status == "alert" ? .appRose : (isDone ? .textTertiary : .textPrimary))
                                            .strikethrough(isDone)
                                            .multilineTextAlignment(.leading)

                                        if !item.modifiers.isEmpty {
                                            Text(item.modifiers.compactMap { $0.modifier?.name }.joined(separator: ", "))
                                                .font(.system(size: 9))
                                                .foregroundColor(isDone ? .textTertiary : .textSecondary)
                                                .strikethrough(isDone)
                                                .multilineTextAlignment(.leading)
                                        }

                                        if item.status == "served" {
                                            HStack(spacing: 2) {
                                                Image(systemName: "checkmark.circle.fill")
                                                if let servedBy = item.servedBy, !servedBy.isEmpty {
                                                    Text(LocalizationManager.shared.t("kds_served_by_template", servedBy))
                                                } else {
                                                    Text("kds_item_ready_badge".t)
                                                }
                                            }
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundColor(.appTeal)
                                        } else if item.status == "cancelled" {
                                            Text("kds_item_cancelled_badge".t)
                                                .font(.system(size: 8, weight: .bold))
                                                .foregroundColor(.appRose)
                                        }
                                    }

                                    Spacer()

                                    // Compact Action Buttons
                                    HStack(spacing: 4) {
                                        if item.status == "served" {
                                            Button(action: { recallItem(item) }) {
                                                Image(systemName: "arrow.uturn.backward")
                                                    .font(.system(size: 8))
                                                    .padding(4)
                                                    .background(Color.appAccent.opacity(0.1))
                                                    .foregroundColor(.appAccent)
                                                    .clipShape(Circle())
                                            }
                                            .buttonStyle(.plain)
                                        } else if item.status == "cancelled" {
                                            // Cancelled
                                        } else {
                                            Button(action: { alertItem(item) }) {
                                                Image(systemName: "exclamationmark.triangle")
                                                    .font(.system(size: 8))
                                                    .padding(4)
                                                    .background(Color.appAmber.opacity(0.1))
                                                    .foregroundColor(.appAmber)
                                                    .clipShape(Circle())
                                            }
                                            .buttonStyle(.plain)
                                            .disabled(item.status == "alert")

                                            Button(action: { serveItem(item) }) {
                                                Image(systemName: "checkmark.circle")
                                                    .font(.system(size: 8))
                                                    .padding(4)
                                                    .background(Color.appTeal.opacity(0.1))
                                                    .foregroundColor(.appTeal)
                                                    .clipShape(Circle())
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                            Divider().background(Color.appDivider.opacity(0.5))
                        }
                    }
                }
                .padding(8)
            }
            .background(Color.appSurface)
            .onTapGesture(perform: onSelect)

            // Footer Action: unified two-button layout matching the premium tickets
            HStack {
                if !identity.isQuickService {
                    Button(action: alertWaiter) {
                        Text("kds_request_waiter".t)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.appTeal)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                let hasActiveItemsForStation = order.items.contains(where: {
                    let matchStation = $0.shouldDisplay(on: station)
                    return ($0.status == "cooking" || $0.status == "alert") && matchStation
                })
                if hasActiveItemsForStation {
                    Button(action: serveEntireTicket) {
                        Text(readyButtonTitle)
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3)
                            .background(Color.appAccent.opacity(0.12))
                            .foregroundColor(.appAccent)
                            .cornerRadius(5)
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(Color.appAccent.opacity(0.3), lineWidth: 0.8)
                            )
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: completeTicket) {
                        Text("kds_clear_delivered".t)
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3)
                            .background(Color.appTeal.opacity(0.12))
                            .foregroundColor(.appTeal)
                            .cornerRadius(5)
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(Color.appTeal.opacity(0.3), lineWidth: 0.8)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color.appSurfaceHigh.opacity(0.5))
        }
        .frame(height: 285) // Taller height to show more menu items
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isFocused ? Color.appAccent : borderColor(), lineWidth: isFocused ? 3 : borderWidth())
        )
        .shadow(color: Color.black.opacity(isFocused ? 0.22 : 0.15), radius: isFocused ? 8 : 4)
    }

    private func headerColor() -> Color {
        if elapsedTime >= KDSDisplayPolicy.delayedMinutes { return .appRose }
        if elapsedTime >= KDSDisplayPolicy.warningMinutes { return .appAmber }
        return Color.appSurface
    }

    private func headerTextColor() -> Color {
        if elapsedTime >= KDSDisplayPolicy.warningMinutes && elapsedTime < KDSDisplayPolicy.delayedMinutes { return .black }
        return .white
    }

    private func borderColor() -> Color {
        if elapsedTime >= KDSDisplayPolicy.delayedMinutes { return .appRose }
        if elapsedTime >= KDSDisplayPolicy.warningMinutes { return .appAmber }
        if station == .bar { return Color.appTeal.opacity(0.4) }
        return Color.appBorderSubtle
    }

    private func borderWidth() -> CGFloat {
        if elapsedTime >= KDSDisplayPolicy.warningMinutes { return 2 }
        return 1
    }

    private func serveItem(_ item: OrderItem) {
        withAnimation {
            _ = KDSTicketActions.markItemReady(
                item,
                order: order,
                completeQuickServiceWhenReady: identity.isQuickService,
                in: modelContext
            )
        }
    }

    private func recallItem(_ item: OrderItem) {
        withAnimation {
            _ = KDSTicketActions.recallItem(item, order: order, in: modelContext)
        }
    }

    private func alertItem(_ item: OrderItem) {
        withAnimation {
            _ = KDSTicketActions.alertItem(item, order: order, in: modelContext)
        }
    }

    private func alertWaiter() {
        KDSTicketActions.requestWaiter(for: order)
        APHaptic.trigger()
    }

    private func serveEntireTicket() {
        withAnimation {
            _ = KDSTicketActions.markStationReady(
                order: order,
                station: station,
                completeQuickServiceWhenReady: identity.isQuickService,
                in: modelContext
            )
        }
        APHaptic.trigger()
    }

    private func completeTicket() {
        withAnimation {
            _ = KDSTicketActions.markStationDelivered(
                order: order,
                station: station,
                actorName: currentActorName,
                in: modelContext
            )
        }
        APHaptic.trigger()
    }
}

// MARK: - L-9: Physical KDS / Bump Bar Helper Extension

extension KitchenDisplayView {

    /// Space / Return — bump (mark station ready) focused ticket, or oldest FIFO ticket
    func bumpSelectedOrOldest() {
        guard kdsKeyboardShortcutsEnabled else { return }
        let target = focusedTicket ?? filteredTickets.first
        guard let ticket = target else { return }
        bumpTicket(ticket)
    }

    /// Arrow Left/Right — cycle focus through visible tickets (does not open detail)
    func selectNextTicket(forward: Bool) {
        guard kdsKeyboardShortcutsEnabled, !filteredTickets.isEmpty else { return }
        if let current = focusedTicket,
           let idx = filteredTickets.firstIndex(where: { $0.id == current.id }) {
            let next = forward
                ? (idx + 1 < filteredTickets.count ? idx + 1 : 0)
                : (idx - 1 >= 0 ? idx - 1 : filteredTickets.count - 1)
            focusedTicket = filteredTickets[next]
        } else {
            focusedTicket = forward ? filteredTickets.first : filteredTickets.last
        }
        APHaptic.trigger()
    }

    /// Bump = mark station ready (order → ready when all stations done). Same as footer Ready.
    private func bumpTicket(_ ticket: KDSTicket) {
        withAnimation {
            _ = KDSTicketActions.markStationReady(
                order: ticket.order,
                station: ticket.station,
                completeQuickServiceWhenReady: OrderDisplayIdentity(
                    order: ticket.order,
                    tableSystemEnabled: tableSystemEnabled
                ).isQuickService,
                in: modelContext
            )
        }
        if focusedTicket?.id == ticket.id { focusedTicket = nil }
        APHaptic.trigger()
        if kdsSoundEnabled { AudioServicesPlaySystemSound(1054) }
    }
}
// MARK: - Full Screen Detail View

struct KitchenOrderDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var lm: LocalizationManager
    @EnvironmentObject private var sessionManager: AppSessionManager
    @AppStorage("enable_table_system") private var tableSystemEnabled = true
    var ticket: KDSTicket
    var canManageKitchen: Bool = true

    var order: Order { ticket.order }
    var station: KDSStation { ticket.station }
    private var identity: OrderDisplayIdentity {
        OrderDisplayIdentity(order: order, tableSystemEnabled: tableSystemEnabled)
    }

    @State private var elapsedTime = 0
    @State private var contentVisible = false
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var displayedItems: [OrderItem] {
        order.items.filter { $0.shouldDisplay(on: station) && !$0.isDeleted }
    }

    private var activeItems: [OrderItem] {
        displayedItems.filter { $0.status == "cooking" || $0.status == "alert" }
    }

    private var completedCount: Int {
        displayedItems.filter { $0.status == "served" }.count
    }

    private var totalCount: Int {
        displayedItems.count
    }

    private var totalQuantity: Int {
        displayedItems.reduce(0) { $0 + $1.quantity }
    }

    private var footerActionTitle: String {
        if identity.isQuickService { return "kds_all_completed".t }
        if station == .kitchen {
            return "kds_mark_kitchen_ready".t
        } else {
            return "kds_mark_bar_ready".t
        }
    }

    private var currentActorName: String? {
        let name = sessionManager.currentStaffSession?.displayName
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? nil : name
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header with live progress bar and urgency indicator
                KDSOrderDetailHeader(
                    ticket: ticket,
                    completedCount: completedCount,
                    totalCount: totalCount
                ) {
                    dismiss()
                }

                // Main body with responsive centered container on iPad
                ScrollView {
                    VStack(spacing: APSpacing.md) {
                        // Special Order/Customer Notes Banner
                        if let customerNotes = order.customer?.notes, !customerNotes.isEmpty {
                            orderNotesBanner(customerNotes)
                        }

                        if displayedItems.isEmpty {
                            kdsDetailEmptyState
                                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        } else {
                            // Food Items List
                            LazyVStack(spacing: 10) {
                                ForEach(Array(displayedItems.enumerated()), id: \.element.id) { index, item in
                                    KDSOrderDetailItemCard(
                                        item: item,
                                        station: station,
                                        canManageKitchen: canManageKitchen,
                                        onReady: { serveItem(item) },
                                        onAlert: { alertItem(item) },
                                        onCancel: { rejectItem(item) },
                                        onRecall: { recallItem(item) }
                                    )
                                    .transition(.asymmetric(
                                        insertion: .move(edge: .bottom).combined(with: .opacity),
                                        removal: .opacity
                                    ))
                                    .animation(
                                        .spring(response: 0.45, dampingFraction: 0.82)
                                            .delay(Double(index) * 0.05),
                                        value: contentVisible
                                    )
                                }
                            }

                            // Order Summary Strip
                            KDSOrderSummaryStrip(
                                itemCount: displayedItems.count,
                                totalQuantity: totalQuantity,
                                orderTime: order.createdAt,
                                actorName: currentActorName
                            )
                            .padding(.top, 4)
                        }
                    }
                    .padding(.horizontal, APSpacing.lg)
                    .padding(.vertical, APSpacing.md)
                    .frame(maxWidth: 820)
                    .frame(maxWidth: .infinity)
                }
                .background(Color.appBackground)

                // Sticky Action Footer
                detailFooter
            }
            .background(Color.appBackground)
            .apColorScheme()
        }
        .onAppear {
            updateElapsedTime()
            withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) {
                contentVisible = true
            }
        }
        .onReceive(timer) { _ in
            updateElapsedTime()
        }
    }

    private func orderNotesBanner(_ notes: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.bubble.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Color(hex: "F59E0B"))

            VStack(alignment: .leading, spacing: 2) {
                Text("order_notes".t.uppercased())
                    .font(.system(size: 10, weight: .black))
                    .foregroundColor(Color(hex: "F59E0B"))
                    .tracking(0.6)
                Text(notes)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textPrimary)
            }

            Spacer()
        }
        .padding(.horizontal, APSpacing.md)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: APRadius.md, style: .continuous)
                .fill(Color(hex: "F59E0B").opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: APRadius.md, style: .continuous)
                .stroke(Color(hex: "F59E0B").opacity(0.3), lineWidth: 1)
        )
    }

    private var kdsDetailEmptyState: some View {
        VStack(spacing: APSpacing.lg) {
            Spacer(minLength: 40)
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(APGradient.positive)
                .symbolEffect(.bounce, value: contentVisible)
            Text("kds_all_station_completed".t)
                .font(.title2.weight(.bold))
                .foregroundColor(.textPrimary)
            Text("kds_dismiss_ticket_hint".t)
                .font(.subheadline)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
            Spacer(minLength: 40)
        }
        .frame(maxWidth: .infinity, minHeight: 420)
    }

    @ViewBuilder
    private var detailFooter: some View {
        VStack(spacing: 0) {
            let activeCount = activeItems.count

            if activeCount > 0 {
                KDSPrimaryFooterButton(
                    title: footerActionTitle,
                    badgeCount: activeCount,
                    systemImage: "checkmark.circle.fill",
                    gradient: LinearGradient(
                        colors: station == .kitchen
                            ? [Color(hex: "10B981"), Color(hex: "059669")]
                            : [Color(hex: "06B6D4"), Color(hex: "0891B2")],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                ) {
                    serveEntireTicket()
                    dismiss()
                }
                .accessibilityHint("kds_mark_ready_hint".t)
                .padding(.horizontal, APSpacing.lg)
                .padding(.vertical, APSpacing.md)
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
            } else {
                KDSPrimaryFooterButton(
                    title: "kds_clear_delivered".t,
                    systemImage: "hand.thumbsup.fill",
                    gradient: LinearGradient(
                        colors: [Color(hex: "0D9488"), Color(hex: "059669")],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                ) {
                    completeTicket()
                    dismiss()
                }
                .padding(.horizontal, APSpacing.lg)
                .padding(.vertical, APSpacing.md)
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
            }
        }
        .background(
            .ultraThinMaterial
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.appDivider.opacity(0.6))
                .frame(height: 1)
        }
    }

    private func updateElapsedTime() {
        let diff = Date().timeIntervalSince(order.createdAt)
        elapsedTime = Int(diff / 60)
    }

    private func serveItem(_ item: OrderItem) {
        withAnimation {
            _ = KDSTicketActions.markItemReady(
                item,
                order: order,
                completeQuickServiceWhenReady: identity.isQuickService,
                in: modelContext
            )
            if !KDSTicketActions.stationHasActiveItems(order: order, station: station) {
                dismiss()
            }
        }
    }

    private func recallItem(_ item: OrderItem) {
        withAnimation {
            _ = KDSTicketActions.recallItem(item, order: order, in: modelContext)
        }
    }

    private func alertItem(_ item: OrderItem) {
        withAnimation {
            _ = KDSTicketActions.alertItem(item, order: order, in: modelContext)
        }
    }

    private func rejectItem(_ item: OrderItem) {
        guard canManageKitchen else { return }
        withAnimation {
            _ = KDSTicketActions.cancelItem(
                item,
                order: order,
                station: station,
                completeQuickServiceWhenReady: identity.isQuickService,
                in: modelContext
            )
            if !KDSTicketActions.stationHasActiveItems(order: order, station: station) {
                dismiss()
            }
        }
    }

    private func serveEntireTicket() {
        _ = KDSTicketActions.markStationReady(
            order: order,
            station: station,
            completeQuickServiceWhenReady: identity.isQuickService,
            in: modelContext
        )
    }

    private func completeTicket() {
        _ = KDSTicketActions.markStationDelivered(
            order: order,
            station: station,
            actorName: currentActorName,
            in: modelContext
        )
    }
}

// MARK: - KDS Item Classification Extension
extension OrderItem {
    var isBeverage: Bool {
        OrderRoutingResolver.stations(for: self).contains(.bar)
    }

    func shouldDisplay(showKitchen: Bool, showBar: Bool) -> Bool {
        let stations = OrderRoutingResolver.stations(for: self)
        return (showKitchen && stations.contains(.kitchen)) || (showBar && stations.contains(.bar))
    }

    func shouldDisplay(on station: KDSStation) -> Bool {
        let target: PrepStation = station == .kitchen ? .kitchen : .bar
        return OrderRoutingResolver.stations(for: self).contains(target)
    }
}

// MARK: - KDS Help Tutorial View
struct KDSHelpView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var lm: LocalizationManager

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Title section
                    HStack(spacing: 12) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.appTeal)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("kds_help_title".t)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.textPrimary)
                            Text("kds_help_subtitle".t)
                                .font(.system(size: 12))
                                .foregroundColor(.textSecondary)
                        }
                    }
                    .padding(.bottom, 8)

                    Divider().background(Color.appDivider)

                    // Tip 1: Splitting Cards
                    helpSection(
                        title: "kds_help_sec1_title".t,
                        icon: "square.split.2x1.fill",
                        iconColor: .appTeal,
                        description: "kds_help_sec1_desc".t,
                        bulletPoints: [
                            "kds_help_sec1_bullet1".t,
                            "kds_help_sec1_bullet2".t
                        ]
                    )

                    // Tip 2: Color Coding
                    helpSection(
                        title: "kds_help_sec2_title".t,
                        icon: "paintpalette.fill",
                        iconColor: .appAmber,
                        description: "kds_help_sec2_desc".t,
                        bulletPoints: [
                            "kds_help_sec2_bullet1".t,
                            "kds_help_sec2_bullet2".t,
                            "kds_help_sec2_bullet3".t
                        ]
                    )

                    // Tip 3: Controls and Actions
                    helpSection(
                        title: "kds_help_sec3_title".t,
                        icon: "hand.tap.fill",
                        iconColor: .appAccent,
                        description: "kds_help_sec3_desc".t,
                        bulletPoints: [
                            "kds_help_sec3_bullet1".t,
                            "kds_help_sec3_bullet2".t,
                            "kds_help_sec3_bullet3".t,
                            "kds_help_sec3_bullet4".t
                        ]
                    )

                    // Tip 4: Settings Toggles
                    helpSection(
                        title: "kds_help_sec4_title".t,
                        icon: "gearshape.2.fill",
                        iconColor: .textSecondary,
                        description: "kds_help_sec4_desc".t,
                        bulletPoints: [
                            "kds_help_sec4_bullet1".t,
                            "kds_help_sec4_bullet2".t,
                            "kds_help_sec4_bullet3".t
                        ]
                    )
                }
                .padding(24)
            }
            .background(Color.appBackground)
            .navigationTitle("kds_help_nav_title".t)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("close_btn".t) {
                        dismiss()
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.appTeal)
                }
            }
            .apColorScheme()
        }
    }

    @ViewBuilder
    private func helpSection(title: String, icon: String, iconColor: Color, description: String, bulletPoints: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(iconColor)
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.textPrimary)
            }

            Text(description)
                .font(.system(size: 12))
                .foregroundColor(.textSecondary)
                .padding(.leading, 24)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(bulletPoints, id: \.self) { point in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.appTeal)
                        Text(point)
                            .font(.system(size: 12))
                            .foregroundColor(.textPrimary)
                            .multilineTextAlignment(.leading)
                    }
                }
            }
            .padding(.leading, 32)
        }
        .padding(14)
        .background(Color.appSurface)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.appBorderSubtle, lineWidth: 1)
        )
    }
}

// MARK: - KDS Quick Settings Popover View
struct KDSSettingsPopoverView: View {
    @EnvironmentObject private var lm: LocalizationManager
    @Binding var showKitchen: Bool
    @Binding var showBar: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("kds_settings_title".t)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.textPrimary)
                .padding(.bottom, 4)

            Toggle(isOn: $showKitchen) {
                HStack(spacing: 8) {
                    Image(systemName: "flame.fill")
                        .foregroundColor(.appRose)
                    Text("kds_show_kitchen_toggle".t)
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: .appTeal))

            Toggle(isOn: $showBar) {
                HStack(spacing: 8) {
                    Image(systemName: "wineglass.fill")
                        .foregroundColor(.appTeal)
                    Text("kds_show_bar_toggle".t)
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: .appTeal))
        }
        .padding(16)
        .frame(width: 280)
        .background(Color.appSurface)
        .cornerRadius(12)
    }
}
