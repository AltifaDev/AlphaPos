// POSView.swift
// AlphaPos — Premium POS Interface

import SwiftUI
import SwiftData

struct POSView: View {
    @EnvironmentObject private var sessionManager: AppSessionManager
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var lm: LocalizationManager
    @Query(sort: \Category.name) private var categories: [Category]
    @Query(sort: \MenuItem.name) private var menuItems: [MenuItem]
    @Query(filter: #Predicate<RegisterSession> { $0.closedAt == nil && !$0.isDeleted })
    private var activeRegisterSessions: [RegisterSession]

    @Binding var activeSession: TableSession?
    @Binding var selectedTab: MainDashboardView.DashboardTab
    @Binding var columnVisibility: NavigationSplitViewVisibility

    @AppStorage("enable_table_system") private var enableTableSystem = true
    
    @AppStorage("payment_method_cash_enabled") private var cashEnabled = true
    @AppStorage("payment_method_card_enabled") private var cardEnabled = true
    @AppStorage("payment_method_qr_enabled") private var qrEnabled = true

    @State private var viewModel = POSViewModel()
    @State private var showNoActiveShiftAlert = false
    @State private var showStartShiftSheet = false
    @State private var showStaleShiftCloseSheet = false
    @State private var staleSessionToClose: RegisterSession? = nil
    @State private var searchQuery = ""
    @State private var showFavoritesOnly = false
    @State private var animateItems = false
    @State private var showDeliverySettings = false
    @State private var cartItemBeingEdited: UUID? = nil
    @State private var showNoteAlert = false
    @State private var noteText = ""
    @State private var itemToEditNote: UUID? = nil
    @State private var editingNoteForOrderedItem: (identity: String, status: String)? = nil

    enum ActivePaymentMethod: Identifiable {
        case cash
        case qrCode
        case creditCard

        var id: Int {
            switch self {
            case .cash: return 1
            case .qrCode: return 2
            case .creditCard: return 3
            }
        }
    }

    @State private var activePayment: ActivePaymentMethod? = nil
    @State private var completedOrderForReceipt: Order? = nil
    @State private var showCustomerPicker = false
    @State private var showHeldOrders = false
    @State private var showRefund = false
    @State private var showSplitPayment = false
    // MARK: - Error Handling
    @State private var errorMessage: String? = nil
    @State private var showingErrorBanner = false
    @State private var sentToKitchenVersion: Int = 0  // incremented after send-to-kitchen to force ordered-items re-render


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
    }

    private var sessionOrdersForDisplay: [Order] {
        guard let session = activeSession else { return [] }
        var orders = session.orders.filter { !$0.isDeleted }
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
            .filter { !$0.isDeleted }

        var groups: [String: (identity: String, name: String, qty: Int, status: String, price: Double, mods: [Modifier], notes: String)] = [:]
        for item in rawItems {
            let identity = orderedItemIdentity(item)
            let displayName = item.menuItem?.localizedName ?? item.itemName
            guard !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let mods = item.modifiers.compactMap { $0.modifier }
            let modKey = mods.map { $0.id.uuidString }.sorted().joined(separator: "-")
            let itemNotes = item.notes ?? ""
            let key = "\(identity)-\(item.status)-\(modKey)-\(itemNotes)"

            if let existing = groups[key] {
                groups[key] = (identity, displayName, existing.qty + item.quantity, item.status, existing.price + item.subtotal, existing.mods, itemNotes)
            } else {
                groups[key] = (identity, displayName, item.quantity, item.status, item.subtotal, mods, itemNotes)
            }
        }

        return groups.map { GroupedOrderedItem(id: $0.key, identity: $0.value.identity, displayName: $0.value.name, quantity: $0.value.qty, status: $0.value.status, totalPrice: $0.value.price, selectedModifiers: $0.value.mods, notes: $0.value.notes) }
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
        let items = groupedOrderedItems
        guard !items.isEmpty else { return false }
        return items.allSatisfy { $0.status == "served" || $0.status == "cancelled" }
    }

    private var sessionOrderedSubtotal: Double {
        let rawItems = sessionOrdersForDisplay.flatMap { $0.items }.filter { !$0.isDeleted }
        return rawItems.reduce(0.0) { sum, item in
            let modifierCost = item.modifiers.reduce(0.0) { $0 + $1.price }
            return sum + (item.unitPrice + modifierCost) * Double(item.quantity)
        }
    }

    private func getTaxRateAndInclusion(for item: MenuItem?) -> (rate: Double, isInclusive: Bool) {
        guard UserDefaults.standard.bool(forKey: "enable_tax") else {
            return (0.0, true)
        }
        guard let item = item else {
            let globalTaxRate = UserDefaults.standard.double(forKey: "store_tax_rate")
            let globalTaxType = UserDefaults.standard.string(forKey: "store_tax_type") ?? "inclusive"
            return (globalTaxRate, globalTaxType == "inclusive")
        }
        let priceBasis = UserDefaults.standard.string(forKey: "tax_price_basis") ?? "itemDefault"
        let globalTaxRate = UserDefaults.standard.double(forKey: "store_tax_rate")
        let globalTaxType = UserDefaults.standard.string(forKey: "store_tax_type") ?? "inclusive"
        
        switch priceBasis {
        case "forceInclusive":
            return (globalTaxRate, true)
        case "forceExclusive":
            return (globalTaxRate, false)
        case "itemDefault":
            let rate = item.taxRate
            let isInclusive = item.isTaxInclusive ?? (globalTaxType == "inclusive")
            return (rate, isInclusive)
        default:
            return (item.taxRate, item.isTaxInclusive ?? (globalTaxType == "inclusive"))
        }
    }

    private var sessionOrderedTax: Double {
        guard UserDefaults.standard.bool(forKey: "enable_tax") else {
            return 0.0
        }
        let rawItems = sessionOrdersForDisplay.flatMap { $0.items }.filter { !$0.isDeleted }
        var totalTax = 0.0
        for item in rawItems {
            let modifierCost = item.modifiers.reduce(0.0) { $0 + $1.price }
            let lineTotal = (item.unitPrice + modifierCost) * Double(item.quantity)
            let (taxRate, isInclusive) = getTaxRateAndInclusion(for: item.menuItem)
            
            if isInclusive {
                totalTax += lineTotal * (taxRate / (100.0 + taxRate))
            } else {
                totalTax += lineTotal * (taxRate / 100.0)
            }
        }
        
        let serviceChargeTaxable = UserDefaults.standard.object(forKey: "tax_service_charge_taxable") as? Bool ?? true
        let globalTaxRate = UserDefaults.standard.double(forKey: "store_tax_rate")
        let serviceChargeTax = serviceChargeTaxable ? sessionOrderedServiceCharge * (globalTaxRate / 100.0) : 0.0
        return totalTax + serviceChargeTax
    }

    private var sessionOrderedServiceCharge: Double {
        guard UserDefaults.standard.bool(forKey: "enable_service_charge") else {
            return 0.0
        }
        let serviceChargeRate = UserDefaults.standard.object(forKey: "store_service_charge_rate") as? Double ?? 10.0
        return sessionOrderedSubtotal * (serviceChargeRate / 100.0)
    }

    private var sessionOrderedDiscount: Double {
        sessionOrdersForDisplay.reduce(0.0) { $0 + $1.discount }
    }

    private var sessionOrderedTotal: Double {
        let taxEnabled = UserDefaults.standard.bool(forKey: "enable_tax")
        guard taxEnabled else {
            return max(0, sessionOrderedSubtotal + sessionOrderedServiceCharge - sessionOrderedDiscount)
        }
        let rawItems = sessionOrdersForDisplay.flatMap { $0.items }.filter { !$0.isDeleted }
        var totalAmount = 0.0
        for item in rawItems {
            let modifierCost = item.modifiers.reduce(0.0) { $0 + $1.price }
            let lineTotal = (item.unitPrice + modifierCost) * Double(item.quantity)
            let (taxRate, isInclusive) = getTaxRateAndInclusion(for: item.menuItem)
            
            if isInclusive {
                totalAmount += lineTotal
            } else {
                totalAmount += lineTotal * (1.0 + taxRate / 100.0)
            }
        }
        
        let serviceChargeTaxable = UserDefaults.standard.object(forKey: "tax_service_charge_taxable") as? Bool ?? true
        let globalTaxRate = UserDefaults.standard.double(forKey: "store_tax_rate")
        let serviceChargeTax = serviceChargeTaxable ? sessionOrderedServiceCharge * (globalTaxRate / 100.0) : 0.0
        return max(0, totalAmount + sessionOrderedServiceCharge + serviceChargeTax - sessionOrderedDiscount)
    }

    private var displaySubtotal: Double {
        viewModel.cartSubtotal + sessionOrderedSubtotal
    }

    private var displayTax: Double {
        viewModel.cartTax + sessionOrderedTax
    }

    private var displayServiceCharge: Double {
        viewModel.cartServiceCharge + sessionOrderedServiceCharge
    }

    private var displayDiscount: Double {
        viewModel.cartDiscount + sessionOrderedDiscount
    }

    private var displayTotal: Double {
        viewModel.cartTotal + sessionOrderedTotal
    }

    private var shouldShowPaymentActions: Bool {
        if enableTableSystem {
            if activeSession == nil {
                return !viewModel.cart.isEmpty
            }
            return viewModel.cart.isEmpty && isAllServed
        }
        return !viewModel.cart.isEmpty
    }

    private func completePayment(methodName: String) {
        if enableTableSystem, activeSession != nil {
            completeCheckout(methodName: methodName)
        } else {
            completeDirectCheckout(methodName: methodName)
        }
    }

    private func completeDirectCheckout(methodName: String) {
        guard let order = viewModel.processCheckout(
            tableSession: nil,
            createPayment: true,
            paymentMethod: methodName
        ) else { return }

        completedOrderForReceipt = order
        APHaptic.trigger()
    }

    private func completeCheckout(methodName: String) {
        guard let session = activeSession else { return }

        var printOrders: [Order] = []
        var ordersToPay: [Order] = []
        // 1. Create payment records for any unpaid orders in the session and mark them completed
        for order in session.orders {
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
            if order.payments.isEmpty {
                let payment = Payment(paymentMethod: methodName, amount: order.total)
                payment.order = order
                modelContext.insert(payment)
                ordersToPay.append(order)
            }
        }

        // 2. Notify backend to close table session asynchronously
        let tableNum = session.table?.tableNumber ?? ""
        Task {
            do {
                try await NetworkManager.shared.closeTableSession(tableNumber: tableNum)
                await SyncEngine.shared.syncAll(modelContext: modelContext)
            } catch {
                await MainActor.run {
                    showError(L.Errors.syncError.t)
                }
            }
        }

        // 3. Mark session inactive and set table status to cleaning
        session.isActive = false
        session.endedAt = Date()
        session.isSynced = false
        session.updatedAt = Date()

        if let table = session.table {
            table.status = "cleaning"
            table.isSynced = false
            table.updatedAt = Date()
        }

        modelContext.saveWithLogging(label: #function)

        if let firstOrder = ordersToPay.first {
            completedOrderForReceipt = firstOrder
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

        // 4. Return to Table view by clearing activeSession
        activeSession = nil
        selectedTab = .tables
        APHaptic.trigger()
    }

    private func completeSplitCheckout(entries: [SplitPaymentEntry]) {
        if !enableTableSystem || activeSession == nil {
            completeDirectSplitCheckout(entries: entries)
            return
        }

        guard let session = activeSession else { return }

        let unpaidOrders = session.orders.filter { $0.payments.isEmpty }
        guard !unpaidOrders.isEmpty else { return }

        for order in session.orders {
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

        if let primaryOrder = unpaidOrders.first {
            for entry in entries {
                let payment = Payment(paymentMethod: entry.method, amount: entry.amount)
                payment.order = primaryOrder
                modelContext.insert(payment)
            }
        }

        let tableNum = session.table?.tableNumber ?? ""
        Task {
            do {
                try await NetworkManager.shared.closeTableSession(tableNumber: tableNum)
                await SyncEngine.shared.syncAll(modelContext: modelContext)
            } catch {
                await MainActor.run {
                    showError(L.Errors.syncError.t)
                }
            }
        }

        session.isActive = false
        session.endedAt = Date()
        session.isSynced = false
        session.updatedAt = Date()

        if let table = session.table {
            table.status = "cleaning"
            table.isSynced = false
            table.updatedAt = Date()
        }

        modelContext.saveWithLogging(label: #function)

        if let firstOrder = unpaidOrders.first {
            completedOrderForReceipt = firstOrder
        }

        activeSession = nil
        selectedTab = .tables
        APHaptic.trigger()
    }

    private func completeDirectSplitCheckout(entries: [SplitPaymentEntry]) {
        guard let order = viewModel.processCheckout(tableSession: nil, createPayment: false, dispatchPrint: false) else { return }

        for entry in entries {
            let payment = Payment(paymentMethod: entry.method, amount: entry.amount)
            payment.order = order
            modelContext.insert(payment)
        }

        order.isSynced = false
        order.updatedAt = Date()
        modelContext.saveWithLogging(label: #function)

        Task {
            await SyncEngine.shared.syncAll(modelContext: modelContext)
            // Split checkout path — this is a payment confirmation (not send-to-kitchen)
            await PrintService.shared.dispatchReceipt(order)
        }

        completedOrderForReceipt = order
        APHaptic.trigger()
    }

    private var hasPendingSelfOrders: Bool {
        sessionOrdersForDisplay.contains { $0.status == "pending" && !$0.isDeleted }
    }

    private func approvePendingSelfOrders() {
        guard let session = activeSession else { return }
        
        let pendingOrders = session.orders.filter { $0.status == "pending" && !$0.isDeleted }
        for order in pendingOrders {
            order.status = "preparing"
            for item in order.items {
                if !item.isDeleted {
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
            await SyncEngine.shared.syncAll(modelContext: modelContext)
        }
    }

    private func deleteOrderedItem(_ orderedItem: GroupedOrderedItem) {
        let targetIdentity = orderedItem.identity
        let targetStatus = orderedItem.status
        for order in sessionOrdersForDisplay {
            if !order.isDeleted {
                for item in order.items {
                    if !item.isDeleted {
                        let itemStatus = item.status
                        if orderedItemIdentity(item) == targetIdentity && itemStatus == targetStatus {
                            item.isDeleted = true
                            item.isSynced = false
                            item.updatedAt = Date()
                        }
                    }
                }
            }
        }
        modelContext.saveWithLogging(label: #function)
        viewModel.syncFromSession(activeSession)
        APHaptic.trigger()
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
        cartItemBeingEdited = cartItem.id
        viewModel.selectedItemForCustomization = cartItem.item
        APHaptic.trigger()
    }

    private func editNoteForCartItemAction(_ cartItem: CartItem) {
        noteText = cartItem.notes
        itemToEditNote = cartItem.id
        showNoteAlert = true
        APHaptic.trigger()
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

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            if menuItems.isEmpty {
                emptyState
            } else if enableTableSystem && activeSession == nil {
                tableRequiredState
            } else {
                VStack(spacing: 0) {
                    if let activeShift = activeRegisterSessions.first, isShiftStale(activeShift) {
                        staleShiftWarningBanner(activeShift)
                    }
                    
                    HStack(spacing: 0) {
                        menuPanel
                        cartPanel
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
        .navigationBarHidden(true)
        .sheet(item: $viewModel.selectedItemForCustomization) { item in
            ModifierCustomizerView(item: item) { modifiers in
                if let editId = cartItemBeingEdited,
                   let idx = viewModel.cart.firstIndex(where: { $0.id == editId }) {
                    viewModel.cart[idx] = CartItem(item: item, selectedModifiers: modifiers, quantity: viewModel.cart[idx].quantity, notes: viewModel.cart[idx].notes)
                    cartItemBeingEdited = nil
                } else {
                    viewModel.addToCart(item, modifiers: modifiers)
                }
            }
        }
        .sheet(isPresented: $showDeliverySettings) {
            if let brand = viewModel.deliveryBrand {
                @Bindable var bindableVM = viewModel
                DeliverySettingsSheet(
                    gp: $bindableVM.deliveryGP,
                    adFee: $bindableVM.deliveryAdFee,
                    adFeeIsPct: $bindableVM.deliveryAdFeeIsPct,
                    otherFee: $bindableVM.deliveryOtherFee,
                    brandName: brand
                )
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
                    viewModel.syncFromSession(activeSession)
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
        .sheet(item: $activePayment) { paymentMethod in
            switch paymentMethod {
            case .cash:
                CashPaymentModalView(totalAmount: displayTotal) { cashReceived in
                    completePayment(methodName: "Cash")
                }
            case .qrCode:
                QRPaymentModalView(totalAmount: displayTotal) {
                    completePayment(methodName: "QR PromptPay")
                }
            case .creditCard:
                CreditCardPaymentModalView(totalAmount: displayTotal) {
                    completePayment(methodName: "Credit Card")
                }
            }
        }
        .sheet(item: $completedOrderForReceipt) { order in
            ReceiptView(order: order)
        }
        .sheet(isPresented: $showCustomerPicker) {
            CustomerPickerView { customer in
                viewModel.selectedCustomer = customer
            }
        }
        .sheet(isPresented: $showHeldOrders) {
            HeldOrdersView { order in
                viewModel.recallHeldOrder(order)
            }
        }
        .sheet(isPresented: $showRefund) {
            RefundView()
        }
        .fullScreenCover(isPresented: $showStartShiftSheet) {
            StartShiftRegisterSheet(onCancel: {
                selectedTab = .tables
            })
        }
        .sheet(item: $staleSessionToClose) { session in
            ForceCloseStaleShiftSheet(session: session, onComplete: {
                staleSessionToClose = nil
                showStartShiftSheet = true
            }, onCancel: {
                // Stay on current page; warning banner remains visible
            })
        }
        .sheet(isPresented: $showSplitPayment) {
            SplitPaymentView(totalAmount: displayTotal) { entries in
                completeSplitCheckout(entries: entries)
            }
        }
        .onAppear {
            viewModel.modelContext = modelContext
            viewModel.syncFromSession(activeSession)
            withAnimation(.spring(response: 0.6, dampingFraction: 0.75, blendDuration: 0)) {
                animateItems = true
            }
            
            // Prompt to start a new shift only if no active shift exists
            if activeRegisterSessions.isEmpty {
                showStartShiftSheet = true
            }
        }
        .onDisappear {
            animateItems = false
        }
        .onChange(of: activeSession) { _, newSession in
            viewModel.syncFromSession(newSession)
            // Reset send-to-kitchen counter so the empty-state guard is lifted for the new session
            sentToKitchenVersion = 0
            animateItems = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.75, blendDuration: 0)) {
                    animateItems = true
                }
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

            Button(action: { viewModel.seedSampleMenu() }) {
                Label("seed_mock_menu_btn".t, systemImage: "plus.square.fill")
                    .apGradientButton()
            }
            .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Menu Panel (Left)

    private var menuPanel: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: APSpacing.sm) {
                    // Back / Sidebar Button
                    Button(action: {
                        if enableTableSystem {
                            activeSession = nil
                            selectedTab = .tables
                        } else {
                            withAnimation {
                                if columnVisibility == .all {
                                    columnVisibility = .detailOnly
                                } else {
                                    columnVisibility = .all
                                }
                            }
                        }
                        APHaptic.trigger()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: enableTableSystem ? "chevron.left" : "sidebar.left")
                                .font(.system(size: 16, weight: .bold))
                            if enableTableSystem {
                                Text("tab_tables".t)
                                    .font(.system(size: 13, weight: .semibold))
                            }
                        }
                        .foregroundColor(.appAccent)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .background(Color.appSurfaceHigh)
                        .cornerRadius(APRadius.md)
                        .overlay(
                            RoundedRectangle(cornerRadius: APRadius.md)
                                .stroke(Color.appBorderSubtle, lineWidth: 1)
                        )
                    }

                    // Refunds Button
                    Button(action: {
                        if sessionManager.can(.refundCreate) {
                            showRefund = true
                        }
                        APHaptic.trigger()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 14, weight: .bold))
                            Text("pos_refund".t)
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(.appAccent)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .background(Color.appSurfaceHigh)
                        .cornerRadius(APRadius.md)
                        .overlay(
                            RoundedRectangle(cornerRadius: APRadius.md)
                                .stroke(sessionManager.can(.refundCreate) ? Color.appBorderSubtle : Color.appRose.opacity(0.35), lineWidth: 1)
                        )
                    }
                    .disabled(!sessionManager.can(.refundCreate))
                    .opacity(sessionManager.can(.refundCreate) ? 1 : 0.45)

                    // Search Bar container
                    HStack(spacing: APSpacing.sm) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.textSecondary)
                        TextField("Search by name, SKU, or scan barcode...", text: $searchQuery)
                            .font(.subheadline)
                            .foregroundColor(.textPrimary)
                            .tint(.appAccent)
                            .submitLabel(.search)
                            .onSubmit {
                                let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !query.isEmpty,
                                   let matchedItem = menuItems.first(where: {
                                       $0.barcode?.lowercased() == query.lowercased() ||
                                       $0.sku?.lowercased() == query.lowercased()
                                   }) {
                                    viewModel.selectItem(matchedItem)
                                    searchQuery = ""
                                }
                            }
                        if !searchQuery.isEmpty {
                            Button(action: { searchQuery = "" }) {
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
                }
                .padding(.horizontal, APSpacing.md)
                .padding(.top, APSpacing.md)

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
                                .apChip(selected: !showFavoritesOnly && viewModel.selectedCategory == nil)
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
                            .apChip(selected: showFavoritesOnly)
                        }

                        ForEach(categories) { cat in
                            Button(action: {
                                withAnimation {
                                    viewModel.selectedCategory = cat
                                    showFavoritesOnly = false
                                }
                            }) {
                                Text(cat.name)
                                    .apChip(selected: !showFavoritesOnly && viewModel.selectedCategory?.id == cat.id)
                            }
                        }
                    }
                    .padding(.horizontal, APSpacing.md)
                    .padding(.vertical, APSpacing.md)
                }
                .background(Color.appBackground)
            }
            .offset(y: animateItems ? 0 : -60)
            .opacity(animateItems ? 1 : 0)

            Divider().background(Color.appDivider)

            // C-4 FIX: Use POSMenuGridView which owns its own @Query for categories + menuItems.
            // This decouples cart updates from menu grid re-renders and vice versa.
            POSMenuGridView(
                searchQuery:       $searchQuery,
                showFavoritesOnly: $showFavoritesOnly,
                animateItems:      $animateItems,
                viewModel:         viewModel
            )
        }
        .frame(maxWidth: .infinity)
        .background(Color.appBackground)
    }

    // MARK: - Cart Panel (Right)

    private var cartPanel: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                // Header (Compact & Combined)
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("pos_current_cart".t)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.textPrimary)
                        if !viewModel.cart.isEmpty {
                            Text(LocalizationManager.shared.t("items_count_template", viewModel.cart.count))
                                .font(.system(size: 11))
                                .foregroundColor(.textSecondary)
                        }
                    }

                    Spacer()

                    // Order Type Selector (Compact)
                    HStack(spacing: 2) {
                        Button(action: {
                            withAnimation { viewModel.updateOrderType("dine_in") }
                        }) {
                            Text("pos_dine_in".t)
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(viewModel.selectedOrderType == "dine_in" ? Color.appAccent : Color.clear)
                                .foregroundColor(viewModel.selectedOrderType == "dine_in" ? .white : .textSecondary)
                                .cornerRadius(3)
                        }
                        Button(action: {
                            withAnimation { viewModel.updateOrderType("take_out") }
                        }) {
                            Text("pos_take_out".t)
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(viewModel.selectedOrderType == "take_out" ? Color.appAccent : Color.clear)
                                .foregroundColor(viewModel.selectedOrderType == "take_out" ? .white : .textSecondary)
                                .cornerRadius(3)
                        }
                        Button(action: {
                            withAnimation {
                                viewModel.updateOrderType("delivery")
                                if viewModel.deliveryBrand == nil {
                                    viewModel.deliveryBrand = "GrabFood"
                                }
                            }
                        }) {
                            Text("pos_delivery".t)
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(viewModel.selectedOrderType == "delivery" ? Color.appAccent : Color.clear)
                                .foregroundColor(viewModel.selectedOrderType == "delivery" ? .white : .textSecondary)
                                .cornerRadius(3)
                        }
                    }
                    .padding(1)
                    .background(Color.appSurfaceHigh)
                    .cornerRadius(4)

                    if !viewModel.cart.isEmpty {
                        HStack(spacing: 8) {
                            Button(action: {
                                viewModel.holdCurrentCart()
                            }) {
                                Text("pos_hold".t)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.appTeal)
                                    .padding(.leading, 8)
                            }

                            Button(action: {
                                withAnimation { viewModel.cart.removeAll() }
                                APHaptic.trigger()
                            }) {
                                Text("pos_clear".t)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.appRose)
                                    .padding(.leading, 8)
                            }
                        }
                    } else {
                        Button(action: {
                            showHeldOrders = true
                            APHaptic.trigger()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.uturn.backward.circle")
                                    .font(.system(size: 11))
                                Text("pos_recall".t)
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .foregroundColor(.appAccent)
                        }
                    }
                }
                .padding(.horizontal, APSpacing.md)
                .padding(.vertical, 10)
                .background(Color.appSurface)

                if viewModel.selectedOrderType == "delivery" {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(["GrabFood", "LINE MAN", "ShopeeFood", "Foodpanda", "Robinhood"], id: \.self) { brand in
                                let isSelected = viewModel.deliveryBrand == brand
                                let brandColor: Color = {
                                    switch brand {
                                    case "GrabFood": return Color(hex: "00B14F")
                                    case "LINE MAN": return Color(hex: "00C25B")
                                    case "ShopeeFood": return Color(hex: "F04D23")
                                    case "Foodpanda": return Color(hex: "D6125D")
                                    case "Robinhood": return Color(hex: "7E22CE")
                                    default: return Color.appAccent
                                    }
                                }()

                                Button(action: {
                                    withAnimation {
                                        viewModel.deliveryBrand = brand
                                    }
                                    APHaptic.trigger()
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "car.fill")
                                            .font(.system(size: 10))
                                        Text(brand)
                                            .font(.system(size: 10, weight: .bold))
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(isSelected ? brandColor.opacity(0.15) : Color.appSurfaceHigh)
                                    .foregroundColor(isSelected ? brandColor : .textSecondary)
                                    .cornerRadius(6)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(isSelected ? brandColor : Color.appBorderSubtle, lineWidth: 1.5)
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, APSpacing.md)
                        .padding(.vertical, 6)
                    }
                    .background(Color.appSurface)

                    // Button to edit settings (GP, Fees)
                    HStack {
                        Spacer()
                        Button(action: {
                            showDeliverySettings = true
                            APHaptic.trigger()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "slider.horizontal.3")
                                    .font(.system(size: 10))
                                Text(LocalizationManager.shared.t("configure_fees_template", viewModel.deliveryBrand ?? "Platform"))
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundColor(.appAccent)
                        }
                    }
                    .padding(.horizontal, APSpacing.md)
                    .padding(.bottom, 6)
                    .background(Color.appSurface)

                    Divider().background(Color.appDivider)
                }

                // Metadata Grid Card (2-row compact version)
                VStack(spacing: 6) {
                    // Row 1: Bill & Queue, Table & Stepper, Cashier
                    HStack(alignment: .center) {
                        // Column 1: Bill & Queue
                        VStack(alignment: .leading, spacing: 2) {
                            Text("pos_bill_no".t)
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.textTertiary)
                            Text(viewModel.currentBillNumber)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.textPrimary)
                            Text(viewModel.currentQueueNumber)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.appTeal)
                        }

                        Spacer()

                        // Column 2: Table & Guests (Pax)
                        VStack(alignment: .center, spacing: 2) {
                            if enableTableSystem, let session = activeSession {
                                HStack(spacing: 3) {
                                    Text(LocalizationManager.shared.t("table_number_template", session.table?.tableNumber ?? "N/A"))
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.textPrimary)
                                    Button(action: {
                                        activeSession = nil
                                        selectedTab = .tables
                                    }) {
                                        Image(systemName: "pencil.circle.fill")
                                            .font(.system(size: 12))
                                            .foregroundColor(.appAccent)
                                    }
                                }
                            } else {
                                Picker("Table", selection: $viewModel.selectedTableNumber) {
                                    ForEach(1...10, id: \.self) { Text("\($0)").tag("\($0)") }
                                }
                                .pickerStyle(.menu)
                                .tint(.textPrimary)
                                .font(.system(size: 11, weight: .bold))
                            }

                            // Stepper
                            HStack(spacing: 4) {
                                Button(action: {
                                    if viewModel.guestCount > 1 {
                                        viewModel.updateGuestCount(viewModel.guestCount - 1, session: activeSession)
                                    }
                                }) {
                                    Image(systemName: "minus.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(.textSecondary)
                                }
                                Text(LocalizationManager.shared.t("pax_count_template", viewModel.guestCount))
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.textPrimary)
                                Button(action: {
                                    viewModel.updateGuestCount(viewModel.guestCount + 1, session: activeSession)
                                }) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(.textSecondary)
                                }
                            }
                        }

                        Spacer()

                        // Column 3: Cashier
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("pos_cashier".t)
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.textTertiary)
                            Text(viewModel.cashierName)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.textPrimary)
                        }
                    }

                    Divider().background(Color.appDivider)

                    // Row 2: Date & Time
                    HStack {
                        Text(viewModel.currentOrderDateString)
                            .font(.system(size: 9))
                            .foregroundColor(.textSecondary)
                        Spacer()
                    }

                    Divider().background(Color.appDivider)

                    // Row 3: Customer Selector
                    HStack {
                        if let customer = viewModel.selectedCustomer {
                            HStack(spacing: 6) {
                                Image(systemName: "person.crop.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.appAccent)
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
                                    .foregroundColor(.appAccent)
                            }
                            Spacer()
                        }
                    }
                    .padding(.top, 2)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.appSurfaceHigh)
                .cornerRadius(APRadius.sm)
                .overlay(
                    RoundedRectangle(cornerRadius: APRadius.sm)
                        .stroke(Color.appBorderSubtle, lineWidth: 1)
                )
                .padding(.horizontal, APSpacing.md)
                .padding(.vertical, APSpacing.sm)
                .background(Color.appSurface)

                Divider().background(Color.appDivider)

                // Payment Ready Banner (if applicable)
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

                // Cart list / empty
                // Read sentToKitchenVersion HERE (outside the if/else) so SwiftUI tracks
                // this state variable at the correct scope and re-evaluates the entire
                // condition when it is incremented after a send-to-kitchen action.
                let _ = sentToKitchenVersion
                if viewModel.cart.isEmpty && groupedOrderedItems.isEmpty && sentToKitchenVersion == 0 {
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
                    .background(Color.appBackground)
                } else {
                    ScrollViewReader { scrollViewProxy in
                        List {
                            // 0. Pending Self-Orders Approval Banner
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
                                            Text("อนุมัติ")
                                                .font(.system(size: 11, weight: .bold))
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 5)
                                                .background(Color.white.opacity(0.2))
                                                .cornerRadius(6)
                                                .foregroundColor(.white)
                                        }
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 12)
                                        .background(
                                            LinearGradient(
                                                gradient: Gradient(colors: [Color.appAmber, Color.orange]),
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .cornerRadius(8)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            }

                            // 1. Already Ordered Items
                            if !groupedOrderedItems.isEmpty {
                                ForEach(groupedOrderedItems) { orderedItem in
                                    OrderedItemRow(groupedItem: orderedItem)
                                        .listRowBackground(Color.clear)
                                        .listRowSeparator(.hidden)
                                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                            Button(role: .destructive) {
                                                deleteOrderedItem(orderedItem)
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

                            // 2. New Draft Items
                            if !viewModel.cart.isEmpty {
                                ForEach(viewModel.cart) { cartItem in
                                    CartItemRow(cartItem: cartItem,
                                                onIncrease: { viewModel.increaseQty(cartItem) },
                                                onDecrease: { viewModel.decreaseQty(cartItem) })
                                        .listRowBackground(Color.clear)
                                        .listRowSeparator(.hidden)
                                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
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
                        .background(Color.appBackground)
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
            .offset(x: animateItems ? 0 : 80)
            .opacity(animateItems ? 1 : 0)

            VStack(spacing: 0) {
                // Financial breakdown
                VStack(spacing: 4) {
                    financeRow(label: "pos_subtotal".t, value: displaySubtotal)
                    financeRow(label: "pos_vat".t + " 7%", value: displayTax)
                    financeRow(label: "pos_service_charge".t + " 10%", value: displayServiceCharge)
                    if displayDiscount > 0 {
                        financeRow(label: "pos_discount".t, value: -displayDiscount)
                    }

                    Divider().background(Color.appDivider).padding(.vertical, 2)

                    HStack {
                        Text("pos_total".t)
                            .font(.subheadline).fontWeight(.bold)
                            .foregroundColor(.textPrimary)
                        Spacer()
                        Text(String(format: "฿%.2f", displayTotal))
                            .font(.headline).fontWeight(.black)
                            .foregroundStyle(APGradient.accent)
                    }
                }
                .padding(.horizontal, APSpacing.md)
                .padding(.vertical, APSpacing.sm)
                .background(Color.appSurface)

                // Checkout / Payment CTAs
                if shouldShowPaymentActions {
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            // 1. Cash Button
                            if cashEnabled {
                                Button(action: { verifyShiftAndExecute { activePayment = .cash } }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "banknote.fill")
                                            .font(.system(size: 13))
                                        Text("pos_cash".t)
                                            .font(.system(size: 13, weight: .bold))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color.appSurfaceHigh)
                                    .foregroundColor(.textPrimary)
                                    .cornerRadius(APRadius.md)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: APRadius.md)
                                            .stroke(Color.appBorderSubtle, lineWidth: 1)
                                    )
                                }
                            }

                            // 2. QR Code Button
                            if qrEnabled {
                                Button(action: { verifyShiftAndExecute { activePayment = .qrCode } }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "qrcode")
                                            .font(.system(size: 13))
                                        Text("pos_qr_code".t)
                                            .font(.system(size: 13, weight: .bold))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color.appTeal)
                                    .foregroundColor(.white)
                                    .cornerRadius(APRadius.md)
                                    .shadow(color: Color.appTeal.opacity(0.3), radius: 8, x: 0, y: 0)
                                }
                            }
                        }

                        HStack(spacing: 8) {
                            // 3. Credit Card Button
                            if cardEnabled {
                                Button(action: { verifyShiftAndExecute { activePayment = .creditCard } }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "creditcard.fill")
                                            .font(.system(size: 13))
                                        Text("pos_card".t)
                                            .font(.system(size: 13, weight: .bold))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color.appSurfaceHigh)
                                    .foregroundColor(.textPrimary)
                                    .cornerRadius(APRadius.md)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: APRadius.md)
                                            .stroke(Color.appBorderSubtle, lineWidth: 1)
                                    )
                                }
                            }

                            // 4. Split Pay Button
                            Button(action: { verifyShiftAndExecute { showSplitPayment = true } }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "square.split.2x2.fill")
                                        .font(.system(size: 13))
                                    Text("pos_split_pay".t)
                                        .font(.system(size: 13, weight: .bold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(APGradient.accent)
                                .foregroundColor(.white)
                                .cornerRadius(APRadius.md)
                                .shadow(color: Color.appAccent.opacity(0.3), radius: 8, x: 0, y: 0)
                            }
                        }
                    }
                    .padding(.horizontal, APSpacing.md)
                    .padding(.bottom, APSpacing.md)
                    .padding(.top, APSpacing.xs)
                    .background(Color.appSurface)
                } else {
                    Button(action: {
                        verifyShiftAndExecute {
                            let order = viewModel.processCheckout(tableSession: enableTableSystem ? activeSession : nil)
                            // Increment version so the cart panel re-evaluates groupedOrderedItems
                            // immediately after the cart is cleared (SwiftData relationship change
                            // may not propagate via @Binding alone when mutated from the ViewModel).
                            if enableTableSystem && activeSession != nil { sentToKitchenVersion += 1 }
                            if !enableTableSystem, let order {
                                completedOrderForReceipt = order
                            }
                        }
                    }) {
                        let btnLabel = viewModel.cart.isEmpty ? "Send to Kitchen" : "Send to Kitchen (฿\(String(format: "%.2f", viewModel.cartTotal)))"
                        Label(btnLabel, systemImage: "flame.fill")
                            .apGradientButton(
                                gradient: viewModel.cart.isEmpty ? LinearGradient(colors: [Color.appSurface], startPoint: .leading, endPoint: .trailing) : APGradient.accent,
                                shadow: APShadow.glow,
                                disabled: viewModel.cart.isEmpty
                            )
                    }
                    .disabled(viewModel.cart.isEmpty)
                    .padding(.horizontal, APSpacing.md)
                    .padding(.bottom, APSpacing.md)
                    .padding(.top, APSpacing.xs)
                    .background(Color.appSurface)
                }
            }
            .offset(y: animateItems ? 0 : 60)
            .opacity(animateItems ? 1 : 0)
        }
        .frame(width: 400)
        .background(Color.appSurface)
        .overlay(
            Rectangle()
                .fill(Color.appDivider)
                .frame(width: 1),
            alignment: .leading
        )
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
        }
    }

    private func verifyShiftAndExecute(_ action: @escaping () -> Void) {
        if activeRegisterSessions.isEmpty {
            showStartShiftSheet = true
            APHaptic.trigger()
        } else if let activeShift = activeRegisterSessions.first, isShiftStale(activeShift) {
            staleSessionToClose = activeShift
            APHaptic.trigger()
        } else {
            action()
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
}

// MARK: - POSMenuGridView (C-4 FIX)
// ─────────────────────────────────────────────────────────────────────────────
// Isolated child view that owns its own @Query for categories + menuItems.
// This prevents cart updates (via POSViewModel) from re-rendering the menu grid
// and prevents menu sync events from re-rendering the cart panel.
//
// Before: POSView had 3 @Query → any cart event rebuilt the entire 2,300-line view
// After:  menuItems/categories @Query isolated here → cart ↔ menu renders decouple
// ─────────────────────────────────────────────────────────────────────────────

struct POSMenuGridView: View {
    @Query(sort: \Category.name)  private var categories:  [Category]
    @Query(sort: \MenuItem.name)  private var menuItems:   [MenuItem]

    @Binding var searchQuery:       String
    @Binding var showFavoritesOnly: Bool
    @Binding var animateItems:      Bool
    let viewModel:                  POSViewModel   // @Observable — fine; only cart changes trigger this child

    var body: some View {
        let filtered = menuItems.filter { item in
            let matchesCategory = viewModel.selectedCategory == nil
                || item.category?.id == viewModel.selectedCategory?.id
            let matchesFavorite = !showFavoritesOnly || (item.isFavorite ?? false)
            let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesSearch = query.isEmpty
                || item.name.localizedCaseInsensitiveContains(query)
                || (item.sku ?? "").localizedCaseInsensitiveContains(query)
                || (item.barcode ?? "").localizedCaseInsensitiveContains(query)
            return matchesCategory && matchesFavorite && matchesSearch
        }

        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: APSpacing.md)],
                spacing: APSpacing.md
            ) {
                ForEach(filtered) { item in
                    let count = viewModel.cart
                        .filter { $0.item.id == item.id }
                        .reduce(0) { $0 + $1.quantity }
                    MenuItemCard(item: item, countInCart: count) {
                        viewModel.selectItem(item)
                    }
                }
            }
            .padding(APSpacing.md)
        }
        .offset(x: animateItems ? 0 : -80)
        .opacity(animateItems ? 1 : 0)
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: animateItems)
    }
}


// MARK: - Menu Item Card Button Style

private struct MenuItemButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Menu Item Card

private struct MenuItemCard: View {
    let item:     MenuItem
    let countInCart: Int
    let onSelect: () -> Void
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var lm: LocalizationManager
    @State private var isGlowActive = false

    var body: some View {
        Button(action: {
            if item.isAvailable {
                onSelect()

                // Trigger tactile green flash shadow animation
                withAnimation(.easeOut(duration: 0.12)) {
                    isGlowActive = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.easeIn(duration: 0.25)) {
                        isGlowActive = false
                    }
                }
            } else {
                APHaptic.trigger()
            }
        }) {
            VStack(alignment: .leading, spacing: 0) {
                // Product Image Container with overlaid badges
                let isDrink = item.category?.name.localizedCaseInsensitiveContains("drink") == true || item.category?.name.localizedCaseInsensitiveContains("bever") == true || item.name.localizedCaseInsensitiveContains("iced") == true
                let fallbackIcon = isDrink ? "wineglass.fill" : "fork.knife"
                let hexColor = item.colorHex ?? "1E1B4B"
                let fallbackColor = Color(hex: hexColor)

                ZStack(alignment: .topLeading) {
                    RemoteImageView(
                        imageUrl: item.imageUrl,
                        imageData: item.imageData,
                        fallbackColor: fallbackColor,
                        fallbackIcon: fallbackIcon
                    )
                    .frame(height: 95)
                    .frame(maxWidth: .infinity)
                    .clipped()

                    // Badges overlay
                    HStack(spacing: 4) {
                        // Bestseller Badge
                        if item.isBestseller ?? false {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.white)
                                .padding(4)
                                .background(Color.orange)
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.3), radius: 1.5)
                        }

                        Spacer()

                        // Favorite Badge
                        if item.isFavorite ?? false {
                            Image(systemName: "star.fill")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.white)
                                .padding(4)
                                .background(Color.appAmber)
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.3), radius: 1.5)
                        }
                    }
                    .padding(6)
                }
                .frame(height: 95)
                .contentShape(Rectangle())

                VStack(alignment: .leading, spacing: 6) {
                    Text(item.localizedName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(height: 34, alignment: .topLeading)

                    HStack(alignment: .bottom) {
                        Text(String(format: "฿%.0f", item.price))
                            .font(.system(size: 14, weight: .black))
                            .foregroundStyle(APGradient.accent)
                        Spacer()
                        if !item.recipes.isEmpty {
                            Image(systemName: "leaf.fill")
                                .font(.caption2)
                                .foregroundColor(.appTeal)
                        }
                    }
                }
                .padding(10)
            }
            .background(Color.appSurface)
            .clipShape(RoundedRectangle(cornerRadius: APRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: APRadius.md, style: .continuous)
                    .stroke(isGlowActive ? Color.appTeal : Color.appBorderSubtle, lineWidth: isGlowActive ? 2 : 1)
            )
            .opacity(item.isAvailable ? 1.0 : 0.6)
            .overlay(
                Group {
                    if !item.isAvailable {
                        Color.black.opacity(0.15)
                            .overlay(
                                Text("pos_out_of_stock".t)
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.appRose.opacity(0.85))
                                    .cornerRadius(4)
                            )
                    }
                }
            )
            .shadow(color: isGlowActive ? Color.appTeal.opacity(0.9) : Color.black.opacity(0.12), radius: isGlowActive ? 16 : 6, x: 0, y: isGlowActive ? 8 : 3)
        }
        .buttonStyle(MenuItemButtonStyle())
        .overlay(
            Group {
                if countInCart > 0 {
                    VStack {
                        HStack {
                            Spacer()
                            Text("\(countInCart)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.appAccent)
                                .clipShape(Capsule())
                                .shadow(color: .black.opacity(0.3), radius: 3)
                                .offset(x: 6, y: -6)
                        }
                        Spacer()
                    }
                }
            }
            .allowsHitTesting(false)
        )
        .contextMenu {
            Button {
                item.isAvailable.toggle()
                item.updatedAt = Date()
                modelContext.saveWithLogging(label: #function)
            } label: {
                Label(item.isAvailable ? "ทำเครื่องหมาย: ของหมด" : "ทำเครื่องหมาย: พร้อมขาย", systemImage: item.isAvailable ? "slash.circle" : "checkmark.circle")
            }

            Button {
                item.isFavorite = !(item.isFavorite ?? false)
                item.updatedAt = Date()
                modelContext.saveWithLogging(label: #function)
            } label: {
                Label((item.isFavorite ?? false) ? "เอาออกจากรายการโปรด" : "เพิ่มเป็นรายการโปรด", systemImage: (item.isFavorite ?? false) ? "star.slash" : "star.fill")
            }

            Button {
                item.isBestseller = !(item.isBestseller ?? false)
                item.updatedAt = Date()
                modelContext.saveWithLogging(label: #function)
            } label: {
                Label((item.isBestseller ?? false) ? "เอาออกจากสินค้าขายดี" : "เพิ่มเป็นสินค้าขายดี", systemImage: (item.isBestseller ?? false) ? "flame.fill" : "flame")
            }
        }
    }
}

// MARK: - Cart Item Row

private struct CartItemRow: View {
    let cartItem:   CartItem
    let onIncrease: () -> Void
    let onDecrease: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Row 1: Name and Draft Badge
            HStack(alignment: .top) {
                Text(cartItem.item.localizedName)
                    .font(.footnote)
                    .fontWeight(.semibold)
                    .foregroundColor(.textPrimary)
                    .lineLimit(nil)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 12)

                Text("pos_pending_confirmation".t)
                    .font(.system(size: 8, weight: .bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.appAccent.opacity(0.12))
                    .foregroundColor(.appAccent)
                    .cornerRadius(3)
            }

            // Row 2: Modifiers (if present)
            if !cartItem.selectedModifiers.isEmpty {
                Text(cartItem.selectedModifiers.map { $0.name }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            }

            if !cartItem.notes.isEmpty {
                Text(LocalizationManager.shared.t("note_label_template", cartItem.notes))
                    .font(.caption2)
                    .foregroundColor(.appAmber)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.appAmber.opacity(0.12))
                    .cornerRadius(4)
            }

            // Row 3: Price and Stepper
            HStack(alignment: .center) {
                Text(String(format: "฿%.0f", cartItem.totalPrice))
                    .font(.subheadline).fontWeight(.bold)
                    .foregroundColor(.textPrimary)

                Spacer()

                HStack(spacing: APSpacing.sm) {
                    Button(action: onDecrease) {
                        Image(systemName: "minus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(APGradient.destructive)
                    }
                    Text("\(cartItem.quantity)")
                        .font(.headline).fontWeight(.bold)
                        .foregroundColor(.textPrimary)
                        .frame(minWidth: 24)
                    Button(action: onIncrease) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(APGradient.accent)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, APSpacing.md)
        .padding(.vertical, 10)
        .background(Color.appSurface)
        .cornerRadius(APRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: APRadius.md)
                .stroke(Color.appBorderSubtle, lineWidth: 1)
        )
    }
}

// MARK: - Ordered Item Row

private struct OrderedItemRow: View {
    let groupedItem: POSView.GroupedOrderedItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Row 1: Name and Badge
            HStack(alignment: .top) {
                Text(groupedItem.displayName)
                    .font(.footnote)
                    .fontWeight(.semibold)
                    .foregroundColor(groupedItem.status == "cancelled" ? .textTertiary : .textPrimary)
                    .strikethrough(groupedItem.status == "cancelled")
                    .lineLimit(nil)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 12)

                statusBadge(status: groupedItem.status)
            }

            // Row 2: Modifiers (if present)
            if !groupedItem.selectedModifiers.isEmpty {
                Text(groupedItem.selectedModifiers.map { $0.name }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            }

            if !groupedItem.notes.isEmpty {
                Text(LocalizationManager.shared.t("note_label_template", groupedItem.notes))
                    .font(.caption2)
                    .foregroundColor(.appAmber)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.appAmber.opacity(0.12))
                    .cornerRadius(4)
            }

            // Row 3: Price and Quantity
            HStack(alignment: .center) {
                Text(String(format: "฿%.0f", groupedItem.totalPrice))
                    .font(.subheadline).fontWeight(.bold)
                    .foregroundColor(groupedItem.status == "cancelled" ? .textTertiary : .textPrimary)

                Spacer()

                Text("× \(groupedItem.quantity)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.appSurfaceHigh)
                    .cornerRadius(APRadius.sm)
            }
        }
        .padding(.horizontal, APSpacing.md)
        .padding(.vertical, 10)
        .background(Color.appSurface.opacity(0.6))
        .cornerRadius(APRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: APRadius.md)
                .stroke(Color.appBorderSubtle.opacity(0.5), lineWidth: 1)
        )
        .opacity(groupedItem.status == "cancelled" ? 0.5 : 0.85)
    }

    private func statusBadge(status: String) -> some View {
        let text: String
        let icon: String
        let color: Color

        switch status.lowercased() {
        case "cooking", "preparing":
            text = "กำลังปรุง"
            icon = "🍳"
            color = .appAmber
        case "ready":
            text = "พร้อมเสิร์ฟ"
            icon = "🛎️"
            color = .appTeal
        case "served":
            text = "เสิร์ฟแล้ว"
            icon = "textSecondary"
            // Wait, "textSecondary" is not a direct static color. We should use Color.textSecondary.
            return HStack(spacing: 3) {
                Text("🍽️")
                    .font(.system(size: 10))
                Text("pos_served".t)
                    .font(.system(size: 9, weight: .bold))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.textSecondary.opacity(0.12))
            .foregroundColor(.textSecondary)
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.textSecondary.opacity(0.25), lineWidth: 0.5)
            )
        case "cancelled":
            text = "ยกเลิก"
            icon = "❌"
            color = .appRose
        default:
            text = status.capitalized
            icon = "⏳"
            color = .appAmber
        }

        return HStack(spacing: 3) {
            Text(icon)
                .font(.system(size: 10))
            Text(text)
                .font(.system(size: 9, weight: .bold))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(color.opacity(0.12))
        .foregroundColor(color)
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(color.opacity(0.25), lineWidth: 0.5)
        )
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
                Color.appBackground.ignoresSafeArea()

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

// MARK: - Cash Payment Modal View

struct CashPaymentModalView: View {
    let totalAmount: Double
    let onConfirm: (Double) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var cashReceivedText = ""
    @State private var showSuccessOverlay = false
    @State private var delayRemaining = 3.0
    @State private var isProcessing = false

    private var cashReceived: Double {
        Double(cashReceivedText) ?? 0.0
    }

    private var changeDue: Double {
        cashReceived - totalAmount
    }

    private var isAmountSufficient: Bool {
        cashReceived >= totalAmount
    }

    private func handleKeypadInput(_ input: String) {
        withAnimation(.spring(response: 0.15, dampingFraction: 0.6)) {
            if input == "⌫" {
                if !cashReceivedText.isEmpty {
                    cashReceivedText.removeLast()
                }
            } else if input == "." {
                if !cashReceivedText.contains(".") {
                    if cashReceivedText.isEmpty {
                        cashReceivedText = "0."
                    } else {
                        cashReceivedText += "."
                    }
                }
            } else {
                if cashReceivedText == "0" {
                    cashReceivedText = input
                } else {
                    if cashReceivedText.count < 8 {
                        cashReceivedText += input
                    }
                }
            }
        }
    }

    private func formatAmountNoCent(_ amount: Double) -> String {
        if amount.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", amount)
        } else {
            return String(format: "%.2f", amount)
        }
    }

    private func startCheckoutDelay() {
        isProcessing = true
        APHaptic.trigger()

        // Show success screen
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            showSuccessOverlay = true
        }

        // Dynamic countdown using Swift Concurrency
        Task {
            for _ in 0..<3 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run {
                    withAnimation {
                        if delayRemaining > 1 {
                            delayRemaining -= 1
                        }
                    }
                }
            }
            await MainActor.run {
                onConfirm(cashReceived)
                dismiss()
            }
        }
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
            .apNavBar(background: Color.appSurface)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.Common.cancel.t) { dismiss() }
                        .foregroundColor(.textSecondary)
                        .disabled(isProcessing)
                }
            }
        }
        .apColorScheme()
    }

    private var mainContentView: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                // Left Column: Bill details, Quick Cash, and Change Due
                VStack(spacing: 10) {
                    // Total Due Card
                    VStack(spacing: 4) {
                        Text("pos_total_amount".t)
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.textSecondary)

                        Text(String(format: "฿%.2f", totalAmount))
                            .font(.system(size: 26, weight: .black))
                            .foregroundStyle(APGradient.accent)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity)
                    .background(Color.appSurface)
                    .cornerRadius(APRadius.md)
                    .overlay(
                        RoundedRectangle(cornerRadius: APRadius.md)
                            .stroke(Color.appBorderSubtle, lineWidth: 1)
                    )

                    // Quick Cash Shortcuts
                    VStack(alignment: .leading, spacing: 6) {
                        Text("pos_quick_cash".t)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.textSecondary)
                            .textCase(.uppercase)

                        VStack(spacing: 6) {
                            HStack(spacing: 6) {
                                quickCashButton(label: "Exact", amountValue: totalAmount)
                                quickCashButton(label: "฿100", amountValue: 100.0)
                            }
                            HStack(spacing: 6) {
                                quickCashButton(label: "฿500", amountValue: 500.0)
                                quickCashButton(label: "฿1,000", amountValue: 1000.0)
                            }
                        }
                    }

                    // Change Due Card
                    VStack(spacing: 4) {
                        if isAmountSufficient {
                            Text("pos_change_due".t)
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.textSecondary)

                            Text(String(format: "฿%.2f", changeDue))
                                .font(.system(size: 24, weight: .black))
                                .foregroundColor(.appTeal)
                                .contentTransition(.numericText())
                                .scaleEffect(isAmountSufficient ? 1.02 : 1.0)
                                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: changeDue)
                        } else {
                            let missingAmount = totalAmount - cashReceived
                            Text("pos_amount_missing".t)
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.textSecondary)

                            Text(String(format: "฿%.2f", missingAmount))
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.appRose)
                                .contentTransition(.numericText())
                                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: missingAmount)
                        }
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, minHeight: 75)
                    .background(isAmountSufficient ? Color.appTeal.opacity(0.08) : Color.appRose.opacity(0.08))
                    .cornerRadius(APRadius.md)
                    .overlay(
                        RoundedRectangle(cornerRadius: APRadius.md)
                            .stroke(isAmountSufficient ? Color.appTeal.opacity(0.3) : Color.appRose.opacity(0.3), lineWidth: 1)
                    )
                }
                .frame(width: 220)

                // Right Column: Cash Received display and Calculator Keypad
                VStack(spacing: 10) {
                    // Input display field
                    HStack {
                        Text("฿")
                            .font(.title3).fontWeight(.black)
                            .foregroundColor(.textPrimary)

                        Spacer()

                        Text(cashReceivedText.isEmpty ? "0" : cashReceivedText)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(cashReceivedText.isEmpty ? .textTertiary : .textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .contentTransition(.numericText())

                        if !cashReceivedText.isEmpty {
                            Button(action: {
                                withAnimation(.spring(response: 0.15, dampingFraction: 0.6)) {
                                    cashReceivedText = ""
                                }
                                APHaptic.trigger()
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.textSecondary)
                                    .font(.system(size: 16))
                            }
                            .transition(.opacity.combined(with: .scale))
                        }
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .background(Color.appSurface)
                    .cornerRadius(APRadius.md)
                    .overlay(
                        RoundedRectangle(cornerRadius: APRadius.md)
                            .stroke(Color.appBorderSubtle, lineWidth: 1)
                    )

                    // Keypad grid
                    keypadGrid
                }
                .frame(maxWidth: .infinity)
            }

            // Confirm CTA (Spans full-width at the bottom)
            Button(action: startCheckoutDelay) {
                Label("confirm_payment_btn".t, systemImage: "checkmark.circle.fill")
                    .apGradientButton(
                        gradient: isAmountSufficient ? APGradient.positive : LinearGradient(colors: [Color.appSurface], startPoint: .leading, endPoint: .trailing),
                        shadow: APShadow.positiveGlow,
                        disabled: !isAmountSufficient
                    )
            }
            .disabled(!isAmountSufficient)
            .padding(.top, 4)
        }
        .padding(14)
    }

    private func quickCashButton(label: String, amountValue: Double) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                if label.contains("Exact") {
                    cashReceivedText = formatAmountNoCent(amountValue)
                } else {
                    cashReceivedText = String(format: "%.0f", amountValue)
                }
            }
            APHaptic.trigger()
        }) {
            Text(label)
                .font(.subheadline).fontWeight(.bold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.appSurfaceHigh)
                .foregroundColor(.textPrimary)
                .cornerRadius(APRadius.sm)
                .overlay(
                    RoundedRectangle(cornerRadius: APRadius.sm)
                        .stroke(Color.appBorderSubtle, lineWidth: 1)
                )
        }
        .buttonStyle(KeypadButtonStyle())
    }

    private var keypadGrid: some View {
        VStack(spacing: 6) {
            let keys = [
                ["7", "8", "9"],
                ["4", "5", "6"],
                ["1", "2", "3"],
                [".", "0", "⌫"]
            ]

            ForEach(keys, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(row, id: \.self) { key in
                        Button(action: {
                            handleKeypadInput(key)
                        }) {
                            Group {
                                if key == "⌫" {
                                    Image(systemName: "delete.left.fill")
                                        .font(.title3)
                                        .foregroundColor(.appRose)
                                } else {
                                    Text(key)
                                        .font(.title3).fontWeight(.bold)
                                        .foregroundColor(key == "." ? .textSecondary : .textPrimary)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Color.appSurfaceHigh)
                            .cornerRadius(APRadius.sm)
                            .overlay(
                                RoundedRectangle(cornerRadius: APRadius.sm)
                                    .stroke(Color.appBorderSubtle, lineWidth: 1)
                            )
                        }
                        .buttonStyle(KeypadButtonStyle())
                    }
                }
            }
        }
    }

    private var successOverlayView: some View {
        VStack(spacing: APSpacing.lg) {
            Spacer()

            // Checkmark Animation
            ZStack {
                Circle()
                    .fill(Color.appTeal.opacity(0.15))
                    .frame(width: 90, height: 90)

                Circle()
                    .stroke(Color.appTeal, lineWidth: 3)
                    .frame(width: 90, height: 90)
                    .scaleEffect(isProcessing ? 1.05 : 1.0)
                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isProcessing)

                Image(systemName: "checkmark")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.appTeal)
            }

            VStack(spacing: APSpacing.xs) {
                Text("pos_payment_successful".t)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.textPrimary)

                Text(LocalizationManager.shared.t("received_cash_template", cashReceived))
                    .font(.subheadline)
                    .foregroundColor(.textSecondary)
            }

            // Large Change Due Box
            if changeDue > 0 {
                VStack(spacing: 6) {
                    Text("pos_change_due".t)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.textSecondary)

                    Text(String(format: "฿%.2f", changeDue))
                        .font(.system(size: 40, weight: .black))
                        .foregroundColor(.appTeal)
                        .shadow(color: Color.appTeal.opacity(0.2), radius: 10, x: 0, y: 5)
                        .scaleEffect(1.05)
                        .animation(.spring(response: 0.4, dampingFraction: 0.7).repeatForever(autoreverses: true), value: isProcessing)
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 28)
                .background(Color.appTeal.opacity(0.08))
                .cornerRadius(APRadius.md)
                .overlay(
                    RoundedRectangle(cornerRadius: APRadius.md)
                        .stroke(Color.appTeal.opacity(0.3), lineWidth: 1)
                )
            } else {
                Text("pos_no_change_due".t)
                    .font(.headline)
                    .foregroundColor(.appTeal)
                    .padding()
                    .background(Color.appTeal.opacity(0.08))
                    .cornerRadius(APRadius.md)
            }

            Spacer()

            // Loading/Countdown indicator
            HStack(spacing: 8) {
                ProgressView()
                    .tint(.textSecondary)
                Text(String(format: "Closing in %.0f seconds...", delayRemaining))
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            }
            .padding(.bottom, APSpacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
    }
}

struct KeypadButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .brightness(configuration.isPressed ? -0.05 : 0.0)
            .animation(.spring(response: 0.15, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - QR Payment Modal View

struct QRPaymentModalView: View {
    let totalAmount: Double
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    @AppStorage("promptpay_number") private var promptPayNumber = ""
    @State private var progressStatus = "waiting" // "waiting", "success"

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                VStack(spacing: APSpacing.lg) {
                    if promptPayNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
                        // QR Content Card
                        VStack(spacing: APSpacing.md) {
                            let payload = generatePromptPayPayload(target: promptPayNumber, amount: totalAmount)
                            if let qrImage = generateQRCode(from: payload) {
                                Image(uiImage: qrImage)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 180, height: 180)
                                    .padding()
                                    .background(Color.white)
                                    .cornerRadius(APRadius.md)
                                    .shadow(color: .black.opacity(0.1), radius: 8)
                            } else {
                                Image(systemName: "qrcode")
                                    .font(.system(size: 140, weight: .light))
                                    .foregroundColor(.textPrimary)
                                    .padding()
                                    .background(Color.white)
                                    .cornerRadius(APRadius.md)
                                    .shadow(color: .black.opacity(0.1), radius: 8)
                            }

                            VStack(spacing: 4) {
                                Text("scan_promptpay_qr_desc".t)
                                    .font(.subheadline)
                                    .foregroundColor(.textSecondary)

                                Text("\("promptpay_id_prefix".t)\(promptPayNumber)")
                                    .font(.caption)
                                    .foregroundColor(.textSecondary)
                                    .fontWeight(.bold)
                            }

                            Text(String(format: "฿%.2f", totalAmount))
                                .font(.title).fontWeight(.black)
                                .foregroundStyle(APGradient.accent)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.appSurface)
                        .cornerRadius(APRadius.md)
                    }

                    // Status Bar
                    HStack(spacing: APSpacing.sm) {
                        if progressStatus == "waiting" {
                            if promptPayNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text("awaiting_configuration".t)
                                    .font(.footnote)
                                    .foregroundColor(.appAmber)
                            } else {
                                ProgressView()
                                    .tint(.appAmber)
                                Text("waiting_for_scan".t)
                                    .font(.footnote)
                                    .foregroundColor(.appAmber)
                            }
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(.appTeal)
                            Text("payment_confirmed_success".t)
                                .font(.footnote).fontWeight(.bold)
                                .foregroundColor(.appTeal)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(progressStatus == "waiting" ? Color.appAmber.opacity(0.08) : Color.appTeal.opacity(0.08))
                    .cornerRadius(APRadius.md)

                    Spacer()

                    // CTA Button
                    Button(action: {
                        onConfirm()
                        dismiss()
                    }) {
                        Label(progressStatus == "waiting" ? "Force Confirm (Cash received)" : "Confirm & Close Session", systemImage: "checkmark.circle.fill")
                            .apGradientButton(
                                gradient: progressStatus == "success" ? APGradient.positive : APGradient.accent,
                                shadow: progressStatus == "success" ? APShadow.positiveGlow : APShadow.glow,
                                disabled: promptPayNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && progressStatus == "waiting"
                            )
                    }
                    .disabled(promptPayNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && progressStatus == "waiting")
                }
                .padding(APSpacing.md)
            }
            .navigationTitle("promptpay_qr_code_title".t)
            .apNavBar(background: Color.appSurface)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.Common.cancel.t) { dismiss() }
                        .foregroundColor(.textSecondary)
                }
            }
            .onAppear {
                if !promptPayNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        withAnimation {
                            progressStatus = "success"
                            APHaptic.trigger()
                        }
                    }
                }
            }
        }
        .apColorScheme()
    }

    // MARK: - PromptPay QR Code Generation Helpers

    private func generatePromptPayPayload(target: String, amount: Double) -> String {
        let sanitized = target.replacingOccurrences(of: " ", with: "")
                              .replacingOccurrences(of: "-", with: "")

        var accountInfo = "0016A000000677010111"

        if sanitized.count == 13 {
            // National ID or Tax ID
            accountInfo += "0213\(sanitized)"
        } else {
            // Mobile Phone number
            var phone = sanitized
            if phone.hasPrefix("0") {
                phone.removeFirst()
            }
            let phoneFormatted = "0066" + phone
            accountInfo += "0113\(phoneFormatted)"
        }

        var payload = "000201010212" // Dynamic QR (locks amount)
        payload += String(format: "29%02d%@", accountInfo.count, accountInfo)
        payload += "5303764" // THB Currency

        let amtStr = String(format: "%.2f", amount)
        payload += String(format: "54%02d%@", amtStr.count, amtStr)

        payload += "5802TH"
        payload += "6304"

        let crc = crc16(payload)
        payload += String(format: "%04X", crc)

        return payload
    }

    private func crc16(_ dataString: String) -> UInt16 {
        let bytes = Array(dataString.utf8)
        var crc: UInt16 = 0xFFFF
        let polynomial: UInt16 = 0x1021

        for byte in bytes {
            for i in 0..<8 {
                let bit = ((byte >> (7 - i)) & 1) == 1
                let c15 = ((crc >> 15) & 1) == 1
                crc <<= 1
                if c15 != bit {
                    crc ^= polynomial
                }
            }
        }
        return crc
    }

    private func generateQRCode(from string: String) -> UIImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        let data = string.data(using: .utf8)
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("Q", forKey: "inputCorrectionLevel")

        guard let ciImage = filter.outputImage else { return nil }

        let scale = 10.0
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        let scaledCIImage = ciImage.transformed(by: transform)

        let context = CIContext()
        guard let cgImage = context.createCGImage(scaledCIImage, from: scaledCIImage.extent) else { return nil }

        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Credit Card Payment Modal View

struct CreditCardPaymentModalView: View {
    let totalAmount: Double
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var step = 1 // 1: Connecting, 2: Insert Card, 3: Processing, 4: Authorized

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

                    // Terminal Simulator Screen
                    VStack(spacing: APSpacing.md) {
                        Image(systemName: "creditcard.and.123")
                            .font(.system(size: 64))
                            .foregroundColor(step == 4 ? .appTeal : .appAccent)

                        VStack(spacing: 4) {
                            switch step {
                            case 1:
                                ProgressView()
                                    .tint(.appAccent)
                                    .padding(.bottom, 4)
                                Text("connecting_to_terminal".t)
                                    .font(.headline)
                                    .foregroundColor(.textPrimary)
                                Text("connecting_to_terminal_desc".t)
                                    .font(.caption)
                                    .foregroundColor(.textSecondary)
                            case 2:
                                Text("please_swipe_card".t)
                                    .font(.headline)
                                    .foregroundColor(.textPrimary)
                                Text("edc_terminal_ready".t)
                                    .font(.caption)
                                    .foregroundColor(.textSecondary)
                            case 3:
                                ProgressView()
                                    .tint(.appAccent)
                                    .padding(.bottom, 4)
                                Text("authorizing_transaction".t)
                                    .font(.headline)
                                    .foregroundColor(.textPrimary)
                                Text("processing_payment_desc".t)
                                    .font(.caption)
                                    .foregroundColor(.textSecondary)
                            default:
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.title)
                                    .foregroundColor(.appTeal)
                                Text("transaction_approved_status".t)
                                    .font(.headline).fontWeight(.bold)
                                    .foregroundColor(.appTeal)
                                Text("payment_completed_desc".t)
                                    .font(.caption)
                                    .foregroundColor(.textSecondary)
                            }
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
                        Label(step == 4 ? "Finish & Print Receipt" : "Skip EDC Simulation", systemImage: "checkmark.circle.fill")
                            .apGradientButton(
                                gradient: step == 4 ? APGradient.positive : APGradient.accent,
                                shadow: step == 4 ? APShadow.positiveGlow : APShadow.glow
                            )
                    }
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
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    withAnimation { step = 2 }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    withAnimation { step = 3 }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) {
                    withAnimation {
                        step = 4
                        APHaptic.trigger()
                    }
                }
            }
        }
        .apColorScheme()
    }
}

#Preview {
    POSView(activeSession: .constant(nil), selectedTab: .constant(.pos), columnVisibility: .constant(.all))
}
