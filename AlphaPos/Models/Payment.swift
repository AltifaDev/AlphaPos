import Foundation
import SwiftData

@Model
final class Payment {
    @Attribute(.unique) var id: UUID
    var order: Order?
    var paymentMethod: String // "cash", "credit_card", "qr_promptpay", "true_money"
    var amount: Double
    var transactionReference: String?
    var status: String // "completed", "refunded", "failed"
    var paidAt: Date
    var businessDateKey: String = ""
    var registerSessionId: UUID?
    var tipAmount: Double
    
    // Offline-First Sync Metadata
    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date
    
    init(id: UUID = UUID(), order: Order? = nil, paymentMethod: String, amount: Double, transactionReference: String? = nil, status: String = "completed", paidAt: Date = Date(), businessDateKey: String = "", registerSessionId: UUID? = nil, tipAmount: Double = 0.0, isSynced: Bool = false, isDeleted: Bool = false, updatedAt: Date = Date()) {
        self.id = id
        self.order = order
        self.paymentMethod = paymentMethod.lowercased().replacingOccurrences(of: " ", with: "_")
        self.amount = amount
        self.transactionReference = transactionReference
        self.status = status
        self.paidAt = paidAt
        self.businessDateKey = businessDateKey
        self.registerSessionId = registerSessionId
        self.tipAmount = tipAmount
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
    }

    /// Encodes cash tendered amount for receipt change lines without a schema migration.
    static func cashTenderedReference(_ tendered: Double) -> String {
        String(format: "tendered:%.2f", tendered)
    }

    static func thaiChuaThaiInternalReference(orderNumber: String) -> String {
        "TCT-\(orderNumber)"
    }

    /// Parses tendered cash from `transactionReference` when present.
    var cashTenderedAmount: Double? {
        guard let ref = transactionReference,
              ref.hasPrefix("tendered:"),
              let value = Double(ref.dropFirst("tendered:".count)) else { return nil }
        return value
    }
}

extension Payment {
    var isCaptured: Bool { status == "completed" || status == "captured" }
}
