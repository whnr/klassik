// Search and list pages use the same fixed field, Filters button and reset pill.
window.FindRow = (() => {
  const { el, ICON } = K;
  const FUNNEL =
    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M4 7h16M7 12h10M10 17h4"/></svg>';
  function make({ query = "", placeholder = "Find", onClear, onFilters, onReset }) {
    const input = el("input", {
      type: "search",
      enterkeyhint: "search",
      autocomplete: "off",
      autocorrect: "off",
      spellcheck: "false",
      placeholder,
      "aria-label": placeholder,
      value: query,
    });
    const clear = el(
      "button",
      {
        class: "clear t-body",
        "aria-label": "Clear",
        onclick: () => {
          input.value = "";
          onClear();
          input.focus();
        },
      },
      "✕",
    );
    const badge = el("span", { class: "badge" });
    const filtersBtn = el(
      "button",
      {
        class: "roundglass",
        "aria-label": "Filters",
        html: FUNNEL,
        onpointerdown: (e) => e.preventDefault(),
        onclick: () => {
          input.blur();
          onFilters();
        },
      },
      badge,
    );
    // The reset pill keeps its place, so clearing conditions never changes the field width.
    const resetBtn = el("button", {
      class: "roundglass reset",
      "aria-label": "Clear search and filters",
      html: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><path d="M7 7l10 10M17 7 7 17"/></svg>',
      onpointerdown: (e) => e.preventDefault(),
      onclick: () => {
        input.value = "";
        onReset();
      },
    });
    const field = el("label", { class: "field" }, el("span", { html: ICON.search }), input, clear);
    const fieldrow = el("div", { class: "fieldrow" }, field, filtersBtn, resetBtn);
    document.body.append(fieldrow);
    return { input, clear, badge, filtersBtn, resetBtn, fieldrow };
  }
  return { make, FUNNEL };
})();
