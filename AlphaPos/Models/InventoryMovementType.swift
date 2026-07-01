// InventoryMovementType.swift
// AlphaPos — Type-safe Inventory Transaction Movement Enum
//
// Replaces all raw String literals for transactionType throughout the app.
// Backward-compatible: rawValue matches existing Supabase "transaction_type" strings.
//
// ─────────────────────────────────────────────────────────────────────────────
// Migration strategy:
//   1. InventoryTransaction.transactionType field stays as String in SwiftData
//      (SwiftData doesn't yet support Enum @Attribute reliably across migrations).
//   2. A computed var `movementType: InventoryMovementType` gives type-safe access.
//   3. All call sites switch from "receive" strings to .receive enum cases.
//   4. Supabase column stays VARCHAR — rawValues are unchanged, no DB migration needed.
// ─────────────────────────────────────────────────────────────────────────────

import Foundation

// MARK: - InventoryMovementType

/// Type-safe enum for all inventory transaction movement types.
/// rawValue = Supabase `transaction_type` column value (no DB migration required).
enum InventoryMovementType: String, Codable, CaseIterable, Identifiable {

    // ── Core inbound ──────────────────────────────────────────────────────────
    /// Stock received from a supplier (creates a new InventoryLot for FEFO).
    case receive            = "receive"

    // ── Core outbound ─────────────────────────────────────────────────────────
    /// Stock consumed by a sold menu item (FEFO lot deduction).
    case sell               = "sell"
    /// Stock wasted, spoiled, or discarded (includes expired lot auto-waste).
    case waste              = "waste"

    // ── Adjustments ───────────────────────────────────────────────────────────
    /// Manual stock count correction (positive or negative delta).
    case adjust             = "adjust"
    /// Customer return: refund that puts stock back.
    case refundReturn       = "refund_return"
    /// Goods returned to supplier (reduces stock, creates a credit).
    case returnToSupplier   = "return_to_supplier"

    // ── Branch transfers ─────────────────────────────────────────────────────
    /// Stock transferred OUT from this branch.
    case transferOut        = "transfer_out"
    /// Stock transferred IN to this branch.
    case transferIn         = "transfer_in"

    // ── Opening balance ───────────────────────────────────────────────────────
    /// Initial stock entry when setting up an item for the first time.
    case opening            = "opening"

    // MARK: - Identifiable
    var id: String { rawValue }

    // MARK: - Display

    var displayName: String {
        switch self {
        case .receive:          return "รับของ"
        case .sell:             return "ขาย"
        case .waste:            return "ทิ้ง/เสีย"
        case .adjust:           return "ปรับสต็อก"
        case .refundReturn:     return "รับคืน"
        case .returnToSupplier: return "คืน Supplier"
        case .transferOut:      return "โอนออก"
        case .transferIn:       return "โอนเข้า"
        case .opening:          return "ยอดเปิด"
        }
    }

    var systemImage: String {
        switch self {
        case .receive:          return "arrow.down.circle.fill"
        case .sell:             return "cart.fill"
        case .waste:            return "trash.fill"
        case .adjust:           return "slider.horizontal.3"
        case .refundReturn:     return "arrow.uturn.left.circle.fill"
        case .returnToSupplier: return "shippingbox.fill"
        case .transferOut:      return "arrow.right.circle.fill"
        case .transferIn:       return "arrow.left.circle.fill"
        case .opening:          return "archivebox.fill"
        }
    }

    /// True for types that ADD stock (increase currentQuantity).
    var isInbound: Bool {
        switch self {
        case .receive, .refundReturn, .transferIn, .opening: return true
        default: return false
        }
    }

    /// True for types that REMOVE stock (decrease currentQuantity).
    var isOutbound: Bool {
        switch self {
        case .sell, .waste, .returnToSupplier, .transferOut: return true
        default: return false
        }
    }

    /// Sign multiplier for quantity display (+/-).
    var sign: Double { isInbound ? 1 : isOutbound ? -1 : 0 }

    // MARK: - Safe init from String

    /// Returns the matching case, or nil if the string is unrecognised.
    static func from(_ raw: String) -> InventoryMovementType? {
        InventoryMovementType(rawValue: raw)
    }

    /// Returns the matching case, or `.adjust` as a safe fallback for unknown values.
    static func fromOrAdjust(_ raw: String) -> InventoryMovementType {
        InventoryMovementType(rawValue: raw) ?? .adjust
    }
}

#if !TEST_RUNNER
import SwiftData

extension InventoryTransaction {
    /// Type-safe accessor for transactionType string.
    /// Reading: parsed from rawValue (falls back to .adjust for unknown strings).
    /// Writing: updates the underlying String field.
    var movementType: InventoryMovementType {
        get { InventoryMovementType.fromOrAdjust(transactionType) }
        set { transactionType = newValue.rawValue }
    }
}
#endif
