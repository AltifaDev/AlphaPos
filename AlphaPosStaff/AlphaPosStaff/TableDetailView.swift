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
    @AppStorage("logged_in_employee_role") private var loggedInEmployeeRole = ""
    @State private var showAccessDeniedAlert = false

    // ── Order state ───────────────────────────────────────────────────────────
    @State private var networkService = NetworkService.shared
    @State private var orders: [Order] = []
    @State private var isLoading = false
    @State private var showingAddItemsSheet = false
    @State private var showingBilling = false
    @State private var emptyItemsPolling = false   // true while periodic refresh is running
    @State private var cartItems: [MenuItem: Int] = [:]
    @State private var showShiftGuard = false
    @State private var servingItemIds = Set<String>()
    @State private var showGuestBillPreview = false

    // ── Item action states ────────────────────────────────────────────────────
    @State private var editTarget:   EditTarget? = nil
    @State private var deleteTarget: EditTarget? = nil

    // ── Post-payment dining state ─────────────────────────────────────────────
    @State private var postPaymentStatus: PostPaymentDiningStatus? = nil
    @State private var showStillDiningConfirm = false
    @State private var showClearTableConfirm  = false
    @State private var isClearingTable = false
    @State private var clearTableError: String? = nil
    @State private var stillDiningTimer: Timer? = nil
    @State private var stillDiningReminderCount = 0
    @State private var lastDiningCheckAt: Date? = nil

    // ── "Serve all" progress ──────────────────────────────────────────────────
    @State private var isServingAll = false
    // Drives the "paper-plane sends the order away" animation on the serve-all
    // button: it slides right + fades, then resets once serving completes.
    @State private var serveAllLaunched = false
    @State private var isPreparingCheckout = false
    @State private var didAppearAnimate = false

    @State private var serveFailedCount: Int = 0
    @State private var showServePartialFailAlert = false

    // ── Approve web order state ─────────────────────────────────────────────
    @State private var approvingOrderIds = Set<String>()   // loading per-order
    @State private var showApproveErrorAlert = false
    @State private var approveErrorMessage = ""

    // ── Order Timeline ──────────────────────────────────────────────────────
    @State private var selectedOrderForTimeline: Order? = nil

    // ── Split Bill ────────────────────────────────────────────────────────────
    @State private var showSplitBill = false
    @State private var loadOrdersError: String? = nil

    @Environment(\.dismiss) private var dismiss

    // Design tokens
    private let royalBlue = Color.appAccent
    // Liquid-Glass blue theme (iOS 26): serve / positive actions now use blue
    // instead of the legacy green so the whole screen shares one accent family.
    private let elfGreen  = Color.appAccent
    private let coralRed  = Color.appRose
    private let amber     = Color.appAmber
    private let serveBlue = Color.appAccent

    // MARK: - Computed

    private var currentTable: RestaurantTable {
        networkService.tables.first(where: { $0.tableNumber == table.tableNumber }) ?? table
    }

    private func belongsToCurrentSession(_ order: Order) -> Bool {
        if let sessionId = currentTable.activeSessionId, !sessionId.isEmpty,
           let orderSessionId = order.tableSessionId, !orderSessionId.isEmpty {
            return orderSessionId == sessionId
        }
        if let token = currentTable.sessionToken, !token.isEmpty,
           let orderToken = order.sessionToken, !orderToken.isEmpty {
            return orderToken == token
        }
        guard let startedAt = currentTable.sessionStartedAt,
              let sessionDate = ElapsedTimeBadge.parseDate(startedAt),
              let orderDate = ElapsedTimeBadge.parseDate(order.createdAt) else { return false }
        return orderDate >= sessionDate
    }

    /// Orders that are still active (not completed / not cancelled)
    private var activeOrders: [Order] {
        orders.filter { !$0.isPaid && $0.status != "cancelled" }
    }

    private var paidOrders: [Order] {
        orders.filter { $0.isPaid }
    }

    /// Orders from the web ordering channel
    private var webOrders: [Order] {
        activeOrders.filter { $0.orderSource == "web" }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// Orders created by the POS or staff app.
    private var staffOrders: [Order] {
        activeOrders.filter { $0.orderSource != "web" }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private var hasAnyActiveOrders: Bool { !activeOrders.isEmpty }

    private var hasPaidOrders: Bool { !paidOrders.isEmpty }

    private var isPaidAwaitingClear: Bool {
        hasPaidOrders && !hasAnyActiveOrders && postPaymentStatus != .left
    }

    private var shouldShowEmptyState: Bool {
        !hasAnyActiveOrders && postPaymentStatus == nil
    }

    private var isAuthorizedToClearTable: Bool {
        let role = loggedInEmployeeRole.lowercased()
        return role.contains("manager") || role.contains("owner") || role.contains("admin")
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
            belongsToCurrentSession($0) &&
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
        activeOrders.filter { !$0.isAwaitingStaffApproval }.flatMap { $0.items }
            .filter { $0.status != "served" && $0.status != "cancelled" }
            .count
    }

    private var lastVisibleItemId: String? {
        (staffOrders.last ?? webOrders.last)?.items.last?.id
    }

    private var isPaidButDining: Bool {
        postPaymentStatus == .stillDining
    }

    /// True while any customer order awaits explicit staff approval.
    private var hasPendingWebItems: Bool {
        webOrders.contains { $0.isAwaitingStaffApproval }
    }

    /// Stable key array สำหรับ track item-level changes ใน onChange
    /// แยกออกจาก inline expression เพื่อหลีกเลี่ยง compiler type-check timeout
    private var tableOrderItemKeys: [String] {
        let tableOrders = networkService.orders.filter {
            $0.tableNumber == table.tableNumber && belongsToCurrentSession($0)
        }
        return tableOrders.flatMap { $0.items }.map { $0.id + $0.status }
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

                // Error banner เมื่อ loadOrders ล้มเหลว (แยกจาก empty state)
                if let errMsg = loadOrdersError {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.appAmber)
                        Text(errMsg)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.textPrimary)
                            .lineLimit(2)
                        Spacer()
                        Button {
                            loadOrdersError = nil
                            Task { await loadOrders() }
                        } label: {
                            Text("retry".localized(for: appLanguage))
                                .font(.caption.bold())
                                .foregroundColor(.appAccent)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.appAmber.opacity(0.12))
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Post-payment dining banner
                if let status = postPaymentStatus, status != .left {
                    postPaymentBanner(status)
                }

                // ── Approval banner for pending web orders ──────────────────
                if hasPendingWebItems {
                    approvalBanner
                        .transition(.move(edge: .top).combined(with: .opacity))
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
        .fullScreenCover(isPresented: $showingBilling) {
            BillingView(table: currentTable, orders: activeOrders)
        }
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
        .sheet(item: $selectedOrderForTimeline) { order in
            OrderTimelineView(order: order)
        }
        .sheet(isPresented: $showSplitBill) {
            if let firstOrder = activeOrders.first {
                SplitBillView(
                    orderId: firstOrder.id,
                    orderItems: activeOrders.flatMap { $0.items },
                    totalAmount: activeOrders.reduce(0) { $0 + $1.total },
                    tableNumber: table.tableNumber
                )
            }
        }
        .sheet(isPresented: $showGuestBillPreview) {
            GuestBillPreviewSheet(table: currentTable, orders: activeOrders)
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
                if isAuthorizedToClearTable {
                    clearTableAfterDining()
                } else {
                    showAccessDeniedAlert = true
                }
            }
        } message: {
            let mins = stillDiningReminderCount == 0 ? 15 : 10
            Text("ชำระเงินไปแล้ว \(mins) นาที โต๊ะ \(currentTable.tableNumber) ยังไม่ถูกเคลียร์ ลูกค้ายังนั่งรับประทานอยู่หรือเปล่า?")
        }
        .alert("สิทธิ์ไม่เพียงพอ", isPresented: $showAccessDeniedAlert) {
            Button("ตกลง", role: .cancel) {}
        } message: {
            Text("เฉพาะผู้จัดการหรือเจ้าของร้านเท่านั้นที่มีสิทธิ์เคลียร์โต๊ะและเซสชันการกิน")
        }
        // ── Clear table confirm ───────────────────────────────────────────────
        .alert("เคลียร์โต๊ะ \(currentTable.tableNumber)?", isPresented: $showClearTableConfirm) {
            Button("ยกเลิก", role: .cancel) {}
            Button("ยืนยันเคลียร์โต๊ะ", role: .destructive) {
                clearTableAfterDining()
            }
        } message: {
            Text("โต๊ะจะถูก reset เป็น Vacant และ session จะถูกปิด")
        }
        .alert("เคลียร์โต๊ะไม่สำเร็จ", isPresented: Binding(
            get: { clearTableError != nil },
            set: { if !$0 { clearTableError = nil } }
        )) {
            Button("ตกลง", role: .cancel) {}
        } message: {
            Text(clearTableError ?? "")
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
        // Approve error alert
        .alert("อนุมัติไม่สำเร็จ", isPresented: $showApproveErrorAlert) {
            Button("ตกลง", role: .cancel) { approveErrorMessage = "" }
        } message: {
            Text(approveErrorMessage.isEmpty
                 ? "เกิดข้อผิดพลาด กรุณาตรวจสอบการเชื่อมต่อแล้วลองใหม่"
                 : approveErrorMessage)
        }
        .onAppear {
            Task { await loadOrders() }
            // Trigger the one-time entry animation for the order list.
            if !didAppearAnimate {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { didAppearAnimate = true }
            }
            // Self-healing: if any active order still has empty items after the initial
            // load (race between orders POST and order_items POST from the iPad app),
            // retry loading once after 2 seconds.  This covers the case where the user
            // opens TableDetailView during the brief window before order_items arrive.
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                let hasEmptyItemOrders = orders.contains { order in
                    order.status != "completed" && order.status != "cancelled" && order.items.isEmpty
                }
                if hasEmptyItemOrders {
                    await loadOrders()
                }
            }
            // Persistent periodic refresh: if orders with empty items are still present
            // after the initial self-healing pass, poll every 30s until items arrive or
            // the view disappears. Handles the case where timeout/network errors prevented
            // items from loading (e.g. 17-minute stale order with no items).
            guard !emptyItemsPolling else { return }
            emptyItemsPolling = true
            Task {
                defer { emptyItemsPolling = false }
                // Phase 1: poll ถี่ (5s × 12 = 1 นาที) — รองรับกรณี iPad "Sync Failed"
                // ที่ retry แล้วสำเร็จภายใน 1 นาที
                for _ in 1...12 {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    let stillMissing = orders.contains { o in
                        o.status != "completed" && o.status != "cancelled" && o.items.isEmpty
                    }
                    guard stillMissing else { break }
                    await loadOrders()
                }
                // Phase 2: poll ห่าง (15s × 8 = 2 นาที) — หลังจาก 1 นาทีแรก
                for _ in 1...8 {
                    try? await Task.sleep(nanoseconds: 15_000_000_000)
                    let stillMissing = orders.contains { o in
                        o.status != "completed" && o.status != "cancelled" && o.items.isEmpty
                    }
                    guard stillMissing else { break }
                    await loadOrders()
                }
            }
        }
        // C-7 FIX: Filter onChange to only fire when orders for THIS table change.
        // Unfiltered onChange(orders) fires for every table — causes unnecessary
        // network round-trips when other tables' orders update.
        .onChange(of: networkService.orders.filter { $0.tableNumber == table.tableNumber }) { _, newOrders in
            Task { await loadOrders() }
            // Self-healing: if the newly-received orders contain any active order with
            // empty items (race window), schedule a reload 1.5 s later.
            let needsRetry = newOrders.contains { o in
                o.status != "completed" && o.status != "cancelled" && o.items.isEmpty
            }
            if needsRetry {
                Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    await loadOrders()
                }
            }
        }
        // BUG FIX: ติดตาม item-level changes — ใช้ computed property เพื่อหลีกเลี่ยง
        // compiler type-check timeout (expression ซับซ้อนเกินไปสำหรับ inline closure)
        .onChange(of: tableOrderItemKeys) { _, _ in
            Task { await loadOrders() }
        }
        // H-8 FIX: Invalidate stillDiningTimer when view disappears to prevent
        // timer firing an alert after the view has been dismissed.
        .onDisappear {
            stillDiningTimer?.invalidate()
            stillDiningTimer = nil
        }
        // When new pending items arrive (food added / new web order), bring the
        // serve button back and shrink Add Food to its compact size again.
        .onChange(of: pendingServeCount) { oldValue, newValue in
            if newValue > oldValue && serveAllLaunched && !isServingAll {
                // New items arrived → serve button slides back, Add Food shrinks.
                APHaptic.trigger()
                withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
                    serveAllLaunched = false
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .checkoutCompleted)) { note in
            // BillingView posted this after successful payment
            guard let tableNumber = note.object as? String,
                  tableNumber == table.tableNumber else { return }
            Task {
                await loadOrders()
                await MainActor.run {
                    serveAllLaunched = false   // clear any stuck expanded state
                    enterPostPaymentMode()
                }
            }
        }
        .onChange(of: networkService.tables) { _, newTables in
            // Auto-dismiss when table becomes vacant after payment
            let targetNumber: String = table.tableNumber
            let myTable: RestaurantTable? = newTables.first(where: { $0.tableNumber == targetNumber })
            let isNowVacant: Bool = myTable?.status == "vacant"
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
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill((isPaidAwaitingClear ? elfGreen : isPaidButDining ? amber : royalBlue).opacity(0.10))
                    .frame(width: 34, height: 34)
                Image(systemName: isPaidAwaitingClear ? "checkmark.seal.fill" : isPaidButDining ? "fork.knife.circle.fill" : "fork.knife")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(isPaidAwaitingClear ? elfGreen : isPaidButDining ? amber : royalBlue)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(isPaidAwaitingClear
                     ? "ชำระเงินแล้ว · รอเคลียร์โต๊ะ"
                     : isPaidButDining
                     ? "ชำระเงินแล้ว · ยังนั่งอยู่"
                     : "session_orders".localized(for: appLanguage))
                    .font(.system(size: 10))
                    .foregroundColor(isPaidAwaitingClear ? elfGreen : isPaidButDining ? amber : Color.textSecondary)
                Text(String(format: "table_guests_count_format".localized(for: appLanguage),
                            currentTable.tableNumber, currentTable.guestCount))
                    .font(.system(size: 14, weight: .bold)).foregroundColor(Color.textPrimary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if currentTable.status == "occupied" {
                    ElapsedTimeBadge(startedAt: currentTable.sessionStartedAt)
                }
                statusBadge(isPaidAwaitingClear ? "paid" : isPaidButDining ? "dining" : currentTable.status)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.appSurface)
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
                if isAuthorizedToClearTable {
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
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10))
                        Text("เคลียร์โต๊ะ")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundColor(.textSecondary.opacity(0.6))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.appSurfaceHigh)
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
        ScrollViewReader { proxy in
            ScrollView {
            LazyVStack(spacing: 8) {

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
                    let completedOrders = paidOrders
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
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .animation(.spring(response: 0.4, dampingFraction: 0.78), value: activeOrders.count)
            // Subtle entry animation when the screen opens: content rises & fades in.
            .opacity(didAppearAnimate ? 1 : 0)
            .offset(y: didAppearAnimate ? 0 : 14)
            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: didAppearAnimate)
            }
            .onChange(of: lastVisibleItemId) { oldValue, newValue in
                guard oldValue != nil, let newValue else { return }
                withAnimation(.easeOut(duration: 0.3)) {
                    proxy.scrollTo(newValue, anchor: .bottom)
                }
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Approval Banner (Web Orders)
    // ─────────────────────────────────────────────────────────────────────────

    private var approvalBanner: some View {
        Button {
            approveAllPendingWebOrders()
        } label: {
            let isApprovingAny = webOrders.contains { approvingOrderIds.contains($0.id) }
            HStack(spacing: 10) {
                if isApprovingAny {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.9)
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .symbolEffect(.bounce, options: .repeating)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("มีออเดอร์ใหม่จากลูกค้า")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                    Text("แตะเพื่อส่งออเดอร์เข้าครัว")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.85))
                }

                Spacer()

                if isApprovingAny {
                    Text("approve".localized(for: appLanguage))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Capsule())
                } else {
                    Text("approve".localized(for: appLanguage))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.22))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                LinearGradient(
                    colors: [Color.appAmber, Color.appAmber.opacity(0.8)],
                    startPoint: .leading, endPoint: .trailing
                )
            )
        }
        .buttonStyle(.plain)
    }

    /// Approve all web orders that have items still in "pending" status (banner tap)
    private func approveAllPendingWebOrders() {
        let ordersToApprove = webOrders.filter(\.isAwaitingStaffApproval)
        guard !ordersToApprove.isEmpty else { return }
        // ถ้ากำลัง approve อยู่แล้วไม่ต้องทำซ้ำ
        guard !ordersToApprove.allSatisfy({ approvingOrderIds.contains($0.id) }) else { return }
        APHaptic.trigger()
        for order in ordersToApprove {
            approvingOrderIds.insert(order.id)
        }
        Task {
            var failCount = 0
            for order in ordersToApprove {
                do {
                    _ = try await NetworkService.shared.approveOrder(order: order)
                } catch {
                    failCount += 1
                    print("TableDetailView [approveAll]: order \(order.id) failed — \(error)")
                }
                approvingOrderIds.remove(order.id)
            }
            await loadOrders()
            if failCount > 0 {
                approveErrorMessage = "อนุมัติสำเร็จ \(ordersToApprove.count - failCount)/\(ordersToApprove.count) ออเดอร์ กรุณาลองใหม่อีกครั้ง"
                showApproveErrorAlert = true
            }
        }
    }

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
            // Card header — clean 2-line layout so the order number, time, status
            // and action never crowd or wrap awkwardly.
            let allServed = !order.items.isEmpty &&
                order.items.allSatisfy { $0.status == "served" || $0.status == "cancelled" }
            let needsApproval = order.isAwaitingStaffApproval
            VStack(alignment: .leading, spacing: 4) {
                // Row 1: source icon + order number (one line) + time on the right
                HStack(spacing: 7) {
                    Image(systemName: source == .web ? "network" : "person.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(source == .web ? royalBlue : elfGreen)

                    Text(order.orderNumber)
                        .font(.system(size: 12, weight: .black, design: .monospaced))
                        .foregroundColor(source == .web ? royalBlue : elfGreen)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Spacer(minLength: 6)

                    Image(systemName: "clock")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    Text(formatOrderTime(order.createdAt))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }

                // Row 2: status badge + action button, aligned on one line
                HStack(spacing: 8) {
                    orderStatusBadge(allServed ? "served" : order.status)
                        .onTapGesture { selectedOrderForTimeline = order }

                    Spacer(minLength: 0)

                    if needsApproval {
                        let isThisApproving = approvingOrderIds.contains(order.id)
                        Button {
                            approveOrder(order)
                        } label: {
                            HStack(spacing: 4) {
                                if isThisApproving {
                                    ProgressView()
                                        .tint(.white).scaleEffect(0.7)
                                        .frame(width: 12, height: 12)
                                } else {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 10, weight: .bold))
                                }
                                Text(isThisApproving ? "..." : "approve".localized(for: appLanguage))
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .foregroundColor(isThisApproving ? .white.opacity(0.6) : .white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(amber)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(isThisApproving)
                    } else if !allServed && !isServingAll {
                        Button {
                            serveAllItems(in: order)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "paperplane.fill")
                                    .font(.system(size: 10, weight: .bold))
                                Text("ยืนยันเสิร์ฟทั้งหมด")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(serveBlue)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
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
                    .id(item.id)
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
        .apLiquidGlass(
            tint: (source == .web ? royalBlue : elfGreen).opacity(0.06),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            (source == .web ? royalBlue : elfGreen).opacity(0.25),
                            Color.white.opacity(0.05)
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 3)
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
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .opacity(0.6)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Bottom Bar
    // ─────────────────────────────────────────────────────────────────────────
    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider().background(Color.appDivider)

            VStack(spacing: 10) {
                // Pending (unserved) items only — once everything is served, fall
                // through to the checkout row. Do NOT gate on `serveAllLaunched`:
                // keeping that flag true after Serve All previously hid Payment.
                if hasAnyActiveOrders && !isAllServed {
                    // ── Pending items → Serve-All (paper-plane) + Add Food, side by side.
                    // When the serve button flies away, it collapses to zero width and
                    // Add Food smoothly expands to (almost) full width to take its place.
                    GeometryReader { geometry in
                        let spacing: CGFloat = serveAllLaunched ? 0 : 10
                        let available = geometry.size.width - spacing
                        HStack(spacing: spacing) {
                        Button {
                            cartItems.removeAll()
                            verifyShiftAndAddFood()
                        } label: {
                            addFoodCompactLabel(expanded: serveAllLaunched)
                        }
                        .buttonStyle(.plain)
                        .frame(width: serveAllLaunched ? geometry.size.width : available * 0.3)

                        Button {
                            launchServeAll()
                        } label: {
                            serveAllLabel
                                .offset(x: serveAllLaunched ? 500 : 0)
                                .opacity(serveAllLaunched ? 0 : 1)
                        }
                        .buttonStyle(.plain)
                        .disabled(isServingAll)
                        .frame(width: serveAllLaunched ? 0 : available * 0.7)
                        .clipped()
                        }
                    }
                    .frame(height: 56)
                    .animation(.spring(response: 0.5, dampingFraction: 0.82), value: serveAllLaunched)

                } else if isPreparingCheckout {
                    HStack(spacing: 12) {
                        ProgressView().tint(coralRed)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("กำลังเตรียมชำระเงิน...")
                                .font(.system(size: 15, weight: .bold))
                            Text("กำลังยืนยันรายการกับเซิร์ฟเวอร์")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.textSecondary)
                        }
                        Spacer()
                    }
                    .foregroundColor(coralRed)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .apLiquidGlass(tint: coralRed.opacity(0.12),
                                   in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))

                } else if isPaidAwaitingClear {
                    Button {
                        guard !isClearingTable else { return }
                        if isAuthorizedToClearTable {
                            showClearTableConfirm = true
                        } else {
                            showAccessDeniedAlert = true
                        }
                    } label: {
                        primaryCTALabel(
                            icon: "checkmark.seal.fill",
                            title: isClearingTable ? "กำลังเคลียร์โต๊ะ..." : "ชำระเงินแล้ว",
                            subtitle: "รอเคลียร์โต๊ะ ไม่สามารถชำระซ้ำได้",
                            showSpinner: isClearingTable,
                            showChevron: true
                        )
                        .apLiquidGlass(tint: elfGreen,
                                       in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isClearingTable)

                } else if hasAnyActiveOrders {
                    // ── All served → primary "Checkout", secondary "Add Food" + "Split" ──
                    Button {
                        APHaptic.trigger()
                        showingBilling = true
                    } label: {
                        primaryCTALabel(
                            icon: "creditcard.fill",
                            title: "bill_payment".localized(for: appLanguage),
                            subtitle: "bill_payment_hint".localized(for: appLanguage),
                            showChevron: true
                        )
                        .apLiquidGlass(tint: coralRed,
                                       in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))

                    secondaryActionRow(showSplit: true)

                } else {
                    // ── No active orders → just Add Food (full width) ──
                    Button {
                        cartItems.removeAll()
                        verifyShiftAndAddFood()
                    } label: {
                        primaryCTALabel(
                            icon: "plus.circle.fill",
                            title: "add_item".localized(for: appLanguage),
                            subtitle: nil,
                            showChevron: true
                        )
                        .apLiquidGlass(tint: royalBlue,
                                       in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.appSurface)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isAllServed)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: hasAnyActiveOrders)
    }

    // MARK: - Bottom Bar Helpers

    /// Prominent full-width primary CTA label (icon chip + title + optional subtitle).
    @ViewBuilder
    private func primaryCTALabel(
        icon: String?,
        title: String,
        subtitle: String?,
        showSpinner: Bool = false,
        showChevron: Bool = false
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.22))
                    .frame(width: 38, height: 38)
                if showSpinner {
                    ProgressView().scaleEffect(0.8).tint(.white)
                } else if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .bold))
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                }
            }
            Spacer()
            if showChevron {
                Image(systemName: "arrow.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
            }
        }
        .foregroundColor(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Secondary action row: Add Food + Print Bill (+ optional Split Bill).
    @ViewBuilder
    private func secondaryActionRow(showSplit: Bool) -> some View {
        HStack(spacing: 8) {
            Button {
                cartItems.removeAll()
                verifyShiftAndAddFood()
            } label: {
                secondaryTileLabel(icon: "plus", title: "add_item".localized(for: appLanguage), tint: royalBlue)
            }
            .buttonStyle(.plain)

            Button {
                APHaptic.trigger()
                showGuestBillPreview = true
            } label: {
                secondaryTileLabel(icon: "printer.fill", title: "print_guest_bill".localized(for: appLanguage), tint: royalBlue)
            }
            .buttonStyle(.plain)

            if showSplit {
                Button {
                    showSplitBill = true
                } label: {
                    secondaryTileLabel(icon: "rectangle.split.3x1.fill", title: "split_bill".localized(for: appLanguage), tint: royalBlue)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func secondaryTileLabel(icon: String, title: String, tint: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
            Text(title)
                .font(.system(size: 14, weight: .bold))
        }
        .foregroundColor(tint)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .apLiquidGlass(tint: tint.opacity(0.12),
                       in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }


    // ── Serve-all button label (paper-plane "send order" style) ─────────────
    @ViewBuilder
    private var serveAllLabel: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.22))
                    .frame(width: 34, height: 34)
                if isServingAll {
                    ProgressView().scaleEffect(0.75).tint(.white)
                } else {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 15, weight: .bold))
                        .rotationEffect(.degrees(serveAllLaunched ? -25 : 0))
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(isServingAll ? "กำลังบันทึก..." : "ยืนยันเสิร์ฟทั้งหมด (\(pendingServeCount))")
                    .font(.system(size: 14, weight: .bold))
                Text("แตะเมื่อนำอาหารให้ลูกค้าแล้ว")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
            }
            Spacer(minLength: 0)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .apLiquidGlass(tint: serveBlue,
                       in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    // ── Compact "Add Food" order-entry button (modern glass, with icon) ─────
    // `expanded` = true renders a prominent full-width primary style (used once
    // the serve button has flown away); false renders the compact side tile.
    @ViewBuilder
    private func addFoodCompactLabel(expanded: Bool) -> some View {
        Group {
            if expanded {
                // Prominent full-width primary style (fills the serve button's spot).
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.22))
                            .frame(width: 34, height: 34)
                        Image(systemName: "cart.badge.plus")
                            .font(.system(size: 16, weight: .bold))
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("add_item".localized(for: appLanguage))
                            .font(.system(size: 15, weight: .bold))
                        Text("แตะเพื่อเพิ่มรายการอาหาร")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.85))
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .apLiquidGlass(tint: royalBlue,
                               in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            } else {
                // Compact side tile beside the serve button.
                VStack(spacing: 3) {
                    Image(systemName: "cart.badge.plus")
                        .font(.system(size: 17, weight: .bold))
                    Text("add_item".localized(for: appLanguage))
                        .font(.system(size: 11, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .foregroundColor(royalBlue)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .apLiquidGlass(tint: royalBlue.opacity(0.14),
                               in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(royalBlue.opacity(0.25), lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
        }
    }

    /// Serve-all with a "launch" animation: the button flies off to the right
    /// (as if the order was sent), then the actual serve request runs. The
    /// button reappears automatically when new pending items arrive.
    private func launchServeAll() {
        guard !isServingAll, !serveAllLaunched else { return }
        APHaptic.trigger()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            serveAllLaunched = true
        }
        // Fire the real serve request after the fly-away starts.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            serveAllActiveOrders()
        }
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
            case "paid":     return ("Paid", elfGreen)
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

    /// Reflect a successful server response immediately. The network layer
    /// refreshes the global cache, but that refresh can complete after this
    /// view's fetch and briefly return the pre-serve snapshot. Updating both
    /// sources prevents the checkout CTA from waiting for another poll cycle.
    @MainActor
    private func applyOptimisticServe(itemId: String, orderId: String) {
        func update(_ source: inout [Order]) {
            guard let orderIndex = source.firstIndex(where: { $0.id == orderId }),
                  let itemIndex = source[orderIndex].items.firstIndex(where: { $0.id == itemId }) else { return }
            source[orderIndex].items[itemIndex].status = "served"
            source[orderIndex].items[itemIndex].servedBy = loggedInEmployeeName
            let allServed = !source[orderIndex].items.isEmpty && source[orderIndex].items.allSatisfy {
                $0.status == "served" || $0.status == "cancelled"
            }
            if allServed && source[orderIndex].status != "completed" {
                source[orderIndex].status = "served"
                isPreparingCheckout = true
            }
        }
        update(&orders)
        update(&networkService.orders)
    }

    private func scheduleOrderRefresh() {
        Task {
            // Let the row-version trigger/realtime event settle before the
            // authoritative refresh; the CTA is already visible optimistically.
            try? await Task.sleep(nanoseconds: 300_000_000)
            await MainActor.run {
                if self.isAllServed { self.isPreparingCheckout = false }
            }
            await loadOrders()
        }
    }

    private func deleteItem(_ item: OrderItem, from order: Order) {
        Task { _ = try? await NetworkService.shared.deleteOrderItem(itemId: item.id) }
    }

    private func serveItem(_ item: OrderItem, from order: Order) {
        guard !order.isAwaitingStaffApproval,
              item.status != "served", !servingItemIds.contains(item.id) else { return }
        servingItemIds.insert(item.id)
        APHaptic.trigger()
        Task {
            do {
                _ = try await NetworkService.shared.serveOrderItem(itemId: item.id, orderId: order.id, servedBy: loggedInEmployeeName)
                await MainActor.run { applyOptimisticServe(itemId: item.id, orderId: order.id) }
                scheduleOrderRefresh()
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
        guard !order.isAwaitingStaffApproval else { return }
        let pending = order.items.filter { $0.status != "served" && $0.status != "cancelled" }
        guard !pending.isEmpty else { return }
        APHaptic.trigger()
        isServingAll = true
        for item in pending { servingItemIds.insert(item.id) }
        Task {
            var succeeded = [OrderItem]()
            for item in pending {
                do {
                    _ = try await NetworkService.shared.serveOrderItem(itemId: item.id, orderId: order.id, servedBy: loggedInEmployeeName)
                    succeeded.append(item)
                } catch {
                    print("TableDetailView [serveOrder]: item \(item.id) failed — \(error)")
                }
            }
            for item in succeeded {
                // Only successful calls should be reflected locally.
                // `serveOrderItem` is idempotent and may have committed before
                // a transient conflict was retried.
                await MainActor.run { applyOptimisticServe(itemId: item.id, orderId: order.id) }
            }
            scheduleOrderRefresh()
            await MainActor.run {
                for item in pending { servingItemIds.remove(item.id) }
                isServingAll = false
            }
        }
    }

    /// Approve pending self-service order (single order, per-row button)
    private func approveOrder(_ order: Order) {
        guard !approvingOrderIds.contains(order.id) else { return }
        APHaptic.trigger()
        approvingOrderIds.insert(order.id)
        Task {
            do {
                _ = try await NetworkService.shared.approveOrder(order: order)
                await loadOrders()
            } catch {
                approveErrorMessage = error.localizedDescription
                showApproveErrorAlert = true
                await loadOrders()
            }
            approvingOrderIds.remove(order.id)
        }
    }

    /// Serve all pending items across ALL active orders
    private func serveAllActiveOrders() {
        let pending = activeOrders.filter { !$0.isAwaitingStaffApproval }.flatMap { order in
            order.items
                .filter { $0.status != "served" && $0.status != "cancelled" }
                .map { (item: $0, order: order) }
        }
        guard !pending.isEmpty else { return }
        isServingAll = true
        serveFailedCount = 0
        for p in pending { servingItemIds.insert(p.item.id) }
        Task {
            var failCount = 0
            var succeeded = [(item: OrderItem, order: Order)]()
            for p in pending {
                // H-4 FIX: Use try/catch instead of try? to detect individual failures
                do {
                    _ = try await NetworkService.shared.serveOrderItem(
                        itemId: p.item.id, orderId: p.order.id, servedBy: loggedInEmployeeName)
                    succeeded.append(p)
                } catch {
                    failCount += 1
                    print("TableDetailView [serveAll]: item \(p.item.id) failed — \(error)")
                }
            }
            for p in succeeded {
                await MainActor.run { applyOptimisticServe(itemId: p.item.id, orderId: p.order.id) }
            }
            scheduleOrderRefresh()
            await MainActor.run {
                for p in pending { servingItemIds.remove(p.item.id) }
                isServingAll = false
                // Reset launch flag so the checkout (Payment) row can appear once
                // all items are served. New pending items restore Serve All via
                // .onChange(of: pendingServeCount).
                if failCount == pending.count {
                    serveAllLaunched = false   // total failure → bring serve button back
                    APHaptic.error()
                } else {
                    serveAllLaunched = false
                    APHaptic.success()
                }
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
            let hasActiveWorkSession = (try? await NetworkService.shared.hasActiveTimecard(for: loggedInEmployeeId)) ?? false
            await MainActor.run {
                if hasActiveWorkSession { showingAddItemsSheet = true } else { showShiftGuard = true }
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
        guard !isClearingTable else { return }
        stillDiningTimer?.invalidate()
        stillDiningTimer = nil
        isClearingTable = true
        APHaptic.trigger()
        
        let tableNumber = table.tableNumber
        Task {
            do {
                _ = try await NetworkService.shared.closeSession(tableNumber: tableNumber)
                _ = try await NetworkService.shared.updateTableStatus(tableNumber: tableNumber, status: "vacant")
                await MainActor.run {
                    postPaymentStatus = .left
                    if let idx = networkService.tables.firstIndex(where: { $0.tableNumber == tableNumber }) {
                        networkService.tables[idx].status = "vacant"
                        networkService.tables[idx].guestCount = 0
                        networkService.tables[idx].activeSessionId = nil
                        networkService.tables[idx].sessionToken = nil
                        networkService.tables[idx].currentTotal = 0
                        networkService.tables[idx].sessionStartedAt = nil
                    }
                    isClearingTable = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isClearingTable = false
                    clearTableError = error.localizedDescription
                    print("Failed to clear table on server: \(error.localizedDescription)")
                }
            }
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
                tableNumber: table.tableNumber,
                activeSessionId: currentTable.activeSessionId,
                sessionToken: currentTable.sessionToken,
                sessionStartedAt: currentTable.sessionStartedAt
            )
            await MainActor.run {
                loadOrdersError = nil
                withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) {
                    orders = fetched
                }
                // If all active orders are now completed → enter post-payment mode
                let active = fetched.filter { $0.status != "cancelled" }
                let allCompleted = !active.isEmpty && active.allSatisfy { $0.isPaid }
                if allCompleted && postPaymentStatus == nil {
                    enterPostPaymentMode()
                }
            }
        } catch {
            await MainActor.run {
                loadOrdersError = "load_orders_failed".localized(for: "th") + "\n\(error.localizedDescription)"
            }
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
                .simultaneousGesture(
                    DragGesture(minimumDistance: 12)
                        .onChanged { val in
                            if item.status == "served" { return }
                            guard abs(val.translation.width) > abs(val.translation.height) else { return }
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
                        .font(.system(size: 12, weight: item.status == "served" ? .regular : .semibold))
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
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(elfGreen)
                        }
                    }
                }

                // ── Options + note (unified, parity with master device) ──────
                ItemOptionsView(
                    modifiers: item.modifiers.map { ($0.name, $0.price) },
                    notes: item.notes,
                    tint: royalBlue,
                    muted: item.status == "served",
                    showNote: isExpanded
                )
            }

            Spacer()

            Text("฿\(Int(item.price * Double(item.quantity)))")
                .font(.system(size: 12, weight: .bold))
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
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                    .background(Color(.systemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
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
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.appSurface)
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
    var allowsQuantityEdit: Bool = true

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

                    // Quantity stepper (disabled for Quick Order until the
                    // server-side order-total mutation RPC is available).
                    if allowsQuantityEdit {
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
                    }

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
    @State private var selectedCategory = "all"
    @State private var errorMsg:    String? = nil

    private let royalBlue = Color.appAccent
    private let elfGreen  = Color.appTeal

    private var categories: [String] {
        let cats = Set(menuItems.map { $0.category }.filter { !$0.isEmpty })
        return ["all"] + cats.sorted()
    }

    private var filteredItems: [MenuItem] {
        var items = menuItems
        if selectedCategory != "all" {
            items = items.filter { $0.category == selectedCategory }
        }
        if !searchText.isEmpty {
            items = items.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.category.localizedCaseInsensitiveContains(searchText)
            }
        }
        return items
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
                        TextField("search_menu".localized(for: appLanguage), text: $searchText)
                            .foregroundColor(.textPrimary)
                    }
                    .padding(10)
                    .background(Color.appSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal).padding(.top, 8).padding(.bottom, 4)

                    // Category pills (Quick Service style)
                    if !menuItems.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(categories, id: \.self) { cat in
                                    Button {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            selectedCategory = cat
                                        }
                                    } label: {
                                        Text(cat == "all"
                                             ? "all_categories".localized(for: appLanguage)
                                             : cat.capitalized)
                                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 8)
                                            .background(selectedCategory == cat ? Color.brandGreenDark : Color.appSurface)
                                            .foregroundColor(selectedCategory == cat ? .white : .textSecondary)
                                            .cornerRadius(20)
                                            .shadow(
                                                color: selectedCategory == cat
                                                    ? Color.brandGreenDark.opacity(0.2)
                                                    : Color.black.opacity(0.02),
                                                radius: 4, x: 0, y: 2
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 20)
                                                    .stroke(selectedCategory == cat ? Color.clear : Color.appDivider, lineWidth: 1)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                        }
                    }

                    if isLoading {
                        ProgressView().tint(royalBlue).frame(maxHeight: .infinity)
                    } else if filteredItems.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "fork.knife.circle")
                                .font(.system(size: 36))
                                .foregroundColor(.textSecondary.opacity(0.5))
                            Text("no_menu_match".localized(for: appLanguage))
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.textSecondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            // Emoji / category icon / Product Image
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(royalBlue.opacity(0.08)).frame(width: 38, height: 38)
                
                if let urlStr = item.image_url, !urlStr.isEmpty, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable()
                                .aspectRatio(contentMode: .fill)
                        case .failure, .empty:
                            Text(item.emoji ?? "🍽").font(.system(size: 20))
                        @unknown default:
                            Text(item.emoji ?? "🍽").font(.system(size: 20))
                        }
                    }
                    .frame(width: 38, height: 38)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Text(item.emoji ?? "🍽").font(.system(size: 20))
                }
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


// ─────────────────────────────────────────────────────────────────────────────
// MARK: - GuestBillPreviewSheet
// Pre-payment guest bill preview. Print is relayed to the receipt-station
// iPad (cable/thermal printer) via sync_outbox — not AirPrint on the phone.
// ─────────────────────────────────────────────────────────────────────────────

struct GuestBillPreviewSheet: View {
    let table: RestaurantTable
    let orders: [Order]

    @Environment(\.dismiss) private var dismiss
    @AppStorage("app_language") private var appLanguage = "en"

    @State private var isSendingPrint = false
    @State private var printStatusMessage: String? = nil
    @State private var printSucceeded = false

    private var billableItems: [(qty: Int, name: String, price: Double, modifiers: [OrderItemModifier])] {
        orders.flatMap { order in
            order.items
                .filter { $0.status != "cancelled" }
                .map { (qty: $0.quantity, name: $0.name, price: $0.price, modifiers: $0.modifiers) }
        }
    }

    private var subtotal: Double {
        orders.map(\.total).reduce(0, +)
    }
    private var tax: Double { subtotal * 0.07 }
    private var serviceCharge: Double { subtotal * 0.10 }
    private var grandTotal: Double { subtotal + tax + serviceCharge }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(spacing: 4) {
                        Text("AlphaPos")
                            .font(.title3.weight(.black))
                        Text(String(format: "table_guests_count_format".localized(for: appLanguage),
                                    table.tableNumber, table.guestCount))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("guest_bill_preview_title".localized(for: appLanguage))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text("print_via_ipad_hint".localized(for: appLanguage))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)

                    Divider()

                    ForEach(Array(billableItems.enumerated()), id: \.offset) { _, item in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text("\(item.qty)x \(item.name)")
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                Text("฿\(String(format: "%.2f", item.price * Double(item.qty)))")
                                    .font(.subheadline.weight(.semibold))
                            }
                            if !item.modifiers.isEmpty {
                                Text("+ " + item.modifiers.map(\.name).joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }

                    Group {
                        Divider()
                        billRow(label: "ยอดก่อนภาษี/บริการ", value: subtotal)
                        billRow(label: "ภาษีมูลค่าเพิ่ม (7%)", value: tax)
                        billRow(label: "ค่าบริการ (10%)", value: serviceCharge)
                        Divider()
                        HStack {
                            Text("ยอดรวมทั้งสิ้น")
                                .font(.headline).fontWeight(.black)
                            Spacer()
                            Text("฿\(String(format: "%.2f", grandTotal))")
                                .font(.headline).fontWeight(.black)
                                .foregroundColor(.appRose)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }

                    Text("ขอบคุณที่ใช้บริการ")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding()

                if let printStatusMessage {
                    Label(
                        printStatusMessage,
                        systemImage: printSucceeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundColor(printSucceeded ? .appTeal : .appRose)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("print_guest_bill".localized(for: appLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("close".localized(for: appLanguage)) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        sendPreBillToIPad()
                    } label: {
                        if isSendingPrint {
                            ProgressView().scaleEffect(0.85)
                        } else {
                            Label("พิมพ์", systemImage: "printer.fill")
                        }
                    }
                    .disabled(isSendingPrint || orders.isEmpty)
                }
            }
        }
    }

    private func billRow(label: String, value: Double) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text("฿\(String(format: "%.2f", value))")
                .font(.subheadline)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private func sendPreBillToIPad() {
        let orderIds = orders.map(\.id)
        guard !orderIds.isEmpty else { return }
        isSendingPrint = true
        printStatusMessage = nil
        Task {
            do {
                try await NetworkService.shared.requestPreBillPrint(
                    orderIds: orderIds,
                    tableNumber: table.tableNumber
                )
                await MainActor.run {
                    isSendingPrint = false
                    printSucceeded = true
                    printStatusMessage = "print_sent_to_ipad".localized(for: appLanguage)
                    APHaptic.success()
                }
            } catch {
                await MainActor.run {
                    isSendingPrint = false
                    printSucceeded = false
                    printStatusMessage = "print_send_failed".localized(for: appLanguage)
                        + ": \(error.localizedDescription)"
                    APHaptic.error()
                }
            }
        }
    }
}


// ─────────────────────────────────────────────────────────────────────────────
// MARK: - FlowChips (option / modifier chips with wrapping layout)
// ─────────────────────────────────────────────────────────────────────────────
//
// Renders a set of option chips that wrap to new lines as needed. Each chip is
// a Liquid-Glass pill showing the option name and, when > 0, its extra price.
// Mirrors the master (iPad) device styling so both apps feel consistent.
struct FlowChips: View {
    let chips: [(String, Double)]
    var tint: Color = .appAccent
    var muted: Bool = false

    var body: some View {
        FlowLayout(spacing: 5) {
            ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                HStack(spacing: 3) {
                    Text(chip.0)
                        .font(.system(size: 10.5, weight: .semibold))
                    if chip.1 > 0 {
                        Text("+฿\(Int(chip.1))")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(muted ? Color.textSecondary : tint)
                    }
                }
                .foregroundColor(muted ? Color.textSecondary : Color.textPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .apLiquidGlass(
                    tint: (muted ? Color.gray : tint).opacity(0.12),
                    in: Capsule(style: .continuous)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke((muted ? Color.gray : tint).opacity(0.22), lineWidth: 0.8)
                )
            }
        }
    }
}


// ─────────────────────────────────────────────────────────────────────────────
// MARK: - ItemOptionsView (unified chips + note, shared across screens)
// ─────────────────────────────────────────────────────────────────────────────
//
// Single source of truth for rendering an order item's options and note so
// every screen (Table Detail, Order Timeline, Billing) looks identical:
//   • structured modifiers  → glass chips with +฿ price
//   • no modifiers, but notes that look like an option list (comma / • separated)
//                            → chips as a graceful fallback
//   • a remaining free-text note → a 📝 line beneath the chips
struct ItemOptionsView: View {
    let modifiers: [(String, Double)]
    let notes: String?
    var tint: Color = .appAccent
    var muted: Bool = false
    /// When false the free-text note is hidden (e.g. collapsed rows).
    var showNote: Bool = true

    var body: some View {
        let noteText = (notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let hasNote = !noteText.isEmpty

        // Chips: real modifiers, or a fallback parse of the note when there are none.
        let fallback: [(String, Double)] = modifiers.isEmpty ? ItemOptionsView.parseNotes(notes) : []
        let chips = modifiers + fallback
        // Only show the 📝 note line when we did NOT consume the note as fallback chips.
        let showNoteLine = showNote && hasNote && !modifiers.isEmpty ? true : (showNote && hasNote && fallback.isEmpty)

        if !chips.isEmpty || showNoteLine {
            VStack(alignment: .leading, spacing: 4) {
                if !chips.isEmpty {
                    FlowChips(chips: chips, tint: tint, muted: muted)
                }
                if showNoteLine {
                    HStack(alignment: .top, spacing: 4) {
                        Text("📝")
                            .font(.system(size: 10))
                        Text(noteText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(muted ? Color.textSecondary : tint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.top, 1)
        }
    }

    /// Parse legacy free-text notes into pseudo-modifiers (comma / newline / • separated).
    static func parseNotes(_ notes: String?) -> [(String, Double)] {
        guard let notes, !notes.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return notes
            .components(separatedBy: CharacterSet(charactersIn: ",\n•"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { ($0, 0.0) }
    }
}
