import Foundation
import SwiftData

extension SyncEngine {
    func pullMerchantSettings() async {
        guard await NetworkManager.shared.isConnected() else { return }

        guard let merchantIdStr = UserDefaults.standard.string(forKey: "active_merchant_id"),
              let merchantId = UUID(uuidString: merchantIdStr) else { return }

        do {
            guard let settings = try await NetworkManager.shared.fetchMerchantSettings(merchantId: merchantId) else { return }

            await MainActor.run {
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
