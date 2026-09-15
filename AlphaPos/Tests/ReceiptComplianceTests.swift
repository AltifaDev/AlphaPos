import Foundation

#if TEST_RUNNER
enum ReceiptComplianceGate {
    static func canIssueAbbreviatedTaxInvoice(vatEnabled: Bool, taxId: String) -> Bool {
        let digits = taxId.filter(\.isNumber)
        return vatEnabled && digits.count == 13 && digits != "1234567890123"
    }
}
#endif

enum ReceiptComplianceTests {
    static func runAll() -> [TestResult] {
        [
            check(true, "0105551234567", expected: true, "valid VAT registration"),
            check(false, "0105551234567", expected: false, "VAT disabled"),
            check(true, "1234567890123", expected: false, "sample tax ID rejected"),
            check(true, "123", expected: false, "invalid tax ID rejected"),
        ]
    }

    private static func check(
        _ enabled: Bool,
        _ taxId: String,
        expected: Bool,
        _ name: String
    ) -> TestResult {
        ReceiptComplianceGate.canIssueAbbreviatedTaxInvoice(vatEnabled: enabled, taxId: taxId) == expected
            ? .success(name)
            : .failure(name, "Unexpected tax-invoice eligibility.")
    }
}
