// The shared sheet frame. A sheet built on it has one header line, one footnote line and one scroll area.
// Frame.make({ title, count, onBack, onDone, body }) returns { box, scroll, set, close }.
// A back chevron shows only when onBack is set, which is one level deeper. Changes apply live; Done closes.
// set({ title, count, onBack, onDone, body }) updates only the keys that it gets. A new body replaces the
// scroll children and scrolls to the top. The header parts stay in place, so focus on Done or back survives.
window.Frame = (() => {
  const { el, ICON } = K;

  function make({ title, count = null, onBack = null, onDone = null, body = [] }) {
    const state = { title, count, onBack, onDone };
    const frame = { close: () => {} };
    const back = el("button", {
      class: "hs-back",
      "aria-label": "Back",
      html: ICON.back,
      onclick: () => state.onBack?.(),
    });
    const heading = el("h2", { class: "hs-title t-headline" });
    const done = el(
      "button",
      {
        class: "hs-done t-body",
        onclick: () => {
          state.onDone?.();
          frame.close();
        },
      },
      "Done",
    );
    const counter = el("div", { class: "hs-count t-footnote" });
    const scroll = el("div", { class: "hs-scroll" });
    const box = el(
      "div",
      { class: "hsheet", role: "dialog", tabindex: "-1" },
      el("div", { class: "hs-grab" }),
      el("div", { class: "hs-head" }, back, heading, done),
      counter,
      scroll,
    );
    const items = (value) => [].concat(value).filter((item) => item != null && item !== false);

    const paint = () => {
      box.setAttribute("aria-label", state.title);
      heading.textContent = state.title;
      counter.textContent = state.count ?? "";
      const hide = !state.onBack;
      if (hide && document.activeElement === back) done.focus();
      back.hidden = hide;
    };
    const set = (next) => {
      for (const key of ["title", "count", "onBack", "onDone"]) if (key in next) state[key] = next[key];
      paint();
      if ("body" in next) {
        scroll.replaceChildren(...items(next.body));
        scroll.scrollTop = 0;
      }
    };
    scroll.append(...items(body));
    paint();
    return Object.assign(frame, { box, scroll, set });
  }

  // The frame opens over the live page and closes with a slide. It has no aria-modal and no scrim by design:
  // the tab behind it stays visible and tappable while the person edits.
  // onClose runs once when the sheet starts to close, however it closes: Done, Escape or close().
  function open(frame, { onClose = null } = {}) {
    const before = document.activeElement;
    const { box } = frame;
    let closing = false;
    const onKey = (event) => {
      if (event.key === "Escape") close();
    };
    const close = () => {
      if (closing) return;
      closing = true;
      onClose?.();
      document.removeEventListener("keydown", onKey);
      box.classList.remove("on");
      const finish = () => {
        box.remove();
        before?.focus?.({ preventScroll: true });
      };
      const motion = parseFloat(getComputedStyle(box).transitionDuration) || 0;
      if (motion === 0) finish();
      else
        box.addEventListener("transitionend", function end(event) {
          if (event.target !== box) return;
          box.removeEventListener("transitionend", end);
          finish();
        });
    };
    frame.close = close;
    document.addEventListener("keydown", onKey);
    document.body.append(box);
    box.focus({ preventScroll: true });
    requestAnimationFrame(() => requestAnimationFrame(() => box.classList.add("on")));
    return { close };
  }

  // The height of the frame in px, read from its own box, so a page can leave room for it.
  function height() {
    const probe = el("div", { class: "hsheet", style: "visibility:hidden;pointer-events:none" });
    document.body.append(probe);
    const px = probe.getBoundingClientRect().height;
    probe.remove();
    return px;
  }

  return { make, open, height };
})();
