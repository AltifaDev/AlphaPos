import Foundation
import SwiftData

@Model
final class Employee {
    @Attribute(.unique) var id: UUID
    var user: User? // Maps to system login details
    var firstName: String
    var lastName: String
    var phone: String?
    var nationalId: String? // For Tax & Social Security calculations
    var bankAccountNumber: String?
    var bankName: String?
    var employmentType: String // "hourly", "daily", "monthly"
    var payRate: Double // Hourly rate or base monthly salary
    var joinedAt: Date
    var resignedAt: Date?
    /// Operational ownership. Kept as UUID text to avoid coupling employee
    /// history to deletion of a local Branch object.
    var branchId: String = ""
    /// Explicit authorization for the companion Staff app. Employment and
    /// login eligibility are separate concerns; never infer this from the
    /// mere existence of an Employee row.
    var staffAppEnabled: Bool = false
    
    // Local Facial Template stored as Binary Data for CoreML comparison
    var faceEmbeddingData: Data?
    var faceRegisteredAt: Date?
    /// Durable intent marker. A nil local embedding can mean that this device
    /// has not loaded the private template; only an explicit clear operation
    /// may remove the server-side biometric template.
    var faceEmbeddingNeedsRemoteClear: Bool = false
    
    // Standard HR compliance fields
    var email: String?
    var dateOfBirth: Date?
    var address: String?
    var emergencyContactName: String?
    var emergencyContactPhone: String?
    
    @Relationship(deleteRule: .cascade, inverse: \EmployeeShift.employee)
    var shifts: [EmployeeShift] = []
    
    @Relationship(deleteRule: .cascade, inverse: \Timecard.employee)
    var timecards: [Timecard] = []
    
    // Offline-First Sync Metadata
    var isSynced: Bool
    var isDeleted: Bool
    var updatedAt: Date
    
    init(
        id: UUID = UUID(),
        user: User? = nil,
        firstName: String,
        lastName: String,
        phone: String? = nil,
        nationalId: String? = nil,
        bankAccountNumber: String? = nil,
        bankName: String? = nil,
        employmentType: String,
        payRate: Double,
        joinedAt: Date = Date(),
        resignedAt: Date? = nil,
        branchId: String = "",
        staffAppEnabled: Bool = false,
        faceEmbeddingData: Data? = nil,
        faceRegisteredAt: Date? = nil,
        faceEmbeddingNeedsRemoteClear: Bool = false,
        email: String? = nil,
        dateOfBirth: Date? = nil,
        address: String? = nil,
        emergencyContactName: String? = nil,
        emergencyContactPhone: String? = nil,
        isSynced: Bool = false,
        isDeleted: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.user = user
        self.firstName = firstName
        self.lastName = lastName
        self.phone = phone
        self.nationalId = nationalId
        self.bankAccountNumber = bankAccountNumber
        self.bankName = bankName
        self.employmentType = employmentType
        self.payRate = payRate
        self.joinedAt = joinedAt
        self.resignedAt = resignedAt
        self.branchId = branchId
        self.staffAppEnabled = staffAppEnabled
        self.faceEmbeddingData = faceEmbeddingData
        self.faceRegisteredAt = faceRegisteredAt
        self.faceEmbeddingNeedsRemoteClear = faceEmbeddingNeedsRemoteClear
        self.email = email
        self.dateOfBirth = dateOfBirth
        self.address = address
        self.emergencyContactName = emergencyContactName
        self.emergencyContactPhone = emergencyContactPhone
        self.isSynced = isSynced
        self.isDeleted = isDeleted
        self.updatedAt = updatedAt
    }
}
