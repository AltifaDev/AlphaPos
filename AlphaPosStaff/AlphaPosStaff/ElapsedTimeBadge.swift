import SwiftUI

/// Small badge แสดงเวลาที่ผ่านไปตั้งแต่เปิดโต๊ะ
/// v2: ใช้ TimelineView(.periodic) แทน Timer.scheduledTimer
/// — จาก N timers (1 ต่อโต๊ะ) เหลือ 1 SwiftUI scheduler ต่อ screen
/// — ลด CPU/RunLoop load เมื่อมีหลายโต๊ะที่ occupied พร้อมกัน
struct ElapsedTimeBadge: View {
    let startedAt: String?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            let text = Self.computeDisplayText(from: startedAt)
            if !text.isEmpty {
                Text(text)
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundColor(.textSecondary)
                    .padding(.vertical, 1)
                    .padding(.horizontal, 4)
                    .background(Color.gray.opacity(0.12))
                    .cornerRadius(3)
            }
        }
    }

    // ── Shared formatting logic ───────────────────────────────────────────
    static func computeDisplayText(from startedAt: String?) -> String {
        guard let raw = startedAt, !raw.isEmpty else { return "" }
        guard let startDate = parseDate(raw) else { return "" }

        let minutes = Int(Date().timeIntervalSince(startDate) / 60)

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

    // ── รองรับทุก format ที่ Supabase ส่งมา ──────────────────────────────
    static func parseDate(_ raw: String) -> Date? {
        var cleaned = raw.replacingOccurrences(of: " ", with: "T")

        let pattern = #"[+-]\d{2}$"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let _ = regex.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)) {
            cleaned += ":00"
        }

        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: cleaned) { return d }

        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        if let d = f2.date(from: cleaned) { return d }

        var cleanedWithoutFractional = cleaned
        if let dotIdx = cleanedWithoutFractional.firstIndex(of: ".") {
            if let tzIdx = cleanedWithoutFractional[dotIdx...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" }) {
                cleanedWithoutFractional = String(cleanedWithoutFractional[..<dotIdx]) + String(cleanedWithoutFractional[tzIdx...])
            }
        }
        if let d = f2.date(from: cleanedWithoutFractional) { return d }

        let f3 = DateFormatter()
        f3.dateFormat = "yyyy-MM-dd HH:mm:ssZ"
        f3.locale = Locale(identifier: "en_US_POSIX")
        if let d = f3.date(from: raw) { return d }

        let f4 = DateFormatter()
        f4.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        f4.locale = Locale(identifier: "en_US_POSIX")
        f4.timeZone = TimeZone(identifier: "UTC")
        if let d = f4.date(from: raw) { return d }

        return nil
    }
}
