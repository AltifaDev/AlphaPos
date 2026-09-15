// DailySalesPDFDocument.swift
// AlphaPos — A4 Daily Sales supporting accounting report
//
// Bilingual (TH/EN) summary with a paginated delivery appendix rendered with
// UIGraphicsPDFRenderer (top-left UIKit coordinates, correct Thai text
// shaping). Includes the full sales bridge, VAT summary, tender
// reconciliation and signature certification block so the report can be
// attached to official filings.

import Foundation
import UIKit

// MARK: - Snapshot

struct DailySalesReportSnapshot {
    struct TenderLine {
        let method: String
        let amount: Double
        let count: Int
    }

    let reportId: String
    let periodLabel: String
    let computedAt: Date
    let isOfflineMode: Bool
    let storeName: String
    let taxId: String?
    let branchName: String?
    var storeAddress: String? = nil
    var storePhone: String? = nil
    var branchCode: String? = nil

    let grossSales: Double
    let discounts: Double
    let netSalesIncVAT: Double
    let merchandiseSubtotal: Double
    let serviceCharge: Double
    let vatCollected: Double
    let refundVAT: Double
    let netSalesExVAT: Double
    let refunds: Double
    let netRevenueAfterRefunds: Double
    let tips: Double
    let voidCount: Int
    let voidAmount: Double
    let orderCount: Int
    let averageTicket: Double
    let paymentsCollected: Double
    let tenderVariance: Double
    let peakHour: Int?
    let paymentBreakdown: [TenderLine]

    var storefrontNetSales: Double = 0
    var storefrontCash: Double = 0
    var storefrontTransfer: Double = 0
    var storefrontCard: Double = 0
    var deliveryNetSales: Double = 0
    var deliveryPlatformFees: Double = 0
    var deliveryNetReceivables: Double = 0
    var deliveryRefunds: Double = 0
    var deliveryOrderDetails: [DailySalesDeliveryOrderItem] = []
}

// MARK: - Layout constants

private enum PDFLayout {
    static let pageWidth: CGFloat = 595.28   // A4 portrait
    static let pageHeight: CGFloat = 841.89
    static let marginH: CGFloat = 42
    static let marginTop: CGFloat = 40
    static let marginBottom: CGFloat = 40
    static var contentWidth: CGFloat { pageWidth - marginH * 2 }

    static let accent = UIColor(red: 0.176, green: 0.443, blue: 0.973, alpha: 1)   // brand blue
    static let ink = UIColor(red: 0.09, green: 0.11, blue: 0.15, alpha: 1)
    static let inkSecondary = UIColor(red: 0.38, green: 0.42, blue: 0.49, alpha: 1)
    static let rule = UIColor(red: 0.82, green: 0.85, blue: 0.89, alpha: 1)
    static let surface = UIColor(red: 0.955, green: 0.965, blue: 0.98, alpha: 1)
    static let emphasisSurface = UIColor(red: 0.90, green: 0.93, blue: 0.99, alpha: 1)
    static let negative = UIColor(red: 0.80, green: 0.18, blue: 0.22, alpha: 1)

    static func font(_ size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        UIFont.systemFont(ofSize: size, weight: weight)
    }
    static func mono(_ size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        UIFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
    }
}

// MARK: - Exporter

@MainActor
enum DailySalesPDFExporter {

    static func export(snapshot: DailySalesReportSnapshot) -> URL? {
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyyMMdd_HHmm"
        let filename = "Daily_Sales_\(stamp.string(from: snapshot.computedAt)).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: "Daily Sales Summary — \(snapshot.storeName)",
            kCGPDFContextCreator as String: "AlphaPos",
            kCGPDFContextAuthor as String: snapshot.storeName
        ]
        let bounds = CGRect(x: 0, y: 0, width: PDFLayout.pageWidth, height: PDFLayout.pageHeight)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds, format: format)

        do {
            try renderer.writePDF(to: url) { ctx in
                ctx.beginPage()
                drawPage(snapshot: snapshot)
                drawDeliveryDetails(context: ctx, snapshot: snapshot)
            }
            return url
        } catch {
            return nil
        }
    }

    private static func drawDeliveryDetails(context: UIGraphicsPDFRendererContext, snapshot: DailySalesReportSnapshot) {
        // Separate paginated appendix keeps long delivery lists off the summary page.
        for offset in stride(from: 0, to: snapshot.deliveryOrderDetails.count, by: 10) {
            context.beginPage()
            var y = sectionTitle("รายละเอียดเดลิเวอรี / Delivery Order Details", y: PDFLayout.marginTop)
            text(snapshot.reportId + " · " + snapshot.periodLabel, x: PDFLayout.marginH, y: y,
                 font: PDFLayout.font(9), color: PDFLayout.inkSecondary)
            y += 26
            for item in snapshot.deliveryOrderDetails.dropFirst(offset).prefix(10) {
                let identity = item.brandName + " · " + (item.platformOrderNumber ?? "ไม่ระบุเลขเดลิเวอรี / Missing delivery number")
                (identity as NSString).draw(in: CGRect(x: PDFLayout.marginH, y: y, width: PDFLayout.contentWidth, height: 30),
                    withAttributes: [.font: PDFLayout.font(10, weight: .semibold), .foregroundColor: PDFLayout.ink])
                text("POS: " + item.orderNumber, x: PDFLayout.marginH, y: y + 31,
                     font: PDFLayout.font(9), color: PDFLayout.inkSecondary)
                rightText("ยอดขาย / Sales " + currency(item.netSales) + " · คืนเงิน / Refunds " + currency(item.refunds),
                          rightX: PDFLayout.pageWidth - PDFLayout.marginH, y: y + 45,
                          font: PDFLayout.mono(9), color: PDFLayout.ink)
                y += 64
                rule(y: y - 3, weight: 0.5, color: PDFLayout.rule)
            }
            drawFooter(snapshot: snapshot, page: offset / 10 + 2)
        }
    }

    // MARK: - Page composition

    private static func drawPage(snapshot: DailySalesReportSnapshot) {
        var y = PDFLayout.marginTop
        y = drawHeader(y: y, snapshot: snapshot)
        y += 14
        y = drawKPIStrip(y: y, snapshot: snapshot)
        y += 16
        y = drawSalesBridge(y: y, snapshot: snapshot)
        y += 14
        y = drawVATBox(y: y, snapshot: snapshot)
        y += 14
        y = drawTenderSection(y: y, snapshot: snapshot)
        drawCertification(snapshot: snapshot)
        drawFooter(snapshot: snapshot)
    }

    // MARK: Header

    private static func drawHeader(y: CGFloat, snapshot: DailySalesReportSnapshot) -> CGFloat {
        var cursor = y

        // Accent brand bar
        let barRect = CGRect(x: 0, y: 0, width: PDFLayout.pageWidth, height: 6)
        PDFLayout.accent.setFill()
        UIRectFill(barRect)

        // Left: store identity
        text(snapshot.storeName, x: PDFLayout.marginH, y: cursor,
             font: PDFLayout.font(19, weight: .bold), color: PDFLayout.ink)
        cursor += 24

        if let address = snapshot.storeAddress, !address.isEmpty {
            text(address, x: PDFLayout.marginH, y: cursor,
                 font: PDFLayout.font(9), color: PDFLayout.inkSecondary)
            cursor += 13
        }
        var identityLine: [String] = []
        if let taxId = snapshot.taxId, !taxId.isEmpty {
            identityLine.append("เลขประจำตัวผู้เสียภาษี (Tax ID): \(taxId)")
        }
        if let code = snapshot.branchCode, !code.isEmpty {
            identityLine.append("สาขาที่ (Branch No.): \(code)")
        }
        if let phone = snapshot.storePhone, !phone.isEmpty {
            identityLine.append("โทร (Tel): \(phone)")
        }
        if !identityLine.isEmpty {
            text(identityLine.joined(separator: "   ·   "), x: PDFLayout.marginH, y: cursor,
                 font: PDFLayout.font(9), color: PDFLayout.inkSecondary)
            cursor += 13
        }
        if let branch = snapshot.branchName, !branch.isEmpty {
            text("สาขา (Branch): \(branch)", x: PDFLayout.marginH, y: cursor,
                 font: PDFLayout.font(9), color: PDFLayout.inkSecondary)
            cursor += 13
        }

        // Right: document meta block
        let metaX = PDFLayout.pageWidth - PDFLayout.marginH - 210
        var metaY = y
        rightText("รายงานสรุปยอดขายประจำวัน", rightX: PDFLayout.pageWidth - PDFLayout.marginH, y: metaY,
                  font: PDFLayout.font(13, weight: .bold), color: PDFLayout.accent)
        metaY += 17
        rightText("DAILY SALES SUMMARY REPORT", rightX: PDFLayout.pageWidth - PDFLayout.marginH, y: metaY,
                  font: PDFLayout.font(8, weight: .semibold), color: PDFLayout.inkSecondary)
        metaY += 16

        let ts = DateFormatter()
        ts.dateStyle = .medium
        ts.timeStyle = .short
        let metaRows: [(String, String)] = [
            ("เลขที่เอกสาร (Doc No.)", snapshot.reportId),
            ("งวดรายงาน (Period)", snapshot.periodLabel),
            ("จัดทำเมื่อ (Generated)", ts.string(from: snapshot.computedAt)),
            ("แหล่งข้อมูล (Source)", snapshot.isOfflineMode ? "Local (Offline)" : "Local + Cloud Sync")
        ]
        for row in metaRows {
            text(row.0, x: metaX, y: metaY, font: PDFLayout.font(7.5), color: PDFLayout.inkSecondary)
            rightText(row.1, rightX: PDFLayout.pageWidth - PDFLayout.marginH, y: metaY,
                      font: PDFLayout.font(8, weight: .semibold), color: PDFLayout.ink)
            metaY += 12
        }

        let bottom = max(cursor, metaY) + 6
        rule(y: bottom, weight: 1.2, color: PDFLayout.accent)
        return bottom + 4
    }

    // MARK: KPI strip

    private static func drawKPIStrip(y: CGFloat, snapshot: DailySalesReportSnapshot) -> CGFloat {
        let items: [(String, String, String)] = [
            ("ยอดขายสุทธิ (รวม VAT)", "Net Sales (inc. VAT)", currency(snapshot.netSalesIncVAT)),
            ("รายได้ทางบัญชี ไม่รวม VAT", "Accounting Revenue ex. VAT", currency(snapshot.netSalesExVAT)),
            ("จำนวนบิลขาย", "Total Orders", "\(snapshot.orderCount)"),
            ("ยอดเฉลี่ยต่อบิล", "Avg. Ticket", currency(snapshot.averageTicket))
        ]
        let gap: CGFloat = 8
        let cardW = (PDFLayout.contentWidth - gap * 3) / 4
        let cardH: CGFloat = 56
        for (idx, item) in items.enumerated() {
            let x = PDFLayout.marginH + CGFloat(idx) * (cardW + gap)
            let box = CGRect(x: x, y: y, width: cardW, height: cardH)
            let path = UIBezierPath(roundedRect: box, cornerRadius: 6)
            PDFLayout.surface.setFill()
            path.fill()
            PDFLayout.rule.setStroke()
            path.lineWidth = 0.6
            path.stroke()
            text(item.0, x: x + 9, y: y + 8, font: PDFLayout.font(7.5, weight: .semibold), color: PDFLayout.inkSecondary)
            text(item.1, x: x + 9, y: y + 18, font: PDFLayout.font(6.5), color: PDFLayout.inkSecondary)
            text(item.2, x: x + 9, y: y + 32, font: PDFLayout.mono(12.5, weight: .bold), color: PDFLayout.ink)
        }
        return y + cardH
    }

    // MARK: Sales bridge table

    private static func drawSalesBridge(y: CGFloat, snapshot: DailySalesReportSnapshot) -> CGFloat {
        var cursor = sectionTitle("สรุปยอดขายแยกหน้าร้าน / เดลิเวอรี และภาษี (Sales & Settlement Breakdown — Accounting Basis)", y: y)

        let rows: [(String, Double, Bool, Bool)] = [
            // (label, amount, isEmphasis, isNegative)
            ("1. ยอดขายหน้าร้านรับเงินจริง (In-Store Net Sales)", snapshot.storefrontNetSales, true, false),
            ("     • เงินสดเข้าลิ้นชัก (Cash in Drawer)", snapshot.storefrontCash, false, false),
            ("     • เงินโอน / QR PromptPay", snapshot.storefrontTransfer, false, false),
            ("     • บัตรเครดิต EDC", snapshot.storefrontCard, false, false),
            ("2. ยอดขายเดลิเวอรี / ลูกหนี้การค้า (Delivery Gross Sales)", snapshot.deliveryNetSales, true, false),
            ("     • คืนเงินเดลิเวอรีในงวด (Delivery Refunds)", -snapshot.deliveryRefunds, false, true),
            ("     • หัก ค่า GP & ค่าธรรมเนียมแอป (Platform Fees)", -snapshot.deliveryPlatformFees, false, true),
            ("     • ยอดคาดรับของงวด ก่อนหักยอดโอนแล้ว (Estimated Payout)", snapshot.deliveryNetReceivables, false, false),
            ("3. ยอดขายรวมทั้งสิ้นก่อนส่วนลด (Total Gross Sales)", snapshot.grossSales, true, false),
            ("     หัก ส่วนลดรวม (Less: Total Discounts)", -snapshot.discounts, false, true),
            ("     ยอดขายสุทธิรวม VAT (Net Sales inc. VAT)", snapshot.netSalesIncVAT, true, false),
            ("     หัก คืนเงิน (Less: Refunds)", -snapshot.refunds, false, true),
            ("     หัก ภาษีขายสุทธิ (Less: Net Output VAT)", -snapshot.vatCollected, false, true),
            ("     รายได้ทางบัญชีไม่รวม VAT (Revenue ex. VAT)", snapshot.netSalesExVAT, true, false)
        ]

        let rowH: CGFloat = 15.5
        for (idx, row) in rows.enumerated() {
            let rect = CGRect(x: PDFLayout.marginH, y: cursor, width: PDFLayout.contentWidth, height: rowH)
            if row.2 {
                PDFLayout.emphasisSurface.setFill()
                UIRectFill(rect)
            } else if idx % 2 == 1 {
                PDFLayout.surface.setFill()
                UIRectFill(rect)
            }
            let labelFont = row.2 ? PDFLayout.font(9.5, weight: .bold) : PDFLayout.font(9)
            let amountFont = row.2 ? PDFLayout.mono(9.5, weight: .bold) : PDFLayout.mono(9)
            let amountColor = row.3 ? PDFLayout.negative : PDFLayout.ink
            text(row.0, x: PDFLayout.marginH + 8, y: cursor + 3, font: labelFont, color: PDFLayout.ink)
            rightText(currency(row.1), rightX: PDFLayout.marginH + PDFLayout.contentWidth - 8, y: cursor + 3,
                      font: amountFont, color: amountColor)
            cursor += rowH
        }
        text("* เอกสารประกอบการบันทึกบัญชีรายได้และภาษีขาย (Supporting document for accounting & tax; not a direct DBD filing statement)",
             x: PDFLayout.marginH + 4, y: cursor + 2, font: PDFLayout.font(6.8), color: PDFLayout.inkSecondary)
        cursor += 12
        rule(y: cursor, weight: 0.8, color: PDFLayout.rule)
        return cursor
    }

    // MARK: VAT summary box (for tax filing)

    private static func drawVATBox(y: CGFloat, snapshot: DailySalesReportSnapshot) -> CGFloat {
        var cursor = sectionTitle("สรุปภาษีมูลค่าเพิ่ม (VAT Summary for Tax Filing)", y: y)

        let boxH: CGFloat = 44
        let box = CGRect(x: PDFLayout.marginH, y: cursor, width: PDFLayout.contentWidth, height: boxH)
        let path = UIBezierPath(roundedRect: box, cornerRadius: 6)
        PDFLayout.surface.setFill()
        path.fill()
        PDFLayout.accent.setStroke()
        path.lineWidth = 0.8
        path.stroke()

        let cols: [(String, String, String)] = [
            ("ยอดหลังคืนเงิน รวม VAT", "Net Sales inc. VAT", currency(snapshot.netRevenueAfterRefunds)),
            ("รายได้ ไม่รวม VAT", "Revenue ex. VAT", currency(snapshot.netSalesExVAT)),
            ("ภาษีขายสุทธิ", "Net Output VAT", currency(snapshot.vatCollected))
        ]
        let colW = PDFLayout.contentWidth / 3
        for (idx, col) in cols.enumerated() {
            let x = PDFLayout.marginH + CGFloat(idx) * colW + 12
            text(col.0, x: x, y: cursor + 7, font: PDFLayout.font(8, weight: .semibold), color: PDFLayout.inkSecondary)
            text(col.1, x: x, y: cursor + 17, font: PDFLayout.font(6.5), color: PDFLayout.inkSecondary)
            text(col.2, x: x, y: cursor + 27, font: PDFLayout.mono(11, weight: .bold), color: PDFLayout.accent)
        }
        cursor += boxH
        return cursor
    }

    // MARK: Tender reconciliation + breakdown

    private static func drawTenderSection(y: CGFloat, snapshot: DailySalesReportSnapshot) -> CGFloat {
        var cursor = sectionTitle("การรับชำระเงินและกระทบยอด (Tender Reconciliation)", y: y)

        // Column headers
        let rowH: CGFloat = 15
        let headerRect = CGRect(x: PDFLayout.marginH, y: cursor, width: PDFLayout.contentWidth, height: rowH)
        PDFLayout.emphasisSurface.setFill()
        UIRectFill(headerRect)
        text("ช่องทางชำระเงิน (Method)", x: PDFLayout.marginH + 8, y: cursor + 3,
             font: PDFLayout.font(8, weight: .bold), color: PDFLayout.ink)
        rightText("จำนวน (Count)", rightX: PDFLayout.marginH + PDFLayout.contentWidth - 190, y: cursor + 3,
                  font: PDFLayout.font(8, weight: .bold), color: PDFLayout.ink)
        rightText("จำนวนเงิน (Amount)", rightX: PDFLayout.marginH + PDFLayout.contentWidth - 78, y: cursor + 3,
                  font: PDFLayout.font(8, weight: .bold), color: PDFLayout.ink)
        rightText("สัดส่วน (%)", rightX: PDFLayout.marginH + PDFLayout.contentWidth - 8, y: cursor + 3,
                  font: PDFLayout.font(8, weight: .bold), color: PDFLayout.ink)
        cursor += rowH

        if snapshot.paymentBreakdown.isEmpty {
            text("ไม่มีรายการรับชำระเงินในงวดนี้ (No completed payments in this period)",
                 x: PDFLayout.marginH + 8, y: cursor + 3, font: PDFLayout.font(8.5), color: PDFLayout.inkSecondary)
            cursor += rowH
        } else {
            let total = snapshot.paymentBreakdown.reduce(0.0) { $0 + $1.amount }
            for (idx, line) in snapshot.paymentBreakdown.enumerated() {
                if idx % 2 == 1 {
                    PDFLayout.surface.setFill()
                    UIRectFill(CGRect(x: PDFLayout.marginH, y: cursor, width: PDFLayout.contentWidth, height: rowH))
                }
                let pct = total > 0 ? line.amount / total * 100 : 0
                text(displayMethod(line.method), x: PDFLayout.marginH + 8, y: cursor + 3,
                     font: PDFLayout.font(9), color: PDFLayout.ink)
                rightText("\(line.count)", rightX: PDFLayout.marginH + PDFLayout.contentWidth - 190, y: cursor + 3,
                          font: PDFLayout.mono(9), color: PDFLayout.ink)
                rightText(currency(line.amount), rightX: PDFLayout.marginH + PDFLayout.contentWidth - 78, y: cursor + 3,
                          font: PDFLayout.mono(9), color: PDFLayout.ink)
                rightText(String(format: "%.1f%%", pct), rightX: PDFLayout.marginH + PDFLayout.contentWidth - 8, y: cursor + 3,
                          font: PDFLayout.mono(9), color: PDFLayout.inkSecondary)
                cursor += rowH
            }
        }

        rule(y: cursor, weight: 0.8, color: PDFLayout.rule)
        cursor += 4

        // Reconciliation lines
        let reconRows: [(String, String, Bool)] = [
            ("เงินรับชำระรวม (Payments Collected)", currency(snapshot.paymentsCollected), false),
            ("ทิปที่รับ (Tips Collected)", currency(snapshot.tips), false),
            ("ผลต่างกระทบยอด (Variance: Payments − Net Sales)", currency(snapshot.tenderVariance),
             abs(snapshot.tenderVariance) > 0.009),
            ("ช่วงเวลาขายสูงสุด (Peak Hour)", snapshot.peakHour.map { String(format: "%02d:00", $0) } ?? "—", false)
        ]
        for row in reconRows {
            text(row.0, x: PDFLayout.marginH + 8, y: cursor + 2, font: PDFLayout.font(8.5), color: PDFLayout.ink)
            rightText(row.1, rightX: PDFLayout.marginH + PDFLayout.contentWidth - 8, y: cursor + 2,
                      font: PDFLayout.mono(8.5, weight: row.2 ? .bold : .regular),
                      color: row.2 ? PDFLayout.negative : PDFLayout.ink)
            cursor += 13
        }
        return cursor
    }

    // MARK: Certification & signatures

    private static func drawCertification(snapshot: DailySalesReportSnapshot) {
        let blockTop = PDFLayout.pageHeight - PDFLayout.marginBottom - 118

        rule(y: blockTop, weight: 0.8, color: PDFLayout.rule)
        text("ขอรับรองว่ารายงานฉบับนี้จัดทำขึ้นจากข้อมูลการขายจริงในระบบ ณ เวลาที่ระบุไว้ข้างต้น",
             x: PDFLayout.marginH, y: blockTop + 8, font: PDFLayout.font(8.5), color: PDFLayout.ink)
        text("We hereby certify that this report is generated from actual sales records in the system as of the time stated above.",
             x: PDFLayout.marginH, y: blockTop + 20, font: PDFLayout.font(7), color: PDFLayout.inkSecondary)

        let signatures: [(String, String)] = [
            ("ผู้จัดทำ", "Prepared by"),
            ("ผู้ตรวจสอบ", "Checked by"),
            ("ผู้อนุมัติ", "Approved by")
        ]
        let gap: CGFloat = 24
        let colW = (PDFLayout.contentWidth - gap * 2) / 3
        let sigTop = blockTop + 42
        for (idx, sig) in signatures.enumerated() {
            let x = PDFLayout.marginH + CGFloat(idx) * (colW + gap)
            // Signature line
            PDFLayout.ink.setStroke()
            let linePath = UIBezierPath()
            linePath.move(to: CGPoint(x: x, y: sigTop + 26))
            linePath.addLine(to: CGPoint(x: x + colW, y: sigTop + 26))
            linePath.lineWidth = 0.6
            linePath.stroke()
            text("ลงชื่อ (Signature)", x: x, y: sigTop + 30, font: PDFLayout.font(6.5), color: PDFLayout.inkSecondary)
            text("\(sig.0) (\(sig.1))", x: x, y: sigTop + 42, font: PDFLayout.font(8, weight: .semibold), color: PDFLayout.ink)
            text("วันที่ (Date): ____ / ____ / ______", x: x, y: sigTop + 54, font: PDFLayout.font(7), color: PDFLayout.inkSecondary)
        }
    }

    // MARK: Footer

    private static func drawFooter(snapshot: DailySalesReportSnapshot, page: Int = 1) {
        let y = PDFLayout.pageHeight - PDFLayout.marginBottom + 14
        rule(y: y - 6, weight: 0.5, color: PDFLayout.rule)
        text("เอกสารออกโดยระบบ AlphaPos POS · อ้างอิง Z-Report สำหรับการปิดลิ้นชักเงินสด",
             x: PDFLayout.marginH, y: y, font: PDFLayout.font(6.5), color: PDFLayout.inkSecondary)
        rightText("หน้า \(page)/\(1 + (snapshot.deliveryOrderDetails.count + 9) / 10) · \(snapshot.reportId)", rightX: PDFLayout.pageWidth - PDFLayout.marginH, y: y,
                  font: PDFLayout.font(6.5), color: PDFLayout.inkSecondary)
    }

    // MARK: - Drawing helpers (UIKit top-left coordinates)

    private static func sectionTitle(_ title: String, y: CGFloat) -> CGFloat {
        // Accent tick + title
        PDFLayout.accent.setFill()
        UIRectFill(CGRect(x: PDFLayout.marginH, y: y + 2, width: 3, height: 10))
        text(title, x: PDFLayout.marginH + 9, y: y, font: PDFLayout.font(10.5, weight: .bold), color: PDFLayout.ink)
        return y + 18
    }

    private static func text(_ string: String, x: CGFloat, y: CGFloat, font: UIFont, color: UIColor) {
        (string as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: [.font: font, .foregroundColor: color])
    }

    private static func rightText(_ string: String, rightX: CGFloat, y: CGFloat, font: UIFont, color: UIColor) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = (string as NSString).size(withAttributes: attrs)
        (string as NSString).draw(at: CGPoint(x: rightX - size.width, y: y), withAttributes: attrs)
    }

    private static func rule(y: CGFloat, weight: CGFloat, color: UIColor) {
        color.setFill()
        UIRectFill(CGRect(x: PDFLayout.marginH, y: y, width: PDFLayout.contentWidth, height: weight))
    }

    private static func currency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "THB"
        f.currencySymbol = "฿"
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: value)) ?? String(format: "฿%.2f", value)
    }

    private static func displayMethod(_ method: String) -> String {
        switch method {
        case "cash": return "เงินสด (Cash)"
        case "credit_card": return "บัตรเครดิต (Credit Card)"
        case "qr_promptpay": return "QR พร้อมเพย์ (PromptPay)"
        case "true_money": return "TrueMoney Wallet"
        default: return method.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}
