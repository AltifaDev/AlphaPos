import Foundation
import SwiftData

extension SyncEngine {
    @MainActor
    func syncFinancialEvents(_ modelContext: ModelContext) async {
        var descriptor = FetchDescriptor<FinancialEvent>(predicate: #Predicate { !$0.isSynced })
        descriptor.fetchLimit = 500
        for event in (try? modelContext.fetch(descriptor)) ?? [] {
            do {
                if try await NetworkManager.shared.uploadFinancialEvent(event) {
                    event.isSynced = true
                    event.updatedAt = Date()
                }
            } catch {
                reportSyncFailure("FinancialEvent push: \(error.localizedDescription)", soft: true)
            }
        }
        modelContext.saveWithLogging(label: #function)
    }

    @MainActor
    func syncAccountingSnapshots(_ modelContext: ModelContext) async {
        for value in ((try? modelContext.fetch(FetchDescriptor<ShiftClosureSnapshot>(predicate: #Predicate { !$0.isSynced }))) ?? []) {
            do { if try await NetworkManager.shared.uploadShiftClosureSnapshot(value) { value.isSynced = true } }
            catch { reportSyncFailure("Shift snapshot push: \(error.localizedDescription)", soft: true) }
        }
        for value in ((try? modelContext.fetch(FetchDescriptor<DailySalesSnapshot>(predicate: #Predicate { !$0.isSynced }))) ?? []) {
            do { if try await NetworkManager.shared.uploadDailySalesSnapshot(value) { value.isSynced = true } }
            catch { reportSyncFailure("Daily snapshot push: \(error.localizedDescription)", soft: true) }
        }
        modelContext.saveWithLogging(label: #function)
    }

    @MainActor
    func pullFinancialEvents(_ modelContext: ModelContext) async {
        do {
            let rows = try await NetworkManager.shared.fetchFinancialEvents()
            let locals = (try? modelContext.fetch(FetchDescriptor<FinancialEvent>())) ?? []
            var byKey = Dictionary(uniqueKeysWithValues: locals.map { ($0.sourceEventKey, $0) })
            var affectedDays = Set<String>()
            for row in rows {
                guard let idString = row["id"] as? String,
                      let id = UUID(uuidString: idString),
                      let sourceKey = row["source_event_key"] as? String,
                      let sourceIdString = row["source_id"] as? String,
                      let sourceId = UUID(uuidString: sourceIdString),
                      let branchString = row["branch_id"] as? String,
                      let branchId = UUID(uuidString: branchString) else { continue }
                if byKey[sourceKey] != nil { continue } // posted facts are immutable
                let event = FinancialEvent(
                    id: id,
                    sourceEventKey: sourceKey,
                    eventType: row["event_type"] as? String ?? "sale_capture",
                    sourceType: row["source_type"] as? String ?? "unknown",
                    sourceId: sourceId,
                    orderId: (row["order_id"] as? String).flatMap(UUID.init(uuidString:)),
                    branchId: branchId,
                    registerSessionId: (row["register_session_id"] as? String).flatMap(UUID.init(uuidString:)),
                    businessDateKey: row["business_date"] as? String ?? "",
                    occurredAt: parseISO8601Date(row["occurred_at"]),
                    recordedAt: parseISO8601Date(row["recorded_at"]),
                    amount: remoteDouble(row["amount"]),
                    paymentMethod: row["payment_method"] as? String,
                    status: row["status"] as? String ?? "posted",
                    revisionOfEventId: (row["revision_of_event_id"] as? String).flatMap(UUID.init(uuidString:)),
                    sourceDeviceId: row["source_device_id"] as? String,
                    isLateAdjustment: remoteBool(row["is_late_adjustment"]),
                    isSynced: true,
                    isDeleted: false,
                    updatedAt: parseISO8601Date(row["updated_at"])
                )
                modelContext.insert(event)
                byKey[sourceKey] = event
                affectedDays.insert("\(branchId.uuidString.lowercased())|\(event.businessDateKey)")
            }
            let branches = (try? modelContext.fetch(FetchDescriptor<Branch>())) ?? []
            for token in affectedDays {
                let parts = token.split(separator: "|", maxSplits: 1).map(String.init)
                guard parts.count == 2, let branch = branches.first(where: { $0.id.uuidString.lowercased() == parts[0] }) else { continue }
                AccountingLedgerService.rebuildDailySnapshot(branch: branch, businessDateKey: parts[1], in: modelContext)
            }
            try modelContext.save()
            NotificationCenter.default.post(name: .accountingLedgerDidChange, object: nil)
        } catch {
            reportSyncFailure("FinancialEvent pull: \(error.localizedDescription)", soft: true)
        }
    }
}
