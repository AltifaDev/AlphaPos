import SwiftUI

struct MoreMenuView: View {
    @Binding var loggedInEmployee: Employee?
    
    @AppStorage("app_language") private var appLanguage = "en"
    @AppStorage("enable_notifications") private var enableNotifications = true
    @AppStorage(StaffSoundFeedback.enabledKey) private var soundFeedbackEnabled = true
    @AppStorage("active_merchant_id") private var activeMerchantId = ""
    @AppStorage("offline_sync_mode") private var offlineSyncMode = false
    @AppStorage("logged_in_employee_id") private var loggedInEmployeeId = ""
    
    @State private var isStoreIdCopied = false
    @State private var isClearingCache = false
    @State private var showStatusMessage = false
    @State private var statusMessage = ""
    @State private var showingSignOutAlert = false
    @State private var todayTimecard: Timecard? = nil
    @State private var isLoadingAttendance = false
    @State private var attendanceLoadFailed = false

    private var isCurrentlyClockedIn: Bool {
        guard let card = todayTimecard else { return false }
        return card.clockOut == nil || card.clockOut == 0.0
    }

    private var clockInDateString: String? {
        guard let card = todayTimecard else { return nil }
        let date = Date(timeIntervalSince1970: card.clockIn)
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return "\(fmt.string(from: date)) น."
    }

    private var clockOutDateString: String? {
        guard let card = todayTimecard, let out = card.clockOut, out > 0 else { return nil }
        let date = Date(timeIntervalSince1970: out)
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return "\(fmt.string(from: date)) น."
    }

    var body: some View {
        ScrollView {
            VStack(spacing: APSpacing.lg) {
                // 1. Premium Profile Header Card
                if let emp = loggedInEmployee {
                    profileHeaderCard(emp: emp)
                }
                
                // 2. Work & Schedule Section
                VStack(alignment: .leading, spacing: APSpacing.sm) {
                    HStack {
                        sectionTitle("work_schedule".localized(for: appLanguage))
                        Spacer()
                        if isLoadingAttendance {
                            ProgressView()
                                .scaleEffect(0.65)
                        } else {
                            Button(action: loadTodayAttendance) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.textTertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    VStack(spacing: 0) {
                        // Live attendance status banner
                        if isCurrentlyClockedIn, let inTime = clockInDateString {
                            HStack(spacing: APSpacing.md) {
                                ZStack {
                                    Circle()
                                        .fill(Color.appGreen.opacity(0.18))
                                        .frame(width: 36, height: 36)
                                    Circle()
                                        .fill(Color.appGreen)
                                        .frame(width: 10, height: 10)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text("กำลังเข้างานอยู่ (On Shift)")
                                            .font(.subheadline.weight(.bold))
                                            .foregroundColor(.appGreen)
                                        Text("· วันนี้")
                                            .font(.caption)
                                            .foregroundColor(.textTertiary)
                                    }
                                    Text("เข้างานเวลา \(inTime) · บันทึกเวลาแล้วที่ iPad ร้านค้า")
                                        .font(.caption)
                                        .foregroundColor(.textSecondary)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, APSpacing.md)
                            .padding(.vertical, 12)
                            .background(Color.appGreen.opacity(0.06))

                            Divider().background(Color.appDivider)
                        } else if let inTime = clockInDateString, let outTime = clockOutDateString {
                            HStack(spacing: APSpacing.md) {
                                iconContainer(name: "checkmark.seal.fill", color: .appTeal)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("ออกงานแล้ววันนี้ (Off Shift)")
                                        .font(.subheadline.weight(.bold))
                                        .foregroundColor(.textPrimary)
                                    Text("เวลา \(inTime) – \(outTime)")
                                        .font(.caption)
                                        .foregroundColor(.textSecondary)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, APSpacing.md)
                            .padding(.vertical, 12)
                            .background(Color.appTeal.opacity(0.04))

                            Divider().background(Color.appDivider)
                        }

                        NavigationLink {
                            ShiftScheduleView()
                        } label: {
                            menuRow(icon: "calendar.badge.clock", iconColor: .appAccent, title: "ตารางงาน (ดูอย่างเดียว)")
                        }
                        
                        Divider().background(Color.appDivider).padding(.leading, 48)
                        
                        // Attendance row
                        HStack(spacing: APSpacing.md) {
                            if isCurrentlyClockedIn {
                                iconContainer(name: "clock.badge.checkmark.fill", color: .appGreen)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("เข้างานแล้ววันนี้ (เวลา \(clockInDateString ?? ""))")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(.textPrimary)
                                    Text("ใช้ iPad ของร้านค้าเพื่อลงเวลาออกเมื่อเลิกงาน")
                                        .font(.caption)
                                        .foregroundColor(.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundColor(.appGreen)
                            } else if let inTime = clockInDateString, let outTime = clockOutDateString {
                                iconContainer(name: "clock.badge.checkmark", color: .appTeal)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("บันทึกเวลาวันนี้เรียบร้อย (\(inTime) – \(outTime))")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(.textPrimary)
                                    Text("ลงเวลาเข้าและออกงานผ่าน iPad ร้านค้าเรียบร้อยแล้ว")
                                        .font(.caption)
                                        .foregroundColor(.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer()
                                Image(systemName: "checkmark.circle")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundColor(.appTeal)
                            } else if attendanceLoadFailed {
                                iconContainer(name: "exclamationmark.triangle.fill", color: .appAmber)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("ไม่สามารถตรวจสอบสถานะลงเวลาได้")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(.textPrimary)
                                    Text("ตรวจสอบการเชื่อมต่อแล้วกดรีเฟรชอีกครั้ง")
                                        .font(.caption)
                                        .foregroundColor(.textSecondary)
                                }
                                Spacer()
                            } else {
                                iconContainer(name: "ipad.and.iphone", color: .appTeal)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("ลงเวลาที่เครื่องร้านค้า (ยังไม่เข้างาน)")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(.textPrimary)
                                    Text("ใช้ iPad ของร้านค้าเพื่อยืนยันตัวตนและลงเวลาเข้างาน")
                                        .font(.caption)
                                        .foregroundColor(.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer()
                                Image(systemName: "lock.fill")
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(.textSecondary)
                            }
                        }
                        .padding(.horizontal, APSpacing.md)
                        .padding(.vertical, 14)
                    }
                    .apCard(padding: 0)
                }
                
                // 3. Personal Account & Preferences Section
                VStack(alignment: .leading, spacing: APSpacing.sm) {
                    sectionTitle("personal_info".localized(for: appLanguage))
                    
                    VStack(spacing: 0) {
                        if let emp = loggedInEmployee {
                            NavigationLink {
                                StaffDashboardView(employee: emp, loggedInEmployee: $loggedInEmployee)
                            } label: {
                                menuRow(icon: "person.text.rectangle.fill", iconColor: .appAmber, title: "ประวัติการทำงานและค่าจ้าง (ดูอย่างเดียว)")
                            }
                        }
                        
                        Divider().background(Color.appDivider).padding(.leading, 48)
                        
                        // Inline Preferences / Notification toggle
                        HStack(spacing: APSpacing.md) {
                            iconContainer(name: "bell.fill", color: .appPurple)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("enable_notifications".localized(for: appLanguage))
                                    .font(.subheadline)
                                    .foregroundColor(.textPrimary)
                            }
                            Spacer()
                            Toggle("", isOn: $enableNotifications)
                                .labelsHidden()
                                .tint(.appAccent)
                        }
                        .padding(.horizontal, APSpacing.md)
                        .padding(.vertical, 12)

                        Divider().background(Color.appDivider).padding(.leading, 48)

                        // Push Notification Settings
                        NavigationLink {
                            PushNotificationSettingsView()
                        } label: {
                            menuRow(icon: "bell.badge.fill", iconColor: .appPurple, title: "push_notification_settings".localized(for: appLanguage))
                        }

                        Divider().background(Color.appDivider).padding(.leading, 48)

                        HStack(spacing: APSpacing.md) {
                            iconContainer(name: soundFeedbackEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill", color: .appTeal)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(appLanguage == "th" ? "เสียงตอบสนองการกด" : "Button sounds")
                                    .font(.subheadline).foregroundColor(.textPrimary)
                                Text(appLanguage == "th" ? "ใช้เสียงมาตรฐานของ iOS สำหรับการสั่งซื้อและชำระเงิน" : "Use iOS system sounds for ordering and payment")
                                    .font(.caption).foregroundColor(.textSecondary)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(get: { soundFeedbackEnabled }, set: { StaffSoundFeedback.setEnabled($0) }))
                                .labelsHidden().tint(.appAccent)
                        }
                        .padding(.horizontal, APSpacing.md).padding(.vertical, 12)
                        
                        Divider().background(Color.appDivider).padding(.leading, 48)
                        
                        // Language Segmented Picker
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                iconContainer(name: "globe", color: .appTeal)
                                Text("app_language".localized(for: appLanguage))
                                    .font(.subheadline)
                                    .foregroundColor(.textPrimary)
                                Spacer()
                            }
                            
                            Picker("", selection: $appLanguage) {
                                ForEach(AppLanguage.allCases) { lang in
                                    Text("\(lang.flag) \(lang.displayName)").tag(lang.rawValue)
                                }
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: appLanguage) { _, _ in
                                // Keep APNs content in sync with the language selected on this device.
                                Task { try? await NetworkService.shared.upsertPushDevice() }
                            }
                            .padding(.top, 4)
                        }
                        .padding(.horizontal, APSpacing.md)
                        .padding(.vertical, 12)
                    }
                    .apCard(padding: 0)
                }
                
                // 4. System Status & Diagnostics Section
                VStack(alignment: .leading, spacing: APSpacing.sm) {
                    sectionTitle("system_session".localized(for: appLanguage))
                    
                    VStack(spacing: 0) {
                        // Diagnostics Connection Row
                        HStack(spacing: APSpacing.md) {
                            iconContainer(name: "cpu.fill", color: .textSecondary)
                            Text("connection_status".localized(for: appLanguage))
                                .font(.subheadline)
                                .foregroundColor(.textPrimary)
                            Spacer()
                            
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(NetworkService.shared.connectionError ? Color.appRose : Color.appGreen)
                                    .frame(width: 6, height: 6)
                                Text((NetworkService.shared.connectionError ? "offline_status" : "online_status").localized(for: appLanguage))
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(NetworkService.shared.connectionError ? .appRose : .appTeal)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(NetworkService.shared.connectionError ? Color.appRose.opacity(0.12) : Color.appGreen.opacity(0.12))
                            )
                        }
                        .padding(.horizontal, APSpacing.md)
                        .padding(.vertical, 12)
                        
                        Divider().background(Color.appDivider).padding(.leading, 48)
                        
                        // Merchant ID Row
                        HStack(spacing: APSpacing.md) {
                            iconContainer(name: "lock.shield.fill", color: .textSecondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("merchant_uuid_label".localized(for: appLanguage))
                                    .font(.caption2)
                                    .foregroundColor(.textSecondary)
                                Text(activeMerchantId.isEmpty ? "not_paired_status".localized(for: appLanguage) : activeMerchantId)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.textPrimary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.5)
                            }
                            Spacer()
                            
                            if !activeMerchantId.isEmpty {
                                Button(action: {
                                    UIPasteboard.general.string = activeMerchantId
                                    APHaptic.trigger()
                                    withAnimation {
                                        isStoreIdCopied = true
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                        isStoreIdCopied = false
                                    }
                                }) {
                                    Image(systemName: isStoreIdCopied ? "checkmark.circle.fill" : "doc.on.doc")
                                        .foregroundColor(isStoreIdCopied ? .appTeal : .appAccent)
                                }
                            }
                        }
                        .padding(.horizontal, APSpacing.md)
                        .padding(.vertical, 12)
                        
                        Divider().background(Color.appDivider).padding(.leading, 48)

                        diagnosticsValueRow(
                            icon: "externaldrive.badge.icloud",
                            iconColor: offlineSyncMode ? .appAmber : .appTeal,
                            title: "offline_sync_mode",
                            value: offlineSyncMode ? "true (Offline)" : "false (Online)"
                        )

                        Divider().background(Color.appDivider).padding(.leading, 48)

                        diagnosticsValueRow(
                            icon: "waveform.path.ecg",
                            iconColor: NetworkService.shared.isRealtimeConnected ? .appTeal : .appRose,
                            title: "Realtime",
                            value: NetworkService.shared.isRealtimeConnected ? "Connected" : "Disconnected"
                        )

                        Divider().background(Color.appDivider).padding(.leading, 48)

                        diagnosticsValueRow(
                            icon: "clock.arrow.circlepath",
                            iconColor: .appAccent,
                            title: "Last Sync",
                            value: NetworkService.shared.lastSyncDisplayDate?.formatted(date: .abbreviated, time: .standard) ?? "Never"
                        )

                        Divider().background(Color.appDivider).padding(.leading, 48)

                        NavigationLink {
                            SyncHealthView()
                        } label: {
                            menuRow(icon: "stethoscope", iconColor: .appAccent, title: "Sync Health & Diagnostics")
                        }

                        Divider().background(Color.appDivider).padding(.leading, 48)
                        
                        // Clear Cache Row
                        Button(action: {
                            APHaptic.trigger()
                            isClearingCache = true
                            NetworkService.shared.clearCache()
                            Task {
                                await NetworkService.shared.refreshAll()
                                await MainActor.run {
                                    isClearingCache = false
                                    statusMessage = "cache_cleared_success".localized(for: appLanguage)
                                    showStatusMessage = true
                                }
                            }
                        }) {
                            HStack(spacing: APSpacing.md) {
                                iconContainer(name: "sparkles", color: .appAccent)
                                Text("clear_cache".localized(for: appLanguage))
                                    .font(.subheadline)
                                    .foregroundColor(.textPrimary)
                                Spacer()
                                if isClearingCache {
                                    ProgressView().tint(.appAccent)
                                } else {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.textTertiary)
                                }
                            }
                            .padding(.horizontal, APSpacing.md)
                            .padding(.vertical, 14)
                        }
                        .disabled(isClearingCache)
                        

                    }
                    .apCard(padding: 0)
                }
                
                // 5. Sign Out Button (Styled premium tinted card)
                Button(action: {
                    APHaptic.trigger()
                    showingSignOutAlert = true
                }) {
                    HStack(spacing: APSpacing.sm) {
                        Spacer()
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.headline)
                        Text("log_out".localized(for: appLanguage))
                            .font(.headline)
                            .fontWeight(.bold)
                        Spacer()
                    }
                    .foregroundColor(.appRose)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: APRadius.md, style: .continuous)
                            .fill(Color.appRose.opacity(0.12))
                    )
                }
                .padding(.top, APSpacing.md)
            }
            .padding()
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("more".localized(for: appLanguage))
        .navigationBarTitleDisplayMode(.large)
        .apNavBar()
        .onAppear {
            loadTodayAttendance()
        }
        .task(id: loggedInEmployeeId) {
            // Attendance can be recorded on the shop iPad while this tab stays
            // open. Periodically refresh the server-backed status so iPhone does
            // not keep presenting a stale "not clocked in" value.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard !Task.isCancelled else { break }
                loadTodayAttendance()
            }
        }
        .refreshable {
            loadTodayAttendance()
        }

        .alert("system_notification".localized(for: appLanguage), isPresented: $showStatusMessage) {
            Button("ok".localized(for: appLanguage), role: .cancel) { }
        } message: {
            Text(statusMessage)
        }
        .alert("log_out".localized(for: appLanguage), isPresented: $showingSignOutAlert) {
            Button("cancel".localized(for: appLanguage), role: .cancel) { }
            Button("log_out".localized(for: appLanguage), role: .destructive) {
                APHaptic.trigger()
                NetworkService.shared.dissociatePushTokenEmployee()
                UserDefaults.standard.set(false, forKey: "staff_is_clocked_in")
                loggedInEmployeeId = ""
                loggedInEmployee = nil
            }
        } message: {
            Text("sign_out_confirm_body".localized(for: appLanguage))
        }
    }
    
    // MARK: - Subviews
    
    private func profileHeaderCard(emp: Employee) -> some View {
        HStack(spacing: APSpacing.md) {
            ZStack {
                Circle()
                    .fill(APGradient.accent)
                    .frame(width: 60, height: 60)
                
                Text(String(emp.firstName.prefix(1)) + String(emp.lastName.prefix(1)))
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
            .shadow(color: Color(hex: "2D71F8").opacity(0.3), radius: 8, x: 0, y: 0)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("\(emp.firstName) \(emp.lastName)")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.textPrimary)
                
                HStack(spacing: 8) {
                    Text(emp.role.uppercased())
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.appAccent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.appAccent.opacity(0.1))
                        .cornerRadius(APRadius.sm)
                    
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.appGreen)
                            .frame(width: 6, height: 6)
                        Text("Active")
                            .font(.caption2)
                            .foregroundColor(.appGreen)
                            .fontWeight(.medium)
                    }

                    if isCurrentlyClockedIn, let inTime = clockInDateString {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.appGreen)
                                .frame(width: 6, height: 6)
                            Text("เข้างาน \(inTime)")
                                .font(.caption2)
                                .foregroundColor(.appGreen)
                                .fontWeight(.bold)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.appGreen.opacity(0.12))
                        .cornerRadius(APRadius.sm)
                    } else if clockOutDateString != nil {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.textTertiary)
                                .frame(width: 6, height: 6)
                            Text("ออกงานแล้ว")
                                .font(.caption2)
                                .foregroundColor(.textSecondary)
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.appSurfaceHigh)
                        .cornerRadius(APRadius.sm)
                    } else if attendanceLoadFailed {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text("ตรวจสอบสถานะไม่ได้")
                        }
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.appAmber)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.appAmber.opacity(0.12))
                        .cornerRadius(APRadius.sm)
                    } else {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.textTertiary)
                                .frame(width: 6, height: 6)
                            Text("ยังไม่เข้างาน")
                                .font(.caption2)
                                .foregroundColor(.textSecondary)
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.appSurfaceHigh)
                        .cornerRadius(APRadius.sm)
                    }
                }
            }
            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: APRadius.lg, style: .continuous)
                .fill(Color.appSurface)
                .shadow(color: Color.black.opacity(0.02), radius: 10, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: APRadius.lg, style: .continuous)
                .stroke(Color.appBorderSubtle, lineWidth: 1)
        )
    }
    
    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption2)
            .fontWeight(.bold)
            .foregroundColor(.textSecondary)
            .tracking(1.2)
            .padding(.leading, 8)
    }
    
    private func iconContainer(name: String, color: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(color.opacity(0.12))
                .frame(width: 32, height: 32)
            Image(systemName: name)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(color)
        }
    }
    
    private func menuRow(icon: String, iconColor: Color, title: String) -> some View {
        HStack(spacing: APSpacing.md) {
            iconContainer(name: icon, color: iconColor)
            
            Text(title)
                .font(.subheadline)
                .foregroundColor(.textPrimary)
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.textTertiary)
        }
        .padding(.horizontal, APSpacing.md)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private func diagnosticsValueRow(icon: String, iconColor: Color, title: String, value: String) -> some View {
        HStack(spacing: APSpacing.md) {
            iconContainer(name: icon, color: iconColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.textSecondary)
                Text(value)
                    .font(.system(.caption, design: value.contains("-") ? .monospaced : .default))
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .textSelection(.enabled)
            }
            Spacer()
        }
        .padding(.horizontal, APSpacing.md)
        .padding(.vertical, 12)
    }

    private func loadTodayAttendance() {
        guard let empId = loggedInEmployee?.id, !empId.isEmpty else { return }
        isLoadingAttendance = true
        Task {
            do {
                let cards = try await NetworkService.shared.fetchTimecards(for: empId)
                await MainActor.run {
                    let cal = Calendar.current
                    self.todayTimecard = cards.first { tc in
                        let d = Date(timeIntervalSince1970: tc.clockIn)
                        return cal.isDateInToday(d)
                    }
                    self.attendanceLoadFailed = false
                    self.isLoadingAttendance = false
                    UserDefaults.standard.set(
                        self.todayTimecard.map { $0.clockOut == nil || $0.clockOut == 0 } ?? false,
                        forKey: "staff_is_clocked_in"
                    )
                }
            } catch {
                await MainActor.run {
                    self.attendanceLoadFailed = true
                    self.isLoadingAttendance = false
                    UserDefaults.standard.set(false, forKey: "staff_is_clocked_in")
                }
            }
        }
    }
}
