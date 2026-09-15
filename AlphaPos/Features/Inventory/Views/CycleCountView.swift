// CycleCountView.swift
// AlphaPos — ABC-based Cycle Counting UI
//
// Surfaces the CycleCountManager (InventoryControl.swift): generate schedules
// from ABC classification, show what's due today, and record a physical count
// that reconciles stock via the existing audit path.

import SwiftUI
import SwiftData

struct CycleCountView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let activeBranch: Branch?

    @State private var dueSchedules: [CycleCountSchedule] = []
    @State private var allSchedules: [CycleCountSchedule] = []
    @State private var selected: CycleCountSchedule?
    @State private var generated = false
    @State private var statusMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        generateSchedules()
                    } label: {
                        Label("สร้าง/อัปเดตตารางนับรอบ (ABC)", systemImage: "arrow.clockwise")
                    }
                    if generated {
                        Text(statusMessage ?? "อัปเดตตารางเรียบร้อย").font(.caption).foregroundColor(.appTeal)
                    }
                } header: { Text("ตารางนับรอบ (Cycle Count)") }

                if !dueSchedules.isEmpty {
                    Section {
                        ForEach(dueSchedules) { sched in
                            Button { selected = sched } label: {
                                CycleCountRow(schedule: sched)
                            }
                        }
                    } header: { Text("ครบกำหนดนับวันนี้ (\(dueSchedules.count))") }
                }

                Section {
                    if allSchedules.isEmpty {
                        Text("ยังไม่มีตารางนับรอบ — กดปุ่มสร้างตารางด้านบน").font(.caption).foregroundColor(.textSecondary)
                    } else {
                        ForEach(allSchedules) { sched in
                            CycleCountRow(schedule: sched, muted: true)
                        }
                    }
                } header: { Text("รายการทั้งหมด") }
            }
            .navigationTitle("นับรอบสต็อก (ABC)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ปิด") { dismiss() }
                }
            }
            .onAppear { refresh() }
            .sheet(item: $selected) { sched in
                CycleCountCountSheet(schedule: sched, activeBranch: activeBranch) {
                    refresh()
                }
            }
        }
    }

    // MARK: - Data

    private func refresh() {
        let mgr = CycleCountManager(modelContext: modelContext)
        dueSchedules = mgr.dueSchedules(branch: activeBranch)
        let branchId = activeBranch?.id
        let descriptor = FetchDescriptor<CycleCountSchedule>(
            predicate: #Predicate<CycleCountSchedule> { !$0.isDeleted }
        )
        let schedules = (try? modelContext.fetch(descriptor)) ?? []
        allSchedules = schedules.filter { branchId == nil || $0.branch?.id == branchId }
    }

    private func generateSchedules() {
        let usage = annualUsageValue()
        let mgr = CycleCountManager(modelContext: modelContext)
        mgr.regenerateSchedules(branch: activeBranch, annualUsageValues: usage)
        refresh()
        generated = true
        statusMessage = "สร้างตาราง \(allSchedules.count) รายการ (A=สัปดาห์, B=เดือน, C=ไตรมาส)"
    }

    /// Annualised usage value per item (last 365 days of sell+waste, by cost).
    private func annualUsageValue() -> [UUID: Double] {
        let since = Calendar.current.date(byAdding: .day, value: -365, to: Date()) ?? Date()
        // #Predicate can't reference enum cases directly (key-path to a case
        // fails to compile), so hoist the raw values into plain String locals.
        let sellType = InventoryMovementType.sell.rawValue
        let wasteType = InventoryMovementType.waste.rawValue
        let txns = (try? modelContext.fetch(FetchDescriptor<InventoryTransaction>(
            predicate: #Predicate<InventoryTransaction> { txn in
                !txn.isDeleted &&
                txn.createdAt >= since &&
                (txn.transactionType == sellType ||
                 txn.transactionType == wasteType)
            }
        ))) ?? []

        var usage: [UUID: Double] = [:]
        for txn in txns {
            guard let item = txn.item else { continue }
            usage[item.id, default: 0] += abs(txn.quantity) * (txn.costPrice ?? item.costPrice)
        }
        return usage
    }
}

// MARK: - Row

private struct CycleCountRow: View {
    let schedule: CycleCountSchedule
    var muted: Bool = false

    private var badgeColor: Color {
        switch schedule.abc {
        case .a: return .appRose
        case .b: return .appAmber
        case .c: return .appTeal
        }
    }

    var body: some View {
        HStack {
            Text(schedule.abc.rawValue)
                .font(.system(size: 12, weight: .black))
                .foregroundColor(.white)
                .padding(6)
                .background(badgeColor)
                .cornerRadius(6)

            VStack(alignment: .leading, spacing: 2) {
                Text(schedule.inventoryItem?.name ?? "—")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let sku = schedule.inventoryItem?.sku, !sku.isEmpty {
                        Text(sku)
                            .font(.caption2)
                            .foregroundColor(.textSecondary)
                    }
                    if let loc = schedule.inventoryItem?.storageLocation, !loc.isEmpty {
                        Text("· \(loc)")
                            .font(.caption2)
                            .foregroundColor(.textTertiary)
                    }
                }
                Text("คงเหลือระบบ: \(Int(schedule.inventoryItem?.currentQuantity ?? 0)) \(schedule.inventoryItem?.unit ?? "")")
                    .font(.caption)
                    .foregroundColor(muted ? .textSecondary : .textPrimary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("ทุก \(schedule.frequencyDays) วัน")
                    .font(.caption2)
                    .foregroundColor(.textSecondary)
                if let last = schedule.lastCountDate {
                    Text("นับล่าสุด: \(last, style: .date)")
                        .font(.caption2)
                        .foregroundColor(.textSecondary)
                }
            }
        }
    }
}

// MARK: - Count Sheet

private struct CycleCountCountSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sessionManager: AppSessionManager

    let schedule: CycleCountSchedule
    let activeBranch: Branch?
    let onDone: () -> Void

    @State private var physicalText: String = ""
    @State private var note: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(schedule.inventoryItem?.name ?? "—").font(.headline)
                    Text("คลาส \(schedule.abc.rawValue) · นับทุก \(schedule.frequencyDays) วัน")
                        .font(.caption).foregroundColor(.textSecondary)
                    if let qty = schedule.inventoryItem?.currentQuantity {
                        Text("จำนวนในระบบ: \(Int(qty)) \(schedule.inventoryItem?.unit ?? "")")
                            .font(.subheadline)
                    }
                }

                Section("จำนวนนับได้จริง") {
                    TextField("0", text: $physicalText)
                        .keyboardType(.decimalPad)
                    TextField("หมายเหตุ (ถ้ามี)", text: $note)
                }
            }
            .navigationTitle("นับสต็อก")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ยกเลิก") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("บันทึก") { save() }
                        .disabled(Double(physicalText) == nil)
                }
            }
        }
    }

    private func save() {
        guard sessionManager.can(.inventoryCount) || sessionManager.can(.inventoryManage) else { return }
        guard let physical = Double(physicalText),
              let item = schedule.inventoryItem else { return }

        // Reconcile stock through the existing physical-audit path (handles lots + txn).
        let vm = InventoryViewModel(modelContext: modelContext)
        vm.commitAudit(auditLines: [(item: item, physicalCount: physical, notes: note.isEmpty ? "Cycle count (\(schedule.abc.rawValue))" : note)])

        CycleCountManager(modelContext: modelContext).recordCount(schedule)
        onDone()
        dismiss()
    }
}
