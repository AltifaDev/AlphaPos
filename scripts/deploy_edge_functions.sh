#!/usr/bin/env bash
# deploy_edge_functions.sh
# Deploy Supabase Edge Functions ไปยัง self-hosted VPS Docker
#
# Usage:
#   ./scripts/deploy_edge_functions.sh                    # deploy ทุก function
#   ./scripts/deploy_edge_functions.sh parse-stock-receipt  # deploy เฉพาะ function เดียว
#
# Requirements: ssh key หรือ sshpass สำหรับ password auth

set -e

VPS_HOST="${VPS_HOST:-119.59.99.163}"
VPS_USER="${VPS_USER:-root}"
VPS_PORT="${VPS_PORT:-22}"
CONTAINER="${CONTAINER:-supabase_edge_runtime_AlphaPos}"
REMOTE_FUNC_DIR="${REMOTE_FUNC_DIR:-/opt/alphapos/supabase/functions}"
LOCAL_FUNC_DIR="$(cd "$(dirname "$0")/.." && pwd)/supabase/functions"

SSH_CMD="ssh -p $VPS_PORT -o StrictHostKeyChecking=no -o ConnectTimeout=10"
SCP_CMD="scp -P $VPS_PORT -o StrictHostKeyChecking=no -o ConnectTimeout=10"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " 🚀 AlphaPos Edge Function Deploy"
echo "    VPS: $VPS_USER@$VPS_HOST:$VPS_PORT"
echo "    Container: $CONTAINER"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── ตรวจ local function dir ──────────────────────────────────────────────────
if [ ! -d "$LOCAL_FUNC_DIR" ]; then
  echo "❌ ไม่พบ $LOCAL_FUNC_DIR"
  exit 1
fi

# ── เลือก functions ที่จะ deploy ─────────────────────────────────────────────
if [ -n "$1" ]; then
  FUNCS=("$1")
  echo "📦 Deploy เฉพาะ: $1"
else
  # หา subdirectory ทั้งหมดใน functions/ (ยกเว้น _shared)
  mapfile -t FUNCS < <(find "$LOCAL_FUNC_DIR" -mindepth 1 -maxdepth 1 -type d \
    ! -name '_*' ! -name '.*' -exec basename {} \;)
  echo "📦 Deploy ทั้งหมด: ${FUNCS[*]}"
fi

echo ""

# ── Deploy แต่ละ function ────────────────────────────────────────────────────
DEPLOYED=()
FAILED=()

for FUNC in "${FUNCS[@]}"; do
  SRC="$LOCAL_FUNC_DIR/$FUNC"

  if [ ! -d "$SRC" ]; then
    echo "⚠️  ไม่พบ function: $FUNC (ข้าม)"
    continue
  fi

  echo "→ Deploying $FUNC ..."

  # Functions are bind-mounted from the VPS host into edge-runtime.
  $SSH_CMD "$VPS_USER@$VPS_HOST" \
    "mkdir -p $REMOTE_FUNC_DIR/$FUNC"

  # copy index.ts (และไฟล์อื่นๆ ถ้ามี)
  for FILE in "$SRC"/*.ts "$SRC"/*.js "$SRC"/*.json; do
    [ -f "$FILE" ] || continue
    FNAME=$(basename "$FILE")
    $SCP_CMD "$FILE" "$VPS_USER@$VPS_HOST:$REMOTE_FUNC_DIR/$FUNC/$FNAME" && \
      echo "   ✅ $FNAME" || { echo "   ❌ $FNAME ล้มเหลว"; FAILED+=("$FUNC"); continue 2; }
  done

  DEPLOYED+=("$FUNC")
done

# ── Restart edge runtime ──────────────────────────────────────────────────────
echo ""
if [ ${#DEPLOYED[@]} -gt 0 ]; then
  echo "🔄 Restarting $CONTAINER ..."
  $SSH_CMD "$VPS_USER@$VPS_HOST" "docker restart $CONTAINER" && \
    echo "✅ Restart สำเร็จ" || echo "⚠️  Restart ล้มเหลว — ลอง restart เอง"

  echo ""
  echo "📋 Logs (10 วินาทีหลัง restart):"
  sleep 3
  $SSH_CMD "$VPS_USER@$VPS_HOST" "docker logs --tail 20 $CONTAINER 2>&1"
fi

# ── สรุปผล ───────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
[ ${#DEPLOYED[@]} -gt 0 ] && echo "✅ สำเร็จ  : ${DEPLOYED[*]}"
[ ${#FAILED[@]}   -gt 0 ] && echo "❌ ล้มเหลว : ${FAILED[*]}" && exit 1
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
