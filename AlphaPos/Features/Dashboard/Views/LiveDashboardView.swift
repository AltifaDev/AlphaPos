// LiveDashboardView.swift
// AlphaPos — Enterprise Live KPI Dashboard (v2 — Real Data)
// Wired to SwiftData @Query for live, real-time metrics.

import SwiftUI
import SwiftData
import Charts

/// Real-time KPI Dashboard showing live business metrics from SwiftData.
/// This is the "home" landing page for the Master Device.
///
/// Data sources:
/// - Orders (@Query) → revenue, order count, avg prep time
/// - RestaurantTables (@Query) → table occupancy
/// - OrderItems (via Orders) → top selling items
/// - Timecards (@Query) → staff on duty
struct LiveDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var lm: LocalizationManager
    @AppStorage("active_branch_id") private var activeBranchId = ""
    @AppStorage("app_currency_symbol") private var currencySymbol = "฿"

    // MARK: - SwiftData Queries

    /// All orders (sorted newest first) — used for revenue, counts, activity
    @Query(sort: \Order.createdAt, order: .reverse) private var allOrders: [Order]

    /// All tables — used for occupancy calculation
    @Query private var allTables: [RestaurantTable]

    /// All order items — used for top selling items ranking
    @Query private var allOrderItems: [OrderItem]

    /// Active timecards (staff currently on duty)
    @Query(filter: #Predicate<Timecard> { $0.clockOut == nil })
    private var activeTimecards: [Timecard]

    /// All inventory items — used for stock alerts
    @Query private var inventoryItems: [InventoryItem]

    // MARK: - State

    @State private var refreshTimer: Timer? = nil
    @State private var currentTime = Date()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // MARK: - Header
                headerSection

                if !lowStockItems.isEmpty {
                    lowStockWarningBanner
                }

                // MARK: - KPI Cards Row
                kpiCardsSection

                // MARK: - Secondary KPIs
                secondaryKPIsSection

                // MARK: - Graphical Charts Row
                HStack(spacing: 16) {
                    hourlySalesChartCard
                    categoryBreakdownChartCard
                }

                // MARK: - Charts Row
                HStack(spacing: 16) {
                    topSellingItemsCard
                    staffOnDutyCard
                }

                // MARK: - Activity Feed
                activitySection
            }
            .padding()
        }
        .background(Color.appBackground)
        .onAppear {
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
                currentTime = Date()
            }
        }
        .onDisappear {
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
    }

    // MARK: - Computed Data

    /// Orders for today only
    private var todayOrders: [Order] {
        let startOfDay = Calendar.current.startOfDay(for: currentTime)
        return allOrders.filter { $0.createdAt >= startOfDay && !$0.isDeleted }
    }

    /// Completed orders today (not cancelled)
    private var completedTodayOrders: [Order] {
        todayOrders.filter { $0.status != "cancelled" }
    }

    /// Today's revenue (sum of total for non-cancelled orders)
    private var todayRevenue: Double {
        completedTodayOrders.reduce(0.0) { $0 + $1.total }
    }

    /// Yesterday's revenue (for comparison)
    private var yesterdayRevenue: Double {
        let startOfYesterday = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: currentTime))!
        let startOfToday = Calendar.current.startOfDay(for: currentTime)
        return allOrders
            .filter { $0.createdAt >= startOfYesterday && $0.createdAt < startOfToday && !$0.isDeleted && $0.status != "cancelled" }
            .reduce(0.0) { $0 + $1.total }
    }

    /// Revenue trend (% vs yesterday)
    private var revenueTrend: String? {
        guard yesterdayRevenue > 0 else { return nil }
        let change = ((todayRevenue - yesterdayRevenue) / yesterdayRevenue) * 100
        let sign = change >= 0 ? "+" : ""
        return "\(sign)\(Int(change))%"
    }

    /// Active orders (preparing/ready)
    private var activeOrders: [Order] {
        todayOrders.filter { $0.status == "preparing" || $0.status == "ready" }
    }

    /// Table occupancy percentage
    private var tableOccupancy: Int {
        let activeTables = allTables.filter { !$0.isDeleted }
        guard !activeTables.isEmpty else { return 0 }
        let occupied = activeTables.filter { $0.status == "occupied" }.count
        return Int((Double(occupied) / Double(activeTables.count)) * 100)
    }

    /// Average prep time in minutes (from order creation to status "ready" or "served")
    private var avgPrepTime: Int {
        let completedItems = todayOrders.flatMap { $0.items }
            .filter { $0.status == "served" || $0.status == "ready" }
        guard !completedItems.isEmpty else { return 0 }
        // Approximate: use order createdAt vs item updatedAt
        let totalMinutes = completedItems.reduce(0.0) { total, item in
            if let order = item.order {
                let diff = item.updatedAt.timeIntervalSince(order.createdAt) / 60
                return total + max(0, min(diff, 60)) // Cap at 60 min to avoid outliers
            }
            return total
        }
        return Int(totalMinutes / Double(completedItems.count))
    }

    /// Average prep time yesterday in minutes (from order creation to status "ready" or "served")
    private var yesterdayAvgPrepTime: Int {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: currentTime)
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday)!
        let yesterdayOrders = allOrders.filter { $0.createdAt >= startOfYesterday && $0.createdAt < startOfToday && !$0.isDeleted && $0.status != "cancelled" }
        let completedItems = yesterdayOrders.flatMap { $0.items }
            .filter { $0.status == "served" || $0.status == "ready" }
        guard !completedItems.isEmpty else { return 0 }
        let totalMinutes = completedItems.reduce(0.0) { total, item in
            if let order = item.order {
                let diff = item.updatedAt.timeIntervalSince(order.createdAt) / 60
                return total + max(0, min(diff, 60))
            }
            return total
        }
        return Int(totalMinutes / Double(completedItems.count))
    }

    /// Average prep time trend vs yesterday
    private var prepTimeTrend: String? {
        let todayAvg = avgPrepTime
        let yesterdayAvg = yesterdayAvgPrepTime
        guard todayAvg > 0, yesterdayAvg > 0 else { return nil }
        let diff = todayAvg - yesterdayAvg
        if diff < 0 {
            return "\(diff) min"
        } else if diff > 0 {
            return "+\(diff) min"
        }
        return "0 min"
    }

    /// Average order value
    private var avgOrderValue: Double {
        guard !completedTodayOrders.isEmpty else { return 0 }
        return todayRevenue / Double(completedTodayOrders.count)
    }

    /// Total guests today
    private var totalGuests: Int {
        completedTodayOrders.reduce(0) { $0 + $1.guestCount }
    }

    /// Top selling items (by quantity, today)
    private var topSellingItems: [(name: String, quantity: Int, revenue: Double)] {
        let todayItems = todayOrders.flatMap { $0.items }
            .filter { !$0.isDeleted && $0.status != "cancelled" }

        var itemMap: [String: (qty: Int, rev: Double)] = [:]
        for item in todayItems {
            let name = item.itemName.isEmpty ? "Unknown" : item.itemName
            let existing = itemMap[name] ?? (qty: 0, rev: 0)
            itemMap[name] = (qty: existing.qty + item.quantity, rev: existing.rev + item.subtotal)
        }

        return itemMap
            .map { (name: $0.key, quantity: $0.value.qty, revenue: $0.value.rev) }
            .sorted { $0.quantity > $1.quantity }
            .prefix(8)
            .map { $0 }
    }

    /// Staff currently on duty
    private var staffOnDuty: [(name: String, clockIn: Date)] {
        activeTimecards.compactMap { tc in
            guard let emp = tc.employee else { return nil }
            return (name: "\(emp.firstName) \(emp.lastName)", clockIn: tc.clockIn)
        }
    }

    /// Check if there is any sales activity yesterday or today (to show empty state in trend chart)
    private var hasSalesDataTodayOrYesterday: Bool {
        let calendar = Calendar.current
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: currentTime))!
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: currentTime))!
        return allOrders.contains { $0.createdAt >= startOfYesterday && $0.createdAt < endOfToday && !$0.isDeleted && $0.status != "cancelled" }
    }

    /// Hourly sales points for today vs yesterday trend chart
    private var chartSalesData: [DashboardHourlySalesPoint] {
        let todayLabel = lm.languageCode == "th" ? "วันนี้" : "Today"
        let yesterdayLabel = lm.languageCode == "th" ? "เมื่อวาน" : "Yesterday"

        var yesterdayHours: [Int: Double] = [:]
        var todayHours: [Int: Double] = [:]

        // Initialize operating hours (8 AM to 11 PM) with 0.0 to ensure a continuous line in Swift Charts
        for h in 8...23 {
            yesterdayHours[h] = 0.0
            todayHours[h] = 0.0
        }

        // Add actual SwiftData orders
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: currentTime)
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday)!
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday)!

        for order in allOrders where !order.isDeleted && order.status != "cancelled" {
            let orderHour = calendar.component(.hour, from: order.createdAt)
            if order.createdAt >= startOfToday && order.createdAt < endOfToday {
                todayHours[orderHour] = (todayHours[orderHour] ?? 0.0) + order.total
            } else if order.createdAt >= startOfYesterday && order.createdAt < startOfToday {
                yesterdayHours[orderHour] = (yesterdayHours[orderHour] ?? 0.0) + order.total
            }
        }

        var points: [DashboardHourlySalesPoint] = []
        for h in 8...23 {
            points.append(DashboardHourlySalesPoint(hour: h, revenue: yesterdayHours[h] ?? 0.0, period: yesterdayLabel))
            points.append(DashboardHourlySalesPoint(hour: h, revenue: todayHours[h] ?? 0.0, period: todayLabel))
        }
        return points
    }

    /// Category sales breakdown for category chart
    private var chartCategoryData: [DashboardCategorySalesPoint] {
        let mainsLabel = lm.languageCode == "th" ? "อาหารหลัก" : "Main Dishes"
        let appetizersLabel = lm.languageCode == "th" ? "ของทานเล่น" : "Appetizers"
        let drinksLabel = lm.languageCode == "th" ? "เครื่องดื่ม" : "Beverages"
        let dessertsLabel = lm.languageCode == "th" ? "ของหวาน" : "Desserts"
        let specialsLabel = lm.languageCode == "th" ? "เมนูพิเศษ" : "Specials"

        var categoryMap: [String: Double] = [:]

        let startOfDay = Calendar.current.startOfDay(for: currentTime)
        let endOfToday = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!
        let activeOrdersToday = allOrders.filter { $0.createdAt >= startOfDay && $0.createdAt < endOfToday && !$0.isDeleted && $0.status != "cancelled" }

        for order in activeOrdersToday {
            for item in order.items where !item.isDeleted {
                let rawCategory = item.menuItem?.category?.name ?? ""
                let mappedCategory: String
                let slug = rawCategory.lowercased()

                if slug.contains("main") {
                    mappedCategory = mainsLabel
                } else if slug.contains("appetizer") {
                    mappedCategory = appetizersLabel
                } else if slug.contains("drink") || slug.contains("beverage") {
                    mappedCategory = drinksLabel
                } else if slug.contains("dessert") {
                    mappedCategory = dessertsLabel
                } else if !rawCategory.isEmpty {
                    mappedCategory = rawCategory
                } else {
                    mappedCategory = specialsLabel
                }

                categoryMap[mappedCategory] = (categoryMap[mappedCategory] ?? 0.0) + item.subtotal
            }
        }

        guard !categoryMap.isEmpty else {
            return []
        }
        return categoryMap.map { DashboardCategorySalesPoint(categoryName: $0.key, revenue: $0.value) }
            .sorted { $0.revenue > $1.revenue }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("dashboard_title".t)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.textPrimary)
                Text("dashboard_subtitle".t)
                    .font(.subheadline)
                    .foregroundColor(.textSecondary)
            }
            Spacer()

            // Live indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle()
                            .stroke(Color.green.opacity(0.4), lineWidth: 2)
                            .scaleEffect(1.5)
                    )
                Text("LIVE")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.green)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.green.opacity(0.1))
            .cornerRadius(20)

            // Current time
            Text(currentTime.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.appSurfaceHigh)
                .cornerRadius(8)
        }
    }

    // MARK: - Primary KPI Cards

    private var kpiCardsSection: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 16) {
            KPICard(
                title: "kpi_revenue_today".t,
                value: "\(currencySymbol)\(todayRevenue.formatted(.number.precision(.fractionLength(0))))",
                icon: "banknote.fill",
                color: Color(hex: "10B981"),
                trend: revenueTrend
            )
            KPICard(
                title: "kpi_active_orders".t,
                value: "\(activeOrders.count)",
                icon: "tray.full.fill",
                color: Color(hex: "3B82F6"),
                trend: nil,
                subtitle: "\(completedTodayOrders.count) " + "kpi_total_today".t
            )
            KPICard(
                title: "kpi_table_occupancy".t,
                value: "\(tableOccupancy)%",
                icon: "tablecells.fill",
                color: Color(hex: "F59E0B"),
                trend: nil,
                subtitle: "\(allTables.filter { $0.status == "occupied" }.count)/\(allTables.filter { !$0.isDeleted }.count) " + "kpi_tables_suffix".t
            )
            KPICard(
                title: "kpi_avg_prep_time".t,
                value: avgPrepTime > 0 ? "\(avgPrepTime) min" : "—",
                icon: "clock.fill",
                color: Color(hex: "8B5CF6"),
                trend: prepTimeTrend
            )
        }
    }

    // MARK: - Secondary KPIs

    private var secondaryKPIsSection: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 16) {
            SecondaryKPICard(
                title: "kpi_avg_order_value".t,
                value: "\(currencySymbol)\(avgOrderValue.formatted(.number.precision(.fractionLength(0))))",
                icon: "cart.fill"
            )
            SecondaryKPICard(
                title: "kpi_total_guests".t,
                value: "\(totalGuests)",
                icon: "person.2.fill"
            )
            SecondaryKPICard(
                title: "kpi_staff_on_duty".t,
                value: "\(staffOnDuty.count)",
                icon: "person.badge.clock.fill"
            )
            SecondaryKPICard(
                title: "kpi_orders_completed".t,
                value: "\(completedTodayOrders.filter { $0.status == "completed" || $0.status == "served" }.count)",
                icon: "checkmark.circle.fill"
            )
        }
    }

    // MARK: - Top Selling Items Card

    private var topSellingItemsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "trophy.fill")
                    .foregroundColor(Color(hex: "F59E0B"))
                Text("kpi_top_items".t)
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                Spacer()
            }

            if topSellingItems.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "fork.knife.circle")
                        .font(.system(size: 28))
                        .foregroundColor(.textTertiary)
                    Text("no_activity_yet".t)
                        .font(.caption)
                        .foregroundColor(.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            } else {
                ForEach(Array(topSellingItems.enumerated()), id: \.offset) { index, item in
                    HStack(spacing: 10) {
                        // Rank
                        Text("#\(index + 1)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(index < 3 ? Color(hex: "F59E0B") : .textTertiary)
                            .frame(width: 24)

                        // Name
                        Text(item.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.textPrimary)
                            .lineLimit(1)

                        Spacer()

                        // Quantity badge
                        Text("×\(item.quantity)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.appAccent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.appAccent.opacity(0.1))
                            .cornerRadius(4)

                        // Revenue
                        Text("\(currencySymbol)\(item.revenue.formatted(.number.precision(.fractionLength(0))))")
                            .font(.system(size: 11))
                            .foregroundColor(.textSecondary)
                            .frame(width: 60, alignment: .trailing)
                    }
                    .padding(.vertical, 3)

                    if index < topSellingItems.count - 1 {
                        Divider().background(Color.appDivider)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.appSurface)
        .cornerRadius(16)
    }

    // MARK: - Staff On Duty Card

    private var staffOnDutyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "person.badge.clock.fill")
                    .foregroundColor(Color(hex: "8B5CF6"))
                Text("kpi_staff_on_duty".t)
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                Spacer()
                Text("\(staffOnDuty.count)")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.appAccent)
            }

            if staffOnDuty.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "person.slash")
                        .font(.system(size: 28))
                        .foregroundColor(.textTertiary)
                    Text("kpi_no_staff_on_duty".t)
                        .font(.caption)
                        .foregroundColor(.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            } else {
                ForEach(Array(staffOnDuty.enumerated()), id: \.offset) { index, staff in
                    HStack(spacing: 10) {
                        // Avatar
                        ZStack {
                            Circle()
                                .fill(Color(hex: "8B5CF6").opacity(0.15))
                                .frame(width: 30, height: 30)
                            Text(staffInitials(staff.name))
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(Color(hex: "8B5CF6"))
                        }

                        VStack(alignment: .leading, spacing: 1) {
                            Text(staff.name)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.textPrimary)
                                .lineLimit(1)
                            Text("kpi_clocked_in_at".t + " " + staff.clockIn.formatted(date: .omitted, time: .shortened))
                                .font(.system(size: 10))
                                .foregroundColor(.textTertiary)
                        }

                        Spacer()

                        // Duration
                        let mins = Int(currentTime.timeIntervalSince(staff.clockIn) / 60)
                        let hours = mins / 60
                        let remainMins = mins % 60
                        Text("\(hours)h \(remainMins)m")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.textSecondary)
                    }
                    .padding(.vertical, 2)

                    if index < staffOnDuty.count - 1 {
                        Divider().background(Color.appDivider)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.appSurface)
        .cornerRadius(16)
    }

    // MARK: - Activity Feed

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundColor(.appAccent)
                Text("kpi_recent_activity".t)
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                Spacer()
                Text("\(completedTodayOrders.count) " + "kpi_orders_today_suffix".t)
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            }

            if todayOrders.prefix(10).isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 28))
                        .foregroundColor(.textTertiary)
                    Text("no_activity_yet".t)
                        .font(.subheadline)
                        .foregroundColor(.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 40)
            } else {
                ForEach(Array(todayOrders.prefix(10).enumerated()), id: \.offset) { index, order in
                    HStack(spacing: 12) {
                        // Status icon
                        ZStack {
                            Circle()
                                .fill(statusColor(order.status).opacity(0.15))
                                .frame(width: 32, height: 32)
                            Image(systemName: statusIcon(order.status))
                                .font(.system(size: 13))
                                .foregroundColor(statusColor(order.status))
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("#\(order.orderNumber)")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.textPrimary)

                                // Order type badge
                                Text(orderTypeName(order.orderType))
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(.textSecondary)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.appSurfaceHigh)
                                    .cornerRadius(4)

                                // Status badge
                                Text(order.status.capitalized)
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(statusColor(order.status))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(statusColor(order.status).opacity(0.1))
                                    .cornerRadius(4)
                            }

                            HStack(spacing: 4) {
                                Text(order.createdAt.formatted(date: .omitted, time: .shortened))
                                    .font(.system(size: 10))
                                    .foregroundColor(.textTertiary)
                                if let table = order.tableSession?.table {
                                    Text("• Table \(table.tableNumber)")
                                        .font(.system(size: 10))
                                        .foregroundColor(.textTertiary)
                                }
                                Text("• \(order.items.count) items")
                                    .font(.system(size: 10))
                                    .foregroundColor(.textTertiary)
                            }
                        }

                        Spacer()

                        Text("\(currencySymbol)\(order.total.formatted(.number.precision(.fractionLength(0))))")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.textPrimary)
                    }
                    .padding(.vertical, 6)

                    if index < min(todayOrders.count, 10) - 1 {
                        Divider().background(Color.appDivider)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.appSurface)
        .cornerRadius(16)
    }

    // MARK: - Helpers

    private func staffInitials(_ name: String) -> String {
        let letters = name.split(separator: " ").prefix(2).compactMap { $0.first }
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    private func statusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "preparing": return Color(hex: "F59E0B")
        case "ready": return Color(hex: "3B82F6")
        case "served", "completed": return Color(hex: "10B981")
        case "cancelled": return Color(hex: "EF4444")
        default: return .textSecondary
        }
    }

    private func statusIcon(_ status: String) -> String {
        switch status.lowercased() {
        case "preparing": return "flame.fill"
        case "ready": return "bell.fill"
        case "served", "completed": return "checkmark.circle.fill"
        case "cancelled": return "xmark.circle.fill"
        default: return "bag.fill"
        }
    }

    private func orderTypeName(_ type: String) -> String {
        switch type {
        case "dine_in": return "Dine In"
        case "take_out": return "Take Out"
        case "delivery": return "Delivery"
        default: return type.capitalized
        }
    }

    // MARK: - Charts Subviews

    private var hourlySalesChartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundColor(.appAccent)
                Text(lm.languageCode == "th" ? "แนวโน้มยอดขายรายชั่วโมง" : "Hourly Sales Trend")
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                Spacer()
                Text(lm.languageCode == "th" ? "วันนี้ vs เมื่อวาน" : "Today vs. Yesterday")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            }

            if !hasSalesDataTodayOrYesterday {
                VStack(spacing: 8) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 28))
                        .foregroundColor(.textTertiary)
                    Text("no_activity_yet".t)
                        .font(.caption)
                        .foregroundColor(.textTertiary)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                Chart(chartSalesData) { point in
                    LineMark(
                        x: .value("Hour", String(format: "%02d:00", point.hour)),
                        y: .value("Revenue", point.revenue)
                    )
                    .foregroundStyle(by: .value("Period", point.period))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: point.period.contains("Today") || point.period.contains("วันนี้") ? 3.0 : 1.5,
                                           dash: point.period.contains("Yesterday") || point.period.contains("เมื่อวาน") ? [4, 4] : []))

                    if point.period.contains("Today") || point.period.contains("วันนี้") {
                        AreaMark(
                            x: .value("Hour", String(format: "%02d:00", point.hour)),
                            y: .value("Revenue", point.revenue)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.appAccent.opacity(0.2), Color.appAccent.opacity(0.0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)
                    }
                }
                .chartForegroundStyleScale([
                    (lm.languageCode == "th" ? "วันนี้" : "Today"): Color.appAccent,
                    (lm.languageCode == "th" ? "เมื่อวาน" : "Yesterday"): Color.textSecondary.opacity(0.5)
                ])
                .chartXAxis {
                    AxisMarks(values: .stride(by: 2)) { value in
                        if let str = value.as(String.self) {
                            AxisValueLabel { Text(str) }
                            AxisTick()
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(abbreviatedCurrency(v))
                            }
                        }
                    }
                }
                .frame(height: 200)
            }
        }
        .padding(16)
        .background(Color.appSurface)
        .cornerRadius(16)
    }

    private var categoryBreakdownChartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundColor(Color(hex: "10B981"))
                Text(lm.languageCode == "th" ? "วิเคราะห์ยอดขายตามหมวดหมู่" : "Sales by Category")
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                Spacer()
            }

            if chartCategoryData.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.textTertiary)
                    Text("no_activity_yet".t)
                        .font(.caption)
                        .foregroundColor(.textTertiary)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                Chart(chartCategoryData) { point in
                    BarMark(
                        x: .value("Revenue", point.revenue),
                        y: .value("Category", point.categoryName)
                    )
                    .foregroundStyle(by: .value("Category", point.categoryName))
                    .cornerRadius(4)
                    .annotation(position: .trailing, alignment: .leading) {
                        Text("\(currencySymbol)\(point.revenue.formatted(.number.precision(.fractionLength(0))))")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundColor(.textSecondary)
                            .padding(.leading, 4)
                    }
                }
                .chartForegroundStyleScale([
                    (lm.languageCode == "th" ? "อาหารหลัก" : "Main Dishes"): Color(hex: "3B82F6"),
                    (lm.languageCode == "th" ? "ของทานเล่น" : "Appetizers"): Color(hex: "F59E0B"),
                    (lm.languageCode == "th" ? "เครื่องดื่ม" : "Beverages"): Color(hex: "10B981"),
                    (lm.languageCode == "th" ? "ของหวาน" : "Desserts"): Color(hex: "8B5CF6"),
                    (lm.languageCode == "th" ? "เมนูพิเศษ" : "Specials"): Color(hex: "EC4899")
                ])
                .chartXAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(abbreviatedCurrency(v))
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisValueLabel()
                    }
                }
                .frame(height: 200)
            }
        }
        .padding(16)
        .background(Color.appSurface)
        .cornerRadius(16)
    }

    private func abbreviatedCurrency(_ value: Double) -> String {
        if value >= 1000000 {
            return String(format: "%.1fM", value / 1000000)
        }
        if value >= 1000 {
            return String(format: "%.0fK", value / 1000)
        }
        return String(format: "%.0f", value)
    }
}

// MARK: - KPI Card Component

private struct KPICard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    let trend: String?
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(color)
                Spacer()
                if let trend = trend {
                    Text(trend)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(trend.hasPrefix("+") ? .green : trend.hasPrefix("-") ? .orange : .textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            (trend.hasPrefix("+") ? Color.green : trend.hasPrefix("-") ? Color.orange : Color.gray)
                                .opacity(0.1)
                        )
                        .cornerRadius(4)
                }
            }

            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(title)
                .font(.system(size: 11))
                .foregroundColor(.textSecondary)
                .lineLimit(1)

            Text(subtitle ?? " ")
                .font(.system(size: 9))
                .foregroundColor(subtitle != nil ? .textTertiary : .clear)
                .lineLimit(1)
        }
        .padding(14)
        .background(Color.appSurface)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(color.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Secondary KPI Card

private struct SecondaryKPICard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.appAccent)
                .frame(width: 28, height: 28)
                .background(Color.appAccent.opacity(0.1))
                .cornerRadius(6)

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.textPrimary)
                Text(title)
                    .font(.system(size: 10))
                    .foregroundColor(.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.appSurface)
        .cornerRadius(12)
    }
}

extension LiveDashboardView {
    private var lowStockItems: [InventoryItem] {
        inventoryItems.filter { item in
            !item.isDeleted && item.currentQuantity <= item.safetyStockLevel
        }
    }

    private var lowStockWarningBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .font(.title3)
                Text("เตือนภัยสต็อกต่ำ (Low Stock Alert)")
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                Spacer()
                Text("\(lowStockItems.count) รายการ")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.2))
                    .foregroundColor(.red)
                    .cornerRadius(8)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(lowStockItems.prefix(10)) { item in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.textPrimary)
                                Text("คงเหลือ: \(String(format: "%.1f", item.currentQuantity)) (เกณฑ์: \(String(format: "%.1f", item.safetyStockLevel)))")
                                    .font(.system(size: 11))
                                    .foregroundColor(.textSecondary)
                            }
                            Image(systemName: item.currentQuantity <= 0 ? "xmark.circle.fill" : "exclamationmark.circle.fill")
                                .foregroundColor(item.currentQuantity <= 0 ? .red : .orange)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.appSurfaceHigh)
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(item.currentQuantity <= 0 ? Color.red.opacity(0.3) : Color.orange.opacity(0.3), lineWidth: 1)
                        )
                    }
                }
            }
        }
        .padding()
        .background(Color.red.opacity(0.06))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.red.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Chart Data Models

private struct DashboardHourlySalesPoint: Identifiable {
    let id = UUID()
    let hour: Int
    let revenue: Double
    let period: String
}

private struct DashboardCategorySalesPoint: Identifiable {
    let id = UUID()
    let categoryName: String
    let revenue: Double
}
