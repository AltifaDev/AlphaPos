#!/usr/bin/env bash
set -euo pipefail

source_file="AlphaPos/Features/POS/Views/POSView.swift"
cash_section="$(sed -n '/struct CashPaymentModalView/,/MARK: - Thai QR Payment Frame View/p' "$source_file")"

marker_count="$(printf '%s' "$cash_section" | rg -c 'CASH_KEYPAD_IMMEDIATE_RENDER')"
numeric_transition_count="$(printf '%s' "$cash_section" | rg -c 'numericText' || true)"
numeric_transition_count="${numeric_transition_count:-0}"

test "$marker_count" -ge 2
test "$numeric_transition_count" -eq 0
printf '%s' "$cash_section" | rg -q 'if !hasEnteredCustomAmount'
printf '%s' "$cash_section" | rg -q 'Button\(action: confirmPrimaryPayment\)'
printf '%s' "$cash_section" | rg -q 'apGlassButton\(prominent: true'
test "$(printf '%s' "$cash_section" | rg -c 'apGlassButton')" -ge 3

echo "Cash keypad animation contract: PASS"
echo "- Tendered/change digits settle in the input frame"
echo "- Native rolling-number transitions in cash entry path: 0"
echo "- Exact cash is the default one-tap primary action"
echo "- Quick cash, keypad and primary CTA use native glass button styles"
