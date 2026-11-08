// The mini player of ADR 0028: a pill at the end of the timeline, play/pause beside the square cover, no text.
"use strict";

(() => {
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

  let pill = null;
  const width = 116;
  root.style.setProperty("--edge-pill-width", width + "px");

  K.setMini({
    build() {
      if (!K.current() || pill) return;
      // The cover opens the player page, so the player page shows the pill without it (ADR 0015).
      const withCover = !chrome.player;
      pill = el("div", { class: "edge-pill glass" }, ppButton(""));
      if (withCover) pill.append(el("a", { class: "cover-link", href: playerHref(), "aria-label": "Open what plays" }, K.coverImage(K.current().album)));
      document.body.append(pill);
      root.classList.add("has-edge-pill");
      if (!withCover) root.style.setProperty("--edge-pill-width", "64px");
    },
    remove() {
      if (pill) { pill.remove(); pill = null; }
      root.classList.remove("has-edge-pill");
      root.style.setProperty("--edge-pill-width", width + "px");
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
    searchItems() { return { lead: [], trail: [], hideCard: true }; },
  });
})();
