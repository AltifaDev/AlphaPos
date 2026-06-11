import Foundation

struct RestaurantTable: Codable, Identifiable, Hashable {
    var id: String { tableNumber }
    let tableNumber: String
    let capacity: Int
    let floor: Int
    var status: String // "vacant", "occupied", "reserved", "cleaning"
    var guestCount: Int
    var sessionToken: String?
    var currentTotal: Double
    var positionX: Double
    var positionY: Double
}

struct MenuItem: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let desc: String?
    let price: Double
    let category: String
    let emoji: String?
    let imgClass: String?
    let image_url: String?
}

struct OrderItem: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let quantity: Int
    let price: Double
    var status: String // "cooking", "ready", "served"
    let item_id: String?
}

struct Order: Codable, Identifiable, Hashable {
    let id: String
    let orderNumber: String
    let tableNumber: String
    var total: Double
    var status: String // "preparing", "ready", "served", "completed", "cancelled"
    let createdAt: String
    var items: [OrderItem]
    var sessionToken: String?
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
    let pinCode: String?
    
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
        case pinCode = "pin_code"
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
}

struct ServiceRequest: Codable, Identifiable, Hashable {
    let id: String
    let tableNumber: String
    let requestType: String // "Call Waiter", "Check Bill"
    var status: String // "pending", "completed"
    let createdAt: String
}
