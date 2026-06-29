// TipTrackerView.swift
// AlphaPosStaff — Tip Tracker Dashboard
//
// Comprehensive tip tracking: daily/weekly/monthly stats,
// breakdown by payment method & time period, goal progress,
// tip pooling share, and full history list.

import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Data Models
// ─────────────────────────────────────────────────────────────────────────────

struct TipRecord: Codable, Identifiable {
    let id: String
    let amount: Double
    let paymentMethod: String    // "cash", "card", "qr"
    let tableNumber: Int?
    let orderId: String?
    let createdAt: Double        // epoch timestamp

    enum CodingKeys: String, CodingKey {
        case id
        case amount
        case paymentMethod = "payment_method"
        case tableNumber = "table_number"
        case orderId = "order_id"
        case createdAt = "created_at"
    }

    var date: Date { Date(timeIntervalSince1970: createdAt) }

    var timePeriod: TipTimePeriod {
        let hour = Calendar.current.component(.hour, from: date)
        if hour < 12 { return .morning }
        else if hour < 17 { return .afternoon }
        else { return .evening }
    }
}

struct TipSummary: Codable {
    let totalTips: Double
    let tipCount: Int
    let avgPerShift: Double
    let poolTotal: Double?
    let poolSharePercent: Double?
    let dailyTotals: [DailyTipTotal]

    struct DailyTipTotal: Codable, Identifiable {
        let date: String            // "2026-06-26"
        let total: Double
        var id: String { date }
    }

    enum CodingKeys: String, CodingKey {
        case totalTips = "total_tips"
        case tipCount = "tip_count"
        case avgPerShift = "avg_per_shift"
        case poolTotal = "pool_total"
        case poolSharePercent = "pool_share_percent"
        case dailyTotals = "daily_totals"
    }
}

enum TipTimePeriod: String, CaseIterable {
    case morning, afternoon, evening

    var icon: String {
        switch self {
        case .morning:   return "sunrise.fill"
        case .afternoon: return "sun.max.fill"
        case .evening:   return "moon.stars.fill"
        }
    }

    var color: Color {
        switch self {
        case .morning:   return .appAmber
        case .afternoon: return Color(hex: "F97316") // orange
        case .evening:   return .appPurple
        }
    }

    func label(for lang: String) -> String {
        switch self {
        case .morning:   return "morning_shift".localized(for: lang)
        case .afternoon: return "afternoon_shift".localized(for: lang)
        case .evening:   return "evening_shift".localized(for: lang)
        }
    }
}

enum TipPaymentMethod: String, CaseIterable {
    case cash, card, qr

    var icon: String {
        switch self {
        case .cash: return "banknote.fill"
        case .card: return "creditcard.fill"
        case .qr:   return "qrcode"
        }
    }

    var color: Color {
        switch self {
        case .cash: return .appTeal
        case .card: return .appAccent
        case .qr:   return .appPurple
        }
    }

    func label(for lang: String) -> String {
        switch self {
        case .cash: return "cash_tips".localized(for: lang)
        case .card: return "card_tips".localized(for: lang)
        case .qr:   return "QR"
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Main View
// ─────────────────────────────────────────────────────────────────────────────

struct TipTrackerView: View {
    let employee: Employee

    @AppStorage("app_language") private var appLanguage = "en"
    @AppStorage("tip_daily_goal") private var tipDailyGoal: Double = 500
    @State private var todayTips: [TipRecord] = []
    @State private var weeklySummary: TipSummary?
    @State private var monthlySummary: TipSummary?
    @State private var isLoading = true
    @State private var animateValue = false
    @State private var showGoalSheet = false
    @State private var goalInput: String = ""
    @State private var selectedTab: TipTab = .today

    enum TipTab: String, CaseIterable {
        case today, weekly, monthly

        func label(for lang: String) -> String {
            switch self {
            case .today:   return "todays_tips".localized(for: lang)
            case .weekly:  return "weekly_tips".localized(for: lang)
            case .monthly: return "monthly_tips".localized(for: lang)
            }
        }

        var icon: String {
            switch self {
            case .today:   return "sun.max.fill"
            case .weekly:  return "calendar.badge.clock"
            case .monthly: return "calendar"
            }
        }
    }

    // MARK: - Computed
    private var todayTotal: Double {
        todayTips.reduce(0) { $0 + $1.amount }
    }
    private var goalProgress: Double {
        guard tipDailyGoal > 0 else { return 0 }
        return min(todayTotal / tipDailyGoal, 1.0)
    }

    // MARK: - Body
    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                if isLoading {
                    loadingView
                } else {
                    mainContent
                }
            }
            .navigationTitle("tip_tracker".localized(for: appLanguage))
            .navigationBarTitleDisplayMode(.large)
            .apColorScheme()
            .task { await loadAllData() }
            .refreshable { await loadAllData() }
            .sheet(isPresented: $showGoalSheet) { goalSettingSheet }
        }
    }

    // MARK: - Loading View
    private var loadingView: some View {
        VStack(spacing: APSpacing.md) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(.appAccent)
            Text("tip_tracker".localized(for: appLanguage))
                .font(.subheadline)
                .foregroundColor(.textSecondary)
        }
    }

    // MARK: - Main Content
    private var mainContent: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: APSpacing.lg) {
                // Goal Progress Ring + Today's Total
                goalRingSection

                // Tab Selector
                tabSelector

                // Content based on selected tab
                switch selectedTab {
                case .today:
                    todaySection
                case .weekly:
                    weeklySection
                case .monthly:
                    monthlySection
                }
            }
            .padding()
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Goal Ring Section
    // ─────────────────────────────────────────────────────────────────────────

    private var goalRingSection: some View {
        VStack(spacing: APSpacing.md) {
            ZStack {
                // Background ring
                Circle()
                    .stroke(Color.appSurfaceHigh, lineWidth: 14)
                    .frame(width: 160, height: 160)

                // Progress ring
                Circle()
                    .trim(from: 0, to: animateValue ? goalProgress : 0)
                    .stroke(
                        AngularGradient(
                            colors: [.appTeal, .appAccent, .appPurple, .appTeal],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 14, lineCap: .round)
                    )
                    .frame(width: 160, height: 160)
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 1.2, dampingFraction: 0.7), value: animateValue)

                // Center content
                VStack(spacing: 4) {
                    Text("฿\(Int(todayTotal))")
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .foregroundColor(.textPrimary)
                        .contentTransition(.numericText())

                    Text("\(Int(goalProgress * 100))%")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.appAccent)

                    Text("tip_goal".localized(for: appLanguage) + ": ฿\(Int(tipDailyGoal))")
                        .font(.caption2)
                        .foregroundColor(.textSecondary)
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    animateValue = true
                }
            }

            // Set Goal button
            Button(action: {
                goalInput = "\(Int(tipDailyGoal))"
                showGoalSheet = true
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "target")
                        .font(.caption)
                    Text("set_goal".localized(for: appLanguage))
                        .font(.caption)
                        .fontWeight(.bold)
                }
                .foregroundColor(.appAccent)
                .padding(.horizontal, APSpacing.md)
                .padding(.vertical, APSpacing.sm)
                .background(
                    Capsule()
                        .fill(Color.appAccent.opacity(0.12))
                        .overlay(
                            Capsule()
                                .stroke(Color.appAccent.opacity(0.3), lineWidth: 1)
                        )
                )
            }
        }
        .padding(.vertical, APSpacing.md)
        .frame(maxWidth: .infinity)
        .apCard()
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Tab Selector
    // ─────────────────────────────────────────────────────────────────────────

    private var tabSelector: some View {
        HStack(spacing: APSpacing.sm) {
            ForEach(TipTab.allCases, id: \.rawValue) { tab in
                Button(action: {
                    withAnimation(.spring(response: 0.3)) {
                        selectedTab = tab
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.caption2)
                        Text(tab.label(for: appLanguage))
                            .font(.caption)
                            .fontWeight(.bold)
                    }
                    .padding(.horizontal, APSpacing.md)
                    .padding(.vertical, APSpacing.sm + 2)
                    .background(
                        Capsule()
                            .fill(selectedTab == tab ? Color.appAccent : Color.appSurface)
                    )
                    .foregroundColor(selectedTab == tab ? .white : .textSecondary)
                }
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Today Section
    // ─────────────────────────────────────────────────────────────────────────

    private var todaySection: some View {
        VStack(spacing: APSpacing.lg) {
            // Breakdown by Payment Method
            breakdownByMethod

            // Breakdown by Time Period
            breakdownByTimePeriod

            // Tip Pool (if applicable)
            if let weekly = weeklySummary, let poolTotal = weekly.poolTotal, poolTotal > 0 {
                tipPoolCard(poolTotal: poolTotal, sharePercent: weekly.poolSharePercent ?? 0)
            }

            // Today's Tip History
            tipHistoryList
        }
    }

    private var breakdownByMethod: some View {
        VStack(alignment: .leading, spacing: APSpacing.md) {
            HStack {
                Image(systemName: "chart.pie.fill")
                    .foregroundColor(.appAccent)
                Text("tip_tracker".localized(for: appLanguage))
                    .font(.headline).fontWeight(.bold)
                    .foregroundColor(.textPrimary)
                Spacer()
            }

            HStack(spacing: APSpacing.sm) {
                ForEach(TipPaymentMethod.allCases, id: \.rawValue) { method in
                    let amount = todayTips
                        .filter { $0.paymentMethod == method.rawValue }
                        .reduce(0) { $0 + $1.amount }
                    methodCard(method: method, amount: amount)
                }
            }
        }
        .padding()
        .apCard(padding: 0)
    }

    private func methodCard(method: TipPaymentMethod, amount: Double) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(method.color.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: method.icon)
                    .font(.body)
                    .foregroundColor(method.color)
            }
            Text("฿\(Int(amount))")
                .font(.subheadline).fontWeight(.black)
                .foregroundColor(.textPrimary)
            Text(method.label(for: appLanguage))
                .font(.caption2)
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, APSpacing.sm)
    }

    private var breakdownByTimePeriod: some View {
        VStack(alignment: .leading, spacing: APSpacing.md) {
            HStack {
                Image(systemName: "clock.fill")
                    .foregroundColor(.appAmber)
                Text("hourly_activity".localized(for: appLanguage))
                    .font(.headline).fontWeight(.bold)
                    .foregroundColor(.textPrimary)
                Spacer()
            }

            ForEach(TipTimePeriod.allCases, id: \.rawValue) { period in
                let amount = todayTips
                    .filter { $0.timePeriod == period }
                    .reduce(0) { $0 + $1.amount }
                let count = todayTips.filter { $0.timePeriod == period }.count

                HStack(spacing: APSpacing.md) {
                    ZStack {
                        RoundedRectangle(cornerRadius: APRadius.sm, style: .continuous)
                            .fill(period.color.opacity(0.15))
                            .frame(width: 36, height: 36)
                        Image(systemName: period.icon)
                            .font(.subheadline)
                            .foregroundColor(period.color)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(period.label(for: appLanguage))
                            .font(.subheadline).fontWeight(.semibold)
                            .foregroundColor(.textPrimary)
                        Text("\(count) tips")
                            .font(.caption2)
                            .foregroundColor(.textSecondary)
                    }

                    Spacer()

                    Text("฿\(Int(amount))")
                        .font(.subheadline).fontWeight(.black)
                        .foregroundColor(period.color)
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .apCard(padding: 0)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Weekly Section
    // ─────────────────────────────────────────────────────────────────────────

    private var weeklySection: some View {
        VStack(spacing: APSpacing.lg) {
            // Weekly bar chart
            weeklyBarChart

            // Weekly stats
            if let summary = weeklySummary {
                weeklyStatsCard(summary)
            }
        }
    }

    private var weeklyBarChart: some View {
        VStack(alignment: .leading, spacing: APSpacing.md) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundColor(.appAccent)
                Text("weekly_tips".localized(for: appLanguage))
                    .font(.headline).fontWeight(.bold)
                    .foregroundColor(.textPrimary)
                Spacer()
            }

            let dailyTotals = weeklySummary?.dailyTotals ?? []
            let maxVal = dailyTotals.map(\.total).max() ?? 1

            HStack(alignment: .bottom, spacing: APSpacing.sm) {
                ForEach(Array(dailyTotals.enumerated()), id: \.offset) { index, day in
                    VStack(spacing: 4) {
                        Text("฿\(Int(day.total))")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundColor(.textSecondary)

                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(
                                isToday(dateString: day.date)
                                    ? LinearGradient(colors: [.appAccent, .appPurple], startPoint: .bottom, endPoint: .top)
                                    : LinearGradient(colors: [Color.appAccent.opacity(0.4), Color.appAccent.opacity(0.2)], startPoint: .bottom, endPoint: .top)
                            )
                            .frame(height: max(8, CGFloat(day.total / maxVal) * 100))

                        Text(dayAbbreviation(from: day.date))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(isToday(dateString: day.date) ? .appAccent : .textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 130)
            .padding(.top, APSpacing.sm)
        }
        .padding()
        .apCard(padding: 0)
    }

    private func weeklyStatsCard(_ summary: TipSummary) -> some View {
        HStack(spacing: APSpacing.md) {
            statPill(
                icon: "sum",
                label: "weekly_tips".localized(for: appLanguage),
                value: "฿\(Int(summary.totalTips))",
                color: .appTeal
            )
            statPill(
                icon: "divide",
                label: "avg_per_shift".localized(for: appLanguage),
                value: "฿\(Int(summary.avgPerShift))",
                color: .appPurple
            )
        }
    }

    private func statPill(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundColor(color)
            }
            Text(value)
                .font(.title3).fontWeight(.black)
                .foregroundColor(.textPrimary)
            Text(label)
                .font(.caption2)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .apCard()
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Monthly Section
    // ─────────────────────────────────────────────────────────────────────────

    private var monthlySection: some View {
        VStack(spacing: APSpacing.lg) {
            if let summary = monthlySummary {
                // Big monthly total
                VStack(spacing: APSpacing.sm) {
                    Text("monthly_tips".localized(for: appLanguage))
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)
                    Text("฿\(Int(summary.totalTips))")
                        .font(.system(size: 42, weight: .black, design: .rounded))
                        .foregroundColor(.textPrimary)

                    HStack(spacing: APSpacing.lg) {
                        VStack(spacing: 2) {
                            Text("\(summary.tipCount)")
                                .font(.title3).fontWeight(.bold)
                                .foregroundColor(.appAccent)
                            Text("Tips")
                                .font(.caption2).foregroundColor(.textSecondary)
                        }
                        Rectangle()
                            .fill(Color.appDivider)
                            .frame(width: 1, height: 30)
                        VStack(spacing: 2) {
                            Text("฿\(Int(summary.avgPerShift))")
                                .font(.title3).fontWeight(.bold)
                                .foregroundColor(.appTeal)
                            Text("avg_per_shift".localized(for: appLanguage))
                                .font(.caption2).foregroundColor(.textSecondary)
                        }
                    }
                    .padding(.top, APSpacing.sm)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .apCard()

                // Monthly pool info
                if let poolTotal = summary.poolTotal, poolTotal > 0 {
                    tipPoolCard(poolTotal: poolTotal, sharePercent: summary.poolSharePercent ?? 0)
                }
            } else {
                VStack(spacing: APSpacing.md) {
                    Image(systemName: "chart.line.downtrend.xyaxis")
                        .font(.largeTitle)
                        .foregroundColor(.textTertiary)
                    Text("No monthly data yet")
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, APSpacing.xxl)
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Tip Pool Card
    // ─────────────────────────────────────────────────────────────────────────

    private func tipPoolCard(poolTotal: Double, sharePercent: Double) -> some View {
        VStack(alignment: .leading, spacing: APSpacing.md) {
            HStack {
                Image(systemName: "person.3.fill")
                    .foregroundColor(.appPurple)
                Text("tip_pool".localized(for: appLanguage))
                    .font(.headline).fontWeight(.bold)
                    .foregroundColor(.textPrimary)
                Spacer()
            }

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pool Total")
                        .font(.caption2).foregroundColor(.textSecondary)
                    Text("฿\(Int(poolTotal))")
                        .font(.title2).fontWeight(.black)
                        .foregroundColor(.textPrimary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("your_share".localized(for: appLanguage))
                        .font(.caption2).foregroundColor(.textSecondary)
                    HStack(spacing: 4) {
                        Text("฿\(Int(poolTotal * sharePercent / 100))")
                            .font(.title2).fontWeight(.black)
                            .foregroundColor(.appPurple)
                        Text("(\(Int(sharePercent))%)")
                            .font(.caption)
                            .foregroundColor(.textTertiary)
                    }
                }
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.appSurfaceHigh)
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [.appPurple, .appAccent],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * sharePercent / 100, height: 8)
                }
            }
            .frame(height: 8)
        }
        .padding()
        .apCard(padding: 0)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Tip History List
    // ─────────────────────────────────────────────────────────────────────────

    private var tipHistoryList: some View {
        VStack(alignment: .leading, spacing: APSpacing.md) {
            HStack {
                Image(systemName: "list.bullet.rectangle.fill")
                    .foregroundColor(.appTeal)
                Text("tip_history".localized(for: appLanguage))
                    .font(.headline).fontWeight(.bold)
                    .foregroundColor(.textPrimary)
                Spacer()
                Text("\(todayTips.count)")
                    .font(.caption).fontWeight(.bold)
                    .foregroundColor(.appAccent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(Color.appAccent.opacity(0.12))
                    )
            }

            if todayTips.isEmpty {
                VStack(spacing: APSpacing.sm) {
                    Image(systemName: "tray")
                        .font(.title)
                        .foregroundColor(.textTertiary)
                    Text("No tips yet today")
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, APSpacing.xl)
            } else {
                ForEach(todayTips.sorted(by: { $0.createdAt > $1.createdAt }).prefix(20)) { tip in
                    tipRow(tip)
                }
            }
        }
        .padding()
        .apCard(padding: 0)
    }

    private func tipRow(_ tip: TipRecord) -> some View {
        HStack(spacing: APSpacing.md) {
            // Method icon
            let method = TipPaymentMethod(rawValue: tip.paymentMethod) ?? .cash
            ZStack {
                RoundedRectangle(cornerRadius: APRadius.sm, style: .continuous)
                    .fill(method.color.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: method.icon)
                    .font(.subheadline)
                    .foregroundColor(method.color)
            }

            // Details
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(method.label(for: appLanguage))
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(.textPrimary)
                    if let table = tip.tableNumber {
                        Text("• T\(table)")
                            .font(.caption)
                            .foregroundColor(.textTertiary)
                    }
                }
                Text(formatTime(tip.date))
                    .font(.caption2)
                    .foregroundColor(.textSecondary)
            }

            Spacer()

            // Amount
            Text("+฿\(Int(tip.amount))")
                .font(.subheadline).fontWeight(.black)
                .foregroundColor(.appTeal)
        }
        .padding(.vertical, 6)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Goal Setting Sheet
    // ─────────────────────────────────────────────────────────────────────────

    private var goalSettingSheet: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                VStack(spacing: APSpacing.xl) {
                    Spacer()

                    Image(systemName: "target")
                        .font(.system(size: 48))
                        .foregroundColor(.appAccent)

                    Text("set_goal".localized(for: appLanguage))
                        .font(.title2).fontWeight(.black)
                        .foregroundColor(.textPrimary)

                    Text("tip_goal".localized(for: appLanguage))
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)

                    HStack(spacing: 4) {
                        Text("฿")
                            .font(.title).fontWeight(.bold)
                            .foregroundColor(.textSecondary)
                        TextField("500", text: $goalInput)
                            .font(.system(size: 40, weight: .black, design: .rounded))
                            .foregroundColor(.textPrimary)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.center)
                            .frame(width: 160)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: APRadius.md, style: .continuous)
                            .fill(Color.appSurface)
                            .overlay(
                                RoundedRectangle(cornerRadius: APRadius.md, style: .continuous)
                                    .stroke(Color.appAccent.opacity(0.3), lineWidth: 1.5)
                            )
                    )

                    // Quick presets
                    HStack(spacing: APSpacing.md) {
                        ForEach([300, 500, 1000, 2000], id: \.self) { preset in
                            Button(action: {
                                goalInput = "\(preset)"
                            }) {
                                Text("฿\(preset)")
                                    .font(.caption).fontWeight(.bold)
                                    .foregroundColor(goalInput == "\(preset)" ? .white : .appAccent)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule()
                                            .fill(goalInput == "\(preset)" ? Color.appAccent : Color.appAccent.opacity(0.1))
                                    )
                            }
                        }
                    }

                    Spacer()

                    Button(action: {
                        if let val = Double(goalInput), val > 0 {
                            tipDailyGoal = val
                            animateValue = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                animateValue = true
                            }
                        }
                        showGoalSheet = false
                    }) {
                        Text("confirm_split".localized(for: appLanguage))
                            .apGradientButton()
                    }
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showGoalSheet = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.textTertiary)
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Helpers
    // ─────────────────────────────────────────────────────────────────────────

    private func formatTime(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt.string(from: date)
    }

    private func isToday(dateString: String) -> Bool {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return dateString == fmt.string(from: Date())
    }

    private func dayAbbreviation(from dateString: String) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        guard let date = fmt.date(from: dateString) else { return "?" }
        let abbr = DateFormatter()
        abbr.dateFormat = "EEE"
        return String(abbr.string(from: date).prefix(2))
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Data Loading
    // ─────────────────────────────────────────────────────────────────────────

    private func loadAllData() async {
        isLoading = true
        do {
            let today = Date()
            let calendar = Calendar.current

            // Today's tips
            let startOfDay = calendar.startOfDay(for: today)
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
            todayTips = try await NetworkService.shared.fetchTips(from: startOfDay, to: endOfDay)

            // Weekly summary
            let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today))!
            weeklySummary = try await NetworkService.shared.fetchTipSummary(period: "weekly")

            // Monthly summary
            monthlySummary = try await NetworkService.shared.fetchTipSummary(period: "monthly")
        } catch {
            print("TipTracker load error: \(error)")
            // Generate from local orders if offline
            generateLocalSummary()
        }

        await MainActor.run {
            isLoading = false
        }
    }

    private func generateLocalSummary() {
        // Fallback: use cached order data to estimate tips
        // When offline and no tip data is available, show empty state.
        // Tips are server-side data; we can't reliably derive them from
        // cached orders since Order model doesn't store tip amounts locally.
        todayTips = []
        
        // Set default summaries for graceful degradation
        weeklySummary = TipSummary(
            totalTips: 0, tipCount: 0, avgPerShift: 0,
            poolTotal: nil, poolSharePercent: nil, dailyTotals: []
        )
        monthlySummary = nil
    }
}
