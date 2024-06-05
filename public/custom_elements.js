class MyCustomElement extends HTMLElement {
  static observedAttributes = ["lat-lng", "markers"];
  map = null;
  latLng = [0, 0];
  markers = [];

  playgroundIcon = null;

  constructor() {
    // Always call super first in constructor
    super();
    this.map = null;
  }

  connectedCallback() {
    // console.log(`Map elment added to page with ${this.latLng}`);

    //const container = document.createElement("div");

    this.map = L.map(this, {
      zoomControl: false,
      attributionControl: false,
    }).setView([this.latLng.lat, this.latLng.lng], 12);


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

    console.log(this.markers)
    for (const marker of this.markers) {
      L.marker([marker.lat, marker.lng], { icon: this.playgroundIcon })
          .addTo(this.map)
          .bindPopup("Spielplatz Alter Markt<br>Platzhalter");
      // .openPopup();
    }
  }

  disconnectedCallback() {
    // console.log("Custom element removed from page.");
  }

  adoptedCallback() {
    // console.log("Custom element moved to new page.");
  }

  attributeChangedCallback(name, oldValue, newValue) {
    switch (name) {
      case "lat-lng":
        this.latLng = JSON.parse(newValue);
        if (this.map != null) {
          this.map.setView([this.latLng.lat, this.latLng.lng], 13);
        }
        break;
      case "markers":
        this.markers = JSON.parse(newValue);
        if (this.map != null) {
          //this.map.setView(latLng, 13);
        }
        break;
    }
  }
}

customElements.define("leaflet-map", MyCustomElement);
