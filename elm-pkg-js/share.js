exports.init = async function (app) {
  app.ports.share.subscribe((data) => {
    console.log("sharing data", data);
    Promise.all(data.files.map(dataUrlToFile)).then((files) => {
      console.log(files);
      if (navigator.share) {
        navigator
          .share({ ...data, files })
          .then(() => console.log("Successful share"))
          .catch((error) => console.log("Error sharing", error));
      } else {
        console.log("Share not supported on this browser, do it the old way.");
      }
    });
  });
};

// @param {string} dataUrl
async function dataUrlToFile(dataUrl) {
  const response = await fetch(dataUrl);
  console.log(response);
  const blob = response.blob();
  console.log(blob.type);
  return new File([blob], "shared.png", { type: "image/png" });
}
