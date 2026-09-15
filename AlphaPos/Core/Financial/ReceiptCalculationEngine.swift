import Foundation

/// The sole money/tax calculation path for checkout, receipts and reporting snapshots.
/// All values are calculated with Decimal and rounded explicitly to the currency minor unit.
enum ReceiptCalculationEngine {
    enum RoundingMode: String, Codable, Sendable { case perLine, perDocument }

    struct Line: Sendable {
        let id: String
        let name: String
        let quantity: Int
        let unitPrice: Decimal
        let taxRate: Decimal
        let taxInclusive: Bool

        var amount: Decimal { unitPrice * Decimal(quantity) }
    }

    struct Input: Sendable {
        let lines: [Line]
        let discount: Decimal
        let serviceChargeRate: Decimal
        let serviceChargeEnabled: Bool
        let serviceChargeTaxable: Bool
        let serviceChargeTaxRate: Decimal
        let serviceChargeTaxInclusive: Bool
        let customerTaxExempt: Bool
        let roundingMode: RoundingMode
    }

    struct TaxLine: Sendable {
        let rate: Decimal
        let inclusive: Bool
        let taxableAmount: Decimal
        let taxAmount: Decimal
    }

    struct LineResult: Sendable {
        let id: String
        let name: String
        let quantity: Int
        let unitPrice: Decimal
        let lineAmount: Decimal
        let allocatedDiscount: Decimal
    }

    struct Result: Sendable {
        let lines: [LineResult]
        let subtotal: Decimal
        let discount: Decimal
        let serviceChargeBase: Decimal
        let serviceChargeRate: Decimal
        let serviceCharge: Decimal
        let taxableBase: Decimal
        let tax: Decimal
        let inclusiveTax: Decimal
        let exclusiveTax: Decimal
        let total: Decimal
        let taxLines: [TaxLine]
        let roundingMode: RoundingMode

        var isBalanced: Bool {
            ReceiptCalculationEngine.money(subtotal + serviceCharge - discount + exclusiveTax) == total
        }
    }

    static func calculate(_ input: Input) -> Result {
        let subtotal = money(input.lines.reduce(Decimal.zero) { $0 + $1.amount })
        let discount = min(max(0, money(input.discount)), subtotal)
        let serviceBase = subtotal
        let serviceCharge = input.serviceChargeEnabled
            ? money(serviceBase * input.serviceChargeRate / 100)
            : 0

        var remainingDiscount = discount
        var lineResults: [LineResult] = []
        var grouped: [String: (rate: Decimal, inclusive: Bool, base: Decimal, tax: Decimal)] = [:]
        var unroundedGroups: [String: (rate: Decimal, inclusive: Bool, base: Decimal, tax: Decimal)] = [:]

        for (index, line) in input.lines.enumerated() {
            let gross = money(line.amount)
            let allocated: Decimal
            if index == input.lines.indices.last {
                allocated = remainingDiscount
            } else if subtotal > 0 {
                allocated = min(remainingDiscount, money(discount * gross / subtotal))
            } else {
                allocated = 0
            }
            remainingDiscount -= allocated
            let discountedAmount = max(0, gross - allocated)
            lineResults.append(.init(
                id: line.id, name: line.name, quantity: line.quantity,
                unitPrice: money(line.unitPrice), lineAmount: gross,
                allocatedDiscount: money(allocated)
            ))

            guard !input.customerTaxExempt, line.taxRate > 0 else { continue }
            appendTax(
                amount: discountedAmount,
                rate: line.taxRate,
                inclusive: line.taxInclusive,
                roundingMode: input.roundingMode,
                roundedGroups: &grouped,
                unroundedGroups: &unroundedGroups
            )
        }

        if !input.customerTaxExempt, input.serviceChargeTaxable,
           serviceCharge > 0, input.serviceChargeTaxRate > 0 {
            appendTax(
                amount: serviceCharge,
                rate: input.serviceChargeTaxRate,
                inclusive: input.serviceChargeTaxInclusive,
                roundingMode: input.roundingMode,
                roundedGroups: &grouped,
                unroundedGroups: &unroundedGroups
            )
        }

        if input.roundingMode == .perDocument {
            grouped = unroundedGroups.mapValues { value in
                (value.rate, value.inclusive, money(value.base), money(value.tax))
            }
        }

        let taxLines = grouped.values
            .map { TaxLine(rate: $0.rate, inclusive: $0.inclusive, taxableAmount: money($0.base), taxAmount: money($0.tax)) }
            .sorted {
                if $0.rate != $1.rate { return $0.rate < $1.rate }
                return $0.inclusive && !$1.inclusive
            }
        let inclusiveTax = money(taxLines.filter(\.inclusive).reduce(0) { $0 + $1.taxAmount })
        let exclusiveTax = money(taxLines.filter { !$0.inclusive }.reduce(0) { $0 + $1.taxAmount })
        let tax = money(inclusiveTax + exclusiveTax)
        let taxableBase = money(taxLines.reduce(0) { $0 + $1.taxableAmount })
        let total = money(max(0, subtotal + serviceCharge - discount + exclusiveTax))

        return Result(
            lines: lineResults, subtotal: subtotal, discount: discount,
            serviceChargeBase: serviceBase, serviceChargeRate: input.serviceChargeRate,
            serviceCharge: serviceCharge, taxableBase: taxableBase, tax: tax,
            inclusiveTax: inclusiveTax, exclusiveTax: exclusiveTax, total: total,
            taxLines: taxLines, roundingMode: input.roundingMode
        )
    }

    private static func appendTax(
        amount: Decimal,
        rate: Decimal,
        inclusive: Bool,
        roundingMode: RoundingMode,
        roundedGroups: inout [String: (rate: Decimal, inclusive: Bool, base: Decimal, tax: Decimal)],
        unroundedGroups: inout [String: (rate: Decimal, inclusive: Bool, base: Decimal, tax: Decimal)]
    ) {
        let rawTax = inclusive ? amount * rate / (100 + rate) : amount * rate / 100
        let rawBase = inclusive ? amount - rawTax : amount
        let key = "\(rate)|\(inclusive)"
        var raw = unroundedGroups[key] ?? (rate, inclusive, 0, 0)
        raw.base += rawBase; raw.tax += rawTax; unroundedGroups[key] = raw
        guard roundingMode == .perLine else { return }
        var rounded = roundedGroups[key] ?? (rate, inclusive, 0, 0)
        rounded.base += money(rawBase); rounded.tax += money(rawTax); roundedGroups[key] = rounded
    }

    static func money(_ value: Decimal) -> Decimal {
        var source = value
        var result = Decimal()
        NSDecimalRound(&result, &source, 2, .plain)
        return result
    }
}

enum ReceiptDocumentType: String, Codable, CaseIterable, Sendable {
    case receipt
    case abbreviatedTaxInvoice
    case receiptAndAbbreviatedTaxInvoice
    case fullTaxInvoice
    case receiptAndFullTaxInvoice
    case preBill

    var thaiTitle: String {
        switch self {
        case .receipt: return "ใบเสร็จรับเงิน"
        case .abbreviatedTaxInvoice: return "ใบกำกับภาษีอย่างย่อ"
        case .receiptAndAbbreviatedTaxInvoice: return "ใบเสร็จรับเงิน/ใบกำกับภาษีอย่างย่อ"
        case .fullTaxInvoice: return "ใบกำกับภาษีเต็มรูปแบบ"
        case .receiptAndFullTaxInvoice: return "ใบเสร็จรับเงิน/ใบกำกับภาษี"
        case .preBill: return "ใบแจ้งรายการ (ยังไม่ชำระ)"
        }
    }

    var isTaxInvoice: Bool {
        switch self {
        case .abbreviatedTaxInvoice, .receiptAndAbbreviatedTaxInvoice, .fullTaxInvoice, .receiptAndFullTaxInvoice:
            return true
        default:
            return false
        }
    }

    var isFullTaxInvoice: Bool {
        switch self {
        case .fullTaxInvoice, .receiptAndFullTaxInvoice:
            return true
        default:
            return false
        }
    }
}

enum ReceiptValidation {
    static func sellerErrors(
        documentType: ReceiptDocumentType,
        storeName: String,
        address: String,
        taxId: String,
        branchCode: String,
        documentNumber: String
    ) -> [String] {
        var errors: [String] = []
        if storeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { errors.append("Missing seller name") }
        if address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { errors.append("Missing seller address") }
        if documentNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { errors.append("Missing document number") }
        if documentType.isTaxInvoice {
            let digits = taxId.filter(\.isNumber)
            if digits.count != 13 { errors.append("Tax invoice requires a 13-digit seller tax ID") }
            if branchCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { errors.append("Tax invoice requires a branch code") }
        }
        return errors
    }

    static func validateTaxId13Digits(_ taxId: String) -> Bool {
        let digits = taxId.filter(\.isNumber)
        guard digits.count == 13 else { return false }
        return true
    }
}
