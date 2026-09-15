import SwiftUI
import SwiftData
import UIKit

/// Enterprise weekly roster: rows = employees, columns = days, cells = shift chips.
/// Shift templates (morning / afternoon / evening) prefill times; Custom allows free pickers.
struct ShiftSchedulerCalendarView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Employee.firstName) private var employees: [Employee]
    @Query private var allShifts: [EmployeeShift]
    @Query(filter: #Predicate<EmployeeLeave> { !$0.isDeleted && $0.status == "approved" })
    private var approvedLeaves: [EmployeeLeave]

    @AppStorage("app_language") private var appLanguage = "en"

    @State private var currentWeekStart = Date()
    @State private var searchText = ""

    @State private var showingFormSheet = false
    @State private var editingShift: EmployeeShift?
    @State private var shiftEmployeeId: UUID?
    @State private var selectedEmployeeIds: Set<UUID> = []
    @State private var shiftStart = Date()
    @State private var shiftEnd = Date().addingTimeInterval(28800)
    @State private var shiftRole = "Cashier"
    @State private var shiftNotes = ""
    @State private var selectedTemplate: ShiftTimeTemplate = .morning
    @State private var formAnchorDay: Date?
    @State private var validationMessage: String?

    private let nameColWidth: CGFloat = 128
    private let hoursColWidth: CGFloat = 56
    private let rowHeight: CGFloat = 44

    private var weekDays: [Date] {
        daysInWeek(for: currentWeekStart)
    }

    private var activeEmployees: [Employee] {
        employees.filter { $0.resignedAt == nil }
    }

    private var filteredEmployees: [Employee] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return activeEmployees }
        return activeEmployees.filter {
            "\($0.firstName) \($0.lastName)".lowercased().contains(q)
                || ($0.phone?.lowercased().contains(q) ?? false)
        }
    }

    private var weekShiftCount: Int {
        weekDays.reduce(0) { $0 + shifts(for: nil, on: $1).count }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                weekNavigationHeader
                Divider().background(Color.appDivider)
                toolbarRow
                Divider().background(Color.appDivider)
                dayHeaderRow
                Divider().background(Color.appDivider)

                if filteredEmployees.isEmpty {
                    emptyEmployees
                } else {
                    rosterScroll
                }
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("shift_planner".t)
            .apNavBar()
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: {
                        Text("close_btn_label".t)
                            .fontWeight(.bold)
                            .foregroundColor(.appRose)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 14) {
                        Button(action: exportReportPDF) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .disabled(allShifts.filter { !$0.isDeleted }.isEmpty)

                        Button(action: addShiftAction) {
                            Image(systemName: "plus")
                        }
                        .disabled(activeEmployees.isEmpty)
                    }
                }
            }
            .sheet(isPresented: $showingFormSheet) {
                shiftFormSheet
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
        .apColorScheme()
        .onAppear {
            currentWeekStart = startOfWeek(for: Date())
        }
    }

    // MARK: - Headers

    private var weekNavigationHeader: some View {
        HStack {
            Button {
                APHaptic.trigger()
                currentWeekStart = Calendar.current.date(byAdding: .day, value: -7, to: currentWeekStart) ?? currentWeekStart
            } label: {
                Label("prev_week_btn".t, systemImage: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: "0F766E"))
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 2) {
                Text(weekRangeString(for: weekDays))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                Text("\(weekShiftCount) " + "roster_shifts_this_week".t)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.textTertiary)
            }

            Spacer()

            Button {
                APHaptic.trigger()
                currentWeekStart = Calendar.current.date(byAdding: .day, value: 7, to: currentWeekStart) ?? currentWeekStart
            } label: {
                HStack(spacing: 4) {
                    Text("next_week_btn".t)
                    Image(systemName: "chevron.right")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(hex: "0F766E"))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, APSpacing.md)
        .padding(.vertical, 10)
        .background(Color.appSurface)
    }

    private var toolbarRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textTertiary)
                TextField("employee_search_placeholder".t, text: $searchText)
                    .font(.system(size: 12))
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.appSurfaceHigh, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Spacer()

            Text("\(filteredEmployees.count) " + "timecard_stat_staff".t)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.textTertiary)
        }
        .padding(.horizontal, APSpacing.md)
        .padding(.vertical, 8)
        .background(Color.appSurface)
    }

    private var dayHeaderRow: some View {
        HStack(spacing: 0) {
            Text("employee_header".t)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.textTertiary)
                .frame(width: nameColWidth, alignment: .leading)
                .padding(.leading, 10)

            ForEach(weekDays, id: \.self) { day in
                let isToday = Calendar.current.isDateInToday(day)
                VStack(spacing: 1) {
                    Text(dayOfWeekAbbreviation(for: day))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.textTertiary)
                    Text(dayOfMonthString(for: day))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(isToday ? Color.white : Color.textPrimary)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(isToday ? Color(hex: "0F766E") : Color.clear))
                }
                .frame(maxWidth: .infinity)
            }

            Text("roster_hrs_week".t)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.textTertiary)
                .frame(width: hoursColWidth)
                .padding(.trailing, 6)
        }
        .padding(.vertical, 8)
        .background(Color.appSurfaceHigh.opacity(0.55))
    }

    // MARK: - Roster grid

    private var rosterScroll: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredEmployees) { emp in
                    employeeRow(emp)
                }
            }
        }
    }

    private func employeeRow(_ emp: Employee) -> some View {
        let weekHours = weeklyHours(for: emp)

        return HStack(spacing: 0) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color(hex: "0F766E").opacity(0.14))
                        .frame(width: 26, height: 26)
                    Text(String(emp.firstName.prefix(1) + emp.lastName.prefix(1)))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color(hex: "0F766E"))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(emp.firstName) \(emp.lastName)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    Text(emp.employmentType.capitalized)
                        .font(.system(size: 9))
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(1)
                }
            }
            .frame(width: nameColWidth, alignment: .leading)
            .padding(.leading, 8)

            ForEach(weekDays, id: \.self) { day in
                dayCell(employee: emp, day: day)
                    .frame(maxWidth: .infinity)
            }

            Text(String(format: "%.1f", weekHours))
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(weekHours > 48 ? Color.appRose : Color.textPrimary)
                .frame(width: hoursColWidth)
                .padding(.trailing, 6)
        }
        .frame(height: rowHeight)
        .background(Color.appBackground)
        .overlay(alignment: .bottom) {
            Divider().background(Color.appDivider)
        }
    }

    private func dayCell(employee: Employee, day: Date) -> some View {
        let dayShifts = shifts(for: employee, on: day)

        return Button {
            if let first = dayShifts.first {
                editShiftAction(first)
            } else {
                addShiftFor(employee: employee, day: day)
            }
        } label: {
            Group {
                if let shift = dayShifts.first {
                    VStack(spacing: 1) {
                        Text(timeRangeLabel(shift))
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        if let role = shift.role, !role.isEmpty {
                            Text(role)
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(.white.opacity(0.9))
                                .lineLimit(1)
                        }
                        if dayShifts.count > 1 {
                            Text("+\(dayShifts.count - 1)")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(chipColor(for: shift.role))
                    )
                } else {
                    Text("roster_off".t)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color.textTertiary)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.appBorderSubtle, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                        )
                }
            }
            .padding(.horizontal, 2)
        }
        .buttonStyle(.plain)
    }

    private var emptyEmployees: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.text.rectangle")
                .font(.system(size: 28))
                .foregroundStyle(Color.textTertiary)
            Text("no_employees_registered".t)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Form

    private var roleSuggestions: [String] {
        if appLanguage == "th" {
            return ["แคชเชียร์", "กุ๊ก/คนครัว", "พนักงานเสิร์ฟ", "ผู้จัดการ", "บาริสต้า", "พนักงานทำความสะอาด"]
        }
        return ["Cashier", "Cook", "Waiter", "Manager", "Barista", "Cleaner"]
    }

    private var shiftFormSheet: some View {
        NavigationStack {
            Form {
                Section(header: Text("roster_shift_template".t)) {
                    Picker("roster_shift_template".t, selection: $selectedTemplate) {
                        ForEach(ShiftTimeTemplate.allCases) { template in
                            Text(template.title).tag(template)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedTemplate) { _, newValue in
                        applyTemplate(newValue)
                    }

                    if selectedTemplate != .custom {
                        Text(templateSummary)
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }

                if editingShift == nil && formAnchorDay == nil {
                    Section(header: Text("select_employees_batch".t)) {
                        ForEach(activeEmployees) { emp in
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
                } else if editingShift != nil || formAnchorDay != nil {
                    Section(header: Text("employee_header".t)) {
                        Picker("Select Employee", selection: $shiftEmployeeId) {
                            Text("choose_dropdown_placeholder".t).tag(nil as UUID?)
                            ForEach(activeEmployees) { emp in
                                Text("\(emp.firstName) \(emp.lastName)").tag(emp.id as UUID?)
                            }
                        }
                    }
                }

                Section(header: Text("time_date_header".t)) {
                    if selectedTemplate == .custom {
                        DatePicker("starts_field".t, selection: $shiftStart)
                        DatePicker("ends_field".t, selection: $shiftEnd)
                    } else {
                        DatePicker("starts_field".t, selection: $shiftStart, displayedComponents: .date)
                            .onChange(of: shiftStart) { _, newDay in
                                applyTemplate(selectedTemplate, anchoring: newDay)
                            }
                        HStack {
                            Text(timeLabel(shiftStart) + " – " + timeLabel(shiftEnd))
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            Spacer()
                            Text(selectedTemplate.title)
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                }

                Section(header: Text("role_notes_header".t)) {
                    HStack {
                        TextField("role_field_placeholder".t, text: $shiftRole)
                        Menu {
                            ForEach(roleSuggestions, id: \.self) { role in
                                Button(role) { shiftRole = role }
                            }
                        } label: {
                            Image(systemName: "tag.circle.fill")
                                .foregroundStyle(Color(hex: "0F766E"))
                        }
                    }
                    TextField("notes_field".t, text: $shiftNotes)
                }

                if editingShift != nil {
                    Section {
                        Button(role: .destructive, action: deleteShift) {
                            Text("delete_shift_btn".t)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .navigationTitle(editingShift == nil ? "schedule_shift".t : "Edit Shift")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel_btn".t) {
                        showingFormSheet = false
                        editingShift = nil
                        formAnchorDay = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("save_btn".t, action: saveShift)
                        .disabled(!canSave)
                }
            }
        }
        .apColorScheme()
    }

    private var templateSummary: String {
        "\(selectedTemplate.title): \(timeLabel(shiftStart)) – \(timeLabel(shiftEnd))"
    }

    private var canSave: Bool {
        guard shiftStart < shiftEnd else { return false }
        if editingShift != nil || formAnchorDay != nil {
            return shiftEmployeeId != nil
        }
        return !selectedEmployeeIds.isEmpty
    }

    // MARK: - Data helpers

    private func shifts(for employee: Employee?, on day: Date) -> [EmployeeShift] {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: day)
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }

        return allShifts.filter { shift in
            guard !shift.isDeleted else { return false }
            if let employee, shift.employee?.id != employee.id { return false }
            return shift.scheduledStart < nextDay && shift.scheduledEnd > dayStart
        }
        .sorted { $0.scheduledStart < $1.scheduledStart }
    }

    private func weeklyHours(for employee: Employee) -> Double {
        guard let start = weekDays.first,
              let end = Calendar.current.date(byAdding: .day, value: 7, to: start) else { return 0 }
        let intervals = allShifts.filter { !$0.isDeleted && $0.employee?.id == employee.id }.map {
            ShiftSchedulingPolicy.Interval(id: $0.id, start: $0.scheduledStart, end: $0.scheduledEnd)
        }
        return ShiftSchedulingPolicy.hours(in: DateInterval(start: start, end: end), intervals: intervals)
    }

    private func timeRangeLabel(_ shift: EmployeeShift) -> String {
        "\(timeLabel(shift.scheduledStart))–\(timeLabel(shift.scheduledEnd))"
    }

    private func timeLabel(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt.string(from: date)
    }

    private func chipColor(for role: String?) -> Color {
        let r = (role ?? "").lowercased()
        if r.contains("cashier") || r.contains("แคชเชียร์") { return Color(hex: "0F766E") }
        if r.contains("cook") || r.contains("kitchen") || r.contains("กุ๊ก") || r.contains("ครัว") { return Color(hex: "D97706") }
        if r.contains("manager") || r.contains("ผู้จัดการ") { return Color(hex: "BE123C") }
        return Color(hex: "334155")
    }

    // MARK: - Calendar helpers

    private func startOfWeek(for date: Date) -> Date {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        let dayStart = calendar.startOfDay(for: date)
        if let interval = calendar.dateInterval(of: .weekOfYear, for: dayStart) {
            return interval.start
        }
        let weekday = calendar.component(.weekday, from: dayStart)
        let daysFromMonday = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -daysFromMonday, to: dayStart) ?? dayStart
    }

    private func daysInWeek(for date: Date) -> [Date] {
        let calendar = Calendar.current
        let start = startOfWeek(for: date)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private func dayOfWeekAbbreviation(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: appLanguage)
        formatter.dateFormat = "EEE"
        return formatter.string(from: date).uppercased()
    }

    private func dayOfMonthString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: appLanguage)
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }

    private func weekRangeString(for days: [Date]) -> String {
        guard let first = days.first, let last = days.last else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: appLanguage)
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return "\(formatter.string(from: first)) – \(formatter.string(from: last))"
    }

    // MARK: - Actions

    private func applyTemplate(_ template: ShiftTimeTemplate, anchoring: Date? = nil) {
        selectedTemplate = template
        guard template != .custom else { return }
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: anchoring ?? formAnchorDay ?? shiftStart)
        let start = calendar.date(bySettingHour: template.startHour, minute: template.startMinute, second: 0, of: day) ?? day
        var end = calendar.date(bySettingHour: template.endHour, minute: template.endMinute, second: 0, of: day) ?? day
        if template.crossesMidnight {
            end = calendar.date(byAdding: .day, value: 1, to: end) ?? end
        }
        shiftStart = start
        shiftEnd = end
    }

    private func addShiftFor(employee: Employee, day: Date) {
        APHaptic.trigger()
        editingShift = nil
        formAnchorDay = day
        shiftEmployeeId = employee.id
        selectedEmployeeIds = [employee.id]
        selectedTemplate = .morning
        applyTemplate(.morning, anchoring: day)
        shiftRole = "Cashier"
        shiftNotes = ""
        showingFormSheet = true
    }

    private func editShiftAction(_ shift: EmployeeShift) {
        APHaptic.trigger()
        editingShift = shift
        formAnchorDay = shift.scheduledStart
        shiftEmployeeId = shift.employee?.id
        selectedEmployeeIds = []
        if let empId = shift.employee?.id {
            selectedEmployeeIds.insert(empId)
        }
        shiftStart = shift.scheduledStart
        shiftEnd = shift.scheduledEnd
        shiftRole = shift.role ?? ""
        shiftNotes = shift.notes ?? ""
        selectedTemplate = ShiftTimeTemplate.matching(start: shift.scheduledStart, end: shift.scheduledEnd) ?? .custom
        showingFormSheet = true
    }

    private func addShiftAction() {
        editingShift = nil
        formAnchorDay = nil
        shiftEmployeeId = activeEmployees.first?.id
        selectedEmployeeIds = Set(activeEmployees.prefix(1).map(\.id))
        let anchor = weekDays.first(where: { Calendar.current.isDateInToday($0) }) ?? weekDays.first ?? Date()
        selectedTemplate = .morning
        applyTemplate(.morning, anchoring: anchor)
        shiftRole = "Cashier"
        shiftNotes = ""
        showingFormSheet = true
    }

    private func saveShift() {
        guard canSave else { return }

        let employeeIds = editingShift != nil || formAnchorDay != nil
            ? Set(shiftEmployeeId.map { [$0] } ?? [])
            : selectedEmployeeIds
        for employeeId in employeeIds {
            let intervals = allShifts.filter { !$0.isDeleted && $0.employee?.id == employeeId }.map {
                ShiftSchedulingPolicy.Interval(id: $0.id, start: $0.scheduledStart, end: $0.scheduledEnd)
            }
            if ShiftSchedulingPolicy.hasConflict(
                start: shiftStart,
                end: shiftEnd,
                existing: intervals,
                excluding: editingShift?.id
            ) {
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
                  let emp = activeEmployees.first(where: { $0.id == empId }) else { return }
            sh.employee = emp
            sh.scheduledStart = shiftStart
            sh.scheduledEnd = shiftEnd
            sh.role = shiftRole.isEmpty ? nil : shiftRole
            sh.notes = shiftNotes.isEmpty ? nil : shiftNotes
            sh.updatedAt = Date()
            sh.isSynced = false
        } else if formAnchorDay != nil {
            guard let empId = shiftEmployeeId,
                  let emp = activeEmployees.first(where: { $0.id == empId }) else { return }
            let newShift = EmployeeShift(
                employee: emp,
                scheduledStart: shiftStart,
                scheduledEnd: shiftEnd,
                role: shiftRole.isEmpty ? nil : shiftRole,
                notes: shiftNotes.isEmpty ? nil : shiftNotes
            )
            modelContext.insert(newShift)
        } else {
            for empId in selectedEmployeeIds {
                guard let emp = activeEmployees.first(where: { $0.id == empId }) else { continue }
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

        modelContext.saveWithLogging(label: #function)
        showingFormSheet = false
        editingShift = nil
        formAnchorDay = nil
        APHaptic.trigger()
    }

    private func deleteShift() {
        if let sh = editingShift {
            sh.isDeleted = true
            sh.isSynced = false
            sh.updatedAt = Date()
            modelContext.saveWithLogging(label: #function)
        }
        showingFormSheet = false
        editingShift = nil
        formAnchorDay = nil
    }

    private func exportReportPDF() {
        let renderer = ImageRenderer(content: ShiftReportView(weekDays: weekDays, allShifts: allShifts, appLanguage: appLanguage))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Weekly_Shift_Schedule_\(Date().timeIntervalSince1970).pdf")

        renderer.render { size, context in
            var box = CGRect(origin: .zero, size: size)
            guard let pdfContext = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            pdfContext.beginPDFPage(nil)
            context(pdfContext)
            pdfContext.endPDFPage()
            pdfContext.closePDF()

            DispatchQueue.main.async {
                let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let rootVC = windowScene.windows.first?.rootViewController {
                    if let popover = activityVC.popoverPresentationController {
                        popover.sourceView = rootVC.view
                        popover.sourceRect = CGRect(x: rootVC.view.bounds.midX, y: rootVC.view.bounds.midY, width: 0, height: 0)
                        popover.permittedArrowDirections = []
                    }
                    rootVC.present(activityVC, animated: true)
                }
            }
        }
    }
}

// MARK: - Shift time templates (day parts)

enum ShiftTimeTemplate: String, CaseIterable, Identifiable {
    case morning
    case afternoon
    case evening
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .morning: return "roster_template_morning".t
        case .afternoon: return "roster_template_afternoon".t
        case .evening: return "roster_template_evening".t
        case .custom: return "roster_template_custom".t
        }
    }

    var startHour: Int {
        switch self {
        case .morning: return 9
        case .afternoon: return 14
        case .evening: return 17
        case .custom: return 9
        }
    }

    var startMinute: Int { 0 }

    var endHour: Int {
        switch self {
        case .morning: return 17
        case .afternoon: return 22
        case .evening: return 1
        case .custom: return 17
        }
    }

    var endMinute: Int { 0 }

    var crossesMidnight: Bool { self == .evening }

    static func matching(start: Date, end: Date, calendar: Calendar = .current) -> ShiftTimeTemplate? {
        let sh = calendar.component(.hour, from: start)
        let sm = calendar.component(.minute, from: start)
        let eh = calendar.component(.hour, from: end)
        let em = calendar.component(.minute, from: end)
        let crosses = !calendar.isDate(start, inSameDayAs: end)

        for template in [ShiftTimeTemplate.morning, .afternoon, .evening] where sm == 0 && em == 0 {
            if sh == template.startHour && eh == template.endHour && crosses == template.crossesMidnight {
                return template
            }
        }
        return nil
    }
}

// MARK: - Local translation helper

fileprivate extension String {
    func localized(for language: String) -> String { self.t }
}

// MARK: - ShiftReportView for PDF Generation

struct ShiftReportView: View {
    let weekDays: [Date]
    let allShifts: [EmployeeShift]
    let appLanguage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("weekly_shift_report_title".t)
                        .font(.title)
                        .fontWeight(.black)
                        .foregroundColor(.primary)
                    Text("Generated on \(Date().formatted(date: .long, time: .shortened))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 40))
                    .foregroundColor(.accentColor)
            }
            .padding(.bottom, 10)

            Divider()

            ForEach(weekDays, id: \.self) { day in
                let dayShifts = shiftsForDay(day)
                if !dayShifts.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(dayHeaderString(for: day))
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.accentColor)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(Color.accentColor.opacity(0.1))
                            .cornerRadius(4)

                        ForEach(dayShifts) { shift in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(shift.employee?.firstName ?? "Staff") \(shift.employee?.lastName ?? "")")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                    Text(shift.role ?? "Staff")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("\(shift.scheduledStart.formatted(date: .omitted, time: .shortened)) - \(shift.scheduledEnd.formatted(date: .omitted, time: .shortened))")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    if let notes = shift.notes, !notes.isEmpty {
                                        Text(notes)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 6)
                            Divider()
                        }
                    }
                    .padding(.bottom, 10)
                }
            }
        }
        .padding(40)
        .frame(width: 612)
    }

    private func shiftsForDay(_ date: Date) -> [EmployeeShift] {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)?.addingTimeInterval(-1) else { return [] }
        return allShifts.filter { shift in
            !shift.isDeleted && shift.scheduledStart <= dayEnd && shift.scheduledEnd >= dayStart
        }
    }

    private func dayHeaderString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: appLanguage)
        formatter.dateFormat = "EEEE, MMMM d, yyyy"
        return formatter.string(from: date)
    }
}
