import SwiftUI

enum AppTextSize: String, CaseIterable, Identifiable {
    case system
    case small
    case normal
    case large

    var id: String { rawValue }

    var dynamicTypeSize: DynamicTypeSize {
        switch self {
        case .system, .normal: return .large
        case .small: return .small
        case .large: return .xxxLarge
        }
    }

    var localizedName: String {
        switch self {
        case .system: return "ตามระบบ / System Default"
        case .small: return "เล็ก / Small"
        case .normal: return "ปกติ / Default"
        case .large: return "ใหญ่ / Large"
        }
    }
}

extension View {
    @ViewBuilder
    func appTextSize(_ value: AppTextSize) -> some View {
        if value == .system {
            self
        } else {
            self.dynamicTypeSize(value.dynamicTypeSize)
        }
    }
}

struct AppearanceSettingsView: View {
    /// When true (iPad split detail), hide nav chrome — parent Settings banner provides context.
    var embedded: Bool = false

    @AppStorage("app_theme") private var appTheme = AppTheme.dark.rawValue
    @AppStorage("enable_pos_sound_effects") private var enablePOSSoundEffects = true
    @AppStorage("pos_sound_volume") private var posSoundVolume = 1.0
    @AppStorage("app_text_size") private var appTextSize = AppTextSize.system.rawValue

    private let barFont = Font.subheadline

    var body: some View {
        ZStack {
            Color.clear

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if !embedded {
                        Text(L.Sections.appearance.t)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .tracking(0.4)
                    }

                    VStack(spacing: 0) {
                        Toggle(isOn: Binding(
                            get: { appTheme == AppTheme.dark.rawValue },
                            set: { isDark in selectTheme(isDark ? .dark : .light) }
                        )) {
                            Text("dark_mode".t)
                                .font(barFont)
                                .foregroundStyle(.primary)
                        }
                        .tint(Color(hex: "8E8E93"))
                        .disabled(appTheme == AppTheme.system.rawValue)
                        .opacity(appTheme == AppTheme.system.rawValue ? 0.5 : 1.0)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(minHeight: 40)

                        Divider().opacity(0.35).padding(.leading, 14)

                        Toggle(isOn: Binding(
                            get: { appTheme == AppTheme.system.rawValue },
                            set: { useSystem in selectTheme(useSystem ? .system : (appTheme == AppTheme.light.rawValue ? .light : .dark)) }
                        )) {
                            Text("match_system_theme".t)
                                .font(barFont)
                                .foregroundStyle(.primary)
                        }
                        .tint(Color(hex: "8E8E93"))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(minHeight: 40)
                    }
                    .background(Color.primary.opacity(embedded ? 0.03 : 0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                    )

                    Text(LocalizationManager.shared.currentLanguage == .thai ? "ขนาดตัวอักษร (Text Size)" : "Text Size")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.4)
                        .padding(.top, 10)

                    VStack(alignment: .leading, spacing: 8) {
                        Picker(
                            LocalizationManager.shared.currentLanguage == .thai ? "ขนาดตัวอักษร" : "Text Size",
                            selection: $appTextSize
                        ) {
                            ForEach(AppTextSize.allCases) { size in
                                Text(size.localizedName).tag(size.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                        .font(.body)

                        Text(LocalizationManager.shared.currentLanguage == .thai
                             ? "ใช้ฟอนต์ระบบของ iOS/iPadOS และปรับขนาดตาม Dynamic Type โดยไม่ใช้ฟอนต์กำหนดเอง"
                             : "Uses the iOS/iPadOS system font and Dynamic Type without a custom font.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.primary.opacity(embedded ? 0.03 : 0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                    )

                    // ── Sound & Feedback ─────────────────────────────────
                    Text(LocalizationManager.shared.currentLanguage == .thai ? "เสียงและการตอบสนอง (Sound & Haptics)" : "Sound & Feedback")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.4)
                        .padding(.top, 10)

                    VStack(spacing: 0) {
                        Toggle(isOn: $enablePOSSoundEffects) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(LocalizationManager.shared.currentLanguage == .thai ? "เสียงประกอบ POS (Sound Effects)" : "POS Sound Effects")
                                    .font(barFont)
                                    .foregroundStyle(.primary)
                                Text(LocalizationManager.shared.currentLanguage == .thai ? "ส่งเสียงบี๊บเมื่อกดเลือกสินค้า และเสียงแคชเชียร์ Cha-Ching เมื่อรับชำระเงินสำเร็จ" : "Play beep when selecting items and cash register Cha-Ching when payment succeeds")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tint(Color.appAccent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(minHeight: 44)

                        if enablePOSSoundEffects {
                            Divider().opacity(0.35).padding(.leading, 14)

                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(LocalizationManager.shared.currentLanguage == .thai ? "ระดับความดังเสียง (Volume)" : "Volume")
                                        .font(barFont)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text("\(Int(posSoundVolume * 100))%")
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                        .foregroundStyle(Color.appAccent)
                                }

                                Slider(value: $posSoundVolume, in: 0.1...1.0, step: 0.05)
                                    .tint(Color.appAccent)
                                    .onChange(of: posSoundVolume) { _, _ in
                                        APSoundEffect.itemTap()
                                    }

                                HStack(spacing: 10) {
                                    Button {
                                        APSoundEffect.itemTap()
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "speaker.wave.2.fill")
                                                .font(.system(size: 11))
                                            Text(LocalizationManager.shared.currentLanguage == .thai ? "ทดสอบเสียงบี๊บ (Beep)" : "Test Beep")
                                                .font(.system(size: 11, weight: .medium))
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color.appAccent.opacity(0.12), in: Capsule())
                                        .foregroundColor(.appAccent)
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        APSoundEffect.paymentSuccess()
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "dollarsign.circle.fill")
                                                .font(.system(size: 11))
                                            Text(LocalizationManager.shared.currentLanguage == .thai ? "ทดสอบเสียงแคชเชียร์ (Cha-Ching 🪙)" : "Test Cha-Ching")
                                                .font(.system(size: 11, weight: .medium))
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color.appTeal.opacity(0.12), in: Capsule())
                                        .foregroundColor(.appTeal)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.top, 4)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        }
                    }
                    .background(Color.primary.opacity(embedded ? 0.03 : 0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                    )
                }
                .padding(14)
            }
        }
        .navigationTitle(embedded ? "" : L.Sections.appearance.t)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(embedded ? .hidden : .automatic, for: .navigationBar)
        .apNavBar(background: Color.clear)
        .apColorScheme()
    }

    private func selectTheme(_ theme: AppTheme) {
        withAnimation(.easeInOut(duration: 0.25)) {
            appTheme = theme.rawValue
            UserDefaults.standard.set(theme.rawValue, forKey: "app_theme")
        }
        APHaptic.trigger()
    }
}

#Preview {
    NavigationStack {
        AppearanceSettingsView()
    }
}
