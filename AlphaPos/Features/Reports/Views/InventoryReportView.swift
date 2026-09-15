// InventoryReportView.swift
// AlphaPos — Reports Feature Module
//
// Inventory status report: low stock alerts, out-of-stock items,
// total stock value summary, and recent waste/spoilage transactions.

import SwiftUI
import SwiftData

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Inventory Report View
// ─────────────────────────────────────────────────────────────────────────────

struct InventoryReportView: View {
    @Bindable var viewModel: ReportsViewModel
    @EnvironmentObject private var lm: LocalizationManager

    var body: some View {
        VStack(alignment: .leading, spacing: APSpacing.lg) {
            // Summary KPIs
            inventorySummaryCards
            usageKPICards

            // Usage vs waste analysis (planning view)
            usageTrendSection
            itemUsageSection
            stockCoverageSection
            movementBreakdownSection
            if !viewModel.wasteReasonBreakdown.isEmpty {
                wasteReasonSection
            }

            // Out-of-Stock Items
            if !viewModel.outOfStockItems.isEmpty {
                outOfStockSection
            }

            // Low Stock Items
            lowStockSection

            // Waste / Spoilage
            wasteSection
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Summary Cards
    // ─────────────────────────────────────────────────────────────────────────

    private var inventorySummaryCards: some View {
        HStack(spacing: APSpacing.md) {
            inventoryCard(
                title: L.Reports.totalStockValue.t,
                value: viewModel.formatCurrency(viewModel.totalStockValue),
                icon: "archivebox.fill",
                color: .appAccent
            )
            inventoryCard(
                title: L.Reports.lowStockCount.t,
                value: "\(viewModel.lowStockItems.count)",
                icon: "exclamationmark.triangle.fill",
                color: .orange
            )
            inventoryCard(
                title: L.Reports.outOfStockCount.t,
                value: "\(viewModel.outOfStockItems.count)",
                icon: "xmark.circle.fill",
                color: .red
            )
            inventoryCard(
                title: L.Reports.wasteCost.t,
                value: viewModel.formatCurrency(viewModel.totalWasteCost),
                icon: "trash.fill",
                color: .pink
            )
        }
    }

    /// Second KPI row — period flow metrics that drive planning:
    /// what came in, what was consumed, and how much of the outflow was waste.
    private var usageKPICards: some View {
        HStack(spacing: APSpacing.md) {
            inventoryCard(
                title: "inv_usage_cost".t,
                value: viewModel.formatCurrency(viewModel.inventoryUsageCost),
                icon: "flame.fill",
                color: .appTeal
            )
            inventoryCard(
                title: "inv_received_cost".t,
                value: viewModel.formatCurrency(viewModel.inventoryReceivedCost),
                icon: "tray.and.arrow.down.fill",
                color: .indigo
            )
            inventoryCard(
                title: "inv_waste_pct".t,
                value: String(format: "%.1f%%", viewModel.inventoryWastePct),
                icon: "chart.pie.fill",
                color: viewModel.inventoryWastePct > 5 ? .red : .appTeal
            )
            inventoryCard(
                title: "inv_net_consumption".t,
                value: viewModel.formatCurrency(viewModel.inventoryUsageCost + viewModel.totalWasteCost),
                icon: "arrow.down.right.circle.fill",
                color: .orange
            )
        }
    }

    private func inventoryCard(title: String, value: String, icon: String, color: Color) -> some View {
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
        .background(translucent(.appSurfaceHigh, 0.5))
        .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Usage vs Waste Trend
    // ─────────────────────────────────────────────────────────────────────────

    private var usageTrendSection: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            Text("inv_usage_trend".t)
                .font(.headline)

            if viewModel.dailyUsageTrend.isEmpty {
                emptyHint("inv_no_movements".t)
            } else {
                let maxCost = max(viewModel.dailyUsageTrend.map { max($0.usageCost, $0.wasteCost) }.max() ?? 0, 1)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .bottom, spacing: 8) {
                        ForEach(viewModel.dailyUsageTrend) { point in
                            VStack(spacing: 4) {
                                HStack(alignment: .bottom, spacing: 2) {
                                    let usedRatio = CGFloat(max(point.usageCost, 0) / maxCost)
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.appTeal)
                                        .frame(width: 12, height: max(usedRatio * 100, 2))

                                    let wasteRatio = CGFloat(max(point.wasteCost, 0) / maxCost)
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.pink)
                                        .frame(width: 12, height: max(wasteRatio * 100, 2))
                                }

                                Text(formatDayMonth(point.date))
                                    .font(.system(size: 8))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                .frame(height: 140)

                HStack(spacing: APSpacing.md) {
                    HStack(spacing: 4) {
                        Circle().fill(Color.appTeal).frame(width: 8, height: 8)
                        Text("inv_used_legend".t).font(.caption2).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 4) {
                        Circle().fill(Color.pink).frame(width: 8, height: 8)
                        Text("inv_waste_legend".t).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(APSpacing.md)
        .background(translucent(.appSurfaceHigh, 0.3))
        .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
    }

    private func formatDayMonth(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "dd/MM"
        return fmt.string(from: date)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Per-item Usage vs Waste
    // ─────────────────────────────────────────────────────────────────────────

    private var itemUsageSection: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            Text("inv_item_usage".t)
                .font(.headline)

            if viewModel.itemUsageBreakdown.isEmpty {
                emptyHint("inv_no_movements".t)
            } else {
                HStack {
                    Text(L.Reports.itemName.t).frame(maxWidth: .infinity, alignment: .leading)
                    Text("inv_used_col".t).frame(width: 110, alignment: .trailing)
                    Text("inv_used_cost_col".t).frame(width: 96, alignment: .trailing)
                    Text("inv_waste_col".t).frame(width: 96, alignment: .trailing)
                    Text("inv_waste_pct_col".t).frame(width: 72, alignment: .trailing)
                }
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                Divider()

                ForEach(viewModel.itemUsageBreakdown.prefix(15)) { item in
                    HStack {
                        Text(item.itemName)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(formatQty(item.usedQty)) \(item.unit)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 110, alignment: .trailing)
                        Text(viewModel.formatCurrency(item.usedCost))
                            .font(.subheadline.monospacedDigit())
                            .frame(width: 96, alignment: .trailing)
                        Text(viewModel.formatCurrency(item.wasteCost))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(item.wasteCost > 0 ? Color.pink : Color.secondary)
                            .frame(width: 96, alignment: .trailing)
                        Text(String(format: "%.1f%%", item.wastePct))
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(item.wastePct > 10 ? Color.red : (item.wastePct > 5 ? Color.orange : Color.secondary))
                            .frame(width: 72, alignment: .trailing)
                    }
                    .padding(.vertical, 4)
                    Divider().opacity(0.2)
                }
            }
        }
        .padding(APSpacing.md)
        .background(translucent(.appSurfaceHigh, 0.3))
        .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Stock Coverage (planning)
    // ─────────────────────────────────────────────────────────────────────────

    private var stockCoverageSection: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            Text("inv_stock_coverage".t)
                .font(.headline)
            Text("inv_stock_coverage_desc".t)
                .font(.caption)
                .foregroundStyle(.secondary)

            if viewModel.stockCoverage.isEmpty {
                emptyHint("inv_no_movements".t)
            } else {
                HStack {
                    Text(L.Reports.itemName.t).frame(maxWidth: .infinity, alignment: .leading)
                    Text("inv_current_col".t).frame(width: 100, alignment: .trailing)
                    Text("inv_avg_daily_col".t).frame(width: 110, alignment: .trailing)
                    Text("inv_days_left_col".t).frame(width: 100, alignment: .trailing)
                }
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                Divider()

                ForEach(viewModel.stockCoverage.prefix(15)) { item in
                    HStack {
                        Text(item.itemName)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(formatQty(item.currentQty)) \(item.unit)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 100, alignment: .trailing)
                        Text("\(formatQty(item.avgDailyUsage)) \(item.unit)/\("inv_day_unit".t)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 110, alignment: .trailing)
                        Text(coverageLabel(item.daysRemaining))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(coverageColor(item.daysRemaining))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(coverageColor(item.daysRemaining).opacity(0.12))
                            .clipShape(Capsule())
                            .frame(width: 100, alignment: .trailing)
                    }
                    .padding(.vertical, 4)
                    Divider().opacity(0.2)
                }
            }
        }
        .padding(APSpacing.md)
        .background(translucent(.appSurfaceHigh, 0.3))
        .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Movement Type Breakdown
    // ─────────────────────────────────────────────────────────────────────────

    private var movementBreakdownSection: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            Text("inv_movement_breakdown".t)
                .font(.headline)

            if viewModel.movementTypeBreakdown.isEmpty {
                emptyHint("inv_no_movements".t)
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: APSpacing.sm), count: 4),
                    spacing: APSpacing.sm
                ) {
                    ForEach(viewModel.movementTypeBreakdown) { point in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(movementColor(point.type))
                                    .frame(width: 8, height: 8)
                                Text(movementLabel(point.type))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(movementColor(point.type))
                                    .lineLimit(1)
                            }
                            Text(viewModel.formatCurrency(point.value))
                                .font(.subheadline.weight(.bold).monospacedDigit())
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text("\(point.count) \("inv_txn_unit".t)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(movementColor(point.type).opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: APRadius.sm))
                    }
                }
            }
        }
        .padding(APSpacing.md)
        .background(translucent(.appSurfaceHigh, 0.3))
        .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Waste by Reason
    // ─────────────────────────────────────────────────────────────────────────

    private var wasteReasonSection: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            Text("inv_waste_by_reason".t)
                .font(.headline)

            ForEach(viewModel.wasteReasonBreakdown.prefix(8)) { reason in
                HStack {
                    Text(reason.reason == "unspecified" ? "inv_reason_unspecified".t : reason.reason)
                        .font(.subheadline)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(reason.count) \("inv_txn_unit".t)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .trailing)
                    Text(viewModel.formatCurrency(reason.cost))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.pink)
                        .frame(width: 104, alignment: .trailing)
                }
                .padding(.vertical, 4)
                Divider().opacity(0.2)
            }
        }
        .padding(APSpacing.md)
        .background(translucent(.pink, 0.05))
        .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Out of Stock Section
    // ─────────────────────────────────────────────────────────────────────────

    private var outOfStockSection: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            Label(L.Reports.outOfStock.t, systemImage: "xmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.red)

            ForEach(viewModel.outOfStockItems) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(.subheadline.weight(.medium))
                        Text("\(L.Reports.reorderLevel.t): \(formatQty(item.reorderLevel)) \(item.unit)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(L.Reports.outOfStockBadge.t)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, APSpacing.sm)
                        .padding(.vertical, 4)
                        .background(Color.red)
                        .clipShape(Capsule())
                }
                .padding(.vertical, APSpacing.xs)
            }
        }
        .padding(APSpacing.md)
        .background(translucent(.red, 0.05))
        .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Low Stock Section
    // ─────────────────────────────────────────────────────────────────────────

    private var lowStockSection: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            Label(L.Reports.lowStock.t, systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)

            if viewModel.lowStockItems.isEmpty {
                Text(L.Reports.noLowStock.t)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, APSpacing.md)
            } else {
                // Stock level visualization
                ForEach(viewModel.lowStockItems) { item in
                    HStack(spacing: APSpacing.md) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                                .font(.subheadline.weight(.medium))
                            Text("\(formatQty(item.currentQty)) / \(formatQty(item.reorderLevel)) \(item.unit)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 200, alignment: .leading)

                        // Progress bar
                        GeometryReader { geo in
                            let ratio = item.reorderLevel > 0 ? min(item.currentQty / item.reorderLevel, 1.0) : 0
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.appSurfaceHigh)
                                    .frame(height: 8)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(stockLevelColor(ratio))
                                    .frame(width: geo.size.width * ratio, height: 8)
                            }
                        }
                        .frame(height: 8)

                        Text(viewModel.formatCurrency(item.currentQty * item.costPrice))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 80, alignment: .trailing)
                    }
                    .padding(.vertical, APSpacing.xs)
                }
            }
        }
        .padding(APSpacing.md)
        .background(translucent(.orange, 0.05))
        .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Waste Section
    // ─────────────────────────────────────────────────────────────────────────

    private var wasteSection: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            HStack {
                Label(L.Reports.wasteAndSpoilage.t, systemImage: "trash.fill")
                    .font(.headline)
                Spacer()
                Text(L.Reports.totalWaste.t + ": " + viewModel.formatCurrency(viewModel.totalWasteCost))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.pink)
            }

            if viewModel.wasteEntries.isEmpty {
                Text(L.Reports.noWaste.t)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, APSpacing.md)
            } else {
                // Table header
                HStack {
                    Text(L.Reports.date.t).frame(width: 80, alignment: .leading)
                    Text(L.Reports.itemName.t).frame(maxWidth: .infinity, alignment: .leading)
                    Text(L.Reports.quantity.t).frame(width: 80, alignment: .trailing)
                    Text(L.Reports.cost.t).frame(width: 100, alignment: .trailing)
                    Text(L.Reports.notes.t).frame(width: 120, alignment: .leading)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

                Divider()

                ForEach(viewModel.wasteEntries.prefix(20)) { entry in
                    HStack {
                        Text(formatDateShort(entry.date))
                            .frame(width: 80, alignment: .leading)
                        Text(entry.itemName)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(1)
                        Text("\(formatQty(entry.quantity)) \(entry.unit)")
                            .frame(width: 80, alignment: .trailing)
                        Text(viewModel.formatCurrency(entry.cost))
                            .foregroundStyle(.pink)
                            .frame(width: 100, alignment: .trailing)
                        Text(entry.notes ?? "—")
                            .frame(width: 120, alignment: .leading)
                            .lineLimit(1)
                    }
                    .font(.subheadline.monospacedDigit())
                    .padding(.vertical, APSpacing.xs)
                }
            }
        }
        .padding(APSpacing.md)
        .background(translucent(.appSurfaceHigh, 0.3))
        .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Helpers
    // ─────────────────────────────────────────────────────────────────────────

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .center)
    }

    private func coverageLabel(_ days: Double) -> String {
        if days >= 90 { return "90+ \("inv_day_unit".t)" }
        return String(format: "%.1f \("inv_day_unit".t)", days)
    }

    private func coverageColor(_ days: Double) -> Color {
        if days < 3 { return .red }
        if days < 7 { return .orange }
        return .appTeal
    }

    private func movementLabel(_ type: String) -> String {
        switch type {
        case "receive":            return "inv_move_receive".t
        case "sell":               return "inv_move_sell".t
        case "waste":              return "inv_move_waste".t
        case "adjust":             return "inv_move_adjust".t
        case "refund_return":      return "inv_move_refund_return".t
        case "return_to_supplier": return "inv_move_return_to_supplier".t
        case "transfer_out":       return "inv_move_transfer_out".t
        case "transfer_in":        return "inv_move_transfer_in".t
        case "opening":            return "inv_move_opening".t
        default:                   return type.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func movementColor(_ type: String) -> Color {
        switch type {
        case "receive", "transfer_in", "opening", "refund_return": return .appTeal
        case "sell":                                               return .appAccent
        case "waste":                                              return .pink
        case "return_to_supplier", "transfer_out":                 return .orange
        default:                                                   return .secondary
        }
    }

    private func stockLevelColor(_ ratio: Double) -> Color {
        if ratio <= 0.25 { return .red }
        if ratio <= 0.5 { return .orange }
        return .yellow
    }

    private func formatQty(_ value: Double) -> String {
        if value == value.rounded() {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }

    private func formatDateShort(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "dd/MM"
        return fmt.string(from: date)
    }

    private func translucent(_ color: Color, _ opacity: Double) -> Color {
        color.opacity(opacity)
    }
}
