import Foundation

enum ShiftSchedulingPolicyTests {
    static func runAll() -> [TestResult] {
        [
            test_adjacentShiftsDoNotOverlap(),
            test_overlappingShiftsConflict(),
            test_crossMidnightHoursCountOnce(),
            test_weekBoundaryClipsHours(),
            test_invalidRangeRejected()
        ]
    }

    private static func date(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: value)!
    }

    private static func test_adjacentShiftsDoNotOverlap() -> TestResult {
        let name = #function
        let result = ShiftSchedulingPolicy.overlaps(
            start: date("2026-08-10T09:00:00Z"), end: date("2026-08-10T17:00:00Z"),
            otherStart: date("2026-08-10T17:00:00Z"), otherEnd: date("2026-08-10T22:00:00Z")
        )
        return !result ? .success(name) : .failure(name, "Adjacent shifts must be allowed")
    }

    private static func test_overlappingShiftsConflict() -> TestResult {
        let name = #function
        let result = ShiftSchedulingPolicy.overlaps(
            start: date("2026-08-10T09:00:00Z"), end: date("2026-08-10T17:00:00Z"),
            otherStart: date("2026-08-10T16:00:00Z"), otherEnd: date("2026-08-10T20:00:00Z")
        )
        return result ? .success(name) : .failure(name, "Overlapping shifts must be rejected")
    }

    private static func test_crossMidnightHoursCountOnce() -> TestResult {
        let name = #function
        let id = UUID()
        let interval = ShiftSchedulingPolicy.Interval(
            id: id, start: date("2026-08-10T17:00:00Z"), end: date("2026-08-11T01:00:00Z")
        )
        let hours = ShiftSchedulingPolicy.hours(
            in: DateInterval(start: date("2026-08-10T00:00:00Z"), end: date("2026-08-17T00:00:00Z")),
            intervals: [interval, interval]
        )
        return hours == 8 ? .success(name) : .failure(name, "Expected 8 hours, got \(hours)")
    }

    private static func test_weekBoundaryClipsHours() -> TestResult {
        let name = #function
        let interval = ShiftSchedulingPolicy.Interval(
            id: UUID(), start: date("2026-08-09T22:00:00Z"), end: date("2026-08-10T02:00:00Z")
        )
        let hours = ShiftSchedulingPolicy.hours(
            in: DateInterval(start: date("2026-08-10T00:00:00Z"), end: date("2026-08-17T00:00:00Z")),
            intervals: [interval]
        )
        return hours == 2 ? .success(name) : .failure(name, "Expected 2 clipped hours, got \(hours)")
    }

    private static func test_invalidRangeRejected() -> TestResult {
        let name = #function
        let instant = date("2026-08-10T09:00:00Z")
        return !ShiftSchedulingPolicy.isValid(start: instant, end: instant)
            ? .success(name) : .failure(name, "Zero-duration shift must be rejected")
    }
}
