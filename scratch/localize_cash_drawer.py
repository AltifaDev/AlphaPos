# -*- coding: utf-8 -*-
import sys

file_path = "/Users/mac/Documents/AlphaPos/AlphaPos/Features/POS/Views/CashDrawerManagementView.swift"

with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# Add EnvironmentObject
if "@EnvironmentObject private var lm: LocalizationManager" not in content:
    content = content.replace(
        "    @Environment(\.modelContext) private var modelContext",
        "    @Environment(\.modelContext) private var modelContext\n    @EnvironmentObject private var lm: LocalizationManager"
    )

subs = [
    # closedSessionView
    ('.navigationTitle("Cash Drawer & Shifts")', '.navigationTitle("cash_drawer_shifts_title".t)'),
    ('Text("Cash Drawer is Locked")', 'Text("drawer_locked_title".t)'),
    ('Text("An active shift register session must be opened before processing cash sales or checkout orders.")', 'Text("drawer_locked_subtitle".t)'),
    ('Text("START A NEW SHIFT REGISTER")', 'Text("start_shift_header".t)'),
    ('Text("Starting Cash Float / เงินทอนเริ่มต้น")', 'Text("starting_cash_float_label".t)'),
    ('Text("Opening Notes / บันทึกเพิ่มเติม")', 'Text("opening_notes_label".t)'),
    ('TextField("e.g. Morning Shift A", text: $openingNotes)', 'TextField("opening_notes_placeholder".t, text: $openingNotes)'),
    ('Label("Open Register Session & Start Shift", systemImage: "lock.open.fill")', 'Label("open_session_btn".t, systemImage: "lock.open.fill")'),

    # openSessionView
    ('Text("Active Shift Running")', 'Text("shift_running_title".t)'),
    ('Text("Opened at \\(formatDate(session.openedAt))")', 'Text(LocalizationManager.shared.t("opened_at_template", formatDate(session.openedAt)))'),
    ('Label("End Shift & Close Drawer", systemImage: "lock.fill")', 'Label("end_shift_btn".t, systemImage: "lock.fill")'),

    # Reconcile Cards
    ('reconcileCard(title: "STARTING FLOAT", amount: session.openingCash, subtitle: "Cash float", color: .textPrimary)',
     'reconcileCard(title: "starting_float_label".t, amount: session.openingCash, subtitle: "cash_float_sub".t, color: .textPrimary)'),
    ('reconcileCard(title: "CASH SALES (+)", amount: cashSalesAmount, subtitle: "Completed orders", color: .appTeal)',
     'reconcileCard(title: "cash_sales_label".t, amount: cashSalesAmount, subtitle: "completed_orders_sub".t, color: .appTeal)'),
    ('reconcileCard(title: "CASH IN (+)", amount: cashInAmount, subtitle: "Paid-in movements", color: .appAccent)',
     'reconcileCard(title: "cash_in_label".t, amount: cashInAmount, subtitle: "paid_in_sub".t, color: .appAccent)'),
    ('reconcileCard(title: "CASH OUT (-)", amount: cashOutAmount, subtitle: "Paid-out movements", color: .appRose)',
     'reconcileCard(title: "cash_out_label".t, amount: cashOutAmount, subtitle: "paid_out_sub".t, color: .appRose)'),

    ('Text("EXPECTED CASH IN DRAWER")', 'Text("expected_cash_drawer".t)'),
    ('Text("CASH MOVEMENTS LOG")', 'Text("cash_movements_log".t)'),
    ('Label("Add Paid In/Out", systemImage: "plus.circle.fill")', 'Label("add_paid_in_out".t, systemImage: "plus.circle.fill")'),
    ('Text("No manual cash inputs or payouts logged in this shift.")', 'Text("no_manual_movements".t)'),
    ('Text(mov.movementType == "paid_in" || mov.movementType == "cash_in" ? "Paid In" : "Paid Out")',
     'Text(mov.movementType == "paid_in" || mov.movementType == "cash_in" ? "paid_in".t : "paid_out".t)'),

    # addMovementModal
    ('Section("Transaction Details")', 'Section("transaction_details_section".t)'),
    ('Picker("Movement Type", selection: $movementType)', 'Picker("movement_type_label".t, selection: $movementType)'),
    ('Text("Paid In (Add Cash)").tag("paid_in")', 'Text("paid_in_add_cash".t).tag("paid_in")'),
    ('Text("Paid Out (Withdraw Cash)").tag("paid_out")', 'Text("paid_out_withdraw_cash".t).tag("paid_out")'),
    ('Text("Amount (฿)").foregroundColor(.textSecondary)', 'Text("amount_baht".t).foregroundColor(.textSecondary)'),
    ('TextField("Reason / Description", text: $movementReason)', 'TextField("reason_description_placeholder".t, text: $movementReason)'),
    ('.navigationTitle("Add Cash Movement")', '.navigationTitle("add_cash_movement_title".t)'),
    ('Button("Cancel") { showMovementModal = false }', 'Button("cancel_btn".t) { showMovementModal = false }'),
    ('Button("Save") {', 'Button("save_btn".t) {'),

    # closeShiftModal
    ('Section("EXPECTED CALCULATED BALANCE")', 'Section("expected_calculated_balance".t)'),
    ('Text("Expected Cash in Drawer")', 'Text("expected_cash_label".t)'),
    ('Section("PHYSICAL CASH COUNT")', 'Section("physical_cash_count".t)'),
    ('Text("Actual Cash Counted (฿)")', 'Text("actual_cash_counted_label".t)'),
    ('Text("Discrepancy / ส่วนต่าง")', 'Text("discrepancy_label".t)'),
    ('Text("฿0.00 (Balanced)")', 'Text("balanced_option".t)'),
    ('Text("\\(discrepancy > 0 ? "+" : "")฿\\(discrepancy.formatted(.number.precision(.fractionLength(2)))) (\\(discrepancy > 0 ? "Overage" : "Shortage"))")',
     'Text("\\(discrepancy > 0 ? "+" : "")฿\\(discrepancy.formatted(.number.precision(.fractionLength(2)))) (\\(discrepancy > 0 ? "overage_label".t : "shortage_label".t))")'),
    ('TextField("Closing Notes / บันทึกการปิดยอดกะ", text: $closingNotes)', 'TextField("closing_notes_label".t, text: $closingNotes)'),
    ('.navigationTitle("Shift Reconciliation")', '.navigationTitle("shift_reconciliation_title".t)'),
    ('Button("Cancel") { showCloseModal = false }', 'Button("cancel_btn".t) { showCloseModal = false }'),
    ('Button("Close Register")', 'Button("close_register_btn".t)'),

    # zReportView
    ('Text("Z-REPORT (SHIFT SUMMARY)")', 'Text("z_report_header".t)'),
    ('Text("AlphaPos Z-Report")', 'Text("z_report_title".t)'),
    ('Text("Shift ID:")', 'Text("shift_id_label".t)'),
    ('Text("Opened At:")', 'Text("opened_at_label".t)'),
    ('Text("Closed At:")', 'Text("closed_at_label".t)'),
    ('Text("Opening Float:")', 'Text("opening_float_label".t)'),
    ('Text("Cash Sales (+):")', 'Text("cash_sales_label_colon".t)'),
    ('Text("Cash In (+):")', 'Text("cash_in_label_colon".t)'),
    ('Text("Cash Out (-):")', 'Text("cash_out_label_colon".t)'),
    ('Text("Expected Cash:")', 'Text("expected_cash_label".t)'),
    ('Text("Actual Cash Counted:")', 'Text("actual_cash_counted_label_colon".t)'),
    ('Text("Discrepancy:")', 'Text("discrepancy_label_colon".t)'),
    ('Text("Notes: \\(notes)")', 'Text("\\("notes_field".t): \\(notes)")'),
    ('Button("Print Simulation Z-Report")', 'Button("print_z_report_btn".t)'),
    ('Button("Done") {', 'Button("done".t) {'),
]

for old_str, new_str in subs:
    content = content.replace(old_str, new_str)

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)

print("CashDrawerManagementView localized successfully!")
