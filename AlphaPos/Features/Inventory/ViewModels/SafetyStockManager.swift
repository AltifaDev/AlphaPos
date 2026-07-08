// SafetyStockManager.swift
// AlphaPos — Safety Stock, Lead Time & Reorder Point Engine
//
// Implements international inventory best-practice formulas:
//   • Reorder Point (ROP) = Safety Stock + (Avg Daily Usage × Lead Time)
//   • Safety Stock = Z-score × σ_demand × √Lead Time   (statistical method)
//   • Simple Safety Stock = (Max Daily Usage − Avg Daily Usage) × Lead Time
//   • Days of Stock Remaining = Current Qty ÷ Avg Daily Usage
//   • Overstock Alert = Current Qty > Max Stock Level
//
// References:
//   ISO 9001:2015 §8.4 (External provider control / lead time)
//   GS1 Global Traceability Standard 2.0
//   APICS Dictionary, 16th ed. — "safety stock", "reorder point"
// ─────────────────────────────────────────────────────────────────────────────

import Foundation
import SwiftData

// MARK: - StockStatus

/// Full stock health classification for one item.
enum StockStatus: String, CaseIterable {
    case overstock          = "overstock"       // qty > maxStockLevel (if set)
    case adequate           = "adequate"        // normal range
    case belowSafety        = "belowSafety"     // qty < safetyStockLevel
    case atReorderPoint     = "atReorderPoint"  // qty ≤ reorder point → order now
    case lowStock           = "lowStock"        // qty ≤ reorderLevel (legacy compat)
    case outOfStock         = "outOfStock"      // qty ≤ 0

    var displayName: String {
        switch self {
        case .overstock:       return "สต็อกเกิน"
        case .adequate:        return "ปกติ"
        case .belowSafety:     return "ต่ำกว่า Safety Stock"
        case .atReorderPoint:  return "ถึงจุดสั่งซื้อ"
        case .lowStock:        return "สต็อกต่ำ"
        case .outOfStock:      return "หมดสต็อก"
        }
    }

    var systemImage: String {
        switch self {
        case .overstock:       return "arrow.up.circle.fill"
        case .adequate:        return "checkmark.circle.fill"
        case .belowSafety:     return "shield.slash.fill"
        case .atReorderPoint:  return "cart.badge.plus"
        case .lowStock:        return "exclamationmark.triangle.fill"
        case .outOfStock:      return "xmark.circle.fill"
        }
    }

    var colorName: String {
        switch self {
        case .overstock:       return "appIndigo"
        case .adequate:        return "appTeal"
        case .belowSafety:     return "appOrange"
        case .atReorderPoint:  return "appYellow"
        case .lowStock:        return "appRose"
        case .outOfStock:      return "appRose"
        }
    }

    /// Priority for sorting alerts (lower = more urgent).
    var urgencyRank: Int {
        switch self {
        case .outOfStock:      return 0
        case .atReorderPoint:  return 1
        case .lowStock:        return 2
        case .belowSafety:     return 3
        case .overstock:       return 4
        case .adequate:        return 5
        }
    }
}

// MARK: - ReorderSuggestion

/// A suggested purchase order line — what to order, how much, and when.
struct ReorderSuggestion: Identifiable {
    let id: UUID
    let item: InventoryItem
    let status: StockStatus
    let reorderPoint: Double       // calculated ROP for this item
    let suggestedOrderQty: Double  // qty to bring stock back to maxStockLevel (or 2× reorderLevel)
    let daysOfStockRemaining: Double?
    let urgencyDays: Int?          // nil if avg usage unknown; 0 = already out
    let supplierName: String?
    let leadTimeDays: Int
}

// MARK: - StockMetrics

/// All computed metrics for one InventoryItem.
struct StockMetrics {
    let item: InventoryItem
    let avgDailyUsage: Double          // computed from last 30-day transactions
    let maxDailyUsage: Double          // peak daily usage in last 30 days
    let reorderPoint: Double           // safety stock + (avgDailyUsage × leadTime)
    let daysOfStockRemaining: Double?  // nil when avgDailyUsage == 0
    let status: StockStatus
    let safetyStockEffective: Double   // item.safetyStockLevel (or 0 if not set)
    let isOverstocked: Bool
    let overstockQty: Double           // how much above max (0 if not overstocked)

    /// Quantity to order to reach maxStockLevel. Falls back to 2× reorderLevel.
    var suggestedOrderQty: Double {
        let target = item.maxStockLevel > 0 ? item.maxStockLevel : item.reorderLevel * 2
        let needed = target - item.currentQuantity
        return max(needed, 0)
    }
}

// MARK: - SafetyStockManager

@Observable
@MainActor
final class SafetyStockManager {

    var modelContext: ModelContext?

    // Cache — rebuilt on each call to `computeMetrics` or `generateSuggestions`
    private var metricsCache: [UUID: StockMetrics] = [:]
    private var cachedTransactions: [InventoryTransaction]? = nil

    func preloadTransactions() {
        guard let modelContext else { return }
        let descriptor = FetchDescriptor<InventoryTransaction>(
            predicate: #Predicate<InventoryTransaction> { txn in
                txn.isDeleted == false
            }
        )
        cachedTransactions = try? modelContext.fetch(descriptor)
    }

    func clearTransactionCache() {
        cachedTransactions = nil
    }

    init(modelContext: ModelContext? = nil) {
        self.modelContext = modelContext
    }

    // MARK: - Core Formula Engine

    /// Calculate Reorder Point for an item given its stored params + average usage.
    /// ROP = Safety Stock + (Avg Daily Usage × Lead Time Days)
    func reorderPoint(for item: InventoryItem, avgDailyUsage: Double) -> Double {
        let safety = item.safetyStockLevel > 0 ? item.safetyStockLevel : item.reorderLevel
        return safety + (avgDailyUsage * Double(item.leadTimeDays))
    }

    /// Statistical Safety Stock (Normally-distributed demand model).
    /// SS = Z × σ_demand × √Lead Time
    /// Z = 1.645 for 95% service level (industry default for food & beverage)
    func statisticalSafetyStock(
        sigma: Double,        // std dev of daily demand
        leadTimeDays: Int,
        serviceLevel: Double = 0.95
    ) -> Double {
        // Z-score lookup (common service levels)
        let z: Double
        switch serviceLevel {
        case ..<0.85: z = 1.04
        case ..<0.90: z = 1.28
        case ..<0.95: z = 1.645
        case ..<0.99: z = 2.326
        default:      z = 2.576
        }
        return z * sigma * sqrt(Double(leadTimeDays))
    }

    /// Simple Safety Stock (Max − Avg demand model — easier for F&B operators).
    /// SS = (Max Daily Usage − Avg Daily Usage) × Lead Time
    func simpleSafetyStock(
        maxDailyUsage: Double,
        avgDailyUsage: Double,
        leadTimeDays: Int
    ) -> Double {
        max(0, (maxDailyUsage - avgDailyUsage) * Double(leadTimeDays))
    }

    // MARK: - Usage Analysis (from InventoryTransaction history)

    /// Compute average and max daily usage from the last `days` calendar days.
    func usageStats(
        for item: InventoryItem,
        days lookbackDays: Int = 30
    ) -> (avgDaily: Double, maxDaily: Double, totalUsed: Double) {
        guard let modelContext else { return (0, 0, 0) }

        let cutoff = Calendar.current.date(byAdding: .day, value: -lookbackDays, to: Date()) ?? Date()

        let allTxns: [InventoryTransaction]
        if let cached = cachedTransactions {
            allTxns = cached
        } else {
            let descriptor = FetchDescriptor<InventoryTransaction>(
                predicate: #Predicate<InventoryTransaction> { txn in
                    txn.isDeleted == false
                }
            )
            allTxns = (try? modelContext.fetch(descriptor)) ?? []
        }

        // Filter: this item, sell/waste types, within lookback window
        let usageTxns = allTxns.filter { txn in
            guard txn.item?.id == item.id,
                  txn.branch?.id == item.branch?.id,
                  txn.updatedAt >= cutoff else { return false }
            return txn.transactionType == InventoryMovementType.sell.rawValue || txn.transactionType == InventoryMovementType.waste.rawValue
        }

        guard !usageTxns.isEmpty else { return (0, 0, 0) }

        // Group by calendar day
        let calendar = Calendar.current
        var dailyUsage: [String: Double] = [:]
        for txn in usageTxns {
            let dayKey = calendar.startOfDay(for: txn.updatedAt).ISO8601Format()
            dailyUsage[dayKey, default: 0] += txn.quantity
        }

        let totalUsed = usageTxns.reduce(0) { $0 + $1.quantity }
        let avg = totalUsed / Double(lookbackDays)   // denominator = full period (incl. zero-usage days)
        let maxDaily = dailyUsage.values.max() ?? 0

        return (avgDaily: avg, maxDaily: maxDaily, totalUsed: totalUsed)
    }

    // MARK: - Compute Metrics for One Item

    func computeMetrics(for item: InventoryItem) -> StockMetrics {
        let (avg, maxD, _) = usageStats(for: item)
        let rop = reorderPoint(for: item, avgDailyUsage: avg)

        let daysLeft: Double? = avg > 0 ? item.currentQuantity / avg : nil
        let isOver = item.maxStockLevel > 0 && item.currentQuantity > item.maxStockLevel
        let overstockQty = isOver ? item.currentQuantity - item.maxStockLevel : 0

        let status = stockStatus(item: item, rop: rop, isOverstocked: isOver)

        let metrics = StockMetrics(
            item: item,
            avgDailyUsage: avg,
            maxDailyUsage: maxD,
            reorderPoint: rop,
            daysOfStockRemaining: daysLeft,
            status: status,
            safetyStockEffective: item.safetyStockLevel,
            isOverstocked: isOver,
            overstockQty: overstockQty
        )
        metricsCache[item.id] = metrics
        return metrics
    }

    // MARK: - Status Classification

    private func stockStatus(
        item: InventoryItem,
        rop: Double,
        isOverstocked: Bool
    ) -> StockStatus {
        if item.currentQuantity <= 0              { return .outOfStock }
        if item.currentQuantity <= rop            { return .atReorderPoint }
        if item.currentQuantity <= item.reorderLevel { return .lowStock }
        if item.safetyStockLevel > 0,
           item.currentQuantity <= item.safetyStockLevel { return .belowSafety }
        if isOverstocked                          { return .overstock }
        return .adequate
    }

    // MARK: - Generate Reorder Suggestions

    /// Returns ReorderSuggestion for all items that need attention,
    /// sorted by urgency (out-of-stock first).
    func generateSuggestions(
        branch: Branch? = nil,
        includeOverstock: Bool = false
    ) -> [ReorderSuggestion] {
        guard let modelContext else { return [] }

        preloadTransactions()
        defer { clearTransactionCache() }

        let descriptor = FetchDescriptor<InventoryItem>(
            predicate: #Predicate<InventoryItem> { item in
                item.isDeleted == false
            }
        )
        guard let allItems = try? modelContext.fetch(descriptor) else { return [] }

        let filtered: [InventoryItem]
        if let branch {
            filtered = allItems.filter { $0.branch?.id == branch.id }
        } else {
            filtered = allItems
        }

        var suggestions: [ReorderSuggestion] = []

        for item in filtered {
            let metrics = computeMetrics(for: item)
            guard metrics.status != .adequate else { continue }
            if !includeOverstock && metrics.status == .overstock { continue }

            let urgencyDays: Int?
            if let days = metrics.daysOfStockRemaining {
                urgencyDays = Int(days)
            } else {
                urgencyDays = nil
            }

            suggestions.append(ReorderSuggestion(
                id: UUID(),
                item: item,
                status: metrics.status,
                reorderPoint: metrics.reorderPoint,
                suggestedOrderQty: metrics.suggestedOrderQty,
                daysOfStockRemaining: metrics.daysOfStockRemaining,
                urgencyDays: urgencyDays,
                supplierName: item.supplier?.name,
                leadTimeDays: item.leadTimeDays
            ))
        }

        return suggestions.sorted { $0.status.urgencyRank < $1.status.urgencyRank }
    }

    // MARK: - Smart Reorder Quantity Calculator

    /// Suggest an order quantity for a specific item.
    /// Target: bring stock to maxStockLevel; fallback to 2× reorderLevel.
    func suggestedOrderQty(for item: InventoryItem) -> Double {
        let target = item.maxStockLevel > 0
            ? item.maxStockLevel
            : max(item.reorderLevel * 2, item.reorderLevel + item.safetyStockLevel)
        return max(target - item.currentQuantity, 0)
    }

    // MARK: - Cached Metric Retrieval

    /// Return cached metrics (fast, no fetch). Falls back to `computeMetrics` if missing.
    func metrics(for item: InventoryItem) -> StockMetrics {
        if let cached = metricsCache[item.id] { return cached }
        return computeMetrics(for: item)
    }

    /// Clear cache (call after bulk receive/waste operations).
    func invalidateCache() {
        metricsCache.removeAll()
    }

    // MARK: - Shared Instance Helper

    private static var instances: [ObjectIdentifier: SafetyStockManager] = [:]

    @MainActor
    static func shared(for context: ModelContext) -> SafetyStockManager {
        let key = ObjectIdentifier(context)
        if let existing = instances[key] { return existing }
        let manager = SafetyStockManager(modelContext: context)
        instances[key] = manager
        return manager
    }
}
