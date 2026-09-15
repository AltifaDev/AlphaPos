import Foundation

struct AccountingExportTests {
    private static func result(_ name: String, _ passed: Bool, _ details: String = "") -> TestResult {
        passed ? .success(name) : .failure(name, details.isEmpty ? "assertion failed" : details)
    }
    static func runAll() -> [TestResult] {
        let at = Date(timeIntervalSince1970: 1_700_000_000)
        let rows = [
            AccountingExportRow(documentNumber: "INV-1", businessDate: "2026-08-25", occurredAt: at, accountCode: "1100", accountName: "เงินสด", debit: 107, credit: 0, taxCode: "", description: "ขาย,หน้าร้าน", sourceEventKey: "payment:1"),
            AccountingExportRow(documentNumber: "INV-1", businessDate: "2026-08-25", occurredAt: at, accountCode: "4100", accountName: "รายได้", debit: 0, credit: 100, taxCode: "VAT7", description: "sale", sourceEventKey: "payment:1"),
            AccountingExportRow(documentNumber: "INV-1", businessDate: "2026-08-25", occurredAt: at, accountCode: "2100", accountName: "ภาษีขาย", debit: 0, credit: 7, taxCode: "VAT7", description: "VAT", sourceEventKey: "payment:1")
        ]
        let data = try? AccountingExport.journalCSV(rows)
        let csv = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let vat = ThaiVATExportRow(documentNumber: "TAX-1", documentDate: "2026-08-25", customerTaxId: "0100000000001", customerName: "บริษัท ทดสอบ จำกัด", branchNumber: "00000", taxableAmount: 100, vatAmount: 7, totalAmount: 107, cancelled: false)
        let vatCSV = (try? AccountingExport.thaiVATCSV([vat])).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        var unbalancedRejected = false
        do { _ = try AccountingExport.journalCSV(Array(rows.dropLast())) } catch AccountingExportError.unbalanced { unbalancedRejected = true } catch {}
        var invalidVATRejected = false
        do { _ = try AccountingExport.thaiVATCSV([ThaiVATExportRow(documentNumber: "BAD", documentDate: "2026-08-25", customerTaxId: "", customerName: "", branchNumber: "00000", taxableAmount: 100, vatAmount: 7, totalAmount: 108, cancelled: false)]) } catch AccountingExportError.invalidVATDocument { invalidVATRejected = true } catch {}
        return [
            result("accounting export emits UTF-8 BOM", data?.starts(with: [0xEF, 0xBB, 0xBF]) == true),
            result("accounting export quotes CSV fields", csv.contains("\"ขาย,หน้าร้าน\"")),
            result("accounting export rejects unbalanced journal", unbalancedRejected),
            result("VAT export emits issued document", vatCSV.contains("TAX-1") && vatCSV.contains("107.00,issued")),
            result("VAT export rejects inconsistent total", invalidVATRejected)
        ]
    }
}
