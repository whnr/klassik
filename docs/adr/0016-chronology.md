# 0016. The Chronology: a chart of one composer among their contemporaries

Date: 2026-11-04. Decided by Flo after four prototype rounds and one grilling. Bead: sz-rs30.1.74.6. Replaces the timeline rules of [0011](0011-enrichment.md): undated works no longer sit inside the composer's lifetime. The work card and the sideways drag are replaced by [0022](0022-chronology-taps.md). The rule for contemporaries is replaced by [0026](0026-contemporaries-by-active-years.md).

## Context

Flo rejected a long list. Round 1 tried lanes, a lens and levels; levels came closest. Later rounds showed that names on lines overlap, that taps on close lines pick the wrong composer, and that a full library holds about 230 works by Chopin, many without a date. The Chronology is for discovery in the listener's own library. Context from what plays is the main way in.

## Decision

- The Chronology has two levels: an overview of all composers, then one composer. The overview shows each composer as a line and the periods as bands. A tap on a line opens that composer.
- The Chronology opens on the composer of what plays, with that work marked. With nothing playing, it opens where the listener left it.
- Years run down the screen. The composer's life fits one screen.
- The focus composer's works show as dots on their line and as rows in a column on the right. A row shows the year and the title. When the rows do not fit, one row stands for a year or a span of years, with a count. A tap on that row lists its works.
- Works without a date are one row at the end of the line, with a count. A tap lists them.
- Contemporaries are composers with works in the library inside the focus composer's active years, 10 years before and after. Each shows as a plain line without a name, with a dot for each held work.
- Active years start at the Wikidata work period start (P2031). The line is bright from that year and dim before it. Without P2031 the line has no shading.
- A sideways drag anywhere on the chart moves to another composer. The width of the screen maps onto the composers in birth order. A label names the composer under the finger. The move glides: lines slide and the years rescale. It never zooms.
- A tap in the chart only picks a work of the focus composer: on its row, on its dot, or beside the focus line.
- A tap on a work opens a card with Play and Open Work. Play plays the reference recording (ADR 0013).

## Consequences

- The view needs composer life dates (P569, P570) and P2031 from one Wikidata call for each composer, and a composition year for each work (outside data, sz-rs30.1.75).
- The code type `Timeline` draws the Chronology. CONTEXT.md gives "timeline" to the player bar, so the tracer renames it.
- The tracer removes the year field with the number pad (digest T05) and the midpoint placement of undated works.
- Without P2031, the contemporary window is the composer's whole life, without a buffer. Flo rejected the life ±10 years.
- Works that the library lacks can come from Wikidata later, as an option that is off by default.
