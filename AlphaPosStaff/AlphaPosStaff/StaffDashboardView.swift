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
                            
                            // Diagnostics & System Status
                            VStack(alignment: .leading, spacing: APSpacing.sm) {
                                Text("DIAGNOSTICS & SYSTEM STATUS")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.appAccent)
                                    .tracking(1.0)
                                
                                Divider().background(Color.appDivider)
                                
                                HStack {
                                    Text("Connection Status")
                                        .font(.subheadline).foregroundColor(.textSecondary)
                                    Spacer()
                                    Text(NetworkService.shared.connectionError ? "Offline 🔴" : "Online 🟢")
                                        .font(.subheadline).fontWeight(.bold)
                                        .foregroundColor(NetworkService.shared.connectionError ? .appRose : .appTeal)
                                }
                                .padding(.vertical, 2)
                                
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Store ID (Merchant UUID)")
                                        .font(.caption2).foregroundColor(.textSecondary)
                                    
                                    HStack {
                                        Text(activeMerchantId.isEmpty ? "None (Not Paired)" : activeMerchantId)
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
                                                statusMessage = "Cache cleared and data re-synced successfully."
                                                showStatusMessage = true
                                            }
                                        }
                                    }) {
                                        if isClearingCache {
                                            ProgressView().tint(.white)
                                        } else {
                                            Label("Clear Cache", systemImage: "trash.fill")
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
                                            Label("Reset Server Data", systemImage: "arrow.counterclockwise.circle.fill")
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
                            
                            // Actions
                            Button(action: {
                                APHaptic.trigger()
                                loggedInEmployee = nil
                            }) {
                                Label("log_out".localized(for: appLanguage), systemImage: "arrow.uturn.left.circle.fill")
                                    .apGradientButton(gradient: APGradient.destructive)
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
            .alert("Wipe Transactions & Sessions?", isPresented: $showingResetAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Yes, Wipe", role: .destructive) {
                    APHaptic.trigger()
                    isResetting = true
                    Task {
                        do {
                            _ = try await NetworkService.shared.wipeRemoteTransactionsAndSessions()
                            await NetworkService.shared.refreshAll()
                            await MainActor.run {
                                isResetting = false
                                statusMessage = "All active sessions and orders wiped from Supabase. Tables reset to vacant."
                                showStatusMessage = true
                            }
                        } catch {
                            await MainActor.run {
                                isResetting = false
                                statusMessage = "Wipe failed: \(error.localizedDescription)"
                                showStatusMessage = true
                            }
                        }
                    }
                }
            } message: {
                Text("This will delete all active sessions, orders, and service requests on the server. Menu items and staff profiles will remain untouched.")
            }
            .alert("System Notification", isPresented: $showStatusMessage) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(statusMessage)
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
                }
            }
        }
    }
}
