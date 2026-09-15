#!/bin/bash
# ============================================================
# deploy-push-notifications.sh
# AlphaPosStaff — Deploy Push Notification System to VPS
#
# Usage:
#   chmod +x scripts/deploy-push-notifications.sh
#   ./scripts/deploy-push-notifications.sh
#
# Prerequisites:
#   • SSH access to VPS (119.59.99.163)
#   • APNs .p8 key file downloaded from developer.apple.com
#   • Fill in APNS_KEY_ID and APNS_P8_FILE below
# ============================================================

set -euo pipefail

# ── Config ─────────────────────────────────────────────────────────────────────
VPS_HOST="${VPS_HOST:-119.59.99.163}"
VPS_USER="${VPS_USER:-root}"

APNS_KEY_ID="${APNS_KEY_ID:-}"
APNS_TEAM_ID="${APNS_TEAM_ID:-SNU4S3B885}"
APNS_P8_FILE="${APNS_P8_FILE:-}"
APNS_ENVIRONMENT="${APNS_ENVIRONMENT:-production}"
APNS_STAFF_BUNDLE_ID="${APNS_STAFF_BUNDLE_ID:-AltifaDev.AlphaPosStaff}"
# ──────────────────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${BLUE}[INFO]${NC} $1"; }
ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()  { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ── Validate inputs ────────────────────────────────────────────────────────────
if [ -z "$APNS_KEY_ID" ]; then
    err "Set APNS_KEY_ID before running this script"
fi

if [ -z "$APNS_P8_FILE" ] || [ ! -f "$APNS_P8_FILE" ]; then
    err "APNs .p8 file not found at: $APNS_P8_FILE\nDownload it from: https://developer.apple.com/account/resources/authkeys/list"
fi

if ! grep -q '^-----BEGIN PRIVATE KEY-----$' "$APNS_P8_FILE" || \
   ! grep -q '^-----END PRIVATE KEY-----$' "$APNS_P8_FILE"; then
    err "APNs .p8 file is incomplete or is not a PKCS#8 private key"
fi

if [ "$APNS_ENVIRONMENT" != "sandbox" ] && [ "$APNS_ENVIRONMENT" != "production" ]; then
    err "APNS_ENVIRONMENT must be sandbox or production"
fi

ok "APNs Key ID: $APNS_KEY_ID"
ok "Team ID: $APNS_TEAM_ID"
ok ".p8 file: $APNS_P8_FILE"
ok "Environment: $APNS_ENVIRONMENT"
ok "Bundle ID: $APNS_STAFF_BUNDLE_ID"

log "APNs private key validated"

# ── STEP 1: Upload Edge Function ───────────────────────────────────────────────
echo ""
log "━━━ STEP 1: Upload send-staff-push Edge Function ━━━"

EDGE_FUNC_SRC="$(dirname "$0")/../supabase/functions/send-staff-push/index.ts"
if [ ! -f "$EDGE_FUNC_SRC" ]; then
    err "Edge function not found at: $EDGE_FUNC_SRC"
fi

# Copy function to VPS
ssh "$VPS_USER@$VPS_HOST" "mkdir -p /opt/alphapos/supabase/functions/send-staff-push"
scp "$EDGE_FUNC_SRC" "$VPS_USER@$VPS_HOST:/opt/alphapos/supabase/functions/send-staff-push/index.ts"
ok "Edge function uploaded"

# ── STEP 2: Set APNs Secrets on VPS ───────────────────────────────────────────
echo ""
log "━━━ STEP 2: Configure APNs Secrets ━━━"

scp "$APNS_P8_FILE" "$VPS_USER@$VPS_HOST:/tmp/alphapos-apns-key.p8"

ssh "$VPS_USER@$VPS_HOST" bash -s -- \
    "$APNS_KEY_ID" \
    "$APNS_TEAM_ID" \
    "$APNS_ENVIRONMENT" \
    "$APNS_STAFF_BUNDLE_ID" << 'REMOTE_EOF'
set -e

SECRETS_FILE="/opt/alphapos/supabase/functions/.env"
KEY_ID="$1"
TEAM_ID="$2"
ENVIRONMENT="$3"
BUNDLE_ID="$4"
KEY_FILE="/tmp/alphapos-apns-key.p8"
TMP_FILE=$(mktemp)

grep -v '^APNS_' "$SECRETS_FILE" > "$TMP_FILE" || true
ESCAPED_KEY=$(awk '{ sub(/\r$/, ""); printf "%s\\n", $0 }' "$KEY_FILE")
ESCAPED_KEY=${ESCAPED_KEY%\\n}

{
    printf 'APNS_KEY_ID=%s\n' "$KEY_ID"
    printf 'APNS_TEAM_ID=%s\n' "$TEAM_ID"
    printf 'APNS_ENVIRONMENT=%s\n' "$ENVIRONMENT"
    printf 'APNS_STAFF_BUNDLE_ID=%s\n' "$BUNDLE_ID"
    printf 'APNS_PRIVATE_KEY=%s\n' "$ESCAPED_KEY"
} >> "$TMP_FILE"

install -m 600 "$TMP_FILE" "$SECRETS_FILE"
rm -f "$TMP_FILE" "$KEY_FILE"
echo "APNs secrets updated without replacing unrelated secrets"
REMOTE_EOF

ok "APNs secrets configured on VPS"

# ── STEP 3: Inject secrets into Supabase Edge Function runtime ────────────────
echo ""
log "━━━ STEP 3: Recreate Edge Runtime with current secrets ━━━"

RECREATE_SCRIPT="$(dirname "$0")/../scratch/recreate_edge_runtime_with_activate.py"
scp "$RECREATE_SCRIPT" "$VPS_USER@$VPS_HOST:/tmp/recreate_edge_runtime_with_activate.py"
ssh "$VPS_USER@$VPS_HOST" "python3 /tmp/recreate_edge_runtime_with_activate.py"

# ── STEP 4: Run Database Migration ────────────────────────────────────────────
echo ""
log "━━━ STEP 4: Run Database Migration ━━━"

MIGRATION_FILE="$(dirname "$0")/../supabase/migrations/20260711000400_staff_push_triggers.sql"
ENV_MIGRATION_FILE="$(dirname "$0")/../supabase/migrations/20260714000100_push_device_apns_environment.sql"
if [ ! -f "$MIGRATION_FILE" ]; then
    err "Migration file not found: $MIGRATION_FILE"
fi
if [ ! -f "$ENV_MIGRATION_FILE" ]; then
    err "Migration file not found: $ENV_MIGRATION_FILE"
fi

# Copy migration to VPS
scp "$MIGRATION_FILE" "$VPS_USER@$VPS_HOST:/tmp/staff_push_triggers.sql"
scp "$ENV_MIGRATION_FILE" "$VPS_USER@$VPS_HOST:/tmp/push_device_apns_environment.sql"

# Run migration via psql inside the Supabase Postgres container
ssh "$VPS_USER@$VPS_HOST" bash << 'REMOTE_EOF'
set -e

# Find postgres container
PG_CONTAINER=$(docker ps --format "{{.Names}}" | grep -E "postgres|supabase[-_]db" | head -1)

if [ -z "$PG_CONTAINER" ]; then
    echo "ERROR: Could not find Postgres container"
    docker ps --format "{{.Names}}"
    exit 1
fi

echo "Using Postgres container: $PG_CONTAINER"

# Run the migration
docker exec -i "$PG_CONTAINER" psql -U postgres -d postgres < /tmp/staff_push_triggers.sql
docker exec -i "$PG_CONTAINER" psql -U postgres -d postgres < /tmp/push_device_apns_environment.sql
echo "Migration applied successfully"
REMOTE_EOF

ok "Database migration applied"

# ── STEP 5: Restart Edge Function Runtime ─────────────────────────────────────
echo ""
log "━━━ STEP 5: Verify Edge Function Runtime ━━━"
ssh "$VPS_USER@$VPS_HOST" "docker exec supabase_edge_runtime_AlphaPos true"
ok "Edge runtime is healthy"

# ── STEP 6: Test the Edge Function ────────────────────────────────────────────
echo ""
log "━━━ STEP 6: Test send-staff-push ━━━"

# Get service role key from VPS
SERVICE_ROLE_KEY=$(ssh "$VPS_USER@$VPS_HOST" "docker exec supabase_edge_runtime_AlphaPos printenv SUPABASE_SERVICE_ROLE_KEY")

if [ -z "$SERVICE_ROLE_KEY" ]; then
    warn "Could not auto-detect service role key. Run test manually:"
    echo ""
    echo "  curl -X POST http://${VPS_HOST}/functions/v1/send-staff-push \\"
    echo "    -H 'Authorization: Bearer YOUR_SERVICE_ROLE_KEY' \\"
    echo "    -H 'Content-Type: application/json' \\"
    echo "    -d '{\"event_type\":\"new_order\",\"merchant_id\":\"163350b0-056d-4d5e-b5d4-24e7aac5ab6d\",\"order_number\":\"TEST-001\",\"table_number\":\"1\"}'"
else
    RESPONSE=$(curl -s -X POST "http://${VPS_HOST}/functions/v1/send-staff-push" \
        -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
        -H "Content-Type: application/json" \
        -d "{\"event_type\":\"new_order\",\"merchant_id\":\"163350b0-056d-4d5e-b5d4-24e7aac5ab6d\",\"order_number\":\"TEST-001\",\"table_number\":\"1\"}" 2>&1)
    echo "Test response: $RESPONSE"
fi

# ── Done ───────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  ✅ Push Notification Deployment Complete!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Next steps:"
echo "  1. Build & run AlphaPosStaff on a real iOS device (push needs real device)"
echo "  2. Login to see the Push Notification Settings in More → Push Notification Settings"
echo "  3. Use the 'Send Test Push' button to verify end-to-end delivery"
echo ""
