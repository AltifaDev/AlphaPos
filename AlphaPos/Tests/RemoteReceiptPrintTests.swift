// RemoteReceiptPrintTests.swift
// AlphaPos — Remote Receipt Printing decision-gate tests
//
// Verifies RemoteReceiptPrintGate.shouldPrint — the pure predicate that decides
// whether this iPad prints a receipt when a staff phone takes payment.
//
// The four inputs mirror the three production safeguards:
//   • isStationEnabled — multi-iPad double-print guard (only ONE iPad prints)
//   • orderExists      — the order synced down and is not deleted
//   • hasLiveItems     — order_items finished syncing (avoids blank receipts)
//   • isCompleted      — bill fully settled (split/mixed → single final print)

import Foundation

// Under the standalone swiftc test build (run_tests.sh compiles with
// -D TEST_RUNNER and does NOT include the SwiftData-dependent production file),
// provide a mirror of the pure gate so the logic can be exercised in isolation.
// This mirror MUST stay byte-for-byte equivalent to the production
// RemoteReceiptPrintGate.shouldPrint in SyncEngine+RemoteReceiptPrint.swift.
#if TEST_RUNNER
enum RemoteReceiptPrintGate {
    static func shouldPrint(
        isStationEnabled: Bool,
        orderExists: Bool,
        hasLiveItems: Bool,
        isCompleted: Bool
    ) -> Bool {
        isStationEnabled && orderExists && hasLiveItems && isCompleted
    }

    static func shouldPrintKitchen(
        isStationEnabled: Bool,
        orderActive: Bool,
        hasUnprintedCookingItem: Bool
    ) -> Bool {
        isStationEnabled && orderActive && hasUnprintedCookingItem
    }
}
#endif

enum RemoteReceiptPrintTests {

    static func runAll() -> [TestResult] {
        [
            test_printsWhenAllConditionsMet(),
            test_skipsWhenStationDisabled(),
            test_skipsWhenOrderMissing(),
            test_skipsWhenNoItemsYet(),
            test_skipsWhenNotCompleted(),
            test_skipsPartialSplitPayment(),
            test_onlyOneStationPrintsAcrossDevices(),
            test_kitchenPrintsWhenActiveWithUnprintedItems(),
            test_kitchenSkipsWhenStationDisabled(),
            test_kitchenSkipsWhenOrderClosed(),
            test_kitchenSkipsWhenAllItemsAlreadyPrinted()
        ]
    }

    // Happy path: designated station, order present with items, and completed.
    private static func test_printsWhenAllConditionsMet() -> TestResult {
        let name = #function
        let result = RemoteReceiptPrintGate.shouldPrint(
            isStationEnabled: true, orderExists: true,
            hasLiveItems: true, isCompleted: true
        )
        return result
            ? .success(name)
            : .failure(name, "Expected print when station enabled + order present + items + completed.")
    }

    // Guard 1: a non-station iPad must never print even if everything else is ready.
    private static func test_skipsWhenStationDisabled() -> TestResult {
        let name = #function
        let result = RemoteReceiptPrintGate.shouldPrint(
            isStationEnabled: false, orderExists: true,
            hasLiveItems: true, isCompleted: true
        )
        return result == false
            ? .success(name)
            : .failure(name, "A non-station device must not print (double-print guard).")
    }

    // Order not yet synced locally.
    private static func test_skipsWhenOrderMissing() -> TestResult {
        let name = #function
        let result = RemoteReceiptPrintGate.shouldPrint(
            isStationEnabled: true, orderExists: false,
            hasLiveItems: false, isCompleted: false
        )
        return result == false
            ? .success(name)
            : .failure(name, "Must not print when the order is missing locally.")
    }

    // Guard 2: payment event beat the order_items sync — no items yet.
    private static func test_skipsWhenNoItemsYet() -> TestResult {
        let name = #function
        let result = RemoteReceiptPrintGate.shouldPrint(
            isStationEnabled: true, orderExists: true,
            hasLiveItems: false, isCompleted: true
        )
        return result == false
            ? .success(name)
            : .failure(name, "Must not print a receipt with no line items (avoids blank/partial receipt).")
    }

    // Guard 3: order present with items but not yet marked completed.
    private static func test_skipsWhenNotCompleted() -> TestResult {
        let name = #function
        let result = RemoteReceiptPrintGate.shouldPrint(
            isStationEnabled: true, orderExists: true,
            hasLiveItems: true, isCompleted: false
        )
        return result == false
            ? .success(name)
            : .failure(name, "Must not print until the order status is 'completed'.")
    }

    // Guard 3 (split/mixed): early payment fragments arrive via uploadPayment,
    // which does NOT flip status → not completed → no print. Only the final
    // completeCheckout RPC sets completed, yielding a single receipt.
    private static func test_skipsPartialSplitPayment() -> TestResult {
        let name = #function
        // Simulate two intermediate payment events (order still "preparing").
        let firstFragment = RemoteReceiptPrintGate.shouldPrint(
            isStationEnabled: true, orderExists: true,
            hasLiveItems: true, isCompleted: false
        )
        let secondFragment = RemoteReceiptPrintGate.shouldPrint(
            isStationEnabled: true, orderExists: true,
            hasLiveItems: true, isCompleted: false
        )
        // Final settling payment flips status → completed.
        let finalSettle = RemoteReceiptPrintGate.shouldPrint(
            isStationEnabled: true, orderExists: true,
            hasLiveItems: true, isCompleted: true
        )
        let printCount = [firstFragment, secondFragment, finalSettle].filter { $0 }.count
        return printCount == 1
            ? .success(name)
            : .failure(name, "Split/mixed bill should print exactly once (on final settle); got \(printCount).")
    }

    // Guard 1 (multi-device): given N iPads receiving the same event, only the
    // one with the station flag enabled prints.
    private static func test_onlyOneStationPrintsAcrossDevices() -> TestResult {
        let name = #function
        // Three iPads: only the second is the receipt station.
        let stationFlags = [false, true, false]
        let prints = stationFlags.map { enabled in
            RemoteReceiptPrintGate.shouldPrint(
                isStationEnabled: enabled, orderExists: true,
                hasLiveItems: true, isCompleted: true
            )
        }
        let total = prints.filter { $0 }.count
        return total == 1
            ? .success(name)
            : .failure(name, "Exactly one iPad should print across devices; got \(total).")
    }

    // ── Kitchen / Bar remote print (Staff iPhone / Web → iPad) ───────────────

    // Happy path: station iPad, order still active, has an unprinted cooking line.
    private static func test_kitchenPrintsWhenActiveWithUnprintedItems() -> TestResult {
        let name = #function
        let result = RemoteReceiptPrintGate.shouldPrintKitchen(
            isStationEnabled: true, orderActive: true, hasUnprintedCookingItem: true
        )
        return result
            ? .success(name)
            : .failure(name, "Expected kitchen ticket when station + active order + unprinted cooking item.")
    }

    // Guard 1: a non-station iPad must not print kitchen tickets.
    private static func test_kitchenSkipsWhenStationDisabled() -> TestResult {
        let name = #function
        let result = RemoteReceiptPrintGate.shouldPrintKitchen(
            isStationEnabled: false, orderActive: true, hasUnprintedCookingItem: true
        )
        return result == false
            ? .success(name)
            : .failure(name, "Non-station device must not print kitchen tickets.")
    }

    // Closed bill (completed/cancelled) must not re-fire kitchen tickets.
    private static func test_kitchenSkipsWhenOrderClosed() -> TestResult {
        let name = #function
        let result = RemoteReceiptPrintGate.shouldPrintKitchen(
            isStationEnabled: true, orderActive: false, hasUnprintedCookingItem: true
        )
        return result == false
            ? .success(name)
            : .failure(name, "Must not print kitchen tickets for a completed/cancelled order.")
    }

    // Guard 2: repeated realtime events with everything already printed → no reprint.
    private static func test_kitchenSkipsWhenAllItemsAlreadyPrinted() -> TestResult {
        let name = #function
        let result = RemoteReceiptPrintGate.shouldPrintKitchen(
            isStationEnabled: true, orderActive: true, hasUnprintedCookingItem: false
        )
        return result == false
            ? .success(name)
            : .failure(name, "Must not reprint when all cooking items were already printed.")
    }
}
