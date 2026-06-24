// MerchantAuthView.swift
// AlphaPos — Merchant Sign-In & Onboarding Wizard

import SwiftUI
import SwiftData

struct MerchantAuthView: View {
    var onAuthenticated: (() -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @AppStorage("is_logged_in") private var isLoggedIn = false
    @AppStorage("active_merchant_id") private var activeMerchantId = "163350b0-056d-4d5e-b5d4-24e7aac5ab6d"
    @AppStorage("logged_in_email") private var loggedInEmail = "owner@alphapos.com"
    @AppStorage("logged_in_name") private var loggedInName = "Somchai Lertwit"
    
    // Auth Mode: "login" or "signup"
    @State private var authMode: String = "login"
    
    // Form Inputs
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var firstName = ""
    @State private var lastName = ""
    
    // Shop Registration Inputs (Step 2)
    @State private var signupStep = 1 // Step 1: User Account, Step 2: Shop Info
    @State private var shopName = ""
    @State private var businessType = "Restaurant" // Restaurant, Cafe, Bar
    @State private var currency = "THB" // THB (฿), USD ($), EUR (€)
    @State private var taxId = ""
    @State private var shopPhone = ""
    
    // Feedback States
    @State private var errorMessage = ""
    @State private var isLoading = false
    
    // Password toggles & sheets
    @State private var showPassword = false
    @State private var showingForgotPasswordSheet = false
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
            // 1. Moving/Animated abstract background (White focus)
            AnimatedWhiteBackgroundView()
                .ignoresSafeArea()
            
            // 2. Main Container
            ScrollView {
                VStack {
                    Spacer(minLength: 40)
                    
                    // Brand Header
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(APGradient.accent)
                                .frame(width: 44, height: 44)
                                .shadow(color: Color.appAccent.opacity(0.3), radius: 8, x: 0, y: 3)
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 22, weight: .black))
                                .foregroundColor(.white)
                        }
                        
                        VStack(alignment: .leading, spacing: 1) {
                            Text("AlphaPos")
                                .font(.system(size: 24, weight: .black, design: .rounded))
                                .foregroundColor(Color(hex: "111827")) // Slate 900
                            Text("auth_brand_sub".t)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Color(hex: "6B7280")) // Slate 500
                        }
                    }
                    .padding(.bottom, 24)
                    
                    // Glassmorphic Card Container
                    VStack(spacing: 0) {
                        if authMode == "login" {
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
                    .padding(32)
                    .frame(width: 480)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color.white.opacity(0.85))
                            .background(VisualEffectBlur(material: .systemThinMaterialLight))
                            .shadow(color: Color.black.opacity(0.06), radius: 25, x: 0, y: 15)
                            .overlay(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .stroke(Color.white.opacity(0.6), lineWidth: 1.5)
                            )
                    )
                    .animation(.spring(response: 0.5, dampingFraction: 0.82), value: authMode)
                    .animation(.spring(response: 0.5, dampingFraction: 0.82), value: signupStep)
                    
                    Spacer(minLength: 40)
                    
                    // Footer Credits
                    VStack(spacing: 4) {
                        Text(L.Auth.sysOnlineSsl.t)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color(hex: "9CA3AF"))
                        Text(L.Auth.cloudEngineVer.t)
                            .font(.system(size: 9))
                            .foregroundColor(Color(hex: "D1D5DB"))
                    }
                    .padding(.bottom, 20)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .sheet(isPresented: $showingForgotPasswordSheet) {
            forgotPasswordSheet
        }
    }
    
    // MARK: - Login Form
    private var loginForm: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L.Auth.signInTitle.t)
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(Color(hex: "111827"))
                Text(L.Auth.signInDesc.t)
                    .font(.system(size: 13))
                    .foregroundColor(Color(hex: "6B7280"))
            }
            .padding(.bottom, 8)
            
            if !errorMessage.isEmpty {
                errorMessageBanner
            }
            
            // Email Input
            VStack(alignment: .leading, spacing: 6) {
                Text(L.Auth.emailLbl.t)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(hex: "4B5563"))
                
                HStack {
                    Image(systemName: "envelope.fill")
                        .foregroundColor(focusedField == .email ? Color.appAccent : Color(hex: "9CA3AF"))
                        .font(.system(size: 14))
                    TextField("owner@myrestaurant.com", text: $email)
                        .font(.system(size: 14))
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .focused($focusedField, equals: .email)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color(hex: "F9FAFB"))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(focusedField == .email ? Color.appAccent.opacity(0.8) : Color(hex: "E5E7EB"), lineWidth: focusedField == .email ? 2 : 1)
                )
                .animation(.easeInOut(duration: 0.15), value: focusedField)
            }
            
            // Password Input
            VStack(alignment: .leading, spacing: 6) {
                Text(L.Auth.passwordLbl.t)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(hex: "4B5563"))
                
                HStack {
                    Image(systemName: "lock.fill")
                        .foregroundColor(focusedField == .password ? Color.appAccent : Color(hex: "9CA3AF"))
                        .font(.system(size: 14))
                    
                    if showPassword {
                        TextField("Password", text: $password)
                            .font(.system(size: 14))
                            .focused($focusedField, equals: .password)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    } else {
                        SecureField("••••••••••••", text: $password)
                            .font(.system(size: 14))
                            .focused($focusedField, equals: .password)
                    }
                    
                    Button(action: {
                        showPassword.toggle()
                    }) {
                        Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                            .foregroundColor(Color(hex: "9CA3AF"))
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color(hex: "F9FAFB"))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(focusedField == .password ? Color.appAccent.opacity(0.8) : Color(hex: "E5E7EB"), lineWidth: focusedField == .password ? 2 : 1)
                )
                .animation(.easeInOut(duration: 0.15), value: focusedField)
            }
            
            // Forgot Password Link
            HStack {
                Spacer()
                Button(action: {
                    showingForgotPasswordSheet = true
                }) {
                    Text(L.Auth.forgotPassword.t)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color.appAccent)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, -10)
            
            // Remember checkbox (Dummy UI)
            HStack {
                Image(systemName: "checkmark.square.fill")
                    .foregroundColor(Color.appAccent)
                Text(L.Auth.rememberStore.t)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(hex: "4B5563"))
            }
            .padding(.top, 2)
            
            // Action Button
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
                .background(email.isEmpty || password.isEmpty ? Color(hex: "9CA3AF") : Color.appAccent)
                .foregroundColor(.white)
                .cornerRadius(10)
                .shadow(color: Color.appAccent.opacity(email.isEmpty || password.isEmpty ? 0.0 : 0.25), radius: 10, x: 0, y: 5)
            }
            .disabled(email.isEmpty || password.isEmpty || isLoading)
            .padding(.top, 6)
            
            // Mode switcher
            HStack {
                Spacer()
                Text(L.Auth.noAccount.t)
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "6B7280"))
                Button(action: {
                    errorMessage = ""
                    withAnimation { authMode = "signup" }
                }) {
                    Text(L.Auth.registerBtn.t)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color.appAccent)
                }
                Spacer()
            }
            .padding(.top, 4)
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
                        .foregroundColor(Color(hex: "111827"))
                    Text(signupStep == 1 ? "Step 1: Admin Account Setup" : "Step 2: Restaurant Details")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color.appAccent)
                }
                Spacer()
                
                // Dots representing steps
                HStack(spacing: 6) {
                    Circle()
                        .fill(signupStep >= 1 ? Color.appAccent : Color(hex: "D1D5DB"))
                        .frame(width: 8, height: 8)
                    Circle()
                        .fill(signupStep >= 2 ? Color.appAccent : Color(hex: "D1D5DB"))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.bottom, 8)
            
            if !errorMessage.isEmpty {
                errorMessageBanner
            }
            
            if signupStep == 1 {
                accountDetailsStep
            } else {
                shopDetailsStep
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
                        .foregroundColor(Color(hex: "4B5563"))
                    TextField("Somchai", text: $firstName)
                        .font(.system(size: 14))
                        .focused($focusedField, equals: .firstName)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Color(hex: "F9FAFB"))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(focusedField == .firstName ? Color.appAccent.opacity(0.8) : Color(hex: "E5E7EB"), lineWidth: focusedField == .firstName ? 2 : 1)
                        )
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(L.Auth.lastName.t)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(hex: "4B5563"))
                    TextField("Lertwit", text: $lastName)
                        .font(.system(size: 14))
                        .focused($focusedField, equals: .lastName)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Color(hex: "F9FAFB"))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(focusedField == .lastName ? Color.appAccent.opacity(0.8) : Color(hex: "E5E7EB"), lineWidth: focusedField == .lastName ? 2 : 1)
                        )
                }
            }
            
            // Email Input
            VStack(alignment: .leading, spacing: 6) {
                Text(L.Auth.emailLbl.t)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(hex: "4B5563"))
                TextField("email@example.com", text: $email)
                    .font(.system(size: 14))
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .focused($focusedField, equals: .email)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color(hex: "F9FAFB"))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(focusedField == .email ? Color.appAccent.opacity(0.8) : Color(hex: "E5E7EB"), lineWidth: focusedField == .email ? 2 : 1)
                    )
            }
            
            // Password Input
            VStack(alignment: .leading, spacing: 6) {
                Text(L.Auth.passwordLbl.t)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(hex: "4B5563"))
                SecureField("Min 8 characters", text: $password)
                    .font(.system(size: 14))
                    .focused($focusedField, equals: .password)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color(hex: "F9FAFB"))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(focusedField == .password ? Color.appAccent.opacity(0.8) : Color(hex: "E5E7EB"), lineWidth: focusedField == .password ? 2 : 1)
                    )
            }
            
            // Password Confirmation Input
            VStack(alignment: .leading, spacing: 6) {
                Text(L.Auth.confirmPassword.t)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(hex: "4B5563"))
                SecureField("Re-enter password", text: $confirmPassword)
                    .font(.system(size: 14))
                    .focused($focusedField, equals: .confirmPassword)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color(hex: "F9FAFB"))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(focusedField == .confirmPassword ? Color.appAccent.opacity(0.8) : Color(hex: "E5E7EB"), lineWidth: focusedField == .confirmPassword ? 2 : 1)
                    )
            }
            
            // CTA Button to Step 2
            Button(action: validateAndGoToStep2) {
                Text(L.Auth.continueStore.t)
                    .font(.system(size: 14, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(firstName.isEmpty || lastName.isEmpty || email.isEmpty || password.isEmpty ? Color(hex: "9CA3AF") : Color.appAccent)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .disabled(firstName.isEmpty || lastName.isEmpty || email.isEmpty || password.isEmpty)
            .padding(.top, 6)
            
            // Mode switcher
            Button(action: {
                errorMessage = ""
                withAnimation { authMode = "login" }
            }) {
                HStack {
                    Spacer()
                    Text(L.Auth.alreadyHaveStore.t)
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "6B7280"))
                    Text(L.Auth.signInBtn.t)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color.appAccent)
                    Spacer()
                }
            }
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
                    .foregroundColor(Color(hex: "4B5563"))
                TextField("Cafe Amazon", text: $shopName)
                    .font(.system(size: 14))
                    .focused($focusedField, equals: .shopName)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color(hex: "F9FAFB"))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(focusedField == .shopName ? Color.appAccent.opacity(0.8) : Color(hex: "E5E7EB"), lineWidth: focusedField == .shopName ? 2 : 1)
                    )
            }
            
            // Business Type & Currency
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L.Auth.businessType.t)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(hex: "4B5563"))
                    
                    Picker("Business Type", selection: $businessType) {
                        Text("business_type_restaurant".t).tag("Restaurant")
                        Text("business_type_cafe".t).tag("Cafe")
                        Text("business_type_bar".t).tag("Bar")
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color(hex: "F9FAFB"))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(hex: "E5E7EB"), lineWidth: 1)
                    )
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(L.Auth.currency.t)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(hex: "4B5563"))
                    
                    Picker("Currency", selection: $currency) {
                        Text("THB (฿)").tag("THB")
                        Text("USD ($)").tag("USD")
                        Text("EUR (€)").tag("EUR")
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color(hex: "F9FAFB"))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(hex: "E5E7EB"), lineWidth: 1)
                    )
                }
            }
            
            // Tax ID / Business Reg No
            VStack(alignment: .leading, spacing: 6) {
                Text(L.Auth.taxId.t)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(hex: "4B5563"))
                TextField("13 digits ID", text: $taxId)
                    .font(.system(size: 14))
                    .keyboardType(.numberPad)
                    .focused($focusedField, equals: .taxId)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color(hex: "F9FAFB"))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(focusedField == .taxId ? Color.appAccent.opacity(0.8) : Color(hex: "E5E7EB"), lineWidth: focusedField == .taxId ? 2 : 1)
                    )
            }
            
            // Contact Phone
            VStack(alignment: .leading, spacing: 6) {
                Text(L.Auth.contactPhone.t)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(hex: "4B5563"))
                TextField("02-XXX-XXXX", text: $shopPhone)
                    .font(.system(size: 14))
                    .keyboardType(.phonePad)
                    .focused($focusedField, equals: .shopPhone)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color(hex: "F9FAFB"))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(focusedField == .shopPhone ? Color.appAccent.opacity(0.8) : Color(hex: "E5E7EB"), lineWidth: focusedField == .shopPhone ? 2 : 1)
                    )
            }
            
            // Action Buttons
            HStack(spacing: 12) {
                Button(action: { withAnimation { signupStep = 1 } }) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 14, weight: .bold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(Color(hex: "E5E7EB"))
                        .foregroundColor(Color(hex: "4B5563"))
                        .cornerRadius(10)
                }
                
                Button(action: handleSignUp) {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .padding(.trailing, 8)
                        }
                        Text(L.Auth.createStoreBtn.t)
                            .font(.system(size: 14, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(shopName.isEmpty || taxId.isEmpty || shopPhone.isEmpty ? Color(hex: "9CA3AF") : Color.appAccent)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(shopName.isEmpty || taxId.isEmpty || shopPhone.isEmpty || isLoading)
            }
            .padding(.top, 6)
        }
    }
    
    private var errorMessageBanner: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            Text(errorMessage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.red)
            Spacer()
        }
        .padding(12)
        .background(Color.red.opacity(0.1))
        .cornerRadius(10)
    }
    
    // MARK: - Logic Handlers
    private func handleLogin() {
        errorMessage = ""
        guard !isLoading else { return }
        isLoading = true

        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            do {
                // บังคับ Online ก่อนทุกครั้ง — await ต้องอยู่ใน Task {} เท่านั้น
                guard await NetworkManager.shared.isConnected() else {
                    await MainActor.run {
                        self.isLoading = false
                        self.errorMessage = "ต้องเชื่อมต่ออินเทอร์เน็ตเพื่อล็อกอิน\nกรุณาตรวจสอบการเชื่อมต่อ"
                    }
                    return
                }
                let session = try await AuthService.shared.signIn(email: cleanEmail, password: cleanPassword)
                let mId = UUID(uuidString: session.user.merchantId ?? "") ?? UUID()
                
                // Authenticate with Edge Function to obtain the JWT token and save it to the Keychain
                try await MerchantAuthManager.shared.authenticate(
                    merchantId: mId.uuidString.lowercased(),
                    deviceSecret: AppConfig.shared.defaultDeviceSecret
                )
                
                await MainActor.run {
                    isLoading = false
                    activeMerchantId = mId.uuidString.lowercased()
                    loggedInEmail = cleanEmail
                    loggedInName = session.user.fullName ?? "Store Owner"
                    seedNewMerchantData(merchantId: mId)
                    withAnimation { isLoggedIn = true }
                    onAuthenticated?()
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func validateAndGoToStep2() {
        errorMessage = ""
        if !email.contains("@") {
            errorMessage = "auth_error_invalid_email".t
            return
        }
        if password.count < 8 {
            errorMessage = "auth_error_short_password".t
            return
        }
        if password != confirmPassword {
            errorMessage = "auth_error_mismatched_passwords".t
            return
        }
        
        withAnimation {
            signupStep = 2
        }
    }
    
    private func handleSignUp() {
        errorMessage = ""
        isLoading = true
        
        Task {
            do {
                // บังคับ Online สำหรับ Sign Up — ต้องสร้างบัญชีบน server
                guard await NetworkManager.shared.isConnected() else {
                    await MainActor.run {
                        isLoading = false
                        errorMessage = "ต้องเชื่อมต่ออินเทอร์เน็ตเพื่อสมัครใช้งาน\nกรุณาตรวจสอบการเชื่อมต่อ"
                    }
                    return
                }
                _ = try await AuthService.shared.signUp(
                    email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                    password: password,
                    userData: ["first_name": firstName, "last_name": lastName]
                )
                
                let newMerchantUUID = UUID()
                
                // Authenticate new merchant to obtain and save JWT in Keychain
                try await MerchantAuthManager.shared.authenticate(
                    merchantId: newMerchantUUID.uuidString.lowercased(),
                    deviceSecret: AppConfig.shared.defaultDeviceSecret
                )
                
                await MainActor.run {
                    isLoading = false
                    seedNewMerchantData(merchantId: newMerchantUUID)
                    activeMerchantId = newMerchantUUID.uuidString.lowercased()
                    loggedInEmail = email
                    loggedInName = "\(firstName) \(lastName)"
                    withAnimation { isLoggedIn = true }
                    onAuthenticated?()
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func seedNewMerchantData(merchantId: UUID) {
        // Only seed if we don't have roles/employees seeded yet to avoid duplicates
        let existingEmployees = (try? modelContext.fetch(FetchDescriptor<Employee>())) ?? []
        guard existingEmployees.isEmpty else { return }


        
        // Seed default tables in memory/SwiftData container
        let t1 = RestaurantTable(id: UUID(), tableNumber: "1", capacity: 4, status: "vacant", qrCodeIdentifier: nil, positionX: 200, positionY: 200, floor: 1, isSynced: false, isDeleted: false, updatedAt: Date())
        let t2 = RestaurantTable(id: UUID(), tableNumber: "2", capacity: 4, status: "vacant", qrCodeIdentifier: nil, positionX: 400, positionY: 200, floor: 1, isSynced: false, isDeleted: false, updatedAt: Date())
        let t3 = RestaurantTable(id: UUID(), tableNumber: "3", capacity: 6, status: "vacant", qrCodeIdentifier: nil, positionX: 600, positionY: 200, floor: 1, isSynced: false, isDeleted: false, updatedAt: Date())
        let t4 = RestaurantTable(id: UUID(), tableNumber: "4", capacity: 2, status: "vacant", qrCodeIdentifier: nil, positionX: 200, positionY: 400, floor: 1, isSynced: false, isDeleted: false, updatedAt: Date())
        let t5 = RestaurantTable(id: UUID(), tableNumber: "5", capacity: 8, status: "vacant", qrCodeIdentifier: nil, positionX: 500, positionY: 400, floor: 1, isSynced: false, isDeleted: false, updatedAt: Date())
        
        modelContext.insert(t1)
        modelContext.insert(t2)
        modelContext.insert(t3)
        modelContext.insert(t4)
        modelContext.insert(t5)
        
        // Seed some default Thai category items
        let catFood = Category(id: UUID(), name: "Burgers & Mains", isSynced: false, isDeleted: false, updatedAt: Date())
        let catDrinks = Category(id: UUID(), name: "Beverages", isSynced: false, isDeleted: false, updatedAt: Date())
        
        modelContext.insert(catFood)
        modelContext.insert(catDrinks)
        
        let item1 = MenuItem(id: UUID().uuidString.lowercased(), name: "Classic Pad Thai", itemDescription: "Stir-fried rice noodles with tofu, shrimp, and peanuts.", price: 120.0, imageUrl: nil, isAvailable: true, taxRate: 7.0, category: catFood, isSynced: false, isDeleted: false, updatedAt: Date())
        let item2 = MenuItem(id: UUID().uuidString.lowercased(), name: "Iced Milk Tea", itemDescription: "Traditional sweet Thai tea served over shaved ice.", price: 65.0, imageUrl: nil, isAvailable: true, taxRate: 7.0, category: catDrinks, isSynced: false, isDeleted: false, updatedAt: Date())
        
        modelContext.insert(item1)
        modelContext.insert(item2)
        
        // Seed default Roles
        let roleManager = Role(
            id: UUID(),
            name: "Store Manager",
            roleDescription: "All administrative privileges",
            permissionKeys: PermissionService.permissionCSV(for: PermissionService.permissions(forRoleName: "Store Manager")),
            isSynced: false,
            isDeleted: false,
            updatedAt: Date()
        )
        let roleStaff = Role(
            id: UUID(),
            name: "Staff",
            roleDescription: "Standard staff privileges",
            permissionKeys: PermissionService.permissionCSV(for: PermissionService.permissions(forRoleName: "Staff")),
            isSynced: false,
            isDeleted: false,
            updatedAt: Date()
        )
        modelContext.insert(roleManager)
        modelContext.insert(roleStaff)

        // Seed default Users
        // Fixed UUIDs — must match SampleDataSeeder constants so employeeId FK references stay valid after re-seed
        let seedEmp1Id  = UUID(uuidString: "11111111-1111-1111-1111-111111111101")!
        let seedEmp2Id  = UUID(uuidString: "11111111-1111-1111-1111-111111111102")!
        let seedUser1Id = UUID(uuidString: "11111111-1111-1111-1111-111111112001")!
        let seedUser2Id = UUID(uuidString: "11111111-1111-1111-1111-111111112002")!
        // Use plain sha256 for seed users — verifyPIN supports the legacy format.
        // Key-stretching is not needed here because seed data is demo-only.
        let user1 = User(id: seedUser1Id, username: "somchai", email: "somchai@alphapos.com", passwordHash: SecurityHelper.sha256("password"), pinCodeHash: SecurityHelper.sha256("1234"), role: roleManager, isSynced: false, isDeleted: false, updatedAt: Date())
        let user2 = User(id: seedUser2Id, username: "somsri", email: "somsri@alphapos.com", passwordHash: SecurityHelper.sha256("password"), pinCodeHash: SecurityHelper.sha256("5678"), role: roleStaff, isSynced: false, isDeleted: false, updatedAt: Date())
        modelContext.insert(user1)
        modelContext.insert(user2)

        // Seed default Employees
        let emp1 = Employee(id: seedEmp1Id, user: user1, firstName: "Somchai", lastName: "Suksabai", phone: "081-234-5678", nationalId: "1234567890123", employmentType: "monthly", payRate: 25000.0, isSynced: false, isDeleted: false, updatedAt: Date())
        let emp2 = Employee(id: seedEmp2Id, user: user2, firstName: "Somsri", lastName: "Jaidee", phone: "089-876-5432", nationalId: "9876543210987", employmentType: "hourly", payRate: 75.0, isSynced: false, isDeleted: false, updatedAt: Date())
        modelContext.insert(emp1)
        modelContext.insert(emp2)
        
        // Save database
        try? modelContext.save()
    }
}

// MARK: - Animated Fluid Pastel blobs Background
struct AnimatedWhiteBackgroundView: View {
    @State private var animate = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Pure clean white base canvas
                Color.white
                    .ignoresSafeArea()
                
                // Blob 1: Soft Indigo/Lavender
                Circle()
                    .fill(Color(hex: "EEF2FF")) // Very light slate blue
                    .frame(width: geometry.size.width * 0.7, height: geometry.size.width * 0.7)
                    .offset(x: animate ? -geometry.size.width * 0.2 : geometry.size.width * 0.2,
                            y: animate ? -geometry.size.height * 0.15 : geometry.size.height * 0.15)
                    .scaleEffect(animate ? 1.08 : 0.92)
                    .opacity(0.85)
                    .blur(radius: 80)
                
                // Blob 2: Soft Light Orchid/Purple
                Circle()
                    .fill(Color(hex: "FAF5FF")) // Very light purple
                    .frame(width: geometry.size.width * 0.6, height: geometry.size.width * 0.6)
                    .offset(x: animate ? geometry.size.width * 0.18 : -geometry.size.width * 0.18,
                            y: animate ? geometry.size.height * 0.12 : -geometry.size.height * 0.12)
                    .scaleEffect(animate ? 0.94 : 1.12)
                    .opacity(0.9)
                    .blur(radius: 70)
                
                // Blob 3: Soft Emerald/Teal Mint
                Circle()
                    .fill(Color(hex: "ECFDF5")) // Very light mint green
                    .frame(width: geometry.size.width * 0.5, height: geometry.size.width * 0.5)
                    .offset(x: animate ? -geometry.size.width * 0.1 : geometry.size.width * 0.15,
                            y: animate ? geometry.size.height * 0.2 : -geometry.size.height * 0.1)
                    .scaleEffect(animate ? 1.05 : 0.95)
                    .opacity(0.75)
                    .blur(radius: 65)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 10.0).repeatForever(autoreverses: true)) {
                    animate = true
                }
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

// MARK: - Preview
#Preview {
    MerchantAuthView()
        .modelContainer(for: [RestaurantTable.self, Category.self, MenuItem.self, Role.self], inMemory: true)
}

// MARK: - Extensions for Password Reset Modal
extension MerchantAuthView {
    private var forgotPasswordSheet: some View {
        VStack(spacing: 24) {
            HStack {
                Spacer()
                Button(action: {
                    showingForgotPasswordSheet = false
                    resetEmail = ""
                    resetSuccessMessage = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(Color(hex: "9CA3AF"))
                }
                .buttonStyle(.plain)
            }
            
            VStack(spacing: 8) {
                Image(systemName: "key.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(APGradient.accent)
                
                Text(L.Auth.resetTitle.t)
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundColor(Color(hex: "111827"))
                
                Text(L.Auth.resetDesc.t)
                    .font(.system(size: 13))
                    .foregroundColor(Color(hex: "6B7280"))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            if !resetSuccessMessage.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.green)
                    Text(resetSuccessMessage)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.green)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(12)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L.Auth.emailLbl.t)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(hex: "4B5563"))
                    
                    HStack {
                        Image(systemName: "envelope.fill")
                            .foregroundColor(Color(hex: "9CA3AF"))
                            .font(.system(size: 14))
                        TextField("owner@myrestaurant.com", text: $resetEmail)
                            .font(.system(size: 14))
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color(hex: "F9FAFB"))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(hex: "E5E7EB"), lineWidth: 1)
                    )
                }
                
                Button(action: handleResetPassword) {
                    if isSendingReset {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(APGradient.accent)
                            .cornerRadius(12)
                    } else {
                        Text(L.Auth.sendResetBtn.t)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(resetEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color(hex: "9CA3AF") : Color.appAccent)
                            .cornerRadius(12)
                    }
                }
                .disabled(resetEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSendingReset)
            }
            
            Spacer()
        }
        .padding(32)
        .presentationDetents([.medium])
    }
    
    private func handleResetPassword() {
        let cleanResetEmail = resetEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanResetEmail.isEmpty else { return }
        isSendingReset = true
        
        Task {
            do {
                try await AuthService.shared.resetPassword(email: cleanResetEmail)
                await MainActor.run {
                    isSendingReset = false
                    resetSuccessMessage = String(format: "auth_reset_success_template".t, cleanResetEmail)
                }
            } catch {
                await MainActor.run {
                    isSendingReset = false
                    resetSuccessMessage = "auth_reset_failed".t
                }
            }
        }
    }
}
