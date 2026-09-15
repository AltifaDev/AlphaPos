import Foundation
import SwiftData

/// Post-dashboard guided setup (Phase 4 of onboarding redesign).
/// Tracks incomplete store readiness without blocking Dashboard entry.
enum StoreSetupChecklist {
    enum Item: String, CaseIterable, Identifiable {
        case firstMenuItem
        case firstTable
        case ownerPin
        case openShift
        case shopProfile
        case activatePlan

        var id: String { rawValue }

        var titleKey: String {
            switch self {
            case .firstMenuItem: return "setup_checklist_menu_title"
            case .firstTable: return "setup_checklist_table_title"
            case .ownerPin: return "setup_checklist_pin_title"
            case .openShift: return "setup_checklist_shift_title"
            case .shopProfile: return "setup_checklist_profile_title"
            case .activatePlan: return "setup_checklist_plan_title"
            }
        }

        var subtitleKey: String {
            switch self {
            case .firstMenuItem: return "setup_checklist_menu_sub"
            case .firstTable: return "setup_checklist_table_sub"
            case .ownerPin: return "setup_checklist_pin_sub"
            case .openShift: return "setup_checklist_shift_sub"
            case .shopProfile: return "setup_checklist_profile_sub"
            case .activatePlan: return "setup_checklist_plan_sub"
            }
        }

        var systemImage: String {
            switch self {
            case .firstMenuItem: return "menucard.fill"
            case .firstTable: return "tablecells.fill"
            case .ownerPin: return "person.badge.key.fill"
            case .openShift: return "coloncurrencysign.circle.fill"
            case .shopProfile: return "building.2.fill"
            case .activatePlan:
                return StoreSetupChecklist.isTrialExpired ? "exclamationmark.triangle.fill" : "creditcard.fill"
            }
        }

        /// Critical items re-surface even after dismiss.
        var isCritical: Bool {
            switch self {
            case .ownerPin: return true
            case .activatePlan: return StoreSetupChecklist.isTrialExpired
            default: return false
            }
        }

        func dynamicSubtitle() -> String {
            switch self {
            case .activatePlan:
                let status = (MerchantAuthManager.shared.subscriptionStatus ?? "").lowercased()
                if status == "trial" {
                    if let days = StoreSetupChecklist.remainingTrialDays {
                        if days <= 0 {
                            return "setup_checklist_plan_trial_expired".t
                        } else if days == 1 {
                            return "setup_checklist_plan_trial_1day".t
                        } else {
                            return LocalizationManager.shared.t("setup_checklist_plan_trial_active", days)
                        }
                    }
                }
                return subtitleKey.t
            default:
                return subtitleKey.t
            }
        }
    }

    static var remainingTrialDays: Int? {
        guard let expiry = MerchantAuthManager.shared.subscriptionExpiry else { return nil }
        let remainingSeconds = expiry - Date().timeIntervalSince1970
        return max(0, Int(ceil(remainingSeconds / 86400.0)))
    }

    static var isTrialExpired: Bool {
        let status = (MerchantAuthManager.shared.subscriptionStatus ?? "").lowercased()
        guard status == "trial" || status == "expired" else { return false }
        if let remaining = remainingTrialDays {
            return remaining <= 0
        }
        return false
    }

    static let pendingFirstProductKey = "pending_catalog_first_product"
    static let pendingAddFirstTableKey = "pending_add_first_table"

    private static let dismissedPrefix = "store_setup_checklist_dismissed_"
    private static let profileSkippedPrefix = "store_setup_profile_skipped_"

    /// Ordered for time-to-value: catalog → tables (if on) → PIN → shift → optional.
    static func incompleteItems(modelContext: ModelContext) -> [Item] {
        var items: [Item] = []

        let menuDescriptor = FetchDescriptor<MenuItem>(
            predicate: #Predicate<MenuItem> { $0.isDeleted == false }
        )
        let menuCount = (try? modelContext.fetchCount(menuDescriptor)) ?? 0
        if menuCount == 0 {
            items.append(.firstMenuItem)
        }

        let tablesEnabled = UserDefaults.standard.object(forKey: "enable_table_system") as? Bool ?? true
        if tablesEnabled {
            let tableDescriptor = FetchDescriptor<RestaurantTable>(
                predicate: #Predicate<RestaurantTable> { $0.isDeleted == false }
            )
            let tableCount = (try? modelContext.fetchCount(tableDescriptor)) ?? 0
            if tableCount == 0 {
                items.append(.firstTable)
            }
        }

        if !KeychainManager.shared.isOwnerPinConfigured() {
            items.append(.ownerPin)
        }

        let openShift = FetchDescriptor<RegisterSession>(
            predicate: #Predicate<RegisterSession> { $0.closedAt == nil && $0.isDeleted == false }
        )
        let openCount = (try? modelContext.fetchCount(openShift)) ?? 0
        if openCount == 0 {
            items.append(.openShift)
        }

        let merchantId = normalize(
            MerchantAuthManager.shared.merchantId
                ?? UserDefaults.standard.string(forKey: "active_merchant_id")
                ?? ""
        )
        if !isProfileSkipped(for: merchantId) {
            let tax = (UserDefaults.standard.string(forKey: "store_tax_id") ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let phone = (UserDefaults.standard.string(forKey: "store_phone") ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if tax.isEmpty || phone.isEmpty {
                items.append(.shopProfile)
            }
        }

        let status = (MerchantAuthManager.shared.subscriptionStatus ?? "active").lowercased()
        if status == "trial" || status == "pending_payment" {
            items.append(.activatePlan)
        }

        return items
    }

    static func shouldShowBanner(modelContext: ModelContext) -> Bool {
        shouldShowBanner(items: incompleteItems(modelContext: modelContext))
    }

    /// Accept precomputed items so navigation does not execute the same SwiftData
    /// counts twice merely to decide banner visibility.
    static func shouldShowBanner(items: [Item]) -> Bool {
        guard !items.isEmpty else { return false }
        let merchantId = normalize(
            MerchantAuthManager.shared.merchantId
                ?? UserDefaults.standard.string(forKey: "active_merchant_id")
                ?? ""
        )
        if isDismissed(for: merchantId) {
            return items.contains(where: \.isCritical)
        }
        return true
    }

    static func dismiss(for merchantId: String) {
        let id = normalize(merchantId)
        guard !id.isEmpty else { return }
        UserDefaults.standard.set(true, forKey: dismissedPrefix + id)
    }

    static func clearDismiss(for merchantId: String) {
        let id = normalize(merchantId)
        guard !id.isEmpty else { return }
        UserDefaults.standard.removeObject(forKey: dismissedPrefix + id)
    }

    /// Re-show the checklist banner (Organization / Settings entry point).
    static func reopen(for merchantId: String) {
        clearDismiss(for: merchantId)
        NotificationCenter.default.post(name: .reopenStoreSetupChecklistNotification, object: nil)
    }

    static func skipProfile(for merchantId: String) {
        let id = normalize(merchantId)
        guard !id.isEmpty else { return }
        UserDefaults.standard.set(true, forKey: profileSkippedPrefix + id)
    }

    static func isProfileSkipped(for merchantId: String) -> Bool {
        let id = normalize(merchantId)
        guard !id.isEmpty else { return false }
        return UserDefaults.standard.bool(forKey: profileSkippedPrefix + id)
    }

    // MARK: - Deep links

    static func requestFirstProductGuide() {
        UserDefaults.standard.set(true, forKey: pendingFirstProductKey)
        NotificationCenter.default.post(name: .openFirstProductGuideNotification, object: nil)
    }

    @discardableResult
    static func consumePendingFirstProductGuide() -> Bool {
        guard UserDefaults.standard.bool(forKey: pendingFirstProductKey) else { return false }
        UserDefaults.standard.removeObject(forKey: pendingFirstProductKey)
        return true
    }

    static func requestAddFirstTable() {
        UserDefaults.standard.set(true, forKey: pendingAddFirstTableKey)
        NotificationCenter.default.post(name: .openAddFirstTableNotification, object: nil)
    }

    @discardableResult
    static func consumePendingAddFirstTable() -> Bool {
        guard UserDefaults.standard.bool(forKey: pendingAddFirstTableKey) else { return false }
        UserDefaults.standard.removeObject(forKey: pendingAddFirstTableKey)
        return true
    }

    private static func isDismissed(for merchantId: String) -> Bool {
        let id = normalize(merchantId)
        guard !id.isEmpty else { return false }
        return UserDefaults.standard.bool(forKey: dismissedPrefix + id)
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
