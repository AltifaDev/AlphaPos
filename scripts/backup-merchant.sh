#!/usr/bin/env bash
# backup-merchant.sh — Per-merchant (per-tenant) backup for the pooled
# multi-tenant database. Exports ONE merchant's data as a portable JSON
# document using the public.export_merchant_data() RPC.
#
# This is the PDPA/GDPR "data portability" artefact and is safe to hand to a
# merchant. It contains only that merchant's rows (RLS-equivalent filtering is
# enforced inside the SECURITY DEFINER function).
#
# Run this ON THE VPS (it talks to the Supabase Postgres container).
#
# Usage:
#   ./backup-merchant.sh <merchant_id> [output_dir]
#
# Environment overrides:
#   PG_CONTAINER  (default: supabase_db_AlphaPos)
#   PG_USER       (default: postgres)
#   PG_DB         (default: postgres)
#
# Examples:
#   ./backup-merchant.sh 163350b0-056d-4d5e-b5d4-24e7aac5ab6d
#   PG_CONTAINER=supabase_db_AlphaPos ./backup-merchant.sh <uuid> /root/tenant-backups

set -euo pipefail

MERCHANT_ID="${1:?usage: backup-merchant.sh <merchant_id> [output_dir]}"
OUT_DIR="${2:-./merchant-backups}"
PG_CONTAINER="${PG_CONTAINER:-supabase_db_AlphaPos}"
PG_USER="${PG_USER:-postgres}"
PG_DB="${PG_DB:-postgres}"

# Basic UUID sanity check.
if ! [[ "$MERCHANT_ID" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
  echo "error: '$MERCHANT_ID' is not a valid merchant UUID" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
TS="$(date +%Y%m%d_%H%M%S)"
OUT_FILE="$OUT_DIR/merchant_${MERCHANT_ID}_${TS}.json"

echo "Exporting merchant $MERCHANT_ID from container $PG_CONTAINER ..."

# -A (unaligned) -t (tuples only) → emit the raw JSON value with no headers.
docker exec -i "$PG_CONTAINER" \
  psql -U "$PG_USER" -d "$PG_DB" -A -t \
  -c "SELECT public.export_merchant_data('${MERCHANT_ID}'::uuid);" \
  > "$OUT_FILE"

if [[ ! -s "$OUT_FILE" ]]; then
  echo "error: export produced an empty file — check the merchant_id and that the migration is applied" >&2
  rm -f "$OUT_FILE"
  exit 1
fi

# Optional: gzip to save space (JSON compresses well).
gzip -f "$OUT_FILE"
echo "Wrote ${OUT_FILE}.gz ($(du -h "${OUT_FILE}.gz" | cut -f1))"
