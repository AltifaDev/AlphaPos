// BreakTimerView.swift
// AlphaPosStaff — Break Timer Feature
//
// Circular countdown timer for staff breaks with auto-notifications,
// break history, and server-synced status.

import SwiftUI
import UserNotifications

// MARK: - Break Models

enum BreakType: String, CaseIterable, Identifiable {
    case short = "short"
    case meal30 = "meal_30"
    case meal60 = "meal_60"
    case custom = "custom"
    
    var id: String { rawValue }
    
    var durationMinutes: Int {
        switch self {
        case .short: return 15
        case .meal30: return 30
        case .meal60: return 60
        case .custom: return 0
        }
    }
    
    var icon: String {
        switch self {
        case .short: return "cup.and.saucer.fill"
        case .meal30: return "fork.knife"
        case .meal60: return "fork.knife.circle.fill"
        case .custom: return "timer"
        }
    }
    
    var color: Color {
        switch self {
        case .short: return .appTeal
        case .meal30: return .appAmber
        case .meal60: return Color(hex: "FF6B35")
        case .custom: return .appPurple
        }
    }
    
    func localizedName(lang: String) -> String {
        switch self {
        case .short: return "short_break".localized(for: lang)
        case .meal30: return "meal_break".localized(for: lang) + " (30)"
        case .meal60: return "meal_break".localized(for: lang) + " (60)"
        case .custom: return "custom_break".localized(for: lang)
        }
    }
}

struct BreakRecord: Identifiable, Codable {
    let id: String
    let type: String
    let startTime: Date
    var endTime: Date?
    var durationMinutes: Int
    
    var isActive: Bool { endTime == nil }
    
    var actualDuration: TimeInterval {
        let end = endTime ?? Date()
        return end.timeIntervalSince(startTime)
    }
    
    var formattedStartTime: String {
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: startTime)
    }
    
    var formattedEndTime: String {
        guard let end = endTime else { return "—" }
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: end)
    }
    
    var formattedDuration: String {
        let mins = Int(actualDuration / 60)
        if mins >= 60 {
            return "\(mins / 60)h \(mins % 60)m"
        }
        return "\(mins)m"
    }
}

// MARK: - Break Timer View

struct BreakTimerView: View {
    @AppStorage("app_language") private var appLanguage = "en"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Timer state
    @State private var isOnBreak = false
    @State private var selectedBreakType: BreakType = .short
    @State private var customMinutes: Int = 20
    @State private var breakStartTime: Date?
    @State private var totalBreakSeconds: Int = 0
    @State private var remainingSeconds: Int = 0
    @State private var isPaused = false
    @State private var isOvertime = false
    
    // Data
    @State private var breakHistory: [BreakRecord] = []
    @State private var isLoading = false
    @State private var loadError: String? = nil
    @State private var showCustomPicker = false
    
    // Timer
    @State private var timer: Timer?
    
    // Animation
    @State private var pulseScale: CGFloat = 1.0
    @State private var glowOpacity: Double = 0.0
    @State private var showSuccess = false
    
    // Break policy
    private let policyTotalMinutes = 60 // per shift
    private var usedBreakMinutes: Int {
        breakHistory.filter { !$0.isActive }.reduce(0) { $0 + Int($1.actualDuration / 60) }
    }
    private var remainingPolicyMinutes: Int {
        max(0, policyTotalMinutes - usedBreakMinutes)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                
                // Ambient glow
                if isOnBreak {
                    Circle()
                        .fill(selectedBreakType.color.opacity(0.08))
                        .frame(width: 350, height: 350)
                        .blur(radius: 80)
                        .scaleEffect(pulseScale)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 2.5).repeatForever(autoreverses: true), value: pulseScale)
                }
                
                ScrollView {
                    VStack(spacing: APSpacing.lg) {
                        // Break policy card
                        policyCard
                            .padding(.top, APSpacing.md)
                        
                        if isOnBreak {
                            // Active timer
                            activeTimerSection
                        } else {
                            // Break type selector
                            breakTypeSelector
                            
                            // Start button
                            startButton
                        }
                        
                        // Break history
                        breakHistorySection
                    }
                    .padding(.horizontal, APSpacing.md)
                    .padding(.bottom, APSpacing.xxl)
                }
            }
            .navigationTitle("break_timer".localized(for: appLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                loadBreakHistory()
                pulseScale = 1.06
            }
            .onDisappear {
                timer?.invalidate()
            }
            .sheet(isPresented: $showCustomPicker) {
                customDurationSheet
                    .presentationDetents([.medium])
                    .apColorScheme()
            }
        }
    }
    
    // MARK: - Policy Card
    
    private var policyCard: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            HStack {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.appAccent)
                Text("break_policy".localized(for: appLanguage))
                    .font(.system(size: 14, weight: .black))
                    .foregroundColor(.textPrimary)
                Spacer()
                Text("\(remainingPolicyMinutes) " + "minutes".localized(for: appLanguage) + " " + "break_remaining".localized(for: appLanguage))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.textSecondary)
            }
            
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.appSurfaceHigh)
                        .frame(height: 6)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [.appTeal, .appAccent],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * CGFloat(usedBreakMinutes) / CGFloat(policyTotalMinutes), height: 6)
                }
            }
            .frame(height: 6)
            
            HStack {
                Text("\(usedBreakMinutes)/\(policyTotalMinutes) " + "minutes".localized(for: appLanguage))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.textTertiary)
                Spacer()
            }
        }
        .padding(APSpacing.md)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: APRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: APRadius.lg, style: .continuous)
                .stroke(Color.appBorderSubtle, lineWidth: 1)
        )
    }
    
    // MARK: - Break Type Selector
    
    private var breakTypeSelector: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            Text("select_break_type".localized(for: appLanguage))
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.textSecondary)
                .padding(.leading, 4)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: APSpacing.sm) {
                ForEach(BreakType.allCases) { breakType in
                    breakTypeCard(breakType)
                }
            }
        }
    }
    
    private func breakTypeCard(_ type: BreakType) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                selectedBreakType = type
                if type == .custom {
                    showCustomPicker = true
                }
            }
        } label: {
            VStack(spacing: APSpacing.sm) {
                ZStack {
                    Circle()
                        .fill(type.color.opacity(selectedBreakType == type ? 0.2 : 0.08))
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: type.icon)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(type.color)
                }
                
                Text(type.localizedName(lang: appLanguage))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                
                if type != .custom {
                    Text("\(type.durationMinutes) " + "minutes".localized(for: appLanguage))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.textSecondary)
                } else {
                    Text("\(customMinutes) " + "minutes".localized(for: appLanguage))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.textSecondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, APSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: APRadius.md, style: .continuous)
                    .fill(selectedBreakType == type ? type.color.opacity(0.08) : Color.appSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: APRadius.md, style: .continuous)
                            .stroke(selectedBreakType == type ? type.color.opacity(0.4) : Color.appBorderSubtle, lineWidth: selectedBreakType == type ? 2 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Start Button
    
    private var startButton: some View {
        Button(action: startBreak) {
            HStack(spacing: APSpacing.sm) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 22, weight: .bold))
                Text("start_break".localized(for: appLanguage))
                    .font(.system(size: 17, weight: .black))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                LinearGradient(
                    colors: [selectedBreakType.color, selectedBreakType.color.opacity(0.8)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: APRadius.md, style: .continuous))
            .shadow(color: selectedBreakType.color.opacity(0.3), radius: 16, x: 0, y: 8)
        }
    }
    
    // MARK: - Active Timer Section
    
    private var activeTimerSection: some View {
        VStack(spacing: APSpacing.lg) {
            // Circular timer
            ZStack {
                // Background ring
                Circle()
                    .stroke(Color.appSurfaceHigh, lineWidth: 12)
                    .frame(width: 220, height: 220)
                
                // Progress ring
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        isOvertime
                            ? LinearGradient(colors: [.appRose, .appAmber], startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [selectedBreakType.color, selectedBreakType.color.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .frame(width: 220, height: 220)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: progress)
                
                // Glow effect
                Circle()
                    .stroke(isOvertime ? Color.appRose.opacity(0.3) : selectedBreakType.color.opacity(0.3), lineWidth: 20)
                    .frame(width: 220, height: 220)
                    .blur(radius: 12)
                    .opacity(glowOpacity)
                    .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: glowOpacity)
                
                // Center content
                VStack(spacing: 6) {
                    if isOvertime {
                        Text("break_overtime".localized(for: appLanguage))
                            .font(.system(size: 12, weight: .black))
                            .foregroundColor(.appRose)
                    }
                    
                    Text(timeString)
                        .font(.system(size: 44, weight: .black, design: .monospaced))
                        .foregroundColor(isOvertime ? .appRose : .textPrimary)
                    
                    Text(isOvertime ? "+" + overtimeString : "break_remaining".localized(for: appLanguage))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(isOvertime ? .appRose : .textSecondary)
                    
                    HStack(spacing: 6) {
                        Circle()
                            .fill(isPaused ? Color.appAmber : Color.appTeal)
                            .frame(width: 8, height: 8)
                        Text(isPaused ? "paused".localized(for: appLanguage) : selectedBreakType.localizedName(lang: appLanguage))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.textTertiary)
                    }
                }
            }
            .padding(.vertical, APSpacing.md)
            
            // Control buttons
            HStack(spacing: APSpacing.md) {
                // Pause/Resume
                Button(action: togglePause) {
                    VStack(spacing: 6) {
                        Image(systemName: isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 20, weight: .bold))
                        Text(isPaused ? "resume_break".localized(for: appLanguage) : "pause_break".localized(for: appLanguage))
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundColor(.appAccent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 72)
                    .background(Color.appAccent.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: APRadius.md, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: APRadius.md, style: .continuous)
                            .stroke(Color.appAccent.opacity(0.2), lineWidth: 1)
                    )
                }
                
                // End Break
                Button(action: endBreak) {
                    VStack(spacing: 6) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 20, weight: .bold))
                        Text("end_break".localized(for: appLanguage))
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundColor(.appRose)
                    .frame(maxWidth: .infinity)
                    .frame(height: 72)
                    .background(Color.appRose.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: APRadius.md, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: APRadius.md, style: .continuous)
                            .stroke(Color.appRose.opacity(0.2), lineWidth: 1)
                    )
                }
            }
        }
        .padding(APSpacing.md)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: APRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: APRadius.lg, style: .continuous)
                .stroke(isOvertime ? Color.appRose.opacity(0.3) : Color.appBorderSubtle, lineWidth: isOvertime ? 2 : 1)
        )
        .shadow(color: isOvertime ? Color.appRose.opacity(0.15) : Color.black.opacity(0.06), radius: 18, x: 0, y: 10)
    }
    
    // MARK: - Break History Section
    
    private var breakHistorySection: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.appAccent)
                Text("break_history".localized(for: appLanguage))
                    .font(.system(size: 15, weight: .black))
                    .foregroundColor(.textPrimary)
                Spacer()
                Text("\(breakHistory.count)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.textTertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.appSurfaceHigh)
                    .clipShape(Capsule())
            }
            
            if breakHistory.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        if let err = loadError {
                            Image(systemName: "wifi.exclamationmark")
                                .font(.system(size: 28)).foregroundColor(.appRose)
                            Text(err)
                                .font(.caption).foregroundColor(.textSecondary)
                                .multilineTextAlignment(.center)
                        } else {
                        Image(systemName: "moon.zzz.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.textTertiary)
                        Text("no_breaks_today".localized(for: appLanguage))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.textSecondary)
                        }
                    }
                    .padding(.vertical, APSpacing.xl)
                    Spacer()
                }
            } else {
                ForEach(breakHistory) { record in
                    breakHistoryRow(record)
                }
            }
        }
        .padding(APSpacing.md)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: APRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: APRadius.lg, style: .continuous)
                .stroke(Color.appBorderSubtle, lineWidth: 1)
        )
    }
    
    private func breakHistoryRow(_ record: BreakRecord) -> some View {
        let type = BreakType(rawValue: record.type) ?? .short
        return HStack(spacing: APSpacing.sm) {
            // Type icon
            ZStack {
                Circle()
                    .fill(type.color.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: type.icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(type.color)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text(type.localizedName(lang: appLanguage))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.textPrimary)
                Text("\(record.formattedStartTime) → \(record.formattedEndTime)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.textSecondary)
            }
            
            Spacer()
            
            // Duration badge
            Text(record.formattedDuration)
                .font(.system(size: 12, weight: .black, design: .monospaced))
                .foregroundColor(type.color)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(type.color.opacity(0.1))
                .clipShape(Capsule())
        }
        .padding(.vertical, 6)
    }
    
    // MARK: - Custom Duration Sheet
    
    private var customDurationSheet: some View {
        VStack(spacing: APSpacing.lg) {
            Spacer().frame(height: 12)
            
            Text("custom_break".localized(for: appLanguage))
                .font(.system(size: 20, weight: .black))
                .foregroundColor(.textPrimary)
            
            Text("set_duration".localized(for: appLanguage))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.textSecondary)
            
            // Duration picker
            HStack(spacing: APSpacing.lg) {
                Button {
                    if customMinutes > 5 { customMinutes -= 5 }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.appRose)
                }
                
                VStack(spacing: 4) {
                    Text("\(customMinutes)")
                        .font(.system(size: 48, weight: .black, design: .monospaced))
                        .foregroundColor(.textPrimary)
                    Text("minutes".localized(for: appLanguage))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.textSecondary)
                }
                .frame(width: 120)
                
                Button {
                    if customMinutes < 120 { customMinutes += 5 }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.appTeal)
                }
            }
            .padding(.vertical, APSpacing.lg)
            
            // Quick presets
            HStack(spacing: APSpacing.sm) {
                ForEach([10, 20, 25, 45], id: \.self) { mins in
                    Button {
                        customMinutes = mins
                    } label: {
                        Text("\(mins)m")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(customMinutes == mins ? .white : .textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(customMinutes == mins ? Color.appPurple : Color.appSurfaceHigh)
                            .clipShape(Capsule())
                    }
                }
            }
            
            Spacer()
            
            Button {
                showCustomPicker = false
            } label: {
                Text("done".localized(for: appLanguage))
                    .font(.system(size: 16, weight: .black))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.appPurple)
                    .clipShape(RoundedRectangle(cornerRadius: APRadius.md, style: .continuous))
            }
            .padding(.bottom, APSpacing.md)
        }
        .padding(.horizontal, APSpacing.lg)
        .background(Color.appBackground.ignoresSafeArea())
    }
    
    // MARK: - Timer Computed Properties
    
    private var progress: CGFloat {
        guard totalBreakSeconds > 0 else { return 0 }
        if isOvertime {
            return 1.0
        }
        let elapsed = totalBreakSeconds - remainingSeconds
        return CGFloat(elapsed) / CGFloat(totalBreakSeconds)
    }
    
    private var timeString: String {
        let absSeconds = abs(remainingSeconds)
        let h = absSeconds / 3600
        let m = (absSeconds % 3600) / 60
        let s = absSeconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
    
    private var overtimeString: String {
        guard isOvertime, let start = breakStartTime else { return "" }
        let totalElapsed = Int(Date().timeIntervalSince(start))
        let overtime = totalElapsed - totalBreakSeconds
        let m = overtime / 60
        let s = overtime % 60
        return String(format: "%d:%02d", m, s)
    }
    
    // MARK: - Actions
    
    private func startBreak() {
        let duration: Int
        if selectedBreakType == .custom {
            duration = customMinutes * 60
        } else {
            duration = selectedBreakType.durationMinutes * 60
        }
        
        totalBreakSeconds = duration
        remainingSeconds = duration
        breakStartTime = Date()
        isOnBreak = true
        isPaused = false
        isOvertime = false
        
        // Start timer
        startTimer()
        
        // Schedule local notifications
        scheduleBreakNotifications(duration: duration)
        
        // Animate glow
        glowOpacity = 0.6
        
        // Sync with server
        Task {
            await syncBreakStart()
        }
    }
    
    private func togglePause() {
        isPaused.toggle()
        if isPaused {
            timer?.invalidate()
            timer = nil
        } else {
            startTimer()
        }
    }
    
    private func endBreak() {
        timer?.invalidate()
        timer = nil
        
        // Cancel pending notifications
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        
        // Record to history
        if let start = breakStartTime {
            let record = BreakRecord(
                id: UUID().uuidString,
                type: selectedBreakType.rawValue,
                startTime: start,
                endTime: Date(),
                durationMinutes: selectedBreakType == .custom ? customMinutes : selectedBreakType.durationMinutes
            )
            breakHistory.insert(record, at: 0)
        }
        
        // Reset state
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            isOnBreak = false
            isOvertime = false
            glowOpacity = 0
            remainingSeconds = 0
            breakStartTime = nil
        }
        
        // Sync with server
        Task {
            await syncBreakEnd()
        }
    }
    
    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if remainingSeconds > 0 {
                remainingSeconds -= 1
                
                // 5 minute warning
                if remainingSeconds == 300 {
                    triggerWarningHaptic()
                }
            } else {
                if !isOvertime {
                    isOvertime = true
                    triggerOvertimeHaptic()
                }
            }
        }
    }
    
    private func scheduleBreakNotifications(duration: Int) {
        let center = UNUserNotificationCenter.current()
        
        // 5 minutes before end
        if duration > 300 {
            let warningContent = UNMutableNotificationContent()
            warningContent.title = "⏰ Break ending soon"
            warningContent.body = "5 minutes remaining on your break"
            warningContent.sound = .default
            
            let warningTrigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(duration - 300), repeats: false)
            let warningRequest = UNNotificationRequest(identifier: "break_warning", content: warningContent, trigger: warningTrigger)
            center.add(warningRequest)
        }
        
        // Break over
        let overtimeContent = UNMutableNotificationContent()
        overtimeContent.title = "🚨 " + "break_overtime".localized(for: appLanguage)
        overtimeContent.body = "Your break time is up. Please return to work."
        overtimeContent.sound = .defaultCritical
        
        let overtimeTrigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(duration), repeats: false)
        let overtimeRequest = UNNotificationRequest(identifier: "break_overtime", content: overtimeContent, trigger: overtimeTrigger)
        center.add(overtimeRequest)
    }
    
    private func triggerWarningHaptic() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
    }
    
    private func triggerOvertimeHaptic() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
    }
    
    // MARK: - Network
    
    private func loadBreakHistory() {
        isLoading = true
        Task {
            do {
                let records = try await NetworkService.shared.fetchBreakHistory(date: Date())
                await MainActor.run {
                    breakHistory = records
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    loadError = "Could not load break history. Check connection."
                }
            }
        }
    }
    
    private func syncBreakStart() async {
        do {
            try await NetworkService.shared.startBreak(type: selectedBreakType.rawValue)
        } catch {
            print("Failed to sync break start: \(error)")
        }
    }
    
    private func syncBreakEnd() async {
        do {
            try await NetworkService.shared.endBreak()
        } catch {
            print("Failed to sync break end: \(error)")
        }
    }
}

// MARK: - Compact Break Card (for TimecardView integration)

struct BreakTimerCard: View {
    @AppStorage("app_language") private var appLanguage = "en"
    @State private var showBreakTimer = false
    
    var body: some View {
        Button(action: { showBreakTimer = true }) {
            HStack(spacing: APSpacing.sm) {
                ZStack {
                    Circle()
                        .fill(Color.appAmber.opacity(0.12))
                        .frame(width: 42, height: 42)
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.appAmber)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text("break_timer".localized(for: appLanguage))
                        .font(.system(size: 14, weight: .black))
                        .foregroundColor(.textPrimary)
                    Text("start_break".localized(for: appLanguage))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.textSecondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.textTertiary)
            }
            .padding(APSpacing.md)
            .background(Color.appAmber.opacity(0.055))
            .clipShape(RoundedRectangle(cornerRadius: APRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: APRadius.md, style: .continuous)
                    .stroke(Color.appAmber.opacity(0.14), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showBreakTimer) {
            BreakTimerView()
                .apColorScheme()
        }
    }
}

#Preview {
    BreakTimerView()
        .preferredColorScheme(.dark)
}
