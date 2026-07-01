// InventoryAnalyticsReportView.swift
// AlphaPos — Inventory Analytics Report
//
// Advanced analytics integrating FEFO lot data, Safety Stock metrics,
// and Cost-of-Goods-Sold breakdown into one unified report view.
//
// ─────────────────────────────────────────────────────────────────────────────
// Sections:
//   1. KPI Summary Row       — Stock Value / COGS / Waste % / Turnover
//   2. Stock Health Heatmap  — ABC × Status grid (A/B/C vs adequate/low/out)
//   3. Consumption Trend     — BarChart: daily usage last 30 days by category
//   4. Expiry Risk Table     — Lots expiring within 14 days (sorted by urgency)
//   5. Reorder Intelligence  — Items at/below ROP with suggested order qty
//   6. Top 10 by Cost Value  — Highest-value items (qty × cost)
//   7. Waste Breakdown       — Pie-style waste by item + cost impact
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI
import SwiftData
import Charts

// MARK: - Data Models (local to this report)

struct DailyUsagePoint: Identifiable {
    let id = UUID()
    let date: Date
    let category: String
    let quantity: Double
}

struct ItemValuePoint: Identifiable {
    let id: UUID
    let name: String
    let value: Double
    let unit: String
    let category: String
}

struct WasteBreakdownPoint: Identifiable {
    let id: UUID
    let itemName: String
    let cost: Double
    let quantity: Double
    let unit: String
}

// MARK: - InventoryAnalyticsReportView

struct InventoryAnalyticsReportView: View {
    @Bindable var viewModel: ReportsViewModel
    @EnvironmentObject private var lm: LocalizationManager

    /// Injected from ReportsView via init — same pattern as other report views.
    let allInventory: [InventoryItem]
    let allTransactions: [InventoryTransaction]
    let allLots: [InventoryLot]

    // PDF export state (shown inline when triggered from within the report)
    @State private var isExportingPDF = false
    @State private var exportedURL: URL? = nil
    @State private var showingExportShare = false

    // ── Computed Analytics ─────────────────────────────────────────────────
    private var analytics: InventoryAnalytics {
        InventoryAnalytics(
            items: allInventory,
            transactions: allTransactions,
            lots: allLots,
            start: viewModel.effectiveStartDate,
            end: viewModel.effectiveEndDate
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: APSpacing.lg) {

            // PDF export bar (inline, also wired via ReportsView toolbar button)
            pdfExportBar

            // 1. KPI Row
            kpiRow

            // 2. Stock Health Heatmap
            stockHealthSection

            // 3. Consumption Trend Chart
            consumptionTrendSection

            // 4. Expiry Risk Table
            if !analytics.expiryRiskLots.isEmpty {
                expiryRiskSection
            }

            // 5. Reorder Intelligence
            if !analytics.reorderItems.isEmpty {
                reorderSection
            }

            // 6. Top 10 by Stock Value
            topValueSection

            // 7. Waste Breakdown
            if analytics.totalWasteCost > 0 {
                wasteBreakdownSection
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: 1 — KPI Row
    // ─────────────────────────────────────────────────────────────────────────

    private var kpiRow: some View {
        HStack(spacing: APSpacing.md) {
            kpiCard(
                title: "มูลค่าสต็อก",
                value: viewModel.formatCurrency(analytics.totalStockValue),
                sub: "\(analytics.totalActiveItems) รายการ",
                icon: "archivebox.fill",
                color: .appAccent
            )
            kpiCard(
                title: "COGS (ช่วงนี้)",
                value: viewModel.formatCurrency(analytics.periodCOGS),
                sub: analytics.periodCOGSLabel,
                icon: "arrow.down.circle.fill",
                color: .blue
            )
            kpiCard(
                title: "Waste %",
                value: String(format: "%.1f%%", analytics.wastePercent),
                sub: viewModel.formatCurrency(analytics.totalWasteCost) + " สูญเสีย",
                icon: "trash.fill",
                color: analytics.wastePercent > 5 ? .red : .orange
            )
            kpiCard(
                title: "Stock Turnover",
                value: String(format: "%.1fx", analytics.stockTurnover),
                sub: analytics.turnoverLabel,
                icon: "arrow.triangle.2.circlepath",
                color: analytics.stockTurnover < 1 ? .orange : .appTeal
            )
            kpiCard(
                title: "Expiry Risk",
                value: "\(analytics.expiryRiskLots.count)",
                sub: "Lots ≤14 วัน",
                icon: "clock.badge.exclamationmark.fill",
                color: analytics.expiryRiskLots.isEmpty ? .secondary : .red
            )
        }
    }

    private func kpiCard(title: String, value: String, sub: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.caption).foregroundStyle(color)
                Text(title).font(.caption2).foregroundStyle(.secondary)
            }
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(.primary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(sub).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(APSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(translucent(.appSurfaceHigh, 0.5))
        .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: 2 — Stock Health Heatmap
    // ─────────────────────────────────────────────────────────────────────────

    private var stockHealthSection: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            sectionLabel("สุขภาพสต็อก (ABC × Status)", icon: "chart.grid.3x3.fill", color: .appAccent)

            let grid = analytics.healthGrid

            VStack(spacing: 2) {
                // Header row
                HStack(spacing: 2) {
                    headerCell("ABC")
                    headerCell("ปกติ")
                    headerCell("ต่ำ")
                    headerCell("หมด")
                    headerCell("Overstock")
                }
                ForEach(["A", "B", "C"], id: \.self) { abc in
                    HStack(spacing: 2) {
                        abcLabel(abc)
                        heatCell(count: grid[abc]?[.adequate]   ?? 0, status: .adequate)
                        heatCell(count: grid[abc]?[.lowStock]   ?? 0, status: .lowStock)
                        heatCell(count: grid[abc]?[.outOfStock] ?? 0, status: .outOfStock)
                        heatCell(count: grid[abc]?[.overstock]  ?? 0, status: .overstock)
                    }
                }
            }
        }
        .padding(APSpacing.md)
        .background(translucent(.appSurfaceHigh, 0.3))
        .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
    }

    private func headerCell(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(Color.appSurface)
    }

    private func abcLabel(_ abc: String) -> some View {
        Text(abc)
            .font(.caption.weight(.bold))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.appSurface)
    }

    private func heatCell(count: Int, status: StockStatus) -> some View {
        let isEmpty = count == 0
        return Text(isEmpty ? "—" : "\(count)")
            .font(.caption.weight(isEmpty ? .regular : .bold))
            .foregroundStyle(isEmpty ? .secondary : heatColor(status))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isEmpty ? Color.appBackground : heatColor(status).opacity(0.12))
    }

    private func heatColor(_ s: StockStatus) -> Color {
        switch s {
        case .outOfStock:   return .red
        case .lowStock, .atReorderPoint: return .orange
        case .belowSafety:  return .yellow
        case .overstock:    return Color("appIndigo", bundle: nil)
        case .adequate:     return Color("appTeal",   bundle: nil)
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: 3 — Consumption Trend
    // ─────────────────────────────────────────────────────────────────────────

    private var consumptionTrendSection: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            sectionLabel("การใช้งาน 30 วันล่าสุด (ตามหมวดหมู่)", icon: "chart.bar.fill", color: .blue)

            let points = analytics.dailyUsagePoints
            if points.isEmpty {
                emptyState("ยังไม่มีข้อมูลการใช้งานในช่วงนี้")
            } else {
                let categories = Array(Set(points.map { $0.category })).sorted()
                Chart(points) { pt in
                    BarMark(
                        x: .value("วันที่", pt.date, unit: .day),
                        y: .value("ปริมาณ", pt.quantity)
                    )
                    .foregroundStyle(by: .value("หมวด", pt.category))
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 5)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    }
                }
                .chartYAxis {
                    AxisMarks { AxisGridLine(); AxisValueLabel() }
                }
                .chartForegroundStyleScale(
                    domain: categories,
                    range: chartColors(count: categories.count)
                )
                .chartLegend(position: .bottom, alignment: .leading)
                .frame(height: 180)
            }
        }
        .padding(APSpacing.md)
        .background(translucent(.blue, 0.04))
        .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
    }

    private func chartColors(count: Int) -> [Color] {
        let palette: [Color] = [.appAccent, .blue, .appTeal, .orange, .pink, .purple, .green, .yellow]
        return (0..<count).map { palette[$0 % palette.count] }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: 4 — Expiry Risk Table
    // ─────────────────────────────────────────────────────────────────────────

    private var expiryRiskSection: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            sectionLabel("Expiry Risk — Lots ≤14 วัน", icon: "clock.badge.exclamationmark.fill", color: .red)

            tableHeader([("รายการ", nil), ("Lot #", 100), ("หมดอายุ", 90), ("เหลือ", 60), ("มูลค่าเสี่ยง", 100)])

            Divider()

            ForEach(analytics.expiryRiskLots) { lot in
                let daysLeft = Calendar.current.dateComponents([.day], from: Date(), to: lot.expiryDate!).day ?? 0
                let riskValue = lot.remainingQuantity * lot.lotCostPrice
                let status: ExpiryStatus = daysLeft < 0 ? .expired : daysLeft <= 3 ? .critical : .warning

                HStack {
                    Text(lot.inventoryItem?.name ?? "—")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(1)
                    Text(lot.lotNumber ?? "—")
                        .frame(width: 100, alignment: .leading)
                        .foregroundStyle(.secondary)
                    Text(shortDate(lot.expiryDate!))
                        .frame(width: 90, alignment: .leading)
                    ExpiryBadge(status: status, daysLeft: daysLeft)
                        .frame(width: 60, alignment: .center)
                    Text(viewModel.formatCurrency(riskValue))
                        .frame(width: 100, alignment: .trailing)
                        .foregroundStyle(.red)
                        .fontWeight(.semibold)
                }
                .font(.subheadline.monospacedDigit())
                .padding(.vertical, 4)

                Divider().opacity(0.5)
            }
        }
        .padding(APSpacing.md)
        .background(translucent(.red, 0.04))
        .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: 5 — Reorder Intelligence
    // ─────────────────────────────────────────────────────────────────────────

    private var reorderSection: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            sectionLabel("Reorder Intelligence", icon: "cart.badge.plus", color: .orange)

            tableHeader([
                ("รายการ",       nil),
                ("สต็อกปัจจุบัน", 120),
                ("Reorder Point", 120),
                ("แนะนำสั่ง",    100),
                ("Lead Time",    80),
                ("Supplier",     120)
            ])
            Divider()

            ForEach(analytics.reorderItems, id: \.item.id) { s in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(s.item.name).lineLimit(1)
                        StockStatusBadge(status: s.status)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text(String(format: "%.1f %@", s.item.currentQuantity, s.item.unit))
                        .frame(width: 120, alignment: .trailing)
                        .foregroundStyle(s.status == .outOfStock ? .red : .primary)

                    Text(String(format: "%.1f", s.reorderPoint))
                        .frame(width: 120, alignment: .trailing)
                        .foregroundStyle(.secondary)

                    Text(String(format: "%.1f %@", s.suggestedOrderQty, s.item.unit))
                        .frame(width: 100, alignment: .trailing)
                        .foregroundStyle(Color("appTeal", bundle: nil))
                        .fontWeight(.semibold)

                    Text("\(s.leadTimeDays)d")
                        .frame(width: 80, alignment: .center)
                        .foregroundStyle(.secondary)

                    Text(s.supplierName ?? "—")
                        .frame(width: 120, alignment: .leading)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .font(.subheadline.monospacedDigit())
                .padding(.vertical, 4)

                Divider().opacity(0.5)
            }
        }
        .padding(APSpacing.md)
        .background(translucent(.orange, 0.04))
        .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: 6 — Top 10 by Stock Value
    // ─────────────────────────────────────────────────────────────────────────

    private var topValueSection: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            sectionLabel("Top 10 มูลค่าสต็อกสูงสุด", icon: "star.fill", color: .appAccent)

            let top10 = analytics.topValueItems.prefix(10)
            let maxVal = top10.first?.value ?? 1

            ForEach(Array(top10.enumerated()), id: \.element.id) { rank, item in
                HStack(spacing: APSpacing.sm) {
                    // Rank badge
                    Text("\(rank + 1)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, alignment: .center)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name).font(.subheadline).lineLimit(1)
                        Text(item.category.isEmpty ? "ไม่ระบุหมวด" : item.category)
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Mini bar
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.appAccent.opacity(0.25))
                            .frame(height: 8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.appAccent)
                                    .frame(width: geo.size.width * (item.value / maxVal), height: 8),
                                alignment: .leading
                            )
                    }
                    .frame(height: 8)

                    Text(viewModel.formatCurrency(item.value))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .frame(width: 110, alignment: .trailing)
                }
                .padding(.vertical, 5)

                if rank < Int(top10.count) - 1 {
                    Divider().opacity(0.4)
                }
            }
        }
        .padding(APSpacing.md)
        .background(translucent(.appSurfaceHigh, 0.3))
        .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: 7 — Waste Breakdown
    // ─────────────────────────────────────────────────────────────────────────

    private var wasteBreakdownSection: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            HStack {
                sectionLabel("Waste Breakdown (ช่วงนี้)", icon: "trash.fill", color: .pink)
                Spacer()
                Text("รวม: \(viewModel.formatCurrency(analytics.totalWasteCost))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.pink)
            }

            // Top-waste chart
            let wastePoints = analytics.wasteBreakdown.prefix(8)
            if !wastePoints.isEmpty {
                Chart(Array(wastePoints), id: \.id) { pt in
                    BarMark(
                        x: .value("Cost", pt.cost),
                        y: .value("Item", pt.itemName)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.pink, .pink.opacity(0.5)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .annotation(position: .trailing) {
                        Text(viewModel.formatCurrency(pt.cost))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .chartXAxis(.hidden)
                .frame(height: CGFloat(wastePoints.count) * 34)
            }

            // Waste % of stock value
            let pct = analytics.wastePercent
            HStack(spacing: 8) {
                Image(systemName: pct > 10 ? "exclamationmark.triangle.fill" : pct > 5 ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(pct > 10 ? .red : pct > 5 ? .orange : Color("appTeal", bundle: nil))
                Text(String(format: "Waste คิดเป็น %.1f%% ของมูลค่าสต็อก", pct))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(pct > 5 ? "⚠️ ควรตรวจสอบ FEFO" : "✅ อยู่ในเกณฑ์ปกติ")
                    .font(.caption2)
                    .foregroundStyle(pct > 5 ? .orange : .secondary)
            }
            .padding(8)
            .background(Color.appBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(APSpacing.md)
        .background(translucent(.pink, 0.04))
        .clipShape(RoundedRectangle(cornerRadius: APRadius.md))
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: — Shared Helpers
    // ─────────────────────────────────────────────────────────────────────────

    private func sectionLabel(_ title: String, icon: String, color: Color) -> some View {
        Label(title, systemImage: icon)
            .font(.headline)
            .foregroundStyle(color)
    }

    private func tableHeader(_ columns: [(String, CGFloat?)]) -> some View {
        HStack {
            ForEach(columns, id: \.0) { (title, width) in
                if let w = width {
                    Text(title).frame(width: w, alignment: title == columns.last?.0 ? .trailing : .leading)
                } else {
                    Text(title).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    private func emptyState(_ message: String) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.vertical, APSpacing.md)
    }

    private func shortDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "dd/MM/yy"
        return fmt.string(from: date)
    }

    private func translucent(_ color: Color, _ opacity: Double) -> Color {
        color.opacity(opacity)
    }


    // ─────────────────────────────────────────────────────────────────────────
    // MARK: — PDF Export Bar
    // ─────────────────────────────────────────────────────────────────────────

    private var pdfExportBar: some View {
        HStack(spacing: APSpacing.sm) {
            Image(systemName: "doc.badge.arrow.up.fill")
                .font(.callout)
                .foregroundStyle(Color.appAccent)

            Text("Inventory Analytics Report")
                .font(.caption).fontWeight(.semibold)
                .foregroundStyle(.primary)

            Spacer()

            if isExportingPDF {
                ProgressView()
                    .scaleEffect(0.75)
                Text("กำลังสร้าง PDF...")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                Button {
                    exportPDF()
                } label: {
                    Label("Export PDF", systemImage: "square.and.arrow.up")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Color.appAccent)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color("appSurface", bundle: nil))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color("appDivider", bundle: nil), lineWidth: 0.5)
        )
        .sheet(isPresented: $showingExportShare) {
            if let url = exportedURL {
                ShareSheet(activityItems: [url])
            }
        }
    }

    private func exportPDF() {
        isExportingPDF = true
        Task { @MainActor in
            let url = InventoryAnalyticsPDFExporter.export(
                analytics: analytics,
                periodLabel: viewModel.periodDescription
            )
            isExportingPDF = false
            if let url {
                exportedURL = url
                showingExportShare = true
            }
        }
    }

}

// MARK: - InventoryAnalytics (pure computation struct)

/// All heavy computation isolated here — no SwiftUI dependency, easily testable.
struct InventoryAnalytics {
    let items: [InventoryItem]
    let transactions: [InventoryTransaction]
    let lots: [InventoryLot]
    let start: Date
    let end: Date

    private var activeItems: [InventoryItem]  { items.filter { !$0.isDeleted } }
    private var periodTxns:  [InventoryTransaction] {
        transactions.filter {
            !$0.isDeleted && $0.updatedAt >= start && $0.updatedAt < end
        }
    }

    // ── KPIs ─────────────────────────────────────────────────────────────────

    var totalActiveItems: Int { activeItems.count }

    var totalStockValue: Double {
        activeItems.reduce(0) { $0 + max($1.currentQuantity, 0) * $1.costPrice }
    }

    var periodCOGS: Double {
        periodTxns
            .filter { $0.transactionType == InventoryMovementType.sell.rawValue }
            .reduce(0) { $0 + $1.quantity * ($1.costPrice ?? $1.item?.costPrice ?? 0) }
    }

    var periodCOGSLabel: String {
        let days = Calendar.current.dateComponents([.day], from: start, to: end).day ?? 1
        return "ใน \(days) วัน"
    }

    var totalWasteCost: Double {
        periodTxns
            .filter { $0.transactionType == InventoryMovementType.waste.rawValue }
            .reduce(0) { $0 + $1.quantity * ($1.costPrice ?? $1.item?.costPrice ?? 0) }
    }

    var wastePercent: Double {
        guard totalStockValue > 0 else { return 0 }
        return (totalWasteCost / totalStockValue) * 100
    }

    /// Inventory Turnover = COGS ÷ Average Stock Value
    /// Simplified: COGS ÷ current stock value (single-point snapshot).
    var stockTurnover: Double {
        guard totalStockValue > 0 else { return 0 }
        return periodCOGS / totalStockValue
    }

    var turnoverLabel: String {
        if stockTurnover >= 12 { return "หมุนเร็ว ✅" }
        if stockTurnover >= 4  { return "ปกติ" }
        return "หมุนช้า ⚠️"
    }

    // ── ABC Classification (by stock value contribution) ─────────────────────
    /// Returns a dictionary [itemId → "A"|"B"|"C"]
    private var abcMap: [UUID: String] {
        let sorted = activeItems.sorted { a, b in
            (a.currentQuantity * a.costPrice) > (b.currentQuantity * b.costPrice)
        }
        let total = totalStockValue
        guard total > 0 else { return [:] }

        var cumulative = 0.0
        var result: [UUID: String] = [:]
        for item in sorted {
            cumulative += (item.currentQuantity * item.costPrice)
            let pct = cumulative / total
            result[item.id] = pct <= 0.70 ? "A" : pct <= 0.90 ? "B" : "C"
        }
        return result
    }

    // ── Health Heatmap Grid ────────────────────────────────────────────────

    var healthGrid: [String: [StockStatus: Int]] {
        var grid: [String: [StockStatus: Int]] = ["A": [:], "B": [:], "C": [:]]
        for item in activeItems {
            let abc = abcMap[item.id] ?? "C"
            let status = itemStatus(item)
            grid[abc]![status, default: 0] += 1
        }
        return grid
    }

    private func itemStatus(_ item: InventoryItem) -> StockStatus {
        if item.currentQuantity <= 0 { return .outOfStock }
        if item.currentQuantity <= item.reorderLevel { return .lowStock }
        if item.maxStockLevel > 0, item.currentQuantity > item.maxStockLevel { return .overstock }
        if item.safetyStockLevel > 0, item.currentQuantity <= item.safetyStockLevel { return .belowSafety }
        return .adequate
    }

    // ── Daily Usage Points (30-day window) ────────────────────────────────────

    var dailyUsagePoints: [DailyUsagePoint] {
        let lookback = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let usageTxns = transactions.filter {
            !$0.isDeleted
            && ($0.transactionType == InventoryMovementType.sell.rawValue || $0.transactionType == InventoryMovementType.waste.rawValue)
            && $0.updatedAt >= lookback
        }

        let cal = Calendar.current
        var byDayCategory: [String: Double] = [:]  // "2026-06-01|Meat" → total qty

        for txn in usageTxns {
            let day = cal.startOfDay(for: txn.updatedAt)
            let dayStr = ISO8601DateFormatter().string(from: day)
            let cat = txn.item?.category ?? "ไม่ระบุ"
            let key = "\(dayStr)|\(cat)"
            byDayCategory[key, default: 0] += txn.quantity
        }

        let fmt = ISO8601DateFormatter()
        return byDayCategory.compactMap { key, qty in
            let parts = key.split(separator: "|", maxSplits: 1)
            guard parts.count == 2,
                  let date = fmt.date(from: String(parts[0])) else { return nil }
            return DailyUsagePoint(date: date, category: String(parts[1]), quantity: qty)
        }
        .sorted { $0.date < $1.date }
    }

    // ── Expiry Risk Lots ─────────────────────────────────────────────────────

    var expiryRiskLots: [InventoryLot] {
        let cutoff = Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date()
        return lots
            .filter { !$0.isDeleted && $0.remainingQuantity > 0 }
            .filter { lot in
                guard let exp = lot.expiryDate else { return false }
                return exp <= cutoff
            }
            .sorted {
                ($0.expiryDate ?? .distantFuture) < ($1.expiryDate ?? .distantFuture)
            }
    }

    // ── Reorder Items (using SafetyStockManager is not available here — pure calculation) ──

    var reorderItems: [ReorderSuggestion] {
        // lightweight ROP check without SafetyStockManager (no ModelContext available)
        activeItems
            .filter { item in
                let rop = item.safetyStockLevel + (0 * Double(item.leadTimeDays)) // no usage data here
                return item.currentQuantity <= max(item.reorderLevel, rop)
            }
            .map { item in
                let rop = item.safetyStockLevel + item.reorderLevel
                let target = item.maxStockLevel > 0 ? item.maxStockLevel : item.reorderLevel * 2
                let suggestQty = max(target - item.currentQuantity, 0)
                let status: StockStatus = item.currentQuantity <= 0 ? .outOfStock
                    : item.currentQuantity <= item.reorderLevel ? .atReorderPoint
                    : .belowSafety
                return ReorderSuggestion(
                    id: UUID(),
                    item: item,
                    status: status,
                    reorderPoint: rop,
                    suggestedOrderQty: suggestQty,
                    daysOfStockRemaining: nil,
                    urgencyDays: nil,
                    supplierName: item.supplier?.name,
                    leadTimeDays: item.leadTimeDays
                )
            }
            .sorted { $0.status.urgencyRank < $1.status.urgencyRank }
    }

    // ── Top Value Items ───────────────────────────────────────────────────────

    var topValueItems: [ItemValuePoint] {
        activeItems
            .map { item in
                ItemValuePoint(
                    id: item.id,
                    name: item.name,
                    value: max(item.currentQuantity, 0) * item.costPrice,
                    unit: item.unit,
                    category: item.category ?? ""
                )
            }
            .filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
    }

    // ── Waste Breakdown ───────────────────────────────────────────────────────

    var wasteBreakdown: [WasteBreakdownPoint] {
        var byItem: [UUID: WasteBreakdownPoint] = [:]
        for txn in periodTxns where txn.transactionType == InventoryMovementType.waste.rawValue {
            guard let item = txn.item else { continue }
            let cost = txn.quantity * (txn.costPrice ?? item.costPrice)
            if var existing = byItem[item.id] {
                let newCost = existing.cost + cost
                let newQty  = existing.quantity + txn.quantity
                byItem[item.id] = WasteBreakdownPoint(
                    id: item.id, itemName: item.name,
                    cost: newCost, quantity: newQty, unit: item.unit
                )
            } else {
                byItem[item.id] = WasteBreakdownPoint(
                    id: item.id, itemName: item.name,
                    cost: cost, quantity: txn.quantity, unit: item.unit
                )
            }
        }
        return byItem.values.sorted { $0.cost > $1.cost }
    }
}

// Type aliases for local point structs (scoped to this file)
// DailyUsagePoint, ItemValuePoint, WasteBreakdownPoint defined at top of file.
