#!/usr/bin/env bash
# Deploy production auth guard scripts to AlphaPos VPS and verify live configuration.
#
# Run from your Mac:
#   ./scripts/deploy-vps-auth-production.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VPS_HOST="${VPS_HOST:-root@119.59.99.163}"
VPS_ROOT="${VPS_ROOT:-/opt/alphapos}"

echo "Deploying VPS auth production scripts to ${VPS_HOST}:${VPS_ROOT}"

scp -o BatchMode=yes \
  "${ROOT_DIR}/scripts/fix-vps-auth-urls.sh" \
  "${ROOT_DIR}/scripts/vps-configure.sh" \
  "${VPS_HOST}:${VPS_ROOT}/scripts/"

ssh -o BatchMode=yes "$VPS_HOST" bash -s <<REMOTE
set -euo pipefail
chmod +x "${VPS_ROOT}/scripts/fix-vps-auth-urls.sh" "${VPS_ROOT}/scripts/vps-configure.sh"
"${VPS_ROOT}/scripts/fix-vps-auth-urls.sh" apply "${VPS_ROOT}"
echo
"${VPS_ROOT}/scripts/fix-vps-auth-urls.sh" verify "${VPS_ROOT}"
REMOTE

echo
echo "Production auth configuration verified on VPS."
