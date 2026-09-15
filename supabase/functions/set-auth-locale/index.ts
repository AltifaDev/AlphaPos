import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const headers = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

const allowed = new Set(["en", "th", "zh", "ja", "ko", "id", "ms"]);

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers });

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

    const body = await req.json().catch(() => null);
    const email = String(body?.email ?? "").trim().toLowerCase();
    const language = String(body?.preferred_language ?? "en").trim().toLowerCase();
    if (!email.includes("@") || !allowed.has(language)) {
      return json({ ok: true });
    }

    const supabase = createClient(url, serviceKey, { auth: { persistSession: false } });
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
