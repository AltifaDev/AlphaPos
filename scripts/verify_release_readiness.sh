#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${ALPHAPOS_RELEASE_MODE:-repository}"

echo "AlphaPos release verification ($MODE)"
"$ROOT_DIR/scripts/verify_no_secrets.sh"
"$ROOT_DIR/scripts/verify_hardware_certification.sh"
"$ROOT_DIR/scripts/verify_concurrency_contract.sh"
"$ROOT_DIR/run_tests.sh"

if [[ "${ALPHAPOS_RUN_SIMULATOR:-0}" == "1" ]]; then
  "$ROOT_DIR/scripts/verify_ipad_simulator.sh"
fi

if [[ -f "$ROOT_DIR/customer-order-web/package.json" ]]; then
  (cd "$ROOT_DIR/customer-order-web" && npm test && npm run build)
  "$ROOT_DIR/scripts/verify_customer_web_contract.sh"
fi

if [[ "$MODE" == "production" ]]; then
  required=(ALPHAPOS_BIOMETRIC_PROVIDER ALPHAPOS_BIOMETRIC_LIVENESS ALPHAPOS_ETAX_PROVIDER ALPHAPOS_ETAX_TAXPAYER_ID)
  for key in "${required[@]}"; do
    if [[ -z "${!key:-}" ]]; then
      echo "Production release blocked: $key is not configured."
      exit 1
    fi
  done
  if [[ "$ALPHAPOS_BIOMETRIC_LIVENESS" != "active" ]]; then
    echo "Production release blocked: biometric liveness must be active."
    exit 1
  fi
fi

echo "Release readiness gates passed for mode: $MODE"
