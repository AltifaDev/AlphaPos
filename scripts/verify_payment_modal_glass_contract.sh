#!/usr/bin/env bash
set -euo pipefail

source_file="AlphaPos/Features/POS/Views/POSView.swift"

assert_glass_cta() {
    local start="$1"
    local end="$2"
    local label="$3"
    local section
    section="$(sed -n "/$start/,/$end/p" "$source_file")"
    printf '%s' "$section" | rg -q 'apGlassButton\(prominent: true'
    printf '%s' "$section" | rg -q 'frame\(maxWidth: 520\)'
    printf '%s' "$section" | rg -q 'minHeight: 58'
    printf '%s' "$section" | rg -q 'font\(\.system\(\.headline, design: \.default'
    printf '%s' "$section" | rg -q 'lineLimit\(2\)'
    echo "- $label: native glass CTA"
}

assert_glass_cta 'struct ThaiChuaThaiPlusPaymentModal' 'struct QRPaymentModalView' 'Thai Chua Thai Plus'
assert_glass_cta 'struct QRPaymentModalView' 'MARK: - Credit Card Payment Modal View' 'PromptPay QR'
assert_glass_cta 'struct CreditCardPaymentModalView' '#Preview' 'Credit card'

echo "Payment modal glass contract: PASS"
