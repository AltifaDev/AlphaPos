import Foundation
import SwiftData

@Model
final class TableSession {
    /// A table session is never allowed to live forever merely because an
    /// `is_active` flag was left behind by an interrupted checkout/sync.
    /// This still covers normal overnight service while bounding stale data.
    static let maximumOperationalAge: TimeInterval = 24 * 60 * 60
    private static let futureClockTolerance: TimeInterval = 5 * 60
    private static let statusReconciliationGrace: TimeInterval = 5 * 60
    static let orderClockTolerance: TimeInterval = 5 * 60
    @Attribute(.unique) var id: UUID
    var sessionToken: String // Generated dynamically for customer mobile web access validation
    var startedAt: Date
    var endedAt: Date?
    var isActive: Bool
    var table: RestaurantTable?
    
    @Relationship(deleteRule: .nullify, inverse: \Order.tableSession)
    var orders: [Order] = []
    
    // Offline-First Sync Metadata
    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date
    var rowVersion: Int = 0
    
    var guestCount: Int = 2
    var cashierName: String = ""
    var queueNumber: String? = nil
    
    var totalAmount: Double {
        orders.filter {
            ownsCurrentOrder($0)
                && !$0.isDeleted
                && !$0.isSettled
                && $0.status != "cancelled"
        }.reduce(0.0) { $0 + $1.total }
    }

    /// Number of visible product lines, not the sum of their quantities.
    var itemCount: Int {
        orders
            .filter {
                ownsCurrentOrder($0)
                    && !$0.isDeleted
                    && !$0.isSettled
                    && $0.status != "cancelled"
            }
            .reduce(0) { count, order in
                count + order.items.filter { !$0.isDeleted && $0.status != "cancelled" }.count
            }
    }

    /// Single gate used by the floor plan and POS before exposing a session.
    /// A later non-occupied table transition is authoritative over an older
    /// session row; `endedAt` and implausible timestamps also invalidate it.
    func isOperationallyActive(for table: RestaurantTable, now: Date = Date()) -> Bool {
        guard isActive, !isDeleted, endedAt == nil else { return false }

        let age = now.timeIntervalSince(startedAt)
        guard age >= -Self.futureClockTolerance,
              age <= Self.maximumOperationalAge else { return false }

        let status = table.status.lowercased()
        if status != "occupied" {
            let tableWasClearedLater = table.updatedAt > startedAt
            let statusMismatchExpired = age > Self.statusReconciliationGrace
            if tableWasClearedLater || statusMismatchExpired { return false }
        }
        return true
    }

    /// Canonical temporal ownership rule for an order and this session.
    /// Table numbers are reusable identifiers and are never sufficient proof
    /// that an order belongs to the current guests.
    func acceptsOrder(createdAt: Date, now: Date = Date()) -> Bool {
        let earliest = startedAt.addingTimeInterval(-Self.orderClockTolerance)
        let latest = now.addingTimeInterval(Self.futureClockTolerance)
        return createdAt >= earliest && createdAt <= latest
    }

    /// Strong relationship check used by totals/badges. Both the UUID link and
    /// temporal window must agree before an order is operationally visible.
    func ownsCurrentOrder(_ order: Order, now: Date = Date()) -> Bool {
        order.tableSession?.id == id
            && acceptsOrder(createdAt: order.createdAt, now: now)
    }
    
    init(id: UUID = UUID(), sessionToken: String = UUID().uuidString, startedAt: Date = Date(), endedAt: Date? = nil, isActive: Bool = true, table: RestaurantTable? = nil, guestCount: Int = 2, cashierName: String = "", queueNumber: String? = nil, isSynced: Bool = false, isDeleted: Bool = false, updatedAt: Date = Date(), rowVersion: Int = 0) {
        self.id = id
        self.sessionToken = sessionToken
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.isActive = isActive
        self.table = table
        self.guestCount = guestCount
        self.cashierName = cashierName
        self.queueNumber = queueNumber
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
        self.rowVersion = rowVersion
    }
}
