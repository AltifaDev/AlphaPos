export default {
  async fetch(request, env, ctx) {
    try {
      const url = new URL(request.url);

      // Never cache index.html — always serve fresh so asset ?v= bumps take effect immediately
      const isHtml = url.pathname === "/" || url.pathname.endsWith(".html");

      // Production must be explicitly configured. A loopback/LAN fallback
      // would point customers at the wrong machine.
      if (url.pathname === "/config.js" || url.pathname === "config.js") {
        if (!env.SUPABASE_URL || !env.SUPABASE_ANON_KEY || !env.MERCHANT_ID) {
          return new Response("Missing Supabase Worker configuration", { status: 500 });
        }
        const configJs = `window.ALPHAPOS_CONFIG = ${JSON.stringify({
          supabaseUrl: env.SUPABASE_URL,
          supabaseKey: env.SUPABASE_ANON_KEY,
          merchantId: env.MERCHANT_ID,
          isProduction: true
        })};`;
        return new Response(configJs, {
          headers: {
            "Content-Type": "application/javascript",
            "Access-Control-Allow-Origin": "*"
          }
        });
      }

      // Otherwise, fall back to serving static assets
      const assetResponse = await env.ASSETS.fetch(request);

      if (isHtml) {
        // Strip Cloudflare's default cache headers for HTML — force revalidation every time
        const newHeaders = new Headers(assetResponse.headers);
        newHeaders.set("Cache-Control", "no-cache, no-store, must-revalidate");
        newHeaders.set("Pragma", "no-cache");
        newHeaders.set("Expires", "0");
        return new Response(assetResponse.body, {
          status: assetResponse.status,
          headers: newHeaders,
        });
      }

      return assetResponse;
    } catch (err) {
      return new Response("Not Found", { status: 404 });
    }
  }
};
