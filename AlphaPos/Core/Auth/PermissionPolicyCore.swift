import Foundation

/// Foundation-only RBAC policy shared by the app and the standalone test runner.
/// Keeping role normalization here prevents UI and tests from maintaining
/// separate permission rules.
enum PermissionPolicyCore {
    /// Exact legacy aliases only. Display names containing "admin" must never
    /// grant administrator privileges.
    static func normalizedRole(_ name: String) -> String {
        switch name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "owner", "store owner", "เจ้าของร้าน": return "owner"
        case "admin", "administrator": return "admin"
        case "manager", "restaurant manager", "store manager", "branch manager", "ผู้จัดการ", "ผู้จัดการร้าน", "ผู้จัดการสาขา": return "manager"
        case "supervisor", "shift supervisor", "lead", "shift lead", "หัวหน้ากะ": return "supervisor"
        case "cashier", "แคชเชียร์": return "cashier"
        case "kitchen", "kitchen staff", "cook", "line cook", "chef", "head chef", "executive chef", "food preparation worker", "food prep", "prep cook", "dishwasher": return "kitchen"
        case "waiter", "waitress", "waitstaff", "server", "service staff", "staff", "busser", "dining attendant", "busser / dining attendant": return "waiter"
        case "host", "hostess", "host / hostess", "reception": return "host"
        case "bartender", "barista": return "cashier"
        default: return "unknown"
        }
    }
    static func permissionKeys(
        roleName: String,
        explicitCSV: String,
        allKeys: Set<String>
    ) -> Set<String> {
        let normalized = normalizedRole(roleName)

        if normalized == "owner" || normalized == "admin" {
            return allKeys
        }

        let explicit = Set(
            explicitCSV
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { allKeys.contains($0) }
        )
        // A non-empty saved policy with no valid keys means deny, not fallback.
        // "none" is the explicit deny-all marker; empty remains legacy/default.
        if !explicitCSV.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return explicit }

        return defaultPermissionKeys(roleName: roleName, allKeys: allKeys)
    }

    static func defaultPermissionKeys(roleName: String, allKeys: Set<String>) -> Set<String> {
        let normalized = normalizedRole(roleName)

        if normalized == "owner" || normalized == "admin" {
            return allKeys
        }
        if normalized == "manager" {
            return Set([
                "pos.sell", "order.void", "refund.create", "discount.apply",
                "tables.manage", "kitchen.view", "kitchen.manage",
                "inventory.view", "inventory.receive", "inventory.count",
                "cash_drawer.open", "cash_drawer.manage", "customers.view",
                "reports.view", "dashboard.view", "devices.view", "notifications.view"
            ]).intersection(allKeys)
        }
        if normalized == "supervisor" {
            return Set([
                "pos.sell", "order.void", "refund.create", "discount.apply",
                "tables.manage", "kitchen.view", "kitchen.manage",
                "inventory.view", "inventory.count",
                "cash_drawer.open", "cash_drawer.manage",
                "customers.view", "notifications.view"
            ]).intersection(allKeys)
        }
        if normalized == "cashier" {
            return Set([
                "pos.sell", "cash_drawer.open",
                "tables.manage", "kitchen.view", "customers.view", "notifications.view"
            ]).intersection(allKeys)
        }
        if normalized == "kitchen" {
            return Set(["kitchen.view", "kitchen.manage"]).intersection(allKeys)
        }
        if normalized == "waiter" {
            return Set(["pos.sell", "tables.manage", "kitchen.view", "customers.view"]).intersection(allKeys)
        }
        if normalized == "host" {
            return Set(["tables.manage", "customers.view"]).intersection(allKeys)
        }
        return []
    }
}
