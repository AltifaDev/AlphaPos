# -*- coding: utf-8 -*-
import sys

file_path = "/Users/mac/Documents/AlphaPos/AlphaPos/Core/Localization/AppLocalization.swift"

with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

target_str = """        "pos_category_all": [
            "en": "All",
            "th": "ทั้งหมด",
            "zh": "全部",
            "ja": "すべて",
            "ko": "전체",
            "id": "Semua",
            "ms": "Semua"
        ],"""

if target_str not in content:
    print("Error: target block not found in AppLocalization.swift")
    sys.exit(1)

new_translations = """
        // ── POS View Extra translations ──
        "pos_refund": [
            "en": "Refund",
            "th": "คืนเงิน"
        ],
        "pos_all_items": [
            "en": "All Items",
            "th": "สินค้าทั้งหมด"
        ],
        "pos_favorites": [
            "en": "Favorites",
            "th": "รายการโปรด"
        ],
        "pos_current_cart": [
            "en": "Current Cart",
            "th": "ตะกร้าปัจจุบัน"
        ],
        "pos_dine_in": [
            "en": "Dine-In",
            "th": "ทานที่ร้าน"
        ],
        "pos_take_out": [
            "en": "Take-Out",
            "th": "กลับบ้าน"
        ],
        "pos_delivery": [
            "en": "Delivery",
            "th": "จัดส่ง"
        ],
        "pos_hold": [
            "en": "Hold",
            "th": "พัก"
        ],
        "pos_clear": [
            "en": "Clear",
            "th": "ล้าง"
        ],
        "pos_recall": [
            "en": "Recall",
            "th": "เรียกคืน"
        ],
        "configure_fees_template": [
            "en": "Configure %@ Fees",
            "th": "ตั้งค่าค่าบริการของ %@"
        ],
        "pos_bill_no": [
            "en": "BILL NO",
            "th": "เลขที่บิล"
        ],
        "table_number_template": [
            "en": "Table %@",
            "th": "โต๊ะ %@"
        ],
        "pax_count_template": [
            "en": "%d Pax",
            "th": "%d ท่าน"
        ],
        "pos_cashier": [
            "en": "CASHIER",
            "th": "พนักงานขาย"
        ],
        "customer_membership_points_template": [
            "en": "%@ • %d pts",
            "th": "%@ • %d คะแนน"
        ],
        "pos_ready_for_payment": [
            "en": "Ready for Payment",
            "th": "เสิร์ฟครบแล้ว พร้อมชำระเงิน"
        ],
        "pos_out_of_stock": [
            "en": "Out of Stock",
            "th": "สินค้าหมด"
        ],
        "pos_pending_confirmation": [
            "en": "Pending KDS Confirmation",
            "th": "รอยืนยันครัว"
        ],
        "note_label_template": [
            "en": "Note: %@",
            "th": "หมายเหตุ: %@"
        ],
        "pos_served": [
            "en": "Served",
            "th": "เสิร์ฟแล้ว"
        ],
        "pos_subtotal": [
            "en": "Subtotal",
            "th": "ยอดรวมก่อนลด"
        ],
        "pos_discount": [
            "en": "Discount",
            "th": "ส่วนลด"
        ],
        "pos_service_charge": [
            "en": "Service Charge",
            "th": "ค่าบริการ"
        ],
        "pos_vat": [
            "en": "VAT",
            "th": "ภาษีมูลค่าเพิ่ม"
        ],
        "pos_total": [
            "en": "Total",
            "th": "ยอดรวมสุทธิ"
        ],
        "pos_cash": [
            "en": "Cash",
            "th": "เงินสด"
        ],
        "pos_qr_code": [
            "en": "QR Code",
            "th": "สแกน QR"
        ],
        "pos_card": [
            "en": "Card",
            "th": "บัตรเครดิต"
        ],
        "pos_split_pay": [
            "en": "Split Pay",
            "th": "แยกจ่าย"
        ],
        "pos_total_amount": [
            "en": "Total Amount",
            "th": "ยอดรวมชำระ"
        ],
        "pos_quick_cash": [
            "en": "Quick Cash",
            "th": "ปุ่มเงินสดด่วน"
        ],
        "pos_change_due": [
            "en": "Change Due",
            "th": "เงินทอน"
        ],
        "pos_amount_missing": [
            "en": "Amount Missing",
            "th": "ยอดขาด"
        ],
        "pos_payment_successful": [
            "en": "Payment Successful",
            "th": "ชำระเงินสำเร็จ"
        ],
        "received_cash_template": [
            "en": "Received Cash: ฿%.2f",
            "th": "รับเงินสด: ฿%.2f"
        ],
        "pos_no_change_due": [
            "en": "No Change Due",
            "th": "ไม่มีเงินทอน"
        ],
        "pos_instructions_hint": [
            "en": "Add special instructions for this item.",
            "th": "เพิ่มคำแนะนำพิเศษสำหรับรายการนี้"
        ],
        "pos_shift_required_hint": [
            "en": "You must open an active cash drawer register session and enter starting float money before completing any checkout payments.",
            "th": "คุณต้องเปิดกะ (Register Session) และกำหนดเงินทอนเริ่มต้นก่อน จึงจะรับชำระเงินได้"
        ],
        "pos_no_menu_items_title": [
            "en": "No Menu Items Yet",
            "th": "ยังไม่มีรายการเมนูอาหาร"
        ],
        "pos_no_menu_items_subtitle": [
            "en": "Seed the database with sample menu items to get started.",
            "th": "คลิกปุ่มเพื่อจำลองรายการอาหารเริ่มต้นในระบบ"
        ],
        "pos_select_table_title": [
            "en": "Select a Table to Begin",
            "th": "กรุณาเลือกโต๊ะอาหารก่อนสั่งซื้อ"
        ],
        "pos_select_table_subtitle": [
            "en": "The Dining Table System is active. You must select an active table session to place an order.",
            "th": "ระบบจัดการโต๊ะเปิดใช้งานอยู่ กรุณาเลือกโต๊ะเพื่อเริ่มรายการสั่งซื้อ"
        ],
"""

replaced_content = content.replace(target_str, target_str + new_translations)

with open(file_path, "w", encoding="utf-8") as f:
    f.write(replaced_content)

print("POS translations successfully added!")
