// MerchantAuthView.swift
// AlphaPos — Merchant Sign-In & Onboarding Wizard

import SwiftUI
import SwiftData
import Combine
import CoreImage
import CoreImage.CIFilterBuiltins
import Network
import UIKit

private final class AuthConnectivityMonitor: ObservableObject {
    @Published private(set) var isConnected: Bool?

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.alphapos.auth-connectivity")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}

private struct PendingMerchantOnboarding: Codable {
    let shopName: String
    let firstName: String
    let lastName: String
    let shopPhone: String
    let currency: String
    let taxId: String
    let subscriptionTier: String
    let billingCycle: String
    let consentedAt: Date
    let idempotencyKey: UUID
}

struct MerchantAuthView: View {
    var onAuthenticated: (() -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var lm: LocalizationManager
    @StateObject private var connectivity = AuthConnectivityMonitor()
    @ObservedObject private var deepLinkCoordinator = AuthDeepLinkCoordinator.shared
    @AppStorage("is_logged_in") private var isLoggedIn = false
    @AppStorage("active_merchant_id") private var activeMerchantId = ""
    @AppStorage("logged_in_email") private var loggedInEmail = "owner@alphapos.com"
    @AppStorage("logged_in_name") private var loggedInName = "Somchai Lertwit"
    @State private var showingLanguagePicker = false

    // Auth Mode: "login" or "signup"
    @State private var authMode: String = "login"
    @State private var rememberStore = RememberStorePreferences.isEnabled

    // Form Inputs
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var firstName = ""
    @State private var lastName = ""

    // Shop Registration Inputs (Step 2)
    @State private var signupStep = 1 // Step 1: User Account, Step 2: Shop Info
    @State private var shopName = ""
    @State private var currency = "THB" // THB (฿), USD ($), EUR (€)
    @State private var taxId = ""
    @State private var shopPhone = ""

    // Pricing Package Inputs (Step 3)
    @State private var selectedPlanId: String = "offline_perpetual"
    @State private var isAnnualBilling = false
    @State private var acceptedTerms = false
    @State private var captchaToken: String?
    @State private var captchaResetToken = 0
    @State private var captchaStatus: TurnstileChallengeStatus = .loading
    @State private var mfaSession: AuthSession?
    /// Session kept while a returning user finishes shop/plan onboarding after login.
    @State private var postAuthSession: AuthSession?
    @State private var mfaEnrollment: TOTPEnrollment?
    @State private var mfaFactorId = ""
    @State private var mfaCode = ""
    @State private var showingMFA = false
    @State private var mfaSecretCopied = false
    /// Enroll flow: ask first (`false`), then show QR/setup (`true`). Verify flow ignores this.
    @State private var mfaEnrollAccepted = false

    // Feedback States
    @State private var errorMessage = ""
    @State private var isLoading = false
    @State private var authCardAppeared = false
    @State private var glassPulse = false
    @State private var logoFloat = false
    @State private var cardFloat = false
    @State private var buttonFloat = false

    // Password toggles & sheets
    @State private var showPassword = false
    @State private var showingForgotPasswordSheet = false
    @State private var showingRecoveryPasswordSheet = false
    @State private var recoveryAccessToken = ""
    @State private var recoveryNewPassword = ""
    @State private var recoveryConfirmPassword = ""
    @State private var recoverySuccessMessage = ""
    @State private var isUpdatingRecoveryPassword = false
    @State private var resetEmail = ""
    @State private var resetSuccessMessage = ""
    @State private var isSendingReset = false

    // Field focus highlight animations
    @FocusState private var focusedField: AuthField?

    enum AuthField {
        case email, password, confirmPassword, firstName, lastName
        case shopName, taxId, shopPhone
    }

    var body: some View {
        ZStack {
            // 1. Restaurant Kitchen image background
            KitchenBackgroundView()
                .ignoresSafeArea()

            // 2. Main Container
            GeometryReader { geometry in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        Spacer(minLength: 20)

                        // Brand Header + language (affects UI + confirmation email locale)
                        HStack(alignment: .center, spacing: 12) {
                            Image("AppLogoMark")
                                .resizable()
                                .scaledToFill()
                                .frame(width: 48, height: 48)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .shadow(color: Color(hex: "00A8FF").opacity(logoFloat ? 0.45 : 0.25), radius: logoFloat ? 10 : 6, x: 0, y: 3)

                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 0) {
                                    Text("Alpha")
                                        .font(.system(size: 26, weight: .bold, design: .default))
                                        .foregroundColor(.white)
                                    Text("Pos")
                                        .font(.system(size: 26, weight: .black, design: .default))
                                        .foregroundColor(Color(hex: "2D71F8"))
                                }
                                Text("auth_brand_sub".t)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(Color(hex: "A7F3D0").opacity(0.95))
                            }

                            Spacer(minLength: 8)

                            Button {
                                triggerHapticFeedback(.light)
                                showingLanguagePicker = true
                            } label: {
                                HStack(spacing: 6) {
                                    Text(lm.currentLanguage.flag)
                                        .font(.system(size: 14))
                                    Text(lm.currentLanguage.rawValue.uppercased())
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.white)
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.white.opacity(0.7))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.12))
                                .overlay(
                                    Capsule()
                                        .stroke(Color.white.opacity(0.28), lineWidth: 1)
                                )
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(L.Language.selectLanguage.t)
                        }
                        .frame(maxWidth: 500)
                        .padding(.horizontal, 22)
                        .offset(y: logoFloat ? -5 : 5)
                        .padding(.bottom, 24)
                        .scaleEffect(authCardAppeared ? 1 : 0.96)
                        .opacity(authCardAppeared ? 1 : 0)

                        // Frosted Glass / Glassmorphism modal container
                        VStack(spacing: 0) {
                            if connectivity.isConnected == nil {
                                checkingConnectionCard
                                    .transition(.opacity)
                            } else if connectivity.isConnected == false {
                                offlineCard
                                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
                            } else if authMode == "login" {
                                loginForm
                                    .transition(.asymmetric(
                                        insertion: .move(edge: .leading).combined(with: .opacity),
                                        removal: .move(edge: .trailing).combined(with: .opacity)
                                    ))
                            } else {
                                signupForm
                                    .transition(.asymmetric(
                                        insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)
                                ))
                            }
                        }
                        .padding(34)
                        .frame(maxWidth: 500)
                        .padding(.horizontal, 22)
                        .frostedAuthPanel(isActive: glassPulse)
                        .scaleEffect(authCardAppeared ? 1 : 0.94)
                        .opacity(authCardAppeared ? 1 : 0)
                        .offset(y: cardFloat ? -4 : 4)
                        .offset(y: authCardAppeared ? 0 : 18)
                        .animation(.spring(response: 0.5, dampingFraction: 0.82), value: authMode)
                        .animation(.spring(response: 0.5, dampingFraction: 0.82), value: signupStep)
                        .animation(.spring(response: 0.5, dampingFraction: 0.86), value: connectivity.isConnected)

                        Spacer(minLength: 20)

                        // Footer Credits
                        VStack(spacing: 4) {
                            Text(L.Auth.sysOnlineSsl.t)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(Color.white.opacity(0.55))
                            Text(L.Auth.cloudEngineVer.t)
                                .font(.system(size: 9))
                                .foregroundColor(Color.white.opacity(0.4))
                        }
                        .padding(.bottom, 20)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: geometry.size.height)
                }
            }
        }
        .onAppear {
            rememberStore = RememberStorePreferences.isEnabled
            if email.isEmpty, RememberStorePreferences.isEnabled {
                let saved = RememberStorePreferences.rememberedEmail
                if !saved.isEmpty { email = saved }
            }
            withAnimation(.spring(response: 0.72, dampingFraction: 0.82).delay(0.08)) {
                authCardAppeared = true
            }
            withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) {
                glassPulse = true
            }
            withAnimation(.easeInOut(duration: 4.5).repeatForever(autoreverses: true)) {
                logoFloat = true
            }
            withAnimation(.easeInOut(duration: 5.5).repeatForever(autoreverses: true)) {
                cardFloat = true
            }
            withAnimation(.easeInOut(duration: 6.2).repeatForever(autoreverses: true)) {
                buttonFloat = true
            }
            if let action = deepLinkCoordinator.pendingAction {
                handleDeepLinkAction(action)
            }
        }
        .onChange(of: deepLinkCoordinator.pendingActionToken) { _, token in
            guard token != nil, let action = deepLinkCoordinator.pendingAction else { return }
            handleDeepLinkAction(action)
        }
        .onChange(of: scenePhase) { previous, phase in
            // Background / long idle often expires Turnstile silently — reload on resume.
            guard phase == .active, previous != .active else { return }
            guard !AppConfig.shared.turnstileSiteKey.isEmpty else { return }
            invalidateCaptcha()
        }
        .sheet(isPresented: $showingForgotPasswordSheet) {
            forgotPasswordSheet
        }
        .sheet(isPresented: $showingRecoveryPasswordSheet) {
            recoveryPasswordSheet
        }
        .sheet(isPresented: $showingMFA) { mfaSheet }
        .sheet(isPresented: $showingLanguagePicker) {
            LanguagePickerSheet(lm: lm)
        }
    }

    // MARK: - Connection State
    private var checkingConnectionCard: some View {
        VStack(spacing: 18) {
            ProgressView()
                .controlSize(.large)
                .tint(.white)

            Text("auth_checking_connection".t)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity, minHeight: 420)
        .accessibilityElement(children: .combine)
    }

    private var offlineCard: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 12)

            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.10))
                    .frame(width: 112, height: 112)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )

                Image(systemName: "wifi.slash")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.white, Color.white.opacity(0.7))
            }
            .scaleEffect(glassPulse ? 1.04 : 0.96)
            .shadow(color: Color(hex: "2D71F8").opacity(0.3), radius: 16, x: 0, y: 6)
            .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("auth_no_internet_title".t)
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                Text("auth_no_internet_message".t)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            Button(action: openAppSettings) {
                Label("auth_open_settings".t, systemImage: "gearshape.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: "2D71F8"), Color(hex: "1A5FE8")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
                    .shadow(color: Color(hex: "1A5FE8").opacity(0.35), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(ScaleButtonStyle(floatAnimation: buttonFloat))

            Text("auth_connection_auto_retry".t)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.55))
                .multilineTextAlignment(.center)

            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity, minHeight: 420)
    }

    private func openAppSettings() {
        triggerHapticFeedback(.light)
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(settingsURL)
    }

    // MARK: - Login Form
    private var loginForm: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L.Auth.signInTitle.t)
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                Text(L.Auth.signInDesc.t)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(.bottom, 8)

            if !errorMessage.isEmpty {
                errorMessageBanner
            }

            // Email Input
            VStack(alignment: .leading, spacing: 6) {
                Text(L.Auth.emailLbl.t)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.85))

                HStack {
                    Image(systemName: "envelope")
                        .premiumAuthIconStyle(isFocused: focusedField == .email)
                    TextField("", text: $email, prompt: Text("owner@myrestaurant.com").foregroundColor(.white.opacity(0.45)))
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .keyboardType(.emailAddress)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .email)
                }
                .premiumAuthInputStyle(isFocused: focusedField == .email)
            }

            // Password Input
            VStack(alignment: .leading, spacing: 6) {
                Text(L.Auth.passwordLbl.t)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.85))

                HStack {
                    Image(systemName: "lock")
                        .premiumAuthIconStyle(isFocused: focusedField == .password)

                    if showPassword {
                        TextField("", text: $password, prompt: Text("Password").foregroundColor(.white.opacity(0.45)))
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                            .keyboardType(.asciiCapable)
                            .textContentType(.password)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .password)
                    } else {
                        SecureField("", text: $password, prompt: Text("••••••••••••").foregroundColor(.white.opacity(0.45)))
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                            .keyboardType(.asciiCapable)
                            .textContentType(.password)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .password)
                    }

                    Button(action: {
                        triggerHapticFeedback(.light)
                        showPassword.toggle()
                    }) {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                            .foregroundColor(Color.white.opacity(0.6))
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                }
                .premiumAuthInputStyle(isFocused: focusedField == .password)
                .onChange(of: password) { _, newValue in
                    let asciiOnly = String(newValue.unicodeScalars.filter(\.isASCII))
                    if password != asciiOnly {
                        password = asciiOnly
                    }
                }
            }

            // Forgot Password Link
            HStack {
                Spacer()
                Button(action: {
                    triggerHapticFeedback(.light)
                    showingForgotPasswordSheet = true
                }) {
                    Text(L.Auth.forgotPassword.t)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(hex: "2D71F8"))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, -10)

            // Remember this store (email + keep returning to Staff Lock via device JWT)
            Button {
                triggerHapticFeedback(.light)
                rememberStore.toggle()
                RememberStorePreferences.isEnabled = rememberStore
                if !rememberStore {
                    RememberStorePreferences.rememberedEmail = ""
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: rememberStore ? "checkmark.square.fill" : "square")
                        .foregroundColor(Color(hex: "2D71F8"))
                        .font(.system(size: 14, weight: .semibold))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L.Auth.rememberStore.t)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white.opacity(0.8))
                        Text("auth_remember_store_hint".t)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.white.opacity(0.45))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 2)

            if !AppConfig.shared.turnstileSiteKey.isEmpty {
                AuthCaptchaBlock(
                    siteKey: AppConfig.shared.turnstileSiteKey,
                    captchaToken: $captchaToken,
                    captchaResetToken: $captchaResetToken,
                    captchaStatus: $captchaStatus,
                    appearance: .onDarkGlass,
                    instanceId: "login"
                )
            } else if AppConfig.shared.isProduction {
                // Release/TestFlight without TURNSTILE_SITE_KEY hides the checkbox entirely.
                Text("กล่องยืนยันตัวตนยังไม่ได้ตั้งค่า (TURNSTILE_SITE_KEY)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.red.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            let captchaRequired = !AppConfig.shared.turnstileSiteKey.isEmpty
            let captchaBlocking = captchaRequired && (captchaToken == nil || captchaStatus == .failed || captchaStatus == .expired || captchaStatus == .loading)
            let loginBlocked = email.isEmpty || password.isEmpty || captchaBlocking || isLoading

            // Action Button (Primary Orange Gradient CTA)
            Button(action: handleLogin) {
                HStack {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .padding(.trailing, 8)
                    }
                    Text(L.Auth.signInBtn.t)
                        .font(.system(size: 15, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    Group {
                        if loginBlocked {
                            Capsule()
                                .fill(Color(hex: "2D71F8").opacity(0.35))
                        } else {
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [Color(hex: "2D71F8"), Color(hex: "1A5FE8")],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        }
                    }
                )
                .foregroundColor(loginBlocked ? .white.opacity(0.6) : .white)
                .shadow(color: Color(hex: "1A5FE8").opacity(loginBlocked ? 0.0 : 0.35), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(ScaleButtonStyle(floatAnimation: buttonFloat))
            .disabled(loginBlocked)
            .padding(.top, 6)

            // Mode switcher styled as a premium secondary button
            VStack(spacing: 12) {
                HStack {
                    Rectangle()
                        .fill(Color.white.opacity(0.2))
                        .frame(height: 1)
                    Text("หรือ")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color.white.opacity(0.6))
                        .padding(.horizontal, 8)
                    Rectangle()
                        .fill(Color.white.opacity(0.2))
                        .frame(height: 1)
                }
                .padding(.vertical, 4)

                Button(action: {
                    errorMessage = ""
                    triggerHapticFeedback(.light)
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) { authMode = "signup" }
                }) {
                    Text(L.Auth.registerBtn.t)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.08))
                        )
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.4), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                }
                .buttonStyle(ScaleButtonStyle(floatAnimation: buttonFloat))
            }
        }
    }

    // MARK: - Sign Up Form (Wizard Steps)
    private var signupForm: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Wizard step indicator
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L.Auth.createTitle.t)
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    Text(signupStep == 1
                         ? "onboarding_step_account".t
                         : (signupStep == 2 ? "onboarding_step_shop".t : "onboarding_step_plan".t))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(hex: "2D71F8"))
                }
                Spacer()

                // Dots representing steps
                HStack(spacing: 6) {
                    Circle()
                        .fill(signupStep >= 1 ? Color(hex: "2D71F8") : Color.white.opacity(0.3))
                        .frame(width: 8, height: 8)
                    Circle()
                        .fill(signupStep >= 2 ? Color(hex: "2D71F8") : Color.white.opacity(0.3))
                        .frame(width: 8, height: 8)
                    Circle()
                        .fill(signupStep >= 3 ? Color(hex: "2D71F8") : Color.white.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.bottom, 8)

            if !errorMessage.isEmpty {
                errorMessageBanner
            }

            if signupStep == 1 {
                accountDetailsStep
            } else if signupStep == 2 {
                shopDetailsStep
            } else {
                pricingSelectionStep
            }
        }
    }

    // Account details fields
    @ViewBuilder
    private var accountDetailsStep: some View {
        VStack(spacing: 16) {
            // First Name & Last Name in row
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L.Auth.firstName.t)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.85))
                    HStack {
                        Image(systemName: "person")
                            .premiumAuthIconStyle(isFocused: focusedField == .firstName)
                        TextField("", text: $firstName, prompt: Text("Somchai").foregroundColor(.white.opacity(0.45)))
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                            .focused($focusedField, equals: .firstName)
                    }
                    .premiumAuthInputStyle(isFocused: focusedField == .firstName)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(L.Auth.lastName.t)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.85))
                    HStack {
                        Image(systemName: "person")
                            .premiumAuthIconStyle(isFocused: focusedField == .lastName)
                        TextField("", text: $lastName, prompt: Text("Lertwit").foregroundColor(.white.opacity(0.45)))
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                            .focused($focusedField, equals: .lastName)
                    }
                    .premiumAuthInputStyle(isFocused: focusedField == .lastName)
                }
            }

            // Email Input
            VStack(alignment: .leading, spacing: 6) {
                Text(L.Auth.emailLbl.t)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.85))
                HStack {
                    Image(systemName: "envelope")
                        .premiumAuthIconStyle(isFocused: focusedField == .email)
                    TextField("", text: $email, prompt: Text("email@example.com").foregroundColor(.white.opacity(0.45)))
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .focused($focusedField, equals: .email)
                }
                .premiumAuthInputStyle(isFocused: focusedField == .email)
            }

            // Password Input
            VStack(alignment: .leading, spacing: 6) {
                Text(L.Auth.passwordLbl.t)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.85))
                HStack {
                    Image(systemName: "lock")
                        .premiumAuthIconStyle(isFocused: focusedField == .password)
                    SecureField("", text: $password, prompt: Text("อย่างน้อย 8 ตัวอักษร").foregroundColor(.white.opacity(0.45)))
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .textContentType(.newPassword)
                        .focused($focusedField, equals: .password)
                }
                .premiumAuthInputStyle(isFocused: focusedField == .password)
            }

            // Password Confirmation Input
            VStack(alignment: .leading, spacing: 6) {
                Text(L.Auth.confirmPassword.t)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.85))
                HStack {
                    Image(systemName: "lock.shield")
                        .premiumAuthIconStyle(isFocused: focusedField == .confirmPassword)
                    SecureField("", text: $confirmPassword, prompt: Text("Re-enter password").foregroundColor(.white.opacity(0.45)))
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .focused($focusedField, equals: .confirmPassword)
                }
                .premiumAuthInputStyle(isFocused: focusedField == .confirmPassword)
            }

            if !AppConfig.shared.turnstileSiteKey.isEmpty {
                AuthCaptchaBlock(
                    siteKey: AppConfig.shared.turnstileSiteKey,
                    captchaToken: $captchaToken,
                    captchaResetToken: $captchaResetToken,
                    captchaStatus: $captchaStatus,
                    appearance: .onDarkGlass,
                    instanceId: "signup-account"
                )
            }

            let signupCaptchaBlocking = !AppConfig.shared.turnstileSiteKey.isEmpty
                && (captchaToken == nil || captchaStatus == .failed || captchaStatus == .expired || captchaStatus == .loading)
            let signupAccountBlocked = firstName.isEmpty || lastName.isEmpty || email.isEmpty || password.isEmpty || isLoading || signupCaptchaBlocking

            // CTA: create account → verify email (shop/plan come after verified login)
            Button(action: registerAccountAndAwaitEmail) {
                if isLoading {
                    ProgressView().tint(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                } else {
                    Text("onboarding_create_account_btn".t)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(signupAccountBlocked ? .white.opacity(0.6) : .white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
            }
            .background(
                Group {
                    if signupAccountBlocked {
                        Capsule()
                            .fill(Color(hex: "2D71F8").opacity(0.35))
                    } else {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: "2D71F8"), Color(hex: "1A5FE8")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    }
                }
            )
            .shadow(color: Color(hex: "1A5FE8").opacity(signupAccountBlocked ? 0.0 : 0.35), radius: 8, x: 0, y: 4)
            .buttonStyle(ScaleButtonStyle(floatAnimation: buttonFloat))
            .disabled(signupAccountBlocked)
            .padding(.top, 6)

            // Mode switcher styled as a pill-shaped secondary button
            Button(action: {
                errorMessage = ""
                triggerHapticFeedback(.light)
                withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) { authMode = "login" }
            }) {
                HStack(spacing: 4) {
                    Text(L.Auth.alreadyHaveStore.t)
                        .font(.system(size: 12))
                        .foregroundColor(Color.white.opacity(0.6))
                    Text(L.Auth.signInBtn.t)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(hex: "2D71F8"))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                )
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.4), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
            }
            .buttonStyle(ScaleButtonStyle(floatAnimation: buttonFloat))
        }
    }

    // Store configuration details
    @ViewBuilder
    private var shopDetailsStep: some View {
        VStack(spacing: 16) {
            // Store Name
            VStack(alignment: .leading, spacing: 6) {
                Text(L.Auth.storeName.t)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.85))
                HStack {
                    Image(systemName: "storefront")
                        .premiumAuthIconStyle(isFocused: focusedField == .shopName)
                    TextField("", text: $shopName, prompt: Text("Cafe Amazon").foregroundColor(.white.opacity(0.45)))
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .focused($focusedField, equals: .shopName)
                }
                .premiumAuthInputStyle(isFocused: focusedField == .shopName)
            }

            // Currency only — business type removed from signup (not persisted).
            VStack(alignment: .leading, spacing: 6) {
                Text(L.Auth.currency.t)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.85))

                Picker("Currency", selection: $currency) {
                    Text("THB (฿)").tag("THB")
                    Text("USD ($)").tag("USD")
                    Text("EUR (€)").tag("EUR")
                }
                .pickerStyle(.menu)
                .tint(.white)
                .accentColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.12))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.35), lineWidth: 1)
                )
            }

            // Tax ID — optional; complete later from checklist / Organization
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(L.Auth.taxId.t)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.85))
                    Text("onboarding_optional_badge".t)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.5))
                }
                HStack {
                    Image(systemName: "doc.text")
                        .premiumAuthIconStyle(isFocused: focusedField == .taxId)
                    TextField("", text: $taxId, prompt: Text("13 digits ID").foregroundColor(.white.opacity(0.45)))
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .keyboardType(.numberPad)
                        .focused($focusedField, equals: .taxId)
                        .onChange(of: taxId) { _, _ in persistShopDraftLocally() }
                }
                .premiumAuthInputStyle(isFocused: focusedField == .taxId)
            }

            // Contact Phone — optional
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(L.Auth.contactPhone.t)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.85))
                    Text("onboarding_optional_badge".t)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.5))
                }
                HStack {
                    Image(systemName: "phone")
                        .premiumAuthIconStyle(isFocused: focusedField == .shopPhone)
                    TextField("", text: $shopPhone, prompt: Text("02-XXX-XXXX").foregroundColor(.white.opacity(0.45)))
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .keyboardType(.phonePad)
                        .focused($focusedField, equals: .shopPhone)
                        .onChange(of: shopPhone) { _, _ in persistShopDraftLocally() }
                }
                .premiumAuthInputStyle(isFocused: focusedField == .shopPhone)
            }

            // Action Buttons
            HStack(spacing: 12) {
                Button(action: {
                    triggerHapticFeedback(.light)
                    withAnimation { signupStep = 1 }
                }) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 14, weight: .bold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.08))
                        )
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.4), lineWidth: 1)
                        )
                        .foregroundColor(.white)
                        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                }
                .buttonStyle(ScaleButtonStyle(floatAnimation: buttonFloat))

                Button(action: validateAndGoToStep3) {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .padding(.trailing, 8)
                        }
                        Text("เลือกแพ็กเกจ")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        Group {
                            if shopName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Capsule()
                                    .fill(Color(hex: "2D71F8").opacity(0.35))
                            } else {
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color(hex: "2D71F8"), Color(hex: "1A5FE8")],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                            }
                        }
                    )
                    .foregroundColor(shopName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .white.opacity(0.6) : .white)
                    .shadow(color: Color(hex: "1A5FE8").opacity(shopName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.0 : 0.35), radius: 8, x: 0, y: 4)
                }
                .buttonStyle(ScaleButtonStyle(floatAnimation: buttonFloat))
                .disabled(shopName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
            }
            .padding(.top, 6)
        }
        .onAppear {
            restoreShopDraftIfNeeded()
        }
        .onChange(of: shopName) { _, _ in persistShopDraftLocally() }
        .onChange(of: currency) { _, _ in persistShopDraftLocally() }
    }

    /// Annual price = monthly × 12 × 0.8 (20% yearly discount).
    private func annualPrice(fromMonthly monthly: Int) -> Int {
        Int((Double(monthly) * 12.0 * 0.8).rounded())
    }

    private func formatPlanPrice(_ amount: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.maximumFractionDigits = 0
        let formatted = formatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
        return "฿\(formatted)"
    }

    @ViewBuilder
    private var pricingSelectionStep: some View {
        VStack(spacing: 16) {
            // Trial callout — makes the 14-day policy visible before plan cards.
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "gift.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(hex: "A7F3D0"))
                VStack(alignment: .leading, spacing: 2) {
                    Text("plan_trial_banner_title".t)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                    Text("plan_trial_banner_body".t)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(Color(hex: "2D71F8").opacity(0.18))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(hex: "2D71F8").opacity(0.35), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            // Billing Cycle Toggle (Monthly vs Annual)
            HStack {
                Text(L.Auth.billingMonthly.t)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isAnnualBilling ? .white.opacity(0.6) : .white)

                Toggle("", isOn: $isAnnualBilling)
                    .toggleStyle(SwitchToggleStyle(tint: Color(hex: "2D71F8")))
                    .labelsHidden()
                    .padding(.horizontal, 4)

                Text(L.Auth.billingAnnualSave20.t)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isAnnualBilling ? .white : .white.opacity(0.6))
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)

            // Plan Cards
            VStack(spacing: 10) {
                planCard(
                    id: "offline_perpetual",
                    title: "ออฟไลน์ ซื้อขาด",
                    subtitle: "ใช้งาน 1 เครื่องตลอดชีพ ไม่มีรายเดือน",
                    price: formatPlanPrice(9900),
                    priceLabel: L.Auth.priceOneTime.t,
                    features: ["ใช้งานถาวรระดับเครื่องแม่", "ไม่ต้องใช้อินเทอร์เน็ต", "สำรองข้อมูลแบบ Manual", "จำกัดเฉพาะฟีเจอร์ปัจจุบัน"],
                    color: Color(hex: "6366F1"),
                    modeBadge: .offline,
                    showsTrial: false
                )

                planCard(
                    id: "offline_subscription",
                    title: isAnnualBilling ? "ออฟไลน์ รายปี" : "ออฟไลน์ รายเดือน",
                    subtitle: "ใช้งาน 1 เครื่อง พร้อมอัปเดตฟรีตลอดสัญญา",
                    price: isAnnualBilling ? formatPlanPrice(annualPrice(fromMonthly: 290)) : formatPlanPrice(290),
                    priceLabel: isAnnualBilling ? L.Auth.pricePerYear.t : L.Auth.pricePerMonth.t,
                    features: [
                        "plan_feature_trial_14".t,
                        "ใช้งานออฟไลน์ 1 เครื่องแม่",
                        "อัปเดตฟีเจอร์ใหม่ฟรีในสัญญา",
                        "บริการความช่วยเหลือ 24/7",
                    ],
                    color: .appTeal,
                    modeBadge: .offline,
                    showsTrial: true
                )

                planCard(
                    id: "online_subscription",
                    title: isAnnualBilling ? "ออนไลน์ รายปี" : "ออนไลน์ รายเดือน",
                    subtitle: "ซิงค์หลายเครื่อง คลาวด์แดชบอร์ด ออเดอร์ QR",
                    price: isAnnualBilling ? formatPlanPrice(annualPrice(fromMonthly: 1190)) : formatPlanPrice(1190),
                    priceLabel: isAnnualBilling ? L.Auth.pricePerYear.t : L.Auth.pricePerMonth.t,
                    features: [
                        "plan_feature_trial_14".t,
                        "ซิงค์ข้อมูลระหว่างหลาย iPad/iPhone",
                        "รับออเดอร์ QR Code จากลูกค้า",
                        "สำรองข้อมูลอัตโนมัติบน Cloud",
                    ],
                    color: Color(hex: "2D71F8"),
                    modeBadge: .online,
                    showsTrial: true
                )
            }

            // Priority order (international): Terms first → Captcha → CTA
            Button {
                triggerHapticFeedback(.light)
                acceptedTerms.toggle()
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: acceptedTerms ? "checkmark.square.fill" : "square")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(acceptedTerms ? Color(hex: "34D399") : .white.opacity(0.55))
                    Text(LocalizationManager.shared.t(L.Auth.acceptTermsPrivacy, "2026-07-17"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.88))
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(acceptedTerms ? Color(hex: "34D399").opacity(0.45) : Color.white.opacity(0.18), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(acceptedTerms ? [.isSelected] : [])

            if !AppConfig.shared.turnstileSiteKey.isEmpty {
                AuthCaptchaBlock(
                    siteKey: AppConfig.shared.turnstileSiteKey,
                    captchaToken: $captchaToken,
                    captchaResetToken: $captchaResetToken,
                    captchaStatus: $captchaStatus,
                    appearance: .onDarkGlass,
                    instanceId: "signup-plan"
                )
            } else if AppConfig.shared.isProduction {
                Text("กล่องยืนยันตัวตนยังไม่ได้ตั้งค่า (TURNSTILE_SITE_KEY)")
                    .font(.caption).foregroundColor(.red)
            } else {
                // Dev fallback: native checkbox captcha stand-in
                Button {
                    captchaToken = captchaToken == nil ? "dev-bypass" : nil
                    captchaStatus = captchaToken == nil ? .ready : .verified
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: captchaToken == nil ? "square" : "checkmark.square.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(captchaToken == nil ? .white.opacity(0.55) : Color(hex: "2D71F8"))
                        Text("plan_captcha_human_checkbox".t)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            let planCaptchaBlocking = !AppConfig.shared.turnstileSiteKey.isEmpty
                && (captchaToken == nil || captchaStatus == .failed || captchaStatus == .expired || captchaStatus == .loading)

            Button(action: handleSignUp) {
                HStack {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .padding(.trailing, 8)
                    }
                    Text(L.Auth.startPlanBtn.t)
                        .font(.system(size: 14, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    Capsule()
                        .fill(APGradient.positive)
                )
                .foregroundColor(.white)
                .shadow(color: Color.appTeal.opacity(0.3), radius: 8, x: 0, y: 3)
            }
            .disabled(
                isLoading
                || !acceptedTerms
                || planCaptchaBlocking
                || (AppConfig.shared.turnstileSiteKey.isEmpty && !AppConfig.shared.isProduction && captchaToken == nil)
            )
            .padding(.top, 4)
        }
    }

    private enum PlanModeBadge {
        case offline
        case online

        var titleKey: String {
            switch self {
            case .offline: return "plan_badge_offline"
            case .online: return "plan_badge_online"
            }
        }

        var color: Color {
            switch self {
            case .offline: return Color(hex: "6366F1")
            case .online: return Color(hex: "2D71F8")
            }
        }

        var icon: String {
            switch self {
            case .offline: return "iphone"
            case .online: return "cloud.fill"
            }
        }
    }

    private func planCard(
        id: String,
        title: String,
        subtitle: String,
        price: String,
        priceLabel: String,
        features: [String],
        color: Color,
        modeBadge: PlanModeBadge,
        showsTrial: Bool
    ) -> some View {
        let isSelected = selectedPlanId == id
        return Button(action: {
            triggerHapticFeedback(.light)
            selectedPlanId = id
        }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    planBadge(title: modeBadge.titleKey.t, icon: modeBadge.icon, color: modeBadge.color)
                    if showsTrial {
                        planBadge(title: "plan_badge_trial_14".t, icon: "gift.fill", color: Color(hex: "34D399"))
                    }
                    Spacer(minLength: 0)
                }

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                        Text(subtitle)
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(price)
                            .font(.system(size: 16, weight: .black))
                            .foregroundColor(color)
                        Text(priceLabel)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }

                Divider().background(Color.white.opacity(0.15))

                HStack(spacing: 12) {
                    ForEach(features.prefix(2), id: \.self) { feat in
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 8))
                                .foregroundColor(color)
                            Text(feat)
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.85))
                                .lineLimit(2)
                        }
                    }
                }
            }
            .padding(12)
            .background(Color.white.opacity(isSelected ? 0.12 : 0.04))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? color : Color.white.opacity(0.15), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func planBadge(title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .bold))
            Text(title)
                .font(.system(size: 9, weight: .bold))
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.16))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(color.opacity(0.35), lineWidth: 1)
        )
    }

    private var errorMessageBanner: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(Color(hex: "FF453A"))
            Text(errorMessage)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
            Spacer()
        }
        .padding(12)
        .background(Color(hex: "FF453A").opacity(0.18))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(hex: "FF453A").opacity(0.4), lineWidth: 1)
        )
    }

    // MARK: - Logic Handlers
    private func handleLogin() {
        errorMessage = ""
        guard !isLoading else { return }
        isLoading = true
        triggerHapticFeedback(.medium)

        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanPassword = password

        Task {
            do {
                let session = try await AuthService.shared.signIn(email: cleanEmail, password: cleanPassword, captchaToken: captchaToken)
                let preparation = try await AuthService.shared.prepareOwnerTOTP(
                    accessToken: session.accessToken,
                    preferredFactorId: session.user.totpFactorId
                )
                await MainActor.run {
                    mfaSession = session
                    mfaCode = ""
                    mfaSecretCopied = false
                    mfaEnrollAccepted = false
                    switch preparation {
                    case .verifyExisting(let factorId):
                        mfaFactorId = factorId
                        mfaEnrollment = nil
                    case .enrollNew(let enrollment):
                        mfaFactorId = enrollment.factorId
                        mfaEnrollment = enrollment
                    }
                    isLoading = false
                    showingMFA = true
                }
            } catch AuthServiceError.emailConfirmationRequired {
                await MainActor.run {
                    isLoading = false
                    invalidateCaptcha()
                    triggerNotificationFeedback(.warning)
                    errorMessage = AuthServiceError.emailConfirmationRequired.localizedDescription
                }
            } catch AuthServiceError.captchaRequired {
                await MainActor.run {
                    isLoading = false
                    invalidateCaptcha()
                    triggerNotificationFeedback(.error)
                    errorMessage = AuthServiceError.captchaRequired.localizedDescription
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    // Turnstile tokens are single-use; always refresh after any failed attempt.
                    invalidateCaptcha()
                    triggerNotificationFeedback(.error)
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func completeLogin(_ session: AuthSession) async {
        do {
                MerchantAuthManager.shared.saveUserAccessToken(session.accessToken)
                let pending = loadPendingOnboarding()

                // Returning auth user without a store yet → finish onboarding instead of failing.
                if session.user.merchantId == nil && pending == nil {
                    let remoteDraft = try? await AuthService.shared.fetchOnboardingDraft(accessToken: session.accessToken)
                    await MainActor.run {
                        postAuthSession = session
                        firstName = (session.user.userMetadata["first_name"] as? String) ?? firstName
                        lastName = (session.user.userMetadata["last_name"] as? String) ?? lastName
                        email = session.user.email.isEmpty ? email : session.user.email
                        password = ""
                        confirmPassword = ""
                        if let remoteDraft {
                            applyOnboardingDraft(remoteDraft)
                        } else {
                            restoreShopDraftIfNeeded()
                        }
                        authMode = "signup"
                        signupStep = 2
                        showingMFA = false
                        isLoading = false
                        errorMessage = "onboarding_complete_shop_message".t
                        triggerNotificationFeedback(.warning)
                    }
                    return
                }

                let activation = try await activateMerchant(session: session, pending: pending)
                guard let mId = UUID(uuidString: activation.merchantId) else { throw AuthServiceError.invalidResponse }
                let merchantKey = mId.uuidString.lowercased()
                // Server may mint a fresh device id when the local UUID was already
                // bound to another merchant (shared iPad) — keep client in sync.
                if let activatedDeviceId = UUID(uuidString: activation.deviceId) {
                    UserDefaults.standard.set(
                        activatedDeviceId.uuidString.lowercased(),
                        forKey: "alphapos_auth_device_uuid"
                    )
                }
                try await MerchantAuthManager.shared.authenticate(
                    merchantId: merchantKey,
                    deviceId: activation.deviceId,
                    deviceSecret: activation.deviceCredential,
                    verifiedUserMerchantId: session.user.merchantId
                )
                guard TenantWorkspaceGuard.isAuthenticatedWorkspaceReady else {
                    throw AuthServiceError.serverError(
                        "ยืนยันตัวตนสำเร็จ แต่ไม่สามารถผูกพื้นที่ข้อมูลของร้านได้ กรุณาลองใหม่"
                    )
                }
                // A previous offline plan may leave this runtime flag enabled.
                // Authentication has just proved the backend is reachable, so allow
                // the merchant settings request to determine the current plan.
                NetworkManager.shared.simulateOffline = false
                NetworkManager.shared.invalidateConnectivityCache()
                let merchantSettings = try? await NetworkManager.shared.fetchMerchantSettings(merchantId: mId)
                let subscriptionStatus = (
                    merchantSettings?["subscription_status"] as? String ?? activation.subscriptionStatus
                ).lowercased()
                // Phase 2: trial / pending_payment may enter; pay later via checklist.
                let allowedStatuses: Set<String> = ["active", "trial", "pending_payment"]
                guard allowedStatuses.contains(subscriptionStatus) else {
                    throw AuthServiceError.serverError("บัญชีหมดอายุหรือยังไม่พร้อมใช้งาน กรุณาติดต่อฝ่ายสนับสนุน")
                }

                await MainActor.run {
                    isLoading = false
                    postAuthSession = nil
                    resetMFAUIState()
                    triggerNotificationFeedback(.success)
                    activeMerchantId = merchantKey
                    loggedInEmail = session.user.email
                    loggedInName = session.user.fullName ?? "Store Owner"
                    RememberStorePreferences.applyAfterSuccessfulLogin(email: session.user.email)
                    let tier = (merchantSettings?["subscription_tier"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                        ?? activation.subscriptionTier
                    let status = (merchantSettings?["subscription_status"] as? String)
                        ?? activation.subscriptionStatus
                    let expiry = (merchantSettings?["subscription_expires_at"] as? String)
                        .flatMap { ISO8601DateFormatter().date(from: $0) }
                        ?? activation.subscriptionExpiresAt
                    applySubscriptionCache(tier: tier, status: status, expiry: expiry)
                    clearPendingOnboarding()
                    Task { await AuthService.shared.clearOnboardingDraft(accessToken: session.accessToken) }

                    MerchantOnboardingGate.markCompleted(
                        [.account, .emailVerified, .shopProfile, .planAndTerms, .tenantActivated, .mfaSoftPrompt, .dashboardReady],
                        for: merchantKey
                    )

                    // Seed only into a wiped/empty workspace — never on top of foreign residual data.
                    seedNewMerchantDataIfWorkspaceEmpty(merchantId: mId)

                    if let notice = TenantWorkspaceGuard.consumeWipeNoticeIfNeeded {
                        InAppNotificationManager.shared.post(
                            InAppNotification(
                                type: .staleShift,
                                title: L.Auth.tenantWipeNoticeTitle.t,
                                body: notice,
                                tableNumber: nil
                            )
                        )
                    }
                    withAnimation { isLoggedIn = true }
                    onAuthenticated?()
                }
            } catch {
                let message = error.localizedDescription
                if message.contains("ONBOARDING_REQUIRED") || message.contains("Missing required onboarding") {
                    await MainActor.run {
                        postAuthSession = session
                        authMode = "signup"
                        signupStep = 2
                        showingMFA = false
                        isLoading = false
                        invalidateCaptcha()
                        errorMessage = "กรุณากรอกข้อมูลร้านและเลือกแพ็กเกจเพื่อเปิดใช้งานบัญชี"
                        triggerNotificationFeedback(.warning)
                    }
                    return
                }
                await MainActor.run {
                    isLoading = false
                    invalidateCaptcha()
                    triggerNotificationFeedback(.error)
                    errorMessage = message
                }
            }
    }

    /// `true` = already enrolled (challenge). `false` = first-time invite.
    private var isMFAChallengeMode: Bool { mfaEnrollment == nil }

    private var mfaSheet: some View {
        NavigationStack {
            Group {
                if isMFAChallengeMode {
                    mfaChallengeContent
                } else if mfaEnrollAccepted {
                    mfaEnrollSetupContent
                } else {
                    mfaEnrollInquiryContent
                }
            }
            .navigationTitle(isMFAChallengeMode
                             ? "Two-Factor Authentication"
                             : (mfaEnrollAccepted ? "ตั้งค่า Authenticator" : "ความปลอดภัยบัญชี"))
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled()
        }
        .presentationDetents(isMFAChallengeMode || !mfaEnrollAccepted ? [.medium, .large] : [.large])
        .presentationDragIndicator(.visible)
        .onAppear {
            if mfaEnrollment != nil {
                mfaEnrollAccepted = false
            }
        }
    }

    private enum MFASecurityHeroStyle {
        case enrollInquiry
        case enrollSetup
        case verifyChallenge

        var primaryIcon: String {
            switch self {
            case .enrollInquiry: return "lock.shield.fill"
            case .enrollSetup: return "qrcode"
            case .verifyChallenge: return "lock.fill"
            }
        }

        var secondaryIcon: String? {
            switch self {
            case .enrollInquiry: return "key.fill"
            case .enrollSetup: return "iphone.gen3"
            case .verifyChallenge: return "shield.checkered"
            }
        }

        var caption: String {
            switch self {
            case .enrollInquiry: return "Two-Factor Protection"
            case .enrollSetup: return "Secure Enrollment"
            case .verifyChallenge: return "Identity Verification"
            }
        }
    }

    private func mfaSecurityHero(_ style: MFASecurityHeroStyle) -> some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "2D71F8").opacity(0.18), Color(hex: "00A8FF").opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 92, height: 92)

                Circle()
                    .stroke(Color(hex: "2D71F8").opacity(0.22), lineWidth: 2)
                    .frame(width: 102, height: 102)

                Image(systemName: style.primaryIcon)
                    .font(.system(size: 38, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color(hex: "2D71F8"))

                if let secondary = style.secondaryIcon {
                    Image(systemName: secondary)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(7)
                        .background(Color(hex: "2D71F8"))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                        .offset(x: 34, y: 34)
                }
            }
            .frame(height: 110)

            Text(style.caption)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color(hex: "2D71F8"))
                .textCase(.uppercase)
                .tracking(0.6)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: MFA — existing factor (standard challenge)

    private var mfaChallengeContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    mfaSecurityHero(.verifyChallenge)
                        .padding(.bottom, 4)

                    mfaStatusBanner(
                        icon: "lock.rotation",
                        tint: Color(hex: "2D71F8"),
                        title: "Verification required",
                        message: "กรุณากรอกรหัส 6 หลักจากแอป Authenticator เพื่อยืนยันตัวตนและเข้าสู่ระบบ"
                    )

                    if !errorMessage.isEmpty {
                        errorMessageBanner
                    }

                    mfaCodeField
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 8)
            }

            mfaFooterActions {
                Button {
                    verifyMFA()
                } label: {
                    Text(isLoading ? "กำลังยืนยัน..." : "ยืนยันและเข้าสู่ระบบ")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: "2D71F8"))
                .disabled(mfaCode.count != 6 || isLoading)
            }
        }
    }

    // MARK: MFA — not enrolled yet (inquiry, then setup)

    private var mfaEnrollInquiryContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    mfaSecurityHero(.enrollInquiry)
                        .padding(.bottom, 2)

                    mfaStatusBanner(
                        icon: "lock.shield.fill",
                        tint: Color(hex: "2D71F8"),
                        title: "ต้องการเปิดใช้รหัสยืนยันสองชั้นหรือไม่?",
                        message: "ช่วยป้องกันบัญชีร้านหากรหัสผ่านรั่วไหล ใช้แอปอย่าง Google Authenticator หรือ Microsoft Authenticator — ตั้งค่าภายหลังได้"
                    )

                    VStack(alignment: .leading, spacing: 12) {
                        mfaBenefitRow(icon: "lock.fill", text: "เพิ่มชั้นป้องกันเวลาเข้าสู่ระบบ")
                        mfaBenefitRow(icon: "key.viewfinder", text: "รหัส 6 หลักจากโทรศัพท์ของคุณเท่านั้น")
                        mfaBenefitRow(icon: "clock.badge.checkmark", text: "ข้ามได้ และตั้งค่าภายหลังในเมนูความปลอดภัย")
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 8)
            }

            mfaFooterActions {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        mfaEnrollAccepted = true
                        mfaCode = ""
                    }
                    triggerHapticFeedback(.medium)
                } label: {
                    Text("ตั้งค่าตอนนี้")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: "2D71F8"))
                .disabled(isLoading)

                Button {
                    skipMFASetup()
                } label: {
                    Text("ข้ามไปก่อน — เข้าสู่ระบบเลย")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .disabled(isLoading)
            }
        }
    }

    private var mfaEnrollSetupContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    mfaSecurityHero(.enrollSetup)
                        .padding(.bottom, 2)

                    mfaStatusBanner(
                        icon: "qrcode.viewfinder",
                        tint: Color(hex: "2D71F8"),
                        title: "สแกน QR ด้วยแอป Authenticator",
                        message: "จากนั้นกรอกรหัส 6 หลักด้านล่างเพื่อยืนยันการตั้งค่า"
                    )

                    if let enrollment = mfaEnrollment {
                        VStack(spacing: 12) {
                            if let qr = Self.makeTOTPQRCodeImage(from: enrollment.uri) {
                                Image(uiImage: qr)
                                    .interpolation(.none)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 156, height: 156)
                                    .padding(10)
                                    .background(Color.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .frame(maxWidth: .infinity)
                            }

                            Text("หรือคัดลอก secret ไปใส่ในแอปด้วยมือ")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            HStack(spacing: 10) {
                                Text(enrollment.secret)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.65)
                                Button {
                                    UIPasteboard.general.string = enrollment.secret
                                    mfaSecretCopied = true
                                    triggerNotificationFeedback(.success)
                                    Task {
                                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                                        await MainActor.run { mfaSecretCopied = false }
                                    }
                                } label: {
                                    Label(mfaSecretCopied ? "คัดลอกแล้ว" : "คัดลอก",
                                          systemImage: mfaSecretCopied ? "checkmark" : "doc.on.doc")
                                        .font(.caption.weight(.semibold))
                                }
                                .buttonStyle(.bordered)
                                .tint(Color(hex: "2D71F8"))
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }

                    mfaCodeField
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 8)
            }

            mfaFooterActions {
                Button {
                    verifyMFA()
                } label: {
                    Text(isLoading ? "กำลังยืนยัน..." : "ยืนยันและเข้าสู่ระบบ")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: "2D71F8"))
                .disabled(mfaCode.count != 6 || isLoading)

                Button {
                    skipMFASetup()
                } label: {
                    Text("ข้ามไปก่อน")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .disabled(isLoading)
            }
        }
    }

    private var mfaCodeField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(isMFAChallengeMode ? "Authentication code" : "รหัสยืนยัน")
                .font(.subheadline.weight(.semibold))
            TextField("000000", text: $mfaCode)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .font(.system(size: 26, weight: .semibold, design: .monospaced))
                .multilineTextAlignment(.center)
                .padding(.vertical, 14)
                .padding(.horizontal, 12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .onChange(of: mfaCode) { _, newValue in
                    let digits = newValue.filter(\.isNumber)
                    if digits != newValue || digits.count > 6 {
                        mfaCode = String(digits.prefix(6))
                    }
                }
        }
    }

    private func mfaStatusBanner(icon: String, tint: Color, title: String, message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.opacity(0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(tint.opacity(0.22), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func mfaBenefitRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(hex: "2D71F8").opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color(hex: "2D71F8"))
            }
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func mfaFooterActions<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 10) {
            content()
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private func resetMFAUIState() {
        showingMFA = false
        mfaCode = ""
        mfaEnrollment = nil
        mfaFactorId = ""
        mfaSecretCopied = false
        mfaEnrollAccepted = false
    }

    private func verifyMFA() {
        guard let session = mfaSession else { return }
        errorMessage = ""
        isLoading = true
        Task {
            do {
                let verified = try await AuthService.shared.verifyTOTP(
                    accessToken: session.accessToken, factorId: mfaFactorId, code: mfaCode
                )
                if mfaEnrollment != nil {
                    try await AuthService.shared.saveTOTPFactorId(accessToken: verified.accessToken, factorId: mfaFactorId)
                }
                await completeLogin(verified)
            } catch {
                await MainActor.run { isLoading = false; errorMessage = error.localizedDescription }
            }
        }
    }

    private func skipMFASetup() {
        guard let session = mfaSession, let enrollment = mfaEnrollment else { return }
        isLoading = true
        Task {
            try? await AuthService.shared.unenrollFactor(
                accessToken: session.accessToken,
                factorId: enrollment.factorId
            )
            await completeLogin(session)
        }
    }

    private static func makeTOTPQRCodeImage(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private func validateAndGoToStep2() {
        // Kept for shop-step callers that previously jumped here; account creation
        // now goes through registerAccountAndAwaitEmail (email verify before shop).
        errorMessage = ""
        if !email.contains("@") {
            triggerNotificationFeedback(.warning)
            errorMessage = "auth_error_invalid_email".t
            return
        }
        if password.count < 8 {
            triggerNotificationFeedback(.warning)
            errorMessage = "auth_error_short_password".t
            return
        }
        if password != confirmPassword {
            triggerNotificationFeedback(.warning)
            errorMessage = "auth_error_mismatched_passwords".t
            return
        }

        triggerHapticFeedback(.medium)
        withAnimation {
            signupStep = 2
        }
    }

    /// Best-practice step 1: create auth account, then require email verification
    /// before shop/plan onboarding.
    private func registerAccountAndAwaitEmail() {
        errorMessage = ""
        if !email.contains("@") {
            triggerNotificationFeedback(.warning)
            errorMessage = "auth_error_invalid_email".t
            return
        }
        if password.count < 8 {
            triggerNotificationFeedback(.warning)
            errorMessage = "auth_error_short_password".t
            return
        }
        if password != confirmPassword {
            triggerNotificationFeedback(.warning)
            errorMessage = "auth_error_mismatched_passwords".t
            return
        }
        if !AppConfig.shared.turnstileSiteKey.isEmpty && captchaToken == nil {
            errorMessage = AuthServiceError.captchaRequired.localizedDescription
            return
        }

        isLoading = true
        triggerHapticFeedback(.medium)

        Task {
            do {
                _ = try await AuthService.shared.signUp(
                    email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                    password: password,
                    captchaToken: captchaToken ?? "",
                    userData: [
                        "first_name": firstName,
                        "last_name": lastName,
                        // Drives localized confirmation email (GoTrue template .Data.preferred_language)
                        "preferred_language": LocalizationManager.shared.currentLanguage.rawValue,
                    ]
                )
                await MainActor.run {
                    isLoading = false
                    invalidateCaptcha()
                    triggerNotificationFeedback(.success)
                    authMode = "login"
                    signupStep = 1
                    errorMessage = "onboarding_verify_email_message".t
                }
            } catch AuthServiceError.emailConfirmationRequired {
                await MainActor.run {
                    isLoading = false
                    invalidateCaptcha()
                    authMode = "login"
                    errorMessage = "onboarding_verify_email_message".t
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    invalidateCaptcha()
                    triggerNotificationFeedback(.error)
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func validateAndGoToStep3() {
        errorMessage = ""
        guard !shopName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            triggerNotificationFeedback(.warning)
            errorMessage = "onboarding_shop_name_required".t
            return
        }

        persistShopDraftLocally()
        syncOnboardingDraftToServerIfPossible()

        triggerHapticFeedback(.medium)
        withAnimation {
            signupStep = 3
        }
    }

    private func handleSignUp() {
        errorMessage = ""
        guard acceptedTerms else {
            errorMessage = "กรุณายอมรับเงื่อนไขการใช้งานและนโยบายความเป็นส่วนตัว"
            return
        }
        isLoading = true
        triggerHapticFeedback(.medium)

        Task {
            // Reuse prior idempotency key on retry so server onboarding stays idempotent.
            let priorKey = loadPendingOnboarding()?.idempotencyKey
            let pending = PendingMerchantOnboarding(
                shopName: shopName.trimmingCharacters(in: .whitespacesAndNewlines),
                firstName: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
                lastName: lastName.trimmingCharacters(in: .whitespacesAndNewlines),
                shopPhone: shopPhone.trimmingCharacters(in: .whitespacesAndNewlines),
                currency: currency,
                taxId: taxId.trimmingCharacters(in: .whitespacesAndNewlines),
                subscriptionTier: selectedPlanId,
                billingCycle: selectedPlanId == "offline_perpetual" ? "perpetual" : (isAnnualBilling ? "annual" : "monthly"),
                consentedAt: Date(),
                idempotencyKey: priorKey ?? UUID()
            )
            savePendingOnboarding(pending)
            // Plan choice is source of truth for online/offline sync mode (Phase 1).
            await MainActor.run {
                OfflineSyncModeController.applyForSubscriptionTier(pending.subscriptionTier, modelContext: modelContext)
                UserDefaults.standard.set(true, forKey: "has_completed_first_launch")
            }
            if let token = (postAuthSession ?? mfaSession)?.accessToken {
                try? await AuthService.shared.upsertOnboardingDraft(
                    accessToken: token,
                    draft: OnboardingDraftPayload(
                        shopName: pending.shopName,
                        shopPhone: pending.shopPhone,
                        currency: pending.currency,
                        taxId: pending.taxId,
                        subscriptionTier: pending.subscriptionTier,
                        billingCycle: pending.billingCycle,
                        firstName: pending.firstName,
                        lastName: pending.lastName
                    )
                )
            }

            // Already signed in (e.g. after email verify) → activate store with shop/plan.
            if let existing = postAuthSession ?? mfaSession {
                await completeLogin(existing)
                return
            }

            // New flow creates the auth account at step 1; step 3 requires a session.
            await MainActor.run {
                isLoading = false
                invalidateCaptcha()
                authMode = "login"
                errorMessage = "onboarding_verify_email_message".t
                triggerNotificationFeedback(.warning)
            }
        }
    }

    private func activateMerchant(session: AuthSession, pending: PendingMerchantOnboarding?) async throws -> MerchantActivationResult {
        let deviceId = currentAuthDeviceId()
        return try await AuthService.shared.activateMerchant(
            accessToken: session.accessToken,
            shopName: pending?.shopName ?? "",
            firstName: pending?.firstName ?? "",
            lastName: pending?.lastName ?? "",
            shopPhone: pending?.shopPhone ?? "",
            currency: pending?.currency ?? "THB",
            taxId: pending?.taxId ?? "",
            subscriptionTier: pending?.subscriptionTier ?? "offline_perpetual",
            billingCycle: pending?.billingCycle ?? "perpetual",
            termsVersion: "2026-07-17",
            privacyVersion: "2026-07-17",
            consentedAt: pending?.consentedAt ?? Date(),
            idempotencyKey: pending?.idempotencyKey ?? UUID(),
            deviceId: deviceId,
            deviceName: "AlphaPos Register",
            deviceFingerprintHash: SecurityHelper.sha256(deviceId.uuidString.lowercased())
        )
    }

    private func currentAuthDeviceId() -> UUID {
        let key = "alphapos_auth_device_uuid"
        if let raw = UserDefaults.standard.string(forKey: key), let id = UUID(uuidString: raw) { return id }
        let id = UUID()
        UserDefaults.standard.set(id.uuidString.lowercased(), forKey: key)
        return id
    }

    private func savePendingOnboarding(_ pending: PendingMerchantOnboarding) {
        if let data = try? JSONEncoder().encode(pending) {
            UserDefaults.standard.set(data, forKey: "pending_merchant_onboarding")
        }
    }

    private func loadPendingOnboarding() -> PendingMerchantOnboarding? {
        guard let data = UserDefaults.standard.data(forKey: "pending_merchant_onboarding") else { return nil }
        return try? JSONDecoder().decode(PendingMerchantOnboarding.self, from: data)
    }

    private func clearPendingOnboarding() {
        UserDefaults.standard.removeObject(forKey: "pending_merchant_onboarding")
        UserDefaults.standard.removeObject(forKey: "pending_merchant_shop_draft")
    }

    /// Phase 5: autosave mid-wizard shop fields so users can leave and return.
    private func persistShopDraftLocally() {
        let draft = OnboardingDraftPayload(
            shopName: shopName.trimmingCharacters(in: .whitespacesAndNewlines),
            shopPhone: shopPhone.trimmingCharacters(in: .whitespacesAndNewlines),
            currency: currency,
            taxId: taxId.trimmingCharacters(in: .whitespacesAndNewlines),
            subscriptionTier: selectedPlanId,
            billingCycle: selectedPlanId == "offline_perpetual" ? "perpetual" : (isAnnualBilling ? "annual" : "monthly"),
            firstName: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
            lastName: lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        if let data = try? JSONEncoder().encode(draft) {
            UserDefaults.standard.set(data, forKey: "pending_merchant_shop_draft")
        }
    }

    private func restoreShopDraftIfNeeded() {
        if shopName.isEmpty, let pending = loadPendingOnboarding() {
            applyPendingToForm(pending)
            return
        }
        guard shopName.isEmpty,
              let data = UserDefaults.standard.data(forKey: "pending_merchant_shop_draft"),
              let draft = try? JSONDecoder().decode(OnboardingDraftPayload.self, from: data) else { return }
        applyOnboardingDraft(draft)
    }

    private func applyPendingToForm(_ pending: PendingMerchantOnboarding) {
        shopName = pending.shopName
        shopPhone = pending.shopPhone
        currency = pending.currency
        taxId = pending.taxId
        selectedPlanId = pending.subscriptionTier
        isAnnualBilling = pending.billingCycle == "annual"
        if !pending.firstName.isEmpty { firstName = pending.firstName }
        if !pending.lastName.isEmpty { lastName = pending.lastName }
    }

    private func applyOnboardingDraft(_ draft: OnboardingDraftPayload) {
        if !draft.shopName.isEmpty { shopName = draft.shopName }
        shopPhone = draft.shopPhone
        if !draft.currency.isEmpty { currency = draft.currency }
        taxId = draft.taxId
        if let tier = draft.subscriptionTier, !tier.isEmpty { selectedPlanId = tier }
        if draft.billingCycle == "annual" { isAnnualBilling = true }
        if let fn = draft.firstName, !fn.isEmpty { firstName = fn }
        if let ln = draft.lastName, !ln.isEmpty { lastName = ln }
    }

    private func syncOnboardingDraftToServerIfPossible() {
        guard let token = postAuthSession?.accessToken ?? mfaSession?.accessToken
                ?? MerchantAuthManager.shared.userAccessToken else { return }
        persistShopDraftLocally()
        let draft = OnboardingDraftPayload(
            shopName: shopName.trimmingCharacters(in: .whitespacesAndNewlines),
            shopPhone: shopPhone.trimmingCharacters(in: .whitespacesAndNewlines),
            currency: currency,
            taxId: taxId.trimmingCharacters(in: .whitespacesAndNewlines),
            subscriptionTier: selectedPlanId,
            billingCycle: selectedPlanId == "offline_perpetual" ? "perpetual" : (isAnnualBilling ? "annual" : "monthly"),
            firstName: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
            lastName: lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        Task {
            try? await AuthService.shared.upsertOnboardingDraft(accessToken: token, draft: draft)
        }
    }

    private func handleSelectPlan() {
        isLoading = true
        errorMessage = ""
        triggerHapticFeedback(.medium)

        Task {
            do {
                let mId = activeMerchantId

                // 1. Calculate subscription parameters
                let tier = selectedPlanId
                let status = "pending_payment"
                let expiry: Double? = nil

                // 2. If online and has internet, update database on Supabase
                if await NetworkManager.shared.isConnected() {
                    let isoExpiry = expiry.map { NetworkManager.iso8601.string(from: Date(timeIntervalSince1970: $0)) }
                    var payload: [String: Any] = [
                        "subscription_tier": tier,
                        "subscription_status": status
                    ]
                    if let isoExpiry = isoExpiry { payload["subscription_expires_at"] = isoExpiry }

                    _ = try await NetworkManager.shared.sendSupabaseRequest(
                        method: "PATCH",
                        endpoint: "merchants",
                        queryItems: [URLQueryItem(name: "id", value: "eq.\(mId)")],
                        payload: payload
                    )
                }

                // 3. Save subscription details locally in Keychain
                MerchantAuthManager.shared.saveSubscription(tier: tier, status: status, expiry: expiry)

                // 4. Force offlineSyncMode depending on plan choice
                await MainActor.run {
                    OfflineSyncModeController.applyForSubscriptionTier(tier, modelContext: modelContext)
                    isLoading = false
                    triggerNotificationFeedback(.success)
                    withAnimation { isLoggedIn = true }
                    onAuthenticated?()
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    triggerNotificationFeedback(.error)
                    errorMessage = "บันทึกแผนสมาชิกไม่สำเร็จ: \(error.localizedDescription)"
                }
            }
        }
    }

    private func applySubscriptionCache(from merchantSettings: [String: Any]?) {
        guard let tier = merchantSettings?["subscription_tier"] as? String, !tier.isEmpty else {
            NetworkManager.shared.simulateOffline = UserDefaults.standard.bool(forKey: "offline_sync_mode")
            return
        }
        let status = merchantSettings?["subscription_status"] as? String ?? "active"
        let expiry = (merchantSettings?["subscription_expires_at"] as? String)
            .flatMap { ISO8601DateFormatter().date(from: $0) }
        applySubscriptionCache(tier: tier, status: status, expiry: expiry)
    }

    private func applySubscriptionCache(tier: String, status: String, expiry: Date?) {
        MerchantAuthManager.shared.saveSubscription(
            tier: tier,
            status: status,
            expiry: expiry?.timeIntervalSince1970
        )
        OfflineSyncModeController.applyForSubscriptionTier(tier, modelContext: modelContext)
    }

    private func seedNewMerchantDataIfWorkspaceEmpty(merchantId: UUID) {
        // Only bootstrap roles for a wiped / empty local workspace.
        let existingEmployees = (try? modelContext.fetch(FetchDescriptor<Employee>())) ?? []
        let existingTables = (try? modelContext.fetch(FetchDescriptor<RestaurantTable>())) ?? []
        let existingMenu = (try? modelContext.fetch(FetchDescriptor<MenuItem>())) ?? []
        guard existingEmployees.isEmpty, existingTables.isEmpty, existingMenu.isEmpty else { return }
        RoleBootstrap.ensureDefaultRoles(modelContext: modelContext)
    }
}

// MARK: - Premium Kitchen Background
struct KitchenBackgroundView: View {
    @State private var animateBlobs = false

    var body: some View {
        ZStack {
            // Video Kitchen base
            LoopingVideoPlayer(videoName: "LoginBG", videoExtension: "mp4")
                .ignoresSafeArea()

            // Motion Blobs (Drifting light leaks)
            GeometryReader { geo in
                ZStack {
                    // Blob 1: Orange/Amber light leak (top-right to bottom-right)
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color(hex: "2D71F8").opacity(0.35), Color.clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: 180
                            )
                        )
                        .frame(width: 360, height: 360)
                        .offset(
                            x: animateBlobs ? geo.size.width * 0.15 : geo.size.width * 0.4,
                            y: animateBlobs ? geo.size.height * 0.2 : geo.size.height * -0.1
                        )

                    // Blob 2: Mint Green light leak (bottom-left to top-left)
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color(hex: "A7F3D0").opacity(0.3), Color.clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: 180
                            )
                        )
                        .frame(width: 360, height: 360)
                        .offset(
                            x: animateBlobs ? geo.size.width * -0.4 : geo.size.width * -0.2,
                            y: animateBlobs ? geo.size.height * 0.3 : geo.size.height * 0.6
                        )

                    // Blob 3: Soft Gold/Yellow leak (center breathing)
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color(hex: "FFCC00").opacity(0.2), Color.clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: 150
                            )
                        )
                        .frame(width: 300, height: 300)
                        .scaleEffect(animateBlobs ? 1.15 : 0.9)
                        .opacity(animateBlobs ? 0.85 : 0.6)
                        .offset(
                            x: animateBlobs ? geo.size.width * 0.1 : geo.size.width * -0.1,
                            y: animateBlobs ? geo.size.height * 0.1 : geo.size.height * 0.2
                        )
                }
                .blur(radius: 80)
            }
            .ignoresSafeArea()

            // Subtle dark overlay to ensure readability for text elements outside the glass panel
            Color.black.opacity(0.12)
                .ignoresSafeArea()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 12.0).repeatForever(autoreverses: true)) {
                animateBlobs = true
            }
        }
    }
}


// MARK: - Visual Effect Blur (UIKit bridge for premium blur depth)
struct VisualEffectBlur: UIViewRepresentable {
    var material: UIBlurEffect.Style

    func makeUIView(context: Context) -> UIVisualEffectView {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: material))
        return view
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: material)
    }
}

// MARK: - Frosted Glass Auth Modal
private struct FrostedAuthPanelModifier: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    // Frosted glass blur using SwiftUI material
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(.ultraThinMaterial)

                    // Highly translucent glass base tint layer (maximum transparency)
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.12),
                                    Color.white.opacity(0.02)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    // Specular highlights and reflections (warm golden glow matching mockup)
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.35),
                            Color.clear,
                            Color(hex: "2D71F8").opacity(isActive ? 0.08 : 0.02)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay {
                    // Thin white stroke
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(
                            Color.white.opacity(0.45),
                            lineWidth: 1.0
                        )
                }
                // Soft shadow for depth
                .shadow(color: Color.black.opacity(0.10), radius: 24, x: 0, y: 12)
            }
    }
}

private extension View {
    func frostedAuthPanel(isActive: Bool) -> some View {
        modifier(FrostedAuthPanelModifier(isActive: isActive))
    }
}

// MARK: - Scale Button Style
struct ScaleButtonStyle: ButtonStyle {
    var floatAnimation: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .offset(y: floatAnimation ? -2 : 2)
            .animation(.spring(response: 0.25, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

// MARK: - Premium Auth Input Modifier
struct PremiumAuthInputModifier: ViewModifier {
    var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.white.opacity(isFocused ? 0.18 : 0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isFocused ? Color(hex: "2D71F8") : Color.white.opacity(0.35), lineWidth: isFocused ? 1.5 : 1)
            )
            .scaleEffect(isFocused ? 1.015 : 1.0)
            .shadow(color: isFocused ? Color(hex: "2D71F8").opacity(0.2) : Color.black.opacity(0.0), radius: isFocused ? 8 : 0, x: 0, y: isFocused ? 3 : 0)
    }
}

// MARK: - Premium Auth Icon Modifier
struct PremiumAuthIconModifier: ViewModifier {
    var isFocused: Bool
    var activeColor: Color = Color(hex: "2D71F8")

    func body(content: Content) -> some View {
        content
            .foregroundColor(isFocused ? activeColor : Color.white.opacity(0.6))
            .font(.system(size: 14))
            .scaleEffect(isFocused ? 1.15 : 1.0)
            .rotationEffect(.degrees(isFocused ? 8 : 0))
    }
}

extension View {
    func premiumAuthInputStyle(isFocused: Bool) -> some View {
        modifier(PremiumAuthInputModifier(isFocused: isFocused))
    }

    func premiumAuthIconStyle(isFocused: Bool) -> some View {
        modifier(PremiumAuthIconModifier(isFocused: isFocused))
    }
}

// MARK: - Preview
#Preview {
    MerchantAuthView()
        .environmentObject(LocalizationManager.shared)
        .modelContainer(for: [RestaurantTable.self, Category.self, MenuItem.self, Role.self], inMemory: true)
}

// MARK: - Extensions for Password Reset Modal
extension MerchantAuthView {
    private func triggerHapticFeedback(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }

    private func invalidateCaptcha() {
        captchaToken = nil
        captchaStatus = .loading
        captchaResetToken += 1
    }

    private func triggerNotificationFeedback(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }

    private var forgotPasswordSheet: some View {
        VStack(spacing: 24) {
            HStack {
                Spacer()
                Button(action: {
                    showingForgotPasswordSheet = false
                    resetEmail = ""
                    resetSuccessMessage = ""
                }) {
                    Image(systemName: "xmark.circle") // Outline close icon
                        .font(.title2)
                        .foregroundColor(Color.primary.opacity(0.6))
                }
                .buttonStyle(ScaleButtonStyle(floatAnimation: buttonFloat))
            }

            VStack(spacing: 8) {
                Image(systemName: "key") // Outline key icon
                    .font(.system(size: 44))
                    .foregroundColor(Color(hex: "2D71F8"))

                Text(L.Auth.resetTitle.t)
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundColor(.primary)

                Text(L.Auth.resetDesc.t)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color.primary.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Text("auth_reset_mfa_note".t)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color.primary.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            if !resetSuccessMessage.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle") // Outline checkmark
                        .font(.system(size: 36))
                        .foregroundColor(.green)
                    Text(resetSuccessMessage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.green)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding()
                .background(Color.green.opacity(0.08))
                .cornerRadius(12)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L.Auth.emailLbl.t)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color.primary.opacity(0.8))

                    HStack {
                        Image(systemName: "envelope") // Outline envelope
                            .foregroundColor(Color.primary.opacity(0.5))
                            .font(.system(size: 14))
                        TextField("", text: $resetEmail, prompt: Text("owner@myrestaurant.com").foregroundColor(Color.primary.opacity(0.4)))
                            .font(.system(size: 14))
                            .foregroundColor(.primary)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                    )
                }

                if !AppConfig.shared.turnstileSiteKey.isEmpty {
                    AuthCaptchaBlock(
                        siteKey: AppConfig.shared.turnstileSiteKey,
                        captchaToken: $captchaToken,
                        captchaResetToken: $captchaResetToken,
                        captchaStatus: $captchaStatus,
                        appearance: .onLightSheet,
                        instanceId: "reset"
                    )
                }

                let resetCaptchaBlocking = !AppConfig.shared.turnstileSiteKey.isEmpty
                    && (captchaToken == nil || captchaStatus == .failed || captchaStatus == .expired || captchaStatus == .loading)
                let resetBlocked = resetEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || isSendingReset
                    || resetCaptchaBlocking

                Button(action: handleResetPassword) {
                    if isSendingReset {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Capsule().fill(Color(hex: "2D71F8")))
                    } else {
                        Text(L.Auth.sendResetBtn.t)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                Group {
                                    if resetBlocked {
                                        Capsule()
                                            .fill(Color(hex: "2D71F8").opacity(0.4))
                                    } else {
                                        Capsule()
                                            .fill(
                                                LinearGradient(
                                                    colors: [Color(hex: "2D71F8"), Color(hex: "1A5FE8")],
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                )
                                            )
                                    }
                                }
                            )
                            .shadow(color: Color(hex: "1A5FE8").opacity(resetBlocked ? 0.0 : 0.3), radius: 8, x: 0, y: 4)
                    }
                }
                .buttonStyle(ScaleButtonStyle(floatAnimation: buttonFloat))
                .disabled(resetBlocked)
            }

            Spacer()
        }
        .padding(32)
        .presentationDetents([.large, .medium])
    }

    private func handleResetPassword() {
        let cleanResetEmail = resetEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanResetEmail.isEmpty else { return }
        if !AppConfig.shared.turnstileSiteKey.isEmpty && captchaToken == nil {
            resetSuccessMessage = "กรุณายืนยัน Captcha ก่อนส่งอีเมลรีเซ็ตรหัสผ่าน"
            return
        }
        isSendingReset = true
        triggerHapticFeedback(.medium)

        Task {
            do {
                try await AuthService.shared.resetPassword(
                    email: cleanResetEmail,
                    captchaToken: captchaToken,
                    preferredLanguage: LocalizationManager.shared.currentLanguage.rawValue
                )
                await MainActor.run {
                    isSendingReset = false
                    invalidateCaptcha()
                    triggerNotificationFeedback(.success)
                    resetSuccessMessage = String(format: "auth_reset_success_template".t, cleanResetEmail)
                }
            } catch {
                await MainActor.run {
                    isSendingReset = false
                    invalidateCaptcha()
                    triggerNotificationFeedback(.error)
                    resetSuccessMessage = error.localizedDescription
                }
            }
        }
    }

    private func handleDeepLinkAction(_ action: AuthDeepLinkAction) {
        switch action {
        case .emailConfirmed(let session):
            deepLinkCoordinator.clearPendingAction()
            showingForgotPasswordSheet = false
            resetSuccessMessage = ""
            isLoading = true
            errorMessage = ""
            Task {
                do {
                    let user = try await AuthService.shared.fetchCurrentUser(accessToken: session.accessToken)
                    let fullSession = AuthSession(
                        accessToken: session.accessToken,
                        refreshToken: session.refreshToken,
                        user: user
                    )
                    let preparation = try await AuthService.shared.prepareOwnerTOTP(
                        accessToken: fullSession.accessToken,
                        preferredFactorId: user.totpFactorId
                    )
                    await MainActor.run {
                        mfaSession = fullSession
                        mfaCode = ""
                        mfaSecretCopied = false
                        mfaEnrollAccepted = false
                        switch preparation {
                        case .verifyExisting(let factorId):
                            mfaFactorId = factorId
                            mfaEnrollment = nil
                        case .enrollNew(let enrollment):
                            mfaFactorId = enrollment.factorId
                            mfaEnrollment = enrollment
                        }
                        isLoading = false
                        showingMFA = true
                    }
                } catch {
                    await MainActor.run {
                        isLoading = false
                        triggerNotificationFeedback(.error)
                        errorMessage = error.localizedDescription
                    }
                }
            }

        case .passwordRecovery(let accessToken):
            deepLinkCoordinator.clearPendingAction()
            // Close the "email sent" / forgot-password sheet first so reset form can show.
            showingForgotPasswordSheet = false
            resetSuccessMessage = ""
            recoveryAccessToken = accessToken
            recoveryNewPassword = ""
            recoveryConfirmPassword = ""
            recoverySuccessMessage = ""
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 350_000_000)
                showingRecoveryPasswordSheet = true
            }

        case .failed(let message):
            deepLinkCoordinator.clearPendingAction()
            showingForgotPasswordSheet = false
            triggerNotificationFeedback(.error)
            errorMessage = message
        }
    }

    private var recoveryPasswordSheet: some View {
        VStack(spacing: 20) {
            Text("ตั้งรหัสผ่านใหม่")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)

            SecureField("รหัสผ่านใหม่", text: $recoveryNewPassword)
                .textContentType(.newPassword)
                .premiumAuthInputStyle(isFocused: false)

            SecureField("ยืนยันรหัสผ่านใหม่", text: $recoveryConfirmPassword)
                .textContentType(.newPassword)
                .premiumAuthInputStyle(isFocused: false)

            if !recoverySuccessMessage.isEmpty {
                Text(recoverySuccessMessage)
                    .font(.footnote)
                    .foregroundColor(Color(hex: "A7F3D0"))
                    .multilineTextAlignment(.center)
            }

            Button(action: handleRecoveryPasswordUpdate) {
                Group {
                    if isUpdatingRecoveryPassword {
                        ProgressView().tint(.white)
                    } else {
                        Text("บันทึกรหัสผ่านใหม่")
                    }
                }
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "2D71F8"), Color(hex: "1A5FE8")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
            }
            .disabled(isUpdatingRecoveryPassword)
        }
        .padding(32)
        .presentationDetents([.medium])
    }

    private func handleRecoveryPasswordUpdate() {
        guard recoveryNewPassword.count >= 8 else {
            recoverySuccessMessage = "auth_error_short_password".t
            return
        }
        guard recoveryNewPassword == recoveryConfirmPassword else {
            recoverySuccessMessage = "auth_error_mismatched_passwords".t
            return
        }

        isUpdatingRecoveryPassword = true
        recoverySuccessMessage = ""

        Task {
            do {
                try await AuthService.shared.updatePassword(
                    accessToken: recoveryAccessToken,
                    newPassword: recoveryNewPassword
                )
                await MainActor.run {
                    isUpdatingRecoveryPassword = false
                    triggerNotificationFeedback(.success)
                    recoverySuccessMessage = "เปลี่ยนรหัสผ่านสำเร็จแล้ว กรุณาเข้าสู่ระบบด้วยรหัสผ่านใหม่ (หากเปิด Two-Factor ไว้ ยังต้องกรอกรหัสจากแอป Authenticator)"
                    authMode = "login"
                    password = ""
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        showingRecoveryPasswordSheet = false
                    }
                }
            } catch {
                await MainActor.run {
                    isUpdatingRecoveryPassword = false
                    triggerNotificationFeedback(.error)
                    recoverySuccessMessage = error.localizedDescription
                }
            }
        }
    }
}
