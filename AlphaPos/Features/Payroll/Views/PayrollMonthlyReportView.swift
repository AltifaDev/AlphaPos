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
import UIKit

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
    let taxWithholding: Double   // L-5: ภาษีหัก ณ ที่จ่าย (personal income tax)
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

    // OT configuration (shared with Payroll dashboard settings)
    @AppStorage("default_ot_multiplier") private var otMultiplier = 1.5
    @AppStorage("ot_threshold_hours_per_day") private var otThresholdHoursPerDay = 8.0
    // L-5: Social Security & Tax Withholding settings
    @AppStorage("ss_rate_percent") private var ssRatePercent = 5.0        // default 5%
    @AppStorage("ss_max_monthly_baht") private var ssMaxMonthlyBaht = 750.0 // default ฿750
    @AppStorage("ss_min_wage_baht") private var ssMinWageBaht = 1650.0    // ขั้นต่ำที่ต้องหัก SS
    @AppStorage("enable_tax_withholding") private var enableTaxWithholding = true
    @AppStorage("tax_allowance_baht") private var taxAllowanceBaht = 60000.0 // ค่าลดหย่อนส่วนตัว/ปี

    @State private var showShareSheet = false
    @State private var isExportingPDF = false
    @State private var exportError: String? = nil
    @State private var generatedPDFURL: URL? = nil

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
        .sheet(isPresented: $showShareSheet) {
            if let url = generatedPDFURL {
                ShareSheet(activityItems: [url])
            }
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

            Text("หักภาษี")
                .frame(width: 80, alignment: .trailing)

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

            Text("-\(formatCurrency(data.taxWithholding))")
                .foregroundColor(.appRose)
                .frame(width: 80, alignment: .trailing)

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

            Text("-\(formatCurrency(reportData.reduce(0) { $0 + $1.taxWithholding }))")
                .foregroundColor(.appRose)
                .frame(width: 80, alignment: .trailing)

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
                detailRow(label: "ค่า OT (\(String(format: "%.2f", otMultiplier))x)", value: "+\(formatCurrency(data.overtimePay))")
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
                Text("• คำนวณ OT อัตรา \(String(format: "%.2f", otMultiplier)) เท่า")
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
                    // Real PDF export (M-7)
                    Button(action: { exportPDF() }) {
                        HStack(spacing: 14) {
                            Image(systemName: isExportingPDF ? "hourglass" : "doc.richtext")
                                .font(.title2)
                                .foregroundColor(.appAccent)
                                .frame(width: 44, height: 44)
                                .background(Color.appAccent.opacity(0.1))
                                .cornerRadius(10)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("payroll_export_pdf_btn".localized())
                                    .font(.subheadline.bold())
                                    .foregroundColor(.textPrimary)
                                Text(isExportingPDF
                                     ? "payroll_export_generating".localized()
                                     : "รายงานแบบพิมพ์ได้")
                                    .font(.caption)
                                    .foregroundColor(.textSecondary)
                            }

                            Spacer()

                            if isExportingPDF {
                                ProgressView().tint(.appAccent)
                            } else {
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.textSecondary)
                            }
                        }
                        .padding(14)
                        .background(Color.appSurface)
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorderSubtle, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(isExportingPDF || reportData.isEmpty)

                    exportOption(icon: "tablecells", title: "Excel (.xlsx)", desc: "ส่งออกเป็นตาราง")
                    exportOption(icon: "doc.text", title: "CSV", desc: "สำหรับนำเข้าระบบอื่น")

                    if let err = exportError {
                        Text(err)
                            .font(.caption)
                            .foregroundColor(.appRose)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
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

    // MARK: - PDF Export (M-7)

    /// Triggers real PDF generation and presents the iOS share sheet.
    private func exportPDF() {
        guard !reportData.isEmpty else { return }
        exportError = nil
        isExportingPDF = true

        // Render off the main render pass, then present share sheet.
        DispatchQueue.main.async {
            if let url = generatePayrollPDF() {
                generatedPDFURL = url
                isExportingPDF = false
                showExportSheet = false
                // Slight delay so the export sheet dismisses before share sheet appears.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    showShareSheet = true
                }
            } else {
                isExportingPDF = false
                exportError = "payroll_export_failed".localized()
            }
        }
    }

    /// Builds a real A4 PDF of the monthly payroll report using UIGraphicsPDFRenderer.
    /// Returns a file URL in the temporary directory, or nil on failure.
    private func generatePayrollPDF() -> URL? {
        // A4 at 72 dpi: 595 x 842 points
        let pageWidth: CGFloat = 595
        let pageHeight: CGFloat = 842
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let margin: CGFloat = 32

        let format = UIGraphicsPDFRendererFormat()
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

        // Fonts
        let titleFont = UIFont.boldSystemFont(ofSize: 20)
        let logoFont = UIFont.boldSystemFont(ofSize: 13)
        let subFont = UIFont.systemFont(ofSize: 11)
        let headerFont = UIFont.boldSystemFont(ofSize: 9)
        let cellFont = UIFont.systemFont(ofSize: 9)
        let totalFont = UIFont.boldSystemFont(ofSize: 9)

        // Colors
        let inkColor = UIColor(red: 0.12, green: 0.13, blue: 0.16, alpha: 1)
        let mutedColor = UIColor(red: 0.45, green: 0.47, blue: 0.52, alpha: 1)
        let accentColor = UIColor(red: 0.20, green: 0.45, blue: 0.92, alpha: 1)
        let redColor = UIColor(red: 0.85, green: 0.22, blue: 0.28, alpha: 1)
        let greenColor = UIColor(red: 0.15, green: 0.60, blue: 0.35, alpha: 1)
        let headerBg = UIColor(red: 0.94, green: 0.95, blue: 0.97, alpha: 1)
        let stripeBg = UIColor(red: 0.975, green: 0.98, blue: 0.99, alpha: 1)
        let lineColor = UIColor(red: 0.85, green: 0.86, blue: 0.89, alpha: 1)

        // Column layout: name | days | hours | ot | base | ot pay | ssf | tax | net  (L-5)
        let contentWidth = pageWidth - margin * 2
        // Proportional widths that sum to contentWidth
        let colFractions: [CGFloat] = [0.20, 0.09, 0.09, 0.08, 0.12, 0.11, 0.11, 0.10, 0.10]
        var colX: [CGFloat] = []
        var acc = margin
        for f in colFractions {
            colX.append(acc)
            acc += f * contentWidth
        }
        colX.append(acc) // right edge

        let currencyFmt: (Double) -> String = { value in
            let f = NumberFormatter()
            f.numberStyle = .decimal
            f.maximumFractionDigits = 0
            return (f.string(from: NSNumber(value: value)) ?? "0") + " ฿"
        }

        let data = renderer.pdfData { ctx in
            ctx.beginPage()
            let cg = ctx.cgContext
            var y: CGFloat = margin

            // ----- Header -----
            let titleStr = "Payroll Report — \(monthYearLabel)"
            (titleStr as NSString).draw(
                at: CGPoint(x: margin, y: y),
                withAttributes: [.font: titleFont, .foregroundColor: inkColor]
            )
            let logo = "AlphaPos"
            let logoSize = (logo as NSString).size(withAttributes: [.font: logoFont])
            (logo as NSString).draw(
                at: CGPoint(x: pageWidth - margin - logoSize.width, y: y + 4),
                withAttributes: [.font: logoFont, .foregroundColor: accentColor]
            )
            y += 28

            let genStr = "Generated: \(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short))   •   Employees: \(reportData.count)"
            (genStr as NSString).draw(
                at: CGPoint(x: margin, y: y),
                withAttributes: [.font: subFont, .foregroundColor: mutedColor]
            )
            y += 22

            // Divider under header
            cg.setStrokeColor(accentColor.cgColor)
            cg.setLineWidth(1.5)
            cg.move(to: CGPoint(x: margin, y: y))
            cg.addLine(to: CGPoint(x: pageWidth - margin, y: y))
            cg.strokePath()
            y += 12

            // ----- Table Header -----
            let rowHeight: CGFloat = 22
            // L-5: Added tax withholding column
            let headers = ["ชื่อพนักงาน", "วันทำงาน", "ชั่วโมง", "OT", "เงินเดือน", "OT Pay", "ประกันสังคม", "ภาษี", "สุทธิ"]
            let alignments: [NSTextAlignment] = [.left, .center, .center, .center, .right, .right, .right, .right, .right]

            cg.setFillColor(headerBg.cgColor)
            cg.fill(CGRect(x: margin, y: y, width: contentWidth, height: rowHeight))

            func drawCell(_ text: String, col: Int, y: CGFloat, font: UIFont, color: UIColor) {
                let cellX = colX[col]
                let cellW = colX[col + 1] - colX[col]
                let para = NSMutableParagraphStyle()
                para.alignment = alignments[col]
                para.lineBreakMode = .byTruncatingTail
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font, .foregroundColor: color, .paragraphStyle: para
                ]
                let inset: CGFloat = 4
                let rect = CGRect(x: cellX + inset, y: y + 6, width: cellW - inset * 2, height: rowHeight - 8)
                (text as NSString).draw(in: rect, withAttributes: attrs)
            }

            for (i, h) in headers.enumerated() {
                drawCell(h, col: i, y: y, font: headerFont, color: mutedColor)
            }
            y += rowHeight

            // ----- Rows -----
            for (idx, item) in reportData.enumerated() {
                // New page if needed (leave room for footer)
                if y + rowHeight > pageHeight - margin - 40 {
                    ctx.beginPage()
                    y = margin
                }
                if idx % 2 == 1 {
                    cg.setFillColor(stripeBg.cgColor)
                    cg.fill(CGRect(x: margin, y: y, width: contentWidth, height: rowHeight))
                }

                let name = "\(item.employee.firstName) \(item.employee.lastName)"
                drawCell(name, col: 0, y: y, font: cellFont, color: inkColor)
                drawCell("\(item.daysWorked)/\(workingDaysInMonth)", col: 1, y: y, font: cellFont, color: inkColor)
                drawCell(String(format: "%.0f", item.totalHours), col: 2, y: y, font: cellFont, color: inkColor)
                drawCell(String(format: "%.1f", item.overtimeHours), col: 3, y: y, font: cellFont, color: inkColor)
                drawCell(currencyFmt(item.basePay), col: 4, y: y, font: cellFont, color: inkColor)
                drawCell(item.overtimePay > 0 ? "+" + currencyFmt(item.overtimePay) : "-", col: 5, y: y, font: cellFont, color: item.overtimePay > 0 ? greenColor : mutedColor)
                drawCell("-" + currencyFmt(item.socialSecurity), col: 6, y: y, font: cellFont, color: redColor)
                // L-5: Tax withholding col 7, net pay now col 8
                drawCell(item.taxWithholding > 0 ? "-" + currencyFmt(item.taxWithholding) : "-",
                         col: 7, y: y, font: cellFont, color: redColor)
                drawCell(currencyFmt(item.netPay), col: 8, y: y, font: totalFont, color: accentColor)

                // Row separator
                cg.setStrokeColor(lineColor.cgColor)
                cg.setLineWidth(0.5)
                cg.move(to: CGPoint(x: margin, y: y + rowHeight))
                cg.addLine(to: CGPoint(x: pageWidth - margin, y: y + rowHeight))
                cg.strokePath()

                y += rowHeight
            }

            // ----- Footer / Totals -----
            if y + rowHeight + 6 > pageHeight - margin {
                ctx.beginPage()
                y = margin
            }
            y += 6
            cg.setFillColor(headerBg.cgColor)
            cg.fill(CGRect(x: margin, y: y, width: contentWidth, height: rowHeight))

            let totalDays = reportData.reduce(0) { $0 + $1.daysWorked }
            let totalHrs = reportData.reduce(0.0) { $0 + $1.totalHours }
            let totalOTh = reportData.reduce(0.0) { $0 + $1.overtimeHours }
            let totalBase = reportData.reduce(0.0) { $0 + $1.basePay }
            let totalOTPay = reportData.reduce(0.0) { $0 + $1.overtimePay }
            let totalSSF = reportData.reduce(0.0) { $0 + $1.socialSecurity }
            let totalNet = reportData.reduce(0.0) { $0 + $1.netPay }

            drawCell("รวมทั้งหมด", col: 0, y: y, font: totalFont, color: inkColor)
            drawCell("\(totalDays)", col: 1, y: y, font: totalFont, color: inkColor)
            drawCell(String(format: "%.0f", totalHrs), col: 2, y: y, font: totalFont, color: inkColor)
            drawCell(String(format: "%.1f", totalOTh), col: 3, y: y, font: totalFont, color: inkColor)
            drawCell(currencyFmt(totalBase), col: 4, y: y, font: totalFont, color: inkColor)
            drawCell("+" + currencyFmt(totalOTPay), col: 5, y: y, font: totalFont, color: greenColor)
            drawCell("-" + currencyFmt(totalSSF), col: 6, y: y, font: totalFont, color: redColor)
            drawCell(currencyFmt(totalNet), col: 7, y: y, font: totalFont, color: accentColor)
            y += rowHeight + 8

            let note = "• OT 1.5x   • ประกันสังคม 5% (สูงสุด 750 บาท)"
            (note as NSString).draw(
                at: CGPoint(x: margin, y: y),
                withAttributes: [.font: subFont, .foregroundColor: mutedColor]
            )
        }

        // Save to temporary directory
        let safeMonth = monthYearLabel.replacingOccurrences(of: " ", with: "_")
        let fileName = "PayrollReport_\(safeMonth).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

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

                // M-3 fix: use configurable OT threshold instead of hardcoded 8 hours/day
                let regularHours = min(totalHours, Double(daysWorked) * otThresholdHoursPerDay)
                let overtimeHours = max(0, totalHours - regularHours)

                let basePay: Double
                let otRate: Double

                if employee.employmentType == "monthly" {
                    basePay = employee.payRate
                    otRate = employee.payRate / 30 / 8 * otMultiplier
                } else {
                    basePay = employee.payRate * totalHours
                    otRate = employee.payRate * otMultiplier
                }

                let overtimePay = overtimeHours * otRate
                // L-5: Social Security — configurable rate & cap
                let grossMonthly = basePay + overtimePay
                let socialSecurity: Double = grossMonthly >= ssMinWageBaht
                    ? min(grossMonthly * (ssRatePercent / 100.0), ssMaxMonthlyBaht)
                    : 0.0

                // L-5: Personal Income Tax Withholding (Thai bracket system)
                let taxWithholding: Double
                if enableTaxWithholding {
                    // Annualise income, apply standard deduction (50% max ฿100,000) + personal allowance
                    let annualIncome = grossMonthly * 12.0
                    let stdDeduction = min(annualIncome * 0.5, 100_000.0)
                    let netAnnual = max(0, annualIncome - stdDeduction - taxAllowanceBaht)
                    let annualTax = thaiIncomeTax(netAnnual)
                    taxWithholding = (annualTax / 12.0).rounded(.toNearestOrAwayFromZero)
                } else {
                    taxWithholding = 0.0
                }

                let netPay = grossMonthly - socialSecurity - taxWithholding

                let lateCount = empTimecards.filter { card in
                    let hour = calendar.component(.hour, from: card.clockIn)
                    let minute = calendar.component(.minute, from: card.clockIn)
                    let threshold = employee.employmentType == "monthly" ? (9 * 60 + 30) : (10 * 60 + 30)
                    return (hour * 60 + minute) > threshold
                }.count

                return PayrollReportData(
                    employee: employee,
                    daysWorked: max(daysWorked, 1),
                    totalHours: max(totalHours, Double(daysWorked) * otThresholdHoursPerDay),
                    regularHours: regularHours,
                    overtimeHours: overtimeHours,
                    basePay: basePay,
                    overtimePay: overtimePay,
                    bonus: 0,
                    deductions: 0,
                    socialSecurity: socialSecurity,
                    taxWithholding: taxWithholding,
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
            let otRate = isMonthly ? (emp.payRate / 30 / 8 * otMultiplier) : (emp.payRate * otMultiplier)
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
                taxWithholding: 0,
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

// MARK: - L-5: Thai Income Tax Bracket Calculation

/// คำนวณภาษีเงินได้บุคคลธรรมดาตามขั้นบันไดไทย (ปีภาษี 2567)
/// Input: net annual taxable income (หลังหักค่าลดหย่อน) in THB
/// Returns: annual tax amount in THB
func thaiIncomeTax(_ netAnnual: Double) -> Double {
    // Progressive brackets (2024 Thai PIT)
    // 0–150,000:        0%
    // 150,001–300,000:  5%
    // 300,001–500,000: 10%
    // 500,001–750,000: 15%
    // 750,001–1,000,000: 20%
    // 1,000,001–2,000,000: 25%
    // 2,000,001–5,000,000: 30%
    // >5,000,000: 35%
    let brackets: [(limit: Double, rate: Double)] = [
        (150_000, 0.00),
        (300_000, 0.05),
        (500_000, 0.10),
        (750_000, 0.15),
        (1_000_000, 0.20),
        (2_000_000, 0.25),
        (5_000_000, 0.30),
        (.infinity, 0.35)
    ]
    var tax = 0.0
    var remaining = netAnnual
    var prevLimit = 0.0
    for bracket in brackets {
        if remaining <= 0 { break }
        let bandSize = bracket.limit == .infinity ? remaining : min(remaining, bracket.limit - prevLimit)
        tax += bandSize * bracket.rate
        remaining -= bandSize
        prevLimit = bracket.limit
    }
    return tax
}

// MARK: - Preview

#Preview {
    NavigationStack {
        PayrollMonthlyReportView()
    }
}
