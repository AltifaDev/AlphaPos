#!/usr/bin/env bash
set -euo pipefail

source_file="AlphaPos/Features/POS/Views/POSView.swift"
selector="$(sed -n '/private var cartPanelCheckoutActions/,/private func openFocusedNotificationOrder/p' "$source_file")"

printf '%s' "$selector" | rg -q 'LazyVGrid'
printf '%s' "$selector" | rg -q 'paymentGridColumnCount'
printf '%s' "$selector" | rg -q 'geometry\.size\.width >= 360 \? 3 : 2'
printf '%s' "$selector" | rg -q 'apGlassButton\(prominent: isActive'
printf '%s' "$selector" | rg -q 'minHeight: 32'
printf '%s' "$selector" | rg -q 'controlSize\(\.small\)'
printf '%s' "$selector" | rg -q 'frame\(minHeight: 44\)'
printf '%s' "$selector" | rg -q 'lineLimit\(2\)'

old_layout_count="$(printf '%s' "$selector" | rg -c 'ScrollView\(\.horizontal' || true)"
old_layout_count="${old_layout_count:-0}"
test "$old_layout_count" -eq 0

echo "Payment selector glass contract: PASS"
echo "- Payment grid uses three compact columns from 360pt, two only when narrower"
echo "- Payment tiles use native glass button styling"
echo "- Long localized labels may occupy two lines"
echo "- Payment tiles preserve the 44pt minimum touch target"
echo "- Legacy secondary horizontal payment row: 0"
