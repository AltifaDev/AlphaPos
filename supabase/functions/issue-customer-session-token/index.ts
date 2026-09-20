import { create, getNumericDate } from "https://deno.land/x/djwt@v3.0.2/mod.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (status: number, body: Record<string, unknown>) => new Response(
  JSON.stringify(body),
  { status, headers: { ...corsHeaders, "Content-Type": "application/problem+json", "Cache-Control": "no-store" } },
);

const sha256 = async (value: string) => {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest)).map((byte) => byte.toString(16).padStart(2, "0")).join("");
};

const issueToken = async (session: Record<string, unknown>, jwtSecret: string, projectRef: string) => {
  const key = await crypto.subtle.importKey(
    "raw", new TextEncoder().encode(jwtSecret), { name: "HMAC", hash: "SHA-256" }, false, ["sign", "verify"],
  );
  const now = Math.floor(Date.now() / 1000);
  const ttl = 30 * 60;
  const token = await create(
    { alg: "HS256", typ: "JWT" },
    {
      iss: "supabase", ref: projectRef, role: "customer_web", aud: "authenticated",
      token_use: "customer_session", merchant_id: session.merchant_id,
      branch_id: session.branch_id, table_session_id: session.id,
      table_number: String(session.table_number), jti: crypto.randomUUID(),
      iat: now, exp: getNumericDate(ttl),
    },
    key,
  );
  return {
    access_token: token, expires_in: ttl, merchant_id: session.merchant_id,
    branch_id: session.branch_id, table_session_id: session.id,
    table_number: String(session.table_number), session_token: session.session_token,
  };
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json(405, { code: "METHOD_NOT_ALLOWED", title: "Method not allowed", status: 405 });

  const requestId = crypto.randomUUID();
  try {
    const body = await req.json();
    const { table_number, session_token, merchant_id, permanent_key, approval_request_id } = body;
    const isPermanent = !!permanent_key;
    if (!table_number || (!session_token && !isPermanent) || String(session_token || permanent_key).length > 255) {
      return json(400, { code: "INVALID_SESSION_REQUEST", title: "Invalid customer session request", status: 400, traceId: requestId });
    }

    const url = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const jwtSecret = Deno.env.get("ALPHAPOS_JWT_SECRET");
    const projectRef = Deno.env.get("PROJECT_REF") || "alphapos";
    if (!url || !serviceKey || !jwtSecret) throw new Error("customer token service is not configured");

    const admin = createClient(url, serviceKey, { auth: { persistSession: false } });

    if (isPermanent) {
      if (!merchant_id || !/^[0-9a-f-]{36}$/i.test(String(merchant_id))) {
        return json(400, { code: "INVALID_PERMANENT_QR", title: "Invalid permanent table QR", status: 400, traceId: requestId });
      }
      const keyHash = await sha256(String(permanent_key));

      if (!approval_request_id) {
        const { data: requested, error: requestError } = await admin.rpc("request_permanent_qr_access", {
          p_merchant_id: merchant_id, p_table_number: String(table_number), p_key_hash: keyHash,
        });
        if (requestError) {
          console.error(JSON.stringify({
            level: "error", event: "permanent_qr.access_request_failed", requestId,
            code: requestError.code, message: requestError.message,
          }));
          return json(503, { code: "PERMANENT_QR_LOOKUP_FAILED", title: "Could not validate table QR", status: 503, traceId: requestId });
        }
        if (requested?.status === "invalid") {
          return json(401, { code: "PERMANENT_QR_INVALID", title: "Permanent table QR is invalid or revoked", status: 401, traceId: requestId });
        }
        if (requested?.status === "unavailable") {
          console.error(JSON.stringify({
            level: "error", event: "permanent_qr.configuration_invalid", requestId,
            code: requested.error_code || "TABLE_CONFIGURATION_INVALID",
          }));
          return json(503, { code: "PERMANENT_QR_UNAVAILABLE", title: "Table ordering is temporarily unavailable", status: 503, traceId: requestId });
        }
        // The RPC is authoritative and already locks/validates the table and
        // returns the active-or-new session. Do not perform a second
        // PostgREST lookup here: it creates a TOCTOU window and can turn a
        // valid self-service scan into a false QR_INVALID/502 when the REST
        // schema cache or internal gateway is unavailable.
        if (requested.status === "approved" && requested.table_session_id && requested.session_token && requested.branch_id) {
          const approvedSession = {
            id: requested.table_session_id,
            merchant_id: requested.merchant_id || merchant_id,
            branch_id: requested.branch_id,
            table_number: requested.table_number || String(table_number),
            session_token: requested.session_token,
          };
          const responseBody = await issueToken(approvedSession, jwtSecret, projectRef);
          return new Response(JSON.stringify(responseBody), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json", "Cache-Control": "no-store" } });
        }
        if (!requested?.request_id) {
          return json(401, { code: "PERMANENT_QR_INVALID", title: "Permanent table QR is invalid or revoked", status: 401, traceId: requestId });
        }
        return json(202, {
          code: "STAFF_APPROVAL_REQUIRED", title: "Waiting for staff confirmation", status: 202,
          approval_request_id: requested.request_id, expires_at: requested.expires_at,
          table_number: requested.table_number, traceId: requestId,
        });
      }

      const { data: access, error: accessError } = await admin
        .from("permanent_qr_access_requests")
        .select("id,status,expires_at,table_session_id,restaurant_table_id")
        .eq("id", String(approval_request_id))
        .eq("merchant_id", String(merchant_id))
        .eq("table_number", String(table_number))
        .maybeSingle();

      // Do not use an embedded PostgREST relationship here. Relationship/schema
      // cache failures previously turned a valid pending approval into a false
      // PERMANENT_QR_INVALID response on the very first poll.
      if (accessError) {
        console.error(JSON.stringify({
          level: "error", event: "permanent_qr.approval_lookup_failed", requestId,
          approvalRequestId: String(approval_request_id), code: accessError.code,
          message: accessError.message,
        }));
        return json(503, { code: "APPROVAL_LOOKUP_FAILED", title: "Could not check staff approval", status: 503, traceId: requestId });
      }
      if (!access?.restaurant_table_id) {
        return json(401, { code: "PERMANENT_QR_INVALID", title: "Permanent table QR is invalid or revoked", status: 401, traceId: requestId });
      }

      const { data: linkedTable, error: tableError } = await admin
        .from("restaurant_tables")
        .select("permanent_qr_key_hash,permanent_qr_revoked_at")
        .eq("id", access.restaurant_table_id)
        .eq("merchant_id", String(merchant_id))
        .eq("table_number", String(table_number))
        .maybeSingle();
      if (tableError) {
        console.error(JSON.stringify({
          level: "error", event: "permanent_qr.table_lookup_failed", requestId,
          approvalRequestId: String(approval_request_id), code: tableError.code,
          message: tableError.message,
        }));
        return json(503, { code: "TABLE_LOOKUP_FAILED", title: "Could not validate table QR", status: 503, traceId: requestId });
      }
      if (!linkedTable || linkedTable.permanent_qr_key_hash !== keyHash || linkedTable.permanent_qr_revoked_at) {
        console.warn(JSON.stringify({
          level: "warn", event: "permanent_qr.validation_rejected", requestId,
          approvalRequestId: String(approval_request_id),
          reason: !linkedTable ? "TABLE_NOT_FOUND" : linkedTable.permanent_qr_revoked_at ? "QR_REVOKED" : "KEY_MISMATCH",
        }));
        return json(401, { code: "PERMANENT_QR_INVALID", title: "Permanent table QR is invalid or revoked", status: 401, traceId: requestId });
      }
      if (access.status === "pending" && new Date(access.expires_at).getTime() > Date.now()) {
        return json(202, { code: "STAFF_APPROVAL_REQUIRED", title: "Waiting for staff confirmation", status: 202,
          approval_request_id: access.id, expires_at: access.expires_at, traceId: requestId });
      }
      if (access.status !== "approved" || !access.table_session_id) {
        return json(410, { code: "APPROVAL_EXPIRED_OR_REJECTED", title: "Staff approval expired or was rejected", status: 410, traceId: requestId });
      }
      const { data: approvedSession } = await admin.from("table_sessions")
        .select("id,merchant_id,branch_id,table_number,session_token,is_active,ended_at")
        .eq("id", access.table_session_id).eq("is_active", 1).is("ended_at", null).maybeSingle();
      if (!approvedSession?.branch_id) {
        return json(410, { code: "SESSION_INVALID_OR_CLOSED", title: "Approved table session is no longer active", status: 410, traceId: requestId });
      }
      const responseBody = await issueToken(approvedSession, jwtSecret, projectRef);
      return new Response(JSON.stringify(responseBody), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json", "Cache-Control": "no-store" } });
    }

    const { data: session, error } = await admin
      .from("table_sessions")
      .select("id, merchant_id, branch_id, table_number, session_token, is_active, ended_at")
      .eq("table_number", String(table_number))
      .eq("session_token", String(session_token))
      .eq("is_active", 1)
      .is("ended_at", null)
      .maybeSingle();

    if (error || !session || !session.branch_id) {
      return json(401, { code: "SESSION_INVALID_OR_CLOSED", title: "Table session is invalid or closed", status: 401, traceId: requestId });
    }

    const responseBody = await issueToken(session, jwtSecret, projectRef);
    return new Response(JSON.stringify(responseBody), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json", "Cache-Control": "no-store" } });
  } catch (error) {
    console.error(JSON.stringify({ level: "error", event: "customer_token.failed", requestId, message: String(error) }));
    return json(500, { code: "CUSTOMER_TOKEN_FAILED", title: "Could not create customer session", status: 500, traceId: requestId });
  }
});
