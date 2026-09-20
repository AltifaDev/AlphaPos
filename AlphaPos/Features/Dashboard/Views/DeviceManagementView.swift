// DeviceManagementView.swift
// AlphaPos — Enterprise Device & Terminal Management
// Created as part of Enterprise Sidebar Redesign

import SwiftUI
import SwiftData
import Combine
import UIKit
import CoreImage

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
    @AppStorage(BranchContext.storageKey) private var activeBranchId = ""
    // READ-ONLY MIRROR — the owner/writer of this flag is PrinterSettingsView.
    // Kept as @AppStorage (not UserDefaults) so the "Receipt Station" indicator
    // below stays reactive and updates instantly when the value is toggled on
    // the Printer settings page. Do NOT bind a Toggle to this flag here.
    @AppStorage("remote_receipt_print_enabled") private var remoteReceiptPrintEnabled = false

    @Query(sort: \MerchantDevice.deviceName) private var devices: [MerchantDevice]
    @State private var selectedDevice: MerchantDevice? = nil
    @State private var showAddDevice = false
    @State private var remoteActionInProgress: UUID? = nil
    // Hide a device immediately after a remove action. SwiftData/@Query may
    // refresh asynchronously, so the UI must not wait for the next sync pass.
    @State private var locallyRemovedDeviceIDs: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
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
        .navigationTitle("devices_title".t)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                headerSection
            }
        }
        .sheet(isPresented: $showAddDevice) {
            AddDevicePairingView()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 12) {
            // Status summary
            HStack(spacing: 16) {
                statusChip(count: onlineCount, label: "Online", color: .green)
                statusChip(count: offlineCount, label: "Offline", color: .red)
                statusChip(count: syncingCount, label: "Syncing", color: .orange)
            }

            // Receipt station indicator — shows whether THIS iPad prints
            // receipts for payments taken on staff phones.
            if remoteReceiptPrintEnabled {
                HStack(spacing: 6) {
                    Image(systemName: "printer.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.appAmber)
                    Text("Receipt Station")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.appAmber)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.appAmber.opacity(0.12))
                .clipShape(Capsule())
                .padding(.leading, 12)
            }

            // Add device
            Button {
                showAddDevice = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "ipad.and.iphone")
                    Text("connect_device".t)
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
            if visibleDevices.isEmpty {
                VStack(spacing: 18) {
                    ContentUnavailableView(
                        "devices_empty_title".t,
                        systemImage: "ipad.and.iphone.slash",
                        description: Text("devices_empty_message".t)
                    )

                    Button {
                        showAddDevice = true
                    } label: {
                        Label("connect_first_iphone".t, systemImage: "ipad.and.iphone")
                            .font(.system(size: 15, weight: .semibold))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .background(Color.appAccent)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 80)
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16)
                ], spacing: 16) {
                    ForEach(visibleDevices, id: \.id) { device in
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
                            // Update the view first. The remote operation is
                            // intentionally best-effort and can complete later.
                            locallyRemovedDeviceIDs.insert(device.id)
                            selectedDevice = nil

                            device.isDeleted = true
                            device.isSynced = false
                            device.updatedAt = Date()
                            modelContext.saveWithLogging(label: "DeviceManagement.removeDevice")
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

    private var visibleDevices: [MerchantDevice] {
        devices.filter {
            !$0.isDeleted && !locallyRemovedDeviceIDs.contains($0.id)
        }
    }

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

struct AddDevicePairingView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(BranchContext.storageKey) private var activeBranchId = ""
    @Query(sort: \Branch.name) private var allBranches: [Branch]
    var embedded = false

    @State private var pairingToken: String = ""
    @State private var pairingCode: String = ""
    @State private var timeLeft: Int = 0
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    @State private var isPaired: Bool = false
    @State private var pairedDeviceName: String = ""
    @State private var pendingDevice: NetworkManager.PairedDeviceInfo? = nil
    @State private var isApproving = false
    @Environment(\.modelContext) private var modelContext

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var merchantId: UUID? {
        let mStr = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        return UUID(uuidString: mStr)
    }

    /// Pairing must use the explicitly selected operational branch.
    private func resolveBranch() -> Branch? {
        try? BranchContext.shared.requireActiveBranch(in: modelContext)
    }

    var body: some View {
        Group {
            if embedded {
                pairingContent
            } else {
                NavigationStack {
                    pairingContent
                        .navigationTitle("Add Device")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") { dismiss() }
                            }
                        }
                }
            }
        }
        .onAppear {
            generateToken()
        }
        .onReceive(timer) { _ in
            if pendingDevice != nil {
                // Keep polling approval result; do not expire/regenerate while waiting.
                if timeLeft > 0 { timeLeft -= 1 }
                if !isPaired && !pairingToken.isEmpty && timeLeft % 2 == 0 {
                    Task { await pollPairingStatus() }
                }
                return
            }
            if timeLeft > 0 {
                timeLeft -= 1
                if timeLeft == 0 {
                    generateToken()
                }
                if !isPaired && !pairingToken.isEmpty && timeLeft % 3 == 0 {
                    Task { await pollPairingStatus() }
                }
            }
        }
    }

    private var pairingContent: some View {
        VStack(spacing: 24) {
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
                        Button(embedded ? "เชื่อมต่ออุปกรณ์อีกเครื่อง" : "done_btn".t) {
                            if embedded {
                                isPaired = false
                                pendingDevice = nil
                                generateToken()
                            } else {
                                dismiss()
                            }
                        }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding()
                } else if let pending = pendingDevice {
                    pendingApprovalCard(pending)
                } else if isLoading {
                    ProgressView("Generating pairing code...")
                        .padding()
                } else if let error = errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.orange)
                        Text("pairing_connection_failed".t)
                            .font(.headline)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        Button("retry".t) {
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

                        VStack(spacing: 4) {
                            Text("หรือป้อนรหัสจับคู่นี้ที่อุปกรณ์พนักงาน")
                                .font(.caption)
                                .foregroundColor(.textTertiary)
                            Text("รหัส 6 หลักต้องกด Approve บน iPad นี้")
                                .font(.caption2)
                                .foregroundColor(.textTertiary)
                            Text(formatPasscode(pairingCode))
                                .font(.system(size: 36, weight: .black, design: .monospaced))
                                .foregroundColor(.appAccent)
                                .tracking(4)
                        }
                        .padding(.vertical, 8)

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
    }

    @ViewBuilder
    private func pendingApprovalCard(_ pending: NetworkManager.PairedDeviceInfo) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "iphone.badge.checkmark")
                .font(.system(size: 52))
                .foregroundColor(.orange)
            Text("รออนุมัติอุปกรณ์")
                .font(.title2.weight(.bold))
                .foregroundColor(.textPrimary)
            Text("\"\(pending.deviceName)\"")
                .font(.headline)
                .foregroundColor(.appAccent)
            Text("มีอุปกรณ์ขอเชื่อมต่อด้วยรหัส 6 หลัก กรุณายืนยันบนเครื่องนี้ก่อนจึงจะเข้าใช้งานร้านได้")
                .font(.subheadline)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            HStack(spacing: 12) {
                Button {
                    rejectPending(pending)
                } label: {
                    Text("ปฏิเสธ")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isApproving)

                Button {
                    approvePending(pending)
                } label: {
                    if isApproving {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Approve")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isApproving)
            }
            .padding(.top, 8)
        }
        .padding()
    }

    private func generateToken() {
        guard let merchantId else {
            errorMessage = "pairing_error_no_merchant".t
            return
        }
        guard let branch = resolveBranch() else {
            errorMessage = "pairing_error_no_branch".t
            return
        }
        isLoading = true
        errorMessage = nil
        pendingDevice = nil
        Task {
            do {
                // The pairing RPC rejects branches the server doesn't know about,
                // so push a branch created offline before requesting a token.
                if !branch.isSynced, try await NetworkManager.shared.uploadBranch(branch) {
                    await MainActor.run {
                        branch.isSynced = true
                        modelContext.saveWithLogging(label: "AddDevicePairingView.pushBranch")
                    }
                }
                let pairing = try await NetworkManager.shared.createPairingToken(merchantId: merchantId, branchId: branch.id)
                await MainActor.run {
                    self.pairingToken = pairing.token
                    self.pairingCode = pairing.pairingCode
                    self.timeLeft = max(1, Int(pairing.expiresAt.timeIntervalSinceNow))
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = pairingErrorMessage(error)
                    self.isLoading = false
                }
            }
        }
    }

    private func pairingErrorMessage(_ error: Error) -> String {
        let raw = error.localizedDescription
        let upper = raw.uppercased()
        if upper.contains("PGRST002") || upper.contains("PGRST003")
            || upper.contains("HTTP 502") || upper.contains("HTTP 503") || upper.contains("HTTP 504") {
            return "เซิร์ฟเวอร์ฐานข้อมูลกำลังเริ่มต้นหรือมีการเชื่อมต่อหนาแน่น ระบบลองใหม่อัตโนมัติแล้ว กรุณากดลองอีกครั้งในไม่กี่วินาที"
        }
        return raw
    }

    @MainActor
    private func pollPairingStatus() async {
        guard !pairingToken.isEmpty, !isPaired else { return }
        do {
            guard let info = try await NetworkManager.shared.checkPairingStatus(token: pairingToken)
            else {
                // Pending request rejected → device row removed.
                if pendingDevice != nil {
                    pendingDevice = nil
                    errorMessage = "คำขอเชื่อมต่อถูกปฏิเสธ หรือหมดอายุแล้ว"
                    generateToken()
                }
                return
            }

            if !info.isTrusted {
                pendingDevice = info
                errorMessage = nil
                return
            }

            persistPairedDevice(info)
            pairedDeviceName = info.deviceName
            pendingDevice = nil
            isPaired = true
            APHaptic.trigger()
        } catch {
            // Silently ignore poll errors — will retry next tick
        }
    }

    private func approvePending(_ pending: NetworkManager.PairedDeviceInfo) {
        isApproving = true
        errorMessage = nil
        Task {
            do {
                try await NetworkManager.shared.approvePendingDevice(id: pending.id)
                await MainActor.run {
                    let approved = NetworkManager.PairedDeviceInfo(
                        id: pending.id,
                        deviceName: pending.deviceName,
                        deviceType: pending.deviceType,
                        branchId: pending.branchId,
                        isTrusted: true,
                        fingerprint: pending.fingerprint,
                        createdAt: pending.createdAt
                    )
                    persistPairedDevice(approved)
                    pairedDeviceName = approved.deviceName
                    pendingDevice = nil
                    isPaired = true
                    isApproving = false
                    APHaptic.trigger()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isApproving = false
                }
            }
        }
    }

    private func rejectPending(_ pending: NetworkManager.PairedDeviceInfo) {
        isApproving = true
        errorMessage = nil
        Task {
            do {
                try await NetworkManager.shared.rejectPendingDevice(id: pending.id)
                await MainActor.run {
                    pendingDevice = nil
                    isApproving = false
                    generateToken()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isApproving = false
                }
            }
        }
    }

    private func persistPairedDevice(_ info: NetworkManager.PairedDeviceInfo) {
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
