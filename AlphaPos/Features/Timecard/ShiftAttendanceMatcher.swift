import Foundation

/// Pure helpers that link attendance events to scheduled shift windows.
enum ShiftAttendanceMatcher {
    /// Default grace before a clock-in is considered late / clock-out early (minutes).
    static let defaultGraceMinutes = 10

    struct ShiftWindow: Equatable {
        let start: Date
        let end: Date
        let isDeleted: Bool

        init(start: Date, end: Date, isDeleted: Bool = false) {
            self.start = start
            self.end = end
            self.isDeleted = isDeleted
        }

        #if !TEST_RUNNER
        init(_ shift: EmployeeShift) {
            self.start = shift.scheduledStart
            self.end = shift.scheduledEnd
            self.isDeleted = shift.isDeleted
        }
        #endif
    }

    /// Pick the best shift window on a calendar day around `date`.
    /// Preference: containing window → upcoming today → latest started today → first of day.
    static func activeShiftWindow(
        from windows: [ShiftWindow],
        at date: Date,
        calendar: Calendar = .current
    ) -> ShiftWindow? {
        let dayStart = calendar.startOfDay(for: date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return nil }

        let dayWindows = windows
            .filter { !$0.isDeleted }
            .filter { $0.start < dayEnd && $0.end > dayStart }
            .sorted { $0.start < $1.start }

        if let containing = dayWindows.first(where: { date >= $0.start && date <= $0.end }) {
            return containing
        }
        if let upcoming = dayWindows.first(where: { $0.start > date }) {
            return upcoming
        }
        if let recent = dayWindows.last(where: { $0.start <= date }) {
            return recent
        }
        return dayWindows.first
    }

    #if !TEST_RUNNER
    @MainActor
    static func activeShift(
        from shifts: [EmployeeShift],
        at date: Date,
        calendar: Calendar = .current
    ) -> EmployeeShift? {
        let windows = shifts.map(ShiftWindow.init)
        guard let match = activeShiftWindow(from: windows, at: date, calendar: calendar) else { return nil }
        return shifts.first {
            !$0.isDeleted &&
            $0.scheduledStart == match.start &&
            $0.scheduledEnd == match.end
        }
    }
    #endif

    /// Minutes late past schedule start, after grace. Zero if on time / early.
    static func lateMinutes(
        clockIn: Date,
        scheduledStart: Date,
        graceMinutes: Int = defaultGraceMinutes
    ) -> Int {
        let threshold = scheduledStart.addingTimeInterval(TimeInterval(graceMinutes * 60))
        guard clockIn > threshold else { return 0 }
        return max(0, Int(clockIn.timeIntervalSince(scheduledStart) / 60))
    }

    /// Minutes early before schedule end, after grace. Zero if on time / late out.
    static func earlyOutMinutes(
        clockOut: Date,
        scheduledEnd: Date,
        graceMinutes: Int = defaultGraceMinutes
    ) -> Int {
        let threshold = scheduledEnd.addingTimeInterval(-TimeInterval(graceMinutes * 60))
        guard clockOut < threshold else { return 0 }
        return max(0, Int(scheduledEnd.timeIntervalSince(clockOut) / 60))
    }

    /// OT minutes = time worked after scheduled end.
    static func overtimeMinutes(
        clockOut: Date,
        scheduledEnd: Date
    ) -> Int {
        guard clockOut > scheduledEnd else { return 0 }
        return max(0, Int(clockOut.timeIntervalSince(scheduledEnd) / 60))
    }

    struct ClockInDecision: Equatable {
        let hasShift: Bool
        let status: String
        let notes: String
        let lateMinutes: Int
    }

    static func clockInDecision(
        hasShift: Bool,
        scheduledStart: Date?,
        clockIn: Date,
        graceMinutes: Int = defaultGraceMinutes
    ) -> ClockInDecision {
        guard hasShift, let scheduledStart else {
            return ClockInDecision(
                hasShift: false,
                status: "pending_audit",
                notes: "Unscheduled clock-in (No shift found)",
                lateMinutes: 0
            )
        }

        let late = lateMinutes(clockIn: clockIn, scheduledStart: scheduledStart, graceMinutes: graceMinutes)
        if late > 0 {
            return ClockInDecision(
                hasShift: true,
                status: "pending_audit",
                notes: "Late \(late) min vs schedule",
                lateMinutes: late
            )
        }

        return ClockInDecision(
            hasShift: true,
            status: "approved",
            notes: "Clock-in matched scheduled shift",
            lateMinutes: 0
        )
    }

    #if !TEST_RUNNER
    static func clockInDecision(
        shift: EmployeeShift?,
        clockIn: Date,
        graceMinutes: Int = defaultGraceMinutes
    ) -> ClockInDecision {
        clockInDecision(
            hasShift: shift != nil,
            scheduledStart: shift?.scheduledStart,
            clockIn: clockIn,
            graceMinutes: graceMinutes
        )
    }
    #endif

    struct ClockOutDecision: Equatable {
        let overtimeMinutes: Int
        let earlyOutMinutes: Int
        let notesSuffix: String?
        let status: String
    }

    static func clockOutDecision(
        scheduledEnd: Date?,
        clockOut: Date,
        graceMinutes: Int = defaultGraceMinutes
    ) -> ClockOutDecision {
        guard let scheduledEnd else {
            return ClockOutDecision(
                overtimeMinutes: 0,
                earlyOutMinutes: 0,
                notesSuffix: nil,
                status: "pending_audit"
            )
        }

        let ot = overtimeMinutes(clockOut: clockOut, scheduledEnd: scheduledEnd)
        let early = earlyOutMinutes(clockOut: clockOut, scheduledEnd: scheduledEnd, graceMinutes: graceMinutes)

        var parts: [String] = []
        if ot > 0 { parts.append("OT \(ot) min after schedule") }
        if early > 0 { parts.append("Early out \(early) min") }

        return ClockOutDecision(
            overtimeMinutes: ot,
            earlyOutMinutes: early,
            notesSuffix: parts.isEmpty ? nil : parts.joined(separator: " · "),
            status: early > 0 ? "pending_audit" : "approved"
        )
    }

    #if !TEST_RUNNER
    static func clockOutDecision(
        shift: EmployeeShift?,
        clockOut: Date,
        existingNotes: String?,
        graceMinutes: Int = defaultGraceMinutes
    ) -> ClockOutDecision {
        _ = existingNotes
        return clockOutDecision(
            scheduledEnd: shift?.scheduledEnd,
            clockOut: clockOut,
            graceMinutes: graceMinutes
        )
    }
    #endif

    static func mergeNotes(_ existing: String?, _ suffix: String?) -> String? {
        let parts = [existing, suffix]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
