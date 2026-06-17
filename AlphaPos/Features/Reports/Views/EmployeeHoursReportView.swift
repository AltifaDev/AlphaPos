// EmployeeHoursReportView.swift
// AlphaPos — Reports Feature Module
//
// Per-employee hours summary: regular hours, overtime, breaks,
// pay rate, and estimated cost. Period-based aggregation.

import SwiftUI
import SwiftData
import Charts

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Employee Hours Report View
// ─────────────────────────────────────────────────────────────────────────────

struct EmployeeHoursReportView: View {
    @Bindable var viewModel: ReportsViewModel
    @EnvironmentObject private var lm: LocalizationManager

    var body: some View {
        VStack(alignment: .leading, spacing: APSpacing.lg) {
            // Summary KPIs
            laborSummaryCards

            // Hours bar chart
            hoursChart

            // Employee detail table
            employeeTable
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Summary Cards
    // ─────────────────────────────────────────────────────────────────────────

    private var laborSummaryCards: some View {
        HStack(spacing: APSpacing.md) {
            laborCard(
                title: L.Reports.totalLaborHours.t,
                value: String(format: "%.1f h", viewModel.totalLaborHours),
                icon: "clock.fill",
                color: .appAccent
            )
            laborCard(
                title: L.Reports.totalLaborCost.t,
                value: viewModel.formatCurrency(viewModel.totalLaborCost),
                icon: "banknote.fill",
                color: .appTeal
            )
            laborCard(
                title: L.Reports.totalOT.t,
                value: String(format: "%.1f h", viewModel.totalOvertimeHours),
                icon: "clock.badge.exclamationmark.fill",
                color: .orange
            )
            laborCard(
                title: L.Reports.activeStaff.t,
                value: "\(viewModel.employeeHoursEntries.count)",
                icon: "person.2.fill",
                color: .purple
            )
        }
    }

    private func laborCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(APSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appSurfaceHigh.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Hours Chart
    // ─────────────────────────────────────────────────────────────────────────

    private var hoursChart: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            Text(L.Reports.hoursPerEmployee.t)
                .font(.headline)

            if viewModel.employeeHoursEntries.isEmpty {
                Text(L.Reports.noData.t)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, APSpacing.lg)
                    .frame(maxWidth: .infinity)
            } else {
                Chart(viewModel.employeeHoursEntries.prefix(15)) { entry in
                    BarMark(
                        x: .value("Hours", entry.regularHours),
                        y: .value("Employee", entry.name)
                    )
                    .foregroundStyle(Color.appAccent.gradient)

                    BarMark(
                        x: .value("OT Hours", entry.overtimeHours),
                        y: .value("Employee", entry.name)
                    )
                    .foregroundStyle(Color.orange.gradient)
                }
                .chartXAxisLabel(L.Reports.hours.t)
                .chartForegroundStyleScale([
                    L.Reports.regularHours.t: Color.appAccent,
                    L.Reports.overtimeHours.t: Color.orange
                ])
                .frame(height: max(200, CGFloat(min(viewModel.employeeHoursEntries.count, 15)) * 32))
            }
        }
        .padding(APSpacing.md)
        .background(Color.appSurfaceHigh.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Employee Table
    // ─────────────────────────────────────────────────────────────────────────

    private var employeeTable: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            Text(L.Reports.employeeDetail.t)
                .font(.headline)

            if viewModel.employeeHoursEntries.isEmpty {
                Text(L.Reports.noData.t)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, APSpacing.lg)
                    .frame(maxWidth: .infinity)
            } else {
                // Table header
                HStack {
                    Text(L.Reports.employee.t)
                        .frame(width: 140, alignment: .leading)
                    Text(L.Reports.type.t)
                        .frame(width: 70, alignment: .center)
                    Text(L.Reports.totalHours.t)
                        .frame(width: 70, alignment: .trailing)
                    Text(L.Reports.regularHours.t)
                        .frame(width: 70, alignment: .trailing)
                    Text(L.Reports.overtimeHours.t)
                        .frame(width: 60, alignment: .trailing)
                    Text(L.Reports.breaks.t)
                        .frame(width: 60, alignment: .trailing)
                    Text(L.Reports.rate.t)
                        .frame(width: 80, alignment: .trailing)
                    Text(L.Reports.estCost.t)
                        .frame(width: 100, alignment: .trailing)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, APSpacing.sm)

                Divider()

                // Data rows
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.employeeHoursEntries) { entry in
                            employeeRow(entry)
                            Divider().opacity(0.3)
                        }
                    }
                }
                .frame(maxHeight: 400)

                Divider()

                // Totals
                HStack {
                    Text(L.Reports.total.t)
                        .font(.subheadline.weight(.bold))
                        .frame(width: 140, alignment: .leading)
                    Text("")
                        .frame(width: 70)
                    Text(String(format: "%.1f", viewModel.totalLaborHours))
                        .frame(width: 70, alignment: .trailing)
                    Text(String(format: "%.1f", totalRegularHours))
                        .frame(width: 70, alignment: .trailing)
                    Text(String(format: "%.1f", viewModel.totalOvertimeHours))
                        .frame(width: 60, alignment: .trailing)
                        .foregroundStyle(.orange)
                    Text(String(format: "%.1f", totalBreakHours))
                        .frame(width: 60, alignment: .trailing)
                    Text("")
                        .frame(width: 80)
                    Text(viewModel.formatCurrency(viewModel.totalLaborCost))
                        .frame(width: 100, alignment: .trailing)
                        .foregroundStyle(Color.appAccent)
                }
                .font(.subheadline.weight(.bold).monospacedDigit())
                .padding(.horizontal, APSpacing.sm)
                .padding(.vertical, APSpacing.sm)
                .background(Color.appSurfaceHigh.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: APRadius.sm))
            }
        }
        .padding(APSpacing.md)
        .background(Color.appSurfaceHigh.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
    }

    private func employeeRow(_ entry: EmployeeHoursEntry) -> some View {
        HStack {
            Text(entry.name)
                .font(.subheadline)
                .lineLimit(1)
                .frame(width: 140, alignment: .leading)
            Text(employmentTypeBadge(entry.employmentType))
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(employmentTypeColor(entry.employmentType).opacity(0.15))
                .foregroundStyle(employmentTypeColor(entry.employmentType))
                .clipShape(Capsule())
                .frame(width: 70, alignment: .center)
            Text(String(format: "%.1f", entry.totalHours))
                .frame(width: 70, alignment: .trailing)
            Text(String(format: "%.1f", entry.regularHours))
                .frame(width: 70, alignment: .trailing)
            Text(String(format: "%.1f", entry.overtimeHours))
                .frame(width: 60, alignment: .trailing)
                .foregroundStyle(entry.overtimeHours > 0 ? .orange : .secondary)
            Text(String(format: "%.1f", entry.breakHours))
                .frame(width: 60, alignment: .trailing)
                .foregroundStyle(.secondary)
            Text(viewModel.formatCurrency(entry.payRate))
                .frame(width: 80, alignment: .trailing)
                .foregroundStyle(.secondary)
            Text(viewModel.formatCurrency(entry.estimatedCost))
                .frame(width: 100, alignment: .trailing)
                .foregroundStyle(Color.appAccent)
        }
        .font(.subheadline.monospacedDigit())
        .padding(.horizontal, APSpacing.sm)
        .padding(.vertical, APSpacing.xs)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Helpers
    // ─────────────────────────────────────────────────────────────────────────

    private var totalRegularHours: Double {
        viewModel.employeeHoursEntries.reduce(0) { $0 + $1.regularHours }
    }

    private var totalBreakHours: Double {
        viewModel.employeeHoursEntries.reduce(0) { $0 + $1.breakHours }
    }

    private func employmentTypeBadge(_ type: String) -> String {
        switch type {
        case "hourly":  return L.Reports.hourly.t
        case "daily":   return L.Reports.daily.t
        case "monthly": return L.Reports.monthly.t
        default:        return type
        }
    }

    private func employmentTypeColor(_ type: String) -> Color {
        switch type {
        case "hourly":  return .appAccent
        case "daily":   return .orange
        case "monthly": return .purple
        default:        return .secondary
        }
    }
}
