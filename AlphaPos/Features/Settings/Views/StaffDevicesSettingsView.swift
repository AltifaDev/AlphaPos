import SwiftUI
import SwiftData
import CoreImage

struct StaffDevicesSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MerchantDevice.updatedAt, order: .reverse) private var devices: [MerchantDevice]
    @AppStorage("active_merchant_id") private var activeMerchantId = "163350b0-056d-4d5e-b5d4-24e7aac5ab6d"
    
    @State private var statusMessage = ""
    @State private var showingStatusAlert = false
    
    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L.Sections.linkStaff.t)
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.appAccent)
                            .tracking(1.0)
                        
                        VStack(spacing: 16) {
                            Text("Waitstaff can pair their devices (AlphaPos Staff) by scanning this store's QR code or entering the ID below.")
                                .font(.subheadline)
                                .foregroundColor(.textSecondary)
                                .multilineTextAlignment(.leading)
                            
                            if let qrImage = generateQRCode(from: activeMerchantId) {
                                Image(uiImage: qrImage)
                                    .interpolation(.none)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 180, height: 180)
                                    .padding(12)
                                    .background(Color.white)
                                    .cornerRadius(APRadius.md)
                                    .shadow(color: Color.black.opacity(0.1), radius: 6)
                            } else {
                                ContentUnavailableView("QR Generation Failed", systemImage: "xmark.circle")
                                    .frame(height: 180)
                            }
                            
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Store ID (Merchant UUID)")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.textSecondary)
                                
                                HStack {
                                    Text(activeMerchantId)
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundColor(.textPrimary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.5)
                                    
                                    Spacer()
                                    
                                    Button(action: {
                                        UIPasteboard.general.string = activeMerchantId
                                        APHaptic.trigger()
                                        statusMessage = "Copied Merchant ID to clipboard."
                                        showingStatusAlert = true
                                    }) {
                                        Image(systemName: "doc.on.doc.fill")
                                            .foregroundColor(.appAccent)
                                    }
                                }
                                .padding(10)
                                .background(Color.appSurfaceHigh)
                                .cornerRadius(APRadius.sm)
                                .overlay(
                                    RoundedRectangle(cornerRadius: APRadius.sm)
                                        .stroke(Color.appBorderSubtle, lineWidth: 1)
                                )
                            }
                        }
                        .apCard()
                    }
                    .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("trusted_devices_title".t)
                            .font(.caption)
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
        .navigationTitle(L.Sections.linkStaff.t)
        .navigationBarTitleDisplayMode(.inline)
        .apNavBar(background: Color.appBackground)
        .onAppear {
            ensureCurrentDevice()
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
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                    if isCurrentDevice(device) {
                        Text("current_device_badge".t)
                            .font(.system(size: 9, weight: .black))
                            .foregroundColor(.appAccent)
                    }
                }
                Text("\(device.deviceType) • \(device.lastSeenAt?.formatted(date: .abbreviated, time: .shortened) ?? "Never seen")")
                    .font(.caption2)
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
                    try? modelContext.save()
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
        try? modelContext.save()
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
    
    private func generateQRCode(from string: String) -> UIImage? {
        let context = CIContext()
        let data = string.data(using: String.Encoding.ascii)
        if let filter = CIFilter(name: "CIQRCodeGenerator") {
            filter.setValue(data, forKey: "inputMessage")
            let transform = CGAffineTransform(scaleX: 10, y: 10)
            if let output = filter.outputImage?.transformed(by: transform) {
                if let cgImage = context.createCGImage(output, from: output.extent) {
                    return UIImage(cgImage: cgImage)
                }
            }
        }
        return nil
    }
}

#Preview {
    NavigationStack {
        StaffDevicesSettingsView()
    }
}
