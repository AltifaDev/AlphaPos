// RefundView.swift
// AlphaPos — Refund Workflow

import SwiftUI
import SwiftData

// MARK: - Refund Reason Codes

enum RefundReason: String, CaseIterable, Identifiable {
    case customerRequest = "Customer Request"
    case wrongOrder      = "Wrong Order"
    case qualityIssue    = "Quality Issue"
    case overcharge      = "Overcharge"
    case other           = "Other"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .customerRequest: return "person.crop.circle.badge.questionmark"
        case .wrongOrder:      return "arrow.uturn.backward.circle"
        case .qualityIssue:    return "exclamationmark.triangle"
        case .overcharge:      return "dollarsign.arrow.circlepath"
        case .other:           return "ellipsis.circle"
        }
    }
}

// MARK: - Refund View Model

@Observable
@MainActor
final class RefundViewModel {
    var selectedOrder: Order?
    var selectedItemIds: Set<UUID> = []
    var isFullRefund: Bool = false
    var selectedReason: RefundReason = .customerRequest
    var otherReasonText: String = ""
    var showPINSheet: Bool = false
    var pinCode: String = ""
    var pinError: String?
    var isProcessing: Bool = false
    var isComplete: Bool = false
    var restockItems: Bool = false

    var refundableItems: [OrderItem] {
        guard let order = selectedOrder else { return [] }
        return order.items.filter { !$0.isDeleted && $0.status != "cancelled" }
    }

    var refundAmount: Double {
        guard let order = selectedOrder else { return 0 }
        let alreadyRefunded = order.refunds
            .filter { !$0.isDeleted && $0.status == "completed" }
            .reduce(0.0) { $0 + $1.refundAmount }
        let remainingRefundable = max(0, order.total - alreadyRefunded)
        if isFullRefund { return remainingRefundable }
        let items = order.items.filter { selectedItemIds.contains($0.id) && !$0.isDeleted }
        guard order.subtotal > 0 else { return 0 }
        let selectedSubtotal = items.reduce(0.0) { $0 + $1.subtotal }
        // Allocate order-level tax, service charge, and discount proportionally.
        return min(remainingRefundable, order.total * selectedSubtotal / order.subtotal)
    }

    var canProcess: Bool {
        guard selectedOrder != nil else { return false }
        if isFullRefund { return true }
        return !selectedItemIds.isEmpty
    }

    func toggleItem(_ itemId: UUID) {
        if selectedItemIds.contains(itemId) {
            selectedItemIds.remove(itemId)
        } else {
            selectedItemIds.insert(itemId)
        }
        // Auto-detect full refund
        if selectedOrder != nil {
            let allIds = Set(refundableItems.map { $0.id })
            isFullRefund = selectedItemIds == allIds
        }
    }

    func selectFullRefund() {
        isFullRefund = true
        selectedItemIds = Set(refundableItems.map { $0.id })
    }

    func deselectFullRefund() {
        isFullRefund = false
        selectedItemIds.removeAll()
    }

    func validatePIN() -> Bool {
        pinError = "Use manager authorization to continue."
        pinCode = ""
        return false
    }

    func processRefund(modelContext: ModelContext) {
        guard let order = selectedOrder, refundAmount > 0 else { return }
        isProcessing = true
        let itemsBeingRefunded = order.items.filter {
            !$0.isDeleted && (isFullRefund || selectedItemIds.contains($0.id))
        }

        let reasonText = selectedReason == .other ? otherReasonText : selectedReason.rawValue

        // Mark selected items as cancelled
        if isFullRefund {
            order.status = "cancelled"
            for item in order.items {
                item.status = "cancelled"
                item.isSynced = false
                item.updatedAt = Date()
            }
        } else {
            for item in order.items where selectedItemIds.contains(item.id) {
                item.status = "cancelled"
                item.isSynced = false
                item.updatedAt = Date()
            }
        }

        // Create audit log
        let auditLog = AuditLog(
            actionType: "refund",
            details: "Refund ฿\(String(format: "%.2f", refundAmount)) — Reason: \(reasonText) — Order: \(order.orderNumber)",
            originalValue: order.total,
            newValue: refundAmount
        )
        modelContext.insert(auditLog)

        // Retrieve current active employee session from DB
        let records = (try? modelContext.fetch(FetchDescriptor<StaffSessionRecord>())) ?? []
        let activeRecord = records.filter { $0.endedAt == nil }.max(by: { $0.startedAt < $1.startedAt })
        let employeeId = activeRecord?.employeeId

        // Allocate the refund across original tenders without exceeding any payment.
        var amountToAllocate = refundAmount
        for payment in order.payments.sorted(by: { $0.paidAt < $1.paidAt }) where amountToAllocate > 0.005 {
            let previouslyRefunded = order.refunds
                .filter { $0.originalPayment?.id == payment.id && !$0.isDeleted && $0.status == "completed" }
                .reduce(0.0) { $0 + $1.refundAmount }
            let allocation = min(max(0, payment.amount - previouslyRefunded), amountToAllocate)
            guard allocation > 0.005 else { continue }

            modelContext.insert(RefundTransaction(
                order: order,
                originalPayment: payment,
                refundAmount: allocation,
                refundMethod: "original_tender",
                reasonCode: selectedReason.rawValue.lowercased().replacingOccurrences(of: " ", with: "_"),
                reasonNotes: reasonText,
                refundedByEmployeeId: employeeId,
                approvedByEmployeeId: employeeId,
                status: "completed"
            ))

            let paymentRefundedTotal = previouslyRefunded + allocation
            payment.status = paymentRefundedTotal >= payment.amount - 0.005 ? "refunded" : "partially_refunded"
            payment.isSynced = false
            payment.updatedAt = Date()
            amountToAllocate -= allocation
        }

        // Legacy orders may not have a Payment relationship; retain an auditable cash refund.
        if amountToAllocate > 0.005 {
            modelContext.insert(RefundTransaction(
                order: order,
                refundAmount: amountToAllocate,
                refundMethod: "cash",
                reasonCode: selectedReason.rawValue.lowercased().replacingOccurrences(of: " ", with: "_"),
                reasonNotes: reasonText,
                refundedByEmployeeId: employeeId,
                approvedByEmployeeId: employeeId,
                status: "completed"
            ))
        }

        order.isSynced = false
        order.updatedAt = Date()
        modelContext.saveWithLogging(label: #function)

        if restockItems {
            POSViewModel(modelContext: modelContext).reverseInventoryDeduction(
                for: order,
                specificItems: itemsBeingRefunded
            )
        }

        // Trigger sync
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }

        isProcessing = false
        isComplete = true
    }
}

// MARK: - Refund View

struct RefundView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sessionManager: AppSessionManager
    @AppStorage("require_manager_override_for_refund") private var requireManagerOverrideForRefund = true

    @Query(
        filter: #Predicate<Order> { order in
            order.status == "completed" && !order.isDeleted
        },
        sort: \Order.createdAt,
        order: .reverse
    )
    private var completedOrders: [Order]

    @State private var viewModel = RefundViewModel()
    @State private var searchText = ""

    private var filteredOrders: [Order] {
        if searchText.isEmpty { return completedOrders }
        return completedOrders.filter {
            $0.orderNumber.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                HStack(spacing: 0) {
                    // Left: Order list
                    orderListPanel

                    Divider().background(Color.appDivider)

                    // Right: Refund details
                    if viewModel.selectedOrder != nil {
                        refundDetailPanel
                    } else {
                        emptyDetailState
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: APSpacing.sm) {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .foregroundColor(.appRose)
                        Text("refund_process_btn".t)
                            .font(.headline).fontWeight(.bold)
                            .foregroundColor(.textPrimary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("close_btn_label".t) {
                        APHaptic.trigger()
                        dismiss()
                    }
                    .foregroundColor(.appAccent)
                    .fontWeight(.semibold)
                }
            }
            .toolbarBackground(Color.appSurface, for: .navigationBar)
            .sheet(isPresented: $viewModel.showPINSheet) {
                ManagerPINVerificationSheet(isPresented: $viewModel.showPINSheet) {
                    viewModel.processRefund(modelContext: modelContext)
                }
            }
            .alert("Refund Processed", isPresented: $viewModel.isComplete) {
                Button(L.Common.done.t) {
                    dismiss()
                }
            } message: {
                Text("Refund of ฿\(viewModel.refundAmount, specifier: "%.2f") has been processed successfully.")
            }
        }
        .apColorScheme()
    }

    // MARK: - Order List Panel

    private var orderListPanel: some View {
        VStack(spacing: 0) {
            // Search
            HStack(spacing: APSpacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.textSecondary)
                TextField("Search order number...", text: $searchText)
                    .font(.subheadline)
                    .foregroundColor(.textPrimary)
                    .tint(.appAccent)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.textSecondary)
                    }
                }
            }
            .padding(10)
            .background(Color.appSurfaceHigh)
            .cornerRadius(APRadius.md)
            .overlay(
                RoundedRectangle(cornerRadius: APRadius.md)
                    .stroke(Color.appBorderSubtle, lineWidth: 1)
            )
            .padding(APSpacing.md)

            Text("refund_recent_orders_title".t)
                .font(.caption.weight(.bold))
                .foregroundColor(.textSecondary)
                .textCase(.uppercase)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, APSpacing.md)
                .padding(.bottom, APSpacing.sm)

            Divider().background(Color.appDivider)

            if filteredOrders.isEmpty {
                VStack(spacing: APSpacing.md) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundColor(.textTertiary)
                    Text("refund_no_orders_found".t)
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: APSpacing.sm) {
                        ForEach(filteredOrders) { order in
                            orderCard(order: order)
                        }
                    }
                    .padding(APSpacing.md)
                }
            }
        }
        .frame(width: 360)
        .background(Color.appBackground)
    }

    private func orderCard(order: Order) -> some View {
        let isSelected = viewModel.selectedOrder?.id == order.id
        return Button(action: {
            withAnimation(.spring(response: 0.3)) {
                viewModel.selectedOrder = order
                viewModel.selectedItemIds.removeAll()
                viewModel.isFullRefund = false
            }
            APHaptic.trigger()
        }) {
            VStack(alignment: .leading, spacing: APSpacing.xs) {
                HStack {
                    Text(order.orderNumber)
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.textPrimary)
                    Spacer()
                    Text("฿\(order.total, specifier: "%.2f")")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.textPrimary)
                }

                HStack {
                    Label(
                        DateFormatter.shortDateTimeFormat().string(from: order.createdAt),
                        systemImage: "clock"
                    )
                    .font(.caption)
                    .foregroundColor(.textSecondary)

                    Spacer()

                    Text("\(order.items.filter { !$0.isDeleted }.count) items")
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                }

                if let table = order.tableSession?.table?.tableNumber {
                    Label("Table \(table)", systemImage: "tablecells")
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                }
            }
            .padding(APSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: APRadius.md, style: .continuous)
                    .fill(isSelected ? Color.appAccent.opacity(0.12) : Color.appSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: APRadius.md, style: .continuous)
                            .stroke(isSelected ? Color.appAccent : Color.appBorderSubtle, lineWidth: isSelected ? 1.5 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty Detail State

    private var emptyDetailState: some View {
        VStack(spacing: APSpacing.lg) {
            ZStack {
                Circle()
                    .fill(Color.appSurface)
                    .frame(width: 100, height: 100)
                Image(systemName: "arrow.uturn.backward.circle")
                    .font(.system(size: 44))
                    .foregroundColor(.textTertiary)
            }
            Text("refund_select_order_title".t)
                .font(.title3.weight(.bold))
                .foregroundColor(.textPrimary)
            Text("refund_select_order_desc".t)
                .font(.subheadline)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
    }

    // MARK: - Refund Detail Panel

    private var refundDetailPanel: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: APSpacing.lg) {
                    // Refund type selector
                    refundTypeSelector

                    // Items list
                    itemsSection

                    // Reason picker
                    reasonSection

                    Toggle(isOn: $viewModel.restockItems) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Return ingredients to inventory")
                                .font(.subheadline.weight(.semibold))
                            Text("Enable only when the returned product can safely be restocked.")
                                .font(.caption)
                                .foregroundColor(.textSecondary)
                        }
                    }
                    .tint(.appTeal)
                    .apCard()

                    // Refund summary
                    refundSummary
                }
                .padding(APSpacing.lg)
            }

            // Process button
            processRefundBar
        }
        .frame(maxWidth: .infinity)
        .background(Color.appBackground)
    }

    // MARK: - Refund Type Selector

    private var refundTypeSelector: some View {
        HStack(spacing: APSpacing.md) {
            Button(action: {
                withAnimation(.spring(response: 0.3)) {
                    viewModel.selectFullRefund()
                }
                APHaptic.trigger()
            }) {
                HStack {
                    Image(systemName: viewModel.isFullRefund ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(viewModel.isFullRefund ? .appRose : .textSecondary)
                    Text("refund_type_full".t)
                        .fontWeight(.semibold)
                }
                .apChip(selected: viewModel.isFullRefund, gradient: APGradient.destructive)
            }

            Button(action: {
                withAnimation(.spring(response: 0.3)) {
                    viewModel.deselectFullRefund()
                }
                APHaptic.trigger()
            }) {
                HStack {
                    Image(systemName: !viewModel.isFullRefund ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(!viewModel.isFullRefund ? .appAccent : .textSecondary)
                    Text("refund_type_partial".t)
                        .fontWeight(.semibold)
                }
                .apChip(selected: !viewModel.isFullRefund)
            }

            Spacer()
        }
    }

    // MARK: - Items Section

    private var itemsSection: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            Text("refund_order_items_header".t)
                .font(.caption.weight(.bold))
                .foregroundColor(.textSecondary)
                .textCase(.uppercase)

            ForEach(viewModel.refundableItems) { item in
                let isSelected = viewModel.isFullRefund || viewModel.selectedItemIds.contains(item.id)

                Button(action: {
                    if !viewModel.isFullRefund {
                        withAnimation(.spring(response: 0.3)) {
                            viewModel.toggleItem(item.id)
                        }
                        APHaptic.trigger()
                    }
                }) {
                    HStack(spacing: APSpacing.md) {
                        Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                            .font(.system(size: 20))
                            .foregroundColor(isSelected ? .appRose : .textTertiary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.menuItem?.localizedName ?? "Unknown")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.textPrimary)

                            let modNames = item.modifiers.compactMap { $0.modifier?.name }.joined(separator: ", ")
                            if !modNames.isEmpty {
                                Text(modNames)
                                    .font(.caption)
                                    .foregroundColor(.textSecondary)
                            }
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text("×\(item.quantity)")
                                .font(.caption.weight(.bold))
                                .foregroundColor(.textSecondary)
                            Text("฿\(item.subtotal, specifier: "%.2f")")
                                .font(.subheadline.weight(.bold))
                                .foregroundColor(isSelected ? .appRose : .textPrimary)
                        }
                    }
                    .padding(APSpacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: APRadius.md, style: .continuous)
                            .fill(isSelected ? Color.appRose.opacity(0.08) : Color.appSurface)
                            .overlay(
                                RoundedRectangle(cornerRadius: APRadius.md, style: .continuous)
                                    .stroke(isSelected ? Color.appRose.opacity(0.3) : Color.appBorderSubtle, lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isFullRefund)
            }
        }
    }

    // MARK: - Reason Section

    private var reasonSection: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            Text("refund_reason_header".t)
                .font(.caption.weight(.bold))
                .foregroundColor(.textSecondary)
                .textCase(.uppercase)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: APSpacing.sm) {
                ForEach(RefundReason.allCases) { reason in
                    let isSelected = viewModel.selectedReason == reason
                    Button(action: {
                        viewModel.selectedReason = reason
                        APHaptic.trigger()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: reason.icon)
                                .font(.system(size: 13))
                            Text(reason.rawValue)
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: APRadius.sm, style: .continuous)
                                .fill(isSelected ? Color.appAccent.opacity(0.12) : Color.appSurface)
                                .overlay(
                                    RoundedRectangle(cornerRadius: APRadius.sm, style: .continuous)
                                        .stroke(isSelected ? Color.appAccent : Color.appBorderSubtle, lineWidth: isSelected ? 1.5 : 1)
                                )
                        )
                        .foregroundColor(isSelected ? .appAccent : .textSecondary)
                    }
                }
            }

            if viewModel.selectedReason == .other {
                TextField("Enter reason...", text: $viewModel.otherReasonText)
                    .font(.subheadline)
                    .foregroundColor(.textPrimary)
                    .padding(APSpacing.md)
                    .background(Color.appSurfaceHigh)
                    .cornerRadius(APRadius.sm)
                    .overlay(
                        RoundedRectangle(cornerRadius: APRadius.sm)
                            .stroke(Color.appBorderSubtle, lineWidth: 1)
                    )
                    .tint(.appAccent)
            }
        }
    }

    // MARK: - Refund Summary

    private var refundSummary: some View {
        VStack(spacing: APSpacing.sm) {
            HStack {
                Text("refund_amount_lbl".t)
                    .font(.subheadline)
                    .foregroundColor(.textSecondary)
                Spacer()
                Text("฿\(viewModel.refundAmount, specifier: "%.2f")")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundColor(.appRose)
            }

            if let order = viewModel.selectedOrder {
                HStack {
                    Text("refund_original_total_lbl".t)
                        .font(.caption)
                        .foregroundColor(.textTertiary)
                    Spacer()
                    Text("฿\(order.total, specifier: "%.2f")")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.textSecondary)
                }

                if let payment = order.payments.first {
                    HStack {
                        Text("refund_payment_method_lbl".t)
                            .font(.caption)
                            .foregroundColor(.textTertiary)
                        Spacer()
                        Text(payment.paymentMethod)
                            .font(.caption.weight(.medium))
                            .foregroundColor(.textSecondary)
                    }
                }
            }
        }
        .apCard()
    }

    // MARK: - Process Refund Bar

    private var processRefundBar: some View {
        VStack(spacing: 0) {
            Divider().background(Color.appDivider)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("refund_total_lbl".t)
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                    Text("฿\(viewModel.refundAmount, specifier: "%.2f")")
                        .font(.title3.weight(.bold))
                        .foregroundColor(.appRose)
                }

                Spacer()

                Button(action: {
                    if requireManagerOverrideForRefund && !sessionManager.can(.managerOverride) {
                        viewModel.showPINSheet = true
                    } else {
                        viewModel.processRefund(modelContext: modelContext)
                    }
                    APHaptic.trigger()
                }) {
                    Label("process_refund_btn".t, systemImage: "arrow.uturn.backward")
                        .apGradientButton(
                            gradient: APGradient.destructive,
                            shadow: APShadow.destructiveGlow,
                            disabled: !viewModel.canProcess
                        )
                }
                .disabled(!viewModel.canProcess)
                .frame(width: 240)
            }
            .padding(APSpacing.md)
        }
        .background(Color.appSurface)
    }

    // MARK: - PIN Entry Sheet

    private var pinEntrySheet: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                VStack(spacing: APSpacing.xl) {
                    Spacer()

                    ZStack {
                        Circle()
                            .fill(Color.appRose.opacity(0.12))
                            .frame(width: 80, height: 80)
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.appRose)
                    }

                    VStack(spacing: APSpacing.sm) {
                        Text("manager_approval_required".t)
                            .font(.title3.weight(.bold))
                            .foregroundColor(.textPrimary)
                        Text("Enter manager PIN to authorize this refund of ฿\(viewModel.refundAmount, specifier: "%.2f")")
                            .font(.subheadline)
                            .foregroundColor(.textSecondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 300)
                    }

                    // PIN dots
                    HStack(spacing: APSpacing.md) {
                        ForEach(0..<4, id: \.self) { i in
                            Circle()
                                .fill(i < viewModel.pinCode.count ? Color.appRose : Color.appSurfaceHigh)
                                .frame(width: 16, height: 16)
                                .overlay(
                                    Circle()
                                        .stroke(Color.appBorderSubtle, lineWidth: 1)
                                )
                                .animation(.spring(response: 0.2), value: viewModel.pinCode.count)
                        }
                    }

                    if let error = viewModel.pinError {
                        Text(error)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.appRose)
                    }

                    // Number pad
                    pinPad

                    Spacer()
                }
                .padding(APSpacing.xl)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L.Common.cancel.t) {
                        viewModel.pinCode = ""
                        viewModel.pinError = nil
                        viewModel.showPINSheet = false
                    }
                    .foregroundColor(.appAccent)
                }
            }
            .toolbarBackground(Color.appSurface, for: .navigationBar)
        }
        .apColorScheme()
        .presentationDetents([.medium, .large])
    }

    private var pinPad: some View {
        let buttons = [
            ["1", "2", "3"],
            ["4", "5", "6"],
            ["7", "8", "9"],
            ["", "0", "⌫"]
        ]

        return VStack(spacing: APSpacing.sm) {
            ForEach(buttons, id: \.self) { row in
                HStack(spacing: APSpacing.sm) {
                    ForEach(row, id: \.self) { key in
                        if key.isEmpty {
                            Color.clear.frame(width: 72, height: 52)
                        } else {
                            Button(action: {
                                handlePINKey(key)
                            }) {
                                Text(key)
                                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                                    .foregroundColor(.textPrimary)
                                    .frame(width: 72, height: 52)
                                    .background(Color.appSurface)
                                    .cornerRadius(APRadius.md)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: APRadius.md)
                                            .stroke(Color.appBorderSubtle, lineWidth: 1)
                                    )
                            }
                        }
                    }
                }
            }
        }
    }

    private func handlePINKey(_ key: String) {
        APHaptic.trigger()
        if key == "⌫" {
            if !viewModel.pinCode.isEmpty {
                viewModel.pinCode.removeLast()
            }
        } else {
            if viewModel.pinCode.count < 4 {
                viewModel.pinCode.append(key)
            }
            if viewModel.pinCode.count == 4 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    if viewModel.validatePIN() {
                        viewModel.showPINSheet = false
                        viewModel.processRefund(modelContext: modelContext)
                    }
                }
            }
        }
    }
}
