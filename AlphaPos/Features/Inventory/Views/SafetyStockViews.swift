// SafetyStockViews.swift
// AlphaPos — Safety Stock & Lead Time UI Components
//
// Drop-in SwiftUI components for the Inventory module.
// ─────────────────────────────────────────────────────────────────────────────
// Includes:
//   • StockStatusBadge           — compact pill for list rows
//   • SafetyStockFields          — 3-field input card for Add/Edit sheets
//   • ReorderSuggestionDashboard — dashboard section with actionable list
//   • ReorderSuggestionRow       — single suggestion row
//   • StockLevelBar              — visual stock bar (safety / reorder / max zones)
//   • SafetyStockInfoCard        — detail card with all metrics for one item
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI
import SwiftData

// MARK: - StockStatusBadge

struct StockStatusBadge: View {
    let status: StockStatus

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: status.systemImage)
                .font(.caption2)
            Text(status.displayName)
                .font(.caption2).fontWeight(.semibold)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(badgeColor.opacity(0.15))
        .foregroundColor(badgeColor)
        .clipShape(Capsule())
    }

    private var badgeColor: Color {
        switch status {
        case .outOfStock, .lowStock: return Color("appRose",   bundle: nil)
        case .atReorderPoint:        return Color("appYellow", bundle: nil)
        case .belowSafety:           return .orange
        case .overstock:             return Color("appIndigo", bundle: nil)
        case .adequate:              return Color("appTeal",   bundle: nil)
        }
    }
}

// MARK: - StockLevelBar

/// Visual bar showing current stock relative to Safety / Reorder / Max zones.
struct StockLevelBar: View {
    let current: Double
    let safetyLevel: Double
    let reorderLevel: Double
    let maxLevel: Double       // 0 = not configured

    private var effectiveMax: Double {
        maxLevel > 0 ? maxLevel : max(reorderLevel * 3, current * 1.5)
    }

    private var fillFraction: Double {
        guard effectiveMax > 0 else { return 0 }
        return min(current / effectiveMax, 1.0)
    }

    private var barColor: Color {
        if current <= 0             { return Color("appRose",   bundle: nil) }
        if current <= reorderLevel  { return Color("appYellow", bundle: nil) }
        if safetyLevel > 0,
           current <= safetyLevel   { return .orange }
        if maxLevel > 0,
           current > maxLevel       { return Color("appIndigo", bundle: nil) }
        return Color("appTeal",     bundle: nil)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color("appDivider", bundle: nil))
                    .frame(height: 6)

                // Zone markers
                if effectiveMax > 0 {
                    // Safety stock zone marker
                    if safetyLevel > 0 {
                        markerLine(at: safetyLevel / effectiveMax, width: geo.size.width, color: .orange)
                    }
                    // Reorder point zone marker
                    markerLine(at: reorderLevel / effectiveMax, width: geo.size.width, color: Color("appYellow", bundle: nil))
                }

                // Fill bar
                RoundedRectangle(cornerRadius: 4)
                    .fill(barColor)
                    .frame(width: geo.size.width * fillFraction, height: 6)
                    .animation(.spring(response: 0.5), value: fillFraction)
            }
        }
        .frame(height: 6)
    }

    private func markerLine(at fraction: Double, width: CGFloat, color: Color) -> some View {
        let x = CGFloat(min(max(fraction, 0), 1)) * width
        return Rectangle()
            .fill(color.opacity(0.7))
            .frame(width: 1.5, height: 10)
            .offset(x: x - 0.75, y: -2)
    }
}

// MARK: - SafetyStockFields

/// 3-field input card: Safety Stock / Max Stock / Lead Time.
/// Add this to AddStockItemView and EditStockItemView.
struct SafetyStockFields: View {
    @Binding var safetyStockString: String
    @Binding var maxStockString: String
    @Binding var leadTimeDaysString: String

    /// Optional: show auto-calculated ROP hint below fields.
    var avgDailyUsage: Double? = nil
    var unit: String = ""

    private var ropHint: String? {
        guard let avg = avgDailyUsage, avg > 0,
              let ss = Double(safetyStockString),
              let lt = Int(leadTimeDaysString) else { return nil }
        let rop = ss + (avg * Double(lt))
        return String(format: "Reorder Point = %.1f %@", rop, unit)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Safety Stock
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "shield.fill").font(.caption).foregroundColor(.orange)
                    Text("safety_stock_label".t)
                        .font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Text("สต็อกกันชน").font(.caption2).foregroundColor(.secondary)
                }
                HStack {
                    TextField("0.0", text: $safetyStockString)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                    if !unit.isEmpty {
                        Text(unit).font(.caption).foregroundColor(.secondary).frame(width: 40)
                    }
                }
            }

            Divider()

            // Max Stock Level
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.circle").font(.caption).foregroundColor(Color("appIndigo", bundle: nil))
                    Text("max_stock_label".t)
                        .font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Text("ป้องกันสั่งเกิน").font(.caption2).foregroundColor(.secondary)
                }
                HStack {
                    TextField("0 = ไม่จำกัด", text: $maxStockString)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                    if !unit.isEmpty {
                        Text(unit).font(.caption).foregroundColor(.secondary).frame(width: 40)
                    }
                }
            }

            Divider()

            // Lead Time
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "clock.arrow.circlepath").font(.caption).foregroundColor(.blue)
                    Text("lead_time_days_label".t)
                        .font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Text("เวลาจัดส่งจาก Supplier").font(.caption2).foregroundColor(.secondary)
                }
                HStack {
                    TextField("1", text: $leadTimeDaysString)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                    Text("วัน").font(.caption).foregroundColor(.secondary).frame(width: 40)
                }
            }

            // Reorder Point hint (live computed)
            if let hint = ropHint {
                HStack(spacing: 6) {
                    Image(systemName: "cart.badge.plus").font(.caption2)
                    Text(hint).font(.caption2)
                }
                .foregroundColor(Color("appTeal", bundle: nil))
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(Color("appTeal", bundle: nil).opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

// MARK: - ReorderSuggestionDashboard

/// Top-level dashboard section showing items that need reordering.
/// Embed in InventoryView alongside ExpiryAlertDashboard.
struct ReorderSuggestionDashboard: View {
    let safetyStockManager: SafetyStockManager
    let activeBranch: Branch?

    @State private var suggestions: [ReorderSuggestion] = []
    @State private var showingFullList = false

    private var criticalCount: Int { suggestions.filter { $0.status == .outOfStock || $0.status == .atReorderPoint }.count }

    var body: some View {
        if suggestions.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    Label("แนะนำการสั่งซื้อ", systemImage: "cart.badge.plus")
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(.primary)
                    Spacer()
                    Button("ดูทั้งหมด (\(suggestions.count))") { showingFullList = true }
                        .font(.caption).foregroundColor(Color("appTeal", bundle: nil))
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)

                // Summary chips
                HStack(spacing: 8) {
                    ForEach(summaryGroups, id: \.status) { group in
                        summaryChip(count: group.count, status: group.status)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)

                // Top-3 urgent rows
                VStack(spacing: 0) {
                    ForEach(suggestions.prefix(3)) { s in
                        ReorderSuggestionRow(suggestion: s)
                        if s.id != suggestions.prefix(3).last?.id {
                            Divider().padding(.leading, 14)
                        }
                    }
                }
            }
            .background(Color("appSurface", bundle: nil))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color("appDivider", bundle: nil), lineWidth: 0.5)
            )
            .padding(.horizontal, 14)
            .padding(.bottom, 6)
            .onAppear { loadSuggestions() }
            .onChange(of: activeBranch) { _, _ in loadSuggestions() }
            .sheet(isPresented: $showingFullList) {
                ReorderSuggestionListSheet(
                    suggestions: suggestions,
                    safetyStockManager: safetyStockManager
                )
            }
        }
    }

    private var summaryGroups: [(status: StockStatus, count: Int)] {
        let order: [StockStatus] = [.outOfStock, .atReorderPoint, .belowSafety, .lowStock, .overstock]
        return order.compactMap { status in
            let c = suggestions.filter { $0.status == status }.count
            return c > 0 ? (status: status, count: c) : nil
        }
    }

    private func loadSuggestions() {
        suggestions = safetyStockManager.generateSuggestions(branch: activeBranch)
    }

    private func summaryChip(count: Int, status: StockStatus) -> some View {
        HStack(spacing: 4) {
            Image(systemName: status.systemImage).font(.caption2)
            Text("\(count)").font(.caption2).fontWeight(.semibold)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(chipColor(status).opacity(0.15))
        .foregroundColor(chipColor(status))
        .clipShape(Capsule())
    }

    private func chipColor(_ status: StockStatus) -> Color {
        switch status {
        case .outOfStock, .lowStock: return Color("appRose",   bundle: nil)
        case .atReorderPoint:        return Color("appYellow", bundle: nil)
        case .belowSafety:           return .orange
        case .overstock:             return Color("appIndigo", bundle: nil)
        case .adequate:              return Color("appTeal",   bundle: nil)
        }
    }
}

// MARK: - ReorderSuggestionRow

struct ReorderSuggestionRow: View {
    let suggestion: ReorderSuggestion

    var body: some View {
        HStack(spacing: 10) {
            // Urgency dot
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.item.name)
                    .font(.subheadline).fontWeight(.medium)
                    .foregroundColor(.primary)

                HStack(spacing: 6) {
                    // Days of stock
                    if let days = suggestion.daysOfStockRemaining {
                        let dayInt = Int(days)
                        Text(dayInt <= 0 ? "หมดแล้ว" : "เหลือ ~\(dayInt) วัน")
                            .font(.caption2)
                            .foregroundColor(dayInt <= suggestion.leadTimeDays ? Color("appRose", bundle: nil) : .secondary)
                    } else {
                        Text("ไม่ทราบการใช้เฉลี่ย")
                            .font(.caption2).foregroundColor(.secondary)
                    }

                    if let supplier = suggestion.supplierName {
                        Text("• \(supplier)")
                            .font(.caption2).foregroundColor(.secondary)
                    }

                    if suggestion.leadTimeDays > 1 {
                        Text("• Lead \(suggestion.leadTimeDays)d")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                StockStatusBadge(status: suggestion.status)
                Text(String(format: "สั่ง %.1f %@", suggestion.suggestedOrderQty, suggestion.item.unit))
                    .font(.caption2).foregroundColor(Color("appTeal", bundle: nil))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private var dotColor: Color {
        switch suggestion.status {
        case .outOfStock, .lowStock: return Color("appRose",   bundle: nil)
        case .atReorderPoint:        return Color("appYellow", bundle: nil)
        case .belowSafety:           return .orange
        case .overstock:             return Color("appIndigo", bundle: nil)
        case .adequate:              return Color("appTeal",   bundle: nil)
        }
    }
}

// MARK: - StockLevelInfoCard

/// Detailed metrics card — embed in EditStockItemView / item detail.
struct StockLevelInfoCard: View {
    let item: InventoryItem
    let safetyStockManager: SafetyStockManager

    @State private var metrics: StockMetrics? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Stock Health", systemImage: "waveform.path.ecg")
                    .font(.subheadline).fontWeight(.semibold)
                Spacer()
                if let m = metrics {
                    StockStatusBadge(status: m.status)
                }
            }

            if let m = metrics {
                // Visual bar
                VStack(alignment: .leading, spacing: 4) {
                    StockLevelBar(
                        current: item.currentQuantity,
                        safetyLevel: item.safetyStockLevel,
                        reorderLevel: item.reorderLevel,
                        maxLevel: item.maxStockLevel
                    )
                    // Zone legend
                    HStack(spacing: 12) {
                        legendDot(color: Color("appYellow", bundle: nil), label: "Reorder")
                        if item.safetyStockLevel > 0 {
                            legendDot(color: .orange, label: "Safety")
                        }
                        if item.maxStockLevel > 0 {
                            legendDot(color: Color("appIndigo", bundle: nil), label: "Max")
                        }
                    }
                    .padding(.top, 2)
                }

                Divider()

                // Metrics grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    metricCell(label: "ใช้เฉลี่ย/วัน",
                               value: m.avgDailyUsage > 0
                                   ? String(format: "%.2f %@", m.avgDailyUsage, item.unit)
                                   : "ไม่พอข้อมูล",
                               icon: "chart.bar.fill",
                               color: .blue)

                    metricCell(label: "Reorder Point",
                               value: String(format: "%.1f %@", m.reorderPoint, item.unit),
                               icon: "cart.badge.plus",
                               color: Color("appYellow", bundle: nil))

                    if let days = m.daysOfStockRemaining {
                        metricCell(label: "เหลืออีก",
                                   value: String(format: "%.0f วัน", days),
                                   icon: "clock.fill",
                                   color: days <= Double(item.leadTimeDays) ? Color("appRose", bundle: nil) : Color("appTeal", bundle: nil))
                    }

                    metricCell(label: "Lead Time",
                               value: "\(item.leadTimeDays) วัน",
                               icon: "shippingbox.fill",
                               color: .secondary)

                    if item.safetyStockLevel > 0 {
                        metricCell(label: "Safety Stock",
                                   value: String(format: "%.1f %@", item.safetyStockLevel, item.unit),
                                   icon: "shield.fill",
                                   color: .orange)
                    }

                    if item.maxStockLevel > 0 {
                        metricCell(label: "Max Stock",
                                   value: String(format: "%.1f %@", item.maxStockLevel, item.unit),
                                   icon: "arrow.up.circle.fill",
                                   color: Color("appIndigo", bundle: nil))

                        if m.isOverstocked {
                            metricCell(label: "Overstock",
                                       value: String(format: "+%.1f %@", m.overstockQty, item.unit),
                                       icon: "exclamationmark.triangle.fill",
                                       color: Color("appIndigo", bundle: nil))
                        }
                    }
                }

                // Suggested order quantity
                if m.suggestedOrderQty > 0 {
                    HStack(spacing: 8) {
                        Image(systemName: "cart.badge.plus")
                            .font(.callout).foregroundColor(Color("appTeal", bundle: nil))
                        Text("แนะนำสั่งซื้อ")
                            .font(.caption).foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "%.1f %@", m.suggestedOrderQty, item.unit))
                            .font(.subheadline).fontWeight(.semibold)
                            .foregroundColor(Color("appTeal", bundle: nil))
                    }
                    .padding(10)
                    .background(Color("appTeal", bundle: nil).opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            metrics = safetyStockManager.computeMetrics(for: item)
        }
    }

    private func metricCell(label: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.caption).foregroundColor(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(.caption).fontWeight(.semibold).foregroundColor(.primary)
                Text(label).font(.caption2).foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color("appSurfaceHigh", bundle: nil))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
    }
}

// MARK: - ReorderSuggestionListSheet

struct ReorderSuggestionListSheet: View {
    let suggestions: [ReorderSuggestion]
    let safetyStockManager: SafetyStockManager

    @Environment(\.dismiss) private var dismiss

    private var grouped: [(status: StockStatus, suggestions: [ReorderSuggestion])] {
        let order: [StockStatus] = [.outOfStock, .atReorderPoint, .belowSafety, .lowStock, .overstock]
        return order.compactMap { status in
            let filtered = suggestions.filter { $0.status == status }
            return filtered.isEmpty ? nil : (status: status, suggestions: filtered)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color("appBackground", bundle: nil).ignoresSafeArea()
                List {
                    ForEach(grouped, id: \.status) { group in
                        Section(header: sectionHeader(group.status)) {
                            ForEach(group.suggestions) { s in
                                ReorderSuggestionRow(suggestion: s)
                                    .listRowBackground(Color("appSurface", bundle: nil))
                                    .listRowInsets(EdgeInsets())
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("แนะนำการสั่งซื้อ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ปิด") { dismiss() }.foregroundColor(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func sectionHeader(_ status: StockStatus) -> some View {
        HStack(spacing: 6) {
            Image(systemName: status.systemImage)
            Text(status.displayName)
        }
        .font(.caption).fontWeight(.semibold)
        .textCase(nil)
    }
}
