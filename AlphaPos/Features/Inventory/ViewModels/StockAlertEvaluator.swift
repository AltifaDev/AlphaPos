// StockAlertEvaluator.swift
// AlphaPos — Refresh live inventory alerts + optional POS auto sold-out

import Foundation
import SwiftData

@MainActor
enum StockAlertEvaluator {
    private static var lastRefreshAt: Date = .distantPast
    private static let minInterval: TimeInterval = 2.0

    private static func scopedKey(_ base: String) -> String {
        let merchant = UserDefaults.standard.string(forKey: "active_merchant_id") ?? "none"
        let branch = BranchContext.shared.activeBranchIDString
        return "\(base).\(merchant.lowercased()).\(branch.lowercased())"
    }

    /// Rebuild Notification Center inventory live rows and optionally auto-lock menus.
    static func refresh(modelContext: ModelContext, force: Bool = false) {
        let alertsEnabled = UserDefaults.standard.object(forKey: "enable_inventory_stock_alerts") as? Bool ?? true
        let autoDisable = UserDefaults.standard.bool(forKey: "auto_disable_oos_menu")

        if !force, Date().timeIntervalSince(lastRefreshAt) < minInterval { return }
        lastRefreshAt = Date()

        let activeBranch = fetchActiveBranch(context: modelContext)

        var itemDesc = FetchDescriptor<InventoryItem>(
            predicate: #Predicate<InventoryItem> { !$0.isDeleted }
        )
        itemDesc.fetchLimit = 5000
        let items = (try? modelContext.fetch(itemDesc)) ?? []

        let branchItems: [InventoryItem]
        if let branch = activeBranch {
            branchItems = items.filter { $0.branch == nil || $0.branch?.id == branch.id }
        } else {
            branchItems = items
        }

        if alertsEnabled {
            NotificationStore.shared.rebuildLiveInventoryAlerts(items: branchItems)
        } else {
            NotificationStore.shared.rebuildLiveInventoryAlerts(items: [])
        }

        // History pulse for newly crossed OOS (once per item until recovered)
        if alertsEnabled {
            pulseHistoryForNewOutages(branchItems)
        }

        if autoDisable {
            applyAutoMenuLocks(modelContext: modelContext, activeBranch: activeBranch)
        }
    }

    // MARK: - History pulses

    private static func pulseHistoryForNewOutages(_ items: [InventoryItem]) {
        let pulseKey = scopedKey("stock_oos_pulse_ids")
        let currentOutIds = Set(items.filter { $0.currentQuantity <= 0 }.map { $0.id.uuidString })
        // First observation establishes the baseline. Existing shortages are
        // active conditions, not a burst of newly delivered events.
        guard UserDefaults.standard.object(forKey: pulseKey) != nil else {
            UserDefaults.standard.set(Array(currentOutIds), forKey: pulseKey)
            return
        }
        var seen = Set(UserDefaults.standard.stringArray(forKey: pulseKey) ?? [])
        var changed = false

        for item in items where item.currentQuantity <= 0 {
            let id = item.id.uuidString
            if !seen.contains(id) {
                seen.insert(id)
                changed = true
                SyncEngine.shared.alertOutOfStock(
                    itemName: item.name,
                    currentQty: item.currentQuantity,
                    itemId: id
                )
                SyncEngine.shared.pushInventoryAlertToStaff(
                    itemName: item.name,
                    itemId: id,
                    isOut: true
                )
            }
        }

        // Clear pulse memory when recovered so a future OOS can notify again
        let pruned = seen.intersection(currentOutIds)
        if pruned.count != seen.count {
            seen = pruned
            changed = true
        }
        if changed {
            UserDefaults.standard.set(Array(seen), forKey: pulseKey)
        }
    }

    // MARK: - Auto menu lock

    private static func applyAutoMenuLocks(modelContext: ModelContext, activeBranch: Branch?) {
        let autoLockKey = scopedKey("stock_auto_disabled_menu_ids")
        var locked = Set(UserDefaults.standard.stringArray(forKey: autoLockKey) ?? [])
        var menuDesc = FetchDescriptor<MenuItem>(
            predicate: #Predicate<MenuItem> { !$0.isDeleted }
        )
        menuDesc.fetchLimit = 5000
        let menus = (try? modelContext.fetch(menuDesc)) ?? []
        var dirty = false

        for menu in menus {
            guard menu.tracksStockOnSale else {
                // If we previously auto-locked a now-untracked item, restore
                if locked.contains(menu.id), !menu.isAvailable {
                    menu.isAvailable = true
                    menu.updatedAt = Date()
                    menu.isSynced = false
                    locked.remove(menu.id)
                    dirty = true
                }
                continue
            }

            let oos = StockAvailability.isOutOfStockForSale(
                menuItem: menu,
                activeBranch: activeBranch,
                modelContext: modelContext
            )

            if oos {
                if menu.isAvailable {
                    menu.isAvailable = false
                    menu.updatedAt = Date()
                    menu.isSynced = false
                    locked.insert(menu.id)
                    dirty = true
                } else if !locked.contains(menu.id) {
                    // Already manually sold-out — do not claim auto ownership
                }
            } else if locked.contains(menu.id) {
                // Recovered — only restore if we auto-locked it
                menu.isAvailable = true
                menu.updatedAt = Date()
                menu.isSynced = false
                locked.remove(menu.id)
                dirty = true
            }
        }

        if dirty {
            UserDefaults.standard.set(Array(locked), forKey: autoLockKey)
            modelContext.saveWithLogging(label: "StockAlertEvaluator.applyAutoMenuLocks")
        } else {
            UserDefaults.standard.set(Array(locked), forKey: autoLockKey)
        }
    }

    private static func fetchActiveBranch(context: ModelContext) -> Branch? {
        try? BranchContext.shared.requireActiveBranch(in: context)
    }
}
