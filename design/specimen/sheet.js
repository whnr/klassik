// The shared sheet frame. A sheet built on it has one header line, one footnote line and one scroll area.
// Frame.make({ title, count, onBack, onDone, body }) returns { box, scroll, set }.
// A back chevron shows only when onBack is set, which is one level deeper. Changes apply live; Done closes.
window.Frame = (() => {
  const { el, ICON } = K;

  function make({ title, count = null, onBack = null, onDone = null, body = [] }) {
    const box = el("div", { class: "hsheet", role: "dialog", "aria-label": title });
    const scroll = el("div", { class: "hs-scroll" });
    const draw = (state) => {
      box.setAttribute("aria-label", state.title);
      box.replaceChildren(
        el("div", { class: "hs-grab" }),
        el(
          "div",
          { class: "hs-head" },
          state.onBack
            ? el("button", { class: "hs-back", "aria-label": "Back", onclick: state.onBack, html: ICON.back })
            : el("span"),
          el("h2", { class: "hs-title t-headline" }, state.title),
          el("button", { class: "hs-done t-body", onclick: state.onDone }, "Done"),
        ),
        state.count ? el("div", { class: "hs-count t-footnote" }, state.count) : null,
        scroll,
      );
    };
    const state = { title, count, onBack, onDone };
    scroll.append(...[].concat(body));
    draw(state);
    // The scroll area stays the same element, so a level change keeps no second scroller.
    const set = (next) => {
      Object.assign(state, next);
      draw(state);
    };
    return { box, scroll, set };
  }

  // The frame opens over the live page and closes with a slide.
  function open(frame) {
    document.body.append(frame.box);
    requestAnimationFrame(() => frame.box.classList.add("on"));
    return () => {
      frame.box.classList.remove("on");
      setTimeout(() => frame.box.remove(), 400);
    };
  }

  return { make, open };
})();
