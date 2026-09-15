import Foundation

enum NotificationDeliveryPolicyTests {
    static func runAll() -> [TestResult] {
        [
            test_first_sync_never_replays(),
            test_recent_event_delivers_after_baseline(),
            test_future_timestamp_is_not_recent(),
            test_each_delayed_event_has_independent_cooldown(),
            test_history_order_deduplicates_against_live(),
            test_unrelated_history_remains_visible(),
            test_operational_work_does_not_cross_business_day(),
            test_current_day_operational_work_is_visible(),
            test_transaction_history_does_not_cross_business_day(),
            test_inventory_history_uses_rolling_window()
        ]
    }

    private static func test_first_sync_never_replays() -> TestResult {
        let now = Date()
        let delivered = NotificationDeliveryPolicy.shouldDeliverPulledEvent(
            isFirstSync: true,
            createdAt: now.addingTimeInterval(-10),
            now: now
        )
        return delivered
            ? .failure(#function, "Cold-start baseline replayed an existing event")
            : .success(#function)
    }

    private static func test_recent_event_delivers_after_baseline() -> TestResult {
        let now = Date()
        let delivered = NotificationDeliveryPolicy.shouldDeliverPulledEvent(
            isFirstSync: false,
            createdAt: now.addingTimeInterval(-10),
            now: now
        )
        return delivered
            ? .success(#function)
            : .failure(#function, "Recent post-baseline event was suppressed")
    }

    private static func test_future_timestamp_is_not_recent() -> TestResult {
        let now = Date()
        return NotificationDeliveryPolicy.isRecent(
            now.addingTimeInterval(60),
            now: now
        )
            ? .failure(#function, "Future clock-skew event was treated as new")
            : .success(#function)
    }

    private static func test_each_delayed_event_has_independent_cooldown() -> TestResult {
        let now = Date()
        let first = NotificationDeliveryPolicy.shouldDeliverRepeatedAlert(
            lastDeliveredAt: now.addingTimeInterval(-60),
            now: now
        )
        let second = NotificationDeliveryPolicy.shouldDeliverRepeatedAlert(
            lastDeliveredAt: nil,
            now: now
        )
        return !first && second
            ? .success(#function)
            : .failure(#function, "One order's cooldown affected another order")
    }

    private static func test_history_order_deduplicates_against_live() -> TestResult {
        let duplicate = NotificationDeliveryPolicy.historyDuplicatesLiveOrder(
            historyOrderNumber: "ORD-100",
            liveOrderNumbers: ["ORD-100", "ORD-200"]
        )
        return duplicate
            ? .success(#function)
            : .failure(#function, "Matching history/live order was not deduplicated")
    }

    private static func test_unrelated_history_remains_visible() -> TestResult {
        let duplicate = NotificationDeliveryPolicy.historyDuplicatesLiveOrder(
            historyOrderNumber: "ORD-300",
            liveOrderNumbers: ["ORD-100", "ORD-200"]
        )
        return duplicate
            ? .failure(#function, "Unrelated history event was incorrectly hidden")
            : .success(#function)
    }

    private static func fixedCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 7 * 3600)!
        return calendar
    }

    private static func test_operational_work_does_not_cross_business_day() -> TestResult {
        let calendar = fixedCalendar()
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 16, hour: 0, minute: 30))!
        let yesterday = calendar.date(from: DateComponents(year: 2026, month: 8, day: 15, hour: 23, minute: 59))!
        return NotificationDeliveryPolicy.isInCurrentBusinessDay(yesterday, now: now, calendar: calendar)
            ? .failure(#function, "Previous-day work leaked into the new business day")
            : .success(#function)
    }

    private static func test_current_day_operational_work_is_visible() -> TestResult {
        let calendar = fixedCalendar()
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 16, hour: 14))!
        let createdAt = calendar.date(from: DateComponents(year: 2026, month: 8, day: 16, hour: 1))!
        return NotificationDeliveryPolicy.isInCurrentBusinessDay(createdAt, now: now, calendar: calendar)
            ? .success(#function)
            : .failure(#function, "Current-day work was hidden")
    }

    private static func test_transaction_history_does_not_cross_business_day() -> TestResult {
        let calendar = fixedCalendar()
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 16, hour: 0, minute: 30))!
        let yesterday = calendar.date(from: DateComponents(year: 2026, month: 8, day: 15, hour: 23, minute: 59))!
        return NotificationDeliveryPolicy.shouldShowHistory(
            categoryRawValue: "Orders",
            createdAt: yesterday,
            now: now,
            calendar: calendar
        )
            ? .failure(#function, "Previous-day order history remained in the active center")
            : .success(#function)
    }

    private static func test_inventory_history_uses_rolling_window() -> TestResult {
        let calendar = fixedCalendar()
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 16, hour: 0, minute: 30))!
        let yesterday = calendar.date(from: DateComponents(year: 2026, month: 8, day: 15, hour: 23, minute: 59))!
        return NotificationDeliveryPolicy.shouldShowHistory(
            categoryRawValue: "Inventory",
            createdAt: yesterday,
            now: now,
            calendar: calendar
        )
            ? .success(#function)
            : .failure(#function, "Fresh inventory history was incorrectly tied to end-of-day")
    }
}
