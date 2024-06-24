exports.init = async function (app) {
  // console.log("geo-location.js")
  if (navigator.geolocation) {
    // The next request is only needed for the location promt
    navigator.geolocation.getCurrentPosition((_) => {});
    navigator.geolocation.watchPosition(
      (position) => {
        const lat = position.coords.latitude;
        const lng = position.coords.longitude;
        let heading = position.coords.heading;
        const location = { lat, lng };
        const geoLocation = { location, heading };
        // console.log("locationUpdated", geoLocation)
        app.ports.geoLocationUpdated.send(JSON.stringify(geoLocation));
      },
      (_) => {
        // TODO some error handling like a user message
        app.ports.geoLocationError.send("");
      },
    ); // TODO options
  }
};
