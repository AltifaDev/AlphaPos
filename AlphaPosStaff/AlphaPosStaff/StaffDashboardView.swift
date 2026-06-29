import SwiftUI

struct StaffDashboardView: View {
    let employee: Employee
    @Binding var loggedInEmployee: Employee?
    @AppStorage("app_language") private var appLanguage = "en"
    
    @State private var timecards: [Timecard] = []
    @State private var isLoading = false
    
    @AppStorage("active_merchant_id") private var activeMerchantId = ""
    @State private var isStoreIdCopied = false
    @State private var showingResetAlert = false
    @State private var isResetting = false
    @State private var isClearingCache = false
    @State private var showStatusMessage = false
    @State private var statusMessage = ""
    @State private var showingSignOutAlert = false
    @AppStorage("enable_notifications") private var enableNotifications = true
    @AppStorage("logged_in_employee_id") private var loggedInEmployeeId = ""
    
    var totalHours: Double {
        timecards.filter { $0.clockOut != nil && $0.clockOut! > 0 }.map { card in
            (card.clockOut! - card.clockIn) / 3600.0
        }.reduce(0, +)
    }
    
    var totalEarnings: Double {
        if employee.employmentType == "hourly" {
            return totalHours * employee.payRate
        } else if employee.employmentType == "daily" {
            let calendar = Calendar.current
            let finishedCards = timecards.filter { $0.clockOut != nil && $0.clockOut! > 0 }
            let uniqueDays = Set(finishedCards.compactMap { card -> Date? in
                let date = Date(timeIntervalSince1970: card.clockIn)
                return calendar.startOfDay(for: date)
            })
            return Double(uniqueDays.count) * employee.payRate
        } else {
            // Monthly calculation: monthly rate pro-rated for hours worked (assuming 160 standard hours a month)
            return (totalHours / 160.0) * employee.payRate
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Loading overlay สำหรับ timecard (แสดงเมื่อ isLoading = true)
                    if isLoading {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.75)
                                .tint(.appAccent)
                            Text("loading_summary".localized(for: appLanguage))
                                .font(.caption.weight(.medium))
                                .foregroundColor(.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.appSurface)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    ScrollView {
                        VStack(spacing: APSpacing.lg) {
                            
                            // Profile Card
                            VStack(spacing: APSpacing.sm) {
                                ZStack {
                                    Circle()
                                        .fill(APGradient.accent)
                                        .frame(width: 80, height: 80)
                                    
                                    Text(String(employee.firstName.prefix(1)) + String(employee.lastName.prefix(1)))
                                        .font(.title).fontWeight(.bold)
                                        .foregroundColor(.white)
                                }
                                
                                Text("\(employee.firstName) \(employee.lastName)")
                                    .font(.title2).fontWeight(.black)
                                    .foregroundColor(.textPrimary)
                                
                                Text(employee.role)
                                    .font(.subheadline)
                                    .foregroundColor(.textSecondary)
                                
                                APBadge(text: {
                                    if employee.employmentType == "hourly" {
                                        return "hourly".localized(for: appLanguage).capitalized
                                    } else if employee.employmentType == "daily" {
                                        return "daily".localized(for: appLanguage).capitalized
                                    } else {
                                        return "monthly".localized(for: appLanguage).capitalized
                                    }
                                }(), color: .appTeal)
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .apCard()
                            
                            // Today's Summary Card — Quick access to DailySummaryView
                            NavigationLink {
                                DailySummaryView(employee: employee)
                            } label: {
                                HStack(spacing: APSpacing.md) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: APRadius.sm, style: .continuous)
                                            .fill(
                                                LinearGradient(
                                                    colors: [Color.appAccent.opacity(0.2), Color.appPurple.opacity(0.15)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                            .frame(width: 40, height: 40)
                                        Image(systemName: "chart.bar.doc.horizontal.fill")
                                            .font(.title3)
                                            .foregroundColor(.appAccent)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("todays_summary".localized(for: appLanguage))
                                            .font(.headline).fontWeight(.bold)
                                            .foregroundColor(.textPrimary)
                                        Text("daily_summary".localized(for: appLanguage))
                                            .font(.caption)
                                            .foregroundColor(.textSecondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.textTertiary)
                                }
                                .padding()
                                .apCard()
            }
                            
                            // Tip Tracker Card
                            NavigationLink {
                                TipTrackerView(employee: employee)
                            } label: {
                                HStack(spacing: APSpacing.md) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: APRadius.sm, style: .continuous)
                                            .fill(
                                                LinearGradient(
                                                    colors: [Color.appTeal.opacity(0.2), Color.appAmber.opacity(0.15)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                            .frame(width: 40, height: 40)
                                        Image(systemName: "banknote.fill")
                                            .font(.title3)
                                            .foregroundColor(.appTeal)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("tip_tracker".localized(for: appLanguage))
                                            .font(.headline).fontWeight(.bold)
                                            .foregroundColor(.textPrimary)
                                        Text("todays_tips".localized(for: appLanguage))
                                            .font(.caption)
                                            .foregroundColor(.textSecondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.textTertiary)
                                }
                                .padding()
                                .apCard()
                            }
                            
                            // Earnings & Hours Widgets
                            HStack(spacing: APSpacing.md) {
                                // Hours Card
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("hours_worked_label".localized(for: appLanguage))
                                        .font(.caption2).foregroundColor(.textSecondary)
                                    Text(String(format: "hours_worked_format".localized(for: appLanguage), totalHours))
                                        .font(.title3).fontWeight(.black)
                                        .foregroundColor(.appTeal)
                                }
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .apCard()
                                
                                // Earnings Card
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("accumulated_pay".localized(for: appLanguage))
                                        .font(.caption2).foregroundColor(.textSecondary)
                                    Text("฿\(Int(totalEarnings))")
                                        .font(.title3).fontWeight(.black)
                                        .foregroundColor(.appRose)
                                }
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .apCard()
                            }
                            
                            // Payroll Details
                            VStack(alignment: .leading, spacing: APSpacing.sm) {
                                Text("contract_details".localized(for: appLanguage))
                                    .font(.headline).fontWeight(.bold)
                                    .foregroundColor(.textPrimary)
                                
                                Divider().background(Color.appDivider)
                                
                                profileRow(label: "phone".localized(for: appLanguage), value: employee.phone ?? "N/A")
                                profileRow(label: "national_id".localized(for: appLanguage), value: employee.nationalId ?? "N/A")
                                profileRow(label: "pay_rate".localized(for: appLanguage), value: {
                                    if employee.employmentType == "hourly" {
                                        return String(format: "pay_rate_hourly_format".localized(for: appLanguage), Int(employee.payRate))
                                    } else if employee.employmentType == "daily" {
                                        return String(format: "pay_rate_daily_format".localized(for: appLanguage), Int(employee.payRate))
                                    } else {
                                        return String(format: "pay_rate_monthly_format".localized(for: appLanguage), Int(employee.payRate))
                                    }
                                }())
                            }
                            .padding()
                            .apCard()
                            
                            // Settings
                            VStack(alignment: .leading, spacing: APSpacing.sm) {
                                Text("settings_section".localized(for: appLanguage))
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.appAccent)
                                    .tracking(1.0)
                                
                                Divider().background(Color.appDivider)
                                
                                Toggle(isOn: $enableNotifications) {
                                    HStack(spacing: APSpacing.sm) {
                                        Image(systemName: "bell.fill")
                                            .foregroundColor(.appAccent)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("enable_notifications".localized(for: appLanguage))
                                                .font(.subheadline)
                                                .foregroundColor(.textPrimary)
                                            Text("enable_notifications_desc".localized(for: appLanguage))
                                                .font(.caption2)
                                                .foregroundColor(.textSecondary)
                                                .multilineTextAlignment(.leading)
                                        }
                                    }
                                }
                                .tint(.appAccent)
                            }
                            .padding()
                            .apCard()
                            
                            // Diagnostics & System Status
                            VStack(alignment: .leading, spacing: APSpacing.sm) {
                                Text("diagnostics_system_status".localized(for: appLanguage).uppercased())
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.appAccent)
                                    .tracking(1.0)
                                
                                Divider().background(Color.appDivider)
                                
                                HStack {
                                    Text("connection_status".localized(for: appLanguage))
                                        .font(.subheadline).foregroundColor(.textSecondary)
                                    Spacer()
                                    Text((NetworkService.shared.connectionError ? "offline_status" : "online_status").localized(for: appLanguage) + (NetworkService.shared.connectionError ? " 🔴" : " 🟢"))
                                        .font(.subheadline).fontWeight(.bold)
                                        .foregroundColor(NetworkService.shared.connectionError ? .appRose : .appTeal)
                                }
                                .padding(.vertical, 2)
                                
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("merchant_uuid_label".localized(for: appLanguage))
                                        .font(.caption2).foregroundColor(.textSecondary)
                                    
                                    HStack {
                                        Text(activeMerchantId.isEmpty ? "not_paired_status".localized(for: appLanguage) : activeMerchantId)
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundColor(.textPrimary)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.5)
                                        
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
                                    .padding(8)
                                    .background(Color.appSurfaceHigh)
                                    .cornerRadius(APRadius.sm)
                                }
                                
                                Divider().background(Color.appDivider)
                                    .padding(.vertical, 4)
                                
                                HStack(spacing: 12) {
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
                                        if isClearingCache {
                                            ProgressView().tint(.white)
                                        } else {
                                            Label("clear_cache".localized(for: appLanguage), systemImage: "trash.fill")
                                                .font(.caption)
                                                .fontWeight(.bold)
                                                .foregroundColor(.white)
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 10)
                                                .background(Color.appAccent)
                                                .cornerRadius(APRadius.sm)
                                        }
                                    }
                                    .disabled(isClearingCache)
                                    
                                    Button(action: {
                                        showingResetAlert = true
                                    }) {
                                        if isResetting {
                                            ProgressView().tint(.white)
                                        } else {
                                            Label("reset_server_data".localized(for: appLanguage), systemImage: "arrow.counterclockwise.circle.fill")
                                                .font(.caption)
                                                .fontWeight(.bold)
                                                .foregroundColor(.white)
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 10)
                                                .background(Color.appRose)
                                                .cornerRadius(APRadius.sm)
                                        }
                                    }
                                    .disabled(isResetting)
                                }
                            }
                            .padding()
                            .apCard()
                            
                            // Server Configuration Card
                            VStack(alignment: .leading, spacing: APSpacing.sm) {
                                Text("Server Configuration".uppercased())
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.appAccent)
                                    .tracking(1.0)
                                
                                Divider().background(Color.appDivider)
                                
                                Text("Supabase Server URL")
                                    .font(.caption)
                                    .foregroundColor(.textSecondary)
                                
                                TextField("http://119.59.99.163", text: Binding(
                                    get: { UserDefaults.standard.string(forKey: "dynamic_supabase_url") ?? AppConfig.supabaseURL.absoluteString },
                                    set: { UserDefaults.standard.set($0, forKey: "dynamic_supabase_url") }
                                ))
                                .textFieldStyle(.roundedBorder)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .foregroundColor(.textPrimary)
                                
                                Text("Note: Changing server addresses requires restarting the app to take effect.")
                                    .font(.caption2)
                                    .foregroundColor(.textSecondary)
                                    .italic()
                            }
                            .padding()
                            .apCard()
                            
                            // Sign Out
                            Button(action: {
                                APHaptic.trigger()
                                showingSignOutAlert = true
                            }) {
                                HStack(spacing: APSpacing.sm) {
                                    Image(systemName: "rectangle.portrait.and.arrow.right")
                                        .font(.headline)
                                    Text("log_out".localized(for: appLanguage))
                                        .font(.headline)
                                        .fontWeight(.bold)
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, APSpacing.md)
                                .background(
                                    RoundedRectangle(cornerRadius: APRadius.md, style: .continuous)
                                        .fill(Color(hex: "FC4A4A"))
                                )
                                .shadow(color: Color(hex: "FC4A4A").opacity(0.35), radius: 16, x: 0, y: 0)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("staff_space".localized(for: appLanguage))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    languageMenu
                }
            }
            .onAppear {
                loadTimecardHistory()
            }
            .alert("wipe_transactions_title".localized(for: appLanguage), isPresented: $showingResetAlert) {
                Button("cancel".localized(for: appLanguage), role: .cancel) { }
                Button("yes_wipe".localized(for: appLanguage), role: .destructive) {
                    APHaptic.trigger()
                    isResetting = true
                    Task {
                        do {
                            _ = try await NetworkService.shared.wipeRemoteTransactionsAndSessions()
                            await NetworkService.shared.refreshAll()
                            await MainActor.run {
                                isResetting = false
                                statusMessage = "wipe_success".localized(for: appLanguage)
                                showStatusMessage = true
                            }
                        } catch {
                            await MainActor.run {
                                isResetting = false
                                statusMessage = "\("wipe_failed_prefix".localized(for: appLanguage)) \(error.localizedDescription)"
                                showStatusMessage = true
                            }
                        }
                    }
                }
            } message: {
                Text("wipe_transactions_body".localized(for: appLanguage))
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
                    loggedInEmployeeId = ""
                    loggedInEmployee = nil
                }
            } message: {
                Text("sign_out_confirm_body".localized(for: appLanguage))
            }
        }
    }
    
    private var languageMenu: some View {
        Menu {
            ForEach(AppLanguage.allCases) { lang in
                Button(action: {
                    APHaptic.trigger()
                    appLanguage = lang.rawValue
                }) {
                    HStack {
                        Text(lang.flag + " " + lang.displayName)
                        if appLanguage == lang.rawValue {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(AppLanguage(rawValue: appLanguage)?.flag ?? "🇺🇸")
                Text((AppLanguage(rawValue: appLanguage)?.rawValue.uppercased() ?? "EN"))
                    .font(.caption)
                    .fontWeight(.bold)
            }
            .foregroundColor(.appAccent)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color.appSurface)
                    .shadow(color: Color.black.opacity(0.1), radius: 4)
            )
            .overlay(
                Capsule()
                    .stroke(Color.appBorderSubtle, lineWidth: 1)
            )
        }
    }
    
    private func profileRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline).foregroundColor(.textSecondary)
            Spacer()
            Text(value)
                .font(.subheadline).foregroundColor(.textPrimary)
        }
        .padding(.vertical, 2)
    }
    
    private func loadTimecardHistory() {
        isLoading = true
        Task {
            do {
                let list = try await NetworkService.shared.fetchTimecards(for: employee.id)
                await MainActor.run {
                    self.timecards = list
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.statusMessage = "Could not load timecard data. Check connection."
                    self.showStatusMessage    = true
                }
            }
        }
    }
}
