if (K.params.get("state") === "accessibility" && !K.params.has("size")) K.params.set("size", "AX3");

K.start(async () => {
  const { el, ICON, M } = K;
  const locale = "en";
  const text = (value) => value;
  const number = (value) => value.toLocaleString(locale);
  const resultsCount = (n) =>
    K.count(n, pageKind === "composers" ? "composer" : pageKind === "performers" ? "performer" : "result");
  await Library.load();
  const pageKind = K.params.get("kind") || "composers";
  const pageTitle = Library.LINKS[pageKind] || (pageKind === "recordings" ? "Recordings" : "Composers");
  const sample = await fetch("data/library.json").then((r) => r.json());
  const state = K.params.get("state") || "default";
  document.documentElement.lang = locale;
  document.title = pageTitle;
  document.body.classList.add("list-page");
  const { scroll } = K.page({
    title: pageTitle,
    back: { label: text("Library"), href: "library.html" },
  });
  document.querySelectorAll(".tabs a").forEach((tab) => {
    const label = tab.querySelector("span");
    tab.setAttribute("aria-label", text(label.textContent));
    label.textContent = text(label.textContent);
  });
  const people = Library.frameItems(pageKind).map((x) => ({
    ...x,
    recordings: x.recs,
    facts: M.people[x.name] || {},
    sortName: sample.sortNames?.[x.name] || [...M.artists.values()].find((a) => a.name === x.name)?.sortName || x.name,
  }));
  const pool = state === "empty" ? [] : people;
  const example = [["genre:Piano"]];
  const long = [[...Filters.index().allTerms.keys()].filter((t) => t.startsWith("composer:")).slice(0, 6)];
  let query = state === "no-match" ? "zzzz" : state === "keyboard" ? "bach" : "";
  let sort = K.params.get("sort") || "az";
  let frame = null;
  let level = "settings";
  let handle = null;
  const folds = new Set();
  const fx = Filters.make({
    conds: K.params.has("conds")
      ? JSON.parse(K.params.get("conds"))
      : state === "filtered"
        ? example
        : state === "long"
          ? long
          : [],
    kind: "genre",
    count: (conds) => filtered(conds).length,
    text,
    formatNumber: number,
    onChange: update,
  });
  function filtered(conds = fx.conds) {
    return pool.filter(
      (p) => Filters.matches(Filters.queryTokens(query), Filters.words(p.name)) && Filters.hit(p.recordings, conds),
    );
  }
  function conditionsLine() {
    return (
      "Filter: " +
      fx.conds
        .map((c) =>
          c
            .map(
              (t, i) =>
                (i === 0 || Filters.kindOf(t) !== Filters.kindOf(c[i - 1])
                  ? Filters.ONE[Filters.kindOf(t)] + " is "
                  : "") + Filters.label(t),
            )
            .join(" or "),
        )
        .join(", and ")
    );
  }
  const {
    input,
    clear,
    badge,
    filtersBtn: filters,
    resetBtn,
    fieldrow,
  } = FindRow.make({
    query,
    placeholder: "Find by name",
    onClear: () => {
      query = "";
      update();
    },
    onFilters: openSheet,
    onReset: () => {
      query = "";
      fx.conds = [];
      fx.marked = null;
      update();
    },
  });
  input.addEventListener("input", () => {
    query = input.value;
    update();
  });
  input.addEventListener("keydown", (event) => {
    if (event.key === "Enter") input.blur();
  });

  const summary = el("button", { class: "conditions t-body", onclick: () => openSheet("filter") });
  const showAll = el(
    "button",
    {
      class: "show-all t-body",
      onclick: () => {
        fx.conds = [];
        fx.marked = null;
        update();
      },
    },
    text("Show all"),
  );
  const results = el("div");
  scroll.append(
    el("div", { class: "page-head" }, el("h1", { class: "t-largeTitle" }, pageTitle), summary, showAll),
    results,
  );

  function row(p) {
    const favourite = p.fav;
    const years = [p.facts.born, p.facts.died].filter(Boolean).join("–");
    const facts = [years, p.fact].filter(Boolean).join(", ");
    const picture = p.facts.picture?.url;
    return el(
      "a",
      {
        class: "row",
        href: p.href,
        "aria-label": `${p.name}, ${text(favourite ? "Favourite" : "Not a favourite")}, ${facts}`,
      },
      el(
        "span",
        { "aria-hidden": "true" },
        p.album
          ? K.coverImage(p.album, "face", 250)
          : picture
            ? el("img", { class: "face", src: picture, alt: "" })
            : el(
                "span",
                { class: "face t-footnote" },
                p.name
                  .split(" ")
                  .map((w) => w[0])
                  .slice(0, 2)
                  .join(""),
              ),
      ),
      el(
        "div",
        { class: "main", "aria-hidden": "true" },
        el("div", { class: "t-body" }, favourite ? K.titled(p.name, K.fermata(true, true)) : p.name),
        el("div", { class: "t-subheadline secondary" }, facts),
      ),
      el("span", { html: ICON.chevron, "aria-hidden": "true" }),
    );
  }
  function section(title, members) {
    const key = `${sort}:${title}`;
    return K.resultSection(title, number(members.length), members.map(row), null, {
      folded: folds.has(key),
      onFold: (folded) => {
        if (folded) folds.add(key);
        else folds.delete(key);
      },
    });
  }

  function renderResults() {
    const shown = filtered().sort((a, b) =>
      sort === "best"
        ? (sample.known[b.name] ?? -1) - (sample.known[a.name] ?? -1) || a.sortName.localeCompare(b.sortName, locale)
        : sort === "heard"
          ? (b.heard || 0) - (a.heard || 0) || a.sortName.localeCompare(b.sortName, locale)
          : a.sortName.localeCompare(b.sortName, locale),
    );
    const groups = new Map();
    for (const p of shown) {
      const key =
        sort === "best"
          ? pageTitle
          : sort === "heard"
            ? p.heard
              ? new Date(p.heard).toLocaleDateString(locale, {
                  month: "long",
                  year: "numeric",
                  timeZone: "UTC",
                })
              : text("Not heard")
            : pageTitle;
      if (!groups.has(key)) groups.set(key, []);
      groups.get(key).push(p);
    }
    results.replaceChildren(...[...groups].map(([title, members]) => section(title, members)));
    if (!shown.length)
      results.append(
        el(
          "div",
          { class: "empty" },
          el("p", { class: "t-headline" }, text(pool.length ? "No matches" : "No composers yet")),
          el(
            "p",
            { class: "t-body secondary" },
            text(pool.length ? "Change the name or filters." : "Composers in your library appear here."),
          ),
        ),
      );
    return shown.length;
  }
  const sorts = { az: "A to Z", best: "Best known", heard: "Last heard" };
  function setLevel(next) {
    level = next === "form" ? "settings" : next;
    drawSheet();
  }
  function drawSheet() {
    if (!frame) return;
    let body;
    if (level === "filter") body = fx.body();
    else if (level === "sort") {
      body = SheetSettings.choices(sorts, sort, (value) => {
        sort = value;
        setLevel("settings");
        update();
      });
    } else
      body = K.form.group(null, [
        SheetSettings.filter(fx.conds, () => setLevel("filter")),
        SheetSettings.line("Sort", sorts[sort], () => setLevel("sort")),
      ]);
    frame.set({
      title: text({ settings: "Filters", filter: "Filter", sort: "Sort", form: "Form" }[level]),
      onBack: level === "settings" ? null : () => setLevel("settings"),
      body,
      count: resultsCount(filtered().length),
    });
    if (level === "filter") fx.draw();
    resize();
  }
  function openSheet(next = "settings") {
    input.blur();
    if (handle) {
      setLevel(typeof next === "string" ? next : "settings");
      return;
    }
    frame = Frame.make({ title: text("Filters"), doneLabel: text("Done"), backLabel: text("Back") });
    frame.box.classList.add("settings-sheet");
    level = typeof next === "string" && next !== "form" ? next : "settings";
    drawSheet();
    handle = Frame.open(frame, {
      onClose: () => {
        handle = null;
        frame = null;
        update();
      },
    });
    update();
  }
  function update() {
    clear.style.visibility = query ? "visible" : "hidden";
    resetBtn.disabled = !query && !fx.conds.length;
    badge.textContent = String(fx.conds.length);
    badge.style.display = fx.conds.length && !handle ? "" : "none";
    summary.textContent = conditionsLine();
    summary.hidden = !fx.conds.length;
    showAll.hidden = !fx.conds.length;
    filters.classList.toggle("on", !!handle);
    filters.setAttribute("aria-label", `${text("Filters")}${fx.conds.length ? ` (${number(fx.conds.length)})` : ""}`);
    const n = renderResults();
    if (frame) {
      frame.set({ count: resultsCount(n) });
      if (level === "filter") fx.draw();
      else drawSheet();
    }
  }
  function resize() {
    document.body.style.setProperty("--list-top", fieldrow.getBoundingClientRect().bottom + "px");
    const vv = window.visualViewport;
    const kb = vv ? Math.max(0, innerHeight - vv.height - vv.offsetTop) : 0;
    document.body.style.setProperty("--list-keyboard", kb + "px");
    if (frame) {
      const up = kb > 40 && frame.box.contains(document.activeElement);
      frame.box.style.bottom = up ? kb + "px" : "";
      frame.box.style.height = up ? Math.min(vv.height - 70, innerHeight * 0.5) + "px" : "";
    }
    if (window.scrollY) window.scrollTo(0, 0);
    K.layoutChrome();
  }
  new ResizeObserver(resize).observe(fieldrow);
  window.visualViewport?.addEventListener("resize", resize);
  window.visualViewport?.addEventListener("scroll", resize);
  document.addEventListener("focusin", resize);
  document.addEventListener("focusout", resize);
  const bar = document.querySelector(".specimen-bar");
  const states = ["default", "filtered", "empty", "no-match", "keyboard", "long", "accessibility"];
  const select = el(
    "select",
    {
      "aria-label": "Review state",
      onchange: () => {
        location.href = K.href("list.html", {
          state: select.value,
          kind: pageKind,
          size: select.value === "accessibility" ? "AX3" : K.params.get("size"),
        });
      },
    },
    ...states.map((value) => el("option", { value, selected: state === value }, value)),
  );
  bar?.append(select);
  update();
  resize();
  if (K.params.has("sheet")) openSheet(K.params.get("sheet"));
  if (state === "keyboard") input.focus();
});
