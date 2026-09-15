import SwiftUI

/// Mandatory post-activate gate: display name + owner PIN (create + confirm).
/// Blocks dashboard until `KeychainManager.isOwnerPinConfigured()`.
struct OwnerSetupView: View {
    @EnvironmentObject private var lm: LocalizationManager

    var initialDisplayName: String = ""
    /// When true, after PIN show a one-time soft MFA prompt (skippable).
    var showMfaSoftPrompt: Bool = true
    let onFinished: (_ displayName: String, _ skippedMfa: Bool) -> Void

    @State private var displayName: String = ""
    @State private var pin = ""
    @State private var pendingPin: String? = nil
    @State private var isConfirming = false
    @State private var errorMessage = ""
    @State private var shakeAttempts = 0
    @State private var phase: Phase = .profileAndPin
    @State private var savedDisplayName = ""

    private enum Phase {
        case profileAndPin
        case mfaSoft
    }

    private let pinLength = 4
    private let keypad = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "C", "0", "⌫"]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "0B1B3A"), Color(hex: "12284F"), Color(hex: "0B1B3A")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Image(systemName: phase == .mfaSoft ? "lock.shield.fill" : "person.badge.key.fill")
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundColor(Color(hex: "2D71F8"))
                    Text(phase == .mfaSoft ? "onboarding_mfa_title".t : "onboarding_owner_setup_title".t)
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    Text(phase == .mfaSoft ? "onboarding_mfa_subtitle".t : "onboarding_owner_setup_subtitle".t)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .padding(.top, 40)

                if phase == .profileAndPin {
                    profileAndPinContent
                } else {
                    mfaSoftContent
                }

                Spacer(minLength: 12)
            }
            .padding(.horizontal, 28)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if displayName.isEmpty {
                displayName = initialDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }

    private var profileAndPinContent: some View {
        VStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("onboarding_display_name_label".t)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.85))
                TextField("", text: $displayName, prompt: Text("Store Owner").foregroundColor(.white.opacity(0.4)))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )
            }

            Text(isConfirming ? "owner_pin_confirm_prompt".t : "owner_pin_create_prompt".t)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.75))

            HStack(spacing: 16) {
                ForEach(0..<pinLength, id: \.self) { index in
                    Circle()
                        .stroke(Color.white.opacity(0.3), lineWidth: 1.5)
                        .frame(width: 16, height: 16)
                        .overlay(
                            Circle()
                                .fill(index < pin.count ? Color.white : Color.clear)
                                .frame(width: 12, height: 12)
                        )
                }
            }
            .modifier(OwnerSetupShakeEffect(animatableData: CGFloat(shakeAttempts)))

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "FF453A"))
                    .multilineTextAlignment(.center)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                ForEach(keypad, id: \.self) { key in
                    Button {
                        handleKey(key)
                    } label: {
                        Text(key)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.white.opacity(0.1))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 320)
        }
    }

    private var mfaSoftContent: some View {
        VStack(spacing: 16) {
            Text("onboarding_mfa_body".t)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.75))
                .multilineTextAlignment(.center)

            Button {
                onFinished(savedDisplayName, false)
            } label: {
                Text("onboarding_mfa_setup_btn".t)
                    .font(.system(size: 15, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(Color(hex: "2D71F8")))
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)

            Button {
                onFinished(savedDisplayName, true)
            } label: {
                Text("onboarding_mfa_skip_btn".t)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 24)
    }

    private func handleKey(_ key: String) {
        errorMessage = ""
        switch key {
        case "C":
            pin = ""
        case "⌫":
            if !pin.isEmpty { pin.removeLast() }
        default:
            guard pin.count < pinLength else { return }
            pin.append(key)
            if pin.count == pinLength {
                submitPin()
            }
        }
    }

    private func submitPin() {
        let entered = pin
        pin = ""

        if !isConfirming {
            guard KeychainManager.isAcceptableOwnerPin(entered) else {
                withAnimation { shakeAttempts += 1 }
                errorMessage = "owner_pin_weak_error".t
                return
            }
            pendingPin = entered
            isConfirming = true
            return
        }

        guard pendingPin == entered else {
            withAnimation { shakeAttempts += 1 }
            pendingPin = nil
            isConfirming = false
            errorMessage = "owner_pin_mismatch_error".t
            return
        }

        guard KeychainManager.shared.saveOwnerPin(entered) else {
            pendingPin = nil
            isConfirming = false
            errorMessage = "settings_pin_save_failed".t
            return
        }

        UserDefaults.standard.removeObject(forKey: "merchant_owner_pin")
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        savedDisplayName = name.isEmpty ? "Store Owner" : name
        UserDefaults.standard.set(savedDisplayName, forKey: "logged_in_name")

        if showMfaSoftPrompt {
            phase = .mfaSoft
        } else {
            onFinished(savedDisplayName, true)
        }
    }
}

private struct OwnerSetupShakeEffect: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let translation = sin(animatableData * .pi * 2) * 6
        return ProjectionTransform(CGAffineTransform(translationX: translation, y: 0))
    }
}
