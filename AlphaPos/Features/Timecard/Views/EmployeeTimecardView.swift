// EmployeeTimecardView.swift
// AlphaPos — Premium Timecard & Biometric Interface

import SwiftUI
import SwiftData

struct EmployeeTimecardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Employee.firstName) private var employees: [Employee]
    @Query(sort: \Timecard.clockIn, order: .reverse) private var recentTimecards: [Timecard]

    @State private var viewModel = EmployeeTimecardViewModel()

    private var filteredEmployees: [Employee] {
        employees.filter { employee in
            let query = viewModel.employeeSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !query.isEmpty {
                let fullName = "\(employee.firstName) \(employee.lastName)".lowercased()
                let phoneMatches = employee.phone?.contains(query) == true
                if !fullName.contains(query) && !phoneMatches {
                    return false
                }
            }

            let isActive = recentTimecards.contains { $0.employee?.id == employee.id && $0.clockOut == nil }
            if viewModel.employeeFilterStatus == 1 && !isActive {
                return false
            }
            if viewModel.employeeFilterStatus == 2 && isActive {
                return false
            }

            return true
        }
    }

    private var filteredTimecards: [Timecard] {
        recentTimecards.filter { card in
            let query = viewModel.timecardSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !query.isEmpty {
                let empName = "\(card.employee?.firstName ?? "") \(card.employee?.lastName ?? "")".lowercased()
                if !empName.contains(query) {
                    return false
                }
            }

            if viewModel.timecardFilterStatus == 1 && card.status != "approved" {
                return false
            }
            if viewModel.timecardFilterStatus == 2 && card.status == "approved" {
                return false
            }

            if let filterDate = viewModel.timecardFilterDate {
                return Calendar.current.isDate(card.clockIn, inSameDayAs: filterDate)
            }

            return true
        }
    }

    enum ScannerMode { case clockIn, clockOut }

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            if employees.isEmpty {
                emptyState
            } else {
                HStack(spacing: 0) {
                    employeePanel
                    timecardLogPanel
                }
            }

            if viewModel.showingScanner, let emp = viewModel.selectedEmployee {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                            viewModel.showingScanner = false
                        }
                    }
                    .transition(.opacity)

                AttendanceCameraReviewView(
                    employee: emp,
                    mode: viewModel.scannerMode,
                    onCancel: {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                            viewModel.showingScanner = false
                        }
                    }
                ) { success, confidence in
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                        viewModel.handleScanResult(employee: emp, success: success, confidence: confidence)
                    }
                }
                .frame(maxWidth: 540, maxHeight: 700)
                .background(Color.appSurface)
                .cornerRadius(24)
                .shadow(color: Color.black.opacity(0.25), radius: 25, x: 0, y: 12)
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .move(edge: .top).combined(with: .opacity)
                ))
                .zIndex(10)
            }
        }
        .navigationTitle(L.Timecard.title.t)
        .apNavBar(background: Color.appBackground)
        .onAppear { viewModel.modelContext = modelContext }
        .alert("คำเตือน: ยังไม่ปิดกะเงินสด", isPresented: Binding(
            get: { viewModel.showRegisterSessionWarning },
            set: { viewModel.showRegisterSessionWarning = $0 }
        )) {
            Button("ลงเวลาออกงานต่อไป (Force)", role: .destructive) {
                if let emp = viewModel.selectedEmployee {
                    viewModel.forceClockOut(employee: emp, confidence: 1.0)
                }
            }
            Button("ยกเลิก (Cancel)", role: .cancel) {
                viewModel.activeRegisterSessionForWarning = nil
            }
        } message: {
            Text("คุณยังมีกะเงินสดที่เปิดใช้งานอยู่ กรุณาปิดกะเงินสดในหน้าจัดการเงินสดก่อนลงเวลาออกงานเพื่อความถูกต้องของยอดเงิน")
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                NavigationLink(destination: TimecardChartsView()) {
                    Label("สถิติ", systemImage: "chart.line.uptrend.xyaxis")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
                .foregroundColor(.appAccent)

                NavigationLink(destination: PayrollMonthlyReportView()) {
                    Label("ค่าแรง", systemImage: "banknote")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
                .foregroundColor(.appAccent)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: APSpacing.lg) {
            ZStack {
                Circle().fill(Color.appSurface).frame(width: 100, height: 100)
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 44))
                    .foregroundStyle(APGradient.accent)
            }
            Text(L.Timecard.noEmployeesTitle.t)
                .font(.title2).fontWeight(.bold)
                .foregroundColor(.textPrimary)
            Text(L.Timecard.noEmployeesSubtitle.t)
                .font(.subheadline).foregroundColor(.textSecondary)
                .multilineTextAlignment(.center).frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Employee Panel (Left)

    private var employeePanel: some View {
        let clockedInCount  = recentTimecards.filter { $0.clockOut == nil }.count
        let approvedCount   = recentTimecards.filter { $0.status == "approved" }.count
        return VStack(spacing: 0) {
            // Stats header
            HStack(spacing: APSpacing.md) {
                statPill(icon: "person.3.fill",        value: "\(employees.count)", label: L.Timecard.statStaff.t,       color: Color.appAccent)
                statPill(icon: "clock.fill",            value: "\(clockedInCount)",  label: L.Timecard.statClockedIn.t,  color: Color.appTeal)
                statPill(icon: "checkmark.circle.fill", value: "\(approvedCount)",   label: L.Timecard.statApproved.t,    color: Color.appAmber)
            }
            .padding(APSpacing.md)
            .background(Color.appSurface)

            Divider().background(Color.appDivider)

            // Search Bar & Filter Picker (Left Panel)
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.textSecondary)
                    TextField("ค้นหาพนักงานด้วยชื่อหรือเบอร์...", text: Binding(
                        get: { viewModel.employeeSearchQuery },
                        set: { val in
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                viewModel.employeeSearchQuery = val
                            }
                        }
                    ))
                    .textFieldStyle(.plain)

                    if !viewModel.employeeSearchQuery.isEmpty {
                        Button(action: {
                            withAnimation { viewModel.employeeSearchQuery = "" }
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
                .background(Color.appSurfaceHigh)
                .cornerRadius(10)

                Picker("", selection: Binding(
                    get: { viewModel.employeeFilterStatus },
                    set: { val in
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            viewModel.employeeFilterStatus = val
                        }
                    }
                )) {
                    Text("ทั้งหมด").tag(0)
                    Text("เข้างานอยู่").tag(1)
                    Text("ยังไม่เข้างาน").tag(2)
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal, APSpacing.md)
            .padding(.vertical, 10)
            .background(Color.appSurface)

            Divider().background(Color.appDivider)

            ScrollView {
                LazyVStack(spacing: APSpacing.sm) {
                    ForEach(filteredEmployees) { employee in
                        let active = recentTimecards.first(where: {
                            $0.employee?.id == employee.id && $0.clockOut == nil
                        })
                        EmployeeRow(employee: employee, isActive: active != nil) { mode in
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                                viewModel.selectedEmployee = employee
                                viewModel.scannerMode = mode
                                viewModel.showingScanner = true
                            }
                        }
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                    }
                }
                .padding(APSpacing.md)
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color.appBackground)
    }

    private func statPill(icon: String, value: String, label: String, color: Color) -> some View {
        HStack(spacing: APSpacing.sm) {
            Image(systemName: icon).font(.subheadline).foregroundColor(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(.headline).fontWeight(.bold).foregroundColor(.textPrimary)
                Text(label).font(.caption2).foregroundColor(.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(APSpacing.sm)
        .background(Color.appSurfaceHigh)
        .clipShape(RoundedRectangle(cornerRadius: APRadius.sm, style: .continuous))
    }

    // MARK: - Timecard Log Panel (Right)

    private var timecardLogPanel: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L.Timecard.recentActivity.t)
                        .font(.headline).fontWeight(.bold)
                        .foregroundColor(.textPrimary)
                    Text(LocalizationManager.shared.t(L.Timecard.recentRecordsTemplate, min(filteredTimecards.count, 30)))
                        .font(.caption2).foregroundColor(.textSecondary)
                }
                Spacer()
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundColor(.textSecondary)
            }
            .padding(APSpacing.md)
            .background(Color.appSurface)

            Divider().background(Color.appDivider)

            // Search & Filters (Right Panel)
            VStack(spacing: 8) {
                // Search field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.textSecondary)
                    TextField("ค้นหาชื่อพนักงาน...", text: Binding(
                        get: { viewModel.timecardSearchQuery },
                        set: { val in
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                viewModel.timecardSearchQuery = val
                            }
                        }
                    ))
                    .textFieldStyle(.plain)

                    if !viewModel.timecardSearchQuery.isEmpty {
                        Button(action: {
                            withAnimation { viewModel.timecardSearchQuery = "" }
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(Color.appSurfaceHigh)
                .cornerRadius(8)

                HStack(spacing: 8) {
                    // Status Picker
                    Picker("", selection: Binding(
                        get: { viewModel.timecardFilterStatus },
                        set: { val in
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                viewModel.timecardFilterStatus = val
                            }
                        }
                    )) {
                        Text("ทั้งหมด").tag(0)
                        Text("อนุมัติแล้ว").tag(1)
                        Text("รอนุมัติ").tag(2)
                    }
                    .pickerStyle(.segmented)

                    // Date Picker
                    DatePicker("", selection: Binding(
                        get: { viewModel.timecardFilterDate ?? Date() },
                        set: { val in
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                viewModel.timecardFilterDate = val
                            }
                        }
                    ), displayedComponents: .date)
                    .labelsHidden()
                    .accentColor(.appAccent)
                    .background(Color.appSurfaceHigh)
                    .cornerRadius(8)

                    if viewModel.timecardFilterDate != nil {
                        Button(action: {
                            withAnimation { viewModel.timecardFilterDate = nil }
                        }) {
                            Image(systemName: "calendar.badge.minus")
                                .font(.subheadline)
                                .foregroundColor(.appRose)
                                .padding(8)
                                .background(Color.appSurfaceHigh)
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, APSpacing.md)
            .padding(.vertical, 10)
            .background(Color.appSurface)

            Divider().background(Color.appDivider)

            if filteredTimecards.isEmpty {
                VStack(spacing: APSpacing.md) {
                    Image(systemName: "tray.fill")
                        .font(.system(size: 36)).foregroundColor(.textTertiary)
                    Text(L.Timecard.noRecordsYet.t)
                        .font(.subheadline).foregroundColor(.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.appBackground)
            } else {
                ScrollView {
                    LazyVStack(spacing: APSpacing.sm) {
                        ForEach(Array(filteredTimecards.prefix(30))) { card in
                            TimecardLogRow(card: card)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal: .move(edge: .top).combined(with: .opacity)
                                ))
                        }
                    }
                    .padding(APSpacing.md)
                }
                .background(Color.appBackground)
            }
        }
        .frame(width: 450)
        .background(Color.appBackground)
        .overlay(Rectangle().fill(Color.appDivider).frame(width: 1), alignment: .leading)
    }
}

// MARK: - Employee Row Card

private struct EmployeeRow: View {
    let employee: Employee
    let isActive: Bool
    let onAction: (EmployeeTimecardView.ScannerMode) -> Void

    var body: some View {
        HStack(spacing: APSpacing.md) {
            // Avatar
            ZStack {
                Circle()
                    .fill(isActive ? APGradient.positive : LinearGradient(colors: [Color.appSurfaceHigh], startPoint: .top, endPoint: .bottom))
                    .frame(width: 46, height: 46)
                    .shadow(color: isActive ? Color(hex: "10B981").opacity(0.4) : .clear, radius: 8, x: 0, y: 0)

                Text(String(employee.firstName.prefix(1)) + String(employee.lastName.prefix(1)))
                    .font(.subheadline).fontWeight(.black)
                    .foregroundColor(isActive ? .white : .textSecondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("\(employee.firstName) \(employee.lastName)")
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(.textPrimary)
                    if isActive {
                        APBadge(text: L.Timecard.badgeOnShift.t, color: .appTeal, icon: "circle.fill")
                    }
                }
                Text(employee.employmentType.capitalized + " · " + L.Timecard.badgeStaffLabel.t)
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            }

            Spacer()

            // Action button
            if isActive {
                Button(action: { onAction(.clockOut) }) {
                    Label(L.Timecard.btnClockOut.t, systemImage: "door.right.hand.open")
                        .font(.caption).fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(APGradient.destructive)
                        .clipShape(Capsule())
                        .shadow(color: Color(hex: "F43F5E").opacity(0.4), radius: 8, x: 0, y: 2)
                }
            } else {
                Button(action: { onAction(.clockIn) }) {
                    Label(L.Timecard.btnClockIn.t, systemImage: "door.left.hand.open")
                        .font(.caption).fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(APGradient.positive)
                        .clipShape(Capsule())
                        .shadow(color: Color(hex: "10B981").opacity(0.4), radius: 8, x: 0, y: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .apCard()
    }
}

// MARK: - Timecard Log Row

private struct TimecardLogRow: View {
    let card: Timecard

    private var isApproved: Bool { card.status == "approved" }
    private var isActive:   Bool { card.clockOut == nil }
    private var confidence: Double? { card.clockInFaceConfidence }

    var body: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            HStack {
                // Avatar
                ZStack {
                    Circle()
                        .fill(isActive ? APGradient.positive : LinearGradient(colors: [Color.appSurfaceHigh], startPoint: .top, endPoint: .bottom))
                        .frame(width: 34, height: 34)
                    let fn = card.employee?.firstName ?? "?"
                    let ln = card.employee?.lastName ?? ""
                    Text(String(fn.prefix(1)) + String(ln.prefix(1)))
                        .font(.caption).fontWeight(.black)
                        .foregroundColor(isActive ? .white : .textSecondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(card.employee?.firstName ?? "Staff") \(card.employee?.lastName ?? "")")
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(.textPrimary)
                    HStack(spacing: 4) {
                        Text(card.clockIn, style: .time)
                        if let out = card.clockOut {
                            Text("→")
                            Text(out, style: .time)
                        } else {
                            Text("→ " + L.Timecard.logActiveNow.t)
                                .foregroundColor(.appTeal)
                                .fontWeight(.semibold)
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                }

                Spacer()

                APBadge(
                    text: isApproved ? L.Timecard.badgeApproved.t : L.Timecard.badgePending.t,
                    color: isApproved ? .appTeal : .appAmber,
                    icon: isApproved ? "checkmark" : "clock"
                )
            }

            // Confidence bar
            if let conf = confidence {
                HStack(spacing: APSpacing.sm) {
                    Image(systemName: "faceid")
                        .font(.caption2)
                        .foregroundColor(conf >= 95 ? .appTeal : .appAmber)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.appSurfaceHigh)
                                .frame(height: 4)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(conf >= 95 ? APGradient.positive : APGradient.warning)
                                .frame(width: geo.size.width * (conf / 100), height: 4)
                        }
                    }
                    .frame(height: 4)
                    Text(String(format: "%.1f%%", conf))
                        .font(.caption2).fontWeight(.semibold)
                        .foregroundColor(conf >= 95 ? .appTeal : .appAmber)
                }
            }
        }
        .padding(APSpacing.md)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: APRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: APRadius.md, style: .continuous)
                .stroke(isActive ? Color.appTeal.opacity(0.3) : Color.appBorderSubtle, lineWidth: 1)
        )
    }
}

// MARK: - Camera-Assisted Attendance Review

struct AttendanceCameraReviewView: View {
    let employee:     Employee
    let mode:         EmployeeTimecardView.ScannerMode
    var onCancel:     () -> Void = {}
    let onCompletion: (Bool, Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isScanning     = false
    @State private var scanPhase      = 0
    @State private var pulseScale:    CGFloat = 1.0
    @State private var ringOpacity:   Double  = 0.0
    @State private var scanLineY:     CGFloat = -130

    private var scanMessages: [String] {
        [
            L.Timecard.scanMsgPosition.t,
            L.Timecard.scanMsgExtracting.t,
            L.Timecard.scanMsgComparing.t,
            L.Timecard.scanMsgDistance.t
        ]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Full dynamic background
                Color.appBackground.ignoresSafeArea()

                VStack(spacing: APSpacing.xl) {

                    // Mode label
                    APBadge(
                        text: mode == .clockIn ? L.Timecard.btnClockIn.t.uppercased() : L.Timecard.btnClockOut.t.uppercased(),
                        color: mode == .clockIn ? .appTeal : .appRose,
                        icon: mode == .clockIn ? "door.left.hand.open" : "door.right.hand.open"
                    )
                    .padding(.top, APSpacing.lg)

                    Text("\(employee.firstName) \(employee.lastName)")
                        .font(.title2).fontWeight(.bold)
                        .foregroundColor(.textPrimary)

                    // ── Scanner Circle ───────────────────────────────────────
                    ZStack {
                        // Outer pulse rings
                        ForEach(0..<3, id: \.self) { i in
                            Circle()
                                .stroke(
                                    mode == .clockIn
                                    ? Color.appTeal.opacity(ringOpacity / Double(i + 1))
                                    : Color.appRose.opacity(ringOpacity / Double(i + 1)),
                                    lineWidth: 1.5
                                )
                                .scaleEffect(pulseScale + CGFloat(i) * 0.15)
                                .frame(width: 280, height: 280)
                        }

                        // Dynamic camera canvas background with real front camera feed
                        Circle()
                            .fill(Color.appSurface)
                            .frame(width: 260, height: 260)
                            .overlay(
                                FrontCameraPreview()
                                    .clipShape(Circle())
                            )
                            .overlay(
                                Circle()
                                    .stroke(
                                        mode == .clockIn
                                        ? LinearGradient(colors: [.appTeal, Color.appAccent], startPoint: .topLeading, endPoint: .bottomTrailing)
                                        : LinearGradient(colors: [.appRose, .appAmber], startPoint: .topLeading, endPoint: .bottomTrailing),
                                        lineWidth: 2
                                    )
                            )

                        // Face ID icon (only show overlay when not scanning/loading camera)
                        if !isScanning {
                            Image(systemName: "faceid")
                                .font(.system(size: 120, weight: .ultraLight))
                                .foregroundColor(
                                    Color.currentTheme == .light ? Color.textTertiary.opacity(0.2) : Color.white.opacity(0.15)
                                )
                                .transition(.opacity)
                        }

                        // Scan line sweep
                        if isScanning {
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            (mode == .clockIn ? Color.appTeal : Color.appRose).opacity(0.0),
                                            (mode == .clockIn ? Color.appTeal : Color.appRose).opacity(0.6),
                                            (mode == .clockIn ? Color.appTeal : Color.appRose).opacity(0.0)
                                        ],
                                        startPoint: .top, endPoint: .bottom
                                    )
                                )
                                .frame(width: 240, height: 40)
                                .offset(y: scanLineY)
                                .clipShape(Circle().scale(1.05))
                        }
                    }
                    .frame(width: 280, height: 280)

                    // Status text
                    Text(scanPhase < scanMessages.count ? scanMessages[scanPhase] : scanMessages[0])
                        .font(.subheadline)
                        .foregroundColor(isScanning
                                         ? (mode == .clockIn ? .appTeal : .appRose)
                                         : .textSecondary)
                        .animation(.easeInOut(duration: 0.3), value: scanPhase)

                    Text("Camera preview only — this attendance entry will require manager review because face matching and liveness detection are not configured.")
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                    .padding(APSpacing.md)
                    .background(Color.appSurface)
                    .clipShape(RoundedRectangle(cornerRadius: APRadius.md, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: APRadius.md, style: .continuous)
                            .stroke(Color.appBorderSubtle, lineWidth: 1)
                    )
                    .padding(.horizontal, APSpacing.xl)

                    // Trigger button
                    if !isScanning {
                        Button(action: startScan) {
                            Label(
                                mode == .clockIn ? L.Timecard.faceBtnClockIn.t : L.Timecard.faceBtnClockOut.t,
                                systemImage: "faceid"
                            )
                            .apGradientButton(
                                gradient: mode == .clockIn ? APGradient.positive : APGradient.destructive,
                                shadow: mode == .clockIn ? APShadow.positiveGlow : APShadow.destructiveGlow
                            )
                        }
                        .padding(.horizontal, APSpacing.xl)
                    }

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
        }
        .apColorScheme()
    }

    private func startScan() {
        isScanning = true
        withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
            pulseScale  = 1.08
            ringOpacity = 0.7
        }
        withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: true)) {
            scanLineY = 110
        }

        // Phase message progression
        for (i, _) in scanMessages.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.6) {
                withAnimation { scanPhase = i }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            onCompletion(false, 0)
        }
    }
}

import AVFoundation

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

            // Find front camera
            let discoverySession = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInWideAngleCamera],
                mediaType: .video,
                position: .front
            )

            guard let frontCamera = discoverySession.devices.first else {
                return
            }

            do {
                let input = try AVCaptureDeviceInput(device: frontCamera)
                if session.canAddInput(input) {
                    session.addInput(input)
                }

                let preview = AVCaptureVideoPreviewLayer(session: session)
                preview.videoGravity = .resizeAspectFill
                preview.frame = bounds
                layer.addSublayer(preview)
                self.previewLayer = preview
                self.captureSession = session

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
