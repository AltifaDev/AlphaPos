import SwiftUI
import SwiftData
import UIKit

/// Full-width payroll engine: period controls + dense slip table.
struct EmployeePayrollEngineView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Employee.firstName) private var employees: [Employee]
    @Query(sort: \Timecard.clockIn, order: .reverse) private var allTimecards: [Timecard]

    @AppStorage("app_language") private var appLanguage = "en"
    @AppStorage("default_ot_multiplier") private var defaultOTMultiplier = 1.5
    @AppStorage("ot_threshold_hours_per_day") private var otThresholdHoursPerDay = 8.0
    @AppStorage("ss_rate_percent") private var ssRatePercent = 5.0
    @AppStorage("ss_max_monthly_baht") private var ssMaxMonthlyBaht = 750.0
    @AppStorage("enable_tax_withholding") private var enableTaxWithholding = true
    @AppStorage("tax_allowance_baht") private var taxAllowanceBaht = 60000.0

    @State private var payPeriodStart = Date().addingTimeInterval(-2592000)
    @State private var payPeriodEnd = Date()
    @State private var calculatedSlips: [LocalPayrollSlip] = []
    @State private var isCalculating = false
    @State private var showingOTSettings = false

    private var totalNet: Double { calculatedSlips.map(\.netPay).reduce(0, +) }
    private var totalHours: Double { calculatedSlips.map(\.hoursWorked).reduce(0, +) }
    private var totalSSF: Double { calculatedSlips.map(\.ssfDeduction).reduce(0, +) }
    private var totalGross: Double { calculatedSlips.map { $0.basePay + $0.otPay }.reduce(0, +) }

    var body: some View {
        VStack(spacing: 0) {
            periodBar
            Divider().background(Color.appDivider)
            if isCalculating {
                calculatingState
            } else if calculatedSlips.isEmpty {
                emptyState
            } else {
                summaryStrip
                Divider().background(Color.appDivider)
                slipsTable
            }
        }
        .background(Color.appBackground)
        .sheet(isPresented: $showingOTSettings) {
            otSettingsSheet
        }
    }

    // MARK: - Period bar

    private var periodBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "banknote")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: "0F766E"))

            Text("payroll_period_header".t)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.textSecondary)

            DatePicker("", selection: $payPeriodStart, displayedComponents: .date)
                .labelsHidden()
                .font(.system(size: 12))

            Text("–")
                .font(.system(size: 11))
                .foregroundStyle(Color.textTertiary)

            DatePicker("", selection: $payPeriodEnd, displayedComponents: .date)
                .labelsHidden()
                .font(.system(size: 12))

            Spacer()

            Button {
                showingOTSettings = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(Color.appSurfaceHigh, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)

            Button(action: calculatePayroll) {
                if isCalculating {
                    ProgressView().tint(.white).scaleEffect(0.8)
                } else {
                    Label("run_calculations_btn".t, systemImage: "function")
                        .font(.system(size: 11, weight: .bold))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(.white)
            .background(Color(hex: "0F766E"), in: Capsule())
            .disabled(isCalculating)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, APSpacing.md)
        .padding(.vertical, 10)
        .background(Color.appSurface)
    }

    private var summaryStrip: some View {
        HStack(spacing: 16) {
            metric("total_payroll".t, String(format: "%.2f ฿", totalNet), Color.appTeal)
            metric("total_hours".t, String(format: "%.1f hrs", totalHours), Color.textPrimary)
            metric("gross_wages_label".t, String(format: "%.1f ฿", totalGross), Color.textPrimary)
            metric("total_ssf".t, String(format: "%.1f ฿", totalSSF), Color.appRose)
            Spacer()
            Button(action: exportReportPDF) {
                Label("export_report".t, systemImage: "square.and.arrow.up")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .foregroundStyle(.white)
                    .background(APGradient.positive, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, APSpacing.md)
        .padding(.vertical, 8)
        .background(Color.appSurfaceHigh.opacity(0.45))
    }

    private func metric(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Color.textTertiary)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(color)
        }
    }

    private var slipsTable: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("employee_header".t).frame(maxWidth: .infinity, alignment: .leading)
                Text("hours_worked_label".t).frame(width: 72, alignment: .trailing)
                Text("ot_pay_label".t).frame(width: 72, alignment: .trailing)
                Text("ssf_deduction_label".t).frame(width: 72, alignment: .trailing)
                Text("net_pay_label".t).frame(width: 88, alignment: .trailing)
            }
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(Color.textTertiary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Color.appSurface)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(calculatedSlips) { slip in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(slip.employee.firstName) \(slip.employee.lastName)")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.textPrimary)
                                Text(slip.employee.employmentType.capitalized)
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color.textTertiary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Text(String(format: "%.1f", slip.hoursWorked))
                                .frame(width: 72, alignment: .trailing)
                            Text(String(format: "%.1f", slip.otPay))
                                .frame(width: 72, alignment: .trailing)
                            Text(String(format: "-%.1f", slip.ssfDeduction))
                                .foregroundStyle(Color.appRose)
                                .frame(width: 72, alignment: .trailing)
                            Text(String(format: "%.2f ฿", slip.netPay))
                                .fontWeight(.bold)
                                .foregroundStyle(Color.appTeal)
                                .frame(width: 88, alignment: .trailing)
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .overlay(alignment: .bottom) {
                            Divider().background(Color.appDivider)
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "function")
                .font(.system(size: 28))
                .foregroundStyle(Color.textTertiary)
            Text("no_slips_calculated".t)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
            Text("payroll_period_header".t)
                .font(.system(size: 10))
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var calculatingState: some View {
        VStack(spacing: 10) {
            ProgressView().tint(Color(hex: "0F766E"))
            Text("computing_payroll_metrics".t)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func calculatePayroll() {
        isCalculating = true
        calculatedSlips = []

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            var slips: [LocalPayrollSlip] = []
            let ssRate = ssRatePercent / 100.0

            for emp in employees where emp.resignedAt == nil || (emp.resignedAt ?? .distantPast) >= payPeriodStart {
                var hoursWorked = 0.0
                var otHours = 0.0
                var basePay = 0.0
                var otPay = 0.0

                let empCards = allTimecards.filter { card in
                    card.employee?.id == emp.id &&
                    card.status == "approved" &&
                    card.clockIn >= payPeriodStart &&
                    (card.clockOut ?? Date()) <= payPeriodEnd
                }

                for card in empCards {
                    if let clockOut = card.clockOut {
                        let durationHours = clockOut.timeIntervalSince(card.clockIn) / 3600.0
                        let breakHours = Double(card.breakDurationMinutes) / 60.0
                        hoursWorked += max(0.0, durationHours - breakHours)
                        otHours += Double(card.overtimeMinutes) / 60.0
                    }
                }

                if emp.employmentType == "hourly" {
                    basePay = hoursWorked * emp.payRate
                    otPay = otHours * (emp.payRate * defaultOTMultiplier)
                } else if emp.employmentType == "daily" {
                    let calendar = Calendar.current
                    let uniqueDays = Set(empCards.map { calendar.startOfDay(for: $0.clockIn) })
                    basePay = Double(uniqueDays.count) * emp.payRate
                    otPay = otHours * ((emp.payRate / 8.0) * defaultOTMultiplier)
                } else {
                    basePay = emp.payRate
                    otPay = otHours * ((emp.payRate / 240.0) * defaultOTMultiplier)
                }

                let rawSsf = basePay * ssRate
                let ssfDeduction = min(ssMaxMonthlyBaht, rawSsf)
                let netPay = basePay + otPay - ssfDeduction

                slips.append(LocalPayrollSlip(
                    employee: emp,
                    hoursWorked: hoursWorked,
                    basePay: basePay,
                    otPay: otPay,
                    ssfDeduction: ssfDeduction,
                    netPay: netPay
                ))
            }

            calculatedSlips = slips
            isCalculating = false
            APHaptic.trigger()
        }
    }

    private func exportReportPDF() {
        let renderer = ImageRenderer(content: PayrollReportView(slips: calculatedSlips, start: payPeriodStart, end: payPeriodEnd))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Payroll_Report_\(Date().timeIntervalSince1970).pdf")

        renderer.render { size, context in
            var box = CGRect(origin: .zero, size: size)
            guard let pdfContext = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            pdfContext.beginPDFPage(nil)
            context(pdfContext)
            pdfContext.endPDFPage()
            pdfContext.closePDF()

            DispatchQueue.main.async {
                let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let rootVC = windowScene.windows.first?.rootViewController {
                    if let popover = activityVC.popoverPresentationController {
                        popover.sourceView = rootVC.view
                        popover.sourceRect = CGRect(x: rootVC.view.bounds.midX, y: rootVC.view.bounds.midY, width: 0, height: 0)
                        popover.permittedArrowDirections = []
                    }
                    rootVC.present(activityVC, animated: true)
                }
            }
        }
    }

    private var otSettingsSheet: some View {
        NavigationStack {
            Form {
                Section(header: Text("payroll_ot_multiplier_lbl".t)) {
                    Stepper(value: $defaultOTMultiplier, in: 1.0...3.0, step: 0.25) {
                        Text(String(format: "%.2fx", defaultOTMultiplier))
                    }
                    Text("payroll_ot_multiplier_hint".t)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                Section(header: Text("payroll_ot_threshold_lbl".t)) {
                    Stepper(value: $otThresholdHoursPerDay, in: 6.0...10.0, step: 1.0) {
                        Text("\(Int(otThresholdHoursPerDay)) hrs/day")
                    }
                }
                Section(header: Text("payroll_ss_settings_title".t)) {
                    Stepper(value: $ssRatePercent, in: 0.0...10.0, step: 0.5) {
                        Text(String(format: "%.1f%%", ssRatePercent))
                    }
                    HStack {
                        Text("payroll_ss_cap_lbl".t)
                        Spacer()
                        TextField("750", value: $ssMaxMonthlyBaht, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                }
                Section(header: Text("payroll_tax_settings_title".t)) {
                    Toggle("payroll_tax_enable_toggle".t, isOn: $enableTaxWithholding)
                    if enableTaxWithholding {
                        HStack {
                            Text("payroll_tax_allowance_lbl".t)
                            Spacer()
                            TextField("60000", value: $taxAllowanceBaht, format: .number)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 90)
                        }
                    }
                }
            }
            .navigationTitle("payroll_ot_settings_btn".t)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("save_btn_label".t) {
                        showingOTSettings = false
                    }
                }
            }
        }
        .apColorScheme()
    }
}
