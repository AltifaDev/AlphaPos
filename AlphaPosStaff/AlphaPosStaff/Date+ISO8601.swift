import Foundation

/// Robust parsing of timestamps from PostgREST / Postgres.
/// Default `ISO8601DateFormatter` fails on fractional seconds (`…00.123456+00:00`),
/// which wrongly made Staff notifications fall back to `Date()` (= "just now").
enum ISO8601DateParser {
    static func date(from raw: String?) -> Date? {
        guard var cleaned = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !cleaned.isEmpty else { return nil }

        cleaned = cleaned.replacingOccurrences(of: " ", with: "T")

        // Postgres often returns "+00" without minutes — normalize to "+00:00".
        if let regex = try? NSRegularExpression(pattern: #"([+-]\d{2})$"#),
           let match = regex.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)),
           let range = Range(match.range(at: 1), in: cleaned) {
            cleaned.replaceSubrange(range, with: cleaned[range] + ":00")
        }

        // Normalize "+0000" / "+0700" → "+00:00" / "+07:00"
        if cleaned.count >= 5 {
            let tail = cleaned.suffix(5)
            if (tail.first == "+" || tail.first == "-"),
               cleaned.dropLast(5).last != ":",
               tail.dropFirst().allSatisfy(\.isNumber) {
                let sign = tail.first!
                let hh = tail.dropFirst().prefix(2)
                let mm = tail.suffix(2)
                cleaned = String(cleaned.dropLast(5)) + "\(sign)\(hh):\(mm)"
            }
        }

        // Apple ISO8601DateFormatter often rejects >3 fractional digits (.123456).
        if let dot = cleaned.firstIndex(of: "."),
           let tz = cleaned[dot...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" }) {
            let frac = cleaned[cleaned.index(after: dot)..<tz]
            if frac.count > 3 {
                cleaned = String(cleaned[...dot]) + frac.prefix(3) + String(cleaned[tz...])
            }
        }

        if cleaned.hasSuffix("Z") == false,
           cleaned.contains("+") == false,
           cleaned.contains("-") == false || cleaned.lastIndex(of: "T") == nil {
            // Bare local/UTC timestamp without zone — treat as UTC.
            if cleaned.count == 19 { cleaned += "Z" }
        }

        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: cleaned) { return date }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: cleaned) { return date }

        // Strip fractional seconds then retry.
        var withoutFraction = cleaned
        if let dot = withoutFraction.firstIndex(of: ".") {
            let afterDot = withoutFraction[dot...]
            if let tz = afterDot.firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" }) {
                withoutFraction = String(withoutFraction[..<dot]) + String(withoutFraction[tz...])
            } else {
                withoutFraction = String(withoutFraction[..<dot]) + "Z"
            }
        }
        if let date = plain.date(from: withoutFraction) { return date }

        let formats = [
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX",
            "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
            "yyyy-MM-dd'T'HH:mm:ssXXXXX",
            "yyyy-MM-dd HH:mm:ssXXXXX",
            "yyyy-MM-dd'T'HH:mm:ss"
        ]
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        for format in formats {
            df.dateFormat = format
            df.timeZone = format.contains("X") ? nil : TimeZone(secondsFromGMT: 0)
            if let date = df.date(from: raw ?? cleaned) ?? df.date(from: cleaned) {
                return date
            }
        }
        return nil
    }

    /// Absolute local clock. Includes the calendar date when not today,
    /// so overnight web orders are not mistaken for "just now" (e.g. 00:17 vs 22:56).
    static func absoluteTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = .current
        if Calendar.current.isDateInToday(date) {
            formatter.dateStyle = .none
            formatter.timeStyle = .short
        } else {
            formatter.dateStyle = .short
            formatter.timeStyle = .short
        }
        return formatter.string(from: date)
    }

    /// Relative age for shared notification UI (matches iPad Notification Center).
    static func relativeAge(_ date: Date, language: String = "en", now: Date = Date()) -> String {
        let interval = now.timeIntervalSince(date)
        let th = language.hasPrefix("th")
        if interval < 60 { return th ? "เมื่อสักครู่" : "just now" }
        if interval < 3600 {
            let m = Int(interval / 60)
            return th ? "\(m) นาทีที่แล้ว" : "\(m) min ago"
        }
        if interval < 86400 {
            let h = Int(interval / 3600)
            return th ? "\(h) ชม.ที่แล้ว" : "\(h) hr ago"
        }
        let days = Int(interval / 86400)
        if th { return days == 1 ? "1 วันที่แล้ว" : "\(days) วันที่แล้ว" }
        return days == 1 ? "1 day ago" : "\(days) days ago"
    }

    /// Combined label: relative age + exact local clock time of the original event.
    static func notificationTimestampLabel(
        _ date: Date,
        language: String = "en",
        now: Date = Date()
    ) -> String {
        "\(relativeAge(date, language: language, now: now)) · \(absoluteTime(date))"
    }
}

/// Shared lifecycle rules for the Staff app's operational notification queue.
/// Orders and customer requests are shift work, so they must not cross the
/// device's local end-of-day boundary. Source records remain on the server for
/// reporting and audit purposes.
enum StaffNotificationPolicy {
    static let allowedClockSkew: TimeInterval = 5 * 60

    static func isCurrentBusinessDay(
        _ date: Date?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard let date else { return false }
        return date >= calendar.startOfDay(for: now)
            && date <= now.addingTimeInterval(allowedClockSkew)
    }

    static func isCurrentBusinessDay(
        timestamp: String?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        isCurrentBusinessDay(
            ISO8601DateParser.date(from: timestamp),
            now: now,
            calendar: calendar
        )
    }

    static func currentBusinessDayStart(
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        ISO8601DateFormatter().string(from: calendar.startOfDay(for: now))
    }
}
