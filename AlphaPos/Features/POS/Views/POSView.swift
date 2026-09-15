// POSView.swift
// AlphaPos — Premium POS Interface

import SwiftUI
import SwiftData
import UIKit

struct POSView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var sessionManager: AppSessionManager
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var lm: LocalizationManager
    @ObservedObject private var printService = PrintService.shared
    @Query(filter: #Predicate<Category> { !$0.isDeleted }, sort: \Category.name) private var categories: [Category]
    @Query(filter: #Predicate<RegisterSession> { $0.closedAt == nil && !$0.isDeleted })
    private var activeRegisterSessions: [RegisterSession]
    @Query(filter: #Predicate<CheckoutSession> {
        $0.state == "parked" && !$0.isDeleted
    }, sort: \CheckoutSession.updatedAt, order: .reverse)
    private var parkedCheckouts: [CheckoutSession]
    @Query(filter: #Predicate<Order> {
        !$0.isDeleted && $0.orderType != "dine_in" &&
        $0.status != "completed" && $0.status != "cancelled"
    }, sort: \Order.createdAt, order: .forward)
    private var quickOrderQueue: [Order]

    @Binding var activeSession: TableSession?
    @Binding var selectedTab: MainDashboardView.DashboardTab
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @Binding var focusedOrderNumber: String?
    @Binding var quickOrderMode: Bool

    @AppStorage("enable_table_system") private var enableTableSystem = true
    @AppStorage("require_manager_override_for_void") private var requireManagerOverrideForVoid = true

    @AppStorage("payment_method_cash_enabled") private var cashEnabled = true
    @AppStorage("payment_method_card_enabled") private var cardEnabled = true
    @AppStorage("payment_method_qr_enabled") private var qrEnabled = true
    @AppStorage(GovernmentSupportProgram.enabledSettingsKey) private var thaiChuaThaiPlusEnabled = true
    @AppStorage("enable_tax") private var enableTax = true
    @AppStorage("enable_service_charge") private var enableServiceCharge = true
    @AppStorage("store_tax_rate") private var storeTaxRate = 7.0
    @AppStorage("store_service_charge_rate") private var storeServiceChargeRate = 10.0
    @AppStorage("tax_apply_dine_in") private var taxApplyDineIn = true
    @AppStorage("tax_apply_take_out") private var taxApplyTakeOut = true
    @AppStorage("tax_apply_delivery") private var taxApplyDelivery = true
    @AppStorage("service_charge_apply_dine_in") private var serviceChargeApplyDineIn = true
    @AppStorage("service_charge_apply_take_out") private var serviceChargeApplyTakeOut = false
    @AppStorage("service_charge_apply_delivery") private var serviceChargeApplyDelivery = false

    @State private var viewModel = POSViewModel()
    @State private var catalog = POSCatalogStore()
    @State private var showNoActiveShiftAlert = false
    @State private var showStartShiftSheet = false
    @State private var showOwnerPinSetup = false
    @State private var showStaleShiftCloseSheet = false
    @State private var staleSessionToClose: RegisterSession? = nil
    @State private var searchQuery = ""
    // A recovered or newly-synced catalog may contain no favorites. Starting on
    // "All" prevents a healthy catalog from looking as if every product vanished.
    @State private var showFavoritesOnly = false
    @State private var animateItems = false
    @State private var cartItemBeingEdited: UUID? = nil
    @State private var showNoteAlert = false
    @State private var showPreBillPrintAlert = false
    @State private var preBillPrintMessage = ""
    @State private var showPrinterControls = false
    @State private var didTriggerPrinterLongPress = false
    @State private var isPrinterButtonPressed = false
    @State private var showReceiptCopyPicker = false
    @State private var showPromotionPicker = false
    @State private var noteText = ""
    @State private var itemToEditNote: UUID? = nil
    @State private var editingNoteForOrderedItem: (identity: String, status: String)? = nil

    enum ActivePaymentMethod: Identifiable {
        case cash
        case qrCode
        case creditCard
        case thaiChuaThaiPlus

        var id: Int {
            switch self {
            case .cash: return 1
            case .qrCode: return 2
            case .creditCard: return 3
            case .thaiChuaThaiPlus: return 4
            }
        }
    }

    @State private var activePayment: ActivePaymentMethod? = nil
    @State private var externalAppHandoff = ExternalAppHandoff()
    @State private var externalAppLaunchID = UUID()
    @State private var showTungNgernOpenFailure = false
    @AppStorage("tung_ngern_open_shortcut_configured") private var tungNgernShortcutConfigured = false
    @State private var showTungNgernShortcutSetup = false
    @State private var showCustomerPicker = false
    @State private var showHeldOrders = false
    @State private var showQuickOrderQueue = false
    @State private var showUnsavedCartNavigationAlert = false
    @State private var showPendingCheckouts = false
    @State private var showRefund = false
    @State private var focusedNotificationOrder: Order?
    @State private var showSplitPayment = false
    @State private var showDeliveryNumberModal = false
    @State private var deliveryCanScrollLeading = false
    @State private var deliveryCanScrollTrailing = true
    // C-1: Gift Card
    @State private var showGiftCardPicker = false
    @Query(filter: #Predicate<GiftCard> { $0.status == "active" && !$0.isDeleted })
    private var activeGiftCards: [GiftCard]

    // MARK: - Error Handling
    @State private var errorMessage: String? = nil
    @State private var showingErrorBanner = false
    @State private var isProcessingCheckout = false
    /// Quick Service uses a pay-first workflow. Staff explicitly confirms the
    /// ticket before tender choices are exposed; the queue is only persisted
    /// together with successful checkout.
    @State private var isQuickServiceCheckoutConfirmed = false
    /// POS can run in Quick Order mode even when table service is enabled.
    /// This mode never creates or selects a table session.
    /// Three compact columns fit a standard iPad checkout panel. The grid drops
    /// to two only for genuinely narrow split-view widths.
    @State private var paymentGridColumnCount = 3

    // Loyalty Points form bindings
    @State private var localUseLoyaltyPoints = false
    @State private var localRedeemLoyaltyPoints = 0
    @State private var couponInput = ""
    @State private var sentToKitchenVersion: Int = 0  // incremented after send-to-kitchen to force ordered-items re-render

    // Persisted items are voided, never silently deleted.
    @State private var showVoidPINSheet = false
    @State private var pendingVoidItem: GroupedOrderedItem? = nil
    @State private var pendingVoidReason = ""
    @State private var showVoidReasonDialog = false

    /// Prefer a non–soft-deleted session. Callers must clear `activeSession`
    /// before any hard wipe so this never observes an invalidated model.
    private var liveActiveSession: TableSession? {
        guard let session = activeSession, session.isActive, !session.isDeleted else { return nil }
        return session
    }

    /// Table service is a POS mode, not a merchant-wide POS visibility flag.
    private var isTableServiceMode: Bool {
        enableTableSystem && !quickOrderMode
    }

    // MARK: - Grouped Ordered Items

    struct GroupedOrderedItem: Identifiable {
        let id: String
        let identity: String
        let displayName: String
        let quantity: Int
        let status: String
        let totalPrice: Double
        let selectedModifiers: [Modifier]
        let notes: String
        let imageURL: String?
        let imageData: Data?
        let colorHex: String?
    }

    /// True when an order has been settled — either explicitly marked
    /// "completed" or carrying at least one completed (non-deleted) payment.
    /// Used to drop paid bills from the live payment surface so they cannot be
    /// charged twice and no longer clutter the cart.
    static func isOrderSettled(_ order: Order) -> Bool {
        order.isSettled
    }

    private var sessionOrdersForDisplay: [Order] {
        guard let session = liveActiveSession else { return [] }
        // Exclude orders that are already settled (paid / completed). A bill
        // paid on a staff phone syncs back here with status "completed" and a
        // completed payment; without this filter it would keep showing in the
        // cart and the payment buttons would stay active — allowing a double
        // charge and leaving served items on screen.
        var orders = session.orders.filter { !$0.isDeleted && !Self.isOrderSettled($0) }
        if let recent = viewModel.recentlySubmittedTableOrder,
           recent.tableSession?.id == session.id,
           !recent.isDeleted,
           !orders.contains(where: { $0.id == recent.id }) {
            orders.append(recent)
        }
        return orders
    }

    private var groupedOrderedItems: [GroupedOrderedItem] {
        let rawItems = sessionOrdersForDisplay
            .flatMap { $0.items }
            .filter { !$0.isDeleted && $0.status != "cancelled" && $0.status != "refunded" }

        var groups: [String: (identity: String, name: String, qty: Int, status: String, price: Double, mods: [Modifier], notes: String, imageURL: String?, imageData: Data?, colorHex: String?)] = [:]
        for item in rawItems {
            let identity = orderedItemIdentity(item)
            let displayName = item.menuItem?.localizedName ?? item.itemName
            guard !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let mods = item.modifiers.compactMap { $0.modifier }
            let modKey = mods.map { $0.id.uuidString }.sorted().joined(separator: "-")
            let itemNotes = item.notes ?? ""
            let imageURL = item.menuItem?.imageUrl
            let imageData = item.menuItem?.imageData
            let colorHex = item.menuItem?.colorHex
            let key = "\(identity)-\(item.status)-\(modKey)-\(itemNotes)"

            if let existing = groups[key] {
                groups[key] = (identity, displayName, existing.qty + item.quantity, item.status, existing.price + item.subtotal, existing.mods, itemNotes, existing.imageURL, existing.imageData, existing.colorHex)
            } else {
                groups[key] = (identity, displayName, item.quantity, item.status, item.subtotal, mods, itemNotes, imageURL, imageData, colorHex)
            }
        }

        return groups.map { GroupedOrderedItem(id: $0.key, identity: $0.value.identity, displayName: $0.value.name, quantity: $0.value.qty, status: $0.value.status, totalPrice: $0.value.price, selectedModifiers: $0.value.mods, notes: $0.value.notes, imageURL: $0.value.imageURL, imageData: $0.value.imageData, colorHex: $0.value.colorHex) }
            .sorted(by: {
                if $0.displayName != $1.displayName {
                    return $0.displayName < $1.displayName
                }
                if $0.status != $1.status {
                    return $0.status < $1.status
                }
                return $0.id < $1.id
            })
    }

    private func orderedItemIdentity(_ item: OrderItem) -> String {
        if let menuItem = item.menuItem {
            return "menu:\(menuItem.id)"
        }
        let fallbackName = item.itemName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !fallbackName.isEmpty {
            return "name:\(fallbackName.lowercased())"
        }
        return "order-item:\(item.id.uuidString)"
    }

    private var isAllServed: Bool {
        let rawItems = sessionOrdersForDisplay
            .flatMap { $0.items }
            .filter { !$0.isDeleted && $0.status != "cancelled" && $0.status != "refunded" }
        guard !rawItems.isEmpty else { return false }
        return rawItems.allSatisfy { $0.status == "served" }
    }

    private var hasSessionOrderedItems: Bool {
        sessionOrdersForDisplay.contains { order in
            order.items.contains { !$0.isDeleted && $0.status != "cancelled" && $0.status != "refunded" }
        }
    }

    private struct SessionFinanceSnapshot {
        var subtotal: Double = 0.0
        var tax: Double = 0.0
        var serviceCharge: Double = 0.0
        var discount: Double = 0.0
        var total: Double = 0.0
    }

    private struct DisplayFinancials {
        let subtotal: Double
        let tax: Double
        let serviceCharge: Double
        let discount: Double
        let total: Double
    }

    private var sessionFinancials: SessionFinanceSnapshot {
        let orders = sessionOrdersForDisplay
        guard !orders.isEmpty else { return SessionFinanceSnapshot() }
        var snapshot = SessionFinanceSnapshot()
        for order in orders {
            snapshot.subtotal += order.subtotal
            snapshot.tax += order.tax
            snapshot.serviceCharge += order.serviceCharge
            snapshot.discount += order.discount
            snapshot.total += order.total
        }
        return snapshot
    }

    private var currentDisplayFinancials: DisplayFinancials {
        let session = sessionFinancials
        return DisplayFinancials(
            subtotal: viewModel.cartSubtotal + session.subtotal,
            tax: viewModel.cartTax + session.tax,
            serviceCharge: viewModel.cartServiceCharge + session.serviceCharge,
            discount: viewModel.cartDiscount + session.discount,
            total: viewModel.cartTotal + session.total
        )
    }

    private var sessionOrderedSubtotal: Double { sessionFinancials.subtotal }
    private var sessionOrderedTax: Double { sessionFinancials.tax }
    private var sessionOrderedServiceCharge: Double { sessionFinancials.serviceCharge }
    private var sessionOrderedDiscount: Double { sessionFinancials.discount }
    private var sessionOrderedTotal: Double { sessionFinancials.total }

    private var displaySubtotal: Double {
        currentDisplayFinancials.subtotal
    }

    private var displayedItemQuantity: Int {
        let cartQty = viewModel.cart.reduce(0) { $0 + $1.quantity }
        let sessionQty = sessionOrdersForDisplay.reduce(0) { orderSum, order in
            orderSum + order.items.reduce(0) { itemSum, item in
                (!item.isDeleted && item.status != "cancelled" && item.status != "refunded") ? itemSum + item.quantity : itemSum
            }
        }
        return cartQty + sessionQty
    }

    private var displayTax: Double {
        currentDisplayFinancials.tax
    }

    private var displayServiceCharge: Double {
        currentDisplayFinancials.serviceCharge
    }

    private var displayDiscount: Double {
        currentDisplayFinancials.discount
    }

    private var appliedPromotionTitle: String? {
        if let code = viewModel.appliedCouponCode, let title = viewModel.activePromotion?.title {
            return "\(code) · \(title)"
        }
        return viewModel.activePromotion?.title ?? sessionOrdersForDisplay
            .flatMap(\.discounts)
            .first { !$0.isDeleted && $0.discountAmount > 0 }?
            .promotion?.title
    }

    private var displayTotal: Double {
        currentDisplayFinancials.total
    }

    private var quickServiceCartFingerprint: Int {
        var hasher = Hasher()
        hasher.combine(viewModel.cart.count)
        for item in viewModel.cart {
            hasher.combine(item.id)
            hasher.combine(item.quantity)
            hasher.combine(item.notes)
            for mod in item.selectedModifiers {
                hasher.combine(mod.id)
            }
        }
        return hasher.finalize()
    }

    private var shouldShowPaymentActions: Bool {
        if isTableServiceMode {
            if liveActiveSession == nil {
                return !viewModel.cart.isEmpty
            }
            return viewModel.cart.isEmpty && isAllServed
        }
        return !viewModel.cart.isEmpty
    }

    private var canPrintPreBill: Bool {
        !viewModel.cart.isEmpty ||
        (isTableServiceMode && liveActiveSession != nil && !sessionOrdersForDisplay.isEmpty)
    }

    @discardableResult
    private func completePayment(methodName: String, cashTendered: Double? = nil, transactionReference: String? = nil) async -> Bool {
        if isTableServiceMode, liveActiveSession != nil {
            return await completeCheckout(methodName: methodName, cashTendered: cashTendered, transactionReference: transactionReference)
        } else {
            return await completeDirectCheckout(methodName: methodName, cashTendered: cashTendered, transactionReference: transactionReference)
        }
    }

    private func parkPayment(methodName: String) {
        guard liveActiveSession == nil else {
            showError("Table checks remain attached to their table and do not need to be parked.")
            return
        }
        guard viewModel.parkCurrentCheckout(method: methodName) != nil else {
            showError("ไม่สามารถพักการชำระเงินได้ กรุณาลองใหม่")
            return
        }
        activePayment = nil
        APHaptic.trigger()
    }

    private func printPreBill() {
        let orders = sessionOrdersForDisplay.filter { !$0.isSettled }
        guard !orders.isEmpty || !viewModel.cart.isEmpty else {
            preBillPrintMessage = "ไม่มีรายการค้างชำระสำหรับพิมพ์ใบตรวจรายการ"
            showPreBillPrintAlert = true
            return
        }

        Task {
            let result: PrintResult
            if !orders.isEmpty {
                result = await PrintService.shared.dispatchPreBill(orders: orders)
            } else {
                let draft = PreBillDraft(
                    orderReference: viewModel.currentQueueNumber.isEmpty ? "AP-NEW" : viewModel.currentQueueNumber,
                    orderType: viewModel.selectedOrderType,
                    guestCount: viewModel.guestCount,
                    items: viewModel.cart.map { item in
                        PreBillDraftItem(
                            name: item.snapshotLocalizedName.isEmpty ? item.snapshotName : item.snapshotLocalizedName,
                            quantity: item.quantity,
                            unitPrice: item.snapshotPrice,
                            modifiers: item.selectedModifiers.map {
                                PreBillDraftModifier(name: $0.name, price: $0.extraPrice)
                            },
                            notes: item.notes
                        )
                    },
                    subtotal: displaySubtotal,
                    tax: displayTax,
                    serviceCharge: displayServiceCharge,
                    discount: displayDiscount,
                    total: displayTotal
                )
                result = await PrintService.shared.dispatchPreBill(draft: draft)
            }
            await MainActor.run {
                preBillPrintMessage = result.success
                    ? "ส่งพิมพ์ใบตรวจรายการให้ลูกค้าแล้ว"
                    : "พิมพ์ใบตรวจรายการไม่สำเร็จ: \(result.message)"
                showPreBillPrintAlert = true
            }
        }
    }

    @discardableResult
    private func completeDirectCheckout(methodName: String, cashTendered: Double? = nil, transactionReference: String? = nil) async -> Bool {
        guard !isProcessingCheckout else { return false }
        isProcessingCheckout = true
        defer { isProcessingCheckout = false }

        await viewModel.allocateCounterServiceIdentifiersIfNeeded()
        guard viewModel.processCheckout(
            tableSession: nil,
            createPayment: true,
            paymentMethod: methodName,
            cashTendered: cashTendered,
            transactionReference: transactionReference
        ) != nil else { return false }

        APHaptic.trigger()
        APSoundEffect.paymentSuccess()
        return true
    }

    @discardableResult
    private func completeCheckout(methodName: String, cashTendered: Double? = nil, transactionReference: String? = nil) async -> Bool {
        guard !isProcessingCheckout else { return false }
        isProcessingCheckout = true
        defer { isProcessingCheckout = false }

        guard let session = liveActiveSession else { return false }

        let unpaidOrders = sessionOrdersForDisplay.filter {
            !$0.isDeleted && $0.status != "cancelled" && !$0.isSettled
        }
        guard !unpaidOrders.isEmpty else {
            showError("ไม่พบออเดอร์ค้างชำระ กรุณาซิงก์ข้อมูลแล้วลองใหม่")
            return false
        }

        var ordersToPay: [Order] = []
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        // 1. Create payment records for any unpaid orders in the session and mark them completed
        for order in unpaidOrders {
            if methodName == GovernmentSupportProgram.thaiChuaThaiPlus {
                let split = GovernmentSupportProgram.split(total: order.total)
                order.supportProgramName = GovernmentSupportProgram.thaiChuaThaiPlus
                order.supportGovernmentRate = GovernmentSupportProgram.governmentRate
                order.supportCitizenAmount = split.citizen
                order.supportGovernmentAmount = split.government
                order.supportSettlementStatus = "pending"
            }
            if order.receiptNumber?.isEmpty != false {
                order.receiptNumber = NetworkManager.localFallbackReceiptNumber(merchantId: merchantId)
            }
            if order.status == "preparing" || order.status == "ready" {
                order.status = "completed"
                order.isSynced = false
                order.updatedAt = Date()

                for item in order.items {
                    if item.status == "cooking" {
                        item.status = "served"
                        item.isSynced = false
                        item.updatedAt = Date()
                    }
                }
            }
            let customerOutstanding = order.usesGovernmentSupport
                ? max(0, order.supportCitizenAmount - order.paidAmount)
                : order.outstandingAmount
            if customerOutstanding > 0 {
                let payment = Payment(paymentMethod: methodName, amount: customerOutstanding)
                if let cashTendered, cashTendered > 0 {
                    payment.transactionReference = Payment.cashTenderedReference(cashTendered)
                } else if let transactionReference, !transactionReference.isEmpty {
                    payment.transactionReference = transactionReference
                } else if order.usesGovernmentSupport {
                    payment.transactionReference = Payment.thaiChuaThaiInternalReference(orderNumber: order.orderNumber)
                }
                payment.order = order
                BusinessDayContext.stamp(payment: payment, order: order, in: modelContext)
                modelContext.insert(payment)
                AccountingLedgerService.recordCapturedPayment(payment, order: order, in: modelContext)
                ordersToPay.append(order)
            }
        }

        // 2. Close remote sessions (leader + joined children), then sync.
        // Always run syncAll even if close fails so local dirty state still pushes.
        let leader = session.table?.joinedParent ?? session.table
        let tableNumbers: [String] = {
            guard let leader else {
                let fallback = session.table?.tableNumber ?? ""
                return fallback.isEmpty ? [] : [fallback]
            }
            return ([leader] + leader.joinedChildren).map(\.tableNumber).filter { !$0.isEmpty }
        }()

        // 3. Mark session inactive and set group status to cleaning
        session.isActive = false
        session.endedAt = Date()
        session.isSynced = false
        session.updatedAt = Date()

        if let leader {
            leader.status = "cleaning"
            leader.isSynced = false
            leader.updatedAt = Date()
            for child in leader.joinedChildren {
                child.status = "cleaning"
                child.isSynced = false
                child.updatedAt = Date()
            }
        } else if let table = session.table {
            table.status = "cleaning"
            table.isSynced = false
            table.updatedAt = Date()
        }

        let saveSuccess = modelContext.saveWithLogging(label: #function)
        guard saveSuccess else {
            showError("เกิดข้อผิดพลาดในการบันทึกข้อมูล กรุณาลองใหม่อีกครั้ง")
            return false
        }

        Task {
            var closeFailed = false
            for number in tableNumbers {
                do {
                    _ = try await NetworkManager.shared.closeTableSession(tableNumber: number)
                } catch {
                    closeFailed = true
                }
            }
            await SyncEngine.shared.syncAll(modelContext: modelContext)
            if closeFailed {
                await MainActor.run {
                    showError(L.Errors.syncError.t)
                }
            }
        }

        // Print receipt for every paid order in this session (parallel)
        let capturedOrders = ordersToPay
        Task {
            await withTaskGroup(of: Void.self) { group in
                for order in capturedOrders {
                    group.addTask { await PrintService.shared.dispatchReceipt(order) }
                }
            }
        }

        activeSession = nil
        selectedTab = .tables
        APHaptic.trigger()
        APSoundEffect.paymentSuccess()
        return true
    }

    private func completeSplitCheckout(entries: [SplitPaymentEntry]) {
        if !isTableServiceMode || liveActiveSession == nil {
            completeDirectSplitCheckout(entries: entries)
            return
        }

        guard let session = liveActiveSession else { return }

        let unpaidOrders = sessionOrdersForDisplay.filter {
            !$0.isDeleted && $0.status != "cancelled" && !$0.isSettled
        }
        guard !unpaidOrders.isEmpty else { return }

        let amountDue = unpaidOrders.reduce(0) { $0 + $1.outstandingAmount }
        guard abs(entries.reduce(0) { $0 + $1.amount } - amountDue) < 0.005 else {
            showError("ยอดแบ่งชำระต้องเท่ากับยอดค้าง ฿\(String(format: "%.2f", amountDue))")
            return
        }

        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        for order in unpaidOrders {
            if order.receiptNumber?.isEmpty != false {
                order.receiptNumber = NetworkManager.localFallbackReceiptNumber(merchantId: merchantId)
            }
            if order.status == "preparing" || order.status == "ready" {
                order.status = "completed"
                order.isSynced = false
                order.updatedAt = Date()

                for item in order.items {
                    if item.status == "cooking" {
                        item.status = "served"
                        item.isSynced = false
                        item.updatedAt = Date()
                    }
                }
            }
        }

        var remainingPaymentEntries = entries.map { (method: $0.method, amount: $0.amount) }
        for order in unpaidOrders {
            var orderRemaining = order.outstandingAmount

            while orderRemaining > 0 && !remainingPaymentEntries.isEmpty {
                var entry = remainingPaymentEntries[0]
                if entry.amount <= 0 {
                    remainingPaymentEntries.removeFirst()
                    continue
                }
                let payAmount = min(orderRemaining, entry.amount)
                let payment = Payment(paymentMethod: entry.method, amount: payAmount)
                payment.order = order
                BusinessDayContext.stamp(payment: payment, order: order, in: modelContext)
                modelContext.insert(payment)
                AccountingLedgerService.recordCapturedPayment(payment, order: order, in: modelContext)

                orderRemaining -= payAmount
                entry.amount -= payAmount
                if entry.amount <= 0 {
                    remainingPaymentEntries.removeFirst()
                } else {
                    remainingPaymentEntries[0] = entry
                }
            }
        }

        let leader = session.table?.joinedParent ?? session.table
        let tableNumbers = leader.map {
            ([$0] + $0.joinedChildren).map(\.tableNumber).filter { !$0.isEmpty }
        } ?? []
        Task {
            var closeFailed = false
            for tableNumber in tableNumbers {
                do {
                    _ = try await NetworkManager.shared.closeTableSession(tableNumber: tableNumber)
                } catch {
                    closeFailed = true
                }
            }
            await SyncEngine.shared.syncAll(modelContext: modelContext)
            if closeFailed {
                await MainActor.run {
                    showError(L.Errors.syncError.t)
                }
            }
        }

        session.isActive = false
        session.endedAt = Date()
        session.isSynced = false
        session.updatedAt = Date()

        if let leader {
            for table in [leader] + leader.joinedChildren {
                table.status = "cleaning"
                table.isSynced = false
                table.updatedAt = Date()
            }
        }

        guard modelContext.saveWithLogging(label: #function) else {
            showError("เกิดข้อผิดพลาดในการบันทึกข้อมูล กรุณาลองใหม่อีกครั้ง")
            return
        }

        // Print receipt for every paid order in this session (same as completeCheckout)
        let capturedOrders = unpaidOrders
        Task {
            await withTaskGroup(of: Void.self) { group in
                for order in capturedOrders {
                    group.addTask { await PrintService.shared.dispatchReceipt(order) }
                }
            }
        }

        activeSession = nil
        selectedTab = .tables
        APHaptic.trigger()
        APSoundEffect.paymentSuccess()
    }

    private func completeDirectSplitCheckout(entries: [SplitPaymentEntry]) {
        Task { @MainActor in
            await viewModel.allocateCounterServiceIdentifiersIfNeeded(includeReceipt: true)
            guard let order = viewModel.processCheckout(tableSession: nil, createPayment: false, dispatchPrint: false) else { return }

            if order.receiptNumber == nil || order.receiptNumber?.isEmpty == true {
                let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
                order.receiptNumber = viewModel.currentReceiptNumber.isEmpty
                    ? NetworkManager.localFallbackReceiptNumber(merchantId: merchantId)
                    : viewModel.currentReceiptNumber
            }

            for entry in entries {
                let payment = Payment(paymentMethod: entry.method, amount: entry.amount)
                payment.order = order
                BusinessDayContext.stamp(payment: payment, order: order, in: modelContext)
                modelContext.insert(payment)
                AccountingLedgerService.recordCapturedPayment(payment, order: order, in: modelContext)
            }

            order.status = "completed"
            order.isSynced = false
            order.updatedAt = Date()
            guard modelContext.saveWithLogging(label: #function) else {
                showError("เกิดข้อผิดพลาดในการบันทึกข้อมูล กรุณาลองใหม่อีกครั้ง")
                return
            }

            await SyncEngine.shared.syncAll(modelContext: modelContext)
            // Split checkout path — this is a payment confirmation (not send-to-kitchen)
            await PrintService.shared.dispatchReceipt(order)
            APHaptic.trigger()
            APSoundEffect.paymentSuccess()
        }
    }

    private var hasPendingSelfOrders: Bool {
        sessionOrdersForDisplay.contains { order in
            guard !order.isDeleted else { return false }
            return order.status == "pending" ||
                   (order.orderSource == "web" && !order.isStaffConfirmed)
        }
    }

    private func approvePendingSelfOrders() {
        guard let session = liveActiveSession else { return }

        // Web orders remain pending until a staff member explicitly approves them.
        let ordersToApprove = session.orders.filter { order in
            guard !order.isDeleted else { return false }
            return order.status == "pending" ||
                   (order.orderSource == "web" && !order.isStaffConfirmed)
        }
        for order in ordersToApprove {
            if order.status == "pending" { order.status = "preparing" }
            // Staff confirmation for web orders — this is what unblocks kitchen
            // printing for orderSource == "web" (see PrintService.staffConfirmedForKitchen).
            order.isStaffConfirmed = true
            for item in order.items {
                if !item.isDeleted && item.status == "pending" {
                    item.status = "cooking"
                    item.isSynced = false
                    item.updatedAt = Date()
                }
            }
            order.isSynced = false
            order.updatedAt = Date()
        }

        session.isSynced = false
        session.updatedAt = Date()

        modelContext.saveWithLogging(label: #function)

        APHaptic.trigger()
        sentToKitchenVersion += 1

        Task {
            // The server changes the order header and every pending line in one
            // transaction. Local sync then converges all iPads/iPhones to it.
            for order in ordersToApprove {
                try? await NetworkManager.shared.approveCustomerOrder(orderId: order.id)
            }
            // Approval unblocks kitchen printing (isStaffConfirmed = true) and
            // syncs that state up. To avoid double-printing when a SEPARATE iPad
            // is the designated kitchen print station, this device prints
            // directly only when it is itself the station. Otherwise the station
            // iPad picks the now-confirmed order up via handleRemoteKitchenPrint
            // on the realtime change — a single printer path, no duplicates.
            let isThisDeviceStation = UserDefaults.standard.object(
                forKey: "remote_kitchen_print_enabled") as? Bool ?? true
            if PrintRoutingGate.approvingDeviceShouldPrint(isThisDeviceStation: isThisDeviceStation) {
                // Idempotent: only unprinted "cooking" lines are sent, and
                // PrintJobRecord + per-item printedAt stamps prevent duplicates.
                for order in ordersToApprove {
                    await PrintService.shared.dispatchIncrementalKitchenOrder(order)
                }
            }
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }

    private func beginVoid(_ orderedItem: GroupedOrderedItem) {
        guard sessionManager.can(.orderVoid) else {
            showError("void_not_authorized".t)
            return
        }
        pendingVoidItem = orderedItem
        pendingVoidReason = ""
        showVoidReasonDialog = true
    }

    private func authorizePendingVoid(reason: String) {
        guard let item = pendingVoidItem else { return }
        pendingVoidReason = reason
        let highRiskStatuses: Set<String> = ["cooking", "ready", "served", "alert"]
        let requiresManager = requireManagerOverrideForVoid || highRiskStatuses.contains(item.status)
        if requiresManager && !sessionManager.can(.managerOverride) {
            showVoidPINSheet = true
        } else {
            let approver = requiresManager ? sessionManager.currentStaffSession?.employeeId : nil
            voidOrderedItem(item, approvedBy: approver)
        }
    }

    private func voidOrderedItem(_ orderedItem: GroupedOrderedItem, approvedBy: UUID?) {
        guard sessionManager.can(.orderVoid),
              let processor = sessionManager.currentStaffSession?.employeeId,
              !pendingVoidReason.isEmpty else {
            showError("void_not_authorized".t)
            return
        }
        let targetIdentity = orderedItem.identity
        let targetStatus = orderedItem.status
        for order in sessionOrdersForDisplay {
            let matchedItems = order.items.filter {
                !$0.isDeleted && $0.status != "cancelled" &&
                orderedItemIdentity($0) == targetIdentity && $0.status == targetStatus
            }
            let voidedSubtotal = matchedItems.reduce(0.0) { $0 + $1.subtotal }
            guard voidedSubtotal > 0 else { continue }

            let originalSubtotal = order.subtotal
            let remainingRatio = originalSubtotal > 0 ? max(0, (originalSubtotal - voidedSubtotal) / originalSubtotal) : 0
            if !order.isDeleted {
                for item in matchedItems {
                            item.status = "cancelled"
                            item.isSynced = false
                            item.updatedAt = Date()

                }
                let references = Set(matchedItems.flatMap { [$0.id] + $0.modifiers.map(\.id) })
                InventoryReversalService.reverse(
                    referenceIds: references,
                    as: .void,
                    notes: "Void ordered item — Order: \(order.orderNumber)",
                    in: modelContext
                )
                order.subtotal = max(0, originalSubtotal - voidedSubtotal)
                order.tax *= remainingRatio
                order.serviceCharge *= remainingRatio
                order.discount *= remainingRatio
                order.total = max(0, order.subtotal + order.tax + order.serviceCharge - order.discount)
                order.isSynced = false
                order.updatedAt = Date()
            }
        }
        logVoidAudit(orderedItem, processor: processor, approvedBy: approvedBy, reason: pendingVoidReason)
        modelContext.saveWithLogging(label: #function)
        viewModel.syncFromSession(liveActiveSession, activeCashierName: activeCashierDisplayName)
        pendingVoidItem = nil
        pendingVoidReason = ""
        APHaptic.trigger()
    }

    private func logVoidAudit(_ orderedItem: GroupedOrderedItem, processor: UUID, approvedBy: UUID?, reason: String) {
        let orderNumbers = sessionOrdersForDisplay
            .filter { order in order.items.contains { orderedItemIdentity($0) == orderedItem.identity } }
            .map(\.orderNumber).joined(separator: ", ")
        let audit = AuditLog(
            employeeId: processor,
            actionType: "item_void",
            details: "Orders: \(orderNumbers) — Voided '\(orderedItem.displayName)' ×\(orderedItem.quantity) — Previous status: \(orderedItem.status) — Reason: \(reason) — Processor: \(processor.uuidString) — Approver: \(approvedBy?.uuidString ?? "not_required")",
            originalValue: orderedItem.totalPrice,
            newValue: 0
        )
        modelContext.insert(audit)
        Task { await SyncEngine.shared.syncAll(modelContext: modelContext) }
    }

    private func editNoteForOrderedItemAction(_ orderedItem: GroupedOrderedItem) {
        noteText = orderedItem.notes
        editingNoteForOrderedItem = (orderedItem.identity, orderedItem.status)
        showNoteAlert = true
        APHaptic.trigger()
    }

    private func deleteCartItem(_ cartItem: CartItem) {
        if let idx = viewModel.cart.firstIndex(where: { $0.id == cartItem.id }) {
            viewModel.cart.remove(at: idx)
        }
        APHaptic.trigger()
    }

    private func editCartItem(_ cartItem: CartItem) {
        // Re-fetch a fresh, valid MenuItem by id rather than reusing the cart's
        // possibly-invalidated model reference (a background sync may have
        // tombstoned/deleted it). This keeps the customization sheet crash-safe.
        let itemId = cartItem.snapshotItemId
        var desc = FetchDescriptor<MenuItem>(predicate: #Predicate { $0.id == itemId && !$0.isDeleted })
        desc.fetchLimit = 1
        guard let liveItem = try? modelContext.fetch(desc).first else {
            // The menu item no longer exists — inform the user instead of crashing.
            viewModel.presentAlert("รายการนี้ไม่มีอยู่ในเมนูแล้ว ไม่สามารถแก้ไขตัวเลือกได้")
            APHaptic.trigger()
            return
        }
        cartItemBeingEdited = cartItem.id
        viewModel.selectedItemForCustomization = liveItem
        APHaptic.trigger()
    }

    private func editNoteForCartItemAction(_ cartItem: CartItem) {
        noteText = cartItem.notes
        itemToEditNote = cartItem.id
        showNoteAlert = true
        APHaptic.trigger()
    }

    private var activeCashierDisplayName: String {
        let staffName = sessionManager.currentStaffSession?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !staffName.isEmpty { return staffName }
        return UserDefaults.standard.string(forKey: "logged_in_name") ?? "Staff"
    }


    // MARK: - Error Handling Helper

    private func showError(_ message: String) {
        withAnimation {
            errorMessage = message
            showingErrorBanner = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            withAnimation { showingErrorBanner = false }
        }
    }

    private static let deliveryBrandImageCache: [String: UIImage] = {
        var dict: [String: UIImage] = [:]
        for brand in ExternalSalesChannel.all {
            let assetName: String = {
                switch brand {
                case "GrabFood": return "DeliveryLogoGrabFood"
                case "LINE MAN": return "DeliveryLogoLineMan"
                case "ShopeeFood": return "DeliveryLogoShopeeFood"
                case "Foodpanda": return "DeliveryLogoFoodpanda"
                case "Robinhood": return "DeliveryLogoRobinhood"
                default: return "DeliveryLogo\(brand.replacingOccurrences(of: " ", with: ""))"
                }
            }()
            if let img = UIImage(named: assetName) {
                dict[brand] = img
            }
        }
        return dict
    }()

    @ViewBuilder
    private func deliveryBrandLabel(_ brand: String) -> some View {
        if let image = Self.deliveryBrandImageCache[brand] ?? UIImage(named: deliveryBrandAssetName(for: brand)) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(minWidth: 58, maxWidth: 92, minHeight: 16, maxHeight: 18)
                .accessibilityLabel(brand)
        } else {
            Text(brand)
                .font(.system(size: 10, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private func deliveryBrandAssetName(for brand: String) -> String {
        switch brand {
        case "GrabFood": return "DeliveryLogoGrabFood"
        case "LINE MAN": return "DeliveryLogoLineMan"
        case "ShopeeFood": return "DeliveryLogoShopeeFood"
        case "Foodpanda": return "DeliveryLogoFoodpanda"
        case "Robinhood": return "DeliveryLogoRobinhood"
        default:
            return "DeliveryLogo\(brand.replacingOccurrences(of: " ", with: ""))"
        }
    }

    private var externalAppAlerts: some View {
        Color.clear
        .alert("เปิดแอปถุงเงินไม่ได้", isPresented: $showTungNgernOpenFailure) {
            Button("ลองอีกครั้ง") { openTungNgernForPayment() }
            Button("วิธีตั้งค่าคำสั่งลัด") { showTungNgernShortcutSetup = true }
            Button("เปิดเอง / ใช้อุปกรณ์อื่น") {
                activePayment = .thaiChuaThaiPlus
            }
            Button("กลับไปยังบิล", role: .cancel) {}
        } message: {
            Text("ตรวจสอบว่าติดตั้งแอปคำสั่งลัดและถุงเงินแล้ว และมีคำสั่งลัดชื่อ เปิดถุงเงิน หรือเปิดแอปเองและทำรายการให้สำเร็จก่อนกดยืนยันออกใบเสร็จ บิลนี้ยังไม่ได้บันทึกชำระเงิน")
        }
        .alert("ตั้งค่าเปิดถุงเงินครั้งแรก", isPresented: $showTungNgernShortcutSetup) {
            Button("เปิดแอปคำสั่งลัด") {
                ExternalAppLauncher.open(URL(string: "shortcuts://")!) { opened in
                    if !opened { showTungNgernOpenFailure = true }
                }
            }
            Button("ตั้งค่าแล้ว เปิดถุงเงิน") {
                tungNgernShortcutConfigured = true
                openTungNgernForPayment()
            }
            Button("ยกเลิก", role: .cancel) {}
        } message: {
            Text("ในแอปคำสั่งลัด (Shortcuts) สร้างคำสั่งลัดชื่อ เปิดถุงเงิน เพิ่มการทำงาน เปิดแอป แล้วเลือก ถุงเงิน จากนั้นกลับมากดไทยช่วยไทยและเลือก ตั้งค่าแล้ว เปิดถุงเงิน ต้องตั้งค่าเพียงครั้งเดียวต่อเครื่อง")
        }
    }

    private func openTungNgernForPayment() {
        guard !externalAppHandoff.isPending else { return }
        guard tungNgernShortcutConfigured else {
            showTungNgernShortcutSetup = true
            return
        }
        externalAppHandoff.begin()
        let launchID = UUID()
        externalAppLaunchID = launchID
        ExternalAppLauncher.open(ExternalAppLauncher.tungNgernURL) { opened in
            guard externalAppLaunchID == launchID, externalAppHandoff.isPending else { return }
            if externalAppHandoff.didOpen(opened) {
                activePayment = .thaiChuaThaiPlus
            }
            if !opened { showTungNgernOpenFailure = true }
        }
    }

    private var catalogFilterKey: String {
        "\(showFavoritesOnly)|\(viewModel.selectedCategory?.id.uuidString ?? "all")|\(searchQuery)"
    }

    private var cartQuantitiesByItemID: [String: Int] {
        viewModel.cart.reduce(into: [:]) { result, cartItem in
            result[cartItem.item.id, default: 0] += cartItem.quantity
        }
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        return ZStack {
            POSReferencePalette.background.ignoresSafeArea()

            if catalog.hasLoaded && catalog.totalAvailableItems == 0 {
                emptyState
            } else if isTableServiceMode && liveActiveSession == nil {
                tableRequiredState
            } else {
                VStack(spacing: 0) {
                    if let activeShift = activeRegisterSessions.first, isShiftStale(activeShift) {
                        staleShiftWarningBanner(activeShift)
                    }

                    HStack(spacing: 0) {
                        erasedMenuPanel
                        erasedCartPanel
                    }
                }
            }

            // MARK: - Error Banner Overlay
            VStack {
                if showingErrorBanner, let msg = errorMessage {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.white)
                        Text(msg)
                            .font(.subheadline).fontWeight(.semibold).foregroundColor(.white)
                        Spacer()
                        Button { withAnimation { showingErrorBanner = false } } label: {
                            Image(systemName: "xmark").foregroundColor(.white.opacity(0.8))
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(Color.appRose)
                    .cornerRadius(12)
                    .shadow(color: Color.appRose.opacity(0.3), radius: 8, y: 4)
                    .padding(.horizontal, 16).padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer()
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showingErrorBanner)
            .zIndex(100)

        }
        .navigationBarTitleDisplayMode(.inline)
        .disabled(externalAppHandoff.isPending)
        .overlay {
            if externalAppHandoff.isPending {
                VStack(spacing: 16) {
                    Text("รอกลับจากแอปถุงเงิน")
                        .font(.headline)
                    Text("บิลนี้ยังไม่ได้บันทึกชำระเงิน")
                        .font(.subheadline)
                    Button("กลับไปยังบิล") { externalAppHandoff.cancel() }
                }
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if externalAppHandoff.activityChanged(isActive: phase == .active) {
                activePayment = .thaiChuaThaiPlus
            }
        }
        .background(externalAppAlerts)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            posToolbarContent
        }
        .sheet(item: $viewModel.selectedItemForCustomization) { item in
            ModifierCustomizerView(item: item) { modifiers in
                if let editId = cartItemBeingEdited,
                   let idx = viewModel.cart.firstIndex(where: { $0.id == editId }) {
                    let (allowed, reason) = viewModel.checkStockBeforeAdding(item, modifiers: modifiers, quantity: viewModel.cart[idx].quantity)
                    if allowed {
                        viewModel.cart[idx] = CartItem(
                            item: item,
                            selectedModifiers: modifiers,
                            quantity: viewModel.cart[idx].quantity,
                            notes: viewModel.cart[idx].notes,
                            unitPrice: viewModel.salesChannelUnitPrice(for: item)
                        )
                        viewModel.presentStockWarningIfNeeded()
                    } else {
                        viewModel.presentAlert(reason)
                    }
                    cartItemBeingEdited = nil
                } else {
                    viewModel.addToCart(item, modifiers: modifiers)
                }
            }
        }
        .alert("Add Note", isPresented: $showNoteAlert) {
            TextField("Enter note...", text: $noteText)
            Button("Cancel", role: .cancel) {
                noteText = ""
                itemToEditNote = nil
                editingNoteForOrderedItem = nil
            }
            Button("save_btn_label".t) {
                if let itemId = itemToEditNote {
                    if let idx = viewModel.cart.firstIndex(where: { $0.id == itemId }) {
                        viewModel.cart[idx].notes = noteText
                    }
                } else if let orderedTarget = editingNoteForOrderedItem {
                    let rawItems = sessionOrdersForDisplay.flatMap { $0.items }.filter { !$0.isDeleted }
                    for item in rawItems {
                        if orderedItemIdentity(item) == orderedTarget.identity && item.status == orderedTarget.status {
                            item.notes = noteText
                            item.isSynced = false
                            item.updatedAt = Date()
                        }
                    }
                    modelContext.saveWithLogging(label: #function)
                    viewModel.syncFromSession(liveActiveSession, activeCashierName: activeCashierDisplayName)
                }
                noteText = ""
                itemToEditNote = nil
                editingNoteForOrderedItem = nil
                APHaptic.trigger()
            }
        } message: {
            Text("pos_instructions_hint".t)
        }
        .alert("Cash Drawer is Locked", isPresented: $showNoActiveShiftAlert) {
            Button("go_to_cash_drawer".t) {
                selectedTab = .cashDrawer
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("pos_shift_required_hint".t)
        }
        .alert("พิมพ์ใบตรวจรายการ", isPresented: $showPreBillPrintAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(preBillPrintMessage)
        }
        .alert("pos_out_of_stock".t, item: $viewModel.activeAlert) { _ in
            Button("OK", role: .cancel) { viewModel.activeAlert = nil }
        } message: {
            Text($0.message)
        }
        .confirmationDialog("void_reason_title".t, isPresented: $showVoidReasonDialog, titleVisibility: .visible) {
            Button("void_reason_entry_error".t) { authorizePendingVoid(reason: "entry_error") }
            Button("void_reason_customer_cancel".t) { authorizePendingVoid(reason: "customer_cancelled") }
            Button("void_reason_unavailable".t) { authorizePendingVoid(reason: "item_unavailable") }
            Button("void_reason_waste".t) { authorizePendingVoid(reason: "damaged_or_waste") }
            Button(L.Common.cancel.t, role: .cancel) {
                pendingVoidItem = nil
                pendingVoidReason = ""
            }
        }
        // Payment is a focused transactional flow. A form sheet can collapse
        // to a compact detent on iPad and clip the keypad/confirmation CTA,
        // especially after rotation. Full-screen presentation gives every
        // payment method stable safe-area dimensions in both orientations.
        .fullScreenCover(item: $activePayment) { paymentMethod in
            switch paymentMethod {
            case .cash:
                CashPaymentModalView(totalAmount: displayTotal, onPark: {
                    parkPayment(methodName: "Cash")
                }) { cashReceived in
                    await completePayment(methodName: "Cash", cashTendered: cashReceived)
                }
            case .qrCode:
                QRPaymentModalView(totalAmount: displayTotal, onPark: {
                    parkPayment(methodName: "QR PromptPay")
                }) {
                    Task {
                        await completePayment(methodName: "QR PromptPay")
                    }
                }
            case .creditCard:
                CreditCardPaymentModalView(totalAmount: displayTotal, onPark: {
                    parkPayment(methodName: "Credit Card")
                }) {
                    Task {
                        await completePayment(methodName: "Credit Card")
                    }
                }
            case .thaiChuaThaiPlus:
                ThaiChuaThaiPlusPaymentModal(totalAmount: displayTotal, onPark: {
                    parkPayment(methodName: GovernmentSupportProgram.thaiChuaThaiPlus)
                }) { reference in
                    Task {
                        await completePayment(
                            methodName: GovernmentSupportProgram.thaiChuaThaiPlus,
                            transactionReference: reference
                        )
                    }
                }
            }
        }
        .sheet(isPresented: $showCustomerPicker) {
            CustomerPickerView { customer in
                viewModel.selectedCustomer = customer
            }
        }
        .sheet(isPresented: $showDeliveryNumberModal) {
            if let brand = viewModel.deliveryBrand {
                let brandColor: Color = {
                    switch brand {
                    case "GrabFood": return Color(hex: "00B14F")
                    case "LINE MAN": return Color(hex: "00C25B")
                    case "ShopeeFood": return Color(hex: "F04D23")
                    case "Foodpanda": return Color(hex: "D6125D")
                    case "Robinhood": return Color(hex: "7E22CE")
                    default: return POSReferencePalette.accent
                    }
                }()
                DeliveryOrderNumberSheet(
                    brand: brand,
                    brandColor: brandColor,
                    brandAssetName: deliveryBrandAssetName(for: brand),
                    placeholder: platformOrderPlaceholder,
                    platformOrderNumber: $viewModel.platformOrderNumber,
                    onSetFromRaw: { viewModel.setPlatformOrderNumberFromRaw($0) },
                    onPasteFromClipboard: { viewModel.pastePlatformOrderNumberFromClipboard() }
                )
            }
        }
        .sheet(isPresented: $showHeldOrders) {
            HeldOrdersView { order in
                viewModel.recallHeldOrder(order)
            }
        }
        .sheet(isPresented: $showQuickOrderQueue) {
            QuickOrderQueueSheet(orders: quickOrderQueue) { order in
                quickOrderQueueSelection(order)
            }
        }
        .sheet(isPresented: $showPendingCheckouts) {
            PendingCheckoutsView { session in
                guard session.order != nil else { return }
                let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? "local-device"
                guard session.acquireLock(deviceId: deviceId) else {
                    showError("รายการนี้กำลังถูกใช้งานจากเครื่องอื่น")
                    return
                }
                viewModel.recallParkedCheckout(session)
                session.lifecycleState = .open
                modelContext.saveWithLogging(label: "resumeParkedCheckout")
            }
        }
        .sheet(item: $focusedNotificationOrder, onDismiss: {
            focusedOrderNumber = nil
        }) { order in
            POSNotificationOrderDetailSheet(
                order: order,
                onApprove: {
                    approveFocusedNotificationOrder(order)
                },
                onRecoverOriginalTable: {
                    guard let tableNumber = order.recoveryTableNumber else {
                        return "notif_recovery_no_table".t
                    }
                    return recoverFocusedNotificationOrder(
                        order,
                        tableNumber: tableNumber
                    )
                },
                onAssignTable: { tableNumber in
                    recoverFocusedNotificationOrder(
                        order,
                        tableNumber: tableNumber
                    )
                },
                onOpenTableLayout: {
                    focusedNotificationOrder = nil
                    focusedOrderNumber = nil
                    selectedTab = .tables
                    columnVisibility = .all
                }
            )
        }
        .fullScreenCover(isPresented: $showRefund) {
            RefundView()
        }
        .onAppear {
            openFocusedNotificationOrder()
        }
        .task(id: catalogFilterKey) {
            catalog.configure(modelContext)
            await catalog.reload(
                favoritesOnly: showFavoritesOnly,
                categoryID: viewModel.selectedCategory?.id,
                searchQuery: searchQuery
            )
        }
        .onChange(of: focusedOrderNumber) { _, _ in
            openFocusedNotificationOrder()
        }
        .onChange(of: activeSession?.id) { _, newID in
            // Selecting a real table always returns POS to Table Service.
            if newID != nil {
                quickOrderMode = false
                isQuickServiceCheckoutConfirmed = false
            }
        }
        .onChange(of: selectedTab) { _, newValue in
            guard newValue != .pos, !viewModel.cart.isEmpty else { return }
            // Sidebar navigation must not discard an in-progress checkout.
            selectedTab = .pos
            showUnsavedCartNavigationAlert = true
        }
        .alert(
            lm.currentLanguage == .thai ? "มีรายการที่ยังไม่บันทึก" : "Unsaved order",
            isPresented: $showUnsavedCartNavigationAlert
        ) {
            Button(lm.currentLanguage == .thai ? "อยู่หน้านี้ต่อ" : "Stay here", role: .cancel) {}
        } message: {
            Text(lm.currentLanguage == .thai
                ? "กรุณาบันทึก พักรายการ หรือเคลียร์ตะกร้าก่อนเปลี่ยนหน้า"
                : "Save, hold, or clear the cart before leaving POS.")
        }
        .fullScreenCover(isPresented: $showStartShiftSheet) {
            StartShiftRegisterSheet(onCancel: {
                selectedTab = isTableServiceMode ? .tables : .pos
            })
        }
        .fullScreenCover(isPresented: $showOwnerPinSetup) {
            OwnerSetupView(
                initialDisplayName: UserDefaults.standard.string(forKey: "logged_in_name") ?? "",
                showMfaSoftPrompt: false,
                onFinished: { displayName, _ in
                    if !displayName.isEmpty {
                        UserDefaults.standard.set(displayName, forKey: "logged_in_name")
                    }
                    let mid = MerchantAuthManager.shared.merchantId
                        ?? UserDefaults.standard.string(forKey: "active_merchant_id")
                        ?? ""
                    if !mid.isEmpty {
                        MerchantOnboardingGate.markCompleted(.ownerPin, for: mid)
                    }
                    showOwnerPinSetup = false
                    showStartShiftSheet = true
                }
            )
        }
        .sheet(item: $staleSessionToClose) { session in
            ForceCloseStaleShiftSheet(session: session, onComplete: {
                staleSessionToClose = nil
                presentStartShiftFlow()
            }, onCancel: {
                // Stay on current page; warning banner remains visible
            })
        }
        .sheet(isPresented: $showSplitPayment) {
            SplitPaymentView(totalAmount: displayTotal) { entries in
                completeSplitCheckout(entries: entries)
            }
        }
        // C-1: Gift Card Picker Sheet
        .sheet(isPresented: $showGiftCardPicker) {
            GiftCardPickerSheet(
                cards: activeGiftCards,
                totalAmount: displayTotal,
                onSelect: { card, amount in
                    viewModel.selectedGiftCard = card
                    viewModel.giftCardRedeemAmount = min(amount, displayTotal)
                }
            )
        }
        // Manager identity is captured separately from the employee performing the void.
        .sheet(isPresented: $showVoidPINSheet) {
            ManagerPINVerificationSheet(
                isPresented: $showVoidPINSheet,
                onSuccess: {},
                onAuthorizedManager: { manager in
                    if let item = pendingVoidItem {
                        voidOrderedItem(item, approvedBy: manager.employeeProfile?.id)
                    }
                },
                onDismiss: {
                    if !showVoidPINSheet {
                        pendingVoidItem = nil
                        pendingVoidReason = ""
                    }
                }
            )
        }
        .onAppear {
            handlePOSAppear()
        }
        .onDisappear {
            animateItems = false
        }
        .onChange(of: activeSession) { _, newSession in
            if let newSession, newSession.isDeleted {
                activeSession = nil
                viewModel.syncFromSession(nil, activeCashierName: activeCashierDisplayName)
            } else {
                viewModel.syncFromSession(newSession, activeCashierName: activeCashierDisplayName)
            }
            // Reset send-to-kitchen counter so the empty-state guard is lifted for the new session
            sentToKitchenVersion = 0
            animateItems = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.75, blendDuration: 0)) {
                    animateItems = true
                }
            }
        }
        .onChange(of: quickServiceCartFingerprint) { _, _ in
            // Any edit after confirmation requires the cashier to review the
            // final ticket again before tendering. Clearing after checkout also
            // prepares the control for the next customer.
            isQuickServiceCheckoutConfirmed = false
        }
        .onChange(of: localUseLoyaltyPoints) { _, newValue in
            if viewModel.useLoyaltyPoints != newValue {
                viewModel.useLoyaltyPoints = newValue
            }
        }
        .onChange(of: localRedeemLoyaltyPoints) { _, newValue in
            if viewModel.redeemLoyaltyPoints != newValue {
                viewModel.redeemLoyaltyPoints = newValue
            }
        }
        .onChange(of: viewModel.useLoyaltyPoints) { _, newValue in
            if localUseLoyaltyPoints != newValue {
                localUseLoyaltyPoints = newValue
            }
        }
        .onChange(of: viewModel.redeemLoyaltyPoints) { _, newValue in
            if localRedeemLoyaltyPoints != newValue {
                localRedeemLoyaltyPoints = newValue
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: APSpacing.lg) {
            ZStack {
                Circle()
                    .fill(Color.appSurface)
                    .frame(width: 100, height: 100)
                Image(systemName: "fork.knife")
                    .font(.system(size: 44))
                    .foregroundStyle(APGradient.accent)
            }
            Text("pos_no_menu_items_title".t)
                .font(.title2).fontWeight(.bold)
                .foregroundColor(.textPrimary)
            Text("pos_no_menu_items_subtitle".t)
                .font(.subheadline)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            Button {
                StoreSetupChecklist.requestFirstProductGuide()
            } label: {
                Label("first_product_start_cta".t, systemImage: "plus.circle.fill")
                    .apGradientButton()
            }
            .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func reconcileStaleActiveSession() {
        guard let session = activeSession else { return }
        if session.isDeleted || !session.isActive {
            activeSession = nil
        }
    }

    private var tableRequiredState: some View {
        VStack(spacing: APSpacing.lg) {
            ZStack {
                Circle()
                    .fill(Color.appSurface)
                    .frame(width: 100, height: 100)
                Image(systemName: "tablecells.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(APGradient.accent)
            }
            Text("pos_select_table_title".t)
                .font(.title2).fontWeight(.bold)
                .foregroundColor(.textPrimary)
            Text("pos_select_table_subtitle".t)
                .font(.subheadline)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)

            Button(action: {
                selectedTab = .tables
            }) {
                Label("go_to_table_layout".t, systemImage: "arrow.right")
                    .apGradientButton()
            }
            .frame(maxWidth: 240)

            Button {
                // Enter the same POS screen without inventing a table.
                quickOrderMode = true
                activeSession = nil
                isQuickServiceCheckoutConfirmed = false
                APHaptic.trigger()
            } label: {
                Label(
                    lm.currentLanguage == .thai ? "เปิด Quick Order" : "Open Quick Order",
                    systemImage: "takeoutbag.and.cup.and.straw.fill"
                )
            }
            .buttonStyle(.bordered)
            .tint(POSReferencePalette.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Menu Panel (Left)

    /// Keep the enormous menu/cart view types from being substituted together
    /// when SwiftUI materializes the workspace `HStack`. On older iPadOS
    /// runtimes that substitution can overflow the main-thread stack and is
    /// reported misleadingly as EXC_BAD_ACCESS at the `HStack` call site.
    private var erasedMenuPanel: AnyView {
        AnyView(menuPanel)
    }

    private var erasedCartPanel: AnyView {
        AnyView(cartPanel)
    }

    private var menuSearchBar: some View {
        POSMenuSearchBar(
            query: $searchQuery,
            placeholder: lm.currentLanguage == .thai
                ? "ค้นหาชื่อ, SKU, บาร์โค้ด..."
                : "Search name, SKU, barcode..."
        ) { rawQuery in
            let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty,
                  let matchedItem = catalog.exactMatch(query) else { return false }
            viewModel.selectItem(matchedItem)
            APSoundEffect.itemTap()
            return true
        }
    }

    private var menuPanel: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                // Category pills & Favorites
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: APSpacing.sm) {
                        Button(action: {
                            withAnimation {
                                showFavoritesOnly = false
                                viewModel.selectedCategory = nil
                            }
                        }) {
                            Text("pos_all_items".t)
                                .posCategoryChip(selected: !showFavoritesOnly && viewModel.selectedCategory == nil)
                        }

                        Button(action: {
                            withAnimation {
                                showFavoritesOnly = true
                                viewModel.selectedCategory = nil
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "star.fill")
                                    .foregroundColor(.appAmber)
                                Text("pos_favorites".t)
                            }
                            .posCategoryChip(selected: showFavoritesOnly)
                        }

                        ForEach(categories) { cat in
                            Button(action: {
                                withAnimation {
                                    viewModel.selectedCategory = cat
                                    showFavoritesOnly = false
                                }
                            }) {
                                Text(cat.name)
                                    .posCategoryChip(selected: !showFavoritesOnly && viewModel.selectedCategory?.id == cat.id)
                            }
                        }
                    }
                    .padding(.horizontal, APSpacing.md)
                    .padding(.vertical, 6)
                }
                .background(POSReferencePalette.background)
            }
            .offset(y: animateItems ? 0 : -60)
            .opacity(animateItems ? 1 : 0)

            Divider().background(Color.appDivider)

            // The product panel owns its own menu queries so cart mutations do
            // not invalidate and rebuild the complete product catalogue.
            // This decouples cart updates from menu grid re-renders and vice versa.
            POSProductPanel(
                catalog: catalog,
                animateItems: $animateItems,
                quantitiesByItemID: cartQuantitiesByItemID,
                displayPrice: { viewModel.salesChannelUnitPrice(for: $0) },
                onIncrease: { item in
                    if let cartItem = viewModel.cart.first(where: { $0.item.id == item.id }) {
                        viewModel.increaseQty(cartItem)
                    } else {
                        viewModel.selectItem(item)
                    }
                },
                onDecrease: { id in
                    if let cartItem = viewModel.cart.first(where: { $0.item.id == id }) {
                        viewModel.decreaseQty(cartItem)
                    }
                },
                onShowAll: {
                    showFavoritesOnly = false
                    viewModel.selectedCategory = nil
                }
            )
        }
        .frame(maxWidth: .infinity)
        .background(POSReferencePalette.background)
    }

    // MARK: - Cart Panel (Right)
    // Split into shallow sub-builders to avoid SwiftUI ViewBuilder stack overflow
    // (EXC_BAD_ACCESS code=2) when this panel is first materialized after an empty state.

    private var cartPanel: some View {
        POSOrderPanel(isPresented: animateItems) {
            cartPanelUpperContent
        } lowerContent: {
            cartPanelLowerContent
        }
    }

    @ViewBuilder
    private var cartPanelUpperContent: some View {
        VStack(spacing: 0) {
            cartPanelMetadataCard
            cartPanelDeliverySection
            Divider().background(Color.appDivider)
            cartPanelReadyBanner
            cartPanelItemList
        }
    }

    // MARK: - POS Navigation Toolbar

    @ToolbarContentBuilder
    private var posToolbarContent: some ToolbarContent {
        if (!catalog.hasLoaded || catalog.totalAvailableItems > 0) && (!isTableServiceMode || liveActiveSession != nil) {
            ToolbarItem(placement: .topBarLeading) {
                posLeadingToolbarItems
            }
            ToolbarItem(placement: .principal) {
                menuSearchBar
                    .frame(minWidth: 260, idealWidth: 320, maxWidth: 380)
            }
            ToolbarItem(placement: .topBarTrailing) {
                posTrailingToolbarItems
            }
        }
    }

    private var posLeadingToolbarItems: some View {
        HStack(spacing: 8) {
            // Back to tables only — main nav sidebar uses the global bottom-leading toggle.
            if isTableServiceMode {
                Button(action: {
                    activeSession = nil
                    selectedTab = .tables
                    APHaptic.trigger()
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .bold))
                        Text(lm.currentLanguage == .thai ? "โต๊ะ" : "Tables")
                            .font(.system(size: 12.5, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundColor(POSReferencePalette.accent)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(Color.appSurface)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .fixedSize()
                .layoutPriority(2)
            }

            // Refunds Button (with text and icon in matching capsule)
            Button(action: {
                if sessionManager.can(.refundCreate) {
                    showRefund = true
                }
                APHaptic.trigger()
            }) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 13, weight: .bold))
                    Text(lm.currentLanguage == .thai ? "คืนเงิน" : "Refund")
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                }
                .foregroundColor(POSReferencePalette.accent)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(Color.appSurface)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!sessionManager.can(.refundCreate))
            .opacity(sessionManager.can(.refundCreate) ? 1 : 0.45)
            .accessibilityLabel(lm.currentLanguage == .thai ? "คืนเงิน" : "Refund")
            .fixedSize()
            .layoutPriority(2)
        }
        .fixedSize()
    }

    private var posTrailingToolbarItems: some View {
        HStack(spacing: 8) {
            Button {
                showQuickOrderQueue = true
                APHaptic.trigger()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "takeoutbag.and.cup.and.straw.fill")
                    Text(lm.currentLanguage == .thai ? "คิวด่วน" : "Quick")
                    if !quickOrderQueue.isEmpty {
                        Text("\(quickOrderQueue.count)")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.appAmber.opacity(0.2))
                            .clipShape(Capsule())
                    }
                }
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(POSReferencePalette.accent)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(Color.appSurface)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(lm.currentLanguage == .thai ? "คิวออเดอร์ด่วน" : "Quick Order Queue")

            RecentOrdersReviewControl()
                .frame(width: 135)

            printerControlMenu

            if !viewModel.cart.isEmpty {
                orderHeaderIcon("tray.full", tint: POSReferencePalette.accent) {
                    viewModel.holdCurrentCart()
                }
                .keyboardShortcut("h", modifiers: [.command])

                orderHeaderIcon("trash", tint: .appRose) {
                    withAnimation { viewModel.cart.removeAll() }
                    APHaptic.trigger()
                }
                .keyboardShortcut(.delete, modifiers: [.command])
            } else {
                orderHeaderIcon("arrow.uturn.backward", tint: POSReferencePalette.accent) {
                    showHeldOrders = true
                    APHaptic.trigger()
                }

                if !parkedCheckouts.isEmpty {
                    orderHeaderIcon("creditcard.trianglebadge.exclamationmark", tint: .appAmber) {
                        showPendingCheckouts = true
                    }
                }
            }
        }
    }

    private var printerControlMenu: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                Image(systemName: "printer.fill")
                    .font(.system(size: 14, weight: .semibold))

                if printService.isAutomaticPrintingTemporarilyPaused {
                    Image(systemName: "slash")
                        .font(.system(size: 20, weight: .bold))
                }
            }
            .foregroundColor(printService.isAutomaticPrintingTemporarilyPaused ? .orange : .textPrimary)
            .frame(width: 34, height: 34)
            .background(
                printService.isAutomaticPrintingTemporarilyPaused
                    ? Color.orange.opacity(0.12)
                    : Color.appSurface
            )
            .clipShape(Circle())
            .overlay(
                Circle().stroke(
                    printService.isAutomaticPrintingTemporarilyPaused
                        ? Color.orange.opacity(0.8) : Color.appDivider.opacity(0.8),
                    lineWidth: 1
                )
            )

            if printService.isAutomaticPrintingTemporarilyPaused {
                Image(systemName: "lock.fill")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(.white)
                    .padding(2.5)
                    .background(Color.orange)
                    .clipShape(Circle())
                    .offset(x: 2, y: -2)
            }
        }
        .scaleEffect(isPrinterButtonPressed ? 0.90 : 1.0)
        .contentShape(Circle())
        .onTapGesture {
            guard !didTriggerPrinterLongPress else { return }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                printService.isAutomaticPrintingTemporarilyPaused.toggle()
            }
            APHaptic.trigger()
        }
        .onLongPressGesture(minimumDuration: 0.45, maximumDistance: 20, pressing: { isPressing in
            withAnimation(.easeInOut(duration: 0.12)) {
                isPrinterButtonPressed = isPressing
            }
            if !isPressing {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    didTriggerPrinterLongPress = false
                }
            }
        }, perform: {
            didTriggerPrinterLongPress = true
            withAnimation(.easeInOut(duration: 0.12)) {
                isPrinterButtonPressed = false
            }
            APHaptic.trigger()
            showPrinterControls = true
        })
        .accessibilityLabel(
            lm.currentLanguage == .thai ? "เมนูควบคุมเครื่องพิมพ์" : "Printer controls"
        )
        .accessibilityHint(
            lm.currentLanguage == .thai
                ? (printService.isAutomaticPrintingTemporarilyPaused
                    ? "แตะเพื่อเปิดเครื่องพิมพ์, กดค้างเพื่อเปิดเมนู"
                    : "แตะเพื่อล็อกปิดเครื่องพิมพ์, กดค้างเพื่อเปิดเมนู")
                : "Tap to toggle printer lock, hold for options"
        )
        .accessibilityAddTraits(.isButton)
        .background {
            Button("") {
                showPrinterControls = true
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .opacity(0)
            .allowsHitTesting(false)
        }
        .sheet(isPresented: $showPrinterControls) {
            POSPrinterControlSheet(
                canPrintPreBill: canPrintPreBill,
                onPrintPreBill: {
                    showPrinterControls = false
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(250))
                        verifyShiftAndExecute { printPreBill() }
                    }
                },
                onSelectReceiptCopy: {
                    showPrinterControls = false
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(250))
                        showReceiptCopyPicker = true
                    }
                }
            )
        }
        .sheet(isPresented: $showReceiptCopyPicker) {
            POSReceiptCopyPicker()
        }
    }

    private func orderHeaderIcon(
        _ systemName: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(tint)
                .frame(width: 34, height: 34)
                .background(Color.appSurface)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.appDivider.opacity(0.8), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func headerTimeString(at date: Date) -> String {
        if let startedAt = liveActiveSession?.startedAt {
            let elapsed = max(0, Int(date.timeIntervalSince(startedAt)))
            return String(format: "%02d:%02d:%02d", elapsed / 3600, (elapsed % 3600) / 60, elapsed % 60)
        } else {
            return date.formatted(date: .omitted, time: .standard)
        }
    }

    private func numericTransitionValue(from text: String) -> Double {
        Double(text.filter { $0.isNumber || $0 == "." }) ?? 0
    }

    private var compactOrderDateText: String {
        Date.now.formatted(date: .numeric, time: .omitted)
    }

    private var cartOrderTypePicker: some View {
        HStack(spacing: 3) {
            orderTypeButton(
                title: "pos_dine_in".t,
                type: isTableServiceMode ? "dine_in" : "walk_in"
            )
            orderTypeButton(title: "pos_take_out".t, type: "take_out")
            orderTypeButton(title: "pos_delivery".t, type: "delivery")
        }
        .padding(4)
        .frame(maxWidth: .infinity)
        .background(Color.appSurfaceHigh)
        .clipShape(Capsule())
    }

    private func orderTypeButton(title: String, type: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                viewModel.updateOrderType(type)
            }
        } label: {
            Text(title)
                .font(.system(size: 11.5, weight: viewModel.selectedOrderType == type ? .semibold : .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(viewModel.selectedOrderType == type ? Color.appSurface : Color.clear)
                .foregroundColor(viewModel.selectedOrderType == type ? .textPrimary : .textSecondary)
                .clipShape(Capsule())
                .shadow(color: viewModel.selectedOrderType == type ? Color.black.opacity(0.06) : .clear, radius: 3, y: 1)
        }
        .buttonStyle(.plain)
    }

    private var platformOrderPlaceholder: String {
        if let prefix = PlatformOrderNumber.prefix(for: viewModel.deliveryBrand) {
            return "\(prefix)xxx"
        }
        return "platform_order_number_placeholder".t
    }

    private func liquidGlassScrollButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: {
            action()
            APHaptic.trigger()
        }) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.55),
                                Color.white.opacity(0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.75),
                                Color.white.opacity(0.20)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )

                Image(systemName: systemName)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.textPrimary)
            }
            .frame(width: 26, height: 26)
            .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 1.5)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var cartPanelDeliverySection: some View {
        if viewModel.selectedOrderType == "delivery" {
            ScrollViewReader { proxy in
                ZStack {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(ExternalSalesChannel.all, id: \.self) { brand in
                                let isSelected = viewModel.deliveryBrand == brand
                                let brandColor: Color = {
                                    switch brand {
                                    case "GrabFood": return Color(hex: "00B14F")
                                    case "LINE MAN": return Color(hex: "00C25B")
                                    case "ShopeeFood": return Color(hex: "F04D23")
                                    case "Foodpanda": return Color(hex: "D6125D")
                                    case "Robinhood": return Color(hex: "7E22CE")
                                    default: return POSReferencePalette.accent
                                    }
                                }()

                                Button(action: {
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                                        viewModel.setDeliveryBrand(brand)
                                    }
                                    APHaptic.trigger()
                                    if viewModel.platformOrderNumber.isEmpty {
                                        showDeliveryNumberModal = true
                                    }
                                }) {
                                    deliveryBrandLabel(brand)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(isSelected ? brandColor.opacity(0.16) : Color.appSurfaceHigh)
                                        )
                                        .foregroundColor(isSelected ? brandColor : .textSecondary)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(isSelected ? brandColor : Color.appBorderSubtle, lineWidth: isSelected ? 1.8 : 1)
                                        )
                                        .shadow(color: isSelected ? brandColor.opacity(0.25) : Color.clear, radius: 4, y: 1.5)
                                        .scaleEffect(isSelected ? 1.03 : 0.98)
                                }
                                .buttonStyle(.plain)
                                .id(brand)
                                .compositingGroup()
                                .animation(.spring(response: 0.28, dampingFraction: 0.75), value: isSelected)
                            }
                        }
                        .padding(.horizontal, APSpacing.md)
                        .padding(.vertical, 8)
                    }
                    .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                    .onScrollGeometryChange(for: Bool.self) { geo in
                        geo.contentOffset.x > 4
                    } action: { _, newValue in
                        if deliveryCanScrollLeading != newValue {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                deliveryCanScrollLeading = newValue
                            }
                        }
                    }
                    .onScrollGeometryChange(for: Bool.self) { geo in
                        let maxOffset = max(0, geo.contentSize.width - geo.containerSize.width)
                        return geo.contentOffset.x < (maxOffset - 4) && maxOffset > 8
                    } action: { _, newValue in
                        if deliveryCanScrollTrailing != newValue {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                deliveryCanScrollTrailing = newValue
                            }
                        }
                    }

                    // Leading Liquid Glass Arrow Indicator
                    if deliveryCanScrollLeading {
                        HStack(spacing: 0) {
                            liquidGlassScrollButton(systemName: "chevron.left") {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                    if let first = ExternalSalesChannel.all.first {
                                        proxy.scrollTo(first, anchor: .leading)
                                    }
                                }
                            }
                            .padding(.leading, 6)

                            Spacer()
                        }
                        .background(
                            LinearGradient(
                                colors: [Color.appSurface.opacity(0.92), Color.appSurface.opacity(0)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: 44)
                            .allowsHitTesting(false),
                            alignment: .leading
                        )
                        .transition(.asymmetric(insertion: .scale(scale: 0.85).combined(with: .opacity), removal: .opacity))
                    }

                    // Trailing Liquid Glass Arrow Indicator
                    if deliveryCanScrollTrailing {
                        HStack(spacing: 0) {
                            Spacer()

                            liquidGlassScrollButton(systemName: "chevron.right") {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                    if let last = ExternalSalesChannel.all.last {
                                        proxy.scrollTo(last, anchor: .trailing)
                                    }
                                }
                            }
                            .padding(.trailing, 6)
                        }
                        .background(
                            LinearGradient(
                                colors: [Color.appSurface.opacity(0), Color.appSurface.opacity(0.92)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: 44)
                            .allowsHitTesting(false),
                            alignment: .trailing
                        )
                        .transition(.asymmetric(insertion: .scale(scale: 0.85).combined(with: .opacity), removal: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: deliveryCanScrollLeading)
                .animation(.easeInOut(duration: 0.2), value: deliveryCanScrollTrailing)
            }
            .background(Color.appSurface)

            // Platform order number — tap to open modal entry.
            Button {
                showDeliveryNumberModal = true
                APHaptic.trigger()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "number.square")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.textTertiary)

                    if viewModel.platformOrderNumber.isEmpty {
                        Text(lm.currentLanguage == .thai ? "กดเพื่อระบุเลขออเดอร์แพลตฟอร์ม" : "Tap to enter platform order #")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.textTertiary)
                    } else {
                        Text(viewModel.platformOrderNumber)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(.textPrimary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.textTertiary)
                }
                .padding(.horizontal, APSpacing.md)
                .padding(.vertical, 10)
                .background(Color.appSurfaceHigh.opacity(0.55))
            }
            .buttonStyle(.plain)

            Divider().background(Color.appDivider)
        }
    }

    @ViewBuilder
    private var cartPanelMetadataCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .center, spacing: 10) {
                Text(viewModel.currentBillNumber)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .layoutPriority(1)
                    .posRollingNumber(value: numericTransitionValue(from: viewModel.currentBillNumber))

                if !viewModel.currentQueueNumber.isEmpty {
                    HStack(spacing: 4) {
                        Text(lm.currentLanguage == .thai ? "คิวที่" : "Queue")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color(hex: "4B5563"))

                        Text(viewModel.currentQueueNumber.replacingOccurrences(of: "#", with: ""))
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.textPrimary)
                            .posRollingNumber(value: numericTransitionValue(from: viewModel.currentQueueNumber))
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                }

                Spacer()

                Button {
                    showPromotionPicker = true
                    APHaptic.trigger()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "tag.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text(promotionHeaderLabel)
                            .font(.system(size: 11.5, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundColor(viewModel.activePromotion == nil ? .textSecondary : Color(hex: "0F766E"))
                    .padding(.horizontal, 11)
                    .frame(height: 32)
                    .background(
                        (viewModel.activePromotion == nil ? Color.appSurfaceHigh : Color(hex: "0F766E").opacity(0.09))
                    )
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(
                            viewModel.activePromotion == nil ? Color.appBorderSubtle : Color(hex: "0F766E").opacity(0.45),
                            lineWidth: 1
                        )
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(lm.currentLanguage == .thai ? "เลือกโปรโมชั่น" : "Select promotion")
                .sheet(isPresented: $showPromotionPicker) {
                    POSPromotionPickerSheet(viewModel: viewModel)
                }
            }

            HStack(spacing: 8) {
                Label(viewModel.cashierName, systemImage: "person.crop.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)

                Label(compactOrderDateText, systemImage: "calendar")
                    .frame(maxWidth: .infinity, alignment: .center)

                TimelineView(.periodic(from: .now, by: 1.0)) { context in
                    Label(headerTimeString(at: context.date), systemImage: "clock")
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .font(.system(size: 10.5, weight: .regular))
            .foregroundColor(.textSecondary)
            .labelStyle(.titleAndIcon)

            cartOrderTypePicker

            HStack(spacing: 10) {
                if isTableServiceMode, let session = liveActiveSession {
                    Button {
                        activeSession = nil
                        selectedTab = .tables
                    } label: {
                        Label(
                            LocalizationManager.shared.t("table_number_template", session.table?.tableNumber ?? "N/A"),
                            systemImage: "tablecells"
                        )
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 4) {
                    Button {
                        if viewModel.guestCount > 1 {
                            viewModel.updateGuestCount(viewModel.guestCount - 1, session: liveActiveSession)
                        }
                    } label: {
                        Image(systemName: "minus.circle")
                    }

                    Text(LocalizationManager.shared.t("pax_count_template", viewModel.guestCount))
                        .posRollingNumber(value: Double(viewModel.guestCount))

                    Button {
                        viewModel.updateGuestCount(viewModel.guestCount + 1, session: liveActiveSession)
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                }

                Spacer(minLength: 4)
                cartPanelCustomerRow
            }
            .font(.system(size: 9.5, weight: .medium))
            .foregroundColor(.textSecondary)

            if let customer = viewModel.selectedCustomer, customer.loyaltyPoints > 0 {
                VStack(alignment: .leading, spacing: 5) {
                    Toggle(isOn: $localUseLoyaltyPoints) {
                        Label("ใช้คะแนนสะสม", systemImage: "star.fill")
                            .font(.system(size: 9.5, weight: .semibold))
                    }
                    .toggleStyle(SwitchToggleStyle(tint: .orange))

                    if localUseLoyaltyPoints {
                        Stepper(value: $localRedeemLoyaltyPoints, in: 10...customer.loyaltyPoints, step: 10) {
                            Text("\(localRedeemLoyaltyPoints) คะแนน (-฿\(String(format: "%.2f", viewModel.loyaltyPointsDiscount)))")
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundColor(.orange)
                        }
                    }
                }
                .padding(7)
                .background(Color.orange.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(.horizontal, APSpacing.md)
        .padding(.bottom, 10)
        .background(Color.appSurface)
    }

    private var promotionHeaderLabel: String {
        guard let promotion = viewModel.activePromotion else {
            return lm.currentLanguage == .thai ? "โปรโมชั่น" : "Promotion"
        }
        let amount = viewModel.cartDiscount
        if amount > 0 {
            return "-฿\(amount.formatted(.number.precision(.fractionLength(0...0))))"
        }
        return promotion.title
    }

    @ViewBuilder
    private var cartPanelCustomerRow: some View {
        HStack {
            if let customer = viewModel.selectedCustomer {
                HStack(spacing: 6) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(POSReferencePalette.accent)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(customer.name)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.textPrimary)
                        Text(LocalizationManager.shared.t("customer_membership_points_template", customer.membershipTier.uppercased(), customer.loyaltyPoints))
                            .font(.system(size: 9))
                            .foregroundColor(.textSecondary)
                    }
                }
                Spacer()
                Button(action: {
                    viewModel.selectedCustomer = nil
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.textSecondary)
                }
            } else {
                Button(action: {
                    showCustomerPicker = true
                    APHaptic.trigger()
                }) {
                    Label("add_customer_btn".t, systemImage: "person.badge.plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(POSReferencePalette.accent)
                }
                Spacer()
            }
        }
    }

    @ViewBuilder
    private var cartPanelReadyBanner: some View {
        if isAllServed && viewModel.cart.isEmpty {
            HStack(spacing: APSpacing.xs) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.appTeal)
                Text("pos_ready_for_payment".t)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.appTeal)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.appTeal.opacity(0.12))
            .cornerRadius(APRadius.sm)
            .padding(.horizontal, APSpacing.md)
            .padding(.top, APSpacing.sm)
        }
    }

    @ViewBuilder
    private var cartPanelItemList: some View {
        let _ = sentToKitchenVersion
        if viewModel.cart.isEmpty && !hasSessionOrderedItems && sentToKitchenVersion == 0 {
            VStack(spacing: APSpacing.md) {
                Image(systemName: "cart.badge.questionmark")
                    .font(.system(size: 40))
                    .foregroundColor(.textTertiary)
                Text("pos_cart_empty".t)
                    .font(.subheadline)
                    .foregroundColor(.textSecondary)
            }
            .frame(maxHeight: .infinity)
            .frame(maxWidth: .infinity)
            .background(Color.appSurface)
        } else {
            ScrollViewReader { scrollViewProxy in
                List {
                    if hasPendingSelfOrders {
                        Section {
                            Button {
                                approvePendingSelfOrders()
                            } label: {
                                HStack {
                                    Image(systemName: "bell.badge.fill")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                        .symbolEffect(.bounce, options: .repeating)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("มีออเดอร์ใหม่จากลูกค้า")
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundColor(.white)
                                        Text("แตะเพื่อส่งออเดอร์นี้เข้าห้องครัว")
                                            .font(.system(size: 10))
                                            .foregroundColor(.white.opacity(0.85))
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.right.circle.fill")
                                        .font(.title3)
                                        .foregroundColor(.white)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(
                                    LinearGradient(
                                        colors: [Color.orange, Color.red.opacity(0.85)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(APRadius.md)
                            }
                            .buttonStyle(.plain)
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }

                    let orderedItems = groupedOrderedItems
                    if !orderedItems.isEmpty {
                        ForEach(orderedItems) { orderedItem in
                            POSOrderRow(
                                groupedItem: orderedItem,
                                showsKitchenStatus: isTableServiceMode
                            )
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 1, leading: 16, bottom: 1, trailing: 16))
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        beginVoid(orderedItem)
                                    } label: {
                                        Label("delete_btn_label".t, systemImage: "trash")
                                    }
                                    .tint(.red)

                                    Button {
                                        editNoteForOrderedItemAction(orderedItem)
                                    } label: {
                                        Label("note_btn_label".t, systemImage: "square.and.pencil")
                                    }
                                    .tint(.orange)
                                }
                        }
                    }

                    if !viewModel.cart.isEmpty {
                        ForEach(viewModel.cart) { cartItem in
                            CartItemRow(cartItem: cartItem)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 1, leading: 16, bottom: 1, trailing: 16))
                                .id(cartItem.id)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal: .opacity
                                ))
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        deleteCartItem(cartItem)
                                    } label: {
                                        Label("delete_btn_label".t, systemImage: "trash")
                                    }
                                    .tint(.red)

                                    Button {
                                        editCartItem(cartItem)
                                    } label: {
                                        Label("edit_btn_label".t, systemImage: "pencil")
                                    }
                                    .tint(.blue)

                                    Button {
                                        editNoteForCartItemAction(cartItem)
                                    } label: {
                                        Label("note_btn_label".t, systemImage: "square.and.pencil")
                                    }
                                    .tint(.orange)
                                }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color.appSurface)
                .onChange(of: viewModel.lastAddedItem) { _, target in
                    if let target = target {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                            scrollViewProxy.scrollTo(target.itemId, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var cartPanelLowerContent: some View {
        VStack(spacing: 0) {
            cartPanelFinanceBreakdown
            cartPanelCheckoutActions
        }
    }

    @ViewBuilder
    private var cartPanelFinanceBreakdown: some View {
        let financials = currentDisplayFinancials
        let qty = displayedItemQuantity
        VStack(spacing: 7) {
            HStack {
                Text(lm.currentLanguage == .thai ? "จำนวนทั้งหมด" : "Total Quantity")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.textPrimary)
                Spacer()
                Text("\(qty)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textPrimary)
                    .posRollingNumber(value: Double(qty))
            }
            financeRow(label: "pos_subtotal".t, value: financials.subtotal)
            if taxEnabledForCurrentOrderType || abs(financials.tax) > 0.005 {
                financeRow(
                    label: "pos_vat".t + " \(formattedPercent(storeTaxRate))%",
                    value: financials.tax
                )
            }
            if serviceChargeEnabledForCurrentOrderType || abs(financials.serviceCharge) > 0.005 {
                financeRow(
                    label: "pos_service_charge".t + " \(formattedPercent(storeServiceChargeRate))%",
                    value: financials.serviceCharge
                )
            }
            if financials.discount > 0 {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            if viewModel.isCouponDiscountActive {
                                Image(systemName: "ticket.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(.appTeal)
                            }
                            Text(viewModel.isCouponDiscountActive ? "coupon_code_lbl".t : "pos_discount".t)
                                .font(.system(size: 11)).foregroundColor(.textSecondary)
                        }
                        if let title = appliedPromotionTitle {
                            Text(title)
                                .font(.system(size: 9)).foregroundColor(.appTeal)
                        }
                    }
                    Spacer()
                    Text(String(format: "-฿%.2f", financials.discount))
                        .font(.system(size: 11, weight: .bold)).foregroundColor(.appRose)
                        .posRollingNumber(value: financials.discount)
                    if viewModel.isCouponDiscountActive {
                        Button {
                            viewModel.clearAppliedCoupon()
                            couponInput = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.textTertiary)
                                .font(.system(size: 13))
                        }
                    }
                }
            }

            if viewModel.useLoyaltyPoints && viewModel.loyaltyPointsDiscount > 0 {
                HStack {
                    HStack(spacing: 5) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "F59E0B"))
                        Text("แลกคะแนน (\(viewModel.redeemLoyaltyPoints) คะแนน)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color(hex: "F59E0B"))
                    }
                    Spacer()
                    Text(String(format: "-฿%.2f", viewModel.loyaltyPointsDiscount))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(hex: "F59E0B"))
                        .posRollingNumber(value: viewModel.loyaltyPointsDiscount)
                    Button { viewModel.useLoyaltyPoints = false; viewModel.redeemLoyaltyPoints = 0 } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.textTertiary)
                            .font(.system(size: 13))
                    }
                }
            }

            if viewModel.giftCardRedeemAmount > 0, let gc = viewModel.selectedGiftCard {
                HStack {
                    HStack(spacing: 5) {
                        Image(systemName: "giftcard.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.appTeal)
                        Text("\("pos_gift_card".t) ···\(gc.cardNumber.suffix(4))")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.appTeal)
                    }
                    Spacer()
                    Text(String(format: "-฿%.2f", viewModel.giftCardRedeemAmount))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.appTeal)
                        .posRollingNumber(value: viewModel.giftCardRedeemAmount)
                    Button { viewModel.selectedGiftCard = nil; viewModel.giftCardRedeemAmount = 0 } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.textTertiary)
                            .font(.system(size: 13))
                    }
                }
            }

            HStack {
                Text("pos_total".t)
                    .font(.subheadline).fontWeight(.bold)
                    .foregroundColor(.textPrimary)
                Spacer()
                Text(String(format: "฿%.2f", financials.total))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.textPrimary)
                    .posRollingNumber(value: financials.total)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, APSpacing.md)
        .padding(.vertical, 12)
        .background(Color.appSurface)
        .overlay(Rectangle().fill(Color.appDivider).frame(height: 1), alignment: .top)
    }

    private func formattedPercent(_ value: Double) -> String {
        value.rounded() == value
            ? String(format: "%.0f", value)
            : String(format: "%.2f", value)
                .replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
                .replacingOccurrences(of: "\\.$", with: "", options: .regularExpression)
    }

    private var taxEnabledForCurrentOrderType: Bool {
        guard enableTax else { return false }
        switch viewModel.selectedOrderType {
        case "take_out": return taxApplyTakeOut
        case "delivery": return taxApplyDelivery
        default: return taxApplyDineIn
        }
    }

    private var serviceChargeEnabledForCurrentOrderType: Bool {
        guard enableServiceCharge else { return false }
        switch viewModel.selectedOrderType {
        case "take_out": return serviceChargeApplyTakeOut
        case "delivery": return serviceChargeApplyDelivery
        default: return serviceChargeApplyDineIn
        }
    }

    @ViewBuilder
    private var cartPanelCheckoutActions: some View {
        if shouldShowPaymentActions {
            POSCheckoutBar {
                VStack(alignment: .leading, spacing: 6) {
                    if viewModel.selectedOrderType == "delivery" {
                        deliveryPlatformPaymentButton
                    } else if !isTableServiceMode && !isQuickServiceCheckoutConfirmed {
                        quickServiceIssueQueueButton
                    } else {
                        if !isTableServiceMode {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundColor(.appTeal)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(lm.currentLanguage == .thai ? "ยืนยันออร์เดอร์แล้ว" : "Order confirmed")
                                        .font(.system(size: 11.5, weight: .semibold))
                                    Text(lm.currentLanguage == .thai
                                         ? "เลือกวิธีชำระ · ระบบจะออกคิวและส่งครัวเมื่อรับชำระสำเร็จ"
                                         : "Select payment · queue and kitchen ticket follow successful payment")
                                        .font(.system(size: 9.5))
                                        .foregroundColor(.textSecondary)
                                }
                                Spacer()
                                Button(lm.currentLanguage == .thai ? "แก้ไข" : "Edit") {
                                    isQuickServiceCheckoutConfirmed = false
                                }
                                .font(.system(size: 10, weight: .semibold))
                                .buttonStyle(.plain)
                                .foregroundColor(POSReferencePalette.accent)
                            }
                            .padding(9)
                            .background(Color.appTeal.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }

                        Text(lm.currentLanguage == .thai ? "เลือกช่องทางชำระเงิน" : "Select Payment Method")
                            .font(.system(.footnote, design: .default, weight: .semibold))
                            .foregroundColor(.textSecondary)

                        LazyVGrid(
                            columns: Array(
                                repeating: GridItem(.flexible(minimum: 0), spacing: 6),
                                count: paymentGridColumnCount
                            ),
                            spacing: 6
                        ) {
                            if cashEnabled {
                                paymentTile(
                                    title: "pos_cash".t, icon: "banknote",
                                    tint: POSReferencePalette.accent, shortcut: "1"
                                ) { verifyShiftAndExecute { activePayment = .cash } }
                            }
                            if cardEnabled {
                                paymentTile(
                                    title: "pos_card".t, icon: "creditcard",
                                    tint: POSReferencePalette.accent, shortcut: "3"
                                ) { verifyShiftAndExecute { activePayment = .creditCard } }
                            }
                            if qrEnabled {
                                paymentTile(
                                    title: lm.currentLanguage == .thai ? "สแกน" : "Scan",
                                    icon: "qrcode", tint: POSReferencePalette.accent, shortcut: "2"
                                ) { verifyShiftAndExecute { activePayment = .qrCode } }
                            }
                            if thaiChuaThaiPlusEnabled {
                                paymentTile(
                                    title: GovernmentSupportProgram.thaiChuaThaiPlus,
                                    icon: "qrcode.viewfinder", tint: Color(hex: "1D4ED8")
                                ) {
                                    verifyShiftAndExecute {
                                        viewModel.activateThaiChuaThaiPlus()
                                        openTungNgernForPayment()
                                    }
                                }
                                .contextMenu {
                                    Button("ตั้งค่าการเปิดถุงเงิน", systemImage: "gearshape") {
                                        showTungNgernShortcutSetup = true
                                    }
                                }
                            }
                            if !activeGiftCards.isEmpty {
                                paymentTile(
                                    title: "pos_gift_card".t,
                                    icon: viewModel.selectedGiftCard == nil ? "giftcard" : "giftcard.fill",
                                    tint: .appTeal, isActive: viewModel.selectedGiftCard != nil
                                ) { verifyShiftAndExecute { showGiftCardPicker = true } }
                            }
                            paymentTile(
                                title: "pos_split_pay".t, icon: "square.split.2x2",
                                tint: POSReferencePalette.accent
                            ) { verifyShiftAndExecute { showSplitPayment = true } }
                        }
                        .onGeometryChange(for: Int.self) { geometry in
                            // Standard iPad Order Detail widths fit three compact
                            // controls. Two columns are reserved for very narrow
                            // split-view windows only.
                            geometry.size.width >= 360 ? 3 : 2
                        } action: { _, newColumnCount in
                            if paymentGridColumnCount != newColumnCount {
                                paymentGridColumnCount = newColumnCount
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.appSurface)
            }
        } else if !viewModel.cart.isEmpty {
            POSCheckoutBar {
                Button(action: {
                    verifyShiftAndExecute {
                        if isTableServiceMode {
                            let order = viewModel.processCheckout(tableSession: liveActiveSession)
                            if liveActiveSession != nil { sentToKitchenVersion += 1 }
                            _ = order
                        } else {
                            Task { @MainActor in
                                await viewModel.allocateCounterServiceIdentifiersIfNeeded(includeReceipt: false)
                                _ = viewModel.processCheckout(tableSession: nil)
                            }
                        }
                    }
                }) {
                    let btnLabel = lm.currentLanguage == .thai
                        ? "ส่งครัว • \(displayedItemQuantity) รายการ • ฿\(String(format: "%.2f", viewModel.cartTotal))"
                        : "Send to Kitchen • \(displayedItemQuantity) items • ฿\(String(format: "%.2f", viewModel.cartTotal))"
                    Label(btnLabel, systemImage: "flame.fill")
                        .apGradientButton(
                            gradient: APGradient.accent,
                            shadow: APShadow.glow,
                            disabled: false
                        )
                }
            }
        }
    }

    private var deliveryPlatformPaymentButton: some View {
        Button {
            verifyShiftAndExecute {
                // Delivery platforms collect from the customer externally.
                // Record one dedicated captured tender so cash/card/QR and the
                // register drawer are never affected by this order.
                Task { @MainActor in
                    _ = await completeDirectCheckout(methodName: "Delivery Platform")
                }
            }
        } label: {
            VStack(spacing: 5) {
                Label(
                    lm.currentLanguage == .thai ? "ชำระผ่านเดลิเวอรี่" : "Paid via Delivery Platform",
                    systemImage: "shippingbox.fill"
                )
                .font(.system(size: 14, weight: .bold))
                Text("\(viewModel.deliveryBrand ?? "Delivery") · \(displayedItemQuantity) \(lm.currentLanguage == .thai ? "รายการ" : "items") · ฿\(String(format: "%.2f", viewModel.cartTotal))")
                    .font(.system(size: 10, weight: .medium))
                    .opacity(0.88)
            }
            .frame(maxWidth: .infinity)
            .apGradientButton(gradient: APGradient.accent, shadow: APShadow.glow, disabled: isProcessingCheckout)
        }
        .buttonStyle(.plain)
        .disabled(isProcessingCheckout || viewModel.deliveryBrand == nil)
        .accessibilityHint(lm.currentLanguage == .thai
                           ? "ยืนยันว่ารับชำระผ่านแพลตฟอร์มและส่งออร์เดอร์"
                           : "Confirms platform payment and submits the order")
    }

    private var quickServiceIssueQueueButton: some View {
        Button {
            verifyShiftAndExecute {
                isQuickServiceCheckoutConfirmed = true
                APHaptic.trigger()
            }
        } label: {
            VStack(spacing: 5) {
                Label(
                    lm.currentLanguage == .thai ? "ยืนยันออร์เดอร์และออกคิว" : "Confirm Order & Issue Queue",
                    systemImage: "number.square.fill"
                )
                .font(.system(size: 14, weight: .bold))
                Text(lm.currentLanguage == .thai
                     ? "\(displayedItemQuantity) รายการ · ฿\(String(format: "%.2f", viewModel.cartTotal)) · รับชำระก่อนส่งครัว"
                     : "\(displayedItemQuantity) items · ฿\(String(format: "%.2f", viewModel.cartTotal)) · payment before kitchen")
                    .font(.system(size: 10, weight: .medium))
                    .opacity(0.88)
            }
            .frame(maxWidth: .infinity)
            .apGradientButton(gradient: APGradient.accent, shadow: APShadow.glow, disabled: false)
        }
        .buttonStyle(.plain)
        .accessibilityHint(lm.currentLanguage == .thai
                           ? "เปิดขั้นตอนรับชำระเงิน เลขคิวจะถูกบันทึกเมื่อชำระสำเร็จ"
                           : "Opens payment. The queue is saved after successful payment.")
    }

    private var couponEntryRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let code = viewModel.appliedCouponCode {
                HStack(spacing: 8) {
                    Image(systemName: "ticket.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: "0F766E"))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(code)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.textPrimary)
                        Text(
                            viewModel.isCouponDiscountActive
                            ? "coupon_pos_applied_short".t
                            : "coupon_pos_not_eligible".t
                        )
                        .font(.system(size: 9))
                        .foregroundColor(
                            viewModel.isCouponDiscountActive
                            ? Color(hex: "0F766E")
                            : .appRose
                        )
                    }
                    Spacer()
                    if viewModel.cartDiscount > 0 {
                        Text(String(format: "-฿%.2f", viewModel.cartDiscount))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.appRose)
                    }
                    Button {
                        viewModel.clearAppliedCoupon()
                        couponInput = ""
                        APHaptic.trigger()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "ticket")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(POSReferencePalette.accent)
                    TextField("coupon_pos_placeholder".t, text: $couponInput)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .onSubmit { applyCouponFromInput() }
                    Button(action: applyCouponFromInput) {
                        Text("coupon_pos_apply_btn".t)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                couponInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? Color.appSurfaceHigh
                                : Color(hex: "0F766E")
                            )
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .disabled(couponInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            if let message = viewModel.couponFeedbackMessage {
                Text(message)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(viewModel.couponFeedbackIsError ? .appRose : Color(hex: "0F766E"))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(8)
        .background(
            (viewModel.isCouponDiscountActive ? Color(hex: "0F766E") : POSReferencePalette.accent)
                .opacity(0.06)
        )
        .cornerRadius(8)
        .padding(.top, 2)
    }

    private func applyCouponFromInput() {
        let ok = viewModel.applyCouponCode(couponInput)
        if ok {
            couponInput = ""
        }
        APHaptic.trigger()
    }

    private func financeRow(label: String, value: Double) -> some View {
        HStack {
            Text(label)
                .font(.footnote)
                .foregroundColor(.textSecondary)
            Spacer()
            Text(String(format: "฿%.2f", value))
                .font(.footnote)
                .foregroundColor(.textPrimary)
                .posRollingNumber(value: value)
        }
    }

    private func verifyShiftAndExecute(_ action: @escaping () -> Void) {
        if activeRegisterSessions.isEmpty {
            presentStartShiftFlow()
            APHaptic.trigger()
        } else if let activeShift = activeRegisterSessions.first, isShiftStale(activeShift) {
            staleSessionToClose = activeShift
            APHaptic.trigger()
        } else {
            action()
        }
    }

    /// Phase 3: owner PIN is required before opening a register shift.
    private func presentStartShiftFlow() {
        if KeychainManager.shared.isOwnerPinConfigured() {
            showStartShiftSheet = true
        } else {
            showOwnerPinSetup = true
        }
    }

    @MainActor
    private func handlePOSAppear() {
        viewModel.modelContext = modelContext
        reconcileStaleActiveSession()
        viewModel.syncFromSession(liveActiveSession, activeCashierName: activeCashierDisplayName)
        StockAlertEvaluator.refresh(modelContext: modelContext)
        withAnimation(.spring(response: 0.6, dampingFraction: 0.75, blendDuration: 0)) {
            animateItems = true
        }

        // Prompt to start a new shift only if no active shift exists.
        if activeRegisterSessions.isEmpty {
            DispatchQueue.main.async {
                self.presentStartShiftFlow()
            }
        }
    }

    private func isShiftStale(_ session: RegisterSession) -> Bool {
        let hoursOpen = Calendar.current.dateComponents([.hour], from: session.openedAt, to: Date()).hour ?? 0
        return hoursOpen >= 24
    }

    private func staleShiftWarningBanner(_ session: RegisterSession) -> some View {
        HStack(spacing: APSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.appAmber)
                .font(.system(size: 16, weight: .bold))

            VStack(alignment: .leading, spacing: 2) {
                Text(lm.currentLanguage == .thai ? "ตรวจพบกะทำงานเก่าค้างข้ามคืน" : "Overnight Shift Detected")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.textPrimary)
                Text(lm.currentLanguage == .thai ? "กรุณาเคลียร์ยอดและปิดกะเก่าก่อนทำรายการขายถัดไป" : "Please reconcile and close the past shift before checkout.")
                    .font(.system(size: 11))
                    .foregroundColor(.textSecondary)
            }

            Spacer()

            Button {
                staleSessionToClose = session
                APHaptic.trigger()
            } label: {
                Text(lm.currentLanguage == .thai ? "เคลียร์ยอดกะเก่า" : "Reconcile")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        LinearGradient(
                            colors: [Color.appAmber, Color.appAmber.opacity(0.85)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(APRadius.sm)
                    .shadow(color: Color.appAmber.opacity(0.2), radius: 4, y: 2)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, APSpacing.md)
        .padding(.vertical, 10)
        .background(Color.appSurface)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.appBorderSubtle),
            alignment: .bottom
        )
    }

    // MARK: - Native Liquid Glass Payment Option Tile
    @ViewBuilder
    private func paymentTile(
        title: String,
        icon: String,
        tint: Color,
        isActive: Bool = false,
        shortcut: Character? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let tile = Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 17)
                Text(title)
                    .font(.system(.caption, design: .default, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .minimumScaleFactor(0.82)
            }
            .frame(maxWidth: .infinity, minHeight: 32)
            .padding(.horizontal, 2)
        }
        .controlSize(.small)
        .apGlassButton(prominent: isActive, tint: isActive ? tint : nil)
        .frame(minHeight: 44)
        .accessibilityLabel(title)

        if let shortcut {
            tile.keyboardShortcut(KeyEquivalent(shortcut), modifiers: [.command])
        } else {
            tile
        }
    }

    private func openFocusedNotificationOrder() {
        guard let orderNumber = focusedOrderNumber, !orderNumber.isEmpty else { return }
        var descriptor = FetchDescriptor<Order>(
            predicate: #Predicate<Order> {
                $0.orderNumber == orderNumber && !$0.isDeleted
            }
        )
        descriptor.fetchLimit = 1
        focusedNotificationOrder = try? modelContext.fetch(descriptor).first
    }

    private func quickOrderQueueSelection(_ order: Order) {
        // Selecting a queue item opens its detail without replacing the
        // current table cart/session. The existing cart remains untouched.
        focusedOrderNumber = order.orderNumber
        showQuickOrderQueue = false
    }

    private func approveFocusedNotificationOrder(_ order: Order) {
        guard order.isAwaitingStaffApproval,
              !order.requiresTableSessionRecovery else { return }
        if order.status.lowercased() == "pending" {
            order.status = "preparing"
        }
        order.isStaffConfirmed = true
        order.isSynced = false
        order.updatedAt = Date()
        for item in order.items where !item.isDeleted && item.status.lowercased() == "pending" {
            item.status = "cooking"
            item.isSynced = false
            item.updatedAt = Date()
        }
        order.tableSession?.isSynced = false
        order.tableSession?.updatedAt = Date()
        modelContext.saveWithLogging(label: #function)
        SyncEngine.shared.refreshLiveOperationalAlerts(modelContext: modelContext)

        Task {
            try? await NetworkManager.shared.approveCustomerOrder(orderId: order.id)
            let isThisDeviceStation = UserDefaults.standard.object(
                forKey: "remote_kitchen_print_enabled"
            ) as? Bool ?? true
            if PrintRoutingGate.approvingDeviceShouldPrint(
                isThisDeviceStation: isThisDeviceStation
            ) {
                #if !targetEnvironment(simulator)
                await PrintService.shared.dispatchKitchenOrder(order)
                #endif
            }
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }

    /// Reattach an order whose original table session was closed or removed.
    /// Recovery never merges into an occupied table automatically.
    private func recoverFocusedNotificationOrder(
        _ order: Order,
        tableNumber: String
    ) -> String? {
        guard order.requiresTableSessionRecovery, !tableNumber.isEmpty else {
            return "notif_recovery_no_table".t
        }

        var descriptor = FetchDescriptor<RestaurantTable>(
            predicate: #Predicate<RestaurantTable> {
                $0.tableNumber == tableNumber && !$0.isDeleted
            }
        )
        descriptor.fetchLimit = 1
        guard let table = try? modelContext.fetch(descriptor).first else {
            return LocalizationManager.shared.t(
                "notif_recovery_table_missing",
                tableNumber
            )
        }

        if table.sessions.contains(where: { $0.isActive && !$0.isDeleted }) {
            return LocalizationManager.shared.t(
                "notif_recovery_table_in_use",
                tableNumber
            )
        }
        guard table.status.lowercased() == "vacant" else {
            return LocalizationManager.shared.t(
                "notif_recovery_table_unavailable",
                tableNumber
            )
        }

        let newSession = TableSession(
            sessionToken: UUID().uuidString,
            startedAt: Date(),
            isActive: true,
            table: table,
            guestCount: max(order.guestCount, 1),
            cashierName: UserDefaults.standard.string(forKey: "logged_in_name") ?? "Staff"
        )
        modelContext.insert(newSession)
        table.sessions.append(newSession)
        newSession.orders.append(order)
        order.tableSession = newSession
        order.floorTableNumber = tableNumber
        order.isSynced = false
        order.updatedAt = Date()
        table.status = "occupied"
        table.isSynced = false
        table.updatedAt = Date()
        modelContext.saveWithLogging(label: #function)

        activeSession = newSession
        SyncEngine.shared.refreshLiveOperationalAlerts(modelContext: modelContext)
        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
        return nil
    }
}

// MARK: - POS Promotion Picker

private struct POSPromotionPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var lm: LocalizationManager
    @Query(
        filter: #Predicate<Promotion> { !$0.isDeleted },
        sort: \Promotion.title
    ) private var promotions: [Promotion]

    let viewModel: POSViewModel

    private var isThai: Bool { lm.currentLanguage == .thai }
    private var publicPromotions: [Promotion] { promotions.filter { $0.couponCode == nil } }
    private var eligiblePromotions: [Promotion] {
        publicPromotions.filter(viewModel.isPromotionEligible).sorted {
            viewModel.promotionDiscountAmount($0) > viewModel.promotionDiscountAmount($1)
        }
    }
    private var unavailablePromotions: [Promotion] {
        publicPromotions.filter { !viewModel.isPromotionEligible($0) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label {
                        Text(isThai
                             ? "ใช้ได้ครั้งละ 1 โปรโมชั่น ระบบคำนวณส่วนลดก่อนภาษีและค่าบริการตามการตั้งค่าร้าน และไม่ลดจำนวนสินค้าที่ต้องตัดสต็อก"
                             : "One promotion per order. Discounts are calculated before tax and service charge according to store settings and never reduce physical stock quantities.")
                            .font(.caption)
                    } icon: {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(POSReferencePalette.accent)
                    }
                }

                Section(isThai ? "วิธีเลือกโปรโมชั่น" : "Promotion selection") {
                    Button {
                        viewModel.useAutomaticPromotion()
                        dismiss()
                    } label: {
                        promotionSelectionRow(
                            title: isThai ? "เลือกให้อัตโนมัติ" : "Best promotion automatically",
                            subtitle: isThai ? "ระบบเลือกส่วนลดที่ประหยัดที่สุดซึ่งผ่านเงื่อนไข" : "Applies the highest eligible discount",
                            icon: "wand.and.stars",
                            selected: viewModel.manuallySelectedPromotion == nil &&
                                viewModel.appliedCouponCode == nil &&
                                !viewModel.suppressAutomaticPromotion
                        )
                    }
                    .buttonStyle(.plain)

                    Button(role: .destructive) {
                        viewModel.clearSelectedPromotion()
                        dismiss()
                    } label: {
                        HStack {
                            Label(isThai ? "ไม่ใช้โปรโมชั่น" : "No promotion", systemImage: "xmark.circle")
                            Spacer()
                            if viewModel.suppressAutomaticPromotion {
                                Image(systemName: "checkmark.circle.fill").foregroundColor(.appTeal)
                            }
                        }
                    }
                }

                if eligiblePromotions.isEmpty {
                    Section {
                        ContentUnavailableView(
                            isThai ? "ยังไม่มีโปรโมชั่นที่ใช้ได้" : "No eligible promotions",
                            systemImage: "tag",
                            description: Text(isThai
                                              ? "เพิ่มสินค้าให้ครบจำนวนหรือยอดขั้นต่ำ หรือสร้างโปรโมชั่นในหน้าการตลาด"
                                              : "Meet the quantity/minimum spend or create a promotion in Marketing.")
                        )
                    }
                } else {
                    Section(isThai ? "โปรโมชั่นที่ใช้ได้" : "Eligible promotions") {
                        ForEach(eligiblePromotions) { promotion in
                            Button {
                                if viewModel.selectPromotion(promotion) { dismiss() }
                            } label: {
                                promotionRow(promotion, isAvailable: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !unavailablePromotions.isEmpty {
                    Section(isThai ? "ยังไม่ผ่านเงื่อนไข" : "Not yet eligible") {
                        ForEach(unavailablePromotions) { promotion in
                            promotionRow(promotion, isAvailable: false)
                        }
                    }
                }

                Section(isThai ? "คูปอง" : "Coupons") {
                    Text(isThai
                         ? "โปรโมชั่นที่กำหนดรหัสคูปองจะไม่แสดงในรายการนี้ ต้องกรอกรหัสในช่องคูปองเพื่อป้องกันการนำไปใช้โดยไม่ได้รับอนุญาต"
                         : "Code-protected promotions are hidden here and must be redeemed through the coupon field.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(isThai ? "เลือกโปรโมชั่น" : "Select promotion")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isThai ? "ปิด" : "Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func promotionSelectionRow(
        title: String,
        subtitle: String,
        icon: String,
        selected: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(POSReferencePalette.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Color.textPrimary)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if selected { Image(systemName: "checkmark.circle.fill").foregroundColor(.appTeal) }
        }
    }

    private func promotionRow(_ promotion: Promotion, isAvailable: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: promotionIcon(promotion))
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(isAvailable ? Color(hex: "0F766E") : .textTertiary)
                .frame(width: 30, height: 30)
                .background((isAvailable ? Color(hex: "0F766E") : Color.gray).opacity(0.09))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(promotion.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isAvailable ? Color.textPrimary : Color.textSecondary)
                if promotion.isStaffDiscount {
                    Text(isThai ? "ส่วนลดพนักงาน · เลือกใช้เอง · ไม่แสดงบนเว็บ" : "Staff discount · Manual selection · Hidden from web")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(promotionRuleText(promotion))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if !isAvailable {
                    Text(unavailableReason(promotion))
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.appAmber)
                }
            }
            Spacer()
            if isAvailable {
                let amount = viewModel.promotionDiscountAmount(promotion)
                VStack(alignment: .trailing, spacing: 3) {
                    Text("-฿\(amount.formatted(.number.precision(.fractionLength(0...2))))")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.red)
                    if viewModel.manuallySelectedPromotion?.id == promotion.id {
                        Label(isThai ? "เลือกแล้ว" : "Selected", systemImage: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.appTeal)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .opacity(isAvailable ? 1 : 0.72)
    }

    private func promotionIcon(_ promotion: Promotion) -> String {
        switch promotion.discountType {
        case "percentage": return "percent"
        case "fixed", "fixed_per_item": return "banknote.fill"
        case "bundle_price": return "shippingbox.fill"
        case "buy_x_get_y", "buy_x_pay_y": return "gift.fill"
        default: return "tag.fill"
        }
    }

    private func promotionRuleText(_ promotion: Promotion) -> String {
        let rule: String
        switch promotion.discountType {
        case "percentage": rule = isThai ? "ลด \(promotion.discountValue.formatted())%" : "\(promotion.discountValue.formatted())% off"
        case "fixed": rule = isThai ? "ลด ฿\(promotion.discountValue.formatted())" : "฿\(promotion.discountValue.formatted()) off"
        case "fixed_per_item":
            rule = isThai
                ? "ลด ฿\(promotion.discountValue.formatted()) ต่อชิ้น เมื่อราคามากกว่า ฿\(promotion.minimumSpend.formatted())"
                : "฿\(promotion.discountValue.formatted()) off each unit priced above ฿\(promotion.minimumSpend.formatted())"
        case "bundle_price": rule = isThai ? "\(promotion.requiredQuantity) ชิ้น ราคา ฿\(promotion.discountValue.formatted())" : "\(promotion.requiredQuantity) for ฿\(promotion.discountValue.formatted())"
        case "buy_x_get_y": rule = isThai ? "ซื้อ \(promotion.requiredQuantity) รับฟรี \(promotion.rewardQuantity)" : "Buy \(promotion.requiredQuantity), get \(promotion.rewardQuantity)"
        case "buy_x_pay_y": rule = isThai ? "ซื้อ \(promotion.requiredQuantity) จ่าย \(promotion.rewardQuantity)" : "Buy \(promotion.requiredQuantity), pay for \(promotion.rewardQuantity)"
        default: rule = promotion.promoDescription ?? ""
        }
        guard promotion.minimumSpend > 0, promotion.discountType != "fixed_per_item" else { return rule }
        return rule + (isThai ? " · ขั้นต่ำ ฿\(promotion.minimumSpend.formatted())" : " · Min ฿\(promotion.minimumSpend.formatted())")
    }

    private func unavailableReason(_ promotion: Promotion) -> String {
        if !promotion.isEffective() { return isThai ? "หมดอายุ ปิดใช้งาน หรือครบสิทธิ์แล้ว" : "Inactive, expired, or redemption limit reached" }
        if viewModel.cartSubtotal < promotion.minimumSpend {
            return isThai ? "ยอดยังไม่ถึง ฿\(promotion.minimumSpend.formatted())" : "Requires ฿\(promotion.minimumSpend.formatted()) minimum"
        }
        return isThai ? "สินค้า/จำนวนยังไม่ครบเงื่อนไข" : "Required item or quantity is missing"
    }
}

// MARK: - Delivery Platform Order Number Modal

/// Full-screen modal for entering a delivery platform order number.
/// Presented when a delivery brand (Grab, LINE MAN, etc.) is selected.
/// Features animated brand logo, numeric-only input, confirm/skip buttons.
private struct DeliveryOrderNumberSheet: View {
    let brand: String
    let brandColor: Color
    let brandAssetName: String
    let placeholder: String
    @Binding var platformOrderNumber: String
    let onSetFromRaw: (String) -> Void
    let onPasteFromClipboard: () -> Bool

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var lm: LocalizationManager
    @State private var localInput: String = ""
    @State private var logoAppeared = false
    @State private var contentAppeared = false
    @FocusState private var isInputFocused: Bool

    private var isThai: Bool { lm.currentLanguage == .thai }

    private func cleanBody(_ value: String) -> String {
        PlatformOrderNumber.stripKnownPrefix(value)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_/ "))
    }

    private var isValid: Bool {
        let stripped = cleanBody(localInput)
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
        let digitsOnly = stripped.filter { $0.isNumber }
        return !digitsOnly.isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer().frame(height: 24)

                // Animated brand logo
                brandLogoView
                    .scaleEffect(logoAppeared ? 1.0 : 0.4)
                    .opacity(logoAppeared ? 1 : 0)
                    .animation(.spring(response: 0.5, dampingFraction: 0.65), value: logoAppeared)

                Spacer().frame(height: 20)

                Text(isThai ? "ระบุหมายเลขออเดอร์ \(brand)" : "Enter \(brand) Order #")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.textPrimary)
                    .multilineTextAlignment(.center)
                    .offset(y: contentAppeared ? 0 : 16)
                    .opacity(contentAppeared ? 1 : 0)
                    .animation(.easeOut(duration: 0.35).delay(0.15), value: contentAppeared)

                Text(isThai ? "กรอกตัวเลขเท่านั้น" : "Numeric digits only")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.textSecondary)
                    .padding(.top, 4)
                    .offset(y: contentAppeared ? 0 : 12)
                    .opacity(contentAppeared ? 1 : 0)
                    .animation(.easeOut(duration: 0.35).delay(0.25), value: contentAppeared)

                Spacer().frame(height: 28)

                // Input field
                inputField
                    .offset(y: contentAppeared ? 0 : 20)
                    .opacity(contentAppeared ? 1 : 0)
                    .animation(.easeOut(duration: 0.4).delay(0.3), value: contentAppeared)

                Spacer().frame(height: 12)

                // Paste from clipboard
                Button {
                    if onPasteFromClipboard() {
                        localInput = cleanBody(platformOrderNumber)
                        APHaptic.trigger()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 12, weight: .semibold))
                        Text(isThai ? "วางจากคลิปบอร์ด" : "Paste from clipboard")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(POSReferencePalette.accent)
                }
                .buttonStyle(.plain)
                .offset(y: contentAppeared ? 0 : 12)
                .opacity(contentAppeared ? 1 : 0)
                .animation(.easeOut(duration: 0.35).delay(0.4), value: contentAppeared)

                Spacer()

                // Confirm + Skip buttons
                VStack(spacing: 10) {
                    Button {
                        onSetFromRaw(cleanBody(localInput))
                        APHaptic.trigger()
                        dismiss()
                    } label: {
                        Text(isThai ? "ยืนยัน" : "Confirm")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(isValid ? brandColor : Color.gray.opacity(0.35))
                            .cornerRadius(12)
                    }
                    .disabled(!isValid)
                    .animation(.easeInOut(duration: 0.2), value: isValid)

                    Button {
                        dismiss()
                    } label: {
                        Text(isThai ? "ข้าม" : "Skip")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.textSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                    }
                }
                .padding(.bottom, 16)
            }
            .padding(.horizontal, 24)
            .background(Color.appSurface.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isThai ? "ปิด" : "Close") { dismiss() }
                }
            }
            .onAppear {
                localInput = cleanBody(platformOrderNumber)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    logoAppeared = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    contentAppeared = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                    isInputFocused = true
                }
            }
            .onChange(of: localInput) { _, newValue in
                let cleaned = cleanBody(newValue)
                if cleaned != newValue {
                    localInput = cleaned
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(false)
    }

    @ViewBuilder
    private var brandLogoView: some View {
        if let image = UIImage(named: brandAssetName) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 40)
        } else {
            Text(brand)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(brandColor)
        }
    }

    private var inputField: some View {
        HStack(spacing: 8) {
            Text(PlatformOrderNumber.prefix(for: brand) ?? "#")
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(brandColor)

            TextField(isThai ? "กรอกหมายเลข..." : "Enter number...", text: $localInput)
                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                .keyboardType(.numberPad)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .foregroundColor(.textPrimary)
                .focused($isInputFocused)

            if !localInput.isEmpty {
                Button {
                    localInput = ""
                    APHaptic.trigger()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .background(Color.appSurfaceHigh)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isInputFocused ? brandColor : Color.appBorderSubtle, lineWidth: isInputFocused ? 2 : 1)
                .animation(.easeInOut(duration: 0.2), value: isInputFocused)
        )
    }
}

// MARK: - POS Printer Controls

private struct POSPrinterControlSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var lm: LocalizationManager
    @ObservedObject private var printService = PrintService.shared

    let canPrintPreBill: Bool
    let onPrintPreBill: () -> Void
    let onSelectReceiptCopy: () -> Void

    private var isThai: Bool { lm.currentLanguage == .thai }

    var body: some View {
        NavigationStack {
            List {
                Section(isThai ? "การพิมพ์อัตโนมัติชั่วคราว" : "Temporary automatic printing") {
                    Button {
                        printService.isAutomaticPrintingTemporarilyPaused.toggle()
                        APHaptic.trigger()
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(printService.isAutomaticPrintingTemporarilyPaused
                                     ? (isThai ? "เปิดการพิมพ์อัตโนมัติ" : "Resume automatic printing")
                                     : (isThai ? "หยุดการพิมพ์อัตโนมัติชั่วคราว" : "Pause automatic printing"))
                                    .foregroundStyle(Color.textPrimary)
                                Text(isThai
                                     ? "ควบคุมใบเสร็จ ใบครัว ใบบาร์ และสติกเกอร์"
                                     : "Controls receipts, kitchen, bar, and labels")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: printService.isAutomaticPrintingTemporarilyPaused ? "play.circle.fill" : "pause.circle.fill")
                                .foregroundColor(printService.isAutomaticPrintingTemporarilyPaused ? .green : .orange)
                        }
                    }
                }

                if printService.isAutomaticPrintingTemporarilyPaused {
                    Section {
                        Label(
                            isThai
                                ? "หยุดการพิมพ์อัตโนมัติแล้ว ระบบจะเปิดกลับตามปกติเมื่อเปิดแอปใหม่"
                                : "Automatic printing is paused and will resume when the app is reopened.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.caption)
                        .foregroundColor(.appAmber)
                    }
                }

                Section(isThai ? "พิมพ์เอกสาร" : "Print documents") {
                    Button(action: onPrintPreBill) {
                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(isThai ? "พิมพ์ใบตรวจรายการและ QR ชำระเงิน" : "Print pre-bill with payment QR")
                                Text(isThai ? "สำหรับตรวจรายการและเรียกเก็บเงินก่อนชำระ" : "Customer check before payment")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "doc.text.viewfinder")
                        }
                    }
                    .disabled(!canPrintPreBill)

                    Button(action: onSelectReceiptCopy) {
                        Label(isThai ? "พิมพ์สำเนาใบเสร็จ" : "Print receipt copy", systemImage: "doc.on.doc")
                    }
                }
            }
            .navigationTitle(isThai ? "ควบคุมเครื่องพิมพ์" : "Printer controls")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isThai ? "ปิด" : "Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Paid-order picker used by the header printer menu. Keeping this query in a
/// separate sheet prevents the main product grid from observing sales history.
private struct POSReceiptCopyPicker: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var lm: LocalizationManager
    @AppStorage(BranchContext.storageKey) private var activeBranchId = ""
    @Query(filter: #Predicate<Order> { !$0.isDeleted }, sort: \Order.createdAt, order: .reverse)
    private var allOrders: [Order]

    @State private var searchText = ""
    @State private var printingOrderID: UUID?
    @State private var resultMessage: String?

    private var isThai: Bool { lm.currentLanguage == .thai }

    private var paidOrders: [Order] {
        let branchID = UUID(uuidString: activeBranchId)
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return Array(allOrders.lazy.filter { order in
            guard order.isSettled, order.status != "cancelled" else { return false }
            if let branchID, order.branch.id != branchID { return false }
            guard !query.isEmpty else { return true }
            let items = order.items.filter { !$0.isDeleted }.map(\.itemName).joined(separator: " ")
            return [order.orderNumber, order.queueNumber ?? "", items]
                .joined(separator: " ").lowercased().contains(query)
        }.prefix(50))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(
                        isThai
                            ? "เลือกออร์เดอร์ที่ชำระแล้วเพื่อพิมพ์สำเนา การพิมพ์ด้วยตนเองยังใช้ได้ระหว่างหยุดพิมพ์อัตโนมัติ"
                            : "Select a paid order to print a copy. Manual printing remains available while automatic printing is paused.",
                        systemImage: "info.circle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if paidOrders.isEmpty {
                    ContentUnavailableView(
                        isThai ? "ไม่พบออร์เดอร์ที่ชำระแล้ว" : "No paid orders found",
                        systemImage: "receipt",
                        description: Text(isThai ? "ค้นหาด้วยเลขออร์เดอร์ เลขคิว หรือชื่อสินค้า" : "Search by order, queue, or item name.")
                    )
                } else {
                    Section(isThai ? "ออร์เดอร์ที่ชำระแล้วล่าสุด" : "Recent paid orders") {
                        ForEach(paidOrders) { order in
                            Button { printCopy(of: order) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "receipt.fill")
                                        .foregroundColor(POSReferencePalette.accent)
                                        .frame(width: 30)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(order.orderNumber)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(Color.textPrimary)
                                        Text(order.items.filter { !$0.isDeleted }.map(\.itemName).filter { !$0.isEmpty }.prefix(3).joined(separator: ", "))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                        Text(order.createdAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if printingOrderID == order.id {
                                        ProgressView()
                                    } else {
                                        VStack(alignment: .trailing, spacing: 3) {
                                            Text(order.total, format: .currency(code: "THB"))
                                                .font(.subheadline.weight(.semibold))
                                            Label(isThai ? "พิมพ์สำเนา" : "Print copy", systemImage: "printer.fill")
                                                .font(.caption2.weight(.semibold))
                                                .foregroundColor(POSReferencePalette.accent)
                                        }
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(printingOrderID != nil)
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: isThai ? "ค้นหาเลขออร์เดอร์ คิว หรือสินค้า" : "Search order, queue, or item")
            .navigationTitle(isThai ? "พิมพ์สำเนาใบเสร็จ" : "Print receipt copy")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isThai ? "ปิด" : "Close") { dismiss() }
                }
            }
            .alert(
                isThai ? "การพิมพ์สำเนา" : "Receipt copy",
                isPresented: Binding(
                    get: { resultMessage != nil },
                    set: { if !$0 { resultMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { resultMessage = nil }
            } message: {
                Text(resultMessage ?? "")
            }
        }
    }

    private func printCopy(of order: Order) {
        guard PrintService.shared.hasActiveReceiptPrinters() else {
            resultMessage = isThai
                ? "ไม่พบเครื่องพิมพ์ใบเสร็จที่เปิดใช้งาน กรุณาตรวจสอบการตั้งค่าเครื่องพิมพ์"
                : "No active receipt printer is configured."
            return
        }
        printingOrderID = order.id
        Task {
            await PrintService.shared.dispatchReceipt(order, forcePrintReceipt: true)
            await MainActor.run {
                printingOrderID = nil
                resultMessage = isThai
                    ? "ส่งพิมพ์สำเนาใบเสร็จ \(order.orderNumber) แล้ว"
                    : "Receipt copy for \(order.orderNumber) was sent."
                APHaptic.trigger()
            }
        }
    }
}

// MARK: - Recent Order Review

/// A self-contained live query so recent-order changes do not force the large
/// POS product/cart view to observe every Order mutation directly.
private struct RecentOrdersReviewControl: View {
    @EnvironmentObject private var lm: LocalizationManager
    @AppStorage(BranchContext.storageKey) private var activeBranchId = ""
    @Query(
        filter: #Predicate<Order> { !$0.isDeleted },
        sort: \Order.createdAt,
        order: .reverse
    ) private var allOrders: [Order]
    @State private var showingRecentOrders = false

    private var branchOrders: [Order] {
        guard let branchId = UUID(uuidString: activeBranchId) else {
            return Array(allOrders.prefix(50))
        }
        return Array(allOrders.lazy.filter { $0.branch.id == branchId }.prefix(50))
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            Button {
                showingRecentOrders = true
                APHaptic.trigger()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 11, weight: .semibold))

                    if let latest = branchOrders.first {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(
                                latest.queueNumber.map {
                                    (lm.currentLanguage == .thai ? "คิว #" : "Queue #") + $0
                                } ?? (lm.currentLanguage == .thai ? "ออเดอร์ล่าสุด" : "Latest order")
                            )
                                .font(.system(size: 8.5, weight: .semibold))
                                .lineLimit(1)
                            Text("\(latest.createdAt.formatted(date: .omitted, time: .shortened)) · \(shortAge(from: latest.createdAt, to: context.date))")
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: needsPayment(latest) ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                            .font(.system(size: 11, weight: .bold))
                    } else {
                        Text(lm.currentLanguage == .thai ? "ยังไม่มีออเดอร์" : "No recent orders")
                            .font(.system(size: 9.5, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                }
                .foregroundColor(branchOrders.first.map { needsPayment($0) } == true ? .appRose : POSReferencePalette.accent)
                .padding(.horizontal, 8)
                .frame(height: 32)
                .background(Color.appSurfaceHigh)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(
                            branchOrders.first.map { needsPayment($0) } == true
                                ? Color.appRose.opacity(0.45)
                                : Color.appBorderSubtle,
                            lineWidth: 1
                        )
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(lm.currentLanguage == .thai ? "เปิดรายการออเดอร์ล่าสุด" : "Open recent orders")
        }
        .sheet(isPresented: $showingRecentOrders) {
            RecentOrdersReviewSheet(orders: branchOrders)
        }
    }

    private func shortAge(from date: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 {
            return lm.currentLanguage == .thai ? "เมื่อกี้" : "now"
        }
        if seconds < 3_600 {
            let minutes = seconds / 60
            return lm.currentLanguage == .thai ? "\(minutes) นาที" : "\(minutes)m"
        }
        let hours = seconds / 3_600
        return lm.currentLanguage == .thai ? "\(hours) ชม." : "\(hours)h"
    }

    private func needsPayment(_ order: Order) -> Bool {
        order.status != "cancelled" && !order.isSettled
    }
}

private struct RecentOrdersReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var lm: LocalizationManager
    let orders: [Order]

    @State private var selectedFilter = "all"
    @State private var searchText = ""

    private var isThai: Bool { lm.currentLanguage == .thai }

    private var visibleOrders: [Order] {
        orders.filter { order in
            let matchesFilter: Bool
            switch selectedFilter {
            case "unpaid": matchesFilter = !order.isSettled && order.status != "cancelled"
            case "paid": matchesFilter = order.isSettled && order.status != "cancelled"
            default: matchesFilter = true
            }

            let normalizedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalizedSearch.isEmpty else { return matchesFilter }
            let itemNames = order.items
                .filter { !$0.isDeleted }
                .map { $0.itemName.isEmpty ? ($0.menuItem?.localizedName ?? "") : $0.itemName }
                .joined(separator: " ")
                .lowercased()
            let searchable = [
                order.orderNumber,
                order.queueNumber ?? "",
                order.cashierName,
                itemNames
            ].joined(separator: " ").lowercased()
            return matchesFilter && searchable.contains(normalizedSearch)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label {
                        Text(isThai
                             ? "เทียบเลขคิว รายการสินค้า และเวลาของลูกค้ากับรายการบนสุด หากไม่พบรายการที่ตรงกัน ออเดอร์อาจยังไม่ได้คีย์ ส่วนสถานะสีแดงหมายถึงยังมียอดค้างชำระ"
                             : "Compare the customer's queue, items, and time with the top entry. If nothing matches, the order may not have been entered. Red means payment is still outstanding.")
                            .font(.caption)
                    } icon: {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.appAccent)
                    }
                }

                Section {
                    Picker(isThai ? "สถานะชำระ" : "Payment status", selection: $selectedFilter) {
                        Text(isThai ? "ทั้งหมด" : "All").tag("all")
                        Text(isThai ? "ยังไม่ชำระ" : "Unpaid").tag("unpaid")
                        Text(isThai ? "ชำระแล้ว" : "Paid").tag("paid")
                    }
                    .pickerStyle(.segmented)
                }

                if visibleOrders.isEmpty {
                    ContentUnavailableView(
                        isThai ? "ไม่พบออเดอร์ที่ตรงกัน" : "No matching orders",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text(isThai ? "ตรวจสอบคำค้นหรือเริ่มคีย์ออเดอร์ใหม่" : "Check the search or start a new order.")
                    )
                } else {
                    Section(isThai ? "ล่าสุด \(visibleOrders.count) รายการ" : "Latest \(visibleOrders.count) orders") {
                        ForEach(visibleOrders) { order in
                            NavigationLink {
                                RecentOrderReviewDetailView(order: order)
                            } label: {
                                RecentOrderReviewRow(order: order)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $searchText, prompt: isThai ? "ค้นหาเลขคิว ออเดอร์ หรือสินค้า" : "Search queue, order, or item")
            .navigationTitle(isThai ? "ตรวจสอบออเดอร์ล่าสุด" : "Recent Order Check")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(isThai ? "ปิด" : "Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .apColorScheme()
    }
}

private struct RecentOrderReviewRow: View {
    @EnvironmentObject private var lm: LocalizationManager
    let order: Order

    private var isThai: Bool { lm.currentLanguage == .thai }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(order.queueNumber.map { (isThai ? "คิว #" : "Queue #") + $0 }
                             ?? "#\(order.orderNumber.suffix(8))")
                            .font(.headline)
                        Text("\(order.createdAt.formatted(date: .abbreviated, time: .standard)) · \(ageText(to: context.date))")
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                    }
                    Spacer()
                    paymentBadge
                }

                Text(itemSummary)
                    .font(.subheadline)
                    .foregroundColor(.textPrimary)
                    .lineLimit(2)

                HStack {
                    Label(order.status.capitalized, systemImage: fulfillmentIcon)
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                    Spacer()
                    if !order.isSettled {
                        Text((isThai ? "ค้าง " : "Due ") + money(order.outstandingAmount))
                            .font(.subheadline.bold())
                            .foregroundColor(.appRose)
                    } else {
                        Text(money(order.total))
                            .font(.subheadline.bold())
                            .foregroundColor(.appTeal)
                    }
                }
            }
            .padding(.vertical, 5)
        }
    }

    @ViewBuilder
    private var paymentBadge: some View {
        let style = paymentStyle
        Text(style.title)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(style.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(style.color.opacity(0.12))
            .clipShape(Capsule())
    }

    private var paymentStyle: (title: String, color: Color) {
        if order.status == "cancelled" {
            return (isThai ? "ยกเลิก" : "CANCELLED", .textSecondary)
        }
        if order.isSettled {
            return (isThai ? "ชำระแล้ว" : "PAID", .appTeal)
        }
        if order.paidAmount > 0 {
            return (isThai ? "ชำระบางส่วน" : "PARTIAL", .appAmber)
        }
        return (isThai ? "ยังไม่ชำระ" : "UNPAID", .appRose)
    }

    private var itemSummary: String {
        let activeItems = order.items.filter { !$0.isDeleted && $0.status != "cancelled" }
        if activeItems.isEmpty { return isThai ? "ไม่มีรายละเอียดสินค้า" : "No item details" }
        return activeItems.prefix(4).map { item in
            let name = item.itemName.isEmpty ? (item.menuItem?.localizedName ?? "Item") : item.itemName
            return "\(item.quantity)× \(name)"
        }.joined(separator: " · ")
    }

    private var fulfillmentIcon: String {
        switch order.status {
        case "served", "completed": return "checkmark.circle"
        case "ready": return "bell.fill"
        case "cancelled": return "xmark.circle"
        default: return "flame"
        }
    }

    private func ageText(to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(order.createdAt)))
        if seconds < 60 { return isThai ? "เมื่อกี้" : "just now" }
        if seconds < 3_600 {
            let minutes = seconds / 60
            return isThai ? "\(minutes) นาทีที่แล้ว" : "\(minutes)m ago"
        }
        let hours = seconds / 3_600
        return isThai ? "\(hours) ชั่วโมงที่แล้ว" : "\(hours)h ago"
    }

    private func money(_ value: Double) -> String {
        String(format: "฿%.2f", value)
    }
}

private struct PaymentCorrectionRequest {
    let payment: Payment
    let newMethod: String
    let reason: String
}

private struct PaymentCorrectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var lm: LocalizationManager

    let payments: [Payment]
    let onContinue: (PaymentCorrectionRequest) -> Void

    @State private var selectedPaymentId: UUID?
    @State private var newMethod = ""
    @State private var reason = ""

    private let methods = ["Cash", "QR PromptPay", "Credit Card", "Delivery Platform"]
    private var isThai: Bool { lm.currentLanguage == .thai }
    private var selectedPayment: Payment? {
        let id = selectedPaymentId ?? payments.first?.id
        return payments.first { $0.id == id }
    }
    private var normalizedNewMethod: String {
        newMethod.lowercased().replacingOccurrences(of: " ", with: "_")
    }
    private var canContinue: Bool {
        guard let selectedPayment else { return false }
        return !newMethod.isEmpty
            && normalizedNewMethod != selectedPayment.paymentMethod
            && !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(isThai ? "รายการรับชำระเดิม" : "Original payment") {
                    Picker(isThai ? "รายการที่ต้องการแก้ไข" : "Payment to correct", selection: Binding(
                        get: { selectedPaymentId ?? payments.first?.id },
                        set: { selectedPaymentId = $0 }
                    )) {
                        ForEach(payments) { payment in
                            Text("\(displayMethod(payment.paymentMethod)) · \(money(payment.amount)) · \(payment.paidAt.formatted(date: .omitted, time: .shortened))")
                                .tag(Optional(payment.id))
                        }
                    }
                }

                Section(isThai ? "ช่องทางที่ถูกต้อง" : "Correct method") {
                    Picker(isThai ? "ช่องทางใหม่" : "New method", selection: $newMethod) {
                        Text(isThai ? "กรุณาเลือก" : "Select method").tag("")
                        ForEach(methods, id: \.self) { method in
                            Text(displayMethod(method)).tag(method)
                        }
                    }
                }

                Section(isThai ? "เหตุผลที่แก้ไข" : "Correction reason") {
                    TextField(
                        isThai ? "เช่น พนักงานเลือกเงินสดแทนบัตร" : "e.g. Cash selected instead of card",
                        text: $reason,
                        axis: .vertical
                    )
                    .lineLimit(2...4)
                }

                Section {
                    Label(
                        isThai
                            ? "ระบบจะ Void การรับชำระเดิมและสร้างรายการใหม่ ยอดขายรวมและรายการสินค้าจะไม่เปลี่ยน"
                            : "The original payment will be voided and replaced. Sales total and order items will not change.",
                        systemImage: "info.circle"
                    )
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                }
            }
            .navigationTitle(isThai ? "แก้ไขช่องทางชำระ" : "Correct Payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isThai ? "ยกเลิก" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isThai ? "ขออนุมัติ" : "Authorize") {
                        guard let selectedPayment else { return }
                        onContinue(PaymentCorrectionRequest(
                            payment: selectedPayment,
                            newMethod: newMethod,
                            reason: reason.trimmingCharacters(in: .whitespacesAndNewlines)
                        ))
                    }
                    .disabled(!canContinue)
                }
            }
        }
        .presentationDetents([.large])
    }

    private func displayMethod(_ raw: String) -> String {
        switch raw.lowercased().replacingOccurrences(of: " ", with: "_") {
        case "cash": return isThai ? "เงินสด" : "Cash"
        case "qr_promptpay": return "QR PromptPay"
        case "credit_card": return isThai ? "บัตรเครดิต" : "Credit Card"
        case "delivery_platform": return isThai ? "เดลิเวอรี่แพลตฟอร์ม" : "Delivery Platform"
        default: return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func money(_ value: Double) -> String {
        String(format: "฿%.2f", value)
    }
}

private struct RecentOrderReviewDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var lm: LocalizationManager
    let order: Order

    @State private var showingPaymentCorrection = false
    @State private var showingManagerAuthorization = false
    @State private var pendingCorrection: PaymentCorrectionRequest?
    @State private var correctionResultMessage: String?

    private var isThai: Bool { lm.currentLanguage == .thai }
    private var capturedPayments: [Payment] {
        order.payments.filter { !$0.isDeleted && $0.isCaptured }.sorted { $0.paidAt < $1.paidAt }
    }

    var body: some View {
        List {
            Section(isThai ? "อ้างอิงออเดอร์" : "Order reference") {
                LabeledContent(isThai ? "เลขออเดอร์" : "Order number", value: order.orderNumber)
                LabeledContent(isThai ? "เลขคิว" : "Queue number", value: order.queueNumber ?? "-")
                LabeledContent(isThai ? "คีย์เมื่อ" : "Entered at", value: exactTime(order.createdAt))
                LabeledContent(isThai ? "พนักงาน" : "Cashier", value: order.cashierName)
                LabeledContent(isThai ? "สถานะครัว" : "Fulfillment", value: order.status.capitalized)
            }

            Section(isThai ? "รายการสินค้า" : "Items") {
                ForEach(order.items.filter { !$0.isDeleted }) { item in
                    HStack {
                        Text("\(item.quantity)×")
                            .foregroundColor(.textSecondary)
                        Text(item.itemName.isEmpty ? (item.menuItem?.localizedName ?? "Item") : item.itemName)
                        Spacer()
                        Text(String(format: "฿%.2f", item.subtotal))
                            .foregroundColor(.textSecondary)
                    }
                }
            }

            Section(isThai ? "การชำระเงิน" : "Payment") {
                LabeledContent(isThai ? "สถานะ" : "Status", value: paymentStatusText)
                LabeledContent(isThai ? "ยอดรวม" : "Total", value: money(order.total))
                LabeledContent(isThai ? "ชำระแล้ว" : "Paid", value: money(order.paidAmount))
                LabeledContent(isThai ? "ยอดค้าง" : "Outstanding", value: money(order.outstandingAmount))

                if capturedPayments.isEmpty {
                    Label(isThai ? "ยังไม่พบรายการรับชำระ" : "No captured payment found", systemImage: "creditcard.trianglebadge.exclamationmark")
                        .foregroundColor(.red)
                } else {
                    ForEach(capturedPayments) { payment in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(payment.paymentMethod.replacingOccurrences(of: "_", with: " ").capitalized)
                                Spacer()
                                Text(money(payment.amount)).fontWeight(.semibold)
                            }
                            Text("\(isThai ? "รับชำระเมื่อ" : "Paid at") \(exactTime(payment.paidAt)) · \(paymentDelayText(payment.paidAt))")
                                .font(.caption)
                                .foregroundColor(.textSecondary)
                        }
                    }

                    if order.status != "cancelled" {
                        Button {
                            showingPaymentCorrection = true
                            APHaptic.trigger()
                        } label: {
                            Label(
                                isThai ? "แก้ไขช่องทางชำระเงิน" : "Correct payment method",
                                systemImage: "arrow.triangle.2.circlepath.circle"
                            )
                        }
                        .foregroundColor(.appAmber)
                    }
                }
            }

            Section {
                Text(isThai
                     ? "สถานะชำระอ้างอิงจาก Payment ที่บันทึกสำเร็จ ไม่ได้อ้างอิงจากคำว่า Served หรือ Completed"
                     : "Payment status comes from captured Payment records, not from Served or Completed fulfillment labels.")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            }
        }
        .navigationTitle(order.queueNumber.map { "#\($0)" } ?? "#\(order.orderNumber.suffix(8))")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingPaymentCorrection) {
            PaymentCorrectionSheet(payments: capturedPayments) { request in
                pendingCorrection = request
                showingPaymentCorrection = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    showingManagerAuthorization = true
                }
            }
        }
        .sheet(isPresented: $showingManagerAuthorization) {
            ManagerPINVerificationSheet(
                isPresented: $showingManagerAuthorization,
                onSuccess: {
                    // Store-owner PIN has no User row; it is still recorded as
                    // an owner-authorized correction in AuditLog details.
                    if pendingCorrection != nil {
                        applyPendingPaymentCorrection(approvedBy: nil)
                    }
                },
                onAuthorizedManager: { manager in
                    applyPendingPaymentCorrection(approvedBy: manager.employeeProfile?.id)
                },
                onDismiss: {
                    if !showingManagerAuthorization { pendingCorrection = nil }
                },
                requiredPermission: .managerOverride
            )
        }
        .alert(isThai ? "ผลการแก้ไขการชำระเงิน" : "Payment correction", isPresented: Binding(
            get: { correctionResultMessage != nil },
            set: { if !$0 { correctionResultMessage = nil } }
        )) {
            Button("OK", role: .cancel) { correctionResultMessage = nil }
        } message: {
            Text(correctionResultMessage ?? "")
        }
    }

    private func applyPendingPaymentCorrection(approvedBy employeeId: UUID?) {
        guard let request = pendingCorrection,
              request.payment.isCaptured,
              !request.payment.isDeleted,
              request.payment.order?.id == order.id else {
            correctionResultMessage = isThai
                ? "รายการรับชำระถูกเปลี่ยนแปลงแล้ว กรุณาเปิดใหม่และตรวจสอบอีกครั้ง"
                : "The payment changed. Reopen the correction and review it again."
            pendingCorrection = nil
            return
        }

        let oldPayment = request.payment
        let oldMethod = oldPayment.paymentMethod
        let now = Date()
        let replacement = Payment(
            order: order,
            paymentMethod: request.newMethod,
            amount: oldPayment.amount,
            transactionReference: "correction:\(oldPayment.id.uuidString.lowercased())",
            status: "completed",
            paidAt: oldPayment.paidAt,
            businessDateKey: oldPayment.businessDateKey,
            registerSessionId: oldPayment.registerSessionId,
            tipAmount: oldPayment.tipAmount,
            isSynced: false,
            updatedAt: now
        )

        oldPayment.status = "voided"
        oldPayment.isSynced = false
        oldPayment.updatedAt = now
        modelContext.insert(replacement)
        order.payments.append(replacement)
        AccountingLedgerService.recordVoidedPayment(oldPayment, order: order, in: modelContext)
        AccountingLedgerService.recordCapturedPayment(replacement, order: order, in: modelContext)
        order.isSynced = false
        order.updatedAt = now

        let approval = employeeId?.uuidString ?? "store_owner"
        let audit = AuditLog(
            employeeId: employeeId,
            actionType: "payment_method_corrected",
            details: "Order: \(order.orderNumber) — Payment: \(oldPayment.id.uuidString) — \(oldMethod) -> \(replacement.paymentMethod) — Amount: \(String(format: "%.2f", oldPayment.amount)) — Reason: \(request.reason) — Approved by: \(approval)",
            originalValue: oldPayment.amount,
            newValue: replacement.amount
        )
        modelContext.insert(audit)

        do {
            try modelContext.save()
            pendingCorrection = nil
            correctionResultMessage = isThai
                ? "แก้ไขช่องทางชำระเงินแล้ว ยอดขายรวมไม่เปลี่ยนแปลง"
                : "Payment method corrected. Total sales are unchanged."
            APHaptic.trigger()
            Task { await SyncEngine.shared.syncAll(modelContext: modelContext) }
        } catch {
            modelContext.rollback()
            pendingCorrection = nil
            correctionResultMessage = isThai
                ? "บันทึกไม่สำเร็จ: \(error.localizedDescription)"
                : "Could not save: \(error.localizedDescription)"
        }
    }

    private var paymentStatusText: String {
        if order.status == "cancelled" { return isThai ? "ยกเลิก" : "Cancelled" }
        if order.isSettled { return isThai ? "ชำระครบแล้ว" : "Paid" }
        if order.paidAmount > 0 { return isThai ? "ชำระบางส่วน" : "Partially paid" }
        return isThai ? "ยังไม่ชำระ" : "Unpaid"
    }

    private func exactTime(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .standard)
    }

    private func paymentDelayText(_ paidAt: Date) -> String {
        let seconds = max(0, Int(paidAt.timeIntervalSince(order.createdAt)))
        if seconds < 60 { return isThai ? "หลังคีย์ไม่ถึง 1 นาที" : "within 1 minute" }
        let minutes = seconds / 60
        return isThai ? "หลังคีย์ \(minutes) นาที" : "\(minutes)m after entry"
    }

    private func money(_ value: Double) -> String {
        String(format: "฿%.2f", value)
    }
}

private struct POSNotificationOrderDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("enable_table_system") private var tableSystemEnabled = true
    @Query(
        filter: #Predicate<RestaurantTable> { !$0.isDeleted },
        sort: \RestaurantTable.tableNumber
    )
    private var restaurantTables: [RestaurantTable]
    let order: Order
    let onApprove: () -> Void
    let onRecoverOriginalTable: () -> String?
    let onAssignTable: (String) -> String?
    let onOpenTableLayout: () -> Void
    @State private var recoveryError: String?

    private var currencySymbol: String {
        UserDefaults.standard.string(forKey: "app_currency_symbol") ?? "฿"
    }

    private var identity: OrderDisplayIdentity {
        OrderDisplayIdentity(order: order, tableSystemEnabled: tableSystemEnabled)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("notif_order_number".t, value: order.orderNumber)
                    if let queue = identity.queueNumber {
                        LabeledContent("queue_number".t, value: queue)
                    }
                    LabeledContent("notif_order_status".t, value: order.status.capitalized)
                    if !identity.isQuickService, let table = identity.tableNumber {
                        LabeledContent("table".t, value: table)
                    }
                }

                if order.requiresTableSessionRecovery {
                    Section {
                        Label {
                            Text("notif_recovery_warning".t)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                        }

                        if order.recoveryTableNumber != nil {
                            Button {
                                recoveryError = onRecoverOriginalTable()
                            } label: {
                                Label(
                                    LocalizationManager.shared.t(
                                        "notif_recover_original_table",
                                        order.recoveryTableNumber ?? ""
                                    ),
                                    systemImage: "arrow.clockwise.circle"
                                )
                            }
                        }

                        let vacantAlternatives = restaurantTables.filter { table in
                            table.status.lowercased() == "vacant"
                                && !table.sessions.contains(where: {
                                    $0.isActive && !$0.isDeleted
                                })
                                && table.tableNumber != order.recoveryTableNumber
                        }
                        if !vacantAlternatives.isEmpty {
                            Menu {
                                ForEach(vacantAlternatives) { table in
                                    Button("\("table".t) \(table.tableNumber)") {
                                        recoveryError = onAssignTable(table.tableNumber)
                                    }
                                }
                            } label: {
                                Label(
                                    "notif_assign_another_table".t,
                                    systemImage: "arrow.left.arrow.right"
                                )
                            }
                        }

                        Button {
                            dismiss()
                            onOpenTableLayout()
                        } label: {
                            Label(
                                "notif_choose_another_table".t,
                                systemImage: "rectangle.grid.2x2"
                            )
                        }
                    } header: {
                        Text("notif_recovery_required".t)
                    }
                }

                Section("notif_order_items".t) {
                    ForEach(order.items.filter { !$0.isDeleted }) { item in
                        POSNotificationOrderItemRow(
                            item: item,
                            currencySymbol: currencySymbol
                        )
                    }
                }

                Section {
                    LabeledContent(
                        "notif_order_total".t,
                        value: currencySymbol + String(format: "%.2f", order.total)
                    )
                }
            }
            .navigationTitle("notif_order_details_title".t)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("close_btn_label".t) { dismiss() }
                }
                if order.isAwaitingStaffApproval && !order.requiresTableSessionRecovery {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("notif_approve_order".t) {
                            onApprove()
                            dismiss()
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
            .alert(
                "notif_recovery_failed".t,
                isPresented: Binding(
                    get: { recoveryError != nil },
                    set: { if !$0 { recoveryError = nil } }
                )
            ) {
                Button(L.Common.close.t) { recoveryError = nil }
            } message: {
                Text(recoveryError ?? "")
            }
        }
        .apColorScheme()
    }

}

private struct POSNotificationOrderItemRow: View {
    let item: OrderItem
    let currencySymbol: String

    var body: some View {
        HStack {
            Text(String(item.quantity) + "x")
                .foregroundColor(.textSecondary)
            Text(displayName)
            Spacer()
            Text(linePrice)
                .foregroundColor(.textSecondary)
        }
    }

    private var displayName: String {
        if !item.itemName.isEmpty { return item.itemName }
        return item.menuItem?.localizedName ?? "Item"
    }

    private var linePrice: String {
        let total = item.unitPrice * Double(item.quantity)
        return currencySymbol + String(format: "%.2f", total)
    }
}

// MARK: - Cart Item Row

private struct CartItemRow: View {
    let cartItem:   CartItem

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            RemoteImageView(
                imageUrl: cartItem.snapshotImageURL,
                imageData: cartItem.snapshotImageData,
                fallbackColor: Color(hex: cartItem.snapshotColorHex ?? "1E1B4B"),
                fallbackIcon: "fork.knife",
                iconSize: 16
            )
            .frame(width: 46, height: 46)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(cartItem.snapshotLocalizedName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textPrimary)
                    .lineLimit(2)

                Text("\(cartItem.quantity) × ฿\(String(format: "%.0f", cartItem.totalPrice / Double(max(1, cartItem.quantity))))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.textSecondary)
                    .posRollingNumber(value: Double(cartItem.quantity))

                ForEach(cartItem.selectedModifiers, id: \.id) { modifier in
                    HStack {
                        Text("(\(modifier.name))")
                        Spacer()
                        Text("(+\(String(format: "%.0f", modifier.extraPrice))฿)")
                    }
                    .font(.system(size: 10.5))
                    .foregroundColor(.textTertiary)
                }

                if !cartItem.notes.isEmpty {
                    Text(cartItem.notes)
                        .font(.system(size: 10))
                        .foregroundColor(.textSecondary)
                        .lineLimit(1)
                }

                Text("pos_pending_confirmation".t)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(POSReferencePalette.accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(String(format: "฿%.0f", cartItem.totalPrice))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.textPrimary)
                .frame(width: 72, alignment: .trailing)
                .posRollingNumber(value: cartItem.totalPrice)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
        .padding(.vertical, 6)
        .background(Color.appSurface)
        .posOrderQuantityFlash(trigger: cartItem.quantity)
    }
}

// MARK: - Modifier Customizer Sheet

struct ModifierCustomizerView: View {
    let item:      MenuItem
    let onConfirm: ([Modifier]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selections: [UUID: Modifier] = [:]

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemBackground).ignoresSafeArea()

                VStack(spacing: 0) {
                    let groups = item.modifierGroupsRelations.compactMap { $0.modifierGroup }

                    ScrollView {
                        VStack(spacing: APSpacing.md) {
                            ForEach(groups) { group in
                                VStack(alignment: .leading, spacing: APSpacing.sm) {
                                    Text(group.name)
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundColor(.textSecondary)
                                        .textCase(.uppercase)
                                        .tracking(1)
                                        .padding(.horizontal, APSpacing.md)

                                    VStack(spacing: 1) {
                                        ForEach(group.modifiers) { modifier in
                                            HStack {
                                                Text(modifier.name)
                                                    .font(.subheadline)
                                                    .foregroundColor(.textPrimary)
                                                if modifier.extraPrice > 0 {
                                                    Text(String(format: "+฿%.0f", modifier.extraPrice))
                                                        .font(.caption)
                                                        .foregroundStyle(APGradient.accent)
                                                }
                                                Spacer()
                                                Image(systemName: selections[group.id]?.id == modifier.id
                                                      ? "checkmark.circle.fill" : "circle")
                                                    .font(.title3)
                                                    .foregroundStyle(
                                                        selections[group.id]?.id == modifier.id
                                                        ? APGradient.accent
                                                        : LinearGradient(colors: [.textTertiary], startPoint: .leading, endPoint: .trailing)
                                                    )
                                            }
                                            .padding(APSpacing.md)
                                            .background(Color.appSurface)
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                withAnimation(.easeOut(duration: 0.15)) {
                                                    selections[group.id] = modifier
                                                }
                                            }
                                        }
                                    }
                                    .clipShape(RoundedRectangle(cornerRadius: APRadius.md, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: APRadius.md, style: .continuous)
                                            .stroke(Color.appBorderSubtle, lineWidth: 1)
                                    )
                                    .padding(.horizontal, APSpacing.md)
                                }
                            }
                        }
                        .padding(.vertical, APSpacing.md)
                    }

                    // CTA
                    Button(action: {
                        onConfirm(Array(selections.values))
                        dismiss()
                    }) {
                        Label("add_to_cart_btn".t, systemImage: "cart.badge.plus")
                            .apGradientButton()
                    }
                    .padding(APSpacing.md)
                    .background(Color.appSurface)
                }
            }
            .navigationTitle("\("customize_title_prefix".t)\(item.localizedName)")
            .apNavBar(background: Color.appSurface)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.Common.cancel.t) { dismiss() }
                        .foregroundColor(.textSecondary)
                }
            }
        }
        .apColorScheme()
    }
}

// MARK: - Debounced POS Search

/// Owns the keystroke-level state so typing does not invalidate the complete
/// POS workspace and its product/order trees. The parent receives a settled
/// query after a short debounce, while barcode/SKU submission remains instant.
private struct POSMenuSearchBar: View {
    @Binding var query: String
    let placeholder: String
    let submitExactMatch: (String) -> Bool

    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.textSecondary)

            TextField(placeholder, text: $draft)
                .font(.system(size: 12.5))
                .foregroundColor(.textPrimary)
                .tint(POSReferencePalette.accent)
                .focused($isFocused)
                .submitLabel(.search)
                .lineLimit(1)
                .onSubmit {
                    if submitExactMatch(draft) {
                        draft = ""
                        query = ""
                    } else {
                        query = draft
                    }
                }

            if !draft.isEmpty {
                Button {
                    draft = ""
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(Color.appSurface)
        .clipShape(Capsule())
        .background {
            Button("") { isFocused = true }
                .keyboardShortcut("f", modifiers: [.command])
                .opacity(0)
        }
        .onAppear { draft = query }
        .onChange(of: query) { _, newValue in
            if newValue.isEmpty && !draft.isEmpty { draft = "" }
        }
        .task(id: draft) {
            do {
                try await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled else { return }
                query = draft
            } catch {
                // A new keystroke cancels the pending update.
            }
        }
    }
}

// MARK: - Cash Payment Modal View

struct CashPaymentModalView: View {
    let totalAmount: Double
    let onPark: () -> Void
    let onConfirm: (Double) async -> Bool
    @Environment(\.dismiss) private var dismiss

    @State private var banknoteAccumulated: Double = 0.0
    @State private var keypadSuffix: String = ""
    @State private var keypadValue: Double = 0.0
    @State private var showSuccessOverlay = false
    @State private var delayRemaining = 3.0
    @State private var isProcessing = false
    @State private var confirmedCashReceived: Double = 0.0
    @State private var confirmedChangeDue: Double = 0.0
    @State private var errorMessage: String? = nil
    @State private var autoDismissTask: Task<Void, Never>? = nil
    /// False means the primary action can complete an exact-cash sale in one tap.
    /// Keypad/quick-cash input switches the CTA back to amount confirmation.
    @State private var hasEnteredCustomAmount = false

    private var cashReceived: Double {
        banknoteAccumulated + (Double(keypadSuffix) ?? 0.0)
    }

    private var cashReceivedDisplayText: String {
        if banknoteAccumulated == 0 && keypadSuffix.isEmpty {
            return "0"
        }
        if !keypadSuffix.isEmpty {
            let total = banknoteAccumulated + keypadValue
            if keypadSuffix.contains(".") {
                return String(format: "%.2f", total)
            } else {
                return String(format: "%.0f", total)
            }
        } else {
            return formatAmountNoCent(banknoteAccumulated)
        }
    }

    private var changeDue: Double {
        cashReceived - totalAmount
    }

    private var isAmountSufficient: Bool {
        cashReceived >= totalAmount && cashReceived > 0
    }

    private var isPrimaryActionEnabled: Bool {
        !hasEnteredCustomAmount || isAmountSufficient
    }

    private struct QuickCashOption: Identifiable {
        let id: String
        let label: String
        let amount: Double
    }

    private var quickCashOptions: [QuickCashOption] {
        [
            QuickCashOption(id: "note_100", label: "฿100", amount: 100.0),
            QuickCashOption(id: "note_500", label: "฿500", amount: 500.0),
            QuickCashOption(id: "note_1000", label: "฿1,000", amount: 1000.0)
        ]
    }

    private func handleQuickCashTap(_ option: QuickCashOption) {
        errorMessage = nil
        hasEnteredCustomAmount = true
        withAnimation(.spring(response: 0.2, dampingFraction: 0.65)) {
            banknoteAccumulated += option.amount
        }
        APNativeKeypadFeedback.tap()
    }

    private func handleKeypadInput(_ input: String) {
        withAnimation(.spring(response: 0.2, dampingFraction: 0.65)) {
            errorMessage = nil
            hasEnteredCustomAmount = true
            if input == "⌫" {
                if !keypadSuffix.isEmpty {
                    keypadSuffix.removeLast()
                } else if banknoteAccumulated > 0 {
                    banknoteAccumulated = 0
                }
            } else if input == "." {
                if !keypadSuffix.contains(".") {
                    if keypadSuffix.isEmpty {
                        keypadSuffix = "0."
                    } else {
                        keypadSuffix += "."
                    }
                }
            } else if input == "00" {
                if !keypadSuffix.isEmpty && keypadSuffix != "0" && keypadSuffix.count <= 6 {
                    keypadSuffix += "00"
                }
            } else {
                if keypadSuffix == "0" {
                    keypadSuffix = input
                } else if keypadSuffix.count < 8 {
                    keypadSuffix += input
                }
            }
            keypadValue = Double(keypadSuffix) ?? 0
        }
        APNativeKeypadFeedback.tap()
    }

    private func formatAmountNoCent(_ amount: Double) -> String {
        if amount.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", amount)
        } else {
            return String(format: "%.2f", amount)
        }
    }

    /// Confirm payment and wait for durable local commit before presenting the change overlay.
    private func confirmPayment() {
        guard !isProcessing, isAmountSufficient else { return }
        isProcessing = true
        errorMessage = nil
        APHaptic.trigger()

        // Freeze the values shown by the success overlay before checkout mutates
        // the parent cart/session and causes `totalAmount` to be rendered as zero.
        let tenderedSnapshot = cashReceived
        let changeSnapshot = max(0, tenderedSnapshot - totalAmount)
        confirmedCashReceived = tenderedSnapshot
        confirmedChangeDue = changeSnapshot

        Task { @MainActor in
            let success = await onConfirm(tenderedSnapshot)
            if success {
                isProcessing = false
                withAnimation(.snappy(duration: 0.25)) {
                    showSuccessOverlay = true
                }

                // Optional auto-dismiss of the change UI (does not gate payment/print).
                let holdSeconds = changeSnapshot > 0 ? 3 : 2
                delayRemaining = Double(holdSeconds)
                autoDismissTask?.cancel()
                autoDismissTask = Task { @MainActor in
                    for _ in 0..<holdSeconds {
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        guard !Task.isCancelled else { return }
                        withAnimation {
                            if delayRemaining > 1 {
                                delayRemaining -= 1
                            }
                        }
                    }
                    guard !Task.isCancelled else { return }
                    dismiss()
                }
            } else {
                isProcessing = false
                errorMessage = "บันทึกการชำระเงินไม่สำเร็จ กรุณาลองใหม่อีกครั้ง"
                APHaptic.trigger()
            }
        }
    }

    /// Default checkout is exact cash, requiring one tap. Once the cashier has
    /// entered another amount, the same control confirms that explicit amount.
    private func confirmPrimaryPayment() {
        if !hasEnteredCustomAmount {
            banknoteAccumulated = totalAmount
            keypadSuffix = ""
            keypadValue = 0
        }
        confirmPayment()
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                if showSuccessOverlay {
                    successOverlayView
                        .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.95)), removal: .opacity))
                } else {
                    mainContentView
                        .transition(.opacity)
                }
            }
            .navigationTitle("cash_payment_title".t)
            .navigationBarTitleDisplayMode(.inline)
            .apNavBar(background: Color.appSurface)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if showSuccessOverlay {
                        Button("done_btn".t) {
                            autoDismissTask?.cancel()
                            dismiss()
                        }
                        .tint(.blue)
                        .fontWeight(.semibold)
                    } else {
                        Button(L.Common.cancel.t) {
                            autoDismissTask?.cancel()
                            dismiss()
                        }
                        .disabled(isProcessing)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    if !showSuccessOverlay {
                        Button {
                            onPark()
                            dismiss()
                        } label: {
                            Label("พักและรับลูกค้าถัดไป", systemImage: "pause.circle.fill")
                                .font(.subheadline.weight(.bold))
                        }
                        .tint(.orange)
                    }
                }
            }
        }
        .apColorScheme()
        .fontDesign(.default)
        .onAppear {
            APSoundEffect.prepare()
        }
        .onDisappear {
            autoDismissTask?.cancel()
            autoDismissTask = nil
        }
    }

    private var mainContentView: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                // MARK: Left Column: Bill details, Quick Cash Shortcuts, and Dynamic Change Status
                VStack(spacing: 10) {
                    // 1. Total Due Card (Highlight Card)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.text.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.blue)
                            Text("pos_total_amount".t)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.textSecondary)
                                .textCase(.uppercase)
                                .tracking(0.5)
                            Spacer()
                        }

                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(String(format: "฿%.2f", totalAmount))
                                .font(.system(size: 32, weight: .black))
                                .foregroundStyle(.primary)
                                .posRollingNumber(value: totalAmount)
                            Spacer()
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .apChromeSurface(
                        usesMaterial: false,
                        in: RoundedRectangle(cornerRadius: APRadius.md, style: .continuous)
                    )

                    // 2. Smart Quick Cash Shortcuts Grid (Equal Size: Exact, 100, 500, 1000)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "banknote.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.blue)
                            Text("pos_quick_cash".t)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.textSecondary)
                                .textCase(.uppercase)
                                .tracking(0.5)
                            Spacer()
                        }

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                            ForEach(quickCashOptions) { option in
                                quickCashTile(option: option)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .apChromeSurface(
                        usesMaterial: false,
                        in: RoundedRectangle(cornerRadius: APRadius.md, style: .continuous)
                    )

                    // 3. Dynamic Live Change Status Hero Card
                    liveStatusHeroCard
                        .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity)

                // MARK: Right Column: Tendered Input Box and Ergonomic Keypad Grid
                VStack(spacing: 10) {
                    // 1. Cash Tendered Display Card
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.blue)

                            Text("tendered_label".t.isEmpty ? "จำนวนเงินที่รับ" : "tendered_label".t)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.textSecondary)
                                .textCase(.uppercase)
                                .tracking(0.5)

                            Spacer()

                            Button {
                                banknoteAccumulated = 0
                                keypadSuffix = ""
                                keypadValue = 0
                                hasEnteredCustomAmount = false
                                errorMessage = nil
                                APHaptic.trigger()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 12, weight: .bold))
                                    Text("Clear")
                                        .font(.system(size: 11, weight: .bold))
                                }
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .apGlassButton(tint: .textSecondary)
                            .opacity(cashReceived > 0 || !keypadSuffix.isEmpty ? 1 : 0)
                            .allowsHitTesting(cashReceived > 0 || !keypadSuffix.isEmpty)
                        }
                        .frame(height: 22)

                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Spacer()

                            Text("฿")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(cashReceived == 0 ? .textTertiary : .blue)

                            CashReceivedNumberView(value: cashReceived, text: cashReceivedDisplayText)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .apChromeSurface(
                        tint: isAmountSufficient ? .blue.opacity(0.12) : nil,
                        usesMaterial: false,
                        in: RoundedRectangle(cornerRadius: APRadius.md, style: .continuous)
                    )

                    // 2. Keypad Grid
                    CashKeypadGrid(onInput: handleKeypadInput)
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: 720)

            if let errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(errorMessage)
                        .font(.footnote.weight(.medium))
                        .foregroundColor(.red)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: APRadius.sm, style: .continuous))
                .cornerRadius(APRadius.sm)
                .frame(maxWidth: 520)
            }

            // MARK: Bottom Confirmation CTA Button
            Button(action: confirmPrimaryPayment) {
                HStack(spacing: 10) {
                    if isProcessing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Image(systemName: !hasEnteredCustomAmount || isAmountSufficient ? "checkmark.circle.fill" : "arrow.right.circle")
                            .font(.system(size: 22, weight: .bold))
                    }

                    if !hasEnteredCustomAmount {
                        Text("รับเงินพอดี ฿\(String(format: "%.2f", totalAmount))")
                    } else if isAmountSufficient {
                        if changeDue > 0 {
                            Text("ยืนยันรับเงิน (เงินทอน ฿\(String(format: "%.2f", changeDue)))")
                        } else {
                            Text("ยืนยันรับเงินพอดี (฿\(String(format: "%.2f", cashReceived)))")
                        }
                    } else {
                        if cashReceived > 0 {
                            let missingAmount = totalAmount - cashReceived
                            Text("จำนวนเงินยังไม่ครบ (ขาดอีก ฿\(String(format: "%.2f", missingAmount)))")
                        } else {
                            Text("กรุณาระบุจำนวนเงินที่รับ")
                        }
                    }
                }
                .font(.system(size: 20, weight: .bold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 58)
            }
            .disabled(!isPrimaryActionEnabled || isProcessing)
            .controlSize(.large)
            .apGlassButton(prominent: true, tint: .blue)
            .frame(maxWidth: 520)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    // MARK: - Quick Cash Tile View
    private func quickCashTile(option: QuickCashOption) -> some View {
        let isSelected = abs(cashReceived - option.amount) < 0.01 && cashReceived > 0

        return Button {
            handleQuickCashTap(option)
        } label: {
            Text(option.label)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(isSelected ? .white : .textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
        }
        .controlSize(.large)
        // Low-frequency shortcut controls can use the native iPadOS Liquid
        // Glass treatment without entering the high-frequency keypad render
        // path. The keypad itself intentionally keeps Calculator-style chrome.
        .apGlassButton(prominent: isSelected, tint: isSelected ? .blue : nil)
    }

    // MARK: - Dynamic Live Status Hero Card
    @ViewBuilder
    private var liveStatusHeroCard: some View {
        if cashReceived == 0 {
            // State 1: Awaiting Tender
            HStack(spacing: 12) {
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.blue)

                VStack(alignment: .leading, spacing: 3) {
                    Text("รอรับเงินสด")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.textPrimary)
                    Text("กดรับเงินพอดีด้านล่าง หรือระบุจำนวนเงินที่รับ")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.textSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .apChromeSurface(
                usesMaterial: false,
                in: RoundedRectangle(cornerRadius: APRadius.md, style: .continuous)
            )
        } else if !isAmountSufficient {
            // State 2: Insufficient Cash
            let missingAmount = totalAmount - cashReceived
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.red)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("pos_amount_missing".t)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.red)
                        .textCase(.uppercase)
                        .tracking(0.5)

                    Text(String(format: "-฿%.2f", missingAmount))
                        .font(.system(size: 22, weight: .black))
                        .foregroundColor(.red)
                        .transaction { $0.animation = nil }
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .apChromeSurface(
                tint: .red.opacity(0.12),
                usesMaterial: false,
                in: RoundedRectangle(cornerRadius: APRadius.md, style: .continuous)
            )
        } else {
            // State 3: Sufficient (Exact or Change Due)
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: changeDue > 0 ? "arrow.counterclockwise.circle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.blue)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(changeDue > 0 ? "pos_change_due".t : "รับเงินพอดี (ไม่ต้องทอน)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.blue)
                        .textCase(.uppercase)
                        .tracking(0.5)

                    Text(String(format: "฿%.2f", changeDue))
                        .font(.system(size: 24, weight: .black))
                        .foregroundColor(.blue)
                        // Keep cash-critical values crisp even when a parent
                        // status transition is animated.
                        .transaction { $0.animation = nil }
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .apChromeSurface(
                tint: .blue.opacity(0.12),
                usesMaterial: false,
                in: RoundedRectangle(cornerRadius: APRadius.md, style: .continuous)
            )
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }

    // MARK: - Keypad Grid (Isolated Subview)
}

private struct CashKeypadGrid: View {
    let onInput: (String) -> Void

    private static let keys = [
        ["7", "8", "9"],
        ["4", "5", "6"],
        ["1", "2", "3"],
        [".", "0", "⌫"]
    ]

    var body: some View {
        VStack(spacing: 7) {
            ForEach(Self.keys, id: \.self) { row in
                HStack(spacing: 7) {
                    ForEach(row, id: \.self) { key in
                        Button {
                            onInput(key)
                        } label: {
                            Group {
                                if key == "⌫" {
                                    Image(systemName: "delete.backward.fill")
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundColor(.red)
                                } else {
                                    Text(key)
                                        .font(.system(size: 24, weight: .bold))
                                        .foregroundColor(key == "." ? .textSecondary : .textPrimary)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 54)
                        }
                        .controlSize(.large)
                        .apGlassButton()
                    }
                }
            }
        }
        .transaction { $0.animation = nil }
    }
}

extension CashPaymentModalView {

    // MARK: - Success Overlay View
    private var successOverlayView: some View {
        VStack(spacing: APSpacing.lg) {
            Spacer()

            // Checkmark Animation
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.18))
                    .frame(width: 90, height: 90)

                Circle()
                    .stroke(Color.blue, lineWidth: 3)
                    .frame(width: 90, height: 90)
                    .scaleEffect(isProcessing ? 1.05 : 1.0)
                    .animation(.snappy(duration: 0.35), value: isProcessing)

                Image(systemName: "checkmark")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundColor(.blue)
            }

            VStack(spacing: APSpacing.xs) {
                Text("pos_payment_successful".t)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.textPrimary)

                Text(LocalizationManager.shared.t("received_cash_template", confirmedCashReceived))
                    .font(.subheadline)
                    .foregroundColor(.textSecondary)
            }

            // Large Change Due Box
            if confirmedChangeDue > 0 {
                VStack(spacing: 4) {
                    Text("pos_change_due".t)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.textSecondary)

                    Text(String(format: "฿%.2f", confirmedChangeDue))
                        .font(.system(size: 40, weight: .black))
                        .foregroundColor(.blue)
                        .scaleEffect(1.03)
                        .animation(.snappy(duration: 0.25), value: isProcessing)
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 28)
                .apLiquidGlass(
                    tint: .blue.opacity(0.12),
                    allowNativeOnPad: true,
                    in: RoundedRectangle(cornerRadius: APRadius.lg, style: .continuous)
                )
            } else {
                Text("pos_no_change_due".t)
                    .font(.headline)
                    .foregroundColor(.blue)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .apLiquidGlass(
                        tint: .blue.opacity(0.12),
                        allowNativeOnPad: true,
                        in: RoundedRectangle(cornerRadius: APRadius.md, style: .continuous)
                    )
            }

            Spacer()

            Button(action: {
                autoDismissTask?.cancel()
                dismiss()
            }) {
                Text("done_btn".t)
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .controlSize(.large)
            .apGlassButton(prominent: true, tint: .blue)
            .padding(.horizontal, 28)
            .frame(maxWidth: 480)

            Text(LocalizationManager.shared.t("cash_overlay_auto_close", Int(delayRemaining)))
                .font(.caption)
                .foregroundColor(.textSecondary)
                .padding(.bottom, APSpacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
    }
}

struct KeypadButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.75 : 1.0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

private struct CashReceivedNumberView: View {
    let value: Double
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 34, weight: .black))
            .foregroundStyle(value == 0 ? .secondary : .primary)
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .frame(height: 42, alignment: .trailing)
            // CASH_KEYPAD_IMMEDIATE_RENDER: never leave tendered digits between
            // animation frames while the cashier is typing rapidly.
            .transaction { $0.animation = nil }
    }
}

// MARK: - Thai QR Payment Frame View (Standard Compliant Layout)

struct ThaiQRPaymentFrame: View {
    let storeName: String
    let promptPayNumber: String
    let amount: Double
    let qrImage: UIImage?

    var body: some View {
        VStack(spacing: 0) {
            // 1. Thai QR Payment Banner Header (Dark Blue)
            HStack(spacing: 12) {
                // Thai QR logo mark: white rounded tile with a crisp QR glyph
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white)
                        .frame(width: 32, height: 32)

                    Image(systemName: "qrcode")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(Color(hex: "0C2B64"))
                }
                
                VStack(alignment: .leading, spacing: 0) {
                    Text("THAI QR")
                        .font(.system(size: 13, weight: .black))
                        .foregroundColor(.white)
                    Text("PAYMENT")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white.opacity(0.9))
                }
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(hex: "0C2B64")) // Official Thai QR deep blue
            
            // 2. Logos row (Visa, Mastercard, PromptPay)
            HStack(spacing: 12) {
                Spacer()
                
                // Stylized Visa Logo Card
                Text("VISA")
                    .font(.system(size: 10, weight: .black))
                    .italic()
                    .foregroundColor(Color(hex: "1A1F71"))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white)
                    .cornerRadius(3)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.gray.opacity(0.3), lineWidth: 0.5))

                // Stylized Mastercard Circles
                HStack(spacing: -4) {
                    Circle()
                        .fill(Color(hex: "EB001B"))
                        .frame(width: 12, height: 12)
                    Circle()
                        .fill(Color(hex: "F79E1B").opacity(0.85))
                        .frame(width: 12, height: 12)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.white)
                .cornerRadius(3)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.gray.opacity(0.3), lineWidth: 0.5))
                
                // Stylized PromptPay Logo
                HStack(spacing: 2) {
                    // Small circle icon
                    Circle()
                        .fill(Color(hex: "173A5E"))
                        .frame(width: 8, height: 8)
                    Text("PromptPay")
                        .font(.system(size: 8, weight: .black))
                        .foregroundColor(Color(hex: "173A5E"))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(Color.white)
                .cornerRadius(3)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.gray.opacity(0.3), lineWidth: 0.5))

                Spacer()
            }
            .padding(.vertical, 8)
            .background(Color(hex: "F8F9FA")) // Light gray subheader

            Divider()
                .background(Color.gray.opacity(0.2))

            // 3. QR Code & Merchant info area
            VStack(spacing: 16) {
                // QR Image Frame
                ZStack {
                    if let img = qrImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 200, height: 200)
                    } else {
                        Image(systemName: "qrcode")
                            .font(.system(size: 160, weight: .light))
                            .foregroundColor(.textPrimary)
                            .frame(width: 200, height: 200)
                    }
                }
                .padding(10)
                .background(Color.white)
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.15), lineWidth: 1.5))
                
                // Merchant/Store Name & ID
                VStack(spacing: 4) {
                    Text(storeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Merchant Store" : storeName)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(Color(hex: "333333"))
                    
                    Text("PromptPay ID: \(promptPayNumber)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.gray)
                }

                // Amount
                VStack(spacing: 2) {
                    Text(String(format: "%.2f", amount))
                        .font(.system(size: 28, weight: .black))
                        .foregroundColor(Color(hex: "0C2B64"))
                    
                    Text("บาท (THB)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color(hex: "0C2B64").opacity(0.8))
                }
            }
            .padding(.vertical, 24)
            .padding(.horizontal, 16)
            .background(Color.white)
        }
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 5)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - QR Payment Modal View

/// Dedicated government co-payment confirmation. It intentionally does not
/// generate a PromptPay QR or classify the citizen portion as cash/PromptPay.
struct ThaiChuaThaiPlusPaymentModal: View {
    let totalAmount: Double
    let onPark: () -> Void
    let onConfirm: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var reference = ""

    private var split: (citizen: Double, government: Double) {
        GovernmentSupportProgram.split(total: totalAmount)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: APSpacing.lg) {
                    VStack(spacing: 8) {
                    Image("ThaiChuaThaiPlusLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 310, maxHeight: 110)
                        .accessibilityLabel(GovernmentSupportProgram.thaiChuaThaiPlus)
                    Text(GovernmentSupportProgram.thaiChuaThaiPlus)
                        .font(.title2.bold())
                    Text("ตรวจสอบว่าชำระในถุงเงินสำเร็จแล้ว ก่อนกดชำระเงินและออกใบเสร็จ")
                        .font(.subheadline).foregroundColor(.textSecondary)
                }

                VStack(spacing: 12) {
                    supportPaymentRow("ยอดขายเต็มจำนวน", amount: totalAmount, color: .textPrimary)
                    Divider()
                    supportPaymentRow("รัฐสนับสนุน 60%", amount: split.government, color: .appAccent)
                    supportPaymentRow("ประชาชนชำระผ่านโครงการ 40%", amount: split.citizen, color: .appTeal)
                }
                .padding(APSpacing.lg)
                .background(Color.appSurface)
                .clipShape(RoundedRectangle(cornerRadius: APRadius.md))

                VStack(alignment: .leading, spacing: 8) {
                    Text("เลขอ้างอิงรายการโครงการ (ไม่บังคับ)")
                        .font(.caption.bold()).foregroundColor(.textSecondary)
                    TextField("กรอกตอนนี้ หรือเพิ่มภายหลังในหน้ากระทบยอด", text: $reference)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .padding(12)
                        .background(Color.appSurfaceHigh)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                Text("ยอดสนับสนุน 60% จะบันทึกเป็นลูกหนี้รอรับจากรัฐ ไม่ถือเป็นเงินสดหรือ PromptPay")
                    .font(.footnote).foregroundColor(.appAmber)
                    .frame(maxWidth: .infinity, alignment: .leading)

                }
                .padding(APSpacing.lg)
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("ชำระด้วยไทยช่วยไทย Plus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.Common.cancel.t) { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("พักรายการ") { onPark(); dismiss() }
                        .foregroundColor(.appAmber)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 8) {
                    Text(confirmRequirementMessage)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.textSecondary)
                    Button {
                        let normalizedReference = reference.trimmingCharacters(in: .whitespacesAndNewlines)
                        onConfirm(normalizedReference)
                        dismiss()
                    } label: {
                        Label("ชำระเงินและออกใบเสร็จ", systemImage: "checkmark.seal.fill")
                            .font(.system(.headline, design: .default, weight: .semibold))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, minHeight: 58)
                    }
                    .disabled(!canConfirm)
                    .controlSize(.large)
                    .apGlassButton(prominent: true, tint: .appAccent)
                    .frame(maxWidth: 520)
                    .accessibilityHint(confirmRequirementMessage)
                }
                .padding(.horizontal, APSpacing.lg)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .background(.ultraThinMaterial)
                .overlay(alignment: .top) { Divider() }
            }
        }
        .apColorScheme()
    }

    private var canConfirm: Bool {
        true
    }

    private var confirmRequirementMessage: String {
        reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "ไม่กรอกได้ — ระบบจะสร้างเลขติดตามภายในและให้เพิ่มภายหลัง"
            : "ระบบจะบันทึกเลขอ้างอิงนี้สำหรับการกระทบยอด"
    }

    private func supportPaymentRow(_ label: String, amount: Double, color: Color) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundColor(.textSecondary)
            Spacer()
            Text("฿\(amount, specifier: "%.2f")")
                .font(.headline).foregroundColor(color)
        }
    }
}

struct QRPaymentModalView: View {
    let totalAmount: Double
    let onPark: () -> Void
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    @AppStorage("promptpay_mode") private var promptPayMode = "direct"
    @AppStorage("promptpay_number") private var promptPayNumber = ""
    @AppStorage("promptpay_account_name") private var promptPayAccountName = ""
    @AppStorage("promptpay_lock_amount") private var promptPayLockAmount = true
    @AppStorage("store_name") private var storeName = ""

    @State private var qrImage: UIImage? = nil

    private var isOfflineMode: Bool {
        OfflineSyncModeController.isEnabled || OfflineSyncModeController.isOfflineSubscriptionPlan
    }

    private var qrPayload: String {
        PromptPayPayloadGenerator.generate(
            target: promptPayNumber,
            amount: promptPayLockAmount ? totalAmount : nil,
            isDynamic: promptPayLockAmount
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                let isConfigured = !promptPayNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let effectiveStoreName = promptPayAccountName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? storeName : promptPayAccountName

                VStack(spacing: 0) {
                    // Scrollable content
                    ScrollView {
                        VStack(spacing: APSpacing.lg) {
                            if !isConfigured {
                                // Warning: PromptPay not configured
                                VStack(spacing: APSpacing.md) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 64))
                                        .foregroundColor(.appAmber)
                                        .padding()

                                    Text("promptpay_not_configured_title".t)
                                        .font(.headline)
                                        .foregroundColor(.textPrimary)

                                    Text("promptpay_not_configured_desc".t)
                                        .font(.subheadline)
                                        .foregroundColor(.textSecondary)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal)
                                }
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.appSurface)
                                .cornerRadius(APRadius.md)
                            } else {
                                // Standard-compliant Thai QR payment frame
                                ThaiQRPaymentFrame(
                                    storeName: effectiveStoreName,
                                    promptPayNumber: promptPayNumber,
                                    amount: totalAmount,
                                    qrImage: qrImage
                                )
                            }

                            // Status / verification notice
                            HStack(alignment: .top, spacing: APSpacing.sm) {
                                if !isConfigured {
                                    Text("awaiting_configuration".t)
                                        .font(.footnote)
                                        .foregroundColor(.appAmber)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                } else if promptPayMode == "api" && !isOfflineMode {
                                    Image(systemName: "network")
                                        .foregroundColor(.appAccent)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("โหมด API Gateway")
                                            .font(.footnote.weight(.bold))
                                            .foregroundColor(.appAccent)
                                        Text("ระบบกำลังรอรับสัญญาณชำระเงินจากธนาคาร หรือสามารถตรวจสอบยอดแล้วกดยืนยันด้วยตนเองได้")
                                            .font(.footnote)
                                            .foregroundColor(.textSecondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                } else {
                                    Image(systemName: "lock.shield.fill")
                                        .foregroundColor(promptPayLockAmount ? .green : .appAmber)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(promptPayLockAmount ? "พร้อมเพย์ตรง · ล็อกยอดเงินตามบิล" : "พร้อมเพย์ตรง · ยอดเงินกำหนดเอง")
                                            .font(.footnote.weight(.bold))
                                            .foregroundColor(promptPayLockAmount ? .green : .appAmber)
                                        Text("ระบบได้สร้าง QR Code พร้อมเพย์ตามยอดบิลเรียบร้อยแล้ว กรุณาตรวจสอบสลิปหรือการแจ้งเตือนของธนาคารก่อนกดยืนยัน")
                                            .font(.footnote)
                                            .foregroundColor(.textSecondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.appSurface)
                            .cornerRadius(APRadius.md)
                            .overlay(
                                RoundedRectangle(cornerRadius: APRadius.md)
                                    .stroke(Color.appBorderSubtle, lineWidth: 1)
                            )
                        }
                        .frame(maxWidth: 420)
                        .frame(maxWidth: .infinity)
                        .padding(APSpacing.md)
                    }

                    // Pinned footer CTA
                    VStack(spacing: 0) {
                        Divider()
                        Button(action: {
                            onConfirm()
                            dismiss()
                        }) {
                            Label(
                                String(format: "ยืนยันรับชำระเงินเรียบร้อย (฿%.2f)", totalAmount),
                                systemImage: "checkmark.circle.fill"
                            )
                            .font(.system(.headline, design: .default, weight: .semibold))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, minHeight: 58)
                        }
                        .disabled(!isConfigured)
                        .controlSize(.large)
                        .apGlassButton(prominent: true, tint: .appAccent)
                        .frame(maxWidth: 520)
                        .frame(maxWidth: .infinity)
                        .padding(APSpacing.md)
                    }
                    .background(.ultraThinMaterial)
                }
            }
            .navigationTitle("promptpay_qr_code_title".t)
            .navigationBarTitleDisplayMode(.inline)
            .apNavBar(background: Color.appSurface)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.Common.cancel.t) { dismiss() }
                        .foregroundColor(.textSecondary)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("พักและรับลูกค้าถัดไป") { onPark(); dismiss() }
                        .foregroundColor(.appAmber)
                }
            }
        }
        .task(id: qrPayload) {
            qrImage = PromptPayPayloadGenerator.generateQRCodeImage(from: qrPayload)
        }
        .apColorScheme()
    }
}

// MARK: - Credit Card Payment Modal View

struct CreditCardPaymentModalView: View {
    let totalAmount: Double
    let onPark: () -> Void
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                VStack(spacing: APSpacing.lg) {
                    // Info Card
                    VStack(spacing: 8) {
                        Text("card_total_label".t)
                            .font(.subheadline)
                            .foregroundColor(.textSecondary)
                        Text(String(format: "฿%.2f", totalAmount))
                            .font(.title).fontWeight(.black)
                            .foregroundStyle(APGradient.accent)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.appSurface)
                    .cornerRadius(APRadius.md)

                    // External terminal confirmation
                    VStack(spacing: APSpacing.md) {
                        Image(systemName: "creditcard.and.123")
                            .font(.system(size: 64))
                            .foregroundColor(.appAccent)

                        VStack(spacing: 4) {
                            Text("Process the card on the external EDC terminal")
                                .font(.headline)
                                .foregroundColor(.textPrimary)
                            Text("This app is not connected to an acquirer. Confirm only after the terminal shows an approval.")
                                .font(.caption)
                                .foregroundColor(.textSecondary)
                        }
                        .multilineTextAlignment(.center)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, minHeight: 200)
                    .background(Color.appSurface)
                    .cornerRadius(APRadius.md)
                    .overlay(
                        RoundedRectangle(cornerRadius: APRadius.md)
                            .stroke(Color.appBorderSubtle, lineWidth: 1)
                    )

                    Spacer()

                    // Complete Button
                    Button(action: {
                        onConfirm()
                        dismiss()
                    }) {
                        Label("Confirm external terminal approved", systemImage: "checkmark.circle.fill")
                            .font(.system(.headline, design: .default, weight: .semibold))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, minHeight: 58)
                    }
                    .controlSize(.large)
                    .apGlassButton(prominent: true, tint: .appAccent)
                    .frame(maxWidth: 520)
                }
                .padding(APSpacing.md)
            }
            .navigationTitle("card_checkout_title".t)
            .apNavBar(background: Color.appSurface)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.Common.cancel.t) { dismiss() }
                        .foregroundColor(.textSecondary)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("พักและรับลูกค้าถัดไป") { onPark(); dismiss() }
                        .foregroundColor(.appAmber)
                }
            }
        }
        .apColorScheme()
    }
}

private struct QuickOrderQueueSheet: View {
    let orders: [Order]
    let onSelect: (Order) -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var lm: LocalizationManager

    var body: some View {
        NavigationStack {
            List(orders) { order in
                Button {
                    onSelect(order)
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(order.queueNumber.map { "คิว #\($0)" } ?? order.orderNumber)
                                .font(.headline)
                            Text(order.orderNumber)
                                .font(.caption.monospaced())
                                .foregroundColor(.secondary)
                            Text(order.orderType == "delivery" ? "Delivery" : (order.orderType == "walk_in" ? "Walk-in" : "Takeaway"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(order.status.capitalized)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.appAmber)
                    }
                }
                .buttonStyle(.plain)
            }
            .overlay {
                if orders.isEmpty {
                    ContentUnavailableView(
                        lm.currentLanguage == .thai ? "ไม่มี Quick Order" : "No Quick Orders",
                        systemImage: "takeoutbag.and.cup.and.straw",
                        description: Text(lm.currentLanguage == .thai ? "ออเดอร์จาก iPhone จะแสดงที่นี่" : "Orders from iPhone will appear here")
                    )
                }
            }
            .navigationTitle(lm.currentLanguage == .thai ? "คิวออเดอร์ด่วน" : "Quick Order Queue")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(lm.currentLanguage == .thai ? "ปิด" : "Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    POSView(
        activeSession: .constant(nil),
        selectedTab: .constant(.pos),
        columnVisibility: .constant(.all),
        focusedOrderNumber: .constant(nil),
        quickOrderMode: .constant(true)
    )
}

// MARK: - C-1: Gift Card Picker Sheet

struct GiftCardPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var lm: LocalizationManager

    let cards: [GiftCard]
    let totalAmount: Double
    let onSelect: (GiftCard, Double) -> Void

    @State private var selectedCard: GiftCard? = nil
    @State private var redeemText: String = ""

    private var redeemAmount: Double {
        Double(redeemText) ?? 0
    }

    private var maxRedeem: Double {
        guard let card = selectedCard else { return 0 }
        return min(card.balance, totalAmount)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                VStack(spacing: 16) {

                    // Card list
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(cards) { card in
                                Button {
                                    selectedCard = card
                                    redeemText = String(format: "%.2f", min(card.balance, totalAmount))
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text("···\(card.cardNumber.suffix(4))")
                                                .font(.system(size: 13, weight: .bold))
                                                .foregroundColor(.textPrimary)
                                            if let customer = card.customer {
                                                Text(customer.name)
                                                    .font(.caption)
                                                    .foregroundColor(.textSecondary)
                                            }
                                        }
                                        Spacer()
                                        Text(String(format: "฿%.2f", card.balance))
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(.appTeal)
                                    }
                                    .padding(12)
                                    .background(selectedCard?.id == card.id
                                        ? Color.appTeal.opacity(0.12)
                                        : Color.appSurface)
                                    .cornerRadius(10)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(selectedCard?.id == card.id
                                                ? Color.appTeal : Color.appBorderSubtle, lineWidth: 1.5)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                    }

                    // Amount to redeem
                    if selectedCard != nil {
                        VStack(spacing: 6) {
                            Text("pos_gift_card_redeem_amount".t)
                                .font(.caption).foregroundColor(.textSecondary)
                            HStack {
                                Text("฿").foregroundColor(.textSecondary)
                                TextField("0.00", text: $redeemText)
                                    .keyboardType(.decimalPad)
                                    .font(.title3.bold())
                                    .foregroundColor(.appTeal)
                                Button("max_btn".t) {
                                    redeemText = String(format: "%.2f", maxRedeem)
                                }
                                .font(.caption.bold())
                                .foregroundColor(.appAccent)
                            }
                            .padding(12)
                            .background(Color.appSurface)
                            .cornerRadius(10)
                            .padding(.horizontal)

                            if redeemAmount > maxRedeem && maxRedeem > 0 {
                                Text("pos_gift_card_exceed_warning".t)
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                    }

                    // Confirm button
                    Button {
                        if let card = selectedCard, redeemAmount > 0 {
                            onSelect(card, min(redeemAmount, maxRedeem))
                            dismiss()
                        }
                    } label: {
                        Text("pos_gift_card_confirm".t)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(selectedCard != nil && redeemAmount > 0
                                ? APGradient.accent
                                : LinearGradient(colors: [Color.appSurfaceHigh], startPoint: .leading, endPoint: .trailing))
                            .foregroundColor(selectedCard != nil && redeemAmount > 0 ? .white : .textTertiary)
                            .cornerRadius(APRadius.md)
                    }
                    .disabled(selectedCard == nil || redeemAmount <= 0 || redeemAmount > maxRedeem)
                    .padding(.horizontal)
                    .padding(.bottom)
                }
            }
            .navigationTitle("pos_gift_card".t)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("cancel_btn".t) { dismiss() }
                        .foregroundColor(.textSecondary)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
