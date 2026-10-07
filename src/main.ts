// The shared app (the window showing reevun.app, updates), built from
// reevun-software/app-core into dist/core next to this file - so it's
// loaded from there at run time, and typed from there at build time.
const { startApp } = require("./core/electron/main") as typeof import("../dist/core/electron/main");

// The system traffic lights sit inside the app's own title strip, vertically
// centred in it; the strip leaves room for them on the left.
const TITLE_BAR_HEIGHT = 36;

startApp({
  platform: "macos",
  window: {
    titleBarStyle: "hidden",
    trafficLightPosition: { x: 14, y: 11 },
  },
  titleBar: { height: TITLE_BAR_HEIGHT, insetLeft: 72, insetRight: 0 },
});
