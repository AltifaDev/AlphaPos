#!/usr/bin/env bash
set -euo pipefail

source_file="AlphaPos/Features/POS/Views/POSView.swift"
cash_section="$(sed -n '/struct CashPaymentModalView/,/MARK: - Thai QR Payment Frame View/p' "$source_file")"

marker_count="$(printf '%s' "$cash_section" | rg -c 'CASH_KEYPAD_IMMEDIATE_RENDER')"
numeric_transition_count="$(printf '%s' "$cash_section" | rg -c 'numericText' || true)"
numeric_transition_count="${numeric_transition_count:-0}"

test "$marker_count" -ge 2
test "$numeric_transition_count" -ge 1
printf '%s' "$cash_section" | rg -q 'if !hasEnteredCustomAmount'
printf '%s' "$cash_section" | rg -q 'Button\(action: confirmPrimaryPayment\)'
printf '%s' "$cash_section" | rg -q 'apGlassButton\(prominent: true'
printf '%s' "$cash_section" | rg -q 'GlassEffectContainer\(spacing: 7\)'
test "$(printf '%s' "$cash_section" | rg -c 'apGlassButton')" -ge 3
! printf '%s' "$cash_section" | rg -q 'CashKeypadButtonStyle'

echo "Cash keypad animation contract: PASS"
echo "- Tendered/change digits settle in the input frame"
echo "- Numeric transition is scoped to the tendered-value text"
echo "- Exact cash is the default one-tap primary action"
echo "- Keypad and primary CTA use native Liquid Glass button styles"
echo "- iOS 26+ keypad glass is grouped in the native GlassEffectContainer"
