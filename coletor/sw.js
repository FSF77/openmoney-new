// OpenMoney Coletor Service Worker - Offline Cache
const CACHE_NAME = 'openmoney-coletor-v1.0.8';
const ASSETS = [
  './',
  './index.html',
  './manifest.json',
  './css/style.css',
  './js/models.js',
  './js/db.js',
  './js/ocr.js',
  './js/voice.js',
  './js/app.js',
  './icons/apple-touch-icon.png',
  './icons/icon-192.png',
  './icons/icon-512.png',
  './icons/favicon-32.png'
];

self.addEventListener('install', (e) => {
  e.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      return cache.addAll(ASSETS);
    }).then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys().then((keys) => {
      return Promise.all(
        keys.filter((key) => key !== CACHE_NAME).map((key) => caches.delete(key))
      );
    }).then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (e) => {
  if (e.request.method !== 'GET') return;
  // Let CDN requests (like Tesseract WASM/worker) pass to network or browser cache
  if (e.request.url.includes('cdn.jsdelivr.net') || e.request.url.includes('tesseract')) {
    return;
  }

  const url = e.request.url;
  const isCodeOrDoc = url.endsWith('.js') || url.includes('.js?') || url.endsWith('.html') || url.endsWith('/') || e.request.mode === 'navigate';

  if (isCodeOrDoc) {
    // Network First for scripts and HTML to ensure immediate code delivery
    e.respondWith(
      fetch(e.request)
        .then((res) => {
          if (res && res.status === 200) {
            const clone = res.clone();
            caches.open(CACHE_NAME).then((c) => c.put(e.request, clone));
          }
          return res;
        })
        .catch(() => caches.match(e.request).then(cached => cached || caches.match('./index.html')))
    );
    return;
  }

  // Cache First for icons, manifest, static assets
  e.respondWith(
    caches.match(e.request).then((cached) => {
      if (cached) return cached;
      return fetch(e.request).then((res) => {
        if (res && res.status === 200) {
          const clone = res.clone();
          caches.open(CACHE_NAME).then((c) => c.put(e.request, clone));
        }
        return res;
      });
    })
  );
});
