# -*- coding: utf-8 -*-
import sys

file_path = "/Users/mac/Documents/AlphaPos/AlphaPos/Core/Localization/AppLocalization.swift"

with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

target_str = """        "receipt_sent_to_printer": [
            "en": "Receipt sent to printer.",
            "th": "ส่งคำสั่งพิมพ์ใบเสร็จแล้ว"
        ],"""

if target_str not in content:
    print("Error: target block not found in AppLocalization.swift")
    sys.exit(1)

new_translations = """
        // ── Cash Drawer Extra translations ──
        "cash_drawer_shifts_title": [
            "en": "Cash Drawer & Shifts",
            "th": "ลิ้นชักเก็บเงิน & กะทำงาน"
        ],
        "drawer_locked_title": [
            "en": "Cash Drawer is Locked",
            "th": "ลิ้นชักเก็บเงินถูกล็อคอยู่"
        ],
        "drawer_locked_subtitle": [
            "en": "An active shift register session must be opened before processing cash sales or checkout orders.",
            "th": "ต้องเปิดกะ (Register Session) ลิ้นชักเก็บเงินก่อน จึงจะทำรายการขายหรือรับชำระเงินได้"
        ],
        "start_shift_header": [
            "en": "START A NEW SHIFT REGISTER",
            "th": "เริ่มเปิดกะทำงานใหม่"
        ],
        "starting_cash_float_label": [
            "en": "Starting Cash Float / เงินทอนเริ่มต้น",
            "th": "เงินทอนเริ่มต้นสต็อก"
        ],
        "opening_notes_label": [
            "en": "Opening Notes / บันทึกเพิ่มเติม",
            "th": "บันทึกเพิ่มเติมตอนเปิดกะ"
        ],
        "opening_notes_placeholder": [
            "en": "e.g. Morning Shift A",
            "th": "เช่น กะเช้า A"
        ],
        "open_session_btn": [
            "en": "Open Register Session & Start Shift",
            "th": "เปิดลิ้นชักเงินสด & เริ่มทำงาน"
        ],
        "shift_running_title": [
            "en": "Active Shift Running",
            "th": "กะทำงานกำลังทำงานอยู่"
        ],
        "opened_at_template": [
            "en": "Opened at %@",
            "th": "เปิดกะเมื่อ %@"
        ],
        "end_shift_btn": [
            "en": "End Shift & Close Drawer",
            "th": "ปิดกะทำงาน & ปิดลิ้นชัก"
        ],
        "starting_float_label": [
            "en": "STARTING FLOAT",
            "th": "เงินทอนเริ่มต้น"
        ],
        "cash_sales_label": [
            "en": "CASH SALES (+)",
            "th": "ยอดขายเงินสด (+)"
        ],
        "cash_in_label": [
            "en": "CASH IN (+)",
            "th": "เงินสดเข้า (+)"
        ],
        "cash_out_label": [
            "en": "CASH OUT (-)",
            "th": "เงินสดออก (-)"
        ],
        "cash_float_sub": [
            "en": "Cash float",
            "th": "เงินทอนตั้งต้น"
        ],
        "completed_orders_sub": [
            "en": "Completed orders",
            "th": "รายการที่สำเร็จ"
        ],
        "paid_in_sub": [
            "en": "Paid-in movements",
            "th": "รายการนำฝากเงินสด"
        ],
        "paid_out_sub": [
            "en": "Paid-out movements",
            "th": "รายการถอนเงินสด"
        ],
        "expected_cash_drawer": [
            "en": "EXPECTED CASH IN DRAWER",
            "th": "ยอดเงินสดที่ควรมีในลิ้นชัก"
        ],
        "cash_movements_log": [
            "en": "CASH MOVEMENTS LOG",
            "th": "บันทึกประวัติความเคลื่อนไหวเงินสด"
        ],
        "add_paid_in_out": [
            "en": "Add Paid In/Out",
            "th": "เพิ่มรายการ นำฝาก/ถอน เงิน"
        ],
        "no_manual_movements": [
            "en": "No manual cash inputs or payouts logged in this shift.",
            "th": "ไม่มีประวัติการนำฝากหรือถอนเงินสดในกะนี้"
        ],
        "paid_in": [
            "en": "Paid In",
            "th": "ฝากเงินสด"
        ],
        "paid_out": [
            "en": "Paid Out",
            "th": "ถอนเงินสด"
        ],
        "transaction_details_section": [
            "en": "Transaction Details",
            "th": "รายละเอียดธุรกรรม"
        ],
        "movement_type_label": [
            "en": "Movement Type",
            "th": "ประเภทรายการ"
        ],
        "paid_in_add_cash": [
            "en": "Paid In (Add Cash)",
            "th": "ฝากเงิน (เพิ่มเงินเข้าลิ้นชัก)"
        ],
        "paid_out_withdraw_cash": [
            "en": "Paid Out (Withdraw Cash)",
            "th": "ถอนเงิน (นำเงินสดออกจากลิ้นชัก)"
        ],
        "amount_baht": [
            "en": "Amount (฿)",
            "th": "จำนวนเงิน (฿)"
        ],
        "reason_description_placeholder": [
            "en": "Reason / Description",
            "th": "เหตุผล / บันทึกอธิบาย"
        ],
        "add_cash_movement_title": [
            "en": "Add Cash Movement",
            "th": "เพิ่มรายการเคลื่อนไหวเงินสด"
        ],
        "expected_calculated_balance": [
            "en": "EXPECTED CALCULATED BALANCE",
            "th": "ยอดเงินที่ระบบคำนวณ"
        ],
        "physical_cash_count": [
            "en": "PHYSICAL CASH COUNT",
            "th": "นับยอดเงินสดจริง"
        ],
        "actual_cash_counted_label": [
            "en": "Actual Cash Counted (฿)",
            "th": "นับเงินสดได้จริง (฿)"
        ],
        "discrepancy_label": [
            "en": "Discrepancy / ส่วนต่าง",
            "th": "ผลต่างเงินสด"
        ],
        "balanced_option": [
            "en": "฿0.00 (Balanced)",
            "th": "฿0.00 (ยอดตรงกันพอดี)"
        ],
        "overage_label": [
            "en": "Overage",
            "th": "เงินเกิน"
        ],
        "shortage_label": [
            "en": "Shortage",
            "th": "เงินขาด"
        ],
        "closing_notes_label": [
            "en": "Closing Notes / บันทึกการปิดยอดกะ",
            "th": "บันทึกสรุปยอดปิดกะ"
        ],
        "shift_reconciliation_title": [
            "en": "Shift Reconciliation",
            "th": "เปรียบเทียบยอดปิดกะทำงาน"
        ],
        "close_register_btn": [
            "en": "Close Register",
            "th": "ปิดลิ้นชัก & จบกะ"
        ],
        "z_report_header": [
            "en": "Z-REPORT (SHIFT SUMMARY)",
            "th": "รายงานการปิดกะ (Z-REPORT)"
        ],
        "z_report_title": [
            "en": "AlphaPos Z-Report",
            "th": "AlphaPos รายงานปิดกะ (Z-Report)"
        ],
        "shift_id_label": [
            "en": "Shift ID:",
            "th": "รหัสกะทำงาน:"
        ],
        "opened_at_label": [
            "en": "Opened At:",
            "th": "เวลาเริ่มกะ:"
        ],
        "closed_at_label": [
            "en": "Closed At:",
            "th": "เวลาปิดกะ:"
        ],
        "opening_float_label": [
            "en": "Opening Float:",
            "th": "เงินทอนเริ่มต้น:"
        ],
        "cash_sales_label_colon": [
            "en": "Cash Sales (+):",
            "th": "ยอดขายเงินสด (+):"
        ],
        "cash_in_label_colon": [
            "en": "Cash In (+):",
            "th": "นำฝากเงินสด (+):"
        ],
        "cash_out_label_colon": [
            "en": "Cash Out (-):",
            "th": "ถอนเงินสด (-):"
        ],
        "expected_cash_label": [
            "en": "Expected Cash:",
            "th": "เงินสดที่ควรมี:"
        ],
        "actual_cash_counted_label_colon": [
            "en": "Actual Cash Counted:",
            "th": "นับได้จริง:"
        ],
        "discrepancy_label_colon": [
            "en": "Discrepancy:",
            "th": "ส่วนต่าง:"
        ],
        "print_z_report_btn": [
            "en": "Print Simulation Z-Report",
            "th": "พิมพ์รายงาน Z-Report"
        ],
"""

replaced_content = content.replace(target_str, target_str + new_translations)

with open(file_path, "w", encoding="utf-8") as f:
    f.write(replaced_content)

print("Cash drawer translations successfully added!")
