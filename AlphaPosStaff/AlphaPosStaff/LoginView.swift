import SwiftUI
import LocalAuthentication
import AVFoundation

struct LoginView: View {
    @Binding var loggedInEmployee: Employee?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("app_theme") private var appTheme = AppTheme.light.rawValue
    @AppStorage("active_merchant_id") private var activeMerchantId = ""
    @AppStorage("app_language") private var appLanguage = "en"
    
    @State private var employees: [Employee] = []
    @State private var selectedEmployee: Employee? = nil
    @State private var pendingLoggedInEmployee: Employee? = nil
    @State private var pinDigits: String = ""
    @State private var pinSheetMode: PinSheetMode = .pin
    
    enum PinSheetMode {
        case pin
        case biometrics
    }
    
    // Pairing & Store Onboarding States
    @State private var showingScannerSheet = false
    @State private var showingManualInputSheet = false
    @State private var manualStoreId = ""
    @State private var isScanningQR = false
    @State private var showingDisconnectAlert = false
    // Entry animation for the pairing screen (fade + rise on appear).
    @State private var pairingAppeared = false
    
    // Bio scan simulation states
    @State private var isBioScanning = false
    @State private var bioScanProgress: Double = 0.0
    @State private var bioScanSuccess = false
    @State private var bioScannerMessage = "Ready to Scan"
    
    @State private var isLoading = false
    @State private var profileLoadRetryCount = 0
    @State private var profileLoadState: ProfileLoadState = .idle
    @State private var pairingAwaitingApproval = false
    @State private var errorMessage: String? = nil
    @State private var errorTitle = ""
    @State private var errorSystemImage = "server.rack"
    @State private var isStoreIdCopied = false

    private enum ProfileLoadState {
        case idle, loading, loaded, confirmedEmpty
    }

    // ── Computed ─────────────────────────────────────────────────────────
    private var pairingCodeIsValid: Bool {
        let cleaned = manualStoreId.replacingOccurrences(of: " ", with: "")
        return cleaned.count == 6 && CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: cleaned))
    }

    var body: some View {

        ZStack {
            if activeMerchantId.isEmpty {
                pairingVideoBackground
                storePairingView
            } else {
                Color.appBackground.ignoresSafeArea()
                employeeSelectionView
            }
        }
        .onAppear {
            loadEmployees()
        }
        // PIN Pad & Biometrics Sheet
        .sheet(item: $selectedEmployee, onDismiss: {
            // Build the dashboard only after UIKit finishes dismissing the PIN
            // sheet. Starting both transitions together can block gesture gates.
            if let employee = pendingLoggedInEmployee {
                pendingLoggedInEmployee = nil
                loggedInEmployee = employee
            }
        }) { emp in
            Group {
                if pinSheetMode == .pin {
                    PinEntryView(
                        employee: emp,
                        pinDigits: $pinDigits,
                        onSuccess: {
                            // Associate this device's push token with the logged-in employee
                            NetworkService.shared.associatePushToken(with: emp.id)
                            pendingLoggedInEmployee = emp
                            selectedEmployee = nil
                        },
                        onTriggerBiometrics: {
                            withAnimation {
                                pinSheetMode = .biometrics
                            }
                        }
                    )
                } else {
                    biometricScannerView(for: emp)
                }
            }
            .presentationDetents([.fraction(0.85)])
            .presentationDragIndicator(.visible)
            .apColorScheme()
        }
        .sheet(isPresented: $showingScannerSheet) {
            pairingScannerView
                .apColorScheme()
        }
        // Manual store input sheet
        .sheet(isPresented: $showingManualInputSheet) {
            manualInputView
                .apColorScheme()
        }
        .alert("unlink_store_title".localized(for: appLanguage), isPresented: $showingDisconnectAlert) {
            Button("cancel".localized(for: appLanguage), role: .cancel) { }
            Button("unlink_store_title".localized(for: appLanguage), role: .destructive) {
                MerchantAuthManager.shared.logout()
                activeMerchantId = ""
                UserDefaults.standard.removeObject(forKey: "active_branch_id")
                UserDefaults.standard.removeObject(forKey: "paired_device_id")
                employees = []
            }
        } message: {
            Text("unlink_store_msg".localized(for: appLanguage))
        }
    }
    
    // MARK: - Subviews: Shared Headers
    
    private var languageMenu: some View {
        Menu {
            ForEach(AppLanguage.allCases) { lang in
                Button(action: {
                    APHaptic.trigger()
                    appLanguage = lang.rawValue
                }) {
                    HStack {
                        Text(lang.flag + " " + lang.displayName)
                        if appLanguage == lang.rawValue {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(AppLanguage(rawValue: appLanguage)?.flag ?? "🇺🇸")
                Text((AppLanguage(rawValue: appLanguage)?.rawValue.uppercased() ?? "EN"))
                    .font(.caption)
                    .fontWeight(.bold)
            }
            .foregroundColor(.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .apLiquidGlass(interactive: true, in: Capsule())
        }
    }
    
    private var themeToggleButton: some View {
        Button(action: {
            APHaptic.trigger()
            withAnimation {
                if appTheme == AppTheme.dark.rawValue {
                    appTheme = AppTheme.light.rawValue
                } else {
                    appTheme = AppTheme.dark.rawValue
                }
            }
        }) {
            Image(systemName: appTheme == AppTheme.dark.rawValue ? "sun.max.fill" : "moon.fill")
                .font(.title3)
                .foregroundColor(.textPrimary)
                .padding(12)
                .apLiquidGlass(interactive: true, in: Circle())
        }
    }
    
    private var unlinkButton: some View {
        Button(action: {
            APHaptic.trigger()
            showingDisconnectAlert = true
        }) {
            Image(systemName: "link.badge.plus")
                .font(.title3)
                .foregroundColor(.appAccent)
                .padding(12)
                .apLiquidGlass(interactive: true, in: Circle())
        }
    }
    
    // MARK: - Subviews: Store Pairing

    private var pairingVideoBackground: some View {
        ZStack {
            StaffLoopingVideoPlayer(videoName: "LoginBG")
            // Lighter dim so the video reads clearly — just enough contrast for
            // the few remaining elements. A soft bottom gradient keeps the
            // button/title legible without hiding the footage.
            LinearGradient(
                colors: [
                    Color.black.opacity(appTheme == AppTheme.dark.rawValue ? 0.28 : 0.16),
                    Color.black.opacity(appTheme == AppTheme.dark.rawValue ? 0.42 : 0.30)
                ],
                startPoint: .top, endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
    
    private var storePairingView: some View {
        // Ultra-minimal layout — let the background video dominate. Only three
        // small elements: a compact title block near the top, a translucent
        // floating QR glyph in the middle (no glass card), and a single primary
        // button + a tiny "enter manually" link at the bottom.
        VStack(spacing: 0) {
            // Header bar (language + theme)
            HStack {
                Spacer()
                languageMenu
                themeToggleButton
            }
            .padding(.horizontal, APSpacing.md)
            .padding(.top, APSpacing.sm)

            Spacer(minLength: 0)

            // Floating QR glyph — no card, sits directly on the video with a
            // sweeping scan-line so it reads as "scanner" while staying airy.
            ZStack {
                Image(systemName: "qrcode")
                    .font(.system(size: 60, weight: .regular))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 10, y: 2)

                // Sweeping scan line
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(colors: [.clear, Color.appAccent, .clear],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(width: 66, height: 2.5)
                    .offset(y: isScanningQR ? 30 : -30)
                    .opacity(0.9)
            }
            .scaleEffect(pairingAppeared ? 1 : 0.7)
            .opacity(pairingAppeared ? 1 : 0)

            Spacer().frame(height: 18)

            // Compact title + subtitle
            VStack(spacing: 5) {
                Text("link_store_title".localized(for: appLanguage))
                    .font(.system(size: 22, weight: .black))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.3), radius: 6, y: 1)

                Text("link_store_sub".localized(for: appLanguage))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
            }
            .padding(.horizontal, APSpacing.lg)
            .opacity(pairingAppeared ? 1 : 0)
            .offset(y: pairingAppeared ? 0 : 10)

            Spacer(minLength: 0)

            // Primary action + small manual link
            VStack(spacing: 12) {
                Button(action: {
                    APHaptic.trigger()
                    showingScannerSheet = true
                }) {
                    Label("scan_qr_code".localized(for: appLanguage), systemImage: "camera.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .apLiquidGlass(
                            tint: .appAccent.opacity(0.78),
                            interactive: true,
                            in: RoundedRectangle(cornerRadius: APRadius.md)
                        )
                }

                Button(action: {
                    APHaptic.trigger()
                    manualStoreId = ""
                    showingManualInputSheet = true
                }) {
                    Text("enter_manually".localized(for: appLanguage))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                        .underline()
                        .shadow(color: .black.opacity(0.3), radius: 4, y: 1)
                }
            }
            .padding(.horizontal, APSpacing.lg)
            .padding(.bottom, APSpacing.lg)
            .opacity(pairingAppeared ? 1 : 0)
            .offset(y: pairingAppeared ? 0 : 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(Animation.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                isScanningQR = true
            }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.82)) {
                pairingAppeared = true
            }
        }
    }
    
    private var pairingScannerView: some View {
        ZStack {
            PairingQRScannerView(
                onScan: handleScannedQRCode,
                onError: { errorMessage = $0 }
            )
            .ignoresSafeArea()

            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white, lineWidth: 3)
                .frame(width: 260, height: 260)

            VStack {
                HStack {
                    Spacer()
                    Button {
                        showingScannerSheet = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(12)
                            .background(.black.opacity(0.55), in: Circle())
                    }
                }
                .padding()

                Spacer()

                VStack(spacing: 10) {
                    if isLoading {
                        ProgressView().tint(.white)
                        Text("Pairing in progress...")
                    } else if let errorMessage {
                        Text(errorMessage).foregroundColor(.red)
                    } else {
                        Text("Scan the one-time QR code shown on AlphaPos")
                    }
                }
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundColor(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(.black.opacity(0.65))
            }
        }
    }
    
    private var manualInputView: some View {
        VStack(spacing: APSpacing.xl) {
            HStack {
                Spacer()
                Button("cancel".localized(for: appLanguage)) {
                    showingManualInputSheet = false
                }
                .foregroundColor(.appAccent)
                .padding()
            }
            
            VStack(spacing: APSpacing.sm) {
                Text("ป้อนรหัสเชื่อมต่อร้านค้า")
                    .font(.title2).fontWeight(.black)
                    .foregroundColor(.textPrimary)
                
                Text("ป้อนรหัสตัวเลข 6 หลักที่แสดงบนเครื่อง iPad POS")
                    .font(.subheadline)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            VStack(spacing: 8) {
                TextField("e.g. 123 456", text: $manualStoreId)
                    .font(.system(.title2, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .keyboardType(.numberPad)
                    .textFieldStyle(PlainTextFieldStyle())
                    .padding(14)
                    .background(Color.appSurfaceHigh)
                    .foregroundColor(.textPrimary)
                    .cornerRadius(APRadius.md)
                    .overlay(
                        RoundedRectangle(cornerRadius: APRadius.md)
                            .stroke(pairingCodeIsValid || manualStoreId.isEmpty ? Color.appBorderSubtle : Color.appRose.opacity(0.6), lineWidth: 1.5)
                    )
                    .padding(.horizontal, APSpacing.lg)
                    .onChange(of: manualStoreId) { _, newValue in
                        let cleaned = newValue.replacingOccurrences(of: " ", with: "")
                        if cleaned.count > 6 {
                            manualStoreId = String(cleaned.prefix(6))
                        } else {
                            manualStoreId = cleaned
                        }
                    }
                
                if isLoading {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text(pairingAwaitingApproval
                             ? "รออนุมัติจาก iPad POS..."
                             : "Pairing...")
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                            .multilineTextAlignment(.center)
                        if pairingAwaitingApproval {
                            Text("เมื่อเครื่องแม่กด Approve การเชื่อมต่อจะเสร็จทันที")
                                .font(.caption2)
                                .foregroundColor(.textTertiary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.top, 4)
                } else if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.appRose)
                        .padding(.top, 4)
                }
            }
            
            Button(action: {
                let cleaned = manualStoreId.replacingOccurrences(of: " ", with: "")
                if pairingCodeIsValid {
                    isLoading = true
                    pairingAwaitingApproval = false
                    errorMessage = nil
                    Task {
                        do {
                            // Flip UI into waiting state shortly after submit.
                            try await Task.sleep(nanoseconds: 400_000_000)
                            await MainActor.run { self.pairingAwaitingApproval = true }
                            let resolvedMerchantId = try await NetworkService.shared.validatePairingCode(code: cleaned)
                            await MainActor.run {
                                self.completePairing(with: resolvedMerchantId)
                                self.showingManualInputSheet = false
                                self.isLoading = false
                                self.pairingAwaitingApproval = false
                            }
                        } catch {
                            await MainActor.run {
                                self.errorMessage = error.localizedDescription
                                self.isLoading = false
                                self.pairingAwaitingApproval = false
                            }
                        }
                    }
                }
            }) {
                Text("link_shop".localized(for: appLanguage))
                    .apGradientButton(gradient: APGradient.accent, disabled: !pairingCodeIsValid || isLoading)
            }
            .disabled(!pairingCodeIsValid || isLoading)
            .padding(.horizontal, APSpacing.lg)
            
            Spacer()
        }
    }
    
    private func handleScannedQRCode(_ value: String) {
        guard !isLoading else { return }
        guard let components = URLComponents(string: value),
              components.scheme?.lowercased() == "alphapos",
              components.host?.lowercased() == "pair",
              let token = components.queryItems?.first(where: { $0.name == "token" })?.value,
              !token.isEmpty else {
            errorMessage = "This is not an AlphaPos pairing QR code"
            return
        }

        isLoading = true
        errorMessage = nil
        Task {
            do {
                let resolvedMerchantId = try await NetworkService.shared.validatePairingToken(token: token)
                await MainActor.run {
                    self.completePairing(with: resolvedMerchantId)
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
    
    private func completePairing(with uuid: String) {
        APHaptic.trigger()
        activeMerchantId = uuid
        profileLoadRetryCount = 0
        profileLoadState = .loading
        showingScannerSheet = false
        NotificationManager.shared.requestAuthorization()
        loadEmployees()
    }
    
    // MARK: - Subviews: Employee Selection

    @State private var headerAppeared = false
    @State private var cardsAppeared = false
    @State private var pressedEmployeeId: String? = nil
    @State private var selectedGlowId: String? = nil

    private var employeeSelectionView: some View {
        ZStack {
            // Layer 0: Aurora flowing background
            AuroraBackground()

            // Layer 0.5: Star field particles
            FloatingStarField()

            // Layer 1: Top control bar (glass morphism row)
            VStack {
                HStack(spacing: 12) {
                    unlinkButton
                    Spacer()
                    languageMenu
                    themeToggleButton
                }
                .padding(.horizontal, APSpacing.md)
                .padding(.top, APSpacing.sm)
                Spacer()
            }
            .opacity(headerAppeared ? 1 : 0)

            // Layer 2: Main content
            VStack(spacing: 0) {
                // Premium Animated Header
                VStack(spacing: APSpacing.md) {
                    Image("AppLogo")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .shadow(color: Color(red: 0.18, green: 0.44, blue: 0.97).opacity(0.4), radius: 12)
                        .opacity(headerAppeared ? 1 : 0)
                        .scaleEffect(headerAppeared ? 1 : 0.5)

                    // Gradient shimmer title
                    GradientTitleText(text: "AlphaPos Staff")
                        .opacity(headerAppeared ? 1 : 0)
                        .offset(y: headerAppeared ? 0 : -20)

                    // Glass pill store ID
                    GlassPillBadge(icon: "storefront", text: activeMerchantId)
                        .opacity(headerAppeared ? 1 : 0)
                        .offset(y: headerAppeared ? 0 : 10)

                    // Subtitle
                    Text("select_profile_title".localized(for: appLanguage))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .opacity(headerAppeared ? 0.8 : 0)
                }
                .padding(.top, 50)

                Spacer().frame(height: 30)

                // Content area
                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .tint(Color(red: 0.18, green: 0.44, blue: 0.97))
                        Text("Loading profiles...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxHeight: .infinity)
                } else if let err = errorMessage {
                    connectionIssueView(message: err)
                        .frame(maxHeight: .infinity)
                        .transition(.scale(scale: 0.94).combined(with: .opacity))
                } else if employees.isEmpty && profileLoadState == .confirmedEmpty {
                    emptyEmployeesView
                        .frame(maxHeight: .infinity)
                } else {
                    // Premium Employee Cards
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 24) {
                            ForEach(Array(employees.enumerated()), id: \.element.id) { index, emp in
                                premiumEmployeeCard(emp: emp, index: index)
                            }
                        }
                        .padding(.horizontal, 40)
                        .padding(.vertical, 8)
                    }
                    .offset(y: cardsAppeared ? 0 : 40)
                    .opacity(cardsAppeared ? 1 : 0)
                }

                Spacer()
            }
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.7).delay(0.05)) {
                headerAppeared = true
            }
            withAnimation(reduceMotion ? nil : .spring(response: 0.7, dampingFraction: 0.65).delay(0.35)) {
                cardsAppeared = true
            }
        }
    }

    private func connectionIssueView(message: String) -> some View {
        let networkAvailable = errorSystemImage != "wifi.slash"
        return VStack(spacing: APSpacing.lg) {
            ZStack {
                Circle()
                    .fill(Color.appRose.opacity(0.12))
                    .frame(width: 76, height: 76)
                Image(systemName: errorSystemImage)
                    .font(.system(size: 31, weight: .semibold))
                    .foregroundStyle(APGradient.accent)
                    .symbolEffect(.pulse, options: reduceMotion ? .nonRepeating : .repeating)
            }

            VStack(spacing: APSpacing.sm) {
                Text(errorTitle)
                    .font(.title3.weight(.bold))
                    .foregroundColor(.textPrimary)
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            HStack(spacing: 7) {
                Circle().fill(networkAvailable ? Color.appGreen : Color.appRose).frame(width: 7, height: 7)
                Text(networkAvailable
                     ? (appLanguage == "th" ? "อุปกรณ์เชื่อมต่อเครือข่ายแล้ว" : "Device network is connected")
                     : (appLanguage == "th" ? "อุปกรณ์ยังไม่มีเครือข่าย" : "Device network is disconnected"))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .apLiquidGlass(in: Capsule())

            Button {
                APHaptic.trigger()
                loadEmployees()
            } label: {
                Label("retry".localized(for: appLanguage), systemImage: "arrow.clockwise")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(APGradient.accent, in: Capsule())
            }
            .buttonStyle(PressableButtonStyle())
        }
        .padding(24)
        .frame(maxWidth: 350)
        .apLiquidGlass(in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .padding(.horizontal, APSpacing.lg)
    }

    private func premiumEmployeeCard(emp: Employee, index: Int) -> some View {
        let initials = String(emp.firstName.prefix(1)) + String(emp.lastName.prefix(1))
        let isPressed = pressedEmployeeId == emp.id
        let isSelected = selectedGlowId == emp.id

        return Button(action: {
            APHaptic.trigger()
            // Press animation
            withAnimation(.spring(response: 0.25, dampingFraction: 0.45)) {
                pressedEmployeeId = emp.id
                selectedGlowId = emp.id
            }
            // Release + open PIN after bounce
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    pressedEmployeeId = nil
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation {
                        selectedGlowId = nil
                        pinDigits = ""
                        pinSheetMode = .pin
                        selectedEmployee = emp
                    }
                }
            }
        }) {
            GlassCard(cornerRadius: 32) {
                VStack(spacing: 16) {
                    PremiumEmployeeAvatar(
                        initials: initials,
                        index: index,
                        size: 100,
                        isPressed: isPressed
                    )

                    VStack(spacing: 4) {
                        Text("\(emp.firstName) \(emp.lastName)")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        Text(emp.role)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    .opacity(headerAppeared ? 1 : 0)
                    .offset(y: headerAppeared ? 0 : 6)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                .frame(width: 160)
            }
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .shadow(
                color: isSelected
                    ? Color(red: 0.18, green: 0.44, blue: 0.97).opacity(0.25)
                    : Color.black.opacity(0.06),
                radius: isSelected ? 24 : 8,
                x: 0,
                y: isSelected ? 8 : 4
            )
        }
        .buttonStyle(.plain)
    }

    private var emptyEmployeesView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: APSpacing.lg) {
                Spacer().frame(height: 10)
                
                // Redesigned Warning / Info Header Card
                VStack(spacing: APSpacing.md) {
                    ZStack {
                        Circle()
                            .fill(Color.appAmber.opacity(0.15))
                            .frame(width: 80, height: 80)
                        
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(APGradient.accent)
                    }
                    .padding(.top, 8)
                    
                    Text(appLanguage == "th" ? "กำลังตรวจสอบข้อมูลพนักงาน" : "Staff profiles are being checked")
                        .font(.title3)
                        .fontWeight(.black)
                        .foregroundColor(.textPrimary)
                        .multilineTextAlignment(.center)
                    
                    Text(appLanguage == "th"
                         ? "ขณะนี้ยังไม่มีรายชื่อแสดงในอุปกรณ์ กรุณากดรีเฟรชเพื่อโหลดข้อมูลล่าสุด ระบบไม่ได้ลบหรือแก้ไขข้อมูลพนักงานของคุณ"
                         : "No profiles are currently displayed on this device. Refresh to load the latest staff data. Your staff records have not been deleted or changed.")
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, APSpacing.sm)
                }
                .apCard(padding: APSpacing.lg)
                .padding(.horizontal, APSpacing.md)
                
                // Interactive Device Store ID Container with Clipboard Copy
                VStack(spacing: APSpacing.xs) {
                    Text("store".localized(for: appLanguage).uppercased())
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.textTertiary)
                    
                    HStack(spacing: APSpacing.sm) {
                        Text(activeMerchantId)
                            .font(.system(.caption, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundColor(.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.appSurfaceHigh)
                            .cornerRadius(APRadius.sm)
                        
                        Button(action: {
                            copyStoreIdToClipboard()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: isStoreIdCopied ? "checkmark.circle.fill" : "doc.on.doc.fill")
                                    .font(.footnote)
                                    .foregroundColor(isStoreIdCopied ? .appTeal : .appAccent)
                                Text((isStoreIdCopied ? "copied" : "copy_store_id").localized(for: appLanguage))
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(isStoreIdCopied ? .appTeal : .appAccent)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(isStoreIdCopied ? Color.appTeal.opacity(0.1) : Color.appAccent.opacity(0.1))
                            .cornerRadius(APRadius.sm)
                        }
                    }
                }
                .padding(.horizontal, APSpacing.md)
                
                // Step-by-Step Instructions Title
                VStack(alignment: .leading, spacing: APSpacing.xs) {
                    Text("onboarding_guide_title".localized(for: appLanguage))
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.textPrimary)
                    
                    Text("onboarding_guide_sub".localized(for: appLanguage))
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, APSpacing.md)
                .padding(.top, 4)
                
                // Step Cards
                VStack(spacing: APSpacing.sm) {
                    stepCard(number: "1", icon: "ipad.and.iphone", text: "onboarding_step1".localized(for: appLanguage))
                    stepCard(number: "2", icon: "checkmark.seal.fill", text: "onboarding_step2".localized(for: appLanguage))
                    stepCard(number: "3", icon: "arrow.clockwise.circle.fill", text: "onboarding_step3".localized(for: appLanguage))
                }
                .padding(.horizontal, APSpacing.md)
                
                // Action Buttons
                VStack(spacing: APSpacing.sm) {
                    Button(action: {
                        loadEmployees()
                    }) {
                        Label("refresh_profiles".localized(for: appLanguage), systemImage: "arrow.clockwise")
                            .apGradientButton(gradient: APGradient.accent)
                    }
                    
                    Button(action: {
                        APHaptic.trigger()
                        showingDisconnectAlert = true
                    }) {
                        Label("change_store_id".localized(for: appLanguage), systemImage: "link.badge.plus")
                            .font(.headline)
                            .foregroundColor(.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, APSpacing.md)
                            .background(Color.appSurface)
                            .cornerRadius(APRadius.md)
                            .overlay(
                                RoundedRectangle(cornerRadius: APRadius.md)
                                    .stroke(Color.appBorderSubtle, lineWidth: 1)
                            )
                    }
                    
                }
                .padding(.horizontal, APSpacing.md)
                .padding(.bottom, APSpacing.lg)
            }
        }
    }
    
    private func stepCard(number: String, icon: String, text: String) -> some View {
        HStack(spacing: APSpacing.md) {
            ZStack {
                Circle()
                    .fill(APGradient.accent.opacity(0.15))
                    .frame(width: 40, height: 40)
                
                Image(systemName: icon)
                    .font(.footnote)
                    .foregroundStyle(APGradient.accent)
            }
            
            Text(text)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.textPrimary)
                .multilineTextAlignment(.leading)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer()
        }
        .padding(APSpacing.md)
        .background(Color.appSurface)
        .cornerRadius(APRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: APRadius.md)
                .stroke(Color.appBorderSubtle, lineWidth: 1)
        )
    }
    
    private func copyStoreIdToClipboard() {
        APHaptic.trigger()
        UIPasteboard.general.string = activeMerchantId
        withAnimation {
            isStoreIdCopied = true
        }
        // Reset after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            withAnimation {
                isStoreIdCopied = false
            }
        }
    }
    
    private func loadEmployees() {
        guard !activeMerchantId.isEmpty else {
            employees = []
            return
        }
        guard !StaffSessionContext.branchId.isEmpty else {
            employees = []
            errorTitle = appLanguage == "th" ? "ต้องเชื่อมต่อสาขาใหม่" : "Branch pairing required"
            errorSystemImage = "point.3.connected.trianglepath.dotted"
            errorMessage = appLanguage == "th"
                ? "ข้อมูลการเชื่อมต่อเดิมไม่มีรหัสสาขา กรุณายกเลิกการเชื่อมโยงแล้วจับคู่กับเครื่องหลักใหม่"
                : "This pairing has no branch identity. Unlink and pair with the main register again."
            return
        }
        // Never retain profiles from a previous request, merchant, or branch.
        // The server response below is the complete authoritative login list.
        employees = []
        isLoading = true
        profileLoadState = .loading
        errorMessage = nil
        errorTitle = ""
        errorSystemImage = "server.rack"
        Task {
            do {
                let mId = activeMerchantId.trimmingCharacters(in: .whitespacesAndNewlines)
                
                let access = try await NetworkService.shared.fetchStaffSubscriptionAccess()
                guard access.merchantID.uuidString.lowercased() == mId.lowercased() else {
                    throw NetworkError.invalidResponse
                }
                if !access.isAllowed {
                    await MainActor.run {
                        let message = access.message(thai: appLanguage == "th")
                        self.isLoading = false
                        self.errorTitle = message.title
                        self.errorMessage = message.body
                        self.errorSystemImage = "creditcard.trianglebadge.exclamationmark"
                    }
                    return
                }

                // Load profiles only after the server grants staff-device access.
                let list = try await NetworkService.shared.fetchEmployees()
                await MainActor.run {
                    // Pairing writes the branch claim and token immediately before
                    // this request. Retry quietly if the first request lands while
                    // that state is still settling, instead of showing a scary
                    // "no staff" warning to the user.
                    if list.isEmpty && self.profileLoadRetryCount < 2 {
                        self.profileLoadRetryCount += 1
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            self.loadEmployees()
                        }
                        return
                    }
                    self.employees = list
                    self.isLoading = false
                    self.profileLoadState = list.isEmpty ? .confirmedEmpty : .loaded
                    self.profileLoadRetryCount = 0
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.profileLoadState = .idle
                    self.presentLoadError(error)
                }
            }
        }
    }

    private func presentLoadError(_ error: Error) {
        #if DEBUG
        print("LoginView [Load Employees]: \(error)")
        #endif

        let urlCode = (error as? URLError)?.code
        if urlCode == .notConnectedToInternet || urlCode == .networkConnectionLost {
            errorTitle = appLanguage == "th" ? "เครือข่ายขาดการเชื่อมต่อ" : "Network disconnected"
            errorSystemImage = "wifi.slash"
            errorMessage = appLanguage == "th"
                ? "อุปกรณ์ยังเข้าเครือข่ายไม่ได้ กรุณาตรวจสอบ Wi‑Fi หรือเครือข่ายมือถือแล้วลองใหม่"
                : "This device cannot reach the network. Check Wi‑Fi or cellular data and try again."
        } else if urlCode == .cannotConnectToHost || urlCode == .cannotFindHost || urlCode == .timedOut || urlCode == .secureConnectionFailed {
            errorTitle = appLanguage == "th" ? "เซิร์ฟเวอร์ไม่ตอบสนอง" : "Server unavailable"
            errorSystemImage = "server.rack"
            errorMessage = appLanguage == "th"
                ? "อินเทอร์เน็ตพร้อมใช้งาน แต่ยังติดต่อบริการ AlphaPos ไม่ได้ กรุณาลองใหม่หรือตรวจสอบเซิร์ฟเวอร์"
                : "Internet is available, but AlphaPos cannot be reached. Try again or check the server."
        } else if let authError = error as? AuthError, case .tokenExpired = authError {
            errorTitle = appLanguage == "th" ? "เซสชันร้านค้าหมดอายุ" : "Store session expired"
            errorSystemImage = "key.slash"
            errorMessage = appLanguage == "th"
                ? "ไม่สามารถต่ออายุสิทธิ์ของอุปกรณ์ได้ กรุณายกเลิกการเชื่อมโยงแล้วเชื่อมต่อร้านค้าอีกครั้ง"
                : "This device could not renew its store access. Unlink and pair the store again."
        } else if case NetworkError.invalidResponse = error {
            errorTitle = appLanguage == "th" ? "ตรวจสอบข้อมูลไม่สำเร็จ" : "Unable to verify data"
            errorSystemImage = "exclamationmark.icloud"
            errorMessage = appLanguage == "th"
                ? "ข้อมูลจากเซิร์ฟเวอร์ไม่ครบถ้วน กรุณาลองใหม่ หากยังพบปัญหาให้ติดต่อฝ่ายสนับสนุน"
                : "The server returned incomplete data. Retry or contact support if the problem persists."
        } else if (error as NSError).domain == "NetworkService", (error as NSError).code == 404 {
            errorTitle = appLanguage == "th" ? "ไม่พบร้านค้านี้" : "Store not found"
            errorSystemImage = "storefront"
            errorMessage = appLanguage == "th"
                ? "รหัสร้านค้าไม่ตรงกับข้อมูลบนเซิร์ฟเวอร์ กรุณาเชื่อมโยงร้านค้าอีกครั้ง"
                : "This store ID does not match a store on the server. Pair the store again."
        } else {
            errorTitle = appLanguage == "th" ? "บริการออนไลน์ขัดข้อง" : "Cloud service error"
            errorSystemImage = "exclamationmark.icloud"
            errorMessage = appLanguage == "th"
                ? "เชื่อมต่ออินเทอร์เน็ตแล้ว แต่บริการส่งข้อมูลกลับมาไม่สำเร็จ กรุณาลองใหม่ภายหลัง"
                : "Internet is connected, but the service returned an error. Please try again later."
        }
    }
    
    // MARK: - Biometric Scanner Sheet
    
    private func biometricScannerView(for employee: Employee) -> some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            
            VStack(spacing: APSpacing.xl) {
                APBadge(text: "biometric_auth".localized(for: appLanguage), color: .appAccent, icon: "faceid")
                    .padding(.top, APSpacing.xl)
                
                Text("biometric_scan_sub".localized(for: appLanguage))
                    .font(.subheadline)
                    .foregroundColor(.textSecondary)
                
                Text("\(employee.firstName) \(employee.lastName)")
                    .font(.title2).fontWeight(.black)
                    .foregroundColor(.textPrimary)
                
                // Sensor view
                ZStack {
                    Circle()
                        .fill(Color.appSurface)
                        .frame(width: 200, height: 200)
                        .overlay(
                            Circle()
                                .stroke(isBioScanning ? APGradient.accent : LinearGradient(colors: [Color.appDivider], startPoint: .top, endPoint: .bottom), lineWidth: 3)
                        )
                    
                    Image(systemName: "faceid")
                        .font(.system(size: 88, weight: .ultraLight))
                        .foregroundStyle(isBioScanning ? APGradient.accent : LinearGradient(colors: [Color.textTertiary], startPoint: .top, endPoint: .bottom))
                    
                    if isBioScanning {
                        Circle()
                            .trim(from: 0.0, to: bioScanProgress)
                            .stroke(APGradient.positive, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .frame(width: 200, height: 200)
                            .rotationEffect(.degrees(-90))
                    }
                }
                .frame(width: 220, height: 220)
                
                Text(bioScanSuccess ? "biometric_success".localized(for: appLanguage) : (isBioScanning ? "biometric_scanning".localized(for: appLanguage) : "ready_to_scan".localized(for: appLanguage)))
                    .font(.headline)
                    .foregroundColor(bioScanSuccess ? .appTeal : .textSecondary)
                
                if !isBioScanning && !bioScanSuccess {
                    Button(action: {
                        startBiometricScan(for: employee)
                    }) {
                        Label("authenticate_now".localized(for: appLanguage), systemImage: "faceid")
                            .apGradientButton()
                    }
                    .padding(.horizontal, APSpacing.xl)
                }
                
                Spacer()
            }
        }
    }
    
    private func startBiometricScan(for employee: Employee) {
        isBioScanning = false
        bioScanSuccess = false
        bioScanProgress = 0
        bioScannerMessage = appLanguage == "th"
            ? "ระบบจดจำใบหน้าพนักงานยังไม่พร้อม กรุณาเข้าสู่ระบบด้วย PIN"
            : "Employee face recognition is not available. Please sign in with your PIN."
    }
}

// MARK: - Subviews: PIN Entry

struct PinEntryView: View {
    let employee: Employee
    @Binding var pinDigits: String
    
    let onSuccess: () -> Void
    let onTriggerBiometrics: () -> Void
    
    @AppStorage("app_language") private var appLanguage = "en"
    @State private var showPinError = false
    @State private var pinErrorMessage = ""
    @State private var isVerifying = false
    @State private var failedAttempts = 0
    @State private var isLocked = false
    @State private var lockoutTimer: Timer?
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    
    private let maxFailedAttempts = 5
    private let lockoutDuration: TimeInterval = 30
    
    var isLandscape: Bool {
        verticalSizeClass == .compact || (UIDevice.current.userInterfaceIdiom == .phone && UIScreen.main.bounds.width > UIScreen.main.bounds.height)
    }

    var body: some View {
        Group {
            if isLandscape {
                HStack(alignment: .center, spacing: 32) {
                    VStack(spacing: APSpacing.md) {
                        Text("enter_pin_for".localized(for: appLanguage) + " \(employee.firstName)")
                            .font(.headline)
                            .foregroundColor(.textPrimary)
                            .multilineTextAlignment(.center)
                        
                        HStack(spacing: APSpacing.md) {
                            ForEach(0..<4, id: \.self) { index in
                                Circle()
                                    .fill(index < pinDigits.count ? Color.appAccent : Color.appSurfaceHigh)
                                    .frame(width: 18, height: 18)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.appBorderSubtle, lineWidth: 1)
                                    )
                            }
                        }
                        .padding(.vertical, APSpacing.xs)
                        .shake(trigger: showPinError)
                        
                        if isVerifying {
                            verificationIndicator
                        } else if showPinError {
                            Text(pinErrorMessage)
                                .font(.caption)
                                .foregroundColor(.appRose)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    
                    keypadView
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, APSpacing.xl)
                .padding(.vertical, APSpacing.sm)
            } else {
                VStack(spacing: APSpacing.lg) {
                    Text("enter_pin_for".localized(for: appLanguage) + " \(employee.firstName)")
                        .font(.headline)
                        .foregroundColor(.textPrimary)
                        .padding(.top, APSpacing.lg)
                    
                    HStack(spacing: APSpacing.md) {
                        ForEach(0..<4, id: \.self) { index in
                            Circle()
                                .fill(index < pinDigits.count ? Color.appAccent : Color.appSurfaceHigh)
                                .frame(width: 20, height: 20)
                                .overlay(
                                    Circle()
                                        .stroke(Color.appBorderSubtle, lineWidth: 1)
                                )
                        }
                    }
                    .padding(.vertical, APSpacing.sm)
                    .shake(trigger: showPinError)
                    
                    if isVerifying {
                        verificationIndicator
                    } else if showPinError {
                        Text(pinErrorMessage)
                            .font(.caption)
                            .foregroundColor(.appRose)
                    }
                    
                    keypadView
                }
                .padding(.horizontal, APSpacing.lg)
                .padding(.bottom, APSpacing.lg)
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    private var keypadView: some View {
        let buttonSize: CGFloat = isLandscape ? 56 : 70
        let spacingValue: CGFloat = isLandscape ? 8 : 16
        
        return VStack(spacing: spacingValue) {
            ForEach(0..<3) { row in
                HStack(spacing: spacingValue) {
                    ForEach(1...3, id: \.self) { col in
                        let num = row * 3 + col
                        keypadButton(text: "\(num)", size: buttonSize)
                    }
                }
            }
            
            HStack(spacing: spacingValue) {
                // Biometrics button
                Button(action: {
                    APHaptic.trigger()
                    onTriggerBiometrics()
                }) {
                    Image(systemName: "faceid")
                        .font(isLandscape ? .body : .title).fontWeight(.semibold)
                        .foregroundColor(.appAccent)
                        .frame(width: buttonSize, height: buttonSize)
                        .background(Color.appSurface)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.appBorderSubtle, lineWidth: 1))
                }
                .disabled(true)
                .opacity(0.45)
                .accessibilityLabel(appLanguage == "th" ? "ระบบจดจำใบหน้ายังไม่พร้อม" : "Face recognition unavailable")
                .accessibilityHint(appLanguage == "th" ? "กรุณาใช้ PIN" : "Use your employee PIN")
                
                keypadButton(text: "0", size: buttonSize)
                
                // Backspace button
                Button(action: {
                    APHaptic.trigger()
                    if !pinDigits.isEmpty {
                        pinDigits.removeLast()
                    }
                }) {
                    Image(systemName: "delete.left.fill")
                        .font(isLandscape ? .body : .title).fontWeight(.semibold)
                        .foregroundColor(.textPrimary)
                        .frame(width: buttonSize, height: buttonSize)
                        .background(Color.appSurface)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.appBorderSubtle, lineWidth: 1))
                }
            }
        }
        .disabled(isVerifying)
        .opacity(isVerifying ? 0.55 : 1)
    }

    private var verificationIndicator: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("pin_verifying".localized(for: appLanguage))
                .font(.caption.weight(.semibold))
        }
        .foregroundColor(.appAccent)
        .accessibilityElement(children: .combine)
    }
    
    private func keypadButton(text: String, size: CGFloat) -> some View {
        Button(action: {
            guard !isLocked, !isVerifying else { return }
            APHaptic.trigger()
            showPinError = false
            if pinDigits.count < 4 {
                pinDigits.append(text)
                
                if pinDigits.count == 4 {
                    let submittedPin = pinDigits
                    isVerifying = true
                    Task {
                        do {
                            // Credential hashes stay on the server; this is one RPC call.
                            let verified = try await NetworkService.shared.verifyPin(employeeId: employee.id, pinDigits: submittedPin)
                            await MainActor.run {
                                isVerifying = false
                                if verified {
                                    failedAttempts = 0
                                    pinDigits = ""
                                    onSuccess()
                                } else {
                                    failedAttempts += 1
                                    showPinError = true
                                    pinErrorMessage = "pin_error".localized(for: appLanguage)
                                    pinDigits = ""
                                    APHaptic.trigger()
                                    if failedAttempts >= maxFailedAttempts {
                                        isLocked = true
                                        lockoutTimer = Timer.scheduledTimer(withTimeInterval: lockoutDuration, repeats: false) { _ in
                                            isLocked = false
                                            failedAttempts = 0
                                        }
                                    }
                                }
                            }
                        } catch {
                            await MainActor.run {
                                isVerifying = false
                                showPinError = true
                                pinErrorMessage = "pin_network_error".localized(for: appLanguage)
                                pinDigits = ""
                                APHaptic.trigger()
                            }
                        }
                    }
                }
            }
        }) {
            Text(text)
                .font(isLandscape ? .title2 : .title).fontWeight(.bold)
                .foregroundColor(.textPrimary)
                .frame(width: size, height: size)
                .background(Color.appSurfaceHigh)
                .clipShape(Circle())
        }
    }
}

// Shake Effect Modifier
struct Shake: GeometryEffect {
    var amount: CGFloat = 10
    var shakesPerUnit = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX:
            amount * sin(animatableData * .pi * CGFloat(shakesPerUnit)),
            y: 0))
    }
}

extension View {
    func shake(trigger: Bool) -> some View {
        modifier(ShakeModifier(trigger: trigger))
    }
}

struct ShakeModifier: ViewModifier {
    let trigger: Bool
    @State private var animatableValue: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .keyframeAnimator(initialValue: 0.0, trigger: trigger) { content, value in
                content.offset(x: sin(value * .pi * 5) * 8)
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(1.0, duration: 0.25)
                }
            }
    }
}

private struct StaffLoopingVideoPlayer: UIViewRepresentable {
    let videoName: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        if let url = Bundle.main.url(forResource: videoName, withExtension: "mp4") {
            context.coordinator.play(url, in: view)
        }
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {}

    final class Coordinator {
        private var player: AVQueuePlayer?
        private var looper: AVPlayerLooper?

        func play(_ url: URL, in view: PlayerView) {
            let player = AVQueuePlayer()
            player.isMuted = true
            // Render at the highest quality the source allows (no artificial cap),
            // so a 1080p LoginBG.mp4 shows crisp instead of being downscaled.
            let asset = AVURLAsset(url: url, options: [
                AVURLAssetPreferPreciseDurationAndTimingKey: true
            ])
            let item = AVPlayerItem(asset: asset)
            item.preferredMaximumResolution = .zero          // .zero = no downscale cap
            item.preferredPeakBitRate = 0                     // 0 = unlimited (use full quality)
            if #available(iOS 14.0, *) {
                item.appliesPerFrameHDRDisplayMetadata = true
            }
            looper = AVPlayerLooper(player: player, templateItem: item)
            self.player = player
            view.playerLayer.player = player
            // Crisper scaling when the layer is larger than the video frame.
            view.playerLayer.magnificationFilter = .trilinear
            player.play()
        }
    }

    final class PlayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

        override init(frame: CGRect) {
            super.init(frame: frame)
            playerLayer.videoGravity = .resizeAspectFill
        }

        required init?(coder: NSCoder) { nil }
    }
}
