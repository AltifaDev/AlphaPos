// PayrollTests.swift
// AlphaPos — Phase 4: Unit Testing Suite
//
// Tests payroll business logic (pure functions, no SwiftData):
//   - Monthly salary net calculation
//   - Hourly wage calculation
//   - OT pay at 1.5x rate
//   - Social Security contribution (5%, capped at 750 THB)
//   - Late penalty deductions
//   - Attendance rate percentage
//   - Working days calculation (exclude weekends)
//   - Edge cases: zero hours, max SSF cap, OT for monthly vs hourly

import Foundation

// ─── Pure payroll calculation helpers ────────────────────────────────────────

private enum PayrollCalculator {
    
    /// Monthly employee base pay = fixed salary (regardless of hours)
    static func monthlyBasePay(salary: Double) -> Double {
        return salary
    }
    
    /// Hourly employee base pay = rate × total hours worked
    static func hourlyBasePay(hourlyRate: Double, totalHours: Double) -> Double {
        return hourlyRate * totalHours
    }
    
    /// OT pay for monthly employee:
    /// OT hourly rate = (salary / 30 days / 8 hours) × multiplier
    static func monthlyOTPay(salary: Double, otHours: Double, multiplier: Double = 1.5) -> Double {
        let otHourlyRate = salary / 30.0 / 8.0
        return otHours * otHourlyRate * multiplier
    }
    
    /// OT pay for hourly employee:
    /// OT pay = hourlyRate × multiplier × otHours
    static func hourlyOTPay(hourlyRate: Double, otHours: Double, multiplier: Double = 1.5) -> Double {
        return hourlyRate * multiplier * otHours
    }
    
    /// Social Security Fund contribution (employee portion):
    /// 5% of total income, capped at 750 THB/month
    static func socialSecurityContribution(totalIncome: Double, rate: Double = 0.05, cap: Double = 750.0) -> Double {
        return min(totalIncome * rate, cap)
    }
    
    /// Net pay = basePay + otPay + bonus - deductions - socialSecurity
    static func netPay(basePay: Double, otPay: Double, bonus: Double = 0, deductions: Double = 0, socialSecurity: Double) -> Double {
        return basePay + otPay + bonus - deductions - socialSecurity
    }
    
    /// Late penalty: deduction per late occurrence
    static func latePenalty(lateCount: Int, penaltyPerOccurrence: Double = 50.0) -> Double {
        return Double(lateCount) * penaltyPerOccurrence
    }
    
    /// Attendance rate = daysWorked / expectedDays × 100
    static func attendanceRate(daysWorked: Int, expectedDays: Int) -> Double {
        guard expectedDays > 0 else { return 0 }
        return (Double(daysWorked) / Double(expectedDays)) * 100.0
    }
    
    /// Count working days (Mon-Fri) in a given month
    static func workingDaysInMonth(year: Int, month: Int) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Bangkok")!
        
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        
        guard let startOfMonth = calendar.date(from: components) else { return 22 }
        
        let range = calendar.range(of: .day, in: .month, for: startOfMonth)!
        var count = 0
        
        for day in range {
            components.day = day
            if let date = calendar.date(from: components) {
                let weekday = calendar.component(.weekday, from: date)
                if weekday != 1 && weekday != 7 { // Not Sunday (1) or Saturday (7)
                    count += 1
                }
            }
        }
        return count
    }
}

// ─────────────────────────────────────────────────────────────────────────────

private let ε = 1e-2

private func approxEqual(_ a: Double, _ b: Double) -> Bool {
    abs(a - b) < ε
}

// MARK: -

enum PayrollTests {
    
    static func runAll() -> [TestResult] {
        [
            test_monthlyBasePay(),
            test_hourlyBasePay(),
            test_monthlyOTPay_standard(),
            test_hourlyOTPay_standard(),
            test_socialSecurity_underCap(),
            test_socialSecurity_atCap(),
            test_socialSecurity_overCap(),
            test_netPay_monthlyEmployee(),
            test_netPay_hourlyEmployee(),
            test_netPay_withBonusAndDeductions(),
            test_latePenalty_zero(),
            test_latePenalty_multiple(),
            test_attendanceRate_perfect(),
            test_attendanceRate_partial(),
            test_attendanceRate_zeroDays(),
            test_workingDays_june2026(),
            test_netPay_zeroHoursHourlyEmployee(),
            test_otPay_doubleRate(),
        ]
    }
    
    // MARK: - Base Pay
    
    private static func test_monthlyBasePay() -> TestResult {
        let name = #function
        let pay = PayrollCalculator.monthlyBasePay(salary: 25000)
        return approxEqual(pay, 25000.0)
            ? .success(name)
            : .failure(name, "Monthly base pay should be 25000, got \(pay)")
    }
    
    private static func test_hourlyBasePay() -> TestResult {
        let name = #function
        // 75 THB/h × 180 hours = 13500 THB
        let pay = PayrollCalculator.hourlyBasePay(hourlyRate: 75, totalHours: 180)
        return approxEqual(pay, 13500.0)
            ? .success(name)
            : .failure(name, "Hourly base pay should be 13500, got \(pay)")
    }
    
    // MARK: - OT Pay
    
    private static func test_monthlyOTPay_standard() -> TestResult {
        let name = #function
        // Salary 25000 → OT rate = 25000/30/8 = 104.17 THB/h
        // 10h OT × 1.5 = 10 × 104.17 × 1.5 = 1562.50
        let ot = PayrollCalculator.monthlyOTPay(salary: 25000, otHours: 10)
        return approxEqual(ot, 1562.50)
            ? .success(name)
            : .failure(name, "Monthly OT pay for 10h should be ~1562.50, got \(ot)")
    }
    
    private static func test_hourlyOTPay_standard() -> TestResult {
        let name = #function
        // 75 THB/h × 1.5 × 20h = 2250 THB
        let ot = PayrollCalculator.hourlyOTPay(hourlyRate: 75, otHours: 20)
        return approxEqual(ot, 2250.0)
            ? .success(name)
            : .failure(name, "Hourly OT pay for 20h should be 2250, got \(ot)")
    }
    
    // MARK: - Social Security
    
    private static func test_socialSecurity_underCap() -> TestResult {
        let name = #function
        // Income 10000 × 5% = 500 (under 750 cap)
        let ssf = PayrollCalculator.socialSecurityContribution(totalIncome: 10000)
        return approxEqual(ssf, 500.0)
            ? .success(name)
            : .failure(name, "SSF for 10000 income should be 500, got \(ssf)")
    }
    
    private static func test_socialSecurity_atCap() -> TestResult {
        let name = #function
        // Income 15000 × 5% = 750 (at cap exactly)
        let ssf = PayrollCalculator.socialSecurityContribution(totalIncome: 15000)
        return approxEqual(ssf, 750.0)
            ? .success(name)
            : .failure(name, "SSF for 15000 income should be 750, got \(ssf)")
    }
    
    private static func test_socialSecurity_overCap() -> TestResult {
        let name = #function
        // Income 30000 × 5% = 1500, capped at 750
        let ssf = PayrollCalculator.socialSecurityContribution(totalIncome: 30000)
        return approxEqual(ssf, 750.0)
            ? .success(name)
            : .failure(name, "SSF for 30000 income should be capped at 750, got \(ssf)")
    }
    
    // MARK: - Net Pay
    
    private static func test_netPay_monthlyEmployee() -> TestResult {
        let name = #function
        // Somchai: salary 25000, OT 10h → OT pay 1562.50, SSF = 750 (capped)
        // Net = 25000 + 1562.50 - 750 = 25812.50
        let basePay = PayrollCalculator.monthlyBasePay(salary: 25000)
        let otPay = PayrollCalculator.monthlyOTPay(salary: 25000, otHours: 10)
        let ssf = PayrollCalculator.socialSecurityContribution(totalIncome: basePay + otPay)
        let net = PayrollCalculator.netPay(basePay: basePay, otPay: otPay, socialSecurity: ssf)
        return approxEqual(net, 25812.50)
            ? .success(name)
            : .failure(name, "Monthly employee net pay should be ~25812.50, got \(net)")
    }
    
    private static func test_netPay_hourlyEmployee() -> TestResult {
        let name = #function
        // Somsri: 75 THB/h, 160h regular + 20h OT
        // Base: 75 × 180 = 13500
        // OT: 75 × 1.5 × 20 = 2250
        // Total income: 13500 + 2250 = 15750
        // SSF: min(15750 × 0.05, 750) = 750 (capped)
        // Net: 13500 + 2250 - 750 = 15000
        let basePay = PayrollCalculator.hourlyBasePay(hourlyRate: 75, totalHours: 180)
        let otPay = PayrollCalculator.hourlyOTPay(hourlyRate: 75, otHours: 20)
        let ssf = PayrollCalculator.socialSecurityContribution(totalIncome: basePay + otPay)
        let net = PayrollCalculator.netPay(basePay: basePay, otPay: otPay, socialSecurity: ssf)
        return approxEqual(net, 15000.0)
            ? .success(name)
            : .failure(name, "Hourly employee net pay should be 15000, got \(net)")
    }
    
    private static func test_netPay_withBonusAndDeductions() -> TestResult {
        let name = #function
        // salary 25000, no OT, bonus 2000, deductions 500, SSF 750
        // Net = 25000 + 0 + 2000 - 500 - 750 = 25750
        let net = PayrollCalculator.netPay(basePay: 25000, otPay: 0, bonus: 2000, deductions: 500, socialSecurity: 750)
        return approxEqual(net, 25750.0)
            ? .success(name)
            : .failure(name, "Net pay with bonus/deductions should be 25750, got \(net)")
    }
    
    // MARK: - Late Penalty
    
    private static func test_latePenalty_zero() -> TestResult {
        let name = #function
        let penalty = PayrollCalculator.latePenalty(lateCount: 0)
        return approxEqual(penalty, 0.0)
            ? .success(name)
            : .failure(name, "Zero late count should produce 0 penalty, got \(penalty)")
    }
    
    private static func test_latePenalty_multiple() -> TestResult {
        let name = #function
        // 3 times late × 50 THB = 150 THB
        let penalty = PayrollCalculator.latePenalty(lateCount: 3, penaltyPerOccurrence: 50)
        return approxEqual(penalty, 150.0)
            ? .success(name)
            : .failure(name, "3× late at 50 THB should be 150, got \(penalty)")
    }
    
    // MARK: - Attendance Rate
    
    private static func test_attendanceRate_perfect() -> TestResult {
        let name = #function
        let rate = PayrollCalculator.attendanceRate(daysWorked: 22, expectedDays: 22)
        return approxEqual(rate, 100.0)
            ? .success(name)
            : .failure(name, "22/22 days should be 100%, got \(rate)")
    }
    
    private static func test_attendanceRate_partial() -> TestResult {
        let name = #function
        // 20/22 = 90.9%
        let rate = PayrollCalculator.attendanceRate(daysWorked: 20, expectedDays: 22)
        return approxEqual(rate, 90.91)
            ? .success(name)
            : .failure(name, "20/22 days should be ~90.91%, got \(rate)")
    }
    
    private static func test_attendanceRate_zeroDays() -> TestResult {
        let name = #function
        let rate = PayrollCalculator.attendanceRate(daysWorked: 0, expectedDays: 0)
        return approxEqual(rate, 0.0)
            ? .success(name)
            : .failure(name, "0/0 days should return 0%, got \(rate)")
    }
    
    // MARK: - Working Days
    
    private static func test_workingDays_june2026() -> TestResult {
        let name = #function
        // June 2026: starts Monday 1st, 30 days
        // Mon-Fri count = 22 working days
        let days = PayrollCalculator.workingDaysInMonth(year: 2026, month: 6)
        return days == 22
            ? .success(name)
            : .failure(name, "June 2026 should have 22 working days, got \(days)")
    }
    
    // MARK: - Edge Cases
    
    private static func test_netPay_zeroHoursHourlyEmployee() -> TestResult {
        let name = #function
        // Hourly employee with 0 hours worked
        let basePay = PayrollCalculator.hourlyBasePay(hourlyRate: 75, totalHours: 0)
        let ssf = PayrollCalculator.socialSecurityContribution(totalIncome: basePay)
        let net = PayrollCalculator.netPay(basePay: basePay, otPay: 0, socialSecurity: ssf)
        return approxEqual(net, 0.0)
            ? .success(name)
            : .failure(name, "Zero hours should yield 0 net pay, got \(net)")
    }
    
    private static func test_otPay_doubleRate() -> TestResult {
        let name = #function
        // Holiday OT at 2x rate: 75 THB/h × 2.0 × 10h = 1500
        let ot = PayrollCalculator.hourlyOTPay(hourlyRate: 75, otHours: 10, multiplier: 2.0)
        return approxEqual(ot, 1500.0)
            ? .success(name)
            : .failure(name, "Holiday OT (2x) for 10h at 75/h should be 1500, got \(ot)")
    }
}
