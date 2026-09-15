//
//  BillHistoryView.swift
//  AlphaPos
//
//  Redesigned Master-Detail Bill & Sales History System.
//  Provides comprehensive multi-dimensional filters (Date, Channel/Delivery, Payment, Status),
//  KPI metric cards, rich bill rows with delivery & tender badges, full order inspection,
//  reprinting receipts, issuing full tax invoices, and reliable order voiding.
//

import SwiftUI
import SwiftData

struct BillHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var lm: LocalizationManager
    @EnvironmentObject private var sessionManager: AppSessionManager
    @AppStorage(BranchContext.storageKey) private var activeBranchId = ""

    // MARK: - Query
    @Query(filter: #Predicate<Order> { !$0.isDeleted }, sort: \Order.createdAt, order: .reverse)
    private var allOrders: [Order]

    // MARK: - Filter States
    @State private var searchText = ""
    @State private var selectedDatePreset: DateRangePreset = .today
    @State private var customStartDate = Calendar.current.startOfDay(for: Date())
    @State private var customEndDate = Date()
    @State private var selectedChannelFilter: ChannelFilter = .all
    @State private var selectedPaymentFilter: PaymentMethodFilter = .all
    @State private var selectedStatusFilter: OrderStatusFilter = .all
    @State private var showCustomDatePicker = false

    // MARK: - Selection & Modals
    @State private var selectedOrderId: UUID? = nil
    @State private var orderToVoid: Order? = nil
    @State private var orderForTaxInvoice: Order? = nil
    @State private var toastMessage: String? = nil
    @State private var isPrintingReceipt = false

    private var isThai: Bool { lm.currentLanguage == .thai }

    // MARK: - Active Branch Scoped Orders
    private var branchOrders: [Order] {
        guard let branchUUID = UUID(uuidString: activeBranchId) else {
            return allOrders
        }
        return allOrders.filter { $0.branch.id == branchUUID }
    }

    // MARK: - Date Range Calculation
    private var activeDateInterval: (start: Date, end: Date) {
        let calendar = Calendar.current
        let now = Date()
        switch selectedDatePreset {
        case .today:
            let start = calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? now
            return (start, end)
        case .yesterday:
            let startOfToday = calendar.startOfDay(for: now)
            let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? now
            return (startOfYesterday, startOfToday)
        case .last7Days:
            let start = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: now)) ?? now
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
            return (start, end)
        case .thisMonth:
            let components = calendar.dateComponents([.year, .month], from: now)
            let start = calendar.date(from: components) ?? now
            let nextMonth = calendar.date(byAdding: .month, value: 1, to: start) ?? now
            return (start, nextMonth)
        case .custom:
            let start = calendar.startOfDay(for: customStartDate)
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: customEndDate)) ?? customEndDate
            return (start, end)
        }
    }

    // MARK: - Filtered Orders
    private var filteredOrders: [Order] {
        let (startDate, endDate) = activeDateInterval
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return branchOrders.filter { order in
            // 1. Date filter
            guard order.createdAt >= startDate && order.createdAt < endDate else { return false }

            // 2. Channel / Delivery filter
            if !matchesChannelFilter(order) { return false }

            // 3. Payment filter
            if !matchesPaymentFilter(order) { return false }

            // 4. Status filter
            switch selectedStatusFilter {
            case .all:
                break
            case .completed:
                guard order.status != "cancelled" else { return false }
            case .voided:
                guard order.status == "cancelled" else { return false }
            }

            // 5. Search Text Query
            guard !query.isEmpty else { return true }

            let orderNumMatches = order.orderNumber.lowercased().contains(query)
            let cashierMatches = order.cashierName.lowercased().contains(query)
            let totalMatches = String(format: "%.2f", order.recognizedNetTotal).contains(query)
            let queueMatches = (order.queueNumber?.lowercased().contains(query) ?? false)
            let tableMatches = (order.tableSession?.table?.tableNumber.lowercased().contains(query) ?? false) ||
                               (order.floorTableNumber?.lowercased().contains(query) ?? false)
            let deliveryBrandMatches = (order.deliveryBrand?.lowercased().contains(query) ?? false)
            let platformRefMatches = (order.platformOrderNumber?.lowercased().contains(query) ?? false)
            let itemMatches = order.items.contains { $0.itemName.lowercased().contains(query) }

            return orderNumMatches || cashierMatches || totalMatches || queueMatches ||
                   tableMatches || deliveryBrandMatches || platformRefMatches || itemMatches
        }
    }

    private func matchesChannelFilter(_ order: Order) -> Bool {
        switch selectedChannelFilter {
        case .all:
            return true
        case .dineIn:
            return order.orderType == "dine_in"
        case .quickService:
            return order.isQuickServiceOrder
        case .takeOut:
            return order.orderType == "take_out"
        case .delivery:
            return order.orderType == "delivery" || order.deliveryBrand != nil
        case .grab:
            return (order.deliveryBrand?.lowercased().contains("grab") ?? false)
        case .lineMan:
            return (order.deliveryBrand?.lowercased().contains("line") ?? false)
        case .shopee:
            return (order.deliveryBrand?.lowercased().contains("shopee") ?? false)
        case .foodpanda:
            return (order.deliveryBrand?.lowercased().contains("panda") ?? false)
        case .robinhood:
            return (order.deliveryBrand?.lowercased().contains("robin") ?? false)
        }
    }

    private func matchesPaymentFilter(_ order: Order) -> Bool {
        switch selectedPaymentFilter {
        case .all:
            return true
        case .cash:
            return order.payments.contains { $0.paymentMethod == "cash" && !$0.isDeleted }
        case .qrPromptPay:
            return order.payments.contains {
                let m = $0.paymentMethod.lowercased()
                return (m.contains("qr") || m.contains("promptpay")) && !$0.isDeleted
            }
        case .card:
            return order.payments.contains {
                let m = $0.paymentMethod.lowercased()
                return (m.contains("card") || m.contains("credit")) && !$0.isDeleted
            }
        case .trueMoney:
            return order.payments.contains {
                $0.paymentMethod.lowercased().contains("true") && !$0.isDeleted
            }
        case .unpaid:
            return !order.isSettled && order.status != "cancelled"
        }
    }

    private var selectedOrder: Order? {
        guard let id = selectedOrderId else {
            return filteredOrders.first
        }
        return branchOrders.first(where: { $0.id == id }) ?? filteredOrders.first
    }

    // MARK: - KPI Metrics Computation
    private var kpiMetrics: (netSales: Double, billCount: Int, paidCount: Int, voidCount: Int, cashTotal: Double, qrTotal: Double, deliveryTotal: Double, voidedTotal: Double) {
        var netSales = 0.0
        var billCount = 0
        var paidCount = 0
        var voidCount = 0
        var cashTotal = 0.0
        var qrTotal = 0.0
        var deliveryTotal = 0.0
        var voidedTotal = 0.0

        for order in filteredOrders {
            billCount += 1
            if order.status == "cancelled" {
                voidCount += 1
                voidedTotal += order.recognizedNetTotal
            } else {
                paidCount += 1
                netSales += order.recognizedNetTotal

                if order.orderType == "delivery" || order.deliveryBrand != nil {
                    deliveryTotal += order.recognizedNetTotal
                }

                for payment in order.payments where !payment.isDeleted && payment.isCaptured {
                    let method = payment.paymentMethod.lowercased()
                    if method == "cash" {
                        cashTotal += payment.amount
                    } else if method.contains("qr") || method.contains("promptpay") {
                        qrTotal += payment.amount
                    }
                }
            }
        }

        return (netSales, billCount, paidCount, voidCount, cashTotal, qrTotal, deliveryTotal, voidedTotal)
    }

    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {
            // 1. KPI Metric Summary Bar
            kpiSummaryHeader

            Divider().background(Color.appDivider)

            // 2. Comprehensive Filter & Search Bar
            filterControlBar

            Divider().background(Color.appDivider)

            // 3. Two-Column Master-Detail Layout
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    // Left Column: Bill Master List
                    masterOrderList
                        .frame(width: min(max(proxy.size.width * 0.42, 380), 480))

                    Divider().background(Color.appDivider)

                    // Right Column: Detail & Actions Pane
                    detailInspectionPane
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(Color.appBackground)
        .navigationTitle(isThai ? "ประวัติบิล / รายการขาย" : "Bill History & Sales")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if selectedOrderId == nil, let first = filteredOrders.first {
                selectedOrderId = first.id
            }
        }
        .sheet(item: $orderForTaxInvoice) { order in
            FullTaxInvoiceSheet(order: order)
        }
        .sheet(item: $orderToVoid) { order in
            OrderVoidConfirmModal(order: order) {
                toastMessage = isThai ? "ยกเลิกบิล #\(order.orderNumber) เรียบร้อยแล้ว" : "Order #\(order.orderNumber) voided successfully"
                orderToVoid = nil
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = toastMessage {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.appTeal)
                    Text(toast)
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Color.black.opacity(0.85))
                .clipShape(Capsule())
                .shadow(radius: 8)
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        withAnimation { toastMessage = nil }
                    }
                }
            }
        }
    }

    // MARK: - KPI Summary Header
    private var kpiSummaryHeader: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                kpiCard(
                    title: isThai ? "ยอดขายสุทธิ" : "Net Sales",
                    value: "฿\(kpiMetrics.netSales.formatted(.number.precision(.fractionLength(2))))",
                    subtitle: "\(kpiMetrics.paidCount) \(isThai ? "บิลที่สำเร็จ" : "completed")",
                    icon: "chart.line.uptrend.xyaxis",
                    accentColor: .appAccent
                )

                kpiCard(
                    title: isThai ? "จำนวนบิลทั้งหมด" : "Total Orders",
                    value: "\(kpiMetrics.billCount)",
                    subtitle: "\(isThai ? "ยกเลิก" : "Voided") \(kpiMetrics.voidCount) \(isThai ? "บิล" : "bills")",
                    icon: "doc.plaintext.fill",
                    accentColor: .appTeal
                )

                kpiCard(
                    title: isThai ? "ยอดเงินสด" : "Cash Sales",
                    value: "฿\(kpiMetrics.cashTotal.formatted(.number.precision(.fractionLength(2))))",
                    subtitle: isThai ? "รับชำระเงินสด" : "Cash tender",
                    icon: "banknote.fill",
                    accentColor: .green
                )

                kpiCard(
                    title: isThai ? "ยอด QR พร้อมเพย์" : "PromptPay QR",
                    value: "฿\(kpiMetrics.qrTotal.formatted(.number.precision(.fractionLength(2))))",
                    subtitle: isThai ? "สแกนชำระเงิน" : "QR scanned",
                    icon: "qrcode",
                    accentColor: .blue
                )

                kpiCard(
                    title: isThai ? "ยอดเดลิเวอรี่" : "Delivery Sales",
                    value: "฿\(kpiMetrics.deliveryTotal.formatted(.number.precision(.fractionLength(2))))",
                    subtitle: isThai ? "ออเดอร์เดลิเวอรี่" : "Online delivery",
                    icon: "scooter",
                    accentColor: .orange
                )

                if kpiMetrics.voidCount > 0 {
                    kpiCard(
                        title: isThai ? "ยอดที่ยกเลิกบิล" : "Voided Sales",
                        value: "฿\(kpiMetrics.voidedTotal.formatted(.number.precision(.fractionLength(2))))",
                        subtitle: "\(kpiMetrics.voidCount) \(isThai ? "บิลที่ยกเลิก" : "voided bills")",
                        icon: "xmark.bin.fill",
                        accentColor: .appRose
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color.appSurface)
    }

    private func kpiCard(title: String, value: String, subtitle: String, icon: String, accentColor: Color) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.15))
                    .frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.textSecondary)
                Text(value)
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundColor(.textPrimary)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(.textTertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.appSurfaceHigh)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.appDivider, lineWidth: 0.8)
        )
    }

    // MARK: - Filter Control Bar
    private var filterControlBar: some View {
        VStack(spacing: 8) {
            // Row 1: Search Field & Date Presets
            HStack(spacing: 10) {
                // Search Input
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.textTertiary)
                    TextField(isThai ? "ค้นหาเลขบิล, โต๊ะ, แคชเชียร์, เมนูอาหาร, รหัสเดลิเวอรี่..." : "Search bill #, table, cashier, menu, delivery code...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.subheadline)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.textTertiary)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.appSurfaceHigh)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                // Date Preset Menu
                Menu {
                    ForEach(DateRangePreset.allCases) { preset in
                        Button {
                            selectedDatePreset = preset
                            if preset == .custom {
                                showCustomDatePicker = true
                            }
                        } label: {
                            HStack {
                                Text(preset.title(isThai: isThai))
                                if selectedDatePreset == preset {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.system(size: 13))
                        Text(selectedDatePreset.title(isThai: isThai))
                            .font(.subheadline.weight(.medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.appSurfaceHigh)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .sheet(isPresented: $showCustomDatePicker) {
                    customDateRangeModal
                }
            }

            // Row 2: Horizontal Filter Chips (Channels, Payment, Status)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Status Filter Menu
                    Menu {
                        ForEach(OrderStatusFilter.allCases) { st in
                            Button {
                                selectedStatusFilter = st
                            } label: {
                                HStack {
                                    Text(st.title(isThai: isThai))
                                    if selectedStatusFilter == st {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        filterPillLabel(
                            title: isThai ? "สถานะ: \(selectedStatusFilter.title(isThai: isThai))" : "Status: \(selectedStatusFilter.title(isThai: isThai))",
                            icon: "flag.fill",
                            isActive: selectedStatusFilter != .all
                        )
                    }

                    // Channel / Delivery Filter Menu
                    Menu {
                        ForEach(ChannelFilter.allCases) { ch in
                            Button {
                                selectedChannelFilter = ch
                            } label: {
                                HStack {
                                    Text(ch.title(isThai: isThai))
                                    if selectedChannelFilter == ch {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        filterPillLabel(
                            title: isThai ? "ช่องทาง: \(selectedChannelFilter.title(isThai: isThai))" : "Channel: \(selectedChannelFilter.title(isThai: isThai))",
                            icon: "scooter",
                            isActive: selectedChannelFilter != .all
                        )
                    }

                    // Payment Tender Filter Menu
                    Menu {
                        ForEach(PaymentMethodFilter.allCases) { pay in
                            Button {
                                selectedPaymentFilter = pay
                            } label: {
                                HStack {
                                    Text(pay.title(isThai: isThai))
                                    if selectedPaymentFilter == pay {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        filterPillLabel(
                            title: isThai ? "การชำระ: \(selectedPaymentFilter.title(isThai: isThai))" : "Payment: \(selectedPaymentFilter.title(isThai: isThai))",
                            icon: "creditcard.fill",
                            isActive: selectedPaymentFilter != .all
                        )
                    }

                    // Clear Filters Button if any active
                    if selectedChannelFilter != .all || selectedPaymentFilter != .all || selectedStatusFilter != .all || selectedDatePreset != .today || !searchText.isEmpty {
                        Button {
                            withAnimation {
                                selectedChannelFilter = .all
                                selectedPaymentFilter = .all
                                selectedStatusFilter = .all
                                selectedDatePreset = .today
                                searchText = ""
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "xmark.circle")
                                Text(isThai ? "ล้างตัวกรอง" : "Reset")
                            }
                            .font(.caption.bold())
                            .foregroundColor(.appRose)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.appRose.opacity(0.12))
                            .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.appSurface)
    }

    private func filterPillLabel(title: String, icon: String, isActive: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
            Text(title)
                .font(.caption.weight(.medium))
            Image(systemName: "chevron.down")
                .font(.system(size: 9))
        }
        .foregroundColor(isActive ? .white : .textPrimary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isActive ? Color.appAccent : Color.appSurfaceHigh)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(isActive ? Color.clear : Color.appDivider, lineWidth: 0.8)
        )
    }

    // MARK: - Master Order List (Left Pane)
    private var masterOrderList: some View {
        VStack(spacing: 0) {
            // Count Header
            HStack {
                Text(isThai ? "พบบิลทั้งหมด \(filteredOrders.count) รายการ" : "Found \(filteredOrders.count) orders")
                    .font(.caption.bold())
                    .foregroundColor(.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.appBackground)

            if filteredOrders.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 44))
                        .foregroundColor(.textTertiary)
                    Text(isThai ? "ไม่พบรายการบิลตามเงื่อนไขที่เลือก" : "No orders match current filters")
                        .font(.subheadline.bold())
                        .foregroundColor(.textSecondary)
                    Text(isThai ? "ลองเปลี่ยนคำค้นหา หรือรีเซ็ตตัวกรองช่วงเวลา" : "Try adjusting search query or date range")
                        .font(.caption)
                        .foregroundColor(.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredOrders) { order in
                            orderCardRow(order)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        }
        .background(Color.appSurface)
    }

    private func orderCardRow(_ order: Order) -> some View {
        let isSelected = selectedOrderId == order.id
        let isVoided = order.status == "cancelled"

        return Button {
            selectedOrderId = order.id
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                // Top line: Bill Number & Net Total
                HStack(alignment: .firstTextBaseline) {
                    Text("#\(order.orderNumber)")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(isSelected ? .white : .textPrimary)

                    Spacer()

                    Text("฿\(order.recognizedNetTotal.formatted(.number.precision(.fractionLength(2))))")
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundColor(isSelected ? .white : (isVoided ? .appRose : .textPrimary))
                }

                // Middle line: Channel Badge, Tender Badge, Status Badge
                HStack(spacing: 6) {
                    channelBadge(order: order, isSelected: isSelected)
                    tenderBadge(order: order, isSelected: isSelected)

                    Spacer()

                    statusBadge(order: order, isSelected: isSelected)
                }

                // Items summary line preview
                let activeItems = order.items.filter { !$0.isDeleted }
                let itemsSummary = activeItems.prefix(2).map { "\($0.quantity)x \($0.itemName)" }.joined(separator: ", ")
                let moreCount = activeItems.count > 2 ? " (+\(activeItems.count - 2))" : ""
                Text("\(itemsSummary)\(moreCount)")
                    .font(.caption2)
                    .foregroundColor(isSelected ? .white.opacity(0.85) : .textSecondary)
                    .lineLimit(1)

                // Bottom line: Time & Cashier
                HStack {
                    Text(order.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 10, design: .monospaced))

                    Spacer()

                    Text("แคชเชียร์: \(order.cashierName)")
                        .font(.system(size: 10))
                }
                .foregroundColor(isSelected ? .white.opacity(0.7) : .textTertiary)
            }
            .padding(12)
            .background(isSelected ? Color.appAccent : (isVoided ? Color.appRose.opacity(0.06) : Color.appSurfaceHigh))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.clear : (isVoided ? Color.appRose.opacity(0.3) : Color.appDivider), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Badges
    private func channelBadge(order: Order, isSelected: Bool) -> some View {
        let (label, icon, color): (String, String, Color) = {
            if let brand = order.deliveryBrand, !brand.isEmpty {
                let col: Color = {
                    let b = brand.lowercased()
                    if b.contains("grab") { return Color(hex: "00B14F") }
                    if b.contains("line") { return Color(hex: "00C25B") }
                    if b.contains("shopee") { return Color(hex: "F04D23") }
                    if b.contains("panda") { return Color(hex: "D6125D") }
                    if b.contains("robin") { return Color(hex: "7E22CE") }
                    return Color.orange
                }()
                return (brand, "scooter", col)
            } else if order.orderType == "dine_in" {
                let table = order.activeTableNumber ?? order.recoveryTableNumber ?? (isThai ? "ทานที่ร้าน" : "Dine-in")
                return (table, "table.furniture", Color.indigo)
            } else {
                let q = order.queueNumber.map { "#\($0)" } ?? (isThai ? "สั่งกลับบ้าน" : "Takeaway")
                return (q, "takeoutbag.and.cup.and.straw", Color.appAmber)
            }
        }()

        return HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text(label)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundColor(isSelected ? .white : color)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(isSelected ? Color.white.opacity(0.2) : color.opacity(0.12))
        .clipShape(Capsule())
    }

    private func tenderBadge(order: Order, isSelected: Bool) -> some View {
        let tenders = order.payments.filter { !$0.isDeleted && $0.isCaptured }
        let tenderName: String = {
            if tenders.isEmpty { return isThai ? "รอชำระ" : "Unpaid" }
            let methods = tenders.map(\.paymentMethod)
            if methods.contains(where: { $0.contains("qr") || $0.contains("promptpay") }) {
                return "PromptPay QR"
            } else if methods.contains("cash") {
                return isThai ? "เงินสด" : "Cash"
            } else if methods.contains(where: { $0.contains("card") || $0.contains("credit") }) {
                return isThai ? "บัตรเครดิต" : "Card"
            } else {
                return methods.first?.capitalized ?? "Paid"
            }
        }()

        return HStack(spacing: 3) {
            Image(systemName: tenderName.contains("QR") ? "qrcode" : (tenderName.contains("Cash") || tenderName == "เงินสด" ? "banknote" : "creditcard"))
                .font(.system(size: 9))
            Text(tenderName)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundColor(isSelected ? .white : .textSecondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(isSelected ? Color.white.opacity(0.15) : Color.appBackground)
        .clipShape(Capsule())
    }

    private func statusBadge(order: Order, isSelected: Bool) -> some View {
        let isVoided = order.status == "cancelled"
        let isSettled = order.isSettled

        let text: String = {
            if isVoided { return isThai ? "ยกเลิกแล้ว" : "Voided" }
            if isSettled { return isThai ? "สำเร็จ" : "Completed" }
            return isThai ? "ยังไม่ชำระ" : "Unpaid"
        }()

        let color: Color = {
            if isVoided { return .appRose }
            if isSettled { return .appTeal }
            return .appAmber
        }()

        return Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(isSelected ? .white : color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(isSelected ? Color.white.opacity(0.2) : color.opacity(0.12))
            .clipShape(Capsule())
    }

    // MARK: - Detail Inspection & Operations Pane (Right Pane)
    private var detailInspectionPane: some View {
        Group {
            if let order = selectedOrder {
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            // 1. Order Header Summary Banner
                            detailHeaderBanner(order)

                            // 2. Delivery & Channel Metadata (if applicable)
                            if order.orderType == "delivery" || order.deliveryBrand != nil || order.floorTableNumber != nil || order.queueNumber != nil {
                                detailChannelInfoCard(order)
                            }

                            // 3. Items Breakdown Table
                            detailItemsCard(order)

                            // 4. Financial Breakdown Card
                            detailFinancialCard(order)

                            // 5. Payment Tender & Reversal Card
                            detailPaymentTenderCard(order)
                        }
                        .padding(20)
                    }

                    Divider().background(Color.appDivider)

                    // 6. Bottom Pinned Operations Bar
                    detailActionBar(order)
                }
                .background(Color.appBackground)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "receipt")
                        .font(.system(size: 56))
                        .foregroundColor(.textTertiary)
                    Text(isThai ? "เลือกบิลจากรายการทางซ้ายมือ" : "Select an order from the list")
                        .font(.headline)
                        .foregroundColor(.textSecondary)
                    Text(isThai ? "คลิกเลือกบิลเพื่อดูรายละเอียดสินค้า ยอดชำระเงิน หรือจัดการยกเลิกบิล" : "Click an order to inspect items, financial details, or reprint/void")
                        .font(.caption)
                        .foregroundColor(.textTertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.appBackground)
            }
        }
    }

    private func detailHeaderBanner(_ order: Order) -> some View {
        let isVoided = order.status == "cancelled"

        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Text("#\(order.orderNumber)")
                        .font(.title2.bold())
                        .fontDesign(.monospaced)
                        .foregroundColor(.textPrimary)

                    statusBadge(order: order, isSelected: false)
                }

                Text("\(isThai ? "เวลาสั่งซื้อ" : "Created"): \(order.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(isThai ? "แคชเชียร์" : "Cashier"): \(order.cashierName)")
                    .font(.caption)
                    .foregroundColor(.textSecondary)

                if let receipt = order.receiptNumber, !receipt.isEmpty {
                    Text("\(isThai ? "เลขที่ใบเสร็จ" : "Receipt No."): \(receipt)")
                        .font(.caption2)
                        .foregroundColor(.textTertiary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(isThai ? "ยอดสุทธิ" : "Net Total")
                    .font(.caption2)
                    .foregroundColor(.textSecondary)

                Text("฿\(order.recognizedNetTotal.formatted(.number.precision(.fractionLength(2))))")
                    .font(.system(size: 26, weight: .bold, design: .monospaced))
                    .foregroundColor(isVoided ? .appRose : .appAccent)
            }
        }
        .padding(16)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isVoided ? Color.appRose.opacity(0.3) : Color.appDivider, lineWidth: 1)
        )
    }

    private func detailChannelInfoCard(_ order: Order) -> some View {
        HStack(spacing: 20) {
            if let brand = order.deliveryBrand, !brand.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "scooter")
                        .font(.system(size: 18))
                        .foregroundColor(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(isThai ? "ช่องทางเดลิเวอรี่" : "Delivery Platform")
                            .font(.caption2)
                            .foregroundColor(.textSecondary)
                        Text(brand)
                            .font(.subheadline.bold())
                            .foregroundColor(.textPrimary)
                    }
                }
            }

            if let ref = order.platformOrderNumber, !ref.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "number.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.appAccent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(isThai ? "รหัสออเดอร์เดลิเวอรี่" : "Platform Ref")
                            .font(.caption2)
                            .foregroundColor(.textSecondary)
                        Text(ref)
                            .font(.subheadline.bold())
                            .fontDesign(.monospaced)
                            .foregroundColor(.textPrimary)
                    }
                }
            }

            if let tableNo = order.activeTableNumber ?? order.recoveryTableNumber {
                HStack(spacing: 8) {
                    Image(systemName: "table.furniture")
                        .font(.system(size: 18))
                        .foregroundColor(.indigo)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(isThai ? "โต๊ะ" : "Table")
                            .font(.caption2)
                            .foregroundColor(.textSecondary)
                        Text(tableNo)
                            .font(.subheadline.bold())
                            .foregroundColor(.textPrimary)
                    }
                }
            }

            if let q = order.queueNumber, !q.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.appTeal)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(isThai ? "คิวรับสินค้า" : "Queue")
                            .font(.caption2)
                            .foregroundColor(.textSecondary)
                        Text("#\(q)")
                            .font(.subheadline.bold())
                            .foregroundColor(.textPrimary)
                    }
                }
            }

            Spacer()
        }
        .padding(14)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.appDivider, lineWidth: 0.8)
        )
    }

    private func detailItemsCard(_ order: Order) -> some View {
        let activeItems = order.items.filter { !$0.isDeleted }

        return VStack(alignment: .leading, spacing: 10) {
            Text(isThai ? "รายการสินค้าในบิล (\(activeItems.count) รายการ)" : "Order Items (\(activeItems.count))")
                .font(.subheadline.bold())
                .foregroundColor(.textSecondary)

            VStack(spacing: 0) {
                ForEach(activeItems) { item in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(item.quantity)x")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(.appAccent)
                            .frame(width: 32, alignment: .leading)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.itemName.isEmpty ? (item.menuItem?.localizedName ?? "Item") : item.itemName)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.textPrimary)

                            if !item.modifiers.isEmpty {
                                Text(item.modifiers.map {
                                    "\($0.modifier?.name ?? "") (+฿\($0.price.formatted(.number.precision(.fractionLength(0)))))"
                                }.joined(separator: ", "))
                                .font(.caption2)
                                .foregroundColor(.textTertiary)
                            }

                            if let notes = item.notes, !notes.isEmpty {
                                Text("หมายเหตุ: \(notes)")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                            }
                        }

                        Spacer()

                        Text("฿\(item.subtotal.formatted(.number.precision(.fractionLength(2))))")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundColor(.textPrimary)
                    }
                    .padding(.vertical, 8)

                    if item.id != activeItems.last?.id {
                        Divider().background(Color.appDivider)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color.appSurface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.appDivider, lineWidth: 0.8)
            )
        }
    }

    private func detailFinancialCard(_ order: Order) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(isThai ? "สรุปยอดเงินและภาษี" : "Financial Breakdown")
                .font(.subheadline.bold())
                .foregroundColor(.textSecondary)

            VStack(spacing: 6) {
                financialRow(title: isThai ? "ยอดรวมสินค้า" : "Subtotal", amount: order.subtotal)

                if order.discount > 0 {
                    financialRow(title: isThai ? "ส่วนลดโปรโมชั่น" : "Discount", amount: -order.discount, isHighlight: true)
                }

                if order.serviceCharge > 0 {
                    financialRow(title: isThai ? "ค่าบริการ (Service Charge)" : "Service Charge", amount: order.serviceCharge)
                }

                if order.tax > 0 {
                    financialRow(title: isThai ? "ภาษีมูลค่าเพิ่ม (VAT)" : "Tax (VAT)", amount: order.tax)
                }

                Divider().background(Color.appDivider)
                    .padding(.vertical, 2)

                HStack {
                    Text(isThai ? "ยอดสุทธิทั้งสิ้น" : "Grand Total")
                        .font(.subheadline.bold())
                        .foregroundColor(.textPrimary)
                    Spacer()
                    Text("฿\(order.recognizedNetTotal.formatted(.number.precision(.fractionLength(2))))")
                        .font(.title3.bold())
                        .fontDesign(.monospaced)
                        .foregroundColor(order.status == "cancelled" ? .appRose : .appAccent)
                }
            }
            .padding(14)
            .background(Color.appSurface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.appDivider, lineWidth: 0.8)
            )
        }
    }

    private func financialRow(title: String, amount: Double, isHighlight: Bool = false) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundColor(isHighlight ? .appTeal : .textSecondary)
            Spacer()
            Text(amount < 0 ? "-฿\(abs(amount).formatted(.number.precision(.fractionLength(2))))" : "฿\(amount.formatted(.number.precision(.fractionLength(2))))")
                .font(.caption.bold())
                .fontDesign(.monospaced)
                .foregroundColor(isHighlight ? .appTeal : .textPrimary)
        }
    }

    private func detailPaymentTenderCard(_ order: Order) -> some View {
        let payments = order.payments.filter { !$0.isDeleted }
        let refunds = order.refunds.filter { !$0.isDeleted && $0.status == "completed" }

        return VStack(alignment: .leading, spacing: 8) {
            Text(isThai ? "ข้อมูลการชำระเงิน & ประวัติรายการ" : "Payment & Settlement Records")
                .font(.subheadline.bold())
                .foregroundColor(.textSecondary)

            VStack(alignment: .leading, spacing: 8) {
                if payments.isEmpty {
                    Text(isThai ? "ยังไม่มีรายการชำระเงิน" : "No payment record found")
                        .font(.caption)
                        .foregroundColor(.textTertiary)
                } else {
                    ForEach(payments) { p in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(displayPaymentMethod(p.paymentMethod))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(.textPrimary)

                                    if p.status == "refunded" {
                                        Text(isThai ? "คืนเงินแล้ว" : "Refunded")
                                            .font(.caption2.bold())
                                            .foregroundColor(.appRose)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 1)
                                            .background(Color.appRose.opacity(0.15))
                                            .clipShape(Capsule())
                                    }
                                }

                                Text("\(isThai ? "ชำระเมื่อ" : "Paid at"): \(p.paidAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption2)
                                    .foregroundColor(.textTertiary)

                                if let ref = p.transactionReference, !ref.isEmpty {
                                    Text("Ref: \(ref)")
                                        .font(.caption2)
                                        .fontDesign(.monospaced)
                                        .foregroundColor(.textTertiary)
                                }
                            }

                            Spacer()

                            Text("฿\(p.amount.formatted(.number.precision(.fractionLength(2))))")
                                .font(.subheadline.bold())
                                .fontDesign(.monospaced)
                                .foregroundColor(p.status == "refunded" ? .appRose : .textPrimary)
                        }
                    }
                }

                // If refunded or voided
                if !refunds.isEmpty {
                    Divider().background(Color.appDivider)
                    ForEach(refunds) { r in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.uturn.backward.circle.fill")
                                        .foregroundColor(.appRose)
                                    Text(isThai ? "รายการคืนเงิน (Void Reversal)" : "Void Refund")
                                        .font(.caption.bold())
                                        .foregroundColor(.appRose)
                                }
                                if let notes = r.reasonNotes, !notes.isEmpty {
                                    Text("เหตุผล: \(notes)")
                                        .font(.caption2)
                                        .foregroundColor(.textSecondary)
                                }
                            }
                            Spacer()
                            Text("-฿\(r.refundAmount.formatted(.number.precision(.fractionLength(2))))")
                                .font(.caption.bold())
                                .fontDesign(.monospaced)
                                .foregroundColor(.appRose)
                        }
                    }
                }
            }
            .padding(14)
            .background(Color.appSurface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.appDivider, lineWidth: 0.8)
            )
        }
    }

    private func displayPaymentMethod(_ raw: String) -> String {
        switch raw.lowercased().replacingOccurrences(of: " ", with: "_") {
        case "cash": return isThai ? "เงินสด (Cash)" : "Cash"
        case "qr_promptpay": return "QR พร้อมเพย์ (PromptPay)"
        case "credit_card": return isThai ? "บัตรเครดิต (Credit Card)" : "Credit Card"
        case "true_money": return "TrueMoney Wallet"
        default: return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    // MARK: - Detail Action Bar (Bottom Pinned)
    private func detailActionBar(_ order: Order) -> some View {
        HStack(spacing: 12) {
            // Button 1: Reprint Receipt
            Button {
                reprintReceipt(order)
            } label: {
                HStack(spacing: 6) {
                    if isPrintingReceipt {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "printer.fill")
                    }
                    Text(isThai ? "พิมพ์ใบเสร็จซ้ำ" : "Reprint Receipt")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.textPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.appSurfaceHigh)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.appDivider, lineWidth: 1)
                )
            }
            .disabled(isPrintingReceipt)

            // Button 2: Full Tax Invoice
            Button {
                orderForTaxInvoice = order
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text.fill")
                    Text(isThai ? "ออกใบกำกับภาษี" : "Tax Invoice")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.appAccent)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.appAccent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            Spacer()

            // Button 3: Void Order
            if order.status != "cancelled" {
                Button {
                    orderToVoid = order
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.bin.fill")
                        Text(isThai ? "ยกเลิกบิลนี้ (Void)" : "Void Order")
                    }
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Color.appRose)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.appRose)
                    Text(isThai ? "บิลนี้ถูกยกเลิกแล้ว" : "Order Voided")
                        .font(.subheadline.bold())
                        .foregroundColor(.appRose)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.appRose.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.appSurface)
    }

    private func reprintReceipt(_ order: Order) {
        isPrintingReceipt = true
        Task {
            await PrintService.shared.dispatchReceipt(order, forcePrintReceipt: true)
            await MainActor.run {
                isPrintingReceipt = false
                toastMessage = isThai ? "ส่งพิมพ์ใบเสร็จซ้ำเรียบร้อย" : "Receipt dispatched to printer"
            }
        }
    }

    // MARK: - Custom Date Range Sheet
    private var customDateRangeModal: some View {
        NavigationStack {
            Form {
                Section(isThai ? "เลือกช่วงวันที่เริ่มต้นและสิ้นสุด" : "Select Date Range") {
                    DatePicker(isThai ? "วันที่เริ่มต้น" : "Start Date", selection: $customStartDate, displayedComponents: [.date])
                    DatePicker(isThai ? "วันที่สิ้นสุด" : "End Date", selection: $customEndDate, displayedComponents: [.date])
                }
            }
            .navigationTitle(isThai ? "กำหนดช่วงวันที่เอง" : "Custom Date Range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(isThai ? "นำไปใช้" : "Apply") {
                        showCustomDatePicker = false
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(isThai ? "ยกเลิก" : "Cancel") {
                        showCustomDatePicker = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Order Void Confirmation Modal (Fixed for QR & Direct Flow)
private struct OrderVoidConfirmModal: View {
    let order: Order
    var onCompleted: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var lm: LocalizationManager
    @EnvironmentObject private var sessionManager: AppSessionManager

    @State private var selectedReason = "duplicate_entry"
    @State private var customReason = ""
    @State private var restockInventory = true
    @State private var showingManagerPinSheet = false
    @State private var authorizedManagerId: UUID? = nil
    @State private var isProcessing = false

    private var isThai: Bool { lm.currentLanguage == .thai }

    private let reasons: [(id: String, th: String, en: String)] = [
        ("duplicate_entry", "คีย์ออเดอร์ซ้ำ / แก้ไขข้อผิดพลาด", "Duplicate order / Error"),
        ("customer_cancelled", "ลูกค้าขอยกเลิก / เปลี่ยนใจ", "Customer cancelled"),
        ("wrong_table_or_items", "คีย์ผิดโต๊ะ / ผิดเมนู", "Wrong table or items"),
        ("amount_mismatch", "ยอดเงินไม่ตรง / ลบเพื่อคีย์ใหม่", "Amount mismatch"),
        ("other", "อื่นๆ (ระบุหมายเหตุ)", "Other (specify note)")
    ]

    private var currentReasonText: String {
        let defaultText = reasons.first(where: { $0.id == selectedReason })?.th ?? selectedReason
        if selectedReason == "other", !customReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return customReason.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return defaultText
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Warning Banner
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.appRose)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(isThai ? "ยืนยันการยกเลิกบิล #\(order.orderNumber)" : "Confirm Void Order #\(order.orderNumber)")
                                .font(.headline)
                                .foregroundColor(.textPrimary)
                            Text(isThai
                                 ? "ยอดเงิน ฿\(order.recognizedNetTotal.formatted(.number.precision(.fractionLength(2)))) จะถูกหักลบออกจากยอดขาย รายการจะถูกบันทึกลงใน Audit Trail"
                                 : "฿\(order.recognizedNetTotal.formatted(.number.precision(.fractionLength(2)))) will be deducted from sales and audited.")
                                .font(.caption)
                                .foregroundColor(.textSecondary)
                        }
                    }
                    .padding(14)
                    .background(Color.appRose.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    // Reason Selector
                    VStack(alignment: .leading, spacing: 8) {
                        Text(isThai ? "สาเหตุในการยกเลิกบิล:" : "Reason for void:")
                            .font(.subheadline.bold())
                            .foregroundColor(.textPrimary)

                        Picker("", selection: $selectedReason) {
                            ForEach(reasons, id: \.id) { r in
                                Text(isThai ? r.th : r.en).tag(r.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.appSurfaceHigh)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                        if selectedReason == "other" {
                            TextField(isThai ? "ระบุเหตุผลเพิ่มเติม..." : "Specify reason...", text: $customReason)
                                .textFieldStyle(.roundedBorder)
                                .padding(.top, 4)
                        }
                    }
                    .padding(14)
                    .background(Color.appSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    // Restock Inventory Toggle
                    Toggle(isOn: $restockInventory) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(isThai ? "คืนสต๊อกสินค้าเข้าคลัง (Restock)" : "Return Stock to Inventory")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.textPrimary)
                            Text(isThai
                                 ? "คืนวัตถุดิบและรายการอาหารเข้าสต๊อกทันที เหมาะสำหรับบิลที่คีย์ซ้ำหรือไม่ได้ทำอาหารจริง"
                                 : "Restores ingredients and items into stock. Ideal for duplicate orders.")
                                .font(.caption2)
                                .foregroundColor(.textTertiary)
                        }
                    }
                    .toggleStyle(SwitchToggleStyle(tint: .appAccent))
                    .padding(14)
                    .background(Color.appSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    // Payment Reversal Information
                    if order.isSettled {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.uturn.backward.circle.fill")
                                    .foregroundColor(.appAmber)
                                Text(isThai ? "การคืนเงินและการปรับยอดบัญชี" : "Payment Reversal")
                                    .font(.caption.bold())
                                    .foregroundColor(.textPrimary)
                            }

                            Text(isThai
                                 ? "ระบบจะออกรายการคืนเงิน (Refund) เต็มจำนวน ฿\(order.recognizedNetTotal.formatted(.number.precision(.fractionLength(2)))) เพื่อหักลบยอดขายและยอดชำระเงิน (รวมถึง QR Code / เงินสด / บัตร) ออกจากรายงานและปิดบิลสมบูรณ์"
                                 : "Full refund of ฿\(order.recognizedNetTotal.formatted(.number.precision(.fractionLength(2)))) will be recorded to reconcile sales reports.")
                                .font(.caption2)
                                .foregroundColor(.textSecondary)
                        }
                        .padding(14)
                        .background(Color.appAmber.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(20)
            }
            .background(Color.appBackground)
            .navigationTitle(isThai ? "จัดการยกเลิกบิล (Void)" : "Void Order")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isThai ? "ปิด" : "Close") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    Divider().background(Color.appDivider)

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(isThai ? "ต้องใช้รหัสผ่านผู้จัดการ (PIN)" : "Manager PIN Required")
                                .font(.caption2)
                                .foregroundColor(.textTertiary)
                            Text(isThai ? "เพื่อความปลอดภัยในการยกเลิกยอดขาย" : "For audit & loss prevention")
                                .font(.caption2)
                                .foregroundColor(.textTertiary)
                        }

                        Spacer()

                        Button {
                            showingManagerPinSheet = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "xmark.bin.fill")
                                Text(isThai ? "ยืนยันยกเลิกบิลนี้" : "Confirm Void Order")
                            }
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(Color.appRose)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .disabled(isProcessing)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Color.appSurface)
                }
            }
            .sheet(isPresented: $showingManagerPinSheet) {
                ManagerPINVerificationSheet(
                    isPresented: $showingManagerPinSheet,
                    onSuccess: {
                        let managerId = authorizedManagerId
                        authorizedManagerId = nil
                        executeVoid(authorizedManagerId: managerId)
                    },
                    onAuthorizedManager: { manager in
                        authorizedManagerId = manager.id
                    }
                )
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func executeVoid(authorizedManagerId: UUID? = nil) {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }

        let managerId = authorizedManagerId ?? sessionManager.currentStaffSession?.employeeId

        order.voidEntireOrder(
            reason: currentReasonText,
            restockInventory: restockInventory,
            managerEmployeeId: managerId,
            in: modelContext
        )

        onCompleted()
        dismiss()
    }
}

// MARK: - Filter Enums
enum DateRangePreset: String, CaseIterable, Identifiable {
    case today, yesterday, last7Days, thisMonth, custom
    var id: String { rawValue }

    func title(isThai: Bool) -> String {
        switch self {
        case .today: return isThai ? "วันนี้" : "Today"
        case .yesterday: return isThai ? "เมื่อวาน" : "Yesterday"
        case .last7Days: return isThai ? "7 วันล่าสุด" : "Last 7 Days"
        case .thisMonth: return isThai ? "เดือนนี้" : "This Month"
        case .custom: return isThai ? "กำหนดเอง..." : "Custom..."
        }
    }
}

enum ChannelFilter: String, CaseIterable, Identifiable {
    case all, dineIn, quickService, takeOut, delivery, grab, lineMan, shopee, foodpanda, robinhood
    var id: String { rawValue }

    func title(isThai: Bool) -> String {
        switch self {
        case .all: return isThai ? "ทั้งหมด" : "All"
        case .dineIn: return isThai ? "ทานที่ร้าน" : "Dine-In"
        case .quickService: return isThai ? "Quick Service" : "Quick Service"
        case .takeOut: return isThai ? "สั่งกลับบ้าน" : "Takeaway"
        case .delivery: return isThai ? "เดลิเวอรี่ทั้งหมด" : "All Delivery"
        case .grab: return "GrabFood"
        case .lineMan: return "LINE MAN"
        case .shopee: return "ShopeeFood"
        case .foodpanda: return "Foodpanda"
        case .robinhood: return "Robinhood"
        }
    }
}

enum PaymentMethodFilter: String, CaseIterable, Identifiable {
    case all, cash, qrPromptPay, card, trueMoney, unpaid
    var id: String { rawValue }

    func title(isThai: Bool) -> String {
        switch self {
        case .all: return isThai ? "ทั้งหมด" : "All"
        case .cash: return isThai ? "เงินสด" : "Cash"
        case .qrPromptPay: return "QR พร้อมเพย์"
        case .card: return isThai ? "บัตรเครดิต" : "Card"
        case .trueMoney: return "TrueMoney"
        case .unpaid: return isThai ? "ยังไม่ชำระ" : "Unpaid"
        }
    }
}

enum OrderStatusFilter: String, CaseIterable, Identifiable {
    case all, completed, voided
    var id: String { rawValue }

    func title(isThai: Bool) -> String {
        switch self {
        case .all: return isThai ? "ทั้งหมด" : "All"
        case .completed: return isThai ? "สำเร็จ (ชำระแล้ว)" : "Completed"
        case .voided: return isThai ? "ยกเลิกแล้ว (Void)" : "Voided"
        }
    }
}
