// The filter sheet that Search and the Library edit sheet share.
// Filters.make({ conds, kind, count, scope, onChange }) returns a controller. Its body() gives the parts of the
// sheet: the conditions as one paragraph of chips, the kind picker with the find field, and the term list.
// A condition is a list of terms joined by "or"; conditions are joined by "and". A term reads "kind:Name".
// The page owns the meaning of a result: count(conds) returns the number of results that the conditions leave,
// and scope() returns the set of recordings that the page may reach, or null for every recording.
window.Filters = (() => {
  const { el, ICON } = K;
  const KINDS = {
    genre: "Genres",
    composer: "Composers",
    conductor: "Conductors",
    performer: "Performers",
    role: "Roles",
  };
  const ONE = { genre: "Genre", composer: "Composer", conductor: "Conductor", performer: "Performer", role: "Role" };

  // ---------- Matching: diacritics fold away; "Op. 67" meets "op67", "K. 626" meets "KV 626". ----------
  const fold = (s) =>
    (s || "")
      .normalize("NFD")
      .replace(/[̀-ͯ]/g, "")
      .toLowerCase()
      .replace(/ø/g, "o")
      .replace(/ł/g, "l")
      .replace(/ß/g, "ss")
      .replace(/æ/g, "ae")
      .replace(/[^a-z0-9]+/g, " ")
      .trim();
  const CATALOGUE = /^(op|k|kv|bwv|d|hob|rv|hwv|kk|swv|wq|sz|l)$/;
  function words(s) {
    const w = fold(s).split(" ").filter(Boolean);
    const out = new Set(w);
    for (let i = 0; i + 1 < w.length; i++)
      if (CATALOGUE.test(w[i]) && /^\d/.test(w[i + 1])) {
        out.add(w[i] + w[i + 1]);
        if (w[i] === "k") out.add("kv" + w[i + 1]);
        if (w[i] === "kv") out.add("k" + w[i + 1]);
      }
    return [...out];
  }
  function queryTokens(q) {
    const w = fold(q).split(" ").filter(Boolean);
    const out = [];
    for (let i = 0; i < w.length; i++) {
      if (CATALOGUE.test(w[i]) && w[i + 1] && /^\d/.test(w[i + 1])) {
        out.push(w[i] + w[i + 1]);
        i++;
      } else out.push(w[i]);
    }
    return out;
  }
  const matches = (tokens, hay) => tokens.every((t) => hay.some((h) => h.startsWith(t)));

  // ---------- The index: every recording with its terms, read from the songs. ----------
  const label = (t) => t.slice(t.indexOf(":") + 1);
  const kindOf = (t) => t.slice(0, t.indexOf(":"));
  let built = null;
  function index() {
    if (built) return built;
    const spellings = new Map();
    for (const r of K.M.recordings.values())
      for (const song of r.songs)
        for (const c of song.contributors || [])
          if (c.role === "performer" && c.subRole) {
            const key = c.subRole.toLocaleLowerCase("en");
            if (!spellings.has(key)) spellings.set(key, new Map());
            const variants = spellings.get(key);
            variants.set(c.subRole, (variants.get(c.subRole) || 0) + 1);
          }
    const roleNames = new Map(
      [...spellings].map(([key, variants]) => [key, [...variants].sort((a, b) => b[1] - a[1])[0][0]]),
    );
    const recs = [...K.M.recordings.values()].map((r) => {
      const terms = new Set(r.genres.map((g) => "genre:" + g));
      for (const s of r.songs)
        for (const c of s.contributors || []) {
          if (c.role === "performer" && c.subRole)
            terms.add("role:" + roleNames.get(c.subRole.toLocaleLowerCase("en")));
          terms.add(
            `${c.role === "composer" ? "composer" : c.role === "conductor" ? "conductor" : "performer"}:${c.artist.name}`,
          );
        }
      if (r.composer) terms.add("composer:" + r.composer);
      r.performers
        .filter((p) => p.role === "artist")
        .forEach((p) => {
          terms.add("performer:" + p.name);
        });
      return { r, terms };
    });
    const allTerms = new Map();
    for (const { terms } of recs) for (const t of terms) allTerms.set(t, (allTerms.get(t) || 0) + 1);
    // A genre that every recording carries filters nothing, so the picker hides it (as on the composer page).
    // Weak tags leave some recordings without a genre, so the test counts only the recordings that carry one.
    const withGenre = recs.filter((x) => x.r.genres.length).length;
    for (const [t, n] of allTerms) if (t.startsWith("genre:") && n === withGenre) allTerms.delete(t);
    built = { recs, allTerms, byRec: new Map(recs.map((x) => [x.r, x])) };
    return built;
  }

  const passes = (x, list) => list.every((c) => c.some((t) => x.terms.has(t)));
  // A page row passes when one of its recordings meets the conditions.
  const hit = (recordings, list) => {
    const { byRec } = index();
    return recordings.some((r) => byRec.has(r) && passes(byRec.get(r), list));
  };
  // The conditions read as they work: terms of one condition joined with "or", conditions with "and".
  const line = (list) => list.map((c) => c.map((t) => `${ONE[kindOf(t)]} ${label(t)}`).join(" or ")).join(" and ");
  // The same without the kind words, for a subtitle.
  const short = (list) => list.map((c) => c.map(label).join(" or ")).join(" and ");

  function make({
    conds = [],
    kind = "composer",
    count,
    scope = () => null,
    onChange = () => {},
    text = (value) => value,
    formatNumber = (value) => String(value),
  }) {
    const { recs, allTerms } = index();
    const fx = { conds, marked: null, kind, narrowQ: "", clearNarrow: () => {}, condsBox: null, redraw: () => {} };

    // A chip is one button for assistive technology: it names the term and "remove", and the x belongs to it.
    // It is a span with role="button", because a native button cannot break across lines.
    const press = (run) => ({
      role: "button",
      tabindex: "0",
      onclick: run,
      onkeydown: (e) => {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault();
          run();
        }
      },
    });
    function chip(t, ci) {
      return el(
        "span",
        {
          class: "tchip t-subheadline",
          "aria-label": `${label(t)}, ${text("remove")}`,
          ...press(() => removeTerm(ci, t)),
        },
        label(t),
        el("span", { class: "x", "aria-hidden": "true" }, "×"),
      );
    }
    function removeTerm(ci, t) {
      fx.conds[ci] = fx.conds[ci].filter((x) => x !== t);
      if (!fx.conds[ci].length) {
        fx.conds.splice(ci, 1);
        if (fx.marked === ci) fx.marked = null;
        else if (fx.marked > ci) fx.marked--;
      }
      onChange();
    }
    // The conditions as one paragraph: "or" inside a condition, "and" between conditions.
    // Each condition ends with its "+ or" button, which marks it so the next term joins it.
    function condParagraph() {
      const box = el("div", { class: "cond", role: "group", "aria-label": text("Conditions") });
      fx.conds.forEach((c, i) => {
        if (i) box.append(el("span", { class: "w and t-subheadline" }, text("and")), " ");
        c.forEach((t, j) => {
          if (j) box.append(el("span", { class: "w t-subheadline" }, text("or")), " ");
          box.append(chip(t, i), " ");
        });
        box.append(
          el(
            "span",
            {
              class: "plus t-subheadline" + (fx.marked === i ? " on" : ""),
              "aria-label": text("Add an or term"),
              "aria-pressed": String(fx.marked === i),
              ...press(() => {
                fx.marked = fx.marked === i ? null : i;
                onChange();
              }),
            },
            text("+ or"),
          ),
          " ",
        );
      });
      return box;
    }
    // A term in use shows a check mark, and a second tap removes it. A free term joins the marked
    // condition with "or", else it starts a condition with "and".
    function termRows(into) {
      const q = queryTokens(fx.narrowQ);
      const list = [...allTerms.keys()]
        .filter((t) => kindOf(t) === fx.kind && (!q.length || matches(q, words(label(t)))))
        .map((t) => ({ t, at: fx.conds.findIndex((c) => c.includes(t)) }))
        .filter(({ t, at }) => {
          if (at >= 0 || into == null) return true;
          const f = scope();
          const others = fx.conds.filter((_, i) => i !== into);
          return recs.some((x) => (!f || f.has(x.r)) && passes(x, others) && x.terms.has(t));
        })
        .map(({ t, at }) => ({
          t,
          at,
          n: count(
            at >= 0
              ? fx.conds
              : into != null
                ? fx.conds.map((c, i) => (i === into ? [...c, t] : c))
                : [...fx.conds, [t]],
          ),
        }))
        .filter((x) => x.n > 0 || x.at >= 0)
        .sort((x, y) => Number(y.at >= 0) - Number(x.at >= 0) || y.n - x.n || label(x.t).localeCompare(label(y.t)));
      if (!list.length)
        return [el("div", { class: "row t-subheadline secondary" }, text("No term of this kind is left."))];
      // A pick clears the narrowing text, so the next term can be typed at once.
      return list.map(({ t, at, n }) =>
        el(
          "button",
          {
            class: "row term",
            "aria-pressed": String(at >= 0),
            onclick: () => {
              fx.clearNarrow();
              if (at >= 0) return removeTerm(at, t);
              if (into != null) fx.conds[into].push(t);
              else {
                fx.conds.push([t]);
                fx.marked = null;
              }
              onChange();
            },
          },
          el("div", { class: "main t-body" }, label(t)),
          el(
            "div",
            { class: "trail" },
            at >= 0 ? el("span", { class: "check", html: ICON.check }) : null,
            el("span", { class: "what t-subheadline nums" }, formatNumber(n)),
          ),
        ),
      );
    }
    function kindSeg(onKind) {
      const seg = el("div", { class: "seg" });
      seg.draw = () =>
        seg.replaceChildren(
          ...Object.keys(KINDS).map((k) =>
            el(
              "button",
              {
                class: "t-footnote" + (k === fx.kind ? " on" : ""),
                onclick: () => {
                  fx.kind = k;
                  seg.draw();
                  onKind();
                },
              },
              text(KINDS[k]),
            ),
          ),
        );
      seg.draw();
      return seg;
    }
    function narrowField(onNarrow) {
      const i = el("input", {
        type: "search",
        enterkeyhint: "done",
        autocomplete: "off",
        autocorrect: "off",
        spellcheck: "false",
      });
      const setPh = () => (i.placeholder = text("Find in " + KINDS[fx.kind].toLowerCase()));
      setPh();
      i.addEventListener("input", () => {
        fx.narrowQ = i.value;
        onNarrow();
      });
      i.addEventListener("keydown", (e) => {
        if (e.key === "Enter") i.blur();
      });
      const box = el("label", { class: "narrow" }, el("span", { html: ICON.search }), i);
      box.reset = () => {
        i.value = "";
        fx.narrowQ = "";
        setPh();
      };
      return box;
    }

    // The parts of the sheet body, for Frame.make or Frame.set.
    fx.body = () => {
      const condsBox = el("div");
      const list = el("div", { class: "list" });
      fx.redraw = () => list.replaceChildren(...termRows(fx.marked));
      const narrow = narrowField(fx.redraw);
      fx.clearNarrow = narrow.reset;
      const seg = kindSeg(() => {
        narrow.reset();
        fx.redraw();
      });
      fx.condsBox = condsBox;
      return [condsBox, el("div", { class: "hs-stick" }, seg, narrow), list];
    };
    // Redraws the paragraph and the term list after the conditions changed.
    fx.draw = () => {
      if (!fx.condsBox) return;
      const next = condParagraph();
      fx.condsBox.replaceWith(next);
      fx.condsBox = next;
      fx.redraw();
    };
    return fx;
  }

  return { KINDS, ONE, fold, words, queryTokens, matches, index, label, kindOf, passes, hit, line, short, make };
})();
