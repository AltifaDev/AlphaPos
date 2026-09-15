#!/usr/bin/env bash
# Open (or check) the SSH tunnel for Cursor → VPS Supabase Studio MCP.
# Local:  http://127.0.0.1:18080/api/mcp
# Remote: Studio container via host port 54323
set -euo pipefail

LOCAL_PORT=18080
SSH_HOST=alphapos-vps-mcp

usage() {
  cat <<EOF
Usage: $(basename "$0") [start|stop|status|test]

  start   Open SSH tunnel (default)
  stop    Close tunnel listening on :${LOCAL_PORT}
  status  Show whether tunnel is up
  test    POST MCP initialize over the tunnel
EOF
}

pids_on_port() {
  lsof -tiTCP:"$LOCAL_PORT" -sTCP:LISTEN 2>/dev/null || true
}

cmd_status() {
  local pids
  pids="$(pids_on_port)"
  if [[ -n "$pids" ]]; then
    echo "Tunnel UP on 127.0.0.1:${LOCAL_PORT} (pid: $pids)"
    return 0
  fi
  echo "Tunnel DOWN (nothing listening on ${LOCAL_PORT})"
  return 1
}

cmd_stop() {
  local pids
  pids="$(pids_on_port)"
  if [[ -z "$pids" ]]; then
    echo "No tunnel on ${LOCAL_PORT}"
    return 0
  fi
  # shellcheck disable=SC2086
  kill $pids 2>/dev/null || true
  sleep 0.5
  echo "Stopped tunnel on ${LOCAL_PORT}"
}

cmd_start() {
  if pids_on_port >/dev/null && [[ -n "$(pids_on_port)" ]]; then
    echo "Already running:"
    cmd_status
    return 0
  fi
  ssh -f -N "$SSH_HOST"
  sleep 0.5
  cmd_status
}

cmd_test() {
  cmd_status || cmd_start
  curl -sS -w '\nHTTP=%{http_code}\n' "http://127.0.0.1:${LOCAL_PORT}/api/mcp" \
    -X POST \
    -H 'Content-Type: application/json' \
    -H 'Accept: application/json, text/event-stream' \
    -H 'MCP-Protocol-Version: 2025-06-18' \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"tunnel-test","version":"1.0.0"}}}'
  echo
}

case "${1:-start}" in
  start) cmd_start ;;
  stop) cmd_stop ;;
  status) cmd_status ;;
  test) cmd_test ;;
  -h|--help|help) usage ;;
  *) usage; exit 1 ;;
esac
