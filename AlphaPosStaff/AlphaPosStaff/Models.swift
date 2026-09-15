import Foundation

enum StaffPINPolicy {
    static let requiredLength = 4

    static func normalized(_ value: String) -> String {
        String(value.filter(\.isNumber).prefix(requiredLength))
    }

    static func isValid(_ value: String) -> Bool {
        value.count == requiredLength && value.allSatisfy(\.isNumber)
    }
}

struct RestaurantTable: Codable, Identifiable, Hashable, Sendable {
    /// Stable database identity. Legacy payloads may omit it, so the scoped
    /// dining-area/table-number key remains a safe read-only fallback.
    var id: String { restaurantTableId ?? "\(diningAreaId ?? "legacy"):\(tableNumber)" }
    var restaurantTableId: String? = nil
    var branchId: String? = nil
    var diningAreaId: String? = nil
    let tableNumber: String
    let capacity: Int
    let floor: Int
    let zone: String?
    var status: String // "vacant", "occupied", "reserved", "cleaning"
    var guestCount: Int
    var activeSessionId: String? = nil
    var sessionToken: String?
    var isRound: Bool
    var currentTotal: Double
    var positionX: Double
    var positionY: Double
    var sessionStartedAt: String? // ISO8601 timestamp when table was occupied
    
    // MARK: - Computed Properties
    
    /// Elapsed minutes since table was occupied (live-calculated)
    /// Uses ElapsedTimeBadge.parseDate for robust Postgres/Supabase timestamp handling
    var elapsedMinutes: Int {
        guard status.lowercased() == "occupied",
              let startedAtStr = sessionStartedAt else { return 0 }
        
        if let date = ElapsedTimeBadge.parseDate(startedAtStr) {
            return Int(Date().timeIntervalSince(date) / 60)
        }
        return 0
    }
}

/// Branch-scoped dining area shared with AlphaPos (for example Main Hall or
/// Terrace). `floorNumber` is retained only for display/backward compatibility.
struct DiningAreaStaff: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let branchId: String
    let floorNumber: Int
    let name: String
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id, name
        case branchId = "branch_id"
        case floorNumber = "floor_number"
        case sortOrder = "sort_order"
    }
}

struct MenuItem: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let desc: String?
    let price: Double
    let category: String
    let emoji: String?
    let imgClass: String?
    let image_url: String?
    let salesRole: String?

    var orderLineType: String { salesRole == "addon" ? "addon" : "main" }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Modifier Groups & Modifiers (option picker — parity with master device)
// ─────────────────────────────────────────────────────────────────────────────

/// A selectable option within a group (e.g. "เผ็ดมาก", "ชีสพิเศษ").
struct StaffModifier: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let extraPrice: Double
    var isAvailable: Bool = true
}

/// A group of options attached to a menu item (e.g. "ระดับความเผ็ด").
/// `minSelection`/`maxSelection` enforce required/optional and single/multi choice.
struct StaffModifierGroup: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let minSelection: Int
    let maxSelection: Int
    var modifiers: [StaffModifier]

    /// A group is required when at least one selection must be made.
    var isRequired: Bool { minSelection >= 1 }
    /// Single-choice groups render as radio; multi as checkboxes.
    var isSingleChoice: Bool { maxSelection == 1 }
}

/// A cart line = a menu item + chosen quantity + chosen options.
/// Used so each line can carry its own modifier selections (the plain
/// `[MenuItem: Int]` cart cannot represent per-line options).
struct CartLine: Identifiable, Hashable {
    let id: String
    let menuItem: MenuItem
    var quantity: Int
    var selectedModifiers: [StaffModifier]

    init(menuItem: MenuItem, quantity: Int = 1, selectedModifiers: [StaffModifier] = []) {
        self.id = UUID().uuidString
        self.menuItem = menuItem
        self.quantity = quantity
        self.selectedModifiers = selectedModifiers
    }

    /// Per-unit price including selected options.
    var unitPrice: Double {
        menuItem.price + selectedModifiers.reduce(0) { $0 + $1.extraPrice }
    }
    var lineTotal: Double { unitPrice * Double(quantity) }
}


struct OrderItemModifier: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String        // modifier name snapshot (e.g. "เผ็ดมาก", "ชีสพิเศษ")
    let price: Double        // extra price charged for this option

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case price
    }
}

struct OrderItem: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    var quantity: Int          // mutable for edit
    let price: Double
    var status: String         // "cooking", "ready", "served"
    let item_id: String?
    var notes: String?         // special instructions / add-on text
    var servedBy: String?
    var modifiers: [OrderItemModifier] = []   // selected options / add-ons (parity with master device)
    var rowVersion: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, quantity, price, status
        case item_id
        case notes
        case servedBy = "served_by"
        case modifiers
        case rowVersion = "row_version"
    }

    // Custom decoder so `modifiers` is optional (older payloads / joined queries may omit it)
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id       = try c.decode(String.self, forKey: .id)
        name     = try c.decode(String.self, forKey: .name)
        quantity = try c.decodeIfPresent(Int.self, forKey: .quantity) ?? 1
        price    = try c.decodeIfPresent(Double.self, forKey: .price) ?? 0
        status   = try c.decodeIfPresent(String.self, forKey: .status) ?? "cooking"
        item_id  = try c.decodeIfPresent(String.self, forKey: .item_id)
        notes    = try c.decodeIfPresent(String.self, forKey: .notes)
        servedBy = try c.decodeIfPresent(String.self, forKey: .servedBy)
        modifiers = try c.decodeIfPresent([OrderItemModifier].self, forKey: .modifiers) ?? []
        rowVersion = try c.decodeIfPresent(Int.self, forKey: .rowVersion)
    }

    // Memberwise-style init retained for manual construction (parseOrderItems, previews)
    init(id: String, name: String, quantity: Int, price: Double, status: String,
         item_id: String?, notes: String?, servedBy: String?,
         modifiers: [OrderItemModifier] = [], rowVersion: Int? = nil) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.price = price
        self.status = status
        self.item_id = item_id
        self.notes = notes
        self.servedBy = servedBy
        self.modifiers = modifiers
        self.rowVersion = rowVersion
    }
}

struct Order: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let orderNumber: String
    let tableNumber: String
    var total: Double
    var status: String // "preparing", "ready", "served", "completed", "cancelled"
    let createdAt: String
    var items: [OrderItem]
    var tableSessionId: String?
    var sessionToken: String?
    var payments: [OrderPayment]
    var orderSource: String
    var isStaffConfirmed: Bool
    var rowVersion: Int?
    var orderType: String
    var queueNumber: String?
    var receiptNumber: String?
    var deliveryBrand: String?
    var platformOrderNumber: String?

    /// True when this is a counter / quick-sale order (never a real table).
    var isQuickOrder: Bool {
        tableNumber.uppercased() == "QUICK" || tableNumber.isEmpty
    }

    var isAwaitingStaffApproval: Bool {
        let hasUnservedItems = items.contains { $0.status != "served" && $0.status != "cancelled" }
        guard hasUnservedItems else { return false }
        let statusLower = status.lowercased()
        if ["cancelled", "completed", "served"].contains(statusLower) { return false }
        // Confirmed on any device → leave the approval queue (status may lag as pending).
        if isStaffConfirmed { return false }
        return statusLower == "pending" || orderSource.lowercased() == "web"
    }

    var paidAmount: Double {
        payments
            .filter { $0.status.lowercased() == "completed" }
            .reduce(0) { $0 + $1.amount }
    }

    var isPaid: Bool {
        status.lowercased() == "completed" || (paidAmount > 0 && paidAmount >= max(0.01, total - 0.01))
    }

    init(
        id: String,
        orderNumber: String,
        tableNumber: String,
        total: Double,
        status: String,
        createdAt: String,
        items: [OrderItem],
        tableSessionId: String? = nil,
        sessionToken: String?,
        payments: [OrderPayment] = [],
        orderSource: String = "pos",
        isStaffConfirmed: Bool = true,
        rowVersion: Int? = nil,
        orderType: String = "dine_in",
        queueNumber: String? = nil,
        receiptNumber: String? = nil,
        deliveryBrand: String? = nil,
        platformOrderNumber: String? = nil
    ) {
        self.id = id
        self.orderNumber = orderNumber
        self.tableNumber = tableNumber
        self.total = total
        self.status = status
        self.createdAt = createdAt
        self.items = items
        self.tableSessionId = tableSessionId
        self.sessionToken = sessionToken
        self.payments = payments
        self.orderSource = orderSource
        self.isStaffConfirmed = isStaffConfirmed
        self.rowVersion = rowVersion
        self.orderType = orderType
        self.queueNumber = queueNumber
        self.receiptNumber = receiptNumber
        self.deliveryBrand = deliveryBrand
        self.platformOrderNumber = platformOrderNumber
    }

    enum CodingKeys: String, CodingKey {
        case id, orderNumber, tableNumber, total, status, createdAt, items, tableSessionId, sessionToken, payments
        case orderSource, isStaffConfirmed
        case rowVersion = "row_version"
        case orderType, queueNumber, receiptNumber, deliveryBrand, platformOrderNumber
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        orderNumber = try container.decode(String.self, forKey: .orderNumber)
        tableNumber = try container.decode(String.self, forKey: .tableNumber)
        total = try container.decode(Double.self, forKey: .total)
        status = try container.decode(String.self, forKey: .status)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        items = try container.decode([OrderItem].self, forKey: .items)
        tableSessionId = try container.decodeIfPresent(String.self, forKey: .tableSessionId)
        sessionToken = try container.decodeIfPresent(String.self, forKey: .sessionToken)
        payments = try container.decodeIfPresent([OrderPayment].self, forKey: .payments) ?? []
        orderSource = try container.decodeIfPresent(String.self, forKey: .orderSource) ?? "pos"
        isStaffConfirmed = try container.decodeIfPresent(Bool.self, forKey: .isStaffConfirmed) ?? (orderSource != "web")
        rowVersion = try container.decodeIfPresent(Int.self, forKey: .rowVersion)
        orderType = try container.decodeIfPresent(String.self, forKey: .orderType) ?? "dine_in"
        queueNumber = try container.decodeIfPresent(String.self, forKey: .queueNumber)
        receiptNumber = try container.decodeIfPresent(String.self, forKey: .receiptNumber)
        deliveryBrand = try container.decodeIfPresent(String.self, forKey: .deliveryBrand)
        platformOrderNumber = try container.decodeIfPresent(String.self, forKey: .platformOrderNumber)
    }
}

struct OrderPayment: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let amount: Double
    let method: String
    let status: String
    let createdAt: String?
}

struct Employee: Codable, Identifiable, Hashable {
    let id: String
    let firstName: String
    let lastName: String
    let phone: String?
    let nationalId: String?
    let employmentType: String // "hourly", "monthly"
    let payRate: Double
    let username: String
    let role: String
    /// faceRegisteredAt: non-nil means a face template has been saved server-side.
    /// The embedding itself is NEVER fetched to the client.
    let faceRegisteredAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case firstName = "first_name"
        case lastName = "last_name"
        case phone
        case nationalId = "national_id"
        case employmentType = "employment_type"
        case payRate = "pay_rate"
        case username
        case role
        case faceRegisteredAt = "face_registered_at"
    }
}

struct Timecard: Codable, Identifiable, Hashable {
    let id: String
    let employeeId: String
    let employeeName: String
    let clockIn: Double // epoch
    let clockOut: Double? // epoch or nil
    let breakDurationMinutes: Int
    let overtimeMinutes: Int
    var status: String // "approved", "pending_audit", "rejected"
    let notes: String?
    let clockInFaceConfidence: Double?
    let clockOutFaceConfidence: Double?
    let clockInSelfieUrl: String?
    let clockOutSelfieUrl: String?
    let shiftId: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case employeeId = "employee_id"
        case employeeName = "employee_name"
        case clockIn = "clock_in"
        case clockOut = "clock_out"
        case breakDurationMinutes = "break_duration"
        case overtimeMinutes = "overtime_minutes"
        case status
        case notes
        case clockInFaceConfidence = "clock_in_confidence"
        case clockOutFaceConfidence = "clock_out_confidence"
        case clockInSelfieUrl = "clock_in_selfie_url"
        case clockOutSelfieUrl = "clock_out_selfie_url"
        case shiftId = "shift_id"
    }
}

struct ServiceRequest: Codable, Identifiable, Hashable {
    let id: String
    let tableNumber: String
    let requestType: String // "Call Waiter", "Check Bill"
    var status: String // "pending", "completed"
    let createdAt: String
}

struct FloorPlanImageStaff: Codable, Identifiable, Hashable {
    let id: String
    let branchId: String?
    let diningAreaId: String?
    let floor: Int
    let imageFilename: String
    let isDeleted: Bool
    
    var scale: Double = 1.0
    var offsetX: Double = 0.0
    var offsetY: Double = 0.0
    
    enum CodingKeys: String, CodingKey {
        case id, floor, isDeleted = "is_deleted"
        case branchId = "branch_id", diningAreaId = "dining_area_id"
        case imageFilename = "image_filename"
        case scale, offsetX = "offset_x", offsetY = "offset_y"
    }

    /// Resolved absolute path for reading the image file
    var resolvedImagePath: String? {
        guard !imageFilename.isEmpty else { return nil }
        let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docsURL.appendingPathComponent(imageFilename).path
    }
}
