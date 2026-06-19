// TestRunner.swift
// AlphaPos — Phase 4: Unit Testing Suite
//
// Aggregates all test suites and prints a formatted report to stdout.
// Call  TestRunner.runAll()  once on app launch (DEBUG only) or from
// the run_tests.sh shell script via `swift Tests/TestRunner.swift`.

import Foundation

enum TestRunner {

    // ── Public entry point ───────────────────────────────────────────────────

    @discardableResult
    static func runAll() -> Bool {

        let suites: [(name: String, results: [TestResult])] = [
            ("Security",  SecurityTests.runAll()),
            ("POS",       POSTests.runAll()),
            ("Decimal Currency", DecimalCurrencyTests.runAll()),
            ("Thread Safety", ThreadSafetyTests.runAll()),
            ("Inventory", InventoryTests.runAll()),
            ("Inventory Enhancement", InventoryEnhancementTests.runAll()),
            ("Inventory Enterprise", InventoryEnterpriseTests.runAll()),
            ("Timecard",  TimecardTests.runAll()),
            ("Payroll",   PayrollTests.runAll()),
            ("Localization", LocalizationTests.runAll())
        ]

        printHeader()

        var totalPassed = 0
        var totalFailed = 0

        for suite in suites {
            let (passed, failed) = printSuite(suite.name, results: suite.results)
            totalPassed += passed
            totalFailed += failed
        }

        printSummary(passed: totalPassed, failed: totalFailed)
        return totalFailed == 0
    }

    // ── Private formatting helpers ───────────────────────────────────────────

    private static func printHeader() {
        let line = String(repeating: "═", count: 60)
        print("\n\(line)")
        print("  AlphaPos — Automated Unit Test Runner")
        print("  \(timestamp())")
        print(line)
    }

    private static func printSuite(
        _ name: String,
        results: [TestResult]
    ) -> (passed: Int, failed: Int) {
        let passed = results.filter { $0.isPassed }.count
        let failed = results.count - passed

        print("\n  ┌─ \(name) Tests (\(results.count) tests, \(passed) passed, \(failed) failed)")

        for result in results {
            switch result {
            case .success(let testName):
                let shortName = prettify(testName)
                print("  │  ✅  \(shortName)")

            case .failure(let testName, let message):
                let shortName = prettify(testName)
                print("  │  ❌  \(shortName)")
                let indented = message
                    .split(separator: "\n", omittingEmptySubsequences: false)
                    .map { "  │        \($0)" }
                    .joined(separator: "\n")
                print(indented)
            }
        }

        print("  └─ \(passed)/\(results.count) passed")
        return (passed, failed)
    }

    private static func printSummary(passed: Int, failed: Int) {
        let total = passed + failed
        let bar   = String(repeating: "─", count: 60)
        print("\n\(bar)")
        if failed == 0 {
            print("  🎉  ALL TESTS PASSED  (\(passed)/\(total))")
        } else {
            print("  ⚠️   \(failed) TEST(S) FAILED  (\(passed)/\(total) passed)")
        }
        print(bar + "\n")
    }

    /// Strips Swift's `#function` decoration: "test_foo_bar() -> TestResult"
    /// becomes "foo bar".
    private static func prettify(_ raw: String) -> String {
        var name = raw
        if let parenIdx = name.firstIndex(of: "(") {
            name = String(name[name.startIndex ..< parenIdx])
        }
        name = name.hasPrefix("test_") ? String(name.dropFirst(5)) : name
        return name.replacingOccurrences(of: "_", with: " ")
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat  = "yyyy-MM-dd HH:mm:ss"
        f.timeZone    = TimeZone(identifier: "Asia/Bangkok")
        return f.string(from: Date()) + " (ICT)"
    }
}
