import Foundation
import Testing
@testable import AlphaPosStaff

@Suite("Staff notification lifecycle")
struct NotificationPolicyTests {
    private func bangkokCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 7 * 3600)!
        return calendar
    }

    @Test func previousDayWorkIsNotActiveAfterMidnight() {
        let calendar = bangkokCalendar()
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 16, hour: 0, minute: 30))!
        let previousDay = calendar.date(from: DateComponents(year: 2026, month: 8, day: 15, hour: 23, minute: 59))!
        #expect(!StaffNotificationPolicy.isCurrentBusinessDay(previousDay, now: now, calendar: calendar))
    }

    @Test func currentDayWorkRemainsActive() {
        let calendar = bangkokCalendar()
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 16, hour: 14))!
        let createdAt = calendar.date(from: DateComponents(year: 2026, month: 8, day: 16, hour: 1))!
        #expect(StaffNotificationPolicy.isCurrentBusinessDay(createdAt, now: now, calendar: calendar))
    }

    @Test func malformedTimestampIsNeverTreatedAsNew() {
        #expect(!StaffNotificationPolicy.isCurrentBusinessDay(timestamp: "invalid"))
        #expect(!StaffNotificationPolicy.isCurrentBusinessDay(timestamp: nil))
    }

    @Test func futureTimestampOutsideClockSkewIsRejected() {
        let now = Date()
        #expect(!StaffNotificationPolicy.isCurrentBusinessDay(
            now.addingTimeInterval(StaffNotificationPolicy.allowedClockSkew + 1),
            now: now
        ))
    }
}
