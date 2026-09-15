import Foundation

extension NetworkManager {
    func isOptimisticConcurrencyConflict(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("[40001]") || message.contains("_conflict") || message.contains("serialization")
    }

    /// Persists conflict metadata after the failed CAS transaction has rolled
    /// back. Business payload and PII are deliberately excluded.
    func recordSyncConflict(
        entityType: String,
        entityId: UUID,
        expectedVersion: Int,
        error: Error
    ) async {
        guard isOptimisticConcurrencyConflict(error) else { return }

        SyncConflictJournal.shared.record(
            source: entityType,
            strategy: "optimistic_cas",
            decision: "manual_pending",
            baseAt: nil,
            localAt: Date(),
            remoteAt: Date()
        )

        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        guard !merchantId.isEmpty else { return }
        var payload: [String: Any] = [
            "merchant_id": merchantId,
            "entity_type": entityType,
            "entity_id": entityId.uuidString.lowercased(),
            "expected_version": expectedVersion > 0 ? expectedVersion : NSNull(),
            "resolution": "manual_required",
            "details": ["source": "ios_cas", "error_class": "serialization_conflict"]
        ]
        if let branchId = try? activeOperationalBranchId() { payload["branch_id"] = branchId }
        do {
            _ = try await sendSupabaseRequest(method: "POST", endpoint: "sync_conflict_journal", payload: payload)
        } catch {
            // The protected local journal remains available while offline.
            #if DEBUG
            print("NetworkManager [Conflict Journal]: server append deferred: \(error.localizedDescription)")
            #endif
        }
    }
}
