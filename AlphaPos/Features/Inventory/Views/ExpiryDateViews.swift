// ExpiryDateViews.swift
// AlphaPos — Expiry Date UI Components
//
// Reusable SwiftUI components for Expiry Date integration across the app.
// ─────────────────────────────────────────────────────────────────────────────
// Includes:
//   • ExpiryBadge              — compact status pill for list rows
//   • ExpiryDatePicker         — date + lot-number input for Add/Receive sheets
//   • ExpiryAlertDashboard     — summary section for Inventory overview
//   • LotListView              — per-item lot breakdown with FEFO order
//   • ExpiryAlertRow           — single row in the dashboard list
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI
import SwiftData

// MARK: - ExpiryBadge

/// A compact coloured pill showing an item's nearest-expiry lot status.
/// Add this to any InventoryItem row.
struct ExpiryBadge: View {
    let status: ExpiryStatus
    let daysLeft: Int?

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: status.systemImage)
                .font(.caption2)
            if let days = daysLeft {
                Text(labelText(days: days))
                    .font(.caption2).fontWeight(.semibold)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(badgeColor.opacity(0.18))
        .foregroundColor(badgeColor)
        .clipShape(Capsule())
    }

    private var badgeColor: Color {
        switch status {
        case .expired:  return Color("appRose",  bundle: nil)
        case .critical: return .orange
        case .warning:  return .yellow
        case .ok:       return Color("appTeal",  bundle: nil)
        }
    }

    private func labelText(days: Int) -> String {
        switch status {
        case .expired:  return "หมดอายุ"
        case .critical: return "\(days)d"
        case .warning:  return "\(days)d"
        case .ok:       return "\(days)d"
        }
    }
}

// MARK: - ExpiryDatePicker

/// Used inside AddStockItemView and ReceiveStockView.
/// Provides toggle (has expiry / no expiry) + DatePicker + Lot Number field.
struct ExpiryDatePicker: View {
    @Binding var hasExpiry: Bool
    @Binding var expiryDate: Date
    @Binding var lotNumber: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Toggle
            Toggle(isOn: $hasExpiry) {
                Label("ระบุวันหมดอายุ", systemImage: "calendar.badge.exclamationmark")
                    .font(.subheadline)
                    .foregroundColor(.primary)
            }
            .tint(Color("appTeal", bundle: nil))

            if hasExpiry {
                Divider()

                // Lot Number
                VStack(alignment: .leading, spacing: 4) {
                    Text("หมายเลข Lot / Batch")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("เช่น LOT-2025-001 (ไม่บังคับ)", text: $lotNumber)
                        .textFieldStyle(.roundedBorder)
                        .font(.subheadline)
                        .autocorrectionDisabled()
                }

                // Date Picker
                VStack(alignment: .leading, spacing: 4) {
                    Text("วันหมดอายุ")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    DatePicker(
                        "",
                        selection: $expiryDate,
                        in: Date()...,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .tint(Color("appTeal", bundle: nil))

                    // Days-from-today helper label
                    let days = Calendar.current.dateComponents([.day], from: Date(), to: expiryDate).day ?? 0
                    Text("หมดอายุใน \(days) วัน")
                        .font(.caption)
                        .foregroundColor(days < 7 ? .orange : .secondary)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: hasExpiry)
    }
}

// MARK: - ExpiryAlertDashboard

/// Drop-in section for the Inventory stats header showing expiry counts.
/// Pass `expiryManager` from the parent view.
struct ExpiryAlertDashboard: View {
    let expiryManager: InventoryExpiryManager
    let activeBranch: Branch?

    @State private var alerts: [ExpiryAlert] = []
    @State private var showingFullList = false

    private var expiredCount: Int  { alerts.filter { $0.status == .expired }.count }
    private var criticalCount: Int { alerts.filter { $0.status == .critical }.count }
    private var warningCount: Int  { alerts.filter { $0.status == .warning }.count }

    var body: some View {
        if alerts.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 0) {
                // Header row
                HStack {
                    Label("การแจ้งเตือนวันหมดอายุ", systemImage: "clock.badge.exclamationmark.fill")
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(.primary)
                    Spacer()
                    Button("ดูทั้งหมด (\(alerts.count))") { showingFullList = true }
                        .font(.caption).foregroundColor(Color("appTeal", bundle: nil))
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)

                // Summary chips
                HStack(spacing: 8) {
                    if expiredCount > 0 {
                        expiryChip(count: expiredCount, label: "หมดอายุแล้ว", status: .expired)
                    }
                    if criticalCount > 0 {
                        expiryChip(count: criticalCount, label: "วิกฤต ≤3วัน", status: .critical)
                    }
                    if warningCount > 0 {
                        expiryChip(count: warningCount, label: "เตือน ≤7วัน", status: .warning)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                // Top-3 urgent rows
                VStack(spacing: 0) {
                    ForEach(alerts.prefix(3)) { alert in
                        ExpiryAlertRow(alert: alert)
                        if alert.id != alerts.prefix(3).last?.id {
                            Divider().padding(.leading, 14)
                        }
                    }
                }
            }
            .background(Color("appSurface", bundle: nil))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color("appDivider", bundle: nil), lineWidth: 0.5)
            )
            .padding(.horizontal, 14)
            .padding(.bottom, 6)
            .onAppear { loadAlerts() }
            .sheet(isPresented: $showingFullList) {
                ExpiryAlertListSheet(alerts: alerts)
            }
        }
    }

    private func loadAlerts() {
        alerts = expiryManager.getExpiringAlerts(branch: activeBranch)
    }

    private func expiryChip(count: Int, label: String, status: ExpiryStatus) -> some View {
        HStack(spacing: 4) {
            Image(systemName: status.systemImage).font(.caption2)
            Text("\(count) \(label)").font(.caption2).fontWeight(.medium)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(chipColor(status).opacity(0.15))
        .foregroundColor(chipColor(status))
        .clipShape(Capsule())
    }

    private func chipColor(_ status: ExpiryStatus) -> Color {
        switch status {
        case .expired:  return Color("appRose",  bundle: nil)
        case .critical: return .orange
        case .warning:  return .yellow
        case .ok:       return Color("appTeal",  bundle: nil)
        }
    }
}

// MARK: - ExpiryAlertRow

struct ExpiryAlertRow: View {
    let alert: ExpiryAlert

    var body: some View {
        HStack(spacing: 10) {
            // Status indicator dot
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(alert.itemName)
                    .font(.subheadline).fontWeight(.medium)
                    .foregroundColor(.primary)
                HStack(spacing: 6) {
                    if let lot = alert.lotNumber {
                        Text("Lot: \(lot)")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                    Text(String(format: "%.1f %@", alert.remainingQuantity, alert.unit))
                        .font(.caption2).foregroundColor(.secondary)
                    if let branch = alert.branchName {
                        Text("• \(branch)").font(.caption2).foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            ExpiryBadge(status: alert.status, daysLeft: alert.daysUntilExpiry)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private var statusColor: Color {
        switch alert.status {
        case .expired:  return Color("appRose",  bundle: nil)
        case .critical: return .orange
        case .warning:  return .yellow
        case .ok:       return Color("appTeal",  bundle: nil)
        }
    }
}

// MARK: - LotListView

/// Shows all active lots for one InventoryItem in FEFO order.
struct LotListView: View {
    let item: InventoryItem
    let expiryManager: InventoryExpiryManager

    @State private var lots: [InventoryLot] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader

            if lots.isEmpty {
                Text("ยังไม่มี Lot ที่บันทึกไว้")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ForEach(lots) { lot in
                    LotRow(lot: lot, unit: item.unit)
                    if lot.id != lots.last?.id {
                        Divider().padding(.leading, 14)
                    }
                }
            }
        }
        .background(Color("appSurfaceHigh", bundle: nil))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onAppear { lots = expiryManager.lots(for: item) }
    }

    private var sectionHeader: some View {
        HStack {
            Label("Lots (FEFO Order)", systemImage: "list.number")
                .font(.subheadline).fontWeight(.semibold)
            Spacer()
            Text("\(lots.count) lots")
                .font(.caption).foregroundColor(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// MARK: - LotRow

private struct LotRow: View {
    let lot: InventoryLot
    let unit: String

    private var status: ExpiryStatus {
        lot.expiryStatus()
    }

    var body: some View {
        HStack(spacing: 10) {
            // FEFO indicator — expired lots shown with strikethrough qty
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if let lotNo = lot.lotNumber {
                        Text(lotNo)
                            .font(.caption).fontWeight(.semibold)
                            .foregroundColor(.primary)
                    } else {
                        Text("No lot #")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    if status == .expired {
                        Text("หมดอายุ")
                            .font(.caption2)
                            .foregroundColor(Color("appRose", bundle: nil))
                    }
                }

                HStack(spacing: 6) {
                    Text(String(format: "%.1f / %.1f %@", lot.remainingQuantity, lot.initialQuantity, unit))
                        .font(.caption2).foregroundColor(.secondary)
                    Text("• รับ \(DateFormatter.shortDate.string(from: lot.receivedDate))")
                        .font(.caption2).foregroundColor(.secondary)
                }
            }

            Spacer()

            // Expiry info
            if let expiry = lot.expiryDate {
                VStack(alignment: .trailing, spacing: 2) {
                    ExpiryBadge(status: status, daysLeft: lot.daysUntilExpiry())
                    Text(DateFormatter.shortDate.string(from: expiry))
                        .font(.caption2).foregroundColor(.secondary)
                }
            } else {
                Text("ไม่มีวันหมดอายุ")
                    .font(.caption2).foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}

// MARK: - ExpiryAlertListSheet

/// Full-screen sheet showing all expiry alerts, grouped by status.
struct ExpiryAlertListSheet: View {
    let alerts: [ExpiryAlert]
    @Environment(\.dismiss) private var dismiss

    private var grouped: [(status: ExpiryStatus, alerts: [ExpiryAlert])] {
        let order: [ExpiryStatus] = [.expired, .critical, .warning]
        return order.compactMap { status in
            let filtered = alerts.filter { $0.status == status }
            return filtered.isEmpty ? nil : (status: status, alerts: filtered)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color("appBackground", bundle: nil).ignoresSafeArea()
                List {
                    ForEach(grouped, id: \.status) { group in
                        Section(header: statusHeader(group.status)) {
                            ForEach(group.alerts) { alert in
                                ExpiryAlertRow(alert: alert)
                                    .listRowBackground(Color("appSurface", bundle: nil))
                                    .listRowInsets(EdgeInsets())
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("การแจ้งเตือนวันหมดอายุ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ปิด") { dismiss() }.foregroundColor(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func statusHeader(_ status: ExpiryStatus) -> some View {
        HStack(spacing: 6) {
            Image(systemName: status.systemImage)
            Text(sectionTitle(status))
        }
        .font(.caption).fontWeight(.semibold)
        .textCase(nil)
    }

    private func sectionTitle(_ status: ExpiryStatus) -> String {
        switch status {
        case .expired:  return "หมดอายุแล้ว"
        case .critical: return "วิกฤต — หมดภายใน 3 วัน"
        case .warning:  return "เตือน — หมดภายใน 7 วัน"
        case .ok:       return "ปกติ"
        }
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
