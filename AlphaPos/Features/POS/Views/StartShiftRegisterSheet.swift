import SwiftUI
import SwiftData

// MARK: - StartShiftRegisterSheet
// Redesigned: Full-screen cover with dismiss prevention,
// modern animations, and iOS HIG-compliant button sizes.
// Uses AlphaPos Design System tokens throughout.

struct StartShiftRegisterSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var lm: LocalizationManager
    
    @Query(sort: \User.username) private var users: [User]
    
    @State private var openingCashString = "1000"
    @State private var openingNotes = ""
    @State private var isAnimating = false
    @State private var lockBounce = false
    @State private var showForm = false
    @State private var isProcessing = false
    @State private var showConfirmCancel = false
    
    var onComplete: (() -> Void)? = nil
    var onCancel: (() -> Void)? = nil
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Gradient Background
                LinearGradient(
                    colors: [Color.appBackground, Color.appSurface.opacity(0.8)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 0) {
                        // Top spacing
                        Spacer().frame(height: 40)
                        
                        // MARK: - Animated Lock Icon
                        lockIconSection
                            .padding(.bottom, APSpacing.lg)
                        
                        // MARK: - Title & Subtitle
                        titleSection
                            .padding(.bottom, APSpacing.xl)
                        
                        // MARK: - Form Card
                        formCard
                            .padding(.horizontal, 32)
                            .opacity(showForm ? 1 : 0)
                            .offset(y: showForm ? 0 : 20)
                        
                        Spacer().frame(height: 40)
                    }
                }
            }
            .navigationTitle("cash_drawer_shifts_title".t)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: { attemptCancel() }) {
                        Text("cancel_btn".t)
                            .font(.subheadline)
                            .foregroundColor(.textSecondary)
                    }
                }
            }
            .interactiveDismissDisabled(true) // ← CRITICAL: Prevent accidental dismiss
            .alert("confirm_cancel_session_title".t, isPresented: $showConfirmCancel) {
                Button("cancel_btn".t, role: .cancel) { }
                Button("confirm_exit_btn".t, role: .destructive) {
                    onCancel?()
                    dismiss()
                }
            } message: {
                Text("confirm_cancel_session_message".t)
            }
            .onAppear {
                startEntryAnimations()
            }
        }
    }
    
    // MARK: - Lock Icon with Animation
    
    private var lockIconSection: some View {
        ZStack {
            // Outer pulse ring
            Circle()
                .stroke(Color.appRose.opacity(0.15), lineWidth: 2)
                .frame(width: 100, height: 100)
                .scaleEffect(isAnimating ? 1.3 : 1.0)
                .opacity(isAnimating ? 0 : 0.6)
            
            // Middle ring
            Circle()
                .stroke(Color.appRose.opacity(0.1), lineWidth: 1.5)
                .frame(width: 85, height: 85)
                .scaleEffect(isAnimating ? 1.15 : 1.0)
                .opacity(isAnimating ? 0.3 : 0.5)
            
            // Main icon container
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.appSurface, Color.appSurfaceHigh],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 72)
                    .shadow(color: Color.appRose.opacity(0.15), radius: 12, y: 4)
                    .overlay(
                        Circle()
                            .stroke(Color.appBorderSubtle, lineWidth: 1)
                    )
                
                Image(systemName: "lock.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.appRose, Color.appRose.opacity(0.7)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .offset(y: lockBounce ? -2 : 2)
            }
        }
        .frame(height: 110)
    }
    
    // MARK: - Title Section
    
    private var titleSection: some View {
        VStack(spacing: APSpacing.xs) {
            Text("drawer_locked_title".t)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.textPrimary)
            
            Text("drawer_locked_subtitle".t)
                .font(.subheadline)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 40)
        }
    }
    
    // MARK: - Form Card
    
    private var formCard: some View {
        VStack(alignment: .leading, spacing: APSpacing.md) {
            // Section Header
            HStack(spacing: 6) {
                Image(systemName: "play.circle.fill")
                    .font(.caption)
                    .foregroundColor(.appAccent)
                Text("start_shift_header".t)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.appAccent)
                    .tracking(0.5)
            }
            .padding(.bottom, 4)
            
            // Starting Cash Field
            VStack(alignment: .leading, spacing: 6) {
                Text("starting_cash_float_label".t)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.textSecondary)
                
                HStack(spacing: 10) {
                    Text("฿")
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundColor(.textSecondary)
                        .frame(width: 24)
                    
                    TextField("0.00", text: $openingCashString)
                        .font(.title3)
                        .fontWeight(.bold)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.plain)
                        .foregroundColor(.textPrimary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.appSurfaceHigh)
                .cornerRadius(APRadius.md)
                .overlay(
                    RoundedRectangle(cornerRadius: APRadius.md)
                        .stroke(Color.appBorderSubtle, lineWidth: 1)
                )
            }
            
            // Notes Field
            VStack(alignment: .leading, spacing: 6) {
                Text("opening_notes_label".t)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.textSecondary)
                
                TextField("opening_notes_placeholder".t, text: $openingNotes)
                    .font(.subheadline)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.appSurfaceHigh)
                    .cornerRadius(APRadius.md)
                    .textFieldStyle(.plain)
                    .overlay(
                        RoundedRectangle(cornerRadius: APRadius.md)
                            .stroke(Color.appBorderSubtle, lineWidth: 1)
                    )
            }
            
            // Primary Action Button — iOS HIG compliant (height ~50pt)
            Button(action: openRegisterSession) {
                HStack(spacing: 8) {
                    if isProcessing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "lock.open.fill")
                            .font(.subheadline.weight(.semibold))
                    }
                    Text("open_session_btn".t)
                        .font(.subheadline)
                        .fontWeight(.bold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50) // iOS HIG: 44-50pt for primary buttons
                .background(
                    LinearGradient(
                        colors: [Color.appTeal, Color.appTeal.opacity(0.85)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(APRadius.md)
                .shadow(color: Color.appTeal.opacity(0.25), radius: 8, y: 4)
            }
            .buttonStyle(.plain)
            .disabled(isProcessing)
            .padding(.top, APSpacing.sm)
            
            // Helper text
            HStack(spacing: 4) {
                Image(systemName: "info.circle")
                    .font(.system(size: 10))
                Text("session_hint_text".t)
                    .font(.system(size: 10))
            }
            .foregroundColor(.textTertiary)
            .padding(.top, 4)
        }
        .padding(20)
        .background(Color.appSurface)
        .cornerRadius(APRadius.lg)
        .overlay(
            RoundedRectangle(cornerRadius: APRadius.lg)
                .stroke(Color.appBorderSubtle, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 12, y: 4)
    }
    
    // MARK: - Animations
    
    private func startEntryAnimations() {
        // Lock pulse animation (repeating)
        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: false)) {
            isAnimating = true
        }
        
        // Lock bounce (subtle float)
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            lockBounce = true
        }
        
        // Form slide-in with delay
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.3)) {
            showForm = true
        }
    }
    
    // MARK: - Cancel with Confirmation
    
    private func attemptCancel() {
        // If user hasn't changed anything, just dismiss
        if openingCashString == "1000" && openingNotes.isEmpty {
            onCancel?()
            dismiss()
        } else {
            // Show confirmation if data has been entered
            showConfirmCancel = true
        }
    }
    
    // MARK: - Open Session Action
    
    private func openRegisterSession() {
        guard !isProcessing else { return }
        isProcessing = true
        
        APHaptic.trigger()
        
        let amount = Double(openingCashString) ?? 0.0
        let userId = users.first?.id ?? UUID()
        
        // Auto-close any other active sessions to prevent duplicate open shifts
        let descriptor = FetchDescriptor<RegisterSession>(
            predicate: #Predicate<RegisterSession> { $0.closedAt == nil && !$0.isDeleted }
        )
        if let activeSessions = try? modelContext.fetch(descriptor) {
            for session in activeSessions {
                session.closedAt = Date()
                session.expectedClosingCash = session.openingCash
                session.actualClosingCash = session.openingCash
                session.cashDiscrepancy = 0.0
                session.closedByUserId = userId
                session.isSynced = false
                session.updatedAt = Date()
                
                let sessionToUpload = session
                Task {
                    _ = try? await NetworkManager.shared.uploadRegisterSession(sessionToUpload)
                }
            }
        }
        
        let newSession = RegisterSession(
            openedByUserId: userId,
            openedAt: Date(),
            openingCash: amount,
            isSynced: false,
            isDeleted: false,
            updatedAt: Date()
        )
        newSession.notes = openingNotes.isEmpty ? nil : openingNotes
        
        modelContext.insert(newSession)
        try? modelContext.save()
        
        // ── Auto-print Open Shift Slip ─────────────────────────────────
        // พิมพ์อัตโนมัติเฉพาะเมื่อ "print_open_shift" = true ใน Settings
        let capturedSession  = newSession
        let capturedCashier  = users.first?.username ?? ""
        Task {
            _ = try? await NetworkManager.shared.uploadRegisterSession(newSession)
            await PrintService.shared.printOpenShift(
                session: capturedSession,
                cashierName: capturedCashier
            )
        }
        
        // Brief delay for feedback
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            isProcessing = false
            onComplete?()
            dismiss()
        }
    }
}
