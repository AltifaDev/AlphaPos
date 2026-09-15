#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"

fail() { printf 'staff login contract: %s\n' "$1" >&2; exit 1; }

rg -q 'rpc/get_staff_login_profiles' AlphaPosStaff/AlphaPosStaff/NetworkService+Timecard.swift \
  || fail 'AlphaPosStaff must use the canonical login-profile RPC'

if rg -U -q 'func fetchEmployees\(\).*endpoint: "employees"' AlphaPosStaff/AlphaPosStaff/NetworkService+Timecard.swift; then
  fail 'AlphaPosStaff must not read the employees table for login profiles'
fi

rg -q 'employee\.staffAppEnabled' AlphaPos/Features/Auth/Views/StaffLockView.swift \
  || fail 'iPad Staff Lock must enforce explicit Staff App access'
rg -q 'user\.pinCodeHash\?\.isEmpty == false' AlphaPos/Features/Auth/Views/StaffLockView.swift \
  || fail 'iPad Staff Lock must hide profiles without a PIN'
rg -q 'employee\.branchId\.lowercased\(\) == activeBranch' AlphaPos/Features/Auth/Views/StaffLockView.swift \
  || fail 'iPad Staff Lock must enforce branch scope'

for migration in \
  supabase/migrations/20260826000200_staff_login_profile_contract.sql \
  supabase/migrations/20260826000300_staff_login_eligibility_hardening.sql; do
  test -s "$migration" || fail "missing migration: $migration"
done

printf 'Staff login contract checks passed\n'
