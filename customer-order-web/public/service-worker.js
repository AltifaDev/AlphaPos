const CACHE_NAME = 'alphapos-customer-web-v24';
const ASSETS_TO_CACHE = [
    './',
    './index.html',
    './config.js'
    // Note: app.js, styles.css, hybrid-location.js are bundled into /assets/ by Vite
    // The bundled assets are cached dynamically by the fetch handler below
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

// Fetch Event (Cache-First, Fallback to Network)
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

    // Always check for a fresh app shell so deployments do not keep serving
    // an old hashed bundle from the service-worker cache.
    if (event.request.mode === 'navigate' || url.pathname === '/' || url.pathname.endsWith('.html')) {
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
                        // Dynamically cache new GET requests (like remote static assets)
                        if (networkResponse && networkResponse.status === 200) {
                            const responseClone = networkResponse.clone();
                            caches.open(CACHE_NAME).then((cache) => {
                                cache.put(event.request, responseClone);
                            });
                        }
                        return networkResponse;
                    })
                    .catch(() => {
                        // Return empty response or basic offline page placeholder if needed
                    });
            })
    );
});
