exports.init = async function (app) {
  app.ports.share.subscribe((data) => {
    Promise.all(data.files.map(dataUrlToFile)).then((files) => {
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
  const blob = await response.blob();
  return new File([blob], "shared.png", { type: blob.type });
}
