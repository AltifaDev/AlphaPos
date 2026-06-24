import Foundation
import SwiftData

@Model
final class ReceiptTemplate {
    @Attribute(.unique) var id: UUID
    var name: String
    var headerText: String?
    var footerText: String?
    var logoUrl: String?
    var showTaxId: Bool
    var showCustomerInfo: Bool
    var isDefault: Bool

    // Display Controls (v2)
    var paperWidth: String          // "80mm" | "58mm"
    var showServiceCharge: Bool
    var showLogo: Bool
    var showTableInfo: Bool
    var showQRCode: Bool
    var showItemModifiers: Bool
    var showOrderType: Bool

    // Offline-First Sync Metadata
    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        headerText: String? = nil,
        footerText: String? = nil,
        logoUrl: String? = nil,
        showTaxId: Bool = true,
        showCustomerInfo: Bool = true,
        isDefault: Bool = false,
        paperWidth: String = "80mm",
        showServiceCharge: Bool = true,
        showLogo: Bool = true,
        showTableInfo: Bool = true,
        showQRCode: Bool = true,
        showItemModifiers: Bool = true,
        showOrderType: Bool = true,
        isSynced: Bool = false,
        isDeleted: Bool = false,
        updatedAt: Date = Date(),
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.headerText = headerText
        self.footerText = footerText
        self.logoUrl = logoUrl
        self.showTaxId = showTaxId
        self.showCustomerInfo = showCustomerInfo
        self.isDefault = isDefault
        self.paperWidth = paperWidth
        self.showServiceCharge = showServiceCharge
        self.showLogo = showLogo
        self.showTableInfo = showTableInfo
        self.showQRCode = showQRCode
        self.showItemModifiers = showItemModifiers
        self.showOrderType = showOrderType
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
        self.createdAt = createdAt
    }
}
