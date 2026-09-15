import { createClient } from "@supabase/supabase-js";

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

async function verifyPayPal(req: Request, event: unknown) {
  const webhookId = Deno.env.get("PAYPAL_WEBHOOK_ID");
  if (!webhookId) throw new Error("Missing PayPal webhook ID");
  const authAlgo = req.headers.get("paypal-auth-algo");
  const certUrl = req.headers.get("paypal-cert-url");
  const transmissionId = req.headers.get("paypal-transmission-id");
  const transmissionSig = req.headers.get("paypal-transmission-sig");
  const transmissionTime = req.headers.get("paypal-transmission-time");
  if (!authAlgo || !certUrl || !transmissionId || !transmissionSig || !transmissionTime) return false;
  const token = await paypalAccessToken();
  const res = await fetch(`${paypalBase()}/v1/notifications/verify-webhook-signature`, {
    method: "POST",
    headers: { "Authorization": `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      auth_algo: authAlgo,
      cert_url: certUrl,
      transmission_id: transmissionId,
      transmission_sig: transmissionSig,
      transmission_time: transmissionTime,
      webhook_id: webhookId,
      webhook_event: event,
    }),
  });
  return res.ok && (await res.json()).verification_status === "SUCCESS";
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });
  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) return new Response("Server configuration error", { status: 500 });

  try {
    const event = await req.json().catch(() => null);
    if (!event || !(await verifyPayPal(req, event))) return new Response("Invalid signature", { status: 401 });

    const type = String(event.event_type ?? "");
    const resource = event.resource ?? {};
    const changeId = resource.custom_id;
    const orderId = resource.supplementary_data?.related_ids?.order_id;
    const paymentId = resource.id ?? event.id;

    if (type !== "PAYMENT.CAPTURE.COMPLETED" || !changeId || !orderId || !paymentId) {
      return new Response("Ignored", { status: 202 });
    }

    const supabase = createClient(url, serviceKey, { auth: { persistSession: false } });
    const { data: change, error: readError } = await supabase.from("subscription_change_requests")
      .select("merchant_id,subscription_tier,billing_cycle,amount_thb,status")
      .eq("id", changeId).eq("provider_order_id", orderId).single();
    if (readError) return new Response(readError.message, { status: 400 });
    if (change.status === "paid") return Response.json({ ok: true });
    if (resource.amount?.currency_code !== "THB" || Number(resource.amount?.value) !== Number(change.amount_thb)) {
      return new Response("Payment amount mismatch", { status: 400 });
    }

    const expiresAt = change.billing_cycle === "perpetual" ? null :
      new Date(Date.now() + (change.billing_cycle === "annual" ? 365 : 30) * 86400000).toISOString();
    const { error } = await supabase.from("merchants").update({
      subscription_tier: change.subscription_tier,
      billing_cycle: change.billing_cycle,
      subscription_status: "active",
      subscription_expires_at: expiresAt,
    }).eq("id", change.merchant_id);
    if (error) return new Response(error.message, { status: 400 });

    const { error: changeError } = await supabase.from("subscription_change_requests").update({
      status: "paid", provider_payment_id: paymentId, paid_at: new Date().toISOString(),
    }).eq("id", changeId).eq("status", "created");
    if (changeError) return new Response(changeError.message, { status: 400 });

    await supabase.from("audit_logs").insert({
      merchant_id: change.merchant_id,
      action_type: "subscription_payment_succeeded",
      details: `PayPal capture ${String(paymentId).slice(0, 100)} activated ${change.subscription_tier}/${change.billing_cycle}`,
    });
    return Response.json({ ok: true });
  } catch (error) {
    console.error("payment-webhook", error);
    return new Response("Server configuration error", { status: 500 });
  }
});
