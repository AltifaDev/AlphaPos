import { createClient } from "@supabase/supabase-js";

const headers = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

const prices: Record<string, Record<string, string>> = {
  offline_perpetual: { perpetual: "9900.00" },
  offline_subscription: { monthly: "290.00", annual: "2990.00" },
  online_subscription: { monthly: "1190.00", annual: "11990.00" },
};

const paypalBase = () =>
  Deno.env.get("PAYPAL_ENV") === "live" ? "https://api-m.paypal.com" : "https://api-m.sandbox.paypal.com";

async function paypalAccessToken() {
  const id = Deno.env.get("PAYPAL_CLIENT_ID");
  const secret = Deno.env.get("PAYPAL_CLIENT_SECRET");
  if (!id || !secret) throw new Error("Missing PayPal credentials");
  const res = await fetch(`${paypalBase()}/v1/oauth2/token`, {
    method: "POST",
    headers: {
      "Authorization": `Basic ${btoa(`${id}:${secret}`)}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: "grant_type=client_credentials",
  });
  if (!res.ok) throw new Error("PayPal OAuth failed");
  return (await res.json()).access_token as string;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers });
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405, headers });

  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) return Response.json({ error: "Server configuration error" }, { status: 500, headers });

  const token = req.headers.get("Authorization")?.replace(/^Bearer /, "");
  if (!token) return Response.json({ error: "Missing user token" }, { status: 401, headers });

  const supabase = createClient(url, serviceKey, { auth: { persistSession: false } });
  const { data } = await supabase.auth.getUser(token);
  const merchantId = data?.user?.app_metadata?.merchant_id;
  if (!merchantId || data?.user?.app_metadata?.role !== "merchant_owner") {
    return Response.json({ error: "Merchant owner access required" }, { status: 403, headers });
  }

  const body = await req.json().catch(() => ({}));
  const tier = String(body.subscription_tier ?? "");
  const cycle = String(body.billing_cycle ?? "");
  const amount = prices[tier]?.[cycle];
  if (!amount) return Response.json({ error: "Unsupported plan" }, { status: 400, headers });

  const { data: change, error } = await supabase.from("subscription_change_requests").insert({
    merchant_id: merchantId,
    subscription_tier: tier,
    billing_cycle: cycle,
    amount_thb: amount,
  }).select("id").single();
  if (error) return Response.json({ error: error.message }, { status: 400, headers });

  const paypalToken = await paypalAccessToken();
  const order = await fetch(`${paypalBase()}/v2/checkout/orders`, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${paypalToken}`,
      "Content-Type": "application/json",
      "PayPal-Request-Id": `${merchantId}-${merchant.billing_cycle}`,
    },
    body: JSON.stringify({
      intent: "CAPTURE",
      purchase_units: [{
        custom_id: change.id,
        description: `AlphaPos ${tier} ${cycle}`,
        amount: { currency_code: "THB", value: amount },
      }],
      application_context: {
        brand_name: "AlphaPos",
        user_action: "PAY_NOW",
        return_url: "alphapos://paypal/return",
        cancel_url: "alphapos://paypal/cancel",
      },
    }),
  });
  const json = await order.json();
  if (!order.ok) return Response.json({ error: json.message ?? "PayPal order failed" }, { status: 400, headers });
  const { error: bindError } = await supabase.from("subscription_change_requests")
    .update({ provider_order_id: json.id }).eq("id", change.id);
  if (bindError) return Response.json({ error: bindError.message }, { status: 500, headers });
  return Response.json({
    order_id: json.id,
    approval_url: json.links?.find((link: { rel: string }) => link.rel === "approve")?.href,
  }, { headers });
});
