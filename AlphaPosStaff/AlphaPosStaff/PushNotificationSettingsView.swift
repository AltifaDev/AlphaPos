// PushNotificationSettingsView.swift
// AlphaPosStaff — Push Notification Preferences UI
//
// Staff can individually toggle each push notification category.
// Includes a "Test Push" button to verify APNs is working end-to-end.

import SwiftUI
import UserNotifications

struct PushNotificationSettingsView: View {
    // ── State ──────────────────────────────────────────────────────────────────
    @AppStorage("app_language") private var appLanguage = "en"
    @State private var systemAuthStatus: UNAuthorizationStatus = .notDetermined
    @State private var prefs = NetworkService.PushNotificationPreferences.current
    @State private var isTesting = false
    @State private var testResult: String? = nil
    @State private var showTestResult = false
    @Environment(\.dismiss) private var dismiss

    // ── Body ───────────────────────────────────────────────────────────────────
    var body: some View {
        NavigationStack {
            List {
                // ── System permission status ───────────────────────────────────
                systemStatusSection

                // ── Per-category toggles ───────────────────────────────────────
                if systemAuthStatus == .authorized || systemAuthStatus == .provisional {
                    orderNotificationsSection
                    customerNotificationsSection
                    staffNotificationsSection
                    testSection
                }
            }
            .navigationTitle("push_notification_settings".localized(for: appLanguage))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("done".localized(for: appLanguage)) { dismiss() }
                }
            }
            .task { await refreshAuthStatus() }
            .onChange(of: prefs.newOrders)         { prefs.save() }
            .onChange(of: prefs.orderReady)        { prefs.save() }
            .onChange(of: prefs.serviceRequests)   { prefs.save() }
            .onChange(of: prefs.tableStatus)       { prefs.save() }
            .onChange(of: prefs.webOrders)         { prefs.save() }
            .onChange(of: prefs.shiftReminders)    { prefs.save() }
            .onChange(of: prefs.timecardReminders) { prefs.save() }
            .onChange(of: prefs.inventoryAlerts)   { prefs.save() }
            .alert("test_push_result".localized(for: appLanguage), isPresented: $showTestResult) {
                Button("ok".localized(for: appLanguage), role: .cancel) { testResult = nil }
            } message: {
                Text(testResult ?? "")
            }
        }
    }

    // ── Sections ───────────────────────────────────────────────────────────────

    private var systemStatusSection: some View {
        Section {
            HStack(spacing: 14) {
                Image(systemName: statusIcon)
                    .font(.system(size: 22))
                    .foregroundStyle(statusColor)
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 3) {
                    Text(statusTitle)
                        .font(.subheadline.weight(.semibold))
                    Text(statusDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if systemAuthStatus == .denied {
                    Button(appLanguage == "th" ? "ตั้งค่า" : "Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                } else if systemAuthStatus == .notDetermined {
                    Button(appLanguage == "th" ? "เปิดใช้งาน" : "Enable") {
                        Task { await requestPermission() }
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("system_notifications".localized(for: appLanguage))
        }
    }

    private var orderNotificationsSection: some View {
        Section {
            Toggle(isOn: $prefs.newOrders) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(appLanguage == "th" ? "ออเดอร์ใหม่" : "New Orders")
                            .font(.subheadline)
                        Text(appLanguage == "th" ? "แจ้งเตือนเมื่อมีออเดอร์เข้ามาใหม่" : "Alert when a new order is placed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "doc.text.fill")
                        .foregroundStyle(.blue)
                }
            }

            Toggle(isOn: $prefs.orderReady) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(appLanguage == "th" ? "ออเดอร์พร้อมเสิร์ฟ" : "Order Ready")
                            .font(.subheadline)
                        Text(appLanguage == "th" ? "แจ้งเตือนเมื่อครัวทำอาหารเสร็จแล้ว" : "Alert when kitchen marks an order ready")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            Toggle(isOn: $prefs.webOrders) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(appLanguage == "th" ? "ออเดอร์จากเว็บ/ลูกค้า" : "Web Orders")
                            .font(.subheadline)
                        Text(appLanguage == "th" ? "แจ้งเตือนออเดอร์สั่งเองของลูกค้า" : "Alert for customer self-ordering app orders")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "network")
                        .foregroundStyle(.purple)
                }
            }
        } header: {
            Text("order_notifications".localized(for: appLanguage))
        }
    }

    private var customerNotificationsSection: some View {
        Section {
            Toggle(isOn: $prefs.serviceRequests) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(appLanguage == "th" ? "คำขอบริการจากลูกค้า" : "Service Requests")
                            .font(.subheadline)
                        Text(appLanguage == "th" ? "แจ้งเตือนเมื่อลูกค้ากดเรียกพนักงาน" : "Alert when customers request assistance")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "bell.badge.fill")
                        .foregroundStyle(.orange)
                }
            }

            Toggle(isOn: $prefs.tableStatus) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(appLanguage == "th" ? "สถานะโต๊ะเปลี่ยนแปลง" : "Table Status Changes")
                            .font(.subheadline)
                        Text(appLanguage == "th" ? "แจ้งเตือนเมื่อเปิดหรือปิดโต๊ะ" : "Alert when tables open or close sessions")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "table.furniture")
                        .foregroundStyle(.teal)
                }
            }
        } header: {
            Text("customer_notifications".localized(for: appLanguage))
        }
    }

    private var staffNotificationsSection: some View {
        Section {
            Toggle(isOn: $prefs.shiftReminders) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(appLanguage == "th" ? "เตือนเวลากะงาน" : "Shift Reminders")
                            .font(.subheadline)
                        Text(appLanguage == "th" ? "เตือนล่วงหน้า 30 นาทีก่อนเริ่มกะงาน" : "Remind me 30 min before my shift starts")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "calendar.badge.clock")
                        .foregroundStyle(.indigo)
                }
            }

            Toggle(isOn: $prefs.timecardReminders) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(appLanguage == "th" ? "เตือนลงเวลาเข้า-ออกงาน" : "Timecard Reminders")
                            .font(.subheadline)
                        Text(appLanguage == "th" ? "เตือนให้ลงเวลาเข้าหรือออกงานตามกะ" : "Remind me to clock in/out for my shift")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "clock.badge.exclamationmark")
                        .foregroundStyle(.red)
                }
            }

            Toggle(isOn: $prefs.inventoryAlerts) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(appLanguage == "th" ? "เตือนสต็อกสินค้า" : "Inventory Alerts")
                            .font(.subheadline)
                        Text(appLanguage == "th" ? "แจ้งเตือนเมื่อสินค้าหมดหรือเหลือน้อยวิกฤต" : "Alert when stock hits zero or is critically low")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "shippingbox.fill")
                        .foregroundStyle(.teal)
                }
            }
        } header: {
            Text("staff_operational_notifications".localized(for: appLanguage))
        }
    }

    private var testSection: some View {
        Section {
            Button {
                Task { await sendTestPush() }
            } label: {
                HStack {
                    Label("send_test_push".localized(for: appLanguage), systemImage: "paperplane.fill")
                    Spacer()
                    if isTesting {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
            .disabled(isTesting)
        } header: {
            Text("test_notification_delivery".localized(for: appLanguage))
        } footer: {
            Text(appLanguage == "th" ? "ส่งการแจ้งเตือนทดสอบมายังอุปกรณ์เครื่องนี้ผ่านเซิร์ฟเวอร์ AlphaPos ให้สลับแอปไปเบื้องหลังก่อนเพื่อดูแบนเนอร์ระบบ" : "Sends a test push to this device via the AlphaPos server. Put the app in background first to see the system banner.")
                .font(.caption)
        }
    }

    // ── Helpers ────────────────────────────────────────────────────────────────

    private var statusIcon: String {
        switch systemAuthStatus {
        case .authorized:    return "bell.fill"
        case .provisional:   return "bell.badge.fill"
        case .denied:        return "bell.slash.fill"
        default:             return "bell"
        }
    }

    private var statusColor: Color {
        switch systemAuthStatus {
        case .authorized:    return .green
        case .provisional:   return .orange
        case .denied:        return .red
        default:             return .gray
        }
    }

    private var statusTitle: String {
        switch systemAuthStatus {
        case .authorized:
            return appLanguage == "th" ? "เปิดใช้งานการแจ้งเตือนแล้ว" : (appLanguage == "lo" ? "ເປີດໃຊ້ການແຈ້ງເຕືອນແລ້ວ" : "Notifications Enabled")
        case .provisional:
            return appLanguage == "th" ? "แบบไม่รบกวน (เงียบ)" : (appLanguage == "lo" ? "ແບບງຽບ" : "Provisional (Quiet)")
        case .denied:
            return appLanguage == "th" ? "ปิดการแจ้งเตือนอยู่" : (appLanguage == "lo" ? "ປິດການແຈ້ງເຕືອນຢູ່" : "Notifications Disabled")
        default:
            return appLanguage == "th" ? "ยังไม่ได้ขอสิทธิ์" : (appLanguage == "lo" ? "ຍັງບໍ່ໄດ້ຂໍສິດ" : "Permission Not Requested")
        }
    }

    private var statusDescription: String {
        switch systemAuthStatus {
        case .authorized:
            return appLanguage == "th" ? "คุณจะได้รับการแจ้งเตือนทั้งหมดที่ตั้งค่าไว้" : (appLanguage == "lo" ? "ທ່ານຈະໄດ້ຮັບການແຈ້ງເຕືອນທັງໝົດທີ່ຕັ້ງໄວ້" : "You will receive all configured push alerts.")
        case .provisional:
            return appLanguage == "th" ? "การแจ้งเตือนจะแสดงเงียบๆ ในศูนย์การแจ้งเตือนเท่านั้น" : (appLanguage == "lo" ? "ການແຈ້ງເຕືອນຈະສະແດງງຽບໆ ໃນສູນແຈ້ງເຕືອນ" : "Pushes appear silently in Notification Center only.")
        case .denied:
            return appLanguage == "th" ? "เปิดใช้งานใน การตั้งค่า → AlphaPos Staff → การแจ้งเตือน" : (appLanguage == "lo" ? "ເປີດໃຊ້ໃນ ການຕັ້ງຄ່າ → AlphaPos Staff → ການແຈ້ງເຕືອນ" : "Enable in Settings → AlphaPos Staff → Notifications.")
        default:
            return appLanguage == "th" ? "กดเปิดใช้งานเพื่อรับการแจ้งเตือน" : (appLanguage == "lo" ? "ກົດເປີດໃຊ້ເພື່ອຮັບການແຈ້ງເຕືອນ" : "Tap Enable to allow push notifications.")
        }
    }

    private func refreshAuthStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        await MainActor.run { systemAuthStatus = settings.authorizationStatus }
    }

    private func requestPermission() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            if granted {
                await MainActor.run {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
            await refreshAuthStatus()
        } catch {
            #if DEBUG
            print("PushSettingsView: Authorization request failed: \(error)")
            #endif
        }
    }

    private func sendTestPush() async {
        isTesting = true
        defer { isTesting = false }

        do {
            let result = try await NetworkService.shared.sendStaffPush(
                eventType: "new_order",
                orderNumber: "TEST-001",
                tableNumber: "1",
                message: "This is a test push notification from AlphaPos Staff"
            )
            let delivered = result["delivered"] as? Int ?? 0
            let total = result["total"] as? Int ?? 0
            testResult = delivered > 0
                ? "✅ Push delivered to \(delivered)/\(total) device(s). Put the app in background to see the banner."
                : "⚠️ No active devices found. Make sure the token is registered."
        } catch {
            testResult = "❌ Failed: \(error.localizedDescription)"
        }
        showTestResult = true
    }
}

// ── Preview ────────────────────────────────────────────────────────────────────

#Preview {
    PushNotificationSettingsView()
}
