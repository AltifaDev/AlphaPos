import SwiftUI
import SwiftData

struct ShiftSchedulerCalendarView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Query(sort: \Employee.firstName) private var employees: [Employee]
    @Query private var allShifts: [EmployeeShift]
    
    @AppStorage("app_language") private var appLanguage = "en"
    
    // Calendar Navigation State
    @State private var currentWeekStart = Date()
    
    // Form and Editing States
    @State private var showingFormSheet = false
    @State private var editingShift: EmployeeShift? = nil
    
    @State private var shiftEmployeeId: UUID? = nil
    @State private var selectedEmployeeIds: Set<UUID> = []
    @State private var animateIn = false
    @State private var shiftStart = Date()
    @State private var shiftEnd = Date().addingTimeInterval(28800)
    @State private var shiftRole = "Cashier"
    @State private var shiftNotes = ""
    
    private var weekDays: [Date] {
        daysInWeek(for: currentWeekStart)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // 1. Calendar Header (Week navigation)
                    weekNavigationHeader
                        .padding()
                        .background(Color.appSurface)
                    
                    Divider().background(Color.appDivider)
                    
                    // 2. Day-of-week Date Header Row
                    GeometryReader { geo in
                        VStack(spacing: 0) {
                            dayDateHeaderRow(width: geo.size.width)
                                .padding(.vertical, 8)
                                .background(Color.appSurface)
                            
                            Divider().background(Color.appDivider)
                            
                            // 3. Immersive Hour Timeline & Shift Card Grid
                            calendarGrid(size: geo.size)
                        }
                    }
                }
                .opacity(animateIn ? 1.0 : 0.0)
                .offset(y: animateIn ? 0 : 30)
            }
            .navigationTitle("shift_planner".localized(for: appLanguage))
            .apNavBar()
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Text("close_btn_label".t)
                            .fontWeight(.bold)
                            .foregroundColor(.appRose)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        Button(action: exportReportPDF) {
                            Label("share_btn_label".t, systemImage: "square.and.arrow.up")
                        }
                        .disabled(allShifts.isEmpty)
                        
                        Button(action: addShiftAction) {
                            Label("schedule_shift".localized(for: appLanguage), systemImage: "plus")
                        }
                        .disabled(employees.isEmpty)
                    }
                }
            }
            .sheet(isPresented: $showingFormSheet) {
                shiftFormSheet
            }
        }
        .apColorScheme()
        .onAppear {
            currentWeekStart = startOfWeek(for: Date())
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8, blendDuration: 0)) {
                animateIn = true
            }
        }
    }
    
    // MARK: - Header & Navigation Subviews
    
    private var weekNavigationHeader: some View {
        HStack {
            Button(action: {
                APHaptic.trigger()
                currentWeekStart = Calendar.current.date(byAdding: .day, value: -7, to: currentWeekStart) ?? currentWeekStart
            }) {
                HStack {
                    Image(systemName: "chevron.left")
                    Text("prev_week_btn".t)
                }
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.appAccent)
            }
            
            Spacer()
            
            Text(weekRangeString(for: weekDays))
                .font(.title3)
                .fontWeight(.black)
                .foregroundColor(.textPrimary)
            
            Spacer()
            
            Button(action: {
                APHaptic.trigger()
                currentWeekStart = Calendar.current.date(byAdding: .day, value: 7, to: currentWeekStart) ?? currentWeekStart
            }) {
                HStack {
                    Text("next_week_btn".t)
                    Image(systemName: "chevron.right")
                }
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.appAccent)
            }
        }
    }
    
    private func dayDateHeaderRow(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            let totalWidth = width
            let colWidth = totalWidth / 7
            
            ForEach(0..<7, id: \.self) { dayIndex in
                let dayDate = weekDays[dayIndex]
                let isToday = Calendar.current.isDateInToday(dayDate)
                
                VStack(spacing: 4) {
                    Text(dayOfWeekAbbreviation(for: dayDate))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.textSecondary)
                    
                    Text(dayOfMonthString(for: dayDate))
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(isToday ? .white : .textPrimary)
                        .padding(8)
                        .background(
                            Circle()
                                .fill(isToday ? Color.appAccent : Color.clear)
                                .frame(width: 32, height: 32)
                        )
                }
                .frame(width: colWidth)
            }
        }
    }
    
    // MARK: - Core Calendar Grid
    
    private func calendarGrid(size: CGSize) -> some View {
        ScrollView(.vertical, showsIndicators: true) {
            ZStack(alignment: .topLeading) {
                // Hour Grid Background Lines (Full Width)
                VStack(spacing: 0) {
                    ForEach(8..<22, id: \.self) { hour in
                        VStack {
                            Divider().background(Color.appDivider)
                            Spacer()
                        }
                        .frame(height: 60)
                    }
                }
                
                // Shift Cards & Touch Overlay
                let totalWidth = size.width
                let colWidth = totalWidth / 7
                
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { dayIndex in
                        let dayDate = weekDays[dayIndex]
                        
                        ZStack(alignment: .topLeading) {
                            // Overlay hour tap zones for quick scheduling
                            VStack(spacing: 0) {
                                ForEach(8..<22, id: \.self) { hour in
                                    Color.clear
                                        .frame(height: 60)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            addNewShiftAt(day: dayDate, hour: hour)
                                        }
                                }
                            }
                            
                            // Shift cards rendered on this column
                            let daySegments = shiftSegmentsForDay(dayDate)
                            ForEach(daySegments) { segment in
                                let yOffset = calculateYOffset(for: segment.displayStart)
                                
                                shiftCard(segment.shift, segmentStart: segment.displayStart, segmentEnd: segment.displayEnd)
                                    .frame(width: colWidth - 6)
                                    .offset(x: 3, y: yOffset)
                                    .onTapGesture {
                                        editShiftAction(segment.shift)
                                    }
                            }
                        }
                        .frame(width: colWidth)
                        .overlay(
                            Rectangle().fill(Color.appDivider).frame(width: 1), alignment: .leading
                        )
                    }
                }
            }
            .frame(height: 14 * 60) // 14 hours total, 60 pt height each
        }
    }
    
    private func shiftCard(_ shift: EmployeeShift, segmentStart: Date, segmentEnd: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(shift.role ?? "Staff")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(1)
            
            Text("\(shift.employee?.firstName ?? "Staff")")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(1)
            
            Text("\(segmentStart.formatted(date: .omitted, time: .shortened)) - \(segmentEnd.formatted(date: .omitted, time: .shortened))")
                .font(.system(size: 8))
                .foregroundColor(.white.opacity(0.8))
                .lineLimit(1)
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: APRadius.sm)
                .fill(cardColorForRole(shift.role))
        )
        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
    
    // MARK: - Scheduling Forms popovers
    
    private var roleSuggestions: [String] {
        if appLanguage == "th" {
            return ["แคชเชียร์", "กุ๊ก/คนครัว", "พนักงานเสิร์ฟ", "ผู้จัดการ", "บาริสต้า", "พนักงานทำความสะอาด"]
        } else {
            return ["Cashier", "Cook", "Waiter", "Manager", "Barista", "Cleaner"]
        }
    }

    private var shiftFormSheet: some View {
        NavigationStack {
            Form {
                if editingShift == nil {
                    Section(header: Text("select_employees_batch".localized(for: appLanguage))) {
                        HStack {
                            Button(action: {
                                selectedEmployeeIds = Set(employees.map { $0.id })
                            }) {
                                Text("select_all".localized(for: appLanguage))
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.appAccent)
                            }
                            .buttonStyle(.borderless)
                            
                            Spacer()
                            
                            Button(action: {
                                selectedEmployeeIds.removeAll()
                            }) {
                                Text("clear_all".localized(for: appLanguage))
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.appRose)
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.vertical, 4)
                        
                        ForEach(employees) { emp in
                            HStack {
                                Text("\(emp.firstName) \(emp.lastName)")
                                    .foregroundColor(.textPrimary)
                                Spacer()
                                if selectedEmployeeIds.contains(emp.id) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.appAccent)
                                } else {
                                    Image(systemName: "circle")
                                        .foregroundColor(.textTertiary)
                                }
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
                    Section(header: Text("employee_header".localized(for: appLanguage))) {
                        Picker("Select Employee", selection: $shiftEmployeeId) {
                            Text("Choose...").tag(nil as UUID?)
                            ForEach(employees) { emp in
                                Text("\(emp.firstName) \(emp.lastName)").tag(emp.id as UUID?)
                            }
                        }
                    }
                }
                
                Section(header: Text("time_date_header".localized(for: appLanguage))) {
                    DatePicker("starts_field".localized(for: appLanguage), selection: $shiftStart)
                    DatePicker("ends_field".localized(for: appLanguage), selection: $shiftEnd)
                }
                
                Section(header: Text("role_notes_header".localized(for: appLanguage))) {
                    HStack {
                        TextField("role_field_placeholder".localized(for: appLanguage), text: $shiftRole)
                        Menu {
                            ForEach(roleSuggestions, id: \.self) { role in
                                Button(role) {
                                    shiftRole = role
                                }
                            }
                        } label: {
                            Image(systemName: "tag.circle.fill")
                                .foregroundColor(.appAccent)
                                .font(.title3)
                        }
                    }
                    TextField("notes_field".localized(for: appLanguage), text: $shiftNotes)
                }
                
                if editingShift != nil {
                    Section {
                        Button(role: .destructive, action: deleteShift) {
                            Text("delete_shift_btn".localized(for: appLanguage))
                                .frame(maxWidth: .infinity)
                                .alignmentGuide(.leading) { _ in 0 }
                        }
                    }
                }
            }
            .navigationTitle(editingShift == nil ? "schedule_shift".localized(for: appLanguage) : "Edit Shift")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel_btn".localized(for: appLanguage)) {
                        showingFormSheet = false
                        editingShift = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("save_btn".localized(for: appLanguage)) {
                        saveShift()
                    }
                    .disabled(editingShift == nil ? (selectedEmployeeIds.isEmpty || shiftStart >= shiftEnd) : (shiftEmployeeId == nil || shiftStart >= shiftEnd))
                }
            }
        }
        .apColorScheme()
    }
    
    // MARK: - Helper Core Calculations
    
    private func startOfWeek(for date: Date) -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        components.weekday = 2 // Monday start
        return calendar.date(from: components) ?? date
    }
    
    private func daysInWeek(for date: Date) -> [Date] {
        let calendar = Calendar.current
        let start = startOfWeek(for: date)
        return (0..<7).compactMap { day in
            calendar.date(byAdding: .day, value: day, to: start)
        }
    }
    
    struct ShiftSegment: Identifiable {
        let id: String
        let shift: EmployeeShift
        let displayStart: Date
        let displayEnd: Date
    }
    
    private func shiftSegmentsForDay(_ date: Date) -> [ShiftSegment] {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)?.addingTimeInterval(-1) else { return [] }
        
        var segments: [ShiftSegment] = []
        
        for shift in allShifts {
            if shift.isDeleted { continue }
            
            // Check if shift overlaps with this day
            if shift.scheduledStart <= dayEnd && shift.scheduledEnd >= dayStart {
                // Calculate grid start & end on this day
                let gridStart = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: date) ?? date
                let gridEnd = calendar.date(bySettingHour: 22, minute: 0, second: 0, of: date) ?? date
                
                // Display start: if it started today, use shift start (clamped to gridStart). Otherwise gridStart.
                let displayStart: Date
                if calendar.isDate(shift.scheduledStart, inSameDayAs: date) {
                    displayStart = max(gridStart, shift.scheduledStart)
                } else {
                    displayStart = gridStart
                }
                
                // Display end: if it ends today, use shift end (clamped to gridEnd). Otherwise gridEnd.
                let displayEnd: Date
                if calendar.isDate(shift.scheduledEnd, inSameDayAs: date) {
                    displayEnd = min(gridEnd, shift.scheduledEnd)
                } else {
                    displayEnd = gridEnd
                }
                
                if displayStart < displayEnd {
                    let segmentId = "\(shift.id.uuidString)-\(calendar.component(.year, from: date))-\(calendar.component(.month, from: date))-\(calendar.component(.day, from: date))"
                    segments.append(ShiftSegment(id: segmentId, shift: shift, displayStart: displayStart, displayEnd: displayEnd))
                }
            }
        }
        return segments
    }
    
    private func calculateYOffset(for date: Date) -> CGFloat {
        let calendar = Calendar.current
        let hour = CGFloat(calendar.component(.hour, from: date))
        let minute = CGFloat(calendar.component(.minute, from: date))
        
        let elapsedHours = (hour + minute / 60.0) - 8.0
        return max(0.0, elapsedHours * 60.0)
    }
    
    private func calculateHeight(for start: Date, end: Date) -> CGFloat {
        let durationSeconds = end.timeIntervalSince(start)
        let durationHours = CGFloat(durationSeconds / 3600.0)
        return max(30.0, durationHours * 60.0)
    }
    
    private func cardColorForRole(_ role: String?) -> LinearGradient {
        let r = role?.lowercased() ?? ""
        if r.contains("cashier") {
            return APGradient.accent
        } else if r.contains("cook") || r.contains("kitchen") {
            return APGradient.warning
        } else if r.contains("manager") {
            return APGradient.destructive
        } else {
            return APGradient.positive
        }
    }
    
    // MARK: - Date Formatting Helpers
    
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
    
    // MARK: - Action Actions
    
    private func addNewShiftAt(day: Date, hour: Int) {
        APHaptic.trigger()
        editingShift = nil
        shiftEmployeeId = employees.first?.id
        
        selectedEmployeeIds = []
        if let firstEmpId = employees.first?.id {
            selectedEmployeeIds.insert(firstEmpId)
        }
        
        // Construct pre-filled dates
        let calendar = Calendar.current
        var comps = calendar.dateComponents([.year, .month, .day], from: day)
        comps.hour = hour
        comps.minute = 0
        comps.second = 0
        let start = calendar.date(from: comps) ?? Date()
        
        shiftStart = start
        shiftEnd = calendar.date(byAdding: .hour, value: 8, to: start) ?? start.addingTimeInterval(28800)
        shiftRole = "Cashier"
        shiftNotes = ""
        showingFormSheet = true
    }
    
    private func editShiftAction(_ shift: EmployeeShift) {
        APHaptic.trigger()
        editingShift = shift
        shiftEmployeeId = shift.employee?.id
        selectedEmployeeIds = []
        if let empId = shift.employee?.id {
            selectedEmployeeIds.insert(empId)
        }
        shiftStart = shift.scheduledStart
        shiftEnd = shift.scheduledEnd
        shiftRole = shift.role ?? ""
        shiftNotes = shift.notes ?? ""
        showingFormSheet = true
    }
    
    private func addShiftAction() {
        editingShift = nil
        shiftEmployeeId = employees.first?.id
        
        selectedEmployeeIds = []
        if let firstEmpId = employees.first?.id {
            selectedEmployeeIds.insert(firstEmpId)
        }
        
        shiftStart = Date()
        shiftEnd = Date().addingTimeInterval(28800)
        shiftRole = "Cashier"
        shiftNotes = ""
        showingFormSheet = true
    }
    
    private func saveShift() {
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
                if let emp = employees.first(where: { $0.id == empId }) {
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
        }
        try? modelContext.save()
        showingFormSheet = false
        editingShift = nil
    }
    
    private func deleteShift() {
        if let sh = editingShift {
            modelContext.delete(sh)
            try? modelContext.save()
        }
        showingFormSheet = false
        editingShift = nil
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
            
            // Native Share sheet trigger
            DispatchQueue.main.async {
                let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let rootVC = windowScene.windows.first?.rootViewController {
                    if let popover = activityVC.popoverPresentationController {
                        popover.sourceView = rootVC.view
                        popover.sourceRect = CGRect(x: rootVC.view.bounds.midX, y: rootVC.view.bounds.midY, width: 0, height: 0)
                        popover.permittedArrowDirections = []
                    }
                    rootVC.present(activityVC, animated: true, completion: nil)
                }
            }
        }
    }
}

// MARK: - Local translation helper extensions

fileprivate extension String {
    func localized(for language: String) -> String {
        return self.t
    }
}


// MARK: - ShiftReportView for PDF Generation

struct ShiftReportView: View {
    let weekDays: [Date]
    let allShifts: [EmployeeShift]
    let appLanguage: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
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
            
            // Loop through each day of the week
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
        .frame(width: 612) // Letter page width
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
