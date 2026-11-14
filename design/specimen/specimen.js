// The specimen frame: data model, specimen controls, app chrome, timeline, mini player and sheet.
// Pages call K.start(render). Flows follow ADR 0013 to 0029; looks come from tokens.css and the decided drawn views.

// biome-ignore lint/correctness/noUnusedVariables: every page script and look file reads K as a global.
const K = (() => {
  const params = new URLSearchParams(location.search);
  // The page name lets the CSS keep inset grouped lists in Settings (the token sheet) only.
  document.documentElement.dataset.page = location.pathname.split("/").pop().replace(".html", "") || "index";
  // Variant files carry the stamp of specimen.js, so Safari loads new copies with it.
  const STAMP = document.currentScript ? new URL(document.currentScript.src).searchParams.get("v") || "" : "";
  const CARRIED = ["variant", "look", "theme", "paper", "contrast", "size", "playing", "side", "edge", "place"];
  const SIZES = [
    "xSmall",
    "small",
    "medium",
    "large",
    "xLarge",
    "xxLarge",
    "xxxLarge",
    "AX1",
    "AX2",
    "AX3",
    "AX4",
    "AX5",
  ];
  const ROMAN = ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII", "XIII", "XIV", "XV", "XVI"];
  const ENSEMBLE = new Set(["Orchestra", "Choir", "Ensemble", "Trio", "Quartet"]);

  function store(key, value) {
    try {
      if (value === undefined) return JSON.parse(sessionStorage.getItem("specimen." + key) || "null");
      sessionStorage.setItem("specimen." + key, JSON.stringify(value));
    } catch {
      return null;
    }
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
    // Safari fetches an image as soon as src is set: crossorigin must come first, or a canvas cannot read it.
    if ("crossorigin" in attrs) node.setAttribute("crossorigin", attrs.crossorigin);
    for (const [k, v] of Object.entries(attrs)) {
      if (v == null || v === false) continue;
      if (k.startsWith("on")) node.addEventListener(k.slice(2), v);
      else if (k === "html") node.innerHTML = v;
      else node.setAttribute(k, v === true ? "" : v);
    }
    for (const c of children.flat())
      if (c != null && c !== false) node.append(c.nodeType ? c : document.createTextNode(c));
    return node;
  }

  const ICON = {
    back: '<svg viewBox="0 0 13 21" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"><path d="M11 2 2.5 10.5 11 19"/></svg>',
    chevron:
      '<svg class="chevron" viewBox="0 0 8 14" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m1.5 1.5 5 5.5-5 5.5"/></svg>',
    play: '<svg viewBox="0 0 14 14" fill="currentColor"><path d="M3 1.6v10.8c0 .6.6.9 1.1.6l8.6-5.4c.5-.3.5-.9 0-1.2L4.1 1C3.6.7 3 1 3 1.6z"/></svg>',
    pause:
      '<svg viewBox="0 0 14 14" fill="currentColor"><rect x="2.5" y="1.5" width="3.2" height="11" rx="1"/><rect x="8.3" y="1.5" width="3.2" height="11" rx="1"/></svg>',
    prev: '<svg viewBox="0 0 14 14" fill="currentColor"><rect x="1.5" y="2" width="2" height="10" rx="1"/><path d="M12.5 2.6v8.8c0 .5-.6.8-1 .5L4.4 7.5c-.4-.3-.4-.8 0-1L11.5 2c.4-.3 1 0 1 .6z"/></svg>',
    next: '<svg viewBox="0 0 14 14" fill="currentColor"><rect x="10.5" y="2" width="2" height="10" rx="1"/><path d="M1.5 2.6v8.8c0 .5.6.8 1 .5l7.1-4.4c.4-.3.4-.8 0-1L2.5 2c-.4-.3-1 0-1 .6z"/></svg>',
    library:
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M5 4v16M10 4v16M15 5l4 15"/></svg>',
    chronology:
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M7 3v18M12 6v12M17 2v15"/><circle cx="7" cy="9" r="1.6" fill="currentColor"/><circle cx="12" cy="13" r="1.6" fill="currentColor"/><circle cx="17" cy="7" r="1.6" fill="currentColor"/></svg>',
    settings:
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><circle cx="12" cy="12" r="3.2"/><path d="M12 2.8v3M12 18.2v3M2.8 12h3M18.2 12h3M5.5 5.5l2.1 2.1M16.4 16.4l2.1 2.1M5.5 18.5l2.1-2.1M16.4 7.6l2.1-2.1"/></svg>',
    search:
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="10.5" cy="10.5" r="6.5"/><path d="m15.5 15.5 5 5"/></svg>',
    note: '<svg viewBox="0 0 24 24" width="22" height="22" fill="currentColor"><path d="M9 17.5a3 3 0 1 1-2-2.8V5l11-2v11.5a3 3 0 1 1-2-2.8V6.3L9 7.6z"/></svg>',
  };

  // The favourite mark of ADR 0033: the engraved arc, the accent at full strength when set and a quiet grey when not.
  const FERMATA =
    "M0 14.5A8.5 10.5 0 0 1 17 14.5H16.3A7.8 7.9 0 0 0 0.7 14.5Z M10.9 11.9A2.4 2.4 0 1 1 6.1 11.9A2.4 2.4 0 1 1 10.9 11.9Z";
  function fermata(on, small = false) {
    const colour = on ? "var(--color-favourite)" : "var(--color-favourite-off, var(--color-text-secondary))";
    const span = el("span", {
      class: "fermata" + (small ? " small" : ""),
      role: "img",
      "aria-label": on ? "Favourite" : "Not a favourite",
    });
    span.innerHTML = `<svg viewBox="0 4 17 10.5" width="100%" height="100%"><path d="${FERMATA}" fill="${colour}"/></svg>`;
    return span;
  }

  function time(seconds) {
    const s = Math.max(0, Math.round(seconds));
    const h = Math.floor(s / 3600),
      m = Math.floor((s % 3600) / 60),
      r = String(s % 60).padStart(2, "0");
    return h ? `${h}:${String(m).padStart(2, "0")}:${r}` : `${m}:${r}`;
  }

  // ---------- Data model ----------
  const M = {
    albums: new Map(),
    recordings: new Map(),
    works: new Map(),
    composers: new Map(),
    artists: new Map(),
    covers: {},
    chronology: null,
  };

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
    for (const s of songs)
      for (const c of s.contributors || []) {
        if (c.role === "composer" || seen.has(c.artist.id)) continue;
        seen.set(c.artist.id, { id: c.artist.id, name: c.artist.name, role: c.role, subRole: c.subRole || null });
      }
    let list = [...seen.values()];
    if (!list.length) {
      list = (album.displayArtist || album.artist || "")
        .split(/,\s*|\s•\s/)
        .filter(Boolean)
        .map((name) => ({ id: null, name, role: "artist", subRole: null }));
    }
    const rank = (p) => (p.role === "conductor" ? 0 : p.role === "artist" ? 1 : ENSEMBLE.has(p.subRole) ? 3 : 2);
    return list.sort((a, b) => rank(a) - rank(b));
  }

  // ---------- Words (sz-rs30.1.83.16): prose and plain words carry facts; no separator glyph ----------
  const NB = " ";
  // A number never wraps away from its word: "4 movements", "1 movement".
  function count(n, one, many = one + "s") {
    return `${n}${NB}${n === 1 ? one : many}`;
  }
  // Rounded to the minute, never under one: 41:58 is "42 minutes"; an hour and more reads "1 hour 14 minutes".
  function duration(seconds) {
    const m = Math.max(1, Math.round(seconds / 60)),
      h = Math.floor(m / 60),
      r = m % 60;
    return h ? [count(h, "hour"), r ? count(r, "minute") : null].filter(Boolean).join(" ") : count(m, "minute");
  }
  const LIST = new Intl.ListFormat("en-GB", { style: "long", type: "conjunction" });
  const joinNames = (names) => LIST.format(names);

  // The label of a role, in lowercase: CSS sets it as small caps.
  function roleLabel(p) {
    if (p.role === "artist") return null;
    if (p.role === "performer") return (p.subRole || "performer").toLowerCase();
    return p.role.toLowerCase();
  }
  // One line per role, in the order of the list; names without a role go last, unlabelled.
  function roleGroups(people) {
    const groups = new Map();
    for (const p of people) {
      const label = roleLabel(p);
      if (!groups.has(label)) groups.set(label, []);
      groups.get(label).push(p);
    }
    const out = [...groups].filter(([l]) => l !== null).map(([label, list]) => ({ label, list }));
    if (groups.has(null)) out.push({ label: null, list: groups.get(null) });
    return out;
  }
  const accessibilitySize = () => /^AX/.test(document.documentElement.dataset.typeSize || "");
  // One line per role: the small-cap label before its names, tied by a no-break space (sz-rs30.1.83.16).
  // At accessibility sizes the label stands above its names, so a long label never takes half a line.
  function roleBlock(people, { link = (p) => p.name, extra = [] } = {}) {
    // ?edge=sort shows every name in the sort form some libraries tag ("Kubelík, Rafael").
    if (params.get("edge") === "sort") people = people.map((p) => ({ ...p, name: sortForm(p.name) }));
    const stacked = accessibilitySize();
    const line = (label, nameNodes) => {
      const names = el("span", { class: "names" }, ...nameNodes);
      if (!label) return el("div", { class: "role" }, names);
      const lab = el("span", { class: "label" }, label);
      return stacked
        ? el("div", { class: "role stacked" }, lab, names)
        : el("div", { class: "role" }, lab, NB + " ", names);
    };
    const nodes = (list) =>
      list.flatMap((p, i) => [i ? (i === list.length - 1 ? " and " : ", ") : null, link(p)]).filter(Boolean);
    const lines = [];
    for (const g of [...roleGroups(people), ...extra]) {
      // A name that holds a comma (a sort form) would make a comma list unreadable: each name of its role takes a line.
      if (g.list.length > 1 && g.list.some((p) => p.name.includes(",")))
        g.list.forEach((p) => {
          lines.push(line(g.label, [link(p)]));
        });
      else lines.push(line(g.label, nodes(g.list)));
    }
    return lines.length ? el("div", { class: "roles" }, ...lines) : null;
  }
  function sortForm(name) {
    const artist = [...M.artists.values()].find((a) => a.name === name);
    if (artist?.sortName?.includes(",")) return artist.sortName;
    const words = name.split(" ");
    return words.length > 1 && !ENSEMBLE_WORDS.test(name) ? `${words.at(-1)}, ${words.slice(0, -1).join(" ")}` : name;
  }
  const ENSEMBLE_WORDS =
    /orchest|choir|chor|ensemble|quartet|trio|philharm|consort|academy|sinfonia|kammer|soloists|singers|players|band|baroque|musica|collegium|concert/i;

  function build(data, chronology) {
    M.covers = data.covers;
    M.chronology = chronology;
    for (const a of data.artists) M.artists.set(a.id, a);
    for (const album of data.albums) {
      M.albums.set(album.id, album);
      const groups = new Map();
      for (const song of album.song) {
        const work = song.works?.[0] ? song.works[0].name : null;
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
            M.works.set(wk, {
              id: wk,
              name: r.work,
              composer: r.composer,
              recordings: [],
              year: year ?? null,
              grouping: r.grouping,
              genres: new Set(),
            });
          }
          const w = M.works.get(wk);
          w.recordings.push(r);
          r.genres.forEach((g) => {
            w.genres.add(g);
          });
          r.workRef = w;
        }
        if (r.composer) {
          if (!M.composers.has(r.composer))
            M.composers.set(r.composer, {
              name: r.composer,
              works: new Set(),
              facts: chronology.composers[r.composer] || null,
            });
          if (r.workRef) M.composers.get(r.composer).works.add(r.workRef);
        }
      }
    }
  }

  // ---------- Favourites: specimen state on this device (ADR 0013 stores some on the server). ----------
  const DEFAULT_FAVOURITES = [
    "work:Ludwig van Beethoven|Symphony No. 5 in C minor, Op. 67",
    "composer:Frédéric Chopin",
  ];
  const favourites = new Set(store("favourites") || DEFAULT_FAVOURITES);
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
    recording: {
      label: "Beethoven 5",
      items: [
        ["recording", "640qawSbxRzx7BX6z3M2wM", "Symphony No. 5 in C minor, Op. 67"],
        ["recording", null, "Symphony No. 9 in E minor, Op. 95"],
      ],
      start: [1, 95],
    },
    album: {
      label: "Chopin album",
      items: [
        ["album", "64HbQV0X1HES4YXv4Z2nCJ"],
        ["recording", "640qawSbxRzx7BX6z3M2wM", "Symphony No. 5 in C minor, Op. 67"],
      ],
      start: [1, 40],
    },
    // Round 25 (sz-rs30.1.83.21): a long work, and an album of three works, for the timeline's gaps.
    passion: { label: "Matthäus-Passion", items: [["album", "0E6R5t8dsTf408V87Y7Lct"]], start: [20, 60] },
    sonatas: { label: "Chopin sonatas", items: [["album", "3Is4qK0IBSlUYtEHMhh8YH"]], start: [4, 60] },
    weak: {
      label: "Weak tags",
      items: [
        ["album", "1KhEMYqfQA2bpiPvD5lSqV"],
        ["album", "6MbFGUFnJLoswdnWRoGffX"],
      ],
      start: [0, 200],
    },
    none: { label: "Nothing", items: [], start: [0, 0] },
  };
  const P = { queue: [], item: 0, index: 0, pos: 0, paused: false, listeners: new Set() };

  function resolveItem(spec) {
    const [kind, id, work] = spec;
    if (kind === "album") {
      const album = M.albums.get(id);
      return {
        spec,
        kind,
        id: "album:" + id,
        title: album.name,
        album,
        songs: album.song,
        recordings: album.recordings,
      };
    }
    let rec = null;
    for (const r of M.recordings.values())
      if (r.work === work && (!id || r.album.id === id)) {
        rec = r;
        break;
      }
    return {
      spec,
      kind,
      id: "rec:" + rec.id,
      title: rec.work,
      album: rec.album,
      songs: rec.songs,
      recordings: [rec],
      recording: rec,
    };
  }

  function startPlayback() {
    const name = setting("playing", "recording");
    const q = QUEUES[name] || QUEUES.recording;
    P.queue = q.items.map(resolveItem);
    const saved = store("play");
    if (saved && saved.name === name) {
      if (saved.queue) P.queue = saved.queue.map(resolveItem);
      Object.assign(P, {
        item: saved.item,
        index: saved.index,
        pos: saved.pos + (saved.paused ? 0 : (Date.now() - saved.at) / 1000),
        paused: saved.paused,
      });
    } else Object.assign(P, { item: 0, index: q.start[0], pos: q.start[1], paused: false });
    P.name = name;
    normalise();
    setInterval(() => {
      if (!P.paused && current()) {
        P.pos += 0.5;
        normalise();
        emit();
      }
    }, 500);
    addEventListener("pagehide", save);
  }

  function save() {
    store("play", {
      name: P.name,
      queue: P.queue.map((q) => q.spec),
      item: P.item,
      index: P.index,
      pos: P.pos,
      paused: P.paused,
      at: Date.now(),
    });
  }
  const current = () => P.queue[P.item] || null;
  const song = () => (current() ? current().songs[P.index] : null);

  function normalise() {
    let item = current();
    while (item && P.pos >= item.songs[P.index].duration) {
      P.pos -= item.songs[P.index].duration;
      P.index++;
      if (P.index >= item.songs.length) {
        P.item++;
        P.index = 0;
        item = current();
        P.onItemEnd?.();
      }
    }
  }

  function emit() {
    save();
    P.listeners.forEach((f) => {
      f();
    });
  }
  // A seek lands at most on the last second of its movement; the end itself would end the queue item.
  function seek(index, pos = 0) {
    P.index = index;
    P.pos = Math.min(pos, current().songs[index].duration - 1);
    normalise();
    emit();
  }
  function playItem(item, index = 0) {
    P.queue = [item, ...P.queue.filter((q) => q.id !== item.id).slice(0, 1)];
    P.item = 0;
    P.paused = false;
    seek(index);
  }
  function togglePause() {
    P.paused = !P.paused;
    emit();
  }
  function onPlay(f) {
    P.listeners.add(f);
  }

  // ---------- Covers and the wash ----------
  function cover(album, width = 250) {
    const c = M.covers[album.id];
    if (!c) return null;
    return {
      url: c.url.replace(/\/\d+px-/, `/${width}px-`).split("?")[0],
      credit: `${c.title}, ${c.painter}, ${c.year}. ${c.licence}.`,
      page: c.page,
    };
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
          let r = 0,
            g = 0,
            b = 0;
          for (let i = 0; i < px.length; i += 4) {
            r += px[i];
            g += px[i + 1];
            b += px[i + 2];
          }
          const n = px.length / 4,
            rgb = [r / n, g / n, b / n].map(Math.round);
          store("colour." + album.id, rgb);
          resolve(rgb);
        } catch {
          resolve(null);
        }
      };
      img.onerror = () => resolve(null);
      img.src = c.url;
    });
  }

  // ---------- Names ----------
  // ADR 0014: a surname comes from the artist's sort name; without a sort name, the full name shows.
  function surname(name) {
    const artist = [...M.artists.values()].find((a) => a.name === name);
    const sort = artist?.sortName;
    if (sort?.includes(",")) {
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
    return names.length ? joinNames(names) : item.album.displayArtist;
  }

  // ---------- Specimen controls ----------
  // A look variant can hold a page in one room, as SwiftUI's preferredColorScheme does for one view.
  let room = null;
  function setRoom(t) {
    room = t;
    applyLook();
  }

  function applyLook() {
    const root = document.documentElement;
    // Only the switch sets the room, so each variant is judged in the room that Flo picks.
    root.dataset.theme = room || (setting("theme", "light") === "dark" ? "dark" : "light");
    // Claret is the default accent (ADR 0034): tokens.css writes it without an attribute.
    const accent = setting("accent", "claret");
    if (accent === "claret") delete root.dataset.accent;
    else root.dataset.accent = accent;
    root.dataset.player = setting("player", "room");
    root.dataset.contrast = setting("contrast", "normal") === "high" ? "high" : "normal";
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
    try {
      variants = await (await fetch("variants/variants.json", { cache: "no-store" })).json();
    } catch {
      /* none yet */
    }
    const name = params.get("variant");
    const v = name && variants[name];
    // The decided mini player loads before any variant, so a variant can still replace it through K.setMini.
    document.head.append(el("link", { rel: "stylesheet", href: "pill.css?v=" + STAMP }));
    await new Promise((ok) =>
      document.head.append(el("script", { src: "pill.js?v=" + STAMP, onload: ok, onerror: ok })),
    );
    // The decided drawn views load on every page: the timeline shape, the player page and the person picture.
    document.head.append(el("link", { rel: "stylesheet", href: "timeline.css?v=" + STAMP }));
    document.head.append(el("link", { rel: "stylesheet", href: "cover.css?v=" + STAMP }));
    document.head.append(el("link", { rel: "stylesheet", href: "picture.css?v=" + STAMP }));
    await new Promise((ok) =>
      document.head.append(el("script", { src: "cover.js?v=" + STAMP, onload: ok, onerror: ok })),
    );
    await new Promise((ok) =>
      document.head.append(el("script", { src: "picture.js?v=" + STAMP, onload: ok, onerror: ok })),
    );
    // A look (variants/looks.json) is the variant of one look ticket. It loads after the palette, so both combine.
    let looks = {};
    try {
      looks = await (await fetch("variants/looks.json", { cache: "no-store" })).json();
    } catch {
      /* none yet */
    }
    // A look for another page does not load here, though links carry it on.
    let l = params.get("look") && looks[params.get("look")];
    if (l?.page && l.page !== document.documentElement.dataset.page) l = null;
    // One look file can serve several looks of a ticket; it reads the name from this attribute.
    if (l) document.documentElement.dataset.look = params.get("look");
    for (const x of [v, l]) {
      if (!x) continue;
      if (x.css) document.head.append(el("link", { rel: "stylesheet", href: "variants/" + x.css + "?v=" + STAMP }));
      if (x.js)
        await new Promise((ok) =>
          document.head.append(el("script", { src: "variants/" + x.js + "?v=" + STAMP, onload: ok, onerror: ok })),
        );
    }
    return { variants, looks };
  }

  function controls({ variants, looks }) {
    const bar = el("div", { class: "specimen-bar", "aria-label": "Specimen controls" });
    // A variant names its page; a look variant without a page shows everywhere. Other pages show no menu.
    const here = location.pathname.split("/").pop().replace(".html", "") || "index";
    const names = Object.keys(variants).filter((n) => !variants[n].page || variants[n].page === here);
    if (names.length) {
      const sel = el(
        "select",
        {
          "aria-label": "Variant",
          onchange: (e) => {
            setParam("variant", e.target.value);
            location.reload();
          },
        },
        el("option", { value: "" }, "decided"),
        ...names.map((n) => el("option", { value: n, selected: params.get("variant") === n }, variants[n].label || n)),
      );
      bar.append(sel);
    }
    const lookNames = Object.keys(looks).filter((n) => !looks[n].page || looks[n].page === here);
    if (lookNames.length) {
      const sel = el(
        "select",
        {
          "aria-label": "Look",
          onchange: (e) => {
            setParam("look", e.target.value);
            location.reload();
          },
        },
        el("option", { value: "" }, "Look: decided"),
        ...lookNames.map((n) => el("option", { value: n, selected: params.get("look") === n }, looks[n].label || n)),
      );
      bar.append(sel);
    }
    const current = () => (setting("theme", "light") === "dark" ? "dark" : "light");
    const theme = el("button", {
      onclick: () => {
        const t = current() === "dark" ? "light" : "dark";
        setParam("theme", t);
        theme.textContent = label(t);
        applyLook();
      },
    });
    const label = (t) => ({ light: "○ Light", dark: "● Dark" })[t];
    theme.textContent = label(current());
    const contrast = el(
      "button",
      {
        onclick: () => {
          const c = setting("contrast", "normal") === "high" ? "normal" : "high";
          setParam("contrast", c);
          contrast.classList.toggle("on", c === "high");
          applyLook();
        },
      },
      "Contrast",
    );
    contrast.classList.toggle("on", setting("contrast", "normal") === "high");
    const size = el(
      "select",
      {
        "aria-label": "Text size",
        onchange: (e) => {
          setParam("size", e.target.value);
          applyLook();
          layoutChrome();
        },
      },
      ...SIZES.map((s) => el("option", { value: s, selected: setting("size", "large") === s }, "Aa " + s)),
    );
    const playing = el(
      "select",
      {
        "aria-label": "What plays",
        onchange: (e) => {
          setParam("playing", e.target.value);
          store("play", null);
          location.reload();
        },
      },
      ...Object.entries(QUEUES).map(([k, q]) =>
        el("option", { value: k, selected: setting("playing", "recording") === k }, "▶ " + q.label),
      ),
    );
    // The accent switch and the player look are in-app settings until sz-rs30.1.83.19.15 decides (ADR 0034).
    const accents = { claret: "Claret", green: "Bottle green", plum: "Plum" };
    const accent = el(
      "select",
      {
        "aria-label": "Accent",
        onchange: (e) => {
          setParam("accent", e.target.value);
          applyLook();
        },
      },
      ...Object.entries(accents).map(([k, v]) =>
        el("option", { value: k, selected: setting("accent", "claret") === k }, v),
      ),
    );
    const player = el(
      "select",
      {
        "aria-label": "Player look",
        onchange: (e) => {
          setParam("player", e.target.value);
          location.reload();
        },
      },
      ...[
        ["room", "Cover room"],
        ["hall", "Hall"],
      ].map(([k, v]) => el("option", { value: k, selected: setting("player", "room") === k }, v)),
    );
    bar.append(theme, accent, player, contrast, size, playing);
    // The timeline edge is a listener option on every page; it leads the pill so a narrow screen never hides it.
    const sides = { right: "Timeline ⇥", left: "⇤ Timeline" };
    bar.prepend(
      el(
        "button",
        {
          class: "on",
          "aria-label": "Timeline edge",
          onclick: () => {
            setParam("side", setting("side", "right") === "right" ? "left" : "right");
            location.reload();
          },
        },
        sides[setting("side", "right")],
      ),
    );
    document.body.append(bar);
    // Safari can show the first option of a select built before it joined the page; set each value once it is there.
    bar.querySelectorAll("select").forEach((s) => {
      const on = s.querySelector("option[selected]");
      if (on) s.value = on.value;
    });
    // The pill wraps on a narrow screen instead of scrolling; the app frame starts below its real height.
    new ResizeObserver(() => {
      document.documentElement.style.setProperty("--pill-space", bar.offsetHeight + 2 + "px");
      layoutChrome();
    }).observe(bar);
  }

  // ---------- App chrome ----------
  const chrome = {};

  function tabbar(tab) {
    const roots = { library: "index.html", chronology: "chronology.html", search: "search.html" };
    const item = (id, name) =>
      el("a", {
        href: href(roots[id], { place: id }),
        class: tab === id ? "on" : null,
        "aria-label": name,
        "aria-current": tab === id ? "page" : null,
        onclick: (event) => {
          event.preventDefault();
          store("stack." + tab, location.href);
          location.href =
            tab === id
              ? href(roots[id], { place: id, back: params.get("back") })
              : store("stack." + id) || href(roots[id], { place: id, back: chrome.title || tab });
        },
        html: ICON[id] + `<span class="t-caption2">${name}</span>`,
      });
    return el(
      "nav",
      { class: "tabbar" },
      el(
        "div",
        { class: "tabs glass" },
        item("library", "Library"),
        item("chronology", "Chronology"),
        item("search", "Search"),
      ),
    );
  }

  function page({
    tab = "library",
    title = "",
    back = null,
    plain = false,
    player = false,
    actions = [],
    tabs = true,
  }) {
    const filename = location.pathname.split("/").pop();
    if (!["index.html", "chronology.html", "search.html", ""].includes(filename)) tab = params.get("place") || tab;
    params.set("place", tab);
    const app = el("div", { class: "app" + (plain ? " plain" : "") });
    const backLabel = params.get("back") || back?.label;
    // ADR 0038 keeps the destination name in the accessibility label.
    const nav = el(
      "header",
      { class: "nav" },
      backLabel
        ? el("button", {
            class: "back",
            onclick: () => {
              if (history.length > 1 && document.referrer) history.back();
              else location.href = href(back ? back.href : "index.html");
            },
            "aria-label": backLabel,
            html: ICON.back,
          })
        : el("span"),
      el(
        "div",
        { class: "actions" },
        ...actions.map((a) => el("button", { class: "t-body", onclick: a.onClick }, a.label)),
      ),
    );
    if (filename === "index.html" || filename === "") {
      nav.querySelector(".actions").append(
        el("a", {
          class: "settings-link",
          href: href("settings.html", { place: "library", back: "Library" }),
          "aria-label": "Settings",
          html: ICON.settings,
        }),
      );
    }
    const scroll = el("main", { class: "scroll" });
    scroll.addEventListener("scroll", () => nav.classList.toggle("scrolled", scroll.scrollTop > 8), { passive: true });
    indicator(scroll);
    app.append(nav, scroll);
    document.body.append(app);
    chrome.player = player;
    chrome.app = app;
    chrome.title = title;
    if (tabs) {
      chrome.tabbar = tabbar(tab);
      document.body.append(chrome.tabbar);
    }
    buildPlayingChrome();
    return { app, nav, scroll };
  }

  // Drawn by hand so it can keep clear of the timeline; it shows while the page moves, as on iOS.
  function indicator(scroll) {
    const bar = el("div", { class: "scroll-indicator" });
    document.body.append(bar);
    let hide = 0;
    const draw = () => {
      const r = scroll.getBoundingClientRect();
      const top = r.top + (parseFloat(getComputedStyle(scroll).paddingTop) || 0) - 40;
      const view = r.bottom - top - 8;
      if (scroll.scrollHeight <= scroll.clientHeight + 1) return;
      const h = Math.max(36, view * (scroll.clientHeight / scroll.scrollHeight));
      const y = top + (view - h) * (scroll.scrollTop / (scroll.scrollHeight - scroll.clientHeight));
      bar.style.top = y + "px";
      bar.style.height = h + "px";
      bar.classList.add("on");
      clearTimeout(hide);
      hide = setTimeout(() => bar.classList.remove("on"), 700);
    };
    scroll.addEventListener("scroll", draw, { passive: true });
  }

  function buildPlayingChrome() {
    if (!current()) return;
    const tl = el("div", { class: "timeline", role: "slider", "aria-label": "Timeline" }, el("div", { class: "bar" }));
    document.documentElement.classList.add("has-timeline");
    const label = el("div", { class: "scrub-label t-body" });
    document.body.append(tl, label);
    chrome.timeline = tl;
    chrome.scrubLabel = label;
    MINI.build();
    timelineGestures(tl);
    addEventListener("resize", layoutChrome);
    onPlay(updatePlayingChrome);
    requestAnimationFrame(() => {
      layoutChrome();
      updatePlayingChrome();
    });
  }

  // Play on a recording or album page turns that page into the player in place (ADR 0015).
  function becomePlayer() {
    chrome.player = true;
    MINI.remove();
    if (!chrome.timeline) buildPlayingChrome();
    else MINI.build();
    layoutChrome();
  }

  function layoutChrome() {
    const tabTop = chrome.tabbar ? chrome.tabbar.getBoundingClientRect().top : innerHeight - 8;
    const gap = parseFloat(getComputedStyle(document.documentElement).getPropertyValue("--space-s")) || 8;
    const room = MINI.place(tabTop - gap, gap);
    if (chrome.timeline)
      chrome.timeline.style.height =
        Math.max(40, room.timelineBottom - chrome.timeline.getBoundingClientRect().top) + "px";
    if (chrome.app)
      chrome.app
        .querySelector(".scroll")
        .style.setProperty("--bottom-space", innerHeight - tabTop + room.reserve + 32 + "px");
    drawTimeline();
  }

  function updatePlayingChrome() {
    drawTimelineProgress();
    if (!current()) {
      // ADR 0015: at the end of the queue the player page stays; elsewhere the mini player and the timeline go.
      if (!chrome.player) {
        MINI.remove();
        if (chrome.timeline) chrome.timeline.remove();
        document.documentElement.classList.remove("has-timeline");
      }
      return;
    }
    MINI.update();
  }

  // ---------- Mini player ----------
  // The card of ADR 0014. A mini player variant (sz-rs30.1.83.9) replaces any of these steps through K.setMini.
  let lastMini = "";
  const cardMini = {
    build() {
      if (chrome.player || chrome.mini) return;
      const mini = el(
        "a",
        { class: "mini glass", href: href("player.html", { back: chrome.title || null }) },
        el("span", { class: "mini-cover" }),
        el(
          "div",
          { class: "lines" },
          el("div", { class: "marquee t-subheadline" }, el("span")),
          el("div", { class: "t-footnote secondary w" }),
          el("div", { class: "t-footnote secondary p" }),
        ),
      );
      document.body.append(mini);
      chrome.mini = mini;
      lastMini = "";
    },
    remove() {
      if (chrome.mini) {
        chrome.mini.remove();
        chrome.mini = null;
      }
    },
    // Gets the bottom edge free above the tab bar; returns where the timeline ends and the room the content keeps free.
    place(bottom, gap) {
      if (!chrome.mini) return { timelineBottom: bottom, reserve: 0 };
      chrome.mini.style.bottom = innerHeight - bottom + "px";
      return { timelineBottom: bottom, reserve: chrome.mini.offsetHeight + gap };
    },
    update() {
      if (!chrome.mini) return;
      const item = current(),
        s = song();
      const key = item.id + "|" + P.index;
      if (key === lastMini) return;
      lastMini = key;
      chrome.mini.querySelector(".mini-cover").replaceChildren(coverImage(item.album));
      const work = s.works?.[0] ? s.works[0].name : item.title;
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
    },
    // The Search page's bottom row: what goes before the field and after the Filters button.
    searchItems() {
      const cur = current();
      const pill = cur
        ? el(
            "a",
            {
              class: "roundglass glass pill fold",
              href: href("player.html", { back: "Search" }),
              "aria-label": "Now playing",
            },
            coverImage(cur.album),
          )
        : null;
      return { lead: [], trail: [pill], hideCard: true };
    },
  };
  let MINI = cardMini;
  function setMini(provider) {
    MINI = { ...cardMini, ...provider };
  }

  // A timeline look (sz-rs30.1.83.21) sets the gap between two segments through K.setTimeline.
  // The gap is space-xxs between every segment (ADR 0035).
  let TL = { gap: () => 2 };
  function setTimeline(provider) {
    TL = { ...TL, ...provider };
  }
  const workOf = (s) => (s.works?.[0] ? s.works[0].name : "");

  function segments() {
    const item = current(),
      n = item.songs.length;
    const H = chrome.timeline.clientHeight;
    const total = item.songs.reduce((t, s) => t + s.duration, 0);
    const gaps = item.songs.map((s, i) => (i ? TL.gap(n, workOf(s) === workOf(item.songs[i - 1])) : 0));
    const usable = H - gaps.reduce((a, b) => a + b, 0);
    let y = 0;
    return item.songs.map((s, i) => {
      y += gaps[i];
      const h = Math.max(1, (s.duration / total) * usable);
      const seg = {
        y,
        h,
        s,
        first: i === 0,
        workStart: i === 0 || workOf(s) !== workOf(item.songs[i - 1]),
        workEnd: i === n - 1 || workOf(s) !== workOf(item.songs[i + 1]),
      };
      y += h;
      return seg;
    });
  }

  function drawTimeline() {
    if (!chrome.timeline || !current()) return;
    const bar = chrome.timeline.querySelector(".bar");
    bar.replaceChildren(
      ...segments().map((g) => {
        const cls = ["seg", g.first && "first", g.workStart && "work-start", g.workEnd && "work-end"]
          .filter(Boolean)
          .join(" ");
        const seg = el("div", { class: cls }, el("div", { class: "done" }));
        seg.style.top = g.y + "px";
        seg.style.height = g.h + "px";
        return seg;
      }),
    );
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
      // Two lines, the movement above its time: no separator.
      chrome.scrubLabel.replaceChildren(
        el("span", {}, movementTitle(s, s.works?.[0]?.name)),
        el("span", { class: "at nums" }, time(t.pos)),
      );
      // The label follows the finger but stays whole on screen: from the top of the timeline down to the tab bar.
      const half = chrome.scrubLabel.offsetHeight / 2,
        top = Math.max(8, chrome.timeline.getBoundingClientRect().top);
      const floor = (chrome.tabbar ? chrome.tabbar.getBoundingClientRect().top : innerHeight) - 8;
      chrome.scrubLabel.style.top = Math.min(Math.max(y, top + half), floor - half) + "px";
      chrome.scrubLabel.classList.add("on");
    };
    tl.addEventListener("pointerdown", (e) => {
      e.preventDefault();
      start = { x: e.clientX, y: e.clientY, scrub: false };
      tl.setPointerCapture(e.pointerId);
    });
    tl.addEventListener("pointermove", (e) => {
      if (!start) return;
      if (
        !start.scrub &&
        Math.abs(e.clientY - start.y) > 8 &&
        Math.abs(e.clientY - start.y) > Math.abs(e.clientX - start.x)
      )
        start.scrub = true;
      // P.scrubbing tells the player page to hold its rows still until the finger lifts.
      if (start.scrub) {
        const t = at(e.clientY);
        show(e.clientY, t);
        P.scrubbing = true;
        seek(t.index, t.pos);
      }
    });
    const end = (e) => {
      if (!start) return;
      const sideways = Math.abs(e.clientX - start.x) > 12;
      if (!start.scrub && !sideways && e.type === "pointerup") seek(at(e.clientY).index, 0);
      chrome.scrubLabel.classList.remove("on");
      start = null;
      if (P.scrubbing) {
        P.scrubbing = false;
        emit();
      }
    };
    tl.addEventListener("pointerup", end);
    tl.addEventListener("pointercancel", end);
  }

  // ---------- Sheet ----------
  function sheet(title, body) {
    const scrim = el("div", { class: "scrim" });
    const done = el("button", { class: "t-body tint", onclick: () => close() }, "Done");
    const box = el(
      "div",
      { class: "sheet", role: "dialog", "aria-label": title },
      el("div", { class: "grabber" }),
      el("div", { class: "sheet-head" }, el("h2", { class: "t-headline" }, title), done),
      el("div", { class: "sheet-body" }, body),
    );
    const close = () => {
      scrim.classList.remove("on");
      box.classList.remove("on");
      setTimeout(() => {
        scrim.remove();
        box.remove();
      }, 400);
    };
    scrim.addEventListener("click", close);
    document.body.append(scrim, box);
    requestAnimationFrame(() => {
      scrim.classList.add("on");
      box.classList.add("on");
    });
    return close;
  }

  async function start(render) {
    applyLook();
    const variants = await loadVariant();
    const [data, chronology, people] = await Promise.all(
      ["specimen", "chronology", "people"].map((n) => fetch(`data/${n}.json`).then((r) => r.json())),
    );
    build(data, chronology);
    M.people = people.people;
    startPlayback();
    controls(variants);
    render();
  }

  return {
    start,
    page,
    el,
    ICON,
    setRoom,
    href,
    params,
    store,
    fermata,
    time,
    sheet,
    cover,
    coverImage,
    coverColour,
    surname,
    M,
    P,
    current,
    song,
    seek,
    playItem,
    togglePause,
    onPlay,
    resolveItem,
    movementTitle,
    isFavourite,
    toggleFavourite,
    orderedRecordings,
    layoutChrome,
    emit,
    becomePlayer,
    performersOf,
    ROMAN,
    titled,
    personHref,
    setMini,
    cardMini,
    setTimeline,
    chrome,
    peopleLine,
    count,
    duration,
    joinNames,
    roleBlock,
    NB,
    searchItems: () => MINI.searchItems(),
  };
})();
