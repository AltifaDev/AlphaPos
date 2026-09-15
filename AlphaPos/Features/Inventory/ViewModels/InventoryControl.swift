// InventoryControl.swift
// AlphaPos — ABC Analysis (Pareto) & Cycle-Count Scheduling
//
// International inventory-management practice:
//   • ABC analysis ranks items by annual usage value so management attention and
//     stock-check frequency are focused where the money is (A = ~80% of value,
//     B = next ~15%, C = remaining ~5%).
//   • Cycle counting replaces annual wall-to-wall stocktakes with frequent,
//     risk-based counts — A items counted often, C items rarely.

import Foundation
import SwiftData

// MARK: - ABC Class

enum InventoryABCClass: String, Codable, CaseIterable, Identifiable {
    case a = "A"
    case b = "B"
    case c = "C"

    var id: String { rawValue }

    /// Recommended count interval (days) per class.
    var defaultFrequencyDays: Int {
        switch self { case .a: return 7; case .b: return 30; case .c: return 90 }
    }

    var displayName: String {
        switch self { case .a: return "A (สูงสุด)"; case .b: return "B (ปานกลาง)"; case .c: return "C (ต่ำสุด)" }
    }
}

// MARK: - ABC Classification

struct ABCValuedItem {
    let item: InventoryItem
    let annualUsageValue: Double
}

enum InventoryABC {
    /// Classify items by annual usage value using the standard 80/15/5 Pareto split.
    /// Items with zero/negative value are assigned class C.
    static func classify(_ items: [ABCValuedItem]) -> [UUID: InventoryABCClass] {
        let positive = items.filter { $0.annualUsageValue > 0 }
        let total = positive.reduce(0.0) { $0 + $1.annualUsageValue }
        guard total > 0 else {
            return Dictionary(uniqueKeysWithValues: items.map { ($0.item.id, InventoryABCClass.c) })
        }

        let sorted = positive.sorted { $0.annualUsageValue > $1.annualUsageValue }
        var cumulative = 0.0
        var result: [UUID: InventoryABCClass] = [:]

        for valued in sorted {
            cumulative += valued.annualUsageValue
            let pct = cumulative / total
            let cls: InventoryABCClass = pct <= 0.80 ? .a : pct <= 0.95 ? .b : .c
            result[valued.item.id] = cls
        }

        // Zero-value items → C
        for valued in items where valued.annualUsageValue <= 0 {
            result[valued.item.id] = .c
        }
        return result
    }
}

// MARK: - Cycle Count Schedule (SwiftData)

@Model
final class CycleCountSchedule {
    @Attribute(.unique) var id: UUID
    var inventoryItem: InventoryItem?
    var branch: Branch?

    var abcClass: String            // "A" | "B" | "C"
    var frequencyDays: Int          // how often to count
    var lastCountDate: Date?
    var nextDueDate: Date

    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        inventoryItem: InventoryItem? = nil,
        branch: Branch? = nil,
        abcClass: InventoryABCClass,
        frequencyDays: Int? = nil,
        lastCountDate: Date? = nil,
        nextDueDate: Date = Date(),
        isSynced: Bool = false,
        isDeleted: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.inventoryItem = inventoryItem
        self.branch = branch
        self.abcClass = abcClass.rawValue
        self.frequencyDays = frequencyDays ?? abcClass.defaultFrequencyDays
        self.lastCountDate = lastCountDate
        self.nextDueDate = nextDueDate
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
    }

    var abc: InventoryABCClass { InventoryABCClass(rawValue: abcClass) ?? .c }
}

// MARK: - Cycle Count Manager

@MainActor
final class CycleCountManager {
    var modelContext: ModelContext?

    init(modelContext: ModelContext? = nil) { self.modelContext = modelContext }

    /// Recompute ABC class + next due date for every active item in a branch and
    /// upsert its CycleCountSchedule. `annualUsageValue` is typically the item's
    /// yearly COGS contribution (usage qty × cost price).
    func regenerateSchedules(
        branch: Branch?,
        annualUsageValues: [UUID: Double]
    ) {
        guard let modelContext else { return }

        let itemDesc = FetchDescriptor<InventoryItem>(
            predicate: #Predicate<InventoryItem> { $0.isDeleted == false }
        )
        guard let items = try? modelContext.fetch(itemDesc) else { return }

        let branchId = branch?.id
        let valued = items.compactMap { item -> ABCValuedItem? in
            guard branchId == nil || item.branch?.id == branchId else { return nil }
            return ABCValuedItem(item: item, annualUsageValue: annualUsageValues[item.id] ?? 0)
        }

        let classes = InventoryABC.classify(valued)

        // Preload existing schedules keyed by item id.
        let schedDesc = FetchDescriptor<CycleCountSchedule>(
            predicate: #Predicate<CycleCountSchedule> { $0.isDeleted == false }
        )
        let existing = (try? modelContext.fetch(schedDesc)) ?? []
        let byItem = Dictionary(uniqueKeysWithValues: existing.map { ($0.inventoryItem?.id, $0) })

        let now = Date()
        for item in items where branchId == nil || item.branch?.id == branchId {
            guard let cls = classes[item.id] else { continue }
            let freq = cls.defaultFrequencyDays

            if let sched = byItem[item.id] {
                sched.abcClass = cls.rawValue
                sched.frequencyDays = freq
                // Push next due date forward only if it has already passed.
                if sched.nextDueDate < now {
                    sched.nextDueDate = Calendar.current.date(byAdding: .day, value: freq, to: now) ?? now
                }
                sched.updatedAt = now
                sched.isSynced = false
            } else {
                let next = Calendar.current.date(byAdding: .day, value: freq, to: now) ?? now
                let sched = CycleCountSchedule(
                    inventoryItem: item,
                    branch: item.branch,
                    abcClass: cls,
                    frequencyDays: freq,
                    nextDueDate: next
                )
                modelContext.insert(sched)
            }
        }

        modelContext.saveWithLogging(label: #function)
    }

    /// Schedules whose next due date is today or earlier (for the count task list).
    func dueSchedules(branch: Branch?) -> [CycleCountSchedule] {
        guard let modelContext else { return [] }
        let branchId = branch?.id
        let descriptor = FetchDescriptor<CycleCountSchedule>(
            predicate: #Predicate<CycleCountSchedule> { sched in
                sched.isDeleted == false &&
                (branchId == nil || sched.branch?.id == branchId)
            }
        )
        guard let all = try? modelContext.fetch(descriptor) else { return [] }
        let today = Calendar.current.startOfDay(for: Date())
        return all.filter { $0.nextDueDate <= today }
            .sorted { $0.abc.rawValue < $1.abc.rawValue }
    }

    /// Mark a schedule as counted today and roll its next due date forward.
    func recordCount(_ schedule: CycleCountSchedule) {
        guard let modelContext else { return }
        let now = Date()
        schedule.lastCountDate = now
        schedule.nextDueDate = Calendar.current.date(byAdding: .day, value: schedule.frequencyDays, to: now) ?? now
        schedule.updatedAt = now
        schedule.isSynced = false
        modelContext.saveWithLogging(label: #function)
    }
}
