import Foundation
import CryptoKit
import SwiftData

enum NetworkError: Error, LocalizedError {
    case offline
    case serverError(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .offline: return "No internet connection detected."
        case .serverError(let msg): return "Server returned error: \(msg)"
        case .invalidResponse: return "Received invalid response from server."
        }
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

    var isWebOrderingEnabled: Bool {
        UserDefaults.standard.object(forKey: "enable_web_ordering") as? Bool ?? true
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
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
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
        if simulateOffline { return false }

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
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        if !merchantId.isEmpty {
            request.setValue(merchantId, forHTTPHeaderField: "x-merchant-id")
        }
        request.timeoutInterval = 5.0
        // Note: fetchCustomerOrders uses a joined query with order_items(*) which
        // can be slow. The per-request override below handles that case.

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
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
    func sendSupabaseRequest(method: String, endpoint: String, queryItems: [URLQueryItem]? = nil, payload: Any? = nil, timeoutOverride: Double? = nil) async throws -> Data {
        if simulateOffline {
            throw NetworkError.offline
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
        // Falls back to anon key during transition period.
        let token = MerchantAuthManager.shared.currentToken ?? anonKey
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
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

        let (data, response) = try await URLSession.shared.data(for: request)

        let httpStatusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

        guard (200...299).contains(httpStatusCode) else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "HTTP Request failed"
            let isAuthError = errorMsg.contains("PGRST301")
                || httpStatusCode == 401
                || httpStatusCode == 403
            if isAuthError {
                // Try to refresh the token once before giving up.
                // PGRST301 = JWT decryption error (token expired or wrong key).
                // Do NOT logout immediately — that makes all subsequent syncs use
                // anonKey which has no merchant_id claim → RLS blocks order_items inserts.
                let refreshed = await MerchantAuthManager.shared.tryRefresh()
                if refreshed {
                    // Retry the original request with the fresh token
                    let newToken = MerchantAuthManager.shared.currentToken ?? anonKey
                    request.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                    let (retryData, retryResponse) = (try? await URLSession.shared.data(for: request))
                        ?? (Data(), URLResponse())
                    if let retryHTTP = retryResponse as? HTTPURLResponse,
                       (200...299).contains(retryHTTP.statusCode) {
                        return retryData
                    }
                }
                // Refresh failed or retry still failed — log but do NOT logout
                #if DEBUG
                print("NetworkManager: Auth error (\(httpStatusCode)) — token refresh attempted. errorMsg: \(errorMsg.prefix(200))")
                #endif
            }
            throw NetworkError.serverError(errorMsg)
        }

        return data
    }

    // Pull active orders from customer self-ordering database in Supabase
    func fetchCustomerOrders() async throws -> [[String: Any]] {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? config.defaultMerchantId
        let data = try await sendSupabaseRequest(method: "GET", endpoint: "orders", queryItems: [
            URLQueryItem(name: "select", value: "*,order_items(*),payments(*)"),
            URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)"),
            // Only fetch active/recent orders — reduces payload size and join cost significantly.
            // "completed" is included so POS can show settled orders in the same session.
            URLQueryItem(name: "status", value: "in.(preparing,ready,served,completed)"),
            URLQueryItem(name: "is_deleted", value: "eq.false"),
            URLQueryItem(name: "order", value: "created_at.desc"),
            URLQueryItem(name: "limit", value: "50")
        ], timeoutOverride: 15.0)

        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw NetworkError.invalidResponse
        }

        func fetchDirectOrderItems(orderId: String) async throws -> [[String: Any]] {
            let itemsData = try await sendSupabaseRequest(method: "GET", endpoint: "order_items", queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "order_id", value: "eq.\(orderId)"),
                URLQueryItem(name: "merchant_id", value: "eq.\(merchantId)"),
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

            // Map items
            var items = dict["order_items"] as? [[String: Any]] ?? []
            if items.isEmpty, let orderId = dict["id"] as? String, !orderId.isEmpty {
                items = (try? await fetchDirectOrderItems(orderId: orderId)) ?? []
            }
            mapped["items"] = items.map { itemDict in
                    var mappedItem = itemDict
                    mappedItem["name"] = itemDict["item_name"]
                    mappedItem["itemId"] = itemDict["item_id"]
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
}
