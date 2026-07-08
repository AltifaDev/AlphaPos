// LeaveManagementView.swift
// AlphaPos — M-5: Leave Management UI

import SwiftUI
import SwiftData

// MARK: - Leave Management Main View

struct LeaveManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var lm: LocalizationManager

    @Query(sort: \Employee.firstName) private var employees: [Employee]
    @Query(
        filter: #Predicate<EmployeeLeave> { !$0.isDeleted },
        sort: \EmployeeLeave.startDate, order: .reverse
    ) private var allLeaves: [EmployeeLeave]

    @State private var selectedStatus: LeaveStatusFilter = .all
    @State private var selectedEmployee: Employee? = nil
    @State private var showingRequestSheet = false
    @State private var leaveToEdit: EmployeeLeave? = nil
    @State private var searchText = ""

    enum LeaveStatusFilter: String, CaseIterable, Identifiable {
        case all      = "all"
        case pending  = "pending"
        case approved = "approved"
        case rejected = "rejected"
        var id: String { rawValue }
        var localizedName: String {
            switch self {
            case .all:      return "leave_filter_all".t
            case .pending:  return "leave_status_pending".t
            case .approved: return "leave_status_approved".t
            case .rejected: return "leave_status_rejected".t
            }
        }
    }

    private var filteredLeaves: [EmployeeLeave] {
        var result = allLeaves
        if selectedStatus != .all {
            result = result.filter { $0.status == selectedStatus.rawValue }
        }
        if let emp = selectedEmployee {
            result = result.filter { $0.employee?.id == emp.id }
        }
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            result = result.filter {
                let name = "\($0.employee?.firstName ?? "") \($0.employee?.lastName ?? "")".lowercased()
                return name.contains(q) || ($0.reason?.lowercased().contains(q) ?? false)
            }
        }
        return result
    }

    private var pendingCount: Int { allLeaves.filter { $0.status == "pending" }.count }
    private var approvedThisMonth: Int {
        let startOfMonth = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date()))!
        return allLeaves.filter { $0.status == "approved" && $0.startDate >= startOfMonth }.count
    }
    private var totalDaysThisMonth: Double {
        let startOfMonth = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date()))!
        return allLeaves.filter { $0.status == "approved" && $0.startDate >= startOfMonth }
            .reduce(0) { $0 + $1.totalDays }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header stats
            headerStats

            Divider().background(Color.appDivider)

            // Filter bar
            filterBar

            Divider().background(Color.appDivider)

            // Leave list
            if filteredLeaves.isEmpty {
                emptyState
            } else {
                leaveList
            }
        }
        .sheet(isPresented: $showingRequestSheet) {
            LeaveRequestSheet(employees: employees) { leave in
                modelContext.insert(leave)
                modelContext.saveWithLogging(label: "LeaveManagementView.addLeave")
                Task { await SyncEngine.shared.syncAll(modelContext: modelContext) }
            }
        }
        .sheet(item: $leaveToEdit) { leave in
            LeaveEditSheet(leave: leave) {
                modelContext.saveWithLogging(label: "LeaveManagementView.editLeave")
                Task { await SyncEngine.shared.syncAll(modelContext: modelContext) }
            }
        }
    }

    // MARK: - Header Stats

    private var headerStats: some View {
        HStack(spacing: 12) {
            leaveStat(title: "leave_stat_pending".t, value: "\(pendingCount)",
                      color: .appAmber, icon: "clock.badge.exclamationmark.fill")
            leaveStat(title: "leave_stat_approved_month".t, value: "\(approvedThisMonth)",
                      color: .appTeal, icon: "checkmark.circle.fill")
            leaveStat(title: "leave_stat_days_month".t, value: String(format: "%.1f", totalDaysThisMonth),
                      color: .appAccent, icon: "calendar.badge.minus")

            Spacer()

            Button(action: { showingRequestSheet = true }) {
                Label("leave_request_btn".t, systemImage: "plus.circle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(APGradient.accent)
                    .cornerRadius(10)
            }
            .buttonStyle(.plain)
        }
        .padding(APSpacing.md)
        .background(Color.appSurface)
    }

    private func leaveStat(title: String, value: String, color: Color, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.system(size: 18))
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(.title3.bold()).foregroundColor(.textPrimary)
                Text(title).font(.caption2).foregroundColor(.textSecondary)
            }
        }
        .padding(10)
        .background(color.opacity(0.08))
        .cornerRadius(10)
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: 12) {
            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundColor(.textTertiary).font(.system(size: 13))
                TextField("leave_search_placeholder".t, text: $searchText)
                    .font(.system(size: 13))
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(Color.appSurfaceHigh).cornerRadius(8)
            .frame(maxWidth: 200)

            // Status filter
            Picker("", selection: $selectedStatus) {
                ForEach(LeaveStatusFilter.allCases) { f in
                    Text(f.localizedName).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 340)

            Spacer()

            // Employee picker
            Menu {
                Button("leave_filter_all".t) { selectedEmployee = nil }
                Divider()
                ForEach(employees.filter { !$0.isDeleted }) { emp in
                    Button("\(emp.firstName) \(emp.lastName)") { selectedEmployee = emp }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "person.fill").font(.system(size: 12))
                    Text(selectedEmployee.map { "\($0.firstName) \($0.lastName)" } ?? "leave_filter_all_staff".t)
                        .font(.system(size: 12, weight: .medium))
                    Image(systemName: "chevron.down").font(.system(size: 10))
                }
                .foregroundColor(.appAccent)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.appSurfaceHigh).cornerRadius(8)
            }
        }
        .padding(.horizontal, APSpacing.md)
        .padding(.vertical, APSpacing.sm)
        .background(Color.appSurface)
    }

    // MARK: - Leave List

    private var leaveList: some View {
        List {
            ForEach(filteredLeaves) { leave in
                leaveRow(leave)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .onTapGesture { leaveToEdit = leave }
            }
        }
        .listStyle(.plain)
        .background(Color.appBackground)
    }

    private func leaveRow(_ leave: EmployeeLeave) -> some View {
        HStack(spacing: 12) {
            // Status indicator
            RoundedRectangle(cornerRadius: 3)
                .fill(statusColor(leave.status))
                .frame(width: 4, height: 48)

            // Employee + type
            VStack(alignment: .leading, spacing: 3) {
                Text("\(leave.employee?.firstName ?? "—") \(leave.employee?.lastName ?? "")")
                    .font(.system(size: 13, weight: .bold)).foregroundColor(.textPrimary)
                HStack(spacing: 6) {
                    Text(leave.displayType)
                        .font(.caption).foregroundColor(.textSecondary)
                    if !leave.isPaidLeave {
                        Text("leave_unpaid_badge".t)
                            .font(.caption2.bold())
                            .foregroundColor(.appRose)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color.appRose.opacity(0.12)).cornerRadius(4)
                    }
                }
            }

            Spacer()

            // Date range + days
            VStack(alignment: .trailing, spacing: 3) {
                Text(leave.startDate == leave.endDate
                    ? leave.startDate.formatted(date: .abbreviated, time: .omitted)
                    : "\(leave.startDate.formatted(date: .abbreviated, time: .omitted)) – \(leave.endDate.formatted(date: .abbreviated, time: .omitted))"
                )
                .font(.caption).foregroundColor(.textSecondary)
                Text(String(format: "%.1f " + "leave_days_unit".t, leave.totalDays))
                    .font(.caption.bold()).foregroundColor(.textPrimary)
            }

            // Status badge
            Text(statusLabel(leave.status))
                .font(.caption2.bold())
                .foregroundColor(statusColor(leave.status))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(statusColor(leave.status).opacity(0.12))
                .cornerRadius(6)
        }
        .padding(10)
        .background(Color.appSurface)
        .cornerRadius(10)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 44)).foregroundColor(.textTertiary)
            Text("leave_empty_title".t)
                .font(.headline).foregroundColor(.textSecondary)
            Button(action: { showingRequestSheet = true }) {
                Label("leave_request_btn".t, systemImage: "plus")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 20).padding(.vertical, 10)
                    .background(APGradient.accent).foregroundColor(.white).cornerRadius(10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
    }

    // MARK: - Helpers

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "approved":  return .appTeal
        case "rejected":  return .appRose
        case "cancelled": return Color(.systemGray)
        default:          return .appAmber
        }
    }

    private func statusLabel(_ status: String) -> String {
        switch status {
        case "approved":  return "leave_status_approved".t
        case "rejected":  return "leave_status_rejected".t
        case "cancelled": return "leave_status_cancelled".t
        default:          return "leave_status_pending".t
        }
    }
}

// MARK: - Leave Request Sheet

struct LeaveRequestSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var lm: LocalizationManager

    let employees: [Employee]
    let onSave: (EmployeeLeave) -> Void

    @State private var selectedEmployee: Employee? = nil
    @State private var leaveType = "sick"
    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var isHalfDay = false
    @State private var reason = ""
    @State private var isPaidLeave = true

    private let leaveTypes = ["sick", "annual", "personal", "unpaid", "maternity", "paternity", "other"]

    private var totalDays: Double {
        if isHalfDay { return 0.5 }
        return EmployeeLeave.businessDays(from: startDate, to: endDate)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("leave_employee_section".t) {
                    Picker("leave_employee_lbl".t, selection: $selectedEmployee) {
                        Text("leave_select_employee".t).tag(Employee?.none)
                        ForEach(employees.filter { !$0.isDeleted }) { emp in
                            Text("\(emp.firstName) \(emp.lastName)").tag(Optional(emp))
                        }
                    }
                }

                Section("leave_details_section".t) {
                    Picker("leave_type_lbl".t, selection: $leaveType) {
                        ForEach(leaveTypes, id: \.self) { t in
                            Text("leave_type_\(t)".t).tag(t)
                        }
                    }
                    DatePicker("leave_start_date".t, selection: $startDate, displayedComponents: .date)
                    DatePicker("leave_end_date".t, selection: $endDate, in: startDate..., displayedComponents: .date)
                    Toggle("leave_half_day_toggle".t, isOn: $isHalfDay)
                    HStack {
                        Text("leave_total_days".t)
                        Spacer()
                        Text(String(format: "%.1f " + "leave_days_unit".t, totalDays))
                            .foregroundColor(.appAccent).fontWeight(.bold)
                    }
                    Toggle("leave_paid_toggle".t, isOn: $isPaidLeave)
                }

                Section("leave_reason_section".t) {
                    TextField("leave_reason_placeholder".t, text: $reason, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section {
                    Button(action: saveLeave) {
                        Text("leave_save_btn".t)
                            .frame(maxWidth: .infinity)
                            .foregroundColor(selectedEmployee == nil ? .textTertiary : .white)
                    }
                    .listRowBackground(selectedEmployee == nil ? Color.appSurfaceHigh : nil)
                    .disabled(selectedEmployee == nil)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .navigationTitle("leave_request_btn".t)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel_btn".t) { dismiss() }.foregroundColor(.textSecondary)
                }
            }
        }
        .presentationDetents([.large])
    }

    private func saveLeave() {
        guard let emp = selectedEmployee else { return }
        let leave = EmployeeLeave(
            employee: emp,
            leaveType: leaveType,
            status: "pending",
            startDate: startDate,
            endDate: isHalfDay ? startDate : endDate,
            totalDays: totalDays,
            reason: reason.isEmpty ? nil : reason,
            isPaidLeave: isPaidLeave && leaveType != "unpaid"
        )
        onSave(leave)
        dismiss()
    }
}

// MARK: - Leave Edit Sheet (Approve / Reject)

struct LeaveEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var lm: LocalizationManager
    @Bindable var leave: EmployeeLeave
    let onSave: () -> Void

    @State private var approvedByText = ""
    @State private var rejectionText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("leave_employee_section".t) {
                    Text("\(leave.employee?.firstName ?? "—") \(leave.employee?.lastName ?? "")")
                        .foregroundColor(.textPrimary)
                    Text(leave.displayType).foregroundColor(.textSecondary).font(.caption)
                }

                Section("leave_dates_section".t) {
                    HStack {
                        Text("leave_start_date".t)
                        Spacer()
                        Text(leave.startDate.formatted(date: .abbreviated, time: .omitted))
                            .foregroundColor(.textSecondary)
                    }
                    HStack {
                        Text("leave_end_date".t)
                        Spacer()
                        Text(leave.endDate.formatted(date: .abbreviated, time: .omitted))
                            .foregroundColor(.textSecondary)
                    }
                    HStack {
                        Text("leave_total_days".t)
                        Spacer()
                        Text(String(format: "%.1f " + "leave_days_unit".t, leave.totalDays))
                            .foregroundColor(.appAccent).fontWeight(.bold)
                    }
                }

                if let reason = leave.reason, !reason.isEmpty {
                    Section("leave_reason_section".t) {
                        Text(reason).foregroundColor(.textSecondary)
                    }
                }

                if leave.status == "pending" {
                    Section("leave_action_section".t) {
                        TextField("leave_approved_by_placeholder".t, text: $approvedByText)

                        HStack(spacing: 12) {
                            Button(action: approveLeave) {
                                Label("leave_approve_btn".t, systemImage: "checkmark.circle.fill")
                                    .frame(maxWidth: .infinity)
                                    .foregroundColor(.white)
                                    .padding(.vertical, 10)
                                    .background(Color.appTeal)
                                    .cornerRadius(10)
                            }
                            .buttonStyle(.plain)

                            Button(action: { rejectLeave() }) {
                                Label("leave_reject_btn".t, systemImage: "xmark.circle.fill")
                                    .frame(maxWidth: .infinity)
                                    .foregroundColor(.white)
                                    .padding(.vertical, 10)
                                    .background(Color.appRose)
                                    .cornerRadius(10)
                            }
                            .buttonStyle(.plain)
                        }
                        .listRowBackground(Color.clear)
                    }
                } else {
                    Section {
                        HStack {
                            Text("leave_status_lbl".t)
                            Spacer()
                            Text(statusLabel(leave.status))
                                .foregroundColor(statusColor(leave.status))
                                .fontWeight(.bold)
                        }
                        if let approved = leave.approvedBy {
                            HStack {
                                Text("leave_approved_by_lbl".t)
                                Spacer()
                                Text(approved).foregroundColor(.textSecondary)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .navigationTitle("leave_details_title".t)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel_btn".t) { dismiss() }.foregroundColor(.textSecondary)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func approveLeave() {
        leave.status = "approved"
        leave.approvedBy = approvedByText.isEmpty ? "Manager" : approvedByText
        leave.isSynced = false
        leave.updatedAt = Date()
        onSave()
        dismiss()
    }

    private func rejectLeave() {
        leave.status = "rejected"
        leave.rejectionReason = rejectionText.isEmpty ? nil : rejectionText
        leave.isSynced = false
        leave.updatedAt = Date()
        onSave()
        dismiss()
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "approved":  return .appTeal
        case "rejected":  return .appRose
        case "cancelled": return .secondary
        default:          return .appAmber
        }
    }

    private func statusLabel(_ status: String) -> String {
        switch status {
        case "approved":  return "leave_status_approved".t
        case "rejected":  return "leave_status_rejected".t
        case "cancelled": return "leave_status_cancelled".t
        default:          return "leave_status_pending".t
        }
    }
}
