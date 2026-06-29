// ShiftScheduleView.swift
// AlphaPosStaff — Weekly Shift Schedule Viewer
//
// Premium dark-themed schedule viewer showing personal shifts,
// team schedule, and next-shift countdown.

import SwiftUI
import Combine

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - Models
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

enum ShiftType: String, Codable, CaseIterable {
    case morning    = "morning"
    case afternoon  = "afternoon"
    case evening    = "evening"
    case night      = "night"
    
    var displayName: String {
        switch self {
        case .morning:   return "morning_shift"
        case .afternoon: return "afternoon_shift"
        case .evening:   return "evening_shift"
        case .night:     return "night_shift"
        }
    }
    
    var icon: String {
        switch self {
        case .morning:   return "sunrise.fill"
        case .afternoon: return "sun.max.fill"
        case .evening:   return "sunset.fill"
        case .night:     return "moon.stars.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .morning:   return Color(hex: "F59E0B") // amber/yellow
        case .afternoon: return Color(hex: "F97316") // orange
        case .evening:   return Color(hex: "3B82F6") // blue
        case .night:     return Color(hex: "8B5CF6") // purple
        }
    }
    
    var gradient: LinearGradient {
        switch self {
        case .morning:
            return LinearGradient(colors: [Color(hex: "F59E0B"), Color(hex: "FBBF24")], startPoint: .leading, endPoint: .trailing)
        case .afternoon:
            return LinearGradient(colors: [Color(hex: "F97316"), Color(hex: "FB923C")], startPoint: .leading, endPoint: .trailing)
        case .evening:
            return LinearGradient(colors: [Color(hex: "3B82F6"), Color(hex: "60A5FA")], startPoint: .leading, endPoint: .trailing)
        case .night:
            return LinearGradient(colors: [Color(hex: "8B5CF6"), Color(hex: "A78BFA")], startPoint: .leading, endPoint: .trailing)
        }
    }
}

struct Shift: Codable, Identifiable, Hashable {
    let id: String
    let employeeId: String
    let employeeName: String
    let date: String           // "2026-06-26"
    let startTime: String      // "09:00"
    let endTime: String        // "17:00"
    let shiftType: ShiftType
    let station: String?       // "Bar", "Kitchen", "Floor"
    let notes: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case employeeId = "employee_id"
        case employeeName = "employee_name"
        case date
        case startTime = "start_time"
        case endTime = "end_time"
        case shiftType = "shift_type"
        case station
        case notes
    }
    
    /// Parse date string to Date
    var dateValue: Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: date)
    }
    
    /// Parse start time to today's Date for countdown
    var startDateTime: Date? {
        guard let baseDate = dateValue else { return nil }
        let parts = startTime.split(separator: ":")
        guard parts.count == 2,
              let h = Int(parts[0]),
              let m = Int(parts[1]) else { return nil }
        return Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: baseDate)
    }
    
    var endDateTime: Date? {
        guard let baseDate = dateValue else { return nil }
        let parts = endTime.split(separator: ":")
        guard parts.count == 2,
              let h = Int(parts[0]),
              let m = Int(parts[1]) else { return nil }
        return Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: baseDate)
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - ShiftScheduleView
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct ShiftScheduleView: View {
    @AppStorage("app_language") private var appLanguage = "en"
    @AppStorage("logged_in_employee_id") private var loggedInEmployeeId = ""
    
    @State private var myShifts: [Shift] = []
    @State private var teamShifts: [Shift] = []
    @State private var isLoading = false
    @State private var selectedWeekOffset = 0  // 0 = this week, 1 = next week
    @State private var currentTime = Date()
    @State private var loadError: String? = nil
    
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    
    // MARK: - Computed
    
    private var weekStartDate: Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: today)
        let daysToMonday = (weekday == 1) ? -6 : (2 - weekday)
        let monday = cal.date(byAdding: .day, value: daysToMonday + (selectedWeekOffset * 7), to: today)!
        return monday
    }
    
    private var weekDays: [Date] {
        (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: weekStartDate) }
    }
    
    private var nextShift: Shift? {
        let now = Date()
        return myShifts
            .filter { shift in
                guard let startDT = shift.startDateTime else { return false }
                return startDT > now
            }
            .sorted { ($0.startDateTime ?? .distantFuture) < ($1.startDateTime ?? .distantFuture) }
            .first
    }
    
    private var countdownText: String {
        guard let next = nextShift, let startDT = next.startDateTime else {
            return "no_shifts".localized(for: appLanguage)
        }
        let interval = startDT.timeIntervalSince(currentTime)
        if interval <= 0 { return "now" }
        
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        
        if hours > 24 {
            let days = hours / 24
            return "\(days)d \(hours % 24)h"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: APSpacing.lg) {
                        // Next Shift Countdown Card
                        nextShiftCard
                        
                        // Week Selector
                        weekSelector
                        
                        // Weekly Calendar
                        weeklyCalendar
                        
                        // My Shifts This Week
                        myShiftsSection
                        
                        // Team Schedule
                        teamScheduleSection
                    }
                    .padding(.horizontal, APSpacing.md)
                    .padding(.bottom, APSpacing.xxl)
                }
                .refreshable {
                    await loadShifts()
                }
            }
            .navigationTitle("schedule".localized(for: appLanguage))
            .apNavBar()
            .onAppear {
                Task { await loadShifts() }
            }
            .alert("load_shifts_failed".localized(for: appLanguage),
                   isPresented: Binding(get: { loadError != nil }, set: { if !$0 { loadError = nil } })) {
                Button("retry".localized(for: appLanguage)) {
                    loadError = nil
                    Task { await loadShifts() }
                }
                Button("ok".localized(for: appLanguage), role: .cancel) { loadError = nil }
            } message: {
                if let err = loadError {
                    Text(err)
                }
            }
            .onReceive(timer) { _ in
                currentTime = Date()
            }
        }
    }
    
    // MARK: - Next Shift Countdown Card
    
    private var nextShiftCard: some View {
        VStack(spacing: APSpacing.sm) {
            if let next = nextShift {
                HStack(spacing: APSpacing.md) {
                    // Left: Shift type icon with color
                    ZStack {
                        Circle()
                            .fill(next.shiftType.color.opacity(0.15))
                            .frame(width: 56, height: 56)
                        Image(systemName: next.shiftType.icon)
                            .font(.title2)
                            .foregroundColor(next.shiftType.color)
                    }
                    
                    // Center: Info
                    VStack(alignment: .leading, spacing: 4) {
                        Text("next_shift".localized(for: appLanguage))
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                        
                        Text(next.shiftType.displayName.localized(for: appLanguage))
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.textPrimary)
                        
                        Text("\(next.startTime) – \(next.endTime)")
                            .font(.subheadline)
                            .foregroundColor(.textSecondary)
                        
                        if let station = next.station, !station.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.caption)
                                Text(station)
                                    .font(.caption)
                            }
                            .foregroundColor(.textTertiary)
                        }
                    }
                    
                    Spacer()
                    
                    // Right: Countdown
                    VStack(spacing: 4) {
                        Text("starts_in".localized(for: appLanguage))
                            .font(.caption2)
                            .foregroundColor(.textTertiary)
                        Text(countdownText)
                            .font(.title2)
                            .fontWeight(.heavy)
                            .foregroundColor(next.shiftType.color)
                            .monospacedDigit()
                    }
                }
                .padding(APSpacing.md)
            } else {
                HStack(spacing: APSpacing.md) {
                    Image(systemName: "calendar.badge.checkmark")
                        .font(.largeTitle)
                        .foregroundColor(.textTertiary)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("no_shifts".localized(for: appLanguage))
                            .font(.headline)
                            .foregroundColor(.textPrimary)
                        Text("schedule".localized(for: appLanguage))
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                    }
                    
                    Spacer()
                }
                .padding(APSpacing.md)
            }
        }
        .apCard()
    }
    
    // MARK: - Week Selector
    
    private var weekSelector: some View {
        HStack {
            Button(action: { withAnimation { selectedWeekOffset -= 1 } }) {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.appAccent)
            }
            
            Spacer()
            
            VStack(spacing: 2) {
                Text(selectedWeekOffset == 0 ? "this_week".localized(for: appLanguage) : weekRangeString)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.textPrimary)
                
                if selectedWeekOffset != 0 {
                    Text(weekRangeString)
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                }
            }
            
            Spacer()
            
            Button(action: { withAnimation { selectedWeekOffset += 1 } }) {
                Image(systemName: "chevron.right")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.appAccent)
            }
        }
        .padding(.horizontal, APSpacing.sm)
        .onChange(of: selectedWeekOffset) { _ in
            Task { await loadShifts() }
        }
    }
    
    private var weekRangeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let start = formatter.string(from: weekStartDate)
        let end = formatter.string(from: weekDays.last ?? weekStartDate)
        return "\(start) – \(end)"
    }
    
    // MARK: - Weekly Calendar (7-day horizontal strip)
    
    private var weeklyCalendar: some View {
        HStack(spacing: 6) {
            ForEach(weekDays, id: \.self) { day in
                let isToday = Calendar.current.isDateInToday(day)
                let dayShifts = shiftsFor(date: day)
                
                VStack(spacing: 6) {
                    // Day name
                    Text(dayAbbreviation(day))
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(isToday ? .white : .textSecondary)
                    
                    // Date number
                    Text("\(Calendar.current.component(.day, from: day))")
                        .font(.subheadline)
                        .fontWeight(isToday ? .bold : .regular)
                        .foregroundColor(isToday ? .white : .textPrimary)
                    
                    // Shift dots
                    HStack(spacing: 2) {
                        ForEach(dayShifts.prefix(3), id: \.id) { shift in
                            Circle()
                                .fill(shift.shiftType.color)
                                .frame(width: 6, height: 6)
                        }
                    }
                    .frame(height: 8)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, APSpacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: APRadius.sm, style: .continuous)
                        .fill(isToday ? Color.appAccent : Color.clear)
                )
            }
        }
        .padding(APSpacing.sm)
        .apCard(padding: APSpacing.sm)
    }
    
    // MARK: - My Shifts Section
    
    private var myShiftsSection: some View {
        VStack(alignment: .leading, spacing: APSpacing.md) {
            HStack {
                Image(systemName: "person.fill")
                    .foregroundColor(.appAccent)
                Text("my_shifts".localized(for: appLanguage))
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.textPrimary)
                
                Spacer()
                
                Text("\(myShifts.count)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.appAccent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.appAccent.opacity(0.15)))
            }
            
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                        .tint(.appAccent)
                    Spacer()
                }
                .padding(.vertical, APSpacing.xl)
            } else if myShifts.isEmpty {
                emptyStateView
            } else {
                ForEach(groupedMyShifts, id: \.0) { (dateStr, shifts) in
                    VStack(alignment: .leading, spacing: APSpacing.sm) {
                        Text(formatDateHeader(dateStr))
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.textSecondary)
                            .padding(.leading, 4)
                        
                        ForEach(shifts) { shift in
                            ShiftRowView(shift: shift, appLanguage: appLanguage)
                        }
                    }
                }
            }
        }
        .apCard()
    }
    
    // MARK: - Team Schedule Section
    
    private var teamScheduleSection: some View {
        VStack(alignment: .leading, spacing: APSpacing.md) {
            HStack {
                Image(systemName: "person.3.fill")
                    .foregroundColor(.appPurple)
                Text("team_schedule".localized(for: appLanguage))
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.textPrimary)
                
                Spacer()
                
                Text("\(teamShifts.count)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.appPurple)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.appPurple.opacity(0.15)))
            }
            
            if teamShifts.isEmpty && !isLoading {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "person.3")
                            .font(.title)
                            .foregroundColor(.textTertiary)
                        Text("no_shifts".localized(for: appLanguage))
                            .font(.subheadline)
                            .foregroundColor(.textSecondary)
                    }
                    Spacer()
                }
                .padding(.vertical, APSpacing.lg)
            } else {
                // Group team shifts by shift type for today
                let todayStr = dateString(from: Date())
                let todayTeamShifts = teamShifts.filter { $0.date == todayStr }
                
                if todayTeamShifts.isEmpty {
                    Text("no_shifts".localized(for: appLanguage))
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)
                        .padding(.vertical, APSpacing.md)
                } else {
                    ForEach(ShiftType.allCases, id: \.rawValue) { type in
                        let typeShifts = todayTeamShifts.filter { $0.shiftType == type }
                        if !typeShifts.isEmpty {
                            VStack(alignment: .leading, spacing: APSpacing.sm) {
                                HStack(spacing: 6) {
                                    Image(systemName: type.icon)
                                        .font(.caption)
                                        .foregroundColor(type.color)
                                    Text(type.displayName.localized(for: appLanguage))
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(type.color)
                                }
                                
                                FlowLayout(spacing: 6) {
                                    ForEach(typeShifts) { shift in
                                        TeamMemberChip(shift: shift)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .apCard()
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: APSpacing.md) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 44))
                .foregroundColor(.textTertiary)
            
            Text("no_shifts".localized(for: appLanguage))
                .font(.headline)
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, APSpacing.xl)
    }
    
    // MARK: - Helpers
    
    private var groupedMyShifts: [(String, [Shift])] {
        Dictionary(grouping: myShifts, by: { $0.date })
            .sorted { $0.key < $1.key }
    }
    
    private func shiftsFor(date: Date) -> [Shift] {
        let str = dateString(from: date)
        return myShifts.filter { $0.date == str }
    }
    
    private func dateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    
    private func dayAbbreviation(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        if appLanguage == "th" { formatter.locale = Locale(identifier: "th_TH") }
        return formatter.string(from: date).prefix(2).uppercased()
    }
    
    private func formatDateHeader(_ dateStr: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateStr) else { return dateStr }
        
        if Calendar.current.isDateInToday(date) {
            return "Today"
        } else if Calendar.current.isDateInTomorrow(date) {
            return "Tomorrow"
        } else {
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "EEEE, MMM d"
            if appLanguage == "th" { displayFormatter.locale = Locale(identifier: "th_TH") }
            return displayFormatter.string(from: date)
        }
    }
    
    // MARK: - Data Loading
    
    private func loadShifts() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let weekDate = weekStartDate
            async let myResult = NetworkService.shared.fetchMyShifts(weekOf: weekDate)
            async let teamResult = NetworkService.shared.fetchTeamShifts(weekOf: weekDate)
            
            let (my, team) = try await (myResult, teamResult)
            
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.3)) {
                    self.myShifts = my
                    self.teamShifts = team
                }
            }
        } catch {
            #if DEBUG
            print("ShiftScheduleView: Failed to load shifts: \(error.localizedDescription)")
            #endif
            loadError = "load_shifts_failed".localized(for: appLanguage) + " — " + error.localizedDescription
        }
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - ShiftRowView
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct ShiftRowView: View {
    let shift: Shift
    let appLanguage: String
    
    var body: some View {
        HStack(spacing: APSpacing.md) {
            // Shift type indicator bar
            RoundedRectangle(cornerRadius: 3)
                .fill(shift.shiftType.gradient)
                .frame(width: 4, height: 48)
            
            // Shift type icon
            ZStack {
                RoundedRectangle(cornerRadius: APRadius.sm, style: .continuous)
                    .fill(shift.shiftType.color.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: shift.shiftType.icon)
                    .font(.body)
                    .foregroundColor(shift.shiftType.color)
            }
            
            // Info
            VStack(alignment: .leading, spacing: 3) {
                Text(shift.shiftType.displayName.localized(for: appLanguage))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.textPrimary)
                
                HStack(spacing: APSpacing.sm) {
                    Label(shift.startTime + " – " + shift.endTime, systemImage: "clock")
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                    
                    if let station = shift.station, !station.isEmpty {
                        Label(station, systemImage: "mappin")
                            .font(.caption)
                            .foregroundColor(.textTertiary)
                    }
                }
            }
            
            Spacer()
            
            // Duration badge
            if let start = shift.startDateTime, let end = shift.endDateTime {
                let hours = end.timeIntervalSince(start) / 3600.0
                Text(String(format: "%.0fh", hours))
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(shift.shiftType.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(shift.shiftType.color.opacity(0.12))
                    )
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, APSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: APRadius.sm, style: .continuous)
                .fill(Color.appSurfaceHigh.opacity(0.5))
        )
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - TeamMemberChip
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct TeamMemberChip: View {
    let shift: Shift
    
    var body: some View {
        HStack(spacing: 6) {
            // Avatar circle
            ZStack {
                Circle()
                    .fill(shift.shiftType.color.opacity(0.2))
                    .frame(width: 24, height: 24)
                Text(String(shift.employeeName.prefix(1)).uppercased())
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(shift.shiftType.color)
            }
            
            Text(shift.employeeName)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.textPrimary)
                .lineLimit(1)
            
            if let station = shift.station, !station.isEmpty {
                Text("• \(station)")
                    .font(.caption2)
                    .foregroundColor(.textTertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.appSurfaceHigh)
                .overlay(
                    Capsule()
                        .stroke(shift.shiftType.color.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - FlowLayout (Horizontal wrapping layout)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, offset) in result.offsets.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + offset.x, y: bounds.minY + offset.y), proposal: .unspecified)
        }
    }
    
    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (offsets: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var offsets: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            
            offsets.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            maxX = max(maxX, currentX)
        }
        
        return (offsets, CGSize(width: maxX, height: currentY + lineHeight))
    }
}
