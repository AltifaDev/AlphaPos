import SwiftUI

/// Small badge แสดงเวลาที่ผ่านไปตั้งแต่เปิดโต๊ะ — auto-updates ทุก 30 วินาที
struct ElapsedTimeBadge: View {
    let startedAt: String?
    
    @State private var displayText: String = ""
    @State private var timer: Timer?
    
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
    }
    
    private func refreshText() {
        guard let startedAtStr = startedAt else {
            displayText = ""
            return
        }
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = formatter.date(from: startedAtStr)
        
        if date == nil {
            formatter.formatOptions = [.withInternetDateTime]
            date = formatter.date(from: startedAtStr)
        }
        
        guard let startDate = date else {
            displayText = ""
            return
        }
        
        let minutes = Int(Date().timeIntervalSince(startDate) / 60)
        
        if minutes < 1 {
            displayText = "< 1 min"
        } else if minutes < 60 {
            displayText = "\(minutes) min"
        } else {
            let hours = minutes / 60
            let mins  = minutes % 60
            displayText = mins == 0 ? "\(hours)h" : "\(hours)h \(mins)m"
        }
    }
}
