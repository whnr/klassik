// Fermata board (sz-rs30.1.83.18): ten shapes and three looks for the mark that is not set.
// Each shape is one filled path in a 24 × 16 box, so the three looks share one drawing.
// The board picks a shape and a look; as variant "fermata" the pick replaces K.fermata on every page.
"use strict";

const KF = (() => {
  const SHAPES = [
    { id: "now", name: "Now", note: "The drawing on the specimen today, for comparison.",
      d: "M1.5 14.5A10.5 10.5 0 0 1 22.5 14.5H20.6A8.6 7.2 0 0 0 3.4 14.5Z M14.1 12.4A2.1 2.1 0 1 1 9.9 12.4A2.1 2.1 0 1 1 14.1 12.4Z" },
    { id: "lunette", name: "Lunette", note: "A crescent: heavy at the crown, hairline at the feet, like an engraved fermata.",
      d: "M1.5 14.5A10.5 10.5 0 0 1 22.5 14.5A0.2 0.2 0 0 1 22.1 14.5A10.1 6.4 0 0 0 1.9 14.5A0.2 0.2 0 0 1 1.5 14.5Z M14.2 12.2A2.2 2.2 0 1 1 9.8 12.2A2.2 2.2 0 1 1 14.2 12.2Z" },
    { id: "nib", name: "Feder", note: "A broad-nib stroke: the weight sits left of the crown, the dot leans to it.",
      d: "M1.5 14.5A10.5 10.5 0 0 1 22.5 14.5H22.3A8.9 7 0 0 0 4.5 14.5Z M13.3 12.2A2.1 2.1 0 1 1 9.1 12.2A2.1 2.1 0 1 1 13.3 12.2Z" },
    { id: "dome", name: "Kuppel", note: "A solid half disc with the dot cut out. Reads as a badge at row size.",
      d: "M2 14.5A10 10 0 0 1 22 14.5Z M14.3 10.6A2.3 2.3 0 1 0 9.7 10.6A2.3 2.3 0 1 0 14.3 10.6Z" },
    { id: "ball", name: "Kugel", rule: "nonzero", note: "A monoline arc with ball ends, the dot as a third ball. Round everywhere.",
      d: "M2 14A10 10 0 0 1 22 14H20A8 8 0 0 0 4 14Z M4.6 14.2A1.6 1.6 0 1 1 1.4 14.2A1.6 1.6 0 1 1 4.6 14.2Z M22.6 14.2A1.6 1.6 0 1 1 19.4 14.2A1.6 1.6 0 1 1 22.6 14.2Z M14.1 12.2A2.1 2.1 0 1 1 9.9 12.2A2.1 2.1 0 1 1 14.1 12.2Z" },
    { id: "embrace", name: "Umarmung", note: "The arc runs on past the dot and closes round it: a held note in two arms.",
      d: "M6.255 14.32A7.5 7.5 0 1 1 17.745 14.32A0.95 0.95 0 0 1 16.29 13.1A5.6 5.6 0 1 0 7.71 13.1A0.95 0.95 0 0 1 6.255 14.32Z M14.2 9.5A2.2 2.2 0 1 1 9.8 9.5A2.2 2.2 0 1 1 14.2 9.5Z" },
    { id: "lunga", name: "Lunga", note: "Two arcs, the score's sign for a very long hold. Hold this one longer.",
      d: "M1.5 14.5A10.5 10.5 0 0 1 22.5 14.5H21.1A9.1 9.1 0 0 0 2.9 14.5Z M4.4 14.5A7.6 7.6 0 0 1 19.6 14.5H18.2A6.2 6.2 0 0 0 5.8 14.5Z M13.9 12.6A1.9 1.9 0 1 1 10.1 12.6A1.9 1.9 0 1 1 13.9 12.6Z" },
    { id: "square", name: "Lang", note: "The square fermata of modern scores, with soft corners. Sits like a door.",
      d: "M2 14.5V7.5A3.5 3.5 0 0 1 5.5 4H18.5A3.5 3.5 0 0 1 22 7.5V14.5H19.8V7.5A1.3 1.3 0 0 0 18.5 6.2H5.5A1.3 1.3 0 0 0 4.2 7.5V14.5Z M14.1 11.6A2.1 2.1 0 1 1 9.9 11.6A2.1 2.1 0 1 1 14.1 11.6Z" },
    { id: "triangle", name: "Kurz", note: "The triangular fermata of modern scores: a tent over the note, rounded apex.",
      d: "M1.5 14.5L10.9 4.6Q12 3.4 13.1 4.6L22.5 14.5H19.6L12 6.6L4.4 14.5Z M14.1 12.2A2.1 2.1 0 1 1 9.9 12.2A2.1 2.1 0 1 1 14.1 12.2Z" },
    { id: "ogive", name: "Spitzbogen", note: "A pointed Gothic arch over the dot. A church window for the reference recording.",
      d: "M2 14.5A12 12 0 0 1 12 2.67A12 12 0 0 1 22 14.5H19.9A9.9 9.9 0 0 0 12 4.8A9.9 9.9 0 0 0 4.1 14.5Z M14 12A2 2 0 1 1 10 12A2 2 0 1 1 14 12Z" },
    { id: "seal", name: "Siegel", note: "A round seal with the fermata cut out of it. A stamp of approval.",
      d: "M4.4 8A7.6 7.6 0 1 1 19.6 8A7.6 7.6 0 1 1 4.4 8Z M6.6 10.6A5.4 5.4 0 0 1 17.4 10.6H16A4 3.6 0 0 0 8 10.6Z M13.3 9.6A1.3 1.3 0 1 1 10.7 9.6A1.3 1.3 0 1 1 13.3 9.6Z" },
  ];

  const STYLES = [
    { id: "grey", name: "Grey", note: "Not set: the same solid shape in secondary grey. Set: the tint." },
    { id: "round", name: "Round line", note: "Not set: a line round the outside, round joins, SF regular weight." },
    { id: "ghost", name: "Ghost", note: "Not set: the solid shape in a faint tint. Setting it only adds colour." },
  ];

  let serial = 0;

  // The round line strokes the shape and masks out its inside, so overlapping parts give one outer contour.
  function svg(shapeId, on, styleId) {
    const shape = SHAPES.find((s) => s.id === shapeId) || SHAPES[1];
    // Cut-outs need even-odd; overlapping parts need non-zero.
    const rule = `fill-rule="${shape.rule || "evenodd"}"`;
    const box = 'viewBox="-0.8 -0.8 25.6 17.6" width="100%" height="100%"';
    if (on) return `<svg ${box}><path d="${shape.d}" ${rule} fill="var(--color-favourite, var(--color-tint))"/></svg>`;
    if (styleId === "round") {
      const id = "kf" + ++serial;
      return `<svg ${box}><mask id="${id}" maskUnits="userSpaceOnUse" x="-1" y="-1" width="26" height="18">` +
        `<path d="${shape.d}" ${rule} fill="none" stroke="#fff" stroke-width="2.7" stroke-linejoin="round"/>` +
        `<path d="${shape.d}" ${rule} fill="#000"/></mask>` +
        `<rect x="-1" y="-1" width="26" height="18" fill="var(--color-text-secondary)" mask="url(#${id})"/></svg>`;
    }
    const fill = styleId === "ghost" ? "color-mix(in srgb, var(--color-favourite, var(--color-tint)) 30%, transparent)" : "var(--color-text-secondary)";
    return `<svg ${box}><path d="${shape.d}" ${rule} fill="${fill}"/></svg>`;
  }

  function pick() {
    const p = (window.K && K.store("fermata")) || {};
    return { shape: p.shape || "lunette", style: p.style || "grey" };
  }

  function mark(on, small = false, shapeId, styleId) {
    const p = pick();
    const span = document.createElement("span");
    span.className = "fermata" + (small ? " small" : "");
    span.setAttribute("role", "img");
    span.setAttribute("aria-label", on ? "Favourite" : "Not a favourite");
    span.innerHTML = svg(shapeId || p.shape, on, styleId || p.style);
    return span;
  }

  if (window.K) K.fermata = (on, small) => mark(on, small);
  return { SHAPES, STYLES, svg, mark, pick };
})();
