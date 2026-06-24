export default {
  async fetch(request, env, ctx) {
    try {
      const url = new URL(request.url);

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
      return await env.ASSETS.fetch(request);
    } catch (err) {
      return new Response("Not Found", { status: 404 });
    }
  }
};
