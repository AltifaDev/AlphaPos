import Foundation

enum InventoryComplianceTests {
    static func runAll() -> [TestResult] {
        [testPackConversion(), testRecountPolicy(), testSegregationOfDuties(),
         testSupplierScorecard(), testInventoryAccuracy(), testMutationRBAC()]
    }

    private static func testPackConversion() -> TestResult {
        let name = #function
        guard InventoryCompliancePolicy.convertedQuantity(3, multiplier: 24) == 72 else {
            return .failure(name, "3 cases x 24 must equal 72 bottles")
        }
        guard InventoryCompliancePolicy.convertedQuantity(3, multiplier: 0) == nil else {
            return .failure(name, "zero conversion must be rejected")
        }
        return .success(name)
    }

    private static func testRecountPolicy() -> TestResult {
        let name = #function
        guard InventoryCompliancePolicy.requiresRecount(systemQuantity: 100, countedQuantity: 94, thresholdPercent: 5) else {
            return .failure(name, "6% variance must require recount")
        }
        guard !InventoryCompliancePolicy.requiresRecount(systemQuantity: 100, countedQuantity: 96, thresholdPercent: 5) else {
            return .failure(name, "4% variance must not require recount")
        }
        return .success(name)
    }

    private static func testSegregationOfDuties() -> TestResult {
        let name = #function
        let counter = UUID(), approver = UUID()
        guard InventoryCompliancePolicy.canApproveCount(counterId: counter, approverId: approver),
              !InventoryCompliancePolicy.canApproveCount(counterId: counter, approverId: counter) else {
            return .failure(name, "counter must not approve their own count")
        }
        return .success(name)
    }

    private static func testSupplierScorecard() -> TestResult {
        let name = #function
        let result = InventoryComplianceAnalytics.supplierScorecard([
            .init(accepted: true, packagingPassed: true, temperatureCompliant: true, receivedQuantity: 10, rejectedQuantity: 0, deliveredOnTime: true),
            .init(accepted: false, packagingPassed: false, temperatureCompliant: false, receivedQuantity: 8, rejectedQuantity: 2, deliveredOnTime: false)
        ])
        guard result.acceptanceRatePercent == 50, result.rejectedQuantity == 2,
              result.temperatureCompliancePercent == 50 else {
            return .failure(name, "supplier scorecard aggregation is incorrect")
        }
        return .success(name)
    }

    private static func testInventoryAccuracy() -> TestResult {
        let name = #function
        let result = InventoryComplianceAnalytics.inventoryAccuracy(lines: [
            (system: 10, counted: 10, unitCost: 5),
            (system: 10, counted: 8, unitCost: 5)
        ], tolerance: 0.5)
        guard result.lineAccuracyPercent == 50, result.absoluteQuantityVariance == 2,
              result.absoluteValueVariance == 10 else {
            return .failure(name, "inventory accuracy calculation is incorrect")
        }
        return .success(name)
    }

    private static func testMutationRBAC() -> TestResult {
        let name = #function
        guard InventoryMutationAuthorization.isAuthorized(action: .transfer, permissionKeys: ["inventory.transfer"]),
              !InventoryMutationAuthorization.isAuthorized(action: .startRecall, permissionKeys: ["inventory.transfer"]) else {
            return .failure(name, "inventory actions must require granular permissions")
        }
        return .success(name)
    }
}
