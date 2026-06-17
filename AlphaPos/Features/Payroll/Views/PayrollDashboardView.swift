import SwiftUI
import SwiftData

struct PayrollDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Employee.firstName) private var employees: [Employee]
    @Query(sort: \Role.name) private var allRoles: [Role]
    @Query(sort: \Timecard.clockIn, order: .reverse) private var allTimecards: [Timecard]
    
    // Payroll calculation state
    @State private var payPeriodStart = Date().addingTimeInterval(-2592000) // 30 days ago
    @State private var payPeriodEnd = Date()
    @State private var calculatedSlips: [LocalPayrollSlip] = []
    @State private var isCalculating = false
    
    // Tab and sheets states
    @AppStorage("app_language") private var appLanguage = "en"
    @State private var selectedTab = 0 // 0: Timecards, 1: Shifts, 2: Staff
    
    @State private var showingEmployeeSheet = false
    @State private var editingEmployee: Employee? = nil
    
    @State private var showingShiftSheet = false
    @State private var showingCalendarScheduler = false
    @State private var editingShift: EmployeeShift? = nil
    
    @State private var showingTimecardSheet = false
    @State private var editingTimecard: Timecard? = nil
    
    // Form States: Employee
    @State private var empFirstName = ""
    @State private var empLastName = ""
    @State private var empPhone = ""
    @State private var empNationalId = ""
    @State private var empEmploymentType = "hourly"
    @State private var empPayRate = 0.0
    @State private var empBankName = ""
    @State private var empBankAccount = ""
    @State private var empEmail = ""
    @State private var empAddress = ""
    @State private var selectedProvinceId: Int? = nil
    @State private var selectedDistrictId: Int? = nil
    @State private var selectedSubDistrictId: Int? = nil
    @State private var addressDetail = ""
    @State private var postalCode = ""
    @State private var empEmergencyContactName = ""
    @State private var empEmergencyContactPhone = ""
    @State private var empJoinedAt = Date()
    @State private var empResignedAt = Date()
    @State private var hasResigned = false
    @State private var specifyDOB = false
    @State private var empDateOfBirth = Date()
    @State private var enableLoginAccess = false
    @State private var empUsername = ""
    @State private var empPassword = ""
    @State private var empPin = ""
    @State private var empRoleId: UUID? = nil
    @State private var faceEmbeddingData: Data? = nil
    @State private var faceRegisteredAt: Date? = nil
    
    // Form States: Shift
    @State private var shiftEmployeeId: UUID? = nil
    @State private var selectedEmployeeIds: Set<UUID> = []
    @State private var shiftStart = Date()
    @State private var shiftEnd = Date().addingTimeInterval(28800) // +8 hours
    @State private var shiftRole = "Cashier"
    @State private var shiftNotes = ""
    
    // Form States: Timecard
    @State private var tcEmployeeId: UUID? = nil
    @State private var tcClockIn = Date().addingTimeInterval(-28800)
    @State private var tcClockOut = Date()
    @State private var tcBreakMinutes = 0
    @State private var tcOvertimeMinutes = 0
    @State private var tcStatus = "approved"
    @State private var tcNotes = ""

    var body: some View {
        ZStack {
                Color.appBackground.ignoresSafeArea()
                
                HStack(spacing: 0) {
                    // LEFT PANEL: Dynamic tab selections
                    VStack(alignment: .leading, spacing: 0) {
                        Picker("Select View", selection: $selectedTab) {
                            Text("timecard_log".localized(for: appLanguage)).tag(0)
                            Text("shift_planner".localized(for: appLanguage)).tag(1)
                            Text("staff_registry".localized(for: appLanguage)).tag(2)
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .padding()
                        .background(Color.appSurface)
                        
                        Divider().background(Color.appDivider)
                        
                        ScrollView {
                            VStack(alignment: .leading, spacing: 24) {
                                if selectedTab == 0 {
                                    timecardsTab
                                } else if selectedTab == 1 {
                                    shiftsTab
                                } else {
                                    staffTab
                                }
                            }
                            .padding()
                        }
                    }
                    .frame(maxWidth: .infinity)
                    
                    // RIGHT PANEL: Payroll Calculator Engine
                    VStack(spacing: 0) {
                        Text("payroll_engine_title".t)
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.textPrimary)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.appSurfaceHigh)
                        
                        VStack(alignment: .leading, spacing: 20) {
                            Text("payroll_period_header".t)
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.appAccent)
                                .tracking(1.0)
                            
                            VStack(spacing: 12) {
                                DatePicker("Period Start", selection: $payPeriodStart, displayedComponents: .date)
                                    .font(.subheadline)
                                    .foregroundColor(.textPrimary)
                                
                                Divider()
                                    .background(Color.appDivider)
                                
                                DatePicker("Period End", selection: $payPeriodEnd, displayedComponents: .date)
                                    .font(.subheadline)
                                    .foregroundColor(.textPrimary)
                            }
                            .padding()
                            .background(Color.appSurface)
                            .cornerRadius(APRadius.md)
                            .overlay(
                                RoundedRectangle(cornerRadius: APRadius.md)
                                    .stroke(Color.appBorderSubtle, lineWidth: 1)
                            )
                            
                            Button(action: calculatePayroll) {
                                if isCalculating {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Label("run_calculations_btn".t, systemImage: "slider.horizontal.3")
                                }
                            }
                            .apGradientButton(gradient: APGradient.accent, shadow: APShadow.glow, disabled: isCalculating)
                            .disabled(isCalculating)
                        }
                        .padding()
                        .background(Color.appSurfaceHigh.opacity(0.3))
                        
                        Divider()
                            .background(Color.appDivider)
                        
                        // Calculation Outputs
                        if isCalculating {
                            VStack(spacing: 16) {
                                ProgressView()
                                    .tint(.appAccent)
                                    .scaleEffect(1.2)
                                Text("computing_payroll_metrics".t)
                                    .font(.subheadline)
                                    .foregroundColor(.textSecondary)
                            }
                            .frame(maxHeight: .infinity)
                            .frame(maxWidth: .infinity)
                        } else if calculatedSlips.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "percent")
                                    .font(.system(size: 40))
                                    .foregroundColor(.textTertiary)
                                Text("no_slips_calculated".t)
                                    .font(.caption)
                                    .foregroundColor(.textSecondary)
                            }
                            .frame(maxHeight: .infinity)
                        } else {
                            VStack(spacing: 0) {
                                payrollSummaryCard
                                
                                ScrollView {
                                    VStack(spacing: 12) {
                                        ForEach(calculatedSlips) { slip in
                                            VStack(alignment: .leading, spacing: 12) {
                                                HStack {
                                                    VStack(alignment: .leading, spacing: 4) {
                                                        Text("\(slip.employee.firstName) \(slip.employee.lastName)")
                                                            .font(.headline)
                                                            .foregroundColor(.textPrimary)
                                                        Text("\(slip.employee.employmentType.capitalized) • Base: \(slip.employee.payRate, specifier: "%.0f") ฿")
                                                            .font(.caption)
                                                            .foregroundColor(.textSecondary)
                                                    }
                                                    Spacer()
                                                    
                                                    VStack(alignment: .trailing, spacing: 4) {
                                                        Text("net_pay_label".t)
                                                            .font(.system(size: 9, weight: .bold))
                                                            .foregroundColor(.appTeal)
                                                            .tracking(1.0)
                                                        Text("\(slip.netPay, specifier: "%.2f") ฿")
                                                            .font(.headline)
                                                            .fontWeight(.bold)
                                                            .foregroundColor(.appTeal)
                                                    }
                                                }
                                                
                                                Divider()
                                                    .background(Color.appDivider)
                                                
                                                // Detailed columns
                                                HStack(alignment: .center) {
                                                    VStack(alignment: .leading, spacing: 2) {
                                                        Text("hours_worked_label".t)
                                                            .font(.system(size: 8, weight: .bold))
                                                            .foregroundColor(.textSecondary)
                                                        Text("\(slip.hoursWorked, specifier: "%.1f") hrs")
                                                            .font(.caption)
                                                            .fontWeight(.semibold)
                                                            .foregroundColor(.textPrimary)
                                                    }
                                                    Spacer()
                                                    VStack(alignment: .leading, spacing: 2) {
                                                        Text("ot_pay_label".t)
                                                            .font(.system(size: 8, weight: .bold))
                                                            .foregroundColor(.textSecondary)
                                                        Text("\(slip.otPay, specifier: "%.1f") ฿")
                                                            .font(.caption)
                                                            .fontWeight(.semibold)
                                                            .foregroundColor(.textPrimary)
                                                    }
                                                    Spacer()
                                                    VStack(alignment: .leading, spacing: 2) {
                                                        Text("ssf_deduction_label".t)
                                                            .font(.system(size: 8, weight: .bold))
                                                            .foregroundColor(.textSecondary)
                                                        Text("-\(slip.ssfDeduction, specifier: "%.1f") ฿")
                                                            .font(.caption)
                                                            .fontWeight(.semibold)
                                                            .foregroundColor(.appRose)
                                                    }
                                                }
                                            }
                                            .padding()
                                            .background(Color.appSurface)
                                            .cornerRadius(APRadius.md)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: APRadius.md)
                                                    .stroke(Color.appBorderSubtle, lineWidth: 1)
                                            )
                                        }
                                    }
                                    .padding()
                                }
                            }
                            .background(Color.appBackground)
                        }
                    }
                    .frame(width: 420)
                    .background(Color.appSurfaceHigh.opacity(0.5))
                    .overlay(Rectangle().fill(Color.appDivider).frame(width: 1), alignment: .leading)
                }
            }
            .navigationTitle("payroll_shifts_title".t)
            .apNavBar()
            .sheet(isPresented: $showingEmployeeSheet) {
                employeeFormSheet
            }
            .sheet(isPresented: $showingShiftSheet) {
                shiftFormSheet
            }
            .sheet(isPresented: $showingTimecardSheet) {
                timecardFormSheet
            }
            .fullScreenCover(isPresented: $showingCalendarScheduler) {
                ShiftSchedulerCalendarView()
            }
    }
    
    // MARK: - Tabs Subviews
    
    private var timecardsTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Section 1: Pending Audits
            let pendingAudits = allTimecards.filter { $0.status == "pending_audit" }
            VStack(alignment: .leading, spacing: 12) {
                Label {
                    Text("pending_face_scan_audits".t)
                        .foregroundColor(.textPrimary)
                } icon: {
                    Image(systemName: "eye.trianglebadge.exclamationmark")
                        .foregroundColor(.appAmber)
                }
                .font(.headline)
                .fontWeight(.bold)
                
                if pendingAudits.isEmpty {
                    Text("no_pending_biometric_audits".t)
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.appSurfaceHigh)
                        .cornerRadius(APRadius.md)
                        .overlay(
                            RoundedRectangle(cornerRadius: APRadius.md)
                                .stroke(Color.appBorderSubtle, lineWidth: 1)
                        )
                } else {
                    ForEach(pendingAudits) { timecard in
                        pendingAuditRow(timecard)
                    }
                }
            }
            .padding()
            .background(Color.appSurface)
            .cornerRadius(APRadius.lg)
            .overlay(
                RoundedRectangle(cornerRadius: APRadius.lg)
                    .stroke(Color.appBorderSubtle, lineWidth: 1)
            )
            
            // Section 2: Recent Logs & Corrections
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("timecard_log".localized(for: appLanguage))
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.textPrimary)
                    Spacer()
                    Button(action: addTimecardAction) {
                        Label("add_timecard".localized(for: appLanguage), systemImage: "plus.circle.fill")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(APGradient.accent)
                            .clipShape(Capsule())
                    }
                }
                
                if allTimecards.isEmpty {
                    Text("no_clockin_records".t)
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.appSurfaceHigh)
                        .cornerRadius(APRadius.md)
                } else {
                    ForEach(allTimecards.prefix(20)) { card in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(card.employee?.firstName ?? "Staff") \(card.employee?.lastName ?? "")")
                                    .font(.subheadline).fontWeight(.semibold)
                                    .foregroundColor(.textPrimary)
                                HStack(spacing: 8) {
                                    Text(card.clockIn, style: .date)
                                    Text("•")
                                    Text(card.clockIn, style: .time)
                                    if let out = card.clockOut {
                                        Text("→")
                                        Text(out, style: .time)
                                    }
                                }
                                .font(.caption)
                                .foregroundColor(.textSecondary)
                            }
                            Spacer()
                            
                            HStack(spacing: 12) {
                                APBadge(
                                    text: card.status.uppercased(),
                                    color: card.status == "approved" ? .appTeal : (card.status == "rejected" ? .appRose : .appAmber)
                                )
                                
                                Button(action: { editTimecardAction(card) }) {
                                    Image(systemName: "pencil.circle.fill")
                                        .font(.title3)
                                        .foregroundColor(.appAccent)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding()
                        .background(Color.appSurface)
                        .cornerRadius(APRadius.md)
                        .overlay(
                            RoundedRectangle(cornerRadius: APRadius.md)
                                .stroke(Color.appBorderSubtle, lineWidth: 1)
                        )
                    }
                }
            }
        }
    }
    
    private var shiftsTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("shift_planner".localized(for: appLanguage))
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.textPrimary)
                Spacer()
                Button(action: addShiftAction) {
                    Label("schedule_shift".localized(for: appLanguage), systemImage: "plus.circle.fill")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(APGradient.accent)
                        .clipShape(Capsule())
                }
            }
            
            // Calendar Preview Card
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 16) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.title)
                        .foregroundColor(.appAccent)
                        .padding()
                        .background(Color.appAccent.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: APRadius.sm))
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("weekly_calendar_view".localized(for: appLanguage))
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.textPrimary)
                        Text("weekly_calendar_sub".localized(for: appLanguage))
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        APHaptic.trigger()
                        showingCalendarScheduler = true
                    }) {
                        HStack {
                            Image(systemName: "arrow.up.left.and.arrow.down.right.and.arrow.up.right.and.arrow.down.left")
                            Text("open_scheduler".localized(for: appLanguage))
                        }
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(APGradient.accent)
                        .cornerRadius(APRadius.sm)
                        .shadow(color: Color.appAccent.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                }
                .padding()
                .background(Color.appSurface)
                .cornerRadius(APRadius.lg)
                .overlay(
                    RoundedRectangle(cornerRadius: APRadius.lg)
                        .stroke(Color.appBorderSubtle, lineWidth: 1)
                )
            }
            .padding(.bottom, 8)
            
            let shifts = employees.flatMap { $0.shifts }
            if shifts.isEmpty {
                Text("no_shifts_scheduled".t)
                    .foregroundColor(.textSecondary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.appSurface)
                    .cornerRadius(APRadius.lg)
                    .overlay(
                        RoundedRectangle(cornerRadius: APRadius.lg)
                            .stroke(Color.appBorderSubtle, lineWidth: 1)
                    )
            } else {
                ForEach(shifts.sorted(by: { $0.scheduledStart > $1.scheduledStart }).prefix(20)) { shift in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(shift.employee?.firstName ?? "Staff") \(shift.employee?.lastName ?? "")")
                                .font(.headline)
                                .foregroundColor(.textPrimary)
                            Text(shift.role ?? "General Staff")
                                .font(.caption)
                                .foregroundColor(.textSecondary)
                        }
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(shift.scheduledStart, style: .date)
                                .font(.subheadline)
                                .foregroundColor(.textPrimary)
                            Text("\(shift.scheduledStart, style: .time) - \(shift.scheduledEnd, style: .time)")
                                .font(.caption)
                                .foregroundColor(.textSecondary)
                        }
                        
                        Button(action: { editShiftAction(shift) }) {
                            Image(systemName: "pencil.circle.fill")
                                .font(.title3)
                                .foregroundColor(.appAccent)
                        }
                        .padding(.leading, 8)
                        .buttonStyle(.plain)
                    }
                    .padding()
                    .background(Color.appSurface)
                    .cornerRadius(APRadius.lg)
                    .overlay(
                        RoundedRectangle(cornerRadius: APRadius.lg)
                            .stroke(Color.appBorderSubtle, lineWidth: 1)
                    )
                }
            }
        }
    }
    
    private var staffTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("staff_registry".localized(for: appLanguage))
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.textPrimary)
                Spacer()
                Button(action: addEmployeeAction) {
                    Label("add_employee".localized(for: appLanguage), systemImage: "plus.circle.fill")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(APGradient.accent)
                        .clipShape(Capsule())
                }
            }
            
            if employees.isEmpty {
                Text("no_employees_registered".t)
                    .foregroundColor(.textSecondary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.appSurface)
                    .cornerRadius(APRadius.lg)
            } else {
                ForEach(employees) { emp in
                    HStack(spacing: APSpacing.md) {
                        ZStack {
                            Circle().fill(APGradient.accent.opacity(0.15)).frame(width: 44, height: 44)
                            Text(String(emp.firstName.prefix(1)) + String(emp.lastName.prefix(1)))
                                .font(.subheadline).fontWeight(.bold)
                                .foregroundColor(.appAccent)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(emp.firstName) \(emp.lastName)")
                                .font(.subheadline).fontWeight(.bold)
                                .foregroundColor(.textPrimary)
                            Text("\(emp.employmentType.capitalized) • Rate: \(emp.payRate, specifier: "%.0f") ฿")
                                .font(.caption)
                                .foregroundColor(.textSecondary)
                            if let bank = emp.bankName, let acc = emp.bankAccountNumber {
                                Text("\(bank) • \(acc)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.textTertiary)
                            }
                        }
                        Spacer()
                        
                        Button(action: { editEmployeeAction(emp) }) {
                            Image(systemName: "pencil.circle.fill")
                                .font(.title3)
                                .foregroundColor(.appAccent)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding()
                    .background(Color.appSurface)
                    .cornerRadius(APRadius.lg)
                    .overlay(
                        RoundedRectangle(cornerRadius: APRadius.lg)
                            .stroke(Color.appBorderSubtle, lineWidth: 1)
                    )
                }
            }
        }
    }

    private func pendingAuditRow(_ timecard: Timecard) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(timecard.employee?.firstName ?? "Staff") \(timecard.employee?.lastName ?? "")")
                        .font(.headline)
                        .foregroundColor(.textPrimary)
                    Text("Clocked in: \(timecard.clockIn, style: .time)")
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)
                }
                Spacer()
                
                // Match score
                if let confidence = timecard.clockInFaceConfidence {
                    Text("Match: \(confidence, specifier: "%.1f")%")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.appRose)
                }
            }
            
            // Mock Selfie Box
            HStack(spacing: 12) {
                VStack {
                    Image(systemName: "person.crop.square.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.appAccent)
                    Text("reference_label".t)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.textSecondary)
                }
                .frame(width: 70, height: 70)
                .background(Color.appSurface.opacity(0.5))
                .cornerRadius(APRadius.sm)
                .overlay(
                    RoundedRectangle(cornerRadius: APRadius.sm)
                        .stroke(Color.appBorderSubtle, lineWidth: 1)
                )
                
                Image(systemName: "arrow.left.and.right")
                    .foregroundColor(.textSecondary)
                
                VStack {
                    Image(systemName: "person.crop.square")
                        .font(.system(size: 32))
                        .foregroundColor(.appRose)
                    Text("selfie_scan_label".t)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.textSecondary)
                }
                .frame(width: 70, height: 70)
                .background(Color.appSurface.opacity(0.5))
                .cornerRadius(APRadius.sm)
                .overlay(
                    RoundedRectangle(cornerRadius: APRadius.sm)
                        .stroke(Color.appBorderSubtle, lineWidth: 1)
                )
                
                Spacer()
                
                // Verify action buttons
                VStack(spacing: 8) {
                    Button(action: { approveTimecard(timecard) }) {
                        Text("verify_match_btn".t)
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(APGradient.positive)
                            .cornerRadius(APRadius.sm)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Button(action: { rejectTimecard(timecard) }) {
                        Text("reject_btn_label".t)
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.appSurface)
                            .cornerRadius(APRadius.sm)
                            .overlay(
                                RoundedRectangle(cornerRadius: APRadius.sm)
                                    .stroke(Color.appBorderSubtle, lineWidth: 1)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding()
        .background(Color.appSurfaceHigh)
        .cornerRadius(APRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: APRadius.md)
                .stroke(Color.appBorderSubtle, lineWidth: 1)
        )
    }
    
    // MARK: - Right Panel summary card
    
    private var payrollSummaryCard: some View {
        let totalWages = calculatedSlips.map { $0.basePay + $0.otPay }.reduce(0, +)
        let totalDeductions = calculatedSlips.map { $0.ssfDeduction }.reduce(0, +)
        let totalNetPay = calculatedSlips.map { $0.netPay }.reduce(0, +)
        let totalHours = calculatedSlips.map { $0.hoursWorked }.reduce(0, +)
        
        return VStack(spacing: 12) {
            HStack {
                Text("total_payroll".localized(for: appLanguage).uppercased())
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.textSecondary)
                Spacer()
                Text("export_report".localized(for: appLanguage).uppercased())
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.textSecondary)
            }
            
            HStack(alignment: .firstTextBaseline) {
                Text("\(totalNetPay, specifier: "%.2f") ฿")
                    .font(.title2)
                    .fontWeight(.black)
                    .foregroundColor(.appTeal)
                Spacer()
                
                Button(action: exportReportPDF) {
                    Label("export_report".localized(for: appLanguage), systemImage: "square.and.arrow.up")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(APGradient.positive)
                        .clipShape(Capsule())
                }
            }
            
            Divider().background(Color.appDivider)
            
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("total_hours".localized(for: appLanguage))
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.textTertiary)
                    Text("\(totalHours, specifier: "%.1f") hrs")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.textPrimary)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 2) {
                    Text("total_ssf".localized(for: appLanguage))
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.textTertiary)
                    Text("\(totalDeductions, specifier: "%.1f") ฿")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.appRose)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("gross_wages_label".t)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.textTertiary)
                    Text("\(totalWages, specifier: "%.1f") ฿")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.textPrimary)
                }
            }
        }
        .padding()
        .background(Color.appSurface)
        .cornerRadius(APRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: APRadius.md)
                .stroke(Color.appBorderSubtle, lineWidth: 1)
        )
        .padding(.horizontal)
        .padding(.top)
    }

    // MARK: - Actions & Calculations
    
    private func approveTimecard(_ timecard: Timecard) {
        timecard.status = "approved"
        timecard.updatedAt = Date()
        timecard.isSynced = false
        try? modelContext.save()
    }
    
    private func rejectTimecard(_ timecard: Timecard) {
        timecard.status = "rejected"
        timecard.updatedAt = Date()
        timecard.isSynced = false
        try? modelContext.save()
    }
    
    private func calculatePayroll() {
        isCalculating = true
        calculatedSlips = []
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            var slips: [LocalPayrollSlip] = []
            
            for emp in employees {
                var hoursWorked = 0.0
                var otHours = 0.0
                var basePay = 0.0
                var otPay = 0.0
                var ssfDeduction = 0.0
                var netPay = 0.0
                
                // Fetch approved timecards inside range
                let empCards = allTimecards.filter { card in
                    card.employee?.id == emp.id &&
                    card.status == "approved" &&
                    card.clockIn >= payPeriodStart &&
                    (card.clockOut ?? Date()) <= payPeriodEnd
                }
                
                // Calculate hours worked
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
                    otPay = otHours * (emp.payRate * 1.5)
                } else if emp.employmentType == "daily" {
                    let calendar = Calendar.current
                    let uniqueDays = Set(empCards.map { calendar.startOfDay(for: $0.clockIn) })
                    let daysWorked = Double(uniqueDays.count)
                    basePay = daysWorked * emp.payRate
                    otPay = otHours * ((emp.payRate / 8.0) * 1.5)
                } else {
                    basePay = emp.payRate
                    otPay = otHours * ((emp.payRate / 240.0) * 1.5)
                }
                
                // Social Security Fund Cap (Thai Regulations: 5%, max 750 THB)
                let rawSsf = basePay * 0.05
                ssfDeduction = min(750.00, rawSsf)
                
                netPay = basePay + otPay - ssfDeduction
                
                let slip = LocalPayrollSlip(
                    employee: emp,
                    hoursWorked: hoursWorked,
                    basePay: basePay,
                    otPay: otPay,
                    ssfDeduction: ssfDeduction,
                    netPay: netPay
                )
                slips.append(slip)
            }
            
            self.calculatedSlips = slips
            self.isCalculating = false
            APHaptic.trigger()
        }
    }
    
    private func updateFullAddress() {
        guard let pId = selectedProvinceId,
              let province = ThailandAddressManager.shared.provinces.first(where: { $0.id == pId }) else {
            empAddress = addressDetail
            return
        }
        
        let pName = province.displayName(for: appLanguage)
        var fullAddress = addressDetail
        
        if let dId = selectedDistrictId,
           let district = province.districts.first(where: { $0.id == dId }) {
            let dName = district.displayName(for: appLanguage)
            let isBangkok = (pId == 1)
            
            if isBangkok {
                fullAddress += " " + (appLanguage == "th" ? "เขต" : "") + dName
            } else {
                fullAddress += " " + (appLanguage == "th" ? "อ." : "Amphur ") + dName
            }
            
            if let sId = selectedSubDistrictId,
               let sub = district.subDistricts.first(where: { $0.id == sId }) {
                let sName = sub.displayName(for: appLanguage)
                
                if isBangkok {
                    fullAddress += " " + (appLanguage == "th" ? "แขวง" : "") + sName
                } else {
                    fullAddress += " " + (appLanguage == "th" ? "ต." : "Tambon ") + sName
                }
                
                fullAddress += " " + pName
                
                if !postalCode.isEmpty {
                    fullAddress += " " + postalCode
                }
            }
        }
        
        empAddress = fullAddress
    }
    
    // MARK: - CRUD Form Actions
    
    private func editEmployeeAction(_ employee: Employee) {
        editingEmployee = employee
        empFirstName = employee.firstName
        empLastName = employee.lastName
        empPhone = employee.phone ?? ""
        empNationalId = employee.nationalId ?? ""
        empEmploymentType = employee.employmentType
        empPayRate = employee.payRate
        empBankName = employee.bankName ?? ""
        empBankAccount = employee.bankAccountNumber ?? ""
        
        empEmail = employee.email ?? ""
        empAddress = employee.address ?? ""
        selectedProvinceId = nil
        selectedDistrictId = nil
        selectedSubDistrictId = nil
        postalCode = ""
        addressDetail = employee.address ?? ""
        empEmergencyContactName = employee.emergencyContactName ?? ""
        empEmergencyContactPhone = employee.emergencyContactPhone ?? ""
        empJoinedAt = employee.joinedAt
        
        if let res = employee.resignedAt {
            hasResigned = true
            empResignedAt = res
        } else {
            hasResigned = false
            empResignedAt = Date()
        }
        
        if let dob = employee.dateOfBirth {
            specifyDOB = true
            empDateOfBirth = dob
        } else {
            specifyDOB = false
            empDateOfBirth = Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date()
        }
        
        if let user = employee.user {
            enableLoginAccess = true
            empUsername = user.username
            empPassword = "" // Secure
            empPin = "" // Leave empty for security and edit flow
            empRoleId = user.role?.id
        } else {
            enableLoginAccess = false
            empUsername = ""
            empPassword = ""
            empPin = ""
            empRoleId = nil
        }
        
        faceEmbeddingData = employee.faceEmbeddingData
        faceRegisteredAt = employee.faceRegisteredAt
        
        showingEmployeeSheet = true
    }
    
    private func addEmployeeAction() {
        editingEmployee = nil
        empFirstName = ""
        empLastName = ""
        empPhone = ""
        empNationalId = ""
        empEmploymentType = "hourly"
        empPayRate = 0.0
        empBankName = ""
        empBankAccount = ""
        
        empEmail = ""
        empAddress = ""
        selectedProvinceId = nil
        selectedDistrictId = nil
        selectedSubDistrictId = nil
        postalCode = ""
        addressDetail = ""
        empEmergencyContactName = ""
        empEmergencyContactPhone = ""
        empJoinedAt = Date()
        empResignedAt = Date()
        hasResigned = false
        specifyDOB = false
        empDateOfBirth = Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date()
        enableLoginAccess = false
        empUsername = ""
        empPassword = ""
        empPin = ""
        empRoleId = nil
        faceEmbeddingData = nil
        faceRegisteredAt = nil
        
        showingEmployeeSheet = true
    }
    
    private func saveEmployee() {
        let selectedRole = allRoles.first(where: { $0.id == empRoleId })
        let targetEmp: Employee
        
        if let emp = editingEmployee {
            emp.firstName = empFirstName
            emp.lastName = empLastName
            emp.phone = empPhone.isEmpty ? nil : empPhone
            emp.nationalId = empNationalId.isEmpty ? nil : empNationalId
            emp.employmentType = empEmploymentType
            emp.payRate = empPayRate
            emp.bankName = empBankName.isEmpty ? nil : empBankName
            emp.bankAccountNumber = empBankAccount.isEmpty ? nil : empBankAccount
            
            emp.email = empEmail.isEmpty ? nil : empEmail
            emp.address = empAddress.isEmpty ? nil : empAddress
            emp.emergencyContactName = empEmergencyContactName.isEmpty ? nil : empEmergencyContactName
            emp.emergencyContactPhone = empEmergencyContactPhone.isEmpty ? nil : empEmergencyContactPhone
            emp.joinedAt = empJoinedAt
            emp.resignedAt = hasResigned ? empResignedAt : nil
            emp.dateOfBirth = specifyDOB ? empDateOfBirth : nil
            
            emp.faceEmbeddingData = faceEmbeddingData
            emp.faceRegisteredAt = faceEmbeddingData == nil ? nil : (faceRegisteredAt ?? Date())
            
            emp.updatedAt = Date()
            emp.isSynced = false
            targetEmp = emp
        } else {
            let newEmp = Employee(
                firstName: empFirstName,
                lastName: empLastName,
                phone: empPhone.isEmpty ? nil : empPhone,
                nationalId: empNationalId.isEmpty ? nil : empNationalId,
                bankAccountNumber: empBankAccount.isEmpty ? nil : empBankAccount,
                bankName: empBankName.isEmpty ? nil : empBankName,
                employmentType: empEmploymentType,
                payRate: empPayRate,
                joinedAt: empJoinedAt,
                resignedAt: hasResigned ? empResignedAt : nil,
                faceEmbeddingData: faceEmbeddingData,
                faceRegisteredAt: faceEmbeddingData == nil ? nil : (faceRegisteredAt ?? Date()),
                email: empEmail.isEmpty ? nil : empEmail,
                dateOfBirth: specifyDOB ? empDateOfBirth : nil,
                address: empAddress.isEmpty ? nil : empAddress,
                emergencyContactName: empEmergencyContactName.isEmpty ? nil : empEmergencyContactName,
                emergencyContactPhone: empEmergencyContactPhone.isEmpty ? nil : empEmergencyContactPhone
            )
            modelContext.insert(newEmp)
            targetEmp = newEmp
        }
        
        if enableLoginAccess {
            let userEmail = empEmail.isEmpty ? nil : empEmail
            
            if let user = targetEmp.user {
                user.username = empUsername.lowercased()
                user.email = userEmail
                user.role = selectedRole
                if !empPin.isEmpty {
                    user.pinCodeHash = SecurityHelper.sha256(empPin)
                }
                if !empPassword.isEmpty {
                    user.passwordHash = SecurityHelper.sha256(empPassword)
                }
                user.updatedAt = Date()
                user.isSynced = false
            } else {
                let pHash = empPassword.isEmpty ? "default_hash" : SecurityHelper.sha256(empPassword)
                let pinValue = empPin.isEmpty ? nil : SecurityHelper.sha256(empPin)
                let newUser = User(
                    username: empUsername.lowercased(),
                    email: userEmail,
                    passwordHash: pHash,
                    pinCodeHash: pinValue,
                    role: selectedRole
                )
                modelContext.insert(newUser)
                targetEmp.user = newUser
            }
        } else {
            if let user = targetEmp.user {
                modelContext.delete(user)
                targetEmp.user = nil
            }
        }
        
        try? modelContext.save()
        showingEmployeeSheet = false
        editingEmployee = nil
        
        // Trigger background sync task to upload the new/updated employee
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }
    
    private func editShiftAction(_ shift: EmployeeShift) {
        editingShift = shift
        shiftEmployeeId = shift.employee?.id
        selectedEmployeeIds = []
        if let empId = shift.employee?.id {
            selectedEmployeeIds.insert(empId)
        }
        shiftStart = shift.scheduledStart
        shiftEnd = shift.scheduledEnd
        shiftRole = shift.role ?? ""
        shiftNotes = shift.notes ?? ""
        showingShiftSheet = true
    }
    
    private func addShiftAction() {
        editingShift = nil
        shiftEmployeeId = employees.first?.id
        selectedEmployeeIds = []
        if let firstEmpId = employees.first?.id {
            selectedEmployeeIds.insert(firstEmpId)
        }
        shiftStart = Date()
        shiftEnd = Date().addingTimeInterval(28800)
        shiftRole = "Cashier"
        shiftNotes = ""
        showingShiftSheet = true
    }
    
    private func saveShift() {
        if let sh = editingShift {
            guard let empId = shiftEmployeeId,
                  let emp = employees.first(where: { $0.id == empId }) else { return }
            sh.employee = emp
            sh.scheduledStart = shiftStart
            sh.scheduledEnd = shiftEnd
            sh.role = shiftRole.isEmpty ? nil : shiftRole
            sh.notes = shiftNotes.isEmpty ? nil : shiftNotes
            sh.updatedAt = Date()
            sh.isSynced = false
        } else {
            for empId in selectedEmployeeIds {
                if let emp = employees.first(where: { $0.id == empId }) {
                    let newShift = EmployeeShift(
                        employee: emp,
                        scheduledStart: shiftStart,
                        scheduledEnd: shiftEnd,
                        role: shiftRole.isEmpty ? nil : shiftRole,
                        notes: shiftNotes.isEmpty ? nil : shiftNotes
                    )
                    modelContext.insert(newShift)
                }
            }
        }
        try? modelContext.save()
        showingShiftSheet = false
        editingShift = nil
    }
    
    private func editTimecardAction(_ timecard: Timecard) {
        editingTimecard = timecard
        tcEmployeeId = timecard.employee?.id
        tcClockIn = timecard.clockIn
        tcClockOut = timecard.clockOut ?? Date()
        tcBreakMinutes = timecard.breakDurationMinutes
        tcOvertimeMinutes = timecard.overtimeMinutes
        tcStatus = timecard.status
        tcNotes = timecard.notes ?? ""
        showingTimecardSheet = true
    }
    
    private func addTimecardAction() {
        editingTimecard = nil
        tcEmployeeId = employees.first?.id
        tcClockIn = Date().addingTimeInterval(-28800)
        tcClockOut = Date()
        tcBreakMinutes = 0
        tcOvertimeMinutes = 0
        tcStatus = "approved"
        tcNotes = ""
        showingTimecardSheet = true
    }
    
    private func saveTimecard() {
        guard let empId = tcEmployeeId,
              let emp = employees.first(where: { $0.id == empId }) else { return }
              
        if let tc = editingTimecard {
            tc.employee = emp
            tc.clockIn = tcClockIn
            tc.clockOut = tcClockOut
            tc.breakDurationMinutes = tcBreakMinutes
            tc.overtimeMinutes = tcOvertimeMinutes
            tc.status = tcStatus
            tc.notes = tcNotes.isEmpty ? nil : tcNotes
            tc.updatedAt = Date()
            tc.isSynced = false
        } else {
            let newTc = Timecard(
                employee: emp,
                clockIn: tcClockIn,
                clockOut: tcClockOut,
                breakDurationMinutes: tcBreakMinutes,
                overtimeMinutes: tcOvertimeMinutes,
                status: tcStatus,
                notes: tcNotes.isEmpty ? nil : tcNotes
            )
            modelContext.insert(newTc)
        }
        try? modelContext.save()
        showingTimecardSheet = false
        editingTimecard = nil
    }
    
    // MARK: - PDF Exporter Core using SwiftUI ImageRenderer
    
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
            
            // Native Share sheet trigger
            DispatchQueue.main.async {
                let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let rootVC = windowScene.windows.first?.rootViewController {
                    if let popover = activityVC.popoverPresentationController {
                        popover.sourceView = rootVC.view
                        popover.sourceRect = CGRect(x: rootVC.view.bounds.midX, y: rootVC.view.bounds.midY, width: 0, height: 0)
                        popover.permittedArrowDirections = []
                    }
                    rootVC.present(activityVC, animated: true, completion: nil)
                }
            }
        }
    }
    
    // MARK: - CRUD Form Sheets Views
    
    private var employeeFormSheet: some View {
        NavigationStack {
            Form {
                Section(header: Text("personal_info_header".t)) {
                    TextField("First Name", text: $empFirstName)
                    TextField("Last Name", text: $empLastName)
                    TextField("Phone Number", text: $empPhone)
                        .keyboardType(.phonePad)
                    TextField("National ID / Passport", text: $empNationalId)
                    TextField("Email Address", text: $empEmail)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                
                Section(header: Text("additional_details_hr_header".t)) {
                    Toggle("Specify Date of Birth", isOn: $specifyDOB)
                    if specifyDOB {
                        DatePicker("Date of Birth", selection: $empDateOfBirth, displayedComponents: .date)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("home_address_header".t)
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.appAccent)
                        
                        TextField("House No., Street, Soi, Road", text: $addressDetail)
                            .onChange(of: addressDetail) { _, _ in updateFullAddress() }
                        
                        HStack(spacing: 12) {
                            Picker("Province", selection: $selectedProvinceId) {
                                Text("select_province_placeholder".t).tag(nil as Int?)
                                ForEach(ThailandAddressManager.shared.provinces) { prov in
                                    Text(prov.displayName(for: appLanguage)).tag(prov.id as Int?)
                                }
                            }
                            .onChange(of: selectedProvinceId) { _, _ in
                                selectedDistrictId = nil
                                selectedSubDistrictId = nil
                                postalCode = ""
                                updateFullAddress()
                            }
                            
                            let availableDistricts = ThailandAddressManager.shared.provinces.first(where: { $0.id == selectedProvinceId })?.districts ?? []
                            
                            Picker("District", selection: $selectedDistrictId) {
                                Text("select_district_placeholder".t).tag(nil as Int?)
                                ForEach(availableDistricts) { dist in
                                    Text(dist.displayName(for: appLanguage)).tag(dist.id as Int?)
                                }
                            }
                            .disabled(selectedProvinceId == nil)
                            .onChange(of: selectedDistrictId) { _, _ in
                                selectedSubDistrictId = nil
                                postalCode = ""
                                updateFullAddress()
                            }
                        }
                        
                        HStack(spacing: 12) {
                            let province = ThailandAddressManager.shared.provinces.first(where: { $0.id == selectedProvinceId })
                            let availableSubDistricts = province?.districts.first(where: { $0.id == selectedDistrictId })?.subDistricts ?? []
                            
                            Picker("Subdistrict", selection: $selectedSubDistrictId) {
                                Text("select_subdistrict_placeholder".t).tag(nil as Int?)
                                ForEach(availableSubDistricts) { sub in
                                    Text(sub.displayName(for: appLanguage)).tag(sub.id as Int?)
                                }
                            }
                            .disabled(selectedDistrictId == nil)
                            .onChange(of: selectedSubDistrictId) { _, newSubId in
                                if let sub = availableSubDistricts.first(where: { $0.id == newSubId }) {
                                    postalCode = String(sub.zipCode)
                                } else {
                                    postalCode = ""
                                }
                                updateFullAddress()
                            }
                            
                            TextField("Postal Code", text: $postalCode)
                                .keyboardType(.numberPad)
                                .disabled(true)
                                .frame(width: 120)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("emergency_contact_header".t)
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.appAccent)
                        
                        TextField("Contact Person Name", text: $empEmergencyContactName)
                        TextField("Contact Phone Number", text: $empEmergencyContactPhone)
                            .keyboardType(.phonePad)
                    }
                }
                
                Section(header: Text("compensation_start_date_header".t)) {
                    Picker("Employment Type", selection: $empEmploymentType) {
                        Text("hourly_pay_type".t).tag("hourly")
                        Text("daily_pay_type".t).tag("daily")
                        Text("monthly_fixed_pay_type".t).tag("monthly")
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    
                    HStack {
                        Text("pay_rate_label".t)
                        Spacer()
                        TextField("Amount", value: $empPayRate, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    DatePicker("Start Date (Joined)", selection: $empJoinedAt, displayedComponents: .date)
                    
                    Toggle("Has Resigned / Terminated", isOn: $hasResigned)
                    if hasResigned {
                        DatePicker("End Date (Resigned)", selection: $empResignedAt, displayedComponents: .date)
                    }
                }
                
                Section(header: Text("banking_details_header".t)) {
                    Picker("bank_name".localized(for: appLanguage), selection: $empBankName) {
                        Text("select_bank".localized(for: appLanguage)).tag("")
                        ForEach(thaiBanks) { bank in
                            Text(bank.displayName(for: appLanguage)).tag(bank.id)
                        }
                    }
                    TextField("Account Number", text: $empBankAccount)
                        .keyboardType(.numberPad)
                }
                
                Section(header: Text("system_access_credentials_header".t)) {
                    Toggle("Enable Waitstaff App Access", isOn: $enableLoginAccess)
                    
                    if enableLoginAccess {
                        TextField("Username", text: $empUsername)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        
                        SecureField(editingEmployee == nil ? "Password" : "New Password (Optional)", text: $empPassword)
                            .textInputAutocapitalization(.never)
                        
                        TextField(editingEmployee == nil ? "Login PIN (4-6 Digits)" : "New PIN (Optional)", text: $empPin)
                            .keyboardType(.numberPad)
                        
                        Picker("Access Role", selection: $empRoleId) {
                            Text("no_system_role".t).tag(nil as UUID?)
                            ForEach(allRoles) { role in
                                Text(role.name).tag(role.id as UUID?)
                            }
                        }
                    }
                }
                
                Section(header: Text("biometrics_faceid_scanner_header".t)) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("face_scanner_biometrics_title".t)
                                .fontWeight(.semibold)
                            if faceEmbeddingData != nil {
                                Text("face_id_registered_status".t)
                                    .font(.caption)
                                    .foregroundColor(.appTeal)
                                if let regDate = faceRegisteredAt {
                                    Text("Enrolled on \(regDate.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.system(size: 10))
                                        .foregroundColor(.textSecondary)
                                }
                            } else {
                                Text("face_id_not_registered_status".t)
                                    .font(.caption)
                                    .foregroundColor(.appRose)
                                Text("face_id_enroll_desc".t)
                                    .font(.system(size: 10))
                                    .foregroundColor(.textSecondary)
                                    .lineLimit(2)
                            }
                        }
                        
                        Spacer()
                        
                        if faceEmbeddingData != nil {
                            Button(role: .destructive, action: {
                                APHaptic.trigger()
                                faceEmbeddingData = nil
                                faceRegisteredAt = nil
                            }) {
                                Text("reset_clear_btn".t)
                                    .font(.caption)
                                    .fontWeight(.bold)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(editingEmployee == nil ? "add_employee".localized(for: appLanguage) : "edit_employee".localized(for: appLanguage))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.Common.cancel.t) {
                        showingEmployeeSheet = false
                        editingEmployee = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("save_btn_label".t) {
                        saveEmployee()
                    }
                    .disabled(empFirstName.isEmpty || empLastName.isEmpty || (enableLoginAccess && empUsername.isEmpty))
                }
            }
        }
        .apColorScheme()
    }
    
    private var roleSuggestions: [String] {
        if appLanguage == "th" {
            return ["แคชเชียร์", "กุ๊ก/คนครัว", "พนักงานเสิร์ฟ", "ผู้จัดการ", "บาริสต้า", "พนักงานทำความสะอาด"]
        } else {
            return ["Cashier", "Cook", "Waiter", "Manager", "Barista", "Cleaner"]
        }
    }

    private var shiftFormSheet: some View {
        NavigationStack {
            Form {
                if editingShift == nil {
                    Section(header: Text("select_employees_batch".localized(for: appLanguage))) {
                        HStack {
                            Button(action: {
                                selectedEmployeeIds = Set(employees.map { $0.id })
                            }) {
                                Text("select_all".localized(for: appLanguage))
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.appAccent)
                            }
                            .buttonStyle(.borderless)
                            
                            Spacer()
                            
                            Button(action: {
                                selectedEmployeeIds.removeAll()
                            }) {
                                Text("clear_all".localized(for: appLanguage))
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.appRose)
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.vertical, 4)
                        
                        ForEach(employees) { emp in
                            HStack {
                                Text("\(emp.firstName) \(emp.lastName)")
                                    .foregroundColor(.textPrimary)
                                Spacer()
                                if selectedEmployeeIds.contains(emp.id) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.appAccent)
                                } else {
                                    Image(systemName: "circle")
                                        .foregroundColor(.textTertiary)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if selectedEmployeeIds.contains(emp.id) {
                                    selectedEmployeeIds.remove(emp.id)
                                } else {
                                    selectedEmployeeIds.insert(emp.id)
                                }
                            }
                        }
                    }
                } else {
                    Section(header: Text("employee_header".localized(for: appLanguage))) {
                        Picker("Select Employee", selection: $shiftEmployeeId) {
                            Text("choose_dropdown_placeholder".t).tag(nil as UUID?)
                            ForEach(employees) { emp in
                                Text("\(emp.firstName) \(emp.lastName)").tag(emp.id as UUID?)
                            }
                        }
                    }
                }
                
                Section(header: Text("time_date_header".localized(for: appLanguage))) {
                    DatePicker("starts_field".localized(for: appLanguage), selection: $shiftStart)
                    DatePicker("ends_field".localized(for: appLanguage), selection: $shiftEnd)
                }
                
                Section(header: Text("role_notes_header".localized(for: appLanguage))) {
                    HStack {
                        TextField("role_field_placeholder".localized(for: appLanguage), text: $shiftRole)
                        Menu {
                            ForEach(roleSuggestions, id: \.self) { role in
                                Button(role) {
                                    shiftRole = role
                                }
                            }
                        } label: {
                            Image(systemName: "tag.circle.fill")
                                .foregroundColor(.appAccent)
                                .font(.title3)
                        }
                    }
                    TextField("notes_field".localized(for: appLanguage), text: $shiftNotes)
                }
            }
            .navigationTitle(editingShift == nil ? "schedule_shift".localized(for: appLanguage) : "Edit Shift")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel_btn".localized(for: appLanguage)) {
                        showingShiftSheet = false
                        editingShift = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("save_btn".localized(for: appLanguage)) {
                        saveShift()
                    }
                    .disabled(editingShift == nil ? (selectedEmployeeIds.isEmpty || shiftStart >= shiftEnd) : (shiftEmployeeId == nil || shiftStart >= shiftEnd))
                }
            }
        }
        .apColorScheme()
    }
    
    private var timecardFormSheet: some View {
        NavigationStack {
            Form {
                Section(header: Text("employee_header_title".t)) {
                    Picker("Select Employee", selection: $tcEmployeeId) {
                        Text("choose_dropdown_placeholder".t).tag(nil as UUID?)
                        ForEach(employees) { emp in
                            Text("\(emp.firstName) \(emp.lastName)").tag(emp.id as UUID?)
                        }
                    }
                }
                
                Section(header: Text("shift_duration_header".t)) {
                    DatePicker("Clock In", selection: $tcClockIn)
                    DatePicker("Clock Out", selection: $tcClockOut)
                }
                
                Section(header: Text("break_overtime_header".t)) {
                    HStack {
                        Text("break_minutes_label".t)
                        Spacer()
                        TextField("Minutes", value: $tcBreakMinutes, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("overtime_minutes_label".t)
                        Spacer()
                        TextField("Minutes", value: $tcOvertimeMinutes, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
                
                Section(header: Text("review_status_header".t)) {
                    Picker("Status", selection: $tcStatus) {
                        Text("approved_status_tag".t).tag("approved")
                        Text("pending_status_tag".t).tag("pending_audit")
                        Text("rejected_status_tag".t).tag("rejected")
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    
                    TextField("Manager Notes", text: $tcNotes)
                }
            }
            .navigationTitle(editingTimecard == nil ? "add_timecard".localized(for: appLanguage) : "Edit Timecard")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.Common.cancel.t) {
                        showingTimecardSheet = false
                        editingTimecard = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("save_btn_label".t) {
                        saveTimecard()
                    }
                    .disabled(tcEmployeeId == nil || tcClockIn >= tcClockOut)
                }
            }
        }
        .apColorScheme()
    }
}

// MARK: - PDF Document Layout View

struct PayrollReportView: View {
    let slips: [LocalPayrollSlip]
    let start: Date
    let end: Date
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("payroll_report_title".t)
                .font(.title).fontWeight(.bold)
                .foregroundColor(.black)
                
            Text("Period: \(start.formatted(date: .numeric, time: .omitted)) - \(end.formatted(date: .numeric, time: .omitted))")
                .font(.subheadline)
                .foregroundColor(.gray)
                
            Divider()
            
            // Slips Table
            VStack(spacing: 12) {
                ForEach(slips) { slip in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(slip.employee.firstName) \(slip.employee.lastName)")
                                .fontWeight(.bold)
                                .foregroundColor(.black)
                            Text(slip.employee.employmentType.capitalized)
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Net Pay: \(slip.netPay, specifier: "%.2f") ฿")
                                .fontWeight(.bold)
                                .foregroundColor(.black)
                            Text("Hours: \(slip.hoursWorked, specifier: "%.1f")")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                    Divider()
                }
            }
            
            Spacer()
        }
        .padding(40)
        .frame(width: 612, height: 792) // standard US Letter size
        .background(Color.white)
    }
}

// MARK: - Local helper model struct to present calculated values

struct LocalPayrollSlip: Identifiable {
    let id = UUID()
    let employee: Employee
    let hoursWorked: Double
    let basePay: Double
    let otPay: Double
    let ssfDeduction: Double
    let netPay: Double
}

// MARK: - Local Translation Dictionary Extension


// MARK: - Thai Bank Model & List

struct ThaiBank: Identifiable, Hashable {
    let id: String
    let code: String
    let englishName: String
    let thaiName: String
    
    func displayName(for language: String) -> String {
        let name = (language == "th" ? thaiName : englishName)
        return "\(code) - \(name)"
    }
}

let thaiBanks: [ThaiBank] = [
    ThaiBank(id: "BBL", code: "BBL", englishName: "Bangkok Bank", thaiName: "ธนาคารกรุงเทพ"),
    ThaiBank(id: "KBANK", code: "KBANK", englishName: "Kasikornbank", thaiName: "ธนาคารกสิกรไทย"),
    ThaiBank(id: "SCB", code: "SCB", englishName: "Siam Commercial Bank", thaiName: "ธนาคารไทยพาณิชย์"),
    ThaiBank(id: "KTB", code: "KTB", englishName: "Krungthai Bank", thaiName: "ธนาคารกรุงไทย"),
    ThaiBank(id: "BAY", code: "BAY", englishName: "Krungsri (Bank of Ayudhya)", thaiName: "ธนาคารกรุงศรีอยุธยา"),
    ThaiBank(id: "TTB", code: "TTB", englishName: "TMBThanachart Bank", thaiName: "ธนาคารทหารไทยธนชาต"),
    ThaiBank(id: "UOB", code: "UOB", englishName: "UOB Bank", thaiName: "ธนาคารยูโอบี"),
    ThaiBank(id: "KKP", code: "KKP", englishName: "Kiatnakin Phatra Bank", thaiName: "ธนาคารเกียรตินาคินภัทร"),
    ThaiBank(id: "LHB", code: "LH Bank", englishName: "LH Bank", thaiName: "ธนาคารแลนด์ แอนด์ เฮ้าส์"),
    ThaiBank(id: "CIMBT", code: "CIMB", englishName: "CIMB Thai Bank", thaiName: "ธนาคารซีไอเอ็มบีไทย"),
    ThaiBank(id: "TISCO", code: "TISCO", englishName: "Tisco Bank", thaiName: "ธนาคารทิสโก้"),
    ThaiBank(id: "ICBCT", code: "ICBC", englishName: "ICBC Bank (Thailand)", thaiName: "ธนาคารไอซีบีซี (ไทย)"),
    ThaiBank(id: "GSB", code: "GSB", englishName: "Government Savings Bank", thaiName: "ธนาคารออมสิน"),
    ThaiBank(id: "BAAC", code: "BAAC", englishName: "Bank for Agriculture and Agricultural Cooperatives", thaiName: "ธนาคารเพื่อการเกษตรและสหกรณ์การเกษตร (ธ.ก.ส.)"),
    ThaiBank(id: "GHB", code: "GHB", englishName: "Government Housing Bank", thaiName: "ธนาคารอาคารสงเคราะห์"),
    ThaiBank(id: "EXIM", code: "EXIM", englishName: "EXIM Bank of Thailand", thaiName: "ธนาคารเพื่อการส่งออกและนำเข้าแห่งประเทศไทย"),
    ThaiBank(id: "SME", code: "SME", englishName: "SME D Bank", thaiName: "ธนาคารพัฒนาวิสาหกิจขนาดกลางและขนาดย่อม"),
    ThaiBank(id: "ISBT", code: "ISBT", englishName: "Islamic Bank of Thailand", thaiName: "ธนาคารอิสลามแห่งประเทศไทย")
]


// MARK: - Thailand Address Models & Manager

struct ThaiProvince: Codable, Identifiable, Hashable {
    let id: Int
    let nameTh: String
    let nameEn: String
    let districts: [ThaiDistrict]
    
    enum CodingKeys: String, CodingKey {
        case id
        case nameTh = "name_th"
        case nameEn = "name_en"
        case districts
    }
    
    func displayName(for language: String) -> String {
        return language == "th" ? nameTh : nameEn
    }
}

struct ThaiDistrict: Codable, Identifiable, Hashable {
    let id: Int
    let nameTh: String
    let nameEn: String
    let subDistricts: [ThaiSubDistrict]
    
    enum CodingKeys: String, CodingKey {
        case id
        case nameTh = "name_th"
        case nameEn = "name_en"
        case subDistricts = "sub_districts"
    }
    
    func displayName(for language: String) -> String {
        return language == "th" ? nameTh : nameEn
    }
}

struct ThaiSubDistrict: Codable, Identifiable, Hashable {
    let id: Int
    let nameTh: String
    let nameEn: String
    let zipCode: Int
    
    enum CodingKeys: String, CodingKey {
        case id
        case nameTh = "name_th"
        case nameEn = "name_en"
        case zipCode = "zip_code"
    }
    
    func displayName(for language: String) -> String {
        return language == "th" ? nameTh : nameEn
    }
}

class ThailandAddressManager {
    static let shared = ThailandAddressManager()
    
    let provinces: [ThaiProvince]
    
    private init() {
        guard let asset = NSDataAsset(name: "thailand_address") else {
            print("Error: thailand_address asset not found")
            self.provinces = []
            return
        }
        do {
            self.provinces = try JSONDecoder().decode([ThaiProvince].self, from: asset.data)
            print("Loaded \(self.provinces.count) provinces successfully!")
        } catch {
            print("Error decoding thailand_address asset: \(error)")
            self.provinces = []
        }
    }
}

fileprivate extension String {
    func localized(for language: String) -> String {
        return LocalizationManager.shared.t(self)
    }
}
