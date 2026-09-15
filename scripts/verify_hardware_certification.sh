#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$ROOT_DIR/config/hardware-certification.json"
MODE="${ALPHAPOS_RELEASE_MODE:-repository}"

jq -e '.schema_version == 1 and .policy == "fail_closed" and (.required_test_cases | length >= 8)' "$MANIFEST" >/dev/null
if [[ "$MODE" == "production" ]]; then
  jq -e '(.devices | length) > 0 and all(.devices[]; .manufacturer and .model and .firmware and .transport and .tested_at and (.passed_test_cases | length >= 8))' "$MANIFEST" >/dev/null || {
    echo "Hardware certification failed: production requires at least one fully tested physical device."
    exit 1
  }
fi
echo "Hardware certification manifest valid for mode: $MODE"
