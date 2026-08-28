const CACHE_NAME = 'alphapos-customer-web-v52';
// Do NOT precache config.js — it is merchant/runtime-specific and always network-only.
const ASSETS_TO_CACHE = [
    './index.html'
];

// Install Event
self.addEventListener('install', (event) => {
    event.waitUntil(
        caches.open(CACHE_NAME)
            .then((cache) => {
                console.log('[Service Worker] Caching app shell assets');
                return cache.addAll(ASSETS_TO_CACHE);
            })
            .then(() => self.skipWaiting())
            .catch((err) => {
                console.warn('[Service Worker] Precache failed (continuing):', err);
                return self.skipWaiting();
            })
    );
});

// Activate Event
self.addEventListener('activate', (event) => {
    event.waitUntil(
        caches.keys().then((cacheNames) => {
            return Promise.all(
                cacheNames.map((cache) => {
                    if (cache !== CACHE_NAME) {
                        console.log('[Service Worker] Clearing old cache:', cache);
                        return caches.delete(cache);
                    }
                })
            );
        }).then(() => self.clients.claim())
    );
});

// Fetch Event
self.addEventListener('fetch', (event) => {
    // Avoid caching POST requests, non-HTTP protocols, or video Range requests (which require native 206)
    if (event.request.method !== 'GET' || !event.request.url.startsWith(self.location.origin)) {
        return;
    }
    if (event.request.headers.get('range')) {
        return;
    }

    const url = new URL(event.request.url);
    if (url.pathname.startsWith('/v1/') || url.pathname === '/config.js') {
        event.respondWith(fetch(event.request));
        return;
    }

    const isHtmlOrNavigate = event.request.mode === 'navigate' ||
                             url.pathname === '/' ||
                             url.pathname === '/index.html' ||
                             url.pathname.endsWith('.html') ||
                             /\.(?:html|js|css)$/.test(url.pathname);

    // Deployments must win over stale cached application code (Network First with Cache Fallback)
    if (isHtmlOrNavigate) {
        event.respondWith(
            fetch(event.request)
                .then((response) => {
                    if (response && response.status === 200) {
                        const clone = response.clone();
                        caches.open(CACHE_NAME).then((cache) => cache.put(event.request, clone));
                    }
                    return response;
                })
                .catch(async () => {
                    const cached = await caches.match(event.request);
                    if (cached) return cached;
                    const fallbackHtml = await caches.match('./index.html') || await caches.match('/');
                    if (fallbackHtml) return fallbackHtml;
                    return fetch(event.request);
                })
        );
        return;
    }

    // Cache First with Network Fallback for static assets
    event.respondWith(
        caches.match(event.request)
            .then(async (cachedResponse) => {
                if (cachedResponse) {
                    return cachedResponse;
                }
                try {
                    const networkResponse = await fetch(event.request);
                    if (networkResponse && networkResponse.status === 200) {
                        const responseClone = networkResponse.clone();
                        caches.open(CACHE_NAME).then((cache) => {
                            cache.put(event.request, responseClone);
                        });
                    }
                    return networkResponse;
                } catch (err) {
                    return caches.match(event.request);
                }
            })
    );
});
