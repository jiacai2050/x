// Qianliyan WebAssembly Service Worker for 100% Offline Capability
const CACHE_NAME = 'qianliyan-v1';

const PRECACHE_ASSETS = [
  './',
  './index.html',
  './qianliyan.wasm',
  './manifest.webmanifest',
  'https://cdn.tailwindcss.com',
  'https://esm.sh/@bjorn3/browser_wasi_shim@0.3.0/es2022/browser_wasi_shim.bundle.mjs',
];

// Install: Pre-cache all essential application assets
self.addEventListener('install', (event) => {
  event.waitUntil(
    caches
      .open(CACHE_NAME)
      .then(async (cache) => {
        await Promise.all(
          PRECACHE_ASSETS.map(async (url) => {
            try {
              const isExternalScript = url.includes('tailwindcss.com');
              const req = isExternalScript
                ? new Request(url, { mode: 'no-cors' })
                : new Request(url);
              const res = await fetch(req);
              if (res.status === 200 || res.type === 'opaque') {
                await cache.put(url, res);
              }
            } catch (err) {
              console.warn('Pre-cache warning for asset:', url, err);
            }
          }),
        );
      })
      .then(() => self.skipWaiting()),
  );
});

// Activate: Clean up outdated caches and claim clients immediately
self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((cacheNames) =>
        Promise.all(
          cacheNames
            .filter((name) => name !== CACHE_NAME)
            .map((name) => caches.delete(name)),
        ),
      )
      .then(() => self.clients.claim()),
  );
});

// Fetch: Cache-first strategy with dynamic fallback to network
self.addEventListener('fetch', (event) => {
  // Only handle standard HTTP/HTTPS GET requests
  if (event.request.method !== 'GET') return;

  event.respondWith(
    caches.match(event.request).then((cachedResponse) => {
      if (cachedResponse) {
        return cachedResponse;
      }

      return fetch(event.request)
        .then((networkResponse) => {
          // Cache successful responses for dynamic or external dependencies
          if (
            networkResponse &&
            (networkResponse.status === 200 ||
              networkResponse.type === 'opaque')
          ) {
            const responseToCache = networkResponse.clone();
            caches.open(CACHE_NAME).then((cache) => {
              cache.put(event.request, responseToCache);
            });
          }
          return networkResponse;
        })
        .catch(() => {
          // If offline and navigating, fallback to cached index.html
          if (event.request.mode === 'navigate') {
            return caches.match('./index.html') || caches.match('./');
          }
        });
    }),
  );
});
