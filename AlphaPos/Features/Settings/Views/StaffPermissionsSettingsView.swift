import SwiftData
import SwiftUI

struct StaffPermissionsSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Role.name) private var roles: [Role]
    @Query(sort: \Employee.firstName) private var employees: [Employee]

    @State private var selectedRoleId: UUID?
    @State private var selectedPermissionKeys: Set<String> = []
    @State private var selectedEmployeeId: UUID?
    @State private var newPasscode = ""
    @State private var statusMessage = ""
    @State private var showingStatus = false

    private var selectedRole: Role? {
        roles.first { $0.id == selectedRoleId } ?? roles.first
    }

    private var selectedEmployee: Employee? {
        employees.first { $0.id == selectedEmployeeId } ?? employees.first
    }

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    rolePermissionSection
                    passcodeSection
                }
                .padding()
            }
        }
        .navigationTitle("staff_permissions_title".t)
        .navigationBarTitleDisplayMode(.inline)
        .apNavBar(background: Color.appBackground)
        .onAppear {
            selectedRoleId = selectedRoleId ?? roles.first?.id
            selectedEmployeeId = selectedEmployeeId ?? employees.first?.id
            loadSelectedRolePermissions()
        }
        .onChange(of: selectedRoleId) { _, _ in
            loadSelectedRolePermissions()
        }
        .alert("settings_saved_title".t, isPresented: $showingStatus) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(statusMessage)
        }
    }

    private var rolePermissionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("staff_permissions_roles".t)
                .font(.caption.weight(.bold))
                .foregroundColor(.appAccent)
                .tracking(1)

            VStack(alignment: .leading, spacing: 16) {
                Picker("staff_permissions_role_picker".t, selection: Binding(
                    get: { selectedRoleId ?? roles.first?.id },
                    set: { selectedRoleId = $0 }
                )) {
                    ForEach(roles) { role in
                        Text(role.name).tag(Optional(role.id))
                    }
                }
                .pickerStyle(.menu)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                    ForEach(AppPermission.allCases) { permission in
                        Toggle(isOn: Binding(
                            get: { selectedPermissionKeys.contains(permission.rawValue) },
                            set: { isOn in
                                if isOn {
                                    selectedPermissionKeys.insert(permission.rawValue)
                                } else {
                                    selectedPermissionKeys.remove(permission.rawValue)
                                }
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(permission.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.textPrimary)
                                Text(permission.rawValue)
                                    .font(.caption2)
                                    .foregroundColor(.textTertiary)
                            }
                        }
                        .tint(.appAccent)
                        .padding(10)
                        .background(Color.appSurfaceHigh)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }

                Button {
                    saveRolePermissions()
                } label: {
                    Label("save_permissions_btn".t, systemImage: "checkmark.shield.fill")
                        .apGradientButton()
                }
            }
            .apCard()
        }
    }

    private var passcodeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("staff_passcode_title".t)
                .font(.caption.weight(.bold))
                .foregroundColor(.appAccent)
                .tracking(1)

            VStack(alignment: .leading, spacing: 16) {
                Picker("staff_picker_title".t, selection: Binding(
                    get: { selectedEmployeeId ?? employees.first?.id },
                    set: { selectedEmployeeId = $0 }
                )) {
                    ForEach(employees) { employee in
                        Text("\(employee.firstName) \(employee.lastName)").tag(Optional(employee.id))
                    }
                }
                .pickerStyle(.menu)

                SecureField("new_passcode_placeholder".t, text: $newPasscode)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .padding(12)
                    .background(Color.appSurfaceHigh)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Button {
                    resetPasscode()
                } label: {
                    Label("reset_passcode_btn".t, systemImage: "key.fill")
                        .apGradientButton(disabled: newPasscode.count < 4)
                }
                .disabled(newPasscode.count < 4)
            }
            .apCard()
        }
    }

    private func loadSelectedRolePermissions() {
        guard let selectedRole else {
            selectedPermissionKeys = []
            return
        }
        let permissions = PermissionService.permissions(for: selectedRole)
        selectedPermissionKeys = Set(permissions.map(\.rawValue))
    }

    private func saveRolePermissions() {
        guard let selectedRole else { return }
        selectedRole.permissionKeys = selectedPermissionKeys.sorted().joined(separator: ",")
        selectedRole.isSynced = false
        selectedRole.updatedAt = Date()
        try? modelContext.save()
        APHaptic.trigger()
        statusMessage = "permissions_saved_message".t
        showingStatus = true
    }

    private func resetPasscode() {
        guard let selectedEmployee, let user = selectedEmployee.user, newPasscode.count >= 4 else { return }
        user.pinCodeHash = SecurityHelper.hashPIN(newPasscode)
        user.isSynced = false
        user.updatedAt = Date()
        modelContext.insert(AuditLog(
            employeeId: selectedEmployee.id,
            actionType: "staff_passcode_reset",
            details: "Passcode reset for \(selectedEmployee.firstName) \(selectedEmployee.lastName)"
        ))
        try? modelContext.save()
        newPasscode = ""
        APHaptic.trigger()
        statusMessage = "passcode_saved_message".t
        showingStatus = true
    }
}
