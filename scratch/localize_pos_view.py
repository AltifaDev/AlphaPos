# -*- coding: utf-8 -*-
import sys

file_path = "/Users/mac/Documents/AlphaPos/AlphaPos/Features/POS/Views/POSView.swift"

with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# Add EnvironmentObject
if "@EnvironmentObject private var lm: LocalizationManager" not in content:
    content = content.replace(
        "    @Environment(\.modelContext) private var modelContext",
        "    @Environment(\.modelContext) private var modelContext\n    @EnvironmentObject private var lm: LocalizationManager"
    )

subs = [
    # Top tab buttons
    ('Text("Tables")', 'Text("tab_tables".t)'),
    ('Text("Refund")', 'Text("pos_refund".t)'),
    ('Text("All Items")', 'Text("pos_all_items".t)'),
    ('Text("Favorites")', 'Text("pos_favorites".t)'),

    # Cart Panel Header
    ('Text("Current Cart")', 'Text("pos_current_cart".t)'),
    ('Text("\\(viewModel.cart.count) items")', 'Text(LocalizationManager.shared.t("items_count_template", viewModel.cart.count))'),

    # Dine-In / Take-Out / Delivery
    ('Text("Dine-In")', 'Text("pos_dine_in".t)'),
    ('Text("Take-Out")', 'Text("pos_take_out".t)'),
    ('Text("Delivery")', 'Text("pos_delivery".t)'),

    # Hold / Clear / Recall
    ('Text("Hold")', 'Text("pos_hold".t)'),
    ('Text("Clear")', 'Text("pos_clear".t)'),
    ('Text("Recall")', 'Text("pos_recall".t)'),

    # Delivery brand fee template
    ('Text("Configure \\(viewModel.deliveryBrand ?? "Platform") Fees")', 'Text(LocalizationManager.shared.t("configure_fees_template", viewModel.deliveryBrand ?? "Platform"))'),

    # Bill Info
    ('Text("BILL NO")', 'Text("pos_bill_no".t)'),
    ('Text("Table \\(session.table?.tableNumber ?? "N/A")")', 'Text(LocalizationManager.shared.t("table_number_template", session.table?.tableNumber ?? "N/A"))'),
    ('Text("\\(viewModel.guestCount) Pax")', 'Text(LocalizationManager.shared.t("pax_count_template", viewModel.guestCount))'),
    ('Text("CASHIER")', 'Text("pos_cashier".t)'),
    ('Text("\\(customer.membershipTier.uppercased()) • \\(customer.loyaltyPoints) pts")', 'Text(LocalizationManager.shared.t("customer_membership_points_template", customer.membershipTier.uppercased(), customer.loyaltyPoints))'),

    # Cart Empty / Out of Stock
    ('Text("เสิร์ฟครบแล้ว พร้อมชำระเงิน (Ready for Payment)")', 'Text("pos_ready_for_payment".t)'),
    ('Text("Cart is empty")', 'Text("pos_cart_empty".t)'),
    ('Text("ของหมด")', 'Text("pos_out_of_stock".t)'),
    ('Text("รอยืนยัน")', 'Text("pos_pending_confirmation".t)'),
    ('Text("Note: \\(cartItem.notes)")', 'Text(LocalizationManager.shared.t("note_label_template", cartItem.notes))'),
    ('Text("Note: \\(groupedItem.notes)")', 'Text(LocalizationManager.shared.t("note_label_template", groupedItem.notes))'),
    ('Text("เสิร์ฟแล้ว")', 'Text("pos_served".t)'),

    # Financial breakdown
    ('financeRow(label: "Subtotal", value: displaySubtotal)', 'financeRow(label: "pos_subtotal".t, value: displaySubtotal)'),
    ('financeRow(label: "VAT 7%", value: displayTax)', 'financeRow(label: "pos_vat".t + " 7%", value: displayTax)'),
    ('financeRow(label: "Service 10%", value: displayServiceCharge)', 'financeRow(label: "pos_service_charge".t + " 10%", value: displayServiceCharge)'),
    ('financeRow(label: "Promotion", value: -displayDiscount)', 'financeRow(label: "pos_discount".t, value: -displayDiscount)'),
    ('Text("Total")', 'Text("pos_total".t)'),

    # Checkout payment methods
    ('Text("Cash")', 'Text("pos_cash".t)'),
    ('Text("QR Code")', 'Text("pos_qr_code".t)'),
    ('Text("Card")', 'Text("pos_card".t)'),
    ('Text("Split Pay")', 'Text("pos_split_pay".t)'),

    # Payment panel overlays
    ('Text("Total Amount")', 'Text("pos_total_amount".t)'),
    ('Text("Quick Cash")', 'Text("pos_quick_cash".t)'),
    ('Text("Change Due")', 'Text("pos_change_due".t)'),
    ('Text("Amount Missing")', 'Text("pos_amount_missing".t)'),
    ('Text("Payment Successful")', 'Text("pos_payment_successful".t)'),
    ('Text("Received Cash: ฿\\(String(format: "%.2f", cashReceived))")', 'Text(LocalizationManager.shared.t("received_cash_template", cashReceived))'),
    ('Text("No Change Due")', 'Text("pos_no_change_due".t)'),

    # Alert/State labels
    ('Text("Add special instructions for this item.")', 'Text("pos_instructions_hint".t)'),
    ('Text("You must open an active cash drawer register session and enter starting float money before completing any checkout payments.")', 'Text("pos_shift_required_hint".t)'),
    ('Text("No Menu Items Yet")', 'Text("pos_no_menu_items_title".t)'),
    ('Text("Seed the database with sample menu items to get started.")', 'Text("pos_no_menu_items_subtitle".t)'),
    ('Text("Select a Table to Begin")', 'Text("pos_select_table_title".t)'),
    ('Text("The Dining Table System is active. You must select an active table session to place an order.")', 'Text("pos_select_table_subtitle".t)'),
]

for old_str, new_str in subs:
    content = content.replace(old_str, new_str)

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)

print("POSView localized successfully!")
