/**
 * Creates a short-lived session exclusively for Apple's App Review demo user.
 *
 * Normal password sign-in remains protected by Cloudflare Turnstile. The demo
 * account contains synthetic data only, and this endpoint is deliberately
 * rate-limited to make the review credentials usable without weakening normal
 * merchant authentication.
 */
import { create } from "djwt";
import { createClient } from "@supabase/supabase-js";

const demoEmail = "appreview@alphaposweb.com";
const sessionTTLSeconds = 2 * 60 * 60;
const attempts = new Map<string, { count: number; resetAt: number }>();

const headers = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers });
}

function allowAttempt(ip: string): boolean {
  const now = Date.now();
  const current = attempts.get(ip);
  if (!current || current.resetAt <= now) {
    attempts.set(ip, { count: 1, resetAt: now + 60_000 });
    return true;
  }
  current.count += 1;
  return current.count <= 10;
}

async function signingKey(secret: string): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign", "verify"],
  );
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const ip = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ?? "unknown";
  if (!allowAttempt(ip)) return json({ error: "Too many attempts. Try again shortly." }, 429);

  try {
    const body = await req.json().catch(() => null);
    const email = typeof body?.email === "string" ? body.email.trim().toLowerCase() : "";
    const password = typeof body?.password === "string" ? body.password : "";
    if (email !== demoEmail || !password) return json({ error: "Invalid credentials" }, 401);

    const url = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const jwtSecret = Deno.env.get("ALPHAPOS_JWT_SECRET");
    const projectRef = Deno.env.get("ALPHAPOS_PROJECT_REF");
    if (!url || !serviceKey || !jwtSecret || !projectRef) return json({ error: "Server configuration error" }, 500);

    const admin = createClient(url, serviceKey, { auth: { persistSession: false } });
    const { data, error } = await admin.rpc("verify_app_review_demo_credentials", {
      p_email: email,
      p_password: password,
    });
    const user = data?.[0];
    if (error || !user?.user_id || !user.email_confirmed) return json({ error: "Invalid credentials" }, 401);

    const now = Math.floor(Date.now() / 1000);
    const accessToken = await create(
      { alg: "HS256", typ: "JWT" },
      {
        aud: "authenticated",
        role: "authenticated",
        sub: user.user_id,
        email: user.email,
        app_metadata: user.app_metadata ?? {},
        user_metadata: user.user_metadata ?? {},
        aal: "aal1",
        amr: [{ method: "password", timestamp: now }],
        iss: "supabase",
        ref: projectRef,
        iat: now,
        exp: now + sessionTTLSeconds,
      },
      await signingKey(jwtSecret),
    );

    return json({
      access_token: accessToken,
      refresh_token: "",
      expires_in: sessionTTLSeconds,
      user: {
        id: user.user_id,
        email: user.email,
        app_metadata: user.app_metadata ?? {},
        user_metadata: user.user_metadata ?? {},
      },
    });
  } catch (error) {
    console.error("app-review-session", error);
    return json({ error: "Internal server error" }, 500);
  }
});
