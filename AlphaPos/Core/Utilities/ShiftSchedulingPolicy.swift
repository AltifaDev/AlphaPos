import Foundation

/// Pure scheduling rules shared by the roster UI and command-line tests.
enum ShiftSchedulingPolicy {
    struct Interval: Equatable {
        let id: UUID
        let start: Date
        let end: Date
    }

    static func isValid(start: Date, end: Date) -> Bool {
        start < end
    }

    static func overlaps(start: Date, end: Date, otherStart: Date, otherEnd: Date) -> Bool {
        start < otherEnd && end > otherStart
    }

    static func hasConflict(start: Date, end: Date, existing: [Interval], excluding id: UUID? = nil) -> Bool {
        existing.contains { interval in
            interval.id != id && overlaps(
                start: start,
                end: end,
                otherStart: interval.start,
                otherEnd: interval.end
            )
        }
    }

    /// Counts each shift once and only the portion falling inside the requested range.
    static func hours(in range: DateInterval, intervals: [Interval]) -> Double {
        let unique = Dictionary(grouping: intervals, by: \.id).compactMap(\.value.first)
        let seconds = unique.reduce(0.0) { total, interval in
            let clippedStart = max(interval.start, range.start)
            let clippedEnd = min(interval.end, range.end)
            return total + max(0, clippedEnd.timeIntervalSince(clippedStart))
        }
        return seconds / 3600
    }
}
