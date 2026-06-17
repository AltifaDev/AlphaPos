#!/usr/bin/env python3
import os
import re

filepath = "/Users/mac/Documents/AlphaPos/AlphaPos/Core/Localization/AppLocalization.swift"

with open(filepath, "r", encoding="utf-8") as f:
    content = f.read()

# 1. Insert enum Reports inside enum L, right after enum Auth
enum_auth_match = re.search(r"(\s*)enum Auth \{[\s\S]*?\n\1\}", content)
if not enum_auth_match:
    print("Error: Could not find enum Auth in AppLocalization.swift")
    exit(1)

auth_block_end = enum_auth_match.end()

reports_enum_content = """

    enum Reports {
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
        static let date = "reports_date"
        static let orders = "reports_orders"

        static let grossRevenue = "reports_gross_revenue"
        static let netRevenue = "reports_net_revenue"
        static let totalDiscount = "reports_total_discount"
        static let totalRefunds = "reports_total_refunds"
        static let paymentMethods = "reports_payment_methods"
        static let peakHour = "reports_peak_hour"
        static let hourlySales = "reports_hourly_sales"
        static let paymentBreakdown = "reports_payment_breakdown"
        static let methodCash = "reports_method_cash"
        static let methodCard = "reports_method_card"
        static let methodQR = "reports_method_qr"
        static let avgTicket = "reports_avg_ticket"
        static let totalOrders = "reports_total_orders"

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
        static let itemName = "reports_item_name"
        static let quantity = "reports_quantity"
        static let cost = "reports_cost"
        static let notes = "reports_notes"

        static let totalItems = "reports_total_items"
        static let totalRevenue = "reports_total_revenue"
        static let totalCOGS = "reports_total_cogs"
        static let avgMargin = "reports_avg_margin"
        static let topProfitable = "reports_top_profitable"
        static let leastProfitable = "reports_least_profitable"
        static let menuItemBreakdown = "reports_menu_item_breakdown"
        static let qtySold = "reports_qty_sold"
        static let revenue = "reports_revenue"
        static let cogs = "reports_cogs"
        static let profit = "reports_profit"
        static let margin = "reports_margin"

        static let title = "reports_title"
        static let selectReport = "reports_select_report"
        static let period = "reports_period"
        static let periodDaily = "reports_period_daily"
        static let periodWeekly = "reports_period_weekly"
        static let periodMonthly = "reports_period_monthly"
        static let periodCustom = "reports_period_custom"
        static let startDate = "reports_start_date"
        static let endDate = "reports_end_date"
        static let exportPDF = "reports_export_pdf"
        static let dailySales = "reports_daily_sales"
        static let zReport = "reports_z_report"
        static let taxVAT = "reports_tax_vat"
        static let menuProfit = "reports_menu_profit"
        static let inventory = "reports_inventory"
        static let employeeHours = "reports_employee_hours"
    }"""

content = content[:auth_block_end] + reports_enum_content + content[auth_block_end:]

# 2. Insert English/Thai translation blocks under AppLocalization.translations dict start
translations_dict_match = re.search(r"static let translations: \[String: \[String: String\]\] = \[", content)
if not translations_dict_match:
    print("Error: Could not find translations dictionary in AppLocalization.swift")
    exit(1)

dict_start = translations_dict_match.end()

reports_translations_str = """

        "reports_no_session": [
            "en": "No Active Session",
            "th": "ไม่มีเซสชันที่เปิดอยู่"
        ],
        "reports_no_session_desc": [
            "en": "Please open a shift in Cash Drawer to view Z-Report data.",
            "th": "กรุณาเปิดกะในเมนูลิ้นชักเก็บเงินเพื่อดูข้อมูลรายงาน Z-Report"
        ],
        "reports_end_of_day": [
            "en": "End of Day (Z-Report)",
            "th": "รายงานสิ้นสุดวัน (Z-Report)"
        ],
        "reports_session_info": [
            "en": "Session Info",
            "th": "ข้อมูลเซสชัน"
        ],
        "reports_opened_at": [
            "en": "Opened At",
            "th": "เปิดเมื่อ"
        ],
        "reports_closed_at": [
            "en": "Closed At",
            "th": "ปิดเมื่อ"
        ],
        "reports_duration": [
            "en": "Duration",
            "th": "ระยะเวลา"
        ],
        "reports_cash_flow": [
            "en": "Cash Flow Summary",
            "th": "สรุปกระแสเงินสด"
        ],
        "reports_opening_balance": [
            "en": "Opening Cash",
            "th": "เงินสดยกมา"
        ],
        "reports_cash_sales": [
            "en": "Cash Sales",
            "th": "ยอดขายเงินสด"
        ],
        "reports_cash_in": [
            "en": "Cash In",
            "th": "เงินสดเข้า"
        ],
        "reports_cash_out": [
            "en": "Cash Out",
            "th": "เงินสดออก"
        ],
        "reports_totals": [
            "en": "Totals Summary",
            "th": "สรุปยอดรวม"
        ],
        "reports_expected_cash": [
            "en": "Expected Drawer Cash",
            "th": "เงินสดที่ควรมีในลิ้นชัก"
        ],
        "reports_actual_cash": [
            "en": "Actual Counted Cash",
            "th": "เงินสดที่นับได้จริง"
        ],
        "reports_variance": [
            "en": "Variance Summary",
            "th": "สรุปผลต่างเงินสด"
        ],
        "reports_variance_short": [
            "en": "Shortage (Cash missing)",
            "th": "เงินขาด (เงินสดหาย)"
        ],
        "reports_variance_over": [
            "en": "Overage (Cash extra)",
            "th": "เงินเกิน (เงินสดเกิน)"
        ],
        "reports_variance_ok": [
            "en": "Balanced (No variance)",
            "th": "ยอดตรง (ไม่มีผลต่าง)"
        ],
        "reports_total_labor_hours": [
            "en": "Total Labor Hours",
            "th": "ชั่วโมงทำงานรวม"
        ],
        "reports_total_labor_cost": [
            "en": "Total Labor Cost",
            "th": "ต้นทุนแรงงานรวม"
        ],
        "reports_total_ot": [
            "en": "Total Overtime Hours",
            "th": "ชั่วโมงล่วงเวลารวม (OT)"
        ],
        "reports_active_staff": [
            "en": "Active Staff",
            "th": "พนักงานที่ปฏิบัติงาน"
        ],
        "reports_hours_per_employee": [
            "en": "Hours Per Employee",
            "th": "ชั่วโมงทำงานต่อคน"
        ],
        "reports_no_data": [
            "en": "No Data Available",
            "th": "ไม่มีข้อมูล"
        ],
        "reports_hours": [
            "en": "Hours",
            "th": "ชั่วโมง"
        ],
        "reports_regular_hours": [
            "en": "Regular Hours",
            "th": "ชั่วโมงทำงานปกติ"
        ],
        "reports_overtime_hours": [
            "en": "Overtime Hours",
            "th": "ชั่วโมงล่วงเวลา (OT)"
        ],
        "reports_employee_detail": [
            "en": "Employee Breakdown",
            "th": "รายละเอียดข้อมูลพนักงาน"
        ],
        "reports_employee": [
            "en": "Employee",
            "th": "พนักงาน"
        ],
        "reports_type": [
            "en": "Type",
            "th": "ประเภท"
        ],
        "reports_total_hours": [
            "en": "Total Hours",
            "th": "ชั่วโมงรวม"
        ],
        "reports_breaks": [
            "en": "Breaks (Min)",
            "th": "เวลาพัก (นาที)"
        ],
        "reports_rate": [
            "en": "Hourly Rate",
            "th": "อัตราต่อชั่วโมง"
        ],
        "reports_est_cost": [
            "en": "Est. Cost",
            "th": "ประมาณการต้นทุน"
        ],
        "reports_total": [
            "en": "Total",
            "th": "ยอดรวม"
        ],
        "reports_hourly": [
            "en": "Hourly",
            "th": "รายชั่วโมง"
        ],
        "reports_daily": [
            "en": "Daily",
            "th": "รายวัน"
        ],
        "reports_monthly": [
            "en": "Monthly",
            "th": "รายเดือน"
        ],
        "reports_sales_inc_vat": [
            "en": "Sales (Incl. VAT)",
            "th": "ยอดขายรวม VAT"
        ],
        "reports_vat_amount": [
            "en": "VAT Amount (7%)",
            "th": "จำนวนภาษีมูลค่าเพิ่ม (7%)"
        ],
        "reports_sales_exc_vat": [
            "en": "Sales (Excl. VAT)",
            "th": "ยอดขายสุทธิ (แยก VAT)"
        ],
        "reports_daily_vat_breakdown": [
            "en": "Daily VAT Breakdown",
            "th": "สรุปภาษีมูลค่าเพิ่มรายวัน"
        ],
        "reports_detailed_breakdown": [
            "en": "Detailed Breakdown",
            "th": "ตารางรายละเอียดภาษี"
        ],
        "reports_date": [
            "en": "Date",
            "th": "วันที่"
        ],
        "reports_orders": [
            "en": "Orders",
            "th": "ออเดอร์"
        ],
        "reports_gross_revenue": [
            "en": "Gross Revenue",
            "th": "ยอดขายรวม"
        ],
        "reports_net_revenue": [
            "en": "Net Revenue",
            "th": "ยอดขายสุทธิ"
        ],
        "reports_total_discount": [
            "en": "Total Discounts",
            "th": "ส่วนลดรวม"
        ],
        "reports_total_refunds": [
            "en": "Total Refunds",
            "th": "ยอดคืนเงินรวม"
        ],
        "reports_payment_methods": [
            "en": "Payment Methods",
            "th": "ช่องทางชำระเงิน"
        ],
        "reports_peak_hour": [
            "en": "Peak Hour",
            "th": "ช่วงเวลาขายดีที่สุด"
        ],
        "reports_hourly_sales": [
            "en": "Hourly Sales Distribution",
            "th": "ยอดขายตามช่วงเวลา"
        ],
        "reports_payment_breakdown": [
            "en": "Payment Breakdown",
            "th": "สัดส่วนการชำระเงิน"
        ],
        "reports_method_cash": [
            "en": "Cash",
            "th": "เงินสด"
        ],
        "reports_method_card": [
            "en": "Credit Card",
            "th": "บัตรเครดิต"
        ],
        "reports_method_qr": [
            "en": "QR PromptPay",
            "th": "คิวอาร์พร้อมเพย์"
        ],
        "reports_avg_ticket": [
            "en": "Avg. Order Value",
            "th": "ยอดขายต่อออเดอร์เฉลี่ย"
        ],
        "reports_total_orders": [
            "en": "Total Orders",
            "th": "ออเดอร์รวม"
        ],
        "reports_total_stock_value": [
            "en": "Total Inventory Value",
            "th": "มูลค่าสินค้าคงคลังรวม"
        ],
        "reports_low_stock_count": [
            "en": "Low Stock Items",
            "th": "สินค้าใกล้หมด"
        ],
        "reports_out_of_stock_count": [
            "en": "Out of Stock Items",
            "th": "สินค้าหมดคลัง"
        ],
        "reports_waste_cost": [
            "en": "Waste Cost",
            "th": "ต้นทุนสินค้าสูญเสีย/ทิ้ง"
        ],
        "reports_out_of_stock": [
            "en": "Out of Stock Summary",
            "th": "สรุปสินค้าที่หมด"
        ],
        "reports_reorder_level": [
            "en": "Reorder Level",
            "th": "จุดสั่งซื้อใหม่"
        ],
        "reports_out_of_stock_badge": [
            "en": "OUT OF STOCK",
            "th": "สินค้าหมด"
        ],
        "reports_low_stock": [
            "en": "Low Stock Warnings",
            "th": "เตือนสินค้าเหลือน้อย"
        ],
        "reports_no_low_stock": [
            "en": "All items are in healthy stock levels.",
            "th": "ระดับสินค้าทุกรายการปกติดี"
        ],
        "reports_waste_and_spoilage": [
            "en": "Waste & Spoilage Log",
            "th": "บันทึกของเสียและสปอยล์"
        ],
        "reports_total_waste": [
            "en": "Total Waste Cost",
            "th": "ต้นทุนเสียหายรวม"
        ],
        "reports_no_waste": [
            "en": "No waste records logged for this period.",
            "th": "ไม่มีบันทึกของเสียหายในรอบนี้"
        ],
        "reports_item_name": [
            "en": "Item Name",
            "th": "ชื่อสินค้า"
        ],
        "reports_quantity": [
            "en": "Qty",
            "th": "จำนวน"
        ],
        "reports_cost": [
            "en": "Unit Cost",
            "th": "ราคาทุน"
        ],
        "reports_notes": [
            "en": "Notes",
            "th": "หมายเหตุ"
        ],
        "reports_total_items": [
            "en": "Total Menu Items Sold",
            "th": "จำนวนเมนูที่ขายได้รวม"
        ],
        "reports_total_revenue": [
            "en": "Total Menu Revenue",
            "th": "รายได้รวมจากเมนู"
        ],
        "reports_total_cogs": [
            "en": "Total COGS",
            "th": "ต้นทุนวัตถุดิบรวม (COGS)"
        ],
        "reports_avg_margin": [
            "en": "Avg. Profit Margin",
            "th": "มาร์จินกำไรเฉลี่ย"
        ],
        "reports_top_profitable": [
            "en": "Top Profitable Items",
            "th": "เมนูที่ทำกำไรสูงสุด"
        ],
        "reports_least_profitable": [
            "en": "Least Profitable Items",
            "th": "เมนูที่ทำกำไรต่ำสุด"
        ],
        "reports_menu_item_breakdown": [
            "en": "Menu Item Profitability Detail",
            "th": "รายละเอียดกำไรแยกตามเมนู"
        ],
        "reports_qty_sold": [
            "en": "Qty Sold",
            "th": "จำนวนที่ขาย"
        ],
        "reports_revenue": [
            "en": "Revenue",
            "th": "รายได้"
        ],
        "reports_cogs": [
            "en": "COGS",
            "th": "ต้นทุน COGS"
        ],
        "reports_profit": [
            "en": "Profit",
            "th": "กำไร"
        ],
        "reports_margin": [
            "en": "Margin %",
            "th": "กำไร %"
        ],
        "reports_title": [
            "en": "Store Reports & Analytics",
            "th": "รายงานและวิเคราะห์ข้อมูลร้าน"
        ],
        "reports_select_report": [
            "en": "Select a report from the menu to get started.",
            "th": "กรุณาเลือกรายงานจากเมนูด้านซ้าย"
        ],
        "reports_period": [
            "en": "Reporting Period",
            "th": "ช่วงเวลาของรายงาน"
        ],
        "reports_period_daily": [
            "en": "Daily (Selected Date)",
            "th": "รายวัน (วันที่เลือก)"
        ],
        "reports_period_weekly": [
            "en": "Weekly (Last 7 Days)",
            "th": "รายสัปดาห์ (ย้อนหลัง 7 วัน)"
        ],
        "reports_period_monthly": [
            "en": "Monthly (Selected Month)",
            "th": "รายเดือน (เดือนที่เลือก)"
        ],
        "reports_period_custom": [
            "en": "Custom Date Range",
            "th": "ระบุช่วงเวลาเอง"
        ],
        "reports_start_date": [
            "en": "Start Date",
            "th": "วันที่เริ่มต้น"
        ],
        "reports_end_date": [
            "en": "End Date",
            "th": "วันที่สิ้นสุด"
        ],
        "reports_export_pdf": [
            "en": "Export PDF Report",
            "th": "ส่งออกรายงานเป็น PDF"
        ],
        "reports_daily_sales": [
            "en": "Daily Sales & Payment",
            "th": "ยอดขายประจำวันและช่องทาง"
        ],
        "reports_z_report": [
            "en": "Z-Report (Cash Session)",
            "th": "รายงานการปิดยอดเงินสด (Z-Report)"
        ],
        "reports_tax_vat": [
            "en": "Tax & VAT Summary",
            "th": "รายงานภาษีมูลค่าเพิ่ม (VAT)"
        ],
        "reports_menu_profit": [
            "en": "Menu & Profitability Analysis",
            "th": "วิเคราะห์เมนูและการทำกำไร"
        ],
        "reports_inventory": [
            "en": "Inventory & Waste Tracking",
            "th": "รายงานสินค้าคงคลังและของเสีย"
        ],
        "reports_employee_hours": [
            "en": "Labor Hours & Payroll Costs",
            "th": "ชั่วโมงทำงานและต้นทุนพนักงาน"
        ],"""

content = content[:dict_start] + reports_translations_str + content[dict_start:]

with open(filepath, "w", encoding="utf-8") as f:
    f.write(content)

print("Successfully injected Reports enums and translations into AppLocalization.swift!")
