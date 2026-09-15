import SwiftUI
import SwiftData

/// Schedule workspace: shifts + leave as compact sub-segments.
struct EmployeeScheduleHubView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Employee.firstName) private var employees: [Employee]
    @Query private var allShifts: [EmployeeShift]
    @Query(filter: #Predicate<EmployeeLeave> { !$0.isDeleted && $0.status == "approved" })
    private var approvedLeaves: [EmployeeLeave]

    @AppStorage("app_language") private var appLanguage = "en"

    @State private var subSection: SubSection = .shifts
    @State private var showingShiftSheet = false
    @State private var showingCalendarScheduler = false
    @State private var editingShift: EmployeeShift?
    @State private var shiftEmployeeId: UUID?
    @State private var selectedEmployeeIds: Set<UUID> = []
    @State private var shiftStart = Date()
    @State private var shiftEnd = Date().addingTimeInterval(28800)
    @State private var shiftRole = "Cashier"
    @State private var shiftNotes = ""
    @State private var validationMessage: String?

    enum SubSection: String, CaseIterable, Identifiable {
        case shifts, leave
        var id: String { rawValue }
        var title: String {
            switch self {
            case .shifts: return "employee_schedule_shifts".t
            case .leave: return "leave_management_tab".t
            }
        }
    }

    private var shifts: [EmployeeShift] {
        employees.flatMap(\.shifts).sorted { $0.scheduledStart > $1.scheduledStart }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 3) {
                    ForEach(SubSection.allCases) { item in
                        Button {
                            withAnimation(.easeInOut(duration: 0.12)) { subSection = item }
                        } label: {
                            Text(item.title)
                                .font(.system(size: 11, weight: .semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .foregroundStyle(subSection == item ? Color.white : Color.textSecondary)
                                .background(subSection == item ? Color(hex: "0F766E") : Color.appSurfaceHigh)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer()

                if subSection == .shifts {
                    Button {
                        showingCalendarScheduler = true
                    } label: {
                        Label("open_scheduler".t, systemImage: "calendar")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .foregroundStyle(Color(hex: "0F766E"))
                            .background(Color(hex: "0F766E").opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        addShift()
                    } label: {
                        Label("schedule_shift".t, systemImage: "plus")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .foregroundStyle(.white)
                            .background(Color(hex: "0F766E"), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, APSpacing.md)
            .padding(.vertical, 8)
            .background(Color.appSurface)
            .overlay(alignment: .bottom) { Divider().background(Color.appDivider) }

            Group {
                if subSection == .shifts {
                    shiftsList
                } else {
                    LeaveManagementView()
                }
            }
        }
        .background(Color.appBackground)
        .sheet(isPresented: $showingShiftSheet) {
            shiftForm
        }
        .fullScreenCover(isPresented: $showingCalendarScheduler) {
            ShiftSchedulerCalendarView()
        }
        .alert("Unable to save shift", isPresented: Binding(
            get: { validationMessage != nil },
            set: { if !$0 { validationMessage = nil } }
        )) {
            Button("OK", role: .cancel) { validationMessage = nil }
        } message: {
            Text(validationMessage ?? "")
        }
    }

    private var shiftsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if shifts.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 28))
                            .foregroundStyle(Color.textTertiary)
                        Text("no_shifts_scheduled".t)
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 48)
                } else {
                    ForEach(shifts.prefix(60)) { shift in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(shift.employee?.firstName ?? "Staff") \(shift.employee?.lastName ?? "")")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.textPrimary)
                                Text(shift.role ?? "General Staff")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color.textTertiary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(shift.scheduledStart, style: .date)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Color.textPrimary)
                                Text("\(shift.scheduledStart, style: .time) – \(shift.scheduledEnd, style: .time)")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color.textSecondary)
                            }
                            Button {
                                editShift(shift)
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color(hex: "0F766E"))
                                    .frame(width: 28, height: 28)
                                    .background(Color(hex: "0F766E").opacity(0.1), in: Circle())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .overlay(alignment: .bottom) {
                            Divider().background(Color.appDivider)
                        }
                    }
                }
            }
        }
    }

    private var shiftForm: some View {
        NavigationStack {
            Form {
                if editingShift == nil {
                    Section(header: Text("select_employees_batch".t)) {
                        ForEach(employees) { emp in
                            HStack {
                                Text("\(emp.firstName) \(emp.lastName)")
                                Spacer()
                                Image(systemName: selectedEmployeeIds.contains(emp.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedEmployeeIds.contains(emp.id) ? Color(hex: "0F766E") : Color.textTertiary)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if selectedEmployeeIds.contains(emp.id) {
                                    selectedEmployeeIds.remove(emp.id)
                                } else {
                                    selectedEmployeeIds.insert(emp.id)
                                }
                            }
                        }
                    }
                } else {
                    Section(header: Text("employee_header".t)) {
                        Picker("Select Employee", selection: $shiftEmployeeId) {
                            Text("choose_dropdown_placeholder".t).tag(nil as UUID?)
                            ForEach(employees) { emp in
                                Text("\(emp.firstName) \(emp.lastName)").tag(emp.id as UUID?)
                            }
                        }
                    }
                }

                Section(header: Text("time_date_header".t)) {
                    DatePicker("starts_field".t, selection: $shiftStart)
                    DatePicker("ends_field".t, selection: $shiftEnd)
                }

                Section(header: Text("role_notes_header".t)) {
                    TextField("role_field_placeholder".t, text: $shiftRole)
                    TextField("notes_field".t, text: $shiftNotes)
                }
            }
            .navigationTitle(editingShift == nil ? "schedule_shift".t : "Edit Shift")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel_btn".t) {
                        showingShiftSheet = false
                        editingShift = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("save_btn".t, action: saveShift)
                        .disabled(editingShift == nil
                                  ? (selectedEmployeeIds.isEmpty || shiftStart >= shiftEnd)
                                  : (shiftEmployeeId == nil || shiftStart >= shiftEnd))
                }
            }
        }
        .apColorScheme()
    }

    private func addShift() {
        editingShift = nil
        shiftEmployeeId = employees.first?.id
        selectedEmployeeIds = Set(employees.prefix(1).map(\.id))
        shiftStart = Date()
        shiftEnd = Date().addingTimeInterval(28800)
        shiftRole = "Cashier"
        shiftNotes = ""
        showingShiftSheet = true
    }

    private func editShift(_ shift: EmployeeShift) {
        editingShift = shift
        shiftEmployeeId = shift.employee?.id
        selectedEmployeeIds = []
        if let id = shift.employee?.id { selectedEmployeeIds.insert(id) }
        shiftStart = shift.scheduledStart
        shiftEnd = shift.scheduledEnd
        shiftRole = shift.role ?? ""
        shiftNotes = shift.notes ?? ""
        showingShiftSheet = true
    }

    private func saveShift() {
        let employeeIds = editingShift == nil
            ? selectedEmployeeIds
            : Set(shiftEmployeeId.map { [$0] } ?? [])
        for employeeId in employeeIds {
            let intervals = allShifts.filter { !$0.isDeleted && $0.employee?.id == employeeId }.map {
                ShiftSchedulingPolicy.Interval(id: $0.id, start: $0.scheduledStart, end: $0.scheduledEnd)
            }
            if ShiftSchedulingPolicy.hasConflict(start: shiftStart, end: shiftEnd, existing: intervals, excluding: editingShift?.id) {
                validationMessage = "This employee already has an overlapping shift."
                return
            }
            if approvedLeaves.contains(where: {
                $0.employee?.id == employeeId &&
                ShiftSchedulingPolicy.overlaps(
                    start: shiftStart,
                    end: shiftEnd,
                    otherStart: Calendar.current.startOfDay(for: $0.startDate),
                    otherEnd: Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: $0.endDate)) ?? $0.endDate
                )
            }) {
                validationMessage = "This employee has approved leave during the selected time."
                return
            }
        }
        if let sh = editingShift {
            guard let empId = shiftEmployeeId,
                  let emp = employees.first(where: { $0.id == empId }) else { return }
            sh.employee = emp
            sh.scheduledStart = shiftStart
            sh.scheduledEnd = shiftEnd
            sh.role = shiftRole.isEmpty ? nil : shiftRole
            sh.notes = shiftNotes.isEmpty ? nil : shiftNotes
            sh.updatedAt = Date()
            sh.isSynced = false
        } else {
            for empId in selectedEmployeeIds {
                guard let emp = employees.first(where: { $0.id == empId }) else { continue }
                let newShift = EmployeeShift(
                    employee: emp,
                    scheduledStart: shiftStart,
                    scheduledEnd: shiftEnd,
                    role: shiftRole.isEmpty ? nil : shiftRole,
                    notes: shiftNotes.isEmpty ? nil : shiftNotes
                )
                modelContext.insert(newShift)
            }
        }
        modelContext.saveWithLogging(label: "EmployeeScheduleHubView.saveShift")
        showingShiftSheet = false
        editingShift = nil
    }
}
