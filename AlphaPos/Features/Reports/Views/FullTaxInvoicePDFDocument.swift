// FullTaxInvoicePDFDocument.swift
// AlphaPos — Formal A4 Full Tax Invoice / Receipt (ใบเสร็จรับเงิน/ใบกำกับภาษีเต็มรูปแบบ)
//
// Compliant with Thai Revenue Code Section 86/4 & RD POS e-Tax specifications.
// Rendered with UIGraphicsPDFRenderer (A4 Portrait, bilingual TH/EN, Thai text shaping).

import Foundation
import UIKit

// MARK: - Models

public struct FullTaxInvoiceBuyerInfo: Codable, Sendable {
    public var name: String
    public var taxId: String
    public var branchType: String  // "head_office" or "branch"
    public var branchCode: String  // "00000" or custom
    public var address: String
    public var phone: String?
    public var email: String?

    public init(
        name: String = "",
        taxId: String = "",
        branchType: String = "head_office",
        branchCode: String = "00000",
        address: String = "",
        phone: String? = nil,
        email: String? = nil
    ) {
        self.name = name
        self.taxId = taxId
        self.branchType = branchType
        self.branchCode = branchCode
        self.address = address
        self.phone = phone
        self.email = email
    }

    public var branchDisplay: String {
        if branchType == "head_office" || branchCode == "00000" || branchCode.isEmpty {
            return "สำนักงานใหญ่ (Head Office)"
        } else {
            return "สาขาที่ \(branchCode) (Branch #\(branchCode))"
        }
    }

    public var formattedTaxId: String {
        let d = taxId.filter(\.isNumber)
        guard d.count == 13 else { return taxId }
        let chars = Array(d)
        return "\(chars[0])-\(String(chars[1...4]))-\(String(chars[5...9]))-\(String(chars[10...11]))-\(chars[12])"
    }
}

public struct FullTaxInvoiceItem: Identifiable, Sendable {
    public let id: UUID
    public let index: Int
    public let name: String
    public let quantity: Int
    public let unitPrice: Double
    public let discount: Double
    public let amount: Double
    public let isTaxable: Bool

    public init(
        id: UUID = UUID(),
        index: Int,
        name: String,
        quantity: Int,
        unitPrice: Double,
        discount: Double = 0.0,
        amount: Double,
        isTaxable: Bool = true
    ) {
        self.id = id
        self.index = index
        self.name = name
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.discount = discount
        self.amount = amount
        self.isTaxable = isTaxable
    }
}

public struct FullTaxInvoiceSnapshot: Sendable {
    public let invoiceNumber: String
    public let invoiceDate: Date
    public let refOrderNumber: String
    public let refReceiptNumber: String?

    // Seller
    public let sellerName: String
    public let sellerTaxId: String
    public let sellerBranchCode: String
    public let sellerAddress: String
    public let sellerPhone: String

    // Buyer
    public let buyer: FullTaxInvoiceBuyerInfo

    // Financials
    public let items: [FullTaxInvoiceItem]
    public let grossSubtotal: Double
    public let discount: Double
    public let serviceCharge: Double
    public let taxableBase: Double
    public let vatAmount: Double
    public let nonVatAmount: Double
    public let grandTotal: Double
    public let thaiBahtText: String

    public let cashierName: String
    public let paymentMethod: String
    public let isCopy: Bool

    public init(
        invoiceNumber: String,
        invoiceDate: Date = Date(),
        refOrderNumber: String,
        refReceiptNumber: String?,
        sellerName: String,
        sellerTaxId: String,
        sellerBranchCode: String,
        sellerAddress: String,
        sellerPhone: String,
        buyer: FullTaxInvoiceBuyerInfo,
        items: [FullTaxInvoiceItem],
        grossSubtotal: Double,
        discount: Double,
        serviceCharge: Double,
        taxableBase: Double,
        vatAmount: Double,
        nonVatAmount: Double,
        grandTotal: Double,
        thaiBahtText: String,
        cashierName: String,
        paymentMethod: String,
        isCopy: Bool = false
    ) {
        self.invoiceNumber = invoiceNumber
        self.invoiceDate = invoiceDate
        self.refOrderNumber = refOrderNumber
        self.refReceiptNumber = refReceiptNumber
        self.sellerName = sellerName
        self.sellerTaxId = sellerTaxId
        self.sellerBranchCode = sellerBranchCode
        self.sellerAddress = sellerAddress
        self.sellerPhone = sellerPhone
        self.buyer = buyer
        self.items = items
        self.grossSubtotal = grossSubtotal
        self.discount = discount
        self.serviceCharge = serviceCharge
        self.taxableBase = taxableBase
        self.vatAmount = vatAmount
        self.nonVatAmount = nonVatAmount
        self.grandTotal = grandTotal
        self.thaiBahtText = thaiBahtText
        self.cashierName = cashierName
        self.paymentMethod = paymentMethod
        self.isCopy = isCopy
    }

    public var formattedSellerTaxId: String {
        let d = sellerTaxId.filter(\.isNumber)
        guard d.count == 13 else { return sellerTaxId }
        let chars = Array(d)
        return "\(chars[0])-\(String(chars[1...4]))-\(String(chars[5...9]))-\(String(chars[10...11]))-\(chars[12])"
    }

    public var sellerBranchDisplay: String {
        if sellerBranchCode == "00000" || sellerBranchCode.isEmpty {
            return "สำนักงานใหญ่ (Head Office)"
        } else {
            return "สาขาที่ \(sellerBranchCode) (Branch #\(sellerBranchCode))"
        }
    }
}

// MARK: - PDF Layout Engine

public final class FullTaxInvoicePDFGenerator {
    private enum Layout {
        static let pageWidth: CGFloat = 595.28   // A4
        static let pageHeight: CGFloat = 841.89
        static let marginH: CGFloat = 36
        static let marginTop: CGFloat = 32
        static let marginBottom: CGFloat = 32
        static let contentWidth = pageWidth - (marginH * 2)
    }

    public static func renderPDF(snapshot: FullTaxInvoiceSnapshot) -> Data {
        let pdfMeta: [CFString: Any] = [
            kCGPDFContextTitle: "Tax Invoice - \(snapshot.invoiceNumber)",
            kCGPDFContextAuthor: snapshot.sellerName,
            kCGPDFContextCreator: "AlphaPos iPad Fiscal Engine"
        ]

        let pageBounds = CGRect(x: 0, y: 0, width: Layout.pageWidth, height: Layout.pageHeight)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = pdfMeta as [String: Any]
        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds, format: format)

        return renderer.pdfData { ctx in
            ctx.beginPage()
            let cg = ctx.cgContext

            // 1. Header Banner & Title
            var cursorY = drawHeader(cg: cg, snapshot: snapshot)

            // 2. Seller & Buyer Information Box
            cursorY = drawPartyInfoBox(cg: cg, snapshot: snapshot, startY: cursorY)

            // 3. Itemized Table
            cursorY = drawItemizedTable(cg: cg, snapshot: snapshot, startY: cursorY)

            // 4. Financial Summary & Baht Text
            cursorY = drawFinancialSummary(cg: cg, snapshot: snapshot, startY: cursorY)

            // 5. Signatures & Footer
            drawSignaturesAndFooter(cg: cg, snapshot: snapshot, atY: cursorY)
        }
    }

    // MARK: - Header
    private static func drawHeader(cg: CGContext, snapshot: FullTaxInvoiceSnapshot) -> CGFloat {
        var y = Layout.marginTop

        // Original vs Copy badge
        let docCopyTitle = snapshot.isCopy ? "สำเนา / COPY" : "ต้นฉบับ / ORIGINAL"
        let copyRect = CGRect(x: Layout.pageWidth - Layout.marginH - 120, y: y, width: 120, height: 20)
        let copyPath = UIBezierPath(roundedRect: copyRect, cornerRadius: 4)
        (snapshot.isCopy ? UIColor(red: 0.85, green: 0.35, blue: 0.35, alpha: 0.15) : UIColor(red: 0.15, green: 0.45, blue: 0.85, alpha: 0.15)).setFill()
        copyPath.fill()

        let copyAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .bold),
            .foregroundColor: snapshot.isCopy ? UIColor(red: 0.75, green: 0.2, blue: 0.2, alpha: 1.0) : UIColor(red: 0.1, green: 0.35, blue: 0.75, alpha: 1.0)
        ]
        let copyStr = NSAttributedString(string: docCopyTitle, attributes: copyAttrs)
        let copySize = copyStr.size()
        copyStr.draw(at: CGPoint(x: copyRect.midX - copySize.width / 2, y: copyRect.midY - copySize.height / 2))

        // Main Document Title
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 18),
            .foregroundColor: UIColor.black
        ]
        let subTitleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: UIColor.darkGray
        ]

        let titleStr = "ใบเสร็จรับเงิน / ใบกำกับภาษี"
        let enTitleStr = "RECEIPT / TAX INVOICE"
        (titleStr as NSString).draw(at: CGPoint(x: Layout.marginH, y: y), withAttributes: titleAttrs)
        (enTitleStr as NSString).draw(at: CGPoint(x: Layout.marginH, y: y + 22), withAttributes: subTitleAttrs)

        y += 44

        // Top horizontal dividing bar
        cg.setStrokeColor(UIColor(white: 0.8, alpha: 1.0).cgColor)
        cg.setLineWidth(1)
        cg.move(to: CGPoint(x: Layout.marginH, y: y))
        cg.addLine(to: CGPoint(x: Layout.pageWidth - Layout.marginH, y: y))
        cg.strokePath()

        return y + 8
    }

    // MARK: - Seller & Buyer Information Box
    private static func drawPartyInfoBox(cg: CGContext, snapshot: FullTaxInvoiceSnapshot, startY: CGFloat) -> CGFloat {
        let boxWidth = Layout.contentWidth
        let boxHeight: CGFloat = 110
        let boxRect = CGRect(x: Layout.marginH, y: startY, width: boxWidth, height: boxHeight)

        // Draw background box
        let bgPath = UIBezierPath(roundedRect: boxRect, cornerRadius: 6)
        UIColor(white: 0.98, alpha: 1.0).setFill()
        bgPath.fill()
        cg.setStrokeColor(UIColor(white: 0.85, alpha: 1.0).cgColor)
        cg.setLineWidth(1)
        bgPath.stroke()

        // Vertical divider
        let midX = Layout.marginH + (boxWidth * 0.52)
        cg.move(to: CGPoint(x: midX, y: startY))
        cg.addLine(to: CGPoint(x: midX, y: startY + boxHeight))
        cg.strokePath()

        let labelFont = UIFont.boldSystemFont(ofSize: 9)
        let bodyFont = UIFont.systemFont(ofSize: 8.5)
        let bodyBoldFont = UIFont.boldSystemFont(ofSize: 8.5)
        let labelColor = UIColor(white: 0.35, alpha: 1.0)
        let valueColor = UIColor.black

        // --- Left: Seller Info ---
        var curY = startY + 8
        let leftX = Layout.marginH + 10
        let leftWidth = midX - leftX - 10

        ("ข้อมูลผู้ขาย (SELLER)" as NSString).draw(at: CGPoint(x: leftX, y: curY), withAttributes: [.font: labelFont, .foregroundColor: UIColor(red: 0.1, green: 0.4, blue: 0.8, alpha: 1.0)])
        curY += 14

        (snapshot.sellerName as NSString).draw(in: CGRect(x: leftX, y: curY, width: leftWidth, height: 13), withAttributes: [.font: bodyBoldFont, .foregroundColor: valueColor])
        curY += 13

        let sellerTaxLine = "เลขประจำตัวผู้เสียภาษี: \(snapshot.formattedSellerTaxId)  (\(snapshot.sellerBranchDisplay))"
        (sellerTaxLine as NSString).draw(in: CGRect(x: leftX, y: curY, width: leftWidth, height: 12), withAttributes: [.font: bodyFont, .foregroundColor: valueColor])
        curY += 12

        if !snapshot.sellerAddress.isEmpty {
            (snapshot.sellerAddress as NSString).draw(in: CGRect(x: leftX, y: curY, width: leftWidth, height: 24), withAttributes: [.font: bodyFont, .foregroundColor: labelColor])
            curY += 24
        }
        if !snapshot.sellerPhone.isEmpty {
            ("โทร: \(snapshot.sellerPhone)" as NSString).draw(at: CGPoint(x: leftX, y: curY), withAttributes: [.font: bodyFont, .foregroundColor: labelColor])
        }

        // --- Right: Buyer Info & Invoice Metadata ---
        curY = startY + 8
        let rightX = midX + 10
        let rightWidth = (Layout.pageWidth - Layout.marginH) - rightX - 10

        // Invoice No & Date block
        let invNoText = "เลขที่ (Inv No): \(snapshot.invoiceNumber)"
        let dateText = "วันที่ (Date): \(snapshot.invoiceDate.formatted(date: .numeric, time: .shortened))"
        (invNoText as NSString).draw(at: CGPoint(x: rightX, y: curY), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 9.5), .foregroundColor: UIColor.black])
        curY += 13
        (dateText as NSString).draw(at: CGPoint(x: rightX, y: curY), withAttributes: [.font: bodyFont, .foregroundColor: labelColor])
        curY += 12

        // Buyer Info
        ("ข้อมูลผู้ซื้อ (CUSTOMER / BUYER)" as NSString).draw(at: CGPoint(x: rightX, y: curY), withAttributes: [.font: labelFont, .foregroundColor: UIColor(red: 0.1, green: 0.4, blue: 0.8, alpha: 1.0)])
        curY += 13

        let buyerName = snapshot.buyer.name.isEmpty ? "ลูกค้าทั่วไป (Cash Customer)" : snapshot.buyer.name
        (buyerName as NSString).draw(in: CGRect(x: rightX, y: curY, width: rightWidth, height: 13), withAttributes: [.font: bodyBoldFont, .foregroundColor: valueColor])
        curY += 13

        if !snapshot.buyer.taxId.isEmpty {
            let buyerTaxLine = "เลขประจำตัวผู้เสียภาษี: \(snapshot.buyer.formattedTaxId)  (\(snapshot.buyer.branchDisplay))"
            (buyerTaxLine as NSString).draw(in: CGRect(x: rightX, y: curY, width: rightWidth, height: 12), withAttributes: [.font: bodyFont, .foregroundColor: valueColor])
            curY += 12
        }

        if !snapshot.buyer.address.isEmpty {
            (snapshot.buyer.address as NSString).draw(in: CGRect(x: rightX, y: curY, width: rightWidth, height: 24), withAttributes: [.font: bodyFont, .foregroundColor: labelColor])
            curY += 24
        }

        return startY + boxHeight + 10
    }

    // MARK: - Itemized Table
    private static func drawItemizedTable(cg: CGContext, snapshot: FullTaxInvoiceSnapshot, startY: CGFloat) -> CGFloat {
        var y = startY
        let colX = [
            Layout.marginH,                        // #
            Layout.marginH + 28,                   // Description
            Layout.marginH + 310,                  // Qty
            Layout.marginH + 360,                  // Unit Price
            Layout.marginH + 430,                  // Discount
            Layout.pageWidth - Layout.marginH      // Total (Right align)
        ]

        let tableHeaderHeight: CGFloat = 22
        let tableHeaderRect = CGRect(x: Layout.marginH, y: y, width: Layout.contentWidth, height: tableHeaderHeight)

        // Header Background
        UIColor(red: 0.15, green: 0.35, blue: 0.65, alpha: 1.0).setFill()
        UIBezierPath(roundedRect: tableHeaderRect, cornerRadius: 4).fill()

        let thAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 8.5),
            .foregroundColor: UIColor.white
        ]

        ("#" as NSString).draw(at: CGPoint(x: colX[0] + 6, y: y + 5), withAttributes: thAttrs)
        ("รายการ (Description)" as NSString).draw(at: CGPoint(x: colX[1], y: y + 5), withAttributes: thAttrs)
        ("จำนวน" as NSString).draw(at: CGPoint(x: colX[2], y: y + 5), withAttributes: thAttrs)
        ("หน่วยละ" as NSString).draw(at: CGPoint(x: colX[3], y: y + 5), withAttributes: thAttrs)
        ("ส่วนลด" as NSString).draw(at: CGPoint(x: colX[4], y: y + 5), withAttributes: thAttrs)
        drawRightText("จำนวนเงิน (THB)", rightX: colX[5] - 6, y: y + 5, attrs: thAttrs)

        y += tableHeaderHeight + 4

        // Item Rows
        let rowFont = UIFont.systemFont(ofSize: 8.5)
        let rowAttrs: [NSAttributedString.Key: Any] = [.font: rowFont, .foregroundColor: UIColor.black]
        let rowHeight: CGFloat = 18

        for (idx, item) in snapshot.items.prefix(18).enumerated() {
            let rowY = y + (CGFloat(idx) * rowHeight)

            // Alternating zebra striping
            if idx % 2 == 1 {
                let zebraRect = CGRect(x: Layout.marginH, y: rowY - 2, width: Layout.contentWidth, height: rowHeight)
                UIColor(white: 0.96, alpha: 1.0).setFill()
                UIRectFill(zebraRect)
            }

            ("\(idx + 1)" as NSString).draw(at: CGPoint(x: colX[0] + 6, y: rowY), withAttributes: rowAttrs)
            (item.name as NSString).draw(in: CGRect(x: colX[1], y: rowY, width: 270, height: rowHeight), withAttributes: rowAttrs)
            ("\(item.quantity)" as NSString).draw(at: CGPoint(x: colX[2] + 4, y: rowY), withAttributes: rowAttrs)
            (formatCurrency(item.unitPrice) as NSString).draw(at: CGPoint(x: colX[3], y: rowY), withAttributes: rowAttrs)

            let discStr = item.discount > 0 ? formatCurrency(item.discount) : "-"
            (discStr as NSString).draw(at: CGPoint(x: colX[4], y: rowY), withAttributes: rowAttrs)

            drawRightText(formatCurrency(item.amount), rightX: colX[5] - 6, y: rowY, attrs: rowAttrs)
        }

        let totalRowsHeight = CGFloat(min(snapshot.items.count, 18)) * rowHeight
        y += max(totalRowsHeight, 60) + 6

        // Bottom table line
        cg.setStrokeColor(UIColor(white: 0.8, alpha: 1.0).cgColor)
        cg.setLineWidth(1)
        cg.move(to: CGPoint(x: Layout.marginH, y: y))
        cg.addLine(to: CGPoint(x: Layout.pageWidth - Layout.marginH, y: y))
        cg.strokePath()

        return y + 8
    }

    // MARK: - Financial Summary & Baht Text
    private static func drawFinancialSummary(cg: CGContext, snapshot: FullTaxInvoiceSnapshot, startY: CGFloat) -> CGFloat {
        var y = startY

        let summaryWidth: CGFloat = 220
        let summaryLeft = Layout.pageWidth - Layout.marginH - summaryWidth
        let leftBoxWidth = summaryLeft - Layout.marginH - 12

        // --- Left: Thai Baht Text & Notes Box ---
        let bahtBoxRect = CGRect(x: Layout.marginH, y: y, width: leftBoxWidth, height: 90)
        let bahtBoxPath = UIBezierPath(roundedRect: bahtBoxRect, cornerRadius: 4)
        UIColor(white: 0.97, alpha: 1.0).setFill()
        bahtBoxPath.fill()
        cg.setStrokeColor(UIColor(white: 0.85, alpha: 1.0).cgColor)
        bahtBoxPath.stroke()

        let bahtTitleAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 8.5), .foregroundColor: UIColor.darkGray]
        let bahtValAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 9.5), .foregroundColor: UIColor(red: 0.1, green: 0.35, blue: 0.75, alpha: 1.0)]

        ("จำนวนเงินตัวอักษร (Amount in Thai Baht):" as NSString).draw(at: CGPoint(x: Layout.marginH + 8, y: y + 8), withAttributes: bahtTitleAttrs)
        ("(\(snapshot.thaiBahtText))" as NSString).draw(in: CGRect(x: Layout.marginH + 8, y: y + 24, width: leftBoxWidth - 16, height: 32), withAttributes: bahtValAttrs)

        let refText = "อ้างอิงบิล/ใบเสร็จ: \(snapshot.refReceiptNumber ?? snapshot.refOrderNumber)  •  แคชเชียร์: \(snapshot.cashierName)"
        (refText as NSString).draw(at: CGPoint(x: Layout.marginH + 8, y: y + 66), withAttributes: [.font: UIFont.systemFont(ofSize: 8), .foregroundColor: UIColor.gray])

        // --- Right: Calculation Lines ---
        var curSumY = y
        let labelAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 8.5), .foregroundColor: UIColor.black]
        let boldLabelAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 10), .foregroundColor: UIColor.black]

        func drawSummaryRow(_ title: String, _ value: String, isBold: Bool = false) {
            let attrs = isBold ? boldLabelAttrs : labelAttrs
            (title as NSString).draw(at: CGPoint(x: summaryLeft, y: curSumY), withAttributes: attrs)
            drawRightText(value, rightX: Layout.pageWidth - Layout.marginH, y: curSumY, attrs: attrs)
            curSumY += 14
        }

        drawSummaryRow("รวมมูลค่าสินค้า (Subtotal)", formatCurrency(snapshot.grossSubtotal))
        if snapshot.discount > 0 {
            drawSummaryRow("หัก ส่วนลด (Discount)", "-\(formatCurrency(snapshot.discount))")
        }
        if snapshot.serviceCharge > 0 {
            drawSummaryRow("ค่าบริการ (Service Charge)", formatCurrency(snapshot.serviceCharge))
        }
        drawSummaryRow("มูลค่าก่อนภาษี (Taxable Base)", formatCurrency(snapshot.taxableBase))
        drawSummaryRow("ภาษีมูลค่าเพิ่ม 7% (VAT 7%)", formatCurrency(snapshot.vatAmount))

        if snapshot.nonVatAmount > 0 {
            drawSummaryRow("สินค้ายกเว้นภาษี (Non-VAT)", formatCurrency(snapshot.nonVatAmount))
        }

        // Grand Total Box
        curSumY += 2
        let grandTotalRect = CGRect(x: summaryLeft - 6, y: curSumY - 2, width: summaryWidth + 6, height: 22)
        UIColor(red: 0.15, green: 0.35, blue: 0.65, alpha: 0.12).setFill()
        UIBezierPath(roundedRect: grandTotalRect, cornerRadius: 3).fill()

        drawSummaryRow("จำนวนเงินรวมทั้งสิ้น (Grand Total)", "฿\(formatCurrency(snapshot.grandTotal))", isBold: true)

        return max(y + 95, curSumY + 10)
    }

    // MARK: - Signatures and Legal Footer
    private static func drawSignaturesAndFooter(cg: CGContext, snapshot: FullTaxInvoiceSnapshot, atY: CGFloat) {
        let sigY = Layout.pageHeight - Layout.marginBottom - 56

        let boxW: CGFloat = 160
        let sig1Left = Layout.marginH + 30
        let sig2Left = Layout.pageWidth - Layout.marginH - boxW - 30

        // Sig 1
        cg.setStrokeColor(UIColor(white: 0.5, alpha: 1.0).cgColor)
        cg.setLineWidth(0.8)
        cg.move(to: CGPoint(x: sig1Left, y: sigY))
        cg.addLine(to: CGPoint(x: sig1Left + boxW, y: sigY))
        cg.strokePath()

        let sigAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 8), .foregroundColor: UIColor.darkGray]
        drawCenteredText("ผู้รับเงิน / Cashier", centerX: sig1Left + (boxW / 2), y: sigY + 4, attrs: sigAttrs)

        // Sig 2
        cg.move(to: CGPoint(x: sig2Left, y: sigY))
        cg.addLine(to: CGPoint(x: sig2Left + boxW, y: sigY))
        cg.strokePath()
        drawCenteredText("ผู้มีอำนาจลงนาม / Authorized Signature", centerX: sig2Left + (boxW / 2), y: sigY + 4, attrs: sigAttrs)

        // Footer legal notice
        let footerText = "เอกสารนี้ออกโดยระบบบริหารจัดการร้านอาหาร AlphaPos ตามมาตรฐานกรมสรรพากร"
        let footerAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 7.5), .foregroundColor: UIColor.lightGray]
        drawCenteredText(footerText, centerX: Layout.pageWidth / 2, y: Layout.pageHeight - Layout.marginBottom - 10, attrs: footerAttrs)
    }

    // MARK: - Helpers
    private static func drawRightText(_ text: String, rightX: CGFloat, y: CGFloat, attrs: [NSAttributedString.Key: Any]) {
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        str.draw(at: CGPoint(x: rightX - size.width, y: y))
    }

    private static func drawCenteredText(_ text: String, centerX: CGFloat, y: CGFloat, attrs: [NSAttributedString.Key: Any]) {
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        str.draw(at: CGPoint(x: centerX - (size.width / 2), y: y))
    }

    private static func formatCurrency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }
}
