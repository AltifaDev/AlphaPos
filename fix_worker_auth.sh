#!/bin/bash
# ============================================================
# AlphaPos — Fix Cloudflare Worker 401 (Missing Supabase Key)
# ============================================================
# ONE-SHOT: pulls anon key from VPS, sets CF secret, deploys, verifies.
#
#   chmod +x fix_worker_auth.sh
#   ./fix_worker_auth.sh
#
# Requires: ssh access to the VPS + wrangler logged in on this Mac.

set -euo pipefail

VPS_HOST="${VPS_HOST:-root@119.59.99.163}"      # override: VPS_HOST=user@ip ./fix_worker_auth.sh
WRANGLER_DIR="/Users/mac/Documents/AlphaPos"
VPS_PROJECT_DIR="${VPS_PROJECT_DIR:-/root/AlphaPos}"  # where supabase/ lives on the VPS

echo ""
echo "🔑 Pulling anon key from VPS ($VPS_HOST)..."

# Preferred: supabase status (matches your vps-configure.sh).
# Fallbacks: the app's own .env, then common docker .env paths.
ANON_KEY=$(ssh "$VPS_HOST" bash -s <<REMOTE 2>/dev/null || echo "SSH_FAILED"
set -e
cd "$VPS_PROJECT_DIR" 2>/dev/null || true
KEY=\$(supabase status --output env 2>/dev/null | grep -E '^ANON_KEY=' | sed 's/.*="\?\([^"]*\)"\?/\1/')
if [ -z "\$KEY" ]; then
  KEY=\$(grep -E '^SUPABASE_ANON_KEY=' customer-order-web/.env 2>/dev/null | cut -d= -f2-)
fi
if [ -z "\$KEY" ]; then
  for f in /opt/supabase/docker/.env /root/supabase/docker/.env /root/supabase/.env /opt/supabase/.env; do
    [ -f "\$f" ] && KEY=\$(grep -E '^ANON_KEY=' "\$f" | cut -d= -f2-) && [ -n "\$KEY" ] && break
  done
fi
echo "\$KEY"
REMOTE
)

if [ "$ANON_KEY" = "SSH_FAILED" ]; then
  echo "❌ Could not SSH to $VPS_HOST."
  echo "   Fix SSH, or run manually on the VPS:  supabase status --output env | grep ANON_KEY"
  echo "   then:  echo 'KEY' | npx wrangler secret put SUPABASE_ANON_KEY && npx wrangler deploy"
  exit 1
fi

ANON_KEY=$(echo "$ANON_KEY" | tr -d '[:space:]')
if [ -z "$ANON_KEY" ] || [ "${ANON_KEY:0:6}" != "eyJhbG" ]; then
  echo "❌ Did not get a valid JWT anon key (got: '${ANON_KEY:0:12}...')."
  echo "   On the VPS run:  supabase status --output env | grep ANON_KEY"
  exit 1
fi

echo "✅ Got anon key (${#ANON_KEY} chars, role should be 'anon')."
echo ""
echo "📤 Setting Cloudflare Worker secret SUPABASE_ANON_KEY..."
cd "$WRANGLER_DIR"
printf '%s' "$ANON_KEY" | npx wrangler secret put SUPABASE_ANON_KEY

echo ""
echo "🚀 Deploying worker..."
npx wrangler deploy

echo ""
echo "✅ Deploy complete."
echo ""
echo "🔍 Verifying: curling /rest/v1/merchants through the worker..."
WORKER_URL="https://sync.alphaposweb.com"
MERCHANT_ID="163350b0-056d-4d5e-b5d4-24e7aac5ab6d"

# Give the deploy a moment to propagate.
sleep 3

# Fetch the anon key the worker now serves in config.js (source of truth).
SERVED_KEY=$(curl -s "$WORKER_URL/config.js" | grep -o "supabaseKey:[^,]*" | sed "s/.*['\"]\(eyJhbG[^'\"]*\)['\"].*/\1/")
if [ -z "$SERVED_KEY" ] || [ "${SERVED_KEY:0:6}" != "eyJhbG" ]; then
  echo "⚠️  Could not read a valid anon key from $WORKER_URL/config.js"
  echo "    config.js returned:"
  curl -s "$WORKER_URL/config.js" | head -c 300
  echo ""
  SERVED_KEY="$ANON_KEY"   # fall back to the key we just set
fi

HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' \
  "$WORKER_URL/rest/v1/merchants?select=id,name&id=eq.$MERCHANT_ID&limit=1" \
  -H "apikey: $SERVED_KEY" \
  -H "Authorization: Bearer $SERVED_KEY")

echo ""
if [ "$HTTP_CODE" = "200" ]; then
  echo "✅ PASS — worker returned HTTP 200. Auth is fixed."
  echo "   Open $WORKER_URL (hard-refresh / unregister the service worker if config.js is cached)."
elif [ "$HTTP_CODE" = "401" ]; then
  echo "❌ FAIL — still HTTP 401. The served key is not accepted by the VPS Supabase."
  echo "   The anon key likely doesn't match the VPS JWT secret. On the VPS run:"
  echo "     supabase status --output env | grep ANON_KEY"
  echo "   and confirm it matches what the worker serves at $WORKER_URL/config.js"
else
  echo "⚠️  Unexpected HTTP $HTTP_CODE from the worker. Check 'npx wrangler tail' for details."
fi
