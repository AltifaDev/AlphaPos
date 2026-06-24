import Foundation
import Combine
import SwiftUI
import AVFoundation
import UserNotifications
import UIKit

// MARK: - In-App Notification Model

/// ประเภทการแจ้งเตือนภายในแอป (ไม่ใช้ Native Push)
enum InAppNotificationType {
    case newOrder           // ออเดอร์ใหม่จากลูกค้า
    case serviceRequest     // ลูกค้าเรียก Staff
    case cookingAlert       // รายการอาหารค้างคิวนานเกิน
    case deliveryAlert      // อาหารพร้อมแต่ยังไม่เสิร์ฟ
    case staleShift         // กะงานค้างเปิดนานเกินไป

    var icon: String {
        switch self {
        case .newOrder:       return "cart.fill.badge.plus"
        case .serviceRequest: return "bell.fill"
        case .cookingAlert:   return "flame.fill"
        case .deliveryAlert:  return "tray.full.fill"
        case .staleShift:     return "clock.badge.exclamationmark.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .newOrder:       return .appTeal
        case .serviceRequest: return .appAccent
        case .cookingAlert:   return .orange
        case .deliveryAlert:  return .red
        case .staleShift:     return .yellow
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
    let createdAt: Date = Date()

    /// แสดงผลอยู่นานแค่ไหน (วินาที)
    var displayDuration: TimeInterval {
        switch type {
        case .staleShift:     return 8
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

    private init() {}

    // MARK: - Post Notification

    /// ส่งการแจ้งเตือนใหม่ — เรียกจาก SyncEngine (ไม่ต้องเป็น @MainActor ที่ call site)
    func post(_ notification: InAppNotification) {
        activeNotifications.insert(notification, at: 0)
        latestNotification = notification

        // ส่ง Local Notification เมื่อแอปอยู่ background / ไม่ active
        // ไม่ต้องการ Push Notifications capability — เป็นแค่ local notification
        postLocalNotificationIfNeeded(notification)

        // เล่นเสียงถ้ามี (ใช้ AudioToolbox — ไม่ต้องการ capability)
        if let soundID = notification.type.soundID {
            AudioServicesPlaySystemSound(soundID)
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

    // MARK: - Local Notification (Background Fallback)

    /// ส่ง UNUserNotificationCenter local notification เมื่อแอปไม่ได้อยู่ foreground
    /// ใช้สำหรับ order ใหม่และ service request เท่านั้น — ไม่ spam ประเภทอื่น
    private func postLocalNotificationIfNeeded(_ item: InAppNotification) {
        // เฉพาะ newOrder และ serviceRequest เท่านั้น
        guard item.type == .newOrder || item.type == .serviceRequest else { return }

        let appState = UIApplication.shared.applicationState
        guard appState != .active else { return } // foreground: banner ทำงานอยู่แล้ว

        let content = UNMutableNotificationContent()
        content.title = item.title
        content.body  = item.body
        content.sound = item.type == .newOrder
            ? UNNotificationSound(named: UNNotificationSoundName("order_chime.caf"))
            : UNNotificationSound.default

        // Badge count = จำนวน active notifications ปัจจุบัน + 1
        content.badge = NSNumber(value: activeNotifications.count)

        // userInfo สำหรับ deep-link เมื่อ user tap notification
        var info: [String: String] = ["type": item.type == .newOrder ? "order" : "service_request"]
        if let table = item.tableNumber { info["table_number"] = table }
        content.userInfo = info

        let request = UNNotificationRequest(
            identifier: item.id.uuidString,
            content: content,
            trigger: nil // แสดงทันที
        )

        UNUserNotificationCenter.current().add(request) { error in
            #if DEBUG
            if let error = error {
                print("InAppNotificationManager: Local notification failed — \(error.localizedDescription)")
            }
            #endif
        }
    }

    /// ลบทุกการแจ้งเตือน
    func clearAll() {
        activeNotifications.removeAll()
        latestNotification = nil
    }

    // MARK: - Convenience Helpers (เรียกจาก SyncEngine)

    func postNewOrder(orderNumber: String, tableNumber: String) {
        post(InAppNotification(
            type: .newOrder,
            title: "ออเดอร์ใหม่!",
            body: "โต๊ะ \(tableNumber) สั่งออเดอร์ #\(orderNumber.suffix(4))",
            tableNumber: tableNumber
        ))
    }

    func postServiceRequest(tableNumber: String, requestType: String) {
        let displayMap = [
            "Bill (Cash)": "ชำระเงิน (เงินสด)",
            "Bill (Card)": "ชำระเงิน (บัตร)",
            "Bill (QR)":   "ชำระเงิน (QR)",
            "Ice/Water":   "ขอน้ำแข็ง/น้ำ",
            "Extra Utensils": "ขออุปกรณ์เพิ่ม",
            "General Help": "เรียกพนักงาน",
        ]
        let display = displayMap[requestType] ?? requestType
        post(InAppNotification(
            type: .serviceRequest,
            title: "🛎️ เรียกพนักงาน: โต๊ะ \(tableNumber)",
            body: "โต๊ะ \(tableNumber) ต้องการ: \(display)",
            tableNumber: tableNumber
        ))
    }

    func postCookingAlert(tableNumber: String, orderNumber: String, isReady: Bool) {
        if isReady {
            post(InAppNotification(
                type: .deliveryAlert,
                title: "อาหารพร้อมเสิร์ฟ!",
                body: "โต๊ะ \(tableNumber) (#\(orderNumber)) พร้อมแต่ยังไม่เสิร์ฟ > 10 นาที",
                tableNumber: tableNumber
            ))
        } else {
            post(InAppNotification(
                type: .cookingAlert,
                title: "แจ้งเตือน: ครัวล่าช้า",
                body: "โต๊ะ \(tableNumber) (#\(orderNumber)) อยู่ในครัว > 10 นาที",
                tableNumber: tableNumber
            ))
        }
    }

    func postStaleShift(hoursOpen: Int) {
        post(InAppNotification(
            type: .staleShift,
            title: "กะงานค้างเปิด \(hoursOpen) ชม.",
            body: "กรุณาปิดกะงานก่อนสิ้นวัน",
            tableNumber: nil
        ))
    }
}

// MARK: - InAppNotificationBanner (SwiftUI View)

/// Banner ที่แสดงด้านบนจอ — ใช้ใน MainDashboardView หรือ AppRootView
struct InAppNotificationBanner: View {
    @ObservedObject private var manager = InAppNotificationManager.shared
    @State private var isVisible = false

    /// Callback เมื่อแตะ banner — navigate ไปยังโต๊ะที่เกี่ยวข้อง
    var onTap: ((String?) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            if let notification = manager.latestNotification {
                bannerView(for: notification)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture {
                        onTap?(notification.tableNumber)
                        manager.clearAll()
                    }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: manager.latestNotification?.id)
    }

    private func bannerView(for notification: InAppNotification) -> some View {
        HStack(spacing: 12) {
            Image(systemName: notification.type.icon)
                .font(.title3)
                .foregroundColor(notification.type.accentColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(notification.title)
                    .font(.subheadline)
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
                    InAppNotificationManager.shared.activeNotifications.removeAll {
                        $0.id == notification.id
                    }
                    if InAppNotificationManager.shared.latestNotification?.id == notification.id {
                        InAppNotificationManager.shared.latestNotification =
                            InAppNotificationManager.shared.activeNotifications.first
                    }
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
    }
}
