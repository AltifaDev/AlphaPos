import SwiftUI
import SwiftData
import PhotosUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sessionManager: AppSessionManager
    
    // Theme selection setting (needed for preview/theme operations if any, but main theme config is in subview)
    @AppStorage("app_theme") private var appTheme = AppTheme.dark.rawValue
    
    // Localization
    @AppStorage("app_language") private var appLanguageCode = "en"
    @EnvironmentObject private var lm: LocalizationManager
    
    // Account details
    // N4: is_logged_in is no longer used as an auth gate (AppSessionManager uses Keychain JWT)
    // kept as @AppStorage for backward-compat UI, but write-side must call signOutMerchant()
    @AppStorage("logged_in_email") private var loggedInEmail = "owner@alphapos.com"
    @AppStorage("logged_in_name") private var loggedInName = "Somchai Lertwit"
    @AppStorage("active_merchant_id") private var activeMerchantId = "163350b0-056d-4d5e-b5d4-24e7aac5ab6d"
    @AppStorage("offline_sync_mode") private var offlineSyncMode = false
    @State private var connectionText = "Checking..."
    @State private var isCheckingConnection = false
    
    // Change password state
    @State private var showingChangePasswordSheet = false
    @State private var showingChangeOwnerPinSheet = false
    @State private var newOwnerPin = ""
    
    // Delete account state
    @State private var showingDeleteConfirmAlert = false
    @State private var isDeletingAccount = false
    @State private var showingStatusAlert = false
    @State private var statusMessage = ""
    
    // Language Picker Sheet state
    @State private var showingLanguageSheet = false

    // Settings sub-view sheet states
    @State private var showingAppearanceSheet = false
    @State private var showingTableSystemSheet = false
    @State private var showingKDSSheet = false
    @State private var showingPrinterSheet = false
    @State private var showingSecuritySheet = false
    @State private var showingStaffDevicesSheet = false
    @State private var showingTaxSheet = false
    @State private var showingReceiptTemplateSheet = false
    @State private var showingCurrencySheet = false
    @State private var showingSystemOpsSheet = false
    @State private var showingSubscriptionSheet = false
    
    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    
                    // ── SECTION: ACCOUNT PROFILE & LANGUAGE ─────────────
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L.Sections.account.t)
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.appAccent)
                            .tracking(1.0)
                        
                        VStack(spacing: 16) {
                            // User Info row
                            HStack(spacing: 16) {
                                // Avatar circle with initials
                                let initials = getInitials(from: loggedInName)
                                ZStack {
                                    Circle()
                                        .fill(APGradient.accent)
                                        .frame(width: 54, height: 54)
                                        .shadow(color: Color.appAccent.opacity(0.3), radius: 6)
                                    Text(initials)
                                        .font(.title3)
                                        .fontWeight(.black)
                                        .foregroundColor(.white)
                                }
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(sessionManager.currentStaffSession?.displayName ?? loggedInName)
                                        .font(.headline)
                                        .foregroundColor(.textPrimary)
                                    Text(loggedInEmail)
                                        .font(.subheadline)
                                        .foregroundColor(.textSecondary)
                                }
                                
                                Spacer()
                                
                                // Role badge
                                Text(sessionManager.currentStaffSession?.roleName ?? L.Account.storeOwner.t)
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.appAccent)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.appAccent.opacity(0.12))
                                    .cornerRadius(APRadius.pill)
                            }
                            .padding(.vertical, 4)
                            
                            Divider()
                                .background(Color.appDivider)
                            
                            // Relocated Language Switcher directly below profile details
                            Button {
                                APHaptic.trigger()
                                showingLanguageSheet = true
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: "globe")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.appAccent)
                                        .frame(width: 32, height: 32)
                                        .background(Color.appAccent.opacity(0.10))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(L.Language.selectLanguage.t)
                                            .font(.body)
                                            .foregroundColor(.textPrimary)
                                        let currentLang = AppLanguage(rawValue: lm.languageCode) ?? .english
                                        Text("\(currentLang.flag)  \(currentLang.displayName)")
                                            .font(.caption)
                                            .foregroundColor(.textSecondary)
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.textTertiary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .sheet(isPresented: $showingLanguageSheet) {
                                LanguagePickerSheet(lm: lm)
                            }
                            
                            Divider()
                                .background(Color.appDivider)
                            
                            // Account actions
                            VStack(spacing: 12) {
                                // Change Password
                                Button(action: { showingChangePasswordSheet = true }) {
                                    HStack {
                                        Label(L.Account.changePassword.t, systemImage: "key.fill")
                                            .foregroundColor(.textPrimary)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.footnote)
                                            .foregroundColor(.textSecondary)
                                    }
                                }
                                
                                Divider()
                                    .background(Color.appDivider)
                                
                                // Change Owner PIN
                                VStack(alignment: .leading, spacing: 6) {
                                    Button(action: { showingChangeOwnerPinSheet = true }) {
                                        HStack {
                                            Label(lm.languageCode == "th" ? "เปลี่ยน PIN บัญชีร้านค้า" : "Change Store Owner PIN", systemImage: "lock.ipad")
                                                .foregroundColor(.textPrimary)
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.footnote)
                                                .foregroundColor(.textSecondary)
                                        }
                                    }
                                    
                                    if KeychainManager.shared.isDefaultPinActive() {
                                        HStack(spacing: 6) {
                                            Image(systemName: "exclamationmark.shield.fill")
                                                .foregroundColor(.appRose)
                                            Text(lm.languageCode == "th" ? "คำเตือน: รหัส PIN เริ่มต้น '8888' ไม่ปลอดภัย โปรดเปลี่ยนใหม่ทันที" : "Warning: Default PIN '8888' is insecure. Change it immediately.")
                                                .font(.caption2)
                                                .foregroundColor(.appRose)
                                        }
                                        .padding(.leading, 8)
                                    }
                                }
                                
                                Divider()
                                    .background(Color.appDivider)
                                
                                // Subscription & Billing
                                Button(action: { showingSubscriptionSheet = true }) {
                                    HStack {
                                        Label(lm.languageCode == "th" ? "แผนสมาชิกและการเรียกเก็บเงิน" : "Subscription & Billing", systemImage: "creditcard.fill")
                                            .foregroundColor(.textPrimary)
                                        Spacer()
                                        if let tier = MerchantAuthManager.shared.subscriptionTier {
                                            Text(tier == "offline_perpetual" ? (lm.languageCode == "th" ? "ออฟไลน์ ซื้อขาด" : "Offline Perpetual") : (tier == "offline_subscription" ? (lm.languageCode == "th" ? "ออฟไลน์ รายเดือน/ปี" : "Offline Sub") : (lm.languageCode == "th" ? "ออนไลน์ คลาวด์" : "Online Cloud")))
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundColor(.appAccent)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(Color.appAccent.opacity(0.12))
                                                .cornerRadius(6)
                                        }
                                        Image(systemName: "chevron.right")
                                            .font(.footnote)
                                            .foregroundColor(.textSecondary)
                                    }
                                }
                                
                                Divider()
                                    .background(Color.appDivider)
                                
                                // Sign Out
                                Button(action: handleLogout) {
                                    HStack {
                                        Label(L.Account.signOut.t, systemImage: "arrow.right.square.fill")
                                            .foregroundColor(.textPrimary)
                                        Spacer()
                                    }
                                }
                                
                                Divider()
                                    .background(Color.appDivider)
                                
                                // Delete Account
                                Button(action: { showingDeleteConfirmAlert = true }) {
                                    HStack {
                                        Label(L.Account.deleteAccount.t, systemImage: "exclamationmark.shield.fill")
                                            .foregroundColor(.appRose)
                                        Spacer()
                                    }
                                }
                            }
                        }
                        .apCard()
                    }
                    .padding(.horizontal)
                    
                    // ── SECTION: CONNECTION & SYNC ───────────────────────
                    VStack(alignment: .leading, spacing: 12) {
                        Text(lm.languageCode == "th" ? "การเชื่อมต่อและซิงค์" : "Connectivity & Sync")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.appAccent)
                            .tracking(1.0)
                        
                        VStack(spacing: 14) {
                            Toggle(isOn: $offlineSyncMode) {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(offlineSyncMode ? Color.orange : Color.appTeal)
                                            .frame(width: 8, height: 8)
                                        Text(offlineSyncMode 
                                             ? (lm.languageCode == "th" ? "โหมดออฟไลน์ (ไม่ซิงค์กับคลาวด์)" : "Offline Mode (Local Only)")
                                             : (lm.languageCode == "th" ? "โหมดออนไลน์ (ซิงค์อัตโนมัติ)" : "Online Mode (Auto-Sync)"))
                                            .font(.body)
                                            .foregroundColor(.textPrimary)
                                    }
                                    Text(offlineSyncMode 
                                         ? (lm.languageCode == "th" ? "ข้อมูลเก็บในเครื่องเท่านั้น ไม่ซิงค์กับคลาวด์ เหมาะสำหรับช่วงอินเทอร์เน็ตมีปัญหา" : "Data saved locally. Cloud sync is disabled. Best for unstable internet.")
                                         : (lm.languageCode == "th" ? "ข้อมูลจะซิงค์ขึ้น Supabase อัตโนมัติทุก 5 วินาที" : "Data synchronizes with Supabase automatically every 5 seconds."))
                                        .font(.caption2)
                                        .foregroundColor(offlineSyncMode ? .orange : .textSecondary)
                                }
                            }
                            .tint(.appAccent)
                            .onChange(of: offlineSyncMode) { _, newValue in
                                APHaptic.trigger()
                                UserDefaults.standard.set(true, forKey: "offline_mode_user_set")
                                NetworkManager.shared.simulateOffline = newValue
                                NetworkManager.shared.invalidateConnectivityCache()
                                if newValue {
                                    SyncEngine.shared.cancelPendingSync()
                                } else {
                                    NetworkManager.shared.simulateOffline = false
                                    SyncEngine.shared.startRealtimeSync(modelContext: modelContext)
                                    Task {
                                        await SyncEngine.shared.syncAll(modelContext: modelContext)
                                    }
                                }
                            }
                            
                            if !offlineSyncMode {
                                Divider().background(Color.appDivider)
                                
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(lm.languageCode == "th" ? "สถานะการเชื่อมต่อปัจจุบัน" : "Current Connection Status")
                                            .font(.body)
                                            .foregroundColor(.textPrimary)
                                        Text(connectionText)
                                            .font(.caption)
                                            .foregroundColor(connectionText == "Online" || connectionText == "ออนไลน์" ? .appTeal : .appRose)
                                    }
                                    Spacer()
                                    Button {
                                        Task {
                                            isCheckingConnection = true
                                            NetworkManager.shared.invalidateConnectivityCache()
                                            let connected = await NetworkManager.shared.isConnected()
                                            connectionText = connected 
                                                ? (lm.languageCode == "th" ? "ออนไลน์" : "Online")
                                                : (lm.languageCode == "th" ? "ออฟไลน์" : "Offline")
                                            isCheckingConnection = false
                                        }
                                    } label: {
                                        if isCheckingConnection {
                                            ProgressView()
                                                .tint(.appAccent)
                                        } else {
                                            Image(systemName: "arrow.clockwise")
                                                .font(.caption)
                                                .foregroundColor(.appAccent)
                                        }
                                    }
                                    .disabled(isCheckingConnection)
                                }
                            }
                        }
                        .apCard()
                    }
                    .padding(.horizontal)
                    
                    // ── SECTION: SETTINGS DIRECTORY (TOPICS) ─────────────
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L.Sections.general.t)
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.appAccent)
                            .tracking(1.0)
                        
                        settingsDirectoryList
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 32)
                }
                .padding(.vertical)
            }
        }
        .navigationTitle(L.Nav.tabSettings.t)
        .apNavBar(background: Color.appBackground)
        .alert("Database Operation", isPresented: $showingStatusAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(statusMessage)
        }
        .alert("Delete Store & Account?", isPresented: $showingDeleteConfirmAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Yes, WIPE Everything", role: .destructive) {
                performAccountDeletion()
            }
        } message: {
            Text("WARNING: This action is irreversible. All table layouts, session logs, order records, and configurations will be permanently purged from this device and from Supabase cloud servers (GDPR compliant).")
        }
        .sheet(isPresented: $showingChangePasswordSheet) {
            ChangePasswordSheet(isPresented: $showingChangePasswordSheet)
        }
        .alert(lm.languageCode == "th" ? "เปลี่ยน PIN บัญชีร้านค้า" : "Change Store Owner PIN", isPresented: $showingChangeOwnerPinSheet) {
            SecureField(lm.languageCode == "th" ? "ป้อน PIN ใหม่ (ตัวเลข 4 หลัก)" : "Enter new 4-digit PIN", text: $newOwnerPin)
            Button(lm.languageCode == "th" ? "บันทึก" : "Save", action: saveNewOwnerPin)
            Button(lm.languageCode == "th" ? "ยกเลิก" : "Cancel", role: .cancel) { newOwnerPin = "" }
        } message: {
            Text(lm.languageCode == "th" ? "กรุณาระบุรหัส PIN 4 หลักเพื่อความปลอดภัยในการเข้าสู่ระบบโหมดเจ้าของร้าน" : "Please enter a 4-digit security PIN for accessing owner mode.")
        }
        .fullScreenCover(isPresented: $showingSubscriptionSheet) {
            NavigationStack {
                SubscriptionSettingsView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button { showingSubscriptionSheet = false } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }
                    }
            }
        }
        .task {
            let connected = await NetworkManager.shared.isConnected()
            connectionText = connected 
                ? (lm.languageCode == "th" ? "ออนไลน์" : "Online")
                : (lm.languageCode == "th" ? "ออฟไลน์" : "Offline")
        }
    }
    
    @ViewBuilder
    private var settingsDirectoryList: some View {
        VStack(spacing: 0) {
            // 1. Appearance & Theme
            Button { showingAppearanceSheet = true } label: {
                SettingsRowView(title: L.Sections.appearance.t, icon: "paintbrush.fill", color: .appAccent)
            }
            .buttonStyle(.plain)
            .fullScreenCover(isPresented: $showingAppearanceSheet) {
                NavigationStack {
                    AppearanceSettingsView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button { showingAppearanceSheet = false } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(Color.textSecondary)
                                }
                            }
                        }
                }
            }
            
            Divider().background(Color.appDivider).padding(.leading, 56)
            
            // 2. Table System & Web Ordering
            Button { showingTableSystemSheet = true } label: {
                SettingsRowView(title: L.Sections.tableSystem.t, icon: "tablecells.fill", color: .appTeal)
            }
            .buttonStyle(.plain)
            .fullScreenCover(isPresented: $showingTableSystemSheet) {
                NavigationStack {
                    TableSystemSettingsView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button { showingTableSystemSheet = false } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(Color.textSecondary)
                                }
                            }
                        }
                }
            }
            
            Divider().background(Color.appDivider).padding(.leading, 56)
            
            // 3. KDS Station Configuration
            Button { showingKDSSheet = true } label: {
                SettingsRowView(title: L.Sections.kds.t, icon: "flame.fill", color: .appAmber)
            }
            .buttonStyle(.plain)
            .fullScreenCover(isPresented: $showingKDSSheet) {
                NavigationStack {
                    KDSSettingsView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button { showingKDSSheet = false } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(Color.textSecondary)
                                }
                            }
                        }
                }
            }
            
            Divider().background(Color.appDivider).padding(.leading, 56)
            
            // 4. Printer Setup & Routing
            Button { showingPrinterSheet = true } label: {
                SettingsRowView(title: L.Sections.printer.t, icon: "printer.fill", color: .indigo)
            }
            .buttonStyle(.plain)
            .fullScreenCover(isPresented: $showingPrinterSheet) {
                NavigationStack {
                    PrinterSettingsView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button { showingPrinterSheet = false } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(Color.textSecondary)
                                }
                            }
                        }
                }
            }
            
            Divider().background(Color.appDivider).padding(.leading, 56)
            
            // 5. Security & Replication
            Button { showingSecuritySheet = true } label: {
                SettingsRowView(title: L.Sections.security.t, icon: "lock.shield.fill", color: .purple)
            }
            .buttonStyle(.plain)
            .fullScreenCover(isPresented: $showingSecuritySheet) {
                NavigationStack {
                    SecuritySettingsView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button { showingSecuritySheet = false } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(Color.textSecondary)
                                }
                            }
                        }
                }
            }
            
            Divider().background(Color.appDivider).padding(.leading, 56)
            
            // 6. Link Staff Devices
            Button { showingStaffDevicesSheet = true } label: {
                SettingsRowView(title: L.Sections.linkStaff.t, icon: "qrcode", color: .appAccent)
            }
            .buttonStyle(.plain)
            .fullScreenCover(isPresented: $showingStaffDevicesSheet) {
                NavigationStack {
                    StaffDevicesSettingsView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button { showingStaffDevicesSheet = false } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(Color.textSecondary)
                                }
                            }
                        }
                }
            }
            
            Divider().background(Color.appDivider).padding(.leading, 56)
            
            // 7. Taxes & Fees
            Button { showingTaxSheet = true } label: {
                SettingsRowView(title: L.Sections.taxRates.t, icon: "percent", color: .appAmber)
            }
            .buttonStyle(.plain)
            .fullScreenCover(isPresented: $showingTaxSheet) {
                NavigationStack {
                    TaxSettingsView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button { showingTaxSheet = false } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(Color.textSecondary)
                                }
                            }
                        }
                }
            }
            
            Divider().background(Color.appDivider).padding(.leading, 56)
            
            // 8. Receipt Templates
            Button { showingReceiptTemplateSheet = true } label: {
                SettingsRowView(title: L.Sections.receiptTemplates.t, icon: "doc.text.fill", color: .blue)
            }
            .buttonStyle(.plain)
            .fullScreenCover(isPresented: $showingReceiptTemplateSheet) {
                NavigationStack {
                    ReceiptTemplateSettingsView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button { showingReceiptTemplateSheet = false } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(Color.textSecondary)
                                }
                            }
                        }
                }
            }
            
            Divider().background(Color.appDivider).padding(.leading, 56)
            
            // 9. Currencies & Exchange
            Button { showingCurrencySheet = true } label: {
                SettingsRowView(title: L.Sections.currencyExchange.t, icon: "dollarsign.circle.fill", color: .appTeal)
            }
            .buttonStyle(.plain)
            .fullScreenCover(isPresented: $showingCurrencySheet) {
                NavigationStack {
                    CurrencySettingsView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button { showingCurrencySheet = false } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(Color.textSecondary)
                                }
                            }
                        }
                }
            }
            
            Divider().background(Color.appDivider).padding(.leading, 56)
            
            // 10. System Operations & Data Seeding
            Button { showingSystemOpsSheet = true } label: {
                SettingsRowView(title: L.Sections.systemOps.t, icon: "arrow.triangle.2.circlepath.circle.fill", color: .appRose)
            }
            .buttonStyle(.plain)
            .fullScreenCover(isPresented: $showingSystemOpsSheet) {
                NavigationStack {
                    SystemOpsSettingsView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button { showingSystemOpsSheet = false } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(Color.textSecondary)
                                }
                            }
                        }
                }
            }
        }
        .apCard()
    }
    
    // MARK: - Actions
    
    private func getInitials(from name: String) -> String {
        let parts = name.split(separator: " ")
        if parts.isEmpty { return "O" }
        if parts.count == 1 { return String(parts[0].prefix(2)).uppercased() }
        let first = String(parts[0].prefix(1))
        let last = String(parts[parts.count - 1].prefix(1))
        return (first + last).uppercased()
    }
    
    private func saveNewOwnerPin() {
        let cleanPin = newOwnerPin.trimmingCharacters(in: .decimalDigits.inverted)
        if cleanPin.count == 4 {
            if KeychainManager.shared.saveOwnerPin(cleanPin) {
                // Clear legacy plaintext storage
                UserDefaults.standard.removeObject(forKey: "merchant_owner_pin")
                statusMessage = lm.languageCode == "th" ? "เปลี่ยน PIN เจ้าของร้านค้าสำเร็จแล้ว" : "Store owner PIN changed successfully."
            } else {
                statusMessage = lm.languageCode == "th" ? "ล้มเหลวในการบันทึก PIN พวงกุญแจ" : "Failed to save secure PIN to Keychain."
            }
            showingStatusAlert = true
        } else {
            statusMessage = lm.languageCode == "th" ? "ล้มเหลว: รหัส PIN ต้องเป็นตัวเลข 4 หลักเท่านั้น" : "Failed: PIN must be exactly 4 digits."
            showingStatusAlert = true
        }
        newOwnerPin = ""
    }
    
    private func handleLogout() {
        APHaptic.trigger()
        withAnimation(.easeInOut(duration: 0.25)) {
            sessionManager.signOutMerchant(modelContext: modelContext)
        }
    }
    
    private func performAccountDeletion() {
        APHaptic.trigger()
        isDeletingAccount = true
        
        Task {
            do {
                _ = try await NetworkManager.shared.deleteMerchantOnServer()
                
                await MainActor.run {
                    clearLocalCacheSilently()
                    isDeletingAccount = false
                    sessionManager.signOutMerchant(modelContext: modelContext)
                }
            } catch {
                await MainActor.run {
                    isDeletingAccount = false
                    statusMessage = "GDPR Account Deletion failed: \(error.localizedDescription)"
                    showingStatusAlert = true
                }
            }
        }
    }
    
    private func clearLocalCacheSilently() {
        if let tables = try? modelContext.fetch(FetchDescriptor<RestaurantTable>()) {
            for table in tables { modelContext.delete(table) }
        }
        if let orders = try? modelContext.fetch(FetchDescriptor<Order>()) {
            for order in orders { modelContext.delete(order) }
        }
        if let categories = try? modelContext.fetch(FetchDescriptor<Category>()) {
            for cat in categories { modelContext.delete(cat) }
        }
        if let items = try? modelContext.fetch(FetchDescriptor<MenuItem>()) {
            for item in items { modelContext.delete(item) }
        }
        modelContext.saveWithLogging(label: #function)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - SettingsRowView
// ─────────────────────────────────────────────────────────────────────────────
struct SettingsRowView: View {
    let title: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            
            Text(title)
                .font(.body)
                .foregroundColor(.textPrimary)
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.textTertiary)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - LanguagePickerSheet
// ─────────────────────────────────────────────────────────────────────────────
struct LanguagePickerSheet: View {
    @ObservedObject var lm: LocalizationManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(AppLanguage.allCases) { lang in
                            Button {
                                APHaptic.trigger()
                                dismiss()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                    lm.setLanguageWithReload(lang)
                                }
                            } label: {
                                HStack(spacing: 14) {
                                    Text(lang.flag)
                                        .font(.title2)
                                        .frame(width: 40)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(lang.displayName)
                                            .font(.body).fontWeight(.medium)
                                            .foregroundColor(.textPrimary)
                                        Text(lang.rawValue.uppercased())
                                            .font(.caption2).foregroundColor(.textTertiary)
                                            .tracking(1.0)
                                    }
                                    Spacer()
                                    if lm.languageCode == lang.rawValue {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.appAccent)
                                            .font(.title3)
                                            .transition(.scale.combined(with: .opacity))
                                    }
                                }
                                .padding(.vertical, 12)
                                .padding(.horizontal, 20)
                                .background(
                                    lm.languageCode == lang.rawValue
                                        ? Color.appAccent.opacity(0.06)
                                        : Color.clear
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .animation(.easeInOut(duration: 0.2), value: lm.languageCode)

                            if lang != AppLanguage.allCases.last {
                                Divider().padding(.leading, 74)
                            }
                        }
                    }
                    .apCard()
                    .padding()

                    Text(L.Language.desc.t)
                        .font(.caption2)
                        .foregroundColor(.textTertiary)
                        .padding(.horizontal)
                        .padding(.bottom, 20)
                }
            }
            .navigationTitle(L.Language.selectLanguage.t)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.Common.done.t) { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundColor(.appAccent)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - ChangePasswordSheet
// ─────────────────────────────────────────────────────────────────────────────
struct ChangePasswordSheet: View {
    @Binding var isPresented: Bool
    @State private var oldPassword = ""
    @State private var newPassword = ""
    @State private var confirmNewPassword = ""
    @State private var errorMessage = ""
    @State private var isSaving = false
    @State private var successMessage = ""
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                
                VStack(spacing: 20) {
                    if !errorMessage.isEmpty {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(.red)
                            Spacer()
                        }
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    if !successMessage.isEmpty {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.appTeal)
                            Text(successMessage)
                                .font(.caption)
                                .foregroundColor(.appTeal)
                            Spacer()
                        }
                        .padding()
                        .background(Color.appTeal.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Current Password")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.textSecondary)
                        SecureField("••••••••", text: $oldPassword)
                            .textFieldStyle(PlainTextFieldStyle())
                            .padding()
                            .background(Color.appSurfaceHigh)
                            .foregroundColor(.textPrimary)
                            .cornerRadius(8)
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("New Password")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.textSecondary)
                        SecureField("Min 8 characters", text: $newPassword)
                            .textFieldStyle(PlainTextFieldStyle())
                            .padding()
                            .background(Color.appSurfaceHigh)
                            .foregroundColor(.textPrimary)
                            .cornerRadius(8)
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Confirm New Password")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.textSecondary)
                        SecureField("Confirm new password", text: $confirmNewPassword)
                            .textFieldStyle(PlainTextFieldStyle())
                            .padding()
                            .background(Color.appSurfaceHigh)
                            .foregroundColor(.textPrimary)
                            .cornerRadius(8)
                    }
                    
                    Spacer()
                    
                    Button(action: savePassword) {
                        if isSaving {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Update Password")
                        }
                    }
                    .apGradientButton(gradient: APGradient.accent, shadow: APShadow.glow, disabled: isSaving || oldPassword.isEmpty || newPassword.isEmpty || confirmNewPassword.isEmpty)
                    .disabled(isSaving || oldPassword.isEmpty || newPassword.isEmpty || confirmNewPassword.isEmpty)
                }
                .padding(24)
            }
            .navigationTitle("Change Password")
            .apNavBar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                        .foregroundColor(.textPrimary)
                }
            }
        }
    }
    
    private func savePassword() {
        errorMessage = ""
        successMessage = ""
        
        if newPassword.count < 8 {
            errorMessage = "New password must be at least 8 characters long."
            return
        }
        if newPassword != confirmNewPassword {
            errorMessage = "New passwords do not match."
            return
        }
        
        isSaving = true
        Task {
            do {
                try await NetworkManager.shared.changeMerchantPassword(newPassword: newPassword)
                await MainActor.run {
                    isSaving = false
                    successMessage = "Your password has been changed successfully in Supabase."
                    APHaptic.trigger()
                    
                    // Dismiss after brief delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        isPresented = false
                    }
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = "Failed: \(error.localizedDescription)"
                }
            }
        }
    }
}
