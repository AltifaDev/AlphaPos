const CACHE_NAME = 'alphapos-customer-web-v41';
// Do NOT precache config.js — it is merchant/runtime-specific and always network-only.
const ASSETS_TO_CACHE = [
    './',
    './index.html'
    // Note: app.js / styles.css (and modules under js/) are bundled into /assets/ by Vite.
    // Bundled assets are cached dynamically by the fetch handler below.
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
    // Avoid caching POST requests or non-HTTP protocols (e.g. chrome-extension)
    if (event.request.method !== 'GET' || !event.request.url.startsWith(self.location.origin)) {
        return;
    }

    const url = new URL(event.request.url);
    if (url.pathname.startsWith('/v1/') || url.pathname === '/config.js') {
        event.respondWith(fetch(event.request));
        return;
    }

    // Deployments must win over stale cached application code.
    if (event.request.mode === 'navigate' || /\.(?:html|js|css)$/.test(url.pathname)) {
        event.respondWith(
            fetch(event.request)
                .then((response) => {
                    const clone = response.clone();
                    caches.open(CACHE_NAME).then((cache) => cache.put(event.request, clone));
                    return response;
                })
                .catch(() => caches.match(event.request))
        );
        return;
    }

    event.respondWith(
        caches.match(event.request)
            .then((cachedResponse) => {
                if (cachedResponse) {
                    return cachedResponse;
                }

                return fetch(event.request)
                    .then((networkResponse) => {
                        if (networkResponse && networkResponse.status === 200) {
                            const responseClone = networkResponse.clone();
                            caches.open(CACHE_NAME).then((cache) => {
                                cache.put(event.request, responseClone);
                            });
                        }
                        return networkResponse;
                    })
                    .catch(() => {
                        // offline placeholder
                    });
            })
    );
});
