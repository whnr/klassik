if (K.params.get("state") === "accessibility" && !K.params.has("size")) K.params.set("size", "AX3");

K.start(async () => {
  const { el, ICON, M } = K;
  const de = K.params.get("lang") === "de";
  const locale = de ? "de" : "en";
  const dictionary = {
    Composers: "Komponisten",
    Library: "Mediathek",
    Chronology: "Chronologie",
    Search: "Suche",
    Filters: "Filter",
    Filter: "Filter",
    Sort: "Sortierung",
    Form: "Darstellung",
    Done: "Fertig",
    Back: "Zurück",
    "A to Z": "A bis Z",
    "Best known": "Am bekanntesten",
    "Last heard": "Zuletzt gehört",
    "Not heard": "Noch nicht gehört",
    "Rich list": "Liste mit Bildern",
    "Show all": "Alle anzeigen",
    "Find by name": "Name suchen",
    Find: "Suchen",
    Clear: "Löschen",
    None: "Keine",
    Genres: "Genres",
    Conductors: "Dirigenten",
    Performers: "Interpreten",
    Conditions: "Bedingungen",
    and: "und",
    or: "oder",
    "+ or": "+ oder",
    remove: "entfernen",
    "Add an or term": "Oder-Begriff hinzufügen",
    "No term of this kind is left.": "Keine weiteren Begriffe dieser Art.",
    Favourite: "Favorit",
    "Not a favourite": "Kein Favorit",
    "No composers yet": "Noch keine Komponisten",
    "Composers in your library appear here.": "Hier erscheinen die Komponisten deiner Mediathek.",
    "No matches": "Keine Ergebnisse",
    "Change the name or filters.": "Ändere den Namen oder die Filter.",
  };
  const text = (value) => {
    if (value.startsWith("Find in ")) return de ? "Suchen" : "Find";
    return de ? dictionary[value] || value : value;
  };
  const number = (value) => value.toLocaleString(locale);
  const count = (n, one, many) => `${number(n)} ${de ? (n === 1 ? one[1] : many[1]) : n === 1 ? one[0] : many[0]}`;
  const worksCount = (n) => count(n, ["work", "Werk"], ["works", "Werke"]);
  const resultsCount = (n) => count(n, ["composer", "Komponist"], ["composers", "Komponisten"]);
  const sample = await fetch("data/library.json").then((r) => r.json());
  const state = K.params.get("state") || "default";
  document.documentElement.lang = locale;
  document.title = text("Composers");
  document.body.classList.add("list-page");
  const { scroll } = K.page({
    title: text("Composers"),
    back: { label: text("Library"), href: "library.html" },
  });
  document.querySelectorAll(".tabs a").forEach((tab) => {
    const label = tab.querySelector("span");
    tab.setAttribute("aria-label", text(label.textContent));
    label.textContent = text(label.textContent);
  });
  const people = [...new Set([...M.works.values()].map((w) => w.composer))].map((name) => {
    const works = [...M.works.values()].filter((w) => w.composer === name);
    const recordings = works.flatMap((w) => w.recordings);
    const heard = recordings
      .map((r) => sample.heard[r.id])
      .filter(Boolean)
      .sort()
      .at(-1);
    return { name, works, recordings, heard, facts: M.people[name] || {} };
  });
  const pool = state === "empty" ? [] : people;
  const example = [["genre:Piano"]];
  const long = [[...Filters.index().allTerms.keys()].filter((t) => t.startsWith("composer:")).slice(0, 6)];
  let query = state === "no-match" ? "zzzz" : state === "keyboard" ? "bach" : "";
  let sort = "az";
  let frame = null;
  let level = "settings";
  let handle = null;
  const folds = new Set();
  const fx = Filters.make({
    conds: state === "filtered" ? example : state === "long" ? long : [],
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
    return fx.conds.map((c) => c.map(Filters.label).join(` ${text("or")} `)).join(` ${text("and")} `);
  }
  const input = el("input", {
    type: "search",
    placeholder: text("Find"),
    "aria-label": text("Find by name"),
    autocomplete: "off",
    enterkeyhint: "search",
    value: query,
    oninput: () => {
      query = input.value;
      update();
    },
    onkeydown: (event) => {
      if (event.key === "Enter") input.blur();
    },
  });
  const clear = el(
    "button",
    {
      class: "find-clear",
      "aria-label": text("Clear"),
      onclick: () => {
        query = "";
        input.value = "";
        update();
        input.focus();
      },
    },
    "×",
  );
  const filters = el("button", {
    class: "filter-button",
    "aria-label": text("Filters"),
    "aria-haspopup": "dialog",
    html: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><path d="M4 7h16M7 12h10M10 17h4"/></svg>',
    onclick: openSheet,
  });
  const fieldrow = el(
    "div",
    { class: "fieldrow" },
    el("label", { class: "find t-body" }, el("span", { html: ICON.search, "aria-hidden": "true" }), input, clear),
    filters,
  );
  document.body.append(fieldrow);
  const summary = el("button", { class: "conditions t-footnote", onclick: () => openSheet("filter") });
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
    el("div", { class: "page-head" }, el("h1", { class: "t-largeTitle" }, text("Composers")), summary, showAll),
    results,
  );

  function row(p) {
    const favourite = sample.favourites.includes(`composer:${p.name}`);
    const years = [p.facts.born, p.facts.died].filter(Boolean).join("–");
    const facts = [years, worksCount(p.works.length)].filter(Boolean).join(", ");
    const picture = p.facts.picture?.url;
    return el(
      "a",
      {
        class: "row",
        href: K.personHref(p.name, { back: text("Composers") }),
        "aria-label": `${p.name}, ${text(favourite ? "Favourite" : "Not a favourite")}, ${facts}`,
      },
      el(
        "span",
        { "aria-hidden": "true" },
        picture
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
        el("div", { class: "t-body" }, p.name, favourite ? K.fermata(true, true) : null),
        el("div", { class: "t-subheadline secondary" }, facts),
      ),
      el("span", { html: ICON.chevron, "aria-hidden": "true" }),
    );
  }
  function section(title, members) {
    const key = `${sort}:${title}`;
    const list = el("div", { class: "list", hidden: folds.has(key) }, ...members.map(row));
    const head = el(
      "button",
      {
        class: "section-head",
        "aria-expanded": String(!folds.has(key)),
        "aria-label": `${title}, ${resultsCount(members.length)}`,
        onclick: () => {
          if (folds.has(key)) folds.delete(key);
          else folds.add(key);
          list.hidden = folds.has(key);
          head.setAttribute("aria-expanded", String(!list.hidden));
        },
      },
      el("span", {}, title),
      el("span", { class: "count" }, `(${number(members.length)})`),
    );
    return el("section", { class: "section" }, head, list);
  }
  function renderResults() {
    const shown = filtered().sort((a, b) =>
      sort === "best"
        ? (sample.known[b.name] ?? -1) - (sample.known[a.name] ?? -1) || a.name.localeCompare(b.name, locale)
        : sort === "heard"
          ? (b.heard || "").localeCompare(a.heard || "") || a.name.localeCompare(b.name, locale)
          : K.surname(a.name).localeCompare(K.surname(b.name), locale),
    );
    const groups = new Map();
    for (const p of shown) {
      const key =
        sort === "best"
          ? text("Composers")
          : sort === "heard"
            ? p.heard
              ? new Date(p.heard + "T12:00:00Z").toLocaleDateString(locale, {
                  month: "long",
                  year: "numeric",
                  timeZone: "UTC",
                })
              : text("Not heard")
            : K.surname(p.name)[0].toLocaleUpperCase(locale);
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
  function setting(label, value, go) {
    return el(
      "button",
      { class: "row list-setting t-body", onclick: go },
      el("span", { class: "main" }, text(label)),
      el("span", { class: "trail" }, text(value), el("span", { html: ICON.chevron })),
    );
  }
  function setLevel(next) {
    level = next;
    drawSheet();
  }
  function drawSheet() {
    if (!frame) return;
    let body;
    if (level === "filter") body = fx.body();
    else if (level === "sort" || level === "form") {
      const options = level === "sort" ? sorts : { rich: "Rich list" };
      body = K.form.group(
        null,
        Object.entries(options).map(([value, label]) =>
          el(
            "button",
            {
              class: "row t-body",
              "aria-pressed": String(level === "form" || sort === value),
              onclick: () => {
                if (level === "sort") sort = value;
                setLevel("settings");
                update();
              },
            },
            el("span", { class: "main" }, text(label)),
            el("span", { html: level === "form" || sort === value ? ICON.check : "" }),
          ),
        ),
      );
    } else
      body = K.form.group(null, [
        setting("Filter", fx.conds.length ? conditionsLine() : "None", () => setLevel("filter")),
        setting("Sort", sorts[sort], () => setLevel("sort")),
        setting("Form", "Rich list", () => setLevel("form")),
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
    level = typeof next === "string" ? next : "settings";
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
    clear.hidden = !query;
    summary.textContent = conditionsLine();
    summary.hidden = !fx.conds.length;
    showAll.hidden = !fx.conds.length;
    filters.classList.toggle("on", !!fx.conds.length || !!handle);
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
          lang: locale,
          size: select.value === "accessibility" ? "AX3" : K.params.get("size"),
        });
      },
    },
    ...states.map((value) => el("option", { value, selected: state === value }, value)),
  );
  bar?.append(select, el("a", { href: K.href("list.html", { lang: de ? "en" : "de", state }) }, de ? "EN" : "DE"));
  update();
  resize();
  if (K.params.has("sheet")) openSheet(K.params.get("sheet"));
  if (state === "keyboard") input.focus();
});
