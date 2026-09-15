
// SubscriptionSettingsView.swift
// AlphaPos — หน้าจอจัดการและอัปเดตแพ็กเกจราคา

import SwiftData
import SwiftUI

struct SubscriptionSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var lm: LocalizationManager

    @AppStorage("active_merchant_id") private var activeMerchantId = ""
    @AppStorage("store_name") private var storeName = ""

    // Form / Selection State
    @State private var selectedPlanId: String = "online_subscription"
    @State private var isAnnualBilling: Bool = false
    @State private var errorMessage: String = ""
    @State private var successMessage: String = ""
    @State private var isLoading: Bool = false
    @State private var isRestoring: Bool = false

    // Current Merchant Subscription State
    @State private var currentTier: String = "offline_perpetual"
    @State private var currentStatus: String = "trial"
    @State private var currentExpiryString: String = ""
    @State private var remainingTrialDays: Int? = nil

    // In-App Payment State
    @State private var paymentURL: URL? = nil
    @State private var showSafariPayment: Bool = false

    // Staggered entry animation
    @State private var appeared: Bool = false

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    // Header Status Card
                    currentStatusHeroCard
                        .modifier(entryEffect(0))

                    // Title & Billing Switch
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("subscription_settings_headline".t)
                                .font(.system(size: 26, weight: .bold))
                                .foregroundColor(.white)
                            Text("subscription_settings_subheadline".t)
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.65))
                        }
                        Spacer()
                        HStack(spacing: 0) {
                            Text("subscription_billing_monthly".t)
                                .pricingToggle(selected: !isAnnualBilling)
                                .onTapGesture { isAnnualBilling = false }
                            Text("subscription_billing_annual".t)
                                .pricingToggle(selected: isAnnualBilling)
                                .onTapGesture { isAnnualBilling = true }
                        }
                        .padding(4)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .modifier(entryEffect(1))

                    // Plan Cards Grid
                    HStack(alignment: .top, spacing: 14) {
                        planCard(
                            id: "offline_perpetual",
                            title: "ออฟไลน์ ซื้อขาด",
                            subtitle: "ใช้งาน 1 เครื่องตลอดชีพ ไม่มีรายเดือน",
                            badge: "จ่ายครั้งเดียว",
                            price: "฿9,900",
                            priceLabel: "จ่ายครั้งเดียว",
                            features: [
                                "ใช้งานถาวรระดับเครื่องแม่ (Master POS)",
                                "ไม่ต้องใช้อินเทอร์เน็ตในการขาย",
                                "สำรองและกู้คืนข้อมูลแบบ Manual",
                                "จำกัดเฉพาะฟีเจอร์ในเวอร์ชันปัจจุบัน"
                            ],
                            color: Color(hex: "6366F1"),
                            imageName: "SubscriptionFabricBlue"
                        )

                        planCard(
                            id: "offline_subscription",
                            title: isAnnualBilling ? "ออฟไลน์ รายปี" : "ออฟไลน์ รายเดือน",
                            subtitle: "ใช้งาน 1 เครื่อง พร้อมอัปเดตฟรีตลอดสัญญา",
                            badge: isAnnualBilling ? "ประหยัด ฿696" : "ยืดหยุ่น",
                            price: isAnnualBilling ? "฿2,784" : "฿290",
                            priceLabel: isAnnualBilling ? "/ปี" : "/เดือน",
                            features: [
                                "ใช้งานออฟไลน์ 1 เครื่องแม่",
                                "อัปเดตฟีเจอร์ใหม่และเวอร์ชันล่าสุดฟรี",
                                "ระบบจัดการสิทธิ์พนักงานและกะการทำงาน",
                                "บริการช่วยเหลือด้านเทคนิค 24/7"
                            ],
                            color: Color(hex: "C63DCE"),
                            imageName: "SubscriptionFabricPurple"
                        )

                        planCard(
                            id: "online_subscription",
                            title: isAnnualBilling ? "ออนไลน์ รายปี" : "ออนไลน์ รายเดือน",
                            subtitle: "ซิงค์หลายเครื่อง คลาวด์แดชบอร์ด ออเดอร์ QR",
                            badge: "⭐ ยอดนิยม",
                            price: isAnnualBilling ? "฿11,424" : "฿1,190",
                            priceLabel: isAnnualBilling ? "/ปี" : "/เดือน",
                            features: [
                                "ซิงค์ข้อมูล Real-time หลาย iPad/iPhone",
                                "ระบบลูกค้าสแกน QR Code สั่งอาหาร",
                                "สำรองข้อมูลอัตโนมัติบนระบบ Cloud",
                                "แดชบอร์ดวิเคราะห์ยอดขาย Real-time"
                            ],
                            color: Color(hex: "3BAF9A"),
                            imageName: "SubscriptionFabricGreen"
                        )
                    }
                    .modifier(entryEffect(2))

                    // Notifications / Alert Banners
                    if !errorMessage.isEmpty {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(Color(hex: "FF453A"))
                            Text(errorMessage)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                            Spacer()
                        }
                        .padding(14)
                        .background(Color(hex: "FF453A").opacity(0.18))
                        .cornerRadius(12)
                    }

                    if !successMessage.isEmpty {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(Color(hex: "34D399"))
                            Text(successMessage)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                            Spacer()
                        }
                        .padding(14)
                        .background(Color(hex: "34D399").opacity(0.18))
                        .cornerRadius(12)
                    }

                    // Bottom Primary Action Bar
                    bottomActionBar
                        .modifier(entryEffect(3))
                }
                .padding(20)
            }
        }
        .preferredColorScheme(.dark)
        .navigationTitle("subscription_settings_title".t)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white.opacity(0.8))
                        .padding(8)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showSafariPayment) {
            if let paymentURL {
                SafariView(url: paymentURL) {
                    refreshSubscriptionStatus()
                }
                .ignoresSafeArea()
            }
        }
        .onAppear(perform: loadSubscriptionDetails)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) {
                appeared = true
            }
        }
    }

    // MARK: - Current Status Hero Card

    @ViewBuilder
    private var currentStatusHeroCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(storeName.isEmpty ? "AlphaPos Store" : storeName)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)

                    HStack(spacing: 8) {
                        Image(systemName: statusIconName)
                            .foregroundColor(statusAccentColor)
                        Text(statusDescriptionText)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                    }
                }

                Spacer()

                // Status Badge
                Text(statusBadgeText)
                    .font(.system(size: 12, weight: .bold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(statusAccentColor.opacity(0.2))
                    .foregroundColor(statusAccentColor)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(statusAccentColor.opacity(0.4), lineWidth: 1)
                    )
            }

            Divider().overlay(Color.white.opacity(0.1))

            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "34D399"))
                Text("subscription_data_safe_notice".t)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.65))
                Spacer()
                Button {
                    refreshSubscriptionStatus()
                } label: {
                    HStack(spacing: 4) {
                        if isRestoring {
                            ProgressView()
                                .scaleEffect(0.7)
                                .tint(.white)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10, weight: .bold))
                        }
                        Text("subscription_btn_restore".t)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(hex: "171722").opacity(0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(statusAccentColor.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Plan Card Helper

    private func planCard(
        id: String,
        title: String,
        subtitle: String,
        badge: String,
        price: String,
        priceLabel: String,
        features: [String],
        color: Color,
        imageName: String
    ) -> some View {
        let isSelected = selectedPlanId == id
        let isCurrent = currentTier == id && currentStatus == "active"

        return Button(action: {
            selectedPlanId = id
        }) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    Image(imageName)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 130)
                        .frame(maxWidth: .infinity)
                        .clipped()

                    if isCurrent {
                        Text("แพ็กเกจปัจจุบัน")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.black.opacity(0.65))
                            .clipShape(Capsule())
                            .padding(10)
                    } else if !badge.isEmpty {
                        Text(badge)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(color.opacity(0.85))
                            .clipShape(Capsule())
                            .padding(10)
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.65))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(price)
                            .font(.system(size: 30, weight: .bold))
                            .foregroundColor(.white)
                        Text(priceLabel)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.55))
                    }

                    // Card selection indicator button
                    HStack {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.white)
                        }
                        Text(isSelected ? "เลือกแพ็กเกจนี้อยู่" : "แตะเพื่อเลือก")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(isSelected ? color : Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    Divider().overlay(Color.white.opacity(0.12))

                    Text("รายละเอียดแพ็กเกจ")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))

                    ForEach(features, id: \.self) { feat in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(color)
                                .padding(.top, 2)
                            Text(feat)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.75))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(16)
            }
            .background(
                LinearGradient(
                    colors: [color.opacity(0.22), Color(hex: "111118")],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? color : Color.white.opacity(0.08), lineWidth: isSelected ? 2 : 1)
            )
            .shadow(color: isSelected ? color.opacity(0.25) : Color.clear, radius: 12, y: 4)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSelected)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bottom Primary Action Bar

    @ViewBuilder
    private var bottomActionBar: some View {
        let isCurrentPlanActive = currentTier == selectedPlanId && currentStatus == "active"

        VStack(spacing: 12) {
            Button {
                if !isCurrentPlanActive {
                    handleUpdatePlan()
                }
            } label: {
                HStack(spacing: 8) {
                    if isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: isCurrentPlanActive ? "checkmark.circle.fill" : "creditcard.fill")
                            .font(.system(size: 15, weight: .bold))
                    }

                    Text(isCurrentPlanActive ? "subscription_btn_current_plan".t : checkoutButtonTitle)
                        .font(.system(size: 16, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    isCurrentPlanActive
                        ? Color.white.opacity(0.12)
                        : Color(hex: "2D71F8")
                )
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: isCurrentPlanActive ? .clear : Color(hex: "2D71F8").opacity(0.4), radius: 12, y: 4)
            }
            .disabled(isLoading || isCurrentPlanActive)
            .buttonStyle(.plain)

            Text("subscription_support_contact".t)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.45))
        }
        .padding(.top, 10)
    }

    // MARK: - Computed Properties for Status

    private var statusAccentColor: Color {
        if currentStatus == "trial" {
            if let days = remainingTrialDays, days <= 0 {
                return Color(hex: "FF453A")
            } else if let days = remainingTrialDays, days <= 3 {
                return Color(hex: "FF9F0A")
            }
            return Color(hex: "34D399")
        } else if currentStatus == "active" {
            return Color(hex: "2D71F8")
        } else {
            return Color(hex: "FF9F0A")
        }
    }

    private var statusIconName: String {
        if currentStatus == "trial" {
            if let days = remainingTrialDays, days <= 0 {
                return "exclamationmark.circle.fill"
            }
            return "gift.fill"
        } else if currentStatus == "active" {
            return "checkmark.seal.fill"
        } else {
            return "clock.badge.exclamationmark.fill"
        }
    }

    private var statusBadgeText: String {
        if currentStatus == "trial" {
            if let days = remainingTrialDays, days <= 0 {
                return "subscription_status_trial_expired".t
            } else if let days = remainingTrialDays {
                return String(format: "subscription_status_trial_active".t, days)
            }
            return "ทดลองใช้ฟรี"
        } else if currentStatus == "active" {
            return "subscription_status_active".t
        } else {
            return "รอการชำระเงิน"
        }
    }

    private var statusDescriptionText: String {
        if currentStatus == "trial" {
            if let days = remainingTrialDays, days <= 0 {
                return "ระยะเวลาทดลองใช้ 10 วันสิ้นสุดแล้ว — กรุณาเลือกแพ็กเกจเพื่อเปิดใช้งานต่อ"
            } else {
                return "ใช้งานได้ครบทุกฟีเจอร์ สิ้นสุดวันที่: \(currentExpiryString)"
            }
        } else if currentStatus == "active" {
            return "แพ็กเกจปัจจุบัน: \(getPlanDisplayName(currentTier)) (หมดอายุ/ต่ออายุ: \(currentExpiryString))"
        } else {
            return "สถานะบัญชีกำลังรอการยืนยันการชำระเงิน"
        }
    }

    private var checkoutButtonTitle: String {
        switch selectedPlanId {
        case "offline_perpetual":
            return "subscription_btn_checkout".t + " (฿9,900)"
        case "offline_subscription":
            let price = isAnnualBilling ? "฿2,784 / ปี" : "฿290 / เดือน"
            return "subscription_btn_checkout".t + " (\(price))"
        case "online_subscription":
            let price = isAnnualBilling ? "฿11,424 / ปี" : "฿1,190 / เดือน"
            return "subscription_btn_checkout".t + " (\(price))"
        default:
            return "subscription_btn_checkout".t
        }
    }

    // MARK: - Logic & Actions

    private func getPlanDisplayName(_ tier: String) -> String {
        switch tier {
        case "offline_perpetual": return "ออฟไลน์ ซื้อขาด"
        case "offline_subscription": return "ออฟไลน์ รายเดือน/รายปี"
        case "online_subscription": return "ออนไลน์ คลาวด์"
        default: return "ออนไลน์ คลาวด์"
        }
    }

    private func loadSubscriptionDetails() {
        let fallbackTier = UserDefaults.standard.bool(forKey: "offline_sync_mode") ? "offline_perpetual" : "online_subscription"
        let tier = MerchantAuthManager.shared.subscriptionTier ?? fallbackTier
        let status = MerchantAuthManager.shared.subscriptionStatus ?? "trial"
        let expiryVal = MerchantAuthManager.shared.subscriptionExpiry

        currentTier = tier
        currentStatus = status
        selectedPlanId = tier

        if let expiryVal = expiryVal {
            let remaining = expiryVal - Date().timeIntervalSince1970
            remainingTrialDays = max(0, Int(ceil(remaining / 86400.0)))

            let df = DateFormatter()
            df.locale = Locale(identifier: "th_TH")
            df.dateFormat = "d MMMM yyyy"
            currentExpiryString = df.string(from: Date(timeIntervalSince1970: expiryVal))
        } else {
            remainingTrialDays = nil
            currentExpiryString = tier == "offline_perpetual" ? "ไม่มีวันหมดอายุ (ถาวร)" : "ถาวร"
        }
    }

    private func refreshSubscriptionStatus() {
        isRestoring = true
        errorMessage = ""
        successMessage = ""

        Task {
            do {
                guard let merchantIdString = MerchantAuthManager.shared.merchantId ?? UserDefaults.standard.string(forKey: "active_merchant_id"),
                      let merchantUUID = UUID(uuidString: merchantIdString) else {
                    await MainActor.run {
                        isRestoring = false
                        loadSubscriptionDetails()
                    }
                    return
                }

                let settings = try await NetworkManager.shared.fetchMerchantSettings(merchantId: merchantUUID)
                await MainActor.run {
                    isRestoring = false
                    if let settings = settings {
                        let tier = (settings["subscription_tier"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? currentTier
                        let status = (settings["subscription_status"] as? String) ?? currentStatus
                        let expiryDate = (settings["subscription_expires_at"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
                        let expiryTimestamp = expiryDate?.timeIntervalSince1970

                        MerchantAuthManager.shared.saveSubscription(tier: tier, status: status, expiry: expiryTimestamp)
                        loadSubscriptionDetails()
                        if status == "active" {
                            successMessage = "subscription_payment_success".t
                        }
                    } else {
                        loadSubscriptionDetails()
                    }
                }
            } catch {
                await MainActor.run {
                    isRestoring = false
                    loadSubscriptionDetails()
                }
            }
        }
    }

    private func handleUpdatePlan() {
        isLoading = true
        errorMessage = ""
        successMessage = ""

        Task {
            do {
                let tier = selectedPlanId
                guard await NetworkManager.shared.isConnected() else { throw NetworkError.offline }
                let cycle = tier == "offline_perpetual" ? "perpetual" : (isAnnualBilling ? "annual" : "monthly")
                let approvalURL = try await NetworkManager.shared.createSubscriptionPayment(tier: tier, billingCycle: cycle)

                await MainActor.run {
                    isLoading = false
                    paymentURL = approvalURL
                    showSafariPayment = true
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = "ไม่สามารถเริ่มชำระเงินได้ กรุณาตรวจสอบการเชื่อมต่ออินเทอร์เน็ตแล้วลองอีกครั้ง"
                }
            }
        }
    }

    private func entryEffect(_ index: Int) -> EntryEffect {
        EntryEffect(appeared: appeared, index: index)
    }
}

// MARK: - Entry Effect (staggered fade + rise)

private struct EntryEffect: ViewModifier {
    let appeared: Bool
    let index: Int

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 18)
            .animation(
                .spring(response: 0.55, dampingFraction: 0.85)
                    .delay(Double(index) * 0.08),
                value: appeared
            )
    }
}

private extension View {
    func pricingToggle(selected: Bool) -> some View {
        self
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.white.opacity(selected ? 1 : 0.55))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(selected ? Color(hex: "2D71F8") : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
