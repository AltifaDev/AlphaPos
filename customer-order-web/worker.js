export default {
  async fetch(request, env, ctx) {
    try {
      const url = new URL(request.url);

      // Serve config.js dynamically using Cloudflare Worker environment variables or fallbacks
      if (url.pathname === "/config.js" || url.pathname === "config.js") {
        const configJs = `window.ALPHAPOS_CONFIG = {
  supabaseUrl: "${env.SUPABASE_URL || 'https://sdmtkixrqkmwcpwoisrg.supabase.co'}",
  supabaseKey: "${env.SUPABASE_ANON_KEY || 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNkbXRraXhycWttd2Nwd29pc3JnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA4NDIxNjAsImV4cCI6MjA5NjQxODE2MH0.rjLwVE0ShXIFoT0k982XO_lVCQMsA4uTKMW1Su-NUws'}",
  merchantId: "${env.MERCHANT_ID || '163350b0-056d-4d5e-b5d4-24e7aac5ab6d'}",
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
      return await env.ASSETS.fetch(request);
    } catch (err) {
      return new Response("Not Found", { status: 404 });
    }
  }
};
