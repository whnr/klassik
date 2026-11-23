// The page menu: one ⋯ button at the top right of a page. It holds the actions of the
// one thing that the page shows: a recording, an album or a work. A page without such a thing has no button.
(() => {
  // menu.html loads this file itself; ?variant=page-menu there must not load it twice.
  if (K.pageMenu) return;
  const { el, params, store, M } = K;
  const SYMBOL = {
    more: '<svg viewBox="0 0 24 24" fill="currentColor"><circle cx="5" cy="12" r="2"/><circle cx="12" cy="12" r="2"/><circle cx="19" cy="12" r="2"/></svg>',
    download:
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="9.5"/><path d="M12 7v9m-4-4 4 4 4-4"/></svg>',
    cancel:
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><circle cx="12" cy="12" r="9.5"/><path d="m8.5 8.5 7 7m0-7-7 7"/></svg>',
    remove:
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 6.5h16M9 6.5V4h6v2.5M6.5 6.5 7.5 20h9l1-13.5M10 10v7m4-7v7"/></svg>',
    playNext:
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M10 6h11M10 12h11M10 18h11"/><path d="M3 4.5v6l4.5-3z" fill="currentColor" stroke="none"/></svg>',
    addToQueue:
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M10 6h11M10 12h11M10 18h11"/><path d="M3 13.5v6l4.5-3z" fill="currentColor" stroke="none"/></svg>',
    tags: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"><path d="M3.5 12.2V4.5a1 1 0 0 1 1-1h7.7l8.3 8.3a1 1 0 0 1 0 1.4l-7.1 7.1a1 1 0 0 1-1.4 0z"/><circle cx="8" cy="8" r="1.4" fill="currentColor"/></svg>',
  };
  // A fake download takes this long, so the Downloading state can be seen.
  const DOWNLOAD_MS = 9000;
  // About 900 kbit/s, a lossless classical average; the specimen data has no file sizes.
  const bytesOf = (item) => item.songs.reduce((sum, s) => sum + s.duration, 0) * 112500;
  const size = (bytes) =>
    bytes >= 1e9 ? `${(bytes / 1e9).toFixed(1)} GB` : `${Math.max(1, Math.round(bytes / 1e6))}${K.NB}MB`;

  /** The download of an item: "none", "downloading" with a share, or "downloaded". ?state= fixes it for a page. */
  function downloadOf(item) {
    const fixed = params.get("state");
    if (fixed === "downloading") return { state: "downloading", share: 0.42 };
    if (fixed === "downloaded") return { state: "downloaded" };
    if (fixed === "none" || fixed === "offline") return { state: "none" };
    const started = store("menu.download." + item.id);
    if (!started) return { state: "none" };
    const share = (Date.now() - started) / DOWNLOAD_MS;
    return share >= 1 ? { state: "downloaded" } : { state: "downloading", share };
  }
  const offline = () => params.get("state") === "offline" || params.get("offline") === "on";

  // Every state shows below its item, never above it as a header.
  function downloadSection(item) {
    const d = downloadOf(item);
    const clear = () => store("menu.download." + item.id, null);
    if (d.state === "downloaded")
      return {
        items: [
          {
            label: "Remove Download",
            icon: "remove",
            sub: `Downloaded, ${size(bytesOf(item))}`,
            destructive: true,
            run: clear,
          },
        ],
      };
    if (d.state === "downloading")
      return {
        items: [
          {
            label: "Cancel Download",
            icon: "cancel",
            sub: offline() ? "Downloading, waits for the server" : `Downloading, ${Math.floor(d.share * 100)}${K.NB}%`,
            run: clear,
          },
        ],
      };
    return {
      items: [
        {
          label: "Download",
          icon: "download",
          sub: offline() ? "Needs the server" : size(bytesOf(item)),
          disabled: offline(),
          run: () => store("menu.download." + item.id, Date.now()),
        },
      ],
    };
  }

  // Play Next and Add to Queue as in the queue. With nothing in the queue, both start the item.
  function queueSection(item) {
    const add = (next) => {
      if (!K.P.queue.length) return K.playItem(item);
      K.P.queue = K.P.queue.filter((q, i) => i === K.P.item || q.id !== item.id);
      K.P.queue.splice(next ? K.P.item + 1 : K.P.queue.length, 0, item);
      K.emit();
    };
    return {
      items: [
        { label: "Play Next", icon: "playNext", run: () => add(true) },
        { label: "Add to Queue", icon: "addToQueue", run: () => add(false) },
      ],
    };
  }

  function tagsSection(item) {
    const s = item.songs[0];
    const rows = [
      ["Title", s.title],
      ["Work", s.works?.[0]?.name],
      ["Composer", s.displayComposer],
      ["Artist", s.displayArtist],
      ["Album", s.album],
      ["Year", s.year],
      ["Genre", s.genre],
    ].filter(([, v]) => v);
    const body = el(
      "div",
      { class: "list" },
      ...rows.map(([k, v]) =>
        el(
          "div",
          { class: "row" },
          el(
            "div",
            { class: "main" },
            el("div", { class: "t-footnote secondary" }, k),
            el("div", { class: "t-body" }, v),
          ),
        ),
      ),
    );
    return { items: [{ label: "Tags and Grouping", icon: "tags", run: () => K.sheet("Tags", body) }] };
  }

  /** The sections of a page's menu, top to bottom: queue, download, tags. The order never changes with the state. */
  function sections(kind, item) {
    if (kind === "recording" || kind === "album") return [queueSection(item), downloadSection(item), tagsSection(item)];
    if (kind === "player") return [downloadSection(item), tagsSection(item)];
    // The work page queues its top recording; the items carry no line that names it.
    if (kind === "work") return [queueSection(item)];
    return [];
  }

  /** Puts the ⋯ button into a page bar. It returns open(), which the menu pages use to draw it open. */
  function attach(nav, kind, item) {
    const button = el("button", {
      class: "menu-button glass",
      "aria-label": "More",
      "aria-haspopup": "menu",
      "aria-expanded": "false",
      html: SYMBOL.more,
    });
    let panel = null;
    let scrim = null;
    const close = (refocus = true) => {
      if (!panel) return;
      panel.remove();
      scrim.remove();
      panel = null;
      button.setAttribute("aria-expanded", "false");
      if (refocus) button.focus();
    };
    const open = () => {
      if (panel) return;
      // A tap beside the open menu closes it and reaches nothing below, as on iOS.
      scrim = el("div", { class: "menu-scrim", onclick: () => close() });
      panel = el("div", { class: "menu-panel glass", role: "menu", "aria-label": "More" });
      for (const section of sections(kind, item)) {
        const group = el("div", { class: "menu-section", role: "group" });
        for (const it of section.items)
          group.append(
            el(
              "button",
              {
                class: "menu-item" + (it.destructive ? " destructive" : ""),
                role: "menuitem",
                disabled: it.disabled,
                "aria-disabled": it.disabled ? "true" : null,
                onclick: () => {
                  close();
                  it.run();
                },
              },
              el(
                "span",
                { class: "menu-text" },
                el("span", { class: "t-body" }, it.label),
                it.sub ? el("span", { class: "t-footnote secondary" }, it.sub) : null,
              ),
              el("span", { class: "menu-symbol", html: SYMBOL[it.icon] }),
            ),
          );
        panel.append(group);
      }
      const box = button.getBoundingClientRect();
      panel.style.top = `${box.bottom + 8}px`;
      panel.style.right = `${Math.max(8, innerWidth - box.right)}px`;
      document.body.append(scrim, panel);
      button.setAttribute("aria-expanded", "true");
      panel.querySelector(".menu-item:not([disabled])")?.focus({ preventScroll: true });
    };
    button.addEventListener("click", () => (panel ? close() : open()));
    document.addEventListener("keydown", (e) => {
      if (e.key === "Escape") close();
    });
    nav.querySelector(".actions").append(button);
    return { open, close };
  }

  /** What a specimen page shows, and so which menu it gets. */
  function pageThing() {
    const page = document.documentElement.dataset.page;
    if (page === "work") {
      const work = M.works.get(params.get("work") || "Ludwig van Beethoven|Symphony No. 5 in C minor, Op. 67");
      const top = K.orderedRecordings(work)[0];
      return { kind: "work", item: K.resolveItem(["recording", top.album.id, top.work]) };
    }
    if (page !== "player") return null;
    if (params.get("album")) return { kind: "album", item: K.resolveItem(["album", params.get("album")]) };
    const r = params.get("recording") && M.recordings.get(params.get("recording"));
    const item =
      (r && K.resolveItem(["recording", r.album.id, r.work])) ||
      K.current() ||
      K.resolveItem(["recording", "640qawSbxRzx7BX6z3M2wM", "Symphony No. 5 in C minor, Op. 67"]);
    if (K.embedded) return { kind: "player", item };
    return { kind: item.kind === "album" ? "album" : "recording", item };
  }

  K.pageMenu = { attach, sections };
  // On the decided pages, the variant adds the button to the bar. menu.html draws each variant itself.
  const page = K.page;
  K.page = (options) => {
    const made = page(options);
    const thing = document.documentElement.dataset.page === "menu" ? null : pageThing();
    if (thing) attach(made.nav, thing.kind, thing.item);
    return made;
  };
})();
