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
    var isProcessing: Bool = false
    var isComplete: Bool = false
    var restockItems: Bool = false
    var errorMessage: String?

    var refundableItems: [OrderItem] {
        guard let order = selectedOrder else { return [] }
        return order.items.filter {
            !$0.isDeleted && $0.status != "cancelled" && $0.status != "refunded"
        }
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
        guard selectedOrder != nil,
              refundAmount > 0,
              refundablePaymentBalance + 0.005 >= refundAmount else { return false }
        guard selectedReason != .other || !otherReasonText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return isFullRefund || !selectedItemIds.isEmpty
    }

    var unsupportedPaymentMethods: [String] {
        []
    }

    var hasNonCashPayments: Bool {
        guard let order = selectedOrder else { return false }
        return order.payments.contains {
            $0.paymentMethod != "cash" && remainingBalance(for: $0, in: order) > 0.005
        }
    }

    private var refundablePaymentBalance: Double {
        guard let order = selectedOrder else { return 0 }
        return order.payments.reduce(0) { total, payment in
            total + remainingBalance(for: payment, in: order)
        }
    }

    private func remainingBalance(for payment: Payment, in order: Order) -> Double {
        let refunded = order.refunds
            .filter { $0.originalPayment?.id == payment.id && !$0.isDeleted && $0.status == "completed" }
            .reduce(0.0) { $0 + $1.refundAmount }
        return max(0, payment.amount - refunded)
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

    func processRefund(
        modelContext: ModelContext,
        processorEmployeeId: UUID,
        approvedByEmployeeId: UUID?,
        isAuthorized: Bool
    ) {
        guard isAuthorized, canProcess, let order = selectedOrder else {
            errorMessage = "refund_not_authorized".t
            return
        }
        isProcessing = true
        let itemsBeingRefunded = refundableItems.filter {
            isFullRefund || selectedItemIds.contains($0.id)
        }

        let reasonText = selectedReason == .other ? otherReasonText : selectedReason.rawValue

        // A paid sale remains completed; refund is a separate financial event.
        for item in itemsBeingRefunded {
            item.status = "refunded"
            item.isSynced = false
            item.updatedAt = Date()
        }

        // Create audit log
        let auditLog = AuditLog(
            employeeId: processorEmployeeId,
            actionType: "refund",
            details: "Refund ฿\(String(format: "%.2f", refundAmount)) — Reason: \(reasonText) — Order: \(order.orderNumber)",
            originalValue: order.total,
            newValue: refundAmount
        )
        modelContext.insert(auditLog)

        // Allocate the refund across original tenders without exceeding any payment.
        var amountToAllocate = refundAmount
        for payment in order.payments.sorted(by: { $0.paidAt < $1.paidAt }) where amountToAllocate > 0.005 {
            let previouslyRefunded = order.refunds
                .filter { $0.originalPayment?.id == payment.id && !$0.isDeleted && $0.status == "completed" }
                .reduce(0.0) { $0 + $1.refundAmount }
            let allocation = min(max(0, payment.amount - previouslyRefunded), amountToAllocate)
            guard allocation > 0.005 else { continue }

            let refund = RefundTransaction(
                order: order,
                originalPayment: payment,
                refundAmount: allocation,
                refundMethod: "original_tender",
                reasonCode: selectedReason.rawValue.lowercased().replacingOccurrences(of: " ", with: "_"),
                reasonNotes: reasonText,
                refundedByEmployeeId: processorEmployeeId,
                approvedByEmployeeId: approvedByEmployeeId,
                status: "completed"
            )
            BusinessDayContext.stamp(refund: refund, order: order, in: modelContext)
            modelContext.insert(refund)
            AccountingLedgerService.recordCompletedRefund(refund, order: order, in: modelContext)

            let paymentRefundedTotal = previouslyRefunded + allocation
            payment.status = paymentRefundedTotal >= payment.amount - 0.005 ? "refunded" : "partially_refunded"
            payment.isSynced = false
            payment.updatedAt = Date()
            amountToAllocate -= allocation
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
    @AppStorage("enable_table_system") private var tableSystemEnabled = true
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sessionManager: AppSessionManager
    @EnvironmentObject private var lm: LocalizationManager
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
    @State private var viewAppeared = false
    @State private var selectedOrderAppeared = false
    @State private var showConfirmation = false

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
                        .opacity(viewAppeared ? 1 : 0)
                        .offset(x: viewAppeared ? 0 : -20)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.1), value: viewAppeared)

                    Divider().background(Color.appDivider)

                    // Right: Refund details
                    if viewModel.selectedOrder != nil {
                        refundDetailPanel
                            .opacity(selectedOrderAppeared ? 1 : 0)
                            .offset(x: selectedOrderAppeared ? 0 : 20)
                            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: selectedOrderAppeared)
                    } else {
                        emptyDetailState
                            .opacity(viewAppeared ? 1 : 0)
                            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.2), value: viewAppeared)
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
                ManagerPINVerificationSheet(
                    isPresented: $viewModel.showPINSheet,
                    onSuccess: {},
                    onAuthorizedManager: { manager in
                        processRefund(approvedBy: manager.employeeProfile?.id)
                    }
                )
            }
            .alert("refund_success_title".t, isPresented: $viewModel.isComplete) {
                Button(L.Common.done.t) {
                    dismiss()
                }
            } message: {
                Text(String(format: "refund_success_message".t, viewModel.refundAmount))
            }
            .confirmationDialog("refund_confirm_title".t, isPresented: $showConfirmation, titleVisibility: .visible) {
                Button("process_refund_btn".t, role: .destructive) { authorizeRefund() }
                Button(L.Common.cancel.t, role: .cancel) {}
            } message: {
                Text(confirmationMessage)
            }
            .alert("refund_error_title".t, isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button(L.Common.done.t) { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
        .apColorScheme()
        .onAppear {
            withAnimation { viewAppeared = true }
        }
        .onChange(of: viewModel.selectedOrder) { _, newOrder in
            if newOrder != nil {
                selectedOrderAppeared = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    withAnimation { selectedOrderAppeared = true }
                }
            }
        }
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
        .frame(minWidth: 380, idealWidth: 440, maxWidth: 480)
        .background(Color.appBackground)
    }

    private func orderCard(order: Order) -> some View {
        let isSelected = viewModel.selectedOrder?.id == order.id
        let identity = OrderDisplayIdentity(order: order, tableSystemEnabled: tableSystemEnabled)
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

                if identity.isQuickService || identity.tableNumber != nil {
                    Label(
                        identity.primaryLabel,
                        systemImage: identity.isQuickService ? "number.square.fill" : "tablecells"
                    )
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
        VStack(spacing: APSpacing.md) {
            ZStack {
                Circle()
                    .fill(Color.appSurface)
                    .frame(width: 80, height: 80)
                Image(systemName: "arrow.uturn.backward.circle")
                    .font(.system(size: 36))
                    .foregroundColor(.textTertiary)
            }
            Text("refund_select_order_title".t)
                .font(.headline.weight(.bold))
                .foregroundColor(.textPrimary)
            Text("refund_select_order_desc".t)
                .font(.subheadline)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
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

                    if viewModel.hasNonCashPayments {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.appAmber)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(lm.currentLanguage == .thai ? "บันทึกการคืนเงิน (Manual Reconciliation)" : "Manual Refund Reconciliation")
                                    .font(.caption.bold())
                                    .foregroundColor(.textPrimary)
                                Text(lm.currentLanguage == .thai
                                     ? "ออเดอร์นี้ชำระด้วย QR Code/บัตร ระบบจะบันทึกรายการคืนเงินในบัญชีและรายงาน กรุณาโอนเงินคืนหรือคืนเป็นเงินสดให้ลูกค้าหน้าร้าน"
                                     : "This order was paid with QR/Card. Refund will be recorded in the ledger. Please transfer back or provide cash to the customer manually.")
                                    .font(.caption2)
                                    .foregroundColor(.textSecondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .apCard()
                    }

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
        HStack(spacing: APSpacing.sm) {
            Button(action: {
                withAnimation(.spring(response: 0.3)) {
                    viewModel.selectFullRefund()
                }
                APHaptic.trigger()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: viewModel.isFullRefund ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14))
                        .foregroundColor(viewModel.isFullRefund ? .appRose : .textSecondary)
                    Text("refund_type_full".t)
                        .font(.system(size: 13, weight: .semibold))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule(style: .continuous)
                        .fill(viewModel.isFullRefund ? Color.appRose.opacity(0.15) : Color.appSurface)
                        .overlay(
                            Capsule()
                                .stroke(viewModel.isFullRefund ? Color.appRose.opacity(0.4) : Color.appBorderSubtle, lineWidth: 1)
                        )
                )
                .foregroundColor(viewModel.isFullRefund ? .appRose : .textSecondary)
            }

            Button(action: {
                withAnimation(.spring(response: 0.3)) {
                    viewModel.deselectFullRefund()
                }
                APHaptic.trigger()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: !viewModel.isFullRefund ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14))
                        .foregroundColor(!viewModel.isFullRefund ? .appAccent : .textSecondary)
                    Text("refund_type_partial".t)
                        .font(.system(size: 13, weight: .semibold))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule(style: .continuous)
                        .fill(!viewModel.isFullRefund ? Color.appAccent.opacity(0.15) : Color.appSurface)
                        .overlay(
                            Capsule()
                                .stroke(!viewModel.isFullRefund ? Color.appAccent.opacity(0.4) : Color.appBorderSubtle, lineWidth: 1)
                        )
                )
                .foregroundColor(!viewModel.isFullRefund ? .appAccent : .textSecondary)
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
                    HStack(spacing: APSpacing.sm) {
                        Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                            .font(.system(size: 16))
                            .foregroundColor(isSelected ? .appRose : .textTertiary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.menuItem?.localizedName ?? "Unknown")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.textPrimary)

                            let modNames = item.modifiers.compactMap { $0.modifier?.name }.joined(separator: ", ")
                            if !modNames.isEmpty {
                                Text(modNames)
                                    .font(.caption2)
                                    .foregroundColor(.textSecondary)
                            }
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text("×\(item.quantity)")
                                .font(.caption2.weight(.bold))
                                .foregroundColor(.textSecondary)
                            Text("฿\(item.subtotal, specifier: "%.2f")")
                                .font(.subheadline.weight(.bold))
                                .foregroundColor(isSelected ? .appRose : .textPrimary)
                        }
                    }
                    .padding(.horizontal, APSpacing.md)
                    .padding(.vertical, APSpacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: APRadius.sm, style: .continuous)
                            .fill(isSelected ? Color.appRose.opacity(0.08) : Color.appSurface)
                            .overlay(
                                RoundedRectangle(cornerRadius: APRadius.sm, style: .continuous)
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

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: APSpacing.sm) {
                ForEach(RefundReason.allCases) { reason in
                    let isSelected = viewModel.selectedReason == reason
                    Button(action: {
                        viewModel.selectedReason = reason
                        APHaptic.trigger()
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: reason.icon)
                                .font(.system(size: 11))
                            Text(reason.rawValue)
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
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
                    .padding(.horizontal, APSpacing.md)
                    .padding(.vertical, APSpacing.sm)
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
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundColor(.appRose)
            }

            if let order = viewModel.selectedOrder {
                HStack {
                    Text("refund_original_total_lbl".t)
                        .font(.caption2)
                        .foregroundColor(.textTertiary)
                    Spacer()
                    Text("฿\(order.total, specifier: "%.2f")")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.textSecondary)
                }

                if let payment = order.payments.first {
                    HStack {
                        Text("refund_payment_method_lbl".t)
                            .font(.caption2)
                            .foregroundColor(.textTertiary)
                        Spacer()
                        Text(payment.paymentMethod)
                            .font(.caption2.weight(.medium))
                            .foregroundColor(.textSecondary)
                    }
                }
            }
        }
        .apCard(padding: APSpacing.sm)
    }

    // MARK: - Process Refund Bar

    private var processRefundBar: some View {
        VStack(spacing: 0) {
            Divider().background(Color.appDivider)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("refund_total_lbl".t)
                        .font(.caption2)
                        .foregroundColor(.textSecondary)
                    Text("฿\(viewModel.refundAmount, specifier: "%.2f")")
                        .font(.title3.weight(.bold))
                        .foregroundColor(.appRose)
                }

                Spacer()

                Button(action: {
                    showConfirmation = true
                    APHaptic.trigger()
                }) {
                    Label("process_refund_btn".t, systemImage: "arrow.uturn.backward")
                        .font(.subheadline.weight(.semibold))
                        .apGradientButton(
                            gradient: APGradient.destructive,
                            shadow: APShadow.destructiveGlow,
                            disabled: !viewModel.canProcess
                        )
                }
                .disabled(!viewModel.canProcess)
                .frame(width: 200)
            }
            .padding(.horizontal, APSpacing.md)
            .padding(.vertical, APSpacing.sm)
        }
        .background(Color.appSurface)
    }

    private var confirmationMessage: String {
        guard let order = viewModel.selectedOrder else { return "" }
        return String(format: "refund_confirm_message".t, order.orderNumber, viewModel.refundAmount)
    }

    private func authorizeRefund() {
        guard sessionManager.can(.refundCreate) else {
            viewModel.errorMessage = "refund_not_authorized".t
            return
        }
        if requireManagerOverrideForRefund && !sessionManager.can(.managerOverride) {
            viewModel.showPINSheet = true
        } else {
            let approver = requireManagerOverrideForRefund ? sessionManager.currentStaffSession?.employeeId : nil
            processRefund(approvedBy: approver)
        }
    }

    private func processRefund(approvedBy: UUID?) {
        guard let processor = sessionManager.currentStaffSession?.employeeId else {
            viewModel.errorMessage = "refund_not_authorized".t
            return
        }
        viewModel.processRefund(
            modelContext: modelContext,
            processorEmployeeId: processor,
            approvedByEmployeeId: approvedBy,
            isAuthorized: sessionManager.can(.refundCreate)
        )
    }

}
