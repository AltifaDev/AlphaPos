#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

fail=0
while IFS= read -r file; do
    case "$file" in
        ./customer-order-web/node_modules/*|./customer-order-web/venv/*|./customer-order-web/.venv/*|./AppStoreBuild/*|./ReleaseBuilds/*|./backups/*|./.build/*|./tmp/*) continue ;;
    esac
    printf 'Secret-like credential file must not be in workspace: %s\n' "$file" >&2
    fail=1
done < <(find . -type f \( -name '*.p8' -o -name '*.p12' -o -name '*.mobileprovision' \) -print)

if command -v rg >/dev/null 2>&1; then
    if rg -l -U --hidden \
        -g '!customer-order-web/node_modules/**' -g '!customer-order-web/venv/**' \
        -g '!customer-order-web/.venv/**' -g '!AppStoreBuild/**' -g '!ReleaseBuilds/**' \
        -g '!backups/**' -g '!.build/**' -g '!tmp/**' -g '!scripts/verify_no_secrets.sh' \
        -- '-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----\r?\n[A-Za-z0-9+/]{20,}|APNS_PRIVATE_KEY=(-----BEGIN|[A-Za-z0-9+/]{32,})|service_role_key[[:space:]]*[:=][[:space:]]*[A-Za-z0-9_-]{20,}' .; then
        printf 'Embedded secret material detected. Move credentials to the deployment secret store.\n' >&2
        fail=1
    fi
fi

if [ "$fail" -ne 0 ]; then exit 1; fi
printf 'Secret scan passed: no private credential material found.\n'
