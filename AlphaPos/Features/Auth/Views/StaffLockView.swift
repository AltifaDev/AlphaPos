import SwiftData
import SwiftUI

// MARK: - StaffLockView
// ─────────────────────────────────────────────────────────────────────────────
// Redesign v2:
//   • Full-screen looping video background (staff_lock_bg.mp4)
//   • Dark glassmorphism overlay — text always legible
//   • Profile cards: larger, frosted glass, cinematic depth
//   • Passcode entry: centered modal card with blur + glow
//   • Smooth spring animations throughout
// ─────────────────────────────────────────────────────────────────────────────

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
    @AppStorage("staff_lockout_until_time") private var lockedUntilTime: Double = 0.0
    private var lockedUntil: Date? {
        get { lockedUntilTime > 0 ? Date(timeIntervalSince1970: lockedUntilTime) : nil }
        set { lockedUntilTime = newValue?.timeIntervalSince1970 ?? 0.0 }
    }
    @State private var isShowingPasscode = false
    @State private var isOwnerPasscodeEntry = false
    @State private var shakeAttempts = 0
    @Namespace private var animationNamespace

    private let passcodeLength = 4
    private let keypad = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "C", "0", "⌫"]

    // MARK: - Body

    var body: some View {
        ZStack {
            // ── Layer 1: Video Background ──────────────────────────────────
            LoopingVideoPlayer(videoName: "staff_lock_bg", videoExtension: "mp4")
                .ignoresSafeArea()

            // ── Layer 2: Scrim — dark gradient for legibility ──────────────
            LinearGradient(
                stops: [
                    .init(color: Color.black.opacity(0.55), location: 0),
                    .init(color: Color.black.opacity(0.30), location: 0.4),
                    .init(color: Color.black.opacity(0.65), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // ── Layer 3: Content ───────────────────────────────────────────
            Group {
                if !isShowingPasscode {
                    profileSelectionView
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.96)),
                            removal:   .opacity.combined(with: .scale(scale: 1.04))
                        ))
                } else {
                    passcodeEntryView
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 1.04)),
                            removal:   .opacity.combined(with: .scale(scale: 0.96))
                        ))
                }
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.82), value: isShowingPasscode)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            selectedEmployee = nil
            passcode = ""
            errorMessage = ""
            isShowingPasscode = false
            isOwnerPasscodeEntry = false
        }
    }

    // MARK: - Helpers

    private var activeEmployees: [Employee] {
        employees.filter { $0.resignedAt == nil && ($0.user?.isActive ?? true) }
    }

    private var isLockedOut: Bool {
        if let lockedUntil, lockedUntil > Date() { return true }
        return false
    }

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

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Profile Selection View
    // ─────────────────────────────────────────────────────────────────────────

    private var profileSelectionView: some View {
        VStack(spacing: 0) {

            // ── Header ─────────────────────────────────────────────────────
            VStack(spacing: 10) {
                // App badge
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: "2D71F8"), Color(hex: "6E3FFF")],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 48, height: 48)
                            .shadow(color: Color(hex: "2D71F8").opacity(0.5), radius: 12, x: 0, y: 4)
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 24, weight: .black))
                            .foregroundColor(.white)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("AlphaPos")
                            .font(.system(size: 18, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                        Text(storeDisplayName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                .padding(.top, 56)

                Spacer().frame(height: 28)

                Text("staff_lock_title".t)
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 2)
                    .multilineTextAlignment(.center)

                Text("staff_lock_desc".t)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
            }

            Spacer().frame(height: 40)

            // ── Profile Grid ───────────────────────────────────────────────
            if activeEmployees.isEmpty {
                emptyStateView
            } else {
                profileGrid
            }

            Spacer()

            // ── Bottom: Lockout + Store Account ───────────────────────────
            VStack(spacing: 14) {
                if let lockedUntil, lockedUntil > Date() {
                    lockoutBanner(until: lockedUntil)
                }

                Button {
                    APHaptic.trigger()
                    passcode = ""
                    errorMessage = ""
                    isOwnerPasscodeEntry = true
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                        isShowingPasscode = true
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "person.badge.key.fill")
                        Text("use_store_account_btn".t)
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white.opacity(0.75))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
                    )
                }
                .buttonStyle(.plain)
                .padding(.bottom, 36)
            }
        }
        .padding(.horizontal, 24)
    }

    private var profileGrid: some View {
        ScrollView(.vertical, showsIndicators: false) {
            let columns = [GridItem(.adaptive(minimum: 150, maximum: 175), spacing: 20)]
            LazyVGrid(columns: columns, spacing: 22) {
                ForEach(activeEmployees) { employee in
                    GlassProfileButton(
                        theme: themeForEmployee(employee),
                        initials: employeeInitials(employee),
                        displayName: employeeDisplayName(employee),
                        roleName: employee.user?.role?.name ?? "Staff",
                        namespace: animationNamespace,
                        namespaceId: "employee-\(employee.id.uuidString)"
                    ) {
                        selectedEmployee = employee
                        passcode = ""
                        errorMessage = ""
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                            isShowingPasscode = true
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
        }
        .frame(maxWidth: 800)
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 54))
                .foregroundColor(.white.opacity(0.5))
            Text("No staff profiles available")
                .font(.headline)
                .foregroundColor(.white)
            Text("Use the store account to set up staff.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.55))
        }
        .padding(40)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
        .frame(maxWidth: 420)
    }

    private func lockoutBanner(until: Date) -> some View {
        Label(
            "ล็อคชั่วคราว — ลองใหม่ได้เวลา \(until.formatted(date: .omitted, time: .shortened))",
            systemImage: "clock.fill"
        )
        .font(.caption.weight(.semibold))
        .foregroundColor(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.red.opacity(0.35))
                .overlay(Capsule().stroke(Color.red.opacity(0.4), lineWidth: 1))
        )
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Passcode Entry View
    // ─────────────────────────────────────────────────────────────────────────

    private var passcodeEntryView: some View {
        VStack {
            Spacer()

            VStack(spacing: 24) {
                if isOwnerPasscodeEntry || selectedEmployee != nil {
                    let theme: ProfileTheme = isOwnerPasscodeEntry
                        ? ProfileTheme(
                            colors: [Color(hex: "8A2387"), Color(hex: "E94057"), Color(hex: "F27121")],
                            iconName: "crown.fill"
                          )
                        : themeForEmployee(selectedEmployee!)
                    let displayName = isOwnerPasscodeEntry ? storeDisplayName : employeeDisplayName(selectedEmployee!)
                    let roleName = isOwnerPasscodeEntry ? "store_owner".t : (selectedEmployee!.user?.role?.name ?? "Staff")

                    // ── Profile Header ──────────────────────────────────────
                    VStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .frame(width: 88, height: 88)
                                .matchedGeometryEffect(
                                    id: isOwnerPasscodeEntry ? "owner_profile" : "employee-\(selectedEmployee!.id.uuidString)",
                                    in: animationNamespace
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                                        .fill(
                                            LinearGradient(
                                                colors: [Color.white.opacity(0.15), Color.white.opacity(0.05)],
                                                startPoint: .topLeading, endPoint: .bottomTrailing
                                            )
                                        )
                                )
                                .overlay(alignment: .trailing) {
                                    // Vertical tab book spine
                                    VStack(spacing: 1.5) {
                                        RoundedRectangle(cornerRadius: 1)
                                            .fill(Color.white.opacity(0.85))
                                            .frame(width: 5, height: 14)
                                        RoundedRectangle(cornerRadius: 1)
                                            .fill(Color.white.opacity(0.4))
                                            .frame(width: 5, height: 14)
                                        RoundedRectangle(cornerRadius: 1)
                                            .fill(Color.white.opacity(0.25))
                                            .frame(width: 5, height: 14)
                                    }
                                    .padding(.trailing, 5)
                                }
                                .overlay(
                                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                                        .stroke(Color.white.opacity(0.4), lineWidth: 1.0)
                                )
                                .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 5)

                            // iOS Contacts style silhouette
                            ZStack {
                                Circle()
                                    .stroke(Color.white.opacity(0.45), lineWidth: 1.5)
                                    .frame(width: 44, height: 44)

                                Circle()
                                    .fill(
                                        LinearGradient(colors: theme.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                                    )
                                    .frame(width: 14, height: 14)
                                    .offset(y: -4)

                                Circle()
                                    .fill(
                                        LinearGradient(colors: theme.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                                    )
                                    .frame(width: 28, height: 28)
                                    .offset(y: 16)
                            }
                            .frame(width: 44, height: 44)
                            .clipShape(Circle())
                        }

                        VStack(spacing: 3) {
                            Text(displayName)
                                .font(.system(size: 22, weight: .black, design: .rounded))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Text(roleName)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white.opacity(0.55))
                        }
                    }

                    // ── PIN Dots ────────────────────────────────────────────
                    HStack(spacing: 18) {
                        ForEach(0..<passcodeLength, id: \.self) { index in
                            ZStack {
                                Circle()
                                    .stroke(Color.white.opacity(0.25), lineWidth: 1.5)
                                    .frame(width: 18, height: 18)
                                Circle()
                                    .fill(index < passcode.count
                                          ? Color.white
                                          : Color.white.opacity(0.08))
                                    .frame(width: index < passcode.count ? 16 : 14,
                                           height: index < passcode.count ? 16 : 14)
                                    .shadow(color: Color.white.opacity(0.6), radius: index < passcode.count ? 6 : 0)
                            }
                            .animation(.spring(response: 0.15, dampingFraction: 0.6), value: passcode.count)
                        }
                    }
                    .modifier(ShakeEffect(animatableData: CGFloat(shakeAttempts)))

                    // ── Error ───────────────────────────────────────────────
                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.caption.weight(.bold))
                            .foregroundColor(Color(hex: "FF6B6B"))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    // ── Keypad ──────────────────────────────────────────────
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3),
                        spacing: 14
                    ) {
                        ForEach(keypad, id: \.self) { key in
                            GlassKeypadButton(key: key, disabled: isLockedOut) {
                                handleKey(key)
                            }
                        }
                    }
                    .frame(maxWidth: 300)

                    // ── Back button ─────────────────────────────────────────
                    Button {
                        APHaptic.trigger()
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                            isShowingPasscode = false
                        }
                        passcode = ""
                        errorMessage = ""
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            if !isShowingPasscode {
                                selectedEmployee = nil
                                isOwnerPasscodeEntry = false
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.left.circle.fill")
                            Text(LocalizationManager.shared.currentLanguage == .thai
                                 ? "เปลี่ยนโปรไฟล์พนักงาน"
                                 : "Switch Profile")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(32)
            .frame(maxWidth: 400)
            .background(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.35), radius: 30, x: 0, y: 16)
            )

            Spacer()
        }
        .padding(.horizontal, 24)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Actions
    // ─────────────────────────────────────────────────────────────────────────

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
                verifyPasscode()
            }
        }
    }

    private func verifyPasscode() {
        let capturedPasscode = passcode
        Task.detached(priority: .userInitiated) {
            let isOwner = await MainActor.run { isOwnerPasscodeEntry }
            if isOwner {
                if await KeychainManager.shared.verifyOwnerPin(capturedPasscode) {
                    await MainActor.run {
                        attempts = 0; lockedUntilTime = 0.0; passcode = ""
                        onUseStoreAccount()
                    }
                } else {
                    await MainActor.run {
                        withAnimation { shakeAttempts += 1 }
                        attempts += 1; passcode = ""
                        if attempts >= maxAttempts {
                            lockedUntilTime = Date().addingTimeInterval(TimeInterval(lockoutMinutes * 60)).timeIntervalSince1970
                            errorMessage = "ล็อคชั่วคราว — พยายามหลายครั้งเกินไป"
                        } else {
                            errorMessage = LocalizationManager.shared.currentLanguage == .thai
                                ? "รหัส PIN ของเจ้าของร้านไม่ถูกต้อง"
                                : "Incorrect store owner passcode."
                        }
                    }
                }
            } else {
                let (employeeId, storedHash) = await MainActor.run {
                    (selectedEmployee?.id, selectedEmployee?.user?.pinCodeHash)
                }
                let verified = storedHash.map { SecurityHelper.verifyPIN(capturedPasscode, against: $0) } ?? false
                guard let employeeId, verified else {
                    await MainActor.run {
                        withAnimation { shakeAttempts += 1 }
                        attempts += 1; passcode = ""
                        if attempts >= maxAttempts {
                            lockedUntilTime = Date().addingTimeInterval(TimeInterval(lockoutMinutes * 60)).timeIntervalSince1970
                            errorMessage = "ล็อคชั่วคราว — พยายามหลายครั้งเกินไป"
                        } else {
                            errorMessage = attempts >= 3
                                ? "รหัสผ่านผิด — โปรดติดต่อผู้จัดการ"
                                : "รหัสผ่านไม่ถูกต้อง"
                        }
                    }
                    return
                }
                await MainActor.run {
                    guard let employee = employees.first(where: { $0.id == employeeId }) else {
                        passcode = ""; errorMessage = "Staff profile unavailable."
                        return
                    }
                    attempts = 0; lockedUntilTime = 0.0; passcode = ""
                    onUnlock(employee)
                }
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Glass Profile Button
// ─────────────────────────────────────────────────────────────────────────────

private struct GlassProfileButton: View {
    let theme: StaffLockView.ProfileTheme
    let initials: String
    let displayName: String
    let roleName: String
    let namespace: Namespace.ID
    let namespaceId: String
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 14) {
                ZStack {
                    // Transparent Frosted Glass Card
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .frame(width: 110, height: 110)
                        .matchedGeometryEffect(id: namespaceId, in: namespace)
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.15), Color.white.opacity(0.05)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .overlay(alignment: .trailing) {
                            // Vertical tab book spine (like the Contacts app icon)
                            VStack(spacing: 2) {
                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(Color.white.opacity(0.85))
                                    .frame(width: 6, height: 18)

                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(Color.white.opacity(0.4))
                                    .frame(width: 6, height: 18)

                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(Color.white.opacity(0.25))
                                    .frame(width: 6, height: 18)
                            }
                            .padding(.trailing, 6)
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(
                                    Color.white.opacity(0.4),
                                    lineWidth: 1.0
                                )
                        )
                        .shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: 6)

                    // iOS Contacts style silhouette in center
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.45), lineWidth: 2)
                            .frame(width: 52, height: 52)

                        Circle()
                            .fill(
                                LinearGradient(colors: theme.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .frame(width: 17, height: 17)
                            .offset(y: -4)

                        Circle()
                            .fill(
                                LinearGradient(colors: theme.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .frame(width: 32, height: 32)
                            .offset(y: 19)
                    }
                    .frame(width: 52, height: 52)
                    .clipShape(Circle())
                }
                .scaleEffect(isPressed ? 0.93 : 1.0)
                .animation(.spring(response: 0.25, dampingFraction: 0.65), value: isPressed)

                VStack(spacing: 3) {
                    Text(displayName)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(roleName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in withAnimation { isPressed = true } }
                .onEnded   { _ in withAnimation { isPressed = false } }
        )
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Glass Keypad Button
// ─────────────────────────────────────────────────────────────────────────────

private struct GlassKeypadButton: View {
    let key: String
    let disabled: Bool
    let action: () -> Void

    @State private var isPressed = false

    var isSpecial: Bool { key == "C" || key == "⌫" }

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSpecial
                          ? Color.white.opacity(isPressed ? 0.06 : 0.04)
                          : Color.white.opacity(isPressed ? 0.22 : 0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(isSpecial ? 0.06 : 0.14), lineWidth: 1)
                    )

                if isSpecial {
                    Image(systemName: key == "⌫" ? "delete.left" : "xmark")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white.opacity(disabled ? 0.25 : 0.7))
                } else {
                    Text(key)
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(disabled ? 0.25 : 1.0))
                }
            }
            .frame(width: 84, height: 62)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .scaleEffect(isPressed ? 0.92 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in withAnimation { isPressed = true } }
                .onEnded   { _ in withAnimation { isPressed = false } }
        )
    }
}
