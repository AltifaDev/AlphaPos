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

    var durationHours: Double {
        guard let start = startDateTime, var end = endDateTime else { return 0 }
        if end <= start { end = Calendar.current.date(byAdding: .day, value: 1, to: end) ?? end }
        return end.timeIntervalSince(start) / 3600
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
    @State private var selectedDayIndex = 0
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

    private var selectedDate: Date { weekDays[selectedDayIndex] }

    private var selectedMyShifts: [Shift] {
        shiftsFor(date: selectedDate).sorted { $0.startTime < $1.startTime }
    }

    private var selectedTeamShifts: [Shift] {
        let date = dateString(from: selectedDate)
        return teamShifts.filter { $0.date == date }.sorted { $0.startTime < $1.startTime }
    }

    private var scheduledHours: Double {
        myShifts.reduce(0) { $0 + $1.durationHours }
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
                    LazyVStack(spacing: APSpacing.md) {
                        weekSelector
                        weekOverview
                        weeklyCalendar
                        myShiftsSection
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
                selectDefaultDay()
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
    
    // MARK: - Week overview

    private var weekOverview: some View {
        VStack(spacing: APSpacing.md) {
            HStack(spacing: 0) {
                summaryMetric(value: "\(myShifts.count)", label: "scheduled_shifts", icon: "calendar")
                Divider().frame(height: 42)
                summaryMetric(value: formattedHours(scheduledHours), label: "scheduled_hours", icon: "clock")
                Divider().frame(height: 42)
                summaryMetric(value: "\(Set(myShifts.map(\.date)).count)", label: "work_days", icon: "briefcase")
            }

            Divider().background(Color.appDivider)

            if let next = nextShift {
                HStack(spacing: APSpacing.md) {
                    Image(systemName: next.shiftType.icon)
                        .font(.title3)
                        .foregroundColor(next.shiftType.color)
                        .frame(width: 44, height: 44)
                        .background(next.shiftType.color.opacity(0.12), in: RoundedRectangle(cornerRadius: APRadius.sm))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("next_shift".localized(for: appLanguage))
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                        Text("\(formatCompactDate(next.date))  •  \(next.startTime)–\(next.endTime)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.textPrimary)
                        if let station = next.station, !station.isEmpty {
                            Label(station, systemImage: "mappin.and.ellipse")
                                .font(.caption)
                                .foregroundColor(.textSecondary)
                        }
                    }

                    Spacer(minLength: APSpacing.sm)

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("starts_in".localized(for: appLanguage))
                            .font(.caption2)
                            .foregroundColor(.textTertiary)
                        Text(countdownText)
                            .font(.headline.weight(.bold))
                            .foregroundColor(next.shiftType.color)
                            .monospacedDigit()
                    }
                }
            } else {
                Label("no_shifts".localized(for: appLanguage), systemImage: "calendar.badge.checkmark")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .apCard()
    }

    private func summaryMetric(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Label(value, systemImage: icon)
                .font(.headline.weight(.bold))
                .foregroundColor(.textPrimary)
                .labelStyle(.titleAndIcon)
            Text(label.localized(for: appLanguage))
                .font(.caption2)
                .foregroundColor(.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
    
    // MARK: - Week Selector
    
    private var weekSelector: some View {
        HStack(spacing: APSpacing.sm) {
            Button(action: { changeWeek(by: -1) }) {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 44)
                    .background(Color.appSurface, in: Circle())
            }

            Spacer()

            VStack(spacing: 2) {
                Text(selectedWeekOffset == 0 ? "this_week".localized(for: appLanguage) : "schedule".localized(for: appLanguage))
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.textPrimary)
                Text(weekRangeString)
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            }

            Spacer()

            Button(action: { changeWeek(by: 1) }) {
                Image(systemName: "chevron.right")
                    .frame(width: 44, height: 44)
                    .background(Color.appSurface, in: Circle())
            }
        }
        .font(.body.weight(.semibold))
        .foregroundColor(.appAccent)
        .accessibilityElement(children: .contain)
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
            ForEach(Array(weekDays.enumerated()), id: \.element) { index, day in
                let isToday = Calendar.current.isDateInToday(day)
                let isSelected = selectedDayIndex == index
                let dayShifts = shiftsFor(date: day)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedDayIndex = index }
                } label: {
                    VStack(spacing: 6) {
                        Text(dayAbbreviation(day))
                            .font(.caption2.weight(.semibold))

                        Text("\(Calendar.current.component(.day, from: day))")
                            .font(.body.weight(isSelected ? .bold : .medium))

                        HStack(spacing: 2) {
                            ForEach(dayShifts.prefix(2), id: \.id) { shift in
                                Circle()
                                    .fill(isSelected ? Color.white : shift.shiftType.color)
                                    .frame(width: 5, height: 5)
                            }
                        }
                        .frame(height: 6)
                    }
                    .foregroundColor(isSelected ? .white : .textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 68)
                    .background(isSelected ? Color.appAccent : Color.clear, in: RoundedRectangle(cornerRadius: APRadius.sm))
                    .overlay {
                        if isToday && !isSelected {
                            RoundedRectangle(cornerRadius: APRadius.sm)
                                .stroke(Color.appAccent, lineWidth: 1.5)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(formatDateHeader(dateString(from: day))), \(dayShifts.count) \("scheduled_shifts".localized(for: appLanguage))")
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
                VStack(alignment: .leading, spacing: 2) {
                    Text("my_shifts".localized(for: appLanguage))
                        .font(.headline.weight(.bold))
                        .foregroundColor(.textPrimary)
                    Text(formatDateHeader(dateString(from: selectedDate)))
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                }
                
                Spacer()
                
                Text("\(selectedMyShifts.count)")
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
            } else if selectedMyShifts.isEmpty {
                emptyStateView
            } else {
                ForEach(selectedMyShifts) { shift in
                    ShiftRowView(shift: shift, appLanguage: appLanguage, now: currentTime)
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
                
                Text("\(selectedTeamShifts.count)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.appPurple)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.appPurple.opacity(0.15)))
            }
            
            if selectedTeamShifts.isEmpty && !isLoading {
                HStack {
                    Spacer()
                    Label("no_team_shifts_day".localized(for: appLanguage), systemImage: "person.3")
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)
                    Spacer()
                }
                .padding(.vertical, APSpacing.sm)
            } else {
                ForEach(ShiftType.allCases, id: \.rawValue) { type in
                    let typeShifts = selectedTeamShifts.filter { $0.shiftType == type }
                    if !typeShifts.isEmpty {
                        VStack(alignment: .leading, spacing: APSpacing.sm) {
                            Label(type.displayName.localized(for: appLanguage), systemImage: type.icon)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(type.color)

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
        .apCard()
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        HStack(spacing: APSpacing.md) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.title2)
                .foregroundColor(.appTeal)

            VStack(alignment: .leading, spacing: 3) {
                Text("no_shift_day".localized(for: appLanguage))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.textPrimary)
                Text("no_shift_day_hint".localized(for: appLanguage))
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            }

            Spacer()
        }
        .padding(APSpacing.md)
        .background(Color.appSurfaceHigh.opacity(0.45), in: RoundedRectangle(cornerRadius: APRadius.sm))
    }
    
    // MARK: - Helpers
    
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
            return "today".localized(for: appLanguage)
        } else if Calendar.current.isDateInTomorrow(date) {
            return "tomorrow".localized(for: appLanguage)
        } else {
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "EEEE, MMM d"
            if appLanguage == "th" { displayFormatter.locale = Locale(identifier: "th_TH") }
            return displayFormatter.string(from: date)
        }
    }

    private func formatCompactDate(_ dateStr: String) -> String {
        let input = DateFormatter()
        input.dateFormat = "yyyy-MM-dd"
        guard let date = input.date(from: dateStr) else { return dateStr }
        let output = DateFormatter()
        output.locale = Locale(identifier: appLanguage == "th" ? "th_TH" : appLanguage == "lo" ? "lo_LA" : "en_US")
        output.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return output.string(from: date)
    }

    private func formattedHours(_ hours: Double) -> String {
        hours.rounded() == hours ? String(format: "%.0fh", hours) : String(format: "%.1fh", hours)
    }

    private func selectDefaultDay() {
        guard selectedWeekOffset == 0 else { selectedDayIndex = 0; return }
        let weekday = Calendar.current.component(.weekday, from: Date())
        selectedDayIndex = weekday == 1 ? 6 : weekday - 2
    }

    private func changeWeek(by offset: Int) {
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedWeekOffset += offset
            selectDefaultDay()
        }
        Task { await loadShifts() }
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
    let now: Date

    private var status: (key: String, color: Color) {
        guard let start = shift.startDateTime, var end = shift.endDateTime else {
            return ("shift_upcoming", .appAccent)
        }
        if end <= start { end = Calendar.current.date(byAdding: .day, value: 1, to: end) ?? end }
        if now < start { return ("shift_upcoming", .appAccent) }
        if now > end { return ("shift_completed", .appTeal) }
        return ("shift_in_progress", .appGreen)
    }

    var body: some View {
        HStack(alignment: .top, spacing: APSpacing.md) {
            RoundedRectangle(cornerRadius: 3)
                .fill(shift.shiftType.gradient)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(shift.startTime)
                    .font(.body.weight(.bold))
                    .foregroundColor(.textPrimary)
                Text(shift.endTime)
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                Text(String(format: "%.1fh", shift.durationHours))
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(shift.shiftType.color)
            }
            .monospacedDigit()
            .frame(width: 48, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: shift.shiftType.icon)
                        .foregroundColor(shift.shiftType.color)
                    Text(shift.shiftType.displayName.localized(for: appLanguage))
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.textPrimary)

                    Spacer()

                    Text(status.key.localized(for: appLanguage))
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(status.color)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(status.color.opacity(0.12), in: Capsule())
                }

                if let station = shift.station, !station.isEmpty {
                    Label(station, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                }

                if let notes = shift.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(APSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: APRadius.md, style: .continuous)
                .fill(Color.appSurfaceHigh.opacity(0.45))
                .overlay(
                    RoundedRectangle(cornerRadius: APRadius.md, style: .continuous)
                        .stroke(Color.appDivider.opacity(0.35), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
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
            
            VStack(alignment: .leading, spacing: 1) {
                Text(shift.employeeName)
                    .font(.caption.weight(.medium))
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
                Text("\(shift.startTime)–\(shift.endTime)" + (shift.station.flatMap { $0.isEmpty ? nil : " • \($0)" } ?? ""))
                    .font(.caption2)
                    .foregroundColor(.textSecondary)
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
