import Foundation

/// Single source of truth for the paired merchant, branch, and signed-in employee.
enum StaffSessionContext {
    private enum Key {
        static let merchantId = "active_merchant_id"
        static let branchId = "active_branch_id"
        static let employeeId = "logged_in_employee_id"
        static let employeeName = "logged_in_employee_name"
    }

    static var merchantId: String { normalized(UserDefaults.standard.string(forKey: Key.merchantId)) }
    static var branchId: String { normalized(UserDefaults.standard.string(forKey: Key.branchId)) }
    static var employeeId: String { normalized(UserDefaults.standard.string(forKey: Key.employeeId)) }
    static var employeeName: String {
        UserDefaults.standard.string(forKey: Key.employeeName)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    static func setMerchant(id: String, branchId: String? = nil) {
        UserDefaults.standard.set(normalized(id), forKey: Key.merchantId)
        if let branchId { UserDefaults.standard.set(normalized(branchId), forKey: Key.branchId) }
    }

    static func setEmployee(id: String, name: String? = nil) {
        UserDefaults.standard.set(normalized(id), forKey: Key.employeeId)
        if let name {
            UserDefaults.standard.set(name.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Key.employeeName)
        }
    }

    static func clearEmployee() {
        UserDefaults.standard.removeObject(forKey: Key.employeeId)
        UserDefaults.standard.removeObject(forKey: Key.employeeName)
    }

    static func clearPairing() {
        clearEmployee()
        UserDefaults.standard.removeObject(forKey: Key.merchantId)
        UserDefaults.standard.removeObject(forKey: Key.branchId)
    }

    private static func normalized(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }
}

enum StaffServiceError: Error, LocalizedError, Equatable {
    case missingEmployeeSession
    case missingMerchantSession
    case missingBranchSession

    var errorDescription: String? {
        switch self {
        case .missingEmployeeSession: return "No employee is signed in."
        case .missingMerchantSession: return "This device is not paired with a store."
        case .missingBranchSession: return "This device is not paired with a branch."
        }
    }
}
