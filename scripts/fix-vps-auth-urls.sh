#!/usr/bin/env bash
# Production Supabase Auth URL guard for AlphaPos VPS.
# Ensures email verification / password reset links never point at 127.0.0.1:54321.
#
# Usage (on VPS, from repo root /opt/alphapos):
#   ./scripts/fix-vps-auth-urls.sh apply    # patch config + restart auth if needed
#   ./scripts/fix-vps-auth-urls.sh verify   # exit 0 only when production URLs are live
#   ./scripts/fix-vps-auth-urls.sh status   # print expected vs actual
set -euo pipefail

ROOT_DIR="/opt/alphapos"
CONFIG="${ROOT_DIR}/supabase/config.toml"
PROJECT_ID="AlphaPos"
AUTH_CONTAINER="supabase_auth_${PROJECT_ID}"

PRODUCTION_SITE_URL="https://alphaposweb.com/auth/callback"
PRODUCTION_EXTERNAL_URL="https://api.alphaposweb.com/auth/v1"
PRODUCTION_REDIRECT_URLS='["https://alphaposweb.com/auth/callback", "https://alphaposweb.com", "https://sync.alphaposweb.com", "alphapos://auth/callback"]'
PRODUCTION_VERIFY_URL="${PRODUCTION_EXTERNAL_URL%/}/verify"

refresh_paths() {
  CONFIG="${ROOT_DIR}/supabase/config.toml"
  PROJECT_ID="$(awk -F'"' '/^project_id = / { print $2; exit }' "$CONFIG" 2>/dev/null || echo AlphaPos)"
  AUTH_CONTAINER="supabase_auth_${PROJECT_ID}"
}

usage() {
  cat <<EOF
Usage: $(basename "$0") <apply|verify|status> [root_dir]

  apply   Patch config only; never stop/recreate the production database
  verify  Fail (exit 1) unless auth container serves production URLs
  status  Show expected vs running auth configuration

Default root_dir: /opt/alphapos
EOF
}

require_config() {
  if [[ ! -f "$CONFIG" ]]; then
    echo "ERROR: missing $CONFIG" >&2
    exit 1
  fi
}

auth_env() {
  docker inspect "$AUTH_CONTAINER" --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null || true
}

patch_config() {
  require_config
  cp "$CONFIG" "${CONFIG}.bak_$(date +%Y%m%d_%H%M%S)"

  python3 - "$CONFIG" <<PY
import re
from pathlib import Path

path = Path("${CONFIG}")
text = path.read_text()

text = re.sub(
    r'^site_url = .*$',
    'site_url = "${PRODUCTION_SITE_URL}"',
    text,
    count=1,
    flags=re.M,
)

if re.search(r'^external_url = ', text, re.M):
    text = re.sub(
        r'^external_url = .*$',
        'external_url = "${PRODUCTION_EXTERNAL_URL}"',
        text,
        count=1,
        flags=re.M,
    )
else:
    text = re.sub(
        r'^# external_url = ""$',
        'external_url = "${PRODUCTION_EXTERNAL_URL}"',
        text,
        count=1,
        flags=re.M,
    )

text = re.sub(
    r'^additional_redirect_urls = .*$',
    'additional_redirect_urls = ${PRODUCTION_REDIRECT_URLS}',
    text,
    count=1,
    flags=re.M,
)

path.write_text(text)
print("Patched auth URLs in", path)
for line in text.splitlines():
    if any(k in line for k in ("site_url", "external_url", "additional_redirect")):
        print(" ", line)
PY
}

verify_auth_env() {
  local env failures=0
  env="$(auth_env)"

  if [[ -z "$env" ]]; then
    echo "FAIL: auth container '$AUTH_CONTAINER' not found or not running" >&2
    return 1
  fi

  check_env() {
    local key="$1" expected="$2"
    local actual
    actual="$(printf '%s\n' "$env" | awk -F= -v k="$key" '$1 == k { sub(/^[^=]*=/, ""); print; exit }')"
    if [[ "$actual" != "$expected" ]]; then
      echo "FAIL: $key"
      echo "      expected: $expected"
      echo "      actual:   ${actual:-<unset>}"
      failures=1
    else
      echo "OK:   $key=$actual"
    fi
  }

  check_env "API_EXTERNAL_URL" "$PRODUCTION_EXTERNAL_URL"
  check_env "GOTRUE_SITE_URL" "$PRODUCTION_SITE_URL"
  check_env "GOTRUE_JWT_ISSUER" "$PRODUCTION_EXTERNAL_URL"
  check_env "GOTRUE_MAILER_URLPATHS_CONFIRMATION" "$PRODUCTION_VERIFY_URL"
  check_env "GOTRUE_MAILER_URLPATHS_RECOVERY" "$PRODUCTION_VERIFY_URL"

  if printf '%s\n' "$env" | grep -q '127\.0\.0\.1:54321'; then
    echo "FAIL: auth container still contains localhost dev URLs (127.0.0.1:54321)" >&2
    failures=1
  fi

  return "$failures"
}

cmd_status() {
  require_config
  echo "Expected production auth configuration:"
  echo "  site_url=$PRODUCTION_SITE_URL"
  echo "  external_url=$PRODUCTION_EXTERNAL_URL"
  echo "  verify_url=$PRODUCTION_VERIFY_URL"
  echo
  echo "config.toml:"
  grep -E '^site_url|^external_url|^additional_redirect' "$CONFIG" || true
  echo
  echo "Running auth container:"
  verify_auth_env || true
}

cmd_verify() {
  verify_auth_env
}

cmd_apply() {
  require_config
  patch_config

  if verify_auth_env; then
    echo "Auth URLs already production-ready; no restart needed."
    return 0
  fi

  echo "ERROR: config was patched, but the running auth container still has old values." >&2
  echo "Refusing to run 'supabase stop/start' on production." >&2
  echo "Recreate only ${AUTH_CONTAINER} with the approved service-specific procedure." >&2
  exit 1
}

main() {
  local command="${1:-apply}"
  shift || true
  if [[ $# -gt 0 ]]; then
    ROOT_DIR="$1"
  fi
  refresh_paths

  case "$command" in
    apply) cmd_apply ;;
    verify) cmd_verify ;;
    status) cmd_status ;;
    -h|--help|help) usage ;;
    *)
      usage
      exit 64
      ;;
  esac
}

main "$@"
