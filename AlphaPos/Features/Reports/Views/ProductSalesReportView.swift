import SwiftUI
import UIKit

struct ProductSalesReportView: View {
    @Bindable var viewModel: ReportsViewModel
    let onScopeChange: () -> Void
    @State private var search = ""
    @State private var category = "ทั้งหมด"
    @State private var sort = Sort.netSales

    enum Sort: String, CaseIterable {
        case netSales = "ยอดขายสุทธิ"
        case quantity = "จำนวนตามขอบเขต"
        case name = "ชื่อสินค้า"
    }

    private var categories: [String] {
        ["ทั้งหมด"] + Set(viewModel.productSalesItems.map(\.category)).sorted()
    }

    private var rows: [ReportProductSalesPoint] {
        let filtered = viewModel.productSalesItems.filter {
            (category == "ทั้งหมด" || $0.category == category) &&
            (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.sku.localizedCaseInsensitiveContains(search))
        }
        switch sort {
        case .netSales: return filtered.sorted { $0.netSales > $1.netSales }
        case .quantity: return filtered.sorted { $0.quantitySold > $1.quantitySold }
        case .name: return filtered.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                TextField("ค้นหาชื่อสินค้า / SKU", text: $search)
                    .textFieldStyle(.roundedBorder)
                Picker("หมวดหมู่", selection: $category) {
                    ForEach(categories, id: \.self) { Text($0).tag($0) }
                }
                Picker("เรียงตาม", selection: $sort) {
                    ForEach(Sort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Picker("ขอบเขต", selection: $viewModel.productSalesScope) {
                    ForEach(ReportItemScope.allCases) { scope in
                        Text(scope.displayName).tag(scope)
                    }
                }
                .onChange(of: viewModel.productSalesScope) { _, _ in onScopeChange() }
            }

            Text("ขอบเขตรายงาน: \(viewModel.productSalesScope.displayName)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                metric("รายการสินค้า", "\(rows.count)")
                metric(viewModel.productSalesScope.quantityLabel, "\(rows.reduce(0) { $0 + $1.quantitySold })")
                metric("ยอดขายสุทธิ", currency(rows.reduce(0) { $0 + $1.netSales }))
                metric("ส่วนลด/คืนเงิน", currency(rows.reduce(0) { $0 + $1.discount + $1.refunds }))
            }

            VStack(spacing: 0) {
                tableRow(["SKU", "สินค้า", "ช่องทาง", "ประเภท", "จำนวน", "ยอดก่อนลด", "ส่วนลด", "คืนเงิน", "ยอดสุทธิ"], header: true)
                if rows.isEmpty {
                    Text("ไม่พบข้อมูลสินค้าที่ขายในช่วงเวลานี้")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(30)
                } else {
                    ForEach(rows) { row in
                        tableRow([
                            row.sku, row.name, row.channel, row.itemType, "\(row.quantitySold)",
                            currency(row.grossSales), currency(row.discount),
                            currency(row.refunds), currency(row.netSales)
                        ])
                    }
                }
            }
            .background(Color.appSurfaceHigh.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.appAccent.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func tableRow(_ values: [String], header: Bool = false) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                Text(value)
                    .font(.system(size: header ? 11 : 10, weight: header || index == values.count - 1 ? .semibold : .regular))
                    .lineLimit(2)
                    .frame(maxWidth: index == 1 ? .infinity : nil, alignment: index >= 4 ? .trailing : .leading)
                    .frame(width: index == 0 ? 60 : (index == 2 || index == 3) ? 72 : index >= 4 ? 72 : nil)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, header ? 10 : 8)
        .background(header ? Color.appAccent.opacity(0.12) : Color.clear)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func currency(_ amount: Double) -> String {
        String(format: "฿%.2f", amount)
    }
}

struct ProductSalesPDFSnapshot {
    let storeName: String
    let period: String
    let generatedAt: Date
    let scopeLabel: String
    let quantityLabel: String
    let rows: [ReportProductSalesPoint]
}

enum ProductSalesPDFExporter {
    static func export(_ snapshot: ProductSalesPDFSnapshot) -> URL? {
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Product_Sales_\(Int(snapshot.generatedAt.timeIntervalSince1970)).pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: page)

        do {
            try renderer.writePDF(to: url) { context in
                let rowsPerPage = 28
                let pages = max(1, Int(ceil(Double(snapshot.rows.count) / Double(rowsPerPage))))
                for pageIndex in 0..<pages {
                    context.beginPage()
                    drawHeader(snapshot, page: pageIndex + 1, pages: pages)
                    let start = pageIndex * rowsPerPage
                    let end = min(start + rowsPerPage, snapshot.rows.count)
                    drawRows(Array(snapshot.rows[start..<end]), startIndex: start, page: page)
                }
            }
            return url
        } catch {
            return nil
        }
    }

    private static func drawHeader(_ snapshot: ProductSalesPDFSnapshot, page: Int, pages: Int) {
        UIColor.systemBlue.setFill()
        UIRectFill(CGRect(x: 0, y: 0, width: 595, height: 6))
        draw(snapshot.storeName, at: CGRect(x: 36, y: 26, width: 320, height: 24), font: .boldSystemFont(ofSize: 17))
        draw("รายงานยอดขายตามสินค้า / PRODUCT SALES REPORT", at: CGRect(x: 36, y: 54, width: 520, height: 18), font: .boldSystemFont(ofSize: 12))
        draw("ช่วงเวลา: \(snapshot.period) · ขอบเขต: \(snapshot.scopeLabel) · KPI: \(snapshot.quantityLabel)", at: CGRect(x: 36, y: 76, width: 360, height: 16), font: .systemFont(ofSize: 8), color: .darkGray)
        let stamp = DateFormatter.localizedString(from: snapshot.generatedAt, dateStyle: .medium, timeStyle: .short)
        draw("จัดทำเมื่อ: \(stamp)   หน้า \(page)/\(pages)", at: CGRect(x: 360, y: 76, width: 199, height: 16), font: .systemFont(ofSize: 8), color: .darkGray, right: true)
        UIColor.systemGray4.setFill()
        UIRectFill(CGRect(x: 36, y: 100, width: 523, height: 1))
    }

    private static func drawRows(_ rows: [ReportProductSalesPoint], startIndex: Int, page: CGRect) {
        let x: [CGFloat] = [36, 58, 114, 265, 335, 371, 425, 479]
        let widths: [CGFloat] = [22, 56, 151, 70, 36, 54, 54, 80]
        let headers = ["#", "SKU", "สินค้า / Product", "หมวดหมู่", "Qty", "Gross", "Disc/Refund", "Net Sales"]
        var y: CGFloat = 112

        UIColor.systemBlue.withAlphaComponent(0.12).setFill()
        UIRectFill(CGRect(x: 36, y: y, width: 523, height: 24))
        for i in headers.indices {
            draw(headers[i], at: CGRect(x: x[i], y: y + 6, width: widths[i], height: 14), font: .boldSystemFont(ofSize: 7.5), right: i >= 4)
        }
        y += 24

        for (offset, row) in rows.enumerated() {
            if offset.isMultiple(of: 2) {
                UIColor.systemGray6.setFill()
                UIRectFill(CGRect(x: 36, y: y, width: 523, height: 23))
            }
            let values = [
                "\(startIndex + offset + 1)", row.sku, row.name, row.category, "\(row.quantitySold)",
                money(row.grossSales), money(row.discount + row.refunds), money(row.netSales)
            ]
            for i in values.indices {
                draw(values[i], at: CGRect(x: x[i], y: y + 5, width: widths[i] - 3, height: 15), font: .systemFont(ofSize: 7.5), right: i >= 4)
            }
            y += 23
        }

        let total = rows.reduce(0) { $0 + $1.netSales }
        draw("ยอดสุทธิในหน้านี้ / Page net sales: \(money(total))",
             at: CGRect(x: 300, y: page.height - 48, width: 259, height: 16),
             font: .boldSystemFont(ofSize: 8), right: true)
        draw("AlphaPos - ข้อมูลจากรายการขายที่รับชำระแล้ว", at: CGRect(x: 36, y: page.height - 30, width: 350, height: 12), font: .systemFont(ofSize: 7), color: .gray)
    }

    private static func draw(_ text: String, at rect: CGRect, font: UIFont, color: UIColor = .label, right: Bool = false) {
        let style = NSMutableParagraphStyle()
        style.alignment = right ? .right : .left
        (text as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
    }

    private static func money(_ value: Double) -> String { String(format: "฿%.2f", value) }
}
