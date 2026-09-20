import Foundation
import OSLog
import SwiftData
import SwiftUI
import UIKit

// MARK: - Cart Items View Representation Struct

struct CartItem: Identifiable {
    let id = UUID()
    let item: MenuItem
    let selectedModifiers: [Modifier]
    var quantity: Int = 1
    var notes: String = ""

    // ── Snapshot of display/pricing values, captured at construction ─────────
    // SwiftData @Model objects can be invalidated when a background sync deletes
    // the underlying row (e.g. menu dedup / hard-delete reconcile). Any later
    // access to `item.name`, `item.price`, etc. on an invalidated model crashes
    // with "backing data could no longer be found". We snapshot the scalar
    // values here so the cart UI never dereferences a deleted model. The live
    // `item` reference is only used at checkout (recipe deduction), guarded
    // separately.
    let snapshotItemId: String
    let snapshotName: String
    let snapshotLocalizedName: String
    let snapshotPrice: Double
    let snapshotPriceDecimal: Decimal
    let snapshotImageURL: String?
    let snapshotImageData: Data?
    let snapshotColorHex: String?

    init(item: MenuItem, selectedModifiers: [Modifier], quantity: Int = 1, notes: String = "", unitPrice: Double? = nil) {
        self.item = item
        self.selectedModifiers = selectedModifiers
        self.quantity = quantity
        self.notes = notes
        // Capture display/pricing scalars now, while the model is valid.
        self.snapshotItemId = item.id
        self.snapshotName = item.name
        self.snapshotLocalizedName = item.localizedName
        self.snapshotPrice = unitPrice ?? item.price
        self.snapshotPriceDecimal = Decimal(unitPrice ?? item.price)
        self.snapshotImageURL = item.imageUrl
        self.snapshotImageData = item.imageData
        self.snapshotColorHex = item.colorHex
    }

    /// Use totalPriceDecimal for accurate currency calculations (avoids floating-point errors).
    /// totalPrice is kept for backward compatibility but may lose precision.
    var totalPrice: Double {
        let modifierCost = selectedModifiers.reduce(0.0) { $0 + $1.extraPrice }
        return (snapshotPrice + modifierCost) * Double(quantity)
    }

    var totalPriceDecimal: Decimal {
        let modifierCost = selectedModifiers.reduce(Decimal.zero) { $0 + ($1.extraPriceDecimal) }
        return (snapshotPriceDecimal + modifierCost) * Decimal(quantity)
    }

    func isEqual(to other: CartItem) -> Bool {
        guard snapshotItemId == other.snapshotItemId else { return false }
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

struct POSAlert: Identifiable, Equatable {
    let id = UUID()
    let message: String
}

// MARK: - POS View Model

@Observable
@MainActor
final class POSViewModel {
    var modelContext: ModelContext?
    private let legacyMockCashierName = "Alex M."

    /// SwiftUI asks for the same totals many times while building one frame.  Those
    /// totals used to re-fetch promotions (and customer redemption history) on
    /// every access.  Keep a snapshot until an input that can affect pricing
    /// changes; the key also covers settings that may be edited elsewhere.
    private struct PricingCacheKey: Equatable {
        struct Line: Equatable {
            let id: UUID
            let quantity: Int
            let totalPrice: Double
        }

        let lines: [Line]
        let orderType: String
        let customerId: UUID?
        let customerPoints: Int
        let customerTaxExempt: Bool
        let useLoyaltyPoints: Bool
        let redeemLoyaltyPoints: Int
        let couponPromotionId: UUID?
        let manualPromotionId: UUID?
        let suppressAutomaticPromotion: Bool
        let settings: String
    }

    @ObservationIgnored private var cachedSettingsFingerprint: String? = nil
    @ObservationIgnored private var lastSettingsCheck: TimeInterval = 0

    private func currentSettingsFingerprint() -> String {
        let now = ProcessInfo.processInfo.systemUptime
        if let cached = cachedSettingsFingerprint, now - lastSettingsCheck < 1.0 {
            return cached
        }
        let defaults = UserDefaults.standard
        let settingKeys = [
            "enable_tax", "tax_price_basis", "store_tax_rate", "store_tax_type",
            "tax_allow_item_exemptions", "tax_rounding_mode", "enable_service_charge",
            "store_service_charge_rate", "tax_service_charge_taxable",
            "tax_apply_\(selectedOrderType)", "service_charge_apply_\(selectedOrderType)",
            "promotions_auto_apply", "loyalty_redeem_value_per_point"
        ]
        let fingerprint = settingKeys.map { key in
            "\(key)=\(defaults.object(forKey: key).map(String.init(describing:)) ?? "nil")"
        }.joined(separator: ";")
        cachedSettingsFingerprint = fingerprint
        lastSettingsCheck = now
        return fingerprint
    }

    @ObservationIgnored private var cachedPromotion: (PricingCacheKey, Promotion?)?
    @ObservationIgnored private var cachedCheckoutCalculation: (PricingCacheKey, ReceiptCalculationEngine.Result)?
    @ObservationIgnored private var pricingCacheClearScheduled = false

    private func clearPricingCacheAfterCurrentUpdate() {
        guard !pricingCacheClearScheduled else { return }
        pricingCacheClearScheduled = true
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.cachedPromotion = nil
            self?.cachedCheckoutCalculation = nil
            self?.pricingCacheClearScheduled = false
        }
    }

    // Cart and configuration states
    var cart: [CartItem] = [] {
        didSet {
            // Protect in-cart menu items from being deleted by a background sync,
            // which would invalidate the model and crash the cart UI.
            SyncEngine.shared.protectedMenuItemIds = Set(cart.map { $0.snapshotItemId })
        }
    }
    var lastAddedItem: FocusTarget? = nil
    var selectedCategory: Category?
    var selectedItemForCustomization: MenuItem?
    var selectedPaymentMethod = "QR PromptPay"
    var selectedSupportProgram: String? = nil

    func activateThaiChuaThaiPlus() {
        guard UserDefaults.standard.bool(forKey: GovernmentSupportProgram.enabledSettingsKey) else {
            selectedSupportProgram = nil
            return
        }
        selectedSupportProgram = GovernmentSupportProgram.thaiChuaThaiPlus
    }

    func clearSupportProgram() { selectedSupportProgram = nil }

    var citizenPayableAmount: Double {
        guard UserDefaults.standard.bool(forKey: GovernmentSupportProgram.enabledSettingsKey),
              selectedSupportProgram == GovernmentSupportProgram.thaiChuaThaiPlus else { return cartTotal }
        return GovernmentSupportProgram.split(total: cartTotal).citizen
    }
    var selectedTableNumber = "1"
    var selectedOrderType = "dine_in"
    var guestCount: Int = 2
    var cashierName: String = "Staff"
    var selectedCustomer: Customer? = nil
    var useLoyaltyPoints: Bool = false
    var redeemLoyaltyPoints: Int = 0

    /// Normalized code currently applied at checkout (nil = auto-apply path).
    var appliedCouponCode: String? = nil
    /// Promotion resolved from `appliedCouponCode`. Cleared with the coupon.
    var appliedCouponPromotion: Promotion? = nil
    /// Explicit non-coupon promotion selected by the cashier from POS.
    var manuallySelectedPromotion: Promotion? = nil
    var suppressAutomaticPromotion = false
    /// Localized feedback after apply/clear (success or error).
    var couponFeedbackMessage: String? = nil
    var couponFeedbackIsError: Bool = false

    var loyaltyPointsDiscount: Double {
        guard useLoyaltyPoints, let customer = selectedCustomer else { return 0.0 }
        let pointsToRedeem = min(redeemLoyaltyPoints, customer.loyaltyPoints)
        let rate = Double(UserDefaults.standard.string(forKey: "loyalty_redeem_value_per_point") ?? "0.25") ?? 0.25
        return Double(pointsToRedeem) * rate
    }

    var currentQueueNumber: String = ""
    var currentReceiptNumber: String = ""
    var currentBillNumber: String = ""

    // C-1: Gift Card at checkout
    var selectedGiftCard: GiftCard? = nil
    var giftCardRedeemAmount: Double = 0.0

    var currentOrderDateString: String = ""
    var recentlySubmittedTableOrder: Order?
    /// Source ticket currently recalled into the cart. It is retired only in
    /// the same SwiftData transaction that saves its replacement order.
    private(set) var recalledHeldOrder: Order?
    private var activeCheckoutSession: CheckoutSession?

    // L6: Checkout error state — nil means no error, non-nil contains error description
    var lastCheckoutError: String? = nil
    var activeAlert: POSAlert? = nil
    private(set) var stockWarningMessage: String? = nil

    /// Presents at most one POS alert at a time. Repeated stock callbacks can
    /// arrive in the same run-loop pass; dropping them prevents UIKit from
    /// queueing identical alert controllers behind the one already visible.
    func presentAlert(_ message: String?) {
        guard activeAlert == nil, let message, !message.isEmpty else { return }
        activeAlert = POSAlert(message: message)
    }

    var deliveryBrand: String? = nil
    /// External platform order id (Grab / LINE MAN / …) — typed or pasted.
    var platformOrderNumber: String = ""
    // Delivery fee fields — persisted per-brand via UserDefaults
    var deliveryGP: Double = 0.0 {
        didSet { if let b = deliveryBrand { UserDefaults.standard.set(deliveryGP,     forKey: "delivery_gp_\(b)") } }
    }
    var deliveryAdFee: Double = 0.0 {
        didSet { if let b = deliveryBrand { UserDefaults.standard.set(deliveryAdFee,  forKey: "delivery_adFee_\(b)") } }
    }
    var deliveryAdFeeIsPct: Bool = false {
        didSet { if let b = deliveryBrand { UserDefaults.standard.set(deliveryAdFeeIsPct, forKey: "delivery_adFeeIsPct_\(b)") } }
    }
    var deliveryOtherFee: Double = 0.0 {
        didSet { if let b = deliveryBrand { UserDefaults.standard.set(deliveryOtherFee, forKey: "delivery_otherFee_\(b)") } }
    }

    /// Call this whenever deliveryBrand changes to restore saved fees for the selected brand.
    func loadDeliveryFees(for brand: String) {
        let ud = UserDefaults.standard
        deliveryGP          = ud.double(forKey: "delivery_gp_\(brand)")
        deliveryAdFee       = ud.double(forKey: "delivery_adFee_\(brand)")
        deliveryAdFeeIsPct  = ud.bool(forKey:   "delivery_adFeeIsPct_\(brand)")
        deliveryOtherFee    = ud.double(forKey: "delivery_otherFee_\(brand)")
    }

    init(modelContext: ModelContext? = nil) {
        self.modelContext = modelContext
    }

    // MARK: - POS Session Synchronization

    private func normalizedCashierName(_ name: String?) -> String? {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    func syncFromSession(_ session: TableSession?, activeCashierName: String? = nil) {
        let activeCashier = normalizedCashierName(activeCashierName)

        if let session = session {
            if recentlySubmittedTableOrder?.tableSession?.id != session.id {
                recentlySubmittedTableOrder = nil
            }
            guestCount = session.guestCount
            if let activeCashier,
               session.cashierName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                session.cashierName == legacyMockCashierName {
                session.cashierName = activeCashier
                session.isSynced = false
                session.updatedAt = Date()
                try? modelContext?.save()
                Task { _ = try? await NetworkManager.shared.uploadTableSession(session: session) }
            }
            let sessionCashier = session.cashierName.trimmingCharacters(in: .whitespacesAndNewlines)
            cashierName = sessionCashier.isEmpty ? (activeCashier ?? "Staff") : sessionCashier
            selectedOrderType = "dine_in"
            currentBillNumber = "AP-\(session.id.uuidString.prefix(6).uppercased())"
            let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
            if let q = session.queueNumber, let sanitized = NetworkManager.sanitizeQueueNumber(q), !q.contains("-") {
                currentQueueNumber = sanitized
                if session.queueNumber != sanitized {
                    session.queueNumber = sanitized
                    session.isSynced = false
                    session.updatedAt = Date()
                    try? modelContext?.save()
                }
            } else {
                let seqQ = NetworkManager.localFallbackQueueNumber(merchantId: merchantId)
                session.queueNumber = seqQ
                currentQueueNumber = seqQ
                session.isSynced = false
                session.updatedAt = Date()
                try? modelContext?.save()
                Task { [weak self] in
                    if let seq = try? await NetworkManager.shared.generateQueueNumber() {
                        let formatted = NetworkManager.formatQueueNumber(seq)
                        await MainActor.run {
                            session.queueNumber = formatted
                            self?.currentQueueNumber = formatted
                            session.isSynced = false
                            session.updatedAt = Date()
                            try? self?.modelContext?.save()
                        }
                    }
                    _ = try? await NetworkManager.shared.uploadTableSession(session: session)
                }
            }
            currentOrderDateString = DateFormatter.shortDateTimeFormat().string(from: session.startedAt)
        } else {
            recentlySubmittedTableOrder = nil
            selectedOrderType = "take_out"
            if let activeCashier {
                cashierName = activeCashier
            } else if cashierName == legacyMockCashierName || cashierName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                cashierName = "Staff"
            }
            currentBillNumber = "AP-NEW"
            // Queue / receipt are allocated at submit time (sequential RPC), not randomly here.
            currentQueueNumber = ""
            currentReceiptNumber = ""
            currentOrderDateString = DateFormatter.shortDateTimeFormat().string(from: Date())
        }
    }

    /// Allocates sequential queue (+ receipt when paying) for counter / quick-sale orders.
    @MainActor
    func allocateCounterServiceIdentifiersIfNeeded(includeReceipt: Bool = true) async {
        let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
        if currentQueueNumber.isEmpty {
            if let seq = try? await NetworkManager.shared.generateQueueNumber() {
                currentQueueNumber = NetworkManager.formatQueueNumber(seq)
            } else {
                currentQueueNumber = NetworkManager.localFallbackQueueNumber(merchantId: merchantId)
            }
        }
        if includeReceipt, currentReceiptNumber.isEmpty {
            if let remote = try? await NetworkManager.shared.generateReceiptNumber() {
                currentReceiptNumber = remote
            } else {
                currentReceiptNumber = NetworkManager.localFallbackReceiptNumber(merchantId: merchantId)
            }
        }
        if currentBillNumber.isEmpty || currentBillNumber == "AP-NEW" {
            let day = DateFormatter.orderDateFormat().string(from: Date())
            let suffix = String(UUID().uuidString.prefix(6)).uppercased()
            currentBillNumber = "QO-\(day)-\(suffix)"
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

    /// Determines the fallback order type after completing or resetting a delivery order.
    /// Reads from user configuration `delivery_post_payment_order_type` (default: "take_out").
    var postDeliveryOrderType: String {
        let preferred = UserDefaults.standard.string(forKey: "delivery_post_payment_order_type") ?? "take_out"
        if preferred == "dine_in" {
            let enableTableSystem = UserDefaults.standard.object(forKey: "enable_table_system") as? Bool ?? true
            return enableTableSystem ? "dine_in" : "walk_in"
        }
        return "take_out"
    }

    func updateOrderType(_ type: String) {
        selectedOrderType = type
        if type == "delivery" {
            setDeliveryBrand(deliveryBrand ?? "GrabFood")
            if platformOrderNumber.isEmpty {
                platformOrderNumber = PlatformOrderNumber.prefix(for: deliveryBrand) ?? ""
            }
        } else {
            repriceCart()
        }
    }

    func setDeliveryBrand(_ brand: String) {
        deliveryBrand = brand
        loadDeliveryFees(for: brand)
        platformOrderNumber = PlatformOrderNumber.rebrand(platformOrderNumber, to: brand)
        repriceCart()
    }

    /// Apply clipboard contents into `platformOrderNumber` when usable.
    @discardableResult
    func pastePlatformOrderNumberFromClipboard() -> Bool {
        guard let value = PlatformOrderNumber.fromPasteboard(brand: deliveryBrand) else { return false }
        platformOrderNumber = value
        return true
    }

    func setPlatformOrderNumberFromRaw(_ raw: String) {
        platformOrderNumber = PlatformOrderNumber.applyBrandPrefixWhileEditing(raw, brand: deliveryBrand)
    }

    func salesChannelUnitPrice(for item: MenuItem) -> Double {
        guard selectedOrderType == "delivery", let brand = deliveryBrand else { return item.price }
        return item.deliveryPrices.first {
            !$0.isDeleted && $0.brandName.caseInsensitiveCompare(brand) == .orderedSame
        }?.price ?? item.price
    }

    private func repriceCart() {
        cart = cart.map {
            CartItem(
                item: $0.item,
                selectedModifiers: $0.selectedModifiers,
                quantity: $0.quantity,
                notes: $0.notes,
                unitPrice: salesChannelUnitPrice(for: $0.item)
            )
        }
    }

    // MARK: - Financial Calculations

    private var pricingCacheKey: PricingCacheKey {
        PricingCacheKey(
            lines: cart.map { .init(id: $0.id, quantity: $0.quantity, totalPrice: $0.totalPrice) },
            orderType: selectedOrderType,
            customerId: selectedCustomer?.id,
            customerPoints: selectedCustomer?.loyaltyPoints ?? 0,
            customerTaxExempt: selectedCustomer?.isTaxExempt ?? false,
            useLoyaltyPoints: useLoyaltyPoints,
            redeemLoyaltyPoints: redeemLoyaltyPoints,
            couponPromotionId: appliedCouponPromotion?.id,
            manualPromotionId: manuallySelectedPromotion?.id,
            suppressAutomaticPromotion: suppressAutomaticPromotion,
            settings: currentSettingsFingerprint()
        )
    }

    var cartSubtotal: Double {
        cart.reduce(0.0) { $0 + $1.totalPrice }
    }

    private var taxAppliesToSelectedOrderType: Bool {
        let key: String
        switch selectedOrderType {
        case "take_out": key = "tax_apply_take_out"
        case "delivery": key = "tax_apply_delivery"
        default: key = "tax_apply_dine_in"
        }
        return UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }

    private var serviceChargeAppliesToSelectedOrderType: Bool {
        let key: String
        switch selectedOrderType {
        case "take_out": key = "service_charge_apply_take_out"
        case "delivery": key = "service_charge_apply_delivery"
        default: key = "service_charge_apply_dine_in"
        }
        let defaultValue = selectedOrderType != "take_out" && selectedOrderType != "delivery"
        return UserDefaults.standard.object(forKey: key) as? Bool ?? defaultValue
    }

    private func getTaxRateAndInclusion(for item: MenuItem) -> (rate: Double, isInclusive: Bool) {
        guard (UserDefaults.standard.object(forKey: "enable_tax") as? Bool ?? true), taxAppliesToSelectedOrderType else {
            return (0.0, true)
        }
        let priceBasis = UserDefaults.standard.string(forKey: "tax_price_basis") ?? "itemDefault"
        let globalTaxRate = UserDefaults.standard.object(forKey: "store_tax_rate") as? Double ?? 7.0
        let globalTaxType = UserDefaults.standard.string(forKey: "store_tax_type") ?? "inclusive"
        let allowItemExemptions = UserDefaults.standard.object(forKey: "tax_allow_item_exemptions") as? Bool ?? true
        let itemRate = allowItemExemptions || item.taxRate > 0 ? item.taxRate : globalTaxRate

        switch priceBasis {
        case "forceInclusive":
            return (globalTaxRate, true)
        case "forceExclusive":
            return (globalTaxRate, false)
        case "itemDefault":
            let isInclusive = item.isTaxInclusive ?? (globalTaxType == "inclusive")
            return (itemRate, isInclusive)
        default:
            return (itemRate, item.isTaxInclusive ?? (globalTaxType == "inclusive"))
        }
    }

    private var roundsTaxPerLine: Bool {
        (UserDefaults.standard.string(forKey: "tax_rounding_mode") ?? "perLine") == "perLine"
    }

    private func roundedMoney(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }

    /// One calculation snapshot feeds the POS totals, persisted Order and tax lines.
    /// Receipt/report code consumes that persisted snapshot instead of recalculating it.
    private var checkoutCalculation: ReceiptCalculationEngine.Result {
        let cacheKey = pricingCacheKey
        if let cachedCheckoutCalculation, cachedCheckoutCalculation.0 == cacheKey {
            return cachedCheckoutCalculation.1
        }
        let taxEnabled = (UserDefaults.standard.object(forKey: "enable_tax") as? Bool ?? true)
            && taxAppliesToSelectedOrderType
        let serviceEnabled = (UserDefaults.standard.object(forKey: "enable_service_charge") as? Bool ?? true)
            && serviceChargeAppliesToSelectedOrderType
        let serviceRate = UserDefaults.standard.object(forKey: "store_service_charge_rate") as? Double ?? 10.0
        let globalTaxRate = UserDefaults.standard.object(forKey: "store_tax_rate") as? Double ?? 7.0
        let globalInclusive = (UserDefaults.standard.string(forKey: "store_tax_type") ?? "inclusive") == "inclusive"
        let lines = cart.map { cartItem -> ReceiptCalculationEngine.Line in
            let config = getTaxRateAndInclusion(for: cartItem.item)
            let unitAmount = cartItem.quantity > 0 ? cartItem.totalPrice / Double(cartItem.quantity) : 0
            return .init(
                id: cartItem.id.uuidString,
                name: cartItem.snapshotName,
                quantity: cartItem.quantity,
                unitPrice: Decimal(string: String(format: "%.6f", unitAmount)) ?? 0,
                taxRate: taxEnabled ? Decimal(string: String(config.rate)) ?? 0 : 0,
                taxInclusive: config.isInclusive
            )
        }
        let result = ReceiptCalculationEngine.calculate(.init(
            lines: lines,
            discount: Decimal(string: String(cartDiscount + loyaltyPointsDiscount)) ?? 0,
            serviceChargeRate: Decimal(string: String(serviceRate)) ?? 0,
            serviceChargeEnabled: serviceEnabled,
            serviceChargeTaxable: UserDefaults.standard.object(forKey: "tax_service_charge_taxable") as? Bool ?? true,
            serviceChargeTaxRate: taxEnabled ? Decimal(string: String(globalTaxRate)) ?? 0 : 0,
            serviceChargeTaxInclusive: globalInclusive,
            customerTaxExempt: selectedCustomer?.isTaxExempt == true,
            roundingMode: roundsTaxPerLine ? .perLine : .perDocument
        ))
        cachedCheckoutCalculation = (cacheKey, result)
        clearPricingCacheAfterCurrentUpdate()
        return result
    }

    var cartTax: Double {
        NSDecimalNumber(decimal: checkoutCalculation.tax).doubleValue
    }

    var cartServiceCharge: Double {
        NSDecimalNumber(decimal: checkoutCalculation.serviceCharge).doubleValue
    }

    var activePromotion: Promotion? {
        let cacheKey = pricingCacheKey
        if let cachedPromotion, cachedPromotion.0 == cacheKey {
            return cachedPromotion.1
        }

        let promotion: Promotion?
        if let couponPromo = resolvedAppliedCouponPromotion() {
            promotion = couponPromo
        } else if let selected = resolvedManuallySelectedPromotion() {
            promotion = selected
        } else if suppressAutomaticPromotion {
            promotion = nil
        } else {
            promotion = bestPromotion()
        }
        cachedPromotion = (cacheKey, promotion)
        clearPricingCacheAfterCurrentUpdate()
        return promotion
    }

    var cartDiscount: Double {
        guard let activePromotion else { return 0.0 }
        return discountAmount(for: activePromotion)
    }

    /// True when a cashier-entered coupon is driving the active discount.
    var isCouponDiscountActive: Bool {
        appliedCouponPromotion != nil && resolvedAppliedCouponPromotion() != nil
    }

    /// Apply a coupon code entered at POS. Returns `true` on success.
    @discardableResult
    func applyCouponCode(_ rawCode: String) -> Bool {
        couponFeedbackMessage = nil
        couponFeedbackIsError = false

        let code = rawCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard !code.isEmpty else {
            setCouponFeedback("coupon_pos_empty".t, isError: true)
            return false
        }
        guard cartSubtotal > 0 else {
            setCouponFeedback("coupon_pos_empty_cart".t, isError: true)
            return false
        }
        guard let modelContext else {
            setCouponFeedback("coupon_pos_unavailable".t, isError: true)
            return false
        }

        let descriptor = FetchDescriptor<Promotion>(
            predicate: #Predicate<Promotion> { $0.isDeleted == false }
        )
        let promotions = (try? modelContext.fetch(descriptor)) ?? []
        let now = Date()

        guard let promo = promotions.first(where: {
            ($0.couponCode ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == code
        }) else {
            setCouponFeedback("coupon_pos_not_found".t, isError: true)
            return false
        }

        guard promo.isEffective(at: now) else {
            setCouponFeedback("coupon_pos_inactive".t, isError: true)
            return false
        }
        guard promo.isCouponRedemptionAllowed(at: now) else {
            if let expires = promo.couponExpiresAt, now > expires {
                setCouponFeedback("coupon_pos_expired".t, isError: true)
            } else {
                setCouponFeedback("coupon_pos_max_uses".t, isError: true)
            }
            return false
        }

        if let customer = selectedCustomer, let limit = promo.perCustomerLimit {
            let used = countCustomerRedemptions(
                customerId: customer.id,
                promotionId: promo.id,
                modelContext: modelContext
            )
            if used >= limit {
                setCouponFeedback("coupon_pos_customer_limit".t, isError: true)
                return false
            }
        }

        guard promo.discountType != "none" else {
            setCouponFeedback("coupon_pos_no_discount".t, isError: true)
            return false
        }

        if cartSubtotal < promo.minimumSpend {
            setCouponFeedback(
                LocalizationManager.shared.t(
                    "coupon_pos_min_spend",
                    promo.minimumSpend.formatted(.number.precision(.fractionLength(0...2)))
                ),
                isError: true
            )
            return false
        }

        let amount = discountAmount(for: promo)
        guard amount > 0 else {
            setCouponFeedback("coupon_pos_not_eligible".t, isError: true)
            return false
        }

        appliedCouponCode = code
        appliedCouponPromotion = promo
        manuallySelectedPromotion = nil
        setCouponFeedback(
            LocalizationManager.shared.t(
                "coupon_pos_applied",
                code,
                amount.formatted(.number.precision(.fractionLength(0...2)))
            ),
            isError: false
        )
        APHaptic.trigger()
        return true
    }

    func clearAppliedCoupon() {
        appliedCouponCode = nil
        appliedCouponPromotion = nil
        couponFeedbackMessage = nil
        couponFeedbackIsError = false
    }

    @discardableResult
    func selectPromotion(_ promotion: Promotion) -> Bool {
        guard promotion.couponCode == nil, isPromotionEligible(promotion) else { return false }
        appliedCouponCode = nil
        appliedCouponPromotion = nil
        couponFeedbackMessage = nil
        couponFeedbackIsError = false
        manuallySelectedPromotion = promotion
        suppressAutomaticPromotion = false
        APHaptic.trigger()
        return true
    }

    func clearSelectedPromotion() {
        manuallySelectedPromotion = nil
        suppressAutomaticPromotion = true
    }

    func useAutomaticPromotion() {
        manuallySelectedPromotion = nil
        suppressAutomaticPromotion = false
    }

    func resetPromotionSelection() {
        manuallySelectedPromotion = nil
        suppressAutomaticPromotion = false
    }

    func isPromotionEligible(_ promotion: Promotion) -> Bool {
        guard promotion.couponCode == nil, promotion.isEffective(), cartSubtotal > 0 else { return false }
        if let customer = selectedCustomer, let limit = promotion.perCustomerLimit, let modelContext {
            let used = countCustomerRedemptions(
                customerId: customer.id,
                promotionId: promotion.id,
                modelContext: modelContext
            )
            if used >= limit { return false }
        }
        return promotionDiscountAmount(promotion) > 0
    }

    func promotionDiscountAmount(_ promotion: Promotion) -> Double {
        discountAmount(for: promotion)
    }

    private func setCouponFeedback(_ message: String, isError: Bool) {
        couponFeedbackMessage = message
        couponFeedbackIsError = isError
    }

    private func resolvedAppliedCouponPromotion() -> Promotion? {
        guard let promo = appliedCouponPromotion else { return nil }
        let now = Date()
        guard promo.isEffective(at: now), promo.isCouponRedemptionAllowed(at: now) else {
            return nil
        }
        if let customer = selectedCustomer, let limit = promo.perCustomerLimit, let modelContext {
            let used = countCustomerRedemptions(
                customerId: customer.id,
                promotionId: promo.id,
                modelContext: modelContext
            )
            if used >= limit { return nil }
        }
        return promo
    }

    private func resolvedManuallySelectedPromotion() -> Promotion? {
        guard let promotion = manuallySelectedPromotion,
              isPromotionEligible(promotion) else { return nil }
        return promotion
    }

    var cartTotal: Double {
        NSDecimalNumber(decimal: checkoutCalculation.total).doubleValue
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

    // A customer limit used to trigger one full OrderDiscount fetch for every
    // candidate promotion. With a sizeable sales history this became the
    // dominant main-thread cost whenever the cart changed. Materialize the
    // customer's counts once and reuse them for all candidates.
    var customerRedemptionsByPromotion: [UUID: Int] = [:]
    if let customerId = selectedCustomer?.id,
       promotions.contains(where: { $0.perCustomerLimit != nil }) {
        let discountDescriptor = FetchDescriptor<OrderDiscount>(
            predicate: #Predicate<OrderDiscount> { $0.isDeleted == false }
        )
        if let discounts = try? modelContext.fetch(discountDescriptor) {
            for discount in discounts where discount.order?.customer?.id == customerId {
                if let promotionId = discount.promotion?.id {
                    customerRedemptionsByPromotion[promotionId, default: 0] += 1
                }
            }
        }
    }

    return promotions
        .filter { promo in
            guard promo.isEffective(at: now) else { return false }
            guard promo.couponCode == nil, promo.allowsAutomaticApplication else { return false }
            guard discountAmount(for: promo) > 0 else { return false }

            // Check per-customer limit if customer is selected
            if selectedCustomer != nil, let limit = promo.perCustomerLimit {
                let customerRedemptions = customerRedemptionsByPromotion[promo.id, default: 0]
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
        guard promotion.isEffective() else { return 0 }
        if promotion.discountType != "fixed_per_item",
           cartSubtotal < promotion.minimumSpend { return 0 }

        if promotion.discountType == "fixed_per_item" {
            guard promotion.discountValue > 0 else { return 0 }
            return AccountingMath.fixedPerItemDiscount(
                value: promotion.discountValue,
                minimumUnitPrice: promotion.minimumSpend,
                lines: cart.map { (quantity: $0.quantity, total: $0.totalPrice) }
            )
        }

        if promotion.discountType == "bundle_price" {
            guard let itemId = promotion.appliesToMenuItemId,
                  promotion.requiredQuantity > 0,
                  promotion.discountValue > 0 else { return 0 }

            return cart.reduce(0.0) { total, cartItem in
                guard cartItem.snapshotItemId == itemId else { return total }
                let bundleCount = cartItem.quantity / promotion.requiredQuantity
                guard bundleCount > 0 else { return total }
                let unitPrice = cartItem.snapshotPrice + cartItem.selectedModifiers.reduce(0.0) { $0 + $1.extraPrice }
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
                guard cartItem.snapshotItemId == itemId else { return total }
                let groupCount = cartItem.quantity / groupSize
                guard groupCount > 0 else { return total }
                let unitPrice = cartItem.snapshotPrice + cartItem.selectedModifiers.reduce(0.0) { $0 + $1.extraPrice }
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
                guard cartItem.snapshotItemId == itemId else { return total }
                let groupCount = cartItem.quantity / promotion.requiredQuantity
                guard groupCount > 0 else { return total }
                let unitPrice = cartItem.snapshotPrice + cartItem.selectedModifiers.reduce(0.0) { $0 + $1.extraPrice }
                let freeUnits = groupCount * (promotion.requiredQuantity - promotion.rewardQuantity)
                return total + max(0, unitPrice * Double(freeUnits))
            }
        }

        // Industry-standard: % / fixed can be order-wide OR item-scoped.
        if promotion.discountType == "percentage" || promotion.discountType == "fixed" {
            if let itemId = promotion.appliesToMenuItemId, !itemId.isEmpty {
                let eligibleSubtotal = cart.reduce(0.0) { total, cartItem in
                    guard cartItem.snapshotItemId == itemId else { return total }
                    return total + cartItem.totalPrice
                }
                guard eligibleSubtotal > 0 else { return 0 }
                return promotion.discountAmount(for: eligibleSubtotal)
            }
            return promotion.discountAmount(for: cartSubtotal)
        }

        return promotion.discountAmount(for: cartSubtotal)
    }

    // MARK: - Cart Operations

    func selectItem(_ item: MenuItem) {
        // If menu item has recipes/modifier groups, open customize screen, else add straight to cart
        if item.modifierGroupsRelations.isEmpty {
            let (allowed, reason) = checkStockBeforeAdding(item, modifiers: [], quantity: 1)
            guard allowed else {
                presentAlert(reason)
                return
            }
            addToCart(item, modifiers: [])
        } else {
            selectedItemForCustomization = item
        }
    }

    func addToCart(_ item: MenuItem, modifiers: [Modifier]) {
        let (allowed, reason) = checkStockBeforeAdding(item, modifiers: modifiers, quantity: 1)
        guard allowed else {
            presentAlert(reason)
            return
        }
        let cartItem = CartItem(item: item, selectedModifiers: modifiers, unitPrice: salesChannelUnitPrice(for: item))
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
        presentStockWarningIfNeeded()
    }

    func increaseQty(_ item: CartItem) {
        if let idx = cart.firstIndex(where: { $0.id == item.id }) {
            let (allowed, reason) = checkStockBeforeAdding(cart[idx].item, modifiers: cart[idx].selectedModifiers, quantity: cart[idx].quantity + 1)
            guard allowed else {
                presentAlert(reason)
                return
            }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                cart[idx].quantity += 1
                lastAddedItem = FocusTarget(itemId: cart[idx].id)
            }
            APHaptic.trigger()
            presentStockWarningIfNeeded()
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
        try? BranchContext.shared.requireActiveBranch(in: context)
    }

    private func makeOrderNumber() -> String {
        let date = DateFormatter.orderDateFormat().string(from: Date())
        let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)
        return "ORD-\(date)-\(suffix)"
    }

    @discardableResult func processCheckout(
        tableSession: TableSession? = nil,
        createPayment: Bool = false,
        paymentMethod: String? = nil,
        dispatchPrint: Bool = true,
        cashTendered: Double? = nil,
        transactionReference: String? = nil
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
    if activeCheckoutSession?.lifecycleState == .completed {
        lastCheckoutError = "checkout already completed — duplicate charge prevented"
        return nil
    }
    let activeBranch = fetchActiveBranch(context: modelContext)

    // 1. Create the Order
    let finalOrderNum: String
    if currentBillNumber.isEmpty || currentBillNumber == "AP-NEW" {
        finalOrderNum = makeOrderNumber()
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
    let calculation = checkoutCalculation
    let assignedReceipt: String? = {
        if createPayment {
            if !currentReceiptNumber.isEmpty { return currentReceiptNumber }
            let merchantId = UserDefaults.standard.string(forKey: "active_merchant_id") ?? ""
            return NetworkManager.localFallbackReceiptNumber(merchantId: merchantId)
        }
        return currentReceiptNumber.isEmpty ? nil : currentReceiptNumber
    }()

    let resolvedPlatformOrderNumber: String? = {
        guard selectedOrderType == "delivery" else { return nil }
        let normalized = PlatformOrderNumber.applyBrandPrefix(platformOrderNumber, brand: deliveryBrand)
        // Ignore bare prefix with no digits (user never typed an id).
        let body = PlatformOrderNumber.stripKnownPrefix(normalized)
        return body.isEmpty ? nil : normalized
    }()

    let order = Order(
        orderNumber: finalOrderNum,
        tableSession: tableSession,
        orderType: selectedOrderType,
        status: "preparing",
        subtotal: NSDecimalNumber(decimal: calculation.subtotal).doubleValue,
        tax: NSDecimalNumber(decimal: calculation.tax).doubleValue,
        serviceCharge: NSDecimalNumber(decimal: calculation.serviceCharge).doubleValue,
        discount: NSDecimalNumber(decimal: calculation.discount).doubleValue,
        total: NSDecimalNumber(decimal: calculation.total).doubleValue,
        branch: activeBranch!,
        customer: selectedCustomer,
        heldAt: nil,
        receiptNumber: assignedReceipt,
        guestCount: guestCount,
        cashierName: cashierName,
        queueNumber: currentQueueNumber.isEmpty ? nil : currentQueueNumber,
        deliveryBrand: selectedOrderType == "delivery" ? deliveryBrand : nil,
        deliveryGP: selectedOrderType == "delivery" ? deliveryGP : 0.0,
        deliveryAdFee: selectedOrderType == "delivery" ? deliveryAdFee : 0.0,
        deliveryAdFeeIsPct: selectedOrderType == "delivery" ? deliveryAdFeeIsPct : false,
        deliveryOtherFee: selectedOrderType == "delivery" ? deliveryOtherFee : 0.0,
        platformOrderNumber: resolvedPlatformOrderNumber
    )

    if UserDefaults.standard.bool(forKey: GovernmentSupportProgram.enabledSettingsKey),
       selectedSupportProgram == GovernmentSupportProgram.thaiChuaThaiPlus {
        let split = GovernmentSupportProgram.split(total: order.total)
        order.supportProgramName = GovernmentSupportProgram.thaiChuaThaiPlus
        order.supportGovernmentRate = GovernmentSupportProgram.governmentRate
        order.supportCitizenAmount = split.citizen
        order.supportGovernmentAmount = split.government
        order.supportSettlementStatus = "pending"
    }

    modelContext.insert(order)
    let sellerTaxId = UserDefaults.standard.string(forKey: "store_tax_id") ?? ""
    let taxMode = UserDefaults.standard.string(forKey: "store_tax_type") ?? "inclusive"
    let canIssueTaxInvoice = taxMode == "inclusive"
        && ReceiptComplianceGate.canIssueAbbreviatedTaxInvoice(vatEnabled: calculation.tax > 0, taxId: sellerTaxId)
    order.receiptDocumentType = canIssueTaxInvoice
        ? ReceiptDocumentType.receiptAndAbbreviatedTaxInvoice.rawValue
        : ReceiptDocumentType.receipt.rawValue
    if let recalledHeldOrder {
        recalledHeldOrder.isDeleted = true
        recalledHeldOrder.isSynced = false
        recalledHeldOrder.updatedAt = Date()
    }

    // Explicitly update relationship in-memory
    if let session = tableSession {
        if let tableNum = session.table?.tableNumber.trimmingCharacters(in: .whitespacesAndNewlines),
           !tableNum.isEmpty {
            order.floorTableNumber = tableNum
        }
        session.orders.append(order)
        recentlySubmittedTableOrder = order
        session.isSynced = false
        session.updatedAt = Date()
    }

    // 2. Record OrderDiscount if promotion applied
    if let appliedPromotion, appliedDiscount > 0 {
        let discountReason: String
        if appliedPromotion.isStaffDiscount {
            discountReason = "Staff discount: \(appliedPromotion.title)"
        } else if let code = appliedCouponCode {
            discountReason = "Coupon \(code): \(appliedPromotion.title)"
        } else if manuallySelectedPromotion?.id == appliedPromotion.id {
            discountReason = "Cashier-selected promotion: \(appliedPromotion.title)"
        } else {
            discountReason = "Auto-applied promotion: \(appliedPromotion.title)"
        }
        let discount = OrderDiscount(
            order: order,
            promotion: appliedPromotion,
            discountType: appliedPromotion.discountType,
            discountValue: appliedPromotion.discountValue,
            discountAmount: appliedDiscount,
            reason: discountReason
        )
        modelContext.insert(discount)

        // Increment promotion usage counter
        appliedPromotion.incrementRedemption()
    }

    // Persist the exact tax groups emitted by the central engine.
    if selectedCustomer?.isTaxExempt != true {
        let taxName = UserDefaults.standard.string(forKey: "store_tax_name") ?? "VAT"
        for group in calculation.taxLines where group.taxAmount > 0 {
            let taxLine = OrderTaxLine(
                order: order,
                taxName: "\(taxName) \(NSDecimalNumber(decimal: group.rate).stringValue)%",
                taxRate: NSDecimalNumber(decimal: group.rate).doubleValue,
                taxableAmount: NSDecimalNumber(decimal: group.taxableAmount).doubleValue,
                taxAmount: NSDecimalNumber(decimal: group.taxAmount).doubleValue,
                isInclusive: group.inclusive
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
            unitPrice: cartItem.snapshotPrice,
            lineType: cartItem.item.orderItemLineType,
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
        let paymentAmount = order.usesGovernmentSupport ? order.supportCitizenAmount : cartTotal
        let payment = Payment(paymentMethod: paymentMethod ?? selectedPaymentMethod, amount: paymentAmount)
        if let cashTendered, cashTendered > 0 {
            payment.transactionReference = Payment.cashTenderedReference(cashTendered)
        } else if let transactionReference, !transactionReference.isEmpty {
            payment.transactionReference = transactionReference
        } else if order.usesGovernmentSupport {
            payment.transactionReference = Payment.thaiChuaThaiInternalReference(orderNumber: order.orderNumber)
        }
        payment.order = order
        order.payments.append(payment)
        BusinessDayContext.stamp(payment: payment, order: order, in: modelContext)

        // C-1: Gift Card Redeem — deduct balance before saving payment
        if let giftCard = selectedGiftCard, giftCardRedeemAmount > 0 {
            let deductAmount = min(giftCardRedeemAmount, giftCard.balance)
            giftCard.balance -= deductAmount
            giftCard.isSynced = false
            giftCard.updatedAt = Date()
            if giftCard.balance <= 0 {
                giftCard.status = "exhausted"
            }
            // Payment covers only the remaining amount after gift card
            payment.amount = max(0, cartTotal - deductAmount)
        }

        // C-2.5: Loyalty Points Redeem — deduct points and save transaction
        if useLoyaltyPoints, let customer = selectedCustomer, redeemLoyaltyPoints > 0 {
            let pointsToRedeem = min(redeemLoyaltyPoints, customer.loyaltyPoints)
            if pointsToRedeem > 0 {
                customer.loyaltyPoints -= pointsToRedeem
                customer.isSynced = false
                customer.updatedAt = Date()

                let loyaltyTx = LoyaltyTransaction(
                    customer: customer,
                    order: order,
                    transactionType: "redeem",
                    points: -pointsToRedeem,
                    pointsBalanceAfter: customer.loyaltyPoints,
                    transactionDescription: "Redeemed points on order \(order.orderNumber)"
                )
                modelContext.insert(loyaltyTx)
            }
        }

        modelContext.insert(payment)
        AccountingLedgerService.recordCapturedPayment(payment, order: order, in: modelContext)
    }

    if let activeCheckoutSession {
        activeCheckoutSession.order = order
        if createPayment {
            activeCheckoutSession.lifecycleState = .completed
            activeCheckoutSession.completedAt = Date()
            if let latest = activeCheckoutSession.paymentAttempts.max(by: { $0.updatedAt < $1.updatedAt }) {
                latest.method = (paymentMethod ?? selectedPaymentMethod).lowercased().replacingOccurrences(of: " ", with: "_")
                latest.lifecycleState = .captured
            }
            let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? "local-device"
            activeCheckoutSession.releaseLock(deviceId: deviceId)
        }
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

        // Revert the entire checkout unit, including stock and promotion counters.
        modelContext.rollback()
        lastCheckoutError = "Failed to save checkout: \(error.localizedDescription)"
        return nil
    }
    cart.removeAll()
    recalledHeldOrder = nil
    activeCheckoutSession = nil
    selectedCustomer = nil
    selectedGiftCard = nil
    giftCardRedeemAmount = 0.0
    useLoyaltyPoints = false
    redeemLoyaltyPoints = 0
    clearAppliedCoupon()
    resetPromotionSelection()
    if tableSession == nil {
        currentQueueNumber = ""
        currentReceiptNumber = ""
        currentBillNumber = "AP-NEW"
    }
    platformOrderNumber = ""
    if selectedOrderType == "delivery" {
        deliveryBrand = nil
        deliveryGP = 0
        deliveryAdFee = 0
        deliveryAdFeeIsPct = false
        deliveryOtherFee = 0
        repriceCart()
    }
    if tableSession == nil {
        // Quick Service is always ready for the next counter customer.
        selectedOrderType = "take_out"
    } else if selectedOrderType == "delivery" {
        selectedOrderType = "dine_in"
    }

    // C-2: Loyalty Points Accrue — only on actual payment (not send-to-kitchen)
    if createPayment, let customer = order.customer {
        let pointsPerBaht = Double(
            UserDefaults.standard.string(forKey: "loyalty_points_per_baht") ?? "0.05"
        ) ?? 0.05
        let earnedPoints = Int((order.total * pointsPerBaht).rounded(.down))
        if earnedPoints > 0 {
            customer.loyaltyPoints += earnedPoints
            customer.totalSpend   += order.total
            // M-3: Loyalty Tier Auto-Upgrade — resolve tier from accumulated spend
            customer.membershipTier = resolvedTier(for: customer.totalSpend)
            customer.visitCount   += 1
            customer.isSynced      = false
            customer.updatedAt     = Date()
            let loyaltyTx = LoyaltyTransaction(
                customer: customer,
                order: order,
                transactionType: "earn",
                points: earnedPoints,
                pointsBalanceAfter: customer.loyaltyPoints,
                transactionDescription: "Earned from order \(order.orderNumber)",
                // M-4: set expiresAt = 1 year from now (configurable via "loyalty_points_expiry_days")
                expiresAt: {
                    let days = UserDefaults.standard.integer(forKey: "loyalty_points_expiry_days")
                    return days > 0
                        ? Calendar.current.date(byAdding: .day, value: days, to: Date())
                        : Calendar.current.date(byAdding: .year, value: 1, to: Date())
                }(),
                earnedAt: Date()
            )
            modelContext.insert(loyaltyTx)
        }
    }

    // Close dine-in table session only after actual payment, not when sending to kitchen.
    if createPayment, selectedOrderType == "dine_in", let session = tableSession {
        session.isActive = false
        session.endedAt = Date()
        session.isSynced = false
        session.updatedAt = Date()
        modelContext.saveWithLogging(label: #function)
    }

    // A paid direct/Quick Service order is financially completed, but its prep
    // items remain cooking until KDS finishes them. Payment settlement and kitchen
    // fulfilment are separate lifecycles; marking items served here made paid Quick
    // Service tickets disappear from KDS before the kitchen could see them.
    if createPayment, tableSession == nil, order.status != "cancelled" {
        order.status = "completed"
        order.isSynced = false
        order.updatedAt = Date()
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
    let triggerQtyInCart = cart.filter { $0.snapshotItemId == triggerItemId }.reduce(0) { $0 + $1.quantity }
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
        lineType: .promotionReward,
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
        let triggerQtyInCart = cart.filter { $0.snapshotItemId == triggerItemId }.reduce(0) { $0 + $1.quantity }
        bundleCount = triggerQtyInCart / promotion.requiredQuantity
    }

    guard bundleCount > 0 else { return }

    // For each bundle component, check if it's already in the cart
    let cartItemIds = Set(cart.map { $0.snapshotItemId })

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
            lineType: .bundleComponent,
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
            currentQueueNumber = NetworkManager.sanitizeQueueNumber(q) ?? q
        }
        selectedCustomer = order.customer
        deliveryBrand = order.deliveryBrand
        deliveryGP = order.deliveryGP
        deliveryAdFee = order.deliveryAdFee
        deliveryAdFeeIsPct = order.deliveryAdFeeIsPct
        deliveryOtherFee = order.deliveryOtherFee
        platformOrderNumber = order.platformOrderNumber ?? ""

        for orderItem in order.items.filter({ !$0.isDeleted }) {
            if let menuItem = orderItem.menuItem {
                let selectedModifiers = orderItem.modifiers.compactMap { $0.modifier }
                let cartItem = CartItem(
                    item: menuItem,
                    selectedModifiers: selectedModifiers,
                    quantity: orderItem.quantity,
                    notes: orderItem.notes ?? "",
                    unitPrice: orderItem.unitPrice
                )
                cart.append(cartItem)
            }
        }

        recalledHeldOrder = order
    }

    func recallParkedCheckout(_ session: CheckoutSession) {
        guard let order = session.order else { return }
        activeCheckoutSession = session
        recallHeldOrder(order)
    }

    @discardableResult
    func holdCurrentCart() -> Order? {
        guard let modelContext = modelContext, !cart.isEmpty else { return nil }
        let activeBranch = fetchActiveBranch(context: modelContext)

        let finalOrderNum = currentBillNumber.isEmpty || currentBillNumber == "AP-NEW" ? makeOrderNumber() : currentBillNumber
        let appliedPromotion = activePromotion
        let appliedDiscount = cartDiscount
        let resolvedPlatformOrderNumber: String? = {
            guard selectedOrderType == "delivery" else { return nil }
            let normalized = PlatformOrderNumber.applyBrandPrefix(platformOrderNumber, brand: deliveryBrand)
            let body = PlatformOrderNumber.stripKnownPrefix(normalized)
            return body.isEmpty ? nil : normalized
        }()

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
            branch: activeBranch!,
            customer: selectedCustomer,
            heldAt: Date(),
            receiptNumber: nil,
            guestCount: guestCount,
            cashierName: cashierName,
            queueNumber: currentQueueNumber.isEmpty ? nil : currentQueueNumber,
            deliveryBrand: selectedOrderType == "delivery" ? deliveryBrand : nil,
            deliveryGP: selectedOrderType == "delivery" ? deliveryGP : 0,
            deliveryAdFee: selectedOrderType == "delivery" ? deliveryAdFee : 0,
            deliveryAdFeeIsPct: selectedOrderType == "delivery" ? deliveryAdFeeIsPct : false,
            deliveryOtherFee: selectedOrderType == "delivery" ? deliveryOtherFee : 0,
            platformOrderNumber: resolvedPlatformOrderNumber
        )

        if UserDefaults.standard.bool(forKey: GovernmentSupportProgram.enabledSettingsKey),
           selectedSupportProgram == GovernmentSupportProgram.thaiChuaThaiPlus {
            let split = GovernmentSupportProgram.split(total: order.total)
            order.supportProgramName = GovernmentSupportProgram.thaiChuaThaiPlus
            order.supportGovernmentRate = GovernmentSupportProgram.governmentRate
            order.supportCitizenAmount = split.citizen
            order.supportGovernmentAmount = split.government
            order.supportSettlementStatus = "pending"
        }

        modelContext.insert(order)
        if let recalledHeldOrder, recalledHeldOrder.id != order.id {
            recalledHeldOrder.isDeleted = true
            recalledHeldOrder.isSynced = false
            recalledHeldOrder.updatedAt = Date()
        }

        if let appliedPromotion, appliedDiscount > 0 {
            let discountReason: String
            if appliedPromotion.isStaffDiscount {
                discountReason = "Staff discount: \(appliedPromotion.title)"
            } else if let code = appliedCouponCode {
                discountReason = "Coupon \(code): \(appliedPromotion.title)"
            } else if manuallySelectedPromotion?.id == appliedPromotion.id {
                discountReason = "Cashier-selected promotion: \(appliedPromotion.title)"
            } else {
                discountReason = "Auto-applied promotion: \(appliedPromotion.title)"
            }
            let discount = OrderDiscount(
                order: order,
                promotion: appliedPromotion,
                discountType: appliedPromotion.discountType,
                discountValue: appliedPromotion.discountValue,
                discountAmount: appliedDiscount,
                reason: discountReason
            )
            modelContext.insert(discount)
        }

        for cartItem in cart {
            let orderItem = OrderItem(
                order: order,
                menuItem: cartItem.item,
                quantity: cartItem.quantity,
                unitPrice: cartItem.snapshotPrice,
                lineType: cartItem.item.orderItemLineType,
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
            modelContext.rollback()
            return nil
        }
        resetForNextCustomer()

        let auditLog = AuditLog(
            actionType: "order_held",
            details: "Held cart order \(finalOrderNum) — Total: ฿\(String(format: "%.2f", order.total))",
            originalValue: order.total,
            newValue: order.total
        )
        modelContext.insert(auditLog)
        modelContext.saveWithLogging(label: #function)

        APHaptic.trigger()
        return order
    }

    /// Parks the active tender without recording revenue. The attempt is kept
    /// for reconciliation/resume and can never be mistaken for a captured Payment.
    @discardableResult
    func parkCurrentCheckout(method: String) -> CheckoutSession? {
        guard let modelContext, let order = holdCurrentCart(),
              let merchantId = UUID(uuidString: UserDefaults.standard.string(forKey: "active_merchant_id") ?? "")
        else { return nil }

        let session = CheckoutSession(
            merchantId: merchantId,
            order: order,
            serviceMode: POSServiceMode.resolve(orderType: order.orderType, hasTable: false),
            state: .parked,
            parkedAt: Date()
        )
        let attempt = PaymentAttempt(
            merchantId: merchantId,
            checkoutSession: session,
            order: order,
            method: method,
            amount: order.total,
            status: .awaitingCustomer,
            expiresAt: method.lowercased().contains("qr") ? Date().addingTimeInterval(15 * 60) : nil
        )
        modelContext.insert(session)
        modelContext.insert(attempt)
        session.paymentAttempts.append(attempt)
        modelContext.saveWithLogging(label: #function)
        return session
    }

    func resetForNextCustomer() {
        cart.removeAll()
        recalledHeldOrder = nil
        activeCheckoutSession = nil
        selectedCustomer = nil
        selectedGiftCard = nil
        giftCardRedeemAmount = 0
        useLoyaltyPoints = false
        redeemLoyaltyPoints = 0
        currentQueueNumber = ""
        currentReceiptNumber = ""
        currentBillNumber = "AP-NEW"
        guestCount = 1
        deliveryBrand = nil
        selectedSupportProgram = nil
        deliveryGP = 0
        deliveryAdFee = 0
        deliveryAdFeeIsPct = false
        deliveryOtherFee = 0
        platformOrderNumber = ""
        selectedOrderType = "take_out"
        clearAppliedCoupon()
        resetPromotionSelection()
    }

    /// Checks if adding a menuItem and its modifiers is allowed based on ingredient/modifier stock levels.
    func checkStockBeforeAdding(_ item: MenuItem, modifiers: [Modifier], quantity: Int = 1) -> (allowed: Bool, reason: String?) {
        guard let modelContext = modelContext else { return (true, nil) }

        let activeBranch = fetchActiveBranch(context: modelContext)
        var negativeShortages: [String] = []
        stockWarningMessage = nil

        // 1. Check base recipe — collect short ingredients
        for requirement in StockAvailability.requirements(menuItem: item, activeBranch: activeBranch, modelContext: modelContext) {
            guard let localItem = requirement.local else {
                negativeShortages.append("• \(requirement.source.name) (not configured for this branch)")
                continue
            }
            let required = requirement.required * Double(max(quantity, 0))
            if localItem.currentQuantity < required {
                let detail = String(
                    format: "• %@ (%.1f / %.1f %@)",
                    localItem.name,
                    localItem.currentQuantity,
                    required,
                    localItem.unit
                )
                negativeShortages.append(detail + String(format: " → %.1f", localItem.currentQuantity - required))
            }
        }

        // 2. Check modifiers
        for mod in modifiers {
            if let ingredient = mod.inventoryItemLink, mod.quantityRequired != nil {
                guard let localItem = findBranchInventoryItem(
                    ingredient: ingredient,
                    activeBranch: activeBranch,
                    modelContext: modelContext
                ) else {
                    negativeShortages.append("• \(ingredient.name) (not configured for this branch)")
                    continue
                }
                let required = InventoryRequirementCalculator.required(for: mod, saleQuantity: quantity)
                if localItem.currentQuantity < required {
                    let detail = String(
                        format: "• %@ — %@ (%.1f / %.1f)",
                        mod.name,
                        localItem.name,
                        localItem.currentQuantity,
                        required
                    )
                    negativeShortages.append(detail + String(format: " → %.1f", localItem.currentQuantity - required))
                }
            }
        }

        if !negativeShortages.isEmpty {
            stockWarningMessage = "pos_negative_stock_warning".t + "\n" + negativeShortages.joined(separator: "\n")
        }
        return (true, nil)
    }

    func presentStockWarningIfNeeded() {
        guard let warning = stockWarningMessage else { return }
        // In the inverted backflush model, only show blocking modal alert if user specifically enabled strict alerts.
        // Otherwise, avoid interrupting rapid order entry at the cash register.
        if UserDefaults.standard.bool(forKey: "enable_strict_negative_stock_alert") {
            presentAlert(warning)
        } else {
            AppLogger.pos.info("Negative stock sale permitted (backflush): \(warning)")
        }
        stockWarningMessage = nil
    }

    private func deductIngredientsLocally(
        for cartItem: CartItem,
        activeBranch: Branch?,
        baseReferenceId: UUID? = nil,
        modifierReferenceIds: [UUID] = [],
        branchInventoryCache: [String: InventoryItem]? = nil
    ) {
    guard let modelContext = modelContext else { return }

    func alreadyRecorded(_ referenceId: UUID?, item: InventoryItem) -> Bool {
        guard let referenceId else { return false }
        let itemID = item.id
        let descriptor = FetchDescriptor<InventoryTransaction>(predicate: #Predicate {
            !$0.isDeleted && $0.referenceId == referenceId
        })
        let movements = (try? modelContext.fetch(descriptor)) ?? []
        return movements.contains {
            $0.item?.id == itemID && $0.transactionType == InventoryMovementType.sell.rawValue
        }
    }

    // Re-fetch a fresh, valid MenuItem by id rather than trusting the cart's
    // possibly-invalidated reference (a background sync may have deleted the
    // original model since it was added to the cart). If it no longer exists,
    // skip recipe deduction gracefully instead of crashing.
    let freshItemId = cartItem.snapshotItemId
    var __desc = FetchDescriptor<MenuItem>(predicate: #Predicate { $0.id == freshItemId })
    __desc.fetchLimit = 1
    guard let liveItem = try? modelContext.fetch(__desc).first else { return }

    // Base menu recipes deduction
        for requirement in StockAvailability.requirements(menuItem: liveItem, activeBranch: activeBranch, modelContext: modelContext) {
            guard let localItem = requirement.local else { continue }
            // Checkout retries/reconciliation can call this method more than
            // once. A sale reference may deduct a given ingredient only once.
            guard !alreadyRecorded(baseReferenceId, item: localItem) else { continue }
            let qtyDeducted = requirement.required * Double(max(cartItem.quantity, 0))
            localItem.currentQuantity -= qtyDeducted
            localItem.updatedAt = Date()
            localItem.isSynced = false

            // Consume from FEFO lots to keep lots in sync with currentQuantity
            let expiryManager = InventoryExpiryManager.shared(for: modelContext)
            let consumption = expiryManager.consumeFEFO(item: localItem, quantity: qtyDeducted)

            let txn = InventoryTransaction(
                item: localItem,
                transactionType: InventoryMovementType.sell.rawValue,
                quantity: -qtyDeducted,
                costPrice: consumption.consumed.isEmpty
                    ? localItem.costPrice
                    : consumption.totalCOGS / consumption.consumed.reduce(0) { $0 + $1.quantityTaken },
                referenceId: baseReferenceId,
                notes: "Local POS checkout deduct for \(cartItem.snapshotName) (Qty: \(cartItem.quantity))",
                branch: activeBranch!
            )
            modelContext.insert(txn)
            BusinessDayContext.stamp(inventoryTransaction: txn, in: modelContext)
            for allocation in consumption.consumed {
                modelContext.insert(InventoryLotAllocation(
                    movementId: txn.id,
                    referenceId: baseReferenceId,
                    inventoryItemId: localItem.id,
                    lotId: allocation.lot.id,
                    quantity: allocation.quantityTaken,
                    costPrice: allocation.lot.lotCostPrice
                ))
            }
    }

    // Modifier recipes deduction
    for (index, mod) in cartItem.selectedModifiers.enumerated() {
        if let ingredient = mod.inventoryItemLink, mod.quantityRequired != nil {
            var localItem: InventoryItem? = ingredient
            if let activeBranch = activeBranch, ingredient.branch?.id != activeBranch.id {
                let key = ingredient.sku ?? ingredient.name
                if let cached = branchInventoryCache?[key] {
                    localItem = cached
                } else {
                    localItem = nil
                }
            }

            guard let localItem else { continue }
            guard !alreadyRecorded(modifierReferenceIds.indices.contains(index) ? modifierReferenceIds[index] : baseReferenceId, item: localItem) else { continue }

            let qtyDeducted = InventoryRequirementCalculator.required(for: mod, saleQuantity: cartItem.quantity)
            localItem.currentQuantity -= qtyDeducted
            localItem.updatedAt = Date()
            localItem.isSynced = false

            // Consume from FEFO lots to keep lots in sync with currentQuantity
            let expiryManager = InventoryExpiryManager.shared(for: modelContext)
            let consumption = expiryManager.consumeFEFO(item: localItem, quantity: qtyDeducted)

            let txn = InventoryTransaction(
                item: localItem,
                transactionType: InventoryMovementType.sell.rawValue,
                quantity: -qtyDeducted,
                costPrice: consumption.consumed.isEmpty
                    ? localItem.costPrice
                    : consumption.totalCOGS / consumption.consumed.reduce(0) { $0 + $1.quantityTaken },
                referenceId: modifierReferenceIds.indices.contains(index) ? modifierReferenceIds[index] : baseReferenceId,
                notes: "Modifier deduct: \(mod.name) for \(cartItem.snapshotName) (Qty: \(cartItem.quantity))",
                branch: activeBranch!
            )
            modelContext.insert(txn)
            BusinessDayContext.stamp(inventoryTransaction: txn, in: modelContext)
            for allocation in consumption.consumed {
                modelContext.insert(InventoryLotAllocation(
                    movementId: txn.id,
                    referenceId: txn.referenceId,
                    inventoryItemId: localItem.id,
                    lotId: allocation.lot.id,
                    quantity: allocation.quantityTaken,
                    costPrice: allocation.lot.lotCostPrice
                ))
            }
        }
    }

    StockAlertEvaluator.refresh(modelContext: modelContext)
}

    func reverseInventoryDeduction(
        for order: Order,
        specificItems: [OrderItem]? = nil,
        movement: InventoryMovementType = .refundReturn
    ) {
    guard let modelContext = modelContext else { return }

    let itemsToReverse = specificItems ?? order.items.filter { !$0.isDeleted && $0.status != "cancelled" }
    let references = Set(itemsToReverse.flatMap { [$0.id] + $0.modifiers.map(\.id) })
    InventoryReversalService.reverse(
        referenceIds: references,
        as: movement,
        notes: "\(movement.displayName) — Order: \(order.orderNumber)",
        in: modelContext
    )

    modelContext.saveWithLogging(label: #function)

    StockAlertEvaluator.refresh(modelContext: modelContext)

    Task {
        await SyncEngine.shared.syncAll(modelContext: modelContext)
    }
}

    private func findBranchInventoryItem(
    ingredient: InventoryItem,
    activeBranch: Branch?,
    modelContext: ModelContext
) -> InventoryItem? {
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

    // Never consume inventory from another branch. Missing branch stock is a
    // configuration error and must block the sale instead of silently leaking.
    return nil
}

    private func fetchMenuItem(id: String, modelContext: ModelContext) -> MenuItem? {
    let descriptor = FetchDescriptor<MenuItem>()
    guard let items = try? modelContext.fetch(descriptor) else { return nil }
    return items.first(where: { $0.id == id && !$0.isDeleted })
}
}


extension POSViewModel {
    fileprivate func resolvedTier(for totalSpend: Double) -> String {
        switch totalSpend {
        case 15_000...:
            return "platinum"
        case 5_000..<15_000:
            return "gold"
        case 1_000..<5_000:
            return "silver"
        default:
            return "standard"
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
