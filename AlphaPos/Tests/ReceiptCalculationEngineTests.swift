import Foundation

enum ReceiptCalculationEngineTests {
    static func runAll() -> [TestResult] {
        [inclusiveVATAfterDiscountAndService(), exclusiveVAT(), taxExempt(), balancedInvariant(), sellerValidation()]
    }

    private static func sample(inclusive: Bool = true, exempt: Bool = false) -> ReceiptCalculationEngine.Result {
        ReceiptCalculationEngine.calculate(.init(
            lines: [
                .init(id: "1", name: "Burger", quantity: 2, unitPrice: 220, taxRate: 7, taxInclusive: inclusive),
                .init(id: "2", name: "Fries", quantity: 1, unitPrice: 120, taxRate: 7, taxInclusive: inclusive),
                .init(id: "3", name: "Latte", quantity: 2, unitPrice: 110, taxRate: 7, taxInclusive: inclusive)
            ],
            discount: 39, serviceChargeRate: 10, serviceChargeEnabled: true,
            serviceChargeTaxable: true, serviceChargeTaxRate: 7,
            serviceChargeTaxInclusive: inclusive, customerTaxExempt: exempt,
            roundingMode: .perLine
        ))
    }

    private static func inclusiveVATAfterDiscountAndService() -> TestResult {
        let value = sample()
        return value.subtotal == 780 && value.serviceCharge == 78 && value.discount == 39
            && value.tax == 53.58 && value.total == 819
            ? .success("inclusive VAT after discount and service")
            : .failure("inclusive VAT after discount and service", "Expected subtotal 780, service 78, VAT 53.58 and total 819; got \(value)")
    }

    private static func exclusiveVAT() -> TestResult {
        let value = sample(inclusive: false)
        return value.tax == Decimal(string: "57.33")! && value.total == Decimal(string: "876.33")!
            ? .success("exclusive VAT adds to total")
            : .failure("exclusive VAT adds to total", "Expected VAT 57.33 and total 876.33; got VAT \(value.tax), total \(value.total)")
    }

    private static func taxExempt() -> TestResult {
        let value = sample(exempt: true)
        return value.tax == 0 && value.total == 819
            ? .success("tax exempt transaction has no VAT")
            : .failure("tax exempt transaction has no VAT", "Tax exemption must remove VAT")
    }

    private static func balancedInvariant() -> TestResult {
        sample().isBalanced && sample(inclusive: false).isBalanced
            ? .success("receipt balance invariant")
            : .failure("receipt balance invariant", "Calculated receipts must balance")
    }

    private static func sellerValidation() -> TestResult {
        let invalid = ReceiptValidation.sellerErrors(
            documentType: .receiptAndAbbreviatedTaxInvoice,
            storeName: "Store", address: "Bangkok", taxId: "123", branchCode: "", documentNumber: ""
        )
        let valid = ReceiptValidation.sellerErrors(
            documentType: .receiptAndAbbreviatedTaxInvoice,
            storeName: "Store", address: "Bangkok", taxId: "0105551234567", branchCode: "00000", documentNumber: "RCP-1"
        )
        return invalid.count == 3 && valid.isEmpty
            ? .success("seller document validation")
            : .failure("seller document validation", "Tax document validation did not reject/accept expected fields")
    }
}
