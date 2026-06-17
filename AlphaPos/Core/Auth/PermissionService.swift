import Foundation

enum AppPermission: String, CaseIterable, Identifiable {
    case posSell = "pos.sell"
    case orderVoid = "order.void"
    case refundCreate = "refund.create"
    case discountApply = "discount.apply"
    case cashDrawerOpen = "cash_drawer.open"
    case cashDrawerManage = "cash_drawer.manage"
    case tablesManage = "tables.manage"
    case kitchenView = "kitchen.view"
    case inventoryView = "inventory.view"
    case inventoryManage = "inventory.manage"
    case reportsView = "reports.view"
    case payrollManage = "payroll.manage"
    case staffManage = "staff.manage"
    case settingsManage = "settings.manage"
    case deviceManage = "device.manage"
    case managerOverride = "manager.override"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .posSell: return "Sell and take orders"
        case .orderVoid: return "Void orders"
        case .refundCreate: return "Create refunds"
        case .discountApply: return "Apply discounts"
        case .cashDrawerOpen: return "Open cash drawer"
        case .cashDrawerManage: return "Manage cash drawer"
        case .tablesManage: return "Manage tables"
        case .kitchenView: return "View kitchen display"
        case .inventoryView: return "View inventory"
        case .inventoryManage: return "Manage inventory"
        case .reportsView: return "View reports"
        case .payrollManage: return "Manage payroll"
        case .staffManage: return "Manage staff"
        case .settingsManage: return "Manage settings"
        case .deviceManage: return "Manage devices"
        case .managerOverride: return "Manager override"
        }
    }
}

struct PermissionService {
    static func permissions(for role: Role?) -> Set<AppPermission> {
        guard let role else { return [] }

        let explicit = role.permissionKeys
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .compactMap(AppPermission.init(rawValue:))

        if !explicit.isEmpty {
            return Set(explicit)
        }

        return defaultPermissions(forRoleName: role.name)
    }

    static func can(_ permission: AppPermission, role: Role?) -> Bool {
        permissions(for: role).contains(permission)
    }

    static func permissionCSV(for permissions: Set<AppPermission>) -> String {
        permissions.map(\.rawValue).sorted().joined(separator: ",")
    }

    static func permissions(forRoleName name: String) -> Set<AppPermission> {
        defaultPermissions(forRoleName: name)
    }

    private static func defaultPermissions(forRoleName name: String) -> Set<AppPermission> {
        let normalized = name.lowercased()

        if normalized.contains("owner") || normalized.contains("admin") {
            return Set(AppPermission.allCases)
        }

        if normalized.contains("manager") {
            return [
                .posSell,
                .orderVoid,
                .refundCreate,
                .discountApply,
                .cashDrawerOpen,
                .cashDrawerManage,
                .tablesManage,
                .kitchenView,
                .inventoryView,
                .inventoryManage,
                .reportsView,
                .payrollManage,
                .staffManage,
                .managerOverride
            ]
        }

        if normalized.contains("kitchen") || normalized.contains("cook") {
            return [.kitchenView]
        }

        if normalized.contains("wait") || normalized.contains("server") {
            return [.posSell, .tablesManage, .kitchenView]
        }

        return [.posSell, .discountApply, .cashDrawerOpen]
    }
}
