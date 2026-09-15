// PermissionService.swift
// AlphaPos — Enterprise Granular RBAC (v2.0)
// Module-level permissions with category grouping for matrix UI.

import Foundation
import SwiftUI

// MARK: - Permission Categories (for Matrix UI grouping)

enum PermissionCategory: String, CaseIterable, Identifiable {
    case orders = "Orders & Sales"
    case tables = "Tables & Floor"
    case kitchen = "Kitchen"
    case inventory = "Inventory & Menu"
    case finance = "Finance & Payments"
    case people = "People & HR"
    case analytics = "Analytics & Reports"
    case enterprise = "Enterprise"
    case system = "System & Settings"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .orders: return "tray.full.fill"
        case .tables: return "tablecells.fill"
        case .kitchen: return "flame.fill"
        case .inventory: return "fork.knife"
        case .finance: return "creditcard.fill"
        case .people: return "person.2.fill"
        case .analytics: return "chart.bar.fill"
        case .enterprise: return "building.columns.fill"
        case .system: return "gearshape.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .orders: return Color(hex: "3B82F6")
        case .tables: return Color(hex: "0EA5E9")
        case .kitchen: return Color(hex: "F59E0B")
        case .inventory: return Color(hex: "6366F1")
        case .finance: return Color(hex: "10B981")
        case .people: return Color(hex: "8B5CF6")
        case .analytics: return Color(hex: "06B6D4")
        case .enterprise: return Color(hex: "F43F5E")
        case .system: return Color(hex: "9CA3AF")
        }
    }
}

// MARK: - Granular Permissions

enum AppPermission: String, CaseIterable, Identifiable {
    case promotionsManage = "promotions.manage"
    case expensesManage = "expenses.manage"
    case accountingView = "accounting.view"
    case staffPermissionsManage = "staff_permissions.manage"
    case notificationsView = "notifications.view"
    // ── Orders & Sales ────────────────────────────────────────
    case posSell            = "pos.sell"              // Take orders, process checkout
    case orderVoid          = "order.void"            // Void/cancel orders
    case refundCreate       = "refund.create"         // Process refunds
    case discountApply      = "discount.apply"        // Apply discounts/promotions
    
    // ── Tables & Floor ────────────────────────────────────────
    case tablesManage       = "tables.manage"         // Manage table layout, sessions
    
    // ── Kitchen ───────────────────────────────────────────────
    case kitchenView        = "kitchen.view"          // View KDS display
    case kitchenManage      = "kitchen.manage"        // Mark ready, cancel items, clear delivered, recall
    
    // ── Inventory & Menu ──────────────────────────────────────
    case inventoryView      = "inventory.view"        // View menu items & stock
    case inventoryManage    = "inventory.manage"      // Edit menu, manage stock, recipes
    case inventoryReceive   = "inventory.receive"     // Receive and inspect supplier deliveries
    case inventoryAdjust    = "inventory.adjust"      // Waste, return and physical adjustments
    case inventoryTransfer  = "inventory.transfer"   // Transfer stock between branches
    case inventoryCount     = "inventory.count"       // Perform blind counts
    case inventoryApprove   = "inventory.approve"     // Approve variances/over-receipts
    case inventoryRecall    = "inventory.recall"      // Quarantine/release lots and manage recalls
    
    // ── Finance & Payments ────────────────────────────────────
    case cashDrawerOpen     = "cash_drawer.open"      // Open cash drawer
    case cashDrawerManage   = "cash_drawer.manage"    // Full cash drawer management
    case paymentsManage     = "payments.manage"       // Manage payment gateways & methods
    
    // ── People & HR ───────────────────────────────────────────
    case customersView      = "customers.view"        // View customer CRM
    case customersManage    = "customers.manage"      // Edit customer data, segments
    case payrollManage      = "payroll.manage"        // View/manage payroll & shifts
    case staffManage        = "staff.manage"          // Manage staff accounts & roles
    
    // ── Analytics & Reports ───────────────────────────────────
    case reportsView        = "reports.view"          // View reports & analytics
    case dashboardView      = "dashboard.view"        // View live KPI dashboard
    case profitAnalyticsView = "profit_analytics.view" // View profit, margin, and COGS analytics
    case productCostsView   = "product_costs.view"    // View product/recipe cost information
    
    // ── Enterprise ────────────────────────────────────────────
    case devicesView        = "devices.view"          // View device status
    case deviceManage       = "device.manage"         // Manage devices, force sync/wipe
    case organizationView   = "organization.view"     // View org settings
    case organizationManage = "organization.manage"   // Manage org, billing, API keys
    
    // ── System & Settings ─────────────────────────────────────
    case settingsManage     = "settings.manage"       // Manage app settings
    case managerOverride    = "manager.override"      // Override PIN for restricted actions
    case notificationsManage = "notifications.manage" // Configure notification rules

    var id: String { rawValue }

    // MARK: - Category mapping
    
    var category: PermissionCategory {
        switch self {
        case .promotionsManage: return .orders
        case .expensesManage, .accountingView: return .finance
        case .staffPermissionsManage: return .people
        case .notificationsView: return .system
        case .posSell, .orderVoid, .refundCreate, .discountApply:
            return .orders
        case .tablesManage:
            return .tables
        case .kitchenView, .kitchenManage:
            return .kitchen
        case .inventoryView, .inventoryManage, .inventoryReceive, .inventoryAdjust,
             .inventoryTransfer, .inventoryCount, .inventoryApprove, .inventoryRecall:
            return .inventory
        case .cashDrawerOpen, .cashDrawerManage, .paymentsManage:
            return .finance
        case .customersView, .customersManage, .payrollManage, .staffManage:
            return .people
        case .reportsView, .dashboardView, .profitAnalyticsView, .productCostsView:
            return .analytics
        case .devicesView, .deviceManage, .organizationView, .organizationManage:
            return .enterprise
        case .settingsManage, .managerOverride, .notificationsManage:
            return .system
        }
    }

    // MARK: - Display
    
    var title: String {
        switch self {
        case .promotionsManage: return "จัดการโปรโมชั่น / Manage promotions"
        case .expensesManage: return "จัดการค่าใช้จ่าย / Manage expenses"
        case .accountingView: return "ดูบัญชี / View accounting"
        case .staffPermissionsManage: return "กำหนดสิทธิ์พนักงาน / Manage staff permissions"
        case .notificationsView: return "ดูการแจ้งเตือน / View notifications"
        case .posSell:              return "perm_pos_sell".t
        case .orderVoid:            return "perm_order_void".t
        case .refundCreate:         return "perm_refund_create".t
        case .discountApply:        return "perm_discount_apply".t
        case .tablesManage:         return "perm_tables_manage".t
        case .kitchenView:          return "perm_kitchen_view".t
        case .kitchenManage:        return "perm_kitchen_manage".t
        case .inventoryView:        return "perm_inventory_view".t
        case .inventoryManage:      return "perm_inventory_manage".t
        case .inventoryReceive:     return "Receive & Inspect Stock"
        case .inventoryAdjust:      return "Adjust Stock"
        case .inventoryTransfer:    return "Transfer Stock"
        case .inventoryCount:       return "Perform Stock Count"
        case .inventoryApprove:     return "Approve Inventory Changes"
        case .inventoryRecall:      return "Recall & Quarantine"
        case .cashDrawerOpen:       return "perm_cash_drawer_open".t
        case .cashDrawerManage:     return "perm_cash_drawer_manage".t
        case .paymentsManage:       return "perm_payments_manage".t
        case .customersView:        return "perm_customers_view".t
        case .customersManage:      return "perm_customers_manage".t
        case .payrollManage:        return "perm_payroll_manage".t
        case .staffManage:          return "perm_staff_manage".t
        case .reportsView:          return "perm_reports_view".t
        case .dashboardView:        return "perm_dashboard_view".t
        case .profitAnalyticsView:  return "perm_profit_analytics_view".t
        case .productCostsView:     return "perm_product_costs_view".t
        case .devicesView:          return "perm_devices_view".t
        case .deviceManage:         return "perm_device_manage".t
        case .organizationView:     return "perm_org_view".t
        case .organizationManage:   return "perm_org_manage".t
        case .settingsManage:       return "perm_settings_manage".t
        case .managerOverride:      return "perm_manager_override".t
        case .notificationsManage:  return "perm_notifications_manage".t
        }
    }
    
    var description: String {
        switch self {
        case .promotionsManage: return "สร้างและแก้ไขโปรโมชั่น ไม่ใช่สิทธิ์ใช้โปรโมชั่นขณะขาย"
        case .expensesManage: return "เข้าถึงและจัดการค่าใช้จ่าย แยกจากรายงานการขาย"
        case .accountingView: return "เข้าถึงหน้าบัญชี แยกจากรายงานการขายทั่วไป"
        case .staffPermissionsManage: return "กำหนดบทบาทและสิทธิ์ โดยห้ามมอบสิทธิ์เกินกว่าที่ตนมี"
        case .notificationsView: return "อ่านการแจ้งเตือน โดยไม่แก้ไขกฎการแจ้งเตือน"
        case .posSell:              return "perm_pos_sell_desc".t
        case .orderVoid:            return "perm_order_void_desc".t
        case .refundCreate:         return "perm_refund_create_desc".t
        case .discountApply:        return "perm_discount_apply_desc".t
        case .tablesManage:         return "perm_tables_manage_desc".t
        case .kitchenView:          return "perm_kitchen_view_desc".t
        case .kitchenManage:        return "perm_kitchen_manage_desc".t
        case .inventoryView:        return "perm_inventory_view_desc".t
        case .inventoryManage:      return "perm_inventory_manage_desc".t
        case .inventoryReceive:     return "Receive deliveries and record quality checks"
        case .inventoryAdjust:      return "Record waste, returns and stock corrections"
        case .inventoryTransfer:    return "Move inventory between branches"
        case .inventoryCount:       return "Enter blind physical counts"
        case .inventoryApprove:     return "Approve variances, recounts and exceptions"
        case .inventoryRecall:      return "Quarantine lots and run product recalls"
        case .cashDrawerOpen:       return "perm_cash_drawer_open_desc".t
        case .cashDrawerManage:     return "perm_cash_drawer_manage_desc".t
        case .paymentsManage:       return "perm_payments_manage_desc".t
        case .customersView:        return "perm_customers_view_desc".t
        case .customersManage:      return "perm_customers_manage_desc".t
        case .payrollManage:        return "perm_payroll_manage_desc".t
        case .staffManage:          return "perm_staff_manage_desc".t
        case .reportsView:          return "perm_reports_view_desc".t
        case .dashboardView:        return "perm_dashboard_view_desc".t
        case .profitAnalyticsView:  return "perm_profit_analytics_view_desc".t
        case .productCostsView:     return "perm_product_costs_view_desc".t
        case .devicesView:          return "perm_devices_view_desc".t
        case .deviceManage:         return "perm_device_manage_desc".t
        case .organizationView:     return "perm_org_view_desc".t
        case .organizationManage:   return "perm_org_manage_desc".t
        case .settingsManage:       return "perm_settings_manage_desc".t
        case .managerOverride:      return "perm_manager_override_desc".t
        case .notificationsManage:  return "perm_notifications_manage_desc".t
        }
    }
    
    /// Permissions grouped by category (for matrix UI)
    static var grouped: [(category: PermissionCategory, permissions: [AppPermission])] {
        PermissionCategory.allCases.map { category in
            (category: category, permissions: AppPermission.allCases.filter { $0.category == category })
        }
    }
}

// MARK: - Permission Service

struct PermissionService {
    static func permissions(for role: Role?) -> Set<AppPermission> {
        guard let role else { return [] }
        let keys = PermissionPolicyCore.permissionKeys(
            roleName: role.name,
            explicitCSV: role.permissionKeys,
            allKeys: Set(AppPermission.allCases.map(\.rawValue))
        )
        return Set(keys.compactMap(AppPermission.init(rawValue:)))
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

    // MARK: - Default Permission Presets (Enterprise)

    private static func defaultPermissions(forRoleName name: String) -> Set<AppPermission> {
        let keys = PermissionPolicyCore.defaultPermissionKeys(
            roleName: name,
            allKeys: Set(AppPermission.allCases.map(\.rawValue))
        )
        return Set(keys.compactMap(AppPermission.init(rawValue:)))
    }
    
    // MARK: - Role Presets (for quick setup)
    
    enum RolePreset: String, CaseIterable, Identifiable {
        case owner = "Store Owner"
        case manager = "Manager"
        case supervisor = "Supervisor"
        case cashier = "Cashier"
        case waiter = "Waiter"
        case kitchen = "Kitchen Staff"
        case host = "Host"
        
        var id: String { rawValue }
        
        var permissions: Set<AppPermission> {
            PermissionService.defaultPermissions(forRoleName: rawValue)
        }
        
        var description: String {
            switch self {
            case .owner: return "Full access to everything"
            case .manager: return "Branch operations; no payroll, role administration, costs or system settings by default"
            case .supervisor: return "Shift operations and stock counts; no role administration or payroll"
            case .cashier: return "POS, cash drawer, basic views"
            case .waiter: return "Tables, orders, kitchen view"
            case .kitchen: return "Kitchen display only"
            case .host: return "Table management, reservations"
            }
        }
    }
}
