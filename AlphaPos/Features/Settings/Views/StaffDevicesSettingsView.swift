import SwiftUI
import SwiftData

struct StaffDevicesSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MerchantDevice.updatedAt, order: .reverse) private var devices: [MerchantDevice]
    @AppStorage("offline_sync_mode") private var offlineSyncMode = false
    
    @State private var statusMessage = ""
    @State private var showingStatusAlert = false
    
    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            
            if offlineSyncMode {
                ContentUnavailableView(
                    "offline_mode".t,
                    systemImage: "wifi.slash",
                    description: Text("web_ordering_offline_unavailable".t)
                )
            } else {
                ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L.Sections.linkStaff.t)
                            .font(.system(size: 12))
                            .fontWeight(.bold)
                            .foregroundColor(.appAccent)
                            .tracking(1.0)
                        
                        AddDevicePairingView(embedded: true)
                            .apCard()
                    }
                    .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("trusted_devices_title".t)
                            .font(.system(size: 12))
                            .fontWeight(.bold)
                            .foregroundColor(.appAccent)
                            .tracking(1.0)

                        VStack(spacing: 0) {
                            if devices.filter({ !$0.isDeleted }).isEmpty {
                                ContentUnavailableView("No trusted devices", systemImage: "ipad.and.iphone")
                                    .frame(height: 160)
                            } else {
                                ForEach(devices.filter { !$0.isDeleted }) { device in
                                    deviceRow(device)
                                    if device.id != devices.filter({ !$0.isDeleted }).last?.id {
                                        Divider().background(Color.appDivider).padding(.leading, 56)
                                    }
                                }
                            }
                        }
                        .apCard()
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
                }
            }
        }
        .navigationTitle(L.Sections.linkStaff.t)
        .navigationBarTitleDisplayMode(.inline)
        .apNavBar(background: Color.appBackground)
        .onAppear {
            if !offlineSyncMode {
                ensureCurrentDevice()
            }
        }
        .alert("Database Operation", isPresented: $showingStatusAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(statusMessage)
        }
    }

    private func deviceRow(_ device: MerchantDevice) -> some View {
        HStack(spacing: 14) {
            Image(systemName: device.deviceType == "kds" ? "flame.fill" : "ipad")
                .foregroundColor(.white)
                .frame(width: 34, height: 34)
                .background(device.isTrusted ? Color.appTeal : Color.appRose)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(device.deviceName)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                    if isCurrentDevice(device) {
                        Text("current_device_badge".t)
                            .font(.system(size: 12, weight: .black))
                            .foregroundColor(.appAccent)
                    }
                }
                Text("\(device.deviceType) • \(device.lastSeenAt?.formatted(date: .abbreviated, time: .shortened) ?? "staff_device_never_seen".t)")
                    .font(.system(size: 12))
                    .foregroundColor(.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { device.isTrusted },
                set: { isTrusted in
                    device.isTrusted = isTrusted
                    device.isSynced = false
                    device.updatedAt = Date()
                    modelContext.insert(AuditLog(
                        actionType: isTrusted ? "device_trusted" : "device_revoked",
                        details: "\(device.deviceName) \(isTrusted ? "trusted" : "revoked")"
                    ))
                    modelContext.saveWithLogging(label: #function)
                }
            ))
            .labelsHidden()
            .tint(.appAccent)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }

    private func ensureCurrentDevice() {
        let key = "alphapos_current_device_id"
        if let rawId = UserDefaults.standard.string(forKey: key),
           let id = UUID(uuidString: rawId),
           devices.contains(where: { $0.id == id }) {
            return
        }

        let device = MerchantDevice(
            deviceName: currentDeviceName,
            deviceFingerprintHash: SecurityHelper.sha256(UUID().uuidString)
        )
        UserDefaults.standard.set(device.id.uuidString.lowercased(), forKey: key)
        modelContext.insert(device)
        modelContext.saveWithLogging(label: #function)
    }

    private func isCurrentDevice(_ device: MerchantDevice) -> Bool {
        UserDefaults.standard.string(forKey: "alphapos_current_device_id") == device.id.uuidString.lowercased()
    }

    private var currentDeviceName: String {
        #if os(iOS)
        return UIDevice.current.name
        #else
        return "AlphaPos Register"
        #endif
    }
    
}

#Preview {
    NavigationStack {
        StaffDevicesSettingsView()
    }
}
