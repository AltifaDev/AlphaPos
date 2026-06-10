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
    var serviceCharge: Double
    var discount: Double
    var total: Double
    var createdAt: Date
    
    @Relationship(deleteRule: .cascade, inverse: \OrderItem.order)
    var items: [OrderItem] = []
    
    @Relationship(deleteRule: .cascade, inverse: \Payment.order)
    var payments: [Payment] = []
    
    var branch: Branch?
    
    // Offline-First Sync Metadata
    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date
    
    var guestCount: Int = 2
    var cashierName: String = "Alex M."
    var queueNumber: String? = nil
    
    var deliveryBrand: String? = nil
    var deliveryGP: Double = 0.0
    var deliveryAdFee: Double = 0.0
    var deliveryAdFeeIsPct: Bool = false
    var deliveryOtherFee: Double = 0.0
    
    init(
        id: UUID = UUID(),
        orderNumber: String,
        tableSession: TableSession? = nil,
        orderType: String = "dine_in",
        status: String = "preparing",
        subtotal: Double = 0.0,
        tax: Double = 0.0,
        serviceCharge: Double = 0.0,
        discount: Double = 0.0,
        total: Double = 0.0,
        createdAt: Date = Date(),
        branch: Branch? = nil,
        guestCount: Int = 2,
        cashierName: String = "Alex M.",
        queueNumber: String? = nil,
        deliveryBrand: String? = nil,
        deliveryGP: Double = 0.0,
        deliveryAdFee: Double = 0.0,
        deliveryAdFeeIsPct: Bool = false,
        deliveryOtherFee: Double = 0.0,
        isSynced: Bool = false,
        isDeleted: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.orderNumber = orderNumber
        self.tableSession = tableSession
        self.orderType = orderType
        self.status = status
        self.subtotal = subtotal
        self.tax = tax
        self.serviceCharge = serviceCharge
        self.discount = discount
        self.total = total
        self.createdAt = createdAt
        self.branch = branch
        self.guestCount = guestCount
        self.cashierName = cashierName
        self.queueNumber = queueNumber
        self.deliveryBrand = deliveryBrand
        self.deliveryGP = deliveryGP
        self.deliveryAdFee = deliveryAdFee
        self.deliveryAdFeeIsPct = deliveryAdFeeIsPct
        self.deliveryOtherFee = deliveryOtherFee
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
    }
}
