// StockAuditView.swift
// AlphaPos — Premium Physical Stock Take & Variance Reporting

import SwiftUI
import SwiftData

struct StockAuditView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var lm: LocalizationManager
    @EnvironmentObject private var sessionManager: AppSessionManager
    @Query(sort: \InventoryItem.name) private var ingredients: [InventoryItem]

    @State private var viewModel = InventoryViewModel()

    struct AuditLineItem: Identifiable {
        let id = UUID()
        let item: InventoryItem
        var physicalCount: Double
        var physicalString: String
        var notes: String
        var isCounted: Bool
    }

    @State private var auditLines: [AuditLineItem] = []
    @State private var showingSuccessAlert = false
    @State private var searchPattern = ""
    @State private var selectedLocation = "All"
    @State private var showingScanner = false

    private var activeBranch: Branch? {
        try? BranchContext.shared.requireActiveBranch(in: modelContext)
    }

    private var filteredAuditLines: [Binding<AuditLineItem>] {
        var lines: [Binding<AuditLineItem>] = []
        for index in $auditLines.indices {
            let item = auditLines[index].item
            let matchesSearch = searchPattern.isEmpty ||
                item.name.localizedCaseInsensitiveContains(searchPattern) ||
                (item.sku ?? "").localizedCaseInsensitiveContains(searchPattern) ||
                (item.barcode ?? "").localizedCaseInsensitiveContains(searchPattern)

            let matchesLocation = selectedLocation == "All" || item.storageLocation == selectedLocation

            if matchesSearch && matchesLocation {
                lines.append($auditLines[index])
            }
        }
        return lines
    }

    // Summary Calculations
    private var totalVarianceCost: Double {
        auditLines.reduce(0.0) { sum, line in
            let diff = line.physicalCount - line.item.currentQuantity
            return sum + (diff * line.item.costPrice)
        }
    }

    private var adjustedItemsCount: Int {
        auditLines.filter { $0.physicalCount != $0.item.currentQuantity }.count
    }

    private var countedItemsCount: Int { auditLines.filter(\.isCounted).count }

    var body: some View {
        VStack(spacing: 0) {
            // Thin KPI + search strip (controls share one height)
            HStack(spacing: 8) {
                auditStatChip("\(countedItemsCount)/\(auditLines.count)", "items_to_audit".t, .appAccent)
                auditStatChip("\(adjustedItemsCount)", "adjusted_items".t, .appAmber)
                auditStatChip(
                    String(format: "฿%.0f", totalVarianceCost),
                    "net_variance_cost".t,
                    totalVarianceCost < 0 ? .appRose : (totalVarianceCost > 0 ? .appTeal : .textSecondary)
                )

                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundColor(.textSecondary)
                    TextField("filter_ingredients_audit".t, text: $searchPattern)
                        .font(.caption)
                        .foregroundColor(.textPrimary)
                    Button(action: { showingScanner = true }) {
                        Image(systemName: "barcode.viewfinder")
                            .font(.system(size: 11))
                            .foregroundColor(.appTeal)
                    }
                    .buttonStyle(.plain)
                    if !searchPattern.isEmpty {
                        Button(action: { searchPattern = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(Color.appSurfaceHigh)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .frame(minWidth: 160, maxWidth: 260)

                let locations = ["All"] + Array(Set(ingredients.compactMap { $0.storageLocation })).sorted()
                if locations.count > 1 {
                    Menu {
                        ForEach(locations, id: \.self) { loc in
                            Button {
                                selectedLocation = loc
                            } label: {
                                if selectedLocation == loc {
                                    Label(loc == "All" ? "location_all".t : loc, systemImage: "checkmark")
                                } else {
                                    Text(loc == "All" ? "location_all".t : loc)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.system(size: 10, weight: .semibold))
                            Text(selectedLocation == "All" ? "location_all".t : selectedLocation)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .foregroundColor(.textSecondary)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(Color.appSurfaceHigh)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.appBorderSubtle, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, APSpacing.md)
            .padding(.vertical, 8)
            .background(Color.appSurface)
            .overlay(Rectangle().fill(Color.appDivider).frame(height: 1), alignment: .bottom)

            if auditLines.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 28))
                        .foregroundColor(.textTertiary)
                    Text("no_inventory_to_audit".t)
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.appBackground)
            } else {
                // Balanced columns — item flexes; numeric cols get enough width (no right-side crush)
                auditColumnHeader
                    .padding(.horizontal, APSpacing.md)
                    .padding(.vertical, 5)
                    .background(Color.appSurfaceHigh.opacity(0.4))

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredAuditLines) { $line in
                            auditItemRow(line: $line)
                        }
                    }
                }
                .background(Color.appBackground)

                bottomActionPanel
            }
        }
        .onAppear {
            viewModel.modelContext = modelContext
            initializeAudit()
        }
        .alert("audit_committed_title".t, isPresented: $showingSuccessAlert) {
            Button("ok_btn_label".t) { initializeAudit() }
        } message: {
            Text("audit_committed_message".t)
        }
        .sheet(isPresented: $showingScanner) {
            BarcodeScannerView(onScan: handleBarcodeScan, continuous: true)
        }
    }

    // MARK: - Subviews

    private func auditStatChip(_ value: String, _ title: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Text(value)
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundColor(color)
            Text(title)
                .font(.system(size: 9))
                .foregroundColor(.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(color.opacity(0.08))
        .clipShape(Capsule())
    }

    /// Proportional column widths so SKU / on-hand / count are not crushed to the trailing edge.
    private enum AuditCol {
        static let sku: CGFloat = 140
        static let onHand: CGFloat = 120
        static let count: CGFloat = 150
        static let variance: CGFloat = 120
        static let gap: CGFloat = 12
    }

    private var auditColumnHeader: some View {
        HStack(spacing: AuditCol.gap) {
            Text("item_header".t)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("SKU")
                .frame(width: AuditCol.sku, alignment: .leading)
            Text("on_hand_label".t)
                .frame(width: AuditCol.onHand, alignment: .trailing)
            Text("inv_count_col".t)
                .frame(width: AuditCol.count, alignment: .trailing)
            Text("variance_label".t)
                .frame(width: AuditCol.variance, alignment: .trailing)
        }
        .font(.caption2.weight(.bold))
        .foregroundColor(.textSecondary)
        .textCase(.uppercase)
    }

    private func auditItemRow(line: Binding<AuditLineItem>) -> some View {
        let item = line.wrappedValue.item
        let diff = line.wrappedValue.physicalCount - item.currentQuantity
        let diffCost = diff * item.costPrice

        return VStack(spacing: 0) {
            HStack(spacing: AuditCol.gap) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                    if let loc = item.storageLocation, !loc.isEmpty {
                        Text(loc)
                            .font(.system(size: 9))
                            .foregroundColor(.textTertiary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(0)

                Text(item.sku ?? "—")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.textSecondary)
                    .lineLimit(1)
                    .frame(width: AuditCol.sku, alignment: .leading)

                Text(String(format: "%.1f %@", item.currentQuantity, item.unit))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(width: AuditCol.onHand, alignment: .trailing)

                HStack(spacing: 6) {
                    TextField("0", text: line.physicalString)
                        .font(.caption.weight(.bold).monospacedDigit())
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(minWidth: 64, maxWidth: 80)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(Color.appSurfaceHigh)
                        .cornerRadius(4)
                        .onChange(of: line.wrappedValue.physicalString) { _, newVal in
                            line.wrappedValue.isCounted = true
                            if let parsed = Double(newVal) {
                                line.wrappedValue.physicalCount = parsed
                            } else if newVal.isEmpty {
                                line.wrappedValue.physicalCount = 0.0
                            }
                        }
                    Text(item.unit)
                        .font(.caption2)
                        .foregroundColor(.textSecondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .frame(width: AuditCol.count, alignment: .trailing)

                Image(systemName: line.wrappedValue.isCounted ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(line.wrappedValue.isCounted ? .appTeal : .textTertiary)
                    .accessibilityLabel(line.wrappedValue.isCounted ? "นับแล้ว" : "ยังไม่ได้นับ")

                Group {
                    if diff == 0 {
                        Text("—")
                            .font(.caption2)
                            .foregroundColor(.textTertiary)
                    } else {
                        Text(String(format: "%@%.1f · ฿%.0f", diff > 0 ? "+" : "", diff, diffCost))
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .foregroundColor(diff < 0 ? .appRose : .appTeal)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .frame(width: AuditCol.variance, alignment: .trailing)
            }
            .padding(.horizontal, APSpacing.md)
            .padding(.vertical, 6)

            if diff != 0 {
                HStack(spacing: 6) {
                    Image(systemName: "pencil")
                        .font(.system(size: 9))
                        .foregroundColor(.textTertiary)
                    TextField("discrepancy_reason_placeholder".t, text: line.notes)
                        .font(.caption2)
                        .foregroundColor(.textPrimary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, APSpacing.md)
                .padding(.bottom, 6)
            }

            Divider().background(Color.appDivider)
        }
        .background(Color.appSurface)
    }

    private var bottomActionPanel: some View {
        HStack {
            Spacer()

            Button(action: {
                initializeAudit()
            }) {
                Text("reset_fields_btn".t)
                    .font(.caption.weight(.bold))
                    .foregroundColor(.textSecondary)
                    .padding(.horizontal, APSpacing.md)
                    .padding(.vertical, 8)
                    .background(Color.appSurfaceHigh)
                    .cornerRadius(APRadius.sm)
            }
            .buttonStyle(.plain)

            Button(action: commitAudit) {
                Text("commit_audit_adjustments_btn".t)
                    .font(.caption.weight(.bold))
                    .foregroundColor(countedItemsCount > 0 ? .white : .textTertiary)
                    .padding(.horizontal, APSpacing.md)
                    .padding(.vertical, 8)
                    .background(countedItemsCount > 0 ? APGradient.accent : nil)
                    .backgroundColor(countedItemsCount > 0 ? .clear : Color.appSurfaceHigh)
                    .cornerRadius(APRadius.sm)
            }
            .disabled(countedItemsCount == 0)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, APSpacing.md)
        .padding(.vertical, 8)
        .background(Color.appSurface)
        .overlay(Rectangle().fill(Color.appDivider).frame(height: 1), alignment: .top)
    }

    // MARK: - Logic

    private func initializeAudit() {
        let active = activeBranch
        let branchIngredients = ingredients.filter { $0.branch?.id == active?.id }
        auditLines = branchIngredients.map { item in
            AuditLineItem(
                item: item,
                physicalCount: item.currentQuantity,
                physicalString: String(format: "%.1f", item.currentQuantity),
                notes: "",
                isCounted: false
            )
        }
    }

    private func handleBarcodeScan(code: String) {
        if let idx = auditLines.firstIndex(where: { $0.item.barcode == code || $0.item.sku == code }) {
            auditLines[idx].physicalCount = auditLines[idx].isCounted ? auditLines[idx].physicalCount + 1.0 : 1.0
            auditLines[idx].physicalString = String(format: "%.1f", auditLines[idx].physicalCount)
            auditLines[idx].isCounted = true
            APHaptic.trigger()
        }
    }

    private func commitAudit() {
        guard sessionManager.can(.inventoryCount) || sessionManager.can(.inventoryManage) else { return }
        let itemsToCommit = auditLines.filter(\.isCounted)
        let linesData = itemsToCommit.map { (item: $0.item, physicalCount: $0.physicalCount, notes: $0.notes) }

        viewModel.commitAudit(auditLines: linesData)
        showingSuccessAlert = true
    }
}
