import SwiftData
import SwiftUI

struct StaffPermissionsSettingsView: View {
    @EnvironmentObject private var sessionManager: AppSessionManager
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Role.name) private var roles: [Role]
    @Query(sort: \Employee.firstName) private var employees: [Employee]

    @State private var selectedRoleId: UUID?
    @State private var selectedPermissionKeys: Set<String> = []
    @State private var selectedEmployeeId: UUID?
    @State private var newPasscode = ""
    @State private var statusMessage = ""
    @State private var showingStatus = false

    private var selectableRoles: [Role] {
        var seen = Set<String>()
        return roles
            .filter { !$0.isDeleted }
            .sorted {
                let lhs = RestaurantRoleCatalog.sortIndex(for: $0.name)
                let rhs = RestaurantRoleCatalog.sortIndex(for: $1.name)
                return lhs == rhs ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending : lhs < rhs
            }
            .filter { seen.insert(RestaurantRoleCatalog.deduplicationKey(for: $0.name)).inserted }
    }

    private var selectedRole: Role? {
        selectableRoles.first { $0.id == selectedRoleId } ?? selectableRoles.first
    }

    private var selectedEmployee: Employee? {
        employees.first { $0.id == selectedEmployeeId } ?? employees.first
    }

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            if sessionManager.can(.staffPermissionsManage) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    rolePermissionSection
                    passcodeSection
                }
                .padding()
            }
            } else {
                ContentUnavailableView("ไม่มีสิทธิ์กำหนดสิทธิ์พนักงาน", systemImage: "lock.shield")
            }
        }
        .navigationTitle("staff_permissions_title".t)
        .navigationBarTitleDisplayMode(.inline)
        .apNavBar(background: Color.appBackground)
        .onAppear {
            RoleBootstrap.ensureDefaultRoles(modelContext: modelContext)
            selectedRoleId = selectedRoleId ?? selectableRoles.first?.id
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
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.appAccent)
                .tracking(1)

            VStack(alignment: .leading, spacing: 16) {
                Picker("staff_permissions_role_picker".t, selection: Binding(
                    get: { selectedRoleId ?? selectableRoles.first?.id },
                    set: { selectedRoleId = $0 }
                )) {
                    ForEach(selectableRoles) { role in
                        Text(role.name).tag(Optional(role.id))
                    }
                }
                .pickerStyle(.menu)

                Button("ใช้สิทธิ์เริ่มต้นแบบจำกัดสำหรับบทบาทนี้") {
                    guard let selectedRole else { return }
                    selectedPermissionKeys = Set(PermissionService.permissions(forRoleName: selectedRole.name).map(\.rawValue))
                }
                Text("ปุ่มนี้เปลี่ยนเฉพาะรายการที่เลือกในหน้าจอ ตรวจสอบก่อนกดบันทึก · สิทธิ์เดิมจะไม่ถูกเปลี่ยนอัตโนมัติ")
                    .font(.caption).foregroundStyle(.secondary)

                DisclosureGroup("ตัวอย่างเมนู sidebar ตามสิทธิ์ที่เลือก") {
                    ForEach(MainDashboardView.DashboardTab.allCases.filter { tab in
                        if tab == .employees {
                            return selectedPermissionKeys.contains(AppPermission.staffManage.rawValue)
                                || selectedPermissionKeys.contains(AppPermission.payrollManage.rawValue)
                        }
                        return selectedPermissionKeys.contains(tab.requiredPermission.rawValue)
                    }) { tab in
                        Text(tab.localizedName)
                    }
                    Text("รายการจริงขึ้นกับโหมดร้านและฟีเจอร์ที่เปิดใช้งานด้วย")
                        .font(.caption).foregroundStyle(.secondary)
                }

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
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.textPrimary)
                                Text(permission.rawValue)
                                    .font(.system(size: 12))
                                    .foregroundColor(.textTertiary)
                            }
                        }
                        .tint(.appAccent)
                        .disabled(!sessionManager.can(permission))
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
                .font(.system(size: 12, weight: .bold))
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
        guard sessionManager.can(.staffPermissionsManage), let session = sessionManager.currentStaffSession,
              selectedPermissionKeys.isSubset(of: Set(session.permissions.map(\.rawValue))),
              PermissionService.permissions(for: selectedRole).isSubset(of: session.permissions),
              !employees.contains(where: { $0.id == session.employeeId && $0.user?.role?.id == selectedRole.id }),
              !["owner", "admin"].contains(PermissionPolicyCore.normalizedRole(selectedRole.name)) else {
            statusMessage = "ไม่สามารถแก้บทบาทของตนเอง บทบาทเจ้าของ/ผู้ดูแล หรือมอบสิทธิ์เกินอำนาจของตนได้"
            showingStatus = true
            return
        }
        let previous = selectedRole.permissionKeys
        selectedRole.permissionKeys = selectedPermissionKeys.isEmpty ? "none" : selectedPermissionKeys.sorted().joined(separator: ",")
        selectedRole.isSynced = false
        selectedRole.updatedAt = Date()
        modelContext.insert(AuditLog(employeeId: session.employeeId, actionType: "role_permissions_changed",
            details: "Role \(selectedRole.id): before=\(previous); after=\(selectedRole.permissionKeys)"))
        modelContext.saveWithLogging(label: #function)
        APHaptic.trigger()
        statusMessage = "permissions_saved_message".t
        showingStatus = true
    }

    private func resetPasscode() {
        guard let selectedEmployee, let user = selectedEmployee.user, newPasscode.count >= 4 else { return }
        guard sessionManager.canAssignRole(user.role, to: selectedEmployee.id) else {
            statusMessage = "ไม่มีสิทธิ์เปลี่ยนรหัสของบัญชีนี้"
            showingStatus = true
            return
        }
        user.pinCodeHash = SecurityHelper.hashPIN(newPasscode)
        user.isSynced = false
        user.updatedAt = Date()
        modelContext.insert(AuditLog(
            employeeId: selectedEmployee.id,
            actionType: "staff_passcode_reset",
            details: "Passcode reset for \(selectedEmployee.firstName) \(selectedEmployee.lastName)"
        ))
        modelContext.saveWithLogging(label: #function)
        newPasscode = ""
        APHaptic.trigger()
        statusMessage = "passcode_saved_message".t
        showingStatus = true
    }
}
