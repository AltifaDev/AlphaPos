#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"

test ! -n "$(grep -R 'DEFAULT_DEVICE_SECRET\|alphapos_sec_' AlphaPosStaff/AlphaPosStaff --exclude='*.xcuserstate' || true)"
grep -q 'complete_checkout_atomic' AlphaPos/Data/Remote/NetworkManager+Orders.swift
grep -q 'complete_checkout_atomic' AlphaPosStaff/AlphaPosStaff/NetworkService+Orders.swift
grep -q 'branch_id: pairedBranchId' supabase/functions/issue-merchant-token/index.ts
grep -q 'requiresManualRetry' AlphaPosStaff/AlphaPosStaff/OfflineCache.swift
grep -q 'table": "sync_outbox"' AlphaPosStaff/AlphaPosStaff/NetworkService+Realtime.swift

xcodebuild -project AlphaPosStaff/AlphaPosStaff.xcodeproj -scheme AlphaPosStaff \
  -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build >/tmp/alphaposstaff-contract-build.log

xcodebuild -project AlphaPos.xcodeproj -scheme AlphaPos -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build >/tmp/alphapos-contract-build.log

echo "AlphaPos online contract verification passed"
