import SwiftUI

struct MoreMenuView: View {
    @Binding var loggedInEmployee: Employee?
    
    @AppStorage("app_language") private var appLanguage = "en"
    @AppStorage("enable_notifications") private var enableNotifications = true
    @AppStorage("active_merchant_id") private var activeMerchantId = ""
    @AppStorage("logged_in_employee_id") private var loggedInEmployeeId = ""
    
    @State private var isStoreIdCopied = false
    @State private var isClearingCache = false
    @State private var showStatusMessage = false
    @State private var statusMessage = ""
    @State private var showingSignOutAlert = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: APSpacing.lg) {
                // 1. Premium Profile Header Card
                if let emp = loggedInEmployee {
                    profileHeaderCard(emp: emp)
                }
                
                // 2. Work & Schedule Section
                VStack(alignment: .leading, spacing: APSpacing.sm) {
                    sectionTitle("work_schedule".localized(for: appLanguage))
                    
                    VStack(spacing: 0) {
                        NavigationLink {
                            ShiftScheduleView()
                        } label: {
                            menuRow(icon: "calendar.badge.clock", iconColor: .appAccent, title: "schedule".localized(for: appLanguage))
                        }
                        
                        Divider().background(Color.appDivider).padding(.leading, 48)
                        
                        if let emp = loggedInEmployee {
                            NavigationLink {
                                TimecardView(employee: emp)
                            } label: {
                                menuRow(icon: "clock.badge.checkmark.fill", iconColor: .appTeal, title: "clock_in_out".localized(for: appLanguage))
                            }
                        }
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
                                menuRow(icon: "person.text.rectangle.fill", iconColor: .appAmber, title: "my_account".localized(for: appLanguage))
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
}
