class MyCustomElement extends HTMLElement {
  static observedAttributes = ["data"];
  map = null;
  data = null;
  playgroundIcon = null;

  markers = [];

  constructor() {
    // Always call super first in constructor
    super();
    this.map = null;
    this.markers = []
  }

  connectedCallback() {
    // console.log(`Map elment added to page with ${this.latLng}`);

    //const container = document.createElement("div");
    console.log(this.data)

    this.map = L.map(this, {
      zoomControl: false,
      attributionControl: false,
    }).setView([this.data.camera.location.lat, this.data.camera.location.lng], this.data.camera.zoom);


    // https://wiki.openstreetmap.org/wiki/Raster_tile_providers
    // const adress =
    //   "https://tiles.stadiamaps.com/tiles/stamen_watercolor/{z}/{x}/{y}.jpg";
    const adress =
      "https://tile.openstreetmap.org/{z}/{x}/{y}.png";
    // https://tile.openstreetmap.org
    L.tileLayer(adress, {
      // {r}
      // attribution:
      //   '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
      // tileSize: 256,
      // zoomOffset: -1,
      detectRetina: false,
    }).addTo(this.map);

    this.playgroundIcon = L.icon({
      iconUrl: "/assets/images/playground_icon_1.png",
      iconSize: [50, 49],
      iconAnchor: [25, 49],
      popupAnchor: [-12, -30],
      shadowUrl: "/assets/images/playground_icon_1_shadow.png",
      shadowSize: [50, 49],
      shadowAnchor: [25, 49],
    });

    for (const marker of this.data.markers) {
      const m = L.marker([marker.lat, marker.lng], { icon: this.playgroundIcon })
          .addTo(this.map)
          .bindPopup("Spielplatz Alter Markt<br>Platzhalter");
      // .openPopup();
      this.markers.push(m)
    }
  }

  disconnectedCallback() {
    // console.log("Custom element removed from page.");
  }

  adoptedCallback() {
    // console.log("Custom element moved to new page.");
  }

  attributeChangedCallback(name, oldValue, newValue) {
    this.data = JSON.parse(newValue);
    if (this.map) {
      for (const marker of this.markers) {
        marker.remove()
      }
      this.markers = []
      for (const marker of this.data.markers) {
        console.log([marker.lat, marker.lng])
        const m = L.marker([marker.lat, marker.lng], { icon: this.playgroundIcon })
            .addTo(this.map)
            .bindPopup("Spielplatz Alter Markt<br>Platzhalter");
        // .openPopup();
        this.markers.push(m)
      }
      this.map.setView([this.data.camera.location.lat, this.data.camera.location.lng], this.data.camera.zoom);
    }
  }
}

customElements.define("leaflet-map", MyCustomElement);
