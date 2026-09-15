/**
 * AlphaPos — Merchant JWT Token Issuer (Edge Function)
 *
 * Issues a per-merchant JWT containing `merchant_id` in its claims.
 * Supabase PostgREST and Realtime automatically extract this claim via
 * `current_setting('request.jwt.claims')`, so RLS policies that call
 * `get_merchant_id()` work without any custom HTTP header.
 *
 * Environment Variables (set via `supabase secrets set`):
 *   SUPABASE_URL           — project URL (auto-injected by Supabase)
 *   SUPABASE_SERVICE_ROLE_KEY — service role key (auto-injected by Supabase)
 *   ALPHAPOS_JWT_SECRET    — Supabase JWT secret (Settings → API → JWT Settings)
 *   ALPHAPOS_PROJECT_REF   — Supabase project reference ID
 *
 * Request:
 *   POST /issue-merchant-token
 *   Body: { "merchant_id": "uuid", "device_secret": "plain-text-secret" }
 *
 * Response (200):
 *   { "access_token": "eyJ...", "expires_in": 86400 }
 *
 * Errors:
 *   400 — missing fields
 *   401 — invalid merchant or device_secret mismatch
 *   500 — internal error
 */

import { createClient } from "@supabase/supabase-js";
import { create } from "djwt";

// ── Helpers ──────────────────────────────────────────────────────────

/** Import a raw secret string as an HMAC CryptoKey for DJWT signing. */
async function importHmacKey(secret: string): Promise<CryptoKey> {
  return await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign", "verify"],
  );
}

/** SHA-256 hex hash (used to verify device_secret). */
async function sha256Hex(input: string): Promise<string> {
  const data = new TextEncoder().encode(input);
  const hashBuffer = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(hashBuffer))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function timingSafeEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.byteLength !== b.byteLength) return false;
  let difference = 0;
  for (let index = 0; index < a.byteLength; index += 1) {
    difference |= a[index] ^ b[index];
  }
  return difference === 0;
}

// ── CORS headers ─────────────────────────────────────────────────────

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const pairingAttempts = new Map<string, { count: number; resetAt: number }>();

function allowPairingCodeAttempt(ip: string): boolean {
  const now = Date.now();
  const current = pairingAttempts.get(ip);
  if (!current || current.resetAt <= now) {
    pairingAttempts.set(ip, { count: 1, resetAt: now + 60_000 });
    return true;
  }
  current.count += 1;
  return current.count <= 10;
}

function createRefreshToken(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return btoa(String.fromCharCode(...bytes))
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");
}

// ── Main handler ─────────────────────────────────────────────────────

Deno.serve(async (req: Request) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(
      JSON.stringify({ error: "Method not allowed" }),
      { status: 405, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  try {
    // ── Read environment ──────────────────────────────────────────────
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
    const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const JWT_SECRET = Deno.env.get("ALPHAPOS_JWT_SECRET");
    const PROJECT_REF = Deno.env.get("ALPHAPOS_PROJECT_REF");

    if (!SUPABASE_URL || !SERVICE_ROLE_KEY || !JWT_SECRET || !PROJECT_REF) {
      console.error("Missing environment variables");
      return new Response(
        JSON.stringify({ error: "Server configuration error" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // ── Parse body ────────────────────────────────────────────────────
    const body = await req.json().catch(() => null);
    if (!body || (!body.merchant_id && !body.pairing_token && !body.pairing_code)) {
      return new Response(
        JSON.stringify({ error: "Missing merchant_id or pairing credential" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const { device_secret, pairing_token, pairing_code } = body;

    if (pairing_code) {
      const clientIp = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ?? "unknown";
      if (!allowPairingCodeAttempt(clientIp)) {
        return new Response(
          JSON.stringify({ error: "Too many pairing attempts. Try again in one minute." }),
          { status: 429, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }
    }

    // ── Verify merchant exists (using service_role to bypass RLS) ──────
    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
      auth: { persistSession: false },
    });

    let merchantId = body.merchant_id as string | undefined;
    let pairedBranchId: string | undefined;
    let pairedDeviceId: string | undefined;
    let pairedRefreshToken: string | undefined;

    if (pairing_token || pairing_code) {
      const deviceName = typeof body.device_name === "string" ? body.device_name.trim() : "";
      if (!deviceName) {
        return new Response(
          JSON.stringify({ error: "device_name is required for pairing" }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }

      pairedRefreshToken = createRefreshToken();
      const refreshTokenHash = await sha256Hex(pairedRefreshToken);
      const refreshExpiresAt = new Date(Date.now() + 90 * 24 * 60 * 60 * 1000).toISOString();
      const { data: pairingRows, error: pairingError } = await supabase.rpc(
        "consume_device_pairing",
        {
          p_token: pairing_token ?? null,
          p_code: pairing_token ? null : pairing_code,
          p_device_name: deviceName,
          p_device_fingerprint_hash: body.device_fingerprint_hash ?? null,
          p_refresh_token_hash: refreshTokenHash,
          p_refresh_token_expires_at: refreshExpiresAt,
        },
      );
      const pairing = pairingRows?.[0];
      if (pairingError || !pairing) {
        return new Response(
          JSON.stringify({ error: "Invalid, expired, or already-used pairing code" }),
          { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }
      merchantId = pairing.merchant_id;
      pairedBranchId = pairing.branch_id;
      pairedDeviceId = pairing.device_id;

      // 6-digit code path waits for POS Approve before issuing JWT.
      if (pairing.requires_approval === true) {
        const { data: merchantRow } = await supabase
          .from("merchants")
          .select("id, name")
          .eq("id", merchantId)
          .maybeSingle();
        return new Response(
          JSON.stringify({
            status: "pending_approval",
            merchant_id: merchantId,
            merchant_name: merchantRow?.name ?? null,
            branch_id: pairedBranchId,
            device_id: pairedDeviceId,
            refresh_token: pairedRefreshToken,
          }),
          {
            status: 202,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }
    }

    if (!merchantId) {
      return new Response(
        JSON.stringify({ error: "Invalid merchant" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const { data: merchant, error: merchantError } = await supabase
      .from("merchants")
      .select("id, name")
      .eq("id", merchantId)
      .maybeSingle();

    if (merchantError || !merchant) {
      console.error("Merchant lookup failed. Error:", merchantError, "Merchant:", merchant);
      return new Response(
        JSON.stringify({ error: "Invalid merchant_id" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // ── Verify device_secret (if the merchant has one configured) ──────
    if (!pairing_token && !pairing_code) {
      const deviceId = typeof body.device_id === "string" ? body.device_id : "";
      if (!deviceId || !device_secret) {
        return new Response(
          JSON.stringify({ error: "device_secret is required" }),
          { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }

      const { data: device } = await supabase.from("merchant_devices")
        .select("credential_hash,revoked_at,is_trusted")
        .eq("id", deviceId).eq("merchant_id", merchantId).maybeSingle();
      if (!device?.credential_hash || device.revoked_at || !device.is_trusted) {
        return new Response(
          JSON.stringify({ error: "Invalid device" }),
          { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }
      const providedHash = await sha256Hex(device_secret);
      const encoder = new TextEncoder();
      const aBytes = encoder.encode(providedHash);
      const bBytes = encoder.encode(device.credential_hash);

      const isMatch = timingSafeEqual(aBytes, bBytes);

      if (!isMatch) {
        return new Response(
          JSON.stringify({ error: "Invalid device_secret" }),
          { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }
    }

    // ── Sign JWT with merchant_id claim ────────────────────────────────
    const TOKEN_TTL_SECONDS = 86400; // 24 hours
    const now = Math.floor(Date.now() / 1000);

    const key = await importHmacKey(JWT_SECRET);

    const jwt = await create(
      { alg: "HS256", typ: "JWT" },
      {
        // Standard Supabase claims — PostgREST requires `iss`, `role`, `exp`
        iss: "supabase",
        ref: PROJECT_REF,
        role: "anon",
        // Custom claim: merchant_id (read by get_merchant_id() in RLS)
        merchant_id: merchantId,
        // Paired staff devices are branch-scoped. Legacy merchant-device
        // credentials may omit this claim and are not accepted by staff RPCs.
        branch_id: pairedBranchId ?? null,
        iat: now,
        exp: now + TOKEN_TTL_SECONDS,
      },
      key,
    );

    // ── Log login event into audit_logs (Login History) ───────────────
    try {
      const clientIp = req.headers.get("x-forwarded-for") || "unknown";
      const userAgent = req.headers.get("user-agent") || "unknown";
      await supabase.from("audit_logs").insert({
        merchant_id: merchantId,
        action_type: "login_merchant",
        details: `Merchant token issued. IP: ${clientIp}, Agent: ${userAgent}`,
      });
    } catch (logErr) {
      console.error("Failed to write to audit_logs:", logErr);
    }

    return new Response(
      JSON.stringify({
        access_token: jwt,
        expires_in: TOKEN_TTL_SECONDS,
        merchant_id: merchantId,
        merchant_name: merchant.name,
        branch_id: pairedBranchId,
        device_id: pairedDeviceId,
        refresh_token: pairedRefreshToken,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (err) {
    console.error("issue-merchant-token error:", err);
    return new Response(
      JSON.stringify({ error: "Internal server error" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});
