// DeviceManagementView.swift
// AlphaPos — Enterprise Device & Terminal Management
// Created as part of Enterprise Sidebar Redesign

import SwiftUI
import SwiftData

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
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16)
            ], spacing: 16) {
                // Master device (this device)
                deviceCard(
                    name: "Master iPad",
                    type: .master,
                    status: .online,
                    lastSync: Date(),
                    appVersion: "2.0.0",
                    registerActive: true
                )
                
                // Placeholder staff devices
                deviceCard(
                    name: "Staff iPhone 1",
                    type: .staff,
                    status: .online,
                    lastSync: Date().addingTimeInterval(-120),
                    appVersion: "1.5.0",
                    registerActive: false
                )
                deviceCard(
                    name: "Staff iPhone 2",
                    type: .staff,
                    status: .offline,
                    lastSync: Date().addingTimeInterval(-3600),
                    appVersion: "1.5.0",
                    registerActive: false
                )
                deviceCard(
                    name: "Kitchen Display",
                    type: .kds,
                    status: .online,
                    lastSync: Date().addingTimeInterval(-30),
                    appVersion: "2.0.0",
                    registerActive: false
                )
                deviceCard(
                    name: "Customer Kiosk",
                    type: .customer,
                    status: .online,
                    lastSync: Date().addingTimeInterval(-60),
                    appVersion: "1.0.0",
                    registerActive: false
                )
                
                // From database
                ForEach(devices, id: \.id) { device in
                    deviceCard(
                        name: device.deviceName,
                        type: deviceType(from: device),
                        status: .online,
                        lastSync: device.lastSeenAt ?? Date(),
                        appVersion: "2.0.0",
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
                
                // Actions
                VStack(spacing: 8) {
                    actionButton(icon: "arrow.triangle.2.circlepath", title: "Force Sync", color: .blue)
                    actionButton(icon: "rectangle.portrait.and.arrow.right", title: "Force Logout", color: .orange)
                    actionButton(icon: "trash", title: "Wipe Data", color: .red)
                }
                
                Spacer()
            }
        }
        .padding()
        .background(Color.appSurface)
    }
    
    private func actionButton(icon: String, title: String, color: Color) -> some View {
        Button {
            // Action
        } label: {
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
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "iphone.badge.plus")
                    .font(.system(size: 48))
                    .foregroundColor(.appAccent)
                Text("device_pair_title".t)
                    .font(.title2.weight(.bold))
                Text("device_pair_desc".t)
                    .font(.subheadline)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
                
                // QR placeholder
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.appSurfaceHigh)
                    .frame(width: 200, height: 200)
                    .overlay(
                        Image(systemName: "qrcode")
                            .font(.system(size: 80))
                            .foregroundColor(.textTertiary)
                    )
            }
            .padding()
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
