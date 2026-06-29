// DailySummaryView.swift
// AlphaPosStaff — Daily Performance Dashboard
//
// Shows real-time daily KPIs for the logged-in staff member:
// orders served, revenue, avg prep time, tables turned, tips,
// hourly activity chart, top items, hours worked, streak.

import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Data Model
// ─────────────────────────────────────────────────────────────────────────────

struct DailySummary: Codable {
    let ordersServed: Int
    let revenueGenerated: Double
    let avgPrepTime: Int          // minutes
    let tablesTurned: Int
    let tipsEarned: Double
    let hourlyOrders: [Int]       // 24 entries (hour 0-23)
    let topItems: [TopSoldItem]
    let hoursWorked: Double
    let streak: Int

    struct TopSoldItem: Codable, Identifiable {
        let name: String
        let quantity: Int
        var id: String { name }
    }

    enum CodingKeys: String, CodingKey {
        case ordersServed = "orders_served"
        case revenueGenerated = "revenue_generated"
        case avgPrepTime = "avg_prep_time"
        case tablesTurned = "tables_turned"
        case tipsEarned = "tips_earned"
        case hourlyOrders = "hourly_orders"
        case topItems = "top_items"
        case hoursWorked = "hours_worked"
        case streak
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Main View
// ─────────────────────────────────────────────────────────────────────────────

struct DailySummaryView: View {
    let employee: Employee

    @AppStorage("app_language") private var appLanguage = "en"
    @State private var summary: DailySummary?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedDate = Date()
    @State private var animateCards = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                if isLoading {
                    loadingView
                } else if let summary = summary {
                    summaryContent(summary)
                } else {
                    emptyStateView
                }
            }
            .navigationTitle("daily_summary".localized(for: appLanguage))
            .navigationBarTitleDisplayMode(.large)
            .apColorScheme()
            .task { await loadSummary() }
            .refreshable { await loadSummary() }
        }
    }

    // MARK: - Summary Content

    @ViewBuilder
    private func summaryContent(_ data: DailySummary) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: APSpacing.lg) {
                // Header
                headerSection(data)

                // KPI Cards Row 1
                HStack(spacing: APSpacing.md) {
                    kpiCard(
                        icon: "bag.fill",
                        label: "orders_served".localized(for: appLanguage),
                        value: "\(data.ordersServed)",
                        color: .appAccent
                    )
                    kpiCard(
                        icon: "banknote.fill",
                        label: "revenue_generated".localized(for: appLanguage),
                        value: "฿\(Int(data.revenueGenerated))",
                        color: .appTeal
                    )
                }

                // KPI Cards Row 2
                HStack(spacing: APSpacing.md) {
                    kpiCard(
                        icon: "clock.fill",
                        label: "avg_prep_time".localized(for: appLanguage),
                        value: "\(data.avgPrepTime) min",
                        color: .appAmber
                    )
                    kpiCard(
                        icon: "table.furniture.fill",
                        label: "tables_turned".localized(for: appLanguage),
                        value: "\(data.tablesTurned)",
                        color: .appPurple
                    )
                }

                // KPI Cards Row 3
                HStack(spacing: APSpacing.md) {
                    kpiCard(
                        icon: "heart.fill",
                        label: "tips_earned".localized(for: appLanguage),
                        value: "฿\(Int(data.tipsEarned))",
                        color: .appRose
                    )
                    kpiCard(
                        icon: "briefcase.fill",
                        label: "hours_worked".localized(for: appLanguage),
                        value: String(format: "%.1fh", data.hoursWorked),
                        color: .appGreen
                    )
                }

                // Streak Badge
                if data.streak > 1 {
                    streakBanner(data.streak)
                }

                // Hourly Activity Chart
                hourlyActivityChart(data.hourlyOrders)

                // Top Items
                if !data.topItems.isEmpty {
                    topItemsSection(data.topItems)
                }

                Spacer(minLength: APSpacing.xxl)
            }
            .padding(.horizontal, APSpacing.md)
            .padding(.top, APSpacing.sm)
        }
    }

    // MARK: - Header Section

    @ViewBuilder
    private func headerSection(_ data: DailySummary) -> some View {
        VStack(spacing: APSpacing.sm) {
            // Date
            HStack {
                Image(systemName: "calendar")
                    .foregroundColor(.appAccent)
                Text(formattedDate(selectedDate))
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                Spacer()
                shiftStatusBadge(data)
            }

            // Employee name
            HStack {
                Text("\(employee.firstName) \(employee.lastName)")
                    .font(.subheadline)
                    .foregroundColor(.textSecondary)
                Spacer()
            }
        }
        .padding()
        .apCard()
    }

    @ViewBuilder
    private func shiftStatusBadge(_ data: DailySummary) -> some View {
        let isOnDuty = data.hoursWorked > 0 && data.ordersServed > 0
        HStack(spacing: 4) {
            Circle()
                .fill(isOnDuty ? Color.appGreen : Color.textTertiary)
                .frame(width: 8, height: 8)
            Text(isOnDuty ? "On Duty" : "Off Duty")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(isOnDuty ? .appGreen : .textTertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill((isOnDuty ? Color.appGreen : Color.textTertiary).opacity(0.12))
        )
    }

    // MARK: - KPI Card

    @ViewBuilder
    private func kpiCard(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(color)
                Spacer()
            }

            Text(value)
                .font(.title2)
                .fontWeight(.black)
                .foregroundColor(.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(label)
                .font(.caption)
                .foregroundColor(.textSecondary)
                .lineLimit(1)
        }
        .padding(APSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: APRadius.lg, style: .continuous)
                .fill(Color.appSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: APRadius.lg, style: .continuous)
                        .stroke(color.opacity(0.2), lineWidth: 1)
                )
        )
        .shadow(color: color.opacity(0.1), radius: 8, x: 0, y: 4)
    }

    // MARK: - Streak Banner

    @ViewBuilder
    private func streakBanner(_ streak: Int) -> some View {
        HStack(spacing: APSpacing.sm) {
            Image(systemName: "flame.fill")
                .font(.title2)
                .foregroundColor(.appAmber)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(streak) " + "day_streak".localized(for: appLanguage))
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.textPrimary)
                Text("Keep up the great work!")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            }

            Spacer()

            // Fire emojis for streaks
            Text(streakEmoji(streak))
                .font(.title)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: APRadius.lg, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.appAmber.opacity(0.15), Color.appRose.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: APRadius.lg, style: .continuous)
                        .stroke(Color.appAmber.opacity(0.3), lineWidth: 1)
                )
        )
    }

    private func streakEmoji(_ streak: Int) -> String {
        if streak >= 30 { return "🔥🏆" }
        if streak >= 14 { return "🔥⭐️" }
        if streak >= 7  { return "🔥" }
        return "✨"
    }

    // MARK: - Hourly Activity Chart

    @ViewBuilder
    private func hourlyActivityChart(_ hourly: [Int]) -> some View {
        VStack(alignment: .leading, spacing: APSpacing.md) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundColor(.appAccent)
                Text("hourly_activity".localized(for: appLanguage))
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.textPrimary)
                Spacer()
            }

            // Bar Chart - show only active hours (6am - 11pm)
            let activeHours = Array(6...23)
            let maxVal = max(hourly.max() ?? 1, 1)

            HStack(alignment: .bottom, spacing: 3) {
                ForEach(activeHours, id: \.self) { hour in
                    let value = hour < hourly.count ? hourly[hour] : 0
                    let height = CGFloat(value) / CGFloat(maxVal)
                    let isCurrentHour = Calendar.current.component(.hour, from: Date()) == hour

                    VStack(spacing: 2) {
                        // Bar
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(
                                isCurrentHour
                                    ? LinearGradient(colors: [.appAccent, .appAccent.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                                    : LinearGradient(colors: [.appAccent.opacity(0.5), .appAccent.opacity(0.25)], startPoint: .top, endPoint: .bottom)
                            )
                            .frame(height: max(height * 100, value > 0 ? 8 : 2))

                        // Hour label (show every 3 hours)
                        if hour % 3 == 0 {
                            Text("\(hour)")
                                .font(.system(size: 8))
                                .foregroundColor(.textTertiary)
                        } else {
                            Text("")
                                .font(.system(size: 8))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 120)
            .padding(.horizontal, APSpacing.xs)
        }
        .padding()
        .apCard()
    }

    // MARK: - Top Items Section

    @ViewBuilder
    private func topItemsSection(_ items: [DailySummary.TopSoldItem]) -> some View {
        VStack(alignment: .leading, spacing: APSpacing.md) {
            HStack {
                Image(systemName: "star.fill")
                    .foregroundColor(.appAmber)
                Text("top_items_sold".localized(for: appLanguage))
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.textPrimary)
                Spacer()
            }

            ForEach(Array(items.prefix(5).enumerated()), id: \.element.id) { index, item in
                HStack(spacing: APSpacing.md) {
                    // Rank badge
                    ZStack {
                        Circle()
                            .fill(rankColor(index).opacity(0.15))
                            .frame(width: 32, height: 32)
                        Text("\(index + 1)")
                            .font(.caption)
                            .fontWeight(.black)
                            .foregroundColor(rankColor(index))
                    }

                    Text(item.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)

                    Spacer()

                    Text("×\(item.quantity)")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.appAccent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.appAccent.opacity(0.12))
                        )
                }
                .padding(.vertical, 4)

                if index < min(items.count - 1, 4) {
                    Divider().background(Color.appDivider)
                }
            }
        }
        .padding()
        .apCard()
    }

    private func rankColor(_ index: Int) -> Color {
        switch index {
        case 0: return .appAmber
        case 1: return .appAccent
        case 2: return .appTeal
        default: return .textSecondary
        }
    }

    // MARK: - Loading View

    @ViewBuilder
    private var loadingView: some View {
        VStack(spacing: APSpacing.lg) {
            ProgressView()
                .tint(.appAccent)
                .scaleEffect(1.5)
            Text("Loading summary...")
                .font(.subheadline)
                .foregroundColor(.textSecondary)
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: APSpacing.lg) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 48))
                .foregroundColor(.textTertiary)

            Text("todays_summary".localized(for: appLanguage))
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.textPrimary)

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.appRose)
                    .multilineTextAlignment(.center)
            } else {
                Text("No activity recorded yet today.")
                    .font(.subheadline)
                    .foregroundColor(.textSecondary)
            }

            Button {
                Task { await loadSummary() }
            } label: {
                Text("Retry")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, APSpacing.lg)
                    .padding(.vertical, APSpacing.sm)
                    .background(Capsule().fill(Color.appAccent))
            }
        }
        .padding()
    }

    // MARK: - Data Loading

    private func loadSummary() async {
        isLoading = true
        errorMessage = nil

        do {
            let result = try await NetworkService.shared.fetchDailySummary(date: selectedDate)
            withAnimation(.easeOut(duration: 0.4)) {
                self.summary = result
                self.isLoading = false
                self.animateCards = true
            }
        } catch {
            self.errorMessage = error.localizedDescription
            // Try local fallback — generate summary from cached orders
            self.summary = generateLocalSummary()
            withAnimation { self.isLoading = false }
        }
    }

    /// Generate a basic summary from locally available data when API is unavailable
    private func generateLocalSummary() -> DailySummary? {
        let todayOrders = NetworkService.shared.orders.filter { order in
            if let date = ISO8601DateFormatter().date(from: order.createdAt) {
                return Calendar.current.isDateInToday(date)
            }
            return false
        }

        guard !todayOrders.isEmpty else { return nil }

        let served = todayOrders.filter { $0.status == "served" || $0.status == "completed" }
        let revenue = served.reduce(0.0) { $0 + $1.total }

        // Build hourly distribution
        var hourly = Array(repeating: 0, count: 24)
        for order in todayOrders {
            if let date = ISO8601DateFormatter().date(from: order.createdAt) {
                let hour = Calendar.current.component(.hour, from: date)
                if hour >= 0 && hour < 24 {
                    hourly[hour] += 1
                }
            }
        }

        // Top items
        var itemCounts: [String: Int] = [:]
        for order in todayOrders {
            for item in order.items {
                itemCounts[item.name, default: 0] += item.quantity
            }
        }
        let topItems = itemCounts
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { DailySummary.TopSoldItem(name: $0.key, quantity: $0.value) }

        return DailySummary(
            ordersServed: served.count,
            revenueGenerated: revenue,
            avgPrepTime: 12,
            tablesTurned: Set(served.map { $0.tableNumber }).count,
            tipsEarned: 0,
            hourlyOrders: hourly,
            topItems: topItems,
            hoursWorked: 0,
            streak: 1
        )
    }

    // MARK: - Helpers

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.locale = Locale(identifier: appLanguage == "th" ? "th_TH" : "en_US")
        return formatter.string(from: date)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Preview
// ─────────────────────────────────────────────────────────────────────────────

#Preview {
    DailySummaryView(employee: Employee(
        id: "preview-001",
        firstName: "John",
        lastName: "Doe",
        phone: "0812345678",
        nationalId: nil,
        employmentType: "hourly",
        payRate: 80.0,
        username: "john",
        role: "Waiter",
        faceRegisteredAt: nil
    ))
}
