export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    // Serve config.js dynamically using Cloudflare Worker environment variables
    if (url.pathname === "/config.js" || url.pathname === "config.js") {
      const configJs = `window.ALPHAPOS_CONFIG = {
  supabaseUrl: "${env.SUPABASE_URL || ''}",
  supabaseKey: "${env.SUPABASE_ANON_KEY || ''}",
  merchantId: "${env.MERCHANT_ID || ''}",
  isProduction: true
};`;
      return new Response(configJs, {
        headers: {
          "Content-Type": "application/javascript",
          "Access-Control-Allow-Origin": "*"
        }
      });
    }

    // Otherwise, fall back to serving static assets
    return env.ASSETS.fetch(request);
  }
};
