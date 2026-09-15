/**
 * AlphaPos — Merchant JWT Token Refresh (Edge Function)
 *
 * Accepts an existing (still-valid) JWT and issues a fresh token with
 * the same merchant_id claim but a new expiry time.
 *
 * Request:
 *   POST /refresh-token
 *   Headers: Authorization: Bearer <existing-jwt>
 *
 * Response (200):
 *   { "access_token": "eyJ...", "expires_in": 86400 }
 */

import {
  create,
  verify,
} from "djwt";
import { createClient } from "@supabase/supabase-js";

// ── Helpers ──────────────────────────────────────────────────────────

async function importHmacKey(secret: string): Promise<CryptoKey> {
  return await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign", "verify"],
  );
}

async function sha256Hex(input: string): Promise<string> {
  const data = new TextEncoder().encode(input);
  const hash = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(hash))
    .map((byte) => byte.toString(16).padStart(2, "0"))
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

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// ── Main handler ─────────────────────────────────────────────────────

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(
      JSON.stringify({ error: "Method not allowed" }),
      {
        status: 405,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }

  try {
    const JWT_SECRET = Deno.env.get("ALPHAPOS_JWT_SECRET");
    const PROJECT_REF = Deno.env.get("ALPHAPOS_PROJECT_REF");
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
    const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

    if (!JWT_SECRET || !PROJECT_REF || !SUPABASE_URL || !SERVICE_ROLE_KEY) {
      return new Response(
        JSON.stringify({ error: "Server configuration error" }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const body = await req.json().catch(() => ({}));

    // A paired staff device can refresh after the JWT expires. The opaque
    // credential is stored only in Keychain; the database stores its hash.
    // Also used by 6-digit pending pairing to poll until POS Approve.
    let merchantId: string | undefined;
    let branchId: string | undefined;
    let resolvedFromDeviceCredential = false;
    if (typeof body.device_id === "string" && typeof body.refresh_token === "string") {
      const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
        auth: { persistSession: false },
      });
      const { data: device } = await supabase
        .from("merchant_devices")
        .select("merchant_id, branch_id, refresh_token_hash, refresh_token_expires_at, is_trusted")
        .eq("id", body.device_id)
        .maybeSingle();
      const providedHash = await sha256Hex(body.refresh_token);
      const encoder = new TextEncoder();
      const provided = encoder.encode(providedHash);
      const stored = encoder.encode(device?.refresh_token_hash ?? "");
      const credentialMatches = !!device
        && !!device.refresh_token_expires_at
        && new Date(device.refresh_token_expires_at).getTime() > Date.now()
        && timingSafeEqual(provided, stored);

      if (!credentialMatches) {
        // Device missing usually means POS rejected the pending request.
        const status = device ? 401 : 410;
        const error = device
          ? "Invalid or revoked device credential"
          : "Pairing request was rejected or expired";
        return new Response(JSON.stringify({ error, status: device ? "invalid" : "rejected" }), {
          status,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      if (device.is_trusted !== true) {
        return new Response(
          JSON.stringify({
            status: "pending_approval",
            merchant_id: device.merchant_id,
            device_id: body.device_id,
          }),
          {
            status: 202,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      merchantId = device.merchant_id;
      branchId = device.branch_id;
      resolvedFromDeviceCredential = true;
    }

    // Existing clients continue to refresh using a still-valid merchant JWT.
    let existingToken = req.headers.get("X-Merchant-Token");
    if (!merchantId && !existingToken) {
      const authHeader = req.headers.get("Authorization");
      if (authHeader && authHeader.startsWith("Bearer ")) {
        existingToken = authHeader.substring(7);
      }
    }

    const key = await importHmacKey(JWT_SECRET);
    if (!merchantId && existingToken) {
      let payload: Record<string, unknown>;
      try {
        payload = await verify(existingToken, key) as Record<string, unknown>;
      } catch {
        return new Response(
          JSON.stringify({ error: "Invalid or expired token" }),
          { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }
      merchantId = payload.merchant_id as string | undefined;
      branchId = payload.branch_id as string | undefined;
      if (!merchantId) {
        return new Response(JSON.stringify({ error: "Token missing merchant_id claim" }), {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      const exp = payload.exp as number | undefined;
      const timeLeft = exp ? exp - Math.floor(Date.now() / 1000) : 0;
      if (timeLeft > 3 * 3600) {
        return new Response(JSON.stringify({ error: "Token is still active and cannot be refreshed yet" }), {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
    }

    if (!merchantId) {
      return new Response(
        JSON.stringify({
          error: resolvedFromDeviceCredential
            ? "Unable to resolve merchant"
            : "Missing or invalid token (use device credentials or X-Merchant-Token)",
        }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // ── Issue fresh token ──────────────────────────────────────────
    const TOKEN_TTL_SECONDS = 86400;
    const now = Math.floor(Date.now() / 1000);

    const jwt = await create(
      { alg: "HS256", typ: "JWT" },
      {
        iss: "supabase",
        ref: PROJECT_REF,
        role: "anon",
        merchant_id: merchantId,
        branch_id: branchId ?? null,
        iat: now,
        exp: now + TOKEN_TTL_SECONDS,
      },
      key,
    );

    // ── Log refresh event into audit_logs (Login History) ─────────────
    try {
      const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
        auth: { persistSession: false },
      });
      const clientIp = req.headers.get("x-forwarded-for") || "unknown";
      const userAgent = req.headers.get("user-agent") || "unknown";
      await supabase.from("audit_logs").insert({
        merchant_id: merchantId,
        branch_id: branchId ?? null,
        action_type: "refresh_merchant_token",
        details: `Merchant token refreshed. IP: ${clientIp}, Agent: ${userAgent}`,
      });
    } catch (logErr) {
      console.error("Failed to write to audit_logs during refresh:", logErr);
    }

    return new Response(
      JSON.stringify({
        access_token: jwt,
        expires_in: TOKEN_TTL_SECONDS,
        merchant_id: merchantId,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (err) {
    console.error("refresh-token error:", err);
    return new Response(
      JSON.stringify({ error: "Internal server error" }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
