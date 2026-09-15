import Foundation
import SwiftData

extension SyncEngine {
    /// Drain shared `sync_outbox` jobs claimed via RPC.
    /// Print jobs are handled by the designated station; push jobs are
    /// acknowledgement-only (APNs already fired from DB triggers).
    func drainSyncOutbox(_ modelContext: ModelContext) async {
        do {
            let jobs = try await NetworkManager.shared.claimSyncOutbox(limit: 20)
            guard !jobs.isEmpty else { return }

            let isReceiptStation = UserDefaults.standard.bool(forKey: Self.remoteReceiptPrintEnabledKey)
            let isKitchenStation = UserDefaults.standard.object(forKey: Self.remoteKitchenPrintEnabledKey) as? Bool ?? true

            for job in jobs {
                guard let id = job["id"] as? String else { continue }
                let jobType = (job["job_type"] as? String) ?? ""
                let payload = job["payload"] as? [String: Any] ?? [:]

                do {
                    switch jobType {
                    case "print_receipt":
                        // Only the receipt-station iPad should consume these.
                        // Non-stations requeue so the station can claim next.
                        guard isReceiptStation else {
                            try await NetworkManager.shared.completeSyncOutbox(
                                id: id, success: false, error: "not_receipt_station"
                            )
                            continue
                        }
                        await handleRemotePaymentPrint(record: payload, modelContext: modelContext)
                        try await NetworkManager.shared.completeSyncOutbox(id: id, success: true)
                    case "print_prebill":
                        guard isReceiptStation else {
                            try await NetworkManager.shared.completeSyncOutbox(
                                id: id, success: false, error: "not_receipt_station"
                            )
                            continue
                        }
                        let ok = await handleRemotePreBillPrint(payload: payload, modelContext: modelContext)
                        try await NetworkManager.shared.completeSyncOutbox(
                            id: id,
                            success: ok,
                            error: ok ? nil : "prebill_print_failed"
                        )
                    case "print_kitchen":
                        guard isKitchenStation else {
                            try await NetworkManager.shared.completeSyncOutbox(
                                id: id, success: false, error: "not_kitchen_station"
                            )
                            continue
                        }
                        // Kitchen print is gated by staff confirmation + station flag;
                        // mark complete after a best-effort remote kitchen dispatch.
                        await handleRemoteKitchenPrint(modelContext: modelContext)
                        try await NetworkManager.shared.completeSyncOutbox(id: id, success: true)
                    case "staff_push":
                        // Notification already delivered by send-staff-push trigger.
                        try await NetworkManager.shared.completeSyncOutbox(id: id, success: true)
                    case "order_bundle.changed":
                        // Realtime/outbox is an invalidation signal. Re-read the
                        // authoritative server snapshot instead of trusting event order.
                        await pullCustomerOrders(modelContext)
                        await pullActiveSessions(modelContext)
                        try await NetworkManager.shared.completeSyncOutbox(id: id, success: true)
                    default:
                        try await NetworkManager.shared.completeSyncOutbox(
                            id: id,
                            success: false,
                            error: "unknown job_type \(jobType)"
                        )
                    }
                } catch {
                    try? await NetworkManager.shared.completeSyncOutbox(
                        id: id,
                        success: false,
                        error: error.localizedDescription
                    )
                    reportSyncFailure("Outbox \(jobType)", soft: true)
                }
            }
        } catch {
            // Outbox RPC may not be migrated yet on older environments.
            reportSyncFailure("Outbox claim", soft: true)
            #if DEBUG
            print("SyncEngine [Outbox]: \(error.localizedDescription)")
            #endif
        }
    }
}
