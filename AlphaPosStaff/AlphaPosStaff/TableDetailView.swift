import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - EditTarget  (รวม item + order ไว้ด้วยกัน ป้องกัน sheet เปล่า)
// ─────────────────────────────────────────────────────────────────────────────
struct EditTarget: Identifiable {
    let id   = UUID()
    let item:  OrderItem
    let order: Order
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - TableDetailView  (Enterprise redesign)
// Colors: Royal Blue #2D71F8 · Elf Green #1C8370 · Coral Red #FC4A4A
// ─────────────────────────────────────────────────────────────────────────────
struct TableDetailView: View {
    let table: RestaurantTable
    @AppStorage("app_language") private var appLanguage = "en"
    @AppStorage("logged_in_employee_id") private var loggedInEmployeeId = ""

    @State private var orders: [Order] = []
    @State private var isLoading = false
    @State private var showingAddItemsSheet = false
    @State private var selectedCategory = "all"
    @State private var cartItems: [MenuItem: Int] = [:]
    @State private var showShiftGuard = false

    // ── Item action states ──────────────────────────────────────────────────
    // ใช้ EditTarget struct รวม item + order ไว้ด้วยกัน
    // เพื่อป้องกัน sheet เปล่าเมื่อ state 2 ตัวถูก set ต่างเวลากัน
    @State private var editTarget:    EditTarget? = nil   // sheet: edit qty + note
    @State private var deleteTarget:  EditTarget? = nil   // confirm delete dialog

    @Environment(\.dismiss) private var dismiss

    // ── Design tokens ───────────────────────────────────────
    private let royalBlue  = Color(hex: "2D71F8")
    private let elfGreen   = Color(hex: "1C8370")
    private let coralRed   = Color(hex: "FC4A4A")

    private var currentTable: RestaurantTable {
        NetworkService.shared.tables.first(where: { $0.tableNumber == table.tableNumber }) ?? table
    }

    private var isAllServed: Bool {
        if !NetworkService.shared.kitchenWorkflowRequired { return true }
        guard !orders.isEmpty else { return false }
        for order in orders {
            if order.status == "cancelled" { continue }
            for item in order.items where item.status != "served" { return false }
        }
        return true
    }

    // ─────────────────────────────────────────────────────────
    var body: some View {
        ZStack {
            Color(hex: "F0F2F5").ignoresSafeArea()

            VStack(spacing: 0) {
                infoBanner
                Divider().background(Color(hex: "E2E5EB"))

                if isLoading {
                    ProgressView().tint(royalBlue).frame(maxHeight: .infinity)
                } else if orders.isEmpty {
                    emptyState
                } else {
                    orderScrollContent
                }

                bottomBar
            }
        }
        .navigationTitle("table_details".localized(for: appLanguage))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .fontWeight(.semibold)
                        .foregroundColor(royalBlue)
                }
            }
        }
        // ── Edit item sheet — ใช้ EditTarget ป้องกัน sheet เปล่า ──────────
        .sheet(item: $editTarget) { target in
            EditOrderItemSheet(
                item: target.item, order: target.order,
                appLanguage: appLanguage,
                royalBlue: royalBlue, elfGreen: elfGreen, coralRed: coralRed
            )
        }
        // ── Delete confirmation ──────────────────────────────
        .confirmationDialog(
            "delete_item_confirm".localized(for: appLanguage),
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("delete".localized(for: appLanguage), role: .destructive) {
                if let target = deleteTarget {
                    deleteItem(target.item, from: target.order)
                }
            }
            Button("cancel".localized(for: appLanguage), role: .cancel) {}
        }
        .sheet(isPresented: $showingAddItemsSheet) {
            AddItemsToOrderSheet(
                table: currentTable,
                cartItems: $cartItems
            )
        }
        .fullScreenCover(isPresented: $showShiftGuard) {
            ShiftGuardOverlay()
        }
        .onAppear { Task { await loadOrders() } }
        .onChange(of: NetworkService.shared.tables) { _, _ in
            Task { await loadOrders() }
        }
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Info Banner
    // ─────────────────────────────────────────────────────────
    private var infoBanner: some View {
        HStack(spacing: 12) {
            // Table icon
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(royalBlue.opacity(0.10))
                    .frame(width: 44, height: 44)
                Image(systemName: "fork.knife")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(royalBlue)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("session_orders".localized(for: appLanguage))
                    .font(.caption2).foregroundColor(Color(hex: "8A94A6"))
                Text(String(format: "table_guests_count_format".localized(for: appLanguage),
                            currentTable.tableNumber, currentTable.guestCount))
                    .font(.system(size: 16, weight: .bold)).foregroundColor(Color(hex: "1A1D23"))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if currentTable.status == "occupied" {
                    ElapsedTimeBadge(startedAt: currentTable.sessionStartedAt)
                }
                statusBadge(currentTable.status)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white)
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Order Scroll Content
    // ─────────────────────────────────────────────────────────
    private var orderScrollContent: some View {
        ScrollView {
            VStack(spacing: 14) {
                ForEach(orders) { order in
                    orderCard(order)
                        .transition(.asymmetric(
                            insertion:  .move(edge: .trailing).combined(with: .opacity),
                            removal:    .move(edge: .leading).combined(with: .opacity)
                        ))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .animation(.spring(response: 0.4, dampingFraction: 0.78), value: orders)
        }
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Order Card
    // ─────────────────────────────────────────────────────────
    private func orderCard(_ order: Order) -> some View {
        VStack(spacing: 0) {
            // ── Card Header ─────────────────────────────────
            HStack {
                Text(order.orderNumber)
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .foregroundColor(royalBlue)

                Spacer()

                let allServed = !order.items.isEmpty &&
                    order.items.allSatisfy { $0.status == "served" || $0.status == "cancelled" }
                let st = allServed ? "served" : order.status
                orderStatusBadge(st)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(royalBlue.opacity(0.05))

            // ── Items List ──────────────────────────────────
            VStack(spacing: 0) {
                ForEach(Array(order.items.enumerated()), id: \.element.id) { idx, item in
                    if item.status != "cancelled" {
                        EnterpriseOrderItemRow(
                            item: item,
                            royalBlue: royalBlue,
                            elfGreen: elfGreen,
                            coralRed: coralRed,
                            appLanguage: appLanguage,
                            onEdit: {
                                editTarget = EditTarget(item: item, order: order)
                            },
                            onNote: {
                                editTarget = EditTarget(item: item, order: order)
                            },
                            onDelete: {
                                deleteTarget = EditTarget(item: item, order: order)
                            }
                        )
                        .transition(.asymmetric(
                            insertion:  .move(edge: .bottom).combined(with: .opacity),
                            removal:    .move(edge: .trailing).combined(with: .opacity)
                        ))

                        if idx < order.items.filter({ $0.status != "cancelled" }).count - 1 {
                            Divider().padding(.leading, 14).background(Color(hex: "F0F2F5"))
                        }
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.75), value: order.items.count)
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: Color.black.opacity(0.07), radius: 8, x: 0, y: 3)
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Bottom Bar
    // ─────────────────────────────────────────────────────────
    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider().background(Color(hex: "E2E5EB"))
            HStack(spacing: 12) {
                // Add Food
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
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(royalBlue.opacity(0.25), lineWidth: 1))
                }

                // Bill / Checkout
                if !orders.isEmpty {
                    if isAllServed {
                        NavigationLink(destination: BillingView(table: currentTable, orders: orders)) {
                            HStack(spacing: 6) {
                                Image(systemName: "creditcard.fill")
                                    .font(.system(size: 14, weight: .bold))
                                Text("bill_payment".localized(for: appLanguage))
                                    .font(.system(size: 14, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(LinearGradient(
                                colors: [coralRed, Color(hex: "FF6B6B")],
                                startPoint: .leading, endPoint: .trailing))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "creditcard.fill")
                            Text("bill_payment".localized(for: appLanguage))
                                .font(.system(size: 14, weight: .bold))
                        }
                        .foregroundColor(Color(hex: "A0AABA"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Color(hex: "E8EBF0"))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.white)

            if !isAllServed && !orders.isEmpty {
                Text("all_items_served_before_checkout".localized(for: appLanguage))
                    .font(.caption2)
                    .foregroundColor(coralRed)
                    .padding(.bottom, 8)
            }
        }
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Empty State
    // ─────────────────────────────────────────────────────────
    private var emptyState: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(royalBlue.opacity(0.08)).frame(width: 80, height: 80)
                Image(systemName: "cart.badge.plus")
                    .font(.system(size: 34)).foregroundColor(royalBlue)
            }
            Text("no_orders_placed".localized(for: appLanguage))
                .font(.headline).foregroundColor(Color(hex: "5A6478"))

            Button {
                cartItems.removeAll()
                verifyShiftAndAddFood()
            } label: {
                Label("order_food".localized(for: appLanguage), systemImage: "plus")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 28).padding(.vertical, 12)
                    .background(LinearGradient(
                        colors: [royalBlue, Color(hex: "5B9BFF")],
                        startPoint: .leading, endPoint: .trailing))
                    .clipShape(Capsule())
            }
        }
        .frame(maxHeight: .infinity)
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Helpers — Badges
    // ─────────────────────────────────────────────────────────
    private func statusBadge(_ status: String) -> some View {
        let (label, color): (String, Color) = {
            switch status.lowercased() {
            case "occupied": return ("Active", coralRed)
            case "vacant":   return ("Vacant", elfGreen)
            default:         return (status.capitalized, Color(hex: "8A94A6"))
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
            case "served":    return ("Served",    Color(hex: "8A94A6"), Color(hex: "F0F2F5"))
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

    // ─────────────────────────────────────────────────────────
    // MARK: Actions
    // ─────────────────────────────────────────────────────────
    private func deleteItem(_ item: OrderItem, from order: Order) {
        Task {
            _ = try? await NetworkService.shared.deleteOrderItem(itemId: item.id)
        }
    }

    /// Verify active shift before allowing food orders.
    /// If no active timecard (clock-in without clock-out), show guard overlay.
    private func verifyShiftAndAddFood() {
        Task {
            let employeeId = loggedInEmployeeId
            let timecards = (try? await NetworkService.shared.fetchTimecards(for: employeeId)) ?? []
            let hasActiveShift = timecards.contains { $0.clockOut == nil || $0.clockOut == 0.0 }
            
            if hasActiveShift {
                showingAddItemsSheet = true
            } else {
                showShiftGuard = true
            }
        }
    }

    func loadOrders() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched = try await NetworkService.shared.fetchTableOrders(
                tableNumber: table.tableNumber
            )
            withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) {
                orders = fetched
            }
        } catch {
            print("TableDetailView: failed to load orders — \(error)")
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - EnterpriseOrderItemRow
// Full swipe + expand + edit + note + delete + add-on
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

    @State private var isExpanded  = false
    @State private var offset: CGFloat = 0
    @State private var showActions = false

    private let actionWidth: CGFloat = 180   // total swipe reveal width

    var body: some View {
        ZStack(alignment: .trailing) {
            // ── Swipe action tray ──────────────────────────
            swipeActionTray
                .opacity(showActions ? 1 : 0)
                .animation(.easeOut(duration: 0.2), value: showActions)

            // ── Row content ────────────────────────────────
            rowContent
                .offset(x: offset)
                .animation(.spring(response: 0.38, dampingFraction: 0.78), value: offset)
                .gesture(
                    DragGesture(minimumDistance: 12)
                        .onChanged { val in
                            if item.status == "served" { return }
                            let dx = val.translation.width
                            if dx < 0 {  // swipe left
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
                                    offset = -actionWidth
                                    showActions = true
                                } else {
                                    offset = 0
                                    showActions = false
                                }
                            }
                        }
                )
        }
        .clipped()
    }

    // ── Row content ───────────────────────────────────────────
    private var rowContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Item status indicator dot
                Circle()
                    .fill(statusDotColor)
                    .frame(width: 7, height: 7)
                    .animation(.easeInOut, value: item.status)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("\(item.quantity)×")
                            .font(.system(size: 13, weight: .black, design: .rounded))
                            .foregroundColor(royalBlue)
                        Text(item.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color(hex: "1A1D23"))
                    }
                    if let note = item.notes, !note.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "note.text")
                                .font(.system(size: 9))
                                .foregroundColor(Color(hex: "8A94A6"))
                            Text(note)
                                .font(.caption2)
                                .foregroundColor(Color(hex: "8A94A6"))
                                .lineLimit(1)
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text("฿\(Int(item.price * Double(item.quantity)))")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: "1A1D23"))
                    itemStatusPill
                }

                // Expand chevron
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(hex: "A0AABA"))
                        .frame(width: 24, height: 24)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())

            // ── Expanded action tray ───────────────────────
            if isExpanded {
                expandedActions
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal:   .move(edge: .top).combined(with: .opacity)
                    ))
            }
        }
        .background(Color.white)
    }

    // ── Expanded inline actions ────────────────────────────────
    private var expandedActions: some View {
        HStack(spacing: 8) {
            if item.status == "served" {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "8A94A6"))
                    Text("served_items_locked".localized(for: appLanguage))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(hex: "8A94A6"))
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color(hex: "F0F2F5"))
                .cornerRadius(8)
                Spacer()
            } else {
                // Edit qty
                actionChip(
                    icon: "pencil", label: "Edit Qty",
                    fg: royalBlue, bg: royalBlue.opacity(0.08),
                    action: onEdit
                )
                // Note only
                actionChip(
                    icon: "note.text.badge.plus", label: "Note",
                    fg: Color(hex: "F59E0B"), bg: Color(hex: "FFF7E6"),
                    action: onNote
                )
                Spacer()
                // Delete
                actionChip(
                    icon: "trash", label: "Delete",
                    fg: coralRed, bg: coralRed.opacity(0.08),
                    action: onDelete
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
        .background(Color(hex: "FAFBFC"))
    }

    private func actionChip(icon: String, label: String, fg: Color, bg: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(label)
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundColor(fg)
            .frame(width: 52, height: 44)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }

    // ── Swipe left action tray ─────────────────────────────────
    private var swipeActionTray: some View {
        HStack(spacing: 0) {
            // Edit
            swipeTrayButton(icon: "pencil", label: "Edit", color: royalBlue) {
                withAnimation { offset = 0; showActions = false }
                onEdit()
            }
            // Note
            swipeTrayButton(icon: "note.text.badge.plus", label: "Note", color: Color(hex: "F59E0B")) {
                withAnimation { offset = 0; showActions = false }
                onNote()
            }
            // Delete
            swipeTrayButton(icon: "trash.fill", label: "Delete", color: coralRed) {
                withAnimation { offset = 0; showActions = false }
                onDelete()
            }
        }
        .frame(width: actionWidth)
    }

    private func swipeTrayButton(icon: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .bold))
                Text(label)
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundColor(.white)
            .frame(width: 60, height: .infinity)
            .frame(maxHeight: .infinity)
            .background(color)
        }
        .buttonStyle(.plain)
    }

    // ── Status helpers ─────────────────────────────────────────
    private var statusDotColor: Color {
        switch item.status.lowercased() {
        case "cooking":  return Color(hex: "F59E0B")
        case "ready":    return elfGreen
        case "served":   return Color(hex: "A0AABA")
        default:         return Color(hex: "D1D5DB")
        }
    }

    private var itemStatusPill: some View {
        let (label, color): (String, Color) = {
            switch item.status.lowercased() {
            case "cooking":  return ("Cooking",  Color(hex: "F59E0B"))
            case "ready":    return ("Ready",    elfGreen)
            case "served":   return ("Served",   Color(hex: "A0AABA"))
            default:         return (item.status.capitalized, Color(hex: "A0AABA"))
            }
        }()
        return Text(label)
            .font(.system(size: 8, weight: .bold))
            .foregroundColor(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.10))
            .clipShape(Capsule())
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - EditOrderItemSheet
// Modify qty, add note, add modifier / extra
// ─────────────────────────────────────────────────────────────────────────────
struct EditOrderItemSheet: View {
    let item:        OrderItem
    let order:       Order
    let appLanguage: String
    let royalBlue:   Color
    let elfGreen:    Color
    let coralRed:    Color

    @Environment(\.dismiss) private var dismiss
    @State private var quantity:    Int    = 1
    @State private var note:        String = ""
    @State private var isSaving     = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // ── Item summary ─────────────────────────────
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(.headline).fontWeight(.bold)
                            .foregroundColor(Color(hex: "1A1D23"))
                        if let existingNote = item.notes, !existingNote.isEmpty {
                            Text(existingNote)
                                .font(.caption2).foregroundColor(Color(hex: "8A94A6"))
                                .lineLimit(2)
                        }
                    }
                    Spacer()
                    Text("฿\(Int(item.price * Double(quantity)))")
                        .font(.system(.headline, design: .rounded))
                        .fontWeight(.bold).foregroundColor(royalBlue)
                }
                .padding(.horizontal, 20).padding(.vertical, 16)
                .background(Color(hex: "F8F9FC"))

                Divider()

                ScrollView {
                    VStack(spacing: 0) {
                        // ── Qty stepper ─────────────────────────
                        editTab.padding(.bottom, 8)
                        Divider().padding(.horizontal, 20)
                        // ── Note field ──────────────────────────
                        noteTab
                    }
                }

                Divider()

                // ── Save button ──────────────────────────────
                Button {
                    save()
                } label: {
                    HStack {
                        if isSaving { ProgressView().tint(.white).scaleEffect(0.8) }
                        Text(isSaving ? "Saving..." : "Save Changes")
                            .font(.system(size: 15, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(LinearGradient(
                        colors: [royalBlue, Color(hex: "5B9BFF")],
                        startPoint: .leading, endPoint: .trailing))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 20).padding(.vertical, 12)
                }
            }
            .background(Color(hex: "F0F2F5"))
            .navigationTitle("Edit Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(royalBlue)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            quantity = item.quantity
            note     = item.notes ?? ""
        }
    }

    // ── Edit Tab (qty stepper) ─────────────────────────────────
    private var editTab: some View {
        VStack(spacing: 20) {
            Text("Quantity")
                .font(.subheadline).foregroundColor(Color(hex: "8A94A6"))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)

            HStack(spacing: 20) {
                Button {
                    if quantity > 1 { withAnimation(.spring()) { quantity -= 1 } }
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(quantity > 1 ? coralRed : Color(hex: "D1D5DB"))
                        .frame(width: 48, height: 48)
                        .background(quantity > 1 ? coralRed.opacity(0.10) : Color(hex: "F0F2F5"))
                        .clipShape(Circle())
                }

                Text("\(quantity)")
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundColor(royalBlue)
                    .frame(minWidth: 60, alignment: .center)
                    .contentTransition(.numericText())
                    .animation(.spring(), value: quantity)

                Button {
                    withAnimation(.spring()) { quantity += 1 }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 48, height: 48)
                        .background(royalBlue)
                        .clipShape(Circle())
                }
            }
            .padding(.vertical, 10)
        }
        .padding(.top, 20)
    }

    // ── Note Tab ───────────────────────────────────────────────
    private var noteTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Special Instructions / Note")
                .font(.subheadline).foregroundColor(Color(hex: "8A94A6"))

            TextEditor(text: $note)
                .font(.body)
                .foregroundColor(Color(hex: "1A1D23"))
                .padding(10)
                .frame(minHeight: 120)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(royalBlue.opacity(0.3), lineWidth: 1))

            Text("e.g. No spicy, extra sauce, allergy info")
                .font(.caption2).foregroundColor(Color(hex: "A0AABA"))
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }



    // ── Save ───────────────────────────────────────────────────
    private func save() {
        isSaving = true
        let finalNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            // PATCH order_items: quantity + notes
            _ = try? await NetworkService.shared.patchOrderItem(
                itemId:   item.id,
                quantity: quantity,
                notes:    finalNote.isEmpty ? nil : finalNote
            )
            await MainActor.run {
                isSaving = false
                dismiss()
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - AddItemsToOrderSheet
// Lets staff pick menu items and add them to an existing table order.
// ─────────────────────────────────────────────────────────────────────────────
struct AddItemsToOrderSheet: View {
    let table:      RestaurantTable
    @Binding var cartItems: [MenuItem: Int]

    @Environment(\.dismiss) private var dismiss
    @AppStorage("app_language") private var appLanguage = "en"
    @State private var menuItems: [MenuItem] = []
    @State private var isLoading = false
    @State private var isSending = false

    private let royalBlue = Color(hex: "2D71F8")
    private let elfGreen  = Color(hex: "1C8370")
    private let coralRed  = Color(hex: "FC4A4A")

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView().tint(royalBlue)
                } else {
                    catalogContent
                }
            }
            .navigationTitle("add_food".localized(for: appLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel".localized(for: appLanguage)) { dismiss() }
                        .foregroundColor(royalBlue)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await submitOrder() }
                    } label: {
                        HStack(spacing: 4) {
                            if isSending { ProgressView().scaleEffect(0.7).tint(.white) }
                            Text("Confirm (\(cartItems.values.reduce(0,+)))")
                                .fontWeight(.bold)
                        }
                        .foregroundColor(cartItems.isEmpty ? Color(hex:"A0AABA") : .white)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(cartItems.isEmpty ? Color(hex:"E8EBF0") : royalBlue)
                        .clipShape(Capsule())
                    }
                    .disabled(cartItems.isEmpty || isSending)
                }
            }
        }
        .presentationDetents([.large])
        .onAppear { Task { await loadMenu() } }
    }

    // ── Catalog grid ───────────────────────────────────────────
    private var catalogContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Group by category
                let categories = Array(Set(menuItems.map { $0.category })).sorted()
                ForEach(categories, id: \.self) { cat in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(cat.capitalized)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Color(hex: "8A94A6"))
                            .padding(.horizontal, 16)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(menuItems.filter { $0.category == cat }) { item in
                                menuItemCard(item)
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                }
            }
            .padding(.vertical, 12)
        }
        .background(Color(hex: "F0F2F5"))
    }

    private func menuItemCard(_ item: MenuItem) -> some View {
        let qty = cartItems[item] ?? 0
        return VStack(spacing: 6) {
            if let emoji = item.emoji {
                Text(emoji).font(.system(size: 28))
            } else {
                Image(systemName: "fork.knife")
                    .font(.system(size: 24)).foregroundColor(royalBlue)
            }
            Text(item.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(hex: "1A1D23"))
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text("฿\(Int(item.price))")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(royalBlue)

            // ── Qty stepper ─────────────────────────────────
            if qty == 0 {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        cartItems[item] = 1
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(royalBlue)
                }
            } else {
                HStack(spacing: 10) {
                    Button {
                        withAnimation(.spring()) {
                            if qty <= 1 { cartItems.removeValue(forKey: item) }
                            else { cartItems[item] = qty - 1 }
                        }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 20)).foregroundColor(coralRed)
                    }
                    Text("\(qty)")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundColor(royalBlue)
                        .contentTransition(.numericText())
                        .animation(.spring(), value: qty)
                    Button {
                        withAnimation(.spring()) { cartItems[item] = qty + 1 }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20)).foregroundColor(elfGreen)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(qty > 0 ? royalBlue.opacity(0.06) : Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(qty > 0 ? royalBlue.opacity(0.3) : Color.clear, lineWidth: 1.5))
        .animation(.easeInOut(duration: 0.2), value: qty)
    }

    private func loadMenu() async {
        isLoading = true
        menuItems = (try? await NetworkService.shared.fetchMenu()) ?? []
        isLoading = false
    }

    private func submitOrder() async {
        guard !cartItems.isEmpty else { return }
        isSending = true
        let items: [[String: Any]] = cartItems.map { (item, qty) in [
            "id":     UUID().uuidString,
            "name":   item.name,
            "itemId": item.id,
            "price":  item.price,
            "quantity": qty
        ]}
        let orderId     = UUID().uuidString
        let orderNumber = "AP-\(String(orderId.prefix(6)).uppercased())"
        _ = try? await NetworkService.shared.uploadOrder(
            orderId:     orderId,
            orderNumber: orderNumber,
            tableNumber: table.tableNumber,
            total:       cartItems.reduce(0) { $0 + $1.key.price * Double($1.value) },
            items:       items,
            sessionToken: table.sessionToken,
            guestCount:  table.guestCount
        )
        isSending = false
        dismiss()
    }
}
