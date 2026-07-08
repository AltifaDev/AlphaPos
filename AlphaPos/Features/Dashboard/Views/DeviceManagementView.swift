// DeviceManagementView.swift
// AlphaPos — Enterprise Device & Terminal Management
// Created as part of Enterprise Sidebar Redesign

import SwiftUI
import SwiftData
import Combine

/// Device Management Dashboard for monitoring all connected devices.
/// Critical for multi-device enterprise POS operations.
///
/// Enterprise features:
/// - Real-time device status (online/offline/syncing)
/// - Last sync timestamp per device
/// - Battery level (mobile devices)
/// - App version per device
/// - Remote actions: force sync, force logout, wipe data
/// - Register session status per terminal
/// - Device groups & assignment
/// - Offline queue depth per device
struct DeviceManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var lm: LocalizationManager
    @AppStorage("active_branch_id") private var activeBranchId = ""

    @Query(sort: \MerchantDevice.deviceName) private var devices: [MerchantDevice]
    @State private var selectedDevice: MerchantDevice? = nil
    @State private var showAddDevice = false
    @State private var remoteActionInProgress: UUID? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection

            Divider().background(Color.appDivider)

            // Content
            HStack(spacing: 0) {
                // Device grid
                deviceGridSection
                    .frame(maxWidth: .infinity)

                // Detail panel
                if selectedDevice != nil {
                    Divider().background(Color.appDivider)
                    deviceDetailPanel
                        .frame(width: 320)
                }
            }
        }
        .background(Color.appBackground)
        .sheet(isPresented: $showAddDevice) {
            AddDevicePlaceholder()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("devices_title".t)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.textPrimary)
                Text("\(devices.count) " + "devices_connected".t)
                    .font(.subheadline)
                    .foregroundColor(.textSecondary)
            }

            Spacer()

            // Status summary
            HStack(spacing: 16) {
                statusChip(count: onlineCount, label: "Online", color: .green)
                statusChip(count: offlineCount, label: "Offline", color: .red)
                statusChip(count: syncingCount, label: "Syncing", color: .orange)
            }

            Spacer()

            // Add device
            Button {
                showAddDevice = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("add_device".t)
                }
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.appAccent)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }

    private func statusChip(count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text("\(count)")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.textPrimary)
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.textSecondary)
        }
    }

    // MARK: - Device Grid

    private var deviceGridSection: some View {
        ScrollView {
            if devices.filter({ !$0.isDeleted }).isEmpty {
                ContentUnavailableView(
                    "No Paired Devices",
                    systemImage: "ipad.and.iphone.slash",
                    description: Text("Pair a device to monitor its real sync status here.")
                )
                .padding(.top, 80)
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16)
                ], spacing: 16) {
                    ForEach(devices.filter { !$0.isDeleted }, id: \.id) { device in
                        deviceCard(
                            name: device.deviceName,
                            type: deviceType(from: device),
                            status: status(for: device),
                            lastSync: device.lastSeenAt ?? device.createdAt,
                            appVersion: currentAppVersion,
                            registerActive: false
                        )
                        .onTapGesture {
                            withAnimation { selectedDevice = device }
                        }
                    }
                }
                .padding()
            }
        }
    }

    private func deviceCard(name: String, type: DeviceType, status: DeviceStatus, lastSync: Date, appVersion: String, registerActive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: type.icon)
                    .font(.system(size: 20))
                    .foregroundColor(type.color)
                Spacer()
                // Status dot
                HStack(spacing: 4) {
                    Circle()
                        .fill(status.color)
                        .frame(width: 8, height: 8)
                    Text(status.rawValue)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(status.color)
                }
            }

            // Name
            Text(name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.textPrimary)
                .lineLimit(1)

            // Info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 9))
                    Text("Synced \(lastSync.formatted(.relative(presentation: .named)))")
                        .font(.system(size: 10))
                }
                .foregroundColor(.textTertiary)

                HStack(spacing: 4) {
                    Image(systemName: "app.badge")
                        .font(.system(size: 9))
                    Text("v\(appVersion)")
                        .font(.system(size: 10))
                }
                .foregroundColor(.textTertiary)
            }

            // Register badge
            if registerActive {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text("Register Active")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.green)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.1))
                .cornerRadius(6)
            }
        }
        .padding(14)
        .background(Color.appSurface)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.appBorderSubtle, lineWidth: 1)
        )
    }

    // MARK: - Device Detail Panel

    private var deviceDetailPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let device = selectedDevice {
                Text(device.deviceName)
                    .font(.title3.weight(.bold))
                    .foregroundColor(.textPrimary)

                if isCurrentDevice(device) {
                    actionButton(icon: "arrow.triangle.2.circlepath", title: "Sync This Device", color: .blue) {
                        Task { await SyncEngine.shared.syncAll(modelContext: modelContext) }
                    }
                } else {
                    // H-6: Remote Actions — Force Sync, Toggle Trust, Remove Device
                    VStack(spacing: 6) {
                        Text("device_remote_actions_title".t)
                            .font(.caption.bold())
                            .foregroundColor(.appAccent)
                            .tracking(1)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        // Force Sync: mark device unsynced → triggers next sync pass
                        actionButton(icon: "arrow.triangle.2.circlepath",
                                     title: "device_force_sync_btn".t,
                                     color: .blue) {
                            device.isSynced = false
                            device.updatedAt = Date()
                            modelContext.saveWithLogging(label: "DeviceManagement.forceSync")
                            remoteActionInProgress = device.id
                            Task {
                                _ = try? await NetworkManager.shared.uploadMerchantDevice(device)
                                await MainActor.run { remoteActionInProgress = nil }
                            }
                        }

                        // Toggle Trust
                        actionButton(icon: device.isTrusted ? "lock.open.fill" : "lock.fill",
                                     title: device.isTrusted ? "device_revoke_trust_btn".t : "device_grant_trust_btn".t,
                                     color: device.isTrusted ? .appRose : .appTeal) {
                            device.isTrusted.toggle()
                            device.isSynced = false
                            device.updatedAt = Date()
                            modelContext.saveWithLogging(label: "DeviceManagement.toggleTrust")
                            Task { _ = try? await NetworkManager.shared.uploadMerchantDevice(device) }
                        }

                        // Remove Device (soft-delete)
                        actionButton(icon: "trash", title: "device_remove_btn".t, color: .appRose) {
                            device.isDeleted = true
                            device.isSynced = false
                            device.updatedAt = Date()
                            modelContext.saveWithLogging(label: "DeviceManagement.removeDevice")
                            selectedDevice = nil
                            Task { _ = try? await NetworkManager.shared.uploadMerchantDevice(device) }
                        }
                    }
                }

                Spacer()
            }
        }
        .padding()
        .background(Color.appSurface)
    }

    private func actionButton(icon: String, title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(color)
                    .frame(width: 28, height: 28)
                    .background(color.opacity(0.1))
                    .cornerRadius(6)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11))
                    .foregroundColor(.textTertiary)
            }
            .padding(10)
            .background(Color.appSurfaceHigh)
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private var onlineCount: Int {
        devices.filter { device in
            guard let lastSeen = device.lastSeenAt else { return false }
            return Date().timeIntervalSince(lastSeen) < 300 // online if seen within last 5 minutes
        }.count
    }

    private var offlineCount: Int {
        devices.filter { device in
            guard let lastSeen = device.lastSeenAt else { return true }
            return Date().timeIntervalSince(lastSeen) >= 300 // offline if not seen within last 5 minutes
        }.count
    }

    private var syncingCount: Int {
        devices.filter { !$0.isSynced }.count
    }

    private var currentAppVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private func status(for device: MerchantDevice) -> DeviceStatus {
        if !device.isSynced { return .syncing }
        guard let lastSeen = device.lastSeenAt,
              Date().timeIntervalSince(lastSeen) < 300 else { return .offline }
        return .online
    }

    private func isCurrentDevice(_ device: MerchantDevice) -> Bool {
        UserDefaults.standard.string(forKey: "alphapos_current_device_id") == device.id.uuidString.lowercased()
    }

    enum DeviceType {
        case master, staff, kds, customer

        var icon: String {
            switch self {
            case .master: return "ipad.landscape"
            case .staff: return "iphone"
            case .kds: return "display"
            case .customer: return "qrcode.viewfinder"
            }
        }

        var color: Color {
            switch self {
            case .master: return .appAccent
            case .staff: return Color(hex: "8B5CF6")
            case .kds: return Color(hex: "F59E0B")
            case .customer: return Color(hex: "10B981")
            }
        }
    }

    enum DeviceStatus: String {
        case online = "Online"
        case offline = "Offline"
        case syncing = "Syncing"

        var color: Color {
            switch self {
            case .online: return .green
            case .offline: return .red
            case .syncing: return .orange
            }
        }
    }

    private func deviceType(from device: MerchantDevice) -> DeviceType {
        switch device.deviceType.lowercased() {
        case "master", "pos_register": return .master
        case "staff", "waiter_handheld": return .staff
        case "kds", "kds_screen": return .kds
        case "customer", "customer_self_order": return .customer
        default: return .staff
        }
    }
}

// MARK: - Add Device Placeholder

private struct AddDevicePlaceholder: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("active_branch_id") private var activeBranchId = ""

    @State private var pairingToken: String = ""
    @State private var pairingCode: String = ""
    @State private var timeLeft: Int = 0
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    // H-5: Polling for pairing completion
    @State private var isPaired: Bool = false
    @State private var pairedDeviceName: String = ""
    @Environment(\.modelContext) private var modelContext

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var merchantId: UUID {
        let mStr = UserDefaults.standard.string(forKey: "active_merchant_id") ?? AppConfig.shared.defaultMerchantId
        return UUID(uuidString: mStr) ?? UUID(uuidString: "163350b0-056d-4d5e-b5d4-24e7aac5ab6d")!
    }
    private var branchId: UUID {
        return UUID(uuidString: activeBranchId) ?? UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // H-5: Paired success state
                if isPaired {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.appTeal)
                        Text("device_paired_success_title".t)
                            .font(.title2.weight(.bold))
                            .foregroundColor(.textPrimary)
                        Text("\"\(pairedDeviceName)\"")
                            .font(.headline)
                            .foregroundColor(.appAccent)
                        Text("device_paired_success_desc".t)
                            .font(.subheadline)
                            .foregroundColor(.textSecondary)
                            .multilineTextAlignment(.center)
                        Button("done_btn".t) { dismiss() }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding()
                } else if isLoading {
                    ProgressView("Generating pairing code...")
                        .padding()
                } else if let error = errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.orange)
                        Text("Connection Failed")
                            .font(.headline)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        Button("Try Again") {
                            generateToken()
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top)
                    }
                } else {
                    VStack(spacing: 16) {
                        Text("device_pair_title".t)
                            .font(.title2.weight(.bold))
                            .foregroundColor(.textPrimary)
                        Text("device_pair_desc".t)
                            .font(.subheadline)
                            .foregroundColor(.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        // QR Code image
                        if let qrImage = generateQRCodeImage(from: "alphapos://pair?token=\(pairingToken)") {
                            Image(uiImage: qrImage)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 220, height: 220)
                                .padding(16)
                                .background(Color.white)
                                .cornerRadius(16)
                                .shadow(radius: 4)
                        } else {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.appSurfaceHigh)
                                .frame(width: 220, height: 220)
                                .overlay(
                                    Image(systemName: "qrcode")
                                        .font(.system(size: 80))
                                        .foregroundColor(.textTertiary)
                                )
                        }

                        // Passcode display (large, e.g. 123 456)
                        VStack(spacing: 4) {
                            Text("หรือป้อนรหัสจับคู่นี้ที่อุปกรณ์พนักงาน")
                                .font(.caption)
                                .foregroundColor(.textTertiary)
                            Text(formatPasscode(pairingCode))
                                .font(.system(size: 36, weight: .black, design: .monospaced))
                                .foregroundColor(.appAccent)
                                .tracking(4)
                        }
                        .padding(.vertical, 8)

                        // Timer countdown
                        HStack(spacing: 6) {
                            Image(systemName: "timer")
                            Text("รหัสหมดอายุใน: \(formatTime(timeLeft))")
                        }
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(timeLeft < 60 ? .red : .textSecondary)

                        Button(action: {
                            generateToken()
                        }) {
                            Label("รีเซ็ต QR Code ใหม่", systemImage: "arrow.clockwise")
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.appSurfaceHigh)
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
            .navigationTitle("Add Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear {
                generateToken()
            }
            .onReceive(timer) { _ in
                if timeLeft > 0 {
                    timeLeft -= 1
                    if timeLeft == 0 {
                        generateToken()
                    }
                    // H-5: Poll every 3 seconds to check if Staff app completed pairing
                    if !isPaired && !pairingToken.isEmpty && timeLeft % 3 == 0 {
                        Task { await pollPairingStatus() }
                    }
                }
            }
        }
    }

    private func generateToken() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let pairing = try await NetworkManager.shared.createPairingToken(merchantId: merchantId, branchId: branchId)
                await MainActor.run {
                    self.pairingToken = pairing.token
                    self.pairingCode = pairing.pairingCode
                    self.timeLeft = Int(pairing.expiresAt.timeIntervalSinceNow)
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    // H-5: Poll Supabase to detect if Staff app has completed pairing
    @MainActor
    private func pollPairingStatus() async {
        guard !pairingToken.isEmpty, !isPaired else { return }
        do {
            guard let info = try await NetworkManager.shared.checkPairingStatus(token: pairingToken)
            else { return }

            // Save new MerchantDevice to SwiftData
            let newDevice = MerchantDevice(
                id: info.id,
                deviceName: info.deviceName,
                deviceType: info.deviceType,
                branchId: info.branchId,
                deviceFingerprintHash: info.fingerprint,
                isTrusted: info.isTrusted,
                lastSeenAt: Date(),
                createdAt: info.createdAt,
                isSynced: true,
                isDeleted: false,
                updatedAt: Date()
            )
            modelContext.insert(newDevice)
            modelContext.saveWithLogging(label: "AddDevicePlaceholder.pollPairingStatus")

            pairedDeviceName = info.deviceName
            isPaired = true
            APHaptic.trigger()
        } catch {
            // Silently ignore poll errors — will retry next tick
        }
    }

    private func generateQRCodeImage(from string: String) -> UIImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        let data = string.data(using: .ascii)
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel")
        guard let ciImage = filter.outputImage else { return nil }

        let transform = CGAffineTransform(scaleX: 10, y: 10)
        let scaledCIImage = ciImage.transformed(by: transform)

        let context = CIContext()
        guard let cgImage = context.createCGImage(scaledCIImage, from: scaledCIImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private func formatPasscode(_ code: String) -> String {
        guard code.count == 6 else { return code }
        let index = code.index(code.startIndex, offsetBy: 3)
        return String(code[..<index]) + " " + String(code[index...])
    }

    private func formatTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }
}
