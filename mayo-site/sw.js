// Mercurius Ⅰ Service Worker — enables PWA install + basic caching
var CACHE_NAME = 'mercurius-v3';
var STATIC_ASSETS = [
  '/mercurius.html',
  '/widget.js',
  '/widget.css',
  '/manifest.json'
];

// Install — cache static assets
self.addEventListener('install', function(event) {
  event.waitUntil(
    caches.open(CACHE_NAME).then(function(cache) {
      return cache.addAll(STATIC_ASSETS).catch(function() {
        // Don't fail install if some assets can't be cached
      });
    })
  );
  self.skipWaiting();
});

// Activate — clean old caches
self.addEventListener('activate', function(event) {
  event.waitUntil(
    caches.keys().then(function(names) {
      return Promise.all(
        names.filter(function(n) { return n !== CACHE_NAME; })
             .map(function(n) { return caches.delete(n); })
      );
    })
  );
  self.clients.claim();
});

// Fetch — ONLY intercept requests for cached mercurius assets
// Let everything else pass through to the network untouched
self.addEventListener('fetch', function(event) {
  var url = new URL(event.request.url);

  // Only handle same-origin, non-API, GET requests for known static assets
  if (url.origin !== self.location.origin) return;
  if (event.request.method !== 'GET') return;
  if (url.pathname.startsWith('/api/')) return;

  // Only intercept if this is a cached asset path
  var isCachedAsset = STATIC_ASSETS.indexOf(url.pathname) !== -1;
  if (!isCachedAsset) return; // Let the browser handle it normally

  event.respondWith(
    fetch(event.request).then(function(response) {
      if (response && response.ok) {
        var clone = response.clone();
        caches.open(CACHE_NAME).then(function(cache) {
          cache.put(event.request, clone);
        });
      }
      return response;
    }).catch(function() {
      return caches.match(event.request).then(function(cached) {
        // Return cached version, or let browser show its own error
        return cached || new Response('Offline — please check your connection.', {
          status: 503,
          headers: { 'Content-Type': 'text/plain' }
        });
      });
    })
  );
});
