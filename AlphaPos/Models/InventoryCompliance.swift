import Foundation
import SwiftData

enum InventoryLotDisposition: String, Codable, CaseIterable {
    case available
    case quarantined
    case released
    case rejected
    case recalled
    case destroyed
}

enum InventoryRecallStatus: String, Codable, CaseIterable {
    case draft
    case active
    case contained
    case closed
}

enum InventoryInspectionDecision: String, Codable, CaseIterable {
    case accepted
    case quarantined
    case rejected
}

enum InventoryCountStatus: String, Codable, CaseIterable {
    case draft
    case submitted
    case recountRequired = "recount_required"
    case approved
    case posted
    case rejected
}

/// Lot-level safety state kept separately from quantity so unsafe stock can be
/// blocked without destroying traceability or changing the physical balance.
@Model
final class InventoryLotControl {
    @Attribute(.unique) var id: UUID
    var lotId: UUID
    var inventoryItemId: UUID
    var branchId: UUID
    var dispositionRaw: String
    var reasonCode: String
    var notes: String?
    var decidedByEmployeeId: UUID?
    var approvedByEmployeeId: UUID?
    var decidedAt: Date
    var releasedAt: Date?
    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date

    init(id: UUID = UUID(), lotId: UUID, inventoryItemId: UUID, branchId: UUID,
         disposition: InventoryLotDisposition, reasonCode: String, notes: String? = nil,
         decidedByEmployeeId: UUID? = nil, approvedByEmployeeId: UUID? = nil,
         decidedAt: Date = Date(), releasedAt: Date? = nil,
         isSynced: Bool = false, isDeleted: Bool = false, updatedAt: Date = Date()) {
        self.id = id; self.lotId = lotId; self.inventoryItemId = inventoryItemId
        self.branchId = branchId; self.dispositionRaw = disposition.rawValue
        self.reasonCode = reasonCode; self.notes = notes
        self.decidedByEmployeeId = decidedByEmployeeId
        self.approvedByEmployeeId = approvedByEmployeeId
        self.decidedAt = decidedAt; self.releasedAt = releasedAt
        self.isSynced = isSynced; self.isDeleted = isDeleted; self.updatedAt = updatedAt
    }

    var disposition: InventoryLotDisposition {
        get { InventoryLotDisposition(rawValue: dispositionRaw) ?? .quarantined }
        set { dispositionRaw = newValue.rawValue; updatedAt = Date(); isSynced = false }
    }
}

@Model
final class InventoryRecall {
    @Attribute(.unique) var id: UUID
    var recallNumber: String
    var title: String
    var reasonCode: String
    var statusRaw: String
    var severity: String
    var initiatedByEmployeeId: UUID?
    var approvedByEmployeeId: UUID?
    var initiatedAt: Date
    var closedAt: Date?
    var correctiveAction: String?
    var effectivenessVerifiedAt: Date?
    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date

    init(id: UUID = UUID(), recallNumber: String, title: String, reasonCode: String,
         status: InventoryRecallStatus = .draft, severity: String = "medium",
         initiatedByEmployeeId: UUID? = nil, approvedByEmployeeId: UUID? = nil,
         initiatedAt: Date = Date(), closedAt: Date? = nil,
         correctiveAction: String? = nil, effectivenessVerifiedAt: Date? = nil,
         isSynced: Bool = false, isDeleted: Bool = false, updatedAt: Date = Date()) {
        self.id = id; self.recallNumber = recallNumber; self.title = title
        self.reasonCode = reasonCode; self.statusRaw = status.rawValue
        self.severity = severity; self.initiatedByEmployeeId = initiatedByEmployeeId
        self.approvedByEmployeeId = approvedByEmployeeId; self.initiatedAt = initiatedAt
        self.closedAt = closedAt; self.correctiveAction = correctiveAction
        self.effectivenessVerifiedAt = effectivenessVerifiedAt
        self.isSynced = isSynced; self.isDeleted = isDeleted; self.updatedAt = updatedAt
    }
}

@Model
final class InventoryRecallLot {
    @Attribute(.unique) var id: UUID
    var recallId: UUID
    var lotId: UUID
    var inventoryItemId: UUID
    var branchId: UUID
    var affectedQuantity: Double
    var recoveredQuantity: Double
    var destroyedQuantity: Double
    var isSynced: Bool
    var updatedAt: Date

    init(id: UUID = UUID(), recallId: UUID, lotId: UUID, inventoryItemId: UUID,
         branchId: UUID, affectedQuantity: Double, recoveredQuantity: Double = 0,
         destroyedQuantity: Double = 0, isSynced: Bool = false, updatedAt: Date = Date()) {
        self.id = id; self.recallId = recallId; self.lotId = lotId
        self.inventoryItemId = inventoryItemId; self.branchId = branchId
        self.affectedQuantity = affectedQuantity; self.recoveredQuantity = recoveredQuantity
        self.destroyedQuantity = destroyedQuantity; self.isSynced = isSynced
        self.updatedAt = updatedAt
    }
}

@Model
final class IncomingInspection {
    @Attribute(.unique) var id: UUID
    var purchaseOrderId: UUID?
    var purchaseOrderItemId: UUID?
    var inventoryItemId: UUID
    var lotId: UUID?
    var branchId: UUID
    var supplierId: UUID?
    var inspectedByEmployeeId: UUID?
    var inspectedAt: Date
    var receivedQuantity: Double
    var rejectedQuantity: Double
    var temperatureCelsius: Double?
    var minimumTemperature: Double?
    var maximumTemperature: Double?
    var packagingPassed: Bool
    var expiryPassed: Bool
    var certificateReference: String?
    var decisionRaw: String
    var reasonCode: String?
    var notes: String?
    var isSynced: Bool
    var updatedAt: Date

    init(id: UUID = UUID(), purchaseOrderId: UUID? = nil, purchaseOrderItemId: UUID? = nil,
         inventoryItemId: UUID, lotId: UUID? = nil, branchId: UUID, supplierId: UUID? = nil,
         inspectedByEmployeeId: UUID? = nil, inspectedAt: Date = Date(),
         receivedQuantity: Double, rejectedQuantity: Double = 0,
         temperatureCelsius: Double? = nil, minimumTemperature: Double? = nil,
         maximumTemperature: Double? = nil, packagingPassed: Bool = true,
         expiryPassed: Bool = true, certificateReference: String? = nil,
         decision: InventoryInspectionDecision = .accepted, reasonCode: String? = nil,
         notes: String? = nil, isSynced: Bool = false, updatedAt: Date = Date()) {
        self.id = id; self.purchaseOrderId = purchaseOrderId
        self.purchaseOrderItemId = purchaseOrderItemId; self.inventoryItemId = inventoryItemId
        self.lotId = lotId; self.branchId = branchId; self.supplierId = supplierId
        self.inspectedByEmployeeId = inspectedByEmployeeId; self.inspectedAt = inspectedAt
        self.receivedQuantity = receivedQuantity; self.rejectedQuantity = rejectedQuantity
        self.temperatureCelsius = temperatureCelsius; self.minimumTemperature = minimumTemperature
        self.maximumTemperature = maximumTemperature; self.packagingPassed = packagingPassed
        self.expiryPassed = expiryPassed; self.certificateReference = certificateReference
        self.decisionRaw = decision.rawValue; self.reasonCode = reasonCode; self.notes = notes
        self.isSynced = isSynced; self.updatedAt = updatedAt
    }
}

@Model
final class TemperatureLog {
    @Attribute(.unique) var id: UUID
    var branchId: UUID
    var storageLocation: String
    var inventoryItemId: UUID?
    var lotId: UUID?
    var temperatureCelsius: Double
    var minimumAllowed: Double
    var maximumAllowed: Double
    var recordedAt: Date
    var recordedByEmployeeId: UUID?
    var source: String
    var correctiveAction: String?
    var verifiedByEmployeeId: UUID?
    var verifiedAt: Date?
    var isSynced: Bool
    var updatedAt: Date

    init(id: UUID = UUID(), branchId: UUID, storageLocation: String,
         inventoryItemId: UUID? = nil, lotId: UUID? = nil, temperatureCelsius: Double,
         minimumAllowed: Double, maximumAllowed: Double, recordedAt: Date = Date(),
         recordedByEmployeeId: UUID? = nil, source: String = "manual",
         correctiveAction: String? = nil, verifiedByEmployeeId: UUID? = nil,
         verifiedAt: Date? = nil, isSynced: Bool = false, updatedAt: Date = Date()) {
        self.id = id; self.branchId = branchId; self.storageLocation = storageLocation
        self.inventoryItemId = inventoryItemId; self.lotId = lotId
        self.temperatureCelsius = temperatureCelsius; self.minimumAllowed = minimumAllowed
        self.maximumAllowed = maximumAllowed; self.recordedAt = recordedAt
        self.recordedByEmployeeId = recordedByEmployeeId; self.source = source
        self.correctiveAction = correctiveAction; self.verifiedByEmployeeId = verifiedByEmployeeId
        self.verifiedAt = verifiedAt; self.isSynced = isSynced; self.updatedAt = updatedAt
    }

    var isExcursion: Bool { temperatureCelsius < minimumAllowed || temperatureCelsius > maximumAllowed }
}

@Model
final class InventoryCountSession {
    @Attribute(.unique) var id: UUID
    var branchId: UUID
    var statusRaw: String
    var blindCount: Bool
    var countedByEmployeeId: UUID?
    var submittedAt: Date?
    var approvedByEmployeeId: UUID?
    var approvedAt: Date?
    var recountThresholdPercent: Double
    var notes: String?
    var isSynced: Bool
    var updatedAt: Date

    init(id: UUID = UUID(), branchId: UUID, status: InventoryCountStatus = .draft,
         blindCount: Bool = true, countedByEmployeeId: UUID? = nil,
         submittedAt: Date? = nil, approvedByEmployeeId: UUID? = nil,
         approvedAt: Date? = nil, recountThresholdPercent: Double = 5,
         notes: String? = nil, isSynced: Bool = false, updatedAt: Date = Date()) {
        self.id = id; self.branchId = branchId; self.statusRaw = status.rawValue
        self.blindCount = blindCount; self.countedByEmployeeId = countedByEmployeeId
        self.submittedAt = submittedAt; self.approvedByEmployeeId = approvedByEmployeeId
        self.approvedAt = approvedAt; self.recountThresholdPercent = recountThresholdPercent
        self.notes = notes; self.isSynced = isSynced; self.updatedAt = updatedAt
    }
}

@Model
final class ItemUnitConversion {
    @Attribute(.unique) var id: UUID
    var inventoryItemId: UUID
    var supplierId: UUID?
    var fromUnit: String
    var toUnit: String
    var multiplier: Double
    var effectiveFrom: Date
    var effectiveTo: Date?
    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date

    init(id: UUID = UUID(), inventoryItemId: UUID, supplierId: UUID? = nil,
         fromUnit: String, toUnit: String, multiplier: Double,
         effectiveFrom: Date = Date(), effectiveTo: Date? = nil,
         isSynced: Bool = false, isDeleted: Bool = false, updatedAt: Date = Date()) {
        precondition(multiplier > 0 && multiplier.isFinite)
        self.id = id; self.inventoryItemId = inventoryItemId; self.supplierId = supplierId
        self.fromUnit = fromUnit; self.toUnit = toUnit; self.multiplier = multiplier
        self.effectiveFrom = effectiveFrom; self.effectiveTo = effectiveTo
        self.isSynced = isSynced; self.isDeleted = isDeleted; self.updatedAt = updatedAt
    }
}
