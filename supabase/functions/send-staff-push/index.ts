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
  event_type: string;        // "new_order" | "order_ready" | "service_request" | "table_occupied" | "inventory_alert" | etc.
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
  inventory_item_id?: string;
  inventory_item_name?: string;
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

function buildContent(payload: PushPayload, activeBadgeCount: number, languageCode = "en"): NotificationContent {
  const thai = languageCode === "th";
  const lao = languageCode === "lo";
  const tbl = payload.table_number ? (thai ? `โต๊ะ ${payload.table_number}` : lao ? `ໂຕະ ${payload.table_number}` : `Table ${payload.table_number}`) : "";
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
        body: payload.message ?? (tbl ? `${tbl} — web order received` : "New web order received"),
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
        title: `🚪 ${tbl || (thai ? "โต๊ะ" : lao ? "ໂຕະ" : "Table")} ${thai ? "มีลูกค้าเข้าใช้บริการ" : lao ? "ມີລູກຄ້າເຂົ້າໃຊ້ບໍລິການ" : "Occupied"}`,
        body: payload.message ?? (thai ? "เริ่มรอบการใช้งานใหม่แล้ว" : lao ? "ເລີ່ມຮອບການໃຊ້ງານໃໝ່ແລ້ວ" : "A new session has started"),
        sound: "default",
        badge: activeBadgeCount,
        interruptionLevel: "active",
        category: "TABLE",
        deeplink: `table:${payload.table_number ?? ""}`,
        type: "table_status",
      };

    case "table_vacant":
      return {
        title: `💳 ${tbl || (thai ? "โต๊ะ" : lao ? "ໂຕະ" : "Table")} ${thai ? "ว่าง" : lao ? "ຫວ່າງ" : "Vacant"}`,
        body: payload.message ?? (thai ? "จบรอบการใช้งาน / เคลียร์โต๊ะแล้ว" : lao ? "ຈົບຮອບການໃຊ້ງານ / ເຄຍໂຕະແລ້ວ" : "Session ended / table cleared"),
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

    case "inventory_alert":
    case "inventory_low":
    case "inventory_out": {
      const itemName = payload.inventory_item_name ?? payload.message ?? "Stock item";
      const itemId = payload.inventory_item_id ?? "";
      const isOut = payload.event_type === "inventory_out"
        || (payload.title ?? "").toLowerCase().includes("out");
      return {
        title: payload.title ?? (isOut ? "📦 Out of Stock" : "📦 Low Stock"),
        body: payload.message ?? `${itemName} needs attention`,
        sound: "default",
        badge: activeBadgeCount,
        interruptionLevel: isOut ? "time-sensitive" : "active",
        category: "INVENTORY",
        deeplink: itemId ? `inventory:${itemId}` : "inventory",
        type: "inventory_alert",
      };
    }

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

    // Staff iPhones receive only actionable operational events. The master
    // iPad uses the POS channel and is intentionally not affected here.
    const staffActionableEvents = new Set([
      "new_order", "order_new", "web_order", "web_order_new",
      "order_ready", "order_cancelled", "service_request", "urgent",
    ]);
    if (!staffActionableEvents.has(body.event_type)) {
      return Response.json(
        { delivered: 0, total: 0, suppressed: true, reason: "non_actionable_staff_event" },
        { headers: corsHeaders },
      );
    }

    // Filter by employee_id when pushing a targeted staff notification (shift/timecard)
    let deviceQuery = admin
      .from("push_devices")
      .select("device_token, app_id, employee_id, environment, language_code")
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

    // A staff device is eligible only while its employee has an open
    // timecard. This is enforced server-side so it also works when the app is
    // closed and prevents stale device registrations from receiving pushes.
    const { data: activeTimecards, error: timecardError } = await admin
      .from("timecards")
      .select("employee_id")
      .eq("merchant_id", merchant_id)
      .is("clock_out", null)
      .lte("clock_in", new Date().toISOString());
    if (timecardError) throw new Error(`Failed to check active timecards: ${timecardError.message}`);
    const activeEmployeeIds = new Set((activeTimecards ?? []).map((row) => row.employee_id));
    const eligibleDevices = (devices ?? []).filter((device) =>
      typeof device.employee_id === "string" && activeEmployeeIds.has(device.employee_id)
    );

    if (eligibleDevices.length === 0) {
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
      .in("status", ["pending", "preparing", "cooking", "ready"]);

    const badgeCount = (pendingRequests ?? 0) + (activeOrders ?? 0);

    // ── 5. Build notification content ─────────────────────────────────────────

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

    const defaultEnvironment = Deno.env.get("APNS_ENVIRONMENT") ?? "production";

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
      eligibleDevices.map((device) => {
        const environment = device.environment ?? defaultEnvironment;
        const apnsHost = environment === "sandbox"
          ? "https://api.sandbox.push.apple.com"
          : "https://api.push.apple.com";
        const content = buildContent(body, badgeCount, device.language_code ?? "en");
        return sendAPNs(device.device_token, staffBundleId, apnsHost, providerToken, content, extraData);
      }),
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
        failures: results.filter((r) => !r.success).map((r) => ({ status: r.status, reason: r.reason })),
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
