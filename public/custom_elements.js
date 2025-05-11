class LeafletMap extends HTMLElement {
  static observedAttributes = ["data"];

  map = null; // Leaflet map object
  data = null; // The interop data
  markers = []; // The current markers

  constructor() {
    super();
    this.map = null;
    this.markers = [];
  }

  connectedCallback() {
    console.log("Leaflet Map: connect callback")
    // Init the map object
    this.map = L.map(this, {
      zoomControl: false,
      attributionControl: false,
    }).setView(
      [this.data.camera.location.lat, this.data.camera.location.lng],
      this.data.camera.zoom,
    );

    // Setup click event
    this.map.on("click", (e) => {
      const { lat, lng } = e.latlng;
      const detail = { lat, lng };
      const event = new CustomEvent("click_elm", { detail });
      this.dispatchEvent(event);
    });

    // Setup camera move event
    // TODO disabled this event because it's not needed and causes camera jitter
    // this.map.on("moveend", (e) => {
    //   console.log("Leaflet Map: moveend event", e)
    //   const { lat, lng } = this.map.getCenter();
    //   const zoom = this.map.getZoom();
    //   const location = { lat, lng };
    //   const detail = { location, zoom };
    //   const event = new CustomEvent("moveend_elm", { detail });
    //   this.dispatchEvent(event);
    // });

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

    this.update(null, this.data);
  }

  disconnectedCallback() {
    // console.log("Custom element removed from page.");
    this.map.remove()
  }

  adoptedCallback() {
    // console.log("Custom element moved to new page.");
  }

  attributeChangedCallback(name, oldValue, newValue) {
    console.log("Leaflet Map: attribute changed callback")
    const newData = JSON.parse(newValue);
    this.update(this.data, newData);
  }

  update(oldData, newData) {
    // if (JSON.stringify(newData) != JSON.stringify(oldData)) {
    //   this.data = newData;
    //   // this.update();
    // } else {
      // console.log("Leaflet Map: data did not change")
    // }
    console.log("Leaflet Map: update from ", oldData, " to ", newData)

    if (this.map) {

      if (oldData == null || JSON.stringify(newData.markers) != JSON.stringify(oldData.markers)) {
        this.data.markers = newData.markers;
        // Clear markers
        for (const marker of this.markers) {
          marker.remove();
        }
        this.markers = [];

        // Add markers from interop data
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

          // TODO popup mouse events or href links are not working sadly
          // const p = L.popup({
          //     content: marker.popupText,
          //     // interactive: true, // Listen for mouse events
          //     // bubblingMouseEvents: false,
          //   })
            // .on("click", (e) => console.log("Leaflet Map: popup click event", e, marker))
            // .on("mousedown", (e) => console.log("Leaflet Map: popup click event", e, marker))

          const m = L.marker([marker.location.lat, marker.location.lng], { icon, opacity: marker.opacity })
            .addTo(this.map)
            // .bindPopup(p)
            .on("click", (e) => {
              console.log("Leaflet Map: marker click event", e, marker);
              const detail = marker;
              const event = new CustomEvent("click_marker_elm", { detail });
              this.dispatchEvent(event);
            });

          this.markers.push(m);
        }
      }

      if (oldData == null || JSON.stringify(newData.camera) != JSON.stringify(oldData.camera)) {
        // Move the map camera to new location and zoom based on interop data
        const { lat, lng } = this.map.getCenter();
        const zoom = this.map.getZoom();
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
      }
    } else {
      this.data = newData;
    }
  }

  getIconLazy(url) {}
}

customElements.define("leaflet-map", LeafletMap);
