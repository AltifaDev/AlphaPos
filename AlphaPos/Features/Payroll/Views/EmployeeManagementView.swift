import SwiftUI

/// Unified HR workspace: staff directory, attendance, schedule, and payroll.
/// Mirrors `CustomerValueManagementView` — one sidebar entry, internal sections.
struct EmployeeManagementView: View {
    enum Section: String, CaseIterable, Identifiable {
        case staff
        case attendance
        case schedule
        case payroll

        var id: String { rawValue }

        var title: String {
            switch self {
            case .staff: return "employee_section_staff".t
            case .attendance: return "employee_section_attendance".t
            case .schedule: return "employee_section_schedule".t
            case .payroll: return "employee_section_payroll".t
            }
        }

        var icon: String {
            switch self {
            case .staff: return "person.text.rectangle"
            case .attendance: return "clock.badge.checkmark"
            case .schedule: return "calendar.badge.clock"
            case .payroll: return "banknote"
            }
        }
    }

    @Binding var columnVisibility: NavigationSplitViewVisibility
    @State private var section: Section

    private let employeeAccent = Color(hex: "0F766E")

    init(
        initialSection: Section = .staff,
        columnVisibility: Binding<NavigationSplitViewVisibility> = .constant(.all)
    ) {
        _section = State(initialValue: initialSection)
        _columnVisibility = columnVisibility
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch section {
                case .staff:
                    EmployeeDirectoryView()
                case .attendance:
                    EmployeeTimecardView(embedded: true)
                case .schedule:
                    EmployeeScheduleHubView()
                case .payroll:
                    EmployeePayrollEngineView()
                }
            }
            .id(section)
            .transition(.opacity)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("employee_mgmt_title".t)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                workspaceHeader
            }
        }
    }

    private var workspaceHeader: some View {
        HStack(spacing: 3) {
            ForEach(Section.allCases) { item in
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) { section = item }
                } label: {
                    Label(item.title, systemImage: item.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .foregroundStyle(section == item ? Color.white : Color.textSecondary)
                        .background {
                            if section == item {
                                Capsule().fill(employeeAccent)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(section == item ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Color.appSurfaceHigh, in: Capsule())
        .overlay(Capsule().stroke(Color.appBorderSubtle, lineWidth: 1))
    }
}
