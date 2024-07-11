exports.init = async function (app) {
  const key = "storage";
  console.log("------- storageLoaded", localStorage.getItem(key));
  app.ports.storageLoaded.send(localStorage.getItem(key));
  app.ports.saveStorage.subscribe((data) => {
    console.log("saveStorage", data);
    localStorage.setItem(key, data);
  });
};
