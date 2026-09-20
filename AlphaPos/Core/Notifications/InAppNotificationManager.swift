import Foundation
import Combine
import SwiftUI
import AVFoundation
import UIKit
import AudioToolbox

// MARK: - In-App Notification Model

/// ประเภทการแจ้งเตือนภายในแอป (ไม่ใช้ Native Push)
enum InAppNotificationType: Equatable {
    case newOrder           // ออเดอร์ใหม่จากลูกค้า
    case serviceRequest     // ลูกค้าเรียก Staff
    case cookingAlert       // รายการอาหารค้างคิวนานเกิน
    case deliveryAlert      // อาหารพร้อมแต่ยังไม่เสิร์ฟ
    case staleShift         // กะงานค้างเปิดนานเกินไป
    case printerAlert       // ข้อผิดพลาดจากเครื่องพิมพ์

    var icon: String {
        switch self {
        case .newOrder:       return "cart.fill.badge.plus"
        case .serviceRequest: return "bell.fill"
        case .cookingAlert:   return "flame.fill"
        case .deliveryAlert:  return "tray.full.fill"
        case .staleShift:     return "clock.badge.exclamationmark.fill"
        case .printerAlert:   return "exclamationmark.triangle.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .newOrder:       return .appTeal
        case .serviceRequest: return .appAccent
        case .cookingAlert:   return .orange
        case .deliveryAlert:  return .red
        case .staleShift:     return .yellow
        case .printerAlert:   return .red
        }
    }

    /// เสียงที่ใช้ (SystemSoundID — ไม่ต้องการ Push capability)
    var soundID: SystemSoundID? {
        switch self {
        case .newOrder:       return 1007  // เสียงรับข้อความ
        case .serviceRequest: return 1005  // เสียง bell
        case .cookingAlert:   return 1016  // เสียงเตือน
        case .deliveryAlert:  return 1016
        case .staleShift:     return nil   // ไม่มีเสียง
        case .printerAlert:   return 1008  // เสียงเตือนข้อผิดพลาด
        }
    }
}

// MARK: - In-App Notification Item

struct InAppNotification: Identifiable {
    let id = UUID()
    let type: InAppNotificationType
    let title: String
    let body: String
    let tableNumber: String?   // สำหรับ navigate ไปโต๊ะที่เกี่ยวข้อง
    let orderNumber: String?   // สำหรับ navigate ไปดูออเดอร์
    let dedupeKey: String?
    let createdAt: Date = Date()

    init(
        type: InAppNotificationType,
        title: String,
        body: String,
        tableNumber: String?,
        orderNumber: String? = nil,
        dedupeKey: String? = nil
    ) {
        self.type = type
        self.title = title
        self.body = body
        self.tableNumber = tableNumber
        self.orderNumber = orderNumber
        self.dedupeKey = dedupeKey
    }

    /// แสดงผลอยู่นานแค่ไหน (วินาที)
    var displayDuration: TimeInterval {
        switch type {
        case .newOrder:       return 6
        case .staleShift:     return 8
        case .printerAlert:   return 7
        case .cookingAlert,
             .deliveryAlert:  return 6
        default:              return 4
        }
    }
}

// MARK: - InAppNotificationManager

/// จัดการการแจ้งเตือนภายในแอป — ไม่ใช้ UNUserNotificationCenter
/// ทำงานเฉพาะเมื่อแอปเปิดอยู่ ไม่แจ้งเตือนเมื่อแอปปิด (ตรงกับความต้องการ)
@MainActor
final class InAppNotificationManager: ObservableObject {
    static let shared = InAppNotificationManager()

    /// รายการแจ้งเตือนที่กำลังแสดงอยู่ (Views observe ตัวนี้)
    @Published var activeNotifications: [InAppNotification] = []

    /// แจ้งเตือนล่าสุด — สำหรับ views ที่ต้องการแค่ตัวล่าสุด
    @Published var latestNotification: InAppNotification? = nil
    private var recentlyDelivered: [String: Date] = [:]
    private let speechSynthesizer = AVSpeechSynthesizer()

    private init() {}

    // MARK: - Post Notification

    /// ส่งการแจ้งเตือนใหม่ — เรียกจาก SyncEngine (ไม่ต้องเป็น @MainActor ที่ call site)
    func post(_ notification: InAppNotification) {
        if let key = notification.dedupeKey {
            let now = Date()
            if let last = recentlyDelivered[key],
               now.timeIntervalSince(last) < 10 {
                return
            }
            recentlyDelivered[key] = now
            recentlyDelivered = recentlyDelivered.filter {
                now.timeIntervalSince($0.value) < 600
            }
        }
        // Banner is a latest-event surface, not a replay queue. Durable/live
        // events remain in NotificationStore; superseded banners must not
        // reappear after a newer banner expires.
        activeNotifications = [notification]
        latestNotification = notification

        if UIApplication.shared.applicationState == .active,
           UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(
                notification: .announcement,
                argument: "\(notification.title). \(notification.body)"
            )
        }

        // เล่นเสียงถ้ามี (ใช้ AudioToolbox — ไม่ต้องการ capability)
        let soundEnabled = UserDefaults.standard.object(
            forKey: "enable_in_app_notification_sounds"
        ) as? Bool ?? true
        if soundEnabled, let soundID = notification.type.soundID {
            AudioServicesPlaySystemSound(soundID)
        }

        let speechEnabled = UserDefaults.standard.object(
            forKey: "enable_in_app_notification_speech"
        ) as? Bool ?? true
        if speechEnabled, notification.type == .newOrder {
            // Announce the location so staff can react without looking at the
            // screen. The table number is supplied by both QR/web customer
            // orders and staff-iPhone orders. Quick orders have no table, so
            // announce their queue number instead.
            let speechText: String
            if let tableNumber = notification.tableNumber,
               !tableNumber.isEmpty {
                speechText = "ออร์เดอร์ใหม่ โต๊ะ (tableNumber) เข้ามาค่ะ"
            } else {
                speechText = "ออร์เดอร์ใหม่เข้ามาค่ะ"
            }
            let utterance = AVSpeechUtterance(string: speechText)
            utterance.voice = AVSpeechSynthesisVoice(language: "th-TH")
            utterance.rate = 0.48
            speechSynthesizer.stopSpeaking(at: .immediate)
            speechSynthesizer.speak(utterance)
        }

        // ลบออกหลัง displayDuration วินาที
        let id = notification.id
        let duration = notification.displayDuration
        Task {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            await MainActor.run {
                self.activeNotifications.removeAll { $0.id == id }
                if self.latestNotification?.id == id {
                    self.latestNotification = self.activeNotifications.first
                }
            }
        }
    }

    /// ลบทุกการแจ้งเตือน
    func clearAll() {
        activeNotifications.removeAll()
        latestNotification = nil
        recentlyDelivered.removeAll()
    }

    /// Remove only the notification the user handled. Other queued banners
    /// remain available instead of being discarded as a side effect.
    func dismiss(_ id: UUID) {
        activeNotifications.removeAll { $0.id == id }
        if latestNotification?.id == id {
            latestNotification = activeNotifications.first
        }
    }

    // MARK: - Convenience Helpers (เรียกจาก SyncEngine)

    func postNewOrder(orderNumber: String, tableNumber: String, queueNumber: String? = nil, orderType: String? = nil) {
        let isQuick = tableNumber.uppercased() == "QUICK" || tableNumber.isEmpty
        let title: String
        let body: String
        if isQuick {
            let isThai = LocalizationManager.shared.currentLanguage == .thai
            let typeLabel: String
            switch orderType {
            case "delivery":
                typeLabel = isThai ? "เดลิเวอรี" : "Delivery"
            case "walk_in":
                typeLabel = isThai ? "ซื้อหน้าร้าน" : "Walk-in"
            default:
                typeLabel = isThai ? "สั่งกลับบ้าน" : "Takeaway"
            }
            title = "alert_new_order_title".t + " (\(typeLabel))"
            if let q = queueNumber, !q.isEmpty {
                body = (isThai ? "คิว #" : "Queue #") + "\(q) — #\(orderNumber)"
            } else {
                body = "#\(orderNumber)"
            }
        } else {
            title = "alert_new_order_title".t
            body = "\("table".t) \(tableNumber) \("notif_placed_order".t) #\(orderNumber.suffix(4))"
        }
        post(InAppNotification(
            type: .newOrder,
            title: title,
            body: body,
            tableNumber: isQuick ? nil : tableNumber,
            orderNumber: orderNumber,
            dedupeKey: "order:\(orderNumber)"
        ))
    }

    func postServiceRequest(tableNumber: String, requestType: String) {
        let displayMap = [
            "Bill (Cash)": "notif_request_bill_cash",
            "Bill (Card)": "notif_request_bill_card",
            "Bill (QR)":   "notif_request_bill_qr",
            "Ice/Water":   "notif_request_ice_water",
            "Extra Utensils": "notif_request_utensils",
            "General Help": "notif_request_general_help",
        ]
        let display = displayMap[requestType]?.t ?? requestType
        let locationLabel = OrderDisplayIdentity.label(forServiceReference: tableNumber)
        post(InAppNotification(
            type: .serviceRequest,
            title: "🛎️ \("alert_customer_call_title".t): \(locationLabel)",
            body: "\(locationLabel) \("notif_requests".t): \(display)",
            tableNumber: tableNumber.hasPrefix("Q-") || tableNumber.hasPrefix("ORDER-") ? nil : tableNumber,
            dedupeKey: "request:\(tableNumber):\(requestType)"
        ))
    }

    func postCookingAlert(tableNumber: String, orderNumber: String, isReady: Bool) {
        if isReady {
            post(InAppNotification(
                type: .deliveryAlert,
                title: "notif_food_ready_title".t,
                body: "\("table".t) \(tableNumber) (#\(orderNumber)) \("notif_ready_not_served".t) > 10 \("notif_minutes".t)",
                tableNumber: tableNumber,
                dedupeKey: "delivery:\(orderNumber)"
            ))
        } else {
            post(InAppNotification(
                type: .cookingAlert,
                title: "alert_order_delayed_title".t,
                body: "\("table".t) \(tableNumber) (#\(orderNumber)) \("notif_in_kitchen".t) > 10 \("notif_minutes".t)",
                tableNumber: tableNumber,
                dedupeKey: "cooking:\(orderNumber)"
            ))
        }
    }

    func postStaleShift(hoursOpen: Int) {
        post(InAppNotification(
            type: .staleShift,
            title: "\("notif_stale_shift_title".t) \(hoursOpen) \("notif_hours".t)",
            body: "notif_stale_shift_body".t,
            tableNumber: nil,
            dedupeKey: "stale-shift"
        ))
    }
}

// MARK: - InAppNotificationBanner (SwiftUI View)

/// Banner ที่แสดงด้านบนจอ — ใช้ใน MainDashboardView หรือ AppRootView
struct InAppNotificationBanner: View {
    @ObservedObject private var manager = InAppNotificationManager.shared
    @State private var isVisible = false

    /// Callback เมื่อแตะ banner — navigate ไปยังโต๊ะหรือออเดอร์ที่เกี่ยวข้อง (tableNumber, orderNumber)
    var onTap: ((String?, String?) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            if let notification = manager.latestNotification {
                bannerView(for: notification)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture {
                        onTap?(notification.tableNumber, notification.orderNumber)
                        manager.dismiss(notification.id)
                    }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: manager.latestNotification?.id)
    }

    private func bannerView(for notification: InAppNotification) -> some View {
        HStack(spacing: 12) {
            Image(systemName: notification.type.icon)
                .font(.title2)
                .foregroundColor(notification.type.accentColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(notification.title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.textPrimary)
                Text(notification.body)
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                    .lineLimit(2)
            }

            Spacer()

            Button {
                withAnimation {
                    InAppNotificationManager.shared.dismiss(notification.id)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            }
            .padding(.leading, 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.appSurface)
                .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(notification.type.accentColor.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(notification.title). \(notification.body)")
        .accessibilityHint("notif_banner_open_hint".t)
        .accessibilityAddTraits(.isButton)
    }
}
