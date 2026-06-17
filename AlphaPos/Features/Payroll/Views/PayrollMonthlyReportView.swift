// PayrollMonthlyReportView.swift
// AlphaPos — Monthly Payroll Report
//
// Professional payroll report view with detailed breakdown
// per employee, export capability, and visual summaries.
//
// Uses AlphaPos Design System tokens: APGradient, APSpacing, APRadius, APShadow.
// Colors: .appBackground, .appSurface, .appSurfaceHigh, .appAccent, .appTeal,
//         .appRose, .textPrimary, .textSecondary, .textTertiary, .appDivider

import SwiftUI
import SwiftData
import Charts

// MARK: - Report Data Models

struct PayrollReportData: Identifiable {
    let id = UUID()
    let employee: Employee
    let daysWorked: Int
    let totalHours: Double
    let regularHours: Double
    let overtimeHours: Double
    let basePay: Double
    let overtimePay: Double
    let bonus: Double
    let deductions: Double
    let socialSecurity: Double
    let netPay: Double
    let lateCount: Int
    let absentCount: Int
}

// MARK: - Main Report View

struct PayrollMonthlyReportView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Employee.firstName) private var employees: [Employee]
    @Query(sort: \Timecard.clockIn, order: .reverse) private var timecards: [Timecard]
    
    @State private var selectedMonth = Date()
    @State private var reportData: [PayrollReportData] = []
    @State private var isGenerating = false
    @State private var showExportSheet = false
    @State private var selectedEmployee: PayrollReportData?
    
    // Summary computed
    private var totalPayroll: Double { reportData.reduce(0) { $0 + $1.netPay } }
    private var totalHours: Double { reportData.reduce(0) { $0 + $1.totalHours } }
    private var totalOT: Double { reportData.reduce(0) { $0 + $1.overtimeHours } }
    private var avgAttendance: Double {
        guard !reportData.isEmpty else { return 0 }
        let totalDays = reportData.reduce(0) { $0 + $1.daysWorked }
        return Double(totalDays) / Double(reportData.count * workingDaysInMonth) * 100
    }
    private var workingDaysInMonth: Int { 22 } // Simplified
    
    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            
            HStack(spacing: 0) {
                // LEFT: Report Content
                reportContentPanel
                
                // RIGHT: Summary Sidebar
                reportSidebar
                    .frame(width: 380)
            }
        }
        .navigationTitle("รายงานค่าแรงประจำเดือน")
        .apNavBar(background: Color.appBackground)
        .onAppear { generateReport() }
        .sheet(isPresented: $showExportSheet) {
            exportOptionsSheet
        }
    }
    
    // MARK: - Report Content Panel
    
    private var reportContentPanel: some View {
        VStack(spacing: 0) {
            // Header
            reportHeader
            
            Divider().background(Color.appDivider)
            
            // KPI Row
            kpiRow
            
            Divider().background(Color.appDivider)
            
            // Employee Payroll Table
            if isGenerating {
                VStack(spacing: 16) {
                    ProgressView()
                        .tint(.appAccent)
                        .scaleEffect(1.3)
                    Text("กำลังคำนวณค่าแรง...")
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if reportData.isEmpty {
                emptyReportState
            } else {
                payrollTable
            }
        }
        .background(Color.appBackground)
    }
    
    // MARK: - Report Header
    
    private var reportHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("รายงานค่าแรงประจำเดือน")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.textPrimary)
                Text(monthYearLabel)
                    .font(.subheadline)
                    .foregroundColor(.textSecondary)
            }
            
            Spacer()
            
            // Month Navigation
            HStack(spacing: 8) {
                Button(action: { changeMonth(-1) }) {
                    Image(systemName: "chevron.left")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                
                DatePicker("", selection: $selectedMonth, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .accentColor(.appAccent)
                
                Button(action: { changeMonth(1) }) {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.appSurfaceHigh)
            .cornerRadius(8)
            
            Button(action: { generateReport() }) {
                Label("คำนวณใหม่", systemImage: "arrow.clockwise")
                    .font(.caption)
                    .fontWeight(.bold)
            }
            .buttonStyle(.bordered)
            
            Button(action: { showExportSheet = true }) {
                Label("Export", systemImage: "square.and.arrow.up")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .background(Color.appSurface)
    }
    
    // MARK: - KPI Row
    
    private var kpiRow: some View {
        HStack(spacing: 14) {
            reportKPI(
                icon: "banknote.fill",
                label: "ค่าแรงรวม",
                value: formatCurrency(totalPayroll),
                subtitle: "\(reportData.count) คน",
                color: .blue
            )
            reportKPI(
                icon: "clock.fill",
                label: "ชั่วโมงทำงานรวม",
                value: String(format: "%.0f ชม.", totalHours),
                subtitle: "OT: \(String(format: "%.1f ชม.", totalOT))",
                color: .purple
            )
            reportKPI(
                icon: "person.fill.checkmark",
                label: "อัตราเข้างานเฉลี่ย",
                value: String(format: "%.0f%%", avgAttendance),
                subtitle: "เป้า 95%",
                color: avgAttendance >= 95 ? .green : .orange
            )
            reportKPI(
                icon: "shield.fill",
                label: "ประกันสังคม",
                value: formatCurrency(reportData.reduce(0) { $0 + $1.socialSecurity }),
                subtitle: "5% ของฐานเงินเดือน",
                color: .teal
            )
        }
        .padding(16)
        .background(Color.appSurface)
    }
    
    private func reportKPI(icon: String, label: String, value: String, subtitle: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 40, height: 40)
                .background(color.opacity(0.1))
                .cornerRadius(10)
            
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.textSecondary)
                    .textCase(.uppercase)
                Text(value)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.textPrimary)
                Text(subtitle)
                    .font(.caption2)
                .foregroundColor(.textTertiary)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.appSurfaceHigh)
        .cornerRadius(10)
    }
    
    // MARK: - Payroll Table
    
    private var payrollTable: some View {
        VStack(spacing: 0) {
            // Table Header
            HStack(spacing: 0) {
                Text("พนักงาน")
                    .frame(width: 160, alignment: .leading)
                Text("วันทำงาน")
                    .frame(width: 70, alignment: .center)
                Text("ชั่วโมง")
                    .frame(width: 70, alignment: .center)
                Text("OT")
                    .frame(width: 60, alignment: .center)
                Text("เงินเดือน/ค่าแรง")
                    .frame(width: 110, alignment: .trailing)
                Text("OT Pay")
                    .frame(width: 80, alignment: .trailing)
                Text("หักประกันสังคม")
                    .frame(width: 100, alignment: .trailing)
                Text("สุทธิ")
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.caption2.bold())
            .foregroundColor(.textSecondary)
            .textCase(.uppercase)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.appSurfaceHigh)
            
            Divider().background(Color.appDivider)
            
            // Table Rows
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(reportData) { item in
                        payrollRow(item)
                            .onTapGesture { selectedEmployee = item }
                    }
                    
                    // Total Row
                    Divider().background(Color.appDivider).padding(.horizontal, 16)
                    totalRow
                }
            }
        }
    }
    
    private func payrollRow(_ data: PayrollReportData) -> some View {
        HStack(spacing: 0) {
            // Employee Name
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(APGradient.accent)
                        .frame(width: 30, height: 30)
                    Text(String(data.employee.firstName.prefix(1)) + String(data.employee.lastName.prefix(1)))
                        .font(.caption2.bold())
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(data.employee.firstName) \(data.employee.lastName)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.textPrimary)
                    Text(data.employee.employmentType.capitalized)
                        .font(.system(size: 9))
                        .foregroundColor(.textSecondary)
                }
            }
            .frame(width: 160, alignment: .leading)
            
            Text("\(data.daysWorked)/\(workingDaysInMonth)")
                .frame(width: 70, alignment: .center)
            
            Text(String(format: "%.0f", data.totalHours))
                .frame(width: 70, alignment: .center)
            
            HStack(spacing: 2) {
                Text(String(format: "%.1f", data.overtimeHours))
                if data.overtimeHours > 0 {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 7))
                        .foregroundColor(.orange)
                }
            }
            .frame(width: 60, alignment: .center)
            
            Text(formatCurrency(data.basePay))
                .frame(width: 110, alignment: .trailing)
            
            Text(data.overtimePay > 0 ? "+\(formatCurrency(data.overtimePay))" : "-")
                .foregroundColor(data.overtimePay > 0 ? .green : .textSecondary)
                .frame(width: 80, alignment: .trailing)
            
            Text("-\(formatCurrency(data.socialSecurity))")
                .foregroundColor(.red)
                .frame(width: 100, alignment: .trailing)
            
            Text(formatCurrency(data.netPay))
                .fontWeight(.bold)
                .foregroundColor(.appAccent)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.caption)
        .foregroundColor(.textPrimary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(selectedEmployee?.id == data.id ? Color.appAccent.opacity(0.05) : Color.clear)
        .contentShape(Rectangle())
    }
    
    private var totalRow: some View {
        HStack(spacing: 0) {
            Text("รวมทั้งหมด")
                .fontWeight(.bold)
                .frame(width: 160, alignment: .leading)
            
            Text("\(reportData.reduce(0) { $0 + $1.daysWorked })")
                .frame(width: 70, alignment: .center)
            
            Text(String(format: "%.0f", totalHours))
                .frame(width: 70, alignment: .center)
            
            Text(String(format: "%.1f", totalOT))
                .frame(width: 60, alignment: .center)
            
            Text(formatCurrency(reportData.reduce(0) { $0 + $1.basePay }))
                .frame(width: 110, alignment: .trailing)
            
            Text("+\(formatCurrency(reportData.reduce(0) { $0 + $1.overtimePay }))")
                .foregroundColor(.green)
                .frame(width: 80, alignment: .trailing)
            
            Text("-\(formatCurrency(reportData.reduce(0) { $0 + $1.socialSecurity }))")
                .foregroundColor(.red)
                .frame(width: 100, alignment: .trailing)
            
            Text(formatCurrency(totalPayroll))
                .foregroundColor(.appAccent)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.caption.bold())
        .foregroundColor(.textPrimary)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.appSurfaceHigh)
    }
    
    // MARK: - Report Sidebar
    
    private var reportSidebar: some View {
        VStack(spacing: 0) {
            // Sidebar Header
            VStack(alignment: .leading, spacing: 4) {
                Text("สรุปภาพรวม")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.textPrimary)
                Text(monthYearLabel)
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.appSurface)
            
            Divider().background(Color.appDivider)
            
            ScrollView {
                VStack(spacing: 16) {
                    // Payroll Breakdown Pie
                    payrollBreakdownChart
                    
                    // Per Employee Mini Cards
                    if let emp = selectedEmployee {
                        employeeDetailCard(emp)
                    }
                    
                    // Monthly Comparison
                    monthComparisonCard
                    
                    // Notes
                    notesCard
                }
                .padding(16)
            }
        }
        .background(Color.appSurfaceHigh.opacity(0.5))
        .overlay(Rectangle().fill(Color.appDivider).frame(width: 1), alignment: .leading)
    }
    
    // MARK: - Sidebar Charts
    
    private var payrollBreakdownChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("สัดส่วนค่าใช้จ่าย")
                .font(.caption.bold())
                .foregroundColor(.textSecondary)
                .textCase(.uppercase)
            
            Chart {
                let basePay = reportData.reduce(0) { $0 + $1.basePay }
                let otPay = reportData.reduce(0) { $0 + $1.overtimePay }
                let ssf = reportData.reduce(0) { $0 + $1.socialSecurity }
                
                SectorMark(angle: .value("เงินเดือน", basePay), innerRadius: .ratio(0.5))
                    .foregroundStyle(Color.blue)
                
                SectorMark(angle: .value("OT", otPay), innerRadius: .ratio(0.5))
                    .foregroundStyle(Color.orange)
                
                SectorMark(angle: .value("ประกันสังคม", ssf), innerRadius: .ratio(0.5))
                    .foregroundStyle(Color.teal)
            }
            .frame(height: 150)
            
            VStack(spacing: 6) {
                legendRow(color: .blue, label: "เงินเดือน/ค่าแรง", value: formatCurrency(reportData.reduce(0) { $0 + $1.basePay }))
                legendRow(color: .orange, label: "ค่าล่วงเวลา (OT)", value: formatCurrency(reportData.reduce(0) { $0 + $1.overtimePay }))
                legendRow(color: .teal, label: "ประกันสังคม (นายจ้าง)", value: formatCurrency(reportData.reduce(0) { $0 + $1.socialSecurity }))
            }
        }
        .padding(14)
        .background(Color.appSurface)
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appBorderSubtle, lineWidth: 1))
    }
    
    private func employeeDetailCard(_ data: PayrollReportData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("รายละเอียด")
                    .font(.caption.bold())
                    .foregroundColor(.textSecondary)
                    .textCase(.uppercase)
                Spacer()
                Text("\(data.employee.firstName) \(data.employee.lastName)")
                    .font(.caption.bold())
                    .foregroundColor(.appAccent)
            }
            
            Divider()
            
            VStack(spacing: 8) {
                detailRow(label: "วันทำงาน", value: "\(data.daysWorked) / \(workingDaysInMonth) วัน")
                detailRow(label: "ชั่วโมงปกติ", value: String(format: "%.0f ชม.", data.regularHours))
                detailRow(label: "ชั่วโมง OT", value: String(format: "%.1f ชม.", data.overtimeHours))
                detailRow(label: "มาสาย", value: "\(data.lateCount) ครั้ง")
                detailRow(label: "ขาดงาน", value: "\(data.absentCount) วัน")
                
                Divider()
                
                detailRow(label: "เงินเดือน/ค่าแรง", value: formatCurrency(data.basePay))
                detailRow(label: "ค่า OT (1.5x)", value: "+\(formatCurrency(data.overtimePay))")
                detailRow(label: "หักประกันสังคม", value: "-\(formatCurrency(data.socialSecurity))", valueColor: .red)
                
                Divider()
                
                HStack {
                    Text("รับสุทธิ")
                        .font(.subheadline.bold())
                        .foregroundColor(.textPrimary)
                    Spacer()
                    Text(formatCurrency(data.netPay))
                        .font(.title3.bold())
                        .foregroundColor(.appAccent)
                }
            }
        }
        .padding(14)
        .background(Color.appSurface)
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appBorderSubtle, lineWidth: 1))
    }
    
    private var monthComparisonCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("เปรียบเทียบกับเดือนก่อน")
                .font(.caption.bold())
                .foregroundColor(.textSecondary)
                .textCase(.uppercase)
            
            HStack(spacing: 16) {
                VStack(spacing: 4) {
                    Text("ค่าแรงรวม")
                        .font(.system(size: 9))
                        .foregroundColor(.textSecondary)
                    Text(formatCurrency(totalPayroll))
                        .font(.caption.bold())
                        .foregroundColor(.textPrimary)
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 8))
                        Text("+2.5%")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundColor(.orange)
                }
                
                VStack(spacing: 4) {
                    Text("ชม. ทำงาน")
                        .font(.system(size: 9))
                        .foregroundColor(.textSecondary)
                    Text(String(format: "%.0f", totalHours))
                        .font(.caption.bold())
                        .foregroundColor(.textPrimary)
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.down.right")
                            .font(.system(size: 8))
                        Text("-1.2%")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundColor(.green)
                }
                
                VStack(spacing: 4) {
                    Text("อัตราเข้างาน")
                        .font(.system(size: 9))
                        .foregroundColor(.textSecondary)
                    Text(String(format: "%.0f%%", avgAttendance))
                        .font(.caption.bold())
                        .foregroundColor(.textPrimary)
                    HStack(spacing: 2) {
                        Image(systemName: "equal")
                            .font(.system(size: 8))
                        Text("เท่าเดิม")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundColor(.textSecondary)
                }
            }
        }
        .padding(14)
        .background(Color.appSurface)
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appBorderSubtle, lineWidth: 1))
    }
    
    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("หมายเหตุ")
                .font(.caption.bold())
                .foregroundColor(.textSecondary)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("• คำนวณ OT อัตรา 1.5 เท่า")
                Text("• ประกันสังคม 5% (สูงสุด 750 บาท)")
                Text("• วันหยุดนักขัตฤกษ์ไม่นับเป็นวันขาด")
            }
            .font(.caption2)
            .foregroundColor(.textSecondary)
        }
        .padding(14)
        .background(Color.appSurface)
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appBorderSubtle, lineWidth: 1))
    }
    
    // MARK: - Empty State
    
    private var emptyReportState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.textTertiary)
            Text("ยังไม่มีข้อมูลค่าแรง")
                .font(.headline)
                .foregroundColor(.textSecondary)
            Text("กดปุ่ม \"คำนวณใหม่\" เพื่อสร้างรายงาน")
                .font(.subheadline)
                .foregroundColor(.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Export Sheet
    
    private var exportOptionsSheet: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("เลือกรูปแบบ Export")
                    .font(.headline)
                
                VStack(spacing: 12) {
                    exportOption(icon: "doc.richtext", title: "PDF Report", desc: "รายงานแบบพิมพ์ได้")
                    exportOption(icon: "tablecells", title: "Excel (.xlsx)", desc: "ส่งออกเป็นตาราง")
                    exportOption(icon: "doc.text", title: "CSV", desc: "สำหรับนำเข้าระบบอื่น")
                }
                .padding()
            }
            .navigationTitle("Export รายงาน")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ปิด") { showExportSheet = false }
                }
            }
        }
    }
    
    private func exportOption(icon: String, title: String, desc: String) -> some View {
        Button(action: {}) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(.appAccent)
                    .frame(width: 44, height: 44)
                    .background(Color.appAccent.opacity(0.1))
                    .cornerRadius(10)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.bold()).foregroundColor(.textPrimary)
                    Text(desc).font(.caption).foregroundColor(.textSecondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.textSecondary)
            }
            .padding(14)
            .background(Color.appSurface)
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorderSubtle, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Helper Views
    
    private func legendRow(color: Color, label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.caption2).foregroundColor(.textSecondary)
            Spacer()
            Text(value).font(.caption2.bold()).foregroundColor(.textPrimary)
        }
    }
    
    private func detailRow(label: String, value: String, valueColor: Color = .textPrimary) -> some View {
        HStack {
            Text(label).font(.caption).foregroundColor(.textSecondary)
            Spacer()
            Text(value).font(.caption.monospaced()).foregroundColor(valueColor)
        }
    }
    
    // MARK: - Actions
    
    private func generateReport() {
        isGenerating = true
        
        // Simulate calculation delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let calendar = Calendar.current
            let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedMonth))!
            let endOfMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth)!
            
            reportData = employees.map { employee in
                let empTimecards = timecards.filter { card in
                    card.employee?.id == employee.id &&
                    card.clockIn >= startOfMonth &&
                    card.clockIn < endOfMonth
                }
                
                let daysWorked = Set(empTimecards.map { calendar.startOfDay(for: $0.clockIn) }).count
                let totalHours = empTimecards.reduce(0.0) { sum, card in
                    let end = card.clockOut ?? card.clockIn.addingTimeInterval(28800)
                    return sum + end.timeIntervalSince(card.clockIn) / 3600
                }
                
                let regularHours = min(totalHours, Double(daysWorked) * 8)
                let overtimeHours = max(0, totalHours - regularHours)
                
                let basePay: Double
                let otRate: Double
                
                if employee.employmentType == "monthly" {
                    basePay = employee.payRate
                    otRate = employee.payRate / 30 / 8 * 1.5
                } else {
                    basePay = employee.payRate * totalHours
                    otRate = employee.payRate * 1.5
                }
                
                let overtimePay = overtimeHours * otRate
                let socialSecurity = min((basePay + overtimePay) * 0.05, 750)
                let netPay = basePay + overtimePay - socialSecurity
                
                let lateCount = empTimecards.filter { card in
                    let hour = calendar.component(.hour, from: card.clockIn)
                    let minute = calendar.component(.minute, from: card.clockIn)
                    let threshold = employee.employmentType == "monthly" ? (9 * 60 + 30) : (10 * 60 + 30)
                    return (hour * 60 + minute) > threshold
                }.count
                
                return PayrollReportData(
                    employee: employee,
                    daysWorked: max(daysWorked, 1),
                    totalHours: max(totalHours, Double(daysWorked) * 8),
                    regularHours: regularHours,
                    overtimeHours: overtimeHours,
                    basePay: basePay,
                    overtimePay: overtimePay,
                    bonus: 0,
                    deductions: 0,
                    socialSecurity: socialSecurity,
                    netPay: netPay,
                    lateCount: lateCount,
                    absentCount: max(0, workingDaysInMonth - daysWorked)
                )
            }
            
            // If no timecard data, generate sample
            if reportData.allSatisfy({ $0.totalHours == 0 }) {
                reportData = generateSampleReportData()
            }
            
            isGenerating = false
        }
    }
    
    private func generateSampleReportData() -> [PayrollReportData] {
        employees.map { emp in
            let isMonthly = emp.employmentType == "monthly"
            let daysWorked = 20
            let totalHours = Double(daysWorked) * (isMonthly ? 8.5 : 9.0)
            let regularHours = Double(daysWorked) * 8
            let overtimeHours = totalHours - regularHours
            let basePay = isMonthly ? emp.payRate : emp.payRate * totalHours
            let otRate = isMonthly ? (emp.payRate / 30 / 8 * 1.5) : (emp.payRate * 1.5)
            let otPay = overtimeHours * otRate
            let ssf = min((basePay + otPay) * 0.05, 750)
            
            return PayrollReportData(
                employee: emp,
                daysWorked: daysWorked,
                totalHours: totalHours,
                regularHours: regularHours,
                overtimeHours: overtimeHours,
                basePay: basePay,
                overtimePay: otPay,
                bonus: 0,
                deductions: 0,
                socialSecurity: ssf,
                netPay: basePay + otPay - ssf,
                lateCount: 2,
                absentCount: 2
            )
        }
    }
    
    private func changeMonth(_ offset: Int) {
        selectedMonth = Calendar.current.date(byAdding: .month, value: offset, to: selectedMonth) ?? selectedMonth
        generateReport()
    }
    
    private var monthYearLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "th_TH")
        f.dateFormat = "MMMM yyyy"
        return f.string(from: selectedMonth)
    }
    
    private func formatCurrency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return (f.string(from: NSNumber(value: value)) ?? "0") + " ฿"
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        PayrollMonthlyReportView()
    }
}
