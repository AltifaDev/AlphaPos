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
        ISO8601DateParser.date(from: raw)
    }
}
