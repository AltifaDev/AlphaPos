import SwiftUI

// MARK: - Elapsed Time View Component
struct ElapsedTimeView: View {
    let table: RestaurantTable
    @State private var elapsedTime: String = "0 min"
    @State private var timer: Timer?
    
    var body: some View {
        if table.status.lowercased() == "occupied" {
            Text(elapsedTime)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.textSecondary)
                .padding(.vertical, 2)
                .padding(.horizontal, 4)
                .background(Color.appSurfaceHigh.opacity(0.6))
                .cornerRadius(3)
                .onAppear { startTimer() }
                .onDisappear { stopTimer() }
        }
    }
    
    private func startTimer() {
        updateElapsedTime()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
            updateElapsedTime()
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func updateElapsedTime() {
        let minutes = table.elapsedMinutes
        
        if minutes < 1 {
            elapsedTime = "< 1 min"
        } else if minutes < 60 {
            elapsedTime = "\(minutes) min"
        } else {
            let hours = minutes / 60
            let mins = minutes % 60
            if mins == 0 {
                elapsedTime = "\(hours)h"
            } else {
                elapsedTime = "\(hours)h \(mins)m"
            }
        }
    }
}

// MARK: - iPad Table Card (with Elapsed Time underneath)
struct iPadTableCard: View {
    let table: RestaurantTable
    let isSelected: Bool
    let isInEditMode: Bool
    
    var statusColor: Color {
        switch table.status.lowercased() {
        case "vacant": return .appTeal
        case "occupied": return .appRose
        case "reserved": return .appAmber
        case "cleaning": return .appAccent
        default: return .textSecondary
        }
    }
    
    var body: some View {
        VStack(spacing: 4) {
            // Status indicator dot
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                    .animation(.spring(response: 0.35, dampingFraction: 0.7), value: table.status)

                Spacer()
                
                Text("⋄ \(table.capacity)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.textSecondary)
            }
            
            // Table number
            Text("T\(table.tableNumber)")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.textPrimary)
            
            // Status badge
            Text(table.status.prefix(3).uppercased())
                .font(.system(size: 9, weight: .heavy))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 3)
                .background(statusColor)
                .animation(.spring(response: 0.35, dampingFraction: 0.7), value: table.status)
                .cornerRadius(3)
            
            // ✨ NEW: Elapsed Time (iPad Only)
            if table.status.lowercased() == "occupied" {
                ElapsedTimeView(table: table)
                    .frame(maxWidth: .infinity)
            }
            
            if isInEditMode {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 9))
                    .foregroundColor(.appAccent)
            }
        }
        .padding(10)
        .background(isSelected ? Color.appSurfaceHigh : Color.appSurface)
        .cornerRadius(APRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: APRadius.md)
                .stroke(isSelected ? statusColor : Color.appBorderSubtle, lineWidth: isSelected ? 2 : 1)
        )
    }
}

// MARK: - iPhone Table Card (Compact - Only Elapsed Time underneath Occupied)
struct iPhoneTableCard: View {
    let table: RestaurantTable
    let isSelected: Bool
    let isInEditMode: Bool
    
    var statusColor: Color {
        switch table.status.lowercased() {
        case "vacant": return .appTeal
        case "occupied": return .appRose
        case "reserved": return .appAmber
        case "cleaning": return .appAccent
        default: return .textSecondary
        }
    }
    
    var body: some View {
        VStack(spacing: 3) {
            // Table number (large, prominent)
            Text("T\(table.tableNumber)")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.textPrimary)
            
            // Status badge (compact)
            Text(table.status.prefix(3).uppercased())
                .font(.system(size: 8, weight: .heavy))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)
                .background(statusColor)
                .animation(.spring(response: 0.35, dampingFraction: 0.7), value: table.status)
                .cornerRadius(2)
            
            // ✨ NEW: Elapsed Time (iPhone Only - when occupied)
            if table.status.lowercased() == "occupied" {
                ElapsedTimeView(table: table)
                    .frame(maxWidth: .infinity)
            }
            
            if isInEditMode {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 8))
                    .foregroundColor(.appAccent)
            }
        }
        .padding(8)
        .background(isSelected ? Color.appSurfaceHigh : Color.appSurface)
        .cornerRadius(APRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: APRadius.md)
                .stroke(isSelected ? statusColor : Color.appBorderSubtle, lineWidth: isSelected ? 2 : 1)
                .animation(.spring(response: 0.35, dampingFraction: 0.7), value: table.status)
        )
    }
}

// MARK: - Preview
#Preview("iPad Card - Occupied") {
    let table = RestaurantTable(
        tableNumber: "2",
        capacity: 4,
        status: "occupied",
        qrCodeIdentifier: "t2_hash"
    )
    table.sessions.append(
        TableSession(
            sessionToken: UUID().uuidString,
            startedAt: Date(timeIntervalSinceNow: -600), // 10 min ago
            isActive: true,
            table: table
        )
    )
    return iPadTableCard(table: table, isSelected: false, isInEditMode: false)
}

#Preview("iPhone Card - Occupied") {
    let table = RestaurantTable(
        tableNumber: "3",
        capacity: 2,
        status: "occupied",
        qrCodeIdentifier: "t3_hash"
    )
    table.sessions.append(
        TableSession(
            sessionToken: UUID().uuidString,
            startedAt: Date(timeIntervalSinceNow: -1800), // 30 min ago
            isActive: true,
            table: table
        )
    )
    return iPhoneTableCard(table: table, isSelected: false, isInEditMode: false)
}
