#!/bin/bash
# AlphaPos VPS Configuration Script
# Run on the VPS after supabase start to provision Vault secrets
# and update customer-order-web config
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

VPS_IP=$(hostname -I | awk '{print $1}')
BASE_URL="http://${VPS_IP}"
WEB_URL="http://${VPS_IP}:8080"

echo "Configuring AlphaPos VPS at ${BASE_URL}"

# ── Get service role key from supabase status ──────────────────────────
SERVICE_KEY=$(supabase status --output env 2>/dev/null | grep SERVICE_ROLE_KEY | sed 's/.*="\(.*\)"/\1/')

if [[ -z "$SERVICE_KEY" ]]; then
    echo "ERROR: Could not get SERVICE_ROLE_KEY from supabase status"
    exit 1
fi

PROJECT=$(awk -F'"' '/^project_id = / { print $2; exit }' supabase/config.toml)
CONTAINER="supabase_db_${PROJECT}"

# ── Provision Vault secrets ────────────────────────────────────────────
docker exec -i \
    -e PGPASSWORD=postgres \
    "$CONTAINER" \
    psql -U postgres -d postgres \
    -v service_key="$SERVICE_KEY" \
    -v edge_url="http://kong:8000" <<'SQL'
DELETE FROM vault.secrets
WHERE name IN ('service_role_key', 'edge_function_base_url');
SELECT vault.create_secret(:'service_key', 'service_role_key');
SELECT vault.create_secret(:'edge_url', 'edge_function_base_url');
SQL

# ── Update customer-order-web config ──────────────────────────────────
ENV_FILE="customer-order-web/.env"
if [[ -f "$ENV_FILE" ]]; then
    sed -i "s#^SUPABASE_URL=.*#SUPABASE_URL=${BASE_URL}#" "$ENV_FILE"
    sed -i "s#^ALLOWED_ORIGINS=.*#ALLOWED_ORIGINS=${WEB_URL}#" "$ENV_FILE"
fi

CONFIG_JS="customer-order-web/config.js"
cat > "$CONFIG_JS" <<JSEOF
window.ALPHAPOS_CONFIG = {
    supabaseUrl: '${BASE_URL}',
    supabaseKey: '$(grep SUPABASE_ANON_KEY "$ENV_FILE" | cut -d= -f2)',
    edgeFunctionUrl: '${BASE_URL}/functions/v1',
    merchantId: '$(grep MERCHANT_ID "$ENV_FILE" | cut -d= -f2)',
    isProduction: false
};
JSEOF

echo "✓ Vault provisioned"
echo "✓ customer-order-web config updated"
echo "✓ Configured AlphaPos VPS at ${BASE_URL}"
