import Foundation
import SwiftUI
import AVFoundation
import UIKit
import Observation

// MARK: - Enhanced Notification Item (with Action Support)
struct EnhancedNotificationItem: Identifiable {
    let id = UUID()
    let title: String
    let body: String
    let type: NotificationType
    let action: (() -> Void)?
    let timestamp: Date = Date()
    
    init(title: String, body: String, type: NotificationType = .system, action: (() -> Void)? = nil) {
        self.title = title
        self.body = body
        self.type = type
        self.action = action
    }
}

enum NotificationType {
    case order           // 🍲 New order (highest priority)
    case urgent          // ⚠️ Urgent/blocking issue
    case request         // 🔔 Customer request
    case tableStatus     // 🪑 Table status change
    case system          // ℹ️ General system info
    
    var icon: String {
        switch self {
        case .order: return "shippingbox.fill"
        case .urgent: return "exclamationmark.triangle.fill"
        case .request: return "bell.badge.fill"
        case .tableStatus: return "table.furniture"
        case .system: return "info.circle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .order: return Color(red: 0.85, green: 0.2, blue: 0.2)    // Red
        case .urgent: return Color(red: 1.0, green: 0.6, blue: 0)       // Orange
        case .request: return Color(red: 0.2, green: 0.5, blue: 0.9)    // Blue
        case .tableStatus: return Color(red: 0.4, green: 0.7, blue: 0.3) // Green
        case .system: return Color(red: 0.5, green: 0.5, blue: 0.5)     // Gray
        }
    }
    
    /// System sound IDs that are guaranteed to play on all iOS devices
    var systemSoundID: SystemSoundID {
        switch self {
        case .order: return 1315    // Anticipate — attention-grabbing chime
        case .urgent: return 1304   // Alarm — urgent alert
        case .request: return 1016  // Tweet — gentle notification
        case .tableStatus: return 1057 // Tink — subtle status change
        case .system: return 1007   // Tink — minimal system info
        }
    }
    
    var shouldVibrate: Bool {
        switch self {
        case .order, .urgent, .request: return true
        default: return false
        }
    }
}

// MARK: - Enhanced Notification Manager (Observable, with FIFO Queue)
@Observable
final class EnhancedNotificationManager {
    static let shared = EnhancedNotificationManager()
    
    // Currently visible banner (driven by the queue)
    var currentBanner: EnhancedNotificationItem?
    
    // Number of pending items in queue (for badge display on banner)
    var queueCount: Int = 0
    
    // FIFO queue of pending notifications
    @ObservationIgnored
    private var queue: [EnhancedNotificationItem] = []
    
    @ObservationIgnored
    private var isProcessingQueue = false
    
    @ObservationIgnored
    private var currentDismissTask: Task<Void, Never>?
    
    private let hapticGenerator = UINotificationFeedbackGenerator()
    
    private init() {}
    
    // MARK: - Public: Enqueue a notification (called by NotificationManager router)
    
    /// Add a notification to the FIFO queue. If nothing is currently showing,
    /// it will be displayed immediately. Otherwise it waits in line.
    func enqueue(title: String, body: String, type: NotificationType, action: (() -> Void)? = nil) {
        let item = EnhancedNotificationItem(title: title, body: body, type: type, action: action)
        
        Task { @MainActor in
            self.queue.append(item)
            self.queueCount = self.queue.count
            
            #if DEBUG
            print("EnhancedNotificationManager [ENQUEUE]: '\(title)' — queue size: \(self.queue.count)")
            #endif
            
            if !self.isProcessingQueue {
                self.processNextInQueue()
            }
        }
    }
    
    /// Dismiss the current banner immediately and show the next one
    func dismissCurrent() {
        Task { @MainActor in
            self.currentDismissTask?.cancel()
            self.currentBanner = nil
            // Small delay before showing next
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s gap
            self.processNextInQueue()
        }
    }
    
    /// Clear everything
    func clearAll() {
        currentDismissTask?.cancel()
        currentBanner = nil
        queue.removeAll()
        queueCount = 0
        isProcessingQueue = false
        UIApplication.shared.applicationIconBadgeNumber = 0
    }
    
    // MARK: - Private Queue Processing
    
    @MainActor
    private func processNextInQueue() {
        guard !queue.isEmpty else {
            isProcessingQueue = false
            queueCount = 0
            return
        }
        
        isProcessingQueue = true
        let item = queue.removeFirst()
        queueCount = queue.count
        
        // Play sound & haptic
        playSystemSound(type: item.type)
        triggerHaptic(type: item.type)
        
        // Show the banner
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            self.currentBanner = item
        }
        
        // Schedule auto-dismiss
        let displayDuration: UInt64 = item.type == .order || item.type == .urgent
            ? 5_000_000_000    // 5s for important items
            : 3_500_000_000    // 3.5s for info/status items
        
        currentDismissTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                try await Task.sleep(nanoseconds: displayDuration)
            } catch {
                return // Task was cancelled — don't auto-dismiss
            }
            
            // Auto-dismiss and show next
            withAnimation(.easeOut(duration: 0.25)) {
                self.currentBanner = nil
            }
            
            // Delay before next item
            try? await Task.sleep(nanoseconds: 400_000_000) // 0.4s gap
            self.processNextInQueue()
        }
    }
    
    // MARK: - Sound & Haptics
    
    private func playSystemSound(type: NotificationType) {
        AudioServicesPlaySystemSoundWithCompletion(type.systemSoundID) { }
    }
    
    private func triggerHaptic(type: NotificationType) {
        guard type.shouldVibrate else { return }
        
        switch type {
        case .order:
            let impact = UIImpactFeedbackGenerator(style: .heavy)
            impact.impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.hapticGenerator.notificationOccurred(.success)
            }
        case .urgent:
            for i in 0..<3 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.15) {
                    let impact = UIImpactFeedbackGenerator(style: .light)
                    impact.impactOccurred()
                }
            }
        default:
            hapticGenerator.notificationOccurred(.warning)
        }
    }
}

// MARK: - UI Views

struct EnhancedBannerNotificationView: View {
    let item: EnhancedNotificationItem
    let pendingCount: Int
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Type icon
                ZStack {
                    Circle()
                        .fill(item.type.color.opacity(0.2))
                        .frame(width: 36, height: 36)
                    Image(systemName: item.type.icon)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(item.type.color)
                }
                
                // Text content
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(item.title)
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        if pendingCount > 0 {
                            Text("+\(pendingCount)")
                                .font(.caption2)
                                .fontWeight(.heavy)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.red)
                                .clipShape(Capsule())
                        }
                    }
                    
                    Text(item.body)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                Spacer(minLength: 8)
                
                // Dismiss button
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary.opacity(0.6))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .shadow(color: item.type.color.opacity(0.25), radius: 12, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(item.type.color.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .transition(.move(edge: .top).combined(with: .opacity))
        .gesture(
            DragGesture(minimumDistance: 10)
                .onEnded { value in
                    if value.translation.height < -20 {
                        onDismiss() // Swipe up to dismiss
                    }
                }
        )
    }
}

struct EnhancedNotificationContainer: View {
    @State private var manager = EnhancedNotificationManager.shared
    
    var body: some View {
        ZStack(alignment: .top) {
            if let bannerItem = manager.currentBanner {
                EnhancedBannerNotificationView(
                    item: bannerItem,
                    pendingCount: manager.queueCount,
                    onDismiss: {
                        manager.dismissCurrent()
                    }
                )
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: manager.currentBanner?.id)
    }
}
