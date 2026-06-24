import Foundation
import CryptoKit
import SwiftData

extension NetworkManager {
    // MARK: - Printers & Routing Rules Sync

    func uploadPrinter(_ printer: Printer) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId

        let payload: [String: Any] = [
            "id": printer.id.uuidString.lowercased(),
            "merchant_id": merchantId,
            "name": printer.name,
            "connection_type": printer.connectionType,
            "ip_address": printer.ipAddress ?? "",
            "port": printer.port,
            "bluetooth_name": printer.bluetoothName ?? "",
            "paper_width": printer.paperWidth,
            "status": printer.status,
            "role": printer.role,
            "is_active": printer.isActive,
            "is_synced": true,
            "is_deleted": printer.isDeleted,
            "updated_at": NetworkManager.iso8601.string(from: printer.updatedAt)
        ]

        _ = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "printers",
            queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
            payload: payload
        )
        return true
    }

    func deletePrinterOnServer(id: UUID) async throws -> Bool {
        _ = try await sendSupabaseRequest(
            method: "DELETE",
            endpoint: "printers",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(id.uuidString.lowercased())")]
        )
        return true
    }

    func uploadPrintRoutingRule(_ rule: PrintRoutingRule) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId

        guard let printerId = rule.printer?.id else {
            throw NSError(domain: "NetworkManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "Rule is not linked to a printer"])
        }

        let payload: [String: Any] = [
            "id": rule.id.uuidString.lowercased(),
            "merchant_id": merchantId,
            "printer_id": printerId.uuidString.lowercased(),
            "category_id": rule.categoryId ?? "",
            "print_on_order": rule.printOnOrder,
            "print_on_payment": rule.printOnPayment,
            "is_synced": true,
            "is_deleted": rule.isDeleted,
            "updated_at": NetworkManager.iso8601.string(from: rule.updatedAt)
        ]

        _ = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "print_routing_rules",
            queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
            payload: payload
        )
        return true
    }

    func deletePrintRoutingRuleOnServer(id: UUID) async throws -> Bool {
        _ = try await sendSupabaseRequest(
            method: "DELETE",
            endpoint: "print_routing_rules",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(id.uuidString.lowercased())")]
        )
        return true
    }
}
