#!/usr/bin/env bash
# Deploy localized confirmation email template to VPS + wire GoTrue.
# Usage: ./scripts/deploy-confirmation-email.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VPS_HOST="${VPS_HOST:-119.59.99.163}"
VPS_USER="${VPS_USER:-root}"
TEMPLATE_SRC="$ROOT/supabase/templates/confirmation.html"
TEMPLATE_URL="https://alphaposweb.com/email/confirmation.html"

SSH=(ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=15)
SCP=(scp -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=15)

echo "━━━ 1) Upload template ━━━"
"${SSH[@]}" "$VPS_USER@$VPS_HOST" "mkdir -p /var/www/alphaposweb/email /opt/alphapos/supabase/templates"
"${SCP[@]}" "$TEMPLATE_SRC" "$VPS_USER@$VPS_HOST:/var/www/alphaposweb/email/confirmation.html"
"${SCP[@]}" "$TEMPLATE_SRC" "$VPS_USER@$VPS_HOST:/opt/alphapos/supabase/templates/confirmation.html"

echo "━━━ 2) Patch VPS config.toml ━━━"
"${SSH[@]}" "$VPS_USER@$VPS_HOST" bash <<'REMOTE'
set -euo pipefail
CONFIG=/opt/alphapos/supabase/config.toml
cp "$CONFIG" "${CONFIG}.bak_email_$(date +%Y%m%d_%H%M%S)"
python3 - <<'PY'
from pathlib import Path
import re
path = Path("/opt/alphapos/supabase/config.toml")
text = path.read_text()
block = """[auth.email.template.confirmation]
subject = \"Confirm your email — AlphaPos\"
content_path = \"./supabase/templates/confirmation.html\"
"""
if "[auth.email.template.confirmation]" in text:
    text = re.sub(
        r"\[auth\.email\.template\.confirmation\][\s\S]*?(?=\n\[|\Z)",
        block.rstrip() + "\n\n",
        text,
        count=1,
    )
elif "[auth.sms]" in text:
    text = text.replace("[auth.sms]", block.rstrip() + "\n\n[auth.sms]", 1)
else:
    text = text.rstrip() + "\n\n" + block
path.write_text(text)
print("config.toml updated")
PY
REMOTE

echo "━━━ 3) Verify public URL ━━━"
curl -sI "$TEMPLATE_URL" | head -8
curl -s "$TEMPLATE_URL" | head -3

echo "━━━ 4) Recreate auth container with template URL ━━━"
"${SSH[@]}" "$VPS_USER@$VPS_HOST" bash <<'REMOTE'
set -euo pipefail
python3 - <<'PY'
import json, subprocess

container = "supabase_auth_AlphaPos"
template_url = "https://alphaposweb.com/email/confirmation.html"
inspect = json.loads(subprocess.check_output(["docker", "inspect", container], text=True))[0]
cfg = inspect["Config"]
name = inspect["Name"].lstrip("/")
image = cfg["Image"]

keys = {
    "GOTRUE_MAILER_TEMPLATES_CONFIRMATION": template_url,
    "GOTRUE_MAILER_SUBJECTS_CONFIRMATION": "Confirm your email — AlphaPos",
    "GOTRUE_MAILER_TEMPLATE_RELOADING_ENABLED": "true",
}
new_env = []
seen = set()
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

run_cmd = [
    "docker", "run", "-d",
    "--name", name,
    "--network", network,
    "--restart", "unless-stopped",
]
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
print("Recreating auth…")
subprocess.check_call(run_cmd)
print("OK")
PY

sleep 5
docker ps --filter name=supabase_auth_AlphaPos --format '{{.Names}} {{.Status}}'
echo "TEMPLATE=$(docker exec supabase_auth_AlphaPos printenv GOTRUE_MAILER_TEMPLATES_CONFIRMATION)"
echo "SUBJECT=$(docker exec supabase_auth_AlphaPos printenv GOTRUE_MAILER_SUBJECTS_CONFIRMATION)"
/opt/alphapos/scripts/fix-vps-auth-urls.sh verify || {
  echo "Auth URLs drifted — applying fix…"
  /opt/alphapos/scripts/fix-vps-auth-urls.sh apply /opt/alphapos
}
REMOTE

echo "━━━ DONE ━━━"
echo "Public template: $TEMPLATE_URL"
