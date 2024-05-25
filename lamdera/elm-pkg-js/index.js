exports.init = async function (app) {
  //   // window.addEventListener('online', function (e) {
  //   //   // sync data with server
  //   //   app.ports.online.send(true);
  //   // }, false);

  //   // window.addEventListener('offline', function (e) {
  //   //   // save data locally
  //   //   app.ports.online.send(false);
  //   // }, false);

  //   // app.ports.pouchDB.subscribe(function (capture) {
  //   //   console.log("capture offline", capture)
  //   //   saveCapture(capture)
  //   // });
  app.ports.pouchDB.subscribe((data) => {
    console.log(data);
  });
  console.log("hello world!", app);
};

// if ('serviceWorker' in navigator) {
//   navigator.serviceWorker
//     .register('/service_worker.js')
//     .then(function () {console.log("Service Worker Registered");});
// }

// Create a class for the element
// class MyCustomElement extends HTMLElement {
//   static observedAttributes = ["color", "size"];

//   constructor() {
//     // Always call super first in constructor
//     super();
//   }

//   connectedCallback() {
//     console.log("Custom element added to page.");

//     //const container = document.createElement("div");

//     var map = L.map(this).setView([51.505, -0.09], 13);

//     L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
//       attribution:
//         '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
//     }).addTo(map);

//     L.marker([51.5, -0.09])
//       .addTo(map)
//       .bindPopup("A pretty CSS popup.<br> Easily customizable.")
//       .openPopup();

//     console.log(map);
//     //console.log(container)
//     //this.appendChild(container)
//   }

//   disconnectedCallback() {
//     console.log("Custom element removed from page.");
//   }

//   adoptedCallback() {
//     console.log("Custom element moved to new page.");
//   }

//   attributeChangedCallback(name, oldValue, newValue) {
//     console.log(`Attribute ${name} has changed.`);
//   }
// }

// customElements.define("my-custom-element", MyCustomElement);
