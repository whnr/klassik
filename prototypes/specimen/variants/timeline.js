// PROTOTYPE, round 25, sz-rs30.1.83.21: the gap between two timeline segments, for each look.
"use strict";
(() => {
  const look = document.documentElement.dataset.look;
  const stamp = new URL(document.currentScript.src).searchParams.get("v") || "";
  // B: a hairline between movements, a wider gap where a work changes. A and C: one gap everywhere.
  K.setTimeline({ gap: (count, sameWork) => (look === "tl-b" ? (sameWork ? 1 : 4) : 2) });
  // The person page keeps the decided picture look (sz-rs30.1.83.19.9, look B), so the keyline shows over a picture.
  if (document.documentElement.dataset.page === "person") {
    document.documentElement.dataset.pic = "scrim";
    document.head.append(Object.assign(document.createElement("link"), { rel: "stylesheet", href: "variants/pictures.css?v=" + stamp }));
    document.head.append(Object.assign(document.createElement("script"), { src: "variants/pictures.js?v=" + stamp }));
  }
})();
