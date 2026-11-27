// The listening notes of a playing row, shared by the player and the notes page. The texts come in English and
// German: `?lang=de` picks German, as the iPhone's per-app language does.
(() => {
  const { el } = K;
  const lang = new URLSearchParams(location.search).get("lang") === "de" ? "de" : "en";
  const TEXT = {
    en: {
      add: "Add a note here",
      write: "Write the note",
      start: "Start here",
      end: "End here",
      cancel: "Cancel",
      save: "Save",
      deleted: "Note deleted",
      undo: "Undo",
    },
    de: {
      add: "Hier eine Notiz hinzufügen",
      write: "Notiz schreiben",
      start: "Hier beginnen",
      end: "Hier enden",
      cancel: "Abbrechen",
      save: "Speichern",
      deleted: "Notiz gelöscht",
      undo: "Rückgängig",
    },
  };
  const t = (key) => TEXT[lang][key];

  // A note is { at, span?, text }. The time reads "1:32" for a moment and "1:32–2:12" for a span.
  const when = (n) => K.time(n.at) + (n.span ? `–${K.time(n.at + n.span)}` : "");

  // A mark sets one end to the playing time. The earlier of the two is the start, so a scrub back still gives a span.
  function mark(n, which, now) {
    const other = which === "start" ? (n.span ? n.at + n.span : null) : n.at;
    const from = Math.min(now, other ?? now);
    const to = Math.max(now, other ?? now);
    n.at = from;
    n.span = to - from || undefined;
  }

  // A note in the list: its time plays from there, its text opens the note for editing.
  function row(n, { play, edit }) {
    return el(
      "div",
      { class: "note t-subheadline" },
      el("button", { class: "at nums", onclick: play }, when(n)),
      el("button", { class: "text", onclick: edit }, n.text),
    );
  }

  // The open note, for a new note and an edited note alike. Start here shows only when a note is edited in the
  // playing row, and End here wherever a time can be set.
  function editor(n, { isNew, canMark, now, onSave, onCancel, onText }) {
    const at = el("span", { class: "at nums t-subheadline" }, when(n));
    const input = el("textarea", {
      class: "note-input t-body",
      placeholder: t("write"),
      enterkeyhint: "done",
      rows: 1,
    });
    input.value = n.text;
    input.addEventListener("input", () => {
      n.text = input.value;
      if (onText) onText();
    });
    input.addEventListener("keydown", (e) => {
      if (e.key === "Enter") {
        e.preventDefault();
        onSave();
      }
    });
    const marker = (which) =>
      el(
        "button",
        {
          class: "t-subheadline",
          onclick: () => {
            mark(n, which, Math.floor(now()));
            at.textContent = when(n);
          },
        },
        t(which),
      );
    const marks = [];
    if (canMark && !isNew) marks.push(marker("start"));
    if (canMark) marks.push(marker("end"));
    return {
      input,
      node: el(
        "div",
        { class: "note-edit" },
        el("div", { class: "note-line" }, at, input),
        el(
          "div",
          { class: "note-actions" },
          el("div", { class: "group" }, ...marks),
          el(
            "div",
            { class: "group" },
            el("button", { class: "cancel-note t-subheadline", onclick: onCancel }, t("cancel")),
            el("button", { class: "save-note t-subheadline", onclick: onSave }, t("save")),
          ),
        ),
      ),
    };
  }

  function addButton(onclick) {
    return el("button", { class: "add-note t-subheadline", onclick }, t("add"));
  }

  // The toast that follows a delete. Text and Undo share one size.
  function toast(onUndo) {
    return el(
      "div",
      { class: "undo-toast" },
      el(
        "div",
        { class: "box t-subheadline", role: "status" },
        el("span", { class: "message" }, t("deleted")),
        el("button", { class: "undo", onclick: onUndo }, t("undo")),
      ),
    );
  }

  K.notes = { lang, t, when, row, editor, addButton, toast };
})();
