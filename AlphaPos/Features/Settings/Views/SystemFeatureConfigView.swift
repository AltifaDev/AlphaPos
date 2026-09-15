import SwiftUI
import SwiftData

// MARK: - SystemFeatureConfigView
// ─────────────────────────────────────────────────────────────────────────────
// Operational feature flags (POS floorplan, tax, KDS, inventory, security).
// Payment tenders are NOT edited here — enterprise IA routes them to the
// Payments hub (single source of truth). This screen only deep-links there.
// ─────────────────────────────────────────────────────────────────────────────

struct SystemFeatureConfigView: View {
    @Environment(\.modelContext) private var modelContext

    // ── POS & Floorplan Features (payments live only under Payments hub) ─
    @AppStorage("enable_table_system") private var enableTableSystem = true
    @AppStorage("enable_web_ordering") private var enableWebOrdering = true
    @AppStorage("enable_tax") private var enableTax = true
    @AppStorage("enable_service_charge") private var enableServiceCharge = true
    @AppStorage("promotions_auto_apply") private var promotionsAutoApply = true
    @AppStorage("enable_realtime_stock_warning") private var enableRealtimeStockWarning = true
    @AppStorage("enable_pos_sound_effects") private var enablePOSSoundEffects = true
    @AppStorage("pos_sound_volume") private var posSoundVolume = 1.0
    @AppStorage("inventory_profile") private var inventoryProfile = "restaurant"
    @AppStorage("enable_inventory_stock_alerts") private var enableInventoryStockAlerts = true
    @AppStorage("auto_disable_oos_menu") private var autoDisableOOSMenu = false
    @AppStorage("enable_inventory_staff_push") private var enableInventoryStaffPush = true
    @AppStorage("enable_in_app_notification_sounds") private var enableInAppNotificationSounds = true

    // ── Kitchen Display System (KDS) ──────────────────────────────────
    @AppStorage("kds_show_kitchen") private var kdsShowKitchen = true
    @AppStorage("kds_show_bar") private var kdsShowBar = true
    @AppStorage("kds_auto_complete_enabled") private var kdsAutoCompleteEnabled = false
    @AppStorage("kds_sound_enabled") private var kdsSoundEnabled = true

    // ── Security & Advanced ───────────────────────────────────────────
    @AppStorage("require_manager_override_for_refund") private var requireManagerOverrideForRefund = true
    @AppStorage("offline_sync_mode") private var offlineSyncMode = false
    @AppStorage("developer_mode_enabled") private var developerModeEnabled = false
    @State private var openRouterApiKey = ""

    var body: some View {
        ScrollView {
            VStack(spacing: APSpacing.lg) {

                // Enterprise IA: tenders belong in Payments, not System Control.
                paymentsHubRedirectCard

                // Destructive data maintenance is kept behind its own screen
                // so category selection, merchant scope and owner PIN are visible.
                dataManagementCard

                // ═══════════════════════════════════════════════════════════
                // SECTION: ระบบ POS และผังโต๊ะ
                // ═══════════════════════════════════════════════════════════
                VStack(alignment: .leading, spacing: 0) {
                    sectionHeader(
                        title: "syscfg_section_pos".t,
                        icon: "banknote.fill",
                        color: .green
                    )

                    toggleRow(
                        title: "enable_table".t,
                        subtitle: "enable_table_desc".t,
                        isOn: $enableTableSystem
                    )
                    sectionDivider

                    toggleRow(
                        title: "enable_web_ordering".t,
                        subtitle: offlineSyncMode
                            ? "web_ordering_offline_unavailable".t
                            : "enable_web_desc".t,
                        isOn: $enableWebOrdering,
                        isDisabled: offlineSyncMode
                    )
                    sectionDivider

                    toggleRow(
                        title: "syscfg_vat_title".t,
                        subtitle: "syscfg_vat_desc".t,
                        isOn: $enableTax
                    )
                    sectionDivider

                    toggleRow(
                        title: "syscfg_service_charge_title".t,
                        subtitle: "syscfg_service_charge_desc".t,
                        isOn: $enableServiceCharge
                    )
                    sectionDivider

                    toggleRow(
                        title: "syscfg_promo_title".t,
                        subtitle: "syscfg_promo_desc".t,
                        isOn: $promotionsAutoApply
                    )
                    sectionDivider

                    toggleRow(
                        title: "syscfg_stock_warn_title".t,
                        subtitle: "syscfg_stock_warn_desc".t,
                        isOn: $enableRealtimeStockWarning
                    )
                    sectionDivider

                    toggleRow(
                        title: LocalizationManager.shared.currentLanguage == .thai ? "เสียงประกอบ POS (Sound Effects)" : "POS Sound Effects",
                        subtitle: LocalizationManager.shared.currentLanguage == .thai ? "ส่งเสียงบี๊บเมื่อกดเลือกสินค้า และเสียงแคชเชียร์ Cha-Ching เมื่อรับชำระเงินสำเร็จ" : "Play beep sound when adding items and cash register Cha-Ching when payment succeeds",
                        isOn: $enablePOSSoundEffects
                    )
                    if enablePOSSoundEffects {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(LocalizationManager.shared.currentLanguage == .thai ? "ระดับความดังเสียง (Volume)" : "Volume")
                                    .font(.system(size: 12))
                                    .fontWeight(.medium)
                                    .foregroundColor(.textPrimary)
                                Spacer()
                                Text("\(Int(posSoundVolume * 100))%")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundColor(.appAccent)
                            }

                            Slider(value: $posSoundVolume, in: 0.1...1.0, step: 0.05)
                                .tint(.appAccent)
                                .onChange(of: posSoundVolume) { _, _ in
                                    APSoundEffect.itemTap()
                                }

                            HStack(spacing: 12) {
                                Button {
                                    APSoundEffect.itemTap()
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "speaker.wave.2.fill")
                                        Text(LocalizationManager.shared.currentLanguage == .thai ? "ทดสอบเสียงบี๊บ (Beep)" : "Test Beep")
                                            .font(.system(size: 12, weight: .medium))
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.appAccent.opacity(0.12), in: Capsule())
                                    .foregroundColor(.appAccent)
                                }
                                .buttonStyle(.plain)

                                Button {
                                    APSoundEffect.paymentSuccess()
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "dollarsign.circle.fill")
                                        Text(LocalizationManager.shared.currentLanguage == .thai ? "ทดสอบเสียงแคชเชียร์ (Cha-Ching 🪙)" : "Test Cha-Ching")
                                            .font(.system(size: 12, weight: .medium))
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.appTeal.opacity(0.12), in: Capsule())
                                    .foregroundColor(.appTeal)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    sectionDivider

                    VStack(alignment: .leading, spacing: 8) {
                        Text("inventory_profile_title".t)
                            .font(.system(size: 12))
                            .fontWeight(.medium)
                            .foregroundColor(.textPrimary)
                        Text("inventory_profile_desc".t)
                            .font(.system(size: 12))
                            .foregroundColor(.textSecondary)
                        Picker("inventory_profile_title".t, selection: $inventoryProfile) {
                            Text("inventory_profile_simple".t).tag("simple")
                            Text("inventory_profile_restaurant".t).tag("restaurant")
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    sectionDivider

                    toggleRow(
                        title: "inventory_alerts_toggle_title".t,
                        subtitle: "inventory_alerts_toggle_desc".t,
                        isOn: $enableInventoryStockAlerts
                    )
                    sectionDivider

                    toggleRow(
                        title: "auto_disable_oos_toggle_title".t,
                        subtitle: "auto_disable_oos_toggle_desc".t,
                        isOn: $autoDisableOOSMenu,
                        tint: .orange
                    )
                    sectionDivider

                    toggleRow(
                        title: "inventory_staff_push_toggle_title".t,
                        subtitle: "inventory_staff_push_toggle_desc".t,
                        isOn: $enableInventoryStaffPush
                    )
                    sectionDivider

                    toggleRow(
                        title: "notif_sound_toggle_title".t,
                        subtitle: "notif_sound_toggle_desc".t,
                        isOn: $enableInAppNotificationSounds
                    )
                }
                .apCard()

                // ═══════════════════════════════════════════════════════════
                // SECTION 3: ระบบจัดการครัว (KDS)
                // ═══════════════════════════════════════════════════════════
                VStack(alignment: .leading, spacing: 0) {
                    sectionHeader(
                        title: "syscfg_section_kds".t,
                        icon: "flame.fill",
                        color: .appTeal
                    )

                    toggleRow(
                        title: "syscfg_kds_kitchen_title".t,
                        subtitle: "syscfg_kds_kitchen_desc".t,
                        isOn: $kdsShowKitchen
                    )
                    sectionDivider

                    toggleRow(
                        title: "syscfg_kds_bar_title".t,
                        subtitle: "syscfg_kds_bar_desc".t,
                        isOn: $kdsShowBar
                    )
                    sectionDivider

                    toggleRow(
                        title: "syscfg_kds_auto_title".t,
                        subtitle: "syscfg_kds_auto_desc".t,
                        isOn: $kdsAutoCompleteEnabled
                    )
                    sectionDivider

                    toggleRow(
                        title: "syscfg_kds_sound_title".t,
                        subtitle: "syscfg_kds_sound_desc".t,
                        isOn: $kdsSoundEnabled
                    )
                }
                .apCard()

                // ═══════════════════════════════════════════════════════════
                // SECTION 4: Printers → redirected to Printers page
                // ═══════════════════════════════════════════════════════════
                VStack(alignment: .leading, spacing: 0) {
                    sectionHeader(
                        title: "syscfg_section_printer".t,
                        icon: "printer.fill",
                        color: .orange
                    )

                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "arrow.up.right.square.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.orange)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("syscfg_printer_moved_title".t)
                                .font(.system(size: 12))
                                .fontWeight(.medium)
                                .foregroundColor(.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("syscfg_printer_moved_desc".t)
                                .font(.system(size: 12))
                                .foregroundColor(.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 14)
                }
                .apCard()


                // ═══════════════════════════════════════════════════════════
                // SECTION 5: Security & Advanced
                // ═══════════════════════════════════════════════════════════
                VStack(alignment: .leading, spacing: 0) {
                    sectionHeader(
                        title: "syscfg_section_security".t,
                        icon: "lock.shield.fill",
                        color: .red
                    )

                    toggleRow(
                        title: "syscfg_manager_refund_title".t,
                        subtitle: "syscfg_manager_refund_desc".t,
                        isOn: $requireManagerOverrideForRefund
                    )
                    sectionDivider

                    toggleRow(
                        title: "syscfg_offline_title".t,
                        subtitle: OfflineSyncModeController.isToggleLockedByPlan
                            ? "settings_offline_locked_by_plan".t
                            : "syscfg_offline_desc".t,
                        isOn: $offlineSyncMode,
                        tint: .orange,
                        isDisabled: OfflineSyncModeController.isToggleLockedByPlan
                    )
                    sectionDivider

                    toggleRow(
                        title: "syscfg_dev_mode_title".t,
                        subtitle: "syscfg_dev_mode_desc".t,
                        isOn: $developerModeEnabled,
                        tint: .purple
                    )
                }
                .apCard()

                // ═══════════════════════════════════════════════════════════
                // SECTION 6: AI & OpenRouter
                // ═══════════════════════════════════════════════════════════
                VStack(alignment: .leading, spacing: 0) {
                    sectionHeader(
                        title: "syscfg_section_ai".t,
                        icon: "sparkles",
                        color: .appTeal
                    )

                    if offlineSyncMode {
                        HStack(spacing: 8) {
                            Image(systemName: "wifi.slash")
                                .foregroundColor(.orange)
                            Text("syscfg_ai_offline_banner".t)
                                .font(.system(size: 12))
                                .foregroundColor(.orange)
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, 14)
                    } else {
                        textFieldRow(
                            title: "syscfg_openrouter_title".t,
                            subtitle: "syscfg_openrouter_desc".t,
                            placeholder: "syscfg_openrouter_placeholder".t,
                            text: $openRouterApiKey,
                            isSecure: true
                        )
                    }
                }
                .apCard()

            }
            .padding()
        }
        .background(Color.appBackground)
        .navigationTitle("settings_system_ops".t)
        .navigationBarTitleDisplayMode(.inline)
        .apNavBar(background: Color.appBackground)
        .onAppear {
            openRouterApiKey = KeychainManager.shared.openRouterAPIKey()
            OfflineSyncModeController.enforcePlanPolicy(modelContext: modelContext)
            offlineSyncMode = OfflineSyncModeController.isEnabled
        }
        .onChange(of: offlineSyncMode) { _, newValue in
            if OfflineSyncModeController.isToggleLockedByPlan {
                OfflineSyncModeController.enforcePlanPolicy(modelContext: modelContext)
                offlineSyncMode = true
                return
            }
            _ = OfflineSyncModeController.setUserPreference(
                isOffline: newValue,
                modelContext: modelContext
            )
            offlineSyncMode = OfflineSyncModeController.isEnabled
        }
        .onChange(of: enableTableSystem) { pushFeatureFlags() }
        .onChange(of: enableWebOrdering) { pushFeatureFlags() }
        .onChange(of: openRouterApiKey) { _, value in
            _ = KeychainManager.shared.saveOpenRouterAPIKey(value)
        }
    }

    private func pushFeatureFlags() {
        guard !offlineSyncMode else { return }
        Task {
            do {
                _ = try await NetworkManager.shared.updateMerchantFeatureFlags(
                    isTableSystemEnabled: enableTableSystem,
                    isWebOrderingEnabled: enableWebOrdering
                )
            } catch {
                #if DEBUG
                print("SystemFeatureConfigView [Feature Flags Sync Error]: \(error.localizedDescription)")
                #endif
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Reusable Components
    // ─────────────────────────────────────────────────────────────────────────

    private var paymentsHubRedirectCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(
                title: "payment_hub_redirect_title".t,
                icon: "creditcard.and.123",
                color: .appAccent
            )

            Button {
                APHaptic.trigger()
                NotificationCenter.default.post(name: .openPaymentsNotification, object: nil)
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("payment_hub_redirect_desc".t)
                            .font(.system(size: 12))
                            .foregroundColor(.textSecondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("payment_hub_redirect_cta".t)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.appAccent)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "arrow.up.right.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.appAccent)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .apCard()
    }

    private var dataManagementCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(
                title: "การจัดการและล้างข้อมูล",
                icon: "externaldrive.badge.xmark",
                color: .red
            )

            NavigationLink {
                SystemOpsSettingsView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "checklist")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.orange)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("ล้างข้อมูลทดสอบแบบเลือกประเภท")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.textPrimary)
                        Text("เลือกแยกล้างออร์เดอร์ การชำระเงิน เซสชันโต๊ะ หรือกะเงินสด โดยไม่ลบสินค้าและการตั้งค่าร้าน")
                            .font(.system(size: 12))
                            .foregroundColor(.textSecondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.textSecondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .apCard()
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.red.opacity(0.2), lineWidth: 1)
        )
    }

    private var sectionDivider: some View {
        Divider().background(Color.appDivider).padding(.leading, 12)
    }

    private func sectionHeader(title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 30, height: 30)
                .background(color.gradient)
                .clipShape(RoundedRectangle(cornerRadius: 7))

            Text(title)
                .font(.system(size: 12))
                .fontWeight(.bold)
                .foregroundColor(.textPrimary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appSurfaceHigh.opacity(0.6))
    }

    private func toggleRow(
        title: String,
        subtitle: String,
        isOn: Binding<Bool>,
        tint: Color = .appAccent,
        isDisabled: Bool = false
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12))
                    .fontWeight(.medium)
                    .foregroundColor(isDisabled ? .textSecondary : .textPrimary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(isDisabled ? .orange : .textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(tint)
                .disabled(isDisabled)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .opacity(isDisabled ? 0.85 : 1)
    }

    private func textFieldRow(
        title: String,
        subtitle: String,
        placeholder: String,
        text: Binding<String>,
        isSecure: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12))
                    .fontWeight(.medium)
                    .foregroundColor(.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if isSecure {
                SecureField(placeholder, text: text)
                    .font(.system(size: 12))
                    .padding(10)
                    .background(Color.appBackground)
                    .cornerRadius(APRadius.sm)
                    .overlay(
                        RoundedRectangle(cornerRadius: APRadius.sm)
                            .stroke(Color.appDivider, lineWidth: 1)
                    )
                    .textInputAutocapitalization(.none)
                    .autocorrectionDisabled()
            } else {
                TextField(placeholder, text: text)
                    .font(.system(size: 12))
                    .padding(10)
                    .background(Color.appBackground)
                    .cornerRadius(APRadius.sm)
                    .overlay(
                        RoundedRectangle(cornerRadius: APRadius.sm)
                            .stroke(Color.appDivider, lineWidth: 1)
                    )
                    .textInputAutocapitalization(.none)
                    .autocorrectionDisabled()
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
    }
}
