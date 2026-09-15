import Foundation
import SwiftData

@Model
final class Order {
    @Attribute(.unique) var id: UUID
    var orderNumber: String
    var tableSession: TableSession?
    var orderType: String // "dine_in", "take_out", "delivery"
    var status: String // "preparing", "ready", "served", "completed", "cancelled" -> starts as preparing for kitchen
    var subtotal: Double
    var tax: Double
    // Channel the order originated from: "pos" (iPad), "staff" (iPhone),
    // "web" (customer web ordering). Used to gate kitchen printing — web
    // orders must be confirmed by staff on iPad/iPhone before any ticket
    // is dispatched to the kitchen/bar/sticker printers.
    var orderSource: String = "pos"
    // Staff confirmation flag for remote (web) orders. Kitchen dispatch is
    // blocked while this is false for orderSource == "web".
    var isStaffConfirmed: Bool = true
    var serviceCharge: Double
    var discount: Double
    var total: Double
    var createdAt: Date
    var businessDateKey: String = ""
    var registerSessionId: UUID?
    /// When the kitchen finished the order. Delivery-delay alerts use this,
    /// never the original order creation time.
    var readyAt: Date?
    
    @Relationship(deleteRule: .cascade, inverse: \OrderItem.order)
    var items: [OrderItem] = []
    
    @Relationship(deleteRule: .nullify, inverse: \Payment.order)
    var payments: [Payment] = []
    
    var branch: Branch
    var customer: Customer?
    var heldAt: Date?
    var receiptNumber: String?
    /// Legal document classification captured at checkout; never inferred at reprint time.
    var receiptDocumentType: String = ReceiptDocumentType.receipt.rawValue
    /// Number of successful physical receipt copies. Values above one are reprints.
    var receiptPrintCount: Int = 0
    var receiptLastPrintedAt: Date?
    
    @Relationship(deleteRule: .cascade, inverse: \OrderDiscount.order)
    var discounts: [OrderDiscount] = []
    
    @Relationship(deleteRule: .cascade, inverse: \OrderTaxLine.order)
    var taxLines: [OrderTaxLine] = []
    
    @Relationship(deleteRule: .cascade, inverse: \Tip.order)
    var tips: [Tip] = []
    
    @Relationship(deleteRule: .cascade, inverse: \RefundTransaction.order)
    var refunds: [RefundTransaction] = []
    
    // Offline-First Sync Metadata
    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date
    /// Last server revision used for optimistic concurrency. Zero means the
    /// order has never been observed on the server and may be inserted.
    var rowVersion: Int = 0
    
    var guestCount: Int = 2
    var cashierName: String = "Staff"
    var queueNumber: String? = nil
    
    var deliveryBrand: String? = nil
    var deliveryGP: Double = 0.0
    var deliveryAdFee: Double = 0.0
    var deliveryAdFeeIsPct: Bool = false
    var deliveryOtherFee: Double = 0.0
    /// External ID from Grab / LINE MAN / etc. (manual entry or paste).
    var platformOrderNumber: String? = nil
    /// Government co-payment metadata. This remains independent of orderType
    /// and delivery fields so dine-in/take-out stock and sales stay canonical.
    var supportProgramName: String? = nil
    var supportGovernmentRate: Double = 0.0
    var supportCitizenAmount: Double = 0.0
    var supportGovernmentAmount: Double = 0.0
    /// "not_applicable", "pending", "received", "rejected"
    var supportSettlementStatus: String = "not_applicable"
    /// Dine-in table number captured when the order was sent to the kitchen.
    /// Used to detect orphaned KDS tickets after `tableSession` is nullified.
    /// Counter / quick-sale dine-in orders leave this nil so they still appear on KDS.
    var floorTableNumber: String? = nil
    
    init(
        id: UUID = UUID(),
        orderNumber: String,
        tableSession: TableSession? = nil,
        orderType: String = "dine_in",
        status: String = "preparing",
        subtotal: Double = 0.0,
        tax: Double = 0.0,
        serviceCharge: Double = 0.0,
        orderSource: String = "pos",
        isStaffConfirmed: Bool = true,
        discount: Double = 0.0,
        total: Double = 0.0,
        createdAt: Date = Date(),
        businessDateKey: String = "",
        registerSessionId: UUID? = nil,
        readyAt: Date? = nil,
        branch: Branch,
        customer: Customer? = nil,
        heldAt: Date? = nil,
        receiptNumber: String? = nil,
        guestCount: Int = 2,
        cashierName: String = "Staff",
        queueNumber: String? = nil,
        deliveryBrand: String? = nil,
        deliveryGP: Double = 0.0,
        deliveryAdFee: Double = 0.0,
        deliveryAdFeeIsPct: Bool = false,
        deliveryOtherFee: Double = 0.0,
        platformOrderNumber: String? = nil,
        supportProgramName: String? = nil,
        supportGovernmentRate: Double = 0.0,
        supportCitizenAmount: Double = 0.0,
        supportGovernmentAmount: Double = 0.0,
        supportSettlementStatus: String = "not_applicable",
        floorTableNumber: String? = nil,
        isSynced: Bool = false,
        isDeleted: Bool = false,
        updatedAt: Date = Date(),
        rowVersion: Int = 0
    ) {
        self.id = id
        self.orderNumber = orderNumber
        self.tableSession = tableSession
        self.orderType = orderType
        self.status = status
        self.subtotal = subtotal
        self.tax = tax
        self.orderSource = orderSource
        self.isStaffConfirmed = isStaffConfirmed
        self.serviceCharge = serviceCharge
        self.discount = discount
        self.total = total
        self.createdAt = createdAt
        self.businessDateKey = businessDateKey
        self.registerSessionId = registerSessionId
        self.readyAt = readyAt
        self.branch = branch
        self.customer = customer
        self.heldAt = heldAt
        self.receiptNumber = receiptNumber
        self.guestCount = guestCount
        self.cashierName = cashierName
        self.queueNumber = queueNumber
        self.deliveryBrand = deliveryBrand
        self.deliveryGP = deliveryGP
        self.deliveryAdFee = deliveryAdFee
        self.deliveryAdFeeIsPct = deliveryAdFeeIsPct
        self.deliveryOtherFee = deliveryOtherFee
        self.platformOrderNumber = platformOrderNumber
        self.supportProgramName = supportProgramName
        self.supportGovernmentRate = supportGovernmentRate
        self.supportCitizenAmount = supportCitizenAmount
        self.supportGovernmentAmount = supportGovernmentAmount
        self.supportSettlementStatus = supportSettlementStatus
        self.floorTableNumber = floorTableNumber
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
        self.rowVersion = rowVersion
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Sales Recognition (Single Source of Truth)
// ─────────────────────────────────────────────────────────────────────────────
//
// Historically each screen defined "a sale" differently:
//   • Live Dashboard   → status != "cancelled"            (counted UNPAID open tabs)
//   • Daily/Tax/Menu   → status == "completed"            (dropped PAID direct sales
//                                                           that stay in "preparing")
//   • Monthly report   → status != "cancelled" && paid    (yet another variant)
// This caused dashboard and reports to disagree and reports to under-count revenue,
// because direct checkout (take-out / delivery / quick sale) records a Payment but
// never flips the order to "completed" — it stays "preparing"/"served".
//
// `isRecognizedSale` unifies all of them: an order is a realized sale when it is
// not deleted, not cancelled, and either has at least one (non-deleted) payment
// OR has been explicitly closed as "completed".
extension Order {
    /// Canonical routing classification shared by POS, KDS and reporting.
    /// Quick-service orders are never table orders, even when a legacy row
    /// accidentally contains a non-empty table label.
    var isQuickServiceOrder: Bool {
        orderType != "dine_in" ||
        tableSession == nil && (floorTableNumber == nil || floorTableNumber?.uppercased() == "QUICK")
    }

    var serviceMode: POSServiceMode {
        isQuickServiceOrder ? .quickService : .tableService
    }

    var usesGovernmentSupport: Bool {
        supportProgramName?.isEmpty == false && supportGovernmentAmount > 0
    }

    /// Approved program contribution covers the check even while provider
    /// reconciliation is pending. It is not customer cash and is presented as
    /// payment-program detail, never as a customer debt.
    var coveredAmount: Double { paidAmount + (usesGovernmentSupport ? supportGovernmentAmount : 0) }

    var paidAmount: Double {
        payments
            .filter { !$0.isDeleted && $0.isCaptured }
            .reduce(0) { $0 + $1.amount }
    }

    var outstandingAmount: Double { max(0, total - coveredAmount) }

    var isSettled: Bool {
        total <= 0.005 || outstandingAmount < 0.005
    }

    var paymentStatus: String {
        if refundedTotal >= paidAmount, paidAmount > 0 { return "refunded" }
        if outstandingAmount < 0.005 { return "paid" }
        if paidAmount > 0 { return "partial" }
        return "unpaid"
    }

    /// True when this order should be counted as realized revenue.
    var isRecognizedSale: Bool {
        guard !isDeleted else { return false }
        guard status != "cancelled" else { return false }
        let hasCapturedPayment = payments.contains { !$0.isDeleted && $0.isCaptured }
        return hasCapturedPayment || status == "completed"
    }

    /// Accounting event time for the sale. Paid orders belong to the period in
    /// which money was captured; explicitly completed zero-tender orders fall
    /// back to their order creation time.
    var recognizedAt: Date {
        payments
            .filter { !$0.isDeleted && $0.isCaptured }
            .map(\.paidAt)
            .min() ?? createdAt
    }

    /// Total refunded on this order (from RefundTransaction records).
    var refundedTotal: Double {
        refunds
            .filter { !$0.isDeleted && $0.status == "completed" }
            .reduce(0.0) { $0 + max($1.refundAmount, 0) }
    }

    /// Revenue actually recognized for this order, net of refunds.
    var recognizedNetTotal: Double {
        max(0.0, total - refundedTotal)
    }

    /// Delivery platform costs use revenue after refunds for percentage fees.
    /// Fixed marketing/packaging costs remain because the store already incurred them.
    var deliveryGPFeeAmount: Double {
        orderType == "delivery" ? recognizedNetTotal * min(max(deliveryGP, 0), 100) / 100 : 0
    }

    var deliveryAdFeeAmount: Double {
        guard orderType == "delivery" else { return 0 }
        return deliveryAdFeeIsPct
            ? recognizedNetTotal * min(max(deliveryAdFee, 0), 100) / 100
            : max(deliveryAdFee, 0)
    }

    var deliveryPlatformCost: Double {
        deliveryGPFeeAmount + deliveryAdFeeAmount + (orderType == "delivery" ? max(deliveryOtherFee, 0) : 0)
    }

    var deliveryNetRevenue: Double {
        recognizedNetTotal - deliveryPlatformCost
    }
}
