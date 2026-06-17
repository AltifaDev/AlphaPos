# -*- coding: utf-8 -*-
import sys

file_path = "/Users/mac/Documents/AlphaPos/AlphaPos/Features/POS/Views/GiftCardManagementView.swift"

with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# Add EnvironmentObject
if "@EnvironmentObject private var lm: LocalizationManager" not in content:
    content = content.replace(
        "    @Environment(\.modelContext) private var modelContext",
        "    @Environment(\.modelContext) private var modelContext\n    @EnvironmentObject private var lm: LocalizationManager"
    )

subs = [
    # Top-level sheets
    ('.navigationTitle("Gift Cards")', '.navigationTitle("gift_cards_title".t)'),
    ('GiftCardAmountSheet(title: "Top Up Gift Card", actionTitle: "Add Balance", icon: "plus.circle.fill")',
     'GiftCardAmountSheet(title: "top_up_gift_card_title".t, actionTitle: "add_balance_btn".t, icon: "plus.circle.fill")'),
    ('GiftCardAmountSheet(title: "Redeem Gift Card", actionTitle: "Redeem", icon: "minus.circle.fill", maxAmount: selectedCard.balance)',
     'GiftCardAmountSheet(title: "redeem_gift_card_title".t, actionTitle: "redeem_btn".t, icon: "minus.circle.fill", maxAmount: selectedCard.balance)'),

    # Void Card Alert
    ('.alert("Void Gift Card?", isPresented: $showingVoidConfirm)', '.alert("void_gift_card_alert_title".t, isPresented: $showingVoidConfirm)'),
    ('Button("Cancel", role: .cancel)', 'Button("cancel_btn".t, role: .cancel)'),
    ('Button("Void", role: .destructive)', 'Button("void_btn".t, role: .destructive)'),
    ('Text("This disables the card and removes any remaining usable balance.")', 'Text("void_gift_card_alert_message".t)'),

    # Metrics
    ('metricCard(title: "Outstanding",', 'metricCard(title: "outstanding_label".t,'),
    ('metricCard(title: "Active Cards",', 'metricCard(title: "active_cards_label".t,'),
    ('metricCard(title: "Disabled",', 'metricCard(title: "disabled_label".t,'),
    ('Label("Issue Card", systemImage: "plus.circle.fill")', 'Label("issue_card_btn".t, systemImage: "plus.circle.fill")'),

    # listPanel Search
    ('TextField("Lookup card number, customer, phone...", text: $searchText)', 'TextField("lookup_card_placeholder".t, text: $searchText)'),
    ('emptyState(title: "No Gift Cards", icon: "giftcard")', 'emptyState(title: "no_gift_cards".t, icon: "giftcard")'),
    ('Text(card.customer?.name ?? "Unassigned")', 'Text(card.customer?.name ?? "unassigned".t)'),

    # detailPanel details
    ('Text(card.customer?.name ?? "No linked customer")', 'Text(card.customer?.name ?? "no_linked_customer".t)'),
    ('metricCard(title: "Balance", value: "฿\\(card.balance.formatted(.number.precision(.fractionLength(2))))", icon: "wallet.pass.fill", color: .appTeal)',
     'metricCard(title: "balance_label".t, value: "฿\\(card.balance.formatted(.number.precision(.fractionLength(2))))", icon: "wallet.pass.fill", color: .appTeal)'),
    ('metricCard(title: "Initial", value: "฿\\(card.initialValue.formatted(.number.precision(.fractionLength(2))))", icon: "banknote.fill", color: .appAccent)',
     'metricCard(title: "initial_value_label".t, value: "฿\\(card.initialValue.formatted(.number.precision(.fractionLength(2))))", icon: "banknote.fill", color: .appAccent)'),
    ('metricCard(title: "Status", value: card.status.capitalized, icon: "flag.fill", color: card.status == "active" ? .appTeal : .appRose)',
     'metricCard(title: "status_label".t, value: card.status.capitalized, icon: "flag.fill", color: card.status == "active" ? .appTeal : .appRose)'),

    ('Text("ACTIONS")', 'Text("actions_header".t)'),
    ('actionButton("Top Up",', 'actionButton("top_up_btn".t,'),
    ('actionButton("Redeem",', 'actionButton("redeem_btn".t,'),
    ('actionButton("Void",', 'actionButton("void_btn".t,'),

    ('Text("DETAILS")', 'Text("details_header".t)'),
    ('detailRow("Updated",', 'detailRow("updated_label".t,'),
    ('detailRow("Expiry", card.expiresAt?.formatted(date: .abbreviated, time: .omitted) ?? "No expiry")',
     'detailRow("expiry_label".t, card.expiresAt?.formatted(date: .abbreviated, time: .omitted) ?? "no_expiry_label".t)'),
    ('detailRow("Customer Phone",', 'detailRow("customer_phone_label".t,'),
    ('emptyState(title: "Select a Gift Card", icon: "giftcard.fill")', 'emptyState(title: "select_gift_card_prompt".t, icon: "giftcard.fill")'),

    # GiftCardIssueSheet
    ('Section("Card")', 'Section("card_section".t)'),
    ('TextField("Card number", text: $cardNumber)', 'TextField("card_number_placeholder".t, text: $cardNumber)'),
    ('TextField("Initial value", text: $amountText)', 'TextField("initial_value_placeholder".t, text: $amountText)'),
    ('Toggle("Set expiry date", isOn: $hasExpiry)', 'Toggle("set_expiry_date_toggle".t, isOn: $hasExpiry)'),
    ('DatePicker("Expires", selection: $expiresAt, displayedComponents: .date)', 'DatePicker("expires_label".t, selection: $expiresAt, displayedComponents: .date)'),
    ('Section("Customer")', 'Section("customer_section".t)'),
    ('Picker("Linked customer", selection: $selectedCustomerId)', 'Picker("linked_customer_label".t, selection: $selectedCustomerId)'),
    ('Text("Unassigned").tag("")', 'Text("unassigned".t).tag("")'),
    ('.navigationTitle("Issue Gift Card")', '.navigationTitle("issue_gift_card_title".t)'),
    ('Button("Cancel") { dismiss() }', 'Button("cancel_btn".t) { dismiss() }'),
    ('Button("Issue") {', 'Button("issue_btn".t) {'),

    # GiftCardAmountSheet
    ('TextField("Amount", text: $amountText)', 'TextField("amount_placeholder".t, text: $amountText)'),
    ('TextField("Note", text: $note)', 'TextField("note_placeholder".t, text: $note)'),
    ('Text("Available balance: ฿\\(maxAmount, specifier: "%.2f")")', 'Text(LocalizationManager.shared.t("available_balance_template", maxAmount))'),
    ('Button("Cancel") { dismiss() }', 'Button("cancel_btn".t) { dismiss() }'),
]

for old_str, new_str in subs:
    content = content.replace(old_str, new_str)

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)

print("GiftCardManagementView localized successfully!")
