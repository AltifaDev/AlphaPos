import SwiftUI
import SwiftData

struct SecuritySettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("require_face_scan") private var requireFaceScan = true
    @AppStorage("passcode_max_attempts") private var passcodeMaxAttempts = 5
    @AppStorage("passcode_lockout_minutes") private var passcodeLockoutMinutes = 5
    @AppStorage("staff_session_timeout_minutes") private var staffSessionTimeoutMinutes = 15
    @AppStorage("require_manager_override_for_refund") private var requireManagerOverrideForRefund = true
    @AppStorage("require_manager_override_for_void") private var requireManagerOverrideForVoid = true
    
    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L.Sections.security.t)
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.appAccent)
                            .tracking(1.0)
                        
                        VStack(spacing: 16) {
                            NavigationLink(destination: StaffPermissionsSettingsView()) {
                                HStack(spacing: 14) {
                                    Image(systemName: "person.2.badge.key.fill")
                                        .foregroundColor(.white)
                                        .frame(width: 32, height: 32)
                                        .background(Color.appAccent)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("staff_permissions_title".t)
                                            .foregroundColor(.textPrimary)
                                        Text("staff_permissions_desc".t)
                                            .font(.caption2)
                                            .foregroundColor(.textSecondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(.textTertiary)
                                }
                            }
                            .buttonStyle(.plain)

                            Divider()
                                .background(Color.appDivider)

                            Stepper(value: $passcodeMaxAttempts, in: 3...10) {
                                policyRow(title: "passcode_attempts_title".t, value: "\(passcodeMaxAttempts)")
                            }
                            .onChange(of: passcodeMaxAttempts) { savePolicy() }

                            Divider()
                                .background(Color.appDivider)

                            Stepper(value: $passcodeLockoutMinutes, in: 1...60) {
                                policyRow(title: "passcode_lockout_title".t, value: "\(passcodeLockoutMinutes) min")
                            }
                            .onChange(of: passcodeLockoutMinutes) { savePolicy() }

                            Divider()
                                .background(Color.appDivider)

                            Stepper(value: $staffSessionTimeoutMinutes, in: 1...480) {
                                policyRow(title: "session_timeout_title".t, value: "\(staffSessionTimeoutMinutes) min")
                            }
                            .onChange(of: staffSessionTimeoutMinutes) { savePolicy() }

                            Divider()
                                .background(Color.appDivider)

                            Toggle(isOn: $requireManagerOverrideForRefund) {
                                policyRow(title: "manager_refund_override_title".t, value: nil)
                            }
                            .tint(.appAccent)
                            .onChange(of: requireManagerOverrideForRefund) { savePolicy() }

                            Divider()
                                .background(Color.appDivider)

                            Toggle(isOn: $requireManagerOverrideForVoid) {
                                policyRow(title: "manager_void_override_title".t, value: nil)
                            }
                            .tint(.appAccent)
                            .onChange(of: requireManagerOverrideForVoid) { savePolicy() }

                            Divider()
                                .background(Color.appDivider)

                            Toggle(isOn: $requireFaceScan) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Enforce Biometric Clock-In")
                                        .foregroundColor(.textPrimary)
                                    Text("Staff must pass facial verification matches.")
                                        .font(.caption2)
                                        .foregroundColor(.textSecondary)
                                }
                            }
                            .tint(.appAccent)
                            .onChange(of: requireFaceScan) { APHaptic.trigger() }
                        }
                        .apCard()
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
        }
        .navigationTitle(L.Sections.security.t)
        .navigationBarTitleDisplayMode(.inline)
        .apNavBar(background: Color.appBackground)
        .onAppear {
            ensurePolicy()
        }
    }

    private func policyRow(title: String, value: String?) -> some View {
        HStack {
            Text(title)
                .foregroundColor(.textPrimary)
            Spacer()
            if let value {
                Text(value)
                    .font(.caption.weight(.bold))
                    .foregroundColor(.textSecondary)
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
        policy.isSynced = false
        policy.updatedAt = Date()
        try? modelContext.save()
    }
}

#Preview {
    NavigationStack {
        SecuritySettingsView()
    }
}
