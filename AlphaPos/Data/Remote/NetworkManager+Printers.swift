import Foundation
import CryptoKit
import SwiftData

extension NetworkManager {
    // MARK: - Printers & Routing Rules Sync

    func uploadPrinter(_ printer: Printer) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        let branchId = try activeOperationalBranchId()

        let payload: [String: Any] = [
            "id": printer.id.uuidString.lowercased(),
            "merchant_id": merchantId,
            "branch_id": branchId,
            "name": printer.name,
            "connection_type": printer.connectionType,
            "ip_address": printer.ipAddress ?? "",
            "port": printer.port,
            "bluetooth_name": printer.bluetoothName ?? "",
            "paper_width": printer.paperWidth,
            "emulation": printer.emulation,
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
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        var queryItems = [URLQueryItem(name: "id", value: "eq.\(id.uuidString.lowercased())")]
        if !merchantId.isEmpty {
            queryItems.append(URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)"))
        }
        _ = try await sendSupabaseRequest(
            method: "PATCH",
            endpoint: "printers",
            queryItems: queryItems,
            payload: [
                "is_deleted": true,
                "updated_at": NetworkManager.iso8601.string(from: Date())
            ]
        )
        return true
    }

    func fetchPrintersFromSupabase() async throws -> [[String: Any]] {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "order", value: "updated_at.asc"),
            URLQueryItem(name: "limit", value: "1000")
        ]
        if !merchantId.isEmpty {
            queryItems.append(URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)"))
        }
        if let branchId = try? activeOperationalBranchId(), !branchId.isEmpty {
            queryItems.append(URLQueryItem(name: "or", value: "(branch_id.eq.\(branchId),branch_id.is.null)"))
        }
        let data = try await sendSupabaseRequest(method: "GET", endpoint: "printers", queryItems: queryItems)
        return (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
    }

    func uploadPrintRoutingRule(_ rule: PrintRoutingRule) async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        let branchId = try activeOperationalBranchId()

        guard let printerId = rule.printer?.id else {
            throw NSError(domain: "NetworkManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "Rule is not linked to a printer"])
        }

        let payload: [String: Any] = [
            "id": rule.id.uuidString.lowercased(),
            "merchant_id": merchantId,
            "branch_id": branchId,
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
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        var queryItems = [URLQueryItem(name: "id", value: "eq.\(id.uuidString.lowercased())")]
        if !merchantId.isEmpty {
            queryItems.append(URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)"))
        }
        _ = try await sendSupabaseRequest(
            method: "PATCH",
            endpoint: "print_routing_rules",
            queryItems: queryItems,
            payload: [
                "is_deleted": true,
                "updated_at": NetworkManager.iso8601.string(from: Date())
            ]
        )
        return true
    }

    func fetchPrintRoutingRulesFromSupabase() async throws -> [[String: Any]] {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "order", value: "updated_at.asc"),
            URLQueryItem(name: "limit", value: "2000")
        ]
        if !merchantId.isEmpty {
            queryItems.append(URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)"))
        }
        if let branchId = try? activeOperationalBranchId(), !branchId.isEmpty {
            queryItems.append(URLQueryItem(name: "or", value: "(branch_id.eq.\(branchId),branch_id.is.null)"))
        }
        let data = try await sendSupabaseRequest(method: "GET", endpoint: "print_routing_rules", queryItems: queryItems)
        return (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
    }

    func uploadPrinterPreferences() async throws -> Bool {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        let defaults = UserDefaults.standard
        let defaultsByKey = [
            "receipt_printer_enabled": true, "kitchen_printer_enabled": true,
            "split_kitchen_print_by_category": true,
            "print_open_shift": false, "print_close_shift": true,
            "auto_print_receipt_on_payment": true,
            "auto_open_cash_drawer_on_cash_payment": true,
            "require_manager_override_for_drawer_test": true,
            "remote_receipt_print_enabled": false, "remote_kitchen_print_enabled": true,
            "single_printer_mode": false, "printer_role_fallback": false,
            "disable_receipt_printing": false, "show_logo_on_receipt": true
        ]
        let preferences = Dictionary(uniqueKeysWithValues: defaultsByKey.map {
            ($0.key, defaults.object(forKey: $0.key) as? Bool ?? $0.value)
        })
        _ = try await sendSupabaseRequest(
            method: "PATCH",
            endpoint: "merchants",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(merchantId)")],
            payload: [
                "printer_preferences": preferences,
                "updated_at": NetworkManager.iso8601.string(from: Date())
            ]
        )
        return true
    }
}
