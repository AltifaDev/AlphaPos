import Foundation

enum BusinessDayTestClock {
    static func key(_ text: String, cutoff: Int = 4) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let date = formatter.date(from: text)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Bangkok")!
        let shifted = calendar.date(byAdding: .hour, value: -cutoff, to: date)!
        let c = calendar.dateComponents([.year, .month, .day], from: shifted)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
}

enum BusinessDayTests {
    static func runAll() -> [TestResult] {
        [beforeMidnight(), afterMidnightSameBusinessDay(), cutoffStartsNewBusinessDay(), calendarDateRemainsAuditable()]
    }

    private static func beforeMidnight() -> TestResult {
        let name = #function
        return BusinessDayTestClock.key("2026-08-23T16:30:00Z") == "2026-08-23" ? .success(name) : .failure(name, "23:30 ICT must belong to Aug 23.")
    }

    private static func afterMidnightSameBusinessDay() -> TestResult {
        let name = #function
        return BusinessDayTestClock.key("2026-08-23T17:30:00Z") == "2026-08-23" ? .success(name) : .failure(name, "00:30 ICT must remain on the preceding business date.")
    }

    private static func cutoffStartsNewBusinessDay() -> TestResult {
        let name = #function
        return BusinessDayTestClock.key("2026-08-23T21:00:00Z") == "2026-08-24" ? .success(name) : .failure(name, "04:00 ICT must start Aug 24 business date.")
    }

    private static func calendarDateRemainsAuditable() -> TestResult {
        let name = #function
        let actual = ISO8601DateFormatter().date(from: "2026-08-23T17:30:00Z")!
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Asia/Bangkok")!
        return cal.component(.day, from: actual) == 24 && BusinessDayTestClock.key("2026-08-23T17:30:00Z") == "2026-08-23"
            ? .success(name) : .failure(name, "Calendar and business dates must coexist.")
    }
}
