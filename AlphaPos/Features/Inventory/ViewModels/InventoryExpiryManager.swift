// InventoryExpiryManager.swift
// AlphaPos — Expiry Date & FEFO (First Expired, First Out) Management
//
// Drop-in addition to the existing inventory system.
// ─────────────────────────────────────────────────────────────────────────────
// What this file adds:
//   ✓ ExpiryStatus enum — classifies each lot (expired / critical / warning / ok)
//   ✓ InventoryLot model — per-batch tracking with expiryDate + lotNumber
//   ✓ ExpiryAlertThreshold — configurable warning windows per item
//   ✓ InventoryExpiryManager — FEFO consumption engine + dashboard queries
//   ✓ ExpiryNotificationScheduler — generates in-app alert payloads
// ─────────────────────────────────────────────────────────────────────────────

import Foundation
import SwiftData

// MARK: - ExpiryStatus

/// Classifies the urgency of an inventory lot based on its expiry date.
enum ExpiryStatus: String, Codable, CaseIterable {
    case expired    = "expired"    // expiryDate < today
    case critical   = "critical"   // expires within criticalDays (default 3)
    case warning    = "warning"    // expires within warningDays (default 7)
    case ok         = "ok"         // safe

    /// SF Symbol name for each status.
    var systemImage: String {
        switch self {
        case .expired:  return "xmark.circle.fill"
        case .critical: return "exclamationmark.triangle.fill"
        case .warning:  return "clock.badge.exclamationmark.fill"
        case .ok:       return "checkmark.seal.fill"
        }
    }

    /// Display color key (map to your app colour tokens in the call site).
    var colorName: String {
        switch self {
        case .expired:  return "appRose"
        case .critical: return "appOrange"
        case .warning:  return "appYellow"
        case .ok:       return "appTeal"
        }
    }
}

// MARK: - ExpiryAlertThreshold

/// Per-item configurable alert windows stored as a value type.
struct ExpiryAlertThreshold {
    /// Days before expiry to show a "Warning" badge (default 7).
    var warningDays: Int
    /// Days before expiry to show a "Critical" badge (default 3).
    var criticalDays: Int

    nonisolated static let `default` = ExpiryAlertThreshold(warningDays: 7, criticalDays: 3)
}

// MARK: - InventoryLot (SwiftData Model)

/// Represents one received batch of an InventoryItem with its own expiry date.
/// Multiple lots per item are consumed FEFO-style.
@Model
final class InventoryLot {
    @Attribute(.unique) var id: UUID

    // Relationships
    var inventoryItem: InventoryItem?
    var branch: Branch?

    // Lot identity
    var lotNumber: String?          // Supplier batch/lot number (optional)
    var receivedDate: Date          // When this lot arrived (set at receive time)
    var expiryDate: Date?           // nil = no-expiry item (e.g., cleaning supplies)

    // Quantities
    var initialQuantity: Double     // Quantity received in this lot
    var remainingQuantity: Double   // Decremented by FEFO consumption

    // Unit cost for this specific lot (may differ from WAC)
    var lotCostPrice: Double

    // Reference back to the transaction that created this lot
    var sourceTransactionId: UUID?

    // Soft-delete / sync metadata
    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        inventoryItem: InventoryItem? = nil,
        branch: Branch? = nil,
        lotNumber: String? = nil,
        receivedDate: Date = Date(),
        expiryDate: Date? = nil,
        initialQuantity: Double,
        remainingQuantity: Double? = nil,
        lotCostPrice: Double = 0.0,
        sourceTransactionId: UUID? = nil,
        isSynced: Bool = false,
        isDeleted: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.inventoryItem = inventoryItem
        self.branch = branch
        self.lotNumber = lotNumber
        self.receivedDate = receivedDate
        self.expiryDate = expiryDate
        self.initialQuantity = initialQuantity
        self.remainingQuantity = remainingQuantity ?? initialQuantity
        self.lotCostPrice = lotCostPrice
        self.sourceTransactionId = sourceTransactionId
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
    }

    // MARK: - Derived Properties

    /// True when remaining quantity is zero (fully consumed or wasted).
    var isFullyConsumed: Bool { remainingQuantity <= 0 }

    /// Computes expiry status relative to `referenceDate` (default: today).
    func expiryStatus(
        threshold: ExpiryAlertThreshold = .default,
        referenceDate: Date = Date()
    ) -> ExpiryStatus {
        guard let expiry = expiryDate else { return .ok }
        let calendar = Calendar.current
        let daysLeft = calendar.dateComponents([.day], from: referenceDate, to: expiry).day ?? 0
        if daysLeft < 0            { return .expired }
        if daysLeft < threshold.criticalDays { return .critical }
        if daysLeft < threshold.warningDays  { return .warning }
        return .ok
    }

    /// Days remaining until expiry. Returns nil for no-expiry items.
    func daysUntilExpiry(from referenceDate: Date = Date()) -> Int? {
        guard let expiry = expiryDate else { return nil }
        return Calendar.current.dateComponents([.day], from: referenceDate, to: expiry).day
    }
}

// MARK: - FEFO Consumption Result

/// Result returned by the FEFO consumption engine.
struct FEFOConsumptionResult {
    /// Lots that were (partially or fully) consumed, with the quantity taken from each.
    var consumed: [(lot: InventoryLot, quantityTaken: Double)]
    /// Quantity that could NOT be fulfilled (stock insufficient).
    var unfulfilled: Double
    /// True if the full requested quantity was satisfied.
    var isFulfilled: Bool { unfulfilled <= 0 }
    /// Total COGS for this consumption (sum of lotCostPrice × quantityTaken).
    var totalCOGS: Double {
        consumed.reduce(0) { $0 + ($1.lot.lotCostPrice * $1.quantityTaken) }
    }
    /// Whether any consumed lot was expired at time of consumption.
    var includedExpiredStock: Bool {
        consumed.contains { $0.lot.expiryStatus() == .expired }
    }
}

// MARK: - Expiry Alert Payload

/// Lightweight struct used to render in-app expiry alerts.
struct ExpiryAlert: Identifiable {
    let id: UUID
    let itemName: String
    let lotNumber: String?
    let expiryDate: Date
    let remainingQuantity: Double
    let unit: String
    let status: ExpiryStatus
    let daysUntilExpiry: Int
    let branchName: String?
}

// MARK: - InventoryExpiryManager

/// Core service for Expiry Date tracking and FEFO consumption.
/// Inject via @StateObject or use as a static utility.
@Observable
@MainActor
final class InventoryExpiryManager {

    var modelContext: ModelContext?
    private var cachedLots: [InventoryLot]? = nil

    func preloadLots() {
        guard let modelContext else { return }
        let descriptor = FetchDescriptor<InventoryLot>(
            predicate: #Predicate<InventoryLot> { lot in
                lot.isDeleted == false
            }
        )
        cachedLots = try? modelContext.fetch(descriptor)
    }

    func clearLotsCache() {
        cachedLots = nil
    }

    init(modelContext: ModelContext? = nil) {
        self.modelContext = modelContext
    }

    // MARK: - Lot Registration (called from processReceive)

    /// Creates a new InventoryLot when stock is received.
    /// Call this inside `InventoryViewModel.processReceive(...)` after WAC update.
    func registerLot(
        for item: InventoryItem,
        quantity: Double,
        costPrice: Double,
        expiryDate: Date?,
        lotNumber: String?,
        sourceTransactionId: UUID?
    ) {
        guard let modelContext else { return }

        let lot = InventoryLot(
            inventoryItem: item,
            branch: item.branch,
            lotNumber: lotNumber,
            receivedDate: Date(),
            expiryDate: expiryDate,
            initialQuantity: quantity,
            remainingQuantity: quantity,
            lotCostPrice: costPrice,
            sourceTransactionId: sourceTransactionId
        )
        modelContext.insert(lot)

        do {
            try modelContext.save()
        } catch {
            // TODO: surface through AppErrorHandler
            print("InventoryExpiryManager: Failed to save lot — \(error.localizedDescription)")
        }
    }

    // MARK: - FEFO Consumption Engine

    /// Deducts `quantity` from the item's lots using FEFO (earliest expiry first).
    /// Non-expiry lots (expiryDate == nil) are consumed last.
    /// Returns a `FEFOConsumptionResult` — the caller must call `modelContext.save()`.
    ///
    /// - Parameters:
    ///   - item: The InventoryItem to deduct from.
    ///   - quantity: Quantity to consume.
    ///   - referenceDate: Date for expiry sorting (default: today).
    @discardableResult
    func consumeFEFO(
        item: InventoryItem,
        quantity: Double,
        referenceDate: Date = Date()
    ) -> FEFOConsumptionResult {
        guard let modelContext else {
            return FEFOConsumptionResult(consumed: [], unfulfilled: quantity)
        }

        // Fetch active lots for this item
        let descriptor = FetchDescriptor<InventoryLot>(
            predicate: #Predicate<InventoryLot> { lot in
                lot.isDeleted == false
            }
        )
        guard let allLots = try? modelContext.fetch(descriptor) else {
            return FEFOConsumptionResult(consumed: [], unfulfilled: quantity)
        }

        // Filter to this item + branch + non-empty
        let itemLots = allLots
            .filter {
                $0.inventoryItem?.id == item.id &&
                $0.branch?.id == item.branch?.id &&
                $0.remainingQuantity > 0
            }

        // FEFO sort: lots with expiryDate first (earliest first), nil-expiry lots last
        let sorted = itemLots.sorted { a, b in
            switch (a.expiryDate, b.expiryDate) {
            case let (.some(da), .some(db)):
                return da < db
            case (.some, .none):
                return true   // expiry lots consumed before no-expiry
            case (.none, .some):
                return false
            case (.none, .none):
                return a.receivedDate < b.receivedDate  // FIFO fallback
            }
        }

        var remaining = quantity
        var consumed: [(lot: InventoryLot, quantityTaken: Double)] = []

        for lot in sorted {
            guard remaining > 0 else { break }
            let take = min(lot.remainingQuantity, remaining)
            lot.remainingQuantity -= take
            lot.updatedAt = Date()
            lot.isSynced = false
            remaining -= take
            consumed.append((lot: lot, quantityTaken: take))
        }

        return FEFOConsumptionResult(consumed: consumed, unfulfilled: max(remaining, 0))
    }

    /// Restores a given quantity back to the inventory lots of an item (used for order voids).
    /// Restores starting from the latest expiry / received date lots (reverse FEFO).
    func restoreFEFO(item: InventoryItem, quantity: Double) {
        guard let modelContext else { return }

        let descriptor = FetchDescriptor<InventoryLot>(
            predicate: #Predicate<InventoryLot> { lot in
                lot.isDeleted == false
            }
        )
        guard let allLots = try? modelContext.fetch(descriptor) else { return }

        let itemLots = allLots.filter {
            $0.inventoryItem?.id == item.id &&
            $0.branch?.id == item.branch?.id &&
            $0.remainingQuantity < $0.initialQuantity
        }

        let sorted = itemLots.sorted { a, b in
            switch (a.expiryDate, b.expiryDate) {
            case let (.some(da), .some(db)):
                return da > db // latest expiry first
            case (.some, .none):
                return false
            case (.none, .some):
                return true
            case (.none, .none):
                return a.receivedDate > b.receivedDate
            }
        }

        var remainingToRestore = quantity
        for lot in sorted {
            guard remainingToRestore > 0 else { break }
            let room = lot.initialQuantity - lot.remainingQuantity
            let restoreAmount = min(room, remainingToRestore)
            lot.remainingQuantity += restoreAmount
            lot.isSynced = false
            lot.updatedAt = Date()
            remainingToRestore -= restoreAmount
        }

        // Fallback: if all lots are full, add remainder to the most recent lot
        if remainingToRestore > 0, let lastLot = sorted.first {
            lastLot.remainingQuantity += remainingToRestore
            lastLot.isSynced = false
            lastLot.updatedAt = Date()
        }
    }

    // MARK: - Expiry Dashboard Queries

    /// Returns all active lots with expiry status != .ok, sorted by urgency.
    func getExpiringAlerts(
        branch: Branch? = nil,
        threshold: ExpiryAlertThreshold = .default,
        referenceDate: Date = Date()
    ) -> [ExpiryAlert] {
        guard let modelContext else { return [] }

        let descriptor = FetchDescriptor<InventoryLot>(
            predicate: #Predicate<InventoryLot> { lot in
                lot.isDeleted == false
            }
        )
        guard let allLots = try? modelContext.fetch(descriptor) else { return [] }

        return allLots
            .filter { lot in
                guard lot.remainingQuantity > 0,
                      let _ = lot.expiryDate else { return false }
                if let branch, lot.branch?.id != branch.id { return false }
                let status = lot.expiryStatus(threshold: threshold, referenceDate: referenceDate)
                return status != .ok
            }
            .compactMap { lot -> ExpiryAlert? in
                guard let item = lot.inventoryItem,
                      let expiry = lot.expiryDate,
                      let days = lot.daysUntilExpiry(from: referenceDate) else { return nil }
                return ExpiryAlert(
                    id: lot.id,
                    itemName: item.name,
                    lotNumber: lot.lotNumber,
                    expiryDate: expiry,
                    remainingQuantity: lot.remainingQuantity,
                    unit: item.unit,
                    status: lot.expiryStatus(threshold: threshold, referenceDate: referenceDate),
                    daysUntilExpiry: days,
                    branchName: lot.branch?.name
                )
            }
            .sorted {
                // Expired first, then critical, then warning; within same status → soonest first
                if $0.status == $1.status { return $0.daysUntilExpiry < $1.daysUntilExpiry }
                let order: [ExpiryStatus] = [.expired, .critical, .warning]
                let ai = order.firstIndex(of: $0.status) ?? 99
                let bi = order.firstIndex(of: $1.status) ?? 99
                return ai < bi
            }
    }

    /// Count of lots expiring within `days` from today (not yet expired).
    func expiringCount(within days: Int, branch: Branch? = nil) -> Int {
        let threshold = ExpiryAlertThreshold(warningDays: days, criticalDays: days)
        return getExpiringAlerts(branch: branch, threshold: threshold)
            .filter { $0.status != .expired }
            .count
    }

    /// Count of already-expired lots still in stock.
    func expiredCount(branch: Branch? = nil) -> Int {
        getExpiringAlerts(branch: branch)
            .filter { $0.status == .expired }
            .count
    }

    /// Returns lots for a specific item sorted FEFO (for display in movement history).
    func lots(for item: InventoryItem, includeEmpty: Bool = false) -> [InventoryLot] {
        guard let modelContext else { return [] }

        let all: [InventoryLot]
        if let cached = cachedLots {
            all = cached
        } else {
            let descriptor = FetchDescriptor<InventoryLot>(
                predicate: #Predicate<InventoryLot> { lot in
                    lot.isDeleted == false
                }
            )
            all = (try? modelContext.fetch(descriptor)) ?? []
        }

        return all
            .filter { lot in
                guard lot.inventoryItem?.id == item.id else { return false }
                if !includeEmpty && lot.remainingQuantity <= 0 { return false }
                return true
            }
            .sorted {
                switch ($0.expiryDate, $1.expiryDate) {
                case let (.some(a), .some(b)): return a < b
                case (.some, .none):           return true
                case (.none, .some):           return false
                case (.none, .none):           return $0.receivedDate < $1.receivedDate
                }
            }
    }

    // MARK: - Waste Expired Stock

    /// Marks all expired lots for a given item as wasted and records transactions.
    /// Returns the total quantity wasted.
    @discardableResult
    func wasteExpiredLots(
        for item: InventoryItem,
        referenceDate: Date = Date()
    ) -> Double {
        guard let modelContext else { return 0 }

        let expiredLots = lots(for: item).filter {
            $0.expiryStatus(referenceDate: referenceDate) == .expired
        }

        var totalWasted = 0.0
        for lot in expiredLots {
            let qty = lot.remainingQuantity
            guard qty > 0 else { continue }

            // Create waste transaction
            let txn = InventoryTransaction(
                item: item,
                transactionType: InventoryMovementType.waste.rawValue,
                quantity: qty,
                costPrice: lot.lotCostPrice,
                notes: "Auto-waste: lot \(lot.lotNumber ?? lot.id.uuidString.prefix(8).description) expired \(lot.expiryDate.map { DateFormatter.shortDate.string(from: $0) } ?? "")",
                branch: item.branch
            )
            modelContext.insert(txn)

            // Drain the lot
            lot.remainingQuantity = 0
            lot.updatedAt = Date()
            lot.isSynced = false

            totalWasted += qty
        }

        // Deduct from item's currentQuantity
        if totalWasted > 0 {
            item.currentQuantity = max(0, item.currentQuantity - totalWasted)
            item.updatedAt = Date()
            item.isSynced = false

            do {
                try modelContext.save()
            } catch {
                print("InventoryExpiryManager: wasteExpiredLots save failed — \(error.localizedDescription)")
            }
        }

        return totalWasted
    }
}

// MARK: - DateFormatter Helper

private extension DateFormatter {
    static let shortDate: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .none
        return df
    }()
}
