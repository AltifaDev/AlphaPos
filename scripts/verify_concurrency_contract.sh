#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

require_pattern() {
  local pattern="$1" file="$2" label="$3"
  if ! /usr/bin/grep -Eq "$pattern" "$ROOT_DIR/$file"; then
    echo "Concurrency contract failed: $label ($file)"
    exit 1
  fi
}

require_pattern 'endpoint:.*"rpc/create_order_atomic_cas"' 'AlphaPos/Data/Remote/NetworkManager+Orders.swift' 'orders must use atomic CAS RPC'
require_pattern 'expected_row_version' 'AlphaPos/Data/Remote/NetworkManager+Orders.swift' 'orders must send expected revisions'
require_pattern 'var rowVersion: Int' 'AlphaPos/Models/Order.swift' 'order must persist server revision'
require_pattern 'endpoint: "rpc/upsert_purchase_order_atomic_cas"' 'AlphaPos/Data/Remote/NetworkManager+Inventory.swift' 'purchase orders must use atomic CAS RPC'
require_pattern 'expected_row_version' 'AlphaPos/Data/Remote/NetworkManager+Inventory.swift' 'purchase orders must send expected revisions'
require_pattern '"is_deleted": item.isDeleted' 'AlphaPos/Data/Remote/NetworkManager+Inventory.swift' 'purchase-order line tombstones must propagate'
require_pattern 'CREATE OR REPLACE FUNCTION public.create_order_atomic_cas' 'supabase/migrations/20260825000300_order_kds_cas_rpc.sql' 'order CAS migration missing'
require_pattern 'CREATE OR REPLACE FUNCTION public.upsert_purchase_order_atomic_cas' 'supabase/migrations/20260825000400_purchase_order_atomic_cas.sql' 'purchase-order CAS migration missing'
require_pattern "USING ERRCODE = '40001'" 'supabase/migrations/20260825000400_purchase_order_atomic_cas.sql' 'purchase-order conflicts must be retryable serialization failures'
require_pattern 'CREATE TABLE IF NOT EXISTS public.sync_conflict_journal' 'supabase/migrations/20260825000200_operational_optimistic_concurrency.sql' 'durable server conflict journal missing'
require_pattern 'endpoint: "sync_conflict_journal"' 'AlphaPos/Data/Remote/NetworkManager+ConflictJournal.swift' 'CAS conflicts must append to the server journal'
require_pattern 'endpoint: "rpc/upsert_table_session_cas"' 'AlphaPos/Data/Remote/NetworkManager+FloorPlan.swift' 'table sessions must use CAS RPC'
require_pattern 'CREATE OR REPLACE FUNCTION public.upsert_table_session_cas' 'supabase/migrations/20260825000500_table_session_cas.sql' 'table-session CAS migration missing'

echo 'Concurrency contract verification passed'
