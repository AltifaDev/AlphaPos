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
        static let startPlanBtn = "start_plan_btn"
        static let acceptTermsPrivacy = "accept_terms_privacy"
        static let billingMonthly = "billing_monthly"
        static let billingAnnualSave20 = "billing_annual_save_20"
        static let priceOneTime = "price_one_time"
        static let pricePerMonth = "price_per_month"
        static let pricePerYear = "price_per_year"
        static let tenantWipeNoticeTitle = "tenant_wipe_notice_title"
        static let tenantWipeNoticeSwitch = "tenant_wipe_notice_switch"
        static let tenantWipeNoticeLogout = "tenant_wipe_notice_logout"
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
        static let preparingWorkspace = "preparing_workspace"
        static let openingWorkspaceFor = "opening_workspace_for"
        static let error = "error"
        static let success = "success"
        static let retry = "retry"
    }

    enum Sections {
        static let kds = "section_kds"
        static let tableSystem = "section_table_system"
        static let queueSystem = "section_queue_system"
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
        static let grossSales = "reports_gross_sales"
        static let netSalesIncVAT = "reports_net_sales_inc_vat"
        static let netSalesExVAT = "reports_net_sales_ex_vat"
        static let salesBridge = "reports_sales_bridge"
        static let lessDiscounts = "reports_less_discounts"
        static let lessRefunds = "reports_less_refunds"
        static let merchandiseSubtotal = "reports_merchandise_subtotal"
        static let serviceCharge = "reports_service_charge_line"
        static let vatCollected = "reports_vat_collected"
        static let tipsNotInSales = "reports_tips_not_in_sales"
        static let voids = "reports_voids"
        static let tenderReconcile = "reports_tender_reconcile"
        static let paymentsCollected = "reports_payments_collected"
        static let tenderVariance = "reports_tender_variance"
        static let tenderVarianceHint = "reports_tender_variance_hint"
        static let zReportCrossLink = "reports_z_report_cross_link"
        static let modeOffline = "reports_mode_offline"
        static let modeOnline = "reports_mode_online"
        static let asOf = "reports_as_of"
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
        static let unscheduled = "timecard_unscheduled"
        static let filterStaff = "timecard_filter_staff"
        static let statusOnShift = "timecard_status_on_shift"
        static let statusOffShift = "timecard_status_off_shift"
        static let clockInAt = "timecard_clock_in_at"
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

// MARK: - Translation Dictionary (loaded from Resources/translations.json)
// Huge nested Swift dictionary literals are pathological for Release compile
// (`swift-frontend` with -O can stall/OOM). Keep strings in JSON instead.

enum AppLocalization {
    private static let _translations: [String: [String: String]] = {
        if let url = Bundle.main.url(forResource: "translations", withExtension: "json") {
            do {
                let data = try Data(contentsOf: url)
                return try JSONDecoder().decode([String: [String: String]].self, from: data)
            } catch {
                assertionFailure("Failed to decode translations.json: \(error)")
                return [:]
            }
        }
        #if TEST_RUNNER
        // Unit-test binary has no app bundle — load from the repo path when present.
        let candidates = [
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("AlphaPos/Resources/translations.json"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Resources/translations.json")
        ]
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            if let data = try? Data(contentsOf: url),
               let decoded = try? JSONDecoder().decode([String: [String: String]].self, from: data) {
                return decoded
            }
        }
        return [:]
        #else
        assertionFailure("Missing translations.json in app bundle")
        return [:]
        #endif
    }()

    static var translations: [String: [String: String]] { _translations }
}
