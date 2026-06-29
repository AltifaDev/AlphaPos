import SwiftUI
import CryptoKit
import LocalAuthentication

struct LoginView: View {
    @Binding var loggedInEmployee: Employee?
    @AppStorage("app_theme") private var appTheme = AppTheme.light.rawValue
    @AppStorage("active_merchant_id") private var activeMerchantId = ""
    @AppStorage("app_language") private var appLanguage = "en"
    
    @State private var employees: [Employee] = []
    @State private var selectedEmployee: Employee? = nil
    @State private var pinDigits: String = ""
    @State private var pinSheetMode: PinSheetMode = .pin
    
    enum PinSheetMode {
        case pin
        case biometrics
    }
    
    @State private var showingLinkAlert = false
    @State private var inputMerchantId = ""
    
    // Pairing & Store Onboarding States
    @State private var showingScannerSheet = false
    @State private var showingManualInputSheet = false
    @State private var manualStoreId = ""
    @State private var isScanningQR = false
    @State private var scanProgress: Double = 0.0
    @State private var isSimulatingScan = false
    @State private var showingDisconnectAlert = false
    
    // Bio scan simulation states
    @State private var isBioScanning = false
    @State private var bioScanProgress: Double = 0.0
    @State private var bioScanSuccess = false
    @State private var bioScannerMessage = "Ready to Scan"
    
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var isStoreIdCopied = false

    // ── Computed ─────────────────────────────────────────────────────────
    private var uuidIsValid: Bool {
        let trimmed = manualStoreId.trimmingCharacters(in: .whitespacesAndNewlines)
        let uuidRegex = #"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"#
        return trimmed.range(of: uuidRegex, options: .regularExpression) != nil
    }

    var body: some View {

        ZStack {
            Color.appBackground.ignoresSafeArea()
            
            if activeMerchantId.isEmpty {
                storePairingView
            } else {
                employeeSelectionView
            }
        }
        .onAppear {
            loadEmployees()
        }
        // PIN Pad & Biometrics Sheet
        .sheet(item: $selectedEmployee) { emp in
            Group {
                if pinSheetMode == .pin {
                    PinEntryView(
                        employee: emp,
                        pinDigits: $pinDigits,
                        onSuccess: {
                            loggedInEmployee = emp
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
        // Scanner simulation sheet
        .sheet(isPresented: $showingScannerSheet) {
            simulatedScannerView
                .apColorScheme()
        }
        // Manual store input sheet
        .sheet(isPresented: $showingManualInputSheet) {
            manualInputView
                .apColorScheme()
        }
        .alert("link_shop".localized(for: appLanguage), isPresented: $showingLinkAlert) {
            TextField("Merchant UUID", text: $inputMerchantId)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button("cancel".localized(for: appLanguage), role: .cancel) { }
            Button("link_shop".localized(for: appLanguage)) {
                let cleaned = inputMerchantId.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty {
                    activeMerchantId = cleaned
                    loadEmployees()
                }
            }
        } message: {
            Text("enter_store_id_sub".localized(for: appLanguage))
        }
        .alert("unlink_store_title".localized(for: appLanguage), isPresented: $showingDisconnectAlert) {
            Button("cancel".localized(for: appLanguage), role: .cancel) { }
            Button("unlink_store_title".localized(for: appLanguage), role: .destructive) {
                activeMerchantId = ""
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
            .foregroundColor(.appAccent)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color.appSurface)
                    .shadow(color: Color.black.opacity(0.1), radius: 4)
            )
            .overlay(
                Capsule()
                    .stroke(Color.appBorderSubtle, lineWidth: 1)
            )
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
                .foregroundColor(.appAccent)
                .padding(12)
                .background(
                    Circle()
                        .fill(Color.appSurface)
                        .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
                )
                .overlay(
                    Circle()
                        .stroke(Color.appBorderSubtle, lineWidth: 1)
                )
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
                .background(
                    Circle()
                        .fill(Color.appSurface)
                        .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
                )
                .overlay(
                    Circle()
                        .stroke(Color.appBorderSubtle, lineWidth: 1)
                )
        }
    }
    
    // MARK: - Subviews: Store Pairing
    
    private var storePairingView: some View {
        VStack(spacing: 0) {
            // Header bar for pairing
            HStack {
                Spacer()
                
                languageMenu
                
                themeToggleButton
            }
            .padding(.horizontal, APSpacing.md)
            .padding(.top, APSpacing.md)
            
            ScrollView {
                VStack(spacing: APSpacing.xl) {
                    Spacer().frame(height: 20)
                    
                    // Welcome Header
                    VStack(spacing: APSpacing.xs) {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.system(size: 64))
                            .foregroundStyle(APGradient.accent)
                            .padding(.bottom, APSpacing.sm)
                        
                        Text("link_store_title".localized(for: appLanguage))
                            .font(.title).fontWeight(.black)
                            .foregroundColor(.textPrimary)
                        
                        Text("link_store_sub".localized(for: appLanguage))
                            .font(.subheadline)
                            .foregroundColor(.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, APSpacing.lg)
                    
                    // Visual Pairing Card (Pulsing QR Code Mockup)
                    ZStack {
                        RoundedRectangle(cornerRadius: APRadius.lg)
                            .fill(Color.appSurface)
                            .frame(height: 240)
                            .shadow(color: Color.black.opacity(0.1), radius: 10)
                            .overlay(
                                RoundedRectangle(cornerRadius: APRadius.lg)
                                    .stroke(Color.appBorderSubtle, lineWidth: 1)
                            )
                        
                        VStack(spacing: APSpacing.md) {
                            ZStack {
                                Circle()
                                    .stroke(APGradient.accent, lineWidth: 3)
                                    .frame(width: 100, height: 100)
                                    .scaleEffect(isScanningQR ? 1.1 : 1.0)
                                    .opacity(isScanningQR ? 0.5 : 1.0)
                                
                                Image(systemName: "qrcode")
                                    .font(.system(size: 48))
                                    .foregroundStyle(APGradient.accent)
                            }
                            
                            Text("scan_pairing_qr_desc".localized(for: appLanguage))
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                    }
                    .padding(.horizontal, APSpacing.lg)
                    .onAppear {
                        withAnimation(Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                            isScanningQR = true
                        }
                    }
                    
                    // Action Buttons
                    VStack(spacing: APSpacing.md) {
                        Button(action: {
                            APHaptic.trigger()
                            showingScannerSheet = true
                        }) {
                            Label("scan_qr_code".localized(for: appLanguage), systemImage: "camera.fill")
                                .apGradientButton(gradient: APGradient.accent)
                        }
                        
                        Button(action: {
                            APHaptic.trigger()
                            manualStoreId = ""
                            showingManualInputSheet = true
                        }) {
                            Label("enter_manually".localized(for: appLanguage), systemImage: "keyboard")
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
                    .padding(.horizontal, APSpacing.lg)
                    
                    Spacer()
                    
                    // Quick Demo Link for Developer testing
                    Button(action: {
                        APHaptic.trigger()
                        activeMerchantId = "163350b0-056d-4d5e-b5d4-24e7aac5ab6d"
                        loadEmployees()
                    }) {
                        Text("sandbox_demo".localized(for: appLanguage))
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.appAccent)
                            .underline()
                    }
                    .padding(.bottom, APSpacing.lg)
                }
            }
        }
    }
    
    private var simulatedScannerView: some View {
        VStack(spacing: APSpacing.xl) {
            HStack {
                Spacer()
                Button("close".localized(for: appLanguage)) {
                    showingScannerSheet = false
                }
                .foregroundColor(.appAccent)
                .padding()
            }
            
            Text("scan_pairing_qr_title".localized(for: appLanguage))
                .font(.headline)
                .foregroundColor(.textPrimary)
            
            // Camera viewfinder simulator
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(APGradient.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [40, 20]))
                    .frame(width: 250, height: 250)
                
                if isSimulatingScan {
                    // Pulsing red scan line
                    Rectangle()
                        .fill(Color.appRose)
                        .frame(width: 230, height: 2)
                        .offset(y: scanProgress)
                        .onAppear {
                            withAnimation(Animation.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                                scanProgress = 110
                            }
                        }
                }
            }
            .frame(width: 260, height: 260)
            .onAppear {
                isSimulatingScan = true
                scanProgress = -110
            }
            
            Text("select_simulated_store".localized(for: appLanguage))
                .font(.subheadline)
                .foregroundColor(.textSecondary)
            
            VStack(spacing: APSpacing.sm) {
                Button(action: {
                    completePairing(with: "163350b0-056d-4d5e-b5d4-24e7aac5ab6d") // Demo
                }) {
                    Text("simulate_sandbox".localized(for: appLanguage))
                        .font(.subheadline)
                        .foregroundColor(.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.appSurface)
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorderSubtle, lineWidth: 1))
                }
                
                Button(action: {
                    completePairing(with: "662c6861-1200-47b2-bd77-160b73c4d9bc") // Cafe Terrace
                }) {
                    Text("simulate_cafe".localized(for: appLanguage))
                        .font(.subheadline)
                        .foregroundColor(.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.appSurface)
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorderSubtle, lineWidth: 1))
                }
            }
            .padding(.horizontal, APSpacing.lg)
            
            Spacer()
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
                Text("enter_store_id".localized(for: appLanguage))
                    .font(.title2).fontWeight(.black)
                    .foregroundColor(.textPrimary)
                
                Text("enter_store_id_sub".localized(for: appLanguage))
                    .font(.subheadline)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            TextField("e.g. 163350b0-056d-4d5e-b5d4-24e7aac5ab6d", text: $manualStoreId)
                .font(.system(.body, design: .monospaced))
                .textFieldStyle(PlainTextFieldStyle())
                .padding(14)
                .background(Color.appSurfaceHigh)
                .foregroundColor(.textPrimary)
                .cornerRadius(APRadius.md)
                .overlay(
                    RoundedRectangle(cornerRadius: APRadius.md)
                        .stroke(uuidIsValid || manualStoreId.isEmpty ? Color.appBorderSubtle : Color.appRose.opacity(0.6), lineWidth: 1.5)
                )
                .padding(.horizontal, APSpacing.lg)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            // Inline UUID validation hint
            if !manualStoreId.isEmpty && !uuidIsValid {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.appRose)
                    Text("invalid_uuid_format".localized(for: appLanguage))
                        .font(.caption)
                        .foregroundColor(.appRose)
                }
                .padding(.horizontal, APSpacing.lg)
            }

            Button(action: {
                let cleaned = manualStoreId.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty && uuidIsValid {
                    completePairing(with: cleaned)
                    showingManualInputSheet = false
                }
            }) {
                Text("link_shop".localized(for: appLanguage))
                    .apGradientButton(gradient: APGradient.accent, disabled: !uuidIsValid)
            }
            .disabled(!uuidIsValid)
            .padding(.horizontal, APSpacing.lg)
            
            Spacer()
        }
    }
    
    private func completePairing(with uuid: String) {
        APHaptic.trigger()
        activeMerchantId = uuid
        showingScannerSheet = false
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
                    // Grid icon with glow
                    Image(systemName: "square.grid.3x3.fill")
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.18, green: 0.44, blue: 0.97),
                                    Color(red: 0.36, green: 0.64, blue: 1.0)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
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
                    VStack(spacing: APSpacing.md) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title)
                            .foregroundColor(Color(red: 0.99, green: 0.27, blue: 0.29))
                        Text(err)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        Button(action: { loadEmployees() }) {
                            Label("retry".localized(for: appLanguage), systemImage: "arrow.clockwise")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: 200)
                                .padding(.vertical, 14)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    Color(red: 0.18, green: 0.44, blue: 0.97),
                                                    Color(red: 0.36, green: 0.64, blue: 1.0)
                                                ],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                )
                        }
                    }
                    .frame(maxHeight: .infinity)
                } else if employees.isEmpty {
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
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.05)) {
                headerAppeared = true
            }
            withAnimation(.spring(response: 0.7, dampingFraction: 0.65).delay(0.35)) {
                cardsAppeared = true
            }
        }
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
                        
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(APGradient.warning)
                    }
                    .padding(.top, 8)
                    
                    Text("no_staff_title".localized(for: appLanguage))
                        .font(.title3)
                        .fontWeight(.black)
                        .foregroundColor(.textPrimary)
                        .multilineTextAlignment(.center)
                    
                    Text("no_staff_sub".localized(for: appLanguage))
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
                    
                    Button(action: {
                        APHaptic.trigger()
                        activeMerchantId = "163350b0-056d-4d5e-b5d4-24e7aac5ab6d"
                        loadEmployees()
                    }) {
                        HStack(spacing: APSpacing.xs) {
                            Image(systemName: "sparkles")
                                .font(.footnote)
                            Text("connect_demo_store".localized(for: appLanguage))
                                .font(.caption)
                                .fontWeight(.bold)
                        }
                        .foregroundColor(.appAccent)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.appAccent.opacity(0.1))
                        .clipShape(Capsule())
                    }
                    .padding(.top, 4)
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
        guard !activeMerchantId.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let list = try await NetworkService.shared.fetchEmployees()
                await MainActor.run {
                    self.employees = list
                    self.isLoading = false
                }
            } catch {
                // Fallback to local mocks if server offline
                await MainActor.run {
                    self.employees = [
                        Employee(id: "11111111-1111-1111-1111-111111111111", firstName: "Somchai", lastName: "Suksabai", phone: "081-234-5678", nationalId: "1234567890123", employmentType: "monthly", payRate: 25000.0, username: "somchai", role: "Store Manager", faceRegisteredAt: nil),
                        Employee(id: "22222222-2222-2222-2222-222222222222", firstName: "Somsri", lastName: "Jaidee", phone: "089-876-5432", nationalId: "9876543210987", employmentType: "hourly", payRate: 75.0, username: "somsri", role: "Waitstaff", faceRegisteredAt: nil)
                    ]
                    self.isLoading = false
                }
            }
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
        // faceEmbedding is no longer stored on the client — use faceRegisteredAt to indicate enrollment
        guard employee.faceRegisteredAt != nil else {
            bioScannerMessage = "No face registered. Log in with PIN first and register your face in the Timecard tab."
            return
        }
        
        let context = LAContext()
        var error: NSError?
        
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            bioScannerMessage = "Biometrics not available on this device"
            return
        }
        
        isBioScanning = true
        bioScanProgress = 0.3
        bioScannerMessage = "Verifying identity..."
        
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                               localizedReason: "Verify your identity to clock in") { success, authError in
            DispatchQueue.main.async {
                if success {
                    self.bioScanProgress = 1.0
                    self.bioScanSuccess = true
                    self.bioScannerMessage = "Biometric Match Confirmed!"
                    APHaptic.trigger()
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.loggedInEmployee = employee
                        self.isBioScanning = false
                        self.bioScanSuccess = false
                        self.bioScanProgress = 0.0
                        self.selectedEmployee = nil
                    }
                } else {
                    self.isBioScanning = false
                    self.bioScanProgress = 0.0
                    self.bioScannerMessage = "Biometric verification failed"
                    APHaptic.trigger()
                }
            }
        }
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
                        
                        if showPinError {
                            Text("pin_error".localized(for: appLanguage))
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
                    
                    if showPinError {
                        Text("pin_error".localized(for: appLanguage))
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
    }
    
    private func keypadButton(text: String, size: CGFloat) -> some View {
        Button(action: {
            guard !isLocked else { return }
            APHaptic.trigger()
            showPinError = false
            if pinDigits.count < 4 {
                pinDigits.append(text)
                
                if pinDigits.count == 4 {
                    Task {
                        do {
                            // SECURITY: do NOT pass expectedPinHash — employee.pinCode is no longer
                            // fetched from the server. Verification always goes through the DB path.
                            let verified = try await NetworkService.shared.verifyPin(employeeId: employee.id, pinDigits: pinDigits)
                            await MainActor.run {
                                if verified {
                                    failedAttempts = 0
                                    onSuccess()
                                } else {
                                    failedAttempts += 1
                                    showPinError = true
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
                                failedAttempts += 1
                                showPinError = true
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
