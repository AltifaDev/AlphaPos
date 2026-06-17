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

    func t(_ key: String, _ args: CVarArg...) -> String {
        let format = translate(key)
        guard !args.isEmpty else { return format }
        return String(format: format, arguments: args)
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
        "tab_tables": ["en": "Tables", "th": "โต๊ะ", "zh": "桌台", "ja": "テーブル", "ko": "테이블", "id": "Meja", "ms": "Meja"],
        "tab_pos": ["en": "POS", "th": "ขายหน้าร้าน", "zh": "收银", "ja": "POS", "ko": "POS", "id": "POS", "ms": "POS"],
        "tab_cash_drawer": ["en": "Cash Drawer", "th": "ลิ้นชักเงินสด", "zh": "钱箱", "ja": "キャッシュドロワー", "ko": "금전함", "id": "Laci Kas", "ms": "Laci Tunai"],
        "tab_kitchen": ["en": "Kitchen", "th": "ครัว", "zh": "厨房", "ja": "キッチン", "ko": "주방", "id": "Dapur", "ms": "Dapur"],
        "tab_timecard": ["en": "Timecard", "th": "บัตรเวลา", "zh": "考勤", "ja": "タイムカード", "ko": "타임카드", "id": "Kartu Waktu", "ms": "Kad Masa"],
        "tab_inventory": ["en": "Inventory", "th": "สินค้าคงคลัง", "zh": "库存", "ja": "在庫", "ko": "재고", "id": "Inventaris", "ms": "Inventori"],
        "tab_gift_cards": ["en": "Gift Cards", "th": "บัตรของขวัญ", "zh": "礼品卡", "ja": "ギフトカード", "ko": "기프트 카드", "id": "Kartu Hadiah", "ms": "Kad Hadiah"],
        "tab_loyalty": ["en": "Loyalty", "th": "สะสมแต้ม", "zh": "会员", "ja": "ロイヤルティ", "ko": "로열티", "id": "Loyalitas", "ms": "Kesetiaan"],
        "tab_payroll": ["en": "Payroll", "th": "เงินเดือน", "zh": "工资", "ja": "給与", "ko": "급여", "id": "Penggajian", "ms": "Gaji"],
        "tab_sales": ["en": "Sales", "th": "ยอดขาย", "zh": "销售", "ja": "売上", "ko": "매출", "id": "Penjualan", "ms": "Jualan"],
        "tab_reports": ["en": "Reports", "th": "รายงาน", "zh": "报表", "ja": "レポート", "ko": "보고서", "id": "Laporan", "ms": "Laporan"],
        "tab_promotions": ["en": "Promotions", "th": "โปรโมชั่น", "zh": "促销", "ja": "プロモーション", "ko": "프로모션", "id": "Promosi", "ms": "Promosi"],
        "tab_store": ["en": "Store", "th": "ร้านค้า", "zh": "门店", "ja": "店舗", "ko": "매장", "id": "Toko", "ms": "Kedai"],
        "tab_sync_health": ["en": "Sync Health", "th": "สถานะซิงค์", "zh": "同步状态", "ja": "同期状態", "ko": "동기화 상태", "id": "Status Sinkronisasi", "ms": "Status Segerak"],
        "tab_settings": ["en": "Settings", "th": "ตั้งค่า", "zh": "设置", "ja": "設定", "ko": "설정", "id": "Pengaturan", "ms": "Tetapan"],
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
        "cancel": ["en": "Cancel", "th": "ยกเลิก", "zh": "取消", "ja": "キャンセル", "ko": "취소", "id": "Batal", "ms": "Batal"],
        "save": ["en": "Save", "th": "บันทึก", "zh": "保存", "ja": "保存", "ko": "저장", "id": "Simpan", "ms": "Simpan"],
        "done": ["en": "Done", "th": "เสร็จสิ้น", "zh": "完成", "ja": "完了", "ko": "완료", "id": "Selesai", "ms": "Selesai"],
        "delete": ["en": "Delete", "th": "ลบ", "zh": "删除", "ja": "削除", "ko": "삭제", "id": "Hapus", "ms": "Padam"],
        "edit": ["en": "Edit", "th": "แก้ไข", "zh": "编辑", "ja": "編集", "ko": "편집", "id": "Edit", "ms": "Sunting"],
        "add": ["en": "Add", "th": "เพิ่ม", "zh": "添加", "ja": "追加", "ko": "추가", "id": "Tambah", "ms": "Tambah"],
        "close": ["en": "Close", "th": "ปิด", "zh": "关闭", "ja": "閉じる", "ko": "닫기", "id": "Tutup", "ms": "Tutup"],
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
        "sync_conn_offline": ["en": "Offline", "th": "ออฟไลน์", "zh": "离线", "ja": "オフライン", "ko": "오프라인", "id": "Offline", "ms": "Luar Talian"]
    ]
}
