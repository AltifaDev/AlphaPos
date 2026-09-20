#!/usr/bin/env bash
# backup-production.sh — Automated Full & Multi-Tenant Backup
#
# Generates:
#   1. PostgreSQL binary custom-format dump (schema + all table data)
#   2. Plain SQL schema-only dump (DDL structure & migrations)
#   3. Per-tenant JSON portability exports (via public.export_merchant_data)
#   4. SHA256 checksums file for data integrity verification
#
# Usage:
#   ./scripts/backup-production.sh [output_dir]
#
# Environment variables:
#   PG_CONTAINER   (default: supabase_db_AlphaPos)
#   PG_USER        (default: postgres)
#   PG_DB          (default: postgres)

set -euo pipefail

BACKUP_ROOT="${1:-/opt/alphapos/backups}"
TS="$(date +%Y%m%d_%H%M%S)"
TARGET_DIR="${BACKUP_ROOT}/${TS}"
PG_CONTAINER="${PG_CONTAINER:-supabase_db_AlphaPos}"
PG_USER="${PG_USER:-postgres}"
PG_DB="${PG_DB:-postgres}"

mkdir -p "${TARGET_DIR}/tenants"
chmod 0700 "${TARGET_DIR}"

echo "========================================================"
echo " AlphaPos Production Backup: ${TS}"
echo " Container: ${PG_CONTAINER} | Target: ${TARGET_DIR}"
echo "========================================================"

# 1. Binary Custom-format PostgreSQL dump (-Fc)
echo "[1/4] Creating PostgreSQL custom dump..."
CUSTOM_DUMP="${TARGET_DIR}/alphapos_${TS}.dump"
docker exec -i "${PG_CONTAINER}" pg_dump -U "${PG_USER}" -d "${PG_DB}" -Fc -Z 6 > "${CUSTOM_DUMP}"
chmod 0600 "${CUSTOM_DUMP}"
echo "      Custom dump: $(du -h "${CUSTOM_DUMP}" | cut -f1)"

# 2. Schema-only SQL dump
echo "[2/4] Exporting plain schema SQL..."
SCHEMA_SQL="${TARGET_DIR}/alphapos_schema_${TS}.sql"
docker exec -i "${PG_CONTAINER}" pg_dump -U "${PG_USER}" -d "${PG_DB}" --schema-only > "${SCHEMA_SQL}"
gzip -f "${SCHEMA_SQL}"
chmod 0600 "${SCHEMA_SQL}.gz"
echo "      Schema dump: $(du -h "${SCHEMA_SQL}.gz" | cut -f1)"

# 3. Multi-Tenant Isolated Portability Backups
echo "[3/4] Exporting active merchant tenant JSONs..."
MERCHANT_IDS=$(docker exec -i "${PG_CONTAINER}" psql -U "${PG_USER}" -d "${PG_DB}" -A -t \
  -c "SELECT id FROM public.merchants WHERE is_active = true OR is_deleted = false;" || true)

for MID in $MERCHANT_IDS; do
  if [[ "$MID" =~ ^[0-9a-fA-F-]{36}$ ]]; then
    TENANT_FILE="${TARGET_DIR}/tenants/merchant_${MID}.json"
    docker exec -i "${PG_CONTAINER}" psql -U "${PG_USER}" -d "${PG_DB}" -A -t \
      -c "SELECT public.export_merchant_data('${MID}'::uuid);" > "${TENANT_FILE}" || true
    if [[ -s "${TENANT_FILE}" ]]; then
      gzip -f "${TENANT_FILE}"
    else
      rm -f "${TENANT_FILE}"
    fi
  fi
done
echo "      Tenant dumps exported to ${TARGET_DIR}/tenants"

# 4. Checksums for tamper detection & archive validation
echo "[4/4] Generating SHA256 integrity checksums..."
(
  cd "${TARGET_DIR}"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum alphapos_*.* tenants/*.json.gz > CHECKSUMS.sha256
  else
    shasum -a 256 alphapos_*.* tenants/*.json.gz > CHECKSUMS.sha256
  fi
)
chmod 0600 "${TARGET_DIR}/CHECKSUMS.sha256"

# Retain 14 days of backups locally
find "${BACKUP_ROOT}" -maxdepth 1 -mindepth 1 -type d -mtime +14 -exec rm -rf {} + 2>/dev/null || true

echo "========================================================"
echo " Backup successfully completed at ${TARGET_DIR}"
echo "========================================================"
