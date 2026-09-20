#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WEB="$ROOT/customer-order-web"
MIGRATION="$ROOT/supabase/migrations/20260811000100_customer_web_branch_security.sql"
PERMANENT_QR_MIGRATION="$ROOT/supabase/migrations/20260812000101_permanent_qr_staff_approval.sql"

check() {
  local pattern="$1"
  local file="$2"
  if command -v rg >/dev/null 2>&1; then
    rg -q "$pattern" "$file" 2>/dev/null || rg -F -q "$pattern" "$file"
  else
    grep -qE "$pattern" "$file" 2>/dev/null || grep -F -q "$pattern" "$file"
  fi
}

check 'role: "customer_web"' "$ROOT/supabase/functions/issue-customer-session-token/index.ts"
check 'token_use: "customer_session"' "$ROOT/supabase/functions/issue-customer-session-token/index.ts"
check 'require_customer_session' "$MIGRATION"
check 'idempotency_conflict' "$MIGRATION"
check 'branch_id=s.branch_id' "$MIGRATION"
check 'FROM anon,authenticated' "$MIGRATION"
check "rpc\('create_customer_service_request'" "$WEB/app.js"
check "idempotency_key: idempotencyKey" "$WEB/app.js"
check "filter: .*session_token=eq" "$WEB/app.js"
if check 'cdn.jsdelivr.net/npm/@supabase/supabase-js' "$WEB/index.html"; then
  echo "Supabase SDK must be bundled, not loaded from a mutable CDN" >&2
  exit 1
fi
check 'return False' "$WEB/server.py"
check 'STAFF_APPROVAL_REQUIRED' "$ROOT/supabase/functions/issue-customer-session-token/index.ts"
check 'requested?.status === "invalid"' "$ROOT/supabase/functions/issue-customer-session-token/index.ts"
check 'PERMANENT_QR_UNAVAILABLE' "$ROOT/supabase/functions/issue-customer-session-token/index.ts"
check 'showQrServiceUnavailableError' "$WEB/app.js"
check 'consecutiveServerFailures < 4' "$WEB/app.js"
check 'requestController.abort' "$WEB/app.js"
check "status', 'invalid'" "$ROOT/supabase/migrations/20260910000100_permanent_qr_error_contract.sql"
check 'approve_permanent_qr_from_service_request' "$PERMANENT_QR_MIGRATION"
check "status='approved'" "$PERMANENT_QR_MIGRATION"
check 'permanentQRKey' "$WEB/app.js"
check '&key=' "$ROOT/AlphaPos/Features/Tables/Views/BatchQRCodePrintView.swift"

echo "customer web contract verification passed"
