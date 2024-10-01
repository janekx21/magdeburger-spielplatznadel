class MyCustomElement extends HTMLElement {
  static observedAttributes = ["data"];
  map = null;
  data = null;

  markers = [];

  constructor() {
    // Always call super first in constructor
    super();
    this.map = null;
    this.markers = [];
  }

  connectedCallback() {
    // console.log(`Map elment added to page with ${this.latLng}`);

    //const container = document.createElement("div");
    console.log("this.data in connected callback", this.data);

    this.map = L.map(this, {
      zoomControl: false,
      attributionControl: false,
    }).setView(
      [this.data.camera.location.lat, this.data.camera.location.lng],
      this.data.camera.zoom,
    );

    this.map.on("click", (e) => {
      const { lat, lng } = e.latlng;
      const detail = { lat, lng };
      const event = new CustomEvent("click_elm", { detail });
      this.dispatchEvent(event);
    });

    // this.map.on("move", (e) => {
    //   if (e.originalEvent) {
    //     const { lat, lng } = this.map.getCenter();
    //     const detail = { lat, lng };
    //     const event = new CustomEvent("moveend_elm", { detail });
    //     this.dispatchEvent(event);
    //   }
    //   console.log(e);
    // });
    this.map.on("moveend", (e) => {
      // console.log(e);
      // console.log(this.map.getCenter());
      const { lat, lng } = this.map.getCenter();
      const zoom = this.map.getZoom();
      const location = { lat, lng };
      const detail = { location, zoom };
      const event = new CustomEvent("moveend_elm", { detail });
      this.dispatchEvent(event);
    });

    // https://wiki.openstreetmap.org/wiki/Raster_tile_providers
    // const adress =
    //   "https://tiles.stadiamaps.com/tiles/stamen_watercolor/{z}/{x}/{y}.jpg";
    const adress = "https://tile.openstreetmap.org/{z}/{x}/{y}.png";
    // https://tile.openstreetmap.org
    L.tileLayer(adress, {
      // {r}
      // attribution:
      //   '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
      // tileSize: 256,
      // zoomOffset: -1,
      detectRetina: false,
    }).addTo(this.map);

    this.update();
  }

  disconnectedCallback() {
    // console.log("Custom element removed from page.");
  }

  adoptedCallback() {
    // console.log("Custom element moved to new page.");
  }

  attributeChangedCallback(name, oldValue, newValue) {
    this.data = JSON.parse(newValue);
    this.update();
  }

  update() {
    if (this.map) {
      for (const marker of this.markers) {
        marker.remove();
      }
      this.markers = [];
      for (const marker of this.data.markers) {
        const icon = L.icon({
          iconUrl: marker.icon.url,
          iconSize: [50, 49],
          iconAnchor: [25, 49],
          popupAnchor: [-12, -30],
          shadowUrl: marker.icon.shadowUrl,
          shadowSize: [50, 49],
          shadowAnchor: [25, 49],
        });

        const m = L.marker([marker.location.lat, marker.location.lng], { icon })
          .addTo(this.map)
          .bindPopup(marker.popupText);
        // .openPopup();
        this.markers.push(m);
      }

      // if (this.map.getZoom() == this.data.camera.zoom) {
      //   this.map.panTo([
      //     this.data.camera.location.lat,
      //     this.data.camera.location.lng,
      //   ]);
      // } else {
      const { lat, lng } = this.map.getCenter();
      const zoom = this.map.getZoom();
      // console.log(
      //   "update current:",
      //   lat,
      //   "new",
      //   this.data.camera.location.lat,
      //   lat === this.data.camera.location.lat,
      // );
      if (
        this.data.camera.location.lat !== lat ||
        this.data.camera.location.lng !== lng ||
        this.data.camera.zoom !== zoom
      ) {
        this.map.setView(
          [this.data.camera.location.lat, this.data.camera.location.lng],
          this.data.camera.zoom,
        );
      }
      // }
    }
  }

  getIconLazy(url) {}
}

customElements.define("leaflet-map", MyCustomElement);
