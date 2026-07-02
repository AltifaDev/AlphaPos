import Foundation
import SwiftData
import SwiftUI

// MARK: - Cart Items View Representation Struct

struct CartItem: Identifiable {
    let id = UUID()
    let item: MenuItem
    let selectedModifiers: [Modifier]
    var quantity: Int = 1
    var notes: String = ""

    /// Use totalPriceDecimal for accurate currency calculations (avoids floating-point errors).
    /// totalPrice is kept for backward compatibility but may lose precision.
    var totalPrice: Double {
        let modifierCost = selectedModifiers.reduce(0.0) { $0 + $1.extraPrice }
        return (item.price + modifierCost) * Double(quantity)
    }

    var totalPriceDecimal: Decimal {
        let modifierCost = selectedModifiers.reduce(Decimal.zero) { $0 + ($1.extraPriceDecimal) }
        return (item.priceDecimal + modifierCost) * Decimal(quantity)
    }

    func isEqual(to other: CartItem) -> Bool {
        guard item.id == other.item.id else { return false }
        let selfIds = selectedModifiers.map { $0.id }.sorted()
        let otherIds = other.selectedModifiers.map { $0.id }.sorted()
        return selfIds == otherIds && notes == other.notes
    }
}

struct FocusTarget: Equatable {
    let triggerId = UUID()
    let itemId: UUID

    static func == (lhs: FocusTarget, rhs: FocusTarget) -> Bool {
        lhs.triggerId == rhs.triggerId
    }
}

// MARK: - POS View Model

@Observable
@MainActor
final class POSViewModel {
    var modelContext: ModelContext?

    // Cart and configuration states
    var cart: [CartItem] = []
    var lastAddedItem: FocusTarget? = nil
    var selectedCategory: Category?
    var selectedItemForCustomization: MenuItem?
    var selectedPaymentMethod = "QR PromptPay"
    var selectedTableNumber = "1"
    var selectedOrderType = "dine_in"
    var guestCount: Int = 2
    var cashierName: String = "Alex M."
    var selectedCustomer: Customer? = nil
    var currentQueueNumber: String = ""
    var currentBillNumber: String = ""
    var currentOrderDateString: String = ""
    var recentlySubmittedTableOrder: Order?

    // L6: Checkout error state — nil means no error, non-nil contains error description
    var lastCheckoutError: String? = nil

    var deliveryBrand: String? = nil
    var deliveryGP: Double = 0.0
    var deliveryAdFee: Double = 0.0
    var deliveryAdFeeIsPct: Bool = false
    var deliveryOtherFee: Double = 0.0

    init(modelContext: ModelContext? = nil) {
        self.modelContext = modelContext
    }

    // MARK: - POS Session Synchronization

    func syncFromSession(_ session: TableSession?) {
        if let session = session {
            if recentlySubmittedTableOrder?.tableSession?.id != session.id {
                recentlySubmittedTableOrder = nil
            }
            guestCount = session.guestCount
            cashierName = session.cashierName
            selectedOrderType = "dine_in"
            currentBillNumber = "AP-\(session.id.uuidString.prefix(6).uppercased())"
            if let q = session.queueNumber {
                currentQueueNumber = q
            } else {
                let tableNum = session.table?.tableNumber ?? "0"
                let newQ = "Q-\(tableNum)-\(session.id.uuidString.prefix(3).uppercased())"
                session.queueNumber = newQ
                currentQueueNumber = newQ
                try? modelContext?.save()
            }
            currentOrderDateString = DateFormatter.shortDateTimeFormat().string(from: session.startedAt)
        } else {
            recentlySubmittedTableOrder = nil
            selectedOrderType = "take_out"
            currentBillNumber = "AP-NEW"
            if currentQueueNumber.isEmpty {
                currentQueueNumber = "Q-\(Int.random(in: 100...999))"
            }
            currentOrderDateString = DateFormatter.shortDateTimeFormat().string(from: Date())
        }
    }

    func updateGuestCount(_ newCount: Int, session: TableSession?) {
        guestCount = newCount
        if let session = session {
            session.guestCount = newCount
            session.isSynced = false
            session.updatedAt = Date()
            try? modelContext?.save()
            Task { _ = try? await NetworkManager.shared.uploadTableSession(session: session) }
        }
    }

    func updateCashierName(_ name: String, session: TableSession?) {
        cashierName = name
        if let session = session {
            session.cashierName = name
            try? modelContext?.save()
        }
    }

    func updateOrderType(_ type: String) {
        selectedOrderType = type
    }

    // MARK: - Financial Calculations

    var cartSubtotal: Double {
        cart.reduce(0.0) { $0 + $1.totalPrice }
    }

    private func getTaxRateAndInclusion(for item: MenuItem) -> (rate: Double, isInclusive: Bool) {
        guard UserDefaults.standard.bool(forKey: "enable_tax") else {
            return (0.0, true)
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

    var cartTax: Double {
        guard UserDefaults.standard.bool(forKey: "enable_tax") else {
            return 0.0
        }
        if selectedCustomer?.isTaxExempt == true {
            return 0.0 // No tax for tax-exempt customers
        }

        var totalTax = 0.0
        for cartItem in cart {
            let lineTotal = cartItem.totalPrice
            let (rate, isInclusive) = getTaxRateAndInclusion(for: cartItem.item)

            if isInclusive {
                totalTax += lineTotal * (rate / (100.0 + rate))
            } else {
                totalTax += lineTotal * (rate / 100.0)
            }
        }

        let serviceChargeTaxable = UserDefaults.standard.object(forKey: "tax_service_charge_taxable") as? Bool ?? true
        let globalTaxRate = UserDefaults.standard.double(forKey: "store_tax_rate")
        let serviceChargeTax = serviceChargeTaxable ? cartServiceCharge * (globalTaxRate / 100.0) : 0.0
        return totalTax + serviceChargeTax
    }

    var cartServiceCharge: Double {
        guard UserDefaults.standard.bool(forKey: "enable_service_charge") else {
            return 0.0
        }
        if selectedOrderType == "take_out" || selectedOrderType == "delivery" {
            return 0.0
        }
        let serviceChargeRate = UserDefaults.standard.object(forKey: "store_service_charge_rate") as? Double ?? 10.0
        return cartSubtotal * (serviceChargeRate / 100.0)
    }

    var activePromotion: Promotion? {
        bestPromotion()
    }

    var cartDiscount: Double {
        guard let activePromotion else { return 0.0 }
        return discountAmount(for: activePromotion)
    }

    var cartTotal: Double {
        let taxEnabled = UserDefaults.standard.bool(forKey: "enable_tax")
        if selectedCustomer?.isTaxExempt == true || !taxEnabled {
            return max(0, cartSubtotal + cartServiceCharge - cartDiscount)
        }

        var totalAmount = 0.0
        for cartItem in cart {
            let lineTotal = cartItem.totalPrice
            let (rate, isInclusive) = getTaxRateAndInclusion(for: cartItem.item)

            if isInclusive {
                totalAmount += lineTotal
            } else {
                totalAmount += lineTotal * (1.0 + rate / 100.0)
            }
        }

        let serviceChargeTaxable = UserDefaults.standard.object(forKey: "tax_service_charge_taxable") as? Bool ?? true
        let globalTaxRate = UserDefaults.standard.double(forKey: "store_tax_rate")
        let serviceChargeTax = serviceChargeTaxable ? cartServiceCharge * (globalTaxRate / 100.0) : 0.0
        return max(0, totalAmount + cartServiceCharge + serviceChargeTax - cartDiscount)
    }

    private func bestPromotion() -> Promotion? {
    guard cartSubtotal > 0,
          UserDefaults.standard.object(forKey: "promotions_auto_apply") as? Bool ?? true,
          let modelContext else { return nil }

    let descriptor = FetchDescriptor<Promotion>(
        predicate: #Predicate<Promotion> { $0.isDeleted == false }
    )
    let now = Date()
    let promotions = (try? modelContext.fetch(descriptor)) ?? []

    return promotions
        .filter { promo in
            guard promo.isEffective(at: now) else { return false }
            guard discountAmount(for: promo) > 0 else { return false }

            // Check per-customer limit if customer is selected
            if let customer = selectedCustomer, let limit = promo.perCustomerLimit {
                let customerRedemptions = countCustomerRedemptions(
                    customerId: customer.id,
                    promotionId: promo.id,
                    modelContext: modelContext
                )
                if customerRedemptions >= limit { return false }
            }

            return true
        }
        .max { lhs, rhs in
            discountAmount(for: lhs) < discountAmount(for: rhs)
        }
}

    private func countCustomerRedemptions(customerId: UUID, promotionId: UUID, modelContext: ModelContext) -> Int {
    let descriptor = FetchDescriptor<OrderDiscount>(
        predicate: #Predicate<OrderDiscount> { $0.isDeleted == false }
    )
    guard let discounts = try? modelContext.fetch(descriptor) else { return 0 }
    return discounts.filter {
        $0.promotion?.id == promotionId && $0.order?.customer?.id == customerId
    }.count
}


    private func discountAmount(for promotion: Promotion) -> Double {
        if promotion.discountType == "bundle_price" {
            guard let itemId = promotion.appliesToMenuItemId,
                  promotion.requiredQuantity > 0,
                  promotion.discountValue > 0 else { return 0 }

            return cart.reduce(0.0) { total, cartItem in
                guard cartItem.item.id == itemId else { return total }
                let bundleCount = cartItem.quantity / promotion.requiredQuantity
                guard bundleCount > 0 else { return total }
                let unitPrice = cartItem.item.price + cartItem.selectedModifiers.reduce(0.0) { $0 + $1.extraPrice }
                let regularBundleTotal = unitPrice * Double(promotion.requiredQuantity * bundleCount)
                let promoBundleTotal = promotion.discountValue * Double(bundleCount)
                return total + max(0, regularBundleTotal - promoBundleTotal)
            }
        }

        if promotion.discountType == "buy_x_get_y" {
            guard let itemId = promotion.appliesToMenuItemId,
                  promotion.requiredQuantity > 0,
                  promotion.rewardQuantity > 0 else { return 0 }

            let groupSize = promotion.requiredQuantity + promotion.rewardQuantity
            return cart.reduce(0.0) { total, cartItem in
                guard cartItem.item.id == itemId else { return total }
                let groupCount = cartItem.quantity / groupSize
                guard groupCount > 0 else { return total }
                let unitPrice = cartItem.item.price + cartItem.selectedModifiers.reduce(0.0) { $0 + $1.extraPrice }
                let freeUnits = groupCount * promotion.rewardQuantity
                return total + max(0, unitPrice * Double(freeUnits))
            }
        }

        if promotion.discountType == "buy_x_pay_y" {
            guard let itemId = promotion.appliesToMenuItemId,
                  promotion.requiredQuantity > 0,
                  promotion.rewardQuantity > 0,
                  promotion.rewardQuantity < promotion.requiredQuantity else { return 0 }

            return cart.reduce(0.0) { total, cartItem in
                guard cartItem.item.id == itemId else { return total }
                let groupCount = cartItem.quantity / promotion.requiredQuantity
                guard groupCount > 0 else { return total }
                let unitPrice = cartItem.item.price + cartItem.selectedModifiers.reduce(0.0) { $0 + $1.extraPrice }
                let freeUnits = groupCount * (promotion.requiredQuantity - promotion.rewardQuantity)
                return total + max(0, unitPrice * Double(freeUnits))
            }
        }

        return promotion.discountAmount(for: cartSubtotal)
    }

    // MARK: - Cart Operations

    func selectItem(_ item: MenuItem) {
        // If menu item has recipes/modifier groups, open customize screen, else add straight to cart
        if item.modifierGroupsRelations.isEmpty {
            addToCart(item, modifiers: [])
        } else {
            selectedItemForCustomization = item
        }
    }

    func addToCart(_ item: MenuItem, modifiers: [Modifier]) {
        let cartItem = CartItem(item: item, selectedModifiers: modifiers)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            if let idx = cart.firstIndex(where: { $0.isEqual(to: cartItem) }) {
                cart[idx].quantity += 1
                lastAddedItem = FocusTarget(itemId: cart[idx].id)
            } else {
                cart.append(cartItem)
                lastAddedItem = FocusTarget(itemId: cartItem.id)
            }
        }
        APHaptic.trigger()
    }

    func increaseQty(_ item: CartItem) {
        if let idx = cart.firstIndex(where: { $0.id == item.id }) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                cart[idx].quantity += 1
                lastAddedItem = FocusTarget(itemId: cart[idx].id)
            }
            APHaptic.trigger()
        }
    }

    func decreaseQty(_ item: CartItem) {
        if let idx = cart.firstIndex(where: { $0.id == item.id }) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                if cart[idx].quantity > 1 {
                    cart[idx].quantity -= 1
                } else {
                    cart.remove(at: idx)
                }
            }
            APHaptic.trigger()
        }
    }

    func removeFromCart(at offsets: IndexSet) {
        cart.remove(atOffsets: offsets)
    }

    // MARK: - Checkout Stock Deduct Logic

    private func fetchActiveBranch(context: ModelContext) -> Branch? {
        if let activeIdString = UserDefaults.standard.string(forKey: "active_branch_id"),
           let activeUUID = UUID(uuidString: activeIdString) {
            let branchDesc = FetchDescriptor<Branch>()
            if let branches = try? context.fetch(branchDesc) {
                return branches.first(where: { $0.id == activeUUID })
            }
        }
        return nil
    }

    @discardableResult func processCheckout(
        tableSession: TableSession? = nil,
        createPayment: Bool = false,
        paymentMethod: String? = nil,
        dispatchPrint: Bool = true
    ) -> Order? {
    lastCheckoutError = nil
    guard let modelContext = modelContext else {
        lastCheckoutError = "modelContext unavailable — cannot checkout"
        return nil
    }
    guard !cart.isEmpty else {
        lastCheckoutError = "cart is empty — cannot create an order without items"
        return nil
    }
    let activeBranch = fetchActiveBranch(context: modelContext)

    // 1. Create the Order
    let finalOrderNum: String
    if currentBillNumber == "AP-NEW" {
        finalOrderNum = "ORD-\(DateFormatter.orderDateFormat().string(from: Date()))-\(Int.random(in: 100...999))"
    } else if let session = tableSession {
        // H-8 FIX: Prevent unique constraint violation on (merchant_id, order_number)
        // by appending a suffix if this is a subsequent order in the same session.
        let sessionOrderCount = session.orders.filter { !$0.isDeleted }.count
        if sessionOrderCount > 0 {
            finalOrderNum = "\(currentBillNumber)-\(sessionOrderCount + 1)"
        } else {
            finalOrderNum = currentBillNumber
        }
    } else {
        finalOrderNum = currentBillNumber
    }
    let appliedPromotion = activePromotion
    let appliedDiscount = cartDiscount
    let order = Order(
        orderNumber: finalOrderNum,
        tableSession: tableSession,
        orderType: selectedOrderType,
        status: "preparing",
        subtotal: cartSubtotal,
        tax: cartTax,
        serviceCharge: cartServiceCharge,
        discount: appliedDiscount,
        total: cartTotal,
        branch: activeBranch,
        guestCount: guestCount,
        cashierName: cashierName,
        queueNumber: currentQueueNumber.isEmpty ? nil : currentQueueNumber,
        deliveryBrand: selectedOrderType == "delivery" ? deliveryBrand : nil,
        deliveryGP: selectedOrderType == "delivery" ? deliveryGP : 0.0,
        deliveryAdFee: selectedOrderType == "delivery" ? deliveryAdFee : 0.0,
        deliveryAdFeeIsPct: selectedOrderType == "delivery" ? deliveryAdFeeIsPct : false,
        deliveryOtherFee: selectedOrderType == "delivery" ? deliveryOtherFee : 0.0
    )
    order.customer = selectedCustomer

    modelContext.insert(order)

    // Explicitly update relationship in-memory
    if let session = tableSession {
        session.orders.append(order)
        recentlySubmittedTableOrder = order
        session.isSynced = false
        session.updatedAt = Date()
    }

    // 2. Record OrderDiscount if promotion applied
    if let appliedPromotion, appliedDiscount > 0 {
        let discount = OrderDiscount(
            order: order,
            promotion: appliedPromotion,
            discountType: appliedPromotion.discountType,
            discountValue: appliedPromotion.discountValue,
            discountAmount: appliedDiscount,
            reason: "Auto-applied promotion: \(appliedPromotion.title)"
        )
        modelContext.insert(discount)

        // Increment promotion usage counter
        appliedPromotion.incrementRedemption()
    }
    
    // Create OrderTaxLines if tax is enabled
    if UserDefaults.standard.bool(forKey: "enable_tax") && selectedCustomer?.isTaxExempt != true {
        let globalTaxRate = UserDefaults.standard.double(forKey: "store_tax_rate")
        let taxName = UserDefaults.standard.string(forKey: "store_tax_name") ?? "VAT"
        let globalTaxType = UserDefaults.standard.string(forKey: "store_tax_type") ?? "inclusive"
        
        if cartTax > 0 {
            let taxLine = OrderTaxLine(
                order: order,
                taxName: "\(taxName) \(Int(globalTaxRate))%",
                taxRate: globalTaxRate,
                taxableAmount: cartSubtotal,
                taxAmount: cartTax,
                isInclusive: (globalTaxType == "inclusive")
            )
            modelContext.insert(taxLine)
            order.taxLines.append(taxLine)
        }
    }

    // Pre-fetch all inventory items for the active branch once (avoids N+1 inside deductIngredientsLocally)
    var branchInventoryCache: [String: InventoryItem]? = nil
    if let activeBranch = activeBranch {
        let allItems = (try? modelContext.fetch(FetchDescriptor<InventoryItem>())) ?? []
        let branchItems = allItems.filter { $0.branch?.id == activeBranch.id }
        var cache: [String: InventoryItem] = [:]
        for item in branchItems {
            if let sku = item.sku { cache[sku] = item }
            cache[item.name] = item
        }
        branchInventoryCache = cache
    }

    // 3. Add OrderItems and deduct stock for regular cart items
    for cartItem in cart {
        let orderItem = OrderItem(
            order: order,
            menuItem: cartItem.item,
            quantity: cartItem.quantity,
            unitPrice: cartItem.item.price,
            notes: cartItem.notes,
            status: "cooking"
        )
        modelContext.insert(orderItem)
        orderItem.order = order
        
        // Explicitly update relationship in-memory
        order.items.append(orderItem)

        // Link modifiers selected
        var modifierReferenceIds: [UUID] = []
        for mod in cartItem.selectedModifiers {
            let orderItemMod = OrderItemModifier(orderItem: orderItem, modifier: mod, price: mod.extraPrice)
            modelContext.insert(orderItemMod)
            orderItemMod.orderItem = orderItem
            
            // Explicitly update relationship in-memory
            orderItem.modifiers.append(orderItemMod)
            
            modifierReferenceIds.append(orderItemMod.id)
        }

        // Local client stock deduction (Offline-First trigger simulation)
        deductIngredientsLocally(
            for: cartItem,
            activeBranch: activeBranch,
            baseReferenceId: orderItem.id,
            modifierReferenceIds: modifierReferenceIds,
            branchInventoryCache: branchInventoryCache
        )
    }

    // 4. Handle promotion-specific inventory effects
    if let appliedPromotion {
        handlePromotionInventoryEffects(
            promotion: appliedPromotion,
            order: order,
            activeBranch: activeBranch,
            modelContext: modelContext
        )
    }

    // 5. Process payment record only when this is an actual checkout.
    // Table-service orders are first sent to the kitchen unpaid, then paid after service.
    if createPayment {
        let payment = Payment(paymentMethod: paymentMethod ?? selectedPaymentMethod, amount: cartTotal)
        payment.order = order
        modelContext.insert(payment)
    }

    do {
        try modelContext.save()
    } catch {
        let errMsg = "POSViewModel [Checkout Save Error]: \(error.localizedDescription)\nFull error: \(error)"
        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let fileURL = docs.appendingPathComponent("alphapos_error.txt")
            try? errMsg.write(to: fileURL, atomically: true, encoding: .utf8)
        }
        print(errMsg)
        
        // Rollback: delete the failed insertions to keep SwiftData context consistent
        modelContext.delete(order)
        for item in order.items {
            modelContext.delete(item)
            for mod in item.modifiers {
                modelContext.delete(mod)
            }
        }
        if let session = tableSession {
            if let index = session.orders.firstIndex(where: { $0.id == order.id }) {
                session.orders.remove(at: index)
            }
        }
        try? modelContext.save() // save the deletions
        
        lastCheckoutError = "Failed to save checkout: \(error.localizedDescription)"
        return nil
    }
    cart.removeAll()
    selectedCustomer = nil
    if tableSession == nil {
        currentQueueNumber = ""
    }

    // Close dine-in table session only after actual payment, not when sending to kitchen.
    if createPayment, selectedOrderType == "dine_in", let session = tableSession {
        session.isActive = false
        session.endedAt = Date()
        session.isSynced = false
        session.updatedAt = Date()
        modelContext.saveWithLogging(label: #function)
    }

    APHaptic.trigger()

    // Background sync
    Task {
        await SyncEngine.shared.syncAll(modelContext: modelContext)
    }

    if dispatchPrint {
        let capturedOrder = order
        let isPayment = createPayment
        Task {
            if isPayment {
                // Payment confirmed → receipt + any kitchen/bar printers with printOnPayment=true
                await PrintService.shared.dispatchReceipt(capturedOrder)
            } else {
                // Sent to kitchen → kitchen/bar/sticker printers with printOnOrder=true, new items only
                await PrintService.shared.dispatchKitchenOrder(capturedOrder)
            }
        }
    }

    return order
}

    private func handlePromotionInventoryEffects(
    promotion: Promotion,
    order: Order,
    activeBranch: Branch?,
    modelContext: ModelContext
) {
    switch promotion.discountType {
    case "buy_x_get_y":
        handleBuyXGetY(promotion: promotion, order: order, activeBranch: activeBranch, modelContext: modelContext)

    case "bundle_price":
        handleBundlePriceDeduction(promotion: promotion, order: order, activeBranch: activeBranch, modelContext: modelContext)

    default:
        break // percentage, fixed, buy_x_pay_y — no extra inventory effect beyond normal deduction
    }
}

    private func handleBuyXGetY(
    promotion: Promotion,
    order: Order,
    activeBranch: Branch?,
    modelContext: ModelContext
) {
    guard let triggerItemId = promotion.appliesToMenuItemId,
          promotion.requiredQuantity > 0,
          promotion.rewardQuantity > 0 else { return }

    let rewardItemId = promotion.effectiveRewardMenuItemId ?? triggerItemId

    // If reward item is the SAME as trigger item, inventory is already deducted
    // because the customer already has all items in their cart (they just get Y of them free price-wise)
    guard rewardItemId != triggerItemId else { return }

    // Reward item DIFFERS from trigger — need to add it to the order and deduct its inventory
    guard let rewardMenuItem = fetchMenuItem(id: rewardItemId, modelContext: modelContext) else { return }

    // Calculate how many reward items to give based on how many trigger items are in the cart
    let triggerQtyInCart = cart.filter { $0.item.id == triggerItemId }.reduce(0) { $0 + $1.quantity }
    // For different-item reward, groupSize is just requiredQuantity (customer doesn't need reward item in cart)
    let rewardGroups = triggerQtyInCart / promotion.requiredQuantity
    let totalRewardQty = rewardGroups * promotion.rewardQuantity

    guard totalRewardQty > 0 else { return }

    // Add reward item to order at price = 0 (it's free)
    let rewardOrderItem = OrderItem(
        order: order,
        menuItem: rewardMenuItem,
        quantity: totalRewardQty,
        unitPrice: 0.0,
        notes: "🎁 Promo reward: \(promotion.title)",
        status: "cooking"
    )
    modelContext.insert(rewardOrderItem)
    rewardOrderItem.order = order
    order.items.append(rewardOrderItem)

    // Deduct inventory for the reward item
    let rewardCartItem = CartItem(item: rewardMenuItem, selectedModifiers: [], quantity: totalRewardQty)
    deductIngredientsLocally(
        for: rewardCartItem,
        activeBranch: activeBranch,
        baseReferenceId: rewardOrderItem.id
    )
}

    private func handleBundlePriceDeduction(
    promotion: Promotion,
    order: Order,
    activeBranch: Branch?,
    modelContext: ModelContext
) {
    // Only process if promotion uses the new PromotionBundleItem model
    guard !promotion.bundleItems.isEmpty else { return }

    // Determine how many bundles were triggered
    // If appliesToMenuItemId is set, count by that item's quantity in cart
    var bundleCount = 1
    if let triggerItemId = promotion.appliesToMenuItemId, promotion.requiredQuantity > 0 {
        let triggerQtyInCart = cart.filter { $0.item.id == triggerItemId }.reduce(0) { $0 + $1.quantity }
        bundleCount = triggerQtyInCart / promotion.requiredQuantity
    }

    guard bundleCount > 0 else { return }

    // For each bundle component, check if it's already in the cart
    let cartItemIds = Set(cart.map { $0.item.id })

    for bundleItem in promotion.bundleItems.filter({ !$0.isDeleted }) {
        guard let menuItem = bundleItem.menuItem else { continue }

        // If this bundle component is already in the cart, inventory was already deducted
        if cartItemIds.contains(menuItem.id) { continue }

        let totalQty = bundleItem.quantity * bundleCount

        // Add to order as part of the bundle (price = 0, included in bundle price)
        let bundleOrderItem = OrderItem(
            order: order,
            menuItem: menuItem,
            quantity: totalQty,
            unitPrice: 0.0,
            notes: "📦 Bundle component: \(promotion.title)",
            status: "cooking"
        )
        modelContext.insert(bundleOrderItem)
        bundleOrderItem.order = order
        order.items.append(bundleOrderItem)

        // Deduct inventory for this bundle component
        let syntheticCartItem = CartItem(item: menuItem, selectedModifiers: [], quantity: totalQty)
        deductIngredientsLocally(
            for: syntheticCartItem,
            activeBranch: activeBranch,
            baseReferenceId: bundleOrderItem.id
        )
    }
}


    func recallHeldOrder(_ order: Order) {
        cart.removeAll()
        guestCount = order.guestCount
        cashierName = order.cashierName
        selectedOrderType = order.orderType
        currentBillNumber = order.orderNumber
        if let q = order.queueNumber {
            currentQueueNumber = q
        }
        selectedCustomer = order.customer

        for orderItem in order.items.filter({ !$0.isDeleted }) {
            if let menuItem = orderItem.menuItem {
                let selectedModifiers = orderItem.modifiers.compactMap { $0.modifier }
                let cartItem = CartItem(
                    item: menuItem,
                    selectedModifiers: selectedModifiers,
                    quantity: orderItem.quantity,
                    notes: orderItem.notes ?? ""
                )
                cart.append(cartItem)
            }
        }

        order.isDeleted = true
        order.isSynced = false
        order.updatedAt = Date()

        try? modelContext?.save()
    }

    func holdCurrentCart() {
        guard let modelContext = modelContext, !cart.isEmpty else { return }
        let activeBranch = fetchActiveBranch(context: modelContext)

        let finalOrderNum = currentBillNumber == "AP-NEW" ? "ORD-\(DateFormatter.orderDateFormat().string(from: Date()))-\(Int.random(in: 100...999))" : currentBillNumber
        let appliedPromotion = activePromotion
        let appliedDiscount = cartDiscount
        let order = Order(
            orderNumber: finalOrderNum,
            tableSession: nil,
            orderType: selectedOrderType,
            status: "held",
            subtotal: cartSubtotal,
            tax: cartTax,
            serviceCharge: cartServiceCharge,
            discount: appliedDiscount,
            total: cartTotal,
            branch: activeBranch,
            guestCount: guestCount,
            cashierName: cashierName,
            queueNumber: currentQueueNumber.isEmpty ? nil : currentQueueNumber
        )
        order.customer = selectedCustomer
        order.heldAt = Date()

        modelContext.insert(order)

        if let appliedPromotion, appliedDiscount > 0 {
            let discount = OrderDiscount(
                order: order,
                promotion: appliedPromotion,
                discountType: appliedPromotion.discountType,
                discountValue: appliedPromotion.discountValue,
                discountAmount: appliedDiscount,
                reason: "Auto-applied promotion: \(appliedPromotion.title)"
            )
            modelContext.insert(discount)
        }

        for cartItem in cart {
            let orderItem = OrderItem(
                order: order,
                menuItem: cartItem.item,
                quantity: cartItem.quantity,
                unitPrice: cartItem.item.price,
                notes: cartItem.notes,
                status: "cooking"
            )
            modelContext.insert(orderItem)
            orderItem.order = order
            order.items.append(orderItem)

            for mod in cartItem.selectedModifiers {
                let orderItemMod = OrderItemModifier(orderItem: orderItem, modifier: mod, price: mod.extraPrice)
                modelContext.insert(orderItemMod)
                orderItemMod.orderItem = orderItem
                orderItem.modifiers.append(orderItemMod)
            }
        }

        do {
            try modelContext.save()
        } catch {
            print("POSViewModel [Hold Order Save Error]: \(error.localizedDescription)")
        }
        cart.removeAll()
        selectedCustomer = nil
        currentQueueNumber = ""
        currentBillNumber = "AP-NEW"

        let auditLog = AuditLog(
            actionType: "order_held",
            details: "Held cart order \(finalOrderNum) — Total: ฿\(String(format: "%.2f", order.total))",
            originalValue: order.total,
            newValue: order.total
        )
        modelContext.insert(auditLog)
        modelContext.saveWithLogging(label: #function)

        APHaptic.trigger()
    }

    private func deductIngredientsLocally(
        for cartItem: CartItem,
        activeBranch: Branch?,
        baseReferenceId: UUID? = nil,
        modifierReferenceIds: [UUID] = [],
        branchInventoryCache: [String: InventoryItem]? = nil
    ) {
    guard let modelContext = modelContext else { return }

    // Base menu recipes deduction
    for recipe in cartItem.item.recipes {
        if let ingredient = recipe.inventoryItem {
            var localItem = ingredient
            if let activeBranch = activeBranch, ingredient.branch?.id != activeBranch.id {
                // Use pre-fetched cache to avoid N+1 fetch inside loop
                let key = ingredient.sku ?? ingredient.name
                if let cached = branchInventoryCache?[key] {
                    localItem = cached
                }
            }

            let qtyDeducted = recipe.quantityRequired * Double(cartItem.quantity)
            localItem.currentQuantity -= qtyDeducted
            localItem.updatedAt = Date()
            localItem.isSynced = false
            
            // Consume from FEFO lots to keep lots in sync with currentQuantity
            let expiryManager = InventoryExpiryManager.shared(for: modelContext)
            expiryManager.consumeFEFO(item: localItem, quantity: qtyDeducted)

            let txn = InventoryTransaction(
                item: localItem,
                transactionType: InventoryMovementType.sell.rawValue,
                quantity: -qtyDeducted,
                referenceId: baseReferenceId,
                notes: "Local POS checkout deduct for \(cartItem.item.name) (Qty: \(cartItem.quantity))",
                branch: activeBranch
            )
            modelContext.insert(txn)
        }
    }

    // Modifier recipes deduction
    for (index, mod) in cartItem.selectedModifiers.enumerated() {
        if let ingredient = mod.inventoryItemLink, let reqQty = mod.quantityRequired {
            var localItem = ingredient
            if let activeBranch = activeBranch, ingredient.branch?.id != activeBranch.id {
                let key = ingredient.sku ?? ingredient.name
                if let cached = branchInventoryCache?[key] {
                    localItem = cached
                }
            }

            let qtyDeducted = reqQty * Double(cartItem.quantity)
            localItem.currentQuantity -= qtyDeducted
            localItem.updatedAt = Date()
            localItem.isSynced = false
            
            // Consume from FEFO lots to keep lots in sync with currentQuantity
            let expiryManager = InventoryExpiryManager.shared(for: modelContext)
            expiryManager.consumeFEFO(item: localItem, quantity: qtyDeducted)

            let txn = InventoryTransaction(
                item: localItem,
                transactionType: InventoryMovementType.sell.rawValue,
                quantity: -qtyDeducted,
                referenceId: modifierReferenceIds.indices.contains(index) ? modifierReferenceIds[index] : baseReferenceId,
                notes: "Modifier deduct: \(mod.name) for \(cartItem.item.name) (Qty: \(cartItem.quantity))",
                branch: activeBranch
            )
            modelContext.insert(txn)
        }
    }
}

    func reverseInventoryDeduction(for order: Order, specificItems: [OrderItem]? = nil) {
    guard let modelContext = modelContext else { return }

    let itemsToReverse = specificItems ?? order.items.filter { !$0.isDeleted && $0.status != "cancelled" }
    let activeBranch = order.branch

    for orderItem in itemsToReverse {
        guard let menuItem = orderItem.menuItem else { continue }

        // Reverse base recipe deductions
        for recipe in menuItem.recipes {
            guard let ingredient = recipe.inventoryItem else { continue }

            let localItem = findBranchInventoryItem(
                ingredient: ingredient,
                activeBranch: activeBranch,
                modelContext: modelContext
            )

            let qtyToRestore = recipe.quantityRequired * Double(orderItem.quantity)
            localItem.currentQuantity += qtyToRestore
            localItem.updatedAt = Date()
            localItem.isSynced = false

            let txn = InventoryTransaction(
                item: localItem,
                transactionType: InventoryMovementType.refundReturn.rawValue,
                quantity: qtyToRestore,
                referenceId: orderItem.id,
                notes: "Refund return: \(menuItem.name) (Qty: \(orderItem.quantity)) — Order: \(order.orderNumber)",
                branch: activeBranch
            )
            modelContext.insert(txn)
        }

        // Reverse modifier deductions
        for orderItemMod in orderItem.modifiers {
            guard let modifier = orderItemMod.modifier,
                  let ingredient = modifier.inventoryItemLink,
                  let reqQty = modifier.quantityRequired else { continue }

            let localItem = findBranchInventoryItem(
                ingredient: ingredient,
                activeBranch: activeBranch,
                modelContext: modelContext
            )

            let qtyToRestore = reqQty * Double(orderItem.quantity)
            localItem.currentQuantity += qtyToRestore
            localItem.updatedAt = Date()
            localItem.isSynced = false

            let txn = InventoryTransaction(
                item: localItem,
                transactionType: InventoryMovementType.refundReturn.rawValue,
                quantity: qtyToRestore,
                referenceId: orderItemMod.id,
                notes: "Refund return modifier: \(modifier.name) for \(menuItem.name) — Order: \(order.orderNumber)",
                branch: activeBranch
            )
            modelContext.insert(txn)
        }
    }

    modelContext.saveWithLogging(label: #function)

    Task {
        await SyncEngine.shared.syncAll(modelContext: modelContext)
    }
}

    private func findBranchInventoryItem(
    ingredient: InventoryItem,
    activeBranch: Branch?,
    modelContext: ModelContext
) -> InventoryItem {
    guard let activeBranch = activeBranch, ingredient.branch?.id != activeBranch.id else {
        return ingredient
    }

    let itemDesc = FetchDescriptor<InventoryItem>()
    if let allItems = try? modelContext.fetch(itemDesc),
       let match = allItems.first(where: {
           $0.branch?.id == activeBranch.id && ($0.sku == ingredient.sku || $0.name == ingredient.name)
       }) {
        return match
    }

    // Fallback: return the original if no branch-specific match found
    return ingredient
}

    private func fetchMenuItem(id: String, modelContext: ModelContext) -> MenuItem? {
    let descriptor = FetchDescriptor<MenuItem>()
    guard let items = try? modelContext.fetch(descriptor) else { return nil }
    return items.first(where: { $0.id == id && !$0.isDeleted })
}


    // MARK: - Database Mock Seed data

    func seedSampleMenu() {
        guard let modelContext = modelContext else { return }
        SampleDataSeeder.seedAll(modelContext: modelContext)
    }
}

// MARK: - Reusable Sample Data Seeder

@MainActor
final class SampleDataSeeder {
    static func clearAllData(modelContext: ModelContext) {
        // Fetch and delete each model type explicitly to avoid complex existential issues in SwiftData
        if let items = try? modelContext.fetch(FetchDescriptor<Role>()) {
            for item in items { modelContext.delete(item) }
        }
        if let items = try? modelContext.fetch(FetchDescriptor<User>()) {
            for item in items { modelContext.delete(item) }
        }
        if let items = try? modelContext.fetch(FetchDescriptor<Employee>()) {
            for item in items { modelContext.delete(item) }
        }
        if let items = try? modelContext.fetch(FetchDescriptor<EmployeeShift>()) {
            for item in items { modelContext.delete(item) }
        }
        if let items = try? modelContext.fetch(FetchDescriptor<Timecard>()) {
            for item in items { modelContext.delete(item) }
        }
        if let items = try? modelContext.fetch(FetchDescriptor<RegisterSession>()) {
            for item in items { modelContext.delete(item) }
        }
        if let items = try? modelContext.fetch(FetchDescriptor<Supplier>()) {
            for item in items { modelContext.delete(item) }
        }
        if let items = try? modelContext.fetch(FetchDescriptor<Branch>()) {
            for item in items { modelContext.delete(item) }
        }
        if let items = try? modelContext.fetch(FetchDescriptor<PurchaseOrder>()) {
            for item in items { modelContext.delete(item) }
        }
        if let items = try? modelContext.fetch(FetchDescriptor<PurchaseOrderItem>()) {
            for item in items { modelContext.delete(item) }
        }
        if let items = try? modelContext.fetch(FetchDescriptor<DeliveryPrice>()) {
            for item in items { modelContext.delete(item) }
        }
        if let tables = try? modelContext.fetch(FetchDescriptor<RestaurantTable>()) {
            for item in tables { modelContext.delete(item) }
        }
        if let sessions = try? modelContext.fetch(FetchDescriptor<TableSession>()) {
            for item in sessions { modelContext.delete(item) }
        }
        if let items = try? modelContext.fetch(FetchDescriptor<MenuItem>()) {
            for item in items { modelContext.delete(item) }
        }
        if let categories = try? modelContext.fetch(FetchDescriptor<Category>()) {
            for item in categories { modelContext.delete(item) }
        }
        if let groups = try? modelContext.fetch(FetchDescriptor<ModifierGroup>()) {
            for item in groups { modelContext.delete(item) }
        }
        if let modifiers = try? modelContext.fetch(FetchDescriptor<Modifier>()) {
            for item in modifiers { modelContext.delete(item) }
        }
        if let rels = try? modelContext.fetch(FetchDescriptor<MenuItemModifierGroup>()) {
            for item in rels { modelContext.delete(item) }
        }
        if let items = try? modelContext.fetch(FetchDescriptor<InventoryItem>()) {
            for item in items { modelContext.delete(item) }
        }
        if let recipes = try? modelContext.fetch(FetchDescriptor<Recipe>()) {
            for item in recipes { modelContext.delete(item) }
        }
        if let orders = try? modelContext.fetch(FetchDescriptor<Order>()) {
            for item in orders { modelContext.delete(item) }
        }
        if let items = try? modelContext.fetch(FetchDescriptor<OrderItem>()) {
            for item in items { modelContext.delete(item) }
        }
        if let mods = try? modelContext.fetch(FetchDescriptor<OrderItemModifier>()) {
            for item in mods { modelContext.delete(item) }
        }
        if let payments = try? modelContext.fetch(FetchDescriptor<Payment>()) {
            for item in payments { modelContext.delete(item) }
        }
        if let txns = try? modelContext.fetch(FetchDescriptor<InventoryTransaction>()) {
            for item in txns { modelContext.delete(item) }
        }
        modelContext.saveWithLogging(label: #function)
    }

    static func seedTables(modelContext: ModelContext) {
        // Delete existing tables first
        if let tables = try? modelContext.fetch(FetchDescriptor<RestaurantTable>()) {
            for table in tables {
                modelContext.delete(table)
            }
        }

        let sampleTables = [
            // Floor 1 Tables
            RestaurantTable(
                tableNumber: "1", capacity: 2, status: "vacant",
                qrCodeIdentifier: "t1_static_hash", positionX: 40, positionY: 40, floor: 1
            ),
            RestaurantTable(
                tableNumber: "2", capacity: 4, status: "vacant",
                qrCodeIdentifier: "t2_static_hash", positionX: 200, positionY: 40, floor: 1
            ),
            RestaurantTable(
                tableNumber: "3", capacity: 4, status: "vacant",
                qrCodeIdentifier: "t3_static_hash", positionX: 380, positionY: 40, floor: 1
            ),
            RestaurantTable(
                tableNumber: "4", capacity: 6, status: "vacant",
                qrCodeIdentifier: "t4_static_hash", positionX: 40, positionY: 200, floor: 1
            ),
            RestaurantTable(
                tableNumber: "5", capacity: 8, status: "vacant",
                qrCodeIdentifier: "t5_static_hash", positionX: 320, positionY: 200, floor: 1
            ),
            RestaurantTable(
                tableNumber: "VIP 1", capacity: 10, status: "vacant",
                qrCodeIdentifier: "tvip1_static_hash", positionX: 140, positionY: 360, floor: 1
            ),
            // Floor 2 Tables
            RestaurantTable(
                tableNumber: "201", capacity: 4, status: "vacant",
                qrCodeIdentifier: "t201_static_hash", positionX: 60, positionY: 60, floor: 2
            ),
            RestaurantTable(
                tableNumber: "202", capacity: 4, status: "vacant",
                qrCodeIdentifier: "t202_static_hash", positionX: 240, positionY: 60, floor: 2
            ),
            RestaurantTable(
                tableNumber: "203", capacity: 6, status: "vacant",
                qrCodeIdentifier: "t203_static_hash", positionX: 420, positionY: 60, floor: 2
            ),
            // Floor 3 Tables
            RestaurantTable(
                tableNumber: "301 (ROOF)", capacity: 8, status: "vacant",
                qrCodeIdentifier: "t301_static_hash", positionX: 120, positionY: 120, floor: 3
            )
        ]

        for table in sampleTables {
            modelContext.insert(table)
        }
        modelContext.saveWithLogging(label: #function)
    }

    static func seedRolesAndEmployeesIfEmpty(modelContext: ModelContext) {
        let roles = (try? modelContext.fetch(FetchDescriptor<Role>())) ?? []
        if roles.isEmpty {
            let roleManager = Role(name: "Store Manager", roleDescription: "Full administrative and settings access.", permissionKeys: PermissionService.permissionCSV(for: PermissionService.permissions(forRoleName: "Store Manager")))
            let roleCashier = Role(name: "Cashier", roleDescription: "Checkout, payments, and order entry.", permissionKeys: PermissionService.permissionCSV(for: PermissionService.permissions(forRoleName: "Cashier")))
            let roleWaitstaff = Role(name: "Waitstaff", roleDescription: "Table ordering and service requests.", permissionKeys: PermissionService.permissionCSV(for: PermissionService.permissions(forRoleName: "Waitstaff")))
            let roleKitchen = Role(name: "Kitchen Staff", roleDescription: "Kitchen display system access.", permissionKeys: PermissionService.permissionCSV(for: PermissionService.permissions(forRoleName: "Kitchen Staff")))

            modelContext.insert(roleManager)
            modelContext.insert(roleCashier)
            modelContext.insert(roleWaitstaff)
            modelContext.insert(roleKitchen)

            // Seed default users and employees if empty
            let employees = (try? modelContext.fetch(FetchDescriptor<Employee>())) ?? []
            if employees.isEmpty {
                // Fixed UUIDs ensure that employeeId references stored in staff_sessions,
                // audit_logs and timecards remain valid after a re-seed.
                // DO NOT change these constants — they are the canonical seed identities.
                let seedEmp1Id  = UUID(uuidString: "9a5767a4-6f30-4614-94d9-5ea85e282775")!
                let seedEmp2Id  = UUID(uuidString: "193df239-104d-4e2d-b2e5-9f2b4ff30ddc")!
                let seedUser1Id = UUID(uuidString: "11111111-1111-1111-1111-111111112001")!
                let seedUser2Id = UUID(uuidString: "11111111-1111-1111-1111-111111112002")!

                // Use plain sha256 for seed users — verifyPIN supports legacy format.
                // This avoids blocking the main thread with key-stretching on first launch.
                let user1 = User(id: seedUser1Id, username: "somchai", email: "somchai@alphapos.com", passwordHash: SecurityHelper.sha256("password"), pinCodeHash: SecurityHelper.sha256("1234"), role: roleManager, isSynced: false, isDeleted: false, updatedAt: Date())
                let user2 = User(id: seedUser2Id, username: "somsri", email: "somsri@alphapos.com", passwordHash: SecurityHelper.sha256("password"), pinCodeHash: SecurityHelper.sha256("5678"), role: roleWaitstaff, isSynced: false, isDeleted: false, updatedAt: Date())
                modelContext.insert(user1)
                modelContext.insert(user2)

                let emp1 = Employee(id: seedEmp1Id, user: user1, firstName: "Somchai", lastName: "Suksabai", phone: "081-234-5678", nationalId: "1234567890123", employmentType: "monthly", payRate: 25000.0, isSynced: false, isDeleted: false, updatedAt: Date())
                let emp2 = Employee(id: seedEmp2Id, user: user2, firstName: "Somsri", lastName: "Jaidee", phone: "089-876-5432", nationalId: "9876543210987", employmentType: "hourly", payRate: 75.0, isSynced: false, isDeleted: false, updatedAt: Date())
                modelContext.insert(emp1)
                modelContext.insert(emp2)
            }
            modelContext.saveWithLogging(label: #function)
        }
    }

    static func clearCatalogOnly(modelContext: ModelContext) {
        if let items = try? modelContext.fetch(FetchDescriptor<RestaurantTable>()) {
            for item in items { modelContext.delete(item) }
        }
        if let items = try? modelContext.fetch(FetchDescriptor<MenuItem>()) {
            for item in items { modelContext.delete(item) }
        }
        if let categories = try? modelContext.fetch(FetchDescriptor<Category>()) {
            for item in categories { modelContext.delete(item) }
        }
        if let groups = try? modelContext.fetch(FetchDescriptor<ModifierGroup>()) {
            for item in groups { modelContext.delete(item) }
        }
        if let modifiers = try? modelContext.fetch(FetchDescriptor<Modifier>()) {
            for item in modifiers { modelContext.delete(item) }
        }
        if let rels = try? modelContext.fetch(FetchDescriptor<MenuItemModifierGroup>()) {
            for item in rels { modelContext.delete(item) }
        }
        if let items = try? modelContext.fetch(FetchDescriptor<InventoryItem>()) {
            for item in items { modelContext.delete(item) }
        }
        if let recipes = try? modelContext.fetch(FetchDescriptor<Recipe>()) {
            for item in recipes { modelContext.delete(item) }
        }
        modelContext.saveWithLogging(label: #function)
    }

    static func autoSeedIfOutdated(modelContext: ModelContext) {
        // M9 Safety: never auto-seed in production — only allowed in debug/developer mode
        // This function is already guarded by developerModeEnabled in MainDashboardView,
        // but we add a compile-time guard here as an extra layer of protection
        #if !DEBUG
        // In release builds, skip destructive re-seed — only seed missing roles/employees
        seedRolesAndEmployeesIfEmpty(modelContext: modelContext)
        return
        #endif
        seedRolesAndEmployeesIfEmpty(modelContext: modelContext)
        let categories = (try? modelContext.fetch(FetchDescriptor<Category>())) ?? []
        if categories.isEmpty {
            seedCatalogOnly(modelContext: modelContext)
            return
        }

        let oldCategoryNames = ["Burgers & Mains", "Coffee & Drinks"]
        let hasOldCategories = categories.contains(where: { oldCategoryNames.contains($0.name) })

        let menuItems = (try? modelContext.fetch(FetchDescriptor<MenuItem>())) ?? []
        let oldMenuItemNames = ["Classic Cheese Burger", "Espresso Hot", "Latte Iced",
                                "Crispy Golden Spring Rolls", "Royal Emerald Green Curry",
                                "Signature River Prawn Pad Thai", "Traditional Thai Iced Tea"]
        let hasOldMenuItems = menuItems.contains(where: { oldMenuItemNames.contains($0.name) })
        let isMissingNewItems = menuItems.count < 50

        if hasOldCategories || hasOldMenuItems || isMissingNewItems {
            #if DEBUG
            print("SampleDataSeeder [AutoSeed]: Outdated or mismatched menu items detected. Re-seeding...")
            #endif
            seedCatalogOnly(modelContext: modelContext)
        }
    }

    static func seedCatalogOnly(modelContext: ModelContext) {
        clearCatalogOnly(modelContext: modelContext)

        // 1. Seed Tables
        let sampleTables = [
            // Floor 1 Tables
            RestaurantTable(
                tableNumber: "1", capacity: 2, status: "vacant",
                qrCodeIdentifier: "t1_static_hash", positionX: 40, positionY: 40, floor: 1
            ),
            RestaurantTable(
                tableNumber: "2", capacity: 4, status: "vacant",
                qrCodeIdentifier: "t2_static_hash", positionX: 200, positionY: 40, floor: 1
            ),
            RestaurantTable(
                tableNumber: "3", capacity: 4, status: "vacant",
                qrCodeIdentifier: "t3_static_hash", positionX: 380, positionY: 40, floor: 1
            ),
            RestaurantTable(
                tableNumber: "4", capacity: 6, status: "vacant",
                qrCodeIdentifier: "t4_static_hash", positionX: 40, positionY: 200, floor: 1
            ),
            RestaurantTable(
                tableNumber: "5", capacity: 8, status: "vacant",
                qrCodeIdentifier: "t5_static_hash", positionX: 320, positionY: 200, floor: 1
            ),
            RestaurantTable(
                tableNumber: "VIP 1", capacity: 10, status: "vacant",
                qrCodeIdentifier: "tvip1_static_hash", positionX: 140, positionY: 360, floor: 1
            ),
            // Floor 2 Tables
            RestaurantTable(
                tableNumber: "201", capacity: 4, status: "vacant",
                qrCodeIdentifier: "t201_static_hash", positionX: 60, positionY: 60, floor: 2
            ),
            RestaurantTable(
                tableNumber: "202", capacity: 4, status: "vacant",
                qrCodeIdentifier: "t202_static_hash", positionX: 240, positionY: 60, floor: 2
            ),
            RestaurantTable(
                tableNumber: "203", capacity: 6, status: "vacant",
                qrCodeIdentifier: "t203_static_hash", positionX: 420, positionY: 60, floor: 2
            ),
            // Floor 3 Tables
            RestaurantTable(
                tableNumber: "301 (ROOF)", capacity: 8, status: "vacant",
                qrCodeIdentifier: "t301_static_hash", positionX: 120, positionY: 120, floor: 3
            )
        ]

        for table in sampleTables {
            modelContext.insert(table)
        }

        // 2. Ingredients (Inventory Items)
        let prawns = InventoryItem(name: "Giant River Prawn", sku: "ING-PRAWN", unit: "piece", currentQuantity: 200, reorderLevel: 30, costPrice: 50.0)
        let noodles = InventoryItem(name: "Rice Noodles", sku: "ING-NOODLE", unit: "g", currentQuantity: 10000, reorderLevel: 2000, costPrice: 0.05)
        let chicken = InventoryItem(name: "Chicken Breast", sku: "ING-CHICKEN", unit: "g", currentQuantity: 8000, reorderLevel: 1500, costPrice: 0.12)
        let curryPaste = InventoryItem(name: "Green Curry Paste", sku: "ING-CURRY", unit: "g", currentQuantity: 3000, reorderLevel: 500, costPrice: 0.08)
        let coconutMilk = InventoryItem(name: "Coconut Milk", sku: "ING-COCONUT", unit: "ml", currentQuantity: 15000, reorderLevel: 3000, costPrice: 0.04)
        let beefShank = InventoryItem(name: "Beef Shank", sku: "ING-BEEF", unit: "g", currentQuantity: 5000, reorderLevel: 1000, costPrice: 0.25)
        let mango = InventoryItem(name: "Honey Mango", sku: "ING-MANGO", unit: "piece", currentQuantity: 150, reorderLevel: 25, costPrice: 15.0)
        let sweetRice = InventoryItem(name: "Glutinous Rice", sku: "ING-SWEETRICE", unit: "g", currentQuantity: 10000, reorderLevel: 2000, costPrice: 0.03)
        let teaLeaves = InventoryItem(name: "Thai Tea Leaves", sku: "ING-TEA", unit: "g", currentQuantity: 2000, reorderLevel: 500, costPrice: 0.3)

        modelContext.insert(prawns)
        modelContext.insert(noodles)
        modelContext.insert(chicken)
        modelContext.insert(curryPaste)
        modelContext.insert(coconutMilk)
        modelContext.insert(beefShank)
        modelContext.insert(mango)
        modelContext.insert(sweetRice)
        modelContext.insert(teaLeaves)

        // 3. Categories
        let mainsCat = Category(name: "Main Dishes")
        let appCat = Category(name: "Appetizers")
        let drinkCat = Category(name: "Beverages")

        modelContext.insert(mainsCat)
        modelContext.insert(appCat)
        modelContext.insert(drinkCat)

        // 4. Modifiers Setup (preserved for future use)
        let sugarGroup = ModifierGroup(name: "Sweetness Level", minSelection: 1, maxSelection: 1)
        let extraGroup = ModifierGroup(name: "Extras Options", minSelection: 0, maxSelection: 1)

        modelContext.insert(sugarGroup)
        modelContext.insert(extraGroup)

        let sugarNormal = Modifier(modifierGroup: sugarGroup, name: "Sweet Normal", extraPrice: 0.0)
        let sugarLess = Modifier(modifierGroup: sugarGroup, name: "Sweet 50%", extraPrice: 0.0)
        let sugarNone = Modifier(modifierGroup: sugarGroup, name: "Unsweetened", extraPrice: 0.0)

        modelContext.insert(sugarNormal)
        modelContext.insert(sugarLess)
        modelContext.insert(sugarNone)

        // 5. Isan Menu Items — 25 Mains
        let items: [MenuItem] = [
            // Mains (25)
            MenuItem(id: "isan1", name: "Classic Som Tum Thai", itemDescription: "Green papaya salad with peanuts, dried shrimp, lime, palm sugar, and fish sauce.", price: 85.0, imageUrl: "https://images.unsplash.com/photo-1626132647523-66f5bf380027?w=400&q=80", category: mainsCat, isBestseller: true),
            MenuItem(id: "isan2", name: "Som Tum Boo Plarah", itemDescription: "Papaya salad with fermented fish sauce, salted crab, and fresh Thai herbs.", price: 90.0, imageUrl: "https://images.unsplash.com/photo-1625813506062-0aeb1d7a094b?w=400&q=80", category: mainsCat),
            MenuItem(id: "isan3", name: "Som Tum Korat", itemDescription: "Papaya salad combining Som Tum Thai and Boo Plarah styles with rice noodles.", price: 95.0, imageUrl: "https://images.unsplash.com/photo-1617470703128-26a0fc9af10f?w=400&q=80", category: mainsCat),
            MenuItem(id: "isan4", name: "Som Tum Suan Pak", itemDescription: "Herbal papaya salad with seasonal Isan wild vegetables and bitter herbs.", price: 100.0, imageUrl: "https://images.unsplash.com/photo-1540420773420-3366772f4999?w=400&q=80", category: mainsCat),
            MenuItem(id: "isan5", name: "Som Tum Tard Platter", itemDescription: "Platter-sized papaya salad served with boiled eggs, pork cracklings, and noodles.", price: 220.0, imageUrl: "https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=400&q=80", category: mainsCat),
            MenuItem(id: "isan6", name: "Tum Corn with Salted Egg", itemDescription: "Sweet yellow corn salad tossed with rich salted egg yolk and lime juice.", price: 110.0, imageUrl: "https://images.unsplash.com/photo-1551248429-40975aa4de74?w=400&q=80", category: mainsCat),
            MenuItem(id: "isan7", name: "Tum Cucumber (Tum Tang)", itemDescription: "Spicy cucumber salad with fermented fish sauce, chilies, and garlic.", price: 80.0, imageUrl: "https://images.unsplash.com/photo-1603052875302-d376b7c0638a?w=400&q=80", category: mainsCat),
            MenuItem(id: "isan8", name: "Tum Tray Seafood", itemDescription: "Papaya salad platter served with giant river prawns, green mussels, and squid.", price: 250.0, imageUrl: "https://images.unsplash.com/photo-1534422298391-e4f8c172dddb?w=400&q=80", category: mainsCat),
            MenuItem(id: "isan9", name: "Spicy Minced Pork Larb", itemDescription: "Minced pork salad with roasted ground rice, mint, lime, and dried chili.", price: 120.0, imageUrl: "https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=400&q=80", category: mainsCat, isBestseller: true),
            MenuItem(id: "isan10", name: "Spicy Minced Chicken Larb", itemDescription: "Minced chicken breast salad seasoned with Isan herbs and fresh lime juice.", price: 120.0, imageUrl: "https://images.unsplash.com/photo-1606787366850-de6330128bfc?w=400&q=80", category: mainsCat),
            MenuItem(id: "isan11", name: "Spicy Minced Duck Larb", itemDescription: "Authentic minced duck salad seasoned with roasted ground rice, mint, and galangal.", price: 140.0, imageUrl: "https://images.unsplash.com/photo-1512621776951-a57141f2eefd?w=400&q=80", category: mainsCat),
            MenuItem(id: "isan12", name: "Larb Woon Sen (Glass Noodle)", itemDescription: "Spicy glass noodle salad with minced pork, red onions, lime, and chilies.", price: 115.0, imageUrl: "https://images.unsplash.com/photo-1569718212165-3a8278d5f624?w=400&q=80", category: mainsCat),
            MenuItem(id: "isan13", name: "Larb Mushroom (Vegetarian)", itemDescription: "Vegetarian Larb with mixed forest mushrooms, mint, and roasted rice powder.", price: 105.0, imageUrl: "https://images.unsplash.com/photo-1544025162-d76694265947?w=400&q=80", category: mainsCat),
            MenuItem(id: "isan14", name: "Nam Tok Moo (Pork Salad)", itemDescription: "Grilled sliced pork collar salad with roasted ground rice, chili, and fresh mint.", price: 130.0, imageUrl: "https://images.unsplash.com/photo-1544025162-d76694265947?w=400&q=80", category: mainsCat),
            MenuItem(id: "isan15", name: "Nam Tok Neua (Beef Salad)", itemDescription: "Grilled sliced beef ribeye salad with authentic Isan herbs and lime dressing.", price: 160.0, imageUrl: "https://images.unsplash.com/photo-1544025162-d76694265947?w=400&q=80", category: mainsCat),
            MenuItem(id: "isan16", name: "Sup Nor Mai (Bamboo Salad)", itemDescription: "Spicy warm shredded bamboo shoot salad infused with aromatic yanang leaf juice.", price: 95.0, imageUrl: "https://images.unsplash.com/photo-1540420773420-3366772f4999?w=400&q=80", category: mainsCat),
            MenuItem(id: "isan17", name: "Tom Zap Pork Ribs", itemDescription: "Hot, sour, and aromatic soup with tender pork ribs and fresh lemongrass.", price: 150.0, imageUrl: "https://images.unsplash.com/photo-1547592180-85f173990554?w=400&q=80", category: mainsCat),
            MenuItem(id: "isan18", name: "Tom Zap Beef Shank", itemDescription: "Spicy herbal soup with slow-braised beef shank, toasted rice, and fresh lime.", price: 180.0, imageUrl: "https://images.unsplash.com/photo-1547592180-85f173990554?w=400&q=80", category: mainsCat),
            MenuItem(id: "isan19", name: "Kaeng Om Pork (Isan Curry)", itemDescription: "Isan herbal soup with pork, dill, cabbage, pumpkin, and yanang juice.", price: 140.0, imageUrl: "https://images.unsplash.com/photo-1547592180-85f173990554?w=400&q=80", category: mainsCat),
            MenuItem(id: "isan20", name: "Kaeng Om Chicken", itemDescription: "Spicy herbal soup with chicken, dill, local vegetables, and roasted rice.", price: 135.0, imageUrl: "https://images.unsplash.com/photo-1547592180-85f173990554?w=400&q=80", category: mainsCat),
            MenuItem(id: "isan21", name: "Kaeng Pak Wahn with Ant Eggs", itemDescription: "Clear seasonal soup with wild star gooseberry leaves and premium ant eggs.", price: 150.0, imageUrl: "https://images.unsplash.com/photo-1547592180-85f173990554?w=400&q=80", category: mainsCat),
            MenuItem(id: "isan22", name: "Koi Neua (Beef Tartare)", itemDescription: "Isan-style raw minced beef salad with fresh chili, herbs, and bitter bile.", price: 175.0, imageUrl: "https://images.unsplash.com/photo-1544025162-d76694265947?w=400&q=80", category: mainsCat),
            MenuItem(id: "isan23", name: "Sizzling Moo Nam Tok", itemDescription: "Sizzling hot plate of grilled pork neck tossed with lime, herbs, and roasted rice.", price: 165.0, imageUrl: "https://images.unsplash.com/photo-1544025162-d76694265947?w=400&q=80", category: mainsCat),
            MenuItem(id: "isan24", name: "Yum Moo Yor (Pork Sausage)", itemDescription: "Spicy Vietnamese pork sausage salad with onions, tomatoes, and lime juice.", price: 110.0, imageUrl: "https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=400&q=80", category: mainsCat),
            MenuItem(id: "isan25", name: "Yum Glass Noodle Seafood", itemDescription: "Spicy salad with glass noodles, fresh river prawns, squid, and celery.", price: 160.0, imageUrl: "https://images.unsplash.com/photo-1569718212165-3a8278d5f624?w=400&q=80", category: mainsCat),

            // Appetizers (15)
            MenuItem(id: "isan26", name: "Classic Gai Yang (Half)", itemDescription: "Charcoal-grilled marinated chicken served with sweet chili and spicy Jaew sauces.", price: 180.0, imageUrl: "https://images.unsplash.com/photo-1626082927389-6cd097cdc6ec?w=400&q=80", category: appCat, isFavorite: true, isBestseller: true),
            MenuItem(id: "isan27", name: "Classic Gai Yang (Whole)", itemDescription: "Full-sized charcoal-grilled marinated chicken with authentic Isan spices.", price: 340.0, imageUrl: "https://images.unsplash.com/photo-1626082927389-6cd097cdc6ec?w=400&q=80", category: appCat),
            MenuItem(id: "isan28", name: "Moo Ping with Sticky Rice", itemDescription: "Three skewers of grilled sweet pork served with warm steamed sticky rice.", price: 95.0, imageUrl: "https://images.unsplash.com/photo-1582576163090-09d3b6f8a969?w=400&q=80", category: appCat, isBestseller: true),
            MenuItem(id: "isan29", name: "Kor Moo Yang (Pork Neck)", itemDescription: "Sliced charcoal-grilled pork neck served with spicy tamarind Jaew dipping sauce.", price: 150.0, imageUrl: "https://images.unsplash.com/photo-1603048588665-791ca8aea617?w=400&q=80", category: appCat),
            MenuItem(id: "isan30", name: "Suea Rong Hai (Crying Tiger)", itemDescription: "Charcoal-grilled marinated beef brisket served with dynamic chili Jaew sauce.", price: 220.0, imageUrl: "https://images.unsplash.com/photo-1544025162-d76694265947?w=400&q=80", category: appCat, isFavorite: true),
            MenuItem(id: "isan31", name: "Isan Sausage Skewers", itemDescription: "Grilled fermented pork and rice sausage served with ginger and cabbage leaves.", price: 110.0, imageUrl: "https://images.unsplash.com/photo-1582576163090-09d3b6f8a969?w=400&q=80", category: appCat),
            MenuItem(id: "isan32", name: "Sai Krok E-San Moo (Balls)", itemDescription: "Grilled round fermented pork and garlic sausage balls served with fresh chilies.", price: 110.0, imageUrl: "https://images.unsplash.com/photo-1582576163090-09d3b6f8a969?w=400&q=80", category: appCat),
            MenuItem(id: "isan33", name: "Fried Larb Balls (Larb Tod)", itemDescription: "Deep-fried spicy minced pork balls with roasted ground rice and lime leaves.", price: 115.0, imageUrl: "https://images.unsplash.com/photo-1544025162-d76694265947?w=400&q=80", category: appCat),
            MenuItem(id: "isan34", name: "Crispy Isan Chicken Wings", itemDescription: "Deep-fried marinated chicken wings tossed in garlic and light soy sauce.", price: 120.0, imageUrl: "https://images.unsplash.com/photo-1569058242253-92a9c755a0ec?w=400&q=80", category: appCat),
            MenuItem(id: "isan35", name: "Deep Fried Pork Ribs", itemDescription: "Crispy deep-fried marinated pork ribs topped with crispy golden garlic.", price: 140.0, imageUrl: "https://images.unsplash.com/photo-1544025162-d76694265947?w=400&q=80", category: appCat),
            MenuItem(id: "isan36", name: "Crispy Pork Crackling", itemDescription: "Crunchy deep-fried pork rinds, the perfect accompaniment for papaya salad.", price: 40.0, imageUrl: "https://images.unsplash.com/photo-1608039829572-78524f79c4c7?w=400&q=80", category: appCat),
            MenuItem(id: "isan37", name: "Fried Sun-Dried Pork (Moo Dad Deaw)", itemDescription: "Deep-fried sweet and salty marinated sun-dried pork strips.", price: 130.0, imageUrl: "https://images.unsplash.com/photo-1544025162-d76694265947?w=400&q=80", category: appCat),
            MenuItem(id: "isan38", name: "Fried Sun-Dried Beef (Neua Dad Deaw)", itemDescription: "Deep-fried marinated sun-dried beef strips served with chili sauce.", price: 160.0, imageUrl: "https://images.unsplash.com/photo-1544025162-d76694265947?w=400&q=80", category: appCat),
            MenuItem(id: "isan39", name: "Grilled River Prawn (Single)", itemDescription: "Charcoal grilled giant river prawn served with spicy garlic seafood sauce.", price: 145.0, imageUrl: "https://images.unsplash.com/photo-1559314809-0d155014e29e?w=400&q=80", category: appCat, isFavorite: true),
            MenuItem(id: "isan40", name: "Steamed Sticky Rice (Khao Niew)", itemDescription: "Warm steamed Thai glutinous rice served in a traditional bamboo basket.", price: 20.0, imageUrl: "https://images.unsplash.com/photo-1536304997881-a372c179924b?w=400&q=80", category: appCat),

            // Beverages (10)
            MenuItem(id: "isan41", name: "Cold Chrysanthemum Tea", itemDescription: "Sweet and cooling herbal chrysanthemum infusion served over ice.", price: 45.0, imageUrl: "https://images.unsplash.com/photo-1576092768241-dec231879fc3?w=400&q=80", category: drinkCat),
            MenuItem(id: "isan42", name: "Cold Roselle Juice", itemDescription: "Sweet and tart herbal roselle flower tea served with ice cubes.", price: 45.0, imageUrl: "https://images.unsplash.com/photo-1497534446932-c925b458314e?w=400&q=80", category: drinkCat),
            MenuItem(id: "isan43", name: "Lemongrass Pandan Iced Tea", itemDescription: "Fragrant iced tea brewed with fresh lemongrass stalk and sweet pandan leaves.", price: 50.0, imageUrl: "https://images.unsplash.com/photo-1513558161293-cdaf765ed2fd?w=400&q=80", category: drinkCat),
            MenuItem(id: "isan44", name: "Traditional Thai Iced Milk Tea", itemDescription: "Sweet brewed orange Thai tea topped with evaporated milk over shaved ice.", price: 65.0, imageUrl: "https://images.unsplash.com/photo-1576092768241-dec231879fc3?w=400&q=80", category: drinkCat, isBestseller: true),
            MenuItem(id: "isan45", name: "Thai Black Tea (Cha Dum Yen)", itemDescription: "Sweetened dark brewed Thai tea served chilled over crushed ice.", price: 55.0, imageUrl: "https://images.unsplash.com/photo-1576092768241-dec231879fc3?w=400&q=80", category: drinkCat),
            MenuItem(id: "isan46", name: "Fresh Whole Young Coconut", itemDescription: "Freshly opened sweet young coconut juice with tender coconut flesh.", price: 80.0, imageUrl: "https://images.unsplash.com/photo-1526318896980-cf78c088247c?w=400&q=80", category: drinkCat, isFavorite: true),
            MenuItem(id: "isan47", name: "Singha Lager Beer (Small)", itemDescription: "Premium clean Thai lager beer bottle, served chilled.", price: 95.0, imageUrl: "https://images.unsplash.com/photo-1608270586620-248524c67de9?w=400&q=80", category: drinkCat),
            MenuItem(id: "isan48", name: "Chang Lager Beer (Small)", itemDescription: "Famous crisp and strong Thai lager beer, served ice-cold.", price: 90.0, imageUrl: "https://images.unsplash.com/photo-1608270586620-248524c67de9?w=400&q=80", category: drinkCat),
            MenuItem(id: "isan49", name: "Sparkling Lime Pandan Soda", itemDescription: "Refreshing carbonated soda infused with fresh lime juice and pandan syrup.", price: 55.0, imageUrl: "https://images.unsplash.com/photo-1513558161293-cdaf765ed2fd?w=400&q=80", category: drinkCat),
            MenuItem(id: "isan50", name: "Mineral Drinking Water", itemDescription: "Chilled bottled mineral drinking water served with a glass of ice.", price: 20.0, imageUrl: "https://images.unsplash.com/photo-1548865140-64a23cf87aee?w=400&q=80", category: drinkCat)
        ]

        for item in items {
            modelContext.insert(item)
        }

        // 6. Link Thai Tea to Sweetness Level modifier group
        if let thaiTea = items.first(where: { $0.name.contains("Traditional Thai Iced Milk Tea") }) {
            let relationTeaSugar = MenuItemModifierGroup(menuItem: thaiTea, modifierGroup: sugarGroup)
            modelContext.insert(relationTeaSugar)
        }

        seedRolesAndEmployeesIfEmpty(modelContext: modelContext)

        // 7. Seed Recipes
        let prawnItem = items.first(where: { $0.id == "isan39" }) // Grilled River Prawn
        let chickenItem = items.first(where: { $0.id == "isan26" }) // Classic Gai Yang (Half)
        let chickenItemWhole = items.first(where: { $0.id == "isan27" }) // Classic Gai Yang (Whole)
        let teaItem = items.first(where: { $0.id == "isan44" }) // Traditional Thai Iced Milk Tea
        let somTumItem = items.first(where: { $0.id == "isan1" }) // Classic Som Tum Thai
        let larbItem = items.first(where: { $0.id == "isan9" }) // Spicy Minced Pork Larb

        if let prawnItem = prawnItem {
            let recipe = Recipe(menuItem: prawnItem, inventoryItem: prawns, quantityRequired: 1.0)
            modelContext.insert(recipe)
        }
        if let chickenItem = chickenItem {
            let recipe = Recipe(menuItem: chickenItem, inventoryItem: chicken, quantityRequired: 300.0)
            modelContext.insert(recipe)
        }
        if let chickenItemWhole = chickenItemWhole {
            let recipe = Recipe(menuItem: chickenItemWhole, inventoryItem: chicken, quantityRequired: 600.0)
            modelContext.insert(recipe)
        }
        if let teaItem = teaItem {
            let recipe1 = Recipe(menuItem: teaItem, inventoryItem: teaLeaves, quantityRequired: 15.0)
            let recipe2 = Recipe(menuItem: teaItem, inventoryItem: coconutMilk, quantityRequired: 50.0)
            modelContext.insert(recipe1)
            modelContext.insert(recipe2)
        }
        if let somTumItem = somTumItem {
            let recipe = Recipe(menuItem: somTumItem, inventoryItem: mango, quantityRequired: 1.0)
            modelContext.insert(recipe)
        }
        if let larbItem = larbItem {
            let recipe = Recipe(menuItem: larbItem, inventoryItem: chicken, quantityRequired: 150.0)
            modelContext.insert(recipe)
        }

        modelContext.saveWithLogging(label: #function)
    }

    static func seedAll(modelContext: ModelContext) {
        clearAllData(modelContext: modelContext)
        seedCatalogOnly(modelContext: modelContext)
        seedMockTransactions(modelContext: modelContext)
        modelContext.saveWithLogging(label: #function)
    }

    static func seedMockTransactions(modelContext: ModelContext) {
        let calendar = Calendar.current
        let today = Date()
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today

        // Fetch Employees
        let employees = (try? modelContext.fetch(FetchDescriptor<Employee>())) ?? []
        let empSomchai = employees.first(where: { $0.firstName == "Somchai" })
        let empSomsri = employees.first(where: { $0.firstName == "Somsri" })

        // Fetch Menu Items
        let menuItems = (try? modelContext.fetch(FetchDescriptor<MenuItem>())) ?? []
        let somTum = menuItems.first(where: { $0.id == "isan1" })
        let larb = menuItems.first(where: { $0.id == "isan9" })
        let gaiYangHalf = menuItems.first(where: { $0.id == "isan26" })
        let gaiYangWhole = menuItems.first(where: { $0.id == "isan27" })
        let prawn = menuItems.first(where: { $0.id == "isan39" })
        let milkTea = menuItems.first(where: { $0.id == "isan44" })
        let beerSingha = menuItems.first(where: { $0.id == "isan47" })
        let water = menuItems.first(where: { $0.id == "isan50" })

        // Define transaction profiles
        // We will generate 16 orders total: 8 yesterday, 8 today.
        // Varying times: 10:00 to 21:00
        let orderSpecs: [(daysAgo: Int, hour: Int, type: String, items: [(item: MenuItem?, qty: Int)], payMethod: String, cashier: String, deliveryBrand: String?, gp: Double, ad: Double)] = [
            // Yesterday (June 11 equivalent)
            (1, 11, "dine_in",  [(somTum, 2), (gaiYangHalf, 1), (milkTea, 2)], "qr_promptpay", "Somsri", nil, 0, 0),
            (1, 12, "take_out", [(larb, 1), (water, 1)], "cash", "Somchai", nil, 0, 0),
            (1, 13, "delivery", [(prawn, 2), (milkTea, 1)], "credit_card", "Somchai", "GrabFood", 30.0, 5.0),
            (1, 15, "dine_in",  [(somTum, 1), (water, 1)], "cash", "Somsri", nil, 0, 0),
            (1, 17, "delivery", [(gaiYangWhole, 1), (larb, 2)], "qr_promptpay", "Somchai", "LINE MAN", 30.0, 0.0),
            (1, 18, "dine_in",  [(prawn, 4), (beerSingha, 3)], "credit_card", "Somsri", nil, 0, 0),
            (1, 19, "delivery", [(somTum, 2), (gaiYangHalf, 2)], "true_money", "Somchai", "ShopeeFood", 30.0, 3.0),
            (1, 20, "dine_in",  [(larb, 1), (beerSingha, 2)], "cash", "Somsri", nil, 0, 0),

            // Today (June 12 equivalent)
            (0, 10, "take_out", [(milkTea, 3)], "cash", "Somsri", nil, 0, 0),
            (0, 12, "dine_in",  [(somTum, 1), (larb, 1), (gaiYangHalf, 1), (water, 2)], "qr_promptpay", "Somchai", nil, 0, 0),
            (0, 13, "delivery", [(prawn, 2), (water, 1)], "credit_card", "Somchai", "GrabFood", 30.0, 5.0),
            (0, 14, "dine_in",  [(gaiYangHalf, 1), (milkTea, 1)], "true_money", "Somsri", nil, 0, 0),
            (0, 16, "delivery", [(somTum, 3), (larb, 1)], "qr_promptpay", "Somchai", "LINE MAN", 30.0, 0.0),
            (0, 18, "dine_in",  [(gaiYangWhole, 1), (prawn, 2), (beerSingha, 4)], "credit_card", "Somsri", nil, 0, 0),
            (0, 19, "delivery", [(larb, 2), (milkTea, 2)], "true_money", "Somchai", "Foodpanda", 30.0, 4.0),
            (0, 21, "dine_in",  [(somTum, 1), (beerSingha, 1)], "cash", "Somsri", nil, 0, 0)
        ]

        var orderCounter = 1
        for spec in orderSpecs {
            let baseDate = spec.daysAgo == 1 ? yesterday : today
            guard let orderDate = calendar.date(bySettingHour: spec.hour, minute: Int.random(in: 0...59), second: 0, of: baseDate) else { continue }

            let dateStr = DateFormatter.orderDateFormat().string(from: orderDate)
            let orderNumber = "ORD-\(dateStr)-\(String(format: "%03d", orderCounter))"
            orderCounter += 1

            // Create Order
            let order = Order(
                orderNumber: orderNumber,
                orderType: spec.type,
                status: "completed",
                createdAt: orderDate,
                cashierName: spec.cashier,
                deliveryBrand: spec.deliveryBrand,
                deliveryGP: spec.gp,
                deliveryAdFee: spec.ad,
                deliveryAdFeeIsPct: spec.ad > 0 ? true : false,
                updatedAt: orderDate
            )
            modelContext.insert(order)

            // Add OrderItems
            var subtotal = 0.0
            for itemSpec in spec.items {
                guard let menuItem = itemSpec.item else { continue }
                let qty = itemSpec.qty
                let unitPrice = menuItem.price
                let itemSubtotal = Double(qty) * unitPrice
                subtotal += itemSubtotal

                let orderItem = OrderItem(
                    order: order,
                    menuItem: menuItem,
                    quantity: qty,
                    unitPrice: unitPrice,
                    status: "served",
                    updatedAt: orderDate
                )
                modelContext.insert(orderItem)
                orderItem.order = order
                order.items.append(orderItem)
            }

            let tax = subtotal * 0.07
            let serviceCharge = spec.type == "dine_in" ? subtotal * 0.10 : 0.0
            let total = subtotal + tax + serviceCharge

            order.subtotal = subtotal
            order.tax = tax
            order.serviceCharge = serviceCharge
            order.total = total

            // Add Payment
            let payment = Payment(
                order: order,
                paymentMethod: spec.payMethod,
                amount: total,
                status: "completed",
                paidAt: orderDate,
                updatedAt: orderDate
            )
            modelContext.insert(payment)
            order.payments.append(payment)
        }

        // Seed Timecards
        // Somchai Timecards
        if let somchai = empSomchai {
            // Yesterday Timecard
            if let clockInYesterday = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: yesterday),
               let clockOutYesterday = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: yesterday) {
                let tc = Timecard(
                    employee: somchai,
                    clockIn: clockInYesterday,
                    clockOut: clockOutYesterday,
                    breakDurationMinutes: 60,
                    overtimeMinutes: 0,
                    status: "approved",
                    updatedAt: clockOutYesterday
                )
                modelContext.insert(tc)
                somchai.timecards.append(tc)
            }

            // Today Timecard
            if let clockInToday = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: today),
               let clockOutToday = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: today) {
                let tc = Timecard(
                    employee: somchai,
                    clockIn: clockInToday,
                    clockOut: clockOutToday,
                    breakDurationMinutes: 60,
                    overtimeMinutes: 0,
                    status: "approved",
                    updatedAt: clockOutToday
                )
                modelContext.insert(tc)
                somchai.timecards.append(tc)
            }
        }

        // Somsri Timecards
        if let somsri = empSomsri {
            // Yesterday Timecard
            if let clockInYesterday = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: yesterday),
               let clockOutYesterday = calendar.date(bySettingHour: 19, minute: 30, second: 0, of: yesterday) {
                let tc = Timecard(
                    employee: somsri,
                    clockIn: clockInYesterday,
                    clockOut: clockOutYesterday,
                    breakDurationMinutes: 60,
                    overtimeMinutes: 30,
                    status: "approved",
                    updatedAt: clockOutYesterday
                )
                modelContext.insert(tc)
                somsri.timecards.append(tc)
            }

            // Today Timecard
            if let clockInToday = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: today),
               let clockOutToday = calendar.date(bySettingHour: 19, minute: 0, second: 0, of: today) {
                let tc = Timecard(
                    employee: somsri,
                    clockIn: clockInToday,
                    clockOut: clockOutToday,
                    breakDurationMinutes: 60,
                    overtimeMinutes: 0,
                    status: "approved",
                    updatedAt: clockOutToday
                )
                modelContext.insert(tc)
                somsri.timecards.append(tc)
            }
        }

        // Seed Waste (InventoryTransaction)
        let inventoryItems = (try? modelContext.fetch(FetchDescriptor<InventoryItem>())) ?? []
        if let mangoItem = inventoryItems.first(where: { $0.sku == "ING-MANGO" }) {
            // Yesterday waste
            let txn1 = InventoryTransaction(
                item: mangoItem,
                transactionType: InventoryMovementType.waste.rawValue,
                quantity: -3.0,
                costPrice: mangoItem.costPrice,
                notes: "Spoiled mangoes",
                isSynced: false,
                isDeleted: false,
                updatedAt: yesterday
            )
            modelContext.insert(txn1)
            mangoItem.transactions.append(txn1)
            mangoItem.currentQuantity -= 3.0

            // Today waste
            let txn2 = InventoryTransaction(
                item: mangoItem,
                transactionType: InventoryMovementType.waste.rawValue,
                quantity: -2.0,
                costPrice: mangoItem.costPrice,
                notes: "Bruised during prep",
                isSynced: false,
                isDeleted: false,
                updatedAt: today
            )
            modelContext.insert(txn2)
            mangoItem.transactions.append(txn2)
            mangoItem.currentQuantity -= 2.0
        }

        if let coconutItem = inventoryItems.first(where: { $0.sku == "ING-COCONUT" }) {
            let txn = InventoryTransaction(
                item: coconutItem,
                transactionType: InventoryMovementType.waste.rawValue,
                quantity: -500.0,
                costPrice: coconutItem.costPrice,
                notes: "Spilled carton",
                isSynced: false,
                isDeleted: false,
                updatedAt: today
            )
            modelContext.insert(txn)
            coconutItem.transactions.append(txn)
            coconutItem.currentQuantity -= 500.0
        }
    }
}

// MARK: - Date Formatter extension helper

extension DateFormatter {
    static func orderDateFormat() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }

    static func shortDateTimeFormat() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd MMM yyyy, HH:mm"
        return formatter
    }
}
