import SwiftUI

struct TableSystemSettingsView: View {
    @AppStorage("enable_table_system") private var enableTableSystem = true
    @AppStorage("enable_web_ordering") private var enableWebOrdering = true
    @AppStorage("offline_sync_mode") private var offlineSyncMode = false
    @AppStorage("table_qr_print_mode") private var qrPrintMode = "permanent"
    @AppStorage("enable_pos_sound_effects") private var enablePOSSoundEffects = true
    @AppStorage("pos_sound_volume") private var posSoundVolume = 1.0
    @State private var featureSyncStatus: String?
    @State private var isSyncingFeatures = false
    @State private var isRollingBack = false
    
    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L.Sections.tableSystem.t)
                            .font(.system(size: 12))
                            .fontWeight(.bold)
                            .foregroundColor(.appAccent)
                            .tracking(1.0)
                        
                        VStack(spacing: 14) {
                            Toggle(isOn: $enableTableSystem) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(L.TableSystem.enableTable.t)
                                        .foregroundColor(.textPrimary)
                                    Text(L.TableSystem.enableTableDesc.t)
                                        .font(.system(size: 12))
                                        .foregroundColor(.textSecondary)
                                }
                            }
                            .tint(.appAccent)
                            .onChange(of: enableTableSystem) { oldValue, _ in
                                guard !isRollingBack else { return }
                                pushFeatureFlags { enableTableSystem = oldValue }
                            }
                            
                            Divider()
                                .background(Color.appDivider)
                            
                            Toggle(isOn: $enableWebOrdering) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(L.TableSystem.enableWebOrdering.t)
                                        .foregroundColor(offlineSyncMode ? .textTertiary : .textPrimary)
                                    if offlineSyncMode {
                                        Text("web_ordering_offline_unavailable".t)
                                            .font(.system(size: 12))
                                            .foregroundColor(.orange)
                                    } else {
                                        Text(L.TableSystem.enableWebDesc.t)
                                            .font(.system(size: 12))
                                            .foregroundColor(.textSecondary)
                                    }
                                }
                            }
                            .tint(.appAccent)
                            .disabled(offlineSyncMode)
                            .onChange(of: enableWebOrdering) { oldValue, _ in
                                guard !isRollingBack else { return }
                                pushFeatureFlags { enableWebOrdering = oldValue }
                            }

                            if let featureSyncStatus {
                                Label(featureSyncStatus, systemImage: isSyncingFeatures ? "arrow.triangle.2.circlepath" : "info.circle")
                                    .font(.caption)
                                    .foregroundStyle(featureSyncStatus == "บันทึกแล้ว" ? Color.green : Color.orange)
                            }

                            if enableWebOrdering {
                                Divider().background(Color.appDivider)

                                Picker("QR Code สำหรับพิมพ์", selection: $qrPrintMode) {
                                    Text("QR ประจำโต๊ะ").tag("permanent")
                                    Text("QR ตามรอบลูกค้า").tag("session")
                                }
                                .pickerStyle(.segmented)

                                Text(qrPrintMode == "permanent"
                                     ? "พิมพ์ครั้งเดียวและใช้ซ้ำได้"
                                     : "ใช้ได้เฉพาะรอบลูกค้าปัจจุบัน และหมดอายุเมื่อเคลียร์โต๊ะ")
                                    .font(.system(size: 12))
                                    .foregroundColor(.textSecondary)
                            }
                        }
                        .apCard()
                    }
                    .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 12) {
                        Text(LocalizationManager.shared.currentLanguage == .thai ? "เสียงประกอบและการตอบสนอง (Sound & Haptics)" : "POS Sound & Feedback")
                            .font(.system(size: 12))
                            .fontWeight(.bold)
                            .foregroundColor(.appAccent)
                            .tracking(1.0)

                        VStack(spacing: 14) {
                            Toggle(isOn: $enablePOSSoundEffects) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(LocalizationManager.shared.currentLanguage == .thai ? "เสียงประกอบ POS (Sound Effects)" : "POS Sound Effects")
                                        .foregroundColor(.textPrimary)
                                    Text(LocalizationManager.shared.currentLanguage == .thai ? "ส่งเสียงบี๊บชัดเจนเมื่อกดเลือกสินค้า และเสียงแคชเชียร์ Cha-Ching เมื่อรับชำระเงินสำเร็จ" : "Play crisp beep when selecting items and cash register Cha-Ching when payment succeeds")
                                        .font(.system(size: 12))
                                        .foregroundColor(.textSecondary)
                                }
                            }
                            .tint(.appAccent)

                            if enablePOSSoundEffects {
                                Divider().background(Color.appDivider)

                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text(LocalizationManager.shared.currentLanguage == .thai ? "ระดับความดังเสียง (Volume)" : "Volume")
                                            .foregroundColor(.textPrimary)
                                        Spacer()
                                        Text("\(Int(posSoundVolume * 100))%")
                                            .font(.system(size: 13, weight: .bold, design: .rounded))
                                            .foregroundColor(.appAccent)
                                    }

                                    Slider(value: $posSoundVolume, in: 0.1...1.0, step: 0.05)
                                        .tint(.appAccent)
                                        .onChange(of: posSoundVolume) { _, _ in
                                            APSoundEffect.itemTap()
                                        }

                                    HStack(spacing: 12) {
                                        Button {
                                            APSoundEffect.itemTap()
                                        } label: {
                                            HStack(spacing: 4) {
                                                Image(systemName: "speaker.wave.2.fill")
                                                Text(LocalizationManager.shared.currentLanguage == .thai ? "ทดสอบเสียงบี๊บ (Beep)" : "Test Beep")
                                                    .font(.system(size: 12, weight: .medium))
                                            }
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 7)
                                            .background(Color.appAccent.opacity(0.12), in: Capsule())
                                            .foregroundColor(.appAccent)
                                        }
                                        .buttonStyle(.plain)

                                        Button {
                                            APSoundEffect.paymentSuccess()
                                        } label: {
                                            HStack(spacing: 4) {
                                                Image(systemName: "dollarsign.circle.fill")
                                                Text(LocalizationManager.shared.currentLanguage == .thai ? "ทดสอบเสียงแคชเชียร์ (Cha-Ching 🪙)" : "Test Cha-Ching")
                                                    .font(.system(size: 12, weight: .medium))
                                            }
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 7)
                                            .background(Color.appTeal.opacity(0.12), in: Capsule())
                                            .foregroundColor(.appTeal)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.top, 4)
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
        .navigationTitle(L.Sections.tableSystem.t)
        .navigationBarTitleDisplayMode(.inline)
        .apNavBar(background: Color.appBackground)
    }

    private func pushFeatureFlags(rollback: @escaping () -> Void) {
        APHaptic.trigger()
        guard !offlineSyncMode else { return }
        isSyncingFeatures = true
        featureSyncStatus = "กำลังบันทึก..."
        Task {
            do {
                _ = try await NetworkManager.shared.updateMerchantFeatureFlags(
                    isTableSystemEnabled: enableTableSystem,
                    isWebOrderingEnabled: enableWebOrdering
                )
                await MainActor.run {
                    isSyncingFeatures = false
                    featureSyncStatus = "บันทึกแล้ว"
                }
            } catch {
                await MainActor.run {
                    isRollingBack = true
                    rollback()
                    isSyncingFeatures = false
                    featureSyncStatus = "บันทึกไม่สำเร็จ ระบบคืนค่าเดิมแล้ว"
                    DispatchQueue.main.async { isRollingBack = false }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        TableSystemSettingsView()
    }
}
