// Mini player round (sz-rs30.1.83.9). Flo's goal: vertical space. Four answers to "how does what plays sit at the bottom?"
// mini-side: a pill out of the timeline in the tab row, play/pause and cover side by side.
// mini-tabs: play/pause in the middle of the tab capsule, the cover alone out of the timeline.
// mini-card: the card of ADR 0014 with a pause button, as the baseline.
"use strict";

(() => {
  const name = K.params.get("variant");
  const { el, ICON, chrome } = K;
  const root = document.documentElement;

  function ppButton(cls) {
    const b = el("button", { class: "pp " + cls, onclick: (e) => { e.preventDefault(); e.stopPropagation(); K.togglePause(); } });
    paint(b);
    return b;
  }
  function paint(b) {
    b.innerHTML = K.P.paused ? ICON.play : ICON.pause;
    b.setAttribute("aria-label", K.P.paused ? "Play" : "Pause");
  }
  const paintAll = () => document.querySelectorAll(".pp").forEach(paint);
  const playerHref = () => K.href("player.html", { back: chrome.title || null });

  if (name === "mini-card") {
    const card = K.cardMini;
    K.setMini({
      build() { card.build(); if (chrome.mini && !chrome.mini.querySelector(".pp")) chrome.mini.append(ppButton("")); },
      update() { card.update(); paintAll(); },
      searchItems() { return { lead: [], trail: [], hideCard: false }; },
    });
    return;
  }

  const shapes = { "mini-side": "side", "mini-tabs": "tabs" };
  const shape = shapes[name];
  if (!shape) return;

  let pill = null, tabPP = null;
  const width = shape === "side" ? 116 : 64;
  root.style.setProperty("--edge-pill-width", width + "px");

  K.setMini({
    build() {
      if (!K.current()) return;
      if (shape === "tabs" && chrome.tabbar && !tabPP) {
        const tabs = chrome.tabbar.querySelector(".tabs");
        if (tabs) { tabPP = ppButton(""); tabs.insertBefore(tabPP, tabs.children[2]); }
      }
      // The cover opens the player page, so the player page shows the pill without it (ADR 0015).
      const withCover = !chrome.player;
      const withPP = shape !== "tabs";
      if (!withCover && !withPP) return;
      pill = el("div", { class: "edge-pill glass" });
      if (withPP) pill.append(ppButton(""));
      if (withCover) pill.append(el("a", { class: "cover-link", href: playerHref(), "aria-label": "Open what plays" }, K.coverImage(K.current().album)));
      document.body.append(pill);
      root.classList.add("has-edge-pill");
      if (!withCover) root.style.setProperty("--edge-pill-width", "64px");
    },
    remove() {
      if (pill) { pill.remove(); pill = null; }
      root.classList.remove("has-edge-pill");
      root.style.setProperty("--edge-pill-width", width + "px");
      if (!K.current() && tabPP) { tabPP.remove(); tabPP = null; }
    },
    // The timeline runs into the pill's flat face.
    place(bottom, gap) {
      if (!pill) return { timelineBottom: bottom, reserve: 0 };
      const top = pill.getBoundingClientRect().top;
      const tabTop = bottom + gap;
      return { timelineBottom: top, reserve: Math.max(0, tabTop - top) };
    },
    update() {
      const key = K.current().id;
      if (pill && pill.dataset.key !== key) {
        pill.dataset.key = key;
        const link = pill.querySelector(".cover-link");
        if (link) link.replaceChildren(K.coverImage(K.current().album));
      }
      paintAll();
    },
    searchItems() {
      return { lead: [], trail: shape === "tabs" && K.current() ? [ppButton("roundglass glass fold")] : [], hideCard: true };
    },
  });
})();
