#!/usr/bin/env python3
import re

filepath = "/Users/mac/Documents/AlphaPos/AlphaPos/Core/Localization/AppLocalization.swift"

with open(filepath, "r", encoding="utf-8") as f:
    content = f.read()

# 1. Remove the second (duplicate) enum Reports block at the end of enum L
# This duplicate starts after enum Auth
# Let's locate the duplicate Reports block
auth_match = re.search(r"(\s*)enum Auth \{[\s\S]*?\n\1\}", content)
if not auth_match:
    print("Error: Could not find enum Auth")
    exit(1)

content_after_auth = content[auth_match.end():]
# Find the next enum Reports { ... }
duplicate_reports_match = re.search(r"(\s*)enum Reports \{[\s\S]*?\n\1\}", content_after_auth)
if duplicate_reports_match:
    print("Found duplicate Reports enum, removing it...")
    # Remove it from content
    content = content[:auth_match.end()] + content_after_auth[:duplicate_reports_match.start()] + content_after_auth[duplicate_reports_match.end():]
else:
    print("No duplicate Reports enum found after enum Auth.")

# 2. Replace the first enum Reports block (around line 419) with the complete unified key set
first_reports_match = re.search(r"(\s*)enum Reports \{[\s\S]*?\n\1\}", content)
if not first_reports_match:
    print("Error: Could not find first enum Reports")
    exit(1)

unified_reports_enum = """    enum Reports {
        static let title              = "reports_title"
        static let selectReport       = "reports_select"
        static let period             = "reports_period"
        static let periodDaily        = "reports_period_daily"
        static let periodWeekly       = "reports_period_weekly"
        static let periodMonthly      = "reports_period_monthly"
        static let periodCustom       = "reports_period_custom"
        static let startDate          = "reports_start_date"
        static let endDate            = "reports_end_date"
        static let date               = "reports_date"
        static let exportPDF          = "reports_export_pdf"
        static let noData             = "reports_no_data"
        static let dailySales         = "reports_daily_sales"
        static let grossRevenue       = "reports_gross_revenue"
        static let netRevenue         = "reports_net_revenue"
        static let totalOrders        = "reports_total_orders"
        static let avgTicket          = "reports_avg_ticket"
        static let totalDiscount      = "reports_total_discount"
        static let totalRefunds       = "reports_total_refunds"
        static let paymentMethods     = "reports_payment_methods"
        static let peakHour           = "reports_peak_hour"
        static let hourlySales        = "reports_hourly_sales"
        static let paymentBreakdown   = "reports_payment_breakdown"
        static let methodCash         = "reports_method_cash"
        static let methodCard         = "reports_method_card"
        static let methodQR           = "reports_method_qr"
        static let zReport            = "reports_z_report"
        static let endOfDay           = "reports_end_of_day"
        static let noSession          = "reports_no_session"
        static let noSessionDesc      = "reports_no_session_desc"
        static let sessionInfo        = "reports_session_info"
        static let openedAt           = "reports_opened_at"
        static let closedAt           = "reports_closed_at"
        static let duration           = "reports_duration"
        static let cashFlow           = "reports_cash_flow"
        static let openingBalance     = "reports_opening_balance"
        static let cashSales          = "reports_cash_sales"
        static let cashIn             = "reports_cash_in"
        static let cashOut            = "reports_cash_out"
        static let totals             = "reports_totals"
        static let expectedCash       = "reports_expected_cash"
        static let actualCash         = "reports_actual_cash"
        static let variance           = "reports_variance"
        static let varianceShort      = "reports_variance_short"
        static let varianceOver       = "reports_variance_over"
        static let varianceOk         = "reports_variance_ok"
        static let taxVAT             = "reports_tax_vat"
        static let salesIncVAT        = "reports_sales_inc_vat"
        static let vatAmount          = "reports_vat_amount"
        static let salesExcVAT        = "reports_sales_exc_vat"
        static let dailyVATBreakdown  = "reports_daily_vat_breakdown"
        static let detailedBreakdown  = "reports_detailed_breakdown"
        static let orders             = "reports_orders"
        static let total              = "reports_total"
        static let menuProfit         = "reports_menu_profit"
        static let totalItems         = "reports_total_items"
        static let totalRevenue       = "reports_total_revenue"
        static let totalCOGS          = "reports_total_cogs"
        static let avgMargin          = "reports_avg_margin"
        static let topProfitable      = "reports_top_profitable"
        static let leastProfitable    = "reports_least_profitable"
        static let menuItemBreakdown  = "reports_menu_item_breakdown"
        static let itemName           = "reports_item_name"
        static let qtySold            = "reports_qty_sold"
        static let revenue            = "reports_revenue"
        static let cogs               = "reports_cogs"
        static let profit             = "reports_profit"
        static let margin             = "reports_margin"
        static let inventory          = "reports_inventory"
        static let totalStockValue    = "reports_total_stock_value"
        static let lowStockCount      = "reports_low_stock_count"
        static let outOfStockCount    = "reports_out_of_stock_count"
        static let wasteCost          = "reports_waste_cost"
        static let outOfStock         = "reports_out_of_stock"
        static let outOfStockBadge    = "reports_out_of_stock_badge"
        static let reorderLevel       = "reports_reorder_level"
        static let lowStock           = "reports_low_stock"
        static let noLowStock         = "reports_no_low_stock"
        static let wasteAndSpoilage   = "reports_waste_and_spoilage"
        static let totalWaste         = "reports_total_waste"
        static let noWaste            = "reports_no_waste"
        static let quantity           = "reports_quantity"
        static let cost               = "reports_cost"
        static let notes              = "reports_notes"
        static let employeeHours      = "reports_employee_hours"
        static let totalEmployees     = "reports_total_employees"
        static let totalHours         = "reports_total_hours"
        static let totalOT            = "reports_total_ot"
        static let totalLabor         = "reports_total_labor"
        static let employeeName       = "reports_employee_name"
        static let regularHours       = "reports_regular_hours"
        static let overtimeHours      = "reports_overtime_hours"
        static let breakTime          = "reports_break_time"
        static let payRate            = "reports_pay_rate"
        static let estimatedCost      = "reports_estimated_cost"

        static let totalLaborHours    = "reports_total_labor_hours"
        static let totalLaborCost     = "reports_total_labor_cost"
        static let activeStaff        = "reports_active_staff"
        static let hoursPerEmployee   = "reports_hours_per_employee"
        static let hours              = "reports_hours"
        static let employeeDetail     = "reports_employee_detail"
        static let employee           = "reports_employee"
        static let type               = "reports_type"
        static let breaks             = "reports_breaks"
        static let rate               = "reports_rate"
        static let estCost            = "reports_est_cost"
        static let hourly             = "reports_hourly"
        static let daily              = "reports_daily"
        static let monthly            = "reports_monthly"
    }"""

content = content[:first_reports_match.start()] + unified_reports_enum + content[first_reports_match.end():]

with open(filepath, "w", encoding="utf-8") as f:
    f.write(content)

print("Successfully cleaned up AppLocalization.swift enums!")
