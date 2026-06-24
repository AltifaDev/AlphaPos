#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
cd "$ROOT_DIR"

project_id() {
  awk -F'"' '/^project_id = / { print $2; exit }' supabase/config.toml
}

lan_ip() {
  local ip
  ip="$(ipconfig getifaddr en0 2>/dev/null || true)"
  [[ -n "$ip" ]] || ip="$(ipconfig getifaddr en1 2>/dev/null || true)"
  [[ -n "$ip" ]] || ip="$(ifconfig | awk '/inet / && $2 !~ /^127\./ { print $2; exit }')"
  [[ -n "$ip" ]] || { print -u2 "Unable to determine the Mac LAN IP"; return 1; }
  print -r -- "$ip"
}

status_value() {
  local key="$1"
  supabase status -o env 2>/dev/null \
    | awk -F= -v wanted="$key" '$1 == wanted { sub(/^[^=]*=/, ""); gsub(/^"|"$/, ""); print; exit }'
}

configure() {
  local project container service_key ip base_url
  project="$(project_id)"
  container="supabase_db_${project}"
  service_key="$(status_value SERVICE_ROLE_KEY)"
  ip="$(lan_ip)"
  base_url="http://${ip}:54321"

  [[ -n "$service_key" ]] || { print -u2 "Supabase is not running or SERVICE_ROLE_KEY is unavailable"; return 1; }

  docker exec -i \
    -e PGPASSWORD=postgres \
    "$container" \
    psql -U postgres -d postgres \
    -v service_key="$service_key" \
    -v edge_url="http://kong:8000" <<'SQL'
DELETE FROM vault.secrets
WHERE name IN ('service_role_key', 'edge_function_base_url');
SELECT vault.create_secret(:'service_key', 'service_role_key');
SELECT vault.create_secret(:'edge_url', 'edge_function_base_url');
SQL

  for plist in \
    "AlphaPos/Supporting Files/Config.plist" \
    "AlphaPosStaff/AlphaPosStaff/Config.plist"; do
    [[ -f "$plist" ]] && /usr/libexec/PlistBuddy -c "Set :SUPABASE_URL $base_url" "$plist"
  done

  if [[ -f customer-order-web/.env ]]; then
    sed -i '' -E "s#^SUPABASE_URL=.*#SUPABASE_URL=${base_url}#" customer-order-web/.env
    sed -i '' -E "s#^ALLOWED_ORIGINS=.*#ALLOWED_ORIGINS=http://${ip}:8080#" customer-order-web/.env
  fi

  print "Configured Local Supabase at $base_url"
}

verify() {
  supabase status
  supabase migration list --local
  supabase db lint --local --level warning
  print "Local Supabase verification passed"
}

backup() {
  local output
  mkdir -p backups
  output="backups/alphapos-$(date +%Y%m%d-%H%M%S).sql"
  supabase db dump --local --file "$output"
  print "Backup written to $output"
}

case "${1:-}" in
  start)
    supabase start
    configure
    ;;
  configure)
    configure
    ;;
  verify)
    verify
    ;;
  backup)
    backup
    ;;
  stop)
    supabase stop
    ;;
  *)
    print "Usage: $0 {start|configure|verify|backup|stop}"
    exit 64
    ;;
esac
