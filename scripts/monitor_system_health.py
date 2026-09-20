#!/usr/bin/env python3
"""
scripts/monitor_system_health.py
AlphaPos Production Telemetry & System Monitoring Utility

Monitors:
  - Active DB connection pool saturation & headroom
  - Lock waits and slow-running queries (>1s)
  - sync_outbox queue backlog, processing lag, and Dead-Letter Queue (DLQ)
  - Optimistic locking conflicts (last 1 hour)
  - Excessive void/refund operations
  - PostgREST / HTTP 5xx indicators

Usage:
  python3 scripts/monitor_system_health.py [--url SUPABASE_URL] [--key SERVICE_KEY] [--json] [--alert-webhook URL]
"""

import os
import sys
import json
import argparse
import urllib.request
import urllib.error
from datetime import datetime

DEFAULT_URL = os.environ.get("SUPABASE_URL", "http://127.0.0.1:54321")
DEFAULT_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", os.environ.get("SUPABASE_ANON_KEY", ""))

def fetch_metrics(base_url: str, key: str):
    endpoint = f"{base_url.rstrip('/')}/rest/v1/rpc/get_system_production_metrics"
    req = urllib.request.Request(
        endpoint,
        data=b"{}",
        headers={
            "Content-Type": "application/json",
            "apikey": key,
            "Authorization": f"Bearer {key}",
            "Prefer": "return=representation"
        },
        method="POST"
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = resp.read()
            return json.loads(data.decode("utf-8")), resp.status
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8")
        return {"error": f"HTTP {e.code}: {body}", "ok": False}, e.code
    except Exception as e:
        return {"error": str(e), "ok": False}, 0

def format_report(metrics: dict) -> str:
    if not metrics.get("ok"):
        return f"[CRITICAL ERROR] Failed to fetch telemetry: {metrics.get('error')}"

    health = metrics.get("overall_health", "unknown").upper()
    health_badge = "🟢 HEALTHY" if health == "HEALTHY" else ("🟡 WARNING" if health == "WARNING" else "🔴 CRITICAL")
    
    db = metrics.get("database", {})
    outbox = metrics.get("outbox_queue", {})
    sec = metrics.get("concurrency_and_security", {})
    alerts = metrics.get("alerts", [])

    lines = [
        "=" * 60,
        f" AlphaPos Production System Telemetry — {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
        f" Overall Status: {health_badge}",
        "=" * 60,
        "",
        "📊 Database Connections & Engine:",
        f"  • Connections: {db.get('active_connections', 0)} active / {db.get('total_connections', 0)} total (Max: {db.get('max_connections', 0)})",
        f"  • Pool Utilization: {db.get('pool_utilization_pct', 0.0)}%",
        f"  • Lock Waits: {db.get('lock_waits', 0)} blocked queries",
        f"  • Slow Queries (>1s): {db.get('slow_queries_1s', 0)} queries",
        "",
        "📬 Outbox & Hardware Queue:",
        f"  • Pending: {outbox.get('pending', 0)} | Processing: {outbox.get('processing', 0)}",
        f"  • Failed Retries: {outbox.get('failed', 0)} | Dead-Letter (DLQ): {outbox.get('dead_letter', 0)}",
        f"  • Oldest Pending Age: {outbox.get('oldest_pending_age_sec', 0)}s",
        f"  • Oldest Stuck Processing: {outbox.get('oldest_processing_age_sec', 0)}s",
        "",
        "🔒 Concurrency & Anti-Fraud (Last 1 Hour):",
        f"  • Optimistic Lock Conflicts: {sec.get('conflicts_last_hour', 0)}",
        f"  • Voided Items / Cancellations: {sec.get('voids_last_hour', 0)}",
        f"  • Customer Refunds: {sec.get('refunds_last_hour', 0)}",
    ]

    if alerts:
        lines.append("")
        lines.append("⚠️ Active Alerts:")
        for alert in alerts:
            lvl = alert.get('level', '').upper()
            msg = alert.get('message', '')
            lines.append(f"  [{lvl}] {msg}")

    lines.append("=" * 60)
    return "\n".join(lines)

def send_alert_webhook(webhook_url: str, metrics: dict):
    if not webhook_url:
        return
    payload = {
        "text": f"AlphaPos Alert [{metrics.get('overall_health', '').upper()}]:\n" + "\n".join(
            [a.get('message', '') for a in metrics.get('alerts', [])]
        )
    }
    req = urllib.request.Request(
        webhook_url,
        data=json.dumps(payload).encode('utf-8'),
        headers={"Content-Type": "application/json"},
        method="POST"
    )
    try:
        urllib.request.urlopen(req, timeout=5)
    except Exception as e:
        print(f"Warning: Failed to send webhook alert: {e}", file=sys.stderr)

def main():
    parser = argparse.ArgumentParser(description="AlphaPos System Monitoring Telemetry")
    parser.add_argument("--url", default=DEFAULT_URL, help="Supabase API URL")
    parser.add_argument("--key", default=DEFAULT_KEY, help="Service Role or Anon API Key")
    parser.add_argument("--json", action="store_true", help="Emit raw JSON")
    parser.add_argument("--alert-webhook", help="Webhook URL (Slack/Discord/Telegram) for alerts")
    args = parser.parse_args()

    metrics, status = fetch_metrics(args.url, args.key)
    if args.json:
        print(json.dumps(metrics, indent=2))
    else:
        print(format_report(metrics))

    if metrics.get("overall_health") in ("warning", "critical") and args.alert_webhook:
        send_alert_webhook(args.alert_webhook, metrics)

    sys.exit(0 if metrics.get("overall_health") == "healthy" else 1)

if __name__ == "__main__":
    main()
