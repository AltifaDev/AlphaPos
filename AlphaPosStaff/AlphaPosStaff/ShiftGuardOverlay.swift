import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - ShiftGuardOverlay
// ─────────────────────────────────────────────────────────────────────────────
// Presented as .fullScreenCover when the staff member has NOT clocked in.
// Prevents placing orders, adding food, or any POS action without an active shift.
//
// iOS HIG compliance:
//  • .interactiveDismissDisabled(true) — cannot be dismissed accidentally
//  • Button height: 50pt (standard iOS primary action)
//  • Animated lock icon with pulse + float
//  • Confirmation alert before "ยกเลิก" if clock-in is mandatory

struct ShiftGuardOverlay: View {
    @AppStorage("app_language") private var appLanguage = "en"
    @Environment(\.dismiss) private var dismiss
    
    /// Called when user wants to navigate to the Clock In tab
    var onGoToClockIn: (() -> Void)? = nil
    
    @State private var isAnimating = false
    @State private var iconFloat = false
    @State private var showContent = false
    
    // Design tokens
    private let royalBlue = Color(hex: "2D71F8")
    private let coralRed  = Color(hex: "FC4A4A")
    private let elfGreen  = Color(hex: "1C8370")
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [Color(hex: "F8F9FC"), Color(hex: "EEF1F7")],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    Spacer()
                    
                    // MARK: Animated Icon
                    lockIcon
                        .padding(.bottom, 24)
                    
                    // MARK: Title & Subtitle
                    VStack(spacing: 10) {
                        Text("shift_required_title".localized(for: appLanguage))
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(Color(hex: "1A1D23"))
                        
                        Text("shift_required_subtitle".localized(for: appLanguage))
                            .font(.subheadline)
                            .foregroundColor(Color(hex: "5A6478"))
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .padding(.horizontal, 40)
                    }
                    .padding(.bottom, 36)
                    
                    // MARK: Action Card
                    actionCard
                        .padding(.horizontal, 28)
                        .opacity(showContent ? 1 : 0)
                        .offset(y: showContent ? 0 : 16)
                    
                    Spacer()
                    Spacer()
                }
            }
            .navigationTitle("shift_guard_nav_title".localized(for: appLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(Color(hex: "8A94A6"))
                    }
                }
            }
            .interactiveDismissDisabled(true)
            .onAppear { startAnimations() }
        }
    }
    
    // MARK: - Lock Icon
    
    private var lockIcon: some View {
        ZStack {
            // Pulse rings
            Circle()
                .stroke(coralRed.opacity(0.12), lineWidth: 2)
                .frame(width: 96, height: 96)
                .scaleEffect(isAnimating ? 1.35 : 1.0)
                .opacity(isAnimating ? 0 : 0.5)
            
            Circle()
                .stroke(coralRed.opacity(0.08), lineWidth: 1.5)
                .frame(width: 80, height: 80)
                .scaleEffect(isAnimating ? 1.2 : 1.0)
                .opacity(isAnimating ? 0.2 : 0.4)
            
            // Main circle
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.white, Color(hex: "F5F6FA")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 68, height: 68)
                    .shadow(color: coralRed.opacity(0.12), radius: 12, y: 4)
                    .overlay(
                        Circle()
                            .stroke(Color(hex: "E2E5EB"), lineWidth: 1)
                    )
                
                Image(systemName: "clock.badge.xmark")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [coralRed, coralRed.opacity(0.7)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .offset(y: iconFloat ? -2 : 2)
            }
        }
        .frame(height: 100)
    }
    
    // MARK: - Action Card
    
    private var actionCard: some View {
        VStack(spacing: 20) {
            // Info row
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: "FF8C00"))
                
                Text("shift_guard_info_text".localized(for: appLanguage))
                    .font(.caption)
                    .foregroundColor(Color(hex: "5A6478"))
                    .lineSpacing(3)
            }
            .padding(12)
            .background(Color(hex: "FFF8F0"))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(hex: "FFE0B2"), lineWidth: 1)
            )
            
            // Clock In Button — Primary CTA (50pt iOS HIG)
            Button(action: {
                onGoToClockIn?()
                dismiss()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "door.left.hand.open")
                        .font(.subheadline.weight(.semibold))
                    Text("go_to_clock_in_btn".localized(for: appLanguage))
                        .font(.subheadline)
                        .fontWeight(.bold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    LinearGradient(
                        colors: [elfGreen, elfGreen.opacity(0.85)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(12)
                .shadow(color: elfGreen.opacity(0.25), radius: 8, y: 4)
            }
            .buttonStyle(.plain)
            
            // Back Button — Secondary (50pt)
            Button(action: { dismiss() }) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.caption.weight(.semibold))
                    Text("go_back_btn".localized(for: appLanguage))
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .foregroundColor(Color(hex: "5A6478"))
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color(hex: "F0F2F5"))
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .background(.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.06), radius: 16, y: 6)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(hex: "E2E5EB"), lineWidth: 1)
        )
    }
    
    // MARK: - Animations
    
    private func startAnimations() {
        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: false)) {
            isAnimating = true
        }
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            iconFloat = true
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.2)) {
            showContent = true
        }
    }
}
