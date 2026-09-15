import SwiftUI
import SwiftData

struct SecuritySettingsView: View {
    @EnvironmentObject private var sessionManager: AppSessionManager
    /// When embedded in Settings split, hide duplicate section chrome.
    var embedded: Bool = false

    @Environment(\.modelContext) private var modelContext
    @AppStorage("require_face_scan") private var requireFaceScan = false
    @AppStorage("passcode_max_attempts") private var passcodeMaxAttempts = 5
    @AppStorage("passcode_lockout_minutes") private var passcodeLockoutMinutes = 5
    @AppStorage("staff_session_timeout_minutes") private var staffSessionTimeoutMinutes = 15
    @AppStorage("require_manager_override_for_refund") private var requireManagerOverrideForRefund = true
    @AppStorage("require_manager_override_for_void") private var requireManagerOverrideForVoid = true
    @AppStorage("require_manager_override_for_no_sale") private var requireManagerOverrideForNoSale = true
    @AppStorage("require_manager_override_for_drawer_test") private var requireManagerOverrideForDrawerTest = true

    private let chrome = Color(hex: "8E8E93")
    private let barFont = Font.system(size: 12, weight: .regular)
    private let barFontSemibold = Font.system(size: 12, weight: .semibold)

    var body: some View {
        ZStack {
            Color.clear

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if !embedded {
                        Text(L.Sections.security.t)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .tracking(0.4)
                    }

                    VStack(spacing: 0) {
                        if sessionManager.can(.staffPermissionsManage) {
                        NavigationLink(destination: StaffPermissionsSettingsView()) {
                            settingsBarRow {
                                HStack(spacing: 10) {
                                    settingsIcon("person.2.badge.key.fill")
                                    Text("staff_permissions_title".t)
                                        .font(barFont)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        }

                        barDivider

                        Stepper(value: $passcodeMaxAttempts, in: 3...10) {
                            policyBar(title: "passcode_attempts_title".t, value: "\(passcodeMaxAttempts)")
                        }
                        .font(barFont)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .onChange(of: passcodeMaxAttempts) { savePolicy() }

                        barDivider

                        Stepper(value: $passcodeLockoutMinutes, in: 1...60) {
                            policyBar(title: "passcode_lockout_title".t, value: "\(passcodeLockoutMinutes) \("waitlist_min_unit".t)")
                        }
                        .font(barFont)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .onChange(of: passcodeLockoutMinutes) { savePolicy() }

                        barDivider

                        Stepper(value: $staffSessionTimeoutMinutes, in: 1...480) {
                            policyBar(title: "session_timeout_title".t, value: "\(staffSessionTimeoutMinutes) \("waitlist_min_unit".t)")
                        }
                        .font(barFont)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .onChange(of: staffSessionTimeoutMinutes) { savePolicy() }

                        barDivider

                        Toggle(isOn: $requireManagerOverrideForRefund) {
                            Text("manager_refund_override_title".t)
                                .font(barFont)
                                .foregroundStyle(.primary)
                        }
                        .tint(chrome)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .onChange(of: requireManagerOverrideForRefund) { savePolicy() }

                        barDivider

                        Toggle(isOn: $requireManagerOverrideForVoid) {
                            Text("manager_void_override_title".t)
                                .font(barFont)
                                .foregroundStyle(.primary)
                        }
                        .tint(chrome)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .onChange(of: requireManagerOverrideForVoid) { savePolicy() }

                        barDivider

                        Toggle(isOn: $requireManagerOverrideForNoSale) {
                            Text("manager_no_sale_override_title".t)
                                .font(barFont)
                                .foregroundStyle(.primary)
                        }
                        .tint(chrome)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .onChange(of: requireManagerOverrideForNoSale) { savePolicy() }

                        barDivider

                        Toggle(isOn: $requireManagerOverrideForDrawerTest) {
                            Text("manager_drawer_test_override_title".t)
                                .font(barFont)
                                .foregroundStyle(.primary)
                        }
                        .tint(chrome)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .onChange(of: requireManagerOverrideForDrawerTest) { savePolicy() }

                        barDivider

                        HStack(spacing: 10) {
                            Image(systemName: "faceid")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("enforce_biometric_clock_in".t)
                                    .font(barFont)
                                    .foregroundStyle(.secondary)
                                Text("ระบบจดจำใบหน้าพนักงานยังไม่พร้อม · ใช้ PIN ฝั่งเซิร์ฟเวอร์")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .background(Color.primary.opacity(embedded ? 0.03 : 0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                    )
                }
                .padding(14)
            }
        }
        .navigationTitle(embedded ? "" : L.Sections.security.t)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if requireFaceScan {
                requireFaceScan = false
                savePolicy()
            }
        }
        .toolbar(embedded ? .hidden : .automatic, for: .navigationBar)
        .apNavBar(background: Color.clear)
        .onAppear {
            ensurePolicy()
        }
    }

    private var barDivider: some View {
        Divider()
            .opacity(0.35)
            .padding(.leading, 46)
    }

    private func settingsBarRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: 36)
    }

    private func settingsIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 24, height: 24)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func policyBar(title: String, value: String?) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(barFont)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .font(barFontSemibold)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private func ensurePolicy() {
        let policies = (try? modelContext.fetch(FetchDescriptor<SecurityPolicy>())) ?? []
        guard policies.isEmpty else { return }
        savePolicy()
    }

    private func savePolicy() {
        let policies = (try? modelContext.fetch(FetchDescriptor<SecurityPolicy>())) ?? []
        let policy = policies.first ?? SecurityPolicy()
        if policies.isEmpty {
            modelContext.insert(policy)
        }
        policy.passcodeMaxAttempts = passcodeMaxAttempts
        policy.lockoutMinutes = passcodeLockoutMinutes
        policy.staffSessionTimeoutMinutes = staffSessionTimeoutMinutes
        policy.requireManagerOverrideForRefund = requireManagerOverrideForRefund
        policy.requireManagerOverrideForVoid = requireManagerOverrideForVoid
        policy.requireManagerOverrideForNoSale = requireManagerOverrideForNoSale
        policy.requireManagerOverrideForDrawerTest = requireManagerOverrideForDrawerTest
        policy.requireFaceScan = requireFaceScan
        policy.isSynced = false
        policy.updatedAt = Date()
        modelContext.saveWithLogging(label: #function)
    }
}

#Preview {
    NavigationStack {
        SecuritySettingsView()
    }
}
