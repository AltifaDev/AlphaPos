import Foundation
import SwiftData

/// Single source of truth for Offline Sync Mode ↔ subscription plan policy.
/// Settings and System Control must both call through this controller.
@MainActor
enum OfflineSyncModeController {
    static let storageKey = "offline_sync_mode"
    static let userSetKey = "offline_mode_user_set"

    static let offlinePlanTiers: Set<String> = [
        "offline_perpetual",
        "offline_subscription"
    ]

    static var isOfflineSubscriptionPlan: Bool {
        isOfflinePlan(tier: MerchantAuthManager.shared.subscriptionTier)
    }

    /// Offline plans keep the toggle locked ON.
    static var isToggleLockedByPlan: Bool {
        isOfflineSubscriptionPlan
    }

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: storageKey)
    }

    static func isOfflinePlan(tier: String?) -> Bool {
        guard let tier, !tier.isEmpty else { return false }
        return offlinePlanTiers.contains(tier)
    }

    /// Force offline mode when the active subscription is an offline plan.
    static func enforcePlanPolicy(modelContext: ModelContext? = nil) {
        guard isOfflineSubscriptionPlan else { return }
        apply(isOffline: true, modelContext: modelContext, markUserSet: false, force: true, isOfflinePlan: true)
    }

    /// Apply mode from a known subscription tier (login / plan change).
    static func applyForSubscriptionTier(_ tier: String, modelContext: ModelContext? = nil) {
        apply(
            isOffline: isOfflinePlan(tier: tier),
            modelContext: modelContext,
            markUserSet: false,
            force: true,
            isOfflinePlan: isOfflinePlan(tier: tier)
        )
    }

    /// User-driven toggle from Settings / System Control.
    /// Returns `false` when the change is rejected by an offline plan lock.
    @discardableResult
    static func setUserPreference(isOffline: Bool, modelContext: ModelContext? = nil) -> Bool {
        apply(
            isOffline: isOffline,
            modelContext: modelContext,
            markUserSet: true,
            force: false,
            isOfflinePlan: isOfflineSubscriptionPlan
        )
    }

    // MARK: - Private

    @discardableResult
    private static func apply(
        isOffline: Bool,
        modelContext: ModelContext?,
        markUserSet: Bool,
        force: Bool,
        isOfflinePlan: Bool
    ) -> Bool {
        let effectiveOffline: Bool
        if !force && isOfflineSubscriptionPlan {
            effectiveOffline = true
        } else {
            effectiveOffline = isOffline
        }

        UserDefaults.standard.set(effectiveOffline, forKey: storageKey)
        // A temporary offline session on an online plan must preserve the
        // merchant's web-ordering preference for automatic recovery.
        if effectiveOffline && isOfflinePlan {
            UserDefaults.standard.set(false, forKey: "enable_web_ordering")
        }
        if markUserSet {
            UserDefaults.standard.set(true, forKey: userSetKey)
        }
        syncRuntime(isOffline: effectiveOffline, modelContext: modelContext)

        // Rejected attempt to leave offline mode on an offline plan.
        if !force && isOfflineSubscriptionPlan && !isOffline {
            return false
        }
        return true
    }

    private static func syncRuntime(isOffline: Bool, modelContext: ModelContext?) {
        NetworkManager.shared.simulateOffline = isOffline
        NetworkManager.shared.invalidateConnectivityCache()
        if isOffline {
            SyncEngine.shared.cancelPendingSync()
        } else if let modelContext {
            SyncEngine.shared.startRealtimeSync(modelContext: modelContext)
            Task {
                await SyncEngine.shared.syncAll(modelContext: modelContext)
            }
        }
    }
}
