import Foundation

func parseDate(_ raw: String) -> Date? {
    // Normalize space separator to "T" for ISO8601 parsing compatibility
    var cleaned = raw.replacingOccurrences(of: " ", with: "T")
    
    // Clean short timezone offset at the end (e.g., +00 or -07) to +00:00 or -07:00
    let pattern = #"[+-]\d{2}$"#
    if let regex = try? NSRegularExpression(pattern: pattern),
       let _ = regex.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)) {
        cleaned += ":00"
    }
    
    // 1. withInternetDateTime + fractional seconds  →  "2026-06-12T17:00:00.123+07:00"
    let f1 = ISO8601DateFormatter()
    f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = f1.date(from: cleaned) { return d }

    // 2. withInternetDateTime (no fractional)       →  "2026-06-12T17:00:00+07:00"
    let f2 = ISO8601DateFormatter()
    f2.formatOptions = [.withInternetDateTime]
    if let d = f2.date(from: cleaned) { return d }

    // 3. Strip fractional seconds manually then retry
    //    "2026-06-12T17:00:00.123456+07:00" → "2026-06-12T17:00:00+07:00"
    var cleanedWithoutFractional = cleaned
    if let dotIdx = cleanedWithoutFractional.firstIndex(of: ".") {
        if let tzIdx = cleanedWithoutFractional[dotIdx...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" }) {
            cleanedWithoutFractional = String(cleanedWithoutFractional[..<dotIdx]) + String(cleanedWithoutFractional[tzIdx...])
        }
    }
    if let d = f2.date(from: cleanedWithoutFractional) { return d }

    // 4. DateFormatter fallback for "2026-06-12 17:00:00+00" (PostgreSQL default)
    let f3 = DateFormatter()
    f3.dateFormat = "yyyy-MM-dd HH:mm:ssZ"
    f3.locale = Locale(identifier: "en_US_POSIX")
    if let d = f3.date(from: raw) { return d }

    // 5. Without timezone  →  "2026-06-12T17:00:00" (assume UTC)
    let f4 = DateFormatter()
    f4.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    f4.locale = Locale(identifier: "en_US_POSIX")
    f4.timeZone = TimeZone(identifier: "UTC")
    if let d = f4.date(from: raw) { return d }

    return nil
}

func getDisplayText(startedAt: String, currentTimestamp: Double) -> String {
    guard let startDate = parseDate(startedAt) else {
        return "FAILED_TO_PARSE"
    }
    let currentDate = Date(timeIntervalSince1970: currentTimestamp)
    let minutes = Int(currentDate.timeIntervalSince(startDate) / 60)

    if minutes < 1 {
        return "< 1 min"
    } else if minutes < 60 {
        return "\(minutes) min"
    } else {
        let hours = minutes / 60
        let mins  = minutes % 60
        return mins == 0 ? "\(hours)h" : "\(hours)h \(mins)m"
    }
}

// Current time: 2026-06-13T13:10:12+07:00 (which is 1781244612 in Unix timestamp)
// Let's verify:
let formatter = ISO8601DateFormatter()
let testCurrentDate = formatter.date(from: "2026-06-13T13:10:12+07:00")!
let currentTimestamp = testCurrentDate.timeIntervalSince1970

let startedAt = "2026-06-12 17:22:57.192928+00"
let result = getDisplayText(startedAt: startedAt, currentTimestamp: currentTimestamp)
print("Result for '\(startedAt)': '\(result)'")
