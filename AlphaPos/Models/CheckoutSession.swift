import Foundation
import SwiftData

enum POSServiceMode: String, CaseIterable, Codable {
    case tableService = "table_service"
    case quickService = "quick_service"
    case takeaway = "takeaway"
    case delivery = "delivery"

    static func resolve(orderType: String, hasTable: Bool) -> POSServiceMode {
        if hasTable { return .tableService }
        switch orderType {
        case "delivery": return .delivery
        case "take_out": return .takeaway
        default: return .quickService
        }
    }
}

enum CheckoutSessionState: String, Codable {
    case open
    case parked
    case processing
    case completed
    case abandoned
}

enum PaymentAttemptState: String, Codable {
    case created
    case awaitingCustomer = "awaiting_customer"
    case processing
    case requiresAction = "requires_action"
    case authorized
    case captured
    case failed
    case cancelled
    case expired
    case unknown

    var isTerminal: Bool {
        [.captured, .failed, .cancelled, .expired].contains(self)
    }
}

/// Durable quick-service checkout context. A parked checkout remains attached to
/// its original order; recalling it never deletes/recreates financial records.
@Model
final class CheckoutSession {
    @Attribute(.unique) var id: UUID
    var merchantId: UUID
    var order: Order?
    var serviceMode: String
    var state: String
    var version: Int
    var lockedByDevice: String?
    var lockedAt: Date?
    var parkedAt: Date?
    var completedAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var isSynced: Bool
    var isDeleted: Bool

    @Relationship(deleteRule: .cascade, inverse: \PaymentAttempt.checkoutSession)
    var paymentAttempts: [PaymentAttempt] = []

    init(
        id: UUID = UUID(), merchantId: UUID, order: Order?, serviceMode: POSServiceMode,
        state: CheckoutSessionState = .open, version: Int = 1,
        lockedByDevice: String? = nil, lockedAt: Date? = nil,
        parkedAt: Date? = nil, completedAt: Date? = nil,
        createdAt: Date = Date(), updatedAt: Date = Date(),
        isSynced: Bool = false, isDeleted: Bool = false
    ) {
        self.id = id
        self.merchantId = merchantId
        self.order = order
        self.serviceMode = serviceMode.rawValue
        self.state = state.rawValue
        self.version = version
        self.lockedByDevice = lockedByDevice
        self.lockedAt = lockedAt
        self.parkedAt = parkedAt
        self.completedAt = completedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isSynced = isSynced
        self.isDeleted = isDeleted
    }

    var lifecycleState: CheckoutSessionState {
        get { CheckoutSessionState(rawValue: state) ?? .open }
        set { state = newValue.rawValue; updatedAt = Date(); version += 1; isSynced = false }
    }

    func acquireLock(deviceId: String, timeout: TimeInterval = 120) -> Bool {
        if let owner = lockedByDevice, owner != deviceId,
           let lockedAt, Date().timeIntervalSince(lockedAt) < timeout { return false }
        lockedByDevice = deviceId
        lockedAt = Date()
        updatedAt = Date()
        version += 1
        isSynced = false
        return true
    }

    func releaseLock(deviceId: String) {
        guard lockedByDevice == nil || lockedByDevice == deviceId else { return }
        lockedByDevice = nil
        lockedAt = nil
        updatedAt = Date()
        version += 1
        isSynced = false
    }
}

@Model
final class PaymentAttempt {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var idempotencyKey: String
    var merchantId: UUID
    var checkoutSession: CheckoutSession?
    var order: Order?
    var method: String
    var amount: Double
    var currency: String
    var status: String
    var providerReference: String?
    var failureReason: String?
    var expiresAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var isSynced: Bool
    var isDeleted: Bool

    init(
        id: UUID = UUID(), merchantId: UUID, checkoutSession: CheckoutSession?, order: Order?,
        method: String, amount: Double, currency: String = "THB",
        status: PaymentAttemptState = .created, providerReference: String? = nil,
        failureReason: String? = nil, expiresAt: Date? = nil,
        idempotencyKey: String? = nil, createdAt: Date = Date(), updatedAt: Date = Date(),
        isSynced: Bool = false, isDeleted: Bool = false
    ) {
        self.id = id
        self.merchantId = merchantId
        self.checkoutSession = checkoutSession
        self.order = order
        let normalizedMethod = method.lowercased().replacingOccurrences(of: " ", with: "_")
        self.method = normalizedMethod
        self.amount = amount
        self.currency = currency
        self.status = status.rawValue
        self.providerReference = providerReference
        self.failureReason = failureReason
        self.expiresAt = expiresAt
        self.idempotencyKey = idempotencyKey ?? "checkout:\(checkoutSession?.id.uuidString ?? order?.id.uuidString ?? id.uuidString):\(normalizedMethod)"
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isSynced = isSynced
        self.isDeleted = isDeleted
    }

    var lifecycleState: PaymentAttemptState {
        get { PaymentAttemptState(rawValue: status) ?? .unknown }
        set { status = newValue.rawValue; updatedAt = Date(); isSynced = false }
    }
}
