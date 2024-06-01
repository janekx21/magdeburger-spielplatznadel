self.addEventListener("install", function (e) {
  // console.log("Service Worker install disabled");
  // return;
  console.log("PWA about to install");
  e.waitUntil(
    caches
      .open("magdeburger-spielplatznadel")
      .then(async (cache) => {
        const frontendLocation = self.performance
          .getEntriesByType("resource")
          .filter(
            (x) =>
              x instanceof PerformanceResourceTiming &&
              x.initiatorType == "script" &&
              x.name.includes("frontend"),
          )
          .at(0).name;

        console.log(
          (frontendLocation = self.performance.getEntriesByType("resource")),
        );

        console.log("Service Worker will cache now");
        console.log("frontend is at frontendLocation");
        const cacheList = [
          "/",
          "/manifest.json",
          // "/elm.js", // not needed?
          // "/frontend.e3jhrsqq.js",
          "/assets/Itim-Regular.ttf",
          "/assets/css/app.css",
          "/assets/images/logo.svg",
          "/assets/images/stamp.svg",
          "/assets/images/playground_icon_1.png",
          "/assets/images/playground_icon_1_shadow.png",
          "/assets/images/logo/logo72x72.png",
          "/assets/images/logo/logo96x96.png",
          "/assets/images/logo/logo128x128.png",
          "/assets/images/logo/logo144x144.png",
          "/assets/images/logo/logo152x152.png",
          "/assets/images/logo/logo192x192.png",
          "/assets/images/logo/logo384x384.png",
          "/assets/images/logo/logo512x512.png",
          "/assets/images/screenshots/pixel7_home.png",
          "/manifest.json",
          "/custom_elements.js",
          "/service_worker.js",
          "https://unpkg.com/leaflet@1.9.4/dist/leaflet.css",
          "https://unpkg.com/leaflet@1.9.4/dist/leaflet.js",
          "https://fonts.googleapis.com/css?family=Itim",
          frontendLocation,
        ];
        for (const addr of cacheList) {
          console.log("caching", addr);
          await cache.add(addr);
        }
        return cache.addAll([]);
      })
      .catch((error) => console.error(error)),
  );
});

self.addEventListener("fetch", function (event) {
  event.respondWith(
    caches.match(event.request).then((response) => {
      if (response) {
        console.log("[fetch from cache]", response.url);
        return response;
      } else {
        console.log("(fetch from web)", event.request.url);
        return fetch(event.request);
      }
    }),
  );
});
