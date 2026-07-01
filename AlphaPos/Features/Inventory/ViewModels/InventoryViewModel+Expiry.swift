// InventoryViewModel+Expiry.swift
// AlphaPos — Extension: Expiry Date & FEFO Integration Patch
//
// Drop this file alongside InventoryViewModel.swift.
// NO changes required to existing InventoryViewModel functions —
// these extension methods augment the existing class.
//
// ─────────────────────────────────────────────────────────────────────────────
// Integration steps required in the main files:
//
//  [1] InventoryItem.swift — add 2 optional fields:
//       var expiryWarningDays: Int    = 7
//       var expiryCriticalDays: Int   = 3
//
//  [2] InventoryViewModel.processReceive() — call registerLot() after save:
//       expiryManager.registerLot(
//           for: item,
//           quantity: amount,
//           costPrice: newUnitCost,
//           expiryDate: expiryDate,       // from ReceiveStockView
//           lotNumber: lotNumber,          // from ReceiveStockView
//           sourceTransactionId: txn.id
//       )
//
//  [3] InventoryViewModel.addInventoryItem() — no change needed (no stock added at creation).
//
//  [4] ReceiveStockView — add ExpiryDatePicker binding (see comments below).
//
//  [5] InventoryView / inventoryStatsHeader — embed ExpiryAlertDashboard.
// ─────────────────────────────────────────────────────────────────────────────

import Foundation
import SwiftData

extension InventoryViewModel {

    // MARK: - Shared ExpiryManager

    /// Lazily vended manager; set modelContext before first use.
    @MainActor
    var expiryManager: InventoryExpiryManager {
        // Store in a computed-property backed by a static cache keyed by modelContext identity.
        // This avoids adding stored properties to @Observable class via extension.
        guard let ctx = modelContext else {
            return InventoryExpiryManager()
        }
        return InventoryExpiryManager.shared(for: ctx)
    }

    // MARK: - processReceive with Expiry (Drop-in replacement signature)

    /// Enhanced receive that also creates an InventoryLot for FEFO tracking.
    /// Call this instead of `processReceive` when the UI provides expiry info.
    @MainActor
    func processReceiveWithExpiry(
        item: InventoryItem,
        amountString: String,
        costString: String,
        notes: String,
        expiryDate: Date?,
        lotNumber: String?
    ) {
        guard let modelContext = modelContext,
              let amount = Double(amountString), amount > 0 else { return }

        let newUnitCost = Double(costString) ?? item.costPrice

        // ── WAC calculation (same as existing processReceive) ──────────────────
        let oldQty  = max(item.currentQuantity, 0.0)
        let oldCost = item.costPrice
        let totalQty = oldQty + amount
        if totalQty > 0 {
            item.costPrice = ((oldQty * oldCost) + (amount * newUnitCost)) / totalQty
        } else {
            item.costPrice = newUnitCost
        }
        item.currentQuantity += amount
        item.updatedAt = Date()
        item.isSynced  = false

        // ── Transaction record ─────────────────────────────────────────────────
        let txn = InventoryTransaction(
            item: item,
            transactionType: InventoryMovementType.receive.rawValue,
            quantity: amount,
            costPrice: newUnitCost,
            notes: notes.isEmpty ? "Supplier delivery receive" : notes,
            branch: item.branch
        )
        modelContext.insert(txn)

        // ── Lot registration (new) ─────────────────────────────────────────────
        let lot = InventoryLot(
            inventoryItem: item,
            branch: item.branch,
            lotNumber: lotNumber?.isEmpty == true ? nil : lotNumber,
            receivedDate: Date(),
            expiryDate: expiryDate,
            initialQuantity: amount,
            remainingQuantity: amount,
            lotCostPrice: newUnitCost,
            sourceTransactionId: txn.id
        )
        modelContext.insert(lot)

        // ── Save ───────────────────────────────────────────────────────────────
        do {
            try modelContext.save()
        } catch {
            print("InventoryViewModel+Expiry: save failed — \(error.localizedDescription)")
        }

        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }

    // MARK: - FEFO Consumption (called when order items are sold)

    /// Call this from the POS checkout flow to consume stock FEFO.
    /// Updates `item.currentQuantity` and drains lots correctly.
    @MainActor
    @discardableResult
    func consumeStockFEFO(
        item: InventoryItem,
        quantity: Double,
        orderId: UUID? = nil
    ) -> FEFOConsumptionResult {
        guard let modelContext = modelContext else {
            return FEFOConsumptionResult(consumed: [], unfulfilled: quantity)
        }

        let result = expiryManager.consumeFEFO(item: item, quantity: quantity)

        // Update item's currentQuantity
        let consumed = quantity - result.unfulfilled
        item.currentQuantity = max(0, item.currentQuantity - consumed)
        item.updatedAt = Date()
        item.isSynced  = false

        // Write one consolidated "sell" transaction
        if consumed > 0 {
            let txn = InventoryTransaction(
                item: item,
                transactionType: InventoryMovementType.sell.rawValue,
                quantity: consumed,
                costPrice: result.consumed.isEmpty ? item.costPrice
                    : result.totalCOGS / consumed,
                referenceId: orderId,
                notes: result.includedExpiredStock ? "⚠️ Consumed expired stock" : nil,
                branch: item.branch
            )
            modelContext.insert(txn)
        }

        do {
            try modelContext.save()
        } catch {
            print("InventoryViewModel+Expiry: consumeStockFEFO save failed — \(error.localizedDescription)")
        }

        return result
    }

    // MARK: - Expiry Stats (for stats header badge)

    @MainActor
    func expiryAlertCount(branch: Branch?) -> (expired: Int, critical: Int, warning: Int) {
        let alerts = expiryManager.getExpiringAlerts(branch: branch)
        return (
            expired:  alerts.filter { $0.status == .expired }.count,
            critical: alerts.filter { $0.status == .critical }.count,
            warning:  alerts.filter { $0.status == .warning }.count
        )
    }
}

// MARK: - InventoryExpiryManager shared instance helper

extension InventoryExpiryManager {
    private static var instances: [ObjectIdentifier: InventoryExpiryManager] = [:]

    @MainActor
    static func shared(for context: ModelContext) -> InventoryExpiryManager {
        let key = ObjectIdentifier(context)
        if let existing = instances[key] { return existing }
        let manager = InventoryExpiryManager(modelContext: context)
        instances[key] = manager
        return manager
    }
}

// MARK: - ReceiveStockView Integration Notes
//
// In ReceiveStockView, add these @State vars and pass them to processReceiveWithExpiry:
//
//   @State private var hasExpiry = false
//   @State private var expiryDate = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
//   @State private var lotNumber = ""
//
// In the ScrollView body, after the "incoming_stock" card, add:
//
//   VStack(alignment: .leading, spacing: APSpacing.sm) {
//       sectionHeader("expiry_lot_tracking".t)
//       ExpiryDatePicker(hasExpiry: $hasExpiry, expiryDate: $expiryDate, lotNumber: $lotNumber)
//   }
//   .apCard()
//
// In the save action (ToolbarItem .confirmationAction), replace processReceive call with:
//
//   viewModel.processReceiveWithExpiry(
//       item: item,
//       amountString: amountString,
//       costString: costString,
//       notes: noteText,
//       expiryDate: hasExpiry ? expiryDate : nil,
//       lotNumber: hasExpiry ? lotNumber : nil
//   )
//   onComplete()
//
// ─────────────────────────────────────────────────────────────────────────────
// InventoryView Integration Notes
//
// 1. Add to InventoryView @State:
//      @State private var expiryManager = InventoryExpiryManager()
//
// 2. In .onAppear:
//      expiryManager.modelContext = modelContext
//
// 3. In inventoryPanel, below inventoryStatsHeader:
//      ExpiryAlertDashboard(expiryManager: expiryManager, activeBranch: activeBranch)
//
// 4. In the stats header, add an expiry stat card:
//      let counts = viewModel.expiryAlertCount(branch: activeBranch)
//      if counts.expired > 0 || counts.critical > 0 {
//          statCard(
//              title: "หมดอายุ/วิกฤต",
//              value: "\(counts.expired + counts.critical)",
//              icon: "clock.badge.exclamationmark.fill",
//              color: counts.expired > 0 ? Color.appRose : .orange
//          )
//      }
//
// 5. In sortItems() inside InventoryView, add a new SortKey case:
//      case .expiry:
//          return items.sorted {
//              let a = expiryManager.lots(for: $0).first?.expiryDate
//              let b = expiryManager.lots(for: $1).first?.expiryDate
//              switch (a, b) {
//              case let (.some(da), .some(db)): return da < db
//              case (.some, .none): return true
//              case (.none, .some): return false
//              default: return $0.name < $1.name
//              }
//          }
//
// 6. In EditStockItemView / InventoryItem detail, add LotListView:
//      LotListView(item: item, expiryManager: expiryManager)
//          .padding(.horizontal, APSpacing.md)
