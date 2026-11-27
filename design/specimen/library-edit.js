// The Library edit sheet, built on the shared sheet frame over the live tab.
// LibraryEdit.open({ rows, tab, onChange, onClose, start }) returns { select, close }.
// Every change edits `rows` in place and redraws the tab at once. Done closes the sheet.
// Levels: the list of rows, Add row, the settings of one row, a choice, and the filter sheet of Search.
window.LibraryEdit = (() => {
  const { el, ICON } = K;

  const HANDLE =
    '<svg width="18" height="12" viewBox="0 0 18 12" aria-hidden="true"><path d="M1 1h16M1 6h16M1 11h16" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/></svg>';
  // The previews of Add row. They draw the shape of a row, never real content.
  const dot = (cx, cy, r, o) => `<circle cx="${cx}" cy="${cy}" r="${r}" fill="currentColor" opacity="${o}"/>`;
  const bar = (x, y, w, o, h = 2.5) =>
    `<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="1" fill="currentColor" opacity="${o}"/>`;
  const box = (x, y, s, o) =>
    `<rect x="${x}" y="${y}" width="${s}" height="${s}" rx="2" fill="currentColor" opacity="${o}"/>`;
  const svg = (inner) => `<svg width="60" height="36" viewBox="0 0 60 36" aria-hidden="true">${inner}</svg>`;
  const PREVIEW = {
    pick: svg(bar(10, 10, 40, 1, 3) + bar(10, 17, 30, 0.6, 3) + bar(10, 24, 36, 0.4, 3)),
    faces: svg([11, 24, 37, 50].map((x) => dot(x, 15, 6, 0.7) + bar(x - 5, 25, 10, 0.4)).join("")),
    covers: svg([4, 22, 40].map((x) => box(x, 4, 16, 0.7) + bar(x, 24, 12, 0.4)).join("")),
    mixed: svg(
      dot(11, 12, 7, 0.7) + box(23, 5, 14, 0.7) + box(41, 5, 14, 0.7) + bar(5, 24, 12, 0.4) + bar(23, 24, 12, 0.4),
    ),
    links: svg(
      [4, 22, 40]
        .map(
          (x) =>
            `<rect x="${x}" y="8" width="16" height="20" rx="3" fill="currentColor" opacity="0.18"/>` +
            bar(x + 3, 12, 8, 0.7, 3) +
            bar(x + 3, 19, 10, 0.4),
        )
        .join(""),
    ),
  };
  const KIND_LINES = {
    pick: ["One recording a day, as a sentence", "pick"],
    composers: ["Faces, with their number of works", "faces"],
    performers: ["Faces, with their number of recordings", "faces"],
    works: ["Covers, with their composer", "covers"],
    recordings: ["Covers, with their lead performer", "covers"],
    albums: ["Covers, newest first", "covers"],
    favourites: ["Faces and covers, mixed", "mixed"],
    added: ["Covers of what you added last", "covers"],
    heard: ["Covers of what you played last", "covers"],
    saved: ["Recordings that a saved search finds", "covers"],
    links: ["Tiles with counts, a way into each page", "links"],
  };

  function open({ rows, tab, onChange = null, onClose = null, start = null }) {
    let sel = null;
    // The level on show: list, add, row (id), choice (id, field) or filter (id).
    let level = { t: "list" };
    const byId = (id) => rows.find((r) => r.id === id);
    // A change can make rows above the edited row taller or shorter. The page scrolls the selected row back to the
    // top, as on select. Without a selection the changed row comes into view.
    const changed = (id = null) => {
      tab.update(rows);
      if (sel) tab.select(sel, { scroll: true });
      else if (id) tab.reveal(id);
      onChange?.(rows);
    };
    const go = (next) => {
      level = next;
      show();
    };
    const toList = () => go({ t: "list" });

    const frame = Frame.make({ title: "Edit Library" });
    frame.box.classList.add("le-sheet");

    // ---------- Level 1: the rows ----------
    function listBody() {
      const add = el(
        "button",
        { class: "row le-add t-body", type: "button", onclick: () => go({ t: "add" }) },
        "Add row",
      );
      const list = el("div", { class: "list" }, ...rows.map(line));
      sortable(
        list,
        ".le-line",
        (ids) => {
          rows.splice(0, rows.length, ...ids.map(byId));
          changed();
        },
        (id) => {
          // The selected row returns to the top, as on select. Without a selection the moved row comes into view.
          if (sel) tab.select(sel, { scroll: true });
          else tab.reveal(id);
        },
      );
      return [
        el("section", { class: "section" }, el("div", { class: "list" }, add)),
        el("section", { class: "section" }, list),
      ];
    }

    // A line: title, subtitle, drag handle. A swipe to the left shows Delete.
    function line(row) {
      const W = 88;
      const empty = Library.empty(row);
      const front = el("div", { class: "le-front" + (sel === row.id ? " cur" : "") });
      const del = el(
        "button",
        { class: "le-del t-body", type: "button", tabindex: "-1", onclick: () => remove(row) },
        "Delete",
      );
      const node = el("div", { class: "le-line", "data-id": row.id }, del, front);
      front.append(
        el(
          "div",
          { class: "le-main" },
          el("div", { class: "le-title t-body" }, Library.title(row)),
          el("div", { class: "le-sub t-footnote secondary" }, empty ? "Nothing to show yet" : Library.facts(row)),
        ),
        el("span", { class: "le-handle", "aria-label": "Reorder", role: "img", html: HANDLE }),
      );
      let startX = null;
      let startY = 0;
      let base = 0;
      let offset = 0;
      let mode = null;
      let moved = false;
      let shown = false;
      const set = (v, animate) => {
        front.classList.toggle("drag", !animate);
        front.style.transform = `translateX(${v}px)`;
        node.classList.toggle("swiped", v < 0);
        // A hidden Delete takes no focus.
        del.tabIndex = v < 0 ? 0 : -1;
        offset = v;
      };
      front.addEventListener("pointerdown", (e) => {
        if (e.target.closest(".le-handle")) return;
        for (const other of node.parentElement.querySelectorAll(".le-line")) if (other !== node) other._close?.();
        startX = e.clientX;
        startY = e.clientY;
        base = shown ? -W : 0;
        mode = null;
        moved = false;
      });
      front.addEventListener("pointermove", (e) => {
        if (startX == null) return;
        const dx = e.clientX - startX;
        const dy = e.clientY - startY;
        if (!mode && Math.abs(dx) > 6 && Math.abs(dx) > Math.abs(dy)) {
          mode = "h";
          moved = true;
          front.setPointerCapture(e.pointerId);
        }
        if (mode === "h") set(Math.max(-W, Math.min(0, base + dx)), false);
      });
      const end = () => {
        if (startX == null) return;
        startX = null;
        if (mode === "h") {
          shown = offset < -W / 2;
          set(shown ? -W : 0, true);
        }
        mode = null;
      };
      front.addEventListener("pointerup", end);
      front.addEventListener("pointercancel", end);
      node._close = () => {
        shown = false;
        set(0, true);
      };
      front.addEventListener("click", (e) => {
        if (e.target.closest(".le-handle")) return;
        if (moved) {
          moved = false;
          return;
        }
        if (shown) return node._close();
        select(row.id);
      });
      return node;
    }
    function remove(row) {
      rows.splice(rows.indexOf(row), 1);
      if (sel === row.id) {
        sel = null;
        tab.select(null);
      }
      changed();
      show();
    }

    // Drag a handle: the list and the tab both follow the finger.
    function sortable(container, item, onSwap, onDrop = null) {
      container.addEventListener("pointerdown", (e) => {
        const handle = e.target.closest(".le-handle");
        if (!handle) return;
        const node = handle.closest(item);
        e.preventDefault();
        handle.setPointerCapture(e.pointerId);
        let startY = e.clientY;
        let dragged = false;
        node.classList.add("moving");
        const ids = () => [...container.querySelectorAll(item)].map((n) => n.dataset.id);
        const move = (ev) => {
          let dy = ev.clientY - startY;
          const prev = node.previousElementSibling;
          const next = node.nextElementSibling;
          if (next && dy > next.offsetHeight / 2) {
            const size = next.offsetHeight;
            next.after(node);
            startY += size;
            dy -= size;
            dragged = true;
            onSwap(ids());
          } else if (prev && dy < -prev.offsetHeight / 2) {
            const size = prev.offsetHeight;
            prev.before(node);
            startY -= size;
            dy += size;
            dragged = true;
            onSwap(ids());
          }
          node.style.transform = `translateY(${dy}px)`;
        };
        const release = () => {
          node.style.transform = "";
          node.classList.remove("moving");
          handle.removeEventListener("pointermove", move);
          if (dragged) onDrop?.(node.dataset.id);
        };
        handle.addEventListener("pointermove", move);
        handle.addEventListener("pointerup", release, { once: true });
        handle.addEventListener("pointercancel", release, { once: true });
      });
    }

    // ---------- Add row ----------
    function addBody() {
      const hasPick = rows.some((r) => r.kind === "pick");
      return K.form.group(
        null,
        Object.entries(Library.KINDS).map(([kind, { label }]) => {
          const [text, shape] = KIND_LINES[kind];
          const off = kind === "pick" && hasPick;
          return el(
            "button",
            { class: "row le-kind" + (off ? " off" : ""), type: "button", disabled: off, onclick: () => add(kind) },
            el("span", { class: "le-preview", html: PREVIEW[shape] }),
            el(
              "span",
              { class: "main" },
              el("div", { class: "t-body" }, label),
              el("div", { class: "t-footnote secondary" }, off ? "Already on the tab" : text),
            ),
          );
        }),
      );
    }
    // The new row goes below the selected row, or to the top of the tab when none is selected.
    function add(kind) {
      const row = Library.make(kind);
      const at = sel ? rows.findIndex((r) => r.id === sel) + 1 : 0;
      rows.splice(at, 0, row);
      changed();
      select(row.id);
    }

    // ---------- Level 2: the settings of one row ----------
    const FIELDS = {
      source: { label: "Source", options: Library.sourceOptions, value: Library.sourceValue },
      sort: { label: "Sort", options: Library.sortOptions, value: (r) => r.sort },
      form: { label: "Form", options: Library.formOptions, value: (r) => r.form },
      count: { label: "Count", options: Library.countOptions, value: (r) => String(r.count) },
    };
    const trail = (text, chevron) =>
      el(
        "span",
        { class: "trail le-trail t-body" },
        el("span", {}, text),
        chevron ? el("span", { html: ICON.chevron }) : null,
      );
    function settingLine(row, field) {
      const f = FIELDS[field];
      const options = f.options(row);
      const only = Object.keys(options).length < 2;
      return el(
        "button",
        {
          class: "row t-body",
          type: "button",
          disabled: only,
          onclick: () => go({ t: "choice", id: row.id, field }),
        },
        el("span", { class: "main" }, f.label),
        trail(options[f.value(row)] ?? "", !only),
      );
    }
    function filterLine(row) {
      const terms = row.conds.flat();
      return el(
        "button",
        { class: "row t-body", type: "button", onclick: () => go({ t: "filter", id: row.id }) },
        el("span", { class: "main" }, "Filter"),
        trail(
          terms.length === 0 ? "None" : terms.length === 1 ? Filters.label(terms[0]) : `${terms.length} terms`,
          true,
        ),
      );
    }
    function rowBody(row) {
      if (row.kind === "links") return linksBody(row);
      if (row.kind === "pick")
        return K.form.group(
          null,
          [settingLine(row, "source")],
          "One complete recording or album a day. The title and the cover open its page. Nothing starts playback.",
        );
      return K.form.group(
        null,
        [
          settingLine(row, "source"),
          filterLine(row),
          settingLine(row, "sort"),
          settingLine(row, "form"),
          settingLine(row, "count"),
        ],
        `The title follows these settings: ${Library.title(row)}.`,
      );
    }
    // Level 3: one choice, checked, then back to the row.
    function choiceBody(row, field) {
      const f = FIELDS[field];
      return K.form.group(
        null,
        Object.entries(f.options(row)).map(([value, text]) =>
          el(
            "button",
            {
              class: "row t-body",
              type: "button",
              onclick: () => {
                Library.apply(row, field, value);
                changed(row.id);
                go({ t: "row", id: row.id });
              },
            },
            el("span", { class: "le-check", html: f.value(row) === value ? ICON.check : "" }),
            el("span", { class: "main" }, text),
          ),
        ),
      );
    }
    // The links of a link list: check to show, drag to reorder.
    function linksBody(row) {
      const list = el("div", { class: "list" });
      const sync = () => {
        row.links = row.order.filter((k) => row.links.includes(k));
        frame.set({ count: Library.empty(row) ? "Nothing to show yet" : "" });
        changed(row.id);
      };
      const entry = (key) =>
        el(
          "div",
          { class: "le-line", "data-id": key },
          el(
            "div",
            { class: "le-front le-link" },
            el("span", { class: "le-check", "aria-hidden": "true", html: row.links.includes(key) ? ICON.check : "" }),
            el(
              "button",
              {
                class: "le-main t-body",
                type: "button",
                role: "checkbox",
                "aria-checked": String(row.links.includes(key)),
              },
              Library.LINKS[key],
            ),
            el("span", { class: "le-handle", "aria-label": "Reorder", role: "img", html: HANDLE }),
          ),
        );
      list.append(...row.order.map(entry));
      list.addEventListener("click", (e) => {
        const node = e.target.closest(".le-line");
        if (!node || e.target.closest(".le-handle")) return;
        const key = node.dataset.id;
        row.links = row.links.includes(key) ? row.links.filter((k) => k !== key) : [...row.links, key];
        const on = row.links.includes(key);
        node.querySelector(".le-check").innerHTML = on ? ICON.check : "";
        node.querySelector("[role=checkbox]").setAttribute("aria-checked", String(on));
        sync();
      });
      sortable(list, ".le-line", (ids) => {
        row.order = ids;
        sync();
      });
      return el(
        "section",
        { class: "section" },
        list,
        el("p", { class: "section-foot t-footnote" }, "Check a link to show it. Drag the handle to reorder."),
      );
    }

    // ---------- The filter level: the sheet of Search, over the items of the row ----------
    function filterBody(row) {
      let scope = null;
      const conds = row.conds;
      const results = (list) => Library.matching(row, list);
      const fx = Filters.make({
        conds,
        kind: "genre",
        count: results,
        // The reach of the row is computed once for each time the level opens.
        scope: () => (scope ??= Library.scopeOf(row)),
        onChange: () => {
          changed(row.id);
          frame.set({ count: K.count(results(conds), "result") });
          fx.draw();
        },
      });
      frame.set({ count: K.count(results(conds), "result") });
      return { parts: fx.body(), after: () => fx.draw() };
    }

    // ---------- The frame ----------
    function show() {
      const row = level.id ? byId(level.id) : null;
      if (level.id && !row) return toList();
      if (level.t === "list")
        return frame.set({ title: "Edit Library", count: K.count(rows.length, "row"), onBack: null, body: listBody() });
      if (level.t === "add") return frame.set({ title: "Add row", count: "", onBack: toList, body: addBody() });
      if (level.t === "row")
        return frame.set({
          title: Library.title(row),
          count: Library.empty(row) ? "Nothing to show yet" : "",
          onBack: toList,
          body: rowBody(row),
        });
      if (level.t === "choice")
        return frame.set({
          title: FIELDS[level.field].label,
          count: "",
          onBack: () => go({ t: "row", id: row.id }),
          body: choiceBody(row, level.field),
        });
      const filter = filterBody(row);
      frame.set({ title: "Filter", onBack: () => go({ t: "row", id: row.id }), body: filter.parts });
      filter.after();
    }

    // A tap in the list or on the tab selects a row: it is tinted on the tab, scrolled to the top, and opens its settings.
    function select(id) {
      sel = id;
      tab.select(id, { scroll: true });
      go({ t: "row", id });
    }

    tab.selecting(true);
    const handle = Frame.open(frame, {
      onClose: () => {
        tab.selecting(false);
        tab.select(null);
        onClose?.();
      },
    });
    show();
    if (start === "row") {
      const first = rows.find((r) => r.kind === "composers") || rows[0];
      if (first) select(first.id);
    }
    return { select, close: handle.close };
  }

  return { open };
})();
