import SwiftUI
import LocalAuthentication

struct TimecardView: View {
    let employee: Employee
    @AppStorage("app_language") private var appLanguage = "en"
    
    @State private var recentTimecards: [Timecard] = []
    @State private var activeTimecard: Timecard? = nil
    @State private var isLoading = false
    @State private var showingScanner = false
    @State private var scannerMode = "clockIn" // "clockIn", "clockOut"
    
    @State private var isScanning = false
    @State private var scanProgress = 0.0
    @State private var scanSuccess = false
    @State private var scannerMessage = "Authenticate to clock in/out"

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    if isLoading {
                        ProgressView().tint(.appAccent).frame(maxHeight: .infinity)
                    } else {
                        ScrollView {
                            VStack(spacing: APSpacing.lg) {
                                // Status banner
                                VStack(spacing: APSpacing.md) {
                                    if let active = activeTimecard {
                                        ZStack {
                                            Circle()
                                                .fill(Color.appTeal.opacity(0.15))
                                                .frame(width: 80, height: 80)
                                            Image(systemName: "clock.badge.checkmark.fill")
                                                .font(.system(size: 40))
                                                .foregroundColor(.appTeal)
                                        }
                                        
                                        VStack(spacing: 2) {
                                            Text("on_shift".localized(for: appLanguage))
                                                .font(.caption).fontWeight(.black)
                                                .foregroundColor(.appTeal)
                                            
                                            let clockInDate = Date(timeIntervalSince1970: active.clockIn)
                                            Text("started_at".localized(for: appLanguage)) + Text(" ") + Text(clockInDate, style: .time)
                                                .font(.title2).fontWeight(.black)
                                                .foregroundColor(.textPrimary)
                                        }
                                        
                                        Button(action: {
                                            APHaptic.trigger()
                                            scannerMode = "clockOut"
                                            showingScanner = true
                                        }) {
                                            Label("auth_clock_out".localized(for: appLanguage), systemImage: "door.right.hand.open")
                                                .apGradientButton(gradient: APGradient.destructive)
                                        }
                                    } else {
                                        ZStack {
                                            Circle()
                                                .fill(Color.appAccent.opacity(0.1))
                                                .frame(width: 80, height: 80)
                                            Image(systemName: "clock.arrow.circlepath")
                                                .font(.system(size: 40))
                                                .foregroundColor(.appAccent)
                                        }
                                        
                                        VStack(spacing: 2) {
                                            Text("off_duty".localized(for: appLanguage))
                                                .font(.caption).fontWeight(.black)
                                                .foregroundColor(.textSecondary)
                                            Text("not_clocked_in_today".localized(for: appLanguage))
                                                .font(.headline)
                                                .foregroundColor(.textSecondary)
                                        }
                                        
                                        Button(action: {
                                            APHaptic.trigger()
                                            scannerMode = "clockIn"
                                            showingScanner = true
                                        }) {
                                            Label("auth_clock_in".localized(for: appLanguage), systemImage: "door.left.hand.open")
                                                .apGradientButton(gradient: APGradient.positive)
                                        }
                                    }
                                }
                                .padding()
                                .apCard()
                                
                                // History Section
                                VStack(alignment: .leading, spacing: APSpacing.md) {
                                    Text("recent_shifts".localized(for: appLanguage))
                                        .font(.headline).fontWeight(.bold)
                                        .foregroundColor(.textPrimary)
                                    
                                    if recentTimecards.isEmpty {
                                        Text("no_clock_in_records".localized(for: appLanguage))
                                            .font(.caption).foregroundColor(.textSecondary)
                                            .padding(.vertical)
                                    } else {
                                        ForEach(recentTimecards.prefix(5)) { card in
                                            HStack(spacing: APSpacing.md) {
                                                // Status Icon
                                                Image(systemName: card.clockOut != nil ? "checkmark.circle.fill" : "arrow.right.circle.fill")
                                                    .font(.title2)
                                                    .foregroundColor(card.clockOut != nil ? .appTeal : .appRose)
                                                
                                                VStack(alignment: .leading, spacing: 2) {
                                                    let inDate = Date(timeIntervalSince1970: card.clockIn)
                                                    Text(inDate, style: .date)
                                                        .font(.subheadline).fontWeight(.bold)
                                                        .foregroundColor(.textPrimary)
                                                    
                                                    HStack(spacing: 4) {
                                                        Text(inDate, style: .time)
                                                        if let outTime = card.clockOut, outTime > 0 {
                                                            Text("→")
                                                            let outDate = Date(timeIntervalSince1970: outTime)
                                                            Text(outDate, style: .time)
                                                        } else {
                                                            Text("→ ") + Text("active_now".localized(for: appLanguage))
                                                                .foregroundColor(.appTeal)
                                                                .fontWeight(.bold)
                                                        }
                                                    }
                                                    .font(.caption)
                                                    .foregroundColor(.textSecondary)
                                                }
                                                
                                                Spacer()
                                                
                                                // Working Hours
                                                if let outTime = card.clockOut, outTime > 0 {
                                                    let hrs = (outTime - card.clockIn) / 3600.0
                                                    Text(String(format: "hours_worked_format".localized(for: appLanguage), hrs))
                                                        .font(.subheadline).fontWeight(.black)
                                                        .foregroundColor(.textPrimary)
                                                }
                                            }
                                            .padding(.vertical, APSpacing.xs)
                                            Divider().background(Color.appDivider)
                                        }
                                    }
                                }
                                .padding()
                                .apCard()
                            }
                            .padding()
                        }
                    }
                }
            }
            .navigationTitle("timecard_register".localized(for: appLanguage))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: loadTimecards) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.appAccent)
                    }
                }
            }
        }
        .onAppear {
            loadTimecards()
        }
        .sheet(isPresented: $showingScanner) {
            scannerView
                .presentationDetents([.fraction(0.85)])
                .apColorScheme()
        }
    }
    
    private func loadTimecards() {
        isLoading = true
        Task {
            do {
                let list = try await NetworkService.shared.fetchTimecards(for: employee.id)
                await MainActor.run {
                    self.recentTimecards = list
                    // Find active shift
                    self.activeTimecard = list.first(where: { $0.clockOut == nil || $0.clockOut == 0.0 })
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }
    
    // MARK: - Biometric Scanner
    
    private var displayScannerMessage: String {
        if scannerMessage == "Authenticating..." {
            return "matching_facial".localized(for: appLanguage)
        } else if scannerMessage == "Identity Verified" {
            return "biometric_verified".localized(for: appLanguage)
        }
        return scannerMessage.localized(for: appLanguage)
    }

    private var scannerView: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            
            VStack(spacing: APSpacing.xl) {
                APBadge(
                    text: scannerMode == "clockIn" ? "clock_in".localized(for: appLanguage).uppercased() : "clock_out".localized(for: appLanguage).uppercased(),
                    color: scannerMode == "clockIn" ? .appTeal : .appRose,
                    icon: "faceid"
                )
                .padding(.top, APSpacing.xl)
                
                Text("\(employee.firstName) \(employee.lastName)")
                    .font(.title2).fontWeight(.black)
                    .foregroundColor(.textPrimary)
                
                // Scan animation area
                ZStack {
                    Circle()
                        .fill(Color.appSurface)
                        .frame(width: 240, height: 240)
                        .overlay(
                            Circle()
                                .stroke(isScanning ? (scannerMode == "clockIn" ? Color.appTeal : Color.appRose) : Color.appBorderSubtle, lineWidth: 2)
                        )
                    
                    Image(systemName: "faceid")
                        .font(.system(size: 110, weight: .ultraLight))
                        .foregroundStyle(isScanning ? (scannerMode == "clockIn" ? Color.appTeal : Color.appRose).opacity(0.8) : Color.textSecondary.opacity(0.3))
                    
                    if isScanning {
                        Circle()
                            .trim(from: 0.0, to: scanProgress)
                            .stroke(scannerMode == "clockIn" ? APGradient.positive : APGradient.destructive, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .frame(width: 240, height: 240)
                            .rotationEffect(.degrees(-90))
                    }
                }
                .frame(width: 260, height: 260)
                
                Text(displayScannerMessage)
                    .font(.subheadline)
                    .foregroundColor(scanSuccess ? .appTeal : .textSecondary)
                
                if !isScanning && !scanSuccess {
                    Button(action: startScan) {
                        Label(scannerMode == "clockIn" ? "auth_clock_in".localized(for: appLanguage) : "auth_clock_out".localized(for: appLanguage), systemImage: "faceid")
                            .apGradientButton(
                                gradient: scannerMode == "clockIn" ? APGradient.positive : APGradient.destructive,
                                shadow: scannerMode == "clockIn" ? APShadow.positiveGlow : APShadow.destructiveGlow
                            )
                    }
                    .padding(.horizontal, APSpacing.xl)
                }
                
                Spacer()
            }
        }
    }
    
    private func startScan() {
        let context = LAContext()
        var error: NSError?
        
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            scannerMessage = "Biometrics not available"
            return
        }
        
        isScanning = true
        scanProgress = 0.0
        scannerMessage = "Authenticating..."
        
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                               localizedReason: "Verify identity for timecard") { success, authError in
            DispatchQueue.main.async {
                if success {
                    self.scanProgress = 1.0
                    self.scanSuccess = true
                    self.scannerMessage = "Identity Verified"
                    APHaptic.trigger()
                    
                    Task {
                        do {
                            if self.scannerMode == "clockIn" {
                                let tc = Timecard(
                                    id: UUID().uuidString,
                                    employeeId: self.employee.id,
                                    employeeName: "\(self.employee.firstName) \(self.employee.lastName)",
                                    clockIn: Date().timeIntervalSince1970,
                                    clockOut: nil,
                                    breakDurationMinutes: 0,
                                    overtimeMinutes: 0,
                                    status: "approved",
                                    notes: "Biometric clock-in via iPhone",
                                    clockInFaceConfidence: 99.0,
                                    clockOutFaceConfidence: nil
                                )
                                _ = try await NetworkService.shared.uploadTimecard(timecard: tc)
                            } else if let active = self.activeTimecard {
                                let tc = Timecard(
                                    id: active.id,
                                    employeeId: self.employee.id,
                                    employeeName: "\(self.employee.firstName) \(self.employee.lastName)",
                                    clockIn: active.clockIn,
                                    clockOut: Date().timeIntervalSince1970,
                                    breakDurationMinutes: 0,
                                    overtimeMinutes: 0,
                                    status: "approved",
                                    notes: "Biometric clock-out via iPhone",
                                    clockInFaceConfidence: active.clockInFaceConfidence,
                                    clockOutFaceConfidence: 99.0
                                )
                                _ = try await NetworkService.shared.uploadTimecard(timecard: tc)
                            }
                            
                            await MainActor.run {
                                self.isScanning = false
                                self.scanSuccess = false
                                self.showingScanner = false
                                self.loadTimecards()
                            }
                        } catch {
                            await MainActor.run {
                                self.isScanning = false
                                self.scanSuccess = false
                                self.showingScanner = false
                            }
                        }
                    }
                } else {
                    self.isScanning = false
                    self.scanProgress = 0.0
                    self.scannerMessage = "Authentication failed"
                }
            }
        }
    }
}
