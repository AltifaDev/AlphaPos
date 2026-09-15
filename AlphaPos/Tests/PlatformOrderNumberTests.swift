import Foundation

enum PlatformOrderNumberTests {
    static func runAll() -> [TestResult] {
        [
            test_normalize_trimsAndStripsHash(),
            test_normalize_extractsFromSentence(),
            test_normalize_orderLabelPattern(),
            test_normalize_emptyStaysEmpty(),
            test_prefix_grabFood(),
            test_applyPrefix_bareNumber(),
            test_applyPrefix_alreadyPrefixed(),
            test_rebrand_switchesPrefix(),
            test_grabRequestedNumber(),
            test_receiptHeaderDisplay_deliveryShowsDeliveryNumber(),
            test_receiptHeaderDisplay_deliveryFallsBackToQueueWhenPlatformEmpty(),
            test_receiptHeaderDisplay_nonDeliveryShowsQueueNumber(),
            test_receiptHeaderDisplay_nonDeliveryReturnsNilWithoutQueue()
        ]
    }

    private static func test_grabRequestedNumber() -> TestResult {
        let name = #function
        for raw in ["777", "GP-777", "gp-777", "GF-777"] {
            guard PlatformOrderNumber.applyBrandPrefix(raw, brand: "GrabFood") == "GP-777" else {
                return .failure(name, "Grab number failed: " + raw)
            }
        }
        return .success(name)
    }

    private static func test_normalize_trimsAndStripsHash() -> TestResult {
        let name = #function
        let value = PlatformOrderNumber.normalize("  #GF-12345  ")
        return value == "GF-12345"
            ? .success(name)
            : .failure(name, "got \(value)")
    }

    private static func test_normalize_extractsFromSentence() -> TestResult {
        let name = #function
        let value = PlatformOrderNumber.normalize("New GrabFood order GF-998877 is waiting")
        return value == "GF-998877"
            ? .success(name)
            : .failure(name, "got \(value)")
    }

    private static func test_normalize_orderLabelPattern() -> TestResult {
        let name = #function
        let value = PlatformOrderNumber.normalize("Order #LM-5555 ready for pickup")
        return value == "LM-5555"
            ? .success(name)
            : .failure(name, "got \(value)")
    }

    private static func test_normalize_emptyStaysEmpty() -> TestResult {
        let name = #function
        let value = PlatformOrderNumber.normalize("   ")
        return value.isEmpty
            ? .success(name)
            : .failure(name, "expected empty, got \(value)")
    }

    private static func test_prefix_grabFood() -> TestResult {
        let name = #function
        return PlatformOrderNumber.prefix(for: "GrabFood") == "GP-"
            ? .success(name)
            : .failure(name, "expected GP-")
    }

    private static func test_applyPrefix_bareNumber() -> TestResult {
        let name = #function
        let value = PlatformOrderNumber.applyBrandPrefix("12345", brand: "GrabFood")
        return value == "GP-12345"
            ? .success(name)
            : .failure(name, "got \(value)")
    }

    private static func test_applyPrefix_alreadyPrefixed() -> TestResult {
        let name = #function
        let value = PlatformOrderNumber.applyBrandPrefix("GF-999", brand: "GrabFood")
        return value == "GP-999"
            ? .success(name)
            : .failure(name, "got \(value)")
    }

    private static func test_rebrand_switchesPrefix() -> TestResult {
        let name = #function
        let value = PlatformOrderNumber.rebrand("GF-888", to: "LINE MAN")
        return value == "LM-888"
            ? .success(name)
            : .failure(name, "got \(value)")
    }

    private static func test_receiptHeaderDisplay_deliveryShowsDeliveryNumber() -> TestResult {
        let name = #function
        let grabResult = PlatformOrderNumber.receiptHeaderDisplay(
            orderType: "delivery",
            platformOrderNumber: "GR-876",
            queueNumber: "001"
        )
        guard grabResult == "GR-876" else {
            return .failure(name, "expected GR-876, got \(grabResult ?? "nil")")
        }

        let lineManResult = PlatformOrderNumber.receiptHeaderDisplay(
            orderType: "delivery",
            platformOrderNumber: "LM-1029",
            queueNumber: nil
        )
        guard lineManResult == "LM-1029" else {
            return .failure(name, "expected LM-1029, got \(lineManResult ?? "nil")")
        }

        return .success(name)
    }

    private static func test_receiptHeaderDisplay_deliveryFallsBackToQueueWhenPlatformEmpty() -> TestResult {
        let name = #function
        let result = PlatformOrderNumber.receiptHeaderDisplay(
            orderType: "delivery",
            platformOrderNumber: "   ",
            queueNumber: "042"
        )
        return result == "คิวที่ #042"
            ? .success(name)
            : .failure(name, "expected คิวที่ #042, got \(result ?? "nil")")
    }

    private static func test_receiptHeaderDisplay_nonDeliveryShowsQueueNumber() -> TestResult {
        let name = #function
        let dineIn = PlatformOrderNumber.receiptHeaderDisplay(
            orderType: "dine_in",
            platformOrderNumber: "GR-876",
            queueNumber: "015"
        )
        guard dineIn == "คิวที่ #015" else {
            return .failure(name, "expected คิวที่ #015, got \(dineIn ?? "nil")")
        }

        let takeaway = PlatformOrderNumber.receiptHeaderDisplay(
            orderType: "take_out",
            platformOrderNumber: nil,
            queueNumber: "099"
        )
        guard takeaway == "คิวที่ #099" else {
            return .failure(name, "expected คิวที่ #099, got \(takeaway ?? "nil")")
        }

        return .success(name)
    }

    private static func test_receiptHeaderDisplay_nonDeliveryReturnsNilWithoutQueue() -> TestResult {
        let name = #function
        let result = PlatformOrderNumber.receiptHeaderDisplay(
            orderType: "dine_in",
            platformOrderNumber: nil,
            queueNumber: nil
        )
        return result == nil
            ? .success(name)
            : .failure(name, "expected nil, got \(result ?? "nil")")
    }
}
