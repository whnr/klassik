// The Library tab as a list of row configs: {id, kind, source, filter, sort, form, count}.
// Library.mount draws the list into a host and redraws it when the list changes, so the edit sheet can edit it live.
// An empty row hides on the tab. The pages behind a row title and a link tile are not in the specimen.

(() => {
  const { el, M } = K;
  const NB = K.NB;

  const KINDS = {
    pick: { label: "Daily pick" },
    composers: { label: "Composers", unit: "composers" },
    performers: { label: "Performers", unit: "performers" },
    works: { label: "Works", unit: "works" },
    recordings: { label: "Recordings", unit: "recordings" },
    albums: { label: "Albums", unit: "albums" },
    favourites: { label: "Favourites", unit: "mixed" },
    added: { label: "Recently added", unit: "albums" },
    heard: { label: "Recently heard", unit: "recordings" },
    saved: { label: "Saved search", unit: "recordings" },
    links: { label: "Link list" },
  };
  // A row of one of these kinds takes its kind from Source. The other kinds have a fixed source.
  const UNIT_KINDS = ["composers", "performers", "works", "recordings", "albums"];
  const PEOPLE = ["composers", "performers"];
  const SOURCE_NAME = { favourites: "Favourites", added: "Albums", heard: "Recordings" };
  // What each kind starts with. Strips hold 6, 9 or 12 cards, tiles 3, 6 or 9.
  const START = {
    pick: { sort: "random" },
    composers: { sort: "random" },
    performers: { sort: "random" },
    works: { sort: "random" },
    recordings: { sort: "random" },
    albums: { sort: "newest" },
    favourites: { filter: "favourites", sort: "random" },
    added: { sort: "newest" },
    heard: { sort: "heard" },
    saved: { source: "Baroque", sort: "random" },
    links: {},
  };
  // Lower case, for titles and subtitles. Code never changes letter case, so the settings list has its own labels.
  const SORTS = {
    random: "random",
    best: "best known",
    newest: "newest first",
    heard: "last heard first",
    az: "A to Z",
  };
  const SORT_LABELS = {
    random: "Random",
    best: "Best known",
    newest: "Newest first",
    heard: "Last heard first",
    az: "A to Z",
  };
  // Best known shows for people only. People without data sort last and the score never shows.
  const SORT_KINDS = {
    composers: ["random", "best", "az", "heard"],
    performers: ["random", "best", "az", "heard"],
    works: ["random", "az", "newest", "heard"],
    recordings: ["random", "az", "newest", "heard"],
    albums: ["newest", "random", "az", "heard"],
    favourites: ["random", "az", "newest"],
    added: ["newest", "random", "az"],
    heard: ["heard", "random", "az"],
    saved: ["random", "az", "newest", "heard"],
  };
  const COUNTS = { strip: [6, 9, 12], tiles: [3, 6, 9] };
  const FILTERS = { favourites: "favourites" };
  const LINKS = {
    composers: "Composers",
    performers: "Performers",
    works: "Works",
    albums: "Albums",
    genres: "Genres",
    roles: "Roles",
    playlists: "Playlists",
    favourites: "Favourites",
  };
  const DEFAULT_LINKS = ["performers", "works", "albums", "genres", "roles", "playlists"];
  // The order of all links of a link list, the checked ones first, as the edit sheet shows them.
  const linkOrder = (checked) => [...checked, ...Object.keys(LINKS).filter((k) => !checked.includes(k))];
  // Saved searches of the sample library: a name and the recordings that match it.
  const SAVED = {
    Baroque: (r) => (M.people[r.composer]?.born || 9999) < 1750,
    Symphonies: (r) => /symphon/i.test(r.work || ""),
  };

  let sample = { favourites: [], added: {}, heard: {}, known: {}, playlists: 0 };
  let data = null;

  const load = async () => {
    sample = await fetch("data/library.json").then((r) => r.json());
  };

  const make = (kind, extra = {}) => ({
    id: `${kind}-${Math.random().toString(36).slice(2, 7)}`,
    kind,
    source: "library",
    filter: "all",
    sort: "random",
    form: "strip",
    count: 9,
    conds: [],
    ...(kind === "links" ? { links: [...DEFAULT_LINKS], order: linkOrder(DEFAULT_LINKS) } : {}),
    ...START[kind],
    ...extra,
  });
  const defaults = () =>
    ["pick", "composers", "favourites", "links", "added", "heard"].map((kind) => make(kind, { id: `d-${kind}` }));

  // ?rows=composers,albums, or ?rows=all for every kind.
  function fromParam(text) {
    if (!text) return defaults();
    const kinds = text === "all" ? Object.keys(KINDS) : text.split(",").filter((k) => KINDS[k]);
    return kinds.map((kind) => make(kind, { id: `p-${kind}` }));
  }

  // ---------- Titles ----------
  // A natural title when the row has no qualifier, else "Kind, qualifier".
  function title(row) {
    const base = KINDS[row.kind].label;
    if (row.kind === "pick" || row.kind === "links") return base;
    const qualifiers = [];
    if (row.kind === "saved") qualifiers.push(row.source);
    if (FILTERS[row.filter] && row.kind !== "favourites") qualifiers.push(FILTERS[row.filter]);
    // One term names itself. Two or more terms make the row "filtered".
    const terms = row.conds?.flat() ?? [];
    if (terms.length) qualifiers.push(terms.length === 1 ? Filters.label(terms[0]) : "filtered");
    if (row.sort !== START[row.kind].sort) qualifiers.push(SORTS[row.sort]);
    return qualifiers.length ? `${base}, ${qualifiers.join(", ")}` : base;
  }

  // ---------- The sample library as items ----------
  const today = () => new Date().toISOString().slice(0, 10);
  const day = (s) => (s ? Date.parse(s) : 0);
  const hash = (s) => [...s].reduce((h, c) => (h * 31 + c.charCodeAt(0)) % 2147483647, 7) || 7;
  // The same seed gives the same order all day.
  function shuffle(list, seed) {
    let s = hash(seed);
    const next = () => {
      s = (s * 16807) % 2147483647;
      return s / 2147483647;
    };
    return list
      .map((x) => [next(), x])
      .sort((a, b) => a[0] - b[0])
      .map((p) => p[1]);
  }

  const albumComplete = (album) => {
    const discs = new Map();
    for (const s of album.song)
      (discs.get(s.discNumber) || discs.set(s.discNumber, []).get(s.discNumber)).push(s.track);
    return [...discs.values()].every((t) => t.sort((a, b) => a - b).every((n, i) => n === i + 1));
  };
  const lead = (r) => r.performers[0]?.name || r.album.displayArtist || r.album.artist || "Various artists";
  const sized = (url, width) => url.replace(/\/\d+px-/, `/${width}px-`).split("?")[0];
  const fav = (key) => K.isFavourite(key) || sample.favourites.includes(key);
  const plural = (n, one, many) => `${n} ${n === 1 ? one : many}`;

  function build() {
    const addedOf = (album) => day(sample.added[album.id]);
    const albums = [...M.albums.values()].map((a) => ({
      type: "album",
      id: a.id,
      name: a.name,
      fact: lead(a.recordings[0]),
      href: K.href("player.html", { album: a.id, back: "Library" }),
      album: a,
      fav: fav("album:" + a.id),
      added: addedOf(a),
      heard: Math.max(0, ...a.recordings.map((r) => day(sample.heard[r.id]))),
      complete: albumComplete(a),
      recs: a.recordings,
    }));
    const recordings = [...M.recordings.values()].map((r) => ({
      type: "recording",
      id: r.id,
      name: r.work || r.album.name,
      fact: lead(r),
      href: K.href("player.html", { recording: r.id, back: "Library" }),
      album: r.album,
      rec: r,
      fav: fav("rec:" + r.id),
      added: addedOf(r.album),
      heard: day(sample.heard[r.id]),
      complete: !K.partOf(r),
      recs: [r],
    }));
    const works = [...M.works.values()].map((w) => ({
      type: "work",
      id: w.id,
      name: w.name,
      // A work has no cover and no lead performer, so its fact line is the composer.
      fact: w.composer,
      href: K.href("work.html", { work: w.id, back: "Library" }),
      album: K.referenceRecording(w).album,
      fav: fav("work:" + w.id),
      added: Math.max(...w.recordings.map((r) => addedOf(r.album))),
      heard: Math.max(0, ...w.recordings.map((r) => day(sample.heard[r.id]))),
      complete: K.recordingLists(w).recordings.length > 0,
      recs: w.recordings,
    }));
    const byPerson = new Map();
    for (const r of M.recordings.values()) {
      for (const p of r.performers) {
        if (!p.name || M.composers.has(p.name)) continue;
        if (!byPerson.has(p.name)) byPerson.set(p.name, []);
        byPerson.get(p.name).push(r);
      }
    }
    const person = (name, type, fact, recs) => ({
      type,
      id: type + ":" + name,
      name,
      fact,
      href: K.personHref(name, { back: "Library" }),
      fav: fav((type === "composer" ? "composer:" : "performer:") + name),
      added: Math.max(0, ...recs.map((r) => addedOf(r.album))),
      heard: Math.max(0, ...recs.map((r) => day(sample.heard[r.id]))),
      complete: true,
      recs,
      // Sample data. The server has no such value; the app derives it from Wikidata sitelinks and page views.
      known: sample.known[name] ?? null,
    });
    const composers = [...M.composers.values()]
      .filter((c) => M.people[c.name])
      .map((c) =>
        person(
          c.name,
          "composer",
          plural(c.works.size, "work", "works"),
          [...c.works].flatMap((w) => w.recordings),
        ),
      );
    const performers = [...byPerson]
      .filter(([name]) => M.people[name]?.kind !== "composer")
      .map(([name, recs]) => person(name, "performer", plural(recs.length, "recording", "recordings"), recs));
    const roles = new Set();
    for (const r of M.recordings.values()) for (const p of r.performers) roles.add(p.subRole || p.role);
    const genres = new Set();
    for (const r of M.recordings.values()) for (const g of r.genres) genres.add(g);
    const mixed = [
      ...composers.filter((x) => x.fav).map((x) => ({ ...x, fact: "Composer" })),
      ...albums.filter((x) => x.fav).map((x) => ({ ...x, fact: "Album" })),
      ...recordings.filter((x) => x.fav).map((x) => ({ ...x, fact: "Recording" })),
    ];
    const counts = {
      composers: composers.length,
      performers: performers.length,
      works: works.length,
      albums: albums.length,
      genres: genres.size,
      roles: roles.size,
      playlists: sample.playlists,
      favourites: mixed.length,
    };
    return { composers, performers, works, recordings, albums, mixed, counts };
  }
  const library = () => {
    data ??= build();
    return data;
  };

  // The items of a row before the count cuts them: the source, the saved search and the conditions.
  function pool(row, conds = row.conds) {
    let list = library()[KINDS[row.kind].unit];
    if (row.kind === "saved") list = list.filter((x) => SAVED[row.source]?.(x.rec));
    if (row.filter === "favourites") list = list.filter((x) => x.fav);
    if (row.sort === "heard") list = list.filter((x) => x.heard);
    if (conds?.length) list = list.filter((x) => Filters.hit(x.recs, conds));
    return list;
  }
  // The recordings that the conditions of a row may reach: those of its source before any condition.
  const scopeOf = (row) => new Set(pool(row, []).flatMap((x) => x.recs));
  const matching = (row, conds) => pool(row, conds).length;

  function items(row) {
    const list = pool(row);
    const order = {
      random: () => shuffle(list, today() + row.id),
      // People without a value sort last, and the value itself never shows.
      best: () => [...list].sort((a, b) => (b.known ?? -1) - (a.known ?? -1) || a.name.localeCompare(b.name)),
      newest: () => [...list].sort((a, b) => b.added - a.added),
      heard: () => [...list].sort((a, b) => b.heard - a.heard),
      az: () => [...list].sort((a, b) => a.name.localeCompare(b.name)),
    };
    return order[row.sort]().slice(0, row.count);
  }
  // A row with nothing to show hides on the tab.
  function empty(row) {
    if (row.kind === "pick") return !pickOf(row);
    if (row.kind === "links") return !row.links.length;
    return !pool(row).length;
  }

  // ---------- Settings: what each row kind offers ----------
  const savedNames = () => Object.fromEntries(Object.keys(SAVED).map((k) => [k, k]));
  function sourceOptions(row) {
    if (UNIT_KINDS.includes(row.kind)) return Object.fromEntries(UNIT_KINDS.map((k) => [k, KINDS[k].label]));
    if (row.kind === "saved") return savedNames();
    if (row.kind === "pick") return { library: "Whole library", ...savedNames() };
    return { [row.kind]: SOURCE_NAME[row.kind] };
  }
  const sourceValue = (row) =>
    UNIT_KINDS.includes(row.kind) ? row.kind : ["saved", "pick"].includes(row.kind) ? row.source : row.kind;
  const sortOptions = (row) => Object.fromEntries((SORT_KINDS[row.kind] || []).map((k) => [k, SORT_LABELS[k]]));
  // Faces for people, covers or tiles for the rest. Favourites mix faces and covers, so they stay a strip.
  function formOptions(row) {
    if (PEOPLE.includes(row.kind)) return { strip: "Strip of faces" };
    if (row.kind === "favourites") return { strip: "Strip of faces and covers" };
    return { strip: "Strip of covers", tiles: "Tiles of covers" };
  }
  const countOptions = (row) => Object.fromEntries(COUNTS[row.form].map((n) => [n, String(n)]));
  // Keeps sort, form and count valid for the kind after any change.
  function fit(row) {
    if (SORT_KINDS[row.kind] && !SORT_KINDS[row.kind].includes(row.sort)) row.sort = START[row.kind].sort;
    if (!formOptions(row)[row.form]) row.form = "strip";
    if (!COUNTS[row.form].includes(row.count)) row.count = 9;
  }
  function apply(row, field, value) {
    if (field === "source") {
      if (UNIT_KINDS.includes(row.kind)) row.kind = value;
      else row.source = value;
    } else if (field === "count") row.count = Number(value);
    else row[field] = value;
    fit(row);
  }
  // The subtitle: what the row shows, minus what the title already says. Parts join with commas.
  // Sort names have a lower case form for the middle of a line and a sentence case form for the start.
  function facts(row) {
    if (row.kind === "pick") return `Sentence, from ${row.source === "library" ? "the whole library" : row.source}`;
    if (row.kind === "links") return row.links.map((k) => LINKS[k]).join(", ") || "No links";
    const noun =
      row.form === "tiles"
        ? "tiles"
        : PEOPLE.includes(row.kind)
          ? "faces"
          : row.kind === "favourites"
            ? "faces and covers"
            : "covers";
    const named = row.sort !== START[row.kind].sort;
    const terms = row.conds?.flat() ?? [];
    // The title names the source of these kinds. The other kinds name it only here.
    const parts = [];
    if (!["favourites", "saved", ...UNIT_KINDS].includes(row.kind)) parts.push(sourceOptions(row)[sourceValue(row)]);
    if (terms.length > 1) parts.push(Filters.short(row.conds));
    if (!named) parts.push(parts.length ? SORTS[row.sort] : SORT_LABELS[row.sort]);
    parts.push(`${row.count} ${noun}`);
    return parts.join(", ");
  }

  // The row setup stays on the device. A page with ?rows= is a specimen view and keeps nothing.
  const STORE = "library.rows";
  const stored = () => {
    const rows = K.store(STORE);
    return Array.isArray(rows) ? rows : null;
  };
  const keep = (rows) => K.store(STORE, rows);

  // ---------- Drawing ----------
  const toast = (text) => {
    document.querySelector(".lib-toast")?.remove();
    const t = el("div", { class: "lib-toast t-subheadline", role: "status" }, text);
    document.body.append(t);
    setTimeout(() => t.remove(), 1600);
  };
  const stub = (a, text) =>
    a.addEventListener("click", (e) => {
      e.preventDefault();
      toast(text);
    });

  function face(x, width) {
    const url = M.people[x.name]?.picture?.url;
    if (url) return el("img", { class: "lib-face", src: sized(url, 250), alt: "", loading: "lazy" });
    const initials = x.name
      .split(/\s+/)
      .filter((w) => /^\p{Lu}/u.test(w))
      .map((w) => w[0])
      .slice(0, 2)
      .join("");
    return el("div", { class: "lib-face t-footnote", style: `font-size:${width / 3}px` }, initials);
  }
  const picture = (x, width) =>
    x.type === "composer" || x.type === "performer" ? face(x, width) : K.coverImage(x.album, "cover", 250);

  // One shape per row: faces, covers or both. Faces are round and centred; covers are square.
  function shape(list) {
    const faces = list.filter((x) => x.type === "composer" || x.type === "performer").length;
    return faces === list.length ? "faces" : faces ? "mixed" : "covers";
  }
  function card(x, look) {
    const width = { faces: 88, mixed: 100, covers: 112 }[look];
    return el(
      "a",
      { class: `lib-card ${look}`, href: x.href },
      el("div", { class: "lib-img" }, picture(x, width)),
      el(
        "div",
        { class: "lib-cap" },
        el("div", { class: "lib-name t-subheadline" }, x.name),
        el("div", { class: "lib-fact t-footnote secondary" }, x.fact),
      ),
    );
  }
  function head(row) {
    const a = el(
      "a",
      { class: "section-head lib-head t-footnote", href: "#" },
      el("span", {}, title(row)),
      el("span", { class: "link", html: K.ICON.chevron }),
    );
    stub(a, `Opens the page of ${title(row)}`);
    return a;
  }
  function strip(row) {
    const list = items(row);
    if (!list.length) return null;
    const look = shape(list);
    const body =
      row.form === "tiles"
        ? el("div", { class: "lib-tiles" }, ...list.map((x) => card(x, look)))
        : el("div", { class: "lib-strip" }, ...list.map((x) => card(x, look)));
    return el("div", {}, head(row), body);
  }
  function links(row) {
    const counts = library().counts;
    if (!row.links.length) return null;
    return el(
      "div",
      { class: "lib-links" },
      ...row.links.map((k) => {
        const a = el(
          "a",
          { href: "#" },
          el("span", { class: "num t-headline" }, String(counts[k])),
          el("span", { class: "t-footnote secondary" }, LINKS[k]),
        );
        stub(a, `Opens the ${LINKS[k]} page`);
        return a;
      }),
    );
  }

  // The Daily pick: only complete recordings and albums, drawn with the date as the seed. No history.
  function pickOf(row) {
    const lib = library();
    let pool = [...lib.recordings.filter((x) => x.rec.work), ...lib.albums].filter(
      (x) => x.complete && K.cover(x.album),
    );
    if (row.source !== "library" && SAVED[row.source]) pool = pool.filter((x) => x.rec && SAVED[row.source](x.rec));
    pool.sort((a, b) => a.id.localeCompare(b.id));
    return pool.length ? pool[hash(today()) % pool.length] : null;
  }
  function pick(row) {
    const x = pickOf(row);
    if (!x) return null;
    // The title and the cover open the recording or the album that the sentence names, never its work.
    const open = x.href;
    const who = (name) => el("a", { class: "who", href: K.personHref(name, { back: "Library" }) }, name);
    const composer = x.rec?.composer && M.people[x.rec.composer] ? x.rec.composer : null;
    const l = x.rec ? lead(x.rec) : x.fact;
    const leadLink = l && M.people[l] ? who(l) : null;
    const title = el("a", { class: "title", href: open }, x.name);
    // One whole sentence per case: the app localises whole strings, never parts.
    const sentence = el(
      "p",
      { class: "dp-text t-title2", lang: "en" },
      "Today from your library:" + NB,
      title,
      composer ? [" by ", who(composer)] : null,
      leadLink ? [", with ", leadLink] : null,
      ".",
    );
    const art = el("a", { class: "art", href: open, "aria-label": x.name }, K.coverImage(x.album, "cover", 250));
    return el("div", { class: "lib-pick" }, art, sentence);
  }

  // The node of a row, or null when it has nothing to show.
  function render(row) {
    if (row.kind === "pick") return pick(row);
    if (row.kind === "links") return links(row);
    return strip(row);
  }

  // Draws the rows into the host. update(rows) redraws only rows that changed, so the tab changes live.
  function mount(host, rows, opts = {}) {
    const state = { selected: opts.selected || null, selecting: !!opts.selecting, onSelect: opts.onSelect };
    const wraps = new Map();
    host.addEventListener(
      "click",
      (e) => {
        const wrap = e.target.closest(".lib-row");
        if (!state.selecting || !wrap) return;
        e.preventDefault();
        e.stopPropagation();
        state.onSelect?.(wrap.dataset.row);
      },
      true,
    );
    const paint = (list) => {
      const live = new Set(list.map((r) => r.id));
      for (const id of [...wraps.keys()]) if (!live.has(id)) wraps.delete(id);
      host.replaceChildren(
        ...list.map((row) => {
          const sig = JSON.stringify(row);
          let entry = wraps.get(row.id);
          if (!entry || entry.sig !== sig) {
            const wrap = entry ? entry.wrap : el("div", { class: "lib-row", "data-row": row.id });
            const node = render(row);
            wrap.replaceChildren(...(node ? [node] : []));
            wrap.hidden = !node;
            entry = { sig, wrap };
            wraps.set(row.id, entry);
          }
          entry.wrap.classList.toggle("sel", state.selected === row.id);
          return entry.wrap;
        }),
      );
    };
    host.classList.toggle("lib-selecting", state.selecting);
    paint(rows);
    return {
      update(list) {
        rows = list;
        paint(list);
      },
      // Tints one row. With scroll, the row moves to the top of the page.
      select(id, { scroll = false } = {}) {
        state.selected = id;
        for (const [rid, { wrap }] of wraps) wrap.classList.toggle("sel", rid === id);
        const wrap = wraps.get(id)?.wrap;
        const page = host.closest(".scroll");
        if (scroll && wrap && page) {
          // The page pads its top for the status bar and the navigation bar. The row stops below that.
          const chrome = parseFloat(getComputedStyle(page).paddingTop) || 0;
          const top = wrap.getBoundingClientRect().top - page.getBoundingClientRect().top + page.scrollTop - chrome;
          page.scrollTo({ top, behavior: "smooth" });
        }
      },
      // Brings a row into view with the smallest move, clear of the top chrome and of the sheet.
      reveal(id) {
        const wrap = wraps.get(id)?.wrap;
        const page = host.closest(".scroll");
        if (!wrap || !page) return;
        const chrome = parseFloat(getComputedStyle(page).paddingTop) || 0;
        const view = page.getBoundingClientRect();
        const box = wrap.getBoundingClientRect();
        const sheet = window.Frame && state.selecting ? Frame.height() : 0;
        const above = box.top - view.top - chrome;
        const below = box.bottom - (view.bottom - sheet);
        if (above < 0) page.scrollTo({ top: page.scrollTop + above, behavior: "smooth" });
        else if (below > 0) page.scrollTo({ top: page.scrollTop + below, behavior: "smooth" });
      },
      // In select mode a tap on a row selects it and opens nothing.
      selecting(on) {
        state.selecting = on;
        host.classList.toggle("lib-selecting", on);
        // Room under the rows, so the last row can scroll to the top above the sheet.
        host.style.paddingBottom = on && window.Frame ? `${Frame.height()}px` : "";
      },
    };
  }

  window.Library = {
    KINDS,
    LINKS,
    UNIT_KINDS,
    defaults,
    make,
    fromParam,
    title,
    items,
    render,
    mount,
    load,
    empty,
    matching,
    scopeOf,
    sourceOptions,
    sourceValue,
    sortOptions,
    formOptions,
    countOptions,
    apply,
    facts,
    linkOrder,
    stored,
    keep,
  };
})();
