// ExpenseTests.swift
// AlphaPos — Automated Unit Test Suite for Expense Tracking
//
// Tests expense calculations and aggregation logic (pure; no SwiftData dependency)

import Foundation

struct MockExpense {
    let id: UUID
    let invoiceNo: String?
    let title: String
    let category: String
    let quantity: Double
    let unit: String?
    let unitPrice: Double
    let amount: Double
    let vatRate: Double
    let vatAmount: Double
    let paymentMethod: String
    let status: String
    let isCapEx: Bool
    let date: Date
    let isDeleted: Bool
}

enum ExpenseCalculator {
    /// Calculate total amount for expenses logged today.
    static func todayTotal(expenses: [MockExpense], today: Date) -> Double {
        let calendar = Calendar.current
        return expenses.filter { !$0.isDeleted && calendar.isDate($0.date, inSameDayAs: today) }
            .reduce(0.0) { $0 + $1.amount }
    }
    
    /// Calculate total amount for expenses logged in the target month.
    static func monthlyTotal(expenses: [MockExpense], forMonthOf date: Date) -> Double {
        let calendar = Calendar.current
        return expenses.filter { !$0.isDeleted && calendar.isDate($0.date, equalTo: date, toGranularity: .month) }
            .reduce(0.0) { $0 + $1.amount }
    }
    
    /// Calculate total amount for CapEx expenses in the target month.
    static func monthlyCapExTotal(expenses: [MockExpense], forMonthOf date: Date) -> Double {
        let calendar = Calendar.current
        return expenses.filter { !$0.isDeleted && $0.isCapEx && calendar.isDate($0.date, equalTo: date, toGranularity: .month) }
            .reduce(0.0) { $0 + $1.amount }
    }
    
    /// Calculate total amount for OpEx expenses in the target month.
    static func monthlyOpExTotal(expenses: [MockExpense], forMonthOf date: Date) -> Double {
        let calendar = Calendar.current
        return expenses.filter { !$0.isDeleted && !$0.isCapEx && calendar.isDate($0.date, equalTo: date, toGranularity: .month) }
            .reduce(0.0) { $0 + $1.amount }
    }
    
    /// Calculate category breakdown for expenses logged in the target month.
    static func categoryTotals(expenses: [MockExpense], forMonthOf date: Date) -> [String: Double] {
        let calendar = Calendar.current
        let monthly = expenses.filter { !$0.isDeleted && calendar.isDate($0.date, equalTo: date, toGranularity: .month) }
        
        var totals = [
            "Raw Materials": 0.0,
            "Equipment": 0.0,
            "Consumables": 0.0,
            "Maintenance": 0.0,
            "Other": 0.0
        ]
        
        for exp in monthly {
            if totals[exp.category] != nil {
                totals[exp.category, default: 0.0] += exp.amount
            } else {
                totals["Other", default: 0.0] += exp.amount
            }
        }
        
        return totals
    }
    
    /// Pure logic to calculate VAT and totals based on tax option.
    /// taxOption: 0 = None, 1 = 7% Inclusive, 2 = 7% Exclusive
    static func calculateVATAndTotal(qty: Double, price: Double, taxOption: Int) -> (subtotal: Double, vat: Double, total: Double) {
        let baseAmount = qty * price
        switch taxOption {
        case 1: // 7% Inclusive
            let total = baseAmount
            let vat = total - (total / 1.07)
            let subtotal = total - vat
            return (subtotal, vat, total)
        case 2: // 7% Exclusive
            let subtotal = baseAmount
            let vat = subtotal * 0.07
            let total = subtotal + vat
            return (subtotal, vat, total)
        default: // None
            return (baseAmount, 0.0, baseAmount)
        }
    }
}

// MARK: - Tests

private let ε = 1e-9
private func approxEqual(_ a: Double, _ b: Double) -> Bool {
    abs(a - b) < ε
}

enum ExpenseTests {
    
    static func runAll() -> [TestResult] {
        [
            test_todayTotal_emptyExpenses(),
            test_todayTotal_sumsCorrectly(),
            test_todayTotal_ignoresOtherDays(),
            test_todayTotal_ignoresDeleted(),
            
            test_monthlyTotal_emptyExpenses(),
            test_monthlyTotal_sumsCorrectly(),
            test_monthlyTotal_ignoresOtherMonths(),
            test_monthlyTotal_ignoresDeleted(),
            
            test_categoryTotals_breaksDownCorrectly(),
            test_categoryTotals_otherCategoryFallback(),
            
            test_monthlyCapExAndOpEx_totalsSeperated(),
            test_calculateVATAndTotal_noTax(),
            test_calculateVATAndTotal_taxInclusive(),
            test_calculateVATAndTotal_taxExclusive()
        ]
    }
    
    // MARK: - Daily Expenses Tests
    
    private static func test_todayTotal_emptyExpenses() -> TestResult {
        let name = #function
        let result = ExpenseCalculator.todayTotal(expenses: [], today: Date())
        return approxEqual(result, 0.0)
            ? .success(name)
            : .failure(name, "Expected 0.0 for empty list, got \(result)")
    }
    
    private static func test_todayTotal_sumsCorrectly() -> TestResult {
        let name = #function
        let today = Date()
        let items = [
            MockExpense(id: UUID(), invoiceNo: "INV001", title: "Paper Bags", category: "Consumables", quantity: 5.0, unit: "packs", unitPrice: 30.0, amount: 150.0, vatRate: 0.0, vatAmount: 0.0, paymentMethod: "Cash", status: "Paid", isCapEx: false, date: today, isDeleted: false),
            MockExpense(id: UUID(), invoiceNo: "INV002", title: "Coffee Beans", category: "Raw Materials", quantity: 3.0, unit: "kg", unitPrice: 150.0, amount: 450.0, vatRate: 0.0, vatAmount: 0.0, paymentMethod: "Cash", status: "Paid", isCapEx: false, date: today, isDeleted: false)
        ]
        let result = ExpenseCalculator.todayTotal(expenses: items, today: today)
        return approxEqual(result, 600.0)
            ? .success(name)
            : .failure(name, "Expected 600.0, got \(result)")
    }
    
    private static func test_todayTotal_ignoresOtherDays() -> TestResult {
        let name = #function
        let today = Date()
        let yesterday = calendarAddDays(today, -1)
        let items = [
            MockExpense(id: UUID(), invoiceNo: "INV001", title: "Today Bags", category: "Consumables", quantity: 5.0, unit: "packs", unitPrice: 30.0, amount: 150.0, vatRate: 0.0, vatAmount: 0.0, paymentMethod: "Cash", status: "Paid", isCapEx: false, date: today, isDeleted: false),
            MockExpense(id: UUID(), invoiceNo: "INV002", title: "Yesterday Beans", category: "Raw Materials", quantity: 3.0, unit: "kg", unitPrice: 150.0, amount: 450.0, vatRate: 0.0, vatAmount: 0.0, paymentMethod: "Cash", status: "Paid", isCapEx: false, date: yesterday, isDeleted: false)
        ]
        let result = ExpenseCalculator.todayTotal(expenses: items, today: today)
        return approxEqual(result, 150.0)
            ? .success(name)
            : .failure(name, "Expected 150.0, got \(result)")
    }
    
    private static func test_todayTotal_ignoresDeleted() -> TestResult {
        let name = #function
        let today = Date()
        let items = [
            MockExpense(id: UUID(), invoiceNo: "INV001", title: "Regular Bags", category: "Consumables", quantity: 5.0, unit: "packs", unitPrice: 30.0, amount: 150.0, vatRate: 0.0, vatAmount: 0.0, paymentMethod: "Cash", status: "Paid", isCapEx: false, date: today, isDeleted: false),
            MockExpense(id: UUID(), invoiceNo: "INV002", title: "Deleted Chairs", category: "Equipment", quantity: 1.0, unit: "pcs", unitPrice: 1200.0, amount: 1200.0, vatRate: 0.0, vatAmount: 0.0, paymentMethod: "Cash", status: "Paid", isCapEx: true, date: today, isDeleted: true)
        ]
        let result = ExpenseCalculator.todayTotal(expenses: items, today: today)
        return approxEqual(result, 150.0)
            ? .success(name)
            : .failure(name, "Expected 150.0 (ignoring deleted), got \(result)")
    }
    
    // MARK: - Monthly Expenses Tests
    
    private static func test_monthlyTotal_emptyExpenses() -> TestResult {
        let name = #function
        let result = ExpenseCalculator.monthlyTotal(expenses: [], forMonthOf: Date())
        return approxEqual(result, 0.0)
            ? .success(name)
            : .failure(name, "Expected 0.0, got \(result)")
    }
    
    private static func test_monthlyTotal_sumsCorrectly() -> TestResult {
        let name = #function
        let now = Date()
        let items = [
            MockExpense(id: UUID(), invoiceNo: "INV001", title: "Bags", category: "Consumables", quantity: 2.0, unit: "packs", unitPrice: 100.0, amount: 200.0, vatRate: 0.0, vatAmount: 0.0, paymentMethod: "Cash", status: "Paid", isCapEx: false, date: now, isDeleted: false),
            MockExpense(id: UUID(), invoiceNo: "INV002", title: "Chairs", category: "Equipment", quantity: 1.0, unit: "pcs", unitPrice: 3000.0, amount: 3000.0, vatRate: 0.0, vatAmount: 0.0, paymentMethod: "Cash", status: "Paid", isCapEx: true, date: now, isDeleted: false)
        ]
        let result = ExpenseCalculator.monthlyTotal(expenses: items, forMonthOf: now)
        return approxEqual(result, 3200.0)
            ? .success(name)
            : .failure(name, "Expected 3200.0, got \(result)")
    }
    
    private static func test_monthlyTotal_ignoresOtherMonths() -> TestResult {
        let name = #function
        let now = Date()
        let twoMonthsAgo = calendarAddMonths(now, -2)
        let items = [
            MockExpense(id: UUID(), invoiceNo: "INV001", title: "Bags", category: "Consumables", quantity: 2.0, unit: "packs", unitPrice: 100.0, amount: 200.0, vatRate: 0.0, vatAmount: 0.0, paymentMethod: "Cash", status: "Paid", isCapEx: false, date: now, isDeleted: false),
            MockExpense(id: UUID(), invoiceNo: "INV002", title: "Chairs", category: "Equipment", quantity: 1.0, unit: "pcs", unitPrice: 3000.0, amount: 3000.0, vatRate: 0.0, vatAmount: 0.0, paymentMethod: "Cash", status: "Paid", isCapEx: true, date: twoMonthsAgo, isDeleted: false)
        ]
        let result = ExpenseCalculator.monthlyTotal(expenses: items, forMonthOf: now)
        return approxEqual(result, 200.0)
            ? .success(name)
            : .failure(name, "Expected 200.0 (ignoring two months ago), got \(result)")
    }
    
    private static func test_monthlyTotal_ignoresDeleted() -> TestResult {
        let name = #function
        let now = Date()
        let items = [
            MockExpense(id: UUID(), invoiceNo: "INV001", title: "Bags", category: "Consumables", quantity: 2.0, unit: "packs", unitPrice: 100.0, amount: 200.0, vatRate: 0.0, vatAmount: 0.0, paymentMethod: "Cash", status: "Paid", isCapEx: false, date: now, isDeleted: false),
            MockExpense(id: UUID(), invoiceNo: "INV002", title: "Deleted", category: "Equipment", quantity: 1.0, unit: "pcs", unitPrice: 3000.0, amount: 3000.0, vatRate: 0.0, vatAmount: 0.0, paymentMethod: "Cash", status: "Paid", isCapEx: true, date: now, isDeleted: true)
        ]
        let result = ExpenseCalculator.monthlyTotal(expenses: items, forMonthOf: now)
        return approxEqual(result, 200.0)
            ? .success(name)
            : .failure(name, "Expected 200.0 (ignoring deleted), got \(result)")
    }
    
    // MARK: - Category Breakdown Tests
    
    private static func test_categoryTotals_breaksDownCorrectly() -> TestResult {
        let name = #function
        let now = Date()
        let items = [
            MockExpense(id: UUID(), invoiceNo: "INV001", title: "Coffee Beans", category: "Raw Materials", quantity: 10.0, unit: "kg", unitPrice: 100.0, amount: 1000.0, vatRate: 0.0, vatAmount: 0.0, paymentMethod: "Cash", status: "Paid", isCapEx: false, date: now, isDeleted: false),
            MockExpense(id: UUID(), invoiceNo: "INV002", title: "Wooden Desk", category: "Equipment", quantity: 1.0, unit: "pcs", unitPrice: 5000.0, amount: 5000.0, vatRate: 0.0, vatAmount: 0.0, paymentMethod: "Cash", status: "Paid", isCapEx: true, date: now, isDeleted: false),
            MockExpense(id: UUID(), invoiceNo: "INV003", title: "Plates", category: "Equipment", quantity: 25.0, unit: "pcs", unitPrice: 100.0, amount: 2500.0, vatRate: 0.0, vatAmount: 0.0, paymentMethod: "Cash", status: "Paid", isCapEx: true, date: now, isDeleted: false),
            MockExpense(id: UUID(), invoiceNo: "INV004", title: "Plasters", category: "Maintenance", quantity: 3.0, unit: "packs", unitPrice: 50.0, amount: 150.0, vatRate: 0.0, vatAmount: 0.0, paymentMethod: "Cash", status: "Paid", isCapEx: false, date: now, isDeleted: false)
        ]
        let breakdown = ExpenseCalculator.categoryTotals(expenses: items, forMonthOf: now)
        let rawMat = breakdown["Raw Materials"] ?? 0.0
        let equip = breakdown["Equipment"] ?? 0.0
        let maint = breakdown["Maintenance"] ?? 0.0
        let consume = breakdown["Consumables"] ?? 0.0
        
        return approxEqual(rawMat, 1000.0) && approxEqual(equip, 7500.0) && approxEqual(maint, 150.0) && approxEqual(consume, 0.0)
            ? .success(name)
            : .failure(name, "Incorrect breakdown: Raw Materials=\(rawMat), Equipment=\(equip), Maintenance=\(maint), Consumables=\(consume)")
    }
    
    private static func test_categoryTotals_otherCategoryFallback() -> TestResult {
        let name = #function
        let now = Date()
        let items = [
            MockExpense(id: UUID(), invoiceNo: "INV001", title: "Random Fees", category: "Unexpected Category", quantity: 1.0, unit: "pcs", unitPrice: 450.0, amount: 450.0, vatRate: 0.0, vatAmount: 0.0, paymentMethod: "Cash", status: "Paid", isCapEx: false, date: now, isDeleted: false)
        ]
        let breakdown = ExpenseCalculator.categoryTotals(expenses: items, forMonthOf: now)
        let other = breakdown["Other"] ?? 0.0
        return approxEqual(other, 450.0)
            ? .success(name)
            : .failure(name, "Expected 450.0 fallback to Other, got \(other)")
    }
    
    // MARK: - Advanced Redesign Tests (CapEx/OpEx & VAT)
    
    private static func test_monthlyCapExAndOpEx_totalsSeperated() -> TestResult {
        let name = #function
        let now = Date()
        let items = [
            MockExpense(id: UUID(), invoiceNo: "INV001", title: "Chair (Asset)", category: "Equipment", quantity: 2.0, unit: "pcs", unitPrice: 500.0, amount: 1000.0, vatRate: 0.0, vatAmount: 0.0, paymentMethod: "Cash", status: "Paid", isCapEx: true, date: now, isDeleted: false),
            MockExpense(id: UUID(), invoiceNo: "INV002", title: "Paper Cups (OpEx)", category: "Consumables", quantity: 1.0, unit: "box", unitPrice: 400.0, amount: 400.0, vatRate: 0.0, vatAmount: 0.0, paymentMethod: "Cash", status: "Paid", isCapEx: false, date: now, isDeleted: false),
            MockExpense(id: UUID(), invoiceNo: "INV003", title: "Stove (Asset)", category: "Equipment", quantity: 1.0, unit: "pcs", unitPrice: 2000.0, amount: 2000.0, vatRate: 0.0, vatAmount: 0.0, paymentMethod: "Cash", status: "Paid", isCapEx: true, date: now, isDeleted: false)
        ]
        let capEx = ExpenseCalculator.monthlyCapExTotal(expenses: items, forMonthOf: now)
        let opEx = ExpenseCalculator.monthlyOpExTotal(expenses: items, forMonthOf: now)
        
        return approxEqual(capEx, 3000.0) && approxEqual(opEx, 400.0)
            ? .success(name)
            : .failure(name, "Expected CapEx=3000.0, OpEx=400.0. Got CapEx=\(capEx), OpEx=\(opEx)")
    }
    
    private static func test_calculateVATAndTotal_noTax() -> TestResult {
        let name = #function
        let calc = ExpenseCalculator.calculateVATAndTotal(qty: 10.0, price: 100.0, taxOption: 0)
        return approxEqual(calc.subtotal, 1000.0) && approxEqual(calc.vat, 0.0) && approxEqual(calc.total, 1000.0)
            ? .success(name)
            : .failure(name, "Expected subtotal=1000, vat=0, total=1000. Got \(calc)")
    }
    
    private static func test_calculateVATAndTotal_taxInclusive() -> TestResult {
        let name = #function
        let calc = ExpenseCalculator.calculateVATAndTotal(qty: 1.0, price: 107.0, taxOption: 1)
        return approxEqual(calc.total, 107.0) && approxEqual(calc.vat, 7.0) && approxEqual(calc.subtotal, 100.0)
            ? .success(name)
            : .failure(name, "Expected subtotal=100, vat=7, total=107. Got \(calc)")
    }
    
    private static func test_calculateVATAndTotal_taxExclusive() -> TestResult {
        let name = #function
        let calc = ExpenseCalculator.calculateVATAndTotal(qty: 1.0, price: 100.0, taxOption: 2)
        return approxEqual(calc.subtotal, 100.0) && approxEqual(calc.vat, 7.0) && approxEqual(calc.total, 107.0)
            ? .success(name)
            : .failure(name, "Expected subtotal=100, vat=7, total=107. Got \(calc)")
    }
    
    // MARK: - Date Helpers
    
    private static func calendarAddDays(_ date: Date, _ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: date) ?? date
    }
    
    private static func calendarAddMonths(_ date: Date, _ months: Int) -> Date {
        Calendar.current.date(byAdding: .month, value: months, to: date) ?? date
    }
}
