#!/usr/bin/env bash
# Deploy confirmation + recovery email templates and set-auth-locale function.
# Usage: ./scripts/deploy-auth-emails.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VPS_HOST="${VPS_HOST:-119.59.99.163}"
VPS_USER="${VPS_USER:-root}"
CONFIRM_URL="https://alphaposweb.com/email/confirmation.html"
RECOVERY_URL="https://alphaposweb.com/email/recovery.html"

SSH=(ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=15)
SCP=(scp -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=15)

echo "━━━ 1) Upload HTML templates ━━━"
"${SSH[@]}" "$VPS_USER@$VPS_HOST" "mkdir -p /var/www/alphaposweb/email /opt/alphapos/supabase/templates /opt/alphapos/supabase/functions/set-auth-locale"
"${SCP[@]}" "$ROOT/supabase/templates/confirmation.html" "$VPS_USER@$VPS_HOST:/var/www/alphaposweb/email/confirmation.html"
"${SCP[@]}" "$ROOT/supabase/templates/recovery.html" "$VPS_USER@$VPS_HOST:/var/www/alphaposweb/email/recovery.html"
"${SCP[@]}" "$ROOT/supabase/templates/confirmation.html" "$VPS_USER@$VPS_HOST:/opt/alphapos/supabase/templates/confirmation.html"
"${SCP[@]}" "$ROOT/supabase/templates/recovery.html" "$VPS_USER@$VPS_HOST:/opt/alphapos/supabase/templates/recovery.html"
"${SCP[@]}" "$ROOT/supabase/functions/set-auth-locale/index.ts" "$VPS_USER@$VPS_HOST:/opt/alphapos/supabase/functions/set-auth-locale/index.ts"

echo "━━━ 2) Patch config.toml ━━━"
"${SSH[@]}" "$VPS_USER@$VPS_HOST" bash <<'REMOTE'
set -euo pipefail
CONFIG=/opt/alphapos/supabase/config.toml
cp "$CONFIG" "${CONFIG}.bak_auth_email_$(date +%Y%m%d_%H%M%S)"
python3 - <<'PY'
from pathlib import Path
import re
path = Path("/opt/alphapos/supabase/config.toml")
text = path.read_text()
block = """[auth.email.template.confirmation]
subject = \"Confirm your email — AlphaPos\"
content_path = \"./supabase/templates/confirmation.html\"

[auth.email.template.recovery]
subject = \"Reset your password — AlphaPos\"
content_path = \"./supabase/templates/recovery.html\"
"""
# Replace existing confirmation/recovery blocks or insert before [auth.sms]
text = re.sub(
    r"\[auth\.email\.template\.confirmation\][\s\S]*?(?=\[auth\.email\.template\.|\[auth\.sms\]|\[auth\.mfa|\Z)",
    "",
    text,
)
text = re.sub(
    r"\[auth\.email\.template\.recovery\][\s\S]*?(?=\[auth\.email\.template\.|\[auth\.sms\]|\[auth\.mfa|\Z)",
    "",
    text,
)
if "[auth.sms]" in text:
    text = text.replace("[auth.sms]", block.rstrip() + "\n\n[auth.sms]", 1)
else:
    text = text.rstrip() + "\n\n" + block
path.write_text(text)
print("config.toml templates updated")
PY
REMOTE

echo "━━━ 3) Public URL check ━━━"
curl -sI "$RECOVERY_URL" | head -6
curl -s "$RECOVERY_URL" | head -3

echo "━━━ 4) Restart edge runtime (set-auth-locale) ━━━"
"${SSH[@]}" "$VPS_USER@$VPS_HOST" "docker restart supabase_edge_runtime_AlphaPos && sleep 3 && docker ps --filter name=supabase_edge_runtime_AlphaPos --format '{{.Names}} {{.Status}}'"

echo "━━━ 5) Recreate auth with confirmation + recovery template URLs ━━━"
"${SSH[@]}" "$VPS_USER@$VPS_HOST" bash <<'REMOTE'
set -euo pipefail
python3 - <<'PY'
import json, subprocess

container = "supabase_auth_AlphaPos"
keys = {
    "GOTRUE_MAILER_TEMPLATES_CONFIRMATION": "https://alphaposweb.com/email/confirmation.html",
    "GOTRUE_MAILER_SUBJECTS_CONFIRMATION": "Confirm your email — AlphaPos",
    "GOTRUE_MAILER_TEMPLATES_RECOVERY": "https://alphaposweb.com/email/recovery.html",
    "GOTRUE_MAILER_SUBJECTS_RECOVERY": "Reset your password — AlphaPos",
    "GOTRUE_MAILER_TEMPLATE_RELOADING_ENABLED": "true",
}
inspect = json.loads(subprocess.check_output(["docker", "inspect", container], text=True))[0]
cfg = inspect["Config"]
name = inspect["Name"].lstrip("/")
image = cfg["Image"]
new_env, seen = [], set()
for item in cfg.get("Env") or []:
    key = item.split("=", 1)[0]
    if key in keys:
        new_env.append(f"{key}={keys[key]}")
        seen.add(key)
    else:
        new_env.append(item)
for key, val in keys.items():
    if key not in seen:
        new_env.append(f"{key}={val}")

networks = list((inspect.get("NetworkSettings") or {}).get("Networks") or {})
network = networks[0] if networks else "supabase_network_AlphaPos"
net_cfg = ((inspect.get("NetworkSettings") or {}).get("Networks") or {}).get(network) or {}
aliases = net_cfg.get("Aliases") or []

subprocess.check_call(["docker", "rm", "-f", name])
run_cmd = ["docker", "run", "-d", "--name", name, "--network", network, "--restart", "unless-stopped"]
for alias in aliases:
    if alias and alias != name:
        run_cmd += ["--network-alias", alias]
for e in new_env:
    run_cmd += ["-e", e]
if cfg.get("WorkingDir"):
    run_cmd += ["-w", cfg["WorkingDir"]]
if cfg.get("User"):
    run_cmd += ["--user", cfg["User"]]
run_cmd.append(image)
if cfg.get("Cmd"):
    run_cmd += list(cfg["Cmd"])
subprocess.check_call(run_cmd)
print("auth recreated")
PY
sleep 5
docker ps --filter name=supabase_auth_AlphaPos --format '{{.Names}} {{.Status}}'
echo "CONFIRM=$(docker exec supabase_auth_AlphaPos printenv GOTRUE_MAILER_TEMPLATES_CONFIRMATION)"
echo "RECOVERY=$(docker exec supabase_auth_AlphaPos printenv GOTRUE_MAILER_TEMPLATES_RECOVERY)"
/opt/alphapos/scripts/fix-vps-auth-urls.sh verify || /opt/alphapos/scripts/fix-vps-auth-urls.sh apply /opt/alphapos
REMOTE

echo "━━━ DONE ━━━"
echo "Recovery template: $RECOVERY_URL"
