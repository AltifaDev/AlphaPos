import { createClient } from "@supabase/supabase-js";

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });
  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) return new Response("Server configuration error", { status: 500 });

  const token = req.headers.get("Authorization")?.replace(/^Bearer /, "");
  const body = await req.json().catch(() => null);
  if (!token || body?.confirmation !== "DELETE") return new Response("Invalid request", { status: 400 });
  try {
    const payload = token.split(".")[1].replaceAll("-", "+").replaceAll("_", "/");
    if (JSON.parse(atob(payload))["aal"] !== "aal2") return new Response("MFA required", { status: 403 });
  } catch { return new Response("Invalid token", { status: 401 }); }

  const supabase = createClient(url, serviceKey, { auth: { persistSession: false } });
  const { data, error } = await supabase.auth.getUser(token);
  const user = data?.user;
  const merchantId = user?.app_metadata?.merchant_id;
  if (error || !user?.id || !merchantId) return new Response("Unauthorized", { status: 401 });

  const { error: eraseError } = await supabase.rpc("erase_merchant_data", {
    p_merchant_id: merchantId,
    p_confirmation: "ERASE",
  });
  if (eraseError) return new Response(eraseError.message, { status: 400 });

  const { error: deleteError } = await supabase.auth.admin.deleteUser(user.id);
  if (deleteError) return new Response(deleteError.message, { status: 500 });
  return Response.json({ deleted: true });
});
