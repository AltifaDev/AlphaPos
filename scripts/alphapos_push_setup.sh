#!/bin/bash
# AlphaPosStaff Push Notification Setup Script
# Run this on your VPS: bash /tmp/alphapos_push_setup.sh

set -euo pipefail

# Credentials are deliberately external to this repository. Prefer the safer
# deploy-push-notifications.sh wrapper; direct execution requires these values.
: "${APNS_KEY_ID:?Set APNS_KEY_ID}"
: "${APNS_TEAM_ID:?Set APNS_TEAM_ID}"
: "${APNS_P8_FILE:?Set APNS_P8_FILE to a PKCS#8 key outside the repository}"
APNS_ENVIRONMENT="${APNS_ENVIRONMENT:-production}"
APNS_STAFF_BUNDLE_ID="${APNS_STAFF_BUNDLE_ID:-AltifaDev.AlphaPosStaff}"
APNS_POS_BUNDLE_ID="${APNS_POS_BUNDLE_ID:-AltifaDev.AlphaPos}"

if [ ! -f "$APNS_P8_FILE" ] ||
   ! grep -q '^-----BEGIN PRIVATE KEY-----$' "$APNS_P8_FILE" ||
   ! grep -q '^-----END PRIVATE KEY-----$' "$APNS_P8_FILE"; then
    echo "Invalid APNS_P8_FILE; expected an external PKCS#8 private key" >&2
    exit 1
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${BLUE}[INFO]${NC} $1"; }
ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()  { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  AlphaPosStaff Push Notification Setup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── Step 1: Show running containers ──────────────────────────────────────────
log "Step 1: Docker containers"
docker ps --format "table {{.Names}}\t{{.Status}}" 2>&1
echo ""

# ── Step 2: Install Edge Function ────────────────────────────────────────────
log "Step 2: Installing send-staff-push Edge Function"

EDGE_DIR=""
for dir in /opt/supabase/volumes/functions /opt/supabase/functions /root/supabase/functions /var/lib/supabase/functions; do
    if [ -d "$dir" ]; then
        EDGE_DIR="$dir"
        break
    fi
done

if [ -z "$EDGE_DIR" ]; then
    EDGE_DIR="/opt/supabase/functions"
    mkdir -p "$EDGE_DIR"
    warn "Created new functions directory: $EDGE_DIR"
fi

mkdir -p "$EDGE_DIR/send-staff-push"

cat > "$EDGE_DIR/send-staff-push/index.ts" << 'FUNCEOF'
// send-staff-push/index.ts
// AlphaPosStaff — Universal Push Notification Edge Function
//
// Handles all push event types for the Staff app:
//   • new_order / order_ready / order_served
//   • service_request (customer call for help)
//   • table_occupied / table_vacant
//   • shift_reminder (upcoming shift)
//   • timecard_reminder (clock-in/out reminder)
//   • web_order (new order from customer web app)
//
// Called by:
//   1. PostgreSQL triggers (via pg_net / http_post) on INSERT/UPDATE
//   2. AlphaPos POS app directly (for manual pushes)
//
// Required env vars (set in Supabase Dashboard → Edge Functions → Secrets):
//   SUPABASE_URL              — e.g. https://api.alphaposweb.com
//   SUPABASE_SERVICE_ROLE_KEY — service role key
//   APNS_KEY_ID               — Apple APNs key ID (10 chars)
//   APNS_TEAM_ID              — Apple Developer Team ID (10 chars)
//   APNS_PRIVATE_KEY          — APNs .p8 private key content (with \n escaped as \\n)
//   APNS_ENVIRONMENT          — "production" or "sandbox" (default: sandbox)
//   APNS_STAFF_BUNDLE_ID      — e.g. AltifaDev.AlphaPosStaff

import { createClient } from "npm:@supabase/supabase-js@2";

// ─── Types ────────────────────────────────────────────────────────────────────

interface PushPayload {
  event_type: string;        // "new_order" | "order_ready" | "service_request" | "table_occupied" | etc.
  merchant_id: string;
  order_id?: string;
  order_number?: string;
  table_number?: string;
  request_id?: string;
  request_type?: string;
  employee_id?: string;
  shift_id?: string;
  message?: string;          // Override default message body
  title?: string;            // Override default title
}

interface APNsResult {
  token: string;
  success: boolean;
  status?: number;
  reason?: string;
}

// ─── CORS Headers ─────────────────────────────────────────────────────────────

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
};

// ─── APNs JWT Token (cached up to 55 minutes) ─────────────────────────────────

const encoder = new TextEncoder();
let cachedProviderToken: { value: string; createdAt: number } | null = null;

function base64url(value: Uint8Array | string): string {
  const bytes = typeof value === "string" ? encoder.encode(value) : value;
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

function pemToBytes(pem: string): Uint8Array {
  const body = pem.replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s/g, "");
  return Uint8Array.from(atob(body), (char) => char.charCodeAt(0));
}

async function getProviderToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  // Reuse cached token for up to 55 minutes (APNs tokens expire at 60 min)
  if (cachedProviderToken && now - cachedProviderToken.createdAt < 3300) {
    return cachedProviderToken.value;
  }

  const keyId = Deno.env.get("APNS_KEY_ID");
  const teamId = Deno.env.get("APNS_TEAM_ID");
  const privateKeyRaw = Deno.env.get("APNS_PRIVATE_KEY");

  if (!keyId || !teamId || !privateKeyRaw) {
    throw new Error("APNs credentials are not configured (APNS_KEY_ID, APNS_TEAM_ID, APNS_PRIVATE_KEY required)");
  }

  const privateKey = privateKeyRaw.replaceAll("\\n", "\n");
  const header = base64url(JSON.stringify({ alg: "ES256", kid: keyId }));
  const claims = base64url(JSON.stringify({ iss: teamId, iat: now }));
  const signingInput = `${header}.${claims}`;

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToBytes(privateKey),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(
    await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, encoder.encode(signingInput)),
  );

  const value = `${signingInput}.${base64url(signature)}`;
  cachedProviderToken = { value, createdAt: now };
  return value;
}

// ─── Notification Content Builder ─────────────────────────────────────────────

interface NotificationContent {
  title: string;
  body: string;
  sound: string;
  badge?: number;
  interruptionLevel: string;
  category: string;
  deeplink: string;
  type: string;
}

function buildContent(payload: PushPayload, activeBadgeCount: number): NotificationContent {
  const tbl = payload.table_number ? `Table ${payload.table_number}` : "";
  const ord = payload.order_number ? `Order #${payload.order_number}` : "";

  switch (payload.event_type) {
    case "new_order":
    case "order_new":
      return {
        title: `📝 New ${ord}`,
        body: payload.message ?? (tbl ? `${tbl} placed a new order` : "A new order has been placed"),
        sound: "order_alert.wav",  // fallback to "default" on device if file not found
        badge: activeBadgeCount,
        interruptionLevel: "time-sensitive",
        category: "ORDER",
        deeplink: `order:${payload.order_id ?? ""}`,
        type: "new_order",
      };

    case "order_ready":
      return {
        title: `🍳 ${ord} Ready!`,
        body: payload.message ?? (tbl ? `${tbl} — ready to be served` : "Order is ready to be served"),
        sound: "default",
        badge: activeBadgeCount,
        interruptionLevel: "time-sensitive",
        category: "ORDER",
        deeplink: `order:${payload.order_id ?? ""}`,
        type: "order_ready",
      };

    case "order_served":
      return {
        title: `🍽️ ${ord} Served`,
        body: payload.message ?? (tbl ? `${tbl} has been served` : "Order has been served"),
        sound: "default",
        badge: activeBadgeCount,
        interruptionLevel: "active",
        category: "ORDER",
        deeplink: `order:${payload.order_id ?? ""}`,
        type: "order_served",
      };

    case "order_cancelled":
      return {
        title: `❌ ${ord} Cancelled`,
        body: payload.message ?? (tbl ? `${tbl} cancelled their order` : "An order has been cancelled"),
        sound: "default",
        badge: activeBadgeCount,
        interruptionLevel: "active",
        category: "ORDER",
        deeplink: `order:${payload.order_id ?? ""}`,
        type: "order_cancelled",
      };

    case "web_order":
    case "web_order_new":
      return {
        title: `🌐 Web Order ${ord}`,
        body: payload.message ?? (tbl ? `${tbl} — new web order requires confirmation` : "New web order requires confirmation"),
        sound: "default",
        badge: activeBadgeCount,
        interruptionLevel: "time-sensitive",
        category: "ORDER",
        deeplink: `order:${payload.order_id ?? ""}`,
        type: "web_order",
      };

    case "service_request":
      return {
        title: `🔔 ${tbl || "Customer"}: ${payload.request_type ?? "Assistance Needed"}`,
        body: payload.message ?? "Customer requested staff assistance",
        sound: "default",
        badge: activeBadgeCount,
        interruptionLevel: "time-sensitive",
        category: "SERVICE_REQUEST",
        deeplink: `alert:${payload.request_id ?? ""}`,
        type: "service_request",
      };

    case "table_occupied":
      return {
        title: `🚪 ${tbl || "Table"} Occupied`,
        body: payload.message ?? "A new session has started",
        sound: "default",
        badge: activeBadgeCount,
        interruptionLevel: "active",
        category: "TABLE",
        deeplink: `table:${payload.table_number ?? ""}`,
        type: "table_status",
      };

    case "table_vacant":
      return {
        title: `💳 ${tbl || "Table"} Vacant`,
        body: payload.message ?? "Session ended / table cleared",
        sound: "default",
        badge: activeBadgeCount,
        interruptionLevel: "active",
        category: "TABLE",
        deeplink: `table:${payload.table_number ?? ""}`,
        type: "table_status",
      };

    case "shift_reminder":
      return {
        title: `📅 Shift Starting Soon`,
        body: payload.message ?? "Your shift begins in 30 minutes",
        sound: "default",
        badge: 0,
        interruptionLevel: "active",
        category: "SHIFT",
        deeplink: "schedule",
        type: "schedule",
      };

    case "timecard_reminder":
      return {
        title: `⏰ Clock-In Reminder`,
        body: payload.message ?? "Don't forget to clock in for your shift",
        sound: "default",
        badge: 0,
        interruptionLevel: "active",
        category: "TIMECARD",
        deeplink: "timecard",
        type: "timecard",
      };

    default:
      return {
        title: payload.title ?? "AlphaPos Staff",
        body: payload.message ?? "You have a new notification",
        sound: "default",
        badge: activeBadgeCount,
        interruptionLevel: "active",
        category: "SYSTEM",
        deeplink: "",
        type: "system",
      };
  }
}

// ─── Send Single APNs Push ─────────────────────────────────────────────────────

async function sendAPNs(
  deviceToken: string,
  bundleId: string,
  apnsHost: string,
  providerToken: string,
  content: NotificationContent,
  extraData: Record<string, unknown>,
): Promise<APNsResult> {
  const apsPayload: Record<string, unknown> = {
    aps: {
      alert: {
        title: content.title,
        body: content.body,
      },
      sound: content.sound,
      "interruption-level": content.interruptionLevel,
      "category": content.category,
      ...(content.badge !== undefined ? { badge: content.badge } : {}),
    },
    type: content.type,
    deeplink: content.deeplink,
    ...extraData,
  };

  const response = await fetch(`${apnsHost}/3/device/${deviceToken}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${providerToken}`,
      "apns-topic": bundleId,
      "apns-push-type": "alert",
      "apns-priority": content.interruptionLevel === "time-sensitive" ? "10" : "5",
      "content-type": "application/json",
    },
    body: JSON.stringify(apsPayload),
  });

  if (response.ok) {
    return { token: deviceToken, success: true, status: response.status };
  }

  const detail = await response.json().catch(() => ({})) as { reason?: string };
  return {
    token: deviceToken,
    success: false,
    status: response.status,
    reason: detail.reason,
  };
}

// ─── Main Handler ──────────────────────────────────────────────────────────────

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // ── 1. Parse request body ─────────────────────────────────────────────────
    const body = await req.json() as PushPayload;
    const { event_type, merchant_id } = body;

    if (!event_type || !merchant_id) {
      return new Response(
        JSON.stringify({ error: "Missing required fields: event_type, merchant_id" }),
        { status: 400, headers: { ...corsHeaders, "content-type": "application/json" } },
      );
    }

    // ── 2. Auth check ─────────────────────────────────────────────────────────
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const bearer = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "") ?? "";

    // Allow service role key OR a merchant JWT that matches merchant_id
    const isServiceRole = bearer === serviceKey;
    let isAuthorized = isServiceRole;

    if (!isAuthorized && bearer) {
      try {
        const payloadPart = bearer.split(".")[1];
        if (payloadPart) {
          const normalized = payloadPart.replaceAll("-", "+").replaceAll("_", "/");
          const padded = normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "=");
          const claims = JSON.parse(atob(padded)) as Record<string, unknown>;
          if (
            claims.role === "service_role" ||
            (claims.merchant_id && claims.merchant_id === merchant_id)
          ) {
            isAuthorized = true;
          }
        }
      } catch {
        // Malformed JWT — stay unauthorized
      }
    }

    if (!isAuthorized) {
      return new Response(
        JSON.stringify({ error: "Forbidden" }),
        { status: 403, headers: { ...corsHeaders, "content-type": "application/json" } },
      );
    }

    // ── 3. Fetch active push devices for this merchant (staff app only) ───────
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } });

    // Filter by employee_id when pushing a targeted staff notification (shift/timecard)
    let deviceQuery = admin
      .from("push_devices")
      .select("device_token, app_id, employee_id")
      .eq("merchant_id", merchant_id)
      .eq("is_active", true)
      .eq("app_id", "staff");  // Only Staff app devices

    // If targeting a specific employee, only send to their devices
    if (body.employee_id) {
      deviceQuery = deviceQuery.eq("employee_id", body.employee_id);
    }

    const { data: devices, error: devicesError } = await deviceQuery;

    if (devicesError) {
      throw new Error(`Failed to fetch push devices: ${devicesError.message}`);
    }

    if (!devices || devices.length === 0) {
      return Response.json(
        { delivered: 0, total: 0, message: "No active staff devices registered" },
        { headers: corsHeaders },
      );
    }

    // ── 4. Calculate active badge count ───────────────────────────────────────
    const { count: pendingRequests } = await admin
      .from("service_requests")
      .select("id", { count: "exact", head: true })
      .eq("merchant_id", merchant_id)
      .eq("status", "pending");

    const { count: activeOrders } = await admin
      .from("orders")
      .select("id", { count: "exact", head: true })
      .eq("merchant_id", merchant_id)
      .in("status", ["preparing", "ready"]);

    const badgeCount = (pendingRequests ?? 0) + (activeOrders ?? 0);

    // ── 5. Build notification content ─────────────────────────────────────────
    const content = buildContent(body, badgeCount);

    // ── 6. Get APNs provider token ────────────────────────────────────────────
    let providerToken: string;
    try {
      providerToken = await getProviderToken();
    } catch (err) {
      return Response.json(
        { error: err instanceof Error ? err.message : "APNs credentials not configured" },
        { status: 503, headers: corsHeaders },
      );
    }

    const production = Deno.env.get("APNS_ENVIRONMENT") === "production";
    const apnsHost = production
      ? "https://api.push.apple.com"
      : "https://api.sandbox.push.apple.com";

    const staffBundleId =
      Deno.env.get("APNS_STAFF_BUNDLE_ID") ?? "AltifaDev.AlphaPosStaff";

    // ── 7. Extra data to include in push payload ──────────────────────────────
    const extraData: Record<string, unknown> = {};
    if (body.order_id) extraData.order_id = body.order_id;
    if (body.order_number) extraData.order_number = body.order_number;
    if (body.table_number) extraData.table_number = body.table_number;
    if (body.request_id) extraData.request_id = body.request_id;
    if (body.request_type) extraData.request_type = body.request_type;
    if (body.employee_id) extraData.employee_id = body.employee_id;
    if (body.shift_id) extraData.shift_id = body.shift_id;

    // ── 8. Send to all devices concurrently ──────────────────────────────────
    const results = await Promise.all(
      devices.map((device) =>
        sendAPNs(device.device_token, staffBundleId, apnsHost, providerToken, content, extraData)
      ),
    );

    // ── 9. Deactivate invalid device tokens ──────────────────────────────────
    const invalidTokens = results
      .filter((r) =>
        !r.success &&
        (r.status === 410 || r.status === 400) &&
        ["BadDeviceToken", "Unregistered", "DeviceTokenNotForTopic"].includes(r.reason ?? "")
      )
      .map((r) => r.token);

    if (invalidTokens.length > 0) {
      await admin
        .from("push_devices")
        .update({ is_active: false })
        .in("device_token", invalidTokens);
    }

    const delivered = results.filter((r) => r.success).length;

    return Response.json(
      {
        delivered,
        total: results.length,
        badge_count: badgeCount,
        invalid_tokens_deactivated: invalidTokens.length,
      },
      { headers: corsHeaders },
    );
  } catch (err) {
    console.error("send-staff-push error:", err);
    return Response.json(
      { error: err instanceof Error ? err.message : "Internal error" },
      { status: 500, headers: corsHeaders },
    );
  }
});

FUNCEOF

ok "Edge function installed at: $EDGE_DIR/send-staff-push/index.ts"
echo ""

# ── Step 3: Find and update .env ─────────────────────────────────────────────
log "Step 3: Configuring APNs secrets"

ENV_FILE=""
for f in /opt/supabase/.env /root/supabase/.env /opt/supabase/docker/.env /home/supabase/.env; do
    if [ -f "$f" ]; then
        ENV_FILE="$f"
        break
    fi
done

if [ -z "$ENV_FILE" ]; then
    warn ".env not found, searching..."
    ENV_FILE=$(find /opt /root /home -name ".env" -path "*/supabase/*" 2>/dev/null | head -1)
fi

if [ -z "$ENV_FILE" ]; then
    ENV_FILE="/opt/supabase/.env"
    warn "Creating new .env at $ENV_FILE"
    touch "$ENV_FILE"
fi

ok "Using .env file: $ENV_FILE"

# Remove existing APNs entries
sed -i '/^APNS_/d' "$ENV_FILE"
sed -i '/APNs Push/d' "$ENV_FILE"

# Append APNs secrets without ever embedding key material in source or argv.
TMP_ENV=$(mktemp)
trap 'rm -f "$TMP_ENV"' EXIT
grep -v '^APNS_' "$ENV_FILE" | grep -v 'APNs Push' > "$TMP_ENV" || true
ESCAPED_KEY=$(awk '{ sub(/\r$/, ""); printf "%s\\n", $0 }' "$APNS_P8_FILE")
ESCAPED_KEY=${ESCAPED_KEY%\\n}
{
    printf '\n# APNs Push Notification Secrets\n'
    printf 'APNS_KEY_ID=%s\n' "$APNS_KEY_ID"
    printf 'APNS_TEAM_ID=%s\n' "$APNS_TEAM_ID"
    printf 'APNS_ENVIRONMENT=%s\n' "$APNS_ENVIRONMENT"
    printf 'APNS_STAFF_BUNDLE_ID=%s\n' "$APNS_STAFF_BUNDLE_ID"
    printf 'APNS_POS_BUNDLE_ID=%s\n' "$APNS_POS_BUNDLE_ID"
    printf 'APNS_PRIVATE_KEY=%s\n' "$ESCAPED_KEY"
} >> "$TMP_ENV"
install -m 600 "$TMP_ENV" "$ENV_FILE"
rm -f "$TMP_ENV"
trap - EXIT

ok "APNs secrets written to $ENV_FILE"
echo ""

# ── Step 4: Database migration ───────────────────────────────────────────────
log "Step 4: Running database migration"

PG_CONTAINER=$(docker ps --format "{{.Names}}" | grep -Ei "postgres|supabase.db|supabase-db" | head -1)

if [ -z "$PG_CONTAINER" ]; then
    err "Cannot find Postgres container. Available containers:"
fi

ok "Postgres container: $PG_CONTAINER"

# Set database config
docker exec "$PG_CONTAINER" psql -U postgres -d postgres -c \
    "ALTER DATABASE postgres SET app.settings.supabase_url = 'https://api.alphaposweb.com';" 2>&1

SERVICE_KEY=$(grep -E "^SERVICE_ROLE_KEY|^ANON_KEY" "$ENV_FILE" 2>/dev/null | grep -i "service" | head -1 | cut -d'=' -f2 | tr -d ' "')
if [ -n "$SERVICE_KEY" ]; then
    docker exec "$PG_CONTAINER" psql -U postgres -d postgres -c \
        "ALTER DATABASE postgres SET app.settings.service_role_key = '$SERVICE_KEY';" 2>&1
    ok "Service role key configured"
else
    warn "SERVICE_ROLE_KEY not found — triggers will use empty key (push disabled until set)"
fi

# Write migration SQL to temp file
cat > /tmp/staff_push_migration.sql << 'SQLEOF'
-- ============================================================
-- Migration: Staff Push Notification Triggers
-- Version: 20260711000400
-- Description: Database triggers that call send-staff-push
--              Edge Function automatically on key events.
--
-- Triggers created:
--   1. trg_push_new_order        → orders INSERT (status preparing/pending)
--   2. trg_push_order_status     → orders UPDATE (status changes to ready/served/cancelled)
--   3. trg_push_web_order        → orders INSERT (order_source = 'web')
--   4. trg_push_service_request  → service_requests INSERT (status pending)
--   5. trg_push_table_occupied   → restaurant_tables UPDATE (status → occupied)
--   6. trg_push_table_vacant     → restaurant_tables UPDATE (status → vacant)
--
-- Requires:
--   • pg_net extension (for async HTTP)
--   • supabase_functions schema accessible
-- ============================================================

-- ── Enable pg_net if not already enabled ────────────────────
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

-- ── Helper: build Edge Function URL ─────────────────────────
-- We use current_setting to read the project URL from Supabase
-- internal config. Fallback to VPS URL if not available.
CREATE OR REPLACE FUNCTION private.staff_push_url()
RETURNS text
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(
    current_setting('app.settings.supabase_url', true),
    'https://api.alphaposweb.com'
  ) || '/functions/v1/send-staff-push';
$$;

-- ── Helper: get service role key ────────────────────────────
CREATE OR REPLACE FUNCTION private.service_role_key()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT current_setting('app.settings.service_role_key', true);
$$;

-- ── Helper: generic push caller (async via pg_net) ───────────
-- Returns void — fire-and-forget. Does NOT block the triggering transaction.
CREATE OR REPLACE FUNCTION private.call_staff_push(payload jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_url    text := private.staff_push_url();
  v_key    text := private.service_role_key();
  v_headers jsonb;
BEGIN
  -- Build auth header; if service_role_key is not available skip push
  -- (avoids crashing migrations in dev environments without secrets)
  IF v_key IS NULL OR v_key = '' THEN
    RETURN;
  END IF;

  v_headers := jsonb_build_object(
    'Content-Type',  'application/json',
    'Authorization', 'Bearer ' || v_key,
    'apikey',        v_key
  );

  -- Async HTTP POST — does not block the caller
  PERFORM extensions.http_post(
    url     := v_url,
    body    := payload::text,
    headers := v_headers::text
  );

EXCEPTION WHEN OTHERS THEN
  -- Never fail the triggering transaction due to push errors
  RAISE WARNING 'staff_push: HTTP call failed: %', SQLERRM;
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- TRIGGER 1: New Order (INSERT, status = preparing or pending)
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION private.trg_fn_push_new_order()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Only fire for POS orders (not web orders — handled by separate trigger)
  IF NEW.status IN ('preparing', 'pending')
     AND (NEW.order_source IS DISTINCT FROM 'web') THEN
    PERFORM private.call_staff_push(jsonb_build_object(
      'event_type',   'new_order',
      'merchant_id',  NEW.merchant_id::text,
      'order_id',     NEW.id::text,
      'order_number', NEW.order_number::text,
      'table_number', NEW.table_number
    ));
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_push_new_order ON public.orders;
CREATE TRIGGER trg_push_new_order
  AFTER INSERT ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION private.trg_fn_push_new_order();

-- ─────────────────────────────────────────────────────────────
-- TRIGGER 2: Order Status Change (UPDATE → ready / served / cancelled)
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION private.trg_fn_push_order_status()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_event text;
BEGIN
  -- Only fire when status actually changes
  IF OLD.status = NEW.status THEN
    RETURN NEW;
  END IF;

  CASE NEW.status
    WHEN 'ready'     THEN v_event := 'order_ready';
    WHEN 'served'    THEN v_event := 'order_served';
    WHEN 'cancelled' THEN v_event := 'order_cancelled';
    ELSE v_event := NULL;
  END CASE;

  IF v_event IS NOT NULL THEN
    PERFORM private.call_staff_push(jsonb_build_object(
      'event_type',   v_event,
      'merchant_id',  NEW.merchant_id::text,
      'order_id',     NEW.id::text,
      'order_number', NEW.order_number::text,
      'table_number', NEW.table_number
    ));
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_push_order_status ON public.orders;
CREATE TRIGGER trg_push_order_status
  AFTER UPDATE OF status ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION private.trg_fn_push_order_status();

-- ─────────────────────────────────────────────────────────────
-- TRIGGER 3: Web Order (INSERT, order_source = 'web')
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION private.trg_fn_push_web_order()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF NEW.order_source = 'web' AND NEW.status IN ('pending', 'preparing') THEN
    PERFORM private.call_staff_push(jsonb_build_object(
      'event_type',   'web_order',
      'merchant_id',  NEW.merchant_id::text,
      'order_id',     NEW.id::text,
      'order_number', NEW.order_number::text,
      'table_number', NEW.table_number,
      'message',      'New web order requires staff confirmation'
    ));
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_push_web_order ON public.orders;
CREATE TRIGGER trg_push_web_order
  AFTER INSERT ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION private.trg_fn_push_web_order();

-- ─────────────────────────────────────────────────────────────
-- TRIGGER 4: Service Request (INSERT, status = pending)
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION private.trg_fn_push_service_request()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF NEW.status = 'pending' THEN
    PERFORM private.call_staff_push(jsonb_build_object(
      'event_type',   'service_request',
      'merchant_id',  NEW.merchant_id::text,
      'request_id',   NEW.id::text,
      'table_number', NEW.table_number,
      'request_type', NEW.request_type
    ));
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_push_service_request ON public.service_requests;
CREATE TRIGGER trg_push_service_request
  AFTER INSERT ON public.service_requests
  FOR EACH ROW
  EXECUTE FUNCTION private.trg_fn_push_service_request();

-- ─────────────────────────────────────────────────────────────
-- TRIGGER 5 & 6: Table Status Changes (occupied / vacant)
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION private.trg_fn_push_table_status()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_event text;
BEGIN
  IF OLD.status = NEW.status THEN
    RETURN NEW;
  END IF;

  IF NEW.status = 'occupied' THEN
    v_event := 'table_occupied';
  ELSIF NEW.status = 'vacant' AND OLD.status = 'occupied' THEN
    v_event := 'table_vacant';
  ELSE
    RETURN NEW;
  END IF;

  PERFORM private.call_staff_push(jsonb_build_object(
    'event_type',   v_event,
    'merchant_id',  NEW.merchant_id::text,
    'table_number', NEW.table_number
  ));

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_push_table_status ON public.restaurant_tables;
CREATE TRIGGER trg_push_table_status
  AFTER UPDATE OF status ON public.restaurant_tables
  FOR EACH ROW
  EXECUTE FUNCTION private.trg_fn_push_table_status();

-- ─────────────────────────────────────────────────────────────
-- Ensure employee_id column exists in push_devices
-- (needed for targeted shift/timecard notifications)
-- ─────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name   = 'push_devices'
      AND column_name  = 'employee_id'
  ) THEN
    ALTER TABLE public.push_devices
      ADD COLUMN employee_id uuid REFERENCES public.employees(id) ON DELETE SET NULL;
    COMMENT ON COLUMN public.push_devices.employee_id IS
      'Logged-in employee who owns this device session. NULL means any staff member.';
  END IF;
END;
$$;

-- Index for employee-targeted pushes
CREATE INDEX IF NOT EXISTS idx_push_devices_employee_id
  ON public.push_devices(employee_id)
  WHERE employee_id IS NOT NULL;

-- ─────────────────────────────────────────────────────────────
-- Grant execute on helper functions to service_role
-- ─────────────────────────────────────────────────────────────
GRANT EXECUTE ON FUNCTION private.call_staff_push(jsonb)      TO service_role;
GRANT EXECUTE ON FUNCTION private.staff_push_url()             TO service_role;
GRANT EXECUTE ON FUNCTION private.trg_fn_push_new_order()      TO service_role;
GRANT EXECUTE ON FUNCTION private.trg_fn_push_order_status()   TO service_role;
GRANT EXECUTE ON FUNCTION private.trg_fn_push_web_order()      TO service_role;
GRANT EXECUTE ON FUNCTION private.trg_fn_push_service_request() TO service_role;
GRANT EXECUTE ON FUNCTION private.trg_fn_push_table_status()   TO service_role;

SQLEOF

# Run migration
docker exec -i "$PG_CONTAINER" psql -U postgres -d postgres < /tmp/staff_push_migration.sql
ok "Migration applied"
echo ""

# ── Step 5: Verify triggers ───────────────────────────────────────────────────
log "Step 5: Verifying triggers"
docker exec "$PG_CONTAINER" psql -U postgres -d postgres -c "
SELECT trigger_name, event_object_table, event_manipulation 
FROM information_schema.triggers 
WHERE trigger_name LIKE 'trg_push_%'
ORDER BY event_object_table, trigger_name;
"
echo ""

# ── Step 6: Restart edge runtime ─────────────────────────────────────────────
log "Step 6: Restarting Edge Runtime"
EDGE_CONTAINER=$(docker ps --format "{{.Names}}" | grep -Ei "edge|function" | head -1)

if [ -n "$EDGE_CONTAINER" ]; then
    docker restart "$EDGE_CONTAINER"
    ok "Restarted: $EDGE_CONTAINER"
    sleep 3
else
    warn "Edge runtime container not found — you may need to restart manually"
    docker ps --format "{{.Names}}"
fi
echo ""

# ── Done ──────────────────────────────────────────────────────────────────────
SERVICE_KEY2=$(grep -E "^SERVICE_ROLE_KEY" "$ENV_FILE" 2>/dev/null | head -1 | cut -d'=' -f2 | tr -d ' "')

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅ Setup Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Test the edge function:"
echo "curl -X POST https://api.alphaposweb.com/functions/v1/send-staff-push \\"
echo "  -H \"Authorization: Bearer $SERVICE_KEY2\" \\"
echo "  -H \"Content-Type: application/json\" \\"
echo "  -d '{"event_type":"new_order","merchant_id":"163350b0-056d-4d5e-b5d4-24e7aac5ab6d","order_number":"TEST-001","table_number":"1"}'"
echo ""
echo "Then build AlphaPosStaff on a real iOS device and use the Test Push button!"
