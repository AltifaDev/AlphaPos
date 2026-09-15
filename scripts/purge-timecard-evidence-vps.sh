#!/usr/bin/env bash
set -euo pipefail

DB_CONTAINER="${DB_CONTAINER:-supabase_db_AlphaPos}"
STORAGE_CONTAINER="${STORAGE_CONTAINER:-supabase_storage_AlphaPos}"
STORAGE_API="${STORAGE_API:-http://127.0.0.1:54321/storage/v1}"

service_key="$(docker inspect "$STORAGE_CONTAINER" --format '{{range .Config.Env}}{{println .}}{{end}}' | sed -n 's/^SERVICE_KEY=//p')"
if [[ -z "$service_key" ]]; then
    echo "Missing Storage SERVICE_KEY" >&2
    exit 1
fi

mapfile -t expired_paths < <(
    docker exec "$DB_CONTAINER" psql -U postgres -d postgres -X -Atc \
        "select name from storage.objects where bucket_id = 'timecard-evidence' and created_at < now() - interval '30 days' order by name"
)

removed=0
for object_path in "${expired_paths[@]}"; do
    [[ -n "$object_path" ]] || continue
    curl --fail --silent --show-error --path-as-is \
        -X DELETE \
        -H "apikey: ${service_key}" \
        -H "Authorization: Bearer ${service_key}" \
        "${STORAGE_API}/object/timecard-evidence/${object_path}" >/dev/null
    removed=$((removed + 1))
done

cleared="$(docker exec "$DB_CONTAINER" psql -U postgres -d postgres -X -Atc 'select public.purge_expired_timecard_evidence()')"
echo "timecard evidence retention: removed=${removed} references_cleared=${cleared}"
