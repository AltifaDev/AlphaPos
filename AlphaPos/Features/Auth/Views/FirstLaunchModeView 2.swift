// FirstLaunchModeView.swift
// AlphaPos — ถามผู้ใช้ครั้งแรกว่าต้องการใช้งานแบบออฟไลน์หรือออนไลน์
// แสดงครั้งเดียวตอน install ใหม่ — หลังจากนี้จะข้ามไปหน้า Login โดยตรง

import SwiftUI

struct FirstLaunchModeView: View {
    /// Callback เมื่อผู้ใช้เลือก mode แล้ว — AppRootView จะ navigate ไป MerchantAuthView
    var onModeSelected: (_ isOffline: Bool) -> Void

    @State private var selectedMode: UsageMode? = nil
    @State private var showConfirmation = false

    enum UsageMode: String, CaseIterable {
        case online  = "online"
        case offline = "offline"

        var title: String {
            switch self {
            case .online:  return "ออนไลน์"
            case .offline: return "ออฟไลน์"
            }
        }
        var subtitle: String {
            switch self {
            case .online:  return "ซิงค์ข้อมูลหลายเครื่อง รายงานแบบเรียลไทม์"
            case .offline: return "ใช้งานบนเครื่องเดียว ไม่ต้องอินเทอร์เน็ต"
            }
        }
        var icon: String {
            switch self {
            case .online:  return "cloud.fill"
            case .offline: return "ipad"
            }
        }
        var color: Color {
            switch self {
            case .online:  return .appTeal
            case .offline: return Color(hex: "6366F1")
            }
        }
        var features: [String] {
            switch self {
            case .online:
                return [
                    "ซิงค์ข้อมูลระหว่างหลาย iPad",
                    "รายงานและสถิติแบบเรียลไทม์",
                    "รับออเดอร์จากลูกค้าผ่าน QR Code",
                    "สำรองข้อมูลอัตโนมัติบน Cloud",
                    "อัปเดต menu จากระยะไกลได้",
                ]
            case .offline:
                return [
                    "ใช้งานได้แม้ไม่มีอินเทอร์เน็ต",
                    "ข้อมูลเก็บบน iPad เครื่องนี้เท่านั้น",
                    "เร็วกว่า — ไม่รอ sync",
                    "เหมาะสำหรับร้านเครื่องเดียว",
                ]
            }
        }
    }

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Header ──────────────────────────────────────────────────
                VStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(APGradient.accent)
                            .frame(width: 64, height: 64)
                            .shadow(color: Color.appAccent.opacity(0.4), radius: 12, y: 4)
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 28, weight: .black))
                            .foregroundColor(.white)
                    }
                    .padding(.top, 48)

                    Text("ยินดีต้อนรับสู่ AlphaPos")
                        .font(.title.bold())
                        .foregroundColor(.textPrimary)

                    Text("เลือกรูปแบบการใช้งานที่เหมาะกับร้านของคุณ")
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)

                // ── Mode Cards ───────────────────────────────────────────────
                HStack(spacing: 20) {
                    ForEach(UsageMode.allCases, id: \.rawValue) { mode in
                        modeCard(mode)
                    }
                }
                .padding(.horizontal, 32)

                // ── Notice: Login ต้องออนไลน์ ──────────────────────────────
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.appAccent)
                        .font(.footnote)
                    Text("ไม่ว่าจะเลือกโหมดใด การล็อกอินครั้งแรกต้องเชื่อมต่ออินเทอร์เน็ตเสมอ เพื่อยืนยันสิทธิ์การใช้งาน")
                        .font(.footnote)
                        .foregroundColor(.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 32)
                .padding(.top, 20)

                Spacer()

                // ── Continue Button ─────────────────────────────────────────
                Button {
                    guard let mode = selectedMode else { return }
                    showConfirmation = true
                    _ = mode
                } label: {
                    HStack {
                        Text("ดำเนินการต่อ")
                            .fontWeight(.semibold)
                        Image(systemName: "arrow.right")
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        selectedMode != nil
                            ? (selectedMode == .online ? Color.appTeal : Color(hex: "6366F1"))
                            : Color.appDivider
                    )
                    .foregroundColor(selectedMode != nil ? .white : .textSecondary)
                    .cornerRadius(14)
                }
                .disabled(selectedMode == nil)
                .padding(.horizontal, 32)
                .padding(.bottom, 48)
                .animation(.easeInOut(duration: 0.2), value: selectedMode)
            }
        }
        .confirmationDialog(
            selectedMode == .offline
                ? "ยืนยันการใช้งานออฟไลน์"
                : "ยืนยันการใช้งานออนไลน์",
            isPresented: $showConfirmation,
            titleVisibility: .visible
        ) {
            Button("ยืนยัน — ไปหน้าล็อกอิน") {
                let isOffline = selectedMode == .offline
                // บันทึก preference
                UserDefaults.standard.set(isOffline, forKey: "offline_sync_mode")
                UserDefaults.standard.set(true, forKey: "offline_mode_user_set")
                UserDefaults.standard.set(true, forKey: "has_completed_first_launch")
                onModeSelected(isOffline)
            }
            Button("ยกเลิก", role: .cancel) {}
        } message: {
            Text(selectedMode == .offline
                 ? "ข้อมูลจะเก็บบน iPad เครื่องนี้เท่านั้น คุณยังสามารถเปลี่ยนเป็นออนไลน์ได้ในภายหลัง"
                 : "ข้อมูลจะซิงค์กับ Cloud อัตโนมัติ คุณยังสามารถเปลี่ยนเป็นออฟไลน์ได้ในภายหลัง")
        }
    }

    // MARK: - Mode Card

    private func modeCard(_ mode: UsageMode) -> some View {
        let isSelected = selectedMode == mode
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedMode = mode
            }
        } label: {
            VStack(alignment: .leading, spacing: 16) {
                // Icon + Title
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(mode.color.opacity(isSelected ? 1 : 0.12))
                            .frame(width: 44, height: 44)
                        Image(systemName: mode.icon)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(isSelected ? .white : mode.color)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("โหมด\(mode.title)")
                            .font(.headline)
                            .foregroundColor(.textPrimary)
                        Text(mode.subtitle)
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                    }
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(mode.color)
                            .font(.title3)
                    }
                }

                Divider()

                // Features
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(mode.features, id: \.self) { feature in
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark")
                                .font(.caption.bold())
                                .foregroundColor(mode.color)
                            Text(feature)
                                .font(.subheadline)
                                .foregroundColor(.textPrimary)
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.appSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? mode.color : Color.appDivider, lineWidth: isSelected ? 2 : 1)
            )
            .shadow(
                color: isSelected ? mode.color.opacity(0.15) : .black.opacity(0.04),
                radius: isSelected ? 12 : 4, y: 2
            )
        }
        .buttonStyle(.plain)
    }
}
