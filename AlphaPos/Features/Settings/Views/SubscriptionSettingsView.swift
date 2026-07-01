// SubscriptionSettingsView.swift
// AlphaPos — หน้าจอจัดการและอัปเดตแพ็กเกจราคา

import SwiftUI
import SwiftData

struct SubscriptionSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @AppStorage("active_merchant_id") private var activeMerchantId = "163350b0-056d-4d5e-b5d4-24e7aac5ab6d"
    
    // SwiftUI Form State Checklist Compliance
    @State private var selectedPlanId: String = "offline_perpetual"
    @State private var isAnnualBilling: Bool = false
    @State private var errorMessage: String = ""
    @State private var isLoading: Bool = false
    
    // Fetch initial subscription values
    @State private var currentTier: String = "offline_perpetual"
    @State private var currentStatus: String = "active"
    @State private var currentExpiryString: String = "ถาวร"
    
    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // ── SECTION 1: CURRENT PLAN SUMMARY ────────────────
                    VStack(alignment: .leading, spacing: 12) {
                        Text("แพ็กเกจปัจจุบันของคุณ")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.appAccent)
                            .tracking(1.0)
                        
                        VStack(spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(getPlanDisplayName(currentTier))
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    Text("สิทธิ์การใช้งานสำหรับเครื่อง POS")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.6))
                                }
                                Spacer()
                                
                                // Status badge
                                Text(currentStatus.uppercased() == "ACTIVE" ? "ปกติ" : "หมดอายุ")
                                    .font(.caption2.weight(.bold))
                                    .foregroundColor(currentStatus.uppercased() == "ACTIVE" ? .green : .appRose)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(currentStatus.uppercased() == "ACTIVE" ? Color.green.opacity(0.12) : Color.appRose.opacity(0.12))
                                    .cornerRadius(6)
                            }
                            
                            Divider().background(Color.white.opacity(0.15))
                            
                            HStack {
                                Label("วันหมดอายุสัญญา:", systemImage: "calendar")
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.7))
                                Spacer()
                                Text(currentExpiryString)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.white)
                            }
                        }
                        .padding()
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        )
                    }
                    
                    // ── SECTION 2: CHANGE / UPGRADE PLAN ───────────────
                    VStack(alignment: .leading, spacing: 12) {
                        Text("อัปเดตแพ็กเกจสัญญา")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.appAccent)
                            .tracking(1.0)
                        
                        // Billing Cycle Toggle (Monthly vs Annual)
                        HStack {
                            Text("รายเดือน")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(isAnnualBilling ? .white.opacity(0.6) : .white)
                            
                            Toggle("", isOn: $isAnnualBilling)
                                .toggleStyle(SwitchToggleStyle(tint: Color(hex: "FF9500")))
                                .labelsHidden()
                                .padding(.horizontal, 4)
                            
                            Text("รายปี (ประหยัด 20%)")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(isAnnualBilling ? .white : .white.opacity(0.6))
                        }
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity)
                        
                        // Plan Cards
                        VStack(spacing: 10) {
                            planCard(
                                id: "offline_perpetual",
                                title: "ออฟไลน์ ซื้อขาด",
                                subtitle: "ใช้งาน 1 เครื่องตลอดชีพ ไม่มีรายเดือน",
                                price: "฿9,900",
                                priceLabel: "จ่ายครั้งเดียว",
                                features: ["ใช้งานถาวรระดับเครื่องแม่", "ไม่ต้องใช้อินเทอร์เน็ต", "สำรองข้อมูลแบบ Manual", "จำกัดเฉพาะฟีเจอร์ปัจจุบัน"],
                                color: Color(hex: "6366F1")
                            )
                            
                            planCard(
                                id: "offline_subscription",
                                title: isAnnualBilling ? "ออฟไลน์ รายปี" : "ออฟไลน์ รายเดือน",
                                subtitle: "ใช้งาน 1 เครื่อง พร้อมอัปเดตฟรีตลอดสัญญา",
                                price: isAnnualBilling ? "฿2,990" : "฿290",
                                priceLabel: isAnnualBilling ? "/ปี" : "/เดือน",
                                features: ["ใช้งานออฟไลน์ 1 เครื่องแม่", "อัปเดตฟีเจอร์ใหม่ฟรีในสัญญา", "แก้ไขสิทธิ์ / พนักงาน", "บริการความช่วยเหลือ 24/7"],
                                color: .appTeal
                            )
                            
                            planCard(
                                id: "online_subscription",
                                title: isAnnualBilling ? "ออนไลน์ รายปี" : "ออนไลน์ รายเดือน",
                                subtitle: "ซิงค์หลายเครื่อง คลาวด์แดชบอร์ด ออเดอร์ QR",
                                price: isAnnualBilling ? "฿11,990" : "฿1,190",
                                priceLabel: isAnnualBilling ? "/ปี" : "/เดือน",
                                features: ["ซิงค์ข้อมูลระหว่างหลาย iPad/iPhone", "รับออเดอร์ QR Code จากลูกค้า", "สำรองข้อมูลอัตโนมัติบน Cloud", "สถิติวิเคราะห์ยอดขายแบบ Real-time"],
                                color: Color(hex: "FF9500")
                            )
                        }
                    }
                    
                    if !errorMessage.isEmpty {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(Color(hex: "FF453A"))
                            Text(errorMessage)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                            Spacer()
                        }
                        .padding(12)
                        .background(Color(hex: "FF453A").opacity(0.18))
                        .cornerRadius(12)
                    }
                    
                    // Save Button
                    Button(action: handleUpdatePlan) {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .padding(.trailing, 8)
                            }
                            Text("บันทึกการเปลี่ยนแปลงแพ็กเกจ")
                                .font(.system(size: 14, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            Capsule()
                                .fill(APGradient.positive)
                        )
                        .foregroundColor(.white)
                        .shadow(color: Color.appTeal.opacity(0.3), radius: 8, x: 0, y: 3)
                    }
                    .disabled(isLoading)
                    .padding(.top, 10)
                }
                .padding()
            }
        }
        .navigationTitle("แผนสมาชิกและการเรียกเก็บเงิน")
        .apNavBar(background: Color.appBackground)
        .onAppear(perform: loadSubscriptionDetails)
    }
    
    // MARK: - Plan Card Helper
    
    private func planCard(
        id: String,
        title: String,
        subtitle: String,
        price: String,
        priceLabel: String,
        features: [String],
        color: Color
    ) -> some View {
        let isSelected = selectedPlanId == id
        return Button(action: {
            selectedPlanId = id
        }) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                        Text(subtitle)
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(price)
                            .font(.system(size: 16, weight: .black))
                            .foregroundColor(color)
                        Text(priceLabel)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                
                Divider().background(Color.white.opacity(0.15))
                
                // Mini features
                HStack(spacing: 12) {
                    ForEach(features.prefix(2), id: \.self) { feat in
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 8))
                                .foregroundColor(color)
                            Text(feat)
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.85))
                        }
                    }
                }
            }
            .padding(12)
            .background(Color.white.opacity(isSelected ? 0.12 : 0.04))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? color : Color.white.opacity(0.15), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Helper Logic
    
    private func getPlanDisplayName(_ tier: String) -> String {
        switch tier {
        case "offline_perpetual": return "ออฟไลน์ ซื้อขาด"
        case "offline_subscription": return "ออฟไลน์ รายเดือน/รายปี"
        case "online_subscription": return "ออนไลน์ คลาวด์"
        default: return "ออฟไลน์ ซื้อขาด"
        }
    }
    
    private func loadSubscriptionDetails() {
        let tier = MerchantAuthManager.shared.subscriptionTier ?? "offline_perpetual"
        let status = MerchantAuthManager.shared.subscriptionStatus ?? "active"
        let expiryVal = MerchantAuthManager.shared.subscriptionExpiry
        
        currentTier = tier
        currentStatus = status
        selectedPlanId = tier
        
        if tier == "offline_perpetual" {
            currentExpiryString = "ไม่มีวันหมดอายุ (ถาวร)"
        } else if let expiryVal = expiryVal {
            let df = DateFormatter()
            df.locale = Locale(identifier: "th_TH")
            df.dateFormat = "d MMMM yyyy"
            currentExpiryString = df.string(from: Date(timeIntervalSince1970: expiryVal))
        } else {
            currentExpiryString = "ถาวร"
        }
    }
    
    private func handleUpdatePlan() {
        isLoading = true
        errorMessage = ""
        
        Task {
            do {
                let mId = activeMerchantId
                let tier = selectedPlanId
                let status = "active"
                let expiry: Double? = {
                    if tier == "offline_perpetual" {
                        return Date.distantFuture.timeIntervalSince1970
                    } else {
                        let days = isAnnualBilling ? 365 : 30
                        return Date().addingTimeInterval(TimeInterval(days * 24 * 60 * 60)).timeIntervalSince1970
                    }
                }()
                
                // 1. Update Supabase if connected
                if await NetworkManager.shared.isConnected() {
                    let isoExpiry = expiry.map { NetworkManager.iso8601.string(from: Date(timeIntervalSince1970: $0)) }
                    var payload: [String: Any] = [
                        "subscription_tier": tier,
                        "subscription_status": status
                    ]
                    if let isoExpiry = isoExpiry { payload["subscription_expires_at"] = isoExpiry }
                    
                    _ = try await NetworkManager.shared.sendSupabaseRequest(
                        method: "PATCH",
                        endpoint: "merchants",
                        queryItems: [URLQueryItem(name: "id", value: "eq.\(mId)")],
                        payload: payload
                    )
                }
                
                // 2. Save locally
                MerchantAuthManager.shared.saveSubscription(tier: tier, status: status, expiry: expiry)
                
                // 3. Set offline sync mode
                let isOfflinePlan = (tier == "offline_perpetual" || tier == "offline_subscription")
                UserDefaults.standard.set(isOfflinePlan, forKey: "offline_sync_mode")
                NetworkManager.shared.simulateOffline = isOfflinePlan
                
                await MainActor.run {
                    isLoading = false
                    loadSubscriptionDetails()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = "บันทึกการเปลี่ยนแปลงไม่สำเร็จ: \(error.localizedDescription)"
                }
            }
        }
    }
}
