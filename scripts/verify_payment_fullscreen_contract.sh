#!/usr/bin/env bash
set -euo pipefail

source_file="AlphaPos/Features/POS/Views/POSView.swift"
presentation="$(sed -n '/fullScreenCover(item: \$activePayment)/,/sheet(isPresented: \$showCustomerPicker)/p' "$source_file")"
cash_modal="$(sed -n '/struct CashPaymentModalView/,/struct KeypadButtonStyle/p' "$source_file")"
support_modal="$(sed -n '/struct ThaiChuaThaiPlusPaymentModal/,/struct QRPaymentModalView/p' "$source_file")"

printf '%s' "$presentation" | rg -q 'case \.cash'
printf '%s' "$presentation" | rg -q 'case \.qrCode'
printf '%s' "$presentation" | rg -q 'case \.creditCard'
printf '%s' "$presentation" | rg -q 'case \.thaiChuaThaiPlus'

cash_detents="$(printf '%s' "$cash_modal" | rg -c 'presentationDetents' || true)"
support_detents="$(printf '%s' "$support_modal" | rg -c 'presentationDetents' || true)"
test "${cash_detents:-0}" -eq 0
test "${support_detents:-0}" -eq 0

echo "Payment full-screen contract: PASS"
echo "- Cash, QR, card and Thai Chua Thai share native full-screen presentation"
echo "- Cash compact height detent: 0"
