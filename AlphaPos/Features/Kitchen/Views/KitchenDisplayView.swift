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
    @Query(filter: #Predicate<Order> { order in
        order.status == "preparing" || order.status == "ready"
    }, sort: \Order.createdAt) private var activeOrders: [Order]
    
    @Query(filter: #Predicate<Order> { order in
        order.status == "served"
    }, sort: \Order.updatedAt, order: .reverse) private var servedOrders: [Order]
    
    private let columns = [
        GridItem(.adaptive(minimum: 220), spacing: 12)
    ]
    
    @State private var selectedTicket: KDSTicket? = nil
    @State private var showingHelpView = false
    @State private var showingSettingsPopover = false
    @State private var showingHistoryDrawer = false
    @State private var isWide = true
    @State private var isViewAppeared = false
    
    // Search and filter states
    @State private var searchText = ""
    @State private var selectedFilter = "all"
    @AppStorage("kds_view_style") private var kdsViewStyle = "columns"
    @AppStorage("kds_show_kitchen") private var kdsShowKitchen = true
    @AppStorage("kds_show_bar") private var kdsShowBar = true
    @AppStorage("kds_auto_complete_enabled") private var kdsAutoCompleteEnabled = false
    @AppStorage("kds_sound_enabled") private var kdsSoundEnabled = true
    
    // Timer for refreshing delayed status every second
    @State private var currentSecond = Date()
    @State private var previousActiveOrderCount = 0
    private let secondTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var filteredTickets: [KDSTicket] {
        var tickets: [KDSTicket] = []
        let now = Date()
        
        for order in activeOrders {
            // Skip ghost tickets belonging to inactive table sessions
            if let session = order.tableSession, !session.isActive {
                continue
            }
            let activeKitchenItems = order.items.filter { ($0.status == "cooking" || $0.status == "alert") && !$0.isBeverage }
            let activeBarItems = order.items.filter { ($0.status == "cooking" || $0.status == "alert") && $0.isBeverage }
            
            // Check station visibility settings:
            if kdsShowKitchen && !activeKitchenItems.isEmpty {
                if matchesSearchAndFilter(order: order, items: activeKitchenItems, now: now, filter: selectedFilter) {
                    tickets.append(KDSTicket(order: order, station: .kitchen))
                }
            }
            
            if kdsShowBar && !activeBarItems.isEmpty {
                if matchesSearchAndFilter(order: order, items: activeBarItems, now: now, filter: selectedFilter) {
                    tickets.append(KDSTicket(order: order, station: .bar))
                }
            }
        }
        
        // Sort by order creation date (FIFO)
        return tickets.sorted { $0.order.createdAt < $1.order.createdAt }
    }
    
    private func matchesSearchAndFilter(order: Order, items: [OrderItem], now: Date, filter: String) -> Bool {
        // 1. Search text filter
        if !searchText.isEmpty {
            let tableNum = order.tableSession?.table?.tableNumber ?? ""
            let orderNum = order.orderNumber
            let matchesTable = tableNum.localizedCaseInsensitiveContains(searchText)
            let matchesOrder = orderNum.localizedCaseInsensitiveContains(searchText)
            let matchesItem = items.contains { $0.menuItem?.name.localizedCaseInsensitiveContains(searchText) ?? false }
            guard matchesTable || matchesOrder || matchesItem else { return false }
        }
        
        // 2. Filter type
        switch filter {
        case "dine_in":
            return order.orderType == "dine_in"
        case "take_out":
            return order.orderType == "take_out"
        case "delayed":
            let isOlderThan10Min = now.timeIntervalSince(order.createdAt) >= 600
            return isOlderThan10Min
        default:
            return true
        }
    }
    
    var oldestDelayedOrder: Order? {
        let now = Date()
        return activeOrders
            .filter { order in
                // Skip ghost tickets belonging to inactive table sessions
                if let session = order.tableSession, !session.isActive {
                    return false
                }
                let activeItems = order.items.filter { $0.status == "cooking" || $0.status == "alert" }
                let matchedItems = activeItems.filter { $0.shouldDisplay(showKitchen: kdsShowKitchen, showBar: kdsShowBar) }
                guard !matchedItems.isEmpty else { return false }
                
                let isOlderThan10Min = now.timeIntervalSince(order.createdAt) >= 600
                return isOlderThan10Min
            }
            .first
    }
    
    private func countForFilter(_ filter: String) -> Int {
        var count = 0
        let now = Date()
        for order in activeOrders {
            // Skip ghost tickets belonging to inactive table sessions
            if let session = order.tableSession, !session.isActive {
                continue
            }
            let activeKitchenItems = order.items.filter { ($0.status == "cooking" || $0.status == "alert") && !$0.isBeverage }
            let activeBarItems = order.items.filter { ($0.status == "cooking" || $0.status == "alert") && $0.isBeverage }
            
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
        ZStack {
            Color.appBackground.ignoresSafeArea()
                    
                    VStack(spacing: 0) {
                        // 1. Flashing warning banner for the oldest active delayed order (FIFO priority)
                        if let delayed = oldestDelayedOrder {
                            let minutes = Int(currentSecond.timeIntervalSince(delayed.createdAt) / 60)
                            let alertMsg = delayed.status == "ready"
                                ? "Delivery Alert: Table \(delayed.tableSession?.table?.tableNumber ?? "1") (#\(delayed.orderNumber.suffix(4))) has been ready but not delivered for \(minutes) minutes!"
                                : "Delayed Order Alert: Table \(delayed.tableSession?.table?.tableNumber ?? "1") (#\(delayed.orderNumber.suffix(4))) has been cooking for \(minutes) minutes!"
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
                        
                        // 2. Search & Filter subbar
                        HStack(spacing: 16) {
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
                            .frame(width: isWide ? 260 : 180)
                            .offset(x: isViewAppeared ? 0 : -40)
                            .opacity(isViewAppeared ? 1 : 0)
                            
                            Spacer()
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    filterPill(title: "pos_category_all".t, tag: "all", count: countForFilter("all"))
                                    filterPill(title: "pos_dine_in".t, tag: "dine_in", count: countForFilter("dine_in"))
                                    filterPill(title: "pos_take_out".t, tag: "take_out", count: countForFilter("take_out"))
                                    filterPill(title: "kds_delayed_pill".t, tag: "delayed", count: countForFilter("delayed"), isDestructive: true)
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
                        
                        // 3. Main content area
                        if filteredTickets.isEmpty {
                            VStack(spacing: 20) {
                                Image(systemName: "flame.fill")
                                    .font(.system(size: 60))
                                    .foregroundColor(.textTertiary)
                                Text("kds_no_active_tickets".t)
                                    .font(.title3)
                                    .foregroundColor(.textSecondary)
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
                                            KitchenPremiumTicketCard(ticket: ticket, onSelect: { selectedTicket = ticket })
                                                .transition(.asymmetric(
                                                    insertion: .scale(scale: 0.9).combined(with: .opacity).combined(with: .move(edge: .bottom)),
                                                    removal: .opacity
                                                ))
                                        }
                                    }
                                    .padding()
                                } else {
                                    // Enhanced original grid view (compact layout)
                                    LazyVGrid(columns: columns, spacing: 12) {
                                        ForEach(filteredTickets) { ticket in
                                            KitchenTicketView(ticket: ticket, onSelect: { selectedTicket = ticket })
                                                .transition(.asymmetric(
                                                    insertion: .scale(scale: 0.9).combined(with: .opacity),
                                                    removal: .opacity
                                                ))
                                        }
                                    }
                                    .padding()
                                }
                            }
                            .offset(y: isViewAppeared ? 0 : 50)
                            .opacity(isViewAppeared ? 1 : 0)
                        }
                    }
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .onAppear {
                                    isWide = geo.size.width > 850
                                }
                                .onChange(of: geo.size.width) { _, newWidth in
                                    isWide = newWidth > 850
                                }
                        }
                    )
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: filteredTickets)
                    
                    if showingHistoryDrawer {
                        historyDrawerOverlay
                    }
                }
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .apNavBar(background: Color.appBackground)
                .fullScreenCover(item: $selectedTicket) { ticket in
                    KitchenOrderDetailView(ticket: ticket)
                }
                .sheet(isPresented: $showingHelpView) {
                    KDSHelpView()
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        HStack(spacing: 8) {
                            Text(isWide ? "kds_queue_wide".t : "kds_queue_narrow".t)
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundColor(.textPrimary)
                                .layoutPriority(1)
                                .fixedSize(horizontal: true, vertical: false)
                            
                            Text("\(filteredTickets.count)")
                                .font(.system(size: 11, weight: .bold))
                                .frame(minWidth: 18)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.appAccent.opacity(0.15))
                                .foregroundColor(.appAccent)
                                .clipShape(Capsule())
                                .layoutPriority(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .fixedSize(horizontal: true, vertical: false)
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
            
            // KDS Sound Alert: play notification sound when a new order arrives
            if kdsSoundEnabled {
                let currentCount = activeOrders.count
                if currentCount > previousActiveOrderCount && previousActiveOrderCount > 0 {
                    APHaptic.trigger()
                    AudioServicesPlaySystemSound(1007)
                }
                previousActiveOrderCount = currentCount
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.65, dampingFraction: 0.75)) {
                isViewAppeared = true
            }
        }
        .onDisappear {
            isViewAppeared = false
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
                        let stationServedOrders = servedOrders.filter { order in
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
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack(alignment: .top) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(LocalizationManager.shared.t("table_number_template", order.tableSession?.table?.tableNumber ?? "1"))
                                                .font(.system(size: 13, weight: .bold))
                                                .foregroundColor(.textPrimary)
                                            Text("#\(order.orderNumber.suffix(4))")
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
                                                    Text(item.menuItem?.name ?? "Unknown Item")
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
            order.status = "preparing"
            for item in order.items {
                if item.status == "served" && item.shouldDisplay(showKitchen: kdsShowKitchen, showBar: kdsShowBar) {
                    item.status = "cooking"
                    item.updatedAt = Date()
                    item.isSynced = false
                }
            }
            order.updatedAt = Date()
            order.isSynced = false
            try? modelContext.save()
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
            lastOrder.status = "preparing"
            for item in lastOrder.items {
                if item.status == "served" {
                    item.status = "cooking"
                    item.isSynced = false
                    item.updatedAt = Date()
                }
            }
            lastOrder.updatedAt = Date()
            lastOrder.isSynced = false
            try? modelContext.save()
            APHaptic.trigger()
        }
    }
    
    /// KDS Auto-Complete: When enabled, automatically transitions orders from "ready" to "served"
    /// when ALL items in the order have a terminal status (served or cancelled).
    private func performAutoCompleteCheck() {
        var didAutoComplete = false
        
        for order in activeOrders {
            // Only auto-complete orders that are currently "ready" (all items cooked, awaiting delivery confirmation)
            guard order.status == "ready" else { continue }
            
            // Skip ghost tickets belonging to inactive table sessions
            if let session = order.tableSession, !session.isActive {
                continue
            }
            
            // Check if ALL items in the order are in a terminal state (served or cancelled)
            let allItemsDone = order.items.allSatisfy { item in
                item.status == "served" || item.status == "cancelled"
            }
            
            if allItemsDone {
                order.status = "served"
                order.updatedAt = Date()
                order.isSynced = false
                didAutoComplete = true
            }
        }
        
        if didAutoComplete {
            try? modelContext.save()
            APHaptic.trigger()
        }
    }
}

// MARK: - Premium KDS Ticket Card (Requested Design Layout)

struct KitchenPremiumTicketCard: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var lm: LocalizationManager
    var ticket: KDSTicket
    var onSelect: () -> Void
    
    var order: Order { ticket.order }
    var station: KDSStation { ticket.station }
    
    @State private var elapsedTime = 0
    @State private var elapsedSeconds = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var groupedItems: [(category: String, items: [OrderItem])] {
        let activeItems = order.items.filter { $0.status == "cooking" || $0.status == "alert" }
        let filtered = activeItems.filter { item in
            if station == .kitchen {
                return !item.isBeverage
            } else {
                return item.isBeverage
            }
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
                        Text(LocalizationManager.shared.t("table_number_template", order.tableSession?.table?.tableNumber ?? "1"))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(elapsedTime >= 5 ? headerTextColor() : .textSecondary)
                        Text("#\(order.orderNumber.suffix(4))")
                            .font(.system(size: 18, weight: .black))
                            .foregroundColor(elapsedTime >= 5 ? headerTextColor() : .textPrimary)
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "timer")
                        Text(timeString(seconds: elapsedSeconds))
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(elapsedTime >= 5 ? headerTextColor() : .appAccent)
                }
                
                if elapsedTime < 5 {
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
                                    HStack(alignment: .top, spacing: 8) {
                                        Text("\(item.quantity)")
                                            .font(.system(size: 14, weight: .black))
                                            .foregroundColor(item.status == "alert" ? .appRose : .textPrimary)
                                            .frame(width: 14, alignment: .leading)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.menuItem?.name ?? "Unknown Item")
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundColor(item.status == "alert" ? .appRose : .textPrimary)
                                                .multilineTextAlignment(.leading)
                                            
                                            if !item.modifiers.isEmpty {
                                                Text(item.modifiers.compactMap { $0.modifier?.name }.joined(separator: ", "))
                                                    .font(.system(size: 10))
                                                    .foregroundColor(.appTeal)
                                                    .multilineTextAlignment(.leading)
                                            }
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, 2)
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
                Button(action: alertWaiter) {
                    Text("kds_request_waiter".t)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.appTeal)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Button(action: serveEntireTicket) {
                    Text("kds_serve".t)
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
                .accessibilityLabel("Mark order as ready")
                .accessibilityHint("Double-tap to mark all items as ready")
            }
            .padding(10)
            .background(Color.appSurfaceHigh.opacity(0.5))
        }
        .frame(width: 240, height: 380)
        .background(Color.appSurface)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColor(), lineWidth: borderWidth())
        )
        .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 3)
        .onTapGesture(perform: onSelect)
        .accessibilityLabel("Order \(order.orderNumber), \(order.items.count) items")
        .accessibilityHint("Double-tap to view order details")
        .onAppear(perform: updateElapsedTime)
        .onReceive(timer) { _ in
            updateElapsedTime()
        }
    }
    
    private func updateElapsedTime() {
        let diff = Date().timeIntervalSince(order.createdAt)
        elapsedSeconds = Int(diff)
        elapsedTime = Int(diff / 60)
    }
    
    private func timeString(seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }
    
    private func headerColor() -> Color {
        if elapsedTime >= 10 { return .appRose }
        if elapsedTime >= 5  { return .appAmber }
        return Color.appSurface
    }
    
    private func headerTextColor() -> Color {
        if elapsedTime >= 5 && elapsedTime < 10 { return .black }
        return .white
    }
    
    private func borderColor() -> Color {
        if elapsedTime >= 10 { return .appRose }
        if elapsedTime >= 5  { return .appAmber }
        if station == .bar { return Color.appTeal.opacity(0.4) }
        return Color.appBorderSubtle
    }
    
    private func borderWidth() -> CGFloat {
        if elapsedTime >= 5 { return 2 }
        return 1
    }
    
    private func alertWaiter() {
        Task {
            let tableNum = order.tableSession?.table?.tableNumber ?? "1"
            _ = try? await NetworkManager.shared.createServiceRequest(
                tableNumber: tableNum,
                type: "KDS Alert: Table \(tableNum) Requesting Waiter"
            )
        }
        APHaptic.trigger()
    }
    
    private func serveEntireTicket() {
        withAnimation {
            var didChange = false
            for item in order.items {
                let matchStation = (station == .kitchen) ? !item.isBeverage : item.isBeverage
                if (item.status == "cooking" || item.status == "alert") && matchStation {
                    item.status = "served"
                    item.updatedAt = Date()
                    item.isSynced = false
                    didChange = true
                }
            }
            if didChange {
                order.isSynced = false
                order.updatedAt = Date()
                
                let hasActiveItems = order.items.contains { $0.status == "cooking" || $0.status == "alert" }
                if !hasActiveItems {
                    order.status = "ready"
                }
                try? modelContext.save()
            }
        }
        APHaptic.trigger()
    }
}

// MARK: - Original KDS Ticket View Component (Enhanced & Compacted)

struct KitchenTicketView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var lm: LocalizationManager
    var ticket: KDSTicket
    var onSelect: () -> Void
    
    var order: Order { ticket.order }
    var station: KDSStation { ticket.station }
    
    @State private var elapsedTime = 0
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    
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
                        Text(LocalizationManager.shared.t("table_number_template", order.tableSession?.table?.tableNumber ?? "1"))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(elapsedTime >= 5 ? headerTextColor() : .textSecondary)
                        Text("#\(order.orderNumber.suffix(4))")
                            .font(.system(size: 14, weight: .black))
                            .foregroundColor(elapsedTime >= 5 ? headerTextColor() : .textPrimary)
                    }
                    Spacer()
                    
                    // Timer
                    HStack(spacing: 3) {
                        Image(systemName: "timer")
                            .font(.system(size: 9))
                        Text("\(elapsedTime)m")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(elapsedTime >= 5 ? headerTextColor() : .appAccent)
                }
                
                if elapsedTime < 5 {
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
                    let activeItems = order.items.filter { $0.status == "cooking" || $0.status == "alert" }
                    let displayedItems = activeItems.filter { item in
                        if station == .kitchen {
                            return !item.isBeverage
                        } else {
                            return item.isBeverage
                        }
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
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(alignment: .top) {
                                    Text("\(item.quantity)x")
                                        .font(.system(size: 11, weight: .black))
                                        .foregroundColor(item.status == "alert" ? .appRose : .appAmber)
                                        .frame(width: 14, alignment: .leading)
                                    
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(item.menuItem?.name ?? "Unknown Item")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor(item.status == "alert" ? .appRose : .textPrimary)
                                            .multilineTextAlignment(.leading)
                                        
                                        if !item.modifiers.isEmpty {
                                            Text(item.modifiers.compactMap { $0.modifier?.name }.joined(separator: ", "))
                                                .font(.system(size: 9))
                                                .foregroundColor(.textSecondary)
                                                .multilineTextAlignment(.leading)
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    // Compact Action Buttons
                                    HStack(spacing: 4) {
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
                Button(action: alertWaiter) {
                    Text("kds_request_waiter".t)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.appTeal)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                let hasActiveItemsForStation = order.items.contains(where: {
                    let matchStation = (station == .kitchen) ? !$0.isBeverage : $0.isBeverage
                    return ($0.status == "cooking" || $0.status == "alert") && matchStation
                })
                if hasActiveItemsForStation {
                    Button(action: serveEntireTicket) {
                        Text("kds_serve".t)
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
                        Text("pos_clear".t)
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
                .stroke(borderColor(), lineWidth: borderWidth())
        )
        .shadow(color: Color.black.opacity(0.15), radius: 4)
        .onAppear(perform: updateElapsedTime)
        .onReceive(timer) { _ in
            updateElapsedTime()
        }
    }
    
    private func updateElapsedTime() {
        let diff = Date().timeIntervalSince(order.createdAt)
        elapsedTime = Int(diff / 60)
    }
    
    private func headerColor() -> Color {
        if elapsedTime >= 10 { return .appRose }
        if elapsedTime >= 5  { return .appAmber }
        return Color.appSurface
    }
    
    private func headerTextColor() -> Color {
        if elapsedTime >= 5 && elapsedTime < 10 { return .black }
        return .white
    }
    
    private func borderColor() -> Color {
        if elapsedTime >= 10 { return .appRose }
        if elapsedTime >= 5  { return .appAmber }
        if station == .bar { return Color.appTeal.opacity(0.4) }
        return Color.appBorderSubtle
    }
    
    private func borderWidth() -> CGFloat {
        if elapsedTime >= 5 { return 2 }
        return 1
    }
    
    private func serveItem(_ item: OrderItem) {
        withAnimation {
            item.status = "served"
            item.updatedAt = Date()
            item.isSynced = false
            
            order.isSynced = false
            order.updatedAt = Date()
            
            let activeItems = order.items.filter { $0.status == "cooking" || $0.status == "alert" }
            if activeItems.isEmpty {
                order.status = "ready"
            }
            try? modelContext.save()
        }
    }
    
    private func alertItem(_ item: OrderItem) {
        withAnimation {
            item.status = "alert"
            item.updatedAt = Date()
            item.isSynced = false
            
            order.isSynced = false
            order.updatedAt = Date()
            try? modelContext.save()
        }
        
        Task {
            let tableNum = order.tableSession?.table?.tableNumber ?? "1"
            let itemName = item.menuItem?.name ?? "Unknown Item"
            _ = try? await NetworkManager.shared.createServiceRequest(
                tableNumber: tableNum,
                type: "Kitchen Alert: \(itemName) Issue"
            )
        }
    }
    
    private func alertWaiter() {
        Task {
            let tableNum = order.tableSession?.table?.tableNumber ?? "1"
            _ = try? await NetworkManager.shared.createServiceRequest(
                tableNumber: tableNum,
                type: "KDS Alert: Table \(tableNum) Requesting Waiter"
            )
        }
        APHaptic.trigger()
    }
    
    private func serveEntireTicket() {
        withAnimation {
            var didChange = false
            for item in order.items {
                let matchStation = (station == .kitchen) ? !item.isBeverage : item.isBeverage
                if (item.status == "cooking" || item.status == "alert") && matchStation {
                    item.status = "served"
                    item.updatedAt = Date()
                    item.isSynced = false
                    didChange = true
                }
            }
            if didChange {
                order.isSynced = false
                order.updatedAt = Date()
                
                let hasActiveItems = order.items.contains { $0.status == "cooking" || $0.status == "alert" }
                if !hasActiveItems {
                    order.status = "ready"
                }
                try? modelContext.save()
            }
        }
        APHaptic.trigger()
    }
    
    private func completeTicket() {
        withAnimation {
            var didChange = false
            for item in order.items {
                let matchStation = (station == .kitchen) ? !item.isBeverage : item.isBeverage
                if (item.status == "cooking" || item.status == "alert") && matchStation {
                    item.status = "served"
                    item.updatedAt = Date()
                    item.isSynced = false
                    didChange = true
                }
            }
            if didChange {
                order.isSynced = false
                order.updatedAt = Date()
                
                let hasActiveItems = order.items.contains { $0.status == "cooking" || $0.status == "alert" }
                if !hasActiveItems {
                    order.status = "served"
                }
                try? modelContext.save()
            }
        }
        APHaptic.trigger()
    }
}
// MARK: - Full Screen Detail View

struct KitchenOrderDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var lm: LocalizationManager
    var ticket: KDSTicket
    
    var order: Order { ticket.order }
    var station: KDSStation { ticket.station }
    
    @State private var elapsedTime = 0
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    
    private var footerActionTitle: String {
        if station == .kitchen {
            return "kds_mark_kitchen_ready".t
        } else {
            return "kds_mark_bar_ready".t
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header Panel - Redesigned to be charcoal gray dark mode
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 12) {
                            Text(LocalizationManager.shared.t("table_number_template", order.tableSession?.table?.tableNumber ?? "1"))
                                .font(.system(size: 32, weight: .black, design: .rounded))
                                .foregroundColor(.textPrimary)
                            
                            // Station badge
                            HStack(spacing: 4) {
                                Image(systemName: station == .kitchen ? "flame.fill" : "wineglass.fill")
                                Text(station == .kitchen ? "kds_station_kitchen_upper".t : "kds_station_bar_upper".t)
                            }
                            .font(.system(size: 11, weight: .black))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(station == .kitchen ? Color.appRose.opacity(0.15) : Color.appTeal.opacity(0.15))
                            .foregroundColor(station == .kitchen ? .appRose : .appTeal)
                            .cornerRadius(6)
                        }
                        
                        HStack(spacing: 12) {
                            Text("#\(order.orderNumber.suffix(4))")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.textSecondary)
                            
                            // Premium Styled Order Type Badge
                            Text(order.orderType == "dine_in" ? "Dine-In" : "Take-Out")
                                .font(.system(size: 11, weight: .bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(order.orderType == "dine_in" ? Color.appTeal.opacity(0.15) : Color.appAmber.opacity(0.15))
                                .foregroundColor(order.orderType == "dine_in" ? .appTeal : .appAmber)
                                .cornerRadius(6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(order.orderType == "dine_in" ? Color.appTeal.opacity(0.3) : Color.appAmber.opacity(0.3), lineWidth: 0.8)
                                )
                        }
                    }
                    
                    Spacer()
                    
                    // Large Timer Badge
                    HStack(spacing: 6) {
                        Image(systemName: "timer")
                            .font(.system(size: 13, weight: .bold))
                        Text(LocalizationManager.shared.t("kds_active_timer_template", elapsedTime))
                            .font(.system(size: 13, weight: .bold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(timerColor().opacity(0.15))
                    .foregroundColor(timerColor())
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(timerColor().opacity(0.3), lineWidth: 0.8)
                    )
                    
                    // Sleek Close button
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .black))
                            .foregroundColor(.textSecondary)
                            .padding(12)
                            .background(Color.appSurfaceHigh)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(Color.appBorderSubtle, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 20)
                .background(Color.appSurfaceHigh)
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(Color.appDivider),
                    alignment: .bottom
                )
                
                // Detailed Items List
                ScrollView {
                    VStack(spacing: 16) {
                        let activeItems = order.items.filter { $0.status == "cooking" || $0.status == "alert" }
                        let displayedItems = activeItems.filter { item in
                            if station == .kitchen {
                                return !item.isBeverage
                            } else {
                                return item.isBeverage
                            }
                        }
                        
                        if displayedItems.isEmpty {
                            VStack(spacing: 20) {
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 70))
                                    .foregroundColor(.appTeal)
                                Text("kds_all_station_completed".t)
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.textPrimary)
                                Text("kds_dismiss_ticket_hint".t)
                                    .font(.subheadline)
                                    .foregroundColor(.textSecondary)
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, minHeight: 450)
                        } else {
                            ForEach(displayedItems) { item in
                                HStack(alignment: .center, spacing: 20) {
                                    // Big Quantity Label
                                    Text("\(item.quantity)x")
                                        .font(.system(size: 22, weight: .black, design: .rounded))
                                        .foregroundColor(item.status == "alert" ? .appRose : .appAmber)
                                        .frame(width: 54, height: 54)
                                        .background(item.status == "alert" ? Color.appRose.opacity(0.12) : Color.appAmber.opacity(0.12))
                                        .cornerRadius(10)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(item.status == "alert" ? Color.appRose.opacity(0.25) : Color.appAmber.opacity(0.25), lineWidth: 1)
                                        )
                                    
                                    // Food details
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.menuItem?.name ?? "Unknown Item")
                                            .font(.system(size: 20, weight: .bold))
                                            .foregroundColor(item.status == "alert" ? .appRose : .textPrimary)
                                        
                                        if !item.modifiers.isEmpty {
                                            Text(item.modifiers.compactMap { $0.modifier?.name }.joined(separator: ", "))
                                                .font(.system(size: 13, weight: .medium))
                                                .foregroundColor(.appTeal)
                                        }
                                        
                                        if item.status == "alert" {
                                            HStack(spacing: 4) {
                                                Image(systemName: "exclamationmark.triangle.fill")
                                                    .font(.caption2)
                                                Text("kds_staff_alerted".t)
                                                    .font(.system(size: 11, weight: .bold))
                                            }
                                            .foregroundColor(.appAmber)
                                            .padding(.top, 2)
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    // Premium Action Buttons
                                    HStack(spacing: 10) {
                                        // Alert Waiter Button
                                        Button(action: { alertItem(item) }) {
                                            HStack(spacing: 4) {
                                                Image(systemName: "exclamationmark.triangle")
                                                Text("kds_alert_staff".t)
                                            }
                                            .font(.system(size: 12, weight: .bold))
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 10)
                                            .background(Color.appAmber.opacity(item.status == "alert" ? 0.05 : 0.12))
                                            .foregroundColor(item.status == "alert" ? Color.appAmber.opacity(0.4) : .appAmber)
                                            .cornerRadius(8)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(Color.appAmber.opacity(item.status == "alert" ? 0.1 : 0.3), lineWidth: 0.8)
                                            )
                                        }
                                        .buttonStyle(.plain)
                                        .disabled(item.status == "alert")
                                        
                                        // Cancel Button
                                        Button(action: { rejectItem(item) }) {
                                            HStack(spacing: 4) {
                                                Image(systemName: "xmark.circle")
                                                Text("cancel".t)
                                            }
                                            .font(.system(size: 12, weight: .bold))
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 10)
                                            .background(Color.appRose.opacity(0.12))
                                            .foregroundColor(.appRose)
                                            .cornerRadius(8)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(Color.appRose.opacity(0.3), lineWidth: 0.8)
                                            )
                                        }
                                        .buttonStyle(.plain)
                                        
                                        // Serve Button
                                        Button(action: { serveItem(item) }) {
                                            HStack(spacing: 4) {
                                                Image(systemName: "checkmark.circle")
                                                Text("kds_serve".t)
                                            }
                                            .font(.system(size: 12, weight: .bold))
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 10)
                                            .background(Color.appTeal.opacity(0.12))
                                            .foregroundColor(.appTeal)
                                            .cornerRadius(8)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(Color.appTeal.opacity(0.3), lineWidth: 0.8)
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(18)
                                .background(Color.appSurface)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.appBorderSubtle, lineWidth: 1)
                                )
                            }
                        }
                    }
                    .padding(32)
                }
                .background(Color.appBackground)
                
                // Big Action Footer Panel
                VStack(spacing: 0) {
                    let hasActiveItemsForStation = order.items.contains(where: {
                        let matchStation = (station == .kitchen) ? !$0.isBeverage : $0.isBeverage
                        return ($0.status == "cooking" || $0.status == "alert") && matchStation
                    })
                    if hasActiveItemsForStation {
                        Button(action: {
                            serveEntireTicket()
                            dismiss()
                        }) {
                            Text(footerActionTitle)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 18)
                                .background(APGradient.positive)
                                .cornerRadius(12)
                                .shadow(color: Color.appTeal.opacity(0.2), radius: 8, x: 0, y: 4)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .accessibilityLabel("Mark order as ready")
                        .accessibilityHint("Double-tap to mark all items as ready")
                        .padding(.horizontal, 32)
                        .padding(.vertical, 20)
                    } else {
                        Button(action: {
                            completeTicket()
                            dismiss()
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 16, weight: .bold))
                                Text("kds_clear_delivered".t)
                            }
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(Color.appTeal)
                            .cornerRadius(12)
                            .shadow(color: Color.appTeal.opacity(0.2), radius: 8, x: 0, y: 4)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.horizontal, 32)
                        .padding(.vertical, 20)
                    }
                }
                .background(Color.appSurfaceHigh)
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(Color.appDivider),
                    alignment: .top
                )
            }
            .background(Color.appBackground)
            .apColorScheme() // Force custom color scheme resolution!
        }
        .onAppear(perform: updateElapsedTime)
        .onReceive(timer) { _ in
            updateElapsedTime()
        }
    }
    
    private func updateElapsedTime() {
        let diff = Date().timeIntervalSince(order.createdAt)
        elapsedTime = Int(diff / 60)
    }
    
    private func timerColor() -> Color {
        if elapsedTime >= 15 { return .appRose }
        if elapsedTime >= 8  { return .appAmber }
        return .appTeal
    }
    
    private func serveItem(_ item: OrderItem) {
        withAnimation {
            item.status = "served"
            item.updatedAt = Date()
            item.isSynced = false
            
            order.isSynced = false
            order.updatedAt = Date()
            
            let activeItems = order.items.filter { $0.status == "cooking" || $0.status == "alert" }
            if activeItems.isEmpty {
                order.status = "ready"
            }
            try? modelContext.save()
            
            // Check if all active items matching this station have been served
            let activeItemsForStation = order.items.filter { ($0.status == "cooking" || $0.status == "alert") && (station == .kitchen ? !$0.isBeverage : $0.isBeverage) }
            if activeItemsForStation.isEmpty {
                dismiss()
            }
        }
    }
    
    private func alertItem(_ item: OrderItem) {
        withAnimation {
            item.status = "alert"
            item.updatedAt = Date()
            item.isSynced = false
            
            order.isSynced = false
            order.updatedAt = Date()
            try? modelContext.save()
        }
        
        Task {
            let tableNum = order.tableSession?.table?.tableNumber ?? "1"
            let itemName = item.menuItem?.name ?? "Unknown Item"
            _ = try? await NetworkManager.shared.createServiceRequest(
                tableNumber: tableNum,
                type: "Kitchen Alert: \(itemName) Issue"
            )
        }
    }
    
    private func rejectItem(_ item: OrderItem) {
        withAnimation {
            item.status = "cancelled"
            item.updatedAt = Date()
            item.isSynced = false
            
            order.isSynced = false
            order.updatedAt = Date()
            
            let activeItems = order.items.filter { $0.status == "cooking" || $0.status == "alert" }
            if activeItems.isEmpty {
                order.status = "ready"
            }
            try? modelContext.save()
            
            // Check if all active items matching this station have been served/cancelled
            let activeItemsForStation = order.items.filter { ($0.status == "cooking" || $0.status == "alert") && (station == .kitchen ? !$0.isBeverage : $0.isBeverage) }
            if activeItemsForStation.isEmpty {
                dismiss()
            }
        }
    }
    
    private func serveEntireTicket() {
        var didChange = false
        for item in order.items {
            let matchStation = (station == .kitchen) ? !item.isBeverage : item.isBeverage
            if (item.status == "cooking" || item.status == "alert") && matchStation {
                item.status = "served"
                item.updatedAt = Date()
                item.isSynced = false
                didChange = true
            }
        }
        if didChange {
            order.isSynced = false
            order.updatedAt = Date()
            
            let hasActiveItems = order.items.contains { $0.status == "cooking" || $0.status == "alert" }
            if !hasActiveItems {
                order.status = "ready"
            }
            try? modelContext.save()
        }
    }
    
    private func completeTicket() {
        // Serve all items for this station (just in case)
        var didChange = false
        for item in order.items {
            let matchStation = (station == .kitchen) ? !item.isBeverage : item.isBeverage
            if (item.status == "cooking" || item.status == "alert") && matchStation {
                item.status = "served"
                item.updatedAt = Date()
                item.isSynced = false
                didChange = true
            }
        }
        if didChange {
            order.isSynced = false
            order.updatedAt = Date()
            
            let hasActiveItems = order.items.contains { $0.status == "cooking" || $0.status == "alert" }
            if !hasActiveItems {
                order.status = "served"
            }
            try? modelContext.save()
        }
    }
}

// MARK: - KDS Item Classification Extension
extension OrderItem {
    var isBeverage: Bool {
        guard let catName = menuItem?.category?.name else { return false }
        let lower = catName.lowercased()
        return lower.contains("beverage") || lower.contains("drink") || lower.contains("juice") || lower.contains("tea") || lower.contains("coffee")
    }
    
    func shouldDisplay(showKitchen: Bool, showBar: Bool) -> Bool {
        if showKitchen && showBar {
            return true
        } else if showKitchen {
            return !isBeverage
        } else if showBar {
            return isBeverage
        } else {
            return false
        }
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
