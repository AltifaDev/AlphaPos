import SwiftUI

/// Owner/manager configuration for delivery commissions and platform costs.
/// POS staff can select a platform, but cannot change these financial values.
struct DeliveryPlatformSettingsView: View {
    private struct BrandSelection: Identifiable {
        let id: String
    }

    @State private var selectedBrand: BrandSelection?
    @State private var pendingBrand: String?
    @State private var showingManagerAuthorization = false
    @State private var gp = 0.0
    @State private var adFee = 0.0
    @State private var adFeeIsPct = false
    @State private var otherFee = 0.0
    @AppStorage("delivery_post_payment_order_type") private var postDeliveryOrderType = "take_out"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("ตั้งค่าเดลิเวอรี่", systemImage: "shippingbox.fill")
                        .font(.title2.bold())
                    Text("กำหนด GP ค่าโฆษณา และค่าใช้จ่ายของแต่ละแพลตฟอร์ม ค่าที่บันทึกจะถูกนำไปใช้กับออร์เดอร์ใหม่โดยอัตโนมัติ")
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                }

                // MARK: - Post-payment Order Mode
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.swap")
                            .foregroundColor(.appAccent)
                        Text(LocalizationManager.shared.currentLanguage == .thai ? "โหมดเริ่มต้นหลังชำระเงินเดลิเวอรี่" : "Default Mode After Delivery Payment")
                            .font(.subheadline.bold())
                            .foregroundColor(.textPrimary)
                    }

                    Text(LocalizationManager.shared.currentLanguage == .thai
                         ? "กำหนดสถานะของออร์เดอร์ที่ต้องการให้ระบบเลือกอัตโนมัติ เมื่อทำการชำระเงินในโหมดเดลิเวอรี่สำเร็จ"
                         : "Select which order mode the POS should automatically switch to after completing a delivery payment.")
                        .font(.caption)
                        .foregroundColor(.textSecondary)

                    Picker(
                        LocalizationManager.shared.currentLanguage == .thai ? "โหมดหลังชำระเงิน" : "Post-payment Mode",
                        selection: $postDeliveryOrderType
                    ) {
                        Text(LocalizationManager.shared.currentLanguage == .thai ? "สั่งกลับบ้าน (Takeaway)" : "Takeaway").tag("take_out")
                        Text(LocalizationManager.shared.currentLanguage == .thai ? "ทานที่ร้าน (Dine-in)" : "Dine-in").tag("dine_in")
                    }
                    .pickerStyle(.segmented)
                }
                .padding(14)
                .background(Color.appSurface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorderSubtle))

                ForEach(ExternalSalesChannel.all, id: \.self) { brand in
                    Button {
                        pendingBrand = brand
                        showingManagerAuthorization = true
                        APHaptic.trigger()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "shippingbox")
                                .foregroundColor(.appAccent)
                                .frame(width: 32, height: 32)
                                .background(Color.appAccent.opacity(0.1), in: Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                Text(brand).fontWeight(.semibold).foregroundColor(.textPrimary)
                                Text(summary(for: brand))
                                    .font(.caption)
                                    .foregroundColor(.textSecondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.textTertiary)
                        }
                        .padding(14)
                        .background(Color.appSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorderSubtle))
                    }
                    .buttonStyle(.plain)
                }

                Label("หน้า POS จะแสดงเฉพาะตัวเลือกแพลตฟอร์มและเลขออร์เดอร์ พนักงานไม่สามารถแก้ค่าธรรมเนียมจากหน้าขายได้", systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                    .padding(12)
                    .background(Color.appAmber.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
            .padding()
        }
        .background(Color.appBackground)
        .navigationTitle("ตั้งค่าเดลิเวอรี่")
        .sheet(item: $selectedBrand) { selection in
            let brand = selection.id
            DeliverySettingsSheet(
                gp: $gp,
                adFee: $adFee,
                adFeeIsPct: $adFeeIsPct,
                otherFee: $otherFee,
                brandName: brand,
                onApply: { save(brand) }
            )
        }
        .sheet(isPresented: $showingManagerAuthorization) {
            ManagerPINVerificationSheet(
                isPresented: $showingManagerAuthorization,
                onSuccess: {
                    // Owner PIN reaches only this callback. A manager callback
                    // consumes pendingBrand before onSuccess is invoked.
                    if pendingBrand != nil { openPendingBrand() }
                },
                onAuthorizedManager: { _ in openPendingBrand() },
                onDismiss: {
                    if !showingManagerAuthorization { pendingBrand = nil }
                },
                requiredPermission: .managerOverride
            )
        }
    }

    private func load(_ brand: String) {
        let defaults = UserDefaults.standard
        gp = defaults.double(forKey: "delivery_gp_\(brand)")
        adFee = defaults.double(forKey: "delivery_adFee_\(brand)")
        adFeeIsPct = defaults.bool(forKey: "delivery_adFeeIsPct_\(brand)")
        otherFee = defaults.double(forKey: "delivery_otherFee_\(brand)")
    }

    private func openPendingBrand() {
        guard let brand = pendingBrand else { return }
        pendingBrand = nil
        load(brand)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            selectedBrand = BrandSelection(id: brand)
        }
    }

    private func save(_ brand: String) {
        let defaults = UserDefaults.standard
        defaults.set(gp, forKey: "delivery_gp_\(brand)")
        defaults.set(adFee, forKey: "delivery_adFee_\(brand)")
        defaults.set(adFeeIsPct, forKey: "delivery_adFeeIsPct_\(brand)")
        defaults.set(otherFee, forKey: "delivery_otherFee_\(brand)")
        defaults.set(true, forKey: "delivery_fee_settings_dirty")
        Task { await SyncEngine.shared.pushDeliveryFeeSettingsIfNeeded() }
    }

    private func summary(for brand: String) -> String {
        let defaults = UserDefaults.standard
        let gpValue = defaults.double(forKey: "delivery_gp_\(brand)")
        let adValue = defaults.double(forKey: "delivery_adFee_\(brand)")
        let adPct = defaults.bool(forKey: "delivery_adFeeIsPct_\(brand)")
        let other = defaults.double(forKey: "delivery_otherFee_\(brand)")
        return "GP \(String(format: "%.1f", gpValue))% · Ads \(adPct ? String(format: "%.1f%%", adValue) : String(format: "฿%.2f", adValue)) · Other ฿\(String(format: "%.2f", other))"
    }
}
