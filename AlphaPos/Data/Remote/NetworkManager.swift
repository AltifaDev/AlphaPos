import Foundation
import CryptoKit
import SwiftData
import os

enum NetworkError: Error, LocalizedError {
    case offline
    case offlineModeProhibited
    case serverError(String)
    case invalidResponse
    /// Optimistic concurrency conflict (row_version / updated_at mismatch).
    case conflict(String)

    var errorDescription: String? {
        switch self {
        case .offline: return "No internet connection detected."
        case .offlineModeProhibited: return "Network access is disabled in offline-only mode."
        case .serverError(let msg): return "Server returned error: \(msg)"
        case .invalidResponse: return "Received invalid response from server."
        case .conflict(let msg): return "Sync conflict: \(msg)"
        }
    }
}

extension NetworkManager {
    /// Operational APIs must never silently fall back to merchant-wide access.
    /// Brand-wide reporting uses dedicated, permission-checked paths instead.
    func activeOperationalBranchId() throws -> String {
        let value = (BranchContext.shared.activeBranchIDString)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard UUID(uuidString: value) != nil else {
            throw NetworkError.serverError("A valid active branch is required")
        }
        return value
    }

    /// Fetches every PostgREST page. Inventory reconciliation must never be
    /// based on a silently truncated first page.
    func fetchAllPages(
        endpoint: String,
        queryItems: [URLQueryItem],
        pageSize: Int = 500
    ) async throws -> [[String: Any]] {
        precondition(pageSize > 0)
        var offset = 0
        var allRows: [[String: Any]] = []

        while true {
            var pageQuery = queryItems.filter { $0.name != "limit" && $0.name != "offset" }
            pageQuery.append(URLQueryItem(name: "limit", value: String(pageSize)))
            pageQuery.append(URLQueryItem(name: "offset", value: String(offset)))
            let data = try await sendSupabaseRequest(method: "GET", endpoint: endpoint, queryItems: pageQuery)
            guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                throw NetworkError.invalidResponse
            }
            allRows.append(contentsOf: rows)
            guard rows.count == pageSize else { break }
            offset += rows.count
        }
        return allRows
    }
}

/// Compact record of a failed Supabase/HTTP call for Sync Health diagnostics.
struct NetworkFailureRecord: Identifiable, Equatable {
    let id: UUID
    let at: Date
    let method: String
    let endpoint: String
    let statusCode: Int
    let message: String

    var summaryLine: String {
        let shortEndpoint = endpoint.split(separator: "?").first.map(String.init) ?? endpoint
        let codePart = statusCode > 0 ? "HTTP \(statusCode)" : "ERR"
        let msg = message
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let clipped = msg.count > 160 ? String(msg.prefix(157)) + "…" : msg
        return "\(method.uppercased()) \(shortEndpoint) · \(codePart) · \(clipped)"
    }
}

protocol RemoteAuditLogUploadable {
    var id: UUID { get }
    var employeeId: UUID? { get }
    var actionType: String { get }
    var details: String? { get }
    var originalValue: Double? { get }
    var newValue: Double? { get }
    var createdAt: Date { get }
    var isDeleted: Bool { get }
    var updatedAt: Date { get }
}

protocol RemoteCustomerUploadable {
    var id: UUID { get }
    var name: String { get }
    var email: String? { get }
    var phone: String? { get }
    var taxId: String? { get }
    var address: String? { get }
    var loyaltyPoints: Int { get }
    var membershipTier: String { get }
    var totalSpend: Double { get }
    var visitCount: Int { get }
    var notes: String? { get }
    var dateOfBirth: Date? { get }
    var allergies: String? { get }
    var preferences: String? { get }
    var isDeleted: Bool { get }
    var updatedAt: Date { get }
}

protocol RemoteRefundTransactionUploadable {
    var id: UUID { get }
    var order: Order? { get }
    var originalPayment: Payment? { get }
    var refundAmount: Double { get }
    var refundMethod: String { get }
    var reasonCode: String { get }
    var reasonNotes: String? { get }
    var refundedByEmployeeId: UUID? { get }
    var approvedByEmployeeId: UUID? { get }
    var status: String { get }
    var createdAt: Date { get }
    var financialEventAt: Date { get }
    var businessDateKey: String { get }
    var registerSessionId: UUID? { get }
    var isDeleted: Bool { get }
    var updatedAt: Date { get }
}

protocol RemoteOrderDiscountUploadable {
    var id: UUID { get }
    var order: Order? { get }
    var promotion: Promotion? { get }
    var discountType: String { get }
    var discountValue: Double { get }
    var discountAmount: Double { get }
    var reason: String? { get }
    var appliedByEmployeeId: UUID? { get }
    var isDeleted: Bool { get }
    var updatedAt: Date { get }
}

protocol RemoteOrderTaxLineUploadable {
    var id: UUID { get }
    var order: Order? { get }
    var taxName: String { get }
    var taxRate: Double { get }
    var taxableAmount: Double { get }
    var taxAmount: Double { get }
    var isInclusive: Bool { get }
    var jurisdiction: String? { get }
    var isDeleted: Bool { get }
    var updatedAt: Date { get }
}

protocol RemoteTipUploadable {
    var id: UUID { get }
    var order: Order? { get }
    var payment: Payment? { get }
    var amount: Double { get }
    var tipType: String { get }
    var employeeId: UUID? { get }
    var isDeleted: Bool { get }
    var updatedAt: Date { get }
}

protocol RemoteCashMovementUploadable {
    var id: UUID { get }
    var registerSession: RegisterSession? { get }
    var movementType: String { get }
    var amount: Double { get }
    var reason: String { get }
    var performedByEmployeeId: UUID? { get }
    var isDeleted: Bool { get }
    var updatedAt: Date { get }
}

protocol RemoteLoyaltyTransactionUploadable {
    var id: UUID { get }
    var customer: Customer? { get }
    var order: Order? { get }
    var transactionType: String { get }
    var points: Int { get }
    var pointsBalanceAfter: Int { get }
    var transactionDescription: String? { get }
    var isDeleted: Bool { get }
    var updatedAt: Date { get }
}

protocol RemoteGiftCardUploadable {
    var id: UUID { get }
    var cardNumber: String { get }
    var balance: Double { get }
    var initialValue: Double { get }
    var customer: Customer? { get }
    var status: String { get }
    var expiresAt: Date? { get }
    var isDeleted: Bool { get }
    var updatedAt: Date { get }
}

final class NetworkManager {
    static let shared = NetworkManager()
    // `internal` (no modifier) so extension files in separate Swift files can access it
    let config = AppConfig.shared

    // Configurable endpoint pointing directly to Supabase REST API
    lazy var serverBaseURL: URL = config.supabaseRestURL
    // `internal` so extensions can read anonKey for auth headers
    lazy var anonKey: String = config.supabaseAnonKey

    // Shared ISO8601 formatter — DateFormatter is expensive; reuse across all calls
    // `internal` so extension files can format dates without allocating new instances
    static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    // Simulator states
    var simulateOffline = false

    // Ring buffer of recent HTTP failures for Sync Health diagnostics.
    private let recentFailuresLock = OSAllocatedUnfairLock()
    private var _recentFailures: [NetworkFailureRecord] = []
    private let maxRecentFailures = 12

    func recordNetworkFailure(
        method: String,
        endpoint: String,
        statusCode: Int = 0,
        message: String
    ) {
        let cleaned = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        let record = NetworkFailureRecord(
            id: UUID(),
            at: Date(),
            method: method,
            endpoint: endpoint,
            statusCode: statusCode,
            message: cleaned
        )
        recentFailuresLock.lock()
        _recentFailures.append(record)
        if _recentFailures.count > maxRecentFailures {
            _recentFailures.removeFirst(_recentFailures.count - maxRecentFailures)
        }
        recentFailuresLock.unlock()
    }

    func recentNetworkFailures(limit: Int = 5) -> [NetworkFailureRecord] {
        recentFailuresLock.lock()
        defer { recentFailuresLock.unlock() }
        return Array(_recentFailures.suffix(max(1, limit)))
    }

    func recentFailureSummaries(limit: Int = 5) -> [String] {
        recentNetworkFailures(limit: limit).map(\.summaryLine)
    }

    func clearRecentNetworkFailures() {
        recentFailuresLock.lock()
        _recentFailures.removeAll(keepingCapacity: true)
        recentFailuresLock.unlock()
    }

    var isWebOrderingEnabled: Bool {
        !OfflineSyncModeController.isEnabled
            && (UserDefaults.standard.object(forKey: "enable_web_ordering") as? Bool ?? true)
    }

    private init() {
        NotificationCenter.default.addObserver(
            forName: .merchantTokenDidRefresh,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { try? await self?.registerSavedPushToken() }
        }
    }

    func registerPushDevice(token: String) async throws {
        UserDefaults.standard.set(token, forKey: "apns_device_token")
        try await registerSavedPushToken()
    }

    private func registerSavedPushToken() async throws {
        guard let token = UserDefaults.standard.string(forKey: "apns_device_token"), !token.isEmpty else { return }
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        let payload: [String: Any] = [
            "merchant_id": merchantId,
            "device_token": token,
            "app_id": "pos",
            "platform": "ios",
            "is_active": true,
            "updated_at": NetworkManager.iso8601.string(from: Date())
        ]
        _ = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "push_devices",
            queryItems: [URLQueryItem(name: "on_conflict", value: "device_token")],
            payload: payload
        )
    }

    // Connectivity cache: avoid one HEAD request per sync function
    private var _lastConnectedAt: Date?
    private var _lastConnectedResult: Bool = false
    private let connectivityCacheTTL: TimeInterval = 10.0

    func isConnected() async -> Bool {
        if simulateOffline || !NetworkPolicy.shared.allows(.connectivityProbe) { return false }

        // Return cached result if fresh enough
        if let last = _lastConnectedAt, Date().timeIntervalSince(last) < connectivityCacheTTL {
            return _lastConnectedResult
        }

        // Quick ping check to Supabase menu_items REST endpoint
        var request = URLRequest(url: serverBaseURL.appendingPathComponent("menu_items"))
        request.httpMethod = "HEAD"
        // Always use public anonKey for connectivity check to bypass expired merchant JWT tokens
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        if !merchantId.isEmpty {
            request.setValue(merchantId, forHTTPHeaderField: "x-merchant-id")
        }
        request.timeoutInterval = 5.0
        // Note: fetchCustomerOrders uses a joined query with order_items(*) which
        // can be slow. The per-request override below handles that case.

        do {
            let (_, response) = try await AppNetworkTransport.data(for: request, purpose: .connectivityProbe)
            let result = (response as? HTTPURLResponse).map { (200...299).contains($0.statusCode) } ?? false
            _lastConnectedAt = Date()
            _lastConnectedResult = result
            return result
        } catch {
            #if DEBUG
            print("NetworkManager: connectivity check failed with error: \(error.localizedDescription) (\(error))")
            #endif
            _lastConnectedAt = Date()
            _lastConnectedResult = false
            return false
        }
    }

    /// Call this when going offline or when you want to force a fresh check on next isConnected() call.
    func invalidateConnectivityCache() {
        _lastConnectedAt = nil
    }

    // General request sender that performs actual HTTP queries to Supabase
    // `internal` so all extension files can issue requests without duplicating auth logic
    func sendSupabaseRequest(method: String, endpoint: String, queryItems: [URLQueryItem]? = nil, payload: Any? = nil, timeoutOverride: Double? = nil, allowOfflinePlanRecovery: Bool = false) async throws -> Data {
        if simulateOffline || NetworkPolicy.shared.mode == .offlineOnly {
            recordNetworkFailure(method: method, endpoint: endpoint, message: "Offline mode / no network")
            throw NetworkError.offlineModeProhibited
        }
        guard TenantWorkspaceGuard.isAuthenticatedWorkspaceReady,
              let token = MerchantAuthManager.shared.authorizationToken else {
            recordNetworkFailure(method: method, endpoint: endpoint, message: "Tenant verification required")
            throw NetworkError.serverError("Tenant verification required")
        }

        var url = serverBaseURL.appendingPathComponent(endpoint)
        if let queryItems = queryItems, var components = URLComponents(url: url, resolvingAgainstBaseURL: true) {
            components.queryItems = queryItems
            if let newUrl = components.url {
                url = newUrl
            }
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        // Use merchant JWT if available — the JWT contains a `merchant_id` claim
        // that PostgREST extracts via `current_setting('request.jwt.claims')`,
        // enabling RLS policies to isolate data per merchant automatically.
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        if !merchantId.isEmpty {
            request.setValue(merchantId, forHTTPHeaderField: "x-merchant-id")
        }

        request.timeoutInterval = timeoutOverride ?? 5.0
        // Enable upsert for POST with on_conflict parameter
        if method == "POST" {
            request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        } else if method == "PATCH" {
            request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        }

        if let payload = payload {
            let jsonData = try JSONSerialization.data(withJSONObject: payload)
            request.httpBody = jsonData
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await AppNetworkTransport.data(
                for: request,
                purpose: allowOfflinePlanRecovery ? .licensingActivation : .cloudData
            )
        } catch {
            recordNetworkFailure(
                method: method,
                endpoint: endpoint,
                message: error.localizedDescription
            )
            throw error
        }

        let httpStatusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

        guard (200...299).contains(httpStatusCode) else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "HTTP Request failed"
            let serverCode = Self.serverErrorCode(errorMsg)
            // PostgREST can report PostgreSQL permission failures (42501) with
            // HTTP 401/403. Refreshing a healthy merchant JWT cannot fix those
            // failures and previously caused a tight refresh/retry loop.
            let isPermissionError = serverCode == "42501"
            let isAuthError = serverCode == "PGRST301"
                || serverCode == "PGRST302"
                || (httpStatusCode == 401 && !isPermissionError)
            if isAuthError {
                // Try to refresh the token once before giving up.
                // PGRST301 = JWT decryption error (token expired or wrong key).
                // Do NOT logout immediately — that makes all subsequent syncs use
                // anonKey which has no merchant_id claim → RLS blocks order_items inserts.
                let refreshed = await MerchantAuthManager.shared.tryRefresh()
                if refreshed {
                    // Retry the original request with the fresh token
                    guard TenantWorkspaceGuard.isAuthenticatedWorkspaceReady,
                          let newToken = MerchantAuthManager.shared.authorizationToken else {
                        throw NetworkError.serverError("Tenant verification required")
                    }
                    request.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                    do {
                        let (retryData, retryResponse) = try await AppNetworkTransport.data(for: request, purpose: .cloudData)
                        if let retryHTTP = retryResponse as? HTTPURLResponse,
                           (200...299).contains(retryHTTP.statusCode) {
                            return retryData
                        }
                        let retryMsg = String(data: retryData, encoding: .utf8) ?? "HTTP Request failed"
                        let retryCode = (retryResponse as? HTTPURLResponse)?.statusCode ?? httpStatusCode
                        recordNetworkFailure(
                            method: method,
                            endpoint: endpoint,
                            statusCode: retryCode,
                            message: Self.compactServerMessage(retryMsg)
                        )
                    } catch {
                        recordNetworkFailure(
                            method: method,
                            endpoint: endpoint,
                            statusCode: httpStatusCode,
                            message: "Auth retry failed: \(error.localizedDescription)"
                        )
                        throw error
                    }
                }
                // Refresh failed or retry still failed — log but do NOT logout
                #if DEBUG
                print("NetworkManager: Auth error (\(httpStatusCode)) — token refresh attempted. errorMsg: \(errorMsg.prefix(200))")
                #endif
            }
            let compact = Self.compactServerMessage(errorMsg)
            recordNetworkFailure(
                method: method,
                endpoint: endpoint,
                statusCode: httpStatusCode,
                message: compact
            )
            throw NetworkError.serverError(compact)
        }

        return data
    }

    /// Strip noisy JSON wrappers so Sync Health can show readable PostgREST errors.
    private static func serverErrorCode(_ raw: String) -> String? {
        guard let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return obj["code"] as? String
    }

    private static func compactServerMessage(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return trimmed.count > 220 ? String(trimmed.prefix(217)) + "…" : trimmed
        }
        let message = (obj["message"] as? String)
            ?? (obj["error_description"] as? String)
            ?? (obj["error"] as? String)
            ?? trimmed
        let code = (obj["code"] as? String).map { "[\($0)] " } ?? ""
        let hint = (obj["hint"] as? String).map { " (\($0))" } ?? ""
        let details = (obj["details"] as? String).map { " — \($0)" } ?? ""
        let combined = "\(code)\(message)\(details)\(hint)"
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return combined.count > 220 ? String(combined.prefix(217)) + "…" : combined
    }

    // Pull active orders from customer self-ordering database in Supabase
    func fetchTableOrderBundle(tableSessionId: UUID, branchId: String) async throws -> [String: Any] {
        let data = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "rpc/get_table_order_bundle",
            payload: [
                "p_table_session_id": tableSessionId.uuidString.lowercased(),
                "p_branch_id": branchId
            ],
            timeoutOverride: 15.0
        )
        guard let bundle = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              bundle["contract_version"] as? Int == 1,
              bundle["orders"] is [[String: Any]] else {
            throw NetworkError.invalidResponse
        }
        return bundle
    }

    func fetchCustomerOrders() async throws -> [[String: Any]] {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        let branchId = try activeOperationalBranchId()
        let data = try await sendSupabaseRequest(method: "GET", endpoint: "orders", queryItems: [
            URLQueryItem(name: "select", value: "*,order_items(*,order_item_modifiers(*)),payments(*)"),
            URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)"),
            URLQueryItem(name: "branch_id", value: "eq.\(branchId)"),
            // Only fetch active/recent orders — reduces payload size and join cost significantly.
            // "completed" is included so POS can show settled orders in the same session.
            // "cancelled" is included so a void on one device propagates to every
            // other device's KDS — otherwise a voided ticket would linger as a
            // ghost on the other stations until their local sweep ran.
            URLQueryItem(name: "status", value: "in.(pending,preparing,ready,served,completed,cancelled)"),
            URLQueryItem(name: "is_deleted", value: "eq.false"),
            URLQueryItem(name: "order", value: "created_at.desc"),
            URLQueryItem(name: "limit", value: "50")
        ], timeoutOverride: 15.0)

        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw NetworkError.invalidResponse
        }

        func fetchDirectOrderItems(orderId: String) async throws -> [[String: Any]] {
            let itemsData = try await sendSupabaseRequest(method: "GET", endpoint: "order_items", queryItems: [
                URLQueryItem(name: "select", value: "*,order_item_modifiers(*)"),
                URLQueryItem(name: "order_id", value: "eq.\(orderId)"),
                URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)"),
                URLQueryItem(name: "branch_id", value: "eq.\(branchId)"),
                URLQueryItem(name: "order", value: "created_at.asc")
            ])
            return (try? JSONSerialization.jsonObject(with: itemsData) as? [[String: Any]]) ?? []
        }

        // Map from snake_case database columns to camelCase client names expected by SyncEngine
        var mappedOrders: [[String: Any]] = []
        for dict in jsonArray {
            var mapped = dict
            mapped["orderNumber"] = dict["order_number"]
            mapped["tableNumber"] = dict["table_number"]
            mapped["createdAt"] = dict["created_at"]
            mapped["readyAt"] = dict["ready_at"]
            mapped["updatedAt"] = dict["updated_at"]
            mapped["rowVersion"] = dict["row_version"]
            // Origin channel + staff-confirmation gate for kitchen printing.
            // Web orders arrive with order_source == "web" and must be confirmed
            // by staff before their kitchen tickets print.
            mapped["orderSource"] = dict["order_source"]
            mapped["isStaffConfirmed"] = dict["is_staff_confirmed"]

            // Map items
            var items = dict["order_items"] as? [[String: Any]] ?? []
            if items.isEmpty, let orderId = dict["id"] as? String, !orderId.isEmpty {
                items = (try? await fetchDirectOrderItems(orderId: orderId)) ?? []
            }
            mapped["items"] = items.map { itemDict in
                    var mappedItem = itemDict
                    mappedItem["name"] = itemDict["item_name"]
                    mappedItem["itemId"] = itemDict["item_id"]
                    mappedItem["lineType"] = itemDict["line_type"]
                    mappedItem["rowVersion"] = itemDict["row_version"]
                    if let mods = itemDict["order_item_modifiers"] as? [[String: Any]] {
                        mappedItem["modifiers"] = mods
                    }
                    return mappedItem
            }

            // Map payments
            if let payments = dict["payments"] as? [[String: Any]] {
                mapped["payments"] = payments.map { payDict in
                    var mappedPay = payDict
                    mappedPay["paymentMethod"] = payDict["payment_method"]
                    mappedPay["createdAt"] = payDict["created_at"]
                    return mappedPay
                }
            }
            mappedOrders.append(mapped)
        }
        return mappedOrders
    }

    /// PATCH with optimistic concurrency. Prefer `row_version` when known;
    /// otherwise filter on the last-seen `updated_at`. Empty representation ⇒ conflict.
    func patchWithOptimisticConcurrency(
        endpoint: String,
        id: String,
        payload: [String: Any],
        expectedRowVersion: Int? = nil,
        expectedUpdatedAt: Date? = nil
    ) async throws -> [[String: Any]] {
        var queryItems = [URLQueryItem(name: "id", value: "eq.\(id)")]
        if let version = expectedRowVersion {
            queryItems.append(URLQueryItem(name: "row_version", value: "eq.\(version)"))
        } else if let updatedAt = expectedUpdatedAt {
            queryItems.append(URLQueryItem(
                name: "updated_at",
                value: "eq.\(NetworkManager.iso8601.string(from: updatedAt))"
            ))
        }

        let data = try await sendSupabaseRequest(
            method: "PATCH",
            endpoint: endpoint,
            queryItems: queryItems,
            payload: payload
        )
        let rows = (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
        if (expectedRowVersion != nil || expectedUpdatedAt != nil) && rows.isEmpty {
            throw NetworkError.conflict("\(endpoint) id=\(id) changed on server")
        }
        return rows
    }

    /// Shared hub health from `sync_outbox` (same RPC as Staff + customer-order-web).
    /// Always passes `p_merchant_id` so the RPC works even when JWT claim path differs.
    func fetchSyncHealth() async throws -> [String: Any] {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        var payload: [String: Any] = [:]
        if !merchantId.isEmpty {
            payload["p_merchant_id"] = merchantId.lowercased()
        }
        let data = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "rpc/get_sync_health",
            payload: payload
        )
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let ok = obj["ok"] as? Bool, ok == false {
                let message = (obj["error"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                throw NetworkError.serverError(message?.isEmpty == false ? message! : "get_sync_health failed")
            }
            return obj
        }
        throw NetworkError.invalidResponse
    }

    /// Exact row count via PostgREST `Prefer: count=exact` (Content-Range).
    /// Used by Sync Health to show live cloud totals next to the device queue.
    func fetchExactRowCount(endpoint: String, extraFilters: [URLQueryItem] = []) async throws -> Int {
        if simulateOffline || !NetworkPolicy.shared.allows(.cloudData) { throw NetworkError.offlineModeProhibited }

        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "select", value: "id"),
            URLQueryItem(name: "limit", value: "1")
        ]
        if !merchantId.isEmpty {
            queryItems.append(URLQueryItem(name: "merchant_id", value: "eq.\(merchantId.lowercased())"))
        }
        queryItems.append(contentsOf: extraFilters)

        var url = serverBaseURL.appendingPathComponent(endpoint)
        if var components = URLComponents(url: url, resolvingAgainstBaseURL: true) {
            components.queryItems = queryItems
            if let newURL = components.url { url = newURL }
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let token = MerchantAuthManager.shared.authorizationToken ?? anonKey
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("count=exact", forHTTPHeaderField: "Prefer")
        request.setValue("0-0", forHTTPHeaderField: "Range")
        if !merchantId.isEmpty {
            request.setValue(merchantId, forHTTPHeaderField: "x-merchant-id")
        }
        request.timeoutInterval = 8.0

        let (_, response) = try await AppNetworkTransport.data(for: request, purpose: .cloudData)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) || http.statusCode == 206 else {
            throw NetworkError.invalidResponse
        }

        let range = http.value(forHTTPHeaderField: "Content-Range")
            ?? (http.allHeaderFields["Content-Range"] as? String)
        guard let range, let slash = range.lastIndex(of: "/") else {
            return 0
        }
        let totalPart = range[range.index(after: slash)...].trimmingCharacters(in: .whitespaces)
        return Int(totalPart) ?? 0
    }

    func claimSyncOutbox(limit: Int = 20) async throws -> [[String: Any]] {
        let data = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "rpc/claim_sync_outbox",
            payload: ["p_limit": limit]
        )
        return (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
    }

    func completeSyncOutbox(id: String, success: Bool, error: String? = nil) async throws {
        var payload: [String: Any] = [
            "p_id": id,
            "p_success": success
        ]
        if let error { payload["p_error"] = error }
        _ = try await sendSupabaseRequest(
            method: "POST",
            endpoint: "rpc/complete_sync_outbox",
            payload: payload
        )
    }

}
