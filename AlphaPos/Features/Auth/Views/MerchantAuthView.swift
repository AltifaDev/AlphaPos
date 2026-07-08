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

    // Pricing Package Inputs (Step 3)
    @State private var selectedPlanId: String = "offline_perpetual"
    @State private var isAnnualBilling = false

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

                        // Brand Header
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color(hex: "FF9500"), Color(hex: "FF5E00")],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 44, height: 44)
                                    .shadow(color: Color(hex: "FF5E00").opacity(logoFloat ? 0.45 : 0.25), radius: logoFloat ? 10 : 6, x: 0, y: 3)
                                Image(systemName: "fork.knife")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.white)
                            }

                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 0) {
                                    Text("Alpha")
                                        .font(.system(size: 26, weight: .black, design: .rounded))
                                        .foregroundColor(.white)
                                    Text("Pos")
                                        .font(.system(size: 26, weight: .black, design: .rounded))
                                        .foregroundColor(Color(hex: "FF9500"))
                                }
                                Text("auth_brand_sub".t)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(Color(hex: "A7F3D0").opacity(0.95))
                            }
                        }
                        .offset(y: logoFloat ? -5 : 5)
                        .padding(.bottom, 24)
                        .scaleEffect(authCardAppeared ? 1 : 0.96)
                        .opacity(authCardAppeared ? 1 : 0)

                        // Frosted Glass / Glassmorphism modal container
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
        }
        .sheet(isPresented: $showingForgotPasswordSheet) {
            forgotPasswordSheet
        }
    }    // MARK: - Login Form
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

                    if showPassword {
                        TextField("", text: $password, prompt: Text("Password").foregroundColor(.white.opacity(0.45)))
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                            .focused($focusedField, equals: .password)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    } else {
                        SecureField("", text: $password, prompt: Text("••••••••••••").foregroundColor(.white.opacity(0.45)))
                            .font(.system(size: 14))
                            .foregroundColor(.white)
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
                        .foregroundColor(Color(hex: "FF9500"))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, -10)

            // Remember checkbox
            HStack(spacing: 8) {
                Image(systemName: "checkmark.square")
                    .foregroundColor(Color(hex: "FF9500"))
                    .font(.system(size: 14, weight: .semibold))
                Text(L.Auth.rememberStore.t)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(.top, 2)

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
                        if email.isEmpty || password.isEmpty {
                            Capsule()
                                .fill(Color.orange.opacity(0.35))
                        } else {
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [Color(hex: "FF9500"), Color(hex: "FF5E00")],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        }
                    }
                )
                .foregroundColor(email.isEmpty || password.isEmpty ? .white.opacity(0.6) : .white)
                .shadow(color: Color(hex: "FF5E00").opacity(email.isEmpty || password.isEmpty ? 0.0 : 0.35), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(ScaleButtonStyle(floatAnimation: buttonFloat))
            .disabled(email.isEmpty || password.isEmpty || isLoading)
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
                    Text(signupStep == 1 ? "Step 1: Admin Account Setup" : (signupStep == 2 ? "Step 2: Restaurant Details" : "Step 3: Choose Pricing Package"))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(hex: "FF9500"))
                }
                Spacer()

                // Dots representing steps
                HStack(spacing: 6) {
                    Circle()
                        .fill(signupStep >= 1 ? Color(hex: "FF9500") : Color.white.opacity(0.3))
                        .frame(width: 8, height: 8)
                    Circle()
                        .fill(signupStep >= 2 ? Color(hex: "FF9500") : Color.white.opacity(0.3))
                        .frame(width: 8, height: 8)
                    Circle()
                        .fill(signupStep >= 3 ? Color(hex: "FF9500") : Color.white.opacity(0.3))
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
                    SecureField("", text: $password, prompt: Text("Min 8 characters").foregroundColor(.white.opacity(0.45)))
                        .font(.system(size: 14))
                        .foregroundColor(.white)
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

            // CTA Button to Step 2 (Primary Orange Gradient Capsule CTA)
            Button(action: validateAndGoToStep2) {
                Text(L.Auth.continueStore.t)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(firstName.isEmpty || lastName.isEmpty || email.isEmpty || password.isEmpty ? .white.opacity(0.6) : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        Group {
                            if firstName.isEmpty || lastName.isEmpty || email.isEmpty || password.isEmpty {
                                Capsule()
                                    .fill(Color.orange.opacity(0.35))
                            } else {
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color(hex: "FF9500"), Color(hex: "FF5E00")],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                            }
                        }
                    )
                    .shadow(color: Color(hex: "FF5E00").opacity(firstName.isEmpty || lastName.isEmpty || email.isEmpty || password.isEmpty ? 0.0 : 0.35), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(ScaleButtonStyle(floatAnimation: buttonFloat))
            .disabled(firstName.isEmpty || lastName.isEmpty || email.isEmpty || password.isEmpty)
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
                        .foregroundColor(Color(hex: "FF9500"))
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

            // Business Type & Currency
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L.Auth.businessType.t)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.85))

                    Picker("Business Type", selection: $businessType) {
                        Text("business_type_restaurant".t).tag("Restaurant")
                        Text("business_type_cafe".t).tag("Cafe")
                        Text("business_type_bar".t).tag("Bar")
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
            }

            // Tax ID / Business Reg No
            VStack(alignment: .leading, spacing: 6) {
                Text(L.Auth.taxId.t)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.85))
                HStack {
                    Image(systemName: "doc.text")
                        .premiumAuthIconStyle(isFocused: focusedField == .taxId)
                    TextField("", text: $taxId, prompt: Text("13 digits ID").foregroundColor(.white.opacity(0.45)))
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .keyboardType(.numberPad)
                        .focused($focusedField, equals: .taxId)
                }
                .premiumAuthInputStyle(isFocused: focusedField == .taxId)
            }

            // Contact Phone
            VStack(alignment: .leading, spacing: 6) {
                Text(L.Auth.contactPhone.t)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.85))
                HStack {
                    Image(systemName: "phone")
                        .premiumAuthIconStyle(isFocused: focusedField == .shopPhone)
                    TextField("", text: $shopPhone, prompt: Text("02-XXX-XXXX").foregroundColor(.white.opacity(0.45)))
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .keyboardType(.phonePad)
                        .focused($focusedField, equals: .shopPhone)
                }
                .premiumAuthInputStyle(isFocused: focusedField == .shopPhone)
            }

            // Action Buttons
            HStack(spacing: 12) {
                // Back Button (Secondary Arrow CTA)
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

                // Submit Button (Primary Orange Gradient Capsule CTA)
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
                    .background(
                        Group {
                            if shopName.isEmpty || taxId.isEmpty || shopPhone.isEmpty {
                                Capsule()
                                    .fill(Color.orange.opacity(0.35))
                            } else {
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color(hex: "FF9500"), Color(hex: "FF5E00")],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                            }
                        }
                    )
                    .foregroundColor(shopName.isEmpty || taxId.isEmpty || shopPhone.isEmpty ? .white.opacity(0.6) : .white)
                    .shadow(color: Color(hex: "FF5E00").opacity(shopName.isEmpty || taxId.isEmpty || shopPhone.isEmpty ? 0.0 : 0.35), radius: 8, x: 0, y: 4)
                }
                .buttonStyle(ScaleButtonStyle(floatAnimation: buttonFloat))
                .disabled(shopName.isEmpty || taxId.isEmpty || shopPhone.isEmpty || isLoading)
            }
            .padding(.top, 6)
        }
    }

    @ViewBuilder
    private var pricingSelectionStep: some View {
        VStack(spacing: 16) {
            // Billing Cycle Toggle (Monthly vs Annual)
            HStack {
                Text("รายเดือน")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isAnnualBilling ? .white.opacity(0.6) : .white)

                Toggle("", isOn: $isAnnualBilling)
                    .toggleStyle(SwitchToggleStyle(tint: Color(hex: "FF9500")))
                    .labelsHidden()
                    .padding(.horizontal, 4)

                Text("รายปี (ประหยัด 20%)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isAnnualBilling ? .white : .white.opacity(0.6))
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)

            // Plan Cards
            VStack(spacing: 10) {
                // Plan 1: Offline Perpetual
                planCard(
                    id: "offline_perpetual",
                    title: "ออฟไลน์ ซื้อขาด",
                    subtitle: "ใช้งาน 1 เครื่องตลอดชีพ ไม่มีรายเดือน",
                    price: "฿9,900",
                    priceLabel: "จ่ายครั้งเดียว",
                    features: ["ใช้งานถาวรระดับเครื่องแม่", "ไม่ต้องใช้อินเทอร์เน็ต", "สำรองข้อมูลแบบ Manual", "จำกัดเฉพาะฟีเจอร์ปัจจุบัน"],
                    color: Color(hex: "6366F1")
                )

                // Plan 2: Offline Subscription
                planCard(
                    id: "offline_subscription",
                    title: isAnnualBilling ? "ออฟไลน์ รายปี" : "ออฟไลน์ รายเดือน",
                    subtitle: "ใช้งาน 1 เครื่อง พร้อมอัปเดตฟรีตลอดสัญญา",
                    price: isAnnualBilling ? "฿2,990" : "฿290",
                    priceLabel: isAnnualBilling ? "/ปี" : "/เดือน",
                    features: ["ใช้งานออฟไลน์ 1 เครื่องแม่", "อัปเดตฟีเจอร์ใหม่ฟรีในสัญญา", "แก้ไขสิทธิ์ / พนักงาน", "บริการความช่วยเหลือ 24/7"],
                    color: .appTeal
                )

                // Plan 3: Online Cloud Subscription
                planCard(
                    id: "online_subscription",
                    title: isAnnualBilling ? "ออนไลน์ รายปี" : "ออนไลน์ รายเดือน",
                    subtitle: "ซิงค์หลายเครื่อง คลาวด์แดชบอร์ด ออเดอร์ QR",
                    price: isAnnualBilling ? "฿11,990" : "฿1,190",
                    priceLabel: isAnnualBilling ? "/ปี" : "/เดือน",
                    features: ["ซิงค์ข้อมูลระหว่างหลาย iPad/iPhone", "รับออเดอร์ QR Code จากลูกค้า", "สำรองข้อมูลอัตโนมัติบน Cloud", "สถิติวิเคราะห์ยอดขายแบบ Real-time"],
                    color: Color(hex: "FF9500")
                )
            }

            // Continue button
            Button(action: handleSelectPlan) {
                HStack {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .padding(.trailing, 8)
                    }
                    Text("เริ่มต้นใช้งานด้วยแพ็กเกจนี้")
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
            .disabled(isLoading)
            .padding(.top, 8)
        }
    }

    private func planCard(
        id: String,
        title: String,
        subtitle: String,
        price: String,
        priceLabel: String,
        features: [String],
        color: Color
    ) -> some View {
        let isSelected = selectedPlanId == id
        return Button(action: {
            triggerHapticFeedback(.light)
            selectedPlanId = id
        }) {
            VStack(alignment: .leading, spacing: 6) {
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

                // Mini features
                HStack(spacing: 12) {
                    ForEach(features.prefix(2), id: \.self) { feat in
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 8))
                                .foregroundColor(color)
                            Text(feat)
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.85))
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
        let cleanPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            do {
                // บังคับ Online ก่อนทุกครั้ง — await ต้องอยู่ใน Task {} เท่านั้น
                guard await NetworkManager.shared.isConnected() else {
                    await MainActor.run {
                        self.isLoading = false
                        self.triggerNotificationFeedback(.error)
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
                    triggerNotificationFeedback(.success)
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
                    triggerNotificationFeedback(.error)
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func validateAndGoToStep2() {
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

    private func handleSignUp() {
        errorMessage = ""
        isLoading = true
        triggerHapticFeedback(.medium)

        Task {
            do {
                // บังคับ Online สำหรับ Sign Up — ต้องสร้างบัญชีบน server
                guard await NetworkManager.shared.isConnected() else {
                    await MainActor.run {
                        isLoading = false
                        triggerNotificationFeedback(.error)
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
                    triggerNotificationFeedback(.success)
                    seedNewMerchantData(merchantId: newMerchantUUID)
                    activeMerchantId = newMerchantUUID.uuidString.lowercased()
                    loggedInEmail = email
                    loggedInName = "\(firstName) \(lastName)"
                    withAnimation {
                        signupStep = 3
                    }
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    triggerNotificationFeedback(.error)
                    errorMessage = error.localizedDescription
                }
            }
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
                let status = "active"
                let expiry: Double? = {
                    if tier == "offline_perpetual" {
                        return Date.distantFuture.timeIntervalSince1970
                    } else {
                        let days = isAnnualBilling ? 365 : 30
                        return Date().addingTimeInterval(TimeInterval(days * 24 * 60 * 60)).timeIntervalSince1970
                    }
                }()

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
                let isOfflinePlan = (tier == "offline_perpetual" || tier == "offline_subscription")
                UserDefaults.standard.set(isOfflinePlan, forKey: "offline_sync_mode")

                await MainActor.run {
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
        let seedEmp1Id  = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let seedEmp2Id  = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
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
        modelContext.saveWithLogging(label: #function)
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
                                colors: [Color(hex: "FF9500").opacity(0.35), Color.clear],
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
                            Color(hex: "FF9500").opacity(isActive ? 0.08 : 0.02)
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
                    .stroke(isFocused ? Color(hex: "FF9500") : Color.white.opacity(0.35), lineWidth: isFocused ? 1.5 : 1)
            )
            .scaleEffect(isFocused ? 1.015 : 1.0)
            .shadow(color: isFocused ? Color(hex: "FF9500").opacity(0.2) : Color.black.opacity(0.0), radius: isFocused ? 8 : 0, x: 0, y: isFocused ? 3 : 0)
    }
}

// MARK: - Premium Auth Icon Modifier
struct PremiumAuthIconModifier: ViewModifier {
    var isFocused: Bool
    var activeColor: Color = Color(hex: "FF9500")

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
        .modelContainer(for: [RestaurantTable.self, Category.self, MenuItem.self, Role.self], inMemory: true)
}

// MARK: - Extensions for Password Reset Modal
extension MerchantAuthView {
    private func triggerHapticFeedback(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
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
                    .foregroundColor(Color(hex: "FF9500"))

                Text(L.Auth.resetTitle.t)
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundColor(.primary)

                Text(L.Auth.resetDesc.t)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color.primary.opacity(0.7))
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

                Button(action: handleResetPassword) {
                    if isSendingReset {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Capsule().fill(Color(hex: "FF9500")))
                    } else {
                        Text(L.Auth.sendResetBtn.t)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                Group {
                                    if resetEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        Capsule()
                                            .fill(Color.orange.opacity(0.4))
                                    } else {
                                        Capsule()
                                            .fill(
                                                LinearGradient(
                                                    colors: [Color(hex: "FF9500"), Color(hex: "FF5E00")],
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                )
                                            )
                                    }
                                }
                            )
                            .shadow(color: Color(hex: "FF5E00").opacity(resetEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.0 : 0.3), radius: 8, x: 0, y: 4)
                    }
                }
                .buttonStyle(ScaleButtonStyle(floatAnimation: buttonFloat))
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
        triggerHapticFeedback(.medium)

        Task {
            do {
                try await AuthService.shared.resetPassword(email: cleanResetEmail)
                await MainActor.run {
                    isSendingReset = false
                    triggerNotificationFeedback(.success)
                    resetSuccessMessage = String(format: "auth_reset_success_template".t, cleanResetEmail)
                }
            } catch {
                await MainActor.run {
                    isSendingReset = false
                    triggerNotificationFeedback(.error)
                    resetSuccessMessage = "auth_reset_failed".t
                }
            }
        }
    }
}
