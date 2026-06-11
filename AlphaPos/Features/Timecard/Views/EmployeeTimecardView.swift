// EmployeeTimecardView.swift
// AlphaPos — Premium Timecard & Biometric Interface

import SwiftUI
import SwiftData

struct EmployeeTimecardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Employee.firstName) private var employees: [Employee]
    @Query(sort: \Timecard.clockIn, order: .reverse) private var recentTimecards: [Timecard]

    @State private var viewModel = EmployeeTimecardViewModel()

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
        }
        .navigationTitle("Timecard Register")
        .apNavBar(background: Color.appBackground)
        .sheet(isPresented: $viewModel.showingScanner) {
            if let emp = viewModel.selectedEmployee {
                BiometricFaceScannerSimulator(
                    employee: emp,
                    mode: viewModel.scannerMode
                ) { success, confidence in
                    viewModel.handleScanResult(employee: emp, success: success, confidence: confidence)
                }
            }
        }
        .onAppear { viewModel.modelContext = modelContext }
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
            Text("No Employees Registered")
                .font(.title2).fontWeight(.bold)
                .foregroundColor(.textPrimary)
            Text("Add employees to begin tracking clock-in/out with face verification.")
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
                statPill(icon: "person.3.fill",        value: "\(employees.count)", label: "Staff",       color: Color.appAccent)
                statPill(icon: "clock.fill",            value: "\(clockedInCount)",  label: "Clocked In",  color: Color.appTeal)
                statPill(icon: "checkmark.circle.fill", value: "\(approvedCount)",   label: "Approved",    color: Color.appAmber)
            }
            .padding(APSpacing.md)
            .background(Color.appSurface)

            Divider().background(Color.appDivider)

            ScrollView {
                LazyVStack(spacing: APSpacing.sm) {
                    ForEach(employees) { employee in
                        let active = recentTimecards.first(where: {
                            $0.employee?.id == employee.id && $0.clockOut == nil
                        })
                        EmployeeRow(employee: employee, isActive: active != nil) { mode in
                            viewModel.selectedEmployee = employee
                            viewModel.scannerMode = mode
                            viewModel.showingScanner = true
                        }
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
                    Text("Recent Activity")
                        .font(.headline).fontWeight(.bold)
                        .foregroundColor(.textPrimary)
                    Text("Last \(min(recentTimecards.count, 15)) records")
                        .font(.caption2).foregroundColor(.textSecondary)
                }
                Spacer()
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundColor(.textSecondary)
            }
            .padding(APSpacing.md)
            .background(Color.appSurface)

            Divider().background(Color.appDivider)

            if recentTimecards.isEmpty {
                VStack(spacing: APSpacing.md) {
                    Image(systemName: "tray.fill")
                        .font(.system(size: 36)).foregroundColor(.textTertiary)
                    Text("No records yet")
                        .font(.subheadline).foregroundColor(.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.appBackground)
            } else {
                ScrollView {
                    LazyVStack(spacing: APSpacing.sm) {
                        ForEach(Array(recentTimecards.prefix(15))) { card in
                            TimecardLogRow(card: card)
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
                        APBadge(text: "On Shift", color: .appTeal, icon: "circle.fill")
                    }
                }
                Text(employee.employmentType.capitalized + " · Staff")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            }

            Spacer()

            // Action button
            if isActive {
                Button(action: { onAction(.clockOut) }) {
                    Label("Clock Out", systemImage: "door.right.hand.open")
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
                    Label("Clock In", systemImage: "door.left.hand.open")
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
                            Text("→ Active now")
                                .foregroundColor(.appTeal)
                                .fontWeight(.semibold)
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                }

                Spacer()

                APBadge(
                    text: isApproved ? "Approved" : "Pending",
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

// MARK: - Biometric Face Scanner Simulator

struct BiometricFaceScannerSimulator: View {
    let employee:     Employee
    let mode:         EmployeeTimecardView.ScannerMode
    let onCompletion: (Bool, Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var simulatedScore: Double = 98.4
    @State private var isScanning     = false
    @State private var scanPhase      = 0
    @State private var pulseScale:    CGFloat = 1.0
    @State private var ringOpacity:   Double  = 0.0
    @State private var scanLineY:     CGFloat = -130

    private let scanMessages = [
        "Position face in frame...",
        "Extracting facial metrics vector...",
        "Comparing biometric templates...",
        "Calculating Euclidean distance..."
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                // Full dynamic background
                Color.appBackground.ignoresSafeArea()

                VStack(spacing: APSpacing.xl) {

                    // Mode label
                    APBadge(
                        text: mode == .clockIn ? "CLOCK IN" : "CLOCK OUT",
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

                        // Dynamic camera canvas background
                        Circle()
                            .fill(Color.appSurface)
                            .frame(width: 260, height: 260)
                            .overlay(
                                Circle()
                                    .stroke(
                                        mode == .clockIn
                                        ? LinearGradient(colors: [.appTeal, Color.appAccent], startPoint: .topLeading, endPoint: .bottomTrailing)
                                        : LinearGradient(colors: [.appRose, .appAmber], startPoint: .topLeading, endPoint: .bottomTrailing),
                                        lineWidth: 2
                                    )
                            )

                        // Face ID icon
                        Image(systemName: "faceid")
                            .font(.system(size: 120, weight: .ultraLight))
                            .foregroundColor(
                                isScanning
                                ? (mode == .clockIn ? Color.appTeal : Color.appRose).opacity(0.8)
                                : (Color.currentTheme == .light ? Color.textTertiary.opacity(0.2) : Color.white.opacity(0.15))
                            )
                            .animation(.easeInOut(duration: 0.4), value: isScanning)

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

                    // Confidence slider
                    VStack(spacing: APSpacing.sm) {
                        HStack {
                            Label("Simulated Match Confidence", systemImage: "waveform.path.ecg")
                                .font(.caption)
                                .foregroundColor(.textSecondary)
                            Spacer()
                            Text(String(format: "%.1f%%", simulatedScore))
                                .font(.caption).fontWeight(.bold)
                                .foregroundColor(simulatedScore >= 95 ? .appTeal : .appRose)
                        }
                        Slider(value: $simulatedScore, in: 80...100, step: 0.1)
                            .tint(simulatedScore >= 95 ? .appTeal : .appRose)
                    }
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
                                mode == .clockIn ? "Authenticate & Clock In" : "Authenticate & Clock Out",
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
            .navigationTitle("Face Verification")
            .apNavBar(background: Color.appBackground)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundColor(.textSecondary)
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
            let success = simulatedScore >= 95.0
            onCompletion(success, simulatedScore)
        }
    }
}
