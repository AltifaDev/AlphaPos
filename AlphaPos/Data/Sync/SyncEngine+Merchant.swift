import Foundation
import SwiftData

extension SyncEngine {
    func pushDeliveryFeeSettingsIfNeeded() async {
        guard UserDefaults.standard.bool(forKey: "delivery_fee_settings_dirty") else { return }
        do {
            try await NetworkManager.shared.uploadDeliveryFeeSettings()
            UserDefaults.standard.set(false, forKey: "delivery_fee_settings_dirty")
        } catch {
            encounteredSyncError = true
            print("SyncEngine [Delivery Fee Settings Push Error]: \(error.localizedDescription)")
        }
    }

    func pullMerchantSettings(modelContext: ModelContext? = nil, allowOfflinePlanRecovery: Bool = false) async {
        if !allowOfflinePlanRecovery {
            guard await NetworkManager.shared.isConnected() else { return }
        }

        guard let merchantIdStr = UserDefaults.standard.string(forKey: "active_merchant_id"),
              let merchantId = UUID(uuidString: merchantIdStr) else { return }

        do {
            guard let settings = try await NetworkManager.shared.fetchMerchantSettings(
                merchantId: merchantId,
                allowOfflinePlanRecovery: allowOfflinePlanRecovery
            ) else { return }

            await MainActor.run {
                if !UserDefaults.standard.bool(forKey: "delivery_fee_settings_dirty"),
                   let deliverySettings = settings["delivery_fee_settings"] as? [String: [String: Any]] {
                    for (brand, fees) in deliverySettings {
                        UserDefaults.standard.set(remoteDouble(fees["gp"]), forKey: "delivery_gp_\(brand)")
                        UserDefaults.standard.set(remoteDouble(fees["ad_fee"]), forKey: "delivery_adFee_\(brand)")
                        UserDefaults.standard.set(remoteBool(fees["ad_fee_is_pct"], fallback: false), forKey: "delivery_adFeeIsPct_\(brand)")
                        UserDefaults.standard.set(remoteDouble(fees["other_fee"]), forKey: "delivery_otherFee_\(brand)")
                    }
                }
                if let name = settings["name"] as? String {
                    UserDefaults.standard.set(name, forKey: "store_name")
                }
                if let phone = settings["phone"] as? String {
                    UserDefaults.standard.set(phone, forKey: "store_phone")
                }
                if let website = settings["website"] as? String {
                    UserDefaults.standard.set(website, forKey: "store_website")
                }
                if let address = settings["address_street"] as? String {
                    UserDefaults.standard.set(address, forKey: "store_address")
                }
                if let taxId = settings["tax_id"] as? String {
                    UserDefaults.standard.set(taxId, forKey: "store_tax_id")
                }
                if let email = settings["email"] as? String {
                    UserDefaults.standard.set(email, forKey: "store_email")
                }
                if let logoUrl = settings["logo_url"] as? String {
                    UserDefaults.standard.set(logoUrl, forKey: "store_logo_url")
                    if let url = URL(string: logoUrl), !logoUrl.isEmpty {
                        Task.detached(priority: .utility) {
                            if let data = try? Data(contentsOf: url) {
                                if let cacheURL = ESCPOSBuilder.remoteLogoCacheURL() {
                                    try? data.write(to: cacheURL, options: .atomic)
                                }
                                if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                                    let docFile = docs.appendingPathComponent("store_logo.png")
                                    try? data.write(to: docFile, options: .atomic)
                                }
                            }
                        }
                    }
                }
                if let branchCode = settings["branch_code"] as? String {
                    UserDefaults.standard.set(branchCode, forKey: "store_branch_code")
                }
                if let taxRate = settings["tax_rate"] as? Double {
                    UserDefaults.standard.set(taxRate, forKey: "store_tax_rate")
                }
                if let taxType = settings["tax_type"] as? String {
                    UserDefaults.standard.set(taxType, forKey: "store_tax_type")
                }
                if let scRate = settings["service_charge_rate"] as? Double {
                    UserDefaults.standard.set(scRate, forKey: "store_service_charge_rate")
                }
                if let header = settings["receipt_header"] as? String {
                    UserDefaults.standard.set(header, forKey: "store_receipt_header")
                }
                if let footer = settings["receipt_footer"] as? String {
                    UserDefaults.standard.set(footer, forKey: "store_receipt_footer")
                }
                if let promptpay = settings["promptpay_number"] as? String {
                    UserDefaults.standard.set(promptpay, forKey: "promptpay_number")
                }
                if let kwRequired = settings["kitchen_workflow_required"] as? Bool {
                    UserDefaults.standard.set(kwRequired, forKey: "kitchen_workflow_required")
                }
                if let tableSys = settings["is_table_system_enabled"] as? Bool {
                    UserDefaults.standard.set(tableSys, forKey: "enable_table_system")
                }
                if let webOrder = settings["is_web_ordering_enabled"] as? Bool {
                    UserDefaults.standard.set(webOrder, forKey: "enable_web_ordering")
                }
                if let preferences = settings["printer_preferences"] as? [String: Any] {
                    for (key, value) in preferences {
                        if let enabled = value as? Bool {
                            UserDefaults.standard.set(enabled, forKey: key)
                        }
                    }
                }

                // Refresh subscription cache from canonical merchant row.
                if let tier = settings["subscription_tier"] as? String, !tier.isEmpty {
                    let wasOfflinePlan = OfflineSyncModeController.isOfflineSubscriptionPlan
                    let status = settings["subscription_status"] as? String ?? "active"
                    let expiry = SyncEngine.shared.parseISO8601DateOptional(settings["subscription_expires_at"])
                        .map(\.timeIntervalSince1970)
                    MerchantAuthManager.shared.saveSubscription(tier: tier, status: status, expiry: expiry)
                    if wasOfflinePlan || OfflineSyncModeController.isOfflinePlan(tier: tier) {
                        OfflineSyncModeController.applyForSubscriptionTier(tier, modelContext: modelContext)
                    }
                }

                #if DEBUG
                print("SyncEngine: Successfully pulled and updated local store settings from merchant profile.")
                #endif
            }
        } catch {
            encounteredSyncError = true
            print("SyncEngine [Merchant Settings Pull Error]: \(error.localizedDescription)")
        }
    }
}
