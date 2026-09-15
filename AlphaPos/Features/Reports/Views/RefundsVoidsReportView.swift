// RefundsVoidsReportView.swift
// AlphaPos — Reports Feature Module
//
// Loss-prevention / exception report: refunds by reason, method and
// employee, plus voided tickets. Standard POS audit report used to spot
// fraud patterns and operational problems.

import SwiftUI

struct RefundsVoidsReportView: View {
    @Bindable var viewModel: ReportsViewModel
    @EnvironmentObject private var lm: LocalizationManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: APSpacing.lg) {
            kpiCardsSection
            reasonAndMethodSection
            employeeSection
            refundLogSection
            voidLogSection
        }
        .onAppear {
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.easeOut(duration: 0.45)) { appeared = true }
            }
        }
    }

    // MARK: - KPIs

    private var kpiCardsSection: some View {
        let columns = Array(
            repeating: GridItem(.flexible(minimum: 0), spacing: APSpacing.md, alignment: .top),
            count: 4
        )
        return LazyVGrid(columns: columns, spacing: APSpacing.md) {
            kpiCard(
                title: "rv_refund_total".t,
                value: viewModel.formatCurrency(viewModel.refundTotalAmount),
                subtitle: "\(viewModel.refundCount) \("rv_txn_unit".t)",
                icon: "arrow.uturn.backward.circle.fill",
                color: .pink, index: 0
            )
            kpiCard(
                title: "rv_refund_rate".t,
                value: String(format: "%.2f%%", viewModel.refundRatePct),
                subtitle: "rv_refund_rate_hint".t,
                icon: "percent",
                color: viewModel.refundRatePct > 2 ? .red : .appTeal, index: 1
            )
            kpiCard(
                title: "rv_void_total".t,
                value: viewModel.formatCurrency(viewModel.auditVoidAmount),
                subtitle: "\(viewModel.auditVoidCount) \("rv_ticket_unit".t)",
                icon: "xmark.circle.fill",
                color: .orange, index: 2
            )
            kpiCard(
                title: "rv_pending_refunds".t,
                value: "\(viewModel.pendingRefundCount)",
                subtitle: "rv_pending_hint".t,
                icon: "hourglass",
                color: viewModel.pendingRefundCount > 0 ? .orange : .appTeal, index: 3
            )
        }
    }

    private func kpiCard(title: String, value: String, subtitle: String, icon: String, color: Color, index: Int) -> some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            HStack {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color)
                Spacer(minLength: 0)
            }
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 24, alignment: .topLeading)
        }
        .padding(APSpacing.md)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .background(Color.appSurfaceHigh.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared || reduceMotion ? 0 : CGFloat(10 + index * 4))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.4).delay(Double(index) * 0.06), value: appeared)
    }

    // MARK: - By reason & method

    private var reasonAndMethodSection: some View {
        HStack(alignment: .top, spacing: APSpacing.md) {
            // By reason
            VStack(alignment: .leading, spacing: APSpacing.sm) {
                Text("rv_by_reason".t)
                    .font(.headline)
                if viewModel.refundsByReason.isEmpty {
                    emptyHint
                } else {
                    ForEach(viewModel.refundsByReason) { point in
                        breakdownRow(
                            label: reasonLabel(point.reason),
                            count: point.count,
                            amount: point.amount,
                            total: viewModel.refundTotalAmount,
                            color: .pink
                        )
                    }
                }
            }
            .padding(APSpacing.md)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Color.appSurfaceHigh.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: APRadius.md))

            // By method
            VStack(alignment: .leading, spacing: APSpacing.sm) {
                Text("rv_by_method".t)
                    .font(.headline)
                if viewModel.refundsByMethod.isEmpty {
                    emptyHint
                } else {
                    ForEach(viewModel.refundsByMethod) { point in
                        breakdownRow(
                            label: methodLabel(point.method),
                            count: point.count,
                            amount: point.amount,
                            total: viewModel.refundTotalAmount,
                            color: .indigo
                        )
                    }
                }
            }
            .padding(APSpacing.md)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Color.appSurfaceHigh.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
        }
        .opacity(appeared ? 1 : 0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.45).delay(0.15), value: appeared)
    }

    private func breakdownRow(label: String, count: Int, amount: Double, total: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Spacer()
                Text("\(count)×")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(viewModel.formatCurrency(amount))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
            }
            GeometryReader { geo in
                let ratio = total > 0 ? min(amount / total, 1.0) : 0
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.appSurfaceHigh)
                        .frame(height: 5)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color.opacity(0.7))
                        .frame(width: geo.size.width * (appeared ? ratio : 0), height: 5)
                }
            }
            .frame(height: 5)
        }
        .padding(.vertical, 4)
    }

    // MARK: - By employee

    private var employeeSection: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            Text("rv_by_employee".t)
                .font(.headline)
            Text("rv_by_employee_hint".t)
                .font(.caption)
                .foregroundStyle(.secondary)

            if viewModel.refundsByEmployee.isEmpty {
                emptyHint
            } else {
                HStack {
                    Text("rv_employee_col".t).frame(maxWidth: .infinity, alignment: .leading)
                    Text("rv_count_col".t).frame(width: 80, alignment: .trailing)
                    Text("rv_amount_col".t).frame(width: 110, alignment: .trailing)
                }
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                Divider()

                ForEach(viewModel.refundsByEmployee) { point in
                    HStack {
                        HStack(spacing: 6) {
                            Image(systemName: "person.circle.fill")
                                .foregroundStyle(Color.appAccent)
                            Text(point.employeeName)
                                .font(.subheadline.weight(.medium))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(point.count)")
                            .font(.subheadline.monospacedDigit())
                            .frame(width: 80, alignment: .trailing)
                        Text(viewModel.formatCurrency(point.amount))
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.pink)
                            .frame(width: 110, alignment: .trailing)
                    }
                    .padding(.vertical, 4)
                    Divider().opacity(0.2)
                }
            }
        }
        .padding(APSpacing.md)
        .background(Color.appSurfaceHigh.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
        .opacity(appeared ? 1 : 0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.45).delay(0.22), value: appeared)
    }

    // MARK: - Refund log

    private var refundLogSection: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            Text("rv_refund_log".t)
                .font(.headline)

            if viewModel.refundLog.isEmpty {
                emptyHint
            } else {
                ForEach(viewModel.refundLog) { entry in
                    HStack(spacing: APSpacing.sm) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.orderNumber)
                                .font(.subheadline.weight(.semibold))
                            Text(entry.reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\("rv_by_lbl".t): \(entry.refundedBy)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            if let approver = entry.approvedBy {
                                Text("\("rv_approved_lbl".t): \(approver)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        statusPill(entry.status)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(viewModel.formatCurrency(entry.amount))
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundStyle(.pink)
                            Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 6)
                    Divider().opacity(0.2)
                }
            }
        }
        .padding(APSpacing.md)
        .background(Color.appSurfaceHigh.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
        .opacity(appeared ? 1 : 0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.45).delay(0.28), value: appeared)
    }

    // MARK: - Void log

    private var voidLogSection: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            Text("rv_void_log".t)
                .font(.headline)

            if viewModel.voidLog.isEmpty {
                emptyHint
            } else {
                ForEach(viewModel.voidLog) { entry in
                    HStack {
                        Text(entry.orderNumber)
                            .font(.subheadline.weight(.semibold))
                        Text("\(entry.itemCount) เมนูหลัก")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(viewModel.formatCurrency(entry.amount))
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.orange)
                        Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .frame(width: 130, alignment: .trailing)
                    }
                    .padding(.vertical, 5)
                    Divider().opacity(0.2)
                }
            }
        }
        .padding(APSpacing.md)
        .background(Color.appSurfaceHigh.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
        .opacity(appeared ? 1 : 0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.45).delay(0.34), value: appeared)
    }

    // MARK: - Helpers

    private var emptyHint: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 22))
                .foregroundStyle(.tertiary)
            Text("rv_no_data".t)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .center)
    }

    private func statusPill(_ status: String) -> some View {
        let (label, color): (String, Color) = {
            switch status {
            case "completed":        return ("rv_status_completed".t, .appTeal)
            case "pending_approval": return ("rv_status_pending".t, .orange)
            case "rejected":         return ("rv_status_rejected".t, .red)
            default:                 return (status.capitalized, .secondary)
            }
        }()
        return Text(label)
            .font(.caption2.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private func reasonLabel(_ reason: String) -> String {
        switch reason {
        case "customer_request": return "rv_reason_customer_request".t
        case "defective":        return "rv_reason_defective".t
        case "wrong_order":      return "rv_reason_wrong_order".t
        case "overcharge":       return "rv_reason_overcharge".t
        default:                 return reason.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func methodLabel(_ method: String) -> String {
        switch method {
        case "cash":            return "rv_method_cash".t
        case "original_tender": return "rv_method_original".t
        case "store_credit":    return "rv_method_store_credit".t
        default:                return method.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}
