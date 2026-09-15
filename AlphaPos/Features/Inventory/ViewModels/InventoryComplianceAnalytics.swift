import Foundation

enum InventoryCompliancePolicy {
    static func convertedQuantity(_ quantity: Double, multiplier: Double) -> Double? {
        guard quantity.isFinite, multiplier.isFinite, quantity >= 0, multiplier > 0 else { return nil }
        return quantity * multiplier
    }

    static func requiresRecount(systemQuantity: Double, countedQuantity: Double,
                                thresholdPercent: Double) -> Bool {
        guard systemQuantity.isFinite, countedQuantity.isFinite, thresholdPercent >= 0 else { return true }
        let base = max(abs(systemQuantity), 1)
        return abs(countedQuantity - systemQuantity) / base * 100 > thresholdPercent
    }

    static func canApproveCount(counterId: UUID?, approverId: UUID?) -> Bool {
        guard let counterId, let approverId else { return false }
        return counterId != approverId
    }
}

struct SupplierInspectionMetric {
    let accepted: Bool
    let packagingPassed: Bool
    let temperatureCompliant: Bool?
    let receivedQuantity: Double
    let rejectedQuantity: Double
    let deliveredOnTime: Bool?
}

struct SupplierScorecardResult: Equatable {
    let inspectionCount: Int
    let acceptanceRatePercent: Double
    let packagingPassPercent: Double
    let temperatureCompliancePercent: Double?
    let onTimeDeliveryPercent: Double?
    let rejectedQuantity: Double
}

struct InventoryAccuracyResult: Equatable {
    let countedLines: Int
    let exactLines: Int
    let accurateLines: Int
    let lineAccuracyPercent: Double
    let absoluteQuantityVariance: Double
    let absoluteValueVariance: Double
}

enum InventoryComplianceAnalytics {
    static func supplierScorecard(_ metrics: [SupplierInspectionMetric]) -> SupplierScorecardResult {
        guard !metrics.isEmpty else {
            return SupplierScorecardResult(inspectionCount: 0, acceptanceRatePercent: 0,
                packagingPassPercent: 0, temperatureCompliancePercent: nil,
                onTimeDeliveryPercent: nil, rejectedQuantity: 0)
        }
        func percent(_ count: Int, _ total: Int) -> Double { total == 0 ? 0 : Double(count) / Double(total) * 100 }
        let temperatures = metrics.compactMap(\.temperatureCompliant)
        let delivery = metrics.compactMap(\.deliveredOnTime)
        return SupplierScorecardResult(
            inspectionCount: metrics.count,
            acceptanceRatePercent: percent(metrics.filter(\.accepted).count, metrics.count),
            packagingPassPercent: percent(metrics.filter(\.packagingPassed).count, metrics.count),
            temperatureCompliancePercent: temperatures.isEmpty ? nil : percent(temperatures.filter { $0 }.count, temperatures.count),
            onTimeDeliveryPercent: delivery.isEmpty ? nil : percent(delivery.filter { $0 }.count, delivery.count),
            rejectedQuantity: metrics.reduce(0) { $0 + max(0, $1.rejectedQuantity) }
        )
    }

    /// A line is considered accurate when its absolute variance is within the
    /// configured tolerance. Value variance always uses the line's frozen cost.
    static func inventoryAccuracy(
        lines: [(system: Double, counted: Double, unitCost: Double)],
        tolerance: Double = 0.0001
    ) -> InventoryAccuracyResult {
        guard !lines.isEmpty else {
            return InventoryAccuracyResult(countedLines: 0, exactLines: 0, accurateLines: 0,
                lineAccuracyPercent: 0, absoluteQuantityVariance: 0, absoluteValueVariance: 0)
        }
        let variances = lines.map { abs($0.counted - $0.system) }
        let exact = variances.filter { $0 <= 0.0001 }.count
        let accurate = variances.filter { $0 <= max(0, tolerance) }.count
        let valueVariance = zip(lines, variances).reduce(0.0) { $0 + $1.1 * max(0, $1.0.unitCost) }
        return InventoryAccuracyResult(
            countedLines: lines.count, exactLines: exact, accurateLines: accurate,
            lineAccuracyPercent: Double(accurate) / Double(lines.count) * 100,
            absoluteQuantityVariance: variances.reduce(0, +),
            absoluteValueVariance: valueVariance
        )
    }
}

enum InventoryMutationAction: String, CaseIterable {
    case receive, adjust, waste, returnToSupplier, transfer, count, approveCount,
         quarantine, releaseLot, startRecall, closeRecall, deletePurchaseOrder
}

enum InventoryMutationAuthorization {
    static func requiredPermissionKey(for action: InventoryMutationAction) -> String {
        switch action {
        case .receive: return "inventory.receive"
        case .adjust, .waste, .returnToSupplier: return "inventory.adjust"
        case .transfer: return "inventory.transfer"
        case .count: return "inventory.count"
        case .approveCount: return "inventory.approve"
        case .quarantine, .releaseLot, .startRecall, .closeRecall: return "inventory.recall"
        case .deletePurchaseOrder: return "inventory.approve"
        }
    }

    static func isAuthorized(action: InventoryMutationAction, permissionKeys: Set<String>) -> Bool {
        permissionKeys.contains(requiredPermissionKey(for: action))
            || permissionKeys.contains("inventory.manage")
    }
}
