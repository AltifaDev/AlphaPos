// PushNotificationSettingsView.swift
// AlphaPosStaff — Push Notification Preferences UI
//
// Staff can individually toggle each push notification category.
// Includes a "Test Push" button to verify APNs is working end-to-end.

import SwiftUI
import UserNotifications

struct PushNotificationSettingsView: View {
    // ── State ──────────────────────────────────────────────────────────────────
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
            .navigationTitle("Push Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
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
            .alert("Test Push Result", isPresented: $showTestResult) {
                Button("OK", role: .cancel) { testResult = nil }
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
                    Button("Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                } else if systemAuthStatus == .notDetermined {
                    Button("Enable") {
                        Task { await requestPermission() }
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("System Permission")
        }
    }

    private var orderNotificationsSection: some View {
        Section {
            Toggle(isOn: $prefs.newOrders) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("New Orders")
                            .font(.subheadline)
                        Text("Alert when a new order is placed")
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
                        Text("Order Ready")
                            .font(.subheadline)
                        Text("Alert when kitchen marks an order ready")
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
                        Text("Web Orders")
                            .font(.subheadline)
                        Text("Alert for customer self-ordering app orders")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "network")
                        .foregroundStyle(.purple)
                }
            }
        } header: {
            Text("Orders")
        }
    }

    private var customerNotificationsSection: some View {
        Section {
            Toggle(isOn: $prefs.serviceRequests) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Service Requests")
                            .font(.subheadline)
                        Text("Alert when customers request assistance")
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
                        Text("Table Status Changes")
                            .font(.subheadline)
                        Text("Alert when tables open or close sessions")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "table.furniture")
                        .foregroundStyle(.teal)
                }
            }
        } header: {
            Text("Customers")
        }
    }

    private var staffNotificationsSection: some View {
        Section {
            Toggle(isOn: $prefs.shiftReminders) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Shift Reminders")
                            .font(.subheadline)
                        Text("Remind me 30 min before my shift starts")
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
                        Text("Timecard Reminders")
                            .font(.subheadline)
                        Text("Remind me to clock in/out for my shift")
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
                        Text("Inventory Alerts")
                            .font(.subheadline)
                        Text("Alert when stock hits zero or is critically low")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "shippingbox.fill")
                        .foregroundStyle(.teal)
                }
            }
        } header: {
            Text("My Schedule")
        }
    }

    private var testSection: some View {
        Section {
            Button {
                Task { await sendTestPush() }
            } label: {
                HStack {
                    Label("Send Test Push", systemImage: "paperplane.fill")
                    Spacer()
                    if isTesting {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
            .disabled(isTesting)
        } header: {
            Text("Test")
        } footer: {
            Text("Sends a test push to this device via the AlphaPos server. Put the app in background first to see the system banner.")
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
        case .authorized:    return "Notifications Enabled"
        case .provisional:   return "Provisional (Quiet)"
        case .denied:        return "Notifications Disabled"
        default:             return "Permission Not Requested"
        }
    }

    private var statusDescription: String {
        switch systemAuthStatus {
        case .authorized:    return "You will receive all configured push alerts."
        case .provisional:   return "Pushes appear silently in Notification Center only."
        case .denied:        return "Enable in Settings → AlphaPos Staff → Notifications."
        default:             return "Tap Enable to allow push notifications."
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
