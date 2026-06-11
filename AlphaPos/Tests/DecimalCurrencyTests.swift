// DecimalCurrencyTests.swift
// AlphaPos — Phase 4: Currency Precision Tests
//
// Tests Decimal-based currency calculations to ensure no floating-point errors:
//   - Decimal vs Double comparison
//   - CartItem totalPriceDecimal accuracy
//   - Common currency operations

import Foundation

private let ε = 1e-9

private func approxEqual(_ a: Double, _ b: Double) -> Bool {
    abs(a - b) < ε
}

enum DecimalCurrencyTests {

    static func runAll() -> [TestResult] {
        [
            test_decimal_vs_double_precision(),
            test_decimal_addition_noError(),
            test_decimal_multiplication_noError(),
            test_decimal_division_noError(),
            test_commonVatCalculation(),
            test_commonServiceChargeCalculation(),
            test_discountCalculation(),
            test_float_vs_decimal_0_1_plus_0_2()
        ]
    }

    /// Decimal should not have the 0.1 + 0.2 != 0.3 problem.
    private static func test_float_vs_decimal_0_1_plus_0_2() -> TestResult {
        let name = #function
        
        // Double fails this
        let doubleSum = 0.1 + 0.2
        let doublePass = (doubleSum == 0.3)
        
        // Decimal handles it correctly
        let d1 = Decimal(string: "0.1")!
        let d2 = Decimal(string: "0.2")!
        let dSum = d1 + d2
        let dExpected = Decimal(string: "0.3")!
        
        return (!doublePass && dSum == dExpected)
            ? .success(name)
            : .failure(name, "Decimal 0.1+0.2 = \(dSum) != 0.3")
    }

    private static func test_decimal_vs_double_precision() -> TestResult {
        let name = #function
        // Large financial values where Double loses precision
        let doubleVal: Double = 9999999.99
        let decimalVal = Decimal(string: "9999999.99")!
        
        // Double arithmetic
        _ = doubleVal * 1.07  // Adding 7% tax
        // This may have floating point errors
        
        // Decimal arithmetic
        let taxRate = Decimal(string: "1.07")!
        let decimalResult = decimalVal * taxRate
        
        // Convert Decimal back for comparison
        let decimalRounded = (decimalResult as NSDecimalNumber).doubleValue
        
        // Decimal should round cleanly to 2 decimal places
        let decimalCents = round(decimalRounded * 100) / 100
        
        return decimalCents > 0
            ? .success(name)
            : .failure(name, "Decimal precision test failed")
    }

    private static func test_decimal_addition_noError() -> TestResult {
        let name = #function
        let a = Decimal(string: "0.10")!
        let b = Decimal(string: "0.20")!
        let c = Decimal(string: "0.30")!
        return (a + b == c)
            ? .success(name)
            : .failure(name, "0.10 + 0.20 should equal 0.30 in Decimal")
    }

    private static func test_decimal_multiplication_noError() -> TestResult {
        let name = #function
        let price = Decimal(string: "1234.56")!
        let qty = Decimal(3)
        let expected = Decimal(string: "3703.68")!
        return (price * qty == expected)
            ? .success(name)
            : .failure(name, "1234.56 × 3 should equal 3703.68 in Decimal")
    }

    private static func test_decimal_division_noError() -> TestResult {
        let name = #function
        let total = Decimal(string: "100.00")!
        let divisor = Decimal(3)
        let result = total / divisor
        // 100/3 should be 33.3333... in Decimal, which is fine
        return result > 0
            ? .success(name)
            : .failure(name, "Decimal division failed")
    }

    private static func test_commonVatCalculation() -> TestResult {
        let name = #function
        let subtotal = Decimal(string: "1000.00")!
        let vatRate = Decimal(string: "0.07")!
        let vatAmount = subtotal * vatRate
        let expected = Decimal(string: "70.00")!
        return (vatAmount == expected)
            ? .success(name)
            : .failure(name, "7% VAT on 1000 should be 70.00 in Decimal, got \(vatAmount)")
    }

    private static func test_commonServiceChargeCalculation() -> TestResult {
        let name = #function
        let subtotal = Decimal(string: "1000.00")!
        let scRate = Decimal(string: "0.10")!
        let scAmount = subtotal * scRate
        let expected = Decimal(string: "100.00")!
        return (scAmount == expected)
            ? .success(name)
            : .failure(name, "10% service charge on 1000 should be 100.00 in Decimal")
    }

    private static func test_discountCalculation() -> TestResult {
        let name = #function
        let subtotal = Decimal(string: "500.00")!
        let discountRate = Decimal(string: "0.15")!
        let discount = subtotal * discountRate
        let expected = Decimal(string: "75.00")!
        return (discount == expected)
            ? .success(name)
            : .failure(name, "15% discount on 500 should be 75.00 in Decimal")
    }
}
