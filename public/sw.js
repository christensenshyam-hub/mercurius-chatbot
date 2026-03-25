// Mercurius Ⅰ Service Worker — enables PWA install + basic caching
var CACHE_NAME = 'mercurius-v1';
var STATIC_ASSETS = [
  '/',
  '/widget.js',
  '/widget.css',
  '/manifest.json',
  '/icons/icon-192.png',
  '/icons/icon-512.png'
];

// Install — cache static assets
self.addEventListener('install', function(event) {
  event.waitUntil(
    caches.open(CACHE_NAME).then(function(cache) {
      return cache.addAll(STATIC_ASSETS);
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

// Fetch — network-first for API calls, cache-first for static assets
self.addEventListener('fetch', function(event) {
  var url = new URL(event.request.url);

  // Always go to network for API calls
  if (url.pathname.startsWith('/api/')) {
    return;
  }

  event.respondWith(
    fetch(event.request).then(function(response) {
      // Cache successful responses
      if (response.ok) {
        var clone = response.clone();
        caches.open(CACHE_NAME).then(function(cache) {
          cache.put(event.request, clone);
        });
      }
      return response;
    }).catch(function() {
      // Fallback to cache if offline
      return caches.match(event.request);
    })
  );
});
