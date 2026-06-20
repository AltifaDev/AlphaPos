import SwiftUI
import SwiftData

struct ManagerPINVerificationSheet: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var lm: LocalizationManager
    @Query private var users: [User]
    
    @Binding var isPresented: Bool
    var onSuccess: () -> Void
    var onDismiss: (() -> Void)? = nil
    // REMOVED: developer_mode_enabled bypass — tampered UserDefaults could bypass manager PIN
    
    @State private var enteredPin = ""
    @State private var errorMessage = ""
    @State private var attempts = 0
    
    private let pinLength = 4
    
    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Top Drawer Handle Indicator
                Capsule()
                    .fill(Color.textSecondary.opacity(0.3))
                    .frame(width: 36, height: 4)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                
                // Compact Horizontal Header
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.appAccent.opacity(0.12))
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.appAccent)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("manager_auth_title".t)
                            .font(.headline)
                            .fontWeight(.black)
                            .foregroundColor(.textPrimary)
                        
                        Text("manager_auth_desc".t)
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
                
                Divider()
                    .background(Color.appDivider)
                    .padding(.horizontal, 24)
                
                Spacer()
                
                // Centered PIN Pad & Dots container
                VStack(spacing: 24) {
                    // PIN Entry Dots Indicators
                    HStack(spacing: 24) {
                        ForEach(0..<pinLength, id: \.self) { index in
                            Circle()
                                .fill(index < enteredPin.count ? Color.appAccent : Color.textTertiary.opacity(0.2))
                                .frame(width: 16, height: 16)
                                .overlay(
                                    Circle()
                                        .stroke(index < enteredPin.count ? Color.appAccent : Color.textTertiary.opacity(0.4), lineWidth: 1.5)
                                        .scaleEffect(index < enteredPin.count ? 1.15 : 1.0)
                                )
                                .animation(.spring(response: 0.18, dampingFraction: 0.65), value: enteredPin.count)
                        }
                    }
                    .modifier(ShakeEffect(animatableData: CGFloat(attempts)))
                    
                    // Error Message Display (Fixed height to prevent vertical layout shifts)
                    Text(errorMessage.isEmpty ? " " : errorMessage)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.appRose)
                        .frame(height: 16)
                    
                    // Compact Grid-based Numeric Keypad
                    keypadGrid
                }
                .frame(maxWidth: 320)
                
                Spacer()
            }
            .padding(.horizontal)
        }
        .apColorScheme()
        .presentationDetents([.fraction(0.80)]) // Increased detent to prevent vertical clipping on landscape iPad
        .presentationDragIndicator(.hidden)
        .onDisappear {
            onDismiss?()
        }
    }
    
    // MARK: - Keypad Grid Layout
    
    private var keypadGrid: some View {
        let keys = [
            ["1", "2", "3"],
            ["4", "5", "6"],
            ["7", "8", "9"],
            ["C", "0", "⌫"]
        ]
        
        return VStack(spacing: 12) {
            ForEach(keys, id: \.self) { row in
                HStack(spacing: 28) {
                    ForEach(row, id: \.self) { key in
                        Button(action: { handleKeyTap(key) }) {
                            if isActionKey(key) {
                                if key == "⌫" {
                                    Image(systemName: "delete.left.fill")
                                        .font(.system(size: 22))
                                        .foregroundColor(.textSecondary)
                                        .frame(width: 72, height: 72)
                                } else {
                                    Text(key)
                                        .font(.system(size: 20, weight: .medium))
                                        .foregroundColor(.textSecondary)
                                        .frame(width: 72, height: 72)
                                }
                            } else {
                                Text(key)
                                    .font(.system(size: 26, weight: .regular))
                                    .foregroundColor(.textPrimary)
                                    .frame(width: 72, height: 72)
                                    .background(
                                        Circle()
                                            .fill(Color.appSurfaceHigh)
                                    )
                                    .overlay(
                                        Circle()
                                            .stroke(Color.appBorderSubtle, lineWidth: 1)
                                    )
                            }
                        }
                        .buttonStyle(ManagerKeypadButtonStyle())
                    }
                }
            }
        }
    }
    
    private func isActionKey(_ key: String) -> Bool {
        return key == "C" || key == "⌫"
    }
    
    // MARK: - Keypad Tap Action
    
    private func handleKeyTap(_ key: String) {
        APHaptic.trigger()
        errorMessage = ""
        
        if key == "C" {
            enteredPin = ""
        } else if key == "⌫" {
            if !enteredPin.isEmpty {
                enteredPin.removeLast()
            }
        } else {
            if enteredPin.count < pinLength {
                enteredPin.append(key)
                if enteredPin.count == pinLength {
                    // Deliberate delay to allow dot scale animation to play out
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        verifyPIN()
                    }
                }
            }
        }
    }
    
    // MARK: - Verification Logic
    
    private func verifyPIN() {
        let hashedEntered = SecurityHelper.sha256(enteredPin)
        
        let matches = users.filter { user in
            guard PermissionService.can(.managerOverride, role: user.role) else { return false }
            
            if let dbPin = user.pinCodeHash {
                return SecurityHelper.verifyPIN(enteredPin, against: dbPin) || SecurityHelper.constantTimeCompare(dbPin, hashedEntered)
            }
            return false
        }
        
        // Developer PIN bypass removed — never allow hardcoded PIN to bypass manager verification
        if !matches.isEmpty {
            isPresented = false
            onSuccess()
        } else {
            // Trigger failure shake animation and shake sound
            enteredPin = ""
            withAnimation(.default) {
                attempts += 1
                errorMessage = "manager_auth_error_invalid".t
            }
        }
    }
}

// MARK: - Custom Keypad Button Style

struct ManagerKeypadButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Shake Geometry Effect

struct ShakeEffect: GeometryEffect {
    var amount: CGFloat = 8
    var shakesPerUnit = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX:
            amount * sin(animatableData * .pi * CGFloat(shakesPerUnit)),
            y: 0))
    }
}
