import Foundation

struct RestaurantTable: Codable, Identifiable, Hashable {
    var id: String { tableNumber }
    let tableNumber: String
    let capacity: Int
    let floor: Int
    let zone: String?
    var status: String // "vacant", "occupied", "reserved", "cleaning"
    var guestCount: Int
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
    var quantity: Int          // mutable for edit
    let price: Double
    var status: String         // "cooking", "ready", "served"
    let item_id: String?
    var notes: String?         // special instructions / add-on text
    var servedBy: String?

    enum CodingKeys: String, CodingKey {
        case id, name, quantity, price, status
        case item_id
        case notes
        case servedBy = "served_by"
    }
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
    let floor: Int
    let imageFilename: String
    let isDeleted: Bool
    
    var scale: Double = 1.0
    var offsetX: Double = 0.0
    var offsetY: Double = 0.0
    
    enum CodingKeys: String, CodingKey {
        case id, floor, isDeleted = "is_deleted"
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
