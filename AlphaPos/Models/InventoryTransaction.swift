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
    var branch: Branch?

    // Offline-First Sync Metadata
    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date

    init(id: UUID = UUID(), item: InventoryItem? = nil, transactionType: String, quantity: Double, costPrice: Double? = nil, referenceId: UUID? = nil, notes: String? = nil, branch: Branch? = nil, isSynced: Bool = false, isDeleted: Bool = false, updatedAt: Date = Date()) {
        self.id = id
        self.item = item
        self.transactionType = transactionType
        self.quantity = quantity
        self.costPrice = costPrice
        self.referenceId = referenceId
        self.branch = branch
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt

        let signature = InventoryAuditSigner.generateSignature(
            id: id,
            type: transactionType,
            quantity: quantity,
            costPrice: costPrice,
            referenceId: referenceId,
            notes: notes,
            branchId: branch?.id
        )
        self.notes = InventoryAuditSigner.appendSignatureToNotes(notes: notes, signature: signature)
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
        branch: Branch? = nil,
        isSynced: Bool = false,
        isDeleted: Bool = false,
        updatedAt: Date = Date()
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
            isSynced: isSynced,
            isDeleted: isDeleted,
            updatedAt: updatedAt
        )
    }
}
