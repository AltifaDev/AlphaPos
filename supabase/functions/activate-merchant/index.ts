import { createClient } from "@supabase/supabase-js";

const headers = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

const allowedPlans: Record<string, string[]> = {
  offline_perpetual: ["perpetual"],
  offline_subscription: ["monthly", "annual"],
  online_subscription: ["monthly", "annual"],
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers });

const sha256 = async (value: string) =>
  Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value))))
    .map((byte) => byte.toString(16).padStart(2, "0")).join("");

const randomSecret = () => {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return btoa(String.fromCharCode(...bytes))
    .replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
};

const jwtAal = (token: string) => {
  try {
    const payload = token.split(".")[1].replaceAll("-", "+").replaceAll("_", "/");
    return JSON.parse(atob(payload))["aal"] as string | undefined;
  } catch {
    return undefined;
  }
};

type Supabase = ReturnType<typeof createClient>;

/** Reuse device id only when unbound or already owned by this merchant. */
async function resolveUsableDeviceId(
  supabase: Supabase,
  requestedDeviceId: string,
  merchantId?: string,
): Promise<string> {
  const { data } = await supabase
    .from("merchant_devices")
    .select("id, merchant_id")
    .eq("id", requestedDeviceId)
    .maybeSingle();
  if (!data) return requestedDeviceId;
  if (merchantId && data.merchant_id === merchantId) return requestedDeviceId;
  // Device UUID was previously registered to another store (common on shared iPads).
  return crypto.randomUUID();
}

async function resolveExistingMerchantId(
  supabase: Supabase,
  user: { id: string; email?: string; app_metadata?: Record<string, unknown> },
): Promise<string | undefined> {
  const fromMeta = user.app_metadata?.merchant_id;
  if (typeof fromMeta === "string" && fromMeta.trim()) return fromMeta;

  const { data: onboarding } = await supabase
    .from("merchant_onboarding_requests")
    .select("merchant_id")
    .eq("user_id", user.id)
    .maybeSingle();
  if (onboarding?.merchant_id) return onboarding.merchant_id as string;

  const { data: merchantUser } = await supabase
    .from("merchant_users")
    .select("merchant_id")
    .eq("id", user.id)
    .maybeSingle();
  if (merchantUser?.merchant_id) return merchantUser.merchant_id as string;

  // Do NOT match by email alone — shared/dev devices may leave other merchants'
  // emails in local state, and email collision must not steal an existing store.

  return undefined;
}

async function attachDeviceAndRespond(
  supabase: Supabase,
  user: { id: string; app_metadata?: Record<string, unknown>; user_metadata?: Record<string, unknown> },
  merchantId: string,
  body: Record<string, unknown>,
) {
  const deviceCredential = randomSecret();
  const requestedDeviceId = String(body.device_id);
  const deviceId = await resolveUsableDeviceId(supabase, requestedDeviceId, merchantId);
  const { error: deviceError } = await supabase.from("merchant_devices").upsert({
    id: deviceId,
    merchant_id: merchantId,
    device_name: String(body.device_name),
    device_type: "pos_register",
    device_fingerprint_hash: String(body.device_fingerprint_hash ?? "") || null,
    credential_hash: await sha256(deviceCredential),
    is_trusted: true,
    revoked_at: null,
    last_seen_at: new Date().toISOString(),
  }, { onConflict: "id" });
  if (deviceError) return json({ error: deviceError.message }, 400);

  // Heal missing app_metadata.merchant_id for returning owners.
  if (user.app_metadata?.merchant_id !== merchantId) {
    await supabase.auth.admin.updateUserById(user.id, {
      app_metadata: {
        ...(user.app_metadata ?? {}),
        merchant_id: merchantId,
        role: "merchant_owner",
      },
    });
  }

  const { data: merchant } = await supabase
    .from("merchants")
    .select("subscription_tier,subscription_status,subscription_expires_at")
    .eq("id", merchantId)
    .single();

  return json({
    merchant_id: merchantId,
    device_id: deviceId,
    device_credential: deviceCredential,
    ...merchant,
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const url = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !serviceKey) return json({ error: "Server configuration error" }, 500);

    const token = req.headers.get("Authorization")?.replace(/^Bearer /, "");
    if (!token) return json({ error: "Missing user token" }, 401);

    const body = await req.json().catch(() => null);
    const required = ["idempotency_key", "device_id", "device_name"];
    if (!body || required.some((key) => !String(body[key] ?? "").trim())) {
      return json({ error: "Missing required device fields" }, 400);
    }

    const supabase = createClient(url, serviceKey, { auth: { persistSession: false } });
    const { data: userData, error: userError } = await supabase.auth.getUser(token);
    const user = userData?.user;
    if (userError || !user?.id || !user.email) return json({ error: "Invalid user token" }, 401);
    if (!user.email_confirmed_at) return json({ error: "Email confirmation required" }, 403);

    // Require MFA (aal2) only after the owner has already enrolled a verified factor.
    const { data: factorsData } = await supabase.auth.admin.mfa.listFactors({ userId: user.id });
    const hasVerifiedTotp = (factorsData?.totp ?? []).some((factor) => factor.status === "verified");
    if (hasVerifiedTotp && jwtAal(token) !== "aal2") {
      return json({ error: "Owner MFA verification required" }, 403);
    }

    const existingMerchantId = await resolveExistingMerchantId(supabase, user);
    if (existingMerchantId) {
      return await attachDeviceAndRespond(supabase, user, existingMerchantId, body);
    }

    const newMerchantRequired = [
      "shop_name",
      "first_name",
      "last_name",
      "subscription_tier",
      "billing_cycle",
      "terms_version",
      "privacy_version",
      "consented_at",
    ];
    if (newMerchantRequired.some((key) => !String(body[key] ?? "").trim())) {
      return json({
        error: "ONBOARDING_REQUIRED",
        message: "กรุณากรอกข้อมูลร้านและเลือกแพ็กเกจเพื่อเปิดใช้งานบัญชี",
      }, 400);
    }

    const tier = String(body.subscription_tier);
    const cycle = String(body.billing_cycle);
    if (!allowedPlans[tier]?.includes(cycle)) return json({ error: "Invalid subscription" }, 400);

    const requestedDeviceId = String(body.device_id);
    const deviceId = await resolveUsableDeviceId(supabase, requestedDeviceId);
    const deviceCredential = randomSecret();
    const { data, error } = await supabase.rpc("complete_merchant_onboarding", {
      p_user_id: user.id,
      p_email: user.email,
      p_shop_name: String(body.shop_name),
      p_first_name: String(body.first_name),
      p_last_name: String(body.last_name),
      p_shop_phone: String(body.shop_phone ?? ""),
      p_currency: String(body.currency ?? "THB"),
      p_tax_id: String(body.tax_id ?? ""),
      p_subscription_tier: tier,
      p_billing_cycle: cycle,
      p_terms_version: String(body.terms_version),
      p_privacy_version: String(body.privacy_version),
      p_consented_at: String(body.consented_at),
      p_idempotency_key: String(body.idempotency_key),
      p_device_id: deviceId,
      p_device_name: String(body.device_name),
      p_device_fingerprint_hash: String(body.device_fingerprint_hash ?? ""),
      p_device_credential_hash: await sha256(deviceCredential),
    });
    if (error || !data?.[0]) return json({ error: error?.message ?? "Onboarding failed" }, 400);

    const merchantId = data[0].merchant_id;
    const { error: updateError } = await supabase.auth.admin.updateUserById(user.id, {
      app_metadata: { ...(user.app_metadata ?? {}), merchant_id: merchantId, role: "merchant_owner" },
      user_metadata: {
        ...(user.user_metadata ?? {}),
        first_name: String(body.first_name),
        last_name: String(body.last_name),
        full_name: `${body.first_name} ${body.last_name}`.trim(),
      },
    });
    if (updateError) return json({ error: updateError.message }, 500);

    // Perpetual activates immediately. Paid tiers start a 14-day trial so
    // merchants can enter the app and finish payment from the checklist (Phase 2).
    const trialDays = 14;
    const subscriptionStatus = tier === "offline_perpetual" ? "active" : "trial";
    const subscriptionExpiresAt = subscriptionStatus === "trial"
      ? new Date(Date.now() + trialDays * 24 * 60 * 60 * 1000).toISOString()
      : null;
    await supabase
      .from("merchants")
      .update({
        subscription_status: subscriptionStatus,
        subscription_expires_at: subscriptionExpiresAt,
      })
      .eq("id", merchantId);

    // Clear any incomplete shop/plan draft once the store exists.
    await supabase.from("merchant_onboarding_drafts").delete().eq("user_id", user.id);

    return json({
      merchant_id: merchantId,
      device_id: data[0].device_id ?? deviceId,
      device_credential: deviceCredential,
      subscription_tier: tier,
      subscription_status: subscriptionStatus,
      subscription_expires_at: subscriptionExpiresAt,
    });
  } catch (error) {
    console.error("activate-merchant", error);
    return json({ error: "Internal server error" }, 500);
  }
});
