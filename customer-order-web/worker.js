export default {
  async fetch(request, env, ctx) {
    try {
      const url = new URL(request.url);

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
        const backendUrlStr = env.SUPABASE_URL || "http://119.59.99.163.nip.io";
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
        const localServerUrlStr = env.LOCAL_SERVER_URL || "http://119.59.99.163.nip.io:8080";
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
      const isHtml = url.pathname === "/" || url.pathname.endsWith(".html");

      // Production must be explicitly configured. A loopback/LAN fallback
      // would point customers at the wrong machine.
      if (url.pathname === "/config.js" || url.pathname === "config.js") {
        if (!env.SUPABASE_URL || !env.SUPABASE_ANON_KEY || !env.MERCHANT_ID) {
          return new Response("Missing Supabase Worker configuration", { status: 500 });
        }
        // Force the supabaseUrl and localServerURL to point to the Cloudflare Worker itself to route through the proxy!
        const configJs = `window.ALPHAPOS_CONFIG = ${JSON.stringify({
          supabaseUrl: url.origin,
          supabaseKey: env.SUPABASE_ANON_KEY,
          localServerURL: url.origin,
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
            "Access-Control-Allow-Origin": "*"
          }
        });
      }

      return assetResponse;
    } catch (err) {
      return new Response("Not Found", { status: 404 });
    }
  }
};
