# -*- coding: utf-8 -*-
import sys

file_path = "/Users/mac/Documents/AlphaPos/AlphaPos/Core/Localization/AppLocalization.swift"

with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

target_str = """        "pos_select_table_subtitle": [
            "en": "The Dining Table System is active. You must select an active table session to place an order.",
            "th": "ระบบจัดการโต๊ะเปิดใช้งานอยู่ กรุณาเลือกโต๊ะเพื่อเริ่มรายการสั่งซื้อ"
        ],"""

if target_str not in content:
    print("Error: target block not found in AppLocalization.swift")
    sys.exit(1)

new_translations = """
        // ── Receipt View translations ──
        "receipt_header_default": [
            "en": "Thank you for dining with us!",
            "th": "ขอบคุณที่ใช้บริการ!"
        ],
        "receipt_footer_default": [
            "en": "See you again soon! • www.alphapos.app",
            "th": "แล้วพบกันใหม่โอกาสหน้า! • www.alphapos.app"
        ],
        "receipt_label": [
            "en": "Receipt",
            "th": "ใบเสร็จรับเงิน"
        ],
        "date_label": [
            "en": "Date",
            "th": "วันที่"
        ],
        "time_label": [
            "en": "Time",
            "th": "เวลา"
        ],
        "cashier_label": [
            "en": "Cashier",
            "th": "พนักงานขาย"
        ],
        "table_label": [
            "en": "Table",
            "th": "โต๊ะ"
        ],
        "payment_label": [
            "en": "Payment",
            "th": "การชำระเงิน"
        ],
        "powered_by_alphapos": [
            "en": "Powered by AlphaPos",
            "th": "ให้บริการโดย AlphaPos"
        ],
        "receipt_title": [
            "en": "Receipt",
            "th": "ใบเสร็จ"
        ],
        "close_btn": [
            "en": "Close",
            "th": "ปิด"
        ],
        "ok_btn": [
            "en": "OK",
            "th": "ตกลง"
        ],
        "receipt_no_label": [
            "en": "Receipt #",
            "th": "เลขที่ใบเสร็จ"
        ],
        "type_label": [
            "en": "Type",
            "th": "ประเภทบริการ"
        ],
        "qty_header": [
            "en": "QTY",
            "th": "จำนวน"
        ],
        "item_header": [
            "en": "ITEM",
            "th": "รายการ"
        ],
        "amount_header": [
            "en": "AMOUNT",
            "th": "มูลค่า"
        ],
        "pos_tip": [
            "en": "Tip",
            "th": "ทิป"
        ],
        "paid_via_label": [
            "en": "Paid via",
            "th": "ชำระด้วย"
        ],
        "tendered_label": [
            "en": "Tendered",
            "th": "จำนวนเงินที่ชำระ"
        ],
        "scan_digital_receipt": [
            "en": "Scan for digital receipt",
            "th": "สแกนเพื่อรับใบเสร็จดิจิทัล"
        ],
        "print_btn": [
            "en": "Print",
            "th": "พิมพ์ใบเสร็จ"
        ],
        "email_btn": [
            "en": "Email",
            "th": "ส่งอีเมล"
        ],
        "receipt_sent_to_printer": [
            "en": "Receipt sent to printer.",
            "th": "ส่งคำสั่งพิมพ์ใบเสร็จแล้ว"
        ],
"""

replaced_content = content.replace(target_str, target_str + new_translations)

with open(file_path, "w", encoding="utf-8") as f:
    f.write(replaced_content)

print("Receipt translations successfully added!")
