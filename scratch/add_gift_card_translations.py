# -*- coding: utf-8 -*-
import sys

file_path = "/Users/mac/Documents/AlphaPos/AlphaPos/Core/Localization/AppLocalization.swift"

with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

target_str = """        "print_z_report_btn": [
            "en": "Print Simulation Z-Report",
            "th": "พิมพ์รายงาน Z-Report"
        ],"""

if target_str not in content:
    print("Error: target block not found in AppLocalization.swift")
    sys.exit(1)

new_translations = """
        // ── Gift Cards Extra translations ──
        "gift_cards_title": [
            "en": "Gift Cards",
            "th": "บัตรของขวัญ"
        ],
        "top_up_gift_card_title": [
            "en": "Top Up Gift Card",
            "th": "เติมเงินบัตรของขวัญ"
        ],
        "add_balance_btn": [
            "en": "Add Balance",
            "th": "เพิ่มเงิน"
        ],
        "redeem_gift_card_title": [
            "en": "Redeem Gift Card",
            "th": "ใช้บัตรของขวัญ"
        ],
        "redeem_btn": [
            "en": "Redeem",
            "th": "ตัดยอด/ชำระ"
        ],
        "void_gift_card_alert_title": [
            "en": "Void Gift Card?",
            "th": "ยกเลิกบัตรของขวัญหรือไม่?"
        ],
        "void_gift_card_alert_message": [
            "en": "This disables the card and removes any remaining usable balance.",
            "th": "การดำเนินการนี้จะระงับการใช้งานบัตรและลบยอดเงินคงเหลือทั้งหมด"
        ],
        "void_btn": [
            "en": "Void",
            "th": "ระงับบัตร"
        ],
        "outstanding_label": [
            "en": "Outstanding",
            "th": "ยอดค้างชำระสะสม"
        ],
        "active_cards_label": [
            "en": "Active Cards",
            "th": "บัตรใช้งานอยู่"
        ],
        "disabled_label": [
            "en": "Disabled",
            "th": "ระงับชั่วคราว"
        ],
        "issue_card_btn": [
            "en": "Issue Card",
            "th": "ออกบัตรใหม่"
        ],
        "lookup_card_placeholder": [
            "en": "Lookup card number, customer, phone...",
            "th": "ค้นหาเลขบัตร, ชื่อลูกค้า, เบอร์โทร..."
        ],
        "no_gift_cards": [
            "en": "No Gift Cards",
            "th": "ไม่มีข้อมูลบัตรของขวัญ"
        ],
        "unassigned": [
            "en": "Unassigned",
            "th": "ยังไม่ได้ระบุ"
        ],
        "no_linked_customer": [
            "en": "No linked customer",
            "th": "ไม่ได้ผูกกับสมาชิก"
        ],
        "balance_label": [
            "en": "Balance",
            "th": "ยอดเงินคงเหลือ"
        ],
        "initial_value_label": [
            "en": "Initial",
            "th": "มูลค่าตั้งต้น"
        ],
        "status_label": [
            "en": "Status",
            "th": "สถานะ"
        ],
        "actions_header": [
            "en": "ACTIONS",
            "th": "การดำเนินการ"
        ],
        "top_up_btn": [
            "en": "Top Up",
            "th": "เติมเงิน"
        ],
        "details_header": [
            "en": "DETAILS",
            "th": "รายละเอียดเพิ่มเติม"
        ],
        "updated_label": [
            "en": "Updated",
            "th": "ปรับปรุงล่าสุด"
        ],
        "expiry_label": [
            "en": "Expiry",
            "th": "วันหมดอายุ"
        ],
        "no_expiry_label": [
            "en": "No expiry",
            "th": "ไม่มีวันหมดอายุ"
        ],
        "customer_phone_label": [
            "en": "Customer Phone",
            "th": "เบอร์โทรศัพท์ลูกค้า"
        ],
        "select_gift_card_prompt": [
            "en": "Select a Gift Card",
            "th": "กรุณาเลือกบัตรของขวัญด้านซ้าย"
        ],
        "card_section": [
            "en": "Card",
            "th": "ข้อมูลบัตร"
        ],
        "card_number_placeholder": [
            "en": "Card number",
            "th": "หมายเลขบัตรของขวัญ"
        ],
        "initial_value_placeholder": [
            "en": "Initial value",
            "th": "มูลค่าเงินตั้งต้น"
        ],
        "set_expiry_date_toggle": [
            "en": "Set expiry date",
            "th": "กำหนดวันหมดอายุบัตร"
        ],
        "expires_label": [
            "en": "Expires",
            "th": "วันหมดอายุ"
        ],
        "customer_section": [
            "en": "Customer",
            "th": "ข้อมูลลูกค้า"
        ],
        "linked_customer_label": [
            "en": "Linked customer",
            "th": "ผูกกับสมาชิก"
        ],
        "issue_gift_card_title": [
            "en": "Issue Gift Card",
            "th": "ออกบัตรของขวัญใหม่"
        ],
        "issue_btn": [
            "en": "Issue",
            "th": "ออกบัตร"
        ],
        "amount_placeholder": [
            "en": "Amount",
            "th": "จำนวนเงิน"
        ],
        "note_placeholder": [
            "en": "Note",
            "th": "หมายเหตุ"
        ],
        "available_balance_template": [
            "en": "Available balance: ฿%.2f",
            "th": "ยอดเงินที่ใช้ได้: ฿%.2f"
        ],
"""

replaced_content = content.replace(target_str, target_str + new_translations)

with open(file_path, "w", encoding="utf-8") as f:
    f.write(replaced_content)

print("Gift Card translations successfully added!")
