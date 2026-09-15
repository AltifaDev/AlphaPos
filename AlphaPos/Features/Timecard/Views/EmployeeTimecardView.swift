// EmployeeTimecardView.swift
// AlphaPos — Enterprise Attendance (dense master–detail)

import SwiftUI
import SwiftData
import AVFoundation

struct EmployeeTimecardView: View {
    var embedded: Bool = false

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Employee.firstName) private var employees: [Employee]
    @Query(sort: \Timecard.clockIn, order: .reverse) private var recentTimecards: [Timecard]
    @AppStorage("require_face_scan") private var requireFaceScan = true

    @State private var viewModel = EmployeeTimecardViewModel()
    @State private var searchQuery = ""
    @State private var staffFilter = 0 // 0 all, 1 on shift, 2 off
    @State private var recordFilter = 0 // 0 all, 1 approved, 2 pending
    @State private var filterDate: Date? = nil

    enum ScannerMode { case clockIn, clockOut }

    private var activeEmployees: [Employee] {
        employees.filter { $0.resignedAt == nil }
    }

    private var filteredEmployees: [Employee] {
        activeEmployees.filter { employee in
            let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !query.isEmpty {
                let fullName = "\(employee.firstName) \(employee.lastName)".lowercased()
                let phoneMatches = employee.phone?.lowercased().contains(query) == true
                if !fullName.contains(query) && !phoneMatches { return false }
            }
            let isActive = recentTimecards.contains { $0.employee?.id == employee.id && $0.clockOut == nil }
            if staffFilter == 1 && !isActive { return false }
            if staffFilter == 2 && isActive { return false }
            return true
        }
    }

    private var filteredTimecards: [Timecard] {
        recentTimecards.filter { card in
            let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !query.isEmpty {
                let empName = "\(card.employee?.firstName ?? "") \(card.employee?.lastName ?? "")".lowercased()
                if !empName.contains(query) { return false }
            }
            if recordFilter == 1 && card.status != "approved" { return false }
            if recordFilter == 2 && card.status == "approved" { return false }
            if let filterDate {
                return Calendar.current.isDate(card.clockIn, inSameDayAs: filterDate)
            }
            return true
        }
    }

    private var clockedInCount: Int {
        recentTimecards.filter { $0.clockOut == nil }.count
    }

    private var approvedCount: Int {
        recentTimecards.filter { $0.status == "approved" }.count
    }

    private var pendingAudits: [Timecard] {
        recentTimecards.filter { $0.status == "pending_audit" }
    }

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            if activeEmployees.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    metricsBar
                    unifiedToolbar
                    Divider().background(Color.appDivider)
                    if !pendingAudits.isEmpty {
                        pendingBanner
                        Divider().background(Color.appDivider)
                    }
                    HStack(spacing: 0) {
                        staffList
                            .frame(maxWidth: .infinity)
                        Divider().background(Color.appDivider)
                        activityPane
                            .frame(width: 380)
                    }
                }
            }

            if viewModel.showingScanner, let emp = viewModel.selectedEmployee {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            viewModel.showingScanner = false
                        }
                    }

                AttendanceCameraReviewView(
                    employee: emp,
                    mode: viewModel.scannerMode,
                    onCancel: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            viewModel.showingScanner = false
                        }
                    }
                ) { success, confidence in
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        viewModel.handleScanResult(employee: emp, success: success, confidence: confidence, context: modelContext)
                    }
                }
                .frame(maxWidth: 520, maxHeight: 640)
                .background(Color.appSurface)
                .cornerRadius(16)
                .shadow(color: Color.black.opacity(0.25), radius: 20, x: 0, y: 10)
                .zIndex(10)
            }

            // Success feedback popup
            if viewModel.showSuccessFeedback, let event = viewModel.lastClockEvent {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            viewModel.showSuccessFeedback = false
                        }
                    }

                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill((event.mode == .clockIn ? Color.appTeal : Color.appRose).opacity(0.15))
                            .frame(width: 72, height: 72)
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 46, weight: .bold))
                            .foregroundColor(event.mode == .clockIn ? .appTeal : .appRose)
                    }

                    VStack(spacing: 6) {
                        Text(event.mode == .clockIn ? "ลงเวลาเข้างานสำเร็จ!" : "ลงเวลาออกงานสำเร็จ!")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.textPrimary)

                        Text(event.employeeName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.textSecondary)

                        HStack(spacing: 6) {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 13))
                            Text(event.time.formatted(date: .abbreviated, time: .standard))
                                .font(.system(size: 14, weight: .bold))
                        }
                        .foregroundColor(event.mode == .clockIn ? .appTeal : .appRose)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background((event.mode == .clockIn ? Color.appTeal : Color.appRose).opacity(0.12), in: Capsule())
                        .padding(.top, 2)
                    }

                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            viewModel.showSuccessFeedback = false
                        }
                    } label: {
                        Text("ตกลง (OK)")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(event.mode == .clockIn ? Color.appTeal : Color.appRose)
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 6)
                }
                .padding(24)
                .frame(maxWidth: 380)
                .background(Color.appSurface)
                .cornerRadius(20)
                .shadow(color: Color.black.opacity(0.3), radius: 25, y: 10)
                .zIndex(20)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                        if viewModel.showSuccessFeedback {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                viewModel.showSuccessFeedback = false
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(embedded ? "" : L.Timecard.title.t)
        .apNavBar(background: Color.appBackground)
        .onAppear {
            viewModel.modelContext = modelContext
        }
        .alert("คำเตือน: ยังไม่ปิดกะเงินสด", isPresented: Binding(
            get: { viewModel.showRegisterSessionWarning },
            set: { viewModel.showRegisterSessionWarning = $0 }
        )) {
            Button("ลงเวลาออกงานต่อไป (Force)", role: .destructive) {
                if let emp = viewModel.selectedEmployee {
                    viewModel.forceClockOut(employee: emp, confidence: 1.0, context: modelContext)
                }
            }
            Button("ยกเลิก (Cancel)", role: .cancel) {
                viewModel.activeRegisterSessionForWarning = nil
            }
        } message: {
            Text("คุณยังมีกะเงินสดที่เปิดใช้งานอยู่ กรุณาปิดกะเงินสดในหน้าจัดการเงินสดก่อนลงเวลาออกงานเพื่อความถูกต้องของยอดเงิน")
        }
        .toolbar {
            if !embedded {
                ToolbarItemGroup(placement: .primaryAction) {
                    NavigationLink(destination: TimecardChartsView()) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                    }
                    NavigationLink(destination: PayrollMonthlyReportView()) {
                        Image(systemName: "banknote")
                    }
                }
            }
        }
    }

    // MARK: - Metrics

    private var metricsBar: some View {
        HStack(spacing: 0) {
            metricCell(value: "\(activeEmployees.count)", label: L.Timecard.statStaff.t, icon: "person.text.rectangle")
            Divider().frame(height: 28)
            metricCell(value: "\(clockedInCount)", label: L.Timecard.statClockedIn.t, icon: "clock.badge.checkmark")
            Divider().frame(height: 28)
            metricCell(value: "\(approvedCount)", label: L.Timecard.statApproved.t, icon: "checkmark.seal")
            Divider().frame(height: 28)
            metricCell(value: "\(pendingAudits.count)", label: L.Timecard.badgePending.t, icon: "eye.trianglebadge.exclamationmark")
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.appSurface)
    }

    private func metricCell(value: String, label: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(hex: "0F766E"))
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Color.textPrimary)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Color.textTertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    // MARK: - Unified toolbar

    private var unifiedToolbar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textTertiary)
                TextField("employee_search_placeholder".t, text: $searchQuery)
                    .font(.system(size: 12))
                    .textFieldStyle(.plain)
                if !searchQuery.isEmpty {
                    Button { searchQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.appSurfaceHigh, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .frame(maxWidth: 240)

            HStack(spacing: 6) {
                Text(L.Timecard.filterStaff.t)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.textSecondary)

                compactChips(
                    selection: $staffFilter,
                    items: [
                        (0, "employee_filter_all".t),
                        (1, L.Timecard.statusOnShift.t),
                        (2, L.Timecard.statusOffShift.t)
                    ]
                )
            }

            Spacer()
        }
        .padding(.horizontal, APSpacing.md)
        .padding(.vertical, 8)
        .background(Color.appSurface)
    }

    private func compactChips(selection: Binding<Int>, items: [(Int, String)]) -> some View {
        HStack(spacing: 3) {
            ForEach(items, id: \.0) { tag, title in
                Button {
                    withAnimation(.easeInOut(duration: 0.12)) { selection.wrappedValue = tag }
                } label: {
                    Text(title)
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .foregroundStyle(selection.wrappedValue == tag ? Color.white : Color.textSecondary)
                        .background(selection.wrappedValue == tag ? Color(hex: "0F766E") : Color.appSurfaceHigh)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var pendingBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "eye.trianglebadge.exclamationmark")
                .font(.system(size: 12))
                .foregroundStyle(Color.appAmber)
            Text("pending_face_scan_audits".t)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
            Text("· \(pendingAudits.count)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.appAmber)
            Spacer()
        }
        .padding(.horizontal, APSpacing.md)
        .padding(.vertical, 6)
        .background(Color.appAmber.opacity(0.08))
    }

    // MARK: - Staff list

    private var staffList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredEmployees) { employee in
                    let active = recentTimecards.first(where: {
                        $0.employee?.id == employee.id && $0.clockOut == nil
                    })
                    let todayShift = viewModel.fetchTodayActiveShift(for: employee)
                    DenseAttendanceRow(
                        employee: employee,
                        isActive: active != nil,
                        activeTimecard: active,
                        todayShift: todayShift
                    ) { mode in
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            viewModel.selectedEmployee = employee
                            viewModel.scannerMode = mode
                            if requireFaceScan {
                                viewModel.showingScanner = true
                            } else {
                                viewModel.handleScanResult(employee: employee, success: true, confidence: 0, context: modelContext)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Activity

    private var activityPane: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack {
                    Text(L.Timecard.recentActivity.t)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Text("\(min(filteredTimecards.count, 40))")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.textTertiary)
                }

                HStack(spacing: 6) {
                    compactChips(
                        selection: $recordFilter,
                        items: [
                            (0, "employee_filter_all".t),
                            (1, L.Timecard.badgeApproved.t),
                            (2, L.Timecard.badgePending.t)
                        ]
                    )

                    Spacer(minLength: 4)

                    DatePicker("", selection: Binding(
                        get: { filterDate ?? Date() },
                        set: { filterDate = $0 }
                    ), displayedComponents: .date)
                    .labelsHidden()
                    .environment(\.locale, Locale(identifier: LocalizationManager.shared.currentLanguage.rawValue == "th" ? "th_TH" : "en_US"))
                    .frame(width: 110)

                    if filterDate != nil {
                        Button {
                            filterDate = nil
                        } label: {
                            Image(systemName: "calendar.badge.minus")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.appRose)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.appSurface)

            Divider().background(Color.appDivider)

            if filteredTimecards.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.textTertiary)
                    Text(L.Timecard.noRecordsYet.t)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(filteredTimecards.prefix(40))) { card in
                            DenseTimecardRow(card: card)
                        }
                    }
                }
            }
        }
        .background(Color.appBackground)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 36))
                .foregroundStyle(Color(hex: "0F766E"))
            Text(L.Timecard.noEmployeesTitle.t)
                .font(.headline.weight(.bold))
                .foregroundStyle(Color.textPrimary)
            Text(L.Timecard.noEmployeesSubtitle.t)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Staff Attendance Kiosk

/// Focused clock-in/out surface opened from the persistent Face ID toolbar button.
/// It intentionally excludes reports, filters and attendance history.
struct StaffAttendanceKioskView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Employee.firstName) private var employees: [Employee]
    @Query(sort: \Timecard.clockIn, order: .reverse) private var timecards: [Timecard]

    @State private var viewModel = EmployeeTimecardViewModel()
    @State private var selectedEmployee: Employee?
    @State private var scannerMode: EmployeeTimecardView.ScannerMode = .clockIn

    private var activeEmployees: [Employee] {
        employees.filter { $0.resignedAt == nil }
    }

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: APSpacing.lg) {
                    VStack(spacing: 8) {
                        Image(systemName: "faceid")
                            .font(.system(size: 44, weight: .light))
                            .foregroundStyle(Color.appTeal)
                        Text("เลือกชื่อเพื่อเข้า/ออกงาน")
                            .font(.title2.bold())
                            .foregroundStyle(Color.textPrimary)
                        Text("ยืนยันตัวตนบน iPad เครื่องร้านค้า")
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .padding(.top, APSpacing.md)

                    if activeEmployees.isEmpty {
                        ContentUnavailableView(
                            "ไม่พบพนักงาน",
                            systemImage: "person.crop.circle.badge.exclamationmark",
                            description: Text("เพิ่มพนักงานในเมนูจัดการพนักงานก่อนลงเวลา")
                        )
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: APSpacing.md)], spacing: APSpacing.md) {
                            ForEach(activeEmployees) { employee in
                                employeeCard(employee)
                            }
                        }
                    }
                }
                .padding(APSpacing.lg)
            }

            // Success feedback popup
            if viewModel.showSuccessFeedback, let event = viewModel.lastClockEvent {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            viewModel.showSuccessFeedback = false
                        }
                    }

                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill((event.mode == .clockIn ? Color.appTeal : Color.appRose).opacity(0.15))
                            .frame(width: 72, height: 72)
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 46, weight: .bold))
                            .foregroundColor(event.mode == .clockIn ? .appTeal : .appRose)
                    }

                    VStack(spacing: 6) {
                        Text(event.mode == .clockIn ? "ลงเวลาเข้างานสำเร็จ!" : "ลงเวลาออกงานสำเร็จ!")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.textPrimary)

                        Text(event.employeeName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.textSecondary)

                        HStack(spacing: 6) {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 13))
                            Text(event.time.formatted(date: .abbreviated, time: .standard))
                                .font(.system(size: 14, weight: .bold))
                        }
                        .foregroundColor(event.mode == .clockIn ? .appTeal : .appRose)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background((event.mode == .clockIn ? Color.appTeal : Color.appRose).opacity(0.12), in: Capsule())
                        .padding(.top, 2)
                    }

                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            viewModel.showSuccessFeedback = false
                        }
                    } label: {
                        Text("ตกลง (OK)")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(event.mode == .clockIn ? Color.appTeal : Color.appRose, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
                .padding(24)
                .frame(maxWidth: 340)
                .background(Color.appSurface)
                .cornerRadius(20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.appDivider, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.3), radius: 24, x: 0, y: 12)
                .transition(.scale(scale: 0.85).combined(with: .opacity))
                .zIndex(100)
            }
        }
        .onAppear { viewModel.modelContext = modelContext }
        .onChange(of: viewModel.showSuccessFeedback) { _, isShowing in
            if isShowing {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        if viewModel.showSuccessFeedback {
                            viewModel.showSuccessFeedback = false
                        }
                    }
                }
            }
        }
        .fullScreenCover(item: $selectedEmployee) { employee in
            AttendanceCameraReviewView(
                employee: employee,
                mode: scannerMode,
                onCancel: { selectedEmployee = nil }
            ) { success, confidence in
                viewModel.scannerMode = scannerMode
                viewModel.handleScanResult(employee: employee, success: success, confidence: confidence, context: modelContext)
                selectedEmployee = nil
            }
        }
    }

    private func activeTimecard(for employee: Employee) -> Timecard? {
        if let memoryCard = employee.timecards.first(where: { $0.clockOut == nil && !$0.isDeleted }) {
            return memoryCard
        }
        return timecards.first { $0.employee?.id == employee.id && $0.clockOut == nil && !$0.isDeleted }
    }

    private func employeeCard(_ employee: Employee) -> some View {
        let activeCard = activeTimecard(for: employee)
        let isWorking = activeCard != nil
        let initials = String(employee.firstName.prefix(1)) + String(employee.lastName.prefix(1))
        return Button {
            selectedEmployee = employee
            scannerMode = isWorking ? .clockOut : .clockIn
            viewModel.selectedEmployee = employee
            viewModel.scannerMode = scannerMode
            APHaptic.trigger()
        } label: {
            HStack(spacing: APSpacing.md) {
                Circle()
                    .fill(isWorking ? Color.appTeal.opacity(0.18) : Color.appSurfaceHigh)
                    .frame(width: 52, height: 52)
                    .overlay {
                        Text(initials)
                            .font(.headline.bold())
                            .foregroundStyle(isWorking ? Color.appTeal : Color.textSecondary)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(employee.firstName) \(employee.lastName)")
                        .font(.headline)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    
                    if let activeCard {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.appTeal)
                                .frame(width: 6, height: 6)
                            Text("เข้างาน \(activeCard.clockIn.formatted(date: .omitted, time: .shortened)) น.")
                                .font(.caption.bold())
                                .foregroundStyle(Color.appTeal)
                        }
                    } else {
                        Text(employee.employmentType.capitalized)
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }

                Spacer()

                Label(isWorking ? "ออกงาน" : "เข้างาน", systemImage: isWorking ? "rectangle.portrait.and.arrow.right" : "faceid")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(isWorking ? Color.appRose : Color.appTeal, in: Capsule())
            }
            .padding(APSpacing.md)
            .background(Color.appSurface, in: RoundedRectangle(cornerRadius: APRadius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: APRadius.md, style: .continuous).stroke(Color.appBorderSubtle, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(employee.firstName) \(employee.lastName), \(isWorking ? "ออกงาน" : "เข้างาน")")
    }
}

// MARK: - Dense rows

private struct DenseAttendanceRow: View {
    let employee: Employee
    let isActive: Bool
    let activeTimecard: Timecard?
    let todayShift: EmployeeShift?
    let onAction: (EmployeeTimecardView.ScannerMode) -> Void

    private var scheduleLabel: String {
        guard let shift = todayShift else { return L.Timecard.unscheduled.t }
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return "\(fmt.string(from: shift.scheduledStart))–\(fmt.string(from: shift.scheduledEnd))"
    }

    private var elapsedWorkTimeString: String? {
        guard let clockIn = activeTimecard?.clockIn else { return nil }
        let minutes = max(0, Int(Date().timeIntervalSince(clockIn) / 60))
        let hours = minutes / 60
        let mins = minutes % 60
        if LocalizationManager.shared.currentLanguage == .thai {
            return hours > 0 ? "\(hours) ชม. \(mins) นาที" : "\(mins) นาที"
        } else {
            return hours > 0 ? "\(hours)h \(mins)m" : "\(mins)m"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(isActive ? Color.appTeal.opacity(0.18) : Color.appSurfaceHigh)
                    .frame(width: 34, height: 34)
                Text(String(employee.firstName.prefix(1) + employee.lastName.prefix(1)))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(isActive ? Color.appTeal : Color.textSecondary)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("\(employee.firstName) \(employee.lastName)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    if isActive {
                        Text(L.Timecard.badgeOnShift.t)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.appTeal)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.appTeal.opacity(0.12), in: Capsule())
                    }
                }
                HStack(spacing: 6) {
                    HStack(spacing: 3) {
                        Image(systemName: todayShift == nil ? "calendar.badge.exclamationmark" : "calendar")
                            .font(.system(size: 9))
                        Text(scheduleLabel)
                            .font(.system(size: 10))
                        if let role = todayShift?.role, !role.isEmpty {
                            Text("· \(role)")
                                .font(.system(size: 10))
                        }
                    }
                    .foregroundStyle(todayShift == nil ? Color.appAmber : Color.textTertiary)

                    if let active = activeTimecard {
                        HStack(spacing: 3) {
                            Text("·")
                                .foregroundStyle(Color.textTertiary)
                            Image(systemName: "clock")
                                .font(.system(size: 9))
                            Text(active.clockIn, style: .time)
                                .font(.system(size: 10, weight: .medium))
                            if let elapsed = elapsedWorkTimeString {
                                Text("(\(elapsed))")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color.textTertiary)
                            }
                        }
                        .foregroundStyle(Color(hex: "0F766E"))
                    }
                }
            }

            Spacer(minLength: 4)

            Button {
                onAction(isActive ? .clockOut : .clockIn)
            } label: {
                if isActive {
                    // Refined Clock-Out: Professional, subtle rose tint with border
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.left.to.line")
                            .font(.system(size: 9, weight: .bold))
                        Text(L.Timecard.btnClockOut.t)
                            .font(.system(size: 11, weight: .bold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .foregroundStyle(Color.appRose)
                    .background(Color.appRose.opacity(0.12), in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.appRose.opacity(0.3), lineWidth: 1)
                    )
                } else {
                    // Clock-In: Primary Teal Capsule
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.right.to.line")
                            .font(.system(size: 9, weight: .bold))
                        Text(L.Timecard.btnClockIn.t)
                            .font(.system(size: 11, weight: .bold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .foregroundStyle(.white)
                    .background(Color.appTeal, in: Capsule())
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Divider().background(Color.appDivider)
        }
    }
}

private struct DenseTimecardRow: View {
    let card: Timecard

    private var isApproved: Bool { card.status == "approved" }
    private var isActive: Bool { card.clockOut == nil }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(isActive ? Color.appTeal.opacity(0.2) : Color.appSurfaceHigh)
                .frame(width: 26, height: 26)
                .overlay(
                    Text(String((card.employee?.firstName ?? "?").prefix(1) + (card.employee?.lastName ?? "").prefix(1)))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(isActive ? Color.appTeal : Color.textSecondary)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("\(card.employee?.firstName ?? "Staff") \(card.employee?.lastName ?? "")")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 3) {
                    Text(card.clockIn, style: .time)
                    if let out = card.clockOut {
                        Text("→")
                        Text(out, style: .time)
                    } else {
                        Text("→ " + L.Timecard.logActiveNow.t)
                            .foregroundStyle(Color.appTeal)
                    }
                    if card.overtimeMinutes > 0 {
                        Text("· OT \(card.overtimeMinutes)m")
                            .foregroundStyle(Color.appAmber)
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(Color.textSecondary)

                if let notes = card.notes, !notes.isEmpty {
                    let isWarning = notes.localizedCaseInsensitiveContains("duplicate") || notes.localizedCaseInsensitiveContains("no shift")
                    Text(notes)
                        .font(.system(size: 9))
                        .foregroundStyle(isWarning ? Color.appAmber : Color.textTertiary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(isApproved ? L.Timecard.badgeApproved.t : L.Timecard.badgePending.t)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(isApproved ? Color.appTeal : Color.appAmber)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background((isApproved ? Color.appTeal : Color.appAmber).opacity(0.12), in: Capsule())

                if card.shift != nil {
                    Image(systemName: "link")
                        .font(.system(size: 9))
                        .foregroundStyle(Color(hex: "0F766E"))
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .overlay(alignment: .bottom) {
            Divider().background(Color.appDivider)
        }
    }
}

// MARK: - Camera-Assisted Attendance Review

struct AttendanceCameraReviewView: View {
    let employee: Employee
    let mode: EmployeeTimecardView.ScannerMode
    var onCancel: () -> Void = {}
    let onCompletion: (Bool, Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @StateObject private var verifier: EmployeeFaceVerifier
    @State private var didComplete = false
    #if targetEnvironment(simulator)
    @State private var showSimulatorPasscodeSheet = false
    #endif

    init(
        employee: Employee,
        mode: EmployeeTimecardView.ScannerMode,
        onCancel: @escaping () -> Void = {},
        onCompletion: @escaping (Bool, Double) -> Void
    ) {
        self.employee = employee
        self.mode = mode
        self.onCancel = onCancel
        self.onCompletion = onCompletion
        _verifier = StateObject(
            wrappedValue: EmployeeFaceVerifier(referenceEmbedding: employee.faceEmbeddingData ?? Data())
        )
    }

    private var statusText: String {
        if didComplete {
            return mode == .clockIn ? "ยืนยันรหัสผ่านและลงเวลาเข้าสำเร็จ" : "ยืนยันรหัสผ่านและลงเวลาออกสำเร็จ"
        }
        switch verifier.state {
        case .preparing: return "กำลังเปิดกล้องหน้า…"
        case .centerFace: return "มองตรงและจัดใบหน้าให้อยู่กลางกรอบ"
        case .turnHead: return "กรุณาหันหน้าไปด้านใดด้านหนึ่ง"
        case .returnToCenter: return "หันกลับมามองตรง"
        case .matching: return "กำลังเปรียบเทียบใบหน้ากับข้อมูลพนักงาน…"
        case .success: return mode == .clockIn ? "ยืนยันใบหน้าและลงเวลาเข้าสำเร็จ" : "ยืนยันใบหน้าและลงเวลาออกสำเร็จ"
        case .failure(let message): return message
        }
    }

    private var isSuccess: Bool {
        if case .success = verifier.state { return true }
        return didComplete
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                VStack(spacing: APSpacing.lg) {
                    APBadge(
                        text: mode == .clockIn ? L.Timecard.btnClockIn.t.uppercased() : L.Timecard.btnClockOut.t.uppercased(),
                        color: mode == .clockIn ? .appTeal : .appRose,
                        icon: mode == .clockIn ? "door.left.hand.open" : "door.right.hand.open"
                    )
                    .padding(.top, APSpacing.md)

                    Text("\(employee.firstName) \(employee.lastName)")
                        .font(.headline.weight(.bold))
                        .foregroundColor(.textPrimary)

                    ZStack {
                        EmployeeFaceCameraPreview(session: verifier.session)
                            .frame(width: 280, height: 280)
                            .clipShape(Circle())
                        Circle()
                            .stroke(isSuccess ? Color.appTeal : Color.appAccent, lineWidth: 4)
                            .frame(width: 284, height: 284)
                        if isSuccess {
                            Circle().fill(Color.black.opacity(0.35)).frame(width: 280, height: 280)
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 88))
                                .foregroundStyle(Color.appTeal)
                        }
                    }

                    Text(statusText)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(isSuccess ? .appTeal : .textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(minHeight: 44)
                        .padding(.horizontal, APSpacing.xl)

                    if employee.faceEmbeddingData == nil {
                        Label("พนักงานยังไม่ได้ลงทะเบียนใบหน้า", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.appAmber)
                    } else if case .preparing = verifier.state {
                        ProgressView()
                            .tint(Color.appTeal)
                    } else if case .failure = verifier.state {
                        Button("ลองตรวจสอบอีกครั้ง") {
                            verifier.retry()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.appAccent)
                    }

                    #if targetEnvironment(simulator)
                    Button {
                        showSimulatorPasscodeSheet = true
                        APHaptic.trigger()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "key.fill")
                                .font(.system(size: 14, weight: .bold))
                            Text(mode == .clockIn ? "เข้างานโดยรหัสผ่าน (Simulator)" : "ออกงานโดยรหัสผ่าน (Simulator)")
                                .font(.system(size: 15, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .frame(height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(mode == .clockIn ? Color.appTeal : Color.appRose)
                        )
                        .shadow(color: (mode == .clockIn ? Color.appTeal : Color.appRose).opacity(0.3), radius: 8, y: 3)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 6)
                    #endif

                    Spacer()
                }
            }
            .navigationTitle(L.Timecard.faceScannerTitle.t)
            .apNavBar(background: Color.appBackground)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel_btn".t) {
                        onCancel()
                        dismiss()
                    }
                    .foregroundColor(.textSecondary)
                }
            }
            #if targetEnvironment(simulator)
            .sheet(isPresented: $showSimulatorPasscodeSheet) {
                SimulatorPasscodeSheet(employee: employee, mode: mode) {
                    showSimulatorPasscodeSheet = false
                    didComplete = true
                    APHaptic.trigger()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        onCompletion(true, 1.0)
                    }
                }
                .modelContext(modelContext)
            }
            #endif
        }
        .apColorScheme()
        .onAppear {
            guard employee.faceEmbeddingData != nil else { return }
            verifier.start()
        }
        .onDisappear { verifier.stop() }
        .onChange(of: verifier.state) { _, state in
            guard !didComplete, case .success(let confidence) = state else { return }
            didComplete = true
            APHaptic.trigger()
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.0))
                onCompletion(true, Double(confidence))
            }
        }
    }
}

#if targetEnvironment(simulator)
private struct SimulatorPasscodeSheet: View {
    @Environment(\.modelContext) private var modelContext
    let employee: Employee
    let mode: EmployeeTimecardView.ScannerMode
    let onSuccess: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var enteredPin = ""
    @State private var errorMessage = ""
    @State private var attempts = 0
    private let pinLength = 4

    private func fetchConfiguredPinHashes() -> [String] {
        var hashes: [String] = []

        // 1. Direct employee user relation
        if let hash = employee.user?.pinCodeHash?.trimmingCharacters(in: .whitespacesAndNewlines), !hash.isEmpty {
            hashes.append(hash)
        }
        if let pwdHash = employee.user?.passwordHash.trimmingCharacters(in: .whitespacesAndNewlines), !pwdHash.isEmpty {
            hashes.append(pwdHash)
        }

        // 2. Fresh fetch of Employee from modelContext to avoid stale SwiftData faults
        let empId = employee.id
        var empDesc = FetchDescriptor<Employee>(predicate: #Predicate<Employee> { $0.id == empId })
        empDesc.fetchLimit = 1
        if let freshEmp = try? modelContext.fetch(empDesc).first {
            if let hash = freshEmp.user?.pinCodeHash?.trimmingCharacters(in: .whitespacesAndNewlines), !hash.isEmpty {
                if !hashes.contains(hash) { hashes.append(hash) }
            }
            if let pwdHash = freshEmp.user?.passwordHash.trimmingCharacters(in: .whitespacesAndNewlines), !pwdHash.isEmpty {
                if !hashes.contains(pwdHash) { hashes.append(pwdHash) }
            }
        }

        // 3. User matched by employeeProfile relation or user id
        var userDesc = FetchDescriptor<User>()
        if let allUsers = try? modelContext.fetch(userDesc) {
            for u in allUsers where u.employeeProfile?.id == empId || (employee.user != nil && u.id == employee.user?.id) {
                if let hash = u.pinCodeHash?.trimmingCharacters(in: .whitespacesAndNewlines), !hash.isEmpty {
                    if !hashes.contains(hash) { hashes.append(hash) }
                }
                let pwd = u.passwordHash.trimmingCharacters(in: .whitespacesAndNewlines)
                if !pwd.isEmpty && !hashes.contains(pwd) {
                    hashes.append(pwd)
                }
            }
        }

        return hashes
    }

    private var hasConfiguredPIN: Bool {
        !fetchConfiguredPinHashes().isEmpty || KeychainManager.shared.isOwnerPinConfigured()
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()

                ZStack {
                    Circle()
                        .fill((mode == .clockIn ? Color.appTeal : Color.appRose).opacity(0.12))
                        .frame(width: 64, height: 64)

                    Image(systemName: "key.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(mode == .clockIn ? .appTeal : .appRose)
                }

                VStack(spacing: 6) {
                    Text(mode == .clockIn ? "เข้างานด้วยรหัสผ่าน" : "ออกงานด้วยรหัสผ่าน")
                        .font(.title3.weight(.bold))
                        .foregroundColor(.textPrimary)

                    Text("\(employee.firstName) \(employee.lastName)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.textSecondary)

                    if hasConfiguredPIN {
                        Text("โหมดทดสอบ Simulator (ระบุ PIN พนักงาน 4 หลัก)")
                            .font(.caption)
                            .foregroundColor(.appAmber)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(Color.appAmber.opacity(0.1))
                            .cornerRadius(8)
                            .padding(.top, 4)
                    }
                }

                if !hasConfiguredPIN {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.appAmber)

                        Text("พนักงานยังไม่ได้ตั้งรหัสผ่าน PIN")
                            .font(.headline.weight(.bold))
                            .foregroundColor(.textPrimary)

                        Text("กรุณากำหนดรหัส PIN 4 หลักของพนักงานในเมนู \"จัดการพนักงาน\" (Staff Directory) ก่อนใช้งาน")
                            .font(.subheadline)
                            .foregroundColor(.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity)
                    .background(Color.appAmber.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.appAmber.opacity(0.25), lineWidth: 1)
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                } else {
                    // PIN Dots
                    HStack(spacing: 20) {
                        ForEach(0..<pinLength, id: \.self) { i in
                            Circle()
                                .fill(i < enteredPin.count ? (mode == .clockIn ? Color.appTeal : Color.appRose) : Color.textTertiary.opacity(0.2))
                                .frame(width: 16, height: 16)
                                .overlay(
                                    Circle()
                                        .stroke(i < enteredPin.count ? (mode == .clockIn ? Color.appTeal : Color.appRose) : Color.textTertiary.opacity(0.4), lineWidth: 1.5)
                                )
                                .scaleEffect(i < enteredPin.count ? 1.15 : 1.0)
                                .animation(.spring(response: 0.18, dampingFraction: 0.65), value: enteredPin.count)
                        }
                    }
                    .modifier(ShakeEffect(animatableData: CGFloat(attempts)))
                    .padding(.vertical, 8)

                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.appRose)
                    }

                    // Keypad
                    keypadGrid
                        .frame(maxWidth: 280)
                }

                Spacer()
            }
            .padding(24)
            .background(Color.appBackground.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel_btn".t) {
                        dismiss()
                    }
                    .foregroundColor(.textSecondary)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var keypadGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 3)
        return LazyVGrid(columns: columns, spacing: 14) {
            ForEach(1...9, id: \.self) { num in
                numpadButton("\(num)") {
                    appendDigit("\(num)")
                }
            }

            numpadButton("C", isAction: true) {
                enteredPin = ""
                errorMessage = ""
                APHaptic.trigger()
            }

            numpadButton("0") {
                appendDigit("0")
            }

            Button {
                if !enteredPin.isEmpty {
                    enteredPin.removeLast()
                    errorMessage = ""
                    APHaptic.trigger()
                }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.appSurface)
                    Image(systemName: "delete.left.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.textSecondary)
                }
                .frame(height: 52)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.appDivider, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func numpadButton(_ title: String, isAction: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: {
            action()
            APHaptic.trigger()
        }) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.appSurface)
                Text(title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(isAction ? .textSecondary : .textPrimary)
            }
            .frame(height: 52)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.appDivider, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func appendDigit(_ digit: String) {
        guard enteredPin.count < pinLength else { return }
        enteredPin.append(digit)
        if enteredPin.count == pinLength {
            verifyPin()
        }
    }

    private func verifyPin() {
        let entered = enteredPin.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Verify against Store Owner PIN from Keychain (used for system login)
        if KeychainManager.shared.verifyOwnerPin(entered) {
            APHaptic.trigger()
            dismiss()
            onSuccess()
            return
        }

        // 2. Verify against any configured PIN hashes for this employee
        let hashes = fetchConfiguredPinHashes()
        guard !hashes.isEmpty else {
            withAnimation(.default) {
                attempts += 1
                errorMessage = "พนักงานยังไม่ได้ตั้งรหัสผ่าน PIN"
                enteredPin = ""
            }
            APHaptic.trigger()
            return
        }

        let isMatch = hashes.contains { hash in
            SecurityHelper.verifyPIN(entered, against: hash)
                || entered == hash
                || SecurityHelper.sha256(entered).lowercased() == hash.lowercased()
                || SecurityHelper.sha256(entered).uppercased() == hash.uppercased()
        }

        if isMatch {
            APHaptic.trigger()
            dismiss()
            onSuccess()
        } else {
            withAnimation(.default) {
                attempts += 1
                errorMessage = "รหัสผ่าน PIN ไม่ถูกต้อง กรุณาลองใหม่อีกครั้ง"
                enteredPin = ""
            }
            APHaptic.trigger()
        }
    }
}
#endif

private struct EmployeeFaceCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer.session = session
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

struct FrontCameraPreview: UIViewRepresentable {
    class CameraView: UIView {
        var captureSession: AVCaptureSession?
        var previewLayer: AVCaptureVideoPreviewLayer?

        override func layoutSubviews() {
            super.layoutSubviews()
            previewLayer?.frame = bounds
        }

        func setupCamera() {
            let session = AVCaptureSession()
            session.sessionPreset = .high
            let discoverySession = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInWideAngleCamera],
                mediaType: .video,
                position: .front
            )
            guard let frontCamera = discoverySession.devices.first else { return }
            do {
                let input = try AVCaptureDeviceInput(device: frontCamera)
                if session.canAddInput(input) { session.addInput(input) }
                let preview = AVCaptureVideoPreviewLayer(session: session)
                preview.videoGravity = .resizeAspectFill
                preview.frame = bounds
                layer.addSublayer(preview)
                previewLayer = preview
                captureSession = session
                DispatchQueue.global(qos: .userInitiated).async {
                    session.startRunning()
                }
            } catch {
                print("Front camera setup failed: \(error)")
            }
        }

        func stopCamera() {
            captureSession?.stopRunning()
        }
    }

    func makeUIView(context: Context) -> CameraView {
        let view = CameraView()
        view.clipsToBounds = true
        view.setupCamera()
        return view
    }

    func updateUIView(_ uiView: CameraView, context: Context) {}

    static func dismantleUIView(_ uiView: CameraView, coordinator: ()) {
        uiView.stopCamera()
    }
}
