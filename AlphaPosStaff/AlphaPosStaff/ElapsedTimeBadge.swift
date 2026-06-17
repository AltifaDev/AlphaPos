import SwiftUI

/// Small badge แสดงเวลาที่ผ่านไปตั้งแต่เปิดโต๊ะ — auto-updates ทุก 30 วินาที
struct ElapsedTimeBadge: View {
    let startedAt: String?

    @State private var displayText: String
    @State private var timer: Timer?

    // ── Eagerly compute initial display text so the view is non-empty on first render ──
    init(startedAt: String?) {
        self.startedAt = startedAt
        self._displayText = State(initialValue: Self.computeDisplayText(from: startedAt))
    }

    var body: some View {
        Group {
            if !displayText.isEmpty {
                Text(displayText)
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundColor(.textSecondary)
                    .padding(.vertical, 1)
                    .padding(.horizontal, 4)
                    .background(Color.gray.opacity(0.12))
                    .cornerRadius(3)
            }
        }
        .onAppear {
            refreshText()
            timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
                refreshText()
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
        // อัปเดตทันทีเมื่อ sessionStartedAt เปลี่ยน (เช่น โต๊ะถูก occupy ใหม่)
        .onChange(of: startedAt) { _, _ in
            refreshText()
        }
    }

    private func refreshText() {
        displayText = Self.computeDisplayText(from: startedAt)
    }

    // ── Shared formatting logic used by both init and refresh ──────────
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

    // ── รองรับทุก format ที่ Supabase ส่งมา ──────────────────────────
    static func parseDate(_ raw: String) -> Date? {
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
}
