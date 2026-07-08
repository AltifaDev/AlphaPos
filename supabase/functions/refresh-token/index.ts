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

    // ── Extract existing token from X-Merchant-Token or Authorization ──
    let existingToken = req.headers.get("X-Merchant-Token");
    if (!existingToken) {
      const authHeader = req.headers.get("Authorization");
      if (authHeader && authHeader.startsWith("Bearer ")) {
        existingToken = authHeader.substring(7);
      }
    }

    if (!existingToken) {
      return new Response(
        JSON.stringify({ error: "Missing or invalid token (use X-Merchant-Token or Authorization header)" }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // ── Verify the existing token ──────────────────────────────────
    const key = await importHmacKey(JWT_SECRET);
    let payload: Record<string, unknown>;

    try {
      payload = await verify(existingToken, key) as Record<string, unknown>;
    } catch {
      return new Response(
        JSON.stringify({ error: "Invalid or expired token" }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const merchantId = payload.merchant_id as string | undefined;
    if (!merchantId) {
      return new Response(
        JSON.stringify({ error: "Token missing merchant_id claim" }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // ── Enforce sliding window policy (Must be within 3 hours of expiry) ─
    const exp = payload.exp as number | undefined;
    if (exp) {
      const nowSeconds = Math.floor(Date.now() / 1000);
      const timeLeft = exp - nowSeconds;
      const THREE_HOURS_SECONDS = 3 * 3600; // 3 hours

      // If token is still fresh (more than 3 hours remaining), reject refresh request
      if (timeLeft > THREE_HOURS_SECONDS) {
        return new Response(
          JSON.stringify({
            error: "Token is still active and cannot be refreshed yet",
            time_left_seconds: timeLeft,
            min_seconds_required: THREE_HOURS_SECONDS
          }),
          {
            status: 400,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }
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
