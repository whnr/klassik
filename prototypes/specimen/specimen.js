// The specimen frame: data model, specimen controls, app chrome, timeline, mini player and sheet.
// Pages call K.start(render). Flows follow ADR 0013 to 0020; looks come from tokens.css and a variant only.
"use strict";

const K = (() => {
  const params = new URLSearchParams(location.search);
  const CARRIED = ["variant", "theme", "contrast", "size", "playing", "side"];
  const SIZES = ["xSmall", "small", "medium", "large", "xLarge", "xxLarge", "xxxLarge", "AX1", "AX2", "AX3", "AX4", "AX5"];
  const ROMAN = ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII", "XIII", "XIV", "XV", "XVI"];
  const ENSEMBLE = new Set(["Orchestra", "Choir", "Ensemble", "Trio", "Quartet"]);

  function store(key, value) {
    try {
      if (value === undefined) return JSON.parse(sessionStorage.getItem("specimen." + key) || "null");
      sessionStorage.setItem("specimen." + key, JSON.stringify(value));
    } catch { return null; }
  }

  // Settings come from the link only, so a page opened without parameters shows the defaults. Links carry them on.
  function setting(name, fallback) {
    return params.get(name) || fallback;
  }

  function href(path, extra = {}) {
    const p = new URLSearchParams();
    for (const name of CARRIED) if (params.get(name)) p.set(name, params.get(name));
    for (const [k, v] of Object.entries(extra)) if (v != null) p.set(k, v);
    const q = p.toString();
    return path + (q ? "?" + q : "");
  }

  function el(tag, attrs = {}, ...children) {
    const node = document.createElement(tag);
    for (const [k, v] of Object.entries(attrs)) {
      if (v == null || v === false) continue;
      if (k.startsWith("on")) node.addEventListener(k.slice(2), v);
      else if (k === "html") node.innerHTML = v;
      else node.setAttribute(k, v === true ? "" : v);
    }
    for (const c of children.flat()) if (c != null && c !== false) node.append(c.nodeType ? c : document.createTextNode(c));
    return node;
  }

  const ICON = {
    back: '<svg viewBox="0 0 13 21" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"><path d="M11 2 2.5 10.5 11 19"/></svg>',
    chevron: '<svg class="chevron" viewBox="0 0 8 14" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m1.5 1.5 5 5.5-5 5.5"/></svg>',
    play: '<svg viewBox="0 0 14 14" fill="currentColor"><path d="M3 1.6v10.8c0 .6.6.9 1.1.6l8.6-5.4c.5-.3.5-.9 0-1.2L4.1 1C3.6.7 3 1 3 1.6z"/></svg>',
    pause: '<svg viewBox="0 0 14 14" fill="currentColor"><rect x="2.5" y="1.5" width="3.2" height="11" rx="1"/><rect x="8.3" y="1.5" width="3.2" height="11" rx="1"/></svg>',
    prev: '<svg viewBox="0 0 14 14" fill="currentColor"><rect x="1.5" y="2" width="2" height="10" rx="1"/><path d="M12.5 2.6v8.8c0 .5-.6.8-1 .5L4.4 7.5c-.4-.3-.4-.8 0-1L11.5 2c.4-.3 1 0 1 .6z"/></svg>',
    next: '<svg viewBox="0 0 14 14" fill="currentColor"><rect x="10.5" y="2" width="2" height="10" rx="1"/><path d="M1.5 2.6v8.8c0 .5.6.8 1 .5l7.1-4.4c.4-.3.4-.8 0-1L2.5 2c-.4-.3-1 0-1 .6z"/></svg>',
    library: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M5 4v16M10 4v16M15 5l4 15"/></svg>',
    chronology: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M7 3v18M12 6v12M17 2v15"/><circle cx="7" cy="9" r="1.6" fill="currentColor"/><circle cx="12" cy="13" r="1.6" fill="currentColor"/><circle cx="17" cy="7" r="1.6" fill="currentColor"/></svg>',
    settings: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><circle cx="12" cy="12" r="3.2"/><path d="M12 2.8v3M12 18.2v3M2.8 12h3M18.2 12h3M5.5 5.5l2.1 2.1M16.4 16.4l2.1 2.1M5.5 18.5l2.1-2.1M16.4 7.6l2.1-2.1"/></svg>',
    search: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="10.5" cy="10.5" r="6.5"/><path d="m15.5 15.5 5 5"/></svg>',
    note: '<svg viewBox="0 0 24 24" width="22" height="22" fill="currentColor"><path d="M9 17.5a3 3 0 1 1-2-2.8V5l11-2v11.5a3 3 0 1 1-2-2.8V6.3L9 7.6z"/></svg>',
  };

  // The favourite mark of ADR 0017: a fermata, filled when set and an outline when not.
  function fermata(on, small = false) {
    const shape = "M1.5 14.5A10.5 10.5 0 0 1 22.5 14.5H20.6A8.6 7.2 0 0 0 3.4 14.5Z";
    const colour = on ? "var(--color-favourite)" : "var(--color-text-tertiary)";
    const body = on
      ? `<path d="${shape}" fill="${colour}"/><circle cx="12" cy="12.4" r="2.1" fill="${colour}"/>`
      : `<path d="${shape}" fill="none" stroke="${colour}" stroke-width="1.1"/><circle cx="12" cy="12.4" r="1.6" fill="none" stroke="${colour}" stroke-width="1.1"/>`;
    const span = el("span", { class: "fermata" + (small ? " small" : ""), role: "img", "aria-label": on ? "Favourite" : "Not a favourite" });
    span.innerHTML = `<svg viewBox="0 0 24 16" width="100%" height="100%">${body}</svg>`;
    return span;
  }

  function time(seconds) {
    const s = Math.max(0, Math.round(seconds));
    const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), r = String(s % 60).padStart(2, "0");
    return h ? `${h}:${String(m).padStart(2, "0")}:${r}` : `${m}:${r}`;
  }

  // ---------- Data model ----------
  const M = { albums: new Map(), recordings: new Map(), works: new Map(), composers: new Map(), artists: new Map(), covers: {}, chronology: null };

  // The title as tagged. Under its work, the work name in front repeats the heading, so it goes; nothing is added.
  function movementTitle(song, work) {
    if (work && song.title.startsWith(work + ": ")) return song.title.slice(work.length + 2);
    return song.title;
  }

  // A title with the favourite mark glued to its last word, so the mark never wraps alone.
  function titled(text, mark) {
    const cut = text.lastIndexOf(" ");
    const frag = document.createDocumentFragment();
    frag.append(text.slice(0, cut + 1), el("span", { style: "white-space: nowrap" }, text.slice(cut + 1), mark));
    return frag;
  }

  const personHref = (name, extra = {}) => href("person.html", { name, ...extra });

  function performersOf(songs, album) {
    const seen = new Map();
    for (const s of songs) for (const c of s.contributors || []) {
      if (c.role === "composer" || seen.has(c.artist.id)) continue;
      seen.set(c.artist.id, { id: c.artist.id, name: c.artist.name, role: c.role, subRole: c.subRole || null });
    }
    let list = [...seen.values()];
    if (!list.length) {
      list = (album.displayArtist || album.artist || "").split(/,\s*|\s•\s/).filter(Boolean)
        .map((name) => ({ id: null, name, role: "artist", subRole: null }));
    }
    const rank = (p) => (p.role === "conductor" ? 0 : p.role === "artist" ? 1 : ENSEMBLE.has(p.subRole) ? 3 : 2);
    return list.sort((a, b) => rank(a) - rank(b));
  }

  function build(data, chronology) {
    M.covers = data.covers;
    M.chronology = chronology;
    for (const a of data.artists) M.artists.set(a.id, a);
    for (const album of data.albums) {
      M.albums.set(album.id, album);
      const groups = new Map();
      for (const song of album.song) {
        const work = song.works && song.works[0] ? song.works[0].name : null;
        const composer = song.displayComposer || null;
        const key = work ? `${album.id}|${composer}|${work}` : `${album.id}|album`;
        if (!groups.has(key)) groups.set(key, { id: key, album, work, composer, songs: [] });
        groups.get(key).songs.push(song);
      }
      album.recordings = [];
      for (const r of groups.values()) {
        r.performers = performersOf(r.songs, album);
        r.year = r.songs[0].year || album.year || null;
        r.duration = r.songs.reduce((t, s) => t + s.duration, 0);
        r.genres = [...new Set(r.songs.flatMap((s) => (s.genres || []).map((g) => g.name)))];
        r.grouping = (r.songs[0].groupings || [])[0] || null;
        M.recordings.set(r.id, r);
        album.recordings.push(r);
        if (r.work) {
          const wk = `${r.composer}|${r.work}`;
          if (!M.works.has(wk)) {
            const year = chronology.workYears[r.composer] ? chronology.workYears[r.composer][r.work] : null;
            M.works.set(wk, { id: wk, name: r.work, composer: r.composer, recordings: [], year: year ?? null, grouping: r.grouping, genres: new Set() });
          }
          const w = M.works.get(wk);
          w.recordings.push(r);
          r.genres.forEach((g) => w.genres.add(g));
          r.workRef = w;
        }
        if (r.composer) {
          if (!M.composers.has(r.composer)) M.composers.set(r.composer, { name: r.composer, works: new Set(), facts: chronology.composers[r.composer] || null });
          if (r.workRef) M.composers.get(r.composer).works.add(r.workRef);
        }
      }
    }
  }

  // ---------- Favourites: specimen state on this device (ADR 0013 stores some on the server). ----------
  const DEFAULT_FAVOURITES = ["work:Ludwig van Beethoven|Symphony No. 5 in C minor, Op. 67", "composer:Frédéric Chopin"];
  let favourites = new Set(store("favourites") || DEFAULT_FAVOURITES);
  const isFavourite = (key) => favourites.has(key);
  function toggleFavourite(key) {
    favourites.has(key) ? favourites.delete(key) : favourites.add(key);
    store("favourites", [...favourites]);
  }

  function orderedRecordings(work) {
    const favs = work.recordings.filter((r) => isFavourite("rec:" + r.id));
    const rest = work.recordings.filter((r) => !favs.includes(r)).sort((a, b) => (b.year || 0) - (a.year || 0));
    return [...favs, ...rest];
  }

  // ---------- Playback: a pretend queue that ticks, so the timeline and the player move. ----------
  const QUEUES = {
    recording: { label: "Beethoven 5", items: [["recording", "640qawSbxRzx7BX6z3M2wM", "Symphony No. 5 in C minor, Op. 67"], ["recording", null, "Symphony No. 9 in E minor, Op. 95"]], start: [1, 95] },
    album: { label: "Chopin album", items: [["album", "64HbQV0X1HES4YXv4Z2nCJ"], ["recording", "640qawSbxRzx7BX6z3M2wM", "Symphony No. 5 in C minor, Op. 67"]], start: [1, 40] },
    weak: { label: "Weak tags", items: [["album", "1KhEMYqfQA2bpiPvD5lSqV"], ["album", "6MbFGUFnJLoswdnWRoGffX"]], start: [0, 200] },
    none: { label: "Nothing", items: [], start: [0, 0] },
  };
  const P = { queue: [], item: 0, index: 0, pos: 0, paused: false, listeners: new Set() };

  function resolveItem(spec) {
    const [kind, id, work] = spec;
    if (kind === "album") {
      const album = M.albums.get(id);
      return { spec, kind, id: "album:" + id, title: album.name, album, songs: album.song, recordings: album.recordings };
    }
    let rec = null;
    for (const r of M.recordings.values()) if (r.work === work && (!id || r.album.id === id)) { rec = r; break; }
    return { spec, kind, id: "rec:" + rec.id, title: rec.work, album: rec.album, songs: rec.songs, recordings: [rec], recording: rec };
  }

  function startPlayback() {
    const name = setting("playing", "recording");
    const q = QUEUES[name] || QUEUES.recording;
    P.queue = q.items.map(resolveItem);
    const saved = store("play");
    if (saved && saved.name === name) {
      if (saved.queue) P.queue = saved.queue.map(resolveItem);
      Object.assign(P, { item: saved.item, index: saved.index, pos: saved.pos + (saved.paused ? 0 : (Date.now() - saved.at) / 1000), paused: saved.paused });
    }
    else Object.assign(P, { item: 0, index: q.start[0], pos: q.start[1], paused: false });
    P.name = name;
    normalise();
    setInterval(() => { if (!P.paused && current()) { P.pos += 0.5; normalise(); emit(); } }, 500);
    addEventListener("pagehide", save);
  }

  function save() { store("play", { name: P.name, queue: P.queue.map((q) => q.spec), item: P.item, index: P.index, pos: P.pos, paused: P.paused, at: Date.now() }); }
  const current = () => P.queue[P.item] || null;
  const song = () => (current() ? current().songs[P.index] : null);

  function normalise() {
    let item = current();
    while (item && P.pos >= item.songs[P.index].duration) {
      P.pos -= item.songs[P.index].duration;
      P.index++;
      if (P.index >= item.songs.length) {
        P.item++; P.index = 0;
        item = current();
        P.onItemEnd && P.onItemEnd();
      }
    }
  }

  function emit() { save(); P.listeners.forEach((f) => f()); }
  function seek(index, pos = 0) { P.index = index; P.pos = pos; normalise(); emit(); }
  function playItem(item, index = 0) { P.queue = [item, ...P.queue.filter((q) => q.id !== item.id).slice(0, 1)]; P.item = 0; P.paused = false; seek(index); }
  function togglePause() { P.paused = !P.paused; emit(); }
  function onPlay(f) { P.listeners.add(f); }

  // ---------- Covers and the wash ----------
  function cover(album, width = 250) {
    const c = M.covers[album.id];
    if (!c) return null;
    return { url: c.url.replace(/\/\d+px-/, `/${width}px-`).split("?")[0], credit: `${c.title}, ${c.painter}, ${c.year}. ${c.licence}.`, page: c.page };
  }

  function coverImage(album, cls = "cover", width = 250) {
    const c = cover(album, width);
    if (!c) {
      const none = el("div", { class: cls + " none", role: "img", "aria-label": "No cover" });
      none.innerHTML = ICON.note;
      return none;
    }
    return el("img", { class: cls, src: c.url, alt: "", loading: "lazy", crossorigin: "anonymous" });
  }

  // The average colour of a cover, or null when the image cannot be read.
  function coverColour(album) {
    const c = cover(album, 250);
    if (!c) return Promise.resolve(null);
    const cached = store("colour." + album.id);
    if (cached) return Promise.resolve(cached);
    return new Promise((resolve) => {
      const img = new Image();
      img.crossOrigin = "anonymous";
      img.onload = () => {
        try {
          const canvas = document.createElement("canvas");
          canvas.width = canvas.height = 16;
          const ctx = canvas.getContext("2d");
          ctx.drawImage(img, 0, 0, 16, 16);
          const px = ctx.getImageData(0, 0, 16, 16).data;
          let r = 0, g = 0, b = 0;
          for (let i = 0; i < px.length; i += 4) { r += px[i]; g += px[i + 1]; b += px[i + 2]; }
          const n = px.length / 4, rgb = [r / n, g / n, b / n].map(Math.round);
          store("colour." + album.id, rgb);
          resolve(rgb);
        } catch { resolve(null); }
      };
      img.onerror = () => resolve(null);
      img.src = c.url;
    });
  }

  // ---------- Names ----------
  // ADR 0014: a surname comes from the artist's sort name; without a sort name, the full name shows.
  function surname(name) {
    const artist = [...M.artists.values()].find((a) => a.name === name);
    const sort = artist && artist.sortName;
    if (sort && sort.includes(",")) {
      const head = sort.split(",")[0].trim().toLowerCase();
      const words = name.split(/\s+/);
      const hit = words.findIndex((w) => w.toLowerCase() === head.split(/\s+/)[0]);
      return hit >= 0 ? words.slice(hit).join(" ") : name;
    }
    return name;
  }

  function peopleLine(item, s) {
    const composer = s.displayComposer;
    const conductor = (s.contributors || []).find((c) => c.role === "conductor");
    const lead = conductor || (s.contributors || []).find((c) => c.role === "performer");
    const names = [composer && surname(composer), lead && surname(lead.artist.name)].filter(Boolean);
    return names.length ? names.join(" · ") : item.album.displayArtist;
  }

  // ---------- Specimen controls ----------
  function applyLook() {
    const root = document.documentElement;
    const theme = setting("theme", "auto");
    const dark = theme === "dark" || (theme === "auto" && matchMedia("(prefers-color-scheme: dark)").matches);
    root.dataset.theme = dark ? "dark" : "light";
    const contrast = setting("contrast", "auto");
    root.dataset.contrast = contrast === "high" || (contrast === "auto" && matchMedia("(prefers-contrast: more)").matches) ? "high" : "normal";
    root.dataset.typeSize = setting("size", "large");
    root.dataset.side = setting("side", "right");
  }

  function setParam(name, value) {
    store(name, value);
    params.set(name, value);
    history.replaceState(null, "", location.pathname + "?" + params.toString());
  }

  async function loadVariant() {
    let variants = {};
    try { variants = await (await fetch("variants/variants.json", { cache: "no-store" })).json(); } catch { /* none yet */ }
    const name = params.get("variant");
    const v = name && variants[name];
    if (v) {
      if (v.css) document.head.append(el("link", { rel: "stylesheet", href: "variants/" + v.css }));
      if (v.js) await new Promise((ok) => document.head.append(el("script", { src: "variants/" + v.js, onload: ok, onerror: ok })));
    }
    return variants;
  }

  function controls(variants) {
    const bar = el("div", { class: "specimen-bar", "aria-label": "Specimen controls" });
    // A variant names its page; a look variant without a page shows everywhere. Other pages show no menu.
    const here = location.pathname.split("/").pop().replace(".html", "") || "index";
    const names = Object.keys(variants).filter((n) => !variants[n].page || variants[n].page === here);
    if (names.length) {
      const sel = el("select", { "aria-label": "Variant", onchange: (e) => { setParam("variant", e.target.value); location.reload(); } },
        el("option", { value: "" }, "decided"), ...names.map((n) => el("option", { value: n, selected: params.get("variant") === n }, variants[n].label || n)));
      bar.append(sel);
    }
    const themes = ["auto", "light", "dark"];
    const theme = el("button", { onclick: () => { const t = themes[(themes.indexOf(setting("theme", "auto")) + 1) % 3]; setParam("theme", t); theme.textContent = label(t); applyLook(); } });
    const label = (t) => ({ auto: "◐ Auto", light: "○ Light", dark: "● Dark" })[t];
    theme.textContent = label(setting("theme", "auto"));
    const contrast = el("button", { onclick: () => { const c = setting("contrast", "auto") === "high" ? "normal" : "high"; setParam("contrast", c); contrast.classList.toggle("on", c === "high"); applyLook(); } }, "Contrast");
    contrast.classList.toggle("on", setting("contrast", "auto") === "high");
    const size = el("select", { "aria-label": "Text size", onchange: (e) => { setParam("size", e.target.value); applyLook(); layoutChrome(); } },
      ...SIZES.map((s) => el("option", { value: s, selected: setting("size", "large") === s }, "Aa " + s)));
    const playing = el("select", { "aria-label": "What plays", onchange: (e) => { setParam("playing", e.target.value); store("play", null); location.reload(); } },
      ...Object.entries(QUEUES).map(([k, q]) => el("option", { value: k, selected: setting("playing", "recording") === k }, "▶ " + q.label)));
    bar.append(theme, contrast, size, playing);
    // The timeline edge is a listener option on every page; it leads the pill so a narrow screen never hides it.
    const sides = { right: "Timeline ⇥", left: "⇤ Timeline" };
    bar.prepend(el("button", { class: "on", "aria-label": "Timeline edge", onclick: () => { setParam("side", setting("side", "right") === "right" ? "left" : "right"); location.reload(); } }, sides[setting("side", "right")]));
    document.body.append(bar);
    // Safari can show the first option of a select built before it joined the page; set each value once it is there.
    bar.querySelectorAll("select").forEach((s) => { const on = s.querySelector("option[selected]"); if (on) s.value = on.value; });
    // The pill wraps on a narrow screen instead of scrolling; the app frame starts below its real height.
    new ResizeObserver(() => { document.documentElement.style.setProperty("--pill-space", bar.offsetHeight + 2 + "px"); layoutChrome(); }).observe(bar);
  }

  // ---------- App chrome ----------
  let chrome = {};

  function tabbar(tab) {
    const t = (id, name, path) => el("a", { href: href(path), class: tab === id ? "on" : null, html: ICON[id] + `<span class="t-caption2">${name}</span>` });
    return el("nav", { class: "tabbar" },
      el("div", { class: "tabs glass" }, t("library", "Library", "index.html"), t("chronology", "Chronology", "chronology.html"), t("settings", "Settings", "tokens.html")),
      el("a", { href: href("search.html"), class: "tab-search glass" + (tab === "search" ? " on" : ""), "aria-label": "Search", html: ICON.search }));
  }

  function page({ tab = "library", title = "", back = null, plain = false, player = false, actions = [], tabs = true }) {
    const app = el("div", { class: "app" + (plain ? " plain" : "") });
    const backLabel = params.get("back") || (back && back.label);
    // ADR 0023: the bar shows no title, so the back button names the page behind in full.
    const nav = el("header", { class: "nav" },
      backLabel
        ? el("button", { class: "back", onclick: () => (history.length > 1 && document.referrer ? history.back() : (location.href = href(back ? back.href : "index.html"))), html: ICON.back + `<span class="t-body"></span>` })
        : el("span"),
      el("div", { class: "actions" }, ...actions.map((a) => el("button", { class: "t-body", onclick: a.onClick }, a.label))));
    if (backLabel) nav.querySelector(".back span").textContent = backLabel;
    const scroll = el("main", { class: "scroll" });
    scroll.addEventListener("scroll", () => nav.classList.toggle("scrolled", scroll.scrollTop > 8), { passive: true });
    app.append(nav, scroll);
    document.body.append(app);
    if (tabs) { chrome.tabbar = tabbar(tab); document.body.append(chrome.tabbar); }
    chrome.player = player;
    chrome.app = app;
    chrome.title = title;
    buildPlayingChrome();
    return { app, nav, scroll };
  }

  function buildPlayingChrome() {
    if (!current()) return;
    const tl = el("div", { class: "timeline", role: "slider", "aria-label": "Timeline" }, el("div", { class: "bar" }));
    const label = el("div", { class: "scrub-label t-footnote" });
    document.body.append(tl, label);
    chrome.timeline = tl;
    chrome.scrubLabel = label;
    if (!chrome.player) {
      const mini = el("a", { class: "mini glass", href: href("player.html", { back: chrome.title || null }) },
        el("span", { class: "mini-cover" }),
        el("div", { class: "lines" }, el("div", { class: "marquee t-subheadline" }, el("span")), el("div", { class: "t-footnote secondary w" }), el("div", { class: "t-footnote secondary p" })));
      document.body.append(mini);
      chrome.mini = mini;
    }
    timelineGestures(tl);
    addEventListener("resize", layoutChrome);
    onPlay(updatePlayingChrome);
    requestAnimationFrame(() => { layoutChrome(); updatePlayingChrome(); });
  }

  // Play on a recording or album page turns that page into the player in place (ADR 0015).
  function becomePlayer() {
    chrome.player = true;
    if (chrome.mini) { chrome.mini.remove(); chrome.mini = null; }
    if (!chrome.timeline) buildPlayingChrome();
    layoutChrome();
  }

  function layoutChrome() {
    const tabTop = chrome.tabbar ? chrome.tabbar.getBoundingClientRect().top : innerHeight - 8;
    const gap = parseFloat(getComputedStyle(document.documentElement).getPropertyValue("--space-s")) || 8;
    let bottom = tabTop - gap;
    if (chrome.mini) {
      chrome.mini.style.bottom = innerHeight - bottom + "px";
    }
    if (chrome.timeline) chrome.timeline.style.height = Math.max(40, bottom - chrome.timeline.getBoundingClientRect().top) + "px";
    const miniH = chrome.mini ? chrome.mini.offsetHeight + gap : 0;
    if (chrome.app) chrome.app.querySelector(".scroll").style.setProperty("--bottom-space", innerHeight - tabTop + miniH + 32 + "px");
    drawTimeline();
  }

  let lastMini = "";
  function updatePlayingChrome() {
    drawTimelineProgress();
    if (!chrome.mini) return;
    const item = current(), s = song();
    if (!item) { chrome.mini.remove(); chrome.timeline.remove(); return; }
    const key = item.id + "|" + P.index;
    if (key === lastMini) return;
    lastMini = key;
    const slot = chrome.mini.querySelector(".mini-cover");
    slot.replaceChildren(coverImage(item.album));
    const work = s.works && s.works[0] ? s.works[0].name : item.title;
    const m = chrome.mini.querySelector(".marquee");
    const text = movementTitle(s, work);
    m.firstChild.textContent = text;
    m.classList.remove("run");
    requestAnimationFrame(() => {
      if (m.scrollWidth > m.clientWidth + 1) {
        m.firstChild.textContent = text;
        m.append(m.firstChild.cloneNode(true));
        m.classList.add("run");
        m.style.setProperty("--marquee-time", Math.max(8, text.length / 4) + "s");
      }
      while (m.children.length > 2) m.lastChild.remove();
    });
    chrome.mini.querySelector(".w").textContent = work;
    chrome.mini.querySelector(".p").textContent = peopleLine(item, s);
  }

  function segments() {
    const item = current();
    const H = chrome.timeline.clientHeight, gap = item.songs.length > 40 ? 1 : 2;
    const total = item.songs.reduce((t, s) => t + s.duration, 0);
    const usable = H - gap * (item.songs.length - 1);
    let y = 0;
    return item.songs.map((s) => { const h = Math.max(1, (s.duration / total) * usable); const seg = { y, h, s }; y += h + gap; return seg; });
  }

  function drawTimeline() {
    if (!chrome.timeline || !current()) return;
    const bar = chrome.timeline.querySelector(".bar");
    bar.replaceChildren(...segments().map((g) => {
      const seg = el("div", { class: "seg" }, el("div", { class: "done" }));
      seg.style.top = g.y + "px"; seg.style.height = g.h + "px";
      return seg;
    }));
    drawTimelineProgress();
  }

  function drawTimelineProgress() {
    if (!chrome.timeline || !current()) return;
    const segs = chrome.timeline.querySelectorAll(".seg .done");
    if (segs.length !== current().songs.length) return drawTimeline();
    segs.forEach((d, i) => {
      const f = i < P.index ? 1 : i > P.index ? 0 : P.pos / current().songs[i].duration;
      d.style.height = f * 100 + "%";
    });
  }

  function timelineGestures(tl) {
    let start = null;
    const at = (clientY) => {
      const y = clientY - tl.getBoundingClientRect().top;
      const segs = segments();
      let i = segs.findIndex((g) => y < g.y + g.h);
      if (i < 0) i = segs.length - 1;
      const g = segs[i];
      return { index: i, pos: Math.min(1, Math.max(0, (y - g.y) / g.h)) * g.s.duration };
    };
    const show = (y, t) => {
      const s = current().songs[t.index];
      chrome.scrubLabel.textContent = `${movementTitle(s, s.works && s.works[0] && s.works[0].name)} · ${time(t.pos)}`;
      chrome.scrubLabel.style.top = y + "px";
      chrome.scrubLabel.classList.add("on");
    };
    tl.addEventListener("pointerdown", (e) => { e.preventDefault(); start = { x: e.clientX, y: e.clientY, scrub: false }; tl.setPointerCapture(e.pointerId); });
    tl.addEventListener("pointermove", (e) => {
      if (!start) return;
      if (!start.scrub && Math.abs(e.clientY - start.y) > 8 && Math.abs(e.clientY - start.y) > Math.abs(e.clientX - start.x)) start.scrub = true;
      // P.scrubbing tells the player page to hold its rows still until the finger lifts.
      if (start.scrub) { const t = at(e.clientY); show(e.clientY, t); P.scrubbing = true; seek(t.index, t.pos); }
    });
    const end = (e) => {
      if (!start) return;
      const sideways = Math.abs(e.clientX - start.x) > 12;
      if (!start.scrub && !sideways && e.type === "pointerup") seek(at(e.clientY).index, 0);
      chrome.scrubLabel.classList.remove("on");
      start = null;
      if (P.scrubbing) { P.scrubbing = false; emit(); }
    };
    tl.addEventListener("pointerup", end);
    tl.addEventListener("pointercancel", end);
  }

  // ---------- Sheet ----------
  function sheet(title, body) {
    const scrim = el("div", { class: "scrim" });
    const done = el("button", { class: "t-body tint", onclick: () => close() }, "Done");
    const box = el("div", { class: "sheet", role: "dialog", "aria-label": title },
      el("div", { class: "grabber" }), el("div", { class: "sheet-head" }, el("h2", { class: "t-headline" }, title), done), el("div", { class: "sheet-body" }, body));
    const close = () => { scrim.classList.remove("on"); box.classList.remove("on"); setTimeout(() => { scrim.remove(); box.remove(); }, 400); };
    scrim.addEventListener("click", close);
    document.body.append(scrim, box);
    requestAnimationFrame(() => { scrim.classList.add("on"); box.classList.add("on"); });
    return close;
  }

  async function start(render) {
    applyLook();
    matchMedia("(prefers-color-scheme: dark)").addEventListener("change", applyLook);
    const variants = await loadVariant();
    const [data, chronology, people] = await Promise.all(["specimen", "chronology", "people"].map((n) => fetch(`data/${n}.json`).then((r) => r.json())));
    build(data, chronology);
    M.people = people.people;
    startPlayback();
    controls(variants);
    render();
  }

  return {
    start, page, el, ICON, href, params, store, fermata, time, sheet, cover, coverImage, coverColour, surname,
    M, P, current, song, seek, playItem, togglePause, onPlay, resolveItem, movementTitle,
    isFavourite, toggleFavourite, orderedRecordings, layoutChrome, emit, becomePlayer, performersOf, ROMAN, titled, personHref,
  };
})();
