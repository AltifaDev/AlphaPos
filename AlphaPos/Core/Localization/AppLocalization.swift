//
//  AppLocalization.swift
//  AlphaPos
//
//  Multi-language localization support for AlphaPos iPad POS system.
//  Supports: English, Thai, Chinese, Japanese, Korean, Indonesian, Malay
//

import Foundation
import Combine

// MARK: - AppLanguage

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case thai = "th"
    case chinese = "zh"
    case japanese = "ja"
    case korean = "ko"
    case indonesian = "id"
    case malay = "ms"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: return "English"
        case .thai: return "ภาษาไทย"
        case .chinese: return "简体中文"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        case .indonesian: return "Bahasa Indonesia"
        case .malay: return "Bahasa Melayu"
        }
    }

    var flag: String {
        switch self {
        case .english: return "🇺🇸"
        case .thai: return "🇹🇭"
        case .chinese: return "🇨🇳"
        case .japanese: return "🇯🇵"
        case .korean: return "🇰🇷"
        case .indonesian: return "🇮🇩"
        case .malay: return "🇲🇾"
        }
    }
}

// MARK: - LocalizationManager

class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    @Published var currentLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(currentLanguage.rawValue, forKey: "app_language")
            // Trigger reload animation
            triggerReload()
        }
    }

    @Published var reloadId: UUID = UUID()
    @Published var isReloading: Bool = false

    /// String bridge for views that compare with rawValue (e.g. `lm.languageCode == "th"`)
    var languageCode: String {
        get { currentLanguage.rawValue }
        set {
            if let lang = AppLanguage(rawValue: newValue) {
                currentLanguage = lang
            }
        }
    }

    /// Convenience setter used by SettingsView: `lm.setLanguageWithReload(lang)`
    func setLanguageWithReload(_ language: AppLanguage) {
        currentLanguage = language
        // triggerReload() is called automatically via didSet on currentLanguage
    }

    private func triggerReload() {
        isReloading = true
        reloadId = UUID()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.isReloading = false
        }
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: "app_language") ?? "en"
        self.currentLanguage = AppLanguage(rawValue: saved) ?? .english
    }

    func translate(_ key: String) -> String {
        let lang = currentLanguage.rawValue
        if let entry = AppLocalization.translations[key],
           let value = entry[lang] {
            return value
        }
        // Fallback to English
        if let entry = AppLocalization.translations[key],
           let value = entry["en"] {
            return value
        }
        return key
    }

    // MARK: - Template interpolation overloads
    // Used as: LocalizationManager.shared.t("key_template", arg1, arg2, ...)
    // Template keys use %@ for strings, %d for ints, %f or %.1f for doubles

    func t(_ key: String) -> String {
        translate(key)
    }

    private static func extractFormatSpecifiers(from format: String) -> [String] {
        var specifiers: [String] = []
        let chars = Array(format)
        var i = 0
        while i < chars.count {
            if chars[i] == "%" {
                i += 1
                if i < chars.count {
                    if chars[i] == "%" {
                        i += 1
                        continue
                    }
                    var specifier = "%"
                    while i < chars.count {
                        let c = chars[i]
                        specifier.append(c)
                        i += 1
                        if c == "@" || c == "d" || c == "f" || c == "s" || c == "i" || c == "x" || c == "X" || c == "u" || c == "g" || c == "e" {
                            break
                        }
                        if !c.isLetter && !c.isNumber && c != "." && c != "-" && c != "+" {
                            break
                        }
                    }
                    specifiers.append(specifier)
                }
            } else {
                i += 1
            }
        }
        return specifiers
    }

    private static func safeCVarArg(for arg: CVarArg, specifier: String?) -> CVarArg {
        let spec = specifier?.lowercased() ?? "%@"

        if spec.hasSuffix("@") {
            if let string = arg as? String {
                return string as NSString
            } else if let number = arg as? NSNumber {
                return number
            } else if let int = arg as? Int {
                return NSNumber(value: int)
            } else if let double = arg as? Double {
                return NSNumber(value: double)
            } else if let float = arg as? Float {
                return NSNumber(value: float)
            } else if let bool = arg as? Bool {
                return NSNumber(value: bool)
            } else if let nsObject = arg as? NSObject {
                return nsObject
            } else {
                return String(describing: arg) as NSString
            }
        }

        if spec.hasSuffix("d") || spec.hasSuffix("i") || spec.hasSuffix("u") || spec.hasSuffix("x") || spec.hasSuffix("o") {
            if let int = arg as? Int {
                return int
            } else if let number = arg as? NSNumber {
                return number.intValue
            } else if let double = arg as? Double {
                return Int(double)
            } else if let float = arg as? Float {
                return Int(float)
            } else if let string = arg as? String {
                return Int(string) ?? 0
            } else if let bool = arg as? Bool {
                return bool ? 1 : 0
            } else {
                return 0
            }
        }

        if spec.hasSuffix("f") || spec.hasSuffix("e") || spec.hasSuffix("g") || spec.hasSuffix("a") {
            if let double = arg as? Double {
                return double
            } else if let float = arg as? Float {
                return Double(float)
            } else if let number = arg as? NSNumber {
                return number.doubleValue
            } else if let int = arg as? Int {
                return Double(int)
            } else if let string = arg as? String {
                return Double(string) ?? 0.0
            } else {
                return 0.0
            }
        }

        if let string = arg as? String {
            return string as NSString
        } else if let nsObject = arg as? NSObject {
            return nsObject
        } else {
            return String(describing: arg) as NSString
        }
    }

    func t(_ key: String, _ args: CVarArg...) -> String {
        let format = translate(key)
        guard !args.isEmpty else { return format }

        let specifiers = Self.extractFormatSpecifiers(from: format)

        var safeArgs: [CVarArg] = []
        for idx in 0..<max(args.count, specifiers.count) {
            let specifier = idx < specifiers.count ? specifiers[idx] : nil
            if idx < args.count {
                let arg = args[idx]
                safeArgs.append(Self.safeCVarArg(for: arg, specifier: specifier))
            } else if let spec = specifier {
                let lowerSpec = spec.lowercased()
                if lowerSpec.hasSuffix("@") {
                    safeArgs.append("" as NSString)
                } else if lowerSpec.hasSuffix("d") || lowerSpec.hasSuffix("i") || lowerSpec.hasSuffix("u") || lowerSpec.hasSuffix("x") || lowerSpec.hasSuffix("o") {
                    safeArgs.append(0)
                } else if lowerSpec.hasSuffix("f") || lowerSpec.hasSuffix("e") || lowerSpec.hasSuffix("g") || lowerSpec.hasSuffix("a") {
                    safeArgs.append(0.0)
                } else {
                    safeArgs.append("" as NSString)
                }
            }
        }

        return String(format: format, arguments: safeArgs)
    }
}

// MARK: - String Extension

extension String {
    /// Shorthand for localization: "key".t
    var t: String {
        LocalizationManager.shared.translate(self)
    }

    /// Alternative localization accessor
    func localized() -> String {
        LocalizationManager.shared.translate(self)
    }
}

// MARK: - Localization Keys

enum L {

    enum Nav {
        static let tabTables = "tab_tables"
        static let tabPOS = "tab_pos"
        static let tabCashDrawer = "tab_cash_drawer"
        static let tabKitchen = "tab_kitchen"
        static let tabTimecard = "tab_timecard"
        static let tabInventory = "tab_inventory"
        static let tabGiftCards = "tab_gift_cards"
        static let tabLoyalty = "tab_loyalty"
        static let tabPayroll = "tab_payroll"
        static let tabSales = "tab_sales"
        static let tabReports = "tab_reports"
        static let tabPromotions = "tab_promotions"
        static let tabStore = "tab_store"
        static let tabSyncHealth = "tab_sync_health"
        static let tabSettings = "tab_settings"
        // Enterprise sidebar additions (v3.0)
        static let tabDashboard = "dashboard_nav"
        static let tabNotifications = "notifications_nav"
        static let tabCustomers = "customers_nav"
        static let tabDevices = "devices_nav"
        static let tabOrganization = "organization_nav"
    }

    enum Auth {
        static let sysOnlineSsl = "sys_online_ssl"
        static let cloudEngineVer = "cloud_engine_ver"
        static let signInTitle = "sign_in_title"
        static let signInDesc = "sign_in_desc"
        static let emailLbl = "email_lbl"
        static let passwordLbl = "password_lbl"
        static let forgotPassword = "forgot_password"
        static let rememberStore = "remember_store"
        static let signInBtn = "sign_in_btn"
        static let noAccount = "no_account"
        static let registerBtn = "register_btn"
        static let createTitle = "create_title"
        static let firstName = "first_name"
        static let lastName = "last_name"
        static let confirmPassword = "confirm_password"
        static let continueStore = "continue_store"
        static let alreadyHaveStore = "already_have_store"
        static let storeName = "store_name"
        static let businessType = "business_type"
        static let currency = "currency"
        static let taxId = "tax_id"
        static let contactPhone = "contact_phone"
        static let createStoreBtn = "create_store_btn"
        static let resetTitle = "reset_title"
        static let resetDesc = "reset_desc"
        static let sendResetBtn = "send_reset_btn"
    }

    enum Common {
        static let cancel = "cancel"
        static let save = "save"
        static let done = "done"
        static let delete = "delete"
        static let edit = "edit"
        static let add = "add"
        static let close = "close"
        static let confirm = "confirm"
        static let back = "back"
        static let next = "next"
        static let search = "search"
        static let loading = "loading"
        static let error = "error"
        static let success = "success"
        static let retry = "retry"
    }

    enum Sections {
        static let kds = "section_kds"
        static let tableSystem = "section_table_system"
        static let appearance = "section_appearance"
        static let account = "section_account"
        static let general = "section_general"
        static let printer = "section_printer"
        static let security = "section_security"
        static let linkStaff = "section_link_staff"
        static let systemOps = "section_system_ops"
        static let taxRates = "section_tax_rates"
        static let receiptTemplates = "section_receipt_templates"
        static let currencyExchange = "section_currency_exchange"
    }

    enum Dashboard {
        static let restaurantManagement = "restaurant_management"
        static let systemOnline = "system_online"
        static let syncSuccess = "sync_success"
        static let syncing = "syncing"
        static let syncFailed = "sync_failed"
        static let offlineMode = "offline_mode"
        static let stockValue = "stock_value"
        static let lowStockAlert = "low_stock_alert"
        static let itemsBelowReorder = "items_below_reorder"
    }

    enum Language {
        static let selectLanguage = "select_language"
        static let desc = "language_desc"
    }

    enum Account {
        static let storeOwner = "store_owner"
        static let changePassword = "change_password"
        static let signOut = "sign_out"
        static let deleteAccount = "delete_account"
    }

    enum Errors {
        static let syncError = "sync_error"
        static let networkError = "network_error"
        static let unknownError = "unknown_error"
        static let timeout = "timeout"
    }

    enum TableSystem {
        static let enableTable = "enable_table"
        static let enableTableDesc = "enable_table_desc"
        static let enableWebOrdering = "enable_web_ordering"
        static let enableWebDesc = "enable_web_desc"
    }

    enum Sales {
        static let tabAnalyticsOverview = "sales_tab_analytics_overview"
        static let tabAnalyticsPL = "sales_tab_analytics_pl"
        static let tabAnalyticsDelivery = "sales_tab_analytics_delivery"
        static let tabAnalyticsMenu = "sales_tab_analytics_menu"
        static let tabAnalyticsInventory = "sales_tab_analytics_inventory"
        static let tabAnalyticsStaff = "sales_tab_analytics_staff"
        static let title = "sales_title"
        static let dailySummary = "sales_daily_summary"
        static let monthlySummary = "sales_monthly_summary"
        static let paymentMethods = "sales_payment_methods"
        static let recentOrders = "sales_recent_orders"
        static let totalRevenue = "sales_total_revenue"
        static let totalOrders = "sales_total_orders"
        static let averageTicketTemplate = "sales_average_ticket_template"
        static let itemsSold = "sales_items_sold"
        static let cancelledItemsTemplate = "sales_cancelled_items_template"
        static let taxCollected = "sales_tax_collected"
        static let salesByOrderType = "sales_by_order_type"
        static let dineIn = "sales_dine_in"
        static let takeOut = "sales_take_out"
        static let delivery = "sales_delivery"
        static let productReportTitle = "sales_product_report_title"
        static let noTopProducts = "sales_no_top_products"
        static let itemNameHeader = "sales_item_name_header"
        static let categoryHeader = "sales_category_header"
        static let qtyHeader = "sales_qty_header"
        static let marginHeader = "sales_margin_header"
        static let cogsFormulaSubtitle = "sales_cogs_formula_subtitle"
        static let profitLoss = "sales_profit_loss"
        static let laborCost = "sales_labor_cost"
        static let laborPctTemplate = "sales_labor_pct_template"
        static let wasteCost = "sales_waste_cost"
        static let wasteFormulaSubtitle = "sales_waste_formula_subtitle"
        static let topMarginProducts = "sales_top_margin_products"
        static let revenueByCategory = "sales_revenue_by_category"
        static let segmentHeader = "sales_segment_header"
    }

    enum Reports {
        static let title = "reports_title"
        static let selectReport = "reports_select_report"
        static let period = "reports_period"
        static let periodDaily = "reports_period_daily"
        static let periodWeekly = "reports_period_weekly"
        static let periodMonthly = "reports_period_monthly"
        static let periodCustom = "reports_period_custom"
        static let startDate = "reports_start_date"
        static let endDate = "reports_end_date"
        static let date = "reports_date"
        static let exportPDF = "reports_export_pdf"
        static let dailySales = "reports_daily_sales"
        static let zReport = "reports_z_report"
        static let taxVAT = "reports_tax_vat"
        static let menuProfit = "reports_menu_profit"
        static let inventory = "reports_inventory"
        static let employeeHours = "reports_employee_hours"
        static let noSession = "reports_no_session"
        static let noSessionDesc = "reports_no_session_desc"
        static let endOfDay = "reports_end_of_day"
        static let sessionInfo = "reports_session_info"
        static let openedAt = "reports_opened_at"
        static let closedAt = "reports_closed_at"
        static let duration = "reports_duration"
        static let cashFlow = "reports_cash_flow"
        static let openingBalance = "reports_opening_balance"
        static let cashSales = "reports_cash_sales"
        static let cashIn = "reports_cash_in"
        static let cashOut = "reports_cash_out"
        static let totals = "reports_totals"
        static let expectedCash = "reports_expected_cash"
        static let actualCash = "reports_actual_cash"
        static let variance = "reports_variance"
        static let varianceShort = "reports_variance_short"
        static let varianceOver = "reports_variance_over"
        static let varianceOk = "reports_variance_ok"
        static let totalLaborHours = "reports_total_labor_hours"
        static let totalLaborCost = "reports_total_labor_cost"
        static let totalOT = "reports_total_ot"
        static let activeStaff = "reports_active_staff"
        static let hoursPerEmployee = "reports_hours_per_employee"
        static let noData = "reports_no_data"
        static let hours = "reports_hours"
        static let regularHours = "reports_regular_hours"
        static let overtimeHours = "reports_overtime_hours"
        static let employeeDetail = "reports_employee_detail"
        static let employee = "reports_employee"
        static let type = "reports_type"
        static let totalHours = "reports_total_hours"
        static let breaks = "reports_breaks"
        static let rate = "reports_rate"
        static let estCost = "reports_est_cost"
        static let total = "reports_total"
        static let hourly = "reports_hourly"
        static let daily = "reports_daily"
        static let monthly = "reports_monthly"
        static let salesIncVAT = "reports_sales_inc_vat"
        static let vatAmount = "reports_vat_amount"
        static let salesExcVAT = "reports_sales_exc_vat"
        static let dailyVATBreakdown = "reports_daily_vat_breakdown"
        static let detailedBreakdown = "reports_detailed_breakdown"
        static let orders = "reports_orders"
        static let totalItems = "reports_total_items"
        static let totalRevenue = "reports_total_revenue"
        static let totalCOGS = "reports_total_cogs"
        static let avgMargin = "reports_avg_margin"
        static let topProfitable = "reports_top_profitable"
        static let leastProfitable = "reports_least_profitable"
        static let menuItemBreakdown = "reports_menu_item_breakdown"
        static let itemName = "reports_item_name"
        static let qtySold = "reports_qty_sold"
        static let revenue = "reports_revenue"
        static let cogs = "reports_cogs"
        static let profit = "reports_profit"
        static let margin = "reports_margin"
        static let grossRevenue = "reports_gross_revenue"
        static let netRevenue = "reports_net_revenue"
        static let totalOrders = "reports_total_orders"
        static let avgTicket = "reports_avg_ticket"
        static let totalDiscount = "reports_total_discount"
        static let totalRefunds = "reports_total_refunds"
        static let paymentMethods = "reports_payment_methods"
        static let peakHour = "reports_peak_hour"
        static let hourlySales = "reports_hourly_sales"
        static let paymentBreakdown = "reports_payment_breakdown"
        static let methodCash = "reports_method_cash"
        static let methodCard = "reports_method_card"
        static let methodQR = "reports_method_qr"
        static let totalStockValue = "reports_total_stock_value"
        static let lowStockCount = "reports_low_stock_count"
        static let outOfStockCount = "reports_out_of_stock_count"
        static let wasteCost = "reports_waste_cost"
        static let outOfStock = "reports_out_of_stock"
        static let reorderLevel = "reports_reorder_level"
        static let outOfStockBadge = "reports_out_of_stock_badge"
        static let lowStock = "reports_low_stock"
        static let noLowStock = "reports_no_low_stock"
        static let wasteAndSpoilage = "reports_waste_and_spoilage"
        static let totalWaste = "reports_total_waste"
        static let noWaste = "reports_no_waste"
        static let quantity = "reports_quantity"
        static let cost = "reports_cost"
        static let notes = "reports_notes"
    }

    enum Promos {
        static let deletePromoBtn = "promos_delete_btn"
        static let title = "promos_title"
        static let subtitle = "promos_subtitle"
        static let addPromotion = "promos_add_promotion"
        static let noPromotionsTitle = "promos_no_promotions_title"
        static let noPromotionsSubtitle = "promos_no_promotions_subtitle"
        static let noDescription = "promos_no_description"
        static let detailsSection = "promos_details_section"
        static let titleLabel = "promos_title_label"
        static let descriptionLabel = "promos_description_label"
        static let statusActive = "promos_status_active"
        static let typeNone = "promos_type_none"
        static let typePercentage = "promos_type_percentage"
        static let typeFixed = "promos_type_fixed"
        static let typeBundle = "promos_type_bundle"
        static let selectProduct = "promos_select_product"
        static let editPromotion = "promos_edit_promotion"
    }

    enum Timecard {
        static let title = "timecard_title"
        static let noEmployeesTitle = "timecard_no_employees_title"
        static let noEmployeesSubtitle = "timecard_no_employees_subtitle"
        static let statStaff = "timecard_stat_staff"
        static let statClockedIn = "timecard_stat_clocked_in"
        static let statApproved = "timecard_stat_approved"
        static let recentActivity = "timecard_recent_activity"
        static let recentRecordsTemplate = "timecard_recent_records_template"
        static let noRecordsYet = "timecard_no_records_yet"
        static let badgeOnShift = "timecard_badge_on_shift"
        static let badgeStaffLabel = "timecard_badge_staff_label"
        static let btnClockOut = "timecard_btn_clock_out"
        static let btnClockIn = "timecard_btn_clock_in"
        static let logActiveNow = "timecard_log_active_now"
        static let badgeApproved = "timecard_badge_approved"
        static let badgePending = "timecard_badge_pending"
        static let scanMsgPosition = "timecard_scan_msg_position"
        static let scanMsgExtracting = "timecard_scan_msg_extracting"
        static let scanMsgComparing = "timecard_scan_msg_comparing"
        static let scanMsgDistance = "timecard_scan_msg_distance"
        static let faceIdSliderLbl = "timecard_face_id_slider_lbl"
        static let faceBtnClockIn = "timecard_face_btn_clock_in"
        static let faceBtnClockOut = "timecard_face_btn_clock_out"
        static let faceScannerTitle = "timecard_face_scanner_title"
    }

    enum Store {
        static let tabProfile = "store_tab_profile"
        static let tabTax = "store_tab_tax"
        static let tabQR = "store_tab_qr"
        static let title = "store_title"
        static let brandingHeader = "store_branding_header"
        static let selectLogo = "store_select_logo"
        static let nameLabel = "store_name_label"
        static let websiteLabel = "store_website_label"
        static let branchLabel = "store_branch_label"
        static let taxInclusiveOpt = "store_tax_inclusive_opt"
        static let taxExclusiveOpt = "store_tax_exclusive_opt"
        static let taxInvoiceHeader = "store_tax_invoice_header"
        static let subtotalLbl = "store_subtotal_lbl"
        static let totalLbl = "store_total_lbl"
        static let qrBrandingHeader = "store_qr_branding_header"
        static let qrStoreNameLbl = "store_qr_store_name_lbl"
        static let qrHeaderLbl = "store_qr_header_lbl"
        static let qrShowLogoToggle = "store_qr_show_logo_toggle"
        static let qrLogoPresetLbl = "store_qr_logo_preset_lbl"
        static let presetBolt = "store_preset_bolt"
        static let presetForkKnife = "store_preset_fork_knife"
        static let presetStar = "store_preset_star"
        static let presetHeart = "store_preset_heart"
        static let presetCoffee = "store_preset_coffee"
        static let presetBeer = "store_preset_beer"
        static let qrThemeColorLbl = "store_qr_theme_color_lbl"
        static let liveQRPreview = "store_live_qr_preview"
    }

    enum Sync {
        static let statusSynced = "sync_status_synced"
        static let statusSyncing = "sync_status_syncing"
        static let statusError = "sync_status_error"
        static let statusOffline = "sync_status_offline"
        static let queueOrders = "sync_queue_orders"
        static let queuePayments = "sync_queue_payments"
        static let queueTables = "sync_queue_tables"
        static let queueMenu = "sync_queue_menu"
        static let queueInventory = "sync_queue_inventory"
        static let queueCustomers = "sync_queue_customers"
        static let queueLoyalty = "sync_queue_loyalty"
        static let queueFinancial = "sync_queue_financial"
        static let title = "sync_title"
        static let syncNowBtn = "sync_now_btn"
        static let summaryStatus = "sync_summary_status"
        static let pendingQueue = "sync_pending_queue"
        static let connection = "sync_connection"
        static let lastSynced = "sync_last_synced"
        static let pendingLabel = "sync_pending_label"
        static let deletedLabel = "sync_deleted_label"
        static let recentActivity = "sync_recent_activity"
        static let noRecentActivity = "sync_no_recent_activity"
        static let connOnline = "sync_conn_online"
        static let connOffline = "sync_conn_offline"
    }
}

// MARK: - Translation Dictionary

enum AppLocalization {
    static let translations: [String: [String: String]] = [
        "staff_permissions_title": ["en": "Staff Permissions", "th": "สิทธิ์พนักงาน"],
        "staff_permissions_desc": ["en": "Manage roles, access, and passcodes.", "th": "จัดการบทบาท สิทธิ์ และรหัสพนักงาน"],
        "staff_permissions_roles": ["en": "Roles and Access", "th": "บทบาทและสิทธิ์"],
        "staff_permissions_role_picker": ["en": "Role", "th": "บทบาท"],
        "save_permissions_btn": ["en": "Save Permissions", "th": "บันทึกสิทธิ์"],
        "staff_passcode_title": ["en": "Staff Passcodes", "th": "รหัสพนักงาน"],
        "staff_picker_title": ["en": "Staff", "th": "พนักงาน"],
        "new_passcode_placeholder": ["en": "New passcode", "th": "รหัสใหม่"],
        "reset_passcode_btn": ["en": "Reset Passcode", "th": "รีเซ็ตรหัส"],
        "settings_saved_title": ["en": "Saved", "th": "บันทึกแล้ว"],
        "permissions_saved_message": ["en": "Role permissions were updated.", "th": "อัปเดตสิทธิ์ของบทบาทแล้ว"],
        "passcode_saved_message": ["en": "Staff passcode was updated.", "th": "อัปเดตรหัสพนักงานแล้ว"],
        "passcode_attempts_title": ["en": "Failed passcode attempts", "th": "จำนวนครั้งที่ใส่รหัสผิด"],
        "passcode_lockout_title": ["en": "Lockout duration", "th": "ระยะเวลาล็อก"],
        "session_timeout_title": ["en": "Staff session timeout", "th": "หมดเวลาเซสชันพนักงาน"],
        "manager_refund_override_title": ["en": "Manager approval for refunds", "th": "ให้ผู้จัดการอนุมัติการคืนเงิน"],
        "manager_void_override_title": ["en": "Manager approval for voids", "th": "ให้ผู้จัดการอนุมัติการยกเลิกบิล"],
        "trusted_devices_title": ["en": "Trusted Devices", "th": "อุปกรณ์ที่เชื่อถือ"],
        "current_device_badge": ["en": "Current", "th": "เครื่องนี้"],
        "splash_secure_pos": ["en": "Secure point of sale", "th": "ระบบขายหน้าร้านที่ปลอดภัย"],
        "staff_lock_title": ["en": "Who is using this register?", "th": "ใครกำลังใช้เครื่องนี้"],
        "staff_lock_desc": ["en": "Select your staff profile and enter your passcode.", "th": "เลือกโปรไฟล์พนักงานและใส่รหัสผ่าน"],
        "staff_lock_staff": ["en": "Staff", "th": "พนักงาน"],
        "use_store_account_btn": ["en": "Use store account", "th": "ใช้บัญชีร้าน"],
        "lock_register_btn": ["en": "Lock register", "th": "ล็อกเครื่องขาย"],
        "tab_tables": ["en": "Tables", "th": "โต๊ะ", "zh": "桌台", "ja": "テーブル", "ko": "테이블", "id": "Meja", "ms": "Meja"],
        "tab_pos": ["en": "Orders", "th": "ออเดอร์", "zh": "订单", "ja": "注文", "ko": "주문", "id": "Pesanan", "ms": "Pesanan"],
        "tab_cash_drawer": ["en": "Cash Drawer", "th": "ลิ้นชักเงินสด", "zh": "钱箱", "ja": "キャッシュドロワー", "ko": "금전함", "id": "Laci Kas", "ms": "Laci Tunai"],
        "tab_kitchen": ["en": "Kitchen Display", "th": "จอครัว", "zh": "厨房显示", "ja": "キッチンディスプレイ", "ko": "주방 디스플레이", "id": "Tampilan Dapur", "ms": "Paparan Dapur"],
        "tab_timecard": ["en": "Timecard", "th": "บัตรเวลา", "zh": "考勤", "ja": "タイムカード", "ko": "타임카드", "id": "Kartu Waktu", "ms": "Kad Masa"],
        "tab_inventory": ["en": "Inventory", "th": "คลังสินค้า", "zh": "库存", "ja": "在庫", "ko": "재고", "id": "Inventaris", "ms": "Inventori"],
        "tab_gift_cards": ["en": "Gift Cards", "th": "บัตรของขวัญ", "zh": "礼品卡", "ja": "ギフトカード", "ko": "기프트 카드", "id": "Kartu Hadiah", "ms": "Kad Hadiah"],
        "tab_loyalty": ["en": "Loyalty", "th": "สะสมแต้ม", "zh": "会员", "ja": "ロイヤルティ", "ko": "로열티", "id": "Loyalitas", "ms": "Kesetiaan"],
        "customer_value_title": ["en": "Customer Value", "th": "สมาชิกและสิทธิประโยชน์", "zh": "客户价值", "ja": "顧客価値", "ko": "고객 가치", "id": "Nilai Pelanggan", "ms": "Nilai Pelanggan"],
        "customer_value_subtitle": ["en": "Manage loyalty, rewards and stored value", "th": "จัดการสมาชิก คะแนน สิทธิประโยชน์ และมูลค่าบัตร", "zh": "管理会员、奖励和储值", "ja": "会員、特典、ストアドバリューを管理", "ko": "멤버십, 리워드 및 충전 금액 관리", "id": "Kelola loyalitas, hadiah, dan saldo tersimpan", "ms": "Urus kesetiaan, ganjaran dan nilai tersimpan"],
        "customer_value_no_results": ["en": "No results found", "th": "ไม่พบข้อมูลที่ค้นหา", "zh": "未找到结果", "ja": "検索結果がありません", "ko": "검색 결과 없음", "id": "Hasil tidak ditemukan", "ms": "Tiada hasil ditemui"],
        "customer_value_search_hint": ["en": "Try a name, phone number, email or card number.", "th": "ลองค้นหาด้วยชื่อ เบอร์โทร อีเมล หรือหมายเลขบัตร", "zh": "尝试姓名、电话、邮箱或卡号。", "ja": "名前、電話番号、メール、カード番号で検索してください。", "ko": "이름, 전화번호, 이메일 또는 카드 번호로 검색하세요.", "id": "Coba nama, telepon, email, atau nomor kartu.", "ms": "Cuba nama, telefon, e-mel atau nombor kad."],
        "loyalty_no_members": ["en": "No members yet", "th": "ยังไม่มีสมาชิก", "zh": "暂无会员", "ja": "会員はまだいません", "ko": "아직 회원이 없습니다", "id": "Belum ada anggota", "ms": "Belum ada ahli"],
        "loyalty_no_members_hint": ["en": "Customers enrolled in loyalty will appear here.", "th": "ลูกค้าที่สมัครสมาชิกสะสมแต้มจะแสดงที่นี่", "zh": "加入会员计划的客户将显示在这里。", "ja": "ロイヤルティに登録した顧客がここに表示されます。", "ko": "로열티에 가입한 고객이 여기에 표시됩니다.", "id": "Pelanggan loyalitas akan muncul di sini.", "ms": "Pelanggan kesetiaan akan dipaparkan di sini."],
        "loyalty_select_customer_hint": ["en": "Select a member to review points, activity and purchase history.", "th": "เลือกสมาชิกเพื่อดูคะแนน กิจกรรม และประวัติการซื้อ", "zh": "选择会员以查看积分、活动和购买记录。", "ja": "会員を選択してポイント、履歴、購入情報を確認します。", "ko": "회원을 선택하여 포인트, 활동 및 구매 내역을 확인하세요.", "id": "Pilih anggota untuk melihat poin dan riwayat.", "ms": "Pilih ahli untuk melihat mata dan sejarah."],
        "gift_card_empty_hint": ["en": "Issue a card to start tracking stored value and activity.", "th": "ออกบัตรใบแรกเพื่อเริ่มติดตามยอดคงเหลือและการใช้งาน", "zh": "发行卡片以开始跟踪储值和活动。", "ja": "カードを発行して残高と利用履歴を管理します。", "ko": "카드를 발급하여 잔액과 사용 내역을 관리하세요.", "id": "Terbitkan kartu untuk mulai melacak saldo.", "ms": "Keluarkan kad untuk mula menjejak baki."],
        "gift_card_select_hint": ["en": "Select a card to view balance, owner, expiry and available actions.", "th": "เลือกบัตรเพื่อดูยอดคงเหลือ เจ้าของ วันหมดอายุ และจัดการบัตร", "zh": "选择卡片以查看余额、持有人、有效期和操作。", "ja": "カードを選択して残高、所有者、有効期限を確認します。", "ko": "카드를 선택하여 잔액, 소유자, 만료일을 확인하세요.", "id": "Pilih kartu untuk melihat saldo dan detail.", "ms": "Pilih kad untuk melihat baki dan butiran."],
        "gift_card_status_active": ["en": "Active", "th": "ใช้งานได้", "zh": "有效", "ja": "有効", "ko": "사용 가능", "id": "Aktif", "ms": "Aktif"],
        "gift_card_status_exhausted": ["en": "Fully redeemed", "th": "ใช้ยอดครบแล้ว", "zh": "已用完", "ja": "使用済み", "ko": "전액 사용", "id": "Saldo habis", "ms": "Baki habis"],
        "gift_card_status_expired": ["en": "Expired", "th": "หมดอายุ", "zh": "已过期", "ja": "期限切れ", "ko": "만료됨", "id": "Kedaluwarsa", "ms": "Tamat tempoh"],
        "gift_card_status_disabled": ["en": "Disabled", "th": "ปิดใช้งาน", "zh": "已停用", "ja": "無効", "ko": "사용 중지", "id": "Dinonaktifkan", "ms": "Dinyahaktif"],
        "email_label": ["en": "Email", "th": "อีเมล", "zh": "邮箱", "ja": "メール", "ko": "이메일", "id": "Email", "ms": "E-mel"],
        "member_since_label": ["en": "Member since", "th": "เป็นสมาชิกตั้งแต่", "zh": "加入日期", "ja": "会員登録日", "ko": "가입일", "id": "Anggota sejak", "ms": "Ahli sejak"],
        "tab_payroll": ["en": "Payroll", "th": "เงินเดือน", "zh": "工资", "ja": "給与", "ko": "급여", "id": "Penggajian", "ms": "Gaji"],
        "tab_sales": ["en": "Accounting", "th": "บัญชี", "zh": "财务", "ja": "会計", "ko": "회계", "id": "Akuntansi", "ms": "Perakaunan"],
        "tab_reports": ["en": "Reports", "th": "รายงาน", "zh": "报表", "ja": "レポート", "ko": "보고서", "id": "Laporan", "ms": "Laporan"],
        "tab_promotions": ["en": "Marketing", "th": "การตลาด", "zh": "营销", "ja": "マーケティング", "ko": "마케팅", "id": "Pemasaran", "ms": "Pemasaran"],
        "tab_store": ["en": "Stores", "th": "สาขา", "zh": "门店管理", "ja": "店舗管理", "ko": "매장 관리", "id": "Toko", "ms": "Kedai"],
        "tab_sync_health": ["en": "Integrations", "th": "การเชื่อมต่อ", "zh": "集成", "ja": "連携", "ko": "연동", "id": "Integrasi", "ms": "Integrasi"],
        "tab_settings": ["en": "Settings", "th": "ตั้งค่า", "zh": "设置", "ja": "設定", "ko": "설정", "id": "Pengaturan", "ms": "Tetapan"],
        // MARK: - Enterprise Sidebar v3.0
        "dashboard_nav": ["en": "Dashboard", "th": "แดชบอร์ด", "zh": "仪表盘", "ja": "ダッシュボード", "ko": "대시보드", "id": "Dasbor", "ms": "Papan Pemuka"],
        "notifications_nav": ["en": "Notifications", "th": "การแจ้งเตือน", "zh": "通知", "ja": "通知", "ko": "알림", "id": "Notifikasi", "ms": "Pemberitahuan"],
        "customers_nav": ["en": "Customers", "th": "ลูกค้า", "zh": "客户", "ja": "顧客", "ko": "고객", "id": "Pelanggan", "ms": "Pelanggan"],
        "devices_nav": ["en": "Devices", "th": "อุปกรณ์", "zh": "设备", "ja": "デバイス", "ko": "장치", "id": "Perangkat", "ms": "Peranti"],
        "organization_nav": ["en": "Organization", "th": "องค์กร", "zh": "组织", "ja": "組織", "ko": "조직", "id": "Organisasi", "ms": "Organisasi"],
        // MARK: - Live Dashboard
        "dashboard_title": ["en": "Dashboard", "th": "แดชบอร์ด", "zh": "仪表盘", "ja": "ダッシュボード", "ko": "대시보드", "id": "Dasbor", "ms": "Papan Pemuka"],
        "dashboard_subtitle": ["en": "Real-time business overview", "th": "ภาพรวมธุรกิจแบบเรียลไทม์", "zh": "实时业务概览", "ja": "リアルタイムビジネス概要", "ko": "실시간 비즈니스 개요", "id": "Gambaran bisnis real-time", "ms": "Gambaran perniagaan masa nyata"],
        "kpi_revenue_today": ["en": "Revenue Today", "th": "รายได้วันนี้", "zh": "今日营收", "ja": "本日の売上", "ko": "오늘 매출", "id": "Pendapatan Hari Ini", "ms": "Hasil Hari Ini"],
        "kpi_active_orders": ["en": "Active Orders", "th": "ออเดอร์ที่กำลังทำ", "zh": "进行中订单", "ja": "進行中の注文", "ko": "진행 중 주문", "id": "Pesanan Aktif", "ms": "Pesanan Aktif"],
        "kpi_table_occupancy": ["en": "Table Occupancy", "th": "อัตราใช้โต๊ะ", "zh": "桌台使用率", "ja": "テーブル稼働率", "ko": "테이블 점유율", "id": "Tingkat Hunian Meja", "ms": "Kadar Penghunian Meja"],
        "kpi_avg_prep_time": ["en": "Avg. Prep Time", "th": "เวลาเตรียมเฉลี่ย", "zh": "平均准备时间", "ja": "平均準備時間", "ko": "평균 준비시간", "id": "Rata-rata Waktu Siap", "ms": "Purata Masa Penyediaan"],
        "kpi_hourly_revenue": ["en": "Hourly Revenue", "th": "รายได้รายชั่วโมง", "zh": "每小时营收", "ja": "1時間あたりの売上", "ko": "시간별 매출", "id": "Pendapatan Per Jam", "ms": "Hasil Setiap Jam"],
        "kpi_top_items": ["en": "Top Selling Items", "th": "สินค้าขายดี", "zh": "热销商品", "ja": "売上トップ商品", "ko": "인기 상품", "id": "Item Terlaris", "ms": "Item Terlaris"],
        "kpi_recent_activity": ["en": "Recent Activity", "th": "กิจกรรมล่าสุด", "zh": "最近活动", "ja": "最近のアクティビティ", "ko": "최근 활동", "id": "Aktivitas Terbaru", "ms": "Aktiviti Terkini"],
        "chart_placeholder": ["en": "Chart will appear here", "th": "กราฟจะแสดงที่นี่", "zh": "图表将显示在此", "ja": "チャートはここに表示されます", "ko": "차트가 여기에 표시됩니다", "id": "Grafik akan muncul di sini", "ms": "Carta akan dipapar di sini"],
        "no_activity_yet": ["en": "No activity yet", "th": "ยังไม่มีกิจกรรม", "zh": "暂无活动", "ja": "まだアクティビティがありません", "ko": "아직 활동이 없습니다", "id": "Belum ada aktivitas", "ms": "Belum ada aktiviti"],
        "kpi_avg_order_value": ["en": "Avg. Order Value", "th": "ยอดเฉลี่ยต่อบิล", "zh": "平均订单金额", "ja": "平均注文額", "ko": "평균 주문 금액", "id": "Rata-rata Nilai Pesanan", "ms": "Purata Nilai Pesanan"],
        "kpi_total_guests": ["en": "Total Guests", "th": "จำนวนลูกค้า", "zh": "总客数", "ja": "総ゲスト数", "ko": "총 고객 수", "id": "Total Tamu", "ms": "Jumlah Tetamu"],
        "kpi_staff_on_duty": ["en": "Staff On Duty", "th": "พนักงานประจำการ", "zh": "在岗员工", "ja": "勤務中スタッフ", "ko": "근무 중 직원", "id": "Staf Bertugas", "ms": "Staf Bertugas"],
        "kpi_orders_completed": ["en": "Completed", "th": "เสร็จแล้ว", "zh": "已完成", "ja": "完了", "ko": "완료", "id": "Selesai", "ms": "Selesai"],
        "kpi_total_today": ["en": "total today", "th": "ทั้งหมดวันนี้", "zh": "今日总计", "ja": "本日合計", "ko": "오늘 합계", "id": "total hari ini", "ms": "jumlah hari ini"],
        "kpi_tables_suffix": ["en": "tables", "th": "โต๊ะ", "zh": "桌", "ja": "テーブル", "ko": "테이블", "id": "meja", "ms": "meja"],
        "kpi_orders_today_suffix": ["en": "orders today", "th": "ออเดอร์วันนี้", "zh": "今日订单", "ja": "本日の注文", "ko": "오늘 주문", "id": "pesanan hari ini", "ms": "pesanan hari ini"],
        "kpi_clocked_in_at": ["en": "In since", "th": "เข้างานตั้งแต่", "zh": "打卡时间", "ja": "出勤", "ko": "출근", "id": "Masuk sejak", "ms": "Masuk sejak"],
        "kpi_no_staff_on_duty": ["en": "No staff on duty", "th": "ไม่มีพนักงานประจำการ", "zh": "无在岗员工", "ja": "勤務中のスタッフなし", "ko": "근무 중인 직원 없음", "id": "Tidak ada staf bertugas", "ms": "Tiada staf bertugas"],
        // MARK: - Notification Center
        "notification_center_title": ["en": "Notification Center", "th": "ศูนย์แจ้งเตือน", "zh": "通知中心", "ja": "通知センター", "ko": "알림 센터", "id": "Pusat Notifikasi", "ms": "Pusat Pemberitahuan"],
        "notification_center_subtitle": ["en": "All alerts from every device", "th": "การแจ้งเตือนทั้งหมดจากทุกอุปกรณ์", "zh": "来自所有设备的提醒", "ja": "すべてのデバイスからのアラート", "ko": "모든 장치의 알림", "id": "Semua peringatan dari setiap perangkat", "ms": "Semua amaran dari setiap peranti"],
        // MARK: - Customer CRM
        "customers_title": ["en": "Customers", "th": "ลูกค้า", "zh": "客户", "ja": "顧客", "ko": "고객", "id": "Pelanggan", "ms": "Pelanggan"],
        "customers_count_suffix": ["en": "customers", "th": "คน", "zh": "位客户", "ja": "名の顧客", "ko": "명의 고객", "id": "pelanggan", "ms": "pelanggan"],
        "add_customer": ["en": "Add Customer", "th": "เพิ่มลูกค้า", "zh": "添加客户", "ja": "顧客を追加", "ko": "고객 추가", "id": "Tambah Pelanggan", "ms": "Tambah Pelanggan"],
        "search_customers": ["en": "Search customers...", "th": "ค้นหาลูกค้า...", "zh": "搜索客户...", "ja": "顧客を検索...", "ko": "고객 검색...", "id": "Cari pelanggan...", "ms": "Cari pelanggan..."],
        "no_customers_found": ["en": "No customers found", "th": "ไม่พบลูกค้า", "zh": "未找到客户", "ja": "顧客が見つかりません", "ko": "고객을 찾을 수 없습니다", "id": "Pelanggan tidak ditemukan", "ms": "Pelanggan tidak dijumpai"],
        "select_customer_prompt": ["en": "Select a customer to view details", "th": "เลือกลูกค้าเพื่อดูรายละเอียด", "zh": "选择客户查看详情", "ja": "顧客を選択して詳細を表示", "ko": "고객을 선택하여 상세보기", "id": "Pilih pelanggan untuk melihat detail", "ms": "Pilih pelanggan untuk melihat butiran"],
        // MARK: - Device Management
        "devices_title": ["en": "Devices & Terminals", "th": "อุปกรณ์และเครื่อง", "zh": "设备与终端", "ja": "デバイスとターミナル", "ko": "장치 및 단말기", "id": "Perangkat & Terminal", "ms": "Peranti & Terminal"],
        "devices_connected": ["en": "devices connected", "th": "อุปกรณ์เชื่อมต่อ", "zh": "设备已连接", "ja": "台のデバイスが接続中", "ko": "대의 장치 연결됨", "id": "perangkat terhubung", "ms": "peranti disambung"],
        "add_device": ["en": "Add Device", "th": "เพิ่มอุปกรณ์", "zh": "添加设备", "ja": "デバイスを追加", "ko": "장치 추가", "id": "Tambah Perangkat", "ms": "Tambah Peranti"],
        // MARK: - Organization Management
        "org_title": ["en": "Organization", "th": "องค์กร", "zh": "组织", "ja": "組織", "ko": "조직", "id": "Organisasi", "ms": "Organisasi"],
        "org_profile": ["en": "Organization Profile", "th": "โปรไฟล์องค์กร", "zh": "组织简介", "ja": "組織プロフィール", "ko": "조직 프로필", "id": "Profil Organisasi", "ms": "Profil Organisasi"],
        "org_subscription": ["en": "Subscription & Plan", "th": "แผนสมาชิก", "zh": "订阅与计划", "ja": "サブスクリプション", "ko": "구독 및 플랜", "id": "Langganan & Paket", "ms": "Langganan & Pelan"],
        "org_billing": ["en": "Billing History", "th": "ประวัติการเรียกเก็บเงิน", "zh": "账单记录", "ja": "請求履歴", "ko": "결제 내역", "id": "Riwayat Tagihan", "ms": "Sejarah Bil"],
        "org_api_keys": ["en": "API Keys & Webhooks", "th": "คีย์ API และ Webhooks", "zh": "API密钥与Webhooks", "ja": "APIキーとWebhooks", "ko": "API 키 및 Webhooks", "id": "Kunci API & Webhooks", "ms": "Kunci API & Webhooks"],
        "org_audit_log": ["en": "Audit Log", "th": "บันทึกตรวจสอบ", "zh": "审计日志", "ja": "監査ログ", "ko": "감사 로그", "id": "Log Audit", "ms": "Log Audit"],
        "org_data_export": ["en": "Data & Backup", "th": "ข้อมูลและสำรอง", "zh": "数据与备份", "ja": "データとバックアップ", "ko": "데이터 및 백업", "id": "Data & Cadangan", "ms": "Data & Sandaran"],
        "org_export_all": ["en": "Export All Data", "th": "ส่งออกข้อมูลทั้งหมด", "zh": "导出所有数据", "ja": "全データをエクスポート", "ko": "모든 데이터 내보내기", "id": "Ekspor Semua Data", "ms": "Eksport Semua Data"],
        "org_backup_history": ["en": "Backup History", "th": "ประวัติสำรองข้อมูล", "zh": "备份记录", "ja": "バックアップ履歴", "ko": "백업 내역", "id": "Riwayat Cadangan", "ms": "Sejarah Sandaran"],
        "org_import_data": ["en": "Import Data", "th": "นำเข้าข้อมูล", "zh": "导入数据", "ja": "データをインポート", "ko": "데이터 가져오기", "id": "Impor Data", "ms": "Import Data"],
        "org_delete_all": ["en": "Delete All Data", "th": "ลบข้อมูลทั้งหมด", "zh": "删除所有数据", "ja": "全データを削除", "ko": "모든 데이터 삭제", "id": "Hapus Semua Data", "ms": "Padam Semua Data"],
        "org_export_all_desc": ["en": "Download complete data as CSV/JSON", "th": "ดาวน์โหลดข้อมูลทั้งหมดเป็น CSV/JSON", "zh": "将完整数据下载为CSV/JSON", "ja": "全データをCSV/JSONでダウンロード", "ko": "전체 데이터를 CSV/JSON으로 다운로드", "id": "Unduh data lengkap sebagai CSV/JSON", "ms": "Muat turun data lengkap sebagai CSV/JSON"],
        "org_backup_history_desc": ["en": "View automatic daily backups", "th": "ดูการสำรองข้อมูลอัตโนมัติรายวัน", "zh": "查看每日自动备份", "ja": "毎日の自動バックアップを表示", "ko": "자동 일일 백업 보기", "id": "Lihat cadangan otomatis harian", "ms": "Lihat sandaran automatik harian"],
        "org_import_data_desc": ["en": "Import from CSV or another POS system", "th": "นำเข้าจาก CSV หรือระบบ POS อื่น", "zh": "从CSV或其他POS系统导入", "ja": "CSVまたは他のPOSシステムからインポート", "ko": "CSV 또는 다른 POS 시스템에서 가져오기", "id": "Impor dari CSV atau sistem POS lain", "ms": "Import dari CSV atau sistem POS lain"],
        "org_delete_all_desc": ["en": "Permanently remove all organization data", "th": "ลบข้อมูลองค์กรทั้งหมดอย่างถาวร", "zh": "永久删除所有组织数据", "ja": "すべての組織データを完全に削除", "ko": "모든 조직 데이터를 영구적으로 삭제", "id": "Hapus semua data organisasi secara permanen", "ms": "Padam semua data organisasi secara kekal"],
        "org_plan_features": ["en": "Unlimited branches • Unlimited devices • Priority support", "th": "สาขาไม่จำกัด • อุปกรณ์ไม่จำกัด • ซัพพอร์ตด่วน", "zh": "无限门店 • 无限设备 • 优先支持", "ja": "無制限の店舗 • 無制限のデバイス • 優先サポート", "ko": "무제한 지점 • 무제한 장치 • 우선 지원", "id": "Cabang tak terbatas • Perangkat tak terbatas • Dukungan prioritas", "ms": "Cawangan tanpa had • Peranti tanpa had • Sokongan keutamaan"],
        "org_billing_desc": ["en": "Invoice history and payment methods will appear here.", "th": "ประวัติใบแจ้งหนี้และช่องทางชำระเงินจะแสดงที่นี่", "zh": "发票记录和支付方式将显示在此", "ja": "請求書履歴と支払い方法がここに表示されます", "ko": "송장 내역 및 결제 방법이 여기에 표시됩니다", "id": "Riwayat faktur dan metode pembayaran akan muncul di sini.", "ms": "Sejarah invois dan kaedah pembayaran akan dipapar di sini."],
        "org_api_keys_desc": ["en": "Manage API keys for third-party integrations and webhook endpoints.", "th": "จัดการคีย์ API สำหรับการเชื่อมต่อกับบริการภายนอก", "zh": "管理第三方集成的API密钥和Webhook端点", "ja": "サードパーティ連携のAPIキーとWebhookエンドポイントを管理", "ko": "서드파티 연동을 위한 API 키 및 Webhook 엔드포인트 관리", "id": "Kelola kunci API untuk integrasi pihak ketiga dan endpoint webhook.", "ms": "Urus kunci API untuk integrasi pihak ketiga dan endpoint webhook."],
        "org_audit_log_desc": ["en": "All administrative actions are logged here for compliance and security.", "th": "การดำเนินการของผู้ดูแลทั้งหมดถูกบันทึกไว้เพื่อความปลอดภัย", "zh": "所有管理操作均记录在此以确保合规和安全", "ja": "すべての管理操作がコンプライアンスとセキュリティのために記録されます", "ko": "모든 관리 작업이 규정 준수 및 보안을 위해 기록됩니다", "id": "Semua tindakan administrasi dicatat di sini untuk kepatuhan dan keamanan.", "ms": "Semua tindakan pentadbiran dicatat di sini untuk pematuhan dan keselamatan."],
        "org_audit_sample": ["en": "Admin updated menu item pricing", "th": "แอดมินอัปเดตราคาเมนู", "zh": "管理员更新了菜品价格", "ja": "管理者がメニュー価格を更新", "ko": "관리자가 메뉴 가격을 업데이트함", "id": "Admin memperbarui harga item menu", "ms": "Admin mengemas kini harga item menu"],
        // MARK: - Notification Center & Device extras
        "escalation_rules_title": ["en": "Escalation Rules", "th": "กฎการยกระดับ", "zh": "升级规则", "ja": "エスカレーションルール", "ko": "에스컬레이션 규칙", "id": "Aturan Eskalasi", "ms": "Peraturan Eskalasi"],
        "escalation_rules_desc": ["en": "Configure alert escalation policies, auto-routing, and notification priorities.", "th": "กำหนดนโยบายการยกระดับแจ้งเตือน การส่งต่ออัตโนมัติ และลำดับความสำคัญ", "zh": "配置告警升级策略、自动路由和通知优先级", "ja": "アラートエスカレーションポリシー、自動ルーティング、通知優先度を設定", "ko": "알림 에스컬레이션 정책, 자동 라우팅, 알림 우선순위 설정", "id": "Konfigurasi kebijakan eskalasi peringatan, routing otomatis, dan prioritas notifikasi.", "ms": "Konfigurasi dasar eskalasi amaran, penghalaan automatik, dan keutamaan pemberitahuan."],
        "notif_mark_all_read": ["en": "Mark all read", "th": "อ่านทั้งหมด", "zh": "全部标为已读", "ja": "すべて既読にする", "ko": "모두 읽음 표시", "id": "Tandai semua dibaca", "ms": "Tanda semua dibaca"],
        "notif_no_alerts": ["en": "No alerts", "th": "ไม่มีการแจ้งเตือน", "zh": "没有提醒", "ja": "アラートなし", "ko": "알림 없음", "id": "Tidak ada peringatan", "ms": "Tiada amaran"],
        "notif_no_alerts_desc": ["en": "All clear! Alerts from orders, kitchen, staff, and devices will appear here.", "th": "เรียบร้อย! การแจ้งเตือนจากออเดอร์ ครัว พนักงาน และอุปกรณ์จะแสดงที่นี่", "zh": "一切正常！来自订单、厨房、员工和设备的提醒将显示在此", "ja": "問題なし！注文、キッチン、スタッフ、デバイスからのアラートがここに表示されます", "ko": "이상 없음! 주문, 주방, 직원, 장치의 알림이 여기에 표시됩니다", "id": "Semua beres! Peringatan dari pesanan, dapur, staf, dan perangkat akan muncul di sini.", "ms": "Semua teratur! Amaran dari pesanan, dapur, staf, dan peranti akan dipapar di sini."],
        "notif_just_now": ["en": "just now", "th": "เมื่อกี้", "zh": "刚刚", "ja": "たった今", "ko": "방금", "id": "baru saja", "ms": "baru sahaja"],
        "notif_min_ago": ["en": "min ago", "th": "นาทีที่แล้ว", "zh": "分钟前", "ja": "分前", "ko": "분 전", "id": "menit lalu", "ms": "minit lalu"],
        "notif_hr_ago": ["en": "hr ago", "th": "ชั่วโมงที่แล้ว", "zh": "小时前", "ja": "時間前", "ko": "시간 전", "id": "jam lalu", "ms": "jam lalu"],
        "service_request_alert_title": ["en": "Service Request", "th": "เรียกพนักงาน", "zh": "服务请求", "ja": "サービスリクエスト", "ko": "서비스 요청", "id": "Permintaan Layanan", "ms": "Permintaan Perkhidmatan"],
        "table": ["en": "Table", "th": "โต๊ะ", "zh": "桌", "ja": "テーブル", "ko": "테이블", "id": "Meja", "ms": "Meja"],
        // MARK: - Escalation Settings
        "escalation_timing_section": ["en": "Escalation Timing", "th": "ระยะเวลายกระดับ", "zh": "升级时间", "ja": "エスカレーションタイミング", "ko": "에스컬레이션 시간", "id": "Waktu Eskalasi", "ms": "Masa Eskalasi"],
        "escalation_critical_timeout": ["en": "Critical alert repeat", "th": "แจ้งซ้ำระดับวิกฤต", "zh": "严重告警重复", "ja": "クリティカルアラート繰り返し", "ko": "긴급 알림 반복", "id": "Pengulangan peringatan kritis", "ms": "Ulangan amaran kritikal"],
        "escalation_high_timeout": ["en": "High alert escalation", "th": "ยกระดับแจ้งเตือนสำคัญ", "zh": "高级告警升级", "ja": "高アラートエスカレーション", "ko": "높은 알림 에스컬레이션", "id": "Eskalasi peringatan tinggi", "ms": "Eskalasi amaran tinggi"],
        "escalation_behavior_section": ["en": "Alert Behavior", "th": "พฤติกรรมการแจ้งเตือน", "zh": "告警行为", "ja": "アラート動作", "ko": "알림 동작", "id": "Perilaku Peringatan", "ms": "Tingkah Laku Amaran"],
        "escalation_auto_sound": ["en": "Play sound for critical alerts", "th": "เล่นเสียงสำหรับแจ้งเตือนวิกฤต", "zh": "严重告警播放声音", "ja": "クリティカルアラート時にサウンドを再生", "ko": "긴급 알림 시 소리 재생", "id": "Putar suara untuk peringatan kritis", "ms": "Mainkan bunyi untuk amaran kritikal"],
        "escalation_repeat_alert": ["en": "Repeat unacknowledged alerts", "th": "แจ้งซ้ำสำหรับแจ้งเตือนที่ยังไม่รับทราบ", "zh": "重复未确认的告警", "ja": "未確認アラートを繰り返す", "ko": "미확인 알림 반복", "id": "Ulangi peringatan yang belum diakui", "ms": "Ulangi amaran yang belum diakui"],
        "escalation_how_it_works": ["en": "How Escalation Works", "th": "การยกระดับทำงานอย่างไร", "zh": "升级如何运作", "ja": "エスカレーションの仕組み", "ko": "에스컬레이션 작동 방식", "id": "Cara Kerja Eskalasi", "ms": "Cara Eskalasi Berfungsi"],
        "escalation_explanation": ["en": "When a critical alert is not acknowledged within the timeout, it will repeat with sound. High-priority alerts escalate to critical after their timeout.", "th": "เมื่อแจ้งเตือนวิกฤตไม่ได้รับการรับทราบภายในเวลาที่กำหนด จะแจ้งซ้ำพร้อมเสียง แจ้งเตือนสำคัญจะยกระดับเป็นวิกฤตหลังหมดเวลา", "zh": "当严重告警在超时时间内未被确认时，将伴随声音重复。高优先级告警在超时后升级为严重级别。", "ja": "タイムアウト内にクリティカルアラートが確認されない場合、サウンドとともに繰り返されます。高優先度アラートはタイムアウト後にクリティカルにエスカレートされます。", "ko": "긴급 알림이 시간 내에 확인되지 않으면 소리와 함께 반복됩니다. 높은 우선순위 알림은 시간 초과 후 긴급으로 에스컬레이션됩니다.", "id": "Ketika peringatan kritis tidak diakui dalam batas waktu, akan diulang dengan suara. Peringatan prioritas tinggi meningkat menjadi kritis setelah batas waktu.", "ms": "Apabila amaran kritikal tidak diakui dalam tempoh masa, ia akan diulang dengan bunyi. Amaran keutamaan tinggi meningkat kepada kritikal selepas tempoh masa."],
        // MARK: - System Alert Triggers
        "alert_sync_failed_title": ["en": "Sync Failed", "th": "ซิงค์ล้มเหลว", "zh": "同步失败", "ja": "同期に失敗", "ko": "동기화 실패", "id": "Sinkronisasi Gagal", "ms": "Penyegerakan Gagal"],
        "alert_sync_failed_msg": ["en": "Unable to sync with server", "th": "ไม่สามารถซิงค์กับเซิร์ฟเวอร์", "zh": "无法与服务器同步", "ja": "サーバーと同期できません", "ko": "서버와 동기화할 수 없습니다", "id": "Tidak dapat menyinkronkan dengan server", "ms": "Tidak dapat menyegerakkan dengan pelayan"],
        "alert_connection_restored_title": ["en": "Connection Restored", "th": "เชื่อมต่อกลับแล้ว", "zh": "连接已恢复", "ja": "接続が復元されました", "ko": "연결 복원됨", "id": "Koneksi Dipulihkan", "ms": "Sambungan Dipulihkan"],
        "alert_connection_restored_msg": ["en": "Real-time sync is back online", "th": "ระบบซิงค์เรียลไทม์กลับมาทำงานแล้ว", "zh": "实时同步已恢复在线", "ja": "リアルタイム同期がオンラインに復帰しました", "ko": "실시간 동기화가 다시 온라인 상태입니다", "id": "Sinkronisasi real-time kembali online", "ms": "Penyegerakan masa nyata kembali dalam talian"],
        "alert_offline_title": ["en": "Offline Mode Active", "th": "โหมดออฟไลน์เปิดใช้งาน", "zh": "离线模式已激活", "ja": "オフラインモードがアクティブ", "ko": "오프라인 모드 활성", "id": "Mode Offline Aktif", "ms": "Mod Luar Talian Aktif"],
        "alert_offline_msg": ["en": "Data will sync when connection is restored", "th": "ข้อมูลจะซิงค์เมื่อเชื่อมต่อกลับ", "zh": "数据将在连接恢复后同步", "ja": "接続が復元されるとデータが同期されます", "ko": "연결이 복원되면 데이터가 동기화됩니다", "id": "Data akan disinkronkan saat koneksi dipulihkan", "ms": "Data akan disegerakkan apabila sambungan dipulihkan"],
        "alert_new_order_title": ["en": "New Order", "th": "ออเดอร์ใหม่", "zh": "新订单", "ja": "新しい注文", "ko": "새 주문", "id": "Pesanan Baru", "ms": "Pesanan Baharu"],
        "alert_items_suffix": ["en": "items", "th": "รายการ", "zh": "项", "ja": "品", "ko": "개", "id": "item", "ms": "item"],
        "alert_order_delayed_title": ["en": "Order Delayed", "th": "ออเดอร์ล่าช้า", "zh": "订单延迟", "ja": "注文遅延", "ko": "주문 지연", "id": "Pesanan Tertunda", "ms": "Pesanan Tertangguh"],
        "alert_min_waiting": ["en": "min waiting", "th": "นาทีที่รอ", "zh": "分钟等待", "ja": "分待機中", "ko": "분 대기 중", "id": "menit menunggu", "ms": "minit menunggu"],
        "alert_order_cancelled_title": ["en": "Order Cancelled", "th": "ยกเลิกออเดอร์", "zh": "订单已取消", "ja": "注文キャンセル", "ko": "주문 취소됨", "id": "Pesanan Dibatalkan", "ms": "Pesanan Dibatalkan"],
        "alert_order_cancelled_msg": ["en": "Order has been cancelled", "th": "ออเดอร์ถูกยกเลิก", "zh": "订单已被取消", "ja": "注文がキャンセルされました", "ko": "주문이 취소되었습니다", "id": "Pesanan telah dibatalkan", "ms": "Pesanan telah dibatalkan"],
        "alert_payment_failed_title": ["en": "Payment Failed", "th": "ชำระเงินล้มเหลว", "zh": "支付失败", "ja": "決済に失敗", "ko": "결제 실패", "id": "Pembayaran Gagal", "ms": "Pembayaran Gagal"],
        "alert_large_refund_title": ["en": "Large Refund Processed", "th": "มีการคืนเงินจำนวนมาก", "zh": "大额退款已处理", "ja": "高額返金が処理されました", "ko": "대규모 환불 처리됨", "id": "Refund Besar Diproses", "ms": "Bayaran Balik Besar Diproses"],
        "alert_staff_clock_in_title": ["en": "Staff Clock In", "th": "พนักงานเข้างาน", "zh": "员工打卡上班", "ja": "スタッフ出勤", "ko": "직원 출근", "id": "Staf Masuk", "ms": "Staf Masuk"],
        "alert_staff_clock_in_msg": ["en": "clocked in", "th": "เข้างานแล้ว", "zh": "已打卡", "ja": "出勤しました", "ko": "출근함", "id": "telah masuk", "ms": "telah masuk"],
        "alert_staff_clock_out_title": ["en": "Staff Clock Out", "th": "พนักงานออกงาน", "zh": "员工打卡下班", "ja": "スタッフ退勤", "ko": "직원 퇴근", "id": "Staf Keluar", "ms": "Staf Keluar"],
        "alert_hours_worked": ["en": "hours worked", "th": "ชั่วโมงทำงาน", "zh": "工作小时", "ja": "時間勤務", "ko": "시간 근무", "id": "jam kerja", "ms": "jam bekerja"],
        "alert_staff_locked_title": ["en": "Staff Session Locked", "th": "เซสชันพนักงานถูกล็อก", "zh": "员工会话已锁定", "ja": "スタッフセッションがロックされました", "ko": "직원 세션 잠김", "id": "Sesi Staf Terkunci", "ms": "Sesi Staf Dikunci"],
        "alert_low_stock_title": ["en": "Low Stock Alert", "th": "แจ้งเตือนสต็อกต่ำ", "zh": "库存不足提醒", "ja": "在庫不足アラート", "ko": "재고 부족 알림", "id": "Peringatan Stok Rendah", "ms": "Amaran Stok Rendah"],
        "alert_low_stock_suffix": ["en": "units remaining", "th": "หน่วยคงเหลือ", "zh": "单位剩余", "ja": "ユニット残り", "ko": "단위 남음", "id": "unit tersisa", "ms": "unit berbaki"],
        "alert_device_offline_title": ["en": "Device Offline", "th": "อุปกรณ์ออฟไลน์", "zh": "设备离线", "ja": "デバイスがオフライン", "ko": "장치 오프라인", "id": "Perangkat Offline", "ms": "Peranti Luar Talian"],
        "alert_last_seen": ["en": "last seen", "th": "เห็นล่าสุด", "zh": "最后在线", "ja": "最終確認", "ko": "마지막 확인", "id": "terakhir terlihat", "ms": "kali terakhir dilihat"],
        "alert_device_reconnected_title": ["en": "Device Reconnected", "th": "อุปกรณ์เชื่อมต่อกลับ", "zh": "设备已重新连接", "ja": "デバイスが再接続されました", "ko": "장치 다시 연결됨", "id": "Perangkat Terhubung Kembali", "ms": "Peranti Disambung Semula"],
        "alert_device_reconnected_msg": ["en": "is back online", "th": "กลับมาออนไลน์แล้ว", "zh": "已恢复在线", "ja": "がオンラインに復帰", "ko": "다시 온라인 상태입니다", "id": "kembali online", "ms": "kembali dalam talian"],
        "alert_order_ready_title": ["en": "Order Ready", "th": "ออเดอร์พร้อมเสิร์ฟ", "zh": "订单已准备好", "ja": "注文準備完了", "ko": "주문 준비 완료", "id": "Pesanan Siap", "ms": "Pesanan Sedia"],
        "alert_order_ready_msg": ["en": "Ready to serve", "th": "พร้อมเสิร์ฟ", "zh": "可以上菜", "ja": "提供可能", "ko": "서빙 준비 완료", "id": "Siap disajikan", "ms": "Sedia untuk dihidang"],
        "alert_customer_call_title": ["en": "Customer Calling Staff", "th": "ลูกค้าเรียกพนักงาน", "zh": "顾客呼叫服务员", "ja": "お客様がスタッフを呼んでいます", "ko": "고객이 직원을 호출 중", "id": "Pelanggan Memanggil Staf", "ms": "Pelanggan Memanggil Staf"],
        "alert_feedback_title": ["en": "Customer Feedback", "th": "ลูกค้าให้คะแนน", "zh": "顾客反馈", "ja": "お客様フィードバック", "ko": "고객 피드백", "id": "Umpan Balik Pelanggan", "ms": "Maklum Balas Pelanggan"],
        "crm_purchase_history": ["en": "Purchase History", "th": "ประวัติการซื้อ", "zh": "购买记录", "ja": "購入履歴", "ko": "구매 내역", "id": "Riwayat Pembelian", "ms": "Sejarah Pembelian"],
        "crm_purchase_history_empty": ["en": "Recent orders will appear here", "th": "ออเดอร์ล่าสุดจะแสดงที่นี่", "zh": "最近的订单将显示在此", "ja": "最近の注文がここに表示されます", "ko": "최근 주문이 여기에 표시됩니다", "id": "Pesanan terbaru akan muncul di sini", "ms": "Pesanan terkini akan dipapar di sini"],
        "device_pair_title": ["en": "Pair New Device", "th": "จับคู่อุปกรณ์ใหม่", "zh": "配对新设备", "ja": "新しいデバイスをペアリング", "ko": "새 장치 페어링", "id": "Pasangkan Perangkat Baru", "ms": "Gandingkan Peranti Baharu"],
        "device_pair_desc": ["en": "Scan the QR code on the new device or enter the pairing code manually.", "th": "สแกน QR code บนอุปกรณ์ใหม่ หรือป้อนรหัสจับคู่ด้วยตนเอง", "zh": "扫描新设备上的二维码或手动输入配对码", "ja": "新しいデバイスのQRコードをスキャンするか、ペアリングコードを手動で入力", "ko": "새 장치의 QR 코드를 스캔하거나 페어링 코드를 수동으로 입력", "id": "Pindai kode QR pada perangkat baru atau masukkan kode pairing secara manual.", "ms": "Imbas kod QR pada peranti baharu atau masukkan kod gandingan secara manual."],
        // MARK: - Payment Gateway
        "payments_nav": ["en": "Payments", "th": "ชำระเงิน", "zh": "支付", "ja": "決済", "ko": "결제", "id": "Pembayaran", "ms": "Pembayaran"],
        "payment_gateway_title": ["en": "Payment Gateway", "th": "ช่องทางชำระเงิน", "zh": "支付网关", "ja": "決済ゲートウェイ", "ko": "결제 게이트웨이", "id": "Gateway Pembayaran", "ms": "Gerbang Pembayaran"],
        "payment_test_mode": ["en": "Test Mode", "th": "โหมดทดสอบ", "zh": "测试模式", "ja": "テストモード", "ko": "테스트 모드", "id": "Mode Uji", "ms": "Mod Ujian"],
        "payment_live_mode": ["en": "Live Mode", "th": "โหมดใช้งานจริง", "zh": "正式模式", "ja": "本番モード", "ko": "라이브 모드", "id": "Mode Live", "ms": "Mod Langsung"],
        "payment_today_stats": ["en": "Today's Payments", "th": "การชำระวันนี้", "zh": "今日收款", "ja": "本日の決済", "ko": "오늘 결제", "id": "Pembayaran Hari Ini", "ms": "Pembayaran Hari Ini"],
        "payment_txns": ["en": "txns", "th": "รายการ", "zh": "笔", "ja": "件", "ko": "건", "id": "transaksi", "ms": "transaksi"],
        "payment_volume": ["en": "volume", "th": "ยอดรวม", "zh": "金额", "ja": "売上高", "ko": "거래액", "id": "volume", "ms": "jumlah"],
        "payment_methods_title": ["en": "Payment Methods", "th": "ช่องทางชำระเงิน", "zh": "支付方式", "ja": "決済方法", "ko": "결제 방법", "id": "Metode Pembayaran", "ms": "Kaedah Pembayaran"],
        "payment_methods_desc": ["en": "Enable, disable, and reorder payment methods for this branch.", "th": "เปิด/ปิด และจัดลำดับช่องทางชำระเงินสำหรับสาขานี้", "zh": "启用、禁用和重新排序此门店的支付方式", "ja": "この店舗の決済方法を有効化・無効化・並べ替え", "ko": "이 지점의 결제 방법을 활성화, 비활성화 및 재정렬", "id": "Aktifkan, nonaktifkan, dan urutkan metode pembayaran untuk cabang ini.", "ms": "Aktifkan, nyahaktif, dan susun semula kaedah pembayaran untuk cawangan ini."],
        "payment_gateways_title": ["en": "Payment Gateways", "th": "เกตเวย์ชำระเงิน", "zh": "支付网关", "ja": "決済ゲートウェイ", "ko": "결제 게이트웨이", "id": "Gateway Pembayaran", "ms": "Gerbang Pembayaran"],
        "payment_gateways_desc": ["en": "Connect third-party payment processors.", "th": "เชื่อมต่อผู้ให้บริการรับชำระเงินภายนอก", "zh": "连接第三方支付处理商", "ja": "サードパーティの決済プロセッサーを接続", "ko": "서드파티 결제 프로세서 연결", "id": "Hubungkan prosesor pembayaran pihak ketiga.", "ms": "Sambung pemproses pembayaran pihak ketiga."],
        "payment_add_gateway": ["en": "Add Gateway", "th": "เพิ่มเกตเวย์", "zh": "添加网关", "ja": "ゲートウェイを追加", "ko": "게이트웨이 추가", "id": "Tambah Gateway", "ms": "Tambah Gerbang"],
        "payment_connected": ["en": "Connected", "th": "เชื่อมต่อแล้ว", "zh": "已连接", "ja": "接続済み", "ko": "연결됨", "id": "Terhubung", "ms": "Disambung"],
        "payment_not_connected": ["en": "Not connected", "th": "ยังไม่เชื่อมต่อ", "zh": "未连接", "ja": "未接続", "ko": "연결 안됨", "id": "Belum terhubung", "ms": "Belum disambung"],
        "payment_transactions_title": ["en": "Transactions", "th": "รายการธุรกรรม", "zh": "交易记录", "ja": "トランザクション", "ko": "거래 내역", "id": "Transaksi", "ms": "Transaksi"],
        "payment_completed": ["en": "Completed", "th": "สำเร็จ", "zh": "已完成", "ja": "完了", "ko": "완료", "id": "Selesai", "ms": "Selesai"],
        "payment_failed": ["en": "Failed", "th": "ล้มเหลว", "zh": "失败", "ja": "失敗", "ko": "실패", "id": "Gagal", "ms": "Gagal"],
        "payment_refunded": ["en": "Refunded", "th": "คืนเงิน", "zh": "已退款", "ja": "返金済み", "ko": "환불됨", "id": "Dikembalikan", "ms": "Dipulangkan"],
        "payment_no_transactions": ["en": "No transactions yet", "th": "ยังไม่มีรายการธุรกรรม", "zh": "暂无交易记录", "ja": "まだトランザクションがありません", "ko": "아직 거래 내역이 없습니다", "id": "Belum ada transaksi", "ms": "Belum ada transaksi"],
        "payment_settings_title": ["en": "Payment Settings", "th": "ตั้งค่าการชำระเงิน", "zh": "支付设置", "ja": "決済設定", "ko": "결제 설정", "id": "Pengaturan Pembayaran", "ms": "Tetapan Pembayaran"],
        "payment_test_mode_title": ["en": "Test Mode", "th": "โหมดทดสอบ", "zh": "测试模式", "ja": "テストモード", "ko": "테스트 모드", "id": "Mode Uji", "ms": "Mod Ujian"],
        "payment_test_mode_desc": ["en": "Process payments in sandbox without real charges.", "th": "ทดสอบการชำระเงินโดยไม่มีค่าใช้จ่ายจริง", "zh": "在沙箱中处理支付，不产生真实费用", "ja": "サンドボックスで実際の課金なしに決済を処理", "ko": "실제 청구 없이 샌드박스에서 결제 처리", "id": "Proses pembayaran di sandbox tanpa biaya nyata.", "ms": "Proses pembayaran dalam sandbox tanpa caj sebenar."],
        "payment_test_mode_gateway_desc": ["en": "Use test API keys — no real money is processed.", "th": "ใช้คีย์ทดสอบ — ไม่มีเงินจริงถูกดำเนินการ", "zh": "使用测试API密钥 — 不会处理真实资金", "ja": "テストAPIキーを使用 — 実際の入金は処理されません", "ko": "테스트 API 키 사용 — 실제 금액은 처리되지 않음", "id": "Gunakan kunci API uji — tidak ada uang nyata yang diproses.", "ms": "Gunakan kunci API ujian — tiada wang sebenar diproses."],
        "payment_auto_reconcile_title": ["en": "Auto-Reconciliation", "th": "ตรวจสอบยอดอัตโนมัติ", "zh": "自动对账", "ja": "自動照合", "ko": "자동 대사", "id": "Rekonsiliasi Otomatis", "ms": "Penyesuaian Automatik"],
        "payment_auto_reconcile_desc": ["en": "Automatically match gateway settlements with POS orders.", "th": "จับคู่ยอดจากเกตเวย์กับออเดอร์ POS โดยอัตโนมัติ", "zh": "自动将网关结算与POS订单匹配", "ja": "ゲートウェイの精算をPOS注文と自動照合", "ko": "게이트웨이 정산을 POS 주문과 자동 매칭", "id": "Otomatis mencocokkan penyelesaian gateway dengan pesanan POS.", "ms": "Secara automatik memadankan penyelesaian gerbang dengan pesanan POS."],
        "payment_auto_receipt_title": ["en": "Auto-Print Receipt", "th": "พิมพ์ใบเสร็จอัตโนมัติ", "zh": "自动打印收据", "ja": "レシート自動印刷", "ko": "영수증 자동 출력", "id": "Cetak Struk Otomatis", "ms": "Cetak Resit Automatik"],
        "payment_auto_receipt_desc": ["en": "Print receipt automatically after payment completion.", "th": "พิมพ์ใบเสร็จอัตโนมัติหลังชำระเงินเสร็จ", "zh": "付款完成后自动打印收据", "ja": "決済完了後にレシートを自動印刷", "ko": "결제 완료 후 영수증 자동 출력", "id": "Cetak struk secara otomatis setelah pembayaran selesai.", "ms": "Cetak resit secara automatik selepas pembayaran selesai."],
        "payment_tipping_title": ["en": "Enable Tipping", "th": "เปิดระบบทิป", "zh": "启用小费", "ja": "チップを有効化", "ko": "팁 활성화", "id": "Aktifkan Tip", "ms": "Aktifkan Tip"],
        "payment_tipping_desc": ["en": "Show tip options on customer-facing payment screen.", "th": "แสดงตัวเลือกทิปบนหน้าจอชำระเงินของลูกค้า", "zh": "在面向客户的支付界面显示小费选项", "ja": "顧客向け決済画面にチップオプションを表示", "ko": "고객 대면 결제 화면에 팁 옵션 표시", "id": "Tampilkan opsi tip di layar pembayaran pelanggan.", "ms": "Papar pilihan tip di skrin pembayaran pelanggan."],
        "payment_multi_currency_title": ["en": "Multi-Currency", "th": "หลายสกุลเงิน", "zh": "多币种", "ja": "マルチ通貨", "ko": "다중 통화", "id": "Multi-Mata Uang", "ms": "Pelbagai Mata Wang"],
        "payment_multi_currency_desc": ["en": "Accept payments in multiple currencies with auto-conversion.", "th": "รับชำระเงินหลายสกุลเงินพร้อมแปลงค่าอัตโนมัติ", "zh": "接受多币种支付并自动换算", "ja": "複数通貨での支払いを自動換算で受け付け", "ko": "자동 변환으로 다중 통화 결제 수락", "id": "Terima pembayaran dalam berbagai mata uang dengan konversi otomatis.", "ms": "Terima pembayaran dalam pelbagai mata wang dengan penukaran automatik."],
        "payment_fee": ["en": "Fee", "th": "ค่าธรรมเนียม", "zh": "费率", "ja": "手数料", "ko": "수수료", "id": "Biaya", "ms": "Yuran"],
        "payment_credentials": ["en": "API Credentials", "th": "ข้อมูลรับรอง API", "zh": "API凭证", "ja": "API認証情報", "ko": "API 자격 증명", "id": "Kredensial API", "ms": "Kelayakan API"],
        "payment_connect_gateway": ["en": "Connect Gateway", "th": "เชื่อมต่อเกตเวย์", "zh": "连接网关", "ja": "ゲートウェイを接続", "ko": "게이트웨이 연결", "id": "Hubungkan Gateway", "ms": "Sambung Gerbang"],
        "payment_choose_gateway": ["en": "Choose a payment gateway to connect.", "th": "เลือกเกตเวย์ชำระเงินเพื่อเชื่อมต่อ", "zh": "选择要连接的支付网关", "ja": "接続する決済ゲートウェイを選択", "ko": "연결할 결제 게이트웨이를 선택하세요", "id": "Pilih gateway pembayaran untuk dihubungkan.", "ms": "Pilih gerbang pembayaran untuk disambung."],
        "payment_cash_desc": ["en": "Accept physical cash payments", "th": "รับชำระเงินสดจริง", "zh": "接受现金支付", "ja": "現金支払いを受付", "ko": "현금 결제 수락", "id": "Terima pembayaran tunai", "ms": "Terima pembayaran tunai"],
        "payment_card_desc": ["en": "Via connected gateway (Omise/2C2P/Stripe)", "th": "ผ่านเกตเวย์ที่เชื่อมต่อ (Omise/2C2P/Stripe)", "zh": "通过已连接网关 (Omise/2C2P/Stripe)", "ja": "接続済みゲートウェイ経由 (Omise/2C2P/Stripe)", "ko": "연결된 게이트웨이를 통해 (Omise/2C2P/Stripe)", "id": "Melalui gateway yang terhubung (Omise/2C2P/Stripe)", "ms": "Melalui gerbang yang disambung (Omise/2C2P/Stripe)"],
        "payment_promptpay_desc": ["en": "Thai national QR payment standard", "th": "มาตรฐาน QR ชำระเงินแห่งชาติ", "zh": "泰国国家QR支付标准", "ja": "タイ国家QR決済規格", "ko": "태국 국가 QR 결제 표준", "id": "Standar pembayaran QR nasional Thailand", "ms": "Standard pembayaran QR kebangsaan Thailand"],
        "payment_truemoney_desc": ["en": "TrueMoney digital wallet", "th": "กระเป๋าเงินดิจิทัล TrueMoney", "zh": "TrueMoney电子钱包", "ja": "TrueMoneyデジタルウォレット", "ko": "TrueMoney 디지털 지갑", "id": "Dompet digital TrueMoney", "ms": "Dompet digital TrueMoney"],
        "payment_linepay_desc": ["en": "LINE messaging app payments", "th": "ชำระเงินผ่านแอป LINE", "zh": "LINE消息应用支付", "ja": "LINEアプリ決済", "ko": "LINE 메시징 앱 결제", "id": "Pembayaran aplikasi perpesanan LINE", "ms": "Pembayaran aplikasi pemesejan LINE"],
        "payment_grabpay_desc": ["en": "Grab super-app wallet", "th": "กระเป๋าเงิน Grab", "zh": "Grab超级应用钱包", "ja": "Grabスーパーアプリウォレット", "ko": "Grab 슈퍼앱 지갑", "id": "Dompet super-app Grab", "ms": "Dompet super-app Grab"],
        "close": ["en": "Close", "th": "ปิด", "zh": "关闭", "ja": "閉じる", "ko": "닫기", "id": "Tutup", "ms": "Tutup"],
        // MARK: - Granular RBAC Permissions
        "perm_pos_sell": ["en": "Sell & Take Orders", "th": "ขายและรับออเดอร์", "zh": "销售和接单", "ja": "販売と注文受付", "ko": "판매 및 주문 접수", "id": "Jual & Terima Pesanan", "ms": "Jual & Terima Pesanan"],
        "perm_pos_sell_desc": ["en": "Process sales and take customer orders", "th": "ดำเนินการขายและรับออเดอร์ลูกค้า", "zh": "处理销售和接受客户订单", "ja": "売上処理と顧客注文の受付", "ko": "판매 처리 및 고객 주문 접수", "id": "Proses penjualan dan terima pesanan pelanggan", "ms": "Proses jualan dan terima pesanan pelanggan"],
        "perm_order_void": ["en": "Void Orders", "th": "ยกเลิกออเดอร์", "zh": "作废订单", "ja": "注文無効", "ko": "주문 무효화", "id": "Batalkan Pesanan", "ms": "Batalkan Pesanan"],
        "perm_order_void_desc": ["en": "Cancel and void existing orders", "th": "ยกเลิกและ void ออเดอร์ที่มีอยู่", "zh": "取消和作废现有订单", "ja": "既存の注文をキャンセル・無効化", "ko": "기존 주문 취소 및 무효화", "id": "Batalkan dan void pesanan yang ada", "ms": "Batal dan void pesanan yang ada"],
        "perm_refund_create": ["en": "Create Refunds", "th": "คืนเงิน", "zh": "创建退款", "ja": "返金作成", "ko": "환불 생성", "id": "Buat Refund", "ms": "Buat Bayaran Balik"],
        "perm_refund_create_desc": ["en": "Process refunds and returns", "th": "ดำเนินการคืนเงินและรับคืนสินค้า", "zh": "处理退款和退货", "ja": "返金と返品の処理", "ko": "환불 및 반품 처리", "id": "Proses refund dan pengembalian", "ms": "Proses bayaran balik dan pemulangan"],
        "perm_discount_apply": ["en": "Apply Discounts", "th": "ใช้ส่วนลด", "zh": "应用折扣", "ja": "割引適用", "ko": "할인 적용", "id": "Terapkan Diskon", "ms": "Gunakan Diskaun"],
        "perm_discount_apply_desc": ["en": "Apply discounts and promotions to orders", "th": "ใช้ส่วนลดและโปรโมชั่นกับออเดอร์", "zh": "对订单应用折扣和促销", "ja": "注文に割引とプロモーションを適用", "ko": "주문에 할인 및 프로모션 적용", "id": "Terapkan diskon dan promosi ke pesanan", "ms": "Gunakan diskaun dan promosi kepada pesanan"],
        "perm_tables_manage": ["en": "Manage Tables", "th": "จัดการโต๊ะ", "zh": "管理桌台", "ja": "テーブル管理", "ko": "테이블 관리", "id": "Kelola Meja", "ms": "Urus Meja"],
        "perm_tables_manage_desc": ["en": "Create, edit, and manage table sessions", "th": "สร้าง แก้ไข และจัดการเซสชันโต๊ะ", "zh": "创建、编辑和管理桌台会话", "ja": "テーブルセッションの作成・編集・管理", "ko": "테이블 세션 생성, 편집 및 관리", "id": "Buat, edit, dan kelola sesi meja", "ms": "Cipta, edit, dan urus sesi meja"],
        "perm_kitchen_view": ["en": "View Kitchen Display", "th": "ดูจอครัว", "zh": "查看厨房显示", "ja": "キッチンディスプレイ表示", "ko": "주방 디스플레이 보기", "id": "Lihat Tampilan Dapur", "ms": "Lihat Paparan Dapur"],
        "perm_kitchen_view_desc": ["en": "View orders in kitchen display system", "th": "ดูออเดอร์ในระบบจอครัว", "zh": "在厨房显示系统中查看订单", "ja": "キッチンディスプレイで注文を表示", "ko": "주방 디스플레이에서 주문 보기", "id": "Lihat pesanan di sistem tampilan dapur", "ms": "Lihat pesanan dalam sistem paparan dapur"],
        "perm_inventory_view": ["en": "View Inventory", "th": "ดูสต็อก", "zh": "查看库存", "ja": "在庫表示", "ko": "재고 보기", "id": "Lihat Inventaris", "ms": "Lihat Inventori"],
        "perm_inventory_view_desc": ["en": "View menu items and stock levels", "th": "ดูเมนูและระดับสต็อก", "zh": "查看菜单和库存水平", "ja": "メニューと在庫レベルを表示", "ko": "메뉴 항목 및 재고 수준 보기", "id": "Lihat item menu dan level stok", "ms": "Lihat item menu dan paras stok"],
        "perm_inventory_manage": ["en": "Manage Inventory", "th": "จัดการสต็อก", "zh": "管理库存", "ja": "在庫管理", "ko": "재고 관리", "id": "Kelola Inventaris", "ms": "Urus Inventori"],
        "perm_inventory_manage_desc": ["en": "Edit menu items, manage stock, recipes", "th": "แก้ไขเมนู จัดการสต็อก สูตรอาหาร", "zh": "编辑菜单、管理库存、食谱", "ja": "メニュー編集、在庫・レシピ管理", "ko": "메뉴 편집, 재고 및 레시피 관리", "id": "Edit item menu, kelola stok, resep", "ms": "Edit item menu, urus stok, resipi"],
        "perm_cash_drawer_open": ["en": "Open Cash Drawer", "th": "เปิดลิ้นชักเงิน", "zh": "打开钱箱", "ja": "キャッシュドロワーを開く", "ko": "금전함 열기", "id": "Buka Laci Kas", "ms": "Buka Laci Tunai"],
        "perm_cash_drawer_open_desc": ["en": "Open cash drawer for making change", "th": "เปิดลิ้นชักเงินสดเพื่อทอนเงิน", "zh": "打开钱箱找零", "ja": "お釣り用にキャッシュドロワーを開く", "ko": "거스름돈을 위해 금전함 열기", "id": "Buka laci kas untuk memberi kembalian", "ms": "Buka laci tunai untuk memberi baki"],
        "perm_cash_drawer_manage": ["en": "Manage Cash Drawer", "th": "จัดการลิ้นชักเงิน", "zh": "管理钱箱", "ja": "キャッシュドロワー管理", "ko": "금전함 관리", "id": "Kelola Laci Kas", "ms": "Urus Laci Tunai"],
        "perm_cash_drawer_manage_desc": ["en": "Full cash drawer management: open/close shifts, cash in/out", "th": "จัดการลิ้นชักเงินเต็มรูปแบบ: เปิด/ปิดกะ เงินเข้า/ออก", "zh": "完整钱箱管理：开关班、现金出入", "ja": "キャッシュドロワーの完全管理：シフト開閉、入出金", "ko": "금전함 전체 관리: 교대 시작/종료, 입출금", "id": "Kelola penuh laci kas: buka/tutup shift, kas masuk/keluar", "ms": "Urus penuh laci tunai: buka/tutup syif, tunai masuk/keluar"],
        "perm_payments_manage": ["en": "Manage Payments", "th": "จัดการชำระเงิน", "zh": "管理支付", "ja": "決済管理", "ko": "결제 관리", "id": "Kelola Pembayaran", "ms": "Urus Pembayaran"],
        "perm_payments_manage_desc": ["en": "Configure payment gateways and methods", "th": "กำหนดค่าเกตเวย์และช่องทางชำระเงิน", "zh": "配置支付网关和方式", "ja": "決済ゲートウェイと方法を設定", "ko": "결제 게이트웨이 및 방법 구성", "id": "Konfigurasi gateway dan metode pembayaran", "ms": "Konfigurasi gerbang dan kaedah pembayaran"],
        "perm_customers_view": ["en": "View Customers", "th": "ดูข้อมูลลูกค้า", "zh": "查看客户", "ja": "顧客表示", "ko": "고객 보기", "id": "Lihat Pelanggan", "ms": "Lihat Pelanggan"],
        "perm_customers_view_desc": ["en": "View customer database and profiles", "th": "ดูฐานข้อมูลและโปรไฟล์ลูกค้า", "zh": "查看客户数据库和档案", "ja": "顧客データベースとプロファイルを表示", "ko": "고객 데이터베이스 및 프로필 보기", "id": "Lihat database dan profil pelanggan", "ms": "Lihat pangkalan data dan profil pelanggan"],
        "perm_customers_manage": ["en": "Manage Customers", "th": "จัดการลูกค้า", "zh": "管理客户", "ja": "顧客管理", "ko": "고객 관리", "id": "Kelola Pelanggan", "ms": "Urus Pelanggan"],
        "perm_customers_manage_desc": ["en": "Edit customer data, segments, and communications", "th": "แก้ไขข้อมูลลูกค้า กลุ่ม และการสื่อสาร", "zh": "编辑客户数据、分组和通信", "ja": "顧客データ、セグメント、コミュニケーションを編集", "ko": "고객 데이터, 세그먼트 및 커뮤니케이션 편집", "id": "Edit data pelanggan, segmen, dan komunikasi", "ms": "Edit data pelanggan, segmen, dan komunikasi"],
        "perm_payroll_manage": ["en": "Manage Payroll", "th": "จัดการเงินเดือน", "zh": "管理工资", "ja": "給与管理", "ko": "급여 관리", "id": "Kelola Penggajian", "ms": "Urus Gaji"],
        "perm_payroll_manage_desc": ["en": "View and manage payroll, shifts, and scheduling", "th": "ดูและจัดการเงินเดือน กะ และตารางงาน", "zh": "查看和管理工资、班次和排班", "ja": "給与、シフト、スケジュールの表示と管理", "ko": "급여, 교대 및 일정 보기 및 관리", "id": "Lihat dan kelola penggajian, shift, dan penjadwalan", "ms": "Lihat dan urus gaji, syif, dan penjadualan"],
        "perm_staff_manage": ["en": "Manage Staff", "th": "จัดการพนักงาน", "zh": "管理员工", "ja": "スタッフ管理", "ko": "직원 관리", "id": "Kelola Staf", "ms": "Urus Staf"],
        "perm_staff_manage_desc": ["en": "Create/edit staff accounts, assign roles", "th": "สร้าง/แก้ไขบัญชีพนักงาน กำหนดบทบาท", "zh": "创建/编辑员工账号、分配角色", "ja": "スタッフアカウントの作成・編集、役割の割り当て", "ko": "직원 계정 생성/편집, 역할 할당", "id": "Buat/edit akun staf, tetapkan peran", "ms": "Cipta/edit akaun staf, tetapkan peranan"],
        "perm_reports_view": ["en": "View Reports", "th": "ดูรายงาน", "zh": "查看报表", "ja": "レポート表示", "ko": "보고서 보기", "id": "Lihat Laporan", "ms": "Lihat Laporan"],
        "perm_reports_view_desc": ["en": "View sales, tax, and analytics reports", "th": "ดูรายงานยอดขาย ภาษี และวิเคราะห์", "zh": "查看销售、税务和分析报表", "ja": "売上、税務、分析レポートを表示", "ko": "매출, 세금 및 분석 보고서 보기", "id": "Lihat laporan penjualan, pajak, dan analitik", "ms": "Lihat laporan jualan, cukai, dan analitik"],
        "perm_dashboard_view": ["en": "View Dashboard", "th": "ดูแดชบอร์ด", "zh": "查看仪表盘", "ja": "ダッシュボード表示", "ko": "대시보드 보기", "id": "Lihat Dasbor", "ms": "Lihat Papan Pemuka"],
        "perm_dashboard_view_desc": ["en": "View live KPI dashboard with real-time metrics", "th": "ดูแดชบอร์ด KPI แบบเรียลไทม์", "zh": "查看实时KPI仪表盘", "ja": "リアルタイムKPIダッシュボードを表示", "ko": "실시간 KPI 대시보드 보기", "id": "Lihat dasbor KPI real-time", "ms": "Lihat papan pemuka KPI masa nyata"],
        "perm_devices_view": ["en": "View Devices", "th": "ดูอุปกรณ์", "zh": "查看设备", "ja": "デバイス表示", "ko": "장치 보기", "id": "Lihat Perangkat", "ms": "Lihat Peranti"],
        "perm_devices_view_desc": ["en": "View connected device status and health", "th": "ดูสถานะและสุขภาพอุปกรณ์ที่เชื่อมต่อ", "zh": "查看已连接设备状态和健康度", "ja": "接続デバイスのステータスと健全性を表示", "ko": "연결된 장치 상태 및 건강 보기", "id": "Lihat status dan kesehatan perangkat yang terhubung", "ms": "Lihat status dan kesihatan peranti yang disambung"],
        "perm_device_manage": ["en": "Manage Devices", "th": "จัดการอุปกรณ์", "zh": "管理设备", "ja": "デバイス管理", "ko": "장치 관리", "id": "Kelola Perangkat", "ms": "Urus Peranti"],
        "perm_device_manage_desc": ["en": "Pair, unpair, force sync, wipe devices", "th": "จับคู่ ถอดคู่ บังคับซิงค์ ล้างอุปกรณ์", "zh": "配对、取消配对、强制同步、擦除设备", "ja": "ペアリング、解除、強制同期、デバイスワイプ", "ko": "페어링, 해제, 강제 동기화, 장치 초기화", "id": "Pasangkan, lepas, paksa sinkronisasi, hapus perangkat", "ms": "Gandingkan, lepas, paksa segerakkan, padam peranti"],
        "perm_org_view": ["en": "View Organization", "th": "ดูข้อมูลองค์กร", "zh": "查看组织", "ja": "組織表示", "ko": "조직 보기", "id": "Lihat Organisasi", "ms": "Lihat Organisasi"],
        "perm_org_view_desc": ["en": "View organization profile and subscription", "th": "ดูโปรไฟล์และแผนสมาชิกองค์กร", "zh": "查看组织简介和订阅", "ja": "組織プロフィールとサブスクリプションを表示", "ko": "조직 프로필 및 구독 보기", "id": "Lihat profil organisasi dan langganan", "ms": "Lihat profil organisasi dan langganan"],
        "perm_org_manage": ["en": "Manage Organization", "th": "จัดการองค์กร", "zh": "管理组织", "ja": "組織管理", "ko": "조직 관리", "id": "Kelola Organisasi", "ms": "Urus Organisasi"],
        "perm_org_manage_desc": ["en": "Manage billing, API keys, and org settings", "th": "จัดการการเรียกเก็บเงิน คีย์ API และตั้งค่าองค์กร", "zh": "管理账单、API密钥和组织设置", "ja": "請求、APIキー、組織設定を管理", "ko": "결제, API 키 및 조직 설정 관리", "id": "Kelola tagihan, kunci API, dan pengaturan organisasi", "ms": "Urus bil, kunci API, dan tetapan organisasi"],
        "perm_settings_manage": ["en": "Manage Settings", "th": "จัดการตั้งค่า", "zh": "管理设置", "ja": "設定管理", "ko": "설정 관리", "id": "Kelola Pengaturan", "ms": "Urus Tetapan"],
        "perm_settings_manage_desc": ["en": "Configure app settings and preferences", "th": "กำหนดค่าการตั้งค่าและค่าปรับแต่ง", "zh": "配置应用设置和偏好", "ja": "アプリの設定とプリファレンスを構成", "ko": "앱 설정 및 기본 설정 구성", "id": "Konfigurasi pengaturan dan preferensi aplikasi", "ms": "Konfigurasi tetapan dan keutamaan aplikasi"],
        "perm_manager_override": ["en": "Manager Override", "th": "สิทธิ์ผู้จัดการ", "zh": "管理员覆盖", "ja": "マネージャーオーバーライド", "ko": "관리자 오버라이드", "id": "Override Manajer", "ms": "Override Pengurus"],
        "perm_manager_override_desc": ["en": "Override PIN for restricted actions", "th": "ใช้ PIN ผู้จัดการสำหรับการดำเนินการที่จำกัด", "zh": "使用管理员PIN覆盖受限操作", "ja": "制限されたアクションのPINオーバーライド", "ko": "제한된 작업에 대한 관리자 PIN 오버라이드", "id": "Override PIN untuk tindakan terbatas", "ms": "Override PIN untuk tindakan terhad"],
        "perm_notifications_manage": ["en": "Manage Notifications", "th": "จัดการการแจ้งเตือน", "zh": "管理通知", "ja": "通知管理", "ko": "알림 관리", "id": "Kelola Notifikasi", "ms": "Urus Pemberitahuan"],
        "perm_notifications_manage_desc": ["en": "Configure notification rules and escalation", "th": "กำหนดกฎการแจ้งเตือนและการยกระดับ", "zh": "配置通知规则和升级", "ja": "通知ルールとエスカレーションを設定", "ko": "알림 규칙 및 에스컬레이션 구성", "id": "Konfigurasi aturan notifikasi dan eskalasi", "ms": "Konfigurasi peraturan pemberitahuan dan eskalasi"],
        // MARK: - Sync Conflict Resolution
        "conflict_title": ["en": "Sync & Conflicts", "th": "ซิงค์และ Conflicts", "zh": "同步与冲突", "ja": "同期と競合", "ko": "동기화 및 충돌", "id": "Sinkronisasi & Konflik", "ms": "Penyegerakan & Konflik"],
        "conflict_nav_title": ["en": "Conflict Resolution", "th": "จัดการ Conflicts", "zh": "冲突解决", "ja": "競合解決", "ko": "충돌 해결", "id": "Resolusi Konflik", "ms": "Penyelesaian Konflik"],
        "conflict_nav_desc": ["en": "View offline queue and resolve sync conflicts", "th": "ดูคิวออฟไลน์และแก้ไข sync conflicts", "zh": "查看离线队列并解决同步冲突", "ja": "オフラインキューを表示し同期の競合を解決", "ko": "오프라인 대기열 확인 및 동기화 충돌 해결", "id": "Lihat antrean offline dan selesaikan konflik sinkronisasi", "ms": "Lihat barisan luar talian dan selesaikan konflik penyegerakan"],
        "conflict_offline_mode": ["en": "Offline mode active", "th": "โหมดออฟไลน์เปิดอยู่", "zh": "离线模式已激活", "ja": "オフラインモードがアクティブ", "ko": "오프라인 모드 활성", "id": "Mode offline aktif", "ms": "Mod luar talian aktif"],
        "conflict_pending_changes": ["en": "Pending changes", "th": "มีการเปลี่ยนแปลงรอซิงค์", "zh": "待同步变更", "ja": "保留中の変更", "ko": "대기 중인 변경 사항", "id": "Perubahan tertunda", "ms": "Perubahan tertangguh"],
        "conflict_all_synced": ["en": "All synced", "th": "ซิงค์ครบแล้ว", "zh": "全部已同步", "ja": "すべて同期済み", "ko": "모두 동기화됨", "id": "Semua tersinkronisasi", "ms": "Semua disegerakkan"],
        "conflict_items_pending": ["en": "items pending", "th": "รายการรอซิงค์", "zh": "项待同步", "ja": "件保留中", "ko": "개 대기 중", "id": "item tertunda", "ms": "item tertangguh"],
        "conflict_force_sync": ["en": "Force Sync", "th": "บังคับซิงค์", "zh": "强制同步", "ja": "強制同期", "ko": "강제 동기화", "id": "Paksa Sinkronisasi", "ms": "Paksa Penyegerakan"],
        "conflict_force_sync_title": ["en": "Force Sync All?", "th": "บังคับซิงค์ทั้งหมด?", "zh": "强制同步全部？", "ja": "すべてを強制同期しますか？", "ko": "모두 강제 동기화?", "id": "Paksa Sinkronisasi Semua?", "ms": "Paksa Segerakkan Semua?"],
        "conflict_force_sync_msg": ["en": "This will push all local changes to the server immediately. Master device data takes priority.", "th": "การดำเนินการนี้จะส่งการเปลี่ยนแปลงทั้งหมดไปยังเซิร์ฟเวอร์ทันที ข้อมูลเครื่องแม่จะมีความสำคัญสูงสุด", "zh": "这将立即将所有本地更改推送到服务器。主设备数据优先。", "ja": "すべてのローカル変更を即座にサーバーにプッシュします。マスターデバイスのデータが優先されます。", "ko": "모든 로컬 변경 사항을 즉시 서버로 푸시합니다. 마스터 장치 데이터가 우선됩니다.", "id": "Ini akan mengirim semua perubahan lokal ke server segera. Data perangkat master yang diprioritaskan.", "ms": "Ini akan menghantar semua perubahan tempatan ke pelayan serta-merta. Data peranti induk diutamakan."],
        "conflict_force_sync_confirm": ["en": "Sync Now", "th": "ซิงค์เลย", "zh": "立即同步", "ja": "今すぐ同期", "ko": "지금 동기화", "id": "Sinkronkan Sekarang", "ms": "Segerakkan Sekarang"],
        "conflict_purge_title": ["en": "Discard Local Changes?", "th": "ยกเลิกการเปลี่ยนแปลงท้องถิ่น?", "zh": "丢弃本地更改？", "ja": "ローカル変更を破棄しますか？", "ko": "로컬 변경 사항을 삭제하시겠습니까?", "id": "Buang Perubahan Lokal?", "ms": "Buang Perubahan Tempatan?"],
        "conflict_purge_msg": ["en": "All unsynced local changes will be permanently discarded. Server data will be kept.", "th": "การเปลี่ยนแปลงท้องถิ่นที่ยังไม่ซิงค์ทั้งหมดจะถูกยกเลิกอย่างถาวร ข้อมูลเซิร์ฟเวอร์จะถูกเก็บไว้", "zh": "所有未同步的本地更改将被永久丢弃。服务器数据将被保留。", "ja": "未同期のローカル変更はすべて完全に破棄されます。サーバーデータは保持されます。", "ko": "동기화되지 않은 모든 로컬 변경 사항이 영구적으로 삭제됩니다. 서버 데이터가 유지됩니다.", "id": "Semua perubahan lokal yang belum disinkronkan akan dibuang secara permanen. Data server akan dipertahankan.", "ms": "Semua perubahan tempatan yang belum disegerakkan akan dibuang secara kekal. Data pelayan akan dikekalkan."],
        "conflict_purge_confirm": ["en": "Discard Changes", "th": "ยกเลิกการเปลี่ยนแปลง", "zh": "丢弃更改", "ja": "変更を破棄", "ko": "변경 사항 삭제", "id": "Buang Perubahan", "ms": "Buang Perubahan"],
        "conflict_purge_btn": ["en": "Discard all local changes", "th": "ยกเลิกการเปลี่ยนแปลงท้องถิ่นทั้งหมด", "zh": "丢弃所有本地更改", "ja": "すべてのローカル変更を破棄", "ko": "모든 로컬 변경 사항 삭제", "id": "Buang semua perubahan lokal", "ms": "Buang semua perubahan tempatan"],
        "conflict_purge_warning": ["en": "This cannot be undone. Use only if local data is corrupted.", "th": "ไม่สามารถย้อนกลับได้ ใช้เฉพาะเมื่อข้อมูลท้องถิ่นเสียหาย", "zh": "此操作不可撤销。仅在本地数据损坏时使用。", "ja": "この操作は元に戻せません。ローカルデータが破損している場合にのみ使用してください。", "ko": "이 작업은 되돌릴 수 없습니다. 로컬 데이터가 손상된 경우에만 사용하세요.", "id": "Tindakan ini tidak dapat dibatalkan. Gunakan hanya jika data lokal rusak.", "ms": "Tindakan ini tidak boleh dibatalkan. Gunakan hanya jika data tempatan rosak."],
        "conflict_queue_empty": ["en": "Queue is empty", "th": "คิวว่าง", "zh": "队列为空", "ja": "キューは空です", "ko": "대기열이 비어 있습니다", "id": "Antrean kosong", "ms": "Barisan kosong"],
        "conflict_queue_empty_desc": ["en": "All data is synced with the server. No pending changes.", "th": "ข้อมูลทั้งหมดซิงค์กับเซิร์ฟเวอร์แล้ว ไม่มีการเปลี่ยนแปลงที่รอ", "zh": "所有数据已与服务器同步。没有待处理的更改。", "ja": "すべてのデータがサーバーと同期されています。保留中の変更はありません。", "ko": "모든 데이터가 서버와 동기화되었습니다. 대기 중인 변경 사항이 없습니다.", "id": "Semua data tersinkronisasi dengan server. Tidak ada perubahan tertunda.", "ms": "Semua data disegerakkan dengan pelayan. Tiada perubahan tertangguh."],
        "conflict_queue_orders": ["en": "Orders", "th": "ออเดอร์", "zh": "订单", "ja": "注文", "ko": "주문", "id": "Pesanan", "ms": "Pesanan"],
        "conflict_queue_payments": ["en": "Payments", "th": "การชำระเงิน", "zh": "支付", "ja": "決済", "ko": "결제", "id": "Pembayaran", "ms": "Pembayaran"],
        "conflict_queue_menu": ["en": "Menu Items", "th": "เมนู", "zh": "菜单项", "ja": "メニュー", "ko": "메뉴", "id": "Item Menu", "ms": "Item Menu"],
        "conflict_queue_tables": ["en": "Tables", "th": "โต๊ะ", "zh": "桌台", "ja": "テーブル", "ko": "테이블", "id": "Meja", "ms": "Meja"],
        "conflict_queue_customers": ["en": "Customers", "th": "ลูกค้า", "zh": "客户", "ja": "顧客", "ko": "고객", "id": "Pelanggan", "ms": "Pelanggan"],
        "conflict_queue_inventory": ["en": "Inventory", "th": "สต็อก", "zh": "库存", "ja": "在庫", "ko": "재고", "id": "Inventaris", "ms": "Inventori"],
        "conflict_queue_timecards": ["en": "Timecards", "th": "บัตรเวลา", "zh": "考勤", "ja": "タイムカード", "ko": "타임카드", "id": "Kartu Waktu", "ms": "Kad Masa"],
        "conflict_more_items": ["en": "more items", "th": "รายการเพิ่มเติม", "zh": "更多项", "ja": "件追加", "ko": "개 더", "id": "item lagi", "ms": "item lagi"],
        "conflict_detected_title": ["en": "Conflict Detection", "th": "การตรวจจับ Conflict", "zh": "冲突检测", "ja": "競合検出", "ko": "충돌 감지", "id": "Deteksi Konflik", "ms": "Pengesanan Konflik"],
        "conflict_detected_desc": ["en": "When the master device and server both modify the same record, a conflict is detected. The current strategy determines which version wins.", "th": "เมื่อเครื่องแม่และเซิร์ฟเวอร์แก้ไขข้อมูลเดียวกัน ระบบจะตรวจจับ conflict กลยุทธ์ปัจจุบันจะตัดสินว่าเวอร์ชันไหนชนะ", "zh": "当主设备和服务器都修改同一记录时，会检测到冲突。当前策略决定哪个版本获胜。", "ja": "マスターデバイスとサーバーの両方が同じレコードを変更した場合、競合が検出されます。現在の戦略がどちらのバージョンが優先されるかを決定します。", "ko": "마스터 장치와 서버 모두 동일한 레코드를 수정하면 충돌이 감지됩니다. 현재 전략에 따라 어떤 버전이 우선되는지 결정됩니다.", "id": "Ketika perangkat master dan server keduanya memodifikasi record yang sama, konflik terdeteksi. Strategi saat ini menentukan versi mana yang menang.", "ms": "Apabila peranti induk dan pelayan kedua-duanya mengubah rekod yang sama, konflik dikesan. Strategi semasa menentukan versi mana yang menang."],
        "conflict_no_conflicts": ["en": "No conflicts detected", "th": "ไม่พบ conflicts", "zh": "未检测到冲突", "ja": "競合は検出されませんでした", "ko": "충돌이 감지되지 않음", "id": "Tidak ada konflik terdeteksi", "ms": "Tiada konflik dikesan"],
        "conflict_no_conflicts_desc": ["en": "All records are consistent between master device and server.", "th": "ข้อมูลทั้งหมดสอดคล้องระหว่างเครื่องแม่และเซิร์ฟเวอร์", "zh": "主设备和服务器之间的所有记录一致。", "ja": "マスターデバイスとサーバー間ですべてのレコードが一貫しています。", "ko": "마스터 장치와 서버 간의 모든 레코드가 일관됩니다.", "id": "Semua record konsisten antara perangkat master dan server.", "ms": "Semua rekod konsisten antara peranti induk dan pelayan."],
        "conflict_strategy_title": ["en": "Conflict Resolution Strategy", "th": "กลยุทธ์แก้ไข Conflict", "zh": "冲突解决策略", "ja": "競合解決戦略", "ko": "충돌 해결 전략", "id": "Strategi Resolusi Konflik", "ms": "Strategi Penyelesaian Konflik"],
        "conflict_strategy_desc": ["en": "Choose how conflicts between local and server data are resolved.", "th": "เลือกวิธีแก้ไข conflict ระหว่างข้อมูลท้องถิ่นและเซิร์ฟเวอร์", "zh": "选择如何解决本地和服务器数据之间的冲突", "ja": "ローカルとサーバーデータ間の競合の解決方法を選択", "ko": "로컬 및 서버 데이터 간의 충돌 해결 방법을 선택하세요", "id": "Pilih cara menyelesaikan konflik antara data lokal dan server.", "ms": "Pilih cara menyelesaikan konflik antara data tempatan dan pelayan."],
        "conflict_strategy_master": ["en": "Master Wins", "th": "เครื่องแม่ชนะ", "zh": "主设备优先", "ja": "マスター優先", "ko": "마스터 우선", "id": "Master Menang", "ms": "Induk Menang"],
        "conflict_strategy_master_desc": ["en": "iPad (master device) data always takes priority. Recommended for single-location.", "th": "ข้อมูล iPad (เครื่องแม่) มีความสำคัญสูงสุดเสมอ แนะนำสำหรับสาขาเดียว", "zh": "iPad（主设备）数据始终优先。推荐用于单店。", "ja": "iPad（マスターデバイス）のデータが常に優先されます。単店舗向け推奨。", "ko": "iPad(마스터 장치) 데이터가 항상 우선됩니다. 단일 매장 권장.", "id": "Data iPad (perangkat master) selalu diprioritaskan. Direkomendasikan untuk lokasi tunggal.", "ms": "Data iPad (peranti induk) sentiasa diutamakan. Disyorkan untuk lokasi tunggal."],
        "conflict_strategy_server": ["en": "Server Wins", "th": "เซิร์ฟเวอร์ชนะ", "zh": "服务器优先", "ja": "サーバー優先", "ko": "서버 우선", "id": "Server Menang", "ms": "Pelayan Menang"],
        "conflict_strategy_server_desc": ["en": "Cloud server data always takes priority. Best for multi-branch operations.", "th": "ข้อมูลเซิร์ฟเวอร์คลาวด์มีความสำคัญสูงสุดเสมอ เหมาะสำหรับหลายสาขา", "zh": "云服务器数据始终优先。最适合多店运营。", "ja": "クラウドサーバーのデータが常に優先されます。マルチ店舗運営に最適。", "ko": "클라우드 서버 데이터가 항상 우선됩니다. 다중 지점 운영에 적합.", "id": "Data server cloud selalu diprioritaskan. Terbaik untuk operasi multi-cabang.", "ms": "Data pelayan awan sentiasa diutamakan. Terbaik untuk operasi berbilang cawangan."],
        "conflict_strategy_newest": ["en": "Newest Wins", "th": "ข้อมูลใหม่สุดชนะ", "zh": "最新优先", "ja": "最新優先", "ko": "최신 우선", "id": "Terbaru Menang", "ms": "Terbaharu Menang"],
        "conflict_strategy_newest_desc": ["en": "The most recently updated version wins regardless of source.", "th": "เวอร์ชันที่อัปเดตล่าสุดชนะโดยไม่คำนึงถึงแหล่งที่มา", "zh": "最近更新的版本获胜，不论来源。", "ja": "ソースに関係なく、最新の更新バージョンが優先されます。", "ko": "출처에 관계없이 가장 최근에 업데이트된 버전이 우선됩니다.", "id": "Versi yang paling baru diperbarui yang menang terlepas dari sumbernya.", "ms": "Versi yang paling baru dikemas kini menang tanpa mengira sumber."],
        "conflict_strategy_manual": ["en": "Manual Review", "th": "ตรวจสอบด้วยตนเอง", "zh": "手动审核", "ja": "手動レビュー", "ko": "수동 검토", "id": "Tinjauan Manual", "ms": "Semakan Manual"],
        "conflict_strategy_manual_desc": ["en": "All conflicts require manual resolution by the owner. Most secure.", "th": "ทุก conflict ต้องการการตัดสินใจจากเจ้าของ ปลอดภัยที่สุด", "zh": "所有冲突需要所有者手动解决。最安全。", "ja": "すべての競合にオーナーによる手動解決が必要です。最も安全。", "ko": "모든 충돌에 소유자의 수동 해결이 필요합니다. 가장 안전합니다.", "id": "Semua konflik memerlukan resolusi manual oleh pemilik. Paling aman.", "ms": "Semua konflik memerlukan penyelesaian manual oleh pemilik. Paling selamat."],
        "conflict_priority_title": ["en": "Per-Entity Priority Override", "th": "ลำดับความสำคัญตามประเภทข้อมูล", "zh": "按实体优先级覆盖", "ja": "エンティティごとの優先度オーバーライド", "ko": "엔티티별 우선순위 오버라이드", "id": "Override Prioritas Per-Entitas", "ms": "Override Keutamaan Per-Entiti"],
        "conflict_priority_desc": ["en": "Override the global strategy for specific data types.", "th": "แทนที่กลยุทธ์หลักสำหรับประเภทข้อมูลเฉพาะ", "zh": "针对特定数据类型覆盖全局策略", "ja": "特定のデータタイプに対してグローバル戦略をオーバーライド", "ko": "특정 데이터 유형에 대해 글로벌 전략 오버라이드", "id": "Override strategi global untuk tipe data tertentu.", "ms": "Override strategi global untuk jenis data tertentu."],
        "conflict_priority_master": ["en": "Master wins", "th": "เครื่องแม่ชนะ", "zh": "主设备", "ja": "マスター", "ko": "마스터", "id": "Master", "ms": "Induk"],
        "conflict_priority_server": ["en": "Server wins", "th": "เซิร์ฟเวอร์ชนะ", "zh": "服务器", "ja": "サーバー", "ko": "서버", "id": "Server", "ms": "Pelayan"],
        "conflict_priority_newest": ["en": "Newest wins", "th": "ใหม่สุดชนะ", "zh": "最新", "ja": "最新", "ko": "최신", "id": "Terbaru", "ms": "Terbaharu"],
        "conflict_log_title": ["en": "Sync Log", "th": "บันทึกการซิงค์", "zh": "同步日志", "ja": "同期ログ", "ko": "동기화 로그", "id": "Log Sinkronisasi", "ms": "Log Penyegerakan"],
        "conflict_last_sync": ["en": "Last sync:", "th": "ซิงค์ล่าสุด:", "zh": "最近同步:", "ja": "最終同期:", "ko": "마지막 동기화:", "id": "Sinkronisasi terakhir:", "ms": "Penyegerakan terakhir:"],
        "cancel": ["en": "Cancel", "th": "ยกเลิก", "zh": "取消", "ja": "キャンセル", "ko": "취소", "id": "Batal", "ms": "Batal"],
        // MARK: - Sidebar badges
        "sidebar_badge_beta": ["en": "Beta", "th": "Beta", "zh": "Beta", "ja": "Beta", "ko": "Beta", "id": "Beta", "ms": "Beta"],
        "sidebar_badge_new": ["en": "New", "th": "ใหม่", "zh": "新", "ja": "新機能", "ko": "신규", "id": "Baru", "ms": "Baru"],
        // MARK: - Sidebar section headers
        "sidebar_section_operations": ["en": "Operations", "th": "การดำเนินงาน", "zh": "运营", "ja": "オペレーション", "ko": "운영", "id": "Operasional", "ms": "Operasi"],
        "sidebar_section_management": ["en": "Management", "th": "จัดการ", "zh": "管理", "ja": "管理", "ko": "관리", "id": "Manajemen", "ms": "Pengurusan"],
        "sidebar_section_system": ["en": "System", "th": "ระบบ", "zh": "系统", "ja": "システム", "ko": "시스템", "id": "Sistem", "ms": "Sistem"],
        // MARK: - New tab: Hot Actions / Cash Drawer
        "tab_cash_drawer_hot": ["en": "Hot Actions", "th": "คำสั่งด่วน", "zh": "快捷操作", "ja": "クイック操作", "ko": "빠른 작업", "id": "Tindakan Cepat", "ms": "Tindakan Pantas"],
        "sys_online_ssl": ["en": "System Online • SSL Secured", "th": "ระบบออนไลน์ • SSL ปลอดภัย", "zh": "系统在线 • SSL加密", "ja": "システムオンライン • SSL保護", "ko": "시스템 온라인 • SSL 보안", "id": "Sistem Online • SSL Aman", "ms": "Sistem Dalam Talian • SSL Selamat"],
        "cloud_engine_ver": ["en": "Cloud Engine v2.1", "th": "Cloud Engine v2.1", "zh": "云引擎 v2.1", "ja": "クラウドエンジン v2.1", "ko": "클라우드 엔진 v2.1", "id": "Cloud Engine v2.1", "ms": "Cloud Engine v2.1"],
        "sign_in_title": ["en": "Sign In", "th": "เข้าสู่ระบบ", "zh": "登录", "ja": "サインイン", "ko": "로그인", "id": "Masuk", "ms": "Log Masuk"],
        "sign_in_desc": ["en": "Welcome back! Sign in to your store.", "th": "ยินดีต้อนรับกลับ! เข้าสู่ระบบร้านของคุณ", "zh": "欢迎回来！登录您的门店。", "ja": "おかえりなさい！店舗にサインインしてください。", "ko": "다시 오신 것을 환영합니다! 매장에 로그인하세요.", "id": "Selamat datang kembali! Masuk ke toko Anda.", "ms": "Selamat kembali! Log masuk ke kedai anda."],
        "email_lbl": ["en": "Email", "th": "อีเมล", "zh": "邮箱", "ja": "メール", "ko": "이메일", "id": "Email", "ms": "E-mel"],
        "password_lbl": ["en": "Password", "th": "รหัสผ่าน", "zh": "密码", "ja": "パスワード", "ko": "비밀번호", "id": "Kata Sandi", "ms": "Kata Laluan"],
        "forgot_password": ["en": "Forgot Password?", "th": "ลืมรหัสผ่าน?", "zh": "忘记密码？", "ja": "パスワードを忘れましたか？", "ko": "비밀번호를 잊으셨나요?", "id": "Lupa Kata Sandi?", "ms": "Lupa Kata Laluan?"],
        "remember_store": ["en": "Remember this store", "th": "จำร้านนี้ไว้", "zh": "记住此门店", "ja": "この店舗を記憶する", "ko": "이 매장 기억하기", "id": "Ingat toko ini", "ms": "Ingat kedai ini"],
        "sign_in_btn": ["en": "Sign In", "th": "เข้าสู่ระบบ", "zh": "登录", "ja": "サインイン", "ko": "로그인", "id": "Masuk", "ms": "Log Masuk"],
        "no_account": ["en": "Don't have an account?", "th": "ยังไม่มีบัญชี?", "zh": "还没有账号？", "ja": "アカウントをお持ちでないですか？", "ko": "계정이 없으신가요?", "id": "Belum punya akun?", "ms": "Belum ada akaun?"],
        "register_btn": ["en": "Register", "th": "ลงทะเบียน", "zh": "注册", "ja": "登録", "ko": "회원가입", "id": "Daftar", "ms": "Daftar"],
        "create_title": ["en": "Create Account", "th": "สร้างบัญชี", "zh": "创建账号", "ja": "アカウント作成", "ko": "계정 만들기", "id": "Buat Akun", "ms": "Buat Akaun"],
        "first_name": ["en": "First Name", "th": "ชื่อ", "zh": "名", "ja": "名", "ko": "이름", "id": "Nama Depan", "ms": "Nama Pertama"],
        "last_name": ["en": "Last Name", "th": "นามสกุล", "zh": "姓", "ja": "姓", "ko": "성", "id": "Nama Belakang", "ms": "Nama Akhir"],
        "confirm_password": ["en": "Confirm Password", "th": "ยืนยันรหัสผ่าน", "zh": "确认密码", "ja": "パスワード確認", "ko": "비밀번호 확인", "id": "Konfirmasi Kata Sandi", "ms": "Sahkan Kata Laluan"],
        "continue_store": ["en": "Continue to Store Setup", "th": "ดำเนินการตั้งค่าร้าน", "zh": "继续门店设置", "ja": "店舗設定に進む", "ko": "매장 설정 계속", "id": "Lanjut ke Pengaturan Toko", "ms": "Teruskan ke Tetapan Kedai"],
        "already_have_store": ["en": "Already have a store?", "th": "มีร้านอยู่แล้ว?", "zh": "已有门店？", "ja": "すでに店舗をお持ちですか？", "ko": "이미 매장이 있으신가요?", "id": "Sudah punya toko?", "ms": "Sudah ada kedai?"],
        "store_name": ["en": "Store Name", "th": "ชื่อร้าน", "zh": "门店名称", "ja": "店舗名", "ko": "매장 이름", "id": "Nama Toko", "ms": "Nama Kedai"],
        "business_type": ["en": "Business Type", "th": "ประเภทธุรกิจ", "zh": "业务类型", "ja": "業種", "ko": "업종", "id": "Jenis Bisnis", "ms": "Jenis Perniagaan"],
        "currency": ["en": "Currency", "th": "สกุลเงิน", "zh": "货币", "ja": "通貨", "ko": "통화", "id": "Mata Uang", "ms": "Mata Wang"],
        "tax_id": ["en": "Tax ID", "th": "เลขประจำตัวผู้เสียภาษี", "zh": "税号", "ja": "税務ID", "ko": "사업자등록번호", "id": "NPWP", "ms": "No. Cukai"],
        "contact_phone": ["en": "Contact Phone", "th": "เบอร์โทรติดต่อ", "zh": "联系电话", "ja": "連絡先電話", "ko": "연락처", "id": "Telepon Kontak", "ms": "Telefon Hubungan"],
        "create_store_btn": ["en": "Create Store", "th": "สร้างร้าน", "zh": "创建门店", "ja": "店舗を作成", "ko": "매장 만들기", "id": "Buat Toko", "ms": "Buat Kedai"],
        "reset_title": ["en": "Reset Password", "th": "รีเซ็ตรหัสผ่าน", "zh": "重置密码", "ja": "パスワードリセット", "ko": "비밀번호 재설정", "id": "Atur Ulang Kata Sandi", "ms": "Tetapkan Semula Kata Laluan"],
        "reset_desc": ["en": "Enter your email to receive a reset link.", "th": "กรอกอีเมลเพื่อรับลิงก์รีเซ็ต", "zh": "输入邮箱以接收重置链接。", "ja": "リセットリンクを受け取るメールを入力してください。", "ko": "재설정 링크를 받을 이메일을 입력하세요.", "id": "Masukkan email untuk menerima tautan reset.", "ms": "Masukkan e-mel untuk menerima pautan tetapan semula."],
        "send_reset_btn": ["en": "Send Reset Link", "th": "ส่งลิงก์รีเซ็ต", "zh": "发送重置链接", "ja": "リセットリンクを送信", "ko": "재설정 링크 보내기", "id": "Kirim Tautan Reset", "ms": "Hantar Pautan Tetapan Semula"],
        "save": ["en": "Save", "th": "บันทึก", "zh": "保存", "ja": "保存", "ko": "저장", "id": "Simpan", "ms": "Simpan"],
        "done": ["en": "Done", "th": "เสร็จสิ้น", "zh": "完成", "ja": "完了", "ko": "완료", "id": "Selesai", "ms": "Selesai"],
        "delete": ["en": "Delete", "th": "ลบ", "zh": "删除", "ja": "削除", "ko": "삭제", "id": "Hapus", "ms": "Padam"],
        "edit": ["en": "Edit", "th": "แก้ไข", "zh": "编辑", "ja": "編集", "ko": "편집", "id": "Edit", "ms": "Sunting"],
        "add": ["en": "Add", "th": "เพิ่ม", "zh": "添加", "ja": "追加", "ko": "추가", "id": "Tambah", "ms": "Tambah"],
        "confirm": ["en": "Confirm", "th": "ยืนยัน", "zh": "确认", "ja": "確認", "ko": "확인", "id": "Konfirmasi", "ms": "Sahkan"],
        "back": ["en": "Back", "th": "กลับ", "zh": "返回", "ja": "戻る", "ko": "뒤로", "id": "Kembali", "ms": "Kembali"],
        "next": ["en": "Next", "th": "ถัดไป", "zh": "下一步", "ja": "次へ", "ko": "다음", "id": "Berikutnya", "ms": "Seterusnya"],
        "search": ["en": "Search", "th": "ค้นหา", "zh": "搜索", "ja": "検索", "ko": "검색", "id": "Cari", "ms": "Cari"],
        "loading": ["en": "Loading...", "th": "กำลังโหลด...", "zh": "加载中...", "ja": "読み込み中...", "ko": "로딩 중...", "id": "Memuat...", "ms": "Memuatkan..."],
        "error": ["en": "Error", "th": "ข้อผิดพลาด", "zh": "错误", "ja": "エラー", "ko": "오류", "id": "Kesalahan", "ms": "Ralat"],
        "success": ["en": "Success", "th": "สำเร็จ", "zh": "成功", "ja": "成功", "ko": "성공", "id": "Berhasil", "ms": "Berjaya"],
        "retry": ["en": "Retry", "th": "ลองอีกครั้ง", "zh": "重试", "ja": "再試行", "ko": "재시도", "id": "Coba Lagi", "ms": "Cuba Semula"],
        "start_scheduled_toggle": ["en": "Start Scheduled", "th": "ตั้งเวลาเริ่มโปรโมชั่น", "zh": "计划开始", "ja": "開始スケジュール", "ko": "시작 일정", "id": "Mulai Dijadwalkan", "ms": "Mula Dijadualkan"],
        "end_auto_toggle": ["en": "End Auto", "th": "ตั้งเวลาสิ้นสุดอัตโนมัติ", "zh": "自动结束", "ja": "自動終了", "ko": "자동 종료", "id": "Selesai Otomatis", "ms": "Tamat Automatik"],
        "banner_media_section": ["en": "Banner Media", "th": "สื่อสำหรับแบนเนอร์", "zh": "横幅媒体", "ja": "バナーメディア", "ko": "배너 미디어", "id": "Media Spanduk", "ms": "Media Sepanduk"],
        "media_display_standard": ["en": "Media Display Standards", "th": "มาตรฐานการแสดงผลสื่อ", "zh": "媒体显示标准", "ja": "メディア表示基準", "ko": "미디어 표시 표준", "id": "Standar Tampilan Media", "ms": "Standard Paparan Media"],
        "banner_image_standard_desc": ["en": "• Recommended image size: 1200 x 500 pixels (2.4:1 aspect ratio)", "th": "• ขนาดรูปภาพที่แนะนำ: 1200 x 500 พิกเซล (อัตราส่วน 2.4:1)", "zh": "• 建议图片大小: 1200 x 500 像素 (2.4:1 比例)", "ja": "• 推奨画像サイズ: 1200 x 500 ピクセル (2.4:1 アスペクト比)", "ko": "• 권장 이미지 크기: 1200 x 500 픽셀 (2.4:1 가로세로비)", "id": "• Rekomendasi ukuran gambar: 1200 x 500 piksel (rasio 2.4:1)", "ms": "• Saiz imej disyorkan: 1200 x 500 piksel (nisbah 2.4:1)"],
        "banner_video_standard_desc": ["en": "• Recommended video size: 1200 x 500 pixels (MP4 H.264)", "th": "• ขนาดวิดีโอที่แนะนำ: 1200 x 500 พิกเซล (MP4 H.264)", "zh": "• 建议视频大小: 1200 x 500 像素 (MP4 H.264)", "ja": "• 推奨動画サイズ: 1200 x 500 ピクセル (MP4 H.264)", "ko": "• 권장 동영상 크기: 1200 x 500 픽셀 (MP4 H.264)", "id": "• Rekomendasi ukuran video: 1200 x 500 piksel (MP4 H.264)", "ms": "• Saiz video disyorkan: 1200 x 500 piksel (MP4 H.264)"],
        "banner_safe_margin_desc": ["en": "• Safe margin: keep text 10% away from left/right edges", "th": "• แนะนำเว้นขอบซ้าย-ขวาอย่างน้อย 10% (Safe Zone)", "zh": "• 安全边距: 文字距离左右边缘保留 10% 空间", "ja": "• セーフマージン: テキストを左右の端から 10% 離してください", "ko": "• 안전 여백: 텍스트를 좌우 가장자리에서 10% 이상 띄우세요", "id": "• Batas aman: jaga teks tetap 10% dari tepi kiri/kanan", "ms": "• Margin selamat: pastikan teks 10% dari tepi kiri/kanan"],
        "auto_loop_preview_label": ["en": "Auto loop preview", "th": "พรีวิววนลูปอัตโนมัติ", "zh": "自动循环预览", "ja": "自動ループプレビュー", "ko": "자동 루프 미리보기", "id": "Pratinjau loop otomatis", "ms": "Pratonton gelung automatik"],
        "select_media_btn": ["en": "Select Image/Video", "th": "เลือกรูปภาพ/วิดีโอแบนเนอร์", "zh": "选择图片/视频", "ja": "画像/動画を選択", "ko": "이미지/동영상 선택", "id": "Pilih Gambar/Video", "ms": "Pilih Imej/Video"],
        "change_media_btn": ["en": "Change Image/Video", "th": "เปลี่ยนรูปภาพ/วิดีโอแบนเนอร์", "zh": "更换图片/视频", "ja": "画像/動画を変更", "ko": "이미지/동영상 변경", "id": "Ubah Gambar/Video", "ms": "Tukar Imej/Video"],
        "stale_shift_notification_title": ["en": "⚠️ Cash Drawer Shift Left Open", "th": "⚠️ กะลิ้นชักเงินเปิดค้างไว้นานผิดปกติ"],
        "stale_shift_notification_body": ["en": "Current shift has been open for %d hours. Please close and reconcile the drawer.", "th": "กะปัจจุบันเปิดใช้งานมาแล้ว %d ชั่วโมง โปรดทำการปิดกะและตรวจสอบยอดเงินสด"],
        "cancel_btn": ["en": "Cancel", "th": "ยกเลิก", "zh": "取消", "ja": "キャンセル", "ko": "취소", "id": "Batal", "ms": "Batal"],
        "save_btn": ["en": "Save", "th": "บันทึก", "zh": "保存", "ja": "保存", "ko": "저장", "id": "Simpan", "ms": "Simpan"],
        "delete_btn": ["en": "Delete Promotion", "th": "ลบโปรโมชั่น", "zh": "删除促销", "ja": "プロモーションを削除", "ko": "프로모션 삭제", "id": "Hapus Promosi", "ms": "Padam Promosi"],
        "minimum_spend_lbl": ["en": "Minimum Spend", "th": "ยอดซื้อขั้นต่ำ", "zh": "最低消费", "ja": "最低利用金額", "ko": "최소 구매 금액", "id": "Minimum Belanja", "ms": "Belanja Minimum"],
        "schedule_section": ["en": "Schedule", "th": "กำหนดเวลา", "zh": "计划", "ja": "スケジュール", "ko": "일정", "id": "Jadwal", "ms": "Jadual"],
        "starts_field": ["en": "Starts", "th": "เริ่มตั้งแต่วันที่", "zh": "开始时间", "ja": "開始日", "ko": "시작일", "id": "Mulai", "ms": "Mula"],
        "ends_field": ["en": "Ends", "th": "สิ้นสุดวันที่", "zh": "结束时间", "ja": "終了日", "ko": "종료일", "id": "Selesai", "ms": "Tamat"],
        "processing_media_lbl": ["en": "Processing media...", "th": "กำลังประมวลผลสื่อ...", "zh": "正在处理媒体...", "ja": "メディアを処理中...", "ko": "미디어 처리 중...", "id": "Memproses media...", "ms": "Memproses media..."],
        "no_image_selected_lbl": ["en": "No media selected", "th": "ยังไม่ได้เลือกรูปภาพ/วิดีโอ", "zh": "未选择媒体", "ja": "メディアが選択されていません", "ko": "선택된 미디어가 없습니다", "id": "Tidak ada media yang dipilih", "ms": "Tiada media dipilih"],
        "section_kds": ["en": "Kitchen Display", "th": "จอแสดงครัว", "zh": "厨房显示", "ja": "キッチンディスプレイ", "ko": "주방 디스플레이", "id": "Tampilan Dapur", "ms": "Paparan Dapur"],
        "section_table_system": ["en": "Table System", "th": "ระบบโต๊ะ", "zh": "桌台系统", "ja": "テーブルシステム", "ko": "테이블 시스템", "id": "Sistem Meja", "ms": "Sistem Meja"],
        "section_appearance": ["en": "Appearance", "th": "การแสดงผล", "zh": "外观", "ja": "外観", "ko": "외관", "id": "Tampilan", "ms": "Penampilan"],
        "section_account": ["en": "Account", "th": "บัญชี", "zh": "账户", "ja": "アカウント", "ko": "계정", "id": "Akun", "ms": "Akaun"],
        "section_general": ["en": "General", "th": "ทั่วไป", "zh": "通用", "ja": "一般", "ko": "일반", "id": "Umum", "ms": "Umum"],
        "section_printer": ["en": "Printer", "th": "เครื่องพิมพ์", "zh": "打印机", "ja": "プリンター", "ko": "프린터", "id": "Printer", "ms": "Pencetak"],
        "section_security": ["en": "Security", "th": "ความปลอดภัย", "zh": "安全", "ja": "セキュリティ", "ko": "보안", "id": "Keamanan", "ms": "Keselamatan"],
        "section_link_staff": ["en": "Staff Management", "th": "จัดการพนักงาน", "zh": "员工管理", "ja": "スタッフ管理", "ko": "직원 관리", "id": "Manajemen Staf", "ms": "Pengurusan Kakitangan"],
        "section_system_ops": ["en": "System Operations", "th": "การดำเนินการระบบ", "zh": "系统操作", "ja": "システム操作", "ko": "시스템 운영", "id": "Operasi Sistem", "ms": "Operasi Sistem"],
        "restaurant_management": ["en": "Restaurant Management", "th": "จัดการร้านอาหาร", "zh": "餐厅管理", "ja": "レストラン管理", "ko": "레스토랑 관리", "id": "Manajemen Restoran", "ms": "Pengurusan Restoran"],
        "system_online": ["en": "System Online", "th": "ระบบออนไลน์", "zh": "系统在线", "ja": "システムオンライン", "ko": "시스템 온라인", "id": "Sistem Online", "ms": "Sistem Dalam Talian"],
        "sync_success": ["en": "Synced", "th": "ซิงค์แล้ว", "zh": "已同步", "ja": "同期完了", "ko": "동기화됨", "id": "Tersinkron", "ms": "Disegerakkan"],
        "syncing": ["en": "Syncing...", "th": "กำลังซิงค์...", "zh": "同步中...", "ja": "同期中...", "ko": "동기화 중...", "id": "Menyinkronkan...", "ms": "Menyegerakkan..."],
        "sync_failed": ["en": "Sync Failed", "th": "ซิงค์ล้มเหลว", "zh": "同步失败", "ja": "同期失敗", "ko": "동기화 실패", "id": "Sinkronisasi Gagal", "ms": "Penyegerakan Gagal"],
        "offline_mode": ["en": "Offline Mode", "th": "โหมดออฟไลน์", "zh": "离线模式", "ja": "オフラインモード", "ko": "오프라인 모드", "id": "Mode Offline", "ms": "Mod Luar Talian"],
        "stock_value": ["en": "Stock Value", "th": "มูลค่าสต็อก", "zh": "库存价值", "ja": "在庫金額", "ko": "재고 가치", "id": "Nilai Stok", "ms": "Nilai Stok"],
        "low_stock_alert": ["en": "Low Stock Alert", "th": "แจ้งเตือนสต็อกต่ำ", "zh": "库存不足警告", "ja": "在庫不足アラート", "ko": "재고 부족 알림", "id": "Peringatan Stok Rendah", "ms": "Amaran Stok Rendah"],
        "items_below_reorder": ["en": "Items Below Reorder Level", "th": "สินค้าต่ำกว่าระดับสั่งซื้อ", "zh": "低于补货水平的商品", "ja": "発注基準以下の商品", "ko": "재주문 수준 미달 항목", "id": "Item di Bawah Level Reorder", "ms": "Item di Bawah Tahap Pesanan Semula"],
        "select_language": ["en": "Select Language", "th": "เลือกภาษา", "zh": "选择语言", "ja": "言語を選択", "ko": "언어 선택", "id": "Pilih Bahasa", "ms": "Pilih Bahasa"],
        "language_desc": ["en": "Choose your preferred language for the app interface.", "th": "เลือกภาษาที่ต้องการสำหรับหน้าจอแอป", "zh": "选择应用界面的首选语言。", "ja": "アプリの表示言語を選択してください。", "ko": "앱 인터페이스에 사용할 언어를 선택하세요.", "id": "Pilih bahasa yang diinginkan untuk antarmuka aplikasi.", "ms": "Pilih bahasa pilihan untuk antara muka aplikasi."],
        "store_owner": ["en": "Store Owner", "th": "เจ้าของร้าน", "zh": "店主", "ja": "店舗オーナー", "ko": "매장 소유자", "id": "Pemilik Toko", "ms": "Pemilik Kedai"],
        "change_password": ["en": "Change Password", "th": "เปลี่ยนรหัสผ่าน", "zh": "修改密码", "ja": "パスワード変更", "ko": "비밀번호 변경", "id": "Ubah Kata Sandi", "ms": "Tukar Kata Laluan"],
        "sign_out": ["en": "Sign Out", "th": "ออกจากระบบ", "zh": "退出登录", "ja": "サインアウト", "ko": "로그아웃", "id": "Keluar", "ms": "Log Keluar"],
        "delete_account": ["en": "Delete Account", "th": "ลบบัญชี", "zh": "删除账户", "ja": "アカウント削除", "ko": "계정 삭제", "id": "Hapus Akun", "ms": "Padam Akaun"],
        "sync_error": ["en": "Sync Error", "th": "ข้อผิดพลาดการซิงค์", "zh": "同步错误", "ja": "同期エラー", "ko": "동기화 오류", "id": "Kesalahan Sinkronisasi", "ms": "Ralat Penyegerakan"],
        "network_error": ["en": "Network Error", "th": "ข้อผิดพลาดเครือข่าย", "zh": "网络错误", "ja": "ネットワークエラー", "ko": "네트워크 오류", "id": "Kesalahan Jaringan", "ms": "Ralat Rangkaian"],
        "unknown_error": ["en": "Unknown Error", "th": "ข้อผิดพลาดไม่ทราบสาเหตุ", "zh": "未知错误", "ja": "不明なエラー", "ko": "알 수 없는 오류", "id": "Kesalahan Tidak Dikenal", "ms": "Ralat Tidak Diketahui"],
        "timeout": ["en": "Request Timeout", "th": "หมดเวลาคำขอ", "zh": "请求超时", "ja": "リクエストタイムアウト", "ko": "요청 시간 초과", "id": "Waktu Permintaan Habis", "ms": "Permintaan Tamat Masa"],
        "enable_table": ["en": "Enable Table System", "th": "เปิดใช้ระบบโต๊ะ", "zh": "启用桌台系统", "ja": "テーブルシステムを有効にする", "ko": "테이블 시스템 활성화", "id": "Aktifkan Sistem Meja", "ms": "Aktifkan Sistem Meja"],
        "enable_table_desc": ["en": "Allow customers to be seated at numbered tables.", "th": "อนุญาตให้ลูกค้านั่งโต๊ะตามหมายเลข", "zh": "允许顾客在编号桌台就座。", "ja": "番号付きテーブルに顧客を案内できます。", "ko": "번호가 매겨진 테이블에 고객을 착석시킵니다.", "id": "Izinkan pelanggan duduk di meja bernomor.", "ms": "Benarkan pelanggan duduk di meja bernombor."],
        "enable_web_ordering": ["en": "Enable Web Ordering", "th": "เปิดใช้สั่งอาหารออนไลน์", "zh": "启用网上点餐", "ja": "ウェブ注文を有効にする", "ko": "웹 주문 활성화", "id": "Aktifkan Pemesanan Web", "ms": "Aktifkan Pesanan Web"],
        "enable_web_desc": ["en": "Let customers scan QR to order from their device.", "th": "ให้ลูกค้าสแกน QR เพื่อสั่งอาหารจากอุปกรณ์", "zh": "让顾客扫描二维码从设备点餐。", "ja": "QRスキャンでデバイスから注文できます。", "ko": "QR 스캔으로 고객이 기기에서 주문할 수 있습니다.", "id": "Biarkan pelanggan scan QR untuk memesan dari perangkat mereka.", "ms": "Biarkan pelanggan imbas QR untuk memesan dari peranti mereka."],
        "sales_tab_analytics_overview": ["en": "Overview", "th": "ภาพรวม", "zh": "概览", "ja": "概要", "ko": "개요", "id": "Ringkasan", "ms": "Gambaran Keseluruhan"],
        "sales_tab_analytics_pl": ["en": "P&L", "th": "กำไร/ขาดทุน", "zh": "损益", "ja": "損益", "ko": "손익", "id": "Laba Rugi", "ms": "Untung Rugi"],
        "sales_tab_analytics_delivery": ["en": "Delivery", "th": "จัดส่ง", "zh": "配送", "ja": "デリバリー", "ko": "배달", "id": "Pengiriman", "ms": "Penghantaran"],
        "sales_tab_analytics_menu": ["en": "Menu", "th": "เมนู", "zh": "菜单", "ja": "メニュー", "ko": "메뉴", "id": "Menu", "ms": "Menu"],
        "sales_tab_analytics_inventory": ["en": "Inventory", "th": "สินค้าคงคลัง", "zh": "库存", "ja": "在庫", "ko": "재고", "id": "Inventaris", "ms": "Inventori"],
        "sales_tab_analytics_staff": ["en": "Staff", "th": "พนักงาน", "zh": "员工", "ja": "スタッフ", "ko": "직원", "id": "Staf", "ms": "Kakitangan"],
        "sales_title": ["en": "Sales Analytics", "th": "วิเคราะห์ยอดขาย", "zh": "销售分析", "ja": "売上分析", "ko": "매출 분석", "id": "Analitik Penjualan", "ms": "Analitik Jualan"],
        "sales_daily_summary": ["en": "Daily Summary", "th": "สรุปรายวัน", "zh": "每日汇总", "ja": "日次サマリー", "ko": "일일 요약", "id": "Ringkasan Harian", "ms": "Ringkasan Harian"],
        "sales_monthly_summary": ["en": "Monthly Summary", "th": "สรุปรายเดือน", "zh": "月度汇总", "ja": "月次サマリー", "ko": "월간 요약", "id": "Ringkasan Bulanan", "ms": "Ringkasan Bulanan"],
        "sales_payment_methods": ["en": "Payment Methods", "th": "วิธีชำระเงิน", "zh": "支付方式", "ja": "支払い方法", "ko": "결제 수단", "id": "Metode Pembayaran", "ms": "Kaedah Pembayaran"],
        "sales_recent_orders": ["en": "Recent Orders", "th": "ออเดอร์ล่าสุด", "zh": "最近订单", "ja": "最近の注文", "ko": "최근 주문", "id": "Pesanan Terbaru", "ms": "Pesanan Terkini"],
        "sales_total_revenue": ["en": "Total Revenue", "th": "รายได้รวม", "zh": "总收入", "ja": "総売上", "ko": "총 매출", "id": "Total Pendapatan", "ms": "Jumlah Hasil"],
        "sales_total_orders": ["en": "Total Orders", "th": "ออเดอร์ทั้งหมด", "zh": "总订单", "ja": "総注文数", "ko": "총 주문", "id": "Total Pesanan", "ms": "Jumlah Pesanan"],
        "sales_average_ticket_template": ["en": "Avg. Ticket", "th": "ค่าเฉลี่ยต่อบิล", "zh": "平均客单", "ja": "平均客単価", "ko": "평균 주문 금액", "id": "Rata-rata Tiket", "ms": "Purata Tiket"],
        "sales_items_sold": ["en": "Items Sold", "th": "สินค้าที่ขาย", "zh": "售出商品", "ja": "販売数", "ko": "판매 수량", "id": "Item Terjual", "ms": "Item Terjual"],
        "sales_cancelled_items_template": ["en": "Cancelled Items", "th": "รายการที่ยกเลิก", "zh": "取消商品", "ja": "キャンセル品", "ko": "취소된 항목", "id": "Item Dibatalkan", "ms": "Item Dibatalkan"],
        "sales_tax_collected": ["en": "Tax Collected", "th": "ภาษีที่เก็บได้", "zh": "已收税额", "ja": "徴収税額", "ko": "징수 세금", "id": "Pajak Terkumpul", "ms": "Cukai Dikutip"],
        "sales_by_order_type": ["en": "Sales by Order Type", "th": "ยอดขายตามประเภทออเดอร์", "zh": "按订单类型销售", "ja": "注文タイプ別売上", "ko": "주문 유형별 매출", "id": "Penjualan per Tipe Pesanan", "ms": "Jualan Mengikut Jenis Pesanan"],
        "sales_dine_in": ["en": "Dine In", "th": "ทานที่ร้าน", "zh": "堂食", "ja": "店内飲食", "ko": "매장 식사", "id": "Makan di Tempat", "ms": "Makan di Sini"],
        "sales_take_out": ["en": "Take Out", "th": "สั่งกลับบ้าน", "zh": "外带", "ja": "テイクアウト", "ko": "포장", "id": "Bawa Pulang", "ms": "Bawa Pulang"],
        "sales_delivery": ["en": "Delivery", "th": "จัดส่ง", "zh": "外卖", "ja": "デリバリー", "ko": "배달", "id": "Pengiriman", "ms": "Penghantaran"],
        "sales_product_report_title": ["en": "Product Report", "th": "รายงานสินค้า", "zh": "商品报表", "ja": "商品レポート", "ko": "상품 보고서", "id": "Laporan Produk", "ms": "Laporan Produk"],
        "sales_no_top_products": ["en": "No top products yet", "th": "ยังไม่มีสินค้ายอดนิยม", "zh": "暂无热门商品", "ja": "人気商品はまだありません", "ko": "인기 상품이 아직 없습니다", "id": "Belum ada produk teratas", "ms": "Tiada produk teratas lagi"],
        "sales_item_name_header": ["en": "Item Name", "th": "ชื่อสินค้า", "zh": "商品名称", "ja": "商品名", "ko": "상품명", "id": "Nama Item", "ms": "Nama Item"],
        "sales_category_header": ["en": "Category", "th": "หมวดหมู่", "zh": "类别", "ja": "カテゴリ", "ko": "카테고리", "id": "Kategori", "ms": "Kategori"],
        "sales_qty_header": ["en": "Qty", "th": "จำนวน", "zh": "数量", "ja": "数量", "ko": "수량", "id": "Jml", "ms": "Kuantiti"],
        "sales_margin_header": ["en": "Margin", "th": "อัตรากำไร", "zh": "利润率", "ja": "利益率", "ko": "마진", "id": "Margin", "ms": "Margin"],
        "sales_cogs_formula_subtitle": ["en": "Cost of Goods Sold", "th": "ต้นทุนสินค้าขาย", "zh": "销售成本", "ja": "売上原価", "ko": "매출원가", "id": "Harga Pokok Penjualan", "ms": "Kos Barangan Dijual"],
        "sales_profit_loss": ["en": "Profit & Loss", "th": "กำไรและขาดทุน", "zh": "损益", "ja": "損益", "ko": "손익", "id": "Laba & Rugi", "ms": "Untung & Rugi"],
        "sales_labor_cost": ["en": "Labor Cost", "th": "ค่าแรง", "zh": "人工成本", "ja": "人件費", "ko": "인건비", "id": "Biaya Tenaga Kerja", "ms": "Kos Buruh"],
        "sales_labor_pct_template": ["en": "Labor %", "th": "% ค่าแรง", "zh": "人工占比", "ja": "人件費率", "ko": "인건비 %", "id": "% Tenaga Kerja", "ms": "% Buruh"],
        "sales_waste_cost": ["en": "Waste Cost", "th": "ค่าเสียของ", "zh": "浪费成本", "ja": "廃棄コスト", "ko": "폐기 비용", "id": "Biaya Limbah", "ms": "Kos Pembaziran"],
        "sales_waste_formula_subtitle": ["en": "Spoilage & Write-offs", "th": "เสียหายและตัดจ่าย", "zh": "损耗与报废", "ja": "損耗と償却", "ko": "폐기 및 감모", "id": "Kerusakan & Penghapusan", "ms": "Kerosakan & Hapus Kira"],
        "sales_top_margin_products": ["en": "Top Margin Products", "th": "สินค้ากำไรสูง", "zh": "高利润商品", "ja": "高利益率商品", "ko": "고마진 상품", "id": "Produk Margin Tertinggi", "ms": "Produk Margin Tertinggi"],
        "sales_revenue_by_category": ["en": "Revenue by Category", "th": "รายได้ตามหมวดหมู่", "zh": "按类别收入", "ja": "カテゴリ別売上", "ko": "카테고리별 매출", "id": "Pendapatan per Kategori", "ms": "Hasil Mengikut Kategori"],
        "sales_segment_header": ["en": "Segment", "th": "กลุ่ม", "zh": "分类", "ja": "セグメント", "ko": "세그먼트", "id": "Segmen", "ms": "Segmen"],
        "reports_title": ["en": "Reports", "th": "รายงาน", "zh": "报表", "ja": "レポート", "ko": "보고서", "id": "Laporan", "ms": "Laporan"],
        "reports_select_report": ["en": "Select Report", "th": "เลือกรายงาน", "zh": "选择报表", "ja": "レポートを選択", "ko": "보고서 선택", "id": "Pilih Laporan", "ms": "Pilih Laporan"],
        "reports_period": ["en": "Period", "th": "ช่วงเวลา", "zh": "期间", "ja": "期間", "ko": "기간", "id": "Periode", "ms": "Tempoh"],
        "reports_period_daily": ["en": "Daily", "th": "รายวัน", "zh": "每日", "ja": "日次", "ko": "일별", "id": "Harian", "ms": "Harian"],
        "reports_period_weekly": ["en": "Weekly", "th": "รายสัปดาห์", "zh": "每周", "ja": "週次", "ko": "주별", "id": "Mingguan", "ms": "Mingguan"],
        "reports_period_monthly": ["en": "Monthly", "th": "รายเดือน", "zh": "每月", "ja": "月次", "ko": "월별", "id": "Bulanan", "ms": "Bulanan"],
        "reports_period_custom": ["en": "Custom", "th": "กำหนดเอง", "zh": "自定义", "ja": "カスタム", "ko": "사용자 지정", "id": "Kustom", "ms": "Tersuai"],
        "reports_start_date": ["en": "Start Date", "th": "วันเริ่มต้น", "zh": "开始日期", "ja": "開始日", "ko": "시작일", "id": "Tanggal Mulai", "ms": "Tarikh Mula"],
        "reports_end_date": ["en": "End Date", "th": "วันสิ้นสุด", "zh": "结束日期", "ja": "終了日", "ko": "종료일", "id": "Tanggal Akhir", "ms": "Tarikh Tamat"],
        "reports_date": ["en": "Date", "th": "วันที่", "zh": "日期", "ja": "日付", "ko": "날짜", "id": "Tanggal", "ms": "Tarikh"],
        "reports_export_pdf": ["en": "Export PDF", "th": "ส่งออก PDF", "zh": "导出PDF", "ja": "PDF出力", "ko": "PDF 내보내기", "id": "Ekspor PDF", "ms": "Eksport PDF"],
        "reports_daily_sales": ["en": "Daily Sales", "th": "ยอดขายรายวัน", "zh": "每日销售", "ja": "日次売上", "ko": "일일 매출", "id": "Penjualan Harian", "ms": "Jualan Harian"],
        "reports_z_report": ["en": "Z-Report", "th": "รายงาน Z", "zh": "Z报表", "ja": "Zレポート", "ko": "Z-리포트", "id": "Laporan Z", "ms": "Laporan Z"],
        "reports_tax_vat": ["en": "Tax / VAT", "th": "ภาษี / VAT", "zh": "税 / 增值税", "ja": "税 / VAT", "ko": "세금 / 부가세", "id": "Pajak / PPN", "ms": "Cukai / GST"],
        "reports_menu_profit": ["en": "Menu Profit", "th": "กำไรเมนู", "zh": "菜品利润", "ja": "メニュー利益", "ko": "메뉴 수익", "id": "Keuntungan Menu", "ms": "Keuntungan Menu"],
        "reports_inventory": ["en": "Inventory", "th": "สินค้าคงคลัง", "zh": "库存", "ja": "在庫", "ko": "재고", "id": "Inventaris", "ms": "Inventori"],
        "reports_employee_hours": ["en": "Employee Hours", "th": "ชั่วโมงพนักงาน", "zh": "员工工时", "ja": "従業員勤務時間", "ko": "직원 근무시간", "id": "Jam Karyawan", "ms": "Jam Pekerja"],
        "reports_no_session": ["en": "No Active Session", "th": "ไม่มีเซสชันที่ใช้งาน", "zh": "无活动会话", "ja": "アクティブなセッションなし", "ko": "활성 세션 없음", "id": "Tidak Ada Sesi Aktif", "ms": "Tiada Sesi Aktif"],
        "reports_no_session_desc": ["en": "Open a cash drawer session to see the Z-Report.", "th": "เปิดเซสชันลิ้นชักเงินสดเพื่อดูรายงาน Z", "zh": "打开收银会话以查看Z报表。", "ja": "Zレポートを表示するにはキャッシュドロワーセッションを開いてください。", "ko": "Z-리포트를 보려면 금전함 세션을 열어주세요.", "id": "Buka sesi laci kas untuk melihat Laporan Z.", "ms": "Buka sesi laci tunai untuk melihat Laporan Z."],
        "reports_end_of_day": ["en": "End of Day Report", "th": "รายงานสิ้นวัน", "zh": "日终报表", "ja": "日締めレポート", "ko": "마감 보고서", "id": "Laporan Akhir Hari", "ms": "Laporan Akhir Hari"],
        "reports_session_info": ["en": "Session Info", "th": "ข้อมูลเซสชัน", "zh": "会话信息", "ja": "セッション情報", "ko": "세션 정보", "id": "Info Sesi", "ms": "Info Sesi"],
        "reports_opened_at": ["en": "Opened At", "th": "เปิดเมื่อ", "zh": "开启时间", "ja": "開始時刻", "ko": "개시 시각", "id": "Dibuka Pada", "ms": "Dibuka Pada"],
        "reports_closed_at": ["en": "Closed At", "th": "ปิดเมื่อ", "zh": "关闭时间", "ja": "終了時刻", "ko": "마감 시각", "id": "Ditutup Pada", "ms": "Ditutup Pada"],
        "reports_duration": ["en": "Duration", "th": "ระยะเวลา", "zh": "持续时间", "ja": "所要時間", "ko": "소요 시간", "id": "Durasi", "ms": "Tempoh"],
        "reports_cash_flow": ["en": "Cash Flow", "th": "กระแสเงินสด", "zh": "现金流", "ja": "キャッシュフロー", "ko": "현금 흐름", "id": "Arus Kas", "ms": "Aliran Tunai"],
        "reports_opening_balance": ["en": "Opening Balance", "th": "ยอดเปิด", "zh": "期初余额", "ja": "開始残高", "ko": "개시 잔액", "id": "Saldo Awal", "ms": "Baki Pembukaan"],
        "reports_cash_sales": ["en": "Cash Sales", "th": "ยอดขายเงินสด", "zh": "现金销售", "ja": "現金売上", "ko": "현금 매출", "id": "Penjualan Tunai", "ms": "Jualan Tunai"],
        "reports_cash_in": ["en": "Cash In", "th": "เงินสดเข้า", "zh": "现金流入", "ja": "入金", "ko": "현금 입금", "id": "Kas Masuk", "ms": "Tunai Masuk"],
        "reports_cash_out": ["en": "Cash Out", "th": "เงินสดออก", "zh": "现金流出", "ja": "出金", "ko": "현금 출금", "id": "Kas Keluar", "ms": "Tunai Keluar"],
        "reports_totals": ["en": "Totals", "th": "ยอดรวม", "zh": "合计", "ja": "合計", "ko": "합계", "id": "Total", "ms": "Jumlah"],
        "reports_expected_cash": ["en": "Expected Cash", "th": "เงินสดที่คาดว่าจะมี", "zh": "应有现金", "ja": "想定現金", "ko": "예상 현금", "id": "Kas Diharapkan", "ms": "Tunai Dijangka"],
        "reports_actual_cash": ["en": "Actual Cash", "th": "เงินสดจริง", "zh": "实际现金", "ja": "実際現金", "ko": "실제 현금", "id": "Kas Aktual", "ms": "Tunai Sebenar"],
        "reports_variance": ["en": "Variance", "th": "ผลต่าง", "zh": "差异", "ja": "差異", "ko": "차이", "id": "Selisih", "ms": "Varians"],
        "reports_variance_short": ["en": "Short", "th": "ขาด", "zh": "短缺", "ja": "不足", "ko": "부족", "id": "Kurang", "ms": "Kurang"],
        "reports_variance_over": ["en": "Over", "th": "เกิน", "zh": "超出", "ja": "超過", "ko": "초과", "id": "Lebih", "ms": "Lebih"],
        "reports_variance_ok": ["en": "Balanced", "th": "สมดุล", "zh": "平衡", "ja": "一致", "ko": "균형", "id": "Seimbang", "ms": "Seimbang"],
        "reports_total_labor_hours": ["en": "Total Labor Hours", "th": "ชั่วโมงแรงงานทั้งหมด", "zh": "总工时", "ja": "総労働時間", "ko": "총 근무시간", "id": "Total Jam Kerja", "ms": "Jumlah Jam Buruh"],
        "reports_total_labor_cost": ["en": "Total Labor Cost", "th": "ค่าแรงทั้งหมด", "zh": "总人工成本", "ja": "総人件費", "ko": "총 인건비", "id": "Total Biaya Tenaga Kerja", "ms": "Jumlah Kos Buruh"],
        "reports_total_ot": ["en": "Total Overtime", "th": "ล่วงเวลาทั้งหมด", "zh": "总加班", "ja": "総残業", "ko": "총 초과근무", "id": "Total Lembur", "ms": "Jumlah Kerja Lebih Masa"],
        "reports_active_staff": ["en": "Active Staff", "th": "พนักงานที่ใช้งาน", "zh": "活跃员工", "ja": "アクティブスタッフ", "ko": "활동 직원", "id": "Staf Aktif", "ms": "Kakitangan Aktif"],
        "reports_hours_per_employee": ["en": "Hours Per Employee", "th": "ชั่วโมงต่อพนักงาน", "zh": "人均工时", "ja": "従業員あたり時間", "ko": "직원당 시간", "id": "Jam Per Karyawan", "ms": "Jam Setiap Pekerja"],
        "reports_no_data": ["en": "No data available", "th": "ไม่มีข้อมูล", "zh": "暂无数据", "ja": "データなし", "ko": "데이터 없음", "id": "Tidak ada data", "ms": "Tiada data"],
        "reports_hours": ["en": "Hours", "th": "ชั่วโมง", "zh": "小时", "ja": "時間", "ko": "시간", "id": "Jam", "ms": "Jam"],
        "reports_regular_hours": ["en": "Regular Hours", "th": "ชั่วโมงปกติ", "zh": "正常工时", "ja": "通常勤務", "ko": "정규 시간", "id": "Jam Reguler", "ms": "Jam Biasa"],
        "reports_overtime_hours": ["en": "Overtime Hours", "th": "ชั่วโมงล่วงเวลา", "zh": "加班工时", "ja": "残業時間", "ko": "초과 근무시간", "id": "Jam Lembur", "ms": "Jam Lebih Masa"],
        "reports_employee_detail": ["en": "Employee Detail", "th": "รายละเอียดพนักงาน", "zh": "员工详情", "ja": "従業員詳細", "ko": "직원 상세", "id": "Detail Karyawan", "ms": "Butiran Pekerja"],
        "reports_employee": ["en": "Employee", "th": "พนักงาน", "zh": "员工", "ja": "従業員", "ko": "직원", "id": "Karyawan", "ms": "Pekerja"],
        "reports_type": ["en": "Type", "th": "ประเภท", "zh": "类型", "ja": "タイプ", "ko": "유형", "id": "Tipe", "ms": "Jenis"],
        "reports_total_hours": ["en": "Total Hours", "th": "ชั่วโมงทั้งหมด", "zh": "总小时", "ja": "合計時間", "ko": "총 시간", "id": "Total Jam", "ms": "Jumlah Jam"],
        "reports_breaks": ["en": "Breaks", "th": "พัก", "zh": "休息", "ja": "休憩", "ko": "휴식", "id": "Istirahat", "ms": "Rehat"],
        "reports_rate": ["en": "Rate", "th": "อัตรา", "zh": "费率", "ja": "時給", "ko": "시급", "id": "Tarif", "ms": "Kadar"],
        "reports_est_cost": ["en": "Est. Cost", "th": "ค่าใช้จ่ายโดยประมาณ", "zh": "预估成本", "ja": "推定コスト", "ko": "예상 비용", "id": "Perkiraan Biaya", "ms": "Anggaran Kos"],
        "reports_total": ["en": "Total", "th": "ทั้งหมด", "zh": "合计", "ja": "合計", "ko": "합계", "id": "Total", "ms": "Jumlah"],
        "reports_hourly": ["en": "Hourly", "th": "รายชั่วโมง", "zh": "按小时", "ja": "時間別", "ko": "시간별", "id": "Per Jam", "ms": "Setiap Jam"],
        "reports_daily": ["en": "Daily", "th": "รายวัน", "zh": "每日", "ja": "日別", "ko": "일별", "id": "Harian", "ms": "Harian"],
        "reports_monthly": ["en": "Monthly", "th": "รายเดือน", "zh": "每月", "ja": "月別", "ko": "월별", "id": "Bulanan", "ms": "Bulanan"],
        "reports_sales_inc_vat": ["en": "Sales (inc. VAT)", "th": "ยอดขาย (รวม VAT)", "zh": "销售额（含税）", "ja": "売上（税込）", "ko": "매출 (부가세 포함)", "id": "Penjualan (inc. PPN)", "ms": "Jualan (termasuk GST)"],
        "reports_vat_amount": ["en": "VAT Amount", "th": "จำนวน VAT", "zh": "税额", "ja": "消費税額", "ko": "부가세 금액", "id": "Jumlah PPN", "ms": "Jumlah GST"],
        "reports_sales_exc_vat": ["en": "Sales (exc. VAT)", "th": "ยอดขาย (ไม่รวม VAT)", "zh": "销售额（不含税）", "ja": "売上（税抜）", "ko": "매출 (부가세 제외)", "id": "Penjualan (exc. PPN)", "ms": "Jualan (tidak termasuk GST)"],
        "reports_daily_vat_breakdown": ["en": "Daily VAT Breakdown", "th": "รายละเอียด VAT รายวัน", "zh": "每日税务明细", "ja": "日次消費税内訳", "ko": "일별 부가세 내역", "id": "Rincian PPN Harian", "ms": "Pecahan GST Harian"],
        "reports_detailed_breakdown": ["en": "Detailed Breakdown", "th": "รายละเอียดแยกย่อย", "zh": "详细明细", "ja": "詳細内訳", "ko": "상세 내역", "id": "Rincian Detail", "ms": "Pecahan Terperinci"],
        "reports_orders": ["en": "Orders", "th": "ออเดอร์", "zh": "订单", "ja": "注文", "ko": "주문", "id": "Pesanan", "ms": "Pesanan"],
        "reports_total_items": ["en": "Total Items", "th": "สินค้าทั้งหมด", "zh": "总商品数", "ja": "総品目", "ko": "총 항목", "id": "Total Item", "ms": "Jumlah Item"],
        "reports_total_revenue": ["en": "Total Revenue", "th": "รายได้รวม", "zh": "总收入", "ja": "総売上", "ko": "총 매출", "id": "Total Pendapatan", "ms": "Jumlah Hasil"],
        "reports_total_cogs": ["en": "Total COGS", "th": "ต้นทุนรวม", "zh": "总销售成本", "ja": "総売上原価", "ko": "총 매출원가", "id": "Total HPP", "ms": "Jumlah KBD"],
        "reports_avg_margin": ["en": "Avg. Margin", "th": "อัตรากำไรเฉลี่ย", "zh": "平均利润率", "ja": "平均利益率", "ko": "평균 마진", "id": "Rata-rata Margin", "ms": "Purata Margin"],
        "reports_top_profitable": ["en": "Top Profitable", "th": "กำไรสูงสุด", "zh": "最高利润", "ja": "最高利益", "ko": "최고 수익", "id": "Paling Menguntungkan", "ms": "Paling Menguntungkan"],
        "reports_least_profitable": ["en": "Least Profitable", "th": "กำไรต่ำสุด", "zh": "最低利润", "ja": "最低利益", "ko": "최저 수익", "id": "Paling Tidak Menguntungkan", "ms": "Paling Tidak Menguntungkan"],
        "reports_menu_item_breakdown": ["en": "Menu Item Breakdown", "th": "รายละเอียดเมนู", "zh": "菜品明细", "ja": "メニュー項目内訳", "ko": "메뉴 항목 내역", "id": "Rincian Menu", "ms": "Pecahan Item Menu"],
        "reports_item_name": ["en": "Item Name", "th": "ชื่อสินค้า", "zh": "商品名称", "ja": "商品名", "ko": "상품명", "id": "Nama Item", "ms": "Nama Item"],
        "reports_qty_sold": ["en": "Qty Sold", "th": "จำนวนขาย", "zh": "售出数", "ja": "販売数", "ko": "판매수량", "id": "Jml Terjual", "ms": "Kuantiti Dijual"],
        "reports_revenue": ["en": "Revenue", "th": "รายได้", "zh": "收入", "ja": "売上", "ko": "매출", "id": "Pendapatan", "ms": "Hasil"],
        "reports_cogs": ["en": "COGS", "th": "ต้นทุน", "zh": "成本", "ja": "原価", "ko": "원가", "id": "HPP", "ms": "KBD"],
        "reports_profit": ["en": "Profit", "th": "กำไร", "zh": "利润", "ja": "利益", "ko": "이익", "id": "Keuntungan", "ms": "Keuntungan"],
        "reports_margin": ["en": "Margin", "th": "อัตรากำไร", "zh": "利润率", "ja": "利益率", "ko": "마진", "id": "Margin", "ms": "Margin"],
        "reports_gross_revenue": ["en": "Gross Revenue", "th": "รายได้รวม", "zh": "总收入", "ja": "総売上", "ko": "총 매출", "id": "Pendapatan Kotor", "ms": "Hasil Kasar"],
        "reports_net_revenue": ["en": "Net Revenue", "th": "รายได้สุทธิ", "zh": "净收入", "ja": "純売上", "ko": "순 매출", "id": "Pendapatan Bersih", "ms": "Hasil Bersih"],
        "reports_total_orders": ["en": "Total Orders", "th": "ออเดอร์ทั้งหมด", "zh": "总订单", "ja": "総注文数", "ko": "총 주문", "id": "Total Pesanan", "ms": "Jumlah Pesanan"],
        "reports_avg_ticket": ["en": "Avg. Ticket", "th": "ค่าเฉลี่ยต่อบิล", "zh": "平均客单", "ja": "平均客単価", "ko": "평균 주문 금액", "id": "Rata-rata Tiket", "ms": "Purata Tiket"],
        "reports_total_discount": ["en": "Total Discount", "th": "ส่วนลดทั้งหมด", "zh": "总折扣", "ja": "総割引", "ko": "총 할인", "id": "Total Diskon", "ms": "Jumlah Diskaun"],
        "reports_total_refunds": ["en": "Total Refunds", "th": "คืนเงินทั้งหมด", "zh": "总退款", "ja": "総返金", "ko": "총 환불", "id": "Total Refund", "ms": "Jumlah Bayaran Balik"],
        "reports_payment_methods": ["en": "Payment Methods", "th": "วิธีชำระเงิน", "zh": "支付方式", "ja": "支払い方法", "ko": "결제 수단", "id": "Metode Pembayaran", "ms": "Kaedah Pembayaran"],
        "reports_peak_hour": ["en": "Peak Hour", "th": "ชั่วโมงเร่งด่วน", "zh": "高峰时段", "ja": "ピーク時間", "ko": "피크 시간", "id": "Jam Sibuk", "ms": "Waktu Puncak"],
        "reports_hourly_sales": ["en": "Hourly Sales", "th": "ยอดขายรายชั่วโมง", "zh": "每小时销售", "ja": "時間帯別売上", "ko": "시간대별 매출", "id": "Penjualan Per Jam", "ms": "Jualan Setiap Jam"],
        "reports_payment_breakdown": ["en": "Payment Breakdown", "th": "รายละเอียดการชำระ", "zh": "支付明细", "ja": "支払い内訳", "ko": "결제 내역", "id": "Rincian Pembayaran", "ms": "Pecahan Pembayaran"],
        "reports_method_cash": ["en": "Cash", "th": "เงินสด", "zh": "现金", "ja": "現金", "ko": "현금", "id": "Tunai", "ms": "Tunai"],
        "reports_method_card": ["en": "Card", "th": "บัตร", "zh": "银行卡", "ja": "カード", "ko": "카드", "id": "Kartu", "ms": "Kad"],
        "reports_method_qr": ["en": "QR Payment", "th": "ชำระผ่าน QR", "zh": "二维码支付", "ja": "QR決済", "ko": "QR 결제", "id": "Pembayaran QR", "ms": "Pembayaran QR"],
        "reports_total_stock_value": ["en": "Total Stock Value", "th": "มูลค่าสต็อกทั้งหมด", "zh": "总库存价值", "ja": "総在庫金額", "ko": "총 재고 가치", "id": "Total Nilai Stok", "ms": "Jumlah Nilai Stok"],
        "reports_low_stock_count": ["en": "Low Stock Count", "th": "จำนวนสต็อกต่ำ", "zh": "低库存数量", "ja": "在庫不足数", "ko": "재고 부족 수", "id": "Jumlah Stok Rendah", "ms": "Bilangan Stok Rendah"],
        "reports_out_of_stock_count": ["en": "Out of Stock Count", "th": "จำนวนสินค้าหมด", "zh": "缺货数量", "ja": "欠品数", "ko": "품절 수", "id": "Jumlah Habis Stok", "ms": "Bilangan Kehabisan Stok"],
        "reports_waste_cost": ["en": "Waste Cost", "th": "ค่าเสียของ", "zh": "浪费成本", "ja": "廃棄コスト", "ko": "폐기 비용", "id": "Biaya Limbah", "ms": "Kos Pembaziran"],
        "reports_out_of_stock": ["en": "Out of Stock", "th": "สินค้าหมด", "zh": "缺货", "ja": "欠品", "ko": "품절", "id": "Habis Stok", "ms": "Kehabisan Stok"],
        "reports_reorder_level": ["en": "Reorder Level", "th": "ระดับสั่งซื้อใหม่", "zh": "补货水平", "ja": "発注基準", "ko": "재주문 수준", "id": "Level Reorder", "ms": "Tahap Pesanan Semula"],
        "reports_out_of_stock_badge": ["en": "OUT", "th": "หมด", "zh": "缺", "ja": "欠品", "ko": "품절", "id": "HABIS", "ms": "HABIS"],
        "reports_low_stock": ["en": "Low Stock Items", "th": "สินค้าสต็อกต่ำ", "zh": "低库存商品", "ja": "在庫不足品", "ko": "재고 부족 항목", "id": "Item Stok Rendah", "ms": "Item Stok Rendah"],
        "reports_no_low_stock": ["en": "No low stock items", "th": "ไม่มีสินค้าสต็อกต่ำ", "zh": "无低库存商品", "ja": "在庫不足品なし", "ko": "재고 부족 항목 없음", "id": "Tidak ada item stok rendah", "ms": "Tiada item stok rendah"],
        "reports_waste_and_spoilage": ["en": "Waste & Spoilage", "th": "ของเสียและเสียหาย", "zh": "浪费与损耗", "ja": "廃棄と損耗", "ko": "폐기 및 손실", "id": "Limbah & Kerusakan", "ms": "Pembaziran & Kerosakan"],
        "reports_total_waste": ["en": "Total Waste", "th": "ของเสียทั้งหมด", "zh": "总浪费", "ja": "総廃棄", "ko": "총 폐기", "id": "Total Limbah", "ms": "Jumlah Pembaziran"],
        "reports_no_waste": ["en": "No waste recorded", "th": "ไม่มีการบันทึกของเสีย", "zh": "无浪费记录", "ja": "廃棄記録なし", "ko": "폐기 기록 없음", "id": "Tidak ada limbah tercatat", "ms": "Tiada pembaziran direkodkan"],
        "reports_quantity": ["en": "Quantity", "th": "จำนวน", "zh": "数量", "ja": "数量", "ko": "수량", "id": "Jumlah", "ms": "Kuantiti"],
        "reports_cost": ["en": "Cost", "th": "ค่าใช้จ่าย", "zh": "成本", "ja": "コスト", "ko": "비용", "id": "Biaya", "ms": "Kos"],
        "reports_notes": ["en": "Notes", "th": "หมายเหตุ", "zh": "备注", "ja": "備考", "ko": "메모", "id": "Catatan", "ms": "Nota"],
        "promos_delete_btn": ["en": "Delete Promotion", "th": "ลบโปรโมชั่น", "zh": "删除促销", "ja": "プロモーション削除", "ko": "프로모션 삭제", "id": "Hapus Promosi", "ms": "Padam Promosi"],
        "promos_title": ["en": "Promotions", "th": "โปรโมชั่น", "zh": "促销活动", "ja": "プロモーション", "ko": "프로모션", "id": "Promosi", "ms": "Promosi"],
        "promos_subtitle": ["en": "Manage your store promotions", "th": "จัดการโปรโมชั่นร้านค้า", "zh": "管理您的促销活动", "ja": "店舗プロモーションを管理", "ko": "매장 프로모션 관리", "id": "Kelola promosi toko Anda", "ms": "Urus promosi kedai anda"],
        "promos_add_promotion": ["en": "Add Promotion", "th": "เพิ่มโปรโมชั่น", "zh": "添加促销", "ja": "プロモーション追加", "ko": "프로모션 추가", "id": "Tambah Promosi", "ms": "Tambah Promosi"],
        "promos_no_promotions_title": ["en": "No Promotions", "th": "ไม่มีโปรโมชั่น", "zh": "无促销活动", "ja": "プロモーションなし", "ko": "프로모션 없음", "id": "Tidak Ada Promosi", "ms": "Tiada Promosi"],
        "promos_no_promotions_subtitle": ["en": "Create your first promotion to attract more customers.", "th": "สร้างโปรโมชั่นแรกเพื่อดึงดูดลูกค้า", "zh": "创建您的第一个促销活动以吸引更多顾客。", "ja": "最初のプロモーションを作成して顧客を増やしましょう。", "ko": "첫 프로모션을 만들어 고객을 유치하세요.", "id": "Buat promosi pertama untuk menarik lebih banyak pelanggan.", "ms": "Buat promosi pertama untuk menarik lebih ramai pelanggan."],
        "promos_no_description": ["en": "No description", "th": "ไม่มีคำอธิบาย", "zh": "无描述", "ja": "説明なし", "ko": "설명 없음", "id": "Tidak ada deskripsi", "ms": "Tiada penerangan"],
        "promos_details_section": ["en": "Details", "th": "รายละเอียด", "zh": "详情", "ja": "詳細", "ko": "세부 사항", "id": "Detail", "ms": "Butiran"],
        "promos_title_label": ["en": "Title", "th": "ชื่อ", "zh": "标题", "ja": "タイトル", "ko": "제목", "id": "Judul", "ms": "Tajuk"],
        "promos_description_label": ["en": "Description", "th": "คำอธิบาย", "zh": "描述", "ja": "説明", "ko": "설명", "id": "Deskripsi", "ms": "Penerangan"],
        "promos_status_active": ["en": "Active", "th": "ใช้งานอยู่", "zh": "活跃", "ja": "有効", "ko": "활성", "id": "Aktif", "ms": "Aktif"],
        "promos_type_none": ["en": "None", "th": "ไม่มี", "zh": "无", "ja": "なし", "ko": "없음", "id": "Tidak Ada", "ms": "Tiada"],
        "promos_type_percentage": ["en": "Percentage Off", "th": "ลดเป็นเปอร์เซ็นต์", "zh": "百分比折扣", "ja": "パーセント割引", "ko": "퍼센트 할인", "id": "Diskon Persentase", "ms": "Diskaun Peratus"],
        "promos_type_fixed": ["en": "Fixed Amount Off", "th": "ลดจำนวนเงินคงที่", "zh": "固定金额折扣", "ja": "定額割引", "ko": "정액 할인", "id": "Diskon Jumlah Tetap", "ms": "Diskaun Jumlah Tetap"],
        "promos_type_bundle": ["en": "Bundle Deal", "th": "ดีลชุดรวม", "zh": "捆绑优惠", "ja": "セット割引", "ko": "번들 딜", "id": "Promo Bundel", "ms": "Tawaran Bundle"],
        "promos_select_product": ["en": "Select Product", "th": "เลือกสินค้า", "zh": "选择商品", "ja": "商品を選択", "ko": "상품 선택", "id": "Pilih Produk", "ms": "Pilih Produk"],
        "promos_edit_promotion": ["en": "Edit Promotion", "th": "แก้ไขโปรโมชั่น", "zh": "编辑促销", "ja": "プロモーション編集", "ko": "프로모션 편집", "id": "Edit Promosi", "ms": "Sunting Promosi"],
        "timecard_title": ["en": "Timecard", "th": "บัตรเวลา", "zh": "考勤", "ja": "タイムカード", "ko": "타임카드", "id": "Kartu Waktu", "ms": "Kad Masa"],
        "timecard_no_employees_title": ["en": "No Employees", "th": "ไม่มีพนักงาน", "zh": "无员工", "ja": "従業員なし", "ko": "직원 없음", "id": "Tidak Ada Karyawan", "ms": "Tiada Pekerja"],
        "timecard_no_employees_subtitle": ["en": "Add employees in Staff Management to use timecards.", "th": "เพิ่มพนักงานในจัดการพนักงานเพื่อใช้บัตรเวลา", "zh": "在员工管理中添加员工以使用考勤。", "ja": "タイムカードを使用するにはスタッフ管理で従業員を追加してください。", "ko": "타임카드를 사용하려면 직원 관리에서 직원을 추가하세요.", "id": "Tambah karyawan di Manajemen Staf untuk menggunakan kartu waktu.", "ms": "Tambah pekerja dalam Pengurusan Kakitangan untuk menggunakan kad masa."],
        "timecard_stat_staff": ["en": "Staff", "th": "พนักงาน", "zh": "员工", "ja": "スタッフ", "ko": "직원", "id": "Staf", "ms": "Kakitangan"],
        "timecard_stat_clocked_in": ["en": "Clocked In", "th": "ลงเวลาเข้า", "zh": "已打卡", "ja": "出勤中", "ko": "출근", "id": "Masuk", "ms": "Masuk"],
        "timecard_stat_approved": ["en": "Approved", "th": "อนุมัติ", "zh": "已批准", "ja": "承認済み", "ko": "승인됨", "id": "Disetujui", "ms": "Diluluskan"],
        "timecard_recent_activity": ["en": "Recent Activity", "th": "กิจกรรมล่าสุด", "zh": "最近活动", "ja": "最近のアクティビティ", "ko": "최근 활동", "id": "Aktivitas Terbaru", "ms": "Aktiviti Terkini"],
        "timecard_recent_records_template": ["en": "Recent Records", "th": "บันทึกล่าสุด", "zh": "最近记录", "ja": "最近の記録", "ko": "최근 기록", "id": "Catatan Terbaru", "ms": "Rekod Terkini"],
        "timecard_no_records_yet": ["en": "No records yet", "th": "ยังไม่มีบันทึก", "zh": "暂无记录", "ja": "記録なし", "ko": "기록 없음", "id": "Belum ada catatan", "ms": "Tiada rekod lagi"],
        "timecard_badge_on_shift": ["en": "On Shift", "th": "กำลังทำงาน", "zh": "当班中", "ja": "勤務中", "ko": "근무 중", "id": "Sedang Shift", "ms": "Sedang Bekerja"],
        "timecard_badge_staff_label": ["en": "Staff", "th": "พนักงาน", "zh": "员工", "ja": "スタッフ", "ko": "직원", "id": "Staf", "ms": "Kakitangan"],
        "timecard_btn_clock_out": ["en": "Clock Out", "th": "ลงเวลาออก", "zh": "下班打卡", "ja": "退勤", "ko": "퇴근", "id": "Clock Out", "ms": "Keluar"],
        "timecard_btn_clock_in": ["en": "Clock In", "th": "ลงเวลาเข้า", "zh": "上班打卡", "ja": "出勤", "ko": "출근", "id": "Clock In", "ms": "Masuk"],
        "timecard_log_active_now": ["en": "Active Now", "th": "กำลังใช้งาน", "zh": "当前活跃", "ja": "アクティブ", "ko": "현재 활동 중", "id": "Aktif Sekarang", "ms": "Aktif Sekarang"],
        "timecard_badge_approved": ["en": "Approved", "th": "อนุมัติ", "zh": "已批准", "ja": "承認済み", "ko": "승인됨", "id": "Disetujui", "ms": "Diluluskan"],
        "timecard_badge_pending": ["en": "Pending", "th": "รอดำเนินการ", "zh": "待处理", "ja": "保留中", "ko": "대기 중", "id": "Menunggu", "ms": "Menunggu"],
        "timecard_scan_msg_position": ["en": "Position your face in the frame", "th": "จัดตำแหน่งใบหน้าในกรอบ", "zh": "将面部对准框内", "ja": "顔をフレーム内に配置してください", "ko": "프레임 안에 얼굴을 위치시키세요", "id": "Posisikan wajah Anda dalam bingkai", "ms": "Letakkan wajah anda dalam bingkai"],
        "timecard_scan_msg_extracting": ["en": "Extracting features...", "th": "กำลังดึงข้อมูลใบหน้า...", "zh": "正在提取特征...", "ja": "特徴を抽出中...", "ko": "특징 추출 중...", "id": "Mengekstrak fitur...", "ms": "Mengekstrak ciri..."],
        "timecard_scan_msg_comparing": ["en": "Comparing...", "th": "กำลังเปรียบเทียบ...", "zh": "正在比较...", "ja": "照合中...", "ko": "비교 중...", "id": "Membandingkan...", "ms": "Membandingkan..."],
        "timecard_scan_msg_distance": ["en": "Distance", "th": "ระยะห่าง", "zh": "距离", "ja": "距離", "ko": "거리", "id": "Jarak", "ms": "Jarak"],
        "timecard_face_id_slider_lbl": ["en": "Face Recognition Sensitivity", "th": "ความไวในการจดจำใบหน้า", "zh": "人脸识别灵敏度", "ja": "顔認識感度", "ko": "얼굴 인식 감도", "id": "Sensitivitas Pengenalan Wajah", "ms": "Sensitiviti Pengecaman Wajah"],
        "timecard_face_btn_clock_in": ["en": "Face Clock In", "th": "ลงเวลาเข้าด้วยใบหน้า", "zh": "人脸上班打卡", "ja": "顔認証出勤", "ko": "얼굴 인식 출근", "id": "Clock In Wajah", "ms": "Masuk Wajah"],
        "timecard_face_btn_clock_out": ["en": "Face Clock Out", "th": "ลงเวลาออกด้วยใบหน้า", "zh": "人脸下班打卡", "ja": "顔認証退勤", "ko": "얼굴 인식 퇴근", "id": "Clock Out Wajah", "ms": "Keluar Wajah"],
        "timecard_face_scanner_title": ["en": "Face Scanner", "th": "สแกนใบหน้า", "zh": "人脸扫描", "ja": "顔スキャナー", "ko": "얼굴 스캐너", "id": "Pemindai Wajah", "ms": "Pengimbas Wajah"],
        "store_tab_profile": ["en": "Profile", "th": "โปรไฟล์", "zh": "资料", "ja": "プロフィール", "ko": "프로필", "id": "Profil", "ms": "Profil"],
        "store_tab_tax": ["en": "Tax", "th": "ภาษี", "zh": "税务", "ja": "税金", "ko": "세금", "id": "Pajak", "ms": "Cukai"],
        "store_tab_qr": ["en": "QR Code", "th": "QR โค้ด", "zh": "二维码", "ja": "QRコード", "ko": "QR 코드", "id": "Kode QR", "ms": "Kod QR"],
        "store_title": ["en": "Store Settings", "th": "ตั้งค่าร้านค้า", "zh": "门店设置", "ja": "店舗設定", "ko": "매장 설정", "id": "Pengaturan Toko", "ms": "Tetapan Kedai"],
        "store_branding_header": ["en": "Branding", "th": "แบรนด์", "zh": "品牌", "ja": "ブランディング", "ko": "브랜딩", "id": "Branding", "ms": "Penjenamaan"],
        "store_select_logo": ["en": "Select Logo", "th": "เลือกโลโก้", "zh": "选择标志", "ja": "ロゴを選択", "ko": "로고 선택", "id": "Pilih Logo", "ms": "Pilih Logo"],
        "store_name_label": ["en": "Store Name", "th": "ชื่อร้าน", "zh": "门店名称", "ja": "店舗名", "ko": "매장 이름", "id": "Nama Toko", "ms": "Nama Kedai"],
        "store_website_label": ["en": "Website", "th": "เว็บไซต์", "zh": "网站", "ja": "ウェブサイト", "ko": "웹사이트", "id": "Situs Web", "ms": "Laman Web"],
        "store_branch_label": ["en": "Branch", "th": "สาขา", "zh": "分店", "ja": "支店", "ko": "지점", "id": "Cabang", "ms": "Cawangan"],
        "store_tax_inclusive_opt": ["en": "Tax Inclusive", "th": "รวมภาษี", "zh": "含税", "ja": "税込", "ko": "세금 포함", "id": "Termasuk Pajak", "ms": "Termasuk Cukai"],
        "store_tax_exclusive_opt": ["en": "Tax Exclusive", "th": "ไม่รวมภาษี", "zh": "不含税", "ja": "税抜", "ko": "세금 별도", "id": "Tidak Termasuk Pajak", "ms": "Tidak Termasuk Cukai"],
        "store_tax_invoice_header": ["en": "Tax Invoice", "th": "ใบกำกับภาษี", "zh": "税务发票", "ja": "税務請求書", "ko": "세금 계산서", "id": "Faktur Pajak", "ms": "Invois Cukai"],
        "store_subtotal_lbl": ["en": "Subtotal", "th": "ยอดรวมย่อย", "zh": "小计", "ja": "小計", "ko": "소계", "id": "Subtotal", "ms": "Jumlah Kecil"],
        "store_total_lbl": ["en": "Total", "th": "ทั้งหมด", "zh": "合计", "ja": "合計", "ko": "합계", "id": "Total", "ms": "Jumlah"],
        "store_qr_branding_header": ["en": "QR Branding", "th": "แบรนด์ QR", "zh": "二维码品牌", "ja": "QRブランディング", "ko": "QR 브랜딩", "id": "Branding QR", "ms": "Penjenamaan QR"],
        "store_qr_store_name_lbl": ["en": "Store Name on QR", "th": "ชื่อร้านบน QR", "zh": "二维码上的店名", "ja": "QR上の店舗名", "ko": "QR 코드 매장 이름", "id": "Nama Toko di QR", "ms": "Nama Kedai pada QR"],
        "store_qr_header_lbl": ["en": "QR Header", "th": "หัวข้อ QR", "zh": "二维码标题", "ja": "QRヘッダー", "ko": "QR 헤더", "id": "Header QR", "ms": "Pengepala QR"],
        "store_qr_show_logo_toggle": ["en": "Show Logo on QR", "th": "แสดงโลโก้บน QR", "zh": "在二维码上显示标志", "ja": "QRにロゴを表示", "ko": "QR에 로고 표시", "id": "Tampilkan Logo di QR", "ms": "Papar Logo pada QR"],
        "store_qr_logo_preset_lbl": ["en": "Logo Preset", "th": "พรีเซ็ตโลโก้", "zh": "标志预设", "ja": "ロゴプリセット", "ko": "로고 프리셋", "id": "Preset Logo", "ms": "Pratetap Logo"],
        "store_preset_bolt": ["en": "Bolt", "th": "สายฟ้า", "zh": "闪电", "ja": "ボルト", "ko": "번개", "id": "Petir", "ms": "Kilat"],
        "store_preset_fork_knife": ["en": "Fork & Knife", "th": "ส้อมและมีด", "zh": "刀叉", "ja": "フォーク＆ナイフ", "ko": "포크 & 나이프", "id": "Garpu & Pisau", "ms": "Garpu & Pisau"],
        "store_preset_star": ["en": "Star", "th": "ดาว", "zh": "星星", "ja": "スター", "ko": "별", "id": "Bintang", "ms": "Bintang"],
        "store_preset_heart": ["en": "Heart", "th": "หัวใจ", "zh": "心形", "ja": "ハート", "ko": "하트", "id": "Hati", "ms": "Hati"],
        "store_preset_coffee": ["en": "Coffee", "th": "กาแฟ", "zh": "咖啡", "ja": "コーヒー", "ko": "커피", "id": "Kopi", "ms": "Kopi"],
        "store_preset_beer": ["en": "Beer", "th": "เบียร์", "zh": "啤酒", "ja": "ビール", "ko": "맥주", "id": "Bir", "ms": "Bir"],
        "store_qr_theme_color_lbl": ["en": "Theme Color", "th": "สีธีม", "zh": "主题色", "ja": "テーマカラー", "ko": "테마 색상", "id": "Warna Tema", "ms": "Warna Tema"],
        "store_live_qr_preview": ["en": "Live QR Preview", "th": "ตัวอย่าง QR สด", "zh": "实时二维码预览", "ja": "QRライブプレビュー", "ko": "QR 실시간 미리보기", "id": "Pratinjau QR Langsung", "ms": "Pratonton QR Langsung"],
        "sync_status_synced": ["en": "Synced", "th": "ซิงค์แล้ว", "zh": "已同步", "ja": "同期済み", "ko": "동기화됨", "id": "Tersinkron", "ms": "Disegerakkan"],
        "sync_status_syncing": ["en": "Syncing...", "th": "กำลังซิงค์...", "zh": "同步中...", "ja": "同期中...", "ko": "동기화 중...", "id": "Menyinkronkan...", "ms": "Menyegerakkan..."],
        "sync_status_error": ["en": "Sync Error", "th": "ข้อผิดพลาดซิงค์", "zh": "同步错误", "ja": "同期エラー", "ko": "동기화 오류", "id": "Kesalahan Sinkronisasi", "ms": "Ralat Penyegerakan"],
        "sync_status_offline": ["en": "Offline", "th": "ออฟไลน์", "zh": "离线", "ja": "オフライン", "ko": "오프라인", "id": "Offline", "ms": "Luar Talian"],
        "sync_queue_orders": ["en": "Orders", "th": "ออเดอร์", "zh": "订单", "ja": "注文", "ko": "주문", "id": "Pesanan", "ms": "Pesanan"],
        "sync_queue_payments": ["en": "Payments", "th": "การชำระเงิน", "zh": "支付", "ja": "支払い", "ko": "결제", "id": "Pembayaran", "ms": "Pembayaran"],
        "sync_queue_tables": ["en": "Tables", "th": "โต๊ะ", "zh": "桌台", "ja": "テーブル", "ko": "테이블", "id": "Meja", "ms": "Meja"],
        "sync_queue_menu": ["en": "Menu", "th": "เมนู", "zh": "菜单", "ja": "メニュー", "ko": "메뉴", "id": "Menu", "ms": "Menu"],
        "sync_queue_inventory": ["en": "Inventory", "th": "สินค้าคงคลัง", "zh": "库存", "ja": "在庫", "ko": "재고", "id": "Inventaris", "ms": "Inventori"],
        "sync_queue_customers": ["en": "Customers", "th": "ลูกค้า", "zh": "顾客", "ja": "顧客", "ko": "고객", "id": "Pelanggan", "ms": "Pelanggan"],
        "sync_queue_loyalty": ["en": "Loyalty", "th": "สะสมแต้ม", "zh": "会员", "ja": "ロイヤルティ", "ko": "로열티", "id": "Loyalitas", "ms": "Kesetiaan"],
        "sync_queue_financial": ["en": "Financial", "th": "การเงิน", "zh": "财务", "ja": "財務", "ko": "재무", "id": "Keuangan", "ms": "Kewangan"],
        "sync_title": ["en": "Sync Health", "th": "สถานะการซิงค์", "zh": "同步状态", "ja": "同期状態", "ko": "동기화 상태", "id": "Status Sinkronisasi", "ms": "Status Penyegerakan"],
        "sync_now_btn": ["en": "Sync Now", "th": "ซิงค์ตอนนี้", "zh": "立即同步", "ja": "今すぐ同期", "ko": "지금 동기화", "id": "Sinkronkan Sekarang", "ms": "Segerakkan Sekarang"],
        "sync_summary_status": ["en": "Status", "th": "สถานะ", "zh": "状态", "ja": "ステータス", "ko": "상태", "id": "Status", "ms": "Status"],
        "sync_pending_queue": ["en": "Pending Queue", "th": "คิวรอดำเนินการ", "zh": "待处理队列", "ja": "保留キュー", "ko": "대기 큐", "id": "Antrian Menunggu", "ms": "Baris Gilir Menunggu"],
        "sync_connection": ["en": "Connection", "th": "การเชื่อมต่อ", "zh": "连接", "ja": "接続", "ko": "연결", "id": "Koneksi", "ms": "Sambungan"],
        "sync_last_synced": ["en": "Last Synced", "th": "ซิงค์ล่าสุด", "zh": "上次同步", "ja": "最終同期", "ko": "마지막 동기화", "id": "Terakhir Disinkronkan", "ms": "Terakhir Disegerakkan"],
        "sync_pending_label": ["en": "Pending", "th": "รอดำเนินการ", "zh": "待处理", "ja": "保留中", "ko": "대기 중", "id": "Menunggu", "ms": "Menunggu"],
        "sync_deleted_label": ["en": "Deleted", "th": "ลบแล้ว", "zh": "已删除", "ja": "削除済み", "ko": "삭제됨", "id": "Dihapus", "ms": "Dipadam"],
        "sync_recent_activity": ["en": "Recent Activity", "th": "กิจกรรมล่าสุด", "zh": "最近活动", "ja": "最近のアクティビティ", "ko": "최근 활동", "id": "Aktivitas Terbaru", "ms": "Aktiviti Terkini"],
        "sync_no_recent_activity": ["en": "No recent activity", "th": "ไม่มีกิจกรรมล่าสุด", "zh": "无最近活动", "ja": "最近のアクティビティなし", "ko": "최근 활동 없음", "id": "Tidak ada aktivitas terbaru", "ms": "Tiada aktiviti terkini"],
        "sync_conn_online": ["en": "Online", "th": "ออนไลน์", "zh": "在线", "ja": "オンライン", "ko": "온라인", "id": "Online", "ms": "Dalam Talian"],
        "sync_conn_offline": ["en": "Offline", "th": "ออฟไลน์", "zh": "离线", "ja": "オフライン", "ko": "오프라인", "id": "Offline", "ms": "Luar Talian"],
        "section_tax_rates": ["en": "Taxes & Fees", "th": "ภาษีและค่าธรรมเนียม", "zh": "税率与费用", "ja": "税金・手数料", "ko": "세금 및 수수료", "id": "Pajak & Biaya", "ms": "Cukai & Bayaran"],
        "section_receipt_templates": ["en": "Receipt Templates", "th": "เทมเพลตใบเสร็จ", "zh": "收据模板", "ja": "レシートテンプレート", "ko": "영수증 템플릿", "id": "Templat Struk", "ms": "Templat Resit"],
        "section_currency_exchange": ["en": "Multi-Currency Settings", "th": "ตั้งค่าหลายสกุลเงิน", "zh": "多货币设置", "ja": "多通貨設定", "ko": "다중 통화 설정", "id": "Pengaturan Multi-Mata Uang", "ms": "Tetapan Multi-Mata Wang"],
        "ADD": ["en": "ADD", "th": "เพิ่ม", "zh": "添加", "ja": "追加", "ko": "추가", "id": "TAMBAH", "ms": "TAMBAH"],
        "INCL": ["en": "INCL", "th": "รวม", "zh": "含", "ja": "込", "ko": "포함", "id": "TERMASUK", "ms": "TERMASUK"],
        "active_status_desc": ["en": "Enable this entry for active usage in calculations", "th": "เปิดใช้งานรายการนี้เพื่อใช้ในการคำนวณ", "zh": "启用此项以在计算中处于激活状态", "ja": "計算でアクティブに使用するためにこのエントリを有効にします", "ko": "계산에서 활성화하여 사용하려면 이 항목을 활성화하십시오", "id": "Aktifkan entri ini untuk penggunaan aktif dalam perhitungan", "ms": "Dayakan entri ini untuk penggunaan aktif dalam pengiraan"],
        "active_status_lbl": ["en": "Active Status", "th": "สถานะใช้งาน", "zh": "激活状态", "ja": "アクティブステータス", "ko": "활성 상태", "id": "Status Aktif", "ms": "Status Aktif"],
        "add_exchange_rate_header": ["en": "Add Exchange Rate", "th": "เพิ่มอัตราแลกเปลี่ยน", "zh": "添加汇率", "ja": "為替レートを追加", "ko": "환율 추가", "id": "Tambah Nilai Tukar", "ms": "Tambah Kadar Pertukaran"],
        "add_new_template_btn": ["en": "Add New Template", "th": "เพิ่มเทมเพลตใหม่", "zh": "添加新模板", "ja": "新規テンプレートを追加", "ko": "새 템플릿 추가", "id": "Tambah Templat Baru", "ms": "Tambah Templat Baru"],
        "add_rate_btn": ["en": "Add Rate", "th": "เพิ่มอัตราแลกเปลี่ยน", "zh": "添加汇率", "ja": "レートを追加", "ko": "환율 추가", "id": "Tambah Nilai", "ms": "Tambah Kadar"],
        "add_tax_btn": ["en": "Add Tax", "th": "เพิ่มภาษี", "zh": "添加税率", "ja": "税金を追加", "ko": "세금 추가", "id": "Tambah Pajak", "ms": "Tambah Cukai"],
        "add_tax_rate_header": ["en": "Add Tax Rate", "th": "เพิ่มอัตราภาษี", "zh": "添加税率", "ja": "税率を追加", "ko": "세율 추가", "id": "Tambah Tarif Pajak", "ms": "Tambah Kadar Cukai"],
        "amount_in_thb_lbl": ["en": "Amount in THB", "th": "จำนวนเงิน (THB)", "zh": "泰铢金额", "ja": "THBでの金額", "ko": "THB 금액", "id": "Jumlah dalam THB", "ms": "Jumlah dalam THB"],
        "base_currency_display": ["en": "Base Currency (THB)", "th": "สกุลเงินหลัก (THB)", "zh": "基准货币 (THB)", "ja": "基軸通貨 (THB)", "ko": "기준 통화 (THB)", "id": "Mata Uang Dasar (THB)", "ms": "Mata Wang Asas (THB)"],
        "converted_amount_lbl": ["en": "Converted Amount", "th": "จำนวนเงินที่แปลงแล้ว", "zh": "转换后的金额", "ja": "変換後の金額", "ko": "변환된 금액", "id": "Jumlah Terkonversi", "ms": "Jumlah Ditukar"],
        "create_template_header": ["en": "Create Receipt Template", "th": "สร้างเทมเพลตใบเสร็จ", "zh": "创建收据模板", "ja": "レシートテンプレートを作成", "ko": "영수증 템플릿 생성", "id": "Buat Templat Struk", "ms": "Buat Templat Resit"],
        "currencies_exchange_section": ["en": "Exchange Rates", "th": "อัตราแลกเปลี่ยน", "zh": "汇率", "ja": "為替レート", "ko": "환율", "id": "Nilai Tukar", "ms": "Kadar Pertukaran"],
        "currencies_exchange_title": ["en": "Currencies & Exchange", "th": "สกุลเงินและอัตราแลกเปลี่ยน", "zh": "货币与汇率", "ja": "通貨と為替", "ko": "통화 및 환율", "id": "Mata Uang & Nilai Tukar", "ms": "Mata Wang & Kadar Pertukaran"],
        "default_badge": ["en": "DEFAULT", "th": "หลัก", "zh": "默认", "ja": "デフォルト", "ko": "기본값", "id": "DEFAULT", "ms": "LALUAN"],
        "demo_grand_total": ["en": "Demo Grand Total", "th": "ยอดรวมสุทธิ (ตัวอย่าง)", "zh": "演示总计", "ja": "デモ総合計", "ko": "데모 총계", "id": "Total Akhir Demo", "ms": "Jumlah Besar Demo"],
        "demo_items_subtotal": ["en": "Demo Items Subtotal", "th": "ยอดรวมสินค้า (ตัวอย่าง)", "zh": "演示商品小计", "ja": "デモ商品小計", "ko": "데모 품목 소계", "id": "Subtotal Item Demo", "ms": "Subjumlah Item Demo"],
        "demo_subtotal_lbl": ["en": "Demo Subtotal", "th": "ยอดรวม (ตัวอย่าง)", "zh": "演示小计", "ja": "デモ小計", "ko": "데모 소계", "id": "Subtotal Demo", "ms": "Subjumlah Demo"],
        "edit_exchange_rate_header": ["en": "Edit Exchange Rate", "th": "แก้ไขอัตราแลกเปลี่ยน", "zh": "编辑汇率", "ja": "為替レートを編集", "ko": "환율 편집", "id": "Edit Nilai Tukar", "ms": "Edit Kadar Pertukaran"],
        "edit_tax_rate_header": ["en": "Edit Tax Rate", "th": "แก้ไขอัตราภาษี", "zh": "编辑税率", "ja": "税率を編集", "ko": "세율 편집", "id": "Edit Tarif Pajak", "ms": "Edit Kadar Cukai"],
        "edit_template_header": ["en": "Edit Receipt Template", "th": "แก้ไขเทมเพลตใบเสร็จ", "zh": "编辑收据模板", "ja": "レシートテンプレートを編集", "ko": "영수증 템플릿 편집", "id": "Edit Templat Struk", "ms": "Edit Templat Resit"],
        "exchange_calculator_title": ["en": "Live Conversion Calculator", "th": "เครื่องคิดเลขแปลงเงินสด", "zh": "实时汇率换算器", "ja": "リアルタイム為替換算機", "ko": "실시간 환율 계산기", "id": "Kalkulator Konversi Langsung", "ms": "Kalkulator Penukaran Langsung"],
        "exchange_rate_lbl": ["en": "Exchange Rate (1 THB = ?)", "th": "อัตราแลกเปลี่ยน (1 THB = ?)", "zh": "汇率 (1 THB = ?)", "ja": "為替レート (1 THB = ?)", "ko": "환율 (1 THB = ?)", "id": "Nilai Tukar (1 THB = ?)", "ms": "Kadar Pertukaran (1 THB = ?)"],
        "exclusive_tax_explanation": ["en": "Tax is added on top of item prices at checkout.", "th": "ภาษีจะถูกบวกเพิ่มจากราคาสินค้า ณ ตอนเช็คเอาต์", "zh": "结账时，税费将加在商品价格之上。", "ja": "税金はチェックアウト時に商品価格の上に追加されます。", "ko": "결제 시 상품 가격 위에 세금이 추가됩니다.", "id": "Pajak ditambahkan di atas harga item saat checkout.", "ms": "Cukai ditambah di atas harga item semasa pembayaran."],
        "footer_text_lbl": ["en": "Footer Text", "th": "ข้อความท้ายใบเสร็จ", "zh": "页脚文本", "ja": "フッターテキスト", "ko": "바닥글 텍스트", "id": "Teks Halaman Bawah", "ms": "Teks Kaki"],
        "header_text_lbl": ["en": "Header Text", "th": "ข้อความหัวใบเสร็จ", "zh": "页眉文本", "ja": "ヘッダーテキスト", "ko": "머리글 텍스트", "id": "Teks Halaman Atas", "ms": "Teks Kepala"],
        "inclusive_tax_explanation": ["en": "Tax is already included in item prices.", "th": "ราคาสินค้าได้รวมภาษีไว้เรียบร้อยแล้ว", "zh": "税费已包含在商品价格中。", "ja": "税金はすでに商品価格に含まれています。", "ko": "세금이 이미 상품 가격에 포함되어 있습니다.", "id": "Pajak sudah termasuk dalam harga item.", "ms": "Cukai sudah termasuk dalam harga item."],
        "info_box_title": ["en": "Information", "th": "ข้อมูล", "zh": "信息", "ja": "情報", "ko": "정보", "id": "Informasi", "ms": "Maklumat"],
        "live_receipt_preview": ["en": "Live Thermal Receipt Preview", "th": "ตัวอย่างใบเสร็จความร้อนแบบเรียลไทม์", "zh": "实时热敏收据预览", "ja": "レシートリアルタイムプレビュー", "ko": "실시간 열전사 영수증 미리보기", "id": "Pratinjau Struk Termal Langsung", "ms": "Pratonton Resit Terma Langsung"],
        "no_rates_placeholder": ["en": "No currency rates defined yet.", "th": "ยังไม่มีการกำหนดอัตราแลกเปลี่ยนสกุลเงิน", "zh": "尚未定义汇率。", "ja": "為替レートがまだ定義されていません。", "ko": "정의된 환율이 없습니다.", "id": "Belum ada nilai tukar yang ditentukan.", "ms": "Tiada kadar mata wang ditakrifkan lagi."],
        "no_taxes_placeholder": ["en": "No tax rates defined yet.", "th": "ยังไม่มีการกำหนดอัตราภาษี", "zh": "尚未定义税率。", "ja": "税率がまだ定義されていません。", "ko": "정의된 세율이 없습니다.", "id": "Belum ada tarif pajak yang ditentukan.", "ms": "Tiada kadar cukai ditakrifkan lagi."],
        "no_templates_placeholder": ["en": "No receipt templates defined yet.", "th": "ยังไม่มีการกำหนดเทมเพลตใบเสร็จ", "zh": "尚未定义收据模板。", "ja": "レシートテンプレートがまだ定義されていません。", "ko": "정의된 영수증 템플릿이 없습니다.", "id": "Belum ada templat struk yang ditentukan.", "ms": "Tiada templat resit ditakrifkan lagi."],
        "receipt_templates_section": ["en": "Templates", "th": "เทมเพลตทั้งหมด", "zh": "模板", "ja": "テンプレート", "ko": "템플릿", "id": "Templat", "ms": "Templat"],
        "receipt_templates_title": ["en": "Receipt Templates", "th": "ตั้งค่าเทมเพลตใบเสร็จ", "zh": "收据模板", "ja": "レシートテンプレート", "ko": "영수증 템플릿", "id": "Templat Struk", "ms": "Templat Resit"],
        "template_tab_edit": ["en": "Template Settings", "th": "ตั้งค่าเทมเพลต", "zh": "设置", "ja": "設定", "ko": "설정", "id": "Pengaturan", "ms": "Tetapan"],
        "template_tab_preview": ["en": "Live Preview", "th": "ดูตัวอย่างใบเสร็จ", "zh": "实时预览", "ja": "ライブプレビュー", "ko": "실시간 미리보기", "id": "Pratinjau Struk", "ms": "Pratonton Resit"],
        "save_changes_btn": ["en": "Save Changes", "th": "บันทึกการเปลี่ยนแปลง", "zh": "保存修改", "ja": "変更を保存", "ko": "변경 사항 저장", "id": "Simpan Perubahan", "ms": "Simpan Perubahan"],
        "save_new_template_btn": ["en": "Save Template", "th": "บันทึกเทมเพลต", "zh": "保存模板", "ja": "テンプレートを保存", "ko": "템플릿 저장", "id": "Simpan Templat", "ms": "Simpan Templat"],
        "save_rate_btn": ["en": "Save Rate", "th": "บันทึกอัตราแลกเปลี่ยน", "zh": "保存汇率", "ja": "レートを保存", "ko": "환율 저장", "id": "Simpan Nilai", "ms": "Simpan Kadar"],
        "save_tax_btn": ["en": "Save Tax", "th": "บันทึกภาษี", "zh": "保存税率", "ja": "税金を保存", "ko": "세금 저장", "id": "Simpan Pajak", "ms": "Simpan Cukai"],
        "set_as_default_desc": ["en": "Use this configuration as system default", "th": "ใช้การตั้งค่านี้เป็นค่าเริ่มต้นของระบบ", "zh": "将此配置用作系统默认值", "ja": "この設定をシステムのデフォルトとして使用します", "ko": "이 구성을 시스템 기본값으로 사용", "id": "Gunakan konfigurasi ini sebagai default sistem", "ms": "Gunakan konfigurasi ini sebagai lalai sistem"],
        "set_as_default_lbl": ["en": "Set as Default", "th": "ตั้งเป็นค่าเริ่มต้น", "zh": "设为默认值", "ja": "デフォルトに設定", "ko": "기본값으로 설정", "id": "Atur sebagai Default", "ms": "Tetapkan sebagai Lalai"],
        "show_customer_info_desc": ["en": "Print customer name and info on receipt", "th": "แสดงชื่อและข้อมูลลูกค้าบนใบเสร็จ", "zh": "在收据上打印顾客姓名和信息", "ja": "レシートに顧客名と情報を印刷します", "ko": "영수증에 고객 이름 및 정보 인쇄", "id": "Cetak nama dan info pelanggan di struk", "ms": "Cetak nama dan maklumat pelanggan pada resit"],
        "show_customer_info_lbl": ["en": "Show Customer Info", "th": "แสดงข้อมูลลูกค้า", "zh": "显示顾客信息", "ja": "顧客情報を表示", "ko": "고객 정보 표시", "id": "Tampilkan Info Pelanggan", "ms": "Papar Maklumat Pelanggan"],
        "show_tax_id_desc": ["en": "Print merchant Tax ID on receipt", "th": "แสดงเลขผู้เสียภาษีบนใบเสร็จ", "zh": "在收据上打印商户税号", "ja": "レシートに加盟店税務IDを印刷します", "ko": "영수증에 가맹점 사업자등록번호 인쇄", "id": "Cetak NPWP merchant di struk", "ms": "Cetak No. Cukai peniaga pada resit"],
        "show_tax_id_lbl": ["en": "Show Tax ID", "th": "แสดงเลขผู้เสียภาษี", "zh": "显示税号", "ja": "税務IDを表示", "ko": "사업자등록번호 표시", "id": "Tampilkan NPWP", "ms": "Papar No. Cukai"],
        "target_currency_lbl": ["en": "Target Currency (e.g. USD, EUR, LAK)", "th": "สกุลเงินเป้าหมาย (เช่น USD, EUR, LAK)", "zh": "目标货币 (例如 USD, EUR, LAK)", "ja": "対象通貨 (例: USD, EUR, LAK)", "ko": "대상 통화 (예: USD, EUR, LAK)", "id": "Mata Uang Target (mis. USD, EUR, LAK)", "ms": "Mata Wang Sasaran (cth. USD, EUR, LAK)"],
        "tax_calculation_demo_title": ["en": "Checkout Tax Calculator Demo", "th": "สาธิตการคำนวณภาษีตอนคิดเงิน", "zh": "结账税费计算演示", "ja": "チェックアウト税金計算デモ", "ko": "결제 세금 계산 데모", "id": "Demo Kalkulator Pajak Checkout", "ms": "Demo Kalkulator Cukai Pembayaran"],
        "tax_calculation_type_lbl": ["en": "Tax Calculation Type", "th": "รูปแบบการคำนวณภาษี", "zh": "计税类型", "ja": "税金計算タイプ", "ko": "세금 계산 유형", "id": "Tipe Perhitungan Pajak", "ms": "Jenis Pengiraan Cukai"],
        "tax_exclusive_btn": ["en": "Exclusive", "th": "ไม่รวมภาษี (Exclusive)", "zh": "不含税 (Exclusive)", "ja": "税抜 (Exclusive)", "ko": "세금 별도 (Exclusive)", "id": "Tidak Termasuk Pajak (Exclusive)", "ms": "Tidak Termasuk Cukai (Exclusive)"],
        "tax_inclusive_btn": ["en": "Inclusive", "th": "รวมภาษี (Inclusive)", "zh": "含税 (Inclusive)", "ja": "税込 (Inclusive)", "ko": "세금 포함 (Inclusive)", "id": "Termasuk Pajak (Inclusive)", "ms": "Termasuk Cukai (Inclusive)"],
        "tax_name_lbl": ["en": "Tax Name", "th": "ชื่อภาษี", "zh": "税率名称", "ja": "税名", "ko": "세금 이름", "id": "Nama Pajak", "ms": "Nama Cukai"],
        "tax_rate_percentage_lbl": ["en": "Tax Rate Percentage (%)", "th": "อัตราภาษี (%)", "zh": "税率百分比 (%)", "ja": "税率 (%)", "ko": "세율 (%)", "id": "Persentase Tarif Pajak (%)", "ms": "Peratusan Kadar Cukai (%)"],
        "tax_rates_section": ["en": "Tax Rates", "th": "อัตราภาษีทั้งหมด", "zh": "税率列表", "ja": "税率一覧", "ko": "세율 목록", "id": "Tarif Pajak", "ms": "Kadar Cukai"],
        "tax_rates_title": ["en": "Tax Settings", "th": "ตั้งค่าภาษีร้านค้า", "zh": "税务设置", "ja": "税金設定", "ko": "세금 설정", "id": "Pengaturan Pajak", "ms": "Tetapan Cukai"],
        "template_name_lbl": ["en": "Template Name", "th": "ชื่อเทมเพลต", "zh": "模板名称", "ja": "テンプレート名", "ko": "템플릿 이름", "id": "Nama Templat", "ms": "Nama Templat"],
        // MARK: - Table Status
        "table_status_vacant": ["en": "Vacant", "th": "ว่าง", "zh": "空桌", "ja": "空席", "ko": "빈 자리", "id": "Kosong", "ms": "Kosong"],
        "table_status_occupied": ["en": "Occupied", "th": "มีลูกค้า", "zh": "使用中", "ja": "使用中", "ko": "사용 중", "id": "Terisi", "ms": "Diduduki"],
        "table_status_reserved": ["en": "Reserved", "th": "จอง", "zh": "已预订", "ja": "予約済み", "ko": "예약됨", "id": "Dipesan", "ms": "Ditempah"],
        "table_status_cleaning": ["en": "Cleaning", "th": "กำลังทำความสะอาด", "zh": "清洁中", "ja": "清掃中", "ko": "청소 중", "id": "Sedang Dibersihkan", "ms": "Sedang Dibersihkan"],
        // MARK: - Table Floor
        "table_floor_1": ["en": "Floor 1", "th": "ชั้น 1", "zh": "1楼", "ja": "1階", "ko": "1층", "id": "Lantai 1", "ms": "Lantai 1"],
        "table_floor_2": ["en": "Floor 2", "th": "ชั้น 2", "zh": "2楼", "ja": "2階", "ko": "2층", "id": "Lantai 2", "ms": "Lantai 2"],
        "table_floor_3": ["en": "Floor 3", "th": "ชั้น 3", "zh": "3楼", "ja": "3階", "ko": "3층", "id": "Lantai 3", "ms": "Lantai 3"],
        "table_floor_level_lbl": ["en": "Floor", "th": "ชั้น", "zh": "楼层", "ja": "階", "ko": "층", "id": "Lantai", "ms": "Lantai"],
        "table_floor_level_hint": ["en": "Select the floor for this table", "th": "เลือกชั้นสำหรับโต๊ะนี้", "zh": "选择此桌的楼层", "ja": "このテーブルの階を選択してください", "ko": "이 테이블의 층을 선택하세요", "id": "Pilih lantai untuk meja ini", "ms": "Pilih tingkat untuk meja ini"],
        // MARK: - Table Zone
        "table_zone_all": ["en": "All Zones", "th": "ทุกโซน", "zh": "所有区域", "ja": "全エリア", "ko": "전체 구역", "id": "Semua Zona", "ms": "Semua Zon"],
        "table_zone_indoor": ["en": "Indoor", "th": "ในร้าน", "zh": "室内", "ja": "室内", "ko": "실내", "id": "Dalam Ruangan", "ms": "Dalam Bangunan"],
        "table_zone_outdoor": ["en": "Outdoor", "th": "นอกร้าน", "zh": "室外", "ja": "屋外", "ko": "야외", "id": "Luar Ruangan", "ms": "Luar Bangunan"],
        "table_zone_rooftop": ["en": "Rooftop", "th": "ดาดฟ้า", "zh": "屋顶", "ja": "屋上", "ko": "루프탑", "id": "Rooftop", "ms": "Bumbung"],
        "table_zone_lbl": ["en": "Zone", "th": "โซน", "zh": "区域", "ja": "エリア", "ko": "구역", "id": "Zona", "ms": "Zon"],
        "table_zone_hint": ["en": "Select the zone for this table", "th": "เลือกโซนสำหรับโต๊ะนี้", "zh": "选择此桌的区域", "ja": "このテーブルのエリアを選択してください", "ko": "이 테이블의 구역을 선택하세요", "id": "Pilih zona untuk meja ini", "ms": "Pilih zon untuk meja ini"],
        // MARK: - Time
        // MARK: - Table Layout Mode
        "table_layout_mode_canvas": ["en": "Canvas", "th": "แคนวาส", "zh": "画布", "ja": "キャンバス", "ko": "캔버스", "id": "Kanvas", "ms": "Kanvas"],
        "table_layout_mode_grid": ["en": "Grid", "th": "กริด", "zh": "网格", "ja": "グリッド", "ko": "그리드", "id": "Grid", "ms": "Grid"],
        // MARK: - Table View Mode
        "table_view_mode_map": ["en": "Map View", "th": "มุมมองแผนผัง", "zh": "地图视图", "ja": "マップ表示", "ko": "지도 보기", "id": "Tampilan Peta", "ms": "Paparan Peta"],
        "table_view_mode_list": ["en": "List View", "th": "มุมมองรายการ", "zh": "列表视图", "ja": "リสต์表示", "ko": "목록 보기", "id": "Tampilan Daftar", "ms": "Paparan Senarai"],
        "table_order_total_template": ["en": "Total: %@", "th": "ยอดรวม: %@", "zh": "总计: %@", "ja": "合計: %@", "ko": "합계: %@", "id": "Total: %@", "ms": "Jumlah: %@"],
        // MARK: - Table Floor Plan Upload
        "table_floor_plan_upload_btn": ["en": "Upload Floor Plan", "th": "อัปโหลดแผนผัง", "zh": "上传平面图", "ja": "フロアプランをアップロード", "ko": "평면도 업로드", "id": "Unggah Denah Lantai", "ms": "Muat Naik Pelan Lantai"],
        "table_floor_plan_remove_btn": ["en": "Remove Image", "th": "ลบรูปภาพ", "zh": "删除图片", "ja": "画像を削除", "ko": "이미지 삭제", "id": "Hapus Gambar", "ms": "Buang Gambar"],
        // MARK: - Table Shape Extended
        "table_shape_square": ["en": "Square", "th": "สี่เหลี่ยมจัตุรัส", "zh": "正方形", "ja": "正方形", "ko": "정사각형", "id": "Persegi", "ms": "Segi Empat Sama"],
        "table_shape_oval": ["en": "Oval", "th": "วงรี", "zh": "椭圆形", "ja": "楕円形", "ko": "타원형", "id": "Oval", "ms": "Bujur"],
        "table_shape_circle": ["en": "Circle", "th": "วงกลม", "zh": "圆形", "ja": "円形", "ko": "원형", "id": "Lingkaran", "ms": "Bulatan"],
        // MARK: - Table Floor Management
        "table_floor_add_btn": ["en": "Add Floor", "th": "เพิ่มชั้น", "zh": "添加楼层", "ja": "フロア追加", "ko": "층 추가", "id": "Tambah Lantai", "ms": "Tambah Lantai"],
        "table_floor_remove_btn": ["en": "Remove Floor", "th": "ลบชั้น", "zh": "删除楼层", "ja": "フロア削除", "ko": "층 삭제", "id": "Hapus Lantai", "ms": "Buang Lantai"],
        "table_floor_save_btn": ["en": "Save Floors", "th": "บันทึกชั้น", "zh": "保存楼层", "ja": "保存", "ko": "저장", "id": "Simpan Lantai", "ms": "Simpan Lantai"],
        "table_floor_new_name": ["en": "Floor %d", "th": "ชั้น %d", "zh": "%d楼", "ja": "%d階", "ko": "%d층", "id": "Lantai %d", "ms": "Lantai %d"],
        "table_floor_rename_title": ["en": "Rename Floor", "th": "เปลี่ยนชื่อชั้น", "zh": "重命名楼层", "ja": "フロア名変更", "ko": "층 이름 변경", "id": "Ubah Nama Lantai", "ms": "Namakan Semula Lantai"],
        "table_floor_remove_confirm": ["en": "Remove this floor and all its tables?", "th": "ลบชั้นนี้และโต๊ะทั้งหมด?", "zh": "删除此楼层及所有桌位？", "ja": "このフロアとすべてのテーブルを削除しますか？", "ko": "이 층과 모든 테이블을 삭제하시겠습니까?", "id": "Hapus lantai ini beserta semua mejanya?", "ms": "Buang lantai ini dan semua mejanya?"],
        // MARK: - Table Background & Presets Localization
        "table_bg_adjust_title": ["en": "Adjust Background", "th": "ปรับแต่งรูปพื้นหลัง", "zh": "调整背景", "ja": "背景調整", "ko": "배경 조정", "id": "Sesuaikan Latar", "ms": "Laraskan Latar"],
        "table_bg_scale_label": ["en": "Zoom", "th": "ย่อขยาย", "zh": "缩放", "ja": "ズーム", "ko": "줌", "id": "Zoom", "ms": "Zon"],
        "table_bg_x_label": ["en": "Offset X", "th": "แกน X", "zh": "偏移 X", "ja": "オフセット X", "ko": "오프셋 X", "id": "Ofset X", "ms": "Ofset X"],
        "table_bg_y_label": ["en": "Offset Y", "th": "แกน Y", "zh": "偏移 Y", "ja": "オフセット Y", "ko": "오ฟเซ็ต Y", "id": "Ofset Y", "ms": "Ofset Y"],
        "table_presets_title": ["en": "Layout Templates", "th": "รูปแบบจัดโต๊ะ", "zh": "布局预设", "ja": "レイアウトプリセット", "ko": "레이아웃 프리셋", "id": "Preset Tata Letak", "ms": "Preset Reka Letak"],
        "table_presets_save_alert": ["en": "Save Current Layout", "th": "บันทึกรูปแบบการจัดโต๊ะ", "zh": "保存当前布局", "ja": "現在のレイアウトを保存", "ko": "현재 레이아웃 저장", "id": "Simpan Tata Letak", "ms": "Simpan Reka Letak"],
        "table_presets_enter_name": ["en": "Enter template name (e.g. Layout A)", "th": "กรอกชื่อรูปแบบ (เช่น รูปแบบ A)", "zh": "输入预设名称 (例如 布局 A)", "ja": "プリセット名を入力 (例: レイアウト A)", "ko": "프리셋 이름 입력 (예: ...)", "id": "Masukkan nama preset", "ms": "Masukkan nama preset"],
        "table_presets_delete_confirm": ["en": "Delete this layout template?", "th": "ลบรูปแบบการจัดโต๊ะนี้?", "zh": "删除此布局预设？", "ja": "このプリセットを削除しますか？", "ko": "이 레이아웃 프리셋을 삭제하시겠습니까?", "id": "Hapus preset ini?", "ms": "Buang preset ini?"],
        // MARK: - Table List Summary Bar
        "table_list_total": ["en": "Total Tables: %d", "th": "โต๊ะทั้งหมด: %d", "zh": "总桌位: %d", "ja": "総テーブル: %d", "ko": "전체 테이블: %d", "id": "Total Meja: %d", "ms": "Jumlah Meja: %d"],
        "table_list_available": ["en": "Available: %d", "th": "ว่าง: %d", "zh": "可用: %d", "ja": "空席: %d", "ko": "이용 가능: %d", "id": "Tersedia: %d", "ms": "Tersedia: %d"],
        "table_list_occupied": ["en": "Occupied: %d", "th": "มีลูกค้า: %d", "zh": "已占用: %d", "ja": "使用中: %d", "ko": "사용 중: %d", "id": "Terisi: %d", "ms": "Terisi: %d"],
        "table_list_reserved": ["en": "Reserved: %d", "th": "จองแล้ว: %d", "zh": "已预订: %d", "ja": "予約済: %d", "ko": "예약됨: %d", "id": "Dipesan: %d", "ms": "Ditempah: %d"],
        "table_list_with_orders": ["en": "With Orders: %d", "th": "มีออเดอร์: %d", "zh": "有订单: %d", "ja": "注文あり: %d", "ko": "주문 있음: %d", "id": "Dengan Pesanan: %d", "ms": "Dengan Pesanan: %d"],
        "table_list_total_seats": ["en": "Total Seats: %d", "th": "ที่นั่งรวม: %d", "zh": "总座位: %d", "ja": "総席数: %d", "ko": "전체 좌석: %d", "id": "Total Kursi: %d", "ms": "Jumlah Kerusi: %d"],
        "table_list_tip": ["en": "Tip: click a table row to view orders.", "th": "แตะแถวโต๊ะเพื่อดูออเดอร์", "zh": "提示：点击行查看订单", "ja": "ヒント：行をタップして注文を確認", "ko": "팁: 행을 눌러 주문 확인", "id": "Tips: klik baris untuk melihat pesanan.", "ms": "Tip: klik baris untuk lihat pesanan."],
        "table_list_col_table": ["en": "Table", "th": "โต๊ะ", "zh": "桌位", "ja": "テーブル", "ko": "테이블", "id": "Meja", "ms": "Meja"],
        "table_list_col_seats": ["en": "Seats", "th": "ที่นั่ง", "zh": "座位", "ja": "席数", "ko": "좌석", "id": "Kursi", "ms": "Kerusi"],
        "table_list_col_shape": ["en": "Shape", "th": "รูปร่าง", "zh": "形状", "ja": "形状", "ko": "모양", "id": "Bentuk", "ms": "Bentuk"],
        "table_list_col_status": ["en": "Status", "th": "สถานะ", "zh": "状态", "ja": "状態", "ko": "상태", "id": "Status", "ms": "Status"],
        "table_list_col_qr": ["en": "QR Code", "th": "คิวอาร์", "zh": "二维码", "ja": "QRコード", "ko": "QR코드", "id": "Kode QR", "ms": "Kod QR"],
        "table_list_col_total": ["en": "Total", "th": "ยอดรวม", "zh": "总计", "ja": "合計", "ko": "합계", "id": "Total", "ms": "Jumlah"],
        "table_status_available": ["en": "Available", "th": "ว่าง", "zh": "可用", "ja": "空席", "ko": "이용가능", "id": "Tersedia", "ms": "Tersedia"],
        // MARK: - Time (restored label)
        "time_minutes": ["en": "minutes", "th": "นาที", "zh": "分钟", "ja": "分", "ko": "분", "id": "menit", "ms": "minit"],
        "overtime_minutes_label": ["en": "Overtime (min)", "th": "ล่วงเวลา (นาที)", "zh": "加班时间 (分钟)", "ja": "残業時間 (分)", "ko": "초과 근무 (분)", "id": "Lembur (menit)", "ms": "Kerja Lebih Masa (minit)"],

        // MARK: - KDS (Kitchen Display)
        "kds_active_timer_template": ["en": "Active: %@ min", "th": "ใช้งาน: %@ นาที", "zh": "活跃: %@ 分钟", "ja": "アクティブ: %@ 分", "ko": "활성: %@ 분", "id": "Aktif: %@ menit", "ms": "Aktif: %@ minit"],
        "kds_alert_staff": ["en": "Alert Staff", "th": "แจ้งพนักงาน", "zh": "通知员工", "ja": "スタッフに通知", "ko": "직원 알림", "id": "Panggil Staf", "ms": "Maklumkan Staf"],
        "kds_all_completed": ["en": "All Completed", "th": "เสร็จทั้งหมด", "zh": "全部完成", "ja": "全て完了", "ko": "모두 완료", "id": "Semua Selesai", "ms": "Semua Selesai"],
        "kds_all_done": ["en": "All Done", "th": "เสร็จหมดแล้ว", "zh": "全部完成", "ja": "全て完了", "ko": "모두 완료", "id": "Semua Selesai", "ms": "Semua Selesai"],
        "kds_all_station_completed": ["en": "All Stations Completed", "th": "ทุกสถานีเสร็จแล้ว", "zh": "所有站点已完成", "ja": "全ステーション完了", "ko": "모든 스테이션 완료", "id": "Semua Stasiun Selesai", "ms": "Semua Stesen Selesai"],
        "kds_auto_complete_enabled": ["en": "Auto-Complete Enabled", "th": "เปิดเสร็จอัตโนมัติ", "zh": "自动完成已启用", "ja": "自動完了有効", "ko": "자동 완료 활성화", "id": "Auto-Selesai Aktif", "ms": "Auto-Selesai Aktif"],
        "kds_cancelled": ["en": "Cancelled", "th": "ยกเลิก", "zh": "已取消", "ja": "キャンセル", "ko": "취소됨", "id": "Dibatalkan", "ms": "Dibatalkan"],
        "kds_clear_delivered": ["en": "Clear Delivered", "th": "ล้างที่เสิร์ฟแล้ว", "zh": "清除已送达", "ja": "配膳済みをクリア", "ko": "배달 완료 지우기", "id": "Hapus Terkirim", "ms": "Kosongkan Dihantar"],
        "kds_delayed_pill": ["en": "Delayed", "th": "ล่าช้า", "zh": "延迟", "ja": "遅延", "ko": "지연됨", "id": "Tertunda", "ms": "Tertangguh"],
        "kds_dismiss_ticket_hint": ["en": "Swipe to dismiss ticket", "th": "ปัดเพื่อปิดตั๋ว", "zh": "滑动关闭票据", "ja": "スワイプでチケットを閉じる", "ko": "스와이프하여 티켓 닫기", "id": "Geser untuk tutup tiket", "ms": "Leret untuk tutup tiket"],
        "kds_help_button": ["en": "Help", "th": "ช่วยเหลือ", "zh": "帮助", "ja": "ヘルプ", "ko": "도움말", "id": "Bantuan", "ms": "Bantuan"],
        "kds_help_nav_title": ["en": "KDS Help", "th": "วิธีใช้ KDS", "zh": "KDS 帮助", "ja": "KDS ヘルプ", "ko": "KDS 도움말", "id": "Bantuan KDS", "ms": "Bantuan KDS"],
        "kds_help_sec1_bullet1": ["en": "Tap an order card to split it into individual items", "th": "แตะบัตรออเดอร์เพื่อแยกเป็นรายการ", "zh": "点击订单卡可拆分为单项", "ja": "注文カードをタップして個別アイテムに分割", "ko": "주문 카드를 탭하여 개별 항목으로 분리", "id": "Ketuk kartu pesanan untuk memisahkan item", "ms": "Ketik kad pesanan untuk pisahkan item"],
        "kds_help_sec1_bullet2": ["en": "Each item can be marked ready independently", "th": "แต่ละรายการสามารถทำเครื่องหมายเสร็จแยกกันได้", "zh": "每个商品可独立标记为就绪", "ja": "各アイテムを個別に完了マーク可能", "ko": "각 항목을 독립적으로 준비 완료 표시 가능", "id": "Setiap item bisa ditandai siap secara terpisah", "ms": "Setiap item boleh ditanda sedia secara berasingan"],
        "kds_help_sec1_desc": ["en": "Split order cards to manage individual items", "th": "แยกบัตรออเดอร์เพื่อจัดการแต่ละรายการ", "zh": "拆分订单卡管理单个商品", "ja": "注文カードを分割して個別管理", "ko": "주문 카드를 분할하여 개별 관리", "id": "Pisahkan kartu pesanan untuk kelola item", "ms": "Pisahkan kad pesanan untuk urus item"],
        "kds_help_sec1_title": ["en": "Splitting Cards", "th": "การแยกบัตร", "zh": "拆分卡片", "ja": "カード分割", "ko": "카드 분할", "id": "Memisahkan Kartu", "ms": "Memisahkan Kad"],
        "kds_help_sec2_bullet1": ["en": "Green: New order just received", "th": "สีเขียว: ออเดอร์ใหม่เข้า", "zh": "绿色: 刚收到新订单", "ja": "緑: 新規注文受付", "ko": "초록: 새 주문 접수", "id": "Hijau: Pesanan baru diterima", "ms": "Hijau: Pesanan baru diterima"],
        "kds_help_sec2_bullet2": ["en": "Yellow: Order in progress", "th": "สีเหลือง: กำลังทำ", "zh": "黄色: 制作中", "ja": "黄: 調理中", "ko": "노랑: 조리 중", "id": "Kuning: Pesanan diproses", "ms": "Kuning: Pesanan diproses"],
        "kds_help_sec2_bullet3": ["en": "Red: Order delayed", "th": "สีแดง: ล่าช้า", "zh": "红色: 订单延迟", "ja": "赤: 遅延", "ko": "빨강: 주문 지연", "id": "Merah: Pesanan tertunda", "ms": "Merah: Pesanan tertangguh"],
        "kds_help_sec2_desc": ["en": "Colors indicate order urgency and status", "th": "สีแสดงความเร่งด่วนและสถานะ", "zh": "颜色表示订单紧急程度和状态", "ja": "色で注文の緊急度と状態を表示", "ko": "색상으로 주문 긴급도 및 상태 표시", "id": "Warna menunjukkan urgensi dan status", "ms": "Warna menunjukkan keutamaan dan status"],
        "kds_help_sec2_title": ["en": "Color Coding", "th": "รหัสสี", "zh": "颜色编码", "ja": "カラーコード", "ko": "색상 코드", "id": "Kode Warna", "ms": "Kod Warna"],
        "kds_help_sec3_bullet1": ["en": "Tap item to mark as ready", "th": "แตะรายการเพื่อทำเครื่องหมายพร้อม", "zh": "点击商品标记为就绪", "ja": "アイテムをタップして準備完了", "ko": "항목을 탭하여 준비 완료 표시", "id": "Ketuk item untuk tandai siap", "ms": "Ketik item untuk tanda sedia"],
        "kds_help_sec3_bullet2": ["en": "Swipe right to serve entire order", "th": "ปัดขวาเพื่อเสิร์ฟทั้งออเดอร์", "zh": "右滑提交整个订单", "ja": "右スワイプで注文全体を提供", "ko": "오른쪽 스와이프로 전체 주문 서빙", "id": "Geser kanan untuk sajikan pesanan", "ms": "Leret kanan untuk hidang pesanan"],
        "kds_help_sec3_bullet3": ["en": "Long press to alert waiter", "th": "กดค้างเพื่อเรียกพนักงาน", "zh": "长按呼叫服务员", "ja": "長押しでウェイターを呼ぶ", "ko": "길게 눌러 웨이터 호출", "id": "Tekan lama untuk panggil pelayan", "ms": "Tekan lama untuk panggil pelayan"],
        "kds_help_sec3_bullet4": ["en": "Double tap to undo ready status", "th": "แตะสองครั้งเพื่อยกเลิกสถานะพร้อม", "zh": "双击撤销就绪状态", "ja": "ダブルタップで準備完了を取消", "ko": "더블 탭으로 준비 완료 취소", "id": "Ketuk dua kali untuk batalkan status", "ms": "Ketik dua kali untuk batal status"],
        "kds_help_sec3_desc": ["en": "Available actions and gestures", "th": "การกระทำและท่าทางที่ใช้ได้", "zh": "可用操作和手势", "ja": "利用可能なアクションとジェスチャー", "ko": "사용 가능한 동작 및 제스처", "id": "Tindakan dan gestur yang tersedia", "ms": "Tindakan dan gerak isyarat tersedia"],
        "kds_help_sec3_title": ["en": "Controls & Actions", "th": "การควบคุมและการกระทำ", "zh": "控制与操作", "ja": "操作とアクション", "ko": "컨트롤 및 동작", "id": "Kontrol & Tindakan", "ms": "Kawalan & Tindakan"],
        "kds_help_sec4_bullet1": ["en": "Toggle sound alerts on/off", "th": "เปิด/ปิดเสียงเตือน", "zh": "开关声音提醒", "ja": "音声アラートのオン/オフ", "ko": "소리 알림 켜기/끄기", "id": "Aktifkan/nonaktifkan suara", "ms": "Aktif/nyahaktif bunyi"],
        "kds_help_sec4_bullet2": ["en": "Choose between kitchen and bar views", "th": "เลือกมุมมองครัวหรือบาร์", "zh": "选择厨房或吧台视图", "ja": "キッチンまたはバービューを選択", "ko": "주방 또는 바 뷰 선택", "id": "Pilih tampilan dapur atau bar", "ms": "Pilih paparan dapur atau bar"],
        "kds_help_sec4_bullet3": ["en": "Adjust card size (narrow/wide)", "th": "ปรับขนาดบัตร (แคบ/กว้าง)", "zh": "调整卡片大小 (窄/宽)", "ja": "カードサイズ調整 (狭い/広い)", "ko": "카드 크기 조정 (좁게/넓게)", "id": "Sesuaikan ukuran kartu (sempit/lebar)", "ms": "Laraskan saiz kad (sempit/lebar)"],
        "kds_help_sec4_desc": ["en": "Configure your KDS preferences", "th": "ตั้งค่า KDS ตามต้องการ", "zh": "配置您的KDS偏好设置", "ja": "KDS設定をカスタマイズ", "ko": "KDS 환경설정 구성", "id": "Konfigurasi preferensi KDS Anda", "ms": "Konfigurasikan keutamaan KDS anda"],
        "kds_help_sec4_title": ["en": "Settings", "th": "การตั้งค่า", "zh": "设置", "ja": "設定", "ko": "설정", "id": "Pengaturan", "ms": "Tetapan"],
        "kds_help_subtitle": ["en": "Tips for using Kitchen Display System", "th": "เคล็ดลับการใช้ระบบแสดงผลครัว", "zh": "厨房显示系统使用技巧", "ja": "キッチンディスプレイの使い方", "ko": "주방 디스플레이 시스템 사용 팁", "id": "Tips menggunakan Layar Dapur", "ms": "Tips menggunakan Paparan Dapur"],
        "kds_help_title": ["en": "Kitchen Display Help", "th": "วิธีใช้หน้าจอครัว", "zh": "厨房显示帮助", "ja": "キッチンディスプレイ ヘルプ", "ko": "주방 디스플레이 도움말", "id": "Bantuan Layar Dapur", "ms": "Bantuan Paparan Dapur"],
        "kds_mark_bar_ready": ["en": "Bar Ready", "th": "บาร์พร้อม", "zh": "吧台就绪", "ja": "バー準備完了", "ko": "바 준비 완료", "id": "Bar Siap", "ms": "Bar Sedia"],
        "kds_mark_kitchen_ready": ["en": "Kitchen Ready", "th": "ครัวพร้อม", "zh": "厨房就绪", "ja": "キッチン準備完了", "ko": "주방 준비 완료", "id": "Dapur Siap", "ms": "Dapur Sedia"],
        "kds_new_view": ["en": "New View", "th": "มุมมองใหม่", "zh": "新视图", "ja": "新しいビュー", "ko": "새 보기", "id": "Tampilan Baru", "ms": "Paparan Baru"],
        "kds_no_active_tickets": ["en": "No Active Tickets", "th": "ไม่มีตั๋วที่ใช้งาน", "zh": "没有活跃票据", "ja": "アクティブなチケットなし", "ko": "활성 티켓 없음", "id": "Tidak Ada Tiket Aktif", "ms": "Tiada Tiket Aktif"],
        "kds_no_recently_served": ["en": "No Recently Served", "th": "ไม่มีรายการเสิร์ฟล่าสุด", "zh": "没有最近送达的订单", "ja": "最近の提供なし", "ko": "최근 서빙 없음", "id": "Belum Ada yang Disajikan", "ms": "Tiada Hidangan Baru"],
        "kds_original_view": ["en": "Original View", "th": "มุมมองเดิม", "zh": "原始视图", "ja": "オリジナルビュー", "ko": "원래 보기", "id": "Tampilan Asli", "ms": "Paparan Asal"],
        "kds_queue_narrow": ["en": "Narrow", "th": "แคบ", "zh": "窄", "ja": "狭い", "ko": "좁게", "id": "Sempit", "ms": "Sempit"],
        "kds_queue_wide": ["en": "Wide", "th": "กว้าง", "zh": "宽", "ja": "広い", "ko": "넓게", "id": "Lebar", "ms": "Lebar"],
        "kds_recently_served": ["en": "Recently Served", "th": "เสิร์ฟล่าสุด", "zh": "最近送达", "ja": "最近の提供", "ko": "최근 서빙", "id": "Baru Disajikan", "ms": "Baru Dihidang"],
        "kds_request_waiter": ["en": "Request Waiter", "th": "เรียกพนักงาน", "zh": "呼叫服务员", "ja": "ウェイターを呼ぶ", "ko": "웨이터 호출", "id": "Panggil Pelayan", "ms": "Panggil Pelayan"],
        "kds_search_placeholder": ["en": "Search orders...", "th": "ค้นหาออเดอร์...", "zh": "搜索订单...", "ja": "注文を検索...", "ko": "주문 검색...", "id": "Cari pesanan...", "ms": "Cari pesanan..."],
        "kds_serve": ["en": "Serve", "th": "เสิร์ฟ", "zh": "上菜", "ja": "提供", "ko": "서빙", "id": "Sajikan", "ms": "Hidang"],
        "kds_served_at_template": ["en": "Served at %@", "th": "เสิร์ฟเมื่อ %@", "zh": "送达时间 %@", "ja": "提供時刻 %@", "ko": "서빙 시간 %@", "id": "Disajikan pukul %@", "ms": "Dihidang pada %@"],
        "kds_settings_title": ["en": "KDS Settings", "th": "ตั้งค่า KDS", "zh": "KDS 设置", "ja": "KDS 設定", "ko": "KDS 설정", "id": "Pengaturan KDS", "ms": "Tetapan KDS"],
        "kds_show_bar": ["en": "Bar", "th": "บาร์", "zh": "吧台", "ja": "バー", "ko": "바", "id": "Bar", "ms": "Bar"],
        "kds_show_bar_toggle": ["en": "Show Bar Orders", "th": "แสดงออเดอร์บาร์", "zh": "显示吧台订单", "ja": "バー注文を表示", "ko": "바 주문 표시", "id": "Tampilkan Pesanan Bar", "ms": "Papar Pesanan Bar"],
        "kds_show_kitchen": ["en": "Kitchen", "th": "ครัว", "zh": "厨房", "ja": "キッチン", "ko": "주방", "id": "Dapur", "ms": "Dapur"],
        "kds_show_kitchen_toggle": ["en": "Show Kitchen Orders", "th": "แสดงออเดอร์ครัว", "zh": "显示厨房订单", "ja": "キッチン注文を表示", "ko": "주방 주문 표시", "id": "Tampilkan Pesanan Dapur", "ms": "Papar Pesanan Dapur"],
        "kds_sound_enabled": ["en": "Sound Alerts", "th": "เสียงเตือน", "zh": "声音提醒", "ja": "音声アラート", "ko": "소리 알림", "id": "Suara Peringatan", "ms": "Bunyi Amaran"],
        "kds_staff_alerted": ["en": "Staff Alerted", "th": "แจ้งพนักงานแล้ว", "zh": "已通知员工", "ja": "スタッフに通知済み", "ko": "직원에게 알림 완료", "id": "Staf Telah Dipanggil", "ms": "Staf Telah Dimaklumkan"],
        "kds_station_bar": ["en": "bar", "th": "บาร์", "zh": "吧台", "ja": "バー", "ko": "바", "id": "bar", "ms": "bar"],
        "kds_station_bar_upper": ["en": "BAR", "th": "บาร์", "zh": "吧台", "ja": "バー", "ko": "바", "id": "BAR", "ms": "BAR"],
        "kds_station_kitchen": ["en": "kitchen", "th": "ครัว", "zh": "厨房", "ja": "キッチン", "ko": "주방", "id": "dapur", "ms": "dapur"],
        "kds_station_kitchen_upper": ["en": "KITCHEN", "th": "ครัว", "zh": "厨房", "ja": "キッチン", "ko": "주방", "id": "DAPUR", "ms": "DAPUR"],
        "kds_station_selector_acc": ["en": "Station Selector", "th": "เลือกสถานี", "zh": "选择站点", "ja": "ステーション選択", "ko": "스테이션 선택", "id": "Pilih Stasiun", "ms": "Pilih Stesen"],
        "kds_view_style": ["en": "View Style", "th": "รูปแบบมุมมอง", "zh": "视图样式", "ja": "表示スタイル", "ko": "보기 스타일", "id": "Gaya Tampilan", "ms": "Gaya Paparan"],
        "kitchen_printer_enabled": ["en": "Kitchen Printer Enabled", "th": "เปิดเครื่องพิมพ์ครัว", "zh": "厨房打印机已启用", "ja": "キッチンプリンター有効", "ko": "주방 프린터 활성화", "id": "Printer Dapur Aktif", "ms": "Pencetak Dapur Aktif"],
        "kitchen_workflow_required": ["en": "Kitchen Workflow Required", "th": "ต้องใช้ขั้นตอนครัว", "zh": "需要厨房工作流程", "ja": "キッチンワークフロー必須", "ko": "주방 워크플로우 필요", "id": "Alur Kerja Dapur Diperlukan", "ms": "Aliran Kerja Dapur Diperlukan"],
        "kpi_avg_ticket": ["en": "Avg. Ticket", "th": "เฉลี่ย/บิล", "zh": "平均客单", "ja": "平均客単価", "ko": "평균 객단가", "id": "Rata-rata Tiket", "ms": "Purata Tiket"],
        "kpi_items_sold": ["en": "Items Sold", "th": "ขายได้", "zh": "售出数量", "ja": "販売数", "ko": "판매 수량", "id": "Item Terjual", "ms": "Item Terjual"],
        "kpi_tax_collected": ["en": "Tax Collected", "th": "ภาษีที่เก็บได้", "zh": "已收税额", "ja": "徴収税額", "ko": "징수 세금", "id": "Pajak Terkumpul", "ms": "Cukai Dikutip"],
        "kpi_total_orders": ["en": "Total Orders", "th": "ออเดอร์ทั้งหมด", "zh": "总订单数", "ja": "注文合計", "ko": "총 주문", "id": "Total Pesanan", "ms": "Jumlah Pesanan"],
        "kpi_total_revenue": ["en": "Total Revenue", "th": "รายได้ทั้งหมด", "zh": "总收入", "ja": "総売上", "ko": "총 매출", "id": "Total Pendapatan", "ms": "Jumlah Hasil"],
        // MARK: - POS
        "pos_all_items": ["en": "All Items", "th": "ทุกรายการ", "zh": "全部商品", "ja": "全商品", "ko": "전체 상품", "id": "Semua Item", "ms": "Semua Item"],
        "pos_amount_missing": ["en": "Amount Missing", "th": "จำนวนเงินไม่ครบ", "zh": "金额不足", "ja": "不足金額", "ko": "부족 금액", "id": "Jumlah Kurang", "ms": "Jumlah Kurang"],
        "pos_bill_no": ["en": "Bill No.", "th": "บิลที่", "zh": "账单号", "ja": "伝票番号", "ko": "청구서 번호", "id": "No. Tagihan", "ms": "No. Bil"],
        "pos_card": ["en": "Card", "th": "บัตร", "zh": "刷卡", "ja": "カード", "ko": "카드", "id": "Kartu", "ms": "Kad"],
        "pos_cart_empty": ["en": "Cart is Empty", "th": "ตะกร้าว่าง", "zh": "购物车为空", "ja": "カートが空です", "ko": "장바구니가 비어있습니다", "id": "Keranjang Kosong", "ms": "Troli Kosong"],
        "pos_cash": ["en": "Cash", "th": "เงินสด", "zh": "现金", "ja": "現金", "ko": "현금", "id": "Tunai", "ms": "Tunai"],
        "pos_cashier": ["en": "Cashier", "th": "แคชเชียร์", "zh": "收银员", "ja": "レジ担当", "ko": "캐셔", "id": "Kasir", "ms": "Juruwang"],
        "pos_category_all": ["en": "All", "th": "ทั้งหมด", "zh": "全部", "ja": "全て", "ko": "전체", "id": "Semua", "ms": "Semua"],
        "pos_change_due": ["en": "Change Due", "th": "เงินทอน", "zh": "找零", "ja": "お釣り", "ko": "거스름돈", "id": "Kembalian", "ms": "Baki"],
        "pos_clear": ["en": "Clear", "th": "ล้าง", "zh": "清除", "ja": "クリア", "ko": "지우기", "id": "Hapus", "ms": "Kosongkan"],
        "pos_current_cart": ["en": "Current Cart", "th": "ตะกร้าปัจจุบัน", "zh": "当前购物车", "ja": "現在のカート", "ko": "현재 장바구니", "id": "Keranjang Saat Ini", "ms": "Troli Semasa"],
        "pos_delivery": ["en": "Delivery", "th": "เดลิเวอรี่", "zh": "外送", "ja": "デリバリー", "ko": "배달", "id": "Delivery", "ms": "Penghantaran"],
        "pos_dine_in": ["en": "Dine In", "th": "ทานที่ร้าน", "zh": "堂食", "ja": "店内", "ko": "매장 식사", "id": "Makan di Tempat", "ms": "Makan di Sini"],
        "pos_discount": ["en": "Discount", "th": "ส่วนลด", "zh": "折扣", "ja": "割引", "ko": "할인", "id": "Diskon", "ms": "Diskaun"],
        "pos_favorites": ["en": "Favorites", "th": "รายการโปรด", "zh": "收藏", "ja": "お気に入り", "ko": "즐겨찾기", "id": "Favorit", "ms": "Kegemaran"],
        "pos_hold": ["en": "Hold", "th": "พักออเดอร์", "zh": "挂起", "ja": "保留", "ko": "보류", "id": "Tahan", "ms": "Tahan"],
        "pos_instructions_hint": ["en": "Special instructions...", "th": "คำสั่งพิเศษ...", "zh": "特殊要求...", "ja": "特別な指示...", "ko": "특별 요청...", "id": "Instruksi khusus...", "ms": "Arahan khas..."],
        "pos_no_change_due": ["en": "No Change Due", "th": "ไม่มีเงินทอน", "zh": "无需找零", "ja": "お釣りなし", "ko": "거스름돈 없음", "id": "Tidak Ada Kembalian", "ms": "Tiada Baki"],
        "pos_no_menu_items_subtitle": ["en": "Add items in Catalog to get started", "th": "เพิ่มรายการในแคตตาล็อกเพื่อเริ่มต้น", "zh": "在目录中添加商品以开始", "ja": "カタログに商品を追加して始めましょう", "ko": "카탈로그에 상품을 추가하여 시작하세요", "id": "Tambahkan item di Katalog untuk memulai", "ms": "Tambah item di Katalog untuk bermula"],
        "pos_no_menu_items_title": ["en": "No Menu Items", "th": "ไม่มีรายการเมนู", "zh": "没有菜单项", "ja": "メニュー商品がありません", "ko": "메뉴 항목 없음", "id": "Tidak Ada Item Menu", "ms": "Tiada Item Menu"],
        "pos_order_number": ["en": "Order #", "th": "ออเดอร์ #", "zh": "订单 #", "ja": "注文 #", "ko": "주문 #", "id": "Pesanan #", "ms": "Pesanan #"],
        "pos_out_of_stock": ["en": "Out of Stock", "th": "สินค้าหมด", "zh": "缺货", "ja": "在庫切れ", "ko": "품절", "id": "Stok Habis", "ms": "Stok Habis"],
        "pos_payment_successful": ["en": "Payment Successful", "th": "ชำระเงินสำเร็จ", "zh": "支付成功", "ja": "支払い完了", "ko": "결제 성공", "id": "Pembayaran Berhasil", "ms": "Pembayaran Berjaya"],
        "pos_pending_confirmation": ["en": "Pending Confirmation", "th": "รอยืนยัน", "zh": "待确认", "ja": "確認待ち", "ko": "확인 대기 중", "id": "Menunggu Konfirmasi", "ms": "Menunggu Pengesahan"],
        "pos_qr_code": ["en": "QR Code", "th": "คิวอาร์โค้ด", "zh": "二维码", "ja": "QRコード", "ko": "QR 코드", "id": "Kode QR", "ms": "Kod QR"],
        "pos_quick_cash": ["en": "Quick Cash", "th": "เงินสดด่วน", "zh": "快捷现金", "ja": "クイックキャッシュ", "ko": "빠른 현금", "id": "Tunai Cepat", "ms": "Tunai Pantas"],
        "pos_ready_for_payment": ["en": "Ready for Payment", "th": "พร้อมชำระ", "zh": "待支付", "ja": "支払い準備完了", "ko": "결제 준비 완료", "id": "Siap Bayar", "ms": "Sedia untuk Bayaran"],
        "pos_recall": ["en": "Recall", "th": "เรียกคืน", "zh": "调回", "ja": "呼出", "ko": "불러오기", "id": "Panggil Kembali", "ms": "Panggil Semula"],
        "pos_refund": ["en": "Refund", "th": "คืนเงิน", "zh": "退款", "ja": "返金", "ko": "환불", "id": "Refund", "ms": "Bayaran Balik"],
        "pos_select_table_subtitle": ["en": "Choose a table for this order", "th": "เลือกโต๊ะสำหรับออเดอร์นี้", "zh": "为此订单选择桌位", "ja": "この注文のテーブルを選択", "ko": "이 주문의 테이블을 선택하세요", "id": "Pilih meja untuk pesanan ini", "ms": "Pilih meja untuk pesanan ini"],
        "pos_select_table_title": ["en": "Select Table", "th": "เลือกโต๊ะ", "zh": "选择桌位", "ja": "テーブル選択", "ko": "테이블 선택", "id": "Pilih Meja", "ms": "Pilih Meja"],
        "pos_served": ["en": "Served", "th": "เสิร์ฟแล้ว", "zh": "已上菜", "ja": "提供済み", "ko": "서빙 완료", "id": "Disajikan", "ms": "Dihidang"],
        "pos_service_charge": ["en": "Service Charge", "th": "ค่าบริการ", "zh": "服务费", "ja": "サービス料", "ko": "서비스 요금", "id": "Biaya Layanan", "ms": "Caj Perkhidmatan"],
        "pos_shift_required_hint": ["en": "Please start a shift to use POS", "th": "กรุณาเปิดกะก่อนใช้ POS", "zh": "请先开始班次再使用POS", "ja": "POSを使用するにはシフトを開始してください", "ko": "POS를 사용하려면 교대를 시작하세요", "id": "Silakan mulai shift untuk menggunakan POS", "ms": "Sila mulakan syif untuk guna POS"],
        "pos_split_pay": ["en": "Split Payment", "th": "แบ่งจ่าย", "zh": "分单支付", "ja": "分割払い", "ko": "분할 결제", "id": "Pembayaran Terpisah", "ms": "Pembayaran Berasingan"],
        "pos_subtotal": ["en": "Subtotal", "th": "รวมย่อย", "zh": "小计", "ja": "小計", "ko": "소계", "id": "Subtotal", "ms": "Jumlah Kecil"],
        "pos_table_number": ["en": "Table No.", "th": "โต๊ะที่", "zh": "桌号", "ja": "テーブル番号", "ko": "테이블 번호", "id": "No. Meja", "ms": "No. Meja"],
        "pos_take_out": ["en": "Take Out", "th": "สั่งกลับบ้าน", "zh": "外带", "ja": "テイクアウト", "ko": "포장", "id": "Bawa Pulang", "ms": "Bungkus"],
        "pos_tip": ["en": "Tip", "th": "ทิป", "zh": "小费", "ja": "チップ", "ko": "팁", "id": "Tip", "ms": "Tip"],
        "pos_total": ["en": "Total", "th": "รวมทั้งหมด", "zh": "合计", "ja": "合計", "ko": "합계", "id": "Total", "ms": "Jumlah"],
        "pos_total_amount": ["en": "Total Amount", "th": "ยอดรวมทั้งหมด", "zh": "总金额", "ja": "合計金額", "ko": "총 금액", "id": "Jumlah Total", "ms": "Jumlah Keseluruhan"],
        "pos_vat": ["en": "VAT", "th": "ภาษีมูลค่าเพิ่ม", "zh": "增值税", "ja": "消費税", "ko": "부가세", "id": "PPN", "ms": "GST"],
        // MARK: - Table Management
        "table_management_title": ["en": "Table Management", "th": "ระบบจัดการโต๊ะ", "zh": "桌台管理", "ja": "テーブル管理", "ko": "테이블 관리", "id": "Manajemen Meja", "ms": "Pengurusan Meja"],
        "table_back_to_login": ["en": "Back to Profiles", "th": "กลับหน้าโปรไฟล์", "zh": "返回个人资料", "ja": "プロフィールに戻る", "ko": "프로필로 돌아가기", "id": "Kembali ke Profil", "ms": "Kembali ke Profil"],
        "table_actions_title": ["en": "Table Actions", "th": "จัดการโต๊ะ", "zh": "桌位操作", "ja": "テーブル操作", "ko": "테이블 작업", "id": "Aksi Meja", "ms": "Tindakan Meja"],
        "table_active_dining_session": ["en": "Active Dining Session", "th": "เซสชันทานอาหารที่ใช้งาน", "zh": "活跃用餐中", "ja": "アクティブな食事セッション", "ko": "활성 식사 세션", "id": "Sesi Makan Aktif", "ms": "Sesi Makan Aktif"],
        "table_add_new_title": ["en": "Add New Table", "th": "เพิ่มโต๊ะใหม่", "zh": "添加新桌", "ja": "新しいテーブルを追加", "ko": "새 테이블 추가", "id": "Tambah Meja Baru", "ms": "Tambah Meja Baru"],
        "table_capacity_lbl": ["en": "Capacity", "th": "ที่นั่ง", "zh": "座位数", "ja": "席数", "ko": "좌석 수", "id": "Kapasitas", "ms": "Kapasiti"],
        "table_chair_layout_lbl": ["en": "Chair Layout", "th": "รูปแบบเก้าอี้", "zh": "椅子布局", "ja": "椅子配置", "ko": "의자 배치", "id": "Tata Kursi", "ms": "Susun Atur Kerusi"],
        "table_checkout_btn": ["en": "Checkout", "th": "เช็คบิล", "zh": "结账", "ja": "会計", "ko": "계산", "id": "Checkout", "ms": "Daftar Keluar"],
        "table_combine_with_btn": ["en": "Combine With", "th": "รวมกับ", "zh": "合并", "ja": "結合", "ko": "합치기", "id": "Gabungkan Dengan", "ms": "Gabung Dengan"],
        "table_combined_group_template": ["en": "T%@ (Group)", "th": "T%@ (กลุ่ม)", "zh": "T%@ (组)", "ja": "T%@ (グループ)", "ko": "T%@ (그룹)", "id": "T%@ (Grup)", "ms": "T%@ (Kumpulan)"],
        "table_combined_with_template": ["en": "Combined with T%@", "th": "รวมกับ T%@", "zh": "已合并至 T%@", "ja": "T%@ と結合中", "ko": "T%@와 합석 중", "id": "Digabung dengan T%@", "ms": "Digabung dengan T%@"],
        "table_create_btn": ["en": "Create Table", "th": "สร้างโต๊ะ", "zh": "创建桌位", "ja": "テーブル作成", "ko": "테이블 만들기", "id": "Buat Meja", "ms": "Cipta Meja"],
        "table_delete_btn": ["en": "Delete Table", "th": "ลบโต๊ะ", "zh": "删除桌位", "ja": "テーブル削除", "ko": "테이블 삭제", "id": "Hapus Meja", "ms": "Padam Meja"],
        "table_details_title": ["en": "Table Details", "th": "รายละเอียดโต๊ะ", "zh": "桌位详情", "ja": "テーブル詳細", "ko": "테이블 상세", "id": "Detail Meja", "ms": "Butiran Meja"],
        "table_draw_exit_btn": ["en": "Exit Draw Mode", "th": "ออกจากโหมดวาด", "zh": "退出绘制模式", "ja": "描画モード終了", "ko": "그리기 모드 종료", "id": "Keluar Mode Gambar", "ms": "Keluar Mod Lukis"],
        "table_draw_walls_btn": ["en": "Draw Walls", "th": "วาดผนัง", "zh": "绘制墙壁", "ja": "壁を描画", "ko": "벽 그리기", "id": "Gambar Dinding", "ms": "Lukis Dinding"],
        "table_draw_tool_wall": ["en": "Straight Wall", "th": "วาดผนังตรง", "zh": "直墙", "ja": "直線壁", "ko": "직선 벽", "id": "Dinding Lurus", "ms": "Dinding Lurus"],
        "table_draw_tool_curve": ["en": "Curved Wall", "th": "วาดผนังโค้ง", "zh": "弧形墙", "ja": "曲線壁", "ko": "곡선 벽", "id": "Dinding Lengkung", "ms": "Dinding Lengkung"],
        "table_draw_tool_eraser": ["en": "Eraser", "th": "ยางลบ", "zh": "橡皮擦", "ja": "消しゴム", "ko": "지우개", "id": "Penghapus", "ms": "Pemadam"],
        "table_empty_canvas_subtitle": ["en": "Tap + to add your first table", "th": "แตะ + เพื่อเพิ่มโต๊ะแรก", "zh": "点击 + 添加第一张桌子", "ja": "タップ + で最初のテーブルを追加", "ko": "+ 를 탭하여 첫 번째 테이블 추가", "id": "Ketuk + untuk tambah meja pertama", "ms": "Ketik + untuk tambah meja pertama"],
        "table_empty_canvas_title": ["en": "No Tables Yet", "th": "ยังไม่มีโต๊ะ", "zh": "还没有桌位", "ja": "テーブルがありません", "ko": "아직 테이블이 없습니다", "id": "Belum Ada Meja", "ms": "Belum Ada Meja"],
        "table_enter_edit_mode_acc": ["en": "Enter Edit Mode", "th": "เข้าสู่โหมดแก้ไข", "zh": "进入编辑模式", "ja": "編集モードに入る", "ko": "편집 모드 진입", "id": "Masuk Mode Edit", "ms": "Masuk Mod Edit"],
        "table_error_empty_number": ["en": "Table number cannot be empty", "th": "หมายเลขโต๊ะต้องไม่ว่าง", "zh": "桌号不能为空", "ja": "テーブル番号は空にできません", "ko": "테이블 번호는 비워둘 수 없습니다", "id": "Nomor meja tidak boleh kosong", "ms": "Nombor meja tidak boleh kosong"],
        "table_error_invalid_capacity": ["en": "Invalid capacity", "th": "จำนวนที่นั่งไม่ถูกต้อง", "zh": "座位数无效", "ja": "席数が無効です", "ko": "잘못된 좌석 수", "id": "Kapasitas tidak valid", "ms": "Kapasiti tidak sah"],
        "table_exit_edit_mode_acc": ["en": "Exit Edit Mode", "th": "ออกจากโหมดแก้ไข", "zh": "退出编辑模式", "ja": "編集モードを終了", "ko": "편집 모드 종료", "id": "Keluar Mode Edit", "ms": "Keluar Mod Edit"],
        "table_find_item_template": ["en": "T%@ (%@ seats)", "th": "T%@ (%@ ที่นั่ง)", "zh": "T%@ (%@ 座)", "ja": "T%@ (%@ 席)", "ko": "T%@ (%@ 석)", "id": "T%@ (%@ kursi)", "ms": "T%@ (%@ kerusi)"],
        "table_grouping_title": ["en": "Table Grouping", "th": "จัดกลุ่มโต๊ะ", "zh": "桌位分组", "ja": "テーブルグループ", "ko": "테이블 그룹", "id": "Pengelompokan Meja", "ms": "Pengelompokan Meja"],
        "table_initial_status_lbl": ["en": "Initial Status", "th": "สถานะเริ่มต้น", "zh": "初始状态", "ja": "初期ステータス", "ko": "초기 상태", "id": "Status Awal", "ms": "Status Awal"],
        "table_joined_to_template": ["en": "Joined to T%@", "th": "รวมกับ T%@", "zh": "合并至 T%@", "ja": "T%@ に結合", "ko": "T%@에 합석", "id": "Digabung ke T%@", "ms": "Digabung ke T%@"],
        "table_label": ["en": "Table", "th": "โต๊ะ", "zh": "桌位", "ja": "テーブル", "ko": "테이블", "id": "Meja", "ms": "Meja"],
        "table_leader_badge": ["en": "Leader", "th": "หัวโต๊ะ", "zh": "主桌", "ja": "リーダー", "ko": "리더", "id": "Utama", "ms": "Utama"],
        "table_no_vacant_combine_hint": ["en": "No vacant tables available to combine", "th": "ไม่มีโต๊ะว่างสำหรับรวม", "zh": "没有空桌可合并", "ja": "結合可能な空席テーブルなし", "ko": "합칠 수 있는 빈 테이블 없음", "id": "Tidak ada meja kosong untuk digabung", "ms": "Tiada meja kosong untuk digabung"],
        "table_number": ["en": "Table Number", "th": "หมายเลขโต๊ะ", "zh": "桌号", "ja": "テーブル番号", "ko": "테이블 번호", "id": "Nomor Meja", "ms": "Nombor Meja"],
        "table_number_name_hint": ["en": "e.g. T1, VIP 1, Patio 3", "th": "เช่น T1, VIP 1, ระเบียง 3", "zh": "如 T1、VIP 1、露台 3", "ja": "例: T1, VIP 1, テラス 3", "ko": "예: T1, VIP 1, 테라스 3", "id": "cth. T1, VIP 1, Teras 3", "ms": "cth. T1, VIP 1, Teres 3"],
        "table_number_name_lbl": ["en": "Table Name/Number", "th": "ชื่อ/หมายเลขโต๊ะ", "zh": "桌名/桌号", "ja": "テーブル名/番号", "ko": "테이블 이름/번호", "id": "Nama/Nomor Meja", "ms": "Nama/Nombor Meja"],
        "table_number_name_placeholder": ["en": "Enter table name or number", "th": "ใส่ชื่อหรือหมายเลขโต๊ะ", "zh": "输入桌名或桌号", "ja": "テーブル名または番号を入力", "ko": "테이블 이름 또는 번호 입력", "id": "Masukkan nama atau nomor meja", "ms": "Masukkan nama atau nombor meja"],
        "table_number_template": ["en": "Table %@", "th": "โต๊ะ %@", "zh": "桌 %@", "ja": "テーブル %@", "ko": "테이블 %@", "id": "Meja %@", "ms": "Meja %@"],
        "table_place_order_btn": ["en": "Place Order", "th": "สั่งอาหาร", "zh": "下单", "ja": "注文する", "ko": "주문하기", "id": "Pesan", "ms": "Buat Pesanan"],
        "table_preview_lbl": ["en": "Preview", "th": "ตัวอย่าง", "zh": "预览", "ja": "プレビュー", "ko": "미리보기", "id": "Pratinjau", "ms": "Pratonton"],
        "table_qr_all_codes_title": ["en": "All QR Codes", "th": "คิวอาร์โค้ดทั้งหมด", "zh": "所有二维码", "ja": "全QRコード", "ko": "모든 QR 코드", "id": "Semua Kode QR", "ms": "Semua Kod QR"],
        "table_qr_copy_link_btn": ["en": "Copy Link", "th": "คัดลอกลิงก์", "zh": "复制链接", "ja": "リンクをコピー", "ko": "링크 복사", "id": "Salin Tautan", "ms": "Salin Pautan"],
        "table_qr_export_pdf_btn": ["en": "Export PDF", "th": "ส่งออก PDF", "zh": "导出 PDF", "ja": "PDF エクスポート", "ko": "PDF 내보내기", "id": "Ekspor PDF", "ms": "Eksport PDF"],
        "table_qr_grid_preview_hint": ["en": "Preview of QR code grid layout", "th": "ตัวอย่างเลย์เอาต์กริดคิวอาร์โค้ด", "zh": "二维码网格布局预览", "ja": "QRコードグリッドレイアウトのプレビュー", "ko": "QR 코드 그리드 레이아웃 미리보기", "id": "Pratinjau tata letak grid kode QR", "ms": "Pratonton susun atur grid kod QR"],
        "table_qr_sim_message_template": ["en": "Table %@ - Scan to order: %@", "th": "โต๊ะ %@ - สแกนเพื่อสั่ง: %@", "zh": "桌 %@ - 扫码点餐: %@", "ja": "テーブル %@ - スキャンして注文: %@", "ko": "테이블 %@ - 스캔하여 주문: %@", "id": "Meja %@ - Pindai untuk pesan: %@", "ms": "Meja %@ - Imbas untuk pesan: %@"],
        "table_qr_sim_title": ["en": "QR Code Simulation", "th": "จำลองคิวอาร์โค้ด", "zh": "二维码模拟", "ja": "QRコードシミュレーション", "ko": "QR 코드 시뮬레이션", "id": "Simulasi Kode QR", "ms": "Simulasi Kod QR"],
        "table_reserve_btn": ["en": "Reserve", "th": "จอง", "zh": "预订", "ja": "予約", "ko": "예약", "id": "Pesan", "ms": "Tempah"],
        "table_seats_lbl": ["en": "Seats", "th": "ที่นั่ง", "zh": "座位", "ja": "席", "ko": "좌석", "id": "Kursi", "ms": "Kerusi"],
        "table_seats_sub": ["en": "Number of chairs around this table", "th": "จำนวนเก้าอี้รอบโต๊ะนี้", "zh": "此桌椅子数量", "ja": "このテーブルの椅子数", "ko": "이 테이블의 의자 수", "id": "Jumlah kursi di meja ini", "ms": "Bilangan kerusi di meja ini"],
        "table_service_requests_title": ["en": "Service Requests", "th": "คำขอบริการ", "zh": "服务请求", "ja": "サービスリクエスト", "ko": "서비스 요청", "id": "Permintaan Layanan", "ms": "Permintaan Perkhidmatan"],
        "table_sessions": ["en": "Table Sessions", "th": "เซสชันโต๊ะ", "zh": "桌位会话", "ja": "テーブルセッション", "ko": "테이블 세션", "id": "Sesi Meja", "ms": "Sesi Meja"],
        "table_shape_lbl": ["en": "Shape", "th": "รูปทรง", "zh": "形状", "ja": "形状", "ko": "모양", "id": "Bentuk", "ms": "Bentuk"],
        "table_shape_rectangle": ["en": "Rectangle", "th": "สี่เหลี่ยม", "zh": "长方形", "ja": "長方形", "ko": "직사각형", "id": "Persegi Panjang", "ms": "Segi Empat"],
        "table_shape_round": ["en": "Round", "th": "กลม", "zh": "圆形", "ja": "丸型", "ko": "원형", "id": "Bulat", "ms": "Bulat"],
        "table_split_btn": ["en": "Split Table", "th": "แยกโต๊ะ", "zh": "拆分桌位", "ja": "テーブル分割", "ko": "테이블 분리", "id": "Pisahkan Meja", "ms": "Pisahkan Meja"],
        "table_start_session_btn": ["en": "Start Session", "th": "เริ่มเซสชัน", "zh": "开始会话", "ja": "セッション開始", "ko": "세션 시작", "id": "Mulai Sesi", "ms": "Mula Sesi"],
        "table_started_at_lbl": ["en": "Started At", "th": "เริ่มเมื่อ", "zh": "开始时间", "ja": "開始時刻", "ko": "시작 시간", "id": "Dimulai Pada", "ms": "Bermula Pada"],
        "table_vacant_btn": ["en": "Set Vacant", "th": "ตั้งเป็นว่าง", "zh": "设为空桌", "ja": "空席にする", "ko": "빈 자리로 설정", "id": "Set Kosong", "ms": "Tetapkan Kosong"],
        // MARK: - Cash Drawer
        "cash_actual": ["en": "Actual Cash", "th": "เงินสดจริง", "zh": "实际现金", "ja": "実際の現金", "ko": "실제 현금", "id": "Tunai Aktual", "ms": "Tunai Sebenar"],
        "cash_discrepancy": ["en": "Discrepancy", "th": "ส่วนต่าง", "zh": "差异", "ja": "差異", "ko": "차이", "id": "Selisih", "ms": "Perbezaan"],
        "cash_drawer_shifts_title": ["en": "Cash Drawer Shifts", "th": "กะลิ้นชักเงิน", "zh": "收银班次", "ja": "キャッシュドロワーシフト", "ko": "현금 서랍 교대", "id": "Shift Laci Kasir", "ms": "Syif Laci Tunai"],
        "cash_expected": ["en": "Expected Cash", "th": "เงินสดที่คาดไว้", "zh": "预期现金", "ja": "予想現金", "ko": "예상 현금", "id": "Tunai yang Diharapkan", "ms": "Tunai Dijangka"],
        "cash_float_sub": ["en": "Starting cash for this shift", "th": "เงินสดเริ่มต้นกะนี้", "zh": "本班次起始现金", "ja": "このシフトの初期現金", "ko": "이 교대의 시작 현금", "id": "Uang awal untuk shift ini", "ms": "Wang permulaan untuk syif ini"],
        "cash_in": ["en": "Cash In", "th": "เงินเข้า", "zh": "现金收入", "ja": "入金", "ko": "현금 입금", "id": "Kas Masuk", "ms": "Tunai Masuk"],
        "cash_in_label": ["en": "Cash In", "th": "เงินเข้า", "zh": "现金收入", "ja": "入金", "ko": "현금 입금", "id": "Kas Masuk", "ms": "Tunai Masuk"],
        "cash_in_label_colon": ["en": "Cash In:", "th": "เงินเข้า:", "zh": "现金收入:", "ja": "入金:", "ko": "현금 입금:", "id": "Kas Masuk:", "ms": "Tunai Masuk:"],
        "cash_movements": ["en": "Cash Movements", "th": "การเคลื่อนไหวเงินสด", "zh": "现金流动", "ja": "現金移動", "ko": "현금 이동", "id": "Pergerakan Kas", "ms": "Pergerakan Tunai"],
        "cash_movements_log": ["en": "Cash Movements Log", "th": "บันทึกการเคลื่อนไหวเงินสด", "zh": "现金流动记录", "ja": "現金移動ログ", "ko": "현금 이동 기록", "id": "Log Pergerakan Kas", "ms": "Log Pergerakan Tunai"],
        "cash_out": ["en": "Cash Out", "th": "เงินออก", "zh": "现金支出", "ja": "出金", "ko": "현금 출금", "id": "Kas Keluar", "ms": "Tunai Keluar"],
        "cash_out_label": ["en": "Cash Out", "th": "เงินออก", "zh": "现金支出", "ja": "出金", "ko": "현금 출금", "id": "Kas Keluar", "ms": "Tunai Keluar"],
        "cash_out_label_colon": ["en": "Cash Out:", "th": "เงินออก:", "zh": "现金支出:", "ja": "出金:", "ko": "현금 출금:", "id": "Kas Keluar:", "ms": "Tunai Keluar:"],
        "cash_payment_title": ["en": "Cash Payment", "th": "ชำระเงินสด", "zh": "现金支付", "ja": "現金払い", "ko": "현금 결제", "id": "Pembayaran Tunai", "ms": "Pembayaran Tunai"],
        "cash_sales_label": ["en": "Cash Sales", "th": "ยอดขายเงินสด", "zh": "现金销售", "ja": "現金売上", "ko": "현금 매출", "id": "Penjualan Tunai", "ms": "Jualan Tunai"],
        "cash_sales_label_colon": ["en": "Cash Sales:", "th": "ยอดขายเงินสด:", "zh": "现金销售:", "ja": "現金売上:", "ko": "현금 매출:", "id": "Penjualan Tunai:", "ms": "Jualan Tunai:"],
        "drawer_locked_subtitle": ["en": "Ask a manager to unlock the cash drawer", "th": "ขอให้ผู้จัดการปลดล็อกลิ้นชักเงิน", "zh": "请管理员解锁收银台", "ja": "管理者にキャッシュドロワーのロック解除を依頼", "ko": "관리자에게 현금 서랍 잠금 해제 요청", "id": "Minta manajer membuka laci kas", "ms": "Minta pengurus buka kunci laci tunai"],
        "drawer_locked_title": ["en": "Drawer Locked", "th": "ลิ้นชักถูกล็อก", "zh": "收银台已锁定", "ja": "ドロワーがロックされています", "ko": "서랍 잠김", "id": "Laci Terkunci", "ms": "Laci Berkunci"],
        // MARK: - Split Payment
        "split_add_payment_method": ["en": "Add Payment Method", "th": "เพิ่มวิธีชำระ", "zh": "添加支付方式", "ja": "支払い方法を追加", "ko": "결제 수단 추가", "id": "Tambah Metode Pembayaran", "ms": "Tambah Kaedah Pembayaran"],
        "split_balanced": ["en": "Balanced", "th": "สมดุล", "zh": "已平衡", "ja": "精算完了", "ko": "균형", "id": "Seimbang", "ms": "Seimbang"],
        "split_bill_total": ["en": "Bill Total", "th": "ยอดบิลรวม", "zh": "账单总额", "ja": "伝票合計", "ko": "청구서 합계", "id": "Total Tagihan", "ms": "Jumlah Bil"],
        "split_complete_payment": ["en": "Complete Payment", "th": "จ่ายเงินเสร็จสิ้น", "zh": "完成支付", "ja": "支払い完了", "ko": "결제 완료", "id": "Selesaikan Pembayaran", "ms": "Selesaikan Pembayaran"],
        "split_equally_by_guests": ["en": "Split Equally by Guests", "th": "แบ่งเท่าๆ ตามจำนวนคน", "zh": "按人数均分", "ja": "人数で均等割り", "ko": "인원수로 균등 분할", "id": "Bagi Rata per Tamu", "ms": "Bahagi Sama per Tetamu"],
        "split_guests_label": ["en": "Guests", "th": "จำนวนคน", "zh": "人数", "ja": "人数", "ko": "인원", "id": "Tamu", "ms": "Tetamu"],
        "split_overpaid": ["en": "Overpaid", "th": "จ่ายเกิน", "zh": "超额支付", "ja": "過払い", "ko": "초과 결제", "id": "Kelebihan Bayar", "ms": "Lebihan Bayaran"],
        "split_payment_index_template": ["en": "Payment %@", "th": "การชำระ %@", "zh": "支付 %@", "ja": "支払い %@", "ko": "결제 %@", "id": "Pembayaran %@", "ms": "Pembayaran %@"],
        "split_payment_title": ["en": "Split Payment", "th": "แบ่งจ่าย", "zh": "分单支付", "ja": "分割払い", "ko": "분할 결제", "id": "Pembayaran Terpisah", "ms": "Pembayaran Berasingan"],
        "split_per_person": ["en": "Per Person", "th": "ต่อคน", "zh": "每人", "ja": "一人あたり", "ko": "1인당", "id": "Per Orang", "ms": "Seorang"],
        "split_remaining": ["en": "Remaining", "th": "คงเหลือ", "zh": "剩余", "ja": "残額", "ko": "잔액", "id": "Sisa", "ms": "Baki"],
        "split_total_payments": ["en": "Total Payments", "th": "ยอดชำระทั้งหมด", "zh": "总支付额", "ja": "支払い合計", "ko": "총 결제액", "id": "Total Pembayaran", "ms": "Jumlah Pembayaran"],
        // MARK: - Refunds
        "refund_amount_lbl": ["en": "Refund Amount", "th": "จำนวนเงินคืน", "zh": "退款金额", "ja": "返金額", "ko": "환불 금액", "id": "Jumlah Refund", "ms": "Jumlah Bayaran Balik"],
        "refund_label": ["en": "Refund", "th": "คืนเงิน", "zh": "退款", "ja": "返金", "ko": "환불", "id": "Refund", "ms": "Bayaran Balik"],
        "refund_no_orders_found": ["en": "No Orders Found", "th": "ไม่พบออเดอร์", "zh": "未找到订单", "ja": "注文が見つかりません", "ko": "주문을 찾을 수 없습니다", "id": "Pesanan Tidak Ditemukan", "ms": "Pesanan Tidak Ditemui"],
        "refund_order_items_header": ["en": "Order Items", "th": "รายการในออเดอร์", "zh": "订单商品", "ja": "注文商品", "ko": "주문 상품", "id": "Item Pesanan", "ms": "Item Pesanan"],
        "refund_original_total_lbl": ["en": "Original Total", "th": "ยอดรวมเดิม", "zh": "原始总额", "ja": "元の合計", "ko": "원래 합계", "id": "Total Asli", "ms": "Jumlah Asal"],
        "refund_payment_method_lbl": ["en": "Refund Method", "th": "วิธีคืนเงิน", "zh": "退款方式", "ja": "返金方法", "ko": "환불 방법", "id": "Metode Refund", "ms": "Kaedah Bayaran Balik"],
        "refund_process_btn": ["en": "Process Refund", "th": "ดำเนินการคืนเงิน", "zh": "处理退款", "ja": "返金処理", "ko": "환불 처리", "id": "Proses Refund", "ms": "Proses Bayaran Balik"],
        "refund_reason_header": ["en": "Refund Reason", "th": "เหตุผลการคืนเงิน", "zh": "退款原因", "ja": "返金理由", "ko": "환불 사유", "id": "Alasan Refund", "ms": "Sebab Bayaran Balik"],
        "refund_recent_orders_title": ["en": "Recent Orders", "th": "ออเดอร์ล่าสุด", "zh": "最近订单", "ja": "最近の注文", "ko": "최근 주문", "id": "Pesanan Terbaru", "ms": "Pesanan Terkini"],
        "refund_return": ["en": "Return", "th": "คืน", "zh": "退回", "ja": "返品", "ko": "반품", "id": "Retur", "ms": "Pulang"],
        "refund_select_order_desc": ["en": "Select an order to refund", "th": "เลือกออเดอร์ที่ต้องการคืนเงิน", "zh": "选择要退款的订单", "ja": "返金する注文を選択", "ko": "환불할 주문을 선택하세요", "id": "Pilih pesanan untuk direfund", "ms": "Pilih pesanan untuk bayaran balik"],
        "refund_select_order_title": ["en": "Select Order", "th": "เลือกออเดอร์", "zh": "选择订单", "ja": "注文を選択", "ko": "주문 선택", "id": "Pilih Pesanan", "ms": "Pilih Pesanan"],
        "refund_total_lbl": ["en": "Refund Total", "th": "ยอดคืนเงินทั้งหมด", "zh": "退款总额", "ja": "返金合計", "ko": "환불 합계", "id": "Total Refund", "ms": "Jumlah Bayaran Balik"],
        "refund_type_full": ["en": "Full Refund", "th": "คืนเงินเต็มจำนวน", "zh": "全额退款", "ja": "全額返金", "ko": "전액 환불", "id": "Refund Penuh", "ms": "Bayaran Balik Penuh"],
        "refund_type_partial": ["en": "Partial Refund", "th": "คืนเงินบางส่วน", "zh": "部分退款", "ja": "一部返金", "ko": "부분 환불", "id": "Refund Sebagian", "ms": "Bayaran Balik Separa"],
        // MARK: - Loyalty
        "loyalty_adjust_loyalty_title": ["en": "Adjust Points", "th": "ปรับแต้ม", "zh": "调整积分", "ja": "ポイント調整", "ko": "포인트 조정", "id": "Sesuaikan Poin", "ms": "Laraskan Mata"],
        "loyalty_adjust_points": ["en": "Adjust Points", "th": "ปรับแต้ม", "zh": "调整积分", "ja": "ポイント調整", "ko": "포인트 조정", "id": "Sesuaikan Poin", "ms": "Laraskan Mata"],
        "loyalty_bal_template": ["en": "Balance: %@ pts", "th": "ยอดคงเหลือ: %@ แต้ม", "zh": "余额: %@ 积分", "ja": "残高: %@ ポイント", "ko": "잔액: %@ 포인트", "id": "Saldo: %@ poin", "ms": "Baki: %@ mata"],
        "loyalty_customer_orders": ["en": "Customer Orders", "th": "ออเดอร์ลูกค้า", "zh": "客户订单", "ja": "顧客注文", "ko": "고객 주문", "id": "Pesanan Pelanggan", "ms": "Pesanan Pelanggan"],
        "loyalty_earn_rate": ["en": "Earn Rate", "th": "อัตราสะสม", "zh": "积分率", "ja": "獲得レート", "ko": "적립률", "id": "Tingkat Perolehan", "ms": "Kadar Perolehan"],
        "loyalty_history": ["en": "Points History", "th": "ประวัติแต้ม", "zh": "积分历史", "ja": "ポイント履歴", "ko": "포인트 내역", "id": "Riwayat Poin", "ms": "Sejarah Mata"],
        "loyalty_history_section": ["en": "History", "th": "ประวัติ", "zh": "历史", "ja": "履歴", "ko": "내역", "id": "Riwayat", "ms": "Sejarah"],
        "loyalty_members": ["en": "Members", "th": "สมาชิก", "zh": "会员", "ja": "メンバー", "ko": "회원", "id": "Anggota", "ms": "Ahli"],
        "loyalty_no_orders": ["en": "No Orders Yet", "th": "ยังไม่มีออเดอร์", "zh": "暂无订单", "ja": "注文なし", "ko": "아직 주문 없음", "id": "Belum Ada Pesanan", "ms": "Belum Ada Pesanan"],
        "loyalty_no_transactions": ["en": "No Transactions", "th": "ไม่มีรายการ", "zh": "无交易记录", "ja": "取引なし", "ko": "거래 없음", "id": "Tidak Ada Transaksi", "ms": "Tiada Transaksi"],
        "loyalty_open_points": ["en": "Open Points", "th": "แต้มที่ใช้ได้", "zh": "可用积分", "ja": "利用可能ポイント", "ko": "사용 가능 포인트", "id": "Poin Tersedia", "ms": "Mata Tersedia"],
        "loyalty_points": ["en": "Points", "th": "แต้ม", "zh": "积分", "ja": "ポイント", "ko": "포인트", "id": "Poin", "ms": "Mata"],
        "loyalty_points_per_baht": ["en": "Points per Baht", "th": "แต้มต่อบาท", "zh": "每泰铢积分", "ja": "バーツあたりポイント", "ko": "바트당 포인트", "id": "Poin per Baht", "ms": "Mata per Baht"],
        "loyalty_reason_note": ["en": "Reason/Note", "th": "เหตุผล/หมายเหตุ", "zh": "原因/备注", "ja": "理由/メモ", "ko": "사유/메모", "id": "Alasan/Catatan", "ms": "Sebab/Nota"],
        "loyalty_redeem_rate": ["en": "Redeem Rate", "th": "อัตราแลก", "zh": "兑换率", "ja": "交換レート", "ko": "교환률", "id": "Tingkat Penukaran", "ms": "Kadar Penebusan"],
        "loyalty_redeem_value": ["en": "Redeem Value", "th": "มูลค่าแลก", "zh": "兑换价值", "ja": "交換価値", "ko": "교환 가치", "id": "Nilai Penukaran", "ms": "Nilai Penebusan"],
        "loyalty_redeem_value_per_point": ["en": "Value per Point", "th": "มูลค่าต่อแต้ม", "zh": "每积分价值", "ja": "ポイント単価", "ko": "포인트당 가치", "id": "Nilai per Poin", "ms": "Nilai per Mata"],
        "loyalty_search_placeholder": ["en": "Search members...", "th": "ค้นหาสมาชิก...", "zh": "搜索会员...", "ja": "メンバー検索...", "ko": "회원 검색...", "id": "Cari anggota...", "ms": "Cari ahli..."],
        "loyalty_select_customer_prompt": ["en": "Select a customer to view loyalty", "th": "เลือกลูกค้าเพื่อดูแต้มสะสม", "zh": "选择客户查看积分", "ja": "顧客を選択してポイントを表示", "ko": "고객을 선택하여 포인트 확인", "id": "Pilih pelanggan untuk lihat loyalitas", "ms": "Pilih pelanggan untuk lihat kesetiaan"],
        "loyalty_transaction_type": ["en": "Transaction Type", "th": "ประเภทรายการ", "zh": "交易类型", "ja": "取引種類", "ko": "거래 유형", "id": "Jenis Transaksi", "ms": "Jenis Transaksi"],
        "loyalty_transactions": ["en": "Transactions", "th": "รายการ", "zh": "交易记录", "ja": "取引履歴", "ko": "거래 내역", "id": "Transaksi", "ms": "Transaksi"],
        "loyalty_visits_spend_template": ["en": "%@ visits · ฿%@ spent", "th": "%@ ครั้ง · ฿%@ ใช้จ่าย", "zh": "%@ 次访问 · ฿%@ 消费", "ja": "%@ 回来店 · ฿%@ 利用", "ko": "%@ 방문 · ฿%@ 사용", "id": "%@ kunjungan · ฿%@ belanja", "ms": "%@ lawatan · ฿%@ belanja"],
        // MARK: - M-3: Loyalty Tiers
        "loyalty_tier_standard": ["en": "Standard", "th": "ทั่วไป", "zh": "标准会员", "ja": "スタンダード", "ko": "스탠다드", "id": "Standar", "ms": "Standard"],
        "loyalty_tier_silver": ["en": "Silver", "th": "ซิลเวอร์", "zh": "银卡会员", "ja": "シルバー", "ko": "실버", "id": "Silver", "ms": "Silver"],
        "loyalty_tier_gold": ["en": "Gold", "th": "โกลด์", "zh": "金卡会员", "ja": "ゴールド", "ko": "골드", "id": "Emas", "ms": "Emas"],
        "loyalty_tier_platinum": ["en": "Platinum", "th": "แพลทินัม", "zh": "白金会员", "ja": "プラチナ", "ko": "플래티넘", "id": "Platinum", "ms": "Platinum"],
        "loyalty_tier_progress_label": ["en": "Progress to next tier", "th": "ความคืบหน้าสู่ระดับถัดไป", "zh": "距下一等级进度", "ja": "次のティアまでの進捗", "ko": "다음 등급까지 진행률", "id": "Kemajuan ke tingkat berikutnya", "ms": "Kemajuan ke peringkat seterusnya"],
        "loyalty_next_tier_label": ["en": "Next: %@", "th": "ถัดไป: %@", "zh": "下一级：%@", "ja": "次: %@", "ko": "다음: %@", "id": "Berikutnya: %@", "ms": "Seterusnya: %@"],
        // MARK: - Purchase Orders
        "po_choose_ingredient_placeholder": ["en": "Choose ingredient", "th": "เลือกวัตถุดิบ", "zh": "选择原料", "ja": "材料を選択", "ko": "재료 선택", "id": "Pilih bahan", "ms": "Pilih bahan"],
        "po_delivery_verification_desc": ["en": "Verify delivered items against order", "th": "ตรวจสอบสินค้าที่ส่งกับออเดอร์", "zh": "核对已交付商品与订单", "ja": "配達品を注文と照合", "ko": "배달 품목을 주문과 대조 확인", "id": "Verifikasi item terkirim dengan pesanan", "ms": "Sahkan item dihantar dengan pesanan"],
        "po_delivery_verification_title": ["en": "Delivery Verification", "th": "ตรวจรับสินค้า", "zh": "交货验证", "ja": "配達確認", "ko": "배달 확인", "id": "Verifikasi Pengiriman", "ms": "Pengesahan Penghantaran"],
        "po_detail_branch_template": ["en": "Branch: %@", "th": "สาขา: %@", "zh": "分店: %@", "ja": "支店: %@", "ko": "지점: %@", "id": "Cabang: %@", "ms": "Cawangan: %@"],
        "po_detail_delivery_template": ["en": "Delivery: %@", "th": "จัดส่ง: %@", "zh": "配送: %@", "ja": "配達: %@", "ko": "배달: %@", "id": "Pengiriman: %@", "ms": "Penghantaran: %@"],
        "po_detail_notes_template": ["en": "Notes: %@", "th": "หมายเหตุ: %@", "zh": "备注: %@", "ja": "メモ: %@", "ko": "메모: %@", "id": "Catatan: %@", "ms": "Nota: %@"],
        "po_detail_ordered_template": ["en": "Ordered: %@", "th": "สั่งเมื่อ: %@", "zh": "订购日期: %@", "ja": "発注日: %@", "ko": "주문일: %@", "id": "Dipesan: %@", "ms": "Ditempah: %@"],
        "po_detail_supplier_template": ["en": "Supplier: %@", "th": "ซัพพลายเออร์: %@", "zh": "供应商: %@", "ja": "仕入先: %@", "ko": "공급업체: %@", "id": "Pemasok: %@", "ms": "Pembekal: %@"],
        "po_details_header": ["en": "PO Details", "th": "รายละเอียด PO", "zh": "采购单详情", "ja": "発注詳細", "ko": "PO 상세", "id": "Detail PO", "ms": "Butiran PO"],
        "po_info_title": ["en": "Purchase Order Info", "th": "ข้อมูลใบสั่งซื้อ", "zh": "采购单信息", "ja": "発注書情報", "ko": "구매 주문 정보", "id": "Info Pesanan Pembelian", "ms": "Info Pesanan Belian"],
        "po_items_count_template": ["en": "%@ items", "th": "%@ รายการ", "zh": "%@ 项", "ja": "%@ 品", "ko": "%@ 항목", "id": "%@ item", "ms": "%@ item"],
        "po_must_register_supplier_desc": ["en": "Register a supplier first to create purchase orders", "th": "ลงทะเบียนซัพพลายเออร์ก่อนสร้างใบสั่งซื้อ", "zh": "请先注册供应商再创建采购单", "ja": "発注書作成前に仕入先を登録してください", "ko": "구매 주문을 만들려면 먼저 공급업체를 등록하세요", "id": "Daftarkan pemasok terlebih dahulu", "ms": "Daftarkan pembekal terlebih dahulu"],
        "po_no_items_added": ["en": "No items added yet", "th": "ยังไม่ได้เพิ่มรายการ", "zh": "尚未添加商品", "ja": "商品が追加されていません", "ko": "아직 추가된 항목 없음", "id": "Belum ada item ditambahkan", "ms": "Belum ada item ditambah"],
        "po_no_orders_desc": ["en": "Create your first purchase order", "th": "สร้างใบสั่งซื้อแรกของคุณ", "zh": "创建您的第一个采购单", "ja": "最初の発注書を作成", "ko": "첫 번째 구매 주문을 만드세요", "id": "Buat pesanan pembelian pertama Anda", "ms": "Buat pesanan belian pertama anda"],
        "po_no_orders_title": ["en": "No Purchase Orders", "th": "ไม่มีใบสั่งซื้อ", "zh": "没有采购单", "ja": "発注書なし", "ko": "구매 주문 없음", "id": "Tidak Ada Pesanan Pembelian", "ms": "Tiada Pesanan Belian"],
        "po_no_suppliers_desc": ["en": "Add suppliers to start ordering", "th": "เพิ่มซัพพลายเออร์เพื่อเริ่มสั่งซื้อ", "zh": "添加供应商以开始订购", "ja": "仕入先を追加して発注開始", "ko": "공급업체를 추가하여 주문 시작", "id": "Tambah pemasok untuk mulai pesan", "ms": "Tambah pembekal untuk mula pesan"],
        "po_no_suppliers_title": ["en": "No Suppliers", "th": "ไม่มีซัพพลายเออร์", "zh": "没有供应商", "ja": "仕入先なし", "ko": "공급업체 없음", "id": "Tidak Ada Pemasok", "ms": "Tiada Pembekal"],
        "po_notes_label": ["en": "Notes", "th": "หมายเหตุ", "zh": "备注", "ja": "メモ", "ko": "메모", "id": "Catatan", "ms": "Nota"],
        "po_number_label": ["en": "PO Number", "th": "เลขที่ PO", "zh": "采购单号", "ja": "発注番号", "ko": "PO 번호", "id": "Nomor PO", "ms": "Nombor PO"],
        "po_ordered_lbl_template": ["en": "Ordered: %@", "th": "สั่งเมื่อ: %@", "zh": "已订购: %@", "ja": "発注日: %@", "ko": "주문일: %@", "id": "Dipesan: %@", "ms": "Ditempah: %@"],
        "po_ordered_products_header": ["en": "Ordered Products", "th": "สินค้าที่สั่ง", "zh": "已订购产品", "ja": "発注商品", "ko": "주문 상품", "id": "Produk Dipesan", "ms": "Produk Ditempah"],
        "po_select_supplier_placeholder": ["en": "Select supplier", "th": "เลือกซัพพลายเออร์", "zh": "选择供应商", "ja": "仕入先を選択", "ko": "공급업체 선택", "id": "Pilih pemasok", "ms": "Pilih pembekal"],
        "po_supplier_label": ["en": "Supplier", "th": "ซัพพลายเออร์", "zh": "供应商", "ja": "仕入先", "ko": "공급업체", "id": "Pemasok", "ms": "Pembekal"],
        "po_verify_barcode_template": ["en": "Scan barcode for: %@", "th": "สแกนบาร์โค้ดสำหรับ: %@", "zh": "扫描条码: %@", "ja": "バーコードをスキャン: %@", "ko": "바코드 스캔: %@", "id": "Pindai barcode untuk: %@", "ms": "Imbas barkod untuk: %@"],
        "po_verify_notes_label": ["en": "Verification Notes", "th": "หมายเหตุการตรวจรับ", "zh": "验收备注", "ja": "検収メモ", "ko": "검수 메모", "id": "Catatan Verifikasi", "ms": "Nota Pengesahan"],
        "po_verify_qty_received": ["en": "Qty Received", "th": "จำนวนที่รับ", "zh": "已收数量", "ja": "受領数量", "ko": "수령 수량", "id": "Qty Diterima", "ms": "Qty Diterima"],
        "po_verify_unit_cost": ["en": "Unit Cost", "th": "ราคาต่อหน่วย", "zh": "单位成本", "ja": "単価", "ko": "단가", "id": "Biaya Satuan", "ms": "Kos Seunit"],
        "purchase_orders": ["en": "Purchase Orders", "th": "ใบสั่งซื้อ", "zh": "采购单", "ja": "発注書", "ko": "구매 주문", "id": "Pesanan Pembelian", "ms": "Pesanan Belian"],
        // MARK: - Inventory & Stock
        "inventory_expenses": ["en": "Expenses", "th": "ค่าใช้จ่าย", "zh": "费用", "ja": "経費", "ko": "비용", "id": "Pengeluaran", "ms": "Perbelanjaan"],
        "expense_today": ["en": "Today's Expenses", "th": "ค่าใช้จ่ายวันนี้", "zh": "今日费用", "ja": "今日の経費", "ko": "오늘의 비용", "id": "Pengeluaran Hari Ini", "ms": "Perbelanjaan Hari Ini"],
        "expense_monthly": ["en": "Monthly Expenses", "th": "ค่าใช้จ่ายเดือนนี้", "zh": "本月费用", "ja": "今月の経費", "ko": "이번 달 비용", "id": "Pengeluaran Bulan Ini", "ms": "Perbelanjaan Bulan Ini"],
        "expense_categories": ["en": "Expense Categories", "th": "สัดส่วนค่าใช้จ่าย", "zh": "费用类别", "ja": "経費カテゴリ", "ko": "비용 카테고리", "id": "Kategori Pengeluaran", "ms": "Kategori Perbelanjaan"],
        "expense_category_raw_materials": ["en": "Raw Materials", "th": "วัตถุดิบอื่นๆ", "zh": "其他原材料", "ja": "その他原材料", "ko": "기타 원자재", "id": "Bahan Baku Lain", "ms": "Bahan Mentah Lain"],
        "expense_category_equipment": ["en": "Equipment", "th": "อุปกรณ์ร้าน", "zh": "店铺设备", "ja": "店舗設備", "ko": "매장 설비", "id": "Peralatan Toko", "ms": "Peralatan Kedai"],
        "expense_category_consumables": ["en": "Consumables", "th": "วัสดุสิ้นเปลือง", "zh": "易耗品", "ja": "消耗品", "ko": "소모품", "id": "Bahan Habis Pakai", "ms": "Bahan Habis Pakai"],
        "expense_category_maintenance": ["en": "Maintenance", "th": "ค่าบำรุงรักษา", "zh": "维护费用", "ja": "メンテナンス費", "ko": "유지보수비", "id": "Pemeliharaan", "ms": "Penyelenggaraan"],
        "expense_category_other": ["en": "Other Expenses", "th": "ค่าใช้จ่ายอื่นๆ", "zh": "其他费用", "ja": "その他経費", "ko": "기타 비용", "id": "Pengeluaran Lain", "ms": "Perbelanjaan Lain"],
        "expense_add": ["en": "Add Expense", "th": "เพิ่มค่าใช้จ่าย", "zh": "添加费用", "ja": "経費追加", "ko": "비용 추가", "id": "Tambah Pengeluaran", "ms": "Tambah Perbelanjaan"],
        "expense_title": ["en": "Expense Item", "th": "รายการค่าใช้จ่าย", "zh": "费用项目", "ja": "経費項目", "ko": "비용 항목", "id": "Item Pengeluaran", "ms": "Item Perbelanjaan"],
        "expense_amount": ["en": "Amount", "th": "จำนวนเงิน", "zh": "金额", "ja": "金額", "ko": "금액", "id": "Jumlah", "ms": "Jumlah"],
        "expense_category": ["en": "Category", "th": "หมวดหมู่", "zh": "类别", "ja": "カテゴリ", "ko": "카테고리", "id": "Kategori", "ms": "Kategori"],
        "expense_date": ["en": "Date", "th": "วันที่", "zh": "日期", "ja": "日付", "ko": "날짜", "id": "Tanggal", "ms": "Tarikh"],
        "expense_notes": ["en": "Notes", "th": "บันทึกเพิ่มเติม", "zh": "备注", "ja": "メモ", "ko": "메모", "id": "Catatan", "ms": "Nota"],
        "expense_new_title": ["en": "New Expense Record", "th": "บันทึกรายจ่ายใหม่", "zh": "新建费用记录", "ja": "新規経費登録", "ko": "새 비용 기록", "id": "Catatan Pengeluaran Baru", "ms": "Rekod Perbelanjaan Baru"],
        "expense_empty_title": ["en": "No Expenses Logged", "th": "ไม่มีรายการค่าใช้จ่าย", "zh": "暂无费用记录", "ja": "経費記録なし", "ko": "비용 기록 없음", "id": "Tidak Ada Pengeluaran", "ms": "Tiada Perbelanjaan"],
        "expense_empty_subtitle": ["en": "Add expense records to track daily or monthly shop costs", "th": "เพิ่มรายการเพื่อติดตามค่าใช้จ่ายและงบประมาณของร้าน", "zh": "添加费用记录以跟踪每日หรือ每月店铺成本", "ja": "経費を登録して日々の店舗運営費を管理します", "ko": "매일 또는 매월 매장 비용을 추적하려면 비용 기록을 추가하세요", "id": "Tambahkan pengeluaran untuk melacak biaya toko harian atau bulanan", "ms": "Tambah rekod perbelanjaan untuk menjejaki kos kedai harian atau bulanan"],
        "expense_confirm_delete": ["en": "Delete Expense?", "th": "ยืนยันการลบค่าใช้จ่าย?", "zh": "确认删除费用吗？", "ja": "経費を削除しますか？", "ko": "비용을 삭제하시겠습니까?", "id": "Hapus Pengeluaran?", "ms": "Padam Perbelanjaan?"],
        "inventory_abc_classification": ["en": "ABC Classification", "th": "การจัดกลุ่ม ABC", "zh": "ABC 分类", "ja": "ABC 分類", "ko": "ABC 분류", "id": "Klasifikasi ABC", "ms": "Klasifikasi ABC"],
        "inventory_empty_subtitle": ["en": "Add items to track your inventory", "th": "เพิ่มสินค้าเพื่อติดตามสต็อก", "zh": "添加商品以跟踪库存", "ja": "商品を追加して在庫管理", "ko": "상품을 추가하여 재고 추적", "id": "Tambahkan item untuk lacak inventaris", "ms": "Tambah item untuk jejak inventori"],
        "inventory_empty_title": ["en": "No Inventory Items", "th": "ไม่มีสินค้าในคลัง", "zh": "没有库存商品", "ja": "在庫商品なし", "ko": "재고 품목 없음", "id": "Tidak Ada Item Inventaris", "ms": "Tiada Item Inventori"],
        "inventory_items": ["en": "Inventory Items", "th": "สินค้าในคลัง", "zh": "库存商品", "ja": "在庫商品", "ko": "재고 품목", "id": "Item Inventaris", "ms": "Item Inventori"],
        "inventory_products": ["en": "Products", "th": "สินค้า", "zh": "产品", "ja": "商品", "ko": "상품", "id": "Produk", "ms": "Produk"],
        "inventory_raw_materials": ["en": "Raw Materials", "th": "วัตถุดิบ", "zh": "原材料", "ja": "原材料", "ko": "원자재", "id": "Bahan Baku", "ms": "Bahan Mentah"],
        "inventory_receive": ["en": "Receive Stock", "th": "รับสินค้า", "zh": "入库", "ja": "入荷", "ko": "입고", "id": "Terima Stok", "ms": "Terima Stok"],
        "inventory_recipes": ["en": "Recipes", "th": "สูตรอาหาร", "zh": "食谱", "ja": "レシピ", "ko": "레시피", "id": "Resep", "ms": "Resipi"],
        "inventory_sort_cost": ["en": "Sort by Cost", "th": "เรียงตามต้นทุน", "zh": "按成本排序", "ja": "原価順", "ko": "비용순 정렬", "id": "Urutkan Biaya", "ms": "Isih Kos"],
        "inventory_sort_name": ["en": "Sort by Name", "th": "เรียงตามชื่อ", "zh": "按名称排序", "ja": "名前順", "ko": "이름순 정렬", "id": "Urutkan Nama", "ms": "Isih Nama"],
        "inventory_sort_quantity": ["en": "Sort by Quantity", "th": "เรียงตามจำนวน", "zh": "按数量排序", "ja": "数量順", "ko": "수량순 정렬", "id": "Urutkan Jumlah", "ms": "Isih Kuantiti"],
        "inventory_sort_updated": ["en": "Sort by Updated", "th": "เรียงตามอัปเดต", "zh": "按更新排序", "ja": "更新順", "ko": "업데이트순 정렬", "id": "Urutkan Terbaru", "ms": "Isih Terkini"],
        "inventory_sort_expiry": ["en": "Sort by Expiry", "th": "เรียงตามวันหมดอายุ", "zh": "按到期排序", "ja": "期限順", "ko": "만료순 정렬", "id": "Urutkan Kedaluwarsa", "ms": "Isih Tamat Tempoh"],
        "safety_stock_section_title": ["en": "Safety Stock & Lead Time", "th": "Safety Stock และ Lead Time", "zh": "安全库存与交货期", "ja": "安全在庫・リードタイム", "ko": "안전 재고 및 리드타임", "id": "Stok Pengaman & Waktu Tunggu", "ms": "Stok Selamat & Masa Tunggu"],
        "safety_stock_label": ["en": "Safety Stock", "th": "Safety Stock (สต็อกกันชน)", "zh": "安全库存", "ja": "安全在庫", "ko": "안전 재고", "id": "Stok Pengaman", "ms": "Stok Selamat"],
        "max_stock_label": ["en": "Max Stock Level", "th": "ปริมาณสต็อกสูงสุด", "zh": "最大库存量", "ja": "最大在庫数", "ko": "최대 재고 수준", "id": "Level Stok Maks", "ms": "Tahap Stok Maks"],
        "lead_time_days_label": ["en": "Supplier Lead Time", "th": "Lead Time จาก Supplier", "zh": "供应商交货期", "ja": "サプライヤーリードタイム", "ko": "공급업체 리드타임", "id": "Waktu Tunggu Supplier", "ms": "Masa Tunggu Pembekal"],
        "expiry_lot_section_title": ["en": "Expiry & Lot Tracking", "th": "ติดตามวันหมดอายุ / Lot", "zh": "到期日期与批次追踪", "ja": "期限・ロット追跡", "ko": "유통기한 및 로트 추적", "id": "Pelacakan Kedaluwarsa & Lot", "ms": "Penjejakan Tamat Tempoh & Lot"],
        "inventory_stock": ["en": "Stock", "th": "สต็อก", "zh": "库存", "ja": "在庫", "ko": "재고", "id": "Stok", "ms": "Stok"],
        "inventory_stock_audit": ["en": "Stock Audit", "th": "ตรวจนับสต็อก", "zh": "库存审计", "ja": "棚卸し", "ko": "재고 감사", "id": "Audit Stok", "ms": "Audit Stok"],
        "inventory_suppliers": ["en": "Suppliers", "th": "ซัพพลายเออร์", "zh": "供应商", "ja": "仕入先", "ko": "공급업체", "id": "Pemasok", "ms": "Pembekal"],
        "inventory_title": ["en": "Inventory", "th": "คลังสินค้า", "zh": "库存", "ja": "在庫", "ko": "재고", "id": "Inventaris", "ms": "Inventori"],
        "inventory_transactions": ["en": "Transactions", "th": "รายการเคลื่อนไหว", "zh": "交易记录", "ja": "取引履歴", "ko": "거래 내역", "id": "Transaksi", "ms": "Transaksi"],
        "inventory_waste": ["en": "Waste", "th": "ของเสีย", "zh": "报损", "ja": "廃棄", "ko": "폐기", "id": "Limbah", "ms": "Sisa"],
        "reorder_at_template": ["en": "Reorder at: %@", "th": "สั่งซื้อเมื่อ: %@", "zh": "补货点: %@", "ja": "再注文点: %@", "ko": "재주문 시점: %@", "id": "Pesan ulang di: %@", "ms": "Pesan semula di: %@"],
        "reorder_cost_header": ["en": "Reorder Cost", "th": "ต้นทุนการสั่งซื้อ", "zh": "补货成本", "ja": "再注文コスト", "ko": "재주문 비용", "id": "Biaya Pemesanan Ulang", "ms": "Kos Pesanan Semula"],
        "reorder_trigger_level_placeholder": ["en": "Enter reorder level", "th": "ใส่ระดับสั่งซื้อใหม่", "zh": "输入补货点", "ja": "再注文レベルを入力", "ko": "재주문 수준 입력", "id": "Masukkan level pemesanan ulang", "ms": "Masukkan tahap pesanan semula"],
        "reordering_costs": ["en": "Reordering Costs", "th": "ต้นทุนการสั่งซื้อซ้ำ", "zh": "补货费用", "ja": "再注文費用", "ko": "재주문 비용", "id": "Biaya Pemesanan Ulang", "ms": "Kos Pesanan Semula"],
        "stock_deduction_link_desc": ["en": "Automatically deduct stock when items are sold", "th": "หักสต็อกอัตโนมัติเมื่อขายสินค้า", "zh": "售出时自动扣除库存", "ja": "販売時に自動在庫控除", "ko": "판매 시 자동 재고 차감", "id": "Otomatis kurangi stok saat item terjual", "ms": "Tolak stok secara automatik apabila item dijual"],
        "stock_deduction_link_title": ["en": "Auto Stock Deduction", "th": "หักสต็อกอัตโนมัติ", "zh": "自动扣除库存", "ja": "自動在庫控除", "ko": "자동 재고 차감", "id": "Pengurangan Stok Otomatis", "ms": "Potongan Stok Automatik"],
        "stock_mode_finished_good": ["en": "Finished Good", "th": "สินค้าสำเร็จรูป", "zh": "成品", "ja": "完成品", "ko": "완제품", "id": "Barang Jadi", "ms": "Barang Siap"],
        "stock_mode_not_tracked": ["en": "Not Tracked", "th": "ไม่ติดตาม", "zh": "不跟踪", "ja": "追跡なし", "ko": "미추적", "id": "Tidak Dilacak", "ms": "Tidak Dijejak"],
        "stock_mode_recipe_based": ["en": "Recipe Based", "th": "ตามสูตร", "zh": "基于食谱", "ja": "レシピベース", "ko": "레시피 기반", "id": "Berbasis Resep", "ms": "Berdasarkan Resipi"],
        "stock_ok": ["en": "Stock OK", "th": "สต็อกปกติ", "zh": "库存正常", "ja": "在庫正常", "ko": "재고 정상", "id": "Stok OK", "ms": "Stok OK"],
        "stock_tracking_mode": ["en": "Stock Tracking Mode", "th": "โหมดติดตามสต็อก", "zh": "库存跟踪模式", "ja": "在庫追跡モード", "ko": "재고 추적 모드", "id": "Mode Pelacakan Stok", "ms": "Mod Penjejakan Stok"],
        "stock_transfer_title": ["en": "Stock Transfer", "th": "โอนสต็อก", "zh": "库存转移", "ja": "在庫移管", "ko": "재고 이동", "id": "Transfer Stok", "ms": "Pindahan Stok"],
        // MARK: - Delivery
        "delivery_apply_btn": ["en": "Apply", "th": "ใช้", "zh": "应用", "ja": "適用", "ko": "적용", "id": "Terapkan", "ms": "Guna"],
        "delivery_config_fees_desc_template": ["en": "Configure fees for %@", "th": "ตั้งค่าค่าธรรมเนียมสำหรับ %@", "zh": "为 %@ 配置费用", "ja": "%@ の料金設定", "ko": "%@ 수수료 설정", "id": "Atur biaya untuk %@", "ms": "Tetapkan yuran untuk %@"],
        "delivery_config_fees_title": ["en": "Configure Fees", "th": "ตั้งค่าค่าธรรมเนียม", "zh": "配置费用", "ja": "料金設定", "ko": "수수료 설정", "id": "Atur Biaya", "ms": "Tetapkan Yuran"],
        "delivery_gp_commission_lbl": ["en": "GP Commission", "th": "ค่าคอมมิชชัน GP", "zh": "GP 佣金", "ja": "GP手数料", "ko": "GP 커미션", "id": "Komisi GP", "ms": "Komisen GP"],
        "delivery_marketing_costs_lbl": ["en": "Marketing Costs", "th": "ค่าการตลาด", "zh": "营销费用", "ja": "マーケティング費用", "ko": "마케팅 비용", "id": "Biaya Marketing", "ms": "Kos Pemasaran"],
        "delivery_orders_lbl": ["en": "Delivery Orders", "th": "ออเดอร์เดลิเวอรี่", "zh": "外卖订单", "ja": "デリバリー注文", "ko": "배달 주문", "id": "Pesanan Delivery", "ms": "Pesanan Penghantaran"],
        "delivery_packaging_fees_lbl": ["en": "Packaging Fees", "th": "ค่าบรรจุภัณฑ์", "zh": "包装费", "ja": "梱包費", "ko": "포장비", "id": "Biaya Kemasan", "ms": "Kos Pembungkusan"],
        "delivery_pricing_desc": ["en": "Set pricing rules for delivery platforms", "th": "ตั้งราคาสำหรับแพลตฟอร์มเดลิเวอรี่", "zh": "设置外卖平台定价规则", "ja": "デリバリープラットフォームの価格設定", "ko": "배달 플랫폼 가격 규칙 설정", "id": "Atur aturan harga untuk platform delivery", "ms": "Tetapkan peraturan harga untuk platform penghantaran"],
        "delivery_pricing_title": ["en": "Delivery Pricing", "th": "ราคาเดลิเวอรี่", "zh": "外卖定价", "ja": "デリバリー価格", "ko": "배달 가격", "id": "Harga Delivery", "ms": "Harga Penghantaran"],
        // MARK: - Customers
        "customer_id": ["en": "Customer ID", "th": "รหัสลูกค้า", "zh": "客户ID", "ja": "顧客ID", "ko": "고객 ID", "id": "ID Pelanggan", "ms": "ID Pelanggan"],
        "customer_membership_points_template": ["en": "Member · %@ pts", "th": "สมาชิก · %@ แต้ม", "zh": "会员 · %@ 积分", "ja": "会員 · %@ ポイント", "ko": "회원 · %@ 포인트", "id": "Member · %@ poin", "ms": "Ahli · %@ mata"],
        "customer_phone_label": ["en": "Phone", "th": "เบอร์โทร", "zh": "电话", "ja": "電話", "ko": "전화", "id": "Telepon", "ms": "Telefon"],
        "customer_request": ["en": "Customer Request", "th": "คำขอลูกค้า", "zh": "客户要求", "ja": "お客様リクエスト", "ko": "고객 요청", "id": "Permintaan Pelanggan", "ms": "Permintaan Pelanggan"],
        "customer_section": ["en": "Customer", "th": "ลูกค้า", "zh": "客户", "ja": "顧客", "ko": "고객", "id": "Pelanggan", "ms": "Pelanggan"],
        "customers_allergies_lbl": ["en": "Allergies", "th": "อาการแพ้", "zh": "过敏", "ja": "アレルギー", "ko": "알레르기", "id": "Alergi", "ms": "Alahan"],
        "customers_count_template": ["en": "%@ customers", "th": "%@ ลูกค้า", "zh": "%@ 位客户", "ja": "%@ 人の顧客", "ko": "%@ 명의 고객", "id": "%@ pelanggan", "ms": "%@ pelanggan"],
        "customers_details_header": ["en": "Customer Details", "th": "รายละเอียดลูกค้า", "zh": "客户详情", "ja": "顧客詳細", "ko": "고객 상세", "id": "Detail Pelanggan", "ms": "Butiran Pelanggan"],
        "customers_last_visit_lbl": ["en": "Last Visit", "th": "มาล่าสุด", "zh": "最近到访", "ja": "最終来店", "ko": "마지막 방문", "id": "Kunjungan Terakhir", "ms": "Lawatan Terakhir"],
        "customers_member_since_lbl": ["en": "Member Since", "th": "เป็นสมาชิกตั้งแต่", "zh": "注册时间", "ja": "加入日", "ko": "가입일", "id": "Anggota Sejak", "ms": "Ahli Sejak"],
        "customers_new_btn": ["en": "New Customer", "th": "ลูกค้าใหม่", "zh": "新客户", "ja": "新規顧客", "ko": "신규 고객", "id": "Pelanggan Baru", "ms": "Pelanggan Baru"],
        "customers_no_orders_yet": ["en": "No orders yet", "th": "ยังไม่มีออเดอร์", "zh": "暂无订单", "ja": "注文なし", "ko": "아직 주문 없음", "id": "Belum ada pesanan", "ms": "Belum ada pesanan"],
        "customers_none_found": ["en": "No customers found", "th": "ไม่พบลูกค้า", "zh": "未找到客户", "ja": "顧客が見つかりません", "ko": "고객을 찾을 수 없습니다", "id": "Pelanggan tidak ditemukan", "ms": "Pelanggan tidak ditemui"],
        "customers_recent_orders_header": ["en": "Recent Orders", "th": "ออเดอร์ล่าสุด", "zh": "最近订单", "ja": "最近の注文", "ko": "최근 주문", "id": "Pesanan Terbaru", "ms": "Pesanan Terkini"],
        "customers_select_desc": ["en": "Search or select a customer", "th": "ค้นหาหรือเลือกลูกค้า", "zh": "搜索或选择客户", "ja": "顧客を検索または選択", "ko": "고객 검색 또는 선택", "id": "Cari atau pilih pelanggan", "ms": "Cari atau pilih pelanggan"],
        "customers_select_title": ["en": "Select Customer", "th": "เลือกลูกค้า", "zh": "选择客户", "ja": "顧客を選択", "ko": "고객 선택", "id": "Pilih Pelanggan", "ms": "Pilih Pelanggan"],
        "customers_selected_lbl": ["en": "Selected", "th": "เลือกแล้ว", "zh": "已选择", "ja": "選択済み", "ko": "선택됨", "id": "Terpilih", "ms": "Dipilih"],
        // MARK: - Auth & Security
        "auth_brand_sub": ["en": "Restaurant Management System", "th": "ระบบจัดการร้านอาหาร", "zh": "餐厅管理系统", "ja": "レストラン管理システム", "ko": "레스토랑 관리 시스템", "id": "Sistem Manajemen Restoran", "ms": "Sistem Pengurusan Restoran"],
        "auth_error_invalid_credentials": ["en": "Invalid email or password", "th": "อีเมลหรือรหัสผ่านไม่ถูกต้อง", "zh": "邮箱或密码错误", "ja": "メールアドレスまたはパスワードが無効です", "ko": "이메일 또는 비밀번호가 올바르지 않습니다", "id": "Email atau kata sandi salah", "ms": "E-mel atau kata laluan tidak sah"],
        "auth_error_invalid_email": ["en": "Invalid email format", "th": "รูปแบบอีเมลไม่ถูกต้อง", "zh": "邮箱格式无效", "ja": "メール形式が無効です", "ko": "이메일 형식이 올바르지 않습니다", "id": "Format email tidak valid", "ms": "Format e-mel tidak sah"],
        "auth_error_mismatched_passwords": ["en": "Passwords do not match", "th": "รหัสผ่านไม่ตรงกัน", "zh": "密码不匹配", "ja": "パスワードが一致しません", "ko": "비밀번호가 일치하지 않습니다", "id": "Kata sandi tidak cocok", "ms": "Kata laluan tidak sepadan"],
        "auth_error_short_password": ["en": "Password must be at least 6 characters", "th": "รหัสผ่านต้องมีอย่างน้อย 6 ตัวอักษร", "zh": "密码至少需要6个字符", "ja": "パスワードは6文字以上必要です", "ko": "비밀번호는 최소 6자 이상이어야 합니다", "id": "Kata sandi minimal 6 karakter", "ms": "Kata laluan mesti sekurang-kurangnya 6 aksara"],
        "auth_error_signup_failed": ["en": "Sign up failed. Please try again.", "th": "สมัครไม่สำเร็จ กรุณาลองอีกครั้ง", "zh": "注册失败，请重试", "ja": "登録に失敗しました。もう一度お試しください", "ko": "가입에 실패했습니다. 다시 시도하세요", "id": "Pendaftaran gagal. Silakan coba lagi.", "ms": "Pendaftaran gagal. Sila cuba lagi."],
        "auth_reset_failed": ["en": "Password reset failed", "th": "รีเซ็ตรหัสผ่านไม่สำเร็จ", "zh": "密码重置失败", "ja": "パスワードリセットに失敗しました", "ko": "비밀번호 재설정 실패", "id": "Reset kata sandi gagal", "ms": "Tetap semula kata laluan gagal"],
        "auth_reset_success_template": ["en": "Reset link sent to %@", "th": "ส่งลิงก์รีเซ็ตไปที่ %@", "zh": "重置链接已发送至 %@", "ja": "リセットリンクを %@ に送信しました", "ko": "재설정 링크가 %@로 전송되었습니다", "id": "Tautan reset dikirim ke %@", "ms": "Pautan tetap semula dihantar ke %@"],
        "manager_approval_required": ["en": "Manager Approval Required", "th": "ต้องได้รับอนุมัติจากผู้จัดการ", "zh": "需要经理批准", "ja": "マネージャーの承認が必要", "ko": "관리자 승인 필요", "id": "Perlu Persetujuan Manajer", "ms": "Kelulusan Pengurus Diperlukan"],
        "manager_auth_desc": ["en": "Enter manager PIN to authorize this action", "th": "ใส่ PIN ผู้จัดการเพื่ออนุมัติ", "zh": "输入管理员PIN以授权", "ja": "マネージャーPINを入力して承認", "ko": "관리자 PIN을 입력하여 승인", "id": "Masukkan PIN manajer untuk otorisasi", "ms": "Masukkan PIN pengurus untuk kelulusan"],
        "manager_auth_error_invalid": ["en": "Invalid PIN. Please try again.", "th": "PIN ไม่ถูกต้อง กรุณาลองอีกครั้ง", "zh": "PIN无效，请重试", "ja": "PINが無効です。もう一度お試しください", "ko": "PIN이 올바르지 않습니다. 다시 시도하세요", "id": "PIN tidak valid. Silakan coba lagi.", "ms": "PIN tidak sah. Sila cuba lagi."],
        "manager_auth_title": ["en": "Manager Authorization", "th": "ยืนยันตัวตนผู้จัดการ", "zh": "管理员授权", "ja": "マネージャー認証", "ko": "관리자 인증", "id": "Otorisasi Manajer", "ms": "Kebenaran Pengurus"],
        // MARK: - Recipe
        "recipe_analysis_header": ["en": "Recipe Analysis", "th": "วิเคราะห์สูตร", "zh": "食谱分析", "ja": "レシピ分析", "ko": "레시피 분석", "id": "Analisis Resep", "ms": "Analisis Resipi"],
        "recipe_auto_create_tag": ["en": "Auto-Created", "th": "สร้างอัตโนมัติ", "zh": "自动创建", "ja": "自動作成", "ko": "자동 생성", "id": "Dibuat Otomatis", "ms": "Dicipta Automatik"],
        "recipe_based": ["en": "Recipe Based", "th": "ตามสูตร", "zh": "基于食谱", "ja": "レシピベース", "ko": "레시피 기반", "id": "Berbasis Resep", "ms": "Berdasarkan Resipi"],
        "recipe_components_header": ["en": "Recipe Components", "th": "ส่วนประกอบสูตร", "zh": "食谱组成", "ja": "レシピ構成", "ko": "레시피 구성 요소", "id": "Komponen Resep", "ms": "Komponen Resipi"],
        "recipe_food_cost_pct": ["en": "Food Cost %", "th": "% ต้นทุนอาหาร", "zh": "食材成本 %", "ja": "原価率 %", "ko": "식재료 원가 %", "id": "Biaya Bahan %", "ms": "Kos Makanan %"],
        "recipe_gross_margin_pct": ["en": "Gross Margin %", "th": "% กำไรขั้นต้น", "zh": "毛利率 %", "ja": "粗利率 %", "ko": "매출 총이익률 %", "id": "Margin Kotor %", "ms": "Margin Kasar %"],
        "recipe_no_ingredients": ["en": "No Ingredients Added", "th": "ยังไม่ได้เพิ่มวัตถุดิบ", "zh": "尚未添加原料", "ja": "材料が追加されていません", "ko": "재료가 추가되지 않았습니다", "id": "Belum Ada Bahan Ditambahkan", "ms": "Belum Ada Bahan Ditambah"],
        "recipe_parts_section": ["en": "Parts/Ingredients", "th": "ส่วนผสม/วัตถุดิบ", "zh": "配料/原料", "ja": "パーツ/材料", "ko": "부품/재료", "id": "Bagian/Bahan", "ms": "Bahagian/Bahan"],
        "recipe_settings_title": ["en": "Recipe Settings", "th": "ตั้งค่าสูตร", "zh": "食谱设置", "ja": "レシピ設定", "ko": "레시피 설정", "id": "Pengaturan Resep", "ms": "Tetapan Resipi"],
        // MARK: - Catalog & Menu
        "catalog_categories": ["en": "Categories", "th": "หมวดหมู่", "zh": "分类", "ja": "カテゴリー", "ko": "카테고리", "id": "Kategori", "ms": "Kategori"],
        "catalog_extras": ["en": "Extras", "th": "ส่วนเสริม", "zh": "附加项", "ja": "エクストラ", "ko": "추가 옵션", "id": "Ekstra", "ms": "Tambahan"],
        "catalog_finished_good": ["en": "Finished Good", "th": "สินค้าสำเร็จรูป", "zh": "成品", "ja": "完成品", "ko": "완제품", "id": "Barang Jadi", "ms": "Barang Siap"],
        "catalog_not_tracked": ["en": "Not Tracked", "th": "ไม่ติดตาม", "zh": "不跟踪", "ja": "追跡なし", "ko": "미추적", "id": "Tidak Dilacak", "ms": "Tidak Dijejak"],
        "catalog_recipe_based": ["en": "Recipe Based", "th": "ตามสูตร", "zh": "基于食谱", "ja": "レシピベース", "ko": "레시피 기반", "id": "Berbasis Resep", "ms": "Berdasarkan Resipi"],
        "category_description": ["en": "Description", "th": "รายละเอียด", "zh": "描述", "ja": "説明", "ko": "설명", "id": "Deskripsi", "ms": "Penerangan"],
        "category_header": ["en": "Category", "th": "หมวดหมู่", "zh": "分类", "ja": "カテゴリー", "ko": "카테고리", "id": "Kategori", "ms": "Kategori"],
        "category_info_title": ["en": "Category Info", "th": "ข้อมูลหมวดหมู่", "zh": "分类信息", "ja": "カテゴリー情報", "ko": "카테고리 정보", "id": "Info Kategori", "ms": "Info Kategori"],
        "category_location_header": ["en": "Location", "th": "ตำแหน่ง", "zh": "位置", "ja": "場所", "ko": "위치", "id": "Lokasi", "ms": "Lokasi"],
        "category_placeholder": ["en": "Select category", "th": "เลือกหมวดหมู่", "zh": "选择分类", "ja": "カテゴリーを選択", "ko": "카테고리 선택", "id": "Pilih kategori", "ms": "Pilih kategori"],
        "menu_engineering_desc": ["en": "Analyze menu item profitability and popularity", "th": "วิเคราะห์ความสามารถทำกำไรและความนิยมของเมนู", "zh": "分析菜品盈利能力和受欢迎程度", "ja": "メニュー収益性と人気度を分析", "ko": "메뉴 수익성 및 인기도 분석", "id": "Analisis profitabilitas dan popularitas menu", "ms": "Analisis keuntungan dan populariti menu"],
        "menu_engineering_matrix_lbl": ["en": "Menu Matrix", "th": "เมทริกซ์เมนู", "zh": "菜单矩阵", "ja": "メニューマトリクス", "ko": "메뉴 매트릭스", "id": "Matriks Menu", "ms": "Matriks Menu"],
        "menu_item_modifier_groups": ["en": "Modifier Groups", "th": "กลุ่มตัวเลือก", "zh": "修饰组", "ja": "修飾グループ", "ko": "수정자 그룹", "id": "Grup Modifier", "ms": "Kumpulan Pengubah"],
        "menu_items": ["en": "Menu Items", "th": "รายการเมนู", "zh": "菜单项", "ja": "メニュー商品", "ko": "메뉴 항목", "id": "Item Menu", "ms": "Item Menu"],
        "menu_profitability": ["en": "Menu Profitability", "th": "ความสามารถทำกำไรของเมนู", "zh": "菜单盈利", "ja": "メニュー収益性", "ko": "메뉴 수익성", "id": "Profitabilitas Menu", "ms": "Keuntungan Menu"],
        "modifier_group_setup": ["en": "Modifier Group Setup", "th": "ตั้งค่ากลุ่มตัวเลือก", "zh": "修饰组设置", "ja": "修飾グループ設定", "ko": "수정자 그룹 설정", "id": "Pengaturan Grup Modifier", "ms": "Tetapan Kumpulan Pengubah"],
        "modifier_options_title": ["en": "Modifier Options", "th": "ตัวเลือก", "zh": "修饰选项", "ja": "オプション", "ko": "옵션", "id": "Opsi Modifier", "ms": "Pilihan Pengubah"],
        "modifier_revenue_lbl": ["en": "Modifier Revenue", "th": "รายได้จากตัวเลือก", "zh": "修饰收入", "ja": "修飾売上", "ko": "수정자 매출", "id": "Pendapatan Modifier", "ms": "Hasil Pengubah"],
        "product_category_label": ["en": "Category", "th": "หมวดหมู่", "zh": "分类", "ja": "カテゴリー", "ko": "카테고리", "id": "Kategori", "ms": "Kategori"],
        "product_details_section": ["en": "Product Details", "th": "รายละเอียดสินค้า", "zh": "产品详情", "ja": "商品詳細", "ko": "상품 상세", "id": "Detail Produk", "ms": "Butiran Produk"],
        "product_image_title": ["en": "Product Image", "th": "รูปสินค้า", "zh": "产品图片", "ja": "商品画像", "ko": "상품 이미지", "id": "Gambar Produk", "ms": "Imej Produk"],
        "product_name_header": ["en": "Product Name", "th": "ชื่อสินค้า", "zh": "产品名称", "ja": "商品名", "ko": "상품명", "id": "Nama Produk", "ms": "Nama Produk"],
        "product_sales_report_title": ["en": "Product Sales Report", "th": "รายงานยอดขายสินค้า", "zh": "产品销售报告", "ja": "商品売上レポート", "ko": "상품 매출 보고서", "id": "Laporan Penjualan Produk", "ms": "Laporan Jualan Produk"],
        "product_tab_details": ["en": "Details", "th": "รายละเอียด", "zh": "详情", "ja": "詳細", "ko": "상세", "id": "Detail", "ms": "Butiran"],
        "product_tab_extras": ["en": "Extras", "th": "ส่วนเสริม", "zh": "附加", "ja": "エクストラ", "ko": "추가", "id": "Ekstra", "ms": "Tambahan"],
        "product_tab_recipe": ["en": "Recipe", "th": "สูตร", "zh": "食谱", "ja": "レシピ", "ko": "레시피", "id": "Resep", "ms": "Resipi"],
        // MARK: - Promotions & Discounts
        "discount_amount": ["en": "Discount Amount", "th": "จำนวนส่วนลด", "zh": "折扣金额", "ja": "割引額", "ko": "할인 금액", "id": "Jumlah Diskon", "ms": "Jumlah Diskaun"],
        "discount_applied": ["en": "Discount Applied", "th": "ใช้ส่วนลดแล้ว", "zh": "已应用折扣", "ja": "割引適用済み", "ko": "할인 적용됨", "id": "Diskon Diterapkan", "ms": "Diskaun Digunakan"],
        "discount_type": ["en": "Discount Type", "th": "ประเภทส่วนลด", "zh": "折扣类型", "ja": "割引タイプ", "ko": "할인 유형", "id": "Tipe Diskon", "ms": "Jenis Diskaun"],
        "discount_val_amt_lbl": ["en": "Amount (฿)", "th": "จำนวน (฿)", "zh": "金额 (฿)", "ja": "金額 (฿)", "ko": "금액 (฿)", "id": "Jumlah (฿)", "ms": "Jumlah (฿)"],
        "discount_val_pct_lbl": ["en": "Percentage (%)", "th": "เปอร์เซ็นต์ (%)", "zh": "百分比 (%)", "ja": "パーセント (%)", "ko": "퍼센트 (%)", "id": "Persentase (%)", "ms": "Peratusan (%)"],
        "discount_value": ["en": "Discount Value", "th": "มูลค่าส่วนลด", "zh": "折扣值", "ja": "割引値", "ko": "할인 값", "id": "Nilai Diskon", "ms": "Nilai Diskaun"],
        "discounts_given_lbl": ["en": "Discounts Given", "th": "ส่วนลดที่ให้", "zh": "已给予折扣", "ja": "割引提供額", "ko": "제공된 할인", "id": "Diskon Diberikan", "ms": "Diskaun Diberikan"],
        "discounts_title": ["en": "Discounts", "th": "ส่วนลด", "zh": "折扣", "ja": "割引", "ko": "할인", "id": "Diskon", "ms": "Diskaun"],
        "promo_delete_confirm_msg": ["en": "Are you sure you want to delete this promotion?", "th": "คุณแน่ใจหรือว่าต้องการลบโปรโมชั่นนี้?", "zh": "确定要删除此促销活动吗?", "ja": "このプロモーションを削除しますか?", "ko": "이 프로모션을 삭제하시겠습니까?", "id": "Yakin ingin menghapus promosi ini?", "ms": "Pasti mahu padam promosi ini?"],
        "promo_description": ["en": "Description", "th": "รายละเอียด", "zh": "描述", "ja": "説明", "ko": "설명", "id": "Deskripsi", "ms": "Penerangan"],
        "promo_type_buy_x_get_y": ["en": "Buy X Get Y", "th": "ซื้อ X แถม Y", "zh": "买X送Y", "ja": "X買ってY無料", "ko": "X개 사면 Y개 무료", "id": "Beli X Dapat Y", "ms": "Beli X Dapat Y"],
        "promo_type_buy_x_pay_y": ["en": "Buy X Pay Y", "th": "ซื้อ X จ่าย Y", "zh": "买X付Y", "ja": "X買ってY支払い", "ko": "X개 사고 Y개 가격", "id": "Beli X Bayar Y", "ms": "Beli X Bayar Y"],
        "promo_type_label": ["en": "Promotion Type", "th": "ประเภทโปรโมชั่น", "zh": "促销类型", "ja": "プロモーションタイプ", "ko": "프로모션 유형", "id": "Tipe Promosi", "ms": "Jenis Promosi"],
        "promo_update_failed": ["en": "Failed to update promotion", "th": "อัปเดตโปรโมชั่นไม่สำเร็จ", "zh": "更新促销失败", "ja": "プロモーション更新に失敗", "ko": "프로모션 업데이트 실패", "id": "Gagal memperbarui promosi", "ms": "Gagal mengemas kini promosi"],
        "promotions_auto_apply": ["en": "Auto-Apply", "th": "ใช้อัตโนมัติ", "zh": "自动应用", "ja": "自動適用", "ko": "자동 적용", "id": "Terapkan Otomatis", "ms": "Guna Automatik"],
        // MARK: - Gift Cards
        "gift_card_redeem": ["en": "Redeem Gift Card", "th": "แลกบัตรของขวัญ", "zh": "兑换礼品卡", "ja": "ギフトカード利用", "ko": "기프트카드 사용", "id": "Tukar Kartu Hadiah", "ms": "Tebus Kad Hadiah"],
        "gift_card_topup": ["en": "Top Up Gift Card", "th": "เติมเงินบัตรของขวัญ", "zh": "充值礼品卡", "ja": "ギフトカードチャージ", "ko": "기프트카드 충전", "id": "Isi Ulang Kartu Hadiah", "ms": "Tambah Nilai Kad Hadiah"],
        "gift_card_void": ["en": "Void Gift Card", "th": "ยกเลิกบัตรของขวัญ", "zh": "作废礼品卡", "ja": "ギフトカード無効化", "ko": "기프트카드 무효화", "id": "Batalkan Kartu Hadiah", "ms": "Batal Kad Hadiah"],
        "gift_cards": ["en": "Gift Cards", "th": "บัตรของขวัญ", "zh": "礼品卡", "ja": "ギフトカード", "ko": "기프트카드", "id": "Kartu Hadiah", "ms": "Kad Hadiah"],
        "gift_cards_title": ["en": "Gift Cards", "th": "บัตรของขวัญ", "zh": "礼品卡", "ja": "ギフトカード", "ko": "기프트카드", "id": "Kartu Hadiah", "ms": "Kad Hadiah"],
        // MARK: - Payroll & Shifts
        "labor_cost_breakdown_lbl": ["en": "Labor Cost Breakdown", "th": "รายละเอียดต้นทุนแรงงาน", "zh": "人工成本明细", "ja": "人件費内訳", "ko": "인건비 내역", "id": "Rincian Biaya Tenaga Kerja", "ms": "Pecahan Kos Buruh"],
        "labor_cost_header": ["en": "Labor Cost", "th": "ต้นทุนแรงงาน", "zh": "人工成本", "ja": "人件費", "ko": "인건비", "id": "Biaya Tenaga Kerja", "ms": "Kos Buruh"],
        "labor_cost_pct_lbl": ["en": "Labor Cost %", "th": "% ต้นทุนแรงงาน", "zh": "人工成本 %", "ja": "人件費率 %", "ko": "인건비 %", "id": "Biaya Tenaga Kerja %", "ms": "Kos Buruh %"],
        "labor_hours_lbl": ["en": "Labor Hours", "th": "ชั่วโมงทำงาน", "zh": "工时", "ja": "労働時間", "ko": "근무 시간", "id": "Jam Kerja", "ms": "Jam Kerja"],
        "ot_hours_header": ["en": "OT Hours", "th": "ชั่วโมง OT", "zh": "加班时数", "ja": "残業時間", "ko": "초과 근무 시간", "id": "Jam Lembur", "ms": "Jam Kerja Lebih"],
        "ot_pay_label": ["en": "OT Pay", "th": "ค่า OT", "zh": "加班费", "ja": "残業代", "ko": "초과 근무 수당", "id": "Gaji Lembur", "ms": "Bayaran Kerja Lebih"],
        "payroll_engine_title": ["en": "Payroll Engine", "th": "ระบบเงินเดือน", "zh": "薪资引擎", "ja": "給与計算", "ko": "급여 엔진", "id": "Mesin Penggajian", "ms": "Enjin Gaji"],
        "payroll_period_header": ["en": "Pay Period", "th": "งวดเงินเดือน", "zh": "薪资周期", "ja": "給与期間", "ko": "급여 기간", "id": "Periode Gaji", "ms": "Tempoh Gaji"],
        "payroll_report_title": ["en": "Payroll Report", "th": "รายงานเงินเดือน", "zh": "薪资报告", "ja": "給与レポート", "ko": "급여 보고서", "id": "Laporan Penggajian", "ms": "Laporan Gaji"],
        "payroll_export_pdf_btn": ["en": "Export PDF", "th": "ส่งออก PDF", "zh": "导出 PDF", "ja": "PDFをエクスポート", "ko": "PDF 내보내기", "id": "Ekspor PDF", "ms": "Eksport PDF"],
        "payroll_export_generating": ["en": "Generating PDF...", "th": "กำลังสร้าง PDF...", "zh": "正在生成 PDF...", "ja": "PDFを生成中...", "ko": "PDF 생성 중...", "id": "Membuat PDF...", "ms": "Menjana PDF..."],
        "payroll_export_failed": ["en": "Failed to generate PDF", "th": "สร้าง PDF ไม่สำเร็จ", "zh": "生成 PDF 失败", "ja": "PDFの生成に失敗しました", "ko": "PDF 생성 실패", "id": "Gagal membuat PDF", "ms": "Gagal menjana PDF"],
        "payroll_shifts_title": ["en": "Payroll Shifts", "th": "กะเงินเดือน", "zh": "薪资班次", "ja": "給与シフト", "ko": "급여 교대", "id": "Shift Penggajian", "ms": "Syif Gaji"],
        "schedule_shift": ["en": "Schedule Shift", "th": "กำหนดกะ", "zh": "排班", "ja": "シフト予約", "ko": "교대 일정", "id": "Jadwalkan Shift", "ms": "Jadualkan Syif"],
        "shift_closed": ["en": "Shift Closed", "th": "ปิดกะแล้ว", "zh": "班次已关闭", "ja": "シフト終了", "ko": "교대 종료", "id": "Shift Ditutup", "ms": "Syif Ditutup"],
        "shift_duration_header": ["en": "Shift Duration", "th": "ระยะเวลากะ", "zh": "班次时长", "ja": "シフト時間", "ko": "교대 시간", "id": "Durasi Shift", "ms": "Tempoh Syif"],
        "shift_history_tab": ["en": "Shift History", "th": "ประวัติกะ", "zh": "班次历史", "ja": "シフト履歴", "ko": "교대 내역", "id": "Riwayat Shift", "ms": "Sejarah Syif"],
        "shift_id_label": ["en": "Shift ID", "th": "รหัสกะ", "zh": "班次ID", "ja": "シフトID", "ko": "교대 ID", "id": "ID Shift", "ms": "ID Syif"],
        "shift_planner": ["en": "Shift Planner", "th": "วางแผนกะ", "zh": "排班计划", "ja": "シフト計画", "ko": "교대 계획", "id": "Perencana Shift", "ms": "Perancang Syif"],
        "shift_reconciliation_title": ["en": "Shift Reconciliation", "th": "กระทบยอดกะ", "zh": "班次对账", "ja": "シフト精算", "ko": "교대 정산", "id": "Rekonsiliasi Shift", "ms": "Penyesuaian Syif"],
        "shift_reports": ["en": "Shift Reports", "th": "รายงานกะ", "zh": "班次报告", "ja": "シフトレポート", "ko": "교대 보고서", "id": "Laporan Shift", "ms": "Laporan Syif"],
        "shift_running": ["en": "Shift Running", "th": "กะกำลังทำงาน", "zh": "班次进行中", "ja": "シフト稼働中", "ko": "교대 진행 중", "id": "Shift Berjalan", "ms": "Syif Berjalan"],
        "shift_running_title": ["en": "Current Shift", "th": "กะปัจจุบัน", "zh": "当前班次", "ja": "現在のシフト", "ko": "현재 교대", "id": "Shift Saat Ini", "ms": "Syif Semasa"],
        "timecard_log": ["en": "Timecard Log", "th": "บันทึกบัตรเวลา", "zh": "考勤记录", "ja": "タイムカードログ", "ko": "타임카드 기록", "id": "Log Kartu Waktu", "ms": "Log Kad Masa"],
        // MARK: - Employees
        "biometrics_faceid_scanner_header": ["en": "Biometric Scanner", "th": "เครื่องสแกนไบโอเมตริก", "zh": "生物识别扫描", "ja": "生体認証スキャナー", "ko": "생체 인식 스캐너", "id": "Pemindai Biometrik", "ms": "Pengimbas Biometrik"],
        "employee_header": ["en": "Employee", "th": "พนักงาน", "zh": "员工", "ja": "従業員", "ko": "직원", "id": "Karyawan", "ms": "Pekerja"],
        "employee_header_title": ["en": "Employee Information", "th": "ข้อมูลพนักงาน", "zh": "员工信息", "ja": "従業員情報", "ko": "직원 정보", "id": "Informasi Karyawan", "ms": "Maklumat Pekerja"],
        "employee_hours": ["en": "Employee Hours", "th": "ชั่วโมงพนักงาน", "zh": "员工工时", "ja": "従業員勤務時間", "ko": "직원 근무시간", "id": "Jam Karyawan", "ms": "Jam Pekerja"],
        "employee_name": ["en": "Employee Name", "th": "ชื่อพนักงาน", "zh": "员工姓名", "ja": "従業員名", "ko": "직원 이름", "id": "Nama Karyawan", "ms": "Nama Pekerja"],
        "employee_shifts": ["en": "Employee Shifts", "th": "กะพนักงาน", "zh": "员工班次", "ja": "従業員シフト", "ko": "직원 교대", "id": "Shift Karyawan", "ms": "Syif Pekerja"],
        "face_id_enroll_desc": ["en": "Register your face for clock-in", "th": "ลงทะเบียนใบหน้าสำหรับลงเวลา", "zh": "注册人脸用于打卡", "ja": "出勤用に顔を登録", "ko": "출근용 얼굴 등록", "id": "Daftarkan wajah untuk absensi", "ms": "Daftarkan muka untuk daftar masuk"],
        "face_id_not_registered_status": ["en": "Not Registered", "th": "ยังไม่ลงทะเบียน", "zh": "未注册", "ja": "未登録", "ko": "미등록", "id": "Belum Terdaftar", "ms": "Belum Didaftarkan"],
        "face_id_registered_status": ["en": "Registered", "th": "ลงทะเบียนแล้ว", "zh": "已注册", "ja": "登録済み", "ko": "등록됨", "id": "Terdaftar", "ms": "Didaftarkan"],
        "face_scanner_biometrics_title": ["en": "Face Recognition", "th": "จดจำใบหน้า", "zh": "人脸识别", "ja": "顔認識", "ko": "안면 인식", "id": "Pengenalan Wajah", "ms": "Pengecaman Muka"],
        "selfie_scan_label": ["en": "Scan Face", "th": "สแกนใบหน้า", "zh": "扫描人脸", "ja": "顔スキャン", "ko": "얼굴 스캔", "id": "Pindai Wajah", "ms": "Imbas Muka"],
        // MARK: - Store & Branch
        "branch_address_label": ["en": "Branch Address", "th": "ที่อยู่สาขา", "zh": "分店地址", "ja": "支店住所", "ko": "지점 주소", "id": "Alamat Cabang", "ms": "Alamat Cawangan"],
        "branch_create_info_desc": ["en": "Fill in the branch details below", "th": "กรอกรายละเอียดสาขาด้านล่าง", "zh": "请填写以下分店信息", "ja": "以下の支店情報を入力", "ko": "아래 지점 정보를 입력하세요", "id": "Isi detail cabang di bawah", "ms": "Isi butiran cawangan di bawah"],
        "branch_mgmt_desc": ["en": "Manage your store branches", "th": "จัดการสาขาของคุณ", "zh": "管理您的门店分店", "ja": "店舗支店を管理", "ko": "매장 지점 관리", "id": "Kelola cabang toko Anda", "ms": "Urus cawangan kedai anda"],
        "branch_mgmt_title": ["en": "Branch Management", "th": "จัดการสาขา", "zh": "分店管理", "ja": "支店管理", "ko": "지점 관리", "id": "Manajemen Cabang", "ms": "Pengurusan Cawangan"],
        "branch_name_label": ["en": "Branch Name", "th": "ชื่อสาขา", "zh": "分店名称", "ja": "支店名", "ko": "지점 이름", "id": "Nama Cabang", "ms": "Nama Cawangan"],
        "branch_phone_label": ["en": "Branch Phone", "th": "เบอร์โทรสาขา", "zh": "分店电话", "ja": "支店電話", "ko": "지점 전화", "id": "Telepon Cabang", "ms": "Telefon Cawangan"],
        "branch_preview_lbl": ["en": "Preview", "th": "ตัวอย่าง", "zh": "预览", "ja": "プレビュー", "ko": "미리보기", "id": "Pratinjau", "ms": "Pratonton"],
        "branch_select_store_btn": ["en": "Select Store", "th": "เลือกร้าน", "zh": "选择门店", "ja": "店舗を選択", "ko": "매장 선택", "id": "Pilih Toko", "ms": "Pilih Kedai"],
        "manage_branches": ["en": "Manage Branches", "th": "จัดการสาขา", "zh": "管理分店", "ja": "支店管理", "ko": "지점 관리", "id": "Kelola Cabang", "ms": "Urus Cawangan"],
        "store_address": ["en": "Store Address", "th": "ที่อยู่ร้าน", "zh": "店铺地址", "ja": "店舗住所", "ko": "매장 주소", "id": "Alamat Toko", "ms": "Alamat Kedai"],
        "store_branches_title": ["en": "Branches", "th": "สาขา", "zh": "分店", "ja": "支店", "ko": "지점", "id": "Cabang", "ms": "Cawangan"],
        "store_credit": ["en": "Store Credit", "th": "เครดิตร้าน", "zh": "店铺余额", "ja": "ストアクレジット", "ko": "매장 크레딧", "id": "Kredit Toko", "ms": "Kredit Kedai"],
        "store_phone": ["en": "Store Phone", "th": "เบอร์โทรร้าน", "zh": "店铺电话", "ja": "店舗電話", "ko": "매장 전화", "id": "Telepon Toko", "ms": "Telefon Kedai"],
        "store_receipt_footer": ["en": "Receipt Footer", "th": "ท้ายใบเสร็จ", "zh": "收据页脚", "ja": "レシートフッター", "ko": "영수증 하단", "id": "Footer Struk", "ms": "Pengaki Resit"],
        "store_receipt_header": ["en": "Receipt Header", "th": "หัวใบเสร็จ", "zh": "收据页头", "ja": "レシートヘッダー", "ko": "영수증 상단", "id": "Header Struk", "ms": "Pengepala Resit"],
        "store_tax_id": ["en": "Tax ID", "th": "เลขประจำตัวผู้เสียภาษี", "zh": "税号", "ja": "税ID", "ko": "세금 ID", "id": "NPWP", "ms": "No. Cukai"],
        "store_website": ["en": "Website", "th": "เว็บไซต์", "zh": "网站", "ja": "ウェブサイト", "ko": "웹사이트", "id": "Situs Web", "ms": "Laman Web"],
        // MARK: - Supplier
        "supplier_address": ["en": "Supplier Address", "th": "ที่อยู่ซัพพลายเออร์", "zh": "供应商地址", "ja": "仕入先住所", "ko": "공급업체 주소", "id": "Alamat Pemasok", "ms": "Alamat Pembekal"],
        "supplier_association": ["en": "Supplier Association", "th": "ซัพพลายเออร์ที่เกี่ยวข้อง", "zh": "供应商关联", "ja": "仕入先関連", "ko": "공급업체 연관", "id": "Asosiasi Pemasok", "ms": "Persatuan Pembekal"],
        "supplier_contact_details_section": ["en": "Contact Details", "th": "ข้อมูลติดต่อ", "zh": "联系方式", "ja": "連絡先", "ko": "연락처 정보", "id": "Detail Kontak", "ms": "Butiran Hubungan"],
        "supplier_contact_person": ["en": "Contact Person", "th": "ผู้ติดต่อ", "zh": "联系人", "ja": "担当者", "ko": "담당자", "id": "Kontak Person", "ms": "Orang Hubungan"],
        "supplier_email_address": ["en": "Email", "th": "อีเมล", "zh": "邮箱", "ja": "メール", "ko": "이메일", "id": "Email", "ms": "E-mel"],
        "supplier_label": ["en": "Supplier", "th": "ซัพพลายเออร์", "zh": "供应商", "ja": "仕入先", "ko": "공급업체", "id": "Pemasok", "ms": "Pembekal"],
        "supplier_phone_number": ["en": "Phone Number", "th": "เบอร์โทร", "zh": "电话号码", "ja": "電話番号", "ko": "전화번호", "id": "Nomor Telepon", "ms": "Nombor Telefon"],
        "supplier_profile_details": ["en": "Supplier Profile", "th": "โปรไฟล์ซัพพลายเออร์", "zh": "供应商资料", "ja": "仕入先プロフィール", "ko": "공급업체 프로필", "id": "Profil Pemasok", "ms": "Profil Pembekal"],
        // MARK: - Bulk Operations
        "bulk_delete_alert_title": ["en": "Delete Items", "th": "ลบรายการ", "zh": "删除商品", "ja": "商品削除", "ko": "항목 삭제", "id": "Hapus Item", "ms": "Padam Item"],
        "bulk_delete_confirm_message": ["en": "Are you sure you want to delete the selected items?", "th": "คุณแน่ใจหรือว่าต้องการลบรายการที่เลือก?", "zh": "确定要删除选中的商品吗?", "ja": "選択した商品を削除しますか?", "ko": "선택한 항목을 삭제하시겠습니까?", "id": "Yakin ingin menghapus item yang dipilih?", "ms": "Pasti mahu padam item yang dipilih?"],
        "bulk_receive_description": ["en": "Receive stock for multiple items at once", "th": "รับสินค้าหลายรายการพร้อมกัน", "zh": "一次性入库多个商品", "ja": "複数商品を一括入荷", "ko": "여러 항목을 한 번에 입고", "id": "Terima stok beberapa item sekaligus", "ms": "Terima stok beberapa item sekaligus"],
        "bulk_receive_info": ["en": "Select items and enter received quantities", "th": "เลือกรายการและใส่จำนวนที่รับ", "zh": "选择商品并输入收货数量", "ja": "商品を選択して受領数を入力", "ko": "항목을 선택하고 수령 수량을 입력", "id": "Pilih item dan masukkan jumlah diterima", "ms": "Pilih item dan masukkan kuantiti diterima"],
        "bulk_receive_title": ["en": "Bulk Receive", "th": "รับสินค้าจำนวนมาก", "zh": "批量入库", "ja": "一括入荷", "ko": "대량 입고", "id": "Terima Massal", "ms": "Terima Pukal"],
        "bulk_waste_description": ["en": "Record waste for multiple items at once", "th": "บันทึกของเสียหลายรายการพร้อมกัน", "zh": "一次性记录多个商品的损耗", "ja": "複数商品の廃棄を一括記録", "ko": "여러 항목의 폐기를 한 번에 기록", "id": "Catat limbah beberapa item sekaligus", "ms": "Rekod sisa beberapa item sekaligus"],
        "bulk_waste_info": ["en": "Select items and enter wasted quantities", "th": "เลือกรายการและใส่จำนวนที่เสีย", "zh": "选择商品并输入损耗数量", "ja": "商品を選択して廃棄数を入力", "ko": "항목을 선택하고 폐기 수량을 입력", "id": "Pilih item dan masukkan jumlah limbah", "ms": "Pilih item dan masukkan kuantiti sisa"],
        "bulk_waste_title": ["en": "Bulk Waste", "th": "บันทึกของเสียจำนวนมาก", "zh": "批量报损", "ja": "一括廃棄", "ko": "대량 폐기", "id": "Limbah Massal", "ms": "Sisa Pukal"],
        // MARK: - Receipt
        "receipt_footer": ["en": "Footer", "th": "ท้ายใบเสร็จ", "zh": "页脚", "ja": "フッター", "ko": "하단", "id": "Footer", "ms": "Pengaki"],
        "receipt_footer_default": ["en": "Thank you for your visit!", "th": "ขอบคุณที่มาอุดหนุน!", "zh": "感谢您的光临!", "ja": "ご来店ありがとうございます!", "ko": "방문해 주셔서 감사합니다!", "id": "Terima kasih atas kunjungan Anda!", "ms": "Terima kasih atas lawatan anda!"],
        "receipt_footer_message": ["en": "Footer Message", "th": "ข้อความท้ายใบเสร็จ", "zh": "页脚信息", "ja": "フッターメッセージ", "ko": "하단 메시지", "id": "Pesan Footer", "ms": "Mesej Pengaki"],
        "receipt_header": ["en": "Header", "th": "หัวใบเสร็จ", "zh": "页头", "ja": "ヘッダー", "ko": "상단", "id": "Header", "ms": "Pengepala"],
        "receipt_header_default": ["en": "Welcome to our restaurant!", "th": "ยินดีต้อนรับสู่ร้านอาหารของเรา!", "zh": "欢迎光临!", "ja": "当店へようこそ!", "ko": "저희 레스토랑에 오신 것을 환영합니다!", "id": "Selamat datang di restoran kami!", "ms": "Selamat datang ke restoran kami!"],
        "receipt_header_message": ["en": "Header Message", "th": "ข้อความหัวใบเสร็จ", "zh": "页头信息", "ja": "ヘッダーメッセージ", "ko": "상단 메시지", "id": "Pesan Header", "ms": "Mesej Pengepala"],
        "receipt_label": ["en": "Receipt", "th": "ใบเสร็จ", "zh": "收据", "ja": "レシート", "ko": "영수증", "id": "Struk", "ms": "Resit"],
        "receipt_no_label": ["en": "Receipt No.", "th": "เลขที่ใบเสร็จ", "zh": "收据号", "ja": "レシート番号", "ko": "영수증 번호", "id": "No. Struk", "ms": "No. Resit"],
        "receipt_printer_enabled": ["en": "Receipt Printer Enabled", "th": "เปิดเครื่องพิมพ์ใบเสร็จ", "zh": "收据打印机已启用", "ja": "レシートプリンター有効", "ko": "영수증 프린터 활성화", "id": "Printer Struk Aktif", "ms": "Pencetak Resit Aktif"],
        "receipt_sent_to_printer": ["en": "Receipt Sent to Printer", "th": "ส่งใบเสร็จไปยังเครื่องพิมพ์แล้ว", "zh": "收据已发送至打印机", "ja": "レシートをプリンターに送信しました", "ko": "영수증을 프린터로 전송했습니다", "id": "Struk Dikirim ke Printer", "ms": "Resit Dihantar ke Pencetak"],
        "receipt_title": ["en": "Receipt", "th": "ใบเสร็จ", "zh": "收据", "ja": "レシート", "ko": "영수증", "id": "Struk", "ms": "Resit"],
        // MARK: - Stock Transfer
        "transfer_choose_branch_placeholder": ["en": "Select branch", "th": "เลือกสาขา", "zh": "选择分店", "ja": "支店を選択", "ko": "지점 선택", "id": "Pilih cabang", "ms": "Pilih cawangan"],
        "transfer_choose_item_placeholder": ["en": "Select item", "th": "เลือกรายการ", "zh": "选择商品", "ja": "商品を選択", "ko": "항목 선택", "id": "Pilih item", "ms": "Pilih item"],
        "transfer_from_branch": ["en": "From Branch", "th": "จากสาขา", "zh": "从分店", "ja": "移管元支店", "ko": "보내는 지점", "id": "Dari Cabang", "ms": "Dari Cawangan"],
        "transfer_in": ["en": "Transfer In", "th": "โอนเข้า", "zh": "转入", "ja": "入庫", "ko": "이입", "id": "Transfer Masuk", "ms": "Pindahan Masuk"],
        "transfer_notes_label": ["en": "Transfer Notes", "th": "หมายเหตุการโอน", "zh": "转移备注", "ja": "移管メモ", "ko": "이동 메모", "id": "Catatan Transfer", "ms": "Nota Pindahan"],
        "transfer_out": ["en": "Transfer Out", "th": "โอนออก", "zh": "转出", "ja": "出庫", "ko": "이출", "id": "Transfer Keluar", "ms": "Pindahan Keluar"],
        "transfer_select_item": ["en": "Select Item to Transfer", "th": "เลือกรายการที่ต้องการโอน", "zh": "选择要转移的商品", "ja": "移管する商品を選択", "ko": "이동할 항목 선택", "id": "Pilih Item untuk Transfer", "ms": "Pilih Item untuk Pindahan"],
        "transfer_stock": ["en": "Transfer Stock", "th": "โอนสต็อก", "zh": "转移库存", "ja": "在庫移管", "ko": "재고 이동", "id": "Transfer Stok", "ms": "Pindahkan Stok"],
        "transfer_to_branch": ["en": "To Branch", "th": "ไปสาขา", "zh": "到分店", "ja": "移管先支店", "ko": "받는 지점", "id": "Ke Cabang", "ms": "Ke Cawangan"],
        "xfer_in": ["en": "Transfer In", "th": "โอนเข้า", "zh": "转入", "ja": "入庫", "ko": "이입", "id": "Transfer Masuk", "ms": "Pindahan Masuk"],
        "xfer_out": ["en": "Transfer Out", "th": "โอนออก", "zh": "转出", "ja": "出庫", "ko": "이출", "id": "Transfer Keluar", "ms": "Pindahan Keluar"],
        // MARK: - Reports
        "report_brand_header": ["en": "Brand Report", "th": "รายงานแบรนด์", "zh": "品牌报告", "ja": "ブランドレポート", "ko": "브랜드 보고서", "id": "Laporan Merek", "ms": "Laporan Jenama"],
        "report_disclaimer": ["en": "This report is for internal use only", "th": "รายงานนี้ใช้ภายในเท่านั้น", "zh": "此报告仅供内部使用", "ja": "本レポートは社内用です", "ko": "이 보고서는 내부용입니다", "id": "Laporan ini hanya untuk penggunaan internal", "ms": "Laporan ini untuk kegunaan dalaman sahaja"],
        "report_generated_at": ["en": "Generated at: %@", "th": "สร้างเมื่อ: %@", "zh": "生成于: %@", "ja": "生成日時: %@", "ko": "생성일시: %@", "id": "Dibuat pada: %@", "ms": "Dijana pada: %@"],
        "report_scope_lbl": ["en": "Report Scope", "th": "ขอบเขตรายงาน", "zh": "报告范围", "ja": "レポート範囲", "ko": "보고서 범위", "id": "Cakupan Laporan", "ms": "Skop Laporan"],
        "report_total_unique": ["en": "Total Unique Items", "th": "จำนวนรายการที่ไม่ซ้ำ", "zh": "唯一商品总数", "ja": "ユニーク商品合計", "ko": "고유 품목 합계", "id": "Total Item Unik", "ms": "Jumlah Item Unik"],
        "report_type": ["en": "Report Type", "th": "ประเภทรายงาน", "zh": "报告类型", "ja": "レポートタイプ", "ko": "보고서 유형", "id": "Tipe Laporan", "ms": "Jenis Laporan"],
        "z_report_header": ["en": "Z-Report", "th": "รายงาน Z", "zh": "Z-报表", "ja": "Zレポート", "ko": "Z-리포트", "id": "Laporan Z", "ms": "Laporan Z"],
        "z_report_title": ["en": "Z-Report", "th": "รายงาน Z", "zh": "Z-报表", "ja": "Zレポート", "ko": "Z-리포트", "id": "Laporan Z", "ms": "Laporan Z"],
        // MARK: - Scanner
        "scanner_camera_denied_desc": ["en": "Camera access is required for scanning. Please enable it in Settings.", "th": "ต้องอนุญาตกล้องเพื่อสแกน กรุณาเปิดในการตั้งค่า", "zh": "扫描需要相机权限，请在设置中开启", "ja": "スキャンにはカメラ権限が必要です。設定で有効にしてください", "ko": "스캔을 위해 카메라 접근이 필요합니다. 설정에서 활성화하세요", "id": "Akses kamera diperlukan untuk pemindaian. Aktifkan di Pengaturan.", "ms": "Akses kamera diperlukan untuk pengimbasan. Aktifkan di Tetapan."],
        "scanner_camera_denied_title": ["en": "Camera Access Denied", "th": "ไม่ได้รับอนุญาตใช้กล้อง", "zh": "相机权限被拒绝", "ja": "カメラアクセスが拒否されました", "ko": "카메라 접근 거부됨", "id": "Akses Kamera Ditolak", "ms": "Akses Kamera Dinafikan"],
        "scanner_manual_entry_header": ["en": "Manual Entry", "th": "กรอกเอง", "zh": "手动输入", "ja": "手動入力", "ko": "수동 입력", "id": "Input Manual", "ms": "Kemasukan Manual"],
        "scanner_manual_fallback_header": ["en": "Or Enter Manually", "th": "หรือกรอกเอง", "zh": "或手动输入", "ja": "または手動入力", "ko": "또는 수동 입력", "id": "Atau Input Manual", "ms": "Atau Masukkan Manual"],
        "scanner_quick_seed_header": ["en": "Quick Seed", "th": "เพิ่มข้อมูลเร็ว", "zh": "快速填充", "ja": "クイックシード", "ko": "빠른 데이터 추가", "id": "Pengisian Cepat", "ms": "Pengisian Pantas"],
        "scanner_sim_mode": ["en": "Simulator Mode", "th": "โหมดจำลอง", "zh": "模拟模式", "ja": "シミュレーターモード", "ko": "시뮬레이터 모드", "id": "Mode Simulator", "ms": "Mod Simulator"],
        "scanner_sim_unavailable_desc": ["en": "Camera is not available in simulator", "th": "กล้องไม่พร้อมใช้ในโหมดจำลอง", "zh": "模拟器中相机不可用", "ja": "シミュレーターではカメラを利用できません", "ko": "시뮬레이터에서는 카메라를 사용할 수 없습니다", "id": "Kamera tidak tersedia di simulator", "ms": "Kamera tidak tersedia dalam simulator"],
        // MARK: - Payments
        "payment_completed_desc": ["en": "Payment has been completed successfully", "th": "ชำระเงินเสร็จสมบูรณ์แล้ว", "zh": "支付已成功完成", "ja": "支払いが完了しました", "ko": "결제가 성공적으로 완료되었습니다", "id": "Pembayaran telah berhasil diselesaikan", "ms": "Pembayaran telah berjaya diselesaikan"],
        "payment_confirmed_success": ["en": "Payment Confirmed", "th": "ยืนยันการชำระเงินแล้ว", "zh": "支付已确认", "ja": "支払い確認済み", "ko": "결제 확인됨", "id": "Pembayaran Dikonfirmasi", "ms": "Pembayaran Disahkan"],
        "payment_label": ["en": "Payment", "th": "การชำระเงิน", "zh": "支付", "ja": "支払い", "ko": "결제", "id": "Pembayaran", "ms": "Pembayaran"],
        "payment_methods": ["en": "Payment Methods", "th": "วิธีชำระเงิน", "zh": "支付方式", "ja": "支払い方法", "ko": "결제 수단", "id": "Metode Pembayaran", "ms": "Kaedah Pembayaran"],
        "promptpay_id_prefix": ["en": "PromptPay ID", "th": "หมายเลขพร้อมเพย์", "zh": "PromptPay ID", "ja": "PromptPay ID", "ko": "PromptPay ID", "id": "ID PromptPay", "ms": "ID PromptPay"],
        "promptpay_not_configured_desc": ["en": "Please set up PromptPay in store settings", "th": "กรุณาตั้งค่าพร้อมเพย์ในตั้งค่าร้าน", "zh": "请在门店设置中配置PromptPay", "ja": "店舗設定でPromptPayを設定してください", "ko": "매장 설정에서 PromptPay를 설정하세요", "id": "Silakan atur PromptPay di pengaturan toko", "ms": "Sila tetapkan PromptPay di tetapan kedai"],
        "promptpay_not_configured_title": ["en": "PromptPay Not Configured", "th": "ยังไม่ได้ตั้งค่าพร้อมเพย์", "zh": "PromptPay 未配置", "ja": "PromptPay未設定", "ko": "PromptPay 미설정", "id": "PromptPay Belum Diatur", "ms": "PromptPay Belum Ditetapkan"],
        "promptpay_number_label": ["en": "PromptPay Number", "th": "หมายเลขพร้อมเพย์", "zh": "PromptPay号码", "ja": "PromptPay番号", "ko": "PromptPay 번호", "id": "Nomor PromptPay", "ms": "Nombor PromptPay"],
        "promptpay_qr_code_title": ["en": "PromptPay QR Code", "th": "คิวอาร์โค้ดพร้อมเพย์", "zh": "PromptPay 二维码", "ja": "PromptPay QRコード", "ko": "PromptPay QR 코드", "id": "Kode QR PromptPay", "ms": "Kod QR PromptPay"],
        // MARK: - Orders
        "order_date": ["en": "Order Date", "th": "วันที่สั่ง", "zh": "订单日期", "ja": "注文日", "ko": "주문일", "id": "Tanggal Pesanan", "ms": "Tarikh Pesanan"],
        "order_discounts": ["en": "Order Discounts", "th": "ส่วนลดออเดอร์", "zh": "订单折扣", "ja": "注文割引", "ko": "주문 할인", "id": "Diskon Pesanan", "ms": "Diskaun Pesanan"],
        "order_held": ["en": "Order Held", "th": "พักออเดอร์", "zh": "订单挂起", "ja": "注文保留", "ko": "주문 보류", "id": "Pesanan Ditahan", "ms": "Pesanan Ditahan"],
        "order_items": ["en": "Order Items", "th": "รายการในออเดอร์", "zh": "订单商品", "ja": "注文商品", "ko": "주문 상품", "id": "Item Pesanan", "ms": "Item Pesanan"],
        "order_number": ["en": "Order Number", "th": "เลขที่ออเดอร์", "zh": "订单号", "ja": "注文番号", "ko": "주문 번호", "id": "Nomor Pesanan", "ms": "Nombor Pesanan"],
        "order_tax_lines": ["en": "Tax Lines", "th": "รายการภาษี", "zh": "税项", "ja": "税明細", "ko": "세금 항목", "id": "Baris Pajak", "ms": "Baris Cukai"],
        "order_void": ["en": "Void Order", "th": "ยกเลิกออเดอร์", "zh": "作废订单", "ja": "注文取消", "ko": "주문 무효화", "id": "Batalkan Pesanan", "ms": "Batal Pesanan"],
        // MARK: - Tax
        "tax_amount": ["en": "Tax Amount", "th": "จำนวนภาษี", "zh": "税额", "ja": "税額", "ko": "세금액", "id": "Jumlah Pajak", "ms": "Jumlah Cukai"],
        "tax_calculation_mode": ["en": "Tax Calculation Mode", "th": "โหมดคำนวณภาษี", "zh": "税金计算模式", "ja": "税計算モード", "ko": "세금 계산 모드", "id": "Mode Perhitungan Pajak", "ms": "Mod Pengiraan Cukai"],
        "tax_id_preview_lbl": ["en": "Tax ID", "th": "เลขประจำตัวผู้เสียภาษี", "zh": "税号", "ja": "税ID", "ko": "세금 ID", "id": "NPWP", "ms": "No. Cukai"],
        "tax_id_vat_registration": ["en": "VAT Registration", "th": "จดทะเบียนภาษีมูลค่าเพิ่ม", "zh": "增值税登记", "ja": "消費税登録", "ko": "부가세 등록", "id": "Pendaftaran PPN", "ms": "Pendaftaran GST"],
        "tax_name": ["en": "Tax Name", "th": "ชื่อภาษี", "zh": "税名", "ja": "税名", "ko": "세금 이름", "id": "Nama Pajak", "ms": "Nama Cukai"],
        "tax_rate": ["en": "Tax Rate", "th": "อัตราภาษี", "zh": "税率", "ja": "税率", "ko": "세율", "id": "Tarif Pajak", "ms": "Kadar Cukai"],
        "tax_type": ["en": "Tax Type", "th": "ประเภทภาษี", "zh": "税种", "ja": "税種", "ko": "세금 유형", "id": "Tipe Pajak", "ms": "Jenis Cukai"],
        "tax_vat": ["en": "VAT", "th": "ภาษีมูลค่าเพิ่ม", "zh": "增值税", "ja": "消費税", "ko": "부가세", "id": "PPN", "ms": "GST"],
        "taxation_receipts_settings": ["en": "Tax & Receipts Settings", "th": "ตั้งค่าภาษีและใบเสร็จ", "zh": "税务与收据设置", "ja": "税金・レシート設定", "ko": "세금 및 영수증 설정", "id": "Pengaturan Pajak & Struk", "ms": "Tetapan Cukai & Resit"],
        "vat_lbl": ["en": "VAT", "th": "ภาษีมูลค่าเพิ่ม", "zh": "增值税", "ja": "消費税", "ko": "부가세", "id": "PPN", "ms": "GST"],
        // MARK: - Financial Totals
        "gross_delivery_lbl": ["en": "Gross Delivery", "th": "เดลิเวอรี่รวม", "zh": "外卖总额", "ja": "デリバリー総額", "ko": "총 배달", "id": "Delivery Kotor", "ms": "Penghantaran Kasar"],
        "gross_header": ["en": "Gross", "th": "รวม", "zh": "总额", "ja": "総額", "ko": "총", "id": "Kotor", "ms": "Kasar"],
        "gross_margin_lbl": ["en": "Gross Margin", "th": "อัตรากำไรขั้นต้น", "zh": "毛利率", "ja": "粗利率", "ko": "매출 총이익률", "id": "Margin Kotor", "ms": "Margin Kasar"],
        "gross_profit_lbl": ["en": "Gross Profit", "th": "กำไรขั้นต้น", "zh": "毛利", "ja": "粗利", "ko": "매출 총이익", "id": "Laba Kotor", "ms": "Keuntungan Kasar"],
        "gross_sales": ["en": "Gross Sales", "th": "ยอดขายรวม", "zh": "总销售额", "ja": "総売上", "ko": "총 매출", "id": "Penjualan Kotor", "ms": "Jualan Kasar"],
        "gross_wages_label": ["en": "Gross Wages", "th": "ค่าจ้างรวม", "zh": "总工资", "ja": "総賃金", "ko": "총 임금", "id": "Gaji Kotor", "ms": "Gaji Kasar"],
        "net_delivery_rev_lbl": ["en": "Net Delivery Revenue", "th": "รายได้เดลิเวอรี่สุทธิ", "zh": "净外卖收入", "ja": "デリバリー純売上", "ko": "순 배달 매출", "id": "Pendapatan Delivery Bersih", "ms": "Hasil Penghantaran Bersih"],
        "net_margin_by_platform_lbl": ["en": "Net Margin by Platform", "th": "อัตรากำไรสุทธิตามแพลตฟอร์ม", "zh": "各平台净利率", "ja": "プラットフォーム別純利益率", "ko": "플랫폼별 순이익률", "id": "Margin Bersih per Platform", "ms": "Margin Bersih per Platform"],
        "net_margin_lbl": ["en": "Net Margin", "th": "อัตรากำไรสุทธิ", "zh": "净利率", "ja": "純利益率", "ko": "순이익률", "id": "Margin Bersih", "ms": "Margin Bersih"],
        "net_pay_label": ["en": "Net Pay", "th": "รายได้สุทธิ", "zh": "净薪资", "ja": "手取り", "ko": "실수령액", "id": "Gaji Bersih", "ms": "Gaji Bersih"],
        "net_rev_header": ["en": "Net Revenue", "th": "รายได้สุทธิ", "zh": "净收入", "ja": "純売上", "ko": "순매출", "id": "Pendapatan Bersih", "ms": "Hasil Bersih"],
        "net_revenue_template": ["en": "Net: ฿%@", "th": "สุทธิ: ฿%@", "zh": "净额: ฿%@", "ja": "純額: ฿%@", "ko": "순액: ฿%@", "id": "Bersih: ฿%@", "ms": "Bersih: ฿%@"],
        "net_sales": ["en": "Net Sales", "th": "ยอดขายสุทธิ", "zh": "净销售", "ja": "純売上", "ko": "순매출", "id": "Penjualan Bersih", "ms": "Jualan Bersih"],
        "net_sales_lbl": ["en": "Net Sales", "th": "ยอดขายสุทธิ", "zh": "净销售额", "ja": "純売上", "ko": "순매출", "id": "Penjualan Bersih", "ms": "Jualan Bersih"],
        "net_variance_cost": ["en": "Net Variance Cost", "th": "ต้นทุนความแตกต่างสุทธิ", "zh": "净差异成本", "ja": "純差異コスト", "ko": "순 차이 비용", "id": "Biaya Varian Bersih", "ms": "Kos Varians Bersih"],
        "total_discounts": ["en": "Total Discounts", "th": "ส่วนลดทั้งหมด", "zh": "总折扣", "ja": "割引合計", "ko": "총 할인", "id": "Total Diskon", "ms": "Jumlah Diskaun"],
        "total_gp_fees_lbl": ["en": "Total GP Fees", "th": "ค่าธรรมเนียม GP ทั้งหมด", "zh": "GP费用合计", "ja": "GP手数料合計", "ko": "총 GP 수수료", "id": "Total Biaya GP", "ms": "Jumlah Yuran GP"],
        "total_hours": ["en": "Total Hours", "th": "ชั่วโมงทั้งหมด", "zh": "总工时", "ja": "合計時間", "ko": "총 시간", "id": "Total Jam", "ms": "Jumlah Jam"],
        "total_items": ["en": "Total Items", "th": "รายการทั้งหมด", "zh": "总项数", "ja": "合計商品数", "ko": "총 항목", "id": "Total Item", "ms": "Jumlah Item"],
        "total_labor_cost_lbl": ["en": "Total Labor Cost", "th": "ต้นทุนแรงงานทั้งหมด", "zh": "总人工成本", "ja": "人件費合計", "ko": "총 인건비", "id": "Total Biaya Tenaga Kerja", "ms": "Jumlah Kos Buruh"],
        "total_lbl": ["en": "Total", "th": "รวม", "zh": "合计", "ja": "合計", "ko": "합계", "id": "Total", "ms": "Jumlah"],
        "total_payroll": ["en": "Total Payroll", "th": "เงินเดือนทั้งหมด", "zh": "总薪资", "ja": "給与合計", "ko": "총 급여", "id": "Total Penggajian", "ms": "Jumlah Gaji"],
        "total_refunds": ["en": "Total Refunds", "th": "ยอดคืนเงินทั้งหมด", "zh": "总退款", "ja": "返金合計", "ko": "총 환불", "id": "Total Refund", "ms": "Jumlah Bayaran Balik"],
        "total_revenue_header": ["en": "Total Revenue", "th": "รายได้ทั้งหมด", "zh": "总收入", "ja": "総売上", "ko": "총 매출", "id": "Total Pendapatan", "ms": "Jumlah Hasil"],
        "total_spend": ["en": "Total Spend", "th": "ยอดใช้จ่ายทั้งหมด", "zh": "总消费", "ja": "合計支出", "ko": "총 지출", "id": "Total Belanja", "ms": "Jumlah Belanja"],
        "total_ssf": ["en": "Total SSF", "th": "ประกันสังคมทั้งหมด", "zh": "社保总额", "ja": "社会保険合計", "ko": "총 사회보험", "id": "Total BPJS", "ms": "Jumlah KWSP"],
        "total_tax": ["en": "Total Tax", "th": "ภาษีทั้งหมด", "zh": "总税额", "ja": "税合計", "ko": "총 세금", "id": "Total Pajak", "ms": "Jumlah Cukai"],
        // MARK: - Empty States
        "no_categories_matched_search": ["en": "No categories match your search", "th": "ไม่มีหมวดหมู่ตรงกับการค้นหา", "zh": "没有匹配的分类", "ja": "検索に一致するカテゴリーがありません", "ko": "검색과 일치하는 카테고리 없음", "id": "Tidak ada kategori yang cocok", "ms": "Tiada kategori yang sepadan"],
        "no_clockin_records": ["en": "No Clock-In Records", "th": "ไม่มีบันทึกลงเวลาเข้า", "zh": "没有打卡记录", "ja": "出勤記録なし", "ko": "출근 기록 없음", "id": "Tidak Ada Catatan Absensi", "ms": "Tiada Rekod Masuk"],
        "no_contact_name": ["en": "No Contact Name", "th": "ไม่มีชื่อผู้ติดต่อ", "zh": "无联系人姓名", "ja": "連絡先名なし", "ko": "연락처 이름 없음", "id": "Tidak Ada Nama Kontak", "ms": "Tiada Nama Hubungan"],
        "no_custom_options_desc": ["en": "Add custom options for this modifier group", "th": "เพิ่มตัวเลือกสำหรับกลุ่มตัวเลือกนี้", "zh": "为此修饰组添加自定义选项", "ja": "この修飾グループにオプションを追加", "ko": "이 수정자 그룹에 사용자 정의 옵션 추가", "id": "Tambahkan opsi kustom untuk grup ini", "ms": "Tambah pilihan tersuai untuk kumpulan ini"],
        "no_data": ["en": "No Data", "th": "ไม่มีข้อมูล", "zh": "无数据", "ja": "データなし", "ko": "데이터 없음", "id": "Tidak Ada Data", "ms": "Tiada Data"],
        "no_delivery_prices_desc": ["en": "No delivery pricing configured yet", "th": "ยังไม่ได้ตั้งราคาเดลิเวอรี่", "zh": "尚未配置外卖定价", "ja": "デリバリー価格未設定", "ko": "배달 가격 미설정", "id": "Belum ada harga delivery diatur", "ms": "Belum ada harga penghantaran ditetapkan"],
        "no_details": ["en": "No Details", "th": "ไม่มีรายละเอียด", "zh": "无详情", "ja": "詳細なし", "ko": "상세 없음", "id": "Tidak Ada Detail", "ms": "Tiada Butiran"],
        "no_discrepancy_label": ["en": "No Discrepancy", "th": "ไม่มีส่วนต่าง", "zh": "无差异", "ja": "差異なし", "ko": "차이 없음", "id": "Tidak Ada Selisih", "ms": "Tiada Perbezaan"],
        "no_employees_registered": ["en": "No Employees Registered", "th": "ไม่มีพนักงานที่ลงทะเบียน", "zh": "没有已注册员工", "ja": "登録従業員なし", "ko": "등록된 직원 없음", "id": "Tidak Ada Karyawan Terdaftar", "ms": "Tiada Pekerja Didaftarkan"],
        "no_expiry_label": ["en": "No Expiry", "th": "ไม่มีวันหมดอายุ", "zh": "无过期日", "ja": "有効期限なし", "ko": "만료일 없음", "id": "Tanpa Kadaluarsa", "ms": "Tiada Tarikh Luput"],
        "no_gift_cards": ["en": "No Gift Cards", "th": "ไม่มีบัตรของขวัญ", "zh": "没有礼品卡", "ja": "ギフトカードなし", "ko": "기프트카드 없음", "id": "Tidak Ada Kartu Hadiah", "ms": "Tiada Kad Hadiah"],
        "no_ingredients_linked": ["en": "No Ingredients Linked", "th": "ไม่มีวัตถุดิบที่เชื่อมโยง", "zh": "未关联原料", "ja": "材料未リンク", "ko": "연결된 재료 없음", "id": "Tidak Ada Bahan Terhubung", "ms": "Tiada Bahan Dipautkan"],
        "no_inventory_to_audit": ["en": "No Inventory to Audit", "th": "ไม่มีสินค้าให้ตรวจนับ", "zh": "没有库存需要审计", "ja": "棚卸し対象の在庫なし", "ko": "감사할 재고 없음", "id": "Tidak Ada Inventaris untuk Diaudit", "ms": "Tiada Inventori untuk Diaudit"],
        "no_items_sold_pdf": ["en": "No items sold in this period", "th": "ไม่มีสินค้าที่ขายในช่วงนี้", "zh": "该期间无售出商品", "ja": "この期間に販売された商品はありません", "ko": "이 기간에 판매된 상품 없음", "id": "Tidak ada item terjual dalam periode ini", "ms": "Tiada item terjual dalam tempoh ini"],
        "no_linked_customer": ["en": "No Linked Customer", "th": "ไม่มีลูกค้าที่เชื่อมโยง", "zh": "未关联客户", "ja": "リンクされた顧客なし", "ko": "연결된 고객 없음", "id": "Tidak Ada Pelanggan Terhubung", "ms": "Tiada Pelanggan Dipautkan"],
        "no_location": ["en": "No Location", "th": "ไม่มีที่ตั้ง", "zh": "无位置", "ja": "場所なし", "ko": "위치 없음", "id": "Tidak Ada Lokasi", "ms": "Tiada Lokasi"],
        "no_manual_movements": ["en": "No Manual Movements", "th": "ไม่มีการเคลื่อนไหวด้วยตนเอง", "zh": "无手动调整记录", "ja": "手動移動なし", "ko": "수동 이동 없음", "id": "Tidak Ada Pergerakan Manual", "ms": "Tiada Pergerakan Manual"],
        "no_menu_items_found": ["en": "No Menu Items Found", "th": "ไม่พบรายการเมนู", "zh": "未找到菜单项", "ja": "メニュー商品が見つかりません", "ko": "메뉴 항목을 찾을 수 없음", "id": "Item Menu Tidak Ditemukan", "ms": "Item Menu Tidak Ditemui"],
        "no_modifiers_matched_search": ["en": "No modifiers match your search", "th": "ไม่มีตัวเลือกตรงกับการค้นหา", "zh": "没有匹配的修饰项", "ja": "検索に一致する修飾がありません", "ko": "검색과 일치하는 수정자 없음", "id": "Tidak ada modifier yang cocok", "ms": "Tiada pengubah yang sepadan"],
        "no_options_added": ["en": "No Options Added", "th": "ยังไม่มีตัวเลือก", "zh": "未添加选项", "ja": "オプション未追加", "ko": "옵션이 추가되지 않음", "id": "Belum Ada Opsi Ditambahkan", "ms": "Belum Ada Pilihan Ditambah"],
        "no_pending_biometric_audits": ["en": "No Pending Biometric Audits", "th": "ไม่มีการตรวจสอบไบโอเมตริกที่รอดำเนินการ", "zh": "没有待处理的生物识别审核", "ja": "保留中の生体認証監査なし", "ko": "대기 중인 생체 인식 감사 없음", "id": "Tidak Ada Audit Biometrik Tertunda", "ms": "Tiada Audit Biometrik Tertangguh"],
        "no_products_matched_search": ["en": "No products match your search", "th": "ไม่มีสินค้าตรงกับการค้นหา", "zh": "没有匹配的产品", "ja": "検索に一致する商品がありません", "ko": "검색과 일치하는 상품 없음", "id": "Tidak ada produk yang cocok", "ms": "Tiada produk yang sepadan"],
        "no_products_sold_pdf": ["en": "No products sold in this period", "th": "ไม่มีสินค้าที่ขายในช่วงนี้", "zh": "该期间无产品售出", "ja": "この期間に販売された商品はありません", "ko": "이 기간에 판매된 상품 없음", "id": "Tidak ada produk terjual dalam periode ini", "ms": "Tiada produk terjual dalam tempoh ini"],
        "no_promotions_desc": ["en": "Create your first promotion to attract more customers", "th": "สร้างโปรโมชั่นแรกเพื่อดึงดูดลูกค้า", "zh": "创建第一个促销活动以吸引更多客户", "ja": "最初のプロモーションを作成して顧客を惹きつけましょう", "ko": "첫 번째 프로모션을 만들어 더 많은 고객을 유치하세요", "id": "Buat promosi pertama untuk menarik pelanggan", "ms": "Buat promosi pertama untuk tarik pelanggan"],
        "no_search_results": ["en": "No Search Results", "th": "ไม่มีผลการค้นหา", "zh": "没有搜索结果", "ja": "検索結果なし", "ko": "검색 결과 없음", "id": "Tidak Ada Hasil Pencarian", "ms": "Tiada Hasil Carian"],
        "no_shift_history": ["en": "No Shift History", "th": "ไม่มีประวัติกะ", "zh": "没有班次历史", "ja": "シフト履歴なし", "ko": "교대 내역 없음", "id": "Tidak Ada Riwayat Shift", "ms": "Tiada Sejarah Syif"],
        "no_shifts_scheduled": ["en": "No Shifts Scheduled", "th": "ไม่มีกะที่กำหนด", "zh": "没有排班", "ja": "予定されたシフトなし", "ko": "예정된 교대 없음", "id": "Tidak Ada Shift Dijadwalkan", "ms": "Tiada Syif Dijadualkan"],
        "no_slips_calculated": ["en": "No Slips Calculated", "th": "ไม่มีสลิปที่คำนวณ", "zh": "没有计算的工资单", "ja": "計算済み明細なし", "ko": "계산된 명세서 없음", "id": "Tidak Ada Slip Dihitung", "ms": "Tiada Slip Dikira"],
        "no_stock_setup": ["en": "No Stock Setup", "th": "ยังไม่ได้ตั้งค่าสต็อก", "zh": "未设置库存", "ja": "在庫未設定", "ko": "재고 미설정", "id": "Belum Ada Pengaturan Stok", "ms": "Belum Ada Tetapan Stok"],
        "no_supplied_ingredients_linked": ["en": "No Supplied Ingredients Linked", "th": "ไม่มีวัตถุดิบจากซัพพลายเออร์ที่เชื่อมโยง", "zh": "未关联供应原料", "ja": "供給材料未リンク", "ko": "공급 재료 연결 없음", "id": "Tidak Ada Bahan Pasokan Terhubung", "ms": "Tiada Bahan Bekalan Dipautkan"],
        "no_supplier_option": ["en": "No Supplier", "th": "ไม่มีซัพพลายเออร์", "zh": "无供应商", "ja": "仕入先なし", "ko": "공급업체 없음", "id": "Tidak Ada Pemasok", "ms": "Tiada Pembekal"],
        "no_suppliers_found": ["en": "No Suppliers Found", "th": "ไม่พบซัพพลายเออร์", "zh": "未找到供应商", "ja": "仕入先が見つかりません", "ko": "공급업체를 찾을 수 없음", "id": "Pemasok Tidak Ditemukan", "ms": "Pembekal Tidak Ditemui"],
        "no_system_role": ["en": "No Role Assigned", "th": "ไม่ได้กำหนดตำแหน่ง", "zh": "未分配角色", "ja": "役割未割当て", "ko": "역할 미할당", "id": "Tidak Ada Peran Ditetapkan", "ms": "Tiada Peranan Ditetapkan"],
        "no_transactions_found": ["en": "No Transactions Found", "th": "ไม่พบรายการ", "zh": "未找到交易", "ja": "取引が見つかりません", "ko": "거래를 찾을 수 없음", "id": "Transaksi Tidak Ditemukan", "ms": "Transaksi Tidak Ditemui"],
        "no_transactions_pdf": ["en": "No transactions in this period", "th": "ไม่มีรายการในช่วงนี้", "zh": "该期间无交易", "ja": "この期間に取引はありません", "ko": "이 기간에 거래 없음", "id": "Tidak ada transaksi dalam periode ini", "ms": "Tiada transaksi dalam tempoh ini"],
        "no_transactions_yet": ["en": "No Transactions Yet", "th": "ยังไม่มีรายการ", "zh": "暂无交易", "ja": "取引なし", "ko": "아직 거래 없음", "id": "Belum Ada Transaksi", "ms": "Belum Ada Transaksi"],
        // MARK: - Scheduling
        "daily_pay_type": ["en": "Daily", "th": "รายวัน", "zh": "日结", "ja": "日払い", "ko": "일급", "id": "Harian", "ms": "Harian"],
        "daily_sales": ["en": "Daily Sales", "th": "ยอดขายรายวัน", "zh": "每日销售", "ja": "日次売上", "ko": "일 매출", "id": "Penjualan Harian", "ms": "Jualan Harian"],
        "hourly_pay_type": ["en": "Hourly", "th": "รายชั่วโมง", "zh": "时薪", "ja": "時給", "ko": "시급", "id": "Per Jam", "ms": "Setiap Jam"],
        "monthly_fixed_pay_type": ["en": "Monthly (Fixed)", "th": "รายเดือน (คงที่)", "zh": "月薪 (固定)", "ja": "月給 (固定)", "ko": "월급 (고정)", "id": "Bulanan (Tetap)", "ms": "Bulanan (Tetap)"],
        "weekly_calendar_sub": ["en": "View your weekly schedule", "th": "ดูตารางประจำสัปดาห์", "zh": "查看您的每周日程", "ja": "週間スケジュールを表示", "ko": "주간 일정 보기", "id": "Lihat jadwal mingguan Anda", "ms": "Lihat jadual mingguan anda"],
        "weekly_calendar_view": ["en": "Weekly Calendar", "th": "ปฏิทินรายสัปดาห์", "zh": "周日历", "ja": "週間カレンダー", "ko": "주간 달력", "id": "Kalender Mingguan", "ms": "Kalendar Mingguan"],
        "weekly_shift_report_title": ["en": "Weekly Shift Report", "th": "รายงานกะรายสัปดาห์", "zh": "周班次报告", "ja": "週間シフトレポート", "ko": "주간 교대 보고서", "id": "Laporan Shift Mingguan", "ms": "Laporan Syif Mingguan"],
        // MARK: - Print & Export
        "export_full_summary": ["en": "Export Full Summary", "th": "ส่งออกสรุปทั้งหมด", "zh": "导出完整摘要", "ja": "全サマリーエクスポート", "ko": "전체 요약 내보내기", "id": "Ekspor Ringkasan Lengkap", "ms": "Eksport Ringkasan Penuh"],
        "export_pdf": ["en": "Export PDF", "th": "ส่งออก PDF", "zh": "导出 PDF", "ja": "PDF エクスポート", "ko": "PDF 내보내기", "id": "Ekspor PDF", "ms": "Eksport PDF"],
        "print_btn": ["en": "Print", "th": "พิมพ์", "zh": "打印", "ja": "印刷", "ko": "인쇄", "id": "Cetak", "ms": "Cetak"],
        "print_z_report_btn": ["en": "Print Z-Report", "th": "พิมพ์รายงาน Z", "zh": "打印 Z-报表", "ja": "Zレポート印刷", "ko": "Z-리포트 인쇄", "id": "Cetak Laporan Z", "ms": "Cetak Laporan Z"],
        // MARK: - Common Buttons
        "btn_apply": ["en": "Apply", "th": "ใช้", "zh": "应用", "ja": "適用", "ko": "적용", "id": "Terapkan", "ms": "Guna"],
        "btn_cancel": ["en": "Cancel", "th": "ยกเลิก", "zh": "取消", "ja": "キャンセル", "ko": "취소", "id": "Batal", "ms": "Batal"],
        "btn_recall": ["en": "Recall", "th": "เรียกคืน", "zh": "调回", "ja": "呼出", "ko": "불러오기", "id": "Panggil", "ms": "Panggil"],
        "btn_save_changes": ["en": "Save Changes", "th": "บันทึกการเปลี่ยนแปลง", "zh": "保存更改", "ja": "変更を保存", "ko": "변경 저장", "id": "Simpan Perubahan", "ms": "Simpan Perubahan"],
        "btn_scan": ["en": "Scan", "th": "สแกน", "zh": "扫描", "ja": "スキャン", "ko": "스캔", "id": "Pindai", "ms": "Imbas"],
        "btn_void": ["en": "Void", "th": "ยกเลิก", "zh": "作废", "ja": "取消", "ko": "무효", "id": "Void", "ms": "Batal"],
        // MARK: - General UI
        "actions_header": ["en": "Actions", "th": "การดำเนินการ", "zh": "操作", "ja": "アクション", "ko": "작업", "id": "Tindakan", "ms": "Tindakan"],
        "active_cards_label": ["en": "Active Cards", "th": "บัตรที่ใช้งาน", "zh": "活跃卡", "ja": "アクティブカード", "ko": "활성 카드", "id": "Kartu Aktif", "ms": "Kad Aktif"],
        "actual_cash_counted_label": ["en": "Actual Cash Counted", "th": "เงินสดที่นับได้จริง", "zh": "实际清点金额", "ja": "実際のレジ金", "ko": "실제 계산 금액", "id": "Tunai Aktual Dihitung", "ms": "Tunai Sebenar Dikira"],
        "actual_cash_counted_label_colon": ["en": "Actual Cash Counted:", "th": "เงินสดที่นับได้จริง:", "zh": "实际清点金额:", "ja": "実際のレジ金:", "ko": "실제 계산 금액:", "id": "Tunai Aktual Dihitung:", "ms": "Tunai Sebenar Dikira:"],
        "ad_fee_header": ["en": "Advertising Fee", "th": "ค่าโฆษณา", "zh": "广告费", "ja": "広告費", "ko": "광고비", "id": "Biaya Iklan", "ms": "Yuran Iklan"],
        "add_balance_btn": ["en": "Add Balance", "th": "เติมเงิน", "zh": "充值", "ja": "残高追加", "ko": "잔액 추가", "id": "Tambah Saldo", "ms": "Tambah Baki"],
        "add_branch_btn": ["en": "Add Branch", "th": "เพิ่มสาขา", "zh": "添加分店", "ja": "支店追加", "ko": "지점 추가", "id": "Tambah Cabang", "ms": "Tambah Cawangan"],
        "add_btn": ["en": "Add", "th": "เพิ่ม", "zh": "添加", "ja": "追加", "ko": "추가", "id": "Tambah", "ms": "Tambah"],
        "add_btn_label": ["en": "Add", "th": "เพิ่ม", "zh": "添加", "ja": "追加", "ko": "추가", "id": "Tambah", "ms": "Tambah"],
        "add_cash_movement_title": ["en": "Add Cash Movement", "th": "เพิ่มการเคลื่อนไหวเงินสด", "zh": "添加现金变动", "ja": "現金移動を追加", "ko": "현금 이동 추가", "id": "Tambah Pergerakan Kas", "ms": "Tambah Pergerakan Tunai"],
        "add_customer_btn": ["en": "Add Customer", "th": "เพิ่มลูกค้า", "zh": "添加客户", "ja": "顧客追加", "ko": "고객 추가", "id": "Tambah Pelanggan", "ms": "Tambah Pelanggan"],
        "add_delivery_brand_btn": ["en": "Add Delivery Brand", "th": "เพิ่มแบรนด์เดลิเวอรี่", "zh": "添加外卖品牌", "ja": "デリバリーブランド追加", "ko": "배달 브랜드 추가", "id": "Tambah Merek Delivery", "ms": "Tambah Jenama Penghantaran"],
        "add_employee": ["en": "Add Employee", "th": "เพิ่มพนักงาน", "zh": "添加员工", "ja": "従業員追加", "ko": "직원 추가", "id": "Tambah Karyawan", "ms": "Tambah Pekerja"],
        "add_ingredient_title": ["en": "Add Ingredient", "th": "เพิ่มวัตถุดิบ", "zh": "添加原料", "ja": "材料追加", "ko": "재료 추가", "id": "Tambah Bahan", "ms": "Tambah Bahan"],
        "add_new_po_btn": ["en": "New Purchase Order", "th": "สร้างใบสั่งซื้อใหม่", "zh": "新建采购单", "ja": "新規発注", "ko": "새 구매 주문", "id": "Pesanan Beli Baru", "ms": "Pesanan Beli Baru"],
        "add_new_supplier_title": ["en": "Add New Supplier", "th": "เพิ่มซัพพลายเออร์ใหม่", "zh": "添加新供应商", "ja": "新規仕入先追加", "ko": "새 공급업체 추가", "id": "Tambah Pemasok Baru", "ms": "Tambah Pembekal Baru"],
        "add_option_btn": ["en": "Add Option", "th": "เพิ่มตัวเลือก", "zh": "添加选项", "ja": "オプション追加", "ko": "옵션 추가", "id": "Tambah Opsi", "ms": "Tambah Pilihan"],
        "add_paid_in_out": ["en": "Add Paid In/Out", "th": "เพิ่มเงินเข้า/ออก", "zh": "添加存入/支出", "ja": "入金/出金追加", "ko": "입출금 추가", "id": "Tambah Kas Masuk/Keluar", "ms": "Tambah Tunai Masuk/Keluar"],
        "add_raw_ingredient_btn": ["en": "Add Raw Ingredient", "th": "เพิ่มวัตถุดิบ", "zh": "添加原材料", "ja": "原材料追加", "ko": "원자재 추가", "id": "Tambah Bahan Mentah", "ms": "Tambah Bahan Mentah"],
        "add_raw_material": ["en": "Add Raw Material", "th": "เพิ่มวัตถุดิบ", "zh": "添加原材料", "ja": "原材料追加", "ko": "원자재 추가", "id": "Tambah Bahan Baku", "ms": "Tambah Bahan Mentah"],
        "add_raw_material_btn": ["en": "Add Raw Material", "th": "เพิ่มวัตถุดิบ", "zh": "添加原材料", "ja": "原材料追加", "ko": "원자재 추가", "id": "Tambah Bahan Baku", "ms": "Tambah Bahan Mentah"],
        "add_timecard": ["en": "Add Timecard", "th": "เพิ่มบัตรเวลา", "zh": "添加考勤", "ja": "タイムカード追加", "ko": "타임카드 추가", "id": "Tambah Kartu Waktu", "ms": "Tambah Kad Masa"],
        "add_to_cart_btn": ["en": "Add to Cart", "th": "เพิ่มลงตะกร้า", "zh": "加入购物车", "ja": "カートに追加", "ko": "장바구니에 추가", "id": "Tambah ke Keranjang", "ms": "Tambah ke Troli"],
        "additional_details": ["en": "Additional Details", "th": "รายละเอียดเพิ่มเติม", "zh": "附加信息", "ja": "追加詳細", "ko": "추가 상세", "id": "Detail Tambahan", "ms": "Butiran Tambahan"],
        "additional_details_hr_header": ["en": "Additional Details", "th": "รายละเอียดเพิ่มเติม", "zh": "附加信息", "ja": "追加詳細", "ko": "추가 상세", "id": "Detail Tambahan", "ms": "Butiran Tambahan"],
        "adjusted_items": ["en": "Adjusted Items", "th": "รายการที่ปรับแล้ว", "zh": "已调整项", "ja": "調整済み商品", "ko": "조정된 항목", "id": "Item Disesuaikan", "ms": "Item Dilaraskan"],
        "adjustment_label": ["en": "Adjustment", "th": "การปรับ", "zh": "调整", "ja": "調整", "ko": "조정", "id": "Penyesuaian", "ms": "Pelarasan"],
        "amount_baht": ["en": "Amount (฿)", "th": "จำนวน (฿)", "zh": "金额 (฿)", "ja": "金額 (฿)", "ko": "금액 (฿)", "id": "Jumlah (฿)", "ms": "Jumlah (฿)"],
        "amount_header": ["en": "Amount", "th": "จำนวนเงิน", "zh": "金额", "ja": "金額", "ko": "금액", "id": "Jumlah", "ms": "Jumlah"],
        "amount_placeholder": ["en": "Enter amount", "th": "ใส่จำนวนเงิน", "zh": "输入金额", "ja": "金額を入力", "ko": "금액 입력", "id": "Masukkan jumlah", "ms": "Masukkan jumlah"],
        "approved_by": ["en": "Approved By", "th": "อนุมัติโดย", "zh": "审批人", "ja": "承認者", "ko": "승인자", "id": "Disetujui Oleh", "ms": "Diluluskan Oleh"],
        "approved_status_tag": ["en": "Approved", "th": "อนุมัติแล้ว", "zh": "已批准", "ja": "承認済み", "ko": "승인됨", "id": "Disetujui", "ms": "Diluluskan"],
        "audit_committed_message": ["en": "Stock audit has been committed successfully", "th": "ตรวจนับสต็อกเสร็จสมบูรณ์", "zh": "库存审计已提交成功", "ja": "棚卸しが正常にコミットされました", "ko": "재고 감사가 성공적으로 제출되었습니다", "id": "Audit stok berhasil dikomit", "ms": "Audit stok berjaya dihantar"],
        "audit_committed_title": ["en": "Audit Committed", "th": "ยืนยันการตรวจนับแล้ว", "zh": "审计已提交", "ja": "棚卸しコミット済み", "ko": "감사 제출됨", "id": "Audit Dikomit", "ms": "Audit Dihantar"],
        "authorizing_transaction": ["en": "Authorizing Transaction...", "th": "กำลังอนุมัติรายการ...", "zh": "正在授权交易...", "ja": "取引を承認中...", "ko": "거래 승인 중...", "id": "Mengotorisasi Transaksi...", "ms": "Memberi Kebenaran Transaksi..."],
        "auto_create_matching_item": ["en": "Auto-Create Matching Item", "th": "สร้างรายการที่ตรงกันอัตโนมัติ", "zh": "自动创建匹配项", "ja": "一致商品を自動作成", "ko": "일치 항목 자동 생성", "id": "Buat Item Cocok Otomatis", "ms": "Cipta Item Sepadan Automatik"],
        "available_balance_template": ["en": "Available: ฿%@", "th": "ใช้ได้: ฿%@", "zh": "可用: ฿%@", "ja": "利用可能: ฿%@", "ko": "사용 가능: ฿%@", "id": "Tersedia: ฿%@", "ms": "Tersedia: ฿%@"],
        "avg_ticket_header": ["en": "Average Ticket", "th": "เฉลี่ยต่อบิล", "zh": "平均客单价", "ja": "平均客単価", "ko": "평균 객단가", "id": "Rata-rata Tiket", "ms": "Purata Tiket"],
        "awaiting_configuration": ["en": "Awaiting Configuration", "th": "รอการตั้งค่า", "zh": "等待配置", "ja": "設定待ち", "ko": "구성 대기 중", "id": "Menunggu Konfigurasi", "ms": "Menunggu Konfigurasi"],
        "balance_label": ["en": "Balance", "th": "ยอดคงเหลือ", "zh": "余额", "ja": "残高", "ko": "잔액", "id": "Saldo", "ms": "Baki"],
        "balanced_option": ["en": "Balanced", "th": "สมดุล", "zh": "已平衡", "ja": "精算完了", "ko": "균형", "id": "Seimbang", "ms": "Seimbang"],
        "banking_details_header": ["en": "Banking Details", "th": "ข้อมูลธนาคาร", "zh": "银行信息", "ja": "銀行情報", "ko": "은행 정보", "id": "Detail Bank", "ms": "Butiran Bank"],
        "barcode_placeholder": ["en": "Enter barcode", "th": "ใส่บาร์โค้ด", "zh": "输入条码", "ja": "バーコード入力", "ko": "바코드 입력", "id": "Masukkan barcode", "ms": "Masukkan barkod"],
        "barcode_scanner_desc": ["en": "Scan product barcodes for quick lookup", "th": "สแกนบาร์โค้ดสินค้าเพื่อค้นหาด่วน", "zh": "扫描产品条码快速查找", "ja": "商品バーコードをスキャンして素早く検索", "ko": "상품 바코드를 스캔하여 빠르게 조회", "id": "Pindai barcode produk untuk pencarian cepat", "ms": "Imbas barkod produk untuk carian pantas"],
        "barcode_scanner_title": ["en": "Barcode Scanner", "th": "เครื่องสแกนบาร์โค้ด", "zh": "条码扫描器", "ja": "バーコードスキャナー", "ko": "바코드 스캐너", "id": "Pemindai Barcode", "ms": "Pengimbas Barkod"],
        "break_minutes_label": ["en": "Break (min)", "th": "พัก (นาที)", "zh": "休息 (分钟)", "ja": "休憩 (分)", "ko": "휴식 (분)", "id": "Istirahat (menit)", "ms": "Rehat (minit)"],
        "break_overtime_header": ["en": "Break & Overtime", "th": "พักและล่วงเวลา", "zh": "休息与加班", "ja": "休憩・残業", "ko": "휴식 및 초과 근무", "id": "Istirahat & Lembur", "ms": "Rehat & Kerja Lebih"],
        "bundle_price_lbl": ["en": "Bundle Price", "th": "ราคาชุด", "zh": "套装价", "ja": "セット価格", "ko": "세트 가격", "id": "Harga Bundel", "ms": "Harga Bundel"],
        "business_type_bar": ["en": "Bar", "th": "บาร์", "zh": "酒吧", "ja": "バー", "ko": "바", "id": "Bar", "ms": "Bar"],
        "business_type_cafe": ["en": "Café", "th": "คาเฟ่", "zh": "咖啡店", "ja": "カフェ", "ko": "카페", "id": "Kafe", "ms": "Kafe"],
        "business_type_restaurant": ["en": "Restaurant", "th": "ร้านอาหาร", "zh": "餐厅", "ja": "レストラン", "ko": "레스토랑", "id": "Restoran", "ms": "Restoran"],
        "cancel_btn_label": ["en": "Cancel", "th": "ยกเลิก", "zh": "取消", "ja": "キャンセル", "ko": "취소", "id": "Batal", "ms": "Batal"],
        "cancel_purchase_order": ["en": "Cancel Purchase Order", "th": "ยกเลิกใบสั่งซื้อ", "zh": "取消采购单", "ja": "発注書キャンセル", "ko": "구매 주문 취소", "id": "Batalkan Pesanan Beli", "ms": "Batal Pesanan Beli"],
        "card_checkout_title": ["en": "Card Checkout", "th": "ชำระด้วยบัตร", "zh": "刷卡结账", "ja": "カード会計", "ko": "카드 결제", "id": "Checkout Kartu", "ms": "Daftar Keluar Kad"],
        "card_color_fallback": ["en": "Default", "th": "ค่าเริ่มต้น", "zh": "默认", "ja": "デフォルト", "ko": "기본값", "id": "Default", "ms": "Lalai"],
        "card_number_placeholder": ["en": "Enter card number", "th": "ใส่หมายเลขบัตร", "zh": "输入卡号", "ja": "カード番号を入力", "ko": "카드 번호 입력", "id": "Masukkan nomor kartu", "ms": "Masukkan nombor kad"],
        "card_section": ["en": "Card", "th": "บัตร", "zh": "卡片", "ja": "カード", "ko": "카드", "id": "Kartu", "ms": "Kad"],
        "card_total_label": ["en": "Card Total", "th": "ยอดบัตร", "zh": "刷卡总额", "ja": "カード合計", "ko": "카드 합계", "id": "Total Kartu", "ms": "Jumlah Kad"],
        "cashier_header": ["en": "Cashier", "th": "แคชเชียร์", "zh": "收银员", "ja": "レジ担当", "ko": "캐셔", "id": "Kasir", "ms": "Juruwang"],
        "cashier_label": ["en": "Cashier", "th": "แคชเชียร์", "zh": "收银员", "ja": "レジ担当", "ko": "캐셔", "id": "Kasir", "ms": "Juruwang"],
        "cashier_performance_lbl": ["en": "Cashier Performance", "th": "ผลงานแคชเชียร์", "zh": "收银员绩效", "ja": "レジ担当実績", "ko": "캐셔 실적", "id": "Kinerja Kasir", "ms": "Prestasi Juruwang"],
        "choose_dropdown_placeholder": ["en": "Choose...", "th": "เลือก...", "zh": "请选择...", "ja": "選択...", "ko": "선택...", "id": "Pilih...", "ms": "Pilih..."],
        "choose_photo_btn": ["en": "Choose Photo", "th": "เลือกรูป", "zh": "选择照片", "ja": "写真を選択", "ko": "사진 선택", "id": "Pilih Foto", "ms": "Pilih Foto"],
        "classification_location": ["en": "Classification & Location", "th": "การจัดกลุ่มและตำแหน่ง", "zh": "分类与位置", "ja": "分類と場所", "ko": "분류 및 위치", "id": "Klasifikasi & Lokasi", "ms": "Klasifikasi & Lokasi"],
        "close_btn": ["en": "Close", "th": "ปิด", "zh": "关闭", "ja": "閉じる", "ko": "닫기", "id": "Tutup", "ms": "Tutup"],
        "close_btn_label": ["en": "Close", "th": "ปิด", "zh": "关闭", "ja": "閉じる", "ko": "닫기", "id": "Tutup", "ms": "Tutup"],
        "close_register_btn": ["en": "Close Register", "th": "ปิดเครื่อง", "zh": "关闭收银机", "ja": "レジ締め", "ko": "레지 마감", "id": "Tutup Register", "ms": "Tutup Daftar"],
        "closed_at_label": ["en": "Closed At", "th": "ปิดเมื่อ", "zh": "关闭时间", "ja": "終了時刻", "ko": "마감 시간", "id": "Ditutup Pada", "ms": "Ditutup Pada"],
        "closing_notes_label": ["en": "Closing Notes", "th": "หมายเหตุปิดกะ", "zh": "关班备注", "ja": "締めメモ", "ko": "마감 메모", "id": "Catatan Penutupan", "ms": "Nota Penutupan"],
        "cogs_used_lbl": ["en": "COGS Used", "th": "ต้นทุนขายที่ใช้", "zh": "已用销货成本", "ja": "使用原価", "ko": "사용된 매출 원가", "id": "HPP Terpakai", "ms": "Kos Barangan Digunakan"],
        "commit_audit_adjustments_btn": ["en": "Commit Adjustments", "th": "ยืนยันการปรับ", "zh": "提交调整", "ja": "調整をコミット", "ko": "조정 확정", "id": "Komit Penyesuaian", "ms": "Hantar Pelarasan"],
        "commit_btn": ["en": "Commit", "th": "ยืนยัน", "zh": "提交", "ja": "コミット", "ko": "확정", "id": "Komit", "ms": "Hantar"],
        "company_supplier_name_label": ["en": "Company/Supplier Name", "th": "ชื่อบริษัท/ซัพพลายเออร์", "zh": "公司/供应商名称", "ja": "会社/仕入先名", "ko": "회사/공급업체명", "id": "Nama Perusahaan/Pemasok", "ms": "Nama Syarikat/Pembekal"],
        "company_supplier_name_placeholder": ["en": "Enter company name", "th": "ใส่ชื่อบริษัท", "zh": "输入公司名称", "ja": "会社名を入力", "ko": "회사명 입력", "id": "Masukkan nama perusahaan", "ms": "Masukkan nama syarikat"],
        "compensation_start_date_header": ["en": "Compensation Start Date", "th": "วันที่เริ่มรับค่าตอบแทน", "zh": "薪酬起始日期", "ja": "報酬開始日", "ko": "보상 시작일", "id": "Tanggal Mulai Kompensasi", "ms": "Tarikh Mula Pampasan"],
        "completed_orders_sub": ["en": "Completed Orders", "th": "ออเดอร์ที่เสร็จ", "zh": "已完成订单", "ja": "完了注文", "ko": "완료된 주문", "id": "Pesanan Selesai", "ms": "Pesanan Selesai"],
        "completed_transactions_lbl": ["en": "Completed Transactions", "th": "รายการที่เสร็จสิ้น", "zh": "已完成交易", "ja": "完了取引", "ko": "완료된 거래", "id": "Transaksi Selesai", "ms": "Transaksi Selesai"],
        "computing_payroll_metrics": ["en": "Computing payroll metrics...", "th": "กำลังคำนวณเงินเดือน...", "zh": "正在计算薪资...", "ja": "給与を計算中...", "ko": "급여 계산 중...", "id": "Menghitung metrik penggajian...", "ms": "Mengira metrik gaji..."],
        "configure_fees_template": ["en": "Configure fees for %@", "th": "ตั้งค่าค่าธรรมเนียมสำหรับ %@", "zh": "为 %@ 配置费用", "ja": "%@ の料金設定", "ko": "%@ 수수료 설정", "id": "Atur biaya untuk %@", "ms": "Tetapkan yuran untuk %@"],
        "confirm_cancel_session_message": ["en": "Are you sure you want to cancel this session?", "th": "คุณแน่ใจหรือว่าต้องการยกเลิกเซสชันนี้?", "zh": "确定要取消此会话吗?", "ja": "このセッションをキャンセルしますか?", "ko": "이 세션을 취소하시겠습니까?", "id": "Yakin ingin membatalkan sesi ini?", "ms": "Pasti mahu batalkan sesi ini?"],
        "confirm_cancel_session_title": ["en": "Cancel Session", "th": "ยกเลิกเซสชัน", "zh": "取消会话", "ja": "セッションキャンセル", "ko": "세션 취소", "id": "Batalkan Sesi", "ms": "Batal Sesi"],
        "confirm_exit_btn": ["en": "Confirm Exit", "th": "ยืนยันออก", "zh": "确认退出", "ja": "終了確認", "ko": "종료 확인", "id": "Konfirmasi Keluar", "ms": "Sahkan Keluar"],
        "confirm_payment_btn": ["en": "Confirm Payment", "th": "ยืนยันการชำระ", "zh": "确认支付", "ja": "支払い確認", "ko": "결제 확인", "id": "Konfirmasi Pembayaran", "ms": "Sahkan Pembayaran"],
        "connecting_to_terminal": ["en": "Connecting to Terminal", "th": "กำลังเชื่อมต่อเทอร์มินัล", "zh": "正在连接终端", "ja": "端末に接続中", "ko": "단말기 연결 중", "id": "Menghubungkan ke Terminal", "ms": "Menyambung ke Terminal"],
        "connecting_to_terminal_desc": ["en": "Please wait while connecting to payment terminal...", "th": "กรุณารอขณะเชื่อมต่อเครื่องรับชำระ...", "zh": "正在连接支付终端，请稍候...", "ja": "決済端末に接続中です...", "ko": "결제 단말기에 연결하는 중입니다...", "id": "Mohon tunggu saat menghubungkan ke terminal...", "ms": "Sila tunggu semasa menyambung ke terminal..."],
        "contact_person_name_label": ["en": "Contact Person", "th": "ชื่อผู้ติดต่อ", "zh": "联系人", "ja": "担当者名", "ko": "담당자명", "id": "Nama Kontak", "ms": "Nama Hubungan"],
        "contact_person_name_placeholder": ["en": "Enter contact person name", "th": "ใส่ชื่อผู้ติดต่อ", "zh": "输入联系人姓名", "ja": "担当者名を入力", "ko": "담당자명 입력", "id": "Masukkan nama kontak", "ms": "Masukkan nama hubungan"],
        "cost_header": ["en": "Cost", "th": "ต้นทุน", "zh": "成本", "ja": "原価", "ko": "비용", "id": "Biaya", "ms": "Kos"],
        "cost_per_unit_template": ["en": "Cost/unit: ฿%@", "th": "ต้นทุน/หน่วย: ฿%@", "zh": "单位成本: ฿%@", "ja": "単価: ฿%@", "ko": "단가: ฿%@", "id": "Biaya/unit: ฿%@", "ms": "Kos/unit: ฿%@"],
        "cost_template": ["en": "Cost: ฿%@", "th": "ต้นทุน: ฿%@", "zh": "成本: ฿%@", "ja": "原価: ฿%@", "ko": "비용: ฿%@", "id": "Biaya: ฿%@", "ms": "Kos: ฿%@"],
        "cost_used_header": ["en": "Cost Used", "th": "ต้นทุนที่ใช้", "zh": "使用成本", "ja": "使用原価", "ko": "사용 비용", "id": "Biaya Terpakai", "ms": "Kos Digunakan"],
        "create_branch_title": ["en": "Create Branch", "th": "สร้างสาขา", "zh": "创建分店", "ja": "支店作成", "ko": "지점 만들기", "id": "Buat Cabang", "ms": "Cipta Cawangan"],
        "current_shift_tab": ["en": "Current Shift", "th": "กะปัจจุบัน", "zh": "当前班次", "ja": "現在のシフト", "ko": "현재 교대", "id": "Shift Saat Ini", "ms": "Syif Semasa"],
        "customize_title_prefix": ["en": "Customize", "th": "ปรับแต่ง", "zh": "自定义", "ja": "カスタマイズ", "ko": "맞춤 설정", "id": "Kustomisasi", "ms": "Sesuaikan"],
        "danger_zone": ["en": "Danger Zone", "th": "โซนอันตราย", "zh": "危险区域", "ja": "危険ゾーン", "ko": "위험 구역", "id": "Zona Bahaya", "ms": "Zon Bahaya"],
        "danger_zone_title": ["en": "Danger Zone", "th": "โซนอันตราย", "zh": "危险区域", "ja": "危険ゾーン", "ko": "위험 구역", "id": "Zona Bahaya", "ms": "Zon Bahaya"],
        "dark_mode": ["en": "Dark Mode", "th": "โหมดมืด", "zh": "深色模式", "ja": "ダークモード", "ko": "다크 모드", "id": "Mode Gelap", "ms": "Mod Gelap"],
        "dark_mode_desc": ["en": "Switch to dark theme", "th": "เปลี่ยนเป็นธีมมืด", "zh": "切换至深色主题", "ja": "ダークテーマに切替", "ko": "다크 테마로 전환", "id": "Beralih ke tema gelap", "ms": "Tukar ke tema gelap"],
        "date_header": ["en": "Date", "th": "วันที่", "zh": "日期", "ja": "日付", "ko": "날짜", "id": "Tanggal", "ms": "Tarikh"],
        "date_label": ["en": "Date", "th": "วันที่", "zh": "日期", "ja": "日付", "ko": "날짜", "id": "Tanggal", "ms": "Tarikh"],
        "default_tax_rate": ["en": "Default Tax Rate", "th": "อัตราภาษีเริ่มต้น", "zh": "默认税率", "ja": "デフォルト税率", "ko": "기본 세율", "id": "Tarif Pajak Default", "ms": "Kadar Cukai Lalai"],
        "delete_btn_label": ["en": "Delete", "th": "ลบ", "zh": "删除", "ja": "削除", "ko": "삭제", "id": "Hapus", "ms": "Padam"],
        "delete_category_btn": ["en": "Delete Category", "th": "ลบหมวดหมู่", "zh": "删除分类", "ja": "カテゴリー削除", "ko": "카테고리 삭제", "id": "Hapus Kategori", "ms": "Padam Kategori"],
        "delete_category_confirm_msg": ["en": "Are you sure you want to delete this category?", "th": "คุณแน่ใจหรือว่าต้องการลบหมวดหมู่นี้?", "zh": "确定要删除此分类吗?", "ja": "このカテゴリーを削除しますか?", "ko": "이 카테고리를 삭제하시겠습니까?", "id": "Yakin ingin menghapus kategori ini?", "ms": "Pasti mahu padam kategori ini?"],
        "delete_category_danger_desc": ["en": "This action cannot be undone", "th": "การดำเนินการนี้ไม่สามารถยกเลิกได้", "zh": "此操作无法撤销", "ja": "この操作は元に戻せません", "ko": "이 작업은 취소할 수 없습니다", "id": "Tindakan ini tidak dapat dibatalkan", "ms": "Tindakan ini tidak boleh dibatalkan"],
        "delete_item_alert_title": ["en": "Delete Item", "th": "ลบรายการ", "zh": "删除商品", "ja": "商品削除", "ko": "항목 삭제", "id": "Hapus Item", "ms": "Padam Item"],
        "delete_modifier_group_btn": ["en": "Delete Modifier Group", "th": "ลบกลุ่มตัวเลือก", "zh": "删除修饰组", "ja": "修飾グループ削除", "ko": "수정자 그룹 삭제", "id": "Hapus Grup Modifier", "ms": "Padam Kumpulan Pengubah"],
        "delete_modifier_group_confirm": ["en": "Are you sure you want to delete this modifier group?", "th": "คุณแน่ใจหรือว่าต้องการลบกลุ่มตัวเลือกนี้?", "zh": "确定要删除此修饰组吗?", "ja": "この修飾グループを削除しますか?", "ko": "이 수정자 그룹을 삭제하시겠습니까?", "id": "Yakin ingin menghapus grup modifier ini?", "ms": "Pasti mahu padam kumpulan pengubah ini?"],
        "delete_modifier_group_danger_desc": ["en": "All options in this group will be removed", "th": "ตัวเลือกทั้งหมดในกลุ่มนี้จะถูกลบ", "zh": "此组中的所有选项将被删除", "ja": "このグループの全オプションが削除されます", "ko": "이 그룹의 모든 옵션이 제거됩니다", "id": "Semua opsi dalam grup ini akan dihapus", "ms": "Semua pilihan dalam kumpulan ini akan dipadam"],
        "delete_option_btn": ["en": "Delete Option", "th": "ลบตัวเลือก", "zh": "删除选项", "ja": "オプション削除", "ko": "옵션 삭제", "id": "Hapus Opsi", "ms": "Padam Pilihan"],
        "delete_option_confirm": ["en": "Are you sure you want to delete this option?", "th": "คุณแน่ใจหรือว่าต้องการลบตัวเลือกนี้?", "zh": "确定要删除此选项吗?", "ja": "このオプションを削除しますか?", "ko": "이 옵션을 삭제하시겠습니까?", "id": "Yakin ingin menghapus opsi ini?", "ms": "Pasti mahu padam pilihan ini?"],
        "delete_product_confirm_msg": ["en": "Are you sure you want to delete this product?", "th": "คุณแน่ใจหรือว่าต้องการลบสินค้านี้?", "zh": "确定要删除此产品吗?", "ja": "この商品を削除しますか?", "ko": "이 상품을 삭제하시겠습니까?", "id": "Yakin ingin menghapus produk ini?", "ms": "Pasti mahu padam produk ini?"],
        "delete_product_danger_desc": ["en": "This will permanently remove the product", "th": "สินค้าจะถูกลบอย่างถาวร", "zh": "这将永久删除该产品", "ja": "商品が完全に削除されます", "ko": "상품이 영구적으로 삭제됩니다", "id": "Ini akan menghapus produk secara permanen", "ms": "Ini akan memadam produk secara kekal"],
        "delete_purchase_order": ["en": "Delete Purchase Order", "th": "ลบใบสั่งซื้อ", "zh": "删除采购单", "ja": "発注書削除", "ko": "구매 주문 삭제", "id": "Hapus Pesanan Beli", "ms": "Padam Pesanan Beli"],
        "delete_shift_btn": ["en": "Delete Shift", "th": "ลบกะ", "zh": "删除班次", "ja": "シフト削除", "ko": "교대 삭제", "id": "Hapus Shift", "ms": "Padam Syif"],
        "delete_this_item_btn": ["en": "Delete This Item", "th": "ลบรายการนี้", "zh": "删除此商品", "ja": "この商品を削除", "ko": "이 항목 삭제", "id": "Hapus Item Ini", "ms": "Padam Item Ini"],
        "details_header": ["en": "Details", "th": "รายละเอียด", "zh": "详情", "ja": "詳細", "ko": "상세", "id": "Detail", "ms": "Butiran"],
        "disabled_label": ["en": "Disabled", "th": "ปิดใช้งาน", "zh": "已禁用", "ja": "無効", "ko": "비활성화", "id": "Dinonaktifkan", "ms": "Dinyahaktifkan"],
        "discrepancy_label": ["en": "Discrepancy", "th": "ส่วนต่าง", "zh": "差异", "ja": "差異", "ko": "차이", "id": "Selisih", "ms": "Perbezaan"],
        "discrepancy_label_colon": ["en": "Discrepancy:", "th": "ส่วนต่าง:", "zh": "差异:", "ja": "差異:", "ko": "차이:", "id": "Selisih:", "ms": "Perbezaan:"],
        "discrepancy_reason_placeholder": ["en": "Enter reason for discrepancy", "th": "ใส่เหตุผลสำหรับส่วนต่าง", "zh": "输入差异原因", "ja": "差異の理由を入力", "ko": "차이 사유 입력", "id": "Masukkan alasan selisih", "ms": "Masukkan sebab perbezaan"],
        "edc_terminal_ready": ["en": "EDC Terminal Ready", "th": "เครื่อง EDC พร้อม", "zh": "EDC终端就绪", "ja": "EDC端末準備完了", "ko": "EDC 단말기 준비 완료", "id": "Terminal EDC Siap", "ms": "Terminal EDC Sedia"],
        "edit_btn_label": ["en": "Edit", "th": "แก้ไข", "zh": "编辑", "ja": "編集", "ko": "편집", "id": "Edit", "ms": "Edit"],
        "edit_details": ["en": "Edit Details", "th": "แก้ไขรายละเอียด", "zh": "编辑详情", "ja": "詳細を編集", "ko": "상세 편집", "id": "Edit Detail", "ms": "Edit Butiran"],
        "edit_employee": ["en": "Edit Employee", "th": "แก้ไขพนักงาน", "zh": "编辑员工", "ja": "従業員編集", "ko": "직원 편집", "id": "Edit Karyawan", "ms": "Edit Pekerja"],
        "edit_item_details_title": ["en": "Edit Item Details", "th": "แก้ไขรายละเอียดสินค้า", "zh": "编辑商品详情", "ja": "商品詳細を編集", "ko": "항목 상세 편집", "id": "Edit Detail Item", "ms": "Edit Butiran Item"],
        "email_address_label": ["en": "Email Address", "th": "อีเมล", "zh": "邮箱地址", "ja": "メールアドレス", "ko": "이메일 주소", "id": "Alamat Email", "ms": "Alamat E-mel"],
        "email_address_placeholder": ["en": "Enter email address", "th": "ใส่อีเมล", "zh": "输入邮箱地址", "ja": "メールアドレスを入力", "ko": "이메일 주소 입력", "id": "Masukkan alamat email", "ms": "Masukkan alamat e-mel"],
        "email_btn": ["en": "Email", "th": "อีเมล", "zh": "邮件", "ja": "メール", "ko": "이메일", "id": "Email", "ms": "E-mel"],
        "emergency_contact_header": ["en": "Emergency Contact", "th": "ผู้ติดต่อฉุกเฉิน", "zh": "紧急联系人", "ja": "緊急連絡先", "ko": "긴급 연락처", "id": "Kontak Darurat", "ms": "Hubungan Kecemasan"],
        "enable_table_system": ["en": "Enable Table System", "th": "เปิดระบบโต๊ะ", "zh": "启用桌位系统", "ja": "テーブルシステム有効化", "ko": "테이블 시스템 활성화", "id": "Aktifkan Sistem Meja", "ms": "Aktifkan Sistem Meja"],
        "end_shift_btn": ["en": "End Shift", "th": "จบกะ", "zh": "结束班次", "ja": "シフト終了", "ko": "교대 종료", "id": "Akhiri Shift", "ms": "Tamat Syif"],
        "estimated_net_lbl": ["en": "Estimated Net", "th": "ประมาณการสุทธิ", "zh": "预估净额", "ja": "予想純額", "ko": "예상 순액", "id": "Estimasi Bersih", "ms": "Anggaran Bersih"],
        "expected_calculated_balance": ["en": "Expected Balance", "th": "ยอดที่คาดไว้", "zh": "预期余额", "ja": "予想残高", "ko": "예상 잔액", "id": "Saldo Diharapkan", "ms": "Baki Dijangka"],
        "expected_cash_drawer": ["en": "Expected Cash in Drawer", "th": "เงินสดที่คาดว่าอยู่ในลิ้นชัก", "zh": "预期抽屉现金", "ja": "ドロワー内予想現金", "ko": "서랍 예상 현금", "id": "Tunai yang Diharapkan di Laci", "ms": "Tunai Dijangka dalam Laci"],
        "expected_cash_label": ["en": "Expected Cash", "th": "เงินสดที่คาดไว้", "zh": "预期现金", "ja": "予想現金", "ko": "예상 현금", "id": "Tunai Diharapkan", "ms": "Tunai Dijangka"],
        "expires_label": ["en": "Expires", "th": "หมดอายุ", "zh": "过期", "ja": "有効期限", "ko": "만료", "id": "Kedaluwarsa", "ms": "Tamat Tempoh"],
        "expiry_label": ["en": "Expiry", "th": "วันหมดอายุ", "zh": "到期日", "ja": "有効期限", "ko": "만료일", "id": "Kadaluarsa", "ms": "Tarikh Luput"],
        "filter_all": ["en": "All", "th": "ทั้งหมด", "zh": "全部", "ja": "全て", "ko": "전체", "id": "Semua", "ms": "Semua"],
        "filter_ingredients_audit": ["en": "Ingredients Audit", "th": "ตรวจนับวัตถุดิบ", "zh": "原料审计", "ja": "材料棚卸し", "ko": "재료 감사", "id": "Audit Bahan", "ms": "Audit Bahan"],
        "filter_low_stock": ["en": "Low Stock", "th": "สต็อกต่ำ", "zh": "低库存", "ja": "在庫少", "ko": "재고 부족", "id": "Stok Rendah", "ms": "Stok Rendah"],
        "filter_out_of_stock": ["en": "Out of Stock", "th": "หมดสต็อก", "zh": "缺货", "ja": "在庫切れ", "ko": "품절", "id": "Stok Habis", "ms": "Stok Habis"],
        "financial_summary_lbl": ["en": "Financial Summary", "th": "สรุปทางการเงิน", "zh": "财务摘要", "ja": "財務サマリー", "ko": "재무 요약", "id": "Ringkasan Keuangan", "ms": "Ringkasan Kewangan"],
        "finished_good_settings": ["en": "Finished Good Settings", "th": "ตั้งค่าสินค้าสำเร็จรูป", "zh": "成品设置", "ja": "完成品設定", "ko": "완제품 설정", "id": "Pengaturan Barang Jadi", "ms": "Tetapan Barang Siap"],
        "finished_good_settings_desc": ["en": "Configure tracking for finished goods", "th": "ตั้งค่าการติดตามสินค้าสำเร็จรูป", "zh": "配置成品跟踪", "ja": "完成品の追跡設定", "ko": "완제품 추적 설정", "id": "Atur pelacakan barang jadi", "ms": "Tetapkan penjejakan barang siap"],
        "finished_goods_map_desc": ["en": "Map finished goods to recipes", "th": "เชื่อมโยงสินค้าสำเร็จรูปกับสูตร", "zh": "将成品映射到食谱", "ja": "完成品をレシピに紐付け", "ko": "완제품을 레시피에 매핑", "id": "Petakan barang jadi ke resep", "ms": "Petakan barang siap ke resipi"],
        "food_cost_pct": ["en": "Food Cost %", "th": "% ต้นทุนอาหาร", "zh": "食材成本 %", "ja": "原価率 %", "ko": "식재료 원가 %", "id": "Biaya Bahan %", "ms": "Kos Makanan %"],
        "food_cost_template": ["en": "Food Cost: %@%%", "th": "ต้นทุนอาหาร: %@%%", "zh": "食材成本: %@%%", "ja": "原価率: %@%%", "ko": "식재료 원가: %@%%", "id": "Biaya Bahan: %@%%", "ms": "Kos Makanan: %@%%"],
        "full_address_label": ["en": "Full Address", "th": "ที่อยู่เต็ม", "zh": "完整地址", "ja": "完全な住所", "ko": "전체 주소", "id": "Alamat Lengkap", "ms": "Alamat Penuh"],
        "full_address_placeholder": ["en": "Enter full address", "th": "ใส่ที่อยู่เต็ม", "zh": "输入完整地址", "ja": "完全な住所を入力", "ko": "전체 주소 입력", "id": "Masukkan alamat lengkap", "ms": "Masukkan alamat penuh"],
        "generated_at_lbl": ["en": "Generated At", "th": "สร้างเมื่อ", "zh": "生成时间", "ja": "生成日時", "ko": "생성일시", "id": "Dibuat Pada", "ms": "Dijana Pada"],
        "go_to_cash_drawer": ["en": "Go to Cash Drawer", "th": "ไปที่ลิ้นชักเงิน", "zh": "前往收银台", "ja": "キャッシュドロワーへ", "ko": "현금 서랍으로 이동", "id": "Buka Laci Kas", "ms": "Pergi ke Laci Tunai"],
        "go_to_table_layout": ["en": "Go to Table Layout", "th": "ไปที่ผังโต๊ะ", "zh": "前往桌位布局", "ja": "テーブルレイアウトへ", "ko": "테이블 배치로 이동", "id": "Buka Tata Letak Meja", "ms": "Pergi ke Susun Atur Meja"],
        "gp_fee_header": ["en": "GP Fee", "th": "ค่า GP", "zh": "GP费用", "ja": "GP手数料", "ko": "GP 수수료", "id": "Biaya GP", "ms": "Yuran GP"],
        "held_orders_none": ["en": "No Held Orders", "th": "ไม่มีออเดอร์ที่พัก", "zh": "没有挂起订单", "ja": "保留注文なし", "ko": "보류 주문 없음", "id": "Tidak Ada Pesanan Ditahan", "ms": "Tiada Pesanan Ditahan"],
        "held_orders_none_desc": ["en": "Orders you hold will appear here", "th": "ออเดอร์ที่พักจะแสดงที่นี่", "zh": "挂起的订单将显示在这里", "ja": "保留した注文はここに表示されます", "ko": "보류한 주문이 여기에 표시됩니다", "id": "Pesanan yang ditahan akan muncul di sini", "ms": "Pesanan yang ditahan akan muncul di sini"],
        "held_orders_title": ["en": "Held Orders", "th": "ออเดอร์ที่พัก", "zh": "挂起订单", "ja": "保留注文", "ko": "보류 주문", "id": "Pesanan Ditahan", "ms": "Pesanan Ditahan"],
        "held_orders_void_confirm_template": ["en": "Void held order #%@?", "th": "ยกเลิกออเดอร์ที่พัก #%@?", "zh": "作废挂起订单 #%@?", "ja": "保留注文 #%@ を取消しますか?", "ko": "보류 주문 #%@를 무효화하시겠습니까?", "id": "Batalkan pesanan ditahan #%@?", "ms": "Batal pesanan ditahan #%@?"],
        "home_address_header": ["en": "Home Address", "th": "ที่อยู่บ้าน", "zh": "家庭住址", "ja": "自宅住所", "ko": "자택 주소", "id": "Alamat Rumah", "ms": "Alamat Rumah"],
        "hours_header": ["en": "Hours", "th": "ชั่วโมง", "zh": "小时", "ja": "時間", "ko": "시간", "id": "Jam", "ms": "Jam"],
        "hours_worked_label": ["en": "Hours Worked", "th": "ชั่วโมงทำงาน", "zh": "工作小时", "ja": "勤務時間", "ko": "근무 시간", "id": "Jam Kerja", "ms": "Jam Bekerja"],
        "incoming_stock": ["en": "Incoming Stock", "th": "สต็อกขาเข้า", "zh": "入库库存", "ja": "入荷在庫", "ko": "입고 재고", "id": "Stok Masuk", "ms": "Stok Masuk"],
        "ingredient_header": ["en": "Ingredient", "th": "วัตถุดิบ", "zh": "原料", "ja": "材料", "ko": "재료", "id": "Bahan", "ms": "Bahan"],
        "ingredients_linked_template": ["en": "%@ ingredients linked", "th": "%@ วัตถุดิบที่เชื่อมโยง", "zh": "%@ 种原料已关联", "ja": "%@ 材料リンク済み", "ko": "%@개 재료 연결됨", "id": "%@ bahan terhubung", "ms": "%@ bahan dipautkan"],
        "initial_value_label": ["en": "Initial Value", "th": "มูลค่าเริ่มต้น", "zh": "初始值", "ja": "初期値", "ko": "초기값", "id": "Nilai Awal", "ms": "Nilai Awal"],
        "initial_value_placeholder": ["en": "Enter initial value", "th": "ใส่มูลค่าเริ่มต้น", "zh": "输入初始值", "ja": "初期値を入力", "ko": "초기값 입력", "id": "Masukkan nilai awal", "ms": "Masukkan nilai awal"],
        "invoice_reference_note": ["en": "Invoice/Reference Note", "th": "เลขที่ใบแจ้งหนี้/อ้างอิง", "zh": "发票/参考号", "ja": "請求書/参照メモ", "ko": "송장/참조 메모", "id": "Nota Invoice/Referensi", "ms": "Nota Invois/Rujukan"],
        "issue_btn": ["en": "Issue", "th": "ออก", "zh": "发放", "ja": "発行", "ko": "발행", "id": "Terbitkan", "ms": "Keluarkan"],
        "issue_card_btn": ["en": "Issue Card", "th": "ออกบัตร", "zh": "发卡", "ja": "カード発行", "ko": "카드 발행", "id": "Terbitkan Kartu", "ms": "Keluarkan Kad"],
        "issue_gift_card_title": ["en": "Issue Gift Card", "th": "ออกบัตรของขวัญ", "zh": "发放礼品卡", "ja": "ギフトカード発行", "ko": "기프트카드 발행", "id": "Terbitkan Kartu Hadiah", "ms": "Keluarkan Kad Hadiah"],
        "item_details": ["en": "Item Details", "th": "รายละเอียดสินค้า", "zh": "商品详情", "ja": "商品詳細", "ko": "항목 상세", "id": "Detail Item", "ms": "Butiran Item"],
        "item_header": ["en": "Item", "th": "รายการ", "zh": "商品", "ja": "商品", "ko": "항목", "id": "Item", "ms": "Item"],
        "item_history_title_template": ["en": "History: %@", "th": "ประวัติ: %@", "zh": "历史: %@", "ja": "履歴: %@", "ko": "내역: %@", "id": "Riwayat: %@", "ms": "Sejarah: %@"],
        "item_information": ["en": "Item Information", "th": "ข้อมูลสินค้า", "zh": "商品信息", "ja": "商品情報", "ko": "항목 정보", "id": "Informasi Item", "ms": "Maklumat Item"],
        "item_level": ["en": "Item Level", "th": "ระดับสินค้า", "zh": "商品层级", "ja": "商品レベル", "ko": "항목 레벨", "id": "Level Item", "ms": "Tahap Item"],
        "item_name": ["en": "Item Name", "th": "ชื่อสินค้า", "zh": "商品名", "ja": "商品名", "ko": "항목명", "id": "Nama Item", "ms": "Nama Item"],
        "item_name_header": ["en": "Item Name", "th": "ชื่อสินค้า", "zh": "商品名称", "ja": "商品名", "ko": "상품명", "id": "Nama Item", "ms": "Nama Item"],
        "item_name_placeholder": ["en": "Enter item name", "th": "ใส่ชื่อสินค้า", "zh": "输入商品名", "ja": "商品名を入力", "ko": "항목명 입력", "id": "Masukkan nama item", "ms": "Masukkan nama item"],
        "item_void": ["en": "Void Item", "th": "ยกเลิกรายการ", "zh": "作废商品", "ja": "商品取消", "ko": "항목 무효화", "id": "Batalkan Item", "ms": "Batal Item"],
        "items_count_template": ["en": "%@ items", "th": "%@ รายการ", "zh": "%@ 项", "ja": "%@ 品", "ko": "%@ 항목", "id": "%@ item", "ms": "%@ item"],
        "items_selected_count": ["en": "items selected", "th": "รายการที่เลือก", "zh": "项已选", "ja": "品選択中", "ko": "항목 선택됨", "id": "item dipilih", "ms": "item dipilih"],
        "items_sold_header": ["en": "Items Sold", "th": "จำนวนที่ขาย", "zh": "售出数量", "ja": "販売数", "ko": "판매 수량", "id": "Item Terjual", "ms": "Item Terjual"],
        "items_to_audit": ["en": "Items to Audit", "th": "รายการที่ต้องตรวจนับ", "zh": "待审计项", "ja": "棚卸し対象商品", "ko": "감사 대상 항목", "id": "Item untuk Diaudit", "ms": "Item untuk Diaudit"],
        "key_template": ["en": "%@", "th": "%@", "zh": "%@", "ja": "%@", "ko": "%@", "id": "%@", "ms": "%@"],
        "last_entries_template": ["en": "Last %@ entries", "th": "%@ รายการล่าสุด", "zh": "最近 %@ 条记录", "ja": "最新 %@ 件", "ko": "최근 %@ 건", "id": "%@ entri terakhir", "ms": "%@ entri terakhir"],
        "link_customization_desc": ["en": "Customize link appearance", "th": "ปรับแต่งลักษณะลิงก์", "zh": "自定义链接外观", "ja": "リンクの外観をカスタマイズ", "ko": "링크 모양 맞춤 설정", "id": "Kustomisasi tampilan tautan", "ms": "Sesuaikan penampilan pautan"],
        "link_customization_options": ["en": "Link Customization", "th": "ปรับแต่งลิงก์", "zh": "链接自定义", "ja": "リンクカスタマイズ", "ko": "링크 맞춤 설정", "id": "Kustomisasi Tautan", "ms": "Penyesuaian Pautan"],
        "link_to_order_btn": ["en": "Link to Order", "th": "เชื่อมกับออเดอร์", "zh": "关联订单", "ja": "注文にリンク", "ko": "주문에 연결", "id": "Hubungkan ke Pesanan", "ms": "Paut ke Pesanan"],
        "linked_customer_label": ["en": "Linked Customer", "th": "ลูกค้าที่เชื่อมโยง", "zh": "关联客户", "ja": "リンク済み顧客", "ko": "연결된 고객", "id": "Pelanggan Terhubung", "ms": "Pelanggan Dipautkan"],
        "live_tax_invoice_preview": ["en": "Live Tax Invoice Preview", "th": "ตัวอย่างใบกำกับภาษี", "zh": "税票实时预览", "ja": "税インボイスプレビュー", "ko": "세금 계산서 미리보기", "id": "Pratinjau Faktur Pajak", "ms": "Pratonton Invois Cukai"],
        "load_more_items": ["en": "Load More Items", "th": "โหลดเพิ่มเติม", "zh": "加载更多", "ja": "さらに読み込む", "ko": "더 불러오기", "id": "Muat Lebih Banyak", "ms": "Muat Lebih Banyak"],
        "location_label": ["en": "Location", "th": "ที่ตั้ง", "zh": "位置", "ja": "場所", "ko": "위치", "id": "Lokasi", "ms": "Lokasi"],
        "logged_in_email": ["en": "Logged in as", "th": "เข้าสู่ระบบเป็น", "zh": "已登录", "ja": "ログイン中", "ko": "로그인됨", "id": "Masuk sebagai", "ms": "Log masuk sebagai"],
        "lookup_card_placeholder": ["en": "Enter card number to look up", "th": "ใส่หมายเลขบัตรเพื่อค้นหา", "zh": "输入卡号查询", "ja": "カード番号を入力して検索", "ko": "카드 번호를 입력하여 조회", "id": "Masukkan nomor kartu untuk dicari", "ms": "Masukkan nombor kad untuk carian"],
        "loops_label": ["en": "Loops", "th": "วนซ้ำ", "zh": "循环", "ja": "ループ", "ko": "반복", "id": "Loop", "ms": "Gelung"],
        "margin_header_short": ["en": "Margin", "th": "กำไร", "zh": "利润", "ja": "利益", "ko": "마진", "id": "Margin", "ms": "Margin"],
        "margin_pct": ["en": "Margin %", "th": "% กำไร", "zh": "利润率 %", "ja": "利益率 %", "ko": "마진 %", "id": "Margin %", "ms": "Margin %"],
        "margin_template": ["en": "Margin: %@%%", "th": "อัตรากำไร: %@%%", "zh": "利润率: %@%%", "ja": "利益率: %@%%", "ko": "마진: %@%%", "id": "Margin: %@%%", "ms": "Margin: %@%%"],
        "margins_analysis_title": ["en": "Margins Analysis", "th": "วิเคราะห์อัตรากำไร", "zh": "利润分析", "ja": "利益率分析", "ko": "마진 분석", "id": "Analisis Margin", "ms": "Analisis Margin"],
        "match_system_theme": ["en": "Match System Theme", "th": "ตามธีมระบบ", "zh": "跟随系统主题", "ja": "システムテーマに合わせる", "ko": "시스템 테마에 맞추기", "id": "Ikuti Tema Sistem", "ms": "Ikut Tema Sistem"],
        "match_system_theme_desc": ["en": "Automatically match system appearance", "th": "ปรับตามธีมระบบอัตโนมัติ", "zh": "自动跟随系统外观", "ja": "システム外観に自動的に合わせる", "ko": "시스템 외관에 자동으로 맞추기", "id": "Otomatis ikuti tampilan sistem", "ms": "Ikut penampilan sistem secara automatik"],
        "max_selection_label": ["en": "Max Selection", "th": "เลือกสูงสุด", "zh": "最大选择", "ja": "最大選択数", "ko": "최대 선택", "id": "Pilihan Maksimal", "ms": "Pilihan Maksimum"],
        "method_header": ["en": "Method", "th": "วิธี", "zh": "方式", "ja": "方法", "ko": "방법", "id": "Metode", "ms": "Kaedah"],
        "min_selection_label": ["en": "Min Selection", "th": "เลือกขั้นต่ำ", "zh": "最小选择", "ja": "最小選択数", "ko": "최소 선택", "id": "Pilihan Minimal", "ms": "Pilihan Minimum"],
        "month_label": ["en": "Month", "th": "เดือน", "zh": "月", "ja": "月", "ko": "월", "id": "Bulan", "ms": "Bulan"],
        "more_actions": ["en": "More Actions", "th": "การดำเนินการเพิ่มเติม", "zh": "更多操作", "ja": "その他のアクション", "ko": "추가 작업", "id": "Tindakan Lainnya", "ms": "Tindakan Lain"],
        "movement_history": ["en": "Movement History", "th": "ประวัติการเคลื่อนไหว", "zh": "变动历史", "ja": "移動履歴", "ko": "이동 내역", "id": "Riwayat Pergerakan", "ms": "Sejarah Pergerakan"],
        "movement_type_label": ["en": "Movement Type", "th": "ประเภทการเคลื่อนไหว", "zh": "变动类型", "ja": "移動種類", "ko": "이동 유형", "id": "Tipe Pergerakan", "ms": "Jenis Pergerakan"],
        "name_label": ["en": "Name", "th": "ชื่อ", "zh": "名称", "ja": "名前", "ko": "이름", "id": "Nama", "ms": "Nama"],
        "new_po_draft_title": ["en": "New PO (Draft)", "th": "PO ใหม่ (ฉบับร่าง)", "zh": "新采购单 (草稿)", "ja": "新規発注 (下書き)", "ko": "새 PO (초안)", "id": "PO Baru (Draft)", "ms": "PO Baru (Draf)"],
        "next_week_btn": ["en": "Next Week", "th": "สัปดาห์หน้า", "zh": "下周", "ja": "来週", "ko": "다음 주", "id": "Minggu Depan", "ms": "Minggu Depan"],
        "none_label": ["en": "None", "th": "ไม่มี", "zh": "无", "ja": "なし", "ko": "없음", "id": "Tidak Ada", "ms": "Tiada"],
        "note_btn_label": ["en": "Note", "th": "หมายเหตุ", "zh": "备注", "ja": "メモ", "ko": "메모", "id": "Catatan", "ms": "Nota"],
        "note_label_template": ["en": "Note: %@", "th": "หมายเหตุ: %@", "zh": "备注: %@", "ja": "メモ: %@", "ko": "메모: %@", "id": "Catatan: %@", "ms": "Nota: %@"],
        "note_placeholder": ["en": "Enter note...", "th": "ใส่หมายเหตุ...", "zh": "输入备注...", "ja": "メモを入力...", "ko": "메모 입력...", "id": "Masukkan catatan...", "ms": "Masukkan nota..."],
        "notes_field": ["en": "Notes", "th": "หมายเหตุ", "zh": "备注", "ja": "メモ", "ko": "메모", "id": "Catatan", "ms": "Nota"],
        "ok_btn": ["en": "OK", "th": "ตกลง", "zh": "确定", "ja": "OK", "ko": "확인", "id": "OK", "ms": "OK"],
        "ok_btn_label": ["en": "OK", "th": "ตกลง", "zh": "确定", "ja": "OK", "ko": "확인", "id": "OK", "ms": "OK"],
        "on_hand_label": ["en": "On Hand", "th": "มีอยู่", "zh": "库存数量", "ja": "手持ち在庫", "ko": "보유 수량", "id": "Tersedia", "ms": "Di Tangan"],
        "on_hand_with_unit_template": ["en": "On hand: %@ %@", "th": "มีอยู่: %@ %@", "zh": "库存: %@ %@", "ja": "手持ち: %@ %@", "ko": "보유: %@ %@", "id": "Tersedia: %@ %@", "ms": "Di tangan: %@ %@"],
        "open_scheduler": ["en": "Open Scheduler", "th": "เปิดตัวจัดตาราง", "zh": "打开排班", "ja": "スケジューラーを開く", "ko": "스케줄러 열기", "id": "Buka Penjadwal", "ms": "Buka Penjadual"],
        "open_session_btn": ["en": "Open Session", "th": "เปิดเซสชัน", "zh": "开始会话", "ja": "セッション開始", "ko": "세션 열기", "id": "Buka Sesi", "ms": "Buka Sesi"],
        "opened_at_label": ["en": "Opened At", "th": "เปิดเมื่อ", "zh": "开始时间", "ja": "開始時刻", "ko": "시작 시간", "id": "Dibuka Pada", "ms": "Dibuka Pada"],
        "opened_at_template": ["en": "Opened: %@", "th": "เปิดเมื่อ: %@", "zh": "开始: %@", "ja": "開始: %@", "ko": "시작: %@", "id": "Dibuka: %@", "ms": "Dibuka: %@"],
        "opened_date_label": ["en": "Opened Date", "th": "วันที่เปิด", "zh": "开始日期", "ja": "開始日", "ko": "시작일", "id": "Tanggal Dibuka", "ms": "Tarikh Dibuka"],
        "opening_float_label": ["en": "Opening Float", "th": "เงินเปิดกะ", "zh": "开班现金", "ja": "開始レジ金", "ko": "개시 현금", "id": "Float Pembukaan", "ms": "Wang Permulaan"],
        "opening_notes_label": ["en": "Opening Notes", "th": "หมายเหตุเปิดกะ", "zh": "开班备注", "ja": "開始メモ", "ko": "개시 메모", "id": "Catatan Pembukaan", "ms": "Nota Pembukaan"],
        "opening_notes_placeholder": ["en": "Add notes for this shift opening", "th": "เพิ่มหมายเหตุสำหรับการเปิดกะ", "zh": "添加开班备注", "ja": "シフト開始メモを追加", "ko": "교대 시작 메모 추가", "id": "Tambahkan catatan pembukaan shift", "ms": "Tambah nota pembukaan syif"],
        "option_info_title": ["en": "Option Info", "th": "ข้อมูลตัวเลือก", "zh": "选项信息", "ja": "オプション情報", "ko": "옵션 정보", "id": "Info Opsi", "ms": "Info Pilihan"],
        "options_count_template": ["en": "%@ options", "th": "%@ ตัวเลือก", "zh": "%@ 个选项", "ja": "%@ オプション", "ko": "%@ 옵션", "id": "%@ opsi", "ms": "%@ pilihan"],
        "orders_count_template": ["en": "%@ orders", "th": "%@ ออเดอร์", "zh": "%@ 个订单", "ja": "%@ 注文", "ko": "%@ 주문", "id": "%@ pesanan", "ms": "%@ pesanan"],
        "orders_header": ["en": "Orders", "th": "ออเดอร์", "zh": "订单", "ja": "注文", "ko": "주문", "id": "Pesanan", "ms": "Pesanan"],
        "outstanding_label": ["en": "Outstanding", "th": "ค้างชำระ", "zh": "未结清", "ja": "未払い", "ko": "미결제", "id": "Belum Dibayar", "ms": "Belum Dibayar"],
        "overage_label": ["en": "Overage", "th": "เกิน", "zh": "超额", "ja": "過剰", "ko": "초과", "id": "Kelebihan", "ms": "Lebihan"],
        "page_template": ["en": "Page %@", "th": "หน้า %@", "zh": "第 %@ 页", "ja": "ページ %@", "ko": "페이지 %@", "id": "Halaman %@", "ms": "Halaman %@"],
        "paid_in": ["en": "Paid In", "th": "เงินเข้า", "zh": "存入", "ja": "入金", "ko": "입금", "id": "Kas Masuk", "ms": "Tunai Masuk"],
        "paid_in_add_cash": ["en": "Paid In (Add Cash)", "th": "เงินเข้า (เพิ่มเงินสด)", "zh": "存入 (添加现金)", "ja": "入金 (現金追加)", "ko": "입금 (현금 추가)", "id": "Kas Masuk (Tambah Tunai)", "ms": "Tunai Masuk (Tambah Tunai)"],
        "paid_in_sub": ["en": "Add cash to drawer", "th": "เพิ่มเงินสดในลิ้นชัก", "zh": "向收银台添加现金", "ja": "ドロワーに現金追加", "ko": "서랍에 현금 추가", "id": "Tambah tunai ke laci", "ms": "Tambah tunai ke laci"],
        "paid_out": ["en": "Paid Out", "th": "เงินออก", "zh": "支出", "ja": "出金", "ko": "출금", "id": "Kas Keluar", "ms": "Tunai Keluar"],
        "paid_out_sub": ["en": "Remove cash from drawer", "th": "เอาเงินสดออกจากลิ้นชัก", "zh": "从收银台取出现金", "ja": "ドロワーから現金取出", "ko": "서랍에서 현금 제거", "id": "Ambil tunai dari laci", "ms": "Keluarkan tunai dari laci"],
        "paid_out_withdraw_cash": ["en": "Paid Out (Withdraw Cash)", "th": "เงินออก (ถอนเงินสด)", "zh": "支出 (取现金)", "ja": "出金 (現金引出)", "ko": "출금 (현금 인출)", "id": "Kas Keluar (Tarik Tunai)", "ms": "Tunai Keluar (Tarik Tunai)"],
        "paid_via_label": ["en": "Paid Via", "th": "ชำระผ่าน", "zh": "支付方式", "ja": "支払い方法", "ko": "결제 수단", "id": "Dibayar Via", "ms": "Dibayar Melalui"],
        "partially_refunded": ["en": "Partially Refunded", "th": "คืนเงินบางส่วน", "zh": "部分退款", "ja": "一部返金済み", "ko": "부분 환불됨", "id": "Refund Sebagian", "ms": "Bayaran Balik Separa"],
        "pax_count_template": ["en": "%@ pax", "th": "%@ คน", "zh": "%@ 位", "ja": "%@ 名", "ko": "%@ 명", "id": "%@ tamu", "ms": "%@ tetamu"],
        "pay_rate": ["en": "Pay Rate", "th": "อัตราค่าจ้าง", "zh": "薪资标准", "ja": "給与レート", "ko": "급여율", "id": "Tarif Gaji", "ms": "Kadar Gaji"],
        "pay_rate_label": ["en": "Pay Rate", "th": "อัตราค่าจ้าง", "zh": "薪资标准", "ja": "給与レート", "ko": "급여율", "id": "Tarif Gaji", "ms": "Kadar Gaji"],
        "peak_hour_lbl": ["en": "Peak Hour", "th": "ชั่วโมงเร่งด่วน", "zh": "高峰时段", "ja": "ピーク時間", "ko": "피크 시간", "id": "Jam Sibuk", "ms": "Jam Puncak"],
        "pending_audit": ["en": "Pending Audit", "th": "รอตรวจนับ", "zh": "待审计", "ja": "監査待ち", "ko": "감사 대기", "id": "Menunggu Audit", "ms": "Menunggu Audit"],
        "pending_face_scan_audits": ["en": "Pending Face Scan Audits", "th": "รอตรวจสอบสแกนใบหน้า", "zh": "待人脸扫描审核", "ja": "顔スキャン監査待ち", "ko": "대기 중인 얼굴 스캔 감사", "id": "Audit Scan Wajah Tertunda", "ms": "Audit Imbasan Muka Tertangguh"],
        "pending_status_tag": ["en": "Pending", "th": "รอดำเนินการ", "zh": "待处理", "ja": "保留中", "ko": "대기 중", "id": "Tertunda", "ms": "Tertangguh"],
        "personal_info_header": ["en": "Personal Information", "th": "ข้อมูลส่วนตัว", "zh": "个人信息", "ja": "個人情報", "ko": "개인 정보", "id": "Informasi Pribadi", "ms": "Maklumat Peribadi"],
        "phone_number_label": ["en": "Phone Number", "th": "เบอร์โทร", "zh": "电话号码", "ja": "電話番号", "ko": "전화번호", "id": "Nomor Telepon", "ms": "Nombor Telefon"],
        "phone_number_placeholder": ["en": "Enter phone number", "th": "ใส่เบอร์โทร", "zh": "输入电话号码", "ja": "電話番号を入力", "ko": "전화번호 입력", "id": "Masukkan nomor telepon", "ms": "Masukkan nombor telefon"],
        "phone_preview_lbl": ["en": "Phone", "th": "โทรศัพท์", "zh": "电话", "ja": "電話", "ko": "전화", "id": "Telepon", "ms": "Telefon"],
        "physical_cash_count": ["en": "Physical Cash Count", "th": "นับเงินสดจริง", "zh": "实际现金清点", "ja": "実地現金カウント", "ko": "실물 현금 계수", "id": "Hitung Tunai Fisik", "ms": "Kiraan Tunai Fizikal"],
        "pin_to_favorites": ["en": "Pin to Favorites", "th": "ปักหมุดเป็นรายการโปรด", "zh": "固定到收藏", "ja": "お気に入りに固定", "ko": "즐겨찾기에 고정", "id": "Sematkan ke Favorit", "ms": "Semat ke Kegemaran"],
        "platform_breakdown_lbl": ["en": "Platform Breakdown", "th": "แยกตามแพลตฟอร์ม", "zh": "平台明细", "ja": "プラットフォーム内訳", "ko": "플랫폼 내역", "id": "Rincian Platform", "ms": "Pecahan Platform"],
        "platform_header": ["en": "Platform", "th": "แพลตฟอร์ม", "zh": "平台", "ja": "プラットフォーム", "ko": "플랫폼", "id": "Platform", "ms": "Platform"],
        "please_swipe_card": ["en": "Please Swipe Card", "th": "กรุณารูดบัตร", "zh": "请刷卡", "ja": "カードをスワイプしてください", "ko": "카드를 밀어주세요", "id": "Silakan Gesek Kartu", "ms": "Sila Leret Kad"],
        "powered_by_alphapos": ["en": "Powered by AlphaPos", "th": "ขับเคลื่อนโดย AlphaPos", "zh": "由 AlphaPos 提供支持", "ja": "AlphaPos 提供", "ko": "AlphaPos 제공", "id": "Didukung oleh AlphaPos", "ms": "Dikuasakan oleh AlphaPos"],
        "prepared_by": ["en": "Prepared By", "th": "จัดทำโดย", "zh": "制作人", "ja": "作成者", "ko": "작성자", "id": "Disiapkan Oleh", "ms": "Disediakan Oleh"],
        "prev_week_btn": ["en": "Previous Week", "th": "สัปดาห์ก่อน", "zh": "上周", "ja": "先週", "ko": "이전 주", "id": "Minggu Lalu", "ms": "Minggu Lepas"],
        "price_template": ["en": "Price: ฿%@", "th": "ราคา: ฿%@", "zh": "价格: ฿%@", "ja": "価格: ฿%@", "ko": "가격: ฿%@", "id": "Harga: ฿%@", "ms": "Harga: ฿%@"],
        "process_btn": ["en": "Process", "th": "ดำเนินการ", "zh": "处理", "ja": "処理", "ko": "처리", "id": "Proses", "ms": "Proses"],
        "process_refund_btn": ["en": "Process Refund", "th": "ดำเนินการคืนเงิน", "zh": "处理退款", "ja": "返金処理", "ko": "환불 처리", "id": "Proses Refund", "ms": "Proses Bayaran Balik"],
        "processing_payment_desc": ["en": "Processing payment...", "th": "กำลังดำเนินการชำระเงิน...", "zh": "正在处理支付...", "ja": "支払い処理中...", "ko": "결제 처리 중...", "id": "Memproses pembayaran...", "ms": "Memproses pembayaran..."],
        "prod_delete_btn": ["en": "Delete Product", "th": "ลบสินค้า", "zh": "删除产品", "ja": "商品削除", "ko": "상품 삭제", "id": "Hapus Produk", "ms": "Padam Produk"],
        "products_count_template": ["en": "%@ products", "th": "%@ สินค้า", "zh": "%@ 个产品", "ja": "%@ 商品", "ko": "%@ 상품", "id": "%@ produk", "ms": "%@ produk"],
        "profit_template": ["en": "Profit: ฿%@", "th": "กำไร: ฿%@", "zh": "利润: ฿%@", "ja": "利益: ฿%@", "ko": "이익: ฿%@", "id": "Laba: ฿%@", "ms": "Keuntungan: ฿%@"],
        "qr_custom_header": ["en": "Custom QR Code", "th": "คิวอาร์โค้ดกำหนดเอง", "zh": "自定义二维码", "ja": "カスタムQRコード", "ko": "맞춤 QR 코드", "id": "Kode QR Kustom", "ms": "Kod QR Tersuai"],
        "qty_header": ["en": "Qty", "th": "จำนวน", "zh": "数量", "ja": "数量", "ko": "수량", "id": "Qty", "ms": "Qty"],
        "qty_sold_header": ["en": "Qty Sold", "th": "จำนวนที่ขาย", "zh": "售出数量", "ja": "販売数", "ko": "판매 수량", "id": "Qty Terjual", "ms": "Qty Terjual"],
        "quantity_exceeds_stock_error": ["en": "Quantity exceeds available stock", "th": "จำนวนเกินสต็อกที่มี", "zh": "数量超出可用库存", "ja": "数量が利用可能在庫を超えています", "ko": "수량이 가용 재고를 초과합니다", "id": "Jumlah melebihi stok tersedia", "ms": "Kuantiti melebihi stok tersedia"],
        "quantity_per_item": ["en": "Quantity per Item", "th": "จำนวนต่อรายการ", "zh": "每项数量", "ja": "商品あたり数量", "ko": "항목당 수량", "id": "Jumlah per Item", "ms": "Kuantiti per Item"],
        "quick_templates_title": ["en": "Quick Templates", "th": "เทมเพลตด่วน", "zh": "快速模板", "ja": "クイックテンプレート", "ko": "빠른 템플릿", "id": "Templat Cepat", "ms": "Templat Pantas"],
        "reason_audit_correction": ["en": "Audit Correction", "th": "แก้ไขจากการตรวจนับ", "zh": "审计修正", "ja": "棚卸し修正", "ko": "감사 수정", "id": "Koreksi Audit", "ms": "Pembetulan Audit"],
        "reason_description_placeholder": ["en": "Enter reason or description", "th": "ใส่เหตุผลหรือคำอธิบาย", "zh": "输入原因或描述", "ja": "理由または説明を入力", "ko": "사유 또는 설명 입력", "id": "Masukkan alasan atau deskripsi", "ms": "Masukkan sebab atau penerangan"],
        "reason_label": ["en": "Reason", "th": "เหตุผล", "zh": "原因", "ja": "理由", "ko": "사유", "id": "Alasan", "ms": "Sebab"],
        "reason_spillage_accident": ["en": "Spillage/Accident", "th": "หก/อุบัติเหตุ", "zh": "溢出/事故", "ja": "こぼし/事故", "ko": "유출/사고", "id": "Tumpah/Kecelakaan", "ms": "Tumpah/Kemalangan"],
        "reason_spoilage": ["en": "Spoilage", "th": "เน่าเสีย", "zh": "变质", "ja": "腐敗", "ko": "부패", "id": "Pembusukan", "ms": "Rosak"],
        "reason_wastage": ["en": "Wastage", "th": "ของเสีย", "zh": "损耗", "ja": "廃棄", "ko": "폐기", "id": "Pemborosan", "ms": "Pembaziran"],
        "receive_all_items_btn": ["en": "Receive All Items", "th": "รับสินค้าทั้งหมด", "zh": "接收全部商品", "ja": "全商品を受領", "ko": "모든 항목 수령", "id": "Terima Semua Item", "ms": "Terima Semua Item"],
        "receive_delivery_title": ["en": "Receive Delivery", "th": "รับสินค้า", "zh": "接收配送", "ja": "配達受取", "ko": "배달 수령", "id": "Terima Pengiriman", "ms": "Terima Penghantaran"],
        "receive_order_deliveries": ["en": "Receive Order Deliveries", "th": "รับสินค้าจากออเดอร์", "zh": "接收订单配送", "ja": "注文配達を受取", "ko": "주문 배달 수령", "id": "Terima Pengiriman Pesanan", "ms": "Terima Penghantaran Pesanan"],
        "receive_stock_title": ["en": "Receive Stock", "th": "รับสต็อก", "zh": "入库", "ja": "入荷", "ko": "입고", "id": "Terima Stok", "ms": "Terima Stok"],
        "received_cash_template": ["en": "Received: ฿%@", "th": "รับ: ฿%@", "zh": "收到: ฿%@", "ja": "受取: ฿%@", "ko": "수령: ฿%@", "id": "Diterima: ฿%@", "ms": "Diterima: ฿%@"],
        "received_label": ["en": "Received", "th": "รับแล้ว", "zh": "已收到", "ja": "受領済み", "ko": "수령됨", "id": "Diterima", "ms": "Diterima"],
        "reconcile_and_close_btn": ["en": "Reconcile & Close", "th": "กระทบยอดและปิด", "zh": "对账并关闭", "ja": "精算して締める", "ko": "정산 및 마감", "id": "Rekonsiliasi & Tutup", "ms": "Penyesuaian & Tutup"],
        "record_waste_adjust": ["en": "Record Waste/Adjustment", "th": "บันทึกของเสีย/ปรับ", "zh": "记录损耗/调整", "ja": "廃棄/調整を記録", "ko": "폐기/조정 기록", "id": "Catat Limbah/Penyesuaian", "ms": "Rekod Sisa/Pelarasan"],
        "redeem_btn": ["en": "Redeem", "th": "แลก", "zh": "兑换", "ja": "交換", "ko": "교환", "id": "Tukarkan", "ms": "Tebus"],
        "redeem_gift_card_title": ["en": "Redeem Gift Card", "th": "แลกบัตรของขวัญ", "zh": "兑换礼品卡", "ja": "ギフトカード利用", "ko": "기프트카드 사용", "id": "Tukarkan Kartu Hadiah", "ms": "Tebus Kad Hadiah"],
        "reference_label": ["en": "Reference", "th": "อ้างอิง", "zh": "参考号", "ja": "参照", "ko": "참조", "id": "Referensi", "ms": "Rujukan"],
        "refunds_template": ["en": "Refunds: ฿%@", "th": "คืนเงิน: ฿%@", "zh": "退款: ฿%@", "ja": "返金: ฿%@", "ko": "환불: ฿%@", "id": "Refund: ฿%@", "ms": "Bayaran Balik: ฿%@"],
        "register_sessions": ["en": "Register Sessions", "th": "เซสชันเครื่อง", "zh": "注册会话", "ja": "レジセッション", "ko": "레지스터 세션", "id": "Sesi Register", "ms": "Sesi Daftar"],
        "reject_btn_label": ["en": "Reject", "th": "ปฏิเสธ", "zh": "拒绝", "ja": "拒否", "ko": "거부", "id": "Tolak", "ms": "Tolak"],
        "rejected_status_tag": ["en": "Rejected", "th": "ปฏิเสธแล้ว", "zh": "已拒绝", "ja": "拒否済み", "ko": "거부됨", "id": "Ditolak", "ms": "Ditolak"],
        "remove_logo": ["en": "Remove Logo", "th": "ลบโลโก้", "zh": "移除标志", "ja": "ロゴを削除", "ko": "로고 제거", "id": "Hapus Logo", "ms": "Buang Logo"],
        "remove_photo_btn": ["en": "Remove Photo", "th": "ลบรูป", "zh": "移除照片", "ja": "写真を削除", "ko": "사진 제거", "id": "Hapus Foto", "ms": "Buang Foto"],
        "required_quantity_template": ["en": "Required: %@", "th": "ต้องการ: %@", "zh": "所需: %@", "ja": "必要数: %@", "ko": "필요: %@", "id": "Diperlukan: %@", "ms": "Diperlukan: %@"],
        "reset_clear_btn": ["en": "Clear", "th": "ล้าง", "zh": "清除", "ja": "クリア", "ko": "지우기", "id": "Hapus", "ms": "Kosongkan"],
        "reset_fields_btn": ["en": "Reset Fields", "th": "รีเซ็ตช่อง", "zh": "重置字段", "ja": "フィールドをリセット", "ko": "필드 초기화", "id": "Reset Kolom", "ms": "Tetapkan Semula Medan"],
        "return_details_placeholder": ["en": "Enter return details", "th": "ใส่รายละเอียดการคืน", "zh": "输入退货详情", "ja": "返品詳細を入力", "ko": "반품 상세 입력", "id": "Masukkan detail pengembalian", "ms": "Masukkan butiran pemulangan"],
        "return_to_supplier": ["en": "Return to Supplier", "th": "คืนให้ซัพพลายเออร์", "zh": "退回供应商", "ja": "仕入先に返品", "ko": "공급업체에 반품", "id": "Kembalikan ke Pemasok", "ms": "Pulangkan ke Pembekal"],
        "return_to_supplier_title": ["en": "Return to Supplier", "th": "คืนสินค้าให้ซัพพลายเออร์", "zh": "退回供应商", "ja": "仕入先への返品", "ko": "공급업체 반품", "id": "Kembalikan ke Pemasok", "ms": "Pulangkan ke Pembekal"],
        "rev_per_labor_hour_lbl": ["en": "Revenue per Labor Hour", "th": "รายได้ต่อชั่วโมงแรงงาน", "zh": "每工时收入", "ja": "労働時間あたり売上", "ko": "인시당 매출", "id": "Pendapatan per Jam Kerja", "ms": "Hasil per Jam Kerja"],
        "revenue_header": ["en": "Revenue", "th": "รายได้", "zh": "收入", "ja": "売上", "ko": "매출", "id": "Pendapatan", "ms": "Hasil"],
        "review_status_header": ["en": "Review Status", "th": "สถานะการตรวจสอบ", "zh": "审核状态", "ja": "レビューステータス", "ko": "검토 상태", "id": "Status Tinjauan", "ms": "Status Semakan"],
        "role_field_placeholder": ["en": "Select role", "th": "เลือกตำแหน่ง", "zh": "选择角色", "ja": "役割を選択", "ko": "역할 선택", "id": "Pilih peran", "ms": "Pilih peranan"],
        "role_notes_header": ["en": "Role Notes", "th": "หมายเหตุตำแหน่ง", "zh": "角色备注", "ja": "役割メモ", "ko": "역할 메모", "id": "Catatan Peran", "ms": "Nota Peranan"],
        "run_calculations_btn": ["en": "Run Calculations", "th": "คำนวณ", "zh": "运行计算", "ja": "計算実行", "ko": "계산 실행", "id": "Jalankan Perhitungan", "ms": "Jalankan Pengiraan"],
        "payroll_ot_settings_btn": ["en": "OT Settings", "th": "ตั้งค่า OT", "zh": "加班设置", "ja": "残業設定", "ko": "초과근무 설정", "id": "Pengaturan Lembur", "ms": "Tetapan OT"],
        "payroll_ot_multiplier_lbl": ["en": "OT Multiplier", "th": "ตัวคูณ OT", "zh": "加班倍率", "ja": "残業倍率", "ko": "초과근무 배율", "id": "Pengali Lembur", "ms": "Pengganda OT"],
        "payroll_ot_threshold_lbl": ["en": "OT Threshold (hrs/day)", "th": "เกณฑ์ OT (ชม./วัน)", "zh": "加班门槛（小时/天）", "ja": "残業しきい値（時間/日）", "ko": "초과근무 기준(시간/일)", "id": "Ambang Lembur (jam/hari)", "ms": "Ambang OT (jam/hari)"],
        "payroll_ot_multiplier_hint": ["en": "Applied to overtime hours beyond the daily threshold.", "th": "ใช้กับชั่วโมงล่วงเวลาที่เกินเกณฑ์ต่อวัน", "zh": "适用于超过每日门槛的加班时数。", "ja": "1日のしきい値を超えた残業時間に適用されます。", "ko": "일일 기준을 초과한 초과근무 시간에 적용됩니다.", "id": "Diterapkan pada jam lembur di atas ambang harian.", "ms": "Digunakan untuk jam lebih masa melebihi ambang harian."],
        "sales_revenue_trend": ["en": "Sales Revenue Trend", "th": "แนวโน้มรายได้ขาย", "zh": "销售收入趋势", "ja": "売上推移", "ko": "매출 트렌드", "id": "Tren Pendapatan Penjualan", "ms": "Trend Hasil Jualan"],
        "save_btn_label": ["en": "Save", "th": "บันทึก", "zh": "保存", "ja": "保存", "ko": "저장", "id": "Simpan", "ms": "Simpan"],
        "save_draft_btn": ["en": "Save Draft", "th": "บันทึกร่าง", "zh": "保存草稿", "ja": "下書き保存", "ko": "초안 저장", "id": "Simpan Draft", "ms": "Simpan Draf"],
        "scan_barcode_btn": ["en": "Scan Barcode", "th": "สแกนบาร์โค้ด", "zh": "扫描条码", "ja": "バーコードスキャン", "ko": "바코드 스캔", "id": "Pindai Barcode", "ms": "Imbas Barkod"],
        "scan_digital_receipt": ["en": "Scan Digital Receipt", "th": "สแกนใบเสร็จดิจิทัล", "zh": "扫描电子收据", "ja": "デジタルレシートスキャン", "ko": "디지털 영수증 스캔", "id": "Pindai Struk Digital", "ms": "Imbas Resit Digital"],
        "scan_promptpay_qr_desc": ["en": "Scan customer's PromptPay QR code", "th": "สแกนคิวอาร์โค้ดพร้อมเพย์ลูกค้า", "zh": "扫描客户PromptPay二维码", "ja": "お客様のPromptPay QRコードをスキャン", "ko": "고객의 PromptPay QR 코드 스캔", "id": "Pindai kode QR PromptPay pelanggan", "ms": "Imbas kod QR PromptPay pelanggan"],
        "search_categories": ["en": "Search categories", "th": "ค้นหาหมวดหมู่", "zh": "搜索分类", "ja": "カテゴリー検索", "ko": "카테고리 검색", "id": "Cari kategori", "ms": "Cari kategori"],
        "search_menu_items": ["en": "Search menu items", "th": "ค้นหารายการเมนู", "zh": "搜索菜单项", "ja": "メニュー商品検索", "ko": "메뉴 항목 검색", "id": "Cari item menu", "ms": "Cari item menu"],
        "search_modifiers": ["en": "Search modifiers", "th": "ค้นหาตัวเลือก", "zh": "搜索修饰项", "ja": "修飾検索", "ko": "수정자 검색", "id": "Cari modifier", "ms": "Cari pengubah"],
        "search_placeholder": ["en": "Search...", "th": "ค้นหา...", "zh": "搜索...", "ja": "検索...", "ko": "검색...", "id": "Cari...", "ms": "Cari..."],
        "search_products": ["en": "Search products", "th": "ค้นหาสินค้า", "zh": "搜索产品", "ja": "商品検索", "ko": "상품 검색", "id": "Cari produk", "ms": "Cari produk"],
        "search_supplier_placeholder": ["en": "Search supplier...", "th": "ค้นหาซัพพลายเออร์...", "zh": "搜索供应商...", "ja": "仕入先検索...", "ko": "공급업체 검색...", "id": "Cari pemasok...", "ms": "Cari pembekal..."],
        "seed_mock_menu_btn": ["en": "Seed Mock Menu", "th": "สร้างเมนูจำลอง", "zh": "生成示例菜单", "ja": "サンプルメニュー生成", "ko": "샘플 메뉴 생성", "id": "Buat Menu Contoh", "ms": "Cipta Menu Contoh"],
        "select_all": ["en": "Select All", "th": "เลือกทั้งหมด", "zh": "全选", "ja": "全て選択", "ko": "모두 선택", "id": "Pilih Semua", "ms": "Pilih Semua"],
        "select_bank": ["en": "Select Bank", "th": "เลือกธนาคาร", "zh": "选择银行", "ja": "銀行を選択", "ko": "은행 선택", "id": "Pilih Bank", "ms": "Pilih Bank"],
        "select_district_placeholder": ["en": "Select district", "th": "เลือกอำเภอ/เขต", "zh": "选择区", "ja": "区を選択", "ko": "구/군 선택", "id": "Pilih kecamatan", "ms": "Pilih daerah"],
        "select_employees_batch": ["en": "Select Employees", "th": "เลือกพนักงาน", "zh": "选择员工", "ja": "従業員を選択", "ko": "직원 선택", "id": "Pilih Karyawan", "ms": "Pilih Pekerja"],
        "select_gift_card_prompt": ["en": "Select a gift card", "th": "เลือกบัตรของขวัญ", "zh": "选择礼品卡", "ja": "ギフトカードを選択", "ko": "기프트카드 선택", "id": "Pilih kartu hadiah", "ms": "Pilih kad hadiah"],
        "select_province_placeholder": ["en": "Select province", "th": "เลือกจังหวัด", "zh": "选择省份", "ja": "県を選択", "ko": "도/시 선택", "id": "Pilih provinsi", "ms": "Pilih negeri"],
        "select_raw_ingredient_title": ["en": "Select Ingredient", "th": "เลือกวัตถุดิบ", "zh": "选择原料", "ja": "材料を選択", "ko": "재료 선택", "id": "Pilih Bahan", "ms": "Pilih Bahan"],
        "select_subdistrict_placeholder": ["en": "Select subdistrict", "th": "เลือกตำบล/แขวง", "zh": "选择街道", "ja": "町を選択", "ko": "읍/면/동 선택", "id": "Pilih kelurahan", "ms": "Pilih mukim"],
        "select_supplier_subtitle": ["en": "Choose a supplier for this order", "th": "เลือกซัพพลายเออร์สำหรับออเดอร์นี้", "zh": "为此订单选择供应商", "ja": "この注文の仕入先を選択", "ko": "이 주문의 공급업체를 선택하세요", "id": "Pilih pemasok untuk pesanan ini", "ms": "Pilih pembekal untuk pesanan ini"],
        "select_supplier_title": ["en": "Select Supplier", "th": "เลือกซัพพลายเออร์", "zh": "选择供应商", "ja": "仕入先選択", "ko": "공급업체 선택", "id": "Pilih Pemasok", "ms": "Pilih Pembekal"],
        "selections_range_template": ["en": "Select %@–%@", "th": "เลือก %@–%@", "zh": "选择 %@–%@", "ja": "%@〜%@ を選択", "ko": "%@–%@ 선택", "id": "Pilih %@–%@", "ms": "Pilih %@–%@"],
        "sell_label": ["en": "Sell", "th": "ขาย", "zh": "销售", "ja": "販売", "ko": "판매", "id": "Jual", "ms": "Jual"],
        "send_po_to_supplier": ["en": "Send PO to Supplier", "th": "ส่ง PO ให้ซัพพลายเออร์", "zh": "发送采购单给供应商", "ja": "発注書を仕入先に送信", "ko": "PO를 공급업체에 전송", "id": "Kirim PO ke Pemasok", "ms": "Hantar PO ke Pembekal"],
        "service_charge_lbl": ["en": "Service Charge", "th": "ค่าบริการ", "zh": "服务费", "ja": "サービス料", "ko": "서비스 요금", "id": "Biaya Layanan", "ms": "Caj Perkhidmatan"],
        "service_charge_percent": ["en": "Service Charge (%)", "th": "ค่าบริการ (%)", "zh": "服务费 (%)", "ja": "サービス料 (%)", "ko": "서비스 요금 (%)", "id": "Biaya Layanan (%)", "ms": "Caj Perkhidmatan (%)"],
        "session_hint_text": ["en": "Start a shift to begin taking orders", "th": "เริ่มกะเพื่อเริ่มรับออเดอร์", "zh": "开始班次以接单", "ja": "シフトを開始して注文を受付", "ko": "교대를 시작하여 주문 접수 시작", "id": "Mulai shift untuk mulai terima pesanan", "ms": "Mulakan syif untuk mula terima pesanan"],
        "set_expiry_date_toggle": ["en": "Set Expiry Date", "th": "กำหนดวันหมดอายุ", "zh": "设置过期日期", "ja": "有効期限を設定", "ko": "만료일 설정", "id": "Atur Tanggal Kadaluarsa", "ms": "Tetapkan Tarikh Luput"],
        "share_btn_label": ["en": "Share", "th": "แชร์", "zh": "分享", "ja": "共有", "ko": "공유", "id": "Bagikan", "ms": "Kongsi"],
        "shortage_label": ["en": "Shortage", "th": "ขาด", "zh": "短缺", "ja": "不足", "ko": "부족", "id": "Kekurangan", "ms": "Kekurangan"],
        "sku_code_placeholder": ["en": "Enter SKU code", "th": "ใส่รหัส SKU", "zh": "输入SKU编码", "ja": "SKUコードを入力", "ko": "SKU 코드 입력", "id": "Masukkan kode SKU", "ms": "Masukkan kod SKU"],
        "sku_label": ["en": "SKU", "th": "SKU", "zh": "SKU", "ja": "SKU", "ko": "SKU", "id": "SKU", "ms": "SKU"],
        "sold_label": ["en": "Sold", "th": "ขายแล้ว", "zh": "已售", "ja": "販売済み", "ko": "판매됨", "id": "Terjual", "ms": "Terjual"],
        "ssf_deduction_label": ["en": "SSF Deduction", "th": "หักประกันสังคม", "zh": "社保扣除", "ja": "社会保険控除", "ko": "사회보험 공제", "id": "Potongan BPJS", "ms": "Potongan KWSP"],
        "stale_shift_subtitle": ["en": "This shift has been running for over 24 hours", "th": "กะนี้ดำเนินการมากกว่า 24 ชั่วโมงแล้ว", "zh": "此班次已运行超过24小时", "ja": "このシフトは24時間以上稼働しています", "ko": "이 교대는 24시간 이상 진행 중입니다", "id": "Shift ini telah berjalan lebih dari 24 jam", "ms": "Syif ini telah berjalan lebih 24 jam"],
        "stale_shift_title": ["en": "Stale Shift Detected", "th": "ตรวจพบกะค้าง", "zh": "检测到过期班次", "ja": "長時間シフト検出", "ko": "오래된 교대 감지됨", "id": "Shift Kadaluarsa Terdeteksi", "ms": "Syif Lapuk Dikesan"],
        "start_shift_header": ["en": "Start Shift", "th": "เริ่มกะ", "zh": "开始班次", "ja": "シフト開始", "ko": "교대 시작", "id": "Mulai Shift", "ms": "Mula Syif"],
        "starting_cash_float_label": ["en": "Starting Cash Float", "th": "เงินสดเริ่มต้น", "zh": "起始现金", "ja": "開始レジ金", "ko": "시작 현금", "id": "Float Tunai Awal", "ms": "Wang Tunai Permulaan"],
        "starting_float_label": ["en": "Starting Float", "th": "เงินเริ่มต้น", "zh": "起始金额", "ja": "開始金額", "ko": "시작 금액", "id": "Float Awal", "ms": "Wang Permulaan"],
        "status_label": ["en": "Status", "th": "สถานะ", "zh": "状态", "ja": "ステータス", "ko": "상태", "id": "Status", "ms": "Status"],
        "storage_location_placeholder": ["en": "Enter storage location", "th": "ใส่ตำแหน่งจัดเก็บ", "zh": "输入存储位置", "ja": "保管場所を入力", "ko": "보관 위치 입력", "id": "Masukkan lokasi penyimpanan", "ms": "Masukkan lokasi simpanan"],
        "submit_btn": ["en": "Submit", "th": "ส่ง", "zh": "提交", "ja": "送信", "ko": "제출", "id": "Kirim", "ms": "Hantar"],
        "supplied_raw_ingredients": ["en": "Supplied Raw Ingredients", "th": "วัตถุดิบที่จัดส่ง", "zh": "供应的原材料", "ja": "供給された原材料", "ko": "공급된 원자재", "id": "Bahan Baku yang Dipasok", "ms": "Bahan Mentah Dibekalkan"],
        "system_access_credentials_header": ["en": "System Access Credentials", "th": "ข้อมูลเข้าสู่ระบบ", "zh": "系统访问凭证", "ja": "システムアクセス認証", "ko": "시스템 접근 자격 증명", "id": "Kredensial Akses Sistem", "ms": "Kelayakan Akses Sistem"],
        "system_stock_cost_template": ["en": "System cost: ฿%@", "th": "ต้นทุนในระบบ: ฿%@", "zh": "系统成本: ฿%@", "ja": "システム原価: ฿%@", "ko": "시스템 비용: ฿%@", "id": "Biaya sistem: ฿%@", "ms": "Kos sistem: ฿%@"],
        "tendered_label": ["en": "Tendered", "th": "จ่าย", "zh": "已支付", "ja": "受取額", "ko": "지불 금액", "id": "Dibayarkan", "ms": "Dibayar"],
        "theoretical_usage_desc": ["en": "Expected usage based on recipes and sales", "th": "การใช้ที่คาดไว้ตามสูตรและยอดขาย", "zh": "基于食谱和销售的预期用量", "ja": "レシピと売上に基づく予想使用量", "ko": "레시피와 매출 기반 예상 사용량", "id": "Penggunaan yang diharapkan berdasarkan resep dan penjualan", "ms": "Penggunaan dijangka berdasarkan resipi dan jualan"],
        "theoretical_usage_lbl": ["en": "Theoretical Usage", "th": "การใช้ตามทฤษฎี", "zh": "理论用量", "ja": "理論使用量", "ko": "이론 사용량", "id": "Penggunaan Teoritis", "ms": "Penggunaan Teori"],
        "time_date_header": ["en": "Date & Time", "th": "วันที่และเวลา", "zh": "日期和时间", "ja": "日時", "ko": "날짜 및 시간", "id": "Tanggal & Waktu", "ms": "Tarikh & Masa"],
        "time_label": ["en": "Time", "th": "เวลา", "zh": "时间", "ja": "時間", "ko": "시간", "id": "Waktu", "ms": "Masa"],
        "top_products_summary_lbl": ["en": "Top Products Summary", "th": "สรุปสินค้ายอดนิยม", "zh": "热门产品摘要", "ja": "人気商品サマリー", "ko": "인기 상품 요약", "id": "Ringkasan Produk Teratas", "ms": "Ringkasan Produk Teratas"],
        "top_up_btn": ["en": "Top Up", "th": "เติมเงิน", "zh": "充值", "ja": "チャージ", "ko": "충전", "id": "Isi Ulang", "ms": "Tambah Nilai"],
        "top_up_gift_card_title": ["en": "Top Up Gift Card", "th": "เติมเงินบัตรของขวัญ", "zh": "充值礼品卡", "ja": "ギフトカードチャージ", "ko": "기프트카드 충전", "id": "Isi Ulang Kartu Hadiah", "ms": "Tambah Nilai Kad Hadiah"],
        "transaction_approved_status": ["en": "Approved", "th": "อนุมัติแล้ว", "zh": "已批准", "ja": "承認済み", "ko": "승인됨", "id": "Disetujui", "ms": "Diluluskan"],
        "transaction_details_section": ["en": "Transaction Details", "th": "รายละเอียดรายการ", "zh": "交易详情", "ja": "取引詳細", "ko": "거래 상세", "id": "Detail Transaksi", "ms": "Butiran Transaksi"],
        "transaction_log": ["en": "Transaction Log", "th": "บันทึกรายการ", "zh": "交易日志", "ja": "取引ログ", "ko": "거래 기록", "id": "Log Transaksi", "ms": "Log Transaksi"],
        "transactions_header": ["en": "Transactions", "th": "รายการ", "zh": "交易", "ja": "取引", "ko": "거래", "id": "Transaksi", "ms": "Transaksi"],
        "try_adjust_filters": ["en": "Try adjusting your filters", "th": "ลองปรับตัวกรอง", "zh": "尝试调整筛选条件", "ja": "フィルターを調整してみてください", "ko": "필터를 조정해 보세요", "id": "Coba sesuaikan filter Anda", "ms": "Cuba laraskan penapis anda"],
        "turnover_rate_lbl": ["en": "Turnover Rate", "th": "อัตราการหมุนเวียน", "zh": "周转率", "ja": "回転率", "ko": "회전율", "id": "Tingkat Perputaran", "ms": "Kadar Pusing Ganti"],
        "type_label": ["en": "Type", "th": "ประเภท", "zh": "类型", "ja": "タイプ", "ko": "유형", "id": "Tipe", "ms": "Jenis"],
        "uncategorized_label": ["en": "Uncategorized", "th": "ไม่มีหมวดหมู่", "zh": "未分类", "ja": "未分類", "ko": "미분류", "id": "Tidak Berkategori", "ms": "Tidak Berkategori"],
        "unit_cost_price_placeholder": ["en": "Enter unit cost", "th": "ใส่ต้นทุนต่อหน่วย", "zh": "输入单位成本", "ja": "単価を入力", "ko": "단가 입력", "id": "Masukkan biaya satuan", "ms": "Masukkan kos seunit"],
        "unit_placeholder": ["en": "Enter unit (e.g. kg, piece)", "th": "ใส่หน่วย (เช่น กก., ชิ้น)", "zh": "输入单位 (如 kg, 件)", "ja": "単位を入力 (例: kg, 個)", "ko": "단위 입력 (예: kg, 개)", "id": "Masukkan unit (mis. kg, buah)", "ms": "Masukkan unit (cth. kg, biji)"],
        "unit_price_header": ["en": "Unit Price", "th": "ราคาต่อหน่วย", "zh": "单价", "ja": "単価", "ko": "단가", "id": "Harga Satuan", "ms": "Harga Seunit"],
        "unknown_item": ["en": "Unknown Item", "th": "รายการไม่ทราบ", "zh": "未知商品", "ja": "不明な商品", "ko": "알 수 없는 항목", "id": "Item Tidak Dikenal", "ms": "Item Tidak Dikenali"],
        "updated_label": ["en": "Updated", "th": "อัปเดตแล้ว", "zh": "已更新", "ja": "更新済み", "ko": "업데이트됨", "id": "Diperbarui", "ms": "Dikemas Kini"],
        "used_theory_header": ["en": "Used vs. Theory", "th": "ใช้จริง vs ทฤษฎี", "zh": "实际 vs. 理论", "ja": "実績 vs. 理論", "ko": "실제 vs. 이론", "id": "Aktual vs. Teori", "ms": "Sebenar vs. Teori"],
        "variance_label": ["en": "Variance", "th": "ผลต่าง", "zh": "差异", "ja": "差異", "ko": "차이", "id": "Varian", "ms": "Varians"],
        "verify_match_btn": ["en": "Verify & Match", "th": "ตรวจสอบและจับคู่", "zh": "验证并匹配", "ja": "確認して照合", "ko": "확인 및 일치", "id": "Verifikasi & Cocokkan", "ms": "Sahkan & Padankan"],
        "void_btn": ["en": "Void", "th": "ยกเลิก", "zh": "作废", "ja": "取消", "ko": "무효", "id": "Void", "ms": "Batal"],
        "void_gift_card_alert_message": ["en": "This will permanently void the gift card", "th": "การดำเนินการนี้จะยกเลิกบัตรของขวัญอย่างถาวร", "zh": "这将永久作废此礼品卡", "ja": "ギフトカードが永久に無効になります", "ko": "기프트카드가 영구적으로 무효화됩니다", "id": "Ini akan membatalkan kartu hadiah secara permanen", "ms": "Ini akan membatalkan kad hadiah secara kekal"],
        "void_gift_card_alert_title": ["en": "Void Gift Card?", "th": "ยกเลิกบัตรของขวัญ?", "zh": "作废礼品卡?", "ja": "ギフトカードを無効にしますか?", "ko": "기프트카드를 무효화하시겠습니까?", "id": "Batalkan Kartu Hadiah?", "ms": "Batal Kad Hadiah?"],
        "waiting_for_scan": ["en": "Waiting for Scan...", "th": "รอสแกน...", "zh": "等待扫描...", "ja": "スキャン待ち...", "ko": "스캔 대기 중...", "id": "Menunggu Pindaian...", "ms": "Menunggu Imbasan..."],
        "waste_log_lbl": ["en": "Waste Log", "th": "บันทึกของเสีย", "zh": "损耗记录", "ja": "廃棄ログ", "ko": "폐기 기록", "id": "Log Limbah", "ms": "Log Sisa"],
        "wasted_label": ["en": "Wasted", "th": "เสียแล้ว", "zh": "已报损", "ja": "廃棄済み", "ko": "폐기됨", "id": "Terbuang", "ms": "Terbazir"],
        "web_preview_lbl": ["en": "Website", "th": "เว็บไซต์", "zh": "网站", "ja": "ウェブサイト", "ko": "웹사이트", "id": "Situs Web", "ms": "Laman Web"],
        // MARK: - General / Misc
        "connection_status_unchecked": ["en": "Not Checked", "th": "ยังไม่ตรวจสอบ", "zh": "未检查", "ja": "未確認", "ko": "확인 안 됨", "id": "Belum Diperiksa", "ms": "Belum Diperiksa"],
        "never": ["en": "Never", "th": "ไม่เคย", "zh": "从不", "ja": "なし", "ko": "없음", "id": "Tidak Pernah", "ms": "Tidak Pernah"],
        "unassigned": ["en": "Unassigned", "th": "ไม่ได้กำหนด", "zh": "未分配", "ja": "未割当", "ko": "미배정", "id": "Tidak Ditetapkan", "ms": "Tidak Ditetapkan"],
        "transactions": ["en": "Transactions", "th": "รายการธุรกรรม", "zh": "交易记录", "ja": "取引履歴", "ko": "거래 내역", "id": "Transaksi", "ms": "Transaksi"],
        "uncategorized": ["en": "Uncategorized", "th": "ไม่มีหมวดหมู่", "zh": "未分类", "ja": "未分類", "ko": "미분류", "id": "Tidak Berkategori", "ms": "Tidak Berkategori"],
        // MARK: - Menu Image Import
        "menu_import_title": ["en": "Import from Menu Photo", "th": "นำเข้าจากรูปเมนู", "zh": "从菜单照片导入", "ja": "メニュー写真からインポート", "ko": "메뉴 사진에서 가져오기", "id": "Impor dari Foto Menu", "ms": "Import dari Foto Menu"],
        "menu_import_step_upload": ["en": "Select Photos", "th": "เลือกรูปเมนู", "zh": "选择照片", "ja": "写真を選択", "ko": "사진 선택", "id": "Pilih Foto", "ms": "Pilih Foto"],
        "menu_import_step_review": ["en": "Review Items", "th": "ตรวจสอบรายการ", "zh": "检查项目", "ja": "項目を確認", "ko": "항목 검토", "id": "Periksa Item", "ms": "Semak Item"],
        "menu_import_step_complete": ["en": "Complete", "th": "เสร็จสิ้น", "zh": "完成", "ja": "完了", "ko": "완료", "id": "Selesai", "ms": "Selesai"],
        "menu_import_analyze_btn": ["en": "Analyze Menu", "th": "วิเคราะห์เมนู", "zh": "分析菜单", "ja": "メニューを分析", "ko": "메뉴 분석", "id": "Analisis Menu", "ms": "Analisis Menu"],
        "menu_import_analyzing": ["en": "Analyzing menu...", "th": "กำลังวิเคราะห์เมนู...", "zh": "正在分析菜单...", "ja": "メニューを分析中...", "ko": "메뉴 분석 중...", "id": "Menganalisis menu...", "ms": "Menganalisis menu..."],
        "menu_import_confirm_btn": ["en": "Import Selected Items", "th": "นำเข้ารายการที่เลือก", "zh": "导入选中的项目", "ja": "選択した項目をインポート", "ko": "선택한 항목 가져오기", "id": "Impor Item Terpilih", "ms": "Import Item Terpilih"],
        "menu_import_select_all": ["en": "Select All", "th": "เลือกทั้งหมด", "zh": "全选", "ja": "すべて選択", "ko": "전체 선택", "id": "Pilih Semua", "ms": "Pilih Semua"],
        "menu_import_deselect_all": ["en": "Deselect All", "th": "ยกเลิกทั้งหมด", "zh": "取消全选", "ja": "すべて解除", "ko": "전체 해제", "id": "Hapus Semua", "ms": "Nyahpilih Semua"],
        "menu_import_upload_hint": ["en": "Upload photos of your menu to automatically extract product names and prices", "th": "อัปโหลดรูปเมนูเพื่อดึงชื่อสินค้าและราคาอัตโนมัติ", "zh": "上传菜单照片以自动提取产品名称和价格", "ja": "メニューの写真をアップロードして商品名と価格を自動抽出", "ko": "메뉴 사진을 업로드하여 상품명과 가격을 자동 추출", "id": "Unggah foto menu untuk otomatis mengekstrak nama dan harga produk", "ms": "Muat naik foto menu untuk mengekstrak nama dan harga produk secara automatik"],
        "menu_import_max_photos": ["en": "Up to 5 photos", "th": "ได้สูงสุด 5 รูป", "zh": "最多5张照片", "ja": "最大5枚", "ko": "최대 5장", "id": "Maksimal 5 foto", "ms": "Maksimum 5 foto"],
        "menu_import_found_items": ["en": "Found %d items", "th": "พบ %d รายการ", "zh": "找到 %d 个项目", "ja": "%d 件見つかりました", "ko": "%d개 항목 발견", "id": "Ditemukan %d item", "ms": "Ditemui %d item"],
        "menu_import_duplicate_badge": ["en": "Duplicate", "th": "ซ้ำ", "zh": "重复", "ja": "重複", "ko": "중복", "id": "Duplikat", "ms": "Pendua"],
        "menu_import_success_title": ["en": "Import Complete!", "th": "นำเข้าเสร็จสิ้น!", "zh": "导入完成！", "ja": "インポート完了！", "ko": "가져오기 완료!", "id": "Impor Selesai!", "ms": "Import Selesai!"],
        "menu_import_imported_count": ["en": "%d items imported", "th": "นำเข้า %d รายการ", "zh": "已导入 %d 个项目", "ja": "%d 件インポート", "ko": "%d개 항목 가져옴", "id": "%d item diimpor", "ms": "%d item diimport"],
        "menu_import_skipped_count": ["en": "%d skipped", "th": "ข้าม %d รายการ", "zh": "跳过 %d 个", "ja": "%d 件スキップ", "ko": "%d개 건너뜀", "id": "%d dilewati", "ms": "%d dilangkau"],
        "menu_import_categories_created": ["en": "%d new categories created", "th": "สร้างหมวดหมู่ใหม่ %d หมวด", "zh": "创建了 %d 个新分类", "ja": "%d 件の新カテゴリー作成", "ko": "새 카테고리 %d개 생성", "id": "%d kategori baru dibuat", "ms": "%d kategori baharu dicipta"],
        "menu_import_no_items": ["en": "No items found in the image", "th": "ไม่พบรายการในรูปภาพ", "zh": "图片中未找到项目", "ja": "画像にアイテムが見つかりません", "ko": "이미지에서 항목을 찾을 수 없음", "id": "Tidak ada item ditemukan di gambar", "ms": "Tiada item ditemui dalam gambar"],
        "menu_import_error": ["en": "Failed to analyze image", "th": "วิเคราะห์รูปภาพไม่สำเร็จ", "zh": "分析图片失败", "ja": "画像の分析に失敗", "ko": "이미지 분석 실패", "id": "Gagal menganalisis gambar", "ms": "Gagal menganalisis gambar"],
        "menu_import_confidence": ["en": "Confidence: %d%%", "th": "ความมั่นใจ: %d%%", "zh": "置信度: %d%%", "ja": "確信度: %d%%", "ko": "신뢰도: %d%%", "id": "Keyakinan: %d%%", "ms": "Keyakinan: %d%%"],
        "menu_import_new_category": ["en": "New", "th": "ใหม่", "zh": "新", "ja": "新規", "ko": "신규", "id": "Baru", "ms": "Baharu"],
        "menu_import_add_photos": ["en": "Add Photos", "th": "เพิ่มรูป", "zh": "添加照片", "ja": "写真を追加", "ko": "사진 추가", "id": "Tambah Foto", "ms": "Tambah Foto"],
        "menu_import_take_photo": ["en": "Take Photo", "th": "ถ่ายรูป", "zh": "拍照", "ja": "写真を撮る", "ko": "사진 촬영", "id": "Ambil Foto", "ms": "Ambil Foto"],
        "menu_import_importing": ["en": "Importing products...", "th": "กำลังนำเข้าสินค้า...", "zh": "正在导入产品...", "ja": "商品をインポート中...", "ko": "상품 가져오는 중...", "id": "Mengimpor produk...", "ms": "Mengimport produk..."],
        "menu_import_done_btn": ["en": "Done", "th": "เสร็จ", "zh": "完成", "ja": "完了", "ko": "완료", "id": "Selesai", "ms": "Selesai"],
        "menu_import_price": ["en": "Price", "th": "ราคา", "zh": "价格", "ja": "価格", "ko": "가격", "id": "Harga", "ms": "Harga"],
        "menu_import_no_category": ["en": "No Category", "th": "ไม่มีหมวดหมู่", "zh": "无分类", "ja": "カテゴリーなし", "ko": "카테고리 없음", "id": "Tanpa Kategori", "ms": "Tanpa Kategori"],
        "menu_import_retry": ["en": "Try Again", "th": "ลองอีกครั้ง", "zh": "重试", "ja": "再試行", "ko": "다시 시도", "id": "Coba Lagi", "ms": "Cuba Lagi"],
        // MARK: - AI Receipt Stock Scanner
        "stock_scan_title": ["en": "AI Receipt Scanner", "th": "สแกนเอกสารด้วย AI"],
        "stock_scan_select_photo": ["en": "Select Invoice / Delivery Note Photo", "th": "เลือกรูปเอกสารใบส่งของหรือใบเสร็จ"],
        "stock_scan_analyze_btn": ["en": "Analyze Document", "th": "วิเคราะห์เอกสาร"],
        "stock_scan_analyzing": ["en": "Analyzing document details...", "th": "กำลังวิเคราะห์ข้อมูลเอกสาร..."],
        "stock_scan_confirm_btn": ["en": "Receive Matched Stock", "th": "นำเข้าสต็อกตามรายการจับคู่"],
        "stock_scan_imported_count": ["en": "Successfully updated %d stock items", "th": "อัปเดตสต็อกสินค้าสำเร็จ %d รายการ"],
        "stock_scan_success_title": ["en": "Stock Received!", "th": "รับสินค้าเข้าสต็อกสำเร็จ!"],
        "stock_scan_no_match": ["en": "No Matched Item", "th": "ไม่พบข้อมูลที่ตรงกัน"]
        ,
        // C-1: Gift Card POS UI keys
        "pos_gift_card": ["en": "Gift Card", "th": "บัตรของขวัญ", "zh": "礼品卡", "ja": "ギフトカード", "ko": "기프트카드", "id": "Kartu Hadiah", "ms": "Kad Hadiah"],
        "pos_gift_card_redeem_amount": ["en": "Amount to Redeem", "th": "จำนวนเงินที่ต้องการใช้", "zh": "兑换金额", "ja": "利用金額", "ko": "사용 금액", "id": "Jumlah Ditukar", "ms": "Jumlah Ditebus"],
        "pos_gift_card_confirm": ["en": "Confirm Gift Card", "th": "ยืนยันใช้บัตรของขวัญ", "zh": "确认礼品卡", "ja": "ギフトカード確認", "ko": "기프트카드 확인", "id": "Konfirmasi Kartu Hadiah", "ms": "Sahkan Kad Hadiah"],
        "pos_gift_card_exceed_warning": ["en": "Amount exceeds card balance", "th": "จำนวนเกินยอดคงเหลือในบัตร", "zh": "超过余额", "ja": "残高を超えています", "ko": "잔액 초과", "id": "Melebihi saldo kartu", "ms": "Melebihi baki kad"],
        "max_btn": ["en": "Max", "th": "สูงสุด", "zh": "最大", "ja": "最大", "ko": "최대", "id": "Maks", "ms": "Maks"]
        ,
        // H-1: No-Sale keys
        "no_sale_btn":            ["en": "No Sale", "th": "ไม่มีการขาย", "zh": "无销售", "ja": "金庫開け", "ko": "거스름돈 인출", "id": "Tanpa Penjualan", "ms": "Tiada Jualan"],
        "no_sale_confirm_title":  ["en": "Open Cash Drawer?", "th": "เปิดลิ้นชักเงินสด?", "zh": "打开收银机?", "ja": "ドロワーを開きますか?", "ko": "서랍 열기?", "id": "Buka Laci Kasir?", "ms": "Buka Laci Wang?"],
        "no_sale_confirm_msg":    ["en": "This will open the cash drawer and record a No-Sale event in the audit log.", "th": "การดำเนินการนี้จะเปิดลิ้นชักเงินสดและบันทึกเป็น No-Sale ใน Audit Log", "zh": "将打开收银机并记录无销售事件", "ja": "金庫を開けてNO-SALEをログに記録します", "ko": "서랍을 열고 감사 로그에 기록합니다", "id": "Ini akan membuka laci kasir dan mencatat No-Sale", "ms": "Ini akan membuka laci wang dan merekod No-Sale"],
        "no_sale_confirm_action": ["en": "Open Drawer", "th": "เปิดลิ้นชัก", "zh": "开抽屉", "ja": "開ける", "ko": "열기", "id": "Buka Laci", "ms": "Buka Laci"],
        "no_sale_reason":         ["en": "No-Sale (Drawer Open)", "th": "ไม่มีการขาย (เปิดลิ้นชัก)", "zh": "无销售（开抽屉）", "ja": "NO-SALE（金庫開け）", "ko": "거스름돈 인출 (서랍 열기)", "id": "Tanpa Penjualan (Buka Laci)", "ms": "Tiada Jualan (Buka Laci)"]
        ,
        // H-2: Table Transfer keys
        "table_transfer_btn":            ["en": "Transfer Table", "th": "ย้ายโต๊ะ", "zh": "转移桌台", "ja": "テーブル移動", "ko": "테이블 이동", "id": "Pindah Meja", "ms": "Pindah Meja"],
        "table_transfer_from":           ["en": "From", "th": "จากโต๊ะ", "zh": "从", "ja": "から", "ko": "에서", "id": "Dari", "ms": "Dari"],
        "table_transfer_orders_count":   ["en": "orders in session", "th": "ออเดอร์ในรอบนี้", "zh": "个订单", "ja": "注文", "ko": "주문", "id": "pesanan", "ms": "pesanan"],
        "table_transfer_no_vacant":      ["en": "No vacant tables available on this floor", "th": "ไม่มีโต๊ะว่างบนชั้นนี้", "zh": "本楼层没有空台", "ja": "この階に空きテーブルがありません", "ko": "이 층에 빈 테이블이 없습니다", "id": "Tidak ada meja kosong di lantai ini", "ms": "Tiada meja kosong di tingkat ini"],
        "table_transfer_confirm_title":  ["en": "Transfer Table?", "th": "ยืนยันการย้ายโต๊ะ?", "zh": "确认转台?", "ja": "テーブルを移動しますか?", "ko": "테이블을 이동하시겠습니까?", "id": "Pindahkan Meja?", "ms": "Pindah Meja?"],
        "table_transfer_confirm_msg":    ["en": "Move all orders to table", "th": "ย้ายออเดอร์ทั้งหมดไปยัง", "zh": "将所有订单移至", "ja": "すべての注文を移動", "ko": "모든 주문 이동", "id": "Pindahkan semua pesanan ke meja", "ms": "Pindah semua pesanan ke meja"],
        "table_transfer_confirm_action": ["en": "Transfer", "th": "ย้ายโต๊ะ", "zh": "转移", "ja": "移動", "ko": "이동", "id": "Pindahkan", "ms": "Pindahkan"]
        ,
        // H-3: Item Void PIN Guard
        "void_pin_required_hint": ["en": "Manager PIN required to void items already sent to kitchen", "th": "ต้องใช้ PIN ผู้จัดการเพื่อยกเลิกรายการที่ส่งครัวแล้ว", "zh": "取消已发厨房的菜品需要经理PIN", "ja": "送信済み品目のキャンセルにはマネージャーPINが必要", "ko": "주방에 전달된 항목 취소는 매니저 PIN 필요", "id": "PIN Manajer diperlukan untuk void item yang sudah dikirim", "ms": "PIN Pengurus diperlukan untuk batal item yang dihantar"]
        ,
        // H-5/H-6: Device Management
        "device_paired_success_title":  ["en": "Device Paired!", "th": "จับคู่อุปกรณ์สำเร็จ!", "zh": "设备配对成功！", "ja": "デバイスのペアリング完了！", "ko": "기기 페어링 완료!", "id": "Perangkat Terpasang!", "ms": "Peranti Dipasangkan!"],
        "device_paired_success_desc":   ["en": "The device is now registered and ready to use.", "th": "อุปกรณ์ลงทะเบียนสำเร็จและพร้อมใช้งาน", "zh": "设备已注册并可使用", "ja": "デバイスが登録され使用可能です", "ko": "기기가 등록되어 사용 준비 완료", "id": "Perangkat terdaftar dan siap digunakan", "ms": "Peranti telah didaftar dan sedia digunakan"],
        "done_btn":                     ["en": "Done", "th": "เสร็จสิ้น", "zh": "完成", "ja": "完了", "ko": "완료", "id": "Selesai", "ms": "Selesai"],
        "device_remote_actions_title":  ["en": "REMOTE ACTIONS", "th": "การดำเนินการระยะไกล", "zh": "远程操作", "ja": "リモート操作", "ko": "원격 작업", "id": "Tindakan Jarak Jauh", "ms": "Tindakan Jauh"],
        "device_force_sync_btn":        ["en": "Force Sync", "th": "บังคับซิงค์", "zh": "强制同步", "ja": "強制同期", "ko": "강제 동기화", "id": "Paksa Sinkronisasi", "ms": "Paksa Segerakkan"],
        "device_revoke_trust_btn":      ["en": "Revoke Trust", "th": "ยกเลิกความน่าเชื่อถือ", "zh": "撤销信任", "ja": "信頼を取り消す", "ko": "신뢰 취소", "id": "Cabut Kepercayaan", "ms": "Tarik Kepercayaan"],
        "device_grant_trust_btn":       ["en": "Grant Trust", "th": "อนุมัติความน่าเชื่อถือ", "zh": "授予信任", "ja": "信頼を付与する", "ko": "신뢰 부여", "id": "Berikan Kepercayaan", "ms": "Beri Kepercayaan"],
        "device_remove_btn":            ["en": "Remove Device", "th": "ลบอุปกรณ์", "zh": "移除设备", "ja": "デバイスを削除", "ko": "기기 삭제", "id": "Hapus Perangkat", "ms": "Buang Peranti"]
        ,
        // M-2: Coupon Code keys
        "coupon_codes_btn":      ["en": "Coupon Codes", "th": "โค้ดคูปอง", "zh": "优惠码", "ja": "クーポンコード", "ko": "쿠폰 코드", "id": "Kode Kupon", "ms": "Kod Kupon"],
        "coupon_new_btn":        ["en": "New Coupon", "th": "สร้างคูปองใหม่", "zh": "新建优惠码", "ja": "新規クーポン", "ko": "새 쿠폰", "id": "Kupon Baru", "ms": "Kupon Baharu"],
        "coupon_code_lbl":       ["en": "Coupon Code", "th": "รหัสคูปอง", "zh": "优惠码", "ja": "クーポンコード", "ko": "쿠폰 코드", "id": "Kode Kupon", "ms": "Kod Kupon"],
        "coupon_generate_btn":   ["en": "Generate", "th": "สร้างรหัส", "zh": "生成", "ja": "生成", "ko": "생성", "id": "Buat", "ms": "Jana"],
        "coupon_promo_link_lbl": ["en": "Link to Promotion", "th": "เชื่อมกับโปรโมชั่น", "zh": "关联促销", "ja": "プロモーションに紐付け", "ko": "프로모션 연결", "id": "Hubungkan ke Promosi", "ms": "Kaitkan dengan Promosi"],
        "coupon_no_promo":       ["en": "— No linked promotion —", "th": "— ไม่เชื่อมกับโปรโมชั่น —", "zh": "— 不关联促销 —", "ja": "— 関連なし —", "ko": "— 연결 없음 —", "id": "— Tanpa promosi —", "ms": "— Tanpa promosi —"],
        "coupon_max_use_lbl":    ["en": "Max Redemptions", "th": "จำนวนการใช้สูงสุด", "zh": "最大兑换次数", "ja": "最大利用回数", "ko": "최대 사용 횟수", "id": "Maks Penukaran", "ms": "Maks Penebusan"],
        "coupon_has_expiry_lbl": ["en": "Has Expiry Date", "th": "มีวันหมดอายุ", "zh": "有效期限", "ja": "有効期限あり", "ko": "만료일 있음", "id": "Ada tanggal kedaluwarsa", "ms": "Ada tarikh luput"],
        "coupon_expires_lbl":    ["en": "Expires", "th": "หมดอายุ", "zh": "到期", "ja": "有効期限", "ko": "만료", "id": "Kedaluwarsa", "ms": "Luput"],
        "coupon_save_btn":       ["en": "Save Coupon", "th": "บันทึกคูปอง", "zh": "保存优惠码", "ja": "クーポン保存", "ko": "쿠폰 저장", "id": "Simpan Kupon", "ms": "Simpan Kupon"],
        "coupon_uses_lbl":       ["en": "uses", "th": "ครั้ง", "zh": "次使用", "ja": "回使用", "ko": "사용", "id": "penggunaan", "ms": "penggunaan"],
        "coupon_copied_msg":     ["en": "Copied!", "th": "คัดลอกแล้ว!", "zh": "已复制！", "ja": "コピー済！", "ko": "복사됨！", "id": "Tersalin！", "ms": "Disalin！"]
        ,
        // M-4: Loyalty Point Expiry
        "loyalty_expiry_days_lbl":  ["en": "Points expire after", "th": "แต้มหมดอายุหลัง", "zh": "积分有效期", "ja": "ポイント有効期限", "ko": "포인트 유효기간", "id": "Poin kadaluarsa setelah", "ms": "Mata ganjaran luput selepas"],
        "loyalty_expiry_days_unit": ["en": "days", "th": "วัน", "zh": "天", "ja": "日", "ko": "일", "id": "hari", "ms": "hari"],
        "loyalty_expiry_ran_msg":   ["en": "Expired points removed", "th": "แต้มหมดอายุถูกหักออกแล้ว", "zh": "已过期积分已扣除", "ja": "期限切れポイントを差し引きました", "ko": "만료된 포인트가 차감되었습니다", "id": "Poin kadaluarsa telah dikurangi", "ms": "Mata luput telah ditolak"]
        ,
        // M-5: Leave Management
        "leave_management_tab":         ["en": "Leave", "th": "การลา", "zh": "请假", "ja": "休暇", "ko": "휴가", "id": "Cuti", "ms": "Cuti"],
        "leave_request_btn":            ["en": "Request Leave", "th": "ขอลา", "zh": "申请请假", "ja": "休暇申請", "ko": "휴가 신청", "id": "Ajukan Cuti", "ms": "Mohon Cuti"],
        "leave_stat_pending":           ["en": "Pending", "th": "รออนุมัติ", "zh": "待审批", "ja": "承認待ち", "ko": "승인 대기", "id": "Menunggu", "ms": "Menunggu"],
        "leave_stat_approved_month":    ["en": "Approved (this month)", "th": "อนุมัติแล้ว (เดือนนี้)", "zh": "已批准(本月)", "ja": "承認済(今月)", "ko": "승인됨(이번달)", "id": "Disetujui (bulan ini)", "ms": "Diluluskan (bulan ini)"],
        "leave_stat_days_month":        ["en": "Days off (this month)", "th": "วันลา (เดือนนี้)", "zh": "请假天数(本月)", "ja": "休暇日数(今月)", "ko": "휴가일수(이번달)", "id": "Hari cuti (bulan ini)", "ms": "Hari cuti (bulan ini)"],
        "leave_filter_all":             ["en": "All", "th": "ทั้งหมด", "zh": "全部", "ja": "全て", "ko": "전체", "id": "Semua", "ms": "Semua"],
        "leave_filter_all_staff":       ["en": "All Staff", "th": "พนักงานทุกคน", "zh": "全部员工", "ja": "全スタッフ", "ko": "전체 직원", "id": "Semua Staf", "ms": "Semua Kakitangan"],
        "leave_search_placeholder":     ["en": "Search staff or reason…", "th": "ค้นหาพนักงานหรือเหตุผล…", "zh": "搜索员工或原因…", "ja": "スタッフまたは理由を検索…", "ko": "직원 또는 사유 검색…", "id": "Cari staf atau alasan…", "ms": "Cari kakitangan atau sebab…"],
        "leave_empty_title":            ["en": "No leave records", "th": "ไม่มีรายการลา", "zh": "暂无请假记录", "ja": "休暇記録なし", "ko": "휴가 기록 없음", "id": "Tidak ada catatan cuti", "ms": "Tiada rekod cuti"],
        "leave_status_pending":         ["en": "Pending", "th": "รออนุมัติ", "zh": "待审批", "ja": "承認待ち", "ko": "승인 대기", "id": "Menunggu", "ms": "Menunggu"],
        "leave_status_approved":        ["en": "Approved", "th": "อนุมัติ", "zh": "已批准", "ja": "承認済み", "ko": "승인됨", "id": "Disetujui", "ms": "Diluluskan"],
        "leave_status_rejected":        ["en": "Rejected", "th": "ปฏิเสธ", "zh": "已拒绝", "ja": "却下", "ko": "거부됨", "id": "Ditolak", "ms": "Ditolak"],
        "leave_status_cancelled":       ["en": "Cancelled", "th": "ยกเลิก", "zh": "已取消", "ja": "キャンセル済", "ko": "취소됨", "id": "Dibatalkan", "ms": "Dibatalkan"],
        "leave_status_lbl":             ["en": "Status", "th": "สถานะ", "zh": "状态", "ja": "ステータス", "ko": "상태", "id": "Status", "ms": "Status"],
        "leave_unpaid_badge":           ["en": "Unpaid", "th": "ไม่ได้รับเงิน", "zh": "无薪", "ja": "無給", "ko": "무급", "id": "Tanpa Bayar", "ms": "Tanpa Bayaran"],
        "leave_days_unit":              ["en": "days", "th": "วัน", "zh": "天", "ja": "日", "ko": "일", "id": "hari", "ms": "hari"],
        "leave_type_lbl":               ["en": "Leave Type", "th": "ประเภทการลา", "zh": "请假类型", "ja": "休暇種別", "ko": "휴가 유형", "id": "Jenis Cuti", "ms": "Jenis Cuti"],
        "leave_type_sick":              ["en": "Sick Leave", "th": "ลาป่วย", "zh": "病假", "ja": "病気休暇", "ko": "병가", "id": "Sakit", "ms": "Cuti Sakit"],
        "leave_type_annual":            ["en": "Annual Leave", "th": "ลาพักร้อน", "zh": "年假", "ja": "年次有給休暇", "ko": "연차", "id": "Cuti Tahunan", "ms": "Cuti Tahunan"],
        "leave_type_personal":          ["en": "Personal Leave", "th": "ลากิจ", "zh": "事假", "ja": "私用休暇", "ko": "개인 휴가", "id": "Cuti Pribadi", "ms": "Cuti Peribadi"],
        "leave_type_unpaid":            ["en": "Unpaid Leave", "th": "ลาไม่ได้รับเงิน", "zh": "无薪假", "ja": "無給休暇", "ko": "무급 휴가", "id": "Cuti Tanpa Bayar", "ms": "Cuti Tanpa Gaji"],
        "leave_type_maternity":         ["en": "Maternity Leave", "th": "ลาคลอด", "zh": "产假", "ja": "産前産後休暇", "ko": "출산 휴가", "id": "Cuti Melahirkan", "ms": "Cuti Bersalin"],
        "leave_type_paternity":         ["en": "Paternity Leave", "th": "ลาเลี้ยงดูบุตร", "zh": "陪产假", "ja": "育児休暇", "ko": "육아 휴가", "id": "Cuti Ayah", "ms": "Cuti Bapa"],
        "leave_type_other":             ["en": "Other", "th": "อื่นๆ", "zh": "其他", "ja": "その他", "ko": "기타", "id": "Lainnya", "ms": "Lain-lain"],
        "leave_employee_section":       ["en": "Employee", "th": "พนักงาน", "zh": "员工", "ja": "従業員", "ko": "직원", "id": "Karyawan", "ms": "Kakitangan"],
        "leave_employee_lbl":           ["en": "Select Employee", "th": "เลือกพนักงาน", "zh": "选择员工", "ja": "従業員を選択", "ko": "직원 선택", "id": "Pilih Karyawan", "ms": "Pilih Kakitangan"],
        "leave_select_employee":        ["en": "— Select —", "th": "— เลือกพนักงาน —", "zh": "— 选择 —", "ja": "— 選択 —", "ko": "— 선택 —", "id": "— Pilih —", "ms": "— Pilih —"],
        "leave_details_section":        ["en": "Leave Details", "th": "รายละเอียดการลา", "zh": "请假详情", "ja": "休暇詳細", "ko": "휴가 세부사항", "id": "Detail Cuti", "ms": "Butiran Cuti"],
        "leave_start_date":             ["en": "Start Date", "th": "วันที่เริ่ม", "zh": "开始日期", "ja": "開始日", "ko": "시작일", "id": "Tanggal Mulai", "ms": "Tarikh Mula"],
        "leave_end_date":               ["en": "End Date", "th": "วันที่สิ้นสุด", "zh": "结束日期", "ja": "終了日", "ko": "종료일", "id": "Tanggal Selesai", "ms": "Tarikh Tamat"],
        "leave_half_day_toggle":        ["en": "Half Day", "th": "ลาครึ่งวัน", "zh": "半天", "ja": "半日", "ko": "반일", "id": "Setengah Hari", "ms": "Separuh Hari"],
        "leave_total_days":             ["en": "Total Days", "th": "จำนวนวัน", "zh": "总天数", "ja": "合計日数", "ko": "총 일수", "id": "Total Hari", "ms": "Jumlah Hari"],
        "leave_paid_toggle":            ["en": "Paid Leave", "th": "ลาได้รับเงิน", "zh": "带薪假", "ja": "有給休暇", "ko": "유급 휴가", "id": "Cuti Berbayar", "ms": "Cuti Berbayar"],
        "leave_reason_section":         ["en": "Reason", "th": "เหตุผล", "zh": "原因", "ja": "理由", "ko": "사유", "id": "Alasan", "ms": "Sebab"],
        "leave_reason_placeholder":     ["en": "Enter reason (optional)…", "th": "กรอกเหตุผล (ไม่บังคับ)…", "zh": "输入原因（可选）…", "ja": "理由を入力（任意）…", "ko": "사유 입력 (선택)…", "id": "Masukkan alasan (opsional)…", "ms": "Masukkan sebab (pilihan)…"],
        "leave_save_btn":               ["en": "Submit Request", "th": "ส่งคำขอ", "zh": "提交申请", "ja": "申請を送信", "ko": "신청 제출", "id": "Kirim Permohonan", "ms": "Hantar Permohonan"],
        "leave_action_section":         ["en": "Action", "th": "การดำเนินการ", "zh": "操作", "ja": "アクション", "ko": "작업", "id": "Tindakan", "ms": "Tindakan"],
        "leave_approve_btn":            ["en": "Approve", "th": "อนุมัติ", "zh": "批准", "ja": "承認", "ko": "승인", "id": "Setujui", "ms": "Luluskan"],
        "leave_reject_btn":             ["en": "Reject", "th": "ปฏิเสธ", "zh": "拒绝", "ja": "却下", "ko": "거부", "id": "Tolak", "ms": "Tolak"],
        "leave_approved_by_placeholder": ["en": "Your name (approver)", "th": "ชื่อผู้อนุมัติ", "zh": "审批人姓名", "ja": "承認者名", "ko": "승인자 이름", "id": "Nama penyetuju", "ms": "Nama pelulus"],
        "leave_approved_by_lbl":        ["en": "Approved by", "th": "อนุมัติโดย", "zh": "审批人", "ja": "承認者", "ko": "승인자", "id": "Disetujui oleh", "ms": "Diluluskan oleh"],
        "leave_details_title":          ["en": "Leave Details", "th": "รายละเอียดการลา", "zh": "请假详情", "ja": "休暇詳細", "ko": "휴가 세부정보", "id": "Detail Cuti", "ms": "Butiran Cuti"],
        "leave_dates_section":          ["en": "Dates", "th": "วันที่", "zh": "日期", "ja": "日付", "ko": "날짜", "id": "Tanggal", "ms": "Tarikh"]
        ,
        // M-10: Billing
        "org_current_plan":         ["en": "Current Plan", "th": "แพ็คเกจปัจจุบัน", "zh": "当前计划", "ja": "現在のプラン", "ko": "현재 플랜", "id": "Paket Saat Ini", "ms": "Pelan Semasa"],
        "org_billing_next_cycle":   ["en": "Next billing cycle: 1st of next month", "th": "รอบถัดไป: 1 ของเดือนหน้า", "zh": "下次账单: 下月1日", "ja": "次の請求: 来月1日", "ko": "다음 결제: 다음달 1일", "id": "Siklus berikutnya: 1 bulan depan", "ms": "Kitaran seterusnya: 1 bulan hadapan"],
        "org_upgrade_btn":          ["en": "Upgrade", "th": "อัพเกรด", "zh": "升级", "ja": "アップグレード", "ko": "업그레이드", "id": "Upgrade", "ms": "Naik Taraf"],
        "org_billing_history":      ["en": "BILLING HISTORY", "th": "ประวัติการชำระเงิน", "zh": "账单历史", "ja": "支払履歴", "ko": "결제 내역", "id": "Riwayat Tagihan", "ms": "Sejarah Bil"],
        "org_billing_upcoming":     ["en": "Upcoming", "th": "กำลังจะถึง", "zh": "即将", "ja": "予定", "ko": "예정", "id": "Mendatang", "ms": "Akan Datang"],
        "org_billing_paid":         ["en": "Paid", "th": "ชำระแล้ว", "zh": "已付", "ja": "支払済", "ko": "결제완료", "id": "Dibayar", "ms": "Dibayar"],
        "org_billing_amount_pending": ["en": "Pending", "th": "รอชำระ", "zh": "待付", "ja": "未払い", "ko": "미결제", "id": "Tertunda", "ms": "Belum Bayar"],
        "org_offline_billing_warning": ["en": "Offline: billing data unavailable", "th": "ออฟไลน์: ไม่สามารถดูข้อมูลการชำระเงิน", "zh": "离线: 账单不可用", "ja": "オフライン: 請求不可", "ko": "오프라인: 결제 정보 불가", "id": "Offline: data tagihan tidak tersedia", "ms": "Luar talian: data bil tidak tersedia"],
        // M-11: API Keys
        "org_api_new_key_btn":          ["en": "New Key", "th": "สร้างคีย์ใหม่", "zh": "新建密钥", "ja": "新規キー", "ko": "새 키", "id": "Kunci Baru", "ms": "Kunci Baharu"],
        "org_no_api_keys":              ["en": "No API keys yet", "th": "ยังไม่มี API Key", "zh": "暂无API密钥", "ja": "APIキーなし", "ko": "API 키 없음", "id": "Belum ada kunci API", "ms": "Tiada kunci API"],
        "org_api_key_default_name":     ["en": "Integration Key", "th": "คีย์เชื่อมต่อ", "zh": "集成密钥", "ja": "連携キー", "ko": "통합 키", "id": "Kunci Integrasi", "ms": "Kunci Integrasi"],
        "org_api_key_name_lbl":         ["en": "Key Name", "th": "ชื่อคีย์", "zh": "密钥名称", "ja": "キー名", "ko": "키 이름", "id": "Nama Kunci", "ms": "Nama Kunci"],
        "org_api_key_name_placeholder": ["en": "e.g. Shopify Integration", "th": "เช่น Shopify Integration", "zh": "如: Shopify集成", "ja": "例: Shopify連携", "ko": "예: Shopify 연동", "id": "cth: Shopify Integration", "ms": "cth: Integrasi Shopify"],
        "org_api_generate_btn":         ["en": "Generate", "th": "สร้าง", "zh": "生成", "ja": "生成", "ko": "생성", "id": "Buat", "ms": "Jana"],
        "org_api_key_copy_hint":        ["en": "Copy and store this key securely — it won't be shown again", "th": "คัดลอกและเก็บคีย์นี้ไว้อย่างปลอดภัย — จะไม่แสดงอีก", "zh": "复制并安全保存 — 不会再次显示", "ja": "コピーして安全に保管 — 再表示されません", "ko": "복사하여 안전하게 저장 — 다시 표시되지 않음", "id": "Salin dan simpan dengan aman — tidak akan ditampilkan lagi", "ms": "Salin dan simpan dengan selamat — tidak akan dipaparkan lagi"],
        "org_offline_api_warning":      ["en": "Offline: API key management disabled", "th": "ออฟไลน์: การจัดการ API Key ถูกปิด", "zh": "离线: API密钥管理已禁用", "ja": "オフライン: APIキー管理無効", "ko": "오프라인: API 키 관리 비활성화", "id": "Offline: manajemen kunci API dinonaktifkan", "ms": "Luar talian: pengurusan kunci API dilumpuhkan"],
        // M-12: Data Export
        "org_offline_export_warning":   ["en": "Offline: cloud backup disabled", "th": "ออฟไลน์: สำรองข้อมูลบนคลาวด์ถูกปิด", "zh": "离线: 云备份已禁用", "ja": "オフライン: クラウドバックアップ無効", "ko": "오프라인: 클라우드 백업 비활성화", "id": "Offline: backup cloud dinonaktifkan", "ms": "Luar talian: sandaran awan dilumpuhkan"],
        "org_backup_auto_msg":          ["en": "Backups run automatically every 24h via Supabase", "th": "ข้อมูลสำรองทำงานอัตโนมัติทุก 24 ชั่วโมงผ่าน Supabase", "zh": "每24小时通过Supabase自动备份", "ja": "24時間ごとにSupabaseで自動バックアップ", "ko": "24시간마다 Supabase를 통해 자동 백업", "id": "Backup otomatis setiap 24 jam via Supabase", "ms": "Sandaran automatik setiap 24 jam melalui Supabase"],
        "org_import_confirm_title":     ["en": "Import Data?", "th": "นำเข้าข้อมูล?", "zh": "导入数据?", "ja": "データをインポート?", "ko": "데이터 가져오기?", "id": "Impor Data?", "ms": "Import Data?"],
        "org_import_confirm_msg":       ["en": "This will merge external data into the current database. Existing records will not be overwritten.", "th": "การดำเนินการนี้จะรวมข้อมูลภายนอกเข้ากับฐานข้อมูลปัจจุบัน ข้อมูลที่มีอยู่จะไม่ถูกเขียนทับ", "zh": "这将把外部数据合并到当前数据库中", "ja": "外部データを現在のDBにマージします", "ko": "외부 데이터를 현재 DB에 병합합니다", "id": "Ini akan menggabungkan data eksternal ke database saat ini", "ms": "Ini akan menggabungkan data luar ke pangkalan data semasa"],
        "org_import_confirm_btn":       ["en": "Import", "th": "นำเข้า", "zh": "导入", "ja": "インポート", "ko": "가져오기", "id": "Impor", "ms": "Import"],
        "org_import_coming_soon":       ["en": "Import via file picker — coming in next update", "th": "นำเข้าผ่าน File Picker — จะมาในการอัปเดตถัดไป", "zh": "文件导入 — 即将推出", "ja": "ファイルインポート — 近日公開", "ko": "파일 가져오기 — 다음 업데이트 예정", "id": "Import via file picker — akan hadir di update berikutnya", "ms": "Import melalui pemilih fail — akan datang dalam kemaskini seterusnya"],
        "org_delete_all_title":         ["en": "Delete ALL Data?", "th": "ลบข้อมูลทั้งหมด?", "zh": "删除所有数据?", "ja": "全データ削除?", "ko": "모든 데이터 삭제?", "id": "Hapus SEMUA Data?", "ms": "Padam SEMUA Data?"],
        "org_delete_all_msg":           ["en": "This is irreversible. All local data will be permanently removed.", "th": "การดำเนินการนี้ไม่สามารถเลิกทำได้ ข้อมูลในเครื่องทั้งหมดจะถูกลบอย่างถาวร", "zh": "此操作不可撤销", "ja": "元に戻せません", "ko": "되돌릴 수 없습니다", "id": "Tindakan ini tidak dapat dibatalkan", "ms": "Tindakan ini tidak boleh dibuat asal"],
        "org_delete_all_confirm_btn":   ["en": "Delete Everything", "th": "ลบทั้งหมด", "zh": "删除所有", "ja": "全て削除", "ko": "모두 삭제", "id": "Hapus Semua", "ms": "Padam Semua"],
        "org_delete_all_coming_soon":   ["en": "Full wipe requires confirmation from Supabase dashboard — coming in next update", "th": "การลบข้อมูลทั้งหมดต้องยืนยันผ่าน Supabase dashboard — จะมาในการอัปเดตถัดไป", "zh": "完整清除需要通过Supabase仪表板确认", "ja": "完全削除はSupabaseダッシュボードでの確認が必要", "ko": "전체 삭제는 Supabase 대시보드 확인 필요", "id": "Penghapusan penuh memerlukan konfirmasi dari dasbor Supabase", "ms": "Pemadaman penuh memerlukan pengesahan dari papan pemuka Supabase"],
        "org_export_success_msg":       ["en": "Export complete", "th": "ส่งออกข้อมูลสำเร็จ", "zh": "导出完成", "ja": "エクスポート完了", "ko": "내보내기 완료", "id": "Ekspor selesai", "ms": "Eksport selesai"],
        "org_export_failed_msg":        ["en": "Export failed", "th": "ส่งออกข้อมูลล้มเหลว", "zh": "导出失败", "ja": "エクスポート失敗", "ko": "내보내기 실패", "id": "Ekspor gagal", "ms": "Eksport gagal"]
        ,
        // L-5: Social Security & Tax Withholding
        "payroll_ss_settings_title":  ["en": "SOCIAL SECURITY", "th": "ประกันสังคม", "zh": "社保", "ja": "社会保険", "ko": "사회보험", "id": "Jaminan Sosial", "ms": "Keselamatan Sosial"],
        "payroll_ss_rate_lbl":        ["en": "SS Contribution Rate", "th": "อัตราเงินสมทบ", "zh": "社保费率", "ja": "保険料率", "ko": "보험료율", "id": "Tarif Kontribusi SS", "ms": "Kadar Caruman SS"],
        "payroll_ss_cap_lbl":         ["en": "Monthly Cap", "th": "เพดานรายเดือน", "zh": "月上限", "ja": "月額上限", "ko": "월 상한선", "id": "Batas Bulanan", "ms": "Had Bulanan"],
        "payroll_ss_min_wage_lbl":    ["en": "Min. Wage for SS", "th": "ค่าแรงขั้นต่ำที่ต้องหักประกันสังคม", "zh": "最低工资(需缴社保)", "ja": "社保対象最低賃金", "ko": "사회보험 최저임금", "id": "Upah Min. untuk SS", "ms": "Upah Min. untuk SS"],
        "payroll_ss_hint":            ["en": "Standard: 5% up to ฿750/month, applies when wage ≥ ฿1,650", "th": "มาตรฐาน: 5% สูงสุด ฿750/เดือน ใช้เมื่อค่าแรง ≥ ฿1,650", "zh": "标准: 5%最高฿750/月,工资≥฿1,650时适用", "ja": "標準: 5%上限฿750/月,賃金≥฿1,650", "ko": "기준: 5% 최대 ฿750/월, 임금 ≥ ฿1,650 적용", "id": "Standar: 5% maks ฿750/bulan, berlaku jika gaji ≥ ฿1.650", "ms": "Piawaian: 5% maks ฿750/bulan, berlaku jika gaji ≥ ฿1,650"],
        "payroll_tax_settings_title": ["en": "TAX WITHHOLDING", "th": "ภาษีหัก ณ ที่จ่าย", "zh": "代扣所得税", "ja": "源泉徴収", "ko": "원천징수", "id": "Pemotongan Pajak", "ms": "Potongan Cukai"],
        "payroll_tax_enable_toggle":  ["en": "Enable Tax Withholding", "th": "เปิดใช้ภาษีหัก ณ ที่จ่าย", "zh": "启用代扣所得税", "ja": "源泉徴収を有効にする", "ko": "원천징수 활성화", "id": "Aktifkan Pemotongan Pajak", "ms": "Aktifkan Potongan Cukai"],
        "payroll_tax_allowance_lbl":  ["en": "Personal Allowance", "th": "ค่าลดหย่อนส่วนตัว", "zh": "个人减免", "ja": "個人控除", "ko": "인적공제", "id": "Tunjangan Pribadi", "ms": "Elaun Peribadi"],
        "payroll_tax_hint":           ["en": "Thai PIT progressive brackets 2024: 0–5–10–15–20–25–30–35%", "th": "ภาษีเงินได้บุคคลธรรมดา 2567: ขั้นบันได 0–5–10–15–20–25–30–35%", "zh": "泰国所得税2024累进税率: 0–5–10–15–20–25–30–35%", "ja": "タイ所得税2024累進税率: 0–5–10–15–20–25–30–35%", "ko": "태국 소득세 2024 누진세율: 0–5–10–15–20–25–30–35%", "id": "PIT Thailand 2024 progresif: 0–5–10–15–20–25–30–35%", "ms": "PIT Thailand 2024 progresif: 0–5–10–15–20–25–30–35%"]
        ,
        // L-2: Monthly Comparison Report
        "report_monthly_comparison_title": ["en": "Monthly Comparison", "th": "เปรียบเทียบรายเดือน", "zh": "月度对比", "ja": "月別比較", "ko": "월별 비교", "id": "Perbandingan Bulanan", "ms": "Perbandingan Bulanan"],
        "report_months_3":   ["en": "3 months", "th": "3 เดือน", "zh": "3个月", "ja": "3ヶ月", "ko": "3개월", "id": "3 bulan", "ms": "3 bulan"],
        "report_months_6":   ["en": "6 months", "th": "6 เดือน", "zh": "6个月", "ja": "6ヶ月", "ko": "6개월", "id": "6 bulan", "ms": "6 bulan"],
        "report_months_12":  ["en": "12 months", "th": "12 เดือน", "zh": "12个月", "ja": "12ヶ月", "ko": "12개월", "id": "12 bulan", "ms": "12 bulan"],
        "report_revenue":    ["en": "Revenue", "th": "ยอดขาย", "zh": "营收", "ja": "売上", "ko": "매출", "id": "Pendapatan", "ms": "Hasil"],
        "report_orders":     ["en": "Orders", "th": "ออเดอร์", "zh": "订单", "ja": "注文数", "ko": "주문수", "id": "Pesanan", "ms": "Pesanan"],
        "report_avg_order":  ["en": "Avg. Order", "th": "เฉลี่ยต่อบิล", "zh": "均单", "ja": "平均注文", "ko": "평균 주문", "id": "Rata-rata Pesanan", "ms": "Purata Pesanan"],
        "report_tax_collected": ["en": "Tax Collected", "th": "ภาษีที่เก็บ", "zh": "已收税额", "ja": "徴収税額", "ko": "징수 세금", "id": "Pajak Terkumpul", "ms": "Cukai Terkumpul"],
        "report_revenue_trend": ["en": "REVENUE TREND", "th": "แนวโน้มยอดขาย", "zh": "营收趋势", "ja": "売上推移", "ko": "매출 추이", "id": "Tren Pendapatan", "ms": "Trend Hasil"],
        "report_monthly_breakdown": ["en": "MONTHLY BREAKDOWN", "th": "รายละเอียดรายเดือน", "zh": "月度明细", "ja": "月別詳細", "ko": "월별 상세", "id": "Rincian Bulanan", "ms": "Pecahan Bulanan"],
        "report_month_col":   ["en": "Month", "th": "เดือน", "zh": "月份", "ja": "月", "ko": "월", "id": "Bulan", "ms": "Bulan"],
        "report_revenue_col": ["en": "Revenue", "th": "ยอดขาย", "zh": "营收", "ja": "売上", "ko": "매출", "id": "Pendapatan", "ms": "Hasil"],
        "report_orders_col":  ["en": "Orders", "th": "บิล", "zh": "单数", "ja": "注文", "ko": "주문", "id": "Pesanan", "ms": "Pesanan"],
        "report_avg_col":     ["en": "Avg.", "th": "เฉลี่ย", "zh": "均单", "ja": "平均", "ko": "평균", "id": "Rata-rata", "ms": "Purata"],
        "report_top_item_col": ["en": "Top Item", "th": "สินค้าขายดี", "zh": "最热单品", "ja": "ベスト商品", "ko": "베스트 상품", "id": "Item Terlaris", "ms": "Item Terlaris"],
        "report_no_data":     ["en": "No data to compare yet", "th": "ยังไม่มีข้อมูลสำหรับเปรียบเทียบ", "zh": "暂无可比较数据", "ja": "比較データなし", "ko": "비교할 데이터 없음", "id": "Belum ada data untuk dibandingkan", "ms": "Tiada data untuk dibandingkan"]
        ,
        // L-6: Multi-Branch UI
        "store_branches_tab":         ["en": "Branches", "th": "สาขา", "zh": "分店", "ja": "支店", "ko": "지점", "id": "Cabang", "ms": "Cawangan"],
        "store_no_branches_hint":     ["en": "No branches yet — add your first branch", "th": "ยังไม่มีสาขา — เพิ่มสาขาแรก", "zh": "还没有分店 — 添加第一家", "ja": "支店なし — 最初の支店を追加", "ko": "지점 없음 — 첫 지점 추가", "id": "Belum ada cabang — tambahkan cabang pertama", "ms": "Belum ada cawangan — tambah cawangan pertama"],
        "store_active_badge":         ["en": "Active", "th": "สาขาที่ใช้งาน", "zh": "当前", "ja": "現在", "ko": "현재", "id": "Aktif", "ms": "Aktif"],
        "store_branch_summary_title": ["en": "BRANCH SUMMARY", "th": "สรุปสาขา", "zh": "分店概览", "ja": "支店概要", "ko": "지점 요약", "id": "Ringkasan Cabang", "ms": "Ringkasan Cawangan"],
        "store_branch_count_unit":    ["en": "branches registered", "th": "สาขาที่ลงทะเบียน", "zh": "家分店", "ja": "店舗登録済み", "ko": "지점 등록됨", "id": "cabang terdaftar", "ms": "cawangan didaftar"],
        "store_edit_branch_title":    ["en": "Edit Branch", "th": "แก้ไขสาขา", "zh": "编辑分店", "ja": "支店編集", "ko": "지점 수정", "id": "Edit Cabang", "ms": "Edit Cawangan"],
        "branch_name_placeholder":    ["en": "e.g. Siam Paragon Branch", "th": "เช่น สาขาสยามพารากอน", "zh": "如: 暹罗百丽宫店", "ja": "例: サイアムパラゴン店", "ko": "예: 시암파라곤 지점", "id": "cth: Cabang Siam Paragon", "ms": "cth: Cawangan Siam Paragon"],
        "branch_address_placeholder": ["en": "Street address, City", "th": "ที่อยู่, เมือง", "zh": "街道地址, 城市", "ja": "住所, 市区町村", "ko": "주소, 도시", "id": "Alamat, Kota", "ms": "Alamat, Bandar"],
        "branch_phone_placeholder":   ["en": "Branch contact number", "th": "เบอร์โทรศัพท์สาขา", "zh": "分店联系电话", "ja": "支店電話番号", "ko": "지점 연락처", "id": "Nomor kontak cabang", "ms": "Nombor hubungi cawangan"]
        ,
        // L-1: Waitlist / Queue System
        "waitlist_title":                ["en": "Waitlist", "th": "คิวรอ", "zh": "等候名单", "ja": "順番待ち", "ko": "대기 목록", "id": "Daftar Tunggu", "ms": "Senarai Tunggu"],
        "waitlist_add_btn":              ["en": "Add to Queue", "th": "เพิ่มคิว", "zh": "加入排队", "ja": "順番追加", "ko": "대기 추가", "id": "Tambah ke Antrian", "ms": "Tambah ke Baris"],
        "waitlist_add_title":            ["en": "New Queue Entry", "th": "เพิ่มลูกค้าเข้าคิว", "zh": "新增等候", "ja": "新規順番", "ko": "새 대기 추가", "id": "Entri Antrian Baru", "ms": "Entri Baris Baharu"],
        "waitlist_tab_waiting":          ["en": "Waiting", "th": "รออยู่", "zh": "等候中", "ja": "待ち", "ko": "대기 중", "id": "Menunggu", "ms": "Menunggu"],
        "waitlist_tab_history":          ["en": "History", "th": "ประวัติ", "zh": "历史", "ja": "履歴", "ko": "이력", "id": "Riwayat", "ms": "Sejarah"],
        "waitlist_stat_waiting":         ["en": "Waiting Now", "th": "รออยู่ขณะนี้", "zh": "当前等候", "ja": "現在待ち", "ko": "현재 대기", "id": "Sedang Menunggu", "ms": "Menunggu Sekarang"],
        "waitlist_stat_avg_wait":        ["en": "Avg. Wait", "th": "รอเฉลี่ย", "zh": "平均等候", "ja": "平均待ち", "ko": "평균 대기", "id": "Rata-rata Tunggu", "ms": "Purata Tunggu"],
        "waitlist_stat_seated_today":    ["en": "Seated Today", "th": "นั่งแล้ววันนี้", "zh": "今日已入座", "ja": "本日着席", "ko": "오늘 착석", "id": "Duduk Hari Ini", "ms": "Duduk Hari Ini"],
        "waitlist_min_unit":             ["en": "min", "th": "นาที", "zh": "分钟", "ja": "分", "ko": "분", "id": "mnt", "ms": "min"],
        "waitlist_overdue_badge":        ["en": "Overdue!", "th": "เกินเวลา!", "zh": "超时！", "ja": "時間超過！", "ko": "초과！", "id": "Terlambat!", "ms": "Terlewat!"],
        "waitlist_empty_title":          ["en": "No one waiting", "th": "ไม่มีลูกค้ารอ", "zh": "暂无等候", "ja": "待ち客なし", "ko": "대기 없음", "id": "Tidak ada yang menunggu", "ms": "Tiada yang menunggu"],
        "waitlist_empty_desc":           ["en": "Tap '+' to add customers to the queue", "th": "กด '+' เพื่อเพิ่มลูกค้าเข้าคิว", "zh": "点击'+'将客户加入排队", "ja": "'+'をタップして追加", "ko": "'+'를 눌러 대기 추가", "id": "Ketuk '+' untuk menambahkan", "ms": "Ketuk '+' untuk tambah pelanggan"],
        "waitlist_guest_section":        ["en": "Guest Details", "th": "ข้อมูลลูกค้า", "zh": "客人详情", "ja": "ゲスト詳細", "ko": "고객 정보", "id": "Detail Tamu", "ms": "Butiran Tetamu"],
        "waitlist_name_placeholder":     ["en": "Guest name", "th": "ชื่อลูกค้า", "zh": "客人姓名", "ja": "ゲスト名", "ko": "고객 이름", "id": "Nama tamu", "ms": "Nama tetamu"],
        "waitlist_party_size_lbl":       ["en": "Party Size", "th": "จำนวนคน", "zh": "人数", "ja": "人数", "ko": "인원수", "id": "Jumlah Tamu", "ms": "Saiz Kumpulan"],
        "waitlist_phone_placeholder":    ["en": "Phone (optional)", "th": "โทรศัพท์ (ไม่บังคับ)", "zh": "电话（选填）", "ja": "電話（任意）", "ko": "전화(선택)", "id": "Telepon (opsional)", "ms": "Telefon (pilihan)"],
        "waitlist_wait_section":         ["en": "Wait Time", "th": "เวลารอ", "zh": "等待时间", "ja": "待ち時間", "ko": "대기 시간", "id": "Waktu Tunggu", "ms": "Masa Tunggu"],
        "waitlist_est_wait_lbl":         ["en": "Estimated Wait", "th": "เวลารอโดยประมาณ", "zh": "预计等待", "ja": "予想待ち時間", "ko": "예상 대기", "id": "Perkiraan Tunggu", "ms": "Anggaran Tunggu"],
        "waitlist_notes_section":        ["en": "Notes", "th": "หมายเหตุ", "zh": "备注", "ja": "メモ", "ko": "메모", "id": "Catatan", "ms": "Nota"],
        "waitlist_notes_placeholder":    ["en": "Allergies, preferences…", "th": "อาหารที่แพ้, ความต้องการ…", "zh": "过敏, 偏好…", "ja": "アレルギー, 好み…", "ko": "알레르기, 선호도…", "id": "Alergi, preferensi…", "ms": "Alahan, pilihan…"],
        "waitlist_save_btn":             ["en": "Add to Queue", "th": "เพิ่มเข้าคิว", "zh": "加入排队", "ja": "キューに追加", "ko": "대기 추가", "id": "Tambahkan ke Antrian", "ms": "Tambah ke Baris"],
        "waitlist_seat_section":         ["en": "Seat Guest", "th": "ให้ลูกค้านั่ง", "zh": "安排入座", "ja": "着席案内", "ko": "착석 안내", "id": "Dudukkan Tamu", "ms": "Dudukkan Tetamu"],
        "waitlist_table_number_placeholder": ["en": "Table number", "th": "หมายเลขโต๊ะ", "zh": "桌号", "ja": "テーブル番号", "ko": "테이블 번호", "id": "Nomor meja", "ms": "Nombor meja"],
        "waitlist_seat_btn":             ["en": "Seat Now", "th": "ให้นั่งได้เลย", "zh": "立即入座", "ja": "今すぐ着席", "ko": "지금 착석", "id": "Dudukkan Sekarang", "ms": "Duduk Sekarang"],
        "waitlist_cancel_section":       ["en": "Other Actions", "th": "การดำเนินการอื่น", "zh": "其他操作", "ja": "その他", "ko": "기타 작업", "id": "Tindakan Lain", "ms": "Tindakan Lain"],
        "waitlist_cancel_btn":           ["en": "Cancel / Left", "th": "ยกเลิก / กลับไปแล้ว", "zh": "取消/离开", "ja": "キャンセル", "ko": "취소/퇴장", "id": "Batal/Pergi", "ms": "Batal/Pergi"],
        "waitlist_no_show_btn":          ["en": "No Show", "th": "ไม่มา", "zh": "未出现", "ja": "ノーショー", "ko": "노쇼", "id": "Tidak Hadir", "ms": "Tidak Hadir"],
        "waitlist_queue_number_lbl":     ["en": "Queue #", "th": "หมายเลขคิว", "zh": "排队号", "ja": "順番号", "ko": "대기 번호", "id": "No. Antrian", "ms": "No. Baris"],
        "waitlist_status_lbl":           ["en": "Status", "th": "สถานะ", "zh": "状态", "ja": "ステータス", "ko": "상태", "id": "Status", "ms": "Status"],
        "waitlist_status_waiting":       ["en": "Waiting", "th": "รออยู่", "zh": "等候中", "ja": "待ち", "ko": "대기", "id": "Menunggu", "ms": "Menunggu"],
        "waitlist_status_seated":        ["en": "Seated", "th": "นั่งแล้ว", "zh": "已入座", "ja": "着席", "ko": "착석", "id": "Duduk", "ms": "Duduk"],
        "waitlist_status_no_show":       ["en": "No Show", "th": "ไม่มา", "zh": "未出现", "ja": "ノーショー", "ko": "노쇼", "id": "Tidak Hadir", "ms": "Tidak Hadir"],
        "waitlist_status_cancelled":     ["en": "Cancelled", "th": "ยกเลิก", "zh": "已取消", "ja": "キャンセル", "ko": "취소", "id": "Dibatalkan", "ms": "Dibatalkan"]
        ,
        // L-7: Multiple KDS Routing
        "kds_routing_section_title": ["en": "CATEGORY ROUTING", "th": "การกำหนด KDS ตามหมวดหมู่", "zh": "按分类路由", "ja": "カテゴリルーティング", "ko": "카테고리 라우팅", "id": "Routing Kategori", "ms": "Laluan Kategori"],
        "kds_no_categories_hint":    ["en": "No menu categories found — add categories in Menus first", "th": "ไม่พบหมวดหมู่เมนู — เพิ่มหมวดหมู่ใน Menus ก่อน", "zh": "没有菜单分类 — 请先在菜单中添加", "ja": "カテゴリなし — メニューで追加してください", "ko": "메뉴 카테고리 없음 — 메뉴에서 먼저 추가하세요", "id": "Tidak ada kategori menu — tambahkan di Menu dulu", "ms": "Tiada kategori menu — tambah di Menu dahulu"],
        "kds_route_kitchen":         ["en": "Kitchen", "th": "ครัว", "zh": "厨房", "ja": "キッチン", "ko": "주방", "id": "Dapur", "ms": "Dapur"],
        "kds_route_bar":             ["en": "Bar", "th": "บาร์", "zh": "吧台", "ja": "バー", "ko": "바", "id": "Bar", "ms": "Bar"],
        "kds_route_both":            ["en": "Both", "th": "ทั้งคู่", "zh": "两者", "ja": "両方", "ko": "모두", "id": "Keduanya", "ms": "Kedua-dua"],
        "kds_routing_hint":          ["en": "Each category routes to Kitchen, Bar, or both screens. Items without a rule use the beverage keyword heuristic.", "th": "แต่ละหมวดหมู่จะส่งไปยัง ครัว บาร์ หรือทั้งคู่ รายการที่ไม่มีกฎจะใช้การตรวจสอบจากชื่อหมวด", "zh": "每个分类路由到厨房、吧台或两者。无规则的使用饮料关键词启发", "ja": "カテゴリごとにキッチン、バー、または両方へ。ルールなしはキーワード判定", "ko": "각 카테고리를 주방, 바 또는 둘 다로 라우팅. 규칙 없으면 음료 키워드 사용", "id": "Setiap kategori diarahkan ke Dapur, Bar, atau keduanya. Tanpa aturan, gunakan heuristik kata kunci", "ms": "Setiap kategori dihalakan ke Dapur, Bar atau kedua-dua. Tanpa peraturan, gunakan heuristik kata kunci"]
        ,
        // L-9: Physical KDS / Bump Bar Keyboard Shortcuts
        "kds_physical_section_title":    ["en": "PHYSICAL KDS / BUMP BAR", "th": "KDS แบบมีปุ่มกด", "zh": "实体KDS/拍单器", "ja": "物理KDS/バンプバー", "ko": "물리 KDS/범프바", "id": "KDS Fisik/Bump Bar", "ms": "KDS Fizikal/Bump Bar"],
        "kds_keyboard_shortcuts_toggle": ["en": "Enable Keyboard Shortcuts", "th": "เปิดใช้แป้นพิมพ์ลัด", "zh": "启用快捷键", "ja": "キーボードショートカットを有効にする", "ko": "키보드 단축키 활성화", "id": "Aktifkan Pintasan Keyboard", "ms": "Aktifkan Pintasan Papan Kekunci"],
        "kds_keyboard_shortcuts_desc":   ["en": "Use Space/Return to bump, arrows to navigate, ⌘K/⌘B to toggle stations. Works with external keyboard or bump bar.", "th": "Space/Return เพื่อ bump, ลูกศรเพื่อนำทาง, ⌘K/⌘B เพื่อสลับสถานี ใช้ได้กับ External Keyboard หรือ Bump Bar", "zh": "空格/回车=拍单, 方向键=导航, ⌘K/⌘B=切换站台", "ja": "スペース/リターン=バンプ, 矢印キー=移動, ⌘K/⌘B=切替", "ko": "스페이스/리턴=범프, 화살표=이동, ⌘K/⌘B=스테이션 전환", "id": "Spasi/Return=bump, panah=navigasi, ⌘K/⌘B=ganti stasiun", "ms": "Spasi/Return=bump, anak panah=navigasi, ⌘K/⌘B=tukar stesen"],
        "kds_kb_bump":                   ["en": "Bump", "th": "ส่งเสร็จ", "zh": "完成", "ja": "バンプ", "ko": "범프", "id": "Selesai", "ms": "Bump"],
        "kds_kb_navigate":               ["en": "Navigate", "th": "เลื่อน", "zh": "导航", "ja": "移動", "ko": "이동", "id": "Navigasi", "ms": "Navigasi"],
        "kds_kb_deselect":               ["en": "Deselect", "th": "ยกเลิกการเลือก", "zh": "取消选择", "ja": "選択解除", "ko": "선택 해제", "id": "Batalkan Pilihan", "ms": "Nyahpilih"],
        "kds_kb_toggle_kitchen":         ["en": "Kitchen", "th": "ครัว", "zh": "厨房", "ja": "キッチン", "ko": "주방", "id": "Dapur", "ms": "Dapur"],
        "kds_kb_toggle_bar":             ["en": "Bar", "th": "บาร์", "zh": "吧台", "ja": "バー", "ko": "바", "id": "Bar", "ms": "Bar"]
        ,
        // L-8: Online Menu Preview
        "menu_preview_title":           ["en": "Menu Preview", "th": "ดูตัวอย่างเมนู", "zh": "菜单预览", "ja": "メニュープレビュー", "ko": "메뉴 미리보기", "id": "Pratinjau Menu", "ms": "Pratonton Menu"],
        "menu_preview_loading":         ["en": "Loading menu preview…", "th": "กำลังโหลดตัวอย่างเมนู…", "zh": "加载菜单预览中…", "ja": "メニュー読み込み中…", "ko": "메뉴 로딩 중…", "id": "Memuat pratinjau menu…", "ms": "Memuatkan pratonton menu…"],
        "menu_preview_error_title":     ["en": "Unable to Load Preview", "th": "โหลดตัวอย่างไม่ได้", "zh": "无法加载预览", "ja": "プレビューを読み込めません", "ko": "미리보기 로드 실패", "id": "Tidak dapat memuat pratinjau", "ms": "Tidak dapat muatkan pratonton"],
        "menu_preview_invalid_url":     ["en": "Preview URL not configured", "th": "ยังไม่ได้ตั้งค่า URL สำหรับ Preview", "zh": "预览URL未配置", "ja": "プレビューURLが未設定", "ko": "미리보기 URL 미설정", "id": "URL pratinjau belum dikonfigurasi", "ms": "URL pratonton belum dikonfigurasikan"],
        "menu_preview_web_btn":         ["en": "Web Preview", "th": "ดูแบบ Web", "zh": "网页预览", "ja": "Web表示", "ko": "웹 미리보기", "id": "Pratinjau Web", "ms": "Pratonton Web"],
        "menu_preview_offline_btn":     ["en": "Local List", "th": "รายการในเครื่อง", "zh": "本地列表", "ja": "ローカルリスト", "ko": "로컬 목록", "id": "Daftar Lokal", "ms": "Senarai Tempatan"],
        "menu_preview_offline_title":   ["en": "Local Menu Preview", "th": "ตัวอย่างเมนู (ออฟไลน์)", "zh": "本地菜单预览", "ja": "ローカルメニュープレビュー", "ko": "로컬 메뉴 미리보기", "id": "Pratinjau Menu Lokal", "ms": "Pratonton Menu Tempatan"],
        "menu_preview_offline_desc":    ["en": "Showing local menu data. Web preview requires internet connection.", "th": "แสดงข้อมูลเมนูในเครื่อง ต้องเชื่อมต่ออินเทอร์เน็ตเพื่อดูแบบ Web", "zh": "显示本地菜单数据。网页预览需要网络连接", "ja": "ローカルデータを表示中。Web表示はインターネット接続が必要", "ko": "로컬 메뉴 데이터 표시 중. 웹 미리보기는 인터넷 필요", "id": "Menampilkan data menu lokal. Pratinjau web memerlukan koneksi internet", "ms": "Memaparkan data menu tempatan. Pratonton web memerlukan sambungan internet"],
        "menu_preview_no_category":     ["en": "Uncategorised", "th": "ไม่ระบุหมวดหมู่", "zh": "未分类", "ja": "未分類", "ko": "미분류", "id": "Tidak Berkategori", "ms": "Tidak Berkategori"],
        "menu_preview_no_items":        ["en": "No menu items yet", "th": "ยังไม่มีรายการเมนู", "zh": "暂无菜单", "ja": "メニューなし", "ko": "메뉴 없음", "id": "Belum ada item menu", "ms": "Tiada item menu"],
        "menu_preview_unavailable":     ["en": "Unavailable", "th": "ไม่พร้อมขาย", "zh": "不可用", "ja": "提供不可", "ko": "판매 불가", "id": "Tidak Tersedia", "ms": "Tidak Tersedia"]
    ]
}
