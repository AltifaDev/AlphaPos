import SwiftUI
import SwiftData
import PhotosUI
import UIKit

/// Dense enterprise staff directory (master–detail).
struct EmployeeDirectoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Employee.firstName) private var employees: [Employee]
    @Query(sort: \Role.name) private var allRoles: [Role]

    @AppStorage("app_language") private var appLanguage = "en"

    @State private var searchText = ""
    @State private var filter: StaffFilter = .active
    @State private var selectedEmployee: Employee?
    @State private var editorRoute: EmployeeEditorRoute?

    private var selectableRoles: [Role] {
        var canonicalRoles: [String: Role] = [:]
        for role in allRoles where !role.isDeleted {
            let key = RestaurantRoleCatalog.deduplicationKey(for: role.name)
            let canonicalName = RestaurantRoleCatalog.canonicalName(for: role.name)
            if let current = canonicalRoles[key] {
                let currentIsCanonical = current.name == RestaurantRoleCatalog.canonicalName(for: current.name)
                let candidateIsCanonical = role.name == canonicalName
                if candidateIsCanonical && !currentIsCanonical {
                    canonicalRoles[key] = role
                }
            } else {
                canonicalRoles[key] = role
            }
        }
        return canonicalRoles.values
            .filter { !$0.isDeleted }
            .sorted {
                let lhs = RestaurantRoleCatalog.sortIndex(for: $0.name)
                let rhs = RestaurantRoleCatalog.sortIndex(for: $1.name)
                return lhs == rhs ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending : lhs < rhs
            }
    }

    private struct EmployeeEditorRoute: Identifiable {
        let id = UUID()
        let employee: Employee?
        static func add() -> Self { .init(employee: nil) }
        static func edit(_ employee: Employee) -> Self { .init(employee: employee) }
    }

    enum StaffFilter: String, CaseIterable, Identifiable {
        case all, active, resigned
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return "employee_filter_all".t
            case .active: return "employee_filter_active".t
            case .resigned: return "employee_filter_resigned".t
            }
        }
    }

    private var filteredEmployees: [Employee] {
        employees.filter { emp in
            guard !emp.isDeleted else { return false }
            let activeBranch = BranchContext.shared.activeBranchIDString.lowercased()
            if !activeBranch.isEmpty,
               !emp.branchId.isEmpty,
               emp.branchId.lowercased() != activeBranch { return false }
            switch filter {
            case .all: break
            case .active: if emp.resignedAt != nil { return false }
            case .resigned: if emp.resignedAt == nil { return false }
            }
            let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !q.isEmpty else { return true }
            let name = "\(emp.firstName) \(emp.lastName)".lowercased()
            let phone = (emp.phone ?? "").lowercased()
            return name.contains(q) || phone.contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().background(Color.appDivider)
            HStack(spacing: 0) {
                listPane
                    .frame(maxWidth: .infinity)
                Divider().background(Color.appDivider)
                detailPane
                    .frame(maxWidth: .infinity)
            }
        }
        .background(Color.appBackground)
        .fullScreenCover(item: $editorRoute) { route in
            EmployeeEditorView(employee: route.employee, roles: selectableRoles) {
                editorRoute = nil
            }
        }
        .onAppear {
            RoleBootstrap.ensureDefaultRoles(modelContext: modelContext)
            if selectedEmployee == nil {
                selectedEmployee = filteredEmployees.first
            }
        }
        .onChange(of: searchText) { _, _ in reconcileSelection() }
        .onChange(of: filter) { _, _ in reconcileSelection() }
        .onChange(of: employees.count) { _, _ in reconcileSelection() }
    }

    private func reconcileSelection() {
        if let selected = selectedEmployee,
           filteredEmployees.contains(where: { $0.id == selected.id }) {
            return
        }
        selectedEmployee = filteredEmployees.first
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textTertiary)
                TextField("employee_search_placeholder".t, text: $searchText)
                    .font(.system(size: 12))
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.appSurfaceHigh, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .frame(maxWidth: 280)

            HStack(spacing: 4) {
                ForEach(StaffFilter.allCases) { item in
                    Button {
                        withAnimation(.easeInOut(duration: 0.12)) { filter = item }
                    } label: {
                        Text(item.title)
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .foregroundStyle(filter == item ? Color.white : Color.textSecondary)
                            .background(filter == item ? Color(hex: "0F766E") : Color.appSurfaceHigh)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            Text("\(filteredEmployees.count) · \("staff_registry".t)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.textTertiary)

            Button {
                editorRoute = .add()
            } label: {
                Label("add_employee".t, systemImage: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .foregroundStyle(.white)
                    .background(Color(hex: "0F766E"), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, APSpacing.md)
        .padding(.vertical, 8)
        .background(Color.appSurface)
    }

    // MARK: - List

    private var listPane: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if filteredEmployees.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "person.text.rectangle")
                            .font(.system(size: 28))
                            .foregroundStyle(Color.textTertiary)
                        Text("no_employees_registered".t)
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 48)
                } else {
                    ForEach(filteredEmployees) { emp in
                        Button {
                            selectedEmployee = emp
                        } label: {
                            employeeRow(emp, selected: selectedEmployee?.id == emp.id)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .background(Color.appBackground)
    }

    private func employeeRow(_ emp: Employee, selected: Bool) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(selected ? Color(hex: "0F766E").opacity(0.18) : Color.appSurfaceHigh)
                    .frame(width: 32, height: 32)
                Text(initials(emp))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(selected ? Color(hex: "0F766E") : Color.textSecondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("\(emp.firstName) \(emp.lastName)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Text(employmentLabel(emp))
                    .font(.system(size: 10))
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if emp.resignedAt != nil {
                Text("employee_filter_resigned".t)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.appRose)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.appRose.opacity(0.12), in: Capsule())
            } else if emp.faceEmbeddingData != nil {
                Image(systemName: "faceid")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.appTeal)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(selected ? Color(hex: "0F766E").opacity(0.08) : Color.clear)
        .overlay(alignment: .bottom) {
            Divider().background(Color.appDivider)
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailPane: some View {
        if let emp = selectedEmployee {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color(hex: "0F766E").opacity(0.15))
                                .frame(width: 48, height: 48)
                            Text(initials(emp))
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Color(hex: "0F766E"))
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(emp.firstName) \(emp.lastName)")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Color.textPrimary)
                            Text(employmentLabel(emp))
                                .font(.system(size: 11))
                                .foregroundStyle(Color.textSecondary)
                        }
                        Spacer()
                        Button {
                            editorRoute = .edit(emp)
                        } label: {
                            Label("edit_employee".t, systemImage: "pencil")
                                .font(.system(size: 11, weight: .semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .foregroundStyle(Color(hex: "0F766E"))
                                .background(Color(hex: "0F766E").opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    detailGrid(emp)
                }
                .padding(APSpacing.md)
            }
            .background(Color.appSurface.opacity(0.35))
        } else {
            VStack(spacing: 8) {
                Image(systemName: "person.crop.rectangle")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.textTertiary)
                Text("employee_select_hint".t)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appSurface.opacity(0.35))
        }
    }

    private func detailGrid(_ emp: Employee) -> some View {
        VStack(spacing: 0) {
            detailRow("phone_number_label".t, emp.phone ?? "—")
            detailRow("email_address_label".t, emp.email ?? "—")
            detailRow(appLanguage == "th" ? "เลขประจำตัว/หนังสือเดินทาง" : "National ID / Passport", emp.nationalId ?? "—")
            detailRow("pay_rate_label".t, String(format: "%.0f ฿ · %@", emp.payRate, localizedEmploymentType(emp.employmentType)))
            detailRow("bank_name".t, bankLine(emp))
            detailRow("home_address_header".t, emp.address ?? "—")
            detailRow("emergency_contact_header".t, emergencyLine(emp))
            detailRow(appLanguage == "th" ? "วันที่เริ่มงาน" : "Joined", localizedDate(emp.joinedAt))
            if let resigned = emp.resignedAt {
                detailRow(appLanguage == "th" ? "วันที่สิ้นสุดงาน" : "Resigned", localizedDate(resigned))
            }
            detailRow("face_scanner_biometrics_title".t, emp.faceEmbeddingData != nil ? "face_id_registered_status".t : "face_id_not_registered_status".t)
            if let user = emp.user {
                detailRow("Username", user.username)
                detailRow("Access Role", displayRoleName(user.role?.name))
            }
        }
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.appBorderSubtle, lineWidth: 1)
        )
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(Color.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Divider().background(Color.appDivider)
        }
    }

    // MARK: - Helpers

    private func initials(_ emp: Employee) -> String {
        String(emp.firstName.prefix(1) + emp.lastName.prefix(1)).uppercased()
    }

    private func employmentLabel(_ emp: Employee) -> String {
        "\(localizedEmploymentType(emp.employmentType)) · \(String(format: "%.0f", emp.payRate)) ฿"
    }

    private func localizedEmploymentType(_ type: String) -> String {
        switch type {
        case "daily": return "daily_pay_type".t
        case "monthly": return "monthly_fixed_pay_type".t
        default: return "hourly_pay_type".t
        }
    }

    private func displayRoleName(_ roleName: String?) -> String {
        guard let roleName, !roleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "—"
        }
        return RestaurantRoleCatalog.canonicalName(for: roleName)
    }

    private func localizedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: appLanguage == "th" ? "th_TH" : "en_US")
        formatter.calendar = Calendar(identifier: appLanguage == "th" ? .buddhist : .gregorian)
        formatter.dateFormat = appLanguage == "th" ? "d MMM yyyy" : "MMM d, yyyy"
        return formatter.string(from: date)
    }

    private func bankLine(_ emp: Employee) -> String {
        let bank = emp.bankName ?? ""
        let acc = emp.bankAccountNumber ?? ""
        if bank.isEmpty && acc.isEmpty { return "—" }
        return [bank, acc].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func emergencyLine(_ emp: Employee) -> String {
        let name = emp.emergencyContactName ?? ""
        let phone = emp.emergencyContactPhone ?? ""
        if name.isEmpty && phone.isEmpty { return "—" }
        return [name, phone].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

// MARK: - Employee Editor Sheet

struct EmployeeEditorView: View {
    @EnvironmentObject private var sessionManager: AppSessionManager
    @Environment(\.modelContext) private var modelContext
    @AppStorage("app_language") private var appLanguage = "en"
    @AppStorage("default_ot_multiplier") private var defaultOTMultiplier = 1.5

    let employee: Employee?
    let roles: [Role]
    let onDismiss: () -> Void

    @State private var empFirstName = ""
    @State private var empLastName = ""
    @State private var empPhone = ""
    @State private var empNationalId = ""
    @State private var empEmploymentType = "hourly"
    @State private var empPayRate = 0.0
    @State private var empBankName = ""
    @State private var empBankAccount = ""
    @State private var empEmail = ""
    @State private var empAddress = ""
    @State private var selectedProvinceId: Int?
    @State private var selectedDistrictId: Int?
    @State private var selectedSubDistrictId: Int?
    @State private var addressDetail = ""
    @State private var postalCode = ""
    @State private var empEmergencyContactName = ""
    @State private var empEmergencyContactPhone = ""
    @State private var empJoinedAt = Date()
    @State private var empResignedAt = Date()
    @State private var hasResigned = false
    @State private var specifyDOB = false
    @State private var empDateOfBirth = Date()
    @State private var empPin = ""
    @State private var empRoleId: UUID?
    @State private var faceEmbeddingData: Data?
    @State private var faceRegisteredAt: Date?
    @State private var faceEmbeddingNeedsRemoteClear = false
    @State private var showFaceCamera = false
    @State private var isProcessingFace = false
    @State private var faceMessage: String?
    @State private var saveErrorMessage: String?

    private var trimmedFirstName: String {
        empFirstName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedLastName: String {
        empLastName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        // Detailed validation belongs in saveEmployee(), where the user receives
        // an actionable message instead of an unexplained disabled Save button.
        !trimmedFirstName.isEmpty && !trimmedLastName.isEmpty
    }

    private func label(_ english: String, _ thai: String) -> String {
        appLanguage == "th" ? thai : english
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.appBackground, Color.appAccent.opacity(0.07), Color.appBackground],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                editorToolbar
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 420, maximum: 720), spacing: 18, alignment: .top)],
                        alignment: .center,
                        spacing: 18
                    ) {
                        personalInformationCard
                        employmentCard
                        employeeAccessSection
                        employeeBiometricsSection
                        addressCard
                        bankingAndEmergencyCard
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                    .frame(maxWidth: 1480)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .apColorScheme()
        .environment(\.locale, Locale(identifier: appLanguage == "th" ? "th_TH" : "en_US"))
        .onAppear(perform: loadForm)
        .sheet(isPresented: $showFaceCamera) {
            FaceCameraPicker { image in processFaceImage(image) }
        }
        .alert("Unable to Save Employee", isPresented: Binding(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { saveErrorMessage = nil }
        } message: {
            Text(saveErrorMessage ?? "")
        }
    }

    private var editorToolbar: some View {
        HStack(spacing: 16) {
            Button(action: onDismiss) {
                Label(L.Common.cancel.t, systemImage: "xmark")
            }
            .apGlassButton()

            VStack(alignment: .leading, spacing: 2) {
                Text(employee == nil ? "add_employee".t : "edit_employee".t)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text(label("Employee profile and restaurant access", "ข้อมูลพนักงานและสิทธิ์การใช้งานร้าน"))
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer()

            Button(action: saveEmployee) {
                Label("save_btn_label".t, systemImage: "checkmark")
                    .fontWeight(.semibold)
            }
            .apGlassButton(prominent: true, tint: Color.appAccent)
            .disabled(!canSave)
            .accessibilityIdentifier("employee_save_button")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) { Divider().opacity(0.35) }
    }

    private var personalInformationCard: some View {
        editorCard(title: label("Personal information", "ข้อมูลส่วนตัว"), icon: "person.text.rectangle") {
            editorTextField(label("First Name (required)", "ชื่อ (จำเป็น)"), text: $empFirstName)
            editorTextField(label("Last Name (required)", "นามสกุล (จำเป็น)"), text: $empLastName)
            editorTextField(label("Phone Number (optional)", "เบอร์โทร (ไม่บังคับ)"), text: $empPhone, keyboard: .phonePad)
            editorTextField(label("National ID / Passport (optional)", "เลขประจำตัว/หนังสือเดินทาง (ไม่บังคับ)"), text: $empNationalId)
            editorTextField(label("Email Address (optional)", "อีเมล (ไม่บังคับ)"), text: $empEmail, keyboard: .emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Toggle(label("Specify Date of Birth", "ระบุวันเกิด"), isOn: $specifyDOB)
            if specifyDOB {
                DatePicker(label("Date of Birth", "วันเกิด"), selection: $empDateOfBirth, displayedComponents: .date)
            }
        }
    }

    private var employmentCard: some View {
        editorCard(title: label("Position and employment", "ตำแหน่งและการจ้างงาน"), icon: "briefcase.fill") {
            VStack(alignment: .leading, spacing: 6) {
                Text(label("Restaurant position", "ตำแหน่งพนักงาน"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                accessRolePicker
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Picker(label("Employment Type", "ประเภทการจ้าง"), selection: $empEmploymentType) {
                Text(label("Hourly", "รายชั่วโมง")).tag("hourly")
                Text(label("Daily", "รายวัน")).tag("daily")
                Text(label("Monthly", "รายเดือน")).tag("monthly")
            }
            .pickerStyle(.segmented)
            HStack {
                Text("pay_rate_label".t)
                Spacer()
                TextField("0.00", value: $empPayRate, format: FloatingPointFormatStyle<Double>.number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 180)
            }
            HStack {
                Text("payroll_ot_multiplier_lbl".t)
                Spacer()
                Text(String(format: "%.2fx", defaultOTMultiplier))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.appAccent)
            }
            DatePicker(label("Start Date (Joined)", "วันที่เริ่มงาน"), selection: $empJoinedAt, displayedComponents: .date)
            Toggle(label("Has Resigned / Terminated", "ลาออก/สิ้นสุดการจ้างแล้ว"), isOn: $hasResigned)
            if hasResigned {
                DatePicker(label("End Date (Resigned)", "วันที่สิ้นสุดการจ้าง"), selection: $empResignedAt, displayedComponents: .date)
            }
        }
    }

    private var addressCard: some View {
        editorCard(title: label("Home address", "ที่อยู่บ้าน"), icon: "house.fill") {
            editorTextField(label("House No., Street, Soi, Road", "บ้านเลขที่ ถนน ซอย"), text: $addressDetail)
                .onChange(of: addressDetail) { _, _ in updateFullAddress() }
            HStack(spacing: 12) {
                Picker(label("Province", "จังหวัด"), selection: $selectedProvinceId) {
                    Text("select_province_placeholder".t).tag(nil as Int?)
                    ForEach(ThailandAddressManager.shared.provinces) { province in
                        Text(province.displayName(for: appLanguage)).tag(province.id as Int?)
                    }
                }
                .onChange(of: selectedProvinceId) { _, _ in
                    selectedDistrictId = nil
                    selectedSubDistrictId = nil
                    postalCode = ""
                    updateFullAddress()
                }
                Picker(label("District", "อำเภอ/เขต"), selection: $selectedDistrictId) {
                    Text("select_district_placeholder".t).tag(nil as Int?)
                    ForEach(availableDistricts) { district in
                        Text(district.displayName(for: appLanguage)).tag(district.id as Int?)
                    }
                }
                .disabled(selectedProvinceId == nil)
                .onChange(of: selectedDistrictId) { _, _ in
                    selectedSubDistrictId = nil
                    postalCode = ""
                    updateFullAddress()
                }
            }
            HStack(spacing: 12) {
                Picker(label("Subdistrict", "ตำบล/แขวง"), selection: $selectedSubDistrictId) {
                    Text("select_subdistrict_placeholder".t).tag(nil as Int?)
                    ForEach(availableSubDistricts) { subdistrict in
                        Text(subdistrict.displayName(for: appLanguage)).tag(subdistrict.id as Int?)
                    }
                }
                .disabled(selectedDistrictId == nil)
                .onChange(of: selectedSubDistrictId, perform: updatePostalCodeAndAddress)
                TextField(label("Postal Code", "รหัสไปรษณีย์"), text: $postalCode)
                    .keyboardType(.numberPad)
                    .disabled(true)
                    .frame(width: 120)
            }
        }
    }

    private var bankingAndEmergencyCard: some View {
        editorCard(title: label("Banking and emergency contact", "ธนาคารและผู้ติดต่อฉุกเฉิน"), icon: "building.columns.fill") {
            Picker("bank_name".t, selection: $empBankName) {
                Text("select_bank".t).tag("")
                ForEach(thaiBanks) { bank in
                    Text(bank.displayName(for: appLanguage)).tag(bank.id)
                }
            }
            editorTextField(label("Account Number", "เลขที่บัญชี"), text: $empBankAccount, keyboard: .numberPad)
            Divider()
            editorTextField(label("Emergency contact", "ชื่อผู้ติดต่อฉุกเฉิน"), text: $empEmergencyContactName)
            editorTextField(label("Contact Phone Number", "เบอร์โทรผู้ติดต่อ"), text: $empEmergencyContactPhone, keyboard: .phonePad)
        }
    }

    private var availableDistricts: [ThaiDistrict] {
        ThailandAddressManager.shared.provinces
            .first(where: { $0.id == selectedProvinceId })?.districts ?? []
    }

    private var availableSubDistricts: [ThaiSubDistrict] {
        availableDistricts.first(where: { $0.id == selectedDistrictId })?.subDistricts ?? []
    }

    private func editorTextField(
        _ title: String,
        text: Binding<String>,
        keyboard: UIKeyboardType = .default
    ) -> some View {
        TextField(title, text: text)
            .keyboardType(keyboard)
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .background(Color.appSurface.opacity(0.55), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(Color.appBorderSubtle, lineWidth: 1))
    }

    private func editorCard<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: icon)
                .font(.headline.weight(.bold))
                .foregroundStyle(Color.textPrimary)
            content()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .apLiquidGlass(
            tint: Color.appAccent.opacity(0.035),
            allowNativeOnPad: true,
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
    }

    private func loadForm() {
        guard let employee else {
            empDateOfBirth = Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date()
            return
        }
        empFirstName = employee.firstName
        empLastName = employee.lastName
        empPhone = employee.phone ?? ""
        empNationalId = employee.nationalId ?? ""
        empEmploymentType = employee.employmentType
        empPayRate = employee.payRate
        empBankName = employee.bankName ?? ""
        empBankAccount = employee.bankAccountNumber ?? ""
        empEmail = employee.email ?? ""
        empAddress = employee.address ?? ""
        addressDetail = employee.address ?? ""
        empEmergencyContactName = employee.emergencyContactName ?? ""
        empEmergencyContactPhone = employee.emergencyContactPhone ?? ""
        empJoinedAt = employee.joinedAt
        if let res = employee.resignedAt {
            hasResigned = true
            empResignedAt = res
        }
        if let dob = employee.dateOfBirth {
            specifyDOB = true
            empDateOfBirth = dob
        } else {
            empDateOfBirth = Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date()
        }
        if let user = employee.user {
            empRoleId = resolveRoleForEditing(user: user, employee: employee)
        }
        faceEmbeddingData = employee.faceEmbeddingData
        faceRegisteredAt = employee.faceRegisteredAt
        faceEmbeddingNeedsRemoteClear = employee.faceEmbeddingNeedsRemoteClear
    }

    private func updateFullAddress() {
        guard let pId = selectedProvinceId,
              let province = ThailandAddressManager.shared.provinces.first(where: { $0.id == pId }) else {
            empAddress = addressDetail
            return
        }
        let pName = province.displayName(for: appLanguage)
        var fullAddress = addressDetail
        if let dId = selectedDistrictId,
           let district = province.districts.first(where: { $0.id == dId }) {
            let dName = district.displayName(for: appLanguage)
            let isBangkok = (pId == 1)
            fullAddress += " " + (isBangkok ? (appLanguage == "th" ? "เขต" : "") : (appLanguage == "th" ? "อ." : "Amphur ")) + dName
            if let sId = selectedSubDistrictId,
               let sub = district.subDistricts.first(where: { $0.id == sId }) {
                let sName = sub.displayName(for: appLanguage)
                fullAddress += " " + (isBangkok ? (appLanguage == "th" ? "แขวง" : "") : (appLanguage == "th" ? "ต." : "Tambon ")) + sName
                fullAddress += " " + pName
                if !postalCode.isEmpty { fullAddress += " " + postalCode }
            }
        }
        empAddress = fullAddress
    }

    private var accessRolePicker: some View {
        Picker(label("Access role", "สิทธิ์การใช้งาน"), selection: $empRoleId) {
            Text(label("No role", "ยังไม่กำหนดสิทธิ์")).tag(nil as UUID?)
            ForEach(roles) { role in
                Text(RestaurantRoleCatalog.canonicalName(for: role.name)).tag(role.id as UUID?)
            }
        }
    }

    /// Resolve old/local Role UUIDs to the active canonical Role row. Role
    /// names such as Manager and Store Manager are aliases of Restaurant
    /// Manager, so an old UUID must not make the Picker appear blank.
    private func resolveRoleForEditing(user: User, employee: Employee) -> UUID? {
        if let currentRole = user.role,
           roles.contains(where: { $0.id == currentRole.id }) {
            return currentRole.id
        }
        guard let currentRole = user.role else { return nil }
        let canonicalName = RestaurantRoleCatalog.canonicalName(for: currentRole.name)
        guard let replacement = roles.first(where: {
            RestaurantRoleCatalog.canonicalName(for: $0.name) == canonicalName
        }) else { return nil }

        if user.role?.id != replacement.id {
            user.role = replacement
            user.isSynced = false
            user.updatedAt = Date()
            employee.isSynced = false
            employee.updatedAt = Date()
        }
        return replacement.id
    }

    private var hasExistingPIN: Bool {
        employee?.user?.pinCodeHash?.isEmpty == false
    }

    @ViewBuilder
    private var employeeAccessSection: some View {
        editorCard(title: label("POS access PIN", "PIN สำหรับเข้าใช้งาน POS"), icon: "key.fill") {
            StaffPINEntryField(
                pin: $empPin,
                hasExistingPIN: hasExistingPIN,
                language: appLanguage
            )
            if hasExistingPIN {
                Label(
                    label("PIN is configured. Leave blank to keep it.", "กำหนด PIN แล้ว เว้นว่างเพื่อใช้ PIN เดิม"),
                    systemImage: "checkmark.shield.fill"
                )
                .font(.caption)
                .foregroundStyle(Color.appTeal)
            }
            Text(employeePINHelpText)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
        }
    }

    private var employeePINHelpText: String {
        label(
            "Username and password are no longer used. The PIN is the only employee sign-in credential.",
            "ระบบยกเลิก Username และ Password แล้ว ใช้ PIN เป็นข้อมูลเข้าสู่ระบบเพียงอย่างเดียว"
        )
    }

    @ViewBuilder
    private var employeeBiometricsSection: some View {
        editorCard(title: label("Employee face verification", "การยืนยันใบหน้าพนักงาน"), icon: "faceid") {
            HStack {
                biometricRegistrationStatus
                Spacer()
                biometricStatusIcon
                biometricRegistrationButton
                if faceEmbeddingData != nil {
                    biometricResetButton
                }
            }
            Text(biometricTestingHelpText)
                .font(.caption2)
                .foregroundStyle(Color.textSecondary)
            if let faceMessage {
                Text(faceMessage)
                    .font(.caption)
                    .foregroundStyle(Color.appAmber)
            }
        }
    }

    private var biometricRegistrationStatus: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label("Employee Face Recognition", "ระบบจดจำใบหน้าพนักงาน"))
                .fontWeight(.semibold)
            Text(faceEmbeddingData == nil
                 ? label("Not registered", "ยังไม่ได้ลงทะเบียน")
                 : label("Registered on this device", "ลงทะเบียนบนอุปกรณ์นี้แล้ว"))
                .font(.caption)
                .foregroundColor(.appAmber)
        }
    }

    private var biometricStatusIcon: some View {
        Image(systemName: faceEmbeddingData == nil
              ? "person.crop.circle.badge.plus"
              : "checkmark.seal.fill")
            .foregroundColor(.textTertiary)
    }

    private var biometricRegistrationButton: some View {
        Button {
            showFaceCamera = true
        } label: {
            Label(label("Register face", "ลงทะเบียนใบหน้า"), systemImage: "camera.fill")
        }
        .apGlassButton(prominent: true, tint: Color.appAccent)
        .disabled(isProcessingFace)
    }

    private var biometricResetButton: some View {
        Button(role: .destructive) {
            faceEmbeddingData = nil
            faceRegisteredAt = nil
            faceEmbeddingNeedsRemoteClear = true
        } label: {
            Text("reset_clear_btn".t)
                .font(.caption)
                .fontWeight(.bold)
        }
        .apGlassButton(tint: Color.appRose)
    }

    private var biometricTestingHelpText: String {
        label(
            "Capture one clear, front-facing employee photo in good lighting. Live head-turn verification is required when clocking in or out.",
            "ถ่ายใบหน้าพนักงานตรงกล้องเพียงคนเดียวในที่แสงเพียงพอ ระบบจะตรวจการหันศีรษะแบบสดขณะลงเวลา"
        )
    }

    private func updatePostalCodeAndAddress(_ newSubId: Int?) {
        let province = ThailandAddressManager.shared.provinces.first { $0.id == selectedProvinceId }
        let district = province?.districts.first { $0.id == selectedDistrictId }
        if let sub = district?.subDistricts.first(where: { $0.id == newSubId }) {
            postalCode = String(sub.zipCode)
        } else {
            postalCode = ""
        }
        updateFullAddress()
    }

    private func processFaceImage(_ image: UIImage?) {
        guard let image, let cgImage = image.cgImage else { return }
        isProcessingFace = true
        faceMessage = nil
        Task {
            do {
                let vector = try FaceEmbeddingService.shared.embedding(from: cgImage)
                let encoded = vector.withUnsafeBufferPointer { Data(buffer: $0) }
                await MainActor.run {
                    faceEmbeddingData = encoded
                    faceRegisteredAt = Date()
                    faceEmbeddingNeedsRemoteClear = false
                    isProcessingFace = false
                    faceMessage = label("Face template saved on-device.", "บันทึกข้อมูลจดจำใบหน้าไว้ในอุปกรณ์แล้ว")
                }
            } catch {
                await MainActor.run {
                    isProcessingFace = false
                    faceMessage = error.localizedDescription
                }
            }
        }
    }

    private func saveEmployee() {
        guard sessionManager.can(.staffManage) else {
            saveErrorMessage = "ไม่มีสิทธิ์จัดการพนักงาน"
            return
        }
        guard !trimmedFirstName.isEmpty, !trimmedLastName.isEmpty else {
            saveErrorMessage = label("First and last name are required.", "กรุณากรอกชื่อและนามสกุล")
            return
        }
        guard empPayRate > 0 else {
            saveErrorMessage = label("Pay rate must be greater than zero.", "อัตราค่าจ้างต้องมากกว่า 0 บาท")
            return
        }
        let hasExistingPIN = employee?.user?.pinCodeHash?.isEmpty == false
        guard empPin.range(of: #"^[0-9]{4}$"#, options: .regularExpression) != nil
                || (employee != nil && hasExistingPIN && empPin.isEmpty) else {
            saveErrorMessage = label("Enter exactly 4 numeric PIN digits.", "กรุณากรอก PIN เป็นตัวเลข 4 หลัก")
            return
        }
        guard empRoleId != nil, roles.contains(where: { $0.id == empRoleId }) else {
            saveErrorMessage = label("Select an access role.", "กรุณาเลือกตำแหน่งสำหรับเข้าใช้งาน")
            return
        }

        // An existing employee must have one canonical User identity before
        // its access role can be changed. Creating a new User here would fork
        // the login identity and leave employees.user_id inconsistent.
        if employee != nil, employee?.user == nil, empPin.isEmpty {
            saveErrorMessage = label(
                "This employee has no linked login account. Sync the employee identity before changing its role.",
                "พนักงานคนนี้ยังไม่ได้เชื่อมโยงบัญชีเข้าสู่ระบบ กรุณา Sync ข้อมูลก่อนเปลี่ยนตำแหน่ง"
            )
            return
        }

        let selectedRole = roles.first(where: { $0.id == empRoleId })
        if employee?.user != nil || empPin.isEmpty == false {
            guard sessionManager.canAssignRole(selectedRole ?? employee?.user?.role, to: employee?.id),
                  employee?.user?.role.map({ PermissionService.permissions(for: $0).isSubset(of: sessionManager.currentStaffSession?.permissions ?? []) }) ?? true else {
                saveErrorMessage = "ไม่มีสิทธิ์จัดการบัญชีหรือกำหนดบทบาทนี้"
                return
            }
        }
        let targetEmp: Employee

        if let emp = employee {
            emp.firstName = trimmedFirstName
            emp.lastName = trimmedLastName
            emp.phone = empPhone.isEmpty ? nil : empPhone
            emp.nationalId = empNationalId.isEmpty ? nil : empNationalId
            emp.employmentType = empEmploymentType
            emp.payRate = empPayRate
            emp.bankName = empBankName.isEmpty ? nil : empBankName
            emp.bankAccountNumber = empBankAccount.isEmpty ? nil : empBankAccount
            emp.email = empEmail.isEmpty ? nil : empEmail
            emp.address = empAddress.isEmpty ? nil : empAddress
            emp.emergencyContactName = empEmergencyContactName.isEmpty ? nil : empEmergencyContactName
            emp.emergencyContactPhone = empEmergencyContactPhone.isEmpty ? nil : empEmergencyContactPhone
            emp.joinedAt = empJoinedAt
            emp.resignedAt = hasResigned ? empResignedAt : nil
            emp.branchId = BranchContext.shared.activeBranchIDString.isEmpty ? emp.branchId : BranchContext.shared.activeBranchIDString
            emp.staffAppEnabled = true
            emp.dateOfBirth = specifyDOB ? empDateOfBirth : nil
            emp.faceEmbeddingData = faceEmbeddingData
            emp.faceRegisteredAt = faceEmbeddingData == nil ? nil : (faceRegisteredAt ?? Date())
            emp.faceEmbeddingNeedsRemoteClear = faceEmbeddingNeedsRemoteClear
            emp.updatedAt = Date()
            emp.isSynced = false
            targetEmp = emp
        } else {
            let newEmp = Employee(
                firstName: trimmedFirstName,
                lastName: trimmedLastName,
                phone: empPhone.isEmpty ? nil : empPhone,
                nationalId: empNationalId.isEmpty ? nil : empNationalId,
                bankAccountNumber: empBankAccount.isEmpty ? nil : empBankAccount,
                bankName: empBankName.isEmpty ? nil : empBankName,
                employmentType: empEmploymentType,
                payRate: empPayRate,
                joinedAt: empJoinedAt,
                resignedAt: hasResigned ? empResignedAt : nil,
                branchId: BranchContext.shared.activeBranchIDString,
                staffAppEnabled: true,
                faceEmbeddingData: faceEmbeddingData,
                faceRegisteredAt: faceEmbeddingData == nil ? nil : (faceRegisteredAt ?? Date()),
                faceEmbeddingNeedsRemoteClear: false,
                email: empEmail.isEmpty ? nil : empEmail,
                dateOfBirth: specifyDOB ? empDateOfBirth : nil,
                address: empAddress.isEmpty ? nil : empAddress,
                emergencyContactName: empEmergencyContactName.isEmpty ? nil : empEmergencyContactName,
                emergencyContactPhone: empEmergencyContactPhone.isEmpty ? nil : empEmergencyContactPhone
            )
            modelContext.insert(newEmp)
            targetEmp = newEmp
        }

        if empPin.isEmpty == false || targetEmp.user != nil {
            let userEmail = empEmail.isEmpty ? nil : empEmail
            let existingUser = targetEmp.user ?? {
                let empId = targetEmp.id
                var userDesc = FetchDescriptor<User>()
                let users = (try? modelContext.fetch(userDesc)) ?? []
                return users.first(where: { $0.employeeProfile?.id == empId })
            }()

            if let user = existingUser {
                user.email = userEmail
                user.role = selectedRole
                user.isActive = true
                user.isDeleted = false
                if !empPin.isEmpty { user.pinCodeHash = SecurityHelper.hashPIN(empPin) }
                user.updatedAt = Date()
                user.isSynced = false
                targetEmp.user = user
                user.employeeProfile = targetEmp
            } else {
                let pHash = SecurityHelper.hashPIN(UUID().uuidString)
                let pinValue = SecurityHelper.hashPIN(empPin)
                let newUser = User(
                    username: "employee-\(targetEmp.id.uuidString.lowercased())",
                    email: userEmail,
                    passwordHash: pHash,
                    pinCodeHash: pinValue,
                    role: selectedRole
                )
                modelContext.insert(newUser)
                targetEmp.user = newUser
                newUser.employeeProfile = targetEmp
            }
        }

        guard modelContext.saveWithLogging(label: "EmployeeEditorView.save") else {
            modelContext.rollback()
            saveErrorMessage = "The employee credentials could not be saved. No changes were applied."
            return
        }
        onDismiss()
        Task { await SyncEngine.shared.syncAll(modelContext: modelContext) }
    }
}

private struct FaceCameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage?) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraDevice = .front
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: FaceCameraPicker
        init(_ parent: FaceCameraPicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.onImage(info[.originalImage] as? UIImage)
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
