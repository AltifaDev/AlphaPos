import Foundation

/// Pure delivery rules shared by sync and UI stores. Keeping these decisions
/// deterministic makes notification regressions testable without networking.
enum NotificationDeliveryPolicy {
    static let recentEventWindow: TimeInterval = 300
    static let repeatCooldown: TimeInterval = 600
    static let historyWindow: TimeInterval = 24 * 60 * 60
    static let allowedClockSkew: TimeInterval = 5 * 60

    /// Actionable POS work belongs to the current local business day. This is
    /// intentionally stricter than a rolling 24-hour window: an order from late
    /// yesterday must not return to today's queue after end-of-day reconciliation.
    static func isInCurrentBusinessDay(
        _ createdAt: Date?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard let createdAt else { return false }
        let start = calendar.startOfDay(for: now)
        return createdAt >= start && createdAt <= now.addingTimeInterval(allowedClockSkew)
    }

    /// History remains available in storage for audit purposes, but the active
    /// Notification Center only shows fresh events. Inventory is excluded from
    /// this rule because its live row is condition-based and clears on recovery.
    static func shouldShowHistory(
        categoryRawValue: String,
        createdAt: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        let age = now.timeIntervalSince(createdAt)
        guard age >= -allowedClockSkew, age < historyWindow else { return false }

        switch categoryRawValue {
        case "Orders", "Kitchen", "Staff", "Customer", "Payment":
            return isInCurrentBusinessDay(createdAt, now: now, calendar: calendar)
        default:
            return true
        }
    }

    static func isRecent(
        _ createdAt: Date?,
        now: Date = Date(),
        window: TimeInterval = recentEventWindow
    ) -> Bool {
        guard let createdAt else { return false }
        let age = now.timeIntervalSince(createdAt)
        return age >= 0 && age < window
    }

    static func shouldDeliverPulledEvent(
        isFirstSync: Bool,
        createdAt: Date?,
        now: Date = Date()
    ) -> Bool {
        !isFirstSync && isRecent(createdAt, now: now)
    }

    static func shouldDeliverRepeatedAlert(
        lastDeliveredAt: Date?,
        now: Date = Date(),
        cooldown: TimeInterval = repeatCooldown
    ) -> Bool {
        guard let lastDeliveredAt else { return true }
        return now.timeIntervalSince(lastDeliveredAt) >= cooldown
    }

    static func historyDuplicatesLiveOrder(
        historyOrderNumber: String?,
        liveOrderNumbers: Set<String>
    ) -> Bool {
        guard let historyOrderNumber else { return false }
        return liveOrderNumbers.contains(historyOrderNumber)
    }
}
