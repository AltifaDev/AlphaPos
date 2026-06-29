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

// MARK: - Granular Permissions (24 total)

enum AppPermission: String, CaseIterable, Identifiable {
    // ── Orders & Sales ────────────────────────────────────────
    case posSell            = "pos.sell"              // Take orders, process checkout
    case orderVoid          = "order.void"            // Void/cancel orders
    case refundCreate       = "refund.create"         // Process refunds
    case discountApply      = "discount.apply"        // Apply discounts/promotions
    
    // ── Tables & Floor ────────────────────────────────────────
    case tablesManage       = "tables.manage"         // Manage table layout, sessions
    
    // ── Kitchen ───────────────────────────────────────────────
    case kitchenView        = "kitchen.view"          // View KDS display
    
    // ── Inventory & Menu ──────────────────────────────────────
    case inventoryView      = "inventory.view"        // View menu items & stock
    case inventoryManage    = "inventory.manage"      // Edit menu, manage stock, recipes
    
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
        case .posSell, .orderVoid, .refundCreate, .discountApply:
            return .orders
        case .tablesManage:
            return .tables
        case .kitchenView:
            return .kitchen
        case .inventoryView, .inventoryManage:
            return .inventory
        case .cashDrawerOpen, .cashDrawerManage, .paymentsManage:
            return .finance
        case .customersView, .customersManage, .payrollManage, .staffManage:
            return .people
        case .reportsView, .dashboardView:
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
        case .posSell:              return "perm_pos_sell".t
        case .orderVoid:            return "perm_order_void".t
        case .refundCreate:         return "perm_refund_create".t
        case .discountApply:        return "perm_discount_apply".t
        case .tablesManage:         return "perm_tables_manage".t
        case .kitchenView:          return "perm_kitchen_view".t
        case .inventoryView:        return "perm_inventory_view".t
        case .inventoryManage:      return "perm_inventory_manage".t
        case .cashDrawerOpen:       return "perm_cash_drawer_open".t
        case .cashDrawerManage:     return "perm_cash_drawer_manage".t
        case .paymentsManage:       return "perm_payments_manage".t
        case .customersView:        return "perm_customers_view".t
        case .customersManage:      return "perm_customers_manage".t
        case .payrollManage:        return "perm_payroll_manage".t
        case .staffManage:          return "perm_staff_manage".t
        case .reportsView:          return "perm_reports_view".t
        case .dashboardView:        return "perm_dashboard_view".t
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
        case .posSell:              return "perm_pos_sell_desc".t
        case .orderVoid:            return "perm_order_void_desc".t
        case .refundCreate:         return "perm_refund_create_desc".t
        case .discountApply:        return "perm_discount_apply_desc".t
        case .tablesManage:         return "perm_tables_manage_desc".t
        case .kitchenView:          return "perm_kitchen_view_desc".t
        case .inventoryView:        return "perm_inventory_view_desc".t
        case .inventoryManage:      return "perm_inventory_manage_desc".t
        case .cashDrawerOpen:       return "perm_cash_drawer_open_desc".t
        case .cashDrawerManage:     return "perm_cash_drawer_manage_desc".t
        case .paymentsManage:       return "perm_payments_manage_desc".t
        case .customersView:        return "perm_customers_view_desc".t
        case .customersManage:      return "perm_customers_manage_desc".t
        case .payrollManage:        return "perm_payroll_manage_desc".t
        case .staffManage:          return "perm_staff_manage_desc".t
        case .reportsView:          return "perm_reports_view_desc".t
        case .dashboardView:        return "perm_dashboard_view_desc".t
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

    // MARK: - Default Permission Presets (Enterprise)

    private static func defaultPermissions(forRoleName name: String) -> Set<AppPermission> {
        let normalized = name.lowercased()

        // Store Owner / Admin — full access
        if normalized.contains("owner") || normalized.contains("admin") {
            return Set(AppPermission.allCases)
        }

        // Manager — everything except org management
        if normalized.contains("manager") {
            return Set(AppPermission.allCases).subtracting([
                .organizationManage  // Only owner can manage billing/subscription
            ])
        }

        // Supervisor / Team Lead — operational + some admin
        if normalized.contains("supervisor") || normalized.contains("lead") {
            return [
                .posSell, .orderVoid, .refundCreate, .discountApply,
                .tablesManage, .kitchenView,
                .inventoryView, .inventoryManage,
                .cashDrawerOpen, .cashDrawerManage,
                .customersView, .customersManage,
                .reportsView, .dashboardView,
                .devicesView,
                .staffManage, .payrollManage,
                .managerOverride
            ]
        }

        // Cashier — POS operations + limited views
        if normalized.contains("cashier") {
            return [
                .posSell, .discountApply,
                .cashDrawerOpen,
                .tablesManage,
                .kitchenView,
                .customersView,
                .dashboardView
            ]
        }

        // Kitchen / Cook — kitchen only
        if normalized.contains("kitchen") || normalized.contains("cook") || normalized.contains("chef") {
            return [.kitchenView]
        }

        // Waiter / Server — tables + POS
        if normalized.contains("wait") || normalized.contains("server") {
            return [.posSell, .tablesManage, .kitchenView, .customersView]
        }

        // Host / Receptionist — tables + customers
        if normalized.contains("host") || normalized.contains("reception") {
            return [.tablesManage, .customersView]
        }

        // Default fallback — basic POS only
        return [.posSell, .discountApply, .cashDrawerOpen]
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
            case .manager: return "All operations, limited org settings"
            case .supervisor: return "Team operations + staff management"
            case .cashier: return "POS, cash drawer, basic views"
            case .waiter: return "Tables, orders, kitchen view"
            case .kitchen: return "Kitchen display only"
            case .host: return "Table management, reservations"
            }
        }
    }
}
