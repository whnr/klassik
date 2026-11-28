// Library rows and list pages share setting lines and checked choices.
window.SheetSettings = (() => {
  const { el, ICON } = K;
  const trail = (text, chevron) =>
    el(
      "span",
      { class: "trail le-trail t-body" },
      el("span", {}, text),
      chevron ? el("span", { html: ICON.chevron }) : null,
    );
  const line = (label, value, go, only = false) =>
    el(
      "button",
      { class: "row t-body", type: "button", disabled: only, onclick: go },
      el("span", { class: "main" }, label),
      trail(value, !only),
    );
  const filter = (conds, go) => {
    const terms = conds.flat();
    return line(
      "Filter",
      terms.length === 0 ? "None" : terms.length === 1 ? Filters.label(terms[0]) : terms.length + " terms",
      go,
    );
  };
  const choices = (options, selected, choose) =>
    K.form.group(
      null,
      Object.entries(options).map(([value, text]) =>
        el(
          "button",
          { class: "row t-body", type: "button", onclick: () => choose(value) },
          el("span", { class: "le-check", html: selected === value ? ICON.check : "" }),
          el("span", { class: "main" }, text),
        ),
      ),
    );
  return { trail, line, filter, choices };
})();
