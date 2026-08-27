export default {
  async fetch(request, env, ctx) {
    try {
      const url = new URL(request.url);
      const supabaseOrigin = (env.SUPABASE_URL || "https://api.alphaposweb.com").replace(/\/$/, "");
      const supabaseWs = supabaseOrigin
        .replace("https://", "wss://")
        .replace("http://", "ws://");
      const csp = [
        "default-src 'self'",
        "media-src 'self' blob: https:",
        "script-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net https://unpkg.com",
        "style-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net https://fonts.googleapis.com",
        "img-src 'self' data: https:",
        `connect-src 'self' https://cdn.jsdelivr.net ${supabaseOrigin} ${supabaseWs}`,
        "font-src 'self' data: https://fonts.gstatic.com",
        "frame-ancestors 'none'",
      ].join("; ");

      // Handle CORS preflight options directly
      if (request.method === "OPTIONS") {
        return new Response(null, {
          headers: {
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, PATCH, OPTIONS",
            "Access-Control-Allow-Headers": "*",
            "Access-Control-Max-Age": "86400"
          }
        });
      }

      // Proxy Supabase REST, Auth, and Functions API requests to avoid Mixed Content (HTTP/HTTPS) issues
      if (
        url.pathname.startsWith("/rest/v1/") ||
        url.pathname.startsWith("/auth/v1/") ||
        url.pathname.startsWith("/functions/v1/")
      ) {
        const backendUrlStr = env.SUPABASE_URL;
        if (!backendUrlStr) {
          return new Response("Supabase URL is not configured", { status: 500 });
        }
        const backendBase = new URL(backendUrlStr);
        
        const targetUrl = new URL(request.url);
        targetUrl.protocol = backendBase.protocol;
        targetUrl.host = backendBase.host;
        targetUrl.port = backendBase.port;

        const headers = new Headers(request.headers);
        headers.set("Host", backendBase.host);
        
        const requestInit = {
          method: request.method,
          headers: headers,
          redirect: "manual"
        };
        
        if (request.method !== "GET" && request.method !== "HEAD") {
          requestInit.body = request.clone().body;
        }
        
        const proxyResponse = await fetch(targetUrl.toString(), requestInit);
        
        const responseHeaders = new Headers(proxyResponse.headers);
        responseHeaders.set("Access-Control-Allow-Origin", "*");
        responseHeaders.set("Access-Control-Allow-Headers", "*");
        responseHeaders.set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, PATCH, OPTIONS");
        
        return new Response(proxyResponse.body, {
          status: proxyResponse.status,
          statusText: proxyResponse.statusText,
          headers: responseHeaders
        });
      }

      // Proxy Local Server API requests (/v1/) to VPS port 8080
      if (url.pathname.startsWith("/v1/")) {
        const localServerUrlStr = env.LOCAL_SERVER_URL;
        if (!localServerUrlStr) {
          return new Response("Local server URL is not configured", { status: 500 });
        }
        const backendBase = new URL(localServerUrlStr);
        
        const targetUrl = new URL(request.url);
        targetUrl.protocol = backendBase.protocol;
        targetUrl.host = backendBase.host;
        targetUrl.port = backendBase.port;

        const headers = new Headers(request.headers);
        headers.set("Host", backendBase.host);
        
        const requestInit = {
          method: request.method,
          headers: headers,
          redirect: "manual"
        };
        
        if (request.method !== "GET" && request.method !== "HEAD") {
          requestInit.body = request.clone().body;
        }
        
        const proxyResponse = await fetch(targetUrl.toString(), requestInit);
        
        const responseHeaders = new Headers(proxyResponse.headers);
        responseHeaders.set("Access-Control-Allow-Origin", "*");
        responseHeaders.set("Access-Control-Allow-Headers", "*");
        responseHeaders.set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, PATCH, OPTIONS");
        
        return new Response(proxyResponse.body, {
          status: proxyResponse.status,
          statusText: proxyResponse.statusText,
          headers: responseHeaders
        });
      }

      // Never cache index.html — always serve fresh so asset ?v= bumps take effect immediately
      const isHtml = url.pathname === "/" || url.pathname === "/privacy" || url.pathname.endsWith(".html");

      // Production must be explicitly configured. A loopback/LAN fallback
      // would point customers at the wrong machine.
      if (url.pathname === "/config.js" || url.pathname === "config.js") {
        const supabaseAnonKey = env.SUPABASE_LEGACY_ANON_KEY || env.SUPABASE_ANON_KEY;
        // MERCHANT_ID is optional. In multi-tenant mode the merchant is taken from
        // the QR code URL (?merchant=<uuid> or ?jwt=<token>) and resolved client-side
        // in app.js. A configured env.MERCHANT_ID (if present) only acts as a
        // single-tenant fallback for deployments that serve exactly one store.
        if (!env.SUPABASE_URL || !supabaseAnonKey) {
          return new Response("Missing Supabase Worker configuration", { status: 500 });
        }
        // REST goes through this Worker (HTTPS proxy). Realtime WSS must hit the
        // public Supabase API host directly — Workers cannot upgrade WebSockets
        // to the self-hosted Kong/Realtime stack.
        const realtimeUrl = env.SUPABASE_URL || "https://api.alphaposweb.com";
        const configJs = `window.ALPHAPOS_CONFIG = ${JSON.stringify({
          supabaseUrl: url.origin,
          supabaseRealtimeUrl: realtimeUrl,
          supabaseKey: supabaseAnonKey,
          localServerURL: url.origin,
          merchantId: env.MERCHANT_ID || "",
          isProduction: true
        })};`;
        return new Response(configJs, {
          headers: {
            "Content-Type": "application/javascript",
            "Access-Control-Allow-Origin": "*",
            "Cache-Control": "no-cache, no-store, must-revalidate",
            "Pragma": "no-cache",
            "Expires": "0"
          }
        });
      }

      if (url.pathname === "/privacy") {
        url.pathname = "/privacy.html";
        request = new Request(url, request);
      }

      // Otherwise, fall back to serving static assets
      const assetResponse = await env.ASSETS.fetch(request);

      if (isHtml) {
        // Inject config.js before </head> so window.ALPHAPOS_CONFIG is always set
        // (Vite build removes the static <script src="config.js"> tag during bundling)
        const originalText = await assetResponse.text();
        const injectedHtml = originalText.replace(
          '</head>',
          `<script src="/config.js"></script>\n</head>`
        );
        return new Response(injectedHtml, {
          status: assetResponse.status,
          headers: {
            "Content-Type": "text/html; charset=utf-8",
            "Cache-Control": "no-cache, no-store, must-revalidate",
            "Pragma": "no-cache",
            "Expires": "0",
            "Access-Control-Allow-Origin": "*",
            "Content-Security-Policy": csp,
            "X-Content-Type-Options": "nosniff",
            "Referrer-Policy": "strict-origin-when-cross-origin",
          }
        });
      }

      return assetResponse;
    } catch (err) {
      return new Response("Not Found", { status: 404 });
    }
  }
};
