self.addEventListener("install", function (e) {
  console.log("Service Worker cache disabled");
  return;
  e.waitUntil(
    caches.open("dwylapp").then(function (cache) {
      console.log("Service Worker will cache now");
      return cache.addAll([
        "/",
        "/manifest.json",
        "/elm.js",
        "/assets/images/dwyl.png",
        "/assets/images/signal_wifi_off.svg",
        "/assets/css/tachyons.css",
        "/assets/css/app.css",
      ]);
    }),
  );
});

self.addEventListener("fetch", function (event) {
  console.log("Service Worker cache disabled");
  return;
  event.respondWith(
    caches.match(event.request).then(function (response) {
      return response || fetch(event.request);
    }),
  );
});
