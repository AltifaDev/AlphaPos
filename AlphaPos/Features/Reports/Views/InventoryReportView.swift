// InventoryReportView.swift
// AlphaPos — Reports Feature Module
//
// Inventory status report: low stock alerts, out-of-stock items,
// total stock value summary, and recent waste/spoilage transactions.

import SwiftUI
import SwiftData
import Charts

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
