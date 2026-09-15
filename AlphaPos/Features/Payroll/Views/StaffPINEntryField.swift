import SwiftUI

/// PIN editor that never exposes a text input surface. Digits can only be
/// entered through the in-app number pad, preventing letters, paste and AutoFill.
struct StaffPINEntryField: View {
    @Binding var pin: String
    let hasExistingPIN: Bool
    let language: String

    @State private var isPresentingKeypad = false

    private var isThai: Bool { language == "th" }

    var body: some View {
        Button {
            isPresentingKeypad = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "number.square.fill")
                    .foregroundStyle(Color.appAccent)

                VStack(alignment: .leading, spacing: 3) {
                    Text(isThai ? "รหัส PIN สำหรับเข้าสู่ระบบ" : "Login PIN")
                        .foregroundStyle(Color.textPrimary)
                    Text(detailText)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }

                Spacer()

                HStack(spacing: 5) {
                    ForEach(0..<4, id: \.self) { index in
                        Circle()
                            .fill(index < pin.count ? Color.appAccent : Color.textTertiary.opacity(0.28))
                            .frame(width: 9, height: 9)
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isPresentingKeypad) {
            StaffPINNumberPad(
                pin: $pin,
                hasExistingPIN: hasExistingPIN,
                language: language
            )
            .presentationDetents([.height(630), .large])
            .presentationDragIndicator(.visible)
            .interactiveDismissDisabled()
        }
        .accessibilityLabel(isThai ? "แก้ไขรหัส PIN สี่หลัก" : "Edit four-digit PIN")
    }

    private var detailText: String {
        if !pin.isEmpty {
            return isThai ? "กำหนด PIN ใหม่แล้ว \(pin.count) จาก 4 หลัก" : "New PIN: \(pin.count) of 4 digits"
        }
        if hasExistingPIN {
            return isThai ? "แตะเพื่อเปลี่ยน หรือเว้นไว้เพื่อใช้ PIN เดิม" : "Tap to change, or keep the existing PIN"
        }
        return isThai ? "แตะเพื่อกำหนดตัวเลข 4 หลัก" : "Tap to set 4 numeric digits"
    }
}

private struct StaffPINNumberPad: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var pin: String
    let hasExistingPIN: Bool
    let language: String

    @State private var draft: String

    private let rows = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"]]
    private var isThai: Bool { language == "th" }

    init(pin: Binding<String>, hasExistingPIN: Bool, language: String) {
        _pin = pin
        self.hasExistingPIN = hasExistingPIN
        self.language = language
        _draft = State(initialValue: String(pin.wrappedValue.filter(\.isNumber).prefix(4)))
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    VStack(spacing: 6) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(Color.appAccent)
                        Text(isThai ? "กำหนดรหัส PIN ใหม่" : "Set a new PIN")
                            .font(.title3.bold())
                        Text(isThai ? "กรอกตัวเลขให้ครบ 4 หลัก" : "Enter exactly four numeric digits")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .padding(.top, 8)

                    HStack(spacing: 16) {
                        ForEach(0..<4, id: \.self) { index in
                            Circle()
                                .fill(index < draft.count ? Color.appAccent : Color.clear)
                                .frame(width: 16, height: 16)
                                .overlay {
                                    Circle().stroke(Color.appAccent.opacity(0.65), lineWidth: 1.5)
                                }
                        }
                    }
                    .accessibilityLabel(isThai ? "กรอกแล้ว \(draft.count) จาก 4 หลัก" : "\(draft.count) of 4 digits entered")
                    .padding(.vertical, 4)

                    VStack(spacing: 10) {
                        ForEach(rows, id: \.self) { row in
                            HStack(spacing: 14) {
                                ForEach(row, id: \.self) { digit in
                                    digitButton(digit)
                                }
                            }
                        }

                        HStack(spacing: 14) {
                            Button {
                                draft = ""
                                APHaptic.trigger()
                            } label: {
                                keypadCell(systemImage: "clear.fill")
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(isThai ? "ล้างทั้งหมด" : "Clear")

                            digitButton("0")

                            Button {
                                guard !draft.isEmpty else { return }
                                draft.removeLast()
                                APHaptic.trigger()
                            } label: {
                                keypadCell(systemImage: "delete.left.fill")
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(isThai ? "ลบตัวเลข" : "Delete digit")
                        }
                    }
                    .frame(maxWidth: 300)

                    Button {
                        pin = draft
                        dismiss()
                    } label: {
                        Text(isThai ? "ยืนยันรหัส PIN (Confirm PIN)" : "Confirm PIN")
                            .font(.headline.weight(.bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(draft.count == 4 ? Color.appAccent : Color.textTertiary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .disabled(draft.count != 4)
                    .frame(maxWidth: 300)
                    .padding(.top, 4)

                    if hasExistingPIN {
                        Button(isThai ? "ใช้ PIN เดิม" : "Keep existing PIN") {
                            pin = ""
                            dismiss()
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.top, 2)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .navigationTitle(isThai ? "แก้ไข PIN" : "Edit PIN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isThai ? "ยกเลิก" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isThai ? "ยืนยัน" : "Done") {
                        pin = draft
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(draft.count != 4)
                }
            }
        }
        .apColorScheme()
    }

    private func digitButton(_ digit: String) -> some View {
        Button {
            guard draft.count < 4 else { return }
            draft.append(contentsOf: digit)
            APHaptic.trigger()
        } label: {
            Text(digit)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.appSurfaceHigh, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(digit)
    }

    private func keypadCell(systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(Color.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color.appSurfaceHigh, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
