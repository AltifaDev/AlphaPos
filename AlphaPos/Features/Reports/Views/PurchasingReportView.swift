// PurchasingReportView.swift
// AlphaPos — Reports Feature Module
//
// Procurement / Purchasing spend analysis: total purchase spend, spend by
// supplier, top purchased items, PO status breakdown and a recent PO log.
// Follows the standard spend-analysis structure (supplier × item × status).

import SwiftUI

struct PurchasingReportView: View {
    @Bindable var viewModel: ReportsViewModel
    @EnvironmentObject private var lm: LocalizationManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: APSpacing.lg) {
            kpiCardsSection
            supplierSpendSection
            topItemsSection
            statusBreakdownSection
            recentPOSection
        }
        .onAppear {
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.easeOut(duration: 0.45)) { appeared = true }
            }
        }
    }

    // MARK: - KPI cards

    private var kpiCardsSection: some View {
        let columns = Array(
            repeating: GridItem(.flexible(minimum: 0), spacing: APSpacing.md, alignment: .top),
            count: 4
        )
        return LazyVGrid(columns: columns, spacing: APSpacing.md) {
            kpiCard(
                title: "purchasing_total_spend".t,
                value: viewModel.formatCurrency(viewModel.purchaseTotalSpend),
                icon: "cart.fill",
                color: .appAccent,
                index: 0
            )
            kpiCard(
                title: "purchasing_received_spend".t,
                value: viewModel.formatCurrency(viewModel.purchaseReceivedSpend),
                icon: "checkmark.seal.fill",
                color: .appTeal,
                index: 1
            )
            kpiCard(
                title: "purchasing_outstanding_spend".t,
                value: viewModel.formatCurrency(viewModel.purchaseOutstandingSpend),
                icon: "clock.badge.exclamationmark",
                color: .orange,
                index: 2
            )
            kpiCard(
                title: "purchasing_po_count".t,
                value: "\(viewModel.purchaseOrderCount) · Ø \(viewModel.formatCurrency(viewModel.purchaseAvgPOValue))",
                icon: "doc.on.doc.fill",
                color: .indigo,
                index: 3
            )
        }
    }

    private func kpiCard(title: String, value: String, icon: String, color: Color, index: Int) -> some View {
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
                .minimumScaleFactor(0.55)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .topLeading)
        }
        .padding(APSpacing.md)
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
        .background(Color.appSurfaceHigh.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared || reduceMotion ? 0 : CGFloat(10 + index * 4))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.4).delay(Double(index) * 0.06), value: appeared)
    }

    // MARK: - Spend by supplier

    private var supplierSpendSection: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            Text("purchasing_by_supplier".t)
                .font(.headline)

            if viewModel.supplierSpendBreakdown.isEmpty {
                emptyState
            } else {
                let maxSpend = max(viewModel.supplierSpendBreakdown.prefix(8).map(\.totalSpend).max() ?? 0, 1)

                VStack(spacing: 8) {
                    ForEach(viewModel.supplierSpendBreakdown.prefix(8)) { point in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(point.supplierName)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                Spacer()
                                Text(viewModel.formatCurrency(point.totalSpend))
                                    .font(.caption.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }

                            GeometryReader { geo in
                                let width = max(CGFloat(max(point.totalSpend, 0) / maxSpend) * geo.size.width, 4)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(
                                        LinearGradient(colors: [Color.appAccent, Color.appAccent.opacity(0.65)],
                                                       startPoint: .leading, endPoint: .trailing)
                                    )
                                    .frame(width: width, height: 8)
                            }
                            .frame(height: 8)
                        }
                    }
                }
                .padding(.vertical, 4)

                Divider().opacity(0.35)

                // Detail table
                supplierTableHeader
                ForEach(viewModel.supplierSpendBreakdown) { supplier in
                    HStack {
                        Text(supplier.supplierName)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(supplier.poCount)")
                            .font(.subheadline.monospacedDigit())
                            .frame(width: 46, alignment: .trailing)
                        Text(viewModel.formatCurrency(supplier.totalSpend))
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .frame(width: 104, alignment: .trailing)
                        Text(viewModel.formatCurrency(supplier.outstandingSpend))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(supplier.outstandingSpend > 0 ? Color.orange : Color.secondary)
                            .frame(width: 104, alignment: .trailing)
                        Text(String(format: "%.1f%%", supplier.sharePct))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 56, alignment: .trailing)
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
        .animation(reduceMotion ? nil : .easeOut(duration: 0.45).delay(0.15), value: appeared)
    }

    private var supplierTableHeader: some View {
        HStack {
            Text("purchasing_supplier_col".t).frame(maxWidth: .infinity, alignment: .leading)
            Text("PO").frame(width: 46, alignment: .trailing)
            Text("purchasing_spend_col".t).frame(width: 104, alignment: .trailing)
            Text("purchasing_outstanding_col".t).frame(width: 104, alignment: .trailing)
            Text("%").frame(width: 56, alignment: .trailing)
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(.secondary)
    }

    // MARK: - Top purchased items

    private var topItemsSection: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            Text("purchasing_top_items".t)
                .font(.headline)

            if viewModel.topPurchasedItems.isEmpty {
                emptyState
            } else {
                HStack {
                    Text("purchasing_item_col".t).frame(maxWidth: .infinity, alignment: .leading)
                    Text("purchasing_qty_col".t).frame(width: 110, alignment: .trailing)
                    Text("purchasing_avg_cost_col".t).frame(width: 96, alignment: .trailing)
                    Text("purchasing_cost_col".t).frame(width: 104, alignment: .trailing)
                }
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)

                ForEach(viewModel.topPurchasedItems.prefix(12)) { item in
                    HStack {
                        Text(item.itemName)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(qty(item.quantityOrdered)) \(item.unit)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 110, alignment: .trailing)
                        Text(viewModel.formatCurrency(item.avgUnitCost))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 96, alignment: .trailing)
                        Text(viewModel.formatCurrency(item.totalCost))
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .frame(width: 104, alignment: .trailing)
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
        .animation(reduceMotion ? nil : .easeOut(duration: 0.45).delay(0.22), value: appeared)
    }

    // MARK: - PO status breakdown

    private var statusBreakdownSection: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            Text("purchasing_status_breakdown".t)
                .font(.headline)

            if viewModel.poStatusBreakdown.isEmpty {
                emptyState
            } else {
                HStack(spacing: APSpacing.md) {
                    ForEach(viewModel.poStatusBreakdown) { point in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(statusColor(point.status))
                                    .frame(width: 8, height: 8)
                                Text(statusLabel(point.status))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(statusColor(point.status))
                            }
                            Text(viewModel.formatCurrency(point.value))
                                .font(.subheadline.weight(.bold).monospacedDigit())
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text("\(point.count) PO")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(statusColor(point.status).opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: APRadius.sm))
                    }
                }

                Text("purchasing_input_vat_note".t + ": " + viewModel.formatCurrency(viewModel.purchaseInputVAT))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(APSpacing.md)
        .background(Color.appSurfaceHigh.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
        .opacity(appeared ? 1 : 0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.45).delay(0.28), value: appeared)
    }

    // MARK: - Recent PO log

    private var recentPOSection: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            Text("purchasing_recent_pos".t)
                .font(.headline)

            if viewModel.recentPurchaseOrders.isEmpty {
                emptyState
            } else {
                ForEach(viewModel.recentPurchaseOrders) { po in
                    HStack(spacing: APSpacing.sm) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(po.poNumber)
                                .font(.subheadline.weight(.semibold))
                            Text(po.supplierName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(statusLabel(po.status))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(statusColor(po.status))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(statusColor(po.status).opacity(0.12))
                            .clipShape(Capsule())
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(viewModel.formatCurrency(po.value))
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                            Text(po.orderDate.formatted(date: .abbreviated, time: .omitted))
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
        .animation(reduceMotion ? nil : .easeOut(duration: 0.45).delay(0.34), value: appeared)
    }

    // MARK: - Helpers

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "shippingbox")
                .font(.system(size: 22))
                .foregroundStyle(.tertiary)
            Text("purchasing_no_data".t)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
    }

    private func statusLabel(_ status: String) -> String {
        switch status {
        case "draft":     return "po_status_draft".t
        case "sent":      return "po_status_sent".t
        case "received":  return "po_status_received".t
        case "cancelled": return "po_status_cancelled".t
        default:          return status.capitalized
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "draft":     return .secondary
        case "sent":      return .orange
        case "received":  return .appTeal
        case "cancelled": return .red
        default:          return .appAccent
        }
    }

    private func qty(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value)
            : String(format: "%.2f", value)
    }
}
