// UnitOfMeasure.swift
// AlphaPos — Unit of Measure normalization (GS1 / ISO 8000 best practice)
//
// Inventories are often recorded in mixed units ("kg", "g", "ml", "liter",
// "piece", "can", …). For accurate cross-item reporting (COGS, turnover,
// reorder math) every quantity must be comparable, so we normalise to a single
// base unit per measurement *family*:
//   • Mass     → gram (g)
//   • Volume   → millilitre (ml)
//   • Count    → piece (ea)
// Conversions are exact factors; cross-family conversions are intentionally
// unsupported (you cannot convert kg → ml) and return nil.

import Foundation

enum UnitOfMeasure: String, Codable, CaseIterable, Identifiable {
    case kg, g, mg
    case liter, ml
    case piece, can, bottle, box, pack

    var id: String { rawValue }

    /// Family this unit belongs to.
    enum Family: String { case mass, volume, count }

    var family: Family {
        switch self {
        case .kg, .g, .mg:                 return .mass
        case .liter, .ml:                 return .volume
        case .piece, .can, .bottle, .box, .pack: return .count
        }
    }

    /// Factor to convert ONE of this unit into ONE base unit of its family.
    var toBaseFactor: Double {
        switch self {
        case .kg:     return 1000
        case .g:      return 1
        case .mg:     return 0.001
        case .liter:  return 1000
        case .ml:     return 1
        case .piece, .can, .bottle, .box, .pack: return 1
        }
    }

    /// Base unit label for the family.
    var baseUnit: String {
        switch family {
        case .mass:   return "g"
        case .volume: return "ml"
        case .count:  return "ea"
        }
    }

    /// Human-readable label (Thai-aware where useful).
    var displayName: String {
        switch self {
        case .kg:     return "กิโลกรัม (kg)"
        case .g:      return "กรัม (g)"
        case .mg:     return "มิลลิกรัม (mg)"
        case .liter:  return "ลิตร (L)"
        case .ml:     return "มิลลิลิตร (ml)"
        case .piece:  return "ชิ้น (pc)"
        case .can:    return "กระป๋อง (can)"
        case .bottle: return "ขวด (btl)"
        case .box:    return "กล่อง (box)"
        case .pack:   return "แพ็ค (pack)"
        }
    }

    /// Parse a free-text unit string (case-insensitive, tolerant of "KG"/"Kg").
    static func parse(_ raw: String?) -> UnitOfMeasure? {
        guard let raw else { return nil }
        let lowered = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return UnitOfMeasure.allCases.first { $0.rawValue == lowered }
            ?? UnitOfMeasure.allCases.first { $0.displayName.lowercased().contains(lowered) }
    }

    /// User-friendly label for any unit string (falling back gracefully).
    static func displayLabel(for raw: String?, isThai: Bool = true) -> String {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return isThai ? "เลือกหน่วย" : "Select unit"
        }
        if let uom = parse(raw) {
            return uom.displayName
        }
        let lower = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch lower {
        case "bag", "ถุง": return isThai ? "ถุง (bag)" : "Bag"
        case "cup", "แก้ว", "ถ้วย": return isThai ? "ถ้วย/แก้ว (cup)" : "Cup"
        case "dish", "จาน", "ที่": return isThai ? "จาน (dish)" : "Dish"
        case "tbsp", "ช้อนโต๊ะ": return isThai ? "ช้อนโต๊ะ (tbsp)" : "tbsp"
        case "tsp", "ช้อนชา": return isThai ? "ช้อนชา (tsp)" : "tsp"
        default: return raw
        }
    }

    /// Returns compatible units within the same measurement family.
    static func compatibleUnits(for raw: String?) -> [String] {
        guard let uom = parse(raw) else {
            return raw.map { [$0].filter { !$0.isEmpty } } ?? []
        }
        switch uom.family {
        case .mass:
            return ["g", "kg", "mg"]
        case .volume:
            return ["ml", "liter"]
        case .count:
            return ["piece", "can", "bottle", "box", "pack", "bag", "cup", "dish"]
        }
    }

    /// Convert `quantity` expressed in this unit into the family base unit.
    func toBase(_ quantity: Double) -> Double { quantity * toBaseFactor }

    /// Convert `baseQuantity` (in the family base unit) back into this unit.
    func fromBase(_ baseQuantity: Double) -> Double { baseQuantity / toBaseFactor }

    /// Convert between two units of the *same* family.
    /// Returns nil if the families differ (invalid conversion).
    static func convert(_ quantity: Double, from: UnitOfMeasure, to: UnitOfMeasure) -> Double? {
        guard from.family == to.family else { return nil }
        return to.fromBase(from.toBase(quantity))
    }
}

enum StockPackagePriceMode: String, CaseIterable, Identifiable {
    case total
    case perPack

    var id: String { rawValue }
}

struct StockPackageCalculation: Equatable {
    let receivedQuantity: Double
    let unitCost: Double
    let totalCost: Double
}

/// Keeps mass and volume inventory in their smallest practical unit. Recipe
/// quantities are commonly expressed in grams / millilitres, so persisting a
/// unit price in `kg` or `liter` would otherwise make a direct cost formula
/// 1,000 times too large.
struct NormalizedInventoryMeasurement: Equatable {
    let unit: String
    let quantity: Double
    let unitCost: Double
}

enum InventoryUnitNormalization {
    /// Normalises mass to grams and volume to millilitres. Count-based units
    /// remain unchanged because a can, box, or pack has no universal piece
    /// conversion without packaging metadata.
    static func normalize(quantity: Double, unit: String, unitCost: Double) -> NormalizedInventoryMeasurement {
        guard let sourceUnit = UnitOfMeasure.parse(unit) else {
            return .init(unit: unit, quantity: quantity, unitCost: unitCost)
        }

        let targetUnit: UnitOfMeasure
        switch sourceUnit.family {
        case .mass: targetUnit = .g
        case .volume: targetUnit = .ml
        case .count: targetUnit = sourceUnit
        }

        return convert(quantity: quantity, unit: sourceUnit, unitCost: unitCost, to: targetUnit)
    }

    static func convert(
        quantity: Double,
        unit sourceUnit: UnitOfMeasure,
        unitCost: Double,
        to targetUnit: UnitOfMeasure
    ) -> NormalizedInventoryMeasurement {

        guard let convertedQuantity = UnitOfMeasure.convert(quantity, from: sourceUnit, to: targetUnit),
              let quantityPerEnteredUnit = UnitOfMeasure.convert(1, from: sourceUnit, to: targetUnit),
              quantityPerEnteredUnit > 0 else {
            return .init(unit: sourceUnit.rawValue, quantity: quantity, unitCost: unitCost)
        }

        return .init(
            unit: targetUnit.rawValue,
            quantity: convertedQuantity,
            unitCost: unitCost / quantityPerEnteredUnit
        )
    }
}

/// Converts a supplier's package-level price into the inventory item's unit.
/// The result can be passed directly to the existing receiving/WAC flow.
enum StockPackagePricing {
    static func calculate(
        packCount: Double,
        quantityPerPack: Double,
        packageUnit: UnitOfMeasure,
        inventoryUnit: UnitOfMeasure,
        enteredPrice: Double,
        priceMode: StockPackagePriceMode
    ) -> StockPackageCalculation? {
        guard packCount.isFinite, packCount > 0,
              quantityPerPack.isFinite, quantityPerPack > 0,
              enteredPrice.isFinite, enteredPrice >= 0,
              packageUnit.family == inventoryUnit.family,
              let receivedQuantity = UnitOfMeasure.convert(
                packCount * quantityPerPack,
                from: packageUnit,
                to: inventoryUnit
              ),
              receivedQuantity.isFinite, receivedQuantity > 0 else {
            return nil
        }

        let totalCost = priceMode == .total ? enteredPrice : enteredPrice * packCount
        guard totalCost.isFinite else { return nil }

        return StockPackageCalculation(
            receivedQuantity: receivedQuantity,
            unitCost: totalCost / receivedQuantity,
            totalCost: totalCost
        )
    }
}

// MARK: - Smart Unit Formatter (Auto-scaling g -> kg, ml -> L for human readability)

struct FormattedStockUnit {
    let primaryText: String
    let secondaryText: String?
    let fullText: String
}

enum SmartUnitFormatter {
    /// Formats a quantity and unit intelligently.
    /// If quantity >= 1,000 g -> primary is "X.XX kg", secondary is "(X,XXX g)"
    /// If quantity >= 1,000 ml -> primary is "X.XX L", secondary is "(X,XXX ml)"
    /// Otherwise -> primary is "X.XX unit", secondary is nil
    static func format(quantity: Double, unit: String) -> FormattedStockUnit {
        guard quantity.isFinite else {
            return FormattedStockUnit(primaryText: "0", secondaryText: nil, fullText: "0 \(unit)")
        }

        let parsed = UnitOfMeasure.parse(unit)
        let absQty = abs(quantity)

        if parsed == .g && absQty >= 1000.0 {
            let inKg = quantity / 1000.0
            let kgFormatted = inKg.formatted(.number.precision(.fractionLength(0...2)))
            let gFormatted = quantity.formatted(.number.precision(.fractionLength(0...1)))
            return FormattedStockUnit(
                primaryText: "\(kgFormatted) kg",
                secondaryText: "(\(gFormatted) g)",
                fullText: "\(kgFormatted) kg (\(gFormatted) g)"
            )
        } else if (parsed == .ml || unit.lowercased() == "ml") && absQty >= 1000.0 {
            let inL = quantity / 1000.0
            let lFormatted = inL.formatted(.number.precision(.fractionLength(0...2)))
            let mlFormatted = quantity.formatted(.number.precision(.fractionLength(0...1)))
            return FormattedStockUnit(
                primaryText: "\(lFormatted) L",
                secondaryText: "(\(mlFormatted) ml)",
                fullText: "\(lFormatted) L (\(mlFormatted) ml)"
            )
        } else {
            let formatted = quantity.formatted(.number.precision(.fractionLength(0...2)))
            return FormattedStockUnit(
                primaryText: "\(formatted) \(unit)",
                secondaryText: nil,
                fullText: "\(formatted) \(unit)"
            )
        }
    }
}

// MARK: - Multi-Tier Packaging Hierarchy (e.g. Crate -> Pack -> Bag -> Grams)

enum PackagingTierLevel: String, CaseIterable, Identifiable {
    case crate = "crate"       // ลัง
    case pack = "pack"         // แพ็ก
    case individual = "piece"  // ห่อ / ชิ้น / ถุง

    var id: String { rawValue }

    func title(isThai: Bool) -> String {
        switch self {
        case .crate: return isThai ? "ลัง (Crate/Box)" : "Crate / Box"
        case .pack: return isThai ? "แพ็ก (Pack)" : "Pack"
        case .individual: return isThai ? "ห่อ / ชิ้น (Bag/Piece)" : "Bag / Piece"
        }
    }
}

struct MultiTierPackagingCalculation {
    let totalBaseQuantity: Double   // e.g. 18,000 g
    let unitCost: Double            // e.g. 0.05 ฿/g
    let totalCost: Double           // e.g. 900 ฿
    let summaryText: String         // "2 ลัง = 24 แพ็ก = 72 ห่อ (36,000 g)"

    static func calculate(
        level: PackagingTierLevel,
        enteredCount: Double,              // จำนวนที่รับตามระดับที่เลือก
        packsPerCrate: Double,             // จำนวนแพ็กต่อลัง (e.g. 12)
        piecesPerPack: Double,             // จำนวนห่อต่อแพ็ก (e.g. 3)
        pieceSize: Double,                 // ปริมาณ/น้ำหนักต่อห่อ (e.g. 500)
        pieceUnit: UnitOfMeasure,          // หน่วยของห่อ (e.g. g or ml or piece)
        inventoryUnit: UnitOfMeasure,      // หน่วยในคลัง (e.g. g)
        enteredPrice: Double,              // ราคาที่ซื้อมา
        priceMode: StockPackagePriceMode,  // ราคารวม หรือ ราคาต่อหน่วยที่เลือก
        isThai: Bool = true
    ) -> MultiTierPackagingCalculation? {
        guard enteredCount > 0, enteredCount.isFinite,
              packsPerCrate > 0, packsPerCrate.isFinite,
              piecesPerPack > 0, piecesPerPack.isFinite,
              pieceSize > 0, pieceSize.isFinite,
              enteredPrice >= 0, enteredPrice.isFinite,
              pieceUnit.family == inventoryUnit.family else {
            return nil
        }

        // 1. Calculate total individual pieces (ห่อ)
        let totalPieces: Double
        let summary: String

        switch level {
        case .crate:
            let totalPacks = enteredCount * packsPerCrate
            totalPieces = totalPacks * piecesPerPack
            let countStr = enteredCount.formatted(.number.precision(.fractionLength(0...1)))
            let packsStr = totalPacks.formatted(.number.precision(.fractionLength(0...1)))
            let piecesStr = totalPieces.formatted(.number.precision(.fractionLength(0...1)))
            summary = isThai
                ? "\(countStr) ลัง (\(packsStr) แพ็ก / \(piecesStr) ห่อ)"
                : "\(countStr) crates (\(packsStr) packs / \(piecesStr) pcs)"

        case .pack:
            totalPieces = enteredCount * piecesPerPack
            let countStr = enteredCount.formatted(.number.precision(.fractionLength(0...1)))
            let piecesStr = totalPieces.formatted(.number.precision(.fractionLength(0...1)))
            summary = isThai
                ? "\(countStr) แพ็ก (\(piecesStr) ห่อ)"
                : "\(countStr) packs (\(piecesStr) pcs)"

        case .individual:
            totalPieces = enteredCount
            let piecesStr = totalPieces.formatted(.number.precision(.fractionLength(0...1)))
            summary = isThai ? "\(piecesStr) ห่อ/ชิ้น" : "\(piecesStr) pcs"
        }

        // 2. Convert total pieces * pieceSize to target inventoryUnit
        guard let totalBaseQty = UnitOfMeasure.convert(
            totalPieces * pieceSize,
            from: pieceUnit,
            to: inventoryUnit
        ), totalBaseQty > 0, totalBaseQty.isFinite else {
            return nil
        }

        // 3. Compute costs
        let totalCost = priceMode == .total ? enteredPrice : enteredPrice * enteredCount
        guard totalCost.isFinite else { return nil }

        let unitCost = totalCost / totalBaseQty

        return MultiTierPackagingCalculation(
            totalBaseQuantity: totalBaseQty,
            unitCost: unitCost,
            totalCost: totalCost,
            summaryText: summary
        )
    }
}
