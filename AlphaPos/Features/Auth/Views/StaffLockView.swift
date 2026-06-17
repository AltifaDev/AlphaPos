import SwiftData
import SwiftUI

struct StaffLockView: View {
    @Query(sort: \Employee.firstName) private var employees: [Employee]
    @AppStorage("logged_in_name") private var storeDisplayName = "AlphaPos Store"
    @AppStorage("passcode_max_attempts") private var maxAttempts = 5
    @AppStorage("passcode_lockout_minutes") private var lockoutMinutes = 5

    let onUnlock: (Employee) -> Void
    let onUseStoreAccount: () -> Void

    @State private var selectedEmployee: Employee?
    @State private var passcode = ""
    @State private var errorMessage = ""
    @State private var attempts = 0
    @State private var lockedUntil: Date?

    @State private var isShowingPasscode = false
    @State private var shakeAttempts = 0
    @Namespace private var animationNamespace

    private let passcodeLength = 4
    private let keypad = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "C", "0", "⌫"]

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            ambientBackground
            
            Group {
                if !isShowingPasscode {
                    profileSelectionView
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.95)),
                            removal: .opacity.combined(with: .scale(scale: 1.05))
                        ))
                } else {
                    passcodeEntryView
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 1.05)),
                            removal: .opacity.combined(with: .scale(scale: 0.95))
                        ))
                }
            }
        }
        .apColorScheme()
        .onAppear {
            selectedEmployee = nil
            passcode = ""
            errorMessage = ""
            isShowingPasscode = false
        }
    }

    private var activeEmployees: [Employee] {
        employees.filter { $0.resignedAt == nil && ($0.user?.isActive ?? true) }
    }

    private var isLockedOut: Bool {
        if let lockedUntil, lockedUntil > Date() { return true }
        return false
    }

    // MARK: - Helpers

    private func employeeDisplayName(_ employee: Employee) -> String {
        let name = "\(employee.firstName) \(employee.lastName)".trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? employee.user?.username ?? "Staff" : name
    }

    private func employeeInitials(_ employee: Employee) -> String {
        let name = employeeDisplayName(employee)
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return letters.isEmpty ? "S" : String(letters).uppercased()
    }

    struct ProfileTheme {
        let colors: [Color]
        let iconName: String
    }

    func themeForEmployee(_ employee: Employee) -> ProfileTheme {
        let role = employee.user?.role?.name.lowercased() ?? ""
        if role.contains("owner") || role.contains("เจ้าของ") {
            return ProfileTheme(
                colors: [Color(hex: "8A2387"), Color(hex: "E94057"), Color(hex: "F27121")],
                iconName: "crown.fill"
            )
        } else if role.contains("admin") || role.contains("แอดมิน") {
            return ProfileTheme(
                colors: [Color(hex: "00B4DB"), Color(hex: "0083B0")],
                iconName: "shield.fill"
            )
        } else if role.contains("manager") || role.contains("ผู้จัดการ") || role.contains("store manager") {
            return ProfileTheme(
                colors: [Color(hex: "11998E"), Color(hex: "38EF7D")],
                iconName: "briefcase.fill"
            )
        } else if role.contains("cashier") || role.contains("แคชเชียร์") {
            return ProfileTheme(
                colors: [Color(hex: "FF416C"), Color(hex: "FF4B2B")],
                iconName: "cart.fill"
            )
        } else if role.contains("waitstaff") || role.contains("พนักงานเสิร์ฟ") {
            return ProfileTheme(
                colors: [Color(hex: "F7971E"), Color(hex: "FFD200")],
                iconName: "tray.fill"
            )
        } else {
            return ProfileTheme(
                colors: [Color(hex: "F857A6"), Color(hex: "FF5858")],
                iconName: "person.fill"
            )
        }
    }

    // MARK: - Subviews

    private var ambientBackground: some View {
        GeometryReader { geo in
            ZStack {
                Circle()
                    .fill(Color(hex: "2D71F8").opacity(0.12))
                    .frame(width: max(geo.size.width, geo.size.height) * 0.5)
                    .blur(radius: 120)
                    .offset(x: -geo.size.width * 0.2, y: -geo.size.height * 0.2)
                
                Circle()
                    .fill(Color(hex: "FF416C").opacity(0.08))
                    .frame(width: max(geo.size.width, geo.size.height) * 0.45)
                    .blur(radius: 120)
                    .offset(x: geo.size.width * 0.7, y: geo.size.height * 0.6)
            }
        }
        .ignoresSafeArea()
    }

    private var profileSelectionView: some View {
        VStack(spacing: 40) {
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(APGradient.accent)
                            .frame(width: 44, height: 44)
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 22, weight: .black))
                            .foregroundColor(.white)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("AlphaPos")
                            .font(.title3.weight(.black))
                            .foregroundColor(.textPrimary)
                        Text(storeDisplayName)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.textSecondary)
                    }
                }
                .padding(.bottom, 12)

                Text("staff_lock_title".t)
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundColor(.textPrimary)
                    .multilineTextAlignment(.center)

                Text("staff_lock_desc".t)
                    .font(.subheadline)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 40)

            if activeEmployees.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "person.crop.circle.badge.exclamationmark")
                        .font(.system(size: 54))
                        .foregroundColor(.appRose)
                    Text("No staff profiles are available on this device.")
                        .font(.headline)
                        .foregroundColor(.textPrimary)
                    Text("Use the store account to finish staff setup.")
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)
                }
                .padding(32)
                .apCard()
                .frame(maxWidth: 450)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 24) {
                        let columns = [
                            GridItem(.adaptive(minimum: 140, maximum: 160), spacing: 28)
                        ]
                        
                        LazyVGrid(columns: columns, spacing: 32) {
                            ForEach(activeEmployees) { employee in
                                ProfileGridButton(
                                    employee: employee,
                                    isSelected: selectedEmployee?.id == employee.id,
                                    action: {
                                        selectedEmployee = employee
                                        passcode = ""
                                        errorMessage = ""
                                        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                                            isShowingPasscode = true
                                        }
                                    },
                                    theme: themeForEmployee(employee),
                                    initials: employeeInitials(employee),
                                    displayName: employeeDisplayName(employee),
                                    namespace: animationNamespace
                                )
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                    .padding(.vertical, 8)
                }
                .frame(maxWidth: 760)
            }

            Spacer()

            VStack(spacing: 16) {
                if let lockedUntil, lockedUntil > Date() {
                    Label("Too many attempts. Try again at \(lockedUntil.formatted(date: .omitted, time: .shortened)).", systemImage: "clock.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.appRose)
                }

                Button {
                    APHaptic.trigger()
                    onUseStoreAccount()
                } label: {
                    Label("use_store_account_btn".t, systemImage: "person.badge.key.fill")
                        .font(.footnote.weight(.bold))
                        .foregroundColor(.appAccent)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 30)
            }
        }
        .padding(.horizontal, 20)
    }

    private var passcodeEntryView: some View {
        VStack(spacing: 32) {
            if let employee = selectedEmployee {
                let theme = themeForEmployee(employee)
                let initials = employeeInitials(employee)
                let displayName = employeeDisplayName(employee)
                let roleName = employee.user?.role?.name ?? "Staff"
                
                VStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(LinearGradient(colors: theme.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 80, height: 80)
                            .matchedGeometryEffect(id: employee.id, in: animationNamespace)
                            .shadow(color: theme.colors[0].opacity(0.3), radius: 8, x: 0, y: 4)
                        
                        VStack(spacing: 4) {
                            Text(initials)
                                .font(.system(size: 24, weight: .black, design: .rounded))
                                .foregroundColor(.white)
                            
                            Image(systemName: theme.iconName)
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.75))
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    
                    VStack(spacing: 4) {
                        Text(displayName)
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundColor(.textPrimary)
                            .lineLimit(1)
                        
                        Text(roleName)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.textSecondary)
                            .lineLimit(1)
                    }
                }
                .padding(.top, 20)
                
                HStack(spacing: 16) {
                    ForEach(0..<passcodeLength, id: \.self) { index in
                        Circle()
                            .fill(index < passcode.count ? Color.appAccent : Color.appSurfaceHigh)
                            .frame(width: 16, height: 16)
                            .scaleEffect(index < passcode.count ? 1.2 : 1.0)
                            .overlay(
                                Circle().stroke(Color.appBorderSubtle, lineWidth: 1)
                            )
                            .animation(.spring(response: 0.15, dampingFraction: 0.6), value: passcode.count)
                    }
                }
                .modifier(Shake(animatableData: CGFloat(shakeAttempts)))
                .padding(.vertical, 8)
                
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.caption.weight(.bold))
                        .foregroundColor(.appRose)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .transition(.opacity.combined(with: .scale))
                }
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 20), count: 3), spacing: 16) {
                    ForEach(keypad, id: \.self) { key in
                        KeypadButton(key: key) {
                            handleKey(key)
                        }
                        .disabled(isLockedOut)
                    }
                }
                .frame(maxWidth: 320)
                
                Button {
                    APHaptic.trigger()
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                        isShowingPasscode = false
                    }
                    passcode = ""
                    errorMessage = ""
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                        if !isShowingPasscode {
                            selectedEmployee = nil
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.left.circle.fill")
                        Text(LocalizationManager.shared.currentLanguage == .thai ? "เปลี่ยนโปรไฟล์พนักงาน" : "Switch Profile")
                    }
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.appAccent)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 20)
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.appSurface.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.appBorderSubtle, lineWidth: 1)
                )
        )
        .shadow(color: APShadow.card.color, radius: APShadow.card.radius, x: APShadow.card.x, y: APShadow.card.y)
        .frame(maxWidth: 440)
    }

    // MARK: - Actions

    private func handleKey(_ key: String) {
        guard !isLockedOut else { return }
        APHaptic.trigger()
        errorMessage = ""

        switch key {
        case "C":
            passcode = ""
        case "⌫":
            if !passcode.isEmpty { passcode.removeLast() }
        default:
            guard passcode.count < passcodeLength else { return }
            passcode.append(key)
            if passcode.count == passcodeLength {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    verifyPasscode()
                }
            }
        }
    }

    private func verifyPasscode() {
        guard let employee = selectedEmployee,
              let storedHash = employee.user?.pinCodeHash,
              SecurityHelper.verifyPIN(passcode, against: storedHash) else {
            withAnimation(.default) {
                shakeAttempts += 1
            }
            attempts += 1
            passcode = ""
            if attempts >= maxAttempts {
                lockedUntil = Date().addingTimeInterval(TimeInterval(lockoutMinutes * 60))
                errorMessage = "Too many failed attempts. This register is temporarily locked."
            } else {
                errorMessage = attempts >= 3 ? "Passcode failed. Ask a manager to verify access." : "Invalid passcode"
            }
            return
        }

        attempts = 0
        lockedUntil = nil
        passcode = ""
        onUnlock(employee)
    }
}

// MARK: - Helper Views

private struct ProfileGridButton: View {
    let employee: Employee
    let isSelected: Bool
    let action: () -> Void
    let theme: StaffLockView.ProfileTheme
    let initials: String
    let displayName: String
    let namespace: Namespace.ID
    
    @State private var isHovered = false
    @State private var isPressed = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(LinearGradient(colors: theme.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 125, height: 125)
                        .matchedGeometryEffect(id: employee.id, in: namespace)
                        .shadow(color: theme.colors[0].opacity(0.35), radius: isHovered ? 12 : 6, x: 0, y: isHovered ? 6 : 3)
                    
                    VStack(spacing: 8) {
                        Text(initials)
                            .font(.system(size: 38, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 2)
                        
                        Image(systemName: theme.iconName)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white.opacity(0.75))
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(isHovered ? 0.35 : 0.15), lineWidth: isHovered ? 2.5 : 1)
                )
                .scaleEffect(isPressed ? 0.92 : (isHovered ? 1.05 : 1.0))
                
                VStack(spacing: 3) {
                    Text(displayName)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                    
                    Text(employee.user?.role?.name ?? "Staff")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.textSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: 135)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                isHovered = hovering
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

private struct KeypadButton: View {
    let key: String
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: action) {
            Text(key)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(key == "C" || key == "⌫" ? .textSecondary : .textPrimary)
                .frame(width: 70, height: 70)
                .background(
                    Circle()
                        .fill(isPressed ? Color.appSurfaceHigh.opacity(0.8) : Color.appSurfaceHigh.opacity(0.3))
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                )
                .scaleEffect(isPressed ? 0.90 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - Shake Animation Helper

struct Shake: GeometryEffect {
    var amount: CGFloat = 8
    var shakesPerUnit = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX:
            amount * sin(animatableData * .pi * CGFloat(shakesPerUnit)),
            y: 0))
    }
}
