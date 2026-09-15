import Foundation

struct AccountingExportRow: Sendable, Equatable {
    let documentNumber: String
    let businessDate: String
    let occurredAt: Date
    let accountCode: String
    let accountName: String
    let debit: Double
    let credit: Double
    let taxCode: String
    let description: String
    let sourceEventKey: String
}

struct ThaiVATExportRow: Sendable, Equatable {
    let documentNumber: String
    let documentDate: String
    let customerTaxId: String
    let customerName: String
    let branchNumber: String
    let taxableAmount: Double
    let vatAmount: Double
    let totalAmount: Double
    let cancelled: Bool
}

enum AccountingExportError: Error, Equatable {
    case unbalanced(debit: Int64, credit: Int64)
    case invalidVATDocument(String)
}

/// Deterministic UTF-8 exports for accounting hand-off. Currency is validated
/// as integer satang before any journal is emitted.
enum AccountingExport {
    static func journalCSV(_ rows: [AccountingExportRow]) throws -> Data {
        let debit = rows.reduce(Int64(0)) { $0 + satang($1.debit) }
        let credit = rows.reduce(Int64(0)) { $0 + satang($1.credit) }
        guard debit == credit else { throw AccountingExportError.unbalanced(debit: debit, credit: credit) }
        var lines = ["document_number,business_date,occurred_at,account_code,account_name,debit,credit,tax_code,description,source_event_key"]
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        lines += rows.sorted(by: journalOrder).map { row in
            [row.documentNumber, row.businessDate, formatter.string(from: row.occurredAt), row.accountCode,
             row.accountName, money(row.debit), money(row.credit), row.taxCode, row.description,
             row.sourceEventKey].map(csv).joined(separator: ",")
        }
        return Data(("\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n").utf8)
    }

    static func thaiVATCSV(_ rows: [ThaiVATExportRow]) throws -> Data {
        for row in rows {
            guard !row.documentNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  row.taxableAmount >= 0, row.vatAmount >= 0,
                  satang(row.taxableAmount + row.vatAmount) == satang(row.totalAmount)
            else { throw AccountingExportError.invalidVATDocument(row.documentNumber) }
        }
        var lines = ["document_number,document_date,customer_tax_id,customer_name,branch_number,taxable_amount,vat_amount,total_amount,status"]
        lines += rows.sorted { ($0.documentDate, $0.documentNumber) < ($1.documentDate, $1.documentNumber) }.map { row in
            [row.documentNumber, row.documentDate, row.customerTaxId, row.customerName, row.branchNumber,
             money(row.taxableAmount), money(row.vatAmount), money(row.totalAmount),
             row.cancelled ? "cancelled" : "issued"].map(csv).joined(separator: ",")
        }
        return Data(("\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n").utf8)
    }

    nonisolated private static func journalOrder(_ lhs: AccountingExportRow, _ rhs: AccountingExportRow) -> Bool {
        (lhs.businessDate, lhs.documentNumber, lhs.accountCode, lhs.sourceEventKey) < (rhs.businessDate, rhs.documentNumber, rhs.accountCode, rhs.sourceEventKey)
    }
    nonisolated private static func satang(_ value: Double) -> Int64 { Int64((value * 100).rounded()) }
    nonisolated private static func money(_ value: Double) -> String { String(format: "%.2f", Double(satang(value)) / 100) }
    nonisolated private static func csv(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
