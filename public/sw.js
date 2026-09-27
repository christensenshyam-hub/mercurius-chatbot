// Mercurius Ⅰ Service Worker — enables PWA install + an offline app shell.
// Bump CACHE_NAME whenever the cached files change shape; activate deletes
// every other cache.
var CACHE_NAME = 'mercurius-v2';
var STATIC_ASSETS = [
  '/',
  '/widget.js',
  '/widget.css',
  '/manifest.json',
  '/icons/icon-192.png',
  '/icons/icon-512.png'
];

// Only the app shell is handled; the API, admin.html and every other origin
// go straight to the network.
function isAppShell(url) {
  return url.pathname === '/' ||
    url.pathname === '/index.html' ||
    url.pathname === '/widget.js' ||
    url.pathname === '/widget.css' ||
    url.pathname === '/manifest.json' ||
    url.pathname.indexOf('/icons/') === 0;
}

// Install — cache static assets. One missing file must not fail the install.
self.addEventListener('install', function(event) {
  event.waitUntil(
    caches.open(CACHE_NAME).then(function(cache) {
      return Promise.all(STATIC_ASSETS.map(function(asset) {
        return cache.add(asset).catch(function() {});
      }));
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

// Fetch — network-first for the app shell, cache only as the offline fallback
self.addEventListener('fetch', function(event) {
  var req = event.request;
  if (req.method !== 'GET') return;
  var url = new URL(req.url);
  if (url.origin !== self.location.origin || !isAppShell(url)) return;

  event.respondWith(
    fetch(req).then(function(response) {
      if (response && response.ok) {
        var clone = response.clone();
        caches.open(CACHE_NAME).then(function(cache) {
          cache.put(req, clone);
        });
      }
      return response;
    }).catch(function() {
      // `?v=` cache-busters must still find the precached copy.
      return caches.match(req, { ignoreSearch: true }).then(function(cached) {
        return cached || Response.error();
      });
    })
  );
});
