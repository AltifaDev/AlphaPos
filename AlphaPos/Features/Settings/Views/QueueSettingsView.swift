import SwiftUI

struct QueueSettingsView: View {
    @AppStorage("enable_queue_reset_limit") private var enableQueueResetLimit = false
    @AppStorage("queue_reset_max_count") private var queueResetMaxCount = 20
    @AppStorage("active_merchant_id") private var activeMerchantId = ""

    @State private var showingResetAlert = false
    @State private var showingResetSuccessToast = false
    @State private var customLimitText = "20"

    private let presetLimits: [Int] = [10, 20, 30, 40, 50, 100]

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    queueLimitSection
                    simulationPreviewSection
                    manualResetSection
                }
                .padding(.vertical)
            }
        }
        .navigationTitle("section_queue_system".t)
        .navigationBarTitleDisplayMode(.inline)
        .apNavBar(background: Color.appBackground)
        .onAppear {
            customLimitText = "\(queueResetMaxCount)"
        }
        .alert("ยืนยันการรีเซ็ตคิว", isPresented: $showingResetAlert) {
            Button("ยกเลิก", role: .cancel) { }
            Button("รีเซ็ตเป็นคิวที่ 001", role: .destructive) {
                NetworkManager.resetDailyQueueSequence(merchantId: activeMerchantId)
                APHaptic.trigger()
                showingResetSuccessToast = true
            }
        } message: {
            Text("ระบบจะเริ่มรันหมายเลขคิวถัดไปที่ 001 สำหรับออเดอร์ใหม่")
        }
        .alert("รีเซ็ตคิวสำเร็จ", isPresented: $showingResetSuccessToast) {
            Button("ตกลง", role: .cancel) { }
        } message: {
            Text("หมายเลขคิวถัดไปจะเริ่มต้นที่ 001 เรียบร้อยแล้ว")
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var queueLimitSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("section_queue_system".t)
                .font(.system(size: 12))
                .fontWeight(.bold)
                .foregroundColor(.appAccent)
                .tracking(1.0)

            VStack(spacing: 16) {
                Toggle(isOn: $enableQueueResetLimit) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("จำกัดและรีเซ็ตหมายเลขคิวอัตโนมัติ")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.textPrimary)
                        Text("เมื่อรันหมายเลขคิวถึงจำนวนที่กำหนด ระบบจะวนกลับไปเริ่มต้นที่ 001 ใหม่โดยอัตโนมัติ")
                            .font(.system(size: 12))
                            .foregroundColor(.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(.appAccent)
                .onChange(of: enableQueueResetLimit) {
                    APHaptic.trigger()
                }

                if enableQueueResetLimit {
                    Divider().background(Color.appDivider)
                    queueLimitConfigControls
                }
            }
            .apCard()
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var queueLimitConfigControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("จำนวนคิวสูงสุดต่อรอบ")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.textPrimary)
                Spacer()
                Text("\(queueResetMaxCount) คิว")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.appAccent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.appAccent.opacity(0.12), in: Capsule())
            }

            presetButtonsRow
            stepperAndCustomInputRow
        }
    }

    @ViewBuilder
    private var presetButtonsRow: some View {
        HStack(spacing: 8) {
            ForEach(presetLimits, id: \.self) { limit in
                let isSelected = queueResetMaxCount == limit
                Button {
                    onPresetSelected(limit)
                } label: {
                    Text("\(limit)")
                        .font(.system(size: 13, weight: isSelected ? .bold : .medium, design: .rounded))
                        .foregroundColor(isSelected ? .white : .textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            isSelected ? Color.appAccent : Color.primary.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var stepperAndCustomInputRow: some View {
        HStack(spacing: 12) {
            Stepper("", value: $queueResetMaxCount, in: 5...999, step: 5)
                .labelsHidden()
                .onChange(of: queueResetMaxCount) {
                    customLimitText = "\(queueResetMaxCount)"
                    APHaptic.trigger()
                }

            Text("หรือระบุจำนวนเอง:")
                .font(.system(size: 12))
                .foregroundColor(.textSecondary)

            TextField("20", text: $customLimitText)
                .keyboardType(.numberPad)
                .textFieldStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(width: 70)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                .multilineTextAlignment(.center)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .onChange(of: customLimitText) {
                    handleCustomLimitChange()
                }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private var simulationPreviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ตัวอย่างการทำงาน (Simulation Preview)")
                .font(.system(size: 12))
                .fontWeight(.bold)
                .foregroundColor(.appAccent)
                .tracking(1.0)

            VStack(alignment: .leading, spacing: 14) {
                Text("ลำดับหมายเลขคิวที่จะแสดงบนหน้าจอและใบเสร็จ:")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.textSecondary)

                simulationBadgeRow

                Divider().background(Color.appDivider)

                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.appAccent)
                    Text(enableQueueResetLimit
                         ? "เมื่อถึงคิวที่ \(queueResetMaxCount) แล้ว คิวถัดไปจะเริ่มที่ 001 โดยอัตโนมัติ"
                         : "รันลำดับคิวต่อเนื่องไปเรื่อยๆ ตามมาตรฐานสากล (001, 002, 003...)")
                        .font(.system(size: 12))
                        .foregroundColor(.textSecondary)
                }
            }
            .apCard()
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var simulationBadgeRow: some View {
        HStack(spacing: 6) {
            previewBadge("001", isStart: true)
            arrowIcon
            previewBadge("002")
            arrowIcon
            Text("...")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.textTertiary)
            arrowIcon

            if enableQueueResetLimit {
                let limitStr = String(format: "%03d", max(1, queueResetMaxCount))
                previewBadge(limitStr, isLimit: true)
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.appAccent)
                previewBadge("001", isReset: true)
            } else {
                previewBadge("099")
                arrowIcon
                previewBadge("100")
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 8)
    }

    private var arrowIcon: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.textTertiary)
    }

    @ViewBuilder
    private var manualResetSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("การจัดการลำดับคิว")
                .font(.system(size: 12))
                .fontWeight(.bold)
                .foregroundColor(.appAccent)
                .tracking(1.0)

            VStack(spacing: 12) {
                Button {
                    showingResetAlert = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.counterclockwise.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.appRose)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("รีเซ็ตลำดับคิวของวันนี้กลับไปเริ่มต้นที่ 001")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.appRose)
                            Text("ใช้เมื่อต้องการเริ่มต้นนับคิวใหม่ทันที")
                                .font(.system(size: 11))
                                .foregroundColor(.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.appRose.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .apCard()
        }
        .padding(.horizontal)
    }

    // MARK: - Helpers

    private func onPresetSelected(_ limit: Int) {
        APHaptic.trigger()
        queueResetMaxCount = limit
        customLimitText = "\(limit)"
    }

    private func handleCustomLimitChange() {
        if let val = Int(customLimitText), val >= 1, val <= 999 {
            queueResetMaxCount = val
        }
    }

    private func previewBadge(_ text: String, isStart: Bool = false, isLimit: Bool = false, isReset: Bool = false) -> some View {
        let badgeColor: Color = isReset ? .appAccent : (isLimit ? .orange : .textPrimary)
        let bgColor: Color = isReset ? Color.appAccent.opacity(0.18) : (isLimit ? Color.orange.opacity(0.18) : Color.primary.opacity(0.06))
        let strokeColor: Color = isReset ? Color.appAccent.opacity(0.4) : (isLimit ? Color.orange.opacity(0.4) : Color.clear)

        return Text(text)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundColor(badgeColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(bgColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(strokeColor, lineWidth: 1)
            )
    }
}
