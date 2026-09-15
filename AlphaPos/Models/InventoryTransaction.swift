import Foundation
import SwiftData

@Model
final class InventoryTransaction {
    @Attribute(.unique) var id: UUID
    var item: InventoryItem?
    var transactionType: String // Use movementType computed var (InventoryMovementType) for type-safe access
    var quantity: Double
    var costPrice: Double?
    var referenceId: UUID? // Maps to OrderItem ID or Supplier invoice
    var notes: String?
    var branch: Branch

    /// Structured audit reason (GS1 / HACCP compliant). Replaces free-text-only
    /// justifications so reports can group by cause (waste, audit, transfer, …).
    var reasonCode: String?

    /// Tamper-evident signature, stored in its OWN column so `notes` stays
    /// user-editable. See `InventoryAuditSigner`. (ISO 27001 audit trail.)
    var auditSignature: String?

    /// When the stock movement actually happened (sale, waste, receive, etc.).
    /// This is the authoritative business timestamp used by all reports.
    ///
    /// IMPORTANT: `updatedAt` is sync metadata and changes every time the row is
    /// re-uploaded, so it must NOT be used to date a movement — an old waste
    /// entry re-synced today would otherwise appear in today's report. Always
    /// filter/report on `createdAt`.
    var createdAt: Date = Date()
    var businessDateKey: String = ""
    var registerSessionId: UUID?

    // Offline-First Sync Metadata
    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        item: InventoryItem? = nil,
        transactionType: String,
        quantity: Double,
        costPrice: Double? = nil,
        referenceId: UUID? = nil,
        notes: String? = nil,
        branch: Branch,
        createdAt: Date = Date(),
        businessDateKey: String = "",
        registerSessionId: UUID? = nil,
        isSynced: Bool = false,
        isDeleted: Bool = false,
        updatedAt: Date = Date(),
        reasonCode: String? = nil,
        auditSignature: String? = nil
    ) {
        self.id = id
        self.item = item
        self.transactionType = transactionType

        // ── Tamper-evident signature (stored in its own column, NOT in notes) ──
        self.auditSignature = auditSignature ?? InventoryAuditSigner.generateSignature(
            id: id,
            type: transactionType,
            quantity: InventoryTransaction.normalizedQuantity(quantity, for: transactionType),
            costPrice: costPrice,
            referenceId: referenceId,
            notes: notes,
            branchId: branch.id
        )
        self.reasonCode = reasonCode

        // ── Sign normalization (single source of truth) ──────────────────────
        // Historically call sites disagreed on the sign of `quantity`:
        //   • POS sale        → -qtyDeducted        (negative, correct)
        //   • FEFO sell       →  consumed           (positive, WRONG)
        //   • manual waste    → -amount             (negative, correct)
        //   • auto-expiry waste →  qty              (positive, WRONG)
        // which made COGS / waste% / usage come out negative in analytics.
        //
        // We now enforce the convention centrally, based on the movement type,
        // so no call site can store the wrong sign again:
        //   • inbound  (receive, refund_return, transfer_in, opening) → +magnitude
        //   • outbound (sell, waste, return_to_supplier, transfer_out) → -magnitude
        //   • adjust / unknown → keep the caller's signed delta (sign is meaningful)
        self.quantity = InventoryTransaction.normalizedQuantity(quantity, for: transactionType)

        self.costPrice = costPrice
        self.referenceId = referenceId
        self.branch = branch
        self.createdAt = createdAt
        self.businessDateKey = businessDateKey.isEmpty
            ? BusinessDayContext.key(for: createdAt, cutoffHour: branch.businessDayCutoffHour, timeZoneID: branch.timeZoneID)
            : businessDateKey
        self.registerSessionId = registerSessionId
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
    }

    /// Applies the canonical sign convention for a raw quantity given a movement type.
    /// Inbound → positive, Outbound → negative, adjust/unknown → unchanged.
    static func normalizedQuantity(_ raw: Double, for transactionType: String) -> Double {
        guard let movement = InventoryMovementType.from(transactionType) else {
            return raw // unknown type: preserve caller's signed value
        }
        if movement.isInbound  { return  abs(raw) }
        if movement.isOutbound { return -abs(raw) }
        return raw // .adjust — signed delta is meaningful
    }
}

/// Immutable link between a sell movement and the exact lot quantity/cost it consumed.
/// Void/refund restores these rows instead of recalculating from the current recipe.
@Model
final class InventoryLotAllocation {
    @Attribute(.unique) var id: UUID
    var movementId: UUID
    var referenceId: UUID?
    var inventoryItemId: UUID
    var lotId: UUID
    var quantity: Double
    var costPrice: Double
    var createdAt: Date
    var isSynced: Bool

    init(
        id: UUID = UUID(),
        movementId: UUID,
        referenceId: UUID?,
        inventoryItemId: UUID,
        lotId: UUID,
        quantity: Double,
        costPrice: Double,
        createdAt: Date = Date(),
        isSynced: Bool = false
    ) {
        self.id = id
        self.movementId = movementId
        self.referenceId = referenceId
        self.inventoryItemId = inventoryItemId
        self.lotId = lotId
        self.quantity = abs(quantity)
        self.costPrice = costPrice
        self.createdAt = createdAt
        self.isSynced = isSynced
    }
}

@MainActor
enum InventoryReversalService {
    private struct Key: Hashable {
        let referenceId: UUID
        let itemId: UUID
    }

    /// Restores exactly what the original sell ledger rows consumed.
    /// It is idempotent per movement type + reference + item.
    @discardableResult
    static func reverse(
        referenceIds: Set<UUID>,
        as reversalType: InventoryMovementType,
        notes: String,
        in context: ModelContext
    ) -> Int {
        guard reversalType == .void || reversalType == .refundReturn,
              !referenceIds.isEmpty else { return 0 }

        let transactions = (try? context.fetch(FetchDescriptor<InventoryTransaction>())) ?? []
        let sells = transactions.filter {
            !$0.isDeleted &&
            $0.transactionType == InventoryMovementType.sell.rawValue &&
            $0.referenceId.map(referenceIds.contains) == true &&
            $0.item != nil
        }
        let alreadyReversed = Set(transactions.compactMap { transaction -> Key? in
            guard !transaction.isDeleted,
                  transaction.transactionType == reversalType.rawValue,
                  let referenceId = transaction.referenceId,
                  let itemId = transaction.item?.id else { return nil }
            return Key(referenceId: referenceId, itemId: itemId)
        })
        let allocations = (try? context.fetch(FetchDescriptor<InventoryLotAllocation>())) ?? []
        let lots = (try? context.fetch(FetchDescriptor<InventoryLot>())) ?? []
        let lotsById = Dictionary(uniqueKeysWithValues: lots.map { ($0.id, $0) })
        let grouped = Dictionary(grouping: sells) {
            Key(referenceId: $0.referenceId!, itemId: $0.item!.id)
        }
        var restored = 0

        for (key, movements) in grouped where !alreadyReversed.contains(key) {
            guard let item = movements.first?.item else { continue }
            let movementIds = Set(movements.map(\.id))
            let originalAllocations = allocations.filter { movementIds.contains($0.movementId) }
            let quantity = movements.reduce(0) { $0 + abs($1.quantity) }

            if originalAllocations.isEmpty {
                // Legacy movements did not preserve allocation; reverse-FEFO is the safest fallback.
                InventoryExpiryManager.shared(for: context).restoreFEFO(item: item, quantity: quantity)
            } else {
                for allocation in originalAllocations {
                    guard let lot = lotsById[allocation.lotId] else { continue }
                    lot.remainingQuantity = min(lot.initialQuantity, lot.remainingQuantity + allocation.quantity)
                    lot.isSynced = false
                    lot.updatedAt = Date()
                }
            }

            item.currentQuantity += quantity
            item.isSynced = false
            item.updatedAt = Date()
            let totalCost = movements.reduce(0) { $0 + abs($1.quantity) * ($1.costPrice ?? item.costPrice) }
            context.insert(InventoryTransaction(
                item: item,
                movement: reversalType,
                quantity: quantity,
                costPrice: quantity > 0 ? totalCost / quantity : item.costPrice,
                referenceId: key.referenceId,
                notes: notes,
                branch: (movements.first?.branch ?? item.branch)!,
                reasonCode: reversalType.rawValue
            ))
            restored += 1
        }
        return restored
    }
}

// MARK: - Convenience Init

extension InventoryTransaction {
    /// Convenience initialiser that accepts InventoryMovementType directly.
    /// This is the preferred init for all new call sites.
    convenience init(
        id: UUID = UUID(),
        item: InventoryItem? = nil,
        movement: InventoryMovementType,
        quantity: Double,
        costPrice: Double? = nil,
        referenceId: UUID? = nil,
        notes: String? = nil,
        branch: Branch,
        createdAt: Date = Date(),
        isSynced: Bool = false,
        isDeleted: Bool = false,
        updatedAt: Date = Date(),
        reasonCode: String? = nil,
        auditSignature: String? = nil
    ) {
        self.init(
            id: id,
            item: item,
            transactionType: movement.rawValue,
            quantity: quantity,
            costPrice: costPrice,
            referenceId: referenceId,
            notes: notes,
            branch: branch,
            createdAt: createdAt,
            isSynced: isSynced,
            isDeleted: isDeleted,
            updatedAt: updatedAt,
            reasonCode: reasonCode,
            auditSignature: auditSignature
        )
    }

    /// Absolute movement magnitude, sign-independent — convenient for reports
    /// that always want a positive quantity (COGS, waste totals, usage charts).
    var magnitude: Double { abs(quantity) }
}
