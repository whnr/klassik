// The player overlay of ADR 0014. The pill's cover opens it. A drag down on its handle, or a tap on another tab, closes it.
// The overlay shows player.html in a frame; the frame follows the clock of the place under it.

(() => {
  const { el, chrome, params } = K;
  const root = document.documentElement;
  const motion = () =>
    matchMedia("(prefers-reduced-motion: reduce)").matches
      ? 0
      : parseFloat(getComputedStyle(root).getPropertyValue("--motion-transition-rise-duration")) || 400;
  let sheet = null;
  let frame = null;

  function build() {
    if (sheet) return;
    frame = el("iframe", { title: "Player", src: K.href("player.html", { embed: "player" }) });
    const grab = el("div", { class: "grab", role: "button", "aria-label": "Close the player" });
    sheet = el("div", { class: "player-overlay", role: "dialog", "aria-label": "Player" }, frame, grab);
    sheet.style.setProperty("--overlay-offset", "100%");
    frame.addEventListener("load", () => {
      const pill = root.style.getPropertyValue("--pill-space");
      if (pill) frame.contentDocument.documentElement.style.setProperty("--pill-space", pill);
    });
    dragging(grab);
    document.body.append(sheet);
    root.classList.add("player-open");
    K.setPlayerOpen(true);
  }

  // The sheet follows the finger down. A pull of 120 points or a fast flick closes it; less returns it.
  function dragging(grab) {
    let start = null;
    grab.addEventListener("pointerdown", (e) => {
      grab.setPointerCapture(e.pointerId);
      start = { y: e.clientY, at: e.timeStamp, dy: 0 };
      sheet.classList.add("dragging");
    });
    grab.addEventListener("pointermove", (e) => {
      if (!start) return;
      start.dy = Math.max(0, e.clientY - start.y);
      sheet.style.setProperty("--overlay-offset", start.dy + "px");
    });
    const end = (e) => {
      if (!start) return;
      const { dy, at } = start;
      start = null;
      sheet.classList.remove("dragging");
      const fast = dy > 40 && dy / Math.max(1, e.timeStamp - at) > 0.6;
      if (dy < 6) close();
      else if (dy > 120 || fast) close();
      else sheet.style.setProperty("--overlay-offset", "0px");
    };
    grab.addEventListener("pointerup", end);
    grab.addEventListener("pointercancel", end);
  }

  function open() {
    if (!K.current() || sheet) return;
    build();
    // One frame at the bottom edge, then the slide.
    requestAnimationFrame(() => requestAnimationFrame(() => sheet.style.setProperty("--overlay-offset", "0px")));
  }

  function close(then) {
    if (!sheet) return then?.();
    const gone = sheet;
    gone.style.setProperty("--overlay-offset", "100%");
    setTimeout(() => {
      gone.remove();
      sheet = null;
      frame = null;
      root.classList.remove("player-open");
      K.setPlayerOpen(false);
      then?.();
    }, motion() + 30);
  }

  // The states for review: the sheet stands where a finger would hold it. The clock still runs.
  function pose(state) {
    build();
    sheet.classList.add("still");
    sheet.style.setProperty("--overlay-offset", { open: "0px", opening: "46%", closing: "24%" }[state]);
  }

  // The states for review open with the page, once the tab bar and the timeline stand.
  function init() {
    const state = params.get("overlay");
    if (K.current() && ["open", "opening", "closing"].includes(state)) pose(state);
  }

  chrome.overlay = { open, close, init, isOpen: () => Boolean(sheet) };
})();
