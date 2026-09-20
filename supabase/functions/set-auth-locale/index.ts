import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { create } from "https://deno.land/x/djwt@v3.0.2/mod.ts";

const headers = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

const allowed = new Set(["en", "th", "zh", "ja", "ko", "id", "ms"]);
const demoEmail = "appreview@alphaposweb.com";
const reviewAttempts = new Map<string, { count: number; resetAt: number }>();

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers });

function allowReviewAttempt(ip: string): boolean {
  const now = Date.now();
  const current = reviewAttempts.get(ip);
  if (!current || current.resetAt <= now) {
    reviewAttempts.set(ip, { count: 1, resetAt: now + 60_000 });
    return true;
  }
  current.count += 1;
  return current.count <= 10;
}

async function reviewSigningKey(secret: string): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign", "verify"],
  );
}

async function issueAppReviewSession(
  req: Request,
  body: Record<string, unknown>,
  supabase: ReturnType<typeof createClient>,
) {
  const ip = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ?? "unknown";
  if (!allowReviewAttempt(ip)) return json({ error: "Too many attempts. Try again shortly." }, 429);

  const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
  const password = typeof body.password === "string" ? body.password : "";
  if (email !== demoEmail || !password) return json({ error: "Invalid credentials" }, 401);

  const jwtSecret = Deno.env.get("ALPHAPOS_JWT_SECRET");
  const projectRef = Deno.env.get("ALPHAPOS_PROJECT_REF");
  if (!jwtSecret || !projectRef) return json({ error: "Server configuration error" }, 500);

  const { data, error } = await supabase.rpc("verify_app_review_demo_credentials", {
    p_email: email,
    p_password: password,
  });
  const user = data?.[0];
  if (error || !user?.user_id || !user.email_confirmed) return json({ error: "Invalid credentials" }, 401);

  const now = Math.floor(Date.now() / 1000);
  const accessToken = await create(
    { alg: "HS256", typ: "JWT" },
    {
      aud: "authenticated", role: "authenticated", sub: user.user_id,
      email: user.email, app_metadata: user.app_metadata ?? {}, user_metadata: user.user_metadata ?? {},
      aal: "aal1", amr: [{ method: "password", timestamp: now }],
      iss: "supabase", ref: projectRef, iat: now, exp: now + 2 * 60 * 60,
    },
    await reviewSigningKey(jwtSecret),
  );
  return json({
    access_token: accessToken, refresh_token: "", expires_in: 2 * 60 * 60,
    user: { id: user.user_id, email: user.email, app_metadata: user.app_metadata ?? {}, user_metadata: user.user_metadata ?? {} },
  });
}

/**
 * Best-effort: stamp preferred_language onto an auth user by email so the next
 * GoTrue recovery/confirmation mail renders the matching locale block.
 * Always returns 200 for unknown emails (anti-enumeration).
 */
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const url = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !serviceKey) return json({ error: "Server configuration error" }, 500);

    const supabase = createClient(url, serviceKey, { auth: { persistSession: false } });

    const body = await req.json().catch(() => null) as Record<string, unknown> | null;
    if (body?.app_review_session === true) {
      return await issueAppReviewSession(req, body, supabase);
    }
    const email = String(body?.email ?? "").trim().toLowerCase();
    const language = String(body?.preferred_language ?? "en").trim().toLowerCase();
    if (!email.includes("@") || !allowed.has(language)) {
      return json({ ok: true });
    }
    const { data, error } = await supabase.auth.admin.getUserByEmail(email);
    if (error || !data?.user?.id) {
      return json({ ok: true });
    }

    const meta = { ...(data.user.user_metadata ?? {}), preferred_language: language };
    await supabase.auth.admin.updateUserById(data.user.id, { user_metadata: meta });
    return json({ ok: true });
  } catch (error) {
    console.error("set-auth-locale", error);
    return json({ ok: true });
  }
});
