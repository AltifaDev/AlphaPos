// TimecardChartsView.swift
// AlphaPos — Attendance Statistics Charts
//
// Interactive charts using Swift Charts framework showing
// weekly/monthly attendance data with AlphaPos Design System tokens.
// using Swift Charts framework. Designed for iPad landscape.

import SwiftUI
import Charts
import SwiftData

// MARK: - Chart Data Models

struct DailyHoursData: Identifiable {
    let id = UUID()
    let date: Date
    let employeeName: String
    let hours: Double
    let isLate: Bool
    
    var dayLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "th_TH")
        f.dateFormat = "E d"
        return f.string(from: date)
    }
}

struct AttendanceSummary: Identifiable {
    let id = UUID()
    let category: String
    let count: Int
    let color: Color
}

struct MonthlyTrendData: Identifiable {
    let id = UUID()
    let weekLabel: String
    let attendanceRate: Double
    let lateRate: Double
}

// MARK: - Main Charts View

struct TimecardChartsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Employee.firstName) private var employees: [Employee]
    @Query(sort: \Timecard.clockIn, order: .reverse) private var timecards: [Timecard]
    
    @State private var selectedPeriod: ChartPeriod = .week
    @State private var selectedDate = Date()
    
    enum ChartPeriod: String, CaseIterable {
        case week = "สัปดาห์"
        case month = "เดือน"
        case quarter = "ไตรมาส"
    }
    
    // Computed chart data
    private var weeklyHoursData: [DailyHoursData] {
        let calendar = Calendar.current
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selectedDate))!
        
        var data: [DailyHoursData] = []
        
        for dayOffset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: startOfWeek) else { continue }
            
            for employee in employees {
                let dayTimecards = timecards.filter { card in
                    card.employee?.id == employee.id &&
                    calendar.isDate(card.clockIn, inSameDayAs: date)
                }
                
                let totalHours = dayTimecards.reduce(0.0) { sum, card in
                    let end = card.clockOut ?? Date()
                    let hours = end.timeIntervalSince(card.clockIn) / 3600.0
                    return sum + hours
                }
                
                let isLate = dayTimecards.contains { card in
                    let hour = calendar.component(.hour, from: card.clockIn)
                    let minute = calendar.component(.minute, from: card.clockIn)
                    // Late if clock in after 9:30 for monthly, 10:30 for hourly
                    let threshold = employee.employmentType == "monthly" ? (9 * 60 + 30) : (10 * 60 + 30)
                    return (hour * 60 + minute) > threshold
                }
                
                data.append(DailyHoursData(
                    date: date,
                    employeeName: "\(employee.firstName) \(String(employee.lastName.prefix(1))).",
                    hours: totalHours,
                    isLate: isLate
                ))
            }
        }
        
        // If no data, generate sample data
        if data.allSatisfy({ $0.hours == 0 }) {
            return generateSampleWeeklyData()
        }
        
        return data
    }
    
    private var attendanceSummaryData: [AttendanceSummary] {
        let calendar = Calendar.current
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedDate))!
        let endOfMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth)!
        
        var onTime = 0
        var late = 0
        var absent = 0
        var leave = 0
        
        let workingDays = countWorkingDays(from: startOfMonth, to: min(Date(), endOfMonth))
        let totalExpected = workingDays * employees.count
        
        let monthTimecards = timecards.filter { card in
            card.clockIn >= startOfMonth && card.clockIn < endOfMonth
        }
        
        for card in monthTimecards {
            let hour = calendar.component(.hour, from: card.clockIn)
            let minute = calendar.component(.minute, from: card.clockIn)
            let isLate = (hour * 60 + minute) > (9 * 60 + 30)
            
            if isLate {
                late += 1
            } else {
                onTime += 1
            }
        }
        
        absent = max(0, totalExpected - onTime - late - leave)
        
        // If no real data, use sample
        if totalExpected == 0 || (onTime == 0 && late == 0) {
            return [
                AttendanceSummary(category: "มาปกติ", count: 20, color: .green),
                AttendanceSummary(category: "มาสาย", count: 2, color: .orange),
                AttendanceSummary(category: "ขาด", count: 0, color: .red),
                AttendanceSummary(category: "ลา", count: 1, color: .gray)
            ]
        }
        
        return [
            AttendanceSummary(category: "มาปกติ", count: onTime, color: .green),
            AttendanceSummary(category: "มาสาย", count: late, color: .orange),
            AttendanceSummary(category: "ขาด", count: absent, color: .red),
            AttendanceSummary(category: "ลา", count: leave, color: .gray)
        ]
    }
    
    private var monthlyTrendData: [MonthlyTrendData] {
        // Sample 4-week trend
        [
            MonthlyTrendData(weekLabel: "สัปดาห์ 1", attendanceRate: 95, lateRate: 5),
            MonthlyTrendData(weekLabel: "สัปดาห์ 2", attendanceRate: 100, lateRate: 0),
            MonthlyTrendData(weekLabel: "สัปดาห์ 3", attendanceRate: 90, lateRate: 10),
            MonthlyTrendData(weekLabel: "สัปดาห์ 4", attendanceRate: 98, lateRate: 2),
        ]
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with period selector
            chartHeader
            
            Divider().background(Color.appDivider).padding(.horizontal, APSpacing.md)
            
            // Charts Grid
            ScrollView {
                VStack(spacing: 20) {
                    HStack(spacing: 16) {
                        weeklyHoursChart
                        attendancePieChart
                    }
                    
                    if selectedPeriod != .week {
                        monthlyTrendChart
                    }
                    
                    // KPI Summary Row
                    kpiSummaryRow
                }
                .padding(APSpacing.lg)
            }
        }
        .background(Color.appBackground)
    }
    
    // MARK: - Chart Header
    
    private var chartHeader: some View {
        HStack {
            Label("สถิติการเข้างาน", systemImage: "chart.line.uptrend.xyaxis")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.textPrimary)
            
            Spacer()
            
            // Period Selector
            HStack(spacing: 4) {
                ForEach(ChartPeriod.allCases, id: \.rawValue) { period in
                    Button(action: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            selectedPeriod = period
                        }
                    }) {
                        Text(period.rawValue)
                            .font(.caption)
                            .fontWeight(.bold)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(selectedPeriod == period ? Color.appAccent : Color.appSurface)
                            .foregroundColor(selectedPeriod == period ? .white : .textSecondary)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // Date Navigation
            HStack(spacing: 8) {
                Button(action: { navigateDate(-1) }) {
                    Image(systemName: "chevron.left")
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                }
                .buttonStyle(.plain)
                
                Text(periodLabel)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.textPrimary)
                
                Button(action: { navigateDate(1) }) {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.appSurfaceHigh)
            .cornerRadius(8)
        }
        .padding(.horizontal, APSpacing.lg)
        .padding(.vertical, APSpacing.md)
        .background(Color.appSurface)
    }
    
    // MARK: - Weekly Hours Bar Chart
    
    private var weeklyHoursChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("ชั่วโมงทำงานรายวัน")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.textPrimary)
                Spacer()
                Text("ชม.")
                    .font(.caption2)
                    .foregroundColor(.textSecondary)
            }
            
            Chart(weeklyHoursData) { item in
                BarMark(
                    x: .value("วัน", item.dayLabel),
                    y: .value("ชั่วโมง", item.hours)
                )
                .foregroundStyle(by: .value("พนักงาน", item.employeeName))
                .cornerRadius(3)
                .annotation(position: .top) {
                    if item.hours > 0 {
                        Text(String(format: "%.1f", item.hours))
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundColor(.textSecondary)
                    }
                }
            }
            .chartYScale(domain: 0...12)
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 4, 8, 12]) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                        .foregroundStyle(Color.appDivider)
                    AxisValueLabel {
                        Text("\(value.as(Int.self) ?? 0)")
                            .font(.caption2)
                            .foregroundColor(.textSecondary)
                    }
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        Text(value.as(String.self) ?? "")
                            .font(.caption2)
                            .foregroundColor(.textSecondary)
                    }
                }
            }
            .chartLegend(position: .bottom, spacing: 12)
            .chartForegroundStyleScale([
                employees.first.map { "\($0.firstName) \(String($0.lastName.prefix(1)))." } ?? "Employee 1": Color.appAccent,
                employees.count > 1 ? "\(employees[1].firstName) \(String(employees[1].lastName.prefix(1)))." : "Employee 2": Color(hex: "6554C0")
            ])
            .frame(height: 200)
        }
        .padding(16)
        .background(Color.appSurface)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.appBorderSubtle, lineWidth: 1)
        )
    }
    
    // MARK: - Attendance Pie/Donut Chart
    
    private var attendancePieChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("สถิติเดือนนี้")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.textPrimary)
                Spacer()
                Text("วัน")
                    .font(.caption2)
                    .foregroundColor(.textSecondary)
            }
            
            Chart(attendanceSummaryData) { item in
                SectorMark(
                    angle: .value("จำนวน", item.count),
                    innerRadius: .ratio(0.55),
                    angularInset: 1.5
                )
                .foregroundStyle(item.color)
                .cornerRadius(3)
                .annotation(position: .overlay) {
                    if item.count > 0 {
                        Text("\(item.count)")
                            .font(.caption2.bold())
                            .foregroundColor(.white)
                    }
                }
            }
            .chartLegend(position: .bottom, spacing: 8)
            .chartForegroundStyleScale([
                "มาปกติ": Color.green,
                "มาสาย": Color.orange,
                "ขาด": Color.red,
                "ลา": Color.gray
            ])
            .frame(height: 200)
            
            // Summary text
            HStack(spacing: 16) {
                ForEach(attendanceSummaryData) { item in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(item.color)
                            .frame(width: 6, height: 6)
                        Text("\(item.category): \(item.count)")
                            .font(.system(size: 10))
                            .foregroundColor(.textSecondary)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.appSurface)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.appBorderSubtle, lineWidth: 1)
        )
    }
    
    // MARK: - Monthly Trend Line Chart
    
    private var monthlyTrendChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("แนวโน้มอัตราเข้างานรายสัปดาห์")
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.textPrimary)
            
            Chart {
                ForEach(monthlyTrendData) { item in
                    LineMark(
                        x: .value("สัปดาห์", item.weekLabel),
                        y: .value("อัตรา", item.attendanceRate)
                    )
                    .foregroundStyle(Color.appAccent)
                    .symbol(Circle())
                    .interpolationMethod(.catmullRom)
                    
                    AreaMark(
                        x: .value("สัปดาห์", item.weekLabel),
                        y: .value("อัตรา", item.attendanceRate)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.appAccent.opacity(0.2), Color.appAccent.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                    
                    BarMark(
                        x: .value("สัปดาห์", item.weekLabel),
                        y: .value("มาสาย", item.lateRate)
                    )
                    .foregroundStyle(Color.orange.opacity(0.6))
                    .cornerRadius(3)
                }
                
                // Target line
                RuleMark(y: .value("เป้าหมาย", 95))
                    .foregroundStyle(Color.green.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
                    .annotation(position: .leading) {
                        Text("เป้า 95%")
                            .font(.system(size: 9))
                            .foregroundColor(.green)
                    }
            }
            .chartYScale(domain: 0...105)
            .chartYAxis {
                AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                        .foregroundStyle(Color.appDivider)
                    AxisValueLabel {
                        Text("\(value.as(Int.self) ?? 0)%")
                            .font(.caption2)
                            .foregroundColor(.textSecondary)
                    }
                }
            }
            .frame(height: 180)
        }
        .padding(16)
        .background(Color.appSurface)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.appBorderSubtle, lineWidth: 1)
        )
    }
    
    // MARK: - KPI Summary Row
    
    private var kpiSummaryRow: some View {
        HStack(spacing: 16) {
            kpiMini(icon: "clock.fill", label: "ชม. เฉลี่ย/วัน", value: "8.2", color: .blue)
            kpiMini(icon: "figure.walk", label: "อัตราเข้างาน", value: "96%", color: .green)
            kpiMini(icon: "exclamationmark.triangle.fill", label: "มาสาย (เดือนนี้)", value: "2 ครั้ง", color: .orange)
            kpiMini(icon: "clock.badge.checkmark.fill", label: "OT รวม", value: "4.5 ชม.", color: .purple)
        }
    }
    
    private func kpiMini(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.1))
                .cornerRadius(8)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.textPrimary)
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.textSecondary)
            }
            
            Spacer()
        }
        .padding(12)
        .background(Color.appSurface)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.appBorderSubtle, lineWidth: 1)
        )
    }
    
    // MARK: - Helpers
    
    private func navigateDate(_ direction: Int) {
        let calendar = Calendar.current
        switch selectedPeriod {
        case .week:
            selectedDate = calendar.date(byAdding: .weekOfYear, value: direction, to: selectedDate) ?? selectedDate
        case .month:
            selectedDate = calendar.date(byAdding: .month, value: direction, to: selectedDate) ?? selectedDate
        case .quarter:
            selectedDate = calendar.date(byAdding: .month, value: direction * 3, to: selectedDate) ?? selectedDate
        }
    }
    
    private var periodLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "th_TH")
        switch selectedPeriod {
        case .week:
            f.dateFormat = "d MMM"
            let calendar = Calendar.current
            let start = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selectedDate))!
            let end = calendar.date(byAdding: .day, value: 6, to: start)!
            return "\(f.string(from: start)) - \(f.string(from: end))"
        case .month:
            f.dateFormat = "MMMM yyyy"
            return f.string(from: selectedDate)
        case .quarter:
            let quarter = Calendar.current.component(.month, from: selectedDate) / 3 + 1
            f.dateFormat = "yyyy"
            return "Q\(quarter) \(f.string(from: selectedDate))"
        }
    }
    
    private func countWorkingDays(from start: Date, to end: Date) -> Int {
        let calendar = Calendar.current
        var count = 0
        var current = start
        while current <= end {
            let weekday = calendar.component(.weekday, from: current)
            if weekday != 1 && weekday != 7 { count += 1 }
            current = calendar.date(byAdding: .day, value: 1, to: current)!
        }
        return count
    }
    
    private func generateSampleWeeklyData() -> [DailyHoursData] {
        let calendar = Calendar.current
        let today = Date()
        var data: [DailyHoursData] = []
        
        let names = ["Somsri J.", "Somchai S."]
        let hoursData: [[Double]] = [
            [9.0, 8.5, 9.0, 8.5, 9.0, 9.5, 6.5],
            [9.0, 9.0, 9.0, 9.0, 9.0, 9.0, 0.0]
        ]
        
        for dayOffset in 0..<7 {
            let date = calendar.date(byAdding: .day, value: dayOffset - 6, to: today)!
            for (nameIdx, name) in names.enumerated() {
                data.append(DailyHoursData(
                    date: date,
                    employeeName: name,
                    hours: hoursData[nameIdx][dayOffset],
                    isLate: dayOffset == 3 && nameIdx == 0
                ))
            }
        }
        return data
    }
}

// MARK: - Preview

#Preview {
    TimecardChartsView()
}
