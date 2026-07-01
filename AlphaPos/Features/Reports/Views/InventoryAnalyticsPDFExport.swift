// InventoryAnalyticsPDFExport.swift
// AlphaPos — Inventory Analytics: Multi-Page PDF Export
//
// Produces a professional A4 PDF report from InventoryAnalytics data.
// Uses CoreGraphics directly (not ImageRenderer) so content spans multiple pages.
//
// ─────────────────────────────────────────────────────────────────────────────
// Architecture:
//   InventoryAnalyticsPDFExporter  — main export actor, builds the CGContext
//   PDFPage                        — internal page builder (auto-paginates)
//   Sections rendered:
//     Page 1: Cover + KPI summary
//     Page 2: Stock Health Heatmap + Reorder Intelligence table
//     Page 3: Expiry Risk table (if any lots) + Top-10 Value
//     Page 4: Consumption trend (text summary) + Waste Breakdown
// ─────────────────────────────────────────────────────────────────────────────

import Foundation
import UIKit
import CoreGraphics
import SwiftData

// MARK: - PDF Constants

private enum PDF {
    static let pageWidth:  CGFloat = 595.28   // A4 portrait
    static let pageHeight: CGFloat = 841.89
    static let marginH:    CGFloat = 40
    static let marginV:    CGFloat = 50
    static let contentWidth: CGFloat = pageWidth - marginH * 2

    // Typography
    static func font(_ size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        UIFont.systemFont(ofSize: size, weight: weight)
    }
    static var titleFont:    UIFont { font(20, weight: .bold) }
    static var headingFont:  UIFont { font(13, weight: .semibold) }
    static var bodyFont:     UIFont { font(10) }
    static var captionFont:  UIFont { font(8.5) }
    static var monoFont:     UIFont { UIFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular) }

    // Colours (UIColor so they work in CoreGraphics context)
    static var accent:     UIColor { UIColor(red: 0.20, green: 0.60, blue: 0.86, alpha: 1) }
    static var teal:       UIColor { UIColor(red: 0.15, green: 0.70, blue: 0.65, alpha: 1) }
    static var rose:       UIColor { UIColor(red: 0.90, green: 0.25, blue: 0.35, alpha: 1) }
    static var orange:     UIColor { UIColor(red: 0.95, green: 0.55, blue: 0.10, alpha: 1) }
    static var yellow:     UIColor { UIColor(red: 0.95, green: 0.80, blue: 0.10, alpha: 1) }
    static var indigo:     UIColor { UIColor(red: 0.35, green: 0.30, blue: 0.80, alpha: 1) }
    static var surface:    UIColor { UIColor(red: 0.95, green: 0.96, blue: 0.97, alpha: 1) }
    static var divider:    UIColor { UIColor(red: 0.85, green: 0.87, blue: 0.90, alpha: 1) }
    static var primary:    UIColor { .label }
    static var secondary:  UIColor { .secondaryLabel }
    static var background: UIColor { .systemBackground }
}

// MARK: - InventoryAnalyticsPDFExporter

@MainActor
final class InventoryAnalyticsPDFExporter {

    // MARK: - Entry Point

    /// Generates the PDF and returns the file URL on success.
    static func export(
        analytics: InventoryAnalytics,
        periodLabel: String,
        merchantName: String = "AlphaPos",
        branchName: String? = nil
    ) -> URL? {
        let filename = "Inventory_Analytics_\(dateStamp()).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        var mediaBox = CGRect(origin: .zero, size: CGSize(width: PDF.pageWidth, height: PDF.pageHeight))

        guard let ctx = CGContext(url as CFURL, mediaBox: &mediaBox, pdfInfo) else { return nil }

        let builder = PDFBuilder(context: ctx, analytics: analytics,
                                 periodLabel: periodLabel,
                                 merchantName: merchantName,
                                 branchName: branchName)
        builder.buildAllPages()
        ctx.closePDF()
        return url
    }

    private static var pdfInfo: CFDictionary {
        [
            kCGPDFContextTitle:   "Inventory Analytics Report" as CFString,
            kCGPDFContextCreator: "AlphaPos" as CFString
        ] as CFDictionary
    }

    private static func dateStamp() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd_HHmm"
        return df.string(from: Date())
    }
}

// MARK: - PDFBuilder (internal page engine)

private final class PDFBuilder {
    let ctx: CGContext
    let analytics: InventoryAnalytics
    let periodLabel: String
    let merchantName: String
    let branchName: String?

    // Page state
    var currentY: CGFloat = 0
    let pageWidth  = PDF.pageWidth
    let pageHeight = PDF.pageHeight
    let marginH    = PDF.marginH
    let marginV    = PDF.marginV
    var contentWidth: CGFloat { pageWidth - marginH * 2 }

    init(context: CGContext, analytics: InventoryAnalytics,
         periodLabel: String, merchantName: String, branchName: String?) {
        self.ctx          = context
        self.analytics    = analytics
        self.periodLabel  = periodLabel
        self.merchantName = merchantName
        self.branchName   = branchName
    }

    func buildAllPages() {
        startPage()
        drawCoverHeader()
        drawKPITable()
        drawStockHealthHeatmap()
        checkPageBreak(needed: 200)
        drawReorderTable()
        checkPageBreak(needed: 200)
        drawExpiryRiskTable()
        checkPageBreak(needed: 200)
        drawTopValueTable()
        checkPageBreak(needed: 200)
        drawWasteBreakdownTable()
        endPage()
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Page Management
    // ─────────────────────────────────────────────────────────────────────────

    func startPage() {
        var box = CGRect(origin: .zero, size: CGSize(width: pageWidth, height: pageHeight))
        ctx.beginPage(mediaBox: &box)
        currentY = pageHeight - marginV
        drawPageFooter()
    }

    func endPage() {
        ctx.endPage()
    }

    func checkPageBreak(needed: CGFloat) {
        if currentY - needed < marginV + 30 {
            endPage()
            startPage()
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Header & Footer
    // ─────────────────────────────────────────────────────────────────────────

    func drawCoverHeader() {
        // Accent bar
        ctx.setFillColor(PDF.accent.cgColor)
        ctx.fill(CGRect(x: 0, y: pageHeight - 8, width: pageWidth, height: 8))

        currentY -= 10

        // Logo / merchant name
        draw(merchantName, at: CGPoint(x: marginH, y: currentY),
             font: PDF.titleFont, color: PDF.accent)
        currentY -= 26

        // Report title
        draw("Inventory Analytics Report", at: CGPoint(x: marginH, y: currentY),
             font: PDF.font(16, weight: .semibold), color: PDF.primary)
        currentY -= 18

        // Period + branch
        let subtitle = [periodLabel, branchName.map { "Branch: \($0)" }]
            .compactMap { $0 }.joined(separator: " · ")
        draw(subtitle, at: CGPoint(x: marginH, y: currentY),
             font: PDF.bodyFont, color: PDF.secondary)
        currentY -= 12

        // Generated timestamp
        let ts = "Generated: \(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short))"
        draw(ts, at: CGPoint(x: marginH, y: currentY),
             font: PDF.captionFont, color: PDF.secondary)
        currentY -= 20

        // Divider
        drawHRule(y: currentY)
        currentY -= 16
    }

    func drawPageFooter() {
        drawHRule(y: marginV - 8)
        draw("AlphaPos · Inventory Analytics · Confidential",
             at: CGPoint(x: marginH, y: marginV - 22),
             font: PDF.captionFont, color: PDF.secondary)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: KPI Table
    // ─────────────────────────────────────────────────────────────────────────

    func drawKPITable() {
        drawSectionHeader("Key Performance Indicators", color: PDF.accent)

        let kpis: [(label: String, value: String, sub: String)] = [
            ("Total Stock Value",   formatCurrency(analytics.totalStockValue), "\(analytics.totalActiveItems) items"),
            ("Period COGS",         formatCurrency(analytics.periodCOGS),      analytics.periodCOGSLabel),
            ("Waste Cost",          formatCurrency(analytics.totalWasteCost),   String(format: "%.1f%% of stock", analytics.wastePercent)),
            ("Stock Turnover",      String(format: "%.2fx", analytics.stockTurnover), analytics.turnoverLabel),
            ("Expiry Risk Lots",    "\(analytics.expiryRiskLots.count)",        "expiring ≤14 days"),
            ("Reorder Items",       "\(analytics.reorderItems.count)",          "need attention"),
        ]

        let colW = contentWidth / 3
        let rowH: CGFloat = 44
        var col = 0

        for (i, kpi) in kpis.enumerated() {
            col = i % 3
            let x = marginH + CGFloat(col) * colW
            if col == 0 && i > 0 { currentY -= rowH + 4 }

            // Card background
            let rect = CGRect(x: x + 2, y: currentY - rowH, width: colW - 4, height: rowH)
            ctx.setFillColor(PDF.surface.cgColor)
            ctx.fill(rect)
            ctx.setStrokeColor(PDF.divider.cgColor)
            ctx.setLineWidth(0.5)
            ctx.stroke(rect)

            // Value
            draw(kpi.value, at: CGPoint(x: x + 8, y: currentY - 18),
                 font: PDF.font(12, weight: .bold), color: PDF.primary)
            // Label
            draw(kpi.label, at: CGPoint(x: x + 8, y: currentY - 30),
                 font: PDF.captionFont, color: PDF.secondary)
            // Sub
            draw(kpi.sub, at: CGPoint(x: x + 8, y: currentY - 40),
                 font: PDF.captionFont, color: PDF.secondary)
        }
        currentY -= rowH + 20
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Stock Health Heatmap
    // ─────────────────────────────────────────────────────────────────────────

    func drawStockHealthHeatmap() {
        drawSectionHeader("Stock Health Heatmap (ABC × Status)", color: PDF.teal)

        let statuses: [StockStatus] = [.adequate, .lowStock, .outOfStock, .overstock]
        let statusLabels = ["Adequate", "Low Stock", "Out of Stock", "Overstock"]
        let abcClasses = ["A", "B", "C"]
        let grid = analytics.healthGrid

        let colLabels = ["Class"] + statusLabels
        let colWidths: [CGFloat] = [50, 80, 80, 80, 80]

        // Header
        drawTableRow(cells: colLabels, widths: colWidths, y: currentY,
                     isHeader: true, headerBg: PDF.teal)
        currentY -= 22

        for abc in abcClasses {
            let values: [String] = [abc] + statuses.map { s in
                let c = grid[abc]?[s] ?? 0
                return c == 0 ? "—" : "\(c)"
            }
            let colors: [UIColor?] = [nil] + statuses.map { s in
                let c = grid[abc]?[s] ?? 0
                guard c > 0 else { return nil }
                return cellColor(for: s)
            }
            drawTableRow(cells: values, widths: colWidths, y: currentY,
                         isHeader: false, cellColors: colors)
            currentY -= 20
        }
        currentY -= 10
    }

    private func cellColor(for status: StockStatus) -> UIColor {
        switch status {
        case .outOfStock:  return PDF.rose.withAlphaComponent(0.25)
        case .lowStock, .atReorderPoint: return PDF.orange.withAlphaComponent(0.20)
        case .belowSafety: return PDF.yellow.withAlphaComponent(0.25)
        case .overstock:   return PDF.indigo.withAlphaComponent(0.20)
        case .adequate:    return PDF.teal.withAlphaComponent(0.15)
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Reorder Table
    // ─────────────────────────────────────────────────────────────────────────

    func drawReorderTable() {
        guard !analytics.reorderItems.isEmpty else { return }
        drawSectionHeader("Reorder Intelligence (\(analytics.reorderItems.count) items)", color: PDF.orange)

        let headers = ["Item", "Current Qty", "Reorder Pt", "Suggest Order", "Lead", "Supplier"]
        let widths: [CGFloat] = [140, 70, 70, 80, 35, 100]

        drawTableRow(cells: headers, widths: widths, y: currentY,
                     isHeader: true, headerBg: PDF.orange)
        currentY -= 22

        for s in analytics.reorderItems.prefix(20) {
            checkPageBreak(needed: 20)
            let statusLabel = s.status.displayName
            let cells = [
                "\(s.item.name) [\(statusLabel)]",
                String(format: "%.1f %@", s.item.currentQuantity, s.item.unit),
                String(format: "%.1f", s.reorderPoint),
                String(format: "%.1f %@", s.suggestedOrderQty, s.item.unit),
                "\(s.leadTimeDays)d",
                s.supplierName ?? "—"
            ]
            let rowBg: UIColor? = s.status == .outOfStock ? PDF.rose.withAlphaComponent(0.10) : nil
            drawTableRow(cells: cells, widths: widths, y: currentY,
                         isHeader: false, rowBg: rowBg)
            currentY -= 18
        }
        currentY -= 10
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Expiry Risk Table
    // ─────────────────────────────────────────────────────────────────────────

    func drawExpiryRiskTable() {
        guard !analytics.expiryRiskLots.isEmpty else { return }
        drawSectionHeader("Expiry Risk — Lots ≤14 Days (\(analytics.expiryRiskLots.count) lots)",
                          color: PDF.rose)

        let headers = ["Item", "Lot #", "Expiry Date", "Days Left", "Qty", "Risk Value (฿)"]
        let widths: [CGFloat] = [140, 80, 75, 60, 60, 90]

        drawTableRow(cells: headers, widths: widths, y: currentY,
                     isHeader: true, headerBg: PDF.rose)
        currentY -= 22

        let df = DateFormatter()
        df.dateFormat = "dd/MM/yyyy"

        for lot in analytics.expiryRiskLots.prefix(25) {
            checkPageBreak(needed: 20)
            guard let exp = lot.expiryDate else { continue }
            let days = Calendar.current.dateComponents([.day], from: Date(), to: exp).day ?? 0
            let riskVal = lot.remainingQuantity * lot.lotCostPrice
            let cells = [
                lot.inventoryItem?.name ?? "—",
                lot.lotNumber ?? "—",
                df.string(from: exp),
                days < 0 ? "EXPIRED" : "\(days)d",
                String(format: "%.1f", lot.remainingQuantity),
                formatCurrency(riskVal)
            ]
            let rowBg: UIColor? = days < 0 ? PDF.rose.withAlphaComponent(0.12)
                : days <= 3 ? PDF.orange.withAlphaComponent(0.10) : nil
            drawTableRow(cells: cells, widths: widths, y: currentY,
                         isHeader: false, rowBg: rowBg)
            currentY -= 18
        }
        currentY -= 10
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Top 10 Value Table
    // ─────────────────────────────────────────────────────────────────────────

    func drawTopValueTable() {
        let top10 = analytics.topValueItems.prefix(10)
        guard !top10.isEmpty else { return }
        drawSectionHeader("Top 10 Items by Stock Value", color: PDF.accent)

        let headers = ["#", "Item", "Category", "Qty", "Unit Cost", "Stock Value"]
        let widths: [CGFloat] = [20, 150, 90, 55, 80, 100]

        drawTableRow(cells: headers, widths: widths, y: currentY,
                     isHeader: true, headerBg: PDF.accent)
        currentY -= 22

        let totalVal = analytics.totalStockValue
        for (i, item) in top10.enumerated() {
            checkPageBreak(needed: 20)
            let pct = totalVal > 0 ? (item.value / totalVal) * 100 : 0
            let cells = [
                "\(i + 1)",
                item.name,
                item.category.isEmpty ? "—" : item.category,
                "—",   // qty not stored in ItemValuePoint — just show value
                "—",
                "\(formatCurrency(item.value)) (\(String(format: "%.1f%%", pct)))"
            ]
            drawTableRow(cells: cells, widths: widths, y: currentY, isHeader: false)
            currentY -= 18
        }
        currentY -= 10
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Waste Breakdown Table
    // ─────────────────────────────────────────────────────────────────────────

    func drawWasteBreakdownTable() {
        let waste = analytics.wasteBreakdown
        guard !waste.isEmpty else { return }
        drawSectionHeader(
            "Waste Breakdown — \(formatCurrency(analytics.totalWasteCost)) total (\(String(format: "%.1f%%", analytics.wastePercent)) of stock)",
            color: UIColor.systemPink
        )

        let headers = ["Item", "Qty Wasted", "Unit", "Cost (฿)", "% of Total Waste"]
        let widths: [CGFloat] = [160, 80, 60, 100, 95]

        drawTableRow(cells: headers, widths: widths, y: currentY,
                     isHeader: true, headerBg: UIColor.systemPink)
        currentY -= 22

        let totalWaste = analytics.totalWasteCost
        for entry in waste.prefix(20) {
            checkPageBreak(needed: 20)
            let pct = totalWaste > 0 ? (entry.cost / totalWaste) * 100 : 0
            let cells = [
                entry.itemName,
                String(format: "%.2f", entry.quantity),
                entry.unit,
                formatCurrency(entry.cost),
                String(format: "%.1f%%", pct)
            ]
            drawTableRow(cells: cells, widths: widths, y: currentY, isHeader: false)
            currentY -= 18
        }

        // Waste health note
        currentY -= 6
        let note = analytics.wastePercent > 5
            ? "⚠️  Waste exceeds 5% of stock value. Review FEFO lot consumption and expiry management."
            : "✅  Waste within acceptable range (<5% of stock value)."
        draw(note, at: CGPoint(x: marginH, y: currentY),
             font: PDF.bodyFont, color: analytics.wastePercent > 5 ? PDF.orange : PDF.teal)
        currentY -= 16
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Drawing Primitives
    // ─────────────────────────────────────────────────────────────────────────

    func drawSectionHeader(_ title: String, color: UIColor) {
        checkPageBreak(needed: 40)
        // Left accent bar
        ctx.setFillColor(color.cgColor)
        ctx.fill(CGRect(x: marginH, y: currentY - 14, width: 3, height: 14))
        // Title
        draw(title, at: CGPoint(x: marginH + 8, y: currentY - 12),
             font: PDF.headingFont, color: color)
        currentY -= 22
    }

    func drawHRule(y: CGFloat) {
        ctx.setStrokeColor(PDF.divider.cgColor)
        ctx.setLineWidth(0.5)
        ctx.move(to: CGPoint(x: marginH, y: y))
        ctx.addLine(to: CGPoint(x: pageWidth - marginH, y: y))
        ctx.strokePath()
    }

    func draw(_ text: String, at point: CGPoint, font: UIFont, color: UIColor,
              maxWidth: CGFloat? = nil) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let w = maxWidth ?? contentWidth
        let bounds = str.boundingRect(with: CGSize(width: w, height: 1000),
                                      options: .usesLineFragmentOrigin, context: nil)
        UIGraphicsPushContext(ctx)
        str.draw(in: CGRect(origin: point, size: CGSize(width: w, height: bounds.height)))
        UIGraphicsPopContext()
    }

    func drawTableRow(
        cells: [String],
        widths: [CGFloat],
        y: CGFloat,
        isHeader: Bool,
        headerBg: UIColor? = nil,
        rowBg: UIColor? = nil,
        cellColors: [UIColor?]? = nil
    ) {
        let rowH: CGFloat = isHeader ? 18 : 16
        var x = marginH

        for (i, (cell, width)) in zip(cells, widths).enumerated() {
            let rect = CGRect(x: x, y: y - rowH, width: width, height: rowH)

            // Background
            let bg: UIColor? = isHeader ? (headerBg ?? PDF.accent) : (cellColors?[i] ?? rowBg)
            if let bg {
                ctx.setFillColor(bg.cgColor)
                ctx.fill(rect)
            }

            // Border
            ctx.setStrokeColor(PDF.divider.cgColor)
            ctx.setLineWidth(0.3)
            ctx.stroke(rect)

            // Text
            let textColor: UIColor = isHeader ? .white : PDF.primary
            let font = isHeader ? PDF.font(8.5, weight: .semibold) : PDF.captionFont
            let textRect = rect.insetBy(dx: 3, dy: 2)
            UIGraphicsPushContext(ctx)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: textColor
            ]
            let truncated = truncate(cell, width: textRect.width, font: font)
            NSAttributedString(string: truncated, attributes: attrs)
                .draw(in: textRect)
            UIGraphicsPopContext()

            x += width
        }
    }

    private func truncate(_ text: String, width: CGFloat, font: UIFont) -> String {
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        if (text as NSString).size(withAttributes: attrs).width <= width { return text }
        var s = text
        while s.count > 1 {
            s = String(s.dropLast())
            if ((s + "…") as NSString).size(withAttributes: attrs).width <= width {
                return s + "…"
            }
        }
        return s
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: Formatting Helpers
    // ─────────────────────────────────────────────────────────────────────────

    private func formatCurrency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "THB"
        f.currencySymbol = "฿"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "฿\(Int(value))"
    }
}

// MARK: - ReportsViewModel Extension — Analytics PDF trigger

extension ReportsViewModel {
    /// Generates and shares the Inventory Analytics PDF.
    /// Called from a toolbar button when selectedReport == .inventoryStock && showInventoryAnalytics.
    @MainActor
    func generateInventoryAnalyticsPDF(
        analytics: InventoryAnalytics,
        branchName: String? = nil
    ) {
        isGeneratingPDF = true
        let period = periodDescription  // uses existing computed var in ReportsViewModel
        guard let url = InventoryAnalyticsPDFExporter.export(
            analytics: analytics,
            periodLabel: period,
            branchName: branchName
        ) else {
            isGeneratingPDF = false
            return
        }
        generatedPDFURL = url
        isGeneratingPDF = false
        showingShareSheet = true
    }
}
