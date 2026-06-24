import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
};

const encoder = new TextEncoder();
let cachedProviderToken: { value: string; createdAt: number } | null = null;

function base64url(value: Uint8Array | string): string {
  const bytes = typeof value === "string" ? encoder.encode(value) : value;
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

function pemToBytes(pem: string): Uint8Array {
  const body = pem.replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s/g, "");
  return Uint8Array.from(atob(body), (char) => char.charCodeAt(0));
}

function decodeJwtPayload(part: string): Record<string, unknown> {
  const normalized = part.replaceAll("-", "+").replaceAll("_", "/");
  const padded = normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "=");
  return JSON.parse(atob(padded));
}

async function providerToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedProviderToken && now - cachedProviderToken.createdAt < 3000) {
    return cachedProviderToken.value;
  }

  const keyId = Deno.env.get("APNS_KEY_ID");
  const teamId = Deno.env.get("APNS_TEAM_ID");
  const privateKeyValue = Deno.env.get("APNS_PRIVATE_KEY");
  if (!keyId || !teamId || !privateKeyValue) {
    throw new Error("APNs credentials are not configured");
  }
  const privateKey = privateKeyValue.replaceAll("\\n", "\n");
  const header = base64url(JSON.stringify({ alg: "ES256", kid: keyId }));
  const claims = base64url(JSON.stringify({ iss: teamId, iat: now }));
  const signingInput = `${header}.${claims}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToBytes(privateKey),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    encoder.encode(signingInput),
  ));
  const value = `${signingInput}.${base64url(signature)}`;
  cachedProviderToken = { value, createdAt: now };
  return value;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const { order_id } = await req.json();
    if (!order_id) return new Response("Missing order_id", { status: 400, headers: corsHeaders });

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } });

    const { data: order, error: orderError } = await admin
      .from("orders")
      .select("id,merchant_id,order_number,table_number,status")
      .eq("id", order_id)
      .single();
    if (orderError || !order) return new Response("Order not found", { status: 404, headers: corsHeaders });

    const bearer = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "") ?? "";
    
    let isAuthorized = false;
    if (bearer && serviceKey && bearer === serviceKey) {
      isAuthorized = true;
    } else {
      const payloadPart = bearer.split(".")[1];
      const claims = payloadPart ? decodeJwtPayload(payloadPart) : {};
      if (claims.role === "service_role" || (claims.merchant_id && claims.merchant_id === order.merchant_id)) {
        isAuthorized = true;
      }
    }

    if (!isAuthorized) {
      return new Response("Forbidden", { status: 403, headers: corsHeaders });
    }

    const { data: devices, error: devicesError } = await admin
      .from("push_devices")
      .select("device_token,app_id")
      .eq("merchant_id", order.merchant_id)
      .eq("is_active", true);
    if (devicesError) throw devicesError;
    if (!devices?.length) {
      return Response.json({ delivered: 0 }, { headers: corsHeaders });
    }

    let token: string;
    try {
      token = await providerToken();
    } catch (error) {
      return Response.json({
        error: error instanceof Error ? error.message : "APNs credentials are not configured",
      }, { status: 503, headers: corsHeaders });
    }
    const production = Deno.env.get("APNS_ENVIRONMENT") === "production";
    const host = production ? "https://api.push.apple.com" : "https://api.sandbox.push.apple.com";
    const bundleIds: Record<string, string> = {
      pos: Deno.env.get("APNS_POS_BUNDLE_ID") ?? "AltifaDev.AlphaPos",
      staff: Deno.env.get("APNS_STAFF_BUNDLE_ID") ?? "AltifaDev.AlphaPosStaff",
    };
    const payload = JSON.stringify({
      aps: {
        alert: {
          title: `New Order ${order.order_number}`,
          body: `Table ${order.table_number}`,
        },
        sound: "default",
        badge: 1,
        "interruption-level": "time-sensitive",
      },
      type: "new_order",
      order_id: order.id,
      table_number: order.table_number,
    });

    const results = await Promise.all(devices.map(async (device) => {
      const response = await fetch(`${host}/3/device/${device.device_token}`, {
        method: "POST",
        headers: {
          authorization: `bearer ${token}`,
          "apns-topic": bundleIds[device.app_id],
          "apns-push-type": "alert",
          "apns-priority": "10",
          "content-type": "application/json",
        },
        body: payload,
      });
      if (response.status === 410 || response.status === 400) {
        const detail = await response.json().catch(() => ({}));
        if (["BadDeviceToken", "Unregistered", "DeviceTokenNotForTopic"].includes(detail.reason)) {
          await admin.from("push_devices").update({ is_active: false }).eq("device_token", device.device_token);
        }
      }
      return response.ok;
    }));

    return Response.json({ delivered: results.filter(Boolean).length, total: results.length }, { headers: corsHeaders });
  } catch (error) {
    console.error(error);
    return Response.json({ error: error instanceof Error ? error.message : "Push failed" }, {
      status: 500,
      headers: corsHeaders,
    });
  }
});
