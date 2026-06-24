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

// ── CORS headers ─────────────────────────────────────────────────────

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

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
    if (!body || !body.merchant_id) {
      return new Response(
        JSON.stringify({ error: "Missing required field: merchant_id" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const { merchant_id, device_secret } = body;

    // ── Verify merchant exists (using service_role to bypass RLS) ──────
    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
      auth: { persistSession: false },
    });

    const { data: merchant, error: merchantError } = await supabase
      .from("merchants")
      .select("id, name, device_secret_hash")
      .eq("id", merchant_id)
      .maybeSingle();

    if (merchantError || !merchant) {
      console.error("Merchant lookup failed. Error:", merchantError, "Merchant:", merchant);
      return new Response(
        JSON.stringify({ error: "Invalid merchant_id" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // ── Verify device_secret (if the merchant has one configured) ──────
    if (merchant.device_secret_hash) {
      if (!device_secret) {
        return new Response(
          JSON.stringify({ error: "device_secret is required" }),
          { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }

      const providedHash = await sha256Hex(device_secret);
      if (providedHash !== merchant.device_secret_hash) {
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
        merchant_id: merchant_id,
        iat: now,
        exp: now + TOKEN_TTL_SECONDS,
      },
      key,
    );

    return new Response(
      JSON.stringify({
        access_token: jwt,
        expires_in: TOKEN_TTL_SECONDS,
        merchant_id: merchant_id,
        merchant_name: merchant.name,
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
