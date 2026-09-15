// NetworkService+Print.swift
// Staff iPhone → iPad thermal printer relay via shared sync_outbox.

import Foundation

extension NetworkService {

    /// Enqueue a cross-device job for the receipt-station iPad to claim.
    @discardableResult
    func enqueueSyncOutbox(
        idempotencyKey: String,
        jobType: String,
        payload: [String: Any]
    ) async throws -> String? {
        let data = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "rpc/enqueue_sync_outbox",
            payload: [
                "p_idempotency_key": idempotencyKey,
                "p_job_type": jobType,
                "p_payload": payload
            ]
        )
        // PostgREST returns a bare UUID string or JSON-encoded UUID.
        if let id = try? JSONDecoder().decode(String.self, from: data) {
            return id
        }
        if let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\" \n"))
            .nilIfEmpty {
            return text
        }
        return nil
    }

    /// Ask the paired iPad to print an unpaid guest check (pre-bill).
    func requestPreBillPrint(orderIds: [String], tableNumber: String) async throws {
        let sortedIds = orderIds.filter { !$0.isEmpty }.sorted()
        guard !sortedIds.isEmpty else {
            throw NetworkError.serverError("ไม่มีออเดอร์ให้พิมพ์บิล")
        }
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        let key = "print-prebill:\(tableNumber):\(sortedIds.joined(separator: ",")):\(stamp)"
        try await enqueueSyncOutbox(
            idempotencyKey: key,
            jobType: "print_prebill",
            payload: [
                "order_ids": sortedIds,
                "table_number": tableNumber,
                "requested_by_device_id": UserDefaults.standard.string(forKey: "paired_device_id") ?? "",
                "requested_at": ISO8601DateFormatter().string(from: Date())
            ]
        )
    }

    /// Ask the paired iPad to print paid receipt(s). Uses a unique key so
    /// intentional reprints are allowed after the auto-print on payment.
    func requestReceiptPrint(orderIds: [String], tableNumber: String? = nil) async throws {
        let sortedIds = orderIds.filter { !$0.isEmpty }.sorted()
        guard !sortedIds.isEmpty else {
            throw NetworkError.serverError("ไม่มีออเดอร์ให้พิมพ์ใบเสร็จ")
        }
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        let tablePart = tableNumber ?? "na"
        let key = "print-receipt-manual:\(tablePart):\(sortedIds.joined(separator: ",")):\(stamp)"
        try await enqueueSyncOutbox(
            idempotencyKey: key,
            jobType: "print_receipt",
            payload: [
                "order_ids": sortedIds,
                "order_id": sortedIds[0],
                "force": true,
                "table_number": tablePart,
                "requested_by_device_id": UserDefaults.standard.string(forKey: "paired_device_id") ?? "",
                "requested_at": ISO8601DateFormatter().string(from: Date())
            ]
        )
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
