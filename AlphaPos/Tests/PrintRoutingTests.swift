// PrintRoutingTests.swift
// AlphaPos — Printer routing & web-order confirmation gate tests
//
// Exercises PrintRoutingGate — the pure decision helpers behind:
//   • Single-Printer Mode        — route every job to one printer (testing / broken station)
//   • Receipt fallback           — station job prints on the receipt printer when no station printer exists
//   • Category-rule application   — per-category rules only apply to a real station printer
//   • Web-order staff confirmation— web orders don't print until staff confirm
//   • Approving-device print gate — only the station device prints on approval (no cross-device double-print)

import Foundation


// Under the standalone swiftc test build (run_tests.sh compiles with
// -D TEST_RUNNER and does NOT include the SwiftData-dependent production
// PrintPipeline.swift), provide a mirror of the pure gate so the logic can be
// exercised in isolation. This mirror MUST stay byte-for-byte equivalent to the
// production PrintRoutingGate in Core/Print/PrintPipeline.swift.
#if TEST_RUNNER
enum PrintRoutingGate {
    static func respondsToPrepTrigger(
        trigger: String,
        isQuickService: Bool,
        printOnOrderValues: [Bool],
        printOnPaymentValues: [Bool]
    ) -> Bool {
        if trigger == "legacy" { return true }
        if isQuickService && trigger == "onPayment" { return true }
        if printOnOrderValues.isEmpty && printOnPaymentValues.isEmpty {
            return trigger == "onOrder"
        }
        switch trigger {
        case "onOrder": return printOnOrderValues.contains(true)
        case "onPayment": return printOnPaymentValues.contains(true)
        default: return false
        }
    }

    static func candidateRoles(
        forStation station: String,
        hasStationPrinter: Bool,
        hasReceiptPrinter: Bool,
        singlePrinterMode: Bool,
        roleFallback: Bool
    ) -> [String] {
        if singlePrinterMode {
            return ["*"]
        }
        if hasStationPrinter {
            return [station]
        }
        if roleFallback, station != "receipt", hasReceiptPrinter {
            return ["receipt"]
        }
        return []
    }

    static func shouldApplyCategoryRules(
        printerRole: String,
        stationRole: String,
        hasActiveRules: Bool
    ) -> Bool {
        printerRole == stationRole && hasActiveRules
    }

    static func kitchenPrintAllowed(
        orderSource: String,
        isStaffConfirmed: Bool
    ) -> Bool {
        orderSource != "web" || isStaffConfirmed
    }

    static func approvingDeviceShouldPrint(isThisDeviceStation: Bool) -> Bool {
        isThisDeviceStation
    }
}
#endif

enum PrintRoutingTests {

    static func runAll() -> [TestResult] {
        [
            // Single-printer mode
            test_singlePrinterModeRoutesEverythingToStar(),
            test_singlePrinterModeOverridesMissingStation(),
            test_quickServiceLegacyRulePrintsAfterPayment(),
            test_quickServiceReceiptFallbackPrintsAfterPayment(),
            test_tableServiceStillRespectsPaymentFlag(),
            // Strict per-role
            test_strictRoleMatchWhenStationPrinterExists(),
            test_noPrinterWhenStationMissingAndNoFallback(),
            // Receipt fallback
            test_fallbackToReceiptWhenStationMissing(),
            test_noFallbackWhenReceiptMissing(),
            test_receiptStationNeverFallsBackToItself(),
            // Category rules
            test_categoryRulesApplyOnMatchingStationPrinter(),
            test_categoryRulesSkippedOnFallbackPrinter(),
            test_categoryRulesSkippedWhenNoRules(),
            // Web-order staff confirmation
            test_webOrderBlockedUntilConfirmed(),
            test_webOrderPrintsAfterConfirmed(),
            test_posOrderAlwaysPrints(),
            test_staffOrderAlwaysPrints(),
            // Approving-device double-print guard
            test_stationDevicePrintsOnApproval(),
            test_nonStationDeviceDefersOnApproval(),
        ]
    }

    // ── Single-printer mode ──────────────────────────────────────────────

    private static func test_quickServiceLegacyRulePrintsAfterPayment() -> TestResult {
        let name = #function
        let responds = PrintRoutingGate.respondsToPrepTrigger(
            trigger: "onPayment", isQuickService: true,
            printOnOrderValues: [true], printOnPaymentValues: [false]
        )
        return responds
            ? .success(name)
            : .failure(name, "Quick Service must migrate legacy on-order prep rules at runtime.")
    }

    private static func test_quickServiceReceiptFallbackPrintsAfterPayment() -> TestResult {
        let name = #function
        let responds = PrintRoutingGate.respondsToPrepTrigger(
            trigger: "onPayment", isQuickService: true,
            printOnOrderValues: [], printOnPaymentValues: []
        )
        return responds
            ? .success(name)
            : .failure(name, "A receipt-only fallback printer must print the Quick Service prep ticket.")
    }

    private static func test_tableServiceStillRespectsPaymentFlag() -> TestResult {
        let name = #function
        let responds = PrintRoutingGate.respondsToPrepTrigger(
            trigger: "onPayment", isQuickService: false,
            printOnOrderValues: [true], printOnPaymentValues: [false]
        )
        return responds == false
            ? .success(name)
            : .failure(name, "Table Service must not reprint prep tickets at payment unless configured.")
    }

    private static func test_singlePrinterModeRoutesEverythingToStar() -> TestResult {
        let name = #function
        let roles = PrintRoutingGate.candidateRoles(
            forStation: "kitchen", hasStationPrinter: true, hasReceiptPrinter: true,
            singlePrinterMode: true, roleFallback: false
        )
        return roles == ["*"]
            ? .success(name)
            : .failure(name, "Single-printer mode must collapse to [\"*\"]; got \(roles).")
    }

    private static func test_singlePrinterModeOverridesMissingStation() -> TestResult {
        let name = #function
        // Even with no kitchen printer, single-printer mode still returns "*".
        let roles = PrintRoutingGate.candidateRoles(
            forStation: "kitchen", hasStationPrinter: false, hasReceiptPrinter: true,
            singlePrinterMode: true, roleFallback: false
        )
        return roles == ["*"]
            ? .success(name)
            : .failure(name, "Single-printer mode should apply regardless of station presence; got \(roles).")
    }

    // ── Strict per-role match ────────────────────────────────────────────

    private static func test_strictRoleMatchWhenStationPrinterExists() -> TestResult {
        let name = #function
        let roles = PrintRoutingGate.candidateRoles(
            forStation: "kitchen", hasStationPrinter: true, hasReceiptPrinter: true,
            singlePrinterMode: false, roleFallback: true
        )
        return roles == ["kitchen"]
            ? .success(name)
            : .failure(name, "Must use the station's own printer when present; got \(roles).")
    }

    private static func test_noPrinterWhenStationMissingAndNoFallback() -> TestResult {
        let name = #function
        let roles = PrintRoutingGate.candidateRoles(
            forStation: "kitchen", hasStationPrinter: false, hasReceiptPrinter: true,
            singlePrinterMode: false, roleFallback: false
        )
        return roles.isEmpty
            ? .success(name)
            : .failure(name, "No station printer + fallback off ⇒ nothing prints; got \(roles).")
    }

    // ── Receipt fallback ─────────────────────────────────────────────────

    private static func test_fallbackToReceiptWhenStationMissing() -> TestResult {
        let name = #function
        let roles = PrintRoutingGate.candidateRoles(
            forStation: "kitchen", hasStationPrinter: false, hasReceiptPrinter: true,
            singlePrinterMode: false, roleFallback: true
        )
        return roles == ["receipt"]
            ? .success(name)
            : .failure(name, "Kitchen job should fall back to the receipt printer; got \(roles).")
    }

    private static func test_noFallbackWhenReceiptMissing() -> TestResult {
        let name = #function
        let roles = PrintRoutingGate.candidateRoles(
            forStation: "bar", hasStationPrinter: false, hasReceiptPrinter: false,
            singlePrinterMode: false, roleFallback: true
        )
        return roles.isEmpty
            ? .success(name)
            : .failure(name, "Fallback needs a receipt printer to exist; got \(roles).")
    }

    private static func test_receiptStationNeverFallsBackToItself() -> TestResult {
        let name = #function
        // A receipt run with no receipt printer must not "fall back" to receipt.
        let roles = PrintRoutingGate.candidateRoles(
            forStation: "receipt", hasStationPrinter: false, hasReceiptPrinter: false,
            singlePrinterMode: false, roleFallback: true
        )
        return roles.isEmpty
            ? .success(name)
            : .failure(name, "Receipt station must not fall back to itself; got \(roles).")
    }

    // ── Category-rule application ────────────────────────────────────────

    private static func test_categoryRulesApplyOnMatchingStationPrinter() -> TestResult {
        let name = #function
        let apply = PrintRoutingGate.shouldApplyCategoryRules(
            printerRole: "kitchen", stationRole: "kitchen", hasActiveRules: true
        )
        return apply
            ? .success(name)
            : .failure(name, "Category rules should apply on a matching station printer with rules.")
    }

    private static func test_categoryRulesSkippedOnFallbackPrinter() -> TestResult {
        let name = #function
        // Fallback: printer is "receipt" but the run represents the "kitchen" station.
        let apply = PrintRoutingGate.shouldApplyCategoryRules(
            printerRole: "receipt", stationRole: "kitchen", hasActiveRules: true
        )
        return apply == false
            ? .success(name)
            : .failure(name, "Fallback/aggregated printer must ignore category rules (print everything).")
    }

    private static func test_categoryRulesSkippedWhenNoRules() -> TestResult {
        let name = #function
        let apply = PrintRoutingGate.shouldApplyCategoryRules(
            printerRole: "kitchen", stationRole: "kitchen", hasActiveRules: false
        )
        return apply == false
            ? .success(name)
            : .failure(name, "With no active rules, all station items pass through.")
    }

    // ── Web-order staff confirmation ─────────────────────────────────────

    private static func test_webOrderBlockedUntilConfirmed() -> TestResult {
        let name = #function
        let allowed = PrintRoutingGate.kitchenPrintAllowed(
            orderSource: "web", isStaffConfirmed: false
        )
        return allowed == false
            ? .success(name)
            : .failure(name, "Unconfirmed web order must NOT print to the kitchen.")
    }

    private static func test_webOrderPrintsAfterConfirmed() -> TestResult {
        let name = #function
        let allowed = PrintRoutingGate.kitchenPrintAllowed(
            orderSource: "web", isStaffConfirmed: true
        )
        return allowed
            ? .success(name)
            : .failure(name, "A staff-confirmed web order should print.")
    }

    private static func test_posOrderAlwaysPrints() -> TestResult {
        let name = #function
        // POS orders are staff-initiated; confirmation flag is irrelevant.
        let allowed = PrintRoutingGate.kitchenPrintAllowed(
            orderSource: "pos", isStaffConfirmed: false
        )
        return allowed
            ? .success(name)
            : .failure(name, "POS orders must always be allowed to print.")
    }

    private static func test_staffOrderAlwaysPrints() -> TestResult {
        let name = #function
        let allowed = PrintRoutingGate.kitchenPrintAllowed(
            orderSource: "staff", isStaffConfirmed: false
        )
        return allowed
            ? .success(name)
            : .failure(name, "Staff (iPhone) orders must always be allowed to print.")
    }

    // ── Approving-device double-print guard ──────────────────────────────

    private static func test_stationDevicePrintsOnApproval() -> TestResult {
        let name = #function
        let prints = PrintRoutingGate.approvingDeviceShouldPrint(isThisDeviceStation: true)
        return prints
            ? .success(name)
            : .failure(name, "The station device should print directly on approval.")
    }

    private static func test_nonStationDeviceDefersOnApproval() -> TestResult {
        let name = #function
        // A non-station device only flips the flag + syncs; the station iPad
        // prints via the realtime handler — prevents cross-device double-print.
        let prints = PrintRoutingGate.approvingDeviceShouldPrint(isThisDeviceStation: false)
        return prints == false
            ? .success(name)
            : .failure(name, "A non-station device must defer printing to the station iPad.")
    }

}
