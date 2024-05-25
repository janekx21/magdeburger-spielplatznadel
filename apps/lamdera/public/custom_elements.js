class MyCustomElement extends HTMLElement {
  static observedAttributes = ["lat-lng"];
  map = null;
  latLng = [0, 0];

  constructor() {
    // Always call super first in constructor
    super();
    this.map = null;
  }

  connectedCallback() {
    console.log(`Map elment added to page with ${this.latLng}`);

    //const container = document.createElement("div");

    this.map = L.map(this, {
      zoomControl: false,
      attributionControl: false,
    }).setView(this.latLng, 12);

    var myIcon = L.icon({
      iconUrl: "/assets/images/playground_icon_1.png",
      iconSize: [50, 49],
      iconAnchor: [25, 49],
      popupAnchor: [-12, -30],
      // shadowUrl: "my-icon-shadow.png",
      // shadowSize: [68, 95],
      // shadowAnchor: [22, 94],
    });

    L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
      // attribution:
      //   '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
    }).addTo(this.map);

    L.marker([52.131667, 11.639167], { icon: myIcon })
      .addTo(this.map)
      .bindPopup("Spielplatz Alter Markt<br>Platzhalter");
    // .openPopup();
  }

  disconnectedCallback() {
    console.log("Custom element removed from page.");
  }

  adoptedCallback() {
    console.log("Custom element moved to new page.");
  }

  attributeChangedCallback(name, oldValue, newValue) {
    console.log(`Attribute ${name} has changed to ${newValue}`);
    switch (name) {
      case "lat-lng":
        const latLng = newValue.split(",").map((x) => Number(x));
        this.latLng = latLng;
        console.log("latLng", latLng);
        if (this.map != null) {
          this.map.setView(latLng, 13);
        }
        break;
    }
  }
}

customElements.define("my-custom-element", MyCustomElement);
