import SwiftUI
import Combine

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Supporting Types
// ─────────────────────────────────────────────────────────────────────────────

struct EditTarget: Identifiable {
    let id   = UUID()
    let item:  OrderItem
    let order: Order
}

// Table "still dining" status after payment
enum PostPaymentDiningStatus: String {
    case paid          // just paid, unknown if still seated
    case stillDining   // paid but customer confirmed still eating
    case left          // table confirmed clear
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - TableDetailView
// ─────────────────────────────────────────────────────────────────────────────

struct TableDetailView: View {
    let table: RestaurantTable
    @AppStorage("app_language") private var appLanguage = "en"
    @AppStorage("logged_in_employee_id") private var loggedInEmployeeId = ""
    @AppStorage("logged_in_employee_name") private var loggedInEmployeeName = ""

    // ── Order state ───────────────────────────────────────────────────────────
    @State private var networkService = NetworkService.shared
    @State private var orders: [Order] = []
    @State private var isLoading = false
    @State private var showingAddItemsSheet = false
    @State private var selectedCategory = "all"
    @State private var cartItems: [MenuItem: Int] = [:]
    @State private var showShiftGuard = false
    @State private var servingItemIds = Set<String>()

    // ── Item action states ────────────────────────────────────────────────────
    @State private var editTarget:   EditTarget? = nil
    @State private var deleteTarget: EditTarget? = nil

    // ── Post-payment dining state ─────────────────────────────────────────────
    @State private var postPaymentStatus: PostPaymentDiningStatus? = nil
    @State private var showStillDiningConfirm = false
    @State private var showClearTableConfirm  = false
    @State private var stillDiningTimer: Timer? = nil
    @State private var stillDiningReminderCount = 0
    @State private var lastDiningCheckAt: Date? = nil

    // ── "Serve all" progress ──────────────────────────────────────────────────
    @State private var isServingAll = false
    // H-4: Track partial serve failures
    @State private var serveFailedCount: Int = 0
    @State private var showServePartialFailAlert = false

    @Environment(\.dismiss) private var dismiss

    // Design tokens
    private let royalBlue = Color.appAccent
    private let elfGreen  = Color.appTeal
    private let coralRed  = Color.appRose
    private let amber     = Color.appAmber

    // MARK: - Computed

    private var currentTable: RestaurantTable {
        networkService.tables.first(where: { $0.tableNumber == table.tableNumber }) ?? table
    }

    /// Orders that are still active (not completed / not cancelled)
    private var activeOrders: [Order] {
        orders.filter { $0.status != "completed" && $0.status != "cancelled" }
    }

    /// Orders from the web ordering channel
    private var webOrders: [Order] {
        activeOrders.filter { $0.sessionToken != nil }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// Orders from staff (no sessionToken or created by staff)
    private var staffOrders: [Order] {
        activeOrders.filter { $0.sessionToken == nil }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private var hasAnyActiveOrders: Bool { !activeOrders.isEmpty }

    private var shouldShowEmptyState: Bool {
        !hasAnyActiveOrders && postPaymentStatus == nil
    }

    private var isAllServed: Bool {
        // If kitchen workflow is disabled, payment is always allowed.
        if !networkService.kitchenWorkflowRequired { return true }
        guard hasAnyActiveOrders else { return false }

        // Primary check: use local @State orders (updated on every loadOrders call).
        // Secondary check: cross-verify against NetworkService.shared.orders so
        // a stale @State doesn't falsely return true when items are still cooking.
        // The more restrictive result wins — if EITHER source has unserved items → false.
        for order in activeOrders {
            for item in order.items where item.status != "served" && item.status != "cancelled" {
                return false
            }
        }

        // Cross-check with live NetworkService orders for this table
        let liveOrders = networkService.orders.filter {
            $0.tableNumber == table.tableNumber &&
            $0.status != "completed" &&
            $0.status != "cancelled"
        }
        for order in liveOrders {
            for item in order.items where item.status != "served" && item.status != "cancelled" {
                return false   // live data shows unserved item — block checkout
            }
        }

        return true
    }

    /// True when there are unserved items
    private var pendingServeCount: Int {
        activeOrders.flatMap { $0.items }
            .filter { $0.status != "served" && $0.status != "cancelled" }
            .count
    }

    private var isPaidButDining: Bool {
        postPaymentStatus == .stillDining
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Body
    // ─────────────────────────────────────────────────────────────────────────
    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // H-7 FIX: Offline banner in TableDetailView
                if networkService.connectionError {
                    HStack(spacing: 8) {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                        Text("ออฟไลน์ — ข้อมูลอาจล่าช้า")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.appRose)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                infoBanner
                Divider().background(Color.appDivider)

                // Post-payment dining banner
                if let status = postPaymentStatus, status != .left {
                    postPaymentBanner(status)
                }

                if isLoading {
                    ProgressView().tint(royalBlue).frame(maxHeight: .infinity)
                } else if shouldShowEmptyState {
                    emptyState
                } else {
                    orderScrollContent
                }

                bottomBar
            }
        }
        .navigationTitle("table_details".localized(for: appLanguage))
        .navigationBarTitleDisplayMode(.inline)
        // ── Sheets & dialogs ─────────────────────────────────────────────────
        .sheet(item: $editTarget) { target in
            EditOrderItemSheet(
                item: target.item, order: target.order,
                appLanguage: appLanguage,
                royalBlue: royalBlue, elfGreen: elfGreen, coralRed: coralRed
            )
        }
        .confirmationDialog(
            "delete_item_confirm".localized(for: appLanguage),
            isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }),
            titleVisibility: .visible
        ) {
            Button("delete".localized(for: appLanguage), role: .destructive) {
                if let target = deleteTarget { deleteItem(target.item, from: target.order) }
            }
            Button("cancel".localized(for: appLanguage), role: .cancel) {}
        }
        .sheet(isPresented: $showingAddItemsSheet) {
            AddItemsToOrderSheet(table: currentTable, cartItems: $cartItems)
        }
        .fullScreenCover(isPresented: $showShiftGuard) {
            ShiftGuardOverlay()
        }
        // ── Still dining reminder alert ───────────────────────────────────────
        .alert("🪑 ลูกค้ายังนั่งอยู่ไหม?", isPresented: $showStillDiningConfirm) {
            Button("ยังนั่งอยู่") {
                postPaymentStatus = .stillDining
                stillDiningReminderCount += 1
                lastDiningCheckAt = Date()
                scheduleNextDiningCheck()
            }
            Button("ลูกค้าไปแล้ว — เคลียร์โต๊ะ", role: .destructive) {
                clearTableAfterDining()
            }
        } message: {
            let mins = stillDiningReminderCount == 0 ? 15 : 10
            Text("ชำระเงินไปแล้ว \(mins) นาที โต๊ะ \(currentTable.tableNumber) ยังไม่ถูกเคลียร์ ลูกค้ายังนั่งรับประทานอยู่หรือเปล่า?")
        }
        // ── Clear table confirm ───────────────────────────────────────────────
        .confirmationDialog("เคลียร์โต๊ะ \(currentTable.tableNumber)?",
                            isPresented: $showClearTableConfirm,
                            titleVisibility: .visible) {
            Button("ยืนยันเคลียร์โต๊ะ", role: .destructive) {
                clearTableAfterDining()
            }
            Button("ยกเลิก", role: .cancel) {}
        } message: {
            Text("โต๊ะจะถูก reset เป็น Vacant และ session จะถูกปิด")
        }
        // H-4: Partial serve failure alert
        .alert("เสิร์ฟไม่ครบ", isPresented: $showServePartialFailAlert) {
            Button("ลองใหม่") {
                serveFailedCount = 0
                serveAllActiveOrders()
            }
            Button("ยกเลิก", role: .cancel) { serveFailedCount = 0 }
        } message: {
            Text("\(serveFailedCount) รายการเสิร์ฟไม่สำเร็จ\nกรุณาตรวจสอบการเชื่อมต่อแล้วลองใหม่")
        }
        .onAppear {
            Task { await loadOrders() }
        }
        // C-7 FIX: Filter onChange to only fire when orders for THIS table change.
        // Unfiltered onChange(orders) fires for every table — causes unnecessary
        // network round-trips when other tables' orders update.
        .onChange(of: networkService.orders.filter { $0.tableNumber == table.tableNumber }) { _, _ in
            Task { await loadOrders() }
        }
        // H-8 FIX: Invalidate stillDiningTimer when view disappears to prevent
        // timer firing an alert after the view has been dismissed.
        .onDisappear {
            stillDiningTimer?.invalidate()
            stillDiningTimer = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .checkoutCompleted)) { note in
            // BillingView posted this after successful payment
            guard let tableNumber = note.object as? String,
                  tableNumber == table.tableNumber else { return }
            Task {
                await loadOrders()
                await MainActor.run { enterPostPaymentMode() }
            }
        }
        .onChange(of: networkService.tables) { _, newTables in
            // Auto-dismiss when table becomes vacant after payment
            let myTable = newTables.first(where: { $0.tableNumber == table.tableNumber })
            let isNowVacant = myTable?.status == "vacant"
            if isNowVacant && postPaymentStatus == nil {
                // Table cleared remotely — dismiss with animation
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    dismiss()
                }
            } else {
                Task { await loadOrders() }
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Info Banner
    // ─────────────────────────────────────────────────────────────────────────
    private var infoBanner: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill((isPaidButDining ? amber : royalBlue).opacity(0.10))
                    .frame(width: 44, height: 44)
                Image(systemName: isPaidButDining ? "fork.knife.circle.fill" : "fork.knife")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(isPaidButDining ? amber : royalBlue)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(isPaidButDining
                     ? "ชำระเงินแล้ว · ยังนั่งอยู่"
                     : "session_orders".localized(for: appLanguage))
                    .font(.caption2)
                    .foregroundColor(isPaidButDining ? amber : Color.textSecondary)
                Text(String(format: "table_guests_count_format".localized(for: appLanguage),
                            currentTable.tableNumber, currentTable.guestCount))
                    .font(.system(size: 16, weight: .bold)).foregroundColor(Color.textPrimary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if currentTable.status == "occupied" {
                    ElapsedTimeBadge(startedAt: currentTable.sessionStartedAt)
                }
                statusBadge(isPaidButDining ? "dining" : currentTable.status)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Post-Payment Banner
    // ─────────────────────────────────────────────────────────────────────────
    private func postPaymentBanner(_ status: PostPaymentDiningStatus) -> some View {
        HStack(spacing: 10) {
            Image(systemName: status == .stillDining ? "fork.knife.circle.fill" : "checkmark.circle.fill")
                .foregroundColor(status == .stillDining ? amber : elfGreen)
                .font(.system(size: 16))

            VStack(alignment: .leading, spacing: 1) {
                Text(status == .stillDining
                     ? "ลูกค้าชำระเงินแล้ว · ยังนั่งรับประทานอยู่"
                     : "ชำระเงินสำเร็จ — รอยืนยันสถานะโต๊ะ")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(status == .stillDining ? amber : elfGreen)
                if let checked = lastDiningCheckAt {
                    Text("ตรวจสอบล่าสุด \(checked, style: .relative) ที่แล้ว")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if status == .stillDining {
                Button {
                    showClearTableConfirm = true
                } label: {
                    Text("เคลียร์โต๊ะ")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(elfGreen)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            (status == .stillDining ? amber : elfGreen).opacity(0.08)
        )
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor((status == .stillDining ? amber : elfGreen).opacity(0.2)),
            alignment: .bottom
        )
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Order Scroll Content
    // ─────────────────────────────────────────────────────────────────────────
    private var orderScrollContent: some View {
        ScrollView {
            LazyVStack(spacing: 14) {

                // ── Web orders section ──────────────────────────────────────
                if !webOrders.isEmpty {
                    sectionHeader(
                        icon: "network",
                        title: "ออเดอร์จากเว็บ (\(webOrders.count))",
                        color: royalBlue
                    )
                    ForEach(webOrders) { order in
                        orderCard(order, source: .web)
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal:   .scale(scale: 0.92).combined(with: .opacity)
                            ))
                    }
                }

                // ── Staff orders section ────────────────────────────────────
                if !staffOrders.isEmpty {
                    if !webOrders.isEmpty {
                        sectionHeader(
                            icon: "person.fill",
                            title: "ออเดอร์จากพนักงาน (\(staffOrders.count))",
                            color: elfGreen
                        )
                    }
                    ForEach(staffOrders) { order in
                        orderCard(order, source: .staff)
                            .transition(.asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal:   .scale(scale: 0.92).combined(with: .opacity)
                            ))
                    }
                }

                // ── Post-payment: show completed orders as history ──────────
                if isPaidButDining {
                    let completedOrders = orders.filter { $0.status == "completed" }
                    if !completedOrders.isEmpty {
                        sectionHeader(
                            icon: "checkmark.seal.fill",
                            title: "ชำระเงินแล้ว (\(completedOrders.count))",
                            color: .secondary
                        )
                        ForEach(completedOrders) { order in
                            completedOrderCard(order)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .animation(.spring(response: 0.4, dampingFraction: 0.78), value: activeOrders.count)
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Section Header
    // ─────────────────────────────────────────────────────────────────────────
    private func sectionHeader(icon: String, title: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(color)
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(color)
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Order Card
    // ─────────────────────────────────────────────────────────────────────────
    enum OrderSource { case web, staff }

    private func orderCard(_ order: Order, source: OrderSource) -> some View {
        VStack(spacing: 0) {
            // Card header
            HStack(spacing: 8) {
                // Source icon
                Image(systemName: source == .web ? "network" : "person.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(source == .web ? royalBlue : elfGreen)
                    .frame(width: 18)

                Text(order.orderNumber)
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .foregroundColor(source == .web ? royalBlue : elfGreen)

                // Time
                Text(formatOrderTime(order.createdAt))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Spacer()

                let allServed = !order.items.isEmpty &&
                    order.items.allSatisfy { $0.status == "served" || $0.status == "cancelled" }
                orderStatusBadge(allServed ? "served" : order.status)

                // Serve-all button (only if not all served)
                if !allServed && !isServingAll {
                    Button {
                        serveAllItems(in: order)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "tray.full.fill")
                                .font(.system(size: 10))
                            Text("เสิร์ฟทั้งหมด")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(elfGreen)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                (source == .web ? royalBlue : elfGreen).opacity(0.05)
            )

            // Items list
            VStack(spacing: 0) {
                let nonCancelledItems = order.items.filter { $0.status != "cancelled" }
                    .sorted { a, _ in a.status != "served" } // pending items first

                ForEach(Array(nonCancelledItems.enumerated()), id: \.element.id) { idx, item in
                    EnterpriseOrderItemRow(
                        item:        item,
                        royalBlue:   royalBlue,
                        elfGreen:    elfGreen,
                        coralRed:    coralRed,
                        appLanguage: appLanguage,
                        onEdit:   { editTarget   = EditTarget(item: item, order: order) },
                        onNote:   { editTarget   = EditTarget(item: item, order: order) },
                        onDelete: { deleteTarget = EditTarget(item: item, order: order) },
                        onServe:  { serveItem(item, from: order) },
                        onRecall: { recallItem(item, from: order) },
                        isServing: servingItemIds.contains(item.id)
                    )
                    .disabled(servingItemIds.contains(item.id))
                    .opacity(servingItemIds.contains(item.id) ? 0.65 : 1)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal:   .move(edge: .trailing).combined(with: .opacity)
                    ))

                    if idx < nonCancelledItems.count - 1 {
                        Divider().padding(.leading, 14)
                    }
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: order.items.count)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 3)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    source == .web ? royalBlue.opacity(0.12) : Color.clear,
                    lineWidth: source == .web ? 1 : 0
                )
        )
    }

    // Completed order (history card — shown when still dining)
    private func completedOrderCard(_ order: Order) -> some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(elfGreen).font(.system(size: 12))
                Text(order.orderNumber)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                Text("ชำระแล้ว")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(elfGreen)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .opacity(0.6)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Bottom Bar
    // ─────────────────────────────────────────────────────────────────────────
    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider().background(Color.appDivider)

            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    // ── Add Food ─────────────────────────────────────────────
                    Button {
                        cartItems.removeAll()
                        verifyShiftAndAddFood()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 16, weight: .bold))
                            Text("add_food".localized(for: appLanguage))
                                .font(.system(size: 14, weight: .bold))
                        }
                        .foregroundColor(royalBlue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(royalBlue.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12)
                            .stroke(royalBlue.opacity(0.25), lineWidth: 1))
                    }

                    // ── Serve All / Checkout ──────────────────────────────────
                    if hasAnyActiveOrders {
                        if !isAllServed {
                            // Show "เสิร์ฟทั้งหมด" button when there are pending items
                            Button {
                                serveAllActiveOrders()
                            } label: {
                                HStack(spacing: 6) {
                                    if isServingAll {
                                        ProgressView()
                                            .scaleEffect(0.75)
                                            .tint(.white)
                                    } else {
                                        Image(systemName: "tray.full.fill")
                                            .font(.system(size: 14, weight: .bold))
                                    }
                                    Text(isServingAll
                                         ? "กำลังเสิร์ฟ..."
                                         : "เสิร์ฟทั้งหมด (\(pendingServeCount))")
                                        .font(.system(size: 14, weight: .bold))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(
                                    LinearGradient(
                                        colors: [elfGreen, Color.appTeal],
                                        startPoint: .leading, endPoint: .trailing
                                    )
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .disabled(isServingAll)

                        } else {
                            // All served → show checkout button
                            NavigationLink(destination: BillingView(
                                table: currentTable, orders: activeOrders
                            )) {
                                HStack(spacing: 6) {
                                    Image(systemName: "creditcard.fill")
                                        .font(.system(size: 14, weight: .bold))
                                    Text("bill_payment".localized(for: appLanguage))
                                        .font(.system(size: 14, weight: .bold))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(
                                    LinearGradient(
                                        colors: [coralRed, Color.appRose],
                                        startPoint: .leading, endPoint: .trailing
                                    )
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                }

                // ── Hint text ─────────────────────────────────────────────────
                if hasAnyActiveOrders && !isAllServed {
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 11))
                        Text("กรุณาเสิร์ฟออเดอร์ทั้งหมดก่อนชำระเงิน")
                            .font(.caption2)
                    }
                    .foregroundColor(coralRed)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.white)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isAllServed)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: hasAnyActiveOrders)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Empty State
    // ─────────────────────────────────────────────────────────────────────────
    private var emptyState: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(royalBlue.opacity(0.08)).frame(width: 80, height: 80)
                Image(systemName: "cart.badge.plus")
                    .font(.system(size: 34)).foregroundColor(royalBlue)
            }
            Text("no_orders_placed".localized(for: appLanguage))
                .font(.headline).foregroundColor(Color.textSecondary)
            Button {
                cartItems.removeAll()
                verifyShiftAndAddFood()
            } label: {
                Label("order_food".localized(for: appLanguage), systemImage: "plus")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 28).padding(.vertical, 12)
                    .background(LinearGradient(
                        colors: [royalBlue, Color.appAccent],
                        startPoint: .leading, endPoint: .trailing))
                    .clipShape(Capsule())
            }
        }
        .frame(maxHeight: .infinity)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Status Badges
    // ─────────────────────────────────────────────────────────────────────────
    private func statusBadge(_ status: String) -> some View {
        let (label, color): (String, Color) = {
            switch status.lowercased() {
            case "occupied": return ("Active",  coralRed)
            case "vacant":   return ("Vacant",  elfGreen)
            case "dining":   return ("Dining 🍽", amber)
            default:         return (status.capitalized, Color.textSecondary)
            }
        }()
        return Text(label)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(color)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(color.opacity(0.3), lineWidth: 1))
    }

    private func orderStatusBadge(_ status: String) -> some View {
        let (label, fg, bg): (String, Color, Color) = {
            switch status.lowercased() {
            case "preparing": return ("Preparing", coralRed,    coralRed.opacity(0.12))
            case "ready":     return ("Ready",     elfGreen,    elfGreen.opacity(0.12))
            case "served":    return ("Served",    Color.textSecondary, Color.appBackground)
            case "completed": return ("Paid ✓",    elfGreen,    elfGreen.opacity(0.10))
            default:          return (status.capitalized, royalBlue, royalBlue.opacity(0.10))
            }
        }()
        return Text(label)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(fg)
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(bg)
            .clipShape(Capsule())
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Actions
    // ─────────────────────────────────────────────────────────────────────────

    private func deleteItem(_ item: OrderItem, from order: Order) {
        Task { _ = try? await NetworkService.shared.deleteOrderItem(itemId: item.id) }
    }

    private func serveItem(_ item: OrderItem, from order: Order) {
        guard item.status != "served", !servingItemIds.contains(item.id) else { return }
        servingItemIds.insert(item.id)
        APHaptic.trigger()
        Task {
            do {
                _ = try await NetworkService.shared.serveOrderItem(itemId: item.id, orderId: order.id, servedBy: loggedInEmployeeName)
                await loadOrders()
            } catch {
                print("TableDetailView: failed to serve item — \(error)")
            }
            await MainActor.run { _ = servingItemIds.remove(item.id) }
        }
    }

    private func recallItem(_ item: OrderItem, from order: Order) {
        guard item.status == "served", !servingItemIds.contains(item.id) else { return }
        servingItemIds.insert(item.id)
        APHaptic.trigger()
        Task {
            do {
                _ = try await NetworkService.shared.recallOrderItem(itemId: item.id, orderId: order.id)
                await loadOrders()
            } catch {
                print("TableDetailView: failed to recall item — \(error)")
            }
            await MainActor.run { _ = servingItemIds.remove(item.id) }
        }
    }

    /// Serve all items in a specific order
    private func serveAllItems(in order: Order) {
        let pending = order.items.filter { $0.status != "served" && $0.status != "cancelled" }
        guard !pending.isEmpty else { return }
        APHaptic.trigger()
        isServingAll = true
        for item in pending { servingItemIds.insert(item.id) }
        Task {
            for item in pending {
                _ = try? await NetworkService.shared.serveOrderItem(itemId: item.id, orderId: order.id, servedBy: loggedInEmployeeName)
            }
            await loadOrders()
            await MainActor.run {
                for item in pending { servingItemIds.remove(item.id) }
                isServingAll = false
            }
        }
    }

    /// Serve all pending items across ALL active orders
    private func serveAllActiveOrders() {
        let pending = activeOrders.flatMap { order in
            order.items
                .filter { $0.status != "served" && $0.status != "cancelled" }
                .map { (item: $0, order: order) }
        }
        guard !pending.isEmpty else { return }
        APHaptic.trigger()
        isServingAll = true
        serveFailedCount = 0
        for p in pending { servingItemIds.insert(p.item.id) }
        Task {
            var failCount = 0
            for p in pending {
                // H-4 FIX: Use try/catch instead of try? to detect individual failures
                do {
                    _ = try await NetworkService.shared.serveOrderItem(
                        itemId: p.item.id, orderId: p.order.id, servedBy: loggedInEmployeeName)
                } catch {
                    failCount += 1
                    print("TableDetailView [serveAll]: item \(p.item.id) failed — \(error)")
                }
            }
            await loadOrders()
            await MainActor.run {
                for p in pending { servingItemIds.remove(p.item.id) }
                isServingAll = false
                // Show alert only if partial failure (not total — total is obvious from UI)
                if failCount > 0 && failCount < pending.count {
                    serveFailedCount = failCount
                    showServePartialFailAlert = true
                }
            }
        }
    }

    private func verifyShiftAndAddFood() {
        Task {
            let timecards = (try? await NetworkService.shared.fetchTimecards(for: loggedInEmployeeId)) ?? []
            let hasActiveShift = timecards.contains { $0.clockOut == nil || $0.clockOut == 0.0 }
            await MainActor.run {
                if hasActiveShift { showingAddItemsSheet = true } else { showShiftGuard = true }
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Post-Payment Still Dining Logic
    // ─────────────────────────────────────────────────────────────────────────

    /// Called from BillingView after checkout success (via notification or onChange)
    func enterPostPaymentMode() {
        postPaymentStatus = .paid
        lastDiningCheckAt = Date()
        scheduleNextDiningCheck()
    }

    private func scheduleNextDiningCheck() {
        stillDiningTimer?.invalidate()
        // First check at 15 min, subsequent checks every 10 min
        let interval: TimeInterval = stillDiningReminderCount == 0 ? 15 * 60 : 10 * 60
        stillDiningTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in
            DispatchQueue.main.async {
                self.showStillDiningConfirm = true
            }
        }
    }

    private func clearTableAfterDining() {
        stillDiningTimer?.invalidate()
        stillDiningTimer = nil
        postPaymentStatus = .left
        APHaptic.trigger()
        
        let tableNumber = table.tableNumber
        Task {
            do {
                _ = try await NetworkService.shared.updateTableStatus(tableNumber: tableNumber, status: "vacant")
            } catch {
                print("Failed to update table status to vacant on server: \(error.localizedDescription)")
            }
        }
        
        // Dismiss the view — table is clear
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            dismiss()
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Data Loading
    // ─────────────────────────────────────────────────────────────────────────

    func loadOrders() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched = try await NetworkService.shared.fetchTableOrders(
                tableNumber: table.tableNumber
            )
            await MainActor.run {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) {
                    orders = fetched
                }
                // If all active orders are now completed → enter post-payment mode
                let active = fetched.filter { $0.status != "cancelled" }
                let allCompleted = !active.isEmpty && active.allSatisfy { $0.status == "completed" }
                if allCompleted && postPaymentStatus == nil {
                    enterPostPaymentMode()
                }
            }
        } catch {
            print("TableDetailView: failed to load orders — \(error)")
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Helpers
    // ─────────────────────────────────────────────────────────────────────────

    private func formatOrderTime(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: isoString) {
            let display = DateFormatter()
            display.timeStyle = .short
            display.dateStyle = .none
            return display.string(from: date)
        }
        return ""
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - EnterpriseOrderItemRow (unchanged logic, refreshed layout)
// ─────────────────────────────────────────────────────────────────────────────

struct EnterpriseOrderItemRow: View {
    let item:        OrderItem
    let royalBlue:   Color
    let elfGreen:    Color
    let coralRed:    Color
    let appLanguage: String
    let onEdit:      () -> Void
    let onNote:      () -> Void
    let onDelete:    () -> Void
    let onServe:     () -> Void
    let onRecall:    () -> Void
    let isServing:   Bool

    @State private var isExpanded  = false
    @State private var offset: CGFloat = 0
    @State private var showActions = false

    private let actionWidth: CGFloat = 240

    var body: some View {
        ZStack(alignment: .trailing) {
            swipeActionTray
                .opacity(showActions ? 1 : 0)
                .animation(.easeOut(duration: 0.2), value: showActions)

            rowContent
                .offset(x: offset)
                .animation(.spring(response: 0.38, dampingFraction: 0.78), value: offset)
                .gesture(
                    DragGesture(minimumDistance: 12)
                        .onChanged { val in
                            if item.status == "served" { return }
                            let dx = val.translation.width
                            if dx < 0 {
                                offset = max(-actionWidth, dx)
                                showActions = true
                            } else if showActions {
                                offset = min(0, -actionWidth + dx)
                            }
                        }
                        .onEnded { val in
                            if item.status == "served" { return }
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                if val.translation.width < -60 {
                                    offset = -actionWidth; showActions = true
                                } else {
                                    offset = 0; showActions = false
                                }
                            }
                        }
                )
        }
        .clipped()
    }

    // MARK: Row Content
    private var rowContent: some View {
        HStack(spacing: 10) {
            // Status indicator dot
            statusDot

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("\(item.quantity)× \(item.name)")
                        .font(.system(size: 14, weight: item.status == "served" ? .regular : .semibold))
                        .foregroundColor(item.status == "served"
                            ? Color.textSecondary
                            : Color.textPrimary)
                        .strikethrough(item.status == "served", color: Color.textSecondary)

                    if item.status == "served" {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(elfGreen)
                        
                        if let servedBy = item.servedBy, !servedBy.isEmpty {
                            Text("(เสิร์ฟโดย: \(servedBy))")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(elfGreen)
                        }
                    }
                }

                if let notes = item.notes, !notes.isEmpty {
                    if isExpanded {
                        Text("📝 \(notes)")
                            .font(.caption2)
                            .foregroundColor(royalBlue)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
            }

            Spacer()

            Text("฿\(Int(item.price * Double(item.quantity)))")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(item.status == "served" ? Color.textSecondary : Color.textPrimary)

            // Serve / Recall button
            if item.status != "served" {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        offset = 0; showActions = false
                    }
                    onServe()
                } label: {
                    Group {
                        if isServing {
                            ProgressView().scaleEffect(0.7).tint(.white)
                        } else {
                            Text("เสิร์ฟ")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    .frame(width: 48, height: 28)
                    .background(elfGreen)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .disabled(isServing)
            } else {
                Button {
                    onRecall()
                } label: {
                    Group {
                        if isServing {
                            ProgressView().scaleEffect(0.7).tint(.gray)
                        } else {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.gray)
                        }
                    }
                    .frame(width: 28, height: 28)
                    .background(Color(.systemGroupedBackground))
                    .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(isServing)
            }

            // Expand toggle (for notes)
            if item.notes != nil && !item.notes!.isEmpty {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color.white)
        .contentShape(Rectangle())
    }

    // MARK: Status Dot
    private var statusDot: some View {
        let color: Color = {
            switch item.status {
            case "served":    return elfGreen
            case "ready":     return Color.appGreen
            case "cancelled": return Color.textSecondary
            default:          return coralRed   // cooking / preparing
            }
        }()
        return ZStack {
            Circle().fill(color.opacity(0.15)).frame(width: 10, height: 10)
            Circle().fill(color).frame(width: 6, height: 6)
        }
    }

    // MARK: Swipe Action Tray
    private var swipeActionTray: some View {
        HStack(spacing: 0) {
            // Edit
            actionButton(icon: "pencil", label: "แก้ไข", color: royalBlue) {
                withAnimation { offset = 0; showActions = false }
                onEdit()
            }
            // Note
            actionButton(icon: "note.text", label: "โน้ต", color: Color.textSecondary) {
                withAnimation { offset = 0; showActions = false }
                onNote()
            }
            // Delete
            actionButton(icon: "trash.fill", label: "ลบ", color: coralRed) {
                withAnimation { offset = 0; showActions = false }
                onDelete()
            }
        }
        .frame(width: actionWidth)
    }

    private func actionButton(icon: String, label: String, color: Color,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 16, weight: .semibold))
                Text(label).font(.system(size: 10, weight: .bold))
            }
            .foregroundColor(.white)
            .frame(width: actionWidth / 3)
            .frame(maxHeight: .infinity)
            .background(color)
        }
        .buttonStyle(.plain)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - EditOrderItemSheet
// Lets staff edit quantity + notes for an existing order item.
// ─────────────────────────────────────────────────────────────────────────────

struct EditOrderItemSheet: View {
    let item:        OrderItem
    let order:       Order
    let appLanguage: String
    let royalBlue:   Color
    let elfGreen:    Color
    let coralRed:    Color

    @Environment(\.dismiss) private var dismiss
    @State private var quantity: Int    = 1
    @State private var notes:    String = ""
    @State private var isSaving = false
    @State private var errorMsg: String? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                VStack(spacing: 18) {

                    // Item name header
                    VStack(spacing: 4) {
                        Text(item.name)
                            .font(.title3).fontWeight(.black).foregroundColor(.textPrimary)
                            .multilineTextAlignment(.center)
                        Text("฿\(String(format: "%.2f", item.price)) / รายการ")
                            .font(.subheadline).foregroundColor(.textSecondary)
                    }
                    .padding(.top, 4)

                    // Quantity stepper
                    VStack(alignment: .leading, spacing: 8) {
                        Text("จำนวน")
                            .font(.subheadline.weight(.semibold)).foregroundColor(.textSecondary)
                        HStack(spacing: 0) {
                            Button {
                                if quantity > 1 { quantity -= 1 }
                            } label: {
                                Image(systemName: "minus")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(quantity > 1 ? royalBlue : .textSecondary)
                                    .frame(width: 44, height: 44)
                                    .background(Color.appSurfaceHigh)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            Spacer()
                            Text("\(quantity)")
                                .font(.system(size: 28, weight: .black, design: .rounded))
                                .foregroundColor(.textPrimary)
                            Spacer()
                            Button {
                                quantity += 1
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(royalBlue)
                                    .frame(width: 44, height: 44)
                                    .background(royalBlue.opacity(0.10))
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                        }
                        .padding(12)
                        .background(Color.appSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.appBorderSubtle, lineWidth: 1))
                    }
                    .apCard()

                    // Notes field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("หมายเหตุ / คำขอพิเศษ")
                            .font(.subheadline.weight(.semibold)).foregroundColor(.textSecondary)
                        TextField("เช่น ไม่เผ็ด, ไม่ใส่ผัก...", text: $notes, axis: .vertical)
                            .lineLimit(3, reservesSpace: true)
                            .padding(10)
                            .background(Color.appSurfaceHigh)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .foregroundColor(.textPrimary)
                    }
                    .apCard()

                    if let err = errorMsg {
                        Label(err, systemImage: "exclamationmark.circle")
                            .font(.caption.weight(.semibold)).foregroundColor(.appRose)
                    }

                    Spacer()

                    // Save button
                    Button {
                        saveChanges()
                    } label: {
                        ZStack {
                            if isSaving {
                                ProgressView().tint(.white)
                            } else {
                                Label("บันทึก", systemImage: "checkmark.circle.fill")
                                    .font(.system(size: 16, weight: .bold))
                            }
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(elfGreen)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(isSaving)
                }
                .padding()
            }
            .navigationTitle("แก้ไขรายการ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ยกเลิก") { dismiss() }.foregroundColor(royalBlue)
                }
            }
        }
        .onAppear {
            quantity = item.quantity
            notes    = item.notes ?? ""
        }
    }

    private func saveChanges() {
        isSaving  = true
        errorMsg  = nil
        Task {
            do {
                _ = try await NetworkService.shared.patchOrderItem(
                    itemId:   item.id,
                    quantity: quantity,
                    notes:    notes.isEmpty ? nil : notes
                )
                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMsg = "บันทึกไม่สำเร็จ: \(error.localizedDescription)"
                }
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - AddItemsToOrderSheet
// Lets staff add new food items to the current table session.
// ─────────────────────────────────────────────────────────────────────────────

struct AddItemsToOrderSheet: View {
    let table:            RestaurantTable
    @Binding var cartItems: [MenuItem: Int]

    @Environment(\.dismiss) private var dismiss
    @AppStorage("app_language") private var appLanguage = "en"

    @State private var menuItems:   [MenuItem] = []
    @State private var isLoading    = false
    @State private var isSubmitting = false
    @State private var searchText   = ""
    @State private var errorMsg:    String? = nil

    private let royalBlue = Color.appAccent
    private let elfGreen  = Color.appTeal

    private var filteredItems: [MenuItem] {
        if searchText.isEmpty { return menuItems }
        return menuItems.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            ($0.category.localizedCaseInsensitiveContains(searchText))
        }
    }

    private var cartTotal: Double {
        cartItems.reduce(0) { $0 + $1.key.price * Double($1.value) }
    }
    private var cartCount: Int { cartItems.values.reduce(0, +) }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Search bar
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.textSecondary).font(.system(size: 14))
                        TextField("ค้นหาเมนู...", text: $searchText)
                            .foregroundColor(.textPrimary)
                    }
                    .padding(10)
                    .background(Color.appSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal).padding(.top, 8).padding(.bottom, 4)

                    if isLoading {
                        ProgressView().tint(royalBlue).frame(maxHeight: .infinity)
                    } else {
                        List {
                            ForEach(filteredItems) { item in
                                menuItemRow(item)
                                    .listRowBackground(Color.appSurface)
                                    .listRowSeparatorTint(Color.appBorderSubtle)
                            }
                        }
                        .listStyle(.plain)
                    }

                    // Cart bottom bar
                    if cartCount > 0 {
                        VStack(spacing: 0) {
                            Divider()
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(cartCount) รายการ")
                                        .font(.caption.weight(.bold)).foregroundColor(.textSecondary)
                                    Text("฿\(String(format: "%.2f", cartTotal))")
                                        .font(.system(size: 18, weight: .black)).foregroundColor(elfGreen)
                                }
                                Spacer()
                                Button {
                                    submitOrder()
                                } label: {
                                    ZStack {
                                        if isSubmitting {
                                            ProgressView().tint(.white).scaleEffect(0.85)
                                        } else {
                                            Label("สั่งอาหาร", systemImage: "paperplane.fill")
                                                .font(.system(size: 14, weight: .bold))
                                        }
                                    }
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 20).padding(.vertical, 10)
                                    .background(elfGreen)
                                    .clipShape(Capsule())
                                }
                                .disabled(isSubmitting)
                            }
                            .padding(.horizontal).padding(.vertical, 10)
                            .background(Color.appSurface)
                        }
                    }

                    if let err = errorMsg {
                        Label(err, systemImage: "exclamationmark.circle")
                            .font(.caption.weight(.semibold)).foregroundColor(.appRose)
                            .padding(.horizontal).padding(.bottom, 8)
                    }
                }
            }
            .navigationTitle("เพิ่มรายการ — โต๊ะ \(table.tableNumber)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ยกเลิก") { dismiss() }.foregroundColor(royalBlue)
                }
            }
            .onAppear { Task { await loadMenu() } }
        }
    }

    private func menuItemRow(_ item: MenuItem) -> some View {
        HStack(spacing: 12) {
            // Emoji / category icon
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(royalBlue.opacity(0.08)).frame(width: 38, height: 38)
                Text(item.emoji ?? "🍽").font(.system(size: 20))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.subheadline.weight(.semibold)).foregroundColor(.textPrimary)
                Text("฿\(String(format: "%.2f", item.price))").font(.caption).foregroundColor(.textSecondary)
            }

            Spacer()

            // Quantity stepper
            HStack(spacing: 6) {
                let qty = cartItems[item] ?? 0
                if qty > 0 {
                    Button {
                        APHaptic.trigger()
                        if qty == 1 { cartItems.removeValue(forKey: item) }
                        else { cartItems[item] = qty - 1 }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 22)).foregroundColor(.appRose)
                    }
                    Text("\(qty)")
                        .font(.system(size: 16, weight: .black)).foregroundColor(.textPrimary)
                        .frame(minWidth: 20)
                }
                Button {
                    APHaptic.trigger()
                    cartItems[item] = (cartItems[item] ?? 0) + 1
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22)).foregroundColor(royalBlue)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func loadMenu() async {
        isLoading = true
        do {
            menuItems = try await NetworkService.shared.fetchMenu()
        } catch {
            print("AddItemsToOrderSheet: failed to load menu — \(error)")
        }
        isLoading = false
    }

    private func submitOrder() {
        guard cartCount > 0 else { return }
        isSubmitting = true
        errorMsg     = nil

        let items: [[String: Any]] = cartItems.map { (menuItem, qty) in
            ["id": UUID().uuidString, "name": menuItem.name,
             "itemId": menuItem.id, "quantity": qty, "price": menuItem.price]
        }
        let total = cartTotal
        let orderId     = UUID().uuidString
        let orderNumber = "S-\(Int.random(in: 1000...9999))"

        Task {
            do {
                _ = try await NetworkService.shared.uploadOrder(
                    orderId:     orderId,
                    orderNumber: orderNumber,
                    tableNumber: table.tableNumber,
                    total:       total,
                    items:       items,
                    sessionToken: table.sessionToken,
                    guestCount:  table.guestCount
                )
                await MainActor.run {
                    cartItems.removeAll()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    errorMsg = "สั่งอาหารไม่สำเร็จ: \(error.localizedDescription)"
                }
            }
        }
    }
}
