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
    
    var soundFile: String? {
        switch self {
        case .order: return "notification_order"      // Urgent beep
        case .urgent: return "notification_urgent"    // Multiple beeps
        case .request: return "notification_request"  // Gentle ding
        case .tableStatus: return nil
        case .system: return nil
        }
    }
    
    var shouldVibrate: Bool {
        switch self {
        case .order, .urgent: return true
        default: return false
        }
    }
    
    var vibrationPattern: [NSNumber] {
        switch self {
        case .order: return [0, 200, 100, 200]        // Short-long pattern
        case .urgent: return [0, 150, 100, 150, 100]  // Urgent pattern
        default: return [0, 100]                       // Single tap
        }
    }
}

// MARK: - Enhanced Notification Manager (Observable)
@Observable
final class EnhancedNotificationManager {
    static let shared = EnhancedNotificationManager()
    
    // Current alert dialog item (top priority)
    var alertItem: EnhancedNotificationItem?
    
    // In-app notification (banner at top)
    var bannerItem: EnhancedNotificationItem?
    
    // Badge count (for app icon)
    @ObservationIgnored
    var badgeCount: Int = 0 {
        didSet {
            DispatchQueue.main.async {
                UIApplication.shared.applicationIconBadgeNumber = self.badgeCount
            }
        }
    }
    
    // Recent notifications history
    @ObservationIgnored
    var recentNotifications: [EnhancedNotificationItem] = []
    
    private let audioPlayer = NotificationAudioPlayer()
    private let hapticGenerator = UINotificationFeedbackGenerator()
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Show alert dialog (modal interrupt) - for high priority items
    func showAlert(title: String, body: String, type: NotificationType = .system, action: (() -> Void)? = nil) {
        let item = EnhancedNotificationItem(title: title, body: body, type: type, action: action)
        
        Task { @MainActor in
            // Play sound & vibrate immediately
            self.playNotificationSound(type: type)
            self.triggerHaptic(type: type)
            
            // Show alert dialog
            self.alertItem = item
            self.addToHistory(item)
            
            // Auto-dismiss after 6 seconds if no action taken
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            if self.alertItem?.id == item.id {
                self.alertItem = nil
            }
        }
    }
    
    /// Show banner notification (non-intrusive) - for lower priority items
    func showBanner(title: String, body: String, type: NotificationType = .system) {
        let item = EnhancedNotificationItem(title: title, body: body, type: type)
        
        Task { @MainActor in
            // Play sound & vibrate
            self.playNotificationSound(type: type)
            if type.shouldVibrate {
                self.triggerHaptic(type: type)
            }
            
            // Show banner
            self.bannerItem = item
            self.addToHistory(item)
            
            // Auto-dismiss after 4 seconds
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if self.bannerItem?.id == item.id {
                self.bannerItem = nil
            }
        }
    }
    
    /// Update badge count
    func updateBadge(_ count: Int) {
        self.badgeCount = count
    }
    
    /// Clear all notifications
    func clearAll() {
        self.alertItem = nil
        self.bannerItem = nil
        self.badgeCount = 0
        self.recentNotifications.removeAll()
        UIApplication.shared.applicationIconBadgeNumber = 0
    }
    
    // MARK: - Private Methods
    
    private func playNotificationSound(type: NotificationType) {
        if let soundFile = type.soundFile {
            audioPlayer.play(soundFile: soundFile)
        }
    }
    
    private func triggerHaptic(type: NotificationType) {
        guard type.shouldVibrate else { return }
        
        switch type {
        case .order:
            // Heavy impact for orders
            let impact = UIImpactFeedbackGenerator(style: .heavy)
            impact.impactOccurred()
            
            // Follow up with notification feedback
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.hapticGenerator.notificationOccurred(.success)
            }
            
        case .urgent:
            // Multiple light impacts for urgent
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
    
    private func addToHistory(_ item: EnhancedNotificationItem) {
        recentNotifications.insert(item, at: 0)
        // Keep only last 50 notifications
        if recentNotifications.count > 50 {
            recentNotifications.removeLast()
        }
    }
}

// MARK: - Audio Player Helper
fileprivate class NotificationAudioPlayer {
    private var audioPlayer: AVAudioPlayer?
    
    func play(soundFile: String) {
        guard let url = Bundle.main.url(forResource: soundFile, withExtension: "wav") ??
              Bundle.main.url(forResource: soundFile, withExtension: "mp3") else {
            // Fallback to system sound if custom file not found
            playSystemSound()
            return
        }
        
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, options: [.duckOthers, .defaultToSpeaker])
            try audioSession.setActive(true)
            
            self.audioPlayer = try AVAudioPlayer(contentsOf: url)
            self.audioPlayer?.play()
        } catch {
            print("Error playing sound: \(error)")
            playSystemSound()
        }
    }
    
    private func playSystemSound() {
        // Use iOS system sound as fallback
        AudioServicesPlaySystemSoundWithCompletion(1016) { }
    }
}

// MARK: - UI Views

struct EnhancedAlertDialogView: View {
    let item: EnhancedNotificationItem
    let onDismiss: () -> Void
    let onAction: (() -> Void)?
    
    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }
            
            // Alert Card
            VStack(spacing: 16) {
                // Header
                HStack(spacing: 12) {
                    Image(systemName: item.type.icon)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(item.type.color)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text(item.body)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    
                    Spacer()
                }
                .padding(.bottom, 4)
                
                // Buttons
                HStack(spacing: 12) {
                    Button(action: onDismiss) {
                        Text("Dismiss")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.gray.opacity(0.2))
                            .foregroundColor(.primary)
                            .cornerRadius(8)
                    }
                    
                    if let onAction = onAction {
                        Button(action: onAction) {
                            Text("View")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(item.type.color)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                    }
                }
            }
            .padding(16)
            .background(Color(uiColor: .systemBackground))
            .cornerRadius(12)
            .shadow(radius: 12)
            .padding(20)
            .transition(.scale.combined(with: .opacity))
        }
    }
}

struct EnhancedBannerNotificationView: View {
    let item: EnhancedNotificationItem
    let onDismiss: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.type.icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text(item.body)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(2)
            }
            
            Spacer(minLength: 8)
            
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    item.type.color,
                    item.type.color.opacity(0.8)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(10)
        .shadow(color: item.type.color.opacity(0.5), radius: 8, x: 0, y: 4)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

struct EnhancedNotificationContainer: View {
    @State private var manager = EnhancedNotificationManager.shared
    
    var body: some View {
        ZStack(alignment: .top) {
            // Alert Dialog (highest layer)
            if let alertItem = manager.alertItem {
                EnhancedAlertDialogView(
                    item: alertItem,
                    onDismiss: {
                        withAnimation(.easeOut(duration: 0.25)) {
                            manager.alertItem = nil
                        }
                    },
                    onAction: alertItem.action
                )
            }
            
            // Banner Notification (below alert)
            if let bannerItem = manager.bannerItem, manager.alertItem == nil {
                EnhancedBannerNotificationView(
                    item: bannerItem,
                    onDismiss: {
                        withAnimation(.easeOut(duration: 0.25)) {
                            manager.bannerItem = nil
                        }
                    }
                )
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: manager.alertItem?.id)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: manager.bannerItem?.id)
    }
}
