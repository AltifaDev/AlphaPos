import SwiftUI
import SwiftData
import PhotosUI
import UIKit

struct SettingsView: View {
    @Binding var columnVisibility: NavigationSplitViewVisibility

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sessionManager: AppSessionManager

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedTopic: SettingTopic? = .appearance
    /// Entrance animation for first open only (cards / rows), not topic changes.
    @State private var isAnimated = false
    /// Collapse the Settings category column (independent of main app sidebar).
    @State private var isCategorySidebarCollapsed = false
    @State private var bannerPhase: CGFloat = 0
    @State private var bannerShine: CGFloat = -0.35

    init(columnVisibility: Binding<NavigationSplitViewVisibility> = .constant(.all)) {
        _columnVisibility = columnVisibility
    }

    enum SettingTopic: Hashable, Identifiable, CaseIterable {
        case appearance
        case tableSystem
        case queue
        case delivery
        case kds
        case printer
        case security
        case staffDevices
        case tax
        case receiptTemplate
        case currency
        case cloudBackup
        case diagnostics
        case featureConfig
        case systemOps

        var id: Self { self }
    }

    // Theme selection setting (needed for preview/theme operations if any, but main theme config is in subview)
    @AppStorage("app_theme") private var appTheme = AppTheme.dark.rawValue
    @AppStorage("app_text_size") private var appTextSize = AppTextSize.system.rawValue

    // Localization
    @AppStorage("app_language") private var appLanguageCode = "en"
    @EnvironmentObject private var lm: LocalizationManager

    // Account details
    // N4: is_logged_in is no longer used as an auth gate (AppSessionManager uses Keychain JWT)
    // kept as @AppStorage for backward-compat UI, but write-side must call signOutMerchant()
    @AppStorage("logged_in_email") private var loggedInEmail = "owner@alphapos.com"
    @AppStorage("logged_in_name") private var loggedInName = "Somchai Lertwit"
    @AppStorage("active_merchant_id") private var activeMerchantId = ""
    @AppStorage("offline_sync_mode") private var offlineSyncMode = false
    @State private var connectionText = "Checking..."
    @State private var isCheckingConnection = false

    // Change password state
    @State private var showingChangePasswordSheet = false
    @State private var showingChangeOwnerPinSheet = false
    @State private var showingChangeOwnerPinAuthorization = false
    @State private var newOwnerPin = ""

    // Delete account state
    @State private var showingDeleteConfirmAlert = false
    @State private var showingDeleteAuthorization = false
    @State private var showingLogoutPINSheet = false
    @State private var showingLogoutOptions = false
    @State private var showingUnsyncedDeleteWarning = false
    @State private var isDeletingAccount = false
    @State private var showingStatusAlert = false
    @State private var statusMessage = ""

    // Language Picker Sheet state
    @State private var showingLanguageSheet = false

    // Settings sub-view sheet states
    @State private var showingAppearanceSheet = false
    @State private var showingTableSystemSheet = false
    @State private var showingQueueSheet = false
    @State private var showingDeliverySheet = false
    @State private var showingKDSSheet = false
    @State private var showingPrinterSheet = false
    @State private var showingSecuritySheet = false
    @State private var showingStaffDevicesSheet = false
    @State private var showingTaxSheet = false
    @State private var showingReceiptTemplateSheet = false
    @State private var showingCurrencySheet = false
    @State private var showingDiagnosticsSheet = false
    @State private var showingSystemOpsSheet = false
    @State private var showingCloudBackupSheet = false
    @State private var showingSubscriptionSheet = false
    @State private var showingFeatureConfigSheet = false

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                ZStack {
                    settingsAmbientBackground

                    HStack(spacing: 10) {
                        if !isCategorySidebarCollapsed {
                            VStack(alignment: .leading, spacing: 0) {
                                HStack(spacing: 8) {
                                    Image(systemName: "gearshape.fill")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Text(L.Nav.tabSettings.t)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Spacer(minLength: 0)
                                    categorySidebarToggleButton(collapsed: false)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)

                                Divider().opacity(0.35)

                                sidebarView
                            }
                            .frame(width: 248)
                            .apLiquidGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .transition(.move(edge: .leading).combined(with: .opacity))
                        }

                        VStack(spacing: 4) {
                            settingsGlassToolbar

                            detailView(for: selectedTopic)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .apLiquidGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .settingsEntrance(isAnimated: isAnimated, direction: .up, delay: 0.08)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 0)
                    .padding(.bottom, 12)
                }
            } else {
                compactSettingsView
            }
        }
        .apSettingsTypography()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .alert("settings_db_operation".t, isPresented: $showingStatusAlert) {
            Button("ok_btn".t, role: .cancel) { }
        } message: {
            Text(statusMessage)
        }
        .alert("settings_delete_store_title".t, isPresented: $showingDeleteConfirmAlert) {
            Button("cancel".t, role: .cancel) { }
            Button("settings_delete_store_confirm".t, role: .destructive) {
                performAccountDeletion()
            }
        } message: {
            Text("settings_delete_store_warning".t)
        }
        .confirmationDialog(
            "ออกจากระบบ",
            isPresented: $showingLogoutOptions,
            titleVisibility: .visible
        ) {
            Button("ออกจากระบบและลบข้อมูลร้านออกจากเครื่อง", role: .destructive) {
                requestLocalDataRemoval()
            }
            Button("cancel".t, role: .cancel) { }
        } message: {
            Text("เพื่อป้องกันข้อมูลข้ามร้าน ระบบจะล้างข้อมูลร้านและข้อมูลยืนยันตัวตนออกจากอุปกรณ์นี้ทุกครั้ง")
        }
        .alert("มีข้อมูลที่ยังไม่ Sync", isPresented: $showingUnsyncedDeleteWarning) {
            Button("ยกเลิก", role: .cancel) { }
            Button("ลบข้อมูลที่ยังไม่ Sync", role: .destructive) {
                performLogout()
            }
        } message: {
            Text("ข้อมูลที่ยังไม่ส่งขึ้น Server จะกู้คืนไม่ได้")
        }
        .sheet(isPresented: $showingChangePasswordSheet) {
            ChangePasswordSheet(isPresented: $showingChangePasswordSheet)
        }
        .sheet(isPresented: $showingLogoutPINSheet) {
            ManagerPINVerificationSheet(
                isPresented: $showingLogoutPINSheet,
                onSuccess: {
                    DispatchQueue.main.async {
                        showingLogoutOptions = true
                    }
                },
                allowStoreOwnerPin: true
            )
        }
        .sheet(isPresented: $showingChangeOwnerPinAuthorization) {
            ManagerPINVerificationSheet(
                isPresented: $showingChangeOwnerPinAuthorization,
                onSuccess: { showingChangeOwnerPinSheet = true },
                allowStoreOwnerPin: true,
                ownerOnly: true
            )
        }
        .sheet(isPresented: $showingDeleteAuthorization) {
            ManagerPINVerificationSheet(
                isPresented: $showingDeleteAuthorization,
                onSuccess: { showingDeleteConfirmAlert = true },
                allowStoreOwnerPin: true,
                ownerOnly: true
            )
        }
        .alert("settings_change_owner_pin".t, isPresented: $showingChangeOwnerPinSheet) {
            SecureField("settings_new_pin_hint".t, text: $newOwnerPin)
            Button("save".t, action: saveNewOwnerPin)
            Button("cancel".t, role: .cancel) { newOwnerPin = "" }
        } message: {
            Text("settings_owner_pin_desc".t)
        }
        .fullScreenCover(isPresented: $showingSubscriptionSheet) {
            NavigationStack {
                SubscriptionSettingsView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button { showingSubscriptionSheet = false } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }
                    }
            }
        }
        .sheet(isPresented: $showingLanguageSheet) {
            LanguagePickerSheet(lm: lm)
        }
        .onAppear {
            OfflineSyncModeController.enforcePlanPolicy(modelContext: modelContext)
            offlineSyncMode = OfflineSyncModeController.isEnabled
            isAnimated = false
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.52, dampingFraction: 0.86)) {
                    isAnimated = true
                }
            }
            startSettingsBannerAnimation()
        }
        .onDisappear {
            isAnimated = false
        }
        .appTextSize(AppTextSize(rawValue: appTextSize) ?? .system)
    }

    private var settingsAmbientBackground: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            LinearGradient(
                colors: [
                    Color.primary.opacity(0.04),
                    Color.clear,
                    Color.primary.opacity(0.03)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
    }

    /// Compact glass toolbar: category toggle + title.
    /// Main nav sidebar uses the global bottom-leading control (never overlaps this bar).
    private var settingsGlassToolbar: some View {
        HStack(spacing: 8) {
            if isCategorySidebarCollapsed {
                categorySidebarToggleButton(collapsed: true)
            }

            ZStack {
                Circle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 28, height: 28)
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .scaleEffect(0.97 + bannerPhase * 0.04)
            }

            Text("settings_banner_title".t)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 6)

            Text(topicTitle(for: selectedTopic))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .apLiquidGlass(in: Capsule())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 44)
        .apLiquidGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(alignment: .leading) {
            // Subtle shine sweep kept for life — does not move content text vertically
            LinearGradient(
                colors: [
                    Color.white.opacity(0),
                    Color.white.opacity(0.18),
                    Color.white.opacity(0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 80)
            .offset(x: bannerShine * 360)
            .mask(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .allowsHitTesting(false)
        }
        .settingsEntrance(isAnimated: isAnimated, direction: .down, delay: 0)
        .clipped()
    }

    private func categorySidebarToggleButton(collapsed: Bool) -> some View {
        Button {
            APHaptic.trigger()
            withAnimation(.easeInOut(duration: 0.22)) {
                isCategorySidebarCollapsed.toggle()
            }
        } label: {
            Image(systemName: collapsed ? "rectangle.split.2x1" : "rectangle.split.2x1.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .apLiquidGlass(interactive: true, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(collapsed ? "Show settings list" : "Hide settings list")
    }

    private func selectTopic(_ topic: SettingTopic) {
        guard topic != selectedTopic else { return }
        selectedTopic = topic
        APHaptic.trigger()
    }

    private func startSettingsBannerAnimation() {
        withAnimation(.easeInOut(duration: 4.2).repeatForever(autoreverses: true)) {
            bannerPhase = 1
        }
        withAnimation(.linear(duration: 3.4).repeatForever(autoreverses: false)) {
            bannerShine = 1.15
        }
    }

    private func topicTitle(for topic: SettingTopic?) -> String {
        switch topic {
        case .appearance: return L.Sections.appearance.t
        case .tableSystem: return L.Sections.tableSystem.t
        case .queue: return L.Sections.queueSystem.t
        case .delivery: return lm.currentLanguage == .thai ? "ตั้งค่าเดลิเวอรี่" : "Delivery Settings"
        case .kds: return L.Sections.kds.t
        case .printer: return L.Sections.printer.t
        case .security: return L.Sections.security.t
        case .staffDevices: return L.Sections.linkStaff.t
        case .tax: return L.Sections.taxRates.t
        case .receiptTemplate: return L.Sections.receiptTemplates.t
        case .currency: return L.Sections.currencyExchange.t
        case .cloudBackup: return lm.currentLanguage == .thai ? "สำรองและกู้คืนข้อมูล" : "Backup & Restore"
        case .diagnostics: return "settings_diagnostics".t
        case .featureConfig: return "settings_system_ops".t
        case .systemOps: return "settings_system_ops".t
        case .none: return L.Nav.tabSettings.t
        }
    }

    private var compactSettingsView: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    profileAndGeneralSections

                    // ── SECTION: SETTINGS DIRECTORY (TOPICS) ─────────────
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L.Sections.general.t)
                            .font(.system(size: 12))
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
        .alert("settings_db_operation".t, isPresented: $showingStatusAlert) {
            Button("ok_btn".t, role: .cancel) { }
        } message: {
            Text(statusMessage)
        }
        .alert("settings_delete_store_title".t, isPresented: $showingDeleteConfirmAlert) {
            Button("cancel".t, role: .cancel) { }
            Button("settings_delete_store_confirm".t, role: .destructive) {
                performAccountDeletion()
            }
        } message: {
            Text("settings_delete_store_warning".t)
        }
        .sheet(isPresented: $showingChangePasswordSheet) {
            ChangePasswordSheet(isPresented: $showingChangePasswordSheet)
        }
        .alert("settings_change_owner_pin".t, isPresented: $showingChangeOwnerPinSheet) {
            SecureField("settings_new_pin_hint".t, text: $newOwnerPin)
            Button("save".t, action: saveNewOwnerPin)
            Button("cancel".t, role: .cancel) { newOwnerPin = "" }
        } message: {
            Text("settings_owner_pin_desc".t)
        }
        .fullScreenCover(isPresented: $showingSubscriptionSheet) {
            NavigationStack {
                SubscriptionSettingsView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button { showingSubscriptionSheet = false } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }
                    }
            }
        }
        .task {
            OfflineSyncModeController.enforcePlanPolicy(modelContext: modelContext)
            offlineSyncMode = OfflineSyncModeController.isEnabled
            let connected = await NetworkManager.shared.isConnected()
            connectionText = (connected ? "sync_conn_online" : "sync_conn_offline").t
        }
    }

    @ViewBuilder
    private var sidebarView: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    let initials = getInitials(from: loggedInName)
                    ZStack {
                        Circle()
                            .fill(Color.appSurfaceHigh)
                            .frame(width: 34, height: 34)
                        Text(initials)
                            .font(.body.weight(.semibold))
                            .foregroundColor(.textSecondary)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(sessionManager.currentStaffSession?.displayName ?? loggedInName)
                            .font(.body.weight(.semibold))
                            .foregroundColor(.textPrimary)
                            .lineLimit(2)
                        Text(loggedInEmail)
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    Text(sessionManager.currentStaffSession?.roleName ?? L.Account.storeOwner.t)
                        .font(.caption.weight(.medium))
                        .foregroundColor(.textSecondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.appSurfaceHigh)
                        .clipShape(Capsule())

                    Spacer(minLength: 0)

                    Button {
                        showingLanguageSheet = true
                    } label: {
                        HStack(spacing: 5) {
                            let currentLang = AppLanguage(rawValue: lm.languageCode) ?? .english
                            Text(currentLang.flag)
                                .font(.body)
                            Text(currentLang.displayName)
                                .font(.body.weight(.medium))
                        }
                        .foregroundColor(.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.appSurfaceHigh, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .settingsEntrance(isAnimated: isAnimated, direction: .down, delay: 0.02)

            Divider().opacity(0.35)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 1) {
                    sidebarRow(topic: .appearance, title: L.Sections.appearance.t, icon: "paintbrush.fill", index: 0)
                    sidebarRow(topic: .tableSystem, title: L.Sections.tableSystem.t, icon: "tablecells.fill", index: 1)
                    sidebarRow(topic: .queue, title: L.Sections.queueSystem.t, icon: "list.number", index: 2)
                    sidebarRow(topic: .delivery, title: lm.currentLanguage == .thai ? "ตั้งค่าเดลิเวอรี่" : "Delivery Settings", icon: "shippingbox.fill", index: 3)
                    sidebarRow(topic: .kds, title: L.Sections.kds.t, icon: "flame.fill", index: 4)
                    sidebarRow(topic: .printer, title: L.Sections.printer.t, icon: "printer.fill", index: 4)
                    sidebarRow(topic: .security, title: L.Sections.security.t, icon: "lock.shield.fill", index: 5)
                    sidebarRow(topic: .staffDevices, title: L.Sections.linkStaff.t, icon: "qrcode", index: 6)
                    sidebarRow(topic: .tax, title: L.Sections.taxRates.t, icon: "percent", index: 7)
                    sidebarRow(topic: .receiptTemplate, title: L.Sections.receiptTemplates.t, icon: "doc.text.fill", index: 8)
                    sidebarRow(topic: .currency, title: L.Sections.currencyExchange.t, icon: "dollarsign.circle.fill", index: 9)
                    sidebarRow(topic: .cloudBackup, title: lm.currentLanguage == .thai ? "สำรองและกู้คืนข้อมูล" : "Backup & Restore", icon: "externaldrive.badge.icloud", index: 10)
                    sidebarRow(topic: .diagnostics, title: "settings_diagnostics".t, icon: "waveform.path.ecg", index: 11)
                    sidebarRow(topic: .featureConfig, title: "settings_system_ops".t, icon: "slider.horizontal.3", index: 12)
                    sidebarRow(topic: .systemOps, title: L.Sections.systemOps.t, icon: "arrow.triangle.2.circlepath.circle.fill", index: 13)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }

            Divider().background(Color.appDivider)

            VStack(spacing: 4) {
                Button(action: handleLogout) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.right.square")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.appRose)
                        Text(L.Account.signOut.t)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.appRose)
                        Spacer()
                    }
                    .padding(.vertical, 7)
                    .padding(.horizontal, 10)
                    .background(Color.appRose.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)

                Button(action: requestAccountDeletion) {
                    HStack(spacing: 8) {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundColor(.textTertiary)
                        Text(L.Account.deleteAccount.t)
                            .font(.system(size: 12))
                            .foregroundColor(.textSecondary)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .settingsEntrance(isAnimated: isAnimated, direction: .up, delay: 0.16)
        }
    }

    private func sidebarRow(topic: SettingTopic, title: String, icon: String, index: Int) -> some View {
        let isSelected = selectedTopic == topic
        let entranceDirection: SettingsEntranceDirection = index % 2 == 0 ? .up : .down
        return Button {
            selectTopic(topic)
        } label: {
            HStack(spacing: 10) {
                        Image(systemName: icon)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )

                Text(title)
                    .font(.body.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .settingsEntrance(isAnimated: isAnimated, direction: entranceDirection, delay: 0.04 + Double(index) * 0.025)
    }

    @ViewBuilder
    private func detailView(for topic: SettingTopic?) -> some View {
        if let topic = topic {
            switch topic {
            case .appearance: AppearanceSettingsView(embedded: true)
            case .tableSystem: TableSystemSettingsView()
            case .queue: QueueSettingsView()
            case .delivery: DeliveryPlatformSettingsView()
            case .kds: KDSSettingsView()
            case .printer: PrinterSettingsView()
            case .security: SecuritySettingsView(embedded: true)
            case .staffDevices: StaffDevicesSettingsView()
            case .tax: TaxSettingsView()
            case .receiptTemplate: ReceiptTemplateSettingsView()
            case .currency: CurrencySettingsView()
            case .cloudBackup: CloudBackupSettingsView()
            case .diagnostics: SystemDiagnosticsView()
            case .featureConfig: SystemFeatureConfigView()
            case .systemOps: SystemOpsSettingsView()
            }
        } else {
            ContentUnavailableView("settings_select_title".t, systemImage: "gear", description: Text("settings_select_desc".t))
        }
    }

    @ViewBuilder
    private var profileAndGeneralSections: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L.Sections.account.t)
                .font(.system(size: 12))
                .fontWeight(.bold)
                .foregroundColor(.appAccent)
                .tracking(1.0)

            VStack(spacing: 16) {
                // User Info row
                HStack(spacing: 16) {
                    let initials = getInitials(from: loggedInName)
                    ZStack {
                        Circle()
                            .fill(APGradient.accent)
                            .frame(width: 54, height: 54)
                            .shadow(color: Color.appAccent.opacity(0.3), radius: 6)
                        Text(initials)
                            .font(.system(size: 12, weight: .semibold))
                            .fontWeight(.black)
                            .foregroundColor(.white)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(sessionManager.currentStaffSession?.displayName ?? loggedInName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.textPrimary)
                        Text(loggedInEmail)
                            .font(.system(size: 12))
                            .foregroundColor(.textSecondary)
                    }

                    Spacer()

                    Text(sessionManager.currentStaffSession?.roleName ?? L.Account.storeOwner.t)
                        .font(.system(size: 12))
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
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.appAccent)
                            .frame(width: 32, height: 32)
                            .background(Color.appAccent.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(L.Language.selectLanguage.t)
                                .font(.system(size: 12))
                                .foregroundColor(.textPrimary)
                            let currentLang = AppLanguage(rawValue: lm.languageCode) ?? .english
                            Text("\(currentLang.flag)  \(currentLang.displayName)")
                                .font(.system(size: 12))
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
                    Button(action: { showingChangePasswordSheet = true }) {
                        HStack {
                            Label(L.Account.changePassword.t, systemImage: "key.fill")
                                .foregroundColor(.textPrimary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                                .foregroundColor(.textSecondary)
                        }
                    }

                    Divider()
                        .background(Color.appDivider)

                    VStack(alignment: .leading, spacing: 6) {
                        Button(action: requestOwnerPinChange) {
                            HStack {
                                Label("settings_change_owner_pin".t, systemImage: "lock.ipad")
                                    .foregroundColor(.textPrimary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12))
                                    .foregroundColor(.textSecondary)
                            }
                        }

                        if KeychainManager.shared.isDefaultPinActive() {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.shield.fill")
                                    .foregroundColor(.appRose)
                                Text("settings_default_pin_warning".t)
                                    .font(.system(size: 12))
                                    .foregroundColor(.appRose)
                            }
                            .padding(.leading, 8)
                        }
                    }

                    Divider()
                        .background(Color.appDivider)

                    Button(action: { showingSubscriptionSheet = true }) {
                        HStack {
                            Label("settings_subscription_billing".t, systemImage: "creditcard.fill")
                                .foregroundColor(.textPrimary)
                            Spacer()
                            if let tier = MerchantAuthManager.shared.subscriptionTier {
                                Text((tier == "offline_perpetual" ? "settings_tier_perpetual" : tier == "offline_subscription" ? "settings_tier_subscription" : "settings_tier_cloud").t)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.appAccent)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.appAccent.opacity(0.12))
                                    .cornerRadius(6)
                            }
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                                .foregroundColor(.textSecondary)
                        }
                    }

                    Divider()
                        .background(Color.appDivider)

                    Button(action: handleLogout) {
                        HStack {
                            Label(L.Account.signOut.t, systemImage: "arrow.right.square.fill")
                                .foregroundColor(.textPrimary)
                            Spacer()
                        }
                    }

                    Divider()
                        .background(Color.appDivider)

                    Button(action: requestAccountDeletion) {
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
            Text("settings_connectivity_sync".t)
                .font(.system(size: 12))
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
                            Text((offlineSyncMode ? "settings_offline_title" : "settings_online_title").t)
                                .font(.system(size: 12))
                                .foregroundColor(.textPrimary)
                        }
                        Text(
                            OfflineSyncModeController.isToggleLockedByPlan
                                ? "settings_offline_locked_by_plan".t
                                : (offlineSyncMode ? "settings_offline_desc" : "settings_online_desc").t
                        )
                            .font(.system(size: 12))
                            .foregroundColor(
                                OfflineSyncModeController.isToggleLockedByPlan
                                    ? .orange
                                    : (offlineSyncMode ? .orange : .textSecondary)
                            )
                    }
                }
                .tint(.appAccent)
                .disabled(OfflineSyncModeController.isToggleLockedByPlan)
                .onChange(of: offlineSyncMode) { _, newValue in
                    if OfflineSyncModeController.isToggleLockedByPlan {
                        OfflineSyncModeController.enforcePlanPolicy(modelContext: modelContext)
                        offlineSyncMode = true
                        return
                    }
                    APHaptic.trigger()
                    let applied = OfflineSyncModeController.setUserPreference(
                        isOffline: newValue,
                        modelContext: modelContext
                    )
                    offlineSyncMode = OfflineSyncModeController.isEnabled
                    if applied {
                        logOfflineModeChange(isOffline: OfflineSyncModeController.isEnabled)
                    }
                }

                if offlineSyncMode {
                    Text("การลบแอปจะลบข้อมูลที่ยังไม่ได้ Backup • ไปที่ สำรองและกู้คืนข้อมูล เพื่อสร้าง Cloud Snapshot")
                        .font(.caption)
                        .foregroundStyle(Color.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !offlineSyncMode {
                    Divider().background(Color.appDivider)

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("settings_connection_status".t)
                                .font(.system(size: 12))
                                .foregroundColor(.textPrimary)
                            Text(connectionText)
                                .font(.system(size: 12))
                                .foregroundColor(connectionText == "Online" || connectionText == "ออนไลน์" ? .appTeal : .appRose)
                        }
                        Spacer()
                        Button {
                            Task {
                                isCheckingConnection = true
                                NetworkManager.shared.invalidateConnectivityCache()
                                let connected = await NetworkManager.shared.isConnected()
                                connectionText = (connected ? "sync_conn_online" : "sync_conn_offline").t
                                isCheckingConnection = false
                            }
                        } label: {
                            if isCheckingConnection {
                                ProgressView()
                                    .tint(.appAccent)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 12))
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
                                        .font(.system(size: 12, weight: .semibold))
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
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Color.textSecondary)
                                }
                            }
                        }
                }
            }

            Divider().background(Color.appDivider).padding(.leading, 56)

            // 3. Queue System Configuration
            Button { showingQueueSheet = true } label: {
                SettingsRowView(title: L.Sections.queueSystem.t, icon: "list.number", color: .appAccent)
            }
            .buttonStyle(.plain)
            .fullScreenCover(isPresented: $showingQueueSheet) {
                NavigationStack {
                    QueueSettingsView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button { showingQueueSheet = false } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Color.textSecondary)
                                }
                            }
                        }
                }
            }

            Divider().background(Color.appDivider).padding(.leading, 56)

            Button { showingDeliverySheet = true } label: {
                SettingsRowView(title: "ตั้งค่าเดลิเวอรี่", icon: "shippingbox.fill", color: .appTeal)
            }
            .buttonStyle(.plain)
            .fullScreenCover(isPresented: $showingDeliverySheet) {
                NavigationStack {
                    DeliveryPlatformSettingsView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button { showingDeliverySheet = false } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(Color.textSecondary)
                                }
                            }
                        }
                }
            }

            Divider().background(Color.appDivider).padding(.leading, 56)

            // 4. KDS Station Configuration
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
                                        .font(.system(size: 12, weight: .semibold))
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
                                        .font(.system(size: 12, weight: .semibold))
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
                                        .font(.system(size: 12, weight: .semibold))
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
            .disabled(offlineSyncMode)
            .opacity(offlineSyncMode ? 0.45 : 1)
            .fullScreenCover(isPresented: $showingStaffDevicesSheet) {
                NavigationStack {
                    StaffDevicesSettingsView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button { showingStaffDevicesSheet = false } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 12, weight: .semibold))
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
                                        .font(.system(size: 12, weight: .semibold))
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
                                        .font(.system(size: 12, weight: .semibold))
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
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Color.textSecondary)
                                }
                            }
                        }
                }
            }

            Divider().background(Color.appDivider).padding(.leading, 56)

            // 9.5 System Feature Control
            Button { showingFeatureConfigSheet = true } label: {
                SettingsRowView(title: "settings_system_ops".t, icon: "slider.horizontal.3", color: .appAccent)
            }
            .buttonStyle(.plain)
            .fullScreenCover(isPresented: $showingFeatureConfigSheet) {
                NavigationStack {
                    SystemFeatureConfigView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button { showingFeatureConfigSheet = false } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Color.textSecondary)
                                }
                            }
                        }
                }
            }

            Divider().background(Color.appDivider).padding(.leading, 56)

            Button { showingCloudBackupSheet = true } label: {
                SettingsRowView(title: lm.currentLanguage == .thai ? "สำรองและกู้คืนข้อมูล" : "Backup & Restore", icon: "externaldrive.badge.icloud", color: .appAccent)
            }
            .buttonStyle(.plain)
            .fullScreenCover(isPresented: $showingCloudBackupSheet) {
                NavigationStack {
                    CloudBackupSettingsView()
                        .navigationTitle(lm.currentLanguage == .thai ? "สำรองและกู้คืนข้อมูล" : "Backup & Restore")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button { showingCloudBackupSheet = false } label: {
                                    Image(systemName: "xmark.circle.fill")
                                }
                            }
                        }
                }
            }

            Divider().background(Color.appDivider).padding(.leading, 56)

            // 9.6 Diagnostics
            Button { showingDiagnosticsSheet = true } label: {
                SettingsRowView(title: "settings_diagnostics".t, icon: "waveform.path.ecg", color: .appTeal)
            }
            .buttonStyle(.plain)
            .fullScreenCover(isPresented: $showingDiagnosticsSheet) {
                NavigationStack {
                    SystemDiagnosticsView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button { showingDiagnosticsSheet = false } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Color.textSecondary)
                                }
                            }
                        }
                }
            }

            Divider().background(Color.appDivider).padding(.leading, 56)

            // 10. System Operations
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
                                        .font(.system(size: 12, weight: .semibold))
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

    private func logOfflineModeChange(isOffline: Bool) {
        let mode = isOffline ? "offline" : "online"
        let actor = sessionManager.currentStaffSession?.displayName ?? loggedInName
        let deviceName = UIDevice.current.name
        let log = AuditLog(
            actionType: "sync_mode_changed",
            details: "Sync mode changed to \(mode) by \(actor) on \(deviceName) (merchant: \(activeMerchantId))",
            originalValue: isOffline ? 0 : 1,
            newValue: isOffline ? 1 : 0,
            createdAt: Date()
        )
        modelContext.insert(log)
        modelContext.saveWithLogging(label: #function)
    }

    private func saveNewOwnerPin() {
        let cleanPin = newOwnerPin.trimmingCharacters(in: .decimalDigits.inverted)
        guard cleanPin.count == 4 else {
            statusMessage = "settings_pin_invalid".t
            showingStatusAlert = true
            newOwnerPin = ""
            return
        }
        guard KeychainManager.isAcceptableOwnerPin(cleanPin) else {
            statusMessage = "owner_pin_weak_error".t
            showingStatusAlert = true
            newOwnerPin = ""
            return
        }
        if KeychainManager.shared.saveOwnerPin(cleanPin) {
            UserDefaults.standard.removeObject(forKey: "merchant_owner_pin")
            let log = AuditLog(
                actionType: "owner_pin_changed",
                details: "Owner PIN changed on \(UIDevice.current.name) (merchant: \(activeMerchantId))",
                createdAt: Date()
            )
            modelContext.insert(log)
            modelContext.saveWithLogging(label: #function)
            statusMessage = "settings_pin_saved".t
        } else {
            statusMessage = "settings_pin_save_failed".t
        }
        showingStatusAlert = true
        newOwnerPin = ""
    }

    private func requestOwnerPinChange() {
        APHaptic.trigger()
        if KeychainManager.shared.isOwnerPinConfigured() {
            showingChangeOwnerPinAuthorization = true
        } else {
            guard sessionManager.currentStaffSession == nil else {
                statusMessage = "Owner account ต้องเป็นผู้ตั้ง Owner PIN ครั้งแรก"
                showingStatusAlert = true
                return
            }
            // First-time owner setup has no previous PIN to verify.
            showingChangeOwnerPinSheet = true
        }
    }

    private func requestAccountDeletion() {
        APHaptic.trigger()
        guard KeychainManager.shared.isOwnerPinConfigured() else {
            statusMessage = "กรุณาตั้ง Owner PIN ก่อนลบร้าน"
            showingStatusAlert = true
            return
        }
        guard SyncEngine.shared.syncStatus != .syncing else {
            statusMessage = "กำลัง Sync ข้อมูล กรุณารอให้เสร็จก่อนลบร้าน"
            showingStatusAlert = true
            return
        }
        guard !SyncEngine.shared.hasPendingSyncData(in: modelContext) else {
            statusMessage = "ยังมีข้อมูลที่ไม่ได้ส่งขึ้น Server กรุณา Sync ให้เสร็จก่อนลบร้าน"
            showingStatusAlert = true
            return
        }
        showingDeleteAuthorization = true
    }

    private func handleLogout() {
        APHaptic.trigger()
        showingLogoutPINSheet = true
    }

    private func requestLocalDataRemoval() {
        guard SyncEngine.shared.syncStatus != .syncing else {
            statusMessage = "กำลัง Sync ข้อมูล กรุณารอให้เสร็จก่อนลบข้อมูลออกจากเครื่อง"
            showingStatusAlert = true
            return
        }
        if SyncEngine.shared.hasPendingSyncData(in: modelContext) {
            showingUnsyncedDeleteWarning = true
        } else {
            performLogout()
        }
    }

    private func performLogout() {
        SyncEngine.shared.cancelPendingSync()
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
                    isDeletingAccount = false
                    sessionManager.signOutMerchant(
                        modelContext: modelContext
                    )
                }
            } catch {
                await MainActor.run {
                    isDeletingAccount = false
                    statusMessage = LocalizationManager.shared.t("settings_gdpr_delete_failed", error.localizedDescription)
                    showingStatusAlert = true
                }
            }
        }
    }

}

private struct SystemDiagnosticsView: View {
    @AppStorage("active_merchant_id") private var activeMerchantId = ""
    @AppStorage("offline_sync_mode") private var offlineSyncMode = false
    @ObservedObject private var syncEngine = SyncEngine.shared
    @State private var connectionText = "Checking..."

    private var realtimeText: String {
        if offlineSyncMode { return "Disabled in Offline Mode" }
        return syncEngine.isRealtimeConnected ? "Connected" : "Disconnected"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("settings_diagnostics".t)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.textPrimary)

                VStack(spacing: 0) {
                    diagnosticRow("active_merchant_id", value: activeMerchantId.isEmpty ? "Not set" : activeMerchantId, monospaced: true)
                    Divider().padding(.leading, 16)
                    diagnosticRow("offline_sync_mode", value: offlineSyncMode ? "true (Offline)" : "false (Online)")
                    Divider().padding(.leading, 16)
                    diagnosticRow("realtime", value: realtimeText)
                    Divider().padding(.leading, 16)
                    diagnosticRow("last_sync_time", value: syncEngine.lastSyncedAt?.formatted(date: .abbreviated, time: .standard) ?? "Never")
                    Divider().padding(.leading, 16)
                    diagnosticRow("connection_check", value: connectionText)
                }
                .apCard(padding: 0)

                Button {
                    Task { await refreshConnection() }
                } label: {
                    Label("settings_refresh_diagnostics".t, systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.appAccent)
            }
            .padding()
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("settings_diagnostics".t)
        .navigationBarTitleDisplayMode(.inline)
        .apNavBar(background: Color.appBackground)
        .task { await refreshConnection() }
    }

    private func refreshConnection() async {
        NetworkManager.shared.invalidateConnectivityCache()
        let connected = await NetworkManager.shared.isConnected()
        await MainActor.run {
            connectionText = connected ? "Online" : "Offline"
        }
    }

    private func diagnosticRow(_ title: String, value: String, monospaced: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.textSecondary)
                .frame(width: 140, alignment: .leading)
            Text(value)
                .font(monospaced ? .system(.caption, design: .monospaced) : .caption)
                .foregroundColor(.textPrimary)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(title)
                .font(.system(size: 12))
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
                                    // Keep auth user_metadata in sync for future emails.
                                    if let token = MerchantAuthManager.shared.userAccessToken, !token.isEmpty {
                                        Task {
                                            await AuthService.shared.updatePreferredLanguage(
                                                accessToken: token,
                                                languageCode: lang.rawValue
                                            )
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 14) {
                                    Text(lang.flag)
                                        .font(.system(size: 12, weight: .bold))
                                        .frame(width: 40)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(lang.displayName)
                                            .font(.system(size: 12)).fontWeight(.medium)
                                            .foregroundColor(.textPrimary)
                                        Text(lang.rawValue.uppercased())
                                            .font(.system(size: 12)).foregroundColor(.textTertiary)
                                            .tracking(1.0)
                                    }
                                    Spacer()
                                    if lm.languageCode == lang.rawValue {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.appAccent)
                                            .font(.system(size: 12, weight: .semibold))
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
                        .font(.system(size: 12))
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
                                .font(.system(size: 12))
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
                                .font(.system(size: 12))
                                .foregroundColor(.appTeal)
                            Spacer()
                        }
                        .padding()
                        .background(Color.appTeal.opacity(0.1))
                        .cornerRadius(8)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("settings_current_password".t)
                            .font(.system(size: 12))
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
                        Text("settings_new_password".t)
                            .font(.system(size: 12))
                            .fontWeight(.bold)
                            .foregroundColor(.textSecondary)
                        SecureField("settings_password_min_8_ph".t, text: $newPassword)
                            .textFieldStyle(PlainTextFieldStyle())
                            .padding()
                            .background(Color.appSurfaceHigh)
                            .foregroundColor(.textPrimary)
                            .cornerRadius(8)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("settings_confirm_password".t)
                            .font(.system(size: 12))
                            .fontWeight(.bold)
                            .foregroundColor(.textSecondary)
                        SecureField("settings_confirm_password".t, text: $confirmNewPassword)
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
                            Text("settings_update_password".t)
                        }
                    }
                    .apGradientButton(gradient: APGradient.accent, shadow: APShadow.glow, disabled: isSaving || oldPassword.isEmpty || newPassword.isEmpty || confirmNewPassword.isEmpty)
                    .disabled(isSaving || oldPassword.isEmpty || newPassword.isEmpty || confirmNewPassword.isEmpty)
                }
                .padding(24)
            }
            .navigationTitle("change_password".t)
            .apNavBar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel".t) { isPresented = false }
                        .foregroundColor(.textPrimary)
                }
            }
        }
    }

    private func savePassword() {
        errorMessage = ""
        successMessage = ""

        if newPassword.count < 8 {
            errorMessage = "settings_password_min_8".t
            return
        }
        if newPassword != confirmNewPassword {
            errorMessage = "auth_error_mismatched_passwords".t
            return
        }

        isSaving = true
        Task {
            do {
                let email = UserDefaults.standard.string(forKey: "logged_in_email") ?? ""
                try await AuthService.shared.changePassword(
                    email: email,
                    currentPassword: oldPassword,
                    newPassword: newPassword
                )
                await MainActor.run {
                    isSaving = false
                    successMessage = "settings_password_changed".t
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

// MARK: - First-open card entrance (not topic transitions)

enum SettingsEntranceDirection {
    case up
    case down

    var offset: CGFloat {
        switch self {
        case .up: return 18
        case .down: return -18
        }
    }
}

private struct SettingsEntranceModifier: ViewModifier {
    let isAnimated: Bool
    let direction: SettingsEntranceDirection
    let delay: Double

    func body(content: Content) -> some View {
        content
            .opacity(isAnimated ? 1 : 0)
            .offset(y: isAnimated ? 0 : direction.offset)
            .animation(
                .spring(response: 0.48, dampingFraction: 0.86).delay(delay),
                value: isAnimated
            )
    }
}

extension View {
    fileprivate func settingsEntrance(
        isAnimated: Bool,
        direction: SettingsEntranceDirection,
        delay: Double
    ) -> some View {
        modifier(SettingsEntranceModifier(isAnimated: isAnimated, direction: direction, delay: delay))
    }
}
