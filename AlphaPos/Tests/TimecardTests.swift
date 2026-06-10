// TimecardTests.swift
// AlphaPos — Phase 4: Unit Testing Suite
//
// Tests timecard / payroll business logic (pure; no SwiftData):
//   - Worked minutes = (clockOut − clockIn) − breakDuration
//   - OT threshold detection (minutes beyond normal shift)
//   - Regular vs. OT pay split
//   - Daily pay calculation (regular + OT)
//   - Overnight shift spanning midnight
//   - Break longer than worked time → clamp to 0 worked minutes
//   - Face-confidence threshold for auto-approval
//   - Status auto-approve vs pending_audit rules

import Foundation

// ─── Lightweight timecard helpers (pure functions) ───────────────────────────

private enum TimecardCalculator {

    /// Total worked minutes after subtracting break.
    /// Clamped at 0 — break cannot produce negative work time.
    static func workedMinutes(clockIn: Date, clockOut: Date, breakMinutes: Int) -> Int {
        let totalMinutes = Int(clockOut.timeIntervalSince(clockIn) / 60)
        return max(0, totalMinutes - breakMinutes)
    }

    /// Overtime minutes = worked minutes beyond the regular shift length.
    static func overtimeMinutes(workedMinutes: Int, regularShiftMinutes: Int) -> Int {
        max(0, workedMinutes - regularShiftMinutes)
    }

    /// Regular (non-OT) minutes capped at regularShiftMinutes.
    static func regularMinutes(workedMinutes: Int, regularShiftMinutes: Int) -> Int {
        min(workedMinutes, regularShiftMinutes)
    }

    /// Daily gross pay = regular pay + OT pay.
    /// - hourlyRate  : base hourly rate (THB)
    /// - otMultiplier: OT rate multiplier (e.g. 1.5 for time-and-a-half)
    static func dailyPay(
        workedMinutes:       Int,
        regularShiftMinutes: Int,
        hourlyRate:          Double,
        otMultiplier:        Double = 1.5
    ) -> Double {
        let regMin = Double(regularMinutes(workedMinutes: workedMinutes, regularShiftMinutes: regularShiftMinutes))
        let otMin  = Double(overtimeMinutes(workedMinutes: workedMinutes, regularShiftMinutes: regularShiftMinutes))
        let regularPay = (regMin / 60.0) * hourlyRate
        let otPay      = (otMin  / 60.0) * hourlyRate * otMultiplier
        return regularPay + otPay
    }

    /// Auto-approval logic: clock-in face confidence must meet threshold.
    static func shouldAutoApprove(clockInFaceConfidence: Double?, threshold: Double = 0.85) -> Bool {
        guard let confidence = clockInFaceConfidence else { return false }
        return confidence >= threshold
    }
}

// ─────────────────────────────────────────────────────────────────────────────

private let ε = 1e-6

private func approxEqual(_ a: Double, _ b: Double) -> Bool {
    abs(a - b) < ε
}

/// Convenience: create a Date from hour + minute offset from now's midnight.
private func dateAt(hour: Int, minute: Int, dayOffset: Int = 0) -> Date {
    var cal  = Calendar.current
    cal.timeZone = TimeZone(identifier: "Asia/Bangkok")!
    var comps = cal.dateComponents([.year, .month, .day], from: Date())
    comps.hour   = hour
    comps.minute = minute
    comps.second = 0
    var date = cal.date(from: comps)!
    if dayOffset != 0 {
        date = cal.date(byAdding: .day, value: dayOffset, to: date)!
    }
    return date
}

// MARK: -

enum TimecardTests {

    static func runAll() -> [TestResult] {
        [
            test_workedMinutes_standardShift(),
            test_workedMinutes_withBreak(),
            test_workedMinutes_breakLongerThanShift_clampsToZero(),
            test_workedMinutes_overnightShift(),
            test_overtimeMinutes_noOT(),
            test_overtimeMinutes_withOT(),
            test_regularMinutes_cappedAtShiftLength(),
            test_dailyPay_regularOnly(),
            test_dailyPay_withOT(),
            test_dailyPay_zeroHours(),
            test_autoApprove_highConfidence(),
            test_autoApprove_lowConfidence(),
            test_autoApprove_nilConfidence(),
            test_autoApprove_exactThreshold()
        ]
    }

    // MARK: - Worked minutes

    private static func test_workedMinutes_standardShift() -> TestResult {
        let name    = #function
        let clockIn  = dateAt(hour: 9,  minute: 0)
        let clockOut = dateAt(hour: 18, minute: 0)  // 9 h = 540 min
        let worked   = TimecardCalculator.workedMinutes(clockIn: clockIn, clockOut: clockOut, breakMinutes: 0)
        return worked == 540
            ? .success(name)
            : .failure(name, "Expected 540 worked minutes (9 h), got \(worked)")
    }

    private static func test_workedMinutes_withBreak() -> TestResult {
        let name     = #function
        let clockIn  = dateAt(hour: 8, minute: 0)
        let clockOut = dateAt(hour: 17, minute: 0)  // 9 h = 540 min gross
        let worked   = TimecardCalculator.workedMinutes(clockIn: clockIn, clockOut: clockOut, breakMinutes: 60)
        return worked == 480
            ? .success(name)
            : .failure(name, "Expected 480 worked min after 60-min break, got \(worked)")
    }

    private static func test_workedMinutes_breakLongerThanShift_clampsToZero() -> TestResult {
        let name     = #function
        let clockIn  = dateAt(hour: 9, minute: 0)
        let clockOut = dateAt(hour: 9, minute: 30)   // 30 min gross
        let worked   = TimecardCalculator.workedMinutes(clockIn: clockIn, clockOut: clockOut, breakMinutes: 60)
        return worked == 0
            ? .success(name)
            : .failure(name, "Break > gross time must clamp to 0, got \(worked)")
    }

    private static func test_workedMinutes_overnightShift() -> TestResult {
        let name     = #function
        // Shift: 22:00 today → 06:00 tomorrow (8 h = 480 min)
        let clockIn  = dateAt(hour: 22, minute: 0, dayOffset:  0)
        let clockOut = dateAt(hour:  6, minute: 0, dayOffset:  1)
        let worked   = TimecardCalculator.workedMinutes(clockIn: clockIn, clockOut: clockOut, breakMinutes: 0)
        return worked == 480
            ? .success(name)
            : .failure(name, "Overnight shift must produce 480 min, got \(worked)")
    }

    // MARK: - OT minutes

    private static func test_overtimeMinutes_noOT() -> TestResult {
        let name = #function
        let ot   = TimecardCalculator.overtimeMinutes(workedMinutes: 480, regularShiftMinutes: 480)
        return ot == 0
            ? .success(name)
            : .failure(name, "Exactly on-shift should produce 0 OT minutes, got \(ot)")
    }

    private static func test_overtimeMinutes_withOT() -> TestResult {
        let name = #function
        // worked 540 min, shift = 480 → 60 OT
        let ot   = TimecardCalculator.overtimeMinutes(workedMinutes: 540, regularShiftMinutes: 480)
        return ot == 60
            ? .success(name)
            : .failure(name, "Expected 60 OT minutes, got \(ot)")
    }

    // MARK: - Regular minutes

    private static func test_regularMinutes_cappedAtShiftLength() -> TestResult {
        let name = #function
        // worked 600, shift 480 → regular = 480
        let reg  = TimecardCalculator.regularMinutes(workedMinutes: 600, regularShiftMinutes: 480)
        return reg == 480
            ? .success(name)
            : .failure(name, "Regular minutes must be capped at 480, got \(reg)")
    }

    // MARK: - Daily pay

    private static func test_dailyPay_regularOnly() -> TestResult {
        let name = #function
        // Exactly on-shift: 480 min = 8 h × 100 THB/h = 800 THB
        let pay  = TimecardCalculator.dailyPay(
            workedMinutes:       480,
            regularShiftMinutes: 480,
            hourlyRate:          100.0
        )
        return approxEqual(pay, 800.0)
            ? .success(name)
            : .failure(name, "Expected 800.0 THB regular pay, got \(pay)")
    }

    private static func test_dailyPay_withOT() -> TestResult {
        let name = #function
        // 540 min worked, shift 480 min, rate 100 THB/h, OT ×1.5
        // Regular: 8 h × 100 = 800
        // OT:      1 h × 150 = 150
        // Total:   950
        let pay  = TimecardCalculator.dailyPay(
            workedMinutes:       540,
            regularShiftMinutes: 480,
            hourlyRate:          100.0,
            otMultiplier:        1.5
        )
        return approxEqual(pay, 950.0)
            ? .success(name)
            : .failure(name, "Expected 950.0 THB (regular + OT), got \(pay)")
    }

    private static func test_dailyPay_zeroHours() -> TestResult {
        let name = #function
        let pay  = TimecardCalculator.dailyPay(
            workedMinutes:       0,
            regularShiftMinutes: 480,
            hourlyRate:          100.0
        )
        return approxEqual(pay, 0.0)
            ? .success(name)
            : .failure(name, "Zero worked hours must yield 0 pay, got \(pay)")
    }

    // MARK: - Face-confidence auto-approval

    private static func test_autoApprove_highConfidence() -> TestResult {
        let name = #function
        return TimecardCalculator.shouldAutoApprove(clockInFaceConfidence: 0.97)
            ? .success(name)
            : .failure(name, "High confidence (0.97) should auto-approve")
    }

    private static func test_autoApprove_lowConfidence() -> TestResult {
        let name = #function
        return !TimecardCalculator.shouldAutoApprove(clockInFaceConfidence: 0.60)
            ? .success(name)
            : .failure(name, "Low confidence (0.60) must NOT auto-approve")
    }

    private static func test_autoApprove_nilConfidence() -> TestResult {
        let name = #function
        return !TimecardCalculator.shouldAutoApprove(clockInFaceConfidence: nil)
            ? .success(name)
            : .failure(name, "Nil confidence must NOT auto-approve")
    }

    private static func test_autoApprove_exactThreshold() -> TestResult {
        let name = #function
        // Exactly at threshold (0.85) must pass.
        return TimecardCalculator.shouldAutoApprove(clockInFaceConfidence: 0.85)
            ? .success(name)
            : .failure(name, "Confidence exactly at threshold (0.85) should auto-approve")
    }
}
