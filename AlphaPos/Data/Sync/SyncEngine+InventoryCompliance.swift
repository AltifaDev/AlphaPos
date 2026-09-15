import Foundation
import SwiftData

extension SyncEngine {
    @MainActor
    func syncInventoryCompliance(_ context: ModelContext) async {
        let network = NetworkManager.shared

        for row in (try? context.fetch(FetchDescriptor<InventoryLotControl>(predicate: #Predicate { !$0.isSynced }))) ?? [] {
            do {
                try await network.uploadInventoryComplianceRow(endpoint: "inventory_lot_controls", id: row.id, fields: [
                    "branch_id": row.branchId.uuidString.lowercased(), "inventory_item_id": row.inventoryItemId.uuidString.lowercased(),
                    "lot_id": row.lotId.uuidString.lowercased(), "disposition": row.dispositionRaw,
                    "reason_code": row.reasonCode, "notes": row.notes as Any,
                    "decided_at": NetworkManager.iso8601.string(from: row.decidedAt), "is_deleted": row.isDeleted
                ]); row.isSynced = true
            } catch { print("SyncEngine [LotControl]: \(error.localizedDescription)") }
        }
        for row in (try? context.fetch(FetchDescriptor<InventoryRecall>(predicate: #Predicate { !$0.isSynced }))) ?? [] {
            do {
                try await network.uploadInventoryComplianceRow(endpoint: "inventory_recalls", id: row.id, fields: [
                    "recall_number": row.recallNumber, "title": row.title, "reason_code": row.reasonCode,
                    "status": row.statusRaw, "severity": row.severity,
                    "initiated_at": NetworkManager.iso8601.string(from: row.initiatedAt),
                    "corrective_action": row.correctiveAction as Any, "is_deleted": row.isDeleted
                ]); row.isSynced = true
            } catch { print("SyncEngine [Recall]: \(error.localizedDescription)") }
        }
        for row in (try? context.fetch(FetchDescriptor<InventoryRecallLot>(predicate: #Predicate { !$0.isSynced }))) ?? [] {
            do {
                try await network.uploadInventoryComplianceRow(endpoint: "inventory_recall_lots", id: row.id, fields: [
                    "recall_id": row.recallId.uuidString.lowercased(), "lot_id": row.lotId.uuidString.lowercased(),
                    "inventory_item_id": row.inventoryItemId.uuidString.lowercased(), "branch_id": row.branchId.uuidString.lowercased(),
                    "affected_quantity": row.affectedQuantity, "recovered_quantity": row.recoveredQuantity,
                    "destroyed_quantity": row.destroyedQuantity
                ]); row.isSynced = true
            } catch { print("SyncEngine [RecallLot]: \(error.localizedDescription)") }
        }
        for row in (try? context.fetch(FetchDescriptor<IncomingInspection>(predicate: #Predicate { !$0.isSynced }))) ?? [] {
            do {
                var fields: [String: Any] = [
                    "branch_id": row.branchId.uuidString.lowercased(), "inventory_item_id": row.inventoryItemId.uuidString.lowercased(),
                    "inspected_at": NetworkManager.iso8601.string(from: row.inspectedAt),
                    "received_quantity": row.receivedQuantity, "rejected_quantity": row.rejectedQuantity,
                    "packaging_passed": row.packagingPassed, "expiry_passed": row.expiryPassed,
                    "decision": row.decisionRaw
                ]
                if let v = row.purchaseOrderId { fields["purchase_order_id"] = v.uuidString.lowercased() }
                if let v = row.purchaseOrderItemId { fields["purchase_order_item_id"] = v.uuidString.lowercased() }
                if let v = row.lotId { fields["lot_id"] = v.uuidString.lowercased() }
                if let v = row.supplierId { fields["supplier_id"] = v.uuidString.lowercased() }
                if let v = row.temperatureCelsius { fields["temperature_celsius"] = v }
                try await network.uploadInventoryComplianceRow(endpoint: "incoming_inspections", id: row.id, fields: fields)
                row.isSynced = true
            } catch { print("SyncEngine [IncomingInspection]: \(error.localizedDescription)") }
        }
        for row in (try? context.fetch(FetchDescriptor<TemperatureLog>(predicate: #Predicate { !$0.isSynced }))) ?? [] {
            do {
                try await network.uploadInventoryComplianceRow(endpoint: "temperature_logs", id: row.id, fields: [
                    "branch_id": row.branchId.uuidString.lowercased(), "storage_location": row.storageLocation,
                    "temperature_celsius": row.temperatureCelsius, "minimum_allowed": row.minimumAllowed,
                    "maximum_allowed": row.maximumAllowed, "recorded_at": NetworkManager.iso8601.string(from: row.recordedAt),
                    "source": row.source, "corrective_action": row.correctiveAction as Any
                ]); row.isSynced = true
            } catch { print("SyncEngine [Temperature]: \(error.localizedDescription)") }
        }
        for row in (try? context.fetch(FetchDescriptor<InventoryCountSession>(predicate: #Predicate { !$0.isSynced }))) ?? [] {
            do {
                try await network.uploadInventoryComplianceRow(endpoint: "inventory_count_sessions", id: row.id, fields: [
                    "branch_id": row.branchId.uuidString.lowercased(), "status": row.statusRaw,
                    "blind_count": row.blindCount, "recount_threshold_percent": row.recountThresholdPercent,
                    "notes": row.notes as Any
                ]); row.isSynced = true
            } catch { print("SyncEngine [CountSession]: \(error.localizedDescription)") }
        }
        for row in (try? context.fetch(FetchDescriptor<ItemUnitConversion>(predicate: #Predicate { !$0.isSynced }))) ?? [] {
            do {
                try await network.uploadInventoryComplianceRow(endpoint: "item_unit_conversions", id: row.id, fields: [
                    "inventory_item_id": row.inventoryItemId.uuidString.lowercased(), "from_unit": row.fromUnit,
                    "to_unit": row.toUnit, "multiplier": row.multiplier,
                    "effective_from": NetworkManager.iso8601.string(from: row.effectiveFrom), "is_deleted": row.isDeleted
                ]); row.isSynced = true
            } catch { print("SyncEngine [UnitConversion]: \(error.localizedDescription)") }
        }
        context.saveWithLogging(label: #function)
    }
}
