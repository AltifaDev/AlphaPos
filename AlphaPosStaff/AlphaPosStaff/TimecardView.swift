import SwiftUI
import LocalAuthentication
import CryptoKit

// MARK: - Clock Action State Machine
// มาตรฐานสากล: แต่ละ state มี transition ชัดเจน
private enum ClockActionState: Equatable {
    case idle                   // รอ user กด
    case confirming             // แสดง confirmation sheet
    case authenticating         // กำลัง biometric / PIN
    case uploading              // กำลังส่งข้อมูล Supabase
    case success(String)        // สำเร็จ — พร้อม timestamp
    case failure(String)        // ล้มเหลว — พร้อม error message
}

struct TimecardView: View {
    let employee: Employee
    @State private var localEmployee: Employee

    @AppStorage("app_language") private var appLanguage = "en"

    // ── Data ──────────────────────────────────────────────────────────────
    @State private var recentTimecards: [Timecard] = []
    @State private var activeTimecard: Timecard?   = nil
    @State private var isLoadingTimecards          = false

    // ── Clock action state machine ────────────────────────────────────────
    @State private var clockState: ClockActionState = .idle
    @State private var showConfirmSheet             = false

    // ── PIN fallback ──────────────────────────────────────────────────────
    @State private var showPINFallback              = false
    @State private var pinInput                     = ""
    @State private var pinError                     = ""

    // ── Face enrollment ───────────────────────────────────────────────────
    @State private var showEnrollmentSheet          = false
    @State private var isRegScanning                = false
    @State private var registrationProgress         = 0.0
    @State private var registrationMessage          = "Align face in camera frame"
    @State private var registrationSuccess          = false

    // ── Interaction & Animation States ────────────────────────────────────
    @State private var bgPulseScale: Double         = 1.0

    init(employee: Employee) {
        self.employee = employee
        self._localEmployee = State(initialValue: employee)
    }

    // MARK: - Computed

    /// ออเดอร์แบบ strict: open timecard ของวันนี้เท่านั้น
    private var todayActiveTimecard: Timecard? {
        recentTimecards.first { tc in
            guard tc.clockOut == nil || tc.clockOut == 0.0 else { return false }
            let date = Date(timeIntervalSince1970: tc.clockIn)
            return Calendar.current.isDateInToday(date)
        }
    }

    private var isClockedIn: Bool { todayActiveTimecard != nil }

    private var timeOfDay: String {
        let h = Calendar.current.component(.hour, from: Date())
        return h < 12 ? "morning" : h < 17 ? "afternoon" : "evening"
    }

    private var clockButtonLabel: String { isClockedIn ? "clock_out".localized(for: appLanguage) : "clock_in".localized(for: appLanguage) }
    private var clockButtonColor: Color  { isClockedIn ? Color.appRose : Color.appTeal }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                ambientBackdrop
                mainContent
            }
            .navigationTitle("timecard_register".localized(for: appLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: loadTimecards) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.appAccent)
                    }
                    .disabled(isLoadingTimecards)
                }
            }
        }
        // ── Sheets ────────────────────────────────────────────────────────
        .sheet(isPresented: $showConfirmSheet) {
            confirmationSheet
                .presentationDetents([.medium])
                .apColorScheme()
        }
        .sheet(isPresented: $showPINFallback, onDismiss: { pinInput = ""; pinError = "" }) {
            pinFallbackSheet
                .presentationDetents([.medium])
                .apColorScheme()
        }
        .sheet(isPresented: $showEnrollmentSheet) {
            enrollmentSheet
                .presentationDetents([.fraction(0.85)])
                .apColorScheme()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                bgPulseScale = 1.08
            }
            loadTimecards()
            localEmployee = employee
        }
        .onChange(of: employee) { _, new in localEmployee = new }
    }

    // MARK: - Main Content

    private var ambientBackdrop: some View {
        Color.appBackground
            .ignoresSafeArea()
            .overlay {
                TimelineView(.animation) { _ in
                    let time = Date().timeIntervalSince1970
                    let leadingX = sin(time * 0.34) * 36
                    let leadingY = cos(time * 0.28) * 42
                    let trailingX = cos(time * 0.22) * 46
                    let trailingY = sin(time * 0.30) * 52

                    ZStack {
                        RoundedRectangle(cornerRadius: 220, style: .continuous)
                            .fill((isClockedIn ? Color.appTeal : Color.appAccent).opacity(0.12))
                            .frame(width: 260, height: 260)
                            .blur(radius: 64)
                            .offset(x: -120 + leadingX, y: -250 + leadingY)

                        RoundedRectangle(cornerRadius: 240, style: .continuous)
                            .fill((isClockedIn ? Color.appGreen : Color.appTeal).opacity(0.09))
                            .frame(width: 320, height: 320)
                            .blur(radius: 78)
                            .offset(x: 140 + trailingX, y: 165 + trailingY)
                    }
                    .allowsHitTesting(false)
                }
            }
    }

    private var mainContent: some View {
        ScrollView {
            VStack(spacing: APSpacing.md) {
                heroHeader
                    .padding(.top, APSpacing.md)

                profilePanel

                stateFeedbackView

                actionPanel

                // Break Timer access
                BreakTimerCard()

                Button(action: {
                    NotificationCenter.default.post(name: NSNotification.Name("LogoutStaff"), object: nil)
                }) {
                    Label("Log out", systemImage: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, APSpacing.sm)
                }
                .padding(.bottom, APSpacing.xl)
            }
            .padding(.horizontal, APSpacing.md)
        }
    }

    private var heroHeader: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("clock_in_out".localized(for: appLanguage))
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Text(isClockedIn ? "live_shift_in_progress".localized(for: appLanguage) : "ready_for_shift".localized(for: appLanguage))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(isClockedIn ? .appTeal : .textSecondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(currentTimestamp())
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(.textPrimary)
                    statusCapsule
                }
            }

            Text(isClockedIn ? "shift_running_hint".localized(for: appLanguage) : "verify_to_clock_in".localized(for: appLanguage))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
    }

    private var statusCapsule: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isClockedIn ? Color.appTeal : Color.textTertiary)
                .frame(width: 7, height: 7)
            Text(isClockedIn ? "ON SHIFT" : "OFF SHIFT")
                .font(.system(size: 10, weight: .black, design: .monospaced))
        }
        .foregroundColor(isClockedIn ? .appTeal : .textSecondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background((isClockedIn ? Color.appTeal : Color.appSurfaceHigh).opacity(isClockedIn ? 0.12 : 0.75))
        .clipShape(Capsule())
    }

    private var profilePanel: some View {
        HStack(spacing: APSpacing.md) {
            avatarView

            VStack(alignment: .leading, spacing: APSpacing.xs) {
                Text("\(localEmployee.firstName) \(localEmployee.lastName)")
                    .font(.system(size: 21, weight: .black, design: .rounded))
                    .foregroundColor(.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)

                HStack(spacing: 8) {
                    Text(localEmployee.role.uppercased())
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundColor(isClockedIn ? .appTeal : .textSecondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background((isClockedIn ? Color.appTeal : Color.appSurfaceHigh).opacity(isClockedIn ? 0.12 : 0.8))
                        .clipShape(Capsule())

                    // faceRegisteredAt is non-nil when a face template exists server-side
                    if localEmployee.faceRegisteredAt != nil {
                        Image(systemName: "faceid")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.appAccent)
                    }
                }

                if let active = todayActiveTimecard {
                    activeBadge(active)
                        .padding(.top, 4)
                } else {
                    Text("No active timecard today")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.textSecondary)
                        .padding(.top, 4)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(APSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: APRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: APRadius.lg, style: .continuous)
                .stroke((isClockedIn ? Color.appTeal : Color.appAccent).opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.07), radius: 18, x: 0, y: 10)
    }

    private var actionPanel: some View {
        VStack(spacing: APSpacing.md) {
            Button(action: onClockButtonTap) {
                HStack(spacing: APSpacing.sm) {
                    if case .uploading = clockState {
                        ProgressView().tint(.white).scaleEffect(0.9)
                    } else {
                        Image(systemName: isClockedIn ? "stop.circle.fill" : "play.circle.fill")
                            .font(.system(size: 22, weight: .bold))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(clockButtonLabel)
                            .font(.system(size: 17, weight: .black))
                        Text(isClockedIn ? "End and submit this shift" : "Start a verified timecard")
                            .font(.system(size: 12, weight: .semibold))
                            .opacity(0.82)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .black))
                        .opacity(0.8)
                }
                .foregroundColor(.white)
                .padding(.horizontal, APSpacing.md)
                .frame(height: 68)
                .background(
                    LinearGradient(
                        colors: isClockedIn
                            ? [Color.appRose, Color.appAmber]
                            : [Color.appTeal, Color.appAccent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: APRadius.md, style: .continuous))
                .shadow(color: (isClockedIn ? Color.appRose : Color.appTeal).opacity(0.26), radius: 18, x: 0, y: 10)
            }
            .disabled(clockState == .authenticating || clockState == .uploading)

            HStack(spacing: APSpacing.sm) {
                secondaryActionButton(
                    title: localEmployee.faceRegisteredAt == nil ? "enroll_face".localized(for: appLanguage) : "update_face".localized(for: appLanguage),
                    subtitle: localEmployee.faceRegisteredAt == nil ? "Coming soon" : "Registered",
                    icon: localEmployee.faceRegisteredAt == nil ? "faceid" : "checkmark.shield.fill",
                    color: .appAccent,
                    action: { showEnrollmentSheet = true }
                )

                secondaryActionButton(
                    title: "adjustment".localized(for: appLanguage),
                    subtitle: "Request correction",
                    icon: "square.and.pencil",
                    color: .appTeal,
                    action: { }
                )
            }
        }
        .padding(APSpacing.md)
        .background(Color.appSurface.opacity(0.86))
        .clipShape(RoundedRectangle(cornerRadius: APRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: APRadius.lg, style: .continuous)
                .stroke(Color.appBorderSubtle, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 18, x: 0, y: 10)
    }

    private func secondaryActionButton(title: String, subtitle: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundColor(color)
                    .frame(width: 34, height: 34)
                    .background(color.opacity(0.11))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .black))
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(subtitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(APSpacing.sm)
            .background(color.opacity(0.055))
            .clipShape(RoundedRectangle(cornerRadius: APRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: APRadius.md, style: .continuous)
                    .stroke(color.opacity(0.14), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Avatar

    private var avatarView: some View {
        ZStack {
            Circle()
                .stroke((isClockedIn ? Color.appTeal : Color.appAccent).opacity(0.12), lineWidth: 8)
                .frame(width: 104, height: 104)
                .scaleEffect(bgPulseScale)

            Circle()
                .fill(
                    LinearGradient(
                        colors: isClockedIn
                            ? [Color.appTeal.opacity(0.22), Color.appGreen.opacity(0.08)]
                            : [Color.appAccent.opacity(0.18), Color.appSurface.opacity(0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 88, height: 88)
                .overlay(
                    Circle()
                        .stroke((isClockedIn ? Color.appTeal : Color.appAccent).opacity(0.35), lineWidth: 2)
                )

            Text(String(localEmployee.firstName.prefix(1) + localEmployee.lastName.prefix(1)).uppercased())
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundColor(isClockedIn ? Color.appTeal : Color.appAccent)

            Circle()
                .fill(isClockedIn ? Color.appTeal : Color.textTertiary)
                .frame(width: 13, height: 13)
                .overlay(Circle().stroke(Color.appSurface, lineWidth: 3))
                .offset(x: 35, y: 34)
        }
        .animation(.easeInOut(duration: 0.3), value: isClockedIn)
    }

    // MARK: - Active Shift Badge

    private func activeBadge(_ tc: Timecard) -> some View {
        let clockInDate = Date(timeIntervalSince1970: tc.clockIn)
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return TimelineView(.periodic(from: Date(), by: 30)) { context in
            let elapsed = Int(context.date.timeIntervalSince(clockInDate) / 60)
            let h = elapsed / 60
            let m = elapsed % 60
            HStack(spacing: 7) {
                Image(systemName: "timer")
                    .font(.system(size: 12, weight: .bold))
                Text("\(formatter.string(from: clockInDate))")
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                Text("\(h > 0 ? "\(h)h " : "")\(m)m")
                    .font(.system(size: 12, weight: .bold))
                Spacer(minLength: 0)
            }
            .foregroundColor(.appTeal)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.appTeal.opacity(0.09))
            .clipShape(RoundedRectangle(cornerRadius: APRadius.sm, style: .continuous))
        }
    }

    // MARK: - State Feedback

    @ViewBuilder
    private var stateFeedbackView: some View {
        switch clockState {
        case .idle:
            EmptyView()
        case .confirming:
            EmptyView()
        case .authenticating:
            feedbackPill(icon: "faceid", text: "Verifying identity", color: .appAccent, showProgress: true)
        case .uploading:
            feedbackPill(icon: "icloud.and.arrow.up.fill", text: "Recording timecard", color: .appAccent, showProgress: true)
        case .success(let msg):
            feedbackPill(icon: "checkmark.circle.fill", text: msg, color: .appTeal)
        case .failure(let msg):
            feedbackPill(icon: "exclamationmark.circle.fill", text: msg, color: .appRose)
            .onTapGesture { clockState = .idle }
        }
    }

    private func feedbackPill(icon: String, text: String, color: Color, showProgress: Bool = false) -> some View {
        HStack(spacing: 9) {
            if showProgress {
                ProgressView()
                    .tint(color)
                    .scaleEffect(0.74)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
            }
            Text(text)
                .font(.system(size: 13, weight: .bold))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .foregroundColor(color)
        .padding(.horizontal, APSpacing.md)
        .padding(.vertical, APSpacing.sm)
        .background(color.opacity(0.09))
        .clipShape(RoundedRectangle(cornerRadius: APRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: APRadius.md, style: .continuous)
                .stroke(color.opacity(0.14), lineWidth: 1)
        )
    }

    // MARK: - Confirmation Sheet

    private var confirmationSheet: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 8)
            Text(isClockedIn ? "Clock Out?" : "Clock In?")
                .font(.title2.weight(.bold)).foregroundColor(.textPrimary)

            VStack(spacing: 6) {
                Text(isClockedIn ? "Ending your shift" : "Starting your shift")
                    .font(.subheadline).foregroundColor(.textSecondary)
                Text(currentTimestamp())
                    .font(.system(size: 22, weight: .semibold, design: .monospaced))
                    .foregroundColor(.textPrimary)
                if isClockedIn, let active = todayActiveTimecard {
                    let duration = Int(Date().timeIntervalSince1970 - active.clockIn) / 60
                    Text("Duration: \(duration / 60)h \(duration % 60)m")
                        .font(.subheadline).foregroundColor(.textSecondary)
                }
            }
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(Color.appBackground)
            .cornerRadius(12)

            // Confirm → biometric auth
            Button(action: {
                showConfirmSheet = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    attemptBiometricAuth()
                }
            }) {
                Text("Confirm \(isClockedIn ? "Clock Out" : "Clock In")")
                    .font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                    .background(clockButtonColor).cornerRadius(10)
            }

            Button("Cancel") {
                showConfirmSheet = false
                clockState = .idle
            }
            .font(.system(size: 15, weight: .medium))
            .foregroundColor(.textSecondary)

            Spacer()
        }
        .padding(.horizontal, 28)
    }

    // MARK: - PIN Fallback Sheet (มาตรฐาน: biometric fail → PIN)

    private var pinFallbackSheet: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 8)
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 40)).foregroundColor(.appAccent)
            Text("Enter PIN to verify").font(.title3.weight(.bold)).foregroundColor(.textPrimary)
            Text("Face ID unavailable — use your PIN").font(.subheadline).foregroundColor(.textSecondary)

            // PIN display
            HStack(spacing: 14) {
                ForEach(0..<4, id: \.self) { i in
                    Circle()
                        .fill(i < pinInput.count ? Color.appAccent : Color.appBorderSubtle)
                        .frame(width: 16, height: 16)
                }
            }
            .padding(.vertical, 8)

            if !pinError.isEmpty {
                Text(pinError).font(.caption).foregroundColor(.appRose)
            }

            // Numpad
            VStack(spacing: 10) {
                ForEach([[1,2,3],[4,5,6],[7,8,9],[0]], id: \.self) { row in
                    HStack(spacing: 16) {
                        ForEach(row, id: \.self) { digit in
                            Button(action: { appendPin(String(digit)) }) {
                                Text("\(digit)")
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundColor(.textPrimary)
                                    .frame(width: 72, height: 52)
                                    .background(Color.appBackground)
                                    .cornerRadius(10)
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appBorderSubtle))
                            }
                        }
                        if row == [0] {
                            Button(action: { if !pinInput.isEmpty { pinInput.removeLast() } }) {
                                Image(systemName: "delete.left")
                                    .font(.system(size: 18))
                                    .foregroundColor(.textSecondary)
                                    .frame(width: 72, height: 52)
                                    .background(Color.appBackground)
                                    .cornerRadius(10)
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appBorderSubtle))
                            }
                        }
                    }
                }
            }

            Button("Cancel") {
                showPINFallback = false
                clockState = .idle
            }
            .font(.caption.weight(.medium)).foregroundColor(.textSecondary)
            .padding(.top, 4)

            Spacer()
        }
        .padding(.horizontal, 28)
    }

    // MARK: - Enrollment Sheet

    private var enrollmentSheet: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 20)
            Image(systemName: "faceid")
                .font(.system(size: 54, weight: .ultraLight)).foregroundColor(.appAccent)

            Text(localEmployee.faceRegisteredAt == nil ? "Enroll Face ID" : "Update Face ID")
                .font(.title2.weight(.bold)).foregroundColor(.textPrimary)
            Text("Face ID enrollment is coming soon. PIN verification is active in the meantime.")
                .font(.subheadline).foregroundColor(.textSecondary)
                .multilineTextAlignment(.center).padding(.horizontal, 20)

            // Progress ring
            ZStack {
                Circle().stroke(Color.appBorderSubtle, lineWidth: 6).frame(width: 100, height: 100)
                if isRegScanning {
                    Circle()
                        .trim(from: 0, to: registrationProgress)
                        .stroke(Color.appAccent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .frame(width: 100, height: 100)
                        .rotationEffect(.degrees(-90))
                }
                Image(systemName: registrationSuccess ? "checkmark" : "faceid")
                    .font(.system(size: 36, weight: .ultraLight))
                    .foregroundColor(registrationSuccess ? .appTeal : .appAccent)
            }

            Text(registrationSuccess ? "Enrollment complete!" : (isRegScanning ? registrationMessage : "Tap Start to begin"))
                .font(.subheadline.weight(.medium))
                .foregroundColor(registrationSuccess ? .appTeal : .textSecondary)

            if !isRegScanning && !registrationSuccess {
                Button(action: startFaceEnrollment) {
                    Text("Start Enrollment")
                        .font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(Color.appAccent).cornerRadius(10)
                }
                .padding(.horizontal, 28)
            }

            Button(registrationSuccess ? "Done" : "Cancel") {
                showEnrollmentSheet = false
                isRegScanning = false; registrationProgress = 0; registrationSuccess = false
            }
            .font(.system(size: 15, weight: .medium)).foregroundColor(.textSecondary)

            Spacer()
        }
    }

    // MARK: - Actions

    private func onClockButtonTap() {
        clockState = .idle
        showConfirmSheet = true
    }

    /// มาตรฐาน: Biometric → fallback PIN
    private func attemptBiometricAuth() {
        let context = LAContext()
        var error: NSError?
        clockState = .authenticating

        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            // Face ID / Touch ID available
            context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Verify identity to \(isClockedIn ? "clock out" : "clock in")"
            ) { success, authError in
                DispatchQueue.main.async {
                    if success {
                        self.performClockAction()
                    } else {
                        // Biometric failed → PIN fallback
                        self.clockState = .idle
                        self.showPINFallback = true
                    }
                }
            }
        } else {
            // Biometrics not available → PIN fallback immediately
            clockState = .idle
            showPINFallback = true
        }
    }

    private func appendPin(_ digit: String) {
        guard pinInput.count < 4 else { return }
        pinInput += digit
        pinError = ""
        if pinInput.count == 4 { verifyPIN() }
    }

    private func verifyPIN() {
        // SECURITY: PIN must ALWAYS be verified server-side.
        // Never compare pinInput == stored (plaintext) — only hash comparison is allowed.
        // TimecardView.verifyPIN() is the biometric fallback path:
        // delegate to NetworkService.verifyPin() which uses constantTimeCompare(SHA256).
        Task {
            do {
                let verified = try await NetworkService.shared.verifyPin(
                    employeeId: localEmployee.id,
                    pinDigits: pinInput)
                await MainActor.run {
                    if verified {
                        showPINFallback = false
                        pinInput = ""
                        performClockAction()
                    } else {
                        pinError = "pin_error".localized(for: appLanguage)
                        pinInput = ""
                    }
                }
            } catch {
                await MainActor.run {
                    pinError = "Could not verify PIN. Check connection."
                    pinInput = ""
                }
            }
        }
    }

    /// simple SHA256 helper สำหรับ PIN comparison
    private func SHA256(_ input: String) -> String {
        let data = Data(input.utf8)
        let digest = CryptoKit.SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func performClockAction() {
        clockState = .uploading
        let now = Date()
        let confidence = dynamicConfidence()

        Task {
            do {
                if !isClockedIn {
                    // ── Clock In ──────────────────────────────────────────
                    let tc = Timecard(
                        id: UUID().uuidString,
                        employeeId: localEmployee.id,
                        employeeName: "\(localEmployee.firstName) \(localEmployee.lastName)",
                        clockIn: now.timeIntervalSince1970,
                        clockOut: nil,
                        breakDurationMinutes: 0,
                        overtimeMinutes: 0,
                        status: "approved",
                        notes: "Clock-in via AlphaPosStaff",
                        clockInFaceConfidence: confidence,
                        clockOutFaceConfidence: nil
                    )
                    _ = try await NetworkService.shared.uploadTimecard(timecard: tc)
                    let formatter = DateFormatter(); formatter.timeStyle = .short
                    await MainActor.run {
                        clockState = .success("Clocked in at \(formatter.string(from: now))")
                        APHaptic.trigger()
                    }
                } else if let active = todayActiveTimecard {
                    // ── Clock Out ─────────────────────────────────────────
                    let tc = Timecard(
                        id: active.id,
                        employeeId: localEmployee.id,
                        employeeName: "\(localEmployee.firstName) \(localEmployee.lastName)",
                        clockIn: active.clockIn,
                        clockOut: now.timeIntervalSince1970,
                        breakDurationMinutes: 0,
                        overtimeMinutes: 0,
                        status: "approved",
                        notes: "Clock-out via AlphaPosStaff",
                        clockInFaceConfidence: active.clockInFaceConfidence,
                        clockOutFaceConfidence: confidence
                    )
                    _ = try await NetworkService.shared.uploadTimecard(timecard: tc)
                    let duration = Int(now.timeIntervalSince1970 - active.clockIn) / 60
                    await MainActor.run {
                        clockState = .success("Clocked out · \(duration / 60)h \(duration % 60)m worked")
                        APHaptic.trigger()
                    }
                }

                // Reload และ reset state หลัง 2.5s
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                await MainActor.run {
                    clockState = .idle
                    loadTimecards()
                }

            } catch {
                await MainActor.run {
                    clockState = .failure("Failed to record. Please try again.")
                }
            }
        }
    }

    private func loadTimecards() {
        isLoadingTimecards = true
        Task {
            do {
                let list = try await NetworkService.shared.fetchTimecards(for: employee.id)
                await MainActor.run {
                    recentTimecards = list
                    activeTimecard  = todayActiveTimecard  // re-evaluate
                    isLoadingTimecards = false
                }
            } catch {
                await MainActor.run {
                    isLoadingTimecards = false
                    clockState = .failure("Could not load timecards. Check connection.")
                }
            }
        }
    }

    private func currentTimestamp() -> String {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short
        return f.string(from: Date())
    }

    private func dynamicConfidence() -> Double {
        // NOTE: Real biometric face recognition is not yet implemented.
        // Returning 0.0 so the database reflects "no biometric verification"
        // rather than storing a fabricated confidence score that misleads
        // managers reviewing attendance records.
        return 0.0
    }

    // MARK: - Face Enrollment

    private func startFaceEnrollment() {
        // SECURITY NOTE: Full biometric face recognition (Vision/ARKit embedding)
        // is not yet implemented. This feature is disabled until a real
        // face embedding pipeline is in place.
        // DO NOT re-enable mock enrollment — storing random hex as a face template
        // creates false audit trails and misleads anti-buddy-punching enforcement.
        registrationMessage = "Face ID enrollment is coming soon.\nPIN verification is active in the meantime."
        registrationSuccess = false
        isRegScanning = false
    }
}
